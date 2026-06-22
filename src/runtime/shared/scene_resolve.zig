const std = @import("std");
const geometry = @import("geometry.zig");
const mesh_codec = @import("mesh_codec.zig");
const scene_document = @import("scene_document.zig");
const scene_io = @import("scene_io.zig");
const scene_binary = @import("scene_binary.zig");
const scene_animation = @import("scene_animation.zig");
const scene_skinning = @import("scene_skinning.zig");
const scene_gameplay = @import("scene_gameplay.zig");
const scene_marker = @import("scene_marker.zig");
const scene_blockout = @import("scene_blockout.zig");

pub const AssetResolver = struct {
    io: std.Io,
    project_dir: std.Io.Dir,
    cache_target: []const u8,

    pub fn readTexture(self: *const AssetResolver, allocator: std.mem.Allocator, ref: []const u8) ![]u8 {
        if (ref.len == 0) return error.MissingTextureAsset;

        const bytes = try self.readAsset(allocator, ref) orelse return error.MissingTextureAsset;
        defer allocator.free(bytes);

        if (bytes.len != scene_binary.texture_pixel_bytes) return error.InvalidTextureSize;
        return try allocator.dupe(u8, bytes);
    }

    pub fn readMesh(self: *const AssetResolver, allocator: std.mem.Allocator, ref: []const u8) !geometry.Mesh {
        const bytes = try self.readAsset(allocator, ref) orelse return error.MissingMeshAsset;
        defer allocator.free(bytes);

        if (bytes.len >= 4 and std.mem.eql(u8, bytes[0..4], &mesh_codec.magic)) {
            return mesh_codec.decodeMesh(allocator, bytes);
        }
        return error.UnsupportedMeshAsset;
    }

    fn readAsset(self: *const AssetResolver, allocator: std.mem.Allocator, ref: []const u8) !?[]u8 {
        const candidates = try buildPathCandidates(allocator, self.cache_target, ref);
        defer freePathCandidates(allocator, candidates);

        for (candidates) |candidate| {
            if (self.project_dir.readFileAlloc(self.io, candidate, allocator, .limited(64 * 1024 * 1024))) |bytes| {
                return bytes;
            } else |err| switch (err) {
                error.FileNotFound => continue,
                else => return err,
            }
        }
        return null;
    }
};

pub fn resolveDocument(
    allocator: std.mem.Allocator,
    document: scene_document.SceneDocument,
    resolver: AssetResolver,
) !scene_io.LoadedScene {
    var objects = std.ArrayList(scene_io.SceneObjectData).empty;
    errdefer {
        for (objects.items) |*obj| obj.deinit(allocator);
        objects.deinit(allocator);
    }

    for (document.entities) |entity| {
        var mesh = try resolveMesh(allocator, entity.mesh, resolver);
        errdefer mesh.deinit(allocator);

        const texture = try resolver.readTexture(allocator, entity.texture_file);
        errdefer allocator.free(texture);

        const primitive_kind: ?geometry.PrimitiveKind = switch (entity.mesh) {
            .primitive => |prim| prim.kind,
            .asset => null,
        };

        const bone_pose = if (entity.skeleton_asset) |asset|
            try scene_skinning.initBonePoseForAsset(allocator, asset, document.skeletons)
        else
            try allocator.dupe(scene_animation.Transform, &.{});
        errdefer allocator.free(bone_pose);

        try objects.append(allocator, .{
            .id = entity.id,
            .name = try allocator.dupe(u8, entity.name),
            .mesh = mesh,
            .position = .{ .x = entity.position[0], .y = entity.position[1], .z = entity.position[2] },
            .rotation = .{ .x = entity.rotation[0], .y = entity.rotation[1], .z = entity.rotation[2] },
            .scale = .{ .x = entity.scale[0], .y = entity.scale[1], .z = entity.scale[2] },
            .texture = texture,
            .base_color = .{
                .r = entity.base_color[0],
                .g = entity.base_color[1],
                .b = entity.base_color[2],
                .a = entity.base_color[3],
            },
            .primitive_kind = primitive_kind,
            .object_kind = entity.object_kind,
            .enabled = entity.enabled,
            .renderer_visible = entity.renderer_visible,
            .cast_shadows = entity.cast_shadows,
            .receive_shadows = entity.receive_shadows,
            .components = try scene_io.duplicateComponents(allocator, entity.components),
            .properties = try scene_io.duplicateProperties(allocator, entity.properties),
            .physics = entity.physics,
            .blockout_intent = if (entity.blockout_intent) |intent| try scene_blockout.Intent.duplicate(allocator, intent) else null,
            .texture_transform = entity.texture_transform,
            .face_materials = try scene_io.duplicateFaceMaterials(allocator, entity.face_materials),
            .face_surfaces = try scene_io.duplicateFaceSurfaces(allocator, entity.face_surfaces),
            .gameplay = if (entity.gameplay) |gameplay| try scene_gameplay.Component.duplicate(allocator, gameplay) else null,
            .marker = if (entity.marker) |marker| try scene_marker.Marker.duplicate(allocator, marker) else null,
            .lightmap_path = if (entity.lightmap_path) |path| try allocator.dupe(u8, path) else null,
            .skeleton_asset = if (entity.skeleton_asset) |asset| try allocator.dupe(u8, asset) else null,
            .bone_pose = bone_pose,
            .parent_id = entity.parent_id,
            .layer = if (entity.layer.len > 0) try allocator.dupe(u8, entity.layer) else "",
            .variant = if (entity.variant) |variant| try allocator.dupe(u8, variant) else null,
            .prop_asset_id = if (entity.prop_asset_id) |asset_id| try allocator.dupe(u8, asset_id) else null,
        });
    }

    return .{
        .objects = try objects.toOwnedSlice(allocator),
        .next_object_id = document.next_object_id,
        .animations = try scene_animation.duplicateClips(allocator, document.animations),
        .skeletons = try scene_animation.duplicateSkeletons(allocator, document.skeletons),
    };
}

