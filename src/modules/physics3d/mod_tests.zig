const std = @import("std");
const root = @import("mod.zig");
const World = root.World;
const WorldConfig = root.WorldConfig;

test "physics world integrates bodies deterministically" {
    const cfg = WorldConfig{
        .gravity = .{ .x = 0.0, .y = -9.81, .z = 0.0 },
        .fixed_dt = 1.0 / 60.0,
    };
    var world_a = World.init(std.testing.allocator, cfg);
    defer world_a.deinit();
    var world_b = World.init(std.testing.allocator, cfg);
    defer world_b.deinit();

    const body_a = try world_a.addRigidBody(.{
        .position = .{ .x = 0.0, .y = 10.0, .z = 0.0 },
    });
    const body_b = try world_b.addRigidBody(.{
        .position = .{ .x = 0.0, .y = 10.0, .z = 0.0 },
    });

    const stats_a = try world_a.stepFixed();
    const stats_b = try world_b.stepFixed();
    const state_a = world_a.getBody(body_a).?;
    const state_b = world_b.getBody(body_b).?;

    try std.testing.expectEqual(@as(usize, 1), stats_a.integrated_bodies);
    try std.testing.expectEqual(@as(usize, 1), stats_b.integrated_bodies);
    try std.testing.expectApproxEqAbs(state_a.position.y, state_b.position.y, 0.0001);
    try std.testing.expect(state_a.position.y < 10.0);
}

test "physics broadphase reports overlapping primitives" {
    var world = World.init(std.testing.allocator, .{
        .gravity = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .fixed_dt = 1.0 / 30.0,
    });
    defer world.deinit();

    const body_a = try world.addRigidBody(.{
        .position = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .shape = .{ .sphere = .{ .radius = 1.0 } },
        .is_static = true,
    });
    const body_b = try world.addRigidBody(.{
        .position = .{ .x = 1.5, .y = 0.0, .z = 0.0 },
        .shape = .{ .sphere = .{ .radius = 1.0 } },
        .is_static = true,
    });
    _ = try world.addRigidBody(.{
        .position = .{ .x = 4.0, .y = 0.0, .z = 0.0 },
        .shape = .{ .aabb = .{ .half_extents = .{ .x = 0.5, .y = 0.5, .z = 0.5 } } },
        .is_static = true,
    });

    const stats = try world.stepFixed();
    const contacts = world.getContacts();
    try std.testing.expectEqual(@as(usize, 0), stats.integrated_bodies);
    try std.testing.expectEqual(@as(usize, 1), stats.potential_pairs);
    try std.testing.expectEqual(@as(usize, 1), contacts.len);
    try std.testing.expectEqual(body_a, contacts[0].a);
    try std.testing.expectEqual(body_b, contacts[0].b);
}

test "physics solver separates dynamic body from static floor" {
    var world = World.init(std.testing.allocator, .{
        .gravity = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .fixed_dt = 1.0 / 60.0,
    });
    defer world.deinit();

    _ = try world.addRigidBody(.{
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .is_static = true,
        .shape = .{ .aabb = .{ .half_extents = .{ .x = 4, .y = 0.5, .z = 4 } } },
    });
    const dynamic_body = try world.addRigidBody(.{
        .position = .{ .x = 0, .y = 0.9, .z = 0 },
        .velocity = .{ .x = 0, .y = -2, .z = 0 },
        .shape = .{ .aabb = .{ .half_extents = .{ .x = 0.5, .y = 0.5, .z = 0.5 } } },
    });

    const stats = try world.stepFixed();
    const body = world.getBody(dynamic_body).?;
    try std.testing.expectEqual(@as(usize, 1), stats.resolved_contacts);
    try std.testing.expect(body.position.y > 0.9);
    try std.testing.expectApproxEqAbs(@as(f32, 0), body.velocity.y, 0.0001);
}

