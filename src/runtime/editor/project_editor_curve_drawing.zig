const std = @import("std");
const shared = @import("runtime_shared");
const editor_math = shared.editor_math;
const shared_color = shared.color;
const project_editor_types = @import("project_editor_types.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_viewport = @import("project_editor_viewport.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
pub const CurveDrawMode = project_editor_types.CurveDrawMode;

pub const AffordanceTone = enum {
    ocean,
    water,
    scatter,
};

pub const HandleState = enum {
    normal,
    hover,
    selected,
    preview,
};

pub const AffordanceStyle = struct {
    line_color: shared_color.Color,
    handle_color: shared_color.Color,
    hover_color: shared_color.Color,
    selected_color: shared_color.Color,
    preview_color: shared_color.Color,
    insert_color: shared_color.Color,
};

pub fn styleForTone(tone: AffordanceTone) AffordanceStyle {
    return switch (tone) {
        .ocean => .{
            .line_color = .{ .r = 95, .g = 205, .b = 255, .a = 245 },
            .handle_color = .{ .r = 235, .g = 250, .b = 255, .a = 255 },
            .hover_color = .{ .r = 150, .g = 255, .b = 225, .a = 255 },
            .selected_color = .{ .r = 255, .g = 220, .b = 90, .a = 255 },
            .preview_color = .{ .r = 95, .g = 205, .b = 255, .a = 155 },
            .insert_color = .{ .r = 120, .g = 255, .b = 210, .a = 220 },
        },
        .water => .{
            .line_color = .{ .r = 60, .g = 180, .b = 230, .a = 235 },
            .handle_color = .{ .r = 215, .g = 245, .b = 255, .a = 245 },
            .hover_color = .{ .r = 125, .g = 235, .b = 255, .a = 255 },
            .selected_color = .{ .r = 255, .g = 225, .b = 110, .a = 255 },
            .preview_color = .{ .r = 85, .g = 210, .b = 255, .a = 170 },
            .insert_color = .{ .r = 145, .g = 235, .b = 255, .a = 210 },
        },
        .scatter => .{
            .line_color = .{ .r = 110, .g = 220, .b = 135, .a = 220 },
            .handle_color = .{ .r = 215, .g = 255, .b = 210, .a = 245 },
            .hover_color = .{ .r = 165, .g = 255, .b = 170, .a = 255 },
            .selected_color = .{ .r = 255, .g = 220, .b = 90, .a = 255 },
            .preview_color = .{ .r = 120, .g = 230, .b = 145, .a = 175 },
            .insert_color = .{ .r = 150, .g = 245, .b = 165, .a = 220 },
        },
    };
}

pub fn handleColor(style: AffordanceStyle, handle_state: HandleState) shared_color.Color {
    return switch (handle_state) {
        .normal => style.handle_color,
        .hover => style.hover_color,
        .selected => style.selected_color,
        .preview => style.preview_color,
    };
}

pub fn handleHalf(handle_state: HandleState) i32 {
    return switch (handle_state) {
        .normal => 4,
        .hover => 6,
        .selected => 8,
        .preview => 3,
    };
}

pub fn drawProjectedHandle(
    state: *ProjectEditorState,
    point: editor_math.Vec3,
    vp_w: f32,
    vp_h: f32,
    style: AffordanceStyle,
    handle_state: HandleState,
) void {
    const screen = project_editor_state.projectViewportPoint(state, point, vp_w, vp_h) orelse return;
    project_editor_viewport.drawViewportSquare(state, screen.x, screen.y, handleHalf(handle_state), handleColor(style, handle_state));
}

pub fn drawProjectedSegment(
    state: *ProjectEditorState,
    a: editor_math.Vec3,
    b: editor_math.Vec3,
    vp_w: f32,
    vp_h: f32,
    color: shared_color.Color,
) void {
    const a_screen = project_editor_state.projectViewportPoint(state, a, vp_w, vp_h) orelse return;
    const b_screen = project_editor_state.projectViewportPoint(state, b, vp_w, vp_h) orelse return;
    project_editor_viewport.drawViewportLine(state, a_screen.x, a_screen.y, b_screen.x, b_screen.y, color);
}

pub const Draft = struct {
    points: *std.ArrayList(editor_math.Vec3),
    preview_end: *?editor_math.Vec3,
};

pub fn clear(draft: Draft) void {
    draft.points.clearRetainingCapacity();
    draft.preview_end.* = null;
}

pub fn clearPreview(draft: Draft) void {
    draft.preview_end.* = null;
}

pub fn setPreview(draft: Draft, point: ?editor_math.Vec3) void {
    draft.preview_end.* = point;
}

pub fn beginFreehand(allocator: std.mem.Allocator, draft: Draft, point: editor_math.Vec3) !void {
    clear(draft);
    try appendPoint(allocator, draft, point, 0.0);
    draft.preview_end.* = point;
}

pub fn sampleFreehand(allocator: std.mem.Allocator, draft: Draft, point: editor_math.Vec3, min_spacing: f32) !void {
    draft.preview_end.* = point;
    try appendPoint(allocator, draft, point, min_spacing);
}

pub fn addPoint(allocator: std.mem.Allocator, draft: Draft, point: editor_math.Vec3, min_spacing: f32) !void {
    try appendPoint(allocator, draft, point, min_spacing);
    draft.preview_end.* = point;
}

pub fn finishablePoints(draft: Draft) ![]const editor_math.Vec3 {
    if (draft.points.items.len < 2) return error.CurveNeedsTwoPoints;
    return draft.points.items;
}

pub fn simplifyInPlace(allocator: std.mem.Allocator, draft: Draft, tolerance: f32) !usize {
    const source = draft.points.items;
    if (source.len <= 2 or tolerance <= 0) return 0;

    const Segment = struct { start: usize, end: usize };
    var keep = try allocator.alloc(bool, source.len);
    defer allocator.free(keep);
    @memset(keep, false);
    keep[0] = true;
    keep[source.len - 1] = true;

    var stack = std.ArrayList(Segment).empty;
    defer stack.deinit(allocator);
    try stack.append(allocator, .{ .start = 0, .end = source.len - 1 });

    while (stack.pop()) |segment| {
        if (segment.end <= segment.start + 1) continue;
        var best_index: usize = segment.start + 1;
        var best_distance: f32 = -1;
        var index = segment.start + 1;
        while (index < segment.end) : (index += 1) {
            const dist = pointSegmentDistanceXZ(source[index], source[segment.start], source[segment.end]);
            if (dist > best_distance) {
                best_distance = dist;
                best_index = index;
            }
        }
        if (best_distance > tolerance) {
            keep[best_index] = true;
            try stack.append(allocator, .{ .start = segment.start, .end = best_index });
            try stack.append(allocator, .{ .start = best_index, .end = segment.end });
        }
    }

    var simplified = std.ArrayList(editor_math.Vec3).empty;
    defer simplified.deinit(allocator);
    for (source, 0..) |point, index| {
        if (keep[index]) try simplified.append(allocator, point);
    }
    if (simplified.items.len < 2 or simplified.items.len >= source.len) return 0;

    const removed = source.len - simplified.items.len;
    draft.points.clearRetainingCapacity();
    try draft.points.appendSlice(allocator, simplified.items);
    draft.preview_end.* = draft.points.items[draft.points.items.len - 1];
    return removed;
}

pub fn drawDraft(
    state: *ProjectEditorState,
    draft: Draft,
    vp_w: f32,
    vp_h: f32,
    line_color: shared_color.Color,
    point_color: shared_color.Color,
    preview_color: shared_color.Color,
) void {
    var prev_screen: ?editor_math.Vec2 = null;
    for (draft.points.items) |point| {
        const screen = project_editor_state.projectViewportPoint(state, point, vp_w, vp_h) orelse {
            prev_screen = null;
            continue;
        };
        if (prev_screen) |prev| {
            project_editor_viewport.drawViewportLine(state, prev.x, prev.y, screen.x, screen.y, line_color);
        }
        project_editor_viewport.drawViewportSquare(state, screen.x, screen.y, 3, point_color);
        prev_screen = screen;
    }

    if (draft.points.items.len > 0) {
        const preview = draft.preview_end.* orelse return;
        const last = draft.points.items[draft.points.items.len - 1];
        if (samePoint(last, preview)) return;
        const last_screen = project_editor_state.projectViewportPoint(state, last, vp_w, vp_h) orelse return;
        const preview_screen = project_editor_state.projectViewportPoint(state, preview, vp_w, vp_h) orelse return;
        project_editor_viewport.drawViewportLine(state, last_screen.x, last_screen.y, preview_screen.x, preview_screen.y, preview_color);
    }
}

fn appendPoint(allocator: std.mem.Allocator, draft: Draft, point: editor_math.Vec3, min_spacing: f32) !void {
    if (draft.points.items.len > 0) {
        const prev = draft.points.items[draft.points.items.len - 1];
        if (distance(prev, point) < min_spacing) return error.PointTooClose;
    }
    try draft.points.append(allocator, point);
}

fn samePoint(a: editor_math.Vec3, b: editor_math.Vec3) bool {
    return a.x == b.x and a.y == b.y and a.z == b.z;
}

fn distance(a: editor_math.Vec3, b: editor_math.Vec3) f32 {
    return editor_math.Vec3.length(editor_math.Vec3.sub(a, b));
}

fn pointSegmentDistanceXZ(point: editor_math.Vec3, a: editor_math.Vec3, b: editor_math.Vec3) f32 {
    const vx = b.x - a.x;
    const vz = b.z - a.z;
    const len_sq = vx * vx + vz * vz;
    if (len_sq <= 0.000001) {
        const dx = point.x - a.x;
        const dz = point.z - a.z;
        return @sqrt(dx * dx + dz * dz);
    }
    const t = std.math.clamp(((point.x - a.x) * vx + (point.z - a.z) * vz) / len_sq, 0, 1);
    const nearest_x = a.x + vx * t;
    const nearest_z = a.z + vz * t;
    const dx = point.x - nearest_x;
    const dz = point.z - nearest_z;
    return @sqrt(dx * dx + dz * dz);
}

test "curve draft rejects finishing with fewer than two points" {
    var points = std.ArrayList(editor_math.Vec3).empty;
    defer points.deinit(std.testing.allocator);
    var preview: ?editor_math.Vec3 = null;
    const draft = Draft{ .points = &points, .preview_end = &preview };

    try std.testing.expectError(error.CurveNeedsTwoPoints, finishablePoints(draft));
    try addPoint(std.testing.allocator, draft, .{ .x = 0, .y = 0, .z = 0 }, 0.0);
    try std.testing.expectError(error.CurveNeedsTwoPoints, finishablePoints(draft));
}

test "curve draft filters close points and preserves order" {
    var points = std.ArrayList(editor_math.Vec3).empty;
    defer points.deinit(std.testing.allocator);
    var preview: ?editor_math.Vec3 = null;
    const draft = Draft{ .points = &points, .preview_end = &preview };

    try addPoint(std.testing.allocator, draft, .{ .x = 0, .y = 0, .z = 0 }, 0.5);
    try std.testing.expectError(error.PointTooClose, addPoint(std.testing.allocator, draft, .{ .x = 0.25, .y = 0, .z = 0 }, 0.5));
    try addPoint(std.testing.allocator, draft, .{ .x = 1, .y = 0, .z = 0 }, 0.5);

    const finished = try finishablePoints(draft);
    try std.testing.expectEqual(@as(usize, 2), finished.len);
    try std.testing.expectEqual(@as(f32, 0), finished[0].x);
    try std.testing.expectEqual(@as(f32, 1), finished[1].x);
}

test "curve draft clear resets points and preview" {
    var points = std.ArrayList(editor_math.Vec3).empty;
    defer points.deinit(std.testing.allocator);
    var preview: ?editor_math.Vec3 = null;
    const draft = Draft{ .points = &points, .preview_end = &preview };

    try beginFreehand(std.testing.allocator, draft, .{ .x = 1, .y = 2, .z = 3 });
    try std.testing.expectEqual(@as(usize, 1), points.items.len);
    try std.testing.expect(preview != null);

    clear(draft);
    try std.testing.expectEqual(@as(usize, 0), points.items.len);
    try std.testing.expectEqual(@as(?editor_math.Vec3, null), preview);
}

test "curve simplification removes nearly straight freehand samples" {
    var points = std.ArrayList(editor_math.Vec3).empty;
    defer points.deinit(std.testing.allocator);
    var preview: ?editor_math.Vec3 = null;
    const draft = Draft{ .points = &points, .preview_end = &preview };

    try addPoint(std.testing.allocator, draft, .{ .x = 0, .y = 0, .z = 0 }, 0);
    try addPoint(std.testing.allocator, draft, .{ .x = 1, .y = 0.1, .z = 0.02 }, 0);
    try addPoint(std.testing.allocator, draft, .{ .x = 2, .y = -0.2, .z = -0.03 }, 0);
    try addPoint(std.testing.allocator, draft, .{ .x = 3, .y = 0.15, .z = 0.01 }, 0);

    const removed = try simplifyInPlace(std.testing.allocator, draft, 0.1);

    try std.testing.expectEqual(@as(usize, 2), removed);
    try std.testing.expectEqual(@as(usize, 2), points.items.len);
    try std.testing.expectEqual(@as(f32, 0), points.items[0].x);
    try std.testing.expectEqual(@as(f32, 3), points.items[1].x);
}

test "curve simplification preserves visible bends" {
    var points = std.ArrayList(editor_math.Vec3).empty;
    defer points.deinit(std.testing.allocator);
    var preview: ?editor_math.Vec3 = null;
    const draft = Draft{ .points = &points, .preview_end = &preview };

    try addPoint(std.testing.allocator, draft, .{ .x = 0, .y = 0, .z = 0 }, 0);
    try addPoint(std.testing.allocator, draft, .{ .x = 2, .y = 0, .z = 0 }, 0);
    try addPoint(std.testing.allocator, draft, .{ .x = 4, .y = 0, .z = 3 }, 0);
    try addPoint(std.testing.allocator, draft, .{ .x = 6, .y = 0, .z = 3 }, 0);

    const removed = try simplifyInPlace(std.testing.allocator, draft, 0.5);

    try std.testing.expect(removed < 2);
    try std.testing.expect(points.items.len >= 3);
    var preserved_bend = false;
    for (points.items[1 .. points.items.len - 1]) |point| {
        if (point.z > 0) preserved_bend = true;
    }
    try std.testing.expect(preserved_bend);
}

test "affordance styles keep hover and selected handles distinct" {
    const ocean = styleForTone(.ocean);
    try std.testing.expectEqual(@as(i32, 4), handleHalf(.normal));
    try std.testing.expectEqual(@as(i32, 6), handleHalf(.hover));
    try std.testing.expectEqual(@as(i32, 8), handleHalf(.selected));
    try std.testing.expect(handleColor(ocean, .hover).g > handleColor(ocean, .normal).g);
    try std.testing.expect(handleColor(ocean, .selected).r >= handleColor(ocean, .normal).r);
}
