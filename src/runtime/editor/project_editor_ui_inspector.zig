const std = @import("std");
const friendly_engine = @import("friendly_engine");
const project_editor_edit = @import("project_editor_edit.zig");
const project_editor_marker = @import("project_editor_marker.zig");
const project_editor_prop = @import("project_editor_prop.zig");
const project_editor_state = @import("project_editor_state.zig");
const shared = @import("runtime_shared");
const ui_widgets = @import("project_editor_ui_widgets.zig");
const ui_architecture = @import("project_editor_ui_architecture.zig");
const ui_build_left = @import("project_editor_ui_build_left.zig");
const ui_world = @import("project_editor_ui_world.zig");
const ui_prop = @import("project_editor_ui_prop.zig");

const core_ui = friendly_engine.modules.core_ui;
const ProjectEditorState = project_editor_state.ProjectEditorState;
const SceneObject = @import("editor_scene_object.zig").SceneObject;
const scene_marker = shared.scene_marker;

pub fn buildRightInspector(ui: *core_ui.UiContext, state: *ProjectEditorState, rect: core_ui.Rect) !void {
    if (state.mode == .world_creation or state.mode == .architecture_creation or state.mode == .prop_creation) {
        try buildInspector(ui, state, rect);
        return;
    }
    try ui.beginPanel(.{ .id = "ed-inspector", .rect = rect, .row_height = 24, .padding = 10, .spacing = 5, .inline_spacing = 5 });
    try inspectorHeader(ui, state, "Project Inspector", 24);
    const scroll_h = try core_ui.layout.remainingPanelContentHeight(ui);
    var scrolled = false;
    if (scroll_h > 1) {
        try core_ui.layout.beginScrollArea(ui, .{ .id = "ed-right-inspector-scroll", .height = scroll_h, .input = core_ui.layout.panel_scroll_input });
        scrolled = true;
    }
    if (state.selected_object != null) {
        try ui.label("Selection");
        try buildSelectionPanel(ui, state, rect);
        try ui.label("Project");
        try ui_build_left.buildProjectPanel(ui, state);
    } else {
        try ui.label("Project");
        try ui_build_left.buildProjectPanel(ui, state);
        try ui.label("Selection");
        try buildSelectionPanel(ui, state, rect);
    }
    if (scrolled) try core_ui.layout.endScrollArea(ui);
    ui.endPanel();
}

pub fn buildInspector(ui: *core_ui.UiContext, state: *ProjectEditorState, rect: core_ui.Rect) !void {
    try ui.beginPanel(.{ .id = "ed-inspector", .rect = rect, .row_height = 26, .padding = 12, .spacing = 6, .inline_spacing = 5 });
    try inspectorHeader(ui, state, inspectorTitle(state.mode), 26);
    var hit_field = false;
    if (state.selected_object) |idx| try buildObjectHeader(ui, state, &state.objects.items[idx]);
    const scroll_h = try core_ui.layout.remainingPanelContentHeight(ui);
    var scrolled = false;
    if (scroll_h > 1) {
        try core_ui.layout.beginScrollArea(ui, .{ .id = "ed-inspector-scroll", .height = scroll_h, .input = core_ui.layout.panel_scroll_input });
        scrolled = true;
    }
    switch (state.mode) {
        .world_creation => try buildWorldInspector(ui, state, &hit_field),
        .architecture_creation => try buildArchitectureInspector(ui, state, &hit_field),
        .prop_creation => try buildPropInspector(ui, state, &hit_field),
        .layout, .life => unreachable,
    }
    if (scrolled) try core_ui.layout.endScrollArea(ui);
    if (state.focused_field != .none and ui.input.primary_pressed and !hit_field) project_editor_edit.cancelFieldEdit(state);
    ui.endPanel();
}

fn inspectorHeader(ui: *core_ui.UiContext, state: *ProjectEditorState, title: []const u8, height: f32) !void {
    const header_rect = try ui.allocFullWidthRow(height);
    try ui_widgets.text(ui, "ed-right-title", header_rect, title, false);
    const hide_rect = core_ui.Rect{ .x = header_rect.x + header_rect.w - 24, .y = header_rect.y, .w = 24, .h = 24 };
    const hide = try ui_widgets.iconOverlayButton(ui, "ed-right-hide", "eye-closed", hide_rect, false);
    if (hide.clicked) state.show_project_inspector = false;
    try core_ui.widgets_feedback.tooltip(ui, hide.rect, "Hide project inspector");
}

