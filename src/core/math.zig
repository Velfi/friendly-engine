const std = @import("std");

pub const Vec2f = struct {
    x: f32,
    y: f32,

    pub fn init(x: f32, y: f32) Vec2f {
        return .{ .x = x, .y = y };
    }

    pub fn add(a: Vec2f, b: Vec2f) Vec2f {
        return .{ .x = a.x + b.x, .y = a.y + b.y };
    }

    pub fn sub(a: Vec2f, b: Vec2f) Vec2f {
        return .{ .x = a.x - b.x, .y = a.y - b.y };
    }

    pub fn scale(v: Vec2f, s: f32) Vec2f {
        return .{ .x = v.x * s, .y = v.y * s };
    }

    pub fn dot(a: Vec2f, b: Vec2f) f32 {
        return (a.x * b.x) + (a.y * b.y);
    }

    pub fn lengthSquared(v: Vec2f) f32 {
        return dot(v, v);
    }

    pub fn length(v: Vec2f) f32 {
        return @sqrt(lengthSquared(v));
    }

    pub fn normalized(v: Vec2f) Vec2f {
        const len = length(v);
        if (len <= std.math.floatEps(f32)) return .{ .x = 0, .y = 0 };
        return scale(v, 1.0 / len);
    }
};

pub const Vec3f = struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn init(x: f32, y: f32, z: f32) Vec3f {
        return .{ .x = x, .y = y, .z = z };
    }

    pub fn add(a: Vec3f, b: Vec3f) Vec3f {
        return .{ .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z };
    }

    pub fn sub(a: Vec3f, b: Vec3f) Vec3f {
        return .{ .x = a.x - b.x, .y = a.y - b.y, .z = a.z - b.z };
    }

    pub fn scale(v: Vec3f, s: f32) Vec3f {
        return .{ .x = v.x * s, .y = v.y * s, .z = v.z * s };
    }

    pub fn dot(a: Vec3f, b: Vec3f) f32 {
        return (a.x * b.x) + (a.y * b.y) + (a.z * b.z);
    }

    pub fn lengthSquared(v: Vec3f) f32 {
        return dot(v, v);
    }

    pub fn length(v: Vec3f) f32 {
        return @sqrt(lengthSquared(v));
    }

    pub fn normalized(v: Vec3f) Vec3f {
        const len = length(v);
        if (len <= std.math.floatEps(f32)) return .{ .x = 0, .y = 0, .z = 0 };
        return scale(v, 1.0 / len);
    }
};

pub fn clamp(value: f32, min_value: f32, max_value: f32) f32 {
    return @max(min_value, @min(max_value, value));
}

pub fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + ((b - a) * t);
}

test "vec operations work" {
    const a = Vec3f.init(1, 2, 3);
    const b = Vec3f.init(4, 5, 6);
    const c = Vec3f.add(a, b);
    try std.testing.expectEqual(@as(f32, 5), c.x);
    try std.testing.expectEqual(@as(f32, 7), c.y);
    try std.testing.expectEqual(@as(f32, 9), c.z);
    try std.testing.expectApproxEqAbs(@as(f32, 32), Vec3f.dot(a, b), 0.0001);
}

test "normalized handles near-zero vectors" {
    const n = Vec2f.normalized(.{ .x = 0, .y = 0 });
    try std.testing.expectEqual(@as(f32, 0), n.x);
    try std.testing.expectEqual(@as(f32, 0), n.y);
}

test "clamp and lerp utilities work" {
    try std.testing.expectEqual(@as(f32, 4), clamp(5, 0, 4));
    try std.testing.expectApproxEqAbs(@as(f32, 2.5), lerp(0, 10, 0.25), 0.0001);
}
