const std = @import("std");
const core = @import("../core/mod.zig");
const framework = @import("../framework/mod.zig");
const game_physics = @import("physics.zig");
const physics_types = @import("physics_types.zig");
const world_mod = @import("../world/mod.zig");
const scene_spawn = @import("scene_spawn.zig");
const root = @import("cell_spawn.zig");
const CellSpawnState = root.CellSpawnState;

test "cell spawn syncs render meshes into ECS state" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();

    var state = CellSpawnState.init(std.testing.allocator);
    defer state.deinit();

    const mesh = world_mod.cell.RenderMesh{
        .name = try std.testing.allocator.dupe(u8, "box"),
        .vertices = try std.testing.allocator.dupe(world_mod.cell.RenderVertex, &.{.{
            .position = .{ .x = -0.5, .y = 0, .z = -0.5 },
            .normal = .{ .x = 0, .y = 1, .z = 0 },
            .uv = .{ .x = 0, .y = 0 },
        }}),
        .indices = try std.testing.allocator.dupe(u32, &.{ 0, 0, 0 }),
        .texture = try std.testing.allocator.dupe(u8, &.{ 1, 2, 3, 4 }),
        .base_color = .{ .r = 170, .g = 180, .b = 195, .a = 255 },
        .position = .{ .x = 0, .y = 0.5, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
    };

    var world_cell = world_mod.cell.WorldCellData{
        .id = .{ .x = 0, .y = 0, .z = 0 },
        .cell_size_m = 256.0,
        .render_meshes = try std.testing.allocator.dupe(world_mod.cell.RenderMesh, &.{mesh}),
        .collisions = try std.testing.allocator.dupe(world_mod.cell.CollisionPlaceholder, &.{.{
            .min = .{ .x = -0.5, .y = 0, .z = -0.5 },
            .max = .{ .x = 0.5, .y = 1, .z = 0.5 },
        }}),
        .instances = try std.testing.allocator.dupe(world_mod.cell.InstanceRecord, &.{.{
            .mesh_index = 0,
            .position = .{ .x = 0, .y = 0.5, .z = 0 },
            .scale = .{ .x = 1, .y = 1, .z = 1 },
        }}),
        .light_probes = try std.testing.allocator.dupe(world_mod.cell.LightProbeMeta, &.{.{
            .position = .{ .x = 0, .y = 2, .z = 0 },
            .intensity = 1.0,
        }}),
        .neighbors = try std.testing.allocator.dupe(world_mod.cell.CellId, &.{.{ .x = 1, .y = 0, .z = 0 }}),
        .blobs = try std.testing.allocator.alloc(world_mod.cell.CellBlob, 0),
    };
    defer world_cell.deinit(std.testing.allocator);

    try state.syncFromActiveCells(&world, &.{&world_cell});
    try std.testing.expectEqual(@as(usize, 1), state.scene_state.entities.items.len);
    try std.testing.expectEqual(@as(usize, 1), state.active_cells.items.len);
    try std.testing.expectEqual(@as(usize, 1), state.collision_placeholder_count);
}

test "cell spawn streams prop instances through the prop asset cache" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "props/meshes");
    try writeTestPropMesh(&tmp.dir, "props/meshes/crate_wood.fmesh");
    try writeTestPropDocument(&tmp.dir, "crate_wood");
    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);

    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();

    var state = try CellSpawnState.initWithProject(std.testing.allocator, std.testing.io, project_path);
    defer state.deinit();

    var world_cell = world_mod.cell.WorldCellData{
        .id = .{ .x = 0, .y = 0, .z = 0 },
        .cell_size_m = 256.0,
        .render_meshes = try std.testing.allocator.alloc(world_mod.cell.RenderMesh, 0),
        .collisions = try std.testing.allocator.alloc(world_mod.cell.CollisionPlaceholder, 0),
        .collision_shapes = try std.testing.allocator.alloc(world_mod.cell.CollisionShape, 0),
        .instances = try std.testing.allocator.alloc(world_mod.cell.InstanceRecord, 0),
        .prop_instances = try std.testing.allocator.dupe(world_mod.cell.PropInstanceRecord, &.{.{
            .instance_id = 33,
            .prop_asset_id = try std.testing.allocator.dupe(u8, "crate_wood"),
            .variant = 1,
            .position = .{ .x = 4, .y = 0.5, .z = 8 },
            .scale = .{ .x = 1, .y = 2, .z = 1 },
            .base_color = .{ .r = 160, .g = 120, .b = 70, .a = 255 },
            .interactable = true,
        }}),
        .light_probes = try std.testing.allocator.alloc(world_mod.cell.LightProbeMeta, 0),
        .neighbors = try std.testing.allocator.alloc(world_mod.cell.CellId, 0),
        .dependencies = try std.testing.allocator.dupe(world_mod.cell.CellDependency, &.{.{
            .kind = try std.testing.allocator.dupe(u8, "prop"),
            .path = try std.testing.allocator.dupe(u8, "crate_wood"),
        }}),
        .blobs = try std.testing.allocator.alloc(world_mod.cell.CellBlob, 0),
    };
    defer world_cell.deinit(std.testing.allocator);

    try state.syncFromActiveCells(&world, &.{&world_cell});
    try std.testing.expectEqual(@as(usize, 0), state.scene_state.entities.items.len);
    try std.testing.expectEqual(@as(usize, 1), state.scene_state.meshes.items.len);
    try std.testing.expectEqual(@as(usize, 1), state.scene_state.draw_batches.items.len);
    try std.testing.expectEqual(@as(usize, 1), state.prop_instance_count);
    try std.testing.expectEqual(@as(usize, 1), state.prop_asset_count);

    try state.syncFromActiveCells(&world, &.{});
    try std.testing.expectEqual(@as(usize, 0), state.scene_state.draw_batches.items.len);
    try std.testing.expectEqual(@as(usize, 0), state.prop_instance_count);
    try std.testing.expectEqual(@as(usize, 0), state.prop_asset_count);
    try std.testing.expectEqual(@as(usize, 1), state.scene_state.meshes.items.len);
}

