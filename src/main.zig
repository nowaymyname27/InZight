const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};

    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("TEST FAIL");
    }

    var spy = SpyAllocator.init(gpa.allocator());
    var allocator = spy.allocator();

    const slice = try allocator.alloc(i32, 5);
    defer allocator.free(slice);
}

pub const SpyAllocator = struct {
    // State: parent allocator to do the actual work
    parent_allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(parent_allocator: std.mem.Allocator) Self {
        return Self{
            .parent_allocator = parent_allocator,
        };
    }

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

    // The Functions: Implement the logic
    fn alloc(ctx: *anyopaque, len: usize, ptr_align: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *SpyAllocator = @ptrCast(@alignCast(ctx));
        std.debug.print("ALLOC: {d} bytes\n", .{len});
        return self.parent_allocator.rawAlloc(len, ptr_align, ret_addr);
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *SpyAllocator = @ptrCast(@alignCast(ctx));
        return self.parent_allocator.rawResize(buf, buf_align, new_len, ret_addr);
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
        const self: *SpyAllocator = @ptrCast(@alignCast(ctx));
        std.debug.print("FREE\n", .{});
        return self.parent_allocator.rawFree(buf, buf_align, ret_addr);
    }
    fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *SpyAllocator = @ptrCast(@alignCast(ctx));
        return self.parent_allocator.rawRemap(memory, alignment, new_len, ret_addr);
    }
};
