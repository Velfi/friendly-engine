const std = @import("std");
const editor_core_ui = @import("editor_core_ui.zig");
const editor_commands = @import("editor_commands.zig");
const editor_display = @import("editor_display.zig");
const editor_draw = @import("editor_draw.zig");
const editor_viewport_gpu = @import("editor_viewport_gpu.zig");
const pm_apply_input = @import("pm_apply_input.zig");
const pm_state = @import("pm_state.zig");
const pm_ui_build = @import("pm_ui_build.zig");
const shared = @import("runtime_shared");

const SDL_Renderer = editor_draw.SDL_Renderer;
const SDL_SetRenderDrawColor = editor_draw.SDL_SetRenderDrawColor;
const SDL_RenderClear = editor_draw.SDL_RenderClear;
const SDL_RenderPresent = editor_draw.SDL_RenderPresent;
const TextRenderer = editor_draw.TextRenderer;

pub fn renderEditorUi(
    allocator: std.mem.Allocator,
    io: std.Io,
    renderer: *SDL_Renderer,
    text_renderer: *TextRenderer,
    state: *pm_state.ProjectManagerState,
    host: *editor_core_ui.Host,
    viewport_gpu: ?*editor_viewport_gpu.EditorViewportGpu,
    display: editor_display.Metrics,
    pending_screenshot: *?editor_commands.PendingScreenshot,
) !bool {
    const window_w = display.logical_w;
    const window_h = display.logical_h;

    host.setFrameBounds(.{ .x = 0, .y = 0, .w = window_w, .h = window_h });
    try pm_ui_build.build(&host.ui, state, window_w, window_h);

    const use_gpu_ui = viewport_gpu != null and viewport_gpu.?.use_gpu;
    if (use_gpu_ui) {
        const gpu = &viewport_gpu.?.gpu_renderer.?;
        try gpu.beginFrame(display.pixel_w, display.pixel_h, editor_bg);
        try host.drawGpu(gpu, text_renderer, display.scale);
        if (pending_screenshot.* != null) {
            try editor_commands.completePendingScreenshot(allocator, io, renderer, gpu, true, pending_screenshot);
        } else {
            try gpu.endFrame();
        }
    } else {
        try editor_display.applySdlScale(renderer, display.scale);
        if (!SDL_SetRenderDrawColor(renderer, editor_bg.r, editor_bg.g, editor_bg.b, editor_bg.a)) return error.SdlColorSetFailed;
        if (!SDL_RenderClear(renderer)) return error.SdlClearFailed;
        try host.draw(renderer, text_renderer);
        if (pending_screenshot.* != null) {
            try editor_commands.completePendingScreenshot(allocator, io, renderer, null, false, pending_screenshot);
        }
        if (!SDL_RenderPresent(renderer)) return error.SdlPresentFailed;
    }
    return try pm_apply_input.applyFrameInput(state, &host.ui, &host.input);
}

const editor_bg = shared.color.Color{ .r = 18, .g = 22, .b = 30, .a = 255 };
