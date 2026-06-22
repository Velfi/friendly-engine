const sdl_gpu = @import("sdl_gpu.zig");
const types = @import("gpu_backend_sdl_types.zig");
const gpu_instance_buffer = @import("gpu_instance_buffer.zig");
const editor_math = @import("editor_math.zig");
const render_commands = @import("render_commands.zig");
const render_lighting = @import("render_lighting.zig");
const render_visibility = @import("render_visibility.zig");
const pipelines = @import("gpu_backend_sdl_pipelines.zig");

pub const MeshVertexUniforms = extern struct {
    mvp: [16]f32,
    model: [16]f32,
};

pub const ShadowVertexUniforms = extern struct {
    light_mvp: [16]f32,
};

pub fn ensureShadowMap(self: anytype, size: u32) !void {
    const effective_size = if (size == 0) 1 else size;
    if (self.shadow_map_texture != null and self.shadow_map_size == effective_size) return;

    if (self.shadow_map_texture) |tex| {
        sdl_gpu.SDL_ReleaseGPUTexture(self.device, tex);
        self.shadow_map_texture = null;
    }

    const tex = sdl_gpu.SDL_CreateGPUTexture(self.device, &.{
        .type = sdl_gpu.SDL_GPU_TEXTURETYPE_2D,
        .format = sdl_gpu.SDL_GPU_TEXTUREFORMAT_D16_UNORM,
        .usage = sdl_gpu.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET | sdl_gpu.SDL_GPU_TEXTUREUSAGE_SAMPLER,
        .width = effective_size,
        .height = effective_size,
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .sample_count = sdl_gpu.SDL_GPU_SAMPLECOUNT_1,
    }) orelse return error.ShadowMapCreateFailed;
    self.shadow_map_texture = tex;
    self.shadow_map_size = effective_size;
}

pub const InstancedShadowUniforms = extern struct {
    light_view_proj: [16]f32,
};

pub fn renderShadowPass(
    self: anytype,
    command_buffer: *render_commands.CommandBuffer,
    scene_bounds: render_visibility.Bounds,
) !void {
    if (!self.settings.shadowsEnabled()) return;
    if (!self.frame_lighting.shadows_enabled or !self.frame_lighting.shading_lit) return;
    if (self.shadow_map_texture == null) return;

    const cmdbuf = self.cmdbuf orelse return error.NoActiveCommandBuffer;
    const render_pass = self.render_pass orelse return error.NoActiveRenderPass;

    sdl_gpu.SDL_EndGPURenderPass(render_pass);
    self.render_pass = null;

    const light_view_proj = render_lighting.directionalLightViewProjection(scene_bounds, self.frame_lighting.sun_direction);
    self.light_view_proj = light_view_proj;

    var depth_target = sdl_gpu.SDL_GPUDepthStencilTargetInfo{
        .texture = self.shadow_map_texture,
        .clear_depth = 1,
        .load_op = sdl_gpu.SDL_GPU_LOADOP_CLEAR,
        .store_op = sdl_gpu.SDL_GPU_STOREOP_STORE,
        .stencil_load_op = sdl_gpu.SDL_GPU_LOADOP_DONT_CARE,
        .stencil_store_op = sdl_gpu.SDL_GPU_STOREOP_DONT_CARE,
    };

    const shadow_pass = sdl_gpu.SDL_BeginGPURenderPass(cmdbuf, null, 0, &depth_target) orelse return error.ShadowRenderPassFailed;

    const viewport = sdl_gpu.SDL_GPUViewport{
        .x = 0,
        .y = 0,
        .w = @floatFromInt(self.shadow_map_size),
        .h = @floatFromInt(self.shadow_map_size),
        .min_depth = 0,
        .max_depth = 1,
    };
    sdl_gpu.SDL_SetGPUViewport(shadow_pass, &viewport);
    sdl_gpu.SDL_BindGPUGraphicsPipeline(shadow_pass, self.shadow_pipeline);

    for (command_buffer.entries.items) |entry| {
        switch (entry.command) {
            .mesh => |draw| {
                if (!draw.cast_shadows or !draw.shading.castsShadows()) continue;
                drawShadowMesh(self, shadow_pass, cmdbuf, light_view_proj, draw.mesh_index, draw.transform);
            },
            .instanced_mesh => |draw| {
                if (!draw.cast_shadows or !draw.shading.castsShadows()) continue;
                try drawInstancedShadowMesh(self, shadow_pass, cmdbuf, command_buffer, light_view_proj, draw);
            },
            else => {},
        }
    }

    sdl_gpu.SDL_EndGPURenderPass(shadow_pass);
    try resumeMainRenderPass(self, sdl_gpu.SDL_GPU_LOADOP_LOAD, sdl_gpu.SDL_GPU_LOADOP_CLEAR);
}

