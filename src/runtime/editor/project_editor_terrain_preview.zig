const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const editor_math = shared.editor_math;
const geometry = shared.geometry;
const shared_color = shared.color;
const gpu_scene = shared.gpu_scene;
const project_editor_state = @import("project_editor_state.zig");
const project_editor_viewport = @import("project_editor_viewport.zig");
const project_editor_world_authoring_manifest = @import("project_editor_world_authoring_manifest.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const modules = friendly_engine.modules;
const world = friendly_engine.world;
const mesh_builder = modules.terrain.mesh_builder;
const splat_texture = modules.terrain.splat_texture;
const lod_pick = modules.terrain.lod_pick;
const terrain_residency = modules.terrain.residency;
const terrain_chunk_store = modules.terrain.chunk_store;

pub const terrain_bake_debounce_s: f32 = 0.75;
pub const clipmap_min_radius_cells: i32 = 2;
pub const clipmap_max_radius_cells: i32 = 64;
pub const max_cells_loaded_per_refresh: usize = 32;
pub const max_resident_cells: usize = 4096;
const batch_draw_radius_cells: f32 = 2;
const batch_max_cells_loaded_per_refresh: usize = 4;
const batch_max_resident_cells: usize = 25;
const far_batch_texture_size: usize = splat_texture.TextureSize;
const max_editor_grass_preview_instances: usize = 1_500;
const lod_transition_duration_s: f32 = 0.22;

pub const TileSnapshot = struct {
    cell: world.cell.CellId,
    bounds: world.cell.CellBounds,
    size: u32,
    lod_levels: []u32,
    heights: []f32,
    west_heights: ?[]f32,
    east_heights: ?[]f32,
    south_heights: ?[]f32,
    north_heights: ?[]f32,
    splat_size: u32,
    splat: []u8,
    paint_layers: [][]u8,
    paint_colors: [][4]u8,
    paint_albedo_textures: [][]u8,
    paint_roughness_textures: [][]u8,
    paint_specular_textures: [][]u8,
    paint_displacement_textures: [][]u8,
    material: []u8,

    pub fn deinit(self: *TileSnapshot, allocator: std.mem.Allocator) void {
        allocator.free(self.lod_levels);
        allocator.free(self.heights);
        if (self.west_heights) |value| allocator.free(value);
        if (self.east_heights) |value| allocator.free(value);
        if (self.south_heights) |value| allocator.free(value);
        if (self.north_heights) |value| allocator.free(value);
        allocator.free(self.splat);
        freePaintLayers(allocator, self.paint_layers);
        allocator.free(self.paint_colors);
        freePaintLayers(allocator, self.paint_albedo_textures);
        freePaintLayers(allocator, self.paint_roughness_textures);
        freePaintLayers(allocator, self.paint_specular_textures);
        freePaintLayers(allocator, self.paint_displacement_textures);
        allocator.free(self.material);
        self.* = .{
            .cell = .{ .x = 0, .y = 0, .z = 0 },
            .bounds = undefined,
            .size = 0,
            .lod_levels = &.{},
            .heights = &.{},
            .west_heights = null,
            .east_heights = null,
            .south_heights = null,
            .north_heights = null,
            .splat_size = 0,
            .splat = &.{},
            .paint_layers = &.{},
            .paint_colors = &.{},
            .paint_albedo_textures = &.{},
            .paint_roughness_textures = &.{},
            .paint_specular_textures = &.{},
            .paint_displacement_textures = &.{},
            .material = &.{},
        };
    }
};

pub const GrassPreview = struct {
    instances: []shared.render_commands.GrassInstance,
    meta: modules.grass.types.ClusterMetadata,
    center: friendly_engine.core.math.Vec3f,

    pub fn deinit(self: *GrassPreview, allocator: std.mem.Allocator) void {
        allocator.free(self.instances);
        self.* = undefined;
    }
};

pub const LodTransition = struct {
    mesh: geometry.Mesh,
    texture: []u8,
    base_color: shared_color.Color,
    lod_index: usize,
    progress_s: f32 = 0,

    pub fn deinit(self: *LodTransition, allocator: std.mem.Allocator) void {
        self.mesh.deinit(allocator);
        allocator.free(self.texture);
        self.* = undefined;
    }
};

pub const Entry = struct {
    snapshot: TileSnapshot,
    lod_index: usize,
    mesh: geometry.Mesh,
    texture: []u8,
    base_color: shared_color.Color,
    grass_preview: ?GrassPreview = null,
    lod_transition: ?LodTransition = null,

    pub fn deinit(self: *Entry, allocator: std.mem.Allocator) void {
        if (self.lod_transition) |*transition| transition.deinit(allocator);
        if (self.grass_preview) |*grass| grass.deinit(allocator);
        self.snapshot.deinit(allocator);
        self.mesh.deinit(allocator);
        allocator.free(self.texture);
        self.* = undefined;
    }
};

pub const FarBatch = struct {
    mesh: geometry.Mesh,
    texture: []u8,
    base_color: shared_color.Color,

    pub fn deinit(self: *FarBatch, allocator: std.mem.Allocator) void {
        self.mesh.deinit(allocator);
        allocator.free(self.texture);
        self.* = undefined;
    }
};

pub const Cache = struct {
    entries: std.ArrayList(Entry) = .empty,
    far_batches: std.ArrayList(FarBatch) = .empty,
    far_batches_dirty: bool = true,
    neighbor_links_dirty: bool = true,
    post_process_active: bool = false,
    post_process_label: []const u8 = "",
    post_process_completed: usize = 0,
    post_process_total: usize = 0,
    post_process_deferred_after_cell_change: bool = false,
    last_desired_cells: usize = 0,
    last_pending_loads: usize = 0,
    last_loaded: usize = 0,
    last_unloaded: usize = 0,
    last_resident_after: usize = 0,

    pub fn deinit(self: *Cache, allocator: std.mem.Allocator) void {
        for (self.entries.items) |*entry| entry.deinit(allocator);
        self.entries.deinit(allocator);
        self.clearFarBatches(allocator);
        self.far_batches.deinit(allocator);
    }

    pub fn clear(self: *Cache, allocator: std.mem.Allocator) void {
        for (self.entries.items) |*entry| entry.deinit(allocator);
        self.entries.clearRetainingCapacity();
        self.clearFarBatches(allocator);
        self.far_batches_dirty = true;
        self.neighbor_links_dirty = true;
        self.clearPostProcess();
        self.last_desired_cells = 0;
        self.last_pending_loads = 0;
        self.last_loaded = 0;
        self.last_unloaded = 0;
        self.last_resident_after = 0;
    }

    fn clearFarBatches(self: *Cache, allocator: std.mem.Allocator) void {
        for (self.far_batches.items) |*batch| batch.deinit(allocator);
        self.far_batches.clearRetainingCapacity();
    }

    fn beginPostProcess(self: *Cache, label: []const u8, completed: usize, total: usize) void {
        self.post_process_active = true;
        self.post_process_label = label;
        self.post_process_completed = completed;
        self.post_process_total = total;
    }

    fn finishPostProcessStep(self: *Cache, label: []const u8, completed: usize, total: usize) void {
        self.post_process_active = completed < total;
        self.post_process_label = label;
        self.post_process_completed = completed;
        self.post_process_total = total;
    }

    fn clearPostProcess(self: *Cache) void {
        self.post_process_active = false;
        self.post_process_label = "";
        self.post_process_completed = 0;
        self.post_process_total = 0;
        self.post_process_deferred_after_cell_change = false;
    }
};

pub fn refreshIfStale(state: *ProjectEditorState) !void {
    if (!state.terrain_preview_stale) return;
    state.terrain_preview_stale = !try refresh(state);
}

pub fn maintainPreview(state: *ProjectEditorState) !void {
    if (!project_editor_state.worldContextVisible(state)) return;
    state.camera.far_clip_m = @max(state.camera.far_clip_m, state.world_draw_distance_m);
    markClipmapStaleIfNeeded(state);
    try refreshIfStale(state);
    keepCameraAboveTerrain(state);
    updateLoadingStats(state);
    if (state.terrain_preview.last_pending_loads > 0) return;
    if ((state.terrain_preview.last_loaded > 0 or state.terrain_preview.last_unloaded > 0) and !state.terrain_preview.post_process_deferred_after_cell_change) {
        state.terrain_preview.post_process_deferred_after_cell_change = true;
        return;
    }
    if (state.terrain_preview.post_process_active and state.terrain_preview.post_process_completed == 2) {
        try rebuildFarBatchesIfNeeded(state);
        state.terrain_preview.finishPostProcessStep("Terrain ready", 3, 3);
        state.terrain_preview.clearPostProcess();
        return;
    }
    if (state.terrain_preview.post_process_active and state.terrain_preview.post_process_completed == 1) {
        try syncLodMeshes(state);
        state.terrain_preview.finishPostProcessStep("Building far terrain batch", 2, 3);
        return;
    }
    if (state.terrain_preview.neighbor_links_dirty) {
        state.terrain_preview.beginPostProcess("Stitching terrain edges", 0, 3);
        try syncNeighborHeights(state);
        state.terrain_preview.neighbor_links_dirty = false;
        state.terrain_preview.finishPostProcessStep("Refreshing terrain LOD meshes", 1, 3);
        return;
    }
    if (!state.terrain_preview.far_batches_dirty) {
        try syncLodMeshes(state);
        try rebuildFarBatchesIfNeeded(state);
        return;
    }
    state.terrain_preview.beginPostProcess("Refreshing terrain LOD meshes", 1, 3);
}

fn updateLoadingStats(state: *ProjectEditorState) void {
    const pending = state.terrain_preview.last_pending_loads;
    const active = state.terrain_preview_stale or pending > 0;
    const now = friendly_engine.core.time.monotonicNs();
    if (!active) {
        state.terrain_loading_active = false;
        state.terrain_loading_elapsed_s = 0;
        state.terrain_loading_eta_s = 0;
        state.terrain_loading_rate_cells_per_s = 0;
        return;
    }
    if (!state.terrain_loading_active) {
        state.terrain_loading_active = true;
        state.terrain_loading_start_ns = now;
        state.terrain_loading_start_resident = state.terrain_preview.entries.items.len;
        state.terrain_loading_elapsed_s = 0;
        state.terrain_loading_eta_s = 0;
        state.terrain_loading_rate_cells_per_s = 0;
        return;
    }

    const elapsed_ns = now - state.terrain_loading_start_ns;
    const elapsed_s = if (elapsed_ns <= 0) 0 else @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, @floatFromInt(std.time.ns_per_s));
    state.terrain_loading_elapsed_s = elapsed_s;
    if (elapsed_s <= 0) return;

    const resident = state.terrain_preview.entries.items.len;
    const loaded = resident -| state.terrain_loading_start_resident;
    const rate = @as(f64, @floatFromInt(loaded)) / elapsed_s;
    state.terrain_loading_rate_cells_per_s = rate;
    state.terrain_loading_eta_s = if (rate > 0)
        @as(f64, @floatFromInt(pending)) / rate
    else
        0;
}

