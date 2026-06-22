const sdl_gpu = @import("sdl_gpu.zig");

pub fn ensureDepthTexture(self: anytype, sample_count: sdl_gpu.SDL_GPUSampleCount) !void {
    if (self.depth_texture != null and
        self.depth_width == self.width and
        self.depth_height == self.height and
        self.depth_sample_count == sample_count)
    {
        return;
    }
    if (self.depth_texture) |tex| {
        sdl_gpu.SDL_ReleaseGPUTexture(self.device, tex);
        self.depth_texture = null;
    }
    const depth_usage = if (sample_count == sdl_gpu.SDL_GPU_SAMPLECOUNT_1)
        sdl_gpu.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET | sdl_gpu.SDL_GPU_TEXTUREUSAGE_SAMPLER
    else
        sdl_gpu.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET;
    const tex = sdl_gpu.SDL_CreateGPUTexture(self.device, &.{
        .type = sdl_gpu.SDL_GPU_TEXTURETYPE_2D,
        .format = sdl_gpu.SDL_GPU_TEXTUREFORMAT_D32_FLOAT,
        .usage = depth_usage,
        .width = self.width,
        .height = self.height,
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .sample_count = sample_count,
    }) orelse return error.DepthTextureCreateFailed;
    self.depth_texture = tex;
    self.depth_width = self.width;
    self.depth_height = self.height;
    self.depth_sample_count = sample_count;
}

pub fn ensureWaterDepthTexture(self: anytype) !void {
    if (self.water_depth_texture != null and self.water_depth_width == self.width and self.water_depth_height == self.height) return;
    if (self.water_depth_texture) |tex| {
        sdl_gpu.SDL_ReleaseGPUTexture(self.device, tex);
        self.water_depth_texture = null;
    }
    const tex = sdl_gpu.SDL_CreateGPUTexture(self.device, &.{
        .type = sdl_gpu.SDL_GPU_TEXTURETYPE_2D,
        .format = sdl_gpu.SDL_GPU_TEXTUREFORMAT_D32_FLOAT,
        .usage = sdl_gpu.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET | sdl_gpu.SDL_GPU_TEXTUREUSAGE_SAMPLER,
        .width = self.width,
        .height = self.height,
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .sample_count = sdl_gpu.SDL_GPU_SAMPLECOUNT_1,
    }) orelse return error.WaterDepthTextureCreateFailed;
    self.water_depth_texture = tex;
    self.water_depth_width = self.width;
    self.water_depth_height = self.height;
}

pub fn destroyWaterDepth(self: anytype) void {
    if (self.water_depth_texture) |tex| {
        sdl_gpu.SDL_ReleaseGPUTexture(self.device, tex);
        self.water_depth_texture = null;
    }
    self.water_depth_width = 0;
    self.water_depth_height = 0;
}

pub fn ensureOffscreenColorTexture(self: anytype) !void {
    const uses_msaa = self.offscreen_sample_count != sdl_gpu.SDL_GPU_SAMPLECOUNT_1;
    if (self.offscreen_color_texture != null and
        (!uses_msaa or self.offscreen_msaa_color_texture != null) and
        self.offscreen_width == self.width and
        self.offscreen_height == self.height)
    {
        return;
    }
    if (self.offscreen_color_texture) |tex| {
        sdl_gpu.SDL_ReleaseGPUTexture(self.device, tex);
        self.offscreen_color_texture = null;
    }
    if (self.offscreen_msaa_color_texture) |tex| {
        sdl_gpu.SDL_ReleaseGPUTexture(self.device, tex);
        self.offscreen_msaa_color_texture = null;
    }
    const resolve_tex = sdl_gpu.SDL_CreateGPUTexture(self.device, &.{
        .type = sdl_gpu.SDL_GPU_TEXTURETYPE_2D,
        .format = sdl_gpu.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
        .usage = sdl_gpu.SDL_GPU_TEXTUREUSAGE_COLOR_TARGET | sdl_gpu.SDL_GPU_TEXTUREUSAGE_SAMPLER,
        .width = self.width,
        .height = self.height,
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .sample_count = sdl_gpu.SDL_GPU_SAMPLECOUNT_1,
    }) orelse return error.OffscreenTextureCreateFailed;
    errdefer sdl_gpu.SDL_ReleaseGPUTexture(self.device, resolve_tex);

    const msaa_tex = if (uses_msaa)
        sdl_gpu.SDL_CreateGPUTexture(self.device, &.{
            .type = sdl_gpu.SDL_GPU_TEXTURETYPE_2D,
            .format = sdl_gpu.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
            .usage = sdl_gpu.SDL_GPU_TEXTUREUSAGE_COLOR_TARGET,
            .width = self.width,
            .height = self.height,
            .layer_count_or_depth = 1,
            .num_levels = 1,
            .sample_count = self.offscreen_sample_count,
        }) orelse return error.OffscreenTextureCreateFailed
    else
        null;

    self.offscreen_color_texture = resolve_tex;
    self.offscreen_msaa_color_texture = msaa_tex;
    self.offscreen_width = self.width;
    self.offscreen_height = self.height;
}

