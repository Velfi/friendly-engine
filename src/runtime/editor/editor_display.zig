const editor_draw = @import("editor_draw.zig");

pub const Metrics = struct {
    logical_w: f32,
    logical_h: f32,
    pixel_w: u32,
    pixel_h: u32,
    scale: f32,
};

pub fn query(window: *editor_draw.SDL_Window, renderer: *editor_draw.SDL_Renderer) !Metrics {
    var logical_w: c_int = 0;
    var logical_h: c_int = 0;
    if (!editor_draw.SDL_GetWindowSize(window, &logical_w, &logical_h)) return error.SdlWindowSizeFailed;

    var pixel_w: c_int = 0;
    var pixel_h: c_int = 0;
    if (!editor_draw.SDL_GetRenderOutputSize(renderer, &pixel_w, &pixel_h)) return error.SdlRenderOutputSizeFailed;

    const safe_logical_w = @max(1, logical_w);
    const safe_logical_h = @max(1, logical_h);
    const safe_pixel_w = @max(1, pixel_w);
    const safe_pixel_h = @max(1, pixel_h);
    const scale_x = @as(f32, @floatFromInt(safe_pixel_w)) / @as(f32, @floatFromInt(safe_logical_w));
    const scale_y = @as(f32, @floatFromInt(safe_pixel_h)) / @as(f32, @floatFromInt(safe_logical_h));

    return .{
        .logical_w = @floatFromInt(safe_logical_w),
        .logical_h = @floatFromInt(safe_logical_h),
        .pixel_w = @intCast(safe_pixel_w),
        .pixel_h = @intCast(safe_pixel_h),
        .scale = @max(1.0, @min(scale_x, scale_y)),
    };
}

pub fn applySdlScale(renderer: *editor_draw.SDL_Renderer, scale: f32) !void {
    if (!editor_draw.SDL_SetRenderScale(renderer, scale, scale)) return error.SdlRenderScaleFailed;
}

pub fn physicalRect(rect: editor_draw.SDL_FRect, scale: f32) editor_draw.SDL_FRect {
    return .{
        .x = rect.x * scale,
        .y = rect.y * scale,
        .w = rect.w * scale,
        .h = rect.h * scale,
    };
}

test "display metrics convert logical rects to physical pixels" {
    const rect = physicalRect(.{ .x = 10, .y = 20, .w = 300, .h = 200 }, 2);
    try @import("std").testing.expectEqual(@as(f32, 20), rect.x);
    try @import("std").testing.expectEqual(@as(f32, 40), rect.y);
    try @import("std").testing.expectEqual(@as(f32, 600), rect.w);
    try @import("std").testing.expectEqual(@as(f32, 400), rect.h);
}
