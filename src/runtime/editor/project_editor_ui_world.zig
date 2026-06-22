const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const command_ids = shared.editor_command_ids;
const editor_math = shared.editor_math;
const shared_color = shared.color;
const project_editor_state = @import("project_editor_state.zig");
const project_editor_types = @import("project_editor_types.zig");
const project_editor_edit = @import("project_editor_edit_undo.zig");
const project_editor_world_bake = @import("project_editor_world_bake.zig");
const project_editor_world_authoring = @import("project_editor_world_authoring.zig");
const world_manifest_authoring = @import("project_editor_world_authoring_manifest.zig");
const project_editor_ui_tree = @import("project_editor_ui_tree.zig");
const project_editor_ui_world_jobs = @import("project_editor_ui_world_jobs.zig");
const project_editor_ui_world_dirty = @import("project_editor_ui_world_dirty.zig");
const project_editor_ui_world_cells = @import("project_editor_ui_world_cells.zig");
const project_editor_ui_world_readouts = @import("project_editor_ui_world_readouts.zig");
const project_editor_ui_world_ocean_actions = @import("project_editor_ui_world_ocean_actions.zig");
const project_editor_ui_world_road_helpers = @import("project_editor_ui_world_road_helpers.zig");
const project_editor_ui_world_scatter_helpers = @import("project_editor_ui_world_scatter_helpers.zig");
const project_editor_ui_world_regions = @import("project_editor_ui_world_regions.zig");
const project_editor_ui_world_region_paint = @import("project_editor_ui_world_region_paint.zig");
const project_editor_ui_world_configurator = @import("project_editor_ui_world_configurator.zig");
const project_editor_ui_world_measure = @import("project_editor_ui_world_measure.zig");
const project_editor_ui_world_ocean_clip = @import("project_editor_ui_world_ocean_clip.zig");
const project_editor_ui_world_overlays = @import("project_editor_ui_world_overlays.zig");
const project_editor_ui_world_scatter_zone = @import("project_editor_ui_world_scatter_zone.zig");
const project_editor_ui_world_water = @import("project_editor_ui_world_water.zig");
const project_editor_dirty_cells = @import("project_editor_dirty_cells.zig");
const project_editor_blockout = @import("project_editor_blockout.zig");
const project_editor_terrain_preview = @import("project_editor_terrain_preview.zig");
const project_editor_viewport = @import("project_editor_viewport.zig");
const project_editor_scatter_preview = @import("project_editor_scatter_preview.zig");
const curve_drawing = @import("project_editor_curve_drawing.zig");
const world_curve_gizmos = @import("project_editor_world_curve_gizmos.zig");
const editor_draw = @import("editor_draw.zig");
const ui_widgets = @import("project_editor_ui_widgets.zig");
const world_atmosphere = @import("project_editor_world_atmosphere.zig");
const project_editor_mode_config = @import("project_editor_mode_config.zig");

const core_ui = friendly_engine.modules.core_ui;
const spline_authoring = friendly_engine.modules.splines.authoring;
const ProjectEditorState = project_editor_state.ProjectEditorState;
const WorldTool = project_editor_types.WorldTool;
const WorldConfigTab = project_editor_types.WorldConfigTab;
const WorldLayerId = project_editor_types.WorldLayerId;
const DirtyCellTracker = project_editor_dirty_cells.DirtyCellTracker;
const world = friendly_engine.world;
const OverlayQuad = shared.gpu_scene.OverlayQuad;
const RoadHitKind = project_editor_ui_world_road_helpers.RoadHitKind;
const RoadHit = project_editor_ui_world_road_helpers.RoadHit;
const RoadSnapKind = project_editor_ui_world_road_helpers.RoadSnapKind;
const RoadSnapTarget = project_editor_ui_world_road_helpers.RoadSnapTarget;

pub fn registerEditor(registry: *project_editor_mode_config.EditorRegistry) !void {
    try registry.registerMode(project_editor_mode_config.descForMode(.world_creation).*);
}

pub fn setWorldTool(state: *ProjectEditorState, tool: WorldTool) void {
    if (state.world_tool == tool) return;
    switchWorldToolStateOnly(state, tool);
    if (tool == .measure) {
        state.world_measure_a = null;
        state.world_measure_b = null;
        project_editor_state.setStatus(state, modeHint(state));
        return;
    }
    if (tool == .scatter) {
        project_editor_state.setStatus(state, modeHint(state));
        return;
    }
    if (tool == .roads) {
        state.selected_world_layer = .spline_road_main;
        clearRoadDraft(state);
        project_editor_state.setStatus(state, modeHint(state));
        return;
    }
    if (tool == .atmosphere) {
        project_editor_state.setStatus(state, "Atmosphere: adjust sky and fog, then Save Atmosphere");
        return;
    }
    if (tool == .ocean) {
        state.world_config_tab = .waves;
        project_editor_state.setStatus(state, modeHint(state));
        return;
    }
    if (tool == .water) {
        state.selected_world_layer = .water_volumes;
        project_editor_state.setStatus(state, modeHint(state));
        return;
    }
    if (tool == .terrain) {
        project_editor_state.setStatus(state, modeHint(state));
        return;
    }
    project_editor_state.setStatus(state, tool.label());
}

fn switchWorldToolStateOnly(state: *ProjectEditorState, tool: WorldTool) void {
    if (state.world_tool == tool) return;
    clearWorldCurveStateForToolChange(state, tool);
    state.world_tool = tool;
}

fn clearWorldCurveStateForToolChange(state: *ProjectEditorState, next_tool: WorldTool) void {
    state.hovered_world_curve_hit = .{};
    state.world_curve_drag_state = .{};
    state.world_curve_drag_anchor = null;
    if (next_tool != .roads) {
        clearRoadDraft(state);
        clearSelectedRoadEdge(state);
        clearSelectedRoadNode(state);
    }
    if (next_tool != .ocean) state.selected_ocean_clip_point = null;
    if (!worldCurveTargetBelongsToTool(state.selected_world_curve_hit.target, next_tool)) {
        state.selected_world_curve_hit = .{};
    }
}

fn worldCurveTargetBelongsToTool(target: project_editor_types.WorldCurveHitTarget, tool: WorldTool) bool {
    return switch (target) {
        .none => true,
        .road => tool == .roads,
        .ocean_clip => tool == .ocean,
        .water_volume => tool == .water,
        .scatter_zone => tool == .scatter,
    };
}

pub fn currentToolLabel(state: *const ProjectEditorState) []const u8 {
    return state.world_tool.label();
}

fn pushWorldCurveUndoSnapshot(state: *ProjectEditorState) void {
    project_editor_edit.pushUndoSnapshot(state);
}

fn beginWorldCurveUndoBatch(state: *ProjectEditorState) void {
    var status_buf: [256]u8 = undefined;
    const status_len = @min(state.status_len, status_buf.len);
    @memcpy(status_buf[0..status_len], state.status_buf[0..status_len]);
    project_editor_edit.beginUndoBatch(state, "World curve edit");
    project_editor_state.setStatus(state, status_buf[0..status_len]);
}

fn endWorldCurveUndoBatch(state: *ProjectEditorState) void {
    var status_buf: [256]u8 = undefined;
    const status_len = @min(state.status_len, status_buf.len);
    @memcpy(status_buf[0..status_len], state.status_buf[0..status_len]);
    project_editor_edit.endUndoBatch(state);
    project_editor_state.setStatus(state, status_buf[0..status_len]);
}

fn rollbackWorldCurveUndoBatch(state: *ProjectEditorState) void {
    const should_undo = state.undo_batch_depth > 0 and state.undo_batch_snapshot_taken;
    if (state.undo_batch_depth > 0) project_editor_edit.cancelUndoBatch(state);
    if (should_undo) project_editor_edit.undo(state);
}

pub fn modeHint(state: *const ProjectEditorState) []const u8 {
    if (activeWorldCurveDragHint(state)) |hint| return hint;
    return switch (state.world_tool) {
        .roads => activeRoadDragHint(state) orelse roadActionHint(state),
        .ocean => project_editor_ui_world_ocean_clip.actionHint(state),
        .water => project_editor_ui_world_water.actionHint(state),
        .scatter => scatterActionHint(state),
        .measure => if (state.world_measure_a == null) "Click to place the first measure point." else "Click to place the second measure point.",
        .terrain => if (state.selected_world_cell == null) "Click a terrain cell to inspect it." else "Use the terrain controls on the selected cell.",
        .paint => if (state.world_region_paint_enabled) "Paint the selected map area on terrain." else "Paint terrain with the active brush.",
        .atmosphere => "Adjust sky or fog, then save atmosphere changes.",
    };
}

fn activeRoadDragHint(state: *const ProjectEditorState) ?[]const u8 {
    if (state.world_road_drag_anchor == null) return null;
    if (state.world_road_mode == .draw) {
        return if (state.world_road_draw_mode == .freehand)
            "Sketching road."
        else
            "Placing road point.";
    }
    if (state.world_road_mode == .join and state.selected_road_node_id != null) return "Previewing road join.";
    if (state.selected_road_edge_id != null) return switch (state.selected_road_handle) {
        .start, .end => "Bending road.",
        .none => "Road line selected.",
    };
    if (state.selected_road_node_id != null) return "Moving road point.";
    return null;
}

fn activeWorldCurveDragHint(state: *const ProjectEditorState) ?[]const u8 {
    const hit = state.world_curve_drag_state.hit;
    if (hit.isNone()) return null;
    return switch (hit.target) {
        .ocean_clip => switch (hit.element) {
            .point => "Moving ocean point.",
            .segment => "Moving ocean boundary.",
            else => null,
        },
        .water_volume => switch (hit.element) {
            .point => "Reshaping water.",
            .segment => "Moving water side.",
            .handle_start => "Adjusting water surface height.",
            .handle_end => "Adjusting water depth.",
            else => null,
        },
        .scatter_zone => switch (hit.element) {
            .point => "Resizing scatter area.",
            .segment => "Resizing scatter side.",
            .width_rail => "Moving scatter area.",
            else => null,
        },
        else => null,
    };
}

pub fn buildViewportTools(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    const tools = [_]WorldTool{ .terrain, .paint, .roads, .scatter, .atmosphere, .ocean, .water, .measure };
    try core_ui.layout.sameLine(ui);
    inline for (tools) |tool| {
        if ((try ui_widgets.flowIconButtonTip(ui, command_ids.worldTool(@tagName(tool)), worldToolIcon(tool), state.world_tool == tool, tool.label())).clicked) {
            setWorldTool(state, tool);
        }
    }
    try core_ui.layout.endSameLine(ui);
}

fn worldToolIcon(tool: WorldTool) []const u8 {
    return switch (tool) {
        .terrain => "grid",
        .paint => "material",
        .roads => "move",
        .scatter => "world",
        .atmosphere => "eye",
        .ocean => "perspective",
        .water => "orthographic",
        .measure => "snap",
    };
}

pub fn buildLayersPanel(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    try ui.label("World Layers");
    _ = try ui_widgets.treeRow(ui, "World", &state.show_world_group);
    if (!state.show_world_group) return;

    try buildTerrainCellsPanel(ui, state);
    try project_editor_ui_world_jobs.buildTerrainJobLoader(ui, state);

    try buildLayerGroup(ui, state, "Terrain", &state.show_world_terrain_group, &.{
        .terrain_base_height,
        .terrain_erosion_mask,
        .terrain_material_tiles,
    });
    try buildLayerGroup(ui, state, "Splines", &state.show_world_splines_group, &.{
        .spline_road_main,
        .spline_path_side,
    });
    try buildLayerGroup(ui, state, "Scatter", &state.show_world_scatter_group, &.{
        .scatter_grass_low,
        .scatter_pine_cluster,
        .scatter_rocks_medium,
        .scatter_density_mask,
    });
    try buildLayerGroup(ui, state, "Atmosphere", &state.show_world_atmosphere_group, &.{
        .atmosphere_fog_bank,
        .atmosphere_sky_tone,
    });
    try buildLayerGroup(ui, state, "Ocean", &state.show_world_ocean_group, &.{
        .ocean_wind,
        .ocean_waves,
    });
    try buildLayerGroup(ui, state, "Water", &state.show_world_water_group, &.{
        .water_volumes,
        .water_surface,
        .water_currents,
    });

    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.button(ui, "ed-recompile-cells", "Bake Dirty", 108, false)).clicked) project_editor_world_bake.recompileDirtyCells(state);
    if ((try ui_widgets.button(ui, "ed-ui-tree", "UI Tree", 78, state.ui_tree_open)).clicked) state.ui_tree_open = !state.ui_tree_open;
    try core_ui.layout.endSameLine(ui);
    if (state.ui_tree_open) {
        var tree_buf: [160]u8 = undefined;
        try core_ui.widgets_feedback.statusLabel(ui, try project_editor_ui_tree.formatStatus(state, ui, &tree_buf));
    }
    if (state.dirty_cells.count > 0) {
        var dirty_buf: [128]u8 = undefined;
        try core_ui.widgets_feedback.statusLabel(ui, try state.dirty_cells.formatStatus(&dirty_buf));
    }
}

pub fn buildToolInspector(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    try buildWorldCurveSelectionStrip(ui, state);
    switch (state.world_tool) {
        .terrain => {
            if (state.selected_world_cell) |id| {
                var selected_buf: [96]u8 = undefined;
                try ui_widgets.compactInfo(ui, std.fmt.bufPrint(
                    &selected_buf,
                    "Selected cell {d},{d},{d}",
                    .{ id.x, id.y, id.z },
                ) catch "Selected cell");
            } else {
                try ui_widgets.compactInfo(ui, "Click a cell to inspect terrain");
            }
            try core_ui.layout.sameLine(ui);
            if ((try ui_widgets.buttonTip(ui, "ed-world-tool-create-cell", "Create Cell", 104, false, "Create terrain cell at camera target")).clicked) {
                try ui_widgets.writeLayer(state, createTerrainCell, "Terrain cell ready", "Terrain cell create failed");
            }
            if ((try ui_widgets.button(ui, "ed-world-tool-apply-cell", "Apply to Cell", 118, false)).clicked) {
                applyActiveTool(state) catch {};
            }
            try core_ui.layout.endSameLine(ui);
        },
        .paint => {
            try core_ui.layout.sameLine(ui);
            if ((try ui_widgets.syncedCheckbox(ui, "Area", "ed-world-region-paint", state.world_region_paint_enabled)).clicked) {
                state.world_region_paint_enabled = !state.world_region_paint_enabled;
            }
            if ((try ui_widgets.syncedCheckbox(ui, "Remove", "ed-world-region-paint-erase", state.world_region_paint_erase)).clicked) {
                state.world_region_paint_erase = !state.world_region_paint_erase;
            }
            try core_ui.layout.endSameLine(ui);
            if (state.world_region_paint_enabled) {
                if (project_editor_ui_world_regions.selectedRegionId(state)) |region_id| {
                    var region_buf: [96]u8 = undefined;
                    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&region_buf, "Painting map area {s}", .{region_id}) catch "Painting map area");
                } else {
                    try core_ui.widgets_feedback.statusLabel(ui, "Select a map area first");
                }
            }
            try buildWorldBrushControls(ui, state, true);
            try core_ui.layout.sameLine(ui);
            if ((try ui_widgets.button(ui, "ed-world-tool-paint-cell", "Apply to Cell", 118, false)).clicked) {
                applyActiveTool(state) catch {};
            }
            try core_ui.layout.endSameLine(ui);
        },
        .roads => {
            try buildRoadControls(ui, state);
        },
        .scatter => {
            if (state.selected_world_layer == .scatter_density_mask) {
                try buildWorldBrushControls(ui, state, false);
            } else {
                try ui_widgets.compactInfo(ui, if (state.selected_world_curve_hit.target == .scatter_zone)
                    project_editor_ui_world_scatter_helpers.scatterSelectionLabel(state.selected_world_curve_hit)
                else
                    "Click to seed, drag blocked areas");
                if (worldCurveSelectionCanDelete(state)) {
                    try core_ui.layout.sameLine(ui);
                    if ((try ui_widgets.flowIconButtonTip(ui, "ed-world-scatter-delete-zone", "delete", false, "Delete Selected Area")).clicked) {
                        _ = deleteSelectedWorldCurvePart(state);
                    }
                    try core_ui.layout.endSameLine(ui);
                }
            }
            if ((try ui_widgets.button(ui, "ed-world-tool-scatter-apply", "Apply Scatter", 118, false)).clicked) {
                applyActiveTool(state) catch {};
            }
        },
        .atmosphere, .ocean => try buildWorldConfigurator(ui, state),
        .water => try buildWaterControls(ui, state),
        .measure => try project_editor_ui_world_measure.buildControls(ui, state),
    }
}

fn buildWorldCurveSelectionStrip(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    if (!isCurveWorldTool(state.world_tool)) return;
    try ui_widgets.compactInfo(ui, worldCurveSelectionLabel(state));
    if (!worldCurveSelectionCanDelete(state)) return;
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.flowIconButtonTip(ui, command_ids.world_curve_delete_selected, "delete", false, "Delete Selected")).clicked) {
        _ = deleteSelectedWorldCurvePart(state);
    }
    try core_ui.layout.endSameLine(ui);
}

