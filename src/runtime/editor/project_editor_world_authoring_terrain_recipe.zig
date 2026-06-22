const std = @import("std");
const friendly_engine = @import("friendly_engine");

const project_editor_state = @import("project_editor_state.zig");
const project_editor_terrain_preview = @import("project_editor_terrain_preview.zig");
const project_editor_terrain_undo_store = @import("project_editor_terrain_undo_store.zig");
const project_editor_types = @import("project_editor_types.zig");
const terrain = @import("project_editor_world_authoring_terrain.zig");
const terrain_manifest = @import("project_editor_world_authoring_manifest.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const TerrainRecipeFeature = project_editor_types.TerrainRecipeFeature;
const TerrainRecipeJob = project_editor_types.TerrainRecipeJob;
const modules = friendly_engine.modules;
const world = friendly_engine.world;
const terrain_chunk_store = modules.terrain.chunk_store;

pub const StartOptions = struct {
    min_x: i32,
    max_x: i32,
    min_z: i32,
    max_z: i32,
    cell_size_m: f32,
    seed: u64,
    sea_level: f32,
    ocean_floor: f32,
    features: []const TerrainRecipeFeature,
};

const TileStats = struct {
    min_height: f32,
    max_height: f32,
};

const TerrainSample = struct {
    height: f32,
    land: bool,
    shore: f32,
    slope_hint: f32 = 0,
    void_depth: f32 = 0,
};

pub fn start(state: *ProjectEditorState, options: StartOptions) !void {
    if (options.max_x < options.min_x or options.max_z < options.min_z) return error.InvalidTerrainRecipeBounds;
    if (!std.math.isFinite(options.cell_size_m) or options.cell_size_m <= 0) return error.InvalidTerrainRecipeCellSize;
    if (!std.math.isFinite(options.sea_level) or !std.math.isFinite(options.ocean_floor)) return error.InvalidTerrainRecipeHeight;
    if (options.features.len == 0 or options.features.len > 128) return error.InvalidTerrainRecipeFeatureCount;

    const width: u64 = @intCast(options.max_x - options.min_x + 1);
    const depth: u64 = @intCast(options.max_z - options.min_z + 1);
    var job = TerrainRecipeJob{
        .id = options.seed ^ (@as(u64, @intCast(width)) << 32) ^ @as(u64, @intCast(depth)),
        .started_ns = nowNs(state),
        .min_x = options.min_x,
        .max_x = options.max_x,
        .min_z = options.min_z,
        .max_z = options.max_z,
        .cell_size_m = options.cell_size_m,
        .total = width * depth,
        .seed = options.seed,
        .sea_level = options.sea_level,
        .ocean_floor = options.ocean_floor,
        .feature_count = @intCast(options.features.len),
        .undo_transaction_id = nowNs(state),
        .active = true,
    };
    @memcpy(job.features[0..options.features.len], options.features);
    job.setStatus("Terrain recipe queued");
    state.terrain_recipe_job = job;
    state.mode = .world_creation;
    state.world_tool = .terrain;
    state.selected_world_layer = .terrain_base_height;
    state.world_cell_size_m = options.cell_size_m;
    project_editor_state.setStatus(state, "Terrain recipe queued");
}

pub fn cancel(state: *ProjectEditorState) void {
    if (state.terrain_recipe_job) |*job| {
        job.active = false;
        job.cancelled = true;
        job.setStatus("Terrain recipe cancelled");
        project_editor_state.setStatus(state, "Terrain recipe cancelled");
    }
}

pub fn tick(state: *ProjectEditorState) !void {
    var job = &(state.terrain_recipe_job orelse return);
    if (!job.active or job.complete or job.cancelled or job.failed) return;
    if (job.next_offset >= job.total) {
        finishJob(state, job);
        return;
    }

    const tick_start_ns = nowNs(state);
    var processed_this_tick: u32 = 0;
    while (job.next_offset < job.total) {
        const id = cellAtOffset(job.*, job.next_offset);
        const stats = writeTerrainTile(state, job, id) catch |err| {
            failJob(state, job, err);
            return err;
        };
        job.next_offset += 1;
        job.changed_cells += 1;
        job.min_height = @min(job.min_height, stats.min_height);
        job.max_height = @max(job.max_height, stats.max_height);
        project_editor_state.markDirtyCell(state, "Terrain", id, "terrain recipe") catch |err| switch (err) {
            error.TooManyDirtyCells => job.dirty_overflow = true,
            else => return err,
        };
        processed_this_tick += 1;
        if (durationNs(tick_start_ns, nowNs(state)) >= job.tick_budget_ns) break;
    }

    job.last_tick_cells = processed_this_tick;
    job.last_tick_ns = durationNs(tick_start_ns, nowNs(state));
    if (job.next_offset >= job.total) {
        finishJob(state, job);
        return;
    }

    var status_buf: [160]u8 = undefined;
    const status = std.fmt.bufPrint(&status_buf, "Terrain recipe {d}/{d} cells", .{ job.next_offset, job.total }) catch "Terrain recipe progress";
    job.setStatus(status);
    project_editor_state.setStatus(state, status);
    state.terrain_preview_stale = true;
}

fn finishJob(state: *ProjectEditorState, job: *TerrainRecipeJob) void {
    job.active = false;
    job.complete = true;
    _ = project_editor_terrain_undo_store.pruneAfterTransaction(state.allocator, state.io, state.project_path, state.terrain_undo_limit_mb) catch {};
    job.setStatus("Terrain recipe complete");
    state.terrain_preview_stale = true;
    project_editor_terrain_preview.scheduleBake(state);
    project_editor_state.setStatus(state, "Terrain recipe complete");
}

fn failJob(state: *ProjectEditorState, job: *TerrainRecipeJob, err: anyerror) void {
    job.active = false;
    job.failed = true;
    var buf: [160]u8 = undefined;
    const message = std.fmt.bufPrint(&buf, "Terrain recipe failed: {s}", .{@errorName(err)}) catch "Terrain recipe failed";
    job.setStatus(message);
    project_editor_state.setStatus(state, message);
}

fn writeTerrainTile(state: *ProjectEditorState, job: *TerrainRecipeJob, id: world.cell.CellId) !TileStats {
    _ = try terrain_manifest.pathForState(state);
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
            const sample = terrainAt(job.*, world_x, world_z);
            const index = z * terrain.terrain_tile_size + x;
            heights[index] = quantizeHeight(sample.height);
            min_height = @min(min_height, heights[index]);
            max_height = @max(max_height, heights[index]);
            const layer = paintLayerForSample(sample, world_x, world_z);
            const base = index * layer_count;
            @memset(splat[base..][0..layer_count], 0);
            splat[base + layer] = 255;
        }
    }

    const region_path = try terrain_chunk_store.regionPath(state.allocator, id);
    defer state.allocator.free(region_path);
    const tx = project_editor_terrain_undo_store.beginTransaction(job.undo_transaction_id);
    if (try project_editor_terrain_undo_store.snapshotFileOnce(state.allocator, state.io, state.project_path, tx, region_path)) {
        job.undo_snapshots += 1;
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

fn terrainAt(job: TerrainRecipeJob, x: f32, z: f32) TerrainSample {
    const warped = warpWorld(job.seed, x, z);
    var sample = TerrainSample{ .height = job.ocean_floor, .land = false, .shore = 0 };
    for (job.features[0..job.feature_count], 0..) |feature, index| {
        switch (feature.brush) {
            .irregular_island_mask => applyIslandMask(job, feature, warped.x, warped.z, &sample),
            .caldera_complex => if (sample.land) applyCaldera(feature, warped.x, warped.z, &sample),
            .radial_volcanic_ridges => if (sample.land) applyRadialRidges(job.seed + index * 977, feature, warped.x, warped.z, &sample),
            .ashland_badlands => if (sample.land) applyAshlands(job.seed + index * 977, feature, warped.x, warped.z, &sample),
            .marsh_delta => if (sample.land) applyMarshDelta(job.seed + index * 977, feature, warped.x, warped.z, &sample),
            .broken_highland_craters => if (sample.land) applyBrokenHighlands(job.seed + index * 977, feature, warped.x, warped.z, &sample),
            .fjord_horn_coast => if (sample.land) applyFjordHorns(job.seed + index * 977, feature, warped.x, warped.z, &sample),
            .chalk_plateau_massif => if (sample.land) applyChalkPlateau(job.seed + index * 977, feature, warped.x, warped.z, &sample),
            .dry_basin_washes => if (sample.land) applyDryBasins(job.seed + index * 977, feature, warped.x, warped.z, &sample),
            .coastal_hook_shelves => if (sample.land) applyHookCoast(job.seed + index * 977, feature, warped.x, warped.z, &sample),
            .volcanic_outlier => applyVolcanicOutlier(job, feature, warped.x, warped.z, &sample),
            .sea_wall_dropoff => applySeaWall(job.seed + index * 977, feature, x, z, &sample),
        }
    }
    applyWorldEdgeCarve(job, x, z, &sample);
    if (sample.land) applyLandscapeDetail(job, x, z, &sample);
    applyWorldVoidFeather(job, x, z, &sample);
    sample.height = std.math.clamp(sample.height, job.ocean_floor - 720, 930);
    return sample;
}

fn applyIslandMask(job: TerrainRecipeJob, feature: TerrainRecipeFeature, x: f32, z: f32, sample: *TerrainSample) void {
    const dx = x - feature.center_x;
    const dz = z - feature.center_z;
    const angle = std.math.atan2(dz, dx);
    const edge = 1.0 + feature.coast_noise * (0.52 * @sin(angle * 7.0 + 0.6) +
        0.32 * @sin(angle * 13.0 - 1.1) +
        0.16 * @sin(angle * 23.0 + 2.4));
    const nx = dx / @max(1, feature.radius_x * edge);
    const nz = dz / @max(1, feature.radius_z * edge);
    const d = @sqrt(nx * nx + nz * nz);
    const islet = offshoreIslet(job.seed, x, z);
    sample.void_depth = @max(sample.void_depth, smoothstep(1.02, 1.42, d));
    if (d <= 1.0 or islet > 0) {
        const interior = @max(0, 1 - d);
        sample.land = true;
        sample.shore = @min(1, interior / 0.08);
        sample.void_depth = 0;
        const shelf = smoothstep(0, 0.18, interior);
        const continental = std.math.pow(f32, @max(0, 1 - d * 0.86), 1.45);
        const coastal_steps = 18 * shelf * @floor((continental + valueNoise(job.seed + 701, x, z, 1250) * 0.08) * 5.0) / 5.0;
        const foothills = 62 * shelf * fbm(job.seed + 703, x, z, 980, 4);
        sample.height = job.sea_level + feature.height * shelf + 145 * continental + coastal_steps + foothills + islet;
        sample.slope_hint += @abs(valueNoise(job.seed + 707, x, z, 430)) * 0.2;
    }
}

fn applyCaldera(feature: TerrainRecipeFeature, x: f32, z: f32, sample: *TerrainSample) void {
    const d = distance(x, z, feature.center_x, feature.center_z);
    const outer = ring(d, feature.inner_radius, feature.outer_radius);
    const breach = breachFactor(x, z, feature, d);
    const scallop = 0.82 + 0.18 * @sin(std.math.atan2(z - feature.center_z, x - feature.center_x) * 11.0 + d * 0.006);
    sample.height += feature.rim_height * outer * breach * scallop;
    if (d < feature.inner_radius) {
        const floor_blend = 1 - smoothstep(feature.inner_radius * 0.72, feature.inner_radius, d);
        sample.height = lerp(sample.height, feature.crater_floor, floor_blend);
    }
    if (d < feature.plug_radius) {
        const plug = 1 - smoothstep(0, feature.plug_radius, d);
        sample.height += feature.plug_height * plug;
    }
}

fn applyRadialRidges(seed: u64, feature: TerrainRecipeFeature, x: f32, z: f32, sample: *TerrainSample) void {
    const dx = x - feature.center_x;
    const dz = z - feature.center_z;
    const d = @sqrt(dx * dx + dz * dz);
    if (d > feature.radius_x) return;
    const angle = std.math.atan2(dz, dx);
    var best: f32 = 0;
    var valley: f32 = 0;
    const count = @max(feature.count, 1);
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const base = (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(count))) * std.math.tau;
        const walk = randomWalkAngle(seed + i * 131, x, z, d, 0.42);
        const bend = 0.2 * valueNoise(seed + i * 131, d, d * 0.37, 900) + walk;
        const jitter = (hash1(seed + i * 31) - 0.5) * 0.28 + bend;
        const da = angularDistance(angle, base + jitter);
        const ridge_width = (feature.width * (0.75 + 0.45 * hash1(seed + i * 37))) / @max(d, 260);
        best = @max(best, @exp(-(da * da) / @max(0.0001, ridge_width * ridge_width)));
        const between = angularDistance(angle, base + std.math.pi / @as(f32, @floatFromInt(count)) + jitter * 0.4);
        valley = @max(valley, @exp(-(between * between) / @max(0.0001, (ridge_width * 0.62) * (ridge_width * 0.62))));
    }
    const fade = smoothstep(feature.radius_x * 0.08, feature.radius_x * 0.24, d) * (1 - smoothstep(feature.radius_x * 0.74, feature.radius_x, d));
    const erode = 0.72 + 0.28 * fbm(seed + 9, x, z, 360, 4);
    sample.height += feature.height * best * fade * erode;
    sample.height -= feature.height * 0.36 * feature.erosion * valley * fade;
    sample.slope_hint += best * fade * 0.65;
}

