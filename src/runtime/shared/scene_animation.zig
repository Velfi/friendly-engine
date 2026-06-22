const std = @import("std");
const editor_math = @import("editor_math.zig");

pub const Transform = struct {
    position: editor_math.Vec3 = .{ .x = 0, .y = 0, .z = 0 },
    rotation: editor_math.Vec3 = .{ .x = 0, .y = 0, .z = 0 },
    scale: editor_math.Vec3 = .{ .x = 1, .y = 1, .z = 1 },
};

pub const Interpolation = enum {
    linear,
    ease_in,
    ease_out,
    hold,

    pub fn label(self: Interpolation) []const u8 {
        return switch (self) {
            .linear => "Linear",
            .ease_in => "Ease In",
            .ease_out => "Ease Out",
            .hold => "Hold",
        };
    }

    pub fn next(self: Interpolation) Interpolation {
        return switch (self) {
            .linear => .ease_in,
            .ease_in => .ease_out,
            .ease_out => .hold,
            .hold => .linear,
        };
    }
};

pub const KeyChannels = struct {
    position: bool = true,
    rotation: bool = true,
    scale: bool = true,

    pub fn any(self: KeyChannels) bool {
        return self.position or self.rotation or self.scale;
    }
};

pub const PoseTarget = union(enum) {
    object: u64,
    bone: struct {
        object_id: u64,
        bone_index: u32,
    },
};

pub const Keyframe = struct {
    time: f32,
    transform: Transform,
    channels: KeyChannels = .{},
    interpolation: Interpolation = .linear,
};

pub const Track = struct {
    target: PoseTarget,
    keyframes: []Keyframe = &.{},

    pub fn deinit(self: *Track, allocator: std.mem.Allocator) void {
        allocator.free(self.keyframes);
    }
};

pub const PoseSnapshot = struct {
    target: PoseTarget,
    transform: Transform,
};

pub const NamedPose = struct {
    name: []u8,
    snapshots: []PoseSnapshot = &.{},

    pub fn deinit(self: *NamedPose, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.snapshots);
    }
};

pub const Clip = struct {
    id: u64,
    name: []u8,
    duration: f32,
    looping: bool = true,
    tracks: []Track = &.{},
    poses: []NamedPose = &.{},

    pub fn deinit(self: *Clip, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        for (self.tracks) |*track| track.deinit(allocator);
        allocator.free(self.tracks);
        for (self.poses) |*pose| pose.deinit(allocator);
        allocator.free(self.poses);
    }
};

pub const Bone = struct {
    index: u32,
    parent: ?u32 = null,
    name: []u8,
    rest: Transform = .{},

    pub fn deinit(self: *Bone, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }
};

pub const Skeleton = struct {
    asset: []u8,
    bones: []Bone = &.{},

    pub fn deinit(self: *Skeleton, allocator: std.mem.Allocator) void {
        allocator.free(self.asset);
        for (self.bones) |*bone| bone.deinit(allocator);
        allocator.free(self.bones);
    }
};

pub fn duplicateClips(allocator: std.mem.Allocator, clips: []const Clip) ![]Clip {
    var out = try allocator.alloc(Clip, clips.len);
    errdefer {
        for (out[0..]) |*clip| clip.deinit(allocator);
        allocator.free(out);
    }
    for (clips, 0..) |clip, idx| out[idx] = try duplicateClip(allocator, clip);
    return out;
}

pub fn duplicateSkeletons(allocator: std.mem.Allocator, skeletons: []const Skeleton) ![]Skeleton {
    var out = try allocator.alloc(Skeleton, skeletons.len);
    errdefer {
        for (out[0..]) |*skeleton| skeleton.deinit(allocator);
        allocator.free(out);
    }
    for (skeletons, 0..) |skeleton, idx| {
        var bones = try allocator.alloc(Bone, skeleton.bones.len);
        errdefer allocator.free(bones);
        for (skeleton.bones, 0..) |bone, bone_idx| {
            bones[bone_idx] = .{
                .index = bone.index,
                .parent = bone.parent,
                .name = try allocator.dupe(u8, bone.name),
                .rest = bone.rest,
            };
        }
        out[idx] = .{
            .asset = try allocator.dupe(u8, skeleton.asset),
            .bones = bones,
        };
    }
    return out;
}

pub fn applyInterpolation(kind: Interpolation, t_raw: f32) f32 {
    const t = std.math.clamp(t_raw, 0.0, 1.0);
    return switch (kind) {
        .linear => t,
        .ease_in => t * t,
        .ease_out => t * (2.0 - t),
        .hold => 0.0,
    };
}