test "cell spawn reads scatter cluster blobs without entities" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();
    var state = CellSpawnState.init(std.testing.allocator);
    defer state.deinit();

    const mesh = world_mod.cell.RenderMesh{
        .name = try std.testing.allocator.dupe(u8, "scatter.grass"),
        .vertices = try std.testing.allocator.dupe(world_mod.cell.RenderVertex, &.{.{
            .position = .{ .x = -0.5, .y = 0, .z = 0 },
            .normal = .{ .x = 0, .y = 1, .z = 0 },
            .uv = .{ .x = 0, .y = 0 },
        }}),
        .indices = try std.testing.allocator.dupe(u32, &.{ 0, 0, 0 }),
        .texture = try std.testing.allocator.alloc(u8, 128 * 128 * 4),
        .base_color = .{ .r = 120, .g = 180, .b = 120, .a = 255 },
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
    };
    @memset(mesh.texture, 1);

    var world_cell = world_mod.cell.WorldCellData{
        .id = .{ .x = 0, .y = 0, .z = 0 },
        .cell_size_m = 256.0,
        .render_meshes = try std.testing.allocator.dupe(world_mod.cell.RenderMesh, &.{mesh}),
        .collisions = try std.testing.allocator.alloc(world_mod.cell.CollisionPlaceholder, 0),
        .collision_shapes = try std.testing.allocator.alloc(world_mod.cell.CollisionShape, 0),
        .instances = try std.testing.allocator.alloc(world_mod.cell.InstanceRecord, 0),
        .light_probes = try std.testing.allocator.alloc(world_mod.cell.LightProbeMeta, 0),
        .neighbors = try std.testing.allocator.alloc(world_mod.cell.CellId, 0),
        .blobs = try std.testing.allocator.dupe(world_mod.cell.CellBlob, &.{
            .{
                .kind = try std.testing.allocator.dupe(u8, "scatter.cluster_meta"),
                .payload = try std.testing.allocator.dupe(
                    u8,
                    \\{"cell":[0,0,0],"instance_count":1,"prototype_count":1,"biome_count":1,"controls":{"max_instances_per_cluster":32,"cull_distance_m":96,"fade_distance_m":12,"lod_bias":1}}
                    ,
                ),
            },
            .{
                .kind = try std.testing.allocator.dupe(u8, "scatter.clusters"),
                .payload = try std.testing.allocator.dupe(
                    u8,
                    \\{"instances":[{"prototype":"scatter.grass","position":[1,0,2],"scale":1.2}]}
                    ,
                ),
            },
        }),
    };
    defer world_cell.deinit(std.testing.allocator);

    try state.syncFromActiveCells(&world, &.{&world_cell});
    try std.testing.expectEqual(@as(usize, 1), state.scene_state.entities.items.len);
    try std.testing.expectEqual(@as(usize, 1), state.scene_state.draw_batches.items.len);
    try std.testing.expectEqual(@as(usize, 1), state.scatter_cluster_count);
    const batch = state.scene_state.draw_batches.items[0];
    try std.testing.expectEqual(@as(f32, 1), batch.position.x);
    try std.testing.expectEqual(@as(f32, 1.2), batch.scale.x);
    try std.testing.expect(batch.scatter_cull != null);
    try std.testing.expectEqual(@as(f32, 96), batch.scatter_cull.?.cull_distance_m);
    try std.testing.expectEqual(@as(f32, 12), batch.scatter_cull.?.fade_distance_m);
}