fn applyAshlands(seed: u64, feature: TerrainRecipeFeature, x: f32, z: f32, sample: *TerrainSample) void {
    const m = ellipseMask(feature, x, z);
    if (m <= 0) return;
    const gully_count: u32 = @max(18, @as(u32, @intFromFloat(feature.gully_density * 42)));
    const gullies = branchingLines(seed + 11, x, z, gully_count, feature.center_x, feature.center_z, feature.radius_x);
    const shelves = terracedNoise(seed + 12, x, z, 580, 7);
    const rough = fbm(seed + 13, x, z, 210, 4);
    sample.height += feature.height * m * (0.22 + 0.22 * rough);
    sample.height -= feature.gully_density * 118 * m * gullies;
    sample.height += feature.basalt_roughness * 105 * m * shelves;
    sample.slope_hint += m * (gullies + rough) * 0.25;
}

fn applyMarshDelta(seed: u64, feature: TerrainRecipeFeature, x: f32, z: f32, sample: *TerrainSample) void {
    const m = ellipseMask(feature, x, z);
    if (m <= 0) return;
    const channels = branchingLines(seed, x, z, feature.channel_count, feature.center_x, feature.center_z, feature.radius_x);
    const flat = feature.height + 6 * valueNoise(seed + 21, x, z, 420);
    sample.height = lerp(sample.height, flat, m * 0.92);
    sample.height -= feature.channel_depth * m * channels;
}