fn buildSelectionPanel(ui: *core_ui.UiContext, state: *ProjectEditorState, rect: core_ui.Rect) !void {
    var hit_field = false;
    if (state.selected_object) |idx| {
        const obj = &state.objects.items[idx];
        _ = rect;
        try buildObjectHeader(ui, state, obj);
        try buildMultiSelectionSummary(ui, state);
        if (obj.marker != null) {
            try buildMarkerSection(ui, state, obj);
            try buildTransformSection(ui, state, obj, &hit_field);
            try buildObjectSection(ui, state, obj);
        } else {
            try buildTransformSection(ui, state, obj, &hit_field);
            try buildObjectSection(ui, state, obj);
            try buildMarkerSection(ui, state, obj);
        }
        switch (state.mode) {
            .world_creation => {},
            .layout => try buildLayoutSelectionSection(ui, state, obj),
            .architecture_creation => try ui_architecture.buildInspectorSections(ui, state),
            .prop_creation => try ui_prop.buildInspector(ui, state),
            .life => try buildLifeSelectionSection(ui, state, obj),
        }
        if ((try ui_widgets.collapsible(ui, "Render", false))) try ui_widgets.renderStats(ui, state);
    } else {
        try core_ui.widgets_feedback.statusLabel(ui, "No selection");
        switch (state.mode) {
            .architecture_creation => try ui_architecture.buildInspectorSections(ui, state),
            .prop_creation => try ui_prop.buildInspector(ui, state),
            else => {},
        }
    }
    if (state.focused_field != .none and ui.input.primary_pressed and !hit_field) project_editor_edit.cancelFieldEdit(state);
}

fn buildMultiSelectionSummary(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    if (state.selected_object_ids.items.len <= 1) return;
    var buf: [96]u8 = undefined;
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&buf, "{d} selected", .{state.selected_object_ids.items.len}) catch "Multiple selected");
}

fn inspectorTitle(mode: project_editor_state.EditorMode) []const u8 {
    return switch (mode) {
        .world_creation => "World Inspector",
        .layout => "Inspector",
        .architecture_creation => "Architecture Inspector",
        .prop_creation => "Prop Inspector",
        .life => "Life Inspector",
    };
}

fn buildObjectHeader(ui: *core_ui.UiContext, state: *ProjectEditorState, obj: *SceneObject) !void {
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.syncedCheckbox(ui, "On", "ed-object-enabled", obj.enabled)).clicked and !obj.isImmutable()) {
        project_editor_edit.pushUndoSnapshot(state);
        obj.enabled = !obj.enabled;
        state.scene_dirty = true;
    }
    _ = try ui_widgets.button(ui, "ed-object-type", ui_widgets.objectTypeLabel(obj), 82, false);
    try core_ui.layout.endSameLine(ui);
    try ui.label(obj.name);
}

fn buildTransformSection(ui: *core_ui.UiContext, state: *ProjectEditorState, obj: *SceneObject, hit_field: *bool) !void {
    if ((try ui_widgets.collapsible(ui, "Transform", true))) {
        try ui_widgets.transformRow(ui, state, "Pos", .pos_x, .pos_y, .pos_z, obj.position, hit_field);
        try ui_widgets.transformRow(ui, state, "Rot", .rot_x, .rot_y, .rot_z, obj.rotation, hit_field);
        try ui_widgets.transformRow(ui, state, "Scale", .scale_x, .scale_y, .scale_z, obj.scale, hit_field);
        try core_ui.layout.sameLine(ui);
        if ((try ui_widgets.button(ui, "ed-transform-reset", "Reset", 62, false)).clicked) ui_widgets.resetSelectedTransform(state);
        const scale_lock = try core_ui.widgets_input.checkbox(ui, "Uniform", "ed-uniform-scale");
        state.inspector_lock_uniform_scale = scale_lock.checked;
        try core_ui.layout.endSameLine(ui);
    }
}

fn buildArchitectureInspector(ui: *core_ui.UiContext, state: *ProjectEditorState, hit_field: *bool) !void {
    if (state.selected_object) |idx| {
        try buildTransformSection(ui, state, &state.objects.items[idx], hit_field);
        try ui_architecture.buildInspectorSections(ui, state);
        if ((try ui_widgets.collapsible(ui, "Render", false))) try ui_widgets.renderStats(ui, state);
        return;
    }
    try ui_architecture.buildInspectorSections(ui, state);
}

