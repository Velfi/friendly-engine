const std = @import("std");

pub const end_transmittance: f32 = 0.01;
pub const default_height_falloff_k: f32 = 0.012;
pub const slice_count: u32 = 4;

pub fn fogDensityFromSpan(start_m: f32, end_m: f32) !f32 {
    if (!std.math.isFinite(start_m) or !std.math.isFinite(end_m)) return error.InvalidAtmosphereValue;
    const span = end_m - start_m;
    if (span <= 0) return error.InvalidAtmosphereValue;
    return -@log(end_transmittance) / span;
}

pub fn heightFogScale(world_y: f32, height_falloff_k: f32) f32 {
    if (world_y <= 0) return 1.0;
    return @exp(-world_y * height_falloff_k);
}

pub fn volumetricFogFactor(
    start_m: f32,
    end_m: f32,
    camera_x: f32,
    camera_y: f32,
    camera_z: f32,
    world_x: f32,
    world_y: f32,
    world_z: f32,
    height_falloff_k: f32,
) !f32 {
    if (!std.math.isFinite(start_m) or !std.math.isFinite(end_m)) return error.InvalidAtmosphereValue;

    const dx = world_x - camera_x;
    const dy = world_y - camera_y;
    const dz = world_z - camera_z;
    const distance_m = @sqrt(dx * dx + dy * dy + dz * dz);
    if (!std.math.isFinite(distance_m)) return error.InvalidAtmosphereValue;
    if (distance_m <= start_m) return 0.0;

    const density = try fogDensityFromSpan(start_m, end_m);
    const inv_dist = 1.0 / distance_m;
    const dir_y = dy * inv_dist;

    const seg_len = (distance_m - start_m) / @as(f32, @floatFromInt(slice_count));
    var optical_depth: f32 = 0.0;
    var i: u32 = 0;
    while (i < slice_count) : (i += 1) {
        const t = start_m + seg_len * (@as(f32, @floatFromInt(i)) + 0.5);
        const sample_y = camera_y + dir_y * t;
        optical_depth += density * heightFogScale(sample_y, height_falloff_k) * seg_len;
    }

    return std.math.clamp(1.0 - @exp(-optical_depth), 0.0, 1.0);
}

test "fog density derives from start and end span" {
    const density = try fogDensityFromSpan(10, 30);
    try std.testing.expect(density > 0);
    const factor = try volumetricFogFactor(10, 30, 0, 0, 0, 0, 0, 30, default_height_falloff_k);
    try std.testing.expect(factor > 0.9);
}

test "volumetric fog is zero before start distance" {
    try std.testing.expectEqual(@as(f32, 0), try volumetricFogFactor(10, 30, 0, 0, 0, 0, 0, 5, default_height_falloff_k));
}

test "height reduces fog density aloft" {
    const horizontal = try volumetricFogFactor(10, 30, 0, 0, 0, 0, 0, 30, default_height_falloff_k);
    const vertical = try volumetricFogFactor(10, 30, 0, 0, 0, 0, 30, 0, default_height_falloff_k);
    try std.testing.expect(horizontal > vertical);
}

test "slice integration increases with distance" {
    const near = try volumetricFogFactor(8, 80, 0, 0, 0, 0, 0, 20, default_height_falloff_k);
    const far = try volumetricFogFactor(8, 80, 0, 0, 0, 0, 0, 60, default_height_falloff_k);
    try std.testing.expect(far > near);
}
