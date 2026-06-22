const std = @import("std");
const shared = @import("runtime_shared");
const editor_math = shared.editor_math;
const geometry = shared.geometry;
const scene_io = shared.scene_io;
const scene_object = @import("editor_scene_object.zig");
const editor_raycast = @import("editor_raycast.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_types = @import("project_editor_types.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const SceneObject = scene_object.SceneObject;
const snapValue = editor_raycast.snapValue;
const pointToSegmentDist = editor_raycast.pointToSegmentDist;
const PropField = project_editor_types.PropField;
const GizmoAxis = project_editor_types.GizmoAxis;
const MoveAxis = project_editor_types.MoveAxis;
const EditChannel = project_editor_types.EditChannel;

pub fn toggleSnap(state: *ProjectEditorState) void {
    state.snap_enabled = !state.snap_enabled;
    project_editor_state.setStatus(state, if (state.snap_enabled) "Grid snap on" else "Grid snap off");
}

pub fn nudgeAxis(state: *ProjectEditorState, axis: enum { x, y, z }, sign: f32, vertical: bool) void {
    if (state.mode != .layout) return;
    const idx = state.selected_object orelse return;
    if (!state.objects.items[idx].canModifyObject()) return;
    pushUndoSnapshot(state);
    const obj = &state.objects.items[idx];
    const step = if (state.snap_enabled) state.snap_size else 0.1;
    const delta = sign * step;

    if (state.edit_channel == .position) {
        if (vertical) {
            obj.position.y += delta;
        } else switch (axis) {
            .x => obj.position.x += delta,
            .y => obj.position.y += delta,
            .z => obj.position.z += delta,
        }
        if (state.snap_enabled) {
            obj.position.x = snapValue(obj.position.x, state.snap_size);
            obj.position.y = snapValue(obj.position.y, state.snap_size);
            obj.position.z = snapValue(obj.position.z, state.snap_size);
        }
    } else {
        const scale_delta = delta * 0.1;
        switch (axis) {
            .x => obj.scale.x = @max(0.1, obj.scale.x + scale_delta),
            .y => obj.scale.y = @max(0.1, obj.scale.y + scale_delta),
            .z => obj.scale.z = @max(0.1, obj.scale.z + scale_delta),
        }
    }
    project_editor_state.setStatus(state, "Transform updated");
}

pub fn adjustSelected(state: *ProjectEditorState, sign: i32, all_axes: bool) void {
    if (state.mode != .layout) return;
    const idx = state.selected_object orelse return;
    if (!state.objects.items[idx].canModifyObject()) return;
    pushUndoSnapshot(state);
    const obj = &state.objects.items[idx];
    const step = if (state.snap_enabled) state.snap_size else 0.1;
    const delta = @as(f32, @floatFromInt(sign)) * step;

    if (state.edit_channel == .position) {
        switch (state.move_axis) {
            .x, .xz => obj.position.x += delta,
            .y => obj.position.y += delta,
            .z => obj.position.z += delta,
            .xy => {
                obj.position.x += delta;
                obj.position.y += delta;
            },
            .yz => {
                obj.position.y += delta;
                obj.position.z += delta;
            },
        }
        if (state.snap_enabled) {
            obj.position.x = snapValue(obj.position.x, state.snap_size);
            obj.position.y = snapValue(obj.position.y, state.snap_size);
            obj.position.z = snapValue(obj.position.z, state.snap_size);
        }
    } else {
        if (all_axes or state.move_axis == .xz) {
            obj.scale.x = @max(0.1, obj.scale.x + delta * 0.1);
            obj.scale.y = @max(0.1, obj.scale.y + delta * 0.1);
            obj.scale.z = @max(0.1, obj.scale.z + delta * 0.1);
        } else switch (state.move_axis) {
            .x => obj.scale.x = @max(0.1, obj.scale.x + delta * 0.1),
            .y => obj.scale.y = @max(0.1, obj.scale.y + delta * 0.1),
            .z => obj.scale.z = @max(0.1, obj.scale.z + delta * 0.1),
            .xz => {},
            .xy => {
                obj.scale.x = @max(0.1, obj.scale.x + delta * 0.1);
                obj.scale.y = @max(0.1, obj.scale.y + delta * 0.1);
            },
            .yz => {
                obj.scale.y = @max(0.1, obj.scale.y + delta * 0.1);
                obj.scale.z = @max(0.1, obj.scale.z + delta * 0.1);
            },
        }
    }
    project_editor_state.setStatus(state, "Transform updated");
}

pub fn fieldInputText(state: *ProjectEditorState) []const u8 {
    return state.field_input_buf[0..state.field_input_len];
}

pub fn beginFieldEdit(state: *ProjectEditorState, field: PropField, value: f32) void {
    state.focused_field = field;
    var buf: [32]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "{d:.2}", .{value}) catch unreachable;
    state.field_input_len = @min(text.len, state.field_input_buf.len);
    @memcpy(state.field_input_buf[0..state.field_input_len], text[0..state.field_input_len]);
}

pub fn cancelFieldEdit(state: *ProjectEditorState) void {
    state.focused_field = .none;
    state.field_input_len = 0;
}