fn buildWorldInspector(ui: *core_ui.UiContext, state: *ProjectEditorState, hit_field: *bool) !void {
    try ui_world.buildInspector(ui, state);
    if (state.selected_object) |idx| {
        if ((try ui_widgets.collapsible(ui, "Selection", false))) {
            try buildTransformSection(ui, state, &state.objects.items[idx], hit_field);
            try buildObjectSection(ui, state, &state.objects.items[idx]);
        }
    }
}

fn buildPropInspector(ui: *core_ui.UiContext, state: *ProjectEditorState, hit_field: *bool) !void {
    if (state.selected_object) |idx| {
        try ui_prop.buildInspector(ui, state);
        if ((try ui_widgets.collapsible(ui, "Transform", false))) {
            try ui_widgets.transformRow(ui, state, "Pos", .pos_x, .pos_y, .pos_z, state.objects.items[idx].position, hit_field);
            try ui_widgets.transformRow(ui, state, "Rot", .rot_x, .rot_y, .rot_z, state.objects.items[idx].rotation, hit_field);
            try ui_widgets.transformRow(ui, state, "Scale", .scale_x, .scale_y, .scale_z, state.objects.items[idx].scale, hit_field);
        }
        if ((try ui_widgets.collapsible(ui, "Render", false))) try ui_widgets.renderStats(ui, state);
        return;
    }
    try ui_prop.buildInspector(ui, state);
}

fn buildObjectSection(ui: *core_ui.UiContext, state: *ProjectEditorState, obj: *SceneObject) !void {
    if ((try ui_widgets.collapsible(ui, "Object", true))) {
        if ((try ui_widgets.syncedCheckbox(ui, "Visible", "ed-right-visible", obj.renderer_visible)).clicked and obj.canModifyObject()) {
            project_editor_edit.pushUndoSnapshot(state);
            obj.renderer_visible = !obj.renderer_visible;
            state.scene_dirty = true;
        }
        if (obj.isImmutable()) {
            _ = try ui_widgets.syncedCheckbox(ui, "Immutable", "ed-right-immutable", true);
        } else if ((try ui_widgets.syncedCheckbox(ui, "Locked", "ed-right-locked", obj.locked)).clicked) {
            project_editor_edit.pushUndoSnapshot(state);
            obj.locked = !obj.locked;
        }
        var id_buf: [64]u8 = undefined;
        try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&id_buf, "Id {d}", .{obj.id}) catch "Id");
        try ui_widgets.compactInfo(ui, ui_widgets.objectTypeLabel(obj));
    }
}

fn buildMarkerSection(ui: *core_ui.UiContext, state: *ProjectEditorState, obj: *SceneObject) !void {
    const marker = obj.marker orelse return;
    if ((try ui_widgets.collapsible(ui, "Marker", true))) {
        var shape_buf: [80]u8 = undefined;
        try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&shape_buf, "Current {s}  {s}", .{ marker.kind.label(), marker.shape.name() }) catch "Marker");
        var requirement_buf: [128]u8 = undefined;
        try ui_widgets.compactInfo(ui, markerRequirementLine(marker.kind, &requirement_buf));
        try ui.label("Shape");
        try markerShapeRow(ui, state, marker.shape);
        try buildMarkerPrimaryFields(ui, state, obj, marker);
        try buildMarkerKindChanger(ui, state, marker.kind);
        try buildMarkerAdvancedFields(ui, state, obj, marker);

        if (obj.marker) |edited_marker| {
            edited_marker.validate() catch |err| {
                var err_buf: [96]u8 = undefined;
                try core_ui.widgets_feedback.statusLabel(ui, std.fmt.bufPrint(&err_buf, "Invalid marker: {s}", .{@errorName(err)}) catch "Invalid marker");
                return;
            };
        } else {
            var err_buf: [96]u8 = undefined;
            try core_ui.widgets_feedback.statusLabel(ui, std.fmt.bufPrint(&err_buf, "Invalid marker: {s}", .{@errorName(error.NoSelectedMarker)}) catch "Invalid marker");
            return;
        }
        try core_ui.widgets_feedback.statusLabel(ui, "Marker valid");
    }
}

