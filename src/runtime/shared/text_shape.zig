const std = @import("std");

const c = @cImport({
    @cInclude("fe_harfbuzz_shape.h");
});

pub const Glyph = struct {
    glyph_id: u32,
    cluster: u32,
    x_advance: i32,
    y_advance: i32,
    x_offset: i32,
    y_offset: i32,
};

pub fn shapeUtf8(
    allocator: std.mem.Allocator,
    font_bytes: []const u8,
    text: []const u8,
) ![]Glyph {
    var glyph_count: c_int = 0;
    var result = c.fe_hb_shape_utf8(
        font_bytes.ptr,
        @intCast(font_bytes.len),
        text.ptr,
        @intCast(text.len),
        null,
        0,
        &glyph_count,
    );
    if (result != 0 and result != 3) return error.TextShapeFailed;
    if (glyph_count < 0) return error.TextShapeFailed;

    const out = try allocator.alloc(Glyph, @intCast(glyph_count));
    errdefer allocator.free(out);
    if (out.len == 0) return out;

    const raw = try allocator.alloc(c.FeHbGlyph, out.len);
    defer allocator.free(raw);
    result = c.fe_hb_shape_utf8(
        font_bytes.ptr,
        @intCast(font_bytes.len),
        text.ptr,
        @intCast(text.len),
        raw.ptr,
        @intCast(raw.len),
        &glyph_count,
    );
    if (result != 0) return error.TextShapeFailed;
    if (@as(usize, @intCast(glyph_count)) != out.len) return error.TextShapeFailed;

    for (raw, out) |source, *dest| {
        dest.* = .{
            .glyph_id = source.glyph_id,
            .cluster = source.cluster,
            .x_advance = source.x_advance,
            .y_advance = source.y_advance,
            .x_offset = source.x_offset,
            .y_offset = source.y_offset,
        };
    }
    return out;
}

test "harfbuzz shapes utf8 into positioned glyph ids" {
    const font = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "third_party/fonts/AtkinsonHyperlegible-Regular.ttf",
        std.testing.allocator,
        .limited(8 * 1024 * 1024),
    );
    defer std.testing.allocator.free(font);

    const glyphs = try shapeUtf8(std.testing.allocator, font, "AV");
    defer std.testing.allocator.free(glyphs);

    try std.testing.expectEqual(@as(usize, 2), glyphs.len);
    try std.testing.expect(glyphs[0].glyph_id != 0);
    try std.testing.expect(glyphs[0].x_advance > 0);
}
