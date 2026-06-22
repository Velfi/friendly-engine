const std = @import("std");

pub const Aabb = struct {
    min: [3]f32,
    max: [3]f32,
};

pub const Point2 = [2]f32;

pub const ConvexPrism = struct {
    footprint: []Point2,
    min_y: f32,
    max_y: f32,

    pub fn deinit(self: *ConvexPrism, allocator: std.mem.Allocator) void {
        allocator.free(self.footprint);
        self.* = .{ .footprint = &.{}, .min_y = 0, .max_y = 0 };
    }

    pub fn clone(self: ConvexPrism, allocator: std.mem.Allocator) !ConvexPrism {
        return .{
            .footprint = try allocator.dupe(Point2, self.footprint),
            .min_y = self.min_y,
            .max_y = self.max_y,
        };
    }
};

pub const Brush = union(enum) {
    box: Aabb,
    convex_prism: ConvexPrism,
};

pub const MeshVertex = struct {
    position: [3]f32,
    normal: [3]f32,
    uv: [2]f32,
};

pub const Mesh = struct {
    vertices: []MeshVertex,
    indices: []u32,

    pub fn deinit(self: *Mesh, allocator: std.mem.Allocator) void {
        allocator.free(self.vertices);
        allocator.free(self.indices);
        self.* = .{ .vertices = &.{}, .indices = &.{} };
    }
};

const default_meters_per_repeat: f32 = 1.0;

pub const Solid = struct {
    boxes: []Aabb = &.{},
    prisms: []ConvexPrism = &.{},

    pub fn deinit(self: *Solid, allocator: std.mem.Allocator) void {
        allocator.free(self.boxes);
        for (self.prisms) |*prism| prism.deinit(allocator);
        allocator.free(self.prisms);
        self.* = .{};
    }

    pub fn fromBrush(allocator: std.mem.Allocator, brush: Brush) !Solid {
        return switch (brush) {
            .box => |bounds| fromBox(allocator, bounds),
            .convex_prism => |prism| fromConvexPrism(allocator, prism.footprint, prism.min_y, prism.max_y),
        };
    }

    pub fn fromBox(allocator: std.mem.Allocator, bounds: Aabb) !Solid {
        try validateAabb(bounds);
        const boxes = try allocator.alloc(Aabb, 1);
        boxes[0] = bounds;
        return .{ .boxes = boxes };
    }

    pub fn fromConvexPrism(allocator: std.mem.Allocator, footprint: []const Point2, min_y: f32, max_y: f32) !Solid {
        try validateConvexPrism(footprint, min_y, max_y);
        const prisms = try allocator.alloc(ConvexPrism, 1);
        errdefer allocator.free(prisms);
        prisms[0] = .{
            .footprint = try allocator.dupe(Point2, footprint),
            .min_y = min_y,
            .max_y = max_y,
        };
        return .{ .prisms = prisms };
    }

    pub fn clone(self: Solid, allocator: std.mem.Allocator) !Solid {
        const boxes = try allocator.dupe(Aabb, self.boxes);
        errdefer allocator.free(boxes);
        const prisms = try clonePrisms(allocator, self.prisms);
        return .{ .boxes = boxes, .prisms = prisms };
    }

    pub fn unionWith(self: Solid, allocator: std.mem.Allocator, other: Solid) !Solid {
        var boxes = try allocator.alloc(Aabb, self.boxes.len + other.boxes.len);
        errdefer allocator.free(boxes);
        @memcpy(boxes[0..self.boxes.len], self.boxes);
        @memcpy(boxes[self.boxes.len..], other.boxes);
        var prisms = try allocator.alloc(ConvexPrism, self.prisms.len + other.prisms.len);
        errdefer allocator.free(prisms);
        var initialized: usize = 0;
        errdefer {
            for (prisms[0..initialized]) |*prism| prism.deinit(allocator);
        }
        for (self.prisms, 0..) |prism, idx| {
            prisms[idx] = try prism.clone(allocator);
            initialized += 1;
        }
        for (other.prisms, 0..) |prism, idx| {
            prisms[self.prisms.len + idx] = try prism.clone(allocator);
            initialized += 1;
        }
        return .{ .boxes = boxes, .prisms = prisms };
    }

    pub fn subtractBrush(self: Solid, allocator: std.mem.Allocator, brush: Brush) !Solid {
        return switch (brush) {
            .box => |bounds| subtractBox(self, allocator, bounds),
            .convex_prism => |prism| subtractConvexPrism(self, allocator, prism.footprint, prism.min_y, prism.max_y),
        };
    }

    pub fn subtractBox(self: Solid, allocator: std.mem.Allocator, cut: Aabb) !Solid {
        try validateAabb(cut);
        var out: std.ArrayList(Aabb) = .empty;
        errdefer out.deinit(allocator);
        var out_prisms: std.ArrayList(ConvexPrism) = .empty;
        errdefer {
            for (out_prisms.items) |*prism| prism.deinit(allocator);
            out_prisms.deinit(allocator);
        }
        for (self.boxes) |source| {
            if (aabbIntersection(source, cut)) |intersection| {
                var pieces: [6]?Aabb = undefined;
                splitAabbSubtract(source, intersection, &pieces);
                for (pieces) |piece_opt| {
                    const piece = piece_opt orelse continue;
                    try out.append(allocator, piece);
                }
            } else {
                try out.append(allocator, source);
            }
        }
        for (self.prisms) |prism| {
            try subtractPrismByBox(allocator, &out_prisms, prism, cut);
        }
        return .{
            .boxes = try out.toOwnedSlice(allocator),
            .prisms = try out_prisms.toOwnedSlice(allocator),
        };
    }

    pub fn subtractConvexPrism(self: Solid, allocator: std.mem.Allocator, footprint: []const Point2, min_y: f32, max_y: f32) !Solid {
        try validateConvexPrism(footprint, min_y, max_y);
        const cut = ConvexPrism{
            .footprint = @constCast(footprint),
            .min_y = min_y,
            .max_y = max_y,
        };
        const cut_bounds = prismAabb(cut);
        var out: std.ArrayList(Aabb) = .empty;
        errdefer out.deinit(allocator);
        var out_prisms: std.ArrayList(ConvexPrism) = .empty;
        errdefer {
            for (out_prisms.items) |*prism| prism.deinit(allocator);
            out_prisms.deinit(allocator);
        }
        for (self.boxes) |source| {
            if (aabbIntersection(source, cut_bounds) == null) {
                try out.append(allocator, source);
                continue;
            }
            const source_footprint = [_]Point2{
                .{ source.min[0], source.min[2] },
                .{ source.max[0], source.min[2] },
                .{ source.max[0], source.max[2] },
                .{ source.min[0], source.max[2] },
            };
            const source_prism = ConvexPrism{
                .footprint = @constCast(&source_footprint),
                .min_y = source.min[1],
                .max_y = source.max[1],
            };
            try subtractPrismByPrism(allocator, &out_prisms, source_prism, cut);
        }
        for (self.prisms) |source| {
            try subtractPrismByPrism(allocator, &out_prisms, source, cut);
        }
        return .{
            .boxes = try out.toOwnedSlice(allocator),
            .prisms = try out_prisms.toOwnedSlice(allocator),
        };
    }

    pub fn toMesh(self: Solid, allocator: std.mem.Allocator) !Mesh {
        var vertices: std.ArrayList(MeshVertex) = .empty;
        defer vertices.deinit(allocator);
        var indices: std.ArrayList(u32) = .empty;
        defer indices.deinit(allocator);
        try appendBoxUnionMesh(allocator, &vertices, &indices, self.boxes, self.prisms);
        try appendPrismUnionMesh(allocator, &vertices, &indices, self.prisms, self.boxes);
        return .{
            .vertices = try vertices.toOwnedSlice(allocator),
            .indices = try indices.toOwnedSlice(allocator),
        };
    }
};

fn clonePrisms(allocator: std.mem.Allocator, source: []const ConvexPrism) ![]ConvexPrism {
    const prisms = try allocator.alloc(ConvexPrism, source.len);
    errdefer allocator.free(prisms);
    var initialized: usize = 0;
    errdefer {
        for (prisms[0..initialized]) |*prism| prism.deinit(allocator);
    }
    for (source, 0..) |prism, idx| {
        prisms[idx] = try prism.clone(allocator);
        initialized += 1;
    }
    return prisms;
}

pub fn boxBrush(bounds: Aabb) !Brush {
    try validateAabb(bounds);
    return .{ .box = bounds };
}

pub fn convexPrismBrush(allocator: std.mem.Allocator, footprint: []const Point2, min_y: f32, max_y: f32) !Brush {
    try validateConvexPrism(footprint, min_y, max_y);
    return .{ .convex_prism = .{
        .footprint = try allocator.dupe(Point2, footprint),
        .min_y = min_y,
        .max_y = max_y,
    } };
}

pub fn deinitBrush(allocator: std.mem.Allocator, brush: *Brush) void {
    switch (brush.*) {
        .box => {},
        .convex_prism => |*prism| prism.deinit(allocator),
    }
    brush.* = .{ .box = .{ .min = .{ 0, 0, 0 }, .max = .{ 1, 1, 1 } } };
}

pub fn validateAabb(bounds: Aabb) !void {
    if (bounds.max[0] <= bounds.min[0] or bounds.max[1] <= bounds.min[1] or bounds.max[2] <= bounds.min[2]) {
        return error.InvalidCsgBounds;
    }
}

