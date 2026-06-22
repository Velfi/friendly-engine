const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_types = @import("project_editor_types.zig");
const project_editor_edit = @import("project_editor_edit_undo.zig");
const world_manifest_authoring = @import("project_editor_world_authoring_manifest.zig");
const project_editor_blockout = @import("project_editor_blockout.zig");
const curve_drawing = @import("project_editor_curve_drawing.zig");
const world_curve_gizmos = @import("project_editor_world_curve_gizmos.zig");
const ui_widgets = @import("project_editor_ui_widgets.zig");
const project_editor_ui_world_configurator = @import("project_editor_ui_world_configurator.zig");

const core_ui = friendly_engine.modules.core_ui;
const editor_math = shared.editor_math;
const shared_color = shared.color;
const ProjectEditorState = project_editor_state.ProjectEditorState;

pub const WorldCurveInteractionBegin = enum {
    none,
    handled,
    drag,
};

pub fn actionHint(state: *const ProjectEditorState) []const u8 {
    if (state.selected_world_curve_hit.target == .water_volume) {
        return switch (state.selected_world_curve_hit.element) {
            .point => "Drag this water point to reshape it.",
            .segment => "Drag this side, double-click to add a point, or Delete to remove it.",
            .handle_start => "Drag the surface handle to raise or lower water.",
            .handle_end => "Drag the bottom handle to change depth.",
            else => "Edit the selected water shape.",
        };
    }
    if (state.hovered_world_curve_hit.target == .water_volume and state.hovered_world_curve_hit.element == .segment) return "Click the water side to select it; double-click to add a point.";
    return "Click a water shape, or create one at the camera target.";
}

pub fn actionError(state: *ProjectEditorState, err: anyerror) void {
    const message: []const u8 = switch (err) {
        error.InvalidWaterVolume => "Water shape needs at least 3 points",
        error.NoWaterVolumeSelected => "Select a water shape first",
        else => "Water edit failed",
    };
    project_editor_state.setStatus(state, message);
}

pub fn selectionLabel(state: *const ProjectEditorState) []const u8 {
    if (state.selected_world_curve_hit.target != .water_volume) return "No water selected";
    return switch (state.selected_world_curve_hit.element) {
        .point => "Selected water point",
        .segment => "Selected water side",
        .handle_start => "Selected water surface",
        .handle_end => "Selected water bottom",
        else => "Selected water shape",
    };
}

pub fn buildControls(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    try ui.label("Local Water");
    try ui_widgets.compactInfo(ui, selectionLabel(state));
    var info_buf: [160]u8 = undefined;
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(
        &info_buf,
        "{s}  surface {d:.1}m  bottom {d:.1}m  current {d:.1},{d:.1},{d:.1}",
        .{
            if (state.water_swimmable) "Swimmable" else "Visual",
            state.water_surface_y,
            state.water_bottom_y,
            state.water_current_x,
            state.water_current_y,
            state.water_current_z,
        },
    ) catch "Water");
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.syncedCheckbox(ui, "Swim", "ed-world-water-swimmable", state.water_swimmable)).clicked) {
        state.water_swimmable = !state.water_swimmable;
        applySelectedSettings(state) catch |err| actionError(state, err);
    }
    if ((try ui_widgets.syncedCheckbox(ui, "Match Ocean", "ed-world-water-ocean-link", state.water_linked_to_ocean)).clicked) {
        state.water_linked_to_ocean = !state.water_linked_to_ocean;
        applySelectedSettings(state) catch |err| actionError(state, err);
    }
    if ((try ui_widgets.button(ui, "ed-world-water-surface-minus", "Surface -", 84, false)).clicked) adjustSurface(state, -0.5);
    if ((try ui_widgets.button(ui, "ed-world-water-surface-plus", "Surface +", 84, false)).clicked) adjustSurface(state, 0.5);
    if ((try ui_widgets.button(ui, "ed-world-water-bottom-minus", "Bottom -", 82, false)).clicked) adjustBottom(state, -0.5);
    if ((try ui_widgets.button(ui, "ed-world-water-bottom-plus", "Bottom +", 82, false)).clicked) adjustBottom(state, 0.5);
    if ((try ui_widgets.button(ui, "ed-world-water-create", "Create Water", 118, false)).clicked) {
        try ui_widgets.writeLayer(state, project_editor_ui_world_configurator.createWaterVolumeAtTarget, "Water shape created", "Water shape failed");
    }
    try core_ui.layout.endSameLine(ui);
}

