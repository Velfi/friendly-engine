const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const project_editor_edit = @import("project_editor_edit_undo.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_types = @import("project_editor_types.zig");
const project_editor_ui_widgets = @import("project_editor_ui_widgets.zig");
const project_editor_ui_world_ocean_actions = @import("project_editor_ui_world_ocean_actions.zig");
const project_editor_world_atmosphere = @import("project_editor_world_atmosphere.zig");
const project_editor_world_authoring_atmosphere = @import("project_editor_world_authoring_atmosphere.zig");
const project_editor_world_authoring_ocean = @import("project_editor_world_authoring_ocean.zig");
const project_editor_world_ocean = @import("project_editor_world_ocean.zig");

const core_ui = friendly_engine.modules.core_ui;
const editor_math = shared.editor_math;
const ProjectEditorState = project_editor_state.ProjectEditorState;
const WorldLayerId = project_editor_types.WorldLayerId;
const world_atmosphere = project_editor_world_atmosphere;
const world_authoring_atmosphere = project_editor_world_authoring_atmosphere;
const world_authoring_ocean = project_editor_world_authoring_ocean;
const world_ocean = project_editor_world_ocean;
const ui_widgets = project_editor_ui_widgets;
const world_manifest_authoring = @import("project_editor_world_authoring_manifest.zig");

pub fn buildAtmosphereControls(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    if (state.world_tool != .atmosphere and (state.selected_world_layer == null or !isAtmosphereLayer(state.selected_world_layer.?))) return;

    world_atmosphere.syncFogFieldsForEditingCell(state);

    try ui.label("Sky");
    var sky_buf: [96]u8 = undefined;
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&sky_buf, "Ambient {d:.2}", .{world_atmosphere.ambientLevel(state)}) catch "Ambient");

    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.syncedCheckbox(ui, "Sun", "ed-world-sun-enabled", state.world_sun_enabled)).clicked) {
        state.world_sun_enabled = !state.world_sun_enabled;
        commitSkyChange(state) catch {};
    }
    if ((try ui_widgets.syncedCheckbox(ui, "Moon", "ed-world-moon-enabled", state.world_moon_enabled)).clicked) {
        state.world_moon_enabled = !state.world_moon_enabled;
        commitSkyChange(state) catch {};
    }
    try core_ui.layout.endSameLine(ui);

    try buildBodyControls(ui, state, .sun);
    try buildBodyControls(ui, state, .moon);
    try buildStarControls(ui, state);

    try ui.label("Fog");
    var scope_buf: [64]u8 = undefined;
    try ui_widgets.compactInfo(ui, world_atmosphere.fogScopeLabel(state, &scope_buf) catch "Fog cell");
    var fog_buf: [96]u8 = undefined;
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(
        &fog_buf,
        "{s}  {d:.0}-{d:.0}m  #{x:0>2}{x:0>2}{x:0>2}",
        .{
            if (state.world_fog_enabled) "On" else "Off",
            state.world_fog_start_m,
            state.world_fog_end_m,
            state.world_fog_color_r,
            state.world_fog_color_g,
            state.world_fog_color_b,
        },
    ) catch "Fog");
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.button(ui, "ed-world-fog-start-minus", "Near-", 52, false)).clicked) adjustFogStart(state, -4.0);
    if ((try ui_widgets.button(ui, "ed-world-fog-start-plus", "Near+", 52, false)).clicked) adjustFogStart(state, 4.0);
    if ((try ui_widgets.button(ui, "ed-world-fog-end-minus", "Far-", 48, false)).clicked) adjustFogEnd(state, -8.0);
    if ((try ui_widgets.button(ui, "ed-world-fog-end-plus", "Far+", 48, false)).clicked) adjustFogEnd(state, 8.0);
    if ((try ui_widgets.button(ui, "ed-world-atmosphere-save", "Save Atmosphere", 132, false)).clicked) {
        try ui_widgets.writeLayer(state, saveAtmosphereLayer, "Atmosphere saved", "Atmosphere save failed");
    }
    try core_ui.layout.endSameLine(ui);
}

