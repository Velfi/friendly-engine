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

/// lod_levels[0] is the finest mesh; later entries are coarser.
pub fn pickLodIndex(distance_m: f32, cell_size_m: f32, lod_level_count: usize) usize {
    if (lod_level_count <= 1) return 0;
    std.debug.assert(std.math.isFinite(distance_m) and distance_m >= 0);
    std.debug.assert(std.math.isFinite(cell_size_m) and cell_size_m > 0);
    const cells = distance_m / cell_size_m;
    if (cells <= 1.5) return 0;
    if (lod_level_count == 2) return 1;
    if (cells >= 5.0) return lod_level_count - 1;

    const t = (cells - 1.5) / (5.0 - 1.5);
    const intermediate_count = lod_level_count - 2;
    const intermediate: usize = @intFromFloat(@floor(t * @as(f32, @floatFromInt(intermediate_count))));
    return 1 + @min(intermediate, intermediate_count - 1);
}

test "lod pick prefers fine mesh near camera" {
    try std.testing.expectEqual(@as(usize, 0), pickLodIndex(10, 256, 2));
    try std.testing.expectEqual(@as(usize, 1), pickLodIndex(300, 256, 2));
}

test "lod pick uses coarse meshes across open-world clipmap distances" {
    try std.testing.expectEqual(@as(usize, 0), pickLodIndex(64, 64, 3));
    try std.testing.expectEqual(@as(usize, 1), pickLodIndex(256, 64, 3));
    try std.testing.expectEqual(@as(usize, 2), pickLodIndex(512, 64, 3));
}

test "lod pick spreads five terrain levels through middle distances" {
    try std.testing.expectEqual(@as(usize, 0), pickLodIndex(128, 256, 5));
    try std.testing.expectEqual(@as(usize, 1), pickLodIndex(512, 256, 5));
    try std.testing.expectEqual(@as(usize, 2), pickLodIndex(768, 256, 5));
    try std.testing.expectEqual(@as(usize, 3), pickLodIndex(1024, 256, 5));
    try std.testing.expectEqual(@as(usize, 4), pickLodIndex(1280, 256, 5));
}
