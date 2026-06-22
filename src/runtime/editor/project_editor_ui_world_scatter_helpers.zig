const std = @import("std");
const shared = @import("runtime_shared");
const project_editor_scatter_preview = @import("project_editor_scatter_preview.zig");
const project_editor_types = @import("project_editor_types.zig");

const editor_math = shared.editor_math;

pub fn scatterDragCreatesZone(start: ?editor_math.Vec3, end: ?editor_math.Vec3) bool {
    const a = start orelse return false;
    const b = end orelse return false;
    const dx = b.x - a.x;
    const dz = b.z - a.z;
    return dx * dx + dz * dz >= project_editor_types.click_drag_threshold_sq;
}

pub fn findScatterZoneByBounds(
    zones: []const project_editor_scatter_preview.ExclusionPreview,
    min_x: f32,
    min_z: f32,
    max_x: f32,
    max_z: f32,
) ?usize {
    var found: ?usize = null;
    for (zones, 0..) |zone, index| {
        if (scatterZoneBoundsMatch(zone, min_x, min_z, max_x, max_z)) found = index;
    }
    return found;
}

pub fn scatterZoneBoundsMatch(zone: project_editor_scatter_preview.ExclusionPreview, min_x: f32, min_z: f32, max_x: f32, max_z: f32) bool {
    const epsilon: f32 = 0.01;
    return approxEq(zone.min.x, min_x, epsilon) and
        approxEq(zone.min.z, min_z, epsilon) and
        approxEq(zone.max.x, max_x, epsilon) and
        approxEq(zone.max.z, max_z, epsilon);
}

pub fn approxEq(a: f32, b: f32, epsilon: f32) bool {
    return @abs(a - b) <= epsilon;
}

pub fn scatterSelectionLabel(hit: project_editor_types.WorldCurveHit) []const u8 {
    return switch (hit.element) {
        .point => "Selected scatter corner",
        .segment => "Selected scatter side",
        .width_rail => "Selected scatter area",
        else => "No scatter area selected",
    };
}

pub fn resizeScatterZoneCorner(corner: usize, point: editor_math.Vec3, min_x: *f32, min_z: *f32, max_x: *f32, max_z: *f32) void {
    switch (corner % 4) {
        0 => {
            min_x.* = point.x;
            min_z.* = point.z;
        },
        1 => {
            max_x.* = point.x;
            min_z.* = point.z;
        },
        2 => {
            max_x.* = point.x;
            max_z.* = point.z;
        },
        else => {
            min_x.* = point.x;
            max_z.* = point.z;
        },
    }
}

pub fn resizeScatterZoneEdge(edge: usize, dx: f32, dz: f32, min_x: *f32, min_z: *f32, max_x: *f32, max_z: *f32) void {
    switch (edge % 4) {
        0 => min_z.* += dz,
        1 => max_x.* += dx,
        2 => max_z.* += dz,
        else => min_x.* += dx,
    }
}

pub fn moveScatterZoneBody(dx: f32, dz: f32, min_x: *f32, min_z: *f32, max_x: *f32, max_z: *f32) void {
    min_x.* += dx;
    max_x.* += dx;
    min_z.* += dz;
    max_z.* += dz;
}

pub fn normalizeMinMax(a: *f32, b: *f32) void {
    if (a.* > b.*) std.mem.swap(f32, a, b);
}

test "scatter zone body move preserves rectangle size" {
    var min_x: f32 = 2;
    var min_z: f32 = 4;
    var max_x: f32 = 8;
    var max_z: f32 = 14;

    moveScatterZoneBody(3, -2, &min_x, &min_z, &max_x, &max_z);

    try std.testing.expectEqual(@as(f32, 5), min_x);
    try std.testing.expectEqual(@as(f32, 2), min_z);
    try std.testing.expectEqual(@as(f32, 11), max_x);
    try std.testing.expectEqual(@as(f32, 12), max_z);
    try std.testing.expectEqual(@as(f32, 6), max_x - min_x);
    try std.testing.expectEqual(@as(f32, 10), max_z - min_z);
}

test "scatter drag creation threshold matches zone creation" {
    try std.testing.expect(!scatterDragCreatesZone(null, .{ .x = 10, .y = 0, .z = 10 }));
    try std.testing.expect(!scatterDragCreatesZone(
        .{ .x = 0, .y = 0, .z = 0 },
        .{ .x = 1, .y = 0, .z = 1 },
    ));
    try std.testing.expect(scatterDragCreatesZone(
        .{ .x = 0, .y = 0, .z = 0 },
        .{ .x = 20, .y = 0, .z = 0 },
    ));
}

test "scatter created zone selection prefers newest matching bounds" {
    const zones = [_]project_editor_scatter_preview.ExclusionPreview{
        .{
            .cell = .{ .x = 0, .y = 0, .z = 0 },
            .min = .{ .x = 1, .y = 0, .z = 2 },
            .max = .{ .x = 5, .y = 4, .z = 6 },
        },
        .{
            .cell = .{ .x = 0, .y = 0, .z = 0 },
            .min = .{ .x = 1, .y = 0, .z = 2 },
            .max = .{ .x = 5, .y = 4, .z = 6 },
        },
    };

    try std.testing.expectEqual(@as(?usize, 1), findScatterZoneByBounds(&zones, 1, 2, 5, 6));
    try std.testing.expectEqual(@as(?usize, null), findScatterZoneByBounds(&zones, 1, 2, 5, 9));
}
