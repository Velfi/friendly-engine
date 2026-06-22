const std = @import("std");
const core = @import("../core/mod.zig");
const framework = @import("../framework/mod.zig");
const physics3d = @import("../modules/physics3d/mod.zig");
const scene_spawn = @import("scene_spawn.zig");
const physics_types = @import("physics_types.zig");

pub const PhysicsBodyKind = physics_types.PhysicsBodyKind;
pub const PhysicsShape = physics_types.PhysicsShape;
pub const ScenePhysicsBody = physics_types.ScenePhysicsBody;

const log = std.log.scoped(.game);

pub const GamePhysicsState = struct {
    allocator: std.mem.Allocator,
    physics_world: physics3d.World,
    bindings: std.AutoHashMap(framework.ecs.Entity, physics3d.BodyId),

    pub fn init(allocator: std.mem.Allocator) GamePhysicsState {
        return .{
            .allocator = allocator,
            .physics_world = physics3d.World.init(allocator, .{}),
            .bindings = std.AutoHashMap(framework.ecs.Entity, physics3d.BodyId).init(allocator),
        };
    }

    pub fn deinit(self: *GamePhysicsState) void {
        self.bindings.deinit();
        self.physics_world.deinit();
    }

    pub fn syncScene(self: *GamePhysicsState, state: *scene_spawn.SceneSpawnState) !void {
        try self.removeStaleBodies(state);

        var iter = state.physics_bodies.values.iterator();
        while (iter.next()) |entry| {
            const entity = entry.key_ptr.*;
            const desc = entry.value_ptr.*;
            const transform = state.transforms.get(entity) orelse continue;
            if (self.bindings.get(entity)) |body_id| {
                try self.syncExistingBody(body_id, transform, desc);
            } else {
                const body_id = try self.physics_world.addRigidBody(rigidBodyDesc(transform, desc));
                try self.bindings.put(entity, body_id);
            }
        }
        self.physics_world.optimizeBroadPhase();
    }

    pub fn stepScene(self: *GamePhysicsState, state: *scene_spawn.SceneSpawnState, dt: f32) !physics3d.StepStats {
        return try self.stepSceneLifecycle(state, dt, false);
    }

    pub fn stepSceneLifecycle(self: *GamePhysicsState, state: *scene_spawn.SceneSpawnState, dt: f32, startup_lifecycle: bool) !physics3d.StepStats {
        const sync_stage = lifecycleBegin(startup_lifecycle, "startup.physics.sync_scene");
        try self.syncScene(state);
        lifecycleEnd(sync_stage);

        const step_stage = lifecycleBegin(startup_lifecycle, "startup.physics.world_step");
        const stats = try self.physics_world.step(dt);
        lifecycleEnd(step_stage);

        const writeback_stage = lifecycleBegin(startup_lifecycle, "startup.physics.writeback_dynamic");
        var writeback_count: usize = 0;
        var iter = self.bindings.iterator();
        while (iter.next()) |entry| {
            const entity = entry.key_ptr.*;
            const body_id = entry.value_ptr.*;
            const desc = state.physics_bodies.get(entity) orelse continue;
            if (desc.kind != .dynamic) continue;
            const body = self.physics_world.getBody(body_id) orelse continue;
            if (state.transforms.getPtr(entity)) |transform| {
                transform.position = body.position;
                writeback_count += 1;
            }
        }
        if (startup_lifecycle) log.info("startup.physics.writeback_dynamic.count bodies={d}", .{writeback_count});
        lifecycleEnd(writeback_stage);
        return stats;
    }

    pub fn bodyCount(self: *const GamePhysicsState) usize {
        return self.bindings.count();
    }

    pub fn bodyForEntity(self: *const GamePhysicsState, entity: framework.ecs.Entity) ?physics3d.BodyId {
        return self.bindings.get(entity);
    }

    fn removeStaleBodies(self: *GamePhysicsState, state: *scene_spawn.SceneSpawnState) !void {
        var stale = std.ArrayList(framework.ecs.Entity).empty;
        defer stale.deinit(self.allocator);

        var iter = self.bindings.iterator();
        while (iter.next()) |entry| {
            const entity = entry.key_ptr.*;
            if (state.transforms.get(entity) == null or state.physics_bodies.get(entity) == null) {
                try stale.append(self.allocator, entity);
            }
        }

        for (stale.items) |entity| {
            const body_id = self.bindings.get(entity).?;
            _ = self.physics_world.removeRigidBody(body_id);
            _ = self.bindings.remove(entity);
        }
    }

    fn syncExistingBody(
        self: *GamePhysicsState,
        body_id: physics3d.BodyId,
        transform: scene_spawn.SceneTransform,
        desc: ScenePhysicsBody,
    ) !void {
        const body = self.physics_world.getBodyPtr(body_id) orelse return error.MissingPhysicsBody;
        body.shape = physicsShape(desc.shape);
        body.is_static = desc.kind == .static;
        body.inv_mass = if (body.is_static or desc.mass <= std.math.floatEps(f32)) 0.0 else 1.0 / desc.mass;
        body.friction = @max(desc.friction, 0.0);
        body.can_sleep = desc.can_sleep;
        body.continuous_collision = desc.continuous_collision;
        if (!desc.can_sleep) {
            body.is_sleeping = false;
            body.sleep_timer = 0.0;
        }
        if (desc.kind != .dynamic) {
            body.position = transform.position;
            body.previous_position = transform.position;
            body.velocity = desc.velocity;
        }
    }
};

