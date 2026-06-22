const std = @import("std");
const project_editor_types = @import("project_editor_types.zig");

pub fn parseFormations(allocator: std.mem.Allocator, value: std.json.Value) ![]project_editor_types.TerrainFormation {
    const root = switch (value) {
        .object => |object| object,
        else => return error.InvalidTerrainFormationRecipe,
    };
    const formations_value = root.get("formations") orelse return error.InvalidTerrainFormationRecipe;
    const array = switch (formations_value) {
        .array => |array| array,
        else => return error.InvalidTerrainFormationRecipe,
    };
    if (array.items.len == 0 or array.items.len > 16) return error.InvalidTerrainFormationCount;
    const formations = try allocator.alloc(project_editor_types.TerrainFormation, array.items.len);
    errdefer allocator.free(formations);
    for (array.items, 0..) |item, index| {
        formations[index] = try parseFormation(item);
    }
    return formations;
}

pub fn parseFeatures(allocator: std.mem.Allocator, value: std.json.Value) ![]project_editor_types.TerrainRecipeFeature {
    const array = switch (value) {
        .array => |array| array,
        else => return error.InvalidTerrainRecipe,
    };
    if (array.items.len == 0 or array.items.len > 128) return error.InvalidTerrainRecipeFeatureCount;
    const features = try allocator.alloc(project_editor_types.TerrainRecipeFeature, array.items.len);
    errdefer allocator.free(features);
    for (array.items, 0..) |item, index| {
        features[index] = try parseFeature(item);
    }
    return features;
}

fn parseFeature(value: std.json.Value) !project_editor_types.TerrainRecipeFeature {
    const object = switch (value) {
        .object => |object| object,
        else => return error.InvalidTerrainRecipe,
    };
    var feature = project_editor_types.TerrainRecipeFeature{
        .brush = try project_editor_types.TerrainRecipeBrush.parse(try jsonString(object, "brush")),
    };
    if (jsonVec2(object, "center")) |center| {
        feature.center_x = center[0];
        feature.center_z = center[1];
    }
    if (jsonVec2(object, "radius")) |radius| {
        feature.radius_x = radius[0];
        feature.radius_z = radius[1];
        feature.outer_radius = radius[0];
    }
    if (jsonNumber(object, "height")) |number| feature.height = number;
    if (jsonNumber(object, "coast_noise")) |number| feature.coast_noise = number;
    if (jsonNumber(object, "outer_radius")) |number| {
        feature.outer_radius = number;
        feature.radius_x = number;
        feature.radius_z = number;
    }
    if (jsonNumber(object, "rim_height")) |number| feature.rim_height = number;
    if (jsonNumber(object, "inner_radius")) |number| feature.inner_radius = number;
    if (jsonNumber(object, "crater_floor")) |number| feature.crater_floor = number;
    if (jsonNumber(object, "plug_radius")) |number| feature.plug_radius = number;
    if (jsonNumber(object, "plug_height")) |number| feature.plug_height = number;
    if (jsonInteger(object, "breaches")) |number| feature.breaches = @intCast(@max(0, number));
    if (jsonInteger(object, "count")) |number| feature.count = @intCast(@max(0, number));
    if (jsonNumber(object, "width")) |number| feature.width = number;
    if (jsonNumber(object, "erosion")) |number| feature.erosion = number;
    if (jsonNumber(object, "gully_density")) |number| feature.gully_density = number;
    if (jsonNumber(object, "basalt_roughness")) |number| feature.basalt_roughness = number;
    if (jsonNumber(object, "channel_depth")) |number| feature.channel_depth = number;
    if (jsonInteger(object, "channel_count")) |number| feature.channel_count = @intCast(@max(0, number));
    if (jsonInteger(object, "craters")) |number| feature.craters = @intCast(@max(0, number));
    if (jsonNumber(object, "weathering")) |number| feature.weathering = number;
    if (jsonInteger(object, "horn_count")) |number| feature.horn_count = @intCast(@max(0, number));
    if (jsonNumber(object, "cliff_height")) |number| feature.cliff_height = number;
    if (jsonNumber(object, "plateau_height")) |number| feature.plateau_height = number;
    if (jsonInteger(object, "terraces")) |number| feature.terraces = @intCast(@max(0, number));
    if (jsonNumber(object, "badland_apron")) |number| feature.badland_apron = number;
    if (jsonInteger(object, "wash_count")) |number| feature.wash_count = @intCast(@max(0, number));
    if (jsonNumber(object, "crack_density")) |number| feature.crack_density = number;
    if (jsonInteger(object, "hooks")) |number| feature.hooks = @intCast(@max(0, number));
    if (jsonInteger(object, "beach_pockets")) |number| feature.beach_pockets = @intCast(@max(0, number));
    if (jsonNumber(object, "coast_jaggedness")) |number| feature.coast_jaggedness = number;
    if (jsonNumber(object, "bottom_height")) |number| feature.bottom_height = number;
    if (jsonNumber(object, "rim_width")) |number| feature.rim_width = number;
    if (jsonNumber(object, "cliff_top_min")) |number| feature.cliff_top_min = number;
    return feature;
}

fn parseFormation(value: std.json.Value) !project_editor_types.TerrainFormation {
    const object = switch (value) {
        .object => |object| object,
        else => return error.InvalidTerrainFormationRecipe,
    };
    const kind = try project_editor_types.TerrainFormationKind.parse(try jsonString(object, "kind"));
    return .{
        .kind = kind,
        .x = jsonNumber(object, "x") orelse 0,
        .z = jsonNumber(object, "z") orelse 0,
        .radius = jsonNumber(object, "radius") orelse 1,
        .width = jsonNumber(object, "width") orelse 1,
        .height = jsonNumber(object, "height") orelse 0,
        .scale = jsonNumber(object, "scale") orelse 1,
        .axis = axisByte(jsonString(object, "axis") catch "z"),
        .start = jsonNumber(object, "start") orelse 0,
        .end = jsonNumber(object, "end") orelse 1,
    };
}

fn jsonString(object: std.json.ObjectMap, key: []const u8) ![]const u8 {
    const value = object.get(key) orelse return error.InvalidTerrainFormationRecipe;
    return switch (value) {
        .string => |string| string,
        else => error.InvalidTerrainFormationRecipe,
    };
}

fn jsonNumber(object: std.json.ObjectMap, key: []const u8) ?f32 {
    const value = object.get(key) orelse return null;
    return switch (value) {
        .integer => |integer| @floatFromInt(integer),
        .float => |float| @floatCast(float),
        else => null,
    };
}

fn jsonInteger(object: std.json.ObjectMap, key: []const u8) ?i64 {
    const value = object.get(key) orelse return null;
    return switch (value) {
        .integer => |integer| integer,
        .float => |float| @intFromFloat(float),
        else => null,
    };
}

fn jsonVec2(object: std.json.ObjectMap, key: []const u8) ?[2]f32 {
    const value = object.get(key) orelse return null;
    const array = switch (value) {
        .array => |array| array,
        else => return null,
    };
    if (array.items.len < 2) return null;
    return .{ jsonValueNumber(array.items[0]) orelse return null, jsonValueNumber(array.items[1]) orelse return null };
}

fn jsonValueNumber(value: std.json.Value) ?f32 {
    return switch (value) {
        .integer => |integer| @floatFromInt(integer),
        .float => |float| @floatCast(float),
        else => null,
    };
}

fn axisByte(value: []const u8) u8 {
    if (std.mem.eql(u8, value, "x")) return 'x';
    return 'z';
}
