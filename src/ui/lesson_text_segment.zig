const std = @import("std");
const fmt = std.fmt;
const vaxis = @import("vaxis");
const sim_mod = @import("../sim.zig");
const theme = @import("../theme.zig");
const shell = @import("shell.zig");

const TextStep = struct {
    title: []const u8,
    description_lines: []const []const u8,
    key_takeaway: []const u8,
};

const text_steps = [_]TextStep{
    .{
        .title = "Pipeline Overview",
        .description_lines = &.{
            "Programs start as source text written by developers.",
            "Compilers translate source into machine instructions.",
            "Those instruction bytes are loaded into the Text segment.",
            "Execution then follows instruction addresses via the PC.",
        },
        .key_takeaway = "Text segment stores executable instruction bytes.",
    },
    .{
        .title = "C-like Source Example",
        .description_lines = &.{
            "This high-level function describes intent, not machine details.",
            "The compiler decides concrete registers and instruction forms.",
            "Still, this source maps to a tiny add routine in text memory.",
        },
        .key_takeaway = "Source code becomes executable bytes after compilation.",
    },
    .{
        .title = "Zig Source Equivalent",
        .description_lines = &.{
            "Different languages can express the same computation.",
            "This Zig function mirrors the C-like add example exactly.",
            "Both eventually compile into machine instructions in text.",
        },
        .key_takeaway = "Language differs, executable text-segment role is the same.",
    },
    .{
        .title = "Pseudo Assembly",
        .description_lines = &.{
            "Assembly is a readable form of machine-level instructions.",
            "Parameters move into registers before arithmetic operations.",
            "The return instruction ends control flow for this function.",
        },
        .key_takeaway = "Assembly exposes how high-level operations execute.",
    },
    .{
        .title = "Instruction Bytes in Text",
        .description_lines = &.{
            "Each instruction has a byte encoding in memory.",
            "The loader places these bytes in the text segment range.",
            "Addresses let CPU fetch instructions in execution order.",
        },
        .key_takeaway = "Text segment contains real byte encodings, not source text.",
    },
    .{
        .title = "Execution via Program Counter",
        .description_lines = &.{
            "The program counter points to the next instruction address.",
            "As instructions run, PC advances or jumps accordingly.",
            "Execution is a walk through text-segment instruction bytes.",
        },
        .key_takeaway = "CPU executes text segment by stepping instruction addresses.",
    },
    .{
        .title = "Permissions: Read/Execute",
        .description_lines = &.{
            "Text is typically readable and executable, not writable.",
            "This separation helps prevent accidental code corruption.",
            "It is also a core part of memory safety hardening.",
        },
        .key_takeaway = "Text segment is R-X to protect executable code.",
    },
    .{
        .title = "Recap",
        .description_lines = &.{
            "Source code compiles into machine instruction bytes.",
            "Those bytes live in a fixed text segment region.",
            "CPU executes by following instruction addresses (PC).",
        },
        .key_takeaway = "Text segment is where code lives and executes.",
    },
};

pub fn step_count() usize {
    return text_steps.len;
}

pub fn rebuild_state(sim: *sim_mod.Simulation, step_idx: usize) void {
    _ = step_idx;
    sim.reset();
}

pub fn step_color(step_idx: usize) vaxis.Cell.Style {
    return switch (step_idx) {
        0 => .{ .fg = .{ .rgb = .{ 190, 235, 255 } }, .bg = .{ .rgb = .{ 20, 36, 48 } } },
        1 => .{ .fg = .{ .rgb = .{ 255, 220, 160 } }, .bg = .{ .rgb = .{ 42, 30, 20 } } },
        2 => .{ .fg = .{ .rgb = .{ 180, 255, 210 } }, .bg = .{ .rgb = .{ 18, 40, 28 } } },
        3 => .{ .fg = .{ .rgb = .{ 220, 210, 255 } }, .bg = .{ .rgb = .{ 28, 24, 44 } } },
        4 => .{ .fg = .{ .rgb = .{ 255, 200, 190 } }, .bg = .{ .rgb = .{ 44, 26, 26 } } },
        5 => .{ .fg = .{ .rgb = .{ 180, 220, 255 } }, .bg = .{ .rgb = .{ 24, 32, 46 } } },
        6 => .{ .fg = .{ .rgb = .{ 255, 215, 170 } }, .bg = .{ .rgb = .{ 46, 32, 20 } } },
        else => .{ .fg = .{ .rgb = .{ 210, 210, 210 } }, .bg = .{ .rgb = .{ 24, 24, 24 } } },
    };
}

