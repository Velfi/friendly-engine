const std = @import("std");
const sdl_gpu = @import("sdl_gpu.zig");
const editor_math = @import("editor_math.zig");
const shared_color = @import("color.zig");
const gpu_scene = @import("gpu_scene.zig");
const types = @import("gpu_backend_sdl_types.zig");
const pipelines = @import("gpu_backend_sdl_pipelines.zig");
const upload = @import("gpu_backend_sdl_upload.zig");
const frame = @import("gpu_backend_sdl_frame.zig");
const render_settings = @import("render_settings.zig");
const render_tonemap = @import("render_tonemap.zig");
const render_commands = @import("render_commands.zig");
const render_lighting = @import("render_lighting.zig");
const render_sky = @import("render_sky.zig");
const shadow = @import("gpu_backend_sdl_shadow.zig");
const gpu_instance_buffer = @import("gpu_instance_buffer.zig");

pub const TextureSize: u32 = gpu_scene.TextureSize;

pub const GpuRenderer = struct {
    allocator: std.mem.Allocator,
    device: *sdl_gpu.SDL_GPUDevice,
    window: *sdl_gpu.SDL_Window,
    shader_format: sdl_gpu.SDL_GPUShaderFormat,
    swapchain_format: sdl_gpu.SDL_GPUTextureFormat,
    settings: render_settings.RenderSettings,
    mesh_pipeline: *sdl_gpu.SDL_GPUGraphicsPipeline,
    lit_mesh_pipeline: *sdl_gpu.SDL_GPUGraphicsPipeline,
    solid_mesh_pipeline: *sdl_gpu.SDL_GPUGraphicsPipeline,
    double_sided_mesh_pipeline: *sdl_gpu.SDL_GPUGraphicsPipeline,
    double_sided_lit_mesh_pipeline: *sdl_gpu.SDL_GPUGraphicsPipeline,
    double_sided_solid_mesh_pipeline: *sdl_gpu.SDL_GPUGraphicsPipeline,
    water_pipeline: *sdl_gpu.SDL_GPUGraphicsPipeline,
    grass_pipeline: *sdl_gpu.SDL_GPUGraphicsPipeline,
    instanced_mesh_pipeline: *sdl_gpu.SDL_GPUGraphicsPipeline,
    lit_instanced_mesh_pipeline: *sdl_gpu.SDL_GPUGraphicsPipeline,
    solid_instanced_mesh_pipeline: *sdl_gpu.SDL_GPUGraphicsPipeline,
    shadow_pipeline: *sdl_gpu.SDL_GPUGraphicsPipeline,
    instanced_shadow_pipeline: *sdl_gpu.SDL_GPUGraphicsPipeline,
    depth_prepass_pipeline: *sdl_gpu.SDL_GPUGraphicsPipeline,
    instanced_depth_prepass_pipeline: *sdl_gpu.SDL_GPUGraphicsPipeline,
    grid_pipeline: *sdl_gpu.SDL_GPUGraphicsPipeline,
    wireframe_pipeline: *sdl_gpu.SDL_GPUGraphicsPipeline,
    sky_pipeline: *sdl_gpu.SDL_GPUGraphicsPipeline,
    overlay_pipeline: *sdl_gpu.SDL_GPUGraphicsPipeline,
    overlay_mask_pipeline: *sdl_gpu.SDL_GPUGraphicsPipeline,
    overlay_sdf_pipeline: *sdl_gpu.SDL_GPUGraphicsPipeline,
    offscreen_mesh_pipeline: *sdl_gpu.SDL_GPUGraphicsPipeline,
    offscreen_lit_mesh_pipeline: *sdl_gpu.SDL_GPUGraphicsPipeline,
    offscreen_solid_mesh_pipeline: *sdl_gpu.SDL_GPUGraphicsPipeline,
    offscreen_double_sided_mesh_pipeline: *sdl_gpu.SDL_GPUGraphicsPipeline,
    offscreen_double_sided_lit_mesh_pipeline: *sdl_gpu.SDL_GPUGraphicsPipeline,
    offscreen_double_sided_solid_mesh_pipeline: *sdl_gpu.SDL_GPUGraphicsPipeline,
    offscreen_water_pipeline: *sdl_gpu.SDL_GPUGraphicsPipeline,
    offscreen_grass_pipeline: *sdl_gpu.SDL_GPUGraphicsPipeline,
    offscreen_instanced_mesh_pipeline: *sdl_gpu.SDL_GPUGraphicsPipeline,
    offscreen_lit_instanced_mesh_pipeline: *sdl_gpu.SDL_GPUGraphicsPipeline,
    offscreen_solid_instanced_mesh_pipeline: *sdl_gpu.SDL_GPUGraphicsPipeline,
    offscreen_grid_pipeline: *sdl_gpu.SDL_GPUGraphicsPipeline,
    offscreen_wireframe_pipeline: *sdl_gpu.SDL_GPUGraphicsPipeline,
    offscreen_sky_pipeline: *sdl_gpu.SDL_GPUGraphicsPipeline,
    offscreen_overlay_pipeline: *sdl_gpu.SDL_GPUGraphicsPipeline,
    offscreen_overlay_mask_pipeline: *sdl_gpu.SDL_GPUGraphicsPipeline,
    offscreen_overlay_sdf_pipeline: *sdl_gpu.SDL_GPUGraphicsPipeline,
    hdr_mesh_pipeline: ?*sdl_gpu.SDL_GPUGraphicsPipeline = null,
    hdr_lit_mesh_pipeline: ?*sdl_gpu.SDL_GPUGraphicsPipeline = null,
    hdr_solid_mesh_pipeline: ?*sdl_gpu.SDL_GPUGraphicsPipeline = null,
    hdr_double_sided_mesh_pipeline: ?*sdl_gpu.SDL_GPUGraphicsPipeline = null,
    hdr_double_sided_lit_mesh_pipeline: ?*sdl_gpu.SDL_GPUGraphicsPipeline = null,
    hdr_double_sided_solid_mesh_pipeline: ?*sdl_gpu.SDL_GPUGraphicsPipeline = null,
    hdr_water_pipeline: ?*sdl_gpu.SDL_GPUGraphicsPipeline = null,
    hdr_grass_pipeline: ?*sdl_gpu.SDL_GPUGraphicsPipeline = null,
    hdr_instanced_mesh_pipeline: ?*sdl_gpu.SDL_GPUGraphicsPipeline = null,
    hdr_lit_instanced_mesh_pipeline: ?*sdl_gpu.SDL_GPUGraphicsPipeline = null,
    hdr_solid_instanced_mesh_pipeline: ?*sdl_gpu.SDL_GPUGraphicsPipeline = null,
    hdr_grid_pipeline: ?*sdl_gpu.SDL_GPUGraphicsPipeline = null,
    hdr_wireframe_pipeline: ?*sdl_gpu.SDL_GPUGraphicsPipeline = null,
    hdr_sky_pipeline: ?*sdl_gpu.SDL_GPUGraphicsPipeline = null,
    hdr_tonemap_pipeline: ?*sdl_gpu.SDL_GPUGraphicsPipeline = null,
    hdr_offscreen_tonemap_pipeline: ?*sdl_gpu.SDL_GPUGraphicsPipeline = null,
    hdr_luminance_pipeline: ?*sdl_gpu.SDL_GPUGraphicsPipeline = null,
    hdr_pipeline_sample_count: sdl_gpu.SDL_GPUSampleCount = sdl_gpu.SDL_GPU_SAMPLECOUNT_1,
    sampler: *sdl_gpu.SDL_GPUSampler,
    mask_sampler: *sdl_gpu.SDL_GPUSampler,
    shadow_compare_sampler: *sdl_gpu.SDL_GPUSampler,
    white_texture: *sdl_gpu.SDL_GPUTexture,
    shadow_map_texture: ?*sdl_gpu.SDL_GPUTexture = null,
    shadow_map_size: u32 = 0,
    frame_lighting: render_lighting.FrameLighting = .{},
    frame_sky: render_sky.FrameSky = .{},
    light_view_proj: editor_math.Mat4 = editor_math.Mat4.identity(),
    grid_vertex_buffer: *sdl_gpu.SDL_GPUBuffer,
    grid_vertex_count: u32,
    depth_texture: ?*sdl_gpu.SDL_GPUTexture = null,
    depth_width: u32 = 0,
    depth_height: u32 = 0,
    depth_sample_count: sdl_gpu.SDL_GPUSampleCount = sdl_gpu.SDL_GPU_SAMPLECOUNT_1,
    water_depth_texture: ?*sdl_gpu.SDL_GPUTexture = null,
    water_depth_width: u32 = 0,
    water_depth_height: u32 = 0,
    frame_msaa_color_texture: ?*sdl_gpu.SDL_GPUTexture = null,
    frame_msaa_width: u32 = 0,
    frame_msaa_height: u32 = 0,
    offscreen_color_texture: ?*sdl_gpu.SDL_GPUTexture = null,
    offscreen_msaa_color_texture: ?*sdl_gpu.SDL_GPUTexture = null,
    offscreen_width: u32 = 0,
    offscreen_height: u32 = 0,
    offscreen_sample_count: sdl_gpu.SDL_GPUSampleCount = sdl_gpu.SDL_GPU_SAMPLECOUNT_1,
    hdr_color_texture: ?*sdl_gpu.SDL_GPUTexture = null,
    hdr_msaa_color_texture: ?*sdl_gpu.SDL_GPUTexture = null,
    luminance_texture: ?*sdl_gpu.SDL_GPUTexture = null,
    hdr_width: u32 = 0,
    hdr_height: u32 = 0,
    hdr_sample_count: sdl_gpu.SDL_GPUSampleCount = sdl_gpu.SDL_GPU_SAMPLECOUNT_1,
    hdr_supported: bool = true,
    scene_color_hdr_active: bool = false,
    hdr_scene_resolved: bool = false,
    exposure_transfer_buffer: ?*sdl_gpu.SDL_GPUTransferBuffer = null,
    exposure_fence: ?*sdl_gpu.SDL_GPUFence = null,
    exposure_readback_queued: bool = false,
    exposure_state: render_tonemap.ExposureState = .{},
    download_transfer_buffer: ?*sdl_gpu.SDL_GPUTransferBuffer = null,
    download_buffer_bytes: u32 = 0,
    in_offscreen_frame: bool = false,
    meshes: std.ArrayList(types.SdlGpuMesh),
    overlay_textures: std.ArrayList(*sdl_gpu.SDL_GPUTexture),
    overlay_vertex_buffer: ?*sdl_gpu.SDL_GPUBuffer = null,
    overlay_vertex_capacity_bytes: u32 = 0,
    instance_buffer: ?*sdl_gpu.SDL_GPUBuffer = null,
    instance_buffer_capacity: usize = 0,
    cached_object_count: usize = 0,
    cached_scene_hash: u64 = 0,
    width: u32 = 1,
    height: u32 = 1,
    cmdbuf: ?*sdl_gpu.SDL_GPUCommandBuffer = null,
    render_pass: ?*sdl_gpu.SDL_GPURenderPass = null,
    swapchain_texture: ?*sdl_gpu.SDL_GPUTexture = null,
    last_command_stats: render_commands.Stats = .{},
    last_swapchain_acquire_ms: f64 = 0,
    grass_time_seconds: f32 = 0,

    pub fn init(
        allocator: std.mem.Allocator,
        device: *sdl_gpu.SDL_GPUDevice,
        window: *sdl_gpu.SDL_Window,
    ) !GpuRenderer {
        return initWithSettings(allocator, device, window, .{});
    }

    pub fn initWithSettings(
        allocator: std.mem.Allocator,
        device: *sdl_gpu.SDL_GPUDevice,
        window: *sdl_gpu.SDL_Window,
        settings: render_settings.RenderSettings,
    ) !GpuRenderer {
        const shader_format = sdl_gpu.activeShaderFormat(device);
        if (shader_format == sdl_gpu.SDL_GPU_SHADERFORMAT_INVALID) return error.NoSupportedShaderFormat;

        const swapchain_format = sdl_gpu.SDL_GetGPUSwapchainTextureFormat(device, window);
        const sample_count = settings.sampleCount();
        try ensureSampleCountSupported(device, swapchain_format, sample_count);
        try ensureSampleCountSupported(device, sdl_gpu.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM, sample_count);
        try ensureSampleCountSupported(device, sdl_gpu.SDL_GPU_TEXTUREFORMAT_D32_FLOAT, sample_count);

        const mesh_pipeline = try pipelines.createMeshPipeline(device, swapchain_format, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(device, mesh_pipeline);

        const lit_mesh_pipeline = try pipelines.createLitMeshPipeline(device, swapchain_format, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(device, lit_mesh_pipeline);

        const solid_mesh_pipeline = try pipelines.createSolidMeshPipeline(device, swapchain_format, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(device, solid_mesh_pipeline);

        const double_sided_mesh_pipeline = try pipelines.createDoubleSidedMeshPipeline(device, swapchain_format, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(device, double_sided_mesh_pipeline);

        const double_sided_lit_mesh_pipeline = try pipelines.createDoubleSidedLitMeshPipeline(device, swapchain_format, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(device, double_sided_lit_mesh_pipeline);

        const double_sided_solid_mesh_pipeline = try pipelines.createDoubleSidedSolidMeshPipeline(device, swapchain_format, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(device, double_sided_solid_mesh_pipeline);

        const water_pipeline = try pipelines.createWaterPipeline(device, swapchain_format, sdl_gpu.SDL_GPU_SAMPLECOUNT_1);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(device, water_pipeline);

        const grass_pipeline = try pipelines.createGrassPipeline(device, swapchain_format, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(device, grass_pipeline);

        const instanced_mesh_pipeline = try pipelines.createInstancedMeshPipeline(device, swapchain_format, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(device, instanced_mesh_pipeline);

        const lit_instanced_mesh_pipeline = try pipelines.createLitInstancedMeshPipeline(device, swapchain_format, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(device, lit_instanced_mesh_pipeline);

        const solid_instanced_mesh_pipeline = try pipelines.createSolidInstancedMeshPipeline(device, swapchain_format, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(device, solid_instanced_mesh_pipeline);

        const shadow_pipeline = try pipelines.createShadowPipeline(device);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(device, shadow_pipeline);

        const instanced_shadow_pipeline = try pipelines.createInstancedShadowPipeline(device);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(device, instanced_shadow_pipeline);

        const depth_prepass_pipeline = try pipelines.createDepthPrepassPipeline(device);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(device, depth_prepass_pipeline);

        const instanced_depth_prepass_pipeline = try pipelines.createInstancedDepthPrepassPipeline(device);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(device, instanced_depth_prepass_pipeline);

        const grid_pipeline = try pipelines.createGridPipeline(device, swapchain_format, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(device, grid_pipeline);

        const wireframe_pipeline = try pipelines.createWireframePipeline(device, swapchain_format, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(device, wireframe_pipeline);

        const sky_pipeline = try pipelines.createSkyPipeline(device, swapchain_format, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(device, sky_pipeline);

        const overlay_pipeline = try pipelines.createOverlayPipeline(device, swapchain_format);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(device, overlay_pipeline);

        const overlay_mask_pipeline = try pipelines.createOverlayMaskPipeline(device, swapchain_format);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(device, overlay_mask_pipeline);

        const overlay_sdf_pipeline = try pipelines.createOverlaySdfPipeline(device, swapchain_format);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(device, overlay_sdf_pipeline);

        const offscreen_format = sdl_gpu.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM;
        const offscreen_mesh_pipeline = try pipelines.createMeshPipeline(device, offscreen_format, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(device, offscreen_mesh_pipeline);

        const offscreen_lit_mesh_pipeline = try pipelines.createLitMeshPipeline(device, offscreen_format, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(device, offscreen_lit_mesh_pipeline);

        const offscreen_solid_mesh_pipeline = try pipelines.createSolidMeshPipeline(device, offscreen_format, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(device, offscreen_solid_mesh_pipeline);

        const offscreen_double_sided_mesh_pipeline = try pipelines.createDoubleSidedMeshPipeline(device, offscreen_format, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(device, offscreen_double_sided_mesh_pipeline);

        const offscreen_double_sided_lit_mesh_pipeline = try pipelines.createDoubleSidedLitMeshPipeline(device, offscreen_format, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(device, offscreen_double_sided_lit_mesh_pipeline);

        const offscreen_double_sided_solid_mesh_pipeline = try pipelines.createDoubleSidedSolidMeshPipeline(device, offscreen_format, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(device, offscreen_double_sided_solid_mesh_pipeline);

        const offscreen_water_pipeline = try pipelines.createWaterPipeline(device, offscreen_format, sdl_gpu.SDL_GPU_SAMPLECOUNT_1);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(device, offscreen_water_pipeline);

        const offscreen_grass_pipeline = try pipelines.createGrassPipeline(device, offscreen_format, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(device, offscreen_grass_pipeline);

        const offscreen_instanced_mesh_pipeline = try pipelines.createInstancedMeshPipeline(device, offscreen_format, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(device, offscreen_instanced_mesh_pipeline);

        const offscreen_lit_instanced_mesh_pipeline = try pipelines.createLitInstancedMeshPipeline(device, offscreen_format, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(device, offscreen_lit_instanced_mesh_pipeline);

        const offscreen_solid_instanced_mesh_pipeline = try pipelines.createSolidInstancedMeshPipeline(device, offscreen_format, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(device, offscreen_solid_instanced_mesh_pipeline);

        const offscreen_grid_pipeline = try pipelines.createGridPipeline(device, offscreen_format, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(device, offscreen_grid_pipeline);

        const offscreen_wireframe_pipeline = try pipelines.createWireframePipeline(device, offscreen_format, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(device, offscreen_wireframe_pipeline);

        const offscreen_sky_pipeline = try pipelines.createSkyPipeline(device, offscreen_format, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(device, offscreen_sky_pipeline);

        const offscreen_overlay_pipeline = try pipelines.createOverlayPipeline(device, offscreen_format);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(device, offscreen_overlay_pipeline);

        const offscreen_overlay_mask_pipeline = try pipelines.createOverlayMaskPipeline(device, offscreen_format);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(device, offscreen_overlay_mask_pipeline);

        const offscreen_overlay_sdf_pipeline = try pipelines.createOverlaySdfPipeline(device, offscreen_format);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(device, offscreen_overlay_sdf_pipeline);

        const sampler = sdl_gpu.SDL_CreateGPUSampler(device, &.{
            .min_filter = sdl_gpu.SDL_GPU_FILTER_LINEAR,
            .mag_filter = sdl_gpu.SDL_GPU_FILTER_LINEAR,
            .mipmap_mode = sdl_gpu.SDL_GPU_SAMPLERMIPMAPMODE_NEAREST,
            .address_mode_u = sdl_gpu.SDL_GPU_SAMPLERADDRESSMODE_REPEAT,
            .address_mode_v = sdl_gpu.SDL_GPU_SAMPLERADDRESSMODE_REPEAT,
            .address_mode_w = sdl_gpu.SDL_GPU_SAMPLERADDRESSMODE_REPEAT,
        }) orelse return error.SamplerCreateFailed;
        errdefer sdl_gpu.SDL_ReleaseGPUSampler(device, sampler);

        const mask_sampler = sdl_gpu.SDL_CreateGPUSampler(device, &.{
            .min_filter = sdl_gpu.SDL_GPU_FILTER_LINEAR,
            .mag_filter = sdl_gpu.SDL_GPU_FILTER_LINEAR,
            .mipmap_mode = sdl_gpu.SDL_GPU_SAMPLERMIPMAPMODE_NEAREST,
            .address_mode_u = sdl_gpu.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
            .address_mode_v = sdl_gpu.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
            .address_mode_w = sdl_gpu.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        }) orelse return error.SamplerCreateFailed;
        errdefer sdl_gpu.SDL_ReleaseGPUSampler(device, mask_sampler);

        const shadow_compare_sampler = sdl_gpu.SDL_CreateGPUSampler(device, &.{
            .min_filter = sdl_gpu.SDL_GPU_FILTER_LINEAR,
            .mag_filter = sdl_gpu.SDL_GPU_FILTER_LINEAR,
            .mipmap_mode = sdl_gpu.SDL_GPU_SAMPLERMIPMAPMODE_NEAREST,
            .address_mode_u = sdl_gpu.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
            .address_mode_v = sdl_gpu.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
            .address_mode_w = sdl_gpu.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
            .compare_op = sdl_gpu.SDL_GPU_COMPAREOP_LESS_OR_EQUAL,
            .enable_compare = true,
        }) orelse return error.SamplerCreateFailed;
        errdefer sdl_gpu.SDL_ReleaseGPUSampler(device, shadow_compare_sampler);

        var renderer = GpuRenderer{
            .allocator = allocator,
            .device = device,
            .window = window,
            .shader_format = shader_format,
            .swapchain_format = swapchain_format,
            .settings = settings,
            .mesh_pipeline = mesh_pipeline,
            .lit_mesh_pipeline = lit_mesh_pipeline,
            .solid_mesh_pipeline = solid_mesh_pipeline,
            .double_sided_mesh_pipeline = double_sided_mesh_pipeline,
            .double_sided_lit_mesh_pipeline = double_sided_lit_mesh_pipeline,
            .double_sided_solid_mesh_pipeline = double_sided_solid_mesh_pipeline,
            .water_pipeline = water_pipeline,
            .grass_pipeline = grass_pipeline,
            .instanced_mesh_pipeline = instanced_mesh_pipeline,
            .lit_instanced_mesh_pipeline = lit_instanced_mesh_pipeline,
            .solid_instanced_mesh_pipeline = solid_instanced_mesh_pipeline,
            .shadow_pipeline = shadow_pipeline,
            .instanced_shadow_pipeline = instanced_shadow_pipeline,
            .depth_prepass_pipeline = depth_prepass_pipeline,
            .instanced_depth_prepass_pipeline = instanced_depth_prepass_pipeline,
            .grid_pipeline = grid_pipeline,
            .wireframe_pipeline = wireframe_pipeline,
            .sky_pipeline = sky_pipeline,
            .overlay_pipeline = overlay_pipeline,
            .overlay_mask_pipeline = overlay_mask_pipeline,
            .overlay_sdf_pipeline = overlay_sdf_pipeline,
            .offscreen_mesh_pipeline = offscreen_mesh_pipeline,
            .offscreen_lit_mesh_pipeline = offscreen_lit_mesh_pipeline,
            .offscreen_solid_mesh_pipeline = offscreen_solid_mesh_pipeline,
            .offscreen_double_sided_mesh_pipeline = offscreen_double_sided_mesh_pipeline,
            .offscreen_double_sided_lit_mesh_pipeline = offscreen_double_sided_lit_mesh_pipeline,
            .offscreen_double_sided_solid_mesh_pipeline = offscreen_double_sided_solid_mesh_pipeline,
            .offscreen_water_pipeline = offscreen_water_pipeline,
            .offscreen_grass_pipeline = offscreen_grass_pipeline,
            .offscreen_instanced_mesh_pipeline = offscreen_instanced_mesh_pipeline,
            .offscreen_lit_instanced_mesh_pipeline = offscreen_lit_instanced_mesh_pipeline,
            .offscreen_solid_instanced_mesh_pipeline = offscreen_solid_instanced_mesh_pipeline,
            .offscreen_grid_pipeline = offscreen_grid_pipeline,
            .offscreen_wireframe_pipeline = offscreen_wireframe_pipeline,
            .offscreen_sky_pipeline = offscreen_sky_pipeline,
            .offscreen_overlay_pipeline = offscreen_overlay_pipeline,
            .offscreen_overlay_mask_pipeline = offscreen_overlay_mask_pipeline,
            .offscreen_overlay_sdf_pipeline = offscreen_overlay_sdf_pipeline,
            .sampler = sampler,
            .mask_sampler = mask_sampler,
            .shadow_compare_sampler = shadow_compare_sampler,
            .white_texture = undefined,
            .grid_vertex_buffer = undefined,
            .grid_vertex_count = 0,
            .offscreen_sample_count = sample_count,
            .meshes = .empty,
            .overlay_textures = .empty,
        };
        renderer.white_texture = try upload.createSolidTexture(&renderer, 255, 255, 255, 255);
        errdefer sdl_gpu.SDL_ReleaseGPUTexture(device, renderer.white_texture);
        try upload.initGrid(&renderer);
        try shadow.ensureShadowMap(&renderer, settings.shadows.mapResolution());
        renderer.frame_lighting.shadows_enabled = settings.shadowsEnabled();
        return renderer;
    }

    pub fn deinit(self: *GpuRenderer) void {
        upload.clearMeshes(self);
        gpu_instance_buffer.releaseInstanceBuffer(self);
        frame.clearOverlayScratch(self);
        frame.destroyFrameMsaa(self);
        frame.destroyOffscreen(self);
        frame.destroyWaterDepth(self);
        frame.destroyHdr(self);
        self.hdr_supported = true;
        frame.destroyHdr(self);
        if (self.depth_texture) |tex| {
            sdl_gpu.SDL_ReleaseGPUTexture(self.device, tex);
            self.depth_texture = null;
        }
        if (self.shadow_map_texture) |tex| {
            sdl_gpu.SDL_ReleaseGPUTexture(self.device, tex);
            self.shadow_map_texture = null;
        }
        sdl_gpu.SDL_ReleaseGPUSampler(self.device, self.shadow_compare_sampler);
        sdl_gpu.SDL_ReleaseGPUSampler(self.device, self.mask_sampler);
        sdl_gpu.SDL_ReleaseGPUBuffer(self.device, self.grid_vertex_buffer);
        sdl_gpu.SDL_ReleaseGPUTexture(self.device, self.white_texture);
        sdl_gpu.SDL_ReleaseGPUSampler(self.device, self.sampler);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.instanced_depth_prepass_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.depth_prepass_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.instanced_shadow_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.shadow_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.offscreen_solid_instanced_mesh_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.offscreen_lit_instanced_mesh_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.solid_instanced_mesh_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.lit_instanced_mesh_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.offscreen_instanced_mesh_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.instanced_mesh_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.offscreen_solid_mesh_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.offscreen_lit_mesh_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.offscreen_double_sided_solid_mesh_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.offscreen_water_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.offscreen_grass_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.offscreen_double_sided_lit_mesh_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.offscreen_double_sided_mesh_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.solid_mesh_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.lit_mesh_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.double_sided_solid_mesh_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.water_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.grass_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.double_sided_lit_mesh_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.double_sided_mesh_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.offscreen_grid_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.offscreen_wireframe_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.offscreen_sky_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.offscreen_mesh_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.offscreen_overlay_mask_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.offscreen_overlay_sdf_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.offscreen_overlay_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.overlay_mask_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.overlay_sdf_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.overlay_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.grid_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.wireframe_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.sky_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.mesh_pipeline);
    }

    pub fn backendName(self: *const GpuRenderer) []const u8 {
        return sdl_gpu.backendName(self.shader_format);
    }

    pub fn renderSettings(self: *const GpuRenderer) render_settings.RenderSettings {
        return self.settings;
    }

    pub fn setFrameLighting(self: *GpuRenderer, lighting: render_lighting.FrameLighting) void {
        self.frame_lighting = lighting;
        self.frame_lighting.shadows_enabled = self.settings.shadowsEnabled() and lighting.shadows_enabled;
    }

    pub fn setFrameSky(self: *GpuRenderer, sky: render_sky.FrameSky) void {
        self.frame_sky = sky;
    }

    pub fn setRenderSettings(self: *GpuRenderer, settings: render_settings.RenderSettings) !void {
        if (self.settings.antialiasing == settings.antialiasing and self.settings.shadows == settings.shadows and self.settings.color_pipeline == settings.color_pipeline) return;
        if (self.render_pass != null or self.cmdbuf != null) return error.RenderSettingsChangedDuringFrame;

        if (self.settings.antialiasing == settings.antialiasing and self.settings.shadows == settings.shadows) {
            self.settings = settings;
            self.frame_lighting.shadows_enabled = settings.shadowsEnabled();
            if (!settings.hdrEnabled()) frame.destroyHdr(self);
            self.hdr_supported = true;
            return;
        }

        const sample_count = settings.sampleCount();
        try ensureSampleCountSupported(self.device, self.swapchain_format, sample_count);
        try ensureSampleCountSupported(self.device, sdl_gpu.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM, sample_count);
        try ensureSampleCountSupported(self.device, sdl_gpu.SDL_GPU_TEXTUREFORMAT_D32_FLOAT, sample_count);

        const mesh_pipeline = try pipelines.createMeshPipeline(self.device, self.swapchain_format, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, mesh_pipeline);
        const lit_mesh_pipeline = try pipelines.createLitMeshPipeline(self.device, self.swapchain_format, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, lit_mesh_pipeline);
        const solid_mesh_pipeline = try pipelines.createSolidMeshPipeline(self.device, self.swapchain_format, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, solid_mesh_pipeline);
        const double_sided_mesh_pipeline = try pipelines.createDoubleSidedMeshPipeline(self.device, self.swapchain_format, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, double_sided_mesh_pipeline);
        const double_sided_lit_mesh_pipeline = try pipelines.createDoubleSidedLitMeshPipeline(self.device, self.swapchain_format, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, double_sided_lit_mesh_pipeline);
        const double_sided_solid_mesh_pipeline = try pipelines.createDoubleSidedSolidMeshPipeline(self.device, self.swapchain_format, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, double_sided_solid_mesh_pipeline);
        const water_pipeline = try pipelines.createWaterPipeline(self.device, self.swapchain_format, sdl_gpu.SDL_GPU_SAMPLECOUNT_1);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, water_pipeline);
        const grass_pipeline = try pipelines.createGrassPipeline(self.device, self.swapchain_format, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, grass_pipeline);
        const instanced_mesh_pipeline = try pipelines.createInstancedMeshPipeline(self.device, self.swapchain_format, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, instanced_mesh_pipeline);
        const lit_instanced_mesh_pipeline = try pipelines.createLitInstancedMeshPipeline(self.device, self.swapchain_format, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, lit_instanced_mesh_pipeline);
        const solid_instanced_mesh_pipeline = try pipelines.createSolidInstancedMeshPipeline(self.device, self.swapchain_format, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, solid_instanced_mesh_pipeline);
        const grid_pipeline = try pipelines.createGridPipeline(self.device, self.swapchain_format, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, grid_pipeline);
        const wireframe_pipeline = try pipelines.createWireframePipeline(self.device, self.swapchain_format, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, wireframe_pipeline);
        const sky_pipeline = try pipelines.createSkyPipeline(self.device, self.swapchain_format, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, sky_pipeline);
        const offscreen_mesh_pipeline = try pipelines.createMeshPipeline(self.device, sdl_gpu.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, offscreen_mesh_pipeline);
        const offscreen_lit_mesh_pipeline = try pipelines.createLitMeshPipeline(self.device, sdl_gpu.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, offscreen_lit_mesh_pipeline);
        const offscreen_solid_mesh_pipeline = try pipelines.createSolidMeshPipeline(self.device, sdl_gpu.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, offscreen_solid_mesh_pipeline);
        const offscreen_double_sided_mesh_pipeline = try pipelines.createDoubleSidedMeshPipeline(self.device, sdl_gpu.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, offscreen_double_sided_mesh_pipeline);
        const offscreen_double_sided_lit_mesh_pipeline = try pipelines.createDoubleSidedLitMeshPipeline(self.device, sdl_gpu.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, offscreen_double_sided_lit_mesh_pipeline);
        const offscreen_double_sided_solid_mesh_pipeline = try pipelines.createDoubleSidedSolidMeshPipeline(self.device, sdl_gpu.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, offscreen_double_sided_solid_mesh_pipeline);
        const offscreen_water_pipeline = try pipelines.createWaterPipeline(self.device, sdl_gpu.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM, sdl_gpu.SDL_GPU_SAMPLECOUNT_1);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, offscreen_water_pipeline);
        const offscreen_grass_pipeline = try pipelines.createGrassPipeline(self.device, sdl_gpu.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, offscreen_grass_pipeline);
        const offscreen_instanced_mesh_pipeline = try pipelines.createInstancedMeshPipeline(self.device, sdl_gpu.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, offscreen_instanced_mesh_pipeline);
        const offscreen_lit_instanced_mesh_pipeline = try pipelines.createLitInstancedMeshPipeline(self.device, sdl_gpu.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, offscreen_lit_instanced_mesh_pipeline);
        const offscreen_solid_instanced_mesh_pipeline = try pipelines.createSolidInstancedMeshPipeline(self.device, sdl_gpu.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM, sample_count);
        errdefer sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, offscreen_solid_instanced_mesh_pipeline);
        const offscreen_grid_pipeline = try pipelines.createGridPipeline(self.device, sdl_gpu.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM, sample_count);
        const offscreen_wireframe_pipeline = try pipelines.createWireframePipeline(self.device, sdl_gpu.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM, sample_count);
        const offscreen_sky_pipeline = try pipelines.createSkyPipeline(self.device, sdl_gpu.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM, sample_count);

        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.mesh_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.lit_mesh_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.solid_mesh_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.double_sided_mesh_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.double_sided_lit_mesh_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.double_sided_solid_mesh_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.water_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.grass_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.instanced_mesh_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.lit_instanced_mesh_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.solid_instanced_mesh_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.grid_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.wireframe_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.sky_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.offscreen_mesh_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.offscreen_lit_mesh_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.offscreen_solid_mesh_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.offscreen_double_sided_mesh_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.offscreen_double_sided_lit_mesh_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.offscreen_double_sided_solid_mesh_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.offscreen_water_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.offscreen_grass_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.offscreen_instanced_mesh_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.offscreen_lit_instanced_mesh_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.offscreen_solid_instanced_mesh_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.offscreen_grid_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.offscreen_wireframe_pipeline);
        sdl_gpu.SDL_ReleaseGPUGraphicsPipeline(self.device, self.offscreen_sky_pipeline);
        self.mesh_pipeline = mesh_pipeline;
        self.lit_mesh_pipeline = lit_mesh_pipeline;
        self.solid_mesh_pipeline = solid_mesh_pipeline;
        self.double_sided_mesh_pipeline = double_sided_mesh_pipeline;
        self.double_sided_lit_mesh_pipeline = double_sided_lit_mesh_pipeline;
        self.double_sided_solid_mesh_pipeline = double_sided_solid_mesh_pipeline;
        self.water_pipeline = water_pipeline;
        self.grass_pipeline = grass_pipeline;
        self.instanced_mesh_pipeline = instanced_mesh_pipeline;
        self.lit_instanced_mesh_pipeline = lit_instanced_mesh_pipeline;
        self.solid_instanced_mesh_pipeline = solid_instanced_mesh_pipeline;
        self.grid_pipeline = grid_pipeline;
        self.wireframe_pipeline = wireframe_pipeline;
        self.sky_pipeline = sky_pipeline;
        self.offscreen_mesh_pipeline = offscreen_mesh_pipeline;
        self.offscreen_lit_mesh_pipeline = offscreen_lit_mesh_pipeline;
        self.offscreen_solid_mesh_pipeline = offscreen_solid_mesh_pipeline;
        self.offscreen_double_sided_mesh_pipeline = offscreen_double_sided_mesh_pipeline;
        self.offscreen_double_sided_lit_mesh_pipeline = offscreen_double_sided_lit_mesh_pipeline;
        self.offscreen_double_sided_solid_mesh_pipeline = offscreen_double_sided_solid_mesh_pipeline;
        self.offscreen_water_pipeline = offscreen_water_pipeline;
        self.offscreen_grass_pipeline = offscreen_grass_pipeline;
        self.offscreen_instanced_mesh_pipeline = offscreen_instanced_mesh_pipeline;
        self.offscreen_lit_instanced_mesh_pipeline = offscreen_lit_instanced_mesh_pipeline;
        self.offscreen_solid_instanced_mesh_pipeline = offscreen_solid_instanced_mesh_pipeline;
        self.offscreen_grid_pipeline = offscreen_grid_pipeline;
        self.offscreen_wireframe_pipeline = offscreen_wireframe_pipeline;
        self.offscreen_sky_pipeline = offscreen_sky_pipeline;
        self.settings = settings;
        self.offscreen_sample_count = sample_count;
        self.frame_lighting.shadows_enabled = settings.shadowsEnabled();
        frame.destroyFrameMsaa(self);
        frame.destroyOffscreen(self);
        frame.destroyWaterDepth(self);
        frame.destroyHdr(self);
        self.hdr_supported = true;
        if (self.shadow_map_texture) |tex| {
            sdl_gpu.SDL_ReleaseGPUTexture(self.device, tex);
            self.shadow_map_texture = null;
            self.shadow_map_size = 0;
        }
        try shadow.ensureShadowMap(self, settings.shadows.mapResolution());
        if (self.depth_texture) |tex| {
            sdl_gpu.SDL_ReleaseGPUTexture(self.device, tex);
            self.depth_texture = null;
        }
        self.depth_width = 0;
        self.depth_height = 0;
        self.depth_sample_count = sdl_gpu.SDL_GPU_SAMPLECOUNT_1;
    }

    pub fn beginOffscreenFrame(self: *GpuRenderer, width: u32, height: u32, clear: shared_color.Color) !void {
        return frame.beginOffscreenFrame(self, width, height, clear);
    }

    pub fn endOffscreenFrame(self: *GpuRenderer) void {
        frame.endOffscreenFrame(self);
    }

    pub fn readOffscreenPixels(self: *GpuRenderer, dest: []u8) void {
        frame.readOffscreenPixels(self, dest);
    }

    pub fn offscreenColorTexture(self: *const GpuRenderer) ?*sdl_gpu.SDL_GPUTexture {
        return self.offscreen_color_texture;
    }

    pub fn offscreenWidth(self: *const GpuRenderer) u32 {
        return self.offscreen_width;
    }

    pub fn offscreenHeight(self: *const GpuRenderer) u32 {
        return self.offscreen_height;
    }

    pub fn beginFrame(self: *GpuRenderer, width: u32, height: u32, clear: shared_color.Color) !void {
        return frame.beginFrame(self, width, height, clear);
    }

    pub fn drawGrid(self: *GpuRenderer, camera: editor_math.OrbitCamera) void {
        frame.drawGrid(self, editor_math.GridDraw.anchored(camera, camera.target, 1.0));
    }

    pub fn syncSceneObjects(self: *GpuRenderer, objects: []const gpu_scene.SceneGpuObject) !void {
        return upload.syncSceneObjects(self, objects);
    }

    pub fn drawMeshByIndex(self: *GpuRenderer, index: usize, transform: [16]f32, camera: editor_math.OrbitCamera) !void {
        try frame.drawMeshByIndex(self, index, transform, camera);
    }

    pub fn drawOverlayQuads(self: *GpuRenderer, quads: []const gpu_scene.OverlayQuad) !void {
        try frame.drawOverlayQuads(self, quads);
    }

    pub fn createOverlayTextureFromRgba(self: *GpuRenderer, rgba: []const u8, width: u32, height: u32) !*sdl_gpu.SDL_GPUTexture {
        return frame.createOverlayTextureFromRgba(self, rgba, width, height);
    }

    pub fn updateOverlayTextureFromRgba(self: *GpuRenderer, texture: *sdl_gpu.SDL_GPUTexture, rgba: []const u8, width: u32, height: u32) !void {
        try frame.updateOverlayTextureFromRgba(self, texture, rgba, width, height);
    }

    pub fn releaseOverlayTexture(self: *GpuRenderer, texture: *sdl_gpu.SDL_GPUTexture) void {
        sdl_gpu.SDL_ReleaseGPUTexture(self.device, texture);
    }

    pub fn submitCommands(self: *GpuRenderer, command_buffer: *render_commands.CommandBuffer) !void {
        self.grass_time_seconds += 1.0 / 60.0;
        try frame.submitCommands(self, command_buffer);
    }

    pub fn lastCommandStats(self: *const GpuRenderer) render_commands.Stats {
        return self.last_command_stats;
    }

    pub fn uploadedMeshStats(self: *const GpuRenderer) types.UploadedMeshStats {
        var stats: types.UploadedMeshStats = .{
            .meshes = @intCast(self.meshes.items.len),
        };
        for (self.meshes.items) |mesh| {
            stats.indexed_primitives += mesh.index_count / 3;
            stats.wireframe_indices += mesh.wireframe_index_count;
        }
        return stats;
    }

    pub fn endFrame(self: *GpuRenderer) !void {
        return frame.endFrame(self);
    }

    pub fn lastSwapchainAcquireMs(self: *const GpuRenderer) f64 {
        return self.last_swapchain_acquire_ms;
    }

    pub fn capturePresentedFrameAndEndFrame(self: *GpuRenderer, dest: []u8) !void {
        return frame.capturePresentedFrameAndEndFrame(self, dest);
    }
};

fn configureEditorPresentMode(device: *sdl_gpu.SDL_GPUDevice, window: *sdl_gpu.SDL_Window) void {
    const preferred = [_]sdl_gpu.SDL_GPUPresentMode{
        sdl_gpu.SDL_GPU_PRESENTMODE_MAILBOX,
        sdl_gpu.SDL_GPU_PRESENTMODE_IMMEDIATE,
        sdl_gpu.SDL_GPU_PRESENTMODE_VSYNC,
    };
    for (preferred) |mode| {
        if (!sdl_gpu.SDL_WindowSupportsGPUPresentMode(device, window, mode)) continue;
        if (sdl_gpu.SDL_SetGPUSwapchainParameters(device, window, sdl_gpu.SDL_GPU_SWAPCHAINCOMPOSITION_SDR, mode)) return;
    }
}

fn ensureSampleCountSupported(
    device: *sdl_gpu.SDL_GPUDevice,
    format: sdl_gpu.SDL_GPUTextureFormat,
    sample_count: sdl_gpu.SDL_GPUSampleCount,
) !void {
    if (sample_count == sdl_gpu.SDL_GPU_SAMPLECOUNT_1) return;
    if (!sdl_gpu.SDL_GPUTextureSupportsSampleCount(device, format, sample_count)) {
        return error.RenderSampleCountUnsupported;
    }
}
