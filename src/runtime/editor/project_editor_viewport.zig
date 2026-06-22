const std = @import("std");
const shared = @import("runtime_shared");
const editor_math = shared.editor_math;
const shared_color = shared.color;
const editor_draw = @import("editor_draw.zig");
const editor_selection = @import("editor_selection.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_types = @import("project_editor_types.zig");
const project_editor_scene = @import("project_editor_scene.zig");
const project_editor_edit = @import("project_editor_edit.zig");
const project_editor_life_gizmo = @import("project_editor_life_gizmo.zig");
const scene_hierarchy = @import("editor_scene_hierarchy.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const OverlayQuad = shared.gpu_scene.OverlayQuad;
const GizmoAxis = project_editor_types.GizmoAxis;
const EditChannel = project_editor_types.EditChannel;
const wall_close_preview_distance: f32 = 0.35;

pub fn drawEditVertices(state: *ProjectEditorState, vp_w: f32, vp_h: f32) void {
    const idx = state.selected_object orelse return;
    const obj = &state.objects.items[idx];

    for (obj.mesh.vertices, 0..) |vert, vi| {
        const world = obj.transform().transformPoint(vert.position);
        const screen = project_editor_state.projectViewportPoint(state, world, vp_w, vp_h);
        if (screen == null) continue;
        const sp = screen.?;
        const px = @as(i32, @intFromFloat(sp.x));
        const py = @as(i32, @intFromFloat(sp.y));
        const selected = state.selected_vertex == @as(u32, @intCast(vi));
        const color: shared_color.Color = if (selected) .{ .r = 255, .g = 220, .b = 100, .a = 255 } else .{ .r = 255, .g = 255, .b = 255, .a = 255 };
        var dy: i32 = -1;
        while (dy <= 1) : (dy += 1) {
            var dx: i32 = -1;
            while (dx <= 1) : (dx += 1) {
                drawViewportPixel(state, px + dx, py + dy, color);
            }
        }
    }
}

pub fn drawObjectMarkers(state: *ProjectEditorState, vp_w: f32, vp_h: f32) void {
    const selected = state.selected_object;
    const hovered = state.hovered_object;
    for (state.objects.items, 0..) |*obj, idx| {
        if (!project_editor_state.objectVisible(state, obj)) continue;
        if (!obj.enabled) continue;
        if (obj.renderer_visible and obj.mesh.vertices.len > 0 and selected != idx and hovered != idx) continue;

        const world = scene_hierarchy.objectWorldPosition(state.objects.items, idx);
        const screen = project_editor_state.projectViewportPoint(state, world, vp_w, vp_h) orelse continue;
        const is_selected = selected == idx;
        const is_hovered = hovered == idx;
        const color: shared_color.Color = if (is_selected)
            .{ .r = 255, .g = 255, .b = 255, .a = 255 }
        else if (is_hovered)
            .{ .r = 120, .g = 235, .b = 255, .a = 235 }
        else
            markerColor(obj.object_kind);
        const half: i32 = if (is_selected) 6 else if (is_hovered) 5 else 4;
        drawViewportLine(state, screen.x - @as(f32, @floatFromInt(half)), screen.y, screen.x + @as(f32, @floatFromInt(half)), screen.y, color);
        drawViewportLine(state, screen.x, screen.y - @as(f32, @floatFromInt(half)), screen.x, screen.y + @as(f32, @floatFromInt(half)), color);
        drawViewportSquare(state, screen.x, screen.y, if (is_selected) 2 else 1, markerColor(obj.object_kind));
        if (obj.marker) |marker| drawMarkerOverlay(state, marker, world, screen, vp_w, vp_h, is_selected);
    }
}

pub fn appendGpuObjectMarkers(state: *ProjectEditorState, allocator: std.mem.Allocator, out: *std.ArrayList(OverlayQuad), vp_w: f32, vp_h: f32) !void {
    const selected = state.selected_object;
    const hovered = state.hovered_object;
    for (state.objects.items, 0..) |*obj, idx| {
        if (!project_editor_state.objectVisible(state, obj)) continue;
        if (!obj.enabled) continue;
        if (obj.renderer_visible and obj.mesh.vertices.len > 0 and selected != idx and hovered != idx) continue;

        const world = scene_hierarchy.objectWorldPosition(state.objects.items, idx);
        const screen = project_editor_state.projectViewportPoint(state, world, vp_w, vp_h) orelse continue;
        const is_selected = selected == idx;
        const is_hovered = hovered == idx;
        const color: shared_color.Color = if (is_selected)
            .{ .r = 255, .g = 255, .b = 255, .a = 255 }
        else if (is_hovered)
            .{ .r = 120, .g = 235, .b = 255, .a = 235 }
        else
            markerColor(obj.object_kind);
        const half: f32 = if (is_selected) 6 else if (is_hovered) 5 else 4;
        try appendGpuScreenLine(state, allocator, out, .{ .x = screen.x - half, .y = screen.y }, .{ .x = screen.x + half, .y = screen.y }, color, 2.0);
        try appendGpuScreenLine(state, allocator, out, .{ .x = screen.x, .y = screen.y - half }, .{ .x = screen.x, .y = screen.y + half }, color, 2.0);
        try appendGpuScreenSquare(state, allocator, out, screen, markerColor(obj.object_kind), if (is_selected) 5.0 else 3.0);
        if (obj.marker) |marker| try appendGpuMarkerOverlay(state, allocator, out, marker, world, screen, vp_w, vp_h, is_selected);
    }
}

pub fn drawSelectionBox(state: *ProjectEditorState) void {
    if (!state.selection_box_active) return;
    const rect = editor_selection.ScreenRect.fromDrag(state.selection_box_start, state.selection_box_end);
    const color: shared_color.Color = .{ .r = 120, .g = 220, .b = 255, .a = 230 };
    drawViewportLine(state, rect.min_x, rect.min_y, rect.max_x, rect.min_y, color);
    drawViewportLine(state, rect.max_x, rect.min_y, rect.max_x, rect.max_y, color);
    drawViewportLine(state, rect.max_x, rect.max_y, rect.min_x, rect.max_y, color);
    drawViewportLine(state, rect.min_x, rect.max_y, rect.min_x, rect.min_y, color);
}

pub fn appendGpuSelectionBox(state: *ProjectEditorState, allocator: std.mem.Allocator, out: *std.ArrayList(OverlayQuad)) !void {
    if (!state.selection_box_active) return;
    const rect = editor_selection.ScreenRect.fromDrag(state.selection_box_start, state.selection_box_end);
    const color: shared_color.Color = .{ .r = 120, .g = 220, .b = 255, .a = 230 };
    try appendGpuScreenLine(state, allocator, out, .{ .x = rect.min_x, .y = rect.min_y }, .{ .x = rect.max_x, .y = rect.min_y }, color, 2.0);
    try appendGpuScreenLine(state, allocator, out, .{ .x = rect.max_x, .y = rect.min_y }, .{ .x = rect.max_x, .y = rect.max_y }, color, 2.0);
    try appendGpuScreenLine(state, allocator, out, .{ .x = rect.max_x, .y = rect.max_y }, .{ .x = rect.min_x, .y = rect.max_y }, color, 2.0);
    try appendGpuScreenLine(state, allocator, out, .{ .x = rect.min_x, .y = rect.max_y }, .{ .x = rect.min_x, .y = rect.min_y }, color, 2.0);
}

fn appendGpuMarkerOverlay(
    state: *ProjectEditorState,
    allocator: std.mem.Allocator,
    out: *std.ArrayList(OverlayQuad),
    marker: shared.scene_marker.Marker,
    world: editor_math.Vec3,
    screen: editor_math.Vec2,
    vp_w: f32,
    vp_h: f32,
    selected: bool,
) !void {
    const color: shared_color.Color = if (selected)
        .{ .r = 120, .g = 235, .b = 255, .a = 255 }
    else
        .{ .r = 90, .g = 210, .b = 255, .a = 180 };
    if (marker.radius > 0 and marker.shape != .path) try appendGpuMarkerShapeOverlay(state, allocator, out, marker, world, screen, vp_w, vp_h, color);
    if (marker.kind == .player_start or marker.kind == .camera_point or marker.kind == .patrol_point) {
        try appendGpuScreenLine(state, allocator, out, .{ .x = screen.x, .y = screen.y - 18 }, .{ .x = screen.x, .y = screen.y - 34 }, color, 2.5);
        try appendGpuScreenLine(state, allocator, out, .{ .x = screen.x, .y = screen.y - 34 }, .{ .x = screen.x - 5, .y = screen.y - 27 }, color, 2.5);
        try appendGpuScreenLine(state, allocator, out, .{ .x = screen.x, .y = screen.y - 34 }, .{ .x = screen.x + 5, .y = screen.y - 27 }, color, 2.5);
    }
}

fn appendGpuMarkerShapeOverlay(
    state: *ProjectEditorState,
    allocator: std.mem.Allocator,
    out: *std.ArrayList(OverlayQuad),
    marker: shared.scene_marker.Marker,
    world: editor_math.Vec3,
    screen: editor_math.Vec2,
    vp_w: f32,
    vp_h: f32,
    color: shared_color.Color,
) !void {
    const screen_radius = markerScreenRadius(state, marker, world, screen, vp_w, vp_h);
    switch (marker.shape) {
        .box => {
            var fill = color;
            fill.a = @min(fill.a, 42);
            try appendGpuScreenRect(state, allocator, out, screen.x - screen_radius, screen.y - screen_radius, screen_radius * 2, screen_radius * 2, fill);
            try appendGpuScreenRectOutline(state, allocator, out, screen.x - screen_radius, screen.y - screen_radius, screen_radius * 2, screen_radius * 2, color, 2.5);
        },
        .sphere, .point => try appendGpuScreenRing(state, allocator, out, screen, screen_radius, color, 2.5),
        .path => {},
    }
}

fn appendGpuScreenRing(state: *ProjectEditorState, allocator: std.mem.Allocator, out: *std.ArrayList(OverlayQuad), center: editor_math.Vec2, radius: f32, color: shared_color.Color, size: f32) !void {
    const segments: usize = 48;
    var prev = editor_math.Vec2{ .x = center.x + radius, .y = center.y };
    var i: usize = 1;
    while (i <= segments) : (i += 1) {
        const t = (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(segments))) * std.math.tau;
        const next = editor_math.Vec2{ .x = center.x + @cos(t) * radius, .y = center.y + @sin(t) * radius };
        try appendGpuScreenLine(state, allocator, out, prev, next, color, size);
        prev = next;
    }
}

fn appendGpuScreenRectOutline(
    state: *ProjectEditorState,
    allocator: std.mem.Allocator,
    out: *std.ArrayList(OverlayQuad),
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    color: shared_color.Color,
    size: f32,
) !void {
    try appendGpuScreenLine(state, allocator, out, .{ .x = x, .y = y }, .{ .x = x + w, .y = y }, color, size);
    try appendGpuScreenLine(state, allocator, out, .{ .x = x + w, .y = y }, .{ .x = x + w, .y = y + h }, color, size);
    try appendGpuScreenLine(state, allocator, out, .{ .x = x + w, .y = y + h }, .{ .x = x, .y = y + h }, color, size);
    try appendGpuScreenLine(state, allocator, out, .{ .x = x, .y = y + h }, .{ .x = x, .y = y }, color, size);
}

fn appendGpuScreenRect(state: *ProjectEditorState, allocator: std.mem.Allocator, out: *std.ArrayList(OverlayQuad), x: f32, y: f32, w: f32, h: f32, color: shared_color.Color) !void {
    if (!std.math.isFinite(x) or !std.math.isFinite(y) or !std.math.isFinite(w) or !std.math.isFinite(h)) return;
    if (w <= 0 or h <= 0) return;
    if (x + w < 0 or y + h < 0 or x > state.viewport_screen_rect.w or y > state.viewport_screen_rect.h) return;
    try out.append(allocator, .{
        .rect = .{
            state.viewport_screen_rect.x + x,
            state.viewport_screen_rect.y + y,
            w,
            h,
        },
        .color = color,
    });
}

fn appendGpuScreenLine(state: *ProjectEditorState, allocator: std.mem.Allocator, out: *std.ArrayList(OverlayQuad), a: editor_math.Vec2, b: editor_math.Vec2, color: shared_color.Color, size: f32) !void {
    if (!std.math.isFinite(a.x) or !std.math.isFinite(a.y) or !std.math.isFinite(b.x) or !std.math.isFinite(b.y)) return;
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    const dist = @sqrt(dx * dx + dy * dy);
    const steps: usize = @intFromFloat(@max(1.0, @ceil(dist / @max(1.0, size * 0.42))));
    var i: usize = 0;
    while (i <= steps) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps));
        try appendGpuScreenSquare(state, allocator, out, .{ .x = a.x + dx * t, .y = a.y + dy * t }, color, size);
    }
}

