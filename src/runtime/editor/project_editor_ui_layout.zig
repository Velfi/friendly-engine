const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const command_ids = shared.editor_command_ids;
const project_editor_edit = @import("project_editor_edit.zig");
const project_editor_scene = @import("project_editor_scene.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_types = @import("project_editor_types.zig");
const project_editor_prop = @import("project_editor_prop.zig");
const project_editor_scene_filter = @import("project_editor_scene_filter.zig");
const scene_hierarchy = @import("editor_scene_hierarchy.zig");
const ui_widgets = @import("project_editor_ui_widgets.zig");
const project_editor_mode_config = @import("project_editor_mode_config.zig");
const scene_context_menu = @import("project_editor_scene_context_menu.zig");

const core_ui = friendly_engine.modules.core_ui;
const ProjectEditorState = project_editor_state.ProjectEditorState;

pub const modeStatus = "Layout mode: select and transform objects";

pub fn registerEditor(registry: *project_editor_mode_config.EditorRegistry) !void {
    try registry.registerMode(project_editor_mode_config.descForMode(.layout).*);
}

pub fn buildViewportTools(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    const tools = [_]project_editor_types.ObjectTool{ .select, .move, .rotate, .scale };
    inline for (tools) |tool| {
        if ((try ui_widgets.iconButtonTip(ui, command_ids.objectTool(@tagName(tool)), ui_widgets.toolIcon(tool), state.object_tool == tool, ui_widgets.toolTip(tool))).clicked) {
            project_editor_scene.setObjectTool(state, tool);
        }
    }
    if ((try ui_widgets.iconButtonTip(ui, "ed-layout-duplicate", "duplicate", false, "Duplicate")).clicked) try project_editor_scene.duplicateSelected(state);
    if ((try ui_widgets.iconButtonTip(ui, "ed-layout-frame", "frame", false, "Frame")).clicked) ui_widgets.frameSelected(state);
}

pub fn buildToolInspector(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    try ui.label("Transform Tool");
    try core_ui.layout.sameLine(ui);
    const tools = [_]project_editor_types.ObjectTool{ .select, .move, .rotate, .scale };
    inline for (tools) |tool| {
        if ((try ui_widgets.iconButtonTip(ui, command_ids.objectTool(@tagName(tool)), ui_widgets.toolIcon(tool), state.object_tool == tool, ui_widgets.toolTip(tool))).clicked) {
            project_editor_scene.setObjectTool(state, tool);
        }
    }
    try core_ui.layout.endSameLine(ui);

    if (state.object_tool == .select) {
        try ui_widgets.compactInfo(ui, "Click an object to select it");
        return;
    }

    try ui.label("Transform Settings");
    if ((try ui_widgets.syncedCheckbox(ui, "Grid Snap", "ed-layout-tool-snap", state.snap_enabled)).clicked) project_editor_edit.toggleSnap(state);
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.button(ui, "ed-layout-tool-grid-minus", "-", 28, false)).clicked) state.snap_size = @max(0.25, state.snap_size * 0.5);
    var grid_buf: [24]u8 = undefined;
    _ = try ui_widgets.button(ui, "ed-layout-tool-grid-label", std.fmt.bufPrint(&grid_buf, "{d:.1}m", .{state.snap_size}) catch "1.0m", 58, false);
    if ((try ui_widgets.button(ui, "ed-layout-tool-grid-plus", "+", 28, false)).clicked) state.snap_size = @min(16, state.snap_size * 2);
    try core_ui.layout.endSameLine(ui);

    try core_ui.layout.sameLine(ui);
    const pivot_label = if (state.pivot_mode == .center) "Median" else "Pivot";
    if ((try ui_widgets.button(ui, "ed-layout-tool-pivot", pivot_label, 74, false)).clicked) {
        state.pivot_mode = if (state.pivot_mode == .pivot) .center else .pivot;
    }
    if ((try ui_widgets.button(ui, "ed-layout-tool-space", state.transform_space.label(), 74, false)).clicked) {
        state.transform_space = if (state.transform_space == .world) .local else .world;
    }
    if ((try ui_widgets.button(ui, "ed-layout-tool-axis", project_editor_state.moveAxisLabel(state), 58, false)).clicked) project_editor_scene.cycleMoveAxis(state);
    try core_ui.layout.endSameLine(ui);

    if ((try ui_widgets.syncedCheckbox(ui, "Show Gizmo", "ed-layout-tool-gizmo", state.show_gizmo)).clicked) state.show_gizmo = !state.show_gizmo;
}

