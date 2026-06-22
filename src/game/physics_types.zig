const std = @import("std");
const core = @import("../core/mod.zig");

pub const PhysicsBodyKind = enum(u8) {
    static,
    dynamic,
    kinematic,
};

pub const HeightFieldShape = struct {
    size: u32,
    block_size: u32,
    offset: core.math.Vec3f,
    scale: core.math.Vec3f,
    envelope_half: core.math.Vec3f,
    heights: []f32,
};

pub const PhysicsShape = union(enum) {
    aabb: core.math.Vec3f,
    sphere: f32,
    heightfield: HeightFieldShape,

    pub fn fromScale(scale: core.math.Vec3f) PhysicsShape {
        return .{ .aabb = core.math.Vec3f.scale(scale, 0.5) };
    }
};

pub const ScenePhysicsBody = struct {
    kind: PhysicsBodyKind = .dynamic,
    mass: f32 = 1.0,
    velocity: core.math.Vec3f = .{ .x = 0, .y = 0, .z = 0 },
    friction: f32 = 0.6,
    can_sleep: bool = true,
    continuous_collision: bool = true,
    shape: PhysicsShape,

    pub fn deinit(self: *ScenePhysicsBody, allocator: std.mem.Allocator) void {
        switch (self.shape) {
            .heightfield => |*heightfield| {
                allocator.free(heightfield.heights);
                heightfield.heights = &.{};
            },
            else => {},
        }
    }

    pub fn dynamicAabb(scale: core.math.Vec3f) ScenePhysicsBody {
        return .{
            .kind = .dynamic,
            .mass = 1.0,
            .shape = PhysicsShape.fromScale(scale),
        };
    }

    pub fn staticAabb(scale: core.math.Vec3f) ScenePhysicsBody {
        return .{
            .kind = .static,
            .mass = 0.0,
            .shape = PhysicsShape.fromScale(scale),
        };
    }
};