pub fn validateConvexPrism(footprint: []const Point2, min_y: f32, max_y: f32) !void {
    if (footprint.len < 3) return error.InvalidCsgPrism;
    if (!std.math.isFinite(min_y) or !std.math.isFinite(max_y) or max_y <= min_y) return error.InvalidCsgPrism;
    var sign: f32 = 0;
    for (footprint, 0..) |point, idx| {
        if (!std.math.isFinite(point[0]) or !std.math.isFinite(point[1])) return error.InvalidCsgPrism;
        const next = footprint[(idx + 1) % footprint.len];
        const prev = footprint[(idx + footprint.len - 1) % footprint.len];
        const cross = cross2(prev, point, next);
        if (@abs(cross) <= 0.0001) return error.InvalidCsgPrism;
        const current_sign: f32 = if (cross > 0) 1 else -1;
        if (sign == 0) {
            sign = current_sign;
        } else if (sign != current_sign) {
            return error.InvalidCsgPrism;
        }
    }
}

pub fn aabbIntersection(a: Aabb, b: Aabb) ?Aabb {
    const min = [3]f32{
        @max(a.min[0], b.min[0]),
        @max(a.min[1], b.min[1]),
        @max(a.min[2], b.min[2]),
    };
    const max = [3]f32{
        @min(a.max[0], b.max[0]),
        @min(a.max[1], b.max[1]),
        @min(a.max[2], b.max[2]),
    };
    if (max[0] <= min[0] or max[1] <= min[1] or max[2] <= min[2]) return null;
    return .{ .min = min, .max = max };
}

pub fn splitAabbSubtract(source: Aabb, cut: Aabb, pieces: *[6]?Aabb) void {
    pieces.* = .{ null, null, null, null, null, null };
    var count: usize = 0;

    if (cut.min[0] > source.min[0]) {
        pieces[count] = .{ .min = source.min, .max = .{ cut.min[0], source.max[1], source.max[2] } };
        count += 1;
    }
    if (cut.max[0] < source.max[0]) {
        pieces[count] = .{ .min = .{ cut.max[0], source.min[1], source.min[2] }, .max = source.max };
        count += 1;
    }

    const mid_x_min = @max(source.min[0], cut.min[0]);
    const mid_x_max = @min(source.max[0], cut.max[0]);
    if (cut.min[1] > source.min[1]) {
        pieces[count] = .{ .min = .{ mid_x_min, source.min[1], source.min[2] }, .max = .{ mid_x_max, cut.min[1], source.max[2] } };
        count += 1;
    }
    if (cut.max[1] < source.max[1]) {
        pieces[count] = .{ .min = .{ mid_x_min, cut.max[1], source.min[2] }, .max = .{ mid_x_max, source.max[1], source.max[2] } };
        count += 1;
    }

    const mid_y_min = @max(source.min[1], cut.min[1]);
    const mid_y_max = @min(source.max[1], cut.max[1]);
    if (cut.min[2] > source.min[2]) {
        pieces[count] = .{ .min = .{ mid_x_min, mid_y_min, source.min[2] }, .max = .{ mid_x_max, mid_y_max, cut.min[2] } };
        count += 1;
    }
    if (cut.max[2] < source.max[2]) {
        pieces[count] = .{ .min = .{ mid_x_min, mid_y_min, cut.max[2] }, .max = .{ mid_x_max, mid_y_max, source.max[2] } };
    }
}

fn subtractPrismByBox(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(ConvexPrism),
    source: ConvexPrism,
    cut: Aabb,
) !void {
    const bounds = prismAabb(source);
    const intersection = aabbIntersection(bounds, cut) orelse {
        try appendPrismClone(allocator, out, source);
        return;
    };
    const y_min = @max(source.min_y, intersection.min[1]);
    const y_max = @min(source.max_y, intersection.max[1]);
    if (y_max <= y_min) {
        try appendPrismClone(allocator, out, source);
        return;
    }

    try appendPrismClipXMax(allocator, out, source.footprint, source.min_y, source.max_y, intersection.min[0]);
    try appendPrismClipXMin(allocator, out, source.footprint, source.min_y, source.max_y, intersection.max[0]);

    const middle_x = try clipFootprintXMin(allocator, source.footprint, intersection.min[0]);
    defer allocator.free(middle_x);
    if (middle_x.len < 3) return;
    const middle_x2 = try clipFootprintXMax(allocator, middle_x, intersection.max[0]);
    defer allocator.free(middle_x2);
    if (middle_x2.len < 3) return;

    if (intersection.min[1] > source.min_y) {
        try appendPrismOwnedFootprint(allocator, out, middle_x2, source.min_y, intersection.min[1]);
    }
    if (intersection.max[1] < source.max_y) {
        try appendPrismOwnedFootprint(allocator, out, middle_x2, intersection.max[1], source.max_y);
    }

    try appendPrismClipZMax(allocator, out, middle_x2, y_min, y_max, intersection.min[2]);
    try appendPrismClipZMin(allocator, out, middle_x2, y_min, y_max, intersection.max[2]);
}

fn appendPrismClipXMax(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(ConvexPrism),
    footprint: []const Point2,
    min_y: f32,
    max_y: f32,
    max_x: f32,
) !void {
    const clipped = try clipFootprintXMax(allocator, footprint, max_x);
    defer allocator.free(clipped);
    try appendPrismOwnedFootprint(allocator, out, clipped, min_y, max_y);
}

fn appendPrismClipXMin(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(ConvexPrism),
    footprint: []const Point2,
    min_y: f32,
    max_y: f32,
    min_x: f32,
) !void {
    const clipped = try clipFootprintXMin(allocator, footprint, min_x);
    defer allocator.free(clipped);
    try appendPrismOwnedFootprint(allocator, out, clipped, min_y, max_y);
}

fn appendPrismClipZMax(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(ConvexPrism),
    footprint: []const Point2,
    min_y: f32,
    max_y: f32,
    max_z: f32,
) !void {
    const clipped = try clipFootprintZMax(allocator, footprint, max_z);
    defer allocator.free(clipped);
    try appendPrismOwnedFootprint(allocator, out, clipped, min_y, max_y);
}

fn appendPrismClipZMin(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(ConvexPrism),
    footprint: []const Point2,
    min_y: f32,
    max_y: f32,
    min_z: f32,
) !void {
    const clipped = try clipFootprintZMin(allocator, footprint, min_z);
    defer allocator.free(clipped);
    try appendPrismOwnedFootprint(allocator, out, clipped, min_y, max_y);
}

fn appendPrismClone(allocator: std.mem.Allocator, out: *std.ArrayList(ConvexPrism), source: ConvexPrism) !void {
    try out.append(allocator, try source.clone(allocator));
}

fn appendPrismOwnedFootprint(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(ConvexPrism),
    footprint: []const Point2,
    min_y: f32,
    max_y: f32,
) !void {
    if (footprint.len < 3 or max_y - min_y <= 0.0001) return;
    const simplified = try simplifyFootprint(allocator, footprint);
    defer allocator.free(simplified);
    if (simplified.len < 3) return;
    validateConvexPrism(simplified, min_y, max_y) catch return;
    try out.append(allocator, .{
        .footprint = try allocator.dupe(Point2, simplified),
        .min_y = min_y,
        .max_y = max_y,
    });
}

fn subtractPrismByPrism(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(ConvexPrism),
    source: ConvexPrism,
    cut: ConvexPrism,
) !void {
    const source_bounds = prismAabb(source);
    const cut_bounds = prismAabb(cut);
    const intersection = aabbIntersection(source_bounds, cut_bounds) orelse {
        try appendPrismClone(allocator, out, source);
        return;
    };
    const y_min = @max(source.min_y, intersection.min[1]);
    const y_max = @min(source.max_y, intersection.max[1]);
    if (y_max <= y_min) {
        try appendPrismClone(allocator, out, source);
        return;
    }

    const overlap = try clipFootprintByConvex(allocator, source.footprint, cut.footprint, .inside);
    defer allocator.free(overlap);
    if (overlap.len < 3) {
        try appendPrismClone(allocator, out, source);
        return;
    }

    if (y_min > source.min_y) {
        try appendPrismOwnedFootprint(allocator, out, source.footprint, source.min_y, y_min);
    }
    if (y_max < source.max_y) {
        try appendPrismOwnedFootprint(allocator, out, source.footprint, y_max, source.max_y);
    }
    try appendFootprintMinusConvex(allocator, out, source.footprint, cut.footprint, y_min, y_max);
}

const HalfspaceKeep = enum { inside, outside };

fn appendFootprintMinusConvex(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(ConvexPrism),
    source: []const Point2,
    cut: []const Point2,
    min_y: f32,
    max_y: f32,
) !void {
    var remainder = try allocator.dupe(Point2, source);
    defer allocator.free(remainder);

    const winding: f32 = if (polygonArea2(cut) > 0) 1 else -1;
    for (cut, 0..) |edge_start, edge_index| {
        if (remainder.len < 3) return;
        const edge_end = cut[(edge_index + 1) % cut.len];
        const outside = try clipFootprintHalfspace(allocator, remainder, edge_start, edge_end, winding, .outside);
        defer allocator.free(outside);
        try appendPrismOwnedFootprint(allocator, out, outside, min_y, max_y);

        const next_remainder = try clipFootprintHalfspace(allocator, remainder, edge_start, edge_end, winding, .inside);
        allocator.free(remainder);
        remainder = next_remainder;
    }
}

fn clipFootprintByConvex(
    allocator: std.mem.Allocator,
    source: []const Point2,
    clip: []const Point2,
    keep: HalfspaceKeep,
) ![]Point2 {
    var current = try allocator.dupe(Point2, source);
    errdefer allocator.free(current);
    const winding: f32 = if (polygonArea2(clip) > 0) 1 else -1;
    for (clip, 0..) |edge_start, edge_index| {
        if (current.len < 3) break;
        const edge_end = clip[(edge_index + 1) % clip.len];
        const next = try clipFootprintHalfspace(allocator, current, edge_start, edge_end, winding, keep);
        allocator.free(current);
        current = next;
    }
    return current;
}

