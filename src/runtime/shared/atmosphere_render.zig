const std = @import("std");
const friendly_engine = @import("friendly_engine");
const editor_math = @import("editor_math.zig");
const shared_color = @import("color.zig");
const render_lighting = @import("render_lighting.zig");
const render_fog = @import("render_fog.zig");
const render_sky = @import("render_sky.zig");

const SkyTone = friendly_engine.modules.atmosphere.SkyTone;
const CloudTone = friendly_engine.modules.atmosphere.CloudTone;
const FogBank = friendly_engine.modules.atmosphere.FogBank;

pub const min_elevation_deg: f32 = -10.0;
pub const max_elevation_deg: f32 = 85.0;

const dark_ambient: f32 = 0.025;
const disk_min_visibility: f32 = 0.01;
const star_count: usize = 180;

const BodyLight = struct {
    sky_vector: editor_math.Vec3,
    direction: editor_math.Vec3,
    intensity: f32,
    color: shared_color.Color,
};

pub const SkyBody = struct {
    enabled: bool,
    direction: editor_math.Vec3,
    angular_radius_deg: f32,
    color: shared_color.Color,
    glow_color: shared_color.Color,
    visibility: f32,
};

pub fn skyColor(sky: SkyTone) shared_color.Color {
    const sun_factor = if (sky.sun_enabled) daylightFactor(sky.sun_elevation_deg) else 0.0;
    const moon_factor = if (sky.moon_enabled) daylightFactor(sky.moon_elevation_deg) else 0.0;
    const brightness = std.math.clamp(sun_factor * 0.88 + moon_factor * 0.22, 0.0, 1.0);
    return .{
        .r = lerpU8(6, 118, brightness),
        .g = lerpU8(7, 174, brightness),
        .b = lerpU8(11, 232, brightness),
        .a = 255,
    };
}

pub fn horizonColor(sky: SkyTone) shared_color.Color {
    const sun_factor = if (sky.sun_enabled) daylightFactor(sky.sun_elevation_deg) else 0.0;
    const moon_factor = if (sky.moon_enabled) daylightFactor(sky.moon_elevation_deg) else 0.0;
    const brightness = std.math.clamp(sun_factor * 0.78 + moon_factor * 0.16, 0.0, 1.0);
    const dusk = if (sky.sun_enabled) twilightFactor(sky.sun_elevation_deg) else 0.0;
    const daylight = shared_color.Color{
        .r = lerpU8(32, 178, brightness),
        .g = lerpU8(38, 210, brightness),
        .b = lerpU8(54, 248, brightness),
        .a = 255,
    };
    return mixColor(daylight, .{ .r = 246, .g = 138, .b = 78, .a = 255 }, dusk * 0.44);
}

pub fn zenithColor(sky: SkyTone) shared_color.Color {
    return skyColor(sky);
}

pub fn sunBody(sky: SkyTone) SkyBody {
    const visibility = if (sky.sun_enabled) daylightFactor(sky.sun_elevation_deg) else 0.0;
    return .{
        .enabled = sky.sun_enabled and visibility > disk_min_visibility,
        .direction = sunSkyVector(sky),
        .angular_radius_deg = 1.6,
        .color = .{ .r = 255, .g = 246, .b = 205, .a = 255 },
        .glow_color = .{ .r = 255, .g = 180, .b = 104, .a = 255 },
        .visibility = visibility,
    };
}

pub fn moonBody(sky: SkyTone) SkyBody {
    const visibility = if (sky.moon_enabled) daylightFactor(sky.moon_elevation_deg) else 0.0;
    return .{
        .enabled = sky.moon_enabled and visibility > disk_min_visibility,
        .direction = moonSkyVector(sky),
        .angular_radius_deg = 1.35,
        .color = .{ .r = 214, .g = 224, .b = 244, .a = 255 },
        .glow_color = .{ .r = 118, .g = 146, .b = 210, .a = 255 },
        .visibility = visibility,
    };
}

pub fn paintSky(
    pixels: []u8,
    width: u32,
    height: u32,
    camera: editor_math.OrbitCamera,
    sky: SkyTone,
) void {
    if (width == 0 or height == 0) return;
    const needed = @as(usize, width) * @as(usize, height) * 4;
    if (pixels.len < needed) return;

    paintSkyGradient(pixels, width, height, sky);
    paintStars(pixels, width, height, camera, sky);
    paintBody(pixels, width, height, camera, sunBody(sky));
    paintBody(pixels, width, height, camera, moonBody(sky));
}

