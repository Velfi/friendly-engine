const std = @import("std");
const geometry = @import("geometry.zig");
const editor_math = @import("editor_math.zig");

const c = @cImport({
    @cInclude("fe_xatlas_bridge.h");
});

pub const AtlasOptions = struct {
    atlas_size: u32 = 128,
    padding_px: u32 = 4,
    texels_per_unit: f32 = 0,
    max_chart_area: f32 = 0,
    normal_seam_weight: f32 = 4,
    max_iterations: u32 = 1,
};

pub const UvReport = struct {
    chart_count: u32 = 0,
    atlas_width: u32 = 0,
    atlas_height: u32 = 0,
    atlas_count: u32 = 0,
    utilization: f32 = 0,
    duplicated_vertex_count: u32 = 0,
    degenerate_triangle_count: u32 = 0,
    texels_per_unit: f32 = 0,
};

const uv_epsilon: f32 = 0.000001;

pub const AtlasResult = struct {
    mesh: geometry.Mesh,
    report: UvReport,

    pub fn deinit(self: *AtlasResult, allocator: std.mem.Allocator) void {
        self.mesh.deinit(allocator);
    }
};

pub const xatlas_commit: []const u8 = "f700c7790aaa030e794b52ba7791a05c085faf0c";

pub fn generatePaintAtlas(allocator: std.mem.Allocator, mesh: *const geometry.Mesh, options: AtlasOptions) !AtlasResult {
    try validateInputMesh(mesh);
    if (mesh.isSkinned()) return error.UnsupportedSkinnedAtlasGeneration;

    const positions = try allocator.alloc(f32, mesh.vertices.len * 3);
    defer allocator.free(positions);
    const normals = try allocator.alloc(f32, mesh.vertices.len * 3);
    defer allocator.free(normals);

    for (mesh.vertices, 0..) |vertex, i| {
        const base = i * 3;
        positions[base] = vertex.position.x;
        positions[base + 1] = vertex.position.y;
        positions[base + 2] = vertex.position.z;
        normals[base] = vertex.normal.x;
        normals[base + 1] = vertex.normal.y;
        normals[base + 2] = vertex.normal.z;
    }

    const input = c.FeXatlasInput{
        .positions = positions.ptr,
        .normals = normals.ptr,
        .indices = mesh.indices.ptr,
        .face_materials = null,
        .vertex_count = @intCast(mesh.vertices.len),
        .position_stride = @sizeOf(f32) * 3,
        .normal_stride = @sizeOf(f32) * 3,
        .index_count = @intCast(mesh.indices.len),
        .face_count = @intCast(mesh.indices.len / 3),
    };
    const c_options = c.FeXatlasOptions{
        .atlas_size = options.atlas_size,
        .padding_px = options.padding_px,
        .max_iterations = options.max_iterations,
        .texels_per_unit = options.texels_per_unit,
        .max_chart_area = options.max_chart_area,
        .normal_seam_weight = options.normal_seam_weight,
    };

    const output = c.fe_xatlas_generate(&input, &c_options);
    defer if (output.atlas != null) c.fe_xatlas_destroy(output.atlas);
    try mapXatlasError(output.error_code);
    if (output.vertices == null or output.indices == null) return error.MissingAtlasOutput;
    if (output.atlas_width == 0 or output.atlas_height == 0) return error.InvalidAtlasOutput;
    if (output.index_count != mesh.indices.len) return error.InvalidAtlasOutput;

    const vertices = try allocator.alloc(geometry.Vertex, output.vertex_count);
    errdefer allocator.free(vertices);
    for (vertices, 0..) |*vertex, i| {
        const atlas_vertex = output.vertices[i];
        if (atlas_vertex.xref >= mesh.vertices.len) return error.InvalidAtlasOutput;
        const source = mesh.vertices[atlas_vertex.xref];
        vertex.* = source;
        if (atlas_vertex.atlas_index < 0) return error.InvalidAtlasOutput;
        vertex.uv = .{
            .x = atlas_vertex.uv[0] / @as(f32, @floatFromInt(output.atlas_width)),
            .y = atlas_vertex.uv[1] / @as(f32, @floatFromInt(output.atlas_height)),
        };
    }

    const indices = try allocator.alloc(u32, output.index_count);
    errdefer allocator.free(indices);
    @memcpy(indices, output.indices[0..output.index_count]);

    const generated = geometry.Mesh{ .vertices = vertices, .indices = indices };
    const validation = try validateUvSet(&generated);
    return .{
        .mesh = generated,
        .report = .{
            .chart_count = output.chart_count,
            .atlas_width = output.atlas_width,
            .atlas_height = output.atlas_height,
            .atlas_count = output.atlas_count,
            .utilization = output.utilization,
            .duplicated_vertex_count = @intCast(if (output.vertex_count > mesh.vertices.len) output.vertex_count - mesh.vertices.len else 0),
            .degenerate_triangle_count = validation.degenerate_triangle_count,
            .texels_per_unit = output.texels_per_unit,
        },
    };
}

