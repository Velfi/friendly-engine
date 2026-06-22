const std = @import("std");
const core = @import("../../core/mod.zig");
const world = @import("../../world/mod.zig");

pub const RoadDeformInput = struct {
    points: []const core.math.Vec3f,
    width: f32,
    elevation: f32 = 0.02,
    material_mask_value: u8 = 255,
    paint_layer_index: usize = 0,
    paint_layer_count: usize = 1,
};

pub fn roadCrossesCell(road: RoadDeformInput, bounds: world.cell.CellBounds) bool {
    if (road.points.len < 2) return false;
    var i: usize = 0;
    while (i + 1 < road.points.len) : (i += 1) {
        const a = road.points[i];
        const b = road.points[i + 1];
        if (segmentIntersectsCell(a, b, bounds)) return true;
    }
    return false;
}

pub fn applyRoadDeformation(
    bounds: world.cell.CellBounds,
    cell_size_m: f32,
    tile_size: u32,
    heights: []f32,
    paint_weights: []u8,
    road: RoadDeformInput,
) void {
    if (road.points.len < 2) return;
    const half_width = road.width * 0.5;
    const grid = @as(usize, tile_size);
    const sample_count = grid * grid;
    if (road.paint_layer_count < 1 or road.paint_layer_index >= road.paint_layer_count) return;
    if (heights.len < sample_count or paint_weights.len < sample_count * road.paint_layer_count) return;

    var y: usize = 0;
    while (y < grid) : (y += 1) {
        var x: usize = 0;
        while (x < grid) : (x += 1) {
            const world_x = bounds.min.x + (@as(f32, @floatFromInt(x)) + 0.5) / @as(f32, @floatFromInt(grid)) * cell_size_m;
            const world_z = bounds.min.z + (@as(f32, @floatFromInt(y)) + 0.5) / @as(f32, @floatFromInt(grid)) * cell_size_m;
            const influence = roadInfluenceAt(.{ .x = world_x, .z = world_z }, road, half_width);
            if (influence.weight <= 0) continue;
            const idx = y * grid + x;
            const target_height = influence.road_y + road.elevation;
            heights[idx] = @max(heights[idx], target_height);
            const paint = @as(f32, @floatFromInt(road.material_mask_value));
            const paint_idx = idx * road.paint_layer_count + road.paint_layer_index;
            const blended = @as(f32, @floatFromInt(paint_weights[paint_idx])) + influence.weight * (paint - @as(f32, @floatFromInt(paint_weights[paint_idx])));
            paint_weights[paint_idx] = @intFromFloat(@round(std.math.clamp(blended, 0, 255)));
        }
    }
}

const RoadInfluence = struct {
    weight: f32,
    road_y: f32,
};

fn roadInfluenceAt(point_xz: struct { x: f32, z: f32 }, road: RoadDeformInput, half_width: f32) RoadInfluence {
    var best: RoadInfluence = .{ .weight = 0, .road_y = 0 };
    var segment_index: usize = 0;
    while (segment_index + 1 < road.points.len) : (segment_index += 1) {
        const a = road.points[segment_index];
        const b = road.points[segment_index + 1];
        const closest = closestOnSegmentXZ(point_xz.x, point_xz.z, a.x, a.z, b.x, b.z);
        if (closest.dist > half_width) continue;
        const edge = 1.0 - (closest.dist / @max(0.001, half_width));
        const weight = std.math.clamp(edge, 0, 1);
        if (weight <= best.weight) continue;
        const road_y = a.y + (b.y - a.y) * closest.t;
        best = .{ .weight = weight, .road_y = road_y };
    }
    return best;
}

fn closestOnSegmentXZ(px: f32, pz: f32, ax: f32, az: f32, bx: f32, bz: f32) struct { t: f32, dist: f32 } {
    const dx = bx - ax;
    const dz = bz - az;
    const len_sq = dx * dx + dz * dz;
    if (len_sq <= 0.000001) {
        const ox = px - ax;
        const oz = pz - az;
        return .{ .t = 0, .dist = @sqrt(ox * ox + oz * oz) };
    }
    const t = std.math.clamp(((px - ax) * dx + (pz - az) * dz) / len_sq, 0, 1);
    const cx = ax + dx * t;
    const cz = az + dz * t;
    const ox = px - cx;
    const oz = pz - cz;
    return .{ .t = t, .dist = @sqrt(ox * ox + oz * oz) };
}

fn segmentIntersectsCell(a: core.math.Vec3f, b: core.math.Vec3f, bounds: world.cell.CellBounds) bool {
    const min_x = @min(a.x, b.x);
    const max_x = @max(a.x, b.x);
    const min_z = @min(a.z, b.z);
    const max_z = @max(a.z, b.z);
    if (max_x < bounds.min.x or min_x > bounds.max.x) return false;
    if (max_z < bounds.min.z or min_z > bounds.max.z) return false;
    return true;
}

test "road deformation raises height and paints splat under width" {
    const bounds = world.cell.CellBounds{
        .min = .{ .x = 0, .y = 0, .z = 0 },
        .max = .{ .x = 256, .y = 256, .z = 256 },
    };
    const tile_size: u32 = 4;
    var heights = [_]f32{0} ** 16;
    var splat = [_]u8{0} ** (16 * 2);
    const road = RoadDeformInput{
        .points = &.{
            .{ .x = 0, .y = 1, .z = 128 },
            .{ .x = 256, .y = 1, .z = 128 },
        },
        .width = 32,
        .elevation = 0.5,
        .material_mask_value = 255,
        .paint_layer_index = 1,
        .paint_layer_count = 2,
    };
    applyRoadDeformation(bounds, 256, tile_size, &heights, &splat, road);
    try std.testing.expect(heights[2 * tile_size + 2] > 0.4);
    try std.testing.expect(splat[(2 * tile_size + 2) * 2 + 1] > 200);
    try std.testing.expect(heights[0] == 0);
}

test "road crosses cell detects segment overlap" {
    const bounds = world.cell.CellBounds{
        .min = .{ .x = 0, .y = 0, .z = 0 },
        .max = .{ .x = 256, .y = 256, .z = 256 },
    };
    const inside = RoadDeformInput{
        .points = &.{ .{ .x = 10, .y = 0, .z = 128 }, .{ .x = 200, .y = 0, .z = 128 } },
        .width = 4,
    };
    const outside = RoadDeformInput{
        .points = &.{ .{ .x = 300, .y = 0, .z = 128 }, .{ .x = 400, .y = 0, .z = 128 } },
        .width = 4,
    };
    try std.testing.expect(roadCrossesCell(inside, bounds));
    try std.testing.expect(!roadCrossesCell(outside, bounds));
}

test "road crosses cell detects sampled path overlap on any segment" {
    const bounds = world.cell.CellBounds{
        .min = .{ .x = 0, .y = 0, .z = 0 },
        .max = .{ .x = 256, .y = 256, .z = 256 },
    };
    const sampled_path = RoadDeformInput{
        .points = &.{
            .{ .x = 300, .y = 0, .z = 10 },
            .{ .x = 300, .y = 0, .z = 200 },
            .{ .x = 128, .y = 0, .z = 200 },
        },
        .width = 4,
    };
    try std.testing.expect(roadCrossesCell(sampled_path, bounds));
}