fn clipFootprintHalfspace(
    allocator: std.mem.Allocator,
    footprint: []const Point2,
    edge_start: Point2,
    edge_end: Point2,
    winding: f32,
    keep: HalfspaceKeep,
) ![]Point2 {
    var out: std.ArrayList(Point2) = .empty;
    defer out.deinit(allocator);
    if (footprint.len == 0) return out.toOwnedSlice(allocator);

    var prev = footprint[footprint.len - 1];
    var prev_inside = pointInsideHalfspace(prev, edge_start, edge_end, winding, keep);
    for (footprint) |current| {
        const current_inside = pointInsideHalfspace(current, edge_start, edge_end, winding, keep);
        if (current_inside != prev_inside) {
            try appendUniquePoint(allocator, &out, intersectHalfspace(prev, current, edge_start, edge_end, winding));
        }
        if (current_inside) {
            try appendUniquePoint(allocator, &out, current);
        }
        prev = current;
        prev_inside = current_inside;
    }
    return simplifyOwnedFootprint(allocator, try out.toOwnedSlice(allocator));
}

fn pointInsideHalfspace(point: Point2, edge_start: Point2, edge_end: Point2, winding: f32, keep: HalfspaceKeep) bool {
    const signed = edgeCross(edge_start, edge_end, point) * winding;
    return switch (keep) {
        .inside => signed >= -0.0001,
        .outside => signed <= 0.0001,
    };
}

fn intersectHalfspace(a: Point2, b: Point2, edge_start: Point2, edge_end: Point2, winding: f32) Point2 {
    const da = edgeCross(edge_start, edge_end, a) * winding;
    const db = edgeCross(edge_start, edge_end, b) * winding;
    const denom = da - db;
    if (@abs(denom) <= 0.0001) return a;
    const t = da / denom;
    return .{
        a[0] + (b[0] - a[0]) * t,
        a[1] + (b[1] - a[1]) * t,
    };
}

fn edgeCross(edge_start: Point2, edge_end: Point2, point: Point2) f32 {
    return (edge_end[0] - edge_start[0]) * (point[1] - edge_start[1]) -
        (edge_end[1] - edge_start[1]) * (point[0] - edge_start[0]);
}

fn simplifyFootprint(allocator: std.mem.Allocator, footprint: []const Point2) ![]Point2 {
    var out: std.ArrayList(Point2) = .empty;
    errdefer out.deinit(allocator);
    for (footprint) |point| {
        try appendUniquePoint(allocator, &out, point);
    }
    return simplifyOwnedFootprint(allocator, try out.toOwnedSlice(allocator));
}

fn simplifyOwnedFootprint(allocator: std.mem.Allocator, owned: []Point2) ![]Point2 {
    var points = owned;
    var changed = true;
    while (changed and points.len >= 3) {
        changed = false;
        var out: std.ArrayList(Point2) = .empty;
        errdefer out.deinit(allocator);
        for (points, 0..) |point, idx| {
            const prev = points[(idx + points.len - 1) % points.len];
            const next = points[(idx + 1) % points.len];
            if (@abs(cross2(prev, point, next)) <= 0.0001) {
                changed = true;
                continue;
            }
            try out.append(allocator, point);
        }
        allocator.free(points);
        points = try out.toOwnedSlice(allocator);
    }
    return points;
}

fn clipFootprintXMin(allocator: std.mem.Allocator, footprint: []const Point2, min_x: f32) ![]Point2 {
    return clipFootprintAxis(allocator, footprint, 0, min_x, .min);
}

fn clipFootprintXMax(allocator: std.mem.Allocator, footprint: []const Point2, max_x: f32) ![]Point2 {
    return clipFootprintAxis(allocator, footprint, 0, max_x, .max);
}

fn clipFootprintZMin(allocator: std.mem.Allocator, footprint: []const Point2, min_z: f32) ![]Point2 {
    return clipFootprintAxis(allocator, footprint, 1, min_z, .min);
}

fn clipFootprintZMax(allocator: std.mem.Allocator, footprint: []const Point2, max_z: f32) ![]Point2 {
    return clipFootprintAxis(allocator, footprint, 1, max_z, .max);
}

const ClipSide = enum { min, max };

fn clipFootprintAxis(
    allocator: std.mem.Allocator,
    footprint: []const Point2,
    axis: usize,
    value: f32,
    side: ClipSide,
) ![]Point2 {
    var out: std.ArrayList(Point2) = .empty;
    defer out.deinit(allocator);
    if (footprint.len == 0) return out.toOwnedSlice(allocator);
    var prev = footprint[footprint.len - 1];
    var prev_inside = pointInsideAxis(prev, axis, value, side);
    for (footprint) |current| {
        const current_inside = pointInsideAxis(current, axis, value, side);
        if (current_inside != prev_inside) {
            try appendUniquePoint(allocator, &out, intersectAxis(prev, current, axis, value));
        }
        if (current_inside) {
            try appendUniquePoint(allocator, &out, current);
        }
        prev = current;
        prev_inside = current_inside;
    }
    return out.toOwnedSlice(allocator);
}

fn pointInsideAxis(point: Point2, axis: usize, value: f32, side: ClipSide) bool {
    return switch (side) {
        .min => point[axis] >= value - 0.0001,
        .max => point[axis] <= value + 0.0001,
    };
}

fn intersectAxis(a: Point2, b: Point2, axis: usize, value: f32) Point2 {
    const denom = b[axis] - a[axis];
    if (@abs(denom) <= 0.0001) return a;
    const t = (value - a[axis]) / denom;
    return .{
        a[0] + (b[0] - a[0]) * t,
        a[1] + (b[1] - a[1]) * t,
    };
}

fn appendUniquePoint(allocator: std.mem.Allocator, points: *std.ArrayList(Point2), point: Point2) !void {
    if (points.items.len > 0 and pointsNear(points.items[points.items.len - 1], point)) return;
    if (points.items.len > 1 and pointsNear(points.items[0], point)) return;
    try points.append(allocator, point);
}

fn pointsNear(a: Point2, b: Point2) bool {
    return @abs(a[0] - b[0]) <= 0.0001 and @abs(a[1] - b[1]) <= 0.0001;
}

fn prismAabb(prism: ConvexPrism) Aabb {
    var min_x = prism.footprint[0][0];
    var max_x = min_x;
    var min_z = prism.footprint[0][1];
    var max_z = min_z;
    for (prism.footprint[1..]) |point| {
        min_x = @min(min_x, point[0]);
        max_x = @max(max_x, point[0]);
        min_z = @min(min_z, point[1]);
        max_z = @max(max_z, point[1]);
    }
    return .{
        .min = .{ min_x, prism.min_y, min_z },
        .max = .{ max_x, prism.max_y, max_z },
    };
}

pub fn appendBoxMesh(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(MeshVertex),
    indices: *std.ArrayList(u32),
    box: Aabb,
) !void {
    try appendQuad(
        allocator,
        vertices,
        indices,
        .{ box.min[0], box.min[1], box.max[2] },
        .{ box.max[0], box.min[1], box.max[2] },
        .{ box.max[0], box.max[1], box.max[2] },
        .{ box.min[0], box.max[1], box.max[2] },
        .{ 0, 0, 1 },
    );
    try appendQuad(
        allocator,
        vertices,
        indices,
        .{ box.max[0], box.min[1], box.min[2] },
        .{ box.min[0], box.min[1], box.min[2] },
        .{ box.min[0], box.max[1], box.min[2] },
        .{ box.max[0], box.max[1], box.min[2] },
        .{ 0, 0, -1 },
    );
    try appendQuad(
        allocator,
        vertices,
        indices,
        .{ box.max[0], box.min[1], box.max[2] },
        .{ box.max[0], box.min[1], box.min[2] },
        .{ box.max[0], box.max[1], box.min[2] },
        .{ box.max[0], box.max[1], box.max[2] },
        .{ 1, 0, 0 },
    );
    try appendQuad(
        allocator,
        vertices,
        indices,
        .{ box.min[0], box.min[1], box.min[2] },
        .{ box.min[0], box.min[1], box.max[2] },
        .{ box.min[0], box.max[1], box.max[2] },
        .{ box.min[0], box.max[1], box.min[2] },
        .{ -1, 0, 0 },
    );
    try appendQuad(
        allocator,
        vertices,
        indices,
        .{ box.min[0], box.max[1], box.max[2] },
        .{ box.max[0], box.max[1], box.max[2] },
        .{ box.max[0], box.max[1], box.min[2] },
        .{ box.min[0], box.max[1], box.min[2] },
        .{ 0, 1, 0 },
    );
    try appendQuad(
        allocator,
        vertices,
        indices,
        .{ box.min[0], box.min[1], box.min[2] },
        .{ box.max[0], box.min[1], box.min[2] },
        .{ box.max[0], box.min[1], box.max[2] },
        .{ box.min[0], box.min[1], box.max[2] },
        .{ 0, -1, 0 },
    );
}

fn appendBoxUnionMesh(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(MeshVertex),
    indices: *std.ArrayList(u32),
    boxes: []const Aabb,
    prisms: []const ConvexPrism,
) !void {
    const faces = [_]BoxFace{ .z_pos, .z_neg, .x_pos, .x_neg, .y_pos, .y_neg };
    for (boxes, 0..) |box, box_index| {
        for (faces) |face| {
            var remaining: std.ArrayList(Rect2) = .empty;
            defer remaining.deinit(allocator);
            try remaining.append(allocator, faceRect(box, face));
            for (boxes, 0..) |other, other_index| {
                if (box_index == other_index) continue;
                const cover = faceCoverRect(box, other, face) orelse continue;
                try subtractRectFromList(allocator, &remaining, cover);
                if (remaining.items.len == 0) break;
            }
            for (prisms) |prism| {
                const cover = faceCoverRectPrism(box, prism, face) orelse continue;
                try subtractRectFromList(allocator, &remaining, cover);
                if (remaining.items.len == 0) break;
            }
            for (remaining.items) |rect| {
                try appendBoxFaceRect(allocator, vertices, indices, box, face, rect);
            }
        }
    }
}

const BoxFace = enum {
    z_pos,
    z_neg,
    x_pos,
    x_neg,
    y_pos,
    y_neg,
};

