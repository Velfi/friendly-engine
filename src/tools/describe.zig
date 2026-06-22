const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const modules = friendly_engine.modules;
const framework = friendly_engine.framework;

pub const EngineDescribe = struct {
    schema_version: u16 = 1,
    runtime_targets: []const []const u8,
    modules: []ModuleEntry,
    components: []ComponentEntry,
    requests: []RequestEntry,
    editor_modes: []const EditorModeEntry,
    editor_screens: []const EditorScreenEntry,
    editor_commands: []const EditorCommandEntry,

    pub const ModuleEntry = struct {
        name: []const u8,
        dependencies: []const []const u8,
        enabled_by_default: bool,
    };

    pub const ComponentEntry = struct {
        name: []const u8,
        fields: []FieldEntry,
    };

    pub const FieldEntry = struct {
        name: []const u8,
        kind: []const u8,
    };

    pub const RequestEntry = struct {
        name: []const u8,
        description: []const u8,
    };

    pub const EditorModeEntry = shared.editor_mode_catalog.Entry;

    pub const EditorScreenEntry = struct {
        name: []const u8,
        builder: []const u8,
        sections: []const []const u8,
    };

    pub const EditorCommandEntry = struct {
        id: []const u8,
        label: []const u8,
        screen: []const u8,
        section: []const u8,
        source: []const u8,
    };

    pub fn deinit(self: *EngineDescribe, allocator: std.mem.Allocator) void {
        for (self.components) |component| {
            allocator.free(component.fields);
        }
        for (self.requests) |request| {
            allocator.free(request.name);
            allocator.free(request.description);
        }
        allocator.free(self.components);
        allocator.free(self.modules);
        allocator.free(self.requests);
        allocator.free(self.editor_commands);
        self.* = undefined;
    }
};

pub fn buildDescribeDocument(allocator: std.mem.Allocator) !EngineDescribe {
    const catalog = modules.moduleCatalogEntries();
    var module_entries = try allocator.alloc(EngineDescribe.ModuleEntry, catalog.len);
    for (catalog, 0..) |desc, idx| {
        module_entries[idx] = .{
            .name = desc.hooks.name,
            .dependencies = desc.hooks.dependencies,
            .enabled_by_default = desc.enabled_by_default,
        };
    }

    var component_registry = framework.components.ComponentRegistry.init(allocator);
    defer component_registry.deinit();
    try framework.components.registerBuiltinComponents(&component_registry);

    var component_entries = try allocator.alloc(EngineDescribe.ComponentEntry, component_registry.entries().len);
    for (component_registry.entries(), 0..) |component, idx| {
        var fields = try allocator.alloc(EngineDescribe.FieldEntry, component.fields.len);
        for (component.fields, 0..) |field, fi| {
            fields[fi] = .{
                .name = field.name,
                .kind = fieldKindName(field.kind),
            };
        }
        component_entries[idx] = .{
            .name = component.name,
            .fields = fields,
        };
    }

    var graph = try modules.initBuiltinGraph(allocator);
    defer graph.deinit();
    try graph.resolveAll();
    var services = modules.ServiceRegistry.init(allocator);
    defer services.deinit();
    try graph.registerAll(&services);
    try framework.introspection.registerIntrospection(&services);

    const request_catalog = services.catalogEntries();
    var request_entries = try allocator.alloc(EngineDescribe.RequestEntry, request_catalog.len + shared.editor_control_commands.entries.len);
    for (request_catalog, 0..) |entry, idx| {
        const owned_name = try allocator.dupe(u8, entry.name);
        errdefer allocator.free(owned_name);
        const owned_description = try allocator.dupe(u8, entry.description);
        errdefer allocator.free(owned_description);
        request_entries[idx] = .{
            .name = owned_name,
            .description = owned_description,
        };
    }
    for (shared.editor_control_commands.entries, 0..) |entry, idx| {
        const owned_name = try allocator.dupe(u8, entry.command_name);
        errdefer allocator.free(owned_name);
        const owned_description = try allocator.dupe(u8, entry.description);
        errdefer allocator.free(owned_description);
        request_entries[request_catalog.len + idx] = .{
            .name = owned_name,
            .description = owned_description,
        };
    }

    var editor_commands = try allocator.alloc(EngineDescribe.EditorCommandEntry, shared.editor_command_catalog.entries.len);
    for (shared.editor_command_catalog.entries, 0..) |entry, idx| {
        editor_commands[idx] = .{
            .id = entry.id,
            .label = entry.label,
            .screen = entry.screen,
            .section = entry.section,
            .source = shared.editor_command_catalog.sourceForEntry(entry),
        };
    }

    return .{
        .runtime_targets = &.{
            "friendly_engine_client",
            "friendly_engine_editor",
            "friendly_engine_mcp",
            "friendly_engine_server",
        },
        .modules = module_entries,
        .components = component_entries,
        .requests = request_entries,
        .editor_modes = &shared.editor_mode_catalog.entries,
        .editor_screens = &.{
            .{
                .name = "Project Manager",
                .builder = "src/runtime/editor/pm_ui_build.zig",
                .sections = &.{ "window menu", "header", "toolbar", "project list", "details", "modal" },
            },
            .{
                .name = "Project Editor",
                .builder = "src/runtime/editor/project_editor_ui_build.zig",
                .sections = &.{ "top bar", "world creation", "layout", "architecture creation", "prop creation", "life", "left rail", "inspector", "bottom strip", "ui inspection", "mcp" },
            },
        },
        .editor_commands = editor_commands,
    };
}

pub fn describeJson(allocator: std.mem.Allocator) ![]u8 {
    var doc = try buildDescribeDocument(allocator);
    defer doc.deinit(allocator);
    return std.fmt.allocPrint(allocator, "{f}\n", .{std.json.fmt(doc, .{ .whitespace = .indent_2 })});
}

fn fieldKindName(kind: framework.components.FieldKind) []const u8 {
    return switch (kind) {
        .f32 => "f32",
        .u32 => "u32",
        .u64 => "u64",
        .bool => "bool",
        .vec3f => "vec3f",
        .asset_id => "asset_id",
    };
}

pub fn runDescribe(allocator: std.mem.Allocator) !void {
    const json = try describeJson(allocator);
    defer allocator.free(json);
    std.debug.print("{s}", .{json});
}

test "describe emits module and request catalog" {
    const json = try describeJson(std.testing.allocator);
    defer std.testing.allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "gem.physics3d") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "gem.luajit") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "luajit.describe") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "world.describe") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "game.scene_transform") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "project_editor_ui_build.zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"editor_commands\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"editor_modes\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "gem.editor_layout") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"id\": \"pm-create\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"id\": \"ed-save\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"section\": \"bottom strip\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"id\": \"ed-inspect-ui-copy\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"source\": \"src/runtime/editor/project_editor_ui_tree.zig\"") != null);
}