const LifecycleStage = struct {
    name: []const u8,
    start_ns: i128,
};

fn lifecycleBegin(enabled: bool, comptime name: []const u8) ?LifecycleStage {
    if (!enabled) return null;
    log.info("{s}.begin", .{name});
    return .{
        .name = name,
        .start_ns = core.diagnostics.scopedTimerStart(),
    };
}

fn lifecycleEnd(stage: ?LifecycleStage) void {
    if (stage) |value| {
        const elapsed_ns = core.diagnostics.scopedTimerElapsedNs(value.start_ns);
        const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, @floatFromInt(std.time.ns_per_ms));
        log.info("{s}.end elapsed_ms={d:.3}", .{ value.name, elapsed_ms });
    }
}

fn rigidBodyDesc(transform: scene_spawn.SceneTransform, desc: ScenePhysicsBody) physics3d.RigidBodyDesc {
    return .{
        .position = transform.position,
        .velocity = desc.velocity,
        .mass = desc.mass,
        .is_static = desc.kind == .static,
        .friction = desc.friction,
        .can_sleep = desc.can_sleep,
        .continuous_collision = desc.continuous_collision,
        .shape = physicsShape(desc.shape),
    };
}

fn physicsShape(shape: PhysicsShape) physics3d.CollisionShape {
    return switch (shape) {
        .aabb => |half_extents| .{ .aabb = .{ .half_extents = half_extents } },
        .sphere => |radius| .{ .sphere = .{ .radius = radius } },
        .heightfield => |heightfield| .{
            .heightfield = .{
                .size = heightfield.size,
                .block_size = heightfield.block_size,
                .offset = heightfield.offset,
                .scale = heightfield.scale,
                .envelope_half = heightfield.envelope_half,
                .heights = heightfield.heights,
            },
        },
    };
}

test "physics sync creates only authored bodies" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();

    var scene = scene_spawn.SceneSpawnState.init(std.testing.allocator);
    defer scene.deinit();
    _ = try scene.spawnObject(&world, .{
        .position = .{ .x = 0, .y = 2, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .vertices = &.{},
        .indices = &.{},
        .texture = &.{},
        .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    });
    _ = try scene.spawnObject(&world, .{
        .position = .{ .x = 0, .y = 4, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .vertices = &.{},
        .indices = &.{},
        .texture = &.{},
        .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .physics = ScenePhysicsBody.dynamicAabb(.{ .x = 1, .y = 1, .z = 1 }),
    });

    var physics = GamePhysicsState.init(std.testing.allocator);
    defer physics.deinit();
    try physics.syncScene(&scene);
    try std.testing.expectEqual(@as(usize, 1), physics.bodyCount());
}

test "dynamic bodies write simulation transforms and static bodies follow transforms" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();

    var scene = scene_spawn.SceneSpawnState.init(std.testing.allocator);
    defer scene.deinit();
    const dynamic_entity = try scene.spawnObject(&world, .{
        .position = .{ .x = 0, .y = 2, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .vertices = &.{},
        .indices = &.{},
        .texture = &.{},
        .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .physics = ScenePhysicsBody.dynamicAabb(.{ .x = 1, .y = 1, .z = 1 }),
    });
    const static_entity = try scene.spawnObject(&world, .{
        .position = .{ .x = 4, .y = 1, .z = 0 },
        .scale = .{ .x = 2, .y = 1, .z = 2 },
        .vertices = &.{},
        .indices = &.{},
        .texture = &.{},
        .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .physics = ScenePhysicsBody.staticAabb(.{ .x = 2, .y = 1, .z = 2 }),
    });

    var physics = GamePhysicsState.init(std.testing.allocator);
    defer physics.deinit();
    _ = try physics.stepScene(&scene, 1.0 / 60.0);
    try std.testing.expect(scene.transforms.get(dynamic_entity).?.position.y < 2.0);

    scene.transforms.getPtr(static_entity).?.position.x = 8;
    try physics.syncScene(&scene);
    const body = physics.physics_world.getBody(physics.bodyForEntity(static_entity).?).?;
    try std.testing.expectEqual(@as(f32, 8), body.position.x);
}