fn worldCurveSelectionCanDelete(state: *const ProjectEditorState) bool {
    const hit = state.selected_world_curve_hit;
    return switch (hit.target) {
        .road => state.selected_road_edge_id != null or state.selected_road_node_id != null,
        .ocean_clip => hit.element == .point or hit.element == .segment,
        .water_volume => hit.element == .point or hit.element == .segment,
        .scatter_zone => hit.element == .width_rail,
        .none => false,
    };
}

fn isCurveWorldTool(tool: WorldTool) bool {
    return switch (tool) {
        .roads, .scatter, .ocean, .water => true,
        else => false,
    };
}

fn worldCurveSelectionLabel(state: *const ProjectEditorState) []const u8 {
    return switch (state.selected_world_curve_hit.target) {
        .road => roadSelectionLabel(state),
        .ocean_clip => if (state.selected_world_curve_hit.element == .segment) "Selected ocean boundary" else "Selected ocean point",
        .water_volume => project_editor_ui_world_water.selectionLabel(state),
        .scatter_zone => project_editor_ui_world_scatter_helpers.scatterSelectionLabel(state.selected_world_curve_hit),
        .none => switch (state.world_tool) {
            .roads => "No road selected",
            .ocean => "No ocean boundary selected",
            .water => "No water selected",
            .scatter => "No scatter area selected",
            else => "No curve selected",
        },
    };
}

fn buildLayerGroup(
    ui: *core_ui.UiContext,
    state: *ProjectEditorState,
    label: []const u8,
    open: *bool,
    layers: []const WorldLayerId,
) !void {
    _ = try ui_widgets.treeRow(ui, label, open);
    if (!open.*) return;
    const group_dirty_count = project_editor_ui_world_dirty.dirtyGroupCount(&state.dirty_cells, label);
    if (group_dirty_count > 0) {
        var group_buf: [96]u8 = undefined;
        try ui_widgets.compactInfo(ui, try std.fmt.bufPrint(&group_buf, "{s} dirty cells {d}", .{ label, group_dirty_count }));
    }
    for (layers) |layer| {
        var row_buf: [64]u8 = undefined;
        const row_label = std.fmt.bufPrint(&row_buf, "  {s}", .{layer.label()}) catch layer.label();
        const row_result = try ui_widgets.row(ui, @tagName(layer), row_label, state.selected_world_layer == layer);
        if (row_result.clicked) {
            state.selected_world_layer = layer;
            project_editor_state.setStatus(state, layer.label());
        }
        var dirty_buf: [64]u8 = undefined;
        if (try project_editor_ui_world_dirty.formatLayerDirtyBadge(&state.dirty_cells, layer, &dirty_buf)) |dirty_text| {
            var dirty_id_buf: [64]u8 = undefined;
            const dirty_id = try std.fmt.bufPrint(&dirty_id_buf, "{s}-dirty", .{@tagName(layer)});
            try ui_widgets.text(ui, dirty_id, .{
                .x = row_result.rect.x + @max(0.0, row_result.rect.w - 88),
                .y = row_result.rect.y + 4,
                .w = 82,
                .h = 16,
            }, dirty_text, true);
        }
    }
}

pub fn buildTerrainCellsPanel(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    try project_editor_ui_world_regions.buildTerrainCellsPanel(ui, state);
}

pub fn buildInspector(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    try project_editor_ui_world_cells.buildSelectedCellInspector(ui, state);

    if (state.selected_world_layer) |layer| {
        var layer_buf: [96]u8 = undefined;
        try ui.label(std.fmt.bufPrint(&layer_buf, "{s} / {s}", .{ layer.groupLabel(), layer.label() }) catch layer.label());
        var dirty_buf: [96]u8 = undefined;
        if (try project_editor_ui_world_dirty.formatLayerDirtyStatus(&state.dirty_cells, layer, &dirty_buf)) |dirty_text| {
            try ui_widgets.compactInfo(ui, dirty_text);
        }
    } else {
        try ui.label("World layer");
    }

    if (state.selected_world_layer == null or !project_editor_ui_world_configurator.isConfiguratorLayer(state.selected_world_layer.?)) {
        try buildWorldBrushControls(ui, state, true);
    }

    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.buttonTip(ui, "ed-world-create-cell", "Create Cell", 104, false, "Create terrain cell at camera target")).clicked) {
        try ui_widgets.writeLayer(state, createTerrainCell, "Terrain cell ready", "Terrain cell create failed");
    }
    if ((try ui_widgets.button(ui, "ed-world-apply-cell", "Apply to Cell", 118, false)).clicked) {
        applyActiveTool(state) catch {};
    }
    if ((try ui_widgets.syncedCheckbox(ui, "Fog", "ed-world-fog-inspector", state.world_fog_enabled)).clicked) {
        state.world_fog_enabled = !state.world_fog_enabled;
        state.world_fog_preview = state.world_fog_enabled;
        project_editor_ui_world_configurator.commitFogChange(state) catch {};
    }
    if ((try ui_widgets.syncedCheckbox(ui, "Ocean", "ed-world-ocean-inspector", state.world_ocean_visible)).clicked) {
        project_editor_ui_world_ocean_actions.toggleOcean(state) catch {};
    }
    try core_ui.layout.endSameLine(ui);
    try buildWorldConfigurator(ui, state);

    if (state.world_tool == .measure) try project_editor_ui_world_measure.buildControls(ui, state);
}

fn buildRoadControls(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    try ui.label("Road");
    try core_ui.layout.sameLine(ui);
    const modes = [_]project_editor_types.RoadToolMode{ .draw, .select, .shape, .join, .surface };
    inline for (modes) |mode| {
        if ((try ui_widgets.flowIconButtonTip(ui, roadModeButtonId(mode), roadModeIcon(mode), state.world_road_mode == mode, mode.label())).clicked) {
            setRoadMode(state, mode);
        }
    }
    try core_ui.layout.endSameLine(ui);

    switch (state.world_road_mode) {
        .draw => {
            try core_ui.layout.sameLine(ui);
            if ((try ui_widgets.flowIconButtonTip(ui, command_ids.world_road_draw_freehand, "move", state.world_road_draw_mode == .freehand, "Freehand")).clicked) setRoadDrawMode(state, .freehand);
            if ((try ui_widgets.flowIconButtonTip(ui, command_ids.world_road_draw_point, "select-point-3d", state.world_road_draw_mode == .point_by_point, "Point")).clicked) setRoadDrawMode(state, .point_by_point);
            if ((try ui_widgets.flowIconButtonTip(ui, command_ids.world_road_finish, "save", false, "Finish")).clicked) finishRoadPlacement(state);
            if ((try ui_widgets.flowIconButtonTip(ui, command_ids.world_road_clear, "close", false, "Clear Draft")).clicked) clearRoadPlacement(state);
            try core_ui.layout.endSameLine(ui);
            try ui_widgets.compactInfo(ui, if (state.world_road_draw_mode == .freehand)
                "Drag terrain to draw a road stroke."
            else
                "Click terrain to add points. Enter or double-click finishes.");
        },
        .select => {
            try ui_widgets.compactInfo(ui, roadSelectionLabel(state));
            try core_ui.layout.sameLine(ui);
            if (roadCanDeleteSegment(state)) {
                if ((try ui_widgets.flowIconButtonTip(ui, command_ids.world_road_delete_selected, "delete", false, "Delete Road Line")).clicked) deleteSelectedRoadEdge(state) catch |err| roadActionError(state, err);
            }
            if (roadCanRebuildSelected(state)) {
                if ((try ui_widgets.flowIconButtonTip(ui, command_ids.world_road_rebuild_selected, "build", false, "Rebuild Selected")).clicked) regenerateSelectedRoad(state) catch |err| roadActionError(state, err);
            }
            try core_ui.layout.endSameLine(ui);
        },
        .shape => {
            try ui_widgets.compactInfo(ui, "Drag a yellow point or handle to shape the road.");
            try core_ui.layout.sameLine(ui);
            if (roadCanShapeSelectedSegment(state)) {
                if ((try ui_widgets.flowIconButtonTip(ui, command_ids.world_road_straighten, "select-edge-3d", false, "Straighten Road")).clicked) straightenSelectedRoadSegment(state) catch |err| roadActionError(state, err);
                if ((try ui_widgets.flowIconButtonTip(ui, command_ids.world_road_soften, "move", false, "Soften Road")).clicked) softenSelectedRoadSegment(state) catch |err| roadActionError(state, err);
            }
            if (roadCanRebuildSelected(state)) {
                if ((try ui_widgets.flowIconButtonTip(ui, command_ids.world_road_rebuild_selected, "build", false, "Rebuild Selected")).clicked) regenerateSelectedRoad(state) catch |err| roadActionError(state, err);
            }
            try core_ui.layout.endSameLine(ui);
        },
        .join => {
            try ui_widgets.compactInfo(ui, "Click endpoints to make joins. Drag one point onto another to merge them.");
            try core_ui.layout.sameLine(ui);
            if (roadCanDeleteJoin(state)) {
                if ((try ui_widgets.flowIconButtonTip(ui, command_ids.world_road_delete_selected, "delete", false, "Delete Join")).clicked) deleteSelectedRoadJunction(state) catch |err| roadActionError(state, err);
            }
            try core_ui.layout.endSameLine(ui);
        },
        .surface => {
            try core_ui.layout.sameLine(ui);
            if ((try ui_widgets.flowIconButtonTip(ui, "ed-world-road-surface-decal", "fill-color", state.world_road_surface_mode == .decal, "Decal")).clicked) {
                state.world_road_surface_mode = .decal;
                applySelectedRoadSurfaceSettings(state) catch |err| roadActionError(state, err);
            }
            if ((try ui_widgets.flowIconButtonTip(ui, "ed-world-road-surface-prop", "package", state.world_road_surface_mode == .prop_sections, "Prop Sections")).clicked) {
                state.world_road_surface_mode = .prop_sections;
                applySelectedRoadSurfaceSettings(state) catch |err| roadActionError(state, err);
            }
            try core_ui.layout.endSameLine(ui);
            try buildRoadSurfaceControls(ui, state);
        },
    }
}

pub fn setRoadMode(state: *ProjectEditorState, mode: project_editor_types.RoadToolMode) void {
    const previous_mode = state.world_road_mode;
    state.world_road_mode = mode;
    clearRoadDragSession(state);
    if (previous_mode == .draw and mode != .draw) clearRoadDraft(state);
    normalizeRoadSelectionForMode(state, mode);
    project_editor_state.setStatus(state, roadModeStatus(mode));
}

pub fn setRoadDrawMode(state: *ProjectEditorState, mode: project_editor_types.CurveDrawMode) void {
    state.world_road_mode = .draw;
    state.world_road_draw_mode = mode;
    clearRoadPlacement(state);
    project_editor_state.setStatus(state, roadActionHint(state));
}

fn normalizeRoadSelectionForMode(state: *ProjectEditorState, mode: project_editor_types.RoadToolMode) void {
    switch (mode) {
        .surface => {
            if (state.selected_road_edge_id) |edge_id| {
                if (state.selected_road_handle == .none) return;
                state.selected_road_handle = .none;
                state.selected_world_curve_hit = .{
                    .target = .road,
                    .element = .segment,
                    .index = resolveRoadSelectionIndex(state, .segment, edge_id) orelse state.selected_world_curve_hit.index,
                };
            }
        },
        .join => {
            if (state.selected_road_edge_id != null) clearSelectedRoadEdge(state);
        },
        .draw => {
            clearSelectedRoadEdge(state);
            clearSelectedRoadNode(state);
        },
        .select, .shape => {},
    }
}

fn buildRoadSurfaceControls(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    var surface_buf: [160]u8 = undefined;
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(
        &surface_buf,
        "{s}  Width {d:.1}m  Terrain {s}",
        .{ state.world_road_surface_mode.label(), state.world_road_width, state.world_road_terrain_mode.label() },
    ) catch "Road surface");
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.flowIconButtonTip(ui, "ed-world-road-width-minus", "minus", false, "Narrower")).clicked) {
        state.world_road_width = @max(1.0, state.world_road_width - 0.5);
        applySelectedRoadSurfaceSettings(state) catch |err| roadActionError(state, err);
    }
    if ((try ui_widgets.flowIconButtonTip(ui, "ed-world-road-width-plus", "add", false, "Wider")).clicked) {
        state.world_road_width = @min(24.0, state.world_road_width + 0.5);
        applySelectedRoadSurfaceSettings(state) catch |err| roadActionError(state, err);
    }
    if ((try ui_widgets.flowIconButtonTip(ui, "ed-world-road-terrain-conform", "magnet", state.world_road_terrain_mode == .conform, "Conform")).clicked) {
        state.world_road_terrain_mode = .conform;
        applySelectedRoadSurfaceSettings(state) catch |err| roadActionError(state, err);
    }
    if ((try ui_widgets.flowIconButtonTip(ui, "ed-world-road-terrain-floating", "perspective", state.world_road_terrain_mode == .floating, "Floating")).clicked) {
        state.world_road_terrain_mode = .floating;
        applySelectedRoadSurfaceSettings(state) catch |err| roadActionError(state, err);
    }
    if ((try ui_widgets.flowIconButtonTip(ui, "ed-world-road-terrain-tunnel", "cube-scan", state.world_road_terrain_mode == .tunnel_reserved, "Tunnel")).clicked) {
        state.world_road_terrain_mode = .tunnel_reserved;
        applySelectedRoadSurfaceSettings(state) catch |err| roadActionError(state, err);
        project_editor_state.setStatus(state, "Tunnel roads are marked; terrain cutting comes later");
    }
    try core_ui.layout.endSameLine(ui);

    if (state.world_road_surface_mode == .decal) {
        var decal_buf: [160]u8 = undefined;
        try ui_widgets.compactInfo(ui, std.fmt.bufPrint(
            &decal_buf,
            "Material road.dirt  Shoulder {d:.1}m  Offset {d:.2}m",
            .{ state.world_road_shoulder_fade, state.world_road_conform_offset },
        ) catch "Decal road");
        try core_ui.layout.sameLine(ui);
        if ((try ui_widgets.flowIconButtonTip(ui, "ed-world-road-shoulder-minus", "minus", false, "Less Shoulder")).clicked) state.world_road_shoulder_fade = @max(0.0, state.world_road_shoulder_fade - 0.1);
        if ((try ui_widgets.flowIconButtonTip(ui, "ed-world-road-shoulder-plus", "add", false, "More Shoulder")).clicked) state.world_road_shoulder_fade = @min(3.0, state.world_road_shoulder_fade + 0.1);
        if ((try ui_widgets.flowIconButtonTip(ui, "ed-world-road-offset-minus", "minus", false, "Lower Offset")).clicked) {
            state.world_road_conform_offset = @max(0.0, state.world_road_conform_offset - 0.01);
            applySelectedRoadSurfaceSettings(state) catch |err| roadActionError(state, err);
        }
        if ((try ui_widgets.flowIconButtonTip(ui, "ed-world-road-offset-plus", "add", false, "Raise Offset")).clicked) {
            state.world_road_conform_offset = @min(1.0, state.world_road_conform_offset + 0.01);
            applySelectedRoadSurfaceSettings(state) catch |err| roadActionError(state, err);
        }
        try core_ui.layout.endSameLine(ui);
    } else {
        var prop_buf: [160]u8 = undefined;
        try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&prop_buf, "Prop road_section_straight  Spacing {d:.1}m  Caps on", .{state.world_road_prop_spacing}) catch "Prop section road");
        try core_ui.layout.sameLine(ui);
        if ((try ui_widgets.flowIconButtonTip(ui, "ed-world-road-prop-spacing-minus", "minus", false, "Less Spacing")).clicked) state.world_road_prop_spacing = @max(0.5, state.world_road_prop_spacing - 0.5);
        if ((try ui_widgets.flowIconButtonTip(ui, "ed-world-road-prop-spacing-plus", "add", false, "More Spacing")).clicked) state.world_road_prop_spacing = @min(16.0, state.world_road_prop_spacing + 0.5);
        try core_ui.layout.endSameLine(ui);
    }

    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.flowIconButtonTip(ui, command_ids.world_road_rebuild_selected, "build", false, "Rebuild Selected")).clicked) regenerateSelectedRoad(state) catch |err| roadActionError(state, err);
    if ((try ui_widgets.flowIconButtonTip(ui, command_ids.world_road_rebuild_all, "build", false, "Rebuild All Roads")).clicked) regenerateAllRoads(state) catch |err| roadActionError(state, err);
    try core_ui.layout.endSameLine(ui);
}

fn roadModeStatus(mode: project_editor_types.RoadToolMode) []const u8 {
    return switch (mode) {
        .draw => "Draw: click terrain to add points, drag to sketch, Enter finishes",
        .select => "Select: choose a road line, point, or handle",
        .shape => "Shape: drag a yellow point or handle to bend the road",
        .join => "Join: connect endpoints or merge nearby points",
        .surface => "Surface: choose how the selected road appears",
    };
}

