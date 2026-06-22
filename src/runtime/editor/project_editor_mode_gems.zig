const std = @import("std");
const friendly_engine = @import("friendly_engine");
const project_editor_mode_config = @import("project_editor_mode_config.zig");
const ui_architecture = @import("project_editor_ui_architecture.zig");
const ui_layout = @import("project_editor_ui_layout.zig");
const ui_life = @import("project_editor_ui_life.zig");
const ui_prop = @import("project_editor_ui_prop.zig");
const ui_world = @import("project_editor_ui_world.zig");

pub fn buildRegistry(
    allocator: std.mem.Allocator,
    enabled_modules: []const []const u8,
) !project_editor_mode_config.EditorRegistry {
    var registry = project_editor_mode_config.EditorRegistry.init(allocator);
    errdefer registry.deinit();

    if (project_editor_mode_config.moduleEnabled(enabled_modules, friendly_engine.modules.editor_world.module_name)) {
        try ui_world.registerEditor(&registry);
    }
    if (project_editor_mode_config.moduleEnabled(enabled_modules, friendly_engine.modules.editor_layout.module_name)) {
        try ui_layout.registerEditor(&registry);
    }
    if (project_editor_mode_config.moduleEnabled(enabled_modules, friendly_engine.modules.editor_architecture.module_name)) {
        try ui_architecture.registerEditor(&registry);
    }
    if (project_editor_mode_config.moduleEnabled(enabled_modules, friendly_engine.modules.editor_prop.module_name)) {
        try ui_prop.registerEditor(&registry);
    }
    if (project_editor_mode_config.moduleEnabled(enabled_modules, friendly_engine.modules.editor_life.module_name)) {
        try ui_life.registerEditor(&registry);
    }

    if (registry.modes.items.len == 0) return error.NoEditorModesEnabled;
    return registry;
}

pub fn flagsFromEnabledModules(
    allocator: std.mem.Allocator,
    enabled_modules: []const []const u8,
) !project_editor_mode_config.ModeFlags {
    var registry = try buildRegistry(allocator, enabled_modules);
    defer registry.deinit();
    return registry.flags();
}

test "enabled editor gems register only their capabilities" {
    var registry = try buildRegistry(std.testing.allocator, &.{
        friendly_engine.modules.editor_layout.module_name,
    });
    defer registry.deinit();
    try std.testing.expectEqual(@as(usize, 1), registry.modes.items.len);
    try std.testing.expectEqual(.layout, registry.modes.items[0].mode);
}
