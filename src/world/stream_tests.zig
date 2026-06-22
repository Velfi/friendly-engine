const std = @import("std");
const cell = @import("cell.zig");
const manifest = @import("manifest.zig");
const fcell = @import("fcell.zig");
const root = @import("stream.zig");
const StreamManager = root.StreamManager;

test "stream manager loads 3x3 and unloads outer ring" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var manifest_kdl: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer manifest_kdl.deinit();
    const writer = &manifest_kdl.writer;
    try writer.writeAll("world version=1 id=\"main\" cell_size_m=256 {\n");
    var x: i32 = -1;
    while (x <= 2) : (x += 1) {
        var y: i32 = -1;
        while (y <= 1) : (y += 1) {
            try writer.print("  cell coord=\"{d},{d},0\" authoring=\"scenes/main.kdl\"\n", .{ x, y });
        }
    }
    try writer.writeAll("}\n");
    const manifest_bytes = try manifest_kdl.toOwnedSlice();
    defer std.testing.allocator.free(manifest_bytes);

    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "world.kdl",
        .data = manifest_bytes,
    });

    x = -1;
    while (x <= 2) : (x += 1) {
        var y: i32 = -1;
        while (y <= 1) : (y += 1) {
            var one_cell = cell.WorldCellData{
                .id = .{ .x = x, .y = y, .z = 0 },
                .cell_size_m = 256.0,
                .render_meshes = try std.testing.allocator.alloc(cell.RenderMesh, 0),
                .collisions = try std.testing.allocator.alloc(cell.CollisionPlaceholder, 0),
                .instances = try std.testing.allocator.alloc(cell.InstanceRecord, 0),
                .light_probes = try std.testing.allocator.dupe(cell.LightProbeMeta, &.{.{
                    .position = .{ .x = 0, .y = 2, .z = 0 },
                    .intensity = 0.5,
                }}),
                .neighbors = try std.testing.allocator.alloc(cell.CellId, 0),
                .blobs = try std.testing.allocator.alloc(cell.CellBlob, 0),
            };
            const encoded = try fcell.encodeCell(std.testing.allocator, one_cell);
            defer std.testing.allocator.free(encoded);
            one_cell.deinit(std.testing.allocator);

            const baked_path = try fcell.bakedCellPath(std.testing.allocator, "client-debug", "main", .{ .x = x, .y = y, .z = 0 });
            defer std.testing.allocator.free(baked_path);
            if (std.fs.path.dirname(baked_path)) |parent| {
                try tmp.dir.createDirPath(std.testing.io, parent);
            }
            try tmp.dir.writeFile(std.testing.io, .{
                .sub_path = baked_path,
                .data = encoded,
            });
        }
    }

    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);

    var loaded_manifest = try manifest.loadManifest(std.testing.allocator, std.testing.io, project_path, "world.kdl");
    defer loaded_manifest.deinit();

    var manager = try StreamManager.init(
        std.testing.allocator,
        std.testing.io,
        project_path,
        "client-debug",
        &loaded_manifest,
    );
    defer manager.deinit();

    const first_update = try manager.updateAroundPosition(.{ .x = 0, .y = 0, .z = 0 });
    try std.testing.expectEqual(@as(usize, 9), first_update.loaded);
    try std.testing.expectEqual(@as(usize, 0), first_update.unloaded);
    try std.testing.expectEqual(@as(usize, 9), first_update.loaded_ids.len);
    try std.testing.expectEqual(@as(usize, 0), first_update.unloaded_ids.len);
    try std.testing.expect(containsCellId(first_update.loaded_ids, .{ .x = 0, .y = 0, .z = 0 }));
    try std.testing.expectEqual(@as(usize, 9), manager.activeCellCount());

    const second_update = try manager.updateAroundPosition(.{ .x = 300, .y = 0, .z = 0 });
    try std.testing.expectEqual(@as(usize, 3), second_update.loaded);
    try std.testing.expectEqual(@as(usize, 3), second_update.unloaded);
    try std.testing.expectEqual(@as(usize, 3), second_update.loaded_ids.len);
    try std.testing.expectEqual(@as(usize, 3), second_update.unloaded_ids.len);
    try std.testing.expect(containsCellId(second_update.loaded_ids, .{ .x = 2, .y = 0, .z = 0 }));
    try std.testing.expect(containsCellId(second_update.unloaded_ids, .{ .x = -1, .y = 0, .z = 0 }));
    try std.testing.expectEqual(@as(usize, 9), manager.activeCellCount());
}

