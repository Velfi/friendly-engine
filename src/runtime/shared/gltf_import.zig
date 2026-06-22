const std = @import("std");
const zgltf = @import("zgltf");
const geometry = @import("geometry.zig");
const mesh_codec = @import("mesh_codec.zig");
const scene_animation = @import("scene_animation.zig");
const editor_math = @import("editor_math.zig");
const uv_atlas = @import("uv_atlas.zig");

pub fn importGlb(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    var mesh = try parseGltfMesh(allocator, bytes, .{});
    defer mesh.deinit(allocator);
    return mesh_codec.encodeMesh(allocator, mesh);
}

pub fn importGlbWithGeneratedPaintAtlas(allocator: std.mem.Allocator, bytes: []const u8, atlas_options: uv_atlas.AtlasOptions) ![]u8 {
    var mesh = try parseGltfMesh(allocator, bytes, .{ .generate_missing_uvs = true, .atlas_options = atlas_options });
    defer mesh.deinit(allocator);
    return mesh_codec.encodeMesh(allocator, mesh);
}

pub fn extractSkeletons(allocator: std.mem.Allocator, bytes: []const u8, asset_ref: []const u8) ![]scene_animation.Skeleton {
    const aligned = try copyAligned(allocator, bytes);
    defer allocator.free(aligned);

    var gltf = zgltf.Gltf.init(allocator);
    defer gltf.deinit();
    try gltf.parse(aligned);

    var skeletons = try allocator.alloc(scene_animation.Skeleton, gltf.data.skins.len);
    var skeleton_count: usize = 0;
    errdefer {
        for (skeletons[0..skeleton_count]) |*skeleton| skeleton.deinit(allocator);
        allocator.free(skeletons);
    }
    for (gltf.data.skins, 0..) |skin, idx| {
        var bones = try allocator.alloc(scene_animation.Bone, skin.joints.len);
        errdefer allocator.free(bones);
        for (skin.joints, 0..) |node_index, bone_idx| {
            const node = gltf.data.nodes[node_index];
            bones[bone_idx] = .{
                .index = @intCast(bone_idx),
                .parent = parentJointIndex(skin.joints, node.parent),
                .name = try allocator.dupe(u8, node.name orelse "Bone"),
                .rest = nodeTransform(node),
            };
        }
        skeletons[idx] = .{ .asset = try allocator.dupe(u8, asset_ref), .bones = bones };
        skeleton_count += 1;
    }
    return skeletons;
}

const ParseOptions = struct {
    generate_missing_uvs: bool = false,
    atlas_options: uv_atlas.AtlasOptions = .{},
};

