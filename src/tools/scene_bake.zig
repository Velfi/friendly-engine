const std = @import("std");
const runtime_shared = @import("runtime_shared");
const scene_binary = runtime_shared.scene_binary;
const scene_document = runtime_shared.scene_document;
const scene_kdl = runtime_shared.scene_kdl;
const scene_resolve = runtime_shared.scene_resolve;
const scene_io = runtime_shared.scene_io;

pub const BakeSummary = struct {
    scene_path: []const u8,
    baked_path: []const u8,
    object_count: usize,
};

pub fn bakedScenePath(allocator: std.mem.Allocator, target: []const u8, scene_rel_path: []const u8) ![]u8 {
    const basename = std.fs.path.stem(scene_rel_path);
    return std.fmt.allocPrint(allocator, "assets/cache/{s}/scenes/{s}.fscene", .{ target, basename });
}

pub fn bakeScene(
    allocator: std.mem.Allocator,
    io: std.Io,
    root_dir: std.Io.Dir,
    project_path: []const u8,
    scene_rel_path: []const u8,
    target: []const u8,
    bundle_rel_path: ?[]const u8,
) !BakeSummary {
    _ = bundle_rel_path;

    const scene_bytes = try root_dir.readFileAlloc(io, scene_rel_path, allocator, .limited(16 * 1024 * 1024));
    defer allocator.free(scene_bytes);

    var document = try scene_kdl.parseSceneDocument(allocator, scene_bytes);
    defer document.deinit(allocator);

    var project_dir = try scene_resolve.openProjectDir(io, project_path);
    defer project_dir.close(io);

    const resolver = scene_resolve.AssetResolver{
        .io = io,
        .project_dir = project_dir,
        .cache_target = target,
    };

    var loaded = try scene_resolve.resolveDocument(allocator, document, resolver);
    defer loaded.deinit(allocator);

    const baked_bytes = try scene_binary.encodeScene(allocator, loaded);
    defer allocator.free(baked_bytes);

    const baked_path = try bakedScenePath(allocator, target, scene_rel_path);
    defer allocator.free(baked_path);

    if (std.fs.path.dirname(baked_path)) |parent| {
        try root_dir.createDirPath(io, parent);
    }
    try root_dir.writeFile(io, .{ .sub_path = baked_path, .data = baked_bytes });

    return .{
        .scene_path = try allocator.dupe(u8, scene_rel_path),
        .baked_path = try allocator.dupe(u8, baked_path),
        .object_count = loaded.objects.len,
    };
}

pub fn documentFromLoaded(allocator: std.mem.Allocator, loaded: scene_io.LoadedScene) !scene_document.SceneDocument {
    var entities = try allocator.alloc(scene_document.SceneEntity, loaded.objects.len);
    errdefer {
        for (entities) |*entity| entity.deinit(allocator);
        allocator.free(entities);
    }

    for (loaded.objects, 0..) |object, index| {
        const mesh: scene_document.EntityMesh = if (object.primitive_kind) |kind| .{
            .primitive = .{ .kind = kind, .params = .{} },
        } else .{
            .asset = try allocator.dupe(u8, ""),
        };

        entities[index] = .{
            .id = object.id,
            .name = try allocator.dupe(u8, object.name),
            .position = .{ object.position.x, object.position.y, object.position.z },
            .rotation = .{ object.rotation.x, object.rotation.y, object.rotation.z },
            .scale = .{ object.scale.x, object.scale.y, object.scale.z },
            .base_color = .{ object.base_color.r, object.base_color.g, object.base_color.b, object.base_color.a },
            .texture_file = try allocator.dupe(u8, "textures/default.png"),
            .mesh = mesh,
            .object_kind = object.object_kind,
            .enabled = object.enabled,
            .renderer_visible = object.renderer_visible,
            .cast_shadows = object.cast_shadows,
            .receive_shadows = object.receive_shadows,
            .components = try scene_io.duplicateComponents(allocator, object.components),
            .properties = try scene_io.duplicateProperties(allocator, object.properties),
            .physics = object.physics,
            .face_surfaces = try scene_io.duplicateFaceSurfaces(allocator, object.face_surfaces),
            .gameplay = if (object.gameplay) |gameplay| try runtime_shared.scene_gameplay.Component.duplicate(allocator, gameplay) else null,
            .marker = if (object.marker) |marker| try runtime_shared.scene_marker.Marker.duplicate(allocator, marker) else null,
        };
    }

    return .{
        .schema_version = 1,
        .next_object_id = loaded.next_object_id,
        .entities = entities,
    };
}

test "bake scene writes binary artifact" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, "scenes");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "scenes/main.kdl",
        .data =
        \\scene version=1 next_object_id=2 {
        \\  entity id=1 name="Box" {
        \\    transform position="0,0.5,0" scale="1,1,1"
        \\    material base_color="170,180,195,255" texture="textures/default.png"
        \\    mesh primitive=box
        \\  }
        \\}
        \\
        ,
    });

    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);

    const summary = try bakeScene(
        std.testing.allocator,
        std.testing.io,
        tmp.dir,
        project_path,
        "scenes/main.kdl",
        "client-debug",
        null,
    );
    try std.testing.expectEqual(@as(usize, 1), summary.object_count);
    try std.testing.expect(std.mem.endsWith(u8, summary.baked_path, "scenes/main.fscene"));
}