test "stream manager includes cells in the camera view cone" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "world.kdl",
        .data =
        \\world version=1 id="main" cell_size_m=256 {
        \\  cell coord="-1,0,0" authoring="scenes/west.kdl"
        \\  cell coord="0,0,0" authoring="scenes/main.kdl"
        \\  cell coord="1,0,0" authoring="scenes/east.kdl"
        \\  cell coord="0,1,0" authoring="scenes/north.kdl"
        \\}
        \\
        ,
    });

    try writeBakedCell(&tmp, .{ .x = -1, .y = 0, .z = 0 });
    try writeBakedCell(&tmp, .{ .x = 0, .y = 0, .z = 0 });
    try writeBakedCell(&tmp, .{ .x = 1, .y = 0, .z = 0 });
    try writeBakedCell(&tmp, .{ .x = 0, .y = 1, .z = 0 });

    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);
    var loaded_manifest = try manifest.loadManifest(std.testing.allocator, std.testing.io, project_path, "world.kdl");
    defer loaded_manifest.deinit();
    var manager = try StreamManager.init(std.testing.allocator, std.testing.io, project_path, "client-debug", &loaded_manifest);
    defer manager.deinit();

    manager.active_radius_cells = 0;
    manager.interior_mode = .disabled;

    const east = try manager.updateAroundView(.{
        .position = .{ .x = 128, .y = 2, .z = 128 },
        .forward = .{ .x = 1, .y = 0, .z = 0 },
        .fov_y_rad = 1.0,
        .aspect = 16.0 / 9.0,
        .far_distance_m = 300,
    });
    try std.testing.expectEqual(@as(usize, 2), east.loaded);
    try std.testing.expect(manager.active_cells.contains(.{ .x = 0, .y = 0, .z = 0 }));
    try std.testing.expect(manager.active_cells.contains(.{ .x = 1, .y = 0, .z = 0 }));
    try std.testing.expect(!manager.active_cells.contains(.{ .x = -1, .y = 0, .z = 0 }));
    try std.testing.expect(!manager.active_cells.contains(.{ .x = 0, .y = 1, .z = 0 }));

    const west = try manager.updateAroundView(.{
        .position = .{ .x = 128, .y = 2, .z = 128 },
        .forward = .{ .x = -1, .y = 0, .z = 0 },
        .fov_y_rad = 1.0,
        .aspect = 16.0 / 9.0,
        .far_distance_m = 300,
    });
    try std.testing.expectEqual(@as(usize, 1), west.loaded);
    try std.testing.expectEqual(@as(usize, 1), west.unloaded);
    try std.testing.expect(manager.active_cells.contains(.{ .x = -1, .y = 0, .z = 0 }));
    try std.testing.expect(!manager.active_cells.contains(.{ .x = 1, .y = 0, .z = 0 }));
}

