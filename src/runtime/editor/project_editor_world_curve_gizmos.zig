const std = @import("std");
const shared = @import("runtime_shared");

const project_editor_state = @import("project_editor_state.zig");
const project_editor_types = @import("project_editor_types.zig");
const project_editor_viewport = @import("project_editor_viewport.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const editor_math = shared.editor_math;
const shared_color = shared.color;

pub const WorldCurveHitKind = enum {
    node,
    segment,
    handle_arm,
    width_rail,
};

pub const WorldCurveHit = struct {
    kind: WorldCurveHitKind,
    index: usize,
    distance_px: f32,
    t: f32 = 0,
};

pub const WorldCurveStyle = struct {
    segment_color: shared_color.Color = .{ .r = 240, .g = 190, .b = 90, .a = 230 },
    segment_selected_color: shared_color.Color = .{ .r = 255, .g = 220, .b = 90, .a = 255 },
    node_color: shared_color.Color = .{ .r = 255, .g = 220, .b = 120, .a = 255 },
    node_selected_color: shared_color.Color = .{ .r = 255, .g = 245, .b = 180, .a = 255 },
    handle_arm_color: shared_color.Color = .{ .r = 120, .g = 205, .b = 255, .a = 180 },
    handle_color: shared_color.Color = .{ .r = 150, .g = 225, .b = 255, .a = 235 },
    width_rail_color: shared_color.Color = .{ .r = 255, .g = 160, .b = 70, .a = 165 },
    node_half_px: i32 = 4,
    selected_node_half_px: i32 = 6,
    handle_half_px: i32 = 3,
    node_hit_radius_px: f32 = 9,
    segment_hit_radius_px: f32 = 7,
    handle_arm_hit_radius_px: f32 = 6,
    width_rail_hit_radius_px: f32 = 6,
};

pub const WorldCurveSegment = struct {
    start: editor_math.Vec3,
    end: editor_math.Vec3,
};

pub const WorldCurveHandleArms = struct {
    start: editor_math.Vec3,
    handle_start: editor_math.Vec3,
    handle_end: editor_math.Vec3,
    end: editor_math.Vec3,
};

pub fn defaultStyle() WorldCurveStyle {
    return .{};
}

pub fn nearerHit(a: ?WorldCurveHit, b: ?WorldCurveHit) ?WorldCurveHit {
    if (a == null) return b;
    if (b == null) return a;
    return if (b.?.distance_px < a.?.distance_px) b else a;
}

pub fn nearerEditorHit(a: ?project_editor_types.WorldCurveHit, b: project_editor_types.WorldCurveHit) project_editor_types.WorldCurveHit {
    if (a) |existing| {
        const existing_priority = hitElementPriority(existing.element);
        const next_priority = hitElementPriority(b.element);
        if (next_priority > existing_priority and b.distance_sq <= existing.distance_sq + priority_bias_sq) return b;
        if (existing_priority > next_priority and existing.distance_sq <= b.distance_sq + priority_bias_sq) return existing;
        if (b.distance_sq >= existing.distance_sq) return existing;
    }
    return b;
}

const priority_bias_sq: f32 = 8.0 * 8.0;

fn hitElementPriority(element: project_editor_types.WorldCurveHitElement) u8 {
    return switch (element) {
        .point, .handle_start, .handle_end => 3,
        .segment => 2,
        .width_rail => 1,
        .none => 0,
    };
}

pub fn hitPointAtScreen(
    mouse: editor_math.Vec2,
    point: editor_math.Vec2,
    index: usize,
    radius_px: f32,
) ?WorldCurveHit {
    if (!finiteVec2(mouse) or !finiteVec2(point) or radius_px < 0) return null;
    const distance_sq = distancePointSq(mouse, point);
    if (distance_sq > radius_px * radius_px) return null;
    return .{
        .kind = .node,
        .index = index,
        .distance_px = @sqrt(distance_sq),
    };
}

pub fn hitSegmentAtScreen(
    mouse: editor_math.Vec2,
    a: editor_math.Vec2,
    b: editor_math.Vec2,
    index: usize,
    radius_px: f32,
) ?WorldCurveHit {
    return hitSegmentKindAtScreen(.segment, mouse, a, b, index, radius_px);
}

pub fn hitHandleArmAtScreen(
    mouse: editor_math.Vec2,
    anchor: editor_math.Vec2,
    handle: editor_math.Vec2,
    index: usize,
    radius_px: f32,
) ?WorldCurveHit {
    return hitSegmentKindAtScreen(.handle_arm, mouse, anchor, handle, index, radius_px);
}

pub fn hitWidthRailAtScreen(
    mouse: editor_math.Vec2,
    a: editor_math.Vec2,
    b: editor_math.Vec2,
    index: usize,
    radius_px: f32,
) ?WorldCurveHit {
    return hitSegmentKindAtScreen(.width_rail, mouse, a, b, index, radius_px);
}

pub fn hitSegmentKindAtScreen(
    kind: WorldCurveHitKind,
    mouse: editor_math.Vec2,
    a: editor_math.Vec2,
    b: editor_math.Vec2,
    index: usize,
    radius_px: f32,
) ?WorldCurveHit {
    if (!finiteVec2(mouse) or !finiteVec2(a) or !finiteVec2(b) or radius_px < 0) return null;
    const nearest = nearestPointOnSegment(mouse, a, b);
    const distance_sq = distancePointSq(mouse, nearest.point);
    if (distance_sq > radius_px * radius_px) return null;
    return .{
        .kind = kind,
        .index = index,
        .distance_px = @sqrt(distance_sq),
        .t = nearest.t,
    };
}

pub fn hitPolylineNodesAtScreen(
    mouse: editor_math.Vec2,
    points: []const editor_math.Vec2,
    radius_px: f32,
) ?WorldCurveHit {
    var best: ?WorldCurveHit = null;
    for (points, 0..) |point, index| {
        best = nearerHit(best, hitPointAtScreen(mouse, point, index, radius_px));
    }
    return best;
}

pub fn hitPolylineSegmentsAtScreen(
    mouse: editor_math.Vec2,
    points: []const editor_math.Vec2,
    radius_px: f32,
) ?WorldCurveHit {
    if (points.len < 2) return null;
    var best: ?WorldCurveHit = null;
    var index: usize = 0;
    while (index + 1 < points.len) : (index += 1) {
        best = nearerHit(best, hitSegmentAtScreen(mouse, points[index], points[index + 1], index, radius_px));
    }
    return best;
}

pub fn hitWorldNodes(
    state: *const ProjectEditorState,
    mouse: editor_math.Vec2,
    points: []const editor_math.Vec3,
    vp_w: f32,
    vp_h: f32,
    radius_px: f32,
) ?WorldCurveHit {
    var best: ?WorldCurveHit = null;
    for (points, 0..) |point, index| {
        const screen = project_editor_state.projectViewportPoint(state, point, vp_w, vp_h) orelse continue;
        best = nearerHit(best, hitPointAtScreen(mouse, screen, index, radius_px));
    }
    return best;
}

pub fn hitWorldSegments(
    state: *const ProjectEditorState,
    mouse: editor_math.Vec2,
    segments: []const WorldCurveSegment,
    vp_w: f32,
    vp_h: f32,
    radius_px: f32,
) ?WorldCurveHit {
    var best: ?WorldCurveHit = null;
    for (segments, 0..) |segment, index| {
        const start = project_editor_state.projectViewportPoint(state, segment.start, vp_w, vp_h) orelse continue;
        const end = project_editor_state.projectViewportPoint(state, segment.end, vp_w, vp_h) orelse continue;
        best = nearerHit(best, hitSegmentAtScreen(mouse, start, end, index, radius_px));
    }
    return best;
}

pub fn drawNode(
    state: *ProjectEditorState,
    vp_w: f32,
    vp_h: f32,
    point: editor_math.Vec3,
    selected: bool,
    style: WorldCurveStyle,
) void {
    const screen = project_editor_state.projectViewportPoint(state, point, vp_w, vp_h) orelse return;
    const half = if (selected) style.selected_node_half_px else style.node_half_px;
    const color = if (selected) style.node_selected_color else style.node_color;
    project_editor_viewport.drawViewportSquare(state, screen.x, screen.y, half, color);
}

pub fn drawSegment(
    state: *ProjectEditorState,
    vp_w: f32,
    vp_h: f32,
    start: editor_math.Vec3,
    end: editor_math.Vec3,
    selected: bool,
    style: WorldCurveStyle,
) void {
    const s0 = project_editor_state.projectViewportPoint(state, start, vp_w, vp_h) orelse return;
    const s1 = project_editor_state.projectViewportPoint(state, end, vp_w, vp_h) orelse return;
    const color = if (selected) style.segment_selected_color else style.segment_color;
    project_editor_viewport.drawViewportLine(state, s0.x, s0.y, s1.x, s1.y, color);
}

pub fn drawHandleArm(
    state: *ProjectEditorState,
    vp_w: f32,
    vp_h: f32,
    anchor: editor_math.Vec3,
    handle: editor_math.Vec3,
    style: WorldCurveStyle,
) void {
    const anchor_screen = project_editor_state.projectViewportPoint(state, anchor, vp_w, vp_h) orelse return;
    const handle_screen = project_editor_state.projectViewportPoint(state, handle, vp_w, vp_h) orelse return;
    project_editor_viewport.drawViewportLine(state, anchor_screen.x, anchor_screen.y, handle_screen.x, handle_screen.y, style.handle_arm_color);
    project_editor_viewport.drawViewportSquare(state, handle_screen.x, handle_screen.y, style.handle_half_px, style.handle_color);
}

pub fn drawHandleArms(
    state: *ProjectEditorState,
    vp_w: f32,
    vp_h: f32,
    arms: WorldCurveHandleArms,
    style: WorldCurveStyle,
) void {
    drawHandleArm(state, vp_w, vp_h, arms.start, arms.handle_start, style);
    drawHandleArm(state, vp_w, vp_h, arms.end, arms.handle_end, style);
}

pub fn drawWidthRails(
    state: *ProjectEditorState,
    vp_w: f32,
    vp_h: f32,
    start: editor_math.Vec3,
    end: editor_math.Vec3,
    width_m: f32,
    style: WorldCurveStyle,
) void {
    const rails = widthRailSegments(start, end, width_m) orelse return;
    const rail_style = WorldCurveStyle{
        .segment_color = style.width_rail_color,
        .segment_selected_color = style.width_rail_color,
        .node_color = style.node_color,
        .node_selected_color = style.node_selected_color,
        .handle_arm_color = style.handle_arm_color,
        .handle_color = style.handle_color,
        .width_rail_color = style.width_rail_color,
        .node_half_px = style.node_half_px,
        .selected_node_half_px = style.selected_node_half_px,
        .handle_half_px = style.handle_half_px,
        .node_hit_radius_px = style.node_hit_radius_px,
        .segment_hit_radius_px = style.segment_hit_radius_px,
        .handle_arm_hit_radius_px = style.handle_arm_hit_radius_px,
        .width_rail_hit_radius_px = style.width_rail_hit_radius_px,
    };
    drawSegment(state, vp_w, vp_h, rails[0].start, rails[0].end, false, rail_style);
    drawSegment(state, vp_w, vp_h, rails[1].start, rails[1].end, false, rail_style);
}

pub fn widthRailSegments(start: editor_math.Vec3, end: editor_math.Vec3, width_m: f32) ?[2]WorldCurveSegment {
    if (width_m <= 0 or !finiteVec3(start) or !finiteVec3(end)) return null;
    const dx = end.x - start.x;
    const dz = end.z - start.z;
    const len = @sqrt(dx * dx + dz * dz);
    if (len <= std.math.floatEps(f32)) return null;
    const offset_x = -dz / len * width_m * 0.5;
    const offset_z = dx / len * width_m * 0.5;
    const offset = editor_math.Vec3{ .x = offset_x, .y = 0, .z = offset_z };
    return .{
        .{ .start = editor_math.Vec3.add(start, offset), .end = editor_math.Vec3.add(end, offset) },
        .{ .start = editor_math.Vec3.sub(start, offset), .end = editor_math.Vec3.sub(end, offset) },
    };
}

pub fn distancePointSegmentSq(point: editor_math.Vec2, a: editor_math.Vec2, b: editor_math.Vec2) f32 {
    const nearest = nearestPointOnSegment(point, a, b);
    return distancePointSq(point, nearest.point);
}

const NearestPoint = struct {
    point: editor_math.Vec2,
    t: f32,
};

fn nearestPointOnSegment(point: editor_math.Vec2, a: editor_math.Vec2, b: editor_math.Vec2) NearestPoint {
    const ab = editor_math.Vec2.sub(b, a);
    const len_sq = editor_math.Vec2.lengthSquared(ab);
    if (len_sq <= std.math.floatEps(f32)) return .{ .point = a, .t = 0 };
    const ap = editor_math.Vec2.sub(point, a);
    const t = std.math.clamp(editor_math.Vec2.dot(ap, ab) / len_sq, 0, 1);
    return .{
        .point = editor_math.Vec2.add(a, editor_math.Vec2.scale(ab, t)),
        .t = t,
    };
}

fn distancePointSq(a: editor_math.Vec2, b: editor_math.Vec2) f32 {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return dx * dx + dy * dy;
}

fn finiteVec2(v: editor_math.Vec2) bool {
    return std.math.isFinite(v.x) and std.math.isFinite(v.y);
}

fn finiteVec3(v: editor_math.Vec3) bool {
    return std.math.isFinite(v.x) and std.math.isFinite(v.y) and std.math.isFinite(v.z);
}

test "world curve point hit returns nearest node inside radius" {
    const points = [_]editor_math.Vec2{
        .{ .x = 10, .y = 10 },
        .{ .x = 24, .y = 10 },
    };
    const hit = hitPolylineNodesAtScreen(.{ .x = 21, .y = 10 }, &points, 5) orelse return error.ExpectedHit;
    try std.testing.expectEqual(WorldCurveHitKind.node, hit.kind);
    try std.testing.expectEqual(@as(usize, 1), hit.index);
    try std.testing.expectApproxEqAbs(@as(f32, 3), hit.distance_px, 0.001);
}

test "world curve segment hit reports segment t and distance" {
    const hit = hitSegmentAtScreen(
        .{ .x = 5, .y = 3 },
        .{ .x = 0, .y = 0 },
        .{ .x = 10, .y = 0 },
        4,
        4,
    ) orelse return error.ExpectedHit;
    try std.testing.expectEqual(WorldCurveHitKind.segment, hit.kind);
    try std.testing.expectEqual(@as(usize, 4), hit.index);
    try std.testing.expectApproxEqAbs(@as(f32, 3), hit.distance_px, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), hit.t, 0.001);
}

