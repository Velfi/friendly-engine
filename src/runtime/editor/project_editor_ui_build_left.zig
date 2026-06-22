const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const geometry = shared.geometry;
const command_ids = shared.editor_command_ids;
const scene_marker = shared.scene_marker;
const project_editor_edit = @import("project_editor_edit.zig");
const project_editor_blockout = @import("project_editor_blockout.zig");
const blockout_primitives = @import("project_editor_blockout_primitives.zig");
const project_editor_world_bake = @import("project_editor_world_bake.zig");
const project_editor_ui_tree = @import("project_editor_ui_tree.zig");
const project_editor_asset_browser = @import("project_editor_asset_browser.zig");
const project_editor_materials = @import("project_editor_materials.zig");
const project_editor_material_apply = @import("project_editor_material_apply.zig");
const project_editor_prop = @import("project_editor_prop.zig");
const project_editor_scene = @import("project_editor_scene.zig");
const project_editor_scene_filter = @import("project_editor_scene_filter.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_types = @import("project_editor_types.zig");
const world_authoring = @import("project_editor_world_authoring.zig");
const project_editor_ui_life = @import("project_editor_ui_life.zig");
const ui_world = @import("project_editor_ui_world.zig");
const project_editor_ui_prop = @import("project_editor_ui_prop.zig");
const ui_widgets = @import("project_editor_ui_widgets.zig");
const ui_layout = @import("project_editor_ui_layout.zig");
const ui_architecture = @import("project_editor_ui_architecture.zig");
const scene_hierarchy = @import("editor_scene_hierarchy.zig");
const project_editor_modes = @import("project_editor_modes.zig");
const scene_context_menu = @import("project_editor_scene_context_menu.zig");

const core_ui = friendly_engine.modules.core_ui;
const ProjectEditorState = project_editor_state.ProjectEditorState;
const left_rail_tabs = [_]project_editor_types.LeftRailTab{ .scene, .add, .world, .assets };

const MarkerButtonSpec = struct {
    kind: scene_marker.Kind,
    label: []const u8,
    width: f32,
};

const create_marker_specs = [_]MarkerButtonSpec{
    .{ .kind = .player_start, .label = "Player Start", .width = 104 },
    .{ .kind = .spawn_point, .label = "Spawn", .width = 82 },
    .{ .kind = .trigger_volume, .label = "Trigger", .width = 82 },
    .{ .kind = .objective, .label = "Objective", .width = 92 },
    .{ .kind = .patrol_point, .label = "Patrol", .width = 82 },
    .{ .kind = .camera_point, .label = "Camera", .width = 82 },
    .{ .kind = .audio_emitter, .label = "Audio", .width = 76 },
    .{ .kind = .checkpoint, .label = "Checkpoint", .width = 104 },
    .{ .kind = .encounter_spawn, .label = "Encounter", .width = 98 },
    .{ .kind = .item_spawn, .label = "Item", .width = 68 },
    .{ .kind = .interactable_anchor, .label = "Interact", .width = 88 },
    .{ .kind = .nav_point, .label = "Nav", .width = 68 },
    .{ .kind = .region_anchor, .label = "Region", .width = 78 },
};

pub fn buildLeftInspector(ui: *core_ui.UiContext, state: *ProjectEditorState, rect: core_ui.Rect) !void {
    try buildLeftRail(ui, state, rect);
}

pub fn buildLeftRail(ui: *core_ui.UiContext, state: *ProjectEditorState, rect: core_ui.Rect) !void {
    const panel_pad: f32 = 8;
    const tab_spacing: f32 = 6;
    try ui.beginPanel(.{ .id = "ed-left", .rect = rect, .row_height = 24, .padding = panel_pad, .spacing = tab_spacing });
    try core_ui.layout.sameLine(ui);
    if (state.left_tab == .world and !project_editor_state.editorModeEnabled(state, .world_creation)) state.left_tab = .scene;
    const content_w = rect.w - panel_pad * 2;
    const tab_w = (content_w - tab_spacing) / 2;
    inline for (left_rail_tabs, 0..) |tab, idx| {
        if (idx == 2) {
            try core_ui.layout.endSameLine(ui);
            try core_ui.layout.sameLine(ui);
        }
        const enabled = tab != .world or project_editor_state.editorModeEnabled(state, .world_creation);
        if (enabled) {
            if ((try ui_widgets.button(ui, command_ids.leftTab(@tagName(tab)), tab.label(), tab_w, state.left_tab == tab)).clicked) state.left_tab = tab;
        }
    }
    try core_ui.layout.endSameLine(ui);
    const scroll_h = try core_ui.layout.remainingPanelContentHeight(ui);
    var scrolled = false;
    if (scroll_h > 1) {
        try core_ui.layout.beginScrollArea(ui, .{ .id = "ed-left-scroll", .height = scroll_h, .input = core_ui.layout.panel_scroll_input });
        scrolled = true;
    }
    switch (state.left_tab) {
        .scene => {
            if (state.mode == .layout) try ui_layout.buildSceneHierarchy(ui, state) else try buildSceneList(ui, state);
        },
        .add => try buildAddList(ui, state),
        .world => try buildWorldList(ui, state),
        .assets => if (state.mode == .prop_creation) {
            try project_editor_ui_prop.buildBrowser(ui, state);
        } else {
            try buildAssetsList(ui, state);
        },
    }
    if (scrolled) try core_ui.layout.endScrollArea(ui);
    ui.endPanel();
}

pub fn buildProjectPanel(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    try core_ui.layout.sameLine(ui);
    if (state.left_tab == .world and !project_editor_state.editorModeEnabled(state, .world_creation)) state.left_tab = .scene;
    const layout = try ui.currentLayout();
    const tab_w = @max(92, (layout.content_w - layout.inline_spacing) / 2);
    inline for (left_rail_tabs, 0..) |tab, idx| {
        if (idx == 2) {
            try core_ui.layout.endSameLine(ui);
            try core_ui.layout.sameLine(ui);
        }
        const enabled = tab != .world or project_editor_state.editorModeEnabled(state, .world_creation);
        if (enabled) {
            if ((try ui_widgets.button(ui, command_ids.leftTab(@tagName(tab)), tab.label(), tab_w, state.left_tab == tab)).clicked) state.left_tab = tab;
        }
    }
    try core_ui.layout.endSameLine(ui);

    switch (state.left_tab) {
        .scene => {
            if (state.mode == .layout) try ui_layout.buildSceneHierarchy(ui, state) else try buildSceneList(ui, state);
        },
        .add => try buildAddList(ui, state),
        .world => try buildWorldList(ui, state),
        .assets => if (state.mode == .prop_creation) {
            try project_editor_ui_prop.buildBrowser(ui, state);
        } else {
            try buildAssetsList(ui, state);
        },
    }
}

fn buildModeToolSettings(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    var mode_buf: [96]u8 = undefined;
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&mode_buf, "{s} / {s}", .{
        state.mode.label(),
        project_editor_modes.toolLabel(state),
    }) catch state.mode.label());
    try project_editor_modes.buildToolInspector(ui, state);
}

