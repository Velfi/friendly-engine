const std = @import("std");
const friendly_engine = @import("friendly_engine");
const editor_command_file = @import("editor_command_file.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_world_authoring = @import("project_editor_world_authoring.zig");

const CommandFile = editor_command_file.CommandFile;
const ProjectEditorState = project_editor_state.ProjectEditorState;
const spline_authoring = friendly_engine.modules.splines.authoring;

pub fn handle(allocator: std.mem.Allocator, command: CommandFile, state: *ProjectEditorState) ![]u8 {
    var doc = try spline_authoring.load(state.allocator, state.io, state.project_path, state.active_world_manifest_path);
    defer doc.deinit();

    if (std.mem.eql(u8, command.name, "road.network-describe")) {
        return roadNetworkJson(allocator, command, state, &doc, null);
    }
    if (std.mem.eql(u8, command.name, "road.network-validate")) {
        const graph_issues = try doc.validateGraph(allocator);
        defer allocator.free(graph_issues);
        var issue_list = std.ArrayList(spline_authoring.ValidationIssue).empty;
        defer issue_list.deinit(allocator);
        try issue_list.appendSlice(allocator, graph_issues);
        project_editor_world_authoring.validateConformingRoadTerrain(state, &doc) catch |err| {
            try issue_list.append(allocator, .{ .code = @errorName(err), .id = "terrain" });
        };
        const issues = try issue_list.toOwnedSlice(allocator);
        defer allocator.free(issues);
        return roadNetworkJson(allocator, command, state, &doc, issues);
    }
    if (std.mem.eql(u8, command.name, "road.graph-list")) {
        return roadGraphListJson(allocator, command, &doc);
    }

    var status: []const u8 = "Road graph updated";
    const primary_id = command.object orelse return error.MissingObject;
    var removed_edges: usize = 0;
    var persist_change: []const u8 = "road graph";

    if (std.mem.eql(u8, command.name, "road.node-add")) {
        if (doc.nodeIndexById(primary_id) != null) return error.DuplicateRoadNode;
        try doc.upsertRoadNode(.{
            .id = primary_id,
            .position = try commandRoadPoint(command),
            .kind = try spline_authoring.RoadNodeKind.parse(command.operation orelse "endpoint"),
            .terrain_mode = try spline_authoring.RoadTerrainMode.parse(command.terrain_mode orelse "conform"),
        });
        status = "Road node added";
    } else if (std.mem.eql(u8, command.name, "road.node-move")) {
        try doc.moveRoadNode(primary_id, try commandRoadPoint(command));
        status = "Road node moved";
    } else if (std.mem.eql(u8, command.name, "road.node-delete")) {
        removed_edges = try doc.deleteRoadNodeCascade(primary_id);
        status = "Road node deleted";
    } else if (std.mem.eql(u8, command.name, "road.node-promote-junction")) {
        try doc.promoteRoadNode(primary_id);
        status = "Road node promoted";
    } else if (std.mem.eql(u8, command.name, "road.node-merge")) {
        try doc.mergeRoadNodes(primary_id, command.parent orelse return error.MissingRoadNode);
        status = "Road nodes merged";
    } else if (std.mem.eql(u8, command.name, "road.edge-add")) {
        const edge = try commandRoadEdge(state.allocator, command, &doc, primary_id);
        defer freeRoadEdgeInput(state.allocator, edge);
        try doc.upsertRoadEdge(edge);
        status = "Road edge added";
    } else if (std.mem.eql(u8, command.name, "road.edge-update")) {
        const existing = doc.roadEdgePtrConst(primary_id) orelse return error.MissingRoadEdge;
        const edge = try commandRoadEdgeUpdate(state.allocator, command, &doc, existing);
        defer freeRoadEdgeInput(state.allocator, edge);
        try doc.updateRoadEdge(edge);
        status = "Road edge updated";
    } else if (std.mem.eql(u8, command.name, "road.edge-delete")) {
        try doc.deleteRoadEdge(primary_id);
        removed_edges = 1;
        status = "Road edge deleted";
    } else if (std.mem.eql(u8, command.name, "road.edge-split")) {
        try doc.splitRoadEdge(primary_id, command.parent orelse return error.MissingRoadNode, command.element orelse return error.MissingRoadEdge, try commandRoadPoint(command));
        status = "Road edge split";
    } else {
        return error.UnknownRoadGraphCommand;
    }

    if (std.mem.startsWith(u8, command.name, "road.node-")) persist_change = "road node graph";
    if (std.mem.startsWith(u8, command.name, "road.edge-")) persist_change = "road edge graph";
    try project_editor_world_authoring.persistRoadGraphDoc(state, doc, persist_change, true);
    project_editor_state.setStatus(state, status);
    return roadMutationJson(allocator, command, state, &doc, status, primary_id, removed_edges);
}

fn commandRoadPoint(command: CommandFile) !friendly_engine.core.math.Vec3f {
    return .{
        .x = command.point_x orelse return error.MissingPoint,
        .y = command.point_y orelse 0,
        .z = command.point_z orelse return error.MissingPoint,
    };
}

fn commandRoadEdge(
    allocator: std.mem.Allocator,
    command: CommandFile,
    doc: *const spline_authoring.SplinesAuthoringDoc,
    edge_id: []const u8,
) !spline_authoring.RoadEdgeInput {
    const start_id = command.parent orelse return error.MissingRoadNode;
    const end_id = command.element orelse return error.MissingRoadNode;
    const start = doc.road_nodes.items[doc.nodeIndexById(start_id) orelse return error.MissingRoadNode].position;
    const end = doc.road_nodes.items[doc.nodeIndexById(end_id) orelse return error.MissingRoadNode].position;
    const owned_start = try allocator.dupe(u8, start_id);
    errdefer allocator.free(owned_start);
    const owned_end = try allocator.dupe(u8, end_id);
    errdefer allocator.free(owned_end);
    const decal_material = try allocator.dupe(u8, command.material_path orelse "road.dirt");
    errdefer allocator.free(decal_material);
    const prop_asset_id = try allocator.dupe(u8, command.asset orelse "");
    errdefer allocator.free(prop_asset_id);
    return .{
        .id = edge_id,
        .start_node_id = owned_start,
        .end_node_id = owned_end,
        .handle_start = lerpRoadPoint(start, end, 0.33),
        .handle_end = lerpRoadPoint(start, end, 0.66),
        .width = command.width orelse return error.MissingWidth,
        .elevation = command.height orelse 0.02,
        .material_mask_value = command.a orelse 255,
        .render_mode = try spline_authoring.RoadRenderMode.parse(command.render_mode orelse "decal"),
        .terrain_mode = try spline_authoring.RoadTerrainMode.parse(command.terrain_mode orelse "conform"),
        .decal_material = decal_material,
        .prop_asset_id = prop_asset_id,
    };
}

fn commandRoadEdgeUpdate(
    allocator: std.mem.Allocator,
    command: CommandFile,
    doc: *const spline_authoring.SplinesAuthoringDoc,
    existing: *const spline_authoring.OwnedRoadEdge,
) !spline_authoring.RoadEdgeInput {
    const start_id = command.parent orelse existing.start_node_id;
    const end_id = command.element orelse existing.end_node_id;
    const start = doc.road_nodes.items[doc.nodeIndexById(start_id) orelse return error.MissingRoadNode].position;
    const end = doc.road_nodes.items[doc.nodeIndexById(end_id) orelse return error.MissingRoadNode].position;
    const owned_start = try allocator.dupe(u8, start_id);
    errdefer allocator.free(owned_start);
    const owned_end = try allocator.dupe(u8, end_id);
    errdefer allocator.free(owned_end);
    const decal_material = try allocator.dupe(u8, command.material_path orelse existing.decal_material);
    errdefer allocator.free(decal_material);
    const prop_asset_id = try allocator.dupe(u8, command.asset orelse existing.prop_asset_id);
    errdefer allocator.free(prop_asset_id);
    return .{
        .id = existing.id,
        .start_node_id = owned_start,
        .end_node_id = owned_end,
        .handle_start = lerpRoadPoint(start, end, 0.33),
        .handle_end = lerpRoadPoint(start, end, 0.66),
        .width = command.width orelse existing.width,
        .elevation = command.height orelse existing.elevation,
        .material_mask_value = command.a orelse existing.material_mask_value,
        .render_mode = if (command.render_mode) |mode| try spline_authoring.RoadRenderMode.parse(mode) else existing.render_mode,
        .terrain_mode = if (command.terrain_mode) |mode| try spline_authoring.RoadTerrainMode.parse(mode) else existing.terrain_mode,
        .decal_material = decal_material,
        .prop_asset_id = prop_asset_id,
    };
}

fn freeRoadEdgeInput(allocator: std.mem.Allocator, input: spline_authoring.RoadEdgeInput) void {
    allocator.free(input.start_node_id);
    allocator.free(input.end_node_id);
    allocator.free(input.decal_material);
    allocator.free(input.prop_asset_id);
}

fn lerpRoadPoint(a: friendly_engine.core.math.Vec3f, b: friendly_engine.core.math.Vec3f, t: f32) friendly_engine.core.math.Vec3f {
    return .{
        .x = a.x + (b.x - a.x) * t,
        .y = a.y + (b.y - a.y) * t,
        .z = a.z + (b.z - a.z) * t,
    };
}

fn roadMutationJson(
    allocator: std.mem.Allocator,
    command: CommandFile,
    state: *const ProjectEditorState,
    doc: *const spline_authoring.SplinesAuthoringDoc,
    status: []const u8,
    primary_id: []const u8,
    removed_edges: usize,
) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, 512);
    defer out.deinit(allocator);
    try appendFmt(allocator, &out, "{{\"ok\":true,\"id\":", .{});
    try appendJsonString(allocator, &out, command.id);
    try appendFmt(allocator, &out, ",\"command\":", .{});
    try appendJsonString(allocator, &out, command.name);
    try appendFmt(allocator, &out, ",\"target\":", .{});
    try appendJsonString(allocator, &out, primary_id);
    try appendFmt(allocator, &out, ",\"nodes\":{d},\"edges\":{d},\"removed_edges\":{d},\"dirty_cells\":{d},\"status\":", .{ doc.road_nodes.items.len, doc.road_edges.items.len, removed_edges, state.dirty_cells.count });
    try appendJsonString(allocator, &out, status);
    try appendFmt(allocator, &out, "}}\n", .{});
    return out.toOwnedSlice(allocator);
}

