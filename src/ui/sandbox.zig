const std = @import("std");
const fmt = std.fmt;
const vaxis = @import("vaxis");
const sim_mod = @import("../sim.zig");
const theme = @import("../theme.zig");
const shell = @import("shell.zig");
const table_segment = @import("table_segment.zig");

pub fn render(win: vaxis.Window, frame_alloc: std.mem.Allocator, sim: *sim_mod.Simulation, view_base: usize) !void {
    const content = try shell.render_shell(
        win,
        frame_alloc,
        "Simulation Sandbox",
        "Explore heap/stack behavior with manual and scripted actions",
        "n/space step | a alloc | f free | c call | x return | j/k scroll | r reset | m menu | q quit",
    );

    var row: usize = 0;
    shell.print_section_title(content, row, "Simulation Sandbox");
    row += 1;

    const last_event_text = try sim.describe_last_event(frame_alloc);
    const metrics = sim.heap_metrics();
    const status = try fmt.allocPrint(
        frame_alloc,
        "Last: {s} | Tick: {d} | HeapUsed: {d}B | HeapFree: {d}B | Frag: {d}% | StackUsed: {d}B",
        .{ last_event_text, sim.tick_count(), metrics.used_bytes, metrics.free_bytes, metrics.fragmentation_percent, sim.stack_used_bytes() },
    );
    shell.print_line_styled(content, row, status, theme.lesson_dim);
    row += 2;

    const table_win = content.child(.{
        .x_off = 0,
        .y_off = @intCast(row),
        .width = content.width,
        .height = @intCast(content.height -| row),
    });
    row += try table_segment.draw_segment_table(table_win, frame_alloc, sim, null, null, null);

    row += 1;
    shell.print_line_styled(content, row, "Map legend: T=text D=data B=bss .=heap-free 0-F=heap-alloc G=gap S=stack-used", theme.controls);
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

        shell.print_line_styled(content, row, line_buf.items, theme.map_dim);
    }
}
