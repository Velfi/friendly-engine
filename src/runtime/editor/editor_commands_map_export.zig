const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const editor_command_file = @import("editor_command_file.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_terrain_preview = @import("project_editor_terrain_preview.zig");
const project_editor_view_nav = @import("project_editor_view_nav.zig");
const project_editor_world_authoring_manifest = @import("project_editor_world_authoring_manifest.zig");

const sdl = shared.sdl;
const CommandFile = editor_command_file.CommandFile;
const ProjectEditorState = project_editor_state.ProjectEditorState;
const command_root = ".friendly-engine/editor-control";
const export_dir = command_root ++ "/exports";

pub fn frameWorldTopDown(state: *ProjectEditorState) !void {
    const manifest_path = try project_editor_world_authoring_manifest.pathForState(state);
    var manifest = try friendly_engine.world.manifest.loadManifest(state.allocator, state.io, state.project_path, manifest_path);
    defer manifest.deinit();

    const bounds = try manifestWorldBounds(&manifest);
    const span_x = bounds.max_x - bounds.min_x;
    const span_z = bounds.max_z - bounds.min_z;
    const span = @max(manifest.cell_size_m, @max(span_x, span_z));
    const diagonal = @max(manifest.cell_size_m, @sqrt(span_x * span_x + span_z * span_z));
    const target_x = (bounds.min_x + bounds.max_x) * 0.5;
    const target_z = (bounds.min_z + bounds.max_z) * 0.5;
    const target_y = project_editor_terrain_preview.sampleHeightAtPoint(state, .{ .x = target_x, .y = 0, .z = target_z }) catch 0.0;

    state.view_camera_mode = .orthographic;
    project_editor_view_nav.applyAxisSnap(state, .top);
    state.camera.target = .{ .x = target_x, .y = target_y, .z = target_z };
    state.camera.max_distance = @max(state.camera.max_distance, diagonal * 1.6);
    state.camera.distance = std.math.clamp(span * 0.78, state.camera.min_distance, state.camera.max_distance);
    state.world_draw_distance_m = @max(state.world_draw_distance_m, diagonal * 1.75);
    state.camera.far_clip_m = state.world_draw_distance_m;
    state.show_viewport_toolbar = false;
    state.show_grid = false;
    project_editor_state.setStatus(state, "Top-down map capture queued");
}

pub fn exportTerrainHeightmap(
    allocator: std.mem.Allocator,
    io: std.Io,
    command: CommandFile,
    state: *ProjectEditorState,
) ![]u8 {
    const terrain_authoring = friendly_engine.modules.terrain.authoring;
    const manifest_path = try project_editor_world_authoring_manifest.pathForState(state);
    var doc = try terrain_authoring.load(allocator, io, state.project_path, manifest_path);
    defer doc.deinit();
    if (doc.tiles.items.len == 0) return error.TerrainTileNotFound;

    var min_cell_x: i32 = std.math.maxInt(i32);
    var max_cell_x: i32 = std.math.minInt(i32);
    var min_cell_z: i32 = std.math.maxInt(i32);
    var max_cell_z: i32 = std.math.minInt(i32);
    var sample_size: u32 = 0;
    var observed_min = std.math.inf(f32);
    var observed_max = -std.math.inf(f32);
    for (doc.tiles.items) |tile| {
        if (tile.size < 2) return error.InvalidTerrainTile;
        if (sample_size == 0) sample_size = tile.size;
        if (tile.size != sample_size) return error.InvalidTerrainTile;
        const id = tile.id();
        min_cell_x = @min(min_cell_x, id.x);
        max_cell_x = @max(max_cell_x, id.x);
        min_cell_z = @min(min_cell_z, id.y);
        max_cell_z = @max(max_cell_z, id.y);
        for (tile.heights) |height| {
            observed_min = @min(observed_min, height);
            observed_max = @max(observed_max, height);
        }
    }
    if (!std.math.isFinite(observed_min) or !std.math.isFinite(observed_max)) return error.InvalidTerrainHeight;

    const norm_min = command.min_height orelse observed_min;
    const norm_max = command.max_height orelse observed_max;
    if (!(norm_max > norm_min)) return error.InvalidTerrainHeight;

    const samples_per_cell: usize = @intCast(sample_size - 1);
    const cells_w: usize = @intCast(max_cell_x - min_cell_x + 1);
    const cells_h: usize = @intCast(max_cell_z - min_cell_z + 1);
    const width = cells_w * samples_per_cell + 1;
    const height = cells_h * samples_per_cell + 1;
    const pixels = try allocator.alloc(u8, width * height * 4);
    defer allocator.free(pixels);
    @memset(pixels, 0);

    for (doc.tiles.items) |tile| {
        const id = tile.id();
        const base_x: usize = @intCast(id.x - min_cell_x);
        const base_z: usize = @intCast(id.y - min_cell_z);
        const tile_size: usize = @intCast(tile.size);
        var z: usize = 0;
        while (z < tile_size) : (z += 1) {
            var x: usize = 0;
            while (x < tile_size) : (x += 1) {
                const source = tile.heights[z * tile_size + x];
                const t = std.math.clamp((source - norm_min) / (norm_max - norm_min), 0.0, 1.0);
                const value: u8 = @intFromFloat(@round(t * 255.0));
                const out_x = base_x * samples_per_cell + x;
                const out_z = base_z * samples_per_cell + z;
                const offset = (out_z * width + out_x) * 4;
                pixels[offset + 0] = value;
                pixels[offset + 1] = value;
                pixels[offset + 2] = value;
                pixels[offset + 3] = 255;
            }
        }
    }

    const absolute_path = try exportOutputPath(allocator, io, state.project_path, state.project_name, command);
    defer allocator.free(absolute_path);
    const absolute_path_z = try allocator.dupeZ(u8, absolute_path);
    defer allocator.free(absolute_path_z);
    try saveRgbaPng(allocator, pixels, @intCast(width), @intCast(height), absolute_path_z.ptr);

    project_editor_state.setStatus(state, "Terrain heightmap exported");
    return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"path\":\"{s}\",\"width\":{d},\"height\":{d},\"cells\":{d},\"sample_size\":{d},\"min_height\":{d:.6},\"max_height\":{d:.6},\"observed_min_height\":{d:.6},\"observed_max_height\":{d:.6}}}\n", .{
        command.id,
        command.name,
        absolute_path,
        width,
        height,
        doc.tiles.items.len,
        sample_size,
        norm_min,
        norm_max,
        observed_min,
        observed_max,
    });
}

