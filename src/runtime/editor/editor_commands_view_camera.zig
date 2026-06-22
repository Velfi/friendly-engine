const std = @import("std");
const shared = @import("runtime_shared");
const editor_command_file = @import("editor_command_file.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_types = @import("project_editor_types.zig");
const project_editor_view_nav = @import("project_editor_view_nav.zig");

const editor_math = shared.editor_math;
const CommandFile = editor_command_file.CommandFile;
const ProjectEditorState = project_editor_state.ProjectEditorState;
const SceneObject = project_editor_state.SceneObject;

pub fn applyViewCommand(state: *ProjectEditorState, command: CommandFile) !void {
    var changed = false;
    if (command.view) |view| {
        state.view_camera_mode = try parseViewCameraMode(view);
        changed = true;
    }
    if (command.orientation) |orientation| {
        project_editor_view_nav.applyAxisSnap(state, try parseViewOrientation(orientation));
        changed = true;
    }
    if (!changed) return error.MissingViewChange;
    project_editor_state.setStatus(state, "View updated");
}

pub fn applyCameraCommand(state: *ProjectEditorState, command: CommandFile) !void {
    var changed = false;
    if (command.target_x) |value| {
        state.camera.target.x = value;
        changed = true;
    }
    if (command.target_y) |value| {
        state.camera.target.y = value;
        changed = true;
    }
    if (command.target_z) |value| {
        state.camera.target.z = value;
        changed = true;
    }
    if (command.yaw) |value| {
        state.camera.yaw = value;
        state.view_orientation = .free;
        changed = true;
    }
    if (command.pitch) |value| {
        state.camera.pitch = std.math.clamp(value, -1.4, 1.4);
        state.view_orientation = .free;
        changed = true;
    }
    if (command.distance) |value| {
        if (value < state.camera.min_distance or value > state.camera.max_distance) return error.InvalidCameraDistance;
        state.camera.distance = value;
        changed = true;
    }
    if (!changed) return error.MissingCameraChange;
    project_editor_state.setStatus(state, "Camera updated");
}

pub fn applyShowMeCommand(state: *ProjectEditorState, command: CommandFile) !void {
    const enabled = command.enabled orelse return error.MissingShowMeMode;
    state.show_me_mode_enabled = enabled;
    if (!enabled) {
        project_editor_state.setStatus(state, "Show me mode off");
        return;
    }

    const radius = command.radius orelse state.show_me_focus_radius;
    if (radius <= 0) return error.InvalidShowMeRadius;
    state.show_me_focus_radius = radius;
    if (showMeCommandPoint(command)) |center| {
        frameShowMeArea(state, center, radius, command.distance, true);
        project_editor_state.setStatus(state, "Show me mode on: framing work area");
        return;
    }
    project_editor_state.setStatus(state, "Show me mode on");
}

pub fn applyShowMeHint(state: *ProjectEditorState, command: CommandFile) void {
    if (!state.show_me_mode_enabled) return;
    if (std.mem.eql(u8, command.name, "show-me") or
        std.mem.eql(u8, command.name, "camera.set") or
        std.mem.eql(u8, command.name, "camera.preset") or
        std.mem.eql(u8, command.name, "camera.random-angle") or
        std.mem.eql(u8, command.name, "focus-in-viewport") or
        std.mem.eql(u8, command.name, "zoom-to-focus"))
    {
        return;
    }
    const center = showMeCommandPoint(command) orelse return;
    const radius = command.radius orelse inferredShowMeRadius(state, command);
    frameShowMeArea(state, center, radius, null, false);
}

fn showMeCommandPoint(command: CommandFile) ?editor_math.Vec3 {
    const x = command.point_x orelse return null;
    const z = command.point_z orelse return null;
    var center = editor_math.Vec3{ .x = x, .y = command.point_y orelse 0, .z = z };
    if (command.end_x) |end_x| {
        const end_z = command.end_z orelse z;
        center.x = (x + end_x) * 0.5;
        center.z = (z + end_z) * 0.5;
        center.y = (center.y + (command.end_y orelse center.y)) * 0.5;
    }
    return center;
}

fn inferredShowMeRadius(state: *const ProjectEditorState, command: CommandFile) f32 {
    var radius = state.show_me_focus_radius;
    if (command.width) |value| radius = @max(radius, value * 0.5);
    if (command.depth) |value| radius = @max(radius, value * 0.5);
    if (command.height) |value| radius = @max(radius, value * 0.5);
    if (command.end_x) |end_x| {
        const x = command.point_x orelse end_x;
        const z = command.point_z orelse command.end_z orelse 0;
        const end_z = command.end_z orelse z;
        const dx = end_x - x;
        const dz = end_z - z;
        radius = @max(radius, @sqrt(dx * dx + dz * dz) * 0.5);
    }
    if (std.mem.startsWith(u8, command.name, "terrain.")) radius = @max(radius, state.world_brush_size);
    return std.math.clamp(radius, 1.0, 240.0);
}

fn frameShowMeArea(
    state: *ProjectEditorState,
    center: editor_math.Vec3,
    radius: f32,
    distance_override: ?f32,
    force: bool,
) void {
    const focus_radius = @max(radius, state.show_me_focus_radius);
    if (!force and vec3Length(editor_math.Vec3.sub(center, state.camera.target)) <= focus_radius) return;
    state.show_me_focus_radius = focus_radius;
    state.view_camera_mode = .perspective;
    state.view_orientation = .free;
    state.camera.target = center;
    const requested_distance = distance_override orelse @max(state.camera.distance, focus_radius * 2.75);
    state.camera.distance = std.math.clamp(requested_distance, state.camera.min_distance, state.camera.max_distance);
}

pub fn applyCameraPreset(state: *ProjectEditorState, preset: []const u8) !void {
    if (std.mem.eql(u8, preset, "review")) {
        state.view_camera_mode = .perspective;
        state.view_orientation = .free;
        state.show_grid = false;
        state.show_viewport_toolbar = false;
        state.world_sun_enabled = true;
        state.world_sun_azimuth_deg = 135.0;
        state.world_sun_elevation_deg = 45.0;
        state.world_fog_enabled = true;
        state.world_fog_start_m = 80.0;
        state.world_fog_end_m = 220.0;
        state.world_fog_color_r = 0x88;
        state.world_fog_color_g = 0x91;
        state.world_fog_color_b = 0x9a;
        state.camera.target = .{ .x = 0.0, .y = 5.6, .z = 1.8 };
        state.camera.yaw = 2.42;
        state.camera.pitch = 0.30;
        state.camera.distance = 57.0;
        project_editor_state.setStatus(state, "Review camera preset");
        return;
    }
    return error.InvalidCameraPreset;
}

pub fn applyRandomCameraAngle(state: *ProjectEditorState, seed: ?u64) !void {
    const bounds = sceneReviewBounds(state.objects.items) orelse return error.NoVisibleSceneBounds;
    const actual_seed = seed orelse defaultRandomCameraSeed(state, bounds);
    var prng = std.Random.DefaultPrng.init(actual_seed);
    const random = prng.random();

    const center = editor_math.Vec3{
        .x = (bounds.min.x + bounds.max.x) * 0.5,
        .y = (bounds.min.y + bounds.max.y) * 0.5,
        .z = (bounds.min.z + bounds.max.z) * 0.5,
    };
    const span = editor_math.Vec3{
        .x = @max(bounds.max.x - bounds.min.x, 1.0),
        .y = @max(bounds.max.y - bounds.min.y, 1.0),
        .z = @max(bounds.max.z - bounds.min.z, 1.0),
    };
    const horizontal_radius = @sqrt(span.x * span.x + span.z * span.z) * 0.5;
    const jitter_radius = @min(horizontal_radius * 0.22, 7.0);
    const jitter_angle = random.float(f32) * std.math.tau;
    const jitter_distance = random.float(f32) * jitter_radius;

    state.camera.target = .{
        .x = center.x + @cos(jitter_angle) * jitter_distance,
        .y = @max(0.8, bounds.min.y + @min(span.y * 0.25, 1.8) + random.float(f32) * 0.7),
        .z = center.z + @sin(jitter_angle) * jitter_distance,
    };
    state.camera.yaw = random.float(f32) * std.math.tau - std.math.pi;
    state.camera.pitch = 0.28 + random.float(f32) * 0.34;
    state.camera.distance = std.math.clamp(horizontal_radius * (0.65 + random.float(f32) * 0.95), 5.0, state.camera.max_distance);
    state.view_orientation = .free;
    project_editor_state.setStatus(state, "Camera randomized for review");
}

const SceneBounds = struct {
    min: editor_math.Vec3,
    max: editor_math.Vec3,
};

fn sceneReviewBounds(objects: []const SceneObject) ?SceneBounds {
    var bounds: ?SceneBounds = null;
    for (objects) |*obj| {
        if (!obj.enabled or !obj.renderer_visible or obj.editor_only) continue;
        const half = editor_math.Vec3{
            .x = @max(@abs(obj.scale.x), 0.1),
            .y = @max(@abs(obj.scale.y), 0.1),
            .z = @max(@abs(obj.scale.z), 0.1),
        };
        includeBoundsPoint(&bounds, .{ .x = obj.position.x - half.x, .y = obj.position.y - half.y, .z = obj.position.z - half.z });
        includeBoundsPoint(&bounds, .{ .x = obj.position.x + half.x, .y = obj.position.y + half.y, .z = obj.position.z + half.z });
    }
    return bounds;
}

fn includeBoundsPoint(bounds: *?SceneBounds, point: editor_math.Vec3) void {
    if (bounds.*) |*existing| {
        existing.min.x = @min(existing.min.x, point.x);
        existing.min.y = @min(existing.min.y, point.y);
        existing.min.z = @min(existing.min.z, point.z);
        existing.max.x = @max(existing.max.x, point.x);
        existing.max.y = @max(existing.max.y, point.y);
        existing.max.z = @max(existing.max.z, point.z);
    } else {
        bounds.* = .{ .min = point, .max = point };
    }
}

fn defaultRandomCameraSeed(state: *const ProjectEditorState, bounds: SceneBounds) u64 {
    var value: u64 = 0x9e3779b97f4a7c15;
    value = mixSeed(value, @as(u64, @intCast(state.objects.items.len)));
    value = mixSeed(value, floatSeedBits(state.camera.target.x));
    value = mixSeed(value, floatSeedBits(state.camera.target.y));
    value = mixSeed(value, floatSeedBits(state.camera.target.z));
    value = mixSeed(value, floatSeedBits(state.camera.yaw));
    value = mixSeed(value, floatSeedBits(state.camera.pitch));
    value = mixSeed(value, floatSeedBits(state.camera.distance));
    value = mixSeed(value, floatSeedBits(bounds.min.x));
    value = mixSeed(value, floatSeedBits(bounds.min.z));
    value = mixSeed(value, floatSeedBits(bounds.max.x));
    value = mixSeed(value, floatSeedBits(bounds.max.z));
    return value;
}

fn floatSeedBits(value: f32) u64 {
    const bits: u32 = @bitCast(value);
    return bits;
}

fn mixSeed(current: u64, next: u64) u64 {
    var out = current ^ (next +% 0x9e3779b97f4a7c15 +% (current << 6) +% (current >> 2));
    out ^= out >> 30;
    out *%= 0xbf58476d1ce4e5b9;
    out ^= out >> 27;
    out *%= 0x94d049bb133111eb;
    out ^= out >> 31;
    return out;
}

fn parseViewCameraMode(value: []const u8) !project_editor_types.ViewCameraMode {
    inline for (std.meta.fields(project_editor_types.ViewCameraMode)) |field| {
        if (std.mem.eql(u8, value, field.name)) return @enumFromInt(field.value);
    }
    return error.InvalidViewCameraMode;
}

fn parseViewOrientation(value: []const u8) !project_editor_types.ViewOrientation {
    inline for (std.meta.fields(project_editor_types.ViewOrientation)) |field| {
        if (std.mem.eql(u8, value, field.name)) return @enumFromInt(field.value);
    }
    return error.InvalidViewOrientation;
}

fn vec3Length(vec: editor_math.Vec3) f32 {
    return @sqrt(vec.x * vec.x + vec.y * vec.y + vec.z * vec.z);
}