fn applyBrokenHighlands(seed: u64, feature: TerrainRecipeFeature, x: f32, z: f32, sample: *TerrainSample) void {
    const m = ellipseMask(feature, x, z);
    if (m <= 0) return;
    sample.height += feature.height * m * (0.38 + 0.36 * fbm(seed + 31, x, z, 760, 4));
    var i: u32 = 0;
    while (i < feature.craters) : (i += 1) {
        const cx = feature.center_x + (hash1(seed + i * 17) - 0.5) * feature.radius_x * 1.1;
        const cz = feature.center_z + (hash1(seed + i * 23) - 0.5) * feature.radius_z * 1.1;
        const r = 180 + hash1(seed + i * 29) * 360;
        const d = distance(x, z, cx, cz);
        const rim = ring(d, r * 0.48, r);
        sample.height += 120 * rim * (0.65 + 0.35 * feature.weathering);
        sample.height -= 145 * (1 - smoothstep(0, r * 0.7, d)) * (0.35 + 0.45 * feature.weathering);
        sample.slope_hint += rim * 0.4;
    }
}

fn applyFjordHorns(seed: u64, feature: TerrainRecipeFeature, x: f32, z: f32, sample: *TerrainSample) void {
    const m = ellipseMask(feature, x, z);
    if (m <= 0) return;
    const ridges = branchingLines(seed + 41, x, z, feature.horn_count, feature.center_x, feature.center_z, feature.radius_x);
    const bite = branchingLines(seed + 42, x, z, feature.horn_count + 5, feature.center_x + 380, feature.center_z - 240, feature.radius_x * 1.12);
    sample.height += feature.height * m * (0.24 + 0.76 * ridges);
    sample.height += feature.cliff_height * m * smoothstep(0.38, 0.92, ridges);
    sample.height -= feature.cliff_height * 0.55 * m * bite * (1 - ridges * 0.5);
    sample.slope_hint += m * ridges * 0.6;
}