fn appendGpuScreenSquare(state: *ProjectEditorState, allocator: std.mem.Allocator, out: *std.ArrayList(OverlayQuad), screen: editor_math.Vec2, color: shared_color.Color, size: f32) !void {
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

fn drawMarkerOverlay(
    state: *ProjectEditorState,
    marker: shared.scene_marker.Marker,
    world: editor_math.Vec3,
    screen: editor_math.Vec2,
    vp_w: f32,
    vp_h: f32,
    selected: bool,
) void {
    const color: shared_color.Color = if (selected)
        .{ .r = 120, .g = 235, .b = 255, .a = 255 }
    else
        .{ .r = 90, .g = 210, .b = 255, .a = 180 };
    if (marker.radius > 0 and marker.shape != .path) drawMarkerShapeOverlay(state, marker, world, screen, vp_w, vp_h, color);
    if (marker.kind == .player_start or marker.kind == .camera_point or marker.kind == .patrol_point) {
        drawViewportLine(state, screen.x, screen.y - 18, screen.x, screen.y - 34, color);
        drawViewportLine(state, screen.x, screen.y - 34, screen.x - 5, screen.y - 27, color);
        drawViewportLine(state, screen.x, screen.y - 34, screen.x + 5, screen.y - 27, color);
    }
}

fn drawMarkerShapeOverlay(
    state: *ProjectEditorState,
    marker: shared.scene_marker.Marker,
    world: editor_math.Vec3,
    screen: editor_math.Vec2,
    vp_w: f32,
    vp_h: f32,
    color: shared_color.Color,
) void {
    const screen_radius = markerScreenRadius(state, marker, world, screen, vp_w, vp_h);
    switch (marker.shape) {
        .box => {
            var fill = color;
            fill.a = @min(fill.a, 42);
            drawViewportRect(state, screen.x - screen_radius, screen.y - screen_radius, screen_radius * 2, screen_radius * 2, fill);
            drawViewportRectOutline(state, screen.x - screen_radius, screen.y - screen_radius, screen_radius * 2, screen_radius * 2, color);
        },
        .sphere, .point => drawViewportRing(state, screen.x, screen.y, screen_radius, color),
        .path => {},
    }
}

fn markerScreenRadius(
    state: *const ProjectEditorState,
    marker: shared.scene_marker.Marker,
    world: editor_math.Vec3,
    screen: editor_math.Vec2,
    vp_w: f32,
    vp_h: f32,
) f32 {
    const right = state.camera.right();
    const radius_world = editor_math.Vec3.add(world, editor_math.Vec3.scale(right, marker.radius));
    var screen_radius: f32 = @min(42, @max(@as(f32, 10), marker.radius * 6.0));
    if (project_editor_state.projectViewportPoint(state, radius_world, vp_w, vp_h)) |edge| {
        const dx = edge.x - screen.x;
        const dy = edge.y - screen.y;
        screen_radius = @min(42, @max(screen_radius, @sqrt(dx * dx + dy * dy)));
    }
    return screen_radius;
}

fn drawViewportRing(state: *ProjectEditorState, cx: f32, cy: f32, r: f32, color: shared_color.Color) void {
    const segments: usize = 24;
    var prev_x = cx + r;
    var prev_y = cy;
    var i: usize = 1;
    while (i <= segments) : (i += 1) {
        const t = (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(segments))) * std.math.tau;
        const x = cx + @cos(t) * r;
        const y = cy + @sin(t) * r;
        drawViewportLine(state, prev_x, prev_y, x, y, color);
        prev_x = x;
        prev_y = y;
    }
}