pub fn evaluateTrack(track: Track, time: f32) ?Transform {
    if (track.keyframes.len == 0) return null;
    if (time <= track.keyframes[0].time) return track.keyframes[0].transform;
    var i: usize = 1;
    while (i < track.keyframes.len) : (i += 1) {
        const prev = track.keyframes[i - 1];
        const next = track.keyframes[i];
        if (time <= next.time) {
            const span = @max(0.0001, next.time - prev.time);
            const t = applyInterpolation(prev.interpolation, (time - prev.time) / span);
            return lerpTransform(prev.transform, next.transform, t, prev.channels);
        }
    }
    return track.keyframes[track.keyframes.len - 1].transform;
}

pub fn lerpTransform(a: Transform, b: Transform, t_raw: f32, channels: KeyChannels) Transform {
    const t = std.math.clamp(t_raw, 0.0, 1.0);
    return .{
        .position = if (channels.position) lerpVec3(a.position, b.position, t) else a.position,
        .rotation = if (channels.rotation) lerpVec3(a.rotation, b.rotation, t) else a.rotation,
        .scale = if (channels.scale) lerpVec3(a.scale, b.scale, t) else a.scale,
    };
}

fn duplicateClip(allocator: std.mem.Allocator, clip: Clip) !Clip {
    var tracks = try allocator.alloc(Track, clip.tracks.len);
    errdefer allocator.free(tracks);
    for (clip.tracks, 0..) |track, idx| {
        tracks[idx] = .{
            .target = track.target,
            .keyframes = try allocator.dupe(Keyframe, track.keyframes),
        };
    }
    var poses = try allocator.alloc(NamedPose, clip.poses.len);
    errdefer allocator.free(poses);
    for (clip.poses, 0..) |pose, idx| {
        poses[idx] = .{
            .name = try allocator.dupe(u8, pose.name),
            .snapshots = try allocator.dupe(PoseSnapshot, pose.snapshots),
        };
    }
    return .{
        .id = clip.id,
        .name = try allocator.dupe(u8, clip.name),
        .duration = clip.duration,
        .looping = clip.looping,
        .tracks = tracks,
        .poses = poses,
    };
}

fn lerpVec3(a: editor_math.Vec3, b: editor_math.Vec3, t: f32) editor_math.Vec3 {
    return .{
        .x = a.x + (b.x - a.x) * t,
        .y = a.y + (b.y - a.y) * t,
        .z = a.z + (b.z - a.z) * t,
    };
}

test "animation track evaluates between keyframes" {
    const frames = [_]Keyframe{
        .{ .time = 0, .transform = .{ .position = .{ .x = 0, .y = 0, .z = 0 } } },
        .{ .time = 1, .transform = .{ .position = .{ .x = 2, .y = 0, .z = 0 } } },
    };
    const track = Track{ .target = .{ .object = 1 }, .keyframes = @constCast(&frames) };
    const value = evaluateTrack(track, 0.5).?;
    try std.testing.expectEqual(@as(f32, 1), value.position.x);
}

test "ease in interpolation is slower at start" {
    const frames = [_]Keyframe{
        .{ .time = 0, .transform = .{ .position = .{ .x = 0, .y = 0, .z = 0 } }, .interpolation = .ease_in },
        .{ .time = 1, .transform = .{ .position = .{ .x = 2, .y = 0, .z = 0 } } },
    };
    const track = Track{ .target = .{ .object = 1 }, .keyframes = @constCast(&frames) };
    const value = evaluateTrack(track, 0.5).?;
    try std.testing.expect(value.position.x < 1.0);
}

test "per-channel keyframes only lerp flagged channels" {
    const frames = [_]Keyframe{
        .{ .time = 0, .transform = .{ .position = .{ .x = 0, .y = 0, .z = 0 }, .scale = .{ .x = 1, .y = 1, .z = 1 } }, .channels = .{ .position = true, .rotation = false, .scale = false } },
        .{ .time = 1, .transform = .{ .position = .{ .x = 2, .y = 0, .z = 0 }, .scale = .{ .x = 4, .y = 4, .z = 4 } }, .channels = .{ .position = true, .rotation = false, .scale = false } },
    };
    const track = Track{ .target = .{ .object = 1 }, .keyframes = @constCast(&frames) };
    const value = evaluateTrack(track, 0.5).?;
    try std.testing.expectEqual(@as(f32, 1), value.position.x);
    try std.testing.expectEqual(@as(f32, 1), value.scale.x);
}