pub fn refresh(state: *ProjectEditorState) !bool {
    const world_cache = try state.ensureWorldCache();
    const world_manifest = world_cache.manifest;
    const terrain_index = world_cache.terrain_index;

    const camera_target = cameraTargetVec(state);
    const camera_eye = cameraEyeVec(state);

    var candidates = std.ArrayList(terrain_residency.Candidate).empty;
    defer candidates.deinit(state.allocator);
    const draw_distance_m = effectiveDrawDistance(state);
    for (terrain_index.entries.items) |entry| {
        const id = entry.cell;
        if (!world_manifest.hasCell(id)) continue;
        if (terrainBatchActive(state) and !cellInClipmap(id, camera_target, world_manifest.cell_size_m, draw_distance_m)) continue;

        const distance = lod_pick.distanceToCellFootprint(camera_eye, id, world_manifest.cell_size_m);
        try candidates.append(state.allocator, .{ .id = id, .distance_m = distance });
    }

    var residents = std.ArrayList(terrain_residency.Resident).empty;
    defer residents.deinit(state.allocator);
    for (state.terrain_preview.entries.items) |entry| {
        const distance = lod_pick.distanceToCellFootprint(camera_eye, entry.snapshot.cell, world_manifest.cell_size_m);
        try residents.append(state.allocator, .{ .id = entry.snapshot.cell, .distance_m = distance });
    }

    const budget = previewBudget(state, candidates.items.len);
    var plan = try terrain_residency.planUpdate(
        state.allocator,
        candidates.items,
        residents.items,
        .{ .max_loads = budget.max_loads, .max_resident = budget.max_resident },
    );
    defer plan.deinit();

    state.terrain_preview.last_desired_cells = plan.desired_count;
    state.terrain_preview.last_pending_loads = plan.pending_loads;
    state.terrain_preview.last_loaded = 0;
    state.terrain_preview.last_unloaded = 0;
    state.terrain_preview.last_resident_after = plan.resident_after;
    state.terrain_preview.post_process_deferred_after_cell_change = false;

    for (plan.evictions) |id| {
        if (removeLoadedCell(state, id)) {
            state.terrain_preview.last_unloaded += 1;
            state.terrain_preview.far_batches_dirty = true;
            state.terrain_preview.neighbor_links_dirty = true;
        }
    }

    const sorted_requests = try state.allocator.dupe(world.cell.CellId, plan.requests);
    defer state.allocator.free(sorted_requests);
    std.mem.sort(world.cell.CellId, sorted_requests, {}, compareCellRegion);

    var request_index: usize = 0;
    while (request_index < sorted_requests.len) {
        const region = terrain_chunk_store.regionIdForCell(sorted_requests[request_index]);
        var region_end = request_index + 1;
        while (region_end < sorted_requests.len and terrain_chunk_store.regionIdForCell(sorted_requests[region_end]).eql(region)) : (region_end += 1) {}

        const region_path = try terrain_chunk_store.regionPath(state.allocator, sorted_requests[request_index]);
        defer state.allocator.free(region_path);
        var region_doc = try terrain_chunk_store.loadRegionTiles(state.allocator, state.io, state.project_path, region_path, sorted_requests[request_index..region_end]);
        defer region_doc.deinit();

        for (sorted_requests[request_index..region_end]) |id| {
            const tile = findTile(region_doc, id) orelse return error.TerrainTileNotFound;
            var snapshot = try snapshotFromTile(state.allocator, id, world_manifest.cell_size_m, tile);
            errdefer snapshot.deinit(state.allocator);

            const distance = candidateDistance(candidates.items, id);
            const lod_index = editableTerrainLodIndex(distance, world_manifest.cell_size_m, snapshot.lod_levels.len);

            const grass_preview = loadGrassPreviewForCell(state, id) catch null;
            const entry = try buildEntry(state.allocator, snapshot, lod_index, grass_preview);
            try state.terrain_preview.entries.append(state.allocator, entry);
            state.terrain_preview.last_loaded += 1;
            state.terrain_preview.far_batches_dirty = true;
            state.terrain_preview.neighbor_links_dirty = true;
        }

        request_index = region_end;
    }
    state.terrain_preview.last_resident_after = state.terrain_preview.entries.items.len;
    return plan.pending_loads == 0;
}

fn dupePaintLayers(allocator: std.mem.Allocator, layers: []const []const u8) ![][]u8 {
    const owned = try allocator.alloc([]u8, layers.len);
    errdefer allocator.free(owned);
    var written: usize = 0;
    errdefer {
        for (owned[0..written]) |layer| allocator.free(layer);
    }
    for (layers, 0..) |layer, index| {
        owned[index] = try allocator.dupe(u8, layer);
        written += 1;
    }
    return owned;
}

fn freePaintLayers(allocator: std.mem.Allocator, layers: [][]u8) void {
    for (layers) |layer| allocator.free(layer);
    allocator.free(layers);
}