fn drawViewportRectOutline(state: *ProjectEditorState, x: f32, y: f32, w: f32, h: f32, color: shared_color.Color) void {
    drawViewportLine(state, x, y, x + w, y, color);
    drawViewportLine(state, x + w, y, x + w, y + h, color);
    drawViewportLine(state, x + w, y + h, x, y + h, color);
    drawViewportLine(state, x, y + h, x, y, color);
}

fn markerColor(kind: shared.scene_document.ObjectKind) shared_color.Color {
    return switch (kind) {
        .empty => .{ .r = 80, .g = 210, .b = 150, .a = 255 },
        .light => .{ .r = 255, .g = 222, .b = 120, .a = 255 },
        .camera => .{ .r = 120, .g = 190, .b = 255, .a = 255 },
        .trigger => .{ .r = 180, .g = 120, .b = 255, .a = 255 },
        .audio => .{ .r = 125, .g = 230, .b = 210, .a = 255 },
        .prefab => .{ .r = 220, .g = 165, .b = 90, .a = 255 },
        .marker => .{ .r = 90, .g = 210, .b = 255, .a = 255 },
        .mesh => .{ .r = 170, .g = 180, .b = 195, .a = 255 },
    };
}

pub fn drawViewportPixel(state: *ProjectEditorState, px: i32, py: i32, color: shared_color.Color) void {
    recordViewportOverlay(state, .{
        .kind = .pixel,
        .color = color,
        .x0 = @floatFromInt(px),
        .y0 = @floatFromInt(py),
    });
    const overlay_renderer = state.viewport_overlay_renderer orelse return;
    if (!editor_draw.SDL_SetRenderDrawColor(overlay_renderer, color.r, color.g, color.b, color.a)) return;
    const rect = state.viewport_overlay_rect;
    _ = editor_draw.SDL_RenderPoint(overlay_renderer, rect.x + @as(f32, @floatFromInt(px)), rect.y + @as(f32, @floatFromInt(py)));
}

