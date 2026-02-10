const std = @import("std");
const InZight = @import("InZight");

pub fn main() void {
    std.log.info("Hello world", .{});
}

pub const SpyAllocator = struct {
    // State: parent allocator to do the actual work
    parent_allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(parent_allocator: std.mem.Allocator) !Self {
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
            },
        };
    }

    // The Functions: Implement the logic
    fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        const self: *SpyAllocator = @ptrCast(@alignCast(ctx));
        return self.parent_allocator.rawAlloc(len, ptr_align, ret_addr);
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        const self: *SpyAllocator = @ptrCast(@alignCast(ctx));
        return self.parent_allocator.rawResize(buf, buf_align, new_len, ret_addr);
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        const self: *SpyAllocator = @ptrCast(@alignCast(ctx));
        return self.parent_allocator.rawFree(buf, buf_align, ret_addr);
    }
};