fn buildMarkerKindChanger(ui: *core_ui.UiContext, state: *ProjectEditorState, current: scene_marker.Kind) !void {
    if (!(try ui_widgets.collapsible(ui, "Change Marker Type", false))) return;
    try markerKindRow(ui, state, current);
}

fn buildMarkerPrimaryFields(ui: *core_ui.UiContext, state: *ProjectEditorState, obj: *SceneObject, marker: scene_marker.Marker) !void {
    if (markerUsesMarkerId(marker.kind)) try markerIdField(ui, state, obj.id, marker.marker_id);
    if (markerUsesGroup(marker.kind)) try markerGroupField(ui, state, obj.id, marker.group);
    if (markerUsesBinding(marker.kind)) try markerBindingField(ui, state, obj.id, marker.binding);
    if (markerUsesRadius(marker.kind, marker.shape)) try markerRadiusField(ui, state, obj.id, marker.radius);
    if (markerUsesOrder(marker.kind)) try markerOrderField(ui, state, obj.id, marker.order);
}

fn buildMarkerAdvancedFields(ui: *core_ui.UiContext, state: *ProjectEditorState, obj: *SceneObject, marker: scene_marker.Marker) !void {
    if (!(try ui_widgets.collapsible(ui, "Advanced Marker Fields", false))) return;
    if (!markerUsesMarkerId(marker.kind)) try markerIdField(ui, state, obj.id, marker.marker_id);
    if (!markerUsesGroup(marker.kind)) try markerGroupField(ui, state, obj.id, marker.group);
    if (!markerUsesBinding(marker.kind)) try markerBindingField(ui, state, obj.id, marker.binding);
    if (!markerUsesRadius(marker.kind, marker.shape)) try markerRadiusField(ui, state, obj.id, marker.radius);
    if (!markerUsesOrder(marker.kind)) try markerOrderField(ui, state, obj.id, marker.order);
}

fn markerIdField(ui: *core_ui.UiContext, state: *ProjectEditorState, object_id: u64, value: []const u8) !void {
    try ui.label("Marker Id");
    var id_input_buf: [96]u8 = undefined;
    const id_input = try core_ui.widgets_input.textInput(ui, .{ .id = markerTextInputId(&id_input_buf, "ed-marker-id", object_id, value), .default_text = value });
    if (id_input.submitted) {
        project_editor_marker.setSelectedMarkerId(state, id_input.text) catch project_editor_state.setStatus(state, "Marker id update failed");
    }
}

fn markerGroupField(ui: *core_ui.UiContext, state: *ProjectEditorState, object_id: u64, value: []const u8) !void {
    try ui.label("Group");
    var group_input_buf: [96]u8 = undefined;
    const group_input = try core_ui.widgets_input.textInput(ui, .{ .id = markerTextInputId(&group_input_buf, "ed-marker-group", object_id, value), .default_text = value });
    if (group_input.submitted) {
        project_editor_marker.setSelectedGroup(state, group_input.text) catch project_editor_state.setStatus(state, "Marker group update failed");
    }
}

fn markerBindingField(ui: *core_ui.UiContext, state: *ProjectEditorState, object_id: u64, value: []const u8) !void {
    try ui.label("Binding");
    var binding_input_buf: [96]u8 = undefined;
    const binding_input = try core_ui.widgets_input.textInput(ui, .{ .id = markerTextInputId(&binding_input_buf, "ed-marker-binding", object_id, value), .default_text = value });
    if (binding_input.submitted) {
        project_editor_marker.setSelectedBinding(state, binding_input.text) catch project_editor_state.setStatus(state, "Marker binding update failed");
    }
}

fn markerRadiusField(ui: *core_ui.UiContext, state: *ProjectEditorState, object_id: u64, value: f32) !void {
    try ui.label("Radius");
    var radius_input_buf: [96]u8 = undefined;
    const radius = try core_ui.widgets_input.numberInput(ui, .{
        .id = markerFloatInputId(&radius_input_buf, "ed-marker-radius", object_id, value),
        .value = value,
        .min = 0.001,
        .max = 1000.0,
        .speed = 0.05,
    });
    if (radius.changed and @abs(radius.value - value) > 0.0001) {
        project_editor_marker.setSelectedRadius(state, radius.value) catch project_editor_state.setStatus(state, "Marker radius update failed");
    }
}

