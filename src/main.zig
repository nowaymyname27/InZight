const std = @import("std");
const vaxis = @import("vaxis");
const heap = std.heap;
const fmt = std.fmt;

const TableRow = struct {
    action: []const u8,
    address: []const u8,
    size: []const u8,
};

const AppEvent = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

// The Worker Thread that creates "Visual Noise"
fn demo_thread(allocator: std.mem.Allocator) void {
    // FIX 1: Use std.Random
    var prng = std.Random.DefaultPrng.init(0);
    const random = prng.random();

    // FIX 2: Use ArrayListUnmanaged
    var list = std.ArrayListUnmanaged([]u8){};
    defer list.deinit(allocator);

    while (true) {
        // Phase 1: Allocate
        var i: usize = 0;
        while (i < 20) : (i += 1) {
            const size = random.intRangeAtMost(usize, 16, 64);
            if (allocator.alloc(u8, size)) |chunk| {
                list.append(allocator, chunk) catch {};
            } else |_| break;

            std.Thread.sleep(100 * std.time.ns_per_ms);
        }

        // Phase 2: Fragment
        var j: usize = 0;
        while (j < 10) : (j += 1) {
            if (list.items.len == 0) break;
            const idx = random.uintLessThan(usize, list.items.len);
            const chunk = list.orderedRemove(idx);
            allocator.free(chunk); // If this still errors, change to `allocator.free(chunk orelse continue);`

            std.Thread.sleep(150 * std.time.ns_per_ms);
        }

        // Phase 3: Drain
        while (list.items.len > 0) {
            const chunk_opt = list.pop();
            if (chunk_opt) |chunk| {
                allocator.free(chunk);
            }
            std.Thread.sleep(50 * std.time.ns_per_ms);
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("TEST FAIL");
    }

    var spy = SpyAllocator.init(gpa.allocator());
    defer spy.deinit();

    const tracked_allocator = spy.allocator();

    const thread = try std.Thread.spawn(.{}, demo_thread, .{tracked_allocator});
    thread.detach();

    var tty_buf: [4096]u8 = undefined;
    var tty = try vaxis.Tty.init(&tty_buf);
    defer tty.deinit();

    var vx = try vaxis.init(gpa.allocator(), .{});
    defer vx.deinit(gpa.allocator(), tty.writer());
    const tty_writer = tty.writer();

    var loop: vaxis.Loop(AppEvent) = .{
        .tty = &tty,
        .vaxis = &vx,
    };
    try loop.init();
    try loop.start();
    defer loop.stop();

    try vx.enterAltScreen(tty.writer());
    try vx.queryTerminal(tty.writer(), 1 * std.time.ns_per_s);

    var frame_arena = heap.ArenaAllocator.init(gpa.allocator());
    defer frame_arena.deinit();

    var scroll_offset: usize = 0;

    while (true) {
        const frame_alloc = frame_arena.allocator();
        defer _ = frame_arena.reset(.retain_capacity);

        const event = loop.nextEvent();
        switch (event) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) break;
                if (key.matches(vaxis.Key.down, .{}) or key.matches('j', .{})) scroll_offset +|= 16;
                if (key.matches(vaxis.Key.up, .{}) or key.matches('k', .{})) scroll_offset -|= 16;
            },
            .winsize => |ws| try vx.resize(gpa.allocator(), tty.writer(), ws),
        }

        const win = vx.window();
        win.clear();

        const Range = struct { start: usize, end: usize };
        // FIX 4: Use ArrayListUnmanaged here too
        var active_ranges = std.ArrayListUnmanaged(Range){};

        {
            spy.mutex.lock();
            defer spy.mutex.unlock();

            for (spy.events.items) |evt| {
                switch (evt) {
                    .alloc => |data| try active_ranges.append(frame_alloc, .{ .start = data.addr, .end = data.addr + data.len }),
                    .free => |data| {
                        for (active_ranges.items, 0..) |r, i| {
                            if (r.start == data.addr) {
                                _ = active_ranges.swapRemove(i);
                                break;
                            }
                        }
                    },
                }
            }
        }

        var base_addr: usize = 0;
        if (active_ranges.items.len > 0) {
            base_addr = active_ranges.items[0].start;
            base_addr = base_addr & ~@as(usize, 0xF);
        }
        base_addr +|= scroll_offset;

        const bytes_per_row = 16;
        var row: usize = 0;

        while (row < win.height) : (row += 1) {
            const row_addr = base_addr + (row * bytes_per_row);

            // FIX 5: Use Child Windows for positioning instead of .row/.col options
            // Create a temporary window just for this row
            const row_win = win.child(.{
                .x_off = 0,
                .y_off = @intCast(row),
                .width = win.width,
                .height = 1,
            });

            // 1. Draw Address
            const addr_str = try fmt.allocPrint(frame_alloc, "0x{x} │ ", .{row_addr});
            _ = row_win.print(&.{.{ .text = addr_str, .style = .{ .fg = .{ .rgb = .{ 100, 100, 100 } } } }}, .{});

            // 2. Draw Blocks (We append to the row_win, which automatically moves cursor right)
            var col: usize = 0;
            while (col < bytes_per_row) : (col += 1) {
                const curr_addr = row_addr + col;
                var is_allocated = false;
                for (active_ranges.items) |range| {
                    if (curr_addr >= range.start and curr_addr < range.end) {
                        is_allocated = true;
                        break;
                    }
                }

                const char = if (is_allocated) "█ " else "· ";
                const style: vaxis.Cell.Style = if (is_allocated)
                    .{ .fg = .{ .rgb = .{ 0, 255, 0 } } }
                else
                    .{ .fg = .{ .rgb = .{ 60, 60, 60 } } };

                _ = row_win.print(&.{.{ .text = char, .style = style }}, .{});
            }
        }

        try vx.render(tty_writer);
    }
}

