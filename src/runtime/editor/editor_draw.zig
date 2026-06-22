const std = @import("std");
const shared = @import("runtime_shared");
const sdl = shared.sdl;
const editor_text_atlas = @import("editor_text_atlas.zig");
const editor_ui_batch = @import("editor_ui_batch.zig");
const rich_text = @import("friendly_engine").modules.core_ui.rich_text;

const ft = @cImport({
    @cInclude("ft2build.h");
    @cInclude("freetype/freetype.h");
});

pub const Color = shared.color.Color;

pub const SDL_INIT_VIDEO = sdl.SDL_INIT_VIDEO;
pub const SDL_INIT_GAMEPAD = sdl.SDL_INIT_GAMEPAD;
pub const SDL_WINDOW_RESIZABLE = sdl.SDL_WINDOW_RESIZABLE;
pub const SDL_WINDOW_HIGH_PIXEL_DENSITY = sdl.SDL_WINDOW_HIGH_PIXEL_DENSITY;
pub const SDL_QUIT = sdl.SDL_QUIT;
pub const SDL_BLENDMODE_BLEND = sdl.SDL_BLENDMODE_BLEND;
pub const SDL_TEXTUREACCESS_STATIC = sdl.SDL_TEXTUREACCESS_STATIC;
pub const SDL_TEXTUREACCESS_STREAMING = sdl.SDL_TEXTUREACCESS_STREAMING;
pub const SDL_TEXTUREACCESS_TARGET = sdl.SDL_TEXTUREACCESS_TARGET;
pub const SDL_PIXELFORMAT_RGBA8888 = sdl.SDL_PIXELFORMAT_RGBA8888;
pub const SDL_PIXELFORMAT_ABGR8888 = sdl.SDL_PIXELFORMAT_ABGR8888;
pub const SDL_PIXELFORMAT_RGBA32 = sdl.SDL_PIXELFORMAT_RGBA32;
pub const SDL_EVENT_KEY_DOWN = sdl.SDL_EVENT_KEY_DOWN;
pub const SDL_EVENT_KEY_UP = sdl.SDL_EVENT_KEY_UP;
pub const SDL_EVENT_TEXT_INPUT = sdl.SDL_EVENT_TEXT_INPUT;
pub const SDL_EVENT_MOUSE_BUTTON_DOWN = sdl.SDL_EVENT_MOUSE_BUTTON_DOWN;
pub const SDL_EVENT_MOUSE_BUTTON_UP = sdl.SDL_EVENT_MOUSE_BUTTON_UP;
pub const SDL_EVENT_MOUSE_MOTION = sdl.SDL_EVENT_MOUSE_MOTION;
pub const SDL_EVENT_MOUSE_WHEEL = sdl.SDL_EVENT_MOUSE_WHEEL;
pub const SDL_EVENT_GAMEPAD_ADDED = sdl.SDL_EVENT_GAMEPAD_ADDED;
pub const SDL_EVENT_GAMEPAD_REMOVED = sdl.SDL_EVENT_GAMEPAD_REMOVED;
pub const SDL_EVENT_GAMEPAD_AXIS_MOTION = sdl.SDL_EVENT_GAMEPAD_AXIS_MOTION;
pub const SDL_EVENT_GAMEPAD_BUTTON_DOWN = sdl.SDL_EVENT_GAMEPAD_BUTTON_DOWN;
pub const SDL_EVENT_GAMEPAD_BUTTON_UP = sdl.SDL_EVENT_GAMEPAD_BUTTON_UP;
pub const SDL_BUTTON_LEFT = sdl.SDL_BUTTON_LEFT;
pub const SDL_BUTTON_MIDDLE = sdl.SDL_BUTTON_MIDDLE;
pub const SDL_BUTTON_RIGHT = sdl.SDL_BUTTON_RIGHT;
pub const SDLK_RETURN = sdl.SDLK_RETURN;
pub const SDLK_ESCAPE = sdl.SDLK_ESCAPE;
pub const SDLK_BACKSPACE = sdl.SDLK_BACKSPACE;
pub const SDLK_TAB = sdl.SDLK_TAB;
pub const SDLK_LEFT = sdl.SDLK_LEFT;
pub const SDLK_RIGHT = sdl.SDLK_RIGHT;
pub const SDLK_UP = sdl.SDLK_UP;
pub const SDLK_DOWN = sdl.SDLK_DOWN;
pub const SDLK_MINUS = sdl.SDLK_MINUS;
pub const SDLK_PERIOD = sdl.SDLK_PERIOD;
pub const SDLK_N = sdl.SDLK_N;
pub const SDLK_O = sdl.SDLK_O;
pub const SDLK_I = sdl.SDLK_I;
pub const SDLK_Q = sdl.SDLK_Q;
pub const SDL_KMOD_CTRL = sdl.SDL_KMOD_CTRL;
pub const SDL_KMOD_GUI = sdl.SDL_KMOD_GUI;
pub const SDL_KMOD_SHIFT = sdl.SDL_KMOD_SHIFT;
pub const SDL_MOUSEWHEEL_NORMAL = sdl.SDL_MOUSEWHEEL_NORMAL;
pub const SDL_MOUSEWHEEL_FLIPPED = sdl.SDL_MOUSEWHEEL_FLIPPED;
pub const SDL_GAMEPAD_AXIS_RIGHTX = sdl.SDL_GAMEPAD_AXIS_RIGHTX;
pub const SDL_GAMEPAD_AXIS_RIGHTY = sdl.SDL_GAMEPAD_AXIS_RIGHTY;
pub const SDL_GAMEPAD_BUTTON_DPAD_UP = sdl.SDL_GAMEPAD_BUTTON_DPAD_UP;
pub const SDL_GAMEPAD_BUTTON_DPAD_DOWN = sdl.SDL_GAMEPAD_BUTTON_DPAD_DOWN;
pub const SDL_GAMEPAD_BUTTON_DPAD_LEFT = sdl.SDL_GAMEPAD_BUTTON_DPAD_LEFT;
pub const SDL_GAMEPAD_BUTTON_DPAD_RIGHT = sdl.SDL_GAMEPAD_BUTTON_DPAD_RIGHT;