fn markerOrderField(ui: *core_ui.UiContext, state: *ProjectEditorState, object_id: u64, value: i32) !void {
    try ui.label("Order");
    var order_input_buf: [96]u8 = undefined;
    const order = try core_ui.widgets_input.numberInput(ui, .{
        .id = std.fmt.bufPrint(&order_input_buf, "ed-marker-order-{d}-{d}", .{ object_id, value }) catch "ed-marker-order",
        .value = @floatFromInt(value),
        .min = -10000.0,
        .max = 10000.0,
        .speed = 1.0,
    });
    const order_value: i32 = @intFromFloat(@round(order.value));
    if (order.changed and order_value != value) {
        project_editor_marker.setSelectedOrder(state, order_value) catch project_editor_state.setStatus(state, "Marker order update failed");
    }
}

fn markerRequirementLine(kind: scene_marker.Kind, buf: []u8) []const u8 {
    _ = buf;
    return switch (kind) {
        .player_start => "Required: binding",
        .objective, .checkpoint, .region_anchor => "Required: marker id",
        .patrol_point => "Required: group",
        else => "Required: none",
    };
}

fn markerUsesMarkerId(kind: scene_marker.Kind) bool {
    return switch (kind) {
        .objective, .checkpoint, .region_anchor, .item_spawn, .interactable_anchor => true,
        else => false,
    };
}

fn markerUsesGroup(kind: scene_marker.Kind) bool {
    return switch (kind) {
        .spawn_point, .encounter_spawn, .patrol_point, .nav_point => true,
        else => false,
    };
}

fn markerUsesBinding(kind: scene_marker.Kind) bool {
    return switch (kind) {
        .player_start, .camera_point, .audio_emitter, .interactable_anchor, .item_spawn => true,
        else => false,
    };
}

fn markerUsesRadius(kind: scene_marker.Kind, shape: scene_marker.Shape) bool {
    return switch (kind) {
        .trigger_volume, .audio_emitter, .region_anchor => true,
        else => shape != .point,
    };
}

fn markerUsesOrder(kind: scene_marker.Kind) bool {
    return switch (kind) {
        .patrol_point, .nav_point, .checkpoint => true,
        else => false,
    };
}

fn markerKindRow(ui: *core_ui.UiContext, state: *ProjectEditorState, current: scene_marker.Kind) !void {
    inline for (std.meta.fields(scene_marker.Kind)) |field| {
        try core_ui.layout.sameLine(ui);
        const kind: scene_marker.Kind = @enumFromInt(field.value);
        try markerKindButton(ui, state, kind, current);
        try core_ui.layout.endSameLine(ui);
    }
}

fn markerShapeRow(ui: *core_ui.UiContext, state: *ProjectEditorState, current: scene_marker.Shape) !void {
    try core_ui.layout.sameLine(ui);
    try markerShapeButton(ui, state, .point, "Point", current);
    try markerShapeButton(ui, state, .box, "Box", current);
    try markerShapeButton(ui, state, .sphere, "Sphere", current);
    try markerShapeButton(ui, state, .path, "Path", current);
    try core_ui.layout.endSameLine(ui);
}

fn markerKindButton(ui: *core_ui.UiContext, state: *ProjectEditorState, kind: scene_marker.Kind, current: scene_marker.Kind) !void {
    var id_buf: [64]u8 = undefined;
    if ((try ui_widgets.button(ui, std.fmt.bufPrint(&id_buf, "ed-marker-kind-{s}", .{kind.name()}) catch "ed-marker-kind", kind.label(), markerKindButtonWidth(kind), kind == current)).clicked) {
        project_editor_marker.setSelectedKind(state, kind) catch project_editor_state.setStatus(state, "Marker kind update failed");
    }
}

fn markerKindButtonWidth(kind: scene_marker.Kind) f32 {
    _ = kind;
    return 236;
}

fn markerShapeButton(ui: *core_ui.UiContext, state: *ProjectEditorState, shape: scene_marker.Shape, label: []const u8, current: scene_marker.Shape) !void {
    var id_buf: [64]u8 = undefined;
    if ((try ui_widgets.button(ui, std.fmt.bufPrint(&id_buf, "ed-marker-shape-{s}", .{shape.name()}) catch "ed-marker-shape", label, markerShapeButtonWidth(shape), shape == current)).clicked) {
        project_editor_marker.setSelectedShape(state, shape) catch project_editor_state.setStatus(state, "Marker shape update failed");
    }
}

