const std = @import("std");
const editor_math = @import("editor_math.zig");

pub const Vec2 = editor_math.Vec2;
pub const Vec3 = editor_math.Vec3;

pub const Vertex = struct {
    position: Vec3,
    normal: Vec3,
    uv: Vec2,
};

pub const default_meters_per_repeat: f32 = 1.0;
const uv_area_epsilon: f32 = 0.00001;

pub const SkinInfluence = struct {
    joints: [4]u8,
    weights: [4]f32,
};

pub const Skin = struct {
    bind_vertices: []Vertex,
    influences: []SkinInfluence,
    inverse_bind: []editor_math.Mat4,

    pub fn deinit(self: *Skin, allocator: std.mem.Allocator) void {
        allocator.free(self.bind_vertices);
        allocator.free(self.influences);
        allocator.free(self.inverse_bind);
        self.bind_vertices = &.{};
        self.influences = &.{};
        self.inverse_bind = &.{};
    }

    pub fn duplicate(allocator: std.mem.Allocator, source: *const Skin) !Skin {
        const bind_vertices = try allocator.alloc(Vertex, source.bind_vertices.len);
        @memcpy(bind_vertices, source.bind_vertices);
        const influences = try allocator.alloc(SkinInfluence, source.influences.len);
        @memcpy(influences, source.influences);
        const inverse_bind = try allocator.alloc(editor_math.Mat4, source.inverse_bind.len);
        @memcpy(inverse_bind, source.inverse_bind);
        return .{
            .bind_vertices = bind_vertices,
            .influences = influences,
            .inverse_bind = inverse_bind,
        };
    }
};

pub const Mesh = struct {
    vertices: []Vertex,
    indices: []u32,
    skin: ?Skin = null,

    pub fn isSkinned(self: *const Mesh) bool {
        return self.skin != null;
    }

    pub fn deinit(self: *Mesh, allocator: std.mem.Allocator) void {
        allocator.free(self.vertices);
        allocator.free(self.indices);
        if (self.skin) |*skin| skin.deinit(allocator);
        self.vertices = &.{};
        self.indices = &.{};
        self.skin = null;
    }
};

pub const PrimitiveKind = enum {
    box,
    plane,
    cylinder,
    sphere,
};

pub const PrimitiveParams = struct {
    width: f32 = 1.0,
    height: f32 = 1.0,
    depth: f32 = 1.0,
    radius: f32 = 0.5,
    segments: u32 = 16,
};

pub fn buildPrimitive(allocator: std.mem.Allocator, kind: PrimitiveKind, params: PrimitiveParams) !Mesh {
    return switch (kind) {
        .box => buildBox(allocator, params.width, params.height, params.depth),
        .plane => buildPlane(allocator, params.width, params.depth),
        .cylinder => buildCylinder(allocator, params.radius, params.height, params.segments),
        .sphere => buildSphere(allocator, params.radius, params.segments),
    };
}

