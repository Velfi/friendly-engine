const std = @import("std");
const shared = @import("runtime_shared");
const editor_draw = @import("editor_draw.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_types = @import("project_editor_types.zig");
const project_editor_edit = @import("project_editor_edit.zig");
const project_editor_life_gizmo = @import("project_editor_life_gizmo.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const OverlayQuad = shared.gpu_scene.OverlayQuad;
const Vec2 = shared.editor_math.Vec2;
const Vec3 = shared.editor_math.Vec3;
const Color = shared.color.Color;
const GizmoAxis = project_editor_types.GizmoAxis;

const gallery_scene_path = "scenes/gizmo_gallery.kdl";

pub fn active(state: *const ProjectEditorState) bool {
    return std.mem.eql(u8, state.active_scene_path, gallery_scene_path);
}

pub fn drawSdl(state: *ProjectEditorState, renderer: *editor_draw.SDL_Renderer, viewport_rect: editor_draw.SDL_FRect) !void {
    if (!active(state)) return;
    const positions = galleryPositions(viewport_rect.w, viewport_rect.h);

    try drawMoveGizmoSdl(renderer, viewport_rect, positions.move, positions.axis_radius);
    try drawScaleGizmoSdl(renderer, viewport_rect, positions.scale, positions.axis_radius);
    try drawRotateGizmoSdl(renderer, viewport_rect, positions.rotate, positions.ring_radius);
    try drawCurveGizmoSdl(renderer, viewport_rect, positions.curve, positions.curve_radius);
    try drawBrushGizmoSdl(renderer, viewport_rect, positions.brush, positions.brush_radius);
}

pub fn appendGpuGallery(state: *ProjectEditorState, allocator: std.mem.Allocator, out: *std.ArrayList(OverlayQuad)) !void {
    if (!active(state)) return;
    const positions = galleryPositions(state.viewport_screen_rect.w, state.viewport_screen_rect.h);

    try appendMoveGizmo(state, allocator, out, positions.move, positions.axis_radius);
    try appendScaleGizmo(state, allocator, out, positions.scale, positions.axis_radius);
    try appendRotateGizmo(state, allocator, out, positions.rotate, positions.ring_radius);
    try appendCurveGizmo(state, allocator, out, positions.curve, positions.curve_radius);
    try appendBrushGizmo(state, allocator, out, positions.brush, positions.brush_radius);
}

pub fn appendSelectedTransformGizmo(state: *ProjectEditorState, allocator: std.mem.Allocator, out: *std.ArrayList(OverlayQuad)) !void {
    if (state.object_tool == .rotate) {
        try appendSelectedRotateGizmo(state, allocator, out);
        return;
    }
    if (state.object_tool != .move and state.object_tool != .scale) return;
    if (state.selected_object == null) return;
    const origin = project_editor_life_gizmo.gizmoOrigin(state) orelse return;
    const vp_w = state.viewport_screen_rect.w;
    const vp_h = state.viewport_screen_rect.h;
    const origin_screen = project_editor_state.projectViewportPoint(state, origin, vp_w, vp_h) orelse return;
    const handle_size: f32 = if (state.edit_channel == .scale) 12.0 else 8.0;

    const axes = [_]GizmoAxis{ .x, .y, .z };
    for (axes) |axis| {
        const active_axis = project_editor_edit.gizmoAxisActive(state, axis);
        const tip = Vec3.add(origin, project_editor_edit.gizmoAxisVector(state, axis));
        const tip_screen = project_editor_state.projectViewportPoint(state, tip, vp_w, vp_h) orelse continue;
        const color = project_editor_edit.gizmoAxisColor(axis, active_axis);
        try appendScreenLine(state, allocator, out, origin_screen, tip_screen, color, 4.0);
        try appendScreenSquare(state, allocator, out, tip_screen, color, handle_size);
    }
    try appendScreenSquare(state, allocator, out, origin_screen, .{ .r = 255, .g = 255, .b = 255, .a = 255 }, 6.0);
}

fn appendSelectedRotateGizmo(state: *ProjectEditorState, allocator: std.mem.Allocator, out: *std.ArrayList(OverlayQuad)) !void {
    if (state.selected_object == null) return;
    const origin = project_editor_life_gizmo.gizmoOrigin(state) orelse return;
    const radius = project_editor_edit.gizmoLength(state);
    const vp_w = state.viewport_screen_rect.w;
    const vp_h = state.viewport_screen_rect.h;
    const axes = [_]GizmoAxis{ .x, .y, .z };
    for (axes) |axis| {
        var prev: ?Vec2 = null;
        var i: usize = 0;
        while (i <= 72) : (i += 1) {
            const angle = (@as(f32, @floatFromInt(i)) / 72.0) * std.math.tau;
            const world = project_editor_edit.rotationRingPoint(origin, axis, radius, angle);
            const screen = project_editor_state.projectViewportPoint(state, world, vp_w, vp_h) orelse {
                prev = null;
                continue;
            };
            if (prev) |p| try appendScreenLine(state, allocator, out, p, screen, project_editor_edit.gizmoAxisColor(axis, true), 3.0);
            prev = screen;
        }
    }
}

fn appendMoveGizmo(state: *ProjectEditorState, allocator: std.mem.Allocator, out: *std.ArrayList(OverlayQuad), center: Vec2, radius: f32) !void {
    try appendScreenCircle(state, allocator, out, center, radius * 0.72, .{ .r = 18, .g = 22, .b = 28, .a = 92 }, 9.0);
    try appendAxes(state, allocator, out, center, radius, 8.0);
    try appendScreenSquare(state, allocator, out, center, .{ .r = 255, .g = 255, .b = 255, .a = 255 }, 7.0);
}

fn appendScaleGizmo(state: *ProjectEditorState, allocator: std.mem.Allocator, out: *std.ArrayList(OverlayQuad), center: Vec2, radius: f32) !void {
    try appendScreenCircle(state, allocator, out, center, radius * 0.72, .{ .r = 18, .g = 22, .b = 28, .a = 92 }, 9.0);
    try appendAxes(state, allocator, out, center, radius, 13.0);
    try appendScreenSquare(state, allocator, out, center, .{ .r = 255, .g = 255, .b = 255, .a = 255 }, 7.0);
}

fn appendAxes(state: *ProjectEditorState, allocator: std.mem.Allocator, out: *std.ArrayList(OverlayQuad), center: Vec2, radius: f32, handle_size: f32) !void {
    const endpoints = [_]struct { axis: GizmoAxis, point: Vec2 }{
        .{ .axis = .x, .point = .{ .x = center.x + radius, .y = center.y } },
        .{ .axis = .y, .point = .{ .x = center.x, .y = center.y - radius } },
        .{ .axis = .z, .point = .{ .x = center.x - radius * 0.58, .y = center.y + radius * 0.58 } },
    };
    for (endpoints) |endpoint| {
        const color = project_editor_edit.gizmoAxisColor(endpoint.axis, true);
        try appendScreenLine(state, allocator, out, center, endpoint.point, .{ .r = 12, .g = 15, .b = 20, .a = 150 }, 7.0);
        try appendScreenLine(state, allocator, out, center, endpoint.point, color, 4.0);
        try appendScreenSquare(state, allocator, out, endpoint.point, .{ .r = 12, .g = 15, .b = 20, .a = 210 }, handle_size + 5.0);
        try appendScreenSquare(state, allocator, out, endpoint.point, color, handle_size);
    }
}

fn appendRotateGizmo(state: *ProjectEditorState, allocator: std.mem.Allocator, out: *std.ArrayList(OverlayQuad), center: Vec2, radius: f32) !void {
    try appendScreenCircle(state, allocator, out, center, radius * 1.08, .{ .r = 18, .g = 22, .b = 28, .a = 105 }, 8.0);
    try appendScreenCircle(state, allocator, out, center, radius, project_editor_edit.gizmoAxisColor(.x, true), 3.0);
    try appendScreenEllipse(state, allocator, out, center, .{ .x = radius * 1.04, .y = radius * 0.46 }, project_editor_edit.gizmoAxisColor(.y, true), 3.0);
    try appendScreenEllipse(state, allocator, out, center, .{ .x = radius * 0.52, .y = radius * 1.0 }, project_editor_edit.gizmoAxisColor(.z, true), 3.0);
}

fn appendCurveGizmo(state: *ProjectEditorState, allocator: std.mem.Allocator, out: *std.ArrayList(OverlayQuad), center: Vec2, radius: f32) !void {
    const color: Color = .{ .r = 108, .g = 222, .b = 246, .a = 245 };
    const handle: Color = .{ .r = 255, .g = 236, .b = 132, .a = 255 };
    try appendScreenCircle(state, allocator, out, center, radius * 0.9, .{ .r = 18, .g = 22, .b = 28, .a = 84 }, 8.0);
    const pts = [_]Vec2{
        .{ .x = center.x - radius * 0.82, .y = center.y + radius * 0.48 },
        .{ .x = center.x - radius * 0.25, .y = center.y - radius * 0.22 },
        .{ .x = center.x + radius * 0.32, .y = center.y - radius * 0.38 },
        .{ .x = center.x + radius * 0.82, .y = center.y + radius * 0.34 },
    };
    var previous = pts[0];
    for (pts[1..]) |pt| {
        try appendScreenLine(state, allocator, out, previous, pt, .{ .r = 12, .g = 15, .b = 20, .a = 160 }, 7.0);
        try appendScreenLine(state, allocator, out, previous, pt, color, 4.0);
        previous = pt;
    }
    for (pts) |pt| {
        try appendScreenSquare(state, allocator, out, pt, .{ .r = 12, .g = 15, .b = 20, .a = 210 }, 14.0);
        try appendScreenSquare(state, allocator, out, pt, handle, 9.0);
    }
    try appendScreenLine(state, allocator, out, .{ .x = center.x - radius, .y = center.y - radius * 0.72 }, .{ .x = center.x - radius, .y = center.y + radius * 0.72 }, .{ .r = 12, .g = 15, .b = 20, .a = 160 }, 6.0);
    try appendScreenLine(state, allocator, out, .{ .x = center.x - radius, .y = center.y - radius * 0.72 }, .{ .x = center.x - radius, .y = center.y + radius * 0.72 }, handle, 3.0);
}

fn appendBrushGizmo(state: *ProjectEditorState, allocator: std.mem.Allocator, out: *std.ArrayList(OverlayQuad), center: Vec2, radius: f32) !void {
    const soft: Color = .{ .r = 115, .g = 205, .b = 255, .a = 80 };
    const color: Color = .{ .r = 115, .g = 205, .b = 255, .a = 230 };
    try appendScreenCircle(state, allocator, out, center, radius * 1.12, .{ .r = 18, .g = 22, .b = 28, .a = 110 }, 8.0);
    try appendScreenCircle(state, allocator, out, center, radius, soft, 7.0);
    try appendScreenCircle(state, allocator, out, center, radius, color, 3.0);
    try appendScreenLine(state, allocator, out, .{ .x = center.x - radius * 0.35, .y = center.y }, .{ .x = center.x + radius * 0.35, .y = center.y }, color, 3.0);
    try appendScreenLine(state, allocator, out, .{ .x = center.x, .y = center.y - radius * 0.35 }, .{ .x = center.x, .y = center.y + radius * 0.35 }, color, 3.0);
}

fn appendScreenCircle(state: *ProjectEditorState, allocator: std.mem.Allocator, out: *std.ArrayList(OverlayQuad), center: Vec2, radius: f32, color: Color, size: f32) !void {
    try appendScreenEllipse(state, allocator, out, center, .{ .x = radius, .y = radius }, color, size);
}

fn appendScreenEllipse(state: *ProjectEditorState, allocator: std.mem.Allocator, out: *std.ArrayList(OverlayQuad), center: Vec2, radius: Vec2, color: Color, size: f32) !void {
    var prev: ?Vec2 = null;
    var i: usize = 0;
    while (i <= 72) : (i += 1) {
        const angle = (@as(f32, @floatFromInt(i)) / 72.0) * std.math.tau;
        const point = Vec2{ .x = center.x + @cos(angle) * radius.x, .y = center.y + @sin(angle) * radius.y };
        if (prev) |p| try appendScreenLine(state, allocator, out, p, point, color, size);
        prev = point;
    }
}

fn appendScreenLine(state: *ProjectEditorState, allocator: std.mem.Allocator, out: *std.ArrayList(OverlayQuad), a: Vec2, b: Vec2, color: Color, size: f32) !void {
    if (!std.math.isFinite(a.x) or !std.math.isFinite(a.y) or !std.math.isFinite(b.x) or !std.math.isFinite(b.y)) return;
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    const dist = @sqrt(dx * dx + dy * dy);
    const steps: usize = @intFromFloat(@max(1.0, @ceil(dist / @max(1.0, size * 0.42))));
    var i: usize = 0;
    while (i <= steps) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps));
        try appendScreenSquare(state, allocator, out, .{ .x = a.x + dx * t, .y = a.y + dy * t }, color, size);
    }
}

