const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const zigimg = @import("zigimg");
const editor_math = shared.editor_math;

const project_editor_state = @import("project_editor_state.zig");
const project_editor_terrain_undo_store = @import("project_editor_terrain_undo_store.zig");
const project_editor_types = @import("project_editor_types.zig");
const manifest = @import("project_editor_world_authoring_manifest.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const WorldLayerId = project_editor_types.WorldLayerId;
const modules = friendly_engine.modules;
const world = friendly_engine.world;
const mesh_builder = modules.terrain.mesh_builder;

pub const terrain_tile_size: u32 = 32;
pub const terrain_lod_levels = [_]u32{ 32, 16, 8, 4, 2 };
pub const default_paint_layers = [_][]const u8{
    "grass",
    "dirt",
    "stone",
    "rock",
    "gravel",
    "road",
    "abyss",
    "shelf",
    "beach",
    "ash",
    "chalk",
    "rust",
    "marsh",
};
pub const default_paint_colors = [_][4]u8{
    .{ 105, 143, 72, 255 },
    .{ 116, 87, 58, 255 },
    .{ 135, 132, 122, 255 },
    .{ 86, 85, 80, 255 },
    .{ 151, 144, 130, 255 },
    .{ 83, 76, 66, 255 },
    .{ 11, 13, 15, 255 },
    .{ 36, 48, 52, 255 },
    .{ 156, 137, 103, 255 },
    .{ 43, 42, 39, 255 },
    .{ 191, 181, 153, 255 },
    .{ 139, 76, 45, 255 },
    .{ 58, 79, 47, 255 },
};
pub const default_paint_albedo_textures = [_][]const u8{ "", "", "", "", "", "", "", "", "", "", "", "", "" };
pub const default_paint_roughness_textures = [_][]const u8{ "", "", "", "", "", "", "", "", "", "", "", "", "" };
pub const default_paint_specular_textures = [_][]const u8{ "", "", "", "", "", "", "", "", "", "", "", "", "" };
pub const default_paint_displacement_textures = [_][]const u8{ "", "", "", "", "", "", "", "", "", "", "", "", "" };

pub const TerrainSculptMode = enum {
    raise,
    lower,
    smooth,

    pub fn parse(value: []const u8) !TerrainSculptMode {
        if (std.mem.eql(u8, value, "raise")) return .raise;
        if (std.mem.eql(u8, value, "lower")) return .lower;
        if (std.mem.eql(u8, value, "smooth")) return .smooth;
        return error.InvalidTerrainSculptMode;
    }

    pub fn label(self: TerrainSculptMode) []const u8 {
        return switch (self) {
            .raise => "raise",
            .lower => "lower",
            .smooth => "smooth",
        };
    }
};

pub const TerrainBrushResult = struct {
    cell: world.cell.CellId,
    affected_samples: usize,
    peak_delta: f32,
};

pub const HeightmapLoadResult = struct {
    cell: world.cell.CellId,
    min_height: f32,
    max_height: f32,
    source_width: u32,
    source_height: u32,
};

pub fn createTerrainCell(state: *ProjectEditorState) !void {
    try createTerrainCellAt(state, state.camera.target);
}

pub fn createTerrainCellAt(state: *ProjectEditorState, point: editor_math.Vec3) !void {
    const id = try manifest.createManifestCellAt(state, point);
    const created_tile = !try terrainTileExists(state, id);
    if (created_tile) {
        const sample_count = @as(usize, terrain_tile_size) * @as(usize, terrain_tile_size);
        const heights = try state.allocator.alloc(f32, sample_count);
        defer state.allocator.free(heights);
        @memset(heights, 0);
        const splat = try state.allocator.alloc(u8, sample_count * default_paint_layers.len);
        defer state.allocator.free(splat);
        fillDefaultPaintWeights(splat, default_paint_layers.len);

        try snapshotTerrainEdit(state, id, nowNs(state));
        try upsertTerrainTile(state, id, heights, splat, "terrain.editor");
        _ = project_editor_terrain_undo_store.pruneAfterTransaction(state.allocator, state.io, state.project_path, state.terrain_undo_limit_mb) catch {};
        try project_editor_state.markDirtyCell(state, "Terrain", id, "new cell");
    }

    var world_manifest = try world.manifest.loadManifest(state.allocator, state.io, state.project_path, try manifest.pathForState(state));
    defer world_manifest.deinit();
    state.world_cell_size_m = world_manifest.cell_size_m;
    state.invalidateWorldCache();
    state.world_tool = .terrain;
    state.selected_world_layer = .terrain_base_height;

    var buf: [128]u8 = undefined;
    project_editor_state.setStatus(state, std.fmt.bufPrint(
        &buf,
        "Terrain cell {d},{d},{d} ready",
        .{ id.x, id.y, id.z },
    ) catch "Terrain cell ready");
}

pub fn deleteTerrainCellAt(state: *ProjectEditorState, point: editor_math.Vec3) !void {
    const id = try manifest.cellForPoint(state, point);
    const deleted = try modules.terrain.authoring.deleteTileFile(
        state.allocator,
        state.io,
        state.project_path,
        try manifest.pathForState(state),
        id,
    );
    if (!deleted) {
        var missing_buf: [128]u8 = undefined;
        project_editor_state.setStatus(state, std.fmt.bufPrint(
            &missing_buf,
            "No terrain cell at {d},{d},{d}",
            .{ id.x, id.y, id.z },
        ) catch "No terrain cell here");
        return;
    }

    try project_editor_state.markDirtyCell(state, "Terrain", id, "deleted cell");
    state.invalidateWorldCache();
    state.world_tool = .terrain;
    state.selected_world_layer = .terrain_base_height;

    var buf: [128]u8 = undefined;
    project_editor_state.setStatus(state, std.fmt.bufPrint(
        &buf,
        "Terrain cell {d},{d},{d} deleted",
        .{ id.x, id.y, id.z },
    ) catch "Terrain cell deleted");
}

pub fn loadHeightmapAt(
    state: *ProjectEditorState,
    point: editor_math.Vec3,
    path: []const u8,
    min_height: f32,
    max_height: f32,
    material: []const u8,
) !HeightmapLoadResult {
    if (path.len == 0) return error.InvalidHeightmapPath;
    if (!std.math.isFinite(min_height) or !std.math.isFinite(max_height)) return error.InvalidHeightmapRange;
    if (min_height >= max_height) return error.InvalidHeightmapRange;

    const id = try manifest.createManifestCellAt(state, point);
    const bytes = try readHeightmapBytes(state.allocator, state.io, state.project_path, path);
    defer state.allocator.free(bytes);

    var image = try zigimg.Image.fromMemory(state.allocator, bytes);
    defer image.deinit(state.allocator);
    try image.convert(state.allocator, .rgba32);

    const heights = try state.allocator.alloc(f32, @as(usize, terrain_tile_size) * @as(usize, terrain_tile_size));
    defer state.allocator.free(heights);
    heightmapRgbaToHeights(
        image.rawBytes(),
        @intCast(image.width),
        @intCast(image.height),
        min_height,
        max_height,
        heights,
        terrain_tile_size,
    );

    const splat = try state.allocator.alloc(u8, @as(usize, terrain_tile_size) * @as(usize, terrain_tile_size) * default_paint_layers.len);
    defer state.allocator.free(splat);
    fillDefaultPaintWeights(splat, default_paint_layers.len);

    try snapshotTerrainEdit(state, id, nowNs(state));
    try upsertTerrainTile(state, id, heights, splat, material);
    _ = project_editor_terrain_undo_store.pruneAfterTransaction(state.allocator, state.io, state.project_path, state.terrain_undo_limit_mb) catch {};
    try project_editor_state.markDirtyCell(state, "Terrain", id, "heightmap import");
    state.world_tool = .terrain;
    state.selected_world_layer = .terrain_base_height;
    var status_buf: [160]u8 = undefined;
    project_editor_state.setStatus(state, std.fmt.bufPrint(
        &status_buf,
        "Heightmap loaded: cell {d},{d},{d}",
        .{ id.x, id.y, id.z },
    ) catch "Heightmap loaded");
    return .{
        .cell = id,
        .min_height = min_height,
        .max_height = max_height,
        .source_width = @intCast(image.width),
        .source_height = @intCast(image.height),
    };
}

pub fn heightmapRgbaToHeights(
    rgba: []const u8,
    src_w: u32,
    src_h: u32,
    min_height: f32,
    max_height: f32,
    heights: []f32,
    tile_size: u32,
) void {
    std.debug.assert(rgba.len == @as(usize, src_w) * @as(usize, src_h) * 4);
    std.debug.assert(heights.len == @as(usize, tile_size) * @as(usize, tile_size));
    var z: u32 = 0;
    while (z < tile_size) : (z += 1) {
        const src_z = z * src_h / tile_size;
        var x: u32 = 0;
        while (x < tile_size) : (x += 1) {
            const src_x = x * src_w / tile_size;
            const src_idx = (@as(usize, src_z) * @as(usize, src_w) + @as(usize, src_x)) * 4;
            const lum = @as(f32, @floatFromInt(rgba[src_idx])) * 0.2126 +
                @as(f32, @floatFromInt(rgba[src_idx + 1])) * 0.7152 +
                @as(f32, @floatFromInt(rgba[src_idx + 2])) * 0.0722;
            const t = lum / 255.0;
            heights[@as(usize, z) * @as(usize, tile_size) + @as(usize, x)] = min_height + (max_height - min_height) * t;
        }
    }
}

fn terrainTileExists(state: *ProjectEditorState, id: world.cell.CellId) !bool {
    const doc = try modules.terrain.authoring.loadCell(state.allocator, state.io, state.project_path, try manifest.pathForState(state), id);
    if (doc == null) return false;
    var owned_doc = doc.?;
    defer owned_doc.deinit();
    return true;
}

fn readHeightmapBytes(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    path: []const u8,
) ![]u8 {
    const max_heightmap_bytes = 64 * 1024 * 1024;
    if (std.fs.path.isAbsolute(path)) {
        const parent = std.fs.path.dirname(path) orelse return error.InvalidHeightmapPath;
        const base = std.fs.path.basename(path);
        var dir = try std.Io.Dir.openDirAbsolute(io, parent, .{});
        defer dir.close(io);
        return dir.readFileAlloc(io, base, allocator, .limited(max_heightmap_bytes));
    }

    var project_dir = if (std.fs.path.isAbsolute(project_path))
        try std.Io.Dir.openDirAbsolute(io, project_path, .{})
    else
        try std.Io.Dir.cwd().openDir(io, project_path, .{});
    defer project_dir.close(io);
    return project_dir.readFileAlloc(io, path, allocator, .limited(max_heightmap_bytes));
}

pub fn paintTerrainTile(state: *ProjectEditorState) !void {
    try paintTerrainAt(state, state.camera.target);
}

pub fn paintTerrainAt(state: *ProjectEditorState, point: editor_math.Vec3) !void {
    const layer = resolveTerrainLayer(state);
    switch (layer) {
        .terrain_base_height => {
            if (!state.world_affects_height) {
                project_editor_state.setStatus(state, "Height brush disabled: enable Height affect");
                return;
            }
            try applyHeightBrush(state, point, .raise);
        },
        .terrain_erosion_mask => try applyHeightBrush(state, point, .erode),
        .terrain_material_tiles => {
            if (!state.world_affects_material) {
                project_editor_state.setStatus(state, "Material brush disabled: enable Material affect");
                return;
            }
            _ = try applyMaterialBrush(state, point);
        },
        else => {
            project_editor_state.setStatus(state, "Select terrain layer: base_height, erosion_mask, or material_tiles");
        },
    }
}

fn resolveTerrainLayer(state: *const ProjectEditorState) WorldLayerId {
    if (state.world_tool == .paint) return .terrain_material_tiles;
    return state.selected_world_layer orelse .terrain_base_height;
}

pub fn paintMaterialLayerAt(state: *ProjectEditorState, point: editor_math.Vec3, layer_name: []const u8) !TerrainBrushResult {
    const layer_index = try defaultPaintLayerIndex(layer_name);
    state.world_tool = .paint;
    state.selected_world_layer = .terrain_material_tiles;
    state.world_affects_material = true;
    state.world_brush_material = 0;
    state.world_brush_tile = @intCast(layer_index);
    return applyMaterialBrush(state, point);
}

pub fn defaultPaintLayerIndex(layer_name: []const u8) !usize {
    for (default_paint_layers, 0..) |candidate, index| {
        if (std.mem.eql(u8, candidate, layer_name)) return index;
    }
    return error.InvalidTerrainPaintLayer;
}

const HeightBrushMode = enum { raise, erode };

fn applyHeightBrush(state: *ProjectEditorState, point: editor_math.Vec3, mode: HeightBrushMode) !void {
    _ = try sculptTerrainAt(state, point, switch (mode) {
        .raise => .raise,
        .erode => .lower,
    }, if (mode == .erode) "erosion mask" else "height brush");
}

pub fn sculptTerrainAt(state: *ProjectEditorState, point: editor_math.Vec3, mode: TerrainSculptMode, change_label: []const u8) !TerrainBrushResult {
    const id = try manifest.cellForPoint(state, point);
    var world_manifest = try world.manifest.loadManifest(state.allocator, state.io, state.project_path, try manifest.pathForState(state));
    defer world_manifest.deinit();
    const cell_size_m = world_manifest.cell_size_m;
    const bounds = world.cell.boundsForCell(id, cell_size_m, world.cell.default_cell_height_m);

    var heights = try loadOrDefaultHeights(state, id);
    defer state.allocator.free(heights);
    const splat = try loadOrDefaultSplat(state, id);
    defer state.allocator.free(splat);
    const original_heights = if (mode == .smooth) try state.allocator.dupe(f32, heights) else &[_]f32{};
    defer if (mode == .smooth) state.allocator.free(original_heights);

    const center = brushCenterSamples(point, bounds, cell_size_m, terrain_tile_size);
    const radius_samples = @max(0.5, (state.world_brush_size / cell_size_m) * @as(f32, @floatFromInt(terrain_tile_size)));
    const delta_scale: f32 = switch (mode) {
        .raise, .lower => 0.5,
        .smooth => 1.0,
    };

    var affected_samples: usize = 0;
    var peak_delta: f32 = 0;
    var y: usize = 0;
    while (y < terrain_tile_size) : (y += 1) {
        var x: usize = 0;
        while (x < terrain_tile_size) : (x += 1) {
            const weight = brushWeightAt(
                x,
                y,
                center.x,
                center.y,
                radius_samples,
                state.world_brush_falloff,
                state.world_brush_strength,
            );
            if (weight <= 0) continue;
            const idx = y * terrain_tile_size + x;
            const delta = weight * delta_scale;
            affected_samples += 1;
            switch (mode) {
                .raise => {
                    peak_delta = @max(peak_delta, delta);
                    heights[idx] += delta;
                },
                .lower => {
                    peak_delta = @max(peak_delta, delta);
                    heights[idx] -= delta;
                },
                .smooth => {
                    const target = averageNeighborHeight(original_heights, terrain_tile_size, x, y);
                    const next = heights[idx] + (target - heights[idx]) * std.math.clamp(weight, 0, 1);
                    peak_delta = @max(peak_delta, @abs(next - heights[idx]));
                    heights[idx] = next;
                },
            }
        }
    }

    const material = try loadTileMaterial(state, id);
    defer state.allocator.free(material);
    try snapshotTerrainEdit(state, id, nowNs(state));
    try upsertTerrainTile(state, id, heights, splat, material);
    _ = project_editor_terrain_undo_store.pruneAfterTransaction(state.allocator, state.io, state.project_path, state.terrain_undo_limit_mb) catch {};
    try project_editor_state.markDirtyCell(state, "Terrain", id, change_label);
    setTerrainPaintStatus(state, id, change_label, affected_samples, peak_delta);
    return .{ .cell = id, .affected_samples = affected_samples, .peak_delta = peak_delta };
}

fn applyMaterialBrush(state: *ProjectEditorState, point: editor_math.Vec3) !TerrainBrushResult {
    const id = try manifest.cellForPoint(state, point);
    var world_manifest = try world.manifest.loadManifest(state.allocator, state.io, state.project_path, try manifest.pathForState(state));
    defer world_manifest.deinit();
    const cell_size_m = world_manifest.cell_size_m;
    const bounds = world.cell.boundsForCell(id, cell_size_m, world.cell.default_cell_height_m);

    const heights = try loadOrDefaultHeights(state, id);
    defer state.allocator.free(heights);
    var palette = try loadOrDefaultPaintPalette(state, id);
    defer palette.deinit(state.allocator);
    const splat = try loadOrDefaultSplat(state, id);
    defer state.allocator.free(splat);
    const layer_count = palette.layers.len;
    const target_layer = paintLayerIndexFromBrush(state, layer_count);

    const center = brushCenterSamples(point, bounds, cell_size_m, terrain_tile_size);
    const radius_samples = @max(0.5, (state.world_brush_size / cell_size_m) * @as(f32, @floatFromInt(terrain_tile_size)));

    var affected_samples: usize = 0;
    var y: usize = 0;
    while (y < terrain_tile_size) : (y += 1) {
        var x: usize = 0;
        while (x < terrain_tile_size) : (x += 1) {
            const weight = brushWeightAt(
                x,
                y,
                center.x,
                center.y,
                radius_samples,
                state.world_brush_falloff,
                state.world_brush_strength,
            );
            if (weight <= 0) continue;
            const idx = y * terrain_tile_size + x;
            affected_samples += 1;
            blendPaintLayer(splat, idx, layer_count, target_layer, weight);
        }
    }

    const material = try std.fmt.allocPrint(state.allocator, "terrain.layer.{s}", .{palette.layers[target_layer]});
    defer state.allocator.free(material);
    try snapshotTerrainEdit(state, id, nowNs(state));
    try upsertTerrainTile(state, id, heights, splat, material);
    _ = project_editor_terrain_undo_store.pruneAfterTransaction(state.allocator, state.io, state.project_path, state.terrain_undo_limit_mb) catch {};
    try project_editor_state.markDirtyCell(state, "Terrain", id, "material tile");
    setTerrainPaintStatus(state, id, "material tile", affected_samples, @as(f32, @floatFromInt(target_layer)));
    return .{ .cell = id, .affected_samples = affected_samples, .peak_delta = @as(f32, @floatFromInt(target_layer)) };
}

fn setTerrainPaintStatus(
    state: *ProjectEditorState,
    id: world.cell.CellId,
    change: []const u8,
    affected_samples: usize,
    peak_delta: f32,
) void {
    var buf: [160]u8 = undefined;
    const message = std.fmt.bufPrint(
        &buf,
        "Terrain {s}: cell {d},{d},{d}, {d} samples, peak {d:.2}",
        .{ change, id.x, id.y, id.z, affected_samples, peak_delta },
    ) catch "Terrain paint applied";
    project_editor_state.setStatus(state, message);
}

pub fn brushCenterSamples(point: editor_math.Vec3, bounds: world.cell.CellBounds, cell_size_m: f32, tile_size: u32) editor_math.Vec2 {
    const local_x = (point.x - bounds.min.x) / cell_size_m * @as(f32, @floatFromInt(tile_size));
    const local_z = (point.z - bounds.min.z) / cell_size_m * @as(f32, @floatFromInt(tile_size));
    return .{ .x = local_x, .y = local_z };
}

pub fn brushWeightAt(
    sample_x: usize,
    sample_y: usize,
    center_x: f32,
    center_y: f32,
    radius_samples: f32,
    falloff: f32,
    strength: f32,
) f32 {
    const dx = @as(f32, @floatFromInt(sample_x)) + 0.5 - center_x;
    const dy = @as(f32, @floatFromInt(sample_y)) + 0.5 - center_y;
    const dist = @sqrt(dx * dx + dy * dy);
    if (dist > radius_samples) return 0;
    const t = dist / @max(0.001, radius_samples);
    const edge = std.math.pow(f32, t, 1.0 / std.math.clamp(falloff, 0.05, 1.0));
    return strength * (1.0 - edge);
}

fn averageNeighborHeight(heights: []const f32, size: u32, sample_x: usize, sample_y: usize) f32 {
    const grid: usize = @intCast(size);
    var sum: f32 = 0;
    var count: f32 = 0;
    const min_x = if (sample_x == 0) 0 else sample_x - 1;
    const min_y = if (sample_y == 0) 0 else sample_y - 1;
    const max_x = @min(grid - 1, sample_x + 1);
    const max_y = @min(grid - 1, sample_y + 1);
    var y = min_y;
    while (y <= max_y) : (y += 1) {
        var x = min_x;
        while (x <= max_x) : (x += 1) {
            sum += heights[y * grid + x];
            count += 1;
        }
    }
    return sum / count;
}

fn loadOrDefaultHeights(state: *ProjectEditorState, id: world.cell.CellId) ![]f32 {
    const sample_count = @as(usize, terrain_tile_size) * @as(usize, terrain_tile_size);
    const doc = try modules.terrain.authoring.loadCell(state.allocator, state.io, state.project_path, try manifest.pathForState(state), id);
    if (doc) |loaded| {
        var owned_doc = loaded;
        defer owned_doc.deinit();
        if (owned_doc.tiles.items.len != 1) return error.InvalidTerrainDocument;
        const tile = owned_doc.tiles.items[0];
        return heightsForEditing(state.allocator, tile.size, tile.heights, terrain_tile_size);
    }
    const heights = try state.allocator.alloc(f32, sample_count);
    @memset(heights, 0);
    return heights;
}

pub const OwnedPaintPalette = struct {
    layers: [][]u8,
    colors: [][4]u8,
    albedo_textures: [][]u8,
    roughness_textures: [][]u8,
    specular_textures: [][]u8,
    displacement_textures: [][]u8,

    pub fn deinit(self: *OwnedPaintPalette, allocator: std.mem.Allocator) void {
        for (self.layers) |layer| allocator.free(layer);
        allocator.free(self.layers);
        allocator.free(self.colors);
        freeStringList(allocator, self.albedo_textures);
        freeStringList(allocator, self.roughness_textures);
        freeStringList(allocator, self.specular_textures);
        freeStringList(allocator, self.displacement_textures);
    }
};

pub fn loadOrDefaultPaintPalette(state: *ProjectEditorState, id: world.cell.CellId) !OwnedPaintPalette {
    const doc = try modules.terrain.authoring.loadCell(state.allocator, state.io, state.project_path, try manifest.pathForState(state), id);
    if (doc) |loaded| {
        var owned_doc = loaded;
        defer owned_doc.deinit();
        if (owned_doc.tiles.items.len != 1) return error.InvalidTerrainDocument;
        const tile = owned_doc.tiles.items[0];
        return .{
            .layers = try dupePaintLayers(state.allocator, tile.paint_layers),
            .colors = try state.allocator.dupe([4]u8, tile.paint_colors),
            .albedo_textures = try dupePaintLayers(state.allocator, tile.paint_albedo_textures),
            .roughness_textures = try dupePaintLayers(state.allocator, tile.paint_roughness_textures),
            .specular_textures = try dupePaintLayers(state.allocator, tile.paint_specular_textures),
            .displacement_textures = try dupePaintLayers(state.allocator, tile.paint_displacement_textures),
        };
    }
    return .{
        .layers = try dupePaintLayers(state.allocator, &default_paint_layers),
        .colors = try state.allocator.dupe([4]u8, &default_paint_colors),
        .albedo_textures = try dupePaintLayers(state.allocator, &default_paint_albedo_textures),
        .roughness_textures = try dupePaintLayers(state.allocator, &default_paint_roughness_textures),
        .specular_textures = try dupePaintLayers(state.allocator, &default_paint_specular_textures),
        .displacement_textures = try dupePaintLayers(state.allocator, &default_paint_displacement_textures),
    };
}

pub fn loadOrDefaultSplat(state: *ProjectEditorState, id: world.cell.CellId) ![]u8 {
    const sample_count = @as(usize, terrain_tile_size) * @as(usize, terrain_tile_size);
    const doc = try modules.terrain.authoring.loadCell(state.allocator, state.io, state.project_path, try manifest.pathForState(state), id);
    if (doc) |loaded| {
        var owned_doc = loaded;
        defer owned_doc.deinit();
        if (owned_doc.tiles.items.len != 1) return error.InvalidTerrainDocument;
        const tile = owned_doc.tiles.items[0];
        return splatForEditing(state.allocator, tile.splat_size, tile.splat, tile.paint_layers.len, terrain_tile_size);
    }
    const splat = try state.allocator.alloc(u8, sample_count * default_paint_layers.len);
    fillDefaultPaintWeights(splat, default_paint_layers.len);
    return splat;
}

pub fn heightsForEditing(
    allocator: std.mem.Allocator,
    source_size: u32,
    heights: []const f32,
    target_size: u32,
) ![]f32 {
    const expected = @as(usize, source_size) * @as(usize, source_size);
    if (heights.len != expected) return error.InvalidTerrainHeightCount;
    if (source_size == target_size) return allocator.dupe(f32, heights);

    const target_count = @as(usize, target_size) * @as(usize, target_size);
    const out = try allocator.alloc(f32, target_count);
    const tile = mesh_builder.HeightTile{ .size = source_size, .heights = heights };
    const grid: usize = @intCast(target_size);
    var z: usize = 0;
    while (z < grid) : (z += 1) {
        var x: usize = 0;
        while (x < grid) : (x += 1) {
            out[z * grid + x] = mesh_builder.sampleHeight(tile, x, z, grid);
        }
    }
    return out;
}

pub fn splatForEditing(
    allocator: std.mem.Allocator,
    source_size: u32,
    splat: []const u8,
    layer_count: usize,
    target_size: u32,
) ![]u8 {
    if (layer_count < 2) return error.InvalidTerrainPaintLayers;
    const expected = @as(usize, source_size) * @as(usize, source_size) * layer_count;
    if (splat.len != expected) return error.InvalidTerrainSplatCount;
    if (source_size == target_size) return allocator.dupe(u8, splat);

    const target_count = @as(usize, target_size) * @as(usize, target_size) * layer_count;
    const out = try allocator.alloc(u8, target_count);
    const src_grid: usize = @intCast(source_size);
    const tgt_grid: usize = @intCast(target_size);
    var z: usize = 0;
    while (z < tgt_grid) : (z += 1) {
        var x: usize = 0;
        while (x < tgt_grid) : (x += 1) {
            const src_x = @min(src_grid - 1, (x * (src_grid - 1)) / @max(tgt_grid - 1, 1));
            const src_z = @min(src_grid - 1, (z * (src_grid - 1)) / @max(tgt_grid - 1, 1));
            const dst_base = (z * tgt_grid + x) * layer_count;
            const src_base = (src_z * src_grid + src_x) * layer_count;
            @memcpy(out[dst_base..][0..layer_count], splat[src_base..][0..layer_count]);
        }
    }
    return out;
}

fn loadTileMaterial(state: *ProjectEditorState, id: world.cell.CellId) ![]u8 {
    const doc = try modules.terrain.authoring.loadCell(state.allocator, state.io, state.project_path, try manifest.pathForState(state), id);
    if (doc) |loaded| {
        var owned_doc = loaded;
        defer owned_doc.deinit();
        if (owned_doc.tiles.items.len != 1) return error.InvalidTerrainDocument;
        return state.allocator.dupe(u8, owned_doc.tiles.items[0].material);
    }
    return state.allocator.dupe(u8, "terrain.editor");
}

pub fn upsertTerrainTile(
    state: *ProjectEditorState,
    id: world.cell.CellId,
    heights: []const f32,
    splat: []const u8,
    material: []const u8,
) !void {
    var palette = try loadOrDefaultPaintPalette(state, id);
    defer palette.deinit(state.allocator);
    try modules.terrain.authoring.upsertTileFile(state.allocator, state.io, state.project_path, try manifest.pathForState(state), .{
        .cell = id,
        .size = terrain_tile_size,
        .lod_levels = &terrain_lod_levels,
        .heights = heights,
        .splat_size = terrain_tile_size,
        .splat = splat,
        .paint_layers = palette.layers,
        .paint_colors = palette.colors,
        .paint_albedo_textures = palette.albedo_textures,
        .paint_roughness_textures = palette.roughness_textures,
        .paint_specular_textures = palette.specular_textures,
        .paint_displacement_textures = palette.displacement_textures,
        .material = material,
    });
}

pub fn snapshotTerrainEdit(state: *ProjectEditorState, id: world.cell.CellId, transaction_id: u64) !void {
    const tx = project_editor_terrain_undo_store.beginTransaction(transaction_id);
    const region_path = try modules.terrain.chunk_store.regionPath(state.allocator, id);
    defer state.allocator.free(region_path);
    _ = try project_editor_terrain_undo_store.snapshotFileOnce(state.allocator, state.io, state.project_path, tx, region_path);
    _ = try project_editor_terrain_undo_store.snapshotFileOnce(state.allocator, state.io, state.project_path, tx, "layers/terrain/index.kdl");
}

pub fn pruneTerrainUndo(state: *ProjectEditorState) void {
    _ = project_editor_terrain_undo_store.pruneAfterTransaction(state.allocator, state.io, state.project_path, state.terrain_undo_limit_mb) catch {};
}

fn nowNs(state: *ProjectEditorState) u64 {
    const ns = std.Io.Clock.awake.now(state.io).nanoseconds;
    if (ns <= 0) return 0;
    return @intCast(ns);
}

fn dupePaintLayers(allocator: std.mem.Allocator, layers: []const []const u8) ![][]u8 {
    const owned = try allocator.alloc([]u8, layers.len);
    var copied: usize = 0;
    errdefer {
        for (owned[0..copied]) |layer| allocator.free(layer);
        allocator.free(owned);
    }
    for (layers, 0..) |layer, index| {
        owned[index] = try allocator.dupe(u8, layer);
        copied += 1;
    }
    return owned;
}

fn freeStringList(allocator: std.mem.Allocator, list: [][]u8) void {
    for (list) |item| allocator.free(item);
    allocator.free(list);
}

fn fillDefaultPaintWeights(weights: []u8, layer_count: usize) void {
    std.debug.assert(layer_count >= 2);
    std.debug.assert(weights.len % layer_count == 0);
    var sample: usize = 0;
    const sample_count = weights.len / layer_count;
    while (sample < sample_count) : (sample += 1) {
        const base = sample * layer_count;
        weights[base] = 255;
        @memset(weights[base + 1 .. base + layer_count], 0);
    }
}

fn paintLayerIndexFromBrush(state: *const ProjectEditorState, layer_count: usize) usize {
    std.debug.assert(layer_count >= 2);
    const raw = @as(usize, state.world_brush_material) * 64 + @as(usize, state.world_brush_tile);
    return raw % layer_count;
}

fn blendPaintLayer(weights: []u8, sample_index: usize, layer_count: usize, target_layer: usize, strength: f32) void {
    const base = sample_index * layer_count;
    const clamped_strength = std.math.clamp(strength, 0, 1);
    var layer: usize = 0;
    while (layer < layer_count) : (layer += 1) {
        const target: f32 = if (layer == target_layer) 255 else 0;
        const current = @as(f32, @floatFromInt(weights[base + layer]));
        weights[base + layer] = @intFromFloat(@round(std.math.clamp(current + clamped_strength * (target - current), 0, 255)));
    }
}

test "terrain default paint layer names resolve to palette indices" {
    try std.testing.expectEqual(@as(usize, 0), try defaultPaintLayerIndex("grass"));
    try std.testing.expectEqual(@as(usize, 3), try defaultPaintLayerIndex("rock"));
    try std.testing.expectEqual(@as(usize, 5), try defaultPaintLayerIndex("road"));
    try std.testing.expectEqual(@as(usize, 9), try defaultPaintLayerIndex("ash"));
    try std.testing.expectError(error.InvalidTerrainPaintLayer, defaultPaintLayerIndex("snow"));
}
