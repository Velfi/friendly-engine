const std = @import("std");
const kdl = @import("kdl");
const scene_animation = @import("scene_animation.zig");
const editor_math = @import("editor_math.zig");

pub fn parseAnimations(allocator: std.mem.Allocator, source: []const u8) !struct {
    clips: []scene_animation.Clip,
    skeletons: []scene_animation.Skeleton,
} {
    const buffer = try allocator.allocSentinel(u8, source.len, 0);
    defer allocator.free(buffer);
    @memcpy(buffer, source);

    var parser = kdl.Parser.init(buffer);
    var depth: i32 = 0;
    var clip: ?ClipBuilder = null;
    var track: ?TrackBuilder = null;
    var pose: ?PoseBuilder = null;
    var skeleton: ?SkeletonBuilder = null;
    var clips = std.ArrayList(scene_animation.Clip).empty;
    var skeletons = std.ArrayList(scene_animation.Skeleton).empty;
    errdefer {
        for (clips.items) |*item| item.deinit(allocator);
        clips.deinit(allocator);
        for (skeletons.items) |*item| item.deinit(allocator);
        skeletons.deinit(allocator);
    }

    while (true) {
        const event = try parser.next();
        switch (event) {
            .node => |node| {
                if (depth == 1 and std.mem.eql(u8, node.val, "animation_clip")) {
                    clip = ClipBuilder.init(allocator);
                } else if (depth == 2 and clip != null and std.mem.eql(u8, node.val, "track")) {
                    track = TrackBuilder.init(allocator);
                } else if (depth == 2 and clip != null and std.mem.eql(u8, node.val, "pose")) {
                    pose = PoseBuilder.init(allocator);
                } else if (depth == 1 and std.mem.eql(u8, node.val, "skeleton")) {
                    skeleton = SkeletonBuilder.init(allocator);
                } else if (depth == 3 and track != null and std.mem.eql(u8, node.val, "keyframe")) {
                    try track.?.finishKeyframe();
                } else if (depth == 3 and pose != null and std.mem.eql(u8, node.val, "snapshot")) {
                    try pose.?.finishSnapshot();
                } else if (depth == 2 and skeleton != null and std.mem.eql(u8, node.val, "bone")) {
                    try skeleton.?.finishBone();
                }
            },
            .prop => |prop| {
                const value = try decodeValue(allocator, prop.val);
                defer allocator.free(value);
                if (depth == 1 and clip != null) try clip.?.apply(prop.key, value);
                if (depth == 2 and track != null) try track.?.apply(prop.key, value);
                if (depth == 2 and pose != null) try pose.?.apply(prop.key, value);
                if (depth == 3 and track != null) try track.?.applyKeyframe(prop.key, value);
                if (depth == 3 and pose != null) try pose.?.applySnapshot(prop.key, value);
                if (depth == 1 and skeleton != null) try skeleton.?.apply(prop.key, value);
                if (depth == 2 and skeleton != null) try skeleton.?.applyBone(prop.key, value);
            },
            .child_block_begin => depth += 1,
            .child_block_end => {
                if (depth == 3 and track != null and clip != null) {
                    try track.?.finishKeyframe();
                    try clip.?.tracks.append(allocator, try track.?.finish());
                    track = null;
                } else if (depth == 3 and pose != null and clip != null) {
                    try pose.?.finishSnapshot();
                    try clip.?.poses.append(allocator, try pose.?.finish());
                    pose = null;
                } else if (depth == 2 and clip != null) {
                    try clips.append(allocator, try clip.?.finish());
                    clip = null;
                } else if (depth == 2 and skeleton != null) {
                    try skeletons.append(allocator, try skeleton.?.finish());
                    skeleton = null;
                }
                depth -= 1;
            },
            .arg, .invalid => return error.InvalidSceneAnimationDocument,
            .eof => break,
        }
    }
    return .{ .clips = try clips.toOwnedSlice(allocator), .skeletons = try skeletons.toOwnedSlice(allocator) };
}