fn roadModeButtonId(mode: project_editor_types.RoadToolMode) []const u8 {
    return switch (mode) {
        inline else => |tag| command_ids.worldRoadMode(@tagName(tag)),
    };
}

fn roadModeIcon(mode: project_editor_types.RoadToolMode) []const u8 {
    return switch (mode) {
        .draw => "cursor",
        .select => "select-edge-3d",
        .shape => "move",
        .join => "select-point-3d",
        .surface => "fill-color",
    };
}

fn roadSelectionLabel(state: *const ProjectEditorState) []const u8 {
    if (state.selected_road_edge_id != null) return switch (state.selected_road_handle) {
        .start => "Selected start handle",
        .end => "Selected end handle",
        .none => "Selected road line",
    };
    if (state.selected_road_node_id != null) return "Selected point";
    return "No road selected";
}

fn roadCanDeleteSegment(state: *const ProjectEditorState) bool {
    return state.selected_road_edge_id != null and state.selected_road_handle == .none;
}

fn roadCanShapeSelectedSegment(state: *const ProjectEditorState) bool {
    return state.selected_road_edge_id != null;
}

fn roadCanDeleteJoin(state: *const ProjectEditorState) bool {
    return state.selected_road_node_id != null;
}

fn roadCanRebuildSelected(state: *const ProjectEditorState) bool {
    return state.selected_road_edge_id != null or state.selected_road_node_id != null;
}

fn roadActionHint(state: *const ProjectEditorState) []const u8 {
    if (state.world_road_mode == .draw) {
        if (state.world_road_draw_mode == .freehand) return "Drag on terrain to sketch a road.";
        if (state.world_road_points.items.len > 0) return "Click the next point, or double-click to finish.";
        return "Click terrain to start a road.";
    }
    if (state.world_road_mode == .join) {
        if (state.selected_road_node_id != null) return "Drag this point onto another road point or line.";
        return "Click a road endpoint to make a join.";
    }
    if (state.selected_road_edge_id != null) return switch (state.selected_road_handle) {
        .start, .end => "Drag the yellow handle to bend the road.",
        .none => if (state.world_road_mode == .shape) "Use Straighten or Soften, or double-click to add a point." else "Double-click the road line to add a point.",
    };
    if (state.selected_road_node_id != null) return "Drag the yellow point to move it.";
    return switch (state.world_road_mode) {
        .shape => "Click a road point, line, or handle to shape it.",
        .surface => "Select a road, then adjust width and surface.",
        else => "Click a road point, line, or handle.",
    };
}

fn scatterActionHint(state: *const ProjectEditorState) []const u8 {
    if (state.selected_world_layer == .scatter_density_mask) return "Paint density directly on terrain.";
    if (state.selected_world_curve_hit.target == .scatter_zone) {
        return switch (state.selected_world_curve_hit.element) {
            .point => "Drag this corner to resize the blocked area.",
            .segment => "Drag this side to resize the blocked area.",
            .width_rail => "Drag inside the area to move it.",
            else => "Edit the selected scatter area.",
        };
    }
    if (state.hovered_world_curve_hit.target == .scatter_zone) return "Click to select this scatter area.";
    return "Click to seed scatter, or drag to draw a blocked area.";
}

fn roadActionError(state: *ProjectEditorState, err: anyerror) void {
    const message: []const u8 = switch (err) {
        error.NoRoadEdgeSelected => "Select a road line first",
        error.NoRoadNodeSelected => "Select a road point first",
        error.RoadNodeStillConnected => "This point is still connected",
        error.MissingRoadEdge => "Select a road line first",
        error.MissingRoadNode => "Road endpoint missing",
        error.UnsupportedRoadSelection => "That road piece is not editable yet",
        else => "Road action failed",
    };
    project_editor_state.setStatus(state, message);
}

pub fn deleteSelectedWorldCurvePart(state: *ProjectEditorState) bool {
    if (state.mode != .world_creation) return false;
    if (!worldCurveSelectionCanDelete(state)) {
        project_editor_state.setStatus(state, worldCurveDeleteUnavailableMessage(state));
        return false;
    }
    switch (state.selected_world_curve_hit.target) {
        .road => {
            if (state.selected_road_edge_id != null) {
                deleteSelectedRoadEdge(state) catch |err| roadActionError(state, err);
                return true;
            }
            if (state.selected_road_node_id != null) {
                deleteSelectedRoadJunction(state) catch |err| roadActionError(state, err);
                return true;
            }
            return false;
        },
        .ocean_clip => {
            project_editor_ui_world_configurator.deleteSelectedOceanClipPart(state) catch {
                project_editor_state.setStatus(state, "Ocean point delete failed");
            };
            return true;
        },
        .water_volume => {
            project_editor_ui_world_water.deleteSelectedPart(state) catch |err| project_editor_ui_world_water.actionError(state, err);
            return true;
        },
        .scatter_zone => {
            project_editor_ui_world_scatter_zone.deleteSelected(state) catch {
                project_editor_state.setStatus(state, "Scatter area delete failed");
            };
            return true;
        },
        else => return false,
    }
}

fn worldCurveDeleteUnavailableMessage(state: *const ProjectEditorState) []const u8 {
    const hit = state.selected_world_curve_hit;
    return switch (hit.target) {
        .road => "Select part of a road first",
        .ocean_clip => "Select an ocean point or boundary first",
        .water_volume => switch (hit.element) {
            .handle_start => "Drag the surface handle to change water height",
            .handle_end => "Drag the bottom handle to change water depth",
            else => "Select a water point or side first",
        },
        .scatter_zone => switch (hit.element) {
            .point => "Drag this corner to resize it; select the area to delete it",
            .segment => "Drag this side to resize it; select the area to delete it",
            else => "Select a scatter area first",
        },
        .none => "Select something on a curve first",
    };
}

fn buildWorldBrushControls(ui: *core_ui.UiContext, state: *ProjectEditorState, include_terrain_channels: bool) !void {
    try ui.label("Brush");
    var size_buf: [64]u8 = undefined;
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&size_buf, "Size {d:.1}m  Strength {d:.2}", .{
        state.world_brush_size,
        state.world_brush_strength,
    }) catch "Brush");
    var falloff_buf: [32]u8 = undefined;
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&falloff_buf, "Falloff {d:.2}", .{state.world_brush_falloff}) catch "Falloff");
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.button(ui, "ed-world-brush-minus", "-", 28, false)).clicked) state.world_brush_size = @max(1.0, state.world_brush_size - 1.0);
    if ((try ui_widgets.button(ui, "ed-world-brush-plus", "+", 28, false)).clicked) state.world_brush_size = @min(64.0, state.world_brush_size + 1.0);
    if ((try ui_widgets.button(ui, "ed-world-strength-minus", "S-", 34, false)).clicked) state.world_brush_strength = @max(0.05, state.world_brush_strength - 0.05);
    if ((try ui_widgets.button(ui, "ed-world-strength-plus", "S+", 34, false)).clicked) state.world_brush_strength = @min(1.0, state.world_brush_strength + 0.05);
    if ((try ui_widgets.button(ui, "ed-world-falloff-minus", "F-", 34, false)).clicked) state.world_brush_falloff = @max(0.05, state.world_brush_falloff - 0.05);
    if ((try ui_widgets.button(ui, "ed-world-falloff-plus", "F+", 34, false)).clicked) state.world_brush_falloff = @min(1.0, state.world_brush_falloff + 0.05);
    try core_ui.layout.endSameLine(ui);

    state.world_brush_material = try terrainByteSlider(ui, "ed-world-material-slider", "Material", state.world_brush_material, 3);
    state.world_brush_tile = try terrainByteSlider(ui, "ed-world-tile-slider", "Tile", state.world_brush_tile, 63);

    if (!include_terrain_channels) return;
    if ((try ui_widgets.syncedCheckbox(ui, "Height", "ed-world-affects-height", state.world_affects_height)).clicked) {
        state.world_affects_height = !state.world_affects_height;
    }
    if ((try ui_widgets.syncedCheckbox(ui, "Material", "ed-world-affects-material", state.world_affects_material)).clicked) {
        state.world_affects_material = !state.world_affects_material;
    }
    if (!state.world_affects_height and !state.world_affects_material) {
        try core_ui.widgets_feedback.statusLabel(ui, "Select Height and/or Material");
    }
}

fn terrainByteSlider(ui: *core_ui.UiContext, id: []const u8, label: []const u8, value: u8, max_value: u8) !u8 {
    const clamped_value = @min(value, max_value);
    var label_buf: [64]u8 = undefined;
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&label_buf, "{s} {d}", .{ label, clamped_value }) catch label);

    const stable = try ui.stableId(id, id);
    try ui.setFloatState(stable, @floatFromInt(clamped_value));
    const result = try core_ui.widgets_input.slider(ui, .{
        .id = id,
        .value = @floatFromInt(clamped_value),
        .min = 0,
        .max = @floatFromInt(max_value),
    });
    if (!result.changed) return clamped_value;

    const rounded = std.math.clamp(@round(result.value), 0, @as(f32, @floatFromInt(max_value)));
    const next: u8 = @intFromFloat(rounded);
    try ui.setFloatState(stable, @floatFromInt(next));
    return next;
}

pub fn buildBottomReadouts(ui: *core_ui.UiContext, state: *ProjectEditorState, rect: core_ui.Rect) !void {
    try project_editor_ui_world_readouts.buildBottomReadouts(ui, state, rect);
}

pub fn drawViewportOverlays(state: *ProjectEditorState, vp_w: f32, vp_h: f32) void {
    if (state.mode != .world_creation) return;

    if (state.show_cell_bounds) project_editor_ui_world_overlays.drawLatestDirtyCellMarker(state, vp_w, vp_h);
    project_editor_ui_world_region_paint.drawSelectedOverlay(state, vp_w, vp_h);

    switch (state.world_tool) {
        .terrain => {
            project_editor_ui_world_overlays.drawSelectedCellMarker(state, vp_w, vp_h);
            project_editor_ui_world_overlays.drawTerrainBrushRing(state, vp_w, vp_h);
        },
        .paint => {
            project_editor_ui_world_overlays.drawTerrainBrushRing(state, vp_w, vp_h);
        },
        .roads => drawRoadSplineHandles(state, vp_w, vp_h),
        .scatter => {
            project_editor_scatter_preview.drawOverlay(state, vp_w, vp_h);
            project_editor_scatter_preview.drawDragPreview(state, vp_w, vp_h);
            if (state.selected_world_layer == .scatter_density_mask) {
                project_editor_ui_world_overlays.drawScatterDensityBrushRing(state, vp_w, vp_h);
            } else {
                project_editor_ui_world_scatter_zone.drawPreview(state, vp_w, vp_h);
            }
        },
        .atmosphere => {},
        .water => project_editor_ui_world_water.drawOverlay(state, vp_w, vp_h),
        .ocean => project_editor_ui_world_ocean_clip.drawOverlay(state, vp_w, vp_h),
        .measure => project_editor_ui_world_measure.drawOverlay(state, vp_w, vp_h),
    }

    if (project_editor_ui_world_readouts.fogPreviewActive(state)) project_editor_ui_world_overlays.drawFogPreview(state);
    if (state.world_lighting_preview and state.world_tool == .atmosphere) project_editor_ui_world_overlays.drawLightingPreview(state, vp_w, vp_h);
    project_editor_terrain_preview.drawCollisionOverlays(state, vp_w, vp_h);
}

pub fn appendGpuViewportOverlays(state: *ProjectEditorState, allocator: std.mem.Allocator, out: *std.ArrayList(OverlayQuad)) !void {
    if (state.mode != .world_creation) return;
    const vp_w = state.viewport_screen_rect.w;
    const vp_h = state.viewport_screen_rect.h;
    try project_editor_ui_world_region_paint.appendGpuSelectedOverlay(state, allocator, out, vp_w, vp_h);
    switch (state.world_tool) {
        .terrain, .paint => try project_editor_ui_world_overlays.appendGpuTerrainBrushRing(state, allocator, out, vp_w, vp_h),
        .scatter => if (state.selected_world_layer == .scatter_density_mask) try project_editor_ui_world_overlays.appendGpuScatterDensityBrushRing(state, allocator, out, vp_w, vp_h),
        else => {},
    }
}

fn buildWorldConfigurator(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    if (state.world_tool != .atmosphere and state.world_tool != .ocean and
        (state.selected_world_layer == null or !project_editor_ui_world_configurator.isConfiguratorLayer(state.selected_world_layer.?))) return;

    if (state.selected_world_layer) |layer| {
        if (project_editor_ui_world_configurator.isAtmosphereLayer(layer)) state.world_config_tab = .atmosphere;
        if (layer == .ocean_wind) state.world_config_tab = .wind;
        if (layer == .ocean_waves) state.world_config_tab = .waves;
    }

    try ui.label("Configurator");
    try core_ui.layout.sameLine(ui);
    inline for (std.meta.fields(WorldConfigTab)) |field| {
        const tab: WorldConfigTab = @enumFromInt(@intFromEnum(@field(WorldConfigTab, field.name)));
        var id_buf: [48]u8 = undefined;
        const id = std.fmt.bufPrint(&id_buf, "ed-world-config-{s}", .{field.name}) catch "ed-world-config";
        if ((try ui_widgets.button(ui, id, tab.label(), 96, state.world_config_tab == tab)).clicked) {
            state.world_config_tab = tab;
            switchWorldToolStateOnly(state, if (tab == .atmosphere) .atmosphere else .ocean);
            state.selected_world_layer = switch (tab) {
                .atmosphere => .atmosphere_sky_tone,
                .wind => .ocean_wind,
                .waves => .ocean_waves,
            };
        }
    }
    try core_ui.layout.endSameLine(ui);

    switch (state.world_config_tab) {
        .atmosphere => try project_editor_ui_world_configurator.buildAtmosphereControls(ui, state),
        .wind => try project_editor_ui_world_configurator.buildOceanWindControls(ui, state),
        .waves => try project_editor_ui_world_configurator.buildOceanWaveControls(ui, state),
    }
}

fn buildWaterControls(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    try project_editor_ui_world_water.buildControls(ui, state);
}

pub fn beginOceanClipInteraction(state: *ProjectEditorState, screen_x: f32, screen_y: f32, click_count: u8) WorldCurveInteractionBegin {
    return switch (project_editor_ui_world_ocean_clip.beginInteraction(state, screen_x, screen_y, click_count)) {
        .none => .none,
        .handled => .handled,
        .drag => .drag,
    };
}

pub fn handleViewportOceanClipDrag(state: *ProjectEditorState, screen_x: f32, screen_y: f32) void {
    project_editor_ui_world_ocean_clip.handleDrag(state, screen_x, screen_y);
}

pub fn applyActiveTool(state: *ProjectEditorState) !void {
    try applyWorldToolAt(state, state.camera.target);
}

pub fn applyWorldToolAt(state: *ProjectEditorState, point: editor_math.Vec3) !void {
    const saved_target = state.camera.target;
    state.camera.target = point;
    defer state.camera.target = saved_target;

    switch (state.world_tool) {
        .terrain => try ui_widgets.writeLayer(state, applyTerrainCellAtPoint, "Terrain cell ready", "Terrain cell create failed"),
        .paint => if (state.world_region_paint_enabled)
            try paintRegionMembershipAt(state, point)
        else
            try ui_widgets.writeLayer(state, applyTerrainAtPoint, "Terrain layer updated", "Terrain layer write failed"),
        .roads => try ui_widgets.writeLayer(state, applyRoadThroughCell, "Road updated", "Road update failed"),
        .scatter => try ui_widgets.writeLayer(state, applyScatterAtPoint, "Scatter layer updated", "Scatter layer write failed"),
        .atmosphere => try ui_widgets.writeLayer(state, project_editor_ui_world_configurator.saveAtmosphereLayer, "Atmosphere saved", "Atmosphere save failed"),
        .ocean => try ui_widgets.writeLayer(state, project_editor_ui_world_configurator.saveOceanLayer, "Ocean saved", "Ocean save failed"),
        .water => try ui_widgets.writeLayer(state, project_editor_ui_world_configurator.createWaterVolumeAtTarget, "Water shape created", "Water shape failed"),
        .measure => project_editor_state.setStatus(state, "Measure: click viewport to place points"),
    }
}

pub fn selectCellAtScreen(state: *ProjectEditorState, screen_x: f32, screen_y: f32) void {
    if (state.world_tool != .terrain) return;
    const pt = project_editor_blockout.screenToGroundPoint(state, screen_x, screen_y) orelse {
        project_editor_state.setStatus(state, "Cell selection missed ground plane");
        return;
    };
    selectCellAtPoint(state, pt);
}

