const std = @import("std");
const core = @import("../../core/mod.zig");
const framework = @import("../../framework/mod.zig");
const world = @import("../../world/mod.zig");
const terrain = @import("../terrain/mod.zig");

pub const types = @import("types.zig");
pub const storage = @import("storage.zig");
pub const runtime = @import("runtime.zig");

pub const module_name = "gem.grass";
const scatter = @import("../scatter/mod.zig");
const physics3d = @import("../physics3d/mod.zig");

pub const dependencies = [_][]const u8{ terrain.module_name, scatter.module_name, physics3d.module_name };
const layer_name = "world.layer.grass";

pub fn register(registry: anytype) !void {
    try registry.registerWorldCompilerLayer(.{ .name = layer_name, .affected_cells = affectedCells, .compile_cell = compileCell });
}

pub fn start(engine_world: *framework.World) !void {
    try engine_world.notifications.publish("gem.grass.started", "{}");
}

pub fn stop(engine_world: *framework.World) !void {
    try engine_world.notifications.publish("gem.grass.stopped", "{}");
}

fn affectedCells(_: ?*anyopaque, compile_ctx: *const world.compiler.layer.CompileContext, allocator: std.mem.Allocator) ![]world.cell.CellId {
    var doc = try storage.loadDoc(allocator, compile_ctx);
    defer doc.deinit();
    var cells = std.ArrayList(world.cell.CellId).empty;
    defer cells.deinit(allocator);
    var lookup = std.AutoHashMap(world.cell.CellId, void).init(allocator);
    defer lookup.deinit();
    for (doc.value.patches) |patch| {
        const id = try types.parseCellId(patch.cell);
        if (lookup.contains(id)) continue;
        try lookup.put(id, {});
        try cells.append(allocator, id);
    }
    return cells.toOwnedSlice(allocator);
}

pub fn compileCell(_: ?*anyopaque, compile_ctx: *const world.compiler.layer.CompileContext, id: world.cell.CellId, allocator: std.mem.Allocator) !world.compiler.layer.CellLayerOutput {
    var doc = try storage.loadDoc(allocator, compile_ctx);
    defer doc.deinit();
    const maybe_terrain_doc = try terrain.authoring.loadCell(allocator, compile_ctx.io, compile_ctx.project_path, compile_ctx.manifest_path, id);
    if (maybe_terrain_doc == null) return .{};
    var terrain_doc = maybe_terrain_doc.?;
    defer terrain_doc.deinit();
    if (terrain_doc.tiles.items.len != 1) return error.InvalidTerrainDocument;
    const tile = terrain_doc.tiles.items[0];
    const bounds = world.cell.boundsForCell(id, compile_ctx.loaded_manifest.cell_size_m, world.cell.default_cell_height_m);

    var instances = std.ArrayList(types.GrassInstance).empty;
    defer {
        for (instances.items) |instance| allocator.free(instance.material);
        instances.deinit(allocator);
    }
    var controls: ?types.ClusterControls = null;

    for (doc.value.patches) |patch| {
        const patch_cell = try types.parseCellId(patch.cell);
        if (!patch_cell.eql(id)) continue;
        if (clusterLimitReached(instances.items.len)) break;
        try generatePatch(allocator, &instances, bounds, tile, patch);
        controls = .{
            .cull_distance_m = patch.cull_distance_m,
            .fade_distance_m = patch.fade_distance_m,
            .wind_direction_deg = doc.value.global_wind.direction_deg,
            .wind_speed_mps = doc.value.global_wind.speed_mps,
            .wind_strength = patch.wind_strength,
            .bend_strength = patch.bend_strength,
            .stiffness = patch.stiffness,
        };
    }
    if (instances.items.len == 0) return .{};

    var blobs = std.ArrayList(world.cell.CellBlob).empty;
    errdefer {
        for (blobs.items) |*blob| blob.deinit(allocator);
        blobs.deinit(allocator);
    }
    const meta = try runtime.buildClusterMetadata(allocator, id, instances.items, controls.?);
    try world.compiler.layer.appendBlobJson(allocator, &blobs, "grass.clusters", .{ .cell = .{ id.x, id.y, id.z }, .instances = instances.items });
    try world.compiler.layer.appendBlobJson(allocator, &blobs, "grass.cluster_meta", meta);
    return .{ .blobs = try blobs.toOwnedSlice(allocator) };
}

