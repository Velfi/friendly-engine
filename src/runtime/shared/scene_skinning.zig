const std = @import("std");
const editor_math = @import("editor_math.zig");
const geometry = @import("geometry.zig");
const scene_animation = @import("scene_animation.zig");

pub fn findSkeletonForAsset(skeletons: []const scene_animation.Skeleton, asset: []const u8) ?scene_animation.Skeleton {
    for (skeletons) |skeleton| {
        if (std.mem.eql(u8, skeleton.asset, asset)) return skeleton;
    }
    return null;
}

pub fn restPoseFromSkeleton(allocator: std.mem.Allocator, skeleton: scene_animation.Skeleton) ![]scene_animation.Transform {
    var pose = try allocator.alloc(scene_animation.Transform, skeleton.bones.len);
    for (skeleton.bones, 0..) |bone, idx| pose[idx] = bone.rest;
    return pose;
}

pub fn initBonePoseForAsset(
    allocator: std.mem.Allocator,
    asset: []const u8,
    skeletons: []const scene_animation.Skeleton,
) ![]scene_animation.Transform {
    const skeleton = findSkeletonForAsset(skeletons, asset) orelse return try allocator.dupe(scene_animation.Transform, &.{});
    return restPoseFromSkeleton(allocator, skeleton);
}

pub fn transformToMatrix(transform: scene_animation.Transform) editor_math.Mat4 {
    return editor_math.Mat4.mul(
        editor_math.Mat4.translation(transform.position),
        editor_math.Mat4.mul(editor_math.Mat4.rotationEuler(transform.rotation), editor_math.Mat4.scale(transform.scale)),
    );
}

pub fn computeGlobalTransforms(
    skeleton: scene_animation.Skeleton,
    bone_pose: []const scene_animation.Transform,
    out: []editor_math.Mat4,
) void {
    std.debug.assert(out.len >= skeleton.bones.len);
    for (skeleton.bones, 0..) |bone, idx| {
        const local = if (idx < bone_pose.len)
            transformToMatrix(bone_pose[idx])
        else
            transformToMatrix(bone.rest);
        if (bone.parent) |parent| {
            out[idx] = editor_math.Mat4.mul(out[parent], local);
        } else {
            out[idx] = local;
        }
    }
}

pub fn computeSkinMatrices(
    skeleton: scene_animation.Skeleton,
    bone_pose: []const scene_animation.Transform,
    inverse_bind: []const editor_math.Mat4,
    out: []editor_math.Mat4,
) void {
    std.debug.assert(out.len >= inverse_bind.len);
    var globals: [256]editor_math.Mat4 = undefined;
    const bone_count = @min(skeleton.bones.len, globals.len);
    computeGlobalTransforms(skeleton, bone_pose, globals[0..bone_count]);
    for (0..inverse_bind.len) |idx| {
        out[idx] = editor_math.Mat4.mul(globals[idx], inverse_bind[idx]);
    }
}

pub fn deformMesh(
    mesh: *geometry.Mesh,
    skeleton: scene_animation.Skeleton,
    bone_pose: []const scene_animation.Transform,
) void {
    const skin = mesh.skin orelse return;
    if (skin.influences.len != mesh.vertices.len or skin.bind_vertices.len != mesh.vertices.len) return;

    var skin_matrices: [256]editor_math.Mat4 = undefined;
    const bone_count = @min(skin.inverse_bind.len, skin_matrices.len);
    computeSkinMatrices(skeleton, bone_pose, skin.inverse_bind[0..bone_count], skin_matrices[0..bone_count]);

    for (skin.bind_vertices, skin.influences, mesh.vertices) |bind, influence, *out| {
        var position = editor_math.Vec3{ .x = 0, .y = 0, .z = 0 };
        var normal = editor_math.Vec3{ .x = 0, .y = 0, .z = 0 };
        for (0..4) |slot| {
            const weight = influence.weights[slot];
            if (weight <= 0) continue;
            const joint = influence.joints[slot];
            if (joint >= bone_count) continue;
            const matrix = skin_matrices[joint];
            position = editor_math.Vec3.add(position, editor_math.Vec3.scale(matrix.transformPoint(bind.position), weight));
            normal = editor_math.Vec3.add(normal, editor_math.Vec3.scale(matrix.transformDir(bind.normal), weight));
        }
        out.position = position;
        out.normal = editor_math.Vec3.normalized(normal);
        out.uv = bind.uv;
    }
}

test "rest pose skinning preserves bind vertices" {
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

    var skeleton = scene_animation.Skeleton{
        .asset = try std.testing.allocator.dupe(u8, "actor.glb"),
        .bones = try std.testing.allocator.dupe(scene_animation.Bone, &.{
            .{
                .index = 0,
                .parent = null,
                .name = try std.testing.allocator.dupe(u8, "Root"),
                .rest = .{},
            },
        }),
    };
    defer skeleton.deinit(std.testing.allocator);
    const pose = [_]scene_animation.Transform{.{}};

    deformMesh(&mesh, skeleton, &pose);
    try std.testing.expectApproxEqAbs(@as(f32, 0), mesh.vertices[0].position.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1), mesh.vertices[0].position.y, 0.001);
}