fn selectCellAtPoint(state: *ProjectEditorState, point: editor_math.Vec3) void {
    const manifest_path = world_manifest_authoring.pathForState(state) catch {
        project_editor_state.setStatus(state, "Cell selection failed: scene world not configured");
        return;
    };
    var loaded_manifest = world.manifest.loadManifest(state.allocator, state.io, state.project_path, manifest_path) catch {
        project_editor_state.setStatus(state, "Cell selection failed");
        return;
    };
    defer loaded_manifest.deinit();

    state.world_cell_size_m = loaded_manifest.cell_size_m;
    const id = world_manifest_authoring.cellIdForPoint(loaded_manifest.cell_size_m, point);
    state.selected_world_cell = id;
    state.camera.target = world_manifest_authoring.cellCenter(id, loaded_manifest.cell_size_m);

    var buf: [128]u8 = undefined;
    const manifest_suffix: []const u8 = if (loaded_manifest.hasCell(id)) "" else " (not in manifest)";
    project_editor_state.setStatus(state, std.fmt.bufPrint(
        &buf,
        "Selected cell {d},{d},{d}{s}",
        .{ id.x, id.y, id.z, manifest_suffix },
    ) catch "Selected cell");
}

pub fn placeTerrainCellAtScreen(state: *ProjectEditorState, screen_x: f32, screen_y: f32) void {
    if (state.world_tool != .terrain) return;
    const pt = project_editor_blockout.screenToGroundPoint(state, screen_x, screen_y) orelse {
        project_editor_state.setStatus(state, "Terrain cell placement missed ground plane");
        return;
    };
    state.camera.target = pt;
    project_editor_world_authoring.createTerrainCellAt(state, pt) catch {
        project_editor_state.setStatus(state, "Terrain cell create failed");
    };
}

pub fn deleteTerrainCellAtScreen(state: *ProjectEditorState, screen_x: f32, screen_y: f32) void {
    if (state.world_tool != .terrain) return;
    const pt = project_editor_blockout.screenToGroundPoint(state, screen_x, screen_y) orelse {
        project_editor_state.setStatus(state, "Terrain cell deletion missed ground plane");
        return;
    };
    state.camera.target = pt;
    project_editor_world_authoring.deleteTerrainCellAt(state, pt) catch |err| {
        const message: []const u8 = switch (err) {
            error.WorldCellNotInManifest => "Terrain delete failed: no cell here",
            else => "Terrain cell delete failed",
        };
        project_editor_state.setStatus(state, message);
    };
}

pub fn handleViewportClick(state: *ProjectEditorState, screen_x: f32, screen_y: f32) void {
    switch (state.world_tool) {
        .terrain, .paint => return,
        else => {},
    }
    const pt = project_editor_blockout.screenToGroundPoint(state, screen_x, screen_y) orelse {
        project_editor_state.setStatus(state, "World click missed ground plane");
        return;
    };
    state.camera.target = pt;
    switch (state.world_tool) {
        .measure => project_editor_ui_world_measure.handleClick(state, pt),
        .roads => {},
        .atmosphere => world_atmosphere.syncFogFieldsForEditingCell(state),
        .ocean => {},
        .water => {
            project_editor_ui_world_configurator.createWaterVolumeAtPoint(state, pt) catch project_editor_state.setStatus(state, "Water shape failed");
        },
        .scatter, .terrain, .paint => {},
    }
}

pub fn beginRoadDrag(state: *ProjectEditorState, screen_x: f32, screen_y: f32) void {
    if (selectRoadGraphAtScreen(state, screen_x, screen_y)) {
        if (state.world_road_mode != .draw) beginWorldCurveUndoBatch(state);
        return;
    }
    if (state.world_road_mode != .draw) {
        clearRoadSelection(state);
        project_editor_state.setStatus(state, "No road selected");
        return;
    }
    const pt = project_editor_blockout.screenToGroundPoint(state, screen_x, screen_y) orelse {
        project_editor_state.setStatus(state, "Road placement missed ground plane");
        return;
    };
    const snapped = snappedRoadPointAtScreen(state, screen_x, screen_y) orelse pt;
    state.world_road_drag_anchor = snapped;
    state.world_road_preview_end = snapped;
    if (state.world_road_draw_mode == .freehand) {
        curve_drawing.beginFreehand(state.allocator, roadDraft(state), snapped) catch {
            project_editor_state.setStatus(state, "Road point failed");
        };
    }
}

pub fn handleViewportRoadDrag(state: *ProjectEditorState, screen_x: f32, screen_y: f32) void {
    if (state.world_road_mode != .draw) {
        moveSelectedRoadGraphItem(state, screen_x, screen_y) catch |err| roadActionError(state, err);
        return;
    }
    const pt = snappedRoadPointAtScreen(state, screen_x, screen_y) orelse project_editor_blockout.screenToGroundPoint(state, screen_x, screen_y) orelse return;
    state.world_road_preview_end = pt;
    if (state.world_road_draw_mode == .freehand) {
        curve_drawing.sampleFreehand(state.allocator, roadDraft(state), pt, roadFreehandSpacing(state)) catch |err| switch (err) {
            error.PointTooClose => {},
            else => project_editor_state.setStatus(state, "Road point failed"),
        };
    }
}

pub fn handleViewportCurveGizmoDrag(state: *ProjectEditorState, screen_x: f32, screen_y: f32) void {
    switch (state.world_tool) {
        .roads => handleViewportRoadDrag(state, screen_x, screen_y),
        .ocean => handleViewportOceanClipDrag(state, screen_x, screen_y),
        .water => project_editor_ui_world_water.moveSelectedPart(state, screen_x, screen_y) catch |err| project_editor_ui_world_water.actionError(state, err),
        .scatter => project_editor_ui_world_scatter_zone.moveSelectedPart(state, screen_x, screen_y) catch {
            project_editor_state.setStatus(state, "Scatter area edit failed");
        },
        else => {},
    }
}

pub fn finishWorldCurveGizmoDrag(state: *ProjectEditorState) void {
    state.world_curve_drag_state = .{};
    state.world_curve_drag_anchor = null;
    endWorldCurveUndoBatch(state);
}

pub fn cancelWorldCurveGizmoDrag(state: *ProjectEditorState) void {
    state.world_curve_drag_state = .{};
    state.world_curve_drag_anchor = null;
    rollbackWorldCurveUndoBatch(state);
}

pub fn cancelRoadDrag(state: *ProjectEditorState) void {
    if (state.world_road_mode == .draw) {
        clearRoadPlacement(state);
        return;
    }
    clearRoadDragSession(state);
    rollbackWorldCurveUndoBatch(state);
}

pub fn updateRoadPointPreview(state: *ProjectEditorState, screen_x: f32, screen_y: f32) void {
    if (state.world_road_draw_mode != .point_by_point) return;
    curve_drawing.setPreview(roadDraft(state), snappedRoadPointAtScreen(state, screen_x, screen_y) orelse project_editor_blockout.screenToGroundPoint(state, screen_x, screen_y));
}

pub fn finishRoadDrag(state: *ProjectEditorState, dragged: bool, click_count: u8) void {
    if (state.world_road_mode != .draw) {
        defer endWorldCurveUndoBatch(state);
        if (state.world_road_mode == .join and dragged) {
            mergeSelectedRoadNodeAtScreen(state, state.mouse_x, state.mouse_y) catch |err| roadActionError(state, err);
        } else if (!dragged and click_count >= 2 and state.selected_road_edge_id != null and state.selected_road_handle == .none) {
            splitSelectedRoadEdgeAtScreen(state, state.mouse_x, state.mouse_y) catch |err| roadActionError(state, err);
        }
        clearRoadDragSession(state);
        return;
    }
    const anchor = state.world_road_drag_anchor orelse return;
    defer clearRoadDragSession(state);

    if (state.world_road_draw_mode == .freehand) {
        pushWorldCurveUndoSnapshot(state);
        const result = commitRoadDraft(state) catch {
            project_editor_state.setStatus(state, if (state.world_road_points.items.len < 2) "Road stroke needs at least 2 points" else "Road save failed");
            return;
        };
        defer state.allocator.free(result.edge_id);
        selectCommittedRoadSegment(state, result.edge_id);
        if (result.removed_points > 0) {
            var buf: [96]u8 = undefined;
            project_editor_state.setStatus(state, std.fmt.bufPrint(&buf, "Road sketch cleaned up: {d} extra point(s) removed", .{result.removed_points}) catch "Road sketch cleaned up");
        }
        clearRoadDraft(state);
        return;
    }

    if (click_count >= 2) {
        _ = appendRoadPoint(state, anchor, 0.001) catch {};
        finishRoadPlacement(state);
        return;
    }

    appendRoadPoint(state, anchor, 0.001) catch {
        project_editor_state.setStatus(state, "Road point too close to previous");
        return;
    };
    setRoadDraftStatus(state);
}

pub fn finishRoadPlacement(state: *ProjectEditorState) void {
    if (state.world_road_points.items.len < 2) {
        var buf: [96]u8 = undefined;
        project_editor_state.setStatus(state, std.fmt.bufPrint(
            &buf,
            "Road needs at least 2 points ({d} placed)",
            .{state.world_road_points.items.len},
        ) catch "Road needs at least 2 points");
        return;
    }
    pushWorldCurveUndoSnapshot(state);
    const result = commitRoadDraft(state) catch {
        project_editor_state.setStatus(state, "Road save failed");
        return;
    };
    defer state.allocator.free(result.edge_id);
    selectCommittedRoadSegment(state, result.edge_id);
    clearRoadDraft(state);
}

const RoadDraftCommit = struct {
    removed_points: usize,
    edge_id: []u8,
};

fn commitRoadDraft(state: *ProjectEditorState) !RoadDraftCommit {
    const removed = if (state.world_road_draw_mode == .freehand)
        try curve_drawing.simplifyInPlace(state.allocator, roadDraft(state), roadFreehandSimplifyTolerance(state))
    else
        0;
    _ = try curve_drawing.finishablePoints(roadDraft(state));
    const edge_id = try project_editor_world_authoring.commitRoadPath(state, state.world_road_points.items);
    return .{ .removed_points = removed, .edge_id = edge_id };
}

fn selectCommittedRoadSegment(state: *ProjectEditorState, edge_id: []const u8) void {
    setRoadMode(state, .select);
    setSelectedRoadEdge(state, edge_id, .none) catch |err| roadActionError(state, err);
}

pub fn deleteSelectedRoadEdge(state: *ProjectEditorState) !void {
    const edge_id = state.selected_road_edge_id orelse return error.NoRoadEdgeSelected;
    pushWorldCurveUndoSnapshot(state);
    var doc = try friendly_engine.modules.splines.authoring.load(
        state.allocator,
        state.io,
        state.project_path,
        try world_manifest_authoring.pathForState(state),
    );
    defer doc.deinit();
    try doc.deleteRoadEdge(edge_id);
    try friendly_engine.modules.splines.authoring.save(doc, state.io, state.project_path, try world_manifest_authoring.pathForState(state));
    clearSelectedRoadEdge(state);
    state.spline_preview_stale = true;
    project_editor_terrain_preview.scheduleBake(state);
    project_editor_state.setStatus(state, "Road line deleted");
}

pub fn splitSelectedRoadEdgeAtScreen(state: *ProjectEditorState, screen_x: f32, screen_y: f32) !void {
    const edge_id = state.selected_road_edge_id orelse return error.NoRoadEdgeSelected;
    pushWorldCurveUndoSnapshot(state);
    var doc = try spline_authoring.load(state.allocator, state.io, state.project_path, try world_manifest_authoring.pathForState(state));
    defer doc.deinit();
    const edge = doc.roadEdgePtrConst(edge_id) orelse return error.MissingRoadEdge;
    const point = roadCurvePointAtScreen(state, &doc, edge, screen_x, screen_y) orelse
        project_editor_blockout.screenToGroundPoint(state, screen_x, screen_y) orelse
        return;
    const new_node_id = try project_editor_ui_world_road_helpers.uniqueRoadNodeId(state.allocator, &doc);
    defer state.allocator.free(new_node_id);
    const new_edge_id = try project_editor_ui_world_road_helpers.uniqueRoadEdgeId(state.allocator, &doc);
    defer state.allocator.free(new_edge_id);
    try doc.splitRoadEdge(edge_id, new_node_id, new_edge_id, point);
    try project_editor_world_authoring.persistRoadGraphDoc(state, doc, "road split", false);
    try setSelectedRoadNode(state, new_node_id);
    project_editor_state.setStatus(state, "Road point added");
}

pub fn straightenSelectedRoadSegment(state: *ProjectEditorState) !void {
    const edge_id = state.selected_road_edge_id orelse return error.NoRoadEdgeSelected;
    pushWorldCurveUndoSnapshot(state);
    var doc = try spline_authoring.load(state.allocator, state.io, state.project_path, try world_manifest_authoring.pathForState(state));
    defer doc.deinit();
    const edge = doc.roadEdgePtrConst(edge_id) orelse return error.MissingRoadEdge;
    const start = project_editor_ui_world_road_helpers.roadNodePosition(&doc, edge.start_node_id) orelse return error.MissingRoadNode;
    const end = project_editor_ui_world_road_helpers.roadNodePosition(&doc, edge.end_node_id) orelse return error.MissingRoadNode;
    try updateRoadEdgeHandlesPreservingSettings(state, &doc, edge, project_editor_ui_world_road_helpers.lerpVec3(start, end, 1.0 / 3.0), project_editor_ui_world_road_helpers.lerpVec3(start, end, 2.0 / 3.0));
    try project_editor_world_authoring.persistRoadGraphDoc(state, doc, "road straighten", false);
    project_editor_state.setStatus(state, "Road straightened");
}

pub fn softenSelectedRoadSegment(state: *ProjectEditorState) !void {
    const edge_id = state.selected_road_edge_id orelse return error.NoRoadEdgeSelected;
    pushWorldCurveUndoSnapshot(state);
    var doc = try spline_authoring.load(state.allocator, state.io, state.project_path, try world_manifest_authoring.pathForState(state));
    defer doc.deinit();
    const edge = doc.roadEdgePtrConst(edge_id) orelse return error.MissingRoadEdge;
    const start = project_editor_ui_world_road_helpers.roadNodePosition(&doc, edge.start_node_id) orelse return error.MissingRoadNode;
    const end = project_editor_ui_world_road_helpers.roadNodePosition(&doc, edge.end_node_id) orelse return error.MissingRoadNode;
    const dx = end.x - start.x;
    const dz = end.z - start.z;
    const length = @sqrt(dx * dx + dz * dz);
    const bow = @min(8.0, length * 0.12);
    const inv_len = if (length <= 0.001) 0 else 1.0 / length;
    const normal = editor_math.Vec3{ .x = -dz * inv_len, .y = 0, .z = dx * inv_len };
    try updateRoadEdgeHandlesPreservingSettings(
        state,
        &doc,
        edge,
        editor_math.Vec3.add(project_editor_ui_world_road_helpers.lerpVec3(start, end, 1.0 / 3.0), editor_math.Vec3.scale(normal, bow)),
        editor_math.Vec3.add(project_editor_ui_world_road_helpers.lerpVec3(start, end, 2.0 / 3.0), editor_math.Vec3.scale(normal, bow)),
    );
    try project_editor_world_authoring.persistRoadGraphDoc(state, doc, "road soften", false);
    project_editor_state.setStatus(state, "Road softened");
}

fn updateRoadEdgeHandlesPreservingSettings(
    state: *ProjectEditorState,
    doc: *spline_authoring.SplinesAuthoringDoc,
    edge: *const spline_authoring.OwnedRoadEdge,
    handle_start: editor_math.Vec3,
    handle_end: editor_math.Vec3,
) !void {
    const start_id = try state.allocator.dupe(u8, edge.start_node_id);
    defer state.allocator.free(start_id);
    const end_id = try state.allocator.dupe(u8, edge.end_node_id);
    defer state.allocator.free(end_id);
    const decal = try state.allocator.dupe(u8, edge.decal_material);
    defer state.allocator.free(decal);
    const prop = try state.allocator.dupe(u8, edge.prop_asset_id);
    defer state.allocator.free(prop);
    try doc.updateRoadEdge(.{
        .id = edge.id,
        .start_node_id = start_id,
        .end_node_id = end_id,
        .handle_start = handle_start,
        .handle_end = handle_end,
        .width = edge.width,
        .elevation = edge.elevation,
        .material_mask_value = edge.material_mask_value,
        .render_mode = edge.render_mode,
        .terrain_mode = edge.terrain_mode,
        .decal_material = decal,
        .prop_asset_id = prop,
    });
}

fn applySelectedRoadSurfaceSettings(state: *ProjectEditorState) !void {
    const edge_id = state.selected_road_edge_id orelse return;
    pushWorldCurveUndoSnapshot(state);
    var doc = try spline_authoring.load(state.allocator, state.io, state.project_path, try world_manifest_authoring.pathForState(state));
    defer doc.deinit();
    const edge = doc.roadEdgePtrConst(edge_id) orelse return error.MissingRoadEdge;
    try updateRoadEdgeSurfaceFromState(state, &doc, edge);
    try project_editor_world_authoring.persistRoadGraphDoc(state, doc, "road surface", false);
    project_editor_state.setStatus(state, "Road surface updated");
}