pub fn buildOceanWindControls(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    try ui.label("Wind");
    var wind_buf: [128]u8 = undefined;
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(
        &wind_buf,
        "{s}  {d:.0}deg  {d:.1}m/s",
        .{ if (state.ocean_wind_enabled) "On" else "Off", state.ocean_wind_direction_deg, state.ocean_wind_speed_mps },
    ) catch "Wind");
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.syncedCheckbox(ui, "Wind", "ed-world-ocean-wind-enabled", state.ocean_wind_enabled)).clicked) {
        state.ocean_wind_enabled = !state.ocean_wind_enabled;
        project_editor_ui_world_ocean_actions.commitOceanChange(state) catch {};
    }
    if ((try ui_widgets.button(ui, "ed-world-ocean-wind-dir-minus", "Dir-", 48, false)).clicked) adjustOceanWindDirection(state, -15);
    if ((try ui_widgets.button(ui, "ed-world-ocean-wind-dir-plus", "Dir+", 48, false)).clicked) adjustOceanWindDirection(state, 15);
    if ((try ui_widgets.button(ui, "ed-world-ocean-wind-speed-minus", "Speed-", 66, false)).clicked) adjustOceanWindSpeed(state, -1);
    if ((try ui_widgets.button(ui, "ed-world-ocean-wind-speed-plus", "Speed+", 66, false)).clicked) adjustOceanWindSpeed(state, 1);
    if ((try ui_widgets.button(ui, "ed-world-ocean-save-wind", "Save Ocean", 112, false)).clicked) {
        try ui_widgets.writeLayer(state, saveOceanLayer, "Ocean saved", "Ocean save failed");
    }
    try core_ui.layout.endSameLine(ui);
}

pub fn buildOceanWaveControls(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    try ui.label("Waves");
    var wave_buf: [160]u8 = undefined;
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(
        &wave_buf,
        "Ocean {s}  sea {d:.1}m  far {d:.0}m  amp {d:.1}m  len {d:.0}m  speed {d:.1}m/s",
        .{
            if (state.world_ocean_visible) "On" else "Off",
            state.ocean_sea_level_m,
            state.ocean_render_min_distance_m,
            state.ocean_waves_amplitude_m,
            state.ocean_waves_length_m,
            state.ocean_waves_speed_mps,
        },
    ) catch "Waves");
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.syncedCheckbox(ui, "Ocean", "ed-world-ocean-waves-enabled", state.world_ocean_visible)).clicked) {
        project_editor_ui_world_ocean_actions.toggleOcean(state) catch {};
    }
    if ((try ui_widgets.button(ui, "ed-world-ocean-sea-minus", "Sea-", 52, false)).clicked) adjustSeaLevel(state, -0.5);
    if ((try ui_widgets.button(ui, "ed-world-ocean-sea-plus", "Sea+", 52, false)).clicked) adjustSeaLevel(state, 0.5);
    if ((try ui_widgets.button(ui, "ed-world-ocean-amp-minus", "Amp-", 52, false)).clicked) adjustWaveAmplitude(state, -0.1);
    if ((try ui_widgets.button(ui, "ed-world-ocean-amp-plus", "Amp+", 52, false)).clicked) adjustWaveAmplitude(state, 0.1);
    if ((try ui_widgets.button(ui, "ed-world-ocean-len-minus", "Len-", 50, false)).clicked) adjustWaveLength(state, -4);
    if ((try ui_widgets.button(ui, "ed-world-ocean-len-plus", "Len+", 50, false)).clicked) adjustWaveLength(state, 4);
    if ((try ui_widgets.button(ui, "ed-world-ocean-save-waves", "Save Ocean", 112, false)).clicked) {
        try ui_widgets.writeLayer(state, saveOceanLayer, "Ocean saved", "Ocean save failed");
    }
    try core_ui.layout.endSameLine(ui);
    try buildOceanClipControls(ui, state);
}

