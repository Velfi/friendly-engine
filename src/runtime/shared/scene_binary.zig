const std = @import("std");
const geometry = @import("geometry.zig");
const shared_color = @import("color.zig");
const scene_io = @import("scene_io.zig");
const scene_physics = @import("scene_physics.zig");
const scene_surface = @import("scene_surface.zig");
const scene_gameplay = @import("scene_gameplay.zig");
const scene_marker = @import("scene_marker.zig");

pub const magic: [4]u8 = .{ 'F', 'E', 'S', 'C' };
pub const version: u32 = 6;
pub const texture_pixel_bytes: usize = 128 * 128 * 4;

pub fn encodeScene(allocator: std.mem.Allocator, scene: scene_io.LoadedScene) ![]u8 {
    if (scene.animations.len > 0 or scene.skeletons.len > 0) return error.UnsupportedSceneAnimationsInBinary;
    var list = std.ArrayList(u8).empty;
    errdefer list.deinit(allocator);

    try writeHeader(&list, allocator, scene.next_object_id, scene.objects.len);
    for (scene.objects) |object| {
        try writeObject(&list, allocator, object);
    }
    return try list.toOwnedSlice(allocator);
}

pub fn decodeScene(allocator: std.mem.Allocator, bytes: []const u8) !scene_io.LoadedScene {
    if (bytes.len < 16) return error.InvalidSceneFormat;
    if (!std.mem.eql(u8, bytes[0..4], &magic)) return error.InvalidSceneFormat;

    const file_version = std.mem.readInt(u32, bytes[4..8], .little);
    if (file_version != version and file_version != 5 and file_version != 4) return error.UnsupportedSceneVersion;

    const next_object_id = std.mem.readInt(u64, bytes[8..16], .little);
    const object_count = std.mem.readInt(u32, bytes[16..20], .little);

    var offset: usize = 20;
    var objects = try allocator.alloc(scene_io.SceneObjectData, object_count);
    errdefer {
        for (objects) |*obj| obj.deinit(allocator);
        allocator.free(objects);
    }

    for (0..object_count) |index| {
        objects[index] = try readObject(allocator, bytes, &offset, file_version);
    }

    if (offset != bytes.len) return error.InvalidSceneFormat;
    return .{ .objects = objects, .next_object_id = next_object_id };
}

fn writeHeader(list: *std.ArrayList(u8), allocator: std.mem.Allocator, next_object_id: u64, object_count: usize) !void {
    try list.appendSlice(allocator, &magic);
    try appendU32(list, allocator, version);
    try appendU64(list, allocator, next_object_id);
    try appendU32(list, allocator, @intCast(object_count));
}

fn writeObject(list: *std.ArrayList(u8), allocator: std.mem.Allocator, object: scene_io.SceneObjectData) !void {
    try appendU64(list, allocator, object.id);
    try appendString(list, allocator, object.name);

    const primitive_tag: u8 = if (object.primitive_kind) |kind| switch (kind) {
        .box => 1,
        .plane => 2,
        .cylinder => 3,
        .sphere => 4,
    } else 0;
    try list.append(allocator, primitive_tag);
    try list.append(allocator, physicsTag(object.physics));
    try list.append(allocator, objectKindTag(object.object_kind));
    try list.append(allocator, flagsByte(object));
    try appendU32(list, allocator, @intCast(object.components.len));
    for (object.components) |component| {
        try appendString(list, allocator, component);
    }
    if (object.physics) |physics| {
        try list.append(allocator, colliderTag(physics.collider));
        try appendF32(list, allocator, physics.mass);
        try appendF32(list, allocator, physics.friction);
        try appendF32(list, allocator, physics.restitution);
        try list.append(allocator, if (physics.trigger) @as(u8, 1) else 0);
    }

    try appendF32(list, allocator, object.position.x);
    try appendF32(list, allocator, object.position.y);
    try appendF32(list, allocator, object.position.z);
    try appendF32(list, allocator, object.rotation.x);
    try appendF32(list, allocator, object.rotation.y);
    try appendF32(list, allocator, object.rotation.z);
    try appendF32(list, allocator, object.scale.x);
    try appendF32(list, allocator, object.scale.y);
    try appendF32(list, allocator, object.scale.z);
    try list.appendSlice(allocator, &.{ object.base_color.r, object.base_color.g, object.base_color.b, object.base_color.a });

    if (object.texture.len != texture_pixel_bytes) return error.InvalidTextureSize;
    try appendU32(list, allocator, @intCast(object.texture.len));
    try list.appendSlice(allocator, object.texture);

    try appendU32(list, allocator, @intCast(object.mesh.vertices.len));
    try appendU32(list, allocator, @intCast(object.mesh.indices.len));
    try list.appendSlice(allocator, std.mem.sliceAsBytes(object.mesh.vertices));
    try list.appendSlice(allocator, std.mem.sliceAsBytes(object.mesh.indices));

    try appendU64(list, allocator, object.parent_id orelse 0);
    try appendString(list, allocator, object.layer);
    try appendString(list, allocator, object.variant orelse "");
    try appendString(list, allocator, object.prop_asset_id orelse "");
    try appendString(list, allocator, object.lightmap_path orelse "");
    try appendU32(list, allocator, @intCast(object.face_surfaces.len));
    for (object.face_surfaces) |face| {
        try appendU32(list, allocator, @intCast(face.face_index));
        try list.append(allocator, surfaceTypeTag(face.surface_type));
    }
    if (object.gameplay) |gameplay| {
        try list.append(allocator, 1);
        try appendString(list, allocator, gameplay.tag);
        try appendF32(list, allocator, gameplay.health);
        try appendI32(list, allocator, gameplay.score);
        try appendI32(list, allocator, gameplay.team);
        try list.append(allocator, if (gameplay.interactable) @as(u8, 1) else 0);
    } else {
        try list.append(allocator, 0);
    }
    if (object.marker) |marker| {
        try list.append(allocator, 1);
        try list.append(allocator, markerKindTag(marker.kind));
        try list.append(allocator, markerShapeTag(marker.shape));
        try appendString(list, allocator, marker.marker_id);
        try appendString(list, allocator, marker.group);
        try appendString(list, allocator, marker.binding);
        try appendF32(list, allocator, marker.radius);
        try appendI32(list, allocator, marker.order);
    } else {
        try list.append(allocator, 0);
    }
}

