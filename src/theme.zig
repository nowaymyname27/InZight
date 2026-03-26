const vaxis = @import("vaxis");

pub const header: vaxis.Cell.Style = .{ .fg = .{ .rgb = .{ 20, 28, 36 } }, .bg = .{ .rgb = .{ 110, 200, 255 } } };
pub const subtitle: vaxis.Cell.Style = .{ .fg = .{ .rgb = .{ 150, 175, 195 } } };
pub const controls: vaxis.Cell.Style = .{ .fg = .{ .rgb = .{ 130, 145, 160 } } };
pub const panel_title: vaxis.Cell.Style = .{ .fg = .{ .rgb = .{ 120, 210, 255 } } };
pub const item: vaxis.Cell.Style = .{ .fg = .{ .rgb = .{ 220, 230, 240 } } };
pub const selected: vaxis.Cell.Style = .{ .fg = .{ .rgb = .{ 8, 14, 18 } }, .bg = .{ .rgb = .{ 115, 210, 255 } } };
pub const lesson_dim: vaxis.Cell.Style = .{ .fg = .{ .rgb = .{ 200, 208, 214 } } };
pub const map_focus: vaxis.Cell.Style = .{ .fg = .{ .rgb = .{ 245, 250, 255 } }, .bg = .{ .rgb = .{ 26, 36, 48 } } };
pub const map_dim: vaxis.Cell.Style = .{ .fg = .{ .rgb = .{ 125, 140, 155 } } };