fn parseGltfMesh(allocator: std.mem.Allocator, bytes: []const u8, options: ParseOptions) !geometry.Mesh {
    const aligned = try copyAligned(allocator, bytes);
    defer allocator.free(aligned);

    var gltf = zgltf.Gltf.init(allocator);
    defer gltf.deinit();

    try gltf.parse(aligned);

    if (gltf.data.meshes.len == 0) return error.MissingGltfMesh;

    const mesh_index: usize = 0;
    const primitive = gltf.data.meshes[mesh_index].primitives[0];
    if (primitive.mode != .triangles) return error.UnsupportedPrimitiveMode;

    const binary = gltf.glb_binary orelse return error.MissingGlbBinary;

    var position_accessor_index: ?usize = null;
    var normal_accessor_index: ?usize = null;
    var texcoord_accessor_index: ?usize = null;
    var joints_accessor_index: ?usize = null;
    var weights_accessor_index: ?usize = null;

    for (primitive.attributes) |attribute| {
        switch (attribute) {
            .position => |index| position_accessor_index = index,
            .normal => |index| normal_accessor_index = index,
            .texcoord => |index| {
                if (texcoord_accessor_index == null) texcoord_accessor_index = index;
            },
            .joints => |index| {
                if (joints_accessor_index == null) joints_accessor_index = index;
            },
            .weights => |index| {
                if (weights_accessor_index == null) weights_accessor_index = index;
            },
            else => {},
        }
    }

    const position_accessor_index_value = position_accessor_index orelse return error.MissingPositionAttribute;
    const position_accessor = gltf.data.accessors[position_accessor_index_value];
    const vertex_count = position_accessor.count;

    var vertices = try allocator.alloc(geometry.Vertex, vertex_count);
    errdefer allocator.free(vertices);

    for (vertices) |*vertex| {
        vertex.normal = .{ .x = 0, .y = 1, .z = 0 };
        vertex.uv = .{ .x = 0, .y = 0 };
    }

    {
        var position_iter = position_accessor.iterator(f32, &gltf, binary);
        var vertex_index: usize = 0;
        while (position_iter.next()) |position| {
            vertices[vertex_index].position = .{
                .x = position[0],
                .y = position[1],
                .z = position[2],
            };
            vertex_index += 1;
        }
    }

    if (normal_accessor_index) |index| {
        const normal_accessor = gltf.data.accessors[index];
        var normal_iter = normal_accessor.iterator(f32, &gltf, binary);
        var vertex_index: usize = 0;
        while (normal_iter.next()) |normal| {
            vertices[vertex_index].normal = .{
                .x = normal[0],
                .y = normal[1],
                .z = normal[2],
            };
            vertex_index += 1;
        }
    }

    const has_texcoords = texcoord_accessor_index != null;
    if (texcoord_accessor_index) |index| {
        const texcoord_accessor = gltf.data.accessors[index];
        var texcoord_iter = texcoord_accessor.iterator(f32, &gltf, binary);
        var vertex_index: usize = 0;
        while (texcoord_iter.next()) |uv| {
            vertices[vertex_index].uv = .{ .x = uv[0], .y = uv[1] };
            vertex_index += 1;
        }
    } else if (!options.generate_missing_uvs) {
        return error.MissingTexcoordAttribute;
    }

    const indices = if (primitive.indices) |index_accessor|
        try readIndices(allocator, &gltf, binary, index_accessor)
    else blk: {
        var generated = try allocator.alloc(u32, vertex_count);
        for (0..vertex_count) |i| generated[i] = @intCast(i);
        break :blk generated;
    };

    const skin = if (joints_accessor_index != null and weights_accessor_index != null) blk: {
        const skin_index = findSkinForMesh(&gltf, mesh_index) orelse return error.MissingGltfSkin;
        const gltf_skin = gltf.data.skins[skin_index];
        const influences = try readSkinInfluences(
            allocator,
            &gltf,
            binary,
            joints_accessor_index.?,
            weights_accessor_index.?,
            vertex_count,
        );
        errdefer allocator.free(influences);
        const inverse_bind = try readInverseBindMatrices(allocator, &gltf, binary, gltf_skin);
        errdefer allocator.free(inverse_bind);
        const bind_vertices = try allocator.dupe(geometry.Vertex, vertices);
        errdefer allocator.free(bind_vertices);
        break :blk geometry.Skin{
            .bind_vertices = bind_vertices,
            .influences = influences,
            .inverse_bind = inverse_bind,
        };
    } else null;

    var mesh = geometry.Mesh{ .vertices = vertices, .indices = indices, .skin = skin };
    if (has_texcoords) return mesh;
    if (mesh.isSkinned()) return mesh;

    const generated = uv_atlas.generatePaintAtlas(allocator, &mesh, options.atlas_options) catch |err| {
        mesh.deinit(allocator);
        return err;
    };
    mesh.deinit(allocator);
    return generated.mesh;
}