pub fn beginInteraction(state: *ProjectEditorState, screen_x: f32, screen_y: f32, click_count: u8) WorldCurveInteractionBegin {
    const hit = hitAtScreen(state, screen_x, screen_y) orelse return .none;
    state.selected_world_curve_hit = hit;
    syncStateFromSelectedVolume(state) catch {};
    if (hit.element == .segment and click_count >= 2) {
        pushUndoSnapshot(state);
        insertPointAtScreen(state, hit, screen_x, screen_y) catch |err| actionError(state, err);
        return .handled;
    }
    beginUndoBatch(state);
    state.world_curve_drag_state = .{
        .hit = hit,
        .start_x = screen_x,
        .start_y = screen_y,
        .start_value = heightForHit(state, hit) orelse 0,
    };
    state.world_curve_drag_anchor = project_editor_blockout.screenToGroundPoint(state, screen_x, screen_y);
    project_editor_state.setStatus(state, dragHint(state) orelse actionHint(state));
    return .drag;
}

pub fn hitAtScreen(state: *ProjectEditorState, screen_x: f32, screen_y: f32) ?project_editor_types.WorldCurveHit {
    const water_mod = friendly_engine.modules.water;
    const manifest_path = world_manifest_authoring.pathForState(state) catch return null;
    var doc = water_mod.authoring.loadProject(state.allocator, state.io, state.project_path, manifest_path) catch return null;
    defer doc.deinit(state.allocator);
    const local_x = screen_x - state.viewport_screen_rect.x;
    const local_y = screen_y - state.viewport_screen_rect.y;
    const vp_w = state.viewport_screen_rect.w;
    const vp_h = state.viewport_screen_rect.h;

    var best: ?project_editor_types.WorldCurveHit = null;
    for (doc.volumes, 0..) |volume, volume_index| {
        if (volume.points.len < 2) continue;
        const y = volume.surface_y + 0.08;
        if (nearestFootprintPointAtScreen(state, volume.points, y, local_x, local_y, vp_w, vp_h, 12)) |point_index| {
            best = world_curve_gizmos.nearerEditorHit(best, .{
                .target = .water_volume,
                .element = .point,
                .index = volume_index,
                .sub_index = point_index,
                .distance_sq = pointDistanceSq(state, volume.points[point_index], y, local_x, local_y, vp_w, vp_h),
            });
        }
        if (nearestFootprintEdgeAtScreen(state, volume.points, y, local_x, local_y, vp_w, vp_h, 8)) |edge_hit| {
            best = world_curve_gizmos.nearerEditorHit(best, .{
                .target = .water_volume,
                .element = .segment,
                .index = volume_index,
                .sub_index = edge_hit.index,
                .distance_sq = edge_hit.distance_sq,
            });
        }
        if (nearestHeightHandleAtScreen(state, volume, local_x, local_y, vp_w, vp_h, 11)) |height_hit| {
            best = world_curve_gizmos.nearerEditorHit(best, .{
                .target = .water_volume,
                .element = height_hit.element,
                .index = volume_index,
                .distance_sq = height_hit.distance_sq,
            });
        }
    }
    return best;
}