pub fn buildSceneHierarchy(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    _ = try core_ui.widgets_input.searchInput(ui, "ed-scene-search");
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.iconButtonTip(ui, "ed-add-small", "add", false, "Add object")).clicked) state.left_tab = .add;
    if ((try ui_widgets.iconButtonTip(ui, "ed-copy", "duplicate", false, "Ctrl+D Duplicate")).clicked) try project_editor_scene.duplicateSelected(state);
    if ((try ui_widgets.iconButtonTip(ui, "ed-delete", "delete", false, "Del Delete")).clicked) try project_editor_scene.deleteSelected(state);
    try core_ui.layout.endSameLine(ui);
    try project_editor_scene_filter.buildControls(ui, state, "ed-layout-scene-filter");
    _ = try ui_widgets.treeRow(ui, "Scene", &state.show_scene_group);
    if (!state.show_scene_group) return;
    const rows = try project_editor_scene_filter.collectVisibleRows(state.allocator, ui, state);
    defer state.allocator.free(rows);
    var count_buf: [80]u8 = undefined;
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&count_buf, "{d} of {d} objects", .{ rows.len, state.objects.items.len }) catch "Objects");
    if (rows.len == 0) {
        try ui_widgets.compactInfo(ui, "No objects match filters");
        return;
    }
    const scroll_h = @min(420.0, @max(140.0, try core_ui.layout.remainingPanelContentHeight(ui)));
    try core_ui.layout.beginScrollArea(ui, .{ .id = "ed-layout-scene-results-scroll", .height = scroll_h, .input = core_ui.layout.panel_scroll_input });
    const range = try core_ui.layout.virtualListRange(ui, rows.len, 24);
    try core_ui.layout.virtualListSpacer(ui, range.top_padding);
    for (rows[range.start..range.end]) |entry| {
        const scene_row_text_pad: f32 = 52;
        const indent_per_depth: f32 = 14;
        const icon_size: f32 = 20;
        var obj = &state.objects.items[entry.idx];
        const text_pad = scene_row_text_pad + @as(f32, @floatFromInt(entry.depth)) * indent_per_depth;
        const row_result = try ui_widgets.rowWithTextPad(ui, obj.name, obj.name, state.selected_object == entry.idx, text_pad);
        if (row_result.hovered and ui.input.right_button_pressed) {
            scene_context_menu.open(state, entry.idx, ui.input.mouse_position.x, ui.input.mouse_position.y);
        }
        if (row_result.clicked) {
            state.selected_object = entry.idx;
            state.selected_vertex = null;
            state.selected_edge = null;
            state.selected_face = null;
        }
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
    try core_ui.layout.virtualListSpacer(ui, range.bottom_padding);
    try core_ui.layout.endScrollArea(ui);
    _ = try scene_context_menu.build(ui, state);
}

pub fn buildInspector(ui: *core_ui.UiContext, state: *ProjectEditorState, rect: core_ui.Rect) !void {
    try ui.beginPanel(.{ .id = "ed-inspector-layout", .rect = rect, .row_height = 24, .padding = 10, .spacing = 5 });
    try ui.label("Inspector");
    var hit_field = false;
    if (state.selected_object) |idx| {
        const obj = &state.objects.items[idx];
        try ui.label(obj.name);
        const scroll_h = try core_ui.layout.remainingPanelContentHeight(ui);
        var scrolled = false;
        if (scroll_h > 1) {
            try core_ui.layout.beginScrollArea(ui, .{ .id = "ed-inspector-layout-scroll", .height = scroll_h, .input = core_ui.layout.panel_scroll_input });
            scrolled = true;
        }
        try ui.label("Transform");
        try ui_widgets.transformRow(ui, state, "Pos", .pos_x, .pos_y, .pos_z, obj.position, &hit_field);
        try ui_widgets.transformRow(ui, state, "Rot", .rot_x, .rot_y, .rot_z, obj.rotation, &hit_field);
        try ui_widgets.transformRow(ui, state, "Scale", .scale_x, .scale_y, .scale_z, obj.scale, &hit_field);
        try core_ui.layout.sameLine(ui);
        if ((try ui_widgets.button(ui, "ed-layout-transform-reset", "Reset", 62, false)).clicked) ui_widgets.resetSelectedTransform(state);
        const scale_lock = try core_ui.widgets_input.checkbox(ui, "Uniform", "ed-layout-uniform-scale");
        state.inspector_lock_uniform_scale = scale_lock.checked;
        try core_ui.layout.endSameLine(ui);
        try ui.label("Object");
        if ((try ui_widgets.syncedCheckbox(ui, "Visible", "ed-layout-visible", obj.renderer_visible)).clicked and obj.canModifyObject()) {
            project_editor_edit.pushUndoSnapshot(state);
            obj.renderer_visible = !obj.renderer_visible;
            state.scene_dirty = true;
        }
        if (obj.isImmutable()) {
            _ = try ui_widgets.syncedCheckbox(ui, "Immutable", "ed-layout-immutable", true);
        } else if ((try ui_widgets.syncedCheckbox(ui, "Locked", "ed-layout-locked", obj.locked)).clicked) {
            project_editor_edit.pushUndoSnapshot(state);
            obj.locked = !obj.locked;
        }
        try ui.label("Parent");
        var parent_default: [64]u8 = undefined;
        const parent_text = if (obj.parent_id) |pid| blk: {
            if (project_editor_prop.objectNameById(state, pid)) |name| {
                break :blk std.fmt.bufPrint(&parent_default, "{s}", .{name}) catch "None";
            }
            break :blk std.fmt.bufPrint(&parent_default, "{d}", .{pid}) catch "None";
        } else "None";
        const parent_input = try core_ui.widgets_input.textInput(ui, .{ .id = "ed-layout-parent", .default_text = parent_text });
        if (parent_input.submitted) {
            const resolved = project_editor_prop.resolveParentId(state, parent_input.text);
            project_editor_prop.setParentId(state, resolved);
        }
        var picker_id_buf: [48]u8 = undefined;
        const picker_id = std.fmt.bufPrint(&picker_id_buf, "ed-layout-parent-pick-{d}", .{obj.id}) catch "ed-layout-parent-pick";
        var parent_items: [128]core_ui.widgets_input.SelectItem = undefined;
        var parent_ids: [128]?u64 = undefined;
        var parent_item_count: usize = 0;
        parent_items[parent_item_count] = .{ .id = "parent-none", .label = "None" };
        parent_ids[parent_item_count] = null;
        parent_item_count += 1;
        for (state.objects.items) |candidate| {
            if (parent_item_count >= parent_items.len) break;
            if (candidate.id == obj.id) continue;
            const is_current = obj.parent_id == candidate.id;
            if (!is_current and !scene_hierarchy.canSetParent(state.objects.items, obj.id, candidate.id)) continue;
            var candidate_id_buf: [32]u8 = undefined;
            const candidate_id = std.fmt.bufPrint(&candidate_id_buf, "parent-{d}", .{candidate.id}) catch continue;
            parent_items[parent_item_count] = .{ .id = candidate_id, .label = candidate.name };
            parent_ids[parent_item_count] = candidate.id;
            parent_item_count += 1;
        }
        if (try core_ui.widgets_input.select(ui, picker_id, parent_items[0..parent_item_count])) |picked| {
            var picked_parent: ?u64 = null;
            for (parent_items[0..parent_item_count], parent_ids[0..parent_item_count]) |item, pid| {
                if (std.mem.eql(u8, item.label, picked)) {
                    picked_parent = pid;
                    break;
                }
            }
            project_editor_prop.setParentId(state, picked_parent);
        }
        try ui.label("Layer");
        const layer_input = try core_ui.widgets_input.textInput(ui, .{ .id = "ed-layout-layer", .default_text = project_editor_prop.layerLabel(obj.layer) });
        if (layer_input.submitted) try project_editor_prop.setLayer(state, layer_input.text);
        if (scrolled) try core_ui.layout.endScrollArea(ui);
    } else {
        try core_ui.widgets_feedback.statusLabel(ui, "No selection");
    }
    if (state.focused_field != .none and ui.input.primary_pressed and !hit_field) project_editor_edit.cancelFieldEdit(state);
    ui.endPanel();
}