fn appendScreenSquare(state: *ProjectEditorState, allocator: std.mem.Allocator, out: *std.ArrayList(OverlayQuad), screen: Vec2, color: Color, size: f32) !void {
    if (!std.math.isFinite(screen.x) or !std.math.isFinite(screen.y)) return;
    if (screen.x < -size or screen.y < -size or screen.x > state.viewport_screen_rect.w + size or screen.y > state.viewport_screen_rect.h + size) return;
    const half = size * 0.5;
    try out.append(allocator, .{
        .rect = .{
            state.viewport_screen_rect.x + screen.x - half,
            state.viewport_screen_rect.y + screen.y - half,
            size,
            size,
        },
        .color = color,
    });
}

fn drawMoveGizmoSdl(renderer: *editor_draw.SDL_Renderer, viewport_rect: editor_draw.SDL_FRect, center: Vec2, radius: f32) !void {
    try drawAxesSdl(renderer, viewport_rect, center, radius, 8.0);
    try drawSquareSdl(renderer, viewport_rect, center, .{ .r = 255, .g = 255, .b = 255, .a = 255 }, 7.0);
}

const GalleryPositions = struct {
    move: Vec2,
    scale: Vec2,
    rotate: Vec2,
    curve: Vec2,
    brush: Vec2,
    axis_radius: f32,
    ring_radius: f32,
    curve_radius: f32,
    brush_radius: f32,
};

