const std = @import("std");
const world = @import("../../world/mod.zig");

pub const schema_version: u32 = 1;

pub const SkyTone = struct {
    sun_enabled: bool = true,
    sun_azimuth_deg: f32 = 135.0,
    sun_elevation_deg: f32 = 48.0,
    moon_enabled: bool = false,
    moon_azimuth_deg: f32 = 315.0,
    moon_elevation_deg: f32 = 35.0,
    star_seed: u32 = 2745,
};

pub const FogBank = struct {
    enabled: bool = false,
    color_r: u8 = 0x88,
    color_g: u8 = 0x94,
    color_b: u8 = 0xa8,
    start_m: f32 = 8.0,
    end_m: f32 = 80.0,
};

pub const CloudTone = struct {
    enabled: bool = true,
    coverage: f32 = 0.42,
    softness: f32 = 0.68,
    scale: f32 = 0.85,
    height_bias: f32 = 0.55,
    drift_dir_x: f32 = 1.0,
    drift_dir_y: f32 = 0.18,
    drift_speed: f32 = 0.015,
    seed: u32 = 2745,
    parallax_enabled: bool = true,
};

pub const CellFogBank = struct {
    cell: [3]i32,
    fog: FogBank,
};

pub const AtmosphereDoc = struct {
    schema_version: u32 = schema_version,
    sky_tone: SkyTone = .{},
    clouds: CloudTone = .{},
    fog_bank: FogBank = .{},
    cell_fog_banks: []const CellFogBank = &.{},
};

pub fn defaultDoc() AtmosphereDoc {
    return .{};
}

pub fn cellIdFromCoord(coord: [3]i32) world.cell.CellId {
    return .{ .x = coord[0], .y = coord[1], .z = coord[2] };
}

pub fn parseCellCoord(text: []const u8) ![3]i32 {
    var parts: [3]i32 = .{ 0, 0, 0 };
    var count: usize = 0;
    var start: usize = 0;
    var index: usize = 0;
    while (index <= text.len) : (index += 1) {
        const at_end = index == text.len;
        const ch = if (at_end) ',' else text[index];
        if (ch == ',') {
            if (count >= 3) return error.InvalidAtmosphereCellCoord;
            const slice = std.mem.trim(u8, text[start..index], " \t");
            if (slice.len == 0) return error.InvalidAtmosphereCellCoord;
            parts[count] = try std.fmt.parseInt(i32, slice, 10);
            count += 1;
            start = index + 1;
        }
    }
    if (count < 2 or count > 3) return error.InvalidAtmosphereCellCoord;
    return parts;
}

pub fn resolveFogForCell(doc: AtmosphereDoc, id: world.cell.CellId) FogBank {
    for (doc.cell_fog_banks) |entry| {
        if (cellIdFromCoord(entry.cell).eql(id)) return entry.fog;
    }
    return doc.fog_bank;
}

pub fn hasCellFogOverride(doc: AtmosphereDoc, id: world.cell.CellId) bool {
    for (doc.cell_fog_banks) |entry| {
        if (cellIdFromCoord(entry.cell).eql(id)) return true;
    }
    return false;
}

pub fn validateSkyTone(sky: SkyTone) !void {
    if (!std.math.isFinite(sky.sun_azimuth_deg) or !std.math.isFinite(sky.sun_elevation_deg)) return error.InvalidAtmosphereValue;
    if (!std.math.isFinite(sky.moon_azimuth_deg) or !std.math.isFinite(sky.moon_elevation_deg)) return error.InvalidAtmosphereValue;
    if (sky.sun_elevation_deg < -90 or sky.sun_elevation_deg > 90) return error.InvalidAtmosphereValue;
    if (sky.moon_elevation_deg < -90 or sky.moon_elevation_deg > 90) return error.InvalidAtmosphereValue;
}

pub fn validateFogBank(fog: FogBank) !void {
    if (!std.math.isFinite(fog.start_m) or !std.math.isFinite(fog.end_m)) return error.InvalidAtmosphereValue;
    if (fog.start_m < 0 or fog.end_m <= fog.start_m) return error.InvalidAtmosphereValue;
}

pub fn validateCloudTone(clouds: CloudTone) !void {
    inline for (.{
        clouds.coverage,
        clouds.softness,
        clouds.scale,
        clouds.height_bias,
        clouds.drift_dir_x,
        clouds.drift_dir_y,
        clouds.drift_speed,
    }) |value| {
        if (!std.math.isFinite(value)) return error.InvalidAtmosphereValue;
    }
    if (clouds.coverage < 0 or clouds.coverage > 1) return error.InvalidAtmosphereValue;
    if (clouds.softness < 0.01 or clouds.softness > 1) return error.InvalidAtmosphereValue;
    if (clouds.scale <= 0 or clouds.scale > 8) return error.InvalidAtmosphereValue;
    if (clouds.height_bias < 0 or clouds.height_bias > 1) return error.InvalidAtmosphereValue;
    if (clouds.drift_speed < 0 or clouds.drift_speed > 8) return error.InvalidAtmosphereValue;
}

