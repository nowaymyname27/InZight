const std = @import("std");
const fmt = std.fmt;
const vaxis = @import("vaxis");
const app = @import("../app.zig");
const theme = @import("../theme.zig");
const shell = @import("shell.zig");

pub fn render_main_menu(win: vaxis.Window, frame_alloc: std.mem.Allocator, selected: usize) !void {
    const content = try shell.render_shell(
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

    shell.print_at(content, menu_start_row + 0, title_col, title, .{ .fg = .{ .rgb = .{ 120, 220, 255 } } });
    shell.print_at(content, menu_start_row + 1, subtitle_col, subtitle, theme.subtitle);
    shell.print_at(content, menu_start_row + 3, if (content.width > 9) (content.width - 9) / 2 else 0, "Main Menu", theme.panel_title);

    for (app.main_menu_items, 0..) |item, idx| {
        const line = if (idx == selected)
            try fmt.allocPrint(frame_alloc, ">> [ {s} ]", .{item})
        else
            try fmt.allocPrint(frame_alloc, "   {s}", .{item});
        const col = if (content.width > line.len) (content.width - line.len) / 2 else 0;
        shell.print_at(content, menu_start_row + 5 + idx, col, line, if (idx == selected) theme.selected else theme.item);
    }

    const selected_label = try fmt.allocPrint(frame_alloc, "Selected: {s}", .{app.main_menu_items[selected]});
    const selected_col = if (content.width > selected_label.len) (content.width - selected_label.len) / 2 else 0;
    shell.print_at(content, menu_start_row + 10, selected_col, selected_label, .{ .fg = .{ .rgb = .{ 165, 225, 190 } } });
}

pub fn render_learn_menu(win: vaxis.Window, frame_alloc: std.mem.Allocator, selected: usize) !void {
    const content = try shell.render_shell(
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

    shell.print_at(content, menu_start_row + 0, title_col, title, .{ .fg = .{ .rgb = .{ 120, 220, 255 } } });
    shell.print_at(content, menu_start_row + 1, subtitle_col, subtitle, theme.subtitle);

    for (app.learn_menu_items, 0..) |topic, idx| {
        const line = if (idx == selected)
            try fmt.allocPrint(frame_alloc, ">> [ {s} ]", .{topic.title()})
        else
            try fmt.allocPrint(frame_alloc, "   {s}", .{topic.title()});
        const col = if (content.width > line.len) (content.width - line.len) / 2 else 0;
        shell.print_at(content, menu_start_row + 4 + idx, col, line, if (idx == selected) theme.selected else theme.item);
    }

    const selected_label = try fmt.allocPrint(frame_alloc, "Selected: {s}", .{app.learn_menu_items[selected].title()});
    const selected_col = if (content.width > selected_label.len) (content.width - selected_label.len) / 2 else 0;
    shell.print_at(content, menu_start_row + 11, selected_col, selected_label, .{ .fg = .{ .rgb = .{ 165, 225, 190 } } });
}