fn roadNetworkJson(
    allocator: std.mem.Allocator,
    command: CommandFile,
    state: *const ProjectEditorState,
    doc: *const spline_authoring.SplinesAuthoringDoc,
    validation_issues: ?[]const spline_authoring.ValidationIssue,
) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, 768);
    defer out.deinit(allocator);
    var min_x: f32 = std.math.inf(f32);
    var min_z: f32 = std.math.inf(f32);
    var max_x: f32 = -std.math.inf(f32);
    var max_z: f32 = -std.math.inf(f32);
    for (doc.road_nodes.items) |node| {
        min_x = @min(min_x, node.position.x);
        min_z = @min(min_z, node.position.z);
        max_x = @max(max_x, node.position.x);
        max_z = @max(max_z, node.position.z);
    }
    const has_bounds = doc.road_nodes.items.len > 0;
    try appendFmt(allocator, &out, "{{\"ok\":true,\"id\":", .{});
    try appendJsonString(allocator, &out, command.id);
    try appendFmt(allocator, &out, ",\"command\":", .{});
    try appendJsonString(allocator, &out, command.name);
    try appendFmt(allocator, &out, ",\"nodes\":{d},\"edges\":{d},\"dirty_cells\":{d},\"bounds\":", .{ doc.road_nodes.items.len, doc.road_edges.items.len, state.dirty_cells.count });
    if (has_bounds) {
        try appendFmt(allocator, &out, "{{\"min_x\":{d:.6},\"min_z\":{d:.6},\"max_x\":{d:.6},\"max_z\":{d:.6}}}", .{ min_x, min_z, max_x, max_z });
    } else {
        try appendFmt(allocator, &out, "null", .{});
    }
    if (validation_issues) |issues| {
        try appendFmt(allocator, &out, ",\"valid\":{},\"validation_errors\":[", .{issues.len == 0});
        for (issues, 0..) |issue, index| {
            if (index > 0) try appendFmt(allocator, &out, ",", .{});
            try appendFmt(allocator, &out, "{{\"code\":", .{});
            try appendJsonString(allocator, &out, issue.code);
            try appendFmt(allocator, &out, ",\"id\":", .{});
            try appendJsonString(allocator, &out, issue.id);
            try appendFmt(allocator, &out, "}}", .{});
        }
        try appendFmt(allocator, &out, "]", .{});
    }
    try appendFmt(allocator, &out, "}}\n", .{});
    return out.toOwnedSlice(allocator);
}