pub fn buildCapsuleFeetOrigin(allocator: std.mem.Allocator, radius: f32, half_height: f32, segments: u32) !Mesh {
    var vertices: std.ArrayList(Vertex) = .empty;
    defer vertices.deinit(allocator);
    var indices: std.ArrayList(u32) = .empty;
    defer indices.deinit(allocator);

    const cols = @max(8, segments);
    const hemi_rings = @max(4, segments / 2);
    const tau = std.math.tau;
    const pi = std.math.pi;
    const top_center_y = radius + half_height * 2.0;
    const bottom_center_y = radius;

    var top_start: u32 = 0;
    for (0..hemi_rings + 1) |ring| {
        const v = @as(f32, @floatFromInt(ring)) / @as(f32, @floatFromInt(hemi_rings));
        const phi = v * pi * 0.5;
        const y = top_center_y + radius * @cos(phi);
        const ring_radius = radius * @sin(phi);
        if (ring == 0) top_start = @intCast(vertices.items.len);
        for (0..cols) |col| {
            const u = @as(f32, @floatFromInt(col)) / @as(f32, @floatFromInt(cols));
            const theta = u * tau;
            const nx = @cos(theta) * @sin(phi);
            const ny = @cos(phi);
            const nz = @sin(theta) * @sin(phi);
            try appendVertex(allocator, &vertices, .{
                .x = ring_radius * @cos(theta),
                .y = y,
                .z = ring_radius * @sin(theta),
            }, .{ .x = nx, .y = ny, .z = nz }, .{ .x = u * tau * radius, .y = y });
        }
    }

    const bottom_start: u32 = @intCast(vertices.items.len);
    for (1..hemi_rings + 1) |ring| {
        const v = @as(f32, @floatFromInt(ring)) / @as(f32, @floatFromInt(hemi_rings));
        const phi = pi * 0.5 + v * pi * 0.5;
        const y = bottom_center_y + radius * @cos(phi);
        const ring_radius = radius * @sin(phi);
        for (0..cols) |col| {
            const u = @as(f32, @floatFromInt(col)) / @as(f32, @floatFromInt(cols));
            const theta = u * tau;
            const nx = @cos(theta) * @sin(phi);
            const ny = @cos(phi);
            const nz = @sin(theta) * @sin(phi);
            try appendVertex(allocator, &vertices, .{
                .x = ring_radius * @cos(theta),
                .y = y,
                .z = ring_radius * @sin(theta),
            }, .{ .x = nx, .y = ny, .z = nz }, .{ .x = u * tau * radius, .y = y });
        }
    }

    const total_rings = hemi_rings + 1 + hemi_rings;
    for (0..total_rings - 1) |ring| {
        const current = if (ring <= hemi_rings) top_start + @as(u32, @intCast(ring * cols)) else bottom_start + @as(u32, @intCast((ring - hemi_rings - 1) * cols));
        const next = if (ring + 1 <= hemi_rings) top_start + @as(u32, @intCast((ring + 1) * cols)) else bottom_start + @as(u32, @intCast((ring - hemi_rings) * cols));
        for (0..cols) |col| {
            const a = current + @as(u32, @intCast(col));
            const b = current + @as(u32, @intCast((col + 1) % cols));
            const c = next + @as(u32, @intCast(col));
            const d = next + @as(u32, @intCast((col + 1) % cols));
            try indices.appendSlice(allocator, &.{ a, b, c, b, d, c });
        }
    }

    return .{
        .vertices = try vertices.toOwnedSlice(allocator),
        .indices = try indices.toOwnedSlice(allocator),
    };
}

fn appendVertex(allocator: std.mem.Allocator, vertices: *std.ArrayList(Vertex), position: Vec3, normal: Vec3, uv: Vec2) !void {
    try vertices.append(allocator, .{
        .position = position,
        .normal = normal,
        .uv = uv,
    });
}

pub fn edgeLength(a: Vec3, b: Vec3) f32 {
    const d = Vec3.sub(b, a);
    return @sqrt(d.x * d.x + d.y * d.y + d.z * d.z);
}

pub fn planarQuadUvs(p0: Vec3, p1: Vec3, p2: Vec3, p3: Vec3) [4]Vec2 {
    _ = p2;
    const u_len = edgeLength(p0, p1) / default_meters_per_repeat;
    const v_len = edgeLength(p0, p3) / default_meters_per_repeat;
    return .{
        .{ .x = 0, .y = 0 },
        .{ .x = u_len, .y = 0 },
        .{ .x = u_len, .y = v_len },
        .{ .x = 0, .y = v_len },
    };
}

pub fn planarTriangleUvs(p0: Vec3, p1: Vec3, p2: Vec3) [3]Vec2 {
    const u_axis = Vec3.normalized(Vec3.sub(p1, p0));
    const p2_delta = Vec3.sub(p2, p0);
    const p1_len = edgeLength(p0, p1) / default_meters_per_repeat;
    return .{
        .{ .x = 0, .y = 0 },
        .{ .x = p1_len, .y = 0 },
        .{
            .x = Vec3.dot(p2_delta, u_axis) / default_meters_per_repeat,
            .y = edgeLength(.{ .x = 0, .y = 0, .z = 0 }, Vec3.sub(p2_delta, Vec3.scale(u_axis, Vec3.dot(p2_delta, u_axis)))) / default_meters_per_repeat,
        },
    };
}