fn buildOceanClipControls(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    var clip_buf: [128]u8 = undefined;
    var count_buf: [32]u8 = undefined;
    const point_count = oceanClipPointCount(state);
    const count_text = if (point_count == 0)
        "none"
    else
        std.fmt.bufPrint(&count_buf, "{d} points", .{point_count}) catch "points";
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(
        &clip_buf,
        "Boundary {s}  target {d:.0},{d:.0}",
        .{ count_text, state.camera.target.x, state.camera.target.z },
    ) catch "Boundary");
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.button(ui, "ed-world-ocean-clip-add", if (point_count == 0) "New Shape" else "Add Point", 96, false)).clicked) {
        try ui_widgets.writeLayer(state, addOceanClipPointAtTarget, "Ocean boundary updated", "Ocean boundary add failed");
    }
    if ((try ui_widgets.button(ui, "ed-world-ocean-clip-move", "Move Point", 98, false)).clicked) {
        try ui_widgets.writeLayer(state, moveNearestOceanClipPointToTarget, "Ocean point moved", "Ocean move failed");
    }
    if ((try ui_widgets.button(ui, "ed-world-ocean-clip-delete", "Delete Point", 106, false)).clicked) {
        try ui_widgets.writeLayer(state, removeNearestOceanClipPointToTarget, "Ocean point deleted", "Ocean delete failed");
    }
    if ((try ui_widgets.button(ui, "ed-world-ocean-clip-smooth", "Smooth", 68, false)).clicked) {
        try ui_widgets.writeLayer(state, smoothOceanClipShape, "Ocean boundary smoothed", "Ocean boundary smooth failed");
    }
    try core_ui.layout.endSameLine(ui);
}

const SkyBody = enum { sun, moon };

fn buildBodyControls(ui: *core_ui.UiContext, state: *ProjectEditorState, comptime body: SkyBody) !void {
    var info_buf: [96]u8 = undefined;
    const label = switch (body) {
        .sun => std.fmt.bufPrint(&info_buf, "Sun az {d:.0} el {d:.0}", .{ state.world_sun_azimuth_deg, state.world_sun_elevation_deg }) catch "Sun",
        .moon => std.fmt.bufPrint(&info_buf, "Moon az {d:.0} el {d:.0}", .{ state.world_moon_azimuth_deg, state.world_moon_elevation_deg }) catch "Moon",
    };
    try ui_widgets.compactInfo(ui, label);
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.button(ui, bodyControlId(body, "az-minus"), "Az-", 42, false)).clicked) adjustBodyAzimuth(state, body, -15.0);
    if ((try ui_widgets.button(ui, bodyControlId(body, "az-plus"), "Az+", 42, false)).clicked) adjustBodyAzimuth(state, body, 15.0);
    if ((try ui_widgets.button(ui, bodyControlId(body, "el-minus"), "El-", 42, false)).clicked) adjustBodyElevation(state, body, -5.0);
    if ((try ui_widgets.button(ui, bodyControlId(body, "el-plus"), "El+", 42, false)).clicked) adjustBodyElevation(state, body, 5.0);
    try core_ui.layout.endSameLine(ui);
}

fn bodyControlId(comptime body: SkyBody, comptime suffix: []const u8) []const u8 {
    return switch (body) {
        .sun => "ed-world-sun-" ++ suffix,
        .moon => "ed-world-moon-" ++ suffix,
    };
}

fn buildStarControls(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    var info_buf: [96]u8 = undefined;
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&info_buf, "Stars seed {d}", .{state.world_star_seed}) catch "Stars");
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.button(ui, "ed-world-stars-seed-minus", "Seed-", 58, false)).clicked) adjustStarSeed(state, -1);
    if ((try ui_widgets.button(ui, "ed-world-stars-seed-plus", "Seed+", 58, false)).clicked) adjustStarSeed(state, 1);
    if ((try ui_widgets.button(ui, "ed-world-stars-seed-jump", "Seed+100", 82, false)).clicked) adjustStarSeed(state, 100);
    try core_ui.layout.endSameLine(ui);
}