fn roadGraphListJson(
    allocator: std.mem.Allocator,
    command: CommandFile,
    doc: *const spline_authoring.SplinesAuthoringDoc,
) ![]u8 {
    const total = doc.road_nodes.items.len + doc.road_edges.items.len;
    const offset: usize = @intCast(@min(command.offset orelse 0, total));
    const limit: usize = @intCast(@min(command.limit orelse 64, 512));
    const end = @min(total, offset + limit);
    var out = try std.ArrayList(u8).initCapacity(allocator, 1024);
    defer out.deinit(allocator);
    try appendFmt(allocator, &out, "{{\"ok\":true,\"id\":", .{});
    try appendJsonString(allocator, &out, command.id);
    try appendFmt(allocator, &out, ",\"command\":", .{});
    try appendJsonString(allocator, &out, command.name);
    try appendFmt(allocator, &out, ",\"count\":{d},\"offset\":{d},\"limit\":{d},\"returned\":{d},\"has_more\":{},\"items\":[", .{ total, offset, limit, end - offset, end < total });
    var index = offset;
    while (index < end) : (index += 1) {
        if (index > offset) try appendFmt(allocator, &out, ",", .{});
        if (index < doc.road_nodes.items.len) {
            const node = doc.road_nodes.items[index];
            try appendFmt(allocator, &out, "{{\"type\":\"node\",\"id\":", .{});
            try appendJsonString(allocator, &out, node.id);
            try appendFmt(allocator, &out, ",\"kind\":\"{s}\",\"terrain_mode\":\"{s}\",\"position\":{{\"x\":{d:.6},\"y\":{d:.6},\"z\":{d:.6}}}}}", .{ node.kind.name(), node.terrain_mode.name(), node.position.x, node.position.y, node.position.z });
        } else {
            const edge = doc.road_edges.items[index - doc.road_nodes.items.len];
            try appendFmt(allocator, &out, "{{\"type\":\"edge\",\"id\":", .{});
            try appendJsonString(allocator, &out, edge.id);
            try appendFmt(allocator, &out, ",\"start\":", .{});
            try appendJsonString(allocator, &out, edge.start_node_id);
            try appendFmt(allocator, &out, ",\"end\":", .{});
            try appendJsonString(allocator, &out, edge.end_node_id);
            try appendFmt(allocator, &out, ",\"width\":{d:.6},\"elevation\":{d:.6},\"material_mask_value\":{d},\"render_mode\":\"{s}\",\"terrain_mode\":\"{s}\",\"decal_material\":", .{ edge.width, edge.elevation, edge.material_mask_value, edge.render_mode.name(), edge.terrain_mode.name() });
            try appendJsonString(allocator, &out, edge.decal_material);
            try appendFmt(allocator, &out, ",\"prop_asset_id\":", .{});
            try appendJsonString(allocator, &out, edge.prop_asset_id);
            try appendFmt(allocator, &out, "}}", .{});
        }
    }
    try appendFmt(allocator, &out, "]}}\n", .{});
    return out.toOwnedSlice(allocator);
}

fn appendJsonString(allocator: std.mem.Allocator, out: *std.ArrayList(u8), value: []const u8) !void {
    try out.append(allocator, '"');
    for (value) |ch| {
        switch (ch) {
            '"' => try out.appendSlice(allocator, "\\\""),
            '\\' => try out.appendSlice(allocator, "\\\\"),
            '\n' => try out.appendSlice(allocator, "\\n"),
            '\r' => try out.appendSlice(allocator, "\\r"),
            '\t' => try out.appendSlice(allocator, "\\t"),
            else => {
                if (ch < 0x20) {
                    try appendFmt(allocator, out, "\\u{x:0>4}", .{ch});
                } else {
                    try out.append(allocator, ch);
                }
            },
        }
    }
    try out.append(allocator, '"');
}

fn appendFmt(allocator: std.mem.Allocator, out: *std.ArrayList(u8), comptime fmt: []const u8, args: anytype) !void {
    const text = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(text);
    try out.appendSlice(allocator, text);
}