fn compareCellRegion(_: void, a: world.cell.CellId, b: world.cell.CellId) bool {
    const ar = terrain_chunk_store.regionIdForCell(a);
    const br = terrain_chunk_store.regionIdForCell(b);
    if (ar.x != br.x) return ar.x < br.x;
    if (ar.y != br.y) return ar.y < br.y;
    if (a.x != b.x) return a.x < b.x;
    return a.y < b.y;
}

fn findTile(doc: modules.terrain.authoring.TerrainAuthoringDoc, id: world.cell.CellId) ?*const modules.terrain.authoring.OwnedTerrainTile {
    for (doc.tiles.items) |*tile| {
        if (tile.id().eql(id)) return tile;
    }
    return null;
}

fn snapshotFromTile(
    allocator: std.mem.Allocator,
    id: world.cell.CellId,
    cell_size_m: f32,
    tile: *const modules.terrain.authoring.OwnedTerrainTile,
) !TileSnapshot {
    return .{
        .cell = id,
        .bounds = world.cell.boundsForCell(id, cell_size_m, world.cell.default_cell_height_m),
        .size = tile.size,
        .lod_levels = try allocator.dupe(u32, tile.lod_levels),
        .heights = try allocator.dupe(f32, tile.heights),
        .west_heights = null,
        .east_heights = null,
        .south_heights = null,
        .north_heights = null,
        .splat_size = tile.splat_size,
        .splat = try allocator.dupe(u8, tile.splat),
        .paint_layers = try dupePaintLayers(allocator, tile.paint_layers),
        .paint_colors = try allocator.dupe([4]u8, tile.paint_colors),
        .paint_albedo_textures = try dupePaintLayers(allocator, tile.paint_albedo_textures),
        .paint_roughness_textures = try dupePaintLayers(allocator, tile.paint_roughness_textures),
        .paint_specular_textures = try dupePaintLayers(allocator, tile.paint_specular_textures),
        .paint_displacement_textures = try dupePaintLayers(allocator, tile.paint_displacement_textures),
        .material = try allocator.dupe(u8, tile.material),
    };
}

fn removeLoadedCell(state: *ProjectEditorState, id: world.cell.CellId) bool {
    var index: usize = 0;
    while (index < state.terrain_preview.entries.items.len) : (index += 1) {
        if (!state.terrain_preview.entries.items[index].snapshot.cell.eql(id)) continue;
        var removed = state.terrain_preview.entries.orderedRemove(index);
        removed.deinit(state.allocator);
        return true;
    }
    return false;
}

fn candidateDistance(candidates: []const terrain_residency.Candidate, id: world.cell.CellId) f32 {
    for (candidates) |candidate| {
        if (candidate.id.eql(id)) return candidate.distance_m;
    }
    return std.math.inf(f32);
}

pub fn syncLodMeshes(state: *ProjectEditorState) !void {
    const camera_eye = cameraEyeVec(state);
    for (state.terrain_preview.entries.items) |*entry| {
        const distance = lod_pick.distanceToCellFootprint(camera_eye, entry.snapshot.cell, state.world_cell_size_m);
        const lod_index = editableTerrainLodIndex(distance, state.world_cell_size_m, entry.snapshot.lod_levels.len);
        if (lod_index == entry.lod_index) continue;
        try rebuildMeshInPlace(state.allocator, entry, lod_index);
        state.terrain_preview.far_batches_dirty = true;
    }
}

pub fn tickLodTransitions(state: *ProjectEditorState, dt: f32) void {
    const step = if (std.math.isFinite(dt) and dt > 0) dt else 0;
    for (state.terrain_preview.entries.items) |*entry| {
        const transition = &(entry.lod_transition orelse continue);
        transition.progress_s += step;
        if (transition.progress_s < lod_transition_duration_s) continue;
        transition.deinit(state.allocator);
        entry.lod_transition = null;
    }
}

fn syncNeighborHeights(state: *ProjectEditorState) !void {
    var height_lookup = std.AutoHashMap(world.cell.CellId, []const f32).init(state.allocator);
    defer height_lookup.deinit();
    try height_lookup.ensureTotalCapacity(@intCast(state.terrain_preview.entries.items.len));
    for (state.terrain_preview.entries.items) |*entry| {
        height_lookup.putAssumeCapacity(entry.snapshot.cell, entry.snapshot.heights);
    }

    var any_changed = false;
    for (state.terrain_preview.entries.items) |*entry| {
        var changed = false;
        const cell = entry.snapshot.cell;
        changed = try syncNeighborSlot(
            state.allocator,
            &entry.snapshot.west_heights,
            height_lookup.get(.{ .x = cell.x - 1, .y = cell.y, .z = cell.z }),
        ) or changed;
        changed = try syncNeighborSlot(
            state.allocator,
            &entry.snapshot.east_heights,
            height_lookup.get(.{ .x = cell.x + 1, .y = cell.y, .z = cell.z }),
        ) or changed;
        changed = try syncNeighborSlot(
            state.allocator,
            &entry.snapshot.south_heights,
            height_lookup.get(.{ .x = cell.x, .y = cell.y - 1, .z = cell.z }),
        ) or changed;
        changed = try syncNeighborSlot(
            state.allocator,
            &entry.snapshot.north_heights,
            height_lookup.get(.{ .x = cell.x, .y = cell.y + 1, .z = cell.z }),
        ) or changed;
        if (!changed) continue;
        try rebuildMeshInPlace(state.allocator, entry, entry.lod_index);
        any_changed = true;
    }
    if (any_changed) state.terrain_preview.far_batches_dirty = true;
}

fn syncNeighborSlot(allocator: std.mem.Allocator, slot: *?[]f32, source: ?[]const f32) !bool {
    if (source) |heights| {
        if (slot.*) |existing| {
            if (std.mem.eql(f32, existing, heights)) return false;
            allocator.free(existing);
        }
        slot.* = try allocator.dupe(f32, heights);
        return true;
    }
    if (slot.*) |existing| {
        allocator.free(existing);
        slot.* = null;
        return true;
    }
    return false;
}

pub fn sampleHeightAtPoint(state: *ProjectEditorState, point: editor_math.Vec3) !f32 {
    var world_manifest = try world.manifest.loadManifest(
        state.allocator,
        state.io,
        state.project_path,
        try project_editor_world_authoring_manifest.pathForState(state),
    );
    defer world_manifest.deinit();

    const id = project_editor_world_authoring_manifest.cellIdForPoint(world_manifest.cell_size_m, point);
    if (!world_manifest.hasCell(id)) return error.WorldCellNotInManifest;

    const maybe_doc = try loadChunkTile(state, id);
    if (maybe_doc == null) return error.TerrainTileNotFound;
    var doc = maybe_doc.?;
    defer doc.deinit();

    const bounds = world.cell.boundsForCell(id, world_manifest.cell_size_m, world.cell.default_cell_height_m);
    for (doc.tiles.items) |tile| {
        if (tile.cell[0] == id.x and tile.cell[1] == id.y and tile.cell[2] == id.z) {
            return sampleHeightInTile(bounds, tile.size, tile.heights, point);
        }
    }
    return error.TerrainTileNotFound;
}

pub fn sampleResidentHeightAtPoint(state: *const ProjectEditorState, point: editor_math.Vec3) ?f32 {
    return residentHeightAtPoint(state.terrain_preview.entries.items, point);
}

pub fn keepCameraAboveTerrain(state: *ProjectEditorState) void {
    _ = state;
}

fn residentHeightAtPoint(entries: []const Entry, point: editor_math.Vec3) ?f32 {
    for (entries) |*entry| {
        const bounds = entry.snapshot.bounds;
        if (point.x < bounds.min.x or point.x > bounds.max.x) continue;
        if (point.z < bounds.min.z or point.z > bounds.max.z) continue;
        if (entry.snapshot.size < 2 or entry.snapshot.heights.len == 0) return null;
        return sampleHeightInTile(bounds, entry.snapshot.size, entry.snapshot.heights, point);
    }
    return null;
}

fn loadChunkTile(state: *ProjectEditorState, id: world.cell.CellId) !?modules.terrain.authoring.TerrainAuthoringDoc {
    const region_path = try terrain_chunk_store.regionPath(state.allocator, id);
    defer state.allocator.free(region_path);
    return terrain_chunk_store.loadTile(state.allocator, state.io, state.project_path, region_path, id);
}

