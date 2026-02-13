const std = @import("std");

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
    var allocator = spy.allocator();

    // Tries to allocate the desired memory, returns an error if it fails
    const slice = try allocator.alloc(i32, 5);
    // This will free the allocated memory at the end of scope
    defer allocator.free(slice);
}

pub const SpyAllocator = struct {
    // parent allocator to do the actual work
    parent_allocator: std.mem.Allocator,
    // A list to store history of every allocation
    events: std.ArrayList(Event),

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
            .events = std.ArrayList(Event).init(parent_allocator), // uses parent_allocator to create the events list
        };
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
        ctx: *anyopaque, // pointer that will be casted to our SpyAllocator
        len: usize, // size of the memory that is allocated
        ptr_align: std.mem.Alignment, // enum use to align the pointer in memory (CPU specific like 8-byte or 16-byte)
        ret_addr: usize, // Address of the code calling this function (for stack traces)
    ) ?[*]u8 {
        const self: *SpyAllocator = @ptrCast(@alignCast(ctx)); // Casting
        std.debug.print("ALLOC: {d} bytes\n", .{len}); // Spy action
        return self.parent_allocator.rawAlloc(len, ptr_align, ret_addr); // Allocation
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
        std.debug.print("FREE\n", .{}); // Spy action
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
