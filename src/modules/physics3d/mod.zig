const std = @import("std");
const core = @import("../../core/mod.zig");
const framework = @import("../../framework/mod.zig");

const collision = @import("collision.zig");
pub const zphysics_backend = @import("zphysics_backend.zig");
pub const character = @import("character.zig");
pub const module_name = "gem.physics3d";
pub const BodyId = u64;

pub const IntegrationMode = enum {
    semi_implicit_euler,
};

pub const Sphere = struct {
    radius: f32 = 0.5,
};

pub const Aabb = struct {
    half_extents: core.math.Vec3f = .{ .x = 0.5, .y = 0.5, .z = 0.5 },
};

pub const HeightField = struct {
    size: u32,
    block_size: u32,
    offset: core.math.Vec3f,
    scale: core.math.Vec3f,
    envelope_half: core.math.Vec3f,
    heights: []const f32,
};

pub const CollisionShape = union(enum) {
    sphere: Sphere,
    aabb: Aabb,
    heightfield: HeightField,
};

pub const WorldConfig = struct {
    gravity: core.math.Vec3f = .{ .x = 0.0, .y = -9.81, .z = 0.0 },
    fixed_dt: f32 = 1.0 / 60.0,
    max_substeps: u8 = 4,
    integration_mode: IntegrationMode = .semi_implicit_euler,
    enable_broadphase: bool = true,
    restitution: f32 = 0.0,
    friction: f32 = 0.6,
    position_correction_percent: f32 = 0.8,
    penetration_slop: f32 = 0.001,
    sleep_linear_threshold: f32 = 0.05,
    sleep_delay: f32 = 0.5,
    enable_sleeping: bool = true,
    enable_continuous_collision: bool = true,
    ccd_contact_offset: f32 = 0.0001,
};

pub const RigidBodyDesc = struct {
    position: core.math.Vec3f = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
    velocity: core.math.Vec3f = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
    mass: f32 = 1.0,
    is_static: bool = false,
    friction: f32 = 0.6,
    can_sleep: bool = true,
    continuous_collision: bool = true,
    shape: CollisionShape = .{ .sphere = .{} },
};

pub const RigidBody = struct {
    id: BodyId,
    position: core.math.Vec3f,
    previous_position: core.math.Vec3f,
    velocity: core.math.Vec3f,
    inv_mass: f32,
    is_static: bool,
    friction: f32,
    can_sleep: bool,
    is_sleeping: bool,
    sleep_timer: f32,
    continuous_collision: bool,
    shape: CollisionShape,
};

pub const ContactPair = struct {
    a: BodyId,
    b: BodyId,
};

pub const ContactManifold = struct {
    a: BodyId,
    b: BodyId,
    normal: core.math.Vec3f,
    depth: f32,
};

pub const StepStats = struct {
    integrated_bodies: usize = 0,
    potential_pairs: usize = 0,
    resolved_contacts: usize = 0,
    executed_substeps: usize = 0,
    sleeping_bodies: usize = 0,
    ccd_hits: usize = 0,
};