test "cell spawn scatter draw batches respect runtime cull distance" {
    const game = @import("mod.zig");
    const scatter_cull_mod = @import("scatter_cull.zig");

    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();
    var state = CellSpawnState.init(std.testing.allocator);
    defer state.deinit();

    const mesh = world_mod.cell.RenderMesh{
        .name = try std.testing.allocator.dupe(u8, "scatter.grass"),
        .vertices = try std.testing.allocator.dupe(world_mod.cell.RenderVertex, &.{.{
            .position = .{ .x = -0.5, .y = 0, .z = 0 },
            .normal = .{ .x = 0, .y = 1, .z = 0 },
            .uv = .{ .x = 0, .y = 0 },
        }}),
        .indices = try std.testing.allocator.dupe(u32, &.{ 0, 0, 0 }),
        .texture = try std.testing.allocator.alloc(u8, 128 * 128 * 4),
        .base_color = .{ .r = 120, .g = 180, .b = 120, .a = 255 },
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
    };
    @memset(mesh.texture, 1);

    var world_cell = world_mod.cell.WorldCellData{
        .id = .{ .x = 0, .y = 0, .z = 0 },
        .cell_size_m = 256.0,
        .render_meshes = try std.testing.allocator.dupe(world_mod.cell.RenderMesh, &.{mesh}),
        .collisions = try std.testing.allocator.alloc(world_mod.cell.CollisionPlaceholder, 0),
        .collision_shapes = try std.testing.allocator.alloc(world_mod.cell.CollisionShape, 0),
        .instances = try std.testing.allocator.alloc(world_mod.cell.InstanceRecord, 0),
        .light_probes = try std.testing.allocator.alloc(world_mod.cell.LightProbeMeta, 0),
        .neighbors = try std.testing.allocator.alloc(world_mod.cell.CellId, 0),
        .blobs = try std.testing.allocator.dupe(world_mod.cell.CellBlob, &.{
            .{
                .kind = try std.testing.allocator.dupe(u8, "scatter.cluster_meta"),
                .payload = try std.testing.allocator.dupe(
                    u8,
                    \\{"cell":[0,0,0],"instance_count":2,"prototype_count":1,"biome_count":1,"controls":{"max_instances_per_cluster":32,"cull_distance_m":10,"fade_distance_m":2,"lod_bias":1}}
                    ,
                ),
            },
            .{
                .kind = try std.testing.allocator.dupe(u8, "scatter.clusters"),
                .payload = try std.testing.allocator.dupe(
                    u8,
                    \\{"instances":[{"prototype":"scatter.grass","position":[5,0,0],"scale":1},{"prototype":"scatter.grass","position":[20,0,0],"scale":1}]}
                    ,
                ),
            },
        }),
    };
    defer world_cell.deinit(std.testing.allocator);

    try state.syncFromActiveCells(&world, &.{&world_cell});
    try std.testing.expectEqual(@as(usize, 2), state.scene_state.draw_batches.items.len);

    const camera: core.math.Vec3f = .{ .x = 0, .y = 0, .z = 0 };
    const near = state.scene_state.draw_batches.items[0];
    const far = state.scene_state.draw_batches.items[1];
    try std.testing.expect(game.shouldSubmitDrawBatch(near, camera));
    try std.testing.expect(!game.shouldSubmitDrawBatch(far, camera));
    try std.testing.expect(scatter_cull_mod.shouldDrawScatter(near.scatter_cull.?, camera, near.position));
    try std.testing.expect(!scatter_cull_mod.shouldDrawScatter(far.scatter_cull.?, camera, far.position));
}

