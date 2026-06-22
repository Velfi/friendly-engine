const std = @import("std");
const friendly_engine = @import("friendly_engine");
const root = @import("world_bake.zig");
const world_mod = friendly_engine.world;
const bakeWorld = root.bakeWorld;
const bakeWorldWithOptions = root.bakeWorldWithOptions;
const parseCellArg = root.parseCellArg;
const expectBakedFile = root.expectBakedFile;

test "world bake writes fcell from single scene cell" {
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

    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "world.kdl",
        .data =
        \\world version=1 cell_size_m=256 {
        \\  cell coord="0,0,0" authoring="scenes/main.kdl"
        \\}
        \\
        ,
    });

    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);

    var summary = try bakeWorld(std.testing.allocator, std.testing.io, project_path, "world.kdl", "client-debug");
    defer summary.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), summary.written_cells);

    const baked_path = try world_mod.fcell.bakedCellPath(std.testing.allocator, "client-debug", "world", .{ .x = 0, .y = 0, .z = 0 });
    defer std.testing.allocator.free(baked_path);

    const encoded = try tmp.dir.readFileAlloc(std.testing.io, baked_path, std.testing.allocator, .limited(64 * 1024 * 1024));
    defer std.testing.allocator.free(encoded);
    var decoded = try world_mod.fcell.decodeCell(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), decoded.render_meshes.len);
    try std.testing.expectEqual(@as(usize, 1), decoded.instances.len);
    try std.testing.expectEqual(@as(usize, 1), decoded.collisions.len);
    try std.testing.expectEqual(@as(usize, 1), decoded.light_probes.len);
}

test "world bake stores scene props as cell prop instances" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, "scenes");
    try tmp.dir.createDirPath(std.testing.io, "props/meshes");
    try writeTestPropMesh(&tmp.dir, "props/meshes/crate_wood.fmesh");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "scenes/main.kdl",
        .data =
        \\scene version=1 next_object_id=2 {
        \\  entity id=1 name="Crate" {
        \\    meta kind=mesh variant="2" prop_asset="crate_wood"
        \\    transform position="3,0.5,4" scale="1,2,1"
        \\    material base_color="160,120,70,255" texture="textures/default.png"
        \\    mesh asset="props/meshes/crate_wood.fmesh"
        \\    gameplay tag="crate" interactable=true
        \\  }
        \\}
        \\
        ,
    });

    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "world.kdl",
        .data =
        \\world version=1 id="main" cell_size_m=256 {
        \\  cell coord="0,0,0" authoring="scenes/main.kdl"
        \\}
        \\
        ,
    });

    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);

    var summary = try bakeWorld(std.testing.allocator, std.testing.io, project_path, "world.kdl", "client-debug");
    defer summary.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), summary.written_cells);

    var decoded = try readDecodedTestCell(&tmp, .{ .x = 0, .y = 0, .z = 0 });
    defer decoded.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), decoded.render_meshes.len);
    try std.testing.expectEqual(@as(usize, 0), decoded.instances.len);
    try std.testing.expectEqual(@as(usize, 1), decoded.prop_instances.len);
    try std.testing.expectEqualStrings("crate_wood", decoded.prop_instances[0].prop_asset_id);
    try std.testing.expectEqual(@as(u32, 2), decoded.prop_instances[0].variant);
    try std.testing.expect(decoded.prop_instances[0].interactable);
    try expectDependency(decoded.dependencies, "scene", "scenes/main.kdl");
    try expectDependency(decoded.dependencies, "prop", "crate_wood");
}

test "world bake fails when manifest authoring scene is missing" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "world.kdl",
        .data =
        \\world version=1 cell_size_m=256 {
        \\  cell coord="0,0,0" authoring="scenes/missing.kdl"
        \\}
        \\
        ,
    });

    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);
    try std.testing.expectError(
        error.FileNotFound,
        bakeWorld(std.testing.allocator, std.testing.io, project_path, "world.kdl", "client-debug"),
    );
}