fn boolName(value: bool) []const u8 {
    return if (value) "true" else "false";
}

fn interpolationName(value: scene_animation.Interpolation) []const u8 {
    return switch (value) {
        .linear => "linear",
        .ease_in => "ease_in",
        .ease_out => "ease_out",
        .hold => "hold",
    };
}

pub fn writeAnimations(writer: anytype, clips: []const scene_animation.Clip, skeletons: []const scene_animation.Skeleton) !void {
    for (skeletons) |skeleton| {
        try writer.print("  skeleton asset=\"{s}\" {{\n", .{skeleton.asset});
        for (skeleton.bones) |bone| {
            try writer.print(
                "    bone index={d} parent={d} name=\"{s}\" rest_position=\"{d},{d},{d}\" rest_rotation=\"{d},{d},{d}\" rest_scale=\"{d},{d},{d}\"\n",
                .{
                    bone.index,
                    if (bone.parent) |p| @as(i32, @intCast(p)) else -1,
                    bone.name,
                    bone.rest.position.x,
                    bone.rest.position.y,
                    bone.rest.position.z,
                    bone.rest.rotation.x,
                    bone.rest.rotation.y,
                    bone.rest.rotation.z,
                    bone.rest.scale.x,
                    bone.rest.scale.y,
                    bone.rest.scale.z,
                },
            );
        }
        try writer.writeAll("  }\n");
    }
    for (clips) |clip| {
        try writer.print("  animation_clip id={d} name=\"{s}\" duration={d} looping={s} {{\n", .{ clip.id, clip.name, clip.duration, boolName(clip.looping) });
        for (clip.tracks) |track| {
            switch (track.target) {
                .object => |id| try writer.print("    track target=object object_id={d} {{\n", .{id}),
                .bone => |bone| try writer.print("    track target=bone object_id={d} bone_index={d} {{\n", .{ bone.object_id, bone.bone_index }),
            }
            for (track.keyframes) |key| {
                try writer.print(
                    "      keyframe time={d} position=\"{d},{d},{d}\" rotation=\"{d},{d},{d}\" scale=\"{d},{d},{d}\"",
                    .{
                        key.time,
                        key.transform.position.x,
                        key.transform.position.y,
                        key.transform.position.z,
                        key.transform.rotation.x,
                        key.transform.rotation.y,
                        key.transform.rotation.z,
                        key.transform.scale.x,
                        key.transform.scale.y,
                        key.transform.scale.z,
                    },
                );
                if (!key.channels.position or !key.channels.rotation or !key.channels.scale or key.interpolation != .linear) {
                    try writer.print(
                        " key_position={s} key_rotation={s} key_scale={s} interpolation=\"{s}\"",
                        .{
                            boolName(key.channels.position),
                            boolName(key.channels.rotation),
                            boolName(key.channels.scale),
                            interpolationName(key.interpolation),
                        },
                    );
                }
                try writer.writeAll("\n");
            }
            try writer.writeAll("    }\n");
        }
        for (clip.poses) |pose| {
            try writer.print("    pose name=\"{s}\" {{\n", .{pose.name});
            for (pose.snapshots) |snap| {
                switch (snap.target) {
                    .object => |id| try writer.print(
                        "      snapshot target=object object_id={d} position=\"{d},{d},{d}\" rotation=\"{d},{d},{d}\" scale=\"{d},{d},{d}\"\n",
                        .{
                            id,
                            snap.transform.position.x,
                            snap.transform.position.y,
                            snap.transform.position.z,
                            snap.transform.rotation.x,
                            snap.transform.rotation.y,
                            snap.transform.rotation.z,
                            snap.transform.scale.x,
                            snap.transform.scale.y,
                            snap.transform.scale.z,
                        },
                    ),
                    .bone => |bone| try writer.print(
                        "      snapshot target=bone object_id={d} bone_index={d} position=\"{d},{d},{d}\" rotation=\"{d},{d},{d}\" scale=\"{d},{d},{d}\"\n",
                        .{
                            bone.object_id,
                            bone.bone_index,
                            snap.transform.position.x,
                            snap.transform.position.y,
                            snap.transform.position.z,
                            snap.transform.rotation.x,
                            snap.transform.rotation.y,
                            snap.transform.rotation.z,
                            snap.transform.scale.x,
                            snap.transform.scale.y,
                            snap.transform.scale.z,
                        },
                    ),
                }
            }
            try writer.writeAll("    }\n");
        }
        try writer.writeAll("  }\n");
    }
}

