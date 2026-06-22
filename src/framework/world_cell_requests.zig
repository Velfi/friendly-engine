const std = @import("std");
const framework = @import("mod.zig");
const game = @import("../game/mod.zig");
const world_mod = @import("../world/mod.zig");

pub fn describe(_: ?*anyopaque, allocator: std.mem.Allocator, payload: []const u8) ![]u8 {
    _ = payload;
    const state = game.cellState() orelse {
        return allocator.dupe(
            u8,
            "{\"active_cell_count\":0,\"nav_triangle_count\":0,\"visibility_link_count\":0,\"dependency_count\":0,\"scatter_cluster_count\":0}",
        );
    };

    return std.fmt.allocPrint(
        allocator,
        "{{\"active_cell_count\":{d},\"collision_placeholder_count\":{d},\"collision_shape_count\":{d},\"instance_count\":{d},\"light_probe_count\":{d},\"neighbor_link_count\":{d},\"nav_triangle_count\":{d},\"visibility_link_count\":{d},\"dependency_count\":{d},\"scatter_cluster_count\":{d},\"culled_cells\":{d},\"visible_meshes\":{d}}}",
        .{
            state.active_cells.items.len,
            state.collision_placeholder_count,
            state.collision_shape_count,
            state.instance_count,
            state.light_probe_count,
            state.neighbor_link_count,
            state.nav_triangle_count,
            state.visibility_link_count,
            state.dependency_count,
            state.scatter_cluster_count,
            state.culled_cells,
            state.visible_mesh_count,
        },
    );
}

pub fn reload(_: ?*anyopaque, allocator: std.mem.Allocator, payload: []const u8) ![]u8 {
    const id = try parseReloadPayload(allocator, payload);
    const stream = game.streamManager() orelse return error.NoActiveWorldStream;
    const reloaded = try stream.reloadActiveCell(id);
    if (reloaded) {
        if (game.cellState()) |cell_state| {
            const active_world = game.activeWorld() orelse return error.NoActiveWorld;
            const world_cell = stream.active_cells.getPtr(id) orelse return error.ActiveCellMissingAfterReload;
            try cell_state.reloadActiveCell(active_world, world_cell);
            try game.syncPhysicsAfterCellChange();
        }
    }

    return std.fmt.allocPrint(
        allocator,
        "{{\"cell\":[{d},{d},{d}],\"reloaded\":{s}}}",
        .{ id.x, id.y, id.z, if (reloaded) "true" else "false" },
    );
}

pub fn reloadAll(_: ?*anyopaque, allocator: std.mem.Allocator, payload: []const u8) ![]u8 {
    _ = payload;
    const stream = game.streamManager() orelse return error.NoActiveWorldStream;
    const result = try stream.reloadActiveCells();
    if (game.cellState()) |cell_state| {
        const active_world = game.activeWorld() orelse return error.NoActiveWorld;
        try cell_state.reloadFromStream(active_world, stream);
        try game.syncPhysicsAfterCellChange();
    }
    return std.fmt.allocPrint(allocator, "{{\"reloaded\":{d}}}", .{result.reloaded});
}

fn parseReloadPayload(allocator: std.mem.Allocator, payload: []const u8) !world_mod.cell.CellId {
    const Payload = struct {
        cell: []const i32,
    };
    var parsed = try std.json.parseFromSlice(Payload, allocator, payload, .{});
    defer parsed.deinit();
    if (parsed.value.cell.len != 2 and parsed.value.cell.len != 3) return error.InvalidCellReloadPayload;
    return .{
        .x = @intCast(parsed.value.cell[0]),
        .y = @intCast(parsed.value.cell[1]),
        .z = if (parsed.value.cell.len == 3) @intCast(parsed.value.cell[2]) else 0,
    };
}

test "world cells describe returns streamed cell counters" {
    var state = game.cell_spawn.CellSpawnState.init(std.testing.allocator);
    defer state.deinit();
    game.setCellState(&state);
    defer game.setCellState(null);

    const response = try describe(null, std.testing.allocator, "{}");
    defer std.testing.allocator.free(response);
    try std.testing.expect(std.mem.indexOf(u8, response, "active_cell_count") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "nav_triangle_count") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "scatter_cluster_count") != null);
}

test "world cells reload payload parses cell id" {
    const id = try parseReloadPayload(std.testing.allocator, "{\"cell\":[4,-2,1]}");
    try std.testing.expect(id.eql(.{ .x = 4, .y = -2, .z = 1 }));

    const flat_id = try parseReloadPayload(std.testing.allocator, "{\"cell\":[4,-2]}");
    try std.testing.expect(flat_id.eql(.{ .x = 4, .y = -2, .z = 0 }));
}

test "world cells reload rejects malformed payload" {
    try std.testing.expectError(
        error.InvalidCellReloadPayload,
        parseReloadPayload(std.testing.allocator, "{\"cell\":[1]}"),
    );
}