fn adjustStarSeed(state: *ProjectEditorState, delta: i32) void {
    if (delta < 0) {
        state.world_star_seed -%= @intCast(-delta);
    } else {
        state.world_star_seed +%= @intCast(delta);
    }
    commitSkyChange(state) catch {};
}

fn adjustBodyAzimuth(state: *ProjectEditorState, body: SkyBody, delta: f32) void {
    switch (body) {
        .sun => state.world_sun_azimuth_deg = world_atmosphere.wrapAzimuth(state.world_sun_azimuth_deg + delta),
        .moon => state.world_moon_azimuth_deg = world_atmosphere.wrapAzimuth(state.world_moon_azimuth_deg + delta),
    }
    commitSkyChange(state) catch {};
}

fn adjustBodyElevation(state: *ProjectEditorState, body: SkyBody, delta: f32) void {
    switch (body) {
        .sun => state.world_sun_elevation_deg = world_atmosphere.clampElevation(state.world_sun_elevation_deg + delta),
        .moon => state.world_moon_elevation_deg = world_atmosphere.clampElevation(state.world_moon_elevation_deg + delta),
    }
    commitSkyChange(state) catch {};
}

fn adjustFogStart(state: *ProjectEditorState, delta: f32) void {
    state.world_fog_start_m = @max(0, state.world_fog_start_m + delta);
    if (state.world_fog_end_m <= state.world_fog_start_m) state.world_fog_end_m = state.world_fog_start_m + 4;
    commitFogChange(state) catch {};
}

fn adjustFogEnd(state: *ProjectEditorState, delta: f32) void {
    state.world_fog_end_m = @max(state.world_fog_start_m + 4, state.world_fog_end_m + delta);
    commitFogChange(state) catch {};
}

pub fn saveAtmosphereLayer(state: *ProjectEditorState) !void {
    try world_authoring_atmosphere.persistFromState(state);
}

pub fn saveOceanLayer(state: *ProjectEditorState) !void {
    try world_authoring_ocean.persistFromState(state);
}

pub fn commitSkyChange(state: *ProjectEditorState) !void {
    if (state.world_tool != .atmosphere and (state.selected_world_layer == null or !isAtmosphereLayer(state.selected_world_layer.?))) {
        world_atmosphere.setStatus(state);
        return;
    }
    try world_authoring_atmosphere.persistSkyTone(state);
}

pub fn commitFogChange(state: *ProjectEditorState) !void {
    if (state.world_tool != .atmosphere and (state.selected_world_layer == null or !isAtmosphereLayer(state.selected_world_layer.?))) {
        world_atmosphere.setStatus(state);
        return;
    }
    try world_authoring_atmosphere.persistFogBank(state);
}

fn adjustOceanWindDirection(state: *ProjectEditorState, delta: f32) void {
    state.ocean_wind_direction_deg = world_ocean.wrapDirection(state.ocean_wind_direction_deg + delta);
    project_editor_ui_world_ocean_actions.commitOceanChange(state) catch {};
}

fn adjustOceanWindSpeed(state: *ProjectEditorState, delta: f32) void {
    state.ocean_wind_speed_mps = @max(0, state.ocean_wind_speed_mps + delta);
    project_editor_ui_world_ocean_actions.commitOceanChange(state) catch {};
}

fn adjustSeaLevel(state: *ProjectEditorState, delta: f32) void {
    state.ocean_sea_level_m += delta;
    project_editor_ui_world_ocean_actions.commitOceanChange(state) catch {};
}

fn adjustWaveAmplitude(state: *ProjectEditorState, delta: f32) void {
    state.ocean_waves_amplitude_m = @max(0, state.ocean_waves_amplitude_m + delta);
    project_editor_ui_world_ocean_actions.commitOceanChange(state) catch {};
}

fn adjustWaveLength(state: *ProjectEditorState, delta: f32) void {
    state.ocean_waves_length_m = @max(1, state.ocean_waves_length_m + delta);
    project_editor_ui_world_ocean_actions.commitOceanChange(state) catch {};
}