pub fn validateUvSet(mesh: *const geometry.Mesh) !UvReport {
    try validateInputMesh(mesh);
    var all_zero = true;
    var tri: usize = 0;
    while (tri < mesh.indices.len) : (tri += 3) {
        const a = mesh.vertices[mesh.indices[tri]];
        const b = mesh.vertices[mesh.indices[tri + 1]];
        const d = mesh.vertices[mesh.indices[tri + 2]];
        try validateUv(a.uv);
        try validateUv(b.uv);
        try validateUv(d.uv);
        all_zero = all_zero and isZeroUv(a.uv) and isZeroUv(b.uv) and isZeroUv(d.uv);
        if (@abs(uvTriangleArea(a.uv, b.uv, d.uv)) <= 0.0000001) return error.CollapsedUvChart;
    }
    if (all_zero) return error.CollapsedUvChart;
    try validateUvChartsDoNotOverlap(mesh);
    return .{
        .atlas_width = 1,
        .atlas_height = 1,
    };
}

pub fn validateRenderableUvSet(mesh: *const geometry.Mesh) !UvReport {
    try validateInputMesh(mesh);
    var all_zero = true;
    var tri: usize = 0;
    while (tri < mesh.indices.len) : (tri += 3) {
        const a = mesh.vertices[mesh.indices[tri]];
        const b = mesh.vertices[mesh.indices[tri + 1]];
        const d = mesh.vertices[mesh.indices[tri + 2]];
        try validateFiniteUv(a.uv);
        try validateFiniteUv(b.uv);
        try validateFiniteUv(d.uv);
        all_zero = all_zero and isZeroUv(a.uv) and isZeroUv(b.uv) and isZeroUv(d.uv);
        if (@abs(uvTriangleArea(a.uv, b.uv, d.uv)) <= 0.0000001) return error.CollapsedUvChart;
    }
    if (all_zero) return error.CollapsedUvChart;
    return .{
        .atlas_width = 1,
        .atlas_height = 1,
    };
}

fn validateUvChartsDoNotOverlap(mesh: *const geometry.Mesh) !void {
    var tri_a: usize = 0;
    while (tri_a < mesh.indices.len) : (tri_a += 3) {
        const a = uvTriangleAt(mesh, tri_a);
        var tri_b = tri_a + 3;
        while (tri_b < mesh.indices.len) : (tri_b += 3) {
            const b = uvTriangleAt(mesh, tri_b);
            if (uvTrianglesOverlapWithArea(a, b)) return error.OverlappingUvChart;
        }
    }
}

