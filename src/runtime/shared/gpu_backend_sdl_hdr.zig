const std = @import("std");
const sdl_gpu = @import("sdl_gpu.zig");
const pipelines = @import("gpu_backend_sdl_pipelines.zig");
const render_tonemap = @import("render_tonemap.zig");
const engine_time = @import("friendly_engine").core.time;

pub const hdr_color_format = sdl_gpu.SDL_GPU_TEXTUREFORMAT_R16G16B16A16_FLOAT;
pub const luminance_format = sdl_gpu.SDL_GPU_TEXTUREFORMAT_R32_FLOAT;

pub fn prepareSceneTarget(self: anytype, sample_count: sdl_gpu.SDL_GPUSampleCount) bool {
    self.scene_color_hdr_active = false;
    self.hdr_scene_resolved = false;
    if (!self.settings.hdrEnabled() or !self.hdr_supported) return false;

    ensureHdrResources(self, sample_count) catch |err| {
        std.log.warn("HDR render target unavailable ({s}); falling back to SDR direct", .{@errorName(err)});
        self.hdr_supported = false;
        destroyHdrTargets(self);
        return false;
    };
    self.scene_color_hdr_active = true;
    return true;
}

pub fn ensureHdrResources(self: anytype, sample_count: sdl_gpu.SDL_GPUSampleCount) !void {
    try ensureHdrTargets(self, sample_count);
    try ensureHdrPipelines(self, sample_count);
    try ensureExposureReadbackBuffer(self);
}

pub fn ensureHdrTargets(self: anytype, sample_count: sdl_gpu.SDL_GPUSampleCount) !void {
    const uses_msaa = sample_count != sdl_gpu.SDL_GPU_SAMPLECOUNT_1;
    if (self.hdr_color_texture != null and
        (!uses_msaa or self.hdr_msaa_color_texture != null) and
        self.luminance_texture != null and
        self.hdr_width == self.width and
        self.hdr_height == self.height and
        self.hdr_sample_count == sample_count)
    {
        return;
    }

    destroyHdrTargets(self);

    const color = sdl_gpu.SDL_CreateGPUTexture(self.device, &.{
        .type = sdl_gpu.SDL_GPU_TEXTURETYPE_2D,
        .format = hdr_color_format,
        .usage = sdl_gpu.SDL_GPU_TEXTUREUSAGE_COLOR_TARGET | sdl_gpu.SDL_GPU_TEXTUREUSAGE_SAMPLER,
        .width = self.width,
        .height = self.height,
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .sample_count = sdl_gpu.SDL_GPU_SAMPLECOUNT_1,
    }) orelse return error.HdrTextureCreateFailed;
    errdefer sdl_gpu.SDL_ReleaseGPUTexture(self.device, color);

    const msaa = if (uses_msaa)
        sdl_gpu.SDL_CreateGPUTexture(self.device, &.{
            .type = sdl_gpu.SDL_GPU_TEXTURETYPE_2D,
            .format = hdr_color_format,
            .usage = sdl_gpu.SDL_GPU_TEXTUREUSAGE_COLOR_TARGET,
            .width = self.width,
            .height = self.height,
            .layer_count_or_depth = 1,
            .num_levels = 1,
            .sample_count = sample_count,
        }) orelse return error.HdrTextureCreateFailed
    else
        null;
    errdefer if (msaa) |tex| sdl_gpu.SDL_ReleaseGPUTexture(self.device, tex);

    const luminance = sdl_gpu.SDL_CreateGPUTexture(self.device, &.{
        .type = sdl_gpu.SDL_GPU_TEXTURETYPE_2D,
        .format = luminance_format,
        .usage = sdl_gpu.SDL_GPU_TEXTUREUSAGE_COLOR_TARGET | sdl_gpu.SDL_GPU_TEXTUREUSAGE_SAMPLER,
        .width = 1,
        .height = 1,
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .sample_count = sdl_gpu.SDL_GPU_SAMPLECOUNT_1,
    }) orelse return error.LuminanceTextureCreateFailed;

    self.hdr_color_texture = color;
    self.hdr_msaa_color_texture = msaa;
    self.luminance_texture = luminance;
    self.hdr_width = self.width;
    self.hdr_height = self.height;
    self.hdr_sample_count = sample_count;
}

