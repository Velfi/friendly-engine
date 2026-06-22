const std = @import("std");
const geometry = @import("geometry.zig");
const scene_physics = @import("scene_physics.zig");
const scene_blockout = @import("scene_blockout.zig");
const scene_texture = @import("scene_texture.zig");
const scene_surface = @import("scene_surface.zig");
const scene_gameplay = @import("scene_gameplay.zig");
const scene_marker = @import("scene_marker.zig");
const scene_animation = @import("scene_animation.zig");

pub const ObjectKind = enum {
    mesh,
    empty,
    light,
    camera,
    trigger,
    audio,
    prefab,
    marker,

    pub fn label(self: ObjectKind) []const u8 {
        return switch (self) {
            .mesh => "Mesh",
            .empty => "Empty",
            .light => "Light",
            .camera => "Camera",
            .trigger => "Trigger",
            .audio => "Audio",
            .prefab => "Prefab",
            .marker => "Marker",
        };
    }
};

pub const EntityMesh = union(enum) {
    primitive: struct {
        kind: geometry.PrimitiveKind,
        params: geometry.PrimitiveParams,
    },
    asset: []const u8,
};

pub const Property = struct {
    key: []u8,
    value: []u8,

    pub fn deinit(self: *Property, allocator: std.mem.Allocator) void {
        allocator.free(self.key);
        allocator.free(self.value);
    }

    pub fn duplicate(allocator: std.mem.Allocator, property: Property) !Property {
        return .{
            .key = try allocator.dupe(u8, property.key),
            .value = try allocator.dupe(u8, property.value),
        };
    }
};

pub const SceneEntity = struct {
    id: u64,
    name: []u8,
    position: [3]f32,
    rotation: [3]f32 = .{ 0, 0, 0 },
    scale: [3]f32,
    base_color: [4]u8,
    texture_file: []u8,
    mesh: EntityMesh,
    object_kind: ObjectKind = .mesh,
    enabled: bool = true,
    renderer_visible: bool = true,
    cast_shadows: bool = true,
    receive_shadows: bool = true,
    components: []const []const u8 = &.{},
    properties: []Property = &.{},
    physics: ?scene_physics.Body = null,
    blockout_intent: ?scene_blockout.Intent = null,
    texture_transform: scene_texture.Transform = .{},
    face_materials: []scene_texture.FaceMaterial = &.{},
    face_surfaces: []scene_surface.FaceSurface = &.{},
    gameplay: ?scene_gameplay.Component = null,
    marker: ?scene_marker.Marker = null,
    lightmap_path: ?[]u8 = null,
    skeleton_asset: ?[]u8 = null,
    parent_id: ?u64 = null,
    layer: []u8 = "",
    variant: ?[]u8 = null,
    prop_asset_id: ?[]u8 = null,

    pub fn deinit(self: *SceneEntity, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.texture_file);
        switch (self.mesh) {
            .asset => |path| allocator.free(path),
            .primitive => {},
        }
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
        if (self.layer.len > 0) allocator.free(self.layer);
        if (self.variant) |variant| allocator.free(variant);
        if (self.prop_asset_id) |asset_id| allocator.free(asset_id);
    }
};

pub const SceneDocument = struct {
    schema_version: u32,
    next_object_id: u64,
    entities: []SceneEntity,
    animations: []scene_animation.Clip = &.{},
    skeletons: []scene_animation.Skeleton = &.{},

    pub fn deinit(self: *SceneDocument, allocator: std.mem.Allocator) void {
        for (self.entities) |*entity| entity.deinit(allocator);
        allocator.free(self.entities);
        for (self.animations) |*clip| clip.deinit(allocator);
        allocator.free(self.animations);
        for (self.skeletons) |*skeleton| skeleton.deinit(allocator);
        allocator.free(self.skeletons);
    }
};

pub fn primitiveKindFromName(name: []const u8) ?geometry.PrimitiveKind {
    if (std.mem.eql(u8, name, "box")) return .box;
    if (std.mem.eql(u8, name, "plane")) return .plane;
    if (std.mem.eql(u8, name, "cylinder")) return .cylinder;
    if (std.mem.eql(u8, name, "sphere")) return .sphere;
    return null;
}

pub fn primitiveKindName(kind: geometry.PrimitiveKind) []const u8 {
    return switch (kind) {
        .box => "box",
        .plane => "plane",
        .cylinder => "cylinder",
        .sphere => "sphere",
    };
}

pub fn objectKindFromName(name: []const u8) ?ObjectKind {
    if (std.mem.eql(u8, name, "mesh")) return .mesh;
    if (std.mem.eql(u8, name, "empty")) return .empty;
    if (std.mem.eql(u8, name, "light")) return .light;
    if (std.mem.eql(u8, name, "camera")) return .camera;
    if (std.mem.eql(u8, name, "trigger")) return .trigger;
    if (std.mem.eql(u8, name, "audio")) return .audio;
    if (std.mem.eql(u8, name, "prefab")) return .prefab;
    if (std.mem.eql(u8, name, "marker")) return .marker;
    return null;
}

pub fn objectKindName(kind: ObjectKind) []const u8 {
    return switch (kind) {
        .mesh => "mesh",
        .empty => "empty",
        .light => "light",
        .camera => "camera",
        .trigger => "trigger",
        .audio => "audio",
        .prefab => "prefab",
        .marker => "marker",
    };
}
