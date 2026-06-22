const std = @import("std");
const shared = @import("runtime_shared");
const shape_source = @import("shape_source.zig");

const editor_math = shared.editor_math;
const geometry = shared.geometry;

pub const Kind = enum {
    extrude,
    solidify,
    revolve,
    cut,
    inset,
    bevel,
    mirror,
    array,
};

pub const Operation = struct {
    kind: Kind,
    amount: f32 = 1.0,
    segments: u32 = 24,

    pub fn validateForSource(self: Operation, source: shape_source.Source) !void {
        try source.validate();
        if (!std.math.isFinite(self.amount)) return error.InvalidShapeOperationAmount;
        if (source.kind == .primitive_seed) return;
        if (source.kind == .path) {
            if (self.kind != .extrude) return error.PathNeedsExtrudeOperation;
            if (self.amount <= 0) return error.InvalidShapeOperationAmount;
            return;
        }
        switch (self.kind) {
            .extrude, .solidify, .cut, .inset, .bevel => {
                if (self.amount <= 0) return error.InvalidShapeOperationAmount;
                if ((self.kind == .inset or self.kind == .bevel) and self.amount >= 0.5) return error.InvalidShapeOperationAmount;
                if (source.kind != .closed_face) return error.OperationNeedsClosedFace;
            },
            .revolve => {
                if (source.kind != .open_profile) return error.RevolveNeedsProfile;
                if (self.segments < 3) return error.InvalidRevolveSegments;
            },
            .mirror, .array => {},
        }
    }

    pub fn evaluateMesh(self: Operation, allocator: std.mem.Allocator, source: shape_source.Source) !geometry.Mesh {
        try self.validateForSource(source);
        if (source.kind == .primitive_seed) {
            return geometry.buildPrimitive(allocator, source.primitive_kind, source.primitive_params);
        }
        return switch (self.kind) {
            .extrude => if (source.kind == .path) buildPathRailMesh(allocator, source.points, self.amount) else buildPrismMesh(allocator, source.points, self.amount),
            .solidify => buildPrismMesh(allocator, source.points, self.amount),
            .cut => buildCutMesh(allocator, source.points, self.amount),
            .inset => buildInsetMesh(allocator, source.points, self.amount),
            .bevel => buildBevelMesh(allocator, source.points, self.amount),
            .revolve => buildRevolveMesh(allocator, source.points, self.segments),
            .mirror, .array => error.ShapeOperationHasNoStandaloneMesh,
        };
    }

    pub fn evaluateExistingMesh(self: Operation, allocator: std.mem.Allocator, mesh: *const geometry.Mesh) !geometry.Mesh {
        return switch (self.kind) {
            .mirror => mirrorMeshX(allocator, mesh),
            .array => {
                if (!std.math.isFinite(self.amount) or self.amount <= 0) return error.InvalidShapeOperationAmount;
                if (self.segments < 2) return error.InvalidArraySegments;
                return arrayMeshX(allocator, mesh, self.amount, @intCast(self.segments));
            },
            else => error.ShapeOperationNeedsSource,
        };
    }
};

pub fn validationErrorLabel(err: anyerror) []const u8 {
    return switch (err) {
        error.NotEnoughShapePoints => "Need more points",
        error.DuplicateShapePoint => "Duplicate point",
        error.InvalidShapePoint => "Bad point",
        error.InvalidPrimitiveSeed => "Bad primitive seed",
        error.OperationNeedsClosedFace => "Needs face source",
        error.RevolveNeedsProfile => "Needs profile",
        error.PathNeedsExtrudeOperation => "Path uses Extrude",
        error.InvalidShapeOperationAmount => "Bad amount",
        error.InvalidRevolveSegments => "Bad segments",
        error.InvalidArraySegments => "Bad array count",
        error.ShapeOperationNeedsSource => "Needs source",
        error.ShapeOperationHasNoStandaloneMesh => "Needs existing mesh",
        else => @errorName(err),
    };
}