fn validateInputMesh(mesh: *const geometry.Mesh) !void {
    if (mesh.vertices.len == 0) return error.EmptyMesh;
    if (mesh.indices.len == 0 or mesh.indices.len % 3 != 0) return error.InvalidIndexCount;
    if (mesh.vertices.len > std.math.maxInt(u32)) return error.MeshTooLarge;
    var tri: usize = 0;
    while (tri < mesh.indices.len) : (tri += 3) {
        const ia = mesh.indices[tri];
        const ib = mesh.indices[tri + 1];
        const ic = mesh.indices[tri + 2];
        if (ia >= mesh.vertices.len or ib >= mesh.vertices.len or ic >= mesh.vertices.len) return error.IndexOutOfRange;
        const a = mesh.vertices[ia];
        const b = mesh.vertices[ib];
        const d = mesh.vertices[ic];
        try validateVec3(a.position);
        try validateVec3(b.position);
        try validateVec3(d.position);
        try validateVec3(a.normal);
        try validateVec3(b.normal);
        try validateVec3(d.normal);
        if (triangleAreaSq(a.position, b.position, d.position) <= 0.000000000001) return error.DegenerateTriangle;
    }
}

fn mapXatlasError(code: c_int) !void {
    return switch (code) {
        c.FE_XATLAS_OK => {},
        c.FE_XATLAS_INDEX_OUT_OF_RANGE => error.IndexOutOfRange,
        c.FE_XATLAS_INVALID_FACE_VERTEX_COUNT => error.InvalidFaceVertexCount,
        c.FE_XATLAS_INVALID_INDEX_COUNT => error.InvalidIndexCount,
        c.FE_XATLAS_MISSING_OUTPUT_MESH => error.MissingAtlasOutput,
        else => error.XatlasGenerationFailed,
    };
}

fn validateUv(uv: editor_math.Vec2) !void {
    try validateFiniteUv(uv);
    if (uv.x < 0 or uv.x > 1 or uv.y < 0 or uv.y > 1) return error.UvOutOfRange;
}

fn validateFiniteUv(uv: editor_math.Vec2) !void {
    if (!std.math.isFinite(uv.x) or !std.math.isFinite(uv.y)) return error.InvalidUvSet;
}

const UvTriangle = struct {
    a: editor_math.Vec2,
    b: editor_math.Vec2,
    c: editor_math.Vec2,
};

fn uvTriangleAt(mesh: *const geometry.Mesh, tri_offset: usize) UvTriangle {
    return .{
        .a = mesh.vertices[mesh.indices[tri_offset]].uv,
        .b = mesh.vertices[mesh.indices[tri_offset + 1]].uv,
        .c = mesh.vertices[mesh.indices[tri_offset + 2]].uv,
    };
}

fn uvTrianglesOverlapWithArea(a: UvTriangle, b: UvTriangle) bool {
    if (bboxSeparated(a, b)) return false;
    if (pointStrictlyInsideTriangle(centroid(a), b)) return true;
    if (pointStrictlyInsideTriangle(centroid(b), a)) return true;
    if (pointStrictlyInsideTriangle(a.a, b) or pointStrictlyInsideTriangle(a.b, b) or pointStrictlyInsideTriangle(a.c, b)) return true;
    if (pointStrictlyInsideTriangle(b.a, a) or pointStrictlyInsideTriangle(b.b, a) or pointStrictlyInsideTriangle(b.c, a)) return true;
    return edgeCrossesTriangleInterior(a.a, a.b, b) or
        edgeCrossesTriangleInterior(a.b, a.c, b) or
        edgeCrossesTriangleInterior(a.c, a.a, b);
}

fn bboxSeparated(a: UvTriangle, b: UvTriangle) bool {
    const a_min_x = @min(a.a.x, @min(a.b.x, a.c.x));
    const a_max_x = @max(a.a.x, @max(a.b.x, a.c.x));
    const a_min_y = @min(a.a.y, @min(a.b.y, a.c.y));
    const a_max_y = @max(a.a.y, @max(a.b.y, a.c.y));
    const b_min_x = @min(b.a.x, @min(b.b.x, b.c.x));
    const b_max_x = @max(b.a.x, @max(b.b.x, b.c.x));
    const b_min_y = @min(b.a.y, @min(b.b.y, b.c.y));
    const b_max_y = @max(b.a.y, @max(b.b.y, b.c.y));
    return a_max_x <= b_min_x + uv_epsilon or
        b_max_x <= a_min_x + uv_epsilon or
        a_max_y <= b_min_y + uv_epsilon or
        b_max_y <= a_min_y + uv_epsilon;
}