fn galleryPositions(vp_w: f32, vp_h: f32) GalleryPositions {
    const top_y = std.math.clamp(vp_h * 0.34, 168.0, vp_h - 220.0);
    const bottom_y = std.math.clamp(vp_h * 0.57, top_y + 120.0, vp_h - 92.0);
    const axis_radius = std.math.clamp(@min(vp_w, vp_h) * 0.075, 38.0, 56.0);
    return .{
        .move = .{ .x = vp_w * 0.24, .y = top_y },
        .scale = .{ .x = vp_w * 0.50, .y = top_y },
        .rotate = .{ .x = vp_w * 0.76, .y = top_y },
        .curve = .{ .x = vp_w * 0.36, .y = bottom_y },
        .brush = .{ .x = vp_w * 0.64, .y = bottom_y },
        .axis_radius = axis_radius,
        .ring_radius = axis_radius * 0.86,
        .curve_radius = axis_radius * 0.92,
        .brush_radius = axis_radius * 0.78,
    };
}

fn drawScaleGizmoSdl(renderer: *editor_draw.SDL_Renderer, viewport_rect: editor_draw.SDL_FRect, center: Vec2, radius: f32) !void {
    try drawAxesSdl(renderer, viewport_rect, center, radius, 13.0);
    try drawSquareSdl(renderer, viewport_rect, center, .{ .r = 255, .g = 255, .b = 255, .a = 255 }, 7.0);
}