pub fn drawViewportLine(state: *ProjectEditorState, x0: f32, y0: f32, x1: f32, y1: f32, color: shared_color.Color) void {
    const clip_w = state.viewport_overlay_rect.w;
    const clip_h = state.viewport_overlay_rect.h;
    const clipped = clipViewportLine(
        .{ .x = x0, .y = y0 },
        .{ .x = x1, .y = y1 },
        clip_w,
        clip_h,
    ) orelse return;
    const c0 = clipped[0];
    const c1 = clipped[1];
    recordViewportOverlay(state, .{
        .kind = .line,
        .color = color,
        .x0 = c0.x,
        .y0 = c0.y,
        .x1 = c1.x,
        .y1 = c1.y,
    });

    const overlay_renderer = state.viewport_overlay_renderer orelse return;
    if (!editor_draw.SDL_SetRenderDrawColor(overlay_renderer, color.r, color.g, color.b, color.a)) return;
    const rect = state.viewport_overlay_rect;
    _ = editor_draw.SDL_RenderLine(
        overlay_renderer,
        rect.x + c0.x,
        rect.y + c0.y,
        rect.x + c1.x,
        rect.y + c1.y,
    );
}

fn clipViewportLine(a: editor_math.Vec2, b: editor_math.Vec2, width: f32, height: f32) ?[2]editor_math.Vec2 {
    var p0 = a;
    var p1 = b;
    while (true) {
        const out0 = viewportOutCode(p0, width, height);
        const out1 = viewportOutCode(p1, width, height);
        if ((out0 | out1) == 0) return .{ p0, p1 };
        if ((out0 & out1) != 0) return null;

        const out = if (out0 != 0) out0 else out1;
        const clipped = clipViewportPoint(p0, p1, out, width, height);
        if (out == out0) {
            p0 = clipped;
        } else {
            p1 = clipped;
        }
    }
}