pub fn ensureHdrPipelines(self: anytype, sample_count: sdl_gpu.SDL_GPUSampleCount) !void {
    if (self.hdr_pipeline_sample_count == sample_count and
        self.hdr_mesh_pipeline != null and
        self.hdr_grass_pipeline != null and
        self.hdr_tonemap_pipeline != null and
        self.hdr_offscreen_tonemap_pipeline != null and
        self.hdr_luminance_pipeline != null)
    {
        return;
    }
    destroyHdrPipelines(self);

    const mesh = try pipelines.createMeshPipeline(self.device, hdr_color_format, sample_count);
    errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, mesh);
    const lit_mesh = try pipelines.createLitMeshPipeline(self.device, hdr_color_format, sample_count);
    errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, lit_mesh);
    const solid_mesh = try pipelines.createSolidMeshPipeline(self.device, hdr_color_format, sample_count);
    errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, solid_mesh);
    const double_mesh = try pipelines.createDoubleSidedMeshPipeline(self.device, hdr_color_format, sample_count);
    errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, double_mesh);
    const double_lit = try pipelines.createDoubleSidedLitMeshPipeline(self.device, hdr_color_format, sample_count);
    errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, double_lit);
    const double_solid = try pipelines.createDoubleSidedSolidMeshPipeline(self.device, hdr_color_format, sample_count);
    errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, double_solid);
    const water = try pipelines.createWaterPipeline(self.device, hdr_color_format, sdl_gpu.SDL_GPU_SAMPLECOUNT_1);
    errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, water);
    const grass = try pipelines.createGrassPipeline(self.device, hdr_color_format, sample_count);
    errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, grass);
    const instanced = try pipelines.createInstancedMeshPipeline(self.device, hdr_color_format, sample_count);
    errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, instanced);
    const lit_instanced = try pipelines.createLitInstancedMeshPipeline(self.device, hdr_color_format, sample_count);
    errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, lit_instanced);
    const solid_instanced = try pipelines.createSolidInstancedMeshPipeline(self.device, hdr_color_format, sample_count);
    errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, solid_instanced);
    const grid = try pipelines.createGridPipeline(self.device, hdr_color_format, sample_count);
    errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, grid);
    const wireframe = try pipelines.createWireframePipeline(self.device, hdr_color_format, sample_count);
    errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, wireframe);
    const sky = try pipelines.createSkyPipeline(self.device, hdr_color_format, sample_count);
    errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, sky);
    const tonemap = try pipelines.createTonemapPipeline(self.device, self.swapchain_format);
    errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, tonemap);
    const offscreen_tonemap = try pipelines.createTonemapPipeline(self.device, sdl_gpu.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM);
    errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, offscreen_tonemap);
    const luminance = try pipelines.createLuminancePipeline(self.device);
    errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, luminance);

    self.hdr_mesh_pipeline = mesh;
    self.hdr_lit_mesh_pipeline = lit_mesh;
    self.hdr_solid_mesh_pipeline = solid_mesh;
    self.hdr_double_sided_mesh_pipeline = double_mesh;
    self.hdr_double_sided_lit_mesh_pipeline = double_lit;
    self.hdr_double_sided_solid_mesh_pipeline = double_solid;
    self.hdr_water_pipeline = water;
    self.hdr_grass_pipeline = grass;
    self.hdr_instanced_mesh_pipeline = instanced;
    self.hdr_lit_instanced_mesh_pipeline = lit_instanced;
    self.hdr_solid_instanced_mesh_pipeline = solid_instanced;
    self.hdr_grid_pipeline = grid;
    self.hdr_wireframe_pipeline = wireframe;
    self.hdr_sky_pipeline = sky;
    self.hdr_tonemap_pipeline = tonemap;
    self.hdr_offscreen_tonemap_pipeline = offscreen_tonemap;
    self.hdr_luminance_pipeline = luminance;
    self.hdr_pipeline_sample_count = sample_count;
}

fn ensureExposureReadbackBuffer(self: anytype) !void {
    if (self.exposure_transfer_buffer != null) return;
    self.exposure_transfer_buffer = sdl_gpu.SDL_CreateGPUTransferBuffer(self.device, &.{
        .usage = sdl_gpu.SDL_GPU_TRANSFERBUFFERUSAGE_DOWNLOAD,
        .size = 4,
    }) orelse return error.ExposureTransferBufferCreateFailed;
}

pub fn finishHdrSceneForComposite(self: anytype) !void {
    if (!self.scene_color_hdr_active or self.hdr_scene_resolved) return;
    const cmdbuf = self.cmdbuf orelse return error.NoActiveCommandBuffer;
    if (self.render_pass) |pass| {
        sdl_gpu.SDL_EndGPURenderPass(pass);
        self.render_pass = null;
    }
    const hdr_tex = self.hdr_color_texture orelse return error.HdrTextureMissing;

    try renderLuminance(self, cmdbuf, hdr_tex);
    try queueExposureReadback(self, cmdbuf);
    try renderTonemap(self, cmdbuf, hdr_tex);

    self.hdr_scene_resolved = true;
    self.scene_color_hdr_active = false;
}

