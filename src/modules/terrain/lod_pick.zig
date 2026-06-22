const std = @import("std");
const core = @import("../../core/mod.zig");
const world = @import("../../world/mod.zig");

pub fn cellCenter(id: world.cell.CellId, cell_size_m: f32) core.math.Vec3f {
    const half = cell_size_m * 0.5;
    return .{
        .x = @as(f32, @floatFromInt(id.x)) * cell_size_m + half,
        .y = 0,
        .z = @as(f32, @floatFromInt(id.y)) * cell_size_m + half,
    };
}

pub fn distanceToCellCenter(target: core.math.Vec3f, center: core.math.Vec3f) f32 {
    const dx = target.x - center.x;
    const dy = target.y - center.y;
    const dz = target.z - center.z;
    return @sqrt(dx * dx + dy * dy + dz * dz);
}

pub fn distanceToCellFootprint(target: core.math.Vec3f, id: world.cell.CellId, cell_size_m: f32) f32 {
    std.debug.assert(std.math.isFinite(cell_size_m) and cell_size_m > 0);
    const min_x = @as(f32, @floatFromInt(id.x)) * cell_size_m;
    const min_z = @as(f32, @floatFromInt(id.y)) * cell_size_m;
    const max_x = min_x + cell_size_m;
    const max_z = min_z + cell_size_m;
    const nearest_x = std.math.clamp(target.x, min_x, max_x);
    const nearest_z = std.math.clamp(target.z, min_z, max_z);
    const dx = target.x - nearest_x;
    const dz = target.z - nearest_z;
    return @sqrt(dx * dx + dz * dz);
}

/// lod_levels[0] is the finest mesh; later entries are coarser.
pub fn pickLodIndex(distance_m: f32, cell_size_m: f32, lod_level_count: usize) usize {
    if (lod_level_count <= 1) return 0;
    std.debug.assert(std.math.isFinite(distance_m) and distance_m >= 0);
    std.debug.assert(std.math.isFinite(cell_size_m) and cell_size_m > 0);
    const cells = distance_m / cell_size_m;
    const linear_band: usize = @intFromFloat(@floor(cells));
    return @min(linear_band, lod_level_count - 1);
}

test "lod pick prefers fine mesh near camera" {
    try std.testing.expectEqual(@as(usize, 0), pickLodIndex(10, 256, 2));
    try std.testing.expectEqual(@as(usize, 0), pickLodIndex(255, 256, 2));
    try std.testing.expectEqual(@as(usize, 1), pickLodIndex(256, 256, 2));
}

test "lod distance is zero while camera is over cell footprint" {
    const id = world.cell.CellId{ .x = 2, .y = -1, .z = 0 };
    try std.testing.expectApproxEqAbs(@as(f32, 0), distanceToCellFootprint(.{ .x = 640, .y = 80, .z = -12 }, id, 256), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 32), distanceToCellFootprint(.{ .x = 800, .y = 0, .z = -12 }, id, 256), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 32), distanceToCellFootprint(.{ .x = 640, .y = 0, .z = -288 }, id, 256), 0.001);
}

test "lod pick uses one-cell linear bands" {
    try std.testing.expectEqual(@as(usize, 0), pickLodIndex(63, 64, 3));
    try std.testing.expectEqual(@as(usize, 1), pickLodIndex(64, 64, 3));
    try std.testing.expectEqual(@as(usize, 2), pickLodIndex(128, 64, 3));
    try std.testing.expectEqual(@as(usize, 2), pickLodIndex(512, 64, 3));
}

test "lod pick spreads five terrain levels linearly" {
    try std.testing.expectEqual(@as(usize, 0), pickLodIndex(128, 256, 5));
    try std.testing.expectEqual(@as(usize, 1), pickLodIndex(256, 256, 5));
    try std.testing.expectEqual(@as(usize, 2), pickLodIndex(512, 256, 5));
    try std.testing.expectEqual(@as(usize, 3), pickLodIndex(768, 256, 5));
    try std.testing.expectEqual(@as(usize, 4), pickLodIndex(1024, 256, 5));
    try std.testing.expectEqual(@as(usize, 4), pickLodIndex(1280, 256, 5));
}