pub const SDL_Window = sdl.SDL_Window;
pub const SDL_Renderer = sdl.SDL_Renderer;
pub const SDL_Texture = sdl.SDL_Texture;
pub const SDL_Rect = sdl.SDL_Rect;
pub const SDL_FRect = sdl.SDL_FRect;
pub const SDL_KeyboardEvent = sdl.SDL_KeyboardEvent;
pub const SDL_Keycode = sdl.SDL_Keycode;
pub const SDL_TextInputEvent = sdl.SDL_TextInputEvent;
pub const SDL_MouseButtonEvent = sdl.SDL_MouseButtonEvent;
pub const SDL_MouseMotionEvent = sdl.SDL_MouseMotionEvent;
pub const SDL_MouseWheelEvent = sdl.SDL_MouseWheelEvent;
pub const SDL_Gamepad = sdl.SDL_Gamepad;
pub const SDL_Event = sdl.SDL_Event;
pub const SDL_DialogFileCallback = sdl.SDL_DialogFileCallback;

pub const SDL_Init = sdl.SDL_Init;
pub const SDL_Quit = sdl.SDL_Quit;
pub const SDL_CreateWindow = sdl.SDL_CreateWindow;
pub const SDL_DestroyWindow = sdl.SDL_DestroyWindow;
pub const SDL_CreateRenderer = sdl.SDL_CreateRenderer;
pub const SDL_CreateGPURenderer = sdl.SDL_CreateGPURenderer;
pub const SDL_DestroyRenderer = sdl.SDL_DestroyRenderer;
pub const SDL_SetRenderDrawColor = sdl.SDL_SetRenderDrawColor;
pub const SDL_RenderClear = sdl.SDL_RenderClear;
pub const SDL_RenderFillRect = sdl.SDL_RenderFillRect;
pub const SDL_RenderRect = sdl.SDL_RenderRect;
pub const SDL_RenderLine = sdl.SDL_RenderLine;
pub const SDL_RenderPoint = sdl.SDL_RenderPoint;
pub const SDL_RenderPresent = sdl.SDL_RenderPresent;
pub const SDL_SetRenderClipRect = sdl.SDL_SetRenderClipRect;
pub const SDL_GetRenderOutputSize = sdl.SDL_GetRenderOutputSize;
pub const SDL_SetRenderScale = sdl.SDL_SetRenderScale;
pub const SDL_GetRenderScale = sdl.SDL_GetRenderScale;
pub const SDL_SetRenderTarget = sdl.SDL_SetRenderTarget;
pub const SDL_CreateTexture = sdl.SDL_CreateTexture;
pub const SDL_CreateTextureWithProperties = sdl.SDL_CreateTextureWithProperties;
pub const SDL_CreateProperties = sdl.SDL_CreateProperties;
pub const SDL_DestroyProperties = sdl.SDL_DestroyProperties;
pub const SDL_SetPointerProperty = sdl.SDL_SetPointerProperty;
pub const SDL_SetNumberProperty = sdl.SDL_SetNumberProperty;
pub const SDL_PROP_TEXTURE_CREATE_FORMAT_NUMBER = sdl.SDL_PROP_TEXTURE_CREATE_FORMAT_NUMBER;
pub const SDL_PROP_TEXTURE_CREATE_ACCESS_NUMBER = sdl.SDL_PROP_TEXTURE_CREATE_ACCESS_NUMBER;
pub const SDL_PROP_TEXTURE_CREATE_WIDTH_NUMBER = sdl.SDL_PROP_TEXTURE_CREATE_WIDTH_NUMBER;
pub const SDL_PROP_TEXTURE_CREATE_HEIGHT_NUMBER = sdl.SDL_PROP_TEXTURE_CREATE_HEIGHT_NUMBER;
pub const SDL_PROP_TEXTURE_CREATE_GPU_TEXTURE_POINTER = sdl.SDL_PROP_TEXTURE_CREATE_GPU_TEXTURE_POINTER;
pub const SDL_SetTextureBlendMode = sdl.SDL_SetTextureBlendMode;
pub const SDL_SetTextureColorMod = sdl.SDL_SetTextureColorMod;
pub const SDL_SetTextureAlphaMod = sdl.SDL_SetTextureAlphaMod;
pub const SDL_UpdateTexture = sdl.SDL_UpdateTexture;
pub const SDL_RenderTexture = sdl.SDL_RenderTexture;
pub const SDL_RenderGeometry = sdl.SDL_RenderGeometry;
pub const SDL_RenderReadPixels = sdl.SDL_RenderReadPixels;
pub const SDL_DestroyTexture = sdl.SDL_DestroyTexture;
pub const SDL_DestroySurface = sdl.SDL_DestroySurface;
pub const SDL_SavePNG = sdl.SDL_SavePNG;
pub const SDL_Delay = sdl.SDL_Delay;
pub const SDL_GetError = sdl.SDL_GetError;
pub const SDL_PollEvent = sdl.SDL_PollEvent;
pub const SDL_OpenGamepad = sdl.SDL_OpenGamepad;
pub const SDL_CloseGamepad = sdl.SDL_CloseGamepad;
pub const SDL_StartTextInput = sdl.SDL_StartTextInput;
pub const SDL_StopTextInput = sdl.SDL_StopTextInput;
pub const SDL_ShowOpenFolderDialog = sdl.SDL_ShowOpenFolderDialog;
pub const SDL_ShowOpenFileDialog = sdl.SDL_ShowOpenFileDialog;
pub const SDL_ShowSaveFileDialog = sdl.SDL_ShowSaveFileDialog;
pub const SDL_DialogFileFilter = sdl.SDL_DialogFileFilter;
pub const SDL_GetWindowSize = sdl.SDL_GetWindowSize;

