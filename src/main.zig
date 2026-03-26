const std = @import("std");
const vaxis = @import("vaxis");
const heap = std.heap;

const sim_mod = @import("sim.zig");
const app = @import("app.zig");
const menu_ui = @import("ui/menu.zig");
const sandbox_ui = @import("ui/sandbox.zig");
const lesson_layout_101 = @import("ui/lesson_layout_101.zig");
const lesson_placeholder = @import("ui/lesson_placeholder.zig");

const AppEvent = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

fn is_enter_pressed(key: vaxis.Key) bool {
    return key.matches(vaxis.Key.enter, .{}) or key.matches('\r', .{});
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
    var screen: app.Screen = .main_menu;
    var main_menu_selected: usize = 0;
    var learn_menu_selected: usize = 0;
    var selected_lesson: app.LessonTopic = .memory_layout;
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
                            if (main_menu_selected + 1 < app.main_menu_items.len) main_menu_selected += 1;
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
                            if (learn_menu_selected + 1 < app.learn_menu_items.len) learn_menu_selected += 1;
                        }
                        if (key.matches(vaxis.Key.up, .{}) or key.matches('k', .{}) or key.matches('w', .{})) {
                            learn_menu_selected -|= 1;
                        }
                        if (key.matches('m', .{})) {
                            screen = .main_menu;
                        }
                        if (is_enter_pressed(key)) {
                            selected_lesson = app.learn_menu_items[learn_menu_selected];
                            screen = .lesson;
                            lesson_step = 0;
                            if (selected_lesson == .memory_layout)
                                lesson_layout_101.rebuild_state(&sim, lesson_step)
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
                                lesson_layout_101.rebuild_state(&sim, lesson_step);
                            }
                            if (key.matches('n', .{}) or key.matches(' ', .{}) or key.matches(vaxis.Key.right, .{})) {
                                if (lesson_step + 1 < lesson_layout_101.step_count()) {
                                    lesson_step += 1;
                                    lesson_layout_101.rebuild_state(&sim, lesson_step);
                                }
                            }
                            if (key.matches('b', .{}) or key.matches(vaxis.Key.left, .{})) {
                                if (lesson_step > 0) {
                                    lesson_step -= 1;
                                    lesson_layout_101.rebuild_state(&sim, lesson_step);
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
            .main_menu => try menu_ui.render_main_menu(win, frame_alloc, main_menu_selected),
            .learn_menu => try menu_ui.render_learn_menu(win, frame_alloc, learn_menu_selected),
            .lesson => {
                if (selected_lesson == .memory_layout)
                    try lesson_layout_101.render(win, frame_alloc, &sim, lesson_step)
                else
                    try lesson_placeholder.render(win, frame_alloc, selected_lesson);
            },
            .sandbox => try sandbox_ui.render(win, frame_alloc, &sim, view_base),
        }

        try vx.render(tty_writer);
    }
}
