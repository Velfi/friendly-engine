const std = @import("std");
const world = @import("../../world/mod.zig");
const root = @import("mod.zig");
const compileCell = root.compileCell;
const validateBuilding = root.validateBuilding;
const makeRectangularBuilding = root.makeRectangularBuilding;
const BuildingFootprintScratch = root.BuildingFootprintScratch;
const DoorDef = root.DoorDef;
const WindowDef = root.WindowDef;

test "buildings layer emits exterior interior trim and lod shell" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "layers");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "layers/buildings.kdl",
        .data =
        \\buildings version=1 {
        \\  building id="bldg_a" cell="0,0,1" floors=2 footprint="0,0; 8,0; 8,6; 0,6" {
        \\    door edge_index=0 offset=0.5 width=1.5 height=2.2
        \\    window edge_index=1 offset=0.5 width=1.2 height=1.0 sill=1.1
        \\  }
        \\}
        \\
        ,
    });

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
    const ctx = world.compiler.layer.CompileContext{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = project_path,
        .target = "client-debug",
        .manifest_path = "world.kdl",
        .loaded_manifest = &manifest_value,
    };

    var output = try compileCell(null, &ctx, .{ .x = 0, .y = 0, .z = 1 }, std.testing.allocator);
    defer output.deinit(std.testing.allocator);
    try std.testing.expect(output.render_meshes.len >= 4);
    try std.testing.expectEqual(@as(usize, 1), output.collisions.len);
    try std.testing.expectEqual(@as(usize, 1), output.collision_shapes.len);
    try std.testing.expectEqual(@as(usize, 8), output.nav_vertices.len);
    try std.testing.expectEqual(@as(usize, 12), output.nav_indices.len);
    try std.testing.expectEqual(@as(usize, 1), output.visibility.len);
    try std.testing.expectEqual(@as(usize, 2), output.blobs.len);
}

test "buildings validation rejects malformed footprint and opening indices" {
    try std.testing.expectError(error.InvalidBuildingFootprint, validateBuilding(.{
        .id = "bad",
        .cell = &.{ 0, 0, 0 },
        .floors = 1,
        .footprint = &.{ &.{ 0, 0 }, &.{1}, &.{ 1, 1 } },
    }));
    try std.testing.expectError(error.InvalidBuildingOpening, validateBuilding(.{
        .id = "bad",
        .cell = &.{ 0, 0, 0 },
        .floors = 1,
        .footprint = &.{ &.{ 0, 0 }, &.{ 1, 0 }, &.{ 1, 1 } },
        .doors = &.{.{ .edge_index = 3, .offset = 0.5, .width = 1, .height = 2 }},
    }));
}

test "building authoring builds semantic rectangular descriptor" {
    var scratch = BuildingFootprintScratch{};
    const doors = [_]DoorDef{.{ .edge_index = 0, .offset = 0.5, .width = 1.2, .height = 2.1 }};
    const windows = [_]WindowDef{.{ .edge_index = 1, .offset = 0.5, .width = 1.0, .height = 0.8, .sill = 1.2 }};
    const building = try makeRectangularBuilding(&scratch, .{
        .id = "corner_shop",
        .cell = .{ 1, 2, 0 },
        .kind = .shop,
        .origin = .{ 10, 20 },
        .size = .{ 8, 6 },
        .floors = 2,
        .doors = doors[0..],
        .windows = windows[0..],
    });
    try std.testing.expectEqualStrings("corner_shop", building.id);
    try std.testing.expectEqual(@as(usize, 4), building.footprint.len);
    try std.testing.expectEqual(@as(i32, 1), building.cell[0]);
    try std.testing.expectEqual(@as(f32, 18), building.footprint[1][0]);
    try std.testing.expectEqual(@as(f32, 26), building.footprint[2][1]);
}

test "building opening validation rejects oversized doors and high windows" {
    var scratch = BuildingFootprintScratch{};
    try std.testing.expectError(error.InvalidBuildingOpening, makeRectangularBuilding(&scratch, .{
        .id = "bad_door",
        .cell = .{ 0, 0, 0 },
        .origin = .{ 0, 0 },
        .size = .{ 4, 4 },
        .doors = &.{.{ .edge_index = 0, .offset = 0.5, .width = 5, .height = 2 }},
    }));
    try std.testing.expectError(error.InvalidBuildingOpening, makeRectangularBuilding(&scratch, .{
        .id = "bad_window",
        .cell = .{ 0, 0, 0 },
        .origin = .{ 0, 0 },
        .size = .{ 4, 4 },
        .windows = &.{.{ .edge_index = 1, .offset = 0.5, .width = 1, .height = 2, .sill = 2 }},
    }));
}
