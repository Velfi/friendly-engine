const std = @import("std");
const shared = @import("runtime_shared");
const friendly_engine = @import("friendly_engine");

const project_editor_state = @import("project_editor_state.zig");
const manifest = @import("project_editor_world_authoring_manifest.zig");
const csg = @import("project_editor_world_authoring_csg.zig");
const terrain = @import("project_editor_world_authoring_terrain.zig");
const layers = @import("project_editor_world_authoring_layers.zig");
const scatter = @import("project_editor_world_authoring_scatter.zig");
const scatter_mask = @import("project_editor_world_authoring_scatter_mask.zig");
const splines = @import("project_editor_world_authoring_splines.zig");
const atmosphere = @import("project_editor_world_authoring_atmosphere.zig");
const ocean = @import("project_editor_world_authoring_ocean.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const modules = friendly_engine.modules;

pub const WorldLayerNotTerrain = manifest.WorldLayerNotTerrain;
pub const WorldLayerNotSpline = manifest.WorldLayerNotSpline;
pub const WorldLayerNotScatter = manifest.WorldLayerNotScatter;
pub const WorldBrushAffectDisabled = manifest.WorldBrushAffectDisabled;

pub const persistAddBlockout = csg.persistAddBlockout;
pub const persistAddWedgeBlockout = csg.persistAddWedgeBlockout;
pub const persistDoorwaySubtract = csg.persistDoorwaySubtract;
pub const persistSubtractBlockout = csg.persistSubtractBlockout;
pub const persistSubtractPrismBlockout = csg.persistSubtractPrismBlockout;
pub const persistStairIntent = csg.persistStairIntent;

pub const paintTerrainTile = terrain.paintTerrainTile;
pub const paintTerrainAt = terrain.paintTerrainAt;
pub const createTerrainCell = terrain.createTerrainCell;
pub const createTerrainCellAt = terrain.createTerrainCellAt;
pub const deleteTerrainCellAt = terrain.deleteTerrainCellAt;

pub const drawRoadThroughCell = layers.drawRoadThroughCell;
pub const drawRoadAt = layers.drawRoadAt;
pub const commitRoadBetween = splines.commitRoadBetween;
pub const commitRoadPath = splines.commitRoadPath;
pub const persistRoadGraphDoc = splines.persistRoadGraphDoc;
pub const validateConformingRoadTerrain = splines.validateConformingRoadTerrain;
pub const seedScatter = scatter.seedScatter;
pub const seedScatterAt = scatter.seedScatterAt;
pub const beginScatterZoneDrag = scatter.beginScatterZoneDrag;
pub const updateScatterZoneDrag = scatter.updateScatterZoneDrag;
pub const finishScatterZoneDrag = scatter.finishScatterZoneDrag;
pub const paintDensityMaskAt = scatter_mask.paintDensityMaskAt;
pub const loadAtmosphereIntoState = atmosphere.loadIntoState;
pub const persistAtmosphere = atmosphere.persistFromState;
pub const loadOceanIntoState = ocean.loadIntoState;
pub const persistOcean = ocean.persistFromState;
pub const authorInteriorRoom = layers.authorInteriorRoom;
pub const authorBuilding = layers.authorBuilding;

test "world authoring computes manifest cell for camera target" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "world.kdl",
        .data =
        \\world version=1 id="main" cell_size_m=64 {
        \\  cell coord="1,2,0" authoring="scenes/main.kdl"
        \\}
        \\
        ,
    });
    const project_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(project_path);
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = @constCast(project_path),
        .active_world_manifest_path = manifest.world_manifest_path,
        .project_name = "",
        .objects = .empty,
    };
    const id = try manifest.cellForPoint(&state, .{ .x = 96, .y = 0, .z = 128 });
    try std.testing.expect(id.eql(.{ .x = 1, .y = 2, .z = 0 }));
}

test "terrain paint marks edited cell dirty" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = manifest.world_manifest_path,
        .data =
        \\world version=1 id="main" cell_size_m=64 {
        \\  cell coord="1,2,0" authoring="scenes/main.kdl"
        \\}
        \\
        ,
    });
    const project_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(project_path);
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = @constCast(project_path),
        .active_world_manifest_path = manifest.world_manifest_path,
        .project_name = "",
        .objects = .empty,
        .camera = .{ .target = .{ .x = 96, .y = 0, .z = 128 } },
        .selected_world_layer = .terrain_base_height,
        .world_affects_height = true,
    };

    try paintTerrainTile(&state);

    try std.testing.expectEqual(@as(usize, 1), state.dirty_cells.count);
    const dirty = state.dirty_cells.last().?;
    try std.testing.expectEqualStrings("Terrain", dirty.layer_name);
    try std.testing.expect(dirty.cell.eql(.{ .x = 1, .y = 2, .z = 0 }));
    try std.testing.expectEqualStrings("height brush", dirty.last_change);
}

