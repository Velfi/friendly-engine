const std = @import("std");

pub const schema_version: u32 = 1;

pub const ScatterDoc = struct {
    schema_version: u32 = schema_version,
    rules: []const ScatterRule = &.{},
    density_masks: []const DensityMask = &.{},
    exclusions: []const ExclusionZone = &.{},
    biome_rules: []const BiomeRule = &.{},
    runtime_controls: RuntimeControls = .{},
};

pub const ScatterRule = struct {
    id: []const u8,
    cell: []const i32,
    prototype: []const u8,
    density: f32,
    spacing: f32 = 4.0,
    slope_min: f32 = 0.0,
    slope_max: f32 = 90.0,
    biome: []const u8 = "default",
    seed: u32 = 1,
    scale_min: f32 = 0.8,
    scale_max: f32 = 1.2,
};

pub const DensityMask = struct {
    cell: []const i32,
    size: u32,
    values: []const u8,
};

pub const ExclusionZone = struct {
    cell: []const i32,
    min: []const f32,
    max: []const f32,
};

pub const BiomeRule = struct {
    id: []const u8,
    density_multiplier: f32 = 1.0,
    spacing_multiplier: f32 = 1.0,
    scale_multiplier: f32 = 1.0,
};

pub const RuntimeControls = struct {
    cull_distance_m: f32 = 128.0,
    fade_distance_m: f32 = 16.0,
    max_instances_per_cluster: u32 = 4096,
    cast_shadows: bool = false,
    receive_shadows: bool = true,
    lod_bias: f32 = 1.0,
};

pub const ClusterInstance = struct {
    prototype: []const u8,
    position: [3]f32,
    scale: f32,
};

pub const CompiledRule = struct {
    id: []const u8,
    prototype: []const u8,
    density: f32,
    spacing: f32,
    slope_min: f32,
    slope_max: f32,
    biome: []const u8,
    seed: u32,
    scale_min: f32,
    scale_max: f32,
};

pub fn validateRule(rule: ScatterRule) !void {
    _ = try parseCellId(rule.cell);
    if (rule.id.len == 0 or rule.prototype.len == 0) return error.InvalidScatterRule;
    if (!std.math.isFinite(rule.density) or rule.density < 0 or rule.density > 1) return error.InvalidScatterRule;
    if (!std.math.isFinite(rule.spacing) or rule.spacing <= 0) return error.InvalidScatterRule;
    if (!std.math.isFinite(rule.slope_min) or !std.math.isFinite(rule.slope_max)) return error.InvalidScatterRule;
    if (rule.slope_min < 0 or rule.slope_max > 90 or rule.slope_min > rule.slope_max) return error.InvalidScatterRule;
    if (rule.biome.len == 0) return error.InvalidScatterRule;
    if (!std.math.isFinite(rule.scale_min) or !std.math.isFinite(rule.scale_max)) return error.InvalidScatterRule;
    if (rule.scale_min <= 0 or rule.scale_max <= 0 or rule.scale_min > rule.scale_max) return error.InvalidScatterRule;
}

pub fn validateMask(mask: DensityMask) !void {
    _ = try parseCellId(mask.cell);
    if (mask.size < 1) return error.InvalidDensityMask;
    const sample_count = @as(usize, mask.size) * @as(usize, mask.size);
    if (mask.values.len != sample_count) return error.InvalidDensityMask;
}

pub fn validateExclusion(zone: ExclusionZone) !void {
    _ = try parseCellId(zone.cell);
    if (zone.min.len != 3 or zone.max.len != 3) return error.InvalidExclusionZone;
    for (zone.min, zone.max) |min_value, max_value| {
        if (!std.math.isFinite(min_value) or !std.math.isFinite(max_value)) return error.InvalidExclusionZone;
        if (min_value > max_value) return error.InvalidExclusionZone;
    }
}

