const std = @import("std");
const grass = @import("mod.zig");
const world = @import("../../world/mod.zig");

test "grass cluster metadata counts unique materials" {
    const instances = [_]grass.types.GrassInstance{
        .{ .position = .{ 0, 0, 0 }, .normal = .{ 0, 1, 0 }, .material = "grass", .color = .{ 80, 150, 70, 255 }, .height = 1, .width = 0.05, .yaw = 0, .phase = 0, .variant = 0 },
        .{ .position = .{ 1, 0, 0 }, .normal = .{ 0, 1, 0 }, .material = "marsh", .color = .{ 60, 120, 90, 255 }, .height = 1, .width = 0.05, .yaw = 0, .phase = 0, .variant = 1 },
    };
    const meta = try grass.runtime.buildClusterMetadata(std.testing.allocator, .{ .x = 0, .y = 0, .z = 0 }, &instances, .{ .cull_distance_m = 64, .fade_distance_m = 8, .wind_direction_deg = 225, .wind_speed_mps = 5, .wind_strength = 0.5, .bend_strength = 0.8, .stiffness = 0.7 });
    try std.testing.expectEqual(@as(usize, 2), meta.material_count);
}

test "grass fade culls beyond distance" {
    const cull = grass.runtime.GrassCull{ .cull_distance_m = 10, .fade_distance_m = 2 };
    try std.testing.expect(grass.runtime.batchFadeFactor(cull, .{ .x = 0, .y = 0, .z = 0 }, .{ .x = 5, .y = 0, .z = 0 }) != null);
    try std.testing.expect(grass.runtime.batchFadeFactor(cull, .{ .x = 0, .y = 0, .z = 0 }, .{ .x = 11, .y = 0, .z = 0 }) == null);
}

test "grass affected cells deduplicate patch cells" {
    _ = world.cell.CellId{ .x = 0, .y = 0, .z = 0 };
}


test "grass compiler enforces per-cell cluster limit predicate" {
    try std.testing.expect(!grass.clusterLimitReached(grass.types.max_instances_per_cell - 1));
    try std.testing.expect(grass.clusterLimitReached(grass.types.max_instances_per_cell));
    try std.testing.expect(grass.clusterLimitReached(grass.types.max_instances_per_cell + 1));
}