pub fn ensureFrameMsaaTexture(self: anytype) !void {
    const sample_count = self.settings.sampleCount();
    if (sample_count == sdl_gpu.SDL_GPU_SAMPLECOUNT_1) {
        destroyFrameMsaa(self);
        return;
    }
    if (self.frame_msaa_color_texture != null and
        self.frame_msaa_width == self.width and
        self.frame_msaa_height == self.height)
    {
        return;
    }
    destroyFrameMsaa(self);
    const tex = sdl_gpu.SDL_CreateGPUTexture(self.device, &.{
        .type = sdl_gpu.SDL_GPU_TEXTURETYPE_2D,
        .format = self.swapchain_format,
        .usage = sdl_gpu.SDL_GPU_TEXTUREUSAGE_COLOR_TARGET,
        .width = self.width,
        .height = self.height,
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .sample_count = sample_count,
    }) orelse return error.FrameTextureCreateFailed;
    self.frame_msaa_color_texture = tex;
    self.frame_msaa_width = self.width;
    self.frame_msaa_height = self.height;
}

pub fn ensureDownloadBuffer(self: anytype) bool {
    const needed = self.width * self.height * 4;
    if (self.download_transfer_buffer != null and self.download_buffer_bytes == needed) return true;

    if (self.download_transfer_buffer) |buffer| {
        sdl_gpu.SDL_ReleaseGPUTransferBuffer(self.device, buffer);
        self.download_transfer_buffer = null;
        self.download_buffer_bytes = 0;
    }

    const transfer = sdl_gpu.SDL_CreateGPUTransferBuffer(self.device, &.{
        .usage = sdl_gpu.SDL_GPU_TRANSFERBUFFERUSAGE_DOWNLOAD,
        .size = needed,
    }) orelse return false;
    self.download_transfer_buffer = transfer;
    self.download_buffer_bytes = needed;
    return true;
}

pub fn destroyOffscreen(self: anytype) void {
    if (self.download_transfer_buffer) |buffer| {
        sdl_gpu.SDL_ReleaseGPUTransferBuffer(self.device, buffer);
        self.download_transfer_buffer = null;
        self.download_buffer_bytes = 0;
    }
    if (self.offscreen_color_texture) |tex| {
        sdl_gpu.SDL_ReleaseGPUTexture(self.device, tex);
        self.offscreen_color_texture = null;
    }
    if (self.offscreen_msaa_color_texture) |tex| {
        sdl_gpu.SDL_ReleaseGPUTexture(self.device, tex);
        self.offscreen_msaa_color_texture = null;
    }
    self.offscreen_width = 0;
    self.offscreen_height = 0;
}

pub fn destroyFrameMsaa(self: anytype) void {
    if (self.frame_msaa_color_texture) |tex| {
        sdl_gpu.SDL_ReleaseGPUTexture(self.device, tex);
        self.frame_msaa_color_texture = null;
    }
    self.frame_msaa_width = 0;
    self.frame_msaa_height = 0;
}
