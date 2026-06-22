const std = @import("std");
const shared = @import("runtime_shared");
const project_editor_edit = @import("project_editor_edit.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_scene = @import("project_editor_scene.zig");
const editor_raycast = @import("editor_raycast.zig");

const editor_math = shared.editor_math;
const ProjectEditorState = project_editor_state.ProjectEditorState;

pub const FaceAxis = enum { x_pos, x_neg, y_pos, y_neg, z_pos, z_neg };

pub fn beginFaceResize(state: *ProjectEditorState, screen_x: f32, screen_y: f32) bool {
    const idx = state.selected_object orelse return false;
    const obj = &state.objects.items[idx];
    if (obj.primitive_kind != .box) return false;
    const face = pickFaceAxis(state, screen_x, screen_y) orelse return false;
    state.blockout_resize_face = face;
    state.blockout_resize_start = obj.position;
    state.blockout_resize_base_scale = obj.scale;
    state.drag_mode = .blockout_face_resize;
    return true;
}

pub fn updateFaceResize(state: *ProjectEditorState, x: f32, y: f32) void {
    const idx = state.selected_object orelse return;
    const face = state.blockout_resize_face orelse return;
    const start = state.blockout_resize_start orelse return;
    const base = state.blockout_resize_base_scale orelse return;
    const pt = project_editor_scene.screenToGroundPoint(state, x, y) orelse return;
    const grid = if (state.snap_enabled) state.snap_size else 0.1;
    const obj = &state.objects.items[idx];

    var scale = base;
    var pos = start;
    switch (face) {
        .x_pos => {
            const delta = editor_raycast.snapValue(pt.x - start.x, grid) * 2.0;
            scale.x = @max(0.25, base.x + delta);
            pos.x = start.x + delta * 0.5;
        },
        .x_neg => {
            const delta = editor_raycast.snapValue(start.x - pt.x, grid) * 2.0;
            scale.x = @max(0.25, base.x + delta);
            pos.x = start.x - delta * 0.5;
        },
        .z_pos => {
            const delta = editor_raycast.snapValue(pt.z - start.z, grid) * 2.0;
            scale.z = @max(0.25, base.z + delta);
            pos.z = start.z + delta * 0.5;
        },
        .z_neg => {
            const delta = editor_raycast.snapValue(start.z - pt.z, grid) * 2.0;
            scale.z = @max(0.25, base.z + delta);
            pos.z = start.z - delta * 0.5;
        },
        .y_pos => {
            const delta = editor_raycast.snapValue(pt.y - start.y, grid) * 2.0;
            scale.y = @max(0.25, base.y + delta);
            pos.y = start.y + delta * 0.5;
        },
        .y_neg => {
            const delta = editor_raycast.snapValue(start.y - pt.y, grid) * 2.0;
            scale.y = @max(0.25, base.y + delta);
            pos.y = start.y - delta * 0.5;
        },
    }
    obj.scale = scale;
    obj.position = pos;
    state.blockout_resize_preview = .{ .w = scale.x, .h = scale.y, .d = scale.z };
}

pub fn finishFaceResize(state: *ProjectEditorState) void {
    if (state.drag_mode != .blockout_face_resize) return;
    const idx = state.selected_object orelse return;
    const obj = &state.objects.items[idx];
    if (state.blockout_resize_preview) |dims| {
        if (obj.blockout_intent) |*intent| {
            const half = editor_math.Vec3.scale(obj.scale, 0.5);
            intent.min = editor_math.Vec3.sub(obj.position, half);
            intent.max = editor_math.Vec3.add(obj.position, half);
        } else if (obj.primitive_kind == .box) {
            const half = editor_math.Vec3.scale(obj.scale, 0.5);
            obj.blockout_intent = .{
                .kind = .box_add,
                .min = editor_math.Vec3.sub(obj.position, half),
                .max = editor_math.Vec3.add(obj.position, half),
            };
        }
        var buf: [96]u8 = undefined;
        project_editor_state.setStatus(state, std.fmt.bufPrint(
            &buf,
            "Size {d:.2} x {d:.2} x {d:.2}",
            .{ dims.w, dims.h, dims.d },
        ) catch "Resize applied");
    }
    state.blockout_resize_face = null;
    state.blockout_resize_start = null;
    state.blockout_resize_base_scale = null;
    state.blockout_resize_preview = null;
    state.drag_mode = .none;
}

fn pickFaceAxis(state: *ProjectEditorState, screen_x: f32, screen_y: f32) ?FaceAxis {
    const idx = state.selected_object orelse return null;
    const obj = &state.objects.items[idx];
    const w = state.viewport_screen_rect.w;
    const h = state.viewport_screen_rect.h;
    const local_x = screen_x - state.viewport_screen_rect.x;
    const local_y = screen_y - state.viewport_screen_rect.y;
    const hx = obj.scale.x * 0.5;
    const hy = obj.scale.y * 0.5;
    _ = hy;
    const hz = obj.scale.z * 0.5;
    const corners = [_]struct { axis: FaceAxis, p: editor_math.Vec3 }{
        .{ .axis = .x_pos, .p = .{ .x = obj.position.x + hx, .y = obj.position.y, .z = obj.position.z } },
        .{ .axis = .x_neg, .p = .{ .x = obj.position.x - hx, .y = obj.position.y, .z = obj.position.z } },
        .{ .axis = .z_pos, .p = .{ .x = obj.position.x, .y = obj.position.y, .z = obj.position.z + hz } },
        .{ .axis = .z_neg, .p = .{ .x = obj.position.x, .y = obj.position.y, .z = obj.position.z - hz } },
    };
    var best: ?FaceAxis = null;
    var best_dist: f32 = 24.0;
    for (corners) |entry| {
        const screen = project_editor_state.projectViewportPoint(state, entry.p, w, h) orelse continue;
        const dx = local_x - screen.x;
        const dy = local_y - screen.y;
        const dist = @sqrt(dx * dx + dy * dy);
        if (dist < best_dist) {
            best_dist = dist;
            best = entry.axis;
        }
    }
    return best;
}