fn readSkinInfluences(
    allocator: std.mem.Allocator,
    gltf: *const zgltf.Gltf,
    binary: []align(4) const u8,
    joints_accessor_index: usize,
    weights_accessor_index: usize,
    vertex_count: usize,
) ![]geometry.SkinInfluence {
    const influences = try allocator.alloc(geometry.SkinInfluence, vertex_count);
    errdefer allocator.free(influences);

    const joints_accessor = gltf.data.accessors[joints_accessor_index];
    const weights_accessor = gltf.data.accessors[weights_accessor_index];
    if (joints_accessor.count != vertex_count or weights_accessor.count != vertex_count) return error.InvalidSkinAttributeCount;

    var joint_index: usize = 0;
    switch (joints_accessor.component_type) {
        .unsigned_byte => {
            var joint_iter = joints_accessor.iterator(u8, gltf, binary);
            while (joint_iter.next()) |joints| : (joint_index += 1) {
                for (0..4) |slot| influences[joint_index].joints[slot] = joints[slot];
            }
        },
        .unsigned_short => {
            var joint_iter = joints_accessor.iterator(u16, gltf, binary);
            while (joint_iter.next()) |joints| : (joint_index += 1) {
                for (0..4) |slot| influences[joint_index].joints[slot] = @intCast(joints[slot]);
            }
        },
        else => return error.UnsupportedJointComponentType,
    }

    var weight_iter = weights_accessor.iterator(f32, gltf, binary);
    var weight_index: usize = 0;
    while (weight_iter.next()) |weights| : (weight_index += 1) {
        for (0..4) |slot| influences[weight_index].weights[slot] = weights[slot];
    }

    return influences;
}

fn readInverseBindMatrices(
    allocator: std.mem.Allocator,
    gltf: *const zgltf.Gltf,
    binary: []align(4) const u8,
    skin: zgltf.Gltf.Skin,
) ![]editor_math.Mat4 {
    const accessor_index = skin.inverse_bind_matrices orelse return error.MissingInverseBindMatrices;
    const accessor = gltf.data.accessors[accessor_index];
    const matrices = try allocator.alloc(editor_math.Mat4, accessor.count);
    errdefer allocator.free(matrices);

    var iter = accessor.iterator(f32, gltf, binary);
    var index: usize = 0;
    while (iter.next()) |values| : (index += 1) {
        if (values.len != 16) return error.InvalidInverseBindMatrix;
        @memcpy(matrices[index].m[0..16], values[0..16]);
    }
    return matrices;
}

fn findSkinForMesh(gltf: *const zgltf.Gltf, mesh_index: usize) ?usize {
    for (gltf.data.nodes) |node| {
        if (node.mesh == mesh_index) return node.skin;
    }
    return null;
}

fn nodeTransform(node: zgltf.Gltf.Node) scene_animation.Transform {
    if (node.matrix) |matrix| {
        return matrixToTransform(matrix);
    }
    return .{
        .position = .{ .x = node.translation[0], .y = node.translation[1], .z = node.translation[2] },
        .rotation = quaternionToEuler(.{
            .x = node.rotation[0],
            .y = node.rotation[1],
            .z = node.rotation[2],
            .w = node.rotation[3],
        }),
        .scale = .{ .x = node.scale[0], .y = node.scale[1], .z = node.scale[2] },
    };
}

fn matrixToTransform(matrix: [16]f32) scene_animation.Transform {
    const position = editor_math.Vec3{
        .x = matrix[12],
        .y = matrix[13],
        .z = matrix[14],
    };
    const scale = editor_math.Vec3{
        .x = @sqrt(matrix[0] * matrix[0] + matrix[1] * matrix[1] + matrix[2] * matrix[2]),
        .y = @sqrt(matrix[4] * matrix[4] + matrix[5] * matrix[5] + matrix[6] * matrix[6]),
        .z = @sqrt(matrix[8] * matrix[8] + matrix[9] * matrix[9] + matrix[10] * matrix[10]),
    };
    const inv_scale_x = if (scale.x > 0.0001) 1.0 / scale.x else 0;
    const inv_scale_y = if (scale.y > 0.0001) 1.0 / scale.y else 0;
    const inv_scale_z = if (scale.z > 0.0001) 1.0 / scale.z else 0;
    const m00 = matrix[0] * inv_scale_x;
    const m10 = matrix[1] * inv_scale_x;
    const m20 = matrix[2] * inv_scale_x;
    const m21 = matrix[6] * inv_scale_y;
    const m22 = matrix[10] * inv_scale_z;
    const pitch = std.math.asin(std.math.clamp(-m20, -1, 1));
    const yaw = std.math.atan2(m10, m00);
    const roll = std.math.atan2(m21, m22);
    return .{
        .position = position,
        .rotation = .{ .x = pitch, .y = yaw, .z = roll },
        .scale = scale,
    };
}