fn resolveMesh(allocator: std.mem.Allocator, mesh: scene_document.EntityMesh, resolver: AssetResolver) !geometry.Mesh {
    return switch (mesh) {
        .primitive => |prim| geometry.buildPrimitive(allocator, prim.kind, prim.params),
        .asset => |path| resolver.readMesh(allocator, path),
    };
}

fn buildPathCandidates(allocator: std.mem.Allocator, cache_target: []const u8, ref: []const u8) ![][]const u8 {
    var list = std.ArrayList([]const u8).empty;
    errdefer {
        for (list.items) |item| allocator.free(item);
        list.deinit(allocator);
    }

    const basename = std.fs.path.basename(ref);
    const ext = std.fs.path.extension(basename);
    if (std.ascii.eqlIgnoreCase(ext, ".png")) {
        const stem = basename[0 .. basename.len - ext.len];
        try list.append(allocator, try std.fmt.allocPrint(allocator, "assets/cache/{s}/textures/{s}.rgba", .{ cache_target, stem }));
    } else if (std.ascii.eqlIgnoreCase(ext, ".glb") or std.ascii.eqlIgnoreCase(ext, ".gltf")) {
        const stem = basename[0 .. basename.len - ext.len];
        try list.append(allocator, try std.fmt.allocPrint(allocator, "assets/cache/{s}/meshes/{s}.fmesh", .{ cache_target, stem }));
    }

    if (std.mem.startsWith(u8, ref, "assets/source/")) {
        const rel_ext = std.fs.path.extension(ref);
        if (std.ascii.eqlIgnoreCase(rel_ext, ".png")) {
            const without_ext = ref[0 .. ref.len - rel_ext.len];
            try list.append(allocator, try std.fmt.allocPrint(allocator, "assets/cache/{s}/{s}.rgba", .{ cache_target, without_ext }));
        } else if (std.ascii.eqlIgnoreCase(rel_ext, ".glb") or std.ascii.eqlIgnoreCase(rel_ext, ".gltf")) {
            const without_ext = ref[0 .. ref.len - rel_ext.len];
            try list.append(allocator, try std.fmt.allocPrint(allocator, "assets/cache/{s}/{s}.fmesh", .{ cache_target, without_ext }));
        }
    }

    if (std.mem.startsWith(u8, ref, "textures/")) {
        try list.append(allocator, try std.fmt.allocPrint(allocator, "scenes/{s}", .{ref}));
    }
    if (std.mem.startsWith(u8, ref, "meshes/")) {
        try list.append(allocator, try std.fmt.allocPrint(allocator, "scenes/{s}", .{ref}));
    }

    try list.append(allocator, try allocator.dupe(u8, ref));

    return try list.toOwnedSlice(allocator);
}

fn freePathCandidates(allocator: std.mem.Allocator, candidates: []const []const u8) void {
    for (candidates) |candidate| allocator.free(candidate);
    allocator.free(candidates);
}

pub fn openProjectDir(io: std.Io, project_path: []const u8) !std.Io.Dir {
    if (std.fs.path.isAbsolute(project_path)) {
        return try std.Io.Dir.openDirAbsolute(io, project_path, .{});
    }
    return try std.Io.Dir.cwd().openDir(io, project_path, .{});
}