const Rect2 = struct {
    min: [2]f32,
    max: [2]f32,
};

fn faceRect(box: Aabb, face: BoxFace) Rect2 {
    return switch (face) {
        .z_pos, .z_neg => .{ .min = .{ box.min[0], box.min[1] }, .max = .{ box.max[0], box.max[1] } },
        .x_pos, .x_neg => .{ .min = .{ box.min[2], box.min[1] }, .max = .{ box.max[2], box.max[1] } },
        .y_pos, .y_neg => .{ .min = .{ box.min[0], box.min[2] }, .max = .{ box.max[0], box.max[2] } },
    };
}

fn faceCoverRect(box: Aabb, other: Aabb, face: BoxFace) ?Rect2 {
    return switch (face) {
        .z_pos => if (near(other.min[2], box.max[2])) rectIntersection(faceRect(box, face), .{ .min = .{ other.min[0], other.min[1] }, .max = .{ other.max[0], other.max[1] } }) else null,
        .z_neg => if (near(other.max[2], box.min[2])) rectIntersection(faceRect(box, face), .{ .min = .{ other.min[0], other.min[1] }, .max = .{ other.max[0], other.max[1] } }) else null,
        .x_pos => if (near(other.min[0], box.max[0])) rectIntersection(faceRect(box, face), .{ .min = .{ other.min[2], other.min[1] }, .max = .{ other.max[2], other.max[1] } }) else null,
        .x_neg => if (near(other.max[0], box.min[0])) rectIntersection(faceRect(box, face), .{ .min = .{ other.min[2], other.min[1] }, .max = .{ other.max[2], other.max[1] } }) else null,
        .y_pos => if (near(other.min[1], box.max[1])) rectIntersection(faceRect(box, face), .{ .min = .{ other.min[0], other.min[2] }, .max = .{ other.max[0], other.max[2] } }) else null,
        .y_neg => if (near(other.max[1], box.min[1])) rectIntersection(faceRect(box, face), .{ .min = .{ other.min[0], other.min[2] }, .max = .{ other.max[0], other.max[2] } }) else null,
    };
}

fn faceCoverRectPrism(box: Aabb, prism: ConvexPrism, face: BoxFace) ?Rect2 {
    if (face == .y_pos or face == .y_neg) {
        const footprint_rect = footprintRect(prism.footprint) orelse return null;
        const touches = switch (face) {
            .y_pos => near(prism.min_y, box.max[1]),
            .y_neg => near(prism.max_y, box.min[1]),
            else => false,
        };
        if (!touches) return null;
        return rectIntersection(faceRect(box, face), footprint_rect);
    }
    const face_edge = boxFaceHorizontalEdge(box, face);
    for (prism.footprint, 0..) |point, idx| {
        const next = prism.footprint[(idx + 1) % prism.footprint.len];
        if (!collinearSegments(face_edge[0], face_edge[1], next, point)) continue;
        const overlap = segmentOverlapOnFace(face_edge[0], face_edge[1], next, point) orelse continue;
        const y_overlap = intervalIntersection(box.min[1], box.max[1], prism.min_y, prism.max_y) orelse continue;
        return .{ .min = .{ overlap[0], y_overlap[0] }, .max = .{ overlap[1], y_overlap[1] } };
    }
    return null;
}

fn rectIntersection(a: Rect2, b: Rect2) ?Rect2 {
    const rect = Rect2{
        .min = .{ @max(a.min[0], b.min[0]), @max(a.min[1], b.min[1]) },
        .max = .{ @min(a.max[0], b.max[0]), @min(a.max[1], b.max[1]) },
    };
    if (rect.max[0] - rect.min[0] <= 0.0001 or rect.max[1] - rect.min[1] <= 0.0001) return null;
    return rect;
}

fn subtractRectFromList(allocator: std.mem.Allocator, rects: *std.ArrayList(Rect2), cut: Rect2) !void {
    var next: std.ArrayList(Rect2) = .empty;
    errdefer next.deinit(allocator);
    for (rects.items) |rect| {
        if (rectIntersection(rect, cut)) |intersection| {
            try appendRectSubtract(allocator, &next, rect, intersection);
        } else {
            try next.append(allocator, rect);
        }
    }
    rects.clearRetainingCapacity();
    try rects.appendSlice(allocator, next.items);
    next.deinit(allocator);
}

fn appendRectSubtract(allocator: std.mem.Allocator, out: *std.ArrayList(Rect2), source: Rect2, cut: Rect2) !void {
    if (cut.min[0] > source.min[0] + 0.0001) {
        try appendValidRect(allocator, out, .{ .min = source.min, .max = .{ cut.min[0], source.max[1] } });
    }
    if (cut.max[0] < source.max[0] - 0.0001) {
        try appendValidRect(allocator, out, .{ .min = .{ cut.max[0], source.min[1] }, .max = source.max });
    }
    const mid_min_u = @max(source.min[0], cut.min[0]);
    const mid_max_u = @min(source.max[0], cut.max[0]);
    if (cut.min[1] > source.min[1] + 0.0001) {
        try appendValidRect(allocator, out, .{ .min = .{ mid_min_u, source.min[1] }, .max = .{ mid_max_u, cut.min[1] } });
    }
    if (cut.max[1] < source.max[1] - 0.0001) {
        try appendValidRect(allocator, out, .{ .min = .{ mid_min_u, cut.max[1] }, .max = .{ mid_max_u, source.max[1] } });
    }
}

fn appendValidRect(allocator: std.mem.Allocator, out: *std.ArrayList(Rect2), rect: Rect2) !void {
    if (rect.max[0] - rect.min[0] <= 0.0001 or rect.max[1] - rect.min[1] <= 0.0001) return;
    try out.append(allocator, rect);
}

fn appendBoxFaceRect(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(MeshVertex),
    indices: *std.ArrayList(u32),
    box: Aabb,
    face: BoxFace,
    rect: Rect2,
) !void {
    switch (face) {
        .z_pos => try appendQuad(
            allocator,
            vertices,
            indices,
            .{ rect.min[0], rect.min[1], box.max[2] },
            .{ rect.max[0], rect.min[1], box.max[2] },
            .{ rect.max[0], rect.max[1], box.max[2] },
            .{ rect.min[0], rect.max[1], box.max[2] },
            .{ 0, 0, 1 },
        ),
        .z_neg => try appendQuad(
            allocator,
            vertices,
            indices,
            .{ rect.max[0], rect.min[1], box.min[2] },
            .{ rect.min[0], rect.min[1], box.min[2] },
            .{ rect.min[0], rect.max[1], box.min[2] },
            .{ rect.max[0], rect.max[1], box.min[2] },
            .{ 0, 0, -1 },
        ),
        .x_pos => try appendQuad(
            allocator,
            vertices,
            indices,
            .{ box.max[0], rect.min[1], rect.max[0] },
            .{ box.max[0], rect.min[1], rect.min[0] },
            .{ box.max[0], rect.max[1], rect.min[0] },
            .{ box.max[0], rect.max[1], rect.max[0] },
            .{ 1, 0, 0 },
        ),
        .x_neg => try appendQuad(
            allocator,
            vertices,
            indices,
            .{ box.min[0], rect.min[1], rect.min[0] },
            .{ box.min[0], rect.min[1], rect.max[0] },
            .{ box.min[0], rect.max[1], rect.max[0] },
            .{ box.min[0], rect.max[1], rect.min[0] },
            .{ -1, 0, 0 },
        ),
        .y_pos => try appendQuad(
            allocator,
            vertices,
            indices,
            .{ rect.min[0], box.max[1], rect.max[1] },
            .{ rect.max[0], box.max[1], rect.max[1] },
            .{ rect.max[0], box.max[1], rect.min[1] },
            .{ rect.min[0], box.max[1], rect.min[1] },
            .{ 0, 1, 0 },
        ),
        .y_neg => try appendQuad(
            allocator,
            vertices,
            indices,
            .{ rect.min[0], box.min[1], rect.min[1] },
            .{ rect.max[0], box.min[1], rect.min[1] },
            .{ rect.max[0], box.min[1], rect.max[1] },
            .{ rect.min[0], box.min[1], rect.max[1] },
            .{ 0, -1, 0 },
        ),
    }
}

fn near(a: f32, b: f32) bool {
    return @abs(a - b) <= 0.0001;
}

fn boxFaceHorizontalEdge(box: Aabb, face: BoxFace) [2]Point2 {
    return switch (face) {
        .z_pos => .{ .{ box.min[0], box.max[2] }, .{ box.max[0], box.max[2] } },
        .z_neg => .{ .{ box.max[0], box.min[2] }, .{ box.min[0], box.min[2] } },
        .x_pos => .{ .{ box.max[0], box.max[2] }, .{ box.max[0], box.min[2] } },
        .x_neg => .{ .{ box.min[0], box.min[2] }, .{ box.min[0], box.max[2] } },
        .y_pos, .y_neg => .{ .{ 0, 0 }, .{ 0, 0 } },
    };
}

fn collinearSegments(a0: Point2, a1: Point2, b0: Point2, b1: Point2) bool {
    return @abs(edgeCross(a0, a1, b0)) <= 0.0001 and @abs(edgeCross(a0, a1, b1)) <= 0.0001;
}

fn segmentOverlapOnFace(face_start: Point2, face_end: Point2, cover_start: Point2, cover_end: Point2) ?[2]f32 {
    const axis: usize = if (@abs(face_end[0] - face_start[0]) >= @abs(face_end[1] - face_start[1])) 0 else 1;
    const face_min = @min(face_start[axis], face_end[axis]);
    const face_max = @max(face_start[axis], face_end[axis]);
    const cover_min = @min(cover_start[axis], cover_end[axis]);
    const cover_max = @max(cover_start[axis], cover_end[axis]);
    return intervalIntersection(face_min, face_max, cover_min, cover_max);
}

