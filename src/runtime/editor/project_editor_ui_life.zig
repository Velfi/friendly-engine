const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const command_ids = shared.editor_command_ids;
const project_editor_edit = @import("project_editor_edit.zig");
const project_editor_life = @import("project_editor_life.zig");
const project_editor_life_gizmo = @import("project_editor_life_gizmo.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_types = @import("project_editor_types.zig");
const ui_widgets = @import("project_editor_ui_widgets.zig");
const project_editor_mode_config = @import("project_editor_mode_config.zig");

const core_ui = friendly_engine.modules.core_ui;
const scene_animation = shared.scene_animation;
const ProjectEditorState = project_editor_state.ProjectEditorState;

pub const frames_per_second: f32 = 30.0;
pub const timeline_height: f32 = 36.0;

pub fn registerEditor(registry: *project_editor_mode_config.EditorRegistry) !void {
    try registry.registerMode(project_editor_mode_config.descForMode(.life).*);
}

pub fn timeToFrame(time: f32) u32 {
    return @intFromFloat(@max(0, time * frames_per_second));
}

pub fn frameToTime(frame: u32) f32 {
    return @as(f32, @floatFromInt(frame)) / frames_per_second;
}

pub fn currentFrame(state: *const ProjectEditorState) u32 {
    return timeToFrame(state.life_time);
}

pub fn clipTotalFrames(state: *const ProjectEditorState) u32 {
    const clip_idx = state.active_clip orelse return 30;
    if (clip_idx >= state.animations.items.len) return 30;
    return @max(1, timeToFrame(state.animations.items[clip_idx].duration));
}

pub fn buildToolbar(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    const life_tools = [_]project_editor_types.LifeTool{
        .select, .pose, .keyframe, .record, .playback, .clips, .bones, .curves,
    };
    inline for (life_tools) |tool| {
        if ((try ui_widgets.button(ui, command_ids.lifeTool(@tagName(tool)), tool.label(), 68, state.life_tool == tool)).clicked) {
            state.life_tool = tool;
            handleToolActivated(state, tool);
        }
    }
}

fn handleToolActivated(state: *ProjectEditorState, tool: project_editor_types.LifeTool) void {
    project_editor_life.onToolActivated(state, tool);
}

pub fn buildLeftPanel(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    try ui.label("Life");
    _ = try ui_widgets.treeRow(ui, "Clips", &state.show_life_clips);
    if (state.show_life_clips) {
        try core_ui.layout.sameLine(ui);
        if ((try ui_widgets.button(ui, command_ids.life_add_clip, "Add", 48, false)).clicked) try project_editor_life.addClip(state);
        try core_ui.layout.endSameLine(ui);
        for (state.animations.items, 0..) |clip, idx| {
            var id_buf: [48]u8 = undefined;
            const row_id = std.fmt.bufPrint(&id_buf, "life-clip-{d}", .{idx}) catch "life-clip";
            if ((try ui_widgets.row(ui, row_id, clip.name, state.active_clip == idx)).clicked) {
                state.active_clip = idx;
                state.life_time = 0;
                state.life_selected_track = null;
                state.life_selected_keyframe = null;
                project_editor_state.setStatus(state, "Clip selected");
            }
        }
        if (state.animations.items.len == 0) {
            try ui_widgets.compactInfo(ui, "No clips yet");
        }
    }
    _ = try ui_widgets.treeRow(ui, "Tracks", &state.show_life_tracks);
    if (state.show_life_tracks) {
        const clip_idx = state.active_clip orelse {
            try ui_widgets.compactInfo(ui, "Select a clip");
            return;
        };
        if (clip_idx >= state.animations.items.len) return;
        const clip = state.animations.items[clip_idx];
        if (clip.tracks.len == 0) {
            try ui_widgets.compactInfo(ui, "No tracks yet");
        }
        for (clip.tracks, 0..) |track, track_idx| {
            var label_buf: [128]u8 = undefined;
            const label = formatTrackLabel(state, track.target, &label_buf) catch "track";
            var id_buf: [48]u8 = undefined;
            const row_id = std.fmt.bufPrint(&id_buf, "life-track-{d}-{d}", .{ clip_idx, track_idx }) catch "life-track";
            if ((try ui_widgets.row(ui, row_id, label, state.life_selected_track == track_idx)).clicked) {
                state.life_selected_track = track_idx;
                state.life_selected_keyframe = null;
                project_editor_state.setStatus(state, "Track selected");
            }
        }
    }
    _ = try ui_widgets.treeRow(ui, "Poses", &state.show_life_poses);
    if (state.show_life_poses) {
        if ((try ui_widgets.row(ui, "life-pose-rest", "rest", false)).clicked) {
            project_editor_life.applyRestPose(state);
        }
        if (state.active_clip) |clip_idx| {
            if (clip_idx < state.animations.items.len) {
                const clip = state.animations.items[clip_idx];
                for (clip.poses, 0..) |pose, pose_idx| {
                    var id_buf: [48]u8 = undefined;
                    const row_id = std.fmt.bufPrint(&id_buf, "life-pose-{d}", .{pose_idx}) catch "life-pose";
                    if ((try ui_widgets.row(ui, row_id, pose.name, false)).clicked) {
                        project_editor_life.applyNamedPose(state, pose.name);
                    }
                }
            }
        }
        if (state.selected_object) |obj_idx| {
            const obj = &state.objects.items[obj_idx];
            try core_ui.layout.sameLine(ui);
            if ((try ui_widgets.button(ui, "ed-life-save-pose", "Save Pose", 82, false)).clicked) {
                try project_editor_life.saveCurrentPose(state, obj.name);
            }
            try core_ui.layout.endSameLine(ui);
        }
    }
    _ = try ui_widgets.treeRow(ui, "Bones", &state.show_life_bones);
    if (state.show_life_bones) {
        const obj_idx = state.selected_object orelse {
            try ui_widgets.compactInfo(ui, "Select a skeletal object");
            return;
        };
        const obj = &state.objects.items[obj_idx];
        if (obj.bone_pose.len == 0) {
            try ui_widgets.compactInfo(ui, "No bones on object");
            return;
        }
        var bone: u32 = 0;
        while (bone < obj.bone_pose.len) : (bone += 1) {
            var label_buf: [96]u8 = undefined;
            const label = std.fmt.bufPrint(&label_buf, "{d}: {s}", .{ bone, project_editor_life_gizmo.boneName(state, obj_idx, bone) }) catch "Bone";
            var id_buf: [48]u8 = undefined;
            const row_id = std.fmt.bufPrint(&id_buf, "life-bone-{d}", .{bone}) catch "life-bone";
            if ((try ui_widgets.row(ui, row_id, label, state.selected_bone == bone)).clicked) {
                project_editor_life.selectBone(state, bone);
            }
        }
    }
}

pub fn buildTimeline(ui: *core_ui.UiContext, state: *ProjectEditorState, rect: core_ui.Rect) !void {
    try ui.beginPanel(.{ .id = "ed-life-timeline", .rect = rect, .row_height = 16, .padding = 4, .spacing = 2 });
    const total_frames = clipTotalFrames(state);
    const frame_step: u32 = 10;
    const ruler_y = rect.y + 4;
    const track_y = rect.y + 20;
    const usable_w = rect.w - 16;
    const px_per_frame = usable_w / @as(f32, @floatFromInt(@max(total_frames, frame_step)));

    var frame: u32 = 0;
    while (frame <= total_frames) : (frame += frame_step) {
        var label_buf: [16]u8 = undefined;
        const label = std.fmt.bufPrint(&label_buf, "{d}f", .{frame}) catch "0f";
        const x = rect.x + 8 + @as(f32, @floatFromInt(frame)) * px_per_frame;
        var id_buf: [32]u8 = undefined;
        const marker_id = std.fmt.bufPrint(&id_buf, "life-ruler-{d}", .{frame}) catch "life-ruler";
        const marker_rect = core_ui.Rect{ .x = x - 2, .y = ruler_y, .w = 28, .h = 14 };
        const marker = try ui_widgets.overlayTextButton(ui, marker_id, label, marker_rect, false);
        if (marker.clicked) {
            state.life_time = frameToTime(frame);
            if (state.active_clip) |clip_idx| {
                if (clip_idx < state.animations.items.len) {
                    project_editor_life.applyClip(state, state.animations.items[clip_idx]);
                }
            }
        }
    }

    if (state.active_clip) |clip_idx| {
        if (clip_idx < state.animations.items.len) {
            const clip = state.animations.items[clip_idx];
            for (clip.tracks, 0..) |track, track_idx| {
                for (track.keyframes, 0..) |key, key_idx| {
                    const key_frame = timeToFrame(key.time);
                    const x = rect.x + 8 + @as(f32, @floatFromInt(key_frame)) * px_per_frame;
                    var id_buf: [48]u8 = undefined;
                    const key_id = std.fmt.bufPrint(&id_buf, "life-key-{d}-{d}-{d}", .{ clip_idx, track_idx, key_idx }) catch "life-key";
                    const selected = state.life_selected_track == track_idx and state.life_selected_keyframe == key_idx;
                    const key_rect = core_ui.Rect{ .x = x - 5, .y = track_y, .w = 12, .h = 12 };
                    const key_btn = try ui_widgets.overlayTextButton(ui, key_id, "", key_rect, selected);
                    if (key_btn.clicked) {
                        state.life_selected_track = track_idx;
                        state.life_selected_keyframe = key_idx;
                        state.life_time = key.time;
                        state.life_interpolation = fromSceneInterpolation(key.interpolation);
                        project_editor_life.applyClip(state, clip);
                        project_editor_state.setStatus(state, "Keyframe selected");
                    }
                }
            }
        }
    }

    const playhead_x = rect.x + 8 + @as(f32, @floatFromInt(currentFrame(state))) * px_per_frame;
    try ui_widgets.text(ui, "life-playhead", .{ .x = playhead_x - 2, .y = ruler_y - 1, .w = 6, .h = rect.h - 6 }, "|", false);

    ui.endPanel();
}

pub fn buildInspectorPanel(ui: *core_ui.UiContext, state: *ProjectEditorState, rect: core_ui.Rect) !void {
    try ui.beginPanel(.{ .id = "ed-inspector-life", .rect = rect, .row_height = 24, .padding = 10, .spacing = 5 });
    try ui.label("Inspector");
    const scroll_h = try core_ui.layout.remainingPanelContentHeight(ui);
    var scrolled = false;
    if (scroll_h > 1) {
        try core_ui.layout.beginScrollArea(ui, .{ .id = "ed-inspector-life-scroll", .height = scroll_h, .input = core_ui.layout.panel_scroll_input });
        scrolled = true;
    }
    try buildInspector(ui, state);
    if (scrolled) try core_ui.layout.endScrollArea(ui);
    ui.endPanel();
}

pub fn buildToolInspector(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    switch (state.life_tool) {
        .select => try ui_widgets.compactInfo(ui, "Select objects, bones, tracks, or keys"),
        .pose => try buildPoseToolControls(ui, state),
        .keyframe => try buildKeyframeToolControls(ui, state),
        .record => try buildRecordToolControls(ui, state),
        .playback => try buildPlaybackToolControls(ui, state),
        .clips => try buildClipToolControls(ui, state),
        .bones => try buildBonesToolControls(ui, state),
        .curves => try buildCurvesPanel(ui, state),
    }
}

fn buildPoseToolControls(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    try ui_widgets.compactInfo(ui, if (state.life_auto_key) "Auto Key on" else "Auto Key off");
    if ((try ui_widgets.button(ui, command_ids.life_auto_key, "Auto Key", 88, state.life_auto_key)).clicked) {
        state.life_auto_key = !state.life_auto_key;
        state.life_recording = state.life_auto_key;
    }
    if (state.selected_object) |idx| {
        const obj = &state.objects.items[idx];
        if (obj.bone_pose.len > 0) {
            var bone_buf: [96]u8 = undefined;
            try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&bone_buf, "Bones {d}  Selected {d}", .{ obj.bone_pose.len, state.selected_bone orelse 0 }) catch "Bones");
            if ((try ui_widgets.button(ui, "ed-life-pose-next-bone", "Next Bone", 88, false)).clicked) project_editor_life.selectNextBone(state);
        } else {
            try ui_widgets.compactInfo(ui, "Pose selected object transform");
        }
    } else {
        try ui_widgets.compactInfo(ui, "Select an object to pose");
    }
}

