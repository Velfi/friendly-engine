const std = @import("std");
const geometry = @import("geometry.zig");
const scene_io = @import("scene_io.zig");
const scene_surface = @import("scene_surface.zig");
const scene_binary = @import("scene_binary.zig");

test "scene binary round trip" {
    const tex = try std.testing.allocator.alloc(u8, scene_binary.texture_pixel_bytes);
    defer std.testing.allocator.free(tex);
    @memset(tex, 128);

    var mesh = try geometry.buildPrimitive(std.testing.allocator, .box, .{});
    defer mesh.deinit(std.testing.allocator);

    var objects = [_]scene_io.SceneObjectData{.{
        .id = 1,
        .name = try std.testing.allocator.dupe(u8, "Box"),
        .mesh = try geometry.duplicateMesh(std.testing.allocator, &mesh),
        .position = .{ .x = 0, .y = 0.5, .z = 0 },
        .rotation = .{ .x = 0.1, .y = 0.2, .z = 0.3 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = try std.testing.allocator.dupe(u8, tex),
        .base_color = .{ .r = 170, .g = 180, .b = 195, .a = 255 },
        .primitive_kind = .box,
    }};
    defer objects[0].deinit(std.testing.allocator);

    const encoded = try scene_binary.encodeScene(std.testing.allocator, .{ .objects = &objects, .next_object_id = 2 });
    defer std.testing.allocator.free(encoded);

    var decoded = try scene_binary.decodeScene(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), decoded.objects.len);
    try std.testing.expectEqualStrings("Box", decoded.objects[0].name);
    try std.testing.expectEqual(@as(f32, 0.3), decoded.objects[0].rotation.z);
}

test "scene binary v5 round trip five-mode fields" {
    const tex = try std.testing.allocator.alloc(u8, scene_binary.texture_pixel_bytes);
    defer std.testing.allocator.free(tex);
    @memset(tex, 128);

    var mesh = try geometry.buildPrimitive(std.testing.allocator, .box, .{});
    defer mesh.deinit(std.testing.allocator);

    const tag = try std.testing.allocator.dupe(u8, "switch");
    const layer = try std.testing.allocator.dupe(u8, "gameplay");
    const variant = try std.testing.allocator.dupe(u8, "door_a");
    const prop_asset = try std.testing.allocator.dupe(u8, "props/door");
    const lightmap = try std.testing.allocator.dupe(u8, "textures/floor_lm.png");

    var objects = [_]scene_io.SceneObjectData{.{
        .id = 1,
        .name = try std.testing.allocator.dupe(u8, "Trigger"),
        .mesh = try geometry.duplicateMesh(std.testing.allocator, &mesh),
        .position = .{ .x = 0, .y = 0.5, .z = 0 },
        .rotation = .{ .x = 0.1, .y = 0.2, .z = 0.3 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = try std.testing.allocator.dupe(u8, tex),
        .base_color = .{ .r = 170, .g = 180, .b = 195, .a = 255 },
        .primitive_kind = .box,
        .object_kind = .trigger,
        .physics = .{ .kind = .static, .trigger = true },
        .gameplay = .{
            .tag = tag,
            .interactable = true,
        },
        .parent_id = 2,
        .layer = layer,
        .variant = variant,
        .prop_asset_id = prop_asset,
        .lightmap_path = lightmap,
        .face_surfaces = try std.testing.allocator.dupe(scene_surface.FaceSurface, &.{
            .{ .face_index = 3, .surface_type = .walkable },
        }),
    }};
    defer objects[0].deinit(std.testing.allocator);

    const encoded = try scene_binary.encodeScene(std.testing.allocator, .{ .objects = &objects, .next_object_id = 2 });
    defer std.testing.allocator.free(encoded);

    var decoded = try scene_binary.decodeScene(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(?u64, 2), decoded.objects[0].parent_id);
    try std.testing.expectEqualStrings("gameplay", decoded.objects[0].layer);
    try std.testing.expectEqualStrings("door_a", decoded.objects[0].variant.?);
    try std.testing.expectEqualStrings("props/door", decoded.objects[0].prop_asset_id.?);
    try std.testing.expectEqualStrings("textures/floor_lm.png", decoded.objects[0].lightmap_path.?);
    try std.testing.expect(decoded.objects[0].physics.?.trigger);
    try std.testing.expect(decoded.objects[0].gameplay.?.interactable);
    try std.testing.expectEqual(scene_surface.SurfaceType.walkable, decoded.objects[0].face_surfaces[0].surface_type);
}