pub fn moveSelectedPart(state: *ProjectEditorState, screen_x: f32, screen_y: f32) !void {
    const hit = state.selected_world_curve_hit;
    if (hit.target != .water_volume) return error.NoWaterVolumeSelected;
    const water_mod = friendly_engine.modules.water;
    const manifest_path = try world_manifest_authoring.pathForState(state);
    var doc = try water_mod.authoring.loadProject(state.allocator, state.io, state.project_path, manifest_path);
    defer doc.deinit(state.allocator);
    if (hit.index >= doc.volumes.len) return error.NoWaterVolumeSelected;
    var volume = &doc.volumes[hit.index];
    var old_volume = try water_mod.WaterVolume.duplicate(state.allocator, volume.*);
    defer old_volume.deinit(state.allocator);

    switch (hit.element) {
        .point => {
            if (hit.sub_index >= volume.points.len) return error.InvalidWaterVolume;
            const point = project_editor_blockout.screenToGroundPoint(state, screen_x, screen_y) orelse return;
            volume.points[hit.sub_index] = .{ point.x, point.z };
        },
        .segment => {
            if (hit.sub_index >= volume.points.len) return error.InvalidWaterVolume;
            const point = project_editor_blockout.screenToGroundPoint(state, screen_x, screen_y) orelse return;
            const anchor = state.world_curve_drag_anchor orelse point;
            const dx = point.x - anchor.x;
            const dz = point.z - anchor.z;
            const next_index = (hit.sub_index + 1) % volume.points.len;
            volume.points[hit.sub_index][0] += dx;
            volume.points[hit.sub_index][1] += dz;
            volume.points[next_index][0] += dx;
            volume.points[next_index][1] += dz;
            state.world_curve_drag_anchor = point;
        },
        .handle_start => {
            const delta = (state.world_curve_drag_state.start_y - screen_y) * 0.05;
            volume.surface_y = @max(volume.bottom_y + 0.25, state.world_curve_drag_state.start_value + delta);
            state.water_surface_y = volume.surface_y;
        },
        .handle_end => {
            const delta = (state.world_curve_drag_state.start_y - screen_y) * 0.05;
            volume.bottom_y = @min(volume.surface_y - 0.25, state.world_curve_drag_state.start_value + delta);
            state.water_bottom_y = volume.bottom_y;
        },
        else => return,
    }

    pushUndoSnapshot(state);
    try water_mod.validateVolume(volume.*);
    try water_mod.authoring.saveProject(state.allocator, state.io, state.project_path, manifest_path, doc);
    try markVolumeDirty(state, old_volume);
    try markVolumeDirty(state, volume.*);
    project_editor_state.setStatus(state, selectionLabel(state));
}

pub fn deleteSelectedPart(state: *ProjectEditorState) !void {
    const hit = state.selected_world_curve_hit;
    if (hit.target != .water_volume) return error.NoWaterVolumeSelected;
    pushUndoSnapshot(state);
    const water_mod = friendly_engine.modules.water;
    const manifest_path = try world_manifest_authoring.pathForState(state);
    var doc = try water_mod.authoring.loadProject(state.allocator, state.io, state.project_path, manifest_path);
    defer doc.deinit(state.allocator);
    if (hit.index >= doc.volumes.len) return error.NoWaterVolumeSelected;
    var old_volume = try water_mod.WaterVolume.duplicate(state.allocator, doc.volumes[hit.index]);
    defer old_volume.deinit(state.allocator);

    if (hit.element == .point or hit.element == .segment) {
        const volume = &doc.volumes[hit.index];
        const remove_index = deletePointIndexForHit(hit, volume.points.len) orelse return error.InvalidWaterVolume;
        try removePointAt(state.allocator, volume, remove_index);
        try water_mod.validateVolume(volume.*);
        try water_mod.authoring.saveProject(state.allocator, state.io, state.project_path, manifest_path, doc);
        try markVolumeDirty(state, old_volume);
        try markVolumeDirty(state, volume.*);
        state.selected_world_curve_hit = .{ .target = .water_volume, .element = .point, .index = hit.index, .sub_index = @min(remove_index, volume.points.len - 1) };
        project_editor_state.setStatus(state, if (hit.element == .segment) "Water side deleted" else "Water point deleted");
        return;
    }

    var volumes = std.ArrayList(water_mod.WaterVolume).empty;
    defer {
        for (volumes.items) |*volume| volume.deinit(state.allocator);
        volumes.deinit(state.allocator);
    }
    for (doc.volumes, 0..) |volume, index| {
        if (index == hit.index) continue;
        try volumes.append(state.allocator, try water_mod.WaterVolume.duplicate(state.allocator, volume));
    }
    const owned = try volumes.toOwnedSlice(state.allocator);
    volumes = .empty;
    var out_doc = water_mod.WaterDoc{ .volumes = owned };
    defer out_doc.deinit(state.allocator);
    try water_mod.authoring.saveProject(state.allocator, state.io, state.project_path, manifest_path, out_doc);
    try markVolumeDirty(state, old_volume);
    state.selected_world_curve_hit = .{};
    state.hovered_world_curve_hit = .{};
    project_editor_state.setStatus(state, "Water shape deleted");
}