fn buildModeLeftRail(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    try project_editor_modes.buildLeftPanel(ui, state);
}

fn buildSceneList(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    _ = try core_ui.widgets_input.searchInput(ui, "ed-scene-search");
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.iconButtonTip(ui, "ed-add-small", "add", false, "Add object")).clicked) state.left_tab = .add;
    if ((try ui_widgets.iconButtonTip(ui, "ed-copy", "duplicate", false, "Ctrl+D Duplicate")).clicked) try project_editor_scene.duplicateSelected(state);
    if ((try ui_widgets.iconButtonTip(ui, "ed-delete", "delete", false, "Del Delete")).clicked) try project_editor_scene.deleteSelected(state);
    try core_ui.layout.endSameLine(ui);
    try project_editor_scene_filter.buildControls(ui, state, "ed-scene-filter");
    _ = try ui_widgets.treeRow(ui, "Scene objects", &state.show_scene_group);
    if (state.show_scene_group) try buildFilteredSceneRows(ui, state);
    if (try scene_context_menu.build(ui, state)) return;
    if (state.mode == .world_creation) try ui_world.buildTerrainCellsPanel(ui, state);
}

fn buildFilteredSceneRows(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    const rows = try project_editor_scene_filter.collectVisibleRows(state.allocator, ui, state);
    defer state.allocator.free(rows);
    var count_buf: [80]u8 = undefined;
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&count_buf, "{d} of {d} objects", .{ rows.len, state.objects.items.len }) catch "Objects");
    if (rows.len == 0) {
        try ui_widgets.compactInfo(ui, "No objects match filters");
        return;
    }
    const scroll_h = @min(420.0, @max(140.0, try core_ui.layout.remainingPanelContentHeight(ui)));
    try core_ui.layout.beginScrollArea(ui, .{ .id = "ed-scene-results-scroll", .height = scroll_h, .input = core_ui.layout.panel_scroll_input });
    const range = try core_ui.layout.virtualListRange(ui, rows.len, 24);
    try core_ui.layout.virtualListSpacer(ui, range.top_padding);
    for (rows[range.start..range.end]) |entry| {
        try buildSceneTreeRow(ui, state, entry.idx, entry.depth);
    }
    try core_ui.layout.virtualListSpacer(ui, range.bottom_padding);
    try core_ui.layout.endScrollArea(ui);
}

