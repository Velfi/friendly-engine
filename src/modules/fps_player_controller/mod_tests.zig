const std = @import("std");
const core = @import("../../core/mod.zig");
const framework = @import("../../framework/mod.zig");
const fps = @import("mod.zig");

test "fps controller walks sprints crouches and clamps look pitch" {
    var state = fps.ControllerState{};
    const config = fps.Config{
        .walk_speed_mps = 4,
        .sprint_speed_mps = 8,
        .crouch_speed_mps = 2,
        .invert_look_y = false,
    };

    const walking = try fps.updateController(&state, .{ .x = 0, .y = 0, .z = 0 }, .{
        .dt_seconds = 1.0 / 60.0,
        .move_forward = true,
        .grounded = true,
        .look_delta_y = -10_000,
    }, config);
    try std.testing.expectEqual(fps.LocomotionMode.walking, walking.mode);
    try std.testing.expectApproxEqAbs(@as(f32, -4), walking.velocity_mps.z, 0.001);
    try std.testing.expectApproxEqAbs(config.max_pitch_rad, state.pitch_rad, 0.001);

    const sprinting = try fps.updateController(&state, .{ .x = 0, .y = 0, .z = 0 }, .{
        .dt_seconds = 1.0 / 60.0,
        .move_forward = true,
        .sprint = true,
        .grounded = true,
    }, config);
    try std.testing.expectEqual(fps.LocomotionMode.sprinting, sprinting.mode);
    try std.testing.expectApproxEqAbs(@as(f32, -8), sprinting.velocity_mps.z, 0.001);

    const crouching = try fps.updateController(&state, .{ .x = 0, .y = 0, .z = 0 }, .{
        .dt_seconds = 1.0 / 60.0,
        .move_forward = true,
        .sprint = true,
        .crouch = true,
        .grounded = true,
    }, config);
    try std.testing.expectEqual(fps.LocomotionMode.crouching, crouching.mode);
    try std.testing.expectApproxEqAbs(@as(f32, -2), crouching.velocity_mps.z, 0.001);
}

test "fps controller can invert both look axes" {
    var default_state = fps.ControllerState{};
    _ = try fps.updateController(&default_state, .{ .x = 0, .y = 0, .z = 0 }, .{
        .dt_seconds = 1.0 / 60.0,
        .look_delta_x = 12,
        .look_delta_y = 8,
    }, .{});
    try std.testing.expect(default_state.yaw_rad < 0);
    try std.testing.expect(default_state.pitch_rad > 0);

    var legacy_state = fps.ControllerState{};
    _ = try fps.updateController(&legacy_state, .{ .x = 0, .y = 0, .z = 0 }, .{
        .dt_seconds = 1.0 / 60.0,
        .look_delta_x = 12,
        .look_delta_y = 8,
    }, .{
        .invert_look_x = false,
        .invert_look_y = false,
    });
    try std.testing.expect(legacy_state.yaw_rad > 0);
    try std.testing.expect(legacy_state.pitch_rad < 0);
}

test "fps controller jumps only while grounded and standing" {
    var state = fps.ControllerState{};

    const jumped = try fps.updateController(&state, .{ .x = 0, .y = 0, .z = 0 }, .{
        .dt_seconds = 1.0 / 60.0,
        .jump_pressed = true,
        .grounded = true,
    }, .{ .jump_velocity_mps = 6 });
    try std.testing.expect(jumped.jumped);
    try std.testing.expectEqual(fps.LocomotionMode.airborne, jumped.mode);
    try std.testing.expectApproxEqAbs(@as(f32, 6), jumped.velocity_mps.y, 0.001);

    const crouch_blocked = try fps.updateController(&state, .{ .x = 0, .y = 0, .z = 0 }, .{
        .dt_seconds = 1.0 / 60.0,
        .jump_pressed = true,
        .crouch = true,
        .grounded = true,
    }, .{ .jump_velocity_mps = 6 });
    try std.testing.expect(!crouch_blocked.jumped);
}

test "fps controller swims with ascend descend and current" {
    var state = fps.ControllerState{};
    const query = @import("../water/mod.zig").WaterQuery{
        .in_water = true,
        .swimmable = true,
        .surface_y = 10,
        .bottom_y = 0,
        .submerged_depth = 5,
        .current = .{ .x = 1, .y = 0, .z = 0 },
        .volume_id = "lake",
        .material = "water.lake.clear",
    };

    const result = try fps.updateController(&state, .{ .x = 0, .y = 5, .z = 0 }, .{
        .dt_seconds = 1.0,
        .move_forward = true,
        .jump_pressed = true,
        .water_query = query,
    }, .{
        .swim_speed_mps = 4,
        .swim_vertical_speed_mps = 2,
        .water_drag = 0.5,
    });

    try std.testing.expectEqual(fps.LocomotionMode.swimming, result.mode);
    try std.testing.expectApproxEqAbs(@as(f32, 1), result.velocity_mps.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2), result.velocity_mps.y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, -2), result.velocity_mps.z, 0.001);
    try std.testing.expect(!result.jumped);
}