pub fn drawOverlay(state: *ProjectEditorState, vp_w: f32, vp_h: f32) void {
    const water_mod = friendly_engine.modules.water;
    const manifest_path = world_manifest_authoring.pathForState(state) catch return;
    var doc = water_mod.authoring.loadProject(state.allocator, state.io, state.project_path, manifest_path) catch return;
    defer doc.deinit(state.allocator);

    const style = curve_drawing.styleForTone(.water);
    const mouse_x = state.mouse_x - state.viewport_screen_rect.x;
    const mouse_y = state.mouse_y - state.viewport_screen_rect.y;
    for (doc.volumes, 0..) |volume, volume_index| {
        if (volume.points.len < 2) continue;
        const y = volume.surface_y + 0.08;
        const hover_point = nearestFootprintPointAtScreen(state, volume.points, y, mouse_x, mouse_y, vp_w, vp_h, 10);
        const hover_edge = if (hover_point == null)
            nearestFootprintEdgeAtScreen(state, volume.points, y, mouse_x, mouse_y, vp_w, vp_h, 8)
        else
            null;
        const selected_volume = state.selected_world_curve_hit.target == .water_volume and state.selected_world_curve_hit.index == volume_index;
        for (volume.points, 0..) |point, point_index| {
            const next = volume.points[(point_index + 1) % volume.points.len];
            const world_point = editor_math.Vec3{ .x = point[0], .y = y, .z = point[1] };
            const world_next = editor_math.Vec3{ .x = next[0], .y = y, .z = next[1] };
            const selected_edge = selected_volume and state.selected_world_curve_hit.element == .segment and state.selected_world_curve_hit.sub_index == point_index;
            const hovered_edge = hover_edge != null and hover_edge.?.index == point_index;
            const line_color = if (selected_edge or selected_volume) style.selected_color else if (hovered_edge) style.hover_color else style.line_color;
            curve_drawing.drawProjectedSegment(state, world_point, world_next, vp_w, vp_h, line_color);
            const midpoint = editor_math.Vec3{
                .x = (point[0] + next[0]) * 0.5,
                .y = y,
                .z = (point[1] + next[1]) * 0.5,
            };
            const insert_state: curve_drawing.HandleState = if (selected_edge) .selected else if (hovered_edge) .hover else .preview;
            curve_drawing.drawProjectedHandle(state, midpoint, vp_w, vp_h, style, insert_state);
            const selected_point = selected_volume and state.selected_world_curve_hit.element == .point and state.selected_world_curve_hit.sub_index == point_index;
            const handle_state: curve_drawing.HandleState = if (selected_point) .selected else if (hover_point != null and hover_point.? == point_index) .hover else .normal;
            curve_drawing.drawProjectedHandle(state, world_point, vp_w, vp_h, style, handle_state);
        }
        drawHeightHandles(state, volume, volume_index, vp_w, vp_h, style);
    }

    drawCreatePreview(state, vp_w, vp_h, style);
}

fn dragHint(state: *const ProjectEditorState) ?[]const u8 {
    const hit = state.world_curve_drag_state.hit;
    if (hit.target != .water_volume) return null;
    return switch (hit.element) {
        .point => "Reshaping water.",
        .segment => "Moving water side.",
        .handle_start => "Adjusting water surface height.",
        .handle_end => "Adjusting water depth.",
        else => null,
    };
}

fn adjustSurface(state: *ProjectEditorState, delta: f32) void {
    state.water_surface_y += delta;
    if (state.water_bottom_y >= state.water_surface_y) state.water_bottom_y = state.water_surface_y - 0.25;
    applySelectedSettings(state) catch |err| actionError(state, err);
}

fn adjustBottom(state: *ProjectEditorState, delta: f32) void {
    state.water_bottom_y = @min(state.water_surface_y - 0.25, state.water_bottom_y + delta);
    applySelectedSettings(state) catch |err| actionError(state, err);
}