const ClipBuilder = struct {
    allocator: std.mem.Allocator,
    id: u64 = 1,
    name: ?[]u8 = null,
    duration: f32 = 1,
    looping: bool = true,
    tracks: std.ArrayList(scene_animation.Track) = .empty,
    poses: std.ArrayList(scene_animation.NamedPose) = .empty,

    fn init(allocator: std.mem.Allocator) ClipBuilder {
        return .{ .allocator = allocator };
    }

    fn apply(self: *ClipBuilder, key: []const u8, value: []const u8) !void {
        if (std.mem.eql(u8, key, "id")) self.id = try parseU64(value);
        if (std.mem.eql(u8, key, "name")) self.name = try self.allocator.dupe(u8, value);
        if (std.mem.eql(u8, key, "duration")) self.duration = try parseF32(value);
        if (std.mem.eql(u8, key, "looping")) self.looping = try parseBool(value);
    }

    fn finish(self: *ClipBuilder) !scene_animation.Clip {
        return .{
            .id = self.id,
            .name = self.name orelse try self.allocator.dupe(u8, "Clip"),
            .duration = self.duration,
            .looping = self.looping,
            .tracks = try self.tracks.toOwnedSlice(self.allocator),
            .poses = try self.poses.toOwnedSlice(self.allocator),
        };
    }
};

const TrackBuilder = struct {
    allocator: std.mem.Allocator,
    target: ?scene_animation.PoseTarget = null,
    pending: ?scene_animation.Keyframe = null,
    keyframes: std.ArrayList(scene_animation.Keyframe) = .empty,
    object_id: u64 = 0,
    bone_index: u32 = 0,
    bone_target: bool = false,

    fn init(allocator: std.mem.Allocator) TrackBuilder {
        return .{ .allocator = allocator };
    }

    fn apply(self: *TrackBuilder, key: []const u8, value: []const u8) !void {
        if (std.mem.eql(u8, key, "object_id")) self.object_id = try parseU64(value);
        if (std.mem.eql(u8, key, "bone_index")) self.bone_index = try parseU32(value);
        if (std.mem.eql(u8, key, "target")) {
            self.bone_target = std.mem.eql(u8, value, "bone");
        }
    }

    fn applyKeyframe(self: *TrackBuilder, key: []const u8, value: []const u8) !void {
        var pending = self.pending orelse scene_animation.Keyframe{ .time = 0, .transform = .{} };
        if (std.mem.eql(u8, key, "time")) pending.time = try parseF32(value);
        if (std.mem.eql(u8, key, "position")) pending.transform.position = try parseVec3(value);
        if (std.mem.eql(u8, key, "rotation")) pending.transform.rotation = try parseVec3(value);
        if (std.mem.eql(u8, key, "scale")) pending.transform.scale = try parseVec3(value);
        if (std.mem.eql(u8, key, "key_position")) pending.channels.position = try parseBool(value);
        if (std.mem.eql(u8, key, "key_rotation")) pending.channels.rotation = try parseBool(value);
        if (std.mem.eql(u8, key, "key_scale")) pending.channels.scale = try parseBool(value);
        if (std.mem.eql(u8, key, "interpolation")) pending.interpolation = try parseInterpolation(value);
        self.pending = pending;
    }

    fn finishKeyframe(self: *TrackBuilder) !void {
        if (self.pending) |key| {
            try self.keyframes.append(self.allocator, key);
            self.pending = null;
        }
    }

    fn finish(self: *TrackBuilder) !scene_animation.Track {
        const target: scene_animation.PoseTarget = if (self.bone_target)
            .{ .bone = .{ .object_id = self.object_id, .bone_index = self.bone_index } }
        else
            .{ .object = self.object_id };
        return .{ .target = self.target orelse target, .keyframes = try self.keyframes.toOwnedSlice(self.allocator) };
    }
};