fn buildSceneTreeChildren(ui: *core_ui.UiContext, state: *ProjectEditorState, parent_id: ?u64, depth: u32) !void {
    for (state.objects.items, 0..) |_, idx| {
        if (!objectBelongsToTreeParent(state.objects.items, idx, parent_id)) continue;
        if (!objectMatchesTreeFilter(ui, state, idx)) continue;
        try buildSceneTreeRow(ui, state, idx, depth);
        if (objectHasTreeChildren(state, idx)) {
            const open = try sceneTreeOpen(ui, state.objects.items[idx].id, depth);
            if (open) try buildSceneTreeChildren(ui, state, state.objects.items[idx].id, depth + 1);
        }
    }
}

fn buildSceneTreeRow(ui: *core_ui.UiContext, state: *ProjectEditorState, idx: usize, depth: u32) !void {
    var obj = &state.objects.items[idx];
    if (!project_editor_state.objectVisible(state, obj)) return;
    const child_count = objectTreeChildCount(state, idx);
    const has_children = child_count > 0;
    const open = if (has_children) try sceneTreeOpen(ui, obj.id, depth) else false;
    const marker = if (has_children) (if (open) "v" else ">") else "-";
    var label_buf: [160]u8 = undefined;
    const label = if (has_children)
        std.fmt.bufPrint(&label_buf, "{s} ({d}) {s}  [{s}]", .{ marker, child_count, obj.name, ui_widgets.objectTypeLabel(obj) }) catch obj.name
    else
        std.fmt.bufPrint(&label_buf, "{s} {s}  [{s}]", .{ marker, obj.name, ui_widgets.objectTypeLabel(obj) }) catch obj.name;
    var row_id_buf: [48]u8 = undefined;
    const row_id = std.fmt.bufPrint(&row_id_buf, "scene-row-{d}", .{obj.id}) catch obj.name;
    const scene_row_text_pad: f32 = 54 + @as(f32, @floatFromInt(@min(depth, 8))) * 16;
    const row_result = try ui_widgets.rowWithTextPad(ui, row_id, label, state.selected_object == idx, scene_row_text_pad);
    if (row_result.hovered and ui.input.right_button_pressed) {
        scene_context_menu.open(state, idx, ui.input.mouse_position.x, ui.input.mouse_position.y);
    }
    if (row_result.clicked) {
        if (has_children and row_result.rect.x + scene_row_text_pad - 18 <= state.mouse_x and state.mouse_x <= row_result.rect.x + scene_row_text_pad) {
            try setSceneTreeOpen(ui, obj.id, !open);
        } else {
            state.selected_object = idx;
            state.selected_vertex = null;
            state.selected_edge = null;
            state.selected_face = null;
        }
    }
    const icon_size: f32 = 20;
    const icon_y = row_result.rect.y + (row_result.rect.h - icon_size) * 0.5;
    var eye_id_buf: [48]u8 = undefined;
    const eye_id = std.fmt.bufPrint(&eye_id_buf, "scene-eye-{d}", .{obj.id}) catch obj.name;
    const eye_icon = if (obj.renderer_visible) "eye" else "eye-closed";
    const eye = try ui_widgets.iconOverlayButton(ui, eye_id, eye_icon, .{ .x = row_result.rect.x + 4, .y = icon_y, .w = icon_size, .h = icon_size }, obj.renderer_visible);
    if (eye.clicked and obj.canModifyObject()) {
        project_editor_edit.pushUndoSnapshot(state);
        obj.renderer_visible = !obj.renderer_visible;
        state.scene_dirty = true;
    }
    try core_ui.widgets_feedback.tooltip(ui, eye.rect, if (obj.isImmutable()) "Immutable object" else if (obj.renderer_visible) "Hide object" else "Show object");
    var lock_id_buf: [48]u8 = undefined;
    const lock_id = std.fmt.bufPrint(&lock_id_buf, "scene-lock-{d}", .{obj.id}) catch obj.name;
    const lock_icon = if (obj.isImmutable() or obj.locked) "lock" else "lock-slash";
    const lock = try ui_widgets.iconOverlayButton(ui, lock_id, lock_icon, .{ .x = row_result.rect.x + 4 + icon_size + 2, .y = icon_y, .w = icon_size, .h = icon_size }, obj.locked);
    if (lock.clicked and !obj.isImmutable()) {
        project_editor_edit.pushUndoSnapshot(state);
        obj.locked = !obj.locked;
    }
    try core_ui.widgets_feedback.tooltip(ui, lock.rect, if (obj.isImmutable()) "Immutable object" else if (obj.locked) "Unlock object" else "Lock object");
}

