pub const Screen = enum {
    main_menu,
    learn_menu,
    sandbox,
    lesson,
};

pub const LessonTopic = enum {
    memory_layout,
    text_segment,
    data_bss,
    heap,
    stack,
    gap,

    pub fn title(self: LessonTopic) []const u8 {
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

pub const main_menu_items = [_][]const u8{
    "Learn Memory Sections",
    "Simulation Sandbox",
    "Quit",
};

pub const learn_menu_items = [_]LessonTopic{
    .memory_layout,
    .text_segment,
    .data_bss,
    .heap,
    .stack,
    .gap,
};
