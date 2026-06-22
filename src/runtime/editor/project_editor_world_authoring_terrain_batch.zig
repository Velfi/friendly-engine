const std = @import("std");
const friendly_engine = @import("friendly_engine");

const project_editor_state = @import("project_editor_state.zig");
const project_editor_terrain_undo_store = @import("project_editor_terrain_undo_store.zig");
const project_editor_types = @import("project_editor_types.zig");
const terrain = @import("project_editor_world_authoring_terrain.zig");
const manifest = @import("project_editor_world_authoring_manifest.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const TerrainBatchJob = project_editor_types.TerrainBatchJob;
const TerrainFormation = project_editor_types.TerrainFormation;
const terrain_chunk_store = friendly_engine.modules.terrain.chunk_store;
const world = friendly_engine.world;
const terrain_empty_scene_path = "scenes/terrain_empty.kdl";

pub const StartOptions = struct {
    min_x: i32,
    max_x: i32,
    min_z: i32,
    max_z: i32,
    cell_size_m: f32,
    batch_size: u32,
    seed: u64,
    formations: []const TerrainFormation,
};

pub fn start(state: *ProjectEditorState, options: StartOptions) !void {
    if (options.max_x < options.min_x or options.max_z < options.min_z) return error.InvalidTerrainBatchBounds;
    if (!std.math.isFinite(options.cell_size_m) or options.cell_size_m <= 0) return error.InvalidTerrainBatchCellSize;
    if (options.batch_size != 1) return error.TerrainBatchStreamsOneCellAtATime;

    const width: u64 = @intCast(options.max_x - options.min_x + 1);
    const depth: u64 = @intCast(options.max_z - options.min_z + 1);
    if (options.formations.len == 0 or options.formations.len > 16) return error.InvalidTerrainFormationCount;
    const tx = project_editor_terrain_undo_store.beginTransaction(nowNs(state));
    var undo_snapshots = try project_editor_terrain_undo_store.snapshotTerrainRegionsForReplace(state.allocator, state.io, state.project_path, tx);
    if (try project_editor_terrain_undo_store.snapshotFileOnce(state.allocator, state.io, state.project_path, tx, "layers/terrain/index.kdl")) {
        undo_snapshots += 1;
    }
    if (try project_editor_terrain_undo_store.snapshotFileOnce(state.allocator, state.io, state.project_path, tx, manifest.world_manifest_path)) {
        undo_snapshots += 1;
    }

    try deleteLegacyTerrainTileKdl(state);
    try deleteTerrainRegionPacks(state);
    try deleteLegacyTerrainCellScenes(state);
    try writeEmptyScene(state);

    var job = TerrainBatchJob{
        .id = options.seed ^ (@as(u64, @intCast(width)) << 32) ^ @as(u64, @intCast(depth)),
        .started_ns = nowNs(state),
        .min_x = options.min_x,
        .max_x = options.max_x,
        .min_z = options.min_z,
        .max_z = options.max_z,
        .cell_size_m = options.cell_size_m,
        .total = width * depth,
        .batch_size = 1,
        .flush_interval_cells = flushIntervalForTotal(width * depth),
        .seed = options.seed,
        .undo_transaction_id = tx.id,
        .undo_snapshots = undo_snapshots,
        .active = true,
        .formation_count = @intCast(options.formations.len),
    };
    @memcpy(job.formations[0..options.formations.len], options.formations);
    try writeWorldManifest(state, job, 0);
    try writeTerrainIndex(state, job, 0);
    job.setStatus("Terrain batch queued");
    state.terrain_batch_job = job;
    state.mode = .world_creation;
    state.world_tool = .terrain;
    state.selected_world_layer = .terrain_base_height;
    state.world_cell_size_m = options.cell_size_m;
    project_editor_state.setStatus(state, "Terrain batch queued");
}

pub fn cancel(state: *ProjectEditorState) void {
    if (state.terrain_batch_job) |*job| {
        job.active = false;
        job.cancelled = true;
        _ = project_editor_terrain_undo_store.pruneAfterTransaction(state.allocator, state.io, state.project_path, state.terrain_undo_limit_mb) catch {};
        writeWorldManifest(state, job.*, job.next_offset) catch {};
        writeTerrainIndex(state, job.*, job.next_offset) catch {};
        job.setStatus("Terrain batch cancelled");
        project_editor_state.setStatus(state, "Terrain batch cancelled");
    }
}

pub fn tick(state: *ProjectEditorState) !void {
    var job = &(state.terrain_batch_job orelse return);
    if (!job.active or job.complete or job.cancelled or job.failed) return;

    if (job.next_offset >= job.total) {
        flushIndexes(state, job, job.next_offset) catch |err| {
            failJob(state, job, err);
            return err;
        };
        job.active = false;
        job.complete = true;
        _ = project_editor_terrain_undo_store.pruneAfterTransaction(state.allocator, state.io, state.project_path, state.terrain_undo_limit_mb) catch {};
        job.setStatus("Terrain batch complete");
        project_editor_state.setStatus(state, "Terrain batch complete");
        return;
    }

    const tick_start_ns = nowNs(state);
    var offset = job.next_offset;
    var processed_this_tick: u32 = 0;
    while (offset < job.total) {
        const total_start_ns = nowNs(state);
        const id = cellAtOffset(job.*, offset);
        const scene_start_ns = nowNs(state);
        const tile_start_ns = nowNs(state);
        const stats = writeTerrainTile(state, job.*, id) catch |err| {
            failJob(state, job, err);
            return err;
        };
        const dirty_start_ns = nowNs(state);
        job.min_height = @min(job.min_height, stats.min_height);
        job.max_height = @max(job.max_height, stats.max_height);
        project_editor_state.markDirtyCell(state, "Terrain", id, "batch terrain") catch {};
        const end_ns = nowNs(state);
        recordProfile(job, .{
            .scene_ns = durationNs(scene_start_ns, tile_start_ns),
            .tile_ns = durationNs(tile_start_ns, dirty_start_ns),
            .manifest_ns = 0,
            .index_ns = 0,
            .dirty_ns = durationNs(dirty_start_ns, end_ns),
            .total_ns = durationNs(total_start_ns, end_ns),
        });

        offset += 1;
        processed_this_tick += 1;
        job.next_offset = offset;
        if (durationNs(tick_start_ns, end_ns) >= job.tick_budget_ns) break;
    }

    const flush_due = job.next_offset >= job.total or job.next_offset - job.flushed_offset >= job.flush_interval_cells;
    if (flush_due) {
        flushIndexes(state, job, job.next_offset) catch |err| {
            failJob(state, job, err);
            return err;
        };
    }

    const tick_end_ns = nowNs(state);
    job.last_tick_cells = processed_this_tick;
    job.last_tick_ns = durationNs(tick_start_ns, tick_end_ns);
    job.total_tick_ns +|= job.last_tick_ns;
    job.profiled_ticks += 1;
    if (job.next_offset >= job.total) {
        job.active = false;
        job.complete = true;
        _ = project_editor_terrain_undo_store.pruneAfterTransaction(state.allocator, state.io, state.project_path, state.terrain_undo_limit_mb) catch {};
    }

    var status_buf: [160]u8 = undefined;
    const status = std.fmt.bufPrint(&status_buf, "Terrain batch {d}/{d} cells", .{ job.next_offset, job.total }) catch "Terrain batch progress";
    job.setStatus(status);
    project_editor_state.setStatus(state, status);
    state.world_cell_size_m = job.cell_size_m;
    state.terrain_preview_stale = true;
}

fn flushIndexes(state: *ProjectEditorState, job: *TerrainBatchJob, processed_count: u64) !void {
    if (job.flushed_offset == processed_count and processed_count < job.total) return;
    const flush_start_ns = nowNs(state);
    const manifest_start_ns = flush_start_ns;
    try writeWorldManifest(state, job.*, processed_count);
    state.invalidateWorldCache();
    const index_start_ns = nowNs(state);
    try writeTerrainIndex(state, job.*, processed_count);
    const flush_end_ns = nowNs(state);
    const manifest_ns = durationNs(manifest_start_ns, index_start_ns);
    const index_ns = durationNs(index_start_ns, flush_end_ns);
    job.flushed_offset = processed_count;
    job.last_manifest_ns = manifest_ns;
    job.last_index_ns = index_ns;
    job.last_flush_ns = durationNs(flush_start_ns, flush_end_ns);
    job.total_manifest_ns +|= manifest_ns;
    job.total_index_ns +|= index_ns;
    job.total_flush_ns +|= job.last_flush_ns;
    job.total_total_ns +|= job.last_flush_ns;
    job.profiled_flushes += 1;
}

const CellProfile = struct {
    scene_ns: u64,
    tile_ns: u64,
    manifest_ns: u64,
    index_ns: u64,
    dirty_ns: u64,
    total_ns: u64,
};

fn durationNs(start_ns: u64, end_ns: u64) u64 {
    if (end_ns <= start_ns) return 0;
    return end_ns - start_ns;
}

fn nowNs(state: *ProjectEditorState) u64 {
    const ns = std.Io.Clock.awake.now(state.io).nanoseconds;
    if (ns <= 0) return 0;
    return @intCast(ns);
}

fn recordProfile(job: *TerrainBatchJob, profile: CellProfile) void {
    job.profiled_cells += 1;
    job.last_scene_ns = profile.scene_ns;
    job.last_tile_ns = profile.tile_ns;
    job.last_manifest_ns = profile.manifest_ns;
    job.last_index_ns = profile.index_ns;
    job.last_dirty_ns = profile.dirty_ns;
    job.last_total_ns = profile.total_ns;
    job.total_scene_ns +|= profile.scene_ns;
    job.total_tile_ns +|= profile.tile_ns;
    job.total_manifest_ns +|= profile.manifest_ns;
    job.total_index_ns +|= profile.index_ns;
    job.total_dirty_ns +|= profile.dirty_ns;
    job.total_total_ns +|= profile.total_ns;
}

fn flushIntervalForTotal(total: u64) u32 {
    if (total >= 8192) return 512;
    if (total >= 2048) return 256;
    return 64;
}

fn failJob(state: *ProjectEditorState, job: *TerrainBatchJob, err: anyerror) void {
    job.active = false;
    job.failed = true;
    _ = project_editor_terrain_undo_store.pruneAfterTransaction(state.allocator, state.io, state.project_path, state.terrain_undo_limit_mb) catch {};
    var buf: [160]u8 = undefined;
    const message = std.fmt.bufPrint(&buf, "Terrain batch failed: {s}", .{@errorName(err)}) catch "Terrain batch failed";
    job.setStatus(message);
    project_editor_state.setStatus(state, message);
}

fn writeWorldManifest(state: *ProjectEditorState, job: TerrainBatchJob, processed_count: u64) !void {
    var bytes: std.Io.Writer.Allocating = .init(state.allocator);
    defer bytes.deinit();
    const writer = &bytes.writer;
    try writer.print("world version=1 id=\"main\" cell_size_m={d} {{\n", .{job.cell_size_m});
    var offset: u64 = 0;
    while (offset < processed_count) : (offset += 1) {
        const id = cellAtOffset(job, offset);
        try writer.print("  cell coord=\"{d},{d},{d}\" authoring=\"{s}\"\n", .{ id.x, id.y, id.z, terrain_empty_scene_path });
    }
    try writer.writeAll("}\n");
    try manifest.writeLayerBytes(state, manifest.world_manifest_path, bytes.written());
}

fn writeTerrainIndex(state: *ProjectEditorState, job: TerrainBatchJob, processed_count: u64) !void {
    var bytes: std.Io.Writer.Allocating = .init(state.allocator);
    defer bytes.deinit();
    const writer = &bytes.writer;
    try writer.writeAll("terrain_index version=1 {\n");
    var offset: u64 = 0;
    while (offset < processed_count) : (offset += 1) {
        const id = cellAtOffset(job, offset);
        const path = try terrain_chunk_store.regionPath(state.allocator, id);
        defer state.allocator.free(path);
        try writer.print("  tile cell=\"{d},{d},{d}\" path=\"{s}\"\n", .{ id.x, id.y, id.z, path });
    }
    try writer.writeAll("}\n");
    try manifest.writeLayerBytes(state, "layers/terrain/index.kdl", bytes.written());
}

fn deleteLegacyTerrainTileKdl(state: *ProjectEditorState) !void {
    var project_dir = if (std.fs.path.isAbsolute(state.project_path))
        try std.Io.Dir.openDirAbsolute(state.io, state.project_path, .{})
    else
        try std.Io.Dir.cwd().openDir(state.io, state.project_path, .{});
    defer project_dir.close(state.io);

    var terrain_dir = project_dir.openDir(state.io, "layers/terrain", .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer terrain_dir.close(state.io);

    var walker = try terrain_dir.walk(state.allocator);
    defer walker.deinit();
    while (try walker.next(state.io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.startsWith(u8, entry.basename, "cell_") or !std.mem.endsWith(u8, entry.basename, ".kdl")) continue;
        terrain_dir.deleteFile(state.io, entry.path) catch |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        };
    }
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

fn deleteLegacyTerrainCellScenes(state: *ProjectEditorState) !void {
    var project_dir = if (std.fs.path.isAbsolute(state.project_path))
        try std.Io.Dir.openDirAbsolute(state.io, state.project_path, .{})
    else
        try std.Io.Dir.cwd().openDir(state.io, state.project_path, .{});
    defer project_dir.close(state.io);

    var scenes_dir = project_dir.openDir(state.io, "scenes", .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer scenes_dir.close(state.io);

    var walker = try scenes_dir.walk(state.allocator);
    defer walker.deinit();
    while (try walker.next(state.io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.startsWith(u8, entry.basename, "cell_") or !std.mem.endsWith(u8, entry.basename, ".kdl")) continue;
        scenes_dir.deleteFile(state.io, entry.path) catch |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        };
    }
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

const TileStats = struct {
    min_height: f32,
    max_height: f32,
};

fn writeTerrainTile(state: *ProjectEditorState, job: TerrainBatchJob, id: world.cell.CellId) !TileStats {
    const sample_count = @as(usize, terrain.terrain_tile_size) * @as(usize, terrain.terrain_tile_size);
    const layer_count = terrain.default_paint_layers.len;
    const heights = try state.allocator.alloc(f32, sample_count);
    defer state.allocator.free(heights);
    const splat = try state.allocator.alloc(u8, sample_count * layer_count);
    defer state.allocator.free(splat);

    var min_height: f32 = std.math.inf(f32);
    var max_height: f32 = -std.math.inf(f32);
    const cell_min_x = @as(f32, @floatFromInt(id.x)) * job.cell_size_m;
    const cell_min_z = @as(f32, @floatFromInt(id.y)) * job.cell_size_m;
    const step = job.cell_size_m / @as(f32, @floatFromInt(terrain.terrain_tile_size - 1));

    var z: usize = 0;
    while (z < terrain.terrain_tile_size) : (z += 1) {
        var x: usize = 0;
        while (x < terrain.terrain_tile_size) : (x += 1) {
            const world_x = cell_min_x + @as(f32, @floatFromInt(x)) * step;
            const world_z = cell_min_z + @as(f32, @floatFromInt(z)) * step;
            const height = quantizeHeight(heightAt(job, world_x, world_z));
            const index = z * terrain.terrain_tile_size + x;
            heights[index] = height;
            min_height = @min(min_height, height);
            max_height = @max(max_height, height);

            const layer = paintLayer(job, height, world_x, world_z);
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
        .material = "terrain.editor",
    });
    state.allocator.free(path);
    return .{ .min_height = min_height, .max_height = max_height };
}

fn cellAtOffset(job: TerrainBatchJob, offset: u64) world.cell.CellId {
    const width: u64 = @intCast(job.max_x - job.min_x + 1);
    const local_x: i32 = @intCast(offset % width);
    const local_z: i32 = @intCast(offset / width);
    return .{ .x = job.min_x + local_x, .y = job.min_z + local_z, .z = 0 };
}

fn heightAt(job: TerrainBatchJob, x: f32, z: f32) f32 {
    var h: f32 = 0;
    for (job.formations[0..job.formation_count], 0..) |formation, index| {
        switch (formation.kind) {
            .base => h += formation.height,
            .slope => {
                const coord = if (formation.axis == 'x') x else z;
                h += formation.height * smoothstep(formation.start, formation.end, coord);
            },
            .ridge => h += ridge(x, z, formation.x, formation.z, formation.radius, formation.height),
            .basin => h -= ridge(x, z, formation.x, formation.z, formation.radius, formation.height),
            .valley => h += cutValley(x, z, formation.x, formation.width, formation.height, formation.start, formation.end),
            .shelf => {
                const blend = 1 - smoothstep(0, formation.radius, @sqrt((x - formation.x) * (x - formation.x) + (z - formation.z) * (z - formation.z)));
                h = h * (1 - blend) + formation.height * blend;
            },
            .noise => h += valueNoise(job.seed + @as(u64, @intCast(index)) * 17, x, z, formation.scale) * formation.height,
        }
    }
    return std.math.clamp(h, 65, 930);
}

fn paintLayer(job: TerrainBatchJob, height: f32, x: f32, z: f32) usize {
    _ = job;
    const center_d = @sqrt(x * x + z * z);
    if (center_d < 850 and @abs(z - 165) < 18) return 5;
    if (center_d < 260) return 0;
    if (height > 700) return 3;
    if (height > 390) return 2;
    if (height < 150) return 1;
    return 0;
}

fn smoothstep(edge0: f32, edge1: f32, x: f32) f32 {
    const t = std.math.clamp((x - edge0) / (edge1 - edge0), 0, 1);
    return t * t * (3 - 2 * t);
}

fn ridge(x: f32, z: f32, cx: f32, cz: f32, radius: f32, height: f32) f32 {
    const dx = x - cx;
    const dz = z - cz;
    const d = @sqrt(dx * dx + dz * dz);
    const t = @max(0, 1 - d / radius);
    return height * t * t;
}

fn cutValley(x: f32, z: f32, cx: f32, width: f32, depth: f32, z_min: f32, z_max: f32) f32 {
    if (z < z_min or z > z_max) return 0;
    const dx = @abs(x - cx);
    return -depth * @exp(-(dx * dx) / (2 * width * width));
}

fn valueNoise(seed: u64, x: f32, z: f32, scale: f32) f32 {
    const fx = x / scale;
    const fz = z / scale;
    const ix: i32 = @intFromFloat(@floor(fx));
    const iz: i32 = @intFromFloat(@floor(fz));
    const tx = fx - @as(f32, @floatFromInt(ix));
    const tz = fz - @as(f32, @floatFromInt(iz));
    const sx = tx * tx * (3 - 2 * tx);
    const sz = tz * tz * (3 - 2 * tz);
    const a = hash2(seed, ix, iz);
    const b = hash2(seed, ix + 1, iz);
    const c = hash2(seed, ix, iz + 1);
    const d = hash2(seed, ix + 1, iz + 1);
    const ab = a + (b - a) * sx;
    const cd = c + (d - c) * sx;
    return (ab + (cd - ab) * sz) * 2 - 1;
}

fn hash2(seed: u64, x: i32, z: i32) f32 {
    var h = seed ^ @as(u64, @bitCast(@as(i64, x) *% 374761393)) ^ @as(u64, @bitCast(@as(i64, z) *% 668265263));
    h ^= h >> 30;
    h *%= 0xbf58476d1ce4e5b9;
    h ^= h >> 27;
    h *%= 0x94d049bb133111eb;
    h ^= h >> 31;
    return @as(f32, @floatFromInt(h & 0xffffff)) / @as(f32, @floatFromInt(0xffffff));
}

fn quantizeHeight(value: f32) f32 {
    return @round(value * 10) / 10;
}
