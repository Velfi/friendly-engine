const std = @import("std");
const world = @import("../../world/mod.zig");
const types = @import("types.zig");

pub const settings_blob_kind = "atmosphere.settings";

pub const BakedFogBank = struct {
    enabled: bool,
    color: [3]u8,
    start_m: f32,
    end_m: f32,
};

pub const CellSettings = struct {
    sky_tone: types.SkyTone,
    clouds: types.CloudTone = .{},
    fog_bank: BakedFogBank,
};

const JsonBlob = struct {
    cell: []const i32,
    sky_tone: types.SkyTone,
    clouds: ?types.CloudTone = null,
    fog_bank: struct {
        enabled: bool,
        color: []const u8,
        start_m: f32,
        end_m: f32,
    },
};

pub fn findSettingsBlob(blobs: []const world.cell.CellBlob) ?[]const u8 {
    for (blobs) |blob| {
        if (std.mem.eql(u8, blob.kind, settings_blob_kind)) return blob.payload;
    }
    return null;
}

pub fn requireSettingsBlob(blobs: []const world.cell.CellBlob) !CellSettings {
    const payload = findSettingsBlob(blobs) orelse return error.MissingAtmosphereSettingsBlob;
    return parseSettingsBlob(payload);
}

pub fn parseSettingsBlob(payload: []const u8) !CellSettings {
    var parsed = try std.json.parseFromSlice(JsonBlob, std.heap.page_allocator, payload, .{
        .allocate = .alloc_if_needed,
    });
    defer parsed.deinit();

    if (parsed.value.fog_bank.color.len != 3) return error.InvalidAtmosphereSettingsBlob;
    try types.validateSkyTone(parsed.value.sky_tone);
    const clouds = parsed.value.clouds orelse types.CloudTone{};
    try types.validateCloudTone(clouds);
    const fog = types.FogBank{
        .enabled = parsed.value.fog_bank.enabled,
        .color_r = parsed.value.fog_bank.color[0],
        .color_g = parsed.value.fog_bank.color[1],
        .color_b = parsed.value.fog_bank.color[2],
        .start_m = parsed.value.fog_bank.start_m,
        .end_m = parsed.value.fog_bank.end_m,
    };
    try types.validateFogBank(fog);

    return .{
        .sky_tone = parsed.value.sky_tone,
        .clouds = clouds,
        .fog_bank = .{
            .enabled = fog.enabled,
            .color = .{ fog.color_r, fog.color_g, fog.color_b },
            .start_m = fog.start_m,
            .end_m = fog.end_m,
        },
    };
}

const fog_math = @import("fog_math.zig");

pub const fogDensityFromSpan = fog_math.fogDensityFromSpan;
pub const volumetricFogFactor = fog_math.volumetricFogFactor;

test "parse atmosphere settings blob round trip" {
    const payload =
        \\{"cell":[0,0,0],"sky_tone":{"sun_enabled":true,"sun_azimuth_deg":120,"sun_elevation_deg":40,"moon_enabled":false,"moon_azimuth_deg":300,"moon_elevation_deg":25},"clouds":{"enabled":true,"coverage":0.5,"softness":0.7,"scale":0.9,"height_bias":0.6,"drift_dir_x":0.8,"drift_dir_y":0.2,"drift_speed":0.02,"seed":99,"parallax_enabled":true},"fog_bank":{"enabled":true,"color":[136,148,168],"start_m":8,"end_m":80}}
        \\
    ;
    const settings = try parseSettingsBlob(payload);
    try std.testing.expect(settings.sky_tone.sun_enabled);
    try std.testing.expectEqual(@as(f32, 0.5), settings.clouds.coverage);
    try std.testing.expectEqual(@as(u32, 99), settings.clouds.seed);
    try std.testing.expect(settings.fog_bank.enabled);
    try std.testing.expectEqual(@as(u8, 136), settings.fog_bank.color[0]);
    try std.testing.expectEqual(@as(f32, 80), settings.fog_bank.end_m);
}

test "parse atmosphere settings blob defaults missing cloud controls" {
    const payload =
        \\{"cell":[0,0,0],"sky_tone":{"sun_enabled":true,"sun_azimuth_deg":120,"sun_elevation_deg":40,"moon_enabled":false,"moon_azimuth_deg":300,"moon_elevation_deg":25},"fog_bank":{"enabled":false,"color":[136,148,168],"start_m":8,"end_m":80}}
        \\
    ;
    const settings = try parseSettingsBlob(payload);
    try std.testing.expect(settings.clouds.enabled);
    try std.testing.expectEqual(@as(f32, 0.42), settings.clouds.coverage);
}

test "require settings blob fails when missing" {
    const blobs = [_]world.cell.CellBlob{
        .{ .kind = "other.blob", .payload = "{}" },
    };
    try std.testing.expectError(error.MissingAtmosphereSettingsBlob, requireSettingsBlob(&blobs));
}

test "volumetric fog factor reaches near full opacity at end span" {
    const factor = try volumetricFogFactor(10, 30, 0, 0, 0, 0, 0, 30, fog_math.default_height_falloff_k);
    try std.testing.expect(factor > 0.95);
}