pub fn ambientLevel(sky: SkyTone) f32 {
    const sun_factor = if (sky.sun_enabled) daylightFactor(sky.sun_elevation_deg) else 0.0;
    const moon_factor = if (sky.moon_enabled) daylightFactor(sky.moon_elevation_deg) else 0.0;
    const star_factor = starVisibility(sky);
    return std.math.clamp(dark_ambient + star_factor * 0.018 + sun_factor * 0.34 + moon_factor * 0.065, dark_ambient, 0.46);
}

pub fn frameFogFromBank(fog: FogBank) render_fog.FrameFog {
    return .{
        .enabled = fog.enabled,
        .color = .{
            .r = fog.color_r,
            .g = fog.color_g,
            .b = fog.color_b,
            .a = 255,
        },
        .start_m = fog.start_m,
        .end_m = fog.end_m,
    };
}

pub fn frameFogFromBaked(enabled: bool, color: [3]u8, start_m: f32, end_m: f32) render_fog.FrameFog {
    return .{
        .enabled = enabled,
        .color = .{ .r = color[0], .g = color[1], .b = color[2], .a = 255 },
        .start_m = start_m,
        .end_m = end_m,
    };
}

/// Builds the per-frame uniforms for the GPU sky pass (gradient + stars + sun/moon),
/// mirroring buildFrameLighting()'s role for the lighting uniforms. This is the GPU
/// counterpart to paintSky(): same SkyTone-derived colors/bodies, consumed by Sky.frag
/// instead of being rasterized into a CPU pixel buffer.
pub fn buildFrameSky(sky: SkyTone, clouds: CloudTone, camera: editor_math.OrbitCamera, time_s: f32) render_sky.FrameSky {
    return .{
        .enabled = true,
        .camera = camera,
        .time_s = time_s,
        .zenith_color = zenithColor(sky),
        .horizon_color = horizonColor(sky),
        .star_seed = if (sky.star_seed == 0) 0xa53c_9e17 else sky.star_seed,
        .star_visibility = starVisibility(sky),
        .clouds = clouds,
        .sun = sunBody(sky),
        .moon = moonBody(sky),
    };
}

pub fn buildFrameLighting(sky: SkyTone, fog: render_fog.FrameFog, camera: editor_math.OrbitCamera) render_lighting.FrameLighting {
    var lighting = render_lighting.FrameLighting{
        .shading_lit = true,
        .shadows_enabled = false,
        .ambient = ambientLevel(sky),
        .fog = fog,
        .camera_position = camera.eye(),
    };

    const sun = sunLight(sky);
    const moon = moonLight(sky);
    if (combineDirectional(sun, moon)) |body| {
        lighting.sun_direction = body.direction;
        lighting.sun_color = body.color;
        lighting.sun_intensity = body.intensity;
    } else {
        lighting.sun_intensity = 0.0;
    }
    return lighting;
}

pub fn sunSkyVector(sky: SkyTone) editor_math.Vec3 {
    return skyVector(sky.sun_azimuth_deg, sky.sun_elevation_deg);
}

pub fn moonSkyVector(sky: SkyTone) editor_math.Vec3 {
    return skyVector(sky.moon_azimuth_deg, sky.moon_elevation_deg);
}

pub fn clampElevation(value: f32) f32 {
    return std.math.clamp(value, min_elevation_deg, max_elevation_deg);
}

pub fn wrapAzimuth(value: f32) f32 {
    var wrapped = @mod(value, 360.0);
    if (wrapped < 0) wrapped += 360.0;
    return wrapped;
}

fn sunLight(sky: SkyTone) ?BodyLight {
    if (!sky.sun_enabled) return null;
    const factor = daylightFactor(sky.sun_elevation_deg);
    if (factor <= 0.0) return null;
    const vec = sunSkyVector(sky);
    return .{
        .sky_vector = vec,
        .direction = editor_math.Vec3.scale(vec, -1.0),
        .intensity = 0.18 + factor * 1.12,
        .color = .{ .r = 255, .g = lerpU8(214, 252, factor), .b = lerpU8(178, 238, factor), .a = 255 },
    };
}

