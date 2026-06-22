const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const editor_math = shared.editor_math;
const shared_color = shared.color;
const project_editor_blockout = @import("project_editor_blockout.zig");
const project_editor_edit = @import("project_editor_edit_undo.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_types = @import("project_editor_types.zig");
const curve_drawing = @import("project_editor_curve_drawing.zig");
const world_ocean = @import("project_editor_world_ocean.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const ClipPoint = world_ocean.ClipPoint;

pub const WorldCurveInteractionBegin = enum {
    none,
    handled,
    drag,
};

pub fn actionHint(state: *const ProjectEditorState) []const u8 {
    if (state.selected_world_curve_hit.target == .ocean_clip) {
        return switch (state.selected_world_curve_hit.element) {
            .point => "Drag this ocean point to move it.",
            .segment => "Drag this boundary, double-click to add a point, or Delete to remove it.",
            else => "Edit the selected ocean boundary.",
        };
    }
    if (state.hovered_world_curve_hit.target == .ocean_clip and state.hovered_world_curve_hit.element == .segment) return "Click or drag the boundary; double-click to add a point.";
    return "Click an ocean point or boundary.";
}

pub fn beginInteraction(state: *ProjectEditorState, screen_x: f32, screen_y: f32, click_count: u8) WorldCurveInteractionBegin {
    const index = world_ocean.findOceanObjectIndex(state) orelse return .none;
    var clip = world_ocean.loadClip(state.allocator, &state.objects.items[index]) catch return .none;
    defer clip.deinit(state.allocator);
    const local_x = screen_x - state.viewport_screen_rect.x;
    const local_y = screen_y - state.viewport_screen_rect.y;
    if (nearestPointAtScreen(state, clip.points, local_x, local_y, state.viewport_screen_rect.w, state.viewport_screen_rect.h, 12)) |point_index| {
        beginUndoBatch(state);
        state.selected_ocean_clip_point = point_index;
        state.selected_world_curve_hit = .{ .target = .ocean_clip, .element = .point, .index = index, .sub_index = point_index };
        project_editor_state.setStatus(state, actionHint(state));
        return .drag;
    }
    if (nearestEdgeAtScreen(state, clip.points, local_x, local_y, state.viewport_screen_rect.w, state.viewport_screen_rect.h, 8)) |edge_index| {
        state.selected_ocean_clip_point = null;
        state.selected_world_curve_hit = .{ .target = .ocean_clip, .element = .segment, .index = index, .sub_index = edge_index };
        if (click_count >= 2) {
            pushUndoSnapshot(state);
            const pt = project_editor_blockout.screenToGroundPoint(state, screen_x, screen_y) orelse return .none;
            world_ocean.insertClipPointAfterIndex(state, edge_index, .{ .x = pt.x, .z = pt.z }) catch {
                project_editor_state.setStatus(state, "Ocean boundary insert failed");
                return .none;
            };
            state.selected_ocean_clip_point = edge_index + 1;
            state.selected_world_curve_hit = .{ .target = .ocean_clip, .element = .point, .index = index, .sub_index = edge_index + 1 };
            project_editor_state.setStatus(state, "Ocean point inserted");
            return .handled;
        } else {
            beginUndoBatch(state);
            project_editor_state.setStatus(state, actionHint(state));
            return .drag;
        }
    }
    return .none;
}

pub fn handleDrag(state: *ProjectEditorState, screen_x: f32, screen_y: f32) void {
    const pt = project_editor_blockout.screenToGroundPoint(state, screen_x, screen_y) orelse return;
    const hit = state.selected_world_curve_hit;
    if (hit.target != .ocean_clip) return;
    switch (hit.element) {
        .point => {
            pushUndoSnapshot(state);
            state.selected_ocean_clip_point = hit.sub_index;
            world_ocean.moveClipPointAtIndex(state, hit.sub_index, .{ .x = pt.x, .z = pt.z }) catch {
                project_editor_state.setStatus(state, "Ocean boundary drag failed");
            };
        },
        .segment => moveSelectedEdgeByDrag(state, hit, .{ .x = pt.x, .z = pt.z }) catch {
            project_editor_state.setStatus(state, "Ocean boundary drag failed");
        },
        else => {},
    }
}

pub fn hitAtScreen(state: *ProjectEditorState, screen_x: f32, screen_y: f32) ?project_editor_types.WorldCurveHit {
    const object_index = world_ocean.findOceanObjectIndex(state) orelse return null;
    var clip = world_ocean.loadClip(state.allocator, &state.objects.items[object_index]) catch return null;
    defer clip.deinit(state.allocator);
    const local_x = screen_x - state.viewport_screen_rect.x;
    const local_y = screen_y - state.viewport_screen_rect.y;
    if (nearestPointAtScreen(state, clip.points, local_x, local_y, state.viewport_screen_rect.w, state.viewport_screen_rect.h, 12)) |point_index| {
        return .{ .target = .ocean_clip, .element = .point, .index = object_index, .sub_index = point_index };
    }
    if (nearestEdgeAtScreen(state, clip.points, local_x, local_y, state.viewport_screen_rect.w, state.viewport_screen_rect.h, 8)) |edge_index| {
        return .{ .target = .ocean_clip, .element = .segment, .index = object_index, .sub_index = edge_index };
    }
    return null;
}

pub fn drawOverlay(state: *ProjectEditorState, vp_w: f32, vp_h: f32) void {
    const index = world_ocean.findOceanObjectIndex(state) orelse return;
    var clip = world_ocean.loadClip(state.allocator, &state.objects.items[index]) catch return;
    defer clip.deinit(state.allocator);
    if (clip.points.len < 2) {
        drawStarterBoundaryPreview(state, vp_w, vp_h, clip.outer_half_extent_m);
        return;
    }

    const y = state.ocean_sea_level_m + 1.0;
    const style = curve_drawing.styleForTone(.ocean);
    const mouse_x = state.mouse_x - state.viewport_screen_rect.x;
    const mouse_y = state.mouse_y - state.viewport_screen_rect.y;
    const hover_point = nearestPointAtScreen(state, clip.points, mouse_x, mouse_y, vp_w, vp_h, 12);
    const hover_edge = if (hover_point == null)
        nearestEdgeAtScreen(state, clip.points, mouse_x, mouse_y, vp_w, vp_h, 8)
    else
        null;

    for (clip.points, 0..) |point, point_index| {
        const next = clip.points[(point_index + 1) % clip.points.len];
        const world_point = editor_math.Vec3{ .x = point.x, .y = y, .z = point.z };
        const world_next = editor_math.Vec3{ .x = next.x, .y = y, .z = next.z };
        const selected_edge = state.selected_world_curve_hit.target == .ocean_clip and state.selected_world_curve_hit.element == .segment and state.selected_world_curve_hit.sub_index == point_index;
        const line_color = if (selected_edge) style.selected_color else if (hover_edge != null and hover_edge.? == point_index) style.hover_color else style.line_color;
        curve_drawing.drawProjectedSegment(state, world_point, world_next, vp_w, vp_h, line_color);
        const midpoint = editor_math.Vec3{
            .x = (point.x + next.x) * 0.5,
            .y = y,
            .z = (point.z + next.z) * 0.5,
        };
        const insert_state: curve_drawing.HandleState = if (selected_edge) .selected else if (hover_edge != null and hover_edge.? == point_index) .hover else .preview;
        curve_drawing.drawProjectedHandle(state, midpoint, vp_w, vp_h, style, insert_state);
        const selected = selectedPoint(state, index, point_index);
        const hovered = hover_point != null and hover_point.? == point_index;
        const handle_state: curve_drawing.HandleState = if (selected) .selected else if (hovered) .hover else .normal;
        curve_drawing.drawProjectedHandle(state, world_point, vp_w, vp_h, style, handle_state);
    }
}

fn pushUndoSnapshot(state: *ProjectEditorState) void {
    project_editor_edit.pushUndoSnapshot(state);
}

fn beginUndoBatch(state: *ProjectEditorState) void {
    var status_buf: [256]u8 = undefined;
    const status_len = @min(state.status_len, status_buf.len);
    @memcpy(status_buf[0..status_len], state.status_buf[0..status_len]);
    project_editor_edit.beginUndoBatch(state, "World curve edit");
    project_editor_state.setStatus(state, status_buf[0..status_len]);
}

fn moveSelectedEdgeByDrag(state: *ProjectEditorState, hit: project_editor_types.WorldCurveHit, point: ClipPoint) !void {
    const index = world_ocean.findOceanObjectIndex(state) orelse return error.OceanObjectNotFound;
    var clip = try world_ocean.loadClip(state.allocator, &state.objects.items[index]);
    defer clip.deinit(state.allocator);
    if (hit.sub_index >= clip.points.len) return error.InvalidOceanClipPoint;
    pushUndoSnapshot(state);
    const points = try state.allocator.alloc(ClipPoint, clip.points.len);
    defer state.allocator.free(points);
    @memcpy(points, clip.points);
    const anchor: editor_math.Vec3 = state.world_curve_drag_anchor orelse .{ .x = point.x, .y = state.ocean_sea_level_m, .z = point.z };
    const dx = point.x - anchor.x;
    const dz = point.z - anchor.z;
    translateEdge(points, hit.sub_index, dx, dz);
    try world_ocean.applyClip(state, index, points, clip.outer_half_extent_m);
    state.selected_ocean_clip_point = null;
    state.selected_world_curve_hit = hit;
    state.world_curve_drag_anchor = .{ .x = point.x, .y = state.ocean_sea_level_m, .z = point.z };
}

fn translateEdge(points: []ClipPoint, edge_index: usize, dx: f32, dz: f32) void {
    if (points.len == 0 or edge_index >= points.len) return;
    const next_index = (edge_index + 1) % points.len;
    points[edge_index].x += dx;
    points[edge_index].z += dz;
    points[next_index].x += dx;
    points[next_index].z += dz;
}

fn drawStarterBoundaryPreview(state: *ProjectEditorState, vp_w: f32, vp_h: f32, outer_half_extent_m: f32) void {
    const style = curve_drawing.styleForTone(.ocean);
    const world_hint_half = @min(96.0, @max(16.0, outer_half_extent_m * 0.004));
    const camera_hint_half = @max(4.0, state.camera.distance * 0.08);
    const half = @min(world_hint_half, camera_hint_half);
    const center = state.camera.target;
    const y = state.ocean_sea_level_m + 1.0;
    const corners = [_]editor_math.Vec3{
        .{ .x = center.x - half, .y = y, .z = center.z - half },
        .{ .x = center.x + half, .y = y, .z = center.z - half },
        .{ .x = center.x + half, .y = y, .z = center.z + half },
        .{ .x = center.x - half, .y = y, .z = center.z + half },
    };
    const center_point = editor_math.Vec3{ .x = center.x, .y = y, .z = center.z };
    for (corners, 0..) |corner, index| {
        const next = corners[(index + 1) % corners.len];
        curve_drawing.drawProjectedSegment(state, corner, next, vp_w, vp_h, style.preview_color);
        curve_drawing.drawProjectedSegment(state, center_point, .{
            .x = (corner.x + next.x) * 0.5,
            .y = y,
            .z = (corner.z + next.z) * 0.5,
        }, vp_w, vp_h, style.preview_color);
        curve_drawing.drawProjectedHandle(state, corner, vp_w, vp_h, style, .preview);
    }
    curve_drawing.drawProjectedHandle(state, center_point, vp_w, vp_h, style, .hover);
}

fn selectedPoint(state: *const ProjectEditorState, object_index: usize, point_index: usize) bool {
    const hit = state.selected_world_curve_hit;
    return hit.target == .ocean_clip and hit.element == .point and hit.index == object_index and hit.sub_index == point_index;
}

fn nearestPointAtScreen(
    state: *ProjectEditorState,
    points: []const ClipPoint,
    screen_x: f32,
    screen_y: f32,
    vp_w: f32,
    vp_h: f32,
    radius_px: f32,
) ?usize {
    const y = state.ocean_sea_level_m + 1.0;
    const radius_sq = radius_px * radius_px;
    var best_index: ?usize = null;
    var best_distance = radius_sq;
    for (points, 0..) |point, index| {
        const p = project_editor_state.projectViewportPoint(state, .{ .x = point.x, .y = y, .z = point.z }, vp_w, vp_h) orelse continue;
        const dx = p.x - screen_x;
        const dy = p.y - screen_y;
        const dist = dx * dx + dy * dy;
        if (dist <= best_distance) {
            best_distance = dist;
            best_index = index;
        }
    }
    return best_index;
}

fn nearestEdgeAtScreen(
    state: *ProjectEditorState,
    points: []const ClipPoint,
    screen_x: f32,
    screen_y: f32,
    vp_w: f32,
    vp_h: f32,
    radius_px: f32,
) ?usize {
    if (points.len < 2) return null;
    const y = state.ocean_sea_level_m + 1.0;
    const radius_sq = radius_px * radius_px;
    var best_index: ?usize = null;
    var best_distance = radius_sq;
    for (points, 0..) |point, index| {
        const next = points[(index + 1) % points.len];
        const p0 = project_editor_state.projectViewportPoint(state, .{ .x = point.x, .y = y, .z = point.z }, vp_w, vp_h) orelse continue;
        const p1 = project_editor_state.projectViewportPoint(state, .{ .x = next.x, .y = y, .z = next.z }, vp_w, vp_h) orelse continue;
        const dist = distancePointSegmentSq(screen_x, screen_y, p0.x, p0.y, p1.x, p1.y);
        if (dist <= best_distance) {
            best_distance = dist;
            best_index = index;
        }
    }
    return best_index;
}

fn distancePointSegmentSq(px: f32, py: f32, ax: f32, ay: f32, bx: f32, by: f32) f32 {
    const vx = bx - ax;
    const vy = by - ay;
    const wx = px - ax;
    const wy = py - ay;
    const len_sq = vx * vx + vy * vy;
    const t = if (len_sq <= 0.0001) 0 else std.math.clamp((wx * vx + wy * vy) / len_sq, 0, 1);
    const cx = ax + vx * t;
    const cy = ay + vy * t;
    const dx = px - cx;
    const dy = py - cy;
    return dx * dx + dy * dy;
}

test "ocean overlay selection follows shared curve hit" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .world_tool = .ocean,
        .selected_ocean_clip_point = null,
        .selected_world_curve_hit = .{ .target = .ocean_clip, .element = .point, .index = 3, .sub_index = 1 },
    };
    try std.testing.expect(selectedPoint(&state, 3, 1));
    try std.testing.expect(!selectedPoint(&state, 3, 2));
    try std.testing.expect(!selectedPoint(&state, 4, 1));
}

