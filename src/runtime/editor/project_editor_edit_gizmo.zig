const std = @import("std");
const shared = @import("runtime_shared");
const editor_math = shared.editor_math;
const project_editor_state = @import("project_editor_state.zig");
const project_editor_types = @import("project_editor_types.zig");
const project_editor_life_gizmo = @import("project_editor_life_gizmo.zig");
const editor_raycast = @import("editor_raycast.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const PropField = project_editor_types.PropField;
const GizmoAxis = project_editor_types.GizmoAxis;
const MoveAxis = project_editor_types.MoveAxis;
const SceneObject = @import("editor_scene_object.zig").SceneObject;
const pointToSegmentDist = editor_raycast.pointToSegmentDist;
const snapValue = editor_raycast.snapValue;

pub fn gizmoAxisActive(state: *ProjectEditorState, axis: GizmoAxis) bool {
    return switch (state.move_axis) {
        .x => axis == .x,
        .y => axis == .y,
        .z => axis == .z,
        .xz => axis == .x or axis == .z,
        .xy => axis == .x or axis == .y,
        .yz => axis == .y or axis == .z,
    };
}

pub fn gizmoLength(state: *const ProjectEditorState) f32 {
    return state.camera.distance * 0.12;
}

fn gizmoAxisUnit(axis: GizmoAxis) editor_math.Vec3 {
    return switch (axis) {
        .x => .{ .x = 1, .y = 0, .z = 0 },
        .y => .{ .x = 0, .y = 1, .z = 0 },
        .z => .{ .x = 0, .y = 0, .z = 1 },
    };
}

pub fn gizmoAxisDirection(state: *ProjectEditorState, axis: GizmoAxis) editor_math.Vec3 {
    const unit = gizmoAxisUnit(axis);
    if (state.transform_space == .world) return unit;

    const rot = editor_math.Mat4.rotationEuler(project_editor_life_gizmo.gizmoRotationEuler(state));
    return editor_math.Vec3.normalized(rot.transformDir(unit));
}

pub fn gizmoAxisVector(state: *ProjectEditorState, axis: GizmoAxis) editor_math.Vec3 {
    return editor_math.Vec3.scale(gizmoAxisDirection(state, axis), gizmoLength(state));
}

pub fn gizmoDragAlongScreenAxis(dx: f32, dy: f32, axis_screen_nx: f32, axis_screen_ny: f32) f32 {
    return dx * axis_screen_nx + dy * axis_screen_ny;
}

pub fn pickGizmoAxis(state: *ProjectEditorState, local_x: f32, local_y: f32, vp_w: f32, vp_h: f32) ?GizmoAxis {
    if (state.object_tool == .rotate) return pickRotationGizmoAxis(state, local_x, local_y, vp_w, vp_h);

    if (state.selected_object == null) return null;
    const origin = project_editor_life_gizmo.gizmoOrigin(state) orelse return null;
    const origin_screen = project_editor_state.projectViewportPoint(state, origin, vp_w, vp_h) orelse return null;

    var best_axis: ?GizmoAxis = null;
    var best_dist: f32 = if (state.edit_channel == .scale) 18.0 else 14.0;

    const axes = [_]GizmoAxis{ .x, .y, .z };
    for (axes) |axis| {
        if (!gizmoAxisActive(state, axis)) continue;
        const tip = editor_math.Vec3.add(origin, gizmoAxisVector(state, axis));
        const tip_screen = project_editor_state.projectViewportPoint(state, tip, vp_w, vp_h) orelse continue;
        const line_dist = pointToSegmentDist(local_x, local_y, origin_screen.x, origin_screen.y, tip_screen.x, tip_screen.y);
        const tip_dist = @sqrt(
            (local_x - tip_screen.x) * (local_x - tip_screen.x) +
                (local_y - tip_screen.y) * (local_y - tip_screen.y),
        );
        const dist = @min(line_dist, tip_dist);
        if (dist < best_dist) {
            best_dist = dist;
            best_axis = axis;
        }
    }
    return best_axis;
}

fn pickRotationGizmoAxis(state: *ProjectEditorState, local_x: f32, local_y: f32, vp_w: f32, vp_h: f32) ?GizmoAxis {
    if (state.selected_object == null) return null;
    const origin = project_editor_life_gizmo.gizmoOrigin(state) orelse return null;
    const radius = gizmoLength(state);
    const axes = [_]GizmoAxis{ .x, .y, .z };
    var best_axis: ?GizmoAxis = null;
    var best_dist: f32 = 14.0;

    for (axes) |axis| {
        var prev: ?editor_math.Vec2 = null;
        var i: usize = 0;
        while (i <= 48) : (i += 1) {
            const angle = (@as(f32, @floatFromInt(i)) / 48.0) * std.math.tau;
            const world = rotationRingPoint(origin, axis, radius, angle);
            const screen = project_editor_state.projectViewportPoint(state, world, vp_w, vp_h) orelse {
                prev = null;
                continue;
            };
            if (prev) |p| {
                const dist = pointToSegmentDist(local_x, local_y, p.x, p.y, screen.x, screen.y);
                if (dist < best_dist) {
                    best_dist = dist;
                    best_axis = axis;
                }
            }
            prev = screen;
        }
    }
    return best_axis;
}

pub fn rotationRingPoint(origin: editor_math.Vec3, axis: GizmoAxis, radius: f32, angle: f32) editor_math.Vec3 {
    const c = @cos(angle) * radius;
    const s = @sin(angle) * radius;
    return switch (axis) {
        .x => .{ .x = origin.x, .y = origin.y + c, .z = origin.z + s },
        .y => .{ .x = origin.x + c, .y = origin.y, .z = origin.z + s },
        .z => .{ .x = origin.x + c, .y = origin.y + s, .z = origin.z },
    };
}

pub fn moveAlongGizmoAxis(state: *ProjectEditorState, dx: f32, dy: f32) void {
    if (project_editor_life_gizmo.transformToolActive(state)) {
        project_editor_life_gizmo.moveAlongGizmoAxis(state, dx, dy);
        return;
    }
    const axis = state.gizmo_drag_axis orelse return;
    const idx = state.selected_object orelse return;
    const obj = &state.objects.items[idx];
    if (state.object_tool == .rotate) {
        const delta = (dx - dy) * 0.012;
        switch (axis) {
            .x => obj.rotation.x += delta,
            .y => obj.rotation.y += delta,
            .z => obj.rotation.z += delta,
        }
        state.drag_moved = true;
        return;
    }

    const origin = obj.position;
    const vp_w = state.viewport_screen_rect.w;
    const vp_h = state.viewport_screen_rect.h;
    const origin_screen = project_editor_state.projectViewportPoint(state, origin, vp_w, vp_h) orelse return;
    const tip = editor_math.Vec3.add(origin, gizmoAxisVector(state, axis));
    const tip_screen = project_editor_state.projectViewportPoint(state, tip, vp_w, vp_h) orelse return;

    const sx = tip_screen.x - origin_screen.x;
    const sy = tip_screen.y - origin_screen.y;
    const screen_len = @sqrt(sx * sx + sy * sy);
    if (screen_len < 0.001) return;
    const nx = sx / screen_len;
    const ny = sy / screen_len;
    const sensitivity = state.camera.distance * 0.003;
    const along = gizmoDragAlongScreenAxis(dx, dy, nx, ny) * sensitivity;
    const axis_dir = gizmoAxisDirection(state, axis);

    if (state.edit_channel == .scale) {
        const scale_delta = along * 0.02;
        switch (axis) {
            .x => obj.scale.x = @max(0.01, obj.scale.x + scale_delta),
            .y => obj.scale.y = @max(0.01, obj.scale.y + scale_delta),
            .z => obj.scale.z = @max(0.01, obj.scale.z + scale_delta),
        }
    } else {
        const delta = editor_math.Vec3.scale(axis_dir, along);
        obj.position.x += delta.x;
        obj.position.y += delta.y;
        obj.position.z += delta.z;

        if (state.snap_enabled) {
            obj.position.x = snapValue(obj.position.x, state.snap_size);
            obj.position.y = snapValue(obj.position.y, state.snap_size);
            obj.position.z = snapValue(obj.position.z, state.snap_size);
        }
    }
    state.drag_moved = true;
}