fn centroid(tri: UvTriangle) editor_math.Vec2 {
    return .{
        .x = (tri.a.x + tri.b.x + tri.c.x) / 3.0,
        .y = (tri.a.y + tri.b.y + tri.c.y) / 3.0,
    };
}

fn pointStrictlyInsideTriangle(point: editor_math.Vec2, tri: UvTriangle) bool {
    const area = uvTriangleArea(tri.a, tri.b, tri.c);
    if (@abs(area) <= uv_epsilon) return false;
    const sign: f32 = if (area >= 0) 1.0 else -1.0;
    const ab = sign * orient2d(tri.a, tri.b, point);
    const bc = sign * orient2d(tri.b, tri.c, point);
    const ca = sign * orient2d(tri.c, tri.a, point);
    return ab > uv_epsilon and bc > uv_epsilon and ca > uv_epsilon;
}

fn edgeCrossesTriangleInterior(a: editor_math.Vec2, b: editor_math.Vec2, tri: UvTriangle) bool {
    return segmentsCrossProperly(a, b, tri.a, tri.b) or
        segmentsCrossProperly(a, b, tri.b, tri.c) or
        segmentsCrossProperly(a, b, tri.c, tri.a);
}

fn segmentsCrossProperly(a: editor_math.Vec2, b: editor_math.Vec2, c_uv: editor_math.Vec2, d: editor_math.Vec2) bool {
    const ab_c = orient2d(a, b, c_uv);
    const ab_d = orient2d(a, b, d);
    const cd_a = orient2d(c_uv, d, a);
    const cd_b = orient2d(c_uv, d, b);
    return oppositeSigns(ab_c, ab_d) and oppositeSigns(cd_a, cd_b);
}

fn oppositeSigns(a: f32, b: f32) bool {
    return (a > uv_epsilon and b < -uv_epsilon) or (a < -uv_epsilon and b > uv_epsilon);
}

fn orient2d(a: editor_math.Vec2, b: editor_math.Vec2, c_uv: editor_math.Vec2) f32 {
    return (b.x - a.x) * (c_uv.y - a.y) - (b.y - a.y) * (c_uv.x - a.x);
}

fn validateVec3(value: editor_math.Vec3) !void {
    if (!std.math.isFinite(value.x) or !std.math.isFinite(value.y) or !std.math.isFinite(value.z)) return error.InvalidMeshVertex;
}

fn isZeroUv(uv: editor_math.Vec2) bool {
    return @abs(uv.x) <= 0.0000001 and @abs(uv.y) <= 0.0000001;
}

fn uvTriangleArea(a: editor_math.Vec2, b: editor_math.Vec2, c_uv: editor_math.Vec2) f32 {
    return ((b.x - a.x) * (c_uv.y - a.y) - (b.y - a.y) * (c_uv.x - a.x)) * 0.5;
}

fn triangleAreaSq(a: editor_math.Vec3, b: editor_math.Vec3, c_pos: editor_math.Vec3) f32 {
    const ab = editor_math.Vec3.sub(b, a);
    const ac = editor_math.Vec3.sub(c_pos, a);
    const cross = editor_math.cross(ab, ac);
    return cross.x * cross.x + cross.y * cross.y + cross.z * cross.z;
}

test "xatlas generates valid paint atlas for cube" {
    var mesh = try geometry.buildPrimitive(std.testing.allocator, .box, .{ .width = 2, .height = 2, .depth = 2 });
    defer mesh.deinit(std.testing.allocator);

    var result = try generatePaintAtlas(std.testing.allocator, &mesh, .{});
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(mesh.indices.len, result.mesh.indices.len);
    try std.testing.expect(result.report.chart_count > 0);
    _ = try validateUvSet(&result.mesh);
}