fn sampleHeightInTile(bounds: world.cell.CellBounds, size: u32, heights: []const f32, point: editor_math.Vec3) f32 {
    std.debug.assert(size >= 2);
    std.debug.assert(heights.len == @as(usize, size) * @as(usize, size));

    const grid: usize = @intCast(size);
    const u = std.math.clamp((point.x - bounds.min.x) / @max(0.001, bounds.max.x - bounds.min.x), 0.0, 1.0);
    const v = std.math.clamp((point.z - bounds.min.z) / @max(0.001, bounds.max.z - bounds.min.z), 0.0, 1.0);
    const sx = u * @as(f32, @floatFromInt(grid - 1));
    const sz = v * @as(f32, @floatFromInt(grid - 1));
    const x0: usize = @intFromFloat(@floor(sx));
    const z0: usize = @intFromFloat(@floor(sz));
    const x1 = @min(grid - 1, x0 + 1);
    const z1 = @min(grid - 1, z0 + 1);
    const tx = sx - @as(f32, @floatFromInt(x0));
    const tz = sz - @as(f32, @floatFromInt(z0));

    const h00 = heights[z0 * grid + x0];
    const h10 = heights[z0 * grid + x1];
    const h01 = heights[z1 * grid + x0];
    const h11 = heights[z1 * grid + x1];
    const hx0 = h00 + (h10 - h00) * tx;
    const hx1 = h01 + (h11 - h01) * tx;
    return hx0 + (hx1 - hx0) * tz;
}

pub fn appendGpuObjects(
    state: *ProjectEditorState,
    gpu_objects: *std.ArrayList(gpu_scene.SceneGpuObject),
) !void {
    if (!project_editor_state.worldContextVisible(state)) return;

    for (state.terrain_preview.entries.items) |*entry| {
        const transition_t = lodTransitionFraction(entry);
        if (entry.lod_transition) |*transition| {
            try gpu_objects.append(state.allocator, terrainSceneObject(
                &transition.mesh,
                transition.texture,
                terrainPreviewColor(state, transition.base_color, transition.lod_index),
                transition_t,
                false,
            ));
        }
        if (entryUsesFarBatch(entry)) continue;
        try gpu_objects.append(state.allocator, terrainSceneObject(
            &entry.mesh,
            entry.texture,
            terrainPreviewColor(state, entry.base_color, entry.lod_index),
            if (entry.lod_transition != null) transition_t else 0,
            entry.lod_transition != null,
        ));
    }
    for (state.terrain_preview.far_batches.items) |*batch| {
        try gpu_objects.append(state.allocator, terrainSceneObject(
            &batch.mesh,
            batch.texture,
            terrainFarBatchPreviewColor(state, batch.base_color),
            0,
            false,
        ));
    }
}

fn terrainSceneObject(
    mesh: *const geometry.Mesh,
    texture: []const u8,
    base_color: shared_color.Color,
    dissolve_amount: f32,
    dissolve_inverted: bool,
) gpu_scene.SceneGpuObject {
    return .{
        .mesh = mesh,
        .texture = texture,
        .base_color = base_color,
        .texture_usage = .terrain_mask,
        .dissolve_amount = dissolve_amount,
        .dissolve_inverted = dissolve_inverted,
    };
}

fn terrainPreviewColor(state: *const ProjectEditorState, base_color: shared_color.Color, lod_index: usize) shared_color.Color {
    if (state.shading_mode == .wireframe) return .{ .r = 135, .g = 220, .b = 160, .a = 255 };
    if (state.shading_mode != .lod_debug) return base_color;
    return terrainLodColor(lod_index);
}

fn terrainFarBatchPreviewColor(state: *const ProjectEditorState, base_color: shared_color.Color) shared_color.Color {
    if (state.shading_mode == .wireframe) return .{ .r = 135, .g = 220, .b = 160, .a = 255 };
    if (state.shading_mode != .lod_debug) return base_color;
    return terrainLodColor(terrain_lod_palette.len - 1);
}

const terrain_lod_palette = [_]shared_color.Color{
    .{ .r = 67, .g = 190, .b = 100, .a = 255 },
    .{ .r = 72, .g = 156, .b = 236, .a = 255 },
    .{ .r = 239, .g = 197, .b = 67, .a = 255 },
    .{ .r = 234, .g = 112, .b = 64, .a = 255 },
    .{ .r = 178, .g = 105, .b = 214, .a = 255 },
    .{ .r = 91, .g = 207, .b = 194, .a = 255 },
};

fn terrainLodColor(lod_index: usize) shared_color.Color {
    return terrain_lod_palette[@min(lod_index, terrain_lod_palette.len - 1)];
}

fn lodTransitionFraction(entry: *const Entry) f32 {
    const transition = entry.lod_transition orelse return 1;
    return std.math.clamp(transition.progress_s / lod_transition_duration_s, 0.0, 1.0);
}

pub fn drawCollisionOverlays(state: *ProjectEditorState, vp_w: f32, vp_h: f32) void {
    if (state.mode != .world_creation) return;
    if (state.shading_mode != .wireframe) return;

    const color: shared_color.Color = .{ .r = 135, .g = 220, .b = 160, .a = 200 };
    for (state.terrain_preview.entries.items) |entry| {
        const bounds = entry.snapshot.bounds;
        project_editor_viewport.drawAabbWireframe(state, .{
            .x = bounds.min.x,
            .y = entry.snapshot.heights[0],
            .z = bounds.min.z,
        }, .{
            .x = bounds.max.x,
            .y = maxHeight(entry.snapshot.heights),
            .z = bounds.max.z,
        }, vp_w, vp_h, color);

        const grid: usize = @intCast(entry.snapshot.size);
        if (grid < 2) continue;
        var z: usize = 0;
        while (z < grid) : (z += 1) {
            var x: usize = 0;
            while (x < grid) : (x += 1) {
                const u = @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(grid - 1));
                const v = @as(f32, @floatFromInt(z)) / @as(f32, @floatFromInt(grid - 1));
                const h = entry.snapshot.heights[z * grid + x];
                const pt = editor_math.Vec3{
                    .x = bounds.min.x + (bounds.max.x - bounds.min.x) * u,
                    .y = h,
                    .z = bounds.min.z + (bounds.max.z - bounds.min.z) * v,
                };
                const screen = project_editor_state.projectViewportPoint(state, pt, vp_w, vp_h) orelse continue;
                project_editor_viewport.drawViewportSquare(state, screen.x, screen.y, 2, color);
            }
        }
    }
}

pub fn scheduleBake(state: *ProjectEditorState) void {
    state.terrain_bake_delay_s = terrain_bake_debounce_s;
}

pub fn tickBake(state: *ProjectEditorState, dt: f32) void {
    if (state.terrain_bake_delay_s <= 0) return;
    state.terrain_bake_delay_s = @max(0, state.terrain_bake_delay_s - dt);
    if (state.terrain_bake_delay_s > 0) return;
    if (state.dirty_cells.count == 0) return;
    const world_bake = @import("project_editor_world_bake.zig");
    world_bake.recompileDirtyCells(state);
}

fn buildEntry(allocator: std.mem.Allocator, snapshot: TileSnapshot, lod_index: usize, grass_preview: ?GrassPreview) !Entry {
    var mesh: geometry.Mesh = .{ .vertices = &.{}, .indices = &.{} };
    var texture: []u8 = &.{};
    var base_color: shared_color.Color = .{ .r = 255, .g = 255, .b = 255, .a = 255 };
    try buildMeshPackage(allocator, &snapshot, lod_index, &mesh, &texture, &base_color);
    return .{
        .snapshot = snapshot,
        .lod_index = lod_index,
        .mesh = mesh,
        .texture = texture,
        .base_color = base_color,
        .grass_preview = grass_preview,
    };
}

