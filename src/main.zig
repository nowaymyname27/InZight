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
    lesson,
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

const MemoryLayoutAction = enum {
    none,
    heap_alloc,
    stack_call,
    gap_pressure,
};

const MemoryLayoutStep = struct {
    title: []const u8,
    message: []const u8,
    action: MemoryLayoutAction,
    focus_segment_start: usize,
    focus_segment_end: usize,
};

const memory_layout_steps = [_]MemoryLayoutStep{
    .{
        .title = "Process Memory Overview",
        .message = "This is a simulated process layout from low to high addresses.",
        .action = .none,
        .focus_segment_start = 0,
        .focus_segment_end = 5,
    },
    .{
        .title = "Text Segment",
        .message = "Text stores machine code and is fixed Read/Execute.",
        .action = .none,
        .focus_segment_start = 0,
        .focus_segment_end = 0,
    },
    .{
        .title = "Data + BSS Segments",
        .message = "Data and BSS store globals/statics and stay fixed Read/Write.",
        .action = .none,
        .focus_segment_start = 1,
        .focus_segment_end = 2,
    },
    .{
        .title = "Heap Growth (Upward)",
        .message = "A heap allocation adds bytes at higher addresses (upward).",
        .action = .heap_alloc,
        .focus_segment_start = 3,
        .focus_segment_end = 3,
    },
    .{
        .title = "Stack Growth (Downward)",
        .message = "A function call pushes a frame to lower addresses (downward).",
        .action = .stack_call,
        .focus_segment_start = 5,
        .focus_segment_end = 5,
    },
    .{
        .title = "The Gap",
        .message = "Heap and stack move toward each other; this gap is your remaining room.",
        .action = .gap_pressure,
        .focus_segment_start = 4,
        .focus_segment_end = 4,
    },
    .{
        .title = "Recap",
        .message = "Text/Data/BSS are fixed. Heap grows up. Stack grows down.",
        .action = .none,
        .focus_segment_start = 0,
        .focus_segment_end = 5,
    },
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

fn apply_memory_layout_step_action(sim: *sim_mod.Simulation, step_idx: usize) void {
    if (step_idx >= memory_layout_steps.len) return;
    switch (memory_layout_steps[step_idx].action) {
        .none => {},
        .heap_alloc => sim.allocate(64) catch {},
        .stack_call => sim.push_frame(64) catch {},
        .gap_pressure => {
            sim.allocate(128) catch {};
            sim.push_frame(96) catch {};
        },
    }
}

fn rebuild_memory_layout_state(sim: *sim_mod.Simulation, step_idx: usize) void {
    sim.reset();
    if (memory_layout_steps.len == 0) return;

    const clamped_step = if (step_idx < memory_layout_steps.len) step_idx else memory_layout_steps.len - 1;
    var i: usize = 0;
    while (i <= clamped_step) : (i += 1) {
        apply_memory_layout_step_action(sim, i);
    }
}

fn row_overlaps_focus(row_start: usize, row_end: usize, focus_start: usize, focus_end: usize) bool {
    return row_start < focus_end and focus_start < row_end;
}

fn memory_layout_ascii(step_idx: usize) []const []const u8 {
    return switch (step_idx) {
        0 => &[_][]const u8{
            "+------------------------+",
            "|       HIGH ADDR        |",
            "|   +----------------+   |",
            "|   |     STACK      |   |",
            "|   +----------------+   |",
            "|   |      GAP       |   |",
            "|   +----------------+   |",
            "|   |      HEAP      |   |",
            "|   +----------------+   |",
            "|   |      BSS       |   |",
            "|   |      DATA      |   |",
            "|   |      TEXT      |   |",
            "|       LOW ADDR         |",
            "+------------------------+",
        },
        1 => &[_][]const u8{
            "+------------------------+",
            "|  TEXT SEGMENT (R-X)    |",
            "|  +------------------+  |",
            "|  |  machine code    |  |",
            "|  |  instructions    |  |",
            "|  +------------------+  |",
            "|     fixed region       |",
            "+------------------------+",
        },
        2 => &[_][]const u8{
            "+------------------------+",
            "| DATA + BSS (R-W)       |",
            "| +--------+ +--------+  |",
            "| | DATA   | |  BSS   |  |",
            "| | init   | | zero   |  |",
            "| | values | | values |  |",
            "| +--------+ +--------+  |",
            "|     fixed regions       |",
            "+------------------------+",
        },
        3 => &[_][]const u8{
            "+------------------------+",
            "| HEAP GROWTH            |",
            "|      higher addr ^     |",
            "|   +--------------+     |",
            "|   | [A1][A2].... |     |",
            "|   +--------------+     |",
            "|      heap base         |",
            "+------------------------+",
        },
        4 => &[_][]const u8{
            "+------------------------+",
            "| STACK GROWTH           |",
            "|      lower addr v      |",
            "|   +--------------+     |",
            "|   | frame 3      |     |",
            "|   | frame 2      |     |",
            "|   | frame 1      |     |",
            "|   +--------------+     |",
            "+------------------------+",
        },
        5 => &[_][]const u8{
            "+------------------------+",
            "| GAP PRESSURE           |",
            "|   heap  ^    v stack   |",
            "|  +---+      +---+      |",
            "|  |###|  ..  |SSS|      |",
            "|  +---+      +---+      |",
            "|      gap shrinking      |",
            "+------------------------+",
        },
        else => &[_][]const u8{
            "+------------------------+",
            "| RECAP                  |",
            "| text/data/bss fixed    |",
            "| heap grows up    ^     |",
            "| stack grows down  v    |",
            "| keep a safe gap        |",
            "+------------------------+",
        },
    };
}

fn ascii_step_color(step_idx: usize) vaxis.Cell.Style {
    return switch (step_idx) {
        0 => .{ .fg = .{ .rgb = .{ 120, 220, 255 } }, .bg = .{ .rgb = .{ 15, 25, 35 } } },
        1 => .{ .fg = .{ .rgb = .{ 255, 210, 120 } }, .bg = .{ .rgb = .{ 35, 25, 15 } } },
        2 => .{ .fg = .{ .rgb = .{ 255, 170, 130 } }, .bg = .{ .rgb = .{ 30, 20, 20 } } },
        3 => .{ .fg = .{ .rgb = .{ 140, 255, 160 } }, .bg = .{ .rgb = .{ 18, 35, 20 } } },
        4 => .{ .fg = .{ .rgb = .{ 150, 190, 255 } }, .bg = .{ .rgb = .{ 20, 24, 38 } } },
        5 => .{ .fg = .{ .rgb = .{ 255, 190, 255 } }, .bg = .{ .rgb = .{ 32, 20, 34 } } },
        else => .{ .fg = .{ .rgb = .{ 210, 210, 210 } }, .bg = .{ .rgb = .{ 24, 24, 24 } } },
    };
}

fn render_ascii_panel(win: vaxis.Window, frame_alloc: std.mem.Allocator, step_idx: usize, start_row: usize, start_col: usize) !usize {
    if (start_row >= win.height) return 0;
    if (start_col >= win.width) return 0;

    const title = "Visual Model";
    const lines = memory_layout_ascii(step_idx);

    var max_len: usize = title.len;
    var max_lines: usize = 0;
    var step_i: usize = 0;
    while (step_i < memory_layout_steps.len) : (step_i += 1) {
        const step_lines = memory_layout_ascii(step_i);
        if (step_lines.len > max_lines) max_lines = step_lines.len;
        for (step_lines) |line| {
            if (line.len > max_len) max_len = line.len;
        }
    }

    const panel_width: usize = max_len + 2;
    if (start_col + panel_width > win.width) return 0;
    const inner_width = panel_width - 2;
    const accent = ascii_step_color(step_idx);

    const title_line = try fmt.allocPrint(frame_alloc, "|{s:<[1]}|", .{ title, inner_width });
    print_at(win, start_row, start_col, title_line, .{ .fg = .{ .rgb = .{ 255, 245, 160 } }, .bg = accent.bg });

    var row: usize = start_row + 1;
    var line_idx: usize = 0;
    while (line_idx < max_lines) : (line_idx += 1) {
        if (row >= win.height) break;
        const raw = if (line_idx < lines.len) lines[line_idx] else "";
        const clipped = if (raw.len > inner_width) raw[0..inner_width] else raw;
        const padded = try fmt.allocPrint(frame_alloc, "|{s:<[1]}|", .{ clipped, inner_width });
        const is_border = clipped.len > 0 and (clipped[0] == '+' or clipped[0] == '|');
        const line_style: vaxis.Cell.Style = if (is_border)
            .{ .fg = .{ .rgb = .{ 255, 255, 255 } }, .bg = accent.bg }
        else
            accent;
        print_at(win, row, start_col, padded, line_style);
        row += 1;
    }

    return 1 + max_lines;
}

fn render_memory_layout_lesson(win: vaxis.Window, frame_alloc: std.mem.Allocator, sim: *sim_mod.Simulation, step_idx: usize) !void {
    const clamped_step = if (step_idx < memory_layout_steps.len) step_idx else memory_layout_steps.len - 1;
    const step = memory_layout_steps[clamped_step];
    const segments = sim.segment_infos();
    const focus_start = segments[step.focus_segment_start].start;
    const focus_end = segments[step.focus_segment_end].end;

    var row: usize = 0;
    const title = try fmt.allocPrint(frame_alloc, "Memory Layout 101 | Step {d}/{d}", .{ clamped_step + 1, memory_layout_steps.len });
    print_line_styled(win, row, title, .{ .fg = .{ .rgb = .{ 120, 230, 255 } } });
    row += 1;

    print_line_styled(win, row, step.title, .{ .fg = .{ .rgb = .{ 255, 240, 170 } } });
    row += 1;
    print_line(win, row, step.message);
    row += 1;
    print_line(win, row, "Controls: n/-> next | b/<- back | r restart | m lessons | q quit");
    row += 2;

    print_line(win, row, "Address Range | Segment | Permissions | Growth");
    row += 1;
    for (segments, 0..) |segment, i| {
        const end_display = if (segment.end > segment.start) segment.end - 1 else segment.end;
        const line = try fmt.allocPrint(
            frame_alloc,
            "0x{x}-0x{x} | {s} | {s} | {s}",
            .{ segment.start, end_display, segment.name, segment.permissions, segment.growth },
        );
        const style: vaxis.Cell.Style = if (i >= step.focus_segment_start and i <= step.focus_segment_end)
            .{ .fg = .{ .rgb = .{ 10, 10, 10 } }, .bg = .{ .rgb = .{ 255, 225, 130 } } }
        else
            .{ .fg = .{ .rgb = .{ 210, 210, 210 } } };
        print_line_styled(win, row, line, style);
        row += 1;
    }

    row += 1;
    row += try render_ascii_panel(win, frame_alloc, clamped_step, row, 2);

    row += 1;
    print_line(win, row, "Map legend: T=text D=data B=bss .=heap-free 0-F=heap-alloc G=gap S=stack-used");
    row += 1;

    const bytes_per_row: usize = 16;
    const aligned_focus = focus_start & ~@as(usize, 0xF);
    const context_rows: usize = 4;
    const map_base = aligned_focus -| (context_rows * bytes_per_row);
    const map_start_row = row;

    while (row < win.height) : (row += 1) {
        const visual_row = row - map_start_row;
        const start_addr = map_base + (visual_row * bytes_per_row);
        if (start_addr >= sim_mod.Simulation.address_space_end) break;
        const end_addr = start_addr + bytes_per_row;

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

        const line_style: vaxis.Cell.Style = if (row_overlaps_focus(start_addr, end_addr, focus_start, focus_end))
            .{ .fg = .{ .rgb = .{ 255, 245, 200 } }, .bg = .{ .rgb = .{ 40, 40, 25 } } }
        else
            .{ .fg = .{ .rgb = .{ 140, 140, 140 } } };

        print_line_styled(win, row, line_buf.items, line_style);
    }
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
    var lesson_step: usize = 0;

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
                            screen = .lesson;
                            lesson_step = 0;
                            if (selected_lesson == .memory_layout)
                                rebuild_memory_layout_state(&sim, lesson_step)
                            else
                                sim.reset();
                        }
                    },
                    .lesson => {
                        if (key.matches('m', .{})) {
                            screen = .learn_menu;
                        }
                        if (selected_lesson == .memory_layout) {
                            if (key.matches('r', .{})) {
                                lesson_step = 0;
                                rebuild_memory_layout_state(&sim, lesson_step);
                            }
                            if (key.matches('n', .{}) or key.matches(' ', .{}) or key.matches(vaxis.Key.right, .{})) {
                                if (lesson_step + 1 < memory_layout_steps.len) {
                                    lesson_step += 1;
                                    rebuild_memory_layout_state(&sim, lesson_step);
                                }
                            }
                            if (key.matches('b', .{}) or key.matches(vaxis.Key.left, .{})) {
                                if (lesson_step > 0) {
                                    lesson_step -= 1;
                                    rebuild_memory_layout_state(&sim, lesson_step);
                                }
                            }
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
            .lesson => {
                if (selected_lesson == .memory_layout)
                    try render_memory_layout_lesson(win, frame_alloc, &sim, lesson_step)
                else
                    render_lesson_placeholder(win, selected_lesson);
            },
            .sandbox => try render_sandbox(win, frame_alloc, &sim, view_base),
        }

        try vx.render(tty_writer);
    }
}
