const std = @import("std");
const core = @import("../../core/mod.zig");
const world = @import("../../world/mod.zig");
const types = @import("types.zig");

pub const GrassCull = struct {
    cull_distance_m: f32,
    fade_distance_m: f32,
};

pub const Decoded = struct {
    cluster_count: usize,
    meta: ?types.ClusterMetadata,
    instances: []types.GrassInstance,

    pub fn deinit(self: *Decoded, allocator: std.mem.Allocator) void {
        for (self.instances) |instance| allocator.free(instance.material);
        allocator.free(self.instances);
        self.instances = &.{};
        self.meta = null;
        self.cluster_count = 0;
    }
};

pub fn buildClusterMetadata(
    allocator: std.mem.Allocator,
    id: world.cell.CellId,
    instances: []const types.GrassInstance,
    controls: types.ClusterControls,
) !types.ClusterMetadata {
    var materials = std.StringHashMap(void).init(allocator);
    defer materials.deinit();
    for (instances) |instance| try materials.put(instance.material, {});
    return .{
        .cell = .{ id.x, id.y, id.z },
        .instance_count = instances.len,
        .material_count = materials.count(),
        .controls = controls,
    };
}

pub fn decode(allocator: std.mem.Allocator, blobs: []const world.cell.CellBlob) !Decoded {
    const MetaBlob = struct {
        cell: []const i32,
        instance_count: usize,
        material_count: usize,
        controls: types.ClusterControls,
    };
    const ClusterBlob = struct {
        cell: []const i32 = &.{},
        instances: []const struct {
            position: []const f32,
            normal: []const f32,
            material: []const u8,
            color: []const u8,
            height: f32,
            width: f32,
            yaw: f32,
            phase: f32,
            variant: u32,
        } = &.{},
    };

    var cluster_count: usize = 0;
    var meta: ?types.ClusterMetadata = null;
    var expected_count: ?usize = null;
    for (blobs) |blob| {
        if (!std.mem.eql(u8, blob.kind, "grass.cluster_meta")) continue;
        var parsed = try std.json.parseFromSlice(MetaBlob, allocator, blob.payload, .{ .allocate = .alloc_always });
        defer parsed.deinit();
        if (parsed.value.cell.len != 3) return error.InvalidGrassClusterMetadata;
        expected_count = parsed.value.instance_count;
        meta = .{
            .cell = .{ parsed.value.cell[0], parsed.value.cell[1], parsed.value.cell[2] },
            .instance_count = parsed.value.instance_count,
            .material_count = parsed.value.material_count,
            .controls = parsed.value.controls,
        };
        cluster_count += 1;
    }

    var instances = std.ArrayList(types.GrassInstance).empty;
    errdefer {
        for (instances.items) |instance| allocator.free(instance.material);
        instances.deinit(allocator);
    }
    for (blobs) |blob| {
        if (!std.mem.eql(u8, blob.kind, "grass.clusters")) continue;
        var parsed = try std.json.parseFromSlice(ClusterBlob, allocator, blob.payload, .{ .allocate = .alloc_always });
        defer parsed.deinit();
        if (expected_count) |expected| if (expected != parsed.value.instances.len) return error.InvalidGrassClusterMetadata;
        for (parsed.value.instances) |entry| {
            if (entry.position.len != 3 or entry.normal.len != 3 or entry.color.len != 4) return error.InvalidGrassClusterInstance;
            if (!std.math.isFinite(entry.height) or !std.math.isFinite(entry.width) or entry.height <= 0 or entry.width <= 0) return error.InvalidGrassClusterInstance;
            try instances.append(allocator, .{
                .position = .{ entry.position[0], entry.position[1], entry.position[2] },
                .normal = .{ entry.normal[0], entry.normal[1], entry.normal[2] },
                .material = try allocator.dupe(u8, entry.material),
                .color = .{ entry.color[0], entry.color[1], entry.color[2], entry.color[3] },
                .height = entry.height,
                .width = entry.width,
                .yaw = entry.yaw,
                .phase = entry.phase,
                .variant = entry.variant,
            });
        }
    }

    return .{ .cluster_count = cluster_count, .meta = meta, .instances = try instances.toOwnedSlice(allocator) };
}

