const std = @import("std");
const shared = @import("runtime_shared");
const editor_math = shared.editor_math;
const editor_draw = @import("editor_draw.zig");
const draw_primitives = @import("editor_draw_primitives.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_types = @import("project_editor_types.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const ViewNavControl = project_editor_types.ViewNavControl;
const OverlayQuad = shared.gpu_api.OverlayQuad;

const axis_radius: f32 = 8.5;
const orbit_radius: f32 = 38.0;
const nav_button_radius: f32 = 14.0;
const panel_pad: f32 = 18.0;

const Hit = union(enum) {
    none,
    control: ViewNavControl,
    axis: project_editor_types.ViewOrientation,
};

pub fn hitTest(state: *const ProjectEditorState, x: f32, y: f32) Hit {
    if (!editor_draw.pointInRect(x, y, state.viewport_screen_rect)) return .none;
    const layout = computeLayout(state, state.viewport_screen_rect);
    if (pointInCircle(x, y, layout.x_axis.screen.x, layout.x_axis.screen.y, axis_radius + 4.0)) return .{ .axis = .side };
    if (pointInCircle(x, y, layout.y_axis.screen.x, layout.y_axis.screen.y, axis_radius + 4.0)) return .{ .axis = .top };
    if (pointInCircle(x, y, layout.z_axis.screen.x, layout.z_axis.screen.y, axis_radius + 4.0)) return .{ .axis = .front };
    if (pointInCircle(x, y, layout.center.x, layout.center.y, 18.0)) return .{ .control = .orbit };
    if (pointInCircle(x, y, rectCenterX(layout.zoom_rect), rectCenterY(layout.zoom_rect), nav_button_radius)) return .{ .control = .zoom };
    if (pointInCircle(x, y, rectCenterX(layout.pan_rect), rectCenterY(layout.pan_rect), nav_button_radius)) return .{ .control = .pan };
    return .none;
}

pub fn applyAxisSnap(state: *ProjectEditorState, orientation: project_editor_types.ViewOrientation) void {
    state.view_orientation = orientation;
    switch (orientation) {
        .free => {},
        .top => {
            state.camera.yaw = 0.0;
            state.camera.pitch = 1.35;
            project_editor_state.setStatus(state, "Top view");
        },
        .front => {
            state.camera.yaw = std.math.pi;
            state.camera.pitch = 0.0;
            project_editor_state.setStatus(state, "Front view");
        },
        .side => {
            state.camera.yaw = std.math.pi * 0.5;
            state.camera.pitch = 0.0;
            project_editor_state.setStatus(state, "Side view");
        },
    }
}

pub fn drawOverlay(
    state: *const ProjectEditorState,
    renderer: *editor_draw.SDL_Renderer,
    text_renderer: *editor_draw.TextRenderer,
    viewport_rect: editor_draw.SDL_FRect,
) !void {
    const layout = computeLayout(state, viewport_rect);
    try drawAxisLines(renderer, layout);
    try draw_primitives.fillCircle(renderer, layout.center.x, layout.center.y, 9.0, .{ .r = 213, .g = 220, .b = 230, .a = 232 });
    try draw_primitives.strokeCircle(renderer, layout.center.x, layout.center.y, 9.0, 1.0, .{ .r = 42, .g = 48, .b = 59, .a = 190 });
    try drawAxisDots(renderer, text_renderer, layout);

    const zoom_active = state.active_view_nav == .zoom;
    const pan_active = state.active_view_nav == .pan;
    try drawNavButton(renderer, layout.zoom_rect, .zoom, zoom_active);
    try drawNavButton(renderer, layout.pan_rect, .pan, pan_active);
}

pub fn drawGpuOverlay(
    state: *const ProjectEditorState,
    allocator: std.mem.Allocator,
    gpu: *shared.gpu_api.GpuRenderer,
    viewport_rect: editor_draw.SDL_FRect,
    scale: f32,
) !void {
    const layout = computeLayout(state, viewport_rect);
    var quads: std.ArrayList(OverlayQuad) = .empty;
    defer quads.deinit(allocator);

    try appendAxisLinesGpu(allocator, &quads, layout);
    try appendCircleGpu(allocator, &quads, layout.center.x, layout.center.y, 9.0, .fill, .{ .r = 213, .g = 220, .b = 230, .a = 232 });
    try appendCircleGpu(allocator, &quads, layout.center.x, layout.center.y, 9.0, .{ .stroke = 1.0 }, .{ .r = 42, .g = 48, .b = 59, .a = 190 });
    try appendAxisDotsGpu(allocator, &quads, layout);

    const zoom_active = state.active_view_nav == .zoom;
    const pan_active = state.active_view_nav == .pan;
    try appendNavButtonGpu(allocator, &quads, layout.zoom_rect, .zoom, zoom_active);
    try appendNavButtonGpu(allocator, &quads, layout.pan_rect, .pan, pan_active);

    scaleOverlayQuads(quads.items, scale);
    try gpu.drawOverlayQuads(quads.items);
}

const Layout = struct {
    center: editor_math.Vec2,
    x_axis: AxisLayout,
    y_axis: AxisLayout,
    z_axis: AxisLayout,
    zoom_rect: editor_draw.SDL_FRect,
    pan_rect: editor_draw.SDL_FRect,
};

const AxisLayout = struct {
    screen: editor_math.Vec2,
    depth: f32,
    label: []const u8,
    color: editor_draw.Color,
};

fn computeLayout(state: *const ProjectEditorState, viewport_rect: editor_draw.SDL_FRect) Layout {
    const center = editor_math.Vec2{
        .x = viewport_rect.x + viewport_rect.w - panel_pad - orbit_radius,
        .y = viewport_rect.y + panel_pad + orbit_radius,
    };
    return .{
        .center = center,
        .x_axis = axisLayout(state, center, "X", .{ .x = 1.0, .y = 0.0, .z = 0.0 }, .{ .r = 232, .g = 75, .b = 72, .a = 255 }),
        .y_axis = axisLayout(state, center, "Y", .{ .x = 0.0, .y = 1.0, .z = 0.0 }, .{ .r = 86, .g = 205, .b = 93, .a = 255 }),
        .z_axis = axisLayout(state, center, "Z", .{ .x = 0.0, .y = 0.0, .z = 1.0 }, .{ .r = 91, .g = 137, .b = 235, .a = 255 }),
        .zoom_rect = circleRect(center.x, center.y + 50.0, nav_button_radius),
        .pan_rect = circleRect(center.x, center.y + 83.0, nav_button_radius),
    };
}

fn axisLayout(state: *const ProjectEditorState, center: editor_math.Vec2, label: []const u8, axis: editor_math.Vec3, color: editor_draw.Color) AxisLayout {
    const right = state.camera.right();
    const forward = state.camera.forward();
    const up = editor_math.Vec3.normalized(editor_math.cross(right, forward));
    const screen_x = editor_math.Vec3.dot(axis, right);
    const screen_y = -editor_math.Vec3.dot(axis, up);
    const depth = editor_math.Vec3.dot(axis, forward);
    const length = orbit_radius * (0.82 + @max(0.0, depth) * 0.12);
    return .{
        .screen = .{ .x = center.x + screen_x * length, .y = center.y + screen_y * length },
        .depth = depth,
        .label = label,
        .color = color,
    };
}

fn drawAxisLines(renderer: *editor_draw.SDL_Renderer, layout: Layout) !void {
    var axes = sortedAxes(layout);
    for (&axes) |axis| {
        var color = axis.color;
        color.a = if (axis.depth < -0.05) 130 else 225;
        try drawAxis(renderer, layout.center, axis.screen, color);
    }
}

fn appendAxisLinesGpu(
    allocator: std.mem.Allocator,
    quads: *std.ArrayList(OverlayQuad),
    layout: Layout,
) !void {
    var axes = sortedAxes(layout);
    for (&axes) |axis| {
        var color = axis.color;
        color.a = if (axis.depth < -0.05) 130 else 225;
        try appendLineGpu(allocator, quads, layout.center.x, layout.center.y, axis.screen.x, axis.screen.y, 1.5, color);
    }
}

fn drawAxisDots(renderer: *editor_draw.SDL_Renderer, text_renderer: *editor_draw.TextRenderer, layout: Layout) !void {
    var axes = sortedAxes(layout);
    for (&axes) |axis| {
        var color = axis.color;
        color.a = if (axis.depth < -0.05) 170 else 255;
        try drawAxisDot(renderer, text_renderer, axis.screen, axis.label, color);
    }
}

fn appendAxisDotsGpu(
    allocator: std.mem.Allocator,
    quads: *std.ArrayList(OverlayQuad),
    layout: Layout,
) !void {
    var axes = sortedAxes(layout);
    for (&axes) |axis| {
        var color = axis.color;
        color.a = if (axis.depth < -0.05) 170 else 255;
        try appendCircleGpu(allocator, quads, axis.screen.x, axis.screen.y, axis_radius, .fill, color);
        try appendCircleGpu(allocator, quads, axis.screen.x, axis.screen.y, axis_radius, .{ .stroke = 1.0 }, .{ .r = 20, .g = 24, .b = 31, .a = 135 });
        try appendAxisLabelGpu(allocator, quads, axis.screen, axis.label, .{ .r = 245, .g = 248, .b = 252, .a = 255 });
    }
}

fn sortedAxes(layout: Layout) [3]AxisLayout {
    var axes = [_]AxisLayout{ layout.x_axis, layout.y_axis, layout.z_axis };
    var i: usize = 0;
    while (i < axes.len) : (i += 1) {
        var j = i + 1;
        while (j < axes.len) : (j += 1) {
            if (axes[i].depth > axes[j].depth) {
                const tmp = axes[i];
                axes[i] = axes[j];
                axes[j] = tmp;
            }
        }
    }
    return axes;
}

fn drawAxis(renderer: *editor_draw.SDL_Renderer, from: editor_math.Vec2, to: editor_math.Vec2, color: editor_draw.Color) !void {
    try draw_primitives.line(renderer, from.x, from.y, to.x, to.y, 1.5, color);
}

fn drawAxisDot(renderer: *editor_draw.SDL_Renderer, text_renderer: *editor_draw.TextRenderer, center: editor_math.Vec2, label: []const u8, color: editor_draw.Color) !void {
    try draw_primitives.fillCircle(renderer, center.x, center.y, axis_radius, color);
    try draw_primitives.strokeCircle(renderer, center.x, center.y, axis_radius, 1.0, .{ .r = 20, .g = 24, .b = 31, .a = 135 });
    var batch = @import("editor_ui_batch.zig").UiDrawBatch.init(std.heap.page_allocator);
    defer batch.deinit();
    try text_renderer.draw(renderer, &batch, label, center.x - 4.5, center.y - 8.5, color);
}

fn drawNavButton(renderer: *editor_draw.SDL_Renderer, rect: editor_draw.SDL_FRect, control: ViewNavControl, active: bool) !void {
    const fill: editor_draw.Color = if (active)
        .{ .r = 74, .g = 92, .b = 124, .a = 230 }
    else
        .{ .r = 20, .g = 25, .b = 34, .a = 168 };
    const cx = rectCenterX(rect);
    const cy = rectCenterY(rect);
    try draw_primitives.fillCircle(renderer, cx, cy, nav_button_radius, fill);
    try draw_primitives.strokeCircle(renderer, cx, cy, nav_button_radius, 1.0, .{ .r = 104, .g = 119, .b = 140, .a = 125 });
    const icon_color: editor_draw.Color = .{ .r = 232, .g = 238, .b = 247, .a = 255 };
    switch (control) {
        .zoom => try drawZoomIcon(renderer, rect, icon_color),
        .pan => try drawPanIcon(renderer, rect, icon_color),
        .orbit, .none => {},
    }
}

fn appendNavButtonGpu(
    allocator: std.mem.Allocator,
    quads: *std.ArrayList(OverlayQuad),
    rect: editor_draw.SDL_FRect,
    control: ViewNavControl,
    active: bool,
) !void {
    const fill: editor_draw.Color = if (active)
        .{ .r = 74, .g = 92, .b = 124, .a = 230 }
    else
        .{ .r = 20, .g = 25, .b = 34, .a = 168 };
    const cx = rectCenterX(rect);
    const cy = rectCenterY(rect);
    try appendCircleGpu(allocator, quads, cx, cy, nav_button_radius, .fill, fill);
    try appendCircleGpu(allocator, quads, cx, cy, nav_button_radius, .{ .stroke = 1.0 }, .{ .r = 104, .g = 119, .b = 140, .a = 125 });
    const icon_color: editor_draw.Color = .{ .r = 232, .g = 238, .b = 247, .a = 255 };
    switch (control) {
        .zoom => try appendZoomIconGpu(allocator, quads, rect, icon_color),
        .pan => try appendPanIconGpu(allocator, quads, rect, icon_color),
        .orbit, .none => {},
    }
}

fn drawZoomIcon(renderer: *editor_draw.SDL_Renderer, rect: editor_draw.SDL_FRect, color: editor_draw.Color) !void {
    // Iconoir search.svg: M17 17L21 21 and an 8px-radius lens centered on 11,11.
    const bounds = iconBounds(rect);
    try drawIconCircleOutline(renderer, bounds, 11.0, 11.0, 8.0, color);
    try drawIconLine(renderer, bounds, 17.0, 17.0, 21.0, 21.0, color);
}

fn appendZoomIconGpu(
    allocator: std.mem.Allocator,
    quads: *std.ArrayList(OverlayQuad),
    rect: editor_draw.SDL_FRect,
    color: editor_draw.Color,
) !void {
    const bounds = iconBounds(rect);
    try appendIconCircleOutlineGpu(allocator, quads, bounds, 11.0, 11.0, 8.0, color);
    try appendIconLineGpu(allocator, quads, bounds, 17.0, 17.0, 21.0, 21.0, color);
}

fn drawPanIcon(renderer: *editor_draw.SDL_Renderer, rect: editor_draw.SDL_FRect, color: editor_draw.Color) !void {
    // Iconoir drag-hand-gesture.svg, simplified from its SVG path coordinates.
    const bounds = iconBounds(rect);
    try drawIconPolyline(renderer, bounds, &.{
        .{ .x = 7.0, .y = 10.5 },
        .{ .x = 4.996, .y = 13.172 },
        .{ .x = 5.122, .y = 15.724 },
        .{ .x = 8.906, .y = 19.852 },
        .{ .x = 10.379, .y = 20.5 },
        .{ .x = 15.0, .y = 20.5 },
        .{ .x = 19.0, .y = 16.5 },
        .{ .x = 19.0, .y = 7.929 },
    }, color);
    try drawIconPolyline(renderer, bounds, &.{ .{ .x = 16.0, .y = 8.5 }, .{ .x = 16.0, .y = 7.929 }, .{ .x = 17.5, .y = 6.214 }, .{ .x = 19.0, .y = 7.929 } }, color);
    try drawIconPolyline(renderer, bounds, &.{ .{ .x = 13.0, .y = 8.5 }, .{ .x = 13.0, .y = 7.027 }, .{ .x = 14.5, .y = 5.313 }, .{ .x = 16.0, .y = 7.027 }, .{ .x = 16.0, .y = 8.5 } }, color);
    try drawIconPolyline(renderer, bounds, &.{ .{ .x = 10.0, .y = 8.5 }, .{ .x = 10.0, .y = 6.5 }, .{ .x = 11.5, .y = 4.786 }, .{ .x = 13.0, .y = 6.5 }, .{ .x = 13.0, .y = 8.5 } }, color);
    try drawIconPolyline(renderer, bounds, &.{ .{ .x = 7.0, .y = 13.5 }, .{ .x = 7.0, .y = 6.5 }, .{ .x = 8.5, .y = 5.0 }, .{ .x = 10.0, .y = 6.384 }, .{ .x = 10.0, .y = 8.5 } }, color);
}

fn appendPanIconGpu(
    allocator: std.mem.Allocator,
    quads: *std.ArrayList(OverlayQuad),
    rect: editor_draw.SDL_FRect,
    color: editor_draw.Color,
) !void {
    const bounds = iconBounds(rect);
    try appendIconPolylineGpu(allocator, quads, bounds, &.{
        .{ .x = 7.0, .y = 10.5 },
        .{ .x = 4.996, .y = 13.172 },
        .{ .x = 5.122, .y = 15.724 },
        .{ .x = 8.906, .y = 19.852 },
        .{ .x = 10.379, .y = 20.5 },
        .{ .x = 15.0, .y = 20.5 },
        .{ .x = 19.0, .y = 16.5 },
        .{ .x = 19.0, .y = 7.929 },
    }, color);
    try appendIconPolylineGpu(allocator, quads, bounds, &.{ .{ .x = 16.0, .y = 8.5 }, .{ .x = 16.0, .y = 7.929 }, .{ .x = 17.5, .y = 6.214 }, .{ .x = 19.0, .y = 7.929 } }, color);
    try appendIconPolylineGpu(allocator, quads, bounds, &.{ .{ .x = 13.0, .y = 8.5 }, .{ .x = 13.0, .y = 7.027 }, .{ .x = 14.5, .y = 5.313 }, .{ .x = 16.0, .y = 7.027 }, .{ .x = 16.0, .y = 8.5 } }, color);
    try appendIconPolylineGpu(allocator, quads, bounds, &.{ .{ .x = 10.0, .y = 8.5 }, .{ .x = 10.0, .y = 6.5 }, .{ .x = 11.5, .y = 4.786 }, .{ .x = 13.0, .y = 6.5 }, .{ .x = 13.0, .y = 8.5 } }, color);
    try appendIconPolylineGpu(allocator, quads, bounds, &.{ .{ .x = 7.0, .y = 13.5 }, .{ .x = 7.0, .y = 6.5 }, .{ .x = 8.5, .y = 5.0 }, .{ .x = 10.0, .y = 6.384 }, .{ .x = 10.0, .y = 8.5 } }, color);
}

const IconBounds = struct {
    x: f32,
    y: f32,
    scale: f32,
};

fn iconBounds(rect: editor_draw.SDL_FRect) IconBounds {
    const size = @min(rect.w, rect.h) - 9.0;
    return .{
        .x = rect.x + (rect.w - size) * 0.5,
        .y = rect.y + (rect.h - size) * 0.5,
        .scale = size / 24.0,
    };
}

fn drawIconCircleOutline(renderer: *editor_draw.SDL_Renderer, bounds: IconBounds, cx: f32, cy: f32, radius: f32, color: editor_draw.Color) !void {
    try draw_primitives.strokeCircle(
        renderer,
        bounds.x + cx * bounds.scale,
        bounds.y + cy * bounds.scale,
        radius * bounds.scale,
        1.25,
        color,
    );
}

fn drawIconPolyline(renderer: *editor_draw.SDL_Renderer, bounds: IconBounds, points: []const editor_math.Vec2, color: editor_draw.Color) !void {
    if (points.len < 2) return;
    var i: usize = 1;
    while (i < points.len) : (i += 1) {
        try drawIconLine(renderer, bounds, points[i - 1].x, points[i - 1].y, points[i].x, points[i].y, color);
    }
}

fn appendIconPolylineGpu(
    allocator: std.mem.Allocator,
    quads: *std.ArrayList(OverlayQuad),
    bounds: IconBounds,
    points: []const editor_math.Vec2,
    color: editor_draw.Color,
) !void {
    if (points.len < 2) return;
    var i: usize = 1;
    while (i < points.len) : (i += 1) {
        try appendIconLineGpu(allocator, quads, bounds, points[i - 1].x, points[i - 1].y, points[i].x, points[i].y, color);
    }
}

fn drawIconLine(renderer: *editor_draw.SDL_Renderer, bounds: IconBounds, x0: f32, y0: f32, x1: f32, y1: f32, color: editor_draw.Color) !void {
    try drawColoredLine(
        renderer,
        bounds.x + x0 * bounds.scale,
        bounds.y + y0 * bounds.scale,
        bounds.x + x1 * bounds.scale,
        bounds.y + y1 * bounds.scale,
        color,
    );
}

fn appendIconLineGpu(
    allocator: std.mem.Allocator,
    quads: *std.ArrayList(OverlayQuad),
    bounds: IconBounds,
    x0: f32,
    y0: f32,
    x1: f32,
    y1: f32,
    color: editor_draw.Color,
) !void {
    try appendLineGpu(
        allocator,
        quads,
        bounds.x + x0 * bounds.scale,
        bounds.y + y0 * bounds.scale,
        bounds.x + x1 * bounds.scale,
        bounds.y + y1 * bounds.scale,
        1.25,
        color,
    );
}

fn appendIconCircleOutlineGpu(
    allocator: std.mem.Allocator,
    quads: *std.ArrayList(OverlayQuad),
    bounds: IconBounds,
    cx: f32,
    cy: f32,
    radius: f32,
    color: editor_draw.Color,
) !void {
    try appendCircleGpu(
        allocator,
        quads,
        bounds.x + cx * bounds.scale,
        bounds.y + cy * bounds.scale,
        radius * bounds.scale,
        .{ .stroke = 1.25 },
        color,
    );
}

fn appendAxisLabelGpu(
    allocator: std.mem.Allocator,
    quads: *std.ArrayList(OverlayQuad),
    center: editor_math.Vec2,
    label: []const u8,
    color: editor_draw.Color,
) !void {
    const x = center.x - 4.5;
    const y = center.y - 5.5;
    if (std.mem.eql(u8, label, "X")) {
        try appendLineGpu(allocator, quads, x, y, x + 9.0, y + 11.0, 1.25, color);
        try appendLineGpu(allocator, quads, x + 9.0, y, x, y + 11.0, 1.25, color);
    } else if (std.mem.eql(u8, label, "Y")) {
        try appendLineGpu(allocator, quads, x, y, x + 4.5, y + 5.5, 1.25, color);
        try appendLineGpu(allocator, quads, x + 9.0, y, x + 4.5, y + 5.5, 1.25, color);
        try appendLineGpu(allocator, quads, x + 4.5, y + 5.5, x + 4.5, y + 11.0, 1.25, color);
    } else if (std.mem.eql(u8, label, "Z")) {
        try appendLineGpu(allocator, quads, x, y, x + 9.0, y, 1.25, color);
        try appendLineGpu(allocator, quads, x + 9.0, y, x, y + 11.0, 1.25, color);
        try appendLineGpu(allocator, quads, x, y + 11.0, x + 9.0, y + 11.0, 1.25, color);
    }
}

const CircleMode = union(enum) {
    fill,
    stroke: f32,
};

fn appendCircleGpu(
    allocator: std.mem.Allocator,
    quads: *std.ArrayList(OverlayQuad),
    cx: f32,
    cy: f32,
    radius: f32,
    mode: CircleMode,
    color: editor_draw.Color,
) !void {
    switch (mode) {
        .fill => {
            var y = -@floor(radius);
            while (y <= radius) : (y += 1.0) {
                const x_extent = @sqrt(@max(0.0, radius * radius - y * y));
                try appendSolidRect(allocator, quads, cx - x_extent, cy + y, x_extent * 2.0, 1.0, color);
            }
        },
        .stroke => |stroke_width| {
            const samples: usize = 56;
            var i: usize = 0;
            while (i < samples) : (i += 1) {
                const t = (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(samples))) * std.math.tau;
                const x = cx + @cos(t) * radius;
                const y = cy + @sin(t) * radius;
                try appendSolidRect(allocator, quads, x - stroke_width, y - stroke_width, stroke_width * 2.0, stroke_width * 2.0, color);
            }
        },
    }
}

