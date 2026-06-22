const std = @import("std");
const friendly_engine = @import("friendly_engine");
const geometry = @import("geometry.zig");
const scene_binary = @import("scene_binary.zig");
const mesh_codec = @import("mesh_codec.zig");
const scene_physics = @import("scene_physics.zig");
const prop_asset_doc = @import("prop_asset_doc.zig");
const scene_surface = @import("scene_surface.zig");
const scene_io = @import("scene_io.zig");
const scene_blockout = @import("scene_blockout.zig");

const bundle_loader = friendly_engine.framework.bundle_loader;

test "scene load resolves textures from runtime bundle" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, "assets/cache/client-debug/textures");
    const rgba = try std.testing.allocator.alloc(u8, scene_binary.texture_pixel_bytes);
    defer std.testing.allocator.free(rgba);
    @memset(rgba, 42);
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "assets/cache/client-debug/textures/wall.rgba",
        .data = rgba,
    });
    try tmp.dir.createDirPath(std.testing.io, "assets/bundles/client-debug");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "assets/bundles/client-debug/bundle.json",
        .data =
        \\{
        \\  "schema_version": 1,
        \\  "target": "client-debug",
        \\  "asset_count": 1,
        \\  "assets": [
        \\    {
        \\      "artifact_path": "assets/cache/client-debug/textures/wall.rgba",
        \\      "content_hash": 42,
        \\      "dependencies": ["textures/wall.png"]
        \\    }
        \\  ]
        \\}
        \\
        ,
    });

    try tmp.dir.createDirPath(std.testing.io, "scenes");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "scenes/main.kdl",
        .data =
        \\scene version=1 next_object_id=2 {
        \\  entity id=1 name="Box" {
        \\    transform position="0,0.5,0" scale="1,1,1"
        \\    material base_color="170,180,195,255" texture="textures/wall.png"
        \\    mesh primitive=box
        \\  }
        \\}
        \\
        ,
    });

    const project_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(project_path);

    var bundle = try bundle_loader.RuntimeBundle.load(
        std.testing.allocator,
        std.testing.io,
        project_path,
        "assets/bundles/client-debug/bundle.json",
    );
    defer bundle.deinit();

    var loaded = try scene_io.loadScene(
        std.testing.allocator,
        std.testing.io,
        project_path,
        scene_io.default_scene_path,
        &bundle,
    );
    defer loaded.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), loaded.objects.len);
    try std.testing.expectEqual(@as(u8, 42), loaded.objects[0].texture[0]);
}

test "scene save and load round trip" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tex = try std.testing.allocator.alloc(u8, scene_binary.texture_pixel_bytes);
    defer std.testing.allocator.free(tex);
    @memset(tex, 128);

    var mesh = try geometry.buildPrimitive(std.testing.allocator, .box, .{});
    defer mesh.deinit(std.testing.allocator);
    const footprint = try std.testing.allocator.dupe(scene_blockout.Point2, &.{
        .{ 0, 0 },
        .{ 1, 0 },
        .{ 0, 1 },
    });

    var objects = [_]scene_io.SceneObjectData{.{
        .id = 1,
        .name = try std.testing.allocator.dupe(u8, "Box 1"),
        .mesh = try geometry.duplicateMesh(std.testing.allocator, &mesh),
        .position = .{ .x = 0, .y = 0.5, .z = 0 },
        .rotation = .{ .x = 0.1, .y = 0.2, .z = 0.3 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = try std.testing.allocator.dupe(u8, tex),
        .base_color = .{ .r = 170, .g = 180, .b = 195, .a = 255 },
        .primitive_kind = .box,
        .physics = .{ .kind = .static },
        .blockout_intent = .{
            .kind = .subtract_prism,
            .min = .{ .x = 0, .y = 0, .z = 0 },
            .max = .{ .x = 1, .y = 1, .z = 1 },
            .footprint = footprint,
        },
    }};
    defer objects[0].deinit(std.testing.allocator);

    const project_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(project_path);

    try scene_io.saveScene(std.testing.allocator, std.testing.io, project_path, scene_io.default_scene_path, &objects, 2, &.{}, &.{});

    var loaded = try scene_io.loadScene(std.testing.allocator, std.testing.io, project_path, scene_io.default_scene_path, null);
    defer loaded.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), loaded.objects.len);
    try std.testing.expectEqual(@as(u64, 2), loaded.next_object_id);
    try std.testing.expectEqualStrings("Box 1", loaded.objects[0].name);
    try std.testing.expect(loaded.objects[0].primitive_kind == .box);
    try std.testing.expect(loaded.objects[0].physics != null);
    try std.testing.expectEqual(scene_physics.BodyKind.static, loaded.objects[0].physics.?.kind);
    try std.testing.expectEqual(@as(f32, 0.5), loaded.objects[0].position.y);
    try std.testing.expectEqual(@as(f32, 0.2), loaded.objects[0].rotation.y);
    try std.testing.expectEqual(scene_blockout.Kind.subtract_prism, loaded.objects[0].blockout_intent.?.kind);
    try std.testing.expectEqual(@as(usize, 3), loaded.objects[0].blockout_intent.?.footprint.len);
    try std.testing.expectEqual(@as(f32, 1), loaded.objects[0].blockout_intent.?.footprint[2][1]);
}