fn insertPointAtScreen(
    state: *ProjectEditorState,
    hit: project_editor_types.WorldCurveHit,
    screen_x: f32,
    screen_y: f32,
) !void {
    if (hit.target != .water_volume or hit.element != .segment) return error.NoWaterVolumeSelected;
    const point = project_editor_blockout.screenToGroundPoint(state, screen_x, screen_y) orelse return error.InvalidWaterVolume;
    const water_mod = friendly_engine.modules.water;
    const manifest_path = try world_manifest_authoring.pathForState(state);
    var doc = try water_mod.authoring.loadProject(state.allocator, state.io, state.project_path, manifest_path);
    defer doc.deinit(state.allocator);
    if (hit.index >= doc.volumes.len) return error.NoWaterVolumeSelected;
    var volume = &doc.volumes[hit.index];
    if (hit.sub_index >= volume.points.len) return error.InvalidWaterVolume;
    var old_volume = try water_mod.WaterVolume.duplicate(state.allocator, volume.*);
    defer old_volume.deinit(state.allocator);

    const insert_index = try volume.insertPointAfter(state.allocator, hit.sub_index, .{ point.x, point.z });
    try water_mod.authoring.saveProject(state.allocator, state.io, state.project_path, manifest_path, doc);
    try markVolumeDirty(state, old_volume);
    try markVolumeDirty(state, volume.*);
    state.selected_world_curve_hit = .{ .target = .water_volume, .element = .point, .index = hit.index, .sub_index = insert_index };
    syncStateFromSelectedVolume(state) catch {};
    project_editor_state.setStatus(state, "Water point inserted");
}

fn selectedVolumeIndex(state: *const ProjectEditorState) ?usize {
    const hit = state.selected_world_curve_hit;
    return if (hit.target == .water_volume) hit.index else null;
}

fn syncStateFromSelectedVolume(state: *ProjectEditorState) !void {
    const volume_index = selectedVolumeIndex(state) orelse return;
    const water_mod = friendly_engine.modules.water;
    const manifest_path = try world_manifest_authoring.pathForState(state);
    var doc = try water_mod.authoring.loadProject(state.allocator, state.io, state.project_path, manifest_path);
    defer doc.deinit(state.allocator);
    if (volume_index >= doc.volumes.len) return error.NoWaterVolumeSelected;
    syncStateFromVolume(state, doc.volumes[volume_index]);
}

fn syncStateFromVolume(state: *ProjectEditorState, volume: friendly_engine.modules.water.WaterVolume) void {
    state.water_surface_y = volume.surface_y;
    state.water_bottom_y = volume.bottom_y;
    state.water_swimmable = volume.swimmable;
    state.water_linked_to_ocean = volume.linked_to_ocean;
    state.water_current_x = volume.current.x;
    state.water_current_y = volume.current.y;
    state.water_current_z = volume.current.z;
}

fn applySelectedSettings(state: *ProjectEditorState) !void {
    const volume_index = selectedVolumeIndex(state) orelse return;
    const water_mod = friendly_engine.modules.water;
    const manifest_path = try world_manifest_authoring.pathForState(state);
    var doc = try water_mod.authoring.loadProject(state.allocator, state.io, state.project_path, manifest_path);
    defer doc.deinit(state.allocator);
    if (volume_index >= doc.volumes.len) return error.NoWaterVolumeSelected;
    const volume = &doc.volumes[volume_index];
    var old_volume = try water_mod.WaterVolume.duplicate(state.allocator, volume.*);
    defer old_volume.deinit(state.allocator);
    pushUndoSnapshot(state);
    try applyStateToVolume(state.allocator, state, volume);
    try water_mod.validateVolume(volume.*);
    try water_mod.authoring.saveProject(state.allocator, state.io, state.project_path, manifest_path, doc);
    try markVolumeDirty(state, old_volume);
    try markVolumeDirty(state, volume.*);
    project_editor_state.setStatus(state, "Water shape updated");
}

pub fn applyStateToVolume(allocator: std.mem.Allocator, state: *ProjectEditorState, volume: *friendly_engine.modules.water.WaterVolume) !void {
    volume.surface_y = state.water_surface_y;
    volume.bottom_y = @min(state.water_surface_y - 0.25, state.water_bottom_y);
    state.water_bottom_y = volume.bottom_y;
    volume.swimmable = state.water_swimmable;
    volume.linked_to_ocean = state.water_linked_to_ocean;
    volume.kind = if (state.water_linked_to_ocean) .ocean_near else .lake;
    const material = if (state.water_linked_to_ocean) "water.ocean.near" else "water.lake.clear";
    if (!std.mem.eql(u8, volume.material, material)) {
        const next_material = try allocator.dupe(u8, material);
        allocator.free(volume.material);
        volume.material = next_material;
    }
    volume.current = .{ .x = state.water_current_x, .y = state.water_current_y, .z = state.water_current_z };
}

