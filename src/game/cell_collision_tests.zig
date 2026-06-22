const std = @import("std");
const framework = @import("../framework/mod.zig");
const game_physics = @import("physics.zig");
const physics_types = @import("physics_types.zig");
const world_mod = @import("../world/mod.zig");
const scene_spawn = @import("scene_spawn.zig");
const cell_collision = @import("cell_collision.zig");

test "road collision strip decodes from fcell as static aabb intent" {
    const strip = world_mod.cell.CollisionShape{
        .kind = .aabb,
        .min = .{ .x = 0, .y = -0.1, .z = -2 },
        .max = .{ .x = 48, .y = 0.2, .z = 2 },
    };

    var world_cell = world_mod.cell.WorldCellData{
        .id = .{ .x = 0, .y = 0, .z = 0 },
        .cell_size_m = 256,
        .render_meshes = try std.testing.allocator.alloc(world_mod.cell.RenderMesh, 0),
        .collisions = try std.testing.allocator.dupe(world_mod.cell.CollisionPlaceholder, &.{.{
            .min = strip.min,
            .max = strip.max,
        }}),
        .collision_shapes = try std.testing.allocator.dupe(world_mod.cell.CollisionShape, &.{strip}),
        .instances = try std.testing.allocator.alloc(world_mod.cell.InstanceRecord, 0),
        .light_probes = try std.testing.allocator.alloc(world_mod.cell.LightProbeMeta, 0),
        .neighbors = try std.testing.allocator.alloc(world_mod.cell.CellId, 0),
        .blobs = try std.testing.allocator.alloc(world_mod.cell.CellBlob, 0),
    };
    defer world_cell.deinit(std.testing.allocator);

    const encoded = try world_mod.fcell.encodeCell(std.testing.allocator, world_cell);
    defer std.testing.allocator.free(encoded);

    var decoded = try world_mod.fcell.decodeCell(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), decoded.collision_shapes.len);
    try std.testing.expectEqual(world_mod.cell.CollisionShapeKind.aabb, decoded.collision_shapes[0].kind);
    try std.testing.expectEqual(@as(f32, 0), decoded.collision_shapes[0].min.x);
    try std.testing.expectEqual(@as(f32, 48), decoded.collision_shapes[0].max.x);

    const body = try cell_collision.collisionShapePhysicsBody(
        std.testing.allocator,
        decoded.collision_shapes[0],
        decoded.blobs,
    );
    try std.testing.expectEqual(physics_types.PhysicsBodyKind.static, body.kind);
    try std.testing.expectEqual(@as(f32, 48), switch (body.shape) {
        .aabb => |half| half.x * 2.0,
        .sphere => 0,
    });
}

test "cell collision spawns baked road strips as static physics bodies" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();

    var scene = scene_spawn.SceneSpawnState.init(std.testing.allocator);
    defer scene.deinit();

    const shapes = [_]world_mod.cell.CollisionShape{.{
        .kind = .aabb,
        .min = .{ .x = 10, .y = 0, .z = -2 },
        .max = .{ .x = 58, .y = 0.3, .z = 2 },
    }};
    const spawned = try cell_collision.spawnCollisionShapes(&scene, &world, &shapes, &.{});
    try std.testing.expectEqual(@as(usize, 1), spawned);
    try std.testing.expectEqual(@as(usize, 1), scene.physics_bodies.values.count());

    var physics = game_physics.GamePhysicsState.init(std.testing.allocator);
    defer physics.deinit();
    try physics.syncScene(&scene);
    try std.testing.expectEqual(@as(usize, 1), physics.bodyCount());
}

test "cell collision rejects malformed strip bounds" {
    try std.testing.expectError(error.InvalidCellCollisionShape, cell_collision.validateCollisionShape(.{
        .kind = .aabb,
        .min = .{ .x = 4, .y = 0, .z = 0 },
        .max = .{ .x = 2, .y = 1, .z = 1 },
    }));
}

test "cell collision allows flat terrain heightfield envelope" {
    try cell_collision.validateCollisionShape(.{
        .kind = .heightfield,
        .min = .{ .x = -1024, .y = -840, .z = -5632 },
        .max = .{ .x = -768, .y = -840, .z = -5376 },
    });
}

test "terrain heightfield collision decodes blob and syncs jolt body" {
    const heights = [_]f32{ 0, 0.2, 0.1, 0, 0.3, 0.4, 0.2, 0.1, 0.2, 0.3, 0.1, 0, 0.1, 0.1, 0.1, 0 };
    const payload = try std.fmt.allocPrint(
        std.testing.allocator,
        "{{\"cell\":[0,0,0],\"size\":4,\"min_y\":0,\"max_y\":0.4,\"heights\":{f}}}",
        .{std.json.fmt(&heights, .{})},
    );
    defer std.testing.allocator.free(payload);

    const blobs = [_]world_mod.cell.CellBlob{
        .{
            .kind = "terrain.heightfield",
            .payload = payload,
        },
    };
    const shape = world_mod.cell.CollisionShape{
        .kind = .heightfield,
        .min = .{ .x = 0, .y = 0, .z = 0 },
        .max = .{ .x = 256, .y = 0.4, .z = 256 },
    };

    const body = try cell_collision.collisionShapePhysicsBody(std.testing.allocator, shape, &blobs);
    defer body.deinit(std.testing.allocator);
    try std.testing.expectEqual(physics_types.PhysicsBodyKind.static, body.kind);
    try std.testing.expectEqual(@as(u32, 4), switch (body.shape) {
        .heightfield => |heightfield| heightfield.size,
        else => 0,
    });

    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();

    var scene = scene_spawn.SceneSpawnState.init(std.testing.allocator);
    defer scene.deinit();

    const spawned = try cell_collision.spawnCollisionShapes(&scene, &world, &.{shape}, &blobs);
    try std.testing.expectEqual(@as(usize, 1), spawned);

    var physics = game_physics.GamePhysicsState.init(std.testing.allocator);
    defer physics.deinit();
    try physics.syncScene(&scene);
    try std.testing.expectEqual(@as(usize, 1), physics.bodyCount());
}

test "terrain heightfield collision fails without blob" {
    const shape = world_mod.cell.CollisionShape{
        .kind = .heightfield,
        .min = .{ .x = 0, .y = 0, .z = 0 },
        .max = .{ .x = 256, .y = 0.4, .z = 256 },
    };
    try std.testing.expectError(
        error.MissingTerrainHeightfieldBlob,
        cell_collision.collisionShapePhysicsBody(std.testing.allocator, shape, &.{}),
    );
}