fn drawAxesSdl(renderer: *editor_draw.SDL_Renderer, viewport_rect: editor_draw.SDL_FRect, center: Vec2, radius: f32, handle_size: f32) !void {
    const endpoints = [_]struct { axis: GizmoAxis, point: Vec2 }{
        .{ .axis = .x, .point = .{ .x = center.x + radius, .y = center.y } },
        .{ .axis = .y, .point = .{ .x = center.x, .y = center.y - radius } },
        .{ .axis = .z, .point = .{ .x = center.x - radius * 0.58, .y = center.y + radius * 0.58 } },
    };
    for (endpoints) |endpoint| {
        const color = project_editor_edit.gizmoAxisColor(endpoint.axis, true);
        try drawLineSdl(renderer, viewport_rect, center, endpoint.point, color);
        try drawSquareSdl(renderer, viewport_rect, endpoint.point, color, handle_size);
    }
}

fn drawRotateGizmoSdl(renderer: *editor_draw.SDL_Renderer, viewport_rect: editor_draw.SDL_FRect, center: Vec2, radius: f32) !void {
    try drawEllipseSdl(renderer, viewport_rect, center, .{ .x = radius, .y = radius }, project_editor_edit.gizmoAxisColor(.x, true));
    try drawEllipseSdl(renderer, viewport_rect, center, .{ .x = radius * 1.04, .y = radius * 0.46 }, project_editor_edit.gizmoAxisColor(.y, true));
    try drawEllipseSdl(renderer, viewport_rect, center, .{ .x = radius * 0.52, .y = radius }, project_editor_edit.gizmoAxisColor(.z, true));
}