fn buildKeyframeToolControls(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    var cur_buf: [64]u8 = undefined;
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&cur_buf, "Frame {d}", .{currentFrame(state)}) catch "Frame");
    try ui.label("Channels");
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.button(ui, "ed-life-tool-key-pos", "Position", 76, state.life_key_position)).clicked) state.life_key_position = !state.life_key_position;
    if ((try ui_widgets.button(ui, "ed-life-tool-key-rot", "Rotation", 76, state.life_key_rotation)).clicked) state.life_key_rotation = !state.life_key_rotation;
    if ((try ui_widgets.button(ui, "ed-life-tool-key-scale", "Scale", 64, state.life_key_scale)).clicked) state.life_key_scale = !state.life_key_scale;
    try core_ui.layout.endSameLine(ui);
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.button(ui, command_ids.life_add_keyframe, "Add Key", 72, false)).clicked) try project_editor_life.addObjectKeyframe(state);
    if ((try ui_widgets.button(ui, "ed-life-tool-bone-key", "Bone Key", 82, false)).clicked) try project_editor_life.addBoneKeyframe(state);
    try core_ui.layout.endSameLine(ui);
    try buildSelectedKeyframeForTool(ui, state);
}

fn buildSelectedKeyframeForTool(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    const track_idx = state.life_selected_track orelse {
        try ui_widgets.compactInfo(ui, "No keyframe selected");
        return;
    };
    const clip_idx = state.active_clip orelse return;
    if (clip_idx >= state.animations.items.len or track_idx >= state.animations.items[clip_idx].tracks.len) return;
    const track = &state.animations.items[clip_idx].tracks[track_idx];
    const key_idx = state.life_selected_keyframe orelse {
        try ui_widgets.compactInfo(ui, "Select a keyframe on the timeline");
        return;
    };
    if (key_idx < track.keyframes.len) try buildSelectedKeyframePanel(ui, state, track, key_idx);
}