fn generatePatch(allocator: std.mem.Allocator, out: *std.ArrayList(types.GrassInstance), bounds: world.cell.CellBounds, tile: terrain.authoring.OwnedTerrainTile, patch: types.GrassPatch) !void {
    var z = bounds.min.z + patch.spacing * 0.5;
    while (z < bounds.max.z) : (z += patch.spacing) {
        var x = bounds.min.x + patch.spacing * 0.5;
        while (x < bounds.max.x) : (x += patch.spacing) {
            if (clusterLimitReached(out.items.len)) return;
            if (randomUnit(x, z, patch.seed) > patch.density) continue;
            const sample = try sampleTerrain(bounds, tile, x, z);
            if (!types.materialAllowed(patch, sample.material)) continue;
            const height = lerp(patch.height_min, patch.height_max, randomUnit(z, x, patch.seed + 17));
            const width = lerp(patch.width_min, patch.width_max, randomUnit(x + 3.7, z - 2.1, patch.seed + 29));
            const yaw = randomUnit(x, z, patch.seed + 41) * std.math.tau;
            const phase = randomUnit(z, x, patch.seed + 53) * std.math.tau;
            try out.append(allocator, .{
                .position = .{ x, sample.height, z },
                .normal = .{ sample.normal.x, sample.normal.y, sample.normal.z },
                .material = try allocator.dupe(u8, sample.material),
                .color = types.stylizedGrassColor(sample.material, sample.color),
                .height = height,
                .width = width,
                .yaw = yaw,
                .phase = phase,
                .variant = @intFromFloat(@floor(randomUnit(x, z, patch.seed + 71) * 4.0)),
            });
        }
    }
}

const TerrainSample = struct {
    height: f32,
    normal: core.math.Vec3f,
    material: []const u8,
    color: [4]u8,
};

fn sampleTerrain(bounds: world.cell.CellBounds, tile: terrain.authoring.OwnedTerrainTile, x: f32, z: f32) !TerrainSample {
    const u = std.math.clamp((x - bounds.min.x) / @max(0.01, bounds.max.x - bounds.min.x), 0.0, 1.0);
    const v = std.math.clamp((z - bounds.min.z) / @max(0.01, bounds.max.z - bounds.min.z), 0.0, 1.0);
    const height = sampleHeight(tile.size, tile.heights, u, v);
    const eps = 1.0 / @as(f32, @floatFromInt(@max(tile.size, 2) - 1));
    const hx0 = sampleHeight(tile.size, tile.heights, std.math.clamp(u - eps, 0, 1), v);
    const hx1 = sampleHeight(tile.size, tile.heights, std.math.clamp(u + eps, 0, 1), v);
    const hz0 = sampleHeight(tile.size, tile.heights, u, std.math.clamp(v - eps, 0, 1));
    const hz1 = sampleHeight(tile.size, tile.heights, u, std.math.clamp(v + eps, 0, 1));
    const normal = core.math.Vec3f.normalized(.{ .x = hx0 - hx1, .y = 2.0, .z = hz0 - hz1 });
    const layer = dominantLayer(tile.splat_size, tile.paint_layers.len, tile.splat, u, v);
    return .{ .height = height, .normal = normal, .material = tile.paint_layers[layer], .color = tile.paint_colors[layer] };
}

fn sampleHeight(size_u32: u32, heights: []const f32, u: f32, v: f32) f32 {
    const size: usize = @intCast(size_u32);
    const sx = std.math.clamp(u * @as(f32, @floatFromInt(size - 1)), 0.0, @as(f32, @floatFromInt(size - 1)));
    const sz = std.math.clamp(v * @as(f32, @floatFromInt(size - 1)), 0.0, @as(f32, @floatFromInt(size - 1)));
    const x0: usize = @intFromFloat(@floor(sx));
    const z0: usize = @intFromFloat(@floor(sz));
    const x1 = @min(size - 1, x0 + 1);
    const z1 = @min(size - 1, z0 + 1);
    const tx = sx - @as(f32, @floatFromInt(x0));
    const tz = sz - @as(f32, @floatFromInt(z0));
    const a = heights[z0 * size + x0] + (heights[z0 * size + x1] - heights[z0 * size + x0]) * tx;
    const b = heights[z1 * size + x0] + (heights[z1 * size + x1] - heights[z1 * size + x0]) * tx;
    return a + (b - a) * tz;
}

fn dominantLayer(splat_size_u32: u32, layer_count: usize, splat: []const u8, u: f32, v: f32) usize {
    const size: usize = @intCast(splat_size_u32);
    const x: usize = @intFromFloat(std.math.clamp(u, 0.0, 0.9999) * @as(f32, @floatFromInt(size)));
    const z: usize = @intFromFloat(std.math.clamp(v, 0.0, 0.9999) * @as(f32, @floatFromInt(size)));
    const base = (z * size + x) * layer_count;
    var best: usize = 0;
    for (1..layer_count) |layer| {
        if (splat[base + layer] > splat[base + best]) best = layer;
    }
    return best;
}

fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}

pub fn clusterLimitReached(count: usize) bool {
    return count >= types.max_instances_per_cell;
}

fn randomUnit(a: f32, b: f32, seed: u32) f32 {
    const h = std.hash.Wyhash.hash(seed, std.mem.asBytes(&[_]f32{ a, b }));
    return @as(f32, @floatFromInt(h & 0xffff)) / 65535.0;
}

comptime {
    _ = @import("mod_tests.zig");
}