test "ocean exclusion overlay emits visible boundary gizmo primitives" {
    const allocator = std.testing.allocator;
    var recorder = project_editor_state.ViewportOverlayRecorder{};
    defer recorder.deinit(allocator);

    const properties = try allocator.alloc(shared.scene_document.Property, 3);
    errdefer allocator.free(properties);
    properties[0] = .{
        .key = try allocator.dupe(u8, "role"),
        .value = try allocator.dupe(u8, "distant_ocean"),
    };
    properties[1] = .{
        .key = try allocator.dupe(u8, "cutout_0_points"),
        .value = try allocator.dupe(u8, "-1,-1;1,-1;1,1;-1,1"),
    };
    properties[2] = .{
        .key = try allocator.dupe(u8, "outer_half_extent_m"),
        .value = try allocator.dupe(u8, "16"),
    };
    errdefer {
        for (properties) |*property| property.deinit(allocator);
        allocator.free(properties);
    }

    var state = ProjectEditorState{
        .allocator = allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .mode = .world_creation,
        .world_tool = .ocean,
        .ocean_sea_level_m = 0,
        .viewport_screen_rect = .{ .x = 0, .y = 0, .w = 640, .h = 480 },
        .viewport_overlay_rect = .{ .x = 0, .y = 0, .w = 640, .h = 480 },
        .viewport_overlay_recorder = &recorder,
        .camera = .{
            .target = .{ .x = 0, .y = 0.5, .z = 0 },
            .yaw = 0.6,
            .pitch = 0.35,
            .distance = 6,
        },
    };
    defer {
        for (state.objects.items) |*object| object.deinit(allocator);
        state.objects.deinit(allocator);
    }

    try state.objects.append(allocator, .{
        .id = 1,
        .name = try allocator.dupe(u8, "Ocean"),
        .mesh = .{
            .vertices = try allocator.alloc(shared.geometry.Vertex, 0),
            .indices = try allocator.alloc(u32, 0),
        },
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = try allocator.dupe(u8, ""),
        .base_color = .{ .r = 30, .g = 80, .b = 140, .a = 255 },
        .properties = properties,
        .layer = try allocator.dupe(u8, "world.water"),
    });

    state.selected_world_curve_hit = .{ .target = .ocean_clip, .element = .segment, .index = 0, .sub_index = 1 };
    drawOverlay(&state, 640, 480);
    state.selected_world_curve_hit = .{ .target = .ocean_clip, .element = .point, .index = 0, .sub_index = 2 };
    drawOverlay(&state, 640, 480);

    const selected_ocean: shared_color.Color = .{ .r = 255, .g = 220, .b = 90, .a = 255 };
    try std.testing.expect(recorder.countKind(.line) >= 8);
    try std.testing.expect(recorder.countKind(.square) >= 12);
    try std.testing.expect(recorder.countColor(selected_ocean) >= 3);
}

