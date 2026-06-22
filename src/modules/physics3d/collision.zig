const std = @import("std");
const core = @import("../../core/mod.zig");
const physics = @import("mod.zig");

const RigidBody = physics.RigidBody;
const Sphere = physics.Sphere;
const Aabb = physics.Aabb;
const ContactManifold = physics.ContactManifold;

pub fn integrateSemiImplicitEuler(bodies: []RigidBody, gravity: core.math.Vec3f, dt: f32) usize {
    var integrated_bodies: usize = 0;
    for (bodies) |*body| {
        body.previous_position = body.position;
        if (body.is_static or body.is_sleeping) continue;
        body.velocity = core.math.Vec3f.add(body.velocity, core.math.Vec3f.scale(gravity, dt));
        body.position = core.math.Vec3f.add(body.position, core.math.Vec3f.scale(body.velocity, dt));
        integrated_bodies += 1;
    }
    return integrated_bodies;
}

pub fn detectContact(a: RigidBody, b: RigidBody) ?ContactManifold {
    return switch (a.shape) {
        .sphere => |a_sphere| switch (b.shape) {
            .sphere => |b_sphere| sphereSphereContact(a, a_sphere, b, b_sphere),
            .aabb => |b_aabb| sphereAabbContact(a, a_sphere, b, b_aabb),
            .heightfield => |b_heightfield| sphereAabbContact(a, a_sphere, b, heightfieldEnvelope(b_heightfield)),
        },
        .aabb => |a_aabb| switch (b.shape) {
            .sphere => |b_sphere| invertContact(sphereAabbContact(b, b_sphere, a, a_aabb)),
            .aabb => |b_aabb| aabbAabbContact(a, a_aabb, b, b_aabb),
            .heightfield => |b_heightfield| aabbAabbContact(a, a_aabb, b, heightfieldEnvelope(b_heightfield)),
        },
        .heightfield => |a_heightfield| switch (b.shape) {
            .sphere => |b_sphere| invertContact(sphereAabbContact(b, b_sphere, a, heightfieldEnvelope(a_heightfield))),
            .aabb => |b_aabb| invertContact(aabbAabbContact(b, b_aabb, a, heightfieldEnvelope(a_heightfield))),
            .heightfield => |b_heightfield| aabbAabbContact(
                a,
                heightfieldEnvelope(a_heightfield),
                b,
                heightfieldEnvelope(b_heightfield),
            ),
        },
    };
}

fn heightfieldEnvelope(heightfield: physics.HeightField) Aabb {
    return .{ .half_extents = heightfield.envelope_half };
}

fn sphereSphereContact(a_body: RigidBody, a: Sphere, b_body: RigidBody, b: Sphere) ?ContactManifold {
    const delta = core.math.Vec3f.sub(b_body.position, a_body.position);
    const dist_sq = core.math.Vec3f.lengthSquared(delta);
    const radii = a.radius + b.radius;
    if (dist_sq > radii * radii) return null;
    const dist = @sqrt(dist_sq);
    const normal = if (dist <= std.math.floatEps(f32))
        core.math.Vec3f{ .x = 0, .y = 1, .z = 0 }
    else
        core.math.Vec3f.scale(delta, 1.0 / dist);
    return .{
        .a = a_body.id,
        .b = b_body.id,
        .normal = normal,
        .depth = radii - dist,
    };
}

fn aabbAabbContact(a_body: RigidBody, a: Aabb, b_body: RigidBody, b: Aabb) ?ContactManifold {
    const delta = core.math.Vec3f.sub(b_body.position, a_body.position);
    const overlap_x = (a.half_extents.x + b.half_extents.x) - @abs(delta.x);
    const overlap_y = (a.half_extents.y + b.half_extents.y) - @abs(delta.y);
    const overlap_z = (a.half_extents.z + b.half_extents.z) - @abs(delta.z);
    if (overlap_x < 0 or overlap_y < 0 or overlap_z < 0) return null;

    var normal = core.math.Vec3f{ .x = if (delta.x >= 0) 1 else -1, .y = 0, .z = 0 };
    var depth = overlap_x;
    if (overlap_y < depth) {
        normal = .{ .x = 0, .y = if (delta.y >= 0) 1 else -1, .z = 0 };
        depth = overlap_y;
    }
    if (overlap_z < depth) {
        normal = .{ .x = 0, .y = 0, .z = if (delta.z >= 0) 1 else -1 };
        depth = overlap_z;
    }
    return .{
        .a = a_body.id,
        .b = b_body.id,
        .normal = normal,
        .depth = depth,
    };
}