test "stream manager activates async cell loads after completion" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "world.kdl",
        .data =
        \\world version=1 id="main" cell_size_m=256 {
        \\  cell coord="0,0,0" authoring="scenes/main.kdl"
        \\  cell coord="1,0,0" authoring="scenes/east.kdl"
        \\}
        \\
        ,
    });

    try writeBakedCell(&tmp, .{ .x = 0, .y = 0, .z = 0 });
    try writeBakedCell(&tmp, .{ .x = 1, .y = 0, .z = 0 });

    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);
    var loaded_manifest = try manifest.loadManifest(std.testing.allocator, std.testing.io, project_path, "world.kdl");
    defer loaded_manifest.deinit();
    var manager = try StreamManager.init(std.testing.allocator, std.testing.io, project_path, "client-debug", &loaded_manifest);
    defer manager.deinit();

    manager.active_radius_cells = 0;
    manager.interior_mode = .disabled;
    manager.max_loads_per_update = 1;
    manager.enableAsyncLoading(std.heap.smp_allocator);

    const view = root.ViewPolicy{
        .position = .{ .x = 128, .y = 2, .z = 128 },
        .forward = .{ .x = 1, .y = 0, .z = 0 },
        .fov_y_rad = 1.0,
        .aspect = 16.0 / 9.0,
        .far_distance_m = 300,
    };

    const first = try manager.updateAroundView(view);
    try std.testing.expectEqual(@as(usize, 1), first.loaded);
    try std.testing.expectEqual(@as(usize, 1), first.pending_loads);
    const first_progress = manager.progressSnapshot();
    try std.testing.expect(first_progress.async_loading);
    try std.testing.expectEqual(@as(usize, 2), first_progress.desired_cells);
    try std.testing.expectEqual(@as(usize, 1), first_progress.active_cells);
    try std.testing.expectEqual(@as(usize, 1), first_progress.pending_loads);
    try std.testing.expectEqual(@as(u64, 1), first_progress.queued_loads_total);
    try std.testing.expect(manager.active_cells.contains(.{ .x = 0, .y = 0, .z = 0 }));
    try std.testing.expect(!manager.active_cells.contains(.{ .x = 1, .y = 0, .z = 0 }));

    var attempts: usize = 0;
    while (!manager.active_cells.contains(.{ .x = 1, .y = 0, .z = 0 }) and attempts < 100) : (attempts += 1) {
        std.Thread.sleep(std.time.ns_per_ms);
        _ = try manager.updateAroundView(view);
    }
    try std.testing.expect(manager.active_cells.contains(.{ .x = 1, .y = 0, .z = 0 }));
    const final_progress = manager.progressSnapshot();
    try std.testing.expectEqual(@as(usize, 2), final_progress.active_cells);
    try std.testing.expectEqual(@as(u64, 1), final_progress.completed_loads_total);
    try std.testing.expectEqual(@as(u64, 0), final_progress.failed_loads_total);
}

test "stream manager includes interior children for active parent cell" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "world.kdl",
        .data =
        \\world version=1 id="main" cell_size_m=256 {
        \\  cell coord="0,0,0" authoring="scenes/main.kdl"
        \\  cell coord="0,0,1" authoring="scenes/interior.kdl" interior_parent="0,0,0"
        \\}
        \\
        ,
    });

    for ([_]cell.CellId{ .{ .x = 0, .y = 0, .z = 0 }, .{ .x = 0, .y = 0, .z = 1 } }) |id| {
        var one_cell = cell.WorldCellData{
            .id = id,
            .cell_size_m = 256,
            .render_meshes = try std.testing.allocator.alloc(cell.RenderMesh, 0),
            .collisions = try std.testing.allocator.alloc(cell.CollisionPlaceholder, 0),
            .instances = try std.testing.allocator.alloc(cell.InstanceRecord, 0),
            .light_probes = try std.testing.allocator.alloc(cell.LightProbeMeta, 0),
            .neighbors = try std.testing.allocator.alloc(cell.CellId, 0),
            .blobs = try std.testing.allocator.alloc(cell.CellBlob, 0),
        };
        const encoded = try fcell.encodeCell(std.testing.allocator, one_cell);
        defer std.testing.allocator.free(encoded);
        one_cell.deinit(std.testing.allocator);

        const baked_path = try fcell.bakedCellPath(std.testing.allocator, "client-debug", "main", id);
        defer std.testing.allocator.free(baked_path);
        if (std.fs.path.dirname(baked_path)) |parent| try tmp.dir.createDirPath(std.testing.io, parent);
        try tmp.dir.writeFile(std.testing.io, .{ .sub_path = baked_path, .data = encoded });
    }

    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);
    var loaded_manifest = try manifest.loadManifest(std.testing.allocator, std.testing.io, project_path, "world.kdl");
    defer loaded_manifest.deinit();
    var manager = try StreamManager.init(std.testing.allocator, std.testing.io, project_path, "client-debug", &loaded_manifest);
    defer manager.deinit();

    const update = try manager.updateAroundPosition(.{ .x = 0, .y = 0, .z = 0 });
    try std.testing.expectEqual(@as(usize, 2), update.loaded);
    try std.testing.expect(manager.active_cells.contains(.{ .x = 0, .y = 0, .z = 1 }));
}