fn viewportOutCode(p: editor_math.Vec2, width: f32, height: f32) u4 {
    var code: u4 = 0;
    if (p.x < 0.0) code |= 1;
    if (p.x > width - 1.0) code |= 2;
    if (p.y < 0.0) code |= 4;
    if (p.y > height - 1.0) code |= 8;
    return code;
}

fn clipViewportPoint(a: editor_math.Vec2, b: editor_math.Vec2, out: u4, width: f32, height: f32) editor_math.Vec2 {
    const max_x = width - 1.0;
    const max_y = height - 1.0;
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    const t = if ((out & 4) != 0)
        (0.0 - a.y) / dy
    else if ((out & 8) != 0)
        (max_y - a.y) / dy
    else if ((out & 2) != 0)
        (max_x - a.x) / dx
    else
        (0.0 - a.x) / dx;
    return .{
        .x = a.x + dx * t,
        .y = a.y + dy * t,
    };
}

pub fn drawViewportSquare(state: *ProjectEditorState, cx: f32, cy: f32, half: i32, color: shared_color.Color) void {
    recordViewportOverlay(state, .{
        .kind = .square,
        .color = color,
        .x0 = cx,
        .y0 = cy,
        .half = half,
    });
    const px: i32 = @intFromFloat(cx);
    const py: i32 = @intFromFloat(cy);
    var dy: i32 = -half;
    while (dy <= half) : (dy += 1) {
        var dx: i32 = -half;
        while (dx <= half) : (dx += 1) {
            drawViewportPixel(state, px + dx, py + dy, color);
        }
    }
}

pub fn drawViewportRect(state: *ProjectEditorState, x: f32, y: f32, w: f32, h: f32, color: shared_color.Color) void {
    recordViewportOverlay(state, .{
        .kind = .rect,
        .color = color,
        .x0 = x,
        .y0 = y,
        .w = w,
        .h = h,
    });
    const overlay_renderer = state.viewport_overlay_renderer orelse return;
    if (!editor_draw.SDL_SetRenderDrawColor(overlay_renderer, color.r, color.g, color.b, color.a)) return;
    const viewport = state.viewport_overlay_rect;
    const rect = editor_draw.SDL_FRect{ .x = viewport.x + x, .y = viewport.y + y, .w = w, .h = h };
    _ = editor_draw.SDL_RenderFillRect(overlay_renderer, &rect);
}

fn recordViewportOverlay(state: *ProjectEditorState, primitive: project_editor_state.ViewportOverlayPrimitive) void {
    if (state.viewport_overlay_recorder) |recorder| recorder.record(state.allocator, primitive);
}

test "box marker overlay records translucent volume footprint" {
    var recorder = project_editor_state.ViewportOverlayRecorder{};
    defer recorder.deinit(std.testing.allocator);
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .viewport_overlay_rect = .{ .x = 0, .y = 0, .w = 320, .h = 240 },
        .viewport_overlay_recorder = &recorder,
    };

    drawMarkerShapeOverlay(
        &state,
        .{ .kind = .trigger_volume, .shape = .box, .radius = 2.0 },
        .{ .x = 0, .y = 0, .z = 0 },
        .{ .x = 160, .y = 120 },
        320,
        240,
        .{ .r = 90, .g = 210, .b = 255, .a = 180 },
    );

    try std.testing.expectEqual(@as(usize, 1), recorder.countKind(.rect));
    try std.testing.expect(recorder.countKind(.line) >= 4);
    try std.testing.expect(recorder.primitives.items[0].color.a <= 42);
}

test "sphere marker overlay remains a radius ring" {
    var recorder = project_editor_state.ViewportOverlayRecorder{};
    defer recorder.deinit(std.testing.allocator);
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .viewport_overlay_rect = .{ .x = 0, .y = 0, .w = 320, .h = 240 },
        .viewport_overlay_recorder = &recorder,
    };

    drawMarkerShapeOverlay(
        &state,
        .{ .kind = .audio_emitter, .shape = .sphere, .radius = 3.0 },
        .{ .x = 0, .y = 0, .z = 0 },
        .{ .x = 160, .y = 120 },
        320,
        240,
        .{ .r = 90, .g = 210, .b = 255, .a = 180 },
    );

    try std.testing.expectEqual(@as(usize, 0), recorder.countKind(.rect));
    try std.testing.expect(recorder.countKind(.line) >= 20);
}

pub fn drawBlockoutPreview(state: *ProjectEditorState, vp_w: f32, vp_h: f32) void {
    if (state.architecture_tool == .wall) {
        drawWallDragPreview(state, vp_w, vp_h);
        return;
    }
    if (state.architecture_tool == .curve) {
        @import("project_editor_architecture_curve.zig").drawDraft(state, vp_w, vp_h);
        return;
    }
    const bounds = project_editor_scene.architectureDragPreviewAabb(state) orelse return;
    const color = architectureDragPreviewColor(state);
    drawAabbWireframe(state, bounds.min, bounds.max, vp_w, vp_h, color);
}

