const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const editor_math = shared.editor_math;

const project_editor_state = @import("project_editor_state.zig");
const ProjectEditorState = project_editor_state.ProjectEditorState;

const world = friendly_engine.world;

pub const world_manifest_path = "world.kdl";

pub fn pathForState(state: *const ProjectEditorState) ![]const u8 {
    if (state.active_world_manifest_path.len == 0) return error.SceneWorldNotConfigured;
    return state.active_world_manifest_path;
}

pub const WorldLayerNotTerrain = error.WorldLayerNotTerrain;
pub const WorldLayerNotSpline = error.WorldLayerNotSpline;
pub const WorldLayerNotScatter = error.WorldLayerNotScatter;
pub const WorldBrushAffectDisabled = error.WorldBrushAffectDisabled;

pub fn cellIdForPoint(cell_size_m: f32, point: editor_math.Vec3) world.cell.CellId {
    return .{
        .x = @intFromFloat(@floor(point.x / cell_size_m)),
        .y = @intFromFloat(@floor(point.z / cell_size_m)),
        .z = 0,
    };
}

pub fn cellCenter(id: world.cell.CellId, cell_size_m: f32) editor_math.Vec3 {
    const half = cell_size_m * 0.5;
    return .{
        .x = @as(f32, @floatFromInt(id.x)) * cell_size_m + half,
        .y = 0,
        .z = @as(f32, @floatFromInt(id.y)) * cell_size_m + half,
    };
}

pub fn cellForPoint(state: *ProjectEditorState, point: editor_math.Vec3) !world.cell.CellId {
    var loaded_manifest = try world.manifest.loadManifest(state.allocator, state.io, state.project_path, try pathForState(state));
    defer loaded_manifest.deinit();
    const id = cellIdForPoint(loaded_manifest.cell_size_m, point);
    if (!loaded_manifest.hasCell(id)) return error.WorldCellNotInManifest;
    return id;
}

pub fn createManifestCellAt(state: *ProjectEditorState, point: editor_math.Vec3) !world.cell.CellId {
    var loaded_manifest = try world.manifest.loadManifest(state.allocator, state.io, state.project_path, try pathForState(state));
    defer loaded_manifest.deinit();

    const id = cellIdForPoint(loaded_manifest.cell_size_m, point);
    if (loaded_manifest.hasCell(id)) return id;

    const authoring_path = try terrainCellScenePath(state.allocator, id);
    defer state.allocator.free(authoring_path);
    try writeEmptySceneFile(state, authoring_path);
    try appendManifestCell(state, loaded_manifest, id, authoring_path);
    return id;
}

pub fn interiorChildForCell(state: *ProjectEditorState, parent: world.cell.CellId) !world.cell.CellId {
    var manifest = try world.manifest.loadManifest(state.allocator, state.io, state.project_path, try pathForState(state));
    defer manifest.deinit();
    for (manifest.cells) |entry| {
        if (entry.interior_parent) |candidate_parent| {
            if (candidate_parent.eql(parent)) return entry.id;
        }
    }
    return error.WorldInteriorCellNotInManifest;
}

pub fn midpoint(a: editor_math.Vec3, b: editor_math.Vec3) editor_math.Vec3 {
    return .{
        .x = (a.x + b.x) * 0.5,
        .y = (a.y + b.y) * 0.5,
        .z = (a.z + b.z) * 0.5,
    };
}

pub fn writeLayerBytes(state: *ProjectEditorState, path: []const u8, bytes: []const u8) !void {
    var dir = if (std.fs.path.isAbsolute(state.project_path))
        try std.Io.Dir.openDirAbsolute(state.io, state.project_path, .{})
    else
        try std.Io.Dir.cwd().openDir(state.io, state.project_path, .{});
    defer dir.close(state.io);
    if (std.fs.path.dirname(path)) |parent| {
        try dir.createDirPath(state.io, parent);
    }
    try dir.writeFile(state.io, .{ .sub_path = path, .data = bytes });
}

fn appendManifestCell(
    state: *ProjectEditorState,
    loaded_manifest: world.manifest.OwnedWorldManifest,
    id: world.cell.CellId,
    authoring_path: []const u8,
) !void {
    var bytes: std.Io.Writer.Allocating = .init(state.allocator);
    defer bytes.deinit();
    const writer = &bytes.writer;

    try writer.print("world version=1 id=\"{s}\" cell_size_m={d} {{\n", .{
        loaded_manifest.world_id,
        loaded_manifest.cell_size_m,
    });
    for (loaded_manifest.cells) |entry| {
        if (entry.interior_parent) |parent| {
            try writer.print(
                "  cell coord=\"{d},{d},{d}\" authoring=\"{s}\" interior_parent=\"{d},{d},{d}\"\n",
                .{ entry.id.x, entry.id.y, entry.id.z, entry.authoring_path, parent.x, parent.y, parent.z },
            );
        } else {
            try writer.print(
                "  cell coord=\"{d},{d},{d}\" authoring=\"{s}\"\n",
                .{ entry.id.x, entry.id.y, entry.id.z, entry.authoring_path },
            );
        }
    }
    try writer.print("  cell coord=\"{d},{d},{d}\" authoring=\"{s}\"\n", .{
        id.x,
        id.y,
        id.z,
        authoring_path,
    });
    try writer.writeAll("}\n");
    try writeLayerBytes(state, try pathForState(state), bytes.written());
}

fn terrainCellScenePath(allocator: std.mem.Allocator, id: world.cell.CellId) ![]u8 {
    return std.fmt.allocPrint(allocator, "scenes/cell_{d}_{d}_{d}.kdl", .{ id.x, id.y, id.z });
}

fn writeEmptySceneFile(state: *ProjectEditorState, path: []const u8) !void {
    try writeLayerBytes(state, path,
        \\scene version=1 next_object_id=1 {
        \\}
        \\
    );
}