fn loadGrassPreviewForCell(state: *ProjectEditorState, id: world.cell.CellId) !?GrassPreview {
    const allocator = state.allocator;
    const cell_path = try world.fcell.bakedCellPath(allocator, "client-debug", "main", id);
    defer allocator.free(cell_path);
    var project_dir = if (std.fs.path.isAbsolute(state.project_path))
        try std.Io.Dir.openDirAbsolute(state.io, state.project_path, .{})
    else
        try std.Io.Dir.cwd().openDir(state.io, state.project_path, .{});
    defer project_dir.close(state.io);
    const bytes = project_dir.readFileAlloc(state.io, cell_path, allocator, .limited(64 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer allocator.free(bytes);
    var world_cell = try world.fcell.decodeCell(allocator, bytes);
    defer world_cell.deinit(allocator);
    var decoded = try modules.grass.runtime.decode(allocator, world_cell.blobs);
    defer decoded.deinit(allocator);
    if (decoded.instances.len == 0) return null;
    const meta = decoded.meta orelse return null;
    const preview_count = @min(decoded.instances.len, max_editor_grass_preview_instances);
    const stride = @max(@as(usize, 1), (decoded.instances.len + preview_count - 1) / preview_count);
    var instances = try allocator.alloc(shared.render_commands.GrassInstance, preview_count);
    errdefer allocator.free(instances);
    var center = friendly_engine.core.math.Vec3f{ .x = 0, .y = 0, .z = 0 };
    var written: usize = 0;
    var source_index: usize = 0;
    while (written < preview_count and source_index < decoded.instances.len) : ({
        written += 1;
        source_index += stride;
    }) {
        const instance = decoded.instances[source_index];
        instances[written] = .{
            .position = instance.position,
            .normal = instance.normal,
            .color = instance.color,
            .height = instance.height,
            .width = instance.width,
            .yaw = instance.yaw,
            .phase = instance.phase,
            .variant = instance.variant,
        };
        center.x += instance.position[0];
        center.y += instance.position[1];
        center.z += instance.position[2];
    }
    if (written != instances.len) {
        instances = try allocator.realloc(instances, written);
    }
    if (instances.len == 0) {
        allocator.free(instances);
        return null;
    }
    const denom = @as(f32, @floatFromInt(instances.len));
    center.x /= denom;
    center.y /= denom;
    center.z /= denom;
    return .{ .instances = instances, .meta = meta, .center = center };
}

fn rebuildMeshInPlace(allocator: std.mem.Allocator, entry: *Entry, lod_index: usize) !void {
    if (entry.lod_transition) |*transition| {
        transition.deinit(allocator);
        entry.lod_transition = null;
    }

    var next_mesh: geometry.Mesh = undefined;
    var next_texture: []u8 = &.{};
    var next_color: shared_color.Color = undefined;
    try buildMeshPackage(allocator, &entry.snapshot, lod_index, &next_mesh, &next_texture, &next_color);
    errdefer {
        next_mesh.deinit(allocator);
        allocator.free(next_texture);
    }

    entry.lod_transition = .{
        .mesh = entry.mesh,
        .texture = entry.texture,
        .base_color = entry.base_color,
        .lod_index = entry.lod_index,
    };
    entry.mesh = next_mesh;
    entry.texture = next_texture;
    entry.base_color = next_color;
    entry.lod_index = lod_index;
}

fn rebuildFarBatchesIfNeeded(state: *ProjectEditorState) !void {
    if (!state.terrain_preview.far_batches_dirty) return;
    state.terrain_preview.clearFarBatches(state.allocator);

    const far_entries = farEntryCount(state.terrain_preview.entries.items);
    if (far_entries == 0) {
        state.terrain_preview.far_batches_dirty = false;
        return;
    }

    var atlas = try FarBatchAtlas.build(state.allocator, state.terrain_preview.entries.items);
    errdefer atlas.deinit(state.allocator);

    var builder: FarBatchBuilder = .{};
    defer builder.deinit(state.allocator);
    for (state.terrain_preview.entries.items) |*entry| {
        if (!entryUsesFarBatch(entry)) continue;
        try builder.appendMesh(state.allocator, &entry.mesh, atlas);
    }

    if (builder.vertices.items.len > 0 and builder.indices.items.len > 0) {
        try builder.smoothSharedNormals(state.allocator);
        try state.terrain_preview.far_batches.append(state.allocator, .{
            .mesh = .{
                .vertices = try builder.vertices.toOwnedSlice(state.allocator),
                .indices = try builder.indices.toOwnedSlice(state.allocator),
            },
            .texture = atlas.texture,
            .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        });
        atlas.texture = &.{};
    }

    state.terrain_preview.far_batches_dirty = false;
}

fn farEntryCount(entries: []const Entry) usize {
    var count: usize = 0;
    for (entries) |*entry| {
        if (entryUsesFarBatch(entry)) count += 1;
    }
    return count;
}

const FarBatchAtlas = struct {
    texture: []u8,
    min_x: i32,
    min_y: i32,
    max_x: i32,
    max_y: i32,
    cell_size_m: f32,
    width_px: usize,
    height_px: usize,

    fn deinit(self: *FarBatchAtlas, allocator: std.mem.Allocator) void {
        allocator.free(self.texture);
        self.texture = &.{};
    }

    fn build(allocator: std.mem.Allocator, entries: []const Entry) !FarBatchAtlas {
        var first = true;
        var min_x: i32 = 0;
        var min_y: i32 = 0;
        var max_x: i32 = 0;
        var max_y: i32 = 0;
        var cell_size_m: f32 = 0;
        for (entries) |*entry| {
            if (!entryUsesFarBatch(entry)) continue;
            const cell = entry.snapshot.cell;
            if (first) {
                min_x = cell.x;
                min_y = cell.y;
                max_x = cell.x;
                max_y = cell.y;
                cell_size_m = entry.snapshot.bounds.max.x - entry.snapshot.bounds.min.x;
                first = false;
            } else {
                min_x = @min(min_x, cell.x);
                min_y = @min(min_y, cell.y);
                max_x = @max(max_x, cell.x);
                max_y = @max(max_y, cell.y);
            }
        }
        if (first) return error.NoFarTerrainCells;
        if (!std.math.isFinite(cell_size_m) or cell_size_m <= 0) return error.InvalidTerrainCellSize;

        const texture = try allocator.alloc(u8, mesh_builder.terrain_texture_size);
        @memset(texture, 0);
        errdefer allocator.free(texture);

        var atlas = FarBatchAtlas{
            .texture = texture,
            .min_x = min_x,
            .min_y = min_y,
            .max_x = max_x,
            .max_y = max_y,
            .cell_size_m = cell_size_m,
            .width_px = far_batch_texture_size,
            .height_px = far_batch_texture_size,
        };
        try atlas.paintOverview(allocator, entries);
        return atlas;
    }

    fn paintOverview(self: *FarBatchAtlas, allocator: std.mem.Allocator, entries: []const Entry) !void {
        const grid_w: usize = @intCast(self.max_x - self.min_x + 1);
        const grid_h: usize = @intCast(self.max_y - self.min_y + 1);
        const lookup = try allocator.alloc(?*const Entry, grid_w * grid_h);
        defer allocator.free(lookup);
        @memset(lookup, null);

        for (entries) |*entry| {
            if (!entryUsesFarBatch(entry)) continue;
            const cell = entry.snapshot.cell;
            const x: usize = @intCast(cell.x - self.min_x);
            const y: usize = @intCast(cell.y - self.min_y);
            lookup[y * grid_w + x] = entry;
        }

        const denom_x = @as(f32, @floatFromInt(self.width_px - 1));
        const denom_y = @as(f32, @floatFromInt(self.height_px - 1));
        var y: usize = 0;
        while (y < self.height_px) : (y += 1) {
            const v = @as(f32, @floatFromInt(y)) / denom_y;
            var x: usize = 0;
            while (x < self.width_px) : (x += 1) {
                const u = @as(f32, @floatFromInt(x)) / denom_x;
                const world_x = self.minWorldX() + (self.maxWorldX() - self.minWorldX()) * u;
                const world_z = self.minWorldZ() + (self.maxWorldZ() - self.minWorldZ()) * v;
                const cell_x: i32 = @intFromFloat(@floor(world_x / self.cell_size_m));
                const cell_y: i32 = @intFromFloat(@floor(world_z / self.cell_size_m));
                const dst = (y * self.width_px + x) * 4;
                if (cell_x < self.min_x or cell_x > self.max_x or cell_y < self.min_y or cell_y > self.max_y) {
                    self.texture[dst] = 0;
                    self.texture[dst + 1] = 0;
                    self.texture[dst + 2] = 0;
                    self.texture[dst + 3] = 0;
                    continue;
                }
                const lookup_x: usize = @intCast(cell_x - self.min_x);
                const lookup_y: usize = @intCast(cell_y - self.min_y);
                const entry = lookup[lookup_y * grid_w + lookup_x] orelse {
                    self.texture[dst] = 0;
                    self.texture[dst + 1] = 0;
                    self.texture[dst + 2] = 0;
                    self.texture[dst + 3] = 0;
                    continue;
                };
                const source_size = textureSquareSize(entry.texture) orelse return error.InvalidTerrainTexture;
                const local_u = std.math.clamp((world_x - entry.snapshot.bounds.min.x) / (entry.snapshot.bounds.max.x - entry.snapshot.bounds.min.x), 0.0, 1.0);
                const local_v = std.math.clamp((world_z - entry.snapshot.bounds.min.z) / (entry.snapshot.bounds.max.z - entry.snapshot.bounds.min.z), 0.0, 1.0);
                const src_x: usize = @intFromFloat(@round(local_u * @as(f32, @floatFromInt(source_size - 1))));
                const src_y: usize = @intFromFloat(@round(local_v * @as(f32, @floatFromInt(source_size - 1))));
                const src = (src_y * source_size + src_x) * 4;
                self.texture[dst] = entry.texture[src];
                self.texture[dst + 1] = entry.texture[src + 1];
                self.texture[dst + 2] = entry.texture[src + 2];
                self.texture[dst + 3] = entry.texture[src + 3];
            }
        }
    }

    fn remapUv(self: FarBatchAtlas, position: editor_math.Vec3) editor_math.Vec2 {
        return .{
            .x = std.math.clamp((position.x - self.minWorldX()) / (self.maxWorldX() - self.minWorldX()), 0.0, 1.0),
            .y = std.math.clamp((position.z - self.minWorldZ()) / (self.maxWorldZ() - self.minWorldZ()), 0.0, 1.0),
        };
    }

    fn minWorldX(self: FarBatchAtlas) f32 {
        return @as(f32, @floatFromInt(self.min_x)) * self.cell_size_m;
    }

    fn minWorldZ(self: FarBatchAtlas) f32 {
        return @as(f32, @floatFromInt(self.min_y)) * self.cell_size_m;
    }

    fn maxWorldX(self: FarBatchAtlas) f32 {
        return @as(f32, @floatFromInt(self.max_x + 1)) * self.cell_size_m;
    }

    fn maxWorldZ(self: FarBatchAtlas) f32 {
        return @as(f32, @floatFromInt(self.max_y + 1)) * self.cell_size_m;
    }
};

fn findFarEntry(entries: []const Entry, cell_x: i32, cell_y: i32) ?*const Entry {
    for (entries) |*entry| {
        if (!entryUsesFarBatch(entry)) continue;
        if (entry.snapshot.cell.x == cell_x and entry.snapshot.cell.y == cell_y) return entry;
    }
    return null;
}

fn textureSquareSize(texture: []const u8) ?usize {
    if (texture.len == 0 or texture.len % 4 != 0) return null;
    const pixels = texture.len / 4;
    const size_float = @sqrt(@as(f64, @floatFromInt(pixels)));
    const size: usize = @intFromFloat(size_float);
    if (size * size != pixels) return null;
    return size;
}

const FarBatchBuilder = struct {
    vertices: std.ArrayList(geometry.Vertex) = .empty,
    indices: std.ArrayList(u32) = .empty,

    fn deinit(self: *FarBatchBuilder, allocator: std.mem.Allocator) void {
        self.vertices.deinit(allocator);
        self.indices.deinit(allocator);
    }

    fn appendMesh(self: *FarBatchBuilder, allocator: std.mem.Allocator, mesh: *const geometry.Mesh, atlas: FarBatchAtlas) !void {
        if (mesh.vertices.len == 0 or mesh.indices.len == 0) return;
        const vertex_offset = self.vertices.items.len;
        if (vertex_offset + mesh.vertices.len > std.math.maxInt(u32)) return error.TerrainBatchMeshTooLarge;
        try self.vertices.ensureUnusedCapacity(allocator, mesh.vertices.len);
        for (mesh.vertices) |vertex| {
            var remapped = vertex;
            remapped.uv = atlas.remapUv(vertex.position);
            self.vertices.appendAssumeCapacity(remapped);
        }
        try self.indices.ensureUnusedCapacity(allocator, mesh.indices.len);
        for (mesh.indices) |index| {
            self.indices.appendAssumeCapacity(@as(u32, @intCast(vertex_offset)) + index);
        }
    }

    fn smoothSharedNormals(self: *FarBatchBuilder, allocator: std.mem.Allocator) !void {
        var normal_map = std.AutoHashMap(PositionKey, NormalAccum).init(allocator);
        defer normal_map.deinit();

        for (self.vertices.items) |vertex| {
            const key = PositionKey.from(vertex.position);
            const entry = try normal_map.getOrPut(key);
            if (!entry.found_existing) entry.value_ptr.* = .{};
            entry.value_ptr.add(vertex.normal);
        }

        for (self.vertices.items) |*vertex| {
            const accum = normal_map.get(PositionKey.from(vertex.position)) orelse continue;
            vertex.normal = accum.normalized();
        }
    }
};

const PositionKey = struct {
    x: i64,
    y: i64,
    z: i64,

    fn from(position: editor_math.Vec3) PositionKey {
        const scale = 100.0;
        return .{
            .x = @intFromFloat(@round(position.x * scale)),
            .y = @intFromFloat(@round(position.y * scale)),
            .z = @intFromFloat(@round(position.z * scale)),
        };
    }
};

const NormalAccum = struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,
    count: u32 = 0,

    fn add(self: *NormalAccum, normal: editor_math.Vec3) void {
        self.x += normal.x;
        self.y += normal.y;
        self.z += normal.z;
        self.count += 1;
    }

    fn normalized(self: NormalAccum) editor_math.Vec3 {
        if (self.count == 0) return .{ .x = 0, .y = 1, .z = 0 };
        const len = @sqrt(self.x * self.x + self.y * self.y + self.z * self.z);
        if (len <= 0.0001) return .{ .x = 0, .y = 1, .z = 0 };
        return .{ .x = self.x / len, .y = self.y / len, .z = self.z / len };
    }
};

fn entryUsesFarBatch(entry: *const Entry) bool {
    return entry.snapshot.lod_levels.len > 1 and entry.lod_index + 1 >= entry.snapshot.lod_levels.len;
}

fn dominantPaintLayerIndex(splat: []const u8, layer_count: usize) usize {
    if (layer_count == 0) return 0;
    var totals = [_]u64{0} ** 16;
    const capped_layer_count = @min(layer_count, totals.len);
    var sample: usize = 0;
    while ((sample + 1) * layer_count <= splat.len) : (sample += 1) {
        const base = sample * layer_count;
        var layer: usize = 0;
        while (layer < capped_layer_count) : (layer += 1) {
            totals[layer] += splat[base + layer];
        }
    }

    var best_index: usize = 0;
    var best_total: u64 = 0;
    var layer: usize = 0;
    while (layer < capped_layer_count) : (layer += 1) {
        if (totals[layer] > best_total) {
            best_total = totals[layer];
            best_index = layer;
        }
    }
    return best_index;
}

fn farBatchColorForLayer(entries: []const Entry, layer_index: usize) shared_color.Color {
    for (entries) |entry| {
        if (layer_index < entry.snapshot.paint_colors.len) {
            const color = entry.snapshot.paint_colors[layer_index];
            return .{ .r = color[0], .g = color[1], .b = color[2], .a = color[3] };
        }
    }
    return .{ .r = 128, .g = 128, .b = 128, .a = 255 };
}

fn buildMeshPackage(
    allocator: std.mem.Allocator,
    snapshot: *const TileSnapshot,
    lod_index: usize,
    mesh_out: *geometry.Mesh,
    texture_out: *[]u8,
    color_out: *shared_color.Color,
) !void {
    const lod_size = snapshot.lod_levels[lod_index];
    const neighbors = mesh_builder.HeightNeighbors{
        .west = if (snapshot.west_heights) |heights| .{ .size = snapshot.size, .heights = heights } else null,
        .east = if (snapshot.east_heights) |heights| .{ .size = snapshot.size, .heights = heights } else null,
        .south = if (snapshot.south_heights) |heights| .{ .size = snapshot.size, .heights = heights } else null,
        .north = if (snapshot.north_heights) |heights| .{ .size = snapshot.size, .heights = heights } else null,
    };
    var render_mesh = try mesh_builder.buildLodMesh(
        allocator,
        snapshot.bounds,
        .{ .size = snapshot.size, .heights = snapshot.heights },
        lod_size,
        lod_index,
        neighbors,
    );
    errdefer render_mesh.deinit(allocator);

    texture_out.* = try splat_texture.buildLayerTexture(
        allocator,
        snapshot.splat_size,
        snapshot.paint_layers,
        snapshot.paint_colors,
        snapshot.splat,
    );
    errdefer allocator.free(texture_out.*);

    mesh_out.* = .{
        .vertices = try allocator.alloc(geometry.Vertex, render_mesh.vertices.len),
        .indices = try allocator.dupe(u32, render_mesh.indices),
    };
    for (render_mesh.vertices, 0..) |vertex, idx| {
        mesh_out.vertices[idx] = .{
            .position = .{ .x = vertex.position.x, .y = vertex.position.y, .z = vertex.position.z },
            .normal = .{ .x = vertex.normal.x, .y = vertex.normal.y, .z = vertex.normal.z },
            .uv = .{ .x = vertex.uv.x, .y = vertex.uv.y },
        };
    }
    color_out.* = .{
        .r = render_mesh.base_color.r,
        .g = render_mesh.base_color.g,
        .b = render_mesh.base_color.b,
        .a = render_mesh.base_color.a,
    };

    allocator.free(render_mesh.vertices);
    allocator.free(render_mesh.indices);
    allocator.free(render_mesh.texture);
    allocator.free(render_mesh.name);
}

fn markClipmapStaleIfNeeded(state: *ProjectEditorState) void {
    if (!terrainBatchActive(state)) return;
    const camera = cameraTargetVec(state);
    const cell_size = state.world_cell_size_m;
    std.debug.assert(std.math.isFinite(cell_size) and cell_size > 0);
    const radius = clipmapRadiusCells(cell_size, effectiveDrawDistance(state));
    const id = world.cell.CellId{
        .x = @intFromFloat(@floor(camera.x / cell_size)),
        .y = @intFromFloat(@floor(camera.z / cell_size)),
        .z = 0,
    };
    if (!id.eql(state.terrain_clip_cell) or radius != state.terrain_clip_radius_cells) {
        state.terrain_clip_cell = id;
        state.terrain_clip_radius_cells = radius;
        state.terrain_preview_stale = true;
    }
}

pub fn effectiveDrawDistance(state: *const ProjectEditorState) f32 {
    if (terrainBatchActive(state)) return state.world_cell_size_m * batch_draw_radius_cells;
    const camera_reach = state.camera.distance + state.world_cell_size_m * 2.0;
    return @max(state.terrain_detail_distance_m, camera_reach);
}

const PreviewBudget = struct {
    max_loads: usize,
    max_resident: usize,
};

fn previewBudget(state: *const ProjectEditorState, candidate_count: usize) PreviewBudget {
    if (terrainBatchActive(state)) return .{
        .max_loads = batch_max_cells_loaded_per_refresh,
        .max_resident = batch_max_resident_cells,
    };
    return .{
        .max_loads = @max(candidate_count, 1),
        .max_resident = @max(candidate_count, 1),
    };
}

fn terrainBatchActive(state: *const ProjectEditorState) bool {
    if (state.terrain_batch_job) |job| return job.active and !job.cancelled and !job.failed;
    if (state.terrain_edge_cliff_job) |job| return job.active and !job.cancelled and !job.failed;
    return false;
}

fn editableTerrainLodIndex(distance_m: f32, cell_size_m: f32, lod_level_count: usize) usize {
    return lod_pick.pickLodIndex(distance_m, cell_size_m, lod_level_count);
}

fn cameraTargetVec(state: *const ProjectEditorState) @import("friendly_engine").core.math.Vec3f {
    return .{
        .x = state.camera.target.x,
        .y = state.camera.target.y,
        .z = state.camera.target.z,
    };
}

fn cameraEyeVec(state: *const ProjectEditorState) @import("friendly_engine").core.math.Vec3f {
    const eye = state.camera.eye();
    return .{ .x = eye.x, .y = eye.y, .z = eye.z };
}

fn cellInClipmap(id: world.cell.CellId, camera: @import("friendly_engine").core.math.Vec3f, cell_size_m: f32, draw_distance_m: f32) bool {
    const radius = clipmapRadiusCells(cell_size_m, draw_distance_m);
    const cx = @as(i32, @intFromFloat(@floor(camera.x / cell_size_m)));
    const cy = @as(i32, @intFromFloat(@floor(camera.z / cell_size_m)));
    const dx = @abs(id.x - cx);
    const dy = @abs(id.y - cy);
    return dx <= radius and dy <= radius;
}

pub fn clipmapRadiusCells(cell_size_m: f32, draw_distance_m: f32) i32 {
    std.debug.assert(std.math.isFinite(cell_size_m) and cell_size_m > 0);
    std.debug.assert(std.math.isFinite(draw_distance_m) and draw_distance_m > 0);
    const raw: i32 = @intFromFloat(@ceil(draw_distance_m / cell_size_m));
    return @min(clipmap_max_radius_cells, @max(clipmap_min_radius_cells, raw));
}

fn maxHeight(heights: []const f32) f32 {
    var peak: f32 = -std.math.floatMax(f32);
    for (heights) |sample| peak = @max(peak, sample);
    return peak;
}

test "clipmap radius derives from meter draw distance and clamps budget" {
    try std.testing.expectEqual(@as(i32, 64), clipmapRadiusCells(64, 4096));
    try std.testing.expectEqual(@as(i32, 32), clipmapRadiusCells(128, 4096));
    try std.testing.expectEqual(@as(i32, 16), clipmapRadiusCells(256, 4096));
    try std.testing.expectEqual(@as(i32, 2), clipmapRadiusCells(2048, 4096));
    try std.testing.expectEqual(@as(i32, 2), clipmapRadiusCells(8192, 4096));
    try std.testing.expectEqual(@as(i32, 64), clipmapRadiusCells(1, 4096));
    try std.testing.expectEqual(@as(i32, 8), clipmapRadiusCells(256, 2048));
}

test "terrain height sampling interpolates within tile bounds" {
    const bounds = world.cell.boundsForCell(.{ .x = 0, .y = 0, .z = 0 }, 10, world.cell.default_cell_height_m);
    const heights = [_]f32{
        0,  10,
        20, 30,
    };
    const height = sampleHeightInTile(bounds, 2, &heights, .{ .x = 5, .y = 0, .z = 5 });
    try std.testing.expectApproxEqAbs(@as(f32, 15), height, 0.001);
}

test "resident terrain height samples loaded preview entries" {
    const bounds = world.cell.boundsForCell(.{ .x = 0, .y = 0, .z = 0 }, 10, world.cell.default_cell_height_m);
    var heights = [_]f32{
        2, 4,
        6, 8,
    };
    const snapshot = TileSnapshot{
        .cell = .{ .x = 0, .y = 0, .z = 0 },
        .bounds = bounds,
        .size = 2,
        .lod_levels = &.{},
        .heights = &heights,
        .west_heights = null,
        .east_heights = null,
        .south_heights = null,
        .north_heights = null,
        .splat_size = 0,
        .splat = &.{},
        .paint_layers = &.{},
        .paint_colors = &.{},
        .paint_albedo_textures = &.{},
        .paint_roughness_textures = &.{},
        .paint_specular_textures = &.{},
        .paint_displacement_textures = &.{},
        .material = "",
    };
    const entries = [_]Entry{.{
        .snapshot = snapshot,
        .lod_index = 0,
        .mesh = .{ .vertices = &.{}, .indices = &.{} },
        .texture = &.{},
        .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    }};

    try std.testing.expectApproxEqAbs(@as(f32, 5), residentHeightAtPoint(&entries, .{ .x = 5, .y = -10, .z = 5 }).?, 0.001);
    try std.testing.expect(residentHeightAtPoint(&entries, .{ .x = 20, .y = -10, .z = 5 }) == null);
}

test "clipmap includes cells inside dynamic radius" {
    const camera = @import("friendly_engine").core.math.Vec3f{ .x = 32, .y = 0, .z = 32 };
    try std.testing.expect(cellInClipmap(.{ .x = 64, .y = 0, .z = 0 }, camera, 64, 4096));
    try std.testing.expect(!cellInClipmap(.{ .x = 65, .y = 0, .z = 0 }, camera, 64, 4096));
}

test "editor terrain preview uses linear lod bands" {
    try std.testing.expectEqual(@as(usize, 0), editableTerrainLodIndex(128, 256, 5));
    try std.testing.expectEqual(@as(usize, 1), editableTerrainLodIndex(256, 256, 5));
    try std.testing.expectEqual(@as(usize, 2), editableTerrainLodIndex(512, 256, 5));
    try std.testing.expectEqual(@as(usize, 3), editableTerrainLodIndex(768, 256, 5));
    try std.testing.expectEqual(@as(usize, 4), editableTerrainLodIndex(1024, 256, 5));
    try std.testing.expectEqual(@as(usize, 4), editableTerrainLodIndex(2048, 256, 5));
}

test "editor terrain preview keeps a broad far field resident budget" {
    try std.testing.expect(max_resident_cells >= 2304);
    try std.testing.expect(max_cells_loaded_per_refresh >= 32);
}

test "lod transition fraction clamps to transition duration" {
    const snapshot = TileSnapshot{
        .cell = .{ .x = 0, .y = 0, .z = 0 },
        .bounds = world.cell.boundsForCell(.{ .x = 0, .y = 0, .z = 0 }, 64, world.cell.default_cell_height_m),
        .size = 0,
        .lod_levels = &.{},
        .heights = &.{},
        .west_heights = null,
        .east_heights = null,
        .south_heights = null,
        .north_heights = null,
        .splat_size = 0,
        .splat = &.{},
        .paint_layers = &.{},
        .paint_colors = &.{},
        .paint_albedo_textures = &.{},
        .paint_roughness_textures = &.{},
        .paint_specular_textures = &.{},
        .paint_displacement_textures = &.{},
        .material = "",
    };
    const mesh = geometry.Mesh{ .vertices = &.{}, .indices = &.{} };
    var entry = Entry{
        .snapshot = snapshot,
        .lod_index = 0,
        .mesh = mesh,
        .texture = &.{},
        .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .lod_transition = .{
            .mesh = mesh,
            .texture = &.{},
            .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
            .lod_index = 0,
            .progress_s = lod_transition_duration_s * 0.5,
        },
    };
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), lodTransitionFraction(&entry), 0.001);
    entry.lod_transition.?.progress_s = lod_transition_duration_s * 2.0;
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), lodTransitionFraction(&entry), 0.001);
}