pub fn validateBiomeRule(rule: BiomeRule) !void {
    if (rule.id.len == 0) return error.InvalidScatterBiomeRule;
    if (!std.math.isFinite(rule.density_multiplier) or rule.density_multiplier < 0) return error.InvalidScatterBiomeRule;
    if (!std.math.isFinite(rule.spacing_multiplier) or rule.spacing_multiplier <= 0) return error.InvalidScatterBiomeRule;
    if (!std.math.isFinite(rule.scale_multiplier) or rule.scale_multiplier <= 0) return error.InvalidScatterBiomeRule;
}

pub fn validateRuntimeControls(controls: RuntimeControls) !void {
    if (!std.math.isFinite(controls.cull_distance_m) or controls.cull_distance_m <= 0) return error.InvalidScatterRuntimeControls;
    if (!std.math.isFinite(controls.fade_distance_m) or controls.fade_distance_m < 0) return error.InvalidScatterRuntimeControls;
    if (controls.fade_distance_m >= controls.cull_distance_m) return error.InvalidScatterRuntimeControls;
    if (controls.max_instances_per_cluster == 0) return error.InvalidScatterRuntimeControls;
    if (!std.math.isFinite(controls.lod_bias) or controls.lod_bias <= 0) return error.InvalidScatterRuntimeControls;
}

pub fn parseCellId(values: []const i32) !@import("../../world/mod.zig").cell.CellId {
    if (values.len != 2 and values.len != 3) return error.InvalidScatterCell;
    return .{
        .x = @intCast(values[0]),
        .y = @intCast(values[1]),
        .z = if (values.len == 3) @intCast(values[2]) else 0,
    };
}

pub fn findBiomeRule(rules: []const BiomeRule, id: []const u8) ?BiomeRule {
    for (rules) |rule| {
        if (std.mem.eql(u8, rule.id, id)) return rule;
    }
    return null;
}

pub fn compileRule(rule: ScatterRule, biome_rule: ?BiomeRule) !CompiledRule {
    try validateRule(rule);
    const biome = biome_rule orelse return .{
        .id = rule.id,
        .prototype = rule.prototype,
        .density = rule.density,
        .spacing = rule.spacing,
        .slope_min = rule.slope_min,
        .slope_max = rule.slope_max,
        .biome = rule.biome,
        .seed = rule.seed,
        .scale_min = rule.scale_min,
        .scale_max = rule.scale_max,
    };
    try validateBiomeRule(biome);
    return .{
        .id = rule.id,
        .prototype = rule.prototype,
        .density = @min(1.0, rule.density * biome.density_multiplier),
        .spacing = rule.spacing * biome.spacing_multiplier,
        .slope_min = rule.slope_min,
        .slope_max = rule.slope_max,
        .biome = rule.biome,
        .seed = rule.seed,
        .scale_min = rule.scale_min * biome.scale_multiplier,
        .scale_max = rule.scale_max * biome.scale_multiplier,
    };
}

test "scatter types validate biome rules and runtime controls" {
    try validateBiomeRule(.{ .id = "forest", .density_multiplier = 1.2 });
    try std.testing.expectError(error.InvalidScatterBiomeRule, validateBiomeRule(.{
        .id = "forest",
        .spacing_multiplier = 0,
    }));
    try validateRuntimeControls(.{ .cull_distance_m = 64, .fade_distance_m = 8 });
    try std.testing.expectError(error.InvalidScatterRuntimeControls, validateRuntimeControls(.{
        .cull_distance_m = 8,
        .fade_distance_m = 8,
    }));
}

test "scatter types apply biome rule data to compile rules" {
    const compiled = try compileRule(.{
        .id = "grass",
        .cell = &.{ 0, 0, 0 },
        .prototype = "scatter.grass",
        .density = 0.5,
        .spacing = 4,
        .biome = "meadow",
        .scale_min = 1,
        .scale_max = 2,
    }, .{
        .id = "meadow",
        .density_multiplier = 1.5,
        .spacing_multiplier = 2,
        .scale_multiplier = 0.5,
    });
    try std.testing.expectEqual(@as(f32, 0.75), compiled.density);
    try std.testing.expectEqual(@as(f32, 8), compiled.spacing);
    try std.testing.expectEqual(@as(f32, 0.5), compiled.scale_min);
    try std.testing.expectEqual(@as(f32, 1), compiled.scale_max);
}