fn architectureDragPreviewColor(state: *const ProjectEditorState) shared_color.Color {
    return switch (state.architecture_tool) {
        .door, .window, .subtract => .{ .r = 230, .g = 90, .b = 70, .a = 220 },
        else => if (state.blockout_op == .subtract)
            .{ .r = 230, .g = 90, .b = 70, .a = 220 }
        else
            .{ .r = 125, .g = 223, .b = 247, .a = 220 },
    };
}

fn drawWallDragPreview(state: *ProjectEditorState, vp_w: f32, vp_h: f32) void {
    const start = state.blockout_drag_start orelse return;
    const end = state.blockout_drag_end orelse return;
    const dx = end.x - start.x;
    const dz = end.z - start.z;
    const length = @sqrt(dx * dx + dz * dz);
    if (length <= 0.001) return;

    const half_t = @max(0.05, state.architecture_wall_thickness) * 0.5;
    const height = @max(0.25, state.architecture_wall_height);
    const nx = -dz / length * half_t;
    const nz = dx / length * half_t;
    const corners = [_]editor_math.Vec3{
        .{ .x = start.x + nx, .y = 0, .z = start.z + nz },
        .{ .x = end.x + nx, .y = 0, .z = end.z + nz },
        .{ .x = end.x - nx, .y = 0, .z = end.z - nz },
        .{ .x = start.x - nx, .y = 0, .z = start.z - nz },
        .{ .x = start.x + nx, .y = height, .z = start.z + nz },
        .{ .x = end.x + nx, .y = height, .z = end.z + nz },
        .{ .x = end.x - nx, .y = height, .z = end.z - nz },
        .{ .x = start.x - nx, .y = height, .z = start.z - nz },
    };
    drawPrismWireframe(state, corners, vp_w, vp_h, .{ .r = 125, .g = 223, .b = 247, .a = 220 });
}

pub fn drawWallOutlinePreview(state: *ProjectEditorState, vp_w: f32, vp_h: f32) void {
    if (state.wall_outline_points.items.len == 0) return;
    const point_color: shared_color.Color = .{ .r = 255, .g = 240, .b = 150, .a = 255 };
    const line_color: shared_color.Color = .{ .r = 125, .g = 220, .b = 255, .a = 230 };
    const close_color: shared_color.Color = .{ .r = 90, .g = 240, .b = 170, .a = 255 };
    var prev_screen: ?editor_math.Vec2 = null;
    for (state.wall_outline_points.items, 0..) |point, idx| {
        const screen = project_editor_state.projectViewportPoint(state, point, vp_w, vp_h) orelse {
            prev_screen = null;
            continue;
        };
        if (prev_screen) |prev| drawViewportLine(state, prev.x, prev.y, screen.x, screen.y, line_color);
        const is_first = idx == 0 and state.wall_outline_points.items.len >= 2;
        drawViewportSquare(state, screen.x, screen.y, if (is_first) 5 else 3, if (is_first) close_color else point_color);
        prev_screen = screen;
    }

    const hover = project_editor_scene.screenToGroundPoint(state, state.mouse_x, state.mouse_y) orelse return;
    const first = state.wall_outline_points.items[0];
    const last = state.wall_outline_points.items[state.wall_outline_points.items.len - 1];
    const closes = state.wall_outline_points.items.len >= 2 and pointsNear2d(hover, first, wall_close_preview_distance);
    const target = if (closes) first else hover;
    const last_screen = project_editor_state.projectViewportPoint(state, last, vp_w, vp_h) orelse return;
    const target_screen = project_editor_state.projectViewportPoint(state, target, vp_w, vp_h) orelse return;
    const preview_color = if (closes) close_color else line_color;
    drawViewportLine(state, last_screen.x, last_screen.y, target_screen.x, target_screen.y, preview_color);
    drawViewportSquare(state, target_screen.x, target_screen.y, if (closes) 6 else 3, preview_color);
}

fn pointsNear2d(a: editor_math.Vec3, b: editor_math.Vec3, distance: f32) bool {
    const dx = a.x - b.x;
    const dz = a.z - b.z;
    return dx * dx + dz * dz <= distance * distance;
}

pub fn drawSelectedFace(state: *ProjectEditorState, vp_w: f32, vp_h: f32) void {
    const obj_idx = state.selected_object orelse return;
    const face_tri = state.selected_face orelse return;
    const obj = &state.objects.items[obj_idx];
    if (face_tri + 2 >= obj.mesh.indices.len) return;
    const xf = obj.transform();
    const vi0 = obj.mesh.indices[face_tri];
    const vi1 = obj.mesh.indices[face_tri + 1];
    const vi2 = obj.mesh.indices[face_tri + 2];
    const w0 = xf.transformPoint(obj.mesh.vertices[vi0].position);
    const w1 = xf.transformPoint(obj.mesh.vertices[vi1].position);
    const w2 = xf.transformPoint(obj.mesh.vertices[vi2].position);
    const s0 = project_editor_state.projectViewportPoint(state, w0, vp_w, vp_h) orelse return;
    const s1 = project_editor_state.projectViewportPoint(state, w1, vp_w, vp_h) orelse return;
    const s2 = project_editor_state.projectViewportPoint(state, w2, vp_w, vp_h) orelse return;
    const color: shared_color.Color = .{ .r = 255, .g = 220, .b = 100, .a = 255 };
    drawViewportLine(state, s0.x, s0.y, s1.x, s1.y, color);
    drawViewportLine(state, s1.x, s1.y, s2.x, s2.y, color);
    drawViewportLine(state, s2.x, s2.y, s0.x, s0.y, color);
}

