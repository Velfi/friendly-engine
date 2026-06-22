const std = @import("std");
const world = @import("../../world/mod.zig");
const root = @import("mod.zig");
const splitAabbForDoorway = root.splitAabbForDoorway;
const compileCell = root.compileCell;
const parseAabb = root.parseAabb;
const makeDoorwaySubtractOperation = root.makeDoorwaySubtractOperation;
const parseLayerDocument = root.parseLayerDocument;
const formatLayerDocument = root.formatLayerDocument;
const appendLayerOperation = root.appendLayerOperation;
const readLayerDocument = root.readLayerDocument;
const makeAddBlockOperation = root.makeAddBlockOperation;
const makeAddPrismOperation = root.makeAddPrismOperation;
const makeSubtractBlockOperation = root.makeSubtractBlockOperation;
const makeSubtractWedgeOperation = root.makeSubtractWedgeOperation;
const makeSubtractPrismOperation = root.makeSubtractPrismOperation;
const OperationKind = root.OperationKind;
const formatOperation = root.formatOperation;

test "local csg doorway split keeps wall segments and opening" {
    const split = splitAabbForDoorway(
        .{ .min = .{ 0, 0, 0 }, .max = .{ 6, 3, 1 } },
        .{ .min = .{ 2, 0, 0 }, .max = .{ 4, 2.2, 1 } },
    );
    try std.testing.expect(split.segments[0] != null);
    try std.testing.expect(split.segments[1] != null);
    try std.testing.expect(split.segments[2] != null);
}

test "local csg doorway split follows z axis walls" {
    const split = splitAabbForDoorway(
        .{ .min = .{ 0, 0, 0 }, .max = .{ 1, 3, 8 } },
        .{ .min = .{ 0, 0, 3 }, .max = .{ 1, 2.2, 5 } },
    );
    try std.testing.expect(split.segments[0] != null);
    try std.testing.expectEqual(@as(f32, 3), split.segments[0].?.max[2]);
    try std.testing.expect(split.segments[1] != null);
    try std.testing.expectEqual(@as(f32, 5), split.segments[1].?.min[2]);
    try std.testing.expect(split.segments[2] != null);
    try std.testing.expectEqual(@as(f32, 2.2), split.segments[2].?.min[1]);
    try std.testing.expectEqual(@as(f32, 3), split.segments[2].?.min[2]);
    try std.testing.expectEqual(@as(f32, 5), split.segments[2].?.max[2]);
}

test "local csg layer emits wall trim and semantic blob" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "layers");
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
    try std.testing.expectEqual(@as(usize, 2), output.render_meshes.len);
    try std.testing.expectEqual(@as(usize, 3), output.collisions.len);
    try std.testing.expectEqual(@as(usize, 3), output.collision_shapes.len);
    for (output.render_meshes) |mesh| {
        try std.testing.expect(mesh.vertices.len != 24 or mesh.indices.len != 36);
    }
    try std.testing.expectEqual(@as(usize, 1), output.visibility.len);
    try std.testing.expectEqual(@as(usize, 1), output.blobs.len);
}

test "local csg additive blocks compile as one union render mesh with separate collisions" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "layers");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "layers/local_csg.kdl",
        .data =
        \\local_csg version=1 {
        \\  operation cell="0,0,1" op="add_block" min="0,0,0" max="1,1,1"
        \\  operation cell="0,0,1" op="add_block" min="1,0,0" max="2,1,1"
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
    try std.testing.expectEqual(@as(usize, 1), output.render_meshes.len);
    try std.testing.expectEqual(@as(usize, 2), output.collisions.len);
    try std.testing.expectEqual(@as(usize, 2), output.collision_shapes.len);
    try std.testing.expectEqual(@as(usize, 40), output.render_meshes[0].vertices.len);
    try std.testing.expectEqual(@as(usize, 60), output.render_meshes[0].indices.len);
}

