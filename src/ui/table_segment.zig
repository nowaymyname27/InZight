const std = @import("std");
const fmt = std.fmt;
const vaxis = @import("vaxis");
const widgets = vaxis.widgets;
const sim_mod = @import("../sim.zig");

const SegmentTableRow = struct {
    address_range: []const u8,
    segment: []const u8,
    permissions: []const u8,
    growth: []const u8,
};

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

pub fn draw_segment_table(
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