test "xatlas generates valid paint atlas for sphere" {
    var mesh = try geometry.buildPrimitive(std.testing.allocator, .sphere, .{ .radius = 1, .segments = 12 });
    defer mesh.deinit(std.testing.allocator);

    var result = try generatePaintAtlas(std.testing.allocator, &mesh, .{});
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(mesh.indices.len, result.mesh.indices.len);
    _ = try validateUvSet(&result.mesh);
}

test "uv validation rejects all zero uv coordinates" {
    var mesh = try geometry.buildPrimitive(std.testing.allocator, .box, .{ .width = 1, .height = 1, .depth = 1 });
    defer mesh.deinit(std.testing.allocator);
    for (mesh.vertices) |*vertex| vertex.uv = .{ .x = 0, .y = 0 };

    try std.testing.expectError(error.CollapsedUvChart, validateUvSet(&mesh));
}

test "uv validation rejects overlapping triangles" {
    const vertices = try std.testing.allocator.dupe(geometry.Vertex, &.{
        .{ .position = .{ .x = 0, .y = 0, .z = 0 }, .normal = .{ .x = 0, .y = 1, .z = 0 }, .uv = .{ .x = 0, .y = 0 } },
        .{ .position = .{ .x = 1, .y = 0, .z = 0 }, .normal = .{ .x = 0, .y = 1, .z = 0 }, .uv = .{ .x = 1, .y = 0 } },
        .{ .position = .{ .x = 0, .y = 0, .z = 1 }, .normal = .{ .x = 0, .y = 1, .z = 0 }, .uv = .{ .x = 0, .y = 1 } },
        .{ .position = .{ .x = 0.1, .y = 0, .z = 0.1 }, .normal = .{ .x = 0, .y = 1, .z = 0 }, .uv = .{ .x = 0.1, .y = 0.1 } },
        .{ .position = .{ .x = 0.9, .y = 0, .z = 0.1 }, .normal = .{ .x = 0, .y = 1, .z = 0 }, .uv = .{ .x = 0.9, .y = 0.1 } },
        .{ .position = .{ .x = 0.1, .y = 0, .z = 0.9 }, .normal = .{ .x = 0, .y = 1, .z = 0 }, .uv = .{ .x = 0.1, .y = 0.9 } },
    });
    const indices = try std.testing.allocator.dupe(u32, &.{ 0, 1, 2, 3, 4, 5 });
    var mesh = geometry.Mesh{ .vertices = vertices, .indices = indices };
    defer mesh.deinit(std.testing.allocator);

    try std.testing.expectError(error.OverlappingUvChart, validateUvSet(&mesh));
}

test "uv generation rejects degenerate triangles" {
    const vertices = try std.testing.allocator.dupe(geometry.Vertex, &.{
        .{ .position = .{ .x = 0, .y = 0, .z = 0 }, .normal = .{ .x = 0, .y = 1, .z = 0 }, .uv = .{ .x = 0, .y = 0 } },
        .{ .position = .{ .x = 0, .y = 0, .z = 0 }, .normal = .{ .x = 0, .y = 1, .z = 0 }, .uv = .{ .x = 1, .y = 0 } },
        .{ .position = .{ .x = 0, .y = 0, .z = 0 }, .normal = .{ .x = 0, .y = 1, .z = 0 }, .uv = .{ .x = 0, .y = 1 } },
    });
    const indices = try std.testing.allocator.dupe(u32, &.{ 0, 1, 2 });
    var mesh = geometry.Mesh{ .vertices = vertices, .indices = indices };
    defer mesh.deinit(std.testing.allocator);

    try std.testing.expectError(error.DegenerateTriangle, generatePaintAtlas(std.testing.allocator, &mesh, .{}));
}
