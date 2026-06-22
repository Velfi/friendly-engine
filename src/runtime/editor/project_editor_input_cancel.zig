const project_editor_state = @import("project_editor_state.zig");
const project_editor_edit = @import("project_editor_edit.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;

pub fn cancelOngoingAction(state: *ProjectEditorState) void {
    if (cancelActiveDrag(state)) {
        project_editor_state.setStatus(state, "Cancelled");
        return;
    }
    if (state.pending_object_drag != .none) {
        state.pending_object_drag = .none;
        state.pending_gizmo_axis = null;
        project_editor_state.setStatus(state, "Cancelled");
        return;
    }
    if (state.is_playing) {
        state.is_playing = false;
        project_editor_state.setStatus(state, "Play scene stopped");
        return;
    }
    if (state.life_recording) {
        state.life_recording = false;
        state.life_auto_key = false;
        project_editor_state.setStatus(state, "Recording off");
        return;
    }
    if (state.world_measure_a != null or state.world_measure_b != null) {
        state.world_measure_a = null;
        state.world_measure_b = null;
        project_editor_state.setStatus(state, "Measure cleared");
        return;
    }
    if (state.world_road_points.items.len > 0 or state.world_road_drag_anchor != null) {
        @import("project_editor_ui_world.zig").clearRoadPlacement(state);
        project_editor_state.setStatus(state, "Road placement cleared");
        return;
    }
    if (state.architecture_curve_points.items.len > 0 or state.architecture_curve_preview_end != null) {
        @import("project_editor_architecture_curve.zig").clearDraft(state);
        project_editor_state.setStatus(state, "Curve draft cleared");
        return;
    }
    if (@import("project_editor_ui_world.zig").clearWorldCurveSelection(state)) {
        project_editor_state.setStatus(state, "Selection cleared");
        return;
    }
    if (clearSubSelection(state)) {
        project_editor_state.setStatus(state, "Selection cleared");
        return;
    }
    if (state.selected_object != null) {
        state.selected_object = null;
        project_editor_state.setStatus(state, "Selection cleared");
        return;
    }
    project_editor_state.setStatus(state, "Nothing to cancel");
}

fn cancelActiveDrag(state: *ProjectEditorState) bool {
    switch (state.drag_mode) {
        .none => return false,
        .camera_orbit, .camera_pan, .camera_zoom => {
            state.active_gesture.cancel();
            clearDragState(state);
            return true;
        },
        .move_object, .gizmo_move, .move_vertex, .move_edge, .move_face, .blockout_brush, .architecture_curve, .blockout_face_resize, .life_pose => {
            if (state.drag_mode == .architecture_curve) @import("project_editor_architecture_curve.zig").clearDraft(state);
            project_editor_edit.undo(state);
            state.active_gesture.cancel();
            clearDragState(state);
            return true;
        },
        .paint_texture, .world_paint, .world_scatter_zone, .world_scatter_density, .world_road, .world_curve_gizmo => {
            if (state.drag_mode == .world_scatter_zone) @import("project_editor_ui_world.zig").cancelScatterZoneDrag(state);
            if (state.drag_mode == .world_scatter_density) @import("project_editor_ui_world.zig").cancelScatterDensityPaint(state);
            if (state.drag_mode == .world_road) @import("project_editor_ui_world.zig").cancelRoadDrag(state);
            if (state.drag_mode == .world_curve_gizmo) @import("project_editor_ui_world.zig").cancelWorldCurveGizmoDrag(state);
            state.active_gesture.cancel();
            clearDragState(state);
            return true;
        },
        .selection_box => {
            state.active_gesture.cancel();
            clearDragState(state);
            return true;
        },
    }
}

fn clearDragState(state: *ProjectEditorState) void {
    state.drag_mode = .none;
    state.pending_object_drag = .none;
    state.pending_gizmo_axis = null;
    state.gizmo_drag_axis = null;
    state.drag_moved = false;
    state.selection_box_active = false;
    state.active_view_nav = .none;
    state.blockout_drag_start = null;
    state.blockout_drag_end = null;
    state.blockout_resize_face = null;
    state.blockout_resize_start = null;
    state.blockout_resize_base_scale = null;
    state.blockout_resize_preview = null;
    state.world_scatter_drag_start = null;
    state.world_scatter_drag_end = null;
}

fn clearSubSelection(state: *ProjectEditorState) bool {
    const had = state.selected_vertex != null or
        state.selected_edge != null or
        state.selected_face != null or
        state.selected_bone != null;
    state.selected_vertex = null;
    state.selected_edge = null;
    state.selected_face = null;
    state.selected_bone = null;
    return had;
}