test "scatter fade submission scales draw batch transform in fade range" {
    const game = @import("mod.zig");
    const batch = scene_spawn.SceneSpawnState.DrawBatch{
        .mesh_index = 0,
        .position = .{ .x = 90, .y = 0, .z = 0 },
        .scale = .{ .x = 2, .y = 2, .z = 2 },
        .scatter_cull = .{ .cull_distance_m = 100, .fade_distance_m = 20 },
    };
    const camera: core.math.Vec3f = .{ .x = 0, .y = 0, .z = 0 };
    const submission = game.scatterDrawSubmission(batch, camera).?;
    try std.testing.expectEqual(@as(f32, 0.5), submission.color_alpha);
    try std.testing.expectEqual(@as(f32, 1), submission.transform[0]);
    try std.testing.expectEqual(@as(f32, 1), submission.transform[5]);
    try std.testing.expectEqual(@as(f32, 1), submission.transform[10]);
    try std.testing.expect(game.scatterDrawSubmission(.{
        .mesh_index = 0,
        .position = .{ .x = 100, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .scatter_cull = batch.scatter_cull,
    }, camera) == null);
}

test "cell spawn reload replaces scatter draw batches" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();
    var state = CellSpawnState.init(std.testing.allocator);
    defer state.deinit();

    const makeScatterCell = struct {
        fn call(allocator: std.mem.Allocator, position_x: f32) !world_mod.cell.WorldCellData {
            const mesh = world_mod.cell.RenderMesh{
                .name = try allocator.dupe(u8, "scatter.grass"),
                .vertices = try allocator.dupe(world_mod.cell.RenderVertex, &.{.{
                    .position = .{ .x = -0.5, .y = 0, .z = 0 },
                    .normal = .{ .x = 0, .y = 1, .z = 0 },
                    .uv = .{ .x = 0, .y = 0 },
                }}),
                .indices = try allocator.dupe(u32, &.{ 0, 0, 0 }),
                .texture = try allocator.alloc(u8, 128 * 128 * 4),
                .base_color = .{ .r = 120, .g = 180, .b = 120, .a = 255 },
                .position = .{ .x = 0, .y = 0, .z = 0 },
                .scale = .{ .x = 1, .y = 1, .z = 1 },
            };
            @memset(mesh.texture, 1);

            return .{
                .id = .{ .x = 0, .y = 0, .z = 0 },
                .cell_size_m = 256.0,
                .render_meshes = try allocator.dupe(world_mod.cell.RenderMesh, &.{mesh}),
                .collisions = try allocator.alloc(world_mod.cell.CollisionPlaceholder, 0),
                .collision_shapes = try allocator.alloc(world_mod.cell.CollisionShape, 0),
                .instances = try allocator.alloc(world_mod.cell.InstanceRecord, 0),
                .light_probes = try allocator.alloc(world_mod.cell.LightProbeMeta, 0),
                .neighbors = try allocator.alloc(world_mod.cell.CellId, 0),
                .blobs = try allocator.dupe(world_mod.cell.CellBlob, &.{
                    .{
                        .kind = try allocator.dupe(u8, "scatter.cluster_meta"),
                        .payload = try allocator.dupe(
                            u8,
                            \\{"cell":[0,0,0],"instance_count":1,"prototype_count":1,"biome_count":1,"controls":{"max_instances_per_cluster":32,"cull_distance_m":96,"fade_distance_m":12,"lod_bias":1}}
                            ,
                        ),
                    },
                    .{
                        .kind = try allocator.dupe(u8, "scatter.clusters"),
                        .payload = try std.fmt.allocPrint(
                            allocator,
                            "{{\"instances\":[{{\"prototype\":\"scatter.grass\",\"position\":[{d},0,2],\"scale\":1.2}}]}}",
                            .{position_x},
                        ),
                    },
                }),
            };
        }
    }.call;

    var first_cell = try makeScatterCell(std.testing.allocator, 1);
    defer first_cell.deinit(std.testing.allocator);
    var second_cell = try makeScatterCell(std.testing.allocator, 9);
    defer second_cell.deinit(std.testing.allocator);

    try state.syncFromActiveCells(&world, &.{&first_cell});
    try std.testing.expectEqual(@as(f32, 1), state.scene_state.draw_batches.items[0].position.x);

    try state.reloadActiveCell(&world, &second_cell);
    try std.testing.expectEqual(@as(usize, 1), state.scene_state.draw_batches.items.len);
    try std.testing.expectEqual(@as(f32, 9), state.scene_state.draw_batches.items[0].position.x);
}

test "cell spawn rejects scatter cluster metadata mismatch" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();
    var state = CellSpawnState.init(std.testing.allocator);
    defer state.deinit();

    const mesh = world_mod.cell.RenderMesh{
        .name = try std.testing.allocator.dupe(u8, "scatter.grass"),
        .vertices = try std.testing.allocator.dupe(world_mod.cell.RenderVertex, &.{.{
            .position = .{ .x = -0.5, .y = 0, .z = 0 },
            .normal = .{ .x = 0, .y = 1, .z = 0 },
            .uv = .{ .x = 0, .y = 0 },
        }}),
        .indices = try std.testing.allocator.dupe(u32, &.{ 0, 0, 0 }),
        .texture = try std.testing.allocator.alloc(u8, 128 * 128 * 4),
        .base_color = .{ .r = 120, .g = 180, .b = 120, .a = 255 },
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
    };
    @memset(mesh.texture, 1);

    var world_cell = world_mod.cell.WorldCellData{
        .id = .{ .x = 0, .y = 0, .z = 0 },
        .cell_size_m = 256.0,
        .render_meshes = try std.testing.allocator.dupe(world_mod.cell.RenderMesh, &.{mesh}),
        .collisions = try std.testing.allocator.alloc(world_mod.cell.CollisionPlaceholder, 0),
        .collision_shapes = try std.testing.allocator.alloc(world_mod.cell.CollisionShape, 0),
        .instances = try std.testing.allocator.alloc(world_mod.cell.InstanceRecord, 0),
        .light_probes = try std.testing.allocator.alloc(world_mod.cell.LightProbeMeta, 0),
        .neighbors = try std.testing.allocator.alloc(world_mod.cell.CellId, 0),
        .blobs = try std.testing.allocator.dupe(world_mod.cell.CellBlob, &.{
            .{
                .kind = try std.testing.allocator.dupe(u8, "scatter.cluster_meta"),
                .payload = try std.testing.allocator.dupe(
                    u8,
                    \\{"cell":[0,0,0],"instance_count":2,"prototype_count":1,"biome_count":1,"controls":{"max_instances_per_cluster":32,"cull_distance_m":96,"fade_distance_m":12,"lod_bias":1}}
                    ,
                ),
            },
            .{
                .kind = try std.testing.allocator.dupe(u8, "scatter.clusters"),
                .payload = try std.testing.allocator.dupe(
                    u8,
                    \\{"instances":[{"prototype":"scatter.grass","position":[1,0,2],"scale":1.2}]}
                    ,
                ),
            },
        }),
    };
    defer world_cell.deinit(std.testing.allocator);

    try std.testing.expectError(
        error.InvalidScatterClusterMetadata,
        state.syncFromActiveCells(&world, &.{&world_cell}),
    );
    try std.testing.expectEqual(@as(usize, 0), state.scene_state.draw_batches.items.len);
}