fn buildRecordToolControls(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    try ui_widgets.compactInfo(ui, if (state.life_recording) "Recording on" else "Recording off");
    if ((try ui_widgets.button(ui, command_ids.life_record, "Record", 82, state.life_recording)).clicked) {
        project_editor_life.onToolActivated(state, .record);
    }
}

fn buildPlaybackToolControls(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.button(ui, command_ids.life_play, if (state.life_playing) "Pause" else "Play", 68, state.life_playing)).clicked) project_editor_life.togglePlayback(state);
    if ((try ui_widgets.button(ui, "ed-life-tool-speed-minus", "Spd-", 48, false)).clicked) state.life_playback_speed = @max(0.25, state.life_playback_speed - 0.25);
    var speed_buf: [48]u8 = undefined;
    _ = try ui_widgets.button(ui, "ed-life-tool-speed-label", std.fmt.bufPrint(&speed_buf, "{d:.2}x", .{state.life_playback_speed}) catch "1.00x", 64, false);
    if ((try ui_widgets.button(ui, "ed-life-tool-speed-plus", "Spd+", 48, false)).clicked) state.life_playback_speed = @min(4.0, state.life_playback_speed + 0.25);
    try core_ui.layout.endSameLine(ui);
}

fn buildClipToolControls(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    if ((try ui_widgets.button(ui, command_ids.life_add_clip, "Add Clip", 82, false)).clicked) try project_editor_life.addClip(state);
    const clip_idx = state.active_clip orelse {
        try ui_widgets.compactInfo(ui, "No clip selected");
        return;
    };
    if (clip_idx >= state.animations.items.len) return;
    const clip = &state.animations.items[clip_idx];
    var len_buf: [96]u8 = undefined;
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&len_buf, "Length {d:.2}s ({d}f)", .{ clip.duration, timeToFrame(clip.duration) }) catch "Length");
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.button(ui, "ed-life-tool-len-minus", "-10f", 48, false)).clicked) {
        project_editor_edit.pushUndoSnapshot(state);
        clip.duration = @max(frameToTime(1), clip.duration - frameToTime(10));
        state.scene_dirty = true;
    }
    if ((try ui_widgets.button(ui, "ed-life-tool-len-plus", "+10f", 48, false)).clicked) {
        project_editor_edit.pushUndoSnapshot(state);
        clip.duration += frameToTime(10);
        state.scene_dirty = true;
    }
    const loop = try ui_widgets.syncedCheckbox(ui, "Loop", "ed-life-tool-loop", clip.looping);
    if (loop.clicked) {
        project_editor_edit.pushUndoSnapshot(state);
        clip.looping = loop.checked;
        state.scene_dirty = true;
    }
    try core_ui.layout.endSameLine(ui);
}

