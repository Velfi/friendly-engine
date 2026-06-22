const std = @import("std");
const mesh_builder = @import("mesh_builder.zig");

pub const TextureSize: usize = 128;

pub fn fillLayerTexture(
    out: []u8,
    paint_size: u32,
    paint_layers: []const []const u8,
    paint_colors: []const [4]u8,
    paint_weights: []const u8,
) !void {
    if (out.len < TextureSize * TextureSize * 4) return error.InvalidTerrainTexture;
    const grid: usize = @intCast(paint_size);
    if (grid < 2) return error.InvalidTerrainSplatCount;
    if (paint_layers.len < 2 or paint_layers.len != paint_colors.len) return error.InvalidTerrainPaintLayers;
    if (paint_weights.len != grid * grid * paint_layers.len) return error.InvalidTerrainSplatCount;

    const denom = @as(f32, @floatFromInt(TextureSize - 1));
    var y: usize = 0;
    while (y < TextureSize) : (y += 1) {
        var x: usize = 0;
        while (x < TextureSize) : (x += 1) {
            const u = @as(f32, @floatFromInt(x)) / denom;
            const v = @as(f32, @floatFromInt(y)) / denom;
            const color = try sampleLayerColor(grid, paint_colors, paint_weights, u, v);
            const idx = (y * TextureSize + x) * 4;
            out[idx] = color[0];
            out[idx + 1] = color[1];
            out[idx + 2] = color[2];
            out[idx + 3] = color[3];
        }
    }
}

pub fn buildLayerTexture(
    allocator: std.mem.Allocator,
    paint_size: u32,
    paint_layers: []const []const u8,
    paint_colors: []const [4]u8,
    paint_weights: []const u8,
) ![]u8 {
    const texture = try allocator.alloc(u8, mesh_builder.terrain_texture_size);
    errdefer allocator.free(texture);
    try fillLayerTexture(texture, paint_size, paint_layers, paint_colors, paint_weights);
    return texture;
}

fn sampleLayerColor(
    grid: usize,
    paint_colors: []const [4]u8,
    paint_weights: []const u8,
    u: f32,
    v: f32,
) ![4]u8 {
    var accum = [_]f32{ 0, 0, 0, 0 };
    var total: f32 = 0;
    for (paint_colors, 0..) |color, layer_index| {
        const weight = sampleLayerWeight(grid, paint_colors.len, paint_weights, layer_index, u, v);
        if (weight <= 0) continue;
        accum[0] += @as(f32, @floatFromInt(color[0])) * weight;
        accum[1] += @as(f32, @floatFromInt(color[1])) * weight;
        accum[2] += @as(f32, @floatFromInt(color[2])) * weight;
        accum[3] += @as(f32, @floatFromInt(color[3])) * weight;
        total += weight;
    }
    if (total <= 0) return error.InvalidTerrainSplatCount;
    return .{
        @intFromFloat(@round(std.math.clamp(accum[0] / total, 0, 255))),
        @intFromFloat(@round(std.math.clamp(accum[1] / total, 0, 255))),
        @intFromFloat(@round(std.math.clamp(accum[2] / total, 0, 255))),
        @intFromFloat(@round(std.math.clamp(accum[3] / total, 0, 255))),
    };
}

fn sampleLayerWeight(
    grid: usize,
    layer_count: usize,
    paint_weights: []const u8,
    layer_index: usize,
    u: f32,
    v: f32,
) f32 {
    const sx = std.math.clamp(u * @as(f32, @floatFromInt(grid - 1)), 0.0, @as(f32, @floatFromInt(grid - 1)));
    const sz = std.math.clamp(v * @as(f32, @floatFromInt(grid - 1)), 0.0, @as(f32, @floatFromInt(grid - 1)));
    const x0: usize = @intFromFloat(@floor(sx));
    const z0: usize = @intFromFloat(@floor(sz));
    const x1 = @min(grid - 1, x0 + 1);
    const z1 = @min(grid - 1, z0 + 1);
    const tx = sx - @as(f32, @floatFromInt(x0));
    const tz = sz - @as(f32, @floatFromInt(z0));
    const w00 = weightAt(grid, layer_count, paint_weights, x0, z0, layer_index);
    const w10 = weightAt(grid, layer_count, paint_weights, x1, z0, layer_index);
    const w01 = weightAt(grid, layer_count, paint_weights, x0, z1, layer_index);
    const w11 = weightAt(grid, layer_count, paint_weights, x1, z1, layer_index);
    const wx0 = w00 + (w10 - w00) * tx;
    const wx1 = w01 + (w11 - w01) * tx;
    return (wx0 + (wx1 - wx0) * tz) / 255.0;
}

fn weightAt(grid: usize, layer_count: usize, paint_weights: []const u8, x: usize, z: usize, layer_index: usize) f32 {
    return @floatFromInt(paint_weights[(z * grid + x) * layer_count + layer_index]);
}

test "layer texture blends caller-provided terrain paint colors" {
    const layers = [_][]const u8{ "meadow", "cliff" };
    const colors = [_][4]u8{
        .{ 100, 150, 80, 255 },
        .{ 90, 88, 84, 255 },
    };
    const weights = [_]u8{
        255, 0,
        0,   255,
        255, 0,
        0,   255,
    };
    var tex: [mesh_builder.terrain_texture_size]u8 = undefined;
    try fillLayerTexture(&tex, 2, &layers, &colors, &weights);
    try std.testing.expect(tex[1] > tex[0]);
    const far_idx = (TextureSize * TextureSize - 1) * 4;
    try std.testing.expect(tex[far_idx] < 120);
}

test "paint layers and colors must line up" {
    const layers = [_][]const u8{ "a", "b" };
    const colors = [_][4]u8{.{ 0, 0, 0, 255 }};
    const weights = [_]u8{255} ** 4;
    var tex: [mesh_builder.terrain_texture_size]u8 = undefined;
    try std.testing.expectError(error.InvalidTerrainPaintLayers, fillLayerTexture(&tex, 2, &layers, &colors, &weights));
}

test "layer texture outer texels land on exact paint borders" {
    const layers = [_][]const u8{ "left", "right" };
    const colors = [_][4]u8{
        .{ 10, 0, 0, 255 },
        .{ 200, 0, 0, 255 },
    };
    const weights = [_]u8{
        255, 0,
        0,   255,
        255, 0,
        0,   255,
    };
    var tex: [mesh_builder.terrain_texture_size]u8 = undefined;
    try fillLayerTexture(&tex, 2, &layers, &colors, &weights);
    const left_idx = 0;
    const right_idx = (TextureSize - 1) * 4;
    try std.testing.expectEqual(@as(u8, 10), tex[left_idx]);
    try std.testing.expectEqual(@as(u8, 200), tex[right_idx]);
}