test "fps controller reports out of breath when eye stays underwater" {
    var state = fps.ControllerState{ .breath_remaining_seconds = 0.5 };
    const query = @import("../water/mod.zig").WaterQuery{
        .in_water = true,
        .swimmable = true,
        .surface_y = 2,
        .bottom_y = -4,
        .submerged_depth = 2,
        .volume_id = "pond",
        .material = "water.pond.clear",
    };

    const result = try fps.updateController(&state, .{ .x = 0, .y = 0, .z = 0 }, .{
        .dt_seconds = 1.0,
        .water_query = query,
    }, .{ .breath_seconds = 5 });

    try std.testing.expectEqual(fps.LocomotionMode.swimming, result.mode);
    try std.testing.expect(result.out_of_breath);
    try std.testing.expectEqual(@as(f32, 0), result.breath_remaining_seconds);
}

test "fps controller resolves authored start onto terrain heightfield" {
    const heights = [_]f32{
        10, 12,
        14, 16,
    };
    const surface = fps.TerrainHeightfield{
        .position = .{ .x = 100, .y = 0, .z = 200 },
        .size = 2,
        .offset = .{ .x = -10, .y = 0, .z = -10 },
        .scale = .{ .x = 20, .y = 1, .z = 20 },
        .heights = &heights,
    };

    const height = fps.sampleTerrainHeightfield(surface, 100, 200) orelse return error.MissingTerrainUnderPlayerStart;
    const position = try fps.resolveTerrainSpawnPosition(
        .{ .x = 100, .y = 0, .z = 200 },
        height,
        .{ .terrain_spawn_clearance_m = 0.25 },
    );

    try std.testing.expectApproxEqAbs(@as(f32, 13), height, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 13.25), position.y, 0.001);
}

test "fps controller terrain spawn requires terrain under marker" {
    const heights = [_]f32{
        0, 0,
        0, 0,
    };
    const surface = fps.TerrainHeightfield{
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .size = 2,
        .offset = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .heights = &heights,
    };

    try std.testing.expect(fps.sampleTerrainHeightfield(surface, 3, 3) == null);
}

test "fps ecs state attaches controller to live entities and updates position" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();
    var controllers = fps.EcsState.init(std.testing.allocator);
    defer controllers.deinit();

    const entity = world.spawnEntity();
    try controllers.attach(&world, entity, .{
        .config = .{ .gravity_enabled = false, .walk_speed_mps = 5 },
    });

    var position = core.math.Vec3f{ .x = 0, .y = 2, .z = 0 };
    const result = try controllers.updateEntityPosition(entity, &position, .{
        .dt_seconds = 0.5,
        .move_forward = true,
    });

    try std.testing.expectEqual(fps.LocomotionMode.walking, result.mode);
    try std.testing.expectApproxEqAbs(@as(f32, -2.5), position.z, 0.001);
    try std.testing.expectError(error.UnknownEntity, controllers.attach(&world, 9999, .{}));
}

test "fps interaction payload targets selected object" {
    const payload = try fps.interactionPayload(
        std.testing.allocator,
        .{ .entity_id = 3, .object_id = 77 },
        .{ .x = 1, .y = 2, .z = 3 },
        .{ .x = 0, .y = 0, .z = -1 },
    );
    defer std.testing.allocator.free(payload);

    try std.testing.expect(std.mem.indexOf(u8, payload, "\"entity_id\":3") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"object_id\":77") != null);
}

test "fps gem registers component and input routes" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();

    try fps.start(&world);
    try std.testing.expectEqualStrings(fps.component_name, world.component_registry.entries()[0].name);
    try std.testing.expectEqualStrings(fps.component_name, world.input.routeOwner(framework.input.InputSystem.actionId(fps.ActionNames.move_forward)).?);
    try std.testing.expectEqualStrings(fps.component_name, world.input.routeOwner(framework.input.InputSystem.actionId(fps.ActionNames.ascend)).?);
    try std.testing.expectEqualStrings(fps.component_name, world.input.routeOwner(framework.input.InputSystem.actionId(fps.ActionNames.descend)).?);

    try fps.stop(&world);
    try std.testing.expect(world.input.routeOwner(framework.input.InputSystem.actionId(fps.ActionNames.move_forward)) == null);
    try std.testing.expectEqual(@as(usize, 0), world.component_registry.entries().len);
}