test "world cells reload request refreshes active stream and cell state" {
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

    const id = world_mod.cell.CellId{ .x = 0, .y = 0, .z = 0 };
    try writeBakedProbeCell(&tmp, id, 0.5);

    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);
    var loaded_manifest = try world_mod.manifest.loadManifest(std.testing.allocator, std.testing.io, project_path, "world.kdl");
    defer loaded_manifest.deinit();

    var stream = try world_mod.stream.StreamManager.init(
        std.testing.allocator,
        std.testing.io,
        project_path,
        "client-debug",
        &loaded_manifest,
    );
    defer stream.deinit();
    stream.active_radius_cells = 0;
    _ = try stream.updateAroundPosition(.{ .x = 0, .y = 0, .z = 0 });

    var framework_world = framework.World.init(std.testing.allocator);
    defer framework_world.deinit();
    var cell_state = game.cell_spawn.CellSpawnState.init(std.testing.allocator);
    defer cell_state.deinit();
    try cell_state.syncFromStream(&framework_world, &stream);
    try std.testing.expectEqual(@as(f32, 0.5), cell_state.light_probes.items[0].intensity);

    game.setActiveWorld(&framework_world);
    defer game.setActiveWorld(null);
    game.setStreamManager(&stream);
    defer game.setStreamManager(null);
    game.setCellState(&cell_state);
    defer game.setCellState(null);

    try writeBakedProbeCell(&tmp, id, 3.0);
    const response = try reload(null, std.testing.allocator, "{\"cell\":[0,0,0]}");
    defer std.testing.allocator.free(response);

    try std.testing.expect(std.mem.indexOf(u8, response, "\"reloaded\":true") != null);
    try std.testing.expectEqual(@as(f32, 3.0), stream.active_cells.get(id).?.light_probes[0].intensity);
    try std.testing.expectEqual(@as(f32, 3.0), cell_state.light_probes.items[0].intensity);
}

test "world cells reload all request refreshes active stream and cell state" {
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

    const a = world_mod.cell.CellId{ .x = 0, .y = 0, .z = 0 };
    const b = world_mod.cell.CellId{ .x = 1, .y = 0, .z = 0 };
    try writeBakedProbeCell(&tmp, a, 0.5);
    try writeBakedProbeCell(&tmp, b, 0.75);

    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);
    var loaded_manifest = try world_mod.manifest.loadManifest(std.testing.allocator, std.testing.io, project_path, "world.kdl");
    defer loaded_manifest.deinit();
    var stream = try world_mod.stream.StreamManager.init(
        std.testing.allocator,
        std.testing.io,
        project_path,
        "client-debug",
        &loaded_manifest,
    );
    defer stream.deinit();
    stream.active_radius_cells = 1;
    stream.interior_mode = .disabled;
    _ = try stream.updateAroundPosition(.{ .x = 0, .y = 0, .z = 0 });

    var framework_world = framework.World.init(std.testing.allocator);
    defer framework_world.deinit();
    var cell_state = game.cell_spawn.CellSpawnState.init(std.testing.allocator);
    defer cell_state.deinit();
    try cell_state.syncFromStream(&framework_world, &stream);

    game.setActiveWorld(&framework_world);
    defer game.setActiveWorld(null);
    game.setStreamManager(&stream);
    defer game.setStreamManager(null);
    game.setCellState(&cell_state);
    defer game.setCellState(null);

    try writeBakedProbeCell(&tmp, a, 4.0);
    try writeBakedProbeCell(&tmp, b, 5.0);
    const response = try reloadAll(null, std.testing.allocator, "{}");
    defer std.testing.allocator.free(response);

    try std.testing.expect(std.mem.indexOf(u8, response, "\"reloaded\":2") != null);
    try std.testing.expectEqual(@as(usize, 2), cell_state.light_probes.items.len);
    try std.testing.expectEqual(@as(f32, 4.0), stream.active_cells.get(a).?.light_probes[0].intensity);
    try std.testing.expectEqual(@as(f32, 5.0), stream.active_cells.get(b).?.light_probes[0].intensity);
}

fn writeBakedProbeCell(tmp: *std.testing.TmpDir, id: world_mod.cell.CellId, intensity: f32) !void {
    var one_cell = world_mod.cell.WorldCellData{
        .id = id,
        .cell_size_m = 256,
        .render_meshes = try std.testing.allocator.alloc(world_mod.cell.RenderMesh, 0),
        .collisions = try std.testing.allocator.alloc(world_mod.cell.CollisionPlaceholder, 0),
        .instances = try std.testing.allocator.alloc(world_mod.cell.InstanceRecord, 0),
        .light_probes = try std.testing.allocator.dupe(world_mod.cell.LightProbeMeta, &.{.{
            .position = .{ .x = 0, .y = 2, .z = 0 },
            .intensity = intensity,
        }}),
        .neighbors = try std.testing.allocator.alloc(world_mod.cell.CellId, 0),
        .blobs = try std.testing.allocator.alloc(world_mod.cell.CellBlob, 0),
    };
    const encoded = try world_mod.fcell.encodeCell(std.testing.allocator, one_cell);
    defer std.testing.allocator.free(encoded);
    one_cell.deinit(std.testing.allocator);

    const baked_path = try world_mod.fcell.bakedCellPath(std.testing.allocator, "client-debug", "main", id);
    defer std.testing.allocator.free(baked_path);
    if (std.fs.path.dirname(baked_path)) |parent| {
        try tmp.dir.createDirPath(std.testing.io, parent);
    }
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = baked_path, .data = encoded });
}