test "cell spawn activates baked collision shapes as static physics bodies" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();
    var state = CellSpawnState.init(std.testing.allocator);
    defer state.deinit();

    var world_cell = try makeTestCell(.{ .x = 0, .y = 0, .z = 0 }, "cell.collision");
    defer world_cell.deinit(std.testing.allocator);
    std.testing.allocator.free(world_cell.collision_shapes);
    world_cell.collision_shapes = try std.testing.allocator.dupe(world_mod.cell.CollisionShape, &.{.{
        .kind = .aabb,
        .min = .{ .x = -1, .y = 0, .z = -2 },
        .max = .{ .x = 1, .y = 2, .z = 2 },
    }});

    try state.syncFromActiveCells(&world, &.{&world_cell});
    try std.testing.expectEqual(@as(usize, 2), state.scene_state.entities.items.len);
    try std.testing.expectEqual(@as(usize, 1), state.scene_state.meshes.items.len);
    try std.testing.expectEqual(@as(usize, 1), state.scene_state.physics_bodies.values.count());

    var iter = state.scene_state.physics_bodies.values.iterator();
    const entity = iter.next().?.key_ptr.*;
    const transform = state.scene_state.transforms.get(entity).?;
    const body = state.scene_state.physics_bodies.get(entity).?;
    try std.testing.expectEqual(physics_types.PhysicsBodyKind.static, body.kind);
    try std.testing.expectEqual(@as(f32, 0), transform.position.x);
    try std.testing.expectEqual(@as(f32, 1), transform.position.y);
    try std.testing.expectEqual(@as(f32, 4), switch (body.shape) {
        .aabb => |half_extents| half_extents.z * 2.0,
        .sphere => 0,
    });

    var physics = game_physics.GamePhysicsState.init(std.testing.allocator);
    defer physics.deinit();
    try physics.syncScene(&state.scene_state);
    try std.testing.expectEqual(@as(usize, 1), physics.bodyCount());
}

test "cell spawn preserves unchanged cell entities during sync" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();
    var state = CellSpawnState.init(std.testing.allocator);
    defer state.deinit();

    var first_cell = try makeTestCell(.{ .x = 0, .y = 0, .z = 0 }, "cell.a");
    defer first_cell.deinit(std.testing.allocator);
    var second_cell = try makeTestCell(.{ .x = 1, .y = 0, .z = 0 }, "cell.b");
    defer second_cell.deinit(std.testing.allocator);

    try state.syncFromActiveCells(&world, &.{ &first_cell, &second_cell });
    try std.testing.expectEqual(@as(usize, 2), state.scene_state.entities.items.len);
    const preserved_entity = state.spawned_cells.get(first_cell.id).?.entities[0];
    const removed_entity = state.spawned_cells.get(second_cell.id).?.entities[0];

    try state.syncFromActiveCells(&world, &.{&first_cell});
    try std.testing.expectEqual(@as(usize, 1), state.scene_state.entities.items.len);
    try std.testing.expect(world.ecs_world.isAlive(preserved_entity));
    try std.testing.expect(!world.ecs_world.isAlive(removed_entity));
    try std.testing.expectEqual(preserved_entity, state.spawned_cells.get(first_cell.id).?.entities[0]);
}