fn readObject(allocator: std.mem.Allocator, bytes: []const u8, offset: *usize, file_version: u32) !scene_io.SceneObjectData {
    const id = try readU64(bytes, offset);
    const name = try readString(allocator, bytes, offset);

    const primitive_tag = try readByte(bytes, offset);
    const primitive_kind: ?geometry.PrimitiveKind = switch (primitive_tag) {
        0 => null,
        1 => .box,
        2 => .plane,
        3 => .cylinder,
        4 => .sphere,
        else => return error.InvalidSceneFormat,
    };
    const physics = physicsFromTag(try readByte(bytes, offset)) orelse return error.InvalidSceneFormat;
    const object_kind = objectKindFromTag(try readByte(bytes, offset)) orelse return error.InvalidSceneFormat;
    const flags = try readByte(bytes, offset);
    const enabled = (flags & 0x01) != 0;
    const renderer_visible = (flags & 0x02) != 0;
    const cast_shadows = (flags & 0x04) != 0;
    const receive_shadows = (flags & 0x08) != 0;
    const component_count = try readU32(bytes, offset);
    const components = try allocator.alloc([]u8, component_count);
    var component_read_count: usize = 0;
    errdefer {
        for (components[0..component_read_count]) |component| allocator.free(component);
        allocator.free(components);
    }
    for (0..component_count) |component_idx| {
        components[component_idx] = try readString(allocator, bytes, offset);
        component_read_count += 1;
    }
    const physics_body = if (physics) |body_tag| blk: {
        var body = body_tag;
        body.collider = colliderFromTag(try readByte(bytes, offset)) orelse return error.InvalidSceneFormat;
        body.mass = try readF32(bytes, offset);
        body.friction = try readF32(bytes, offset);
        body.restitution = try readF32(bytes, offset);
        if (file_version >= 5) {
            body.trigger = (try readByte(bytes, offset)) != 0;
        }
        break :blk body;
    } else null;

    var position: [3]f32 = undefined;
    var rotation: [3]f32 = undefined;
    var scale: [3]f32 = undefined;
    for (&position) |*component| component.* = try readF32(bytes, offset);
    for (&rotation) |*component| component.* = try readF32(bytes, offset);
    for (&scale) |*component| component.* = try readF32(bytes, offset);

    var color_bytes: [4]u8 = undefined;
    for (&color_bytes) |*component| component.* = try readByte(bytes, offset);
    const base_color = shared_color.Color{
        .r = color_bytes[0],
        .g = color_bytes[1],
        .b = color_bytes[2],
        .a = color_bytes[3],
    };

    const texture_len = try readU32(bytes, offset);
    if (texture_len != texture_pixel_bytes) return error.InvalidTextureSize;
    const texture = try allocator.alloc(u8, texture_len);
    errdefer allocator.free(texture);
    try readExact(bytes, offset, texture);

    const vertex_count = try readU32(bytes, offset);
    const index_count = try readU32(bytes, offset);
    const vertices = try allocator.alloc(geometry.Vertex, vertex_count);
    errdefer allocator.free(vertices);
    const indices = try allocator.alloc(u32, index_count);
    errdefer allocator.free(indices);

    try readExact(bytes, offset, std.mem.sliceAsBytes(vertices));
    try readExact(bytes, offset, std.mem.sliceAsBytes(indices));

    var parent_id: ?u64 = null;
    var layer: []u8 = "";
    var variant: ?[]u8 = null;
    var prop_asset_id: ?[]u8 = null;
    var lightmap_path: ?[]u8 = null;
    var face_surfaces: []scene_surface.FaceSurface = &.{};
    var gameplay: ?scene_gameplay.Component = null;
    var marker: ?scene_marker.Marker = null;

    if (file_version >= 5) {
        const parent_raw = try readU64(bytes, offset);
        parent_id = if (parent_raw == 0) null else parent_raw;
        layer = try readString(allocator, bytes, offset);
        const variant_raw = try readString(allocator, bytes, offset);
        variant = if (variant_raw.len == 0) null else variant_raw;
        const prop_raw = try readString(allocator, bytes, offset);
        prop_asset_id = if (prop_raw.len == 0) null else prop_raw;
        const lightmap_raw = try readString(allocator, bytes, offset);
        lightmap_path = if (lightmap_raw.len == 0) null else lightmap_raw;
        const face_surface_count = try readU32(bytes, offset);
        face_surfaces = try allocator.alloc(scene_surface.FaceSurface, face_surface_count);
        errdefer allocator.free(face_surfaces);
        for (face_surfaces) |*face| {
            face.face_index = try readU32(bytes, offset);
            face.surface_type = surfaceTypeFromTag(try readByte(bytes, offset)) orelse return error.InvalidSceneFormat;
        }
        const gameplay_present = try readByte(bytes, offset);
        if (gameplay_present != 0) {
            gameplay = .{
                .tag = try readString(allocator, bytes, offset),
                .health = try readF32(bytes, offset),
                .score = try readI32(bytes, offset),
                .team = try readI32(bytes, offset),
                .interactable = (try readByte(bytes, offset)) != 0,
            };
        }
        if (file_version >= 6) {
            const marker_present = try readByte(bytes, offset);
            if (marker_present != 0) {
                marker = .{
                    .kind = markerKindFromTag(try readByte(bytes, offset)) orelse return error.InvalidSceneFormat,
                    .shape = markerShapeFromTag(try readByte(bytes, offset)) orelse return error.InvalidSceneFormat,
                    .marker_id = try readString(allocator, bytes, offset),
                    .group = try readString(allocator, bytes, offset),
                    .binding = try readString(allocator, bytes, offset),
                    .radius = try readF32(bytes, offset),
                    .order = try readI32(bytes, offset),
                };
            }
        }
    }

    return .{
        .id = id,
        .name = name,
        .mesh = .{ .vertices = vertices, .indices = indices },
        .position = .{ .x = position[0], .y = position[1], .z = position[2] },
        .rotation = .{ .x = rotation[0], .y = rotation[1], .z = rotation[2] },
        .scale = .{ .x = scale[0], .y = scale[1], .z = scale[2] },
        .texture = texture,
        .base_color = base_color,
        .primitive_kind = primitive_kind,
        .object_kind = object_kind,
        .enabled = enabled,
        .renderer_visible = renderer_visible,
        .cast_shadows = cast_shadows,
        .receive_shadows = receive_shadows,
        .components = components,
        .physics = physics_body,
        .parent_id = parent_id,
        .layer = layer,
        .variant = variant,
        .prop_asset_id = prop_asset_id,
        .lightmap_path = lightmap_path,
        .face_surfaces = face_surfaces,
        .gameplay = gameplay,
        .marker = marker,
    };
}

