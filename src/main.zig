const std = @import("std");
const vaxis = @import("vaxis");
const fmt = std.fmt;
const heap = std.heap;
const sim_mod = @import("sim.zig");

const AppEvent = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

fn print_line(win: vaxis.Window, row: usize, text: []const u8) void {
    const row_win = win.child(.{
        .x_off = 0,
        .y_off = @intCast(row),
        .width = win.width,
        .height = 1,
    });
    _ = row_win.print(&.{.{ .text = text, .style = .{} }}, .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const status = gpa.deinit();
        if (status == .leak) @panic("leak detected");
    }

    var sim = try sim_mod.Simulation.init(gpa.allocator());
    defer sim.deinit();

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

    var view_base: usize = 0;

    while (true) {
        const frame_alloc = frame_arena.allocator();
        defer _ = frame_arena.reset(.retain_capacity);

        const event = loop.nextEvent();
        switch (event) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true }) or key.matches('q', .{})) break;
                if (key.matches(vaxis.Key.down, .{}) or key.matches('j', .{})) view_base +|= 16;
                if (key.matches(vaxis.Key.up, .{}) or key.matches('k', .{})) view_base -|= 16;
                if (key.matches('n', .{}) or key.matches(' ', .{})) sim.step_scripted() catch {};
                if (key.matches('a', .{})) sim.allocate(24) catch {};
                if (key.matches('f', .{})) sim.free_oldest() catch {};
                if (key.matches('c', .{})) sim.push_frame(32) catch {};
                if (key.matches('x', .{})) sim.pop_frame();
                if (key.matches('r', .{})) sim.reset();
            },
            .winsize => |ws| try vx.resize(gpa.allocator(), tty.writer(), ws),
        }

        const win = vx.window();
        win.clear();

        var row: usize = 0;
        print_line(win, row, "InZight - Simulated Process Memory (educational mode)");
        row += 1;
        print_line(win, row, "Controls: n/space scripted step | a alloc | f free | c call | x return | j/k scroll | r reset | q quit");
        row += 1;

        const last_event_text = try sim.describe_last_event(frame_alloc);
        const metrics = sim.heap_metrics();
        const status = try fmt.allocPrint(
            frame_alloc,
            "Last: {s} | Tick: {d} | HeapUsed: {d}B | HeapFree: {d}B | Frag: {d}% | StackUsed: {d}B",
            .{ last_event_text, sim.tick_count(), metrics.used_bytes, metrics.free_bytes, metrics.fragmentation_percent, sim.stack_used_bytes() },
        );
        print_line(win, row, status);
        row += 2;

        print_line(win, row, "Address Range | Segment | Permissions | Growth");
        row += 1;

        const segments = sim.segment_infos();
        for (segments) |segment| {
            const end_display = if (segment.end > segment.start) segment.end - 1 else segment.end;
            const line = try fmt.allocPrint(
                frame_alloc,
                "0x{x}-0x{x} | {s} | {s} | {s}",
                .{ segment.start, end_display, segment.name, segment.permissions, segment.growth },
            );
            print_line(win, row, line);
            row += 1;
        }

        row += 1;
        print_line(win, row, "Map legend: T=text D=data B=bss .=heap-free 0-F=heap-alloc G=gap S=stack-used");
        row += 1;

        const bytes_per_row: usize = 16;
        while (row < win.height) : (row += 1) {
            const visual_row = row - 12;
            const start_addr = view_base + (visual_row * bytes_per_row);
            if (start_addr >= sim_mod.Simulation.address_space_end) break;

            var line_buf = std.ArrayListUnmanaged(u8){};
            defer line_buf.deinit(frame_alloc);
            const writer = line_buf.writer(frame_alloc);

            try writer.print("0x{x} | ", .{start_addr});
            var col: usize = 0;
            while (col < bytes_per_row) : (col += 1) {
                const addr = start_addr + col;
                if (addr >= sim_mod.Simulation.address_space_end) break;
                try writer.print("{c} ", .{sim.symbol_for_address(addr)});
            }

            print_line(win, row, line_buf.items);
        }

        try vx.render(tty_writer);
    }
}