pub fn mirrorMeshX(allocator: std.mem.Allocator, mesh: *const geometry.Mesh) !geometry.Mesh {
    const old_v_len = mesh.vertices.len;
    const old_i_len = mesh.indices.len;
    const new_vertices = try allocator.alloc(geometry.Vertex, old_v_len * 2);
    errdefer allocator.free(new_vertices);
    @memcpy(new_vertices[0..old_v_len], mesh.vertices);
    for (mesh.vertices, 0..) |vert, i| {
        var mirrored = vert;
        mirrored.position.x = -mirrored.position.x;
        mirrored.normal.x = -mirrored.normal.x;
        new_vertices[old_v_len + i] = mirrored;
    }

    const new_indices = try allocator.alloc(u32, old_i_len * 2);
    errdefer allocator.free(new_indices);
    @memcpy(new_indices[0..old_i_len], mesh.indices);
    var tri: usize = 0;
    var out: usize = old_i_len;
    while (tri + 2 < old_i_len) : (tri += 3) {
        new_indices[out] = mesh.indices[tri] + @as(u32, @intCast(old_v_len));
        new_indices[out + 1] = mesh.indices[tri + 2] + @as(u32, @intCast(old_v_len));
        new_indices[out + 2] = mesh.indices[tri + 1] + @as(u32, @intCast(old_v_len));
        out += 3;
    }
    return .{ .vertices = new_vertices, .indices = new_indices };
}

pub fn arrayMeshX(allocator: std.mem.Allocator, mesh: *const geometry.Mesh, stride: f32, count: usize) !geometry.Mesh {
    if (!std.math.isFinite(stride) or stride <= 0) return error.InvalidShapeOperationAmount;
    if (count < 2) return error.InvalidArraySegments;

    const old_v_len = mesh.vertices.len;
    const old_i_len = mesh.indices.len;
    const new_vertices = try allocator.alloc(geometry.Vertex, old_v_len * count);
    errdefer allocator.free(new_vertices);
    const new_indices = try allocator.alloc(u32, old_i_len * count);
    errdefer allocator.free(new_indices);

    for (0..count) |copy_index| {
        const offset = editor_math.Vec3{ .x = stride * @as(f32, @floatFromInt(copy_index)), .y = 0, .z = 0 };
        const vertex_base = copy_index * old_v_len;
        for (mesh.vertices, 0..) |vert, i| {
            var shifted = vert;
            shifted.position = editor_math.Vec3.add(shifted.position, offset);
            new_vertices[vertex_base + i] = shifted;
        }
        const index_base = copy_index * old_i_len;
        for (mesh.indices, 0..) |index, i| {
            new_indices[index_base + i] = index + @as(u32, @intCast(vertex_base));
        }
    }

    return .{ .vertices = new_vertices, .indices = new_indices };
}

fn buildPrismMesh(allocator: std.mem.Allocator, points: []const editor_math.Vec3, height: f32) !geometry.Mesh {
    var vertices: std.ArrayList(geometry.Vertex) = .empty;
    defer vertices.deinit(allocator);
    var indices: std.ArrayList(u32) = .empty;
    defer indices.deinit(allocator);

    const top_normal = sourceNormal(points);
    const bottom_normal = editor_math.Vec3.scale(top_normal, -1);
    const offset = editor_math.Vec3.scale(top_normal, height);

    for (1..points.len - 1) |i| {
        try appendTriangle(allocator, &vertices, &indices, points[0], points[i + 1], points[i], bottom_normal);
        try appendTriangle(
            allocator,
            &vertices,
            &indices,
            editor_math.Vec3.add(points[0], offset),
            editor_math.Vec3.add(points[i], offset),
            editor_math.Vec3.add(points[i + 1], offset),
            top_normal,
        );
    }

    for (0..points.len) |i| {
        const next = (i + 1) % points.len;
        const p0 = points[i];
        const p1 = points[next];
        const p2 = editor_math.Vec3.add(points[next], offset);
        const p3 = editor_math.Vec3.add(points[i], offset);
        const normal = faceNormal(p0, p1, p2);
        try appendQuad(allocator, &vertices, &indices, p0, p1, p2, p3, normal);
    }

    return .{
        .vertices = try vertices.toOwnedSlice(allocator),
        .indices = try indices.toOwnedSlice(allocator),
    };
}

fn buildCutMesh(allocator: std.mem.Allocator, points: []const editor_math.Vec3, depth: f32) !geometry.Mesh {
    var mesh = try buildPrismMesh(allocator, points, -depth);
    invertMeshWindingAndNormals(&mesh);
    return mesh;
}

