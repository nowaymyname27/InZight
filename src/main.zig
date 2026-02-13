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
    defer spy.deinit();
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
        ctx: *anyopaque, // pointer that will be casted to our SpyAllocator
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