const Quat = struct { x: f32, y: f32, z: f32, w: f32 };

fn quaternionToEuler(q: Quat) editor_math.Vec3 {
    const sinr_cosp = 2 * (q.w * q.x + q.y * q.z);
    const cosr_cosp = 1 - 2 * (q.x * q.x + q.y * q.y);
    const roll = std.math.atan2(sinr_cosp, cosr_cosp);

    const sinp = 2 * (q.w * q.y - q.z * q.x);
    const half_pi: f32 = std.math.pi / 2.0;
    const pitch = if (@abs(sinp) >= 1)
        if (sinp >= 0) half_pi else -half_pi
    else
        std.math.asin(sinp);

    const siny_cosp = 2 * (q.w * q.z + q.x * q.y);
    const cosy_cosp = 1 - 2 * (q.y * q.y + q.z * q.z);
    const yaw = std.math.atan2(siny_cosp, cosy_cosp);

    return .{ .x = pitch, .y = yaw, .z = roll };
}

fn readIndices(
    allocator: std.mem.Allocator,
    gltf: *const zgltf.Gltf,
    binary: []align(4) const u8,
    accessor_index: usize,
) ![]u32 {
    const accessor = gltf.data.accessors[accessor_index];
    const indices = try allocator.alloc(u32, accessor.count);
    errdefer allocator.free(indices);

    switch (accessor.component_type) {
        .unsigned_short => {
            var iter = accessor.iterator(u16, gltf, binary);
            var index: usize = 0;
            while (iter.next()) |value| {
                indices[index] = value[0];
                index += 1;
            }
        },
        .unsigned_integer => {
            var iter = accessor.iterator(u32, gltf, binary);
            var index: usize = 0;
            while (iter.next()) |value| {
                indices[index] = value[0];
                index += 1;
            }
        },
        else => return error.UnsupportedIndexComponentType,
    }

    return indices;
}

fn copyAligned(allocator: std.mem.Allocator, bytes: []const u8) ![]align(4) const u8 {
    const aligned = try allocator.alignedAlloc(u8, .@"4", bytes.len);
    @memcpy(aligned, bytes);
    return aligned;
}

fn parentJointIndex(joints: []const usize, parent_node: ?usize) ?u32 {
    const parent = parent_node orelse return null;
    for (joints, 0..) |joint, idx| {
        if (joint == parent) return @intCast(idx);
    }
    return null;
}

test "glb import encodes mesh binary" {
    const glb = std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "assets/source/meshes/box.glb",
        std.testing.allocator,
        .limited(8 * 1024 * 1024),
    ) catch return;
    defer std.testing.allocator.free(glb);

    const encoded = try importGlb(std.testing.allocator, glb);
    defer std.testing.allocator.free(encoded);
    try std.testing.expect(std.mem.eql(u8, encoded[0..4], &mesh_codec.magic));
}

test "glb skeleton extraction reports empty skeleton list for static mesh" {
    const glb = std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "assets/source/meshes/box.glb",
        std.testing.allocator,
        .limited(8 * 1024 * 1024),
    ) catch return;
    defer std.testing.allocator.free(glb);

    const skeletons = try extractSkeletons(std.testing.allocator, glb, "assets/source/meshes/box.glb");
    defer std.testing.allocator.free(skeletons);
    try std.testing.expectEqual(@as(usize, 0), skeletons.len);
}

test "glb skin import preserves bind data" {
    const glb_path = "assets/source/meshes/rigged_simple.glb";
    const glb = std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        glb_path,
        std.testing.allocator,
        .limited(8 * 1024 * 1024),
    ) catch return;
    defer std.testing.allocator.free(glb);

    var mesh = try parseGltfMesh(std.testing.allocator, glb, .{});
    defer mesh.deinit(std.testing.allocator);

    try std.testing.expect(mesh.skin != null);
    try std.testing.expect(mesh.skin.?.inverse_bind.len > 0);
    try std.testing.expectEqual(mesh.vertices.len, mesh.skin.?.influences.len);
}