pub fn appendWorldQuad(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(Vertex),
    indices: *std.ArrayList(u32),
    p0: Vec3,
    p1: Vec3,
    p2: Vec3,
    p3: Vec3,
    normal: Vec3,
) !void {
    const uvs = planarQuadUvs(p0, p1, p2, p3);
    try appendQuad(allocator, vertices, indices, p0, p1, p2, p3, normal, uvs[0], uvs[1], uvs[2], uvs[3]);
}

pub fn triangleTexelDensity(mesh: *const Mesh, tri_offset: usize, texture_size: f32) ?f32 {
    if (tri_offset + 2 >= mesh.indices.len) return null;
    const a = mesh.vertices[mesh.indices[tri_offset]];
    const b = mesh.vertices[mesh.indices[tri_offset + 1]];
    const c = mesh.vertices[mesh.indices[tri_offset + 2]];
    const world_area = triangleWorldArea(a.position, b.position, c.position);
    const uv_area = @abs(triangleUvArea(a.uv, b.uv, c.uv));
    if (world_area <= uv_area_epsilon or uv_area <= uv_area_epsilon) return null;
    return @sqrt(uv_area / world_area) * texture_size;
}

pub fn validateUniformTexelDensity(mesh: *const Mesh, texture_size: f32, expected: f32, tolerance: f32) !void {
    var checked: usize = 0;
    var tri: usize = 0;
    while (tri + 2 < mesh.indices.len) : (tri += 3) {
        const density = triangleTexelDensity(mesh, tri, texture_size) orelse continue;
        try std.testing.expectApproxEqAbs(expected, density, tolerance);
        checked += 1;
    }
    try std.testing.expect(checked > 0);
}

fn triangleWorldArea(a: Vec3, b: Vec3, c: Vec3) f32 {
    const n = editor_math.cross(Vec3.sub(b, a), Vec3.sub(c, a));
    return @sqrt(n.x * n.x + n.y * n.y + n.z * n.z) * 0.5;
}

fn triangleUvArea(a: Vec2, b: Vec2, c: Vec2) f32 {
    return ((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)) * 0.5;
}

fn appendQuad(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(Vertex),
    indices: *std.ArrayList(u32),
    p0: Vec3,
    p1: Vec3,
    p2: Vec3,
    p3: Vec3,
    normal: Vec3,
    uv0: Vec2,
    uv1: Vec2,
    uv2: Vec2,
    uv3: Vec2,
) !void {
    const base: u32 = @intCast(vertices.items.len);
    try appendVertex(allocator, vertices, p0, normal, uv0);
    try appendVertex(allocator, vertices, p1, normal, uv1);
    try appendVertex(allocator, vertices, p2, normal, uv2);
    try appendVertex(allocator, vertices, p3, normal, uv3);
    try indices.appendSlice(allocator, &.{ base, base + 2, base + 1, base, base + 3, base + 2 });
}