test "empty ocean exclusion still emits starter boundary gizmo preview" {
    const allocator = std.testing.allocator;
    var recorder = project_editor_state.ViewportOverlayRecorder{};
    defer recorder.deinit(allocator);

    var state = ProjectEditorState{
        .allocator = allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .mode = .world_creation,
        .world_tool = .ocean,
        .ocean_sea_level_m = 0,
        .viewport_screen_rect = .{ .x = 0, .y = 0, .w = 640, .h = 480 },
        .viewport_overlay_rect = .{ .x = 0, .y = 0, .w = 640, .h = 480 },
        .viewport_overlay_recorder = &recorder,
        .camera = .{
            .target = .{ .x = 0, .y = 0.5, .z = 0 },
            .yaw = 0.6,
            .pitch = 0.35,
            .distance = 6,
        },
    };

    drawStarterBoundaryPreview(&state, 640, 480, 256);

    const preview_ocean: shared_color.Color = .{ .r = 95, .g = 205, .b = 255, .a = 155 };
    const hover_ocean: shared_color.Color = .{ .r = 150, .g = 255, .b = 225, .a = 255 };
    try std.testing.expect(recorder.countKind(.line) >= 4);
    try std.testing.expect(recorder.countKind(.square) >= 5);
    try std.testing.expect(recorder.countColor(preview_ocean) >= 8);
    try std.testing.expect(recorder.countColor(hover_ocean) >= 1);
}

test "ocean clip edge drag moves both edge endpoints" {
    var points = [_]ClipPoint{
        .{ .x = 0, .z = 0 },
        .{ .x = 10, .z = 0 },
        .{ .x = 10, .z = 10 },
        .{ .x = 0, .z = 10 },
    };

    translateEdge(&points, 3, 2, -3);

    try std.testing.expectEqual(@as(f32, 2), points[3].x);
    try std.testing.expectEqual(@as(f32, 7), points[3].z);
    try std.testing.expectEqual(@as(f32, 2), points[0].x);
    try std.testing.expectEqual(@as(f32, -3), points[0].z);
    try std.testing.expectEqual(@as(f32, 10), points[1].x);
}