test "cell spawn retains and unloads baked world metadata" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();
    var state = CellSpawnState.init(std.testing.allocator);
    defer state.deinit();

    var first_cell = try makeTestCell(.{ .x = 0, .y = 0, .z = 0 }, "cell.a");
    defer first_cell.deinit(std.testing.allocator);
    first_cell.nav_vertices = try std.testing.allocator.dupe(core.math.Vec3f, &.{
        .{ .x = 0, .y = 0, .z = 0 },
        .{ .x = 1, .y = 0, .z = 0 },
        .{ .x = 0, .y = 0, .z = 1 },
    });
    first_cell.nav_indices = try std.testing.allocator.dupe(u32, &.{ 0, 1, 2 });
    first_cell.visibility = try std.testing.allocator.dupe(world_mod.cell.VisibilityLink, &.{.{
        .target = .{ .x = 1, .y = 0, .z = 0 },
        .min = .{ .x = 0, .y = 0, .z = 0 },
        .max = .{ .x = 1, .y = 2, .z = 1 },
    }});
    first_cell.dependencies = try std.testing.allocator.dupe(world_mod.cell.CellDependency, &.{.{
        .kind = try std.testing.allocator.dupe(u8, "mesh"),
        .path = try std.testing.allocator.dupe(u8, "world/object/1/mesh"),
    }});

    var second_cell = try makeTestCell(.{ .x = 1, .y = 0, .z = 0 }, "cell.b");
    defer second_cell.deinit(std.testing.allocator);
    second_cell.nav_vertices = try std.testing.allocator.dupe(core.math.Vec3f, &.{
        .{ .x = 2, .y = 0, .z = 0 },
        .{ .x = 3, .y = 0, .z = 0 },
        .{ .x = 2, .y = 0, .z = 1 },
    });
    second_cell.nav_indices = try std.testing.allocator.dupe(u32, &.{ 0, 1, 2 });
    second_cell.dependencies = try std.testing.allocator.dupe(world_mod.cell.CellDependency, &.{.{
        .kind = try std.testing.allocator.dupe(u8, "material"),
        .path = try std.testing.allocator.dupe(u8, "world/object/2/material"),
    }});

    try state.syncFromActiveCells(&world, &.{ &first_cell, &second_cell });
    try std.testing.expectEqual(@as(usize, 6), state.nav_vertices.items.len);
    try std.testing.expectEqual(@as(usize, 6), state.nav_indices.items.len);
    try std.testing.expectEqual(@as(usize, 2), state.nav_triangle_count);
    try std.testing.expectEqual(@as(usize, 1), state.visibility_link_count);
    try std.testing.expectEqual(@as(usize, 2), state.dependency_count);
    try std.testing.expectEqual(@as(u32, 3), state.nav_indices.items[3]);

    try state.syncFromActiveCells(&world, &.{&second_cell});
    try std.testing.expectEqual(@as(usize, 3), state.nav_vertices.items.len);
    try std.testing.expectEqual(@as(usize, 3), state.nav_indices.items.len);
    try std.testing.expectEqual(@as(usize, 1), state.nav_triangle_count);
    try std.testing.expectEqual(@as(usize, 0), state.visibility_link_count);
    try std.testing.expectEqual(@as(usize, 1), state.dependency_count);
    try std.testing.expectEqual(@as(u32, 0), state.nav_indices.items[0]);
    try std.testing.expectEqualStrings("world/object/2/material", state.dependencies.items[0].path);
}

test "cell spawn rejects malformed baked navmesh" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();
    var state = CellSpawnState.init(std.testing.allocator);
    defer state.deinit();

    var world_cell = try makeTestCell(.{ .x = 0, .y = 0, .z = 0 }, "cell.bad_nav");
    defer world_cell.deinit(std.testing.allocator);
    world_cell.nav_vertices = try std.testing.allocator.dupe(core.math.Vec3f, &.{
        .{ .x = 0, .y = 0, .z = 0 },
    });
    world_cell.nav_indices = try std.testing.allocator.dupe(u32, &.{ 0, 1, 2 });

    try std.testing.expectError(
        error.InvalidCellNavmesh,
        state.syncFromActiveCells(&world, &.{&world_cell}),
    );
    try std.testing.expectEqual(@as(usize, 0), state.nav_vertices.items.len);
    try std.testing.expectEqual(@as(usize, 0), state.nav_indices.items.len);
}