fn buildBox(allocator: std.mem.Allocator, width: f32, height: f32, depth: f32) !Mesh {
    var vertices: std.ArrayList(Vertex) = .empty;
    defer vertices.deinit(allocator);
    var indices: std.ArrayList(u32) = .empty;
    defer indices.deinit(allocator);

    const hx = width * 0.5;
    const hy = height * 0.5;
    const hz = depth * 0.5;

    // +X face
    try appendWorldQuad(
        allocator,
        &vertices,
        &indices,
        .{ .x = hx, .y = -hy, .z = -hz },
        .{ .x = hx, .y = -hy, .z = hz },
        .{ .x = hx, .y = hy, .z = hz },
        .{ .x = hx, .y = hy, .z = -hz },
        .{ .x = 1, .y = 0, .z = 0 },
    );
    // -X face
    try appendWorldQuad(
        allocator,
        &vertices,
        &indices,
        .{ .x = -hx, .y = -hy, .z = hz },
        .{ .x = -hx, .y = -hy, .z = -hz },
        .{ .x = -hx, .y = hy, .z = -hz },
        .{ .x = -hx, .y = hy, .z = hz },
        .{ .x = -1, .y = 0, .z = 0 },
    );
    // +Y face
    try appendWorldQuad(
        allocator,
        &vertices,
        &indices,
        .{ .x = -hx, .y = hy, .z = -hz },
        .{ .x = hx, .y = hy, .z = -hz },
        .{ .x = hx, .y = hy, .z = hz },
        .{ .x = -hx, .y = hy, .z = hz },
        .{ .x = 0, .y = 1, .z = 0 },
    );
    // -Y face
    try appendWorldQuad(
        allocator,
        &vertices,
        &indices,
        .{ .x = -hx, .y = -hy, .z = hz },
        .{ .x = hx, .y = -hy, .z = hz },
        .{ .x = hx, .y = -hy, .z = -hz },
        .{ .x = -hx, .y = -hy, .z = -hz },
        .{ .x = 0, .y = -1, .z = 0 },
    );
    // +Z face
    try appendWorldQuad(
        allocator,
        &vertices,
        &indices,
        .{ .x = hx, .y = -hy, .z = hz },
        .{ .x = -hx, .y = -hy, .z = hz },
        .{ .x = -hx, .y = hy, .z = hz },
        .{ .x = hx, .y = hy, .z = hz },
        .{ .x = 0, .y = 0, .z = 1 },
    );
    // -Z face
    try appendWorldQuad(
        allocator,
        &vertices,
        &indices,
        .{ .x = -hx, .y = -hy, .z = -hz },
        .{ .x = hx, .y = -hy, .z = -hz },
        .{ .x = hx, .y = hy, .z = -hz },
        .{ .x = -hx, .y = hy, .z = -hz },
        .{ .x = 0, .y = 0, .z = -1 },
    );

    return .{
        .vertices = try vertices.toOwnedSlice(allocator),
        .indices = try indices.toOwnedSlice(allocator),
    };
}

fn buildPlane(allocator: std.mem.Allocator, width: f32, depth: f32) !Mesh {
    var vertices: std.ArrayList(Vertex) = .empty;
    defer vertices.deinit(allocator);
    var indices: std.ArrayList(u32) = .empty;
    defer indices.deinit(allocator);

    const hx = width * 0.5;
    const hz = depth * 0.5;
    try appendWorldQuad(
        allocator,
        &vertices,
        &indices,
        .{ .x = -hx, .y = 0, .z = -hz },
        .{ .x = hx, .y = 0, .z = -hz },
        .{ .x = hx, .y = 0, .z = hz },
        .{ .x = -hx, .y = 0, .z = hz },
        .{ .x = 0, .y = 1, .z = 0 },
    );

    return .{
        .vertices = try vertices.toOwnedSlice(allocator),
        .indices = try indices.toOwnedSlice(allocator),
    };
}