pub fn pointInRect(x: f32, y: f32, rect: SDL_FRect) bool {
    return x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h;
}

pub fn drawPanel(renderer: *SDL_Renderer, rect: SDL_FRect, fill_color: Color, border_color: Color) !void {
    if (!SDL_SetRenderDrawColor(renderer, fill_color.r, fill_color.g, fill_color.b, fill_color.a)) {
        return error.SdlColorSetFailed;
    }
    if (!SDL_RenderFillRect(renderer, &rect)) {
        return error.SdlFillRectFailed;
    }
    if (!SDL_SetRenderDrawColor(renderer, border_color.r, border_color.g, border_color.b, border_color.a)) {
        return error.SdlColorSetFailed;
    }
    if (!SDL_RenderRect(renderer, &rect)) {
        return error.SdlRectFailed;
    }
}

pub const TextRenderer = struct {
    allocator: std.mem.Allocator,
    renderer: *SDL_Renderer,
    library: ft.FT_Library,
    face: ft.FT_Face,
    font_bytes: []u8,
    font_unit_scale: f32,
    pixel_size: u32,
    atlas: editor_text_atlas.Atlas,
    glyph_cache: std.AutoHashMap(u32, GlyphCacheEntry),

    const GlyphCacheEntry = struct {
        slot: ?editor_text_atlas.GlyphSlot,
        width: f32,
        height: f32,
        bearing_left: f32,
        bearing_top: f32,
        advance_x: f32,
    };

    const ShapedGlyph = struct {
        glyph_id: u32,
        x_advance: f32,
        y_advance: f32,
        x_offset: f32,
        y_offset: f32,
    };

    pub fn init(allocator: std.mem.Allocator, io: std.Io, renderer: *SDL_Renderer, font_path: []const u8, pixel_size: u32) !TextRenderer {
        var library: ft.FT_Library = undefined;
        if (ft.FT_Init_FreeType(&library) != 0) {
            return error.FreeTypeInitFailed;
        }
        errdefer _ = ft.FT_Done_FreeType(library);

        const font_bytes = try readFontBytes(allocator, io, font_path);
        errdefer allocator.free(font_bytes);

        const font_path_z = try allocator.dupeZ(u8, font_path);
        defer allocator.free(font_path_z);

        var face: ft.FT_Face = undefined;
        if (ft.FT_New_Face(library, font_path_z.ptr, 0, &face) != 0) {
            return error.FreeTypeFaceInitFailed;
        }
        errdefer _ = ft.FT_Done_Face(face);

        if (ft.FT_Set_Pixel_Sizes(face, 0, pixel_size * font_oversample) != 0) {
            return error.FreeTypeSizeSetFailed;
        }

        var self = TextRenderer{
            .allocator = allocator,
            .renderer = renderer,
            .library = library,
            .face = face,
            .font_bytes = font_bytes,
            .font_unit_scale = @as(f32, @floatFromInt(pixel_size)) / @as(f32, @floatFromInt(face.*.units_per_EM)),
            .pixel_size = pixel_size,
            .atlas = try editor_text_atlas.Atlas.init(allocator, atlas_size, atlas_size),
            .glyph_cache = std.AutoHashMap(u32, GlyphCacheEntry).init(allocator),
        };
        errdefer self.deinit();

        var codepoint: u32 = 32;
        while (codepoint <= 126) : (codepoint += 1) {
            const glyph_id = ft.FT_Get_Char_Index(self.face, codepoint);
            if (glyph_id != 0) _ = try self.getOrCreateGlyph(@intCast(glyph_id));
        }
        try self.atlas.ensureTexture(renderer);
        return self;
    }

    pub fn deinit(self: *TextRenderer) void {
        self.glyph_cache.deinit();
        self.atlas.deinit();
        self.allocator.free(self.font_bytes);
        _ = ft.FT_Done_Face(self.face);
        _ = ft.FT_Done_FreeType(self.library);
    }

    pub fn draw(self: *TextRenderer, renderer: *SDL_Renderer, batch: *editor_ui_batch.UiDrawBatch, text: []const u8, x: f32, y: f32, color: Color) !void {
        try self.drawInRect(renderer, batch, text, x, y, null, color);
    }

    pub fn measureText(self: *TextRenderer, text: []const u8) !f32 {
        return self.measureRichText(&.{rich_text.plain(text)});
    }

    pub fn measureRichText(self: *TextRenderer, spans: []const rich_text.Span) !f32 {
        var width: f32 = 0;
        var line_width: f32 = 0;
        for (spans) |span| {
            var start: usize = 0;
            var i: usize = 0;
            while (i <= span.text.len) : (i += 1) {
                if (i < span.text.len and span.text[i] != '\n') continue;
                if (i > start) {
                    const shaped = try self.shapeRun(span.text[start..i], span.style);
                    defer self.allocator.free(shaped);
                    for (shaped) |glyph| {
                        _ = try self.getOrCreateGlyph(glyph.glyph_id);
                        line_width += styledShapedAdvance(glyph, span.style);
                    }
                }
                if (i < span.text.len) {
                    width = @max(width, line_width);
                    line_width = 0;
                    start = i + 1;
                }
            }
        }
        return @max(width, line_width);
    }

    pub fn atlasDirty(self: *const TextRenderer) bool {
        return self.atlas.dirty;
    }

    pub fn markAtlasClean(self: *TextRenderer) void {
        self.atlas.markClean();
    }

    pub fn appendOverlayQuads(
        self: *TextRenderer,
        text: []const u8,
        x: f32,
        y: f32,
        max_width: ?f32,
        color: Color,
        gpu_texture: *shared.sdl_gpu.SDL_GPUTexture,
        out: *std.ArrayList(shared.gpu_scene.OverlayQuad),
        allocator: std.mem.Allocator,
    ) !void {
        try self.appendRichOverlayQuads(&.{rich_text.plain(text)}, x, y, max_width, color, gpu_texture, out, allocator);
    }

    pub fn appendRichOverlayQuads(
        self: *TextRenderer,
        spans: []const rich_text.Span,
        x: f32,
        y: f32,
        max_width: ?f32,
        default_color: Color,
        gpu_texture: *shared.sdl_gpu.SDL_GPUTexture,
        out: *std.ArrayList(shared.gpu_scene.OverlayQuad),
        allocator: std.mem.Allocator,
    ) !void {
        var pen_x = x;
        var baseline_y = y + @as(f32, @floatFromInt(self.pixel_size));
        const max_x: ?f32 = if (max_width) |width| x + @max(0, width) else null;

        for (spans) |span| {
            const color = spanColor(span.style, default_color);
            var deco_start_x = pen_x;
            var deco_baseline_y = baseline_y;
            var start: usize = 0;
            var i: usize = 0;
            while (i <= span.text.len) : (i += 1) {
                if (i < span.text.len and span.text[i] != '\n') continue;
                if (i > start) {
                    const shaped = try self.shapeRun(span.text[start..i], span.style);
                    defer self.allocator.free(shaped);
                    try self.appendShapedOverlayRun(out, allocator, shaped, &pen_x, baseline_y, max_x, color, span.style, gpu_texture);
                }
                if (i < span.text.len) {
                    try appendDecorations(out, allocator, deco_start_x, pen_x, deco_baseline_y, color, span.style);
                    pen_x = x;
                    baseline_y += @as(f32, @floatFromInt(self.pixel_size + 4));
                    deco_start_x = pen_x;
                    deco_baseline_y = baseline_y;
                    start = i + 1;
                }
            }
            try appendDecorations(out, allocator, deco_start_x, pen_x, deco_baseline_y, color, span.style);
        }
    }

    fn appendGlyphTextureQuad(
        _: *TextRenderer,
        out: *std.ArrayList(shared.gpu_scene.OverlayQuad),
        allocator: std.mem.Allocator,
        slot: editor_text_atlas.GlyphSlot,
        x: f32,
        y: f32,
        draw_w: f32,
        color: Color,
        style: rich_text.TextStyle,
        gpu_texture: *shared.sdl_gpu.SDL_GPUTexture,
    ) !void {
        const full_w = scaleFontMetric(@floatFromInt(slot.pixel_w));
        const full_h = scaleFontMetric(@floatFromInt(slot.pixel_h));
        const visible_w = @max(0, @min(draw_w, full_w));
        if (visible_w <= 0 or full_h <= 0) return;

        const skew = if (style.italic) @min(4.0, full_h * 0.18) else 0.0;
        try out.append(allocator, .{
            .rect = .{ x, y, visible_w, full_h },
            .uv = .{ slot.u0, slot.v0, clippedU1(slot, visible_w, full_w), slot.v1 },
            .skew_x = skew,
            .gpu_texture = @ptrCast(gpu_texture),
            .color = color,
        });
    }

    pub fn drawInRect(
        self: *TextRenderer,
        renderer: *SDL_Renderer,
        batch: *editor_ui_batch.UiDrawBatch,
        text: []const u8,
        x: f32,
        y: f32,
        max_width: ?f32,
        color: Color,
    ) !void {
        try self.drawRichInRect(renderer, batch, &.{rich_text.plain(text)}, x, y, max_width, color);
    }

    pub fn drawRichInRect(
        self: *TextRenderer,
        renderer: *SDL_Renderer,
        batch: *editor_ui_batch.UiDrawBatch,
        spans: []const rich_text.Span,
        x: f32,
        y: f32,
        max_width: ?f32,
        default_color: Color,
    ) !void {
        _ = batch;
        const atlas_texture = self.atlas.textureHandle() orelse return error.FontAtlasTextureMissing;

        var pen_x = x;
        var baseline_y = y + @as(f32, @floatFromInt(self.pixel_size));
        const max_x: ?f32 = if (max_width) |width| x + @max(0, width) else null;

        for (spans) |span| {
            const color = spanColor(span.style, default_color);
            if (!SDL_SetTextureColorMod(atlas_texture, color.r, color.g, color.b)) {
                return error.SdlTextureColorModFailed;
            }
            if (!SDL_SetTextureAlphaMod(atlas_texture, color.a)) {
                return error.SdlTextureAlphaModFailed;
            }
            var deco_start_x = pen_x;
            var deco_baseline_y = baseline_y;
            var start: usize = 0;
            var i: usize = 0;
            while (i <= span.text.len) : (i += 1) {
                if (i < span.text.len and span.text[i] != '\n') continue;
                if (i > start) {
                    const shaped = try self.shapeRun(span.text[start..i], span.style);
                    defer self.allocator.free(shaped);
                    try self.drawShapedRun(renderer, atlas_texture, shaped, &pen_x, baseline_y, max_x, span.style);
                }
                if (i < span.text.len) {
                    try drawDecorations(renderer, deco_start_x, pen_x, deco_baseline_y, color, span.style);
                    pen_x = x;
                    baseline_y += @as(f32, @floatFromInt(self.pixel_size + 4));
                    deco_start_x = pen_x;
                    deco_baseline_y = baseline_y;
                    start = i + 1;
                }
            }
            try drawDecorations(renderer, deco_start_x, pen_x, deco_baseline_y, color, span.style);
        }
    }

    fn shapeRun(self: *TextRenderer, text: []const u8, style: rich_text.TextStyle) ![]ShapedGlyph {
        const raw = try shared.text_shape.shapeUtf8(self.allocator, self.font_bytes, text);
        defer self.allocator.free(raw);
        const shaped = try self.allocator.alloc(ShapedGlyph, raw.len);
        const monospace_advance = if (style.monospace) @as(f32, @floatFromInt(self.pixel_size)) * 0.62 else 0;
        for (raw, shaped) |source, *dest| {
            dest.* = .{
                .glyph_id = source.glyph_id,
                .x_advance = if (style.monospace) monospace_advance else self.scaleFontUnits(source.x_advance),
                .y_advance = self.scaleFontUnits(source.y_advance),
                .x_offset = self.scaleFontUnits(source.x_offset),
                .y_offset = self.scaleFontUnits(source.y_offset),
            };
        }
        return shaped;
    }

    fn appendShapedOverlayRun(
        self: *TextRenderer,
        out: *std.ArrayList(shared.gpu_scene.OverlayQuad),
        allocator: std.mem.Allocator,
        shaped: []const ShapedGlyph,
        pen_x: *f32,
        baseline_y: f32,
        max_x: ?f32,
        color: Color,
        style: rich_text.TextStyle,
        gpu_texture: *shared.sdl_gpu.SDL_GPUTexture,
    ) !void {
        for (shaped) |glyph| {
            const glyph_entry = try self.getOrCreateGlyph(glyph.glyph_id);
            if (max_x) |limit| {
                if (pen_x.* >= limit) break;
            }
            if (glyph_entry.slot) |slot| {
                const dst_x = pen_x.* + glyph.x_offset + glyph_entry.bearing_left;
                const dst_y = baseline_y - glyph.y_offset - glyph_entry.bearing_top;
                var draw_w = glyph_entry.width;
                if (max_x) |limit| {
                    if (dst_x >= limit) {
                        pen_x.* += styledShapedAdvance(glyph, style);
                        continue;
                    }
                    draw_w = @min(draw_w, limit - dst_x);
                }
                if (draw_w > 0) {
                    try self.appendGlyphTextureQuad(out, allocator, slot, dst_x, dst_y, draw_w, color, style, gpu_texture);
                    if (style.bold) {
                        try self.appendGlyphTextureQuad(out, allocator, slot, dst_x + 1.0, dst_y, draw_w, color, style, gpu_texture);
                    }
                }
            }
            pen_x.* += styledShapedAdvance(glyph, style);
        }
    }

    fn drawShapedRun(
        self: *TextRenderer,
        renderer: *SDL_Renderer,
        atlas_texture: *SDL_Texture,
        shaped: []const ShapedGlyph,
        pen_x: *f32,
        baseline_y: f32,
        max_x: ?f32,
        style: rich_text.TextStyle,
    ) !void {
        for (shaped) |glyph| {
            const glyph_entry = try self.getOrCreateGlyph(glyph.glyph_id);
            if (max_x) |limit| {
                if (pen_x.* >= limit) break;
            }
            if (glyph_entry.slot) |slot| {
                var dst = SDL_FRect{
                    .x = pen_x.* + glyph.x_offset + glyph_entry.bearing_left,
                    .y = baseline_y - glyph.y_offset - glyph_entry.bearing_top,
                    .w = glyph_entry.width,
                    .h = glyph_entry.height,
                };
                var src = SDL_FRect{
                    .x = @floatFromInt(slot.pixel_x),
                    .y = @floatFromInt(slot.pixel_y),
                    .w = @floatFromInt(slot.pixel_w),
                    .h = @floatFromInt(slot.pixel_h),
                };
                if (max_x) |limit| {
                    if (dst.x >= limit) {
                        pen_x.* += styledShapedAdvance(glyph, style);
                        continue;
                    }
                    if (dst.x + dst.w > limit) {
                        const visible_w = limit - dst.x;
                        src.w *= visible_w / dst.w;
                        dst.w = visible_w;
                    }
                }
                if (dst.w > 0) {
                    const uv = .{ slot.u0, slot.v0, clippedU1(slot, dst.w, glyph_entry.width), slot.v1 };
                    try drawGlyphTexture(renderer, atlas_texture, src, dst, uv, style);
                    if (style.bold) {
                        var bold_dst = dst;
                        bold_dst.x += 1.0;
                        try drawGlyphTexture(renderer, atlas_texture, src, bold_dst, uv, style);
                    }
                }
            }
            pen_x.* += styledShapedAdvance(glyph, style);
        }
    }

    fn getOrCreateGlyph(self: *TextRenderer, glyph_id: u32) !GlyphCacheEntry {
        if (self.glyph_cache.get(glyph_id)) |entry| {
            return entry;
        }

        if (ft.FT_Load_Glyph(self.face, glyph_id, ft.FT_LOAD_RENDER | ft.FT_LOAD_TARGET_NORMAL) != 0) {
            const empty: GlyphCacheEntry = .{
                .slot = null,
                .width = 0,
                .height = 0,
                .bearing_left = 0,
                .bearing_top = 0,
                .advance_x = 0,
            };
            try self.glyph_cache.put(glyph_id, empty);
            return empty;
        }

        const glyph = self.face.*.glyph;
        const bitmap = glyph.*.bitmap;
        const glyph_w: usize = @intCast(bitmap.width);
        const glyph_h: usize = @intCast(bitmap.rows);
        var slot: ?editor_text_atlas.GlyphSlot = null;

        if (glyph_w > 0 and glyph_h > 0 and bitmap.buffer != null) {
            const rgba_len = glyph_w * glyph_h * 4;
            var rgba_pixels = try self.allocator.alloc(u8, rgba_len);
            defer self.allocator.free(rgba_pixels);

            for (0..glyph_h) |row| {
                for (0..glyph_w) |col| {
                    const color = glyphBitmapPixel(bitmap, row, col);
                    const px = (row * glyph_w + col) * 4;
                    rgba_pixels[px] = color.r;
                    rgba_pixels[px + 1] = color.g;
                    rgba_pixels[px + 2] = color.b;
                    rgba_pixels[px + 3] = color.a;
                }
            }

            const allocated = try self.atlas.allocSlot(@intCast(glyph_w), @intCast(glyph_h));
            self.atlas.writeGlyph(allocated, rgba_pixels, glyph_w, glyph_h);
            if (self.atlas.textureHandle() != null) {
                try self.atlas.syncSlot(allocated);
            }
            slot = allocated;
        }

        const entry: GlyphCacheEntry = .{
            .slot = slot,
            .width = scaleFontMetric(@floatFromInt(glyph_w)),
            .height = scaleFontMetric(@floatFromInt(glyph_h)),
            .bearing_left = scaleFontMetric(@floatFromInt(glyph.*.bitmap_left)),
            .bearing_top = scaleFontMetric(@floatFromInt(glyph.*.bitmap_top)),
            .advance_x = scaleFontMetric(@floatFromInt(@divTrunc(glyph.*.advance.x, 64))),
        };
        try self.glyph_cache.put(glyph_id, entry);
        return entry;
    }

    fn scaleFontUnits(self: *const TextRenderer, value: i32) f32 {
        return @as(f32, @floatFromInt(value)) * self.font_unit_scale;
    }

    const atlas_size: u32 = 1024;
};