fn applyChalkPlateau(seed: u64, feature: TerrainRecipeFeature, x: f32, z: f32, sample: *TerrainSample) void {
    const m = ellipseMask(feature, x, z);
    if (m <= 0) return;
    const d = normalizedEllipseDistance(feature, x, z);
    const terrace_count = @max(feature.terraces, 1);
    const terrace_noise = valueNoise(seed + 52, x, z, 680) * 0.08;
    const terrace = @floor(((1 - d) + terrace_noise) * @as(f32, @floatFromInt(terrace_count))) / @as(f32, @floatFromInt(terrace_count));
    sample.height = @max(sample.height, feature.plateau_height * smoothstep(0.0, 0.55, m) + terrace * 118 + 24 * fbm(seed + 53, x, z, 330, 3));
    const apron_d = distance(x, z, feature.center_x, feature.center_z);
    if (apron_d < feature.radius_x + feature.badland_apron and apron_d > feature.radius_x * 0.72) {
        sample.height -= 92 * smoothstep(feature.radius_x * 0.72, feature.radius_x + feature.badland_apron, apron_d) * @abs(fbm(seed + 51, x, z, 210, 4));
    }
    sample.slope_hint += m * 0.25;
}

fn applyDryBasins(seed: u64, feature: TerrainRecipeFeature, x: f32, z: f32, sample: *TerrainSample) void {
    const m = ellipseMask(feature, x, z);
    if (m <= 0) return;
    const washes = branchingLines(seed + 61, x, z, feature.wash_count, feature.center_x, feature.center_z, feature.radius_x);
    sample.height = lerp(sample.height, feature.height + 40 * valueNoise(seed + 62, x, z, 560), m * 0.55);
    sample.height -= 46 * washes * m;
    sample.height += 16 * feature.crack_density * valueNoise(seed + 63, x, z, 90) * m;
}