fn renderLuminance(self: anytype, cmdbuf: *sdl_gpu.SDL_GPUCommandBuffer, hdr_tex: *sdl_gpu.SDL_GPUTexture) !void {
    const target = sdl_gpu.SDL_GPUColorTargetInfo{
        .texture = self.luminance_texture,
        .clear_color = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
        .load_op = sdl_gpu.SDL_GPU_LOADOP_CLEAR,
        .store_op = sdl_gpu.SDL_GPU_STOREOP_STORE,
    };
    const targets = [_]sdl_gpu.SDL_GPUColorTargetInfo{target};
    const pass = sdl_gpu.SDL_BeginGPURenderPass(cmdbuf, &targets, 1, null) orelse return error.RenderPassFailed;
    defer sdl_gpu.SDL_EndGPURenderPass(pass);
    const viewport = sdl_gpu.SDL_GPUViewport{ .x = 0, .y = 0, .w = 1, .h = 1, .min_depth = 0, .max_depth = 1 };
    sdl_gpu.SDL_SetGPUViewport(pass, &viewport);
    sdl_gpu.SDL_BindGPUGraphicsPipeline(pass, self.hdr_luminance_pipeline.?);
    const bindings = [_]sdl_gpu.SDL_GPUTextureSamplerBinding{.{ .texture = hdr_tex, .sampler = self.mask_sampler }};
    sdl_gpu.SDL_BindGPUFragmentSamplers(pass, 0, &bindings, 1);
    sdl_gpu.SDL_DrawGPUPrimitives(pass, 3, 1, 0, 0);
}

fn queueExposureReadback(self: anytype, cmdbuf: *sdl_gpu.SDL_GPUCommandBuffer) !void {
    if (self.exposure_fence != null or self.exposure_readback_queued) return;
    const transfer = self.exposure_transfer_buffer orelse return;
    const luminance = self.luminance_texture orelse return;
    const copy_pass = sdl_gpu.SDL_BeginGPUCopyPass(cmdbuf) orelse return error.CopyPassFailed;
    sdl_gpu.SDL_DownloadFromGPUTexture(copy_pass, &.{
        .texture = luminance,
        .w = 1,
        .h = 1,
        .d = 1,
    }, &.{
        .transfer_buffer = transfer,
        .offset = 0,
        .pixels_per_row = 1,
        .rows_per_layer = 1,
    });
    sdl_gpu.SDL_EndGPUCopyPass(copy_pass);
    self.exposure_readback_queued = true;
}

fn renderTonemap(self: anytype, cmdbuf: *sdl_gpu.SDL_GPUCommandBuffer, hdr_tex: *sdl_gpu.SDL_GPUTexture) !void {
    const output = if (self.in_offscreen_frame) self.offscreen_color_texture else self.swapchain_texture;
    const target = sdl_gpu.SDL_GPUColorTargetInfo{
        .texture = output,
        .load_op = sdl_gpu.SDL_GPU_LOADOP_DONT_CARE,
        .store_op = sdl_gpu.SDL_GPU_STOREOP_STORE,
    };
    if (target.texture == null) return error.ColorTargetMissing;
    const targets = [_]sdl_gpu.SDL_GPUColorTargetInfo{target};
    const pass = sdl_gpu.SDL_BeginGPURenderPass(cmdbuf, &targets, 1, null) orelse return error.RenderPassFailed;
    defer sdl_gpu.SDL_EndGPURenderPass(pass);
    const viewport = sdl_gpu.SDL_GPUViewport{ .x = 0, .y = 0, .w = @floatFromInt(self.width), .h = @floatFromInt(self.height), .min_depth = 0, .max_depth = 1 };
    sdl_gpu.SDL_SetGPUViewport(pass, &viewport);
    const uniforms = self.exposure_state.uniforms(true);
    sdl_gpu.SDL_PushGPUFragmentUniformData(cmdbuf, 0, &uniforms, @intCast(@sizeOf(render_tonemap.FrameToneMapping)));
    sdl_gpu.SDL_BindGPUGraphicsPipeline(pass, if (self.in_offscreen_frame) self.hdr_offscreen_tonemap_pipeline.? else self.hdr_tonemap_pipeline.?);
    const bindings = [_]sdl_gpu.SDL_GPUTextureSamplerBinding{.{ .texture = hdr_tex, .sampler = self.mask_sampler }};
    sdl_gpu.SDL_BindGPUFragmentSamplers(pass, 0, &bindings, 1);
    sdl_gpu.SDL_DrawGPUPrimitives(pass, 3, 1, 0, 0);
}