const font_oversample: u32 = 3;

fn readFontBytes(allocator: std.mem.Allocator, io: std.Io, font_path: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(font_path)) {
        const dir_path = std.fs.path.dirname(font_path) orelse return error.InvalidFontPath;
        const file_name = std.fs.path.basename(font_path);
        var dir = try std.Io.Dir.openDirAbsolute(io, dir_path, .{});
        defer dir.close(io);
        return try dir.readFileAlloc(io, file_name, allocator, .limited(16 * 1024 * 1024));
    }

    return try std.Io.Dir.cwd().readFileAlloc(io, font_path, allocator, .limited(16 * 1024 * 1024));
}

fn scaleFontMetric(value: f32) f32 {
    return value / @as(f32, @floatFromInt(font_oversample));
}

fn spanColor(style: rich_text.TextStyle, default_color: Color) Color {
    if (style.color) |color| {
        return .{ .r = color.r, .g = color.g, .b = color.b, .a = color.a };
    }
    return default_color;
}

fn glyphBitmapPixel(bitmap: ft.FT_Bitmap, row: usize, col: usize) Color {
    const pitch_abs: usize = @intCast(if (bitmap.pitch < 0) -bitmap.pitch else bitmap.pitch);
    const src_row: usize = if (bitmap.pitch < 0) (@as(usize, @intCast(bitmap.rows)) - 1 - row) else row;
    const bitmap_data = bitmap.buffer.?;
    return switch (bitmap.pixel_mode) {
        ft.FT_PIXEL_MODE_GRAY => blk: {
            const alpha = bitmap_data[src_row * pitch_abs + col];
            break :blk .{ .r = 255, .g = 255, .b = 255, .a = alpha };
        },
        ft.FT_PIXEL_MODE_BGRA => blk: {
            const px = src_row * pitch_abs + col * 4;
            break :blk .{
                .r = bitmap_data[px + 2],
                .g = bitmap_data[px + 1],
                .b = bitmap_data[px],
                .a = bitmap_data[px + 3],
            };
        },
        else => @panic("unsupported FreeType glyph bitmap pixel mode"),
    };
}

