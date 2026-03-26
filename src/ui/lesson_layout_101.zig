const std = @import("std");
const fmt = std.fmt;
const vaxis = @import("vaxis");
const sim_mod = @import("../sim.zig");
const theme = @import("../theme.zig");
const shell = @import("shell.zig");
const table_segment = @import("table_segment.zig");

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
    .{ .title = "Process Memory Overview", .message = "This is a simulated process layout from low to high addresses.", .action = .none, .focus_segment_start = 0, .focus_segment_end = 5 },
    .{ .title = "Text Segment", .message = "Text stores machine code and is fixed Read/Execute.", .action = .none, .focus_segment_start = 0, .focus_segment_end = 0 },
    .{ .title = "Data + BSS Segments", .message = "Data and BSS store globals/statics and stay fixed Read/Write.", .action = .none, .focus_segment_start = 1, .focus_segment_end = 2 },
    .{ .title = "Heap Growth (Upward)", .message = "A heap allocation adds bytes at higher addresses (upward).", .action = .heap_alloc, .focus_segment_start = 3, .focus_segment_end = 3 },
    .{ .title = "Stack Growth (Downward)", .message = "A function call pushes a frame to lower addresses (downward).", .action = .stack_call, .focus_segment_start = 5, .focus_segment_end = 5 },
    .{ .title = "The Gap", .message = "Heap and stack move toward each other; this gap is your remaining room.", .action = .gap_pressure, .focus_segment_start = 4, .focus_segment_end = 4 },
    .{ .title = "Recap", .message = "Text/Data/BSS are fixed. Heap grows up. Stack grows down.", .action = .none, .focus_segment_start = 0, .focus_segment_end = 5 },
};

pub fn step_count() usize {
    return memory_layout_steps.len;
}

pub fn apply_step_action(sim: *sim_mod.Simulation, step_idx: usize) void {
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

pub fn rebuild_state(sim: *sim_mod.Simulation, step_idx: usize) void {
    sim.reset();
    if (memory_layout_steps.len == 0) return;

    const clamped_step = if (step_idx < memory_layout_steps.len) step_idx else memory_layout_steps.len - 1;
    var i: usize = 0;
    while (i <= clamped_step) : (i += 1) {
        apply_step_action(sim, i);
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

pub fn step_color(step_idx: usize) vaxis.Cell.Style {
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
    const accent = step_color(step_idx);

    const title_line = try fmt.allocPrint(frame_alloc, "|{s:<[1]}|", .{ title, inner_width });
    shell.print_at(win, start_row, start_col, title_line, .{ .fg = .{ .rgb = .{ 255, 245, 160 } }, .bg = accent.bg });

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
        shell.print_at(win, row, start_col, padded, line_style);
        row += 1;
    }

    return 1 + max_lines;
}

pub fn render(win: vaxis.Window, frame_alloc: std.mem.Allocator, sim: *sim_mod.Simulation, step_idx: usize) !void {
    const clamped_step = if (step_idx < memory_layout_steps.len) step_idx else memory_layout_steps.len - 1;
    const step = memory_layout_steps[clamped_step];
    const segments = sim.segment_infos();
    const focus_start = segments[step.focus_segment_start].start;
    const focus_end = segments[step.focus_segment_end].end;

    const content = try shell.render_shell(
        win,
        frame_alloc,
        "Lesson: Memory Layout 101",
        "Step through segment behavior with synchronized visuals",
        "n/-> next | b/<- back | r restart | m lessons | q quit",
    );

    var row: usize = 0;
    const title = try fmt.allocPrint(frame_alloc, "Memory Layout 101 | Step {d}/{d}", .{ clamped_step + 1, memory_layout_steps.len });
    shell.print_section_title(content, row, title);
    row += 1;

    shell.print_line_styled(content, row, step.title, .{ .fg = .{ .rgb = .{ 255, 230, 165 } } });
    row += 1;
    shell.print_line_styled(content, row, step.message, theme.lesson_dim);
    row += 2;

    const table_win = content.child(.{
        .x_off = 0,
        .y_off = @intCast(row),
        .width = content.width,
        .height = @intCast(content.height -| row),
    });
    row += try table_segment.draw_segment_table(table_win, frame_alloc, sim, step.focus_segment_start, step.focus_segment_end + 1, step_color(clamped_step));

    row += 1;
    row += try render_ascii_panel(content, frame_alloc, clamped_step, row, 2);

    row += 1;
    shell.print_line_styled(content, row, "Map legend: T=text D=data B=bss .=heap-free 0-F=heap-alloc G=gap S=stack-used", theme.controls);
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

        shell.print_line_styled(content, row, line_buf.items, line_style);
    }
}