fn markerShapeButtonWidth(shape: scene_marker.Shape) f32 {
    return switch (shape) {
        .sphere => 78,
        else => 66,
    };
}

fn markerTextInputId(buf: []u8, prefix: []const u8, object_id: u64, value: []const u8) []const u8 {
    return std.fmt.bufPrint(buf, "{s}-{d}-{x}", .{ prefix, object_id, std.hash.Wyhash.hash(0, value) }) catch prefix;
}

fn markerFloatInputId(buf: []u8, prefix: []const u8, object_id: u64, value: f32) []const u8 {
    return std.fmt.bufPrint(buf, "{s}-{d}-{x}", .{ prefix, object_id, @as(u32, @bitCast(value)) }) catch prefix;
}

fn buildLayoutSelectionSection(ui: *core_ui.UiContext, state: *ProjectEditorState, obj: *SceneObject) !void {
    if ((try ui_widgets.collapsible(ui, "Parent", true))) {
        var parent_default: [64]u8 = undefined;
        const parent_text = if (obj.parent_id) |pid| blk: {
            if (project_editor_prop.objectNameById(state, pid)) |name| {
                break :blk std.fmt.bufPrint(&parent_default, "{s}", .{name}) catch "None";
            }
            break :blk std.fmt.bufPrint(&parent_default, "{d}", .{pid}) catch "None";
        } else "None";
        const parent_input = try core_ui.widgets_input.textInput(ui, .{ .id = "ed-right-layout-parent", .default_text = parent_text });
        if (parent_input.submitted) {
            const resolved = project_editor_prop.resolveParentId(state, parent_input.text);
            project_editor_prop.setParentId(state, resolved);
        }
    }
    if ((try ui_widgets.collapsible(ui, "Layer", true))) {
        const layer_input = try core_ui.widgets_input.textInput(ui, .{ .id = "ed-right-layout-layer", .default_text = project_editor_prop.layerLabel(obj.layer) });
        if (layer_input.submitted) try project_editor_prop.setLayer(state, layer_input.text);
    }
}

fn buildLifeSelectionSection(ui: *core_ui.UiContext, state: *ProjectEditorState, obj: *SceneObject) !void {
    if ((try ui_widgets.collapsible(ui, "Life Selection", true))) {
        if (obj.bone_pose.len == 0) {
            try ui_widgets.compactInfo(ui, "No bones on object");
            return;
        }
        var bone_buf: [96]u8 = undefined;
        try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&bone_buf, "Bones {d}  Selected {d}", .{
            obj.bone_pose.len,
            state.selected_bone orelse 0,
        }) catch "Bones");
    }
}

test "marker inspector exposes every marker kind with canonical labels" {
    inline for (std.meta.fields(scene_marker.Kind)) |field| {
        const kind: scene_marker.Kind = @enumFromInt(field.value);
        try std.testing.expect(markerKindButtonWidth(kind) >= 100);
    }
    try std.testing.expectEqualStrings("Player Start", scene_marker.Kind.player_start.label());
    try std.testing.expectEqualStrings("Objective", scene_marker.Kind.objective.label());
    try std.testing.expectEqualStrings("Interactable Anchor", scene_marker.Kind.interactable_anchor.label());
}

test "marker inspector primary fields follow marker gameplay intent" {
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("Required: binding", markerRequirementLine(.player_start, &buf));
    try std.testing.expectEqualStrings("Required: marker id", markerRequirementLine(.objective, &buf));
    try std.testing.expectEqualStrings("Required: group", markerRequirementLine(.patrol_point, &buf));
    try std.testing.expectEqualStrings("Required: none", markerRequirementLine(.audio_emitter, &buf));

    try std.testing.expect(markerUsesBinding(.player_start));
    try std.testing.expect(!markerUsesMarkerId(.player_start));
    try std.testing.expect(markerUsesMarkerId(.objective));
    try std.testing.expect(markerUsesGroup(.spawn_point));
    try std.testing.expect(markerUsesGroup(.patrol_point));
    try std.testing.expect(markerUsesOrder(.patrol_point));
    try std.testing.expect(markerUsesRadius(.trigger_volume, .box));
    try std.testing.expect(markerUsesRadius(.audio_emitter, .sphere));
    try std.testing.expect(!markerUsesRadius(.spawn_point, .point));
}
