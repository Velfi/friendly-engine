const std = @import("std");
const core = @import("../core/mod.zig");
const framework = @import("../framework/mod.zig");
const world_mod = @import("../world/mod.zig");
const scene_spawn = @import("scene_spawn.zig");
const physics_types = @import("physics_types.zig");
const terrain_heightfield = @import("terrain_heightfield.zig");

pub fn validateCollisionShape(shape: world_mod.cell.CollisionShape) !void {
    switch (shape.kind) {
        .aabb => {
            if (!isFiniteVec3(shape.min) or !isFiniteVec3(shape.max)) return error.InvalidCellCollisionShape;
            if (shape.min.x > shape.max.x or shape.min.y > shape.max.y or shape.min.z > shape.max.z) {
                return error.InvalidCellCollisionShape;
            }
            const extent = extents(shape.min, shape.max);
            const min_extent: f32 = 0.01;
            if (extent.x < min_extent or extent.y < min_extent or extent.z < min_extent) {
                return error.InvalidCellCollisionShape;
            }
        },
        .heightfield => {
            if (!isFiniteVec3(shape.min) or !isFiniteVec3(shape.max)) return error.InvalidCellCollisionShape;
            if (shape.min.x > shape.max.x or shape.min.y > shape.max.y or shape.min.z > shape.max.z) {
                return error.InvalidCellCollisionShape;
            }
            const extent = extents(shape.min, shape.max);
            const min_extent: f32 = 0.01;
            if (extent.x < min_extent or extent.z < min_extent) {
                return error.InvalidCellCollisionShape;
            }
        },
        .sphere => {
            if (!isFiniteVec3(shape.center) or !std.math.isFinite(shape.radius) or shape.radius <= 0) {
                return error.InvalidCellCollisionShape;
            }
        },
    }
}

pub fn collisionShapeTransform(shape: world_mod.cell.CollisionShape) scene_spawn.SceneTransform {
    return switch (shape.kind) {
        .aabb => .{
            .position = midpoint(shape.min, shape.max),
            .scale = extents(shape.min, shape.max),
        },
        .heightfield => .{
            .position = .{
                .x = (shape.min.x + shape.max.x) * 0.5,
                .y = 0.0,
                .z = (shape.min.z + shape.max.z) * 0.5,
            },
            .scale = .{ .x = 1, .y = 1, .z = 1 },
        },
        .sphere => .{
            .position = shape.center,
            .scale = .{ .x = shape.radius * 2.0, .y = shape.radius * 2.0, .z = shape.radius * 2.0 },
        },
    };
}

pub fn collisionShapePhysicsBody(
    allocator: std.mem.Allocator,
    shape: world_mod.cell.CollisionShape,
    blobs: []const world_mod.cell.CellBlob,
) !physics_types.ScenePhysicsBody {
    return switch (shape.kind) {
        .aabb => physics_types.ScenePhysicsBody.staticAabb(extents(shape.min, shape.max)),
        .heightfield => blk: {
            const payload = terrain_heightfield.findHeightfieldBlobForShape(blobs, shape.min, shape.max) orelse return error.MissingTerrainHeightfieldBlob;
            var decoded = try terrain_heightfield.decodeBlob(allocator, payload, shape.min, shape.max);
            errdefer decoded.deinit(allocator);
            break :blk .{
                .kind = .static,
                .mass = 0.0,
                .shape = .{ .heightfield = .{
                    .size = decoded.size,
                    .block_size = decoded.block_size,
                    .offset = decoded.offset,
                    .scale = decoded.scale,
                    .envelope_half = decoded.envelope_half,
                    .heights = decoded.heights,
                } },
            };
        },
        .sphere => .{
            .kind = .static,
            .mass = 0.0,
            .shape = .{ .sphere = shape.radius },
        },
    };
}

pub fn spawnCollisionShapes(
    scene_state: *scene_spawn.SceneSpawnState,
    world: *framework.World,
    shapes: []const world_mod.cell.CollisionShape,
    blobs: []const world_mod.cell.CellBlob,
) !usize {
    var spawned: usize = 0;
    for (shapes) |shape| {
        try validateCollisionShape(shape);
        _ = try scene_state.spawnPhysicsBody(
            world,
            collisionShapeTransform(shape),
            try collisionShapePhysicsBody(scene_state.allocator, shape, blobs),
        );
        spawned += 1;
    }
    return spawned;
}

fn isFiniteVec3(value: core.math.Vec3f) bool {
    return std.math.isFinite(value.x) and std.math.isFinite(value.y) and std.math.isFinite(value.z);
}

fn midpoint(min: core.math.Vec3f, max: core.math.Vec3f) core.math.Vec3f {
    return .{
        .x = (min.x + max.x) * 0.5,
        .y = (min.y + max.y) * 0.5,
        .z = (min.z + max.z) * 0.5,
    };
}

fn extents(min: core.math.Vec3f, max: core.math.Vec3f) core.math.Vec3f {
    return .{
        .x = @abs(max.x - min.x),
        .y = @abs(max.y - min.y),
        .z = @abs(max.z - min.z),
    };
}

comptime {
    _ = @import("cell_collision_tests.zig");
}