fn exportOutputPath(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    project_name: []const u8,
    command: CommandFile,
) ![]u8 {
    if (command.path) |path| {
        if (std.fs.path.isAbsolute(path)) {
            try ensureParentDir(io, path);
            return allocator.dupe(u8, path);
        }
        try ensureExportDirs(io, project_path);
        const absolute = try std.fs.path.join(allocator, &.{ project_path, path });
        errdefer allocator.free(absolute);
        try ensureParentDir(io, absolute);
        return absolute;
    }

    try ensureExportDirs(io, project_path);
    const project_dir_name = try sanitizedProjectName(allocator, project_name);
    defer allocator.free(project_dir_name);
    const project_export_dir = try std.fs.path.join(allocator, &.{ export_dir, project_dir_name });
    defer allocator.free(project_export_dir);
    try makeProjectPath(io, project_path, project_export_dir);
    const file_name = try std.fmt.allocPrint(allocator, "{s}-heightmap.png", .{command.id});
    defer allocator.free(file_name);
    const rel_path = try std.fs.path.join(allocator, &.{ project_export_dir, file_name });
    defer allocator.free(rel_path);
    return std.fs.path.join(allocator, &.{ project_path, rel_path });
}

fn ensureExportDirs(io: std.Io, project_path: []const u8) !void {
    try makeProjectPath(io, project_path, command_root);
    try makeProjectPath(io, project_path, export_dir);
}

fn ensureParentDir(io: std.Io, absolute_path: []const u8) !void {
    const parent = std.fs.path.dirname(absolute_path) orelse return;
    try std.Io.Dir.cwd().createDirPath(io, parent);
}

const ManifestWorldBounds = struct {
    min_x: f32,
    min_z: f32,
    max_x: f32,
    max_z: f32,
};

fn manifestWorldBounds(manifest: *const friendly_engine.world.manifest.OwnedWorldManifest) !ManifestWorldBounds {
    var min_x: f32 = std.math.floatMax(f32);
    var min_z: f32 = std.math.floatMax(f32);
    var max_x: f32 = -std.math.floatMax(f32);
    var max_z: f32 = -std.math.floatMax(f32);
    for (manifest.cells) |entry| {
        if (entry.id.z != 0) continue;
        const cell_min_x = @as(f32, @floatFromInt(entry.id.x)) * manifest.cell_size_m;
        const cell_min_z = @as(f32, @floatFromInt(entry.id.y)) * manifest.cell_size_m;
        min_x = @min(min_x, cell_min_x);
        min_z = @min(min_z, cell_min_z);
        max_x = @max(max_x, cell_min_x + manifest.cell_size_m);
        max_z = @max(max_z, cell_min_z + manifest.cell_size_m);
    }
    if (!std.math.isFinite(min_x)) return error.WorldCellNotInManifest;
    return .{ .min_x = min_x, .min_z = min_z, .max_x = max_x, .max_z = max_z };
}

fn sanitizedProjectName(allocator: std.mem.Allocator, project_name: []const u8) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, @max(project_name.len, 1));
    defer out.deinit(allocator);
    var last_dash = false;
    for (project_name) |ch| {
        const mapped: ?u8 = if (std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '-' or ch == '.')
            ch
        else if (std.ascii.isWhitespace(ch))
            '-'
        else
            null;
        if (mapped) |value| {
            if (value == '-') {
                if (last_dash or out.items.len == 0) continue;
                last_dash = true;
            } else {
                last_dash = false;
            }
            try out.append(allocator, value);
        }
    }
    while (out.items.len > 0 and out.items[out.items.len - 1] == '-') {
        _ = out.pop();
    }
    if (out.items.len == 0) try out.appendSlice(allocator, "project");
    return out.toOwnedSlice(allocator);
}

fn makeProjectPath(io: std.Io, project_path: []const u8, rel_path: []const u8) !void {
    if (rel_path.len == 0) return;
    var project_dir = try std.Io.Dir.cwd().openDir(io, project_path, .{});
    defer project_dir.close(io);
    try project_dir.createDirPath(io, rel_path);
}

fn saveRgbaPng(
    allocator: std.mem.Allocator,
    pixels: []const u8,
    width: u32,
    height: u32,
    path: [*:0]const u8,
) !void {
    const surface = sdl.SDL_CreateSurfaceFrom(@intCast(width), @intCast(height), sdl.SDL_PIXELFORMAT_RGBA32, @constCast(pixels.ptr), @intCast(width * 4)) orelse return error.SdlSurfaceCreateFailed;
    defer sdl.SDL_DestroySurface(surface);
    if (!sdl.SDL_SavePNG(surface, path)) return error.SdlSavePngFailed;
    _ = allocator;
}