fn buildBonesToolControls(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    const obj_idx = state.selected_object orelse {
        try ui_widgets.compactInfo(ui, "Select a skeletal object");
        return;
    };
    const obj = &state.objects.items[obj_idx];
    if (obj.bone_pose.len == 0) {
        try ui_widgets.compactInfo(ui, "No bones on object");
        return;
    }
    var bone_buf: [96]u8 = undefined;
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&bone_buf, "Bones {d}  Selected {d}", .{ obj.bone_pose.len, state.selected_bone orelse 0 }) catch "Bones");
    if ((try ui_widgets.button(ui, "ed-life-tool-next-bone", "Next Bone", 88, false)).clicked) project_editor_life.selectNextBone(state);
}

pub fn buildInspector(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    try ui.label("Clip");
    if (state.active_clip) |clip_idx| {
        if (clip_idx < state.animations.items.len) {
            const clip = &state.animations.items[clip_idx];
            var len_buf: [96]u8 = undefined;
            try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&len_buf, "Length {d:.2}s ({d}f)", .{ clip.duration, timeToFrame(clip.duration) }) catch "Length");
            try core_ui.layout.sameLine(ui);
            if ((try ui_widgets.button(ui, "ed-life-len-minus", "-", 28, false)).clicked) {
                project_editor_edit.pushUndoSnapshot(state);
                clip.duration = @max(frameToTime(1), clip.duration - frameToTime(10));
                state.scene_dirty = true;
            }
            if ((try ui_widgets.button(ui, "ed-life-len-plus", "+", 28, false)).clicked) {
                project_editor_edit.pushUndoSnapshot(state);
                clip.duration += frameToTime(10);
                state.scene_dirty = true;
            }
            const loop = try ui_widgets.syncedCheckbox(ui, "Loop", "ed-life-loop", clip.looping);
            if (loop.clicked) {
                project_editor_edit.pushUndoSnapshot(state);
                clip.looping = loop.checked;
                state.scene_dirty = true;
            }
            try core_ui.layout.endSameLine(ui);
            try core_ui.layout.sameLine(ui);
            if ((try ui_widgets.button(ui, "ed-life-speed-minus", "Spd-", 48, false)).clicked) {
                state.life_playback_speed = @max(0.25, state.life_playback_speed - 0.25);
            }
            var speed_buf: [48]u8 = undefined;
            _ = try ui_widgets.button(ui, "ed-life-speed-label", std.fmt.bufPrint(&speed_buf, "Speed {d:.2}x", .{state.life_playback_speed}) catch "Speed", 96, false);
            if ((try ui_widgets.button(ui, "ed-life-speed-plus", "Spd+", 48, false)).clicked) {
                state.life_playback_speed = @min(4.0, state.life_playback_speed + 0.25);
            }
            try core_ui.layout.endSameLine(ui);
        }
    } else {
        try ui_widgets.compactInfo(ui, "No clip selected");
        if ((try ui_widgets.button(ui, command_ids.life_add_clip, "Add Clip", 82, false)).clicked) try project_editor_life.addClip(state);
    }

    try ui.label("Keyframe");
    if (state.life_selected_track) |track_idx| {
        if (state.active_clip) |clip_idx| {
            if (clip_idx < state.animations.items.len and track_idx < state.animations.items[clip_idx].tracks.len) {
                const track = &state.animations.items[clip_idx].tracks[track_idx];
                if (state.life_selected_keyframe) |key_idx| {
                    if (key_idx < track.keyframes.len) {
                        try buildSelectedKeyframePanel(ui, state, track, key_idx);
                    }
                } else {
                    try ui_widgets.compactInfo(ui, "Select a keyframe on the timeline");
                }
            }
        }
    } else {
        var cur_buf: [64]u8 = undefined;
        try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&cur_buf, "Frame {d} (current)", .{currentFrame(state)}) catch "Frame");
        try ui_widgets.compactInfo(ui, "No keyframe selected");
    }

    try ui.label("Key Channels");
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.button(ui, "ed-life-key-pos", "Position", 76, state.life_key_position)).clicked) state.life_key_position = !state.life_key_position;
    if ((try ui_widgets.button(ui, "ed-life-key-rot", "Rotation", 76, state.life_key_rotation)).clicked) state.life_key_rotation = !state.life_key_rotation;
    if ((try ui_widgets.button(ui, "ed-life-key-scale", "Scale", 64, state.life_key_scale)).clicked) state.life_key_scale = !state.life_key_scale;
    try core_ui.layout.endSameLine(ui);
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.button(ui, command_ids.life_add_keyframe, "Add Key", 72, false)).clicked) try project_editor_life.addObjectKeyframe(state);
    if ((try ui_widgets.button(ui, "ed-life-bone-key-inspector", "Bone Key", 82, false)).clicked) try project_editor_life.addBoneKeyframe(state);
    try core_ui.layout.endSameLine(ui);

    if (state.life_tool == .curves) {
        try buildCurvesPanel(ui, state);
    }

    if (state.selected_object) |idx| {
        const obj = &state.objects.items[idx];
        if (obj.bone_pose.len > 0) {
            var bone_buf: [96]u8 = undefined;
            try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&bone_buf, "Bones {d}  Selected {d}", .{ obj.bone_pose.len, state.selected_bone orelse 0 }) catch "Bones");
            try core_ui.layout.sameLine(ui);
            if ((try ui_widgets.button(ui, "ed-life-next-bone", "Next Bone", 88, false)).clicked) project_editor_life.selectNextBone(state);
            try core_ui.layout.endSameLine(ui);
        }
    }
}