fn sceneTreeOpen(ui: *core_ui.UiContext, object_id: u64, depth: u32) !bool {
    var key_buf: [48]u8 = undefined;
    const key = std.fmt.bufPrint(&key_buf, "scene-tree-open-{d}", .{object_id}) catch "scene-tree-open";
    const stable = try ui.stableId(key, key);
    return try ui.getBoolState(stable, depth <= 1);
}

fn setSceneTreeOpen(ui: *core_ui.UiContext, object_id: u64, open: bool) !void {
    var key_buf: [48]u8 = undefined;
    const key = std.fmt.bufPrint(&key_buf, "scene-tree-open-{d}", .{object_id}) catch "scene-tree-open";
    const stable = try ui.stableId(key, key);
    try ui.setBoolState(stable, open);
}

fn objectBelongsToTreeParent(objects: []const project_editor_state.SceneObject, idx: usize, parent_id: ?u64) bool {
    const obj = objects[idx];
    if (parent_id) |pid| return obj.parent_id == pid;
    if (obj.parent_id == null) return true;
    return scene_hierarchy.objectIndexById(objects, obj.parent_id.?) == null;
}

fn objectHasTreeChildren(state: *const ProjectEditorState, idx: usize) bool {
    return objectTreeChildCount(state, idx) > 0;
}

fn objectTreeChildCount(state: *const ProjectEditorState, idx: usize) usize {
    const parent_id = state.objects.items[idx].id;
    var count: usize = 0;
    for (state.objects.items) |child| {
        if (child.parent_id == parent_id and project_editor_state.objectVisible(state, &child)) count += 1;
    }
    return count;
}

fn objectMatchesTreeFilter(ui: *core_ui.UiContext, state: *const ProjectEditorState, idx: usize) bool {
    const obj = &state.objects.items[idx];
    if (!project_editor_state.objectVisible(state, obj)) return false;
    if (ui_widgets.matchesFilter(ui, "ed-scene-search", obj.name)) return true;
    for (state.objects.items, 0..) |child, child_idx| {
        if (child.parent_id == obj.id and objectMatchesTreeFilter(ui, state, child_idx)) return true;
    }
    return false;
}