pub fn batchFadeFactor(cull: GrassCull, camera: core.math.Vec3f, center: core.math.Vec3f) ?f32 {
    const dx = camera.x - center.x;
    const dy = camera.y - center.y;
    const dz = camera.z - center.z;
    const dist = @sqrt(dx * dx + dy * dy + dz * dz);
    if (dist >= cull.cull_distance_m) return null;
    const fade_start = @max(0.0, cull.cull_distance_m - cull.fade_distance_m);
    if (dist <= fade_start or cull.fade_distance_m <= 0.001) return 1.0;
    return std.math.clamp((cull.cull_distance_m - dist) / cull.fade_distance_m, 0.0, 1.0);
}

pub fn nearestInfluencers(
    allocator: std.mem.Allocator,
    camera: core.math.Vec3f,
    influencers: []const types.GrassInfluencer,
) ![]types.GrassInfluencer {
    for (influencers) |influencer| try types.validateInfluencer(influencer);
    var copy = try allocator.dupe(types.GrassInfluencer, influencers);
    errdefer allocator.free(copy);
    std.mem.sort(types.GrassInfluencer, copy, camera, struct {
        fn lessThan(cam: core.math.Vec3f, a: types.GrassInfluencer, b: types.GrassInfluencer) bool {
            return distSq(cam, a) < distSq(cam, b);
        }
        fn distSq(cam: core.math.Vec3f, value: types.GrassInfluencer) f32 {
            const dx = cam.x - value.position[0];
            const dy = cam.y - value.position[1];
            const dz = cam.z - value.position[2];
            return dx * dx + dy * dy + dz * dz;
        }
    }.lessThan);
    const count = @min(copy.len, types.max_influencers);
    const out = try allocator.dupe(types.GrassInfluencer, copy[0..count]);
    allocator.free(copy);
    return out;
}

test "grass runtime decodes clusters from blobs" {
    const blobs = [_]world.cell.CellBlob{
        .{ .kind = try std.testing.allocator.dupe(u8, "grass.cluster_meta"), .payload = try std.testing.allocator.dupe(u8,
            \\{"cell":[0,0,0],"instance_count":1,"material_count":1,"controls":{"cull_distance_m":96,"fade_distance_m":12,"wind_direction_deg":225,"wind_speed_mps":5,"wind_strength":0.5,"bend_strength":0.8,"stiffness":0.7}}
        ) },
        .{ .kind = try std.testing.allocator.dupe(u8, "grass.clusters"), .payload = try std.testing.allocator.dupe(u8,
            \\{"cell":[0,0,0],"instances":[{"position":[1,2,3],"normal":[0,1,0],"material":"grass","color":[80,150,70,255],"height":0.8,"width":0.05,"yaw":1,"phase":2,"variant":0}]}
        ) },
    };
    defer for (blobs) |blob| {
        std.testing.allocator.free(blob.kind);
        std.testing.allocator.free(blob.payload);
    };
    var decoded = try decode(std.testing.allocator, &blobs);
    defer decoded.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), decoded.instances.len);
    try std.testing.expectEqualStrings("grass", decoded.instances[0].material);
}

test "grass influencer packing keeps nearest sixteen" {
    var influencers: [20]types.GrassInfluencer = undefined;
    for (&influencers, 0..) |*influencer, i| influencer.* = .{ .position = .{ @floatFromInt(20 - i), 0, 0 }, .radius = 1, .strength = 1 };
    const packed_influencers = try nearestInfluencers(std.testing.allocator, .{ .x = 0, .y = 0, .z = 0 }, &influencers);
    defer std.testing.allocator.free(packed_influencers);
    try std.testing.expectEqual(@as(usize, 16), packed_influencers.len);
    try std.testing.expect(packed_influencers[0].position[0] < packed_influencers[15].position[0]);
}
