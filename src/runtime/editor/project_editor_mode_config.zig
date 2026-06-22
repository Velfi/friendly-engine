const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const project_editor_types = @import("project_editor_types.zig");

const command_ids = shared.editor_command_ids;
const EditorMode = project_editor_types.EditorMode;

pub const mode_count = 5;
pub const ModeFlags = [mode_count]bool;

pub const EditorModeDesc = struct {
    mode: EditorMode,
    label: []const u8,
    command_id: []const u8,
    section: []const u8,
    source: []const u8,
    module_name: []const u8,
    toolbar_width: f32,
};

pub const all_mode_descs = [_]EditorModeDesc{
    .{
        .mode = .world_creation,
        .label = "World",
        .command_id = command_ids.mode_world_creation,
        .section = "world creation",
        .source = "src/runtime/editor/project_editor_ui_world.zig",
        .module_name = friendly_engine.modules.editor_world.module_name,
        .toolbar_width = 470,
    },
    .{
        .mode = .layout,
        .label = "Layout",
        .command_id = command_ids.mode_layout,
        .section = "layout",
        .source = "src/runtime/editor/project_editor_ui_layout.zig",
        .module_name = friendly_engine.modules.editor_layout.module_name,
        .toolbar_width = 220,
    },
    .{
        .mode = .architecture_creation,
        .label = "Architecture",
        .command_id = command_ids.mode_architecture_creation,
        .section = "architecture creation",
        .source = "src/runtime/editor/project_editor_ui_architecture.zig",
        .module_name = friendly_engine.modules.editor_architecture.module_name,
        .toolbar_width = 860,
    },
    .{
        .mode = .prop_creation,
        .label = "Prop",
        .command_id = command_ids.mode_prop_creation,
        .section = "prop creation",
        .source = "src/runtime/editor/project_editor_ui_prop.zig",
        .module_name = friendly_engine.modules.editor_prop.module_name,
        .toolbar_width = 700,
    },
    .{
        .mode = .life,
        .label = "Life",
        .command_id = command_ids.mode_life,
        .section = "life",
        .source = "src/runtime/editor/project_editor_ui_life.zig",
        .module_name = friendly_engine.modules.editor_life.module_name,
        .toolbar_width = 580,
    },
};

pub const EditorRegistry = struct {
    allocator: std.mem.Allocator,
    modes: std.ArrayList(EditorModeDesc),

    pub fn init(allocator: std.mem.Allocator) EditorRegistry {
        return .{ .allocator = allocator, .modes = .empty };
    }

    pub fn deinit(self: *EditorRegistry) void {
        self.modes.deinit(self.allocator);
    }

    pub fn registerMode(self: *EditorRegistry, desc: EditorModeDesc) !void {
        for (self.modes.items) |existing| {
            if (existing.mode == desc.mode) return error.EditorModeAlreadyRegistered;
            if (std.mem.eql(u8, existing.command_id, desc.command_id)) return error.EditorModeCommandAlreadyRegistered;
        }
        try self.modes.append(self.allocator, desc);
    }

    pub fn flags(self: *const EditorRegistry) ModeFlags {
        var out = emptyFlags();
        for (self.modes.items) |desc| out[modeIndex(desc.mode)] = true;
        return out;
    }
};

pub fn defaultFlags() ModeFlags {
    return .{ true, true, true, true, true };
}

pub fn emptyFlags() ModeFlags {
    return .{ false, false, false, false, false };
}

pub fn flagsFromEnabledModules(enabled_modules: []const []const u8) !ModeFlags {
    var flags = emptyFlags();
    var any = false;
    for (all_mode_descs) |desc| {
        if (moduleEnabled(enabled_modules, desc.module_name)) {
            flags[modeIndex(desc.mode)] = true;
            any = true;
        }
    }
    if (!any) return error.NoEditorModesEnabled;
    return flags;
}

pub fn flagsFromEnabledModulesWithAllocator(
    allocator: std.mem.Allocator,
    enabled_modules: []const []const u8,
) !ModeFlags {
    var registry = EditorRegistry.init(allocator);
    defer registry.deinit();
    for (all_mode_descs) |desc| {
        if (moduleEnabled(enabled_modules, desc.module_name)) {
            try registry.registerMode(desc);
        }
    }
    if (registry.modes.items.len == 0) return error.NoEditorModesEnabled;
    return registry.flags();
}

pub fn modeEnabled(flags: ModeFlags, mode: EditorMode) bool {
    return flags[modeIndex(mode)];
}

pub fn firstEnabledMode(flags: ModeFlags) ?EditorMode {
    for (all_mode_descs) |desc| {
        if (modeEnabled(flags, desc.mode)) return desc.mode;
    }
    return null;
}

pub fn descForMode(mode: EditorMode) *const EditorModeDesc {
    for (&all_mode_descs) |*desc| {
        if (desc.mode == mode) return desc;
    }
    unreachable;
}

pub fn descForCommand(command_id: []const u8) ?*const EditorModeDesc {
    for (&all_mode_descs) |*desc| {
        if (std.mem.eql(u8, desc.command_id, command_id)) return desc;
    }
    return null;
}

pub fn modeIndex(mode: EditorMode) usize {
    return switch (mode) {
        .world_creation => 0,
        .layout => 1,
        .architecture_creation => 2,
        .prop_creation => 3,
        .life => 4,
    };
}

pub fn hasAnyEditorGem(enabled_modules: []const []const u8) bool {
    for (all_mode_descs) |desc| {
        if (moduleEnabled(enabled_modules, desc.module_name)) return true;
    }
    return false;
}

pub fn moduleEnabled(enabled_modules: []const []const u8, module_name: []const u8) bool {
    for (enabled_modules) |enabled| {
        if (std.mem.eql(u8, enabled, module_name)) return true;
    }
    return false;
}

test "editor registry rejects duplicate mode ids" {
    var registry = EditorRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.registerMode(all_mode_descs[0]);
    try std.testing.expectError(error.EditorModeAlreadyRegistered, registry.registerMode(all_mode_descs[0]));
}

test "editor registry rejects duplicate command ids" {
    var registry = EditorRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.registerMode(all_mode_descs[0]);
    var duplicate = all_mode_descs[1];
    duplicate.command_id = all_mode_descs[0].command_id;
    try std.testing.expectError(error.EditorModeCommandAlreadyRegistered, registry.registerMode(duplicate));
}

test "configs without editor gems enable no editor modes" {
    try std.testing.expectError(error.NoEditorModesEnabled, flagsFromEnabledModulesWithAllocator(std.testing.allocator, &.{
        friendly_engine.modules.physics3d.module_name,
        friendly_engine.modules.core_ui.module_name,
    }));
}

test "explicit editor gems hide omitted modes" {
    const flags = try flagsFromEnabledModulesWithAllocator(std.testing.allocator, &.{
        friendly_engine.modules.editor_layout.module_name,
    });
    try std.testing.expect(!modeEnabled(flags, .world_creation));
    try std.testing.expect(modeEnabled(flags, .layout));
    try std.testing.expect(!modeEnabled(flags, .architecture_creation));
    try std.testing.expect(!modeEnabled(flags, .prop_creation));
    try std.testing.expect(!modeEnabled(flags, .life));
}