fn appendLineGpu(
    allocator: std.mem.Allocator,
    quads: *std.ArrayList(OverlayQuad),
    x0: f32,
    y0: f32,
    x1: f32,
    y1: f32,
    width: f32,
    color: editor_draw.Color,
) !void {
    const dx = x1 - x0;
    const dy = y1 - y0;
    const length = @sqrt(dx * dx + dy * dy);
    const steps: usize = @max(1, @as(usize, @intFromFloat(@ceil(length))));
    var i: usize = 0;
    while (i <= steps) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps));
        const x = x0 + dx * t;
        const y = y0 + dy * t;
        try appendSolidRect(allocator, quads, x - width * 0.5, y - width * 0.5, width, width, color);
    }
}

fn appendSolidRect(
    allocator: std.mem.Allocator,
    quads: *std.ArrayList(OverlayQuad),
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    color: editor_draw.Color,
) !void {
    if (w <= 0.0 or h <= 0.0) return;
    try quads.append(allocator, .{
        .rect = .{ x, y, w, h },
        .color = color,
    });
}

fn scaleOverlayQuads(quads: []OverlayQuad, scale: f32) void {
    if (scale == 1) return;
    for (quads) |*quad| {
        quad.rect[0] *= scale;
        quad.rect[1] *= scale;
        quad.rect[2] *= scale;
        quad.rect[3] *= scale;
        quad.skew_x *= scale;
    }
}

fn drawColoredLine(renderer: *editor_draw.SDL_Renderer, x0: f32, y0: f32, x1: f32, y1: f32, color: editor_draw.Color) !void {
    try draw_primitives.line(renderer, x0, y0, x1, y1, 1.25, color);
}

fn pointInCircle(x: f32, y: f32, cx: f32, cy: f32, radius: f32) bool {
    const dx = x - cx;
    const dy = y - cy;
    return dx * dx + dy * dy <= radius * radius;
}

fn circleRect(cx: f32, cy: f32, radius: f32) editor_draw.SDL_FRect {
    return .{ .x = cx - radius, .y = cy - radius, .w = radius * 2.0, .h = radius * 2.0 };
}

fn rectCenterX(rect: editor_draw.SDL_FRect) f32 {
    return rect.x + rect.w * 0.5;
}

fn rectCenterY(rect: editor_draw.SDL_FRect) f32 {
    return rect.y + rect.h * 0.5;
}