fn heightForHit(state: *ProjectEditorState, hit: project_editor_types.WorldCurveHit) ?f32 {
    if (hit.target != .water_volume) return null;
    const water_mod = friendly_engine.modules.water;
    const manifest_path = world_manifest_authoring.pathForState(state) catch return null;
    var doc = water_mod.authoring.loadProject(state.allocator, state.io, state.project_path, manifest_path) catch return null;
    defer doc.deinit(state.allocator);
    if (hit.index >= doc.volumes.len) return null;
    const volume = doc.volumes[hit.index];
    return switch (hit.element) {
        .handle_start => volume.surface_y,
        .handle_end => volume.bottom_y,
        else => null,
    };
}

pub fn deletePointIndexForHit(hit: project_editor_types.WorldCurveHit, point_count: usize) ?usize {
    if (point_count <= 3) return null;
    if (hit.sub_index >= point_count) return null;
    return switch (hit.element) {
        .point => hit.sub_index,
        .segment => (hit.sub_index + 1) % point_count,
        else => null,
    };
}

pub fn removePointAt(allocator: std.mem.Allocator, volume: *friendly_engine.modules.water.WaterVolume, remove_index: usize) !void {
    if (volume.points.len <= 3 or remove_index >= volume.points.len) return error.InvalidWaterVolume;
    const new_points = try allocator.alloc([2]f32, volume.points.len - 1);
    errdefer allocator.free(new_points);
    var out: usize = 0;
    for (volume.points, 0..) |point, index| {
        if (index == remove_index) continue;
        new_points[out] = point;
        out += 1;
    }
    allocator.free(volume.points);
    volume.points = new_points;
}

fn markVolumeDirty(state: *ProjectEditorState, volume: friendly_engine.modules.water.WaterVolume) !void {
    const center = volumeCenter(volume);
    const cell = world_manifest_authoring.cellIdForPoint(state.world_cell_size_m, .{ .x = center[0], .y = 0, .z = center[1] });
    try project_editor_state.markDirtyCell(state, "Water", cell, "volumes");
}

fn drawHeightHandles(
    state: *ProjectEditorState,
    volume: friendly_engine.modules.water.WaterVolume,
    volume_index: usize,
    vp_w: f32,
    vp_h: f32,
    style: curve_drawing.AffordanceStyle,
) void {
    const center = volumeCenter(volume);
    const surface = editor_math.Vec3{ .x = center[0], .y = volume.surface_y, .z = center[1] };
    const bottom = editor_math.Vec3{ .x = center[0], .y = volume.bottom_y, .z = center[1] };
    const surface_state = heightHandleState(state, volume_index, .handle_start);
    const bottom_state = heightHandleState(state, volume_index, .handle_end);
    const line_color = if (surface_state == .selected or bottom_state == .selected)
        style.selected_color
    else if (surface_state == .hover or bottom_state == .hover)
        style.hover_color
    else
        shared_color.Color{ .r = 95, .g = 215, .b = 255, .a = 150 };
    curve_drawing.drawProjectedSegment(state, surface, bottom, vp_w, vp_h, line_color);
    curve_drawing.drawProjectedHandle(state, surface, vp_w, vp_h, style, surface_state);
    curve_drawing.drawProjectedHandle(state, bottom, vp_w, vp_h, style, bottom_state);
}

pub fn heightHandleState(
    state: *const ProjectEditorState,
    volume_index: usize,
    element: project_editor_types.WorldCurveHitElement,
) curve_drawing.HandleState {
    if (curveHitMatches(state.selected_world_curve_hit, .water_volume, volume_index, element)) return .selected;
    if (curveHitMatches(state.hovered_world_curve_hit, .water_volume, volume_index, element)) return .hover;
    return .preview;
}

fn curveHitMatches(
    hit: project_editor_types.WorldCurveHit,
    target: project_editor_types.WorldCurveHitTarget,
    index: usize,
    element: project_editor_types.WorldCurveHitElement,
) bool {
    return hit.target == target and hit.index == index and hit.element == element;
}