fn addOceanClipPointAtTarget(state: *ProjectEditorState) !void {
    project_editor_edit.pushUndoSnapshot(state);
    try world_ocean.addClipPointAtTarget(state);
    syncOceanClipSelectionFromPoint(state);
}

fn moveNearestOceanClipPointToTarget(state: *ProjectEditorState) !void {
    project_editor_edit.pushUndoSnapshot(state);
    try world_ocean.moveNearestClipPointToTarget(state);
    syncOceanClipSelectionFromPoint(state);
}

fn removeNearestOceanClipPointToTarget(state: *ProjectEditorState) !void {
    project_editor_edit.pushUndoSnapshot(state);
    if (state.selected_ocean_clip_point) |point_index| {
        try world_ocean.removeClipPointAtIndex(state, point_index);
    } else {
        try world_ocean.removeNearestClipPointToTarget(state);
    }
    syncOceanClipSelectionFromPoint(state);
}

fn syncOceanClipSelectionFromPoint(state: *ProjectEditorState) void {
    const object_index = world_ocean.findOceanObjectIndex(state) orelse {
        state.selected_world_curve_hit = .{};
        state.selected_ocean_clip_point = null;
        return;
    };
    state.selected_world_curve_hit = oceanClipSelectionAfterPointDelete(object_index, state.selected_ocean_clip_point, oceanClipPointCount(state));
}

pub fn deleteSelectedOceanClipPart(state: *ProjectEditorState) !void {
    const hit = state.selected_world_curve_hit;
    if (hit.target != .ocean_clip) return error.InvalidOceanClip;
    const point_index = oceanDeletePointIndexForHit(hit, oceanClipPointCount(state)) orelse {
        project_editor_state.setStatus(state, "Select an ocean point or boundary to delete it.");
        return;
    };
    project_editor_edit.pushUndoSnapshot(state);
    try world_ocean.removeClipPointAtIndex(state, point_index);
    const remaining_count = oceanClipPointCount(state);
    const selected_point = if (hit.element == .point) hit.sub_index else state.selected_ocean_clip_point;
    const next_selection = oceanClipSelectionAfterPointDelete(hit.index, selected_point, remaining_count);
    state.selected_ocean_clip_point = if (next_selection.target == .ocean_clip and next_selection.element == .point) next_selection.sub_index else null;
    state.selected_world_curve_hit = next_selection;
    project_editor_state.setStatus(state, if (hit.element == .segment) "Ocean boundary deleted" else "Ocean point deleted");
}

pub fn oceanClipSelectionAfterPointDelete(object_index: usize, selected_point: ?usize, point_count: usize) project_editor_types.WorldCurveHit {
    const point_index = selected_point orelse return .{};
    if (point_count == 0) return .{};
    return .{ .target = .ocean_clip, .element = .point, .index = object_index, .sub_index = @min(point_index, point_count - 1) };
}

pub fn oceanDeletePointIndexForHit(hit: project_editor_types.WorldCurveHit, point_count: usize) ?usize {
    if (point_count < 3) return null;
    if (hit.sub_index >= point_count) return null;
    return switch (hit.element) {
        .point => hit.sub_index,
        .segment => (hit.sub_index + 1) % point_count,
        else => null,
    };
}

fn smoothOceanClipShape(state: *ProjectEditorState) !void {
    const index = world_ocean.findOceanObjectIndex(state) orelse return error.OceanObjectNotFound;
    project_editor_edit.pushUndoSnapshot(state);
    var clip = try world_ocean.loadClip(state.allocator, &state.objects.items[index]);
    defer clip.deinit(state.allocator);
    if (clip.points.len < 3 or clip.points.len > 512) return error.InvalidOceanClip;
    var points = try state.allocator.alloc(world_ocean.ClipPoint, clip.points.len * 2);
    defer state.allocator.free(points);
    var out: usize = 0;
    for (clip.points, 0..) |point, point_index| {
        const next = clip.points[(point_index + 1) % clip.points.len];
        points[out] = .{ .x = point.x * 0.75 + next.x * 0.25, .z = point.z * 0.75 + next.z * 0.25 };
        points[out + 1] = .{ .x = point.x * 0.25 + next.x * 0.75, .z = point.z * 0.25 + next.z * 0.75 };
        out += 2;
    }
    try world_ocean.applyClip(state, index, points, clip.outer_half_extent_m);
}

