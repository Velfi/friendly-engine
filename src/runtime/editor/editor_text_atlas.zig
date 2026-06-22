const std = @import("std");
const shared = @import("runtime_shared");
const editor_draw = @import("editor_draw.zig");

const sdl = shared.sdl;

pub const GlyphSlot = struct {
    u0: f32,
    v0: f32,
    u1: f32,
    v1: f32,
    pixel_x: u32,
    pixel_y: u32,
    pixel_w: u32,
    pixel_h: u32,
};

pub const Atlas = struct {
    allocator: std.mem.Allocator,
    width: u32,
    height: u32,
    pixels: []u8,
    cursor_x: u32,
    cursor_y: u32,
    row_height: u32,
    texture: ?*editor_draw.SDL_Texture,
    dirty: bool,

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32) !Atlas {
        const pixel_count = @as(usize, width) * @as(usize, height) * 4;
        const pixels = try allocator.alloc(u8, pixel_count);
        @memset(pixels, 0);

        return .{
            .allocator = allocator,
            .width = width,
            .height = height,
            .pixels = pixels,
            .cursor_x = 1,
            .cursor_y = 1,
            .row_height = 0,
            .texture = null,
            .dirty = true,
        };
    }

    pub fn deinit(self: *Atlas) void {
        if (self.texture) |texture| {
            editor_draw.SDL_DestroyTexture(texture);
        }
        self.allocator.free(self.pixels);
    }

    pub fn textureHandle(self: *Atlas) ?*editor_draw.SDL_Texture {
        return self.texture;
    }

    pub fn allocSlot(self: *Atlas, glyph_w: u32, glyph_h: u32) !GlyphSlot {
        const pad: u32 = 1;
        const slot_w = glyph_w + pad;
        const slot_h = glyph_h + pad;

        if (slot_w + 2 > self.width or slot_h + 2 > self.height) {
            return error.GlyphTooLargeForAtlas;
        }

        if (self.cursor_x + slot_w + 1 > self.width) {
            self.cursor_x = 1;
            self.cursor_y += self.row_height + 1;
            self.row_height = 0;
        }
        if (self.cursor_y + slot_h + 1 > self.height) {
            return error.FontAtlasFull;
        }

        const x = self.cursor_x;
        const y = self.cursor_y;
        self.cursor_x += slot_w;
        self.row_height = @max(self.row_height, slot_h);

        const fw: f32 = @floatFromInt(self.width);
        const fh: f32 = @floatFromInt(self.height);
        const px: f32 = @floatFromInt(x);
        const py: f32 = @floatFromInt(y);
        const gw: f32 = @floatFromInt(glyph_w);
        const gh: f32 = @floatFromInt(glyph_h);
        const half_texel_u: f32 = 0.5 / fw;
        const half_texel_v: f32 = 0.5 / fh;

        return .{
            .u0 = px / fw + half_texel_u,
            .v0 = py / fh + half_texel_v,
            .u1 = (px + gw + @as(f32, @floatFromInt(pad))) / fw - half_texel_u,
            .v1 = (py + gh + @as(f32, @floatFromInt(pad))) / fh - half_texel_v,
            .pixel_x = x,
            .pixel_y = y,
            .pixel_w = glyph_w,
            .pixel_h = glyph_h,
        };
    }

    pub fn writeGlyph(self: *Atlas, slot: GlyphSlot, rgba: []const u8, glyph_w: usize, glyph_h: usize) void {
        std.debug.assert(rgba.len == glyph_w * glyph_h * 4);
        std.debug.assert(glyph_w == slot.pixel_w and glyph_h == slot.pixel_h);

        const atlas_w: usize = @intCast(self.width);
        for (0..glyph_h) |row| {
            const src = row * glyph_w * 4;
            const dst = ((@as(usize, slot.pixel_y) + row) * atlas_w + @as(usize, slot.pixel_x)) * 4;
            @memcpy(self.pixels[dst .. dst + glyph_w * 4], rgba[src .. src + glyph_w * 4]);
        }
        self.dirty = true;
    }

    pub fn ensureTexture(self: *Atlas, renderer: *editor_draw.SDL_Renderer) !void {
        if (self.texture != null) return;
        const texture = editor_draw.SDL_CreateTexture(
            renderer,
            editor_draw.SDL_PIXELFORMAT_RGBA32,
            editor_draw.SDL_TEXTUREACCESS_STATIC,
            @intCast(self.width),
            @intCast(self.height),
        ) orelse return error.SdlTextureCreationFailed;
        errdefer editor_draw.SDL_DestroyTexture(texture);

        if (!editor_draw.SDL_SetTextureBlendMode(texture, editor_draw.SDL_BLENDMODE_BLEND)) {
            return error.SdlTextureBlendFailed;
        }
        if (!editor_draw.SDL_UpdateTexture(texture, null, self.pixels.ptr, @intCast(self.width * 4))) {
            return error.SdlTextureUpdateFailed;
        }
        self.texture = texture;
        self.dirty = false;
    }

    pub fn syncSlot(self: *Atlas, slot: GlyphSlot) !void {
        const texture = self.texture orelse return;
        const rect = sdl.SDL_Rect{
            .x = @intCast(slot.pixel_x),
            .y = @intCast(slot.pixel_y),
            .w = @intCast(slot.pixel_w),
            .h = @intCast(slot.pixel_h),
        };
        const pitch: c_int = @intCast(self.width * 4);
        const offset = (@as(usize, slot.pixel_y) * @as(usize, self.width) + @as(usize, slot.pixel_x)) * 4;
        if (!editor_draw.SDL_UpdateTexture(texture, &rect, self.pixels.ptr + offset, pitch)) {
            return error.SdlTextureUpdateFailed;
        }
    }

    pub fn markClean(self: *Atlas) void {
        self.dirty = false;
    }
};

test "glyph slot UVs inset by half a texel" {
    var atlas = try Atlas.init(std.testing.allocator, 1024, 1024);
    defer atlas.deinit();
    const slot = try atlas.allocSlot(10, 12);
    try std.testing.expectApproxEqAbs(@as(f32, 1.5) / 1024.0, slot.u0, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.5) / 1024.0, slot.v0, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 11.5) / 1024.0, slot.u1, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 13.5) / 1024.0, slot.v1, 0.0001);
}