fn nearestFootprintPointAtScreen(
    state: *ProjectEditorState,
    points: []const [2]f32,
    y: f32,
    screen_x: f32,
    screen_y: f32,
    vp_w: f32,
    vp_h: f32,
    radius_px: f32,
) ?usize {
    const radius_sq = radius_px * radius_px;
    var best_index: ?usize = null;
    var best_distance = radius_sq;
    for (points, 0..) |point, index| {
        const p = project_editor_state.projectViewportPoint(state, .{ .x = point[0], .y = y, .z = point[1] }, vp_w, vp_h) orelse continue;
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

const IndexedDistance = struct {
    index: usize,
    distance_sq: f32,
};

const HeightHandleHit = struct {
    element: project_editor_types.WorldCurveHitElement,
    distance_sq: f32,
};

fn pointDistanceSq(
    state: *ProjectEditorState,
    point: [2]f32,
    y: f32,
    screen_x: f32,
    screen_y: f32,
    vp_w: f32,
    vp_h: f32,
) f32 {
    const p = project_editor_state.projectViewportPoint(state, .{ .x = point[0], .y = y, .z = point[1] }, vp_w, vp_h) orelse return std.math.inf(f32);
    return distanceSq(screen_x, screen_y, p.x, p.y);
}

fn nearestFootprintEdgeAtScreen(
    state: *ProjectEditorState,
    points: []const [2]f32,
    y: f32,
    screen_x: f32,
    screen_y: f32,
    vp_w: f32,
    vp_h: f32,
    radius_px: f32,
) ?IndexedDistance {
    if (points.len < 2) return null;
    const radius_sq = radius_px * radius_px;
    var best: ?IndexedDistance = null;
    var best_distance = radius_sq;
    for (points, 0..) |point, index| {
        const next = points[(index + 1) % points.len];
        const p0 = project_editor_state.projectViewportPoint(state, .{ .x = point[0], .y = y, .z = point[1] }, vp_w, vp_h) orelse continue;
        const p1 = project_editor_state.projectViewportPoint(state, .{ .x = next[0], .y = y, .z = next[1] }, vp_w, vp_h) orelse continue;
        const dist = distancePointSegmentSq(screen_x, screen_y, p0.x, p0.y, p1.x, p1.y);
        if (dist <= best_distance) {
            best_distance = dist;
            best = .{ .index = index, .distance_sq = dist };
        }
    }
    return best;
}

fn nearestHeightHandleAtScreen(
    state: *ProjectEditorState,
    volume: friendly_engine.modules.water.WaterVolume,
    screen_x: f32,
    screen_y: f32,
    vp_w: f32,
    vp_h: f32,
    radius_px: f32,
) ?HeightHandleHit {
    const center = volumeCenter(volume);
    const surface = project_editor_state.projectViewportPoint(state, .{ .x = center[0], .y = volume.surface_y, .z = center[1] }, vp_w, vp_h) orelse return null;
    const bottom = project_editor_state.projectViewportPoint(state, .{ .x = center[0], .y = volume.bottom_y, .z = center[1] }, vp_w, vp_h) orelse return null;
    const radius_sq = radius_px * radius_px;
    const surface_dist = distanceSq(screen_x, screen_y, surface.x, surface.y);
    const bottom_dist = distanceSq(screen_x, screen_y, bottom.x, bottom.y);
    if (surface_dist <= radius_sq and surface_dist <= bottom_dist) return .{ .element = .handle_start, .distance_sq = surface_dist };
    if (bottom_dist <= radius_sq) return .{ .element = .handle_end, .distance_sq = bottom_dist };
    return null;
}

fn volumeCenter(volume: friendly_engine.modules.water.WaterVolume) [2]f32 {
    if (volume.points.len == 0) return .{ 0, 0 };
    var x: f32 = 0;
    var z: f32 = 0;
    for (volume.points) |point| {
        x += point[0];
        z += point[1];
    }
    const count: f32 = @floatFromInt(volume.points.len);
    return .{ x / count, z / count };
}

fn drawCreatePreview(
    state: *ProjectEditorState,
    vp_w: f32,
    vp_h: f32,
    style: curve_drawing.AffordanceStyle,
) void {
    const center = project_editor_blockout.screenToGroundPoint(state, state.mouse_x, state.mouse_y) orelse state.camera.target;
    const half: f32 = @max(2.0, state.world_brush_size);
    const y = state.water_surface_y + 0.08;
    drawRectangleFootprint(
        state,
        .{ .x = center.x - half, .y = y, .z = center.z - half },
        .{ .x = center.x + half, .y = y, .z = center.z + half },
        vp_w,
        vp_h,
        style,
        .preview,
    );
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

fn distanceSq(ax: f32, ay: f32, bx: f32, by: f32) f32 {
    const dx = ax - bx;
    const dy = ay - by;
    return dx * dx + dy * dy;
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