fn applyHookCoast(seed: u64, feature: TerrainRecipeFeature, x: f32, z: f32, sample: *TerrainSample) void {
    const m = ellipseMask(feature, x, z);
    if (m <= 0) return;
    const hooks = branchingLines(seed + 71, x, z, feature.hooks, feature.center_x, feature.center_z, feature.radius_x);
    sample.height = lerp(sample.height, feature.height + hooks * 75, m * 0.35);
    const beach = smoothstep(0.15, 0.55, @abs(valueNoise(seed + 72, x, z, 260)));
    sample.height = lerp(sample.height, @max(sample.height, 22), m * beach * 0.18);
}

fn applyVolcanicOutlier(job: TerrainRecipeJob, feature: TerrainRecipeFeature, x: f32, z: f32, sample: *TerrainSample) void {
    const m = ellipseMask(feature, x, z);
    if (m <= 0) return;
    sample.land = true;
    sample.shore = @max(sample.shore, smoothstep(0.05, 0.25, m));
    sample.height = @max(sample.height, job.sea_level + 50 + feature.rim_height * m);
    const d = distance(x, z, feature.center_x, feature.center_z);
    sample.height += feature.rim_height * 0.55 * ring(d, @min(feature.radius_x, feature.radius_z) * 0.28, @min(feature.radius_x, feature.radius_z) * 0.56);
    sample.height = lerp(sample.height, feature.crater_floor, (1 - smoothstep(0, @min(feature.radius_x, feature.radius_z) * 0.26, d)) * 0.65);
}

fn applySeaWall(seed: u64, feature: TerrainRecipeFeature, x: f32, z: f32, sample: *TerrainSample) void {
    if (!sample.land) {
        const broken_floor = 80 * ridgeNoise(seed + 881, x, z, 360, 4) + 46 * fbm(seed + 883, x, z, 910, 3);
        const abyss = feature.bottom_height - 260 * sample.void_depth - broken_floor;
        sample.height = @min(sample.height, abyss);
        return;
    }
    if (sample.shore < 1) {
        const top = @max(feature.cliff_top_min, sample.height);
        sample.height = lerp(feature.bottom_height, top, smoothstep(0, 1, sample.shore));
    }
}

fn applyWorldVoidFeather(job: TerrainRecipeJob, x: f32, z: f32, sample: *TerrainSample) void {
    if (sample.land) return;
    const min_x = @as(f32, @floatFromInt(job.min_x)) * job.cell_size_m;
    const max_x = @as(f32, @floatFromInt(job.max_x + 1)) * job.cell_size_m;
    const min_z = @as(f32, @floatFromInt(job.min_z)) * job.cell_size_m;
    const max_z = @as(f32, @floatFromInt(job.max_z + 1)) * job.cell_size_m;
    const edge_dist = @min(@min(x - min_x, max_x - x), @min(z - min_z, max_z - z));
    const edge_falloff = 1 - smoothstep(job.cell_size_m * 1.0, job.cell_size_m * 7.0, edge_dist);
    const abyss_noise = 0.55 + 0.45 * ridgeNoise(job.seed + 887, x, z, 740, 4);
    sample.void_depth = @max(sample.void_depth, edge_falloff);
    sample.height -= edge_falloff * abyss_noise * 620;
}

fn applyWorldEdgeCarve(job: TerrainRecipeJob, x: f32, z: f32, sample: *TerrainSample) void {
    const min_x = @as(f32, @floatFromInt(job.min_x)) * job.cell_size_m;
    const max_x = @as(f32, @floatFromInt(job.max_x + 1)) * job.cell_size_m;
    const min_z = @as(f32, @floatFromInt(job.min_z)) * job.cell_size_m;
    const max_z = @as(f32, @floatFromInt(job.max_z + 1)) * job.cell_size_m;
    const edge_dist = @min(@min(x - min_x, max_x - x), @min(z - min_z, max_z - z));
    const hard_edge = 1 - smoothstep(job.cell_size_m * 1.25, job.cell_size_m * 3.1, edge_dist);
    const soft_edge = 1 - smoothstep(job.cell_size_m * 3.1, job.cell_size_m * 7.4, edge_dist);
    const ragged = 0.5 + 0.5 * fbm(job.seed + 901, x, z, 920, 4);
    const carve = @max(hard_edge, soft_edge * smoothstep(0.34, 0.78, ragged));
    if (carve <= 0) return;

    if (sample.land and carve > 0.38) {
        sample.land = false;
        sample.shore = 0;
        sample.void_depth = @max(sample.void_depth, carve);
        sample.height = job.ocean_floor - 180 - 520 * carve - 90 * ridgeNoise(job.seed + 903, x, z, 430, 3);
        return;
    }
    if (sample.land) {
        sample.shore *= 1 - carve * 0.75;
        sample.height = lerp(sample.height, job.ocean_floor - 80, carve * 0.55);
    }
}