fn sphereAabbContact(sphere_body: RigidBody, sphere: Sphere, aabb_body: RigidBody, aabb: Aabb) ?ContactManifold {
    const min = core.math.Vec3f.sub(aabb_body.position, aabb.half_extents);
    const max = core.math.Vec3f.add(aabb_body.position, aabb.half_extents);
    const closest = core.math.Vec3f{
        .x = core.math.clamp(sphere_body.position.x, min.x, max.x),
        .y = core.math.clamp(sphere_body.position.y, min.y, max.y),
        .z = core.math.clamp(sphere_body.position.z, min.z, max.z),
    };
    const delta_to_sphere = core.math.Vec3f.sub(sphere_body.position, closest);
    const dist_sq = core.math.Vec3f.lengthSquared(delta_to_sphere);
    if (dist_sq > sphere.radius * sphere.radius) return null;

    if (dist_sq > std.math.floatEps(f32)) {
        const dist = @sqrt(dist_sq);
        return .{
            .a = sphere_body.id,
            .b = aabb_body.id,
            .normal = core.math.Vec3f.scale(delta_to_sphere, -1.0 / dist),
            .depth = sphere.radius - dist,
        };
    }

    const to_center = core.math.Vec3f.sub(sphere_body.position, aabb_body.position);
    const face_x = aabb.half_extents.x - @abs(to_center.x);
    const face_y = aabb.half_extents.y - @abs(to_center.y);
    const face_z = aabb.half_extents.z - @abs(to_center.z);
    var normal = core.math.Vec3f{ .x = if (to_center.x >= 0) -1 else 1, .y = 0, .z = 0 };
    var depth = sphere.radius + face_x;
    if (face_y < face_x and face_y <= face_z) {
        normal = .{ .x = 0, .y = if (to_center.y >= 0) -1 else 1, .z = 0 };
        depth = sphere.radius + face_y;
    } else if (face_z < face_x and face_z < face_y) {
        normal = .{ .x = 0, .y = 0, .z = if (to_center.z >= 0) -1 else 1 };
        depth = sphere.radius + face_z;
    }
    return .{
        .a = sphere_body.id,
        .b = aabb_body.id,
        .normal = normal,
        .depth = depth,
    };
}

fn invertContact(contact: ?ContactManifold) ?ContactManifold {
    const c = contact orelse return null;
    return .{
        .a = c.b,
        .b = c.a,
        .normal = core.math.Vec3f.scale(c.normal, -1),
        .depth = c.depth,
    };
}

pub fn resolveContact(
    a: *RigidBody,
    b: *RigidBody,
    normal: core.math.Vec3f,
    depth: f32,
    restitution: f32,
    world_friction: f32,
    correction_percent: f32,
    slop: f32,
) bool {
    const inv_mass_sum = a.inv_mass + b.inv_mass;
    if (inv_mass_sum <= std.math.floatEps(f32)) return false;

    const correction_depth = @max(depth - slop, 0.0);
    if (correction_depth > 0) {
        const correction = core.math.Vec3f.scale(normal, correction_depth * correction_percent / inv_mass_sum);
        if (a.inv_mass > 0) {
            a.position = core.math.Vec3f.sub(a.position, core.math.Vec3f.scale(correction, a.inv_mass));
        }
        if (b.inv_mass > 0) {
            b.position = core.math.Vec3f.add(b.position, core.math.Vec3f.scale(correction, b.inv_mass));
        }
    }

    const relative_velocity = core.math.Vec3f.sub(b.velocity, a.velocity);
    const velocity_along_normal = core.math.Vec3f.dot(relative_velocity, normal);
    if (velocity_along_normal > 0) return true;

    const impulse_scalar = -(1.0 + restitution) * velocity_along_normal / inv_mass_sum;
    const impulse = core.math.Vec3f.scale(normal, impulse_scalar);
    if (a.inv_mass > 0) {
        a.velocity = core.math.Vec3f.sub(a.velocity, core.math.Vec3f.scale(impulse, a.inv_mass));
    }
    if (b.inv_mass > 0) {
        b.velocity = core.math.Vec3f.add(b.velocity, core.math.Vec3f.scale(impulse, b.inv_mass));
    }
    if (@abs(impulse_scalar) > std.math.floatEps(f32)) {
        if (a.inv_mass > 0) wakeBody(a);
        if (b.inv_mass > 0) wakeBody(b);
    }

    const post_relative_velocity = core.math.Vec3f.sub(b.velocity, a.velocity);
    const tangent_speed = core.math.Vec3f.dot(post_relative_velocity, normal);
    const tangent = core.math.Vec3f.sub(post_relative_velocity, core.math.Vec3f.scale(normal, tangent_speed));
    const tangent_len_sq = core.math.Vec3f.lengthSquared(tangent);
    if (tangent_len_sq > std.math.floatEps(f32)) {
        const tangent_normal = core.math.Vec3f.scale(tangent, 1.0 / @sqrt(tangent_len_sq));
        const tangent_impulse_scalar = -core.math.Vec3f.dot(post_relative_velocity, tangent_normal) / inv_mass_sum;
        const friction = @sqrt(@max(a.friction, 0.0) * @max(b.friction, 0.0)) * @max(world_friction, 0.0);
        const max_friction = impulse_scalar * friction;
        const clamped_tangent_impulse = core.math.clamp(tangent_impulse_scalar, -max_friction, max_friction);
        const friction_impulse = core.math.Vec3f.scale(tangent_normal, clamped_tangent_impulse);
        if (a.inv_mass > 0) {
            a.velocity = core.math.Vec3f.sub(a.velocity, core.math.Vec3f.scale(friction_impulse, a.inv_mass));
        }
        if (b.inv_mass > 0) {
            b.velocity = core.math.Vec3f.add(b.velocity, core.math.Vec3f.scale(friction_impulse, b.inv_mass));
        }
        if (@abs(clamped_tangent_impulse) > std.math.floatEps(f32)) {
            if (a.inv_mass > 0) wakeBody(a);
            if (b.inv_mass > 0) wakeBody(b);
        }
    }
    return true;
}

