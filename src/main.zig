const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

/// Our main application state
const Model = struct {
    /// State of the counter
    count: u32 = 0,
    /// The button. This widget is stateful and must live between frames
    button: vxfw.Button,

    /// Helper function to return a vxfw.Widget struct
    pub fn widget(self: *Model) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = Model.typeErasedEventHandler,
            .drawFn = Model.typeErasedDrawFn,
        };
    }

    /// This function will be called from the vxfw runtime.
    fn typeErasedEventHandler(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
        const self: *Model = @ptrCast(@alignCast(ptr));
        switch (event) {
            // The root widget is always sent an init event as the first event. Users of the
            // library can also send this event to other widgets they create if they need to do
            // some initialization.
            .init => return ctx.requestFocus(self.button.widget()),
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) {
                    ctx.quit = true;
                    return;
                }
            },
            // We can request a specific widget gets focus. In this case, we always want to focus
            // our button. Having focus means that key events will be sent up the widget tree to
            // the focused widget, and then bubble back down the tree to the root. Users can tell
            // the runtime the event was handled and the capture or bubble phase will stop
            .focus_in => return ctx.requestFocus(self.button.widget()),
            else => {},
        }
    }

    /// This function is called from the vxfw runtime. It will be called on a regular interval, and
    /// only when any event handler has marked the redraw flag in EventContext as true. By
    /// explicitly requiring setting the redraw flag, vxfw can prevent excessive redraws for events
    /// which don't change state (ie mouse motion, unhandled key events, etc)
    fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
        const self: *Model = @ptrCast(@alignCast(ptr));
        // The DrawContext is inspired from Flutter. Each widget will receive a minimum and maximum
        // constraint. The minimum constraint will always be set, even if it is set to 0x0. The
        // maximum constraint can have null width and/or height - meaning there is no constraint in
        // that direction and the widget should take up as much space as it needs. By calling size()
        // on the max, we assert that it has some constrained size. This is *always* the case for
        // the root widget - the maximum size will always be the size of the terminal screen.
        const max_size = ctx.max.size();

        // The DrawContext also contains an arena allocator that can be used for each frame. The
        // lifetime of this allocation is until the next time we draw a frame. This is useful for
        // temporary allocations such as the one below: we have an integer we want to print as text.
        // We can safely allocate this with the ctx arena since we only need it for this frame.
        if (self.count > 0) {
            self.button.label = try std.fmt.allocPrint(ctx.arena, "Clicks: {d}", .{self.count});
        } else {
            self.button.label = "Click me!";
        }

        // Each widget returns a Surface from it's draw function. A Surface contains the rectangular
        // area of the widget, as well as some information about the surface or widget: can we focus
        // it? does it handle the mouse?
        //
        // It DOES NOT contain the location it should be within it's parent. Only the parent can set
        // this via a SubSurface. Here, we will return a Surface for the root widget (Model), which
        // has two SubSurfaces: one for the text and one for the button. A SubSurface is a Surface
        // with an offset and a z-index - the offset can be negative. This lets a parent draw a
        // child and place it within itself
        const button_child: vxfw.SubSurface = .{
            .origin = .{ .row = 0, .col = 0 },
            .surface = try self.button.draw(ctx.withConstraints(
                ctx.min,
                // Here we explicitly set a new maximum size constraint for the Button. A Button will
                // expand to fill it's area and must have some hard limit in the maximum constraint
                .{ .width = 16, .height = 3 },
            )),
        };

        // We also can use our arena to allocate the slice for our SubSurfaces. This slice only
        // needs to live until the next frame, making this safe.
        const children = try ctx.arena.alloc(vxfw.SubSurface, 1);
        children[0] = button_child;

        return .{
            // A Surface must have a size. Our root widget is the size of the screen
            .size = max_size,
            .widget = self.widget(),
            // We didn't actually need to draw anything for the root. In this case, we can set
            // buffer to a zero length slice. If this slice is *not zero length*, the runtime will
            // assert that it's length is equal to the size.width * size.height.
            .buffer = &.{},
            .children = children,
        };
    }

    /// The onClick callback for our button. This is also called if we press enter while the button
    /// has focus
    fn onClick(maybe_ptr: ?*anyopaque, ctx: *vxfw.EventContext) anyerror!void {
        const ptr = maybe_ptr orelse return;
        const self: *Model = @ptrCast(@alignCast(ptr));
        self.count +|= 1;
        return ctx.consumeAndRedraw();
    }
};

pub fn main() !void {
    // Using a GeneralPurposeAllocator as the parent allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};

    // Checks for memory leaks at the end of scope
    defer _ = gpa.deinit();
    defer {
        const deinit_status = gpa.deinit();
        // If memory leaks somewhere this will terminate the program
        if (deinit_status == .leak) @panic("TEST FAIL");
    }

    // We initialize our SpyAllocator using gpa as the parent allocator
    var spy = SpyAllocator.init(gpa.allocator());
    defer spy.deinit();
    const allocator = gpa.allocator();

    var app = try vxfw.App.init(allocator);
    defer app.deinit();

    const model = try allocator.create(Model);
    defer allocator.destroy(model);

    model.* = .{
        .count = 0,
        .button = .{
            .label = "Click me!",
            .onClick = Model.onClick,
            .userdata = model,
        },
    };

    try app.run(model.widget(), .{});
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