test "stream manager can disable interior children" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "world.kdl",
        .data =
        \\world version=1 id="main" cell_size_m=256 {
        \\  cell coord="0,0,0" authoring="scenes/main.kdl"
        \\  cell coord="0,0,1" authoring="scenes/interior.kdl" interior_parent="0,0,0"
        \\}
        \\
        ,
    });

    try writeBakedCell(&tmp, .{ .x = 0, .y = 0, .z = 0 });
    try writeBakedCell(&tmp, .{ .x = 0, .y = 0, .z = 1 });

    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);
    var loaded_manifest = try manifest.loadManifest(std.testing.allocator, std.testing.io, project_path, "world.kdl");
    defer loaded_manifest.deinit();
    var manager = try StreamManager.init(std.testing.allocator, std.testing.io, project_path, "client-debug", &loaded_manifest);
    defer manager.deinit();

    manager.interior_mode = .disabled;

    const update = try manager.updateAroundPosition(.{ .x = 0, .y = 0, .z = 0 });
    try std.testing.expectEqual(@as(usize, 1), update.loaded);
    try std.testing.expect(manager.active_cells.contains(.{ .x = 0, .y = 0, .z = 0 }));
    try std.testing.expect(!manager.active_cells.contains(.{ .x = 0, .y = 0, .z = 1 }));
}

test "stream manager can budget cell loads across updates" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "world.kdl",
        .data =
        \\world version=1 id="main" cell_size_m=256 {
        \\  cell coord="-1,0,0" authoring="scenes/a.kdl"
        \\  cell coord="0,0,0" authoring="scenes/b.kdl"
        \\  cell coord="1,0,0" authoring="scenes/c.kdl"
        \\}
        \\
        ,
    });

    try writeBakedCell(&tmp, .{ .x = -1, .y = 0, .z = 0 });
    try writeBakedCell(&tmp, .{ .x = 0, .y = 0, .z = 0 });
    try writeBakedCell(&tmp, .{ .x = 1, .y = 0, .z = 0 });

    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);
    var loaded_manifest = try manifest.loadManifest(std.testing.allocator, std.testing.io, project_path, "world.kdl");
    defer loaded_manifest.deinit();
    var manager = try StreamManager.init(std.testing.allocator, std.testing.io, project_path, "client-debug", &loaded_manifest);
    defer manager.deinit();

    manager.active_radius_cells = 1;
    manager.interior_mode = .disabled;

    const first = try manager.updateAroundPositionBudgeted(.{ .x = 0, .y = 0, .z = 0 }, 1);
    try std.testing.expectEqual(@as(usize, 1), first.loaded);
    try std.testing.expectEqual(@as(usize, 2), first.pending_loads);
    try std.testing.expectEqual(@as(usize, 1), manager.activeCellCount());

    const second = try manager.updateAroundPositionBudgeted(.{ .x = 0, .y = 0, .z = 0 }, 1);
    try std.testing.expectEqual(@as(usize, 1), second.loaded);
    try std.testing.expectEqual(@as(usize, 1), second.pending_loads);
    try std.testing.expectEqual(@as(usize, 2), manager.activeCellCount());

    const third = try manager.updateAroundPositionBudgeted(.{ .x = 0, .y = 0, .z = 0 }, 1);
    try std.testing.expectEqual(@as(usize, 1), third.loaded);
    try std.testing.expectEqual(@as(usize, 0), third.pending_loads);
    try std.testing.expectEqual(@as(usize, 3), manager.activeCellCount());
}

