const std = @import("std");

pub const schema_version: u32 = 1;

pub const WindSettings = struct {
    enabled: bool = true,
    direction_deg: f32 = 225.0,
    speed_mps: f32 = 8.0,
};

pub const WaveSettings = struct {
    enabled: bool = true,
    amplitude_m: f32 = 0.8,
    length_m: f32 = 42.0,
    speed_mps: f32 = 6.0,
};

pub const OceanDoc = struct {
    schema_version: u32 = schema_version,
    enabled: bool = true,
    sea_level_m: f32 = 0.0,
    render_min_distance_m: f32 = 1800.0,
    fade_in_start_m: f32 = 1400.0,
    fade_in_end_m: f32 = 2600.0,
    wind: WindSettings = .{},
    waves: WaveSettings = .{},
};

pub fn defaultDoc() OceanDoc {
    return .{};
}

pub fn validateWind(wind: WindSettings) !void {
    if (!std.math.isFinite(wind.direction_deg) or !std.math.isFinite(wind.speed_mps)) return error.InvalidOceanValue;
    if (wind.speed_mps < 0) return error.InvalidOceanValue;
}

pub fn validateWaves(waves: WaveSettings) !void {
    if (!std.math.isFinite(waves.amplitude_m) or !std.math.isFinite(waves.length_m) or !std.math.isFinite(waves.speed_mps)) return error.InvalidOceanValue;
    if (waves.amplitude_m < 0 or waves.length_m <= 0 or waves.speed_mps < 0) return error.InvalidOceanValue;
}

pub fn validateDoc(doc: OceanDoc) !void {
    if (doc.schema_version != schema_version) return error.UnsupportedOceanSchemaVersion;
    if (!std.math.isFinite(doc.sea_level_m) or !std.math.isFinite(doc.render_min_distance_m) or
        !std.math.isFinite(doc.fade_in_start_m) or !std.math.isFinite(doc.fade_in_end_m))
    {
        return error.InvalidOceanValue;
    }
    if (doc.render_min_distance_m < 0 or doc.fade_in_start_m < 0 or doc.fade_in_end_m < doc.fade_in_start_m) return error.InvalidOceanValue;
    try validateWind(doc.wind);
    try validateWaves(doc.waves);
}

test "validate default ocean doc" {
    try validateDoc(defaultDoc());
}