test "world bake can target a single cell" {
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
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "world.kdl",
        .data =
        \\world version=1 id="main" cell_size_m=256 {
        \\  cell coord="0,0,0" authoring="scenes/main.kdl"
        \\  cell coord="1,0,0" authoring="scenes/main.kdl"
        \\}
        \\
        ,
    });

    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);
    var summary = try bakeWorldWithOptions(
        std.testing.allocator,
        std.testing.io,
        project_path,
        "world.kdl",
        "client-debug",
        .{ .cells = &.{.{ .x = 1, .y = 0, .z = 0 }} },
    );
    defer summary.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), summary.written_cells);

    const selected_path = try world_mod.fcell.bakedCellPath(std.testing.allocator, "client-debug", "main", .{ .x = 1, .y = 0, .z = 0 });
    defer std.testing.allocator.free(selected_path);
    const skipped_path = try world_mod.fcell.bakedCellPath(std.testing.allocator, "client-debug", "main", .{ .x = 0, .y = 0, .z = 0 });
    defer std.testing.allocator.free(skipped_path);

    const selected = try tmp.dir.readFileAlloc(std.testing.io, selected_path, std.testing.allocator, .limited(64 * 1024 * 1024));
    defer std.testing.allocator.free(selected);
    try std.testing.expectError(
        error.FileNotFound,
        tmp.dir.readFileAlloc(std.testing.io, skipped_path, std.testing.allocator, .limited(64 * 1024 * 1024)),
    );
}