pub fn buildBottomBar(ui: *core_ui.UiContext, state: *ProjectEditorState, rect: core_ui.Rect) !void {
    var frame_buf: [64]u8 = undefined;
    const frame_label = std.fmt.bufPrint(&frame_buf, "Frame {d}/{d}", .{ currentFrame(state), clipTotalFrames(state) }) catch "Frame";
    try ui_widgets.text(ui, "ed-life-frame", .{ .x = rect.x + rect.w - 520, .y = rect.y + 5, .w = 120, .h = 22 }, frame_label, false);

    const playback_label = if (state.life_playing) "Playback Playing" else "Playback Paused";
    const play_btn = try ui_widgets.iconOverlayButton(
        ui,
        command_ids.life_play,
        "play",
        .{ .x = rect.x + rect.w - 390, .y = rect.y + 4, .w = 24, .h = 22 },
        state.life_playing,
    );
    if (play_btn.clicked) project_editor_life.togglePlayback(state);
    try ui_widgets.text(ui, "ed-life-playback", .{ .x = rect.x + rect.w - 360, .y = rect.y + 5, .w = 140, .h = 22 }, playback_label, false);

    const auto_key_btn = try ui_widgets.iconOverlayButton(
        ui,
        command_ids.life_auto_key,
        "music-note",
        .{ .x = rect.x + rect.w - 200, .y = rect.y + 4, .w = 24, .h = 22 },
        state.life_auto_key,
    );
    if (auto_key_btn.clicked) {
        state.life_auto_key = !state.life_auto_key;
        state.life_recording = state.life_auto_key;
    }
    try ui_widgets.text(ui, "ed-life-auto-key", .{ .x = rect.x + rect.w - 170, .y = rect.y + 5, .w = 96, .h = 22 }, if (state.life_auto_key) "Auto Key on" else "Auto Key off", false);
}

