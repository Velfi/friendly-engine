const std = @import("std");
const shared = @import("runtime_shared");
const editor_math = shared.editor_math;
const geometry = shared.geometry;
const scene_physics = shared.scene_physics;
const scene_blockout = shared.scene_blockout;
const scene_texture = shared.scene_texture;
const scene_surface = shared.scene_surface;
const scene_gameplay = shared.scene_gameplay;
const scene_marker = shared.scene_marker;
const scene_animation = shared.scene_animation;
const shared_color = shared.color;

pub const TextureSize: u32 = 128;

pub const PaintAtlasStatus = enum {
    missing,
    valid,
    stale,
};

pub const SceneObject = struct {
    id: u64,
    name: []u8,
    mesh: geometry.Mesh,
    position: editor_math.Vec3,
    rotation: editor_math.Vec3 = .{ .x = 0, .y = 0, .z = 0 },
    scale: editor_math.Vec3,
    texture: []u8,
    base_color: shared_color.Color,
    primitive_kind: ?geometry.PrimitiveKind = null,
    object_kind: shared.scene_document.ObjectKind = .mesh,
    enabled: bool = true,
    renderer_visible: bool = true,
    locked: bool = false,
    cast_shadows: bool = true,
    receive_shadows: bool = true,
    components: []const []u8 = &.{},
    properties: []shared.scene_document.Property = &.{},
    physics: ?scene_physics.Body = null,
    blockout_intent: ?scene_blockout.Intent = null,
    texture_transform: scene_texture.Transform = .{},
    face_materials: []scene_texture.FaceMaterial = &.{},
    face_surfaces: []scene_surface.FaceSurface = &.{},
    gameplay: ?scene_gameplay.Component = null,
    marker: ?scene_marker.Marker = null,
    material_path: ?[]u8 = null,
    material_error: ?[]u8 = null,
    lightmap_path: ?[]u8 = null,
    skeleton_asset: ?[]u8 = null,
    bone_pose: []scene_animation.Transform = &.{},
    parent_id: ?u64 = null,
    layer: []u8 = "",
    variant: ?[]u8 = null,
    prop_asset_id: ?[]u8 = null,
    editor_only: bool = false,
    paint_atlas_status: PaintAtlasStatus = .stale,
    paint_atlas_size: u32 = 0,
    paint_atlas_padding_px: u32 = 0,
    paint_atlas_report: shared.uv_atlas.UvReport = .{},
    paint_atlas_generator: []const u8 = "",

    pub fn deinit(self: *SceneObject, allocator: std.mem.Allocator) void {
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
        if (self.material_path) |path| allocator.free(path);
        if (self.material_error) |err| allocator.free(err);
        if (self.lightmap_path) |path| allocator.free(path);
        if (self.skeleton_asset) |asset| allocator.free(asset);
        allocator.free(self.bone_pose);
        if (self.layer.len > 0) allocator.free(self.layer);
        if (self.variant) |variant| allocator.free(variant);
        if (self.prop_asset_id) |asset_id| allocator.free(asset_id);
    }

    pub fn transform(self: *const SceneObject) editor_math.Mat4 {
        return editor_math.Mat4.mul(
            editor_math.Mat4.translation(self.position),
            editor_math.Mat4.mul(editor_math.Mat4.rotationEuler(self.rotation), editor_math.Mat4.scale(self.scale)),
        );
    }

    pub fn worldTransform(self: *const SceneObject, objects: []const SceneObject) editor_math.Mat4 {
        const idx = @import("editor_scene_hierarchy.zig").objectIndexById(objects, self.id) orelse return self.transform();
        return @import("editor_scene_hierarchy.zig").objectWorldTransform(objects, idx);
    }
    pub fn propertyValue(self: *const SceneObject, key: []const u8) ?[]const u8 {
        for (self.properties) |property| {
            if (std.mem.eql(u8, property.key, key)) return property.value;
        }
        return null;
    }

    pub fn isImmutable(self: *const SceneObject) bool {
        if (self.propertyValue("mutability")) |value| {
            if (std.mem.eql(u8, value, "immutable")) return true;
        }
        return false;
    }

    pub fn isProjectAnchor(self: *const SceneObject) bool {
        const role = self.propertyValue("role") orelse return false;
        return std.mem.eql(u8, role, "project_anchor");
    }

    pub fn canModifyObject(self: *const SceneObject) bool {
        return !self.isImmutable() and !self.locked;
    }

    pub fn enforceImmutableInvariants(self: *SceneObject) void {
        if (!self.isImmutable()) return;
        self.locked = true;
        if (self.isProjectAnchor()) {
            self.position = .{ .x = 0, .y = 0, .z = 0 };
            self.rotation = .{ .x = 0, .y = 0, .z = 0 };
            self.scale = .{ .x = 1, .y = 1, .z = 1 };
            self.parent_id = null;
            self.enabled = true;
        }
    }
};

pub fn fillCheckerTexture(pixels: []u8, size: u32, r: u8, g: u8, b: u8) void {
    const cell: u32 = 16;
    for (0..size) |y| {
        for (0..size) |x| {
            const checker = ((x / cell) + (y / cell)) % 2 == 0;
            const shade: u8 = if (checker) 255 else 220;
            const idx = (y * size + x) * 4;
            pixels[idx] = @intCast((@as(u16, r) * shade) / 255);
            pixels[idx + 1] = @intCast((@as(u16, g) * shade) / 255);
            pixels[idx + 2] = @intCast((@as(u16, b) * shade) / 255);
            pixels[idx + 3] = 255;
        }
    }
}

pub fn paintTextureBrush(pixels: []u8, size: u32, uv: editor_math.Vec2, color: shared_color.Color, radius: f32) void {
    const cx = @as(i32, @intFromFloat(uv.x * @as(f32, @floatFromInt(size))));
    const cy = @as(i32, @intFromFloat(uv.y * @as(f32, @floatFromInt(size))));
    const r = @as(i32, @intFromFloat(radius * @as(f32, @floatFromInt(size))));
    const r2 = r * r;
    var y = cy - r;
    while (y <= cy + r) : (y += 1) {
        if (y < 0 or y >= @as(i32, @intCast(size))) continue;
        var x = cx - r;
        while (x <= cx + r) : (x += 1) {
            if (x < 0 or x >= @as(i32, @intCast(size))) continue;
            const dx = x - cx;
            const dy = y - cy;
            if (dx * dx + dy * dy > r2) continue;
            const idx = (@as(usize, @intCast(y)) * @as(usize, size) + @as(usize, @intCast(x))) * 4;
            pixels[idx] = color.r;
            pixels[idx + 1] = color.g;
            pixels[idx + 2] = color.b;
            pixels[idx + 3] = 255;
        }
    }
}