test "cell spawn hot reload replaces road collision physics bodies" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();
    var state = CellSpawnState.init(std.testing.allocator);
    defer state.deinit();

    var first_cell = try makeTestCell(.{ .x = 0, .y = 0, .z = 0 }, "cell.before");
    defer first_cell.deinit(std.testing.allocator);
    std.testing.allocator.free(first_cell.collision_shapes);
    first_cell.collision_shapes = try std.testing.allocator.dupe(world_mod.cell.CollisionShape, &.{.{
        .kind = .aabb,
        .min = .{ .x = 0, .y = 0, .z = -2 },
        .max = .{ .x = 48, .y = 0.2, .z = 2 },
    }});

    var second_cell = try makeTestCell(.{ .x = 0, .y = 0, .z = 0 }, "cell.after");
    defer second_cell.deinit(std.testing.allocator);
    std.testing.allocator.free(second_cell.collision_shapes);
    second_cell.collision_shapes = try std.testing.allocator.dupe(world_mod.cell.CollisionShape, &.{.{
        .kind = .aabb,
        .min = .{ .x = 8, .y = 0, .z = -2 },
        .max = .{ .x = 56, .y = 0.2, .z = 2 },
    }});

    try state.syncFromActiveCells(&world, &.{&first_cell});
    try std.testing.expectEqual(@as(usize, 1), state.collision_shape_count);
    try std.testing.expectEqual(@as(usize, 2), state.scene_state.entities.items.len);

    var physics = game_physics.GamePhysicsState.init(std.testing.allocator);
    defer physics.deinit();
    try physics.syncScene(&state.scene_state);
    try std.testing.expectEqual(@as(usize, 1), physics.bodyCount());

    try state.reloadActiveCell(&world, &second_cell);
    try std.testing.expectEqual(@as(usize, 1), state.collision_shape_count);
    try physics.syncScene(&state.scene_state);
    try std.testing.expectEqual(@as(usize, 1), physics.bodyCount());

    var iter = state.scene_state.physics_bodies.values.iterator();
    const entity = iter.next().?.key_ptr.*;
    const transform = state.scene_state.transforms.get(entity).?;
    try std.testing.expect(transform.position.x > 20);
}

test "cell spawn hot reload replaces active cell entities" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();
    var state = CellSpawnState.init(std.testing.allocator);
    defer state.deinit();

    var first_cell = try makeTestCell(.{ .x = 0, .y = 0, .z = 0 }, "cell.before");
    defer first_cell.deinit(std.testing.allocator);
    var second_cell = try makeTestCell(.{ .x = 0, .y = 0, .z = 0 }, "cell.after");
    defer second_cell.deinit(std.testing.allocator);
    second_cell.render_meshes[0].position = .{ .x = 8, .y = 0.5, .z = 0 };

    try state.syncFromActiveCells(&world, &.{&first_cell});
    const old_entity = state.spawned_cells.get(first_cell.id).?.entities[0];
    try std.testing.expect(world.ecs_world.isAlive(old_entity));

    try state.reloadActiveCell(&world, &second_cell);
    try std.testing.expect(!world.ecs_world.isAlive(old_entity));
    try std.testing.expectEqual(@as(usize, 1), state.scene_state.entities.items.len);
    const new_entity = state.spawned_cells.get(second_cell.id).?.entities[0];
    const transform = state.scene_state.transforms.get(new_entity).?;
    try std.testing.expectEqual(@as(f32, 8), transform.position.x);
}

fn makeTestCell(id: world_mod.cell.CellId, name: []const u8) !world_mod.cell.WorldCellData {
    const mesh = world_mod.cell.RenderMesh{
        .name = try std.testing.allocator.dupe(u8, name),
        .vertices = try std.testing.allocator.dupe(world_mod.cell.RenderVertex, &.{.{
            .position = .{ .x = -0.5, .y = 0, .z = -0.5 },
            .normal = .{ .x = 0, .y = 1, .z = 0 },
            .uv = .{ .x = 0, .y = 0 },
        }}),
        .indices = try std.testing.allocator.dupe(u32, &.{ 0, 0, 0 }),
        .texture = try std.testing.allocator.dupe(u8, &.{ 1, 2, 3, 4 }),
        .base_color = .{ .r = 170, .g = 180, .b = 195, .a = 255 },
        .position = .{ .x = @floatFromInt(id.x), .y = 0.5, .z = @floatFromInt(id.y) },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
    };

    return .{
        .id = id,
        .cell_size_m = 256.0,
        .render_meshes = try std.testing.allocator.dupe(world_mod.cell.RenderMesh, &.{mesh}),
        .collisions = try std.testing.allocator.alloc(world_mod.cell.CollisionPlaceholder, 0),
        .instances = try std.testing.allocator.alloc(world_mod.cell.InstanceRecord, 0),
        .light_probes = try std.testing.allocator.alloc(world_mod.cell.LightProbeMeta, 0),
        .neighbors = try std.testing.allocator.alloc(world_mod.cell.CellId, 0),
        .blobs = try std.testing.allocator.alloc(world_mod.cell.CellBlob, 0),
    };
}

test "sync physics from baked project outdoor cell" {
    const project_path = std.fs.cwd().realpathAlloc(std.testing.allocator, ".") catch return error.SkipZigTest;
    defer std.testing.allocator.free(project_path);

    var cell_io = try world_mod.file_io.SyncCellFileIo.init(
        std.testing.allocator,
        std.testing.io,
        project_path,
        "client-debug",
        "main",
    );
    defer cell_io.deinit();

    var world_cell = try cell_io.readCell(.{ .x = 0, .y = 0, .z = 0 });
    defer world_cell.deinit(std.testing.allocator);

    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();
    var state = CellSpawnState.init(std.testing.allocator);
    defer state.deinit();

    try state.syncFromActiveCells(&world, &.{&world_cell});

    var physics = game_physics.GamePhysicsState.init(std.testing.allocator);
    defer physics.deinit();
    try physics.syncScene(&state.scene_state);
    try std.testing.expect(physics.bodyCount() > 0);
}

