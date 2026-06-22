const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_types = @import("project_editor_types.zig");

const editor_math = shared.editor_math;
const shared_color = shared.color;
const spline_authoring = friendly_engine.modules.splines.authoring;
const ProjectEditorState = project_editor_state.ProjectEditorState;

pub const RoadHitKind = enum { node, edge, handle_start, handle_end };

pub const RoadHit = struct {
    kind: RoadHitKind,
    id: []u8,
    index: usize,
};

pub const RoadSnapKind = enum { node, edge };

pub const RoadSnapTarget = struct {
    kind: RoadSnapKind,
    id: []u8,
    point: editor_math.Vec3,
    distance_sq: f32,
};

pub const road_width_rail_samples: usize = 12;

pub fn roadHitToWorldCurveHit(hit: RoadHit) project_editor_types.WorldCurveHit {
    return .{
        .target = .road,
        .element = switch (hit.kind) {
            .node => .point,
            .edge => .segment,
            .handle_start => .handle_start,
            .handle_end => .handle_end,
        },
        .index = hit.index,
    };
}

pub fn applyRoadHitIndexToSelectedCurveHit(state: *ProjectEditorState, hit: RoadHit) void {
    if (state.selected_world_curve_hit.target != .road) return;
    state.selected_world_curve_hit.index = hit.index;
}

pub fn roadEdgeIndexById(doc: *const spline_authoring.SplinesAuthoringDoc, edge_id: []const u8) ?usize {
    for (doc.road_edges.items, 0..) |edge, index| {
        if (std.mem.eql(u8, edge.id, edge_id)) return index;
    }
    return null;
}

pub fn nearestPointOnWorldSegment(
    screen_x: f32,
    screen_y: f32,
    a_screen: editor_math.Vec2,
    b_screen: editor_math.Vec2,
    a_world: editor_math.Vec3,
    b_world: editor_math.Vec3,
) editor_math.Vec3 {
    const vx = b_screen.x - a_screen.x;
    const vy = b_screen.y - a_screen.y;
    const len_sq = vx * vx + vy * vy;
    const t = if (len_sq <= 0.0001) 0 else std.math.clamp(((screen_x - a_screen.x) * vx + (screen_y - a_screen.y) * vy) / len_sq, 0, 1);
    return lerpVec3(a_world, b_world, t);
}

pub fn roadNodePosition(doc: *const spline_authoring.SplinesAuthoringDoc, node_id: []const u8) ?friendly_engine.core.math.Vec3f {
    const index = doc.nodeIndexById(node_id) orelse return null;
    return doc.road_nodes.items[index].position;
}

pub fn roadNodeDegree(doc: *const spline_authoring.SplinesAuthoringDoc, node_id: []const u8) usize {
    var degree: usize = 0;
    for (doc.road_edges.items) |edge| {
        if (std.mem.eql(u8, edge.start_node_id, node_id) or std.mem.eql(u8, edge.end_node_id, node_id)) degree += 1;
    }
    return degree;
}

pub fn uniqueRoadNodeId(allocator: std.mem.Allocator, doc: *const spline_authoring.SplinesAuthoringDoc) ![]u8 {
    var index: usize = doc.road_nodes.items.len + 1;
    while (true) : (index += 1) {
        const id = try std.fmt.allocPrint(allocator, "road_point_{d}", .{index});
        if (doc.nodeIndexById(id) == null) return id;
        allocator.free(id);
    }
}

pub fn uniqueRoadEdgeId(allocator: std.mem.Allocator, doc: *const spline_authoring.SplinesAuthoringDoc) ![]u8 {
    var index: usize = doc.road_edges.items.len + 1;
    while (true) : (index += 1) {
        const id = try std.fmt.allocPrint(allocator, "road_segment_{d}", .{index});
        if (doc.roadEdgePtrConst(id) == null) return id;
        allocator.free(id);
    }
}

pub fn sampleRoadCurve(
    a: friendly_engine.core.math.Vec3f,
    h0: friendly_engine.core.math.Vec3f,
    h1: friendly_engine.core.math.Vec3f,
    b: friendly_engine.core.math.Vec3f,
    t: f32,
) friendly_engine.core.math.Vec3f {
    const inv = 1.0 - t;
    const aa = inv * inv * inv;
    const bb = 3.0 * inv * inv * t;
    const cc = 3.0 * inv * t * t;
    const dd = t * t * t;
    return .{
        .x = a.x * aa + h0.x * bb + h1.x * cc + b.x * dd,
        .y = a.y * aa + h0.y * bb + h1.y * cc + b.y * dd,
        .z = a.z * aa + h0.z * bb + h1.z * cc + b.z * dd,
    };
}

