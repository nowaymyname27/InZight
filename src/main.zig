const std = @import("std");
const InZight = @import("InZight");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var spy = try SpyAllocator.init(allocator, 10);
    defer spy.deinit();

    for (spy.slice, 0..) |*item, i| {
        item.* = @intCast(i * 10);
    }

    std.debug.print("Memory contents: {any}\n", .{spy.slice});
}

pub const SpyAllocator = struct {
    slice: []i32,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, size: usize) !Self {
        const slice = try allocator.alloc(i32, size);
        return Self{
            .slice = slice,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: Self) void {
        self.allocator.free(self.slice);
    }
};
