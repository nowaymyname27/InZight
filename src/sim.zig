const std = @import("std");

pub const Simulation = struct {
    pub const address_space_start: usize = 0x0000;
    pub const address_space_end: usize = 0x10000;

    const text_end: usize = 0x2000;
    const data_end: usize = 0x2800;
    const bss_end: usize = 0x3000;
    const heap_base: usize = bss_end;
    const stack_top: usize = address_space_end;

    const HeapBlock = struct {
        start: usize,
        size: usize,
        allocation_id: ?u32,
    };

    const StackFrame = struct {
        id: u32,
        start: usize,
        size: usize,
    };

    pub const SegmentInfo = struct {
        start: usize,
        end: usize,
        name: []const u8,
        permissions: []const u8,
        growth: []const u8,
    };

    pub const HeapMetrics = struct {
        used_bytes: usize,
        free_bytes: usize,
        fragmentation_percent: usize,
    };

    pub const Event = union(enum) {
        startup: void,
        alloc: struct { id: u32, start: usize, size: usize },
        free: struct { id: u32, start: usize, size: usize },
        call: struct { id: u32, start: usize, size: usize },
        ret: struct { id: u32, start: usize, size: usize },
        alloc_failed: struct { size: usize },
        call_failed: struct { size: usize },
        idle: void,
    };

    allocator: std.mem.Allocator,
    tick: usize,
    next_alloc_id: u32,
    next_frame_id: u32,
    heap_end: usize,
    stack_ptr: usize,
    heap_blocks: std.ArrayListUnmanaged(HeapBlock),
    active_alloc_ids: std.ArrayListUnmanaged(u32),
    stack_frames: std.ArrayListUnmanaged(StackFrame),
    last_event: Event,

    pub fn init(allocator: std.mem.Allocator) !Simulation {
        return .{
            .allocator = allocator,
            .tick = 0,
            .next_alloc_id = 1,
            .next_frame_id = 1,
            .heap_end = heap_base,
            .stack_ptr = stack_top,
            .heap_blocks = .{},
            .active_alloc_ids = .{},
            .stack_frames = .{},
            .last_event = .startup,
        };
    }

    pub fn deinit(self: *Simulation) void {
        self.heap_blocks.deinit(self.allocator);
        self.active_alloc_ids.deinit(self.allocator);
        self.stack_frames.deinit(self.allocator);
    }

    pub fn reset(self: *Simulation) void {
        self.tick = 0;
        self.next_alloc_id = 1;
        self.next_frame_id = 1;
        self.heap_end = heap_base;
        self.stack_ptr = stack_top;
        self.heap_blocks.clearRetainingCapacity();
        self.active_alloc_ids.clearRetainingCapacity();
        self.stack_frames.clearRetainingCapacity();
        self.last_event = .startup;
    }

    pub fn tick_count(self: *const Simulation) usize {
        return self.tick;
    }

    pub fn stack_used_bytes(self: *const Simulation) usize {
        return stack_top - self.stack_ptr;
    }

    pub fn segment_infos(self: *const Simulation) [6]SegmentInfo {
        return .{
            .{ .start = address_space_start, .end = text_end, .name = "Text Segment", .permissions = "Read/Execute", .growth = "Fixed" },
            .{ .start = text_end, .end = data_end, .name = "Data Segment", .permissions = "Read/Write", .growth = "Fixed" },
            .{ .start = data_end, .end = bss_end, .name = "BSS Segment", .permissions = "Read/Write", .growth = "Fixed" },
            .{ .start = heap_base, .end = self.heap_end, .name = "Heap", .permissions = "Read/Write", .growth = "Upward (↑)" },
            .{ .start = self.heap_end, .end = self.stack_ptr, .name = "Unused Space (Gap)", .permissions = "N/A", .growth = "N/A" },
            .{ .start = self.stack_ptr, .end = stack_top, .name = "Stack", .permissions = "Read/Write", .growth = "Downward (↓)" },
        };
    }

    pub fn heap_metrics(self: *const Simulation) HeapMetrics {
        var used_bytes: usize = 0;
        var free_bytes: usize = 0;
        var largest_free: usize = 0;

        for (self.heap_blocks.items) |block| {
            if (block.allocation_id) |_| {
                used_bytes += block.size;
            } else {
                free_bytes += block.size;
                if (block.size > largest_free) largest_free = block.size;
            }
        }

        const fragmentation_percent = if (free_bytes == 0)
            0
        else
            ((free_bytes - largest_free) * 100) / free_bytes;

        return .{
            .used_bytes = used_bytes,
            .free_bytes = free_bytes,
            .fragmentation_percent = fragmentation_percent,
        };
    }

    pub fn describe_last_event(self: *const Simulation, allocator: std.mem.Allocator) ![]const u8 {
        return switch (self.last_event) {
            .startup => try std.fmt.allocPrint(allocator, "Simulation reset", .{}),
            .alloc => |evt| try std.fmt.allocPrint(allocator, "alloc id={d} size={d}B at 0x{x}", .{ evt.id, evt.size, evt.start }),
            .free => |evt| try std.fmt.allocPrint(allocator, "free id={d} size={d}B at 0x{x}", .{ evt.id, evt.size, evt.start }),
            .call => |evt| try std.fmt.allocPrint(allocator, "call frame={d} size={d}B at 0x{x}", .{ evt.id, evt.size, evt.start }),
            .ret => |evt| try std.fmt.allocPrint(allocator, "return frame={d} size={d}B from 0x{x}", .{ evt.id, evt.size, evt.start }),
            .alloc_failed => |evt| try std.fmt.allocPrint(allocator, "alloc FAILED size={d}B (heap would collide with stack)", .{evt.size}),
            .call_failed => |evt| try std.fmt.allocPrint(allocator, "call FAILED frame size={d}B (stack would collide with heap)", .{evt.size}),
            .idle => try std.fmt.allocPrint(allocator, "idle (no-op)", .{}),
        };
    }

    pub fn symbol_for_address(self: *const Simulation, addr: usize) u8 {
        if (addr < text_end) return 'T';
        if (addr < data_end) return 'D';
        if (addr < bss_end) return 'B';

        if (addr < self.heap_end) {
            for (self.heap_blocks.items) |block| {
                if (addr >= block.start and addr < block.start + block.size) {
                    if (block.allocation_id) |id| {
                        const hex = "0123456789ABCDEF";
                        return hex[id % 16];
                    }
                    return '.';
                }
            }
            return '.';
        }

        if (addr < self.stack_ptr) return 'G';
        if (addr < stack_top) return 'S';
        return ' ';
    }

    pub fn step_scripted(self: *Simulation) !void {
        const action = self.tick % 8;
        self.tick += 1;

        switch (action) {
            0 => try self.allocate(24),
            1 => try self.allocate(40),
            2 => try self.push_frame(32),
            3 => try self.free_oldest(),
            4 => try self.allocate(16),
            5 => try self.push_frame(48),
            6 => self.pop_frame(),
            7 => try self.free_newest(),
            else => unreachable,
        }
    }

    pub fn allocate(self: *Simulation, requested_size: usize) !void {
        const size = align_up(requested_size, 8);

        var i: usize = 0;
        while (i < self.heap_blocks.items.len) : (i += 1) {
            const block = self.heap_blocks.items[i];
            if (block.allocation_id == null and block.size >= size) {
                const id = self.next_alloc_id;
                self.next_alloc_id += 1;

                self.heap_blocks.items[i].allocation_id = id;

                if (block.size > size) {
                    const remainder = HeapBlock{
                        .start = block.start + size,
                        .size = block.size - size,
                        .allocation_id = null,
                    };
                    self.heap_blocks.items[i].size = size;
                    try self.heap_blocks.insert(self.allocator, i + 1, remainder);
                }

                try self.active_alloc_ids.append(self.allocator, id);
                self.last_event = .{ .alloc = .{ .id = id, .start = block.start, .size = size } };
                return;
            }
        }

        if (self.heap_end + size > self.stack_ptr) {
            self.last_event = .{ .alloc_failed = .{ .size = size } };
            return;
        }

        const id = self.next_alloc_id;
        self.next_alloc_id += 1;

        const start = self.heap_end;
        try self.heap_blocks.append(self.allocator, .{
            .start = start,
            .size = size,
            .allocation_id = id,
        });
        self.heap_end += size;
        try self.active_alloc_ids.append(self.allocator, id);
        self.last_event = .{ .alloc = .{ .id = id, .start = start, .size = size } };
    }

    pub fn free_oldest(self: *Simulation) !void {
        if (self.active_alloc_ids.items.len == 0) {
            self.last_event = .idle;
            return;
        }

        const id = self.active_alloc_ids.items[0];
        _ = self.active_alloc_ids.orderedRemove(0);
        try self.free_by_id(id);
    }

    pub fn free_newest(self: *Simulation) !void {
        if (self.active_alloc_ids.items.len == 0) {
            self.last_event = .idle;
            return;
        }

        const id = self.active_alloc_ids.pop() orelse unreachable;
        try self.free_by_id(id);
    }

    pub fn push_frame(self: *Simulation, requested_size: usize) !void {
        const size = align_up(requested_size, 16);

        if (self.stack_ptr < self.heap_end + size) {
            self.last_event = .{ .call_failed = .{ .size = size } };
            return;
        }

        self.stack_ptr -= size;
        const id = self.next_frame_id;
        self.next_frame_id += 1;

        try self.stack_frames.append(self.allocator, .{
            .id = id,
            .start = self.stack_ptr,
            .size = size,
        });

        self.last_event = .{ .call = .{ .id = id, .start = self.stack_ptr, .size = size } };
    }

    pub fn pop_frame(self: *Simulation) void {
        const frame = self.stack_frames.pop() orelse {
            self.last_event = .idle;
            return;
        };

        self.stack_ptr += frame.size;
        self.last_event = .{ .ret = .{ .id = frame.id, .start = frame.start, .size = frame.size } };
    }

    fn free_by_id(self: *Simulation, id: u32) !void {
        for (self.heap_blocks.items, 0..) |*block, i| {
            if (block.allocation_id != null and block.allocation_id.? == id) {
                block.allocation_id = null;
                const event_start = block.start;
                const event_size = block.size;
                self.coalesce_around(i);
                self.last_event = .{ .free = .{ .id = id, .start = event_start, .size = event_size } };
                return;
            }
        }

        self.last_event = .idle;
    }

    fn coalesce_around(self: *Simulation, index: usize) void {
        var idx = index;

        if (idx > 0) {
            const left = self.heap_blocks.items[idx - 1];
            const curr = self.heap_blocks.items[idx];
            if (left.allocation_id == null and curr.allocation_id == null and left.start + left.size == curr.start) {
                self.heap_blocks.items[idx - 1].size += curr.size;
                _ = self.heap_blocks.orderedRemove(idx);
                idx -= 1;
            }
        }

        if (idx + 1 < self.heap_blocks.items.len) {
            const curr = self.heap_blocks.items[idx];
            const right = self.heap_blocks.items[idx + 1];
            if (curr.allocation_id == null and right.allocation_id == null and curr.start + curr.size == right.start) {
                self.heap_blocks.items[idx].size += right.size;
                _ = self.heap_blocks.orderedRemove(idx + 1);
            }
        }

        while (self.heap_blocks.items.len > 0) {
            const last_idx = self.heap_blocks.items.len - 1;
            const last = self.heap_blocks.items[last_idx];
            if (last.allocation_id != null) break;
            self.heap_end = last.start;
            _ = self.heap_blocks.pop();
        }
    }
};