pub fn cycleFieldTab(state: *ProjectEditorState) void {
    if (state.selected_object == null) return;
    const next_field = if (state.focused_field == .none) .pos_x else state.focused_field.next();
    const idx = state.selected_object.?;
    const obj = &state.objects.items[idx];
    const value = switch (next_field) {
        .none => return,
        .pos_x => obj.position.x,
        .pos_y => obj.position.y,
        .pos_z => obj.position.z,
        .rot_x => obj.rotation.x,
        .rot_y => obj.rotation.y,
        .rot_z => obj.rotation.z,
        .scale_x => obj.scale.x,
        .scale_y => obj.scale.y,
        .scale_z => obj.scale.z,
    };
    beginFieldEdit(state, next_field, value);
}

pub fn appendFieldInput(state: *ProjectEditorState, text: []const u8) void {
    for (text) |ch| {
        if (ch >= '0' and ch <= '9') {
            appendFieldChar(state, ch);
        } else if (ch == '-' and state.field_input_len == 0) {
            appendFieldChar(state, ch);
        } else if (ch == '.' and std.mem.indexOfScalar(u8, fieldInputText(state), '.') == null) {
            appendFieldChar(state, ch);
        }
    }
}

pub fn appendFieldChar(state: *ProjectEditorState, ch: u8) void {
    if (state.field_input_len >= state.field_input_buf.len) return;
    state.field_input_buf[state.field_input_len] = ch;
    state.field_input_len += 1;
}

pub fn popFieldInput(state: *ProjectEditorState) void {
    if (state.field_input_len > 0) state.field_input_len -= 1;
}

pub fn applyFieldEdit(state: *ProjectEditorState) void {
    const field = state.focused_field;
    if (field == .none) return;
    const idx = state.selected_object orelse {
        cancelFieldEdit(state);
        return;
    };

    const trimmed = std.mem.trim(u8, fieldInputText(state), " \t");
    const parsed = std.fmt.parseFloat(f32, trimmed) catch {
        project_editor_state.setStatus(state, "Invalid number");
        return;
    };

    if (!state.objects.items[idx].canModifyObject()) {
        cancelFieldEdit(state);
        project_editor_state.setStatus(state, "Object is immutable");
        return;
    }
    pushUndoSnapshot(state);
    const obj = &state.objects.items[idx];
    switch (field) {
        .pos_x => {
            obj.position.x = if (state.snap_enabled) snapValue(parsed, state.snap_size) else parsed;
        },
        .pos_y => {
            obj.position.y = if (state.snap_enabled) snapValue(parsed, state.snap_size) else parsed;
        },
        .pos_z => {
            obj.position.z = if (state.snap_enabled) snapValue(parsed, state.snap_size) else parsed;
        },
        .rot_x => obj.rotation.x = parsed,
        .rot_y => obj.rotation.y = parsed,
        .rot_z => obj.rotation.z = parsed,
        .scale_x => obj.scale.x = @max(0.01, parsed),
        .scale_y => obj.scale.y = @max(0.01, parsed),
        .scale_z => obj.scale.z = @max(0.01, parsed),
        .none => {},
    }
    cancelFieldEdit(state);
    project_editor_state.setStatus(state, "Property updated");
}

const edit_gizmo = @import("project_editor_edit_gizmo.zig");
const edit_undo = @import("project_editor_edit_undo.zig");

pub const gizmoAxisActive = edit_gizmo.gizmoAxisActive;
pub const gizmoLength = edit_gizmo.gizmoLength;
pub const gizmoAxisDirection = edit_gizmo.gizmoAxisDirection;
pub const gizmoAxisVector = edit_gizmo.gizmoAxisVector;
pub const gizmoDragAlongScreenAxis = edit_gizmo.gizmoDragAlongScreenAxis;
pub const pickGizmoAxis = edit_gizmo.pickGizmoAxis;
pub const rotationRingPoint = edit_gizmo.rotationRingPoint;
pub const moveAlongGizmoAxis = edit_gizmo.moveAlongGizmoAxis;
pub const gizmoAxisColor = edit_undo.gizmoAxisColor;
pub const pushUndoSnapshot = edit_undo.pushUndoSnapshot;
pub const beginUndoBatch = edit_undo.beginUndoBatch;
pub const endUndoBatch = edit_undo.endUndoBatch;
pub const cancelUndoBatch = edit_undo.cancelUndoBatch;
pub const undo = edit_undo.undo;
pub const redo = edit_undo.redo;
pub const clearUndoHistory = edit_undo.clearUndoHistory;
pub const SceneSnapshot = edit_undo.SceneSnapshot;
pub const duplicateObjectData = edit_undo.duplicateObjectData;
pub const duplicateSceneObject = edit_undo.duplicateSceneObject;
pub const captureSnapshot = edit_undo.captureSnapshot;
pub const applySnapshot = edit_undo.applySnapshot;

test "gizmo drag follows upward screen motion on Y axis" {
    const along = gizmoDragAlongScreenAxis(0, -5, 0, -1);
    try std.testing.expect(along > 0);
}

test "gizmo drag follows rightward screen motion on X axis" {
    const along = gizmoDragAlongScreenAxis(5, 0, 1, 0);
    try std.testing.expect(along > 0);
}
