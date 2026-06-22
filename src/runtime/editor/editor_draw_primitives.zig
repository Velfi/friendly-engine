const std = @import("std");
const editor_draw = @import("editor_draw.zig");

pub const Color = editor_draw.Color;
const SDL_Renderer = editor_draw.SDL_Renderer;

const max_tex_dim: usize = 128;

pub fn fillCircle(renderer: *SDL_Renderer, cx: f32, cy: f32, radius: f32, color: Color) !void {
    const pad: f32 = 2.0;
    const local_center = radius + pad;
    const diameter = @ceil(radius * 2.0 + pad * 2.0);
    const tex_w: usize = @intFromFloat(diameter);
    const tex_h = tex_w;
    if (tex_w == 0 or tex_w > max_tex_dim) return error.ShapeTooLarge;

    var pixels: [max_tex_dim * max_tex_dim * 4]u8 = undefined;
    @memset(pixels[0 .. tex_w * tex_h * 4], 0);

    var y: usize = 0;
    while (y < tex_h) : (y += 1) {
        var x: usize = 0;
        while (x < tex_w) : (x += 1) {
            const px = @as(f32, @floatFromInt(x)) + 0.5 - local_center;
            const py = @as(f32, @floatFromInt(y)) + 0.5 - local_center;
            const coverage = fillCoverage(px, py, radius);
            setPixelAlpha(&pixels, tex_w, x, y, coverage);
        }
    }

    try blitMask(renderer, pixels[0 .. tex_w * tex_h * 4], tex_w, tex_h, cx - local_center, cy - local_center, color);
}

pub fn strokeCircle(renderer: *SDL_Renderer, cx: f32, cy: f32, radius: f32, stroke_width: f32, color: Color) !void {
    const pad: f32 = 2.0;
    const local_center = radius + pad;
    const diameter = @ceil(radius * 2.0 + pad * 2.0);
    const tex_w: usize = @intFromFloat(diameter);
    const tex_h = tex_w;
    if (tex_w == 0 or tex_w > max_tex_dim) return error.ShapeTooLarge;

    var pixels: [max_tex_dim * max_tex_dim * 4]u8 = undefined;
    @memset(pixels[0 .. tex_w * tex_h * 4], 0);

    const half_width = stroke_width * 0.5;
    var y: usize = 0;
    while (y < tex_h) : (y += 1) {
        var x: usize = 0;
        while (x < tex_w) : (x += 1) {
            const px = @as(f32, @floatFromInt(x)) + 0.5 - local_center;
            const py = @as(f32, @floatFromInt(y)) + 0.5 - local_center;
            const coverage = ringCoverage(px, py, radius, half_width);
            setPixelAlpha(&pixels, tex_w, x, y, coverage);
        }
    }

    try blitMask(renderer, pixels[0 .. tex_w * tex_h * 4], tex_w, tex_h, cx - local_center, cy - local_center, color);
}

pub fn line(renderer: *SDL_Renderer, x0: f32, y0: f32, x1: f32, y1: f32, width: f32, color: Color) !void {
    const half = width * 0.5;
    const pad: f32 = 2.0;
    const min_x = @min(x0, x1) - half - pad;
    const min_y = @min(y0, y1) - half - pad;
    const max_x = @max(x0, x1) + half + pad;
    const max_y = @max(y0, y1) + half + pad;
    const tex_w: usize = @intFromFloat(@ceil(max_x - min_x));
    const tex_h: usize = @intFromFloat(@ceil(max_y - min_y));
    if (tex_w == 0 or tex_h == 0 or tex_w > max_tex_dim or tex_h > max_tex_dim) return error.ShapeTooLarge;

    const local_x0 = x0 - min_x;
    const local_y0 = y0 - min_y;
    const local_x1 = x1 - min_x;
    const local_y1 = y1 - min_y;

    var pixels: [max_tex_dim * max_tex_dim * 4]u8 = undefined;
    @memset(pixels[0 .. tex_w * tex_h * 4], 0);

    var y: usize = 0;
    while (y < tex_h) : (y += 1) {
        var x: usize = 0;
        while (x < tex_w) : (x += 1) {
            const px = @as(f32, @floatFromInt(x)) + 0.5;
            const py = @as(f32, @floatFromInt(y)) + 0.5;
            const coverage = lineCoverage(px, py, local_x0, local_y0, local_x1, local_y1, half);
            setPixelAlpha(&pixels, tex_w, x, y, coverage);
        }
    }

    try blitMask(renderer, pixels[0 .. tex_w * tex_h * 4], tex_w, tex_h, min_x, min_y, color);
}

