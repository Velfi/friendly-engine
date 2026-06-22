const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const zigimg = @import("zigimg");

const project_editor_state = @import("project_editor_state.zig");
const project_editor_terrain_undo_store = @import("project_editor_terrain_undo_store.zig");
const terrain = @import("project_editor_world_authoring_terrain.zig");
const manifest = @import("project_editor_world_authoring_manifest.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const editor_math = shared.editor_math;
const modules = friendly_engine.modules;
const world = friendly_engine.world;
const terrain_chunk_store = modules.terrain.chunk_store;

const terrain_empty_scene_path = "scenes/terrain_empty.kdl";
const floor_luma_tolerance: f32 = 2.0;
const cliff_top_fraction: f32 = 0.06;
const land_height_gamma: f32 = 1.35;

pub const BatchOptions = struct {
    path: []const u8,
    albedo_path: ?[]const u8 = null,
    min_x: i32,
    max_x: i32,
    min_z: i32,
    max_z: i32,
    cell_size_m: f32,
    min_height: f32,
    max_height: f32,
    material: []const u8,
};

pub const BatchResult = struct {
    min_x: i32,
    max_x: i32,
    min_z: i32,
    max_z: i32,
    cell_size_m: f32,
    cells: u64,
    min_height: f32,
    max_height: f32,
    source_width: u32,
    source_height: u32,
    albedo_source_width: u32,
    albedo_source_height: u32,
    dirty_overflow: bool,
};

const SourceHeightmap = struct {
    rgba: []const u8,
    floor_mask: []const bool,
    width: u32,
    height: u32,
    min_height: f32,
    max_height: f32,
    floor_luma: f32,
    land_min_luma: f32,
    land_max_luma: f32,
    world_min_x: f32,
    world_min_z: f32,
    world_width: f32,
    world_depth: f32,
};

const SourceAlbedo = struct {
    rgba: []const u8,
    width: u32,
    height: u32,
    world_min_x: f32,
    world_min_z: f32,
    world_width: f32,
    world_depth: f32,
};

pub fn loadBatch(state: *ProjectEditorState, options: BatchOptions) !BatchResult {
    try validateOptions(options);

    const bytes = try readHeightmapBytes(state.allocator, state.io, state.project_path, options.path);
    defer state.allocator.free(bytes);

    var image = try zigimg.Image.fromMemory(state.allocator, bytes);
    defer image.deinit(state.allocator);
    try image.convert(state.allocator, .rgba32);
    const floor_mask = try buildFloorMask(state.allocator, image.rawBytes(), @intCast(image.width), @intCast(image.height));
    defer state.allocator.free(floor_mask);
    const height_stats = analyzeHeightmap(image.rawBytes(), floor_mask, @intCast(image.width), @intCast(image.height));

    var albedo_image: ?zigimg.Image = null;
    defer if (albedo_image) |*img| img.deinit(state.allocator);
    if (options.albedo_path) |albedo_path| {
        if (albedo_path.len > 0) {
            const albedo_bytes = try readHeightmapBytes(state.allocator, state.io, state.project_path, albedo_path);
            defer state.allocator.free(albedo_bytes);
            albedo_image = try zigimg.Image.fromMemory(state.allocator, albedo_bytes);
            try albedo_image.?.convert(state.allocator, .rgba32);
        }
    }

    const tx = project_editor_terrain_undo_store.beginTransaction(nowNs(state));
    _ = try project_editor_terrain_undo_store.snapshotTerrainRegionsForReplace(state.allocator, state.io, state.project_path, tx);
    _ = try project_editor_terrain_undo_store.snapshotFileOnce(state.allocator, state.io, state.project_path, tx, "layers/terrain/index.kdl");
    _ = try project_editor_terrain_undo_store.snapshotFileOnce(state.allocator, state.io, state.project_path, tx, manifest.world_manifest_path);

    try deleteTerrainRegionPacks(state);
    try writeEmptyScene(state);

    const width_cells = @as(u64, @intCast(options.max_x - options.min_x + 1));
    const depth_cells = @as(u64, @intCast(options.max_z - options.min_z + 1));
    const total = width_cells * depth_cells;
    const source = SourceHeightmap{
        .rgba = image.rawBytes(),
        .floor_mask = floor_mask,
        .width = @intCast(image.width),
        .height = @intCast(image.height),
        .min_height = options.min_height,
        .max_height = options.max_height,
        .floor_luma = height_stats.floor_luma,
        .land_min_luma = height_stats.land_min_luma,
        .land_max_luma = height_stats.land_max_luma,
        .world_min_x = @as(f32, @floatFromInt(options.min_x)) * options.cell_size_m,
        .world_min_z = @as(f32, @floatFromInt(options.min_z)) * options.cell_size_m,
        .world_width = @as(f32, @floatFromInt(width_cells)) * options.cell_size_m,
        .world_depth = @as(f32, @floatFromInt(depth_cells)) * options.cell_size_m,
    };
    var albedo_source: ?SourceAlbedo = null;
    if (albedo_image) |*img| {
        albedo_source = .{
            .rgba = img.rawBytes(),
            .width = @intCast(img.width),
            .height = @intCast(img.height),
            .world_min_x = source.world_min_x,
            .world_min_z = source.world_min_z,
            .world_width = source.world_width,
            .world_depth = source.world_depth,
        };
    }

    var observed_min = std.math.inf(f32);
    var observed_max = -std.math.inf(f32);
    var dirty_overflow = false;
    var offset: u64 = 0;
    while (offset < total) : (offset += 1) {
        const id = cellAtOffset(options, offset);
        const stats = try writeTerrainTile(state, options, source, albedo_source, id);
        observed_min = @min(observed_min, stats.min_height);
        observed_max = @max(observed_max, stats.max_height);
        project_editor_state.markDirtyCell(state, "Terrain", id, "heightmap batch import") catch |err| switch (err) {
            error.TooManyDirtyCells => dirty_overflow = true,
            else => return err,
        };
    }

    try writeWorldManifest(state, options, total);
    try writeTerrainIndex(state, options, total);
    if (state.active_world_manifest_path_owned) state.allocator.free(state.active_world_manifest_path);
    state.active_world_manifest_path = try state.allocator.dupe(u8, manifest.world_manifest_path);
    state.active_world_manifest_path_owned = true;
    state.world_cell_size_m = options.cell_size_m;
    state.mode = .world_creation;
    state.world_tool = .terrain;
    state.selected_world_layer = .terrain_base_height;
    state.terrain_preview_stale = true;
    var status_buf: [160]u8 = undefined;
    project_editor_state.setStatus(state, std.fmt.bufPrint(&status_buf, "Heightmap batch loaded: {d} cells", .{total}) catch "Heightmap batch loaded");
    _ = project_editor_terrain_undo_store.pruneAfterTransaction(state.allocator, state.io, state.project_path, state.terrain_undo_limit_mb) catch {};

    return .{
        .min_x = options.min_x,
        .max_x = options.max_x,
        .min_z = options.min_z,
        .max_z = options.max_z,
        .cell_size_m = options.cell_size_m,
        .cells = total,
        .min_height = observed_min,
        .max_height = observed_max,
        .source_width = @intCast(image.width),
        .source_height = @intCast(image.height),
        .albedo_source_width = if (albedo_image) |img| @intCast(img.width) else 0,
        .albedo_source_height = if (albedo_image) |img| @intCast(img.height) else 0,
        .dirty_overflow = dirty_overflow,
    };
}

fn nowNs(state: *ProjectEditorState) u64 {
    const ns = std.Io.Clock.awake.now(state.io).nanoseconds;
    if (ns <= 0) return 0;
    return @intCast(ns);
}

fn validateOptions(options: BatchOptions) !void {
    if (options.path.len == 0) return error.InvalidHeightmapPath;
    if (options.max_x < options.min_x or options.max_z < options.min_z) return error.InvalidTerrainBatchBounds;
    if (!std.math.isFinite(options.cell_size_m) or options.cell_size_m <= 0) return error.InvalidTerrainBatchCellSize;
    if (!std.math.isFinite(options.min_height) or !std.math.isFinite(options.max_height)) return error.InvalidHeightmapRange;
    if (options.min_height >= options.max_height) return error.InvalidHeightmapRange;
}

fn writeTerrainTile(state: *ProjectEditorState, options: BatchOptions, source: SourceHeightmap, albedo_source: ?SourceAlbedo, id: world.cell.CellId) !struct { min_height: f32, max_height: f32 } {
    const sample_count = @as(usize, terrain.terrain_tile_size) * @as(usize, terrain.terrain_tile_size);
    const layer_count = terrain.default_paint_layers.len;
    const heights = try state.allocator.alloc(f32, sample_count);
    defer state.allocator.free(heights);
    const splat = try state.allocator.alloc(u8, sample_count * layer_count);
    defer state.allocator.free(splat);

    var min_height = std.math.inf(f32);
    var max_height = -std.math.inf(f32);
    const cell_min_x = @as(f32, @floatFromInt(id.x)) * options.cell_size_m;
    const cell_min_z = @as(f32, @floatFromInt(id.y)) * options.cell_size_m;
    const step = options.cell_size_m / @as(f32, @floatFromInt(terrain.terrain_tile_size - 1));

    var z: usize = 0;
    while (z < terrain.terrain_tile_size) : (z += 1) {
        var x: usize = 0;
        while (x < terrain.terrain_tile_size) : (x += 1) {
            const world_x = cell_min_x + @as(f32, @floatFromInt(x)) * step;
            const world_z = cell_min_z + @as(f32, @floatFromInt(z)) * step;
            const height = quantizeHeight(sampleHeight(source, world_x, world_z));
            const index = z * terrain.terrain_tile_size + x;
            heights[index] = height;
            min_height = @min(min_height, height);
            max_height = @max(max_height, height);

            const layer = if (albedo_source) |albedo| paintLayerFromAlbedo(albedo, world_x, world_z) else paintLayer(height);
            const base = index * layer_count;
            @memset(splat[base..][0..layer_count], 0);
            splat[base + layer] = 255;
        }
    }

    const path = try terrain_chunk_store.upsertTile(state.allocator, state.io, state.project_path, .{
        .cell = id,
        .size = terrain.terrain_tile_size,
        .lod_levels = &terrain.terrain_lod_levels,
        .heights = heights,
        .splat_size = terrain.terrain_tile_size,
        .splat = splat,
        .paint_layers = &terrain.default_paint_layers,
        .paint_colors = &terrain.default_paint_colors,
        .paint_albedo_textures = &terrain.default_paint_albedo_textures,
        .paint_roughness_textures = &terrain.default_paint_roughness_textures,
        .paint_specular_textures = &terrain.default_paint_specular_textures,
        .paint_displacement_textures = &terrain.default_paint_displacement_textures,
        .material = options.material,
    });
    state.allocator.free(path);
    return .{ .min_height = min_height, .max_height = max_height };
}

fn sampleHeight(source: SourceHeightmap, world_x: f32, world_z: f32) f32 {
    const u = std.math.clamp((world_x - source.world_min_x) / source.world_width, 0, 1);
    const v = std.math.clamp((world_z - source.world_min_z) / source.world_depth, 0, 1);
    const src_x = u * @as(f32, @floatFromInt(source.width - 1));
    const src_z = v * @as(f32, @floatFromInt(source.height - 1));
    if (sampleNearestFloor(source, src_x, src_z)) {
        return source.min_height;
    }
    const luma = smoothLandLuminance(source, src_x, src_z);
    const denominator = @max(1, source.land_max_luma - source.land_min_luma);
    const t = std.math.clamp((luma - source.land_min_luma) / denominator, 0, 1);
    const shaped = std.math.pow(f32, t, land_height_gamma);
    const cliff_top = source.min_height + (source.max_height - source.min_height) * cliff_top_fraction;
    return cliff_top + (source.max_height - cliff_top) * shaped;
}

fn sampleRawHeight(source: SourceHeightmap, src_x: f32, src_z: f32) f32 {
    const x0: u32 = @intFromFloat(@floor(src_x));
    const z0: u32 = @intFromFloat(@floor(src_z));
    const x1 = @min(x0 + 1, source.width - 1);
    const z1 = @min(z0 + 1, source.height - 1);
    const tx = src_x - @as(f32, @floatFromInt(x0));
    const tz = src_z - @as(f32, @floatFromInt(z0));
    const a = luminance(source, x0, z0);
    const b = luminance(source, x1, z0);
    const c = luminance(source, x0, z1);
    const d = luminance(source, x1, z1);
    const ab = a + (b - a) * tx;
    const cd = c + (d - c) * tx;
    const t = (ab + (cd - ab) * tz) / 255.0;
    return source.min_height + (source.max_height - source.min_height) * t;
}

fn sampleNearestFloor(source: SourceHeightmap, src_x: f32, src_z: f32) bool {
    const x: u32 = @intFromFloat(@round(std.math.clamp(src_x, 0, @as(f32, @floatFromInt(source.width - 1)))));
    const z: u32 = @intFromFloat(@round(std.math.clamp(src_z, 0, @as(f32, @floatFromInt(source.height - 1)))));
    return source.floor_mask[@as(usize, z) * @as(usize, source.width) + @as(usize, x)];
}

fn smoothLandLuminance(source: SourceHeightmap, src_x: f32, src_z: f32) f32 {
    const center_x: i32 = @intFromFloat(@round(src_x));
    const center_z: i32 = @intFromFloat(@round(src_z));
    var total: f32 = 0;
    var weight_total: f32 = 0;
    const radius: i32 = 4;
    var dz: i32 = -radius;
    while (dz <= radius) : (dz += 1) {
        var dx: i32 = -radius;
        while (dx <= radius) : (dx += 1) {
            const sx = @max(0, @min(@as(i32, @intCast(source.width - 1)), center_x + dx));
            const sz = @max(0, @min(@as(i32, @intCast(source.height - 1)), center_z + dz));
            if (source.floor_mask[@as(usize, @intCast(sz)) * @as(usize, source.width) + @as(usize, @intCast(sx))]) continue;
            const luma = luminance(source, @intCast(sx), @intCast(sz));
            const distance: i32 = @intCast(@max(@abs(dx), @abs(dz)));
            const weight: f32 = @floatFromInt(radius + 1 - distance);
            total += luma * weight;
            weight_total += weight;
        }
    }
    if (weight_total <= 0) return source.land_min_luma;
    return total / weight_total;
}

fn luminance(source: SourceHeightmap, x: u32, z: u32) f32 {
    const idx = (@as(usize, z) * @as(usize, source.width) + @as(usize, x)) * 4;
    return @as(f32, @floatFromInt(source.rgba[idx])) * 0.2126 +
        @as(f32, @floatFromInt(source.rgba[idx + 1])) * 0.7152 +
        @as(f32, @floatFromInt(source.rgba[idx + 2])) * 0.0722;
}

fn pixelLuminance(rgba: []const u8, index: usize) f32 {
    const idx = index * 4;
    return @as(f32, @floatFromInt(rgba[idx])) * 0.2126 +
        @as(f32, @floatFromInt(rgba[idx + 1])) * 0.7152 +
        @as(f32, @floatFromInt(rgba[idx + 2])) * 0.0722;
}

fn buildFloorMask(allocator: std.mem.Allocator, rgba: []const u8, width: u32, height: u32) ![]bool {
    const total = @as(usize, width) * @as(usize, height);
    const mask = try allocator.alloc(bool, total);
    errdefer allocator.free(mask);
    @memset(mask, false);
    const queue = try allocator.alloc(usize, total);
    defer allocator.free(queue);

    var floor_luma = std.math.inf(f32);
    var i: usize = 0;
    while (i < total) : (i += 1) floor_luma = @min(floor_luma, pixelLuminance(rgba, i));
    const cutoff = floor_luma + floor_luma_tolerance;

    var head: usize = 0;
    var tail: usize = 0;
    const w: usize = @intCast(width);
    const h: usize = @intCast(height);
    var x: usize = 0;
    while (x < w) : (x += 1) {
        tail = enqueueFloor(rgba, mask, queue, tail, x, cutoff);
        tail = enqueueFloor(rgba, mask, queue, tail, (h - 1) * w + x, cutoff);
    }
    var z: usize = 1;
    while (z + 1 < h) : (z += 1) {
        tail = enqueueFloor(rgba, mask, queue, tail, z * w, cutoff);
        tail = enqueueFloor(rgba, mask, queue, tail, z * w + (w - 1), cutoff);
    }

    while (head < tail) : (head += 1) {
        const current = queue[head];
        const cx = current % w;
        const cz = current / w;
        if (cx > 0) tail = enqueueFloor(rgba, mask, queue, tail, current - 1, cutoff);
        if (cx + 1 < w) tail = enqueueFloor(rgba, mask, queue, tail, current + 1, cutoff);
        if (cz > 0) tail = enqueueFloor(rgba, mask, queue, tail, current - w, cutoff);
        if (cz + 1 < h) tail = enqueueFloor(rgba, mask, queue, tail, current + w, cutoff);
    }
    return mask;
}

fn enqueueFloor(rgba: []const u8, mask: []bool, queue: []usize, tail: usize, index: usize, cutoff: f32) usize {
    if (mask[index] or pixelLuminance(rgba, index) > cutoff) return tail;
    mask[index] = true;
    queue[tail] = index;
    return tail + 1;
}

const HeightStats = struct {
    floor_luma: f32,
    land_min_luma: f32,
    land_max_luma: f32,
};

fn analyzeHeightmap(rgba: []const u8, floor_mask: []const bool, width: u32, height: u32) HeightStats {
    var floor_luma = std.math.inf(f32);
    var hist = [_]u32{0} ** 256;
    var land_count: u32 = 0;
    const total = @as(usize, width) * @as(usize, height);
    var i: usize = 0;
    while (i < total) : (i += 1) {
        const luma = pixelLuminance(rgba, i);
        floor_luma = @min(floor_luma, luma);
        if (!floor_mask[i]) {
            const bucket: usize = @intFromFloat(std.math.clamp(@round(luma), 0, 255));
            hist[bucket] += 1;
            land_count += 1;
        }
    }

    const land_min_luma = percentileFromHist(&hist, land_count, 0.03) orelse floor_luma;
    const land_max_luma = percentileFromHist(&hist, land_count, 0.995) orelse 255;
    return .{ .floor_luma = floor_luma, .land_min_luma = land_min_luma, .land_max_luma = land_max_luma };
}

fn percentileFromHist(hist: *const [256]u32, count: u32, percentile: f32) ?f32 {
    if (count == 0) return null;
    const target: u32 = @max(@as(u32, 1), @as(u32, @intFromFloat(@ceil(@as(f32, @floatFromInt(count)) * percentile))));
    var cumulative: u32 = 0;
    for (hist, 0..) |bucket_count, index| {
        cumulative += bucket_count;
        if (cumulative >= target) return @floatFromInt(index);
    }
    return 255;
}

fn paintLayerFromAlbedo(source: SourceAlbedo, world_x: f32, world_z: f32) usize {
    const u = std.math.clamp((world_x - source.world_min_x) / source.world_width, 0, 1);
    const v = std.math.clamp((world_z - source.world_min_z) / source.world_depth, 0, 1);
    const x: u32 = @intFromFloat(@round(u * @as(f32, @floatFromInt(source.width - 1))));
    const z: u32 = @intFromFloat(@round(v * @as(f32, @floatFromInt(source.height - 1))));
    const idx = (@as(usize, z) * @as(usize, source.width) + @as(usize, x)) * 4;
    return nearestPaintLayer(source.rgba[idx], source.rgba[idx + 1], source.rgba[idx + 2]);
}

fn nearestPaintLayer(r: u8, g: u8, b: u8) usize {
    var best_index: usize = 0;
    var best_distance: u32 = std.math.maxInt(u32);
    for (terrain.default_paint_colors, 0..) |color, index| {
        const dr = @as(i32, r) - @as(i32, color[0]);
        const dg = @as(i32, g) - @as(i32, color[1]);
        const db = @as(i32, b) - @as(i32, color[2]);
        const distance: u32 = @intCast(dr * dr + dg * dg + db * db);
        if (distance < best_distance) {
            best_distance = distance;
            best_index = index;
        }
    }
    return best_index;
}

fn paintLayer(height: f32) usize {
    if (height < -2) return 4;
    if (height < 18) return 1;
    if (height > 570) return 3;
    if (height > 260) return 2;
    return 0;
}

fn quantizeHeight(value: f32) f32 {
    return @round(value * 10) / 10;
}

fn cellAtOffset(options: BatchOptions, offset: u64) world.cell.CellId {
    const width: u64 = @intCast(options.max_x - options.min_x + 1);
    const local_x: i32 = @intCast(offset % width);
    const local_z: i32 = @intCast(offset / width);
    return .{ .x = options.min_x + local_x, .y = options.min_z + local_z, .z = 0 };
}

fn writeWorldManifest(state: *ProjectEditorState, options: BatchOptions, cell_count: u64) !void {
    var bytes: std.Io.Writer.Allocating = .init(state.allocator);
    defer bytes.deinit();
    const writer = &bytes.writer;
    try writer.print("world version=1 id=\"main\" cell_size_m={d} {{\n", .{options.cell_size_m});
    var offset: u64 = 0;
    while (offset < cell_count) : (offset += 1) {
        const id = cellAtOffset(options, offset);
        try writer.print("  cell coord=\"{d},{d},{d}\" authoring=\"{s}\"\n", .{ id.x, id.y, id.z, terrain_empty_scene_path });
    }
    try writer.writeAll("}\n");
    try manifest.writeLayerBytes(state, manifest.world_manifest_path, bytes.written());
}

fn writeTerrainIndex(state: *ProjectEditorState, options: BatchOptions, cell_count: u64) !void {
    var bytes: std.Io.Writer.Allocating = .init(state.allocator);
    defer bytes.deinit();
    const writer = &bytes.writer;
    try writer.writeAll("terrain_index version=1 {\n");
    var offset: u64 = 0;
    while (offset < cell_count) : (offset += 1) {
        const id = cellAtOffset(options, offset);
        const path = try terrain_chunk_store.regionPath(state.allocator, id);
        defer state.allocator.free(path);
        try writer.print("  tile cell=\"{d},{d},{d}\" path=\"{s}\"\n", .{ id.x, id.y, id.z, path });
    }
    try writer.writeAll("}\n");
    try manifest.writeLayerBytes(state, "layers/terrain/index.kdl", bytes.written());
}

fn writeEmptyScene(state: *ProjectEditorState) !void {
    try manifest.writeLayerBytes(state, terrain_empty_scene_path,
        \\scene version=1 next_object_id=2 {
        \\  entity id=1 name="Terrain Anchor" {
        \\    transform position="0,0,0" rotation="0,0,0" scale="1,1,1"
        \\    meta kind=empty enabled=true visible=true cast_shadows=false receive_shadows=false
        \\  }
        \\}
        \\
    );
}

fn deleteTerrainRegionPacks(state: *ProjectEditorState) !void {
    var project_dir = if (std.fs.path.isAbsolute(state.project_path))
        try std.Io.Dir.openDirAbsolute(state.io, state.project_path, .{})
    else
        try std.Io.Dir.cwd().openDir(state.io, state.project_path, .{});
    defer project_dir.close(state.io);

    var regions_dir = project_dir.openDir(state.io, "layers/terrain/regions", .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer regions_dir.close(state.io);

    var walker = try regions_dir.walk(state.allocator);
    defer walker.deinit();
    while (try walker.next(state.io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.basename, ".fetr")) continue;
        regions_dir.deleteFile(state.io, entry.path) catch |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        };
    }
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

test "batch validation rejects invalid bounds and ranges" {
    try std.testing.expectError(error.InvalidTerrainBatchBounds, validateOptions(.{
        .path = "height.png",
        .min_x = 2,
        .max_x = 1,
        .min_z = 0,
        .max_z = 0,
        .cell_size_m = 256,
        .min_height = -25,
        .max_height = 760,
        .material = "terrain.editor",
    }));
    try std.testing.expectError(error.InvalidHeightmapRange, validateOptions(.{
        .path = "height.png",
        .min_x = 0,
        .max_x = 1,
        .min_z = 0,
        .max_z = 0,
        .cell_size_m = 256,
        .min_height = 8,
        .max_height = 8,
        .material = "terrain.editor",
    }));
}

test "batch source sampling preserves shared edge heights" {
    var rgba = [_]u8{
        0, 0, 0, 255, 85, 85, 85, 255, 170, 170, 170, 255, 255, 255, 255, 255,
        0, 0, 0, 255, 85, 85, 85, 255, 170, 170, 170, 255, 255, 255, 255, 255,
        0, 0, 0, 255, 85, 85, 85, 255, 170, 170, 170, 255, 255, 255, 255, 255,
        0, 0, 0, 255, 85, 85, 85, 255, 170, 170, 170, 255, 255, 255, 255, 255,
    };
    const source = SourceHeightmap{
        .rgba = &rgba,
        .floor_mask = &([_]bool{false} ** 16),
        .width = 4,
        .height = 4,
        .min_height = 0,
        .max_height = 30,
        .floor_luma = 0,
        .land_min_luma = 0,
        .land_max_luma = 1,
        .world_min_x = 0,
        .world_min_z = 0,
        .world_width = 20,
        .world_depth = 10,
    };
    const left_edge = sampleHeight(source, 10, 5);
    const right_edge = sampleHeight(source, 10, 5);
    try std.testing.expectApproxEqAbs(left_edge, right_edge, 0.0001);
}
