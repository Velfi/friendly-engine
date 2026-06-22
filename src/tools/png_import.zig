const std = @import("std");
const zigimg = @import("zigimg");

pub const texture_size: u32 = 128;
pub const texture_pixel_bytes: usize = texture_size * texture_size * 4;

pub fn decodePngToRgba128(allocator: std.mem.Allocator, png_bytes: []const u8) ![]u8 {
    var image = try zigimg.Image.fromMemory(allocator, png_bytes);
    defer image.deinit(allocator);

    try image.convert(allocator, .rgba32);

    const out = try allocator.alloc(u8, texture_pixel_bytes);
    resizeNearestNeighbor(
        image.rawBytes(),
        @intCast(image.width),
        @intCast(image.height),
        4,
        out,
        texture_size,
        texture_size,
    );
    return out;
}

fn resizeNearestNeighbor(
    src: []const u8,
    src_w: u32,
    src_h: u32,
    src_channels: u8,
    dst: []u8,
    dst_w: u32,
    dst_h: u32,
) void {
    var y: u32 = 0;
    while (y < dst_h) : (y += 1) {
        const src_y = y * src_h / dst_h;
        var x: u32 = 0;
        while (x < dst_w) : (x += 1) {
            const src_x = x * src_w / dst_w;
            const src_idx = (src_y * src_w + src_x) * src_channels;
            const dst_idx = (y * dst_w + x) * 4;
            dst[dst_idx] = src[src_idx];
            dst[dst_idx + 1] = src[src_idx + 1];
            dst[dst_idx + 2] = src[src_idx + 2];
            dst[dst_idx + 3] = if (src_channels == 4) src[src_idx + 3] else 255;
        }
    }
}

test "png decode produces 128x128 rgba" {
    const png = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "assets/source/textures/default.png",
        std.testing.allocator,
        .limited(1024 * 1024),
    ) catch return;
    defer std.testing.allocator.free(png);

    const rgba = try decodePngToRgba128(std.testing.allocator, png);
    defer std.testing.allocator.free(rgba);
    try std.testing.expectEqual(texture_pixel_bytes, rgba.len);
}