fn surfaceTypeTag(kind: scene_surface.SurfaceType) u8 {
    return switch (kind) {
        .default => 0,
        .walkable => 1,
        .slippery => 2,
    };
}

fn surfaceTypeFromTag(tag: u8) ?scene_surface.SurfaceType {
    return switch (tag) {
        0 => .default,
        1 => .walkable,
        2 => .slippery,
        else => null,
    };
}

fn appendI32(list: *std.ArrayList(u8), allocator: std.mem.Allocator, value: i32) !void {
    const bits: u32 = @bitCast(value);
    try appendU32(list, allocator, bits);
}

fn readI32(bytes: []const u8, offset: *usize) !i32 {
    const bits = try readU32(bytes, offset);
    return @bitCast(bits);
}

fn physicsTag(body: ?scene_physics.Body) u8 {
    return if (body) |value| switch (value.kind) {
        .static => 1,
        .dynamic => 2,
        .kinematic => 3,
    } else 0;
}

fn physicsFromTag(tag: u8) ??scene_physics.Body {
    return switch (tag) {
        0 => @as(?scene_physics.Body, null),
        1 => .{ .kind = .static },
        2 => .{ .kind = .dynamic },
        3 => .{ .kind = .kinematic },
        else => null,
    };
}

fn objectKindTag(kind: @import("scene_document.zig").ObjectKind) u8 {
    return switch (kind) {
        .mesh => 0,
        .empty => 1,
        .light => 2,
        .camera => 3,
        .trigger => 4,
        .audio => 5,
        .prefab => 6,
        .marker => 7,
    };
}