fn moonLight(sky: SkyTone) ?BodyLight {
    if (!sky.moon_enabled) return null;
    const factor = daylightFactor(sky.moon_elevation_deg);
    if (factor <= 0.0) return null;
    const vec = moonSkyVector(sky);
    return .{
        .sky_vector = vec,
        .direction = editor_math.Vec3.scale(vec, -1.0),
        .intensity = 0.05 + factor * 0.22,
        .color = .{ .r = 174, .g = 198, .b = 255, .a = 255 },
    };
}

fn combineDirectional(sun: ?BodyLight, moon: ?BodyLight) ?BodyLight {
    if (sun == null and moon == null) return null;
    if (sun == null) return moon.?;
    if (moon == null) return sun.?;

    const s = sun.?;
    const m = moon.?;
    const total = s.intensity + m.intensity;
    const sky = editor_math.Vec3.normalized(editor_math.Vec3.add(
        editor_math.Vec3.scale(s.sky_vector, s.intensity / total),
        editor_math.Vec3.scale(m.sky_vector, m.intensity / total),
    ));
    return .{
        .sky_vector = sky,
        .direction = editor_math.Vec3.scale(sky, -1.0),
        .intensity = @min(1.15, total),
        .color = mixColor(s.color, m.color, m.intensity / total),
    };
}

fn skyVector(azimuth_deg: f32, elevation_deg: f32) editor_math.Vec3 {
    const az = std.math.degreesToRadians(azimuth_deg);
    const el = std.math.degreesToRadians(elevation_deg);
    const cos_el = @cos(el);
    return editor_math.Vec3.normalized(.{
        .x = @sin(az) * cos_el,
        .y = @sin(el),
        .z = @cos(az) * cos_el,
    });
}

fn daylightFactor(elevation_deg: f32) f32 {
    const normalized = (elevation_deg - min_elevation_deg) / (max_elevation_deg - min_elevation_deg);
    return std.math.clamp(normalized, 0.0, 1.0);
}

fn twilightFactor(elevation_deg: f32) f32 {
    const center = 2.0;
    const span = 20.0;
    return std.math.clamp(1.0 - @abs(elevation_deg - center) / span, 0.0, 1.0);
}

fn starVisibility(sky: SkyTone) f32 {
    const sun_dark = if (sky.sun_enabled)
        std.math.clamp((-sky.sun_elevation_deg) / 12.0, 0.0, 1.0)
    else
        1.0;
    const moon_wash = if (sky.moon_enabled) daylightFactor(sky.moon_elevation_deg) * 0.28 else 0.0;
    return std.math.clamp(sun_dark * (1.0 - moon_wash), 0.0, 1.0);
}

fn paintSkyGradient(pixels: []u8, width: u32, height: u32, sky: SkyTone) void {
    const top = zenithColor(sky);
    const horizon = horizonColor(sky);
    const h_f = @as(f32, @floatFromInt(@max(1, height - 1)));
    var y: u32 = 0;
    while (y < height) : (y += 1) {
        const t = @as(f32, @floatFromInt(y)) / h_f;
        const horizon_mix = std.math.clamp(std.math.pow(f32, t, 1.8), 0.0, 1.0);
        const color = mixColor(top, horizon, horizon_mix);
        var x: u32 = 0;
        while (x < width) : (x += 1) {
            const idx = (@as(usize, y) * @as(usize, width) + @as(usize, x)) * 4;
            pixels[idx] = color.r;
            pixels[idx + 1] = color.g;
            pixels[idx + 2] = color.b;
            pixels[idx + 3] = 255;
        }
    }
}