fn buildCurvesPanel(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    try ui.label("Curves");
    const track_idx = state.life_selected_track orelse {
        try ui_widgets.compactInfo(ui, "Select a track");
        return;
    };
    const clip_idx = state.active_clip orelse {
        try ui_widgets.compactInfo(ui, "Select a clip");
        return;
    };
    if (clip_idx >= state.animations.items.len or track_idx >= state.animations.items[clip_idx].tracks.len) return;
    const track = state.animations.items[clip_idx].tracks[track_idx];
    if (track.keyframes.len == 0) {
        try ui_widgets.compactInfo(ui, "No keyframes on track");
        return;
    }
    var track_buf: [128]u8 = undefined;
    try ui_widgets.compactInfo(ui, formatTrackLabel(state, track.target, &track_buf) catch "Track");
    var summary_buf: [160]u8 = undefined;
    try ui_widgets.compactInfo(ui, formatTrackSummary(track, &summary_buf) catch "Track summary");
    for (track.keyframes, 0..) |key, key_idx| {
        var row_buf: [160]u8 = undefined;
        const row_label = formatKeyframeRow(key, &row_buf) catch "Keyframe";
        var id_buf: [48]u8 = undefined;
        const row_id = std.fmt.bufPrint(&id_buf, "life-curve-key-{d}-{d}", .{ track_idx, key_idx }) catch "life-curve-key";
        const selected = state.life_selected_keyframe == key_idx;
        if ((try ui_widgets.row(ui, row_id, row_label, selected)).clicked) {
            project_editor_life.selectKeyframe(state, clip_idx, track_idx, key_idx);
        }
    }
}