test "stream manager hot reloads an active baked cell" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "world.kdl",
        .data =
        \\world version=1 id="main" cell_size_m=256 {
        \\  cell coord="0,0,0" authoring="scenes/main.kdl"
        \\}
        \\
        ,
    });

    const id = cell.CellId{ .x = 0, .y = 0, .z = 0 };
    try writeBakedCellWithProbe(&tmp, id, 0.5);

    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);
    var loaded_manifest = try manifest.loadManifest(std.testing.allocator, std.testing.io, project_path, "world.kdl");
    defer loaded_manifest.deinit();
    var manager = try StreamManager.init(std.testing.allocator, std.testing.io, project_path, "client-debug", &loaded_manifest);
    defer manager.deinit();
    manager.active_radius_cells = 0;

    _ = try manager.updateAroundPosition(.{ .x = 0, .y = 0, .z = 0 });
    try std.testing.expectEqual(@as(f32, 0.5), manager.active_cells.get(id).?.light_probes[0].intensity);

    try writeBakedCellWithProbe(&tmp, id, 2.0);
    try std.testing.expect(try manager.reloadActiveCell(id));
    try std.testing.expectEqual(@as(f32, 2.0), manager.active_cells.get(id).?.light_probes[0].intensity);
    try std.testing.expect(!try manager.reloadActiveCell(.{ .x = 4, .y = 0, .z = 0 }));
}

test "stream manager hot reloads all active baked cells" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "world.kdl",
        .data =
        \\world version=1 id="main" cell_size_m=256 {
        \\  cell coord="0,0,0" authoring="scenes/a.kdl"
        \\  cell coord="1,0,0" authoring="scenes/b.kdl"
        \\}
        \\
        ,
    });

    const a = cell.CellId{ .x = 0, .y = 0, .z = 0 };
    const b = cell.CellId{ .x = 1, .y = 0, .z = 0 };
    try writeBakedCellWithProbe(&tmp, a, 0.5);
    try writeBakedCellWithProbe(&tmp, b, 0.75);

    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);
    var loaded_manifest = try manifest.loadManifest(std.testing.allocator, std.testing.io, project_path, "world.kdl");
    defer loaded_manifest.deinit();
    var manager = try StreamManager.init(std.testing.allocator, std.testing.io, project_path, "client-debug", &loaded_manifest);
    defer manager.deinit();

    manager.active_radius_cells = 1;
    manager.interior_mode = .disabled;
    _ = try manager.updateAroundPosition(.{ .x = 0, .y = 0, .z = 0 });
    try std.testing.expectEqual(@as(usize, 2), manager.activeCellCount());

    try writeBakedCellWithProbe(&tmp, a, 2.0);
    try writeBakedCellWithProbe(&tmp, b, 3.0);
    const result = try manager.reloadActiveCells();
    try std.testing.expectEqual(@as(usize, 2), result.reloaded);
    try std.testing.expectEqual(@as(f32, 2.0), manager.active_cells.get(a).?.light_probes[0].intensity);
    try std.testing.expectEqual(@as(f32, 3.0), manager.active_cells.get(b).?.light_probes[0].intensity);
}

