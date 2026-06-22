const sdl_gpu = @import("sdl_gpu.zig");
const shared_color = @import("color.zig");
const textures = @import("gpu_backend_sdl_frame_textures.zig");
const hdr = @import("gpu_backend_sdl_hdr.zig");

pub fn beginOffscreenFrame(self: anytype, width: u32, height: u32, clear: shared_color.Color) !void {
    hdr.pollExposureReadback(self);
    self.width = @max(1, width);
    self.height = @max(1, height);
    self.in_offscreen_frame = true;
    try textures.ensureOffscreenColorTexture(self);
    const render_hdr = hdr.prepareSceneTarget(self, self.offscreen_sample_count);
    try textures.ensureDepthTexture(self, self.offscreen_sample_count);

    const cmdbuf = sdl_gpu.SDL_AcquireGPUCommandBuffer(self.device) orelse return error.CommandBufferFailed;
    self.cmdbuf = cmdbuf;
    sdl_gpu.SDL_PushGPUDebugGroup(cmdbuf, "friendly-engine offscreen frame");

    const uses_msaa = self.offscreen_sample_count != sdl_gpu.SDL_GPU_SAMPLECOUNT_1;
    var color_target = sdl_gpu.SDL_GPUColorTargetInfo{
        .texture = if (render_hdr)
            if (uses_msaa) self.hdr_msaa_color_texture else self.hdr_color_texture
        else if (uses_msaa) self.offscreen_msaa_color_texture else self.offscreen_color_texture,
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
        color_target.resolve_texture = if (render_hdr) self.hdr_color_texture else self.offscreen_color_texture;
    }

    var depth_target = sdl_gpu.SDL_GPUDepthStencilTargetInfo{
        .texture = self.depth_texture,
        .clear_depth = 1,
        .load_op = sdl_gpu.SDL_GPU_LOADOP_CLEAR,
        .store_op = sdl_gpu.SDL_GPU_STOREOP_STORE,
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

pub fn endOffscreenFrame(self: anytype) void {
    hdr.finishHdrSceneForComposite(self) catch {};
    if (self.render_pass) |pass| {
        sdl_gpu.SDL_EndGPURenderPass(pass);
        self.render_pass = null;
    }
    if (self.cmdbuf) |cmdbuf| {
        sdl_gpu.SDL_PopGPUDebugGroup(cmdbuf);
        hdr.submitCommandBuffer(self, cmdbuf) catch {};
        self.cmdbuf = null;
    }
    self.in_offscreen_frame = false;
    self.swapchain_texture = null;
}

pub fn readOffscreenPixels(self: anytype, dest: []u8) void {
    hdr.finishHdrSceneForComposite(self) catch return;
    if (self.offscreen_color_texture == null) return;
    const w = self.width;
    const h = self.height;
    const row_bytes = @as(usize, w) * 4;
    const needed = row_bytes * @as(usize, h);
    if (dest.len < needed) return;

    const cmdbuf = self.cmdbuf orelse return;
    if (self.render_pass) |pass| {
        sdl_gpu.SDL_EndGPURenderPass(pass);
        self.render_pass = null;
    }

    if (!textures.ensureDownloadBuffer(self)) return;

    const transfer = self.download_transfer_buffer.?;
    const copy_pass = sdl_gpu.SDL_BeginGPUCopyPass(cmdbuf) orelse return;
    sdl_gpu.SDL_DownloadFromGPUTexture(copy_pass, &.{
        .texture = self.offscreen_color_texture,
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
    const fence = sdl_gpu.SDL_SubmitGPUCommandBufferAndAcquireFence(cmdbuf) orelse return;
    self.cmdbuf = null;
    defer sdl_gpu.SDL_ReleaseGPUFence(self.device, fence);

    var fences = [_]?*sdl_gpu.SDL_GPUFence{fence};
    if (!sdl_gpu.SDL_WaitForGPUFences(self.device, true, @ptrCast(&fences), 1)) return;
    if (had_exposure_readback) hdr.consumeCompletedExposureReadback(self);

    const mapped = sdl_gpu.SDL_MapGPUTransferBuffer(self.device, transfer, false) orelse return;
    defer sdl_gpu.SDL_UnmapGPUTransferBuffer(self.device, transfer);
    @memcpy(dest[0..needed], @as([*]const u8, @ptrCast(mapped))[0..needed]);
}
