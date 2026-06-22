const builtin = @import("builtin");
const std = @import("std");
const core = @import("../../core/mod.zig");
const physics = @import("mod.zig");
pub const zphy = @import("zphysics");

const BodyId = physics.BodyId;
const CollisionShape = physics.CollisionShape;
const RigidBodyDesc = physics.RigidBodyDesc;
const WorldConfig = physics.WorldConfig;

pub const Dependency = struct {
    pub const name = "zphysics";
    pub const double_precision = zphy.Real == f64;
    pub const deterministic = true;
};

const object_layers = struct {
    const non_moving: zphy.ObjectLayer = 0;
    const moving: zphy.ObjectLayer = 1;
    const len: u32 = 2;
};

const broad_phase_layers = struct {
    const non_moving: zphy.BroadPhaseLayer = 0;
    const moving: zphy.BroadPhaseLayer = 1;
    const len: u32 = 2;
};

const BroadphaseLayerInterface = extern struct {
    interface: zphy.BroadPhaseLayerInterface = .init(@This()),
    object_to_broad_phase: [object_layers.len]zphy.BroadPhaseLayer = .{
        broad_phase_layers.non_moving,
        broad_phase_layers.moving,
    },

    pub fn getNumBroadPhaseLayers(interface: *const zphy.BroadPhaseLayerInterface) callconv(.c) u32 {
        const self: *const BroadphaseLayerInterface = @alignCast(@fieldParentPtr("interface", interface));
        return @intCast(self.object_to_broad_phase.len);
    }

    pub const getBroadPhaseLayer = if (builtin.abi == .msvc) getBroadPhaseLayerMsvc else getBroadPhaseLayerNative;

    fn getBroadPhaseLayerNative(interface: *const zphy.BroadPhaseLayerInterface, layer: zphy.ObjectLayer) callconv(.c) zphy.BroadPhaseLayer {
        const self: *const BroadphaseLayerInterface = @alignCast(@fieldParentPtr("interface", interface));
        return self.object_to_broad_phase[@intCast(layer)];
    }

    fn getBroadPhaseLayerMsvc(
        interface: *const zphy.BroadPhaseLayerInterface,
        out_layer: *zphy.BroadPhaseLayer,
        layer: zphy.ObjectLayer,
    ) callconv(.c) *const zphy.BroadPhaseLayer {
        out_layer.* = getBroadPhaseLayerNative(interface, layer);
        return out_layer;
    }
};

const ObjectVsBroadPhaseLayerFilter = extern struct {
    filter: zphy.ObjectVsBroadPhaseLayerFilter = .init(@This()),

    pub fn shouldCollide(
        _: *const zphy.ObjectVsBroadPhaseLayerFilter,
        layer1: zphy.ObjectLayer,
        layer2: zphy.BroadPhaseLayer,
    ) callconv(.c) bool {
        return switch (layer1) {
            object_layers.non_moving => layer2 == broad_phase_layers.moving,
            object_layers.moving => true,
            else => false,
        };
    }
};

const ObjectLayerPairFilter = extern struct {
    filter: zphy.ObjectLayerPairFilter = .init(@This()),

    pub fn shouldCollide(
        _: *const zphy.ObjectLayerPairFilter,
        object1: zphy.ObjectLayer,
        object2: zphy.ObjectLayer,
    ) callconv(.c) bool {
        return switch (object1) {
            object_layers.non_moving => object2 == object_layers.moving,
            object_layers.moving => true,
            else => false,
        };
    }
};

const BodyMapEntry = struct {
    friendly_id: BodyId,
    jolt_id: zphy.BodyId,
};

