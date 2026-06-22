const std = @import("std");
const geometry = @import("geometry.zig");

const glb_magic: u32 = 0x46546C67; // "glTF" as little-endian u32
const glb_version: u32 = 2;
const chunk_type_json: u32 = 0x4E4F534A; // "JSON"
const chunk_type_bin: u32 = 0x004E4942; // "BIN\0"

const component_type_f32: u32 = 5126;
const component_type_u32: u32 = 5125;
const primitive_mode_triangles: u32 = 4;

/// Encodes a static mesh (positions, normals, UVs, indices) as a binary GLB
/// document. Skinning data is not exported: props are static decorative
/// objects and don't use Mesh.skin today.
pub fn exportGlb(allocator: std.mem.Allocator, mesh: geometry.Mesh) ![]u8 {
    if (mesh.vertices.len == 0) return error.EmptyMesh;

    const binary = try buildBinaryBuffer(allocator, mesh);
    defer allocator.free(binary);

    const json_text = try buildJsonDocument(allocator, mesh, binary.len);
    defer allocator.free(json_text);

    return assembleGlb(allocator, json_text, binary);
}

fn buildBinaryBuffer(allocator: std.mem.Allocator, mesh: geometry.Mesh) ![]u8 {
    const vertex_count = mesh.vertices.len;
    const position_bytes = vertex_count * 3 * 4;
    const normal_bytes = vertex_count * 3 * 4;
    const uv_bytes = vertex_count * 2 * 4;
    const index_bytes = mesh.indices.len * 4;

    var out = try allocator.alloc(u8, position_bytes + normal_bytes + uv_bytes + index_bytes);
    errdefer allocator.free(out);

    var offset: usize = 0;
    for (mesh.vertices) |vertex| {
        writeF32Le(out, &offset, vertex.position.x);
        writeF32Le(out, &offset, vertex.position.y);
        writeF32Le(out, &offset, vertex.position.z);
    }
    for (mesh.vertices) |vertex| {
        writeF32Le(out, &offset, vertex.normal.x);
        writeF32Le(out, &offset, vertex.normal.y);
        writeF32Le(out, &offset, vertex.normal.z);
    }
    for (mesh.vertices) |vertex| {
        writeF32Le(out, &offset, vertex.uv.x);
        writeF32Le(out, &offset, vertex.uv.y);
    }
    for (mesh.indices) |index| {
        std.mem.writeInt(u32, out[offset..][0..4], index, .little);
        offset += 4;
    }
    std.debug.assert(offset == out.len);

    return out;
}

fn writeF32Le(out: []u8, offset: *usize, value: f32) void {
    std.mem.writeInt(u32, out[offset.*..][0..4], @bitCast(value), .little);
    offset.* += 4;
}

fn buildJsonDocument(allocator: std.mem.Allocator, mesh: geometry.Mesh, binary_len: usize) ![]u8 {
    const vertex_count = mesh.vertices.len;
    const position_bytes = vertex_count * 3 * 4;
    const normal_bytes = vertex_count * 3 * 4;
    const uv_bytes = vertex_count * 2 * 4;

    var bounds_min = mesh.vertices[0].position;
    var bounds_max = mesh.vertices[0].position;
    for (mesh.vertices) |vertex| {
        bounds_min.x = @min(bounds_min.x, vertex.position.x);
        bounds_min.y = @min(bounds_min.y, vertex.position.y);
        bounds_min.z = @min(bounds_min.z, vertex.position.z);
        bounds_max.x = @max(bounds_max.x, vertex.position.x);
        bounds_max.y = @max(bounds_max.y, vertex.position.y);
        bounds_max.z = @max(bounds_max.z, vertex.position.z);
    }

    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    const writer = &out.writer;

    try writer.print(
        "{{" ++
            "\"asset\":{{\"version\":\"2.0\",\"generator\":\"friendly-engine\"}}," ++
            "\"scene\":0," ++
            "\"scenes\":[{{\"nodes\":[0]}}]," ++
            "\"nodes\":[{{\"mesh\":0}}]," ++
            "\"meshes\":[{{\"primitives\":[{{\"attributes\":{{\"POSITION\":0,\"NORMAL\":1,\"TEXCOORD_0\":2}},\"indices\":3,\"mode\":{d}}}]}}]," ++
            "\"accessors\":[" ++
            "{{\"bufferView\":0,\"componentType\":{d},\"count\":{d},\"type\":\"VEC3\",\"min\":[{d},{d},{d}],\"max\":[{d},{d},{d}]}}," ++
            "{{\"bufferView\":1,\"componentType\":{d},\"count\":{d},\"type\":\"VEC3\"}}," ++
            "{{\"bufferView\":2,\"componentType\":{d},\"count\":{d},\"type\":\"VEC2\"}}," ++
            "{{\"bufferView\":3,\"componentType\":{d},\"count\":{d},\"type\":\"SCALAR\"}}" ++
            "]," ++
            "\"bufferViews\":[" ++
            "{{\"buffer\":0,\"byteOffset\":0,\"byteLength\":{d}}}," ++
            "{{\"buffer\":0,\"byteOffset\":{d},\"byteLength\":{d}}}," ++
            "{{\"buffer\":0,\"byteOffset\":{d},\"byteLength\":{d}}}," ++
            "{{\"buffer\":0,\"byteOffset\":{d},\"byteLength\":{d}}}" ++
            "]," ++
            "\"buffers\":[{{\"byteLength\":{d}}}]" ++
            "}}",
        .{
            primitive_mode_triangles,
            component_type_f32,
            vertex_count,
            bounds_min.x,
            bounds_min.y,
            bounds_min.z,
            bounds_max.x,
            bounds_max.y,
            bounds_max.z,
            component_type_f32,
            vertex_count,
            component_type_f32,
            vertex_count,
            component_type_u32,
            mesh.indices.len,
            position_bytes,
            position_bytes,
            normal_bytes,
            position_bytes + normal_bytes,
            uv_bytes,
            position_bytes + normal_bytes + uv_bytes,
            binary_len - position_bytes - normal_bytes - uv_bytes,
            binary_len,
        },
    );

    return out.toOwnedSlice();
}

