const std = @import("std");
const editor_math = @import("editor_math.zig");

pub const Kind = enum {
    box_add,
    wedge_add,
    subtract_block,
    subtract_prism,
    doorway_subtract,
    ramp,
    stair,

    pub fn name(self: Kind) []const u8 {
        return switch (self) {
            .box_add => "box_add",
            .wedge_add => "wedge_add",
            .subtract_block => "subtract_block",
            .subtract_prism => "subtract_prism",
            .doorway_subtract => "doorway_subtract",
            .ramp => "ramp",
            .stair => "stair",
        };
    }

    pub fn fromName(text: []const u8) ?Kind {
        if (std.mem.eql(u8, text, "box_add")) return .box_add;
        if (std.mem.eql(u8, text, "wedge_add")) return .wedge_add;
        if (std.mem.eql(u8, text, "subtract_block")) return .subtract_block;
        if (std.mem.eql(u8, text, "subtract_prism")) return .subtract_prism;
        if (std.mem.eql(u8, text, "doorway_subtract")) return .doorway_subtract;
        if (std.mem.eql(u8, text, "ramp")) return .ramp;
        if (std.mem.eql(u8, text, "stair")) return .stair;
        return null;
    }
};

pub const Aabb = struct {
    min: editor_math.Vec3,
    max: editor_math.Vec3,

    pub fn valid(self: Aabb) bool {
        return self.min.x <= self.max.x and self.min.y <= self.max.y and self.min.z <= self.max.z;
    }
};

pub const Point2 = [2]f32;

pub const Intent = struct {
    kind: Kind,
    min: editor_math.Vec3,
    max: editor_math.Vec3,
    wall_min: ?editor_math.Vec3 = null,
    wall_max: ?editor_math.Vec3 = null,
    footprint: []Point2 = &.{},

    pub fn deinit(self: *Intent, allocator: std.mem.Allocator) void {
        allocator.free(self.footprint);
        self.footprint = &.{};
    }

    pub fn duplicate(allocator: std.mem.Allocator, source: Intent) !Intent {
        return .{
            .kind = source.kind,
            .min = source.min,
            .max = source.max,
            .wall_min = source.wall_min,
            .wall_max = source.wall_max,
            .footprint = if (source.footprint.len > 0) try allocator.dupe(Point2, source.footprint) else &.{},
        };
    }
};

pub fn parseTriple(text: []const u8) ![3]f32 {
    var parts: [3]f32 = undefined;
    var iter = std.mem.splitScalar(u8, text, ',');
    var i: usize = 0;
    while (iter.next()) |part| {
        if (i >= 3) return error.InvalidBlockoutTriple;
        parts[i] = try std.fmt.parseFloat(f32, std.mem.trim(u8, part, " \t"));
        i += 1;
    }
    if (i != 3) return error.InvalidBlockoutTriple;
    return parts;
}

pub fn tripleToVec3(triple: [3]f32) editor_math.Vec3 {
    return .{ .x = triple[0], .y = triple[1], .z = triple[2] };
}

pub fn formatTriple(writer: anytype, v: editor_math.Vec3) !void {
    try writer.print("{d},{d},{d}", .{ v.x, v.y, v.z });
}

pub fn parsePoint2List(allocator: std.mem.Allocator, text: []const u8) ![]Point2 {
    var points: std.ArrayList(Point2) = .empty;
    errdefer points.deinit(allocator);

    var iter = std.mem.splitScalar(u8, text, ';');
    while (iter.next()) |raw_point| {
        const point_text = std.mem.trim(u8, raw_point, " \t\r\n");
        if (point_text.len == 0) continue;

        var pair_iter = std.mem.splitScalar(u8, point_text, ',');
        const x_text = pair_iter.next() orelse return error.InvalidBlockoutFootprint;
        const z_text = pair_iter.next() orelse return error.InvalidBlockoutFootprint;
        if (pair_iter.next() != null) return error.InvalidBlockoutFootprint;

        try points.append(allocator, .{
            try std.fmt.parseFloat(f32, std.mem.trim(u8, x_text, " \t")),
            try std.fmt.parseFloat(f32, std.mem.trim(u8, z_text, " \t")),
        });
    }
    if (points.items.len == 0) return error.InvalidBlockoutFootprint;
    return points.toOwnedSlice(allocator);
}

pub fn formatPoint2List(writer: anytype, points: []const Point2) !void {
    for (points, 0..) |point, idx| {
        if (idx > 0) try writer.writeAll("; ");
        try writer.print("{d},{d}", .{ point[0], point[1] });
    }
}

test "blockout intent kinds round trip names" {
    try std.testing.expectEqual(Kind.box_add, Kind.fromName("box_add").?);
    try std.testing.expectEqual(Kind.wedge_add, Kind.fromName("wedge_add").?);
    try std.testing.expectEqual(Kind.subtract_block, Kind.fromName("subtract_block").?);
    try std.testing.expectEqual(Kind.subtract_prism, Kind.fromName("subtract_prism").?);
    try std.testing.expectEqual(Kind.doorway_subtract, Kind.fromName("doorway_subtract").?);
    try std.testing.expectEqualStrings("stair", Kind.stair.name());
}

test "blockout aabb validation rejects inverted bounds" {
    const good: Aabb = .{
        .min = .{ .x = 0, .y = 0, .z = 0 },
        .max = .{ .x = 1, .y = 2, .z = 3 },
    };
    try std.testing.expect(good.valid());
    const bad: Aabb = .{
        .min = .{ .x = 2, .y = 0, .z = 0 },
        .max = .{ .x = 1, .y = 2, .z = 3 },
    };
    try std.testing.expect(!bad.valid());
}

test "blockout footprint point list round trips" {
    const text = "0,0; 1.5,0; 0,2.25";
    const points = try parsePoint2List(std.testing.allocator, text);
    defer std.testing.allocator.free(points);

    try std.testing.expectEqual(@as(usize, 3), points.len);
    try std.testing.expectEqual(@as(f32, 1.5), points[1][0]);
    try std.testing.expectEqual(@as(f32, 2.25), points[2][1]);

    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try formatPoint2List(&out.writer, points);
    const bytes = try out.toOwnedSlice();
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualStrings("0,0; 1.5,0; 0,2.25", bytes);
}
