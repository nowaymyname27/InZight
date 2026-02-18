const std = @import("std");
const heap = std.heap;
const fmt = std.fmt;
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const TableRow = struct {
    action: []const u8,
    address: []const u8,
    size: []const u8,
};

const AppEvent = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

/// Our main application state
pub fn main() !void {
    // Using a GeneralPurposeAllocator as the parent allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};

    // Checks for memory leaks at the end of scope
    defer {
        const deinit_status = gpa.deinit();
        // If memory leaks somewhere this will terminate the program
        if (deinit_status == .leak) @panic("TEST FAIL");
    }

    // We initialize our SpyAllocator using gpa as the parent allocator
    var spy = SpyAllocator.init(gpa.allocator());
    defer spy.deinit();

    const tracked_allocator = spy.allocator();

    {
        const a = try tracked_allocator.alloc(u8, 100);
        const b = try tracked_allocator.alloc(u32, 5);
        tracked_allocator.free(a);
        const c = try tracked_allocator.alloc(u8, 200);
        defer tracked_allocator.free(b);
        defer tracked_allocator.free(c);
    }

    var tty_buf: [4096]u8 = undefined;
    var tty = try vaxis.Tty.init(&tty_buf);
    defer tty.deinit();

    var vx = try vaxis.init(gpa.allocator(), .{});
    const tty_writer = tty.writer();
    defer vx.deinit(gpa.allocator(), tty.writer());

    var loop: vaxis.Loop(AppEvent) = .{
        .tty = &tty,
        .vaxis = &vx,
    };
    try loop.init();
    try loop.start();
    defer loop.stop();

    try vx.enterAltScreen(tty.writer());
    try vx.queryTerminal(tty.writer(), 1 * std.time.ns_per_s);

    // 5. Setup Table Configuration
    var table_ctx: vaxis.widgets.Table.TableContext = .{
        // Define columns: Type, Address, Size
        .header_names = .{ .custom = &.{ "Action", "Address", "Size (Bytes)" } },
        // Map columns to fields in 'TableRow' struct: 0->type, 1->address, 2->size
        .col_indexes = .{ .by_idx = &.{ 0, 1, 2 } },
        .active_bg = .{ .rgb = .{ 64, 128, 255 } },
        .selected_bg = .{ .rgb = .{ 32, 64, 255 } },
        // Default column width strategy
        .col_width = .{ .static_individual = &.{ 10, 20, 15 } },
    };

    // Arena for per-frame temporary allocations (like the string adapters)
    var frame_arena = heap.ArenaAllocator.init(gpa.allocator());
    defer frame_arena.deinit();

    while (true) {
        // Reset temporary memory every frame
        const frame_alloc = frame_arena.allocator();
        defer _ = frame_arena.reset(.retain_capacity);

        // Input Handling
        const event = loop.nextEvent();
        switch (event) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) break;

                // Table Navigation
                if (key.matches(vaxis.Key.down, .{}) or key.matches('j', .{})) table_ctx.row +|= 1;
                if (key.matches(vaxis.Key.up, .{}) or key.matches('k', .{})) table_ctx.row -|= 1;
            },
            .winsize => |ws| try vx.resize(gpa.allocator(), tty.writer(), ws),
        }

        // Draw Logic
        const win = vx.window();
        win.clear();

        // 6. The Adapter Logic (Data -> View)
        // Convert the Spy's "Event List" into a "Table Row List"
        // We do this every frame. It's fast enough for a TUI.
        const events = spy.events.items;
        const rows = try frame_alloc.alloc(TableRow, events.len);

        for (events, 0..) |evt, i| {
            switch (evt) {
                .alloc => |data| {
                    rows[i] = .{
                        .action = "ALLOC",
                        // Format address as hex (0x...)
                        .address = try fmt.allocPrint(frame_alloc, "0x{x}", .{data.addr}),
                        // Format size as decimal
                        .size = try fmt.allocPrint(frame_alloc, "{d}", .{data.len}),
                    };
                },
                .free => |data| {
                    rows[i] = .{
                        .action = "FREE",
                        .address = try fmt.allocPrint(frame_alloc, "0x{x}", .{data.addr}),
                        .size = "-", // Or "0"
                    };
                },
            }
        }

        // 7. Draw the Table
        try vaxis.widgets.Table.drawTable(
            null,
            win,
            rows, // Pass our adapted rows
            &table_ctx,
        );

        try vx.render(tty_writer);
    }
}

pub const SpyAllocator = struct {
    // parent allocator to do the actual work
    parent_allocator: std.mem.Allocator,
    // A list to store history of every allocation
    events: std.ArrayListUnmanaged(Event),

    // @This makes Self the type of the immediate parent struct
    const Self = @This(); // SpyAllocator is the type being assigned here

    // Tagged union for the types of events being recorded
    pub const Event = union(enum) {
        alloc: struct { addr: usize, len: usize },
        free: struct { addr: usize },
    };

    // initializes the struct when called
    pub fn init(parent_allocator: std.mem.Allocator) Self {
        return Self{
            .parent_allocator = parent_allocator,
            .events = .{},
        };
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
            self.events.append(self.parent_allocator, .{
                .alloc = .{ // Recording an allocation
                    .addr = addr, // Record the address of the memory being allocated
                    .len = len, // Record the length
                },
            }) catch {
                // Lets me know if the SpyAllocator doesn't have enough memory to record
                std.debug.print("WARNING: SpyAllocator failed to record allocation (Out of Memory)\n", .{});
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
        self.events.append(self.parent_allocator, .{
            .free = .{ // Recording what memory is freed
                .addr = addr, // The address of the memory being released
            },
        }) catch {
            // Lets me know if the SpyAllocator doesn't have enough memory to record
            std.debug.print("WARNING: SpyAllocator failed to record memory being freed (Out of Memory)\n", .{});
        };
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