pub fn validateCellFogBank(entry: CellFogBank) !void {
    try validateFogBank(entry.fog);
}

pub fn validateDoc(doc: AtmosphereDoc) !void {
    if (doc.schema_version != schema_version) return error.UnsupportedAtmosphereSchemaVersion;
    try validateSkyTone(doc.sky_tone);
    try validateCloudTone(doc.clouds);
    try validateFogBank(doc.fog_bank);
    for (doc.cell_fog_banks) |entry| try validateCellFogBank(entry);
    var index: usize = 0;
    while (index < doc.cell_fog_banks.len) : (index += 1) {
        const left = cellIdFromCoord(doc.cell_fog_banks[index].cell);
        var probe = index + 1;
        while (probe < doc.cell_fog_banks.len) : (probe += 1) {
            if (left.eql(cellIdFromCoord(doc.cell_fog_banks[probe].cell))) return error.DuplicateAtmosphereCellFogBank;
        }
    }
}

pub fn parseHexColor(text: []const u8) ![3]u8 {
    var trimmed = std.mem.trim(u8, text, " \t\r\n");
    if (trimmed.len > 0 and trimmed[0] == '#') trimmed = trimmed[1..];
    if (trimmed.len != 6) return error.InvalidAtmosphereValue;
    return .{
        try std.fmt.parseInt(u8, trimmed[0..2], 16),
        try std.fmt.parseInt(u8, trimmed[2..4], 16),
        try std.fmt.parseInt(u8, trimmed[4..6], 16),
    };
}

test "parse cell coord accepts two or three components" {
    const two = try parseCellCoord("1,2");
    try std.testing.expectEqual(@as(i32, 1), two[0]);
    try std.testing.expectEqual(@as(i32, 2), two[1]);
    try std.testing.expectEqual(@as(i32, 0), two[2]);

    const three = try parseCellCoord("0,0,1");
    try std.testing.expectEqual(@as(i32, 1), three[2]);
}

test "resolve fog prefers cell override" {
    const doc = AtmosphereDoc{
        .fog_bank = .{ .enabled = false, .start_m = 8, .end_m = 80 },
        .cell_fog_banks = &.{
            .{ .cell = .{ 1, 0, 0 }, .fog = .{ .enabled = true, .start_m = 4, .end_m = 40 } },
        },
    };
    const default_cell = world.cell.CellId{ .x = 0, .y = 0, .z = 0 };
    const override_cell = world.cell.CellId{ .x = 1, .y = 0, .z = 0 };
    try std.testing.expect(!resolveFogForCell(doc, default_cell).enabled);
    try std.testing.expect(resolveFogForCell(doc, override_cell).enabled);
    try std.testing.expectEqual(@as(f32, 40), resolveFogForCell(doc, override_cell).end_m);
}

test "parse hex fog color" {
    const rgb = try parseHexColor("#8894a8");
    try std.testing.expectEqual(@as(u8, 0x88), rgb[0]);
    try std.testing.expectEqual(@as(u8, 0x94), rgb[1]);
    try std.testing.expectEqual(@as(u8, 0xa8), rgb[2]);
}

test "validate fog bank requires end after start" {
    try std.testing.expectError(error.InvalidAtmosphereValue, validateFogBank(.{ .start_m = 80, .end_m = 8 }));
}

test "validate cloud tone bounds painterly controls" {
    try validateCloudTone(.{});
    try std.testing.expectError(error.InvalidAtmosphereValue, validateCloudTone(.{ .coverage = 1.2 }));
    try std.testing.expectError(error.InvalidAtmosphereValue, validateCloudTone(.{ .softness = 0.0 }));
    try std.testing.expectError(error.InvalidAtmosphereValue, validateCloudTone(.{ .scale = 0.0 }));
    try std.testing.expectError(error.InvalidAtmosphereValue, validateCloudTone(.{ .drift_speed = -0.1 }));
}

test "validate doc rejects duplicate cell fog banks" {
    const doc = AtmosphereDoc{
        .cell_fog_banks = &.{
            .{ .cell = .{ 0, 0, 0 }, .fog = .{} },
            .{ .cell = .{ 0, 0, 0 }, .fog = .{ .enabled = true } },
        },
    };
    try std.testing.expectError(error.DuplicateAtmosphereCellFogBank, validateDoc(doc));
}
