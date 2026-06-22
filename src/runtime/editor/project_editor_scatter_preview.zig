const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const editor_math = shared.editor_math;
const shared_color = shared.color;

const project_editor_state = @import("project_editor_state.zig");
const project_editor_types = @import("project_editor_types.zig");
const project_editor_viewport = @import("project_editor_viewport.zig");
const curve_drawing = @import("project_editor_curve_drawing.zig");
const manifest = @import("project_editor_world_authoring_manifest.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const WorldCurveHit = project_editor_types.WorldCurveHit;
const modules = friendly_engine.modules;
const world = friendly_engine.world;

pub const RuleMarker = struct {
    cell: world.cell.CellId,
    prototype: []const u8,
    center: editor_math.Vec3,
};

pub const ExclusionPreview = struct {
    cell: world.cell.CellId,
    min: editor_math.Vec3,
    max: editor_math.Vec3,
};

pub const DensityMaskPreview = struct {
    cell: world.cell.CellId,
    size: u32,
    values: []u8,
    bounds: world.cell.CellBounds,
};

pub const Cache = struct {
    rules: std.ArrayList(RuleMarker) = .empty,
    exclusions: std.ArrayList(ExclusionPreview) = .empty,
    density_masks: std.ArrayList(DensityMaskPreview) = .empty,

    pub fn deinit(self: *Cache, allocator: std.mem.Allocator) void {
        for (self.rules.items) |rule| allocator.free(rule.prototype);
        self.rules.deinit(allocator);
        self.exclusions.deinit(allocator);
        for (self.density_masks.items) |mask| allocator.free(mask.values);
        self.density_masks.deinit(allocator);
    }

    pub fn clear(self: *Cache, allocator: std.mem.Allocator) void {
        for (self.rules.items) |rule| allocator.free(rule.prototype);
        self.rules.clearRetainingCapacity();
        self.exclusions.clearRetainingCapacity();
        for (self.density_masks.items) |mask| allocator.free(mask.values);
        self.density_masks.clearRetainingCapacity();
    }
};

pub fn markStale(state: *ProjectEditorState) void {
    state.scatter_preview_stale = true;
}

pub fn refreshIfStale(state: *ProjectEditorState) !void {
    if (!state.scatter_preview_stale) return;
    try refresh(state);
    state.scatter_preview_stale = false;
}

pub fn refresh(state: *ProjectEditorState) !void {
    state.scatter_preview.clear(state.allocator);

    var world_manifest = try world.manifest.loadManifest(
        state.allocator,
        state.io,
        state.project_path,
        try manifest.pathForState(state),
    );
    defer world_manifest.deinit();

    var doc = try modules.scatter.authoring.loadProject(
        state.allocator,
        state.io,
        state.project_path,
        try manifest.pathForState(state),
    );
    defer doc.deinit();

    const parsed = doc.toDoc();
    for (parsed.rules) |rule| {
        const id = try modules.scatter.parseCellId(rule.cell);
        if (!world_manifest.hasCell(id)) continue;
        const bounds = world.cell.boundsForCell(id, world_manifest.cell_size_m, world.cell.default_cell_height_m);
        const center = editor_math.Vec3{
            .x = (bounds.min.x + bounds.max.x) * 0.5,
            .y = 0.5,
            .z = (bounds.min.z + bounds.max.z) * 0.5,
        };
        try state.scatter_preview.rules.append(state.allocator, .{
            .cell = id,
            .prototype = try state.allocator.dupe(u8, rule.prototype),
            .center = center,
        });
    }
    for (parsed.exclusions) |zone| {
        const id = try modules.scatter.parseCellId(zone.cell);
        if (!world_manifest.hasCell(id)) continue;
        try state.scatter_preview.exclusions.append(state.allocator, .{
            .cell = id,
            .min = .{ .x = zone.min[0], .y = zone.min[1], .z = zone.min[2] },
            .max = .{ .x = zone.max[0], .y = zone.max[1], .z = zone.max[2] },
        });
    }
    for (parsed.density_masks) |mask| {
        const id = try modules.scatter.parseCellId(mask.cell);
        if (!world_manifest.hasCell(id)) continue;
        const bounds = world.cell.boundsForCell(id, world_manifest.cell_size_m, world.cell.default_cell_height_m);
        try state.scatter_preview.density_masks.append(state.allocator, .{
            .cell = id,
            .size = mask.size,
            .values = try state.allocator.dupe(u8, mask.values),
            .bounds = bounds,
        });
    }
}

pub fn drawOverlay(state: *ProjectEditorState, vp_w: f32, vp_h: f32) void {
    refreshIfStale(state) catch return;

    const style = curve_drawing.styleForTone(.scatter);
    const zone_color: shared_color.Color = .{ .r = 220, .g = 90, .b = 90, .a = 175 };

    for (state.scatter_preview.exclusions.items, 0..) |zone, zone_index| {
        const selected_hit = if (state.selected_world_curve_hit.target == .scatter_zone and state.selected_world_curve_hit.index == zone_index) state.selected_world_curve_hit else null;
        const hovered_hit = if (state.hovered_world_curve_hit.target == .scatter_zone and state.hovered_world_curve_hit.index == zone_index) state.hovered_world_curve_hit else null;
        const body_selected = selected_hit != null and selected_hit.?.element == .width_rail;
        const body_hovered = hovered_hit != null and hovered_hit.?.element == .width_rail;
        const color = if (body_selected) style.selected_color else if (body_hovered or hovered_hit != null) style.hover_color else zone_color;
        project_editor_viewport.drawAabbWireframe(state, zone.min, zone.max, vp_w, vp_h, color);
        drawZoneFootprint(state, zone.min, zone.max, vp_w, vp_h, style, selected_hit, hovered_hit);
    }
    for (state.scatter_preview.rules.items) |rule| {
        curve_drawing.drawProjectedHandle(state, rule.center, vp_w, vp_h, style, .normal);
    }
    drawDensityMaskOverlay(state, vp_w, vp_h);
}

fn drawDensityMaskOverlay(state: *ProjectEditorState, vp_w: f32, vp_h: f32) void {
    for (state.scatter_preview.density_masks.items) |mask| {
        const size: usize = @intCast(mask.size);
        const cell_size_m = mask.bounds.max.x - mask.bounds.min.x;
        const sample_w = cell_size_m / @as(f32, @floatFromInt(size));
        const sample_d = (mask.bounds.max.z - mask.bounds.min.z) / @as(f32, @floatFromInt(size));
        var z: usize = 0;
        while (z < size) : (z += 2) {
            var x: usize = 0;
            while (x < size) : (x += 2) {
                const value = mask.values[z * size + x];
                if (value < 8) continue;
                const min_pt = editor_math.Vec3{
                    .x = mask.bounds.min.x + @as(f32, @floatFromInt(x)) * sample_w,
                    .y = 0.08,
                    .z = mask.bounds.min.z + @as(f32, @floatFromInt(z)) * sample_d,
                };
                const max_pt = editor_math.Vec3{
                    .x = min_pt.x + sample_w * 2,
                    .y = 0.12 + (@as(f32, @floatFromInt(value)) / 255.0) * 0.35,
                    .z = min_pt.z + sample_d * 2,
                };
                const alpha: u8 = @intCast(@min(@as(u16, 220), 80 + @as(u16, value) * 140 / 255));
                const color: shared_color.Color = .{
                    .r = @intCast(@min(@as(u16, 255), 40 + @as(u16, value) * 180 / 255)),
                    .g = @intCast(@min(@as(u16, 255), 120 + @as(u16, value) * 100 / 255)),
                    .b = 70,
                    .a = alpha,
                };
                project_editor_viewport.drawAabbWireframe(state, min_pt, max_pt, vp_w, vp_h, color);
            }
        }
    }
}

pub fn drawDragPreview(state: *ProjectEditorState, vp_w: f32, vp_h: f32) void {
    const start = state.world_scatter_drag_start orelse return;
    const end = state.world_scatter_drag_end orelse return;
    const min_pt = editor_math.Vec3{
        .x = @min(start.x, end.x),
        .y = 0,
        .z = @min(start.z, end.z),
    };
    const max_pt = editor_math.Vec3{
        .x = @max(start.x, end.x),
        .y = 4,
        .z = @max(start.z, end.z),
    };
    const style = curve_drawing.styleForTone(.scatter);
    project_editor_viewport.drawAabbWireframe(state, min_pt, max_pt, vp_w, vp_h, style.preview_color);
    drawZoneFootprint(state, min_pt, max_pt, vp_w, vp_h, style, null, null);
}

fn drawZoneFootprint(
    state: *ProjectEditorState,
    min_pt: editor_math.Vec3,
    max_pt: editor_math.Vec3,
    vp_w: f32,
    vp_h: f32,
    style: curve_drawing.AffordanceStyle,
    selected_hit: ?WorldCurveHit,
    hovered_hit: ?WorldCurveHit,
) void {
    const y = @max(min_pt.y, 0.05);
    const corners = [_]editor_math.Vec3{
        .{ .x = min_pt.x, .y = y, .z = min_pt.z },
        .{ .x = max_pt.x, .y = y, .z = min_pt.z },
        .{ .x = max_pt.x, .y = y, .z = max_pt.z },
        .{ .x = min_pt.x, .y = y, .z = max_pt.z },
    };
    for (corners, 0..) |corner, index| {
        const next = corners[(index + 1) % corners.len];
        const edge_selected = selected_hit != null and selected_hit.?.element == .segment and selected_hit.?.sub_index == index;
        const edge_hovered = hovered_hit != null and hovered_hit.?.element == .segment and hovered_hit.?.sub_index == index;
        const body_selected = selected_hit != null and selected_hit.?.element == .width_rail;
        const body_hovered = hovered_hit != null and hovered_hit.?.element == .width_rail;
        const line_color = if (edge_selected or body_selected) style.selected_color else if (edge_hovered or body_hovered) style.hover_color else style.line_color;
        curve_drawing.drawProjectedSegment(state, corner, next, vp_w, vp_h, line_color);

        const corner_selected = selected_hit != null and selected_hit.?.element == .point and selected_hit.?.sub_index == index;
        const corner_hovered = hovered_hit != null and hovered_hit.?.element == .point and hovered_hit.?.sub_index == index;
        const handle_state: curve_drawing.HandleState = if (corner_selected or body_selected) .selected else if (corner_hovered or body_hovered) .hover else .normal;
        curve_drawing.drawProjectedHandle(state, corner, vp_w, vp_h, style, handle_state);
    }
}