pub fn drawSelectedEdge(state: *ProjectEditorState, vp_w: f32, vp_h: f32) void {
    const obj_idx = state.selected_object orelse return;
    const edge = state.selected_edge orelse return;
    const obj = &state.objects.items[obj_idx];
    if (edge[0] >= obj.mesh.vertices.len or edge[1] >= obj.mesh.vertices.len) return;
    const xf = obj.transform();
    const w0 = xf.transformPoint(obj.mesh.vertices[edge[0]].position);
    const w1 = xf.transformPoint(obj.mesh.vertices[edge[1]].position);
    const s0 = project_editor_state.projectViewportPoint(state, w0, vp_w, vp_h) orelse return;
    const s1 = project_editor_state.projectViewportPoint(state, w1, vp_w, vp_h) orelse return;
    const color: shared_color.Color = .{ .r = 125, .g = 220, .b = 255, .a = 255 };
    drawViewportLine(state, s0.x, s0.y, s1.x, s1.y, color);
    drawViewportSquare(state, s0.x, s0.y, 3, color);
    drawViewportSquare(state, s1.x, s1.y, 3, color);
}

pub fn drawTransformGizmo(state: *ProjectEditorState, vp_w: f32, vp_h: f32) void {
    if (state.object_tool == .rotate) {
        drawRotateGizmo(state, vp_w, vp_h);
        return;
    }
    if (state.object_tool != .move and state.object_tool != .scale) return;
    if (state.selected_object == null) return;
    const origin = project_editor_life_gizmo.gizmoOrigin(state) orelse return;
    const origin_screen = project_editor_state.projectViewportPoint(state, origin, vp_w, vp_h) orelse return;
    const handle_half: i32 = if (state.edit_channel == .scale) 6 else 4;

    const axes = [_]GizmoAxis{ .x, .y, .z };
    for (axes) |axis| {
        const active = project_editor_edit.gizmoAxisActive(state, axis);
        const tip = editor_math.Vec3.add(origin, project_editor_edit.gizmoAxisVector(state, axis));
        const tip_screen = project_editor_state.projectViewportPoint(state, tip, vp_w, vp_h) orelse continue;
        drawViewportLine(state, origin_screen.x, origin_screen.y, tip_screen.x, tip_screen.y, project_editor_edit.gizmoAxisColor(axis, active));
        drawViewportSquare(state, tip_screen.x, tip_screen.y, handle_half, project_editor_edit.gizmoAxisColor(axis, active));
    }
    drawViewportSquare(state, origin_screen.x, origin_screen.y, 3, .{ .r = 255, .g = 255, .b = 255, .a = 255 });
}

pub fn drawRotateGizmo(state: *ProjectEditorState, vp_w: f32, vp_h: f32) void {
    const origin = project_editor_life_gizmo.gizmoOrigin(state) orelse return;
    const radius = project_editor_edit.gizmoLength(state);
    const axes = [_]GizmoAxis{ .x, .y, .z };
    for (axes) |axis| {
        const color = project_editor_edit.gizmoAxisColor(axis, true);
        var prev: ?editor_math.Vec2 = null;
        var i: usize = 0;
        while (i <= 72) : (i += 1) {
            const angle = (@as(f32, @floatFromInt(i)) / 72.0) * 6.28318530718;
            const world = project_editor_edit.rotationRingPoint(origin, axis, radius, angle);
            const screen = project_editor_state.projectViewportPoint(state, world, vp_w, vp_h) orelse {
                prev = null;
                continue;
            };
            if (prev) |p| drawViewportLine(state, p.x, p.y, screen.x, screen.y, color);
            prev = screen;
        }
    }
}

