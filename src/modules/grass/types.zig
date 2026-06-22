const std = @import("std");
const world = @import("../../world/mod.zig");

pub const schema_version: u32 = 1;
pub const max_influencers: usize = 16;
pub const max_instances_per_cell: usize = 24_000;

pub const GrassDoc = struct {
    schema_version: u32 = schema_version,
    global_wind: WindSettings = .{},
    patches: []const GrassPatch = &.{},
};

pub const WindSettings = struct {
    enabled: bool = true,
    direction_deg: f32 = 225.0,
    speed_mps: f32 = 5.0,
};

pub const GrassPatch = struct {
    id: []const u8,
    cell: []const i32,
    density: f32,
    spacing: f32,
    seed: u32 = 1,
    allowed_materials: []const []const u8 = default_allowed_materials,
    excluded_materials: []const []const u8 = default_excluded_materials,
    height_min: f32 = 0.42,
    height_max: f32 = 1.1,
    width_min: f32 = 0.035,
    width_max: f32 = 0.09,
    wind_strength: f32 = 0.55,
    bend_strength: f32 = 0.85,
    stiffness: f32 = 0.72,
    cull_distance_m: f32 = 96.0,
    fade_distance_m: f32 = 18.0,
};

pub const default_allowed_materials: []const []const u8 = &.{ "grass", "marsh" };
pub const default_excluded_materials: []const []const u8 = &.{ "road", "rock", "stone", "beach", "abyss", "gravel" };

pub const GrassInstance = struct {
    position: [3]f32,
    normal: [3]f32,
    material: []const u8,
    color: [4]u8,
    height: f32,
    width: f32,
    yaw: f32,
    phase: f32,
    variant: u32,
};

pub const ClusterControls = struct {
    cull_distance_m: f32,
    fade_distance_m: f32,
    wind_direction_deg: f32,
    wind_speed_mps: f32,
    wind_strength: f32,
    bend_strength: f32,
    stiffness: f32,
};

pub const ClusterMetadata = struct {
    cell: [3]i32,
    instance_count: usize,
    material_count: usize,
    controls: ClusterControls,
};

pub const GrassInfluencer = struct {
    position: [3]f32,
    radius: f32,
    strength: f32,
    velocity_dir: [3]f32 = .{ 0, 0, 0 },
};

pub fn parseCellId(values: []const i32) !world.cell.CellId {
    if (values.len != 2 and values.len != 3) return error.InvalidGrassCell;
    return .{ .x = @intCast(values[0]), .y = @intCast(values[1]), .z = if (values.len == 3) @intCast(values[2]) else 0 };
}

pub fn validateWind(wind: WindSettings) !void {
    if (!std.math.isFinite(wind.direction_deg) or !std.math.isFinite(wind.speed_mps) or wind.speed_mps < 0) return error.InvalidGrassWind;
}

pub fn validatePatch(patch: GrassPatch) !void {
    _ = try parseCellId(patch.cell);
    if (patch.id.len == 0) return error.InvalidGrassPatch;
    if (!std.math.isFinite(patch.density) or patch.density < 0 or patch.density > 1) return error.InvalidGrassPatch;
    if (!std.math.isFinite(patch.spacing) or patch.spacing <= 0) return error.InvalidGrassPatch;
    if (patch.allowed_materials.len == 0) return error.InvalidGrassPatch;
    if (!validRange(patch.height_min, patch.height_max, 0.01, 8.0)) return error.InvalidGrassPatch;
    if (!validRange(patch.width_min, patch.width_max, 0.001, 2.0)) return error.InvalidGrassPatch;
    if (!std.math.isFinite(patch.wind_strength) or patch.wind_strength < 0) return error.InvalidGrassPatch;
    if (!std.math.isFinite(patch.bend_strength) or patch.bend_strength < 0) return error.InvalidGrassPatch;
    if (!std.math.isFinite(patch.stiffness) or patch.stiffness < 0 or patch.stiffness > 1) return error.InvalidGrassPatch;
    if (!std.math.isFinite(patch.cull_distance_m) or patch.cull_distance_m <= 0) return error.InvalidGrassPatch;
    if (!std.math.isFinite(patch.fade_distance_m) or patch.fade_distance_m < 0 or patch.fade_distance_m >= patch.cull_distance_m) return error.InvalidGrassPatch;
}

fn validRange(min_value: f32, max_value: f32, lower: f32, upper: f32) bool {
    return std.math.isFinite(min_value) and std.math.isFinite(max_value) and min_value >= lower and max_value <= upper and min_value <= max_value;
}

pub fn materialAllowed(patch: GrassPatch, material: []const u8) bool {
    for (patch.excluded_materials) |excluded| {
        if (std.mem.eql(u8, material, excluded)) return false;
    }
    for (patch.allowed_materials) |allowed| {
        if (std.mem.eql(u8, material, allowed)) return true;
    }
    return false;
}

pub fn stylizedGrassColor(material: []const u8, source: [4]u8) [4]u8 {
    const bias: [3]u8 = if (std.mem.eql(u8, material, "marsh"))
        .{ 54, 108, 82 }
    else if (std.mem.eql(u8, material, "dirt"))
        .{ 116, 124, 72 }
    else if (std.mem.eql(u8, material, "shelf") or std.mem.eql(u8, material, "chalk"))
        .{ 146, 160, 98 }
    else
        .{ 84, 150, 74 };
    return .{
        mixChannel(source[0], bias[0]),
        mixChannel(source[1], bias[1]),
        mixChannel(source[2], bias[2]),
        255,
    };
}

fn mixChannel(a: u8, b: u8) u8 {
    return @intCast((@as(u16, a) + @as(u16, b) * 3) / 4);
}

pub fn validateInfluencer(influencer: GrassInfluencer) !void {
    if (!std.math.isFinite(influencer.position[0]) or !std.math.isFinite(influencer.position[1]) or !std.math.isFinite(influencer.position[2])) return error.InvalidGrassInfluencer;
    if (!std.math.isFinite(influencer.radius) or influencer.radius <= 0) return error.InvalidGrassInfluencer;
    if (!std.math.isFinite(influencer.strength) or influencer.strength < 0) return error.InvalidGrassInfluencer;
}

test "grass types validate defaults and material filtering" {
    const patch = GrassPatch{ .id = "south", .cell = &.{ 0, 0, 0 }, .density = 0.8, .spacing = 2 };
    try validatePatch(patch);
    try std.testing.expect(materialAllowed(patch, "grass"));
    try std.testing.expect(!materialAllowed(patch, "road"));
}

test "grass colors bias terrain material toward painterly palette" {
    const color = stylizedGrassColor("grass", .{ 10, 90, 20, 255 });
    try std.testing.expect(color[1] > color[0]);
    try std.testing.expectEqual(@as(u8, 255), color[3]);
}
