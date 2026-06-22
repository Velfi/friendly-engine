const std = @import("std");
const world_mod = @import("../world/mod.zig");
const terrain_heightfield = @import("terrain_heightfield.zig");

test "terrain heightfield blob decodes samples and jolt layout" {
    const payload =
        \\{"cell":[0,0,0],"size":4,"min_y":0,"max_y":0.5,"heights":[0,0.1,0.2,0.3,0.1,0.2,0.3,0.4,0.2,0.3,0.4,0.5,0.3,0.4,0.5,0.6]}
    ;

    var decoded = try terrain_heightfield.decodeBlob(
        std.testing.allocator,
        payload,
        .{ .x = 0, .y = 0, .z = 0 },
        .{ .x = 256, .y = 0.6, .z = 256 },
    );
    defer decoded.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u32, 4), decoded.size);
    try std.testing.expectEqual(@as(usize, 16), decoded.heights.len);
    try std.testing.expectEqual(@as(f32, 0), decoded.offset.x);
    try std.testing.expectEqual(@as(f32, -128), decoded.offset.z);
    try std.testing.expectApproxEqAbs(@as(f32, 256.0 / 3.0), decoded.scale.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 256.0 / 3.0), decoded.scale.z, 0.0001);
    try std.testing.expectEqual(@as(f32, 1), decoded.scale.y);
}

test "terrain heightfield fcell round-trip preserves blob kind" {
    const heights = [_]f32{ 0, 0.2, 0.1, 0, 0.3, 0.4, 0.2, 0.1, 0.2, 0.3, 0.1, 0, 0.1, 0.1, 0.1, 0 };
    const payload = try std.fmt.allocPrint(
        std.testing.allocator,
        "{{\"cell\":[0,0,0],\"size\":4,\"min_y\":0,\"max_y\":0.4,\"heights\":{f}}}",
        .{std.json.fmt(&heights, .{})},
    );
    defer std.testing.allocator.free(payload);

    var world_cell = world_mod.cell.WorldCellData{
        .id = .{ .x = 0, .y = 0, .z = 0 },
        .cell_size_m = 256,
        .render_meshes = try std.testing.allocator.alloc(world_mod.cell.RenderMesh, 0),
        .collisions = try std.testing.allocator.dupe(world_mod.cell.CollisionPlaceholder, &.{.{
            .min = .{ .x = 0, .y = 0, .z = 0 },
            .max = .{ .x = 256, .y = 0.4, .z = 256 },
        }}),
        .collision_shapes = try std.testing.allocator.dupe(world_mod.cell.CollisionShape, &.{.{
            .kind = .heightfield,
            .min = .{ .x = 0, .y = 0, .z = 0 },
            .max = .{ .x = 256, .y = 0.4, .z = 256 },
        }}),
        .instances = try std.testing.allocator.alloc(world_mod.cell.InstanceRecord, 0),
        .light_probes = try std.testing.allocator.alloc(world_mod.cell.LightProbeMeta, 0),
        .neighbors = try std.testing.allocator.alloc(world_mod.cell.CellId, 0),
        .blobs = try std.testing.allocator.dupe(world_mod.cell.CellBlob, &.{.{
            .kind = try std.testing.allocator.dupe(u8, "terrain.heightfield"),
            .payload = try std.testing.allocator.dupe(u8, payload),
        }}),
    };
    defer world_cell.deinit(std.testing.allocator);

    const encoded = try world_mod.fcell.encodeCell(std.testing.allocator, world_cell);
    defer std.testing.allocator.free(encoded);

    var decoded_cell = try world_mod.fcell.decodeCell(std.testing.allocator, encoded);
    defer decoded_cell.deinit(std.testing.allocator);

    try std.testing.expectEqual(world_mod.cell.CollisionShapeKind.heightfield, decoded_cell.collision_shapes[0].kind);
    const blob_payload = terrain_heightfield.findHeightfieldBlob(decoded_cell.blobs) orelse return error.MissingTerrainHeightfieldBlob;
    var decoded_hf = try terrain_heightfield.decodeBlob(
        std.testing.allocator,
        blob_payload,
        decoded_cell.collision_shapes[0].min,
        decoded_cell.collision_shapes[0].max,
    );
    defer decoded_hf.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u32, 4), decoded_hf.size);
}

test "terrain heightfield rejects jolt-incompatible size" {
    try std.testing.expectError(
        error.InvalidTerrainHeightfieldSize,
        terrain_heightfield.validateJoltHeightfieldSize(2, 2),
    );
    try std.testing.expectError(
        error.InvalidTerrainHeightfieldSize,
        terrain_heightfield.validateJoltHeightfieldSize(6, 2),
    );
    try terrain_heightfield.validateJoltHeightfieldSize(32, 2);
}