fn paintBody(pixels: []u8, width: u32, height: u32, camera: editor_math.OrbitCamera, body: SkyBody) void {
    if (!body.enabled) return;
    const projected = projectSkyDirection(camera, body.direction, width, height) orelse return;
    const radius_px = @max(4.0, body.angular_radius_deg / std.math.radiansToDegrees(camera.fov_y) * @as(f32, @floatFromInt(height)));
    const glow_radius = radius_px * 4.0;
    const min_x = @max(0, @as(i32, @intFromFloat(@floor(projected.x - glow_radius))));
    const max_x = @min(@as(i32, @intCast(width)) - 1, @as(i32, @intFromFloat(@ceil(projected.x + glow_radius))));
    const min_y = @max(0, @as(i32, @intFromFloat(@floor(projected.y - glow_radius))));
    const max_y = @min(@as(i32, @intCast(height)) - 1, @as(i32, @intFromFloat(@ceil(projected.y + glow_radius))));

    var y = min_y;
    while (y <= max_y) : (y += 1) {
        var x = min_x;
        while (x <= max_x) : (x += 1) {
            const dx = (@as(f32, @floatFromInt(x)) + 0.5) - projected.x;
            const dy = (@as(f32, @floatFromInt(y)) + 0.5) - projected.y;
            const dist = @sqrt(dx * dx + dy * dy);
            if (dist > glow_radius) continue;
            const idx = (@as(usize, @intCast(y)) * @as(usize, width) + @as(usize, @intCast(x))) * 4;
            const base = shared_color.Color{ .r = pixels[idx], .g = pixels[idx + 1], .b = pixels[idx + 2], .a = 255 };
            const glow_t = std.math.clamp(1.0 - dist / glow_radius, 0.0, 1.0);
            const disk_t = std.math.clamp(1.0 - (dist - radius_px * 0.78) / (radius_px * 0.22), 0.0, 1.0);
            const glow = mixColor(base, body.glow_color, glow_t * glow_t * body.visibility * 0.32);
            const final = mixColor(glow, body.color, disk_t * body.visibility);
            pixels[idx] = final.r;
            pixels[idx + 1] = final.g;
            pixels[idx + 2] = final.b;
            pixels[idx + 3] = 255;
        }
    }
}

fn paintStars(pixels: []u8, width: u32, height: u32, camera: editor_math.OrbitCamera, sky: SkyTone) void {
    const visibility = starVisibility(sky);
    if (visibility <= 0.001) return;

    var state = sky.star_seed;
    if (state == 0) state = 0xa53c_9e17;
    var index: usize = 0;
    while (index < star_count) : (index += 1) {
        const azimuth = rand01(&state) * std.math.tau;
        const elevation = std.math.degreesToRadians(8.0 + rand01(&state) * 78.0);
        const twinkle = 0.45 + rand01(&state) * 0.55;
        const warm = rand01(&state);
        const cos_el = @cos(elevation);
        const direction = editor_math.Vec3.normalized(.{
            .x = @sin(azimuth) * cos_el,
            .y = @sin(elevation),
            .z = @cos(azimuth) * cos_el,
        });
        const projected = projectSkyDirection(camera, direction, width, height) orelse continue;
        const size = if (twinkle > 0.92) @as(i32, 1) else @as(i32, 0);
        const intensity = visibility * twinkle;
        const color = mixColor(
            .{ .r = 182, .g = 198, .b = 255, .a = 255 },
            .{ .r = 255, .g = 236, .b = 196, .a = 255 },
            warm * 0.38,
        );
        paintStarPixel(pixels, width, height, projected.x, projected.y, size, color, intensity);
    }
}

fn paintStarPixel(
    pixels: []u8,
    width: u32,
    height: u32,
    center_x: f32,
    center_y: f32,
    radius: i32,
    color: shared_color.Color,
    intensity: f32,
) void {
    const cx = @as(i32, @intFromFloat(@round(center_x)));
    const cy = @as(i32, @intFromFloat(@round(center_y)));
    var y = cy - radius;
    while (y <= cy + radius) : (y += 1) {
        if (y < 0 or y >= @as(i32, @intCast(height))) continue;
        var x = cx - radius;
        while (x <= cx + radius) : (x += 1) {
            if (x < 0 or x >= @as(i32, @intCast(width))) continue;
            const dx = x - cx;
            const dy = y - cy;
            const dist2 = dx * dx + dy * dy;
            const falloff: f32 = if (radius == 0 or dist2 == 0) 1.0 else 0.38;
            const idx = (@as(usize, @intCast(y)) * @as(usize, width) + @as(usize, @intCast(x))) * 4;
            const base = shared_color.Color{ .r = pixels[idx], .g = pixels[idx + 1], .b = pixels[idx + 2], .a = 255 };
            const out = mixColor(base, color, std.math.clamp(intensity * falloff, 0.0, 1.0));
            pixels[idx] = out.r;
            pixels[idx + 1] = out.g;
            pixels[idx + 2] = out.b;
            pixels[idx + 3] = 255;
        }
    }
}