fn buildSelectedKeyframePanel(ui: *core_ui.UiContext, state: *ProjectEditorState, track: *const scene_animation.Track, key_idx: usize) !void {
    const key = track.keyframes[key_idx];
    var track_buf: [128]u8 = undefined;
    try ui_widgets.compactInfo(ui, formatTrackLabel(state, track.target, &track_buf) catch "Track");

    var frame_buf: [96]u8 = undefined;
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&frame_buf, "Frame {d}  Time {d:.3}s", .{ timeToFrame(key.time), key.time }) catch "Frame");
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.button(ui, "ed-life-key-prev-frame", "-1f", 42, false)).clicked) {
        project_editor_life.nudgeSelectedKeyframeTime(state, -frameToTime(1));
    }
    if ((try ui_widgets.button(ui, "ed-life-key-next-frame", "+1f", 42, false)).clicked) {
        project_editor_life.nudgeSelectedKeyframeTime(state, frameToTime(1));
    }
    if ((try ui_widgets.button(ui, "ed-life-key-stamp", "Use Pose", 82, false)).clicked) {
        project_editor_life.stampSelectedKeyframeFromScene(state);
    }
    try core_ui.layout.endSameLine(ui);

    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.button(ui, "ed-life-interp", key.interpolation.label(), 82, false)).clicked) {
        state.life_interpolation = fromSceneInterpolation(key.interpolation).next();
        project_editor_life.setSelectedKeyframeInterpolation(state, state.life_interpolation);
    }
    var channels = key.channels;
    if ((try ui_widgets.button(ui, "ed-life-key-channel-pos", "Pos", 46, channels.position)).clicked) {
        channels.position = !channels.position;
        project_editor_life.setSelectedKeyframeChannels(state, channels);
    }
    if ((try ui_widgets.button(ui, "ed-life-key-channel-rot", "Rot", 46, channels.rotation)).clicked) {
        channels.rotation = !channels.rotation;
        project_editor_life.setSelectedKeyframeChannels(state, channels);
    }
    if ((try ui_widgets.button(ui, "ed-life-key-channel-scale", "Scale", 58, channels.scale)).clicked) {
        channels.scale = !channels.scale;
        project_editor_life.setSelectedKeyframeChannels(state, channels);
    }
    try core_ui.layout.endSameLine(ui);

    try buildTransformReadout(ui, key.transform);
}