fn intervalIntersection(a_min: f32, a_max: f32, b_min: f32, b_max: f32) ?[2]f32 {
    const min_value = @max(a_min, b_min);
    const max_value = @min(a_max, b_max);
    if (max_value - min_value <= 0.0001) return null;
    return .{ min_value, max_value };
}

fn footprintRect(footprint: []const Point2) ?Rect2 {
    if (footprint.len != 4) return null;
    var min_x = footprint[0][0];
    var max_x = min_x;
    var min_z = footprint[0][1];
    var max_z = min_z;
    for (footprint[1..]) |point| {
        min_x = @min(min_x, point[0]);
        max_x = @max(max_x, point[0]);
        min_z = @min(min_z, point[1]);
        max_z = @max(max_z, point[1]);
    }
    var corners = [_]bool{ false, false, false, false };
    for (footprint) |point| {
        const idx: usize = if (near(point[0], min_x) and near(point[1], min_z))
            0
        else if (near(point[0], max_x) and near(point[1], min_z))
            1
        else if (near(point[0], max_x) and near(point[1], max_z))
            2
        else if (near(point[0], min_x) and near(point[1], max_z))
            3
        else
            return null;
        if (corners[idx]) return null;
        corners[idx] = true;
    }
    return .{ .min = .{ min_x, min_z }, .max = .{ max_x, max_z } };
}

pub fn appendConvexPrismMesh(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(MeshVertex),
    indices: *std.ArrayList(u32),
    prism: ConvexPrism,
) !void {
    try validateConvexPrism(prism.footprint, prism.min_y, prism.max_y);
    const area = polygonArea2(prism.footprint);
    const winding: f32 = if (area > 0) 1 else -1;

    var i: usize = 1;
    while (i + 1 < prism.footprint.len) : (i += 1) {
        if (winding > 0) {
            try appendTri(allocator, vertices, indices, pointAtY(prism.footprint[0], prism.max_y), pointAtY(prism.footprint[i + 1], prism.max_y), pointAtY(prism.footprint[i], prism.max_y), .{ 0, 1, 0 });
            try appendTri(allocator, vertices, indices, pointAtY(prism.footprint[0], prism.min_y), pointAtY(prism.footprint[i], prism.min_y), pointAtY(prism.footprint[i + 1], prism.min_y), .{ 0, -1, 0 });
        } else {
            try appendTri(allocator, vertices, indices, pointAtY(prism.footprint[0], prism.max_y), pointAtY(prism.footprint[i], prism.max_y), pointAtY(prism.footprint[i + 1], prism.max_y), .{ 0, 1, 0 });
            try appendTri(allocator, vertices, indices, pointAtY(prism.footprint[0], prism.min_y), pointAtY(prism.footprint[i + 1], prism.min_y), pointAtY(prism.footprint[i], prism.min_y), .{ 0, -1, 0 });
        }
    }

    for (prism.footprint, 0..) |point, idx| {
        const next = prism.footprint[(idx + 1) % prism.footprint.len];
        const dx = next[0] - point[0];
        const dz = next[1] - point[1];
        const len = @max(0.0001, @sqrt(dx * dx + dz * dz));
        const normal: [3]f32 = .{ winding * dz / len, 0, -winding * dx / len };
        try appendQuad(
            allocator,
            vertices,
            indices,
            pointAtY(point, prism.min_y),
            pointAtY(next, prism.min_y),
            pointAtY(next, prism.max_y),
            pointAtY(point, prism.max_y),
            normal,
        );
    }
}

fn appendPrismUnionMesh(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(MeshVertex),
    indices: *std.ArrayList(u32),
    prisms: []const ConvexPrism,
    boxes: []const Aabb,
) !void {
    for (prisms, 0..) |prism, prism_index| {
        try appendConvexPrismVisibleCaps(allocator, vertices, indices, prism, prism_index, prisms, boxes);
        try appendConvexPrismVisibleSides(allocator, vertices, indices, prism, prism_index, prisms, boxes);
    }
}

fn appendConvexPrismVisibleCaps(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(MeshVertex),
    indices: *std.ArrayList(u32),
    prism: ConvexPrism,
    prism_index: usize,
    prisms: []const ConvexPrism,
    boxes: []const Aabb,
) !void {
    try appendPrismCapPolygons(allocator, vertices, indices, prism, prism_index, prisms, boxes, .top);
    try appendPrismCapPolygons(allocator, vertices, indices, prism, prism_index, prisms, boxes, .bottom);
}

const PrismCap = enum { top, bottom };

fn appendPrismCapPolygons(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(MeshVertex),
    indices: *std.ArrayList(u32),
    prism: ConvexPrism,
    prism_index: usize,
    prisms: []const ConvexPrism,
    boxes: []const Aabb,
    cap: PrismCap,
) !void {
    var remaining: std.ArrayList(ConvexPrism) = .empty;
    defer {
        for (remaining.items) |*item| item.deinit(allocator);
        remaining.deinit(allocator);
    }
    try appendPrismOwnedFootprint(allocator, &remaining, prism.footprint, 0, 1);
    const cap_y = if (cap == .top) prism.max_y else prism.min_y;
    for (boxes) |box| {
        const touches = if (cap == .top) near(box.min[1], cap_y) else near(box.max[1], cap_y);
        if (!touches) continue;
        const cover = [_]Point2{
            .{ box.min[0], box.min[2] },
            .{ box.max[0], box.min[2] },
            .{ box.max[0], box.max[2] },
            .{ box.min[0], box.max[2] },
        };
        try subtractCoverFromCapFootprints(allocator, &remaining, &cover);
        if (remaining.items.len == 0) break;
    }
    for (prisms, 0..) |other, other_index| {
        if (prism_index == other_index) continue;
        const touches = if (cap == .top) near(other.min_y, cap_y) else near(other.max_y, cap_y);
        if (!touches) continue;
        try subtractCoverFromCapFootprints(allocator, &remaining, other.footprint);
        if (remaining.items.len == 0) break;
    }
    for (remaining.items) |visible| {
        try appendPrismCapFootprint(allocator, vertices, indices, visible.footprint, cap_y, cap);
    }
}

fn subtractCoverFromCapFootprints(
    allocator: std.mem.Allocator,
    footprints: *std.ArrayList(ConvexPrism),
    cover: []const Point2,
) !void {
    var next: std.ArrayList(ConvexPrism) = .empty;
    errdefer {
        for (next.items) |*item| item.deinit(allocator);
        next.deinit(allocator);
    }
    for (footprints.items) |source| {
        const overlap = try clipFootprintByConvex(allocator, source.footprint, cover, .inside);
        defer allocator.free(overlap);
        if (overlap.len < 3) {
            try appendPrismClone(allocator, &next, source);
            continue;
        }
        try appendFootprintMinusConvex(allocator, &next, source.footprint, cover, 0, 1);
    }
    for (footprints.items) |*item| item.deinit(allocator);
    footprints.clearRetainingCapacity();
    try footprints.appendSlice(allocator, next.items);
    next.deinit(allocator);
}

fn appendPrismCapFootprint(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(MeshVertex),
    indices: *std.ArrayList(u32),
    footprint: []const Point2,
    y: f32,
    cap: PrismCap,
) !void {
    const area = polygonArea2(footprint);
    const winding: f32 = if (area > 0) 1 else -1;
    var i: usize = 1;
    while (i + 1 < footprint.len) : (i += 1) {
        switch (cap) {
            .top => if (winding > 0) {
                try appendTri(allocator, vertices, indices, pointAtY(footprint[0], y), pointAtY(footprint[i + 1], y), pointAtY(footprint[i], y), .{ 0, 1, 0 });
            } else {
                try appendTri(allocator, vertices, indices, pointAtY(footprint[0], y), pointAtY(footprint[i], y), pointAtY(footprint[i + 1], y), .{ 0, 1, 0 });
            },
            .bottom => if (winding > 0) {
                try appendTri(allocator, vertices, indices, pointAtY(footprint[0], y), pointAtY(footprint[i], y), pointAtY(footprint[i + 1], y), .{ 0, -1, 0 });
            } else {
                try appendTri(allocator, vertices, indices, pointAtY(footprint[0], y), pointAtY(footprint[i + 1], y), pointAtY(footprint[i], y), .{ 0, -1, 0 });
            },
        }
    }
}

fn appendPrismCapRects(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(MeshVertex),
    indices: *std.ArrayList(u32),
    prism: ConvexPrism,
    prism_index: usize,
    prisms: []const ConvexPrism,
    boxes: []const Aabb,
    rect: Rect2,
    cap: PrismCap,
) !void {
    var remaining: std.ArrayList(Rect2) = .empty;
    defer remaining.deinit(allocator);
    try remaining.append(allocator, rect);
    const cap_y = if (cap == .top) prism.max_y else prism.min_y;
    for (boxes) |box| {
        const touches = if (cap == .top) near(box.min[1], cap_y) else near(box.max[1], cap_y);
        if (!touches) continue;
        const cover = rectIntersection(rect, .{ .min = .{ box.min[0], box.min[2] }, .max = .{ box.max[0], box.max[2] } }) orelse continue;
        try subtractRectFromList(allocator, &remaining, cover);
        if (remaining.items.len == 0) break;
    }
    for (prisms, 0..) |other, other_index| {
        if (prism_index == other_index) continue;
        const touches = if (cap == .top) near(other.min_y, cap_y) else near(other.max_y, cap_y);
        if (!touches) continue;
        const other_rect = footprintRect(other.footprint) orelse continue;
        const cover = rectIntersection(rect, other_rect) orelse continue;
        try subtractRectFromList(allocator, &remaining, cover);
        if (remaining.items.len == 0) break;
    }
    for (remaining.items) |visible| {
        try appendPrismCapRect(allocator, vertices, indices, visible, cap_y, cap);
    }
}

