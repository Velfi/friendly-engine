const std = @import("std");
const shared = @import("runtime_shared");

const Color = shared.color.Color;
const OverlayQuad = shared.gpu_scene.OverlayQuad;
const TextureHandle = *shared.sdl_gpu.SDL_GPUTexture;
const Vec2 = @import("friendly_engine").core.math.Vec2f;

pub const SdfAtlasKind = enum {
    sdf,
    msdf,
    mtsdf,
};

pub const RectI = struct {
    x: i32,
    y: i32,
    w: i32,
    h: i32,
};

pub const RectF = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
};

pub const IconId = []const u8;

pub const SdfAtlas = struct {
    texture: TextureHandle,
    kind: SdfAtlasKind,
    width_px: u32,
    height_px: u32,
    px_range: f32,
};

pub const SdfGlyph = struct {
    codepoint: u32,
    atlas_rect_px: RectI,
    plane_bounds: RectF,
    advance: f32,
};

pub const SdfIcon = struct {
    id: IconId,
    atlas_rect_px: RectI,
    plane_bounds: RectF,
};

pub const SdfTextStyle = struct {
    size_px: f32,
    color: Color,
    outline_color: Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
    outline_width_px: f32 = 0,
    shadow_color: Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
    shadow_offset_px: Vec2 = .{ .x = 0, .y = 0 },
};

pub const RuntimeAtlas = struct {
    atlas: SdfAtlas,
    glyphs: []const SdfGlyph,
    icons: []const SdfIcon,
    line_height: f32,
    ascender: f32,

    pub fn findGlyph(self: *const RuntimeAtlas, codepoint: u32) ?SdfGlyph {
        for (self.glyphs) |glyph| {
            if (glyph.codepoint == codepoint) return glyph;
        }
        return null;
    }

    pub fn findIcon(self: *const RuntimeAtlas, id: IconId) ?SdfIcon {
        for (self.icons) |icon| {
            if (std.mem.eql(u8, icon.id, id)) return icon;
        }
        return null;
    }

    pub fn appendText(
        self: *const RuntimeAtlas,
        allocator: std.mem.Allocator,
        out: *std.ArrayList(OverlayQuad),
        text: []const u8,
        x: f32,
        y: f32,
        max_width: ?f32,
        style: SdfTextStyle,
    ) !bool {
        // TODO(sdf-text): consume generated kerning pairs and shaped glyph runs instead of ASCII byte iteration.
        // TODO(sdf-text): use outline_color/outline_width_px and shadow_* once the fragment constants path exists.
        var pen_x = x;
        const baseline_y = y + self.ascender * style.size_px;
        const max_x = if (max_width) |width| x + @max(0, width) else null;
        var emitted = false;

        for (text) |byte| {
            if (byte == '\n') break;
            const glyph = self.findGlyph(byte) orelse return false;
            if (max_x) |limit| {
                if (pen_x >= limit) break;
            }
            const dst = rectFromPlane(glyph.plane_bounds, pen_x, baseline_y, style.size_px);
            var draw_w = dst.w;
            if (max_x) |limit| {
                if (dst.x >= limit) {
                    pen_x += glyph.advance * style.size_px;
                    continue;
                }
                draw_w = @min(draw_w, limit - dst.x);
            }
            if (draw_w > 0 and dst.h > 0) {
                var uv = uvFromAtlasRect(self.atlas, glyph.atlas_rect_px);
                if (draw_w < dst.w) {
                    uv[2] = uv[0] + (uv[2] - uv[0]) * (draw_w / dst.w);
                }
                try out.append(allocator, .{
                    .rect = .{ dst.x, dst.y, draw_w, dst.h },
                    .uv = uv,
                    .gpu_texture = @ptrCast(self.atlas.texture),
                    .color = style.color,
                    .material = .distance_field,
                });
                emitted = true;
            }
            pen_x += glyph.advance * style.size_px;
        }

        return emitted;
    }

    pub fn appendIcon(
        self: *const RuntimeAtlas,
        allocator: std.mem.Allocator,
        out: *std.ArrayList(OverlayQuad),
        id: IconId,
        rect: RectF,
        color: Color,
    ) !bool {
        const icon = self.findIcon(id) orelse return false;
        const bounds = icon.plane_bounds;
        try out.append(allocator, .{
            .rect = .{
                rect.x + bounds.x * rect.w,
                rect.y + bounds.y * rect.h,
                bounds.w * rect.w,
                bounds.h * rect.h,
            },
            .uv = uvFromAtlasRect(self.atlas, icon.atlas_rect_px),
            .gpu_texture = @ptrCast(self.atlas.texture),
            .color = color,
            .material = .distance_field,
        });
        return true;
    }

    pub fn appendWorldLabelStub(self: *const RuntimeAtlas) void {
        _ = self;
        // TODO(sdf-world-labels): project world-space anchors into screen-space and depth-fade/clamp labels.
    }
};

fn rectFromPlane(bounds: RectF, pen_x: f32, baseline_y: f32, size_px: f32) RectF {
    return .{
        .x = pen_x + bounds.x * size_px,
        .y = baseline_y - (bounds.y + bounds.h) * size_px,
        .w = bounds.w * size_px,
        .h = bounds.h * size_px,
    };
}

fn uvFromAtlasRect(atlas: SdfAtlas, rect: RectI) [4]f32 {
    const atlas_w: f32 = @floatFromInt(atlas.width_px);
    const atlas_h: f32 = @floatFromInt(atlas.height_px);
    const x: f32 = @floatFromInt(rect.x);
    const y: f32 = @floatFromInt(rect.y);
    const w: f32 = @floatFromInt(rect.w);
    const h: f32 = @floatFromInt(rect.h);
    return .{ x / atlas_w, y / atlas_h, (x + w) / atlas_w, (y + h) / atlas_h };
}

test "sdf atlas glyph lookup is explicit" {
    const glyphs = [_]SdfGlyph{.{
        .codepoint = 'A',
        .atlas_rect_px = .{ .x = 0, .y = 0, .w = 16, .h = 16 },
        .plane_bounds = .{ .x = 0, .y = 0, .w = 1, .h = 1 },
        .advance = 0.8,
    }};
    const atlas = RuntimeAtlas{
        .atlas = .{
            .texture = undefined,
            .kind = .msdf,
            .width_px = 128,
            .height_px = 128,
            .px_range = 4,
        },
        .glyphs = &glyphs,
        .icons = &.{},
        .line_height = 1.2,
        .ascender = 0.9,
    };
    try std.testing.expect(atlas.findGlyph('A') != null);
    try std.testing.expect(atlas.findGlyph('B') == null);
}
