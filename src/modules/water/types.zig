const std = @import("std");
const core = @import("../../core/mod.zig");

pub const schema_version: u32 = 1;

pub const WaterKind = enum {
    ocean_near,
    lake,
    pond,
    river,
    interior,

    pub fn label(self: WaterKind) []const u8 {
        return switch (self) {
            .ocean_near => "ocean_near",
            .lake => "lake",
            .pond => "pond",
            .river => "river",
            .interior => "interior",
        };
    }
};

pub fn kindFromName(name: []const u8) ?WaterKind {
    inline for (std.meta.fields(WaterKind)) |field| {
        if (std.mem.eql(u8, name, field.name)) return @enumFromInt(field.value);
    }
    return null;
}

pub const WaterVolume = struct {
    id: []u8,
    kind: WaterKind = .lake,
    material: []u8,
    surface_y: f32,
    bottom_y: f32,
    swimmable: bool = true,
    linked_to_ocean: bool = false,
    current: core.math.Vec3f = .{ .x = 0, .y = 0, .z = 0 },
    points: [][2]f32,

    pub fn deinit(self: *WaterVolume, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.material);
        allocator.free(self.points);
        self.* = undefined;
    }

    pub fn duplicate(allocator: std.mem.Allocator, source: WaterVolume) !WaterVolume {
        return .{
            .id = try allocator.dupe(u8, source.id),
            .kind = source.kind,
            .material = try allocator.dupe(u8, source.material),
            .surface_y = source.surface_y,
            .bottom_y = source.bottom_y,
            .swimmable = source.swimmable,
            .linked_to_ocean = source.linked_to_ocean,
            .current = source.current,
            .points = try allocator.dupe([2]f32, source.points),
        };
    }

    pub fn insertPointAfter(self: *WaterVolume, allocator: std.mem.Allocator, edge_index: usize, point: [2]f32) !usize {
        if (edge_index >= self.points.len) return error.InvalidWaterVolume;
        const insert_index = edge_index + 1;
        const new_points = try allocator.alloc([2]f32, self.points.len + 1);
        errdefer allocator.free(new_points);
        for (self.points[0..insert_index], 0..) |existing, index| new_points[index] = existing;
        new_points[insert_index] = point;
        for (self.points[insert_index..], insert_index + 1..) |existing, index| new_points[index] = existing;
        const old_points = self.points;
        self.points = new_points;
        validateVolume(self.*) catch |err| {
            self.points = old_points;
            allocator.free(new_points);
            return err;
        };
        allocator.free(old_points);
        return insert_index;
    }
};

pub const WaterDoc = struct {
    schema_version: u32 = schema_version,
    volumes: []WaterVolume = &.{},

    pub fn deinit(self: *WaterDoc, allocator: std.mem.Allocator) void {
        for (self.volumes) |*volume| volume.deinit(allocator);
        if (self.volumes.len > 0) allocator.free(self.volumes);
        self.* = .{};
    }
};

pub const WaterQuery = struct {
    in_water: bool = false,
    swimmable: bool = false,
    surface_y: f32 = 0,
    bottom_y: f32 = 0,
    submerged_depth: f32 = 0,
    current: core.math.Vec3f = .{ .x = 0, .y = 0, .z = 0 },
    volume_id: []const u8 = "",
    material: []const u8 = "",
};

pub fn defaultMaterial(kind: WaterKind) []const u8 {
    return switch (kind) {
        .ocean_near => "water.ocean.near",
        .lake => "water.lake.clear",
        .pond => "water.pond.clear",
        .river => "water.river.clear",
        .interior => "water.interior.clear",
    };
}

pub fn validateDoc(doc: WaterDoc) !void {
    if (doc.schema_version != schema_version) return error.UnsupportedWaterSchemaVersion;
    for (doc.volumes, 0..) |volume, index| {
        try validateVolume(volume);
        for (doc.volumes[0..index]) |other| {
            if (std.mem.eql(u8, other.id, volume.id)) return error.DuplicateWaterVolumeId;
        }
    }
}