pub fn drawTransformGizmoOverlay(
    state: *ProjectEditorState,
    renderer: *editor_draw.SDL_Renderer,
    viewport_rect: editor_draw.SDL_FRect,
) !void {
    if (state.object_tool == .rotate) {
        try drawRotateGizmoOverlay(state, renderer, viewport_rect);
        return;
    }
    if (state.object_tool != .move and state.object_tool != .scale) return;
    if (state.selected_object == null) return;
    const origin = project_editor_life_gizmo.gizmoOrigin(state) orelse return;
    const vp_w = viewport_rect.w;
    const vp_h = viewport_rect.h;
    const origin_screen = project_editor_state.projectViewportPoint(state, origin, vp_w, vp_h) orelse return;
    const handle_half: f32 = if (state.edit_channel == .scale) 6.0 else 4.0;

    const axes = [_]GizmoAxis{ .x, .y, .z };
    for (axes) |axis| {
        const active = project_editor_edit.gizmoAxisActive(state, axis);
        const tip = editor_math.Vec3.add(origin, project_editor_edit.gizmoAxisVector(state, axis));
        const tip_screen = project_editor_state.projectViewportPoint(state, tip, vp_w, vp_h) orelse continue;
        const color = project_editor_edit.gizmoAxisColor(axis, active);
        if (!editor_draw.SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a)) return error.SdlColorSetFailed;
        const x0 = viewport_rect.x + origin_screen.x;
        const y0 = viewport_rect.y + origin_screen.y;
        const x1 = viewport_rect.x + tip_screen.x;
        const y1 = viewport_rect.y + tip_screen.y;
        if (!editor_draw.SDL_RenderLine(renderer, x0, y0, x1, y1)) return error.SdlLineFailed;

        const hx = viewport_rect.x + tip_screen.x;
        const hy = viewport_rect.y + tip_screen.y;
        const handle_rect = editor_draw.SDL_FRect{
            .x = hx - handle_half,
            .y = hy - handle_half,
            .w = handle_half * 2.0,
            .h = handle_half * 2.0,
        };
        try editor_draw.drawPanel(renderer, handle_rect, color, color);
    }
}

fn drawRotateGizmoOverlay(
    state: *ProjectEditorState,
    renderer: *editor_draw.SDL_Renderer,
    viewport_rect: editor_draw.SDL_FRect,
) !void {
    const origin = project_editor_life_gizmo.gizmoOrigin(state) orelse return;
    const radius = project_editor_edit.gizmoLength(state);
    const axes = [_]GizmoAxis{ .x, .y, .z };
    for (axes) |axis| {
        const color = project_editor_edit.gizmoAxisColor(axis, true);
        if (!editor_draw.SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a)) return error.SdlColorSetFailed;
        var prev: ?editor_math.Vec2 = null;
        var i: usize = 0;
        while (i <= 72) : (i += 1) {
            const angle = (@as(f32, @floatFromInt(i)) / 72.0) * 6.28318530718;
            const world = project_editor_edit.rotationRingPoint(origin, axis, radius, angle);
            const screen = project_editor_state.projectViewportPoint(state, world, viewport_rect.w, viewport_rect.h) orelse {
                prev = null;
                continue;
            };
            if (prev) |p| {
                if (!editor_draw.SDL_RenderLine(
                    renderer,
                    viewport_rect.x + p.x,
                    viewport_rect.y + p.y,
                    viewport_rect.x + screen.x,
                    viewport_rect.y + screen.y,
                )) return error.SdlLineFailed;
            }
            prev = screen;
        }
    }
}
pub fn gizmoAxisColor(axis: GizmoAxis, active: bool) shared_color.Color {
    const alpha: u8 = if (active) 255 else 90;
    return switch (axis) {
        .x => .{ .r = 230, .g = 70, .b = 70, .a = alpha },
        .y => .{ .r = 90, .g = 210, .b = 90, .a = alpha },
        .z => .{ .r = 80, .g = 130, .b = 230, .a = alpha },
    };
}

pub fn drawAabbWireframe(
    state: *ProjectEditorState,
    min_pt: editor_math.Vec3,
    max_pt: editor_math.Vec3,
    vp_w: f32,
    vp_h: f32,
    color: shared_color.Color,
) void {
    const corners = [_]editor_math.Vec3{
        .{ .x = min_pt.x, .y = min_pt.y, .z = min_pt.z },
        .{ .x = max_pt.x, .y = min_pt.y, .z = min_pt.z },
        .{ .x = max_pt.x, .y = max_pt.y, .z = min_pt.z },
        .{ .x = min_pt.x, .y = max_pt.y, .z = min_pt.z },
        .{ .x = min_pt.x, .y = min_pt.y, .z = max_pt.z },
        .{ .x = max_pt.x, .y = min_pt.y, .z = max_pt.z },
        .{ .x = max_pt.x, .y = max_pt.y, .z = max_pt.z },
        .{ .x = min_pt.x, .y = max_pt.y, .z = max_pt.z },
    };
    drawPrismWireframe(state, corners, vp_w, vp_h, color);
}

fn drawPrismWireframe(
    state: *ProjectEditorState,
    corners: [8]editor_math.Vec3,
    vp_w: f32,
    vp_h: f32,
    color: shared_color.Color,
) void {
    var screens: [8]?editor_math.Vec2 = undefined;
    for (corners, 0..) |corner, i| {
        screens[i] = project_editor_state.projectViewportPoint(state, corner, vp_w, vp_h);
    }
    const edges = [_][2]usize{
        .{ 0, 1 }, .{ 1, 2 }, .{ 2, 3 }, .{ 3, 0 },
        .{ 4, 5 }, .{ 5, 6 }, .{ 6, 7 }, .{ 7, 4 },
        .{ 0, 4 }, .{ 1, 5 }, .{ 2, 6 }, .{ 3, 7 },
    };
    for (edges) |edge| {
        const s0 = screens[edge[0]] orelse continue;
        const s1 = screens[edge[1]] orelse continue;
        drawViewportLine(state, s0.x, s0.y, s1.x, s1.y, color);
    }
}