test "coarsest terrain lod uses far batch" {
    const snapshot = TileSnapshot{
        .cell = .{ .x = 0, .y = 0, .z = 0 },
        .bounds = world.cell.boundsForCell(.{ .x = 0, .y = 0, .z = 0 }, 64, world.cell.default_cell_height_m),
        .size = 0,
        .lod_levels = @constCast(&[_]u32{ 32, 16, 8, 4, 2 }),
        .heights = &.{},
        .west_heights = null,
        .east_heights = null,
        .south_heights = null,
        .north_heights = null,
        .splat_size = 0,
        .splat = &.{},
        .paint_layers = &.{},
        .paint_colors = &.{},
        .paint_albedo_textures = &.{},
        .paint_roughness_textures = &.{},
        .paint_specular_textures = &.{},
        .paint_displacement_textures = &.{},
        .material = "",
    };
    const entry = Entry{
        .snapshot = snapshot,
        .lod_index = 4,
        .mesh = .{ .vertices = &.{}, .indices = &.{} },
        .texture = &.{},
        .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    };
    try std.testing.expect(entryUsesFarBatch(&entry));
}

test "terrain preview marks terrain textures as terrain masks" {
    const mesh = geometry.Mesh{ .vertices = &.{}, .indices = &.{} };
    const texture = [_]u8{ 0, 0, 0, 255 };
    const object = terrainSceneObject(
        &mesh,
        &texture,
        .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        0,
        false,
    );

    try std.testing.expectEqual(gpu_scene.TextureUsage.terrain_mask, object.texture_usage);
}