fn buildPathRailMesh(allocator: std.mem.Allocator, points: []const editor_math.Vec3, thickness: f32) !geometry.Mesh {
    if (points.len < 2) return error.NotEnoughShapePoints;
    if (!std.math.isFinite(thickness) or thickness <= 0) return error.InvalidShapeOperationAmount;

    var vertices: std.ArrayList(geometry.Vertex) = .empty;
    defer vertices.deinit(allocator);
    var indices: std.ArrayList(u32) = .empty;
    defer indices.deinit(allocator);

    const half = thickness * 0.5;
    for (0..points.len - 1) |i| {
        const p0 = points[i];
        const p1 = points[i + 1];
        const tangent = normalizeOrFallback(editor_math.Vec3.sub(p1, p0), .{ .x = 1, .y = 0, .z = 0 });
        const up_hint = if (@abs(editor_math.Vec3.dot(tangent, .{ .x = 0, .y = 1, .z = 0 })) > 0.92)
            editor_math.Vec3{ .x = 1, .y = 0, .z = 0 }
        else
            editor_math.Vec3{ .x = 0, .y = 1, .z = 0 };
        const side = editor_math.Vec3.scale(normalizeOrFallback(editor_math.cross(up_hint, tangent), .{ .x = 0, .y = 0, .z = 1 }), half);
        const up = editor_math.Vec3.scale(normalizeOrFallback(editor_math.cross(tangent, side), .{ .x = 0, .y = 1, .z = 0 }), half);

        const a0 = editor_math.Vec3.sub(editor_math.Vec3.sub(p0, side), up);
        const b0 = editor_math.Vec3.sub(editor_math.Vec3.add(p0, side), up);
        const c0 = editor_math.Vec3.add(editor_math.Vec3.add(p0, side), up);
        const d0 = editor_math.Vec3.add(editor_math.Vec3.sub(p0, side), up);
        const a1 = editor_math.Vec3.sub(editor_math.Vec3.sub(p1, side), up);
        const b1 = editor_math.Vec3.sub(editor_math.Vec3.add(p1, side), up);
        const c1 = editor_math.Vec3.add(editor_math.Vec3.add(p1, side), up);
        const d1 = editor_math.Vec3.add(editor_math.Vec3.sub(p1, side), up);

        try appendQuad(allocator, &vertices, &indices, a0, b0, b1, a1, faceNormal(a0, b0, b1));
        try appendQuad(allocator, &vertices, &indices, b0, c0, c1, b1, faceNormal(b0, c0, c1));
        try appendQuad(allocator, &vertices, &indices, c0, d0, d1, c1, faceNormal(c0, d0, d1));
        try appendQuad(allocator, &vertices, &indices, d0, a0, a1, d1, faceNormal(d0, a0, a1));
        try appendQuad(allocator, &vertices, &indices, d0, c0, b0, a0, faceNormal(d0, c0, b0));
        try appendQuad(allocator, &vertices, &indices, a1, b1, c1, d1, faceNormal(a1, b1, c1));
    }

    return .{
        .vertices = try vertices.toOwnedSlice(allocator),
        .indices = try indices.toOwnedSlice(allocator),
    };
}

fn invertMeshWindingAndNormals(mesh: *geometry.Mesh) void {
    for (mesh.vertices) |*vert| {
        vert.normal = editor_math.Vec3.scale(vert.normal, -1);
    }
    var tri: usize = 0;
    while (tri + 2 < mesh.indices.len) : (tri += 3) {
        std.mem.swap(u32, &mesh.indices[tri + 1], &mesh.indices[tri + 2]);
    }
}

fn buildInsetMesh(allocator: std.mem.Allocator, points: []const editor_math.Vec3, amount: f32) !geometry.Mesh {
    const inner = try insetPoints(allocator, points, amount);
    defer allocator.free(inner);

    var vertices: std.ArrayList(geometry.Vertex) = .empty;
    defer vertices.deinit(allocator);
    var indices: std.ArrayList(u32) = .empty;
    defer indices.deinit(allocator);

    const normal = sourceNormal(points);
    for (1..inner.len - 1) |i| {
        try appendTriangle(allocator, &vertices, &indices, inner[0], inner[i], inner[i + 1], normal);
    }
    for (0..points.len) |i| {
        const next = (i + 1) % points.len;
        try appendQuad(allocator, &vertices, &indices, points[i], points[next], inner[next], inner[i], normal);
    }
    return .{
        .vertices = try vertices.toOwnedSlice(allocator),
        .indices = try indices.toOwnedSlice(allocator),
    };
}