test "local csg add then subtract compiles one final cut solid" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "layers");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "layers/local_csg.kdl",
        .data =
        \\local_csg version=1 {
        \\  operation cell="0,0,1" op="add_block" min="0,0,0" max="4,4,4"
        \\  operation cell="0,0,1" op="subtract_block" min="1,1,1" max="3,3,3" wall_min="0,0,0" wall_max="4,4,4"
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
    try std.testing.expectEqual(@as(usize, 1), output.render_meshes.len);
    try std.testing.expectEqual(@as(usize, 6), output.collisions.len);
    try std.testing.expectEqual(@as(usize, 6), output.collision_shapes.len);
    try std.testing.expect(output.render_meshes[0].vertices.len < 6 * 24);
    try std.testing.expect(output.render_meshes[0].indices.len < 6 * 36);
}

test "local csg subtract block emits solid remainder without doorway metadata" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "layers");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "layers/local_csg.kdl",
        .data =
        \\local_csg version=1 {
        \\  operation cell="0,0,1" op="subtract_block" min="1,1,1" max="3,3,3" wall_min="0,0,0" wall_max="4,4,4"
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
    try std.testing.expectEqual(@as(usize, 1), output.render_meshes.len);
    try std.testing.expectEqual(@as(usize, 6), output.collisions.len);
    try std.testing.expectEqual(@as(usize, 0), output.visibility.len);
    try std.testing.expectEqual(@as(usize, 0), output.blobs.len);
    try std.testing.expect(output.render_meshes[0].vertices.len < 6 * 24);
    try std.testing.expect(output.render_meshes[0].indices.len < 6 * 36);
}

test "local csg add wedge emits convex prism mesh" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "layers");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "layers/local_csg.kdl",
        .data =
        \\local_csg version=1 {
        \\  operation cell="0,0,1" op="add_wedge" min="0,0,0" max="2,1,2"
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
    try std.testing.expectEqual(@as(usize, 1), output.render_meshes.len);
    try std.testing.expectEqual(@as(usize, 18), output.render_meshes[0].vertices.len);
    try std.testing.expectEqual(@as(usize, 24), output.render_meshes[0].indices.len);
    try std.testing.expectEqual(@as(usize, 1), output.collisions.len);
}

test "local csg add prism parses footprint and emits convex prism mesh" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "layers");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "layers/local_csg.kdl",
        .data =
        \\local_csg version=1 {
        \\  operation cell="0,0,1" op="add_prism" min="0,0,0" max="2,1,2" footprint="0,0; 2,0; 2,1; 0,2"
        \\}
        \\
        ,
    });

    const doc_project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(doc_project_path);
    var doc = try readLayerDocument(std.testing.allocator, std.testing.io, doc_project_path, "world.kdl");
    defer doc.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), doc.operations.len);
    try std.testing.expectEqual(OperationKind.add_prism, doc.operations[0].kind);
    try std.testing.expectEqual(@as(usize, 4), doc.operations[0].footprint.len);

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
    try std.testing.expectEqual(@as(usize, 1), output.render_meshes.len);
    try std.testing.expect(output.render_meshes[0].vertices.len > 18);
}

test "local csg subtract wedge cuts box source with wedge cutter" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "layers");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "layers/local_csg.kdl",
        .data =
        \\local_csg version=1 {
        \\  operation cell="0,0,1" op="subtract_wedge" min="0.25,0.25,0.25" max="0.75,0.75,0.75" wall_min="0,0,0" wall_max="2,2,2"
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
    try std.testing.expectEqual(@as(usize, 1), output.render_meshes.len);
    try std.testing.expect(output.collisions.len > output.render_meshes.len);
    try std.testing.expectEqual(@as(usize, 0), output.visibility.len);
    try std.testing.expectEqual(@as(usize, 0), output.blobs.len);
}

test "local csg add then subtract wedge compiles one final cut solid" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "layers");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "layers/local_csg.kdl",
        .data =
        \\local_csg version=1 {
        \\  operation cell="0,0,1" op="add_block" min="0,0,0" max="2,2,2"
        \\  operation cell="0,0,1" op="subtract_wedge" min="0.25,0,0.25" max="1.5,2,1.5" wall_min="0,0,0" wall_max="2,2,2"
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
    try std.testing.expectEqual(@as(usize, 1), output.render_meshes.len);
    try std.testing.expect(output.collisions.len > output.render_meshes.len);
    try std.testing.expect(output.render_meshes[0].vertices.len != 24 or output.render_meshes[0].indices.len != 36);
}