test "physics solver applies restitution between dynamic spheres" {
    var world = World.init(std.testing.allocator, .{
        .gravity = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .fixed_dt = 1.0 / 60.0,
        .restitution = 1.0,
    });
    defer world.deinit();

    const body_a = try world.addRigidBody(.{
        .position = .{ .x = -0.4, .y = 0, .z = 0 },
        .velocity = .{ .x = 1, .y = 0, .z = 0 },
        .shape = .{ .sphere = .{ .radius = 0.5 } },
    });
    const body_b = try world.addRigidBody(.{
        .position = .{ .x = 0.4, .y = 0, .z = 0 },
        .velocity = .{ .x = -1, .y = 0, .z = 0 },
        .shape = .{ .sphere = .{ .radius = 0.5 } },
    });

    const stats = try world.stepFixed();
    const a = world.getBody(body_a).?;
    const b = world.getBody(body_b).?;
    try std.testing.expectEqual(@as(usize, 1), stats.resolved_contacts);
    try std.testing.expect(a.velocity.x < 0);
    try std.testing.expect(b.velocity.x > 0);
    try std.testing.expect(a.position.x < -0.4);
    try std.testing.expect(b.position.x > 0.4);
}

test "physics solver applies contact friction" {
    var world = World.init(std.testing.allocator, .{
        .gravity = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .fixed_dt = 1.0 / 60.0,
        .friction = 1.0,
    });
    defer world.deinit();

    _ = try world.addRigidBody(.{
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .is_static = true,
        .friction = 1.0,
        .shape = .{ .aabb = .{ .half_extents = .{ .x = 4, .y = 0.5, .z = 4 } } },
    });
    const dynamic_body = try world.addRigidBody(.{
        .position = .{ .x = 0, .y = 0.9, .z = 0 },
        .velocity = .{ .x = 4, .y = -2, .z = 0 },
        .friction = 1.0,
        .shape = .{ .aabb = .{ .half_extents = .{ .x = 0.5, .y = 0.5, .z = 0.5 } } },
    });

    const stats = try world.stepFixed();
    const body = world.getBody(dynamic_body).?;
    try std.testing.expectEqual(@as(usize, 1), stats.resolved_contacts);
    try std.testing.expect(body.velocity.x < 4.0);
}

test "physics world sleeps quiet dynamic bodies" {
    var world = World.init(std.testing.allocator, .{
        .gravity = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .fixed_dt = 0.1,
        .sleep_linear_threshold = 0.05,
        .sleep_delay = 0.2,
    });
    defer world.deinit();

    const body_id = try world.addRigidBody(.{
        .position = .{ .x = 0, .y = 1, .z = 0 },
        .velocity = .{ .x = 0.01, .y = 0, .z = 0 },
        .shape = .{ .sphere = .{ .radius = 0.5 } },
    });

    _ = try world.stepFixed();
    const stats = try world.stepFixed();
    const body = world.getBody(body_id).?;
    try std.testing.expectEqual(@as(usize, 1), stats.sleeping_bodies);
    try std.testing.expect(body.is_sleeping);

    const post_sleep_stats = try world.stepFixed();
    try std.testing.expectEqual(@as(usize, 0), post_sleep_stats.integrated_bodies);
}

test "continuous collision stops fast sphere before thin static wall" {
    var world = World.init(std.testing.allocator, .{
        .gravity = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .fixed_dt = 1.0 / 60.0,
        .enable_continuous_collision = true,
    });
    defer world.deinit();

    _ = try world.addRigidBody(.{
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .is_static = true,
        .shape = .{ .aabb = .{ .half_extents = .{ .x = 0.05, .y = 2, .z = 2 } } },
    });
    const fast_body = try world.addRigidBody(.{
        .position = .{ .x = -2.5, .y = 0, .z = 0 },
        .velocity = .{ .x = 300, .y = 0, .z = 0 },
        .shape = .{ .sphere = .{ .radius = 0.1 } },
        .continuous_collision = true,
    });

    const stats = try world.stepFixed();
    const body = world.getBody(fast_body).?;
    try std.testing.expectEqual(@as(usize, 1), stats.ccd_hits);
    try std.testing.expect(body.position.x < -0.05);
    try std.testing.expectApproxEqAbs(@as(f32, 0), body.velocity.x, 0.0001);
}
