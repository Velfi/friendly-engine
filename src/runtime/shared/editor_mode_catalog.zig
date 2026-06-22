const command_ids = @import("editor_command_ids.zig");

pub const Entry = struct {
    id: []const u8,
    label: []const u8,
    module_name: []const u8,
    command_id: []const u8,
    section: []const u8,
    source: []const u8,
    enabled_by_default: bool,
};

pub const entries = [_]Entry{
    .{
        .id = "world_creation",
        .label = "World",
        .module_name = "gem.editor_world",
        .command_id = command_ids.mode_world_creation,
        .section = "world creation",
        .source = "src/runtime/editor/project_editor_ui_world.zig",
        .enabled_by_default = true,
    },
    .{
        .id = "layout",
        .label = "Layout",
        .module_name = "gem.editor_layout",
        .command_id = command_ids.mode_layout,
        .section = "layout",
        .source = "src/runtime/editor/project_editor_ui_layout.zig",
        .enabled_by_default = true,
    },
    .{
        .id = "architecture_creation",
        .label = "Architecture",
        .module_name = "gem.editor_architecture",
        .command_id = command_ids.mode_architecture_creation,
        .section = "architecture creation",
        .source = "src/runtime/editor/project_editor_ui_architecture.zig",
        .enabled_by_default = true,
    },
    .{
        .id = "prop_creation",
        .label = "Prop",
        .module_name = "gem.editor_prop",
        .command_id = command_ids.mode_prop_creation,
        .section = "prop creation",
        .source = "src/runtime/editor/project_editor_ui_prop.zig",
        .enabled_by_default = true,
    },
    .{
        .id = "life",
        .label = "Life",
        .module_name = "gem.editor_life",
        .command_id = command_ids.mode_life,
        .section = "life",
        .source = "src/runtime/editor/project_editor_ui_life.zig",
        .enabled_by_default = true,
    },
};
