const std = @import("std");
const shared = @import("runtime_shared");

pub const Kind = enum {
    closed_face,
    open_profile,
    path,
    primitive_seed,
};

pub const Source = struct {
    kind: Kind,
    points: []const shared.editor_math.Vec3,
    primitive_kind: shared.geometry.PrimitiveKind = .box,
    primitive_params: shared.geometry.PrimitiveParams = .{},

    pub fn validate(self: Source) !void {
        switch (self.kind) {
            .closed_face => {
                if (self.points.len < 3) return error.NotEnoughShapePoints;
            },
            .open_profile, .path => {
                if (self.points.len < 2) return error.NotEnoughShapePoints;
            },
            .primitive_seed => try validatePrimitiveParams(self.primitive_kind, self.primitive_params),
        }
        for (self.points) |point| {
            if (!std.math.isFinite(point.x) or !std.math.isFinite(point.y) or !std.math.isFinite(point.z)) return error.InvalidShapePoint;
        }
        var i: usize = 1;
        while (i < self.points.len) : (i += 1) {
            if (near(self.points[i - 1], self.points[i])) return error.DuplicateShapePoint;
        }
    }
};

fn validatePrimitiveParams(kind: shared.geometry.PrimitiveKind, params: shared.geometry.PrimitiveParams) !void {
    switch (kind) {
        .box => {
            if (!positiveFinite(params.width) or !positiveFinite(params.height) or !positiveFinite(params.depth)) return error.InvalidPrimitiveSeed;
        },
        .plane => {
            if (!positiveFinite(params.width) or !positiveFinite(params.depth)) return error.InvalidPrimitiveSeed;
        },
        .cylinder => {
            if (!positiveFinite(params.radius) or !positiveFinite(params.height) or params.segments < 3) return error.InvalidPrimitiveSeed;
        },
        .sphere => {
            if (!positiveFinite(params.radius) or params.segments < 4) return error.InvalidPrimitiveSeed;
        },
    }
}

fn positiveFinite(value: f32) bool {
    return std.math.isFinite(value) and value > 0;
}

fn near(a: shared.editor_math.Vec3, b: shared.editor_math.Vec3) bool {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    const dz = a.z - b.z;
    return dx * dx + dy * dy + dz * dz < 0.000001;
}

test "closed face requires three unique points" {
    const pts = [_]shared.editor_math.Vec3{
        .{ .x = 0, .y = 0, .z = 0 },
        .{ .x = 1, .y = 0, .z = 0 },
    };
    try std.testing.expectError(error.NotEnoughShapePoints, (Source{ .kind = .closed_face, .points = &pts }).validate());
}

test "profile accepts two points" {
    const pts = [_]shared.editor_math.Vec3{
        .{ .x = 0, .y = 0, .z = 0 },
        .{ .x = 1, .y = 0, .z = 0 },
    };
    try (Source{ .kind = .open_profile, .points = &pts }).validate();
}

test "path accepts a two point chain" {
    const pts = [_]shared.editor_math.Vec3{
        .{ .x = 0, .y = 0, .z = 0 },
        .{ .x = 1, .y = 0.25, .z = 0.5 },
    };
    try (Source{ .kind = .path, .points = &pts }).validate();
}

test "source validation rejects non-finite points" {
    const pts = [_]shared.editor_math.Vec3{
        .{ .x = 0, .y = 0, .z = 0 },
        .{ .x = std.math.inf(f32), .y = 0, .z = 0 },
    };
    try std.testing.expectError(error.InvalidShapePoint, (Source{ .kind = .open_profile, .points = &pts }).validate());
}

test "primitive seed validates primitive params without points" {
    try (Source{ .kind = .primitive_seed, .points = &.{}, .primitive_kind = .box, .primitive_params = .{ .width = 1, .height = 2, .depth = 3 } }).validate();
    try std.testing.expectError(error.InvalidPrimitiveSeed, (Source{ .kind = .primitive_seed, .points = &.{}, .primitive_kind = .cylinder, .primitive_params = .{ .radius = 1, .height = 2, .segments = 2 } }).validate());
}
