const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const project_editor_edit = @import("project_editor_edit.zig");
const command_ids = shared.editor_command_ids;
const project_editor_material_apply = @import("project_editor_material_apply.zig");
const project_editor_materials = @import("project_editor_materials.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_terrain_preview = @import("project_editor_terrain_preview.zig");
const project_editor_types = @import("project_editor_types.zig");
const project_editor_life = @import("project_editor_life.zig");
const scene_hierarchy = @import("editor_scene_hierarchy.zig");
const ui_world = @import("project_editor_ui_world.zig");
const world_authoring = @import("project_editor_world_authoring.zig");

const core_ui = friendly_engine.modules.core_ui;
const ProjectEditorState = project_editor_state.ProjectEditorState;

pub const CheckboxResult = struct { checked: bool, clicked: bool };

pub fn buildMaterialButtons(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    var col: usize = 0;
    for (project_editor_materials.catalog[2..]) |material| {
        if (col == 0) try core_ui.layout.sameLine(ui);
        if ((try materialSwatch(ui, material, state.selected_material == material.id)).clicked) {
            project_editor_material_apply.apply(state, material.id);
        }
        col += 1;
        if (col == 3) {
            try core_ui.layout.endSameLine(ui);
            col = 0;
        }
    }
    if (col != 0) {
        try core_ui.layout.endSameLine(ui);
    }
}

pub fn materialSwatch(ui: *core_ui.UiContext, material: project_editor_materials.MaterialAsset, selected: bool) !core_ui.ButtonResult {
    const rect = try ui.allocRowRect(52, 42);
    const stable = try ui.stableId(material.toolbar_command_id, material.label);
    const click = core_ui.input.handleClick(ui, stable, rect);
    const thumb_rect = core_ui.Rect{
        .x = rect.x + 5,
        .y = rect.y + 4,
        .w = 38,
        .h = 30,
    };
    const text_rect = core_ui.Rect{
        .x = rect.x,
        .y = rect.y,
        .w = 0,
        .h = 0,
    };
    try ui.pushCommand(.{ .asset_preview = .{
        .id = ui.nextCommandId(stable),
        .rect = rect,
        .thumbnail_rect = thumb_rect,
        .text_rect = text_rect,
        .label = "",
        .detail = "",
        .fill_color = toPreviewColor(material.color),
        .accent_color = previewAccent(material.color),
        .shape = .sphere,
        .selected = selected,
        .hovered = click.hovered,
        .active = click.active,
    } });
    try core_ui.widgets_feedback.tooltip(ui, rect, material.label);
    return .{ .id = stable, .rect = rect, .hovered = click.hovered, .clicked = click.clicked };
}

pub fn compactMaterialSwatch(ui: *core_ui.UiContext, id: []const u8, label: []const u8, color: shared.color.Color) !void {
    const rect = try ui.allocFullWidthRow((try ui.currentLayout()).row_height);
    const stable = try ui.stableId(id, label);
    const thumb_rect = core_ui.Rect{
        .x = rect.x + 2,
        .y = rect.y + 3,
        .w = 22,
        .h = 22,
    };
    const text_rect = core_ui.Rect{
        .x = rect.x + 28,
        .y = rect.y + 1,
        .w = rect.w - 30,
        .h = rect.h - 2,
    };
    try ui.pushCommand(.{ .asset_preview = .{
        .id = ui.nextCommandId(stable),
        .rect = rect,
        .thumbnail_rect = thumb_rect,
        .text_rect = text_rect,
        .label = try ui.dupeText(label),
        .detail = "",
        .fill_color = toPreviewColor(color),
        .accent_color = previewAccent(color),
        .shape = .sphere,
        .selected = false,
        .hovered = false,
        .active = false,
    } });
}

pub fn prop(ui: *core_ui.UiContext, state: *ProjectEditorState, label: []const u8, field: project_editor_types.PropField, value: f32, hit: *bool) !void {
    const row_rects = try core_ui.layout.fieldRow(ui, label, 0.78);
    const stable = try ui.stableId(@tagName(field), label);
    const click = core_ui.input.handleClick(ui, stable, row_rects.control_rect);
    hit.* = hit.* or click.hovered;
    if (click.clicked) project_editor_edit.beginFieldEdit(state, field, value);
    var buf: [32]u8 = undefined;
    const display = if (state.focused_field == field) project_editor_edit.fieldInputText(state) else std.fmt.bufPrint(&buf, "{d:.2}", .{value}) catch label;
    try ui.pushCommand(.{ .text_input = .{
        .id = ui.nextCommandId(stable),
        .rect = row_rects.control_rect,
        .text = try ui.dupeText(display),
        .cursor = display.len,
        .focused = state.focused_field == field,
        .hovered = click.hovered,
    } });
}

pub fn transformRow(
    ui: *core_ui.UiContext,
    state: *ProjectEditorState,
    label: []const u8,
    x_field: project_editor_types.PropField,
    y_field: project_editor_types.PropField,
    z_field: project_editor_types.PropField,
    value: shared.editor_math.Vec3,
    hit: *bool,
) !void {
    var x_label: [16]u8 = undefined;
    var y_label: [16]u8 = undefined;
    var z_label: [16]u8 = undefined;
    try prop(ui, state, std.fmt.bufPrint(&x_label, "{s} X", .{label}) catch "X", x_field, value.x, hit);
    try prop(ui, state, std.fmt.bufPrint(&y_label, "{s} Y", .{label}) catch "Y", y_field, value.y, hit);
    try prop(ui, state, std.fmt.bufPrint(&z_label, "{s} Z", .{label}) catch "Z", z_field, value.z, hit);
}

pub fn section(ui: *core_ui.UiContext, label: []const u8) !void {
    _ = try row(ui, label, label, true);
}

pub fn collapsible(ui: *core_ui.UiContext, label: []const u8, default_open: bool) !bool {
    const stable = try ui.stableId(label, label);
    var open = try ui.getBoolState(stable, default_open);
    const rect = try ui.allocFullWidthRow((try ui.currentLayout()).row_height);
    const click = core_ui.input.handleClick(ui, stable, rect);
    if (click.clicked) open = !open;
    try ui.setBoolState(stable, open);
    try ui.pushCommand(.{ .collapsing_header = .{
        .id = ui.nextCommandId(stable),
        .rect = rect,
        .text = try ui.dupeText(label),
        .open = open,
        .hovered = click.hovered,
        .active = click.active,
    } });
    return open;
}

pub fn compactInfo(ui: *core_ui.UiContext, value: []const u8) !void {
    try core_ui.widgets_feedback.statusLabel(ui, value);
}

pub fn layerButton(ui: *core_ui.UiContext, label: []const u8, detail: []const u8) !core_ui.ButtonResult {
    const row_h: f32 = 44;
    const inset: f32 = 12;
    const rect = try ui.allocFullWidthRow(row_h);
    const stable = try ui.stableId(label, label);
    const click = core_ui.input.handleClick(ui, stable, rect);
    try ui.pushCommand(.{ .selectable = .{
        .id = ui.nextCommandId(stable),
        .rect = rect,
        .text = try ui.dupeText(label),
        .text_pad_x = inset,
        .selected = false,
        .hovered = click.hovered,
        .active = click.active,
    } });
    try text(ui, detail, .{ .x = rect.x + inset, .y = rect.y + 26, .w = rect.w - inset * 2, .h = 16 }, detail, true);
    return .{ .id = stable, .rect = rect, .hovered = click.hovered, .clicked = click.clicked };
}

pub fn materialRow(ui: *core_ui.UiContext, material: project_editor_materials.MaterialAsset, selected: bool) !core_ui.ButtonResult {
    const row_h: f32 = 44;
    const inset: f32 = 12;
    const rect = try ui.allocFullWidthRow(row_h);
    const stable = try ui.stableId(material.asset_command_id, material.label);
    const click = core_ui.input.handleClick(ui, stable, rect);
    try ui.pushCommand(.{ .selectable = .{
        .id = ui.nextCommandId(stable),
        .rect = rect,
        .text = try ui.dupeText(material.label),
        .text_pad_x = inset,
        .selected = selected,
        .hovered = click.hovered,
        .active = click.active,
    } });
    try text(ui, material.path, .{ .x = rect.x + inset, .y = rect.y + 26, .w = rect.w - inset * 2, .h = 16 }, material.path, true);
    return .{ .id = stable, .rect = rect, .hovered = click.hovered, .clicked = click.clicked };
}

pub fn row(ui: *core_ui.UiContext, id: []const u8, label: []const u8, selected: bool) !core_ui.ButtonResult {
    return rowWithTextPad(ui, id, label, selected, 8);
}

pub fn rowWithTextPad(ui: *core_ui.UiContext, id: []const u8, label: []const u8, selected: bool, text_pad_x: f32) !core_ui.ButtonResult {
    const rect = try ui.allocFullWidthRow(24);
    const stable = try ui.stableId(id, label);
    const click = core_ui.input.handleClick(ui, stable, rect);
    try ui.pushCommand(.{ .selectable = .{
        .id = ui.nextCommandId(stable),
        .rect = rect,
        .text = try ui.dupeText(label),
        .text_pad_x = text_pad_x,
        .selected = selected,
        .hovered = click.hovered,
        .active = click.active,
    } });
    return .{ .id = stable, .rect = rect, .hovered = click.hovered, .clicked = click.clicked };
}

pub const AssetPreview = struct {
    id: []const u8,
    label: []const u8,
    detail: []const u8 = "",
    fill_color: shared.color.Color,
    shape: core_ui.commands.AssetPreviewShape,
    preview_mask: u16 = 0,
    selected: bool = false,
};

pub fn assetPreview(ui: *core_ui.UiContext, preview: AssetPreview) !core_ui.ButtonResult {
    const row_h: f32 = 58;
    const rect = try ui.allocFullWidthRow(row_h);
    const stable = try ui.stableId(preview.id, preview.label);
    const click = core_ui.input.handleClick(ui, stable, rect);
    const thumb_size: f32 = 44;
    const thumb_rect = core_ui.Rect{
        .x = rect.x + 7,
        .y = rect.y + (rect.h - thumb_size) * 0.5,
        .w = thumb_size,
        .h = thumb_size,
    };
    const text_rect = core_ui.Rect{
        .x = thumb_rect.x + thumb_rect.w + 10,
        .y = rect.y + 7,
        .w = @max(0, rect.w - thumb_rect.w - 24),
        .h = rect.h - 12,
    };
    try ui.pushCommand(.{ .asset_preview = .{
        .id = ui.nextCommandId(stable),
        .rect = rect,
        .thumbnail_rect = thumb_rect,
        .text_rect = text_rect,
        .label = try ui.dupeText(preview.label),
        .detail = try ui.dupeText(preview.detail),
        .fill_color = toPreviewColor(preview.fill_color),
        .accent_color = previewAccent(preview.fill_color),
        .shape = preview.shape,
        .preview_mask = preview.preview_mask,
        .selected = preview.selected,
        .hovered = click.hovered,
        .active = click.active,
    } });
    return .{ .id = stable, .rect = rect, .hovered = click.hovered, .clicked = click.clicked };
}

pub fn treeRow(ui: *core_ui.UiContext, label: []const u8, open: *bool) !core_ui.ButtonResult {
    const stable = try ui.stableId(label, label);
    const rect = try ui.allocFullWidthRow(24);
    const click = core_ui.input.handleClick(ui, stable, rect);
    if (click.clicked) open.* = !open.*;
    try ui.pushCommand(.{ .collapsing_header = .{
        .id = ui.nextCommandId(stable),
        .rect = rect,
        .text = try ui.dupeText(label),
        .open = open.*,
        .hovered = click.hovered,
        .active = click.active,
    } });
    return .{ .id = stable, .rect = rect, .hovered = click.hovered, .clicked = click.clicked };
}

fn toPreviewColor(color: shared.color.Color) core_ui.commands.PreviewColor {
    return .{ .r = color.r, .g = color.g, .b = color.b, .a = color.a };
}

fn previewAccent(color: shared.color.Color) core_ui.commands.PreviewColor {
    return .{
        .r = @min(255, @as(u16, color.r) + 34),
        .g = @min(255, @as(u16, color.g) + 34),
        .b = @min(255, @as(u16, color.b) + 34),
        .a = color.a,
    };
}

pub fn button(ui: *core_ui.UiContext, id: []const u8, label: []const u8, width: f32, active: bool) !core_ui.ButtonResult {
    const rect = try ui.allocRowRect(width, (try ui.currentLayout()).row_height);
    const stable = try ui.stableId(id, label);
    const click = core_ui.input.handleClick(ui, stable, rect);
    try ui.pushCommand(.{ .button = .{ .id = ui.nextCommandId(stable), .rect = rect, .text = try ui.dupeText(label), .hovered = click.hovered, .active = click.active or active } });
    return .{ .id = stable, .rect = rect, .hovered = click.hovered, .clicked = click.clicked };
}

pub fn buttonTip(ui: *core_ui.UiContext, id: []const u8, label: []const u8, width: f32, active: bool, tip: []const u8) !core_ui.ButtonResult {
    const result = try button(ui, id, label, width, active);
    try core_ui.widgets_feedback.tooltip(ui, result.rect, tip);
    return result;
}

pub fn iconButtonTip(ui: *core_ui.UiContext, id: []const u8, icon: []const u8, active: bool, tip: []const u8) !core_ui.ButtonResult {
    const rect = try ui.allocRowRect(32, (try ui.currentLayout()).row_height);
    const stable = try ui.stableId(id, icon);
    const click = core_ui.input.handleClick(ui, stable, rect);
    try ui.pushCommand(.{ .icon_button = .{
        .id = ui.nextCommandId(stable),
        .rect = rect,
        .icon = try ui.dupeText(icon),
        .hovered = click.hovered,
        .active = click.active,
        .toggled = active,
    } });
    try core_ui.widgets_feedback.tooltip(ui, rect, tip);
    return .{ .id = stable, .rect = rect, .hovered = click.hovered, .clicked = click.clicked };
}

pub fn flowIconButtonTip(ui: *core_ui.UiContext, id: []const u8, icon: []const u8, active: bool, tip: []const u8) !core_ui.ButtonResult {
    const width: f32 = 32;
    try wrapSameLineBefore(ui, width);
    return iconButtonTip(ui, id, icon, active, tip);
}

fn wrapSameLineBefore(ui: *core_ui.UiContext, width: f32) !void {
    const cursor = try ui.currentLayout();
    if (!cursor.same_line) return;
    if (cursor.cursor_x <= cursor.content_x) return;
    const right = cursor.content_x + cursor.content_w;
    if (cursor.cursor_x + width <= right) return;
    cursor.same_line_y += cursor.row_height + cursor.spacing;
    cursor.cursor_x = cursor.content_x;
    cursor.cursor_y = cursor.same_line_y;
}

pub fn iconOverlayButton(ui: *core_ui.UiContext, id: []const u8, icon: []const u8, rect: core_ui.Rect, toggled: bool) !core_ui.ButtonResult {
    const stable = try ui.stableId(id, icon);
    const click = core_ui.input.handleClick(ui, stable, rect);
    try ui.pushCommand(.{ .icon_button = .{
        .id = ui.nextCommandId(stable),
        .rect = rect,
        .icon = try ui.dupeText(icon),
        .hovered = click.hovered,
        .active = click.active,
        .toggled = toggled,
    } });
    return .{ .id = stable, .rect = rect, .hovered = click.hovered, .clicked = click.clicked };
}

pub fn overlayTextButton(ui: *core_ui.UiContext, id: []const u8, text_value: []const u8, rect: core_ui.Rect, active: bool) !core_ui.ButtonResult {
    const stable = try ui.stableId(id, text_value);
    const click = core_ui.input.handleClick(ui, stable, rect);
    try ui.pushCommand(.{ .button = .{
        .id = ui.nextCommandId(stable),
        .rect = rect,
        .text = try ui.dupeText(text_value),
        .hovered = click.hovered,
        .active = click.active or active,
    } });
    return .{ .id = stable, .rect = rect, .hovered = click.hovered, .clicked = click.clicked };
}

pub fn rowAt(ui: *core_ui.UiContext, x: f32, y: f32) !void {
    const cursor = try ui.currentLayout();
    cursor.same_line = true;
    cursor.same_line_y = y;
    cursor.cursor_x = x;
    cursor.cursor_y = y;
}

pub fn text(ui: *core_ui.UiContext, id: []const u8, rect: core_ui.Rect, value: []const u8, muted: bool) !void {
    const stable = try ui.stableId(id, id);
    try ui.pushCommand(.{ .text = .{ .id = ui.nextCommandId(stable), .rect = rect, .text = try ui.dupeText(value), .muted = muted } });
}

pub fn richText(ui: *core_ui.UiContext, id: []const u8, rect: core_ui.Rect, spans: []const core_ui.rich_text.Span, muted: bool) !void {
    const stable = try ui.stableId(id, id);
    try ui.pushCommand(.{ .text = .{
        .id = ui.nextCommandId(stable),
        .rect = rect,
        .text = "",
        .spans = try ui.dupeRichText(spans),
        .muted = muted,
    } });
}

pub fn writeLayer(state: *ProjectEditorState, func: *const fn (*ProjectEditorState) anyerror!void, ok: []const u8, err: []const u8) !void {
    const dirty_before = state.dirty_cells.total_marks;
    func(state) catch {
        project_editor_state.setStatus(state, err);
        return;
    };
    if (state.dirty_cells.total_marks == dirty_before) project_editor_state.setStatus(state, ok);
}

pub fn renderStats(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    try section(ui, "Render");
    var command_buf: [96]u8 = undefined;
    try core_ui.widgets_feedback.statusLabel(ui, std.fmt.bufPrint(&command_buf, "Commands {d}  Mesh {d}  Grid {d}", .{ state.render_command_stats.total, state.render_command_stats.meshes, state.render_command_stats.grids }) catch "Commands");
    var visibility_buf: [96]u8 = undefined;
    try core_ui.widgets_feedback.statusLabel(ui, std.fmt.bufPrint(&visibility_buf, "Visible {d}/{d}  Batches {d}", .{ state.visibility_stats.visible_meshes, state.objects.items.len, state.visibility_stats.emitted_batches }) catch "Visible");
}

pub const fps_readout_w: f32 = 72;
pub const fps_readout_right_pad: f32 = 8;
pub const fps_readout_reserved_w: f32 = fps_readout_w + fps_readout_right_pad;

pub fn buildFpsReadout(ui: *core_ui.UiContext, state: *ProjectEditorState, rect: core_ui.Rect) !void {
    var fps_buf: [32]u8 = undefined;
    const fps_text = std.fmt.bufPrint(&fps_buf, "{d:.0} FPS", .{state.fps}) catch "FPS";
    try text(ui, "ed-fps", .{
        .x = rect.x + rect.w - fps_readout_w - fps_readout_right_pad,
        .y = rect.y + 5,
        .w = fps_readout_w,
        .h = 22,
    }, fps_text, true);
}

pub fn physicsSelected(obj: *const @import("editor_scene_object.zig").SceneObject, kind: shared.scene_physics.BodyKind) bool {
    return if (obj.physics) |body| body.kind == kind else false;
}

pub fn saveScene(state: *ProjectEditorState) !void {
    state.saveSceneToDisk() catch {
        project_editor_state.setStatus(state, "Scene save failed");
        return;
    };
    state.scene_dirty = false;
    project_editor_state.setStatus(state, "Scene saved");
}

pub fn resetSelectedTransform(state: *ProjectEditorState) void {
    const idx = state.selected_object orelse return;
    const obj = &state.objects.items[idx];
    if (!obj.canModifyObject()) return;
    project_editor_edit.pushUndoSnapshot(state);
    obj.position = .{ .x = 0, .y = 0, .z = 0 };
    obj.rotation = .{ .x = 0, .y = 0, .z = 0 };
    obj.scale = .{ .x = 1, .y = 1, .z = 1 };
    project_editor_state.setStatus(state, "Transform reset");
}

pub fn resetCameraToOrigin(state: *ProjectEditorState) void {
    state.camera = .{ .target = .{ .x = 0, .y = 0, .z = 0 } };
    state.view_orientation = .free;
    project_editor_state.setStatus(state, "View reset to origin");
}

pub fn snapCameraToTerrainHeight(state: *ProjectEditorState) !void {
    const target = state.camera.target;
    const terrain_y = project_editor_terrain_preview.sampleHeightAtPoint(state, target) catch |err| switch (err) {
        error.WorldCellNotInManifest, error.TerrainTileNotFound => {
            project_editor_state.setStatus(state, "View snap rejected: no terrain tile here");
            return;
        },
        else => return err,
    };
    state.camera.target = .{ .x = target.x, .y = terrain_y + 6.0, .z = target.z };
    state.view_orientation = .free;
    project_editor_state.setStatus(state, "View snapped 6m above terrain");
}

pub fn frameSelected(state: *ProjectEditorState) void {
    const idx = state.selected_object orelse {
        project_editor_state.setStatus(state, "Nothing selected");
        return;
    };
    const objects = state.objects.items;
    state.camera.target = scene_hierarchy.objectWorldPosition(objects, idx);
    const bounds = scene_hierarchy.objectWorldBounds(objects, idx);
    const extent_x = bounds.max.x - bounds.min.x;
    const extent_y = bounds.max.y - bounds.min.y;
    const extent_z = bounds.max.z - bounds.min.z;
    const radius = @max(@max(extent_x, extent_y), extent_z) * 0.5;
    state.camera.distance = std.math.clamp(@max(radius * 3.0, 1.5), 1.5, state.camera.max_distance);
    project_editor_state.setStatus(state, "Selection framed");
}

pub fn currentToolLabel(state: *const ProjectEditorState) []const u8 {
    return switch (state.mode) {
        .world_creation => ui_world.currentToolLabel(state),
        .layout => state.object_tool.label(),
        .architecture_creation => state.architecture_tool.label(),
        .prop_creation => state.prop_workspace_mode.label(),
        .life => state.life_tool.label(),
    };
}

pub fn toolTip(tool: project_editor_types.ObjectTool) []const u8 {
    return switch (tool) {
        .select => "Select",
        .move => "W Move",
        .rotate => "E Rotate",
        .scale => "R Scale",
    };
}

pub fn toolIcon(tool: project_editor_types.ObjectTool) []const u8 {
    return switch (tool) {
        .select => "select",
        .move => "move",
        .rotate => "rotate",
        .scale => "scale",
    };
}

pub fn syncedCheckbox(ui: *core_ui.UiContext, label_text: []const u8, explicit_id: []const u8, value: bool) !CheckboxResult {
    const stable = try ui.stableId(explicit_id, label_text);
    try ui.setBoolState(stable, value);
    const result = try core_ui.widgets_input.checkbox(ui, label_text, explicit_id);
    return .{ .checked = result.checked, .clicked = result.clicked };
}

pub fn objectTypeLabel(obj: anytype) []const u8 {
    if (obj.object_kind != .mesh) return obj.object_kind.label();
    return switch (obj.primitive_kind orelse .box) {
        .box => if (obj.primitive_kind == null) "mesh" else "box",
        .plane => "plane",
        .cylinder => "cyl",
        .sphere => "sphere",
    };
}

pub fn addComponent(state: *ProjectEditorState) !void {
    const idx = state.selected_object orelse {
        project_editor_state.setStatus(state, "No selection");
        return;
    };
    project_editor_edit.pushUndoSnapshot(state);
    const obj = &state.objects.items[idx];
    const next = try state.allocator.alloc([]u8, obj.components.len + 1);
    for (obj.components, 0..) |component, component_idx| next[component_idx] = component;
    const name = try std.fmt.allocPrint(state.allocator, "Component {d}", .{obj.components.len + 1});
    next[obj.components.len] = name;
    state.allocator.free(obj.components);
    obj.components = next;
    state.scene_dirty = true;
    project_editor_state.setStatus(state, "Component added");
}

pub fn removeComponent(state: *ProjectEditorState, remove_index: usize) !void {
    const idx = state.selected_object orelse return;
    project_editor_edit.pushUndoSnapshot(state);
    const obj = &state.objects.items[idx];
    if (remove_index >= obj.components.len) return;
    state.allocator.free(obj.components[remove_index]);
    const next = try state.allocator.alloc([]u8, obj.components.len - 1);
    var write_index: usize = 0;
    for (obj.components, 0..) |component, component_idx| {
        if (component_idx == remove_index) continue;
        next[write_index] = component;
        write_index += 1;
    }
    state.allocator.free(obj.components);
    obj.components = next;
    state.scene_dirty = true;
    project_editor_state.setStatus(state, "Component removed");
}

pub fn matchesFilter(ui: *core_ui.UiContext, id: []const u8, text_value: []const u8) bool {
    const stable = ui.stableId(id, id) catch return true;
    const state = ui.persistent.get(stable) orelse return true;
    switch (state) {
        .text => |entry| {
            if (entry.buffer.len == 0) return true;
            return containsIgnoreCase(text_value, entry.buffer);
        },
        else => return true,
    }
}

pub fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[i .. i + needle.len], needle)) return true;
    }
    return false;
}

pub fn modeHint(state: *const ProjectEditorState) []const u8 {
    return switch (state.mode) {
        .world_creation => ui_world.modeHint(state),
        .layout => "Layout mode: select and transform objects",
        .architecture_creation => switch (state.architecture_tool) {
            .brush, .add, .subtract => if (state.blockout_op == .add) "Drag to add brush boxes" else "Drag to subtract",
            .ramp => "Click viewport to place ramp",
            else => "Click or drag architecture geometry",
        },
        .prop_creation => "Prop mode: create, texture, edit, and configure props",
        .life => "Life mode: pose and animate objects or bones",
    };
}