fn drawShadowMesh(
    self: anytype,
    shadow_pass: *sdl_gpu.SDL_GPURenderPass,
    cmdbuf: *sdl_gpu.SDL_GPUCommandBuffer,
    light_view_proj: editor_math.Mat4,
    mesh_index: u32,
    transform: [16]f32,
) void {
    if (mesh_index >= self.meshes.items.len) return;
    const mesh = &self.meshes.items[mesh_index];
    if (mesh.index_count == 0) return;
    const vertex_buffer = mesh.vertex_buffer orelse return;
    const index_buffer = mesh.index_buffer orelse return;
    sdl_gpu.SDL_BindGPUGraphicsPipeline(shadow_pass, self.shadow_pipeline);
    const model = pipelines.mat4FromFlat(transform);
    const light_mvp = editor_math.Mat4.mul(light_view_proj, model);
    const uniforms = ShadowVertexUniforms{ .light_mvp = light_mvp.m };
    sdl_gpu.SDL_PushGPUVertexUniformData(cmdbuf, 0, &uniforms, @intCast(@sizeOf(ShadowVertexUniforms)));

    const vertex_bindings = [_]sdl_gpu.SDL_GPUBufferBinding{.{ .buffer = vertex_buffer, .offset = 0 }};
    sdl_gpu.SDL_BindGPUVertexBuffers(shadow_pass, 0, &vertex_bindings, 1);
    const index_binding = sdl_gpu.SDL_GPUBufferBinding{ .buffer = index_buffer, .offset = 0 };
    sdl_gpu.SDL_BindGPUIndexBuffer(shadow_pass, &index_binding, sdl_gpu.SDL_GPU_INDEXELEMENTSIZE_32BIT);
    sdl_gpu.SDL_DrawGPUIndexedPrimitives(shadow_pass, mesh.index_count, 1, 0, 0, 0);
}

fn drawInstancedShadowMesh(
    self: anytype,
    shadow_pass: *sdl_gpu.SDL_GPURenderPass,
    cmdbuf: *sdl_gpu.SDL_GPUCommandBuffer,
    command_buffer: *render_commands.CommandBuffer,
    light_view_proj: editor_math.Mat4,
    draw: render_commands.InstancedMeshDraw,
) !void {
    if (draw.mesh_index >= self.meshes.items.len) return;
    const mesh = &self.meshes.items[draw.mesh_index];
    if (mesh.index_count == 0) return;
    const vertex_buffer = mesh.vertex_buffer orelse return;
    const index_buffer = mesh.index_buffer orelse return;
    const transforms = command_buffer.instanceTransforms(draw);
    var instances = try self.allocator.alloc(types.GpuMeshInstance, transforms.len);
    defer self.allocator.free(instances);
    for (transforms, 0..) |transform, idx| {
        instances[idx] = .{ .model = transform };
    }
    const instance_buffer = try gpu_instance_buffer.uploadInstancesOnCommandBuffer(self, cmdbuf, instances);

    const uniforms = InstancedShadowUniforms{ .light_view_proj = light_view_proj.m };
    sdl_gpu.SDL_PushGPUVertexUniformData(cmdbuf, 0, &uniforms, @intCast(@sizeOf(InstancedShadowUniforms)));
    sdl_gpu.SDL_BindGPUGraphicsPipeline(shadow_pass, self.instanced_shadow_pipeline);

    const vertex_bindings = [_]sdl_gpu.SDL_GPUBufferBinding{
        .{ .buffer = vertex_buffer, .offset = 0 },
        .{ .buffer = instance_buffer, .offset = 0 },
    };
    sdl_gpu.SDL_BindGPUVertexBuffers(shadow_pass, 0, &vertex_bindings, 2);
    const index_binding = sdl_gpu.SDL_GPUBufferBinding{ .buffer = index_buffer, .offset = 0 };
    sdl_gpu.SDL_BindGPUIndexBuffer(shadow_pass, &index_binding, sdl_gpu.SDL_GPU_INDEXELEMENTSIZE_32BIT);
    sdl_gpu.SDL_DrawGPUIndexedPrimitives(shadow_pass, mesh.index_count, draw.instance_count, 0, 0, 0);
}

pub fn resumeMainRenderPass(self: anytype, color_load: sdl_gpu.SDL_GPULoadOp, depth_load: sdl_gpu.SDL_GPULoadOp) !void {
    const cmdbuf = self.cmdbuf orelse return error.NoActiveCommandBuffer;

    const uses_msaa = if (self.in_offscreen_frame)
        self.offscreen_sample_count != sdl_gpu.SDL_GPU_SAMPLECOUNT_1
    else
        self.settings.sampleCount() != sdl_gpu.SDL_GPU_SAMPLECOUNT_1;

    var color_target = sdl_gpu.SDL_GPUColorTargetInfo{
        .texture = if (self.scene_color_hdr_active)
            if (uses_msaa) self.hdr_msaa_color_texture else self.hdr_color_texture
        else if (self.in_offscreen_frame)
            if (uses_msaa) self.offscreen_msaa_color_texture else self.offscreen_color_texture
        else if (uses_msaa)
            self.frame_msaa_color_texture
        else
            self.swapchain_texture,
        .load_op = color_load,
        .store_op = if (uses_msaa) sdl_gpu.SDL_GPU_STOREOP_RESOLVE_AND_STORE else sdl_gpu.SDL_GPU_STOREOP_STORE,
    };
    if (uses_msaa) {
        color_target.resolve_texture = if (self.scene_color_hdr_active)
            self.hdr_color_texture
        else if (self.in_offscreen_frame) self.offscreen_color_texture else self.swapchain_texture;
    }

    var depth_target = sdl_gpu.SDL_GPUDepthStencilTargetInfo{
        .texture = self.depth_texture,
        .clear_depth = 1,
        .load_op = depth_load,
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