const PoseBuilder = struct {
    allocator: std.mem.Allocator,
    name: ?[]u8 = null,
    pending_snapshot: ?scene_animation.PoseSnapshot = null,
    snapshots: std.ArrayList(scene_animation.PoseSnapshot) = .empty,
    snapshot_object_id: u64 = 0,
    snapshot_bone_index: u32 = 0,
    snapshot_bone_target: bool = false,

    fn init(allocator: std.mem.Allocator) PoseBuilder {
        return .{ .allocator = allocator };
    }

    fn apply(self: *PoseBuilder, key: []const u8, value: []const u8) !void {
        if (std.mem.eql(u8, key, "name")) self.name = try self.allocator.dupe(u8, value);
    }

    fn applySnapshot(self: *PoseBuilder, key: []const u8, value: []const u8) !void {
        var pending = self.pending_snapshot orelse scene_animation.PoseSnapshot{
            .target = .{ .object = self.snapshot_object_id },
            .transform = .{},
        };
        if (std.mem.eql(u8, key, "object_id")) self.snapshot_object_id = try parseU64(value);
        if (std.mem.eql(u8, key, "bone_index")) self.snapshot_bone_index = try parseU32(value);
        if (std.mem.eql(u8, key, "target")) self.snapshot_bone_target = std.mem.eql(u8, value, "bone");
        if (std.mem.eql(u8, key, "position")) pending.transform.position = try parseVec3(value);
        if (std.mem.eql(u8, key, "rotation")) pending.transform.rotation = try parseVec3(value);
        if (std.mem.eql(u8, key, "scale")) pending.transform.scale = try parseVec3(value);
        pending.target = if (self.snapshot_bone_target)
            .{ .bone = .{ .object_id = self.snapshot_object_id, .bone_index = self.snapshot_bone_index } }
        else
            .{ .object = self.snapshot_object_id };
        self.pending_snapshot = pending;
    }

    fn finishSnapshot(self: *PoseBuilder) !void {
        if (self.pending_snapshot) |snapshot| {
            try self.snapshots.append(self.allocator, snapshot);
            self.pending_snapshot = null;
        }
    }

    fn finish(self: *PoseBuilder) !scene_animation.NamedPose {
        return .{
            .name = self.name orelse try self.allocator.dupe(u8, "Pose"),
            .snapshots = try self.snapshots.toOwnedSlice(self.allocator),
        };
    }
};

const SkeletonBuilder = struct {
    allocator: std.mem.Allocator,
    asset: ?[]u8 = null,
    bones: std.ArrayList(scene_animation.Bone) = .empty,
    pending: ?scene_animation.Bone = null,

    fn init(allocator: std.mem.Allocator) SkeletonBuilder {
        return .{ .allocator = allocator };
    }

    fn apply(self: *SkeletonBuilder, key: []const u8, value: []const u8) !void {
        if (std.mem.eql(u8, key, "asset")) self.asset = try self.allocator.dupe(u8, value);
    }

    fn applyBone(self: *SkeletonBuilder, key: []const u8, value: []const u8) !void {
        var bone = self.pending orelse scene_animation.Bone{ .index = 0, .name = try self.allocator.dupe(u8, "Bone") };
        if (std.mem.eql(u8, key, "index")) bone.index = try parseU32(value);
        if (std.mem.eql(u8, key, "parent")) {
            const parent = try std.fmt.parseInt(i32, value, 10);
            bone.parent = if (parent < 0) null else @intCast(parent);
        }
        if (std.mem.eql(u8, key, "name")) {
            self.allocator.free(bone.name);
            bone.name = try self.allocator.dupe(u8, value);
        }
        if (std.mem.eql(u8, key, "rest_position")) bone.rest.position = try parseVec3(value);
        if (std.mem.eql(u8, key, "rest_rotation")) bone.rest.rotation = try parseVec3(value);
        if (std.mem.eql(u8, key, "rest_scale")) bone.rest.scale = try parseVec3(value);
        self.pending = bone;
    }

    fn finishBone(self: *SkeletonBuilder) !void {
        if (self.pending) |bone| {
            try self.bones.append(self.allocator, bone);
            self.pending = null;
        }
    }

    fn finish(self: *SkeletonBuilder) !scene_animation.Skeleton {
        try self.finishBone();
        return .{ .asset = self.asset orelse try self.allocator.dupe(u8, ""), .bones = try self.bones.toOwnedSlice(self.allocator) };
    }
};