fn buildTransformReadout(ui: *core_ui.UiContext, transform: scene_animation.Transform) !void {
    var pos_buf: [96]u8 = undefined;
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&pos_buf, "Pos {d:.2}, {d:.2}, {d:.2}", .{
        transform.position.x,
        transform.position.y,
        transform.position.z,
    }) catch "Pos");
    var rot_buf: [96]u8 = undefined;
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&rot_buf, "Rot {d:.2}, {d:.2}, {d:.2}", .{
        transform.rotation.x,
        transform.rotation.y,
        transform.rotation.z,
    }) catch "Rot");
    var scale_buf: [96]u8 = undefined;
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&scale_buf, "Scale {d:.2}, {d:.2}, {d:.2}", .{
        transform.scale.x,
        transform.scale.y,
        transform.scale.z,
    }) catch "Scale");
}

fn formatTrackSummary(track: scene_animation.Track, buf: []u8) ![]const u8 {
    var pos_count: usize = 0;
    var rot_count: usize = 0;
    var scale_count: usize = 0;
    for (track.keyframes) |key| {
        if (key.channels.position) pos_count += 1;
        if (key.channels.rotation) rot_count += 1;
        if (key.channels.scale) scale_count += 1;
    }
    const first = track.keyframes[0];
    const last = track.keyframes[track.keyframes.len - 1];
    return std.fmt.bufPrint(buf, "{d} keys  f{d}-f{d}  P{d} R{d} S{d}", .{
        track.keyframes.len,
        timeToFrame(first.time),
        timeToFrame(last.time),
        pos_count,
        rot_count,
        scale_count,
    });
}

fn formatKeyframeRow(key: scene_animation.Keyframe, buf: []u8) ![]const u8 {
    var channels_buf: [4]u8 = .{ '-', '-', '-', 0 };
    if (key.channels.position) channels_buf[0] = 'P';
    if (key.channels.rotation) channels_buf[1] = 'R';
    if (key.channels.scale) channels_buf[2] = 'S';
    if (key.channels.rotation and !key.channels.position and !key.channels.scale) {
        return std.fmt.bufPrint(buf, "f{d} {s} {s} rot {d:.2},{d:.2},{d:.2}", .{
            timeToFrame(key.time),
            channels_buf[0..3],
            key.interpolation.label(),
            key.transform.rotation.x,
            key.transform.rotation.y,
            key.transform.rotation.z,
        });
    }
    return std.fmt.bufPrint(buf, "f{d} {s} {s} pos {d:.2},{d:.2},{d:.2}", .{
        timeToFrame(key.time),
        channels_buf[0..3],
        key.interpolation.label(),
        key.transform.position.x,
        key.transform.position.y,
        key.transform.position.z,
    });
}

fn formatTrackLabel(state: *const ProjectEditorState, target: scene_animation.PoseTarget, buf: []u8) ![]const u8 {
    return switch (target) {
        .object => |id| blk: {
            const name = objectName(state, id) orelse "Object";
            break :blk try std.fmt.bufPrint(buf, "{s} transform", .{name});
        },
        .bone => |bone| blk: {
            const name = objectName(state, bone.object_id) orelse "Object";
            const bone_name = if (objectIndexById(state, bone.object_id)) |obj_idx| project_editor_life_gizmo.boneName(state, obj_idx, bone.bone_index) else "Bone";
            break :blk try std.fmt.bufPrint(buf, "{s} bone {d}: {s}", .{ name, bone.bone_index, bone_name });
        },
    };
}

fn objectName(state: *const ProjectEditorState, id: u64) ?[]const u8 {
    for (state.objects.items) |obj| {
        if (obj.id == id) return obj.name;
    }
    return null;
}

fn objectIndexById(state: *const ProjectEditorState, id: u64) ?usize {
    for (state.objects.items, 0..) |obj, idx| {
        if (obj.id == id) return idx;
    }
    return null;
}

fn fromSceneInterpolation(interp: scene_animation.Interpolation) project_editor_types.LifeInterpolation {
    return @enumFromInt(@intFromEnum(interp));
}
