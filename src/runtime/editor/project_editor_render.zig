const std = @import("std");
const editor_core_ui = @import("editor_core_ui.zig");
const editor_commands = @import("editor_commands.zig");
const editor_display = @import("editor_display.zig");
const editor_draw = @import("editor_draw.zig");
const editor_core_ui_draw = @import("editor_core_ui_draw.zig");
const editor_frame_perf = @import("editor_frame_perf.zig");
const editor_viewport_gpu = @import("editor_viewport_gpu.zig");
const shared = @import("runtime_shared");
const friendly_engine = @import("friendly_engine");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_types = @import("project_editor_types.zig");
const project_editor_ui_build = @import("project_editor_ui_build.zig");
const project_editor_preferences = @import("project_editor_preferences.zig");
const project_editor_modes = @import("project_editor_modes.zig");
const project_editor_view_nav = @import("project_editor_view_nav.zig");
const project_editor_world_atmosphere = @import("project_editor_world_atmosphere.zig");
const project_editor_gizmo_gallery = @import("project_editor_gizmo_gallery.zig");
const project_editor_viewport = @import("project_editor_viewport.zig");
const render_viewport = @import("project_editor_render_viewport.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const EditorAction = project_editor_types.EditorAction;
const UiStyle = editor_core_ui_draw.Style;
const core_ui = friendly_engine.modules.core_ui;

pub fn render(
    state: *ProjectEditorState,
    renderer: *editor_draw.SDL_Renderer,
    text_renderer: *editor_draw.TextRenderer,
    display: editor_display.Metrics,
    viewport_gpu: ?*editor_viewport_gpu.EditorViewportGpu,
    host: *editor_core_ui.Host,
    preferences: ?*project_editor_preferences.Context,
    pending_screenshot: *?editor_commands.PendingScreenshot,
    pending_turntable: *?editor_commands.PendingTurntableCapture,
) !EditorAction {
    const window_w = display.logical_w;
    const window_h = display.logical_h;
    state.window_w = window_w;
    state.window_h = window_h;
    state.display_scale = display.scale;

    const layout = project_editor_ui_build.computeLayout(window_w, window_h, state);
    state.viewport_screen_rect = toSdlRect(layout.viewport);

    host.setFrameBounds(.{ .x = 0, .y = 0, .w = window_w, .h = window_h });
    if (terrainLoadingActive(state)) {
        state.frame_perf.mark(.render_ui_build);
        try buildTerrainLoadingUi(&host.ui, state);
        state.frame_perf.mark(.render_input);
        state.uses_gpu_ui = viewport_gpu != null and viewport_gpu.?.use_gpu and state.view_camera_mode == .perspective;
        try renderTerrainLoadingFrame(state, renderer, text_renderer, display, viewport_gpu, host);
        return .continue_;
    }

    state.frame_perf.mark(.render_ui_build);
    try project_editor_ui_build.build(&host.ui, state, layout, preferences);
    state.frame_perf.mark(.render_input);
    const action = try state.handleEvent(host);

    state.uses_gpu_ui = viewport_gpu != null and viewport_gpu.?.use_gpu and state.view_camera_mode == .perspective;
    const editor_bg = host.style.input_bg_color;
    const review_capture = !state.show_viewport_toolbar;
    const sky_enabled = state.world_sky_visible and state.view_camera_mode == .perspective and (project_editor_state.worldContextVisible(state) or review_capture);
    const viewport_clear = if (sky_enabled and review_capture) project_editor_world_atmosphere.skyColor(state) else viewportClearColor(host.style);
    const use_atmosphere_sky = sky_enabled;

    if (state.uses_gpu_ui) {
        const gpu = &viewport_gpu.?.gpu_renderer.?;
        const vp_w: u32 = @intFromFloat(@max(1.0, layout.viewport.w));
        const vp_h: u32 = @intFromFloat(@max(1.0, layout.viewport.h));
        state.frame_perf.mark(.render_viewport);
        if (pending_screenshot.* != null and pending_screenshot.*.?.clean_viewport) {
            if (pending_screenshot.*.?.command_start_camera) |camera| state.camera = camera;
        }
        try render_viewport.drawOffscreen(state, viewport_gpu, vp_w, vp_h, viewport_clear, use_atmosphere_sky);
        state.frame_perf.mark(.render_present);
        try gpu.beginFrame(display.pixel_w, display.pixel_h, editor_bg);
        state.frame_perf.recordScope(.gpu_swapchain_acquire, gpu.lastSwapchainAcquireMs());
        try render_viewport.compositeGpuViewport(state, gpu, editor_display.physicalRect(state.viewport_screen_rect, display.scale));
        if (pending_screenshot.* != null and pending_screenshot.*.?.clean_viewport) {
            try editor_commands.completePendingScreenshot(state.allocator, state.io, renderer, gpu, true, pending_screenshot);
            return action;
        }
        var viewport_overlay_quads: std.ArrayList(shared.gpu_scene.OverlayQuad) = .empty;
        defer viewport_overlay_quads.deinit(state.allocator);
        if (state.mode == .layout or state.selection_scope == .marker or selectedObjectIsMarker(state)) {
            try project_editor_viewport.appendGpuObjectMarkers(state, state.allocator, &viewport_overlay_quads, state.viewport_screen_rect.w, state.viewport_screen_rect.h);
        }
        try project_editor_viewport.appendGpuSelectionBox(state, state.allocator, &viewport_overlay_quads);
        try project_editor_modes.appendGpuViewportOverlays(state, state.allocator, &viewport_overlay_quads);
        if (state.show_gizmo and (state.mode == .layout or @import("project_editor_life.zig").transformToolActive(state)) and state.selected_object != null) {
            try project_editor_gizmo_gallery.appendSelectedTransformGizmo(state, state.allocator, &viewport_overlay_quads);
        }
        try project_editor_gizmo_gallery.appendGpuGallery(state, state.allocator, &viewport_overlay_quads);
        scaleOverlayQuads(viewport_overlay_quads.items, display.scale);
        if (viewport_overlay_quads.items.len > 0) try gpu.drawOverlayQuads(viewport_overlay_quads.items);
        if (state.show_viewport_toolbar) {
            try project_editor_view_nav.drawGpuOverlay(state, state.allocator, gpu, state.viewport_screen_rect, display.scale);
        }
        state.frame_perf.mark(.render_ui_draw);
        try host.drawGpu(gpu, text_renderer, display.scale);
        if (pending_screenshot.* != null) {
            try editor_commands.completePendingScreenshot(state.allocator, state.io, renderer, gpu, true, pending_screenshot);
        } else if (pending_turntable.* != null) {
            try editor_commands.completePendingTurntableCapture(state.allocator, state.io, renderer, gpu, true, state, pending_turntable);
        } else {
            try gpu.endFrame();
        }
        return action;
    }

    try editor_display.applySdlScale(renderer, display.scale);
    if (!editor_draw.SDL_SetRenderDrawColor(renderer, editor_bg.r, editor_bg.g, editor_bg.b, editor_bg.a)) return error.SdlColorSetFailed;
    if (!editor_draw.SDL_RenderClear(renderer)) return error.SdlClearFailed;

    state.frame_perf.mark(.render_viewport);
    if (pending_screenshot.* != null and pending_screenshot.*.?.clean_viewport) {
        if (pending_screenshot.*.?.command_start_camera) |camera| state.camera = camera;
    }
    try render_viewport.draw(state, renderer, text_renderer, state.viewport_screen_rect, viewport_gpu, viewport_clear, use_atmosphere_sky);
    if (pending_screenshot.* != null and pending_screenshot.*.?.clean_viewport) {
        try editor_commands.completePendingScreenshot(state.allocator, state.io, renderer, null, false, pending_screenshot);
    }
    state.frame_perf.mark(.render_ui_draw);
    try host.draw(renderer, text_renderer);
    state.frame_perf.mark(.render_present);
    if (pending_screenshot.* != null) {
        try editor_commands.completePendingScreenshot(state.allocator, state.io, renderer, null, false, pending_screenshot);
    } else if (pending_turntable.* != null) {
        try editor_commands.completePendingTurntableCapture(state.allocator, state.io, renderer, null, false, state, pending_turntable);
    }
    if (!editor_draw.SDL_RenderPresent(renderer)) return error.SdlPresentFailed;

    return action;
}

fn selectedObjectIsMarker(state: *const ProjectEditorState) bool {
    const idx = state.selected_object orelse return false;
    if (idx >= state.objects.items.len) return false;
    return state.objects.items[idx].marker != null;
}

fn viewportClearColor(style: UiStyle) editor_draw.Color {
    var color = style.panel_color;
    color.a = 255;
    return color;
}

fn terrainLoadingActive(state: *const ProjectEditorState) bool {
    if (!project_editor_state.worldContextVisible(state)) return false;
    const resident = state.terrain_preview.entries.items.len;
    const desired = state.terrain_preview.last_desired_cells;
    const pending = state.terrain_preview.last_pending_loads;
    if (state.terrain_preview.post_process_active) return true;
    if (state.terrain_preview.post_process_deferred_after_cell_change and (state.terrain_preview.neighbor_links_dirty or state.terrain_preview.far_batches_dirty)) return true;
    if (state.terrain_preview_stale or pending > 0) return true;
    if (desired == 0) return false;
    return resident < desired;
}

fn buildTerrainLoadingUi(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    const bounds = ui.frame_bounds;
    const panel_w = @min(460.0, @max(320.0, bounds.w - 48.0));
    const panel_h: f32 = if (state.terrain_preview.post_process_active) 310.0 else 264.0;
    try ui.beginPanel(.{
        .id = "terrain-loading",
        .rect = .{
            .x = @max(24.0, (bounds.w - panel_w) * 0.5),
            .y = @max(24.0, (bounds.h - panel_h) * 0.5),
            .w = panel_w,
            .h = panel_h,
        },
        .row_height = 23.0,
    });
    try ui.label("Loading terrain");
    try ui.label(state.project_name);
    var progress_buf: [160]u8 = undefined;
    const resident = state.terrain_preview.entries.items.len;
    const desired = state.terrain_preview.last_desired_cells;
    const pending = state.terrain_preview.last_pending_loads;
    const progress = if (desired > 0)
        @as(f32, @floatFromInt(@min(resident, desired))) / @as(f32, @floatFromInt(desired))
    else
        0;
    try core_ui.widgets_feedback.progressBar(ui, "terrain-loading-progress", progress);
    const percent = progress * 100.0;
    const progress_text = std.fmt.bufPrint(
        &progress_buf,
        "{d} / {d} ({d:.0}%)",
        .{ resident, desired, percent },
    ) catch "Streaming terrain";
    try ui.richLabel("terrain-loading-loaded", &.{
        .{ .text = "Loaded " },
        .{ .text = progress_text, .style = .{ .monospace = true } },
    });

    var pending_buf: [48]u8 = undefined;
    const pending_text = std.fmt.bufPrint(&pending_buf, "{d}", .{pending}) catch "pending";
    try ui.richLabel("terrain-loading-pending", &.{
        .{ .text = "Pending " },
        .{ .text = pending_text, .style = .{ .monospace = true } },
    });

    if (state.terrain_preview.post_process_active) {
        const post_total = @max(state.terrain_preview.post_process_total, 1);
        const post_progress = @as(f32, @floatFromInt(@min(state.terrain_preview.post_process_completed, post_total))) / @as(f32, @floatFromInt(post_total));
        try core_ui.widgets_feedback.progressBar(ui, "terrain-post-process-progress", post_progress);
        var post_buf: [160]u8 = undefined;
        const post_text = std.fmt.bufPrint(
            &post_buf,
            "{s} {d} / {d}",
            .{
                state.terrain_preview.post_process_label,
                state.terrain_preview.post_process_completed,
                post_total,
            },
        ) catch "Preparing terrain";
        try ui.richLabel("terrain-loading-post-process", &.{
            .{ .text = "Preparing " },
            .{ .text = post_text, .style = .{ .monospace = true } },
        });
    }

    var elapsed_buf: [48]u8 = undefined;
    const elapsed_text = std.fmt.bufPrint(&elapsed_buf, "{d:.1}s", .{state.terrain_loading_elapsed_s}) catch "estimating";
    try ui.richLabel("terrain-loading-elapsed", &.{
        .{ .text = "Elapsed " },
        .{ .text = elapsed_text, .style = .{ .monospace = true } },
    });

    if (state.terrain_loading_rate_cells_per_s > 0) {
        var eta_buf: [48]u8 = undefined;
        var rate_buf: [48]u8 = undefined;
        const eta_text = std.fmt.bufPrint(&eta_buf, "{d:.1}s", .{state.terrain_loading_eta_s}) catch "estimating";
        const rate_text = std.fmt.bufPrint(&rate_buf, "{d:.1}", .{state.terrain_loading_rate_cells_per_s}) catch "estimating";
        try ui.richLabel("terrain-loading-eta", &.{
            .{ .text = "ETA " },
            .{ .text = eta_text, .style = .{ .monospace = true } },
        });
        try ui.richLabel("terrain-loading-rate", &.{
            .{ .text = "Rate " },
            .{ .text = rate_text, .style = .{ .monospace = true } },
            .{ .text = " cells/s" },
        });
    } else {
        try ui.label("Estimating remaining time");
    }
    try ui.label("Viewport paused for initial terrain");
    ui.endPanel();
}

fn renderTerrainLoadingFrame(
    state: *ProjectEditorState,
    renderer: *editor_draw.SDL_Renderer,
    text_renderer: *editor_draw.TextRenderer,
    display: editor_display.Metrics,
    viewport_gpu: ?*editor_viewport_gpu.EditorViewportGpu,
    host: *editor_core_ui.Host,
) !void {
    const bg = shared.color.Color{ .r = 18, .g = 22, .b = 30, .a = 255 };
    state.frame_perf.mark(.render_viewport);
    if (state.uses_gpu_ui) {
        const gpu = &viewport_gpu.?.gpu_renderer.?;
        state.frame_perf.mark(.render_present);
        try gpu.beginFrame(display.pixel_w, display.pixel_h, bg);
        state.frame_perf.recordScope(.gpu_swapchain_acquire, gpu.lastSwapchainAcquireMs());
        state.frame_perf.mark(.render_ui_draw);
        try host.drawGpu(gpu, text_renderer, display.scale);
        try gpu.endFrame();
        return;
    }

    try editor_display.applySdlScale(renderer, display.scale);
    if (!editor_draw.SDL_SetRenderDrawColor(renderer, bg.r, bg.g, bg.b, bg.a)) return error.SdlColorSetFailed;
    if (!editor_draw.SDL_RenderClear(renderer)) return error.SdlClearFailed;
    state.frame_perf.mark(.render_ui_draw);
    try host.draw(renderer, text_renderer);
    state.frame_perf.mark(.render_present);
    if (!editor_draw.SDL_RenderPresent(renderer)) return error.SdlPresentFailed;
}

fn toSdlRect(rect: @import("friendly_engine").modules.core_ui.Rect) editor_draw.SDL_FRect {
    return .{ .x = rect.x, .y = rect.y, .w = rect.w, .h = rect.h };
}

fn scaleOverlayQuads(quads: []shared.gpu_scene.OverlayQuad, scale: f32) void {
    if (scale == 1) return;
    for (quads) |*quad| {
        quad.rect[0] *= scale;
        quad.rect[1] *= scale;
        quad.rect[2] *= scale;
        quad.rect[3] *= scale;
        quad.skew_x *= scale;
    }
}
