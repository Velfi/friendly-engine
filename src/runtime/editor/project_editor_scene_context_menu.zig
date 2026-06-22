const std = @import("std");
const friendly_engine = @import("friendly_engine");
const project_editor_scene = @import("project_editor_scene.zig");
const project_editor_state = @import("project_editor_state.zig");
const scene_hierarchy = @import("editor_scene_hierarchy.zig");
const ui_widgets = @import("project_editor_ui_widgets.zig");

const core_ui = friendly_engine.modules.core_ui;
const ProjectEditorState = project_editor_state.ProjectEditorState;

pub fn open(state: *ProjectEditorState, object_idx: usize, x: f32, y: f32) void {
    if (object_idx >= state.objects.items.len) return;
    state.selected_object = object_idx;
    state.selected_vertex = null;
    state.selected_edge = null;
    state.selected_face = null;
    state.scene_object_context_menu_open = true;
    state.scene_object_context_menu_id = state.objects.items[object_idx].id;
    state.scene_object_context_menu_x = x;
    state.scene_object_context_menu_y = y;
}

pub fn build(ui: *core_ui.UiContext, state: *ProjectEditorState) !bool {
    if (!state.scene_object_context_menu_open) return false;
    const object_idx = scene_hierarchy.objectIndexById(state.objects.items, state.scene_object_context_menu_id) orelse {
        close(state);
        return false;
    };
    const obj = &state.objects.items[object_idx];

    const menu_w: f32 = 170;
    const row_h: f32 = 26;
    const menu_h: f32 = row_h * 4 + 10;
    const x = clampMenuX(ui, state.scene_object_context_menu_x, menu_w);
    const y = clampMenuY(ui, state.scene_object_context_menu_y, menu_h);
    const rect = core_ui.Rect{ .x = x, .y = y, .w = menu_w, .h = menu_h };

    if ((ui.input.primary_pressed or ui.input.right_button_pressed) and !rect.contains(ui.input.mouse_position)) {
        close(state);
        return false;
    }

    try ui.beginPanel(.{
        .id = "ed-scene-object-context-menu",
        .rect = rect,
        .row_height = row_h,
        .padding = 5,
        .spacing = 2,
    });
    defer ui.endPanel();

    if ((try ui_widgets.button(ui, "ed-scene-object-menu-select", "Select", menu_w - 10, false)).clicked) {
        selectObject(state, object_idx);
        close(state);
        return false;
    }
    if ((try ui_widgets.button(ui, "ed-scene-object-menu-zoom", "Zoom To", menu_w - 10, false)).clicked) {
        selectObject(state, object_idx);
        ui_widgets.frameSelected(state);
        project_editor_state.setStatus(state, "Zoomed to object");
        close(state);
        return false;
    }
    if ((try ui_widgets.button(ui, "ed-scene-object-menu-duplicate", "Duplicate", menu_w - 10, false)).clicked) {
        selectObject(state, object_idx);
        try project_editor_scene.duplicateSelected(state);
        close(state);
        return true;
    }
    if ((try ui_widgets.button(ui, "ed-scene-object-menu-delete", "Delete Object", menu_w - 10, obj.isImmutable())).clicked) {
        selectObject(state, object_idx);
        try project_editor_scene.deleteSelected(state);
        close(state);
        return true;
    }
    return true;
}

fn selectObject(state: *ProjectEditorState, object_idx: usize) void {
    if (object_idx >= state.objects.items.len) return;
    state.selected_object = object_idx;
    state.selected_vertex = null;
    state.selected_edge = null;
    state.selected_face = null;
}

fn close(state: *ProjectEditorState) void {
    state.scene_object_context_menu_open = false;
    state.scene_object_context_menu_id = 0;
}

fn clampMenuX(ui: *const core_ui.UiContext, x: f32, w: f32) f32 {
    if (ui.frame_bounds.w <= 0) return x;
    return @min(@max(ui.frame_bounds.x, x), @max(ui.frame_bounds.x, ui.frame_bounds.x + ui.frame_bounds.w - w - 4));
}

fn clampMenuY(ui: *const core_ui.UiContext, y: f32, h: f32) f32 {
    if (ui.frame_bounds.h <= 0) return y;
    return @min(@max(ui.frame_bounds.y, y), @max(ui.frame_bounds.y, ui.frame_bounds.y + ui.frame_bounds.h - h - 4));
}