fn objectKindFromTag(tag: u8) ?@import("scene_document.zig").ObjectKind {
    return switch (tag) {
        0 => .mesh,
        1 => .empty,
        2 => .light,
        3 => .camera,
        4 => .trigger,
        5 => .audio,
        6 => .prefab,
        7 => .marker,
        else => null,
    };
}

fn markerKindTag(kind: scene_marker.Kind) u8 {
    return @intFromEnum(kind);
}

fn markerKindFromTag(tag: u8) ?scene_marker.Kind {
    if (tag >= std.meta.fields(scene_marker.Kind).len) return null;
    return @enumFromInt(tag);
}

fn markerShapeTag(shape: scene_marker.Shape) u8 {
    return @intFromEnum(shape);
}

fn markerShapeFromTag(tag: u8) ?scene_marker.Shape {
    if (tag >= std.meta.fields(scene_marker.Shape).len) return null;
    return @enumFromInt(tag);
}

fn colliderTag(kind: scene_physics.ColliderKind) u8 {
    return switch (kind) {
        .box => 0,
        .sphere => 1,
        .capsule => 2,
        .mesh => 3,
    };
}

fn colliderFromTag(tag: u8) ?scene_physics.ColliderKind {
    return switch (tag) {
        0 => .box,
        1 => .sphere,
        2 => .capsule,
        3 => .mesh,
        else => null,
    };
}

fn flagsByte(object: scene_io.SceneObjectData) u8 {
    var flags: u8 = 0;
    if (object.enabled) flags |= 0x01;
    if (object.renderer_visible) flags |= 0x02;
    if (object.cast_shadows) flags |= 0x04;
    if (object.receive_shadows) flags |= 0x08;
    return flags;
}

fn appendU32(list: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u32) !void {
    var buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &buf, value, .little);
    try list.appendSlice(allocator, &buf);
}

fn appendU64(list: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u64) !void {
    var buf: [8]u8 = undefined;
    std.mem.writeInt(u64, &buf, value, .little);
    try list.appendSlice(allocator, &buf);
}

fn appendF32(list: *std.ArrayList(u8), allocator: std.mem.Allocator, value: f32) !void {
    const bits: u32 = @bitCast(value);
    try appendU32(list, allocator, bits);
}

fn appendString(list: *std.ArrayList(u8), allocator: std.mem.Allocator, value: []const u8) !void {
    try appendU32(list, allocator, @intCast(value.len));
    try list.appendSlice(allocator, value);
}

fn readU32(bytes: []const u8, offset: *usize) !u32 {
    if (offset.* + 4 > bytes.len) return error.InvalidSceneFormat;
    const value = std.mem.readInt(u32, bytes[offset.*..][0..4], .little);
    offset.* += 4;
    return value;
}

fn readU64(bytes: []const u8, offset: *usize) !u64 {
    if (offset.* + 8 > bytes.len) return error.InvalidSceneFormat;
    const value = std.mem.readInt(u64, bytes[offset.*..][0..8], .little);
    offset.* += 8;
    return value;
}

fn readF32(bytes: []const u8, offset: *usize) !f32 {
    const bits = try readU32(bytes, offset);
    return @bitCast(bits);
}

fn readByte(bytes: []const u8, offset: *usize) !u8 {
    if (offset.* >= bytes.len) return error.InvalidSceneFormat;
    const value = bytes[offset.*];
    offset.* += 1;
    return value;
}

fn readString(allocator: std.mem.Allocator, bytes: []const u8, offset: *usize) ![]u8 {
    const len = try readU32(bytes, offset);
    if (offset.* + len > bytes.len) return error.InvalidSceneFormat;
    const value = try allocator.dupe(u8, bytes[offset.* .. offset.* + len]);
    offset.* += len;
    return value;
}

fn readExact(bytes: []const u8, offset: *usize, out: []u8) !void {
    if (offset.* + out.len > bytes.len) return error.InvalidSceneFormat;
    @memcpy(out, bytes[offset.* .. offset.* + out.len]);
    offset.* += out.len;
}

test {
    _ = @import("scene_binary_tests.zig");
}