test "stream manager vertical streaming is opt in" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "world.kdl",
        .data =
        \\world version=1 id="main" cell_size_m=256 {
        \\  cell coord="0,0,0" authoring="scenes/z0.kdl"
        \\  cell coord="0,0,1" authoring="scenes/z1.kdl"
        \\  cell coord="0,0,2" authoring="scenes/z2.kdl"
        \\}
        \\
        ,
    });

    try writeBakedCell(&tmp, .{ .x = 0, .y = 0, .z = 0 });
    try writeBakedCell(&tmp, .{ .x = 0, .y = 0, .z = 1 });
    try writeBakedCell(&tmp, .{ .x = 0, .y = 0, .z = 2 });

    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);
    var loaded_manifest = try manifest.loadManifest(std.testing.allocator, std.testing.io, project_path, "world.kdl");
    defer loaded_manifest.deinit();

    var flat_manager = try StreamManager.init(std.testing.allocator, std.testing.io, project_path, "client-debug", &loaded_manifest);
    defer flat_manager.deinit();
    flat_manager.active_radius_cells = 0;
    flat_manager.interior_mode = .disabled;

    const flat_update = try flat_manager.updateAroundPosition(.{ .x = 0, .y = 300, .z = 0 });
    try std.testing.expectEqual(@as(usize, 1), flat_update.loaded);
    try std.testing.expect(flat_manager.active_cells.contains(.{ .x = 0, .y = 0, .z = 0 }));

    var vertical_manager = try StreamManager.init(std.testing.allocator, std.testing.io, project_path, "client-debug", &loaded_manifest);
    defer vertical_manager.deinit();
    vertical_manager.active_radius_cells = 0;
    vertical_manager.active_vertical_radius_cells = 1;
    vertical_manager.stream_vertical_cells = true;
    vertical_manager.interior_mode = .disabled;

    const vertical_update = try vertical_manager.updateAroundPosition(.{ .x = 0, .y = 300, .z = 0 });
    try std.testing.expectEqual(@as(usize, 3), vertical_update.loaded);
    try std.testing.expect(containsCellId(vertical_update.loaded_ids, .{ .x = 0, .y = 0, .z = 0 }));
    try std.testing.expect(containsCellId(vertical_update.loaded_ids, .{ .x = 0, .y = 0, .z = 1 }));
    try std.testing.expect(containsCellId(vertical_update.loaded_ids, .{ .x = 0, .y = 0, .z = 2 }));
}

test "stream manager rejects negative streaming radius" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

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
    var loaded_manifest = try manifest.loadManifest(std.testing.allocator, std.testing.io, project_path, "world.kdl");
    defer loaded_manifest.deinit();
    var manager = try StreamManager.init(std.testing.allocator, std.testing.io, project_path, "client-debug", &loaded_manifest);
    defer manager.deinit();

    manager.active_radius_cells = -1;
    try std.testing.expectError(
        error.InvalidStreamPolicy,
        manager.updateAroundPosition(.{ .x = 0, .y = 0, .z = 0 }),
    );

    manager.active_radius_cells = 0;
    manager.active_vertical_radius_cells = -1;
    try std.testing.expectError(
        error.InvalidStreamPolicy,
        manager.updateAroundPosition(.{ .x = 0, .y = 0, .z = 0 }),
    );
}

fn containsCellId(ids: []const cell.CellId, needle: cell.CellId) bool {
    for (ids) |id| {
        if (id.eql(needle)) return true;
    }
    return false;
}

fn writeBakedCell(tmp: *std.testing.TmpDir, id: cell.CellId) !void {
    try writeBakedCellWithProbe(tmp, id, 0);
}

fn writeBakedCellWithProbe(tmp: *std.testing.TmpDir, id: cell.CellId, intensity: f32) !void {
    var one_cell = cell.WorldCellData{
        .id = id,
        .cell_size_m = 256,
        .render_meshes = try std.testing.allocator.alloc(cell.RenderMesh, 0),
        .collisions = try std.testing.allocator.alloc(cell.CollisionPlaceholder, 0),
        .instances = try std.testing.allocator.alloc(cell.InstanceRecord, 0),
        .light_probes = try std.testing.allocator.dupe(cell.LightProbeMeta, &.{.{
            .position = .{ .x = 0, .y = 2, .z = 0 },
            .intensity = intensity,
        }}),
        .neighbors = try std.testing.allocator.alloc(cell.CellId, 0),
        .blobs = try std.testing.allocator.alloc(cell.CellBlob, 0),
    };
    const encoded = try fcell.encodeCell(std.testing.allocator, one_cell);
    defer std.testing.allocator.free(encoded);
    one_cell.deinit(std.testing.allocator);

    const baked_path = try fcell.bakedCellPath(std.testing.allocator, "client-debug", "main", id);
    defer std.testing.allocator.free(baked_path);
    if (std.fs.path.dirname(baked_path)) |parent| {
        try tmp.dir.createDirPath(std.testing.io, parent);
    }
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = baked_path, .data = encoded });
}