fn appendPrismCapRect(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(MeshVertex),
    indices: *std.ArrayList(u32),
    rect: Rect2,
    y: f32,
    cap: PrismCap,
) !void {
    switch (cap) {
        .top => try appendQuad(
            allocator,
            vertices,
            indices,
            .{ rect.min[0], y, rect.max[1] },
            .{ rect.max[0], y, rect.max[1] },
            .{ rect.max[0], y, rect.min[1] },
            .{ rect.min[0], y, rect.min[1] },
            .{ 0, 1, 0 },
        ),
        .bottom => try appendQuad(
            allocator,
            vertices,
            indices,
            .{ rect.min[0], y, rect.min[1] },
            .{ rect.max[0], y, rect.min[1] },
            .{ rect.max[0], y, rect.max[1] },
            .{ rect.min[0], y, rect.max[1] },
            .{ 0, -1, 0 },
        ),
    }
}

fn appendConvexPrismCaps(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(MeshVertex),
    indices: *std.ArrayList(u32),
    prism: ConvexPrism,
) !void {
    try validateConvexPrism(prism.footprint, prism.min_y, prism.max_y);
    const area = polygonArea2(prism.footprint);
    const winding: f32 = if (area > 0) 1 else -1;

    var i: usize = 1;
    while (i + 1 < prism.footprint.len) : (i += 1) {
        if (winding > 0) {
            try appendTri(allocator, vertices, indices, pointAtY(prism.footprint[0], prism.max_y), pointAtY(prism.footprint[i + 1], prism.max_y), pointAtY(prism.footprint[i], prism.max_y), .{ 0, 1, 0 });
            try appendTri(allocator, vertices, indices, pointAtY(prism.footprint[0], prism.min_y), pointAtY(prism.footprint[i], prism.min_y), pointAtY(prism.footprint[i + 1], prism.min_y), .{ 0, -1, 0 });
        } else {
            try appendTri(allocator, vertices, indices, pointAtY(prism.footprint[0], prism.max_y), pointAtY(prism.footprint[i], prism.max_y), pointAtY(prism.footprint[i + 1], prism.max_y), .{ 0, 1, 0 });
            try appendTri(allocator, vertices, indices, pointAtY(prism.footprint[0], prism.min_y), pointAtY(prism.footprint[i + 1], prism.min_y), pointAtY(prism.footprint[i], prism.min_y), .{ 0, -1, 0 });
        }
    }
}

fn appendConvexPrismVisibleSides(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(MeshVertex),
    indices: *std.ArrayList(u32),
    prism: ConvexPrism,
    prism_index: usize,
    prisms: []const ConvexPrism,
    boxes: []const Aabb,
) !void {
    try validateConvexPrism(prism.footprint, prism.min_y, prism.max_y);
    const area = polygonArea2(prism.footprint);
    const winding: f32 = if (area > 0) 1 else -1;
    for (prism.footprint, 0..) |point, idx| {
        const next = prism.footprint[(idx + 1) % prism.footprint.len];
        if (prismSideCovered(prism, prism_index, point, next, prisms)) continue;
        const dx = next[0] - point[0];
        const dz = next[1] - point[1];
        const len = @max(0.0001, @sqrt(dx * dx + dz * dz));
        const normal: [3]f32 = .{ winding * dz / len, 0, -winding * dx / len };
        var remaining: std.ArrayList(Rect2) = .empty;
        defer remaining.deinit(allocator);
        try remaining.append(allocator, .{ .min = .{ 0, prism.min_y }, .max = .{ 1, prism.max_y } });
        for (prisms, 0..) |other, other_index| {
            if (prism_index == other_index) continue;
            const cover = prismSideCoverRectPrism(prism, point, next, other) orelse continue;
            try subtractRectFromList(allocator, &remaining, cover);
            if (remaining.items.len == 0) break;
        }
        for (boxes) |box| {
            const cover = prismSideCoverRectBox(prism, point, next, box) orelse continue;
            try subtractRectFromList(allocator, &remaining, cover);
            if (remaining.items.len == 0) break;
        }
        for (remaining.items) |rect| {
            try appendPrismSideRect(allocator, vertices, indices, point, next, rect, normal);
        }
    }
}

fn prismSideCoverRectBox(prism: ConvexPrism, point: Point2, next: Point2, box: Aabb) ?Rect2 {
    const faces = [_]BoxFace{ .z_pos, .z_neg, .x_pos, .x_neg };
    const y_overlap = intervalIntersection(prism.min_y, prism.max_y, box.min[1], box.max[1]) orelse return null;
    for (faces) |face| {
        const edge = boxFaceHorizontalEdge(box, face);
        if (!collinearSegments(point, next, edge[1], edge[0])) continue;
        const overlap = segmentOverlapT(point, next, edge[1], edge[0]) orelse continue;
        return .{ .min = .{ overlap[0], y_overlap[0] }, .max = .{ overlap[1], y_overlap[1] } };
    }
    return null;
}

fn prismSideCoverRectPrism(prism: ConvexPrism, point: Point2, next: Point2, other: ConvexPrism) ?Rect2 {
    const y_overlap = intervalIntersection(prism.min_y, prism.max_y, other.min_y, other.max_y) orelse return null;
    for (other.footprint, 0..) |other_point, other_edge_index| {
        const other_next = other.footprint[(other_edge_index + 1) % other.footprint.len];
        if (!collinearSegments(point, next, other_next, other_point)) continue;
        const overlap = segmentOverlapT(point, next, other_next, other_point) orelse continue;
        return .{ .min = .{ overlap[0], y_overlap[0] }, .max = .{ overlap[1], y_overlap[1] } };
    }
    return null;
}

fn appendPrismSideRect(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(MeshVertex),
    indices: *std.ArrayList(u32),
    point: Point2,
    next: Point2,
    rect: Rect2,
    normal: [3]f32,
) !void {
    const p0 = pointAtY(pointAtT(point, next, rect.min[0]), rect.min[1]);
    const p1 = pointAtY(pointAtT(point, next, rect.max[0]), rect.min[1]);
    const p2 = pointAtY(pointAtT(point, next, rect.max[0]), rect.max[1]);
    const p3 = pointAtY(pointAtT(point, next, rect.min[0]), rect.max[1]);
    try appendQuad(allocator, vertices, indices, p0, p1, p2, p3, normal);
}

fn pointAtT(a: Point2, b: Point2, t: f32) Point2 {
    return .{
        a[0] + (b[0] - a[0]) * t,
        a[1] + (b[1] - a[1]) * t,
    };
}

fn segmentOverlapT(seg_start: Point2, seg_end: Point2, cover_start: Point2, cover_end: Point2) ?[2]f32 {
    const axis: usize = if (@abs(seg_end[0] - seg_start[0]) >= @abs(seg_end[1] - seg_start[1])) 0 else 1;
    const denom = seg_end[axis] - seg_start[axis];
    if (@abs(denom) <= 0.0001) return null;
    const t0 = (cover_start[axis] - seg_start[axis]) / denom;
    const t1 = (cover_end[axis] - seg_start[axis]) / denom;
    const cover_min = @min(t0, t1);
    const cover_max = @max(t0, t1);
    return intervalIntersection(0, 1, cover_min, cover_max);
}

fn prismSideCovered(
    prism: ConvexPrism,
    prism_index: usize,
    point: Point2,
    next: Point2,
    prisms: []const ConvexPrism,
) bool {
    for (prisms, 0..) |other, other_index| {
        if (prism_index == other_index) continue;
        if (!near(prism.min_y, other.min_y) or !near(prism.max_y, other.max_y)) continue;
        for (other.footprint, 0..) |other_point, other_edge_index| {
            const other_next = other.footprint[(other_edge_index + 1) % other.footprint.len];
            if (pointsNear(point, other_next) and pointsNear(next, other_point)) return true;
        }
    }
    return false;
}

fn appendQuad(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(MeshVertex),
    indices: *std.ArrayList(u32),
    p0: [3]f32,
    p1: [3]f32,
    p2: [3]f32,
    p3: [3]f32,
    normal: [3]f32,
) !void {
    const base: u32 = @intCast(vertices.items.len);
    const u_len = pointDistance3(p0, p1) / default_meters_per_repeat;
    const v_len = pointDistance3(p0, p3) / default_meters_per_repeat;
    try vertices.append(allocator, .{ .position = p0, .normal = normal, .uv = .{ 0, 0 } });
    try vertices.append(allocator, .{ .position = p1, .normal = normal, .uv = .{ u_len, 0 } });
    try vertices.append(allocator, .{ .position = p2, .normal = normal, .uv = .{ u_len, v_len } });
    try vertices.append(allocator, .{ .position = p3, .normal = normal, .uv = .{ 0, v_len } });
    try indices.appendSlice(allocator, &.{ base, base + 2, base + 1, base, base + 3, base + 2 });
}

fn appendTri(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(MeshVertex),
    indices: *std.ArrayList(u32),
    p0: [3]f32,
    p1: [3]f32,
    p2: [3]f32,
    normal: [3]f32,
) !void {
    const base: u32 = @intCast(vertices.items.len);
    const uv = triangleUvs(p0, p1, p2);
    try vertices.append(allocator, .{ .position = p0, .normal = normal, .uv = .{ 0, 0 } });
    try vertices.append(allocator, .{ .position = p1, .normal = normal, .uv = uv[1] });
    try vertices.append(allocator, .{ .position = p2, .normal = normal, .uv = uv[2] });
    try indices.appendSlice(allocator, &.{ base, base + 1, base + 2 });
}

fn pointDistance3(a: [3]f32, b: [3]f32) f32 {
    const dx = b[0] - a[0];
    const dy = b[1] - a[1];
    const dz = b[2] - a[2];
    return @sqrt(dx * dx + dy * dy + dz * dz);
}

