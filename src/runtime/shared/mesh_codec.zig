const std = @import("std");
const geometry = @import("geometry.zig");
const editor_math = @import("editor_math.zig");

pub const magic: [4]u8 = .{ 'F', 'M', 'E', 'S' };
pub const version: u32 = 2;
pub const version_v1: u32 = 1;

pub fn encodeMesh(allocator: std.mem.Allocator, mesh: geometry.Mesh) ![]u8 {
    const vertex_bytes = mesh.vertices.len * @sizeOf(geometry.Vertex);
    const index_bytes = mesh.indices.len * @sizeOf(u32);
    const skin_bytes = if (mesh.skin) |skin|
        1 + skin.influences.len * @sizeOf(geometry.SkinInfluence) + 4 + skin.inverse_bind.len * @sizeOf(editor_math.Mat4) + skin.bind_vertices.len * @sizeOf(geometry.Vertex)
    else
        1;
    const total: usize = 4 + 4 + 4 + 4 + vertex_bytes + index_bytes + skin_bytes;

    var out = try allocator.alloc(u8, total);
    var offset: usize = 0;

    @memcpy(out[offset..][0..4], &magic);
    offset += 4;
    std.mem.writeInt(u32, out[offset..][0..4], version, .little);
    offset += 4;
    std.mem.writeInt(u32, out[offset..][0..4], @intCast(mesh.vertices.len), .little);
    offset += 4;
    std.mem.writeInt(u32, out[offset..][0..4], @intCast(mesh.indices.len), .little);
    offset += 4;

    const vert_slice = std.mem.sliceAsBytes(mesh.vertices);
    @memcpy(out[offset..][0..vert_slice.len], vert_slice);
    offset += vert_slice.len;

    const idx_slice = std.mem.sliceAsBytes(mesh.indices);
    @memcpy(out[offset..][0..idx_slice.len], idx_slice);
    offset += idx_slice.len;

    if (mesh.skin) |skin| {
        out[offset] = 1;
        offset += 1;
        const influence_slice = std.mem.sliceAsBytes(skin.influences);
        @memcpy(out[offset..][0..influence_slice.len], influence_slice);
        offset += influence_slice.len;
        std.mem.writeInt(u32, out[offset..][0..4], @intCast(skin.inverse_bind.len), .little);
        offset += 4;
        const inverse_bind_slice = std.mem.sliceAsBytes(skin.inverse_bind);
        @memcpy(out[offset..][0..inverse_bind_slice.len], inverse_bind_slice);
        offset += inverse_bind_slice.len;
        const bind_slice = std.mem.sliceAsBytes(skin.bind_vertices);
        @memcpy(out[offset..][0..bind_slice.len], bind_slice);
        offset += bind_slice.len;
    } else {
        out[offset] = 0;
        offset += 1;
    }

    std.debug.assert(offset == total);
    return out;
}

pub fn decodeMesh(allocator: std.mem.Allocator, bytes: []const u8) !geometry.Mesh {
    if (bytes.len < 16) return error.InvalidMeshFormat;
    if (!std.mem.eql(u8, bytes[0..4], &magic)) return error.InvalidMeshFormat;

    const file_version = std.mem.readInt(u32, bytes[4..8], .little);
    return switch (file_version) {
        version_v1 => decodeMeshV1(allocator, bytes),
        version => decodeMeshV2(allocator, bytes),
        else => error.UnsupportedMeshVersion,
    };
}

fn decodeMeshV1(allocator: std.mem.Allocator, bytes: []const u8) !geometry.Mesh {
    const vertex_count = std.mem.readInt(u32, bytes[8..12], .little);
    const index_count = std.mem.readInt(u32, bytes[12..16], .little);

    const vertex_bytes = vertex_count * @sizeOf(geometry.Vertex);
    const index_bytes = index_count * @sizeOf(u32);
    const expected = 16 + vertex_bytes + index_bytes;
    if (bytes.len != expected) return error.InvalidMeshFormat;

    const vertices = try allocator.alloc(geometry.Vertex, vertex_count);
    errdefer allocator.free(vertices);
    @memcpy(std.mem.sliceAsBytes(vertices), bytes[16 .. 16 + vertex_bytes]);

    const indices = try allocator.alloc(u32, index_count);
    errdefer allocator.free(indices);
    @memcpy(std.mem.sliceAsBytes(indices), bytes[16 + vertex_bytes .. expected]);

    return .{ .vertices = vertices, .indices = indices };
}