pub fn pollExposureReadback(self: anytype) void {
    const fence = self.exposure_fence orelse return;
    if (!sdl_gpu.SDL_QueryGPUFence(self.device, fence)) return;
    consumeCompletedExposureReadback(self);
    sdl_gpu.SDL_ReleaseGPUFence(self.device, fence);
    self.exposure_fence = null;
}

pub fn consumeCompletedExposureReadback(self: anytype) void {
    const transfer = self.exposure_transfer_buffer orelse return;
    const mapped = sdl_gpu.SDL_MapGPUTransferBuffer(self.device, transfer, false) orelse return;
    defer sdl_gpu.SDL_UnmapGPUTransferBuffer(self.device, transfer);
    const bytes = @as([*]const u8, @ptrCast(mapped))[0..4];
    const avg_log_luma = std.mem.bytesToValue(f32, bytes);
    self.exposure_state.updateFromAverageLogLuminance(avg_log_luma, engine_time.monotonicNs());
}

pub fn submitCommandBuffer(self: anytype, cmdbuf: *sdl_gpu.SDL_GPUCommandBuffer) !void {
    if (self.exposure_readback_queued) {
        const fence = sdl_gpu.SDL_SubmitGPUCommandBufferAndAcquireFence(cmdbuf) orelse return error.CommandSubmitFailed;
        self.exposure_fence = fence;
        self.exposure_readback_queued = false;
    } else if (!sdl_gpu.SDL_SubmitGPUCommandBuffer(cmdbuf)) {
        return error.CommandSubmitFailed;
    }
}

pub fn releaseQueuedExposureFence(self: anytype) void {
    if (self.exposure_fence) |fence| {
        sdl_gpu.SDL_ReleaseGPUFence(self.device, fence);
        self.exposure_fence = null;
    }
    self.exposure_readback_queued = false;
}

pub fn destroyHdrTargets(self: anytype) void {
    if (self.hdr_color_texture) |tex| {
        sdl_gpu.SDL_ReleaseGPUTexture(self.device, tex);
        self.hdr_color_texture = null;
    }
    if (self.hdr_msaa_color_texture) |tex| {
        sdl_gpu.SDL_ReleaseGPUTexture(self.device, tex);
        self.hdr_msaa_color_texture = null;
    }
    if (self.luminance_texture) |tex| {
        sdl_gpu.SDL_ReleaseGPUTexture(self.device, tex);
        self.luminance_texture = null;
    }
    self.hdr_width = 0;
    self.hdr_height = 0;
    self.hdr_sample_count = sdl_gpu.SDL_GPU_SAMPLECOUNT_1;
    self.scene_color_hdr_active = false;
    self.hdr_scene_resolved = false;
}

pub fn destroyHdrReadback(self: anytype) void {
    releaseQueuedExposureFence(self);
    if (self.exposure_transfer_buffer) |buffer| {
        sdl_gpu.SDL_ReleaseGPUTransferBuffer(self.device, buffer);
        self.exposure_transfer_buffer = null;
    }
}

pub fn destroyHdrPipelines(self: anytype) void {
    inline for (.{
        "hdr_mesh_pipeline",
        "hdr_lit_mesh_pipeline",
        "hdr_solid_mesh_pipeline",
        "hdr_double_sided_mesh_pipeline",
        "hdr_double_sided_lit_mesh_pipeline",
        "hdr_double_sided_solid_mesh_pipeline",
        "hdr_water_pipeline",
        "hdr_grass_pipeline",
        "hdr_instanced_mesh_pipeline",
        "hdr_lit_instanced_mesh_pipeline",
        "hdr_solid_instanced_mesh_pipeline",
        "hdr_grid_pipeline",
        "hdr_wireframe_pipeline",
        "hdr_sky_pipeline",
        "hdr_tonemap_pipeline",
        "hdr_offscreen_tonemap_pipeline",
        "hdr_luminance_pipeline",
    }) |field_name| {
        if (@field(self, field_name)) |pipeline| {
            sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, pipeline);
            @field(self, field_name) = null;
        }
    }
    self.hdr_pipeline_sample_count = sdl_gpu.SDL_GPU_SAMPLECOUNT_1;
}

pub fn destroyHdr(self: anytype) void {
    destroyHdrReadback(self);
    destroyHdrTargets(self);
    destroyHdrPipelines(self);
}