fn buildCylinder(allocator: std.mem.Allocator, radius: f32, height: f32, segments: u32) !Mesh {
    var vertices: std.ArrayList(Vertex) = .empty;
    defer vertices.deinit(allocator);
    var indices: std.ArrayList(u32) = .empty;
    defer indices.deinit(allocator);

    const seg = @max(3, segments);
    const hy = height * 0.5;
    const tau = std.math.pi * 2.0;

    // Side wall
    for (0..seg) |i| {
        const t0 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(seg));
        const t1 = @as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(seg));
        const a0 = t0 * tau;
        const a1 = t1 * tau;
        const c0 = @cos(a0);
        const s0 = @sin(a0);
        const c1 = @cos(a1);
        const s1 = @sin(a1);
        const n0: Vec3 = .{ .x = c0, .y = 0, .z = s0 };
        const n1: Vec3 = .{ .x = c1, .y = 0, .z = s1 };
        try appendQuad(
            allocator,
            &vertices,
            &indices,
            .{ .x = radius * c0, .y = -hy, .z = radius * s0 },
            .{ .x = radius * c1, .y = -hy, .z = radius * s1 },
            .{ .x = radius * c1, .y = hy, .z = radius * s1 },
            .{ .x = radius * c0, .y = hy, .z = radius * s0 },
            n0,
            .{ .x = t0 * tau * radius, .y = 0 },
            .{ .x = t1 * tau * radius, .y = 0 },
            .{ .x = t1 * tau * radius, .y = height },
            .{ .x = t0 * tau * radius, .y = height },
        );
        _ = n1;
    }

    // Top cap
    const top_center: u32 = @intCast(vertices.items.len);
    try appendVertex(allocator, &vertices, .{ .x = 0, .y = hy, .z = 0 }, .{ .x = 0, .y = 1, .z = 0 }, .{ .x = 0.5, .y = 0.5 });
    var top_ring: [64]u32 = undefined;
    const top_ring_len = @min(seg, 64);
    for (0..top_ring_len) |i| {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(top_ring_len));
        const a = t * tau;
        const c = @cos(a);
        const s = @sin(a);
        top_ring[i] = @intCast(vertices.items.len);
        try appendVertex(allocator, &vertices, .{ .x = radius * c, .y = hy, .z = radius * s }, .{ .x = 0, .y = 1, .z = 0 }, .{ .x = radius * c, .y = radius * s });
    }
    for (0..top_ring_len) |i| {
        const next = (i + 1) % top_ring_len;
        try indices.appendSlice(allocator, &.{ top_center, top_ring[next], top_ring[i] });
    }

    // Bottom cap
    const bottom_center: u32 = @intCast(vertices.items.len);
    try appendVertex(allocator, &vertices, .{ .x = 0, .y = -hy, .z = 0 }, .{ .x = 0, .y = -1, .z = 0 }, .{ .x = 0.5, .y = 0.5 });
    var bottom_ring: [64]u32 = undefined;
    for (0..top_ring_len) |i| {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(top_ring_len));
        const a = t * tau;
        const c = @cos(a);
        const s = @sin(a);
        bottom_ring[i] = @intCast(vertices.items.len);
        try appendVertex(allocator, &vertices, .{ .x = radius * c, .y = -hy, .z = radius * s }, .{ .x = 0, .y = -1, .z = 0 }, .{ .x = radius * c, .y = radius * s });
    }
    for (0..top_ring_len) |i| {
        const next = (i + 1) % top_ring_len;
        try indices.appendSlice(allocator, &.{ bottom_center, bottom_ring[i], bottom_ring[next] });
    }

    return .{
        .vertices = try vertices.toOwnedSlice(allocator),
        .indices = try indices.toOwnedSlice(allocator),
    };
}

fn buildSphere(allocator: std.mem.Allocator, radius: f32, segments: u32) !Mesh {
    var vertices: std.ArrayList(Vertex) = .empty;
    defer vertices.deinit(allocator);
    var indices: std.ArrayList(u32) = .empty;
    defer indices.deinit(allocator);

    const rings = @max(4, segments);
    const cols = @max(4, segments);
    const pi = std.math.pi;

    const top_center: u32 = @intCast(vertices.items.len);
    try appendVertex(allocator, &vertices, .{
        .x = 0,
        .y = radius,
        .z = 0,
    }, .{ .x = 0, .y = 1, .z = 0 }, .{ .x = 0, .y = 0 });

    for (1..rings) |ring| {
        const v = @as(f32, @floatFromInt(ring)) / @as(f32, @floatFromInt(rings));
        const phi = v * pi;
        const y = @cos(phi);
        const ring_radius = @sin(phi);
        for (0..cols) |col| {
            const u = @as(f32, @floatFromInt(col)) / @as(f32, @floatFromInt(cols));
            const theta = u * pi * 2.0;
            const x = ring_radius * @cos(theta);
            const z = ring_radius * @sin(theta);
            const normal: Vec3 = .{ .x = x, .y = y, .z = z };
            try appendVertex(allocator, &vertices, .{
                .x = radius * x,
                .y = radius * y,
                .z = radius * z,
            }, normal, .{ .x = u * std.math.tau * radius, .y = v * pi * radius });
        }
    }

    const bottom_center: u32 = @intCast(vertices.items.len);
    try appendVertex(allocator, &vertices, .{
        .x = 0,
        .y = -radius,
        .z = 0,
    }, .{ .x = 0, .y = -1, .z = 0 }, .{ .x = 0, .y = pi * radius });

    for (0..cols) |col| {
        const cur = sphereRingIndex(1, cols, col);
        const next = sphereRingIndex(1, cols, (col + 1) % cols);
        try indices.appendSlice(allocator, &.{ top_center, next, cur });
    }

    for (1..rings - 1) |ring| {
        for (0..cols) |col| {
            const vidx0 = sphereRingIndex(ring, cols, col);
            const vidx1 = sphereRingIndex(ring, cols, (col + 1) % cols);
            const vidx2 = sphereRingIndex(ring + 1, cols, col);
            const vidx3 = sphereRingIndex(ring + 1, cols, (col + 1) % cols);
            try indices.appendSlice(allocator, &.{ @intCast(vidx0), @intCast(vidx1), @intCast(vidx2), @intCast(vidx1), @intCast(vidx3), @intCast(vidx2) });
        }
    }

    for (0..cols) |col| {
        const cur = sphereRingIndex(rings - 1, cols, col);
        const next = sphereRingIndex(rings - 1, cols, (col + 1) % cols);
        try indices.appendSlice(allocator, &.{ bottom_center, cur, next });
    }

    return .{
        .vertices = try vertices.toOwnedSlice(allocator),
        .indices = try indices.toOwnedSlice(allocator),
    };
}