fn paintLayerForSample(sample: TerrainSample, x: f32, z: f32) usize {
    if (!sample.land) return if (sample.height > -230 and sample.void_depth < 0.38) 7 else 6;
    if (sample.height < 4) return 7;
    if (sample.shore < 0.34 and sample.height < 42) return 4;

    const n1 = valueNoise(0x6d6174, x, z, 520);
    const n2 = fbm(0x7061696e74, x, z, 310, 4);
    const caldera = 1 - smoothstep(900, 1800, distance(x, z, 0, 200));
    const marsh = 1 - smoothstep(0.72, 1.08, ellipseValue(x, z, -3550, 1250, 1550, 1750));
    const southeast = 1 - smoothstep(0.76, 1.12, ellipseValue(x, z, 2850, 2850, 1700, 1550));
    const dry_south = smoothstep(1600, 3900, z) * (1 - smoothstep(5200, 6500, z));
    const north = smoothstep(1800, 3600, -z);
    const steep = sample.slope_hint + ridgeNoise(0x736c6f7065, x, z, 260, 3) * 0.5;

    if (caldera > 0.25) {
        if (sample.height < 32) return 7;
        if (steep > 0.7 or sample.height > 360) return 3;
        return if (n2 > 0.18) 9 else 3;
    }
    if (marsh > 0.2 and sample.height < 62) {
        return if (n1 + marsh > 0.8) 12 else 0;
    }
    if (southeast > 0.18) {
        if (sample.height > 330 or steep > 0.64) return 10;
        return if (n2 > 0.08) 11 else 8;
    }
    if (north > 0.45 and sample.height > 250) {
        return if (steep > 0.48 or n2 > -0.15) 2 else 3;
    }
    if (dry_south > 0.35 and sample.height < 180) {
        return if (n1 > 0.22) 11 else 8;
    }
    if (sample.shore < 0.58 and sample.height < 70) return if (n1 > -0.1) 8 else 7;
    if (steep > 0.82 and sample.height > 80) return 3;
    if (sample.height > 520) return if (n1 > -0.25) 2 else 3;
    if (sample.height > 230) return if (n2 > 0.05) 3 else 0;
    return if (n2 > 0.32) 1 else 0;
}