pub const SweepHit = struct {
    time: f32,
    normal: core.math.Vec3f,
};

pub fn sweepContact(moving: RigidBody, target: RigidBody, movement: core.math.Vec3f) ?SweepHit {
    return switch (moving.shape) {
        .sphere => |moving_sphere| switch (target.shape) {
            .sphere => |target_sphere| sweepSphereSphere(moving, moving_sphere, target, target_sphere, movement),
            .aabb => |target_aabb| sweepPointAabb(
                moving.previous_position,
                movement,
                core.math.Vec3f.sub(target.position, growAabb(target_aabb, moving_sphere.radius)),
                core.math.Vec3f.add(target.position, growAabb(target_aabb, moving_sphere.radius)),
            ),
            .heightfield => |target_heightfield| sweepPointAabb(
                moving.previous_position,
                movement,
                core.math.Vec3f.sub(target.position, growAabb(heightfieldEnvelope(target_heightfield), moving_sphere.radius)),
                core.math.Vec3f.add(target.position, growAabb(heightfieldEnvelope(target_heightfield), moving_sphere.radius)),
            ),
        },
        .aabb => |moving_aabb| switch (target.shape) {
            .sphere => |target_sphere| sweepPointAabb(
                moving.previous_position,
                movement,
                core.math.Vec3f.sub(target.position, growAabb(moving_aabb, target_sphere.radius)),
                core.math.Vec3f.add(target.position, growAabb(moving_aabb, target_sphere.radius)),
            ),
            .aabb => |target_aabb| sweepPointAabb(
                moving.previous_position,
                movement,
                core.math.Vec3f.sub(target.position, expandAabb(target_aabb, moving_aabb.half_extents)),
                core.math.Vec3f.add(target.position, expandAabb(target_aabb, moving_aabb.half_extents)),
            ),
            .heightfield => |target_heightfield| sweepPointAabb(
                moving.previous_position,
                movement,
                core.math.Vec3f.sub(target.position, expandAabb(heightfieldEnvelope(target_heightfield), moving_aabb.half_extents)),
                core.math.Vec3f.add(target.position, expandAabb(heightfieldEnvelope(target_heightfield), moving_aabb.half_extents)),
            ),
        },
        .heightfield => |moving_heightfield| switch (target.shape) {
            .sphere => |target_sphere| sweepPointAabb(
                moving.previous_position,
                movement,
                core.math.Vec3f.sub(target.position, growAabb(heightfieldEnvelope(moving_heightfield), target_sphere.radius)),
                core.math.Vec3f.add(target.position, growAabb(heightfieldEnvelope(moving_heightfield), target_sphere.radius)),
            ),
            .aabb => |target_aabb| sweepPointAabb(
                moving.previous_position,
                movement,
                core.math.Vec3f.sub(target.position, expandAabb(target_aabb, heightfieldEnvelope(moving_heightfield).half_extents)),
                core.math.Vec3f.add(target.position, expandAabb(target_aabb, heightfieldEnvelope(moving_heightfield).half_extents)),
            ),
            .heightfield => |target_heightfield| sweepPointAabb(
                moving.previous_position,
                movement,
                core.math.Vec3f.sub(
                    target.position,
                    expandAabb(heightfieldEnvelope(target_heightfield), heightfieldEnvelope(moving_heightfield).half_extents),
                ),
                core.math.Vec3f.add(
                    target.position,
                    expandAabb(heightfieldEnvelope(target_heightfield), heightfieldEnvelope(moving_heightfield).half_extents),
                ),
            ),
        },
    };
}

