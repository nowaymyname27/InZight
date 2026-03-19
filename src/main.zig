const std = @import("std");
const vaxis = @import("vaxis");
const fmt = std.fmt;
const heap = std.heap;
const sim_mod = @import("sim.zig");

const AppEvent = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

const Screen = enum {
    main_menu,
    learn_menu,
    sandbox,
    lesson_placeholder,
};

const LessonTopic = enum {
    memory_layout,
    text_segment,
    data_bss,
    heap,
    stack,
    gap,

    fn title(self: LessonTopic) []const u8 {
        return switch (self) {
            .memory_layout => "Memory Layout 101",
            .text_segment => "Text Segment",
            .data_bss => "Data + BSS",
            .heap => "Heap",
            .stack => "Stack",
            .gap => "Gap (Heap/Stack Pressure)",
        };
    }
};

const main_menu_items = [_][]const u8{
    "Simulation Sandbox",
    "Learn Memory Sections",
    "Quit",
};

const learn_menu_items = [_]LessonTopic{
    .memory_layout,
    .text_segment,
    .data_bss,
    .heap,
    .stack,
    .gap,
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

fn print_line_styled(win: vaxis.Window, row: usize, text: []const u8, style: vaxis.Cell.Style) void {
    const row_win = win.child(.{
        .x_off = 0,
        .y_off = @intCast(row),
        .width = win.width,
        .height = 1,
    });
    _ = row_win.print(&.{.{ .text = text, .style = style }}, .{});
}

fn is_enter_pressed(key: vaxis.Key) bool {
    return key.matches(vaxis.Key.enter, .{}) or key.matches('\r', .{});
}

fn print_at(win: vaxis.Window, row: usize, col: usize, text: []const u8, style: vaxis.Cell.Style) void {
    if (col >= win.width or row >= win.height) return;
    const row_win = win.child(.{
        .x_off = @intCast(col),
        .y_off = @intCast(row),
        .width = @intCast(win.width - col),
        .height = 1,
    });
    _ = row_win.print(&.{.{ .text = text, .style = style }}, .{});
}

fn render_main_menu(win: vaxis.Window, frame_alloc: std.mem.Allocator, selected: usize) !void {
    const menu_start_row: usize = if (win.height > 16) (win.height - 16) / 2 else 0;
    const item_style: vaxis.Cell.Style = .{ .fg = .{ .rgb = .{ 230, 230, 230 } } };
    const selected_style: vaxis.Cell.Style = .{ .fg = .{ .rgb = .{ 10, 10, 10 } }, .bg = .{ .rgb = .{ 120, 220, 120 } } };

    const title = "InZight";
    const subtitle = "Interactive educational memory visualizer";
    const title_col = if (win.width > title.len) (win.width - title.len) / 2 else 0;
    const subtitle_col = if (win.width > subtitle.len) (win.width - subtitle.len) / 2 else 0;

    print_at(win, menu_start_row + 0, title_col, title, .{ .fg = .{ .rgb = .{ 80, 200, 255 } } });
    print_at(win, menu_start_row + 1, subtitle_col, subtitle, .{ .fg = .{ .rgb = .{ 170, 170, 170 } } });
    print_at(win, menu_start_row + 3, if (win.width > 9) (win.width - 9) / 2 else 0, "Main Menu", .{ .fg = .{ .rgb = .{ 255, 255, 200 } } });

    for (main_menu_items, 0..) |item, idx| {
        const line = if (idx == selected)
            try fmt.allocPrint(frame_alloc, ">> [ {s} ]", .{item})
        else
            try fmt.allocPrint(frame_alloc, "   {s}", .{item});
        const col = if (win.width > line.len) (win.width - line.len) / 2 else 0;
        print_at(win, menu_start_row + 5 + idx, col, line, if (idx == selected) selected_style else item_style);
    }

    const selected_label = try fmt.allocPrint(frame_alloc, "Selected: {s}", .{main_menu_items[selected]});
    const selected_col = if (win.width > selected_label.len) (win.width - selected_label.len) / 2 else 0;
    print_at(win, menu_start_row + 10, selected_col, selected_label, .{ .fg = .{ .rgb = .{ 160, 210, 160 } } });

    const controls = "Controls: j/k, arrows, w/s move | enter select | q quit";
    const controls_col = if (win.width > controls.len) (win.width - controls.len) / 2 else 0;
    print_at(win, menu_start_row + 12, controls_col, controls, .{ .fg = .{ .rgb = .{ 130, 130, 130 } } });
}

fn render_learn_menu(win: vaxis.Window, frame_alloc: std.mem.Allocator, selected: usize) !void {
    const menu_start_row: usize = if (win.height > 18) (win.height - 18) / 2 else 0;
    const item_style: vaxis.Cell.Style = .{ .fg = .{ .rgb = .{ 230, 230, 230 } } };
    const selected_style: vaxis.Cell.Style = .{ .fg = .{ .rgb = .{ 10, 10, 10 } }, .bg = .{ .rgb = .{ 255, 205, 100 } } };

    const title = "Learn Memory Sections";
    const subtitle = "Pick one topic to start a focused guided lesson";
    const title_col = if (win.width > title.len) (win.width - title.len) / 2 else 0;
    const subtitle_col = if (win.width > subtitle.len) (win.width - subtitle.len) / 2 else 0;

    print_at(win, menu_start_row + 0, title_col, title, .{ .fg = .{ .rgb = .{ 255, 220, 120 } } });
    print_at(win, menu_start_row + 1, subtitle_col, subtitle, .{ .fg = .{ .rgb = .{ 170, 170, 170 } } });

    for (learn_menu_items, 0..) |topic, idx| {
        const line = if (idx == selected)
            try fmt.allocPrint(frame_alloc, ">> [ {s} ]", .{topic.title()})
        else
            try fmt.allocPrint(frame_alloc, "   {s}", .{topic.title()});
        const col = if (win.width > line.len) (win.width - line.len) / 2 else 0;
        print_at(win, menu_start_row + 4 + idx, col, line, if (idx == selected) selected_style else item_style);
    }

    const selected_label = try fmt.allocPrint(frame_alloc, "Selected: {s}", .{learn_menu_items[selected].title()});
    const selected_col = if (win.width > selected_label.len) (win.width - selected_label.len) / 2 else 0;
    print_at(win, menu_start_row + 12, selected_col, selected_label, .{ .fg = .{ .rgb = .{ 255, 225, 160 } } });

    const controls = "Controls: j/k, arrows, w/s move | enter select | m back | q quit";
    const controls_col = if (win.width > controls.len) (win.width - controls.len) / 2 else 0;
    print_at(win, menu_start_row + 14, controls_col, controls, .{ .fg = .{ .rgb = .{ 130, 130, 130 } } });
}

fn render_lesson_placeholder(win: vaxis.Window, topic: LessonTopic) void {
    var row: usize = 2;
    var title_buf: [128]u8 = undefined;
    const title = fmt.bufPrint(&title_buf, "Lesson: {s}", .{topic.title()}) catch topic.title();
    print_line(win, row, title);
    row += 2;
    print_line(win, row, "This lesson screen is now wired into the app flow.");
    row += 1;
    print_line(win, row, "Next update will add guided simulation + explanations for this topic.");
    row += 2;
    print_line(win, row, "Controls: m back to lessons | q quit");
}

fn render_sandbox(win: vaxis.Window, frame_alloc: std.mem.Allocator, sim: *sim_mod.Simulation, view_base: usize) !void {
    var row: usize = 0;
    print_line(win, row, "InZight - Simulation Sandbox");
    row += 1;
    print_line(win, row, "Controls: n/space scripted step | a alloc | f free | c call | x return | j/k scroll | r reset | m menu | q quit");
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

    const map_start_row = row;
    const bytes_per_row: usize = 16;
    while (row < win.height) : (row += 1) {
        const visual_row = row - map_start_row;
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
    var screen: Screen = .main_menu;
    var main_menu_selected: usize = 0;
    var learn_menu_selected: usize = 0;
    var selected_lesson: LessonTopic = .memory_layout;

    main_loop: while (true) {
        const frame_alloc = frame_arena.allocator();
        defer _ = frame_arena.reset(.retain_capacity);

        const event = loop.nextEvent();
        switch (event) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true }) or key.matches('q', .{})) break :main_loop;

                switch (screen) {
                    .main_menu => {
                        if (key.matches(vaxis.Key.down, .{}) or key.matches('j', .{}) or key.matches('s', .{})) {
                            if (main_menu_selected + 1 < main_menu_items.len) main_menu_selected += 1;
                        }
                        if (key.matches(vaxis.Key.up, .{}) or key.matches('k', .{}) or key.matches('w', .{})) {
                            main_menu_selected -|= 1;
                        }
                        if (is_enter_pressed(key)) {
                            switch (main_menu_selected) {
                                0 => {
                                    screen = .sandbox;
                                    view_base = 0;
                                    sim.reset();
                                },
                                1 => {
                                    screen = .learn_menu;
                                    learn_menu_selected = 0;
                                },
                                2 => break :main_loop,
                                else => {},
                            }
                        }
                    },
                    .learn_menu => {
                        if (key.matches(vaxis.Key.down, .{}) or key.matches('j', .{}) or key.matches('s', .{})) {
                            if (learn_menu_selected + 1 < learn_menu_items.len) learn_menu_selected += 1;
                        }
                        if (key.matches(vaxis.Key.up, .{}) or key.matches('k', .{}) or key.matches('w', .{})) {
                            learn_menu_selected -|= 1;
                        }
                        if (key.matches('m', .{})) {
                            screen = .main_menu;
                        }
                        if (is_enter_pressed(key)) {
                            selected_lesson = learn_menu_items[learn_menu_selected];
                            screen = .lesson_placeholder;
                        }
                    },
                    .lesson_placeholder => {
                        if (key.matches('m', .{})) {
                            screen = .learn_menu;
                        }
                    },
                    .sandbox => {
                        if (key.matches('m', .{})) {
                            screen = .main_menu;
                        }
                        if (key.matches(vaxis.Key.down, .{}) or key.matches('j', .{})) view_base +|= 16;
                        if (key.matches(vaxis.Key.up, .{}) or key.matches('k', .{})) view_base -|= 16;
                        if (key.matches('n', .{}) or key.matches(' ', .{})) sim.step_scripted() catch {};
                        if (key.matches('a', .{})) sim.allocate(24) catch {};
                        if (key.matches('f', .{})) sim.free_oldest() catch {};
                        if (key.matches('c', .{})) sim.push_frame(32) catch {};
                        if (key.matches('x', .{})) sim.pop_frame();
                        if (key.matches('r', .{})) sim.reset();
                    },
                }
            },
            .winsize => |ws| try vx.resize(gpa.allocator(), tty.writer(), ws),
        }

        const win = vx.window();
        win.clear();

        switch (screen) {
            .main_menu => try render_main_menu(win, frame_alloc, main_menu_selected),
            .learn_menu => try render_learn_menu(win, frame_alloc, learn_menu_selected),
            .lesson_placeholder => render_lesson_placeholder(win, selected_lesson),
            .sandbox => try render_sandbox(win, frame_alloc, &sim, view_base),
        }

        try vx.render(tty_writer);
    }
}