fn decodeValue(allocator: std.mem.Allocator, raw: []const u8) ![]const u8 {
    return kdl.string_utils.makeRealString(allocator, raw);
}

fn parseInterpolation(text: []const u8) !scene_animation.Interpolation {
    if (std.mem.eql(u8, text, "linear")) return .linear;
    if (std.mem.eql(u8, text, "ease_in")) return .ease_in;
    if (std.mem.eql(u8, text, "ease_out")) return .ease_out;
    if (std.mem.eql(u8, text, "hold")) return .hold;
    return error.InvalidValue;
}

fn parseBool(text: []const u8) !bool {
    if (std.mem.eql(u8, text, "true")) return true;
    if (std.mem.eql(u8, text, "false")) return false;
    return error.InvalidValue;
}

fn parseU64(text: []const u8) !u64 {
    return std.fmt.parseInt(u64, text, 10);
}

fn parseU32(text: []const u8) !u32 {
    return std.fmt.parseInt(u32, text, 10);
}

fn parseF32(text: []const u8) !f32 {
    return std.fmt.parseFloat(f32, text);
}

fn parseVec3(text: []const u8) !editor_math.Vec3 {
    var iter = std.mem.splitScalar(u8, text, ',');
    const x = try parseF32(std.mem.trim(u8, iter.next() orelse return error.InvalidValue, " \t"));
    const y = try parseF32(std.mem.trim(u8, iter.next() orelse return error.InvalidValue, " \t"));
    const z = try parseF32(std.mem.trim(u8, iter.next() orelse return error.InvalidValue, " \t"));
    if (iter.next() != null) return error.InvalidValue;
    return .{ .x = x, .y = y, .z = z };
}

test "named pose snapshots parse from animation clip" {
    const source =
        \\scene version=1 next_object_id=2 {
        \\  animation_clip id=1 name="Wave" duration=1 looping=true {
        \\    pose name="raised" {
        \\      snapshot target=object object_id=1 position="0,1,0" rotation="0,0.5,0" scale="1,1,1"
        \\      snapshot target=bone object_id=1 bone_index=1 position="0,1,0" rotation="0,0.25,0" scale="1,1,1"
        \\    }
        \\  }
        \\}
        \\
    ;

    const parsed = try parseAnimations(std.testing.allocator, source);
    defer {
        for (parsed.clips) |*clip| clip.deinit(std.testing.allocator);
        std.testing.allocator.free(parsed.clips);
        for (parsed.skeletons) |*skeleton| skeleton.deinit(std.testing.allocator);
        std.testing.allocator.free(parsed.skeletons);
    }

    try std.testing.expectEqual(@as(usize, 1), parsed.clips.len);
    try std.testing.expectEqual(@as(usize, 1), parsed.clips[0].poses.len);
    try std.testing.expectEqualStrings("raised", parsed.clips[0].poses[0].name);
    try std.testing.expectEqual(@as(usize, 2), parsed.clips[0].poses[0].snapshots.len);
    try std.testing.expectEqual(@as(f32, 1), parsed.clips[0].poses[0].snapshots[0].transform.position.y);
    try std.testing.expect(parsed.clips[0].poses[0].snapshots[1].target == .bone);
}
