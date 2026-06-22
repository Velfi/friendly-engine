const std = @import("std");
const shared = @import("runtime_shared");
const project_editor_edit = @import("project_editor_edit.zig");
const project_editor_life_gizmo = @import("project_editor_life_gizmo.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_types = @import("project_editor_types.zig");

const scene_animation = shared.scene_animation;
const scene_skinning = shared.scene_skinning;
const ProjectEditorState = project_editor_state.ProjectEditorState;
const LifeInterpolation = project_editor_types.LifeInterpolation;
const LifeTool = project_editor_types.LifeTool;

const key_time_epsilon: f32 = 0.001;

pub fn ensureClip(state: *ProjectEditorState) !usize {
    if (state.active_clip) |idx| return idx;
    try addClip(state);
    return state.active_clip.?;
}

pub fn addClip(state: *ProjectEditorState) !void {
    project_editor_edit.pushUndoSnapshot(state);
    const id = @as(u64, @intCast(state.animations.items.len + 1));
    const name = try std.fmt.allocPrint(state.allocator, "Clip {d}", .{id});
    try state.animations.append(state.allocator, .{
        .id = id,
        .name = name,
        .duration = 1,
        .looping = true,
        .tracks = &.{},
        .poses = &.{},
    });
    state.active_clip = state.animations.items.len - 1;
    state.life_time = 0;
    state.scene_dirty = true;
    project_editor_state.setStatus(state, "Animation clip added");
}

pub fn onToolActivated(state: *ProjectEditorState, tool: LifeTool) void {
    switch (tool) {
        .record => toggleRecord(state),
        .playback => togglePlayback(state),
        .clips => project_editor_state.setStatus(state, "Clips panel: select or add animation clips"),
        .bones => {
            state.show_life_bones = true;
            project_editor_state.setStatus(state, "Bones tool: select bones and add bone keyframes");
        },
        .curves => {
            state.show_life_tracks = true;
            project_editor_state.setStatus(state, "Curves: select a track to edit keyframes");
        },
        .keyframe => project_editor_state.setStatus(state, "Keyframe tool: add keys at current frame"),
        else => {},
    }
}

pub fn toggleRecord(state: *ProjectEditorState) void {
    state.life_recording = !state.life_recording;
    state.life_auto_key = state.life_recording;
    project_editor_state.setStatus(state, if (state.life_recording) "Recording on" else "Recording off");
}

pub fn addObjectKeyframe(state: *ProjectEditorState) !void {
    const obj_idx = state.selected_object orelse {
        project_editor_state.setStatus(state, "Select an object to keyframe");
        return;
    };
    const channels = selectedKeyChannels(state);
    if (!channels.any()) {
        project_editor_state.setStatus(state, "Select key channels");
        return;
    }
    const clip_idx = try ensureClip(state);
    project_editor_edit.pushUndoSnapshot(state);
    const obj = &state.objects.items[obj_idx];
    try upsertKeyframe(state, clip_idx, .{ .object = obj.id }, .{
        .position = obj.position,
        .rotation = obj.rotation,
        .scale = obj.scale,
    }, channels, toSceneInterpolation(state.life_interpolation));
    state.scene_dirty = true;
    project_editor_state.setStatus(state, "Object keyframe added");
}

pub fn autoKeyframeAfterPoseEdit(state: *ProjectEditorState) void {
    if (!state.life_auto_key) return;
    if (state.life_tool == .pose or state.life_tool == .bones) {
        if (state.selected_bone != null) {
            addBoneKeyframe(state) catch return;
        } else {
            addObjectKeyframe(state) catch return;
        }
    }
}

pub fn addBoneKeyframe(state: *ProjectEditorState) !void {
    const obj_idx = state.selected_object orelse {
        project_editor_state.setStatus(state, "Select a skeletal object");
        return;
    };
    const bone_idx = state.selected_bone orelse {
        project_editor_state.setStatus(state, "Select a bone");
        return;
    };
    const obj = &state.objects.items[obj_idx];
    if (bone_idx >= obj.bone_pose.len) {
        project_editor_state.setStatus(state, "Bone pose missing");
        return;
    }
    const clip_idx = try ensureClip(state);
    project_editor_edit.pushUndoSnapshot(state);
    const channels = scene_animation.KeyChannels{ .position = true, .rotation = true, .scale = true };
    try upsertKeyframe(
        state,
        clip_idx,
        .{ .bone = .{ .object_id = obj.id, .bone_index = bone_idx } },
        obj.bone_pose[bone_idx],
        channels,
        toSceneInterpolation(state.life_interpolation),
    );
    state.scene_dirty = true;
    project_editor_state.setStatus(state, "Bone keyframe added");
}

pub fn setSelectedKeyframeInterpolation(state: *ProjectEditorState, interpolation: LifeInterpolation) void {
    const clip_idx = state.active_clip orelse return;
    const track_idx = state.life_selected_track orelse return;
    const key_idx = state.life_selected_keyframe orelse return;
    if (clip_idx >= state.animations.items.len) return;
    const clip = &state.animations.items[clip_idx];
    if (track_idx >= clip.tracks.len) return;
    const track = &clip.tracks[track_idx];
    if (key_idx >= track.keyframes.len) return;
    project_editor_edit.pushUndoSnapshot(state);
    track.keyframes[key_idx].interpolation = toSceneInterpolation(interpolation);
    state.scene_dirty = true;
    project_editor_state.setStatus(state, "Keyframe interpolation updated");
}

pub fn nudgeSelectedKeyframeTime(state: *ProjectEditorState, delta: f32) void {
    const clip_idx = state.active_clip orelse return;
    const track_idx = state.life_selected_track orelse return;
    const key_idx = state.life_selected_keyframe orelse return;
    if (clip_idx >= state.animations.items.len) return;
    const clip = &state.animations.items[clip_idx];
    if (track_idx >= clip.tracks.len) return;
    const track = &clip.tracks[track_idx];
    if (key_idx >= track.keyframes.len) return;

    const min_time = if (key_idx > 0) track.keyframes[key_idx - 1].time + key_time_epsilon else 0;
    const max_time = if (key_idx + 1 < track.keyframes.len) track.keyframes[key_idx + 1].time - key_time_epsilon else clip.duration;
    if (min_time > max_time) {
        project_editor_state.setStatus(state, "Keyframe has no room to move");
        return;
    }

    const next_time = std.math.clamp(track.keyframes[key_idx].time + delta, min_time, max_time);
    if (@abs(next_time - track.keyframes[key_idx].time) <= key_time_epsilon) {
        project_editor_state.setStatus(state, "Keyframe blocked by neighbor");
        return;
    }
    project_editor_edit.pushUndoSnapshot(state);
    track.keyframes[key_idx].time = next_time;
    state.life_time = next_time;
    state.scene_dirty = true;
    project_editor_state.setStatus(state, "Keyframe frame updated");
}

pub fn setSelectedKeyframeChannels(state: *ProjectEditorState, channels: scene_animation.KeyChannels) void {
    if (!channels.any()) {
        project_editor_state.setStatus(state, "Keyframe needs a channel");
        return;
    }
    const clip_idx = state.active_clip orelse return;
    const track_idx = state.life_selected_track orelse return;
    const key_idx = state.life_selected_keyframe orelse return;
    if (clip_idx >= state.animations.items.len) return;
    const clip = &state.animations.items[clip_idx];
    if (track_idx >= clip.tracks.len) return;
    const track = &clip.tracks[track_idx];
    if (key_idx >= track.keyframes.len) return;
    project_editor_edit.pushUndoSnapshot(state);
    track.keyframes[key_idx].channels = channels;
    state.scene_dirty = true;
    project_editor_state.setStatus(state, "Keyframe channels updated");
}

pub fn stampSelectedKeyframeFromScene(state: *ProjectEditorState) void {
    const clip_idx = state.active_clip orelse return;
    const track_idx = state.life_selected_track orelse return;
    const key_idx = state.life_selected_keyframe orelse return;
    if (clip_idx >= state.animations.items.len) return;
    const clip = &state.animations.items[clip_idx];
    if (track_idx >= clip.tracks.len) return;
    const track = &clip.tracks[track_idx];
    if (key_idx >= track.keyframes.len) return;
    const transform = currentTransformForTarget(state, track.target) orelse {
        project_editor_state.setStatus(state, "Keyframe target missing");
        return;
    };
    project_editor_edit.pushUndoSnapshot(state);
    track.keyframes[key_idx].transform = transform;
    state.scene_dirty = true;
    project_editor_state.setStatus(state, "Keyframe pose updated");
}

pub fn applyRestPose(state: *ProjectEditorState) void {
    const obj_idx = state.selected_object orelse {
        project_editor_state.setStatus(state, "Select an object for rest pose");
        return;
    };
    project_editor_edit.pushUndoSnapshot(state);
    const obj = &state.objects.items[obj_idx];
    if (obj.skeleton_asset) |asset| {
        const skeleton = scene_skinning.findSkeletonForAsset(state.skeletons.items, asset) orelse {
            project_editor_state.setStatus(state, "Skeleton asset missing");
            return;
        };
        const rest = scene_skinning.restPoseFromSkeleton(state.allocator, skeleton) catch {
            project_editor_state.setStatus(state, "Rest pose failed");
            return;
        };
        state.allocator.free(obj.bone_pose);
        obj.bone_pose = rest;
        state.scene_dirty = true;
        project_editor_state.setStatus(state, "Rest pose applied");
        return;
    }
    obj.position = .{ .x = 0, .y = 0, .z = 0 };
    obj.rotation = .{ .x = 0, .y = 0, .z = 0 };
    obj.scale = .{ .x = 1, .y = 1, .z = 1 };
    state.scene_dirty = true;
    project_editor_state.setStatus(state, "Rest pose applied");
}

pub fn saveCurrentPose(state: *ProjectEditorState, name: []const u8) !void {
    const obj_idx = state.selected_object orelse {
        project_editor_state.setStatus(state, "Select an object to save pose");
        return;
    };
    const clip_idx = try ensureClip(state);
    project_editor_edit.pushUndoSnapshot(state);
    const obj = &state.objects.items[obj_idx];
    const snapshot = scene_animation.PoseSnapshot{
        .target = .{ .object = obj.id },
        .transform = .{
            .position = obj.position,
            .rotation = obj.rotation,
            .scale = obj.scale,
        },
    };
    try upsertNamedPose(state, clip_idx, name, &[1]scene_animation.PoseSnapshot{snapshot});
    state.scene_dirty = true;
    project_editor_state.setStatus(state, "Pose saved");
}

pub fn applyNamedPose(state: *ProjectEditorState, name: []const u8) void {
    const clip_idx = state.active_clip orelse {
        project_editor_state.setStatus(state, "Select a clip");
        return;
    };
    if (clip_idx >= state.animations.items.len) return;
    const clip = state.animations.items[clip_idx];
    const pose_idx = findNamedPose(clip, name) orelse {
        project_editor_state.setStatus(state, "Pose not found");
        return;
    };
    project_editor_edit.pushUndoSnapshot(state);
    const pose = clip.poses[pose_idx];
    for (pose.snapshots) |snap| {
        applyPoseSnapshot(state, snap);
    }
    state.scene_dirty = true;
    project_editor_state.setStatus(state, "Pose applied");
}

pub fn togglePlayback(state: *ProjectEditorState) void {
    if (state.active_clip == null) {
        project_editor_state.setStatus(state, "Add an animation clip first");
        return;
    }
    state.life_playing = !state.life_playing;
    project_editor_state.setStatus(state, if (state.life_playing) "Animation playing" else "Animation stopped");
}

pub fn update(state: *ProjectEditorState, dt: f32) void {
    if (!state.life_playing) return;
    const clip_idx = state.active_clip orelse return;
    if (clip_idx >= state.animations.items.len) return;
    const clip = state.animations.items[clip_idx];
    state.life_time += dt * state.life_playback_speed;
    if (state.life_time > clip.duration) {
        state.life_time = if (clip.looping) @mod(state.life_time, clip.duration) else clip.duration;
        if (!clip.looping) state.life_playing = false;
    }
    applyClip(state, clip);
}

pub fn applyClip(state: *ProjectEditorState, clip: scene_animation.Clip) void {
    for (clip.tracks) |track| {
        const transform = scene_animation.evaluateTrack(track, state.life_time) orelse continue;
        switch (track.target) {
            .object => |id| if (findObjectById(state, id)) |idx| {
                state.objects.items[idx].position = transform.position;
                state.objects.items[idx].rotation = transform.rotation;
                state.objects.items[idx].scale = transform.scale;
            },
            .bone => |target| if (findObjectById(state, target.object_id)) |idx| {
                if (target.bone_index < state.objects.items[idx].bone_pose.len) {
                    state.objects.items[idx].bone_pose[target.bone_index] = transform;
                }
            },
        }
    }
}

pub fn selectNextBone(state: *ProjectEditorState) void {
    const obj_idx = state.selected_object orelse return;
    const obj = &state.objects.items[obj_idx];
    if (obj.bone_pose.len == 0) {
        state.selected_bone = null;
        project_editor_state.setStatus(state, "Selected object has no skeleton");
        return;
    }
    state.selected_bone = if (state.selected_bone) |bone| (bone + 1) % @as(u32, @intCast(obj.bone_pose.len)) else 0;
    project_editor_state.setStatus(state, "Bone selected");
}

pub fn selectBone(state: *ProjectEditorState, bone_idx: u32) void {
    const obj_idx = state.selected_object orelse {
        project_editor_state.setStatus(state, "Select a skeletal object");
        return;
    };
    if (bone_idx >= state.objects.items[obj_idx].bone_pose.len) {
        project_editor_state.setStatus(state, "Bone not found");
        return;
    }
    state.selected_bone = bone_idx;
    project_editor_state.setStatus(state, "Bone selected");
}

pub fn pickBoneAtScreen(state: *ProjectEditorState, local_x: f32, local_y: f32, vp_w: f32, vp_h: f32) bool {
    return project_editor_life_gizmo.pickBoneAtScreen(state, local_x, local_y, vp_w, vp_h);
}

pub fn selectKeyframe(state: *ProjectEditorState, clip_idx: usize, track_idx: usize, key_idx: usize) void {
    if (clip_idx >= state.animations.items.len) return;
    const clip = state.animations.items[clip_idx];
    if (track_idx >= clip.tracks.len) return;
    const track = clip.tracks[track_idx];
    if (key_idx >= track.keyframes.len) return;
    const key = track.keyframes[key_idx];
    state.life_selected_track = track_idx;
    state.life_selected_keyframe = key_idx;
    state.life_time = key.time;
    state.life_interpolation = @enumFromInt(@intFromEnum(key.interpolation));
    applyClip(state, clip);
    project_editor_state.setStatus(state, "Keyframe selected");
}

pub fn poseToolActive(state: *const ProjectEditorState) bool {
    return state.mode == .life and state.life_tool == .pose;
}

pub fn bonesToolActive(state: *const ProjectEditorState) bool {
    return state.mode == .life and state.life_tool == .bones;
}

pub fn curvesToolActive(state: *const ProjectEditorState) bool {
    return state.mode == .life and state.life_tool == .curves;
}

pub fn transformToolActive(state: *const ProjectEditorState) bool {
    return state.mode == .life and (state.life_tool == .pose or state.life_tool == .bones);
}

pub fn bonePickActive(state: *const ProjectEditorState) bool {
    return transformToolActive(state) and state.selected_object != null;
}

fn selectedKeyChannels(state: *const ProjectEditorState) scene_animation.KeyChannels {
    return .{
        .position = state.life_key_position,
        .rotation = state.life_key_rotation,
        .scale = state.life_key_scale,
    };
}

fn toSceneInterpolation(interp: LifeInterpolation) scene_animation.Interpolation {
    return @enumFromInt(@intFromEnum(interp));
}

fn upsertKeyframe(
    state: *ProjectEditorState,
    clip_idx: usize,
    target: scene_animation.PoseTarget,
    transform: scene_animation.Transform,
    channels: scene_animation.KeyChannels,
    interpolation: scene_animation.Interpolation,
) !void {
    var clip = &state.animations.items[clip_idx];
    const track_idx = findTrack(clip.*, target) orelse blk: {
        const next = try state.allocator.alloc(scene_animation.Track, clip.tracks.len + 1);
        @memcpy(next[0..clip.tracks.len], clip.tracks);
        next[clip.tracks.len] = .{ .target = target, .keyframes = &.{} };
        state.allocator.free(clip.tracks);
        clip.tracks = next;
        break :blk clip.tracks.len - 1;
    };
    var track = &clip.tracks[track_idx];
    for (track.keyframes, 0..) |*key, idx| {
        if (@abs(key.time - state.life_time) <= key_time_epsilon) {
            mergeKeyframe(key, transform, channels, interpolation);
            if (state.life_time > clip.duration) clip.duration = state.life_time;
            state.life_selected_track = track_idx;
            state.life_selected_keyframe = idx;
            return;
        }
    }
    const next_keys = try state.allocator.alloc(scene_animation.Keyframe, track.keyframes.len + 1);
    @memcpy(next_keys[0..track.keyframes.len], track.keyframes);
    next_keys[track.keyframes.len] = .{
        .time = state.life_time,
        .transform = transform,
        .channels = channels,
        .interpolation = interpolation,
    };
    state.allocator.free(track.keyframes);
    track.keyframes = next_keys;
    state.life_selected_track = track_idx;
    state.life_selected_keyframe = track.keyframes.len - 1;
    if (state.life_time > clip.duration) clip.duration = state.life_time;
}

fn mergeKeyframe(
    key: *scene_animation.Keyframe,
    transform: scene_animation.Transform,
    channels: scene_animation.KeyChannels,
    interpolation: scene_animation.Interpolation,
) void {
    if (channels.position) key.transform.position = transform.position;
    if (channels.rotation) key.transform.rotation = transform.rotation;
    if (channels.scale) key.transform.scale = transform.scale;
    key.channels.position = key.channels.position or channels.position;
    key.channels.rotation = key.channels.rotation or channels.rotation;
    key.channels.scale = key.channels.scale or channels.scale;
    key.interpolation = interpolation;
}

fn upsertNamedPose(state: *ProjectEditorState, clip_idx: usize, name: []const u8, snapshots: []const scene_animation.PoseSnapshot) !void {
    var clip = &state.animations.items[clip_idx];
    if (findNamedPose(clip.*, name)) |idx| {
        const pose = &clip.poses[idx];
        state.allocator.free(pose.snapshots);
        pose.snapshots = try state.allocator.dupe(scene_animation.PoseSnapshot, snapshots);
        return;
    }
    const next = try state.allocator.alloc(scene_animation.NamedPose, clip.poses.len + 1);
    @memcpy(next[0..clip.poses.len], clip.poses);
    next[clip.poses.len] = .{
        .name = try state.allocator.dupe(u8, name),
        .snapshots = try state.allocator.dupe(scene_animation.PoseSnapshot, snapshots),
    };
    state.allocator.free(clip.poses);
    clip.poses = next;
}

fn applyPoseSnapshot(state: *ProjectEditorState, snap: scene_animation.PoseSnapshot) void {
    switch (snap.target) {
        .object => |id| if (findObjectById(state, id)) |idx| {
            state.objects.items[idx].position = snap.transform.position;
            state.objects.items[idx].rotation = snap.transform.rotation;
            state.objects.items[idx].scale = snap.transform.scale;
        },
        .bone => |target| if (findObjectById(state, target.object_id)) |idx| {
            if (target.bone_index < state.objects.items[idx].bone_pose.len) {
                state.objects.items[idx].bone_pose[target.bone_index] = snap.transform;
            }
        },
    }
}

fn currentTransformForTarget(state: *const ProjectEditorState, target: scene_animation.PoseTarget) ?scene_animation.Transform {
    return switch (target) {
        .object => |id| if (findObjectById(state, id)) |idx| .{
            .position = state.objects.items[idx].position,
            .rotation = state.objects.items[idx].rotation,
            .scale = state.objects.items[idx].scale,
        } else null,
        .bone => |bone| if (findObjectById(state, bone.object_id)) |idx| blk: {
            if (bone.bone_index >= state.objects.items[idx].bone_pose.len) break :blk null;
            break :blk state.objects.items[idx].bone_pose[bone.bone_index];
        } else null,
    };
}

fn findNamedPose(clip: scene_animation.Clip, name: []const u8) ?usize {
    for (clip.poses, 0..) |pose, idx| {
        if (std.mem.eql(u8, pose.name, name)) return idx;
    }
    return null;
}

fn findTrack(clip: scene_animation.Clip, target: scene_animation.PoseTarget) ?usize {
    for (clip.tracks, 0..) |track, idx| {
        if (sameTarget(track.target, target)) return idx;
    }
    return null;
}

fn sameTarget(a: scene_animation.PoseTarget, b: scene_animation.PoseTarget) bool {
    return switch (a) {
        .object => |id| switch (b) {
            .object => |other| id == other,
            .bone => false,
        },
        .bone => |bone| switch (b) {
            .object => false,
            .bone => |other| bone.object_id == other.object_id and bone.bone_index == other.bone_index,
        },
    };
}

fn findObjectById(state: *const ProjectEditorState, id: u64) ?usize {
    for (state.objects.items, 0..) |obj, idx| {
        if (obj.id == id) return idx;
    }
    return null;
}
