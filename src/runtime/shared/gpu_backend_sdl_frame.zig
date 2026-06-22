const sdl_gpu = @import("sdl_gpu.zig");
const std = @import("std");
const builtin = @import("builtin");
const shared_color = @import("color.zig");
const offscreen = @import("gpu_backend_sdl_frame_offscreen.zig");
const textures = @import("gpu_backend_sdl_frame_textures.zig");
const draw = @import("gpu_backend_sdl_frame_draw.zig");
const hdr = @import("gpu_backend_sdl_hdr.zig");

pub const activeGridPipeline = @import("gpu_backend_sdl_frame_pipelines.zig").activeGridPipeline;
pub const activeWireframePipeline = @import("gpu_backend_sdl_frame_pipelines.zig").activeWireframePipeline;
pub const activeLitMeshPipeline = @import("gpu_backend_sdl_frame_pipelines.zig").activeLitMeshPipeline;
pub const activeMeshPipeline = @import("gpu_backend_sdl_frame_pipelines.zig").activeMeshPipeline;
pub const activeSkyPipeline = @import("gpu_backend_sdl_frame_pipelines.zig").activeSkyPipeline;

pub const beginOffscreenFrame = offscreen.beginOffscreenFrame;
pub const endOffscreenFrame = offscreen.endOffscreenFrame;
pub const readOffscreenPixels = offscreen.readOffscreenPixels;

pub const drawSky = draw.drawSky;
pub const drawGrid = draw.drawGrid;
pub const drawMeshByIndex = draw.drawMeshByIndex;
pub const drawMeshDraw = draw.drawMeshDraw;
pub const drawMeshWireframeByIndex = draw.drawMeshWireframeByIndex;
pub const drawOverlayQuads = draw.drawOverlayQuads;
pub const submitCommands = draw.submitCommands;
pub const clearOverlayScratch = draw.clearOverlayScratch;
pub const createOverlayTextureFromRgba = @import("gpu_backend_sdl_overlay.zig").createOverlayTextureFromRgba;
pub const updateOverlayTextureFromRgba = @import("gpu_backend_sdl_overlay.zig").updateOverlayTextureFromRgba;

pub const ensureDepthTexture = textures.ensureDepthTexture;
pub const ensureOffscreenColorTexture = textures.ensureOffscreenColorTexture;
pub const ensureFrameMsaaTexture = textures.ensureFrameMsaaTexture;
pub const ensureWaterDepthTexture = textures.ensureWaterDepthTexture;
pub const destroyWaterDepth = textures.destroyWaterDepth;
pub const ensureDownloadBuffer = textures.ensureDownloadBuffer;
pub const destroyOffscreen = textures.destroyOffscreen;
pub const destroyFrameMsaa = textures.destroyFrameMsaa;
pub const destroyHdr = hdr.destroyHdr;

pub fn beginFrame(self: anytype, width: u32, height: u32, clear: shared_color.Color) !void {
    hdr.pollExposureReadback(self);
    self.width = @max(1, width);
    self.height = @max(1, height);
    const sample_count = self.settings.sampleCount();
    const render_hdr = hdr.prepareSceneTarget(self, sample_count);
    try textures.ensureDepthTexture(self, sample_count);

    const cmdbuf = sdl_gpu.SDL_AcquireGPUCommandBuffer(self.device) orelse return error.CommandBufferFailed;
    self.cmdbuf = cmdbuf;
    sdl_gpu.SDL_PushGPUDebugGroup(cmdbuf, "friendly-engine frame");

    var swapchain_texture: ?*sdl_gpu.SDL_GPUTexture = null;
    const acquire_start = monotonicNs();
    if (!sdl_gpu.SDL_WaitAndAcquireGPUSwapchainTexture(cmdbuf, self.window, &swapchain_texture, null, null)) {
        return error.SwapchainAcquireFailed;
    }
    const acquire_ns = monotonicNs() - acquire_start;
    self.last_swapchain_acquire_ms = if (acquire_ns <= 0) 0 else @as(f64, @floatFromInt(acquire_ns)) / @as(f64, @floatFromInt(@import("std").time.ns_per_ms));
    self.swapchain_texture = swapchain_texture;
    if (swapchain_texture == null) return;
    if (!render_hdr) try textures.ensureFrameMsaaTexture(self);

    const uses_msaa = sample_count != sdl_gpu.SDL_GPU_SAMPLECOUNT_1;
    var color_target = sdl_gpu.SDL_GPUColorTargetInfo{
        .texture = if (render_hdr)
            if (uses_msaa) self.hdr_msaa_color_texture else self.hdr_color_texture
        else if (uses_msaa) self.frame_msaa_color_texture else swapchain_texture,
        .clear_color = .{
            .r = @as(f32, @floatFromInt(clear.r)) / 255.0,
            .g = @as(f32, @floatFromInt(clear.g)) / 255.0,
            .b = @as(f32, @floatFromInt(clear.b)) / 255.0,
            .a = @as(f32, @floatFromInt(clear.a)) / 255.0,
        },
        .load_op = sdl_gpu.SDL_GPU_LOADOP_CLEAR,
        .store_op = if (uses_msaa) sdl_gpu.SDL_GPU_STOREOP_RESOLVE else sdl_gpu.SDL_GPU_STOREOP_STORE,
    };
    if (uses_msaa) {
        color_target.resolve_texture = if (render_hdr) self.hdr_color_texture else swapchain_texture;
    }

    var depth_target = sdl_gpu.SDL_GPUDepthStencilTargetInfo{
        .texture = self.depth_texture,
        .clear_depth = 1,
        .load_op = sdl_gpu.SDL_GPU_LOADOP_CLEAR,
        .store_op = sdl_gpu.SDL_GPU_STOREOP_STORE,
        // D16_UNORM has no stencil component; setting stencil ops to anything but
        // DONT_CARE makes Metal mishandle the depth attachment (depth never clears).
        .stencil_load_op = sdl_gpu.SDL_GPU_LOADOP_DONT_CARE,
        .stencil_store_op = sdl_gpu.SDL_GPU_STOREOP_DONT_CARE,
    };

    const color_targets = [_]sdl_gpu.SDL_GPUColorTargetInfo{color_target};
    const render_pass = sdl_gpu.SDL_BeginGPURenderPass(cmdbuf, &color_targets, 1, &depth_target) orelse return error.RenderPassFailed;
    self.render_pass = render_pass;

    const viewport = sdl_gpu.SDL_GPUViewport{
        .x = 0,
        .y = 0,
        .w = @floatFromInt(self.width),
        .h = @floatFromInt(self.height),
        .min_depth = 0,
        .max_depth = 1,
    };
    sdl_gpu.SDL_SetGPUViewport(render_pass, &viewport);
}