fn updateRoadEdgeSurfaceFromState(
    state: *ProjectEditorState,
    doc: *spline_authoring.SplinesAuthoringDoc,
    edge: *const spline_authoring.OwnedRoadEdge,
) !void {
    const start_id = try state.allocator.dupe(u8, edge.start_node_id);
    defer state.allocator.free(start_id);
    const end_id = try state.allocator.dupe(u8, edge.end_node_id);
    defer state.allocator.free(end_id);
    const decal = try state.allocator.dupe(u8, roadDecalMaterialForState(state));
    defer state.allocator.free(decal);
    const prop = try state.allocator.dupe(u8, roadPropAssetForState(state));
    defer state.allocator.free(prop);
    try doc.updateRoadEdge(roadEdgeInputWithSurface(state, edge, start_id, end_id, decal, prop));
}

fn roadEdgeInputWithSurface(
    state: *const ProjectEditorState,
    edge: *const spline_authoring.OwnedRoadEdge,
    start_id: []const u8,
    end_id: []const u8,
    decal_material: []const u8,
    prop_asset_id: []const u8,
) spline_authoring.RoadEdgeInput {
    return .{
        .id = edge.id,
        .start_node_id = start_id,
        .end_node_id = end_id,
        .handle_start = edge.handle_start,
        .handle_end = edge.handle_end,
        .width = @max(0.5, state.world_road_width),
        .elevation = state.world_road_conform_offset,
        .material_mask_value = edge.material_mask_value,
        .render_mode = roadRenderModeForState(state),
        .terrain_mode = roadTerrainModeForState(state),
        .decal_material = decal_material,
        .prop_asset_id = prop_asset_id,
    };
}

fn roadRenderModeForState(state: *const ProjectEditorState) spline_authoring.RoadRenderMode {
    return switch (state.world_road_surface_mode) {
        .decal => .decal,
        .prop_sections => .prop_sections,
    };
}

fn roadTerrainModeForState(state: *const ProjectEditorState) spline_authoring.RoadTerrainMode {
    return switch (state.world_road_terrain_mode) {
        .conform => .conform,
        .floating => .floating,
        .tunnel_reserved => .tunnel_reserved,
    };
}

fn roadDecalMaterialForState(state: *const ProjectEditorState) []const u8 {
    _ = state;
    return "road.dirt";
}

fn roadPropAssetForState(state: *const ProjectEditorState) []const u8 {
    return if (state.world_road_surface_mode == .prop_sections) "road_section_straight" else "";
}

pub fn deleteSelectedRoadJunction(state: *ProjectEditorState) !void {
    const node_id = state.selected_road_node_id orelse return error.NoRoadNodeSelected;
    pushWorldCurveUndoSnapshot(state);
    var doc = try friendly_engine.modules.splines.authoring.load(
        state.allocator,
        state.io,
        state.project_path,
        try world_manifest_authoring.pathForState(state),
    );
    defer doc.deinit();
    try doc.deleteRoadNode(node_id);
    try friendly_engine.modules.splines.authoring.save(doc, state.io, state.project_path, try world_manifest_authoring.pathForState(state));
    clearSelectedRoadNode(state);
    state.spline_preview_stale = true;
    project_editor_terrain_preview.scheduleBake(state);
    project_editor_state.setStatus(state, "Road junction deleted");
}

pub fn regenerateSelectedRoad(state: *ProjectEditorState) !void {
    if (state.selected_road_edge_id == null and state.selected_road_node_id == null) return error.NoRoadEdgeSelected;
    state.spline_preview_stale = true;
    project_editor_terrain_preview.scheduleBake(state);
    project_editor_state.setStatus(state, "Selected road queued for rebuild");
}

pub fn regenerateAllRoads(state: *ProjectEditorState) !void {
    state.spline_preview_stale = true;
    project_editor_terrain_preview.scheduleBake(state);
    project_editor_state.setStatus(state, "All roads queued for rebuild");
}

fn clearSelectedRoadEdge(state: *ProjectEditorState) void {
    if (state.selected_road_edge_id) |id| state.allocator.free(id);
    state.selected_road_edge_id = null;
    state.selected_road_handle = .none;
    if (state.selected_road_node_id == null) state.selected_world_curve_hit = .{};
}

fn clearSelectedRoadNode(state: *ProjectEditorState) void {
    if (state.selected_road_node_id) |id| state.allocator.free(id);
    state.selected_road_node_id = null;
    if (state.selected_road_edge_id == null) state.selected_world_curve_hit = .{};
}

fn clearRoadSelection(state: *ProjectEditorState) void {
    clearSelectedRoadEdge(state);
    clearSelectedRoadNode(state);
    state.selected_world_curve_hit = .{};
}

fn appendRoadPoint(state: *ProjectEditorState, point: editor_math.Vec3, min_spacing: f32) !void {
    curve_drawing.addPoint(state.allocator, roadDraft(state), point, min_spacing) catch |err| switch (err) {
        error.PointTooClose => return error.InvalidRoadSegment,
        else => return err,
    };
}

fn setRoadDraftStatus(state: *ProjectEditorState) void {
    var buf: [128]u8 = undefined;
    project_editor_state.setStatus(state, std.fmt.bufPrint(
        &buf,
        "Road: {d} point(s) — click to add, Enter or double-click to finish",
        .{state.world_road_points.items.len},
    ) catch "Road point added");
}

fn clearRoadDraft(state: *ProjectEditorState) void {
    curve_drawing.clear(roadDraft(state));
}

fn clearRoadDragSession(state: *ProjectEditorState) void {
    state.world_road_drag_anchor = null;
    state.world_road_preview_end = null;
}

pub fn roadViewportWantsPointer(state: *ProjectEditorState, screen_x: f32, screen_y: f32) bool {
    if (state.world_road_mode == .draw) return true;
    const hit = hitRoadGraphAtScreen(state, screen_x, screen_y) orelse return true;
    state.allocator.free(hit.id);
    return true;
}

pub fn clearWorldCurveHover(state: *ProjectEditorState) void {
    state.hovered_world_curve_hit = .{};
}

pub fn clearWorldCurveSelection(state: *ProjectEditorState) bool {
    const had_selection = !state.selected_world_curve_hit.isNone() or
        state.selected_road_edge_id != null or
        state.selected_road_node_id != null or
        state.selected_ocean_clip_point != null;
    if (!had_selection) return false;
    clearRoadSelection(state);
    state.selected_ocean_clip_point = null;
    state.selected_world_curve_hit = .{};
    return true;
}

pub fn updateWorldCurveHover(state: *ProjectEditorState, screen_x: f32, screen_y: f32) void {
    clearWorldCurveHover(state);
    if (state.mode != .world_creation) return;
    switch (state.world_tool) {
        .roads => {
            const hit = hitRoadGraphAtScreen(state, screen_x, screen_y) orelse return;
            defer state.allocator.free(hit.id);
            state.hovered_world_curve_hit = project_editor_ui_world_road_helpers.roadHitToWorldCurveHit(hit);
        },
        .ocean => {
            if (project_editor_ui_world_ocean_clip.hitAtScreen(state, screen_x, screen_y)) |hit| state.hovered_world_curve_hit = hit;
        },
        .water => {
            if (project_editor_ui_world_water.hitAtScreen(state, screen_x, screen_y)) |hit| state.hovered_world_curve_hit = hit;
        },
        .scatter => {
            if (project_editor_ui_world_scatter_zone.hitAtScreen(state, screen_x, screen_y)) |hit| state.hovered_world_curve_hit = hit;
        },
        else => {},
    }
}

pub const WorldCurveInteractionBegin = enum {
    none,
    handled,
    drag,
};

fn resolveRoadSelectionIndex(
    state: *ProjectEditorState,
    element: project_editor_types.WorldCurveHitElement,
    id: []const u8,
) ?usize {
    var doc = spline_authoring.load(state.allocator, state.io, state.project_path, world_manifest_authoring.pathForState(state) catch return null) catch return null;
    defer doc.deinit();
    return switch (element) {
        .point => doc.nodeIndexById(id),
        .segment, .handle_start, .handle_end => project_editor_ui_world_road_helpers.roadEdgeIndexById(&doc, id),
        else => null,
    };
}

pub fn beginWaterVolumeInteraction(state: *ProjectEditorState, screen_x: f32, screen_y: f32, click_count: u8) WorldCurveInteractionBegin {
    return switch (project_editor_ui_world_water.beginInteraction(state, screen_x, screen_y, click_count)) {
        .none => .none,
        .handled => .handled,
        .drag => .drag,
    };
}

fn selectRoadGraphAtScreen(state: *ProjectEditorState, screen_x: f32, screen_y: f32) bool {
    const hit = hitRoadGraphAtScreen(state, screen_x, screen_y) orelse return false;
    defer state.allocator.free(hit.id);
    switch (hit.kind) {
        .node => {
            setSelectedRoadNode(state, hit.id) catch {
                project_editor_state.setStatus(state, "Road point selection failed");
                return true;
            };
            if (state.world_road_mode == .join) promoteSelectedRoadNode(state) catch |err| roadActionError(state, err);
        },
        .edge => setSelectedRoadEdge(state, hit.id, .none) catch {
            project_editor_state.setStatus(state, "Road selection failed");
            return true;
        },
        .handle_start => setSelectedRoadEdge(state, hit.id, .start) catch {
            project_editor_state.setStatus(state, "Road handle selection failed");
            return true;
        },
        .handle_end => setSelectedRoadEdge(state, hit.id, .end) catch {
            project_editor_state.setStatus(state, "Road handle selection failed");
            return true;
        },
    }
    project_editor_ui_world_road_helpers.applyRoadHitIndexToSelectedCurveHit(state, hit);
    state.world_road_drag_anchor = project_editor_blockout.screenToGroundPoint(state, screen_x, screen_y);
    return true;
}

fn hitRoadGraphAtScreen(state: *ProjectEditorState, screen_x: f32, screen_y: f32) ?RoadHit {
    var doc = spline_authoring.load(state.allocator, state.io, state.project_path, world_manifest_authoring.pathForState(state) catch return null) catch return null;
    defer doc.deinit();
    const local_x = screen_x - state.viewport_screen_rect.x;
    const local_y = screen_y - state.viewport_screen_rect.y;
    const vp_w = state.viewport_screen_rect.w;
    const vp_h = state.viewport_screen_rect.h;
    const node_radius_px: f32 = 10.0;
    const handle_radius_px: f32 = 8.0;
    const edge_radius_px: f32 = 7.0;

    var best_hit: ?RoadHit = null;
    var best_distance = node_radius_px * node_radius_px;
    for (doc.road_nodes.items, 0..) |node, node_index| {
        const screen = project_editor_state.projectViewportPoint(state, node.position, vp_w, vp_h) orelse continue;
        const dist = project_editor_ui_world_road_helpers.distanceSq(local_x, local_y, screen.x, screen.y);
        if (dist <= best_distance) {
            best_distance = dist;
            replaceRoadHit(state, &best_hit, .node, node.id, node_index) catch return best_hit;
        }
    }
    if (best_hit != null) return best_hit;

    best_distance = handle_radius_px * handle_radius_px;
    for (doc.road_edges.items, 0..) |edge, edge_index| {
        if (roadHandleHit(state, edge.id, edge.handle_start, local_x, local_y, vp_w, vp_h, &best_distance)) {
            replaceRoadHit(state, &best_hit, .handle_start, edge.id, edge_index) catch return best_hit;
        }
        if (roadHandleHit(state, edge.id, edge.handle_end, local_x, local_y, vp_w, vp_h, &best_distance)) {
            replaceRoadHit(state, &best_hit, .handle_end, edge.id, edge_index) catch return best_hit;
        }
    }
    if (best_hit != null) return best_hit;

    best_distance = edge_radius_px * edge_radius_px;
    for (doc.road_edges.items, 0..) |edge, edge_index| {
        const start = project_editor_ui_world_road_helpers.roadNodePosition(&doc, edge.start_node_id) orelse continue;
        const end = project_editor_ui_world_road_helpers.roadNodePosition(&doc, edge.end_node_id) orelse continue;
        var prev = project_editor_state.projectViewportPoint(state, start, vp_w, vp_h) orelse continue;
        var sample_index: usize = 1;
        while (sample_index <= 16) : (sample_index += 1) {
            const t = @as(f32, @floatFromInt(sample_index)) / 16.0;
            const world_pt = project_editor_ui_world_road_helpers.sampleRoadCurve(start, edge.handle_start, edge.handle_end, end, t);
            const next = project_editor_state.projectViewportPoint(state, world_pt, vp_w, vp_h) orelse continue;
            const dist = distancePointSegmentSq(local_x, local_y, prev.x, prev.y, next.x, next.y);
            if (dist <= best_distance) {
                best_distance = dist;
                replaceRoadHit(state, &best_hit, .edge, edge.id, edge_index) catch return best_hit;
            }
            prev = next;
        }
    }
    return best_hit;
}

fn snappedRoadPointAtScreen(state: *ProjectEditorState, screen_x: f32, screen_y: f32) ?editor_math.Vec3 {
    if (state.world_tool != .roads or state.world_road_mode != .draw) return null;
    const snap = roadSnapTargetAtScreen(state, screen_x, screen_y, null) orelse return null;
    defer state.allocator.free(snap.id);
    return snap.point;
}

fn roadSnapTargetAtScreen(
    state: *ProjectEditorState,
    screen_x: f32,
    screen_y: f32,
    exclude_node_id: ?[]const u8,
) ?RoadSnapTarget {
    var doc = spline_authoring.load(state.allocator, state.io, state.project_path, world_manifest_authoring.pathForState(state) catch return null) catch return null;
    defer doc.deinit();
    const local_x = screen_x - state.viewport_screen_rect.x;
    const local_y = screen_y - state.viewport_screen_rect.y;
    const vp_w = state.viewport_screen_rect.w;
    const vp_h = state.viewport_screen_rect.h;
    const radius_sq: f32 = 14.0 * 14.0;
    var best_distance = radius_sq;
    var best: ?RoadSnapTarget = null;

    for (doc.road_nodes.items) |node| {
        if (exclude_node_id) |exclude| {
            if (std.mem.eql(u8, exclude, node.id)) continue;
        }
        const screen = project_editor_state.projectViewportPoint(state, node.position, vp_w, vp_h) orelse continue;
        const dist = project_editor_ui_world_road_helpers.distanceSq(local_x, local_y, screen.x, screen.y);
        if (dist <= best_distance) {
            best_distance = dist;
            replaceRoadSnap(state, &best, .node, node.id, node.position, dist) catch return best;
        }
    }
    if (best != null) return best;

    for (doc.road_edges.items) |edge| {
        if (exclude_node_id) |exclude| {
            if (std.mem.eql(u8, exclude, edge.start_node_id) or std.mem.eql(u8, exclude, edge.end_node_id)) continue;
        }
        const start = project_editor_ui_world_road_helpers.roadNodePosition(&doc, edge.start_node_id) orelse continue;
        const end = project_editor_ui_world_road_helpers.roadNodePosition(&doc, edge.end_node_id) orelse continue;
        var prev_world = start;
        var prev_screen = project_editor_state.projectViewportPoint(state, start, vp_w, vp_h) orelse continue;
        var sample_index: usize = 1;
        while (sample_index <= 24) : (sample_index += 1) {
            const t = @as(f32, @floatFromInt(sample_index)) / 24.0;
            const world_pt = project_editor_ui_world_road_helpers.sampleRoadCurve(start, edge.handle_start, edge.handle_end, end, t);
            const next_screen = project_editor_state.projectViewportPoint(state, world_pt, vp_w, vp_h) orelse continue;
            const seg_dist = distancePointSegmentSq(local_x, local_y, prev_screen.x, prev_screen.y, next_screen.x, next_screen.y);
            if (seg_dist <= best_distance) {
                best_distance = seg_dist;
                replaceRoadSnap(
                    state,
                    &best,
                    .edge,
                    edge.id,
                    project_editor_ui_world_road_helpers.nearestPointOnWorldSegment(local_x, local_y, prev_screen, next_screen, prev_world, world_pt),
                    seg_dist,
                ) catch return best;
            }
            prev_world = world_pt;
            prev_screen = next_screen;
        }
    }
    return best;
}

fn replaceRoadSnap(
    state: *ProjectEditorState,
    snap: *?RoadSnapTarget,
    kind: RoadSnapKind,
    id: []const u8,
    point: editor_math.Vec3,
    distance_sq: f32,
) !void {
    if (snap.*) |existing| state.allocator.free(existing.id);
    snap.* = .{
        .kind = kind,
        .id = try state.allocator.dupe(u8, id),
        .point = point,
        .distance_sq = distance_sq,
    };
}

