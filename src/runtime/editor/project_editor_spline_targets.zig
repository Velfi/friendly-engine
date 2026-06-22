const std = @import("std");
const shared = @import("runtime_shared");

const editor_math = shared.editor_math;

pub const Target = struct {
    position: editor_math.Vec3,
    yaw: f32,
    distance: f32,
};

pub const StairStep = struct {
    position: editor_math.Vec3,
    yaw: f32,
    size: editor_math.Vec3,
    index: u32,
};

pub fn sampleArrayTargets(
    allocator: std.mem.Allocator,
    points: []const editor_math.Vec3,
    spacing: f32,
    include_end: bool,
) ![]Target {
    if (points.len < 2) return error.SplineNeedsTwoPoints;
    if (spacing <= 0) return error.InvalidSplineSpacing;

    const length = polylineLength(points);
    if (length <= 0) return error.InvalidSplineLength;

    var targets: std.ArrayList(Target) = .empty;
    errdefer targets.deinit(allocator);

    var distance: f32 = 0;
    while (distance <= length) : (distance += spacing) {
        try targets.append(allocator, try sampleAtDistance(points, @min(distance, length)));
    }

    if (include_end and targets.items[targets.items.len - 1].distance < length - 0.001) {
        try targets.append(allocator, try sampleAtDistance(points, length));
    }

    return targets.toOwnedSlice(allocator);
}

pub fn sampleStairSteps(
    allocator: std.mem.Allocator,
    points: []const editor_math.Vec3,
    tread_depth: f32,
    riser_height: f32,
    width: f32,
) ![]StairStep {
    if (points.len < 2) return error.SplineNeedsTwoPoints;
    if (tread_depth <= 0 or riser_height <= 0 or width <= 0) return error.InvalidStairDimensions;

    const length = polylineLength(points);
    if (length <= 0) return error.InvalidSplineLength;

    const count = @max(@as(u32, 1), @as(u32, @intFromFloat(@floor(length / tread_depth))));
    var steps = try allocator.alloc(StairStep, count);
    errdefer allocator.free(steps);

    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const center_distance = @min((@as(f32, @floatFromInt(i)) + 0.5) * tread_depth, length);
        const target = try sampleAtDistance(points, center_distance);
        steps[i] = .{
            .position = .{
                .x = target.position.x,
                .y = target.position.y + (@as(f32, @floatFromInt(i)) + 0.5) * riser_height,
                .z = target.position.z,
            },
            .yaw = target.yaw,
            .size = .{ .x = width, .y = riser_height, .z = tread_depth },
            .index = i,
        };
    }

    return steps;
}

fn sampleAtDistance(points: []const editor_math.Vec3, target_distance: f32) !Target {
    var walked: f32 = 0;
    var i: usize = 0;
    while (i + 1 < points.len) : (i += 1) {
        const a = points[i];
        const b = points[i + 1];
        const delta = editor_math.Vec3.sub(b, a);
        const segment_length = editor_math.Vec3.length(delta);
        if (segment_length <= 0) continue;
        if (walked + segment_length >= target_distance) {
            const t = std.math.clamp((target_distance - walked) / segment_length, 0, 1);
            const position = editor_math.Vec3.add(a, editor_math.Vec3.scale(delta, t));
            return .{
                .position = position,
                .yaw = std.math.atan2(delta.x, delta.z),
                .distance = target_distance,
            };
        }
        walked += segment_length;
    }

    const last = points[points.len - 1];
    const prev = points[points.len - 2];
    const delta = editor_math.Vec3.sub(last, prev);
    return .{
        .position = last,
        .yaw = std.math.atan2(delta.x, delta.z),
        .distance = walked,
    };
}

fn polylineLength(points: []const editor_math.Vec3) f32 {
    var length: f32 = 0;
    var i: usize = 0;
    while (i + 1 < points.len) : (i += 1) {
        length += editor_math.Vec3.length(editor_math.Vec3.sub(points[i + 1], points[i]));
    }
    return length;
}

test "array targets follow spline spacing and orientation" {
    const points = [_]editor_math.Vec3{
        .{ .x = 0, .y = 0, .z = 0 },
        .{ .x = 0, .y = 0, .z = 5 },
    };
    const targets = try sampleArrayTargets(std.testing.allocator, &points, 2.0, true);
    defer std.testing.allocator.free(targets);

    try std.testing.expectEqual(@as(usize, 4), targets.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0), targets[0].position.z, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2), targets[1].position.z, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 4), targets[2].position.z, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 5), targets[3].position.z, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), targets[1].yaw, 0.001);
}

test "array targets turn with spline direction" {
    const points = [_]editor_math.Vec3{
        .{ .x = 0, .y = 0, .z = 0 },
        .{ .x = 3, .y = 0, .z = 0 },
    };
    const targets = try sampleArrayTargets(std.testing.allocator, &points, 1.5, false);
    defer std.testing.allocator.free(targets);

    try std.testing.expectEqual(@as(usize, 3), targets.len);
    try std.testing.expectApproxEqAbs(std.math.pi / 2.0, targets[1].yaw, 0.001);
}

test "stair steps rise along spline targets" {
    const points = [_]editor_math.Vec3{
        .{ .x = 0, .y = 0, .z = 0 },
        .{ .x = 0, .y = 0, .z = 4 },
    };
    const steps = try sampleStairSteps(std.testing.allocator, &points, 1.0, 0.25, 2.0);
    defer std.testing.allocator.free(steps);

    try std.testing.expectEqual(@as(usize, 4), steps.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), steps[0].position.z, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.125), steps[0].position.y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.875), steps[3].position.y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), steps[0].size.x, 0.001);
}