fn assembleGlb(allocator: std.mem.Allocator, json_text: []const u8, binary: []const u8) ![]u8 {
    const json_padded_len = std.mem.alignForward(usize, json_text.len, 4);
    const bin_padded_len = std.mem.alignForward(usize, binary.len, 4);

    const total_len = 12 + 8 + json_padded_len + 8 + bin_padded_len;
    var out = try allocator.alloc(u8, total_len);
    errdefer allocator.free(out);

    var offset: usize = 0;
    std.mem.writeInt(u32, out[offset..][0..4], glb_magic, .little);
    offset += 4;
    std.mem.writeInt(u32, out[offset..][0..4], glb_version, .little);
    offset += 4;
    std.mem.writeInt(u32, out[offset..][0..4], @intCast(total_len), .little);
    offset += 4;

    std.mem.writeInt(u32, out[offset..][0..4], @intCast(json_padded_len), .little);
    offset += 4;
    std.mem.writeInt(u32, out[offset..][0..4], chunk_type_json, .little);
    offset += 4;
    @memcpy(out[offset..][0..json_text.len], json_text);
    offset += json_text.len;
    @memset(out[offset..][0 .. json_padded_len - json_text.len], ' ');
    offset += json_padded_len - json_text.len;

    std.mem.writeInt(u32, out[offset..][0..4], @intCast(bin_padded_len), .little);
    offset += 4;
    std.mem.writeInt(u32, out[offset..][0..4], chunk_type_bin, .little);
    offset += 4;
    @memcpy(out[offset..][0..binary.len], binary);
    offset += binary.len;
    @memset(out[offset..][0 .. bin_padded_len - binary.len], 0);
    offset += bin_padded_len - binary.len;

    std.debug.assert(offset == total_len);
    return out;
}

test "exportGlb produces a header with glTF magic and version 2" {
    var mesh = try geometry.buildPrimitive(std.testing.allocator, .box, .{ .width = 1, .height = 1, .depth = 1 });
    defer mesh.deinit(std.testing.allocator);

    const bytes = try exportGlb(std.testing.allocator, mesh);
    defer std.testing.allocator.free(bytes);

    try std.testing.expect(bytes.len >= 12);
    try std.testing.expectEqualStrings("glTF", bytes[0..4]);
    try std.testing.expectEqual(@as(u32, 2), std.mem.readInt(u32, bytes[4..8], .little));
    const total_len = std.mem.readInt(u32, bytes[8..12], .little);
    try std.testing.expectEqual(@as(u32, @intCast(bytes.len)), total_len);
}

test "exportGlb round trips through the existing glTF importer" {
    const gltf_import = @import("gltf_import.zig");
    const mesh_codec = @import("mesh_codec.zig");

    var source = try geometry.buildPrimitive(std.testing.allocator, .box, .{ .width = 2, .height = 1, .depth = 0.5 });
    defer source.deinit(std.testing.allocator);
    // buildPrimitive's box repeats the same [0,1]x[0,1] UV square on every
    // face (normal texture-repeat UVs). The importer's atlas validation
    // requires non-overlapping per-triangle UV charts, so give each face its
    // own exclusive horizontal strip for this round-trip test specifically.
    for (source.vertices, 0..) |*vertex, i| {
        const face: f32 = @floatFromInt(i / 4);
        vertex.uv.x = (face + vertex.uv.x) / 6.0;
    }

    const glb_bytes = try exportGlb(std.testing.allocator, source);
    defer std.testing.allocator.free(glb_bytes);

    const encoded = try gltf_import.importGlb(std.testing.allocator, glb_bytes);
    defer std.testing.allocator.free(encoded);
    var decoded = try mesh_codec.decodeMesh(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);

    try std.testing.expectEqual(source.vertices.len, decoded.vertices.len);
    try std.testing.expectEqual(source.indices.len, decoded.indices.len);
    for (source.vertices, decoded.vertices) |expected, actual| {
        try std.testing.expectApproxEqAbs(expected.position.x, actual.position.x, 0.0001);
        try std.testing.expectApproxEqAbs(expected.position.y, actual.position.y, 0.0001);
        try std.testing.expectApproxEqAbs(expected.position.z, actual.position.z, 0.0001);
        try std.testing.expectApproxEqAbs(expected.normal.x, actual.normal.x, 0.0001);
        try std.testing.expectApproxEqAbs(expected.normal.y, actual.normal.y, 0.0001);
        try std.testing.expectApproxEqAbs(expected.normal.z, actual.normal.z, 0.0001);
    }
    for (source.indices, decoded.indices) |expected, actual| {
        try std.testing.expectEqual(expected, actual);
    }
}