fn decodeMeshV2(allocator: std.mem.Allocator, bytes: []const u8) !geometry.Mesh {
    const vertex_count = std.mem.readInt(u32, bytes[8..12], .little);
    const index_count = std.mem.readInt(u32, bytes[12..16], .little);

    const vertex_bytes = vertex_count * @sizeOf(geometry.Vertex);
    const index_bytes = index_count * @sizeOf(u32);
    var offset: usize = 16 + vertex_bytes + index_bytes;
    if (bytes.len < offset + 1) return error.InvalidMeshFormat;

    const vertices = try allocator.alloc(geometry.Vertex, vertex_count);
    errdefer allocator.free(vertices);
    @memcpy(std.mem.sliceAsBytes(vertices), bytes[16 .. 16 + vertex_bytes]);

    const indices = try allocator.alloc(u32, index_count);
    errdefer allocator.free(indices);
    @memcpy(std.mem.sliceAsBytes(indices), bytes[16 + vertex_bytes .. offset]);

    const has_skin = bytes[offset] == 1;
    offset += 1;
    if (!has_skin) {
        if (offset != bytes.len) return error.InvalidMeshFormat;
        return .{ .vertices = vertices, .indices = indices };
    }

    const influence_bytes = vertex_count * @sizeOf(geometry.SkinInfluence);
    if (bytes.len < offset + influence_bytes + 4) return error.InvalidMeshFormat;
    const influences = try allocator.alloc(geometry.SkinInfluence, vertex_count);
    errdefer allocator.free(influences);
    @memcpy(std.mem.sliceAsBytes(influences), bytes[offset .. offset + influence_bytes]);
    offset += influence_bytes;

    const bone_count = std.mem.readInt(u32, bytes[offset..][0..4], .little);
    offset += 4;
    const inverse_bind_bytes = bone_count * @sizeOf(editor_math.Mat4);
    if (bytes.len < offset + inverse_bind_bytes + vertex_bytes) return error.InvalidMeshFormat;
    const inverse_bind = try allocator.alloc(editor_math.Mat4, bone_count);
    errdefer allocator.free(inverse_bind);
    @memcpy(std.mem.sliceAsBytes(inverse_bind), bytes[offset .. offset + inverse_bind_bytes]);
    offset += inverse_bind_bytes;

    const bind_vertices = try allocator.alloc(geometry.Vertex, vertex_count);
    errdefer allocator.free(bind_vertices);
    @memcpy(std.mem.sliceAsBytes(bind_vertices), bytes[offset .. offset + vertex_bytes]);
    offset += vertex_bytes;

    if (offset != bytes.len) return error.InvalidMeshFormat;
    return .{
        .vertices = vertices,
        .indices = indices,
        .skin = .{
            .bind_vertices = bind_vertices,
            .influences = influences,
            .inverse_bind = inverse_bind,
        },
    };
}

test "mesh codec round trip" {
    var mesh = try geometry.buildPrimitive(std.testing.allocator, .box, .{});
    defer mesh.deinit(std.testing.allocator);

    const encoded = try encodeMesh(std.testing.allocator, mesh);
    defer std.testing.allocator.free(encoded);

    var decoded = try decodeMesh(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);

    try std.testing.expectEqual(mesh.vertices.len, decoded.vertices.len);
    try std.testing.expectEqual(mesh.indices.len, decoded.indices.len);
    try std.testing.expectEqual(mesh.vertices[0].position.x, decoded.vertices[0].position.x);
}

test "mesh codec round trip with skin" {
    const bind = [_]geometry.Vertex{
        .{ .position = .{ .x = 0, .y = 1, .z = 0 }, .normal = .{ .x = 0, .y = 1, .z = 0 }, .uv = .{ .x = 0, .y = 0 } },
    };
    const influences = [_]geometry.SkinInfluence{
        .{ .joints = .{ 0, 0, 0, 0 }, .weights = .{ 1, 0, 0, 0 } },
    };
    const inverse_bind = [_]editor_math.Mat4{editor_math.Mat4.identity()};
    var mesh = geometry.Mesh{
        .vertices = try std.testing.allocator.dupe(geometry.Vertex, &bind),
        .indices = try std.testing.allocator.dupe(u32, &.{0}),
        .skin = .{
            .bind_vertices = try std.testing.allocator.dupe(geometry.Vertex, &bind),
            .influences = try std.testing.allocator.dupe(geometry.SkinInfluence, &influences),
            .inverse_bind = try std.testing.allocator.dupe(editor_math.Mat4, &inverse_bind),
        },
    };
    defer mesh.deinit(std.testing.allocator);

    const encoded = try encodeMesh(std.testing.allocator, mesh);
    defer std.testing.allocator.free(encoded);

    var decoded = try decodeMesh(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);

    try std.testing.expect(decoded.skin != null);
    try std.testing.expectEqual(@as(usize, 1), decoded.skin.?.inverse_bind.len);
    try std.testing.expectApproxEqAbs(@as(f32, 1), decoded.skin.?.bind_vertices[0].position.y, 0.001);
}
