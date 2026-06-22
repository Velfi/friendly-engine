const std = @import("std");
const core = @import("../core/mod.zig");
const scatter_clusters = @import("scatter_clusters.zig");

pub fn distanceFromCamera(camera: core.math.Vec3f, position: core.math.Vec3f) f32 {
    return core.math.Vec3f.sub(position, camera).length();
}

/// Returns null when the instance is fully culled; otherwise a fade factor in [0, 1].
pub fn scatterFadeFactor(cull: scatter_clusters.ScatterCull, distance_m: f32) ?f32 {
    if (distance_m >= cull.cull_distance_m) return null;
    const fade_start = cull.cull_distance_m - cull.fade_distance_m;
    if (distance_m <= fade_start) return 1.0;
    if (cull.fade_distance_m <= 0) return null;
    return 1.0 - (distance_m - fade_start) / cull.fade_distance_m;
}

pub fn shouldDrawScatter(
    cull: scatter_clusters.ScatterCull,
    camera: core.math.Vec3f,
    position: core.math.Vec3f,
) bool {
    return scatterBatchFadeFactor(cull, camera, position) != null;
}

pub fn scatterBatchFadeFactor(
    cull: scatter_clusters.ScatterCull,
    camera: core.math.Vec3f,
    position: core.math.Vec3f,
) ?f32 {
    return scatterFadeFactor(cull, distanceFromCamera(camera, position));
}

pub fn uniformFadeScale(scale: core.math.Vec3f, fade: f32) core.math.Vec3f {
    return .{
        .x = scale.x * fade,
        .y = scale.y * fade,
        .z = scale.z * fade,
    };
}

test "scatter cull keeps instances inside fade start distance" {
    const cull = scatter_clusters.ScatterCull{ .cull_distance_m = 100, .fade_distance_m = 20 };
    const camera: core.math.Vec3f = .{ .x = 0, .y = 0, .z = 0 };
    const near: core.math.Vec3f = .{ .x = 50, .y = 0, .z = 0 };
    try std.testing.expect(shouldDrawScatter(cull, camera, near));
    try std.testing.expectEqual(@as(?f32, 1.0), scatterFadeFactor(cull, 50));
}

test "scatter cull drops instances beyond cull distance" {
    const cull = scatter_clusters.ScatterCull{ .cull_distance_m = 100, .fade_distance_m = 20 };
    const camera: core.math.Vec3f = .{ .x = 0, .y = 0, .z = 0 };
    const far: core.math.Vec3f = .{ .x = 100, .y = 0, .z = 0 };
    try std.testing.expect(!shouldDrawScatter(cull, camera, far));
    try std.testing.expect(scatterFadeFactor(cull, 100) == null);
    try std.testing.expect(scatterFadeFactor(cull, 150) == null);
}

test "scatter cull linear fade ramps between fade start and cull distance" {
    const cull = scatter_clusters.ScatterCull{ .cull_distance_m = 100, .fade_distance_m = 20 };
    try std.testing.expectEqual(@as(?f32, 1.0), scatterFadeFactor(cull, 80));
    try std.testing.expectEqual(@as(?f32, 0.5), scatterFadeFactor(cull, 90));
    try std.testing.expectEqual(@as(?f32, 0.0), scatterFadeFactor(cull, 100));
}

test "scatter cull uses camera-relative distance" {
    const cull = scatter_clusters.ScatterCull{ .cull_distance_m = 10, .fade_distance_m = 2 };
    const camera: core.math.Vec3f = .{ .x = 10, .y = 0, .z = 0 };
    const instance: core.math.Vec3f = .{ .x = 16, .y = 0, .z = 0 };
    try std.testing.expect(!shouldDrawScatter(cull, camera, instance));
    try std.testing.expect(shouldDrawScatter(cull, camera, .{ .x = 14, .y = 0, .z = 0 }));
}

test "scatter fade scales instance size uniformly" {
    const scaled = uniformFadeScale(.{ .x = 2, .y = 3, .z = 4 }, 0.5);
    try std.testing.expectEqual(@as(f32, 1), scaled.x);
    try std.testing.expectEqual(@as(f32, 1.5), scaled.y);
    try std.testing.expectEqual(@as(f32, 2), scaled.z);
}
