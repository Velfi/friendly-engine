const std = @import("std");
const world = @import("../../world/mod.zig");
const root = @import("mod.zig");
const TerrainTile = root.TerrainTile;
const compileCell = root.compileCell;
const validateTile = root.validateTile;
const parseCellId = root.parseCellId;

const test_paint_layers = [_][]const u8{ "base", "detail" };
const test_paint_colors = [_][4]u8{ .{ 32, 96, 32, 255 }, .{ 120, 96, 64, 255 } };
const test_paint_textures = [_][]const u8{ "", "" };

test "terrain layer compiles terrain lods and splat blob" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var manifest_value = world.manifest.OwnedWorldManifest{
        .allocator = std.testing.allocator,
        .world_id = try std.testing.allocator.dupe(u8, "main"),
        .manifest_path = try std.testing.allocator.dupe(u8, "world.kdl"),
        .cell_size_m = 256,
        .cells = try std.testing.allocator.alloc(world.manifest.ManifestCell, 0),
        .lookup = std.AutoHashMap(world.cell.CellId, usize).init(std.testing.allocator),
    };
    defer manifest_value.deinit();

    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);
    try root.authoring.upsertTileFile(std.testing.allocator, std.testing.io, project_path, "world.kdl", .{
        .cell = .{ .x = 0, .y = 0, .z = 0 },
        .size = 4,
        .lod_levels = &.{ 4, 2 },
        .heights = &.{ 0, 0.3, 0.1, 0, 0.2, 0.5, 0.4, 0.2, 0.1, 0.2, 0.3, 0.1, 0, 0.1, 0.1, 0 },
        .splat_size = 4,
        .splat = &.{ 255, 0, 128, 127, 128, 127, 255, 0, 255, 0, 128, 127, 128, 127, 255, 0, 128, 127, 255, 0, 128, 127, 255, 0, 128, 127, 255, 0, 128, 127, 255, 0 },
        .paint_layers = &test_paint_layers,
        .paint_colors = &test_paint_colors,
        .paint_albedo_textures = &test_paint_textures,
        .paint_roughness_textures = &test_paint_textures,
        .paint_specular_textures = &test_paint_textures,
        .paint_displacement_textures = &test_paint_textures,
    });

    const ctx = world.compiler.layer.CompileContext{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = project_path,
        .target = "client-debug",
        .manifest_path = "world.kdl",
        .loaded_manifest = &manifest_value,
    };

    var output = try compileCell(null, &ctx, .{ .x = 0, .y = 0, .z = 0 }, std.testing.allocator);
    defer output.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), output.render_meshes.len);
    for (output.render_meshes) |mesh| {
        try std.testing.expectEqual(root.mesh_builder.terrain_texture_size, mesh.texture.len);
        try std.testing.expectEqual(test_paint_colors[0][0], mesh.texture[0]);
        try std.testing.expectEqual(test_paint_colors[0][1], mesh.texture[1]);
        try std.testing.expectEqual(test_paint_colors[0][2], mesh.texture[2]);
        try std.testing.expect(mesh.texture[0] != mesh.texture[1]);
    }
    try std.testing.expectEqual(@as(usize, 1), output.collisions.len);
    try std.testing.expectEqual(@as(usize, 1), output.collision_shapes.len);
    try std.testing.expectEqual(world.cell.CollisionShapeKind.heightfield, output.collision_shapes[0].kind);
    try std.testing.expectEqual(@as(usize, 16), output.nav_vertices.len);
    try std.testing.expectEqual(@as(usize, 54), output.nav_indices.len);
    try std.testing.expectEqual(@as(usize, 3), output.blobs.len);
}