fn buildBevelMesh(allocator: std.mem.Allocator, points: []const editor_math.Vec3, amount: f32) !geometry.Mesh {
    const inner = try insetPoints(allocator, points, amount);
    defer allocator.free(inner);

    var vertices: std.ArrayList(geometry.Vertex) = .empty;
    defer vertices.deinit(allocator);
    var indices: std.ArrayList(u32) = .empty;
    defer indices.deinit(allocator);

    const top_normal = sourceNormal(points);
    const bottom_normal = editor_math.Vec3.scale(top_normal, -1);
    const offset = editor_math.Vec3.scale(top_normal, amount);

    for (1..points.len - 1) |i| {
        try appendTriangle(allocator, &vertices, &indices, points[0], points[i + 1], points[i], bottom_normal);
    }
    for (1..inner.len - 1) |i| {
        try appendTriangle(
            allocator,
            &vertices,
            &indices,
            editor_math.Vec3.add(inner[0], offset),
            editor_math.Vec3.add(inner[i], offset),
            editor_math.Vec3.add(inner[i + 1], offset),
            top_normal,
        );
    }
    for (0..points.len) |i| {
        const next = (i + 1) % points.len;
        const p0 = points[i];
        const p1 = points[next];
        const p2 = editor_math.Vec3.add(inner[next], offset);
        const p3 = editor_math.Vec3.add(inner[i], offset);
        try appendQuad(allocator, &vertices, &indices, p0, p1, p2, p3, faceNormal(p0, p1, p2));
    }

    return .{
        .vertices = try vertices.toOwnedSlice(allocator),
        .indices = try indices.toOwnedSlice(allocator),
    };
}

fn insetPoints(allocator: std.mem.Allocator, points: []const editor_math.Vec3, amount: f32) ![]editor_math.Vec3 {
    if (points.len < 3) return error.NotEnoughShapePoints;
    if (!std.math.isFinite(amount) or amount <= 0 or amount >= 0.5) return error.InvalidShapeOperationAmount;
    const center = centroid(points);
    const scale = 1.0 - amount;
    const inner = try allocator.alloc(editor_math.Vec3, points.len);
    for (points, 0..) |point, idx| {
        inner[idx] = editor_math.Vec3.add(center, editor_math.Vec3.scale(editor_math.Vec3.sub(point, center), scale));
    }
    return inner;
}

fn centroid(points: []const editor_math.Vec3) editor_math.Vec3 {
    var center = editor_math.Vec3{ .x = 0, .y = 0, .z = 0 };
    for (points) |point| center = editor_math.Vec3.add(center, point);
    return editor_math.Vec3.scale(center, 1.0 / @as(f32, @floatFromInt(points.len)));
}

fn buildRevolveMesh(allocator: std.mem.Allocator, points: []const editor_math.Vec3, segment_count: u32) !geometry.Mesh {
    const segments: usize = @intCast(@max(segment_count, 3));
    var vertices = try allocator.alloc(geometry.Vertex, points.len * segments);
    errdefer allocator.free(vertices);
    var indices = try allocator.alloc(u32, (points.len - 1) * segments * 6);
    errdefer allocator.free(indices);

    for (points, 0..) |point, ring| {
        const radius = @abs(point.x);
        for (0..segments) |segment| {
            const u = @as(f32, @floatFromInt(segment)) / @as(f32, @floatFromInt(segments));
            const angle = u * std.math.tau;
            const c = @cos(angle);
            const s = @sin(angle);
            vertices[ring * segments + segment] = .{
                .position = .{ .x = radius * c, .y = point.y, .z = radius * s },
                .normal = .{ .x = c, .y = 0, .z = s },
                .uv = .{ .x = u, .y = point.y },
            };
        }
    }

    var out: usize = 0;
    for (0..points.len - 1) |ring| {
        for (0..segments) |segment| {
            const next = (segment + 1) % segments;
            const a: u32 = @intCast(ring * segments + segment);
            const b: u32 = @intCast(ring * segments + next);
            const c: u32 = @intCast((ring + 1) * segments + segment);
            const d: u32 = @intCast((ring + 1) * segments + next);
            indices[out] = a;
            indices[out + 1] = b;
            indices[out + 2] = c;
            indices[out + 3] = b;
            indices[out + 4] = d;
            indices[out + 5] = c;
            out += 6;
        }
    }

    return .{ .vertices = vertices, .indices = indices };
}

