const std = @import("std");
const shared = @import("runtime_shared");
const editor_math = shared.editor_math;
const shared_color = shared.color;
const project_editor_state = @import("project_editor_state.zig");
const project_editor_blockout = @import("project_editor_blockout.zig");
const project_editor_viewport = @import("project_editor_viewport.zig");
const world_manifest_authoring = @import("project_editor_world_authoring_manifest.zig");
const editor_draw = @import("editor_draw.zig");
const world_atmosphere = @import("project_editor_world_atmosphere.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const OverlayQuad = shared.gpu_scene.OverlayQuad;

pub fn drawSelectedCellMarker(state: *ProjectEditorState, vp_w: f32, vp_h: f32) void {
    const id = state.selected_world_cell orelse return;
    const cell_size_m = state.world_cell_size_m;
    const min_x = @as(f32, @floatFromInt(id.x)) * cell_size_m;
    const min_z = @as(f32, @floatFromInt(id.y)) * cell_size_m;
    const max_x = min_x + cell_size_m;
    const max_z = min_z + cell_size_m;
    const y: f32 = 0.22;
    const p0 = project_editor_state.projectViewportPoint(state, .{ .x = min_x, .y = y, .z = min_z }, vp_w, vp_h) orelse return;
    const p1 = project_editor_state.projectViewportPoint(state, .{ .x = max_x, .y = y, .z = min_z }, vp_w, vp_h) orelse return;
    const p2 = project_editor_state.projectViewportPoint(state, .{ .x = max_x, .y = y, .z = max_z }, vp_w, vp_h) orelse return;
    const p3 = project_editor_state.projectViewportPoint(state, .{ .x = min_x, .y = y, .z = max_z }, vp_w, vp_h) orelse return;
    const color: shared_color.Color = .{ .r = 120, .g = 200, .b = 255, .a = 245 };
    project_editor_viewport.drawViewportLine(state, p0.x, p0.y, p1.x, p1.y, color);
    project_editor_viewport.drawViewportLine(state, p1.x, p1.y, p2.x, p2.y, color);
    project_editor_viewport.drawViewportLine(state, p2.x, p2.y, p3.x, p3.y, color);
    project_editor_viewport.drawViewportLine(state, p3.x, p3.y, p0.x, p0.y, color);
    project_editor_viewport.drawViewportSquare(state, p0.x, p0.y, 3, color);
    project_editor_viewport.drawViewportSquare(state, p1.x, p1.y, 3, color);
    project_editor_viewport.drawViewportSquare(state, p2.x, p2.y, 3, color);
    project_editor_viewport.drawViewportSquare(state, p3.x, p3.y, 3, color);
}

pub fn drawTerrainBrushRing(state: *ProjectEditorState, vp_w: f32, vp_h: f32) void {
    const center = terrainBrushHoverPoint(state) orelse return;
    const center_screen = project_editor_state.projectViewportPoint(state, center, vp_w, vp_h) orelse return;
    const color: shared_color.Color = if (state.world_tool == .paint)
        .{ .r = 120, .g = 210, .b = 160, .a = 220 }
    else
        .{ .r = 170, .g = 220, .b = 255, .a = 220 };
    drawWorldBrushRing(state, center, @max(1.0, state.world_brush_size * 0.35), vp_w, vp_h, .{ .r = color.r, .g = color.g, .b = color.b, .a = 110 });
    drawWorldBrushRing(state, center, state.world_brush_size, vp_w, vp_h, color);
    project_editor_viewport.drawViewportSquare(state, center_screen.x, center_screen.y, 3, .{ .r = 255, .g = 255, .b = 255, .a = 230 });
}

pub fn appendGpuTerrainBrushRing(
    state: *ProjectEditorState,
    allocator: std.mem.Allocator,
    out: *std.ArrayList(OverlayQuad),
    vp_w: f32,
    vp_h: f32,
) !void {
    const center = terrainBrushHoverPoint(state) orelse return;
    const color: shared_color.Color = if (state.world_tool == .paint)
        .{ .r = 120, .g = 210, .b = 160, .a = 220 }
    else
        .{ .r = 170, .g = 220, .b = 255, .a = 220 };
    try appendGpuWorldBrushRing(state, allocator, out, center, @max(1.0, state.world_brush_size * 0.35), vp_w, vp_h, .{ .r = color.r, .g = color.g, .b = color.b, .a = 110 }, 2.0);
    try appendGpuWorldBrushRing(state, allocator, out, center, state.world_brush_size, vp_w, vp_h, color, 3.0);
    try appendGpuProjectedSquare(state, allocator, out, center, vp_w, vp_h, .{ .r = 255, .g = 255, .b = 255, .a = 230 }, 7.0);
}

pub fn drawLatestDirtyCellMarker(state: *ProjectEditorState, vp_w: f32, vp_h: f32) void {
    const dirty = state.dirty_cells.last() orelse return;

    const cell_size_m = state.world_cell_size_m;
    const min_x = @as(f32, @floatFromInt(dirty.cell.x)) * cell_size_m;
    const min_z = @as(f32, @floatFromInt(dirty.cell.y)) * cell_size_m;
    const max_x = min_x + cell_size_m;
    const max_z = min_z + cell_size_m;
    const y: f32 = dirtyCellMarkerHeight(dirty.layer_name);
    const p0 = project_editor_state.projectViewportPoint(state, .{ .x = min_x, .y = y, .z = min_z }, vp_w, vp_h) orelse return;
    const p1 = project_editor_state.projectViewportPoint(state, .{ .x = max_x, .y = y, .z = min_z }, vp_w, vp_h) orelse return;
    const p2 = project_editor_state.projectViewportPoint(state, .{ .x = max_x, .y = y, .z = max_z }, vp_w, vp_h) orelse return;
    const p3 = project_editor_state.projectViewportPoint(state, .{ .x = min_x, .y = y, .z = max_z }, vp_w, vp_h) orelse return;
    const color = dirtyCellMarkerColor(dirty.layer_name);
    project_editor_viewport.drawViewportLine(state, p0.x, p0.y, p1.x, p1.y, color);
    project_editor_viewport.drawViewportLine(state, p1.x, p1.y, p2.x, p2.y, color);
    project_editor_viewport.drawViewportLine(state, p2.x, p2.y, p3.x, p3.y, color);
    project_editor_viewport.drawViewportLine(state, p3.x, p3.y, p0.x, p0.y, color);
    project_editor_viewport.drawViewportSquare(state, p0.x, p0.y, 3, color);
    project_editor_viewport.drawViewportSquare(state, p1.x, p1.y, 3, color);
    project_editor_viewport.drawViewportSquare(state, p2.x, p2.y, 3, color);
    project_editor_viewport.drawViewportSquare(state, p3.x, p3.y, 3, color);
}

fn dirtyCellMarkerHeight(layer_name: []const u8) f32 {
    if (std.mem.eql(u8, layer_name, "Terrain")) return 0.12;
    if (std.mem.eql(u8, layer_name, "Splines")) return 0.45;
    if (std.mem.eql(u8, layer_name, "Scatter")) return 1.0;
    if (std.mem.eql(u8, layer_name, "Atmosphere")) return 1.5;
    if (std.mem.eql(u8, layer_name, "Ocean")) return 0.08;
    if (std.mem.eql(u8, layer_name, "Water")) return 0.12;
    return 1.5;
}

fn dirtyCellMarkerColor(layer_name: []const u8) shared_color.Color {
    if (std.mem.eql(u8, layer_name, "Terrain")) return .{ .r = 255, .g = 215, .b = 90, .a = 235 };
    if (std.mem.eql(u8, layer_name, "Splines")) return .{ .r = 240, .g = 170, .b = 80, .a = 235 };
    if (std.mem.eql(u8, layer_name, "Scatter")) return .{ .r = 120, .g = 220, .b = 140, .a = 225 };
    if (std.mem.eql(u8, layer_name, "Atmosphere")) return .{ .r = 180, .g = 200, .b = 255, .a = 220 };
    if (std.mem.eql(u8, layer_name, "Ocean")) return .{ .r = 70, .g = 185, .b = 230, .a = 225 };
    if (std.mem.eql(u8, layer_name, "Water")) return .{ .r = 55, .g = 170, .b = 210, .a = 230 };
    return .{ .r = 180, .g = 200, .b = 255, .a = 220 };
}

pub fn drawScatterDensityBrushRing(state: *ProjectEditorState, vp_w: f32, vp_h: f32) void {
    const center = terrainBrushHoverPoint(state) orelse return;
    const center_screen = project_editor_state.projectViewportPoint(state, center, vp_w, vp_h) orelse return;
    const color: shared_color.Color = .{ .r = 90, .g = 210, .b = 120, .a = 220 };
    drawWorldBrushRing(state, center, @max(1.0, state.world_brush_size * 0.35), vp_w, vp_h, .{ .r = color.r, .g = color.g, .b = color.b, .a = 110 });
    drawWorldBrushRing(state, center, state.world_brush_size, vp_w, vp_h, color);
    project_editor_viewport.drawViewportSquare(state, center_screen.x, center_screen.y, 3, .{ .r = 255, .g = 255, .b = 255, .a = 230 });
}

pub fn appendGpuScatterDensityBrushRing(
    state: *ProjectEditorState,
    allocator: std.mem.Allocator,
    out: *std.ArrayList(OverlayQuad),
    vp_w: f32,
    vp_h: f32,
) !void {
    const center = terrainBrushHoverPoint(state) orelse return;
    const color: shared_color.Color = .{ .r = 90, .g = 210, .b = 120, .a = 220 };
    try appendGpuWorldBrushRing(state, allocator, out, center, @max(1.0, state.world_brush_size * 0.35), vp_w, vp_h, .{ .r = color.r, .g = color.g, .b = color.b, .a = 110 }, 2.0);
    try appendGpuWorldBrushRing(state, allocator, out, center, state.world_brush_size, vp_w, vp_h, color, 3.0);
    try appendGpuProjectedSquare(state, allocator, out, center, vp_w, vp_h, .{ .r = 255, .g = 255, .b = 255, .a = 230 }, 7.0);
}

fn terrainBrushHoverPoint(state: *ProjectEditorState) ?editor_math.Vec3 {
    const point = project_editor_blockout.screenToGroundPoint(state, state.mouse_x, state.mouse_y) orelse return null;
    if (!loadedTerrainCellContainsPoint(state, point)) return null;
    return point;
}

fn loadedTerrainCellContainsPoint(state: *const ProjectEditorState, point: editor_math.Vec3) bool {
    if (state.world_cell_size_m <= 0) return false;
    const id = world_manifest_authoring.cellIdForPoint(state.world_cell_size_m, point);
    for (state.terrain_preview.entries.items) |entry| {
        if (entry.snapshot.cell.eql(id)) return true;
    }
    return false;
}

pub fn drawFogPreview(state: *ProjectEditorState) void {
    const fog = world_atmosphere.fogColor(state);
    const overlay_renderer = state.viewport_overlay_renderer orelse return;
    const rect = state.viewport_overlay_rect;
    const overlay_h = @min(rect.h / 3.0, @max(24.0, state.world_fog_end_m * 0.35));
    const fog_rect = editor_draw.SDL_FRect{ .x = rect.x, .y = rect.y, .w = rect.w, .h = overlay_h };
    _ = editor_draw.SDL_SetRenderDrawColor(overlay_renderer, fog.r, fog.g, fog.b, 90);
    _ = editor_draw.SDL_RenderFillRect(overlay_renderer, &fog_rect);
}

pub fn drawLightingPreview(state: *ProjectEditorState, vp_w: f32, vp_h: f32) void {
    const target = project_editor_state.projectViewportPoint(state, state.camera.target, vp_w, vp_h) orelse return;
    if (state.world_sun_enabled) {
        drawSkyBodyPreview(state, vp_w, vp_h, target, world_atmosphere.sunSkyVector(state), .{ .r = 255, .g = 226, .b = 92, .a = 235 }, 5);
    }
    if (state.world_moon_enabled) {
        drawSkyBodyPreview(state, vp_w, vp_h, target, world_atmosphere.moonSkyVector(state), .{ .r = 174, .g = 198, .b = 255, .a = 230 }, 4);
    }
}

fn drawSkyBodyPreview(
    state: *ProjectEditorState,
    vp_w: f32,
    vp_h: f32,
    target_screen: editor_math.Vec2,
    sky_vector: editor_math.Vec3,
    color: shared_color.Color,
    half: i32,
) void {
    const pos = editor_math.Vec3.add(state.camera.target, editor_math.Vec3.scale(sky_vector, 24.0));
    const screen = project_editor_state.projectViewportPoint(state, pos, vp_w, vp_h) orelse return;
    project_editor_viewport.drawViewportLine(state, target_screen.x, target_screen.y, screen.x, screen.y, .{ .r = color.r, .g = color.g, .b = color.b, .a = 120 });
    project_editor_viewport.drawViewportSquare(state, screen.x, screen.y, half, color);
}

fn drawWorldBrushRing(
    state: *ProjectEditorState,
    center: editor_math.Vec3,
    radius: f32,
    vp_w: f32,
    vp_h: f32,
    color: shared_color.Color,
) void {
    if (radius <= 0) return;
    var prev: ?editor_math.Vec2 = null;
    var i: usize = 0;
    while (i <= 96) : (i += 1) {
        const angle = (@as(f32, @floatFromInt(i)) / 96.0) * std.math.tau;
        const world_point = editor_math.Vec3{
            .x = center.x + @cos(angle) * radius,
            .y = center.y,
            .z = center.z + @sin(angle) * radius,
        };
        const screen = project_editor_state.projectViewportPoint(state, world_point, vp_w, vp_h) orelse {
            prev = null;
            continue;
        };
        if (!std.math.isFinite(screen.x) or !std.math.isFinite(screen.y)) {
            prev = null;
            continue;
        }
        if (prev) |p| project_editor_viewport.drawViewportLine(state, p.x, p.y, screen.x, screen.y, color);
        prev = screen;
    }
}

fn appendGpuWorldBrushRing(
    state: *ProjectEditorState,
    allocator: std.mem.Allocator,
    out: *std.ArrayList(OverlayQuad),
    center: editor_math.Vec3,
    radius: f32,
    vp_w: f32,
    vp_h: f32,
    color: shared_color.Color,
    size: f32,
) !void {
    if (radius <= 0) return;
    var i: usize = 0;
    while (i < 96) : (i += 1) {
        const angle = (@as(f32, @floatFromInt(i)) / 96.0) * std.math.tau;
        const world_point = editor_math.Vec3{
            .x = center.x + @cos(angle) * radius,
            .y = center.y,
            .z = center.z + @sin(angle) * radius,
        };
        try appendGpuProjectedSquare(state, allocator, out, world_point, vp_w, vp_h, color, size);
    }
}

fn appendGpuProjectedSquare(
    state: *ProjectEditorState,
    allocator: std.mem.Allocator,
    out: *std.ArrayList(OverlayQuad),
    point: editor_math.Vec3,
    vp_w: f32,
    vp_h: f32,
    color: shared_color.Color,
    size: f32,
) !void {
    const screen = project_editor_state.projectViewportPoint(state, point, vp_w, vp_h) orelse return;
    if (!std.math.isFinite(screen.x) or !std.math.isFinite(screen.y)) return;
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