fn monotonicNs() i128 {
    if (builtin.os.tag == .windows) {
        const kernel32 = std.os.windows.kernel32;
        var count: i64 = undefined;
        _ = kernel32.QueryPerformanceCounter(&count);
        var freq: i64 = undefined;
        _ = kernel32.QueryPerformanceFrequency(&freq);
        return @divFloor(@as(i128, count) * std.time.ns_per_s, freq);
    }
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(std.c.CLOCK.MONOTONIC, &ts);
    return @as(i128, ts.sec) * std.time.ns_per_s + @as(i128, ts.nsec);
}

pub fn endFrame(self: anytype) !void {
    try hdr.finishHdrSceneForComposite(self);
    if (self.render_pass) |pass| {
        sdl_gpu.SDL_EndGPURenderPass(pass);
        self.render_pass = null;
    }
    if (self.cmdbuf) |cmdbuf| {
        sdl_gpu.SDL_PopGPUDebugGroup(cmdbuf);
        try hdr.submitCommandBuffer(self, cmdbuf);
        self.cmdbuf = null;
    }
    self.swapchain_texture = null;
}

/// Read back the exact swapchain texture produced by the normal frame renderer.
/// Call this after all final viewport, overlay, and UI draws, at the point where
/// endFrame would otherwise submit/present, so screenshot tools see what users see.
pub fn capturePresentedFrameAndEndFrame(self: anytype, dest: []u8) !void {
    try hdr.finishHdrSceneForComposite(self);
    const swapchain = self.swapchain_texture orelse return error.SwapchainTextureMissing;
    const w = self.width;
    const h = self.height;
    const row_bytes = @as(usize, w) * 4;
    const needed = row_bytes * @as(usize, h);
    if (dest.len < needed) return error.CaptureBufferTooSmall;

    const cmdbuf = self.cmdbuf orelse return error.NoActiveCommandBuffer;
    if (self.render_pass) |pass| {
        sdl_gpu.SDL_EndGPURenderPass(pass);
        self.render_pass = null;
    }
    if (!textures.ensureDownloadBuffer(self)) return error.DownloadBufferCreateFailed;
    const transfer = self.download_transfer_buffer.?;

    const copy_pass = sdl_gpu.SDL_BeginGPUCopyPass(cmdbuf) orelse return error.CopyPassFailed;
    sdl_gpu.SDL_DownloadFromGPUTexture(copy_pass, &.{
        .texture = swapchain,
        .w = w,
        .h = h,
        .d = 1,
    }, &.{
        .transfer_buffer = transfer,
        .offset = 0,
        .pixels_per_row = w,
        .rows_per_layer = h,
    });
    sdl_gpu.SDL_EndGPUCopyPass(copy_pass);

    sdl_gpu.SDL_PopGPUDebugGroup(cmdbuf);
    const had_exposure_readback = self.exposure_readback_queued;
    self.exposure_readback_queued = false;
    const fence = sdl_gpu.SDL_SubmitGPUCommandBufferAndAcquireFence(cmdbuf) orelse return error.CommandSubmitFailed;
    self.cmdbuf = null;
    self.swapchain_texture = null;
    defer sdl_gpu.SDL_ReleaseGPUFence(self.device, fence);

    var fences = [_]?*sdl_gpu.SDL_GPUFence{fence};
    if (!sdl_gpu.SDL_WaitForGPUFences(self.device, true, @ptrCast(&fences), 1)) return error.GpuFenceWaitFailed;
    if (had_exposure_readback) hdr.consumeCompletedExposureReadback(self);

    const mapped = sdl_gpu.SDL_MapGPUTransferBuffer(self.device, transfer, false) orelse return error.TransferMapFailed;
    defer sdl_gpu.SDL_UnmapGPUTransferBuffer(self.device, transfer);
    @memcpy(dest[0..needed], @as([*]const u8, @ptrCast(mapped))[0..needed]);

    switch (self.swapchain_format) {
        sdl_gpu.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
        sdl_gpu.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM_SRGB,
        => {},
        sdl_gpu.SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM,
        sdl_gpu.SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM_SRGB,
        => bgraToRgba(dest[0..needed]),
        else => return error.UnsupportedSwapchainCaptureFormat,
    }
}

fn bgraToRgba(pixels: []u8) void {
    var i: usize = 0;
    while (i + 3 < pixels.len) : (i += 4) {
        const b = pixels[i];
        pixels[i] = pixels[i + 2];
        pixels[i + 2] = b;
    }
}