pub fn oceanClipPointCount(state: *ProjectEditorState) usize {
    const index = world_ocean.findOceanObjectIndex(state) orelse return 0;
    var clip = world_ocean.loadClip(state.allocator, &state.objects.items[index]) catch return 0;
    defer clip.deinit(state.allocator);
    return clip.points.len;
}

pub fn createWaterVolumeAtTarget(state: *ProjectEditorState) !void {
    try createWaterVolumeAtPoint(state, state.camera.target);
}

pub fn createWaterVolumeAtPoint(state: *ProjectEditorState, point: editor_math.Vec3) !void {
    project_editor_edit.pushUndoSnapshot(state);
    const water_mod = friendly_engine.modules.water;
    const manifest_path = try world_manifest_authoring.pathForState(state);
    var doc = try water_mod.authoring.loadProject(state.allocator, state.io, state.project_path, manifest_path);
    defer doc.deinit(state.allocator);

    var volumes = std.ArrayList(water_mod.WaterVolume).empty;
    defer {
        for (volumes.items) |*volume| volume.deinit(state.allocator);
        volumes.deinit(state.allocator);
    }
    for (doc.volumes) |volume| try volumes.append(state.allocator, try water_mod.WaterVolume.duplicate(state.allocator, volume));

    const id = try std.fmt.allocPrint(state.allocator, "water_{d}", .{doc.volumes.len + 1});
    errdefer state.allocator.free(id);
    const material_name = if (state.water_linked_to_ocean) "water.ocean.near" else "water.lake.clear";
    const half: f32 = @max(2.0, state.world_brush_size);
    const points = try state.allocator.dupe([2]f32, &.{
        .{ point.x - half, point.z - half },
        .{ point.x + half, point.z - half },
        .{ point.x + half, point.z + half },
        .{ point.x - half, point.z + half },
    });
    errdefer state.allocator.free(points);
    try volumes.append(state.allocator, .{
        .id = id,
        .kind = if (state.water_linked_to_ocean) .ocean_near else .lake,
        .material = try state.allocator.dupe(u8, material_name),
        .surface_y = state.water_surface_y,
        .bottom_y = @min(state.water_bottom_y, state.water_surface_y - 0.25),
        .swimmable = state.water_swimmable,
        .linked_to_ocean = state.water_linked_to_ocean,
        .current = .{ .x = state.water_current_x, .y = state.water_current_y, .z = state.water_current_z },
        .points = points,
    });
    const owned = try volumes.toOwnedSlice(state.allocator);
    volumes = .empty;
    var out_doc = water_mod.WaterDoc{ .volumes = owned };
    defer out_doc.deinit(state.allocator);
    try water_mod.authoring.saveProject(state.allocator, state.io, state.project_path, manifest_path, out_doc);
    const cell = world_manifest_authoring.cellIdForPoint(state.world_cell_size_m, point);
    try project_editor_state.markDirtyCell(state, "Water", cell, "volumes");
    state.selected_world_curve_hit = .{ .target = .water_volume, .element = .segment, .index = doc.volumes.len, .sub_index = 0 };
    project_editor_state.setStatus(state, "Water shape created");
}

pub fn isConfiguratorLayer(layer: WorldLayerId) bool {
    return isAtmosphereLayer(layer) or project_editor_ui_world_ocean_actions.isOceanLayer(layer) or isWaterLayer(layer);
}

pub fn isAtmosphereLayer(layer: WorldLayerId) bool {
    return switch (layer) {
        .atmosphere_fog_bank, .atmosphere_sky_tone => true,
        else => false,
    };
}

fn isWaterLayer(layer: WorldLayerId) bool {
    return switch (layer) {
        .water_volumes, .water_surface, .water_currents => true,
        else => false,
    };
}