fn appendTriangle(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(geometry.Vertex),
    indices: *std.ArrayList(u32),
    a: editor_math.Vec3,
    b: editor_math.Vec3,
    c: editor_math.Vec3,
    normal: editor_math.Vec3,
) !void {
    const base: u32 = @intCast(vertices.items.len);
    try vertices.append(allocator, vertex(a, normal));
    try vertices.append(allocator, vertex(b, normal));
    try vertices.append(allocator, vertex(c, normal));
    try indices.appendSlice(allocator, &.{ base, base + 1, base + 2 });
}

fn appendQuad(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(geometry.Vertex),
    indices: *std.ArrayList(u32),
    p0: editor_math.Vec3,
    p1: editor_math.Vec3,
    p2: editor_math.Vec3,
    p3: editor_math.Vec3,
    normal: editor_math.Vec3,
) !void {
    const base: u32 = @intCast(vertices.items.len);
    try vertices.append(allocator, vertex(p0, normal));
    try vertices.append(allocator, vertex(p1, normal));
    try vertices.append(allocator, vertex(p2, normal));
    try vertices.append(allocator, vertex(p3, normal));
    try indices.appendSlice(allocator, &.{ base, base + 1, base + 2, base, base + 2, base + 3 });
}

fn vertex(position: editor_math.Vec3, normal: editor_math.Vec3) geometry.Vertex {
    return .{ .position = position, .normal = normal, .uv = .{ .x = position.x, .y = position.z } };
}

fn faceNormal(a: editor_math.Vec3, b: editor_math.Vec3, c: editor_math.Vec3) editor_math.Vec3 {
    const normal = editor_math.cross(editor_math.Vec3.sub(b, a), editor_math.Vec3.sub(c, a));
    const len = @sqrt(normal.x * normal.x + normal.y * normal.y + normal.z * normal.z);
    if (len <= std.math.floatEps(f32)) return .{ .x = 0, .y = 1, .z = 0 };
    return .{ .x = normal.x / len, .y = normal.y / len, .z = normal.z / len };
}

fn sourceNormal(points: []const editor_math.Vec3) editor_math.Vec3 {
    if (points.len < 3) return .{ .x = 0, .y = 1, .z = 0 };
    var normal = faceNormal(points[0], points[1], points[2]);
    if (@abs(normal.y) > @abs(normal.x) and @abs(normal.y) > @abs(normal.z) and normal.y < 0) {
        normal = editor_math.Vec3.scale(normal, -1);
    }
    return normal;
}

fn normalizeOrFallback(value: editor_math.Vec3, fallback: editor_math.Vec3) editor_math.Vec3 {
    const len_sq = value.x * value.x + value.y * value.y + value.z * value.z;
    if (len_sq <= std.math.floatEps(f32)) return fallback;
    return editor_math.Vec3.scale(value, 1.0 / @sqrt(len_sq));
}

test "revolve requires an open profile" {
    const pts = [_]editor_math.Vec3{
        .{ .x = 0, .y = 0, .z = 0 },
        .{ .x = 1, .y = 0, .z = 0 },
        .{ .x = 1, .y = 0, .z = 1 },
    };
    const source = shape_source.Source{ .kind = .closed_face, .points = &pts };
    try std.testing.expectError(error.RevolveNeedsProfile, (Operation{ .kind = .revolve }).validateForSource(source));
}

test "shape validation errors have concise editor labels" {
    try std.testing.expectEqualStrings("Need more points", validationErrorLabel(error.NotEnoughShapePoints));
    try std.testing.expectEqualStrings("Needs profile", validationErrorLabel(error.RevolveNeedsProfile));
    try std.testing.expectEqualStrings("Bad amount", validationErrorLabel(error.InvalidShapeOperationAmount));
}