fn writeTestPropMesh(dir: *std.fs.Dir, path: []const u8) !void {
    const vertices = [_]scene_spawn.StoredVertex{
        .{ .position = .{ .x = -0.5, .y = 0, .z = 0 }, .normal = .{ .x = 0, .y = 1, .z = 0 }, .uv = .{ .x = 0, .y = 0 } },
        .{ .position = .{ .x = 0.5, .y = 0, .z = 0 }, .normal = .{ .x = 0, .y = 1, .z = 0 }, .uv = .{ .x = 1, .y = 0 } },
        .{ .position = .{ .x = 0, .y = 1, .z = 0 }, .normal = .{ .x = 0, .y = 1, .z = 0 }, .uv = .{ .x = 0.5, .y = 1 } },
    };
    const indices = [_]u32{ 0, 1, 2 };
    const bytes = try encodeTestPropMesh(std.testing.allocator, &vertices, &indices);
    defer std.testing.allocator.free(bytes);
    try dir.writeFile(std.testing.io, .{ .sub_path = path, .data = bytes });
}

fn writeTestPropDocument(dir: *std.fs.Dir, asset_id: []const u8) !void {
    const bytes = try std.fmt.allocPrint(std.testing.allocator,
        \\prop_asset version=1 id="{s}" label="Crate Wood" tags="test" deleted=false {{
        \\  recipe {{
        \\  }}
        \\  mesh asset="props/meshes/{s}.fmesh"
        \\  material base_color="160,120,70,255"
        \\  variants count=1
        \\}}
        \\
    , .{ asset_id, asset_id });
    defer std.testing.allocator.free(bytes);
    const path = try std.fmt.allocPrint(std.testing.allocator, "props/{s}.kdl", .{asset_id});
    defer std.testing.allocator.free(path);
    try dir.writeFile(std.testing.io, .{ .sub_path = path, .data = bytes });
}

fn encodeTestPropMesh(
    allocator: std.mem.Allocator,
    vertices: []const scene_spawn.StoredVertex,
    indices: []const u32,
) ![]u8 {
    const vertex_bytes = std.mem.sliceAsBytes(vertices);
    const index_bytes = std.mem.sliceAsBytes(indices);
    const total = 4 + 4 + 4 + 4 + vertex_bytes.len + index_bytes.len + 1;
    const bytes = try allocator.alloc(u8, total);
    var offset: usize = 0;
    @memcpy(bytes[offset..][0..4], "FMES");
    offset += 4;
    std.mem.writeInt(u32, bytes[offset..][0..4], 2, .little);
    offset += 4;
    std.mem.writeInt(u32, bytes[offset..][0..4], @intCast(vertices.len), .little);
    offset += 4;
    std.mem.writeInt(u32, bytes[offset..][0..4], @intCast(indices.len), .little);
    offset += 4;
    @memcpy(bytes[offset..][0..vertex_bytes.len], vertex_bytes);
    offset += vertex_bytes.len;
    @memcpy(bytes[offset..][0..index_bytes.len], index_bytes);
    offset += index_bytes.len;
    bytes[offset] = 0;
    return bytes;
}

test "sync physics from all baked project cells" {
    const project_path = std.fs.cwd().realpathAlloc(std.testing.allocator, ".") catch return error.SkipZigTest;
    defer std.testing.allocator.free(project_path);

    var cell_io = try world_mod.file_io.SyncCellFileIo.init(
        std.testing.allocator,
        std.testing.io,
        project_path,
        "client-debug",
        "main",
    );
    defer cell_io.deinit();

    const ids = [_]world_mod.cell.CellId{
        .{ .x = 0, .y = 0, .z = 0 },
        .{ .x = 0, .y = 0, .z = 1 },
        .{ .x = 0, .y = -1, .z = 0 },
    };

    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();
    var state = CellSpawnState.init(std.testing.allocator);
    defer state.deinit();

    var cells: [3]*const world_mod.cell.WorldCellData = undefined;
    var loaded: [3]world_mod.cell.WorldCellData = undefined;
    for (ids, 0..) |id, i| {
        loaded[i] = try cell_io.readCell(id);
        cells[i] = &loaded[i];
    }
    defer for (&loaded) |*cell_data| cell_data.deinit(std.testing.allocator);

    try state.syncFromActiveCells(&world, &cells);

    var physics = game_physics.GamePhysicsState.init(std.testing.allocator);
    defer physics.deinit();
    try physics.syncScene(&state.scene_state);
    try std.testing.expect(physics.bodyCount() > 0);
}