test "terrain layer applies architecture cutouts to render nav and collision" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var manifest_value = world.manifest.OwnedWorldManifest{
        .allocator = std.testing.allocator,
        .world_id = try std.testing.allocator.dupe(u8, "main"),
        .manifest_path = try std.testing.allocator.dupe(u8, "world.kdl"),
        .cell_size_m = 256,
        .cells = try std.testing.allocator.alloc(world.manifest.ManifestCell, 0),
        .lookup = std.AutoHashMap(world.cell.CellId, usize).init(std.testing.allocator),
    };
    defer manifest_value.deinit();

    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);
    try tmp.dir.makePath("scenes");
    try tmp.dir.writeFile(.{ .sub_path = "engine.kdl", .data =
        \\engine startup_scene="scenes/main.kdl" startup_bundle="" {
        \\  scene path="scenes/main.kdl" world="world.kdl"
        \\}
        \\
    });
    try tmp.dir.writeFile(.{ .sub_path = "scenes/main.kdl", .data =
        \\scene version=1 next_object_id=2 {
        \\  entity id=1 name="Cutout Network" {
        \\    transform position="0,0,0" rotation="0,0,0" scale="1,1,1"
        \\    material base_color="255,255,255,255" texture=""
        \\    mesh primitive="box" width=1 height=1 depth=1
        \\    meta kind=mesh enabled=true visible=true cast_shadows=true receive_shadows=true
        \\    components names="architecture:building,arch.cutout:0|80|-4|80|176|1|176"
        \\  }
        \\}
        \\
    });
    try root.authoring.upsertTileFile(std.testing.allocator, std.testing.io, project_path, "world.kdl", .{
        .cell = .{ .x = 0, .y = 0, .z = 0 },
        .size = 4,
        .lod_levels = &.{ 4, 2 },
        .heights = &.{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
        .splat_size = 4,
        .splat = &.{ 255, 0, 255, 0, 255, 0, 255, 0, 255, 0, 255, 0, 255, 0, 255, 0, 255, 0, 255, 0, 255, 0, 255, 0, 255, 0, 255, 0, 255, 0, 255, 0 },
        .paint_layers = &test_paint_layers,
        .paint_colors = &test_paint_colors,
        .paint_albedo_textures = &test_paint_textures,
        .paint_roughness_textures = &test_paint_textures,
        .paint_specular_textures = &test_paint_textures,
        .paint_displacement_textures = &test_paint_textures,
    });

    const ctx = world.compiler.layer.CompileContext{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = project_path,
        .target = "client-debug",
        .manifest_path = "world.kdl",
        .loaded_manifest = &manifest_value,
    };

    var output = try compileCell(null, &ctx, .{ .x = 0, .y = 0, .z = 0 }, std.testing.allocator);
    defer output.deinit(std.testing.allocator);

    try std.testing.expect(output.render_meshes[0].indices.len < 54);
    try std.testing.expect(output.nav_indices.len < 54);
    try std.testing.expectEqual(@as(f32, -4), output.collision_shapes[0].min.y);
    var found_heightfield = false;
    for (output.blobs) |blob| {
        if (!std.mem.eql(u8, blob.kind, "terrain.heightfield")) continue;
        found_heightfield = true;
        try std.testing.expect(std.mem.indexOf(u8, blob.payload, "\"cutout_count\":1") != null);
        try std.testing.expect(std.mem.indexOf(u8, blob.payload, "-4") != null);
    }
    try std.testing.expect(found_heightfield);
}

test "terrain layer affected cells dedupe repeated tiles" {
    var cells = std.ArrayList(world.cell.CellId).empty;
    defer cells.deinit(std.testing.allocator);
    var lookup = std.AutoHashMap(world.cell.CellId, void).init(std.testing.allocator);
    defer lookup.deinit();

    const raw_cells = [_][]const i32{ &.{ 1, 2, 3 }, &.{ 1, 2, 3 } };
    for (raw_cells) |raw_cell| {
        const id = try parseCellId(raw_cell);
        if (lookup.contains(id)) continue;
        try lookup.put(id, {});
        try cells.append(std.testing.allocator, id);
    }
    try std.testing.expectEqual(@as(usize, 1), cells.items.len);
}

test "terrain tile validation rejects invalid lod shape" {
    try std.testing.expectError(error.InvalidTerrainTile, validateTile(.{
        .cell = &.{ 0, 0, 0 },
        .size = 2,
        .lod_levels = &.{ 4, 2 },
        .heights = &.{ 0, 0, 0, 0 },
        .splat_size = 2,
        .splat = &.{ 255, 0, 255, 0, 255, 0, 255, 0 },
        .paint_layers = &test_paint_layers,
        .paint_colors = &test_paint_colors,
        .paint_albedo_textures = &test_paint_textures,
        .paint_roughness_textures = &test_paint_textures,
        .paint_specular_textures = &test_paint_textures,
        .paint_displacement_textures = &test_paint_textures,
    }));
}