fn sphereRingIndex(ring: usize, cols: u32, col: usize) u32 {
    return 1 + @as(u32, @intCast((ring - 1) * cols + col));
}

pub fn groundOffsetY(kind: PrimitiveKind, params: PrimitiveParams, scale_y: f32) f32 {
    return switch (kind) {
        .plane => 0,
        .box => params.height * 0.5 * scale_y,
        .cylinder => params.height * 0.5 * scale_y,
        .sphere => params.radius * scale_y,
    };
}

pub fn meshGroundOffsetY(mesh: *const Mesh, scale_y: f32) f32 {
    var min_y: f32 = std.math.inf(f32);
    for (mesh.vertices) |vert| {
        min_y = @min(min_y, vert.position.y);
    }
    if (min_y >= 0) return 0;
    return -min_y * scale_y;
}

pub fn duplicateMesh(allocator: std.mem.Allocator, source: *const Mesh) !Mesh {
    const verts = try allocator.alloc(Vertex, source.vertices.len);
    @memcpy(verts, source.vertices);
    const idx = try allocator.alloc(u32, source.indices.len);
    @memcpy(idx, source.indices);
    const skin = if (source.skin) |value| try Skin.duplicate(allocator, &value) else null;
    return .{ .vertices = verts, .indices = idx, .skin = skin };
}

test "box primitive has world-space planar UVs per face" {
    var mesh = try buildPrimitive(std.testing.allocator, .box, .{ .width = 2, .height = 2, .depth = 2 });
    defer mesh.deinit(std.testing.allocator);
    try std.testing.expect(mesh.vertices.len == 24);
    try std.testing.expect(mesh.indices.len == 36);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), mesh.vertices[1].uv.x - mesh.vertices[0].uv.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), mesh.vertices[3].uv.y - mesh.vertices[0].uv.y, 0.0001);
    try validateUniformTexelDensity(&mesh, 128.0, 128.0, 0.001);
}

test "resized primitives keep texel density stable" {
    var small = try buildPrimitive(std.testing.allocator, .box, .{ .width = 1, .height = 2, .depth = 3 });
    defer small.deinit(std.testing.allocator);
    var large = try buildPrimitive(std.testing.allocator, .box, .{ .width = 4, .height = 5, .depth = 6 });
    defer large.deinit(std.testing.allocator);
    var plane = try buildPrimitive(std.testing.allocator, .plane, .{ .width = 7, .depth = 2 });
    defer plane.deinit(std.testing.allocator);

    try validateUniformTexelDensity(&small, 128.0, 128.0, 0.001);
    try validateUniformTexelDensity(&large, 128.0, 128.0, 0.001);
    try validateUniformTexelDensity(&plane, 128.0, 128.0, 0.001);
}