test "scene save and load round trip generated mesh asset" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tex = try std.testing.allocator.alloc(u8, scene_binary.texture_pixel_bytes);
    defer std.testing.allocator.free(tex);
    @memset(tex, 96);

    var mesh = try geometry.buildPrimitive(std.testing.allocator, .box, .{ .width = 2, .height = 3, .depth = 4 });
    defer mesh.deinit(std.testing.allocator);

    var objects = [_]scene_io.SceneObjectData{.{
        .id = 1,
        .name = try std.testing.allocator.dupe(u8, "Generated Roof"),
        .mesh = try geometry.duplicateMesh(std.testing.allocator, &mesh),
        .position = .{ .x = 0, .y = 3, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = try std.testing.allocator.dupe(u8, tex),
        .base_color = .{ .r = 120, .g = 80, .b = 70, .a = 255 },
        .primitive_kind = null,
    }};
    defer objects[0].deinit(std.testing.allocator);

    const project_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(project_path);

    try scene_io.saveScene(std.testing.allocator, std.testing.io, project_path, scene_io.default_scene_path, &objects, 2, &.{}, &.{});

    const kdl_bytes = try tmp.dir.readFileAlloc(std.testing.io, scene_io.default_scene_path, std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(kdl_bytes);
    try std.testing.expect(std.mem.indexOf(u8, kdl_bytes, "mesh asset=\"meshes/1.fmesh\"") != null);

    const mesh_bytes = try tmp.dir.readFileAlloc(std.testing.io, "scenes/meshes/1.fmesh", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(mesh_bytes);
    try std.testing.expectEqualStrings("FMES", mesh_bytes[0..4]);

    var loaded = try scene_io.loadScene(std.testing.allocator, std.testing.io, project_path, scene_io.default_scene_path, null);
    defer loaded.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), loaded.objects.len);
    try std.testing.expect(loaded.objects[0].primitive_kind == null);
    try std.testing.expectEqual(mesh.vertices.len, loaded.objects[0].mesh.vertices.len);
    try std.testing.expectEqual(mesh.indices.len, loaded.objects[0].mesh.indices.len);
}