fn align_up(value: usize, alignment: usize) usize {
    return std.mem.alignForward(usize, value, alignment);
}

test "segment ordering follows text/data/bss/heap/gap/stack" {
    var sim = try Simulation.init(std.testing.allocator);
    defer sim.deinit();

    const segments = sim.segment_infos();

    try std.testing.expectEqual(@as(usize, 0x0000), segments[0].start);
    try std.testing.expectEqual(@as(usize, 0x2000), segments[1].start);
    try std.testing.expectEqual(@as(usize, 0x2800), segments[2].start);
    try std.testing.expectEqual(@as(usize, 0x3000), segments[3].start);
    try std.testing.expectEqualStrings("Text Segment", segments[0].name);
    try std.testing.expectEqualStrings("Heap", segments[3].name);
    try std.testing.expectEqualStrings("Stack", segments[5].name);
}

test "heap alloc and free update metrics" {
    var sim = try Simulation.init(std.testing.allocator);
    defer sim.deinit();

    try sim.allocate(24);
    try sim.allocate(40);
    const before = sim.heap_metrics();
    try std.testing.expect(before.used_bytes >= 64);

    try sim.free_oldest();
    const after = sim.heap_metrics();
    try std.testing.expect(after.used_bytes < before.used_bytes);
    try std.testing.expect(after.free_bytes > 0);
}

test "stack grows downward and returns upward" {
    var sim = try Simulation.init(std.testing.allocator);
    defer sim.deinit();

    const start = sim.stack_used_bytes();
    try sim.push_frame(32);
    const after_call = sim.stack_used_bytes();
    try std.testing.expect(after_call > start);

    sim.pop_frame();
    const after_return = sim.stack_used_bytes();
    try std.testing.expectEqual(start, after_return);
}