test "path source extrudes into an editable rail mesh" {
    const pts = [_]editor_math.Vec3{
        .{ .x = 0, .y = 0, .z = 0 },
        .{ .x = 1, .y = 0, .z = 1 },
    };
    const source = shape_source.Source{ .kind = .path, .points = &pts };
    var mesh = try (Operation{ .kind = .extrude, .amount = 0.25 }).evaluateMesh(std.testing.allocator, source);
    defer mesh.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 24), mesh.vertices.len);
    try std.testing.expectEqual(@as(usize, 36), mesh.indices.len);
    try std.testing.expectError(error.PathNeedsExtrudeOperation, (Operation{ .kind = .solidify }).validateForSource(source));
}

test "extrude closed face produces a prism mesh" {
    const pts = [_]editor_math.Vec3{
        .{ .x = -1, .y = 0, .z = -1 },
        .{ .x = 1, .y = 0, .z = -1 },
        .{ .x = 1, .y = 0, .z = 1 },
        .{ .x = -1, .y = 0, .z = 1 },
    };
    const source = shape_source.Source{ .kind = .closed_face, .points = &pts };
    var mesh = try (Operation{ .kind = .extrude, .amount = 2 }).evaluateMesh(std.testing.allocator, source);
    defer mesh.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 36), mesh.indices.len);
    try std.testing.expectApproxEqAbs(@as(f32, 2), mesh.vertices[4].position.y, 0.0001);
}

test "solidify and cut produce editable volume meshes" {
    const pts = [_]editor_math.Vec3{
        .{ .x = 0, .y = 0, .z = 0 },
        .{ .x = 2, .y = 0, .z = 0 },
        .{ .x = 2, .y = 0, .z = 2 },
        .{ .x = 0, .y = 0, .z = 2 },
    };
    const source = shape_source.Source{ .kind = .closed_face, .points = &pts };
    var solid = try (Operation{ .kind = .solidify, .amount = 0.5 }).evaluateMesh(std.testing.allocator, source);
    defer solid.deinit(std.testing.allocator);
    var cut = try (Operation{ .kind = .cut, .amount = 1.5 }).evaluateMesh(std.testing.allocator, source);
    defer cut.deinit(std.testing.allocator);
    try std.testing.expectEqual(solid.indices.len, cut.indices.len);
    try std.testing.expectApproxEqAbs(@as(f32, -1.5), cut.vertices[4].position.y, 0.0001);
    try std.testing.expect(cut.vertices[0].normal.y > 0);
    try std.testing.expect(cut.vertices[3].normal.y < 0);
    try std.testing.expectEqual(@as(u32, 2), cut.indices[1]);
    try std.testing.expectEqual(@as(u32, 1), cut.indices[2]);
}

test "inset closed face produces an inner face and border ring" {
    const pts = [_]editor_math.Vec3{
        .{ .x = -1, .y = 0, .z = -1 },
        .{ .x = 1, .y = 0, .z = -1 },
        .{ .x = 1, .y = 0, .z = 1 },
        .{ .x = -1, .y = 0, .z = 1 },
    };
    const source = shape_source.Source{ .kind = .closed_face, .points = &pts };
    var mesh = try (Operation{ .kind = .inset, .amount = 0.25 }).evaluateMesh(std.testing.allocator, source);
    defer mesh.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 30), mesh.indices.len);
    try std.testing.expectApproxEqAbs(@as(f32, -0.75), mesh.vertices[0].position.x, 0.0001);
    try std.testing.expectError(error.InvalidShapeOperationAmount, (Operation{ .kind = .inset, .amount = 0.75 }).evaluateMesh(std.testing.allocator, source));
}

test "bevel closed face produces shallow beveled volume" {
    const pts = [_]editor_math.Vec3{
        .{ .x = -1, .y = 0, .z = -1 },
        .{ .x = 1, .y = 0, .z = -1 },
        .{ .x = 1, .y = 0, .z = 1 },
        .{ .x = -1, .y = 0, .z = 1 },
    };
    const source = shape_source.Source{ .kind = .closed_face, .points = &pts };
    var mesh = try (Operation{ .kind = .bevel, .amount = 0.2 }).evaluateMesh(std.testing.allocator, source);
    defer mesh.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 36), mesh.indices.len);
    var max_y: f32 = -1000;
    for (mesh.vertices) |vert| max_y = @max(max_y, vert.position.y);
    try std.testing.expectApproxEqAbs(@as(f32, 0.2), max_y, 0.0001);
}

