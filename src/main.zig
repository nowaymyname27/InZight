const std = @import("std");
const vaxis = @import("vaxis");
const fmt = std.fmt;
const heap = std.heap;
const sim_mod = @import("sim.zig");
const widgets = vaxis.widgets;

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
    "Learn Memory Sections",
    "Simulation Sandbox",
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

const theme = struct {
    const header: vaxis.Cell.Style = .{ .fg = .{ .rgb = .{ 20, 28, 36 } }, .bg = .{ .rgb = .{ 110, 200, 255 } } };
    const subtitle: vaxis.Cell.Style = .{ .fg = .{ .rgb = .{ 150, 175, 195 } } };
    const controls: vaxis.Cell.Style = .{ .fg = .{ .rgb = .{ 130, 145, 160 } } };
    const panel_title: vaxis.Cell.Style = .{ .fg = .{ .rgb = .{ 120, 210, 255 } } };
    const item: vaxis.Cell.Style = .{ .fg = .{ .rgb = .{ 220, 230, 240 } } };
    const selected: vaxis.Cell.Style = .{ .fg = .{ .rgb = .{ 8, 14, 18 } }, .bg = .{ .rgb = .{ 115, 210, 255 } } };
    const lesson_focus: vaxis.Cell.Style = .{ .fg = .{ .rgb = .{ 8, 10, 12 } }, .bg = .{ .rgb = .{ 255, 225, 130 } } };
    const lesson_dim: vaxis.Cell.Style = .{ .fg = .{ .rgb = .{ 200, 208, 214 } } };
    const map_focus: vaxis.Cell.Style = .{ .fg = .{ .rgb = .{ 245, 250, 255 } }, .bg = .{ .rgb = .{ 26, 36, 48 } } };
    const map_dim: vaxis.Cell.Style = .{ .fg = .{ .rgb = .{ 125, 140, 155 } } };
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

const SegmentTableRow = struct {
    address_range: []const u8,
    segment: []const u8,
    permissions: []const u8,
    growth: []const u8,
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

fn render_shell(win: vaxis.Window, frame_alloc: std.mem.Allocator, context: []const u8, subtitle: []const u8, controls: []const u8) !vaxis.Window {
    const header = try fmt.allocPrint(frame_alloc, " InZight  |  {s}", .{context});
    print_line_styled(win, 0, header, theme.header);
    if (win.height > 1) {
        print_line_styled(win, 1, subtitle, theme.subtitle);
    }
    if (win.height > 0) {
        print_line_styled(win, win.height - 1, controls, theme.controls);
    }

    const content_y: usize = if (win.height > 3) 3 else 0;
    const content_h: usize = if (win.height > 4) win.height - 4 else win.height;
    const content_w: usize = if (win.width > 2) win.width - 2 else win.width;
    return win.child(.{
        .x_off = 1,
        .y_off = @intCast(content_y),
        .width = @intCast(content_w),
        .height = @intCast(content_h),
    });
}

fn print_section_title(win: vaxis.Window, row: usize, title: []const u8) void {
    print_line_styled(win, row, title, theme.panel_title);
}

fn build_segment_table_rows(allocator: std.mem.Allocator, sim: *sim_mod.Simulation) ![]SegmentTableRow {
    const segments = sim.segment_infos();
    var rows = try allocator.alloc(SegmentTableRow, segments.len);
    for (segments, 0..) |segment, i| {
        const end_display = if (segment.end > segment.start) segment.end - 1 else segment.end;
        rows[i] = .{
            .address_range = try fmt.allocPrint(allocator, "0x{x}-0x{x}", .{ segment.start, end_display }),
            .segment = segment.name,
            .permissions = segment.permissions,
            .growth = segment.growth,
        };
    }
    return rows;
}

fn draw_segment_table(
    win: vaxis.Window,
    allocator: std.mem.Allocator,
    sim: *sim_mod.Simulation,
    focus_start: ?usize,
    focus_end: ?usize,
    step_style: ?vaxis.Cell.Style,
) !usize {
    const rows = try build_segment_table_rows(allocator, sim);

    const active_fg = if (step_style) |style| style.fg else vaxis.Cell.Color{ .rgb = .{ 8, 10, 12 } };
    const active_bg = if (step_style) |style| style.bg else vaxis.Cell.Color{ .rgb = .{ 255, 225, 130 } };
    const selected_fg = if (step_style) |style| style.fg else vaxis.Cell.Color{ .default = {} };
    const selected_bg = if (step_style) |style| style.bg else vaxis.Cell.Color{ .rgb = .{ 55, 88, 112 } };

    var table_ctx: widgets.Table.TableContext = .{
        .selected_bg = selected_bg,
        .selected_fg = selected_fg,
        .active_bg = active_bg,
        .active_fg = active_fg,
        .hdr_bg_1 = .{ .rgb = .{ 24, 44, 58 } },
        .hdr_bg_2 = .{ .rgb = .{ 16, 36, 48 } },
        .row_bg_1 = .{ .rgb = .{ 20, 24, 30 } },
        .row_bg_2 = .{ .rgb = .{ 14, 18, 24 } },
        .header_borders = true,
        .col_borders = false,
        .col_width = .dynamic_fill,
        .header_names = .{ .custom = &.{ "Address Range", "Segment", "Permissions", "Growth" } },
    };

    if (focus_start != null and focus_end != null) {
        const fs = focus_start.?;
        const fe = focus_end.?;
        if (fs < rows.len) {
            table_ctx.active = true;
            table_ctx.row = @intCast(fs);
        }

        if (fe > fs + 1 and fe <= rows.len) {
            const selected_count = fe - fs - 1;
            const selected = try allocator.alloc(u16, selected_count);
            for (selected, 0..) |*entry, i| {
                entry.* = @intCast(fs + 1 + i);
            }
            table_ctx.sel_rows = selected;
        }
    }

    try widgets.Table.drawTable(allocator, win, rows, &table_ctx);
    return 1 + rows.len;
}

fn render_main_menu(win: vaxis.Window, frame_alloc: std.mem.Allocator, selected: usize) !void {
    const content = try render_shell(
        win,
        frame_alloc,
        "Main Menu",
        "Educational memory visualization in a simulated process model",
        "j/k or arrows/w/s move | enter select | q quit",
    );

    const menu_start_row: usize = if (content.height > 12) (content.height - 12) / 2 else 0;

    const title = "InZight";
    const subtitle = "Choose a mode to start learning";
    const title_col = if (content.width > title.len) (content.width - title.len) / 2 else 0;
    const subtitle_col = if (content.width > subtitle.len) (content.width - subtitle.len) / 2 else 0;

    print_at(content, menu_start_row + 0, title_col, title, .{ .fg = .{ .rgb = .{ 120, 220, 255 } } });
    print_at(content, menu_start_row + 1, subtitle_col, subtitle, theme.subtitle);
    print_at(content, menu_start_row + 3, if (content.width > 9) (content.width - 9) / 2 else 0, "Main Menu", theme.panel_title);

    for (main_menu_items, 0..) |item, idx| {
        const line = if (idx == selected)
            try fmt.allocPrint(frame_alloc, ">> [ {s} ]", .{item})
        else
            try fmt.allocPrint(frame_alloc, "   {s}", .{item});
        const col = if (content.width > line.len) (content.width - line.len) / 2 else 0;
        print_at(content, menu_start_row + 5 + idx, col, line, if (idx == selected) theme.selected else theme.item);
    }

    const selected_label = try fmt.allocPrint(frame_alloc, "Selected: {s}", .{main_menu_items[selected]});
    const selected_col = if (content.width > selected_label.len) (content.width - selected_label.len) / 2 else 0;
    print_at(content, menu_start_row + 10, selected_col, selected_label, .{ .fg = .{ .rgb = .{ 165, 225, 190 } } });
}

fn render_learn_menu(win: vaxis.Window, frame_alloc: std.mem.Allocator, selected: usize) !void {
    const content = try render_shell(
        win,
        frame_alloc,
        "Learn Memory Sections",
        "Select a topic and step through guided visual explanations",
        "j/k or arrows/w/s move | enter select | m back | q quit",
    );

    const menu_start_row: usize = if (content.height > 14) (content.height - 14) / 2 else 0;

    const title = "Learn Memory Sections";
    const subtitle = "Pick one topic to start a focused guided lesson";
    const title_col = if (content.width > title.len) (content.width - title.len) / 2 else 0;
    const subtitle_col = if (content.width > subtitle.len) (content.width - subtitle.len) / 2 else 0;

    print_at(content, menu_start_row + 0, title_col, title, .{ .fg = .{ .rgb = .{ 120, 220, 255 } } });
    print_at(content, menu_start_row + 1, subtitle_col, subtitle, theme.subtitle);

    for (learn_menu_items, 0..) |topic, idx| {
        const line = if (idx == selected)
            try fmt.allocPrint(frame_alloc, ">> [ {s} ]", .{topic.title()})
        else
            try fmt.allocPrint(frame_alloc, "   {s}", .{topic.title()});
        const col = if (content.width > line.len) (content.width - line.len) / 2 else 0;
        print_at(content, menu_start_row + 4 + idx, col, line, if (idx == selected) theme.selected else theme.item);
    }

    const selected_label = try fmt.allocPrint(frame_alloc, "Selected: {s}", .{learn_menu_items[selected].title()});
    const selected_col = if (content.width > selected_label.len) (content.width - selected_label.len) / 2 else 0;
    print_at(content, menu_start_row + 11, selected_col, selected_label, .{ .fg = .{ .rgb = .{ 165, 225, 190 } } });
}

fn render_lesson_placeholder(win: vaxis.Window, frame_alloc: std.mem.Allocator, topic: LessonTopic) !void {
    const content = try render_shell(
        win,
        frame_alloc,
        "Lesson",
        "Guided visuals for this topic are coming next",
        "m back to lesson menu | q quit",
    );

    var row: usize = 1;
    var title_buf: [128]u8 = undefined;
    const title = fmt.bufPrint(&title_buf, "Lesson: {s}", .{topic.title()}) catch topic.title();
    print_section_title(content, row, title);
    row += 2;
    print_line(content, row, "This lesson is wired into the app flow.");
    row += 1;
    print_line(content, row, "Next update will add guided simulation + topic-specific visuals.");
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
            "|   +----------------+   |",
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
            "|     fixed regions      |",
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
            "|      gap shrinking     |",
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

    const content = try render_shell(
        win,
        frame_alloc,
        "Lesson: Memory Layout 101",
        "Step through segment behavior with synchronized visuals",
        "n/-> next | b/<- back | r restart | m lessons | q quit",
    );

    var row: usize = 0;
    const title = try fmt.allocPrint(frame_alloc, "Memory Layout 101 | Step {d}/{d}", .{ clamped_step + 1, memory_layout_steps.len });
    print_section_title(content, row, title);
    row += 1;

    print_line_styled(content, row, step.title, .{ .fg = .{ .rgb = .{ 255, 230, 165 } } });
    row += 1;
    print_line_styled(content, row, step.message, theme.lesson_dim);
    row += 2;

    const table_win = content.child(.{
        .x_off = 0,
        .y_off = @intCast(row),
        .width = content.width,
        .height = @intCast(content.height -| row),
    });
    row += try draw_segment_table(table_win, frame_alloc, sim, step.focus_segment_start, step.focus_segment_end + 1, ascii_step_color(clamped_step));

    row += 1;
    row += try render_ascii_panel(content, frame_alloc, clamped_step, row, 2);

    row += 1;
    print_line_styled(content, row, "Map legend: T=text D=data B=bss .=heap-free 0-F=heap-alloc G=gap S=stack-used", theme.controls);
    row += 1;

    const bytes_per_row: usize = 16;
    const aligned_focus = focus_start & ~@as(usize, 0xF);
    const context_rows: usize = 4;
    const map_base = aligned_focus -| (context_rows * bytes_per_row);
    const map_start_row = row;

    while (row < content.height) : (row += 1) {
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
            theme.map_focus
        else
            theme.map_dim;

        print_line_styled(content, row, line_buf.items, line_style);
    }
}

fn render_sandbox(win: vaxis.Window, frame_alloc: std.mem.Allocator, sim: *sim_mod.Simulation, view_base: usize) !void {
    const content = try render_shell(
        win,
        frame_alloc,
        "Simulation Sandbox",
        "Explore heap/stack behavior with manual and scripted actions",
        "n/space step | a alloc | f free | c call | x return | j/k scroll | r reset | m menu | q quit",
    );

    var row: usize = 0;
    print_section_title(content, row, "Simulation Sandbox");
    row += 1;

    const last_event_text = try sim.describe_last_event(frame_alloc);
    const metrics = sim.heap_metrics();
    const status = try fmt.allocPrint(
        frame_alloc,
        "Last: {s} | Tick: {d} | HeapUsed: {d}B | HeapFree: {d}B | Frag: {d}% | StackUsed: {d}B",
        .{ last_event_text, sim.tick_count(), metrics.used_bytes, metrics.free_bytes, metrics.fragmentation_percent, sim.stack_used_bytes() },
    );
    print_line_styled(content, row, status, theme.lesson_dim);
    row += 2;

    const table_win = content.child(.{
        .x_off = 0,
        .y_off = @intCast(row),
        .width = content.width,
        .height = @intCast(content.height -| row),
    });
    row += try draw_segment_table(table_win, frame_alloc, sim, null, null, null);

    row += 1;
    print_line_styled(content, row, "Map legend: T=text D=data B=bss .=heap-free 0-F=heap-alloc G=gap S=stack-used", theme.controls);
    row += 1;

    const map_start_row = row;
    const bytes_per_row: usize = 16;
    while (row < content.height) : (row += 1) {
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

        print_line_styled(content, row, line_buf.items, theme.map_dim);
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
                                    screen = .learn_menu;
                                    learn_menu_selected = 0;
                                },
                                1 => {
                                    screen = .sandbox;
                                    view_base = 0;
                                    sim.reset();
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
                    try render_lesson_placeholder(win, frame_alloc, selected_lesson);
            },
            .sandbox => try render_sandbox(win, frame_alloc, &sim, view_base),
        }

        try vx.render(tty_writer);
    }
}
