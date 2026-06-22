const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");

const project_editor_state = @import("project_editor_state.zig");
const project_editor_ui_world_regions = @import("project_editor_ui_world_regions.zig");
const project_editor_viewport = @import("project_editor_viewport.zig");
const world_manifest_authoring = @import("project_editor_world_authoring_manifest.zig");

const editor_math = shared.editor_math;
const shared_color = shared.color;
const OverlayQuad = shared.gpu_scene.OverlayQuad;
const ProjectEditorState = project_editor_state.ProjectEditorState;
const world = friendly_engine.world;

pub fn paintAt(state: *ProjectEditorState, point: editor_math.Vec3) !void {
    const region_id = project_editor_ui_world_regions.selectedRegionId(state) orelse return error.WorldRegionNotSelected;
    if (std.mem.eql(u8, region_id, project_editor_ui_world_regions.unassigned_region_id)) return error.WorldRegionNotSelected;
    _ = try paintForRegion(state, region_id, region_id, point, state.world_brush_size, if (state.world_region_paint_erase) .erase else .assign);
}

pub fn paintForRegion(
    state: *ProjectEditorState,
    region_id: []const u8,
    region_name: []const u8,
    point: editor_math.Vec3,
    radius_m: f32,
    mode: world.regions.PaintMode,
) !usize {
    const cells = try cellsInRegionBrush(state, point, radius_m);
    defer state.allocator.free(cells);
    if (cells.len == 0) return error.WorldCellNotInManifest;
    var regions = try world.regions.paintRegionCells(
        state.allocator,
        state.io,
        state.project_path,
        world.regions.default_regions_path,
        region_id,
        region_name,
        cells,
        mode,
    );
    defer regions.deinit();
    project_editor_ui_world_regions.selectRegion(state, region_id);
    state.terrain_preview_stale = true;
    state.invalidateWorldCache();
    var buf: [128]u8 = undefined;
    project_editor_state.setStatus(state, std.fmt.bufPrint(&buf, "{s} {d} {s}", .{ if (mode == .erase) "Removed" else "Painted", cells.len, if (cells.len == 1) "cell" else "cells" }) catch "Area paint updated");
    return cells.len;
}

fn cellsInRegionBrush(state: *ProjectEditorState, point: editor_math.Vec3, radius_m: f32) ![]world.cell.CellId {
    var loaded_manifest = try world.manifest.loadManifest(state.allocator, state.io, state.project_path, try world_manifest_authoring.pathForState(state));
    defer loaded_manifest.deinit();
    state.world_cell_size_m = loaded_manifest.cell_size_m;

    const center_cell = world_manifest_authoring.cellIdForPoint(loaded_manifest.cell_size_m, point);
    if (!loaded_manifest.hasCell(center_cell)) return error.WorldCellNotInManifest;

    var cells = std.ArrayList(world.cell.CellId).empty;
    errdefer cells.deinit(state.allocator);
    const radius = @max(radius_m, loaded_manifest.cell_size_m * 0.5);
    const min_cell = world_manifest_authoring.cellIdForPoint(loaded_manifest.cell_size_m, .{ .x = point.x - radius, .y = point.y, .z = point.z - radius });
    const max_cell = world_manifest_authoring.cellIdForPoint(loaded_manifest.cell_size_m, .{ .x = point.x + radius, .y = point.y, .z = point.z + radius });
    var cell_y = min_cell.y;
    while (cell_y <= max_cell.y) : (cell_y += 1) {
        var cell_x = min_cell.x;
        while (cell_x <= max_cell.x) : (cell_x += 1) {
            const id = world.cell.CellId{ .x = cell_x, .y = cell_y, .z = 0 };
            if (!loaded_manifest.hasCell(id)) continue;
            const center = world_manifest_authoring.cellCenter(id, loaded_manifest.cell_size_m);
            const dx = center.x - point.x;
            const dz = center.z - point.z;
            if (@sqrt(dx * dx + dz * dz) <= radius) try cells.append(state.allocator, id);
        }
    }
    if (cells.items.len == 0) try cells.append(state.allocator, center_cell);
    return cells.toOwnedSlice(state.allocator);
}