fn growAabb(aabb: Aabb, amount: f32) core.math.Vec3f {
    return .{
        .x = aabb.half_extents.x + amount,
        .y = aabb.half_extents.y + amount,
        .z = aabb.half_extents.z + amount,
    };
}

fn expandAabb(aabb: Aabb, amount: core.math.Vec3f) core.math.Vec3f {
    return .{
        .x = aabb.half_extents.x + amount.x,
        .y = aabb.half_extents.y + amount.y,
        .z = aabb.half_extents.z + amount.z,
    };
}

fn sweepSphereSphere(
    moving_body: RigidBody,
    moving: Sphere,
    target_body: RigidBody,
    target: Sphere,
    movement: core.math.Vec3f,
) ?SweepHit {
    const radius = moving.radius + target.radius;
    const origin_to_target = core.math.Vec3f.sub(moving_body.previous_position, target_body.position);
    const a = core.math.Vec3f.dot(movement, movement);
    if (a <= std.math.floatEps(f32)) return null;
    const b = 2.0 * core.math.Vec3f.dot(origin_to_target, movement);
    const c = core.math.Vec3f.dot(origin_to_target, origin_to_target) - (radius * radius);
    if (c <= 0.0) return null;
    const discriminant = (b * b) - (4.0 * a * c);
    if (discriminant < 0.0) return null;
    const time = (-b - @sqrt(discriminant)) / (2.0 * a);
    if (time < 0.0 or time > 1.0) return null;
    const hit_position = core.math.Vec3f.add(moving_body.previous_position, core.math.Vec3f.scale(movement, time));
    const normal = core.math.Vec3f.normalized(core.math.Vec3f.sub(hit_position, target_body.position));
    return .{ .time = time, .normal = normal };
}

fn sweepPointAabb(
    origin: core.math.Vec3f,
    movement: core.math.Vec3f,
    min: core.math.Vec3f,
    max: core.math.Vec3f,
) ?SweepHit {
    var entry_time: f32 = 0.0;
    var exit_time: f32 = 1.0;
    var hit_normal = core.math.Vec3f{ .x = 0, .y = 0, .z = 0 };

    if (!clipSweepAxis(origin.x, movement.x, min.x, max.x, &entry_time, &exit_time, .{ .x = if (movement.x > 0) -1 else 1, .y = 0, .z = 0 }, &hit_normal)) return null;
    if (!clipSweepAxis(origin.y, movement.y, min.y, max.y, &entry_time, &exit_time, .{ .x = 0, .y = if (movement.y > 0) -1 else 1, .z = 0 }, &hit_normal)) return null;
    if (!clipSweepAxis(origin.z, movement.z, min.z, max.z, &entry_time, &exit_time, .{ .x = 0, .y = 0, .z = if (movement.z > 0) -1 else 1 }, &hit_normal)) return null;

    if (entry_time < 0.0 or entry_time > 1.0) return null;
    return .{ .time = entry_time, .normal = hit_normal };
}

fn clipSweepAxis(
    origin: f32,
    movement: f32,
    min: f32,
    max: f32,
    entry_time: *f32,
    exit_time: *f32,
    axis_normal: core.math.Vec3f,
    hit_normal: *core.math.Vec3f,
) bool {
    if (@abs(movement) <= std.math.floatEps(f32)) {
        return origin >= min and origin <= max;
    }

    var axis_entry = (min - origin) / movement;
    var axis_exit = (max - origin) / movement;
    if (axis_entry > axis_exit) std.mem.swap(f32, &axis_entry, &axis_exit);

    if (axis_entry > entry_time.*) {
        entry_time.* = axis_entry;
        hit_normal.* = axis_normal;
    }
    if (axis_exit < exit_time.*) {
        exit_time.* = axis_exit;
    }
    return entry_time.* <= exit_time.*;
}

pub fn wakeBody(body: *RigidBody) void {
    body.is_sleeping = false;
    body.sleep_timer = 0.0;
}
