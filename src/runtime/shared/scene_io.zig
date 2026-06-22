const std = @import("std");
const friendly_engine = @import("friendly_engine");
const geometry = @import("geometry.zig");
const editor_math = @import("editor_math.zig");
const shared_color = @import("color.zig");
const scene_binary = @import("scene_binary.zig");
const scene_document = @import("scene_document.zig");
const scene_animation = @import("scene_animation.zig");
const scene_kdl = @import("scene_kdl.zig");
const scene_physics = @import("scene_physics.zig");
const scene_blockout = @import("scene_blockout.zig");
const scene_texture = @import("scene_texture.zig");
const scene_surface = @import("scene_surface.zig");
const scene_gameplay = @import("scene_gameplay.zig");
const scene_marker = @import("scene_marker.zig");
const scene_resolve = @import("scene_resolve.zig");
const prop_asset_doc = @import("prop_asset_doc.zig");
const mesh_codec = @import("mesh_codec.zig");

const bundle_loader = friendly_engine.framework.bundle_loader;

pub const SceneObjectData = struct {
    id: u64,
    name: []u8,
    mesh: geometry.Mesh,
    position: editor_math.Vec3,
    rotation: editor_math.Vec3 = .{ .x = 0, .y = 0, .z = 0 },
    scale: editor_math.Vec3,
    texture: []u8,
    base_color: shared_color.Color,
    primitive_kind: ?geometry.PrimitiveKind = null,
    object_kind: scene_document.ObjectKind = .mesh,
    enabled: bool = true,
    renderer_visible: bool = true,
    cast_shadows: bool = true,
    receive_shadows: bool = true,
    components: []const []u8 = &.{},
    properties: []scene_document.Property = &.{},
    physics: ?scene_physics.Body = null,
    blockout_intent: ?scene_blockout.Intent = null,
    texture_transform: scene_texture.Transform = .{},
    face_materials: []scene_texture.FaceMaterial = &.{},
    face_surfaces: []scene_surface.FaceSurface = &.{},
    gameplay: ?scene_gameplay.Component = null,
    marker: ?scene_marker.Marker = null,
    lightmap_path: ?[]u8 = null,
    skeleton_asset: ?[]u8 = null,
    bone_pose: []scene_animation.Transform = &.{},
    parent_id: ?u64 = null,
    layer: []u8 = "",
    variant: ?[]u8 = null,
    prop_asset_id: ?[]u8 = null,

    pub fn deinit(self: *SceneObjectData, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        self.mesh.deinit(allocator);
        allocator.free(self.texture);
        for (self.components) |component| allocator.free(component);
        allocator.free(self.components);
        for (self.properties) |*property| property.deinit(allocator);
        allocator.free(self.properties);
        if (self.blockout_intent) |*intent| intent.deinit(allocator);
        for (self.face_materials) |*face| face.deinit(allocator);
        allocator.free(self.face_materials);
        allocator.free(self.face_surfaces);
        if (self.gameplay) |*gameplay| gameplay.deinit(allocator);
        if (self.marker) |*marker| marker.deinit(allocator);
        if (self.lightmap_path) |path| allocator.free(path);
        if (self.skeleton_asset) |asset| allocator.free(asset);
        allocator.free(self.bone_pose);
        if (self.layer.len > 0) allocator.free(self.layer);
        if (self.variant) |variant| allocator.free(variant);
        if (self.prop_asset_id) |asset_id| allocator.free(asset_id);
    }
};

pub const LoadedScene = struct {
    objects: []SceneObjectData,
    next_object_id: u64,
    animations: []scene_animation.Clip = &.{},
    skeletons: []scene_animation.Skeleton = &.{},

    pub fn deinit(self: *LoadedScene, allocator: std.mem.Allocator) void {
        for (self.objects) |*obj| obj.deinit(allocator);
        allocator.free(self.objects);
        for (self.animations) |*clip| clip.deinit(allocator);
        allocator.free(self.animations);
        for (self.skeletons) |*skeleton| skeleton.deinit(allocator);
        allocator.free(self.skeletons);
    }
};

pub const default_scene_path = "scenes/main.kdl";

pub fn bakedScenePath(allocator: std.mem.Allocator, target: []const u8, scene_rel_path: []const u8) ![]u8 {
    const basename = std.fs.path.stem(scene_rel_path);
    return std.fmt.allocPrint(allocator, "assets/cache/{s}/scenes/{s}.fscene", .{ target, basename });
}