fn buildAddList(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    _ = try core_ui.widgets_input.searchInput(ui, "ed-add-search");
    try ui.label("Create");
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.button(ui, "ed-empty", "Empty", 68, false)).clicked) try project_editor_scene.addEditorObject(state, .empty);
    if ((try ui_widgets.button(ui, "Box", "Box", 68, false)).clicked) try project_editor_scene.addPrimitive(state, .box, "Box");
    if ((try ui_widgets.button(ui, "Plane", "Plane", 68, false)).clicked) try project_editor_scene.addPrimitive(state, .plane, "Plane");
    try core_ui.layout.endSameLine(ui);
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.button(ui, "Sphere", "Sphere", 68, false)).clicked) try project_editor_scene.addPrimitive(state, .sphere, "Sphere");
    if ((try ui_widgets.button(ui, "Cylinder", "Cyl", 68, false)).clicked) try project_editor_scene.addPrimitive(state, .cylinder, "Cylinder");
    if ((try ui_widgets.button(ui, "ed-light", "Light", 68, false)).clicked) try project_editor_scene.addEditorObject(state, .light);
    try core_ui.layout.endSameLine(ui);
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.button(ui, "ed-camera", "Camera", 68, false)).clicked) try project_editor_scene.addMarkerObject(state, .camera_point);
    if ((try ui_widgets.button(ui, "ed-trigger", "Trigger", 68, false)).clicked) try project_editor_scene.addMarkerObject(state, .trigger_volume);
    if ((try ui_widgets.button(ui, "ed-audio", "Audio", 68, false)).clicked) try project_editor_scene.addMarkerObject(state, .audio_emitter);
    try core_ui.layout.endSameLine(ui);
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.button(ui, "ed-prefab", "Prefab", 68, false)).clicked) try project_editor_scene.addEditorObject(state, .prefab);
    if (project_editor_state.editorModeEnabled(state, .architecture_creation)) {
        if ((try ui_widgets.button(ui, "ed-brush-box", "Brush", 68, state.mode == .architecture_creation and state.architecture_tool == .brush)).clicked) {
            project_editor_scene.setMode(state, .architecture_creation);
            state.architecture_tool = .brush;
            project_editor_scene.onModeChanged(state);
        }
        if ((try ui_widgets.button(ui, command_ids.blockout_ramp, "Ramp", 68, false)).clicked) try project_editor_blockout.addBlockoutRamp(state);
        if ((try ui_widgets.button(ui, "ed-blockout-doorway", "Door", 68, false)).clicked) try blockout_primitives.addDoorway(state);
        if ((try ui_widgets.button(ui, "ed-blockout-stair", "Stair", 68, false)).clicked) try blockout_primitives.addStair(state);
    }
    try core_ui.layout.endSameLine(ui);
    try ui.label("Game Markers");
    try markerButtonGrid(ui, state);
    try ui.label("Primitives");
    const primitives = [_]struct { kind: geometry.PrimitiveKind, label: []const u8 }{
        .{ .kind = .box, .label = "Box" },
        .{ .kind = .plane, .label = "Plane" },
        .{ .kind = .cylinder, .label = "Cylinder" },
        .{ .kind = .sphere, .label = "Sphere" },
    };
    for (primitives) |prim| {
        if ((try ui_widgets.button(ui, prim.label, prim.label, 226, false)).clicked) try project_editor_scene.addPrimitive(state, prim.kind, prim.label);
    }
}

fn markerButtonGrid(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    for (create_marker_specs, 0..) |spec, idx| {
        if (idx % 2 == 0) try core_ui.layout.sameLine(ui);
        try markerButton(ui, state, spec.kind, spec.label, spec.width);
        if (idx % 2 == 1 or idx + 1 == create_marker_specs.len) try core_ui.layout.endSameLine(ui);
    }
}

fn markerButton(ui: *core_ui.UiContext, state: *ProjectEditorState, kind: scene_marker.Kind, label: []const u8, width: f32) !void {
    var id_buf: [80]u8 = undefined;
    if ((try ui_widgets.button(
        ui,
        std.fmt.bufPrint(&id_buf, "ed-marker-{s}", .{kind.name()}) catch "ed-marker",
        label,
        width,
        false,
    )).clicked) try project_editor_scene.addMarkerObject(state, kind);
}