fn roadCurvePointAtScreen(
    state: *ProjectEditorState,
    doc: *const spline_authoring.SplinesAuthoringDoc,
    edge: *const spline_authoring.OwnedRoadEdge,
    screen_x: f32,
    screen_y: f32,
) ?editor_math.Vec3 {
    const start = project_editor_ui_world_road_helpers.roadNodePosition(doc, edge.start_node_id) orelse return null;
    const end = project_editor_ui_world_road_helpers.roadNodePosition(doc, edge.end_node_id) orelse return null;
    const local_x = screen_x - state.viewport_screen_rect.x;
    const local_y = screen_y - state.viewport_screen_rect.y;
    const vp_w = state.viewport_screen_rect.w;
    const vp_h = state.viewport_screen_rect.h;
    var best_point: ?editor_math.Vec3 = null;
    var best_distance = std.math.inf(f32);
    var prev_world = start;
    var prev_screen = project_editor_state.projectViewportPoint(state, start, vp_w, vp_h) orelse return null;
    var sample_index: usize = 1;
    while (sample_index <= 32) : (sample_index += 1) {
        const t = @as(f32, @floatFromInt(sample_index)) / 32.0;
        const world_pt = project_editor_ui_world_road_helpers.sampleRoadCurve(start, edge.handle_start, edge.handle_end, end, t);
        const next_screen = project_editor_state.projectViewportPoint(state, world_pt, vp_w, vp_h) orelse continue;
        const dist = distancePointSegmentSq(local_x, local_y, prev_screen.x, prev_screen.y, next_screen.x, next_screen.y);
        if (dist <= best_distance) {
            best_distance = dist;
            best_point = project_editor_ui_world_road_helpers.nearestPointOnWorldSegment(local_x, local_y, prev_screen, next_screen, prev_world, world_pt);
        }
        prev_world = world_pt;
        prev_screen = next_screen;
    }
    return best_point;
}

fn replaceRoadHit(state: *ProjectEditorState, hit: *?RoadHit, kind: RoadHitKind, id: []const u8, index: usize) !void {
    if (hit.*) |existing| state.allocator.free(existing.id);
    hit.* = .{ .kind = kind, .id = try state.allocator.dupe(u8, id), .index = index };
}

fn roadHandleHit(
    state: *ProjectEditorState,
    edge_id: []const u8,
    point: friendly_engine.core.math.Vec3f,
    screen_x: f32,
    screen_y: f32,
    vp_w: f32,
    vp_h: f32,
    best_distance: *f32,
) bool {
    _ = edge_id;
    const screen = project_editor_state.projectViewportPoint(state, point, vp_w, vp_h) orelse return false;
    const dist = project_editor_ui_world_road_helpers.distanceSq(screen_x, screen_y, screen.x, screen.y);
    if (dist > best_distance.*) return false;
    best_distance.* = dist;
    return true;
}

fn moveSelectedRoadGraphItem(state: *ProjectEditorState, screen_x: f32, screen_y: f32) !void {
    if (state.world_road_mode == .surface) return;
    const point = project_editor_blockout.screenToGroundPoint(state, screen_x, screen_y) orelse return;
    var doc = try spline_authoring.load(state.allocator, state.io, state.project_path, try world_manifest_authoring.pathForState(state));
    defer doc.deinit();

    if (state.selected_road_edge_id) |edge_id| {
        if (state.world_road_mode != .shape or state.selected_road_handle == .none) return;
        const edge = doc.roadEdgePtrConst(edge_id) orelse return error.NoRoadEdgeSelected;
        const start_id = try state.allocator.dupe(u8, edge.start_node_id);
        defer state.allocator.free(start_id);
        const end_id = try state.allocator.dupe(u8, edge.end_node_id);
        defer state.allocator.free(end_id);
        const decal = try state.allocator.dupe(u8, edge.decal_material);
        defer state.allocator.free(decal);
        const prop = try state.allocator.dupe(u8, edge.prop_asset_id);
        defer state.allocator.free(prop);
        pushWorldCurveUndoSnapshot(state);
        try doc.updateRoadEdge(.{
            .id = edge.id,
            .start_node_id = start_id,
            .end_node_id = end_id,
            .handle_start = if (state.selected_road_handle == .start) point else edge.handle_start,
            .handle_end = if (state.selected_road_handle == .end) point else edge.handle_end,
            .width = edge.width,
            .elevation = edge.elevation,
            .material_mask_value = edge.material_mask_value,
            .render_mode = edge.render_mode,
            .terrain_mode = edge.terrain_mode,
            .decal_material = decal,
            .prop_asset_id = prop,
        });
        try project_editor_world_authoring.persistRoadGraphDoc(state, doc, "road handle", false);
        project_editor_state.setStatus(state, "Road handle moved");
        return;
    }

    const node_id = state.selected_road_node_id orelse return;
    if (state.world_road_mode != .shape and state.world_road_mode != .join and state.world_road_mode != .select) return;
    pushWorldCurveUndoSnapshot(state);
    try doc.moveRoadNode(node_id, point);
    try project_editor_world_authoring.persistRoadGraphDoc(state, doc, "road node", false);
    project_editor_state.setStatus(state, "Road point moved");
}

fn promoteSelectedRoadNode(state: *ProjectEditorState) !void {
    const node_id = state.selected_road_node_id orelse return error.NoRoadNodeSelected;
    pushWorldCurveUndoSnapshot(state);
    var doc = try spline_authoring.load(state.allocator, state.io, state.project_path, try world_manifest_authoring.pathForState(state));
    defer doc.deinit();
    try doc.promoteRoadNode(node_id);
    try project_editor_world_authoring.persistRoadGraphDoc(state, doc, "road join", false);
    project_editor_state.setStatus(state, "Road point is a junction");
}

fn mergeSelectedRoadNodeAtScreen(state: *ProjectEditorState, screen_x: f32, screen_y: f32) !void {
    const keep_id = state.selected_road_node_id orelse return error.NoRoadNodeSelected;
    const snap = roadSnapTargetAtScreen(state, screen_x, screen_y, keep_id) orelse return;
    defer state.allocator.free(snap.id);
    pushWorldCurveUndoSnapshot(state);
    var doc = try spline_authoring.load(state.allocator, state.io, state.project_path, try world_manifest_authoring.pathForState(state));
    defer doc.deinit();
    switch (snap.kind) {
        .node => {
            if (std.mem.eql(u8, keep_id, snap.id)) return;
            try doc.mergeRoadNodes(snap.id, keep_id);
            try project_editor_world_authoring.persistRoadGraphDoc(state, doc, "road join merge", false);
            try setSelectedRoadNode(state, snap.id);
            project_editor_state.setStatus(state, "Road points joined");
        },
        .edge => {
            const split_node_id = try project_editor_ui_world_road_helpers.uniqueRoadNodeId(state.allocator, &doc);
            defer state.allocator.free(split_node_id);
            const split_edge_id = try project_editor_ui_world_road_helpers.uniqueRoadEdgeId(state.allocator, &doc);
            defer state.allocator.free(split_edge_id);
            try doc.splitRoadEdge(snap.id, split_node_id, split_edge_id, snap.point);
            try doc.mergeRoadNodes(split_node_id, keep_id);
            try project_editor_world_authoring.persistRoadGraphDoc(state, doc, "road join split", false);
            try setSelectedRoadNode(state, split_node_id);
            project_editor_state.setStatus(state, "Road joined into line");
        },
    }
}

fn setSelectedRoadNode(state: *ProjectEditorState, node_id: []const u8) !void {
    clearSelectedRoadEdge(state);
    clearSelectedRoadNode(state);
    state.selected_road_node_id = try state.allocator.dupe(u8, node_id);
    state.selected_world_curve_hit = .{
        .target = .road,
        .element = .point,
        .index = resolveRoadSelectionIndex(state, .point, node_id) orelse 0,
    };
    project_editor_state.setStatus(state, modeHint(state));
}

fn setSelectedRoadEdge(state: *ProjectEditorState, edge_id: []const u8, handle: @TypeOf(state.selected_road_handle)) !void {
    clearSelectedRoadNode(state);
    clearSelectedRoadEdge(state);
    state.selected_road_edge_id = try state.allocator.dupe(u8, edge_id);
    state.selected_road_handle = handle;
    syncRoadSurfaceStateFromEdge(state, edge_id) catch {};
    const element: project_editor_types.WorldCurveHitElement = switch (handle) {
        .none => .segment,
        .start => .handle_start,
        .end => .handle_end,
    };
    state.selected_world_curve_hit = .{
        .target = .road,
        .element = element,
        .index = resolveRoadSelectionIndex(state, element, edge_id) orelse 0,
    };
    project_editor_state.setStatus(state, modeHint(state));
}

fn syncRoadSurfaceStateFromEdge(state: *ProjectEditorState, edge_id: []const u8) !void {
    var doc = try spline_authoring.load(state.allocator, state.io, state.project_path, try world_manifest_authoring.pathForState(state));
    defer doc.deinit();
    const edge = doc.roadEdgePtrConst(edge_id) orelse return error.MissingRoadEdge;
    state.world_road_width = edge.width;
    state.world_road_conform_offset = edge.elevation;
    state.world_road_surface_mode = switch (edge.render_mode) {
        .decal => .decal,
        .prop_sections => .prop_sections,
    };
    state.world_road_terrain_mode = switch (edge.terrain_mode) {
        .conform => .conform,
        .floating => .floating,
        .tunnel_reserved => .tunnel_reserved,
    };
}

pub fn clearRoadPlacement(state: *ProjectEditorState) void {
    clearRoadDraft(state);
    clearRoadDragSession(state);
}

fn roadDraft(state: *ProjectEditorState) curve_drawing.Draft {
    return .{ .points = &state.world_road_points, .preview_end = &state.world_road_preview_end };
}

fn roadFreehandSpacing(state: *const ProjectEditorState) f32 {
    return std.math.clamp(state.world_road_width * 0.35, 0.5, 4.0);
}

fn roadFreehandSimplifyTolerance(state: *const ProjectEditorState) f32 {
    return std.math.clamp(state.world_road_width * 0.18, 0.25, 2.0);
}

pub fn handleViewportScatterDensityDrag(state: *ProjectEditorState, screen_x: f32, screen_y: f32) void {
    if (state.world_tool != .scatter or state.selected_world_layer != .scatter_density_mask) return;
    const pt = project_editor_blockout.screenToGroundPoint(state, screen_x, screen_y) orelse return;
    pushWorldCurveUndoSnapshot(state);
    paintScatterDensityAt(state, pt) catch |err| {
        const message: []const u8 = switch (err) {
            error.WorldCellNotInManifest => "Scatter density paint failed: no cell here — use Create Cell",
            else => "Scatter density paint failed",
        };
        project_editor_state.setStatus(state, message);
    };
}

pub fn beginScatterDensityPaint(state: *ProjectEditorState) void {
    beginWorldCurveUndoBatch(state);
}

pub fn finishScatterDensityPaint(state: *ProjectEditorState) void {
    endWorldCurveUndoBatch(state);
}

pub fn cancelScatterDensityPaint(state: *ProjectEditorState) void {
    rollbackWorldCurveUndoBatch(state);
}

pub fn handleViewportPaintDrag(state: *ProjectEditorState, screen_x: f32, screen_y: f32) void {
    if (state.world_tool != .terrain and state.world_tool != .paint) return;
    const pt = project_editor_blockout.screenToGroundPoint(state, screen_x, screen_y) orelse return;
    if (state.world_region_paint_enabled) {
        paintRegionMembershipAt(state, pt) catch |err| {
            const message: []const u8 = switch (err) {
                error.WorldCellNotInManifest => "Area paint failed: no cell here",
                error.WorldRegionNotSelected => "Area paint failed: select an area first",
                else => "Area paint failed",
            };
            project_editor_state.setStatus(state, message);
        };
        return;
    }
    paintTerrainAt(state, pt) catch |err| {
        const message: []const u8 = switch (err) {
            error.WorldCellNotInManifest => "Terrain paint failed: no cell here — use Create Cell",
            else => "Terrain paint failed",
        };
        project_editor_state.setStatus(state, message);
    };
}

pub fn beginScatterZoneDrag(state: *ProjectEditorState, screen_x: f32, screen_y: f32) void {
    project_editor_ui_world_scatter_zone.beginDrag(state, screen_x, screen_y);
}

pub fn beginScatterZoneInteraction(state: *ProjectEditorState, screen_x: f32, screen_y: f32) bool {
    return project_editor_ui_world_scatter_zone.beginInteraction(state, screen_x, screen_y);
}

pub fn updateScatterZoneDrag(state: *ProjectEditorState, screen_x: f32, screen_y: f32) void {
    project_editor_ui_world_scatter_zone.updateDrag(state, screen_x, screen_y);
}

pub fn finishScatterZoneDrag(state: *ProjectEditorState) void {
    project_editor_ui_world_scatter_zone.finishDrag(state);
}

pub fn cancelScatterZoneDrag(state: *ProjectEditorState) void {
    project_editor_ui_world_scatter_zone.cancelDrag(state);
}

fn applyTerrainAtPoint(state: *ProjectEditorState) !void {
    try paintTerrainAt(state, state.camera.target);
}

fn applyTerrainCellAtPoint(state: *ProjectEditorState) !void {
    try project_editor_world_authoring.createTerrainCellAt(state, state.camera.target);
}

fn paintTerrainAt(state: *ProjectEditorState, point: editor_math.Vec3) !void {
    try project_editor_world_authoring.paintTerrainAt(state, point);
}

pub fn paintRegionMembershipAt(state: *ProjectEditorState, point: editor_math.Vec3) !void {
    try project_editor_ui_world_region_paint.paintAt(state, point);
}

pub fn paintRegionMembershipForRegion(
    state: *ProjectEditorState,
    region_id: []const u8,
    region_name: []const u8,
    point: editor_math.Vec3,
    radius_m: f32,
    mode: world.regions.PaintMode,
) !usize {
    return project_editor_ui_world_region_paint.paintForRegion(state, region_id, region_name, point, radius_m, mode);
}

fn applyRoadThroughCell(state: *ProjectEditorState) !void {
    pushWorldCurveUndoSnapshot(state);
    try project_editor_world_authoring.drawRoadThroughCell(state);
}

fn applyScatterAtPoint(state: *ProjectEditorState) !void {
    pushWorldCurveUndoSnapshot(state);
    if (state.selected_world_layer == .scatter_density_mask) {
        try paintScatterDensityAt(state, state.camera.target);
        return;
    }
    try project_editor_world_authoring.seedScatterAt(state, state.camera.target);
}

