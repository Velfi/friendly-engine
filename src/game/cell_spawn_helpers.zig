const std = @import("std");
const core = @import("../core/mod.zig");
const framework = @import("../framework/mod.zig");
const world_mod = @import("../world/mod.zig");
const cell_collision = @import("cell_collision.zig");
const cell_spawn = @import("cell_spawn.zig");
const scatter_clusters = @import("scatter_clusters.zig");
const grass_clusters = @import("grass_clusters.zig");

const CellSpawnState = cell_spawn.CellSpawnState;

pub const SpawnedRangeKind = enum {
    light_probe,
    neighbor_link,
    nav_vertex,
    nav_index,
    visibility_link,
    dependency,
};

pub fn validateCellMetadata(world_cell: *const world_mod.cell.WorldCellData) !void {
    if (world_cell.nav_indices.len % 3 != 0) return error.InvalidCellNavmesh;
    for (world_cell.nav_indices) |index| {
        if (index >= world_cell.nav_vertices.len) return error.InvalidCellNavmesh;
    }
    for (world_cell.instances) |instance| {
        if (instance.mesh_index >= world_cell.render_meshes.len) return error.InvalidCellInstanceMesh;
        if (!isFiniteVec3(instance.position) or !isFiniteVec3(instance.scale)) {
            return error.InvalidCellInstanceTransform;
        }
    }
    for (world_cell.light_probes) |probe| {
        if (!isFiniteVec3(probe.position) or !std.math.isFinite(probe.intensity)) {
            return error.InvalidCellLightProbe;
        }
    }
    for (world_cell.visibility) |link| {
        if (!isFiniteVec3(link.min) or !isFiniteVec3(link.max)) {
            return error.InvalidCellVisibilityLink;
        }
        if (link.min.x > link.max.x or link.min.y > link.max.y or link.min.z > link.max.z) {
            return error.InvalidCellVisibilityLink;
        }
    }
    for (world_cell.dependencies) |dependency| {
        if (dependency.kind.len == 0 or dependency.path.len == 0) {
            return error.InvalidCellDependency;
        }
    }
    for (world_cell.collision_shapes, 0..) |shape, index| {
        cell_collision.validateCollisionShape(shape) catch |err| {
            std.log.err(
                "invalid collision shape: cell={d},{d},{d} index={d} kind={s} min={d},{d},{d} max={d},{d},{d} center={d},{d},{d} radius={d}",
                .{
                    world_cell.id.x,
                    world_cell.id.y,
                    world_cell.id.z,
                    index,
                    @tagName(shape.kind),
                    shape.min.x,
                    shape.min.y,
                    shape.min.z,
                    shape.max.x,
                    shape.max.y,
                    shape.max.z,
                    shape.center.x,
                    shape.center.y,
                    shape.center.z,
                    shape.radius,
                },
            );
            return err;
        };
    }
}

pub fn appendOffsetNavIndices(
    allocator: std.mem.Allocator,
    nav_indices: *std.ArrayList(u32),
    cell_indices: []const u32,
    vertex_start: usize,
) !void {
    for (cell_indices) |index| {
        const adjusted = try std.math.add(u32, index, @intCast(vertex_start));
        try nav_indices.append(allocator, adjusted);
    }
}

pub fn appendDependencies(
    allocator: std.mem.Allocator,
    dependencies: *std.ArrayList(world_mod.cell.CellDependency),
    cell_dependencies: []const world_mod.cell.CellDependency,
) !void {
    for (cell_dependencies) |dependency| {
        const kind = try allocator.dupe(u8, dependency.kind);
        errdefer allocator.free(kind);
        const path = try allocator.dupe(u8, dependency.path);
        errdefer allocator.free(path);
        try dependencies.append(allocator, .{
            .kind = kind,
            .path = path,
        });
    }
}

pub fn removePlainRange(
    comptime T: type,
    list: *std.ArrayList(T),
    start: usize,
    count: usize,
) !void {
    if (count == 0) return;
    if (start + count > list.items.len) return error.InvalidCellMetadataRange;
    list.replaceRangeAssumeCapacity(start, count, &.{});
}

pub fn shiftCellStarts(
    state: *CellSpawnState,
    kind: SpawnedRangeKind,
    removed_start: usize,
    removed_count: usize,
) void {
    if (removed_count == 0) return;
    var iter = state.spawned_cells.iterator();
    while (iter.next()) |entry| {
        const start = switch (kind) {
            .light_probe => &entry.value_ptr.light_probe_start,
            .neighbor_link => &entry.value_ptr.neighbor_link_start,
            .nav_vertex => &entry.value_ptr.nav_vertex_start,
            .nav_index => &entry.value_ptr.nav_index_start,
            .visibility_link => &entry.value_ptr.visibility_link_start,
            .dependency => &entry.value_ptr.dependency_start,
        };
        if (start.* > removed_start) {
            start.* -= removed_count;
        }
    }
}

fn isFiniteVec3(value: core.math.Vec3f) bool {
    return std.math.isFinite(value.x) and std.math.isFinite(value.y) and std.math.isFinite(value.z);
}

pub fn removeEntityId(list: *std.ArrayList(framework.ecs.Entity), entity: framework.ecs.Entity) void {
    for (list.items, 0..) |candidate, index| {
        if (candidate == entity) {
            _ = list.swapRemove(index);
            return;
        }
    }
}

pub fn appendScatterDrawBatches(
    state: *CellSpawnState,
    world_cell: *const world_mod.cell.WorldCellData,
    mesh_lookup: *const std.StringHashMap(u32),
) !usize {
    var decoded = try scatter_clusters.decode(state.allocator, world_cell.blobs);
    defer decoded.deinit(state.allocator);

    const scatter_cull = if (decoded.instances.len > 0) blk: {
        const meta = decoded.meta orelse return error.MissingScatterClusterMetadata;
        break :blk meta.controls.cullDistances();
    } else null;

    for (decoded.instances) |instance| {
        const mesh_index = mesh_lookup.get(instance.prototype) orelse return error.MissingScatterPrototypeMesh;
        const scale = instance.scale;
        try state.scene_state.addDrawBatch(
            mesh_index,
            instance.position,
            .{ .x = scale, .y = scale, .z = scale },
            scatter_cull,
        );
    }
    return decoded.cluster_count;
}

pub fn appendGrassBatches(
    state: *CellSpawnState,
    world_cell: *const world_mod.cell.WorldCellData,
) !usize {
    var decoded = try grass_clusters.decode(state.allocator, world_cell.blobs);
    defer decoded.deinit(state.allocator);
    if (decoded.instances.len == 0) return 0;
    const meta = decoded.meta orelse return error.MissingGrassClusterMetadata;
    const owned = try state.allocator.alloc(grass_clusters.Instance, decoded.instances.len);
    var initialized: usize = 0;
    errdefer {
        for (owned[0..initialized]) |instance| state.allocator.free(instance.material);
        state.allocator.free(owned);
    }
    var center = core.math.Vec3f{ .x = 0, .y = 0, .z = 0 };
    for (decoded.instances, 0..) |instance, i| {
        owned[i] = instance;
        owned[i].material = try state.allocator.dupe(u8, instance.material);
        initialized += 1;
        center.x += instance.position[0];
        center.y += instance.position[1];
        center.z += instance.position[2];
    }
    const denom = @as(f32, @floatFromInt(decoded.instances.len));
    center.x /= denom;
    center.y /= denom;
    center.z /= denom;
    try state.scene_state.addGrassBatch(center, owned, meta);
    return decoded.cluster_count;
}