fn styledShapedAdvance(glyph: TextRenderer.ShapedGlyph, style: rich_text.TextStyle) f32 {
    const bold_extra: f32 = if (style.bold) 1.0 else 0.0;
    return glyph.x_advance + bold_extra;
}

fn clippedU1(slot: editor_text_atlas.GlyphSlot, draw_w: f32, full_w: f32) f32 {
    if (full_w <= 0) return slot.u1;
    return slot.u0 + (slot.u1 - slot.u0) * @min(1.0, draw_w / full_w);
}

fn appendDecorations(
    out: *std.ArrayList(shared.gpu_scene.OverlayQuad),
    allocator: std.mem.Allocator,
    start_x: f32,
    end_x: f32,
    baseline_y: f32,
    color: Color,
    style: rich_text.TextStyle,
) !void {
    const width = end_x - start_x;
    if (width <= 0) return;
    if (style.underline) {
        try out.append(allocator, .{ .rect = .{ start_x, baseline_y + 2.0, width, 1.0 }, .color = color });
    }
    if (style.strikethrough) {
        try out.append(allocator, .{ .rect = .{ start_x, baseline_y - 8.0, width, 1.0 }, .color = color });
    }
}

fn drawDecorations(renderer: *SDL_Renderer, start_x: f32, end_x: f32, baseline_y: f32, color: Color, style: rich_text.TextStyle) !void {
    const width = end_x - start_x;
    if (width <= 0) return;
    if (!SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a)) return error.SdlColorSetFailed;
    if (style.underline) {
        var rect = SDL_FRect{ .x = start_x, .y = baseline_y + 2.0, .w = width, .h = 1.0 };
        if (!SDL_RenderFillRect(renderer, &rect)) return error.SdlFillRectFailed;
    }
    if (style.strikethrough) {
        var rect = SDL_FRect{ .x = start_x, .y = baseline_y - 8.0, .w = width, .h = 1.0 };
        if (!SDL_RenderFillRect(renderer, &rect)) return error.SdlFillRectFailed;
    }
}