fn triangleUvs(p0: [3]f32, p1: [3]f32, p2: [3]f32) [3][2]f32 {
    const u_len = @max(0.0001, pointDistance3(p0, p1));
    const ux = (p1[0] - p0[0]) / u_len;
    const uy = (p1[1] - p0[1]) / u_len;
    const uz = (p1[2] - p0[2]) / u_len;
    const dx = p2[0] - p0[0];
    const dy = p2[1] - p0[1];
    const dz = p2[2] - p0[2];
    const proj = dx * ux + dy * uy + dz * uz;
    const px = dx - ux * proj;
    const py = dy - uy * proj;
    const pz = dz - uz * proj;
    return .{
        .{ 0, 0 },
        .{ u_len / default_meters_per_repeat, 0 },
        .{ proj / default_meters_per_repeat, @sqrt(px * px + py * py + pz * pz) / default_meters_per_repeat },
    };
}

fn pointAtY(point: Point2, y: f32) [3]f32 {
    return .{ point[0], y, point[1] };
}

fn cross2(a: Point2, b: Point2, c: Point2) f32 {
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]);
}

fn polygonArea2(footprint: []const Point2) f32 {
    var area: f32 = 0;
    for (footprint, 0..) |point, idx| {
        const next = footprint[(idx + 1) % footprint.len];
        area += point[0] * next[1] - next[0] * point[1];
    }
    return area;
}

test "solid subtract splits an interior box cut into six boxes" {
    const source = try Solid.fromBox(std.testing.allocator, .{ .min = .{ 0, 0, 0 }, .max = .{ 4, 4, 4 } });
    defer {
        var owned = source;
        owned.deinit(std.testing.allocator);
    }
    var result = try source.subtractBox(std.testing.allocator, .{ .min = .{ 1, 1, 1 }, .max = .{ 3, 3, 3 } });
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 6), result.boxes.len);
    var mesh = try result.toMesh(std.testing.allocator);
    defer mesh.deinit(std.testing.allocator);
    try std.testing.expect(mesh.vertices.len < 6 * 24);
}

test "solid union preserves authored boxes" {
    var a = try Solid.fromBox(std.testing.allocator, .{ .min = .{ 0, 0, 0 }, .max = .{ 1, 1, 1 } });
    defer a.deinit(std.testing.allocator);
    var b = try Solid.fromBox(std.testing.allocator, .{ .min = .{ 1, 0, 0 }, .max = .{ 2, 1, 1 } });
    defer b.deinit(std.testing.allocator);
    var result = try a.unionWith(std.testing.allocator, b);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), result.boxes.len);
}

test "solid box union mesh suppresses shared full faces" {
    var a = try Solid.fromBox(std.testing.allocator, .{ .min = .{ 0, 0, 0 }, .max = .{ 1, 1, 1 } });
    defer a.deinit(std.testing.allocator);
    var b = try Solid.fromBox(std.testing.allocator, .{ .min = .{ 1, 0, 0 }, .max = .{ 2, 1, 1 } });
    defer b.deinit(std.testing.allocator);
    var result = try a.unionWith(std.testing.allocator, b);
    defer result.deinit(std.testing.allocator);
    var mesh = try result.toMesh(std.testing.allocator);
    defer mesh.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 40), mesh.vertices.len);
    try std.testing.expectEqual(@as(usize, 60), mesh.indices.len);
}

test "solid mesh export emits full box faces" {
    var solid = try Solid.fromBox(std.testing.allocator, .{ .min = .{ 0, 0, 0 }, .max = .{ 1, 2, 3 } });
    defer solid.deinit(std.testing.allocator);
    var mesh = try solid.toMesh(std.testing.allocator);
    defer mesh.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 24), mesh.vertices.len);
    try std.testing.expectEqual(@as(usize, 36), mesh.indices.len);
}

test "solid convex prism mesh export emits caps and sides" {
    const footprint = [_]Point2{
        .{ 0, 0 },
        .{ 2, 0 },
        .{ 2, 1 },
        .{ 0, 1 },
    };
    var solid = try Solid.fromConvexPrism(std.testing.allocator, &footprint, 0, 2);
    defer solid.deinit(std.testing.allocator);
    var mesh = try solid.toMesh(std.testing.allocator);
    defer mesh.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 36), mesh.vertices.len);
    try std.testing.expectEqual(@as(usize, 60), mesh.indices.len);
}

test "solid convex prism rejects concave footprints" {
    const footprint = [_]Point2{
        .{ 0, 0 },
        .{ 2, 0 },
        .{ 1, 0.5 },
        .{ 2, 1 },
        .{ 0, 1 },
    };
    try std.testing.expectError(error.InvalidCsgPrism, Solid.fromConvexPrism(std.testing.allocator, &footprint, 0, 1));
}

test "solid union can combine box and convex prism fragments" {
    var box = try Solid.fromBox(std.testing.allocator, .{ .min = .{ 0, 0, 0 }, .max = .{ 1, 1, 1 } });
    defer box.deinit(std.testing.allocator);
    const footprint = [_]Point2{
        .{ 0, 0 },
        .{ 1, 0 },
        .{ 0.5, 1 },
    };
    var prism = try Solid.fromConvexPrism(std.testing.allocator, &footprint, 0, 1);
    defer prism.deinit(std.testing.allocator);
    var combined = try box.unionWith(std.testing.allocator, prism);
    defer combined.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), combined.boxes.len);
    try std.testing.expectEqual(@as(usize, 1), combined.prisms.len);
    var mesh = try combined.toMesh(std.testing.allocator);
    defer mesh.deinit(std.testing.allocator);
    try std.testing.expect(mesh.vertices.len > 24);
}

test "solid mixed box prism union mesh suppresses exact shared vertical side faces" {
    var box = try Solid.fromBox(std.testing.allocator, .{ .min = .{ 0, 0, 0 }, .max = .{ 1, 1, 1 } });
    defer box.deinit(std.testing.allocator);
    const footprint = [_]Point2{
        .{ 1, 0 },
        .{ 2, 0 },
        .{ 2, 1 },
        .{ 1, 1 },
    };
    var prism = try Solid.fromConvexPrism(std.testing.allocator, &footprint, 0, 1);
    defer prism.deinit(std.testing.allocator);
    var box_mesh = try box.toMesh(std.testing.allocator);
    defer box_mesh.deinit(std.testing.allocator);
    var prism_mesh = try prism.toMesh(std.testing.allocator);
    defer prism_mesh.deinit(std.testing.allocator);
    var combined = try box.unionWith(std.testing.allocator, prism);
    defer combined.deinit(std.testing.allocator);
    var combined_mesh = try combined.toMesh(std.testing.allocator);
    defer combined_mesh.deinit(std.testing.allocator);
    try std.testing.expect(combined_mesh.vertices.len < box_mesh.vertices.len + prism_mesh.vertices.len);
    try std.testing.expect(combined_mesh.indices.len < box_mesh.indices.len + prism_mesh.indices.len);
}

test "solid mixed box prism union mesh clips partial shared vertical faces" {
    var box = try Solid.fromBox(std.testing.allocator, .{ .min = .{ 0, 0, 0 }, .max = .{ 1, 2, 2 } });
    defer box.deinit(std.testing.allocator);
    const footprint = [_]Point2{
        .{ 1, 0.5 },
        .{ 2, 0.5 },
        .{ 2, 1.5 },
        .{ 1, 1.5 },
    };
    var prism = try Solid.fromConvexPrism(std.testing.allocator, &footprint, 0.5, 1.5);
    defer prism.deinit(std.testing.allocator);
    var combined = try box.unionWith(std.testing.allocator, prism);
    defer combined.deinit(std.testing.allocator);
    var mesh = try combined.toMesh(std.testing.allocator);
    defer mesh.deinit(std.testing.allocator);
    try std.testing.expect(!meshHasPlaneQuadCoveringPoint(mesh, 0, 1, 1, 1));
}

test "solid mixed box prism union mesh clips stacked horizontal cap faces" {
    var box = try Solid.fromBox(std.testing.allocator, .{ .min = .{ 0, 0, 0 }, .max = .{ 2, 1, 2 } });
    defer box.deinit(std.testing.allocator);
    const footprint = [_]Point2{
        .{ 0.5, 0.5 },
        .{ 1.5, 0.5 },
        .{ 1.5, 1.5 },
        .{ 0.5, 1.5 },
    };
    var prism = try Solid.fromConvexPrism(std.testing.allocator, &footprint, 1, 2);
    defer prism.deinit(std.testing.allocator);
    var combined = try box.unionWith(std.testing.allocator, prism);
    defer combined.deinit(std.testing.allocator);
    var mesh = try combined.toMesh(std.testing.allocator);
    defer mesh.deinit(std.testing.allocator);
    try std.testing.expect(!meshHasPlaneQuadCoveringPoint(mesh, 1, 1, 1, 1));
}

test "solid prism union mesh suppresses exact shared vertical side faces" {
    const left_footprint = [_]Point2{
        .{ 0, 0 },
        .{ 1, 0 },
        .{ 1, 1 },
        .{ 0, 1 },
    };
    const right_footprint = [_]Point2{
        .{ 1, 0 },
        .{ 2, 0 },
        .{ 2, 1 },
        .{ 1, 1 },
    };
    var left = try Solid.fromConvexPrism(std.testing.allocator, &left_footprint, 0, 1);
    defer left.deinit(std.testing.allocator);
    var right = try Solid.fromConvexPrism(std.testing.allocator, &right_footprint, 0, 1);
    defer right.deinit(std.testing.allocator);
    var left_mesh = try left.toMesh(std.testing.allocator);
    defer left_mesh.deinit(std.testing.allocator);
    var right_mesh = try right.toMesh(std.testing.allocator);
    defer right_mesh.deinit(std.testing.allocator);
    var combined = try left.unionWith(std.testing.allocator, right);
    defer combined.deinit(std.testing.allocator);
    var combined_mesh = try combined.toMesh(std.testing.allocator);
    defer combined_mesh.deinit(std.testing.allocator);
    try std.testing.expect(combined_mesh.vertices.len < left_mesh.vertices.len + right_mesh.vertices.len);
    try std.testing.expect(combined_mesh.indices.len < left_mesh.indices.len + right_mesh.indices.len);
}