pub const World = struct {
    allocator: std.mem.Allocator,
    config: WorldConfig,
    id_generator: core.IdGenerator,
    bodies: std.ArrayList(RigidBody),
    contacts: std.ArrayList(ContactPair),
    manifolds: std.ArrayList(ContactManifold),
    backend: ?*zphysics_backend.World = null,
    accumulator: f32 = 0.0,
    tick: u64 = 0,

    pub fn init(allocator: std.mem.Allocator, config: WorldConfig) World {
        return .{
            .allocator = allocator,
            .config = config,
            .id_generator = core.IdGenerator.init(1),
            .bodies = .empty,
            .contacts = .empty,
            .manifolds = .empty,
        };
    }

    pub fn deinit(self: *World) void {
        if (self.backend) |backend| {
            backend.deinit();
            self.allocator.destroy(backend);
        }
        self.manifolds.deinit(self.allocator);
        self.contacts.deinit(self.allocator);
        self.bodies.deinit(self.allocator);
    }

    pub fn addRigidBody(self: *World, desc: RigidBodyDesc) !BodyId {
        try self.ensureBackend();
        const body_id: BodyId = self.id_generator.nextId();
        const inv_mass = if (desc.is_static or desc.mass <= std.math.floatEps(f32)) 0.0 else 1.0 / desc.mass;
        try self.bodies.append(self.allocator, .{
            .id = body_id,
            .position = desc.position,
            .previous_position = desc.position,
            .velocity = desc.velocity,
            .inv_mass = inv_mass,
            .is_static = desc.is_static,
            .friction = @max(desc.friction, 0.0),
            .can_sleep = desc.can_sleep,
            .is_sleeping = false,
            .sleep_timer = 0.0,
            .continuous_collision = desc.continuous_collision,
            .shape = desc.shape,
        });
        errdefer _ = self.bodies.pop();
        try self.backend.?.addRigidBody(body_id, desc, self.config);
        return body_id;
    }

    pub fn optimizeBroadPhase(self: *World) void {
        if (self.backend) |backend| backend.optimizeBroadPhase();
    }

    pub fn removeRigidBody(self: *World, body_id: BodyId) bool {
        for (self.bodies.items, 0..) |body, idx| {
            if (body.id == body_id) {
                if (self.backend) |backend| _ = backend.removeRigidBody(body_id);
                _ = self.bodies.orderedRemove(idx);
                return true;
            }
        }
        return false;
    }

    pub fn getBody(self: *const World, body_id: BodyId) ?RigidBody {
        for (self.bodies.items) |body| {
            if (body.id == body_id) return body;
        }
        return null;
    }

    pub fn getBodyPtr(self: *World, body_id: BodyId) ?*RigidBody {
        for (self.bodies.items) |*body| {
            if (body.id == body_id) return body;
        }
        return null;
    }

    pub fn getContacts(self: *const World) []const ContactPair {
        return self.contacts.items;
    }

    pub fn stepFixed(self: *World) !StepStats {
        return self.step(self.config.fixed_dt);
    }

    pub fn step(self: *World, dt: f32) !StepStats {
        try self.ensureBackend();
        var stats = StepStats{};
        self.accumulator += dt;
        var substeps: u8 = 0;
        while (self.accumulator >= self.config.fixed_dt and substeps < self.config.max_substeps) {
            stats.integrated_bodies += self.dynamicAwakeBodyCount();
            try self.backend.?.step(self.config, self.config.fixed_dt);
            self.backend.?.syncBodies(self.bodies.items);
            stats.potential_pairs += try self.runBroadphase();
            stats.resolved_contacts += self.dynamicContactCount();
            stats.sleeping_bodies = self.updateSleeping(self.config.fixed_dt);
            self.accumulator -= self.config.fixed_dt;
            self.tick += 1;
            substeps += 1;
        }
        stats.executed_substeps = substeps;
        return stats;
    }

    pub fn ensureJoltSystem(self: *World) !*zphysics_backend.zphy.PhysicsSystem {
        try self.ensureBackend();
        return self.backend.?.physics_system;
    }

    fn ensureBackend(self: *World) !void {
        if (self.backend != null) return;
        const backend = try zphysics_backend.World.create(self.allocator, self.config);
        self.backend = backend;
    }

    fn runBroadphase(self: *World) !usize {
        self.contacts.clearRetainingCapacity();
        self.manifolds.clearRetainingCapacity();
        if (!self.config.enable_broadphase) return 0;

        var overlaps: usize = 0;
        var i: usize = 0;
        while (i < self.bodies.items.len) : (i += 1) {
            var j: usize = i + 1;
            while (j < self.bodies.items.len) : (j += 1) {
                const a = self.bodies.items[i];
                const b = self.bodies.items[j];
                if (collision.detectContact(a, b)) |contact| {
                    try self.contacts.append(self.allocator, .{ .a = a.id, .b = b.id });
                    try self.manifolds.append(self.allocator, contact);
                    overlaps += 1;
                }
            }
        }
        return overlaps;
    }

    fn solveContacts(self: *World) usize {
        var resolved: usize = 0;
        for (self.manifolds.items) |contact| {
            const a_index = self.findBodyIndex(contact.a) orelse continue;
            const b_index = self.findBodyIndex(contact.b) orelse continue;
            if (collision.resolveContact(
                &self.bodies.items[a_index],
                &self.bodies.items[b_index],
                contact.normal,
                contact.depth,
                self.config.restitution,
                self.config.friction,
                self.config.position_correction_percent,
                self.config.penetration_slop,
            )) {
                resolved += 1;
            }
        }
        return resolved;
    }

    fn dynamicAwakeBodyCount(self: *const World) usize {
        var count: usize = 0;
        for (self.bodies.items) |body| {
            if (!body.is_static and body.inv_mass > 0 and !body.is_sleeping) count += 1;
        }
        return count;
    }

    fn dynamicContactCount(self: *const World) usize {
        var count: usize = 0;
        for (self.manifolds.items) |contact| {
            const a = self.getBody(contact.a) orelse continue;
            const b = self.getBody(contact.b) orelse continue;
            if (!a.is_static or !b.is_static) count += 1;
        }
        return count;
    }

    fn runContinuousCollision(self: *World, dt: f32) usize {
        _ = dt;
        var hit_count: usize = 0;
        for (self.bodies.items, 0..) |*body, body_index| {
            if (body.is_static or body.inv_mass <= 0 or body.is_sleeping or !body.continuous_collision) continue;
            const sweep = core.math.Vec3f.sub(body.position, body.previous_position);
            if (core.math.Vec3f.lengthSquared(sweep) <= std.math.floatEps(f32)) continue;

            var best: ?collision.SweepHit = null;
            for (self.bodies.items, 0..) |target, target_index| {
                if (body_index == target_index or target.inv_mass > 0) continue;
                const hit = collision.sweepContact(body.*, target, sweep) orelse continue;
                if (best == null or hit.time < best.?.time) best = hit;
            }

            if (best) |hit| {
                const safe_time = @max(hit.time - self.config.ccd_contact_offset, 0.0);
                body.position = core.math.Vec3f.add(body.previous_position, core.math.Vec3f.scale(sweep, safe_time));
                const normal_speed = core.math.Vec3f.dot(body.velocity, hit.normal);
                if (normal_speed < 0.0) {
                    body.velocity = core.math.Vec3f.sub(body.velocity, core.math.Vec3f.scale(hit.normal, normal_speed));
                }
                collision.wakeBody(body);
                hit_count += 1;
            }
        }
        return hit_count;
    }

    fn updateSleeping(self: *World, dt: f32) usize {
        if (!self.config.enable_sleeping) return 0;

        var sleeping: usize = 0;
        const threshold_sq = self.config.sleep_linear_threshold * self.config.sleep_linear_threshold;
        for (self.bodies.items) |*body| {
            if (body.is_static or body.inv_mass <= 0 or !body.can_sleep) continue;
            if (core.math.Vec3f.lengthSquared(body.velocity) <= threshold_sq) {
                body.sleep_timer += dt;
                if (body.sleep_timer >= self.config.sleep_delay) {
                    body.velocity = .{ .x = 0, .y = 0, .z = 0 };
                    body.is_sleeping = true;
                }
            } else {
                collision.wakeBody(body);
            }
            if (body.is_sleeping) sleeping += 1;
        }
        return sleeping;
    }

    fn findBodyIndex(self: *const World, body_id: BodyId) ?usize {
        for (self.bodies.items, 0..) |body, idx| {
            if (body.id == body_id) return idx;
        }
        return null;
    }
};

pub fn register(registry: anytype) !void {
    _ = registry;
}

pub fn start(world: *framework.World) !void {
    try world.notifications.publish("gem.physics3d.started", "{}");
}

pub fn stop(world: *framework.World) !void {
    try world.notifications.publish("gem.physics3d.stopped", "{}");
}

comptime {
    _ = @import("mod_tests.zig");
}
