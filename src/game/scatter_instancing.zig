const std = @import("std");
const core = @import("../core/mod.zig");
const scene_spawn = @import("scene_spawn.zig");
const scatter_clusters = @import("scatter_clusters.zig");
const scatter_cull = @import("scatter_cull.zig");

pub const DrawBatch = scene_spawn.SceneSpawnState.DrawBatch;

pub const MeshGroup = struct {
    mesh_index: u32,
    transform_offset: u32,
    transform_count: u32,
};

pub const ScatterMeshGroups = struct {
    allocator: std.mem.Allocator,
    transforms: [][16]f32,
    groups: []MeshGroup,

    pub fn deinit(self: *ScatterMeshGroups) void {
        self.allocator.free(self.transforms);
        self.allocator.free(self.groups);
        self.transforms = &.{};
        self.groups = &.{};
    }
};

fn emptyGroups(allocator: std.mem.Allocator) !ScatterMeshGroups {
    return .{
        .allocator = allocator,
        .transforms = try allocator.alloc([16]f32, 0),
        .groups = try allocator.alloc(MeshGroup, 0),
    };
}

pub fn shouldIncludeBatch(batch: DrawBatch, camera: ?core.math.Vec3f) bool {
    return batchTransform(batch, camera) != null;
}

fn batchTransform(batch: DrawBatch, camera: ?core.math.Vec3f) ?[16]f32 {
    var scale = batch.scale;
    if (batch.scatter_cull) |cull| {
        if (camera) |cam| {
            const fade = scatter_cull.scatterBatchFadeFactor(cull, cam, batch.position) orelse return null;
            scale = scatter_cull.uniformFadeScale(scale, fade);
        }
    }
    return scene_spawn.objectTransformMatrix(.{
        .position = batch.position,
        .scale = scale,
    });
}

pub fn groupVisibleScatterBatches(
    allocator: std.mem.Allocator,
    batches: []const DrawBatch,
    camera: ?core.math.Vec3f,
) !ScatterMeshGroups {
    if (batches.len == 0) {
        return try emptyGroups(allocator);
    }

    var transforms = std.ArrayList([16]f32).empty;
    errdefer transforms.deinit(allocator);

    var group_counts = std.AutoHashMap(u32, u32).init(allocator);
    errdefer group_counts.deinit();

    for (batches) |batch| {
        if (batchTransform(batch, camera) == null) continue;
        const count = group_counts.get(batch.mesh_index) orelse 0;
        try group_counts.put(batch.mesh_index, count + 1);
    }

    if (group_counts.count() == 0) {
        return try emptyGroups(allocator);
    }

    var groups = try allocator.alloc(MeshGroup, group_counts.count());
    errdefer allocator.free(groups);

    var mesh_indices = std.ArrayList(u32).empty;
    defer mesh_indices.deinit(allocator);
    try mesh_indices.ensureTotalCapacity(allocator, group_counts.count());
    var group_iter = group_counts.keyIterator();
    while (group_iter.next()) |mesh_index| {
        mesh_indices.appendAssumeCapacity(mesh_index.*);
    }
    std.mem.sort(u32, mesh_indices.items, {}, std.sort.asc(u32));

    var transform_offset: u32 = 0;
    for (mesh_indices.items, 0..) |mesh_index, group_index| {
        const instance_count = group_counts.get(mesh_index).?;
        groups[group_index] = .{
            .mesh_index = mesh_index,
            .transform_offset = transform_offset,
            .transform_count = instance_count,
        };
        transform_offset += instance_count;
    }

    try transforms.ensureTotalCapacityPrecise(allocator, transform_offset);
    for (mesh_indices.items) |mesh_index| {
        for (batches) |batch| {
            if (batch.mesh_index != mesh_index) continue;
            const transform = batchTransform(batch, camera) orelse continue;
            transforms.appendAssumeCapacity(transform);
        }
    }

    return .{
        .allocator = allocator,
        .transforms = try transforms.toOwnedSlice(allocator),
        .groups = groups,
    };
}

test "scatter instancing groups visible batches by mesh index" {
    const batches = [_]DrawBatch{
        .{ .mesh_index = 1, .position = .{ .x = 0, .y = 0, .z = 0 }, .scale = .{ .x = 1, .y = 1, .z = 1 }, .scatter_cull = null },
        .{ .mesh_index = 0, .position = .{ .x = 1, .y = 0, .z = 0 }, .scale = .{ .x = 1, .y = 1, .z = 1 }, .scatter_cull = null },
        .{ .mesh_index = 0, .position = .{ .x = 2, .y = 0, .z = 0 }, .scale = .{ .x = 2, .y = 2, .z = 2 }, .scatter_cull = null },
        .{ .mesh_index = 1, .position = .{ .x = 3, .y = 0, .z = 0 }, .scale = .{ .x = 1, .y = 1, .z = 1 }, .scatter_cull = null },
    };

    var grouped = try groupVisibleScatterBatches(std.testing.allocator, &batches, .{ .x = 0, .y = 0, .z = 0 });
    defer grouped.deinit();

    try std.testing.expectEqual(@as(usize, 2), grouped.groups.len);
    try std.testing.expectEqual(@as(u32, 0), grouped.groups[0].mesh_index);
    try std.testing.expectEqual(@as(u32, 2), grouped.groups[0].transform_count);
    try std.testing.expectEqual(@as(u32, 1), grouped.groups[1].mesh_index);
    try std.testing.expectEqual(@as(u32, 2), grouped.groups[1].transform_count);
    try std.testing.expectEqual(@as(usize, 4), grouped.transforms.len);
    try std.testing.expectEqual(@as(f32, 2), grouped.transforms[1][0]);
    try std.testing.expectEqual(@as(f32, 2), grouped.transforms[1][5]);
}

test "scatter instancing preserves cull filtering before grouping" {
    const cull = scatter_clusters.ScatterCull{ .cull_distance_m = 10, .fade_distance_m = 2 };
    const batches = [_]DrawBatch{
        .{ .mesh_index = 0, .position = .{ .x = 5, .y = 0, .z = 0 }, .scale = .{ .x = 1, .y = 1, .z = 1 }, .scatter_cull = cull },
        .{ .mesh_index = 0, .position = .{ .x = 20, .y = 0, .z = 0 }, .scale = .{ .x = 1, .y = 1, .z = 1 }, .scatter_cull = cull },
    };

    var grouped = try groupVisibleScatterBatches(std.testing.allocator, &batches, .{ .x = 0, .y = 0, .z = 0 });
    defer grouped.deinit();

    try std.testing.expectEqual(@as(usize, 1), grouped.groups.len);
    try std.testing.expectEqual(@as(u32, 1), grouped.groups[0].transform_count);
    try std.testing.expectEqual(@as(f32, 5), grouped.transforms[0][12]);
}

test "scatter instance transform layout is sixteen floats" {
    try std.testing.expectEqual(@as(usize, 64), @sizeOf([16]f32));
}
