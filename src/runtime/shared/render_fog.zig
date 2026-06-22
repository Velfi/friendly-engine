const std = @import("std");
const friendly_engine = @import("friendly_engine");
const editor_math = @import("editor_math.zig");
const shared_color = @import("color.zig");

const fog_math = friendly_engine.modules.atmosphere.fog_math;

pub const end_transmittance = fog_math.end_transmittance;
pub const default_height_falloff_k = fog_math.default_height_falloff_k;
pub const slice_count = fog_math.slice_count;

pub const FrameFog = struct {
    enabled: bool = false,
    color: shared_color.Color = .{ .r = 0x88, .g = 0x94, .b = 0xa8, .a = 255 },
    start_m: f32 = 8.0,
    end_m: f32 = 80.0,
    height_falloff_k: f32 = default_height_falloff_k,
};

pub fn fogDensityFromSpan(start_m: f32, end_m: f32) !f32 {
    return fog_math.fogDensityFromSpan(start_m, end_m);
}

pub fn heightFogScale(world_y: f32, height_falloff_k: f32) f32 {
    return fog_math.heightFogScale(world_y, height_falloff_k);
}

pub fn fogFactor(fog: FrameFog, camera_position: editor_math.Vec3, world_position: editor_math.Vec3) !f32 {
    if (!fog.enabled) return 0.0;
    return fog_math.volumetricFogFactor(
        fog.start_m,
        fog.end_m,
        camera_position.x,
        camera_position.y,
        camera_position.z,
        world_position.x,
        world_position.y,
        world_position.z,
        fog.height_falloff_k,
    );
}

pub fn distanceFromCamera(camera_position: editor_math.Vec3, world_position: editor_math.Vec3) f32 {
    return editor_math.Vec3.length(editor_math.Vec3.sub(world_position, camera_position));
}

pub fn applyFog(color: shared_color.Color, fog: FrameFog, factor: f32) shared_color.Color {
    const t = std.math.clamp(factor, 0.0, 1.0);
    return .{
        .r = lerpU8(color.r, fog.color.r, t),
        .g = lerpU8(color.g, fog.color.g, t),
        .b = lerpU8(color.b, fog.color.b, t),
        .a = color.a,
    };
}

pub fn shadeWithFog(
    color: shared_color.Color,
    fog: FrameFog,
    camera_position: editor_math.Vec3,
    world_position: editor_math.Vec3,
) shared_color.Color {
    const factor = fogFactor(fog, camera_position, world_position) catch return color;
    return applyFog(color, fog, factor);
}

fn lerpU8(a: u8, b: u8, t: f32) u8 {
    const af = @as(f32, @floatFromInt(a));
    const bf = @as(f32, @floatFromInt(b));
    return @intFromFloat(@round(std.math.clamp(af + (bf - af) * t, 0, 255)));
}

test "volumetric fog ramps with distance and height" {
    const fog = FrameFog{ .enabled = true, .start_m = 10, .end_m = 30 };
    const camera: editor_math.Vec3 = .{ .x = 0, .y = 0, .z = 0 };
    try std.testing.expectEqual(@as(f32, 0), try fogFactor(fog, camera, .{ .x = 0, .y = 0, .z = 5 }));
    const ground = try fogFactor(fog, camera, .{ .x = 0, .y = 0, .z = 20 });
    const aloft = try fogFactor(fog, camera, .{ .x = 0, .y = 20, .z = 0 });
    try std.testing.expect(ground > 0.5);
    try std.testing.expect(ground > aloft);
}

test "disabled fog leaves factor at zero" {
    const fog = FrameFog{ .enabled = false, .start_m = 0, .end_m = 10 };
    try std.testing.expectEqual(@as(f32, 0), try fogFactor(fog, .{ .x = 0, .y = 0, .z = 0 }, .{ .x = 0, .y = 0, .z = 50 }));
}

test "apply fog lerps toward fog color" {
    const fog = FrameFog{
        .enabled = true,
        .color = .{ .r = 100, .g = 100, .b = 100, .a = 255 },
        .start_m = 0,
        .end_m = 10,
    };
    const base = shared_color.Color{ .r = 200, .g = 0, .b = 0, .a = 255 };
    const dense = applyFog(base, fog, 0.5);
    try std.testing.expect(dense.r < base.r and dense.r > fog.color.r);
}

test "fog density matches span helper" {
    try std.testing.expectEqual(
        try fogDensityFromSpan(8, 80),
        try fog_math.fogDensityFromSpan(8, 80),
    );
}