fn buildWorldList(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    if (state.mode == .world_creation) {
        try ui_world.buildLayersPanel(ui, state);
        return;
    }
    try ui.label("Scene Settings");
    try ui_widgets.compactInfo(ui, "Ambient 0.8  #b8c0cc");
    try ui_widgets.compactInfo(ui, "Sky #121821");
    const fog = try core_ui.widgets_input.checkbox(ui, "Fog", "ed-world-fog");
    state.world_fog_enabled = fog.checked;
    try ui_widgets.compactInfo(ui, if (state.world_fog_enabled) "Fog color #8894a8  8-80m" else "Fog off");
    try ui_widgets.compactInfo(ui, "Gravity 0,-9.8,0");
    try ui_widgets.compactInfo(ui, "Active Camera: Editor");
    try ui_widgets.compactInfo(ui, "Units: meters  Grid 1.0");
    try ui.label("World Layers");
    try core_ui.widgets_feedback.statusLabel(ui, "Author compiled cell data");
    if ((try ui_widgets.layerButton(ui, "Terrain Tile", "Height + splat patch")).clicked) try ui_widgets.writeLayer(state, world_authoring.paintTerrainTile, "Terrain layer updated", "Terrain layer write failed");
    if ((try ui_widgets.layerButton(ui, "Road", "Road mesh + mask")).clicked) try ui_widgets.writeLayer(state, world_authoring.drawRoadThroughCell, "Road updated", "Road update failed");
    if ((try ui_widgets.layerButton(ui, "Scatter", "Density + cluster controls")).clicked) try ui_widgets.writeLayer(state, world_authoring.seedScatter, "Scatter layer updated", "Scatter layer write failed");
    if ((try ui_widgets.layerButton(ui, "Interior Room", "Sector cell plan")).clicked) try ui_widgets.writeLayer(state, world_authoring.authorInteriorRoom, "Sector layer updated", "Sector layer write failed");
    if ((try ui_widgets.layerButton(ui, "Building", "Semantic shell")).clicked) try ui_widgets.writeLayer(state, world_authoring.authorBuilding, "Building layer updated", "Building layer write failed");
    if ((try ui_widgets.button(ui, "ed-recompile-cells", "Bake Dirty", 108, false)).clicked) project_editor_world_bake.recompileDirtyCells(state);
    if ((try ui_widgets.button(ui, "ed-ui-tree", "UI Tree", 78, state.ui_tree_open)).clicked) state.ui_tree_open = !state.ui_tree_open;
    if (state.ui_tree_open) {
        var tree_buf: [256]u8 = undefined;
        try core_ui.widgets_feedback.statusLabel(ui, try project_editor_ui_tree.formatStatus(state, ui, &tree_buf));
    }
    if (state.dirty_cells.count > 0) {
        var dirty_buf: [128]u8 = undefined;
        try core_ui.widgets_feedback.statusLabel(ui, try state.dirty_cells.formatStatus(&dirty_buf));
    }
}