test "local csg subtract prism emits convex fragment meshes" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "layers");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "layers/local_csg.kdl",
        .data =
        \\local_csg version=1 {
        \\  operation cell="0,0,1" op="subtract_prism" min="0.5,0,0.5" max="1.5,2,1.5" wall_min="0,0,0" wall_max="2,2,2" footprint="0.5,0.5; 1.5,0.5; 1,1.5"
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
    try std.testing.expectEqual(@as(usize, 1), output.render_meshes.len);
    try std.testing.expect(output.collisions.len > output.render_meshes.len);
    try std.testing.expectEqual(@as(usize, 0), output.visibility.len);
    try std.testing.expectEqual(@as(usize, 0), output.blobs.len);
}

test "local csg validation rejects invalid boxes and doorway bounds" {
    try std.testing.expectError(error.InvalidAabb, parseAabb(&.{ 0, 0, 0 }, &.{ 0, 1, 1 }));
    try std.testing.expectError(error.InvalidCsgOperation, makeDoorwaySubtractOperation(
        .{ .x = 0, .y = 0, .z = 0 },
        .{ .min = .{ -1, 0, 0 }, .max = .{ 2, 2, 1 } },
        .{ .min = .{ 0, 0, 0 }, .max = .{ 4, 3, 1 } },
    ));
}

test "local csg validation accepts general subtract operations" {
    const operation = try makeSubtractBlockOperation(
        .{ .x = 0, .y = 0, .z = 0 },
        .{ .min = .{ 1, 1, 1 }, .max = .{ 3, 3, 3 } },
        .{ .min = .{ 0, 0, 0 }, .max = .{ 4, 4, 4 } },
    );
    try std.testing.expectEqual(OperationKind.subtract_block, operation.kind);
    const wedge = try makeSubtractWedgeOperation(
        .{ .x = 0, .y = 0, .z = 0 },
        .{ .min = .{ 0.25, 0.25, 0.25 }, .max = .{ 0.5, 0.5, 0.5 } },
        .{ .min = .{ 0, 0, 0 }, .max = .{ 1, 1, 1 } },
    );
    try std.testing.expectEqual(OperationKind.subtract_wedge, wedge.kind);
    const footprint = [_]root.Point2{
        .{ 0.25, 0.25 },
        .{ 0.75, 0.25 },
        .{ 0.5, 0.75 },
    };
    var prism = try makeSubtractPrismOperation(
        std.testing.allocator,
        .{ .x = 0, .y = 0, .z = 0 },
        &footprint,
        0.25,
        0.75,
        .{ .min = .{ 0, 0, 0 }, .max = .{ 1, 1, 1 } },
    );
    defer prism.deinit(std.testing.allocator);
    try std.testing.expectEqual(OperationKind.subtract_prism, prism.kind);
}

test "local csg make add prism formats footprint" {
    const footprint = [_]root.Point2{
        .{ 0, 0 },
        .{ 1, 0 },
        .{ 1, 1 },
        .{ 0, 1 },
    };
    var operation = try makeAddPrismOperation(std.testing.allocator, .{ .x = 0, .y = 0, .z = 0 }, &footprint, 0, 1);
    defer operation.deinit(std.testing.allocator);
    const bytes = try formatLayerDocument(std.testing.allocator, &.{operation});
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "op=\"add_prism\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "footprint=\"0,0; 1,0; 1,1; 0,1\"") != null);
}

test "local csg make subtract prism formats footprint and source" {
    const footprint = [_]root.Point2{
        .{ 0.25, 0.25 },
        .{ 0.75, 0.25 },
        .{ 0.5, 0.75 },
    };
    var operation = try makeSubtractPrismOperation(
        std.testing.allocator,
        .{ .x = 0, .y = 0, .z = 0 },
        &footprint,
        0.25,
        0.75,
        .{ .min = .{ 0, 0, 0 }, .max = .{ 1, 1, 1 } },
    );
    defer operation.deinit(std.testing.allocator);
    const bytes = try formatLayerDocument(std.testing.allocator, &.{operation});
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "op=\"subtract_prism\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "wall_min=\"0,0,0\" wall_max=\"1,1,1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "footprint=\"0.25,0.25; 0.75,0.25; 0.5,0.75\"") != null);
}

