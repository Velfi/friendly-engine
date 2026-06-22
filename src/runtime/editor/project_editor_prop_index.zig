const std = @import("std");
const shared = @import("runtime_shared");
const scene_resolve = shared.scene_resolve;
const prop_asset_doc = shared.prop_asset_doc;
const project_editor_state = @import("project_editor_state.zig");
const project_editor_types = @import("project_editor_types.zig");
const prop_catalog = @import("project_editor_prop_catalog.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const PropAssetIndexRow = project_editor_types.PropAssetIndexRow;
const PropAssetSource = project_editor_types.PropAssetSource;

pub fn ensure(state: *ProjectEditorState) ![]const PropAssetIndexRow {
    if (!state.prop_asset_index_valid) try rebuild(state);
    return state.prop_asset_index.items;
}

pub fn invalidate(state: *ProjectEditorState) void {
    state.prop_asset_index_valid = false;
}

pub fn clear(state: *ProjectEditorState) void {
    for (state.prop_asset_index.items) |*row| row.deinit(state.allocator);
    state.prop_asset_index.clearRetainingCapacity();
    state.prop_asset_index_valid = false;
}

fn rebuild(state: *ProjectEditorState) !void {
    clear(state);
    errdefer clear(state);

    for (prop_catalog.catalog) |entry| {
        var doc = loadDocument(state, entry.id) catch null;
        defer if (doc) |*loaded| loaded.deinit(state.allocator);
        try state.prop_asset_index.append(state.allocator, .{
            .id = try state.allocator.dupe(u8, entry.id),
            .label = try state.allocator.dupe(u8, if (doc) |loaded| loaded.label else entry.label),
            .tags = try state.allocator.dupe(u8, if (doc) |loaded| loaded.tags else catalogTags(entry)),
            .source = .builtin,
            .kind = try state.allocator.dupe(u8, prop_catalog.primitiveLabel(entry.kind)),
            .variant_count = if (doc) |loaded| loaded.variant_count else entry.variant_count,
            .source_count = entry.recipe.sources.len,
            .deleted = if (doc) |loaded| loaded.deleted else false,
            .color = entry.color,
        });
    }

    var project_dir = scene_resolve.openProjectDir(state.io, state.project_path) catch |err| switch (err) {
        error.FileNotFound => {
            state.prop_asset_index_valid = true;
            return;
        },
        else => return err,
    };
    defer project_dir.close(state.io);
    var props_dir = project_dir.openDir(state.io, "props", .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => {
            state.prop_asset_index_valid = true;
            return;
        },
        else => return err,
    };
    defer props_dir.close(state.io);

    var walker = try props_dir.walk(state.allocator);
    defer walker.deinit();
    while (try walker.next(state.io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.path, ".kdl")) continue;
        if (std.fs.path.dirname(entry.path) != null) continue;
        const id = std.fs.path.stem(std.fs.path.basename(entry.path));
        if (prop_catalog.findCatalogEntry(id) != null) continue;
        var doc = try loadDocument(state, id);
        defer doc.deinit(state.allocator);
        try state.prop_asset_index.append(state.allocator, .{
            .id = try state.allocator.dupe(u8, doc.id),
            .label = try state.allocator.dupe(u8, doc.label),
            .tags = try state.allocator.dupe(u8, doc.tags),
            .source = .project,
            .kind = try state.allocator.dupe(u8, projectKind(doc)),
            .variant_count = doc.variant_count,
            .source_count = doc.recipe.sources.len,
            .deleted = doc.deleted,
            .color = doc.base_color,
        });
    }

    state.prop_asset_index_valid = true;
}

fn loadDocument(state: *ProjectEditorState, asset_id: []const u8) !prop_asset_doc.PropAssetDocument {
    const path = try prop_asset_doc.documentPath(state.allocator, asset_id);
    defer state.allocator.free(path);
    var project_dir = try scene_resolve.openProjectDir(state.io, state.project_path);
    defer project_dir.close(state.io);
    const bytes = try project_dir.readFileAlloc(state.io, path, state.allocator, .limited(2 * 1024 * 1024));
    defer state.allocator.free(bytes);
    return prop_asset_doc.parse(state.allocator, bytes);
}

fn catalogTags(entry: prop_catalog.CatalogEntry) []const u8 {
    if (entry.recipe.shaping.len == 0) return "shape";
    if (recipeContains(entry, "tint") or recipeContains(entry, "mask") or recipeContains(entry, "rust")) return "paint, shape";
    if (std.ascii.indexOfIgnoreCase(entry.id, "door") != null or std.ascii.indexOfIgnoreCase(entry.id, "lamp") != null) return "game, shape";
    return "shape";
}

fn projectKind(doc: prop_asset_doc.PropAssetDocument) []const u8 {
    if (doc.recipe.shape_intents.len > 0) return "shape";
    if (doc.recipe.sources.len > 0) return "recipe";
    if (doc.material_path != null or doc.texture_path != null or doc.face_materials.len > 0) return "paint";
    return "mesh";
}

fn recipeContains(entry: prop_catalog.CatalogEntry, needle: []const u8) bool {
    for (entry.recipe.shaping) |shape| {
        if (std.ascii.indexOfIgnoreCase(shape, needle) != null) return true;
    }
    return false;
}

pub fn sourceLabel(source: PropAssetSource) []const u8 {
    return switch (source) {
        .builtin => "built-in",
        .project => "project",
    };
}

test "prop asset index includes built-in catalog rows once" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = try std.testing.allocator.dupe(u8, ""),
        .project_name = try std.testing.allocator.dupe(u8, ""),
        .objects = .empty,
    };
    defer state.deinit();

    const rows = try ensure(&state);
    var builtin_count: usize = 0;
    for (prop_catalog.catalog) |entry| {
        var matches: usize = 0;
        for (rows) |row| {
            if (row.source == .builtin and std.mem.eql(u8, row.id, entry.id)) matches += 1;
        }
        try std.testing.expectEqual(@as(usize, 1), matches);
        builtin_count += matches;
    }
    try std.testing.expectEqual(prop_catalog.catalog.len, builtin_count);
}

test "prop asset index classifies project assets with shape intents" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "props");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "props/intent_panel.kdl", .data =
        \\prop_asset version=1 id="intent_panel" label="Intent Panel" tags="shape" deleted=false {
        \\  recipe {
        \\    shape id="shape_1" source=closed_face operation=solidify amount=0.08 segments=24 points="-1,0,-1;1,0,-1;1,0,1;-1,0,1"
        \\  }
        \\  mesh asset="props/meshes/intent_panel.fmesh"
        \\  material base_color="255,255,255,255"
        \\  variants count=1
        \\}
        \\
    });
    const project_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(project_path);

    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = try std.testing.allocator.dupe(u8, project_path),
        .project_name = try std.testing.allocator.dupe(u8, ""),
        .objects = .empty,
    };
    defer state.deinit();

    const rows = try ensure(&state);
    for (rows) |row| {
        if (std.mem.eql(u8, row.id, "intent_panel")) {
            try std.testing.expectEqualStrings("shape", row.kind);
            try std.testing.expectEqual(@as(usize, 0), row.source_count);
            return;
        }
    }
    return error.MissingShapeIntentProp;
}
