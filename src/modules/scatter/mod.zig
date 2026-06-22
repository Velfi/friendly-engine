const std = @import("std");
const framework = @import("../../framework/mod.zig");
const world = @import("../../world/mod.zig");
const types = @import("types.zig");
const kdl = @import("kdl");
const layer_kdl = @import("../layer_kdl.zig");

const storage = @import("storage.zig");
pub const parseCellId = types.parseCellId;
pub const authoring = @import("authoring.zig");
pub const runtime = @import("runtime.zig");

pub const module_name = "gem.scatter";
const layer_name = "world.layer.scatter";
const scatter_layer_file = "layers/scatter.kdl";
const tex_size: usize = 128 * 128 * 4;

pub const ScatterDoc = types.ScatterDoc;
pub const ScatterRule = types.ScatterRule;
pub const DensityMask = types.DensityMask;
pub const ExclusionZone = types.ExclusionZone;
pub const BiomeRule = types.BiomeRule;
pub const RuntimeControls = types.RuntimeControls;
pub const ClusterInstance = types.ClusterInstance;

pub fn register(registry: anytype) !void {
    try registry.registerWorldCompilerLayer(.{
        .name = layer_name,
        .affected_cells = affectedCells,
        .compile_cell = compileCell,
    });
}

pub fn start(engine_world: *framework.World) !void {
    try engine_world.notifications.publish("gem.scatter.started", "{}");
}

pub fn stop(engine_world: *framework.World) !void {
    try engine_world.notifications.publish("gem.scatter.stopped", "{}");
}

fn affectedCells(
    _: ?*anyopaque,
    compile_ctx: *const world.compiler.layer.CompileContext,
    allocator: std.mem.Allocator,
) ![]world.cell.CellId {
    var doc = try storage.loadDoc(allocator, compile_ctx);
    defer doc.deinit();
    var cells = std.ArrayList(world.cell.CellId).empty;
    defer cells.deinit(allocator);
    var lookup = std.AutoHashMap(world.cell.CellId, void).init(allocator);
    defer lookup.deinit();

    for (doc.value.rules) |rule| {
        const id = try types.parseCellId(rule.cell);
        if (lookup.contains(id)) continue;
        try lookup.put(id, {});
        try cells.append(allocator, id);
    }
    return cells.toOwnedSlice(allocator);
}

pub fn compileCell(
    _: ?*anyopaque,
    compile_ctx: *const world.compiler.layer.CompileContext,
    id: world.cell.CellId,
    allocator: std.mem.Allocator,
) !world.compiler.layer.CellLayerOutput {
    var doc = try storage.loadDoc(allocator, compile_ctx);
    defer doc.deinit();

    var meshes = std.ArrayList(world.cell.RenderMesh).empty;
    var blobs = std.ArrayList(world.cell.CellBlob).empty;
    var instances = std.ArrayList(ClusterInstance).empty;
    defer instances.deinit(allocator);
    errdefer {
        for (meshes.items) |*mesh| mesh.deinit(allocator);
        meshes.deinit(allocator);
        for (blobs.items) |*blob| blob.deinit(allocator);
        blobs.deinit(allocator);
    }

    const bounds = world.cell.boundsForCell(id, compile_ctx.loaded_manifest.cell_size_m, world.cell.default_cell_height_m);
    var prototypes = std.StringHashMap(void).init(allocator);
    defer prototypes.deinit();
    var used_mask_override = false;

    for (doc.value.rules) |rule| {
        const rule_cell = try types.parseCellId(rule.cell);
        if (!rule_cell.eql(id)) continue;
        const biome_rule = try resolveBiomeRule(doc.value.biome_rules, rule);
        const compiled_rule = try types.compileRule(rule, biome_rule);
        if (!prototypes.contains(rule.prototype)) {
            try prototypes.put(rule.prototype, {});
            try meshes.append(allocator, try buildPrototypeMesh(allocator, rule.prototype));
        }

        const mask = try findMask(doc.value.density_masks, id);
        const zones = try findZones(allocator, doc.value.exclusions, id);
        defer allocator.free(zones);
        if (mask != null) used_mask_override = true;
        try generateRuleInstances(allocator, &instances, bounds, compiled_rule, mask, zones, doc.value.runtime_controls);
    }

    if (instances.items.len == 0) return .{};
    const cluster_meta = try runtime.buildClusterMetadata(allocator, id, instances.items, doc.value.rules, doc.value.runtime_controls);
    try world.compiler.layer.appendBlobJson(allocator, &blobs, "scatter.clusters", .{
        .cell = .{ id.x, id.y, id.z },
        .instances = instances.items,
    });
    try world.compiler.layer.appendBlobJson(allocator, &blobs, "scatter.cluster_meta", cluster_meta);
    try world.compiler.layer.appendBlobJson(allocator, &blobs, "scatter.mask_override", .{
        .cell = .{ id.x, id.y, id.z },
        .enabled = used_mask_override,
    });

    return .{
        .render_meshes = try meshes.toOwnedSlice(allocator),
        .blobs = try blobs.toOwnedSlice(allocator),
    };
}

