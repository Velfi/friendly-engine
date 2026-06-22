pub const BodyKind = enum {
    static,
    dynamic,
    kinematic,

    pub fn label(self: BodyKind) []const u8 {
        return switch (self) {
            .static => "Static",
            .dynamic => "Dynamic",
            .kinematic => "Kinematic",
        };
    }
};

pub const ColliderKind = enum {
    box,
    sphere,
    capsule,
    mesh,

    pub fn label(self: ColliderKind) []const u8 {
        return switch (self) {
            .box => "Box",
            .sphere => "Sphere",
            .capsule => "Capsule",
            .mesh => "Mesh",
        };
    }
};

pub const Body = struct {
    kind: BodyKind = .static,
    collider: ColliderKind = .box,
    mass: f32 = 1.0,
    friction: f32 = 0.6,
    restitution: f32 = 0.0,
    trigger: bool = false,
};

pub fn kindFromName(name: []const u8) ?BodyKind {
    const std = @import("std");
    if (std.mem.eql(u8, name, "static")) return .static;
    if (std.mem.eql(u8, name, "dynamic")) return .dynamic;
    if (std.mem.eql(u8, name, "kinematic")) return .kinematic;
    return null;
}

pub fn kindName(kind: BodyKind) []const u8 {
    return switch (kind) {
        .static => "static",
        .dynamic => "dynamic",
        .kinematic => "kinematic",
    };
}

pub fn colliderFromName(name: []const u8) ?ColliderKind {
    const std = @import("std");
    if (std.mem.eql(u8, name, "box")) return .box;
    if (std.mem.eql(u8, name, "sphere")) return .sphere;
    if (std.mem.eql(u8, name, "capsule")) return .capsule;
    if (std.mem.eql(u8, name, "mesh")) return .mesh;
    return null;
}

pub fn colliderName(kind: ColliderKind) []const u8 {
    return switch (kind) {
        .box => "box",
        .sphere => "sphere",
        .capsule => "capsule",
        .mesh => "mesh",
    };
}