test "world curve segment hit clamps to endpoints" {
    const hit = hitSegmentAtScreen(
        .{ .x = -2, .y = 0 },
        .{ .x = 0, .y = 0 },
        .{ .x = 10, .y = 0 },
        0,
        3,
    ) orelse return error.ExpectedHit;
    try std.testing.expectApproxEqAbs(@as(f32, 2), hit.distance_px, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), hit.t, 0.001);
}

test "world curve polyline segment hit picks nearest segment" {
    const points = [_]editor_math.Vec2{
        .{ .x = 0, .y = 0 },
        .{ .x = 10, .y = 0 },
        .{ .x = 10, .y = 10 },
    };
    const hit = hitPolylineSegmentsAtScreen(.{ .x = 8, .y = 6 }, &points, 4) orelse return error.ExpectedHit;
    try std.testing.expectEqual(@as(usize, 1), hit.index);
    try std.testing.expectApproxEqAbs(@as(f32, 0.6), hit.t, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2), hit.distance_px, 0.001);
}

test "world curve editor hit prefers nearby point over segment" {
    const segment = project_editor_types.WorldCurveHit{
        .target = .water_volume,
        .element = .segment,
        .index = 1,
        .distance_sq = 9,
    };
    const point = project_editor_types.WorldCurveHit{
        .target = .water_volume,
        .element = .point,
        .index = 1,
        .sub_index = 2,
        .distance_sq = 16,
    };

    const picked = nearerEditorHit(segment, point);

    try std.testing.expectEqual(project_editor_types.WorldCurveHitElement.point, picked.element);
    try std.testing.expectEqual(@as(usize, 2), picked.sub_index);
}

