const std = @import("std");
const vaxis = @import("vaxis");
const app = @import("../app.zig");
const shell = @import("shell.zig");

pub fn render(win: vaxis.Window, frame_alloc: std.mem.Allocator, topic: app.LessonTopic) !void {
    const content = try shell.render_shell(
        win,
        frame_alloc,
        "Lesson",
        "Guided visuals for this topic are coming next",
        "m back to lesson menu | q quit",
    );

    var row: usize = 1;
    var title_buf: [128]u8 = undefined;
    const title = std.fmt.bufPrint(&title_buf, "Lesson: {s}", .{topic.title()}) catch topic.title();
    shell.print_section_title(content, row, title);
    row += 2;
    shell.print_line(content, row, "This lesson is wired into the app flow.");
    row += 1;
    shell.print_line(content, row, "Next update will add guided simulation + topic-specific visuals.");
}