test "terrain cell creation appends manifest cell and keeps camera target" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = manifest.world_manifest_path,
        .data =
        \\world version=1 id="main" cell_size_m=64 {
        \\  cell coord="0,0,0" authoring="scenes/main.kdl"
        \\}
        \\
        ,
    });
    const project_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(project_path);
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = @constCast(project_path),
        .active_world_manifest_path = manifest.world_manifest_path,
        .project_name = "",
        .objects = .empty,
        .camera = .{ .target = .{ .x = 96, .y = 0, .z = 32 } },
    };

    try createTerrainCell(&state);

    var loaded_manifest = try friendly_engine.world.manifest.loadManifest(std.testing.allocator, std.testing.io, project_path, manifest.world_manifest_path);
    defer loaded_manifest.deinit();
    try std.testing.expect(loaded_manifest.hasCell(.{ .x = 1, .y = 0, .z = 0 }));
    try std.testing.expectEqual(@as(f32, 96), state.camera.target.x);
    try std.testing.expectEqual(@as(f32, 32), state.camera.target.z);
    try std.testing.expectEqual(@as(f32, 64), state.world_cell_size_m);
    try std.testing.expectEqual(@as(usize, 1), state.dirty_cells.count);
    try std.testing.expectEqualStrings("new cell", state.dirty_cells.last().?.last_change);

    var terrain_doc = try modules.terrain.authoring.load(std.testing.allocator, std.testing.io, project_path, manifest.world_manifest_path);
    defer terrain_doc.deinit();
    try std.testing.expectEqual(@as(usize, 1), terrain_doc.tiles.items.len);
    try std.testing.expectEqual(@as(i32, 1), terrain_doc.tiles.items[0].cell[0]);

    const scene_bytes = try tmp.dir.readFileAlloc(std.testing.io, "scenes/cell_1_0_0.kdl", std.testing.allocator, .limited(1024));
    defer std.testing.allocator.free(scene_bytes);
    try std.testing.expect(std.mem.indexOf(u8, scene_bytes, "scene version=1") != null);
}

test "terrain paint resamples legacy 4x4 tiles to editor brush size" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = manifest.world_manifest_path,
        .data =
        \\world version=1 id="main" cell_size_m=64 {
        \\  cell coord="0,0,0" authoring="scenes/main.kdl"
        \\}
        \\
        ,
    });
    const project_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(project_path);
    try modules.terrain.authoring.upsertTileFile(std.testing.allocator, std.testing.io, project_path, manifest.world_manifest_path, .{
        .cell = .{ .x = 0, .y = 0, .z = 0 },
        .size = 4,
        .lod_levels = &.{ 4, 2 },
        .heights = &.{ 1, 1, 1, 1, 1, 2, 2, 1, 1, 2, 3, 1, 1, 1, 1, 1 },
        .splat_size = 4,
        .splat = &.{ 128, 127, 128, 127, 128, 127, 128, 127, 128, 127, 128, 127, 128, 127, 128, 127, 128, 127, 128, 127, 128, 127, 128, 127, 128, 127, 128, 127, 128, 127, 128, 127 },
        .paint_layers = &.{ "base", "detail" },
        .paint_colors = &.{ .{ 32, 96, 32, 255 }, .{ 120, 96, 64, 255 } },
        .paint_albedo_textures = &.{ "", "" },
        .paint_roughness_textures = &.{ "", "" },
        .paint_specular_textures = &.{ "", "" },
        .paint_displacement_textures = &.{ "", "" },
        .material = "terrain.editor",
    });
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = @constCast(project_path),
        .active_world_manifest_path = manifest.world_manifest_path,
        .project_name = "",
        .objects = .empty,
        .camera = .{ .target = .{ .x = 32, .y = 0, .z = 32 } },
        .selected_world_layer = .terrain_base_height,
        .world_affects_height = true,
        .world_brush_size = 16.0,
        .world_brush_strength = 1.0,
        .world_brush_falloff = 0.5,
    };

    try paintTerrainTile(&state);

    var doc = try modules.terrain.authoring.load(std.testing.allocator, std.testing.io, project_path, manifest.world_manifest_path);
    defer doc.deinit();
    try std.testing.expectEqual(@as(usize, 1), doc.tiles.items.len);
    try std.testing.expectEqual(terrain.terrain_tile_size, doc.tiles.items[0].size);
    try std.testing.expectEqual(
        @as(usize, terrain.terrain_tile_size) * @as(usize, terrain.terrain_tile_size),
        doc.tiles.items[0].heights.len,
    );
}