pub fn validateVolume(volume: WaterVolume) !void {
    if (volume.id.len == 0 or volume.material.len == 0) return error.InvalidWaterVolume;
    if (volume.points.len < 3) return error.InvalidWaterVolume;
    if (!std.math.isFinite(volume.surface_y) or !std.math.isFinite(volume.bottom_y)) return error.InvalidWaterVolume;
    if (volume.bottom_y >= volume.surface_y) return error.InvalidWaterVolume;
    if (!std.math.isFinite(volume.current.x) or !std.math.isFinite(volume.current.y) or !std.math.isFinite(volume.current.z)) return error.InvalidWaterVolume;
    for (volume.points) |point| {
        if (!std.math.isFinite(point[0]) or !std.math.isFinite(point[1])) return error.InvalidWaterVolume;
    }
    if (@abs(polygonArea(volume.points)) < 0.001) return error.InvalidWaterVolume;
}

pub fn queryPoint(volumes: []const WaterVolume, point: core.math.Vec3f) WaterQuery {
    var best: ?WaterQuery = null;
    for (volumes) |volume| {
        if (point.y > volume.surface_y or point.y < volume.bottom_y) continue;
        if (!pointInPolygon(volume.points, point.x, point.z)) continue;
        const query = WaterQuery{
            .in_water = true,
            .swimmable = volume.swimmable,
            .surface_y = volume.surface_y,
            .bottom_y = volume.bottom_y,
            .submerged_depth = volume.surface_y - point.y,
            .current = volume.current,
            .volume_id = volume.id,
            .material = volume.material,
        };
        if (best == null or query.surface_y > best.?.surface_y) best = query;
    }
    return best orelse .{};
}

pub fn pointInPolygon(points: []const [2]f32, x: f32, z: f32) bool {
    if (points.len < 3) return false;
    var inside = false;
    var j = points.len - 1;
    for (points, 0..) |point, i| {
        const zi = point[1];
        const zj = points[j][1];
        const crosses = (zi > z) != (zj > z);
        if (crosses) {
            const xi = point[0];
            const xj = points[j][0];
            const at_x = ((xj - xi) * (z - zi) / (zj - zi)) + xi;
            if (x < at_x) inside = !inside;
        }
        j = i;
    }
    return inside;
}

pub fn polygonArea(points: []const [2]f32) f32 {
    var area: f32 = 0;
    var j = points.len - 1;
    for (points, 0..) |point, i| {
        area += (points[j][0] * point[1]) - (point[0] * points[j][1]);
        j = i;
    }
    return area * 0.5;
}

pub fn bounds(volume: WaterVolume) struct { min_x: f32, max_x: f32, min_z: f32, max_z: f32 } {
    var min_x = volume.points[0][0];
    var max_x = volume.points[0][0];
    var min_z = volume.points[0][1];
    var max_z = volume.points[0][1];
    for (volume.points[1..]) |point| {
        min_x = @min(min_x, point[0]);
        max_x = @max(max_x, point[0]);
        min_z = @min(min_z, point[1]);
        max_z = @max(max_z, point[1]);
    }
    return .{ .min_x = min_x, .max_x = max_x, .min_z = min_z, .max_z = max_z };
}

test "query point uses polygon prism" {
    const volume = WaterVolume{
        .id = @constCast("pond"),
        .material = @constCast("water.pond.clear"),
        .surface_y = 4,
        .bottom_y = 1,
        .points = @constCast(&[_][2]f32{ .{ 0, 0 }, .{ 4, 0 }, .{ 4, 4 }, .{ 0, 4 } }),
    };
    const wet = queryPoint(&.{volume}, .{ .x = 2, .y = 3, .z = 2 });
    try std.testing.expect(wet.in_water);
    try std.testing.expectEqualStrings("pond", wet.volume_id);
    const dry = queryPoint(&.{volume}, .{ .x = 6, .y = 3, .z = 2 });
    try std.testing.expect(!dry.in_water);
}

test "insert water volume point after selected edge" {
    var volume = WaterVolume{
        .id = try std.testing.allocator.dupe(u8, "pond"),
        .material = try std.testing.allocator.dupe(u8, "water.pond.clear"),
        .surface_y = 4,
        .bottom_y = 1,
        .points = try std.testing.allocator.dupe([2]f32, &[_][2]f32{ .{ 0, 0 }, .{ 4, 0 }, .{ 4, 4 }, .{ 0, 4 } }),
    };
    defer volume.deinit(std.testing.allocator);

    const inserted = try volume.insertPointAfter(std.testing.allocator, 1, .{ 5, 2 });

    try std.testing.expectEqual(@as(usize, 2), inserted);
    try std.testing.expectEqual(@as(usize, 5), volume.points.len);
    try std.testing.expectEqual(@as(f32, 5), volume.points[2][0]);
    try std.testing.expectEqual(@as(f32, 2), volume.points[2][1]);
    try validateVolume(volume);
}