test "scene save and load round trip five-mode fields" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

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
        .rotation = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = try std.testing.allocator.dupe(u8, tex),
        .base_color = .{ .r = 170, .g = 180, .b = 195, .a = 255 },
        .primitive_kind = .box,
        .object_kind = .trigger,
        .physics = .{ .kind = .static, .trigger = true },
        .gameplay = .{ .tag = tag, .interactable = true },
        .parent_id = 2,
        .layer = layer,
        .variant = variant,
        .prop_asset_id = prop_asset,
        .lightmap_path = lightmap,
        .face_surfaces = try std.testing.allocator.dupe(scene_surface.FaceSurface, &.{
            .{ .face_index = 3, .surface_type = scene_surface.SurfaceType.walkable },
        }),
    }};
    defer objects[0].deinit(std.testing.allocator);

    const project_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(project_path);
    try writePropMesh(&tmp.dir, "props/door", &mesh);

    try scene_io.saveScene(std.testing.allocator, std.testing.io, project_path, scene_io.default_scene_path, &objects, 3, &.{}, &.{});

    var loaded = try scene_io.loadScene(std.testing.allocator, std.testing.io, project_path, scene_io.default_scene_path, null);
    defer loaded.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(?u64, 2), loaded.objects[0].parent_id);
    try std.testing.expectEqualStrings("gameplay", loaded.objects[0].layer);
    try std.testing.expectEqualStrings("door_a", loaded.objects[0].variant.?);
    try std.testing.expectEqualStrings("props/door", loaded.objects[0].prop_asset_id.?);
    try std.testing.expectEqualStrings("textures/floor_lm.png", loaded.objects[0].lightmap_path.?);
    try std.testing.expect(loaded.objects[0].physics.?.trigger);
    try std.testing.expect(loaded.objects[0].gameplay.?.interactable);
    try std.testing.expectEqual(scene_surface.SurfaceType.walkable, loaded.objects[0].face_surfaces[0].surface_type);
}

test "scene prop instance saves shared prop mesh reference without duplicate object mesh" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tex = try std.testing.allocator.alloc(u8, scene_binary.texture_pixel_bytes);
    defer std.testing.allocator.free(tex);
    @memset(tex, 64);

    var mesh = try geometry.buildPrimitive(std.testing.allocator, .box, .{ .width = 0.8, .height = 0.8, .depth = 0.8 });
    defer mesh.deinit(std.testing.allocator);
    try writePropMesh(&tmp.dir, "crate_wood", &mesh);

    const prop_asset = try std.testing.allocator.dupe(u8, "crate_wood");
    var objects = [_]scene_io.SceneObjectData{.{
        .id = 7,
        .name = try std.testing.allocator.dupe(u8, "Crate Instance"),
        .mesh = try geometry.duplicateMesh(std.testing.allocator, &mesh),
        .position = .{ .x = 4, .y = 0.4, .z = 2 },
        .scale = .{ .x = 2, .y = 1, .z = 0.5 },
        .texture = try std.testing.allocator.dupe(u8, tex),
        .base_color = .{ .r = 80, .g = 120, .b = 200, .a = 255 },
        .primitive_kind = null,
        .prop_asset_id = prop_asset,
    }};
    defer objects[0].deinit(std.testing.allocator);

    const project_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(project_path);

    try scene_io.saveScene(std.testing.allocator, std.testing.io, project_path, scene_io.default_scene_path, &objects, 8, &.{}, &.{});

    const kdl_bytes = try tmp.dir.readFileAlloc(std.testing.io, scene_io.default_scene_path, std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(kdl_bytes);
    try std.testing.expect(std.mem.indexOf(u8, kdl_bytes, "mesh asset=\"props/meshes/crate_wood.fmesh\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, kdl_bytes, "prop_asset=\"crate_wood\"") != null);
    try std.testing.expectError(error.FileNotFound, tmp.dir.access(std.testing.io, "scenes/meshes/7.fmesh", .{}));

    var loaded = try scene_io.loadScene(std.testing.allocator, std.testing.io, project_path, scene_io.default_scene_path, null);
    defer loaded.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("crate_wood", loaded.objects[0].prop_asset_id.?);
    try std.testing.expectEqual(@as(f32, 4), loaded.objects[0].position.x);
    try std.testing.expectEqual(@as(f32, 2), loaded.objects[0].scale.x);
    try std.testing.expectEqual(@as(u8, 80), loaded.objects[0].base_color.r);
    try std.testing.expectEqual(mesh.vertices.len, loaded.objects[0].mesh.vertices.len);
}

fn writePropMesh(dir: *std.Io.Dir, asset_id: []const u8, mesh: *const geometry.Mesh) !void {
    const path = try prop_asset_doc.meshPath(std.testing.allocator, asset_id);
    defer std.testing.allocator.free(path);
    if (std.fs.path.dirname(path)) |parent| try dir.createDirPath(std.testing.io, parent);
    const bytes = try mesh_codec.encodeMesh(std.testing.allocator, mesh.*);
    defer std.testing.allocator.free(bytes);
    try dir.writeFile(std.testing.io, .{ .sub_path = path, .data = bytes });
}
