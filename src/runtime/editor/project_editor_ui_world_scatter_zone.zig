const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const editor_math = shared.editor_math;
const project_editor_blockout = @import("project_editor_blockout.zig");
const project_editor_edit = @import("project_editor_edit_undo.zig");
const project_editor_scatter_preview = @import("project_editor_scatter_preview.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_types = @import("project_editor_types.zig");
const project_editor_ui_world_scatter_helpers = @import("project_editor_ui_world_scatter_helpers.zig");
const project_editor_world_authoring = @import("project_editor_world_authoring.zig");
const world_manifest_authoring = @import("project_editor_world_authoring_manifest.zig");
const curve_drawing = @import("project_editor_curve_drawing.zig");
const world_curve_gizmos = @import("project_editor_world_curve_gizmos.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;

pub fn beginDrag(state: *ProjectEditorState, screen_x: f32, screen_y: f32) void {
    beginUndoBatch(state);
    project_editor_world_authoring.beginScatterZoneDrag(state, screen_x, screen_y);
}

pub fn beginInteraction(state: *ProjectEditorState, screen_x: f32, screen_y: f32) bool {
    const hit = hitAtScreen(state, screen_x, screen_y) orelse return false;
    beginUndoBatch(state);
    state.selected_world_curve_hit = hit;
    state.world_curve_drag_state = .{ .hit = hit, .start_x = screen_x, .start_y = screen_y };
    state.world_curve_drag_anchor = project_editor_blockout.screenToGroundPoint(state, screen_x, screen_y);
    project_editor_state.setStatus(state, project_editor_ui_world_scatter_helpers.scatterSelectionLabel(hit));
    return true;
}

pub fn updateDrag(state: *ProjectEditorState, screen_x: f32, screen_y: f32) void {
    project_editor_world_authoring.updateScatterZoneDrag(state, screen_x, screen_y);
}

pub fn finishDrag(state: *ProjectEditorState) void {
    const start = state.world_scatter_drag_start;
    const end = state.world_scatter_drag_end;
    const created_zone = project_editor_ui_world_scatter_helpers.scatterDragCreatesZone(start, end);
    if (created_zone) pushUndoSnapshot(state);
    project_editor_world_authoring.finishScatterZoneDrag(state);
    if (created_zone) selectFromDrag(state, start.?, end.?) catch {};
    endUndoBatch(state);
}

pub fn cancelDrag(state: *ProjectEditorState) void {
    state.world_scatter_drag_start = null;
    state.world_scatter_drag_end = null;
    rollbackUndoBatch(state);
}

pub fn moveSelectedPart(state: *ProjectEditorState, screen_x: f32, screen_y: f32) !void {
    const hit = state.selected_world_curve_hit;
    if (hit.target != .scatter_zone) return;
    const point = project_editor_blockout.screenToGroundPoint(state, screen_x, screen_y) orelse return;
    var doc = try friendly_engine.modules.scatter.authoring.loadProject(state.allocator, state.io, state.project_path, try world_manifest_authoring.pathForState(state));
    defer doc.deinit();
    if (hit.index >= doc.exclusions.items.len) return error.InvalidExclusionZone;
    var zone = &doc.exclusions.items[hit.index];
    var min_x = zone.min[0];
    const min_y = zone.min[1];
    var min_z = zone.min[2];
    var max_x = zone.max[0];
    const max_y = zone.max[1];
    var max_z = zone.max[2];
    switch (hit.element) {
        .point => project_editor_ui_world_scatter_helpers.resizeScatterZoneCorner(hit.sub_index, point, &min_x, &min_z, &max_x, &max_z),
        .segment => {
            const anchor = state.world_curve_drag_anchor orelse point;
            const dx = point.x - anchor.x;
            const dz = point.z - anchor.z;
            project_editor_ui_world_scatter_helpers.resizeScatterZoneEdge(hit.sub_index, dx, dz, &min_x, &min_z, &max_x, &max_z);
            state.world_curve_drag_anchor = point;
        },
        .width_rail => {
            const anchor = state.world_curve_drag_anchor orelse point;
            const dx = point.x - anchor.x;
            const dz = point.z - anchor.z;
            project_editor_ui_world_scatter_helpers.moveScatterZoneBody(dx, dz, &min_x, &min_z, &max_x, &max_z);
            state.world_curve_drag_anchor = point;
        },
        else => return,
    }
    project_editor_ui_world_scatter_helpers.normalizeMinMax(&min_x, &max_x);
    project_editor_ui_world_scatter_helpers.normalizeMinMax(&min_z, &max_z);
    if (max_x - min_x < 0.5 or max_z - min_z < 0.5) return error.InvalidExclusionZone;
    const next_min = try state.allocator.dupe(f32, &[_]f32{ min_x, min_y, min_z });
    errdefer state.allocator.free(next_min);
    const next_max = try state.allocator.dupe(f32, &[_]f32{ max_x, max_y, max_z });
    errdefer state.allocator.free(next_max);
    pushUndoSnapshot(state);
    state.allocator.free(zone.min);
    state.allocator.free(zone.max);
    zone.min = next_min;
    zone.max = next_max;
    try friendly_engine.modules.scatter.authoring.saveProject(&doc, state.io, state.project_path, try world_manifest_authoring.pathForState(state));
    project_editor_scatter_preview.markStale(state);
    try project_editor_state.markDirtyCell(state, "Scatter", .{ .x = @intCast(zone.cell[0]), .y = @intCast(zone.cell[1]), .z = if (zone.cell.len == 3) @intCast(zone.cell[2]) else 0 }, "exclusion zone");
    project_editor_state.setStatus(state, project_editor_ui_world_scatter_helpers.scatterSelectionLabel(hit));
}

pub fn deleteSelected(state: *ProjectEditorState) !void {
    const hit = state.selected_world_curve_hit;
    if (hit.target != .scatter_zone) return;
    pushUndoSnapshot(state);
    var doc = try friendly_engine.modules.scatter.authoring.loadProject(state.allocator, state.io, state.project_path, try world_manifest_authoring.pathForState(state));
    defer doc.deinit();
    if (hit.index >= doc.exclusions.items.len) return error.InvalidExclusionZone;
    const zone = doc.exclusions.items[hit.index];
    const cell = friendly_engine.world.cell.CellId{ .x = @intCast(zone.cell[0]), .y = @intCast(zone.cell[1]), .z = if (zone.cell.len == 3) @intCast(zone.cell[2]) else 0 };
    state.allocator.free(zone.cell);
    state.allocator.free(zone.min);
    state.allocator.free(zone.max);
    _ = doc.exclusions.swapRemove(hit.index);
    try friendly_engine.modules.scatter.authoring.saveProject(&doc, state.io, state.project_path, try world_manifest_authoring.pathForState(state));
    project_editor_scatter_preview.markStale(state);
    try project_editor_state.markDirtyCell(state, "Scatter", cell, "exclusion zone");
    state.selected_world_curve_hit = .{};
    state.hovered_world_curve_hit = .{};
    project_editor_state.setStatus(state, "Scatter area deleted");
}

pub fn hitAtScreen(state: *ProjectEditorState, screen_x: f32, screen_y: f32) ?project_editor_types.WorldCurveHit {
    project_editor_scatter_preview.refreshIfStale(state) catch return null;
    const local_x = screen_x - state.viewport_screen_rect.x;
    const local_y = screen_y - state.viewport_screen_rect.y;
    const vp_w = state.viewport_screen_rect.w;
    const vp_h = state.viewport_screen_rect.h;
    var best: ?project_editor_types.WorldCurveHit = null;
    for (state.scatter_preview.exclusions.items, 0..) |zone, zone_index| {
        if (nearestRectangleCornerAtScreen(state, zone.min, zone.max, local_x, local_y, vp_w, vp_h, 12)) |corner_hit| {
            best = world_curve_gizmos.nearerEditorHit(best, .{
                .target = .scatter_zone,
                .element = .point,
                .index = zone_index,
                .sub_index = corner_hit.index,
                .distance_sq = corner_hit.distance_sq,
            });
        }
        if (nearestRectangleEdgeAtScreen(state, zone.min, zone.max, local_x, local_y, vp_w, vp_h, 8)) |edge_hit| {
            best = world_curve_gizmos.nearerEditorHit(best, .{
                .target = .scatter_zone,
                .element = .segment,
                .index = zone_index,
                .sub_index = edge_hit.index,
                .distance_sq = edge_hit.distance_sq,
            });
        }
        if (best == null and rectangleContainsGroundPoint(state, zone.min, zone.max, screen_x, screen_y)) {
            best = .{
                .target = .scatter_zone,
                .element = .width_rail,
                .index = zone_index,
                .distance_sq = 48.0 * 48.0,
            };
        }
    }
    return best;
}

pub fn drawPreview(state: *ProjectEditorState, vp_w: f32, vp_h: f32) void {
    if (state.world_scatter_drag_start == null or state.world_scatter_drag_end == null) return;
    const start = state.world_scatter_drag_start.?;
    const end = state.world_scatter_drag_end.?;
    const min_pt = editor_math.Vec3{ .x = @min(start.x, end.x), .y = 0.08, .z = @min(start.z, end.z) };
    const max_pt = editor_math.Vec3{ .x = @max(start.x, end.x), .y = 0.08, .z = @max(start.z, end.z) };
    drawRectangleFootprint(state, min_pt, max_pt, vp_w, vp_h, curve_drawing.styleForTone(.scatter), .preview);
}

fn beginUndoBatch(state: *ProjectEditorState) void {
    var status_buf: [256]u8 = undefined;
    const status_len = @min(state.status_len, status_buf.len);
    @memcpy(status_buf[0..status_len], state.status_buf[0..status_len]);
    project_editor_edit.beginUndoBatch(state, "World curve edit");
    project_editor_state.setStatus(state, status_buf[0..status_len]);
}

fn endUndoBatch(state: *ProjectEditorState) void {
    var status_buf: [256]u8 = undefined;
    const status_len = @min(state.status_len, status_buf.len);
    @memcpy(status_buf[0..status_len], state.status_buf[0..status_len]);
    project_editor_edit.endUndoBatch(state);
    project_editor_state.setStatus(state, status_buf[0..status_len]);
}

fn rollbackUndoBatch(state: *ProjectEditorState) void {
    const should_undo = state.undo_batch_depth > 0 and state.undo_batch_snapshot_taken;
    if (state.undo_batch_depth > 0) project_editor_edit.cancelUndoBatch(state);
    if (should_undo) project_editor_edit.undo(state);
}

fn pushUndoSnapshot(state: *ProjectEditorState) void {
    project_editor_edit.pushUndoSnapshot(state);
}

fn selectFromDrag(state: *ProjectEditorState, start: editor_math.Vec3, end: editor_math.Vec3) !void {
    project_editor_scatter_preview.refreshIfStale(state) catch {
        try project_editor_scatter_preview.refresh(state);
    };
    const min_x = @min(start.x, end.x);
    const max_x = @max(start.x, end.x);
    const min_z = @min(start.z, end.z);
    const max_z = @max(start.z, end.z);
    const zone_index = project_editor_ui_world_scatter_helpers.findScatterZoneByBounds(state.scatter_preview.exclusions.items, min_x, min_z, max_x, max_z) orelse return;
    state.selected_world_curve_hit = .{ .target = .scatter_zone, .element = .width_rail, .index = zone_index };
    state.hovered_world_curve_hit = .{};
    project_editor_state.setStatus(state, "Scatter area selected");
}

const IndexedDistance = struct {
    index: usize,
    distance_sq: f32,
};

fn nearestRectangleCornerAtScreen(
    state: *ProjectEditorState,
    min_pt: editor_math.Vec3,
    max_pt: editor_math.Vec3,
    screen_x: f32,
    screen_y: f32,
    vp_w: f32,
    vp_h: f32,
    radius_px: f32,
) ?IndexedDistance {
    const corners = rectangleFootprintCorners(min_pt, max_pt);
    const radius_sq = radius_px * radius_px;
    var best: ?IndexedDistance = null;
    var best_distance = radius_sq;
    for (corners, 0..) |corner, index| {
        const screen = project_editor_state.projectViewportPoint(state, corner, vp_w, vp_h) orelse continue;
        const dist = distanceSq(screen_x, screen_y, screen.x, screen.y);
        if (dist <= best_distance) {
            best_distance = dist;
            best = .{ .index = index, .distance_sq = dist };
        }
    }
    return best;
}

fn nearestRectangleEdgeAtScreen(
    state: *ProjectEditorState,
    min_pt: editor_math.Vec3,
    max_pt: editor_math.Vec3,
    screen_x: f32,
    screen_y: f32,
    vp_w: f32,
    vp_h: f32,
    radius_px: f32,
) ?IndexedDistance {
    const corners = rectangleFootprintCorners(min_pt, max_pt);
    const radius_sq = radius_px * radius_px;
    var best: ?IndexedDistance = null;
    var best_distance = radius_sq;
    for (corners, 0..) |corner, index| {
        const next = corners[(index + 1) % corners.len];
        const p0 = project_editor_state.projectViewportPoint(state, corner, vp_w, vp_h) orelse continue;
        const p1 = project_editor_state.projectViewportPoint(state, next, vp_w, vp_h) orelse continue;
        const dist = distancePointSegmentSq(screen_x, screen_y, p0.x, p0.y, p1.x, p1.y);
        if (dist <= best_distance) {
            best_distance = dist;
            best = .{ .index = index, .distance_sq = dist };
        }
    }
    return best;
}

fn rectangleContainsGroundPoint(state: *ProjectEditorState, min_pt: editor_math.Vec3, max_pt: editor_math.Vec3, screen_x: f32, screen_y: f32) bool {
    const point = project_editor_blockout.screenToGroundPoint(state, screen_x, screen_y) orelse return false;
    return point.x >= @min(min_pt.x, max_pt.x) and point.x <= @max(min_pt.x, max_pt.x) and
        point.z >= @min(min_pt.z, max_pt.z) and point.z <= @max(min_pt.z, max_pt.z);
}

fn rectangleFootprintCorners(min_pt: editor_math.Vec3, max_pt: editor_math.Vec3) [4]editor_math.Vec3 {
    const y = @max(min_pt.y, 0.05);
    return .{
        .{ .x = min_pt.x, .y = y, .z = min_pt.z },
        .{ .x = max_pt.x, .y = y, .z = min_pt.z },
        .{ .x = max_pt.x, .y = y, .z = max_pt.z },
        .{ .x = min_pt.x, .y = y, .z = max_pt.z },
    };
}

fn drawRectangleFootprint(
    state: *ProjectEditorState,
    min_pt: editor_math.Vec3,
    max_pt: editor_math.Vec3,
    vp_w: f32,
    vp_h: f32,
    style: curve_drawing.AffordanceStyle,
    handle_state: curve_drawing.HandleState,
) void {
    const y = min_pt.y;
    const corners = [_]editor_math.Vec3{
        .{ .x = min_pt.x, .y = y, .z = min_pt.z },
        .{ .x = max_pt.x, .y = y, .z = min_pt.z },
        .{ .x = max_pt.x, .y = y, .z = max_pt.z },
        .{ .x = min_pt.x, .y = y, .z = max_pt.z },
    };
    for (corners, 0..) |corner, index| {
        const next = corners[(index + 1) % corners.len];
        curve_drawing.drawProjectedSegment(state, corner, next, vp_w, vp_h, style.preview_color);
        curve_drawing.drawProjectedHandle(state, corner, vp_w, vp_h, style, handle_state);
    }
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
    return distanceSq(px, py, cx, cy);
}

fn distanceSq(ax: f32, ay: f32, bx: f32, by: f32) f32 {
    const dx = ax - bx;
    const dy = ay - by;
    return dx * dx + dy * dy;
}
