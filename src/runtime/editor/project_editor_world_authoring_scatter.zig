const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const editor_math = shared.editor_math;

const project_editor_state = @import("project_editor_state.zig");
const project_editor_types = @import("project_editor_types.zig");
const project_editor_scatter_preview = @import("project_editor_scatter_preview.zig");
const manifest = @import("project_editor_world_authoring_manifest.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const WorldLayerId = project_editor_types.WorldLayerId;
const modules = friendly_engine.modules;

pub fn seedScatter(state: *ProjectEditorState) !void {
    try seedScatterAt(state, state.camera.target);
}

pub fn seedScatterAt(state: *ProjectEditorState, point: editor_math.Vec3) !void {
    const layer = resolveScatterLayer(state);
    if (layer != .scatter_grass_low and layer != .scatter_pine_cluster and layer != .scatter_rocks_medium) {
        project_editor_state.setStatus(state, "Select scatter layer: grass_low, pine_cluster, or rocks_medium");
        return manifest.WorldLayerNotScatter;
    }
    const prototype: []const u8 = switch (layer) {
        .scatter_grass_low => "scatter.grass",
        .scatter_pine_cluster => "scatter.pine",
        .scatter_rocks_medium => "scatter.rocks",
        else => unreachable,
    };
    const density: f32 = switch (layer) {
        .scatter_grass_low => 0.65,
        .scatter_pine_cluster => 0.35,
        .scatter_rocks_medium => 0.2,
        else => unreachable,
    };
    const id = try manifest.cellForPoint(state, point);
    var rule_id_buf: [48]u8 = undefined;
    const rule_id = try std.fmt.bufPrint(&rule_id_buf, "{s}_editor", .{layer.label()});
    try modules.scatter.authoring.upsertRuleFile(state.allocator, state.io, state.project_path, try manifest.pathForState(state), .{
        .id = rule_id,
        .cell = .{ id.x, id.y, id.z },
        .prototype = prototype,
        .density = density,
        .spacing = 12,
        .slope_min = 0,
        .slope_max = 45,
        .biome = "meadow",
    });
    project_editor_scatter_preview.markStale(state);
    try project_editor_state.markDirtyCell(state, "Scatter", id, layer.label());
}

pub fn beginScatterZoneDrag(state: *ProjectEditorState, screen_x: f32, screen_y: f32) void {
    const pt = @import("project_editor_blockout.zig").screenToGroundPoint(state, screen_x, screen_y) orelse return;
    state.world_scatter_drag_start = pt;
    state.world_scatter_drag_end = pt;
}

pub fn updateScatterZoneDrag(state: *ProjectEditorState, screen_x: f32, screen_y: f32) void {
    const pt = @import("project_editor_blockout.zig").screenToGroundPoint(state, screen_x, screen_y) orelse return;
    state.world_scatter_drag_end = pt;
}

pub fn finishScatterZoneDrag(state: *ProjectEditorState) void {
    const start = state.world_scatter_drag_start orelse return;
    const end = state.world_scatter_drag_end orelse return;
    defer {
        state.world_scatter_drag_start = null;
        state.world_scatter_drag_end = null;
    }

    const dx = end.x - start.x;
    const dz = end.z - start.z;
    if (dx * dx + dz * dz < project_editor_types.click_drag_threshold_sq) {
        seedScatterAt(state, start) catch {
            project_editor_state.setStatus(state, "Scatter layer write failed");
        };
        return;
    }

    addExclusionZoneFromDrag(state, start, end) catch {
        project_editor_state.setStatus(state, "Scatter exclusion write failed");
    };
}

fn addExclusionZoneFromDrag(state: *ProjectEditorState, start: editor_math.Vec3, end: editor_math.Vec3) !void {
    const min_x = @min(start.x, end.x);
    const max_x = @max(start.x, end.x);
    const min_z = @min(start.z, end.z);
    const max_z = @max(start.z, end.z);
    const center = manifest.midpoint(start, end);
    const id = try manifest.cellForPoint(state, center);
    try modules.scatter.authoring.appendExclusionFile(state.allocator, state.io, state.project_path, try manifest.pathForState(state), .{
        .cell = .{ id.x, id.y, id.z },
        .min = .{ min_x, 0, min_z },
        .max = .{ max_x, 4, max_z },
    });
    project_editor_scatter_preview.markStale(state);
    try project_editor_state.markDirtyCell(state, "Scatter", id, "exclusion zone");
}

fn resolveScatterLayer(state: *const ProjectEditorState) WorldLayerId {
    const layer = state.selected_world_layer orelse .scatter_grass_low;
    if (layer == .scatter_grass_low or layer == .scatter_pine_cluster or layer == .scatter_rocks_medium) return layer;
    return .scatter_grass_low;
}

test "scatter exclusion drag writes zone and marks dirty" {
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
        .selected_world_layer = .scatter_grass_low,
    };

    state.world_scatter_drag_start = .{ .x = 10, .y = 0, .z = 10 };
    state.world_scatter_drag_end = .{ .x = 30, .y = 0, .z = 30 };
    finishScatterZoneDrag(&state);

    try std.testing.expectEqual(@as(usize, 1), state.dirty_cells.count);
    try std.testing.expectEqualStrings("exclusion zone", state.dirty_cells.last().?.last_change);
    const bytes = try tmp.dir.readFileAlloc(std.testing.io, "layers/scatter.kdl", std.testing.allocator, .limited(8192));
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "exclusion ") != null);
}

test "scatter seed marks dirty cell and writes layer file" {
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
        .selected_world_layer = .scatter_grass_low,
    };

    try seedScatterAt(&state, .{ .x = 96, .y = 0, .z = 128 });

    try std.testing.expectEqual(@as(usize, 1), state.dirty_cells.count);
    const dirty = state.dirty_cells.last().?;
    try std.testing.expectEqualStrings("Scatter", dirty.layer_name);
    try std.testing.expectEqualStrings("grass_low", dirty.last_change);

    const bytes = try tmp.dir.readFileAlloc(std.testing.io, "layers/scatter.kdl", std.testing.allocator, .limited(8192));
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "grass_low_editor") != null);
}