fn fillCoverage(dx: f32, dy: f32, radius: f32) f32 {
    const dist = @sqrt(dx * dx + dy * dy);
    return std.math.clamp(radius + 0.5 - dist, 0.0, 1.0);
}

fn ringCoverage(dx: f32, dy: f32, radius: f32, half_width: f32) f32 {
    const dist = @sqrt(dx * dx + dy * dy);
    const inner = radius - half_width;
    const outer = radius + half_width;
    return std.math.clamp(@min(dist - inner, outer - dist) + 0.5, 0.0, 1.0);
}

fn lineCoverage(px: f32, py: f32, x0: f32, y0: f32, x1: f32, y1: f32, half_width: f32) f32 {
    const dist = segmentDistance(px, py, x0, y0, x1, y1);
    return std.math.clamp(half_width + 0.5 - dist, 0.0, 1.0);
}

fn segmentDistance(px: f32, py: f32, x0: f32, y0: f32, x1: f32, y1: f32) f32 {
    const dx = x1 - x0;
    const dy = y1 - y0;
    const len_sq = dx * dx + dy * dy;
    if (len_sq <= std.math.floatEps(f32)) {
        const ox = px - x0;
        const oy = py - y0;
        return @sqrt(ox * ox + oy * oy);
    }
    const t = std.math.clamp(((px - x0) * dx + (py - y0) * dy) / len_sq, 0.0, 1.0);
    const qx = x0 + dx * t;
    const qy = y0 + dy * t;
    const ox = px - qx;
    const oy = py - qy;
    return @sqrt(ox * ox + oy * oy);
}

fn setPixelAlpha(pixels: []u8, width: usize, x: usize, y: usize, coverage: f32) void {
    if (coverage <= 0.0) return;
    const alpha: u8 = @intFromFloat(std.math.clamp(coverage, 0.0, 1.0) * 255.0);
    const i = (y * width + x) * 4;
    pixels[i] = 255;
    pixels[i + 1] = 255;
    pixels[i + 2] = 255;
    pixels[i + 3] = alpha;
}

fn blitMask(renderer: *SDL_Renderer, pixels: []const u8, width: usize, height: usize, x: f32, y: f32, color: Color) !void {
    const texture = editor_draw.SDL_CreateTexture(
        renderer,
        editor_draw.SDL_PIXELFORMAT_RGBA32,
        editor_draw.SDL_TEXTUREACCESS_STREAMING,
        @intCast(width),
        @intCast(height),
    ) orelse return error.SdlTextureCreationFailed;
    defer editor_draw.SDL_DestroyTexture(texture);

    if (!editor_draw.SDL_SetTextureBlendMode(texture, editor_draw.SDL_BLENDMODE_BLEND)) return error.SdlTextureBlendFailed;
    if (!editor_draw.SDL_UpdateTexture(texture, null, pixels.ptr, @intCast(width * 4))) return error.SdlTextureUpdateFailed;
    if (!editor_draw.SDL_SetTextureColorMod(texture, color.r, color.g, color.b)) return error.SdlTextureColorModFailed;
    if (!editor_draw.SDL_SetTextureAlphaMod(texture, color.a)) return error.SdlTextureAlphaModFailed;

    const dst = editor_draw.SDL_FRect{ .x = x, .y = y, .w = @floatFromInt(width), .h = @floatFromInt(height) };
    if (!editor_draw.SDL_RenderTexture(renderer, texture, null, &dst)) return error.SdlTextureRenderFailed;
}

test "fill coverage peaks at circle center" {
    try std.testing.expectEqual(@as(f32, 1.0), fillCoverage(0.0, 0.0, 8.0));
    try std.testing.expect(fillCoverage(8.5, 0.0, 8.0) < 0.5);
    try std.testing.expectEqual(@as(f32, 0.0), fillCoverage(10.0, 0.0, 8.0));
}

test "ring coverage is strongest on the stroke centerline" {
    try std.testing.expect(ringCoverage(8.0, 0.0, 8.0, 0.5) > 0.9);
    try std.testing.expect(ringCoverage(0.0, 0.0, 8.0, 0.5) < 0.1);
}

test "line coverage is strongest on the segment midpoint" {
    try std.testing.expect(lineCoverage(5.0, 5.0, 0.0, 5.0, 10.0, 5.0, 0.5) > 0.9);
    try std.testing.expect(lineCoverage(5.0, 8.0, 0.0, 5.0, 10.0, 5.0, 0.5) < 0.1);
}