test "world curve editor hit still respects a much closer segment" {
    const segment = project_editor_types.WorldCurveHit{
        .target = .scatter_zone,
        .element = .segment,
        .index = 1,
        .distance_sq = 1,
    };
    const point = project_editor_types.WorldCurveHit{
        .target = .scatter_zone,
        .element = .point,
        .index = 1,
        .sub_index = 2,
        .distance_sq = 100,
    };

    const picked = nearerEditorHit(segment, point);

    try std.testing.expectEqual(project_editor_types.WorldCurveHitElement.segment, picked.element);
}

test "world curve specialized segment hits preserve kind" {
    const arm = hitHandleArmAtScreen(
        .{ .x = 3, .y = 1 },
        .{ .x = 0, .y = 0 },
        .{ .x = 6, .y = 0 },
        2,
        2,
    ) orelse return error.ExpectedHit;
    try std.testing.expectEqual(WorldCurveHitKind.handle_arm, arm.kind);

    const rail = hitWidthRailAtScreen(
        .{ .x = 3, .y = 1 },
        .{ .x = 0, .y = 0 },
        .{ .x = 6, .y = 0 },
        1,
        2,
    ) orelse return error.ExpectedHit;
    try std.testing.expectEqual(WorldCurveHitKind.width_rail, rail.kind);
}

test "world curve width rails offset in horizontal plane" {
    const rails = widthRailSegments(
        .{ .x = 0, .y = 3, .z = 0 },
        .{ .x = 10, .y = 3, .z = 0 },
        4,
    ) orelse return error.ExpectedRails;
    try std.testing.expectApproxEqAbs(@as(f32, 2), rails[0].start.z, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, -2), rails[1].start.z, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 3), rails[0].start.y, 0.001);
    try std.testing.expect(widthRailSegments(.{ .x = 1, .y = 0, .z = 1 }, .{ .x = 1, .y = 0, .z = 1 }, 4) == null);
}