pub const SpyAllocator = struct {
    // parent allocator to do the actual work
    parent_allocator: std.mem.Allocator,
    // A list to store history of every allocation
    events: std.ArrayListUnmanaged(Event),
    // Thread safety
    mutex: std.Thread.Mutex,

    // @This makes Self the type of the immediate parent struct
    const Self = @This(); // SpyAllocator is the type being assigned here

    // Tagged union for the types of events being recorded
    pub const Event = union(enum) {
        alloc: struct { addr: usize, len: usize },
        free: struct { addr: usize },
    };

    // initializes the struct when called
    pub fn init(parent_allocator: std.mem.Allocator) Self {
        return Self{ .parent_allocator = parent_allocator, .events = .{}, .mutex = .{} };
    }

    pub fn deinit(self: *Self) void {
        self.events.deinit(self.parent_allocator);
    }

    // Using the allocator interface to set up our SpyAllocator
    pub fn allocator(self: *Self) std.mem.Allocator {
        return .{
            .ptr = self,

            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
                .remap = remap,
            },
        };
    }

    // allocates memory, with some spy action added
    fn alloc(
        ctx: *anyopaque, // Context: pointer that will be casted to our SpyAllocator
        len: usize, // size of the memory that is allocated
        ptr_align: std.mem.Alignment, // enum use to align the pointer in memory (CPU specific like 8-byte or 16-byte)
        ret_addr: usize, // Address of the code calling this function (for stack traces)
    ) ?[*]u8 {
        const self: *SpyAllocator = @ptrCast(@alignCast(ctx)); // Casting
        const result = self.parent_allocator.rawAlloc(len, ptr_align, ret_addr); // Allocation
        // Spy Action
        if (result) |ptr| {
            const addr = @intFromPtr(ptr);

            // LOCK THE MUTEX
            self.mutex.lock();
            defer self.mutex.unlock();

            self.events.append(self.parent_allocator, .{
                .alloc = .{ .addr = addr, .len = len },
            }) catch {
                std.debug.print("WARNING: SpyAllocator failed to record allocation\n", .{});
            };
        }
        return result;
    }

    // resizes the existing block of memory without changing its location
    fn resize(
        ctx: *anyopaque, // pointer used to cast to the allocator
        buf: []u8, // this is the current "slice" of memory being used, it stores both the pointer and current length
        buf_align: std.mem.Alignment, // The alignment of the existing buffer
        new_len: usize, // the new size we want for our memory
        ret_addr: usize, // Address of the code calling this function (for stack traces)
    ) bool {
        const self: *SpyAllocator = @ptrCast(@alignCast(ctx)); // Casting
        return self.parent_allocator.rawResize(buf, buf_align, new_len, ret_addr); // Resizing
    }

    // Releases memory in used for use else where
    fn free(
        ctx: *anyopaque, // pointer used to cast to the allocator
        buf: []u8, // the slice of memory that is no longer needed
        buf_align: std.mem.Alignment, // the alignment of that buffer
        ret_addr: usize, // Address of the code calling this function (for stack traces)
    ) void {
        const self: *SpyAllocator = @ptrCast(@alignCast(ctx)); // casting
        const addr = @intFromPtr(buf.ptr);
        // Spy action
        {
            self.mutex.lock();
            defer self.mutex.unlock();

            self.events.append(self.parent_allocator, .{
                .free = .{ .addr = addr },
            }) catch {
                std.debug.print("WARNING: SpyAllocator failed to record free\n", .{});
            };
        }
        return self.parent_allocator.rawFree(buf, buf_align, ret_addr); // Freeing memory
    }

    // it remaps the memory and its more of an advanced function
    // NOTE: WE DON'T NEED TO WORRY ABOUT THIS FUNCTION
    fn remap(
        ctx: *anyopaque,
        memory: []u8,
        alignment: std.mem.Alignment,
        new_len: usize,
        ret_addr: usize,
    ) ?[*]u8 {
        const self: *SpyAllocator = @ptrCast(@alignCast(ctx));
        return self.parent_allocator.rawRemap(memory, alignment, new_len, ret_addr);
    }
};
