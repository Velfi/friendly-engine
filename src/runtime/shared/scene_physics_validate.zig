const std = @import("std");
const scene_physics = @import("scene_physics.zig");

pub const ValidationError = error{
    UnsupportedColliderCapsule,
    UnsupportedColliderMesh,
    UnsupportedDynamicStaticCollider,
    UnsupportedKinematicMeshCollider,
    InvalidPhysicsMass,
};

pub fn validateBody(body: scene_physics.Body) ValidationError!void {
    switch (body.collider) {
        .capsule => return error.UnsupportedColliderCapsule,
        .mesh => return error.UnsupportedColliderMesh,
        .box, .sphere => {},
    }
    if (body.kind == .dynamic and body.mass <= 0.0) return error.InvalidPhysicsMass;
    if (body.kind == .kinematic and body.collider == .mesh) return error.UnsupportedKinematicMeshCollider;
    if (body.kind == .static and body.collider == .sphere and body.mass > 0.0) return error.UnsupportedDynamicStaticCollider;
}

pub fn errorMessage(err: ValidationError) []const u8 {
    return switch (err) {
        error.UnsupportedColliderCapsule => "Capsule colliders are not supported at runtime yet",
        error.UnsupportedColliderMesh => "Mesh colliders are not supported at runtime yet",
        error.UnsupportedDynamicStaticCollider => "Static bodies cannot use dynamic sphere mass settings",
        error.UnsupportedKinematicMeshCollider => "Kinematic bodies cannot use mesh colliders",
        error.InvalidPhysicsMass => "Dynamic bodies require mass greater than zero",
    };
}

test "physics validation rejects unsupported colliders" {
    try std.testing.expectError(
        error.UnsupportedColliderCapsule,
        validateBody(.{ .collider = .capsule }),
    );
    try std.testing.expectError(
        error.UnsupportedColliderMesh,
        validateBody(.{ .collider = .mesh }),
    );
}

test "physics validation rejects invalid dynamic mass" {
    try std.testing.expectError(
        error.InvalidPhysicsMass,
        validateBody(.{ .kind = .dynamic, .mass = 0.0, .collider = .box }),
    );
}

test "physics validation accepts box and sphere" {
    try validateBody(.{ .kind = .static, .collider = .box });
    try validateBody(.{ .kind = .dynamic, .mass = 1.0, .collider = .sphere });
}