pub fn drawSelectedOverlay(state: *ProjectEditorState, vp_w: f32, vp_h: f32) void {
    if (!state.world_region_paint_enabled) return;
    const region_id = project_editor_ui_world_regions.selectedRegionId(state) orelse return;
    if (std.mem.eql(u8, region_id, project_editor_ui_world_regions.unassigned_region_id)) return;

    var regions = world.regions.loadOrEmpty(
        state.allocator,
        state.io,
        state.project_path,
        world.regions.default_regions_path,
    ) catch return;
    defer regions.deinit();

    const region_index = blk: {
        for (regions.regions, 0..) |region, index| {
            if (std.mem.eql(u8, region.id, region_id)) break :blk index;
        }
        return;
    };

    const color: shared_color.Color = if (state.world_region_paint_enabled and state.world_region_paint_erase)
        .{ .r = 240, .g = 120, .b = 82, .a = 230 }
    else
        .{ .r = 94, .g = 210, .b = 255, .a = 220 };

    const cell_size = if (state.world_cell_size_m > 0) state.world_cell_size_m else world.cell.default_cell_size_m;
    const y: f32 = 8.0;
    const max_overlay_cells = 512;
    for (regions.regions[region_index].cells, 0..) |id, index| {
        if (index >= max_overlay_cells) break;
        drawRegionCellOutline(state, id, cell_size, y, vp_w, vp_h, color);
    }
}

fn drawRegionCellOutline(
    state: *ProjectEditorState,
    id: world.cell.CellId,
    cell_size: f32,
    y: f32,
    vp_w: f32,
    vp_h: f32,
    color: shared_color.Color,
) void {
    const min_x = @as(f32, @floatFromInt(id.x)) * cell_size;
    const min_z = @as(f32, @floatFromInt(id.y)) * cell_size;
    const max_x = min_x + cell_size;
    const max_z = min_z + cell_size;
    const corners = [_]editor_math.Vec3{
        .{ .x = min_x, .y = y, .z = min_z },
        .{ .x = max_x, .y = y, .z = min_z },
        .{ .x = max_x, .y = y, .z = max_z },
        .{ .x = min_x, .y = y, .z = max_z },
    };
    drawProjectedLine(state, corners[0], corners[1], vp_w, vp_h, color);
    drawProjectedLine(state, corners[1], corners[2], vp_w, vp_h, color);
    drawProjectedLine(state, corners[2], corners[3], vp_w, vp_h, color);
    drawProjectedLine(state, corners[3], corners[0], vp_w, vp_h, color);

    const center = editor_math.Vec3{ .x = (min_x + max_x) * 0.5, .y = y, .z = (min_z + max_z) * 0.5 };
    if (project_editor_state.projectViewportPoint(state, center, vp_w, vp_h)) |screen| {
        project_editor_viewport.drawViewportSquare(state, screen.x, screen.y, 4, color);
    }
}

fn drawProjectedLine(
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

pub fn appendGpuSelectedOverlay(
    state: *ProjectEditorState,
    allocator: std.mem.Allocator,
    out: *std.ArrayList(OverlayQuad),
    vp_w: f32,
    vp_h: f32,
) !void {
    if (!state.world_region_paint_enabled) return;
    const region_id = project_editor_ui_world_regions.selectedRegionId(state) orelse return;
    if (std.mem.eql(u8, region_id, project_editor_ui_world_regions.unassigned_region_id)) return;

    var regions = world.regions.loadOrEmpty(
        state.allocator,
        state.io,
        state.project_path,
        world.regions.default_regions_path,
    ) catch return;
    defer regions.deinit();

    const region_index = blk: {
        for (regions.regions, 0..) |region, index| {
            if (std.mem.eql(u8, region.id, region_id)) break :blk index;
        }
        return;
    };

    const color: shared_color.Color = if (state.world_region_paint_enabled and state.world_region_paint_erase)
        .{ .r = 240, .g = 120, .b = 82, .a = 220 }
    else
        .{ .r = 94, .g = 210, .b = 255, .a = 210 };
    const cell_size = if (state.world_cell_size_m > 0) state.world_cell_size_m else world.cell.default_cell_size_m;
    const max_overlay_cells = 512;
    for (regions.regions[region_index].cells, 0..) |id, index| {
        if (index >= max_overlay_cells) break;
        const center = world_manifest_authoring.cellCenter(id, cell_size);
        try appendGpuProjectedSquare(state, allocator, out, .{ .x = center.x, .y = 8.0, .z = center.z }, vp_w, vp_h, color, 9.0);
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
