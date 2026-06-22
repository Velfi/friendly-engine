const project_editor_state = @import("project_editor_state.zig");
const project_editor_types = @import("project_editor_types.zig");
const project_editor_edit = @import("project_editor_edit.zig");
const project_editor_scene = @import("project_editor_scene.zig");
const project_editor_life = @import("project_editor_life.zig");
const project_editor_ui_world = @import("project_editor_ui_world.zig");
const friendly_engine = @import("friendly_engine");

const core_ui = friendly_engine.modules.core_ui;
const ProjectEditorState = project_editor_state.ProjectEditorState;
const click_drag_threshold_sq = project_editor_types.click_drag_threshold_sq;

pub fn viewportDragActive(state: *const ProjectEditorState) bool {
    return switch (state.drag_mode) {
        .camera_orbit, .camera_pan, .camera_zoom, .move_object, .gizmo_move, .move_vertex, .move_edge, .move_face, .paint_texture, .blockout_brush, .architecture_curve, .blockout_face_resize, .life_pose, .world_paint, .world_scatter_zone, .world_scatter_density, .world_road, .world_curve_gizmo, .selection_box => true,
        .none => state.pending_object_drag != .none,
    };
}

pub fn handleDrag(state: *ProjectEditorState, input: core_ui.InputState) void {
    const x = input.mouse_position.x;
    const y = input.mouse_position.y;
    if (state.walk_mode and (input.motion_delta_x != 0 or input.motion_delta_y != 0)) {
        state.camera.lookInPlace(input.motion_delta_x, input.motion_delta_y);
    }

    if (usesPrimaryButton(state) and !input.primary_down) return;

    if (input.primary_down) {
        tryStartPendingDrag(state, x, y);
    }

    const dx = x - state.drag_last_x;
    const dy = y - state.drag_last_y;
    state.drag_last_x = x;
    state.drag_last_y = y;

    switch (state.drag_mode) {
        .none => {},
        .camera_orbit => {
            state.camera.orbit(dx, dy);
            state.view_orientation = .free;
        },
        .camera_pan => {
            if (state.active_view_nav == .pan) {
                state.camera.pan(-dx, -dy);
            } else {
                state.camera.pan(dx, dy);
            }
        },
        .camera_zoom => state.camera.zoom(-dy * 0.1),
        .move_object => project_editor_scene.moveSelectedObject(state, dx, dy),
        .gizmo_move => project_editor_edit.moveAlongGizmoAxis(state, dx, dy),
        .move_vertex => project_editor_scene.moveSelectedVertex(state, dx, dy),
        .move_edge => project_editor_scene.moveSelectedEdge(state, dx, dy),
        .move_face => project_editor_scene.moveSelectedFace(state, dx, dy),
        .paint_texture => project_editor_scene.paintAtMouse(state, x, y),
        .world_paint => project_editor_ui_world.handleViewportPaintDrag(state, x, y),
        .world_scatter_zone => project_editor_ui_world.updateScatterZoneDrag(state, x, y),
        .world_scatter_density => project_editor_ui_world.handleViewportScatterDensityDrag(state, x, y),
        .world_road => {
            project_editor_ui_world.handleViewportRoadDrag(state, x, y);
            const mdx = x - state.click_start_x;
            const mdy = y - state.click_start_y;
            if (mdx * mdx + mdy * mdy >= click_drag_threshold_sq) state.drag_moved = true;
        },
        .world_curve_gizmo => {
            project_editor_ui_world.handleViewportCurveGizmoDrag(state, x, y);
            state.drag_moved = true;
        },
        .selection_box => {
            state.selection_box_end = .{ .x = x - state.viewport_screen_rect.x, .y = y - state.viewport_screen_rect.y };
            const mdx = x - state.click_start_x;
            const mdy = y - state.click_start_y;
            if (mdx * mdx + mdy * mdy >= click_drag_threshold_sq) {
                state.selection_box_active = true;
                state.drag_moved = true;
                state.active_gesture.drag();
            }
        },
        .blockout_brush => project_editor_scene.updateBlockoutDrag(state, x, y),
        .architecture_curve => @import("project_editor_architecture_curve.zig").updateFreehandDrag(state, x, y),
        .blockout_face_resize => @import("project_editor_blockout_resize.zig").updateFaceResize(state, x, y),
        .life_pose => {
            if (state.gizmo_drag_axis != null) {
                project_editor_edit.moveAlongGizmoAxis(state, dx, dy);
            } else {
                project_editor_scene.moveSelectedObject(state, dx, dy);
            }
        },
    }
}

fn usesPrimaryButton(state: *const ProjectEditorState) bool {
    if (state.pending_object_drag != .none) return true;
    return switch (state.drag_mode) {
        .move_object, .gizmo_move, .move_vertex, .move_edge, .move_face, .paint_texture, .world_paint, .world_scatter_zone, .world_scatter_density, .world_road, .world_curve_gizmo, .blockout_brush, .architecture_curve, .blockout_face_resize, .life_pose, .selection_box => true,
        .none, .camera_orbit, .camera_pan, .camera_zoom => false,
    };
}

pub fn tryStartPendingDrag(state: *ProjectEditorState, x: f32, y: f32) void {
    if (state.pending_object_drag == .none or state.drag_mode != .none or selectedObjectLocked(state)) return;
    const mdx = x - state.click_start_x;
    const mdy = y - state.click_start_y;
    if (mdx * mdx + mdy * mdy < click_drag_threshold_sq) return;

    project_editor_edit.pushUndoSnapshot(state);
    switch (state.pending_object_drag) {
        .none => {},
        .gizmo => {
            state.drag_mode = .gizmo_move;
            state.gizmo_drag_axis = state.pending_gizmo_axis;
            state.active_gesture.begin(.shape_handle);
        },
        .move_object => {
            state.drag_mode = .move_object;
            state.active_gesture.begin(.shape_handle);
        },
    }
    state.drag_last_x = x;
    state.drag_last_y = y;
}

pub fn frameSelected(state: *ProjectEditorState) void {
    @import("project_editor_ui_widgets.zig").frameSelected(state);
}

fn selectedObjectLocked(state: *const ProjectEditorState) bool {
    const idx = state.selected_object orelse return false;
    return !state.objects.items[idx].canModifyObject();
}

comptime {
    _ = @import("project_editor_input_drag_tests.zig");
}