fn row_overlaps_focus(row_start: usize, row_end: usize, focus_start: usize, focus_end: usize) bool {
    return row_start < focus_end and focus_start < row_end;
}

fn visual_lines(step_idx: usize) []const []const u8 {
    return switch (step_idx) {
        0 => &[_][]const u8{
            "+----------------------------------------------------------+",
            "|                  TEXT SEGMENT PIPELINE                   |",
            "|   Source Code  ->  Compiler  ->  Instruction Bytes       |",
            "|        (C/Zig)      (backend)      (.text at addresses)  |",
            "|                                      -> Execute via PC   |",
            "+----------------------------------------------------------+",
        },
        1 => &[_][]const u8{
            "+----------------------------------------------------------+",
            "| C-like Source                                            |",
            "| int add(int a, int b) {                                  |",
            "|     return a + b;                                        |",
            "| }                                                        |",
            "+----------------------------------------------------------+",
        },
        2 => &[_][]const u8{
            "+----------------------------------------------------------+",
            "| Zig Source                                               |",
            "| fn add(a: i32, b: i32) i32 {                             |",
            "|     return a + b;                                        |",
            "| }                                                        |",
            "+----------------------------------------------------------+",
        },
        3 => &[_][]const u8{
            "+----------------------------------------------------------+",
            "| Pseudo Assembly                                          |",
            "| mov eax, edi            ; load a into accumulator        |",
            "| add eax, esi            ; add b                          |",
            "| ret                     ; return eax                     |",
            "+----------------------------------------------------------+",
        },
        4 => &[_][]const u8{
            "+----------------------------------------------------------+",
            "| Text Segment Bytes                                       |",
            "| 0x1000: 89 F8              mov eax, edi                  |",
            "| 0x1002: 01 F0              add eax, esi                  |",
            "| 0x1004: C3                 ret                           |",
            "+----------------------------------------------------------+",
        },
        5 => &[_][]const u8{
            "+----------------------------------------------------------+",
            "| Execution (Program Counter)                              |",
            "| PC -> 0x1000 : mov eax, edi                              |",
            "|      0x1002 : add eax, esi                               |",
            "|      0x1004 : ret                                        |",
            "+----------------------------------------------------------+",
        },
        6 => &[_][]const u8{
            "+----------------------------------------------------------+",
            "| Text Permissions                                         |",
            "| Segment: .text                                           |",
            "| Permissions: Read + Execute                              |",
            "| Write attempts blocked by memory protection              |",
            "+----------------------------------------------------------+",
        },
        else => &[_][]const u8{
            "+----------------------------------------------------------+",
            "| Recap                                                    |",
            "| source -> compiler -> instruction bytes                  |",
            "| bytes in .text -> CPU executes by program counter        |",
            "| .text stays fixed and protected as Read/Execute          |",
            "+----------------------------------------------------------+",
        },
    };
}

fn render_visual_panel(win: vaxis.Window, frame_alloc: std.mem.Allocator, step_idx: usize, start_row: usize, start_col: usize) !usize {
    if (start_row >= win.height or start_col >= win.width) return 0;

    const lines = visual_lines(step_idx);
    const accent = step_color(step_idx);

    var max_len: usize = 0;
    for (lines) |line| {
        if (line.len > max_len) max_len = line.len;
    }
    if (max_len == 0) return 0;

    if (start_col + max_len > win.width) return 0;
    const panel_width = max_len;

    var row = start_row;
    for (lines) |line| {
        if (row >= win.height) break;
        const text_line = try fmt.allocPrint(frame_alloc, "{s:<[1]}", .{ line, panel_width });
        const is_border = line.len > 0 and (line[0] == '+' or line[0] == '|');
        const style: vaxis.Cell.Style = if (is_border)
            .{ .fg = .{ .rgb = .{ 245, 245, 245 } }, .bg = accent.bg }
        else
            accent;
        shell.print_at(win, row, start_col, text_line, style);
        row += 1;
    }

    return row - start_row;
}