fn cellAtOffset(job: TerrainRecipeJob, offset: u64) world.cell.CellId {
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

fn distance(x: f32, z: f32, cx: f32, cz: f32) f32 {
    const dx = x - cx;
    const dz = z - cz;
    return @sqrt(dx * dx + dz * dz);
}

fn ellipseMask(feature: TerrainRecipeFeature, x: f32, z: f32) f32 {
    return @max(0, 1 - normalizedEllipseDistance(feature, x, z));
}

fn normalizedEllipseDistance(feature: TerrainRecipeFeature, x: f32, z: f32) f32 {
    return ellipseValue(x, z, feature.center_x, feature.center_z, feature.radius_x, feature.radius_z);
}

fn ellipseValue(x: f32, z: f32, cx: f32, cz: f32, rx: f32, rz: f32) f32 {
    const nx = (x - cx) / @max(1, rx);
    const nz = (z - cz) / @max(1, rz);
    return @sqrt(nx * nx + nz * nz);
}

const WarpedPoint = struct {
    x: f32,
    z: f32,
};

fn warpWorld(seed: u64, x: f32, z: f32) WarpedPoint {
    const broad_x = valueNoise(seed + 501, x, z, 2100) * 190;
    const broad_z = valueNoise(seed + 503, x + 811, z - 421, 2100) * 190;
    const fold_x = valueNoise(seed + 505, x + broad_x, z, 860) * 65;
    const fold_z = valueNoise(seed + 507, x, z + broad_z, 860) * 65;
    return .{ .x = x + broad_x + fold_x, .z = z + broad_z + fold_z };
}

fn applyLandscapeDetail(job: TerrainRecipeJob, x: f32, z: f32, sample: *TerrainSample) void {
    const island_falloff = smoothstep(0.05, 0.85, sample.shore);
    const massif = fbm(job.seed + 801, x, z, 1450, 5);
    const knuckle = ridgeNoise(job.seed + 803, x, z, 410, 4);
    const fine = fbm(job.seed + 805, x, z, 155, 3);
    const drainage = radialDrainage(job.seed + 807, x, z, 0, 200, 24);
    const contour = terracedNoise(job.seed + 809, x, z, 720, 8);
    const cliffiness = std.math.clamp(sample.slope_hint + knuckle * 0.55 + (1 - sample.shore) * 0.35, 0, 1);

    sample.height += island_falloff * (56 * massif + 28 * fine);
    sample.height += island_falloff * cliffiness * 72 * knuckle;
    sample.height += island_falloff * 22 * contour;
    sample.height -= island_falloff * drainage * (46 + 62 * cliffiness);

    if (sample.height > 150 and sample.height < 520) {
        const bench = @round(sample.height / 38) * 38;
        sample.height = lerp(sample.height, bench, 0.08 * cliffiness);
    }
    if (sample.shore < 0.72) {
        const beach_or_cliff = smoothstep(0.18, 0.72, sample.shore);
        sample.height = lerp(sample.height, @max(sample.height, 18 + 32 * beach_or_cliff), 0.18);
    }
}

fn ring(d: f32, inner: f32, outer: f32) f32 {
    return smoothstep(inner * 0.65, inner, d) * (1 - smoothstep(inner, outer, d));
}

fn breachFactor(x: f32, z: f32, feature: TerrainRecipeFeature, d: f32) f32 {
    if (feature.breaches == 0) return 1;
    const angle = std.math.atan2(z - feature.center_z, x - feature.center_x);
    var cut: f32 = 0;
    var i: u32 = 0;
    while (i < feature.breaches) : (i += 1) {
        const a = (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(feature.breaches))) * std.math.tau + 0.18 * @sin(@as(f32, @floatFromInt(i)) * 2.1);
        const da = angularDistance(angle, a);
        cut = @max(cut, @exp(-(da * da) / 0.012) * ring(d, feature.inner_radius * 0.85, feature.outer_radius * 1.05));
    }
    return 1 - cut * 0.75;
}

fn branchingLines(seed: u64, x: f32, z: f32, count: u32, cx: f32, cz: f32, radius: f32) f32 {
    if (count == 0) return 0;
    var best: f32 = 0;
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const angle = (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(count))) * std.math.tau + (hash1(seed + i * 43) - 0.5) * 1.0;
        const px = x - cx;
        const pz = z - cz;
        const raw_along = px * @cos(angle) + pz * @sin(angle);
        if (raw_along < -radius * 0.08 or raw_along > radius * 1.45) continue;
        const walk = randomWalkOffset(seed + i * 211, x, z, raw_along, radius);
        const drift_angle = angle + 0.38 * valueNoise(seed + i * 223, raw_along, walk, 680);
        const along = px * @cos(drift_angle) + pz * @sin(drift_angle);
        if (along < 0 or along > radius * 1.35) continue;
        const across = @abs((-px * @sin(drift_angle) + pz * @cos(drift_angle)) - walk);
        const width = 35 + hash1(seed + i * 47) * 90 + 34 * valueNoise(seed + i * 227, along, across, 430);
        const broken = 0.62 + 0.38 * fbm(seed + i * 229, x, z, 520, 3);
        best = @max(best, broken * @exp(-(across * across) / (2 * width * width)) * (1 - smoothstep(radius * 0.9, radius * 1.35, along)));
    }
    return best;
}

fn radialDrainage(seed: u64, x: f32, z: f32, cx: f32, cz: f32, count: u32) f32 {
    const dx = x - cx;
    const dz = z - cz;
    const d = @sqrt(dx * dx + dz * dz);
    if (d < 280) return 0;
    const angle = std.math.atan2(dz, dx);
    var best: f32 = 0;
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const base = (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(count))) * std.math.tau;
        const bend = 0.32 * valueNoise(seed + i * 71, d, angle * 900, 520) +
            randomWalkAngle(seed + i * 233, x, z, d, 0.36);
        const da = angularDistance(angle, base + bend);
        const width = 0.018 + 0.018 * hash1(seed + i * 73);
        const groove = @exp(-(da * da) / @max(0.0001, width * width));
        const runout = smoothstep(350, 1800, d) * (1 - smoothstep(4200, 5900, d));
        best = @max(best, groove * runout);
    }
    return best;
}

fn randomWalkAngle(seed: u64, x: f32, z: f32, along: f32, strength: f32) f32 {
    const broad = valueNoise(seed + 1, along, x * 0.41 + z * 0.23, 920);
    const mid = valueNoise(seed + 2, along, x - z, 390);
    const fine = valueNoise(seed + 3, x, z, 240);
    return strength * (0.55 * broad + 0.32 * mid + 0.13 * fine);
}