fn openProjectDir(io: std.Io, project_path: []const u8) !std.Io.Dir {
    if (std.fs.path.isAbsolute(project_path)) {
        return try std.Io.Dir.openDirAbsolute(io, project_path, .{});
    }
    return try std.Io.Dir.cwd().openDir(io, project_path, .{});
}

pub fn loadScene(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    scene_rel_path: []const u8,
    bundle: ?*const bundle_loader.RuntimeBundle,
) !LoadedScene {
    return loadKdlScene(allocator, io, project_path, scene_rel_path, bundle);
}

fn loadBakedScene(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    baked_rel_path: []const u8,
) !LoadedScene {
    var project_dir = try openProjectDir(io, project_path);
    defer project_dir.close(io);

    const bytes = try project_dir.readFileAlloc(io, baked_rel_path, allocator, .limited(64 * 1024 * 1024));
    defer allocator.free(bytes);
    return scene_binary.decodeScene(allocator, bytes);
}

fn loadKdlScene(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    scene_rel_path: []const u8,
    bundle: ?*const bundle_loader.RuntimeBundle,
) !LoadedScene {
    var project_dir = try openProjectDir(io, project_path);
    defer project_dir.close(io);

    const scene_dir_part = std.fs.path.dirname(scene_rel_path) orelse return error.InvalidScenePath;
    const scene_file_part = std.fs.path.basename(scene_rel_path);

    var scenes_dir = try project_dir.openDir(io, scene_dir_part, .{});
    defer scenes_dir.close(io);

    const bytes = try scenes_dir.readFileAlloc(io, scene_file_part, allocator, .limited(16 * 1024 * 1024));
    defer allocator.free(bytes);

    var document = try scene_kdl.parseSceneDocument(allocator, bytes);
    defer document.deinit(allocator);

    const target = if (bundle) |runtime_bundle| runtime_bundle.target else "client-debug";
    const resolver = scene_resolve.AssetResolver{
        .io = io,
        .project_dir = project_dir,
        .cache_target = target,
    };

    var loaded = try scene_resolve.resolveDocument(allocator, document, resolver);
    errdefer loaded.deinit(allocator);

    if (bundle) |runtime_bundle| {
        try applyBundleTextures(allocator, io, project_path, document.entities, loaded.objects, runtime_bundle);
    }

    return loaded;
}

fn applyBundleTextures(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    entities: []const scene_document.SceneEntity,
    objects: []SceneObjectData,
    bundle: *const bundle_loader.RuntimeBundle,
) !void {
    for (entities, objects) |entity, *object| {
        if (try bundle.readBytesForRef(io, project_path, entity.texture_file, allocator)) |tex_bytes| {
            if (tex_bytes.len != scene_binary.texture_pixel_bytes) {
                allocator.free(tex_bytes);
                return error.InvalidTextureSize;
            }
            allocator.free(object.texture);
            object.texture = tex_bytes;
        } else {
            return error.MissingBundledTexture;
        }
    }
}

pub fn saveScene(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    scene_rel_path: []const u8,
    objects: []const SceneObjectData,
    next_object_id: u64,
    animations: []const scene_animation.Clip,
    skeletons: []const scene_animation.Skeleton,
) !void {
    var document = try sceneDocumentFromObjects(allocator, objects, next_object_id, animations, skeletons);
    defer document.deinit(allocator);

    const kdl_bytes = try scene_kdl.formatScene(allocator, document);
    defer allocator.free(kdl_bytes);

    var project_dir = try openProjectDir(io, project_path);
    defer project_dir.close(io);
    const scene_dir = std.fs.path.dirname(scene_rel_path) orelse return error.InvalidScenePath;
    try project_dir.createDirPath(io, scene_dir);
    const texture_dir = try std.fs.path.join(allocator, &.{ scene_dir, "textures" });
    defer allocator.free(texture_dir);
    const mesh_dir = try std.fs.path.join(allocator, &.{ scene_dir, "meshes" });
    defer allocator.free(mesh_dir);
    try project_dir.createDirPath(io, texture_dir);
    try project_dir.createDirPath(io, mesh_dir);
    for (objects) |object| {
        const texture_path = try std.fmt.allocPrint(allocator, "{s}/textures/{d}.rgba", .{ scene_dir, object.id });
        defer allocator.free(texture_path);
        try project_dir.writeFile(io, .{ .sub_path = texture_path, .data = object.texture });
        if (object.prop_asset_id) |asset_id| {
            const prop_mesh_path = try prop_asset_doc.meshPath(allocator, asset_id);
            defer allocator.free(prop_mesh_path);
            try project_dir.access(io, prop_mesh_path, .{});
        } else if (object.primitive_kind == null) {
            const mesh_path = try std.fmt.allocPrint(allocator, "{s}/meshes/{d}.fmesh", .{ scene_dir, object.id });
            defer allocator.free(mesh_path);
            const mesh_bytes = try mesh_codec.encodeMesh(allocator, object.mesh);
            defer allocator.free(mesh_bytes);
            try project_dir.writeFile(io, .{ .sub_path = mesh_path, .data = mesh_bytes });
        }
    }
    try project_dir.writeFile(io, .{ .sub_path = scene_rel_path, .data = kdl_bytes });
}