fn buildAssetsList(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    _ = try core_ui.widgets_input.searchInput(ui, "ed-asset-search");
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.button(ui, "ed-assets-list", "List", 54, !state.asset_grid_view)).clicked) state.asset_grid_view = false;
    if ((try ui_widgets.button(ui, "ed-assets-grid", "Grid", 54, state.asset_grid_view)).clicked) state.asset_grid_view = true;
    if ((try ui_widgets.button(ui, "ed-assets-add", "Add", 54, false)).clicked) try project_editor_scene.instantiateSelectedAsset(state);
    try core_ui.layout.endSameLine(ui);
    try ui_widgets.compactInfo(ui, "assets / cache / client-debug");
    var catalog = project_editor_asset_browser.load(state.allocator, state.io, state.project_path, "client-debug") catch {
        try core_ui.widgets_feedback.statusLabel(ui, "Asset manifest missing or stale");
        try ui.label("Materials");
        for (project_editor_materials.catalog) |material| {
            if (!ui_widgets.matchesFilter(ui, "ed-asset-search", material.label) and !ui_widgets.matchesFilter(ui, "ed-asset-search", material.path)) continue;
            if ((try ui_widgets.materialRow(ui, material, state.selected_material == material.id)).clicked) {
                project_editor_material_apply.apply(state, material.id);
            }
        }
        return;
    };
    defer catalog.deinit(state.allocator);

    var count_buf: [64]u8 = undefined;
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&count_buf, "{d} imported assets", .{catalog.entries.len}) catch "Imported assets");
    try ui.label("Imported");
    for (catalog.entries) |entry| {
        if (!ui_widgets.matchesFilter(ui, "ed-asset-search", entry.source_path) and !ui_widgets.matchesFilter(ui, "ed-asset-search", entry.artifact_path)) continue;
        var label_buf: [192]u8 = undefined;
        const label = std.fmt.bufPrint(
            &label_buf,
            "{s}  {s}  {d}b",
            .{ entry.kind, std.fs.path.basename(entry.source_path), entry.runtime_size_bytes },
        ) catch entry.source_path;
        var id_buf: [64]u8 = undefined;
        const row_id = std.fmt.bufPrint(&id_buf, "asset-{d}", .{entry.asset_id}) catch entry.source_path;
        if ((try ui_widgets.row(ui, row_id, label, false)).clicked) {
            project_editor_state.setStatus(state, entry.artifact_path);
        }
    }

    try ui.label("Materials");
    for (project_editor_materials.catalog) |material| {
        if (!ui_widgets.matchesFilter(ui, "ed-asset-search", material.label) and !ui_widgets.matchesFilter(ui, "ed-asset-search", material.path)) continue;
        if ((try ui_widgets.materialRow(ui, material, state.selected_material == material.id)).clicked) {
            project_editor_material_apply.apply(state, material.id);
        }
    }
    try ui.label("Meshes");
    if ((try ui_widgets.row(ui, "asset-mesh-box", "mesh  box.glb", state.selected_asset == .mesh_box)).clicked) {
        state.selected_asset = .mesh_box;
        project_editor_state.setStatus(state, "Mesh asset selected");
    }
    try ui.label("Props");
    for (project_editor_prop.catalog, 0..) |entry, idx| {
        if (!ui_widgets.matchesFilter(ui, "ed-asset-search", entry.label) and !ui_widgets.matchesFilter(ui, "ed-asset-search", entry.id)) continue;
        var id_buf: [48]u8 = undefined;
        const row_id = std.fmt.bufPrint(&id_buf, "layout-prop-asset-{d}", .{idx}) catch entry.id;
        var detail_buf: [96]u8 = undefined;
        if ((try ui_widgets.assetPreview(ui, .{
            .id = row_id,
            .label = entry.label,
            .detail = project_editor_ui_prop.propAssetDetail(entry, &detail_buf),
            .fill_color = entry.color,
            .shape = project_editor_ui_prop.propPreviewShape(entry.kind),
            .selected = std.mem.eql(u8, state.prop_selected_asset, entry.id),
        })).clicked) {
            state.prop_selected_asset = entry.id;
            const point = shared.editor_math.Vec3{
                .x = state.camera.target.x,
                .y = geometry.groundOffsetY(entry.kind, entry.params, 1.0),
                .z = state.camera.target.z,
            };
            try project_editor_prop.instantiatePropAssetAt(state, entry.id, point);
            project_editor_state.setStatus(state, "Placed prop from Layout assets");
        }
    }
    try ui.label("Scenes");
    if ((try ui_widgets.row(ui, "asset-scene-main", "scene  main.kdl", state.selected_asset == .scene_main)).clicked) {
        state.selected_asset = .scene_main;
        project_editor_state.setStatus(state, "Scene asset selected");
    }
}

test "left rail create tab uses requested label" {
    try std.testing.expectEqualStrings("Create", project_editor_types.LeftRailTab.add.label());
}

test "left rail task tabs are shared across editor modes" {
    try std.testing.expectEqual(@as(usize, 4), left_rail_tabs.len);
    try std.testing.expectEqual(project_editor_types.LeftRailTab.scene, left_rail_tabs[0]);
    try std.testing.expectEqual(project_editor_types.LeftRailTab.add, left_rail_tabs[1]);
    try std.testing.expectEqual(project_editor_types.LeftRailTab.world, left_rail_tabs[2]);
    try std.testing.expectEqual(project_editor_types.LeftRailTab.assets, left_rail_tabs[3]);
}

test "create rail exposes every gameplay marker primitive" {
    var seen = [_]bool{false} ** std.meta.fields(scene_marker.Kind).len;
    for (create_marker_specs) |spec| {
        const idx = @intFromEnum(spec.kind);
        try std.testing.expect(!seen[idx]);
        seen[idx] = true;
        try std.testing.expect(spec.label.len > 0);
        try std.testing.expect(spec.width >= 60);
    }
    inline for (std.meta.fields(scene_marker.Kind)) |field| {
        try std.testing.expect(seen[field.value]);
    }
}