test "revolve profile produces a segmented lathe mesh" {
    const pts = [_]editor_math.Vec3{
        .{ .x = 1, .y = 0, .z = 0 },
        .{ .x = 0.5, .y = 1, .z = 0 },
        .{ .x = 1, .y = 2, .z = 0 },
    };
    const source = shape_source.Source{ .kind = .open_profile, .points = &pts };
    var mesh = try (Operation{ .kind = .revolve, .segments = 8 }).evaluateMesh(std.testing.allocator, source);
    defer mesh.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 24), mesh.vertices.len);
    try std.testing.expectEqual(@as(usize, 96), mesh.indices.len);
    try std.testing.expectApproxEqAbs(@as(f32, 1), mesh.vertices[0].position.x, 0.0001);
}

test "primitive seed produces a standalone primitive mesh through operation evaluator" {
    const source = shape_source.Source{
        .kind = .primitive_seed,
        .points = &.{},
        .primitive_kind = .box,
        .primitive_params = .{ .width = 2, .height = 3, .depth = 4 },
    };
    var mesh = try (Operation{ .kind = .extrude }).evaluateMesh(std.testing.allocator, source);
    defer mesh.deinit(std.testing.allocator);
    try std.testing.expect(mesh.vertices.len > 0);
    try std.testing.expect(mesh.indices.len > 0);
}

test "primitive seed keeps invalid setup loud and editable" {
    const source = shape_source.Source{
        .kind = .primitive_seed,
        .points = &.{},
        .primitive_kind = .sphere,
        .primitive_params = .{ .radius = 0, .segments = 16 },
    };
    try std.testing.expectError(error.InvalidPrimitiveSeed, (Operation{ .kind = .solidify }).evaluateMesh(std.testing.allocator, source));
}

test "mirror existing mesh duplicates across X and reverses winding" {
    var mesh = try geometry.buildPrimitive(std.testing.allocator, .box, .{ .width = 2, .height = 1, .depth = 1 });
    defer mesh.deinit(std.testing.allocator);

    var mirrored = try (Operation{ .kind = .mirror }).evaluateExistingMesh(std.testing.allocator, &mesh);
    defer mirrored.deinit(std.testing.allocator);

    try std.testing.expectEqual(mesh.vertices.len * 2, mirrored.vertices.len);
    try std.testing.expectEqual(mesh.indices.len * 2, mirrored.indices.len);
    const old_v_len = mesh.vertices.len;
    try std.testing.expectApproxEqAbs(-mesh.vertices[0].position.x, mirrored.vertices[old_v_len].position.x, 0.0001);
    try std.testing.expectApproxEqAbs(-mesh.vertices[0].normal.x, mirrored.vertices[old_v_len].normal.x, 0.0001);
    try std.testing.expectEqual(mesh.indices[0] + @as(u32, @intCast(old_v_len)), mirrored.indices[mesh.indices.len]);
    try std.testing.expectEqual(mesh.indices[2] + @as(u32, @intCast(old_v_len)), mirrored.indices[mesh.indices.len + 1]);
}

test "array existing mesh creates ordered shifted copies" {
    var mesh = try geometry.buildPrimitive(std.testing.allocator, .box, .{ .width = 1, .height = 1, .depth = 1 });
    defer mesh.deinit(std.testing.allocator);

    var arrayed = try (Operation{ .kind = .array, .amount = 1.5, .segments = 3 }).evaluateExistingMesh(std.testing.allocator, &mesh);
    defer arrayed.deinit(std.testing.allocator);

    try std.testing.expectEqual(mesh.vertices.len * 3, arrayed.vertices.len);
    try std.testing.expectEqual(mesh.indices.len * 3, arrayed.indices.len);
    const old_v_len = mesh.vertices.len;
    try std.testing.expectApproxEqAbs(mesh.vertices[0].position.x + 1.5, arrayed.vertices[old_v_len].position.x, 0.0001);
    try std.testing.expectApproxEqAbs(mesh.vertices[0].position.x + 3.0, arrayed.vertices[old_v_len * 2].position.x, 0.0001);
    try std.testing.expectEqual(mesh.indices[0] + @as(u32, @intCast(old_v_len)), arrayed.indices[mesh.indices.len]);
    try std.testing.expectError(error.InvalidArraySegments, (Operation{ .kind = .array, .amount = 1.5, .segments = 1 }).evaluateExistingMesh(std.testing.allocator, &mesh));
}
