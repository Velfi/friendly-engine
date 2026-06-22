const std = @import("std");
const friendly_engine = @import("friendly_engine");
const editor_math = @import("editor_math.zig");
const shared_color = @import("color.zig");
const atmosphere_render = @import("atmosphere_render.zig");

/// Per-frame data needed by the GPU sky pass, mirroring render_lighting.FrameLighting's
/// role: the editor/client builds this once per frame from a SkyTone + camera and hands
/// it to the GPU backend via GpuRenderer.setFrameSky().
pub const FrameSky = struct {
    enabled: bool = true,
    camera: editor_math.OrbitCamera = .{},
    time_s: f32 = 0,
    zenith_color: shared_color.Color = .{ .r = 6, .g = 7, .b = 11, .a = 255 },
    horizon_color: shared_color.Color = .{ .r = 12, .g = 14, .b = 20, .a = 255 },
    star_seed: u32 = 0,
    star_visibility: f32 = 0,
    clouds: friendly_engine.modules.atmosphere.CloudTone = .{},
    sun: atmosphere_render.SkyBody = .{
        .enabled = false,
        .direction = .{ .x = 0, .y = 1, .z = 0 },
        .angular_radius_deg = 1.6,
        .color = .{ .r = 255, .g = 246, .b = 205, .a = 255 },
        .glow_color = .{ .r = 255, .g = 180, .b = 104, .a = 255 },
        .visibility = 0,
    },
    moon: atmosphere_render.SkyBody = .{
        .enabled = false,
        .direction = .{ .x = 0, .y = 1, .z = 0 },
        .angular_radius_deg = 1.35,
        .color = .{ .r = 214, .g = 224, .b = 244, .a = 255 },
        .glow_color = .{ .r = 118, .g = 146, .b = 210, .a = 255 },
        .visibility = 0,
    },
};

pub const GpuSkyUniforms = extern struct {
    camera_right: [4]f32,
    camera_up: [4]f32,
    camera_forward: [4]f32,
    /// x = tan(fov_y * 0.5), y = aspect, z = star_seed as f32, w = star_visibility
    params0: [4]f32,
    zenith_color: [4]f32,
    horizon_color: [4]f32,
    sun_direction: [4]f32,
    sun_color: [4]f32,
    sun_glow_color: [4]f32,
    /// x = angular_radius_deg, y = visibility, z = enabled (0/1), w unused
    sun_params: [4]f32,
    moon_direction: [4]f32,
    moon_color: [4]f32,
    moon_glow_color: [4]f32,
    /// x = angular_radius_deg, y = visibility, z = enabled (0/1), w unused
    moon_params: [4]f32,
    /// x = enabled (0/1), y = coverage, z = softness, w = scale
    cloud_params0: [4]f32,
    /// x = height_bias, y = drift_dir_x, z = drift_dir_y, w = drift_speed
    cloud_params1: [4]f32,
    /// x = seed as f32, y = parallax_enabled (0/1), z = time_s, w unused
    cloud_params2: [4]f32,
};

/// Builds the GPU sky pass uniforms from a FrameSky and the current viewport aspect ratio.
/// The camera right/up/forward vectors and fov are packed so the fragment shader can
/// reconstruct a per-pixel view ray identically to atmosphere_render.projectSkyDirection(),
/// just inverted (screen UV -> direction instead of direction -> screen UV).
pub fn packGpuSkyUniforms(sky: FrameSky, aspect: f32) GpuSkyUniforms {
    const camera = sky.camera;
    const forward = camera.forward();
    const right = camera.right();
    const up = editor_math.Vec3.normalized(editor_math.cross(right, forward));
    const tan_half = @tan(camera.fov_y * 0.5);

    return .{
        .camera_right = vec4(right, 0),
        .camera_up = vec4(up, 0),
        .camera_forward = vec4(forward, 0),
        .params0 = .{ tan_half, aspect, @as(f32, @floatFromInt(sky.star_seed)), sky.star_visibility },
        .zenith_color = colorToFloat4(sky.zenith_color),
        .horizon_color = colorToFloat4(sky.horizon_color),
        .sun_direction = vec4(sky.sun.direction, 0),
        .sun_color = colorToFloat4(sky.sun.color),
        .sun_glow_color = colorToFloat4(sky.sun.glow_color),
        .sun_params = .{ sky.sun.angular_radius_deg, sky.sun.visibility, if (sky.sun.enabled) 1.0 else 0.0, 0 },
        .moon_direction = vec4(sky.moon.direction, 0),
        .moon_color = colorToFloat4(sky.moon.color),
        .moon_glow_color = colorToFloat4(sky.moon.glow_color),
        .moon_params = .{ sky.moon.angular_radius_deg, sky.moon.visibility, if (sky.moon.enabled) 1.0 else 0.0, 0 },
        .cloud_params0 = .{ if (sky.clouds.enabled) 1.0 else 0.0, sky.clouds.coverage, sky.clouds.softness, sky.clouds.scale },
        .cloud_params1 = .{ sky.clouds.height_bias, sky.clouds.drift_dir_x, sky.clouds.drift_dir_y, sky.clouds.drift_speed },
        .cloud_params2 = .{ @as(f32, @floatFromInt(if (sky.clouds.seed == 0) 0xa53c_9e17 else sky.clouds.seed)), if (sky.clouds.parallax_enabled) 1.0 else 0.0, sky.time_s, 0 },
    };
}

fn vec4(v: editor_math.Vec3, w: f32) [4]f32 {
    return .{ v.x, v.y, v.z, w };
}

fn colorToFloat4(color: shared_color.Color) [4]f32 {
    return .{
        @as(f32, @floatFromInt(color.r)) / 255.0,
        @as(f32, @floatFromInt(color.g)) / 255.0,
        @as(f32, @floatFromInt(color.b)) / 255.0,
        @as(f32, @floatFromInt(color.a)) / 255.0,
    };
}

test "pack gpu sky uniforms produces finite values" {
    const sky = FrameSky{
        .camera = .{ .yaw = 0.3, .pitch = 0.2, .distance = 6 },
        .star_seed = 42,
        .star_visibility = 0.5,
    };
    const uniforms = packGpuSkyUniforms(sky, 16.0 / 9.0);
    inline for (.{
        uniforms.camera_right,
        uniforms.camera_up,
        uniforms.camera_forward,
        uniforms.params0,
        uniforms.zenith_color,
        uniforms.horizon_color,
        uniforms.cloud_params0,
        uniforms.cloud_params1,
        uniforms.cloud_params2,
    }) |group| {
        for (group) |value| try std.testing.expect(std.math.isFinite(value));
    }
}