fn randomWalkOffset(seed: u64, x: f32, z: f32, along: f32, radius: f32) f32 {
    const broad = valueNoise(seed + 11, along, x * 0.27 + z * 0.39, 760);
    const mid = valueNoise(seed + 13, along, x - z, 310);
    const fine = valueNoise(seed + 17, x, z, 180);
    const runout = smoothstep(radius * 0.08, radius * 0.36, along) * (1 - smoothstep(radius * 1.02, radius * 1.35, along));
    return runout * (145 * broad + 72 * mid + 24 * fine);
}

fn offshoreIslet(seed: u64, x: f32, z: f32) f32 {
    const grid: f32 = 520;
    const ix: i32 = @intFromFloat(@floor(x / grid));
    const iz: i32 = @intFromFloat(@floor(z / grid));
    var out: f32 = 0;
    var oz: i32 = -1;
    while (oz <= 1) : (oz += 1) {
        var ox: i32 = -1;
        while (ox <= 1) : (ox += 1) {
            const gx = ix + ox;
            const gz = iz + oz;
            const chance = hash2(seed + 91, gx, gz);
            if (chance < 0.78) continue;
            const cx = (@as(f32, @floatFromInt(gx)) + hash2(seed + 93, gx, gz)) * grid;
            const cz = (@as(f32, @floatFromInt(gz)) + hash2(seed + 95, gx, gz)) * grid;
            const r = 45 + hash2(seed + 97, gx, gz) * 150;
            const d = distance(x, z, cx, cz);
            out = @max(out, 85 * (1 - smoothstep(0, r, d)));
        }
    }
    return out;
}

fn angularDistance(a: f32, b: f32) f32 {
    var d = @mod(a - b + std.math.pi, std.math.tau) - std.math.pi;
    if (d < -std.math.pi) d += std.math.tau;
    return @abs(d);
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
    return lerp(lerp(a, b, sx), lerp(c, d, sx), sz) * 2 - 1;
}

fn fbm(seed: u64, x: f32, z: f32, scale: f32, octaves: u32) f32 {
    var total: f32 = 0;
    var amp: f32 = 0.5;
    var freq: f32 = 1;
    var norm: f32 = 0;
    var i: u32 = 0;
    while (i < octaves) : (i += 1) {
        total += valueNoise(seed + i * 101, x * freq, z * freq, scale) * amp;
        norm += amp;
        amp *= 0.5;
        freq *= 2.03;
    }
    return if (norm > 0) total / norm else 0;
}

fn ridgeNoise(seed: u64, x: f32, z: f32, scale: f32, octaves: u32) f32 {
    var total: f32 = 0;
    var amp: f32 = 0.55;
    var freq: f32 = 1;
    var norm: f32 = 0;
    var i: u32 = 0;
    while (i < octaves) : (i += 1) {
        const n = valueNoise(seed + i * 109, x * freq, z * freq, scale);
        total += (1 - @abs(n)) * amp;
        norm += amp;
        amp *= 0.52;
        freq *= 2.17;
    }
    return if (norm > 0) total / norm else 0;
}

fn terracedNoise(seed: u64, x: f32, z: f32, scale: f32, steps: u32) f32 {
    const n = (fbm(seed, x, z, scale, 4) + 1) * 0.5;
    const step_count = @as(f32, @floatFromInt(@max(steps, 1)));
    const stepped = @floor(n * step_count) / step_count;
    return (lerp(n, stepped, 0.68) * 2) - 1;
}

fn hash1(seed: u64) f32 {
    var h = seed;
    h ^= h >> 30;
    h *%= 0xbf58476d1ce4e5b9;
    h ^= h >> 27;
    h *%= 0x94d049bb133111eb;
    h ^= h >> 31;
    return @as(f32, @floatFromInt(h & 0xffffff)) / @as(f32, @floatFromInt(0xffffff));
}

fn hash2(seed: u64, x: i32, z: i32) f32 {
    const h = seed ^ @as(u64, @bitCast(@as(i64, x) *% 374761393)) ^ @as(u64, @bitCast(@as(i64, z) *% 668265263));
    return hash1(h);
}

fn smoothstep(edge0: f32, edge1: f32, x: f32) f32 {
    const t = std.math.clamp((x - edge0) / @max(0.0001, edge1 - edge0), 0, 1);
    return t * t * (3 - 2 * t);
}

fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * std.math.clamp(t, 0, 1);
}

fn quantizeHeight(value: f32) f32 {
    return @round(value * 10) / 10;
}