test "primitive triangles face outward for backface culling" {
    const cases = [_]struct {
        kind: PrimitiveKind,
        params: PrimitiveParams,
    }{
        .{ .kind = .box, .params = .{ .width = 2, .height = 2, .depth = 2 } },
        .{ .kind = .plane, .params = .{ .width = 2, .depth = 2 } },
        .{ .kind = .cylinder, .params = .{ .radius = 1, .height = 2, .segments = 16 } },
        .{ .kind = .sphere, .params = .{ .radius = 1, .segments = 16 } },
    };

    for (cases) |case| {
        var mesh = try buildPrimitive(std.testing.allocator, case.kind, case.params);
        defer mesh.deinit(std.testing.allocator);
        try expectMeshTrianglesMatchVertexNormals(&mesh);
    }
}

test "capsule debug mesh uses feet origin" {
    var mesh = try buildCapsuleFeetOrigin(std.testing.allocator, 0.35, 0.55, 16);
    defer mesh.deinit(std.testing.allocator);

    var min_y: f32 = std.math.inf(f32);
    var max_y: f32 = -std.math.inf(f32);
    for (mesh.vertices) |vertex| {
        min_y = @min(min_y, vertex.position.y);
        max_y = @max(max_y, vertex.position.y);
    }

    try std.testing.expectApproxEqAbs(@as(f32, 0), min_y, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.8), max_y, 0.0001);
}

test "every basic primitive faces outward across varied dimensions and segment counts" {
    const dims = [_]f32{ 0.1, 1, 2, 5, 17 };
    const segment_counts = [_]u32{ 3, 4, 5, 8, 16, 17, 32, 64, 65, 100 };

    for (dims) |width| {
        for (dims) |height| {
            for (dims) |depth| {
                var box_mesh = try buildPrimitive(std.testing.allocator, .box, .{ .width = width, .height = height, .depth = depth });
                defer box_mesh.deinit(std.testing.allocator);
                try expectMeshTrianglesMatchVertexNormals(&box_mesh);

                var plane_mesh = try buildPrimitive(std.testing.allocator, .plane, .{ .width = width, .depth = depth });
                defer plane_mesh.deinit(std.testing.allocator);
                try expectMeshTrianglesMatchVertexNormals(&plane_mesh);
            }
        }
    }

    for (dims) |radius| {
        for (dims) |height| {
            for (segment_counts) |segments| {
                var cylinder_mesh = try buildPrimitive(std.testing.allocator, .cylinder, .{ .radius = radius, .height = height, .segments = segments });
                defer cylinder_mesh.deinit(std.testing.allocator);
                try expectMeshTrianglesMatchVertexNormals(&cylinder_mesh);
            }
        }
    }

    for (dims) |radius| {
        for (segment_counts) |segments| {
            var sphere_mesh = try buildPrimitive(std.testing.allocator, .sphere, .{ .radius = radius, .segments = segments });
            defer sphere_mesh.deinit(std.testing.allocator);
            try expectMeshTrianglesMatchVertexNormals(&sphere_mesh);
        }
    }
}

fn expectMeshTrianglesMatchVertexNormals(mesh: *const Mesh) !void {
    var checked: usize = 0;
    var tri: usize = 0;
    while (tri + 2 < mesh.indices.len) : (tri += 3) {
        const a = mesh.vertices[mesh.indices[tri]];
        const b = mesh.vertices[mesh.indices[tri + 1]];
        const c = mesh.vertices[mesh.indices[tri + 2]];
        const face_normal = editor_math.cross(
            editor_math.Vec3.sub(b.position, a.position),
            editor_math.Vec3.sub(c.position, a.position),
        );
        const face_area_sq = face_normal.x * face_normal.x + face_normal.y * face_normal.y + face_normal.z * face_normal.z;
        try std.testing.expect(face_area_sq > 1e-20);
        const expected = a.normal;
        const alignment = face_normal.x * expected.x + face_normal.y * expected.y + face_normal.z * expected.z;
        try std.testing.expect(alignment > 0);
        checked += 1;
    }
    try std.testing.expect(checked > 0);
}

test "sphere primitive generates UV sphere" {
    var mesh = try buildPrimitive(std.testing.allocator, .sphere, .{ .radius = 1, .segments = 8 });
    defer mesh.deinit(std.testing.allocator);
    try std.testing.expect(mesh.vertices.len > 0);
    try std.testing.expect(mesh.indices.len > 0);
}