fn render_description_panel(win: vaxis.Window, frame_alloc: std.mem.Allocator, step_idx: usize, step: TextStep, start_row: usize, start_col: usize) !usize {
    if (start_row >= win.height or start_col >= win.width) return 0;

    const accent = step_color(step_idx);
    const panel_width = win.width - start_col;
    if (panel_width < 24) return 0;
    const inner_width = panel_width - 2;

    var row = start_row;
    const header_line = try fmt.allocPrint(frame_alloc, "|{s:<[1]}|", .{ "Description", inner_width });
    shell.print_at(win, row, start_col, header_line, .{ .fg = .{ .rgb = .{ 230, 245, 255 } }, .bg = accent.bg });
    row += 1;

    for (step.description_lines) |line| {
        if (row >= win.height) break;
        const clipped = if (line.len > inner_width) line[0..inner_width] else line;
        const text_line = try fmt.allocPrint(frame_alloc, "|{s:<[1]}|", .{ clipped, inner_width });
        shell.print_at(win, row, start_col, text_line, .{ .fg = .{ .rgb = .{ 210, 225, 238 } }, .bg = .{ .rgb = .{ 16, 22, 30 } } });
        row += 1;
    }

    if (row < win.height) {
        const spacer = try fmt.allocPrint(frame_alloc, "|{s:<[1]}|", .{ "", inner_width });
        shell.print_at(win, row, start_col, spacer, .{ .fg = .{ .rgb = .{ 180, 196, 208 } }, .bg = .{ .rgb = .{ 16, 22, 30 } } });
        row += 1;
    }

    if (row < win.height) {
        const inner_takeaway = if (inner_width > 15) inner_width - 15 else 0;
        const takeaway = try fmt.allocPrint(frame_alloc, "| Key takeaway: {s:<[1]}|", .{ step.key_takeaway, inner_takeaway });
        shell.print_at(win, row, start_col, takeaway, .{ .fg = accent.fg, .bg = accent.bg });
        row += 1;
    }

    return row - start_row;
}

fn render_visual_and_description(win: vaxis.Window, frame_alloc: std.mem.Allocator, step_idx: usize, step: TextStep, start_row: usize) !usize {
    const visual_width: usize = 60;
    const gap: usize = 2;
    const side_by_side = win.width >= (visual_width + gap + 32);

    if (side_by_side) {
        const visual_rows = try render_visual_panel(win, frame_alloc, step_idx, start_row, 2);
        const desc_start = 2 + visual_width + gap;
        const desc_rows = try render_description_panel(win, frame_alloc, step_idx, step, start_row, desc_start);
        return @max(visual_rows, desc_rows);
    }

    var used = try render_visual_panel(win, frame_alloc, step_idx, start_row, 2);
    used += 1;
    used += try render_description_panel(win, frame_alloc, step_idx, step, start_row + used, 2);
    return used;
}

pub fn render(win: vaxis.Window, frame_alloc: std.mem.Allocator, sim: *sim_mod.Simulation, step_idx: usize) !void {
    const clamped_step = if (step_idx < text_steps.len) step_idx else text_steps.len - 1;
    const step = text_steps[clamped_step];
    const segments = sim.segment_infos();
    const focus_start = segments[0].start;
    const focus_end = segments[0].end;

    const content = try shell.render_shell(
        win,
        frame_alloc,
        "Lesson: Text Segment",
        "See source transform into executable text-segment bytes",
        "n/-> next | b/<- back | r restart | m lessons | q quit",
    );

    var row: usize = 0;
    const title = try fmt.allocPrint(frame_alloc, "Text Segment | Step {d}/{d}", .{ clamped_step + 1, text_steps.len });
    shell.print_section_title(content, row, title);
    row += 1;

    shell.print_line_styled(content, row, step.title, .{ .fg = .{ .rgb = .{ 255, 230, 165 } } });
    row += 1;
    if (clamped_step == 0) {
        const intro_style: vaxis.Cell.Style = .{ .fg = .{ .rgb = .{ 235, 246, 255 } }, .bg = .{ .rgb = .{ 18, 30, 42 } } };
        shell.print_line_styled(content, row, "What You Will Learn", intro_style);
        row += 1;
        shell.print_line_styled(content, row, "How source code becomes executable instruction bytes in .text", theme.lesson_dim);
        row += 1;
        shell.print_line_styled(content, row, "How CPU follows those bytes through instruction addresses", theme.lesson_dim);
        row += 1;
    } else {
        row += 1;
    }

    row += 1;
    row += try render_visual_and_description(content, frame_alloc, clamped_step, step, row);

    row += 1;
    shell.print_line_styled(content, row, "Map legend: T=text D=data B=bss .=heap-free 0-F=heap-alloc G=gap S=stack-used", theme.controls);
    row += 1;

    const bytes_per_row: usize = 16;
    const aligned_focus = focus_start & ~@as(usize, 0xF);
    const context_rows: usize = 1;
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
