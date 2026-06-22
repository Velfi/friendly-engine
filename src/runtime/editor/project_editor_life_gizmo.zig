const shared = @import("runtime_shared");
const editor_math = shared.editor_math;
const scene_skinning = shared.scene_skinning;
const project_editor_state = @import("project_editor_state.zig");
const project_editor_edit = @import("project_editor_edit.zig");
const project_editor_types = @import("project_editor_types.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const GizmoAxis = project_editor_types.GizmoAxis;
const snapValue = @import("editor_raycast.zig").snapValue;

pub fn boneEditActive(state: *const ProjectEditorState) bool {
    if (state.mode != .life) return false;
    if (state.life_tool != .pose and state.life_tool != .bones) return false;
    const obj_idx = state.selected_object orelse return false;
    const bone_idx = state.selected_bone orelse return false;
    return bone_idx < state.objects.items[obj_idx].bone_pose.len;
}

pub fn transformToolActive(state: *const ProjectEditorState) bool {
    if (state.mode == .layout) return true;
    return state.mode == .life and (state.life_tool == .pose or state.life_tool == .bones);
}

pub fn gizmoOrigin(state: *const ProjectEditorState) ?editor_math.Vec3 {
    const obj_idx = state.selected_object orelse return null;
    if (boneEditActive(state)) {
        return boneWorldPosition(state, obj_idx, state.selected_bone.?);
    }
    return state.objects.items[obj_idx].position;
}

pub fn gizmoRotationEuler(state: *const ProjectEditorState) editor_math.Vec3 {
    const obj_idx = state.selected_object orelse return .{ .x = 0, .y = 0, .z = 0 };
    if (boneEditActive(state)) {
        return state.objects.items[obj_idx].bone_pose[state.selected_bone.?].rotation;
    }
    return state.objects.items[obj_idx].rotation;
}

pub fn moveAlongGizmoAxis(state: *ProjectEditorState, dx: f32, dy: f32) void {
    const axis = state.gizmo_drag_axis orelse return;
    const obj_idx = state.selected_object orelse return;
    const obj = &state.objects.items[obj_idx];

    if (state.object_tool == .rotate) {
        const delta = (dx - dy) * 0.012;
        if (boneEditActive(state)) {
            const bone = state.selected_bone.?;
            switch (axis) {
                .x => obj.bone_pose[bone].rotation.x += delta,
                .y => obj.bone_pose[bone].rotation.y += delta,
                .z => obj.bone_pose[bone].rotation.z += delta,
            }
        } else {
            switch (axis) {
                .x => obj.rotation.x += delta,
                .y => obj.rotation.y += delta,
                .z => obj.rotation.z += delta,
            }
        }
        state.drag_moved = true;
        state.scene_dirty = true;
        return;
    }

    const origin = gizmoOrigin(state) orelse return;
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
    const along = project_editor_edit.gizmoDragAlongScreenAxis(dx, dy, nx, ny) * sensitivity;
    const axis_dir = gizmoAxisDirection(state, axis);

    if (state.edit_channel == .scale) {
        const scale_delta = along * 0.02;
        if (boneEditActive(state)) {
            const bone = state.selected_bone.?;
            switch (axis) {
                .x => obj.bone_pose[bone].scale.x = @max(0.01, obj.bone_pose[bone].scale.x + scale_delta),
                .y => obj.bone_pose[bone].scale.y = @max(0.01, obj.bone_pose[bone].scale.y + scale_delta),
                .z => obj.bone_pose[bone].scale.z = @max(0.01, obj.bone_pose[bone].scale.z + scale_delta),
            }
        } else {
            switch (axis) {
                .x => obj.scale.x = @max(0.01, obj.scale.x + scale_delta),
                .y => obj.scale.y = @max(0.01, obj.scale.y + scale_delta),
                .z => obj.scale.z = @max(0.01, obj.scale.z + scale_delta),
            }
        }
    } else if (boneEditActive(state)) {
        const bone = state.selected_bone.?;
        const delta = editor_math.Vec3.scale(axis_dir, along);
        obj.bone_pose[bone].position.x += delta.x;
        obj.bone_pose[bone].position.y += delta.y;
        obj.bone_pose[bone].position.z += delta.z;
        if (state.snap_enabled) {
            obj.bone_pose[bone].position.x = snapValue(obj.bone_pose[bone].position.x, state.snap_size);
            obj.bone_pose[bone].position.y = snapValue(obj.bone_pose[bone].position.y, state.snap_size);
            obj.bone_pose[bone].position.z = snapValue(obj.bone_pose[bone].position.z, state.snap_size);
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
    state.scene_dirty = true;
}

pub fn pickBoneAtScreen(state: *ProjectEditorState, local_x: f32, local_y: f32, vp_w: f32, vp_h: f32) bool {
    const obj_idx = state.selected_object orelse return false;
    const obj = &state.objects.items[obj_idx];
    if (obj.bone_pose.len == 0) return false;

    var best_dist: f32 = 16.0;
    var best_bone: ?u32 = null;
    var bone: u32 = 0;
    while (bone < obj.bone_pose.len) : (bone += 1) {
        const world = boneWorldPosition(state, obj_idx, bone) orelse continue;
        const screen = project_editor_state.projectViewportPoint(state, world, vp_w, vp_h) orelse continue;
        const dx = screen.x - local_x;
        const dy = screen.y - local_y;
        const dist = @sqrt(dx * dx + dy * dy);
        if (dist < best_dist) {
            best_dist = dist;
            best_bone = bone;
        }
    }

    if (best_bone) |bone_idx| {
        state.selected_bone = bone_idx;
        project_editor_state.setStatus(state, "Bone selected");
        return true;
    }
    return false;
}

pub fn boneWorldPosition(state: *const ProjectEditorState, obj_idx: usize, bone_idx: u32) ?editor_math.Vec3 {
    const obj = &state.objects.items[obj_idx];
    if (bone_idx >= obj.bone_pose.len) return null;

    if (obj.skeleton_asset) |asset| {
        const skeleton = scene_skinning.findSkeletonForAsset(state.skeletons.items, asset) orelse {
            return obj.transform().transformPoint(obj.bone_pose[bone_idx].position);
        };
        var globals: [256]editor_math.Mat4 = undefined;
        const count = @min(skeleton.bones.len, globals.len);
        if (bone_idx >= count) return null;
        scene_skinning.computeGlobalTransforms(skeleton, obj.bone_pose, globals[0..count]);
        const combined = editor_math.Mat4.mul(obj.transform(), globals[bone_idx]);
        return combined.transformPoint(.{ .x = 0, .y = 0, .z = 0 });
    }

    return obj.transform().transformPoint(obj.bone_pose[bone_idx].position);
}

pub fn boneName(state: *const ProjectEditorState, obj_idx: usize, bone_idx: u32) []const u8 {
    const obj = &state.objects.items[obj_idx];
    if (obj.skeleton_asset) |asset| {
        if (scene_skinning.findSkeletonForAsset(state.skeletons.items, asset)) |skeleton| {
            if (bone_idx < skeleton.bones.len) return skeleton.bones[bone_idx].name;
        }
    }
    return "Bone";
}

fn gizmoAxisUnit(axis: GizmoAxis) editor_math.Vec3 {
    return switch (axis) {
        .x => .{ .x = 1, .y = 0, .z = 0 },
        .y => .{ .x = 0, .y = 1, .z = 0 },
        .z => .{ .x = 0, .y = 0, .z = 1 },
    };
}

fn gizmoAxisDirection(state: *const ProjectEditorState, axis: GizmoAxis) editor_math.Vec3 {
    const unit = gizmoAxisUnit(axis);
    if (state.transform_space == .world) return unit;
    const rot = editor_math.Mat4.rotationEuler(gizmoRotationEuler(state));
    return editor_math.Vec3.normalized(rot.transformDir(unit));
}

fn gizmoAxisVector(state: *const ProjectEditorState, axis: GizmoAxis) editor_math.Vec3 {
    return editor_math.Vec3.scale(gizmoAxisDirection(state, axis), project_editor_edit.gizmoLength(state));
}