pub fn lerpVec3(a: friendly_engine.core.math.Vec3f, b: friendly_engine.core.math.Vec3f, t: f32) friendly_engine.core.math.Vec3f {
    return .{
        .x = a.x + (b.x - a.x) * t,
        .y = a.y + (b.y - a.y) * t,
        .z = a.z + (b.z - a.z) * t,
    };
}

pub fn distanceSq(ax: f32, ay: f32, bx: f32, by: f32) f32 {
    const dx = ax - bx;
    const dy = ay - by;
    return dx * dx + dy * dy;
}

pub fn roadJoinPreviewColor(kind: RoadSnapKind) shared_color.Color {
    return switch (kind) {
        .node => .{ .r = 120, .g = 235, .b = 255, .a = 180 },
        .edge => .{ .r = 255, .g = 185, .b = 95, .a = 190 },
    };
}

pub fn roadWidthRailSampleT(sample_index: usize) f32 {
    return @as(f32, @floatFromInt(sample_index)) / @as(f32, @floatFromInt(road_width_rail_samples));
}

pub fn roadTerrainOverlayColor(mode: spline_authoring.RoadTerrainMode, base: shared_color.Color) shared_color.Color {
    return switch (mode) {
        .conform => base,
        .floating => .{
            .r = @intCast((@as(u16, base.r) * 2 + 80) / 3),
            .g = @intCast((@as(u16, base.g) * 2 + 235) / 3),
            .b = @intCast((@as(u16, base.b) * 2 + 255) / 3),
            .a = base.a,
        },
        .tunnel_reserved => .{
            .r = @intCast((@as(u16, base.r) * 2 + 255) / 3),
            .g = @intCast((@as(u16, base.g) * 2 + 95) / 3),
            .b = @intCast((@as(u16, base.b) * 2 + 165) / 3),
            .a = base.a,
        },
    };
}

pub fn roadTerrainOverlayRailColor(mode: spline_authoring.RoadTerrainMode) shared_color.Color {
    return switch (mode) {
        .conform => .{ .r = 255, .g = 238, .b = 155, .a = 175 },
        .floating => .{ .r = 120, .g = 230, .b = 255, .a = 185 },
        .tunnel_reserved => .{ .r = 255, .g = 125, .b = 185, .a = 185 },
    };
}

pub fn roadPassiveHandleColor(mode: project_editor_types.RoadToolMode, base: shared_color.Color) shared_color.Color {
    var color = base;
    color.a = switch (mode) {
        .select, .shape => base.a,
        .join => @min(base.a, 160),
        .surface => @min(base.a, 115),
        .draw => base.a,
    };
    return color;
}

pub fn roadHandleArmLineColor(mode: project_editor_types.RoadToolMode, base: shared_color.Color, active: bool) shared_color.Color {
    if (active) return base;
    var color = base;
    color.a = switch (mode) {
        .select, .shape => @min(base.a, 180),
        .join => @min(base.a, 120),
        .surface => @min(base.a, 90),
        .draw => base.a,
    };
    return color;
}

test "road join preview colors distinguish point and segment targets" {
    const node = roadJoinPreviewColor(.node);
    const edge = roadJoinPreviewColor(.edge);

    try std.testing.expect(node.b > node.r);
    try std.testing.expect(edge.r > edge.b);
    try std.testing.expect(edge.a >= node.a);
}

test "road curve width rail samples cover full curve" {
    try std.testing.expectEqual(@as(f32, 1.0 / 12.0), roadWidthRailSampleT(1));
    try std.testing.expectEqual(@as(f32, 0.5), roadWidthRailSampleT(6));
    try std.testing.expectEqual(@as(f32, 1.0), roadWidthRailSampleT(road_width_rail_samples));
}