test "local csg formatted operation preserves prism footprint" {
    const footprint = [_]root.Point2{
        .{ 0.25, 0.25 },
        .{ 0.75, 0.25 },
        .{ 0.5, 0.75 },
    };
    var add = try makeAddPrismOperation(std.testing.allocator, .{ .x = 0, .y = 0, .z = 0 }, &footprint, 0.25, 0.75);
    defer add.deinit(std.testing.allocator);
    const formatted_add = formatOperation(add);
    try std.testing.expectEqual(OperationKind.add_prism.jsonName(), formatted_add.op);
    try std.testing.expect(formatted_add.footprint != null);
    try std.testing.expectEqual(@as(usize, 3), formatted_add.footprint.?.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), formatted_add.footprint.?[2][0], 0.0001);

    var subtract = try makeSubtractPrismOperation(
        std.testing.allocator,
        .{ .x = 0, .y = 0, .z = 0 },
        &footprint,
        0.25,
        0.75,
        .{ .min = .{ 0, 0, 0 }, .max = .{ 1, 1, 1 } },
    );
    defer subtract.deinit(std.testing.allocator);
    const formatted_subtract = formatOperation(subtract);
    try std.testing.expectEqual(OperationKind.subtract_prism.jsonName(), formatted_subtract.op);
    try std.testing.expect(formatted_subtract.footprint != null);
    try std.testing.expectEqual(@as(usize, 3), formatted_subtract.footprint.?.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), formatted_subtract.footprint.?[2][1], 0.0001);
}

test "local csg parse and format keep semantic operations canonical" {
    var doc = try parseLayerDocument(std.testing.allocator,
        \\local_csg version=1 {
        \\  operation cell="2,-1,0" op="add_block" min="0,0,0" max="1,2,3"
        \\}
        \\
    );
    defer doc.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), doc.operations.len);
    try std.testing.expectEqual(@as(i32, 2), doc.operations[0].cell.x);
    try std.testing.expectEqual(@as(i32, -1), doc.operations[0].cell.y);
    try std.testing.expectEqual(@as(i32, 0), doc.operations[0].cell.z);
    try std.testing.expectEqual(OperationKind.add_block, doc.operations[0].kind);

    const bytes = try formatLayerDocument(std.testing.allocator, doc.operations);
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "cell=\"2,-1,0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "op=\"add_block\"") != null);
}

test "local csg append persists add and doorway operations" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);

    try appendLayerOperation(
        std.testing.allocator,
        std.testing.io,
        project_path,
        "world.kdl",
        try makeAddBlockOperation(
            .{ .x = 0, .y = 0, .z = 1 },
            .{ .min = .{ 0, 0, 0 }, .max = .{ 6, 3, 1 } },
        ),
    );
    try appendLayerOperation(
        std.testing.allocator,
        std.testing.io,
        project_path,
        "world.kdl",
        try makeDoorwaySubtractOperation(
            .{ .x = 0, .y = 0, .z = 1 },
            .{ .min = .{ 2, 0, 0 }, .max = .{ 4, 2.2, 1 } },
            .{ .min = .{ 0, 0, 0 }, .max = .{ 6, 3, 1 } },
        ),
    );

    var doc = try readLayerDocument(std.testing.allocator, std.testing.io, project_path, "world.kdl");
    defer doc.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), doc.operations.len);
    try std.testing.expectEqual(OperationKind.add_block, doc.operations[0].kind);
    try std.testing.expectEqual(OperationKind.doorway_subtract, doc.operations[1].kind);
}

test "local csg parse fails loudly on unknown operations" {
    try std.testing.expectError(error.InvalidCsgOperation, parseLayerDocument(std.testing.allocator,
        \\local_csg version=1 {
        \\  operation cell="0,0,0" op="subtractish" min="0,0,0" max="1,1,1"
        \\}
        \\
    ));
}