fn drawGlyphTexture(renderer: *SDL_Renderer, texture: *SDL_Texture, src: SDL_FRect, dst: SDL_FRect, uv: [4]f32, style: rich_text.TextStyle) !void {
    if (!style.italic) {
        var src_copy = src;
        var dst_copy = dst;
        if (!SDL_RenderTexture(renderer, texture, &src_copy, &dst_copy)) return error.SdlTextureRenderFailed;
        return;
    }

    const skew = @min(4.0, dst.h * 0.18);
    const white = sdl.SDL_FColor{ .r = 1, .g = 1, .b = 1, .a = 1 };
    var vertices = [_]sdl.SDL_Vertex{
        vertex(dst.x + skew, dst.y, uv[0], uv[1], white),
        vertex(dst.x + dst.w + skew, dst.y, uv[2], uv[1], white),
        vertex(dst.x + dst.w, dst.y + dst.h, uv[2], uv[3], white),
        vertex(dst.x, dst.y + dst.h, uv[0], uv[3], white),
    };
    var indices = [_]c_int{ 0, 1, 2, 0, 2, 3 };
    if (!SDL_RenderGeometry(renderer, texture, &vertices, vertices.len, &indices, indices.len)) {
        return error.SdlRenderGeometryFailed;
    }
}

fn vertex(x: f32, y: f32, u: f32, v: f32, color: sdl.SDL_FColor) sdl.SDL_Vertex {
    return .{
        .position = .{ .x = x, .y = y },
        .color = color,
        .tex_coord = .{ .x = u, .y = v },
    };
}

