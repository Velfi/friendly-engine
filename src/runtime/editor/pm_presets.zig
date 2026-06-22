const std = @import("std");
const friendly_engine = @import("friendly_engine");
const project_editor_mode_config = @import("project_editor_mode_config.zig");

pub const GemPreset = struct {
    name: []const u8,
    modules: []const []const u8,
    builtin: bool,
};

const minimal_modules = [_][]const u8{
    friendly_engine.modules.ecs.module_name,
    friendly_engine.modules.persistence.module_name,
    friendly_engine.modules.luajit.module_name,
    friendly_engine.modules.core_ui.module_name,
    friendly_engine.modules.keyboard_mouse_controller.module_name,
};

const catalog_entries = friendly_engine.modules.moduleCatalogEntries();
const catalog_names = blk: {
    var names: [catalog_entries.len][]const u8 = undefined;
    for (catalog_entries, 0..) |entry, idx| names[idx] = entry.hooks.name;
    break :blk names;
};

pub fn builtinPresets() [2]GemPreset {
    return .{
        .{ .name = "Minimal", .modules = &minimal_modules, .builtin = true },
        .{ .name = "Full", .modules = catalogModuleNames(), .builtin = true },
    };
}

pub fn catalogModuleNames() []const []const u8 {
    return &catalog_names;
}

pub fn hasEditorGem(modules: []const []const u8) bool {
    return project_editor_mode_config.hasAnyEditorGem(modules);
}

pub fn findPreset(state: anytype, name: []const u8) ?GemPreset {
    const trimmed = std.mem.trim(u8, name, " \t\r\n");
    if (trimmed.len == 0) return null;
    const builtins = builtinPresets();
    for (builtins) |preset| {
        if (std.mem.eql(u8, preset.name, trimmed)) return preset;
    }
    for (state.user_presets.items) |preset| {
        if (std.mem.eql(u8, preset.name, trimmed)) return preset;
    }
    return null;
}

pub fn dupeModuleList(allocator: std.mem.Allocator, modules: []const []const u8) ![][]u8 {
    var owned = try allocator.alloc([]u8, modules.len);
    var i: usize = 0;
    errdefer {
        while (i > 0) {
            i -= 1;
            allocator.free(owned[i]);
        }
        allocator.free(owned);
    }
    for (modules) |module| {
        owned[i] = try allocator.dupe(u8, module);
        i += 1;
    }
    return owned;
}

pub fn freeOwnedPreset(allocator: std.mem.Allocator, preset: *GemPreset) void {
    allocator.free(@constCast(preset.name));
    for (preset.modules) |module| allocator.free(@constCast(module));
    allocator.free(@constCast(preset.modules));
    preset.* = undefined;
}

test "builtins include minimal and full presets" {
    const builtins = builtinPresets();
    try std.testing.expectEqualStrings("Minimal", builtins[0].name);
    try std.testing.expect(!hasEditorGem(builtins[0].modules));
    try std.testing.expectEqualStrings("Full", builtins[1].name);
    try std.testing.expectEqual(friendly_engine.modules.moduleCatalogEntries().len, builtins[1].modules.len);
    try std.testing.expect(hasEditorGem(builtins[1].modules));
}

test "findPreset hits builtins and misses unknown names" {
    const State = struct { user_presets: std.ArrayList(GemPreset) };
    var state = State{ .user_presets = .empty };
    try std.testing.expect(findPreset(&state, "Minimal") != null);
    try std.testing.expect(findPreset(&state, "Missing") == null);
}