fn paintScatterDensityAt(state: *ProjectEditorState, point: editor_math.Vec3) !void {
    try project_editor_world_authoring.paintDensityMaskAt(state, point);
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

fn drawRoadSplineHandles(state: *ProjectEditorState, vp_w: f32, vp_h: f32) void {
    const line_color: shared_color.Color = .{ .r = 240, .g = 190, .b = 90, .a = 230 };
    const handle_color: shared_color.Color = .{ .r = 255, .g = 220, .b = 120, .a = 255 };
    const draft_color: shared_color.Color = .{ .r = 255, .g = 160, .b = 70, .a = 200 };
    const drew_graph = drawCommittedRoadGraph(state, vp_w, vp_h);
    if (state.world_road_mode == .draw) {
        if (roadSnapTargetAtScreen(state, state.mouse_x, state.mouse_y, null)) |snap| {
            defer state.allocator.free(snap.id);
            drawRoadSnapMarker(state, vp_w, vp_h, snap.point, snap.kind);
        }
    } else if (state.world_road_mode == .join) {
        if (state.selected_road_node_id) |selected_id| {
            if (roadSnapTargetAtScreen(state, state.mouse_x, state.mouse_y, selected_id)) |snap| {
                defer state.allocator.free(snap.id);
                drawRoadJoinPreview(state, vp_w, vp_h, selected_id, snap);
                drawRoadSnapMarker(state, vp_w, vp_h, snap.point, snap.kind);
            }
        }
    }

    if (state.world_road_points.items.len > 0) {
        var index: usize = 0;
        while (index + 1 < state.world_road_points.items.len) : (index += 1) {
            drawRoadDraftWidthRails(
                state,
                vp_w,
                vp_h,
                state.world_road_points.items[index],
                state.world_road_points.items[index + 1],
            );
            drawRoadHandleLine(
                state,
                vp_w,
                vp_h,
                state.world_road_points.items[index],
                state.world_road_points.items[index + 1],
                draft_color,
                handle_color,
            );
        }
        const last = state.world_road_points.items[state.world_road_points.items.len - 1];
        const preview = state.world_road_preview_end orelse last;
        if (preview.x != last.x or preview.y != last.y or preview.z != last.z) {
            drawRoadDraftWidthRails(state, vp_w, vp_h, last, preview);
            drawRoadHandleLine(state, vp_w, vp_h, last, preview, draft_color, handle_color);
        }
        for (state.world_road_points.items) |point| {
            drawRoadHandle(state, vp_w, vp_h, point, handle_color);
        }
    } else if (state.world_road_drag_anchor) |anchor| {
        drawRoadDraftWidthRails(state, vp_w, vp_h, anchor, state.world_road_preview_end orelse anchor);
        drawRoadHandleLine(state, vp_w, vp_h, anchor, state.world_road_preview_end orelse anchor, draft_color, handle_color);
    } else if (!drew_graph) {
        const chunk = project_editor_ui_world_readouts.chunkCoords(state);
        const cell_size_m = state.world_cell_size_m;
        const hint_start = editor_math.Vec3{
            .x = chunk.x * cell_size_m + 4,
            .y = state.camera.target.y,
            .z = chunk.y * cell_size_m + (cell_size_m * 0.5),
        };
        const hint_end = editor_math.Vec3{
            .x = (chunk.x + 1) * cell_size_m - 4,
            .y = state.camera.target.y,
            .z = chunk.y * cell_size_m + (cell_size_m * 0.5),
        };
        drawRoadHandleLine(state, vp_w, vp_h, hint_start, hint_end, line_color, handle_color);
    }
}

fn drawRoadDraftWidthRails(
    state: *ProjectEditorState,
    vp_w: f32,
    vp_h: f32,
    start: editor_math.Vec3,
    end: editor_math.Vec3,
) void {
    var style = world_curve_gizmos.defaultStyle();
    style.width_rail_color = .{ .r = 255, .g = 160, .b = 70, .a = 105 };
    world_curve_gizmos.drawWidthRails(state, vp_w, vp_h, start, end, @max(0.5, state.world_road_width), style);
}

fn drawRoadJoinPreview(
    state: *ProjectEditorState,
    vp_w: f32,
    vp_h: f32,
    selected_node_id: []const u8,
    snap: RoadSnapTarget,
) void {
    const start = selectedRoadNodePosition(state, selected_node_id) orelse return;
    const start_screen = project_editor_state.projectViewportPoint(state, start, vp_w, vp_h) orelse return;
    const end_screen = project_editor_state.projectViewportPoint(state, snap.point, vp_w, vp_h) orelse return;
    const color = project_editor_ui_world_road_helpers.roadJoinPreviewColor(snap.kind);
    project_editor_viewport.drawViewportLine(state, start_screen.x, start_screen.y, end_screen.x, end_screen.y, color);
    project_editor_viewport.drawViewportSquare(state, start_screen.x, start_screen.y, 7, color);
}

fn selectedRoadNodePosition(state: *ProjectEditorState, node_id: []const u8) ?editor_math.Vec3 {
    var doc = spline_authoring.load(state.allocator, state.io, state.project_path, world_manifest_authoring.pathForState(state) catch return null) catch return null;
    defer doc.deinit();
    return project_editor_ui_world_road_helpers.roadNodePosition(&doc, node_id);
}

fn drawRoadCurveWidthRails(
    state: *ProjectEditorState,
    vp_w: f32,
    vp_h: f32,
    start: editor_math.Vec3,
    handle_start: editor_math.Vec3,
    handle_end: editor_math.Vec3,
    end: editor_math.Vec3,
    width_m: f32,
    style: world_curve_gizmos.WorldCurveStyle,
) void {
    if (width_m <= 0) return;
    var previous = start;
    var sample_index: usize = 1;
    while (sample_index <= project_editor_ui_world_road_helpers.road_width_rail_samples) : (sample_index += 1) {
        const t = project_editor_ui_world_road_helpers.roadWidthRailSampleT(sample_index);
        const point = project_editor_ui_world_road_helpers.sampleRoadCurve(start, handle_start, handle_end, end, t);
        world_curve_gizmos.drawWidthRails(state, vp_w, vp_h, previous, point, width_m, style);
        previous = point;
    }
}

fn drawCommittedRoadGraph(state: *ProjectEditorState, vp_w: f32, vp_h: f32) bool {
    var doc = spline_authoring.load(state.allocator, state.io, state.project_path, world_manifest_authoring.pathForState(state) catch return false) catch return false;
    defer doc.deinit();
    if (doc.road_nodes.items.len == 0 and doc.road_edges.items.len == 0) return false;

    const normal_line: shared_color.Color = .{ .r = 240, .g = 190, .b = 90, .a = 220 };
    const selected_line: shared_color.Color = .{ .r = 255, .g = 235, .b = 125, .a = 255 };
    const hover_line: shared_color.Color = .{ .r = 130, .g = 230, .b = 255, .a = 245 };
    const node_color: shared_color.Color = .{ .r = 255, .g = 220, .b = 120, .a = 250 };
    const handle_color: shared_color.Color = .{ .r = 255, .g = 175, .b = 105, .a = 235 };
    const selected_color: shared_color.Color = .{ .r = 255, .g = 245, .b = 150, .a = 255 };
    const hover_color: shared_color.Color = .{ .r = 135, .g = 235, .b = 255, .a = 255 };

    const hover = hitRoadGraphAtScreen(state, state.mouse_x, state.mouse_y);
    defer if (hover) |hit| state.allocator.free(hit.id);

    for (doc.road_edges.items) |edge| {
        const start = project_editor_ui_world_road_helpers.roadNodePosition(&doc, edge.start_node_id) orelse continue;
        const end = project_editor_ui_world_road_helpers.roadNodePosition(&doc, edge.end_node_id) orelse continue;
        const edge_selected = state.selected_road_edge_id != null and std.mem.eql(u8, state.selected_road_edge_id.?, edge.id);
        const edge_hovered = hover != null and std.mem.eql(u8, hover.?.id, edge.id);
        const terrain_mode = roadTerrainOverlayMode(state, edge.terrain_mode, edge_selected);
        const color = project_editor_ui_world_road_helpers.roadTerrainOverlayColor(terrain_mode, if (edge_hovered) hover_line else if (edge_selected) selected_line else normal_line);
        drawRoadCurve(state, vp_w, vp_h, start, edge.handle_start, edge.handle_end, end, color);
        if (edge_selected) {
            var style = world_curve_gizmos.defaultStyle();
            style.width_rail_color = project_editor_ui_world_road_helpers.roadTerrainOverlayRailColor(terrain_mode);
            const rail_width = if (state.world_road_mode == .surface) state.world_road_width else edge.width;
            drawRoadCurveWidthRails(state, vp_w, vp_h, start, edge.handle_start, edge.handle_end, end, rail_width, style);
        }

        const passive_handle_color = project_editor_ui_world_road_helpers.roadPassiveHandleColor(state.world_road_mode, handle_color);
        const arm_line_color = project_editor_ui_world_road_helpers.roadHandleArmLineColor(state.world_road_mode, color, edge_selected or edge_hovered);
        drawRoadHandleLine(state, vp_w, vp_h, start, edge.handle_start, arm_line_color, passive_handle_color);
        drawRoadHandleLine(state, vp_w, vp_h, end, edge.handle_end, arm_line_color, passive_handle_color);
        const start_handle_color = if (edge_selected and state.selected_road_handle == .start) selected_color else if (edge_hovered and hover.?.kind == .handle_start) hover_color else passive_handle_color;
        const end_handle_color = if (edge_selected and state.selected_road_handle == .end) selected_color else if (edge_hovered and hover.?.kind == .handle_end) hover_color else passive_handle_color;
        drawRoadHandle(state, vp_w, vp_h, edge.handle_start, start_handle_color);
        drawRoadHandle(state, vp_w, vp_h, edge.handle_end, end_handle_color);
    }

    for (doc.road_nodes.items) |node| {
        const selected = state.selected_road_node_id != null and std.mem.eql(u8, state.selected_road_node_id.?, node.id);
        const hovered = hover != null and hover.?.kind == .node and std.mem.eql(u8, hover.?.id, node.id);
        if (state.world_road_mode == .join and project_editor_ui_world_road_helpers.roadNodeDegree(&doc, node.id) <= 1) {
            drawRoadNodeHalo(state, vp_w, vp_h, node.position, if (hovered or selected) hover_color else .{ .r = 255, .g = 225, .b = 90, .a = 115 });
        }
        drawRoadHandle(state, vp_w, vp_h, node.position, if (hovered) hover_color else if (selected) selected_color else node_color);
    }
    return true;
}

fn roadTerrainOverlayMode(state: *const ProjectEditorState, edge_mode: spline_authoring.RoadTerrainMode, edge_selected: bool) spline_authoring.RoadTerrainMode {
    if (edge_selected and state.world_road_mode == .surface) return roadTerrainModeForState(state);
    return edge_mode;
}

fn drawRoadNodeHalo(
    state: *ProjectEditorState,
    vp_w: f32,
    vp_h: f32,
    point: editor_math.Vec3,
    color: shared_color.Color,
) void {
    const screen = project_editor_state.projectViewportPoint(state, point, vp_w, vp_h) orelse return;
    project_editor_viewport.drawViewportSquare(state, screen.x, screen.y, 9, color);
}

fn drawRoadSnapMarker(
    state: *ProjectEditorState,
    vp_w: f32,
    vp_h: f32,
    point: editor_math.Vec3,
    kind: RoadSnapKind,
) void {
    const screen = project_editor_state.projectViewportPoint(state, point, vp_w, vp_h) orelse return;
    const color: shared_color.Color = switch (kind) {
        .node => .{ .r = 120, .g = 235, .b = 255, .a = 245 },
        .edge => .{ .r = 255, .g = 185, .b = 95, .a = 250 },
    };
    project_editor_viewport.drawViewportLine(state, screen.x - 9, screen.y, screen.x + 9, screen.y, color);
    project_editor_viewport.drawViewportLine(state, screen.x, screen.y - 9, screen.x, screen.y + 9, color);
    project_editor_viewport.drawViewportSquare(state, screen.x, screen.y, if (kind == .edge) 7 else 5, color);
}

fn drawRoadCurve(
    state: *ProjectEditorState,
    vp_w: f32,
    vp_h: f32,
    start: friendly_engine.core.math.Vec3f,
    handle_start: friendly_engine.core.math.Vec3f,
    handle_end: friendly_engine.core.math.Vec3f,
    end: friendly_engine.core.math.Vec3f,
    color: shared_color.Color,
) void {
    var prev = project_editor_state.projectViewportPoint(state, start, vp_w, vp_h) orelse return;
    var sample_index: usize = 1;
    while (sample_index <= 20) : (sample_index += 1) {
        const t = @as(f32, @floatFromInt(sample_index)) / 20.0;
        const point = project_editor_ui_world_road_helpers.sampleRoadCurve(start, handle_start, handle_end, end, t);
        const screen = project_editor_state.projectViewportPoint(state, point, vp_w, vp_h) orelse continue;
        project_editor_viewport.drawViewportLine(state, prev.x, prev.y, screen.x, screen.y, color);
        prev = screen;
    }
}

fn drawRoadHandle(
    state: *ProjectEditorState,
    vp_w: f32,
    vp_h: f32,
    point: editor_math.Vec3,
    handle_color: shared_color.Color,
) void {
    const screen = project_editor_state.projectViewportPoint(state, point, vp_w, vp_h) orelse return;
    project_editor_viewport.drawViewportSquare(state, screen.x, screen.y, 4, handle_color);
}

fn drawRoadHandleLine(
    state: *ProjectEditorState,
    vp_w: f32,
    vp_h: f32,
    start: editor_math.Vec3,
    end: editor_math.Vec3,
    line_color: shared_color.Color,
    handle_color: shared_color.Color,
) void {
    const s0 = project_editor_state.projectViewportPoint(state, start, vp_w, vp_h) orelse return;
    const s1 = project_editor_state.projectViewportPoint(state, end, vp_w, vp_h) orelse return;
    project_editor_viewport.drawViewportLine(state, s0.x, s0.y, s1.x, s1.y, line_color);
    project_editor_viewport.drawViewportSquare(state, s0.x, s0.y, 4, handle_color);
    project_editor_viewport.drawViewportSquare(state, s1.x, s1.y, 4, handle_color);
}

fn createTerrainCell(state: *ProjectEditorState) !void {
    try project_editor_world_authoring.createTerrainCell(state);
}

test "world curve mode hint describes selected road action" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .world_tool = .roads,
        .world_road_mode = .shape,
        .selected_world_curve_hit = .{ .target = .road, .element = .handle_start },
        .selected_road_edge_id = @constCast("road.edge.1"),
        .selected_road_handle = .start,
    };

    try std.testing.expectEqualStrings("Drag the yellow handle to bend the road.", modeHint(&state));
}

test {
    _ = @import("project_editor_ui_world_water_tests.zig");
}

test "world curve mode hint describes active road drags" {
    var draw_state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .world_tool = .roads,
        .world_road_mode = .draw,
        .world_road_draw_mode = .freehand,
        .world_road_drag_anchor = .{ .x = 1, .y = 0, .z = 2 },
    };
    try std.testing.expectEqualStrings("Sketching road.", modeHint(&draw_state));

    var point_state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .world_tool = .roads,
        .world_road_mode = .shape,
        .selected_road_node_id = @constCast("road.node.1"),
        .world_road_drag_anchor = .{ .x = 1, .y = 0, .z = 2 },
    };
    try std.testing.expectEqualStrings("Moving road point.", modeHint(&point_state));

    var handle_state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .world_tool = .roads,
        .world_road_mode = .shape,
        .selected_road_edge_id = @constCast("road.edge.1"),
        .selected_road_handle = .start,
        .world_road_drag_anchor = .{ .x = 1, .y = 0, .z = 2 },
    };
    try std.testing.expectEqualStrings("Bending road.", modeHint(&handle_state));

    var segment_state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .world_tool = .roads,
        .world_road_mode = .shape,
        .selected_road_edge_id = @constCast("road.edge.1"),
        .selected_road_handle = .none,
        .world_road_drag_anchor = .{ .x = 1, .y = 0, .z = 2 },
    };
    try std.testing.expectEqualStrings("Road line selected.", modeHint(&segment_state));
}

test "world curve undo batch preserves status and coalesces snapshots" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .animations = .empty,
        .skeletons = .empty,
    };
    defer project_editor_edit.clearUndoHistory(&state);

    project_editor_state.setStatus(&state, "Moving road point.");
    beginWorldCurveUndoBatch(&state);
    pushWorldCurveUndoSnapshot(&state);
    pushWorldCurveUndoSnapshot(&state);
    endWorldCurveUndoBatch(&state);

    try std.testing.expectEqual(@as(usize, 1), state.undo_stack.items.len);
    try std.testing.expectEqualStrings("Moving road point.", state.status_buf[0..state.status_len]);
}

test "scatter density paint stroke coalesces undo snapshots" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .animations = .empty,
        .skeletons = .empty,
    };
    defer project_editor_edit.clearUndoHistory(&state);

    project_editor_state.setStatus(&state, "Painting scatter density.");
    beginScatterDensityPaint(&state);
    pushWorldCurveUndoSnapshot(&state);
    pushWorldCurveUndoSnapshot(&state);
    finishScatterDensityPaint(&state);

    try std.testing.expectEqual(@as(usize, 1), state.undo_stack.items.len);
    try std.testing.expectEqualStrings("Painting scatter density.", state.status_buf[0..state.status_len]);
}

test "road mode switch normalizes incompatible selections" {
    var surface_state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .world_tool = .roads,
        .world_road_mode = .shape,
        .selected_world_curve_hit = .{ .target = .road, .element = .handle_start, .index = 9 },
        .selected_road_edge_id = try std.testing.allocator.dupe(u8, "road.edge.1"),
        .selected_road_handle = .start,
    };
    defer if (surface_state.selected_road_edge_id) |id| std.testing.allocator.free(id);

    setRoadMode(&surface_state, .surface);

    try std.testing.expectEqual(project_editor_types.RoadToolMode.surface, surface_state.world_road_mode);
    try std.testing.expectEqual(@as(@TypeOf(surface_state.selected_road_handle), .none), surface_state.selected_road_handle);
    try std.testing.expectEqual(project_editor_types.WorldCurveHitElement.segment, surface_state.selected_world_curve_hit.element);
    try std.testing.expectEqual(@as(usize, 9), surface_state.selected_world_curve_hit.index);

    var join_state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .world_tool = .roads,
        .world_road_mode = .select,
        .selected_world_curve_hit = .{ .target = .road, .element = .segment },
        .selected_road_edge_id = try std.testing.allocator.dupe(u8, "road.edge.2"),
    };

    setRoadMode(&join_state, .join);

    try std.testing.expectEqual(project_editor_types.RoadToolMode.join, join_state.world_road_mode);
    try std.testing.expect(join_state.selected_road_edge_id == null);
    try std.testing.expect(join_state.selected_world_curve_hit.isNone());
}

test "road mode switch clears transient road preview" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .world_tool = .roads,
        .world_road_mode = .draw,
        .world_road_drag_anchor = .{ .x = 1, .y = 0, .z = 2 },
        .world_road_preview_end = .{ .x = 4, .y = 0, .z = 5 },
    };
    try state.world_road_points.append(std.testing.allocator, .{ .x = 1, .y = 0, .z = 2 });
    defer state.world_road_points.deinit(std.testing.allocator);

    setRoadMode(&state, .select);

    try std.testing.expectEqual(@as(usize, 0), state.world_road_points.items.len);
    try std.testing.expect(state.world_road_drag_anchor == null);
    try std.testing.expect(state.world_road_preview_end == null);
}

test "road edit miss clears stale selection with clear feedback" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .world_tool = .roads,
        .world_road_mode = .select,
        .viewport_screen_rect = .{ .x = 0, .y = 0, .w = 320, .h = 200 },
        .selected_world_curve_hit = .{ .target = .road, .element = .segment, .index = 2 },
        .selected_road_edge_id = try std.testing.allocator.dupe(u8, "road.edge.1"),
    };

    try std.testing.expect(roadViewportWantsPointer(&state, 20, 20));
    beginRoadDrag(&state, 20, 20);

    try std.testing.expect(state.selected_road_edge_id == null);
    try std.testing.expect(state.selected_road_node_id == null);
    try std.testing.expect(state.selected_world_curve_hit.isNone());
    try std.testing.expectEqualStrings("No road selected", state.status_buf[0..state.status_len]);
}

