const std = @import("std");
const friendly_engine = @import("friendly_engine");

const project_editor_state = @import("project_editor_state.zig");
const project_editor_terrain_preview = @import("project_editor_terrain_preview.zig");
const project_editor_terrain_undo_store = @import("project_editor_terrain_undo_store.zig");
const terrain_manifest = @import("project_editor_world_authoring_manifest.zig");
const project_editor_types = @import("project_editor_types.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const TerrainStretchSmoothJob = project_editor_types.TerrainStretchSmoothJob;
const modules = friendly_engine.modules;
const world = friendly_engine.world;
const terrain_chunk_store = modules.terrain.chunk_store;

pub const StartOptions = struct {
    threshold_m: f32 = 180,
    strength: f32 = 0.35,
    iterations: u32 = 1,
    max_samples_per_cell: u32 = 12,
    min_height: f32 = -std.math.inf(f32),
    max_height: f32 = std.math.inf(f32),
};

const TileChange = struct {
    samples: usize = 0,
    max_delta: f32 = 0,
    total_delta: f32 = 0,
};

const Candidate = struct {
    index: usize,
    delta: f32,
};

pub fn start(state: *ProjectEditorState, options: StartOptions) !void {
    if (!std.math.isFinite(options.threshold_m) or options.threshold_m <= 0) return error.InvalidTerrainSmoothThreshold;
    if (!std.math.isFinite(options.strength) or options.strength <= 0 or options.strength > 1) return error.InvalidTerrainSmoothStrength;
    if (options.iterations == 0 or options.iterations > 16) return error.InvalidTerrainSmoothIterations;
    if (options.max_samples_per_cell == 0) return error.InvalidTerrainSmoothSampleCap;
    if (!std.math.isFinite(options.min_height) and options.min_height != -std.math.inf(f32)) return error.InvalidTerrainSmoothHeightRange;
    if (!std.math.isFinite(options.max_height) and options.max_height != std.math.inf(f32)) return error.InvalidTerrainSmoothHeightRange;
    if (options.min_height > options.max_height) return error.InvalidTerrainSmoothHeightRange;

    const manifest_path = try terrain_manifest.pathForState(state);
    var world_manifest = try world.manifest.loadManifest(state.allocator, state.io, state.project_path, manifest_path);
    defer world_manifest.deinit();
    if (world_manifest.cells.len == 0) return error.InvalidWorldManifest;

    const bounds = manifestCellBounds(world_manifest);
    const width: u64 = @intCast(bounds.max_x - bounds.min_x + 1);
    const depth: u64 = @intCast(bounds.max_z - bounds.min_z + 1);
    var job = TerrainStretchSmoothJob{
        .id = @as(u64, @bitCast(@as(i64, @intFromFloat(options.threshold_m * 1000)))) ^ (@as(u64, @intCast(options.iterations)) << 48) ^ @as(u64, @intCast(options.max_samples_per_cell)),
        .started_ns = nowNs(state),
        .min_x = bounds.min_x,
        .max_x = bounds.max_x,
        .min_z = bounds.min_z,
        .max_z = bounds.max_z,
        .cell_size_m = world_manifest.cell_size_m,
        .threshold_m = options.threshold_m,
        .strength = options.strength,
        .iterations = options.iterations,
        .max_samples_per_cell = options.max_samples_per_cell,
        .min_height = options.min_height,
        .max_height = options.max_height,
        .undo_transaction_id = nowNs(state),
        .total = width * depth,
        .active = true,
    };
    job.setStatus("Terrain stretch smoothing queued");
    state.terrain_stretch_smooth_job = job;
    state.mode = .world_creation;
    state.world_tool = .terrain;
    state.selected_world_layer = .terrain_base_height;
    project_editor_state.setStatus(state, "Terrain stretch smoothing queued");
}

pub fn cancel(state: *ProjectEditorState) void {
    if (state.terrain_stretch_smooth_job) |*job| {
        job.active = false;
        job.cancelled = true;
        job.setStatus("Terrain stretch smoothing cancelled");
        project_editor_state.setStatus(state, "Terrain stretch smoothing cancelled");
    }
}

pub fn tick(state: *ProjectEditorState) !void {
    var job = &(state.terrain_stretch_smooth_job orelse return);
    if (!job.active or job.complete or job.cancelled or job.failed) return;
    if (job.next_offset >= job.total) {
        if (try finishPassOrContinue(state, job)) return;
        return;
    }

    const tick_start_ns = nowNs(state);
    var processed_this_tick: u32 = 0;
    while (job.next_offset < job.total) {
        const id = cellAtOffset(job.*, job.next_offset);
        job.next_offset += 1;
        processCell(state, job, id) catch |err| {
            fail(state, job, err);
            return err;
        };
        processed_this_tick += 1;
        if (durationNs(tick_start_ns, nowNs(state)) >= job.tick_budget_ns) break;
    }

    job.last_tick_cells = processed_this_tick;
    job.last_tick_ns = durationNs(tick_start_ns, nowNs(state));
    if (job.next_offset >= job.total) {
        if (try finishPassOrContinue(state, job)) return;
        return;
    }

    var status_buf: [160]u8 = undefined;
    const status = std.fmt.bufPrint(&status_buf, "Terrain stretch smoothing pass {d}/{d}: {d}/{d} cells, {d} samples", .{ job.current_pass, job.iterations, job.next_offset, job.total, job.pass_changed_samples }) catch "Terrain stretch smoothing progress";
    job.setStatus(status);
    project_editor_state.setStatus(state, status);
}

fn finishPassOrContinue(state: *ProjectEditorState, job: *TerrainStretchSmoothJob) !bool {
    if (job.pass_changed_samples == 0 or job.current_pass >= job.iterations) {
        finish(state, job);
        return true;
    }
    job.current_pass += 1;
    job.next_offset = 0;
    job.pass_changed_cells = 0;
    job.pass_changed_samples = 0;
    var status_buf: [160]u8 = undefined;
    const status = std.fmt.bufPrint(&status_buf, "Terrain stretch smoothing pass {d}/{d} queued", .{ job.current_pass, job.iterations }) catch "Terrain stretch smoothing next pass";
    job.setStatus(status);
    project_editor_state.setStatus(state, status);
    return false;
}

fn finish(state: *ProjectEditorState, job: *TerrainStretchSmoothJob) void {
    job.active = false;
    job.complete = true;
    _ = project_editor_terrain_undo_store.pruneAfterTransaction(state.allocator, state.io, state.project_path, state.terrain_undo_limit_mb) catch {};
    job.setStatus("Terrain stretch smoothing complete");
    state.terrain_preview_stale = true;
    project_editor_terrain_preview.scheduleBake(state);
    project_editor_state.setStatus(state, "Terrain stretch smoothing complete");
}

fn fail(state: *ProjectEditorState, job: *TerrainStretchSmoothJob, err: anyerror) void {
    job.active = false;
    job.failed = true;
    var buf: [160]u8 = undefined;
    const message = std.fmt.bufPrint(&buf, "Terrain stretch smoothing failed: {s}", .{@errorName(err)}) catch "Terrain stretch smoothing failed";
    job.setStatus(message);
    project_editor_state.setStatus(state, message);
}

fn processCell(state: *ProjectEditorState, job: *TerrainStretchSmoothJob, id: world.cell.CellId) !void {
    const region_path = try terrain_chunk_store.regionPath(state.allocator, id);
    defer state.allocator.free(region_path);
    const maybe_doc = try terrain_chunk_store.loadTile(state.allocator, state.io, state.project_path, region_path, id);
    if (maybe_doc == null) return;
    var doc = maybe_doc.?;
    defer doc.deinit();
    if (doc.tiles.items.len != 1) return error.InvalidTerrainDocument;
    var tile = &doc.tiles.items[0];
    if (!tile.id().eql(id)) return error.InvalidTerrainDocument;

    job.processed_cells += 1;
    const changed = try smoothTile(state.allocator, tile, job.*);
    if (changed.samples == 0) return;

    const tx = project_editor_terrain_undo_store.beginTransaction(job.undo_transaction_id);
    if (try project_editor_terrain_undo_store.snapshotFileOnce(state.allocator, state.io, state.project_path, tx, region_path)) {
        job.undo_snapshots += 1;
    }
    const path = try terrain_chunk_store.upsertTile(state.allocator, state.io, state.project_path, .{
        .cell = tile.id(),
        .size = tile.size,
        .lod_levels = tile.lod_levels,
        .heights = tile.heights,
        .splat_size = tile.splat_size,
        .splat = tile.splat,
        .paint_layers = tile.paint_layers,
        .paint_colors = tile.paint_colors,
        .paint_albedo_textures = tile.paint_albedo_textures,
        .paint_roughness_textures = tile.paint_roughness_textures,
        .paint_specular_textures = tile.paint_specular_textures,
        .paint_displacement_textures = tile.paint_displacement_textures,
        .material = tile.material,
    });
    defer state.allocator.free(path);

    project_editor_state.markDirtyCell(state, "Terrain", id, "stretch smooth") catch |err| switch (err) {
        error.TooManyDirtyCells => job.dirty_overflow = true,
        else => return err,
    };
    job.changed_cells += 1;
    job.changed_samples += changed.samples;
    job.pass_changed_cells += 1;
    job.pass_changed_samples += changed.samples;
    job.max_delta = @max(job.max_delta, changed.max_delta);
    job.total_delta += changed.total_delta;
}

fn smoothTile(
    allocator: std.mem.Allocator,
    tile: *modules.terrain.authoring.OwnedTerrainTile,
    job: TerrainStretchSmoothJob,
) !TileChange {
    const sample_count = @as(usize, tile.size) * @as(usize, tile.size);
    if (sample_count == 0) return .{};

    var candidates = try allocator.alloc(Candidate, sample_count);
    defer allocator.free(candidates);
    const scratch = try allocator.alloc(f32, sample_count);
    defer allocator.free(scratch);

    @memcpy(scratch, tile.heights);
    var candidate_count: usize = 0;
    var z: u32 = 0;
    while (z < tile.size) : (z += 1) {
        var x: u32 = 0;
        while (x < tile.size) : (x += 1) {
            const index = @as(usize, z) * @as(usize, tile.size) + @as(usize, x);
            const h = scratch[index];
            if (h < job.min_height or h > job.max_height) continue;
            const delta = worstNeighborDelta(scratch, tile.size, x, z);
            if (delta < job.threshold_m) continue;
            candidates[candidate_count] = .{ .index = index, .delta = delta };
            candidate_count += 1;
        }
    }
    if (candidate_count == 0) return .{};
    std.mem.sort(Candidate, candidates[0..candidate_count], {}, compareCandidateDesc);

    var total_change = TileChange{};
    const limit = @min(candidate_count, @as(usize, @intCast(job.max_samples_per_cell)));
    var i: usize = 0;
    while (i < limit) : (i += 1) {
        const index = candidates[i].index;
        const x: u32 = @intCast(index % @as(usize, tile.size));
        const sample_z: u32 = @intCast(index / @as(usize, tile.size));
        const avg = neighborAverage(scratch, tile.size, x, sample_z);
        const old = scratch[index];
        const next = old + (avg - old) * job.strength;
        if (@abs(next - old) < 0.001) continue;
        tile.heights[index] = next;
        total_change.samples += 1;
        total_change.max_delta = @max(total_change.max_delta, candidates[i].delta);
        total_change.total_delta += @abs(next - old);
    }
    return total_change;
}

fn worstNeighborDelta(heights: []const f32, size: u32, x: u32, z: u32) f32 {
    const index = @as(usize, z) * @as(usize, size) + @as(usize, x);
    const h = heights[index];
    var worst: f32 = 0;
    if (x > 0) worst = @max(worst, @abs(h - heights[index - 1]));
    if (x + 1 < size) worst = @max(worst, @abs(h - heights[index + 1]));
    if (z > 0) worst = @max(worst, @abs(h - heights[index - @as(usize, size)]));
    if (z + 1 < size) worst = @max(worst, @abs(h - heights[index + @as(usize, size)]));
    return worst;
}

fn neighborAverage(heights: []const f32, size: u32, x: u32, z: u32) f32 {
    const index = @as(usize, z) * @as(usize, size) + @as(usize, x);
    var total: f32 = 0;
    var count: f32 = 0;
    if (x > 0) {
        total += heights[index - 1];
        count += 1;
    }
    if (x + 1 < size) {
        total += heights[index + 1];
        count += 1;
    }
    if (z > 0) {
        total += heights[index - @as(usize, size)];
        count += 1;
    }
    if (z + 1 < size) {
        total += heights[index + @as(usize, size)];
        count += 1;
    }
    return if (count > 0) total / count else heights[index];
}

fn compareCandidateDesc(_: void, a: Candidate, b: Candidate) bool {
    return a.delta > b.delta;
}

const ManifestCellBounds = struct {
    min_x: i32,
    max_x: i32,
    min_z: i32,
    max_z: i32,
};

fn manifestCellBounds(manifest: world.manifest.OwnedWorldManifest) ManifestCellBounds {
    var min_x: i32 = manifest.cells[0].id.x;
    var max_x: i32 = manifest.cells[0].id.x;
    var min_z: i32 = manifest.cells[0].id.y;
    var max_z: i32 = manifest.cells[0].id.y;
    for (manifest.cells[1..]) |entry| {
        min_x = @min(min_x, entry.id.x);
        max_x = @max(max_x, entry.id.x);
        min_z = @min(min_z, entry.id.y);
        max_z = @max(max_z, entry.id.y);
    }
    return .{ .min_x = min_x, .max_x = max_x, .min_z = min_z, .max_z = max_z };
}

fn cellAtOffset(job: TerrainStretchSmoothJob, offset: u64) world.cell.CellId {
    const width: u64 = @intCast(job.max_x - job.min_x + 1);
    const dx: i32 = @intCast(offset % width);
    const dz: i32 = @intCast(offset / width);
    return .{ .x = job.min_x + dx, .y = job.min_z + dz, .z = 0 };
}

fn nowNs(state: *ProjectEditorState) u64 {
    const ns = std.Io.Clock.awake.now(state.io).nanoseconds;
    if (ns <= 0) return 0;
    return @intCast(ns);
}

fn durationNs(start_ns: u64, end_ns: u64) u64 {
    if (end_ns <= start_ns) return 0;
    return end_ns - start_ns;
}