pub fn buildBottomStrip(ui: *core_ui.UiContext, state: *ProjectEditorState, rect: core_ui.Rect) !void {
    try ui.beginPanel(.{ .id = "ed-bottom-layout", .rect = rect, .row_height = 24, .padding = 6, .spacing = 6 });
    const status = if (state.status_len > 0) state.status_buf[0..state.status_len] else modeStatus;
    try ui_widgets.text(ui, "ed-layout-status", .{ .x = rect.x + 10, .y = rect.y + 5, .w = 300, .h = 22 }, status, true);

    try ui_widgets.rowAt(ui, rect.x + 320, rect.y + 3);
    if ((try ui_widgets.iconButtonTip(ui, "ed-layout-snap", "snap", state.snap_enabled, "Snap")).clicked) project_editor_edit.toggleSnap(state);
    if ((try ui_widgets.button(ui, "ed-layout-grid-minus", "-", 24, false)).clicked) state.snap_size = @max(0.25, state.snap_size * 0.5);
    var grid_buf: [16]u8 = undefined;
    _ = try ui_widgets.button(ui, "ed-layout-grid-label", std.fmt.bufPrint(&grid_buf, "Grid {d:.1}", .{state.snap_size}) catch "Grid 1.0", 72, false);
    if ((try ui_widgets.button(ui, "ed-layout-grid-plus", "+", 24, false)).clicked) state.snap_size = @min(16, state.snap_size * 2);
    const pivot_label = if (state.pivot_mode == .center) "Median" else "Pivot";
    if ((try ui_widgets.button(ui, "ed-layout-pivot", pivot_label, 64, false)).clicked) {
        state.pivot_mode = if (state.pivot_mode == .pivot) .center else .pivot;
    }
    if ((try ui_widgets.button(ui, "ed-layout-space", state.transform_space.label(), 64, false)).clicked) {
        state.transform_space = if (state.transform_space == .world) .local else .world;
    }
    try core_ui.layout.endSameLine(ui);

    var info_buf: [128]u8 = undefined;
    const selected_name = if (state.selected_object) |idx| state.objects.items[idx].name else "No object";
    try ui_widgets.text(ui, "ed-layout-selection", .{ .x = rect.x + rect.w - 320, .y = rect.y + 5, .w = 310, .h = 22 }, std.fmt.bufPrint(&info_buf, "{s}: {s} | Snap {s}", .{ state.selection_scope.label(), selected_name, if (state.snap_enabled) "on" else "off" }) catch selected_name, true);
    try ui_widgets.buildFpsReadout(ui, state, rect);
    ui.endPanel();
}