test "road split interpolation returns point on visible segment" {
    const point = nearestPointOnWorldSegment(
        5,
        0,
        .{ .x = 0, .y = 0 },
        .{ .x = 10, .y = 0 },
        .{ .x = 0, .y = 2, .z = 0 },
        .{ .x = 10, .y = 4, .z = 0 },
    );

    try std.testing.expectEqual(@as(f32, 5), point.x);
    try std.testing.expectEqual(@as(f32, 3), point.y);
    try std.testing.expectEqual(@as(f32, 0), point.z);
}

test "road handle colors quiet non-shaping modes" {
    const base = shared_color.Color{ .r = 255, .g = 175, .b = 105, .a = 235 };
    const shape = roadPassiveHandleColor(.shape, base);
    const surface = roadPassiveHandleColor(.surface, base);
    const inactive_arm = roadHandleArmLineColor(.surface, base, false);
    const active_arm = roadHandleArmLineColor(.surface, base, true);

    try std.testing.expectEqual(base.a, shape.a);
    try std.testing.expect(surface.a < shape.a);
    try std.testing.expect(inactive_arm.a < surface.a);
    try std.testing.expectEqual(base.a, active_arm.a);
}

test "road hit maps graph index into shared curve hit" {
    const hit = roadHitToWorldCurveHit(.{
        .kind = .handle_end,
        .id = @constCast("road.edge.7"),
        .index = 7,
    });

    try std.testing.expectEqual(project_editor_types.WorldCurveHitTarget.road, hit.target);
    try std.testing.expectEqual(project_editor_types.WorldCurveHitElement.handle_end, hit.element);
    try std.testing.expectEqual(@as(usize, 7), hit.index);
}

test "road click selection preserves hovered graph index" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .selected_world_curve_hit = .{ .target = .road, .element = .segment, .index = 0 },
    };

    applyRoadHitIndexToSelectedCurveHit(&state, .{
        .kind = .edge,
        .id = @constCast("road.edge.12"),
        .index = 12,
    });

    try std.testing.expectEqual(project_editor_types.WorldCurveHitTarget.road, state.selected_world_curve_hit.target);
    try std.testing.expectEqual(project_editor_types.WorldCurveHitElement.segment, state.selected_world_curve_hit.element);
    try std.testing.expectEqual(@as(usize, 12), state.selected_world_curve_hit.index);
}

test "road edge index lookup follows graph order" {
    var doc = spline_authoring.SplinesAuthoringDoc.init(std.testing.allocator);
    defer doc.deinit();

    try doc.upsertRoadNode(.{ .id = "a", .position = .{ .x = 0, .y = 0, .z = 0 } });
    try doc.upsertRoadNode(.{ .id = "b", .position = .{ .x = 10, .y = 0, .z = 0 } });
    try doc.upsertRoadNode(.{ .id = "c", .position = .{ .x = 20, .y = 0, .z = 0 } });
    try doc.upsertRoadEdge(.{
        .id = "ab",
        .start_node_id = "a",
        .end_node_id = "b",
        .handle_start = .{ .x = 3, .y = 0, .z = 0 },
        .handle_end = .{ .x = 6, .y = 0, .z = 0 },
        .width = 4,
    });
    try doc.upsertRoadEdge(.{
        .id = "bc",
        .start_node_id = "b",
        .end_node_id = "c",
        .handle_start = .{ .x = 13, .y = 0, .z = 0 },
        .handle_end = .{ .x = 16, .y = 0, .z = 0 },
        .width = 4,
    });

    try std.testing.expectEqual(@as(?usize, 0), roadEdgeIndexById(&doc, "ab"));
    try std.testing.expectEqual(@as(?usize, 1), roadEdgeIndexById(&doc, "bc"));
    try std.testing.expectEqual(@as(?usize, null), roadEdgeIndexById(&doc, "missing"));
}

test "road terrain overlay colors make floating and tunnel visually distinct" {
    const base = shared_color.Color{ .r = 240, .g = 190, .b = 90, .a = 220 };
    const conform = roadTerrainOverlayColor(.conform, base);
    const floating = roadTerrainOverlayColor(.floating, base);
    const tunnel = roadTerrainOverlayColor(.tunnel_reserved, base);

    try std.testing.expectEqual(base, conform);
    try std.testing.expect(floating.b > base.b);
    try std.testing.expect(floating.g > base.g);
    try std.testing.expect(tunnel.r > base.r);
    try std.testing.expect(tunnel.g < base.g);
    try std.testing.expectEqual(base.a, floating.a);
    try std.testing.expectEqual(base.a, tunnel.a);
}