test "world bake merges phase two through six layer outputs" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, "scenes");
    try tmp.dir.createDirPath(std.testing.io, "layers");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "scenes/main.kdl",
        .data =
        \\scene version=1 next_object_id=2 {
        \\  entity id=1 name="Floor" {
        \\    transform position="0,0,0" scale="4,1,4"
        \\    material base_color="170,180,195,255" texture="textures/default.png"
        \\    mesh primitive=plane
        \\  }
        \\}
        \\
        ,
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "scenes/interior.kdl",
        .data =
        \\scene version=1 next_object_id=1 {
        \\}
        \\
        ,
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "world.kdl",
        .data =
        \\world version=1 id="main" cell_size_m=64 {
        \\  cell coord="0,0,0" authoring="scenes/main.kdl"
        \\  cell coord="0,0,1" authoring="scenes/interior.kdl" interior_parent="0,0,0"
        \\}
        \\
        ,
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "layers/splines.kdl",
        .data =
        \\splines version=2 {
        \\  road_node id="road_a.start" position="0,0,0"
        \\  road_node id="road_a.end" position="32,0,0"
        \\  road_edge id="road_a" start="road_a.start" end="road_a.end" handle_start="10,0,0" handle_end="22,0,0" width=4 elevation=0.08 material_mask_value=255 render_mode="decal" terrain_mode="conform" decal_material="road.dirt" prop_asset_id=""
        \\}
        \\
        ,
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "layers/scatter.kdl",
        .data =
        \\scatter version=1 {
        \\  rule id="grass" cell="0,0,0" prototype="scatter.grass" density=1 spacing=64 slope_min=0 slope_max=90 seed=7
        \\  density_mask cell="0,0,0" size=1 values="255"
        \\}
        \\
        ,
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "layers/sectors.kdl",
        .data =
        \\sectors version=1 {
        \\  interior cell="0,0,1" parent_cell="0,0,0" {
        \\    sector id=1 floor_height=0 ceiling_height=3 polygon="0,0; 6,0; 6,6; 0,6" {
        \\      portal to_sector=1 position="3,0,6" width=2 height=2.2
        \\    }
        \\  }
        \\}
        \\
        ,
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "layers/buildings.kdl",
        .data =
        \\buildings version=1 {
        \\  building id="house" cell="0,0,1" floors=1 footprint="8,0; 14,0; 14,6; 8,6" {
        \\    door edge_index=0 offset=0.5 width=1.5 height=2.2
        \\    window edge_index=1 offset=0.5 width=1 height=1 sill=1
        \\  }
        \\}
        \\
        ,
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "layers/local_csg.kdl",
        .data =
        \\local_csg version=1 {
        \\  operation cell="0,0,1" op="add_block" min="0,0,0" max="6,3,1"
        \\  operation cell="0,0,1" op="doorway_subtract" min="2,0,0" max="4,2.2,1" wall_min="0,0,0" wall_max="6,3,1"
        \\}
        \\
        ,
    });

    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);
    try friendly_engine.modules.terrain.authoring.upsertTileFile(std.testing.allocator, std.testing.io, project_path, "world.kdl", .{
        .cell = .{ .x = 0, .y = 0, .z = 0 },
        .size = 2,
        .lod_levels = &.{ 2, 2 },
        .heights = &.{ 0, 0.1, 0.2, 0 },
        .splat_size = 2,
        .splat = &.{ 255, 0, 128, 127, 128, 127, 255, 0 },
        .paint_layers = &.{ "base", "detail" },
        .paint_colors = &.{ .{ 32, 96, 32, 255 }, .{ 120, 96, 64, 255 } },
        .paint_albedo_textures = &.{ "", "" },
        .paint_roughness_textures = &.{ "", "" },
        .paint_specular_textures = &.{ "", "" },
        .paint_displacement_textures = &.{ "", "" },
    });
    var summary = try bakeWorld(std.testing.allocator, std.testing.io, project_path, "world.kdl", "client-debug");
    defer summary.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), summary.written_cells);

    var outdoor = try readDecodedTestCell(&tmp, .{ .x = 0, .y = 0, .z = 0 });
    defer outdoor.deinit(std.testing.allocator);
    try expectNavIndicesValid(outdoor);
    try std.testing.expect(outdoor.render_meshes.len >= 5);
    try std.testing.expect(outdoor.collisions.len >= 3);
    try std.testing.expect(outdoor.collision_shapes.len >= 3);
    try std.testing.expect(outdoor.nav_vertices.len > 0);
    try std.testing.expect(outdoor.nav_indices.len > 0);
    try std.testing.expect(hasBlobKind(outdoor, "terrain.patch"));
    try std.testing.expect(hasBlobKind(outdoor, "terrain.splat"));
    try std.testing.expect(hasBlobKind(outdoor, "terrain.deformation"));
    try std.testing.expect(hasBlobKind(outdoor, "terrain.material_mask"));
    try std.testing.expect(hasBlobKind(outdoor, "scatter.clusters"));
    try std.testing.expect(hasBlobKind(outdoor, "scatter.mask_override"));
    try std.testing.expect(hasBlobKind(outdoor, "atmosphere.settings"));

    var interior = try readDecodedTestCell(&tmp, .{ .x = 0, .y = 0, .z = 1 });
    defer interior.deinit(std.testing.allocator);
    try expectNavIndicesValid(interior);
    try std.testing.expect(interior.render_meshes.len >= 10);
    try std.testing.expect(interior.collisions.len >= 4);
    try std.testing.expect(interior.collision_shapes.len >= 4);
    try std.testing.expect(interior.visibility.len >= 3);
    try std.testing.expect(interior.nav_vertices.len > 0);
    try std.testing.expect(interior.nav_indices.len > 0);
    try std.testing.expect(hasBlobKind(interior, "interior.parent"));
    try std.testing.expect(hasBlobKind(interior, "sector.occlusion"));
    try std.testing.expect(hasBlobKind(interior, "navmesh.tile"));
    try std.testing.expect(hasBlobKind(interior, "building.portals"));
    try std.testing.expect(hasBlobKind(interior, "building.lod_shell"));
    try std.testing.expect(hasBlobKind(interior, "local_csg.semantic"));
}

test "world bake parses cell cli coordinates" {
    try std.testing.expect((try parseCellArg("4,-2")).eql(.{ .x = 4, .y = -2, .z = 0 }));
    try std.testing.expect((try parseCellArg("4,-2,3")).eql(.{ .x = 4, .y = -2, .z = 3 }));
    try std.testing.expectError(error.InvalidCellArgument, parseCellArg("4"));
    try std.testing.expectError(error.InvalidCellArgument, parseCellArg("4,"));
}