fn sceneDocumentFromObjects(
    allocator: std.mem.Allocator,
    objects: []const SceneObjectData,
    next_object_id: u64,
    animations: []const scene_animation.Clip,
    skeletons: []const scene_animation.Skeleton,
) !scene_document.SceneDocument {
    var entities = try allocator.alloc(scene_document.SceneEntity, objects.len);
    errdefer {
        for (entities) |*entity| entity.deinit(allocator);
        allocator.free(entities);
    }

    for (objects, 0..) |object, index| {
        const mesh: scene_document.EntityMesh = if (object.prop_asset_id) |asset_id|
            .{ .asset = try prop_asset_doc.meshPath(allocator, asset_id) }
        else if (object.primitive_kind) |kind|
            .{ .primitive = .{ .kind = kind, .params = .{} } }
        else
            .{ .asset = try std.fmt.allocPrint(allocator, "meshes/{d}.fmesh", .{object.id}) };

        const texture_file = try std.fmt.allocPrint(allocator, "textures/{d}.rgba", .{object.id});

        entities[index] = .{
            .id = object.id,
            .name = try allocator.dupe(u8, object.name),
            .position = .{ object.position.x, object.position.y, object.position.z },
            .rotation = .{ object.rotation.x, object.rotation.y, object.rotation.z },
            .scale = .{ object.scale.x, object.scale.y, object.scale.z },
            .base_color = .{ object.base_color.r, object.base_color.g, object.base_color.b, object.base_color.a },
            .texture_file = texture_file,
            .mesh = mesh,
            .object_kind = object.object_kind,
            .enabled = object.enabled,
            .renderer_visible = object.renderer_visible,
            .cast_shadows = object.cast_shadows,
            .receive_shadows = object.receive_shadows,
            .components = try duplicateComponents(allocator, object.components),
            .properties = try duplicateProperties(allocator, object.properties),
            .physics = object.physics,
            .blockout_intent = if (object.blockout_intent) |intent| try scene_blockout.Intent.duplicate(allocator, intent) else null,
            .texture_transform = object.texture_transform,
            .face_materials = try duplicateFaceMaterials(allocator, object.face_materials),
            .face_surfaces = try duplicateFaceSurfaces(allocator, object.face_surfaces),
            .gameplay = if (object.gameplay) |gameplay| try scene_gameplay.Component.duplicate(allocator, gameplay) else null,
            .marker = if (object.marker) |marker| try scene_marker.Marker.duplicate(allocator, marker) else null,
            .lightmap_path = if (object.lightmap_path) |path| try allocator.dupe(u8, path) else null,
            .skeleton_asset = if (object.skeleton_asset) |asset| try allocator.dupe(u8, asset) else null,
            .parent_id = object.parent_id,
            .layer = if (object.layer.len > 0) try allocator.dupe(u8, object.layer) else "",
            .variant = if (object.variant) |variant| try allocator.dupe(u8, variant) else null,
            .prop_asset_id = if (object.prop_asset_id) |asset_id| try allocator.dupe(u8, asset_id) else null,
        };
    }

    return .{
        .schema_version = 1,
        .next_object_id = next_object_id,
        .entities = entities,
        .animations = try scene_animation.duplicateClips(allocator, animations),
        .skeletons = try scene_animation.duplicateSkeletons(allocator, skeletons),
    };
}

