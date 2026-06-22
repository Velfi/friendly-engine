const std = @import("std");
const shared = @import("runtime_shared");
const editor_draw = @import("editor_draw.zig");

const sdl = shared.sdl;
const Color = editor_draw.Color;

pub const UiDrawBatch = struct {
    allocator: std.mem.Allocator,
    vertices: std.ArrayList(sdl.SDL_Vertex),
    indices: std.ArrayList(c_int),
    active_texture: ?*editor_draw.SDL_Texture = null,

    pub fn init(allocator: std.mem.Allocator) UiDrawBatch {
        return .{
            .allocator = allocator,
            .vertices = .empty,
            .indices = .empty,
        };
    }

    pub fn deinit(self: *UiDrawBatch) void {
        self.vertices.deinit(self.allocator);
        self.indices.deinit(self.allocator);
    }

    pub fn reset(self: *UiDrawBatch) void {
        self.vertices.clearRetainingCapacity();
        self.indices.clearRetainingCapacity();
        self.active_texture = null;
    }

    pub fn flush(self: *UiDrawBatch, renderer: *editor_draw.SDL_Renderer) !void {
        if (self.indices.items.len == 0) return;
        if (!sdl.SDL_RenderGeometry(
            renderer,
            self.active_texture,
            self.vertices.items.ptr,
            @intCast(self.vertices.items.len),
            self.indices.items.ptr,
            @intCast(self.indices.items.len),
        )) {
            return error.SdlRenderGeometryFailed;
        }
        self.reset();
    }

    pub fn addSolidRect(self: *UiDrawBatch, renderer: *editor_draw.SDL_Renderer, rect: editor_draw.SDL_FRect, color: Color) !void {
        if (self.active_texture != null) try self.flush(renderer);
        try self.appendQuad(rect, .{ .u0 = 0, .v0 = 0, .u1 = 0, .v1 = 0 }, color);
    }

    pub fn addTexturedRect(
        self: *UiDrawBatch,
        renderer: *editor_draw.SDL_Renderer,
        texture: *editor_draw.SDL_Texture,
        dst: editor_draw.SDL_FRect,
        uv: UvRect,
        color: Color,
    ) !void {
        if (self.active_texture != texture) {
            try self.flush(renderer);
            self.active_texture = texture;
        }
        try self.appendQuad(dst, uv, color);
    }

    const UvRect = struct {
        u0: f32,
        v0: f32,
        u1: f32,
        v1: f32,
    };

    fn appendQuad(self: *UiDrawBatch, rect: editor_draw.SDL_FRect, uv: UvRect, color: Color) !void {
        if (self.vertices.items.len + 4 > max_vertices) return error.UiDrawBatchFull;
        if (self.indices.items.len + 6 > max_indices) return error.UiDrawBatchFull;

        const fc = toFColor(color);
        const base: u32 = @intCast(self.vertices.items.len);
        try self.vertices.appendSlice(self.allocator, &.{
            vertex(rect.x, rect.y, uv.u0, uv.v0, fc),
            vertex(rect.x + rect.w, rect.y, uv.u1, uv.v0, fc),
            vertex(rect.x + rect.w, rect.y + rect.h, uv.u1, uv.v1, fc),
            vertex(rect.x, rect.y + rect.h, uv.u0, uv.v1, fc),
        });
        try self.indices.appendSlice(self.allocator, &.{
            @intCast(base + 0),
            @intCast(base + 1),
            @intCast(base + 2),
            @intCast(base + 0),
            @intCast(base + 2),
            @intCast(base + 3),
        });
    }

    fn vertex(x: f32, y: f32, u: f32, v: f32, color: sdl.SDL_FColor) sdl.SDL_Vertex {
        return .{
            .position = .{ .x = x, .y = y },
            .color = color,
            .tex_coord = .{ .x = u, .y = v },
        };
    }

    fn toFColor(color: Color) sdl.SDL_FColor {
        return .{
            .r = @as(f32, @floatFromInt(color.r)) / 255.0,
            .g = @as(f32, @floatFromInt(color.g)) / 255.0,
            .b = @as(f32, @floatFromInt(color.b)) / 255.0,
            .a = @as(f32, @floatFromInt(color.a)) / 255.0,
        };
    }

    const max_vertices = 16_384;
    const max_indices = 24_576;
};

test "ui draw batch packs two solid rects into one draw" {
    var batch = UiDrawBatch.init(std.testing.allocator);
    defer batch.deinit();

    const color = Color{ .r = 10, .g = 20, .b = 30, .a = 255 };
    try batch.addSolidRect(undefined, .{ .x = 0, .y = 0, .w = 10, .h = 10 }, color);
    try batch.addSolidRect(undefined, .{ .x = 20, .y = 0, .w = 10, .h = 10 }, color);
    try std.testing.expectEqual(@as(usize, 8), batch.vertices.items.len);
    try std.testing.expectEqual(@as(usize, 12), batch.indices.items.len);
}