test "erosion mask subtracts heights" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = manifest.world_manifest_path,
        .data =
        \\world version=1 id="main" cell_size_m=64 {
        \\  cell coord="0,0,0" authoring="scenes/main.kdl"
        \\}
        \\
        ,
    });
    const project_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(project_path);
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = @constCast(project_path),
        .active_world_manifest_path = manifest.world_manifest_path,
        .project_name = "",
        .objects = .empty,
        .camera = .{ .target = .{ .x = 32, .y = 0, .z = 32 } },
        .selected_world_layer = .terrain_erosion_mask,
        .world_brush_size = 32.0,
        .world_brush_strength = 1.0,
        .world_brush_falloff = 0.5,
    };

    try paintTerrainTile(&state);
    var doc = try modules.terrain.authoring.load(std.testing.allocator, std.testing.io, project_path, manifest.world_manifest_path);
    defer doc.deinit();
    try std.testing.expectEqual(@as(usize, 1), doc.tiles.items.len);
    try std.testing.expect(doc.tiles.items[0].heights[0] < 0.5);
}

test "terrain sculpt lower can cut below flat ground" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = manifest.world_manifest_path,
        .data =
        \\world version=1 id="main" cell_size_m=64 {
        \\  cell coord="0,0,0" authoring="scenes/main.kdl"
        \\}
        \\
        ,
    });
    const project_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(project_path);
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = @constCast(project_path),
        .active_world_manifest_path = manifest.world_manifest_path,
        .project_name = "",
        .objects = .empty,
        .world_brush_size = 32.0,
        .world_brush_strength = 1.0,
        .world_brush_falloff = 0.5,
    };

    const result = try terrain.sculptTerrainAt(&state, .{ .x = 32, .y = 0, .z = 32 }, .lower, "terrain sculpt");

    try std.testing.expect(result.affected_samples > 0);
    var doc = try modules.terrain.authoring.load(std.testing.allocator, std.testing.io, project_path, manifest.world_manifest_path);
    defer doc.deinit();
    try std.testing.expectEqual(@as(usize, 1), doc.tiles.items.len);
    try std.testing.expect(doc.tiles.items[0].heights[16 * terrain.terrain_tile_size + 16] < 0);
}

test "terrain sculpt smooth blends sharp height changes" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = manifest.world_manifest_path,
        .data =
        \\world version=1 id="main" cell_size_m=64 {
        \\  cell coord="0,0,0" authoring="scenes/main.kdl"
        \\}
        \\
        ,
    });
    const project_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(project_path);
    const sample_count = @as(usize, terrain.terrain_tile_size) * @as(usize, terrain.terrain_tile_size);
    const heights = try std.testing.allocator.alloc(f32, sample_count);
    defer std.testing.allocator.free(heights);
    @memset(heights, 0);
    heights[16 * terrain.terrain_tile_size + 16] = 9;
    const splat = try std.testing.allocator.alloc(u8, sample_count * terrain.default_paint_layers.len);
    defer std.testing.allocator.free(splat);
    @memset(splat, 0);
    var sample: usize = 0;
    while (sample < sample_count) : (sample += 1) splat[sample * terrain.default_paint_layers.len] = 255;

    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = @constCast(project_path),
        .active_world_manifest_path = manifest.world_manifest_path,
        .project_name = "",
        .objects = .empty,
        .world_brush_size = 8.0,
        .world_brush_strength = 1.0,
        .world_brush_falloff = 1.0,
    };
    try terrain.upsertTerrainTile(&state, .{ .x = 0, .y = 0, .z = 0 }, heights, splat, "terrain.editor");

    const result = try terrain.sculptTerrainAt(&state, .{ .x = 32, .y = 0, .z = 32 }, .smooth, "terrain sculpt");

    try std.testing.expect(result.affected_samples > 0);
    var doc = try modules.terrain.authoring.load(std.testing.allocator, std.testing.io, project_path, manifest.world_manifest_path);
    defer doc.deinit();
    try std.testing.expect(doc.tiles.items[0].heights[16 * terrain.terrain_tile_size + 16] < 9);
}

test "heightmap rgba conversion maps luminance into height range" {
    const rgba = [_]u8{
        0,   0,   0,   255,
        255, 255, 255, 255,
        127, 127, 127, 255,
        64,  64,  64,  255,
    };
    var heights: [4]f32 = undefined;
    terrain.heightmapRgbaToHeights(&rgba, 2, 2, -2, 6, &heights, 2);

    try std.testing.expectApproxEqAbs(@as(f32, -2), heights[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 6), heights[1], 0.001);
    try std.testing.expect(heights[2] > 1.9 and heights[2] < 2.1);
    try std.testing.expect(heights[3] > -0.1 and heights[3] < 0.1);
}