pub const required_ui_font_path = "third_party/fonts/AtkinsonHyperlegible-Regular.ttf";

pub fn initRequiredTextRenderer(allocator: std.mem.Allocator, io: std.Io, sdl_renderer: *SDL_Renderer, font_path: []const u8, pixel_size: u32) !TextRenderer {
    return TextRenderer.init(allocator, io, sdl_renderer, font_path, pixel_size);
}

pub fn sdlError() []const u8 {
    return sdl.errorMessage();
}

pub fn createTextureFromGpuTexture(
    renderer: *SDL_Renderer,
    gpu_texture: *sdl.SDL_GPUTexture,
    width: u32,
    height: u32,
) !*SDL_Texture {
    const props = SDL_CreateProperties();
    if (props == 0) return error.SdlPropertiesFailed;
    defer SDL_DestroyProperties(props);

    if (!SDL_SetNumberProperty(props, SDL_PROP_TEXTURE_CREATE_FORMAT_NUMBER, @intCast(SDL_PIXELFORMAT_RGBA32))) {
        return error.SdlPropertySetFailed;
    }
    if (!SDL_SetNumberProperty(props, SDL_PROP_TEXTURE_CREATE_ACCESS_NUMBER, SDL_TEXTUREACCESS_STATIC)) {
        return error.SdlPropertySetFailed;
    }
    if (!SDL_SetNumberProperty(props, SDL_PROP_TEXTURE_CREATE_WIDTH_NUMBER, @intCast(width))) {
        return error.SdlPropertySetFailed;
    }
    if (!SDL_SetNumberProperty(props, SDL_PROP_TEXTURE_CREATE_HEIGHT_NUMBER, @intCast(height))) {
        return error.SdlPropertySetFailed;
    }
    if (!SDL_SetPointerProperty(props, SDL_PROP_TEXTURE_CREATE_GPU_TEXTURE_POINTER, gpu_texture)) {
        return error.SdlPropertySetFailed;
    }

    const texture = SDL_CreateTextureWithProperties(renderer, props) orelse return error.SdlTextureCreationFailed;
    if (!SDL_SetTextureBlendMode(texture, SDL_BLENDMODE_BLEND)) {
        SDL_DestroyTexture(texture);
        return error.SdlTextureBlendFailed;
    }
    return texture;
}