fn drawCurveGizmoSdl(renderer: *editor_draw.SDL_Renderer, viewport_rect: editor_draw.SDL_FRect, center: Vec2, radius: f32) !void {
    const color: Color = .{ .r = 108, .g = 222, .b = 246, .a = 245 };
    const handle: Color = .{ .r = 255, .g = 236, .b = 132, .a = 255 };
    const pts = [_]Vec2{
        .{ .x = center.x - radius * 0.82, .y = center.y + radius * 0.48 },
        .{ .x = center.x - radius * 0.25, .y = center.y - radius * 0.22 },
        .{ .x = center.x + radius * 0.32, .y = center.y - radius * 0.38 },
        .{ .x = center.x + radius * 0.82, .y = center.y + radius * 0.34 },
    };
    var previous = pts[0];
    for (pts[1..]) |pt| {
        try drawLineSdl(renderer, viewport_rect, previous, pt, color);
        previous = pt;
    }
    for (pts) |pt| try drawSquareSdl(renderer, viewport_rect, pt, handle, 9.0);
    try drawLineSdl(renderer, viewport_rect, .{ .x = center.x - radius, .y = center.y - radius * 0.72 }, .{ .x = center.x - radius, .y = center.y + radius * 0.72 }, handle);
}

fn drawBrushGizmoSdl(renderer: *editor_draw.SDL_Renderer, viewport_rect: editor_draw.SDL_FRect, center: Vec2, radius: f32) !void {
    const color: Color = .{ .r = 115, .g = 205, .b = 255, .a = 230 };
    try drawEllipseSdl(renderer, viewport_rect, center, .{ .x = radius, .y = radius }, color);
    try drawLineSdl(renderer, viewport_rect, .{ .x = center.x - radius * 0.35, .y = center.y }, .{ .x = center.x + radius * 0.35, .y = center.y }, color);
    try drawLineSdl(renderer, viewport_rect, .{ .x = center.x, .y = center.y - radius * 0.35 }, .{ .x = center.x, .y = center.y + radius * 0.35 }, color);
}

fn drawEllipseSdl(renderer: *editor_draw.SDL_Renderer, viewport_rect: editor_draw.SDL_FRect, center: Vec2, radius: Vec2, color: Color) !void {
    var prev: ?Vec2 = null;
    var i: usize = 0;
    while (i <= 72) : (i += 1) {
        const angle = (@as(f32, @floatFromInt(i)) / 72.0) * std.math.tau;
        const point = Vec2{ .x = center.x + @cos(angle) * radius.x, .y = center.y + @sin(angle) * radius.y };
        if (prev) |p| try drawLineSdl(renderer, viewport_rect, p, point, color);
        prev = point;
    }
}

fn drawLineSdl(renderer: *editor_draw.SDL_Renderer, viewport_rect: editor_draw.SDL_FRect, a: Vec2, b: Vec2, color: Color) !void {
    if (!editor_draw.SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a)) return error.SdlColorSetFailed;
    if (!editor_draw.SDL_RenderLine(renderer, viewport_rect.x + a.x, viewport_rect.y + a.y, viewport_rect.x + b.x, viewport_rect.y + b.y)) return error.SdlLineFailed;
}

fn drawSquareSdl(renderer: *editor_draw.SDL_Renderer, viewport_rect: editor_draw.SDL_FRect, center: Vec2, color: Color, size: f32) !void {
    const half = size * 0.5;
    const rect = editor_draw.SDL_FRect{
        .x = viewport_rect.x + center.x - half,
        .y = viewport_rect.y + center.y - half,
        .w = size,
        .h = size,
    };
    try editor_draw.drawPanel(renderer, rect, color, color);
}

test "gizmo gallery only activates for the gallery scene path" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .active_scene_path = gallery_scene_path,
        .objects = .empty,
    };
    try std.testing.expect(active(&state));
    state.active_scene_path = "scenes/main.kdl";
    try std.testing.expect(!active(&state));
}