fn projectSkyDirection(
    camera: editor_math.OrbitCamera,
    direction: editor_math.Vec3,
    width: u32,
    height: u32,
) ?editor_math.Vec2 {
    const forward = camera.forward();
    const right = camera.right();
    const up = editor_math.Vec3.normalized(editor_math.cross(right, forward));
    const z = editor_math.Vec3.dot(direction, forward);
    if (z <= 0.001) return null;
    const aspect = @as(f32, @floatFromInt(width)) / @max(1.0, @as(f32, @floatFromInt(height)));
    const tan_half = @tan(camera.fov_y * 0.5);
    const ndc_x = editor_math.Vec3.dot(direction, right) / (z * tan_half * aspect);
    const ndc_y = editor_math.Vec3.dot(direction, up) / (z * tan_half);
    if (ndc_x < -1.35 or ndc_x > 1.35 or ndc_y < -1.35 or ndc_y > 1.35) return null;
    return .{
        .x = (ndc_x + 1.0) * 0.5 * @as(f32, @floatFromInt(width)),
        .y = (1.0 - ndc_y) * 0.5 * @as(f32, @floatFromInt(height)),
    };
}

fn rand01(state: *u32) f32 {
    state.* = state.* *% 1664525 +% 1013904223;
    const bits = (state.* >> 8) & 0x00ff_ffff;
    return @as(f32, @floatFromInt(bits)) / @as(f32, @floatFromInt(0x0100_0000));
}

fn lerpU8(a: u8, b: u8, t: f32) u8 {
    const af = @as(f32, @floatFromInt(a));
    const bf = @as(f32, @floatFromInt(b));
    return @intFromFloat(@round(std.math.clamp(af + (bf - af) * t, 0, 255)));
}

fn mixColor(a: shared_color.Color, b: shared_color.Color, t: f32) shared_color.Color {
    return .{
        .r = lerpU8(a.r, b.r, t),
        .g = lerpU8(a.g, b.g, t),
        .b = lerpU8(a.b, b.b, t),
        .a = 255,
    };
}

test "build frame lighting includes fog and camera" {
    var sky = SkyTone{};
    sky.sun_elevation_deg = 40;
    const fog = render_fog.FrameFog{ .enabled = true, .start_m = 8, .end_m = 64 };
    const camera = editor_math.OrbitCamera{};
    const lighting = buildFrameLighting(sky, fog, camera);
    try std.testing.expect(lighting.fog.enabled);
    try std.testing.expect(lighting.sun_intensity > 0.0);
}

test "paint sky draws a visible sun disk" {
    var pixels: [64 * 64 * 4]u8 = undefined;
    var sky = SkyTone{};
    sky.sun_azimuth_deg = 180;
    sky.sun_elevation_deg = 20;
    paintSky(&pixels, 64, 64, .{ .yaw = 0, .pitch = 0, .distance = 6 }, sky);
    var min_r: u8 = 255;
    var bright_pixels: usize = 0;
    var index: usize = 0;
    while (index + 3 < pixels.len) : (index += 4) {
        min_r = @min(min_r, pixels[index]);
        if (pixels[index] > 90 and pixels[index + 1] > 85 and pixels[index + 2] > 70) bright_pixels += 1;
    }
    try std.testing.expect(bright_pixels > 0);
    try std.testing.expect(min_r < 90);
}

test "paint sky draws deterministic stars when sun is down" {
    var pixels_a: [96 * 64 * 4]u8 = undefined;
    var pixels_b: [96 * 64 * 4]u8 = undefined;
    const sky = SkyTone{
        .sun_enabled = true,
        .sun_elevation_deg = -16,
        .moon_enabled = false,
        .star_seed = 17,
    };
    const camera = editor_math.OrbitCamera{ .yaw = 0, .pitch = 0.25, .distance = 6 };
    paintSky(&pixels_a, 96, 64, camera, sky);
    paintSky(&pixels_b, 96, 64, camera, sky);
    try std.testing.expectEqualSlices(u8, &pixels_a, &pixels_b);

    var bright_pixels: usize = 0;
    var index: usize = 0;
    while (index + 3 < pixels_a.len) : (index += 4) {
        if (pixels_a[index] > 120 and pixels_a[index + 1] > 130 and pixels_a[index + 2] > 170) bright_pixels += 1;
    }
    try std.testing.expect(bright_pixels > 0);
}