pub fn duplicateComponents(allocator: std.mem.Allocator, components: []const []const u8) ![]const []u8 {
    var copy = try allocator.alloc([]u8, components.len);
    var copied_count: usize = 0;
    errdefer {
        for (copy[0..copied_count]) |item| allocator.free(item);
        allocator.free(copy);
    }
    for (components, 0..) |component, idx| {
        copy[idx] = try allocator.dupe(u8, component);
        copied_count += 1;
    }
    return copy;
}

pub fn duplicateProperties(allocator: std.mem.Allocator, properties: []const scene_document.Property) ![]scene_document.Property {
    var copy = try allocator.alloc(scene_document.Property, properties.len);
    var copied_count: usize = 0;
    errdefer {
        for (copy[0..copied_count]) |*property| property.deinit(allocator);
        allocator.free(copy);
    }
    for (properties, 0..) |property, idx| {
        copy[idx] = try scene_document.Property.duplicate(allocator, property);
        copied_count += 1;
    }
    return copy;
}

pub fn duplicateFaceSurfaces(allocator: std.mem.Allocator, faces: []const scene_surface.FaceSurface) ![]scene_surface.FaceSurface {
    var copy = try allocator.alloc(scene_surface.FaceSurface, faces.len);
    for (faces, 0..) |face, idx| {
        copy[idx] = scene_surface.FaceSurface.duplicate(allocator, face);
    }
    return copy;
}

pub fn duplicateFaceMaterials(allocator: std.mem.Allocator, faces: []const scene_texture.FaceMaterial) ![]scene_texture.FaceMaterial {
    var copy = try allocator.alloc(scene_texture.FaceMaterial, faces.len);
    var copied: usize = 0;
    errdefer {
        for (copy[0..copied]) |*face| face.deinit(allocator);
        allocator.free(copy);
    }
    for (faces, 0..) |face, idx| {
        copy[idx] = try scene_texture.FaceMaterial.duplicate(allocator, face);
        copied += 1;
    }
    return copy;
}

pub fn ensureSampleScene(allocator: std.mem.Allocator, io: std.Io, project_path: []const u8, scene_rel_path: []const u8) !void {
    var project_dir = try openProjectDir(io, project_path);
    defer project_dir.close(io);

    if (project_dir.access(io, scene_rel_path, .{})) |_| return else |_| {}

    const tex_size: usize = scene_binary.texture_pixel_bytes;
    const tex = try allocator.alloc(u8, tex_size);
    defer allocator.free(tex);
    @memset(tex, 140);

    var floor_mesh = try geometry.buildPrimitive(allocator, .plane, .{ .width = 8, .depth = 8 });
    defer floor_mesh.deinit(allocator);
    var box_mesh = try geometry.buildPrimitive(allocator, .box, .{});
    defer box_mesh.deinit(allocator);

    var objects = [_]SceneObjectData{
        .{
            .id = 1,
            .name = try allocator.dupe(u8, "Floor"),
            .mesh = try geometry.duplicateMesh(allocator, &floor_mesh),
            .position = .{ .x = 0, .y = 0, .z = 0 },
            .rotation = .{ .x = 0, .y = 0, .z = 0 },
            .scale = .{ .x = 1, .y = 1, .z = 1 },
            .texture = try allocator.dupe(u8, tex),
            .base_color = .{ .r = 90, .g = 100, .b = 110, .a = 255 },
            .primitive_kind = .plane,
            .physics = .{ .kind = .static },
        },
        .{
            .id = 2,
            .name = try allocator.dupe(u8, "Box"),
            .mesh = try geometry.duplicateMesh(allocator, &box_mesh),
            .position = .{ .x = 0, .y = 0.5, .z = 0 },
            .rotation = .{ .x = 0, .y = 0, .z = 0 },
            .scale = .{ .x = 1, .y = 1, .z = 1 },
            .texture = try allocator.dupe(u8, tex),
            .base_color = .{ .r = 170, .g = 180, .b = 195, .a = 255 },
            .primitive_kind = .box,
            .physics = .{ .kind = .dynamic },
        },
    };
    defer objects[0].deinit(allocator);
    defer objects[1].deinit(allocator);

    try saveScene(allocator, io, project_path, scene_rel_path, &objects, 3, &.{}, &.{});
}

test {
    _ = @import("scene_io_tests.zig");
}