test "terrain lod preview colors are stable and clamp to palette" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
    };
    const base_color: shared_color.Color = .{ .r = 12, .g = 34, .b = 56, .a = 255 };

    try std.testing.expectEqual(terrain_lod_palette[0], terrainLodColor(0));
    try std.testing.expectEqual(terrain_lod_palette[1], terrainLodColor(1));
    try std.testing.expectEqual(terrain_lod_palette[terrain_lod_palette.len - 1], terrainLodColor(99));
    try std.testing.expectEqual(base_color, terrainPreviewColor(&state, base_color, 1));
    try std.testing.expectEqual(base_color, terrainFarBatchPreviewColor(&state, base_color));
    state.shading_mode = .lod_debug;
    try std.testing.expectEqual(terrain_lod_palette[1], terrainPreviewColor(&state, base_color, 1));
    try std.testing.expectEqual(terrain_lod_palette[terrain_lod_palette.len - 1], terrainFarBatchPreviewColor(&state, base_color));
}

test "far terrain batch picks dominant splat layer" {
    const splat = [_]u8{
        10, 200, 0,
        20, 180, 0,
        30, 170, 0,
    };
    try std.testing.expectEqual(@as(usize, 1), dominantPaintLayerIndex(&splat, 3));
}

test "far terrain batch smooths duplicate border normals" {
    var builder = FarBatchBuilder{};
    defer builder.deinit(std.testing.allocator);

    try builder.vertices.append(std.testing.allocator, .{
        .position = .{ .x = 256, .y = 12, .z = 0 },
        .normal = .{ .x = 1, .y = 0, .z = 0 },
        .uv = .{ .x = 0, .y = 0 },
    });
    try builder.vertices.append(std.testing.allocator, .{
        .position = .{ .x = 256, .y = 12, .z = 0 },
        .normal = .{ .x = 0, .y = 1, .z = 0 },
        .uv = .{ .x = 1, .y = 0 },
    });

    try builder.smoothSharedNormals(std.testing.allocator);
    try std.testing.expectApproxEqAbs(builder.vertices.items[0].normal.x, builder.vertices.items[1].normal.x, 0.001);
    try std.testing.expectApproxEqAbs(builder.vertices.items[0].normal.y, builder.vertices.items[1].normal.y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.707), builder.vertices.items[0].normal.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.707), builder.vertices.items[0].normal.y, 0.001);
}

test "neighbor height slot tracks resident adjacent cell heights" {
    var slot: ?[]f32 = null;
    defer if (slot) |heights| std.testing.allocator.free(heights);

    const heights = [_]f32{ 0, 1, 2, 3 };
    try std.testing.expect(try syncNeighborSlot(std.testing.allocator, &slot, &heights));
    try std.testing.expect(slot != null);
    try std.testing.expectEqualSlices(f32, &heights, slot.?);
    try std.testing.expect(!try syncNeighborSlot(std.testing.allocator, &slot, &heights));
    try std.testing.expect(try syncNeighborSlot(std.testing.allocator, &slot, null));
    try std.testing.expect(slot == null);
}
