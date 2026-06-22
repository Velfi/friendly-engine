const std = @import("std");
const world = @import("../../world/mod.zig");
const root = @import("mod.zig");
const compileCell = root.compileCell;
const validateSector = root.validateSector;
const validateInterior = root.validateInterior;
const makeRectangularSector = root.makeRectangularSector;
const SectorPolygonScratch = root.SectorPolygonScratch;
const makePortalOnSectorEdge = root.makePortalOnSectorEdge;
const PortalPositionScratch = root.PortalPositionScratch;
const validatePortalForSector = root.validatePortalForSector;

test "sectors layer compiles meshes occlusion navmesh and parent link" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "layers");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "layers/sectors.kdl",
        .data =
        \\sectors version=1 {
        \\  interior cell="0,0,1" parent_cell="0,0,0" {
        \\    sector id=1 floor_height=0 ceiling_height=3 polygon="0,0; 6,0; 6,6; 0,6" {
        \\      portal to_sector=2 position="3,0,6" width=2 height=2.2
        \\    }
        \\    sector id=2 floor_height=0 ceiling_height=3 polygon="6,0; 12,0; 12,6; 6,6" {
        \\      portal to_sector=1 position="6,0,3" width=2 height=2.2
        \\    }
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
    try std.testing.expect(output.render_meshes.len >= 3);
    try std.testing.expectEqual(@as(usize, 2), output.collisions.len);
    try std.testing.expectEqual(@as(usize, 2), output.collision_shapes.len);
    try std.testing.expectEqual(@as(usize, 1), output.neighbors.len);
    try std.testing.expectEqual(@as(usize, 8), output.nav_vertices.len);
    try std.testing.expectEqual(@as(usize, 12), output.nav_indices.len);
    try std.testing.expectEqual(@as(usize, 2), output.visibility.len);
    try std.testing.expectEqual(@as(usize, 3), output.blobs.len);
}

test "sectors validation rejects malformed polygon and portal target" {
    try std.testing.expectError(error.InvalidSectorPolygon, validateSector(.{
        .id = 1,
        .floor_height = 0,
        .ceiling_height = 3,
        .polygon = &.{ &.{ 0, 0 }, &.{1}, &.{ 1, 1 } },
    }));
    try std.testing.expectError(error.InvalidSectorPortal, validateInterior(std.testing.allocator, .{
        .cell = &.{ 0, 0, 1 },
        .parent_cell = &.{ 0, 0, 0 },
        .sectors = &.{.{
            .id = 1,
            .floor_height = 0,
            .ceiling_height = 3,
            .polygon = &.{ &.{ 0, 0 }, &.{ 1, 0 }, &.{ 1, 1 } },
            .portals = &.{.{ .to_sector = 2, .position = &.{ 0, 0, 0 }, .width = 1, .height = 2 }},
        }},
    }));
}

test "sector authoring builds rectangular rooms and edge portals" {
    var room_scratch = SectorPolygonScratch{};
    const sector = try makeRectangularSector(&room_scratch, .{
        .id = 7,
        .origin = .{ 2, 4 },
        .size = .{ 6, 5 },
        .floor_height = 0,
        .ceiling_height = 3,
    }, &.{});
    try std.testing.expectEqual(@as(u32, 7), sector.id);
    try std.testing.expectEqual(@as(usize, 4), sector.polygon.len);
    try std.testing.expectEqual(@as(f32, 8), sector.polygon[1][0]);
    try std.testing.expectEqual(@as(f32, 9), sector.polygon[2][1]);

    var portal_scratch = PortalPositionScratch{};
    const portal = try makePortalOnSectorEdge(&portal_scratch, sector, 1, 8, 0.5, 1.5, 2.2);
    try std.testing.expectEqual(@as(u32, 8), portal.to_sector);
    try std.testing.expectEqual(@as(f32, 8), portal.position[0]);
    try std.testing.expectEqual(@as(f32, 6.5), portal.position[2]);
}

test "sector portal validation rejects off edge and oversized openings" {
    var room_scratch = SectorPolygonScratch{};
    const sector = try makeRectangularSector(&room_scratch, .{
        .id = 1,
        .origin = .{ 0, 0 },
        .size = .{ 4, 4 },
    }, &.{});
    try std.testing.expectError(error.InvalidSectorPortal, validatePortalForSector(sector, .{
        .to_sector = 2,
        .position = &.{ 2, 0, 2 },
        .width = 1,
        .height = 2,
    }));
    try std.testing.expectError(error.InvalidSectorPortal, validatePortalForSector(sector, .{
        .to_sector = 2,
        .position = &.{ 2, 0, 0 },
        .width = 5,
        .height = 2,
    }));
}