pub const World = struct {
    allocator: std.mem.Allocator,
    layer_interface: BroadphaseLayerInterface = .{},
    broadphase_filter: ObjectVsBroadPhaseLayerFilter = .{},
    object_filter: ObjectLayerPairFilter = .{},
    physics_system: *zphy.PhysicsSystem,
    bodies: std.ArrayList(BodyMapEntry),

    pub fn create(allocator: std.mem.Allocator, config: WorldConfig) !*World {
        try retainJolt(allocator);
        errdefer releaseJolt();

        const self = try allocator.create(World);
        errdefer allocator.destroy(self);
        self.* = .{
            .allocator = allocator,
            .physics_system = undefined,
            .bodies = .empty,
        };
        self.physics_system = try zphy.PhysicsSystem.create(
            &self.layer_interface.interface,
            &self.broadphase_filter.filter,
            &self.object_filter.filter,
            .{
                .max_bodies = 4096,
                .num_body_mutexes = 0,
                .max_body_pairs = 4096,
                .max_contact_constraints = 4096,
            },
        );
        self.physics_system.setGravity(vec3ToArray(config.gravity));
        return self;
    }

    pub fn deinit(self: *World) void {
        const body_interface = self.physics_system.getBodyInterfaceMut();
        for (self.bodies.items) |entry| {
            body_interface.removeAndDestroyBody(entry.jolt_id);
        }
        self.bodies.deinit(self.allocator);
        self.physics_system.destroy();
        releaseJolt();
    }

    pub fn addRigidBody(self: *World, friendly_id: BodyId, desc: RigidBodyDesc, config: WorldConfig) !void {
        const shape = try makeShape(desc.shape, desc.mass);
        defer shape.release();

        const object_layer = if (desc.is_static) object_layers.non_moving else object_layers.moving;
        const motion_type: zphy.MotionType = if (desc.is_static) .static else .dynamic;
        const motion_quality: zphy.MotionQuality = if (config.enable_continuous_collision and desc.continuous_collision) .linear_cast else .discrete;

        const body_interface = self.physics_system.getBodyInterfaceMut();
        const jolt_id = try body_interface.createAndAddBody(.{
            .position = vec3ToRVec4(desc.position),
            .linear_velocity = vec3ToVec4(desc.velocity),
            .shape = shape,
            .motion_type = motion_type,
            .object_layer = object_layer,
            .motion_quality = motion_quality,
            .allow_sleeping = desc.can_sleep and config.enable_sleeping,
            .friction = @max(desc.friction, 0.0),
            .restitution = @max(config.restitution, 0.0),
            .user_data = friendly_id,
        }, if (desc.is_static) .dont_activate else .activate);
        errdefer body_interface.removeAndDestroyBody(jolt_id);

        try self.bodies.append(self.allocator, .{
            .friendly_id = friendly_id,
            .jolt_id = jolt_id,
        });
    }

    pub fn optimizeBroadPhase(self: *World) void {
        self.physics_system.optimizeBroadPhase();
    }

    pub fn removeRigidBody(self: *World, friendly_id: BodyId) bool {
        const index = self.findIndex(friendly_id) orelse return false;
        const entry = self.bodies.orderedRemove(index);
        self.physics_system.getBodyInterfaceMut().removeAndDestroyBody(entry.jolt_id);
        return true;
    }

    pub fn step(self: *World, config: WorldConfig, dt: f32) !void {
        self.physics_system.setGravity(vec3ToArray(config.gravity));
        try self.physics_system.update(dt, .{ .collision_steps = 1 });
    }

    pub fn syncBodies(self: *World, bodies: []physics.RigidBody) void {
        const body_interface = self.physics_system.getBodyInterface();
        for (bodies) |*body| {
            const entry = self.entryFor(body.id) orelse continue;
            const position = body_interface.getPosition(entry.jolt_id);
            const velocity = body_interface.getLinearVelocity(entry.jolt_id);
            body.previous_position = body.position;
            body.position = arrayToVec3(position);
            body.velocity = arrayToVec3(velocity);
            body.is_sleeping = !body.is_static and !body_interface.isActive(entry.jolt_id);
        }
    }

    fn findIndex(self: *const World, friendly_id: BodyId) ?usize {
        for (self.bodies.items, 0..) |entry, index| {
            if (entry.friendly_id == friendly_id) return index;
        }
        return null;
    }

    fn entryFor(self: *const World, friendly_id: BodyId) ?BodyMapEntry {
        for (self.bodies.items) |entry| {
            if (entry.friendly_id == friendly_id) return entry;
        }
        return null;
    }
};

fn makeShape(shape: CollisionShape, mass: f32) !*zphy.Shape {
    switch (shape) {
        .sphere => |sphere| {
            const settings = try zphy.SphereShapeSettings.create(sphere.radius);
            defer settings.asShapeSettings().release();
            settings.asConvexShapeSettings().setDensity(sphereDensity(sphere.radius, mass));
            return settings.asShapeSettings().createShape();
        },
        .aabb => |aabb| {
            const settings = try zphy.BoxShapeSettings.create(vec3ToArray(aabb.half_extents));
            defer settings.asShapeSettings().release();
            settings.asConvexShapeSettings().setDensity(boxDensity(aabb.half_extents, mass));
            return settings.asShapeSettings().createShape();
        },
        .heightfield => |heightfield| {
            const settings = try zphy.HeightFieldShapeSettings.create(
                heightfield.heights.ptr,
                heightfield.size,
            );
            defer settings.asShapeSettings().release();
            settings.setBlockSize(heightfield.block_size);
            settings.setOffset(vec3ToArray(heightfield.offset));
            settings.setScale(vec3ToArray(heightfield.scale));
            return settings.asShapeSettings().createShape();
        },
    }
}

fn sphereDensity(radius: f32, mass: f32) f32 {
    const volume = (4.0 / 3.0) * std.math.pi * radius * radius * radius;
    return density(mass, volume);
}

fn boxDensity(half_extents: core.math.Vec3f, mass: f32) f32 {
    return density(mass, half_extents.x * 2.0 * half_extents.y * 2.0 * half_extents.z * 2.0);
}

fn density(mass: f32, volume: f32) f32 {
    if (mass <= std.math.floatEps(f32) or volume <= std.math.floatEps(f32)) return 1.0;
    return mass / volume;
}

fn vec3ToArray(v: core.math.Vec3f) [3]f32 {
    return .{ v.x, v.y, v.z };
}

fn vec3ToVec4(v: core.math.Vec3f) [4]f32 {
    return .{ v.x, v.y, v.z, 0 };
}

fn vec3ToRVec4(v: core.math.Vec3f) [4]zphy.Real {
    return .{ v.x, v.y, v.z, 0 };
}

fn arrayToVec3(v: anytype) core.math.Vec3f {
    return .{ .x = @floatCast(v[0]), .y = @floatCast(v[1]), .z = @floatCast(v[2]) };
}

var global_jolt_ref_count: usize = 0;

fn retainJolt(allocator: std.mem.Allocator) !void {
    if (global_jolt_ref_count == 0) {
        try zphy.init(allocator, .{
            .temp_allocator_size = 16 * 1024 * 1024,
            .max_jobs = 1,
            .max_barriers = 1,
            .num_threads = 0,
        });
    }
    global_jolt_ref_count += 1;
}

fn releaseJolt() void {
    std.debug.assert(global_jolt_ref_count > 0);
    global_jolt_ref_count -= 1;
    if (global_jolt_ref_count == 0) zphy.deinit();
}

pub fn initProbe(allocator: std.mem.Allocator) !void {
    try retainJolt(allocator);
    releaseJolt();
}

test "zphysics initializes Jolt through the Zig package" {
    try initProbe(std.testing.allocator);
}