test "world curve mode hint describes selected non-road actions" {
    var ocean_state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .world_tool = .ocean,
        .selected_world_curve_hit = .{ .target = .ocean_clip, .element = .segment },
    };
    try std.testing.expectEqualStrings("Drag this boundary, double-click to add a point, or Delete to remove it.", modeHint(&ocean_state));

    var water_state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .world_tool = .water,
        .selected_world_curve_hit = .{ .target = .water_volume, .element = .segment },
    };
    try std.testing.expectEqualStrings("Drag this side, double-click to add a point, or Delete to remove it.", modeHint(&water_state));

    var scatter_state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .world_tool = .scatter,
        .selected_world_curve_hit = .{ .target = .scatter_zone, .element = .width_rail },
    };
    try std.testing.expectEqualStrings("Drag inside the area to move it.", modeHint(&scatter_state));
}

test "world curve delete affordance only appears for deletable visible parts" {
    var empty_state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .world_tool = .ocean,
    };
    try std.testing.expect(!worldCurveSelectionCanDelete(&empty_state));

    var water_edge_state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .world_tool = .water,
        .selected_world_curve_hit = .{ .target = .water_volume, .element = .segment },
    };
    try std.testing.expect(worldCurveSelectionCanDelete(&water_edge_state));

    var water_height_state = water_edge_state;
    water_height_state.selected_world_curve_hit = .{ .target = .water_volume, .element = .handle_start };
    try std.testing.expect(!worldCurveSelectionCanDelete(&water_height_state));

    var scatter_corner_state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .world_tool = .scatter,
        .selected_world_curve_hit = .{ .target = .scatter_zone, .element = .point },
    };
    try std.testing.expect(!worldCurveSelectionCanDelete(&scatter_corner_state));

    var scatter_zone_state = scatter_corner_state;
    scatter_zone_state.selected_world_curve_hit = .{ .target = .scatter_zone, .element = .width_rail };
    try std.testing.expect(worldCurveSelectionCanDelete(&scatter_zone_state));

    var unresolved_road_state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .world_tool = .roads,
        .selected_world_curve_hit = .{ .target = .road, .element = .segment },
    };
    try std.testing.expect(!worldCurveSelectionCanDelete(&unresolved_road_state));

    unresolved_road_state.selected_road_edge_id = try std.testing.allocator.dupe(u8, "road.edge.1");
    defer if (unresolved_road_state.selected_road_edge_id) |id| std.testing.allocator.free(id);
    try std.testing.expect(worldCurveSelectionCanDelete(&unresolved_road_state));
}

test "world curve delete command ignores non deletable handles" {
    var water_height_state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .mode = .world_creation,
        .world_tool = .water,
        .selected_world_curve_hit = .{ .target = .water_volume, .element = .handle_start },
    };
    try std.testing.expect(!deleteSelectedWorldCurvePart(&water_height_state));
    try std.testing.expectEqualStrings(
        "Drag the surface handle to change water height",
        water_height_state.status_buf[0..water_height_state.status_len],
    );

    var scatter_corner_state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .mode = .world_creation,
        .world_tool = .scatter,
        .selected_world_curve_hit = .{ .target = .scatter_zone, .element = .point },
    };
    try std.testing.expect(!deleteSelectedWorldCurvePart(&scatter_corner_state));
    try std.testing.expectEqualStrings(
        "Drag this corner to resize it; select the area to delete it",
        scatter_corner_state.status_buf[0..scatter_corner_state.status_len],
    );
}

test "road toolbar actions follow the selected road part" {
    var empty_state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .world_tool = .roads,
    };
    try std.testing.expect(!roadCanDeleteSegment(&empty_state));
    try std.testing.expect(!roadCanShapeSelectedSegment(&empty_state));
    try std.testing.expect(!roadCanDeleteJoin(&empty_state));
    try std.testing.expect(!roadCanRebuildSelected(&empty_state));

    var segment_state = empty_state;
    segment_state.selected_road_edge_id = @constCast("road.edge.1");
    segment_state.selected_road_handle = .none;
    try std.testing.expect(roadCanDeleteSegment(&segment_state));
    try std.testing.expect(roadCanShapeSelectedSegment(&segment_state));
    try std.testing.expect(!roadCanDeleteJoin(&segment_state));
    try std.testing.expect(roadCanRebuildSelected(&segment_state));

    var handle_state = segment_state;
    handle_state.selected_road_handle = .start;
    try std.testing.expect(!roadCanDeleteSegment(&handle_state));
    try std.testing.expect(roadCanShapeSelectedSegment(&handle_state));
    try std.testing.expect(roadCanRebuildSelected(&handle_state));

    var point_state = empty_state;
    point_state.selected_road_node_id = @constCast("road.node.1");
    try std.testing.expect(!roadCanDeleteSegment(&point_state));
    try std.testing.expect(!roadCanShapeSelectedSegment(&point_state));
    try std.testing.expect(roadCanDeleteJoin(&point_state));
    try std.testing.expect(roadCanRebuildSelected(&point_state));
}

test "world curve mode hint describes active gizmo drags" {
    var ocean_state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .world_tool = .ocean,
        .world_curve_drag_state = .{ .hit = .{ .target = .ocean_clip, .element = .point } },
    };
    try std.testing.expectEqualStrings("Moving ocean point.", modeHint(&ocean_state));

    var water_state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .world_tool = .water,
        .world_curve_drag_state = .{ .hit = .{ .target = .water_volume, .element = .handle_start } },
    };
    try std.testing.expectEqualStrings("Adjusting water surface height.", modeHint(&water_state));

    var scatter_state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .world_tool = .scatter,
        .world_curve_drag_state = .{ .hit = .{ .target = .scatter_zone, .element = .width_rail } },
    };
    try std.testing.expectEqualStrings("Moving scatter area.", modeHint(&scatter_state));
}

test "world tool switch clears incompatible curve selections" {
    var road_state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .world_tool = .roads,
        .selected_world_curve_hit = .{ .target = .road, .element = .segment },
        .selected_road_edge_id = try std.testing.allocator.dupe(u8, "road.edge.1"),
    };

    setWorldTool(&road_state, .water);

    try std.testing.expectEqual(project_editor_types.WorldTool.water, road_state.world_tool);
    try std.testing.expect(road_state.selected_world_curve_hit.isNone());
    try std.testing.expect(road_state.selected_road_edge_id == null);
    try std.testing.expectEqual(project_editor_types.WorldLayerId.water_volumes, road_state.selected_world_layer.?);

    var water_state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .world_tool = .water,
        .selected_world_curve_hit = .{ .target = .water_volume, .element = .point, .index = 2, .sub_index = 1 },
    };

    setWorldTool(&water_state, .roads);

    try std.testing.expectEqual(project_editor_types.WorldTool.roads, water_state.world_tool);
    try std.testing.expect(water_state.selected_world_curve_hit.isNone());
}

test "world curve selection clear resets road and ocean selection state" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .world_tool = .ocean,
        .selected_world_curve_hit = .{ .target = .ocean_clip, .element = .point, .index = 2, .sub_index = 3 },
        .selected_ocean_clip_point = 3,
        .selected_road_edge_id = try std.testing.allocator.dupe(u8, "stale.road.edge"),
    };

    try std.testing.expect(clearWorldCurveSelection(&state));
    try std.testing.expect(state.selected_world_curve_hit.isNone());
    try std.testing.expect(state.selected_ocean_clip_point == null);
    try std.testing.expect(state.selected_road_edge_id == null);
    try std.testing.expect(!clearWorldCurveSelection(&state));
}

test "inline world tool transition also clears curve selections" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .world_tool = .scatter,
        .selected_world_curve_hit = .{ .target = .scatter_zone, .element = .width_rail, .index = 4 },
        .hovered_world_curve_hit = .{ .target = .scatter_zone, .element = .point, .index = 4, .sub_index = 1 },
        .world_curve_drag_anchor = .{ .x = 1, .y = 0, .z = 2 },
        .world_curve_drag_state = .{ .start_x = 10, .start_y = 20 },
    };

    switchWorldToolStateOnly(&state, .paint);

    try std.testing.expectEqual(project_editor_types.WorldTool.paint, state.world_tool);
    try std.testing.expect(state.selected_world_curve_hit.isNone());
    try std.testing.expect(state.hovered_world_curve_hit.isNone());
    try std.testing.expect(state.world_curve_drag_anchor == null);
    try std.testing.expect(state.world_curve_drag_state.hit.isNone());
}

test "curve interaction begin reports miss without starting drag" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .viewport_screen_rect = .{ .x = 0, .y = 0, .w = 200, .h = 120 },
    };

    try std.testing.expectEqual(WorldCurveInteractionBegin.none, beginOceanClipInteraction(&state, 10, 10, 2));
    try std.testing.expectEqual(WorldCurveInteractionBegin.none, beginWaterVolumeInteraction(&state, 10, 10, 2));
}

test "ocean clip delete selection follows remaining point" {
    const kept = project_editor_ui_world_configurator.oceanClipSelectionAfterPointDelete(7, 2, 4);
    try std.testing.expectEqual(project_editor_types.WorldCurveHitTarget.ocean_clip, kept.target);
    try std.testing.expectEqual(project_editor_types.WorldCurveHitElement.point, kept.element);
    try std.testing.expectEqual(@as(usize, 7), kept.index);
    try std.testing.expectEqual(@as(usize, 2), kept.sub_index);

    const clamped = project_editor_ui_world_configurator.oceanClipSelectionAfterPointDelete(7, 4, 4);
    try std.testing.expectEqual(project_editor_types.WorldCurveHitTarget.ocean_clip, clamped.target);
    try std.testing.expectEqual(project_editor_types.WorldCurveHitElement.point, clamped.element);
    try std.testing.expectEqual(@as(usize, 7), clamped.index);
    try std.testing.expectEqual(@as(usize, 3), clamped.sub_index);

    const cleared = project_editor_ui_world_configurator.oceanClipSelectionAfterPointDelete(7, null, 4);
    try std.testing.expect(cleared.isNone());

    const empty = project_editor_ui_world_configurator.oceanClipSelectionAfterPointDelete(7, 0, 0);
    try std.testing.expect(empty.isNone());
}

test "ocean point selection mapping drives shared curve hit" {
    const selected = project_editor_ui_world_configurator.oceanClipSelectionAfterPointDelete(3, 0, 3);
    try std.testing.expectEqual(project_editor_types.WorldCurveHitTarget.ocean_clip, selected.target);
    try std.testing.expectEqual(project_editor_types.WorldCurveHitElement.point, selected.element);
    try std.testing.expectEqual(@as(usize, 3), selected.index);
    try std.testing.expectEqual(@as(usize, 0), selected.sub_index);
}

test "ocean point selection clears without remaining points" {
    const cleared = project_editor_ui_world_configurator.oceanClipSelectionAfterPointDelete(3, 0, 0);
    try std.testing.expect(cleared.isNone());
}

test "ocean edge delete removes the following exclusion point" {
    try std.testing.expectEqual(
        @as(?usize, 2),
        project_editor_ui_world_configurator.oceanDeletePointIndexForHit(.{ .target = .ocean_clip, .element = .segment, .sub_index = 1 }, 4),
    );
    try std.testing.expectEqual(
        @as(?usize, 0),
        project_editor_ui_world_configurator.oceanDeletePointIndexForHit(.{ .target = .ocean_clip, .element = .segment, .sub_index = 3 }, 4),
    );
    try std.testing.expectEqual(
        @as(?usize, null),
        project_editor_ui_world_configurator.oceanDeletePointIndexForHit(.{ .target = .ocean_clip, .element = .handle_start, .sub_index = 1 }, 4),
    );
}

test "road surface state maps onto edge input without moving handles" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .world_road_width = 9.5,
        .world_road_conform_offset = 0.35,
        .world_road_surface_mode = .prop_sections,
        .world_road_terrain_mode = .floating,
    };
    const edge = spline_authoring.OwnedRoadEdge{
        .id = @constCast("edge"),
        .start_node_id = @constCast("a"),
        .end_node_id = @constCast("b"),
        .handle_start = .{ .x = 1, .y = 0, .z = 0 },
        .handle_end = .{ .x = 2, .y = 0, .z = 0 },
        .width = 4,
        .elevation = 0.02,
        .material_mask_value = 200,
        .render_mode = .decal,
        .terrain_mode = .conform,
        .decal_material = @constCast("road.old"),
        .prop_asset_id = @constCast(""),
    };

    const input = roadEdgeInputWithSurface(&state, &edge, "a", "b", roadDecalMaterialForState(&state), roadPropAssetForState(&state));

    try std.testing.expectEqual(@as(f32, 9.5), input.width);
    try std.testing.expectEqual(@as(f32, 0.35), input.elevation);
    try std.testing.expectEqual(spline_authoring.RoadRenderMode.prop_sections, input.render_mode);
    try std.testing.expectEqual(spline_authoring.RoadTerrainMode.floating, input.terrain_mode);
    try std.testing.expectEqual(@as(f32, 1), input.handle_start.x);
    try std.testing.expectEqual(@as(f32, 2), input.handle_end.x);
    try std.testing.expectEqualStrings("road_section_straight", input.prop_asset_id);
}

test "selected surface road previews pending terrain mode in overlay" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .world_road_mode = .surface,
        .world_road_terrain_mode = .tunnel_reserved,
    };

    try std.testing.expectEqual(
        spline_authoring.RoadTerrainMode.tunnel_reserved,
        roadTerrainOverlayMode(&state, .conform, true),
    );
    try std.testing.expectEqual(
        spline_authoring.RoadTerrainMode.conform,
        roadTerrainOverlayMode(&state, .conform, false),
    );
}

test "selected committed road emits visible curve gizmo overlay primitives" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var project_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const project_path_len = try tmp.dir.realPath(std.testing.io, &project_path_buf);
    const project_path = try std.testing.allocator.dupe(u8, project_path_buf[0..project_path_len]);
    defer std.testing.allocator.free(project_path);

    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "world.kdl",
        .data =
        \\world version=1 id="test" cell_size_m=64 {
        \\  cell coord="-1,-1,0" authoring="scenes/terrain_empty.kdl"
        \\  cell coord="0,-1,0" authoring="scenes/terrain_empty.kdl"
        \\  cell coord="-1,0,0" authoring="scenes/terrain_empty.kdl"
        \\  cell coord="0,0,0" authoring="scenes/terrain_empty.kdl"
        \\}
        \\
        ,
    });

    const nodes = [_]spline_authoring.RoadNodeInput{
        .{
            .id = "a",
            .position = .{ .x = -1.5, .y = 0, .z = 0 },
        },
        .{
            .id = "b",
            .position = .{ .x = 1.5, .y = 0, .z = 0 },
        },
    };
    const edges = [_]spline_authoring.RoadEdgeInput{
        .{
            .id = "road.visible",
            .start_node_id = "a",
            .end_node_id = "b",
            .handle_start = .{ .x = -0.6, .y = 0.15, .z = -0.35 },
            .handle_end = .{ .x = 0.6, .y = 0.15, .z = 0.35 },
            .width = 2.0,
            .elevation = 0.05,
            .material_mask_value = 220,
            .render_mode = .decal,
            .terrain_mode = .conform,
            .decal_material = "terrain.road",
            .prop_asset_id = "",
        },
    };
    try spline_authoring.upsertRoadGraphFile(std.testing.allocator, std.testing.io, project_path, "world.kdl", &nodes, &edges);

    var recorder = project_editor_state.ViewportOverlayRecorder{};
    defer recorder.deinit(std.testing.allocator);
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = project_path,
        .project_name = "",
        .objects = .empty,
        .mode = .world_creation,
        .world_tool = .roads,
        .world_road_mode = .surface,
        .world_road_width = 2.0,
        .active_world_manifest_path = "world.kdl",
        .selected_world_layer = .spline_road_main,
        .selected_road_edge_id = try std.testing.allocator.dupe(u8, "road.visible"),
        .selected_road_handle = .start,
        .selected_world_curve_hit = .{ .target = .road, .element = .segment, .index = 0 },
        .camera = .{
            .target = .{ .x = 0, .y = 0, .z = 0 },
            .yaw = 0,
            .pitch = 0,
            .distance = 6,
        },
        .view_camera_mode = .perspective,
        .viewport_screen_rect = .{ .x = 0, .y = 0, .w = 640, .h = 480 },
        .viewport_overlay_rect = .{ .x = 0, .y = 0, .w = 640, .h = 480 },
        .viewport_overlay_recorder = &recorder,
    };
    defer if (state.selected_road_edge_id) |id| std.testing.allocator.free(id);

    const drew = drawCommittedRoadGraph(&state, 640, 480);
    try std.testing.expect(drew);
    try std.testing.expect(recorder.countKind(.line) >= 10);
    try std.testing.expect(recorder.countKind(.square) >= 6);
    try std.testing.expect(recorder.countColor(.{ .r = 255, .g = 235, .b = 125, .a = 255 }) > 0);
    try std.testing.expect(recorder.countColor(.{ .r = 255, .g = 245, .b = 150, .a = 255 }) > 0);
}
