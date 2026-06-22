const std = @import("std");
const friendly_engine = @import("friendly_engine");

const project_editor_state = @import("project_editor_state.zig");
const project_editor_terrain_preview = @import("project_editor_terrain_preview.zig");
const project_editor_terrain_undo_store = @import("project_editor_terrain_undo_store.zig");
const terrain_manifest = @import("project_editor_world_authoring_manifest.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const modules = friendly_engine.modules;
const world = friendly_engine.world;
const TerrainEdgeCliffJob = @import("project_editor_types.zig").TerrainEdgeCliffJob;

const terrain_chunk_store = modules.terrain.chunk_store;

pub const EdgeCliffResult = struct {
    cells: usize,
    samples: usize,
    min_height: f32,
    max_drop: f32,
    dirty_overflow: bool,
};

pub fn start(state: *ProjectEditorState, bottom_height: f32, width_m: f32) !void {
    if (!std.math.isFinite(bottom_height)) return error.InvalidTerrainEdgeCliffHeight;
    if (!std.math.isFinite(width_m) or width_m <= 0) return error.InvalidTerrainEdgeCliffWidth;

    const manifest_path = try terrain_manifest.pathForState(state);
    var world_manifest = try world.manifest.loadManifest(state.allocator, state.io, state.project_path, manifest_path);
    defer world_manifest.deinit();
    if (world_manifest.cells.len == 0) return error.InvalidWorldManifest;

    const cell_bounds = manifestCellBounds(world_manifest);
    const width_cells: u64 = @intCast(cell_bounds.max_x - cell_bounds.min_x + 1);
    const depth_cells: u64 = @intCast(cell_bounds.max_z - cell_bounds.min_z + 1);
    var job = TerrainEdgeCliffJob{
        .id = @as(u64, @bitCast(@as(i64, bottomHeightBits(bottom_height)))) ^ (@as(u64, @intCast(width_cells)) << 32) ^ @as(u64, @intCast(depth_cells)),
        .started_ns = nowNs(state),
        .min_x = cell_bounds.min_x,
        .max_x = cell_bounds.max_x,
        .min_z = cell_bounds.min_z,
        .max_z = cell_bounds.max_z,
        .cell_size_m = world_manifest.cell_size_m,
        .bottom_height = bottom_height,
        .width_m = width_m,
        .undo_transaction_id = nowNs(state),
        .total = width_cells * depth_cells,
        .active = true,
    };
    job.setStatus("Terrain edge cliff queued");
    state.terrain_edge_cliff_job = job;
    state.mode = .world_creation;
    state.world_tool = .terrain;
    state.selected_world_layer = .terrain_base_height;
    project_editor_state.setStatus(state, "Terrain edge cliff queued");
}

pub fn cancel(state: *ProjectEditorState) void {
    if (state.terrain_edge_cliff_job) |*job| {
        job.active = false;
        job.cancelled = true;
        job.setStatus("Terrain edge cliff cancelled");
        project_editor_state.setStatus(state, "Terrain edge cliff cancelled");
    }
}

pub fn tick(state: *ProjectEditorState) !void {
    var job = &(state.terrain_edge_cliff_job orelse return);
    if (!job.active or job.complete or job.cancelled or job.failed) return;
    if (job.next_offset >= job.total) {
        job.active = false;
        job.complete = true;
        _ = project_editor_terrain_undo_store.pruneAfterTransaction(state.allocator, state.io, state.project_path, state.terrain_undo_limit_mb) catch {};
        job.setStatus("Terrain edge cliff complete");
        state.terrain_preview_stale = true;
        project_editor_terrain_preview.scheduleBake(state);
        project_editor_state.setStatus(state, "Terrain edge cliff complete");
        return;
    }

    const tick_start_ns = nowNs(state);
    var processed_this_tick: u32 = 0;
    while (job.next_offset < job.total) {
        const id = cellAtOffset(job.*, job.next_offset);
        job.next_offset += 1;
        if (!cellInRim(id, job.*)) continue;

        processCell(state, job, id) catch |err| {
            job.active = false;
            job.failed = true;
            var fail_buf: [160]u8 = undefined;
            const message = std.fmt.bufPrint(&fail_buf, "Terrain edge cliff failed: {s}", .{@errorName(err)}) catch "Terrain edge cliff failed";
            job.setStatus(message);
            project_editor_state.setStatus(state, message);
            return err;
        };
        processed_this_tick += 1;
        if (durationNs(tick_start_ns, nowNs(state)) >= job.tick_budget_ns) break;
    }

    job.last_tick_cells = processed_this_tick;
    job.last_tick_ns = durationNs(tick_start_ns, nowNs(state));
    if (job.next_offset >= job.total) {
        job.active = false;
        job.complete = true;
        _ = project_editor_terrain_undo_store.pruneAfterTransaction(state.allocator, state.io, state.project_path, state.terrain_undo_limit_mb) catch {};
        state.terrain_preview_stale = true;
        project_editor_terrain_preview.scheduleBake(state);
    }

    var status_buf: [160]u8 = undefined;
    const status = std.fmt.bufPrint(&status_buf, "Terrain edge cliff {d}/{d} cells, {d} changed", .{ job.next_offset, job.total, job.changed_cells }) catch "Terrain edge cliff progress";
    job.setStatus(status);
    project_editor_state.setStatus(state, status);
}

const WorldBounds = struct {
    min_x: f32,
    max_x: f32,
    min_z: f32,
    max_z: f32,
};

pub fn sculptEdgeCliff(state: *ProjectEditorState, bottom_height: f32, width_m: f32) !EdgeCliffResult {
    if (!std.math.isFinite(bottom_height)) return error.InvalidTerrainEdgeCliffHeight;
    if (!std.math.isFinite(width_m) or width_m <= 0) return error.InvalidTerrainEdgeCliffWidth;

    const manifest_path = try terrain_manifest.pathForState(state);
    var world_manifest = try world.manifest.loadManifest(state.allocator, state.io, state.project_path, manifest_path);
    defer world_manifest.deinit();
    if (world_manifest.cells.len == 0) return error.InvalidWorldManifest;

    var terrain_index = try modules.terrain.authoring.loadIndex(state.allocator, state.io, state.project_path, manifest_path);
    defer terrain_index.deinit();
    if (terrain_index.entries.items.len == 0) return error.TerrainTileNotFound;

    const bounds = manifestBounds(world_manifest);
    var changed_cells: usize = 0;
    var changed_samples: usize = 0;
    var min_height = std.math.inf(f32);
    var max_drop: f32 = 0;
    var dirty_overflow = false;

    for (terrain_index.entries.items) |entry| {
        const cell_bounds = world.cell.boundsForCell(entry.cell, world_manifest.cell_size_m, world.cell.default_cell_height_m);
        if (!cellIntersectsRim(cell_bounds, bounds, width_m)) continue;

        const maybe_doc = try modules.terrain.authoring.loadCell(state.allocator, state.io, state.project_path, manifest_path, entry.cell);
        if (maybe_doc == null) return error.TerrainTileNotFound;
        var doc = maybe_doc.?;
        defer doc.deinit();
        if (doc.tiles.items.len != 1) return error.InvalidTerrainDocument;
        var tile = &doc.tiles.items[0];
        if (!tile.id().eql(entry.cell)) return error.InvalidTerrainDocument;

        const changed = applyCliffToTile(tile, entry.cell, world_manifest.cell_size_m, bounds, bottom_height, width_m);
        if (changed.samples == 0) continue;

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
        try terrain_index.upsert(entry.cell, path);
        project_editor_state.markDirtyCell(state, "Terrain", entry.cell, "edge cliff") catch |err| switch (err) {
            error.TooManyDirtyCells => dirty_overflow = true,
            else => return err,
        };

        changed_cells += 1;
        changed_samples += changed.samples;
        min_height = @min(min_height, changed.min_height);
        max_drop = @max(max_drop, changed.max_drop);
    }

    try modules.terrain.authoring.saveIndex(state.allocator, state.io, state.project_path, manifest_path, terrain_index);
    state.terrain_preview_stale = true;
    project_editor_terrain_preview.scheduleBake(state);

    if (!std.math.isFinite(min_height)) min_height = bottom_height;
    return .{
        .cells = changed_cells,
        .samples = changed_samples,
        .min_height = min_height,
        .max_drop = max_drop,
        .dirty_overflow = dirty_overflow,
    };
}

fn manifestBounds(manifest: world.manifest.OwnedWorldManifest) WorldBounds {
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
    const cell_size = manifest.cell_size_m;
    return .{
        .min_x = @as(f32, @floatFromInt(min_x)) * cell_size,
        .max_x = @as(f32, @floatFromInt(max_x + 1)) * cell_size,
        .min_z = @as(f32, @floatFromInt(min_z)) * cell_size,
        .max_z = @as(f32, @floatFromInt(max_z + 1)) * cell_size,
    };
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

fn cellAtOffset(job: TerrainEdgeCliffJob, offset: u64) world.cell.CellId {
    const width: u64 = @intCast(job.max_x - job.min_x + 1);
    const dx: i32 = @intCast(offset % width);
    const dz: i32 = @intCast(offset / width);
    return .{ .x = job.min_x + dx, .y = job.min_z + dz, .z = 0 };
}

fn cellInRim(id: world.cell.CellId, job: TerrainEdgeCliffJob) bool {
    const bounds = jobWorldBounds(job);
    const cell_bounds = world.cell.boundsForCell(id, job.cell_size_m, world.cell.default_cell_height_m);
    return cellIntersectsRim(cell_bounds, bounds, job.width_m);
}

fn processCell(state: *ProjectEditorState, job: *TerrainEdgeCliffJob, id: world.cell.CellId) !void {
    const region_path = try terrain_chunk_store.regionPath(state.allocator, id);
    defer state.allocator.free(region_path);
    const maybe_doc = try terrain_chunk_store.loadTile(state.allocator, state.io, state.project_path, region_path, id);
    if (maybe_doc == null) return error.TerrainTileNotFound;
    var doc = maybe_doc.?;
    defer doc.deinit();
    if (doc.tiles.items.len != 1) return error.InvalidTerrainDocument;
    var tile = &doc.tiles.items[0];
    if (!tile.id().eql(id)) return error.InvalidTerrainDocument;

    const changed = applyCliffToTile(tile, id, job.cell_size_m, jobWorldBounds(job.*), job.bottom_height, job.width_m);
    job.processed_cells += 1;
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

    project_editor_state.markDirtyCell(state, "Terrain", id, "edge cliff") catch |err| switch (err) {
        error.TooManyDirtyCells => job.dirty_overflow = true,
        else => return err,
    };
    job.changed_cells += 1;
    job.changed_samples += changed.samples;
    job.min_height = @min(job.min_height, changed.min_height);
    job.max_drop = @max(job.max_drop, changed.max_drop);
}

fn jobWorldBounds(job: TerrainEdgeCliffJob) WorldBounds {
    return .{
        .min_x = @as(f32, @floatFromInt(job.min_x)) * job.cell_size_m,
        .max_x = @as(f32, @floatFromInt(job.max_x + 1)) * job.cell_size_m,
        .min_z = @as(f32, @floatFromInt(job.min_z)) * job.cell_size_m,
        .max_z = @as(f32, @floatFromInt(job.max_z + 1)) * job.cell_size_m,
    };
}

fn bottomHeightBits(value: f32) i32 {
    return @bitCast(value);
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

fn cellIntersectsRim(cell_bounds: world.cell.CellBounds, bounds: WorldBounds, width_m: f32) bool {
    return cell_bounds.min.x <= bounds.min_x + width_m or
        cell_bounds.max.x >= bounds.max_x - width_m or
        cell_bounds.min.z <= bounds.min_z + width_m or
        cell_bounds.max.z >= bounds.max_z - width_m;
}

const TileChange = struct {
    samples: usize = 0,
    min_height: f32 = std.math.inf(f32),
    max_drop: f32 = 0,
};

fn applyCliffToTile(
    tile: *modules.terrain.authoring.OwnedTerrainTile,
    id: world.cell.CellId,
    cell_size_m: f32,
    bounds: WorldBounds,
    bottom_height: f32,
    width_m: f32,
) TileChange {
    const size = tile.size;
    const step = cell_size_m / @as(f32, @floatFromInt(size - 1));
    const cell_min_x = @as(f32, @floatFromInt(id.x)) * cell_size_m;
    const cell_min_z = @as(f32, @floatFromInt(id.y)) * cell_size_m;
    var change = TileChange{};

    var z: u32 = 0;
    while (z < size) : (z += 1) {
        var x: u32 = 0;
        while (x < size) : (x += 1) {
            const world_x = cell_min_x + @as(f32, @floatFromInt(x)) * step;
            const world_z = cell_min_z + @as(f32, @floatFromInt(z)) * step;
            const edge_distance = nearestEdgeDistance(world_x, world_z, bounds);
            if (edge_distance >= width_m) continue;

            const index = @as(usize, z) * @as(usize, size) + @as(usize, x);
            const old_height = tile.heights[index];
            const blend = smoothstep(std.math.clamp(edge_distance / width_m, 0, 1));
            const new_height = bottom_height + (old_height - bottom_height) * blend;
            if (new_height >= old_height) continue;

            tile.heights[index] = new_height;
            change.samples += 1;
            change.min_height = @min(change.min_height, new_height);
            change.max_drop = @max(change.max_drop, old_height - new_height);
        }
    }
    return change;
}

fn nearestEdgeDistance(x: f32, z: f32, bounds: WorldBounds) f32 {
    return @min(
        @min(x - bounds.min_x, bounds.max_x - x),
        @min(z - bounds.min_z, bounds.max_z - z),
    );
}

fn smoothstep(t: f32) f32 {
    return t * t * (3 - 2 * t);
}
