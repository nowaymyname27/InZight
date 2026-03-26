const std = @import("std");
const vaxis = @import("vaxis");
const fmt = std.fmt;
const theme = @import("../theme.zig");

pub fn print_line(win: vaxis.Window, row: usize, text: []const u8) void {
    const row_win = win.child(.{
        .x_off = 0,
        .y_off = @intCast(row),
        .width = win.width,
        .height = 1,
    });
    _ = row_win.print(&.{.{ .text = text, .style = .{} }}, .{});
}

pub fn print_line_styled(win: vaxis.Window, row: usize, text: []const u8, style: vaxis.Cell.Style) void {
    const row_win = win.child(.{
        .x_off = 0,
        .y_off = @intCast(row),
        .width = win.width,
        .height = 1,
    });
    _ = row_win.print(&.{.{ .text = text, .style = style }}, .{});
}

pub fn print_at(win: vaxis.Window, row: usize, col: usize, text: []const u8, style: vaxis.Cell.Style) void {
    if (col >= win.width or row >= win.height) return;
    const row_win = win.child(.{
        .x_off = @intCast(col),
        .y_off = @intCast(row),
        .width = @intCast(win.width - col),
        .height = 1,
    });
    _ = row_win.print(&.{.{ .text = text, .style = style }}, .{});
}

pub fn render_shell(win: vaxis.Window, frame_alloc: std.mem.Allocator, context: []const u8, subtitle: []const u8, controls: []const u8) !vaxis.Window {
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

pub fn print_section_title(win: vaxis.Window, row: usize, title: []const u8) void {
    print_line_styled(win, row, title, theme.panel_title);
}