fn generateRuleInstances(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(ClusterInstance),
    bounds: world.cell.CellBounds,
    rule: types.CompiledRule,
    mask: ?DensityMask,
    zones: []const ExclusionZone,
    controls: RuntimeControls,
) !void {
    var z = bounds.min.z;
    while (z <= bounds.max.z) : (z += rule.spacing) {
        var x = bounds.min.x;
        while (x <= bounds.max.x) : (x += rule.spacing) {
            if (!(try runtime.enforceClusterLimit(out.items.len, controls))) return;
            if (isInsideExclusionZones(x, z, zones)) continue;
            const slope = pseudoSlope(x, z, rule.seed);
            if (slope < rule.slope_min or slope > rule.slope_max) continue;

            var density = rule.density;
            if (mask) |m| {
                const sample = maskDensity(m, bounds, x, z);
                density = @as(f32, @floatFromInt(sample)) / 255.0;
            }
            if (density <= 0) continue;

            const selector = randomUnit(x, z, rule.seed);
            if (selector > density) continue;
            const scale = rule.scale_min + (rule.scale_max - rule.scale_min) * randomUnit(z, x, rule.seed + 99);
            try out.append(allocator, .{
                .prototype = rule.prototype,
                .position = .{ x, bounds.min.y, z },
                .scale = scale,
            });
        }
    }
}

fn buildPrototypeMesh(allocator: std.mem.Allocator, prototype: []const u8) !world.cell.RenderMesh {
    const verts = try allocator.dupe(world.cell.RenderVertex, &.{
        .{ .position = .{ .x = -0.5, .y = 0, .z = 0 }, .normal = .{ .x = 0, .y = 0, .z = 1 }, .uv = .{ .x = 0, .y = 0 } },
        .{ .position = .{ .x = 0.5, .y = 0, .z = 0 }, .normal = .{ .x = 0, .y = 0, .z = 1 }, .uv = .{ .x = 1, .y = 0 } },
        .{ .position = .{ .x = 0.5, .y = 1.2, .z = 0 }, .normal = .{ .x = 0, .y = 0, .z = 1 }, .uv = .{ .x = 1, .y = 1 } },
        .{ .position = .{ .x = -0.5, .y = 1.2, .z = 0 }, .normal = .{ .x = 0, .y = 0, .z = 1 }, .uv = .{ .x = 0, .y = 1 } },
    });
    errdefer allocator.free(verts);
    const indices = try allocator.dupe(u32, &.{ 0, 1, 2, 0, 2, 3 });
    errdefer allocator.free(indices);
    const texture = try allocator.alloc(u8, tex_size);
    @memset(texture, 135);
    errdefer allocator.free(texture);
    return .{
        .name = try allocator.dupe(u8, prototype),
        .vertices = verts,
        .indices = indices,
        .texture = texture,
        .base_color = .{ .r = 120, .g = 155, .b = 110, .a = 255 },
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
    };
}

fn findMask(masks: []const DensityMask, id: world.cell.CellId) !?DensityMask {
    for (masks) |mask| {
        const mask_cell = try types.parseCellId(mask.cell);
        if (mask_cell.eql(id)) return mask;
    }
    return null;
}

fn findZones(
    allocator: std.mem.Allocator,
    exclusions: []const ExclusionZone,
    id: world.cell.CellId,
) ![]ExclusionZone {
    var count: usize = 0;
    for (exclusions) |zone| {
        const zone_cell = try types.parseCellId(zone.cell);
        if (zone_cell.eql(id)) count += 1;
    }
    var zones = try allocator.alloc(ExclusionZone, count);
    errdefer allocator.free(zones);
    var index: usize = 0;
    for (exclusions) |zone| {
        const zone_cell = try types.parseCellId(zone.cell);
        if (!zone_cell.eql(id)) continue;
        zones[index] = zone;
        index += 1;
    }
    return zones;
}

pub fn resolveBiomeRule(rules: []const BiomeRule, rule: ScatterRule) !?BiomeRule {
    const biome_rule = types.findBiomeRule(rules, rule.biome);
    if (biome_rule != null) return biome_rule;
    if (std.mem.eql(u8, rule.biome, "default")) return null;
    return error.MissingScatterBiomeRule;
}

fn isInsideExclusionZones(x: f32, z: f32, zones: []const ExclusionZone) bool {
    for (zones) |zone| {
        if (x >= zone.min[0] and x <= zone.max[0] and z >= zone.min[2] and z <= zone.max[2]) return true;
    }
    return false;
}

fn maskDensity(mask: DensityMask, bounds: world.cell.CellBounds, x: f32, z: f32) u8 {
    const size: usize = @intCast(mask.size);
    const u = @max(0.0, @min(0.9999, (x - bounds.min.x) / @max(0.01, bounds.max.x - bounds.min.x)));
    const v = @max(0.0, @min(0.9999, (z - bounds.min.z) / @max(0.01, bounds.max.z - bounds.min.z)));
    const sx: usize = @intFromFloat(u * @as(f32, @floatFromInt(size)));
    const sz: usize = @intFromFloat(v * @as(f32, @floatFromInt(size)));
    return mask.values[sz * size + sx];
}

fn pseudoSlope(x: f32, z: f32, seed: u32) f32 {
    return randomUnit(x, z, seed) * 45.0;
}

fn randomUnit(a: f32, b: f32, seed: u32) f32 {
    const h = std.hash.Wyhash.hash(seed, std.mem.asBytes(&[_]f32{ a, b }));
    return @as(f32, @floatFromInt(h & 0xffff)) / 65535.0;
}

comptime {
    _ = @import("mod_tests.zig");
}
comptime {
    _ = @import("mod_tests.zig");
}
