const std = @import("std");
const world = @import("../../world/mod.zig");
const root = @import("mod.zig");
const RoadEdgeDef = root.RoadEdgeDef;
const RoadNodeDef = root.RoadNodeDef;
const compileCell = root.compileCell;
const validateRoadEdge = root.validateRoadEdge;

test "spline layer generates v2 road graph mesh collision and terrain blobs" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "layers");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "layers/splines.kdl",
        .data =
        \\splines version=2 {
        \\  road_node id="a" position="0,0,0" kind="endpoint" terrain_mode="conform"
        \\  road_node id="b" position="48,0,0" kind="junction" terrain_mode="conform"
        \\  road_node id="c" position="96,0,0" kind="endpoint" terrain_mode="conform"
        \\  road_edge id="main_0" start="a" end="b" handle_start="16,0,0" handle_end="32,0,0" width=4.0 elevation=0.1 material_mask_value=255 render_mode="decal" terrain_mode="conform" decal_material="road.dirt" prop_asset_id=""
        \\  road_edge id="main_1" start="b" end="c" handle_start="64,0,0" handle_end="80,0,0" width=4.0 elevation=0.1 material_mask_value=255 render_mode="decal" terrain_mode="conform" decal_material="road.dirt" prop_asset_id=""
        \\}
        \\
        ,
    });

    const ctx = try makeContext(&tmp);
    defer ctx.deinit();

    var output = try compileCell(null, &ctx.value, .{ .x = 0, .y = 0, .z = 0 }, std.testing.allocator);
    defer output.deinit(std.testing.allocator);
    try std.testing.expect(output.render_meshes.len >= 1);
    try std.testing.expect(output.collisions.len >= 1);
    try std.testing.expect(output.collision_shapes.len >= 1);
    try std.testing.expectEqual(world.cell.CollisionShapeKind.aabb, output.collision_shapes[0].kind);
    try std.testing.expect(output.nav_vertices.len >= 4);
    try std.testing.expect(output.nav_indices.len >= 6);
    try std.testing.expectEqual(@as(usize, 2), output.blobs.len);
}

test "spline road graph collision strips round trip through fcell" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "layers");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "layers/splines.kdl",
        .data =
        \\splines version=2 {
        \\  road_node id="a" position="0,0,0"
        \\  road_node id="b" position="48,0,0"
        \\  road_edge id="main_road" start="a" end="b" handle_start="16,0,0" handle_end="32,0,0" width=4.0 elevation=0.1
        \\}
        \\
        ,
    });

    const ctx = try makeContext(&tmp);
    defer ctx.deinit();

    var output = try compileCell(null, &ctx.value, .{ .x = 0, .y = 0, .z = 0 }, std.testing.allocator);
    defer output.deinit(std.testing.allocator);
    try std.testing.expect(output.collision_shapes.len >= 1);

    const world_cell = world.cell.WorldCellData{
        .id = .{ .x = 0, .y = 0, .z = 0 },
        .cell_size_m = 256,
        .render_meshes = output.render_meshes,
        .collisions = output.collisions,
        .collision_shapes = output.collision_shapes,
        .instances = try std.testing.allocator.alloc(world.cell.InstanceRecord, 0),
        .light_probes = try std.testing.allocator.alloc(world.cell.LightProbeMeta, 0),
        .neighbors = try std.testing.allocator.alloc(world.cell.CellId, 0),
        .nav_vertices = output.nav_vertices,
        .nav_indices = output.nav_indices,
        .blobs = output.blobs,
    };
    output.render_meshes = &.{};
    output.collisions = &.{};
    output.collision_shapes = &.{};
    output.nav_vertices = &.{};
    output.nav_indices = &.{};
    output.blobs = &.{};

    const encoded = try world.fcell.encodeCell(std.testing.allocator, world_cell);
    defer std.testing.allocator.free(encoded);
    var decoded = try world.fcell.decodeCell(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);

    try std.testing.expect(decoded.collision_shapes.len >= 1);
    try std.testing.expectEqual(world.cell.CollisionShapeKind.aabb, decoded.collision_shapes[0].kind);
    try std.testing.expect(decoded.collision_shapes[0].max.x > decoded.collision_shapes[0].min.x);
}

test "spline validation rejects malformed graph edges" {
    const nodes = &.{
        RoadNodeDef{ .id = "a", .position = .{ .x = 0, .y = 0, .z = 0 } },
        RoadNodeDef{ .id = "b", .position = .{ .x = 0, .y = 4, .z = 0 } },
    };
    try std.testing.expectError(error.InvalidRoadSegment, validateRoadEdge(.{ .road_nodes = nodes }, .{
        .id = "bad",
        .start_node_id = "a",
        .end_node_id = "b",
        .handle_start = .{ .x = 0, .y = 1, .z = 0 },
        .handle_end = .{ .x = 0, .y = 2, .z = 0 },
        .width = 2,
    }));
    try std.testing.expectError(error.MissingRoadNode, validateRoadEdge(.{ .road_nodes = nodes }, .{
        .id = "bad",
        .start_node_id = "a",
        .end_node_id = "missing",
        .handle_start = .{ .x = 1, .y = 0, .z = 0 },
        .handle_end = .{ .x = 2, .y = 0, .z = 0 },
        .width = 2,
    }));
}

const TestContext = struct {
    value: world.compiler.layer.CompileContext,
    manifest_value: *world.manifest.OwnedWorldManifest,
    project_path: []u8,

    fn deinit(self: *const TestContext) void {
        self.manifest_value.deinit();
        std.testing.allocator.destroy(self.manifest_value);
        std.testing.allocator.free(self.project_path);
    }
};

fn makeContext(tmp: *std.testing.TmpDir) !TestContext {
    const cells = try std.testing.allocator.dupe(world.manifest.ManifestCell, &.{.{
        .id = .{ .x = 0, .y = 0, .z = 0 },
        .authoring_path = try std.testing.allocator.dupe(u8, "scenes/main.kdl"),
    }});
    var lookup = std.AutoHashMap(world.cell.CellId, usize).init(std.testing.allocator);
    try lookup.put(.{ .x = 0, .y = 0, .z = 0 }, 0);
    const manifest_value = try std.testing.allocator.create(world.manifest.OwnedWorldManifest);
    errdefer std.testing.allocator.destroy(manifest_value);
    manifest_value.* = .{
        .allocator = std.testing.allocator,
        .world_id = try std.testing.allocator.dupe(u8, "main"),
        .manifest_path = try std.testing.allocator.dupe(u8, "world.kdl"),
        .cell_size_m = 256,
        .cells = cells,
        .lookup = lookup,
    };
    errdefer manifest_value.deinit();

    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    errdefer std.testing.allocator.free(project_path);

    return .{
        .manifest_value = manifest_value,
        .project_path = project_path,
        .value = .{
            .allocator = std.testing.allocator,
            .io = std.testing.io,
            .project_path = project_path,
            .target = "client-debug",
            .manifest_path = "world.kdl",
            .loaded_manifest = manifest_value,
        },
    };
}