fn readDecodedTestCell(tmp: *std.testing.TmpDir, id: world_mod.cell.CellId) !world_mod.cell.WorldCellData {
    const baked_path = try world_mod.fcell.bakedCellPath(std.testing.allocator, "client-debug", "main", id);
    defer std.testing.allocator.free(baked_path);
    const encoded = try tmp.dir.readFileAlloc(std.testing.io, baked_path, std.testing.allocator, .limited(64 * 1024 * 1024));
    defer std.testing.allocator.free(encoded);
    return world_mod.fcell.decodeCell(std.testing.allocator, encoded);
}

fn expectNavIndicesValid(world_cell: world_mod.cell.WorldCellData) !void {
    try std.testing.expectEqual(@as(usize, 0), world_cell.nav_indices.len % 3);
    for (world_cell.nav_indices) |index| {
        try std.testing.expect(index < world_cell.nav_vertices.len);
    }
}

fn expectDependency(dependencies: []const world_mod.cell.CellDependency, kind: []const u8, path: []const u8) !void {
    for (dependencies) |dependency| {
        if (std.mem.eql(u8, dependency.kind, kind) and std.mem.eql(u8, dependency.path, path)) return;
    }
    return error.MissingDependency;
}

fn hasBlobKind(world_cell: world_mod.cell.WorldCellData, kind: []const u8) bool {
    for (world_cell.blobs) |blob| {
        if (std.mem.eql(u8, blob.kind, kind)) return true;
    }
    return false;
}

fn writeTestPropMesh(dir: *std.fs.Dir, path: []const u8) !void {
    const vertices = [_]world_mod.cell.RenderVertex{
        .{ .position = .{ .x = -0.5, .y = 0, .z = 0 }, .normal = .{ .x = 0, .y = 1, .z = 0 }, .uv = .{ .x = 0, .y = 0 } },
        .{ .position = .{ .x = 0.5, .y = 0, .z = 0 }, .normal = .{ .x = 0, .y = 1, .z = 0 }, .uv = .{ .x = 1, .y = 0 } },
        .{ .position = .{ .x = 0, .y = 1, .z = 0 }, .normal = .{ .x = 0, .y = 1, .z = 0 }, .uv = .{ .x = 0.5, .y = 1 } },
    };
    const indices = [_]u32{ 0, 1, 2 };
    const bytes = try encodeTestPropMesh(std.testing.allocator, &vertices, &indices);
    defer std.testing.allocator.free(bytes);
    try dir.writeFile(std.testing.io, .{ .sub_path = path, .data = bytes });
}

fn encodeTestPropMesh(
    allocator: std.mem.Allocator,
    vertices: []const world_mod.cell.RenderVertex,
    indices: []const u32,
) ![]u8 {
    const vertex_bytes = std.mem.sliceAsBytes(vertices);
    const index_bytes = std.mem.sliceAsBytes(indices);
    const total = 4 + 4 + 4 + 4 + vertex_bytes.len + index_bytes.len + 1;
    const bytes = try allocator.alloc(u8, total);
    var offset: usize = 0;
    @memcpy(bytes[offset..][0..4], "FMES");
    offset += 4;
    std.mem.writeInt(u32, bytes[offset..][0..4], 2, .little);
    offset += 4;
    std.mem.writeInt(u32, bytes[offset..][0..4], @intCast(vertices.len), .little);
    offset += 4;
    std.mem.writeInt(u32, bytes[offset..][0..4], @intCast(indices.len), .little);
    offset += 4;
    @memcpy(bytes[offset..][0..vertex_bytes.len], vertex_bytes);
    offset += vertex_bytes.len;
    @memcpy(bytes[offset..][0..index_bytes.len], index_bytes);
    offset += index_bytes.len;
    bytes[offset] = 0;
    return bytes;
}