test "solid prism union mesh clips partial shared vertical side faces" {
    const tall_footprint = [_]Point2{
        .{ 0, 0 },
        .{ 1, 0 },
        .{ 1, 2 },
        .{ 0, 2 },
    };
    const small_footprint = [_]Point2{
        .{ 1, 0.5 },
        .{ 2, 0.5 },
        .{ 2, 1.5 },
        .{ 1, 1.5 },
    };
    var tall = try Solid.fromConvexPrism(std.testing.allocator, &tall_footprint, 0, 2);
    defer tall.deinit(std.testing.allocator);
    var small = try Solid.fromConvexPrism(std.testing.allocator, &small_footprint, 0.5, 1.5);
    defer small.deinit(std.testing.allocator);
    var combined = try tall.unionWith(std.testing.allocator, small);
    defer combined.deinit(std.testing.allocator);
    var mesh = try combined.toMesh(std.testing.allocator);
    defer mesh.deinit(std.testing.allocator);
    try std.testing.expect(!meshHasPlaneQuadCoveringPoint(mesh, 0, 1, 1, 1));
}

test "solid prism union mesh clips stacked horizontal cap faces" {
    const base_footprint = [_]Point2{
        .{ 0, 0 },
        .{ 2, 0 },
        .{ 2, 2 },
        .{ 0, 2 },
    };
    const top_footprint = [_]Point2{
        .{ 0.5, 0.5 },
        .{ 1.5, 0.5 },
        .{ 1.5, 1.5 },
        .{ 0.5, 1.5 },
    };
    var base = try Solid.fromConvexPrism(std.testing.allocator, &base_footprint, 0, 1);
    defer base.deinit(std.testing.allocator);
    var top = try Solid.fromConvexPrism(std.testing.allocator, &top_footprint, 1, 2);
    defer top.deinit(std.testing.allocator);
    var combined = try base.unionWith(std.testing.allocator, top);
    defer combined.deinit(std.testing.allocator);
    var mesh = try combined.toMesh(std.testing.allocator);
    defer mesh.deinit(std.testing.allocator);
    try std.testing.expect(!meshHasPlaneQuadCoveringPoint(mesh, 1, 1, 1, 1));
}

test "solid prism union mesh clips non rectangular stacked horizontal cap faces" {
    const base_footprint = [_]Point2{
        .{ 0, 0 },
        .{ 2, 0 },
        .{ 0, 2 },
    };
    const top_footprint = [_]Point2{
        .{ 0.25, 0.25 },
        .{ 1.0, 0.25 },
        .{ 0.25, 1.0 },
    };
    var base = try Solid.fromConvexPrism(std.testing.allocator, &base_footprint, 0, 1);
    defer base.deinit(std.testing.allocator);
    var top = try Solid.fromConvexPrism(std.testing.allocator, &top_footprint, 1, 2);
    defer top.deinit(std.testing.allocator);
    var combined = try base.unionWith(std.testing.allocator, top);
    defer combined.deinit(std.testing.allocator);
    var mesh = try combined.toMesh(std.testing.allocator);
    defer mesh.deinit(std.testing.allocator);
    try std.testing.expect(!meshHasPlaneTriangleCoveringPoint(mesh, 1, 1, 0.5, 0.5));
}

fn meshHasPlaneQuadCoveringPoint(mesh: Mesh, plane_axis: usize, plane_value: f32, u_value: f32, v_value: f32) bool {
    var idx: usize = 0;
    while (idx + 3 < mesh.vertices.len) : (idx += 4) {
        const v0 = mesh.vertices[idx].position;
        const v1 = mesh.vertices[idx + 1].position;
        const v2 = mesh.vertices[idx + 2].position;
        const v3 = mesh.vertices[idx + 3].position;
        if (!near(v0[plane_axis], plane_value) or !near(v1[plane_axis], plane_value) or
            !near(v2[plane_axis], plane_value) or !near(v3[plane_axis], plane_value))
        {
            continue;
        }
        var axes: [2]usize = undefined;
        var out: usize = 0;
        for (0..3) |axis| {
            if (axis == plane_axis) continue;
            axes[out] = axis;
            out += 1;
        }
        const min_u = @min(@min(v0[axes[0]], v1[axes[0]]), @min(v2[axes[0]], v3[axes[0]]));
        const max_u = @max(@max(v0[axes[0]], v1[axes[0]]), @max(v2[axes[0]], v3[axes[0]]));
        const min_v = @min(@min(v0[axes[1]], v1[axes[1]]), @min(v2[axes[1]], v3[axes[1]]));
        const max_v = @max(@max(v0[axes[1]], v1[axes[1]]), @max(v2[axes[1]], v3[axes[1]]));
        if (u_value > min_u + 0.0001 and u_value < max_u - 0.0001 and
            v_value > min_v + 0.0001 and v_value < max_v - 0.0001)
        {
            return true;
        }
    }
    return false;
}

fn meshHasPlaneTriangleCoveringPoint(mesh: Mesh, plane_axis: usize, plane_value: f32, u_value: f32, v_value: f32) bool {
    var idx: usize = 0;
    while (idx + 2 < mesh.indices.len) : (idx += 3) {
        const a = mesh.vertices[mesh.indices[idx]].position;
        const b = mesh.vertices[mesh.indices[idx + 1]].position;
        const c = mesh.vertices[mesh.indices[idx + 2]].position;
        if (!near(a[plane_axis], plane_value) or !near(b[plane_axis], plane_value) or !near(c[plane_axis], plane_value)) continue;
        var axes: [2]usize = undefined;
        var out: usize = 0;
        for (0..3) |axis| {
            if (axis == plane_axis) continue;
            axes[out] = axis;
            out += 1;
        }
        const p = Point2{ u_value, v_value };
        const pa = Point2{ a[axes[0]], a[axes[1]] };
        const pb = Point2{ b[axes[0]], b[axes[1]] };
        const pc = Point2{ c[axes[0]], c[axes[1]] };
        if (pointInTriangle(p, pa, pb, pc)) return true;
    }
    return false;
}

fn pointInTriangle(p: Point2, a: Point2, b: Point2, c: Point2) bool {
    const c0 = cross2(a, b, p);
    const c1 = cross2(b, c, p);
    const c2 = cross2(c, a, p);
    return (c0 >= -0.0001 and c1 >= -0.0001 and c2 >= -0.0001) or
        (c0 <= 0.0001 and c1 <= 0.0001 and c2 <= 0.0001);
}

test "solid prism subtraction with box cutter emits prism fragments" {
    const footprint = [_]Point2{
        .{ 0, 0 },
        .{ 2, 0 },
        .{ 0, 2 },
    };
    var prism = try Solid.fromConvexPrism(std.testing.allocator, &footprint, 0, 2);
    defer prism.deinit(std.testing.allocator);
    var result = try prism.subtractBox(std.testing.allocator, .{ .min = .{ 0.5, 0.5, 0.5 }, .max = .{ 1.0, 1.5, 1.0 } });
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.boxes.len);
    try std.testing.expect(result.prisms.len > 0);
    var mesh = try result.toMesh(std.testing.allocator);
    defer mesh.deinit(std.testing.allocator);
    try std.testing.expect(mesh.vertices.len > 0);
    try std.testing.expect(mesh.indices.len > 0);
}

test "solid prism subtraction keeps untouched prism when cutter misses" {
    const footprint = [_]Point2{
        .{ 0, 0 },
        .{ 1, 0 },
        .{ 0, 1 },
    };
    var prism = try Solid.fromConvexPrism(std.testing.allocator, &footprint, 0, 1);
    defer prism.deinit(std.testing.allocator);
    var result = try prism.subtractBox(std.testing.allocator, .{ .min = .{ 2, 0, 2 }, .max = .{ 3, 1, 3 } });
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), result.prisms.len);
}

test "solid box subtract convex prism emits valid prism fragments" {
    var box = try Solid.fromBox(std.testing.allocator, .{ .min = .{ 0, 0, 0 }, .max = .{ 2, 2, 2 } });
    defer box.deinit(std.testing.allocator);
    const cutter = [_]Point2{
        .{ 0.5, 0.5 },
        .{ 1.5, 0.5 },
        .{ 1.0, 1.5 },
    };
    var result = try box.subtractConvexPrism(std.testing.allocator, &cutter, 0, 2);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.boxes.len);
    try std.testing.expect(result.prisms.len > 0);
    for (result.prisms) |prism| {
        try validateConvexPrism(prism.footprint, prism.min_y, prism.max_y);
    }
    var mesh = try result.toMesh(std.testing.allocator);
    defer mesh.deinit(std.testing.allocator);
    try std.testing.expect(mesh.vertices.len > 0);
    try std.testing.expect(mesh.indices.len > 0);
}

test "solid prism subtract convex prism preserves top and bottom bands" {
    const source = [_]Point2{
        .{ 0, 0 },
        .{ 2, 0 },
        .{ 2, 2 },
        .{ 0, 2 },
    };
    var prism = try Solid.fromConvexPrism(std.testing.allocator, &source, 0, 3);
    defer prism.deinit(std.testing.allocator);
    const cutter = [_]Point2{
        .{ 0.5, 0.5 },
        .{ 1.5, 0.5 },
        .{ 1.5, 1.5 },
        .{ 0.5, 1.5 },
    };
    var result = try prism.subtractConvexPrism(std.testing.allocator, &cutter, 1, 2);
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result.prisms.len >= 3);
    var has_bottom = false;
    var has_top = false;
    for (result.prisms) |fragment| {
        if (@abs(fragment.min_y - 0) <= 0.0001 and @abs(fragment.max_y - 1) <= 0.0001) has_bottom = true;
        if (@abs(fragment.min_y - 2) <= 0.0001 and @abs(fragment.max_y - 3) <= 0.0001) has_top = true;
    }
    try std.testing.expect(has_bottom);
    try std.testing.expect(has_top);
}
