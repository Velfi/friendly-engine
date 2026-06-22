const std = @import("std");
const sdl_gpu = @import("sdl_gpu.zig");
const editor_math = @import("editor_math.zig");
const gpu_scene = @import("gpu_scene.zig");
const pipelines = @import("gpu_backend_sdl_pipelines.zig");
const overlay = @import("gpu_backend_sdl_overlay.zig");
const render_commands = @import("render_commands.zig");
const render_graph = @import("render_graph.zig");
const render_lighting = @import("render_lighting.zig");
const render_sky = @import("render_sky.zig");
const render_visibility = @import("render_visibility.zig");
const shadow = @import("gpu_backend_sdl_shadow.zig");
const frame_pipelines = @import("gpu_backend_sdl_frame_pipelines.zig");
const gpu_instance_buffer = @import("gpu_instance_buffer.zig");
const types = @import("gpu_backend_sdl_types.zig");
const hdr = @import("gpu_backend_sdl_hdr.zig");

/// Renders the gradient + procedural stars + sun/moon glow disks as a single
/// fullscreen-triangle draw at the start of the main scene pass. Depth test is
/// disabled in the pipeline so this never blocks subsequent geometry.
pub fn drawSky(self: anytype) void {
    if (!self.frame_sky.enabled) return;
    const render_pass = self.render_pass orelse return;
    const cmdbuf = self.cmdbuf orelse return;
    sdl_gpu.SDL_InsertGPUDebugLabel(cmdbuf, "sky");

    const aspect = @as(f32, @floatFromInt(self.width)) / @max(1.0, @as(f32, @floatFromInt(self.height)));
    const uniforms = render_sky.packGpuSkyUniforms(self.frame_sky, aspect);
    sdl_gpu.SDL_PushGPUFragmentUniformData(cmdbuf, 0, &uniforms, @intCast(@sizeOf(render_sky.GpuSkyUniforms)));
    sdl_gpu.SDL_BindGPUGraphicsPipeline(render_pass, frame_pipelines.activeSkyPipeline(self));
    sdl_gpu.SDL_DrawGPUPrimitives(render_pass, 3, 1, 0, 0);
}

pub fn drawGrid(self: anytype, draw: editor_math.GridDraw) void {
    const render_pass = self.render_pass orelse return;
    const cmdbuf = self.cmdbuf orelse return;
    sdl_gpu.SDL_InsertGPUDebugLabel(cmdbuf, "grid");

    const aspect = @as(f32, @floatFromInt(self.width)) / @as(f32, @floatFromInt(self.height));
    const view = draw.camera.viewMatrix();
    const proj = editor_math.projectionMatrix(draw.camera, aspect, .perspective);
    const vp = editor_math.Mat4.mul(proj, view);
    const mvp = editor_math.Mat4.mul(vp, draw.modelMatrix());

    sdl_gpu.SDL_PushGPUVertexUniformData(cmdbuf, 0, &mvp.m, @intCast(@sizeOf([16]f32)));
    sdl_gpu.SDL_BindGPUGraphicsPipeline(render_pass, frame_pipelines.activeGridPipeline(self));
    const grid_vertex_bindings = [_]sdl_gpu.SDL_GPUBufferBinding{.{ .buffer = self.grid_vertex_buffer, .offset = 0 }};
    sdl_gpu.SDL_BindGPUVertexBuffers(render_pass, 0, &grid_vertex_bindings, 1);
    sdl_gpu.SDL_DrawGPUPrimitives(render_pass, self.grid_vertex_count, 1, 0, 0);
}

fn beginColorOnlyPass(self: anytype) !void {
    const cmdbuf = self.cmdbuf orelse return error.NoActiveCommandBuffer;
    const uses_msaa = if (self.in_offscreen_frame)
        self.offscreen_sample_count != sdl_gpu.SDL_GPU_SAMPLECOUNT_1
    else
        self.settings.sampleCount() != sdl_gpu.SDL_GPU_SAMPLECOUNT_1;

    const color_target = sdl_gpu.SDL_GPUColorTargetInfo{
        .texture = if (self.scene_color_hdr_active)
            if (uses_msaa) self.hdr_msaa_color_texture else self.hdr_color_texture
        else if (self.in_offscreen_frame)
            if (uses_msaa) self.offscreen_msaa_color_texture else self.offscreen_color_texture
        else if (uses_msaa)
            self.frame_msaa_color_texture
        else
            self.swapchain_texture,
        .resolve_texture = if (self.scene_color_hdr_active and uses_msaa) self.hdr_color_texture else null,
        .load_op = sdl_gpu.SDL_GPU_LOADOP_LOAD,
        .store_op = if (self.scene_color_hdr_active and uses_msaa) sdl_gpu.SDL_GPU_STOREOP_RESOLVE else sdl_gpu.SDL_GPU_STOREOP_STORE,
    };
    if (color_target.texture == null) return error.ColorTargetMissing;

    const color_targets = [_]sdl_gpu.SDL_GPUColorTargetInfo{color_target};
    const render_pass = sdl_gpu.SDL_BeginGPURenderPass(cmdbuf, &color_targets, 1, null) orelse return error.RenderPassFailed;
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

fn drawSkyColorOnlyBeforeScene(self: anytype) !void {
    if (!self.frame_sky.enabled) return;
    const current_pass = self.render_pass orelse return error.RenderPassMissing;
    sdl_gpu.SDL_EndGPURenderPass(current_pass);
    self.render_pass = null;

    try beginColorOnlyPass(self);
    drawSky(self);
    if (self.render_pass) |sky_pass| {
        sdl_gpu.SDL_EndGPURenderPass(sky_pass);
        self.render_pass = null;
    }
    try shadow.resumeMainRenderPass(self, sdl_gpu.SDL_GPU_LOADOP_LOAD, sdl_gpu.SDL_GPU_LOADOP_CLEAR);
}

pub fn drawMeshByIndex(self: anytype, index: usize, transform: [16]f32, camera: editor_math.OrbitCamera) !void {
    try drawMeshDraw(self, .{
        .mesh_index = @intCast(index),
        .transform = transform,
        .camera = camera,
        .shading = .rendered,
    });
}

const TextureSamplerKind = enum {
    material_repeat,
    clamp_to_edge,
};

fn textureSamplerKind(usage: gpu_scene.TextureUsage) TextureSamplerKind {
    return switch (usage) {
        .material => .material_repeat,
        .terrain_mask => .clamp_to_edge,
    };
}

fn textureSampler(self: anytype, usage: gpu_scene.TextureUsage) *sdl_gpu.SDL_GPUSampler {
    return switch (textureSamplerKind(usage)) {
        .material_repeat => self.sampler,
        .clamp_to_edge => self.mask_sampler,
    };
}

pub fn drawMeshDraw(self: anytype, draw: render_commands.MeshDraw) !void {
    const index = draw.mesh_index;
    if (index >= self.meshes.items.len) return;
    const render_pass = self.render_pass orelse return;
    const cmdbuf = self.cmdbuf orelse return;
    const mesh = &self.meshes.items[index];
    if (mesh.index_count == 0) return;
    const vertex_buffer = mesh.vertex_buffer orelse return;
    const index_buffer = mesh.index_buffer orelse return;
    sdl_gpu.SDL_InsertGPUDebugLabel(cmdbuf, "mesh");

    const aspect = @as(f32, @floatFromInt(self.width)) / @as(f32, @floatFromInt(self.height));
    const view = draw.camera.viewMatrix();
    const proj = editor_math.projectionMatrix(draw.camera, aspect, .perspective);
    const vp = editor_math.Mat4.mul(proj, view);
    const model = pipelines.mat4FromFlat(draw.transform);
    const mvp = editor_math.Mat4.mul(vp, model);
    const uniforms = shadow.MeshVertexUniforms{ .mvp = mvp.m, .model = model.m };
    sdl_gpu.SDL_PushGPUVertexUniformData(cmdbuf, 0, &uniforms, @intCast(@sizeOf(shadow.MeshVertexUniforms)));

    const shading = effectiveMeshShading(self, draw.shading);
    if (draw.surface == .water) {
        sdl_gpu.SDL_BindGPUGraphicsPipeline(render_pass, frame_pipelines.activeWaterPipeline(self));
    } else {
        switch (shading) {
            .rendered => {
                const pipeline = if (draw.double_sided)
                    frame_pipelines.activeDoubleSidedLitMeshPipeline(self)
                else
                    frame_pipelines.activeLitMeshPipeline(self);
                sdl_gpu.SDL_BindGPUGraphicsPipeline(render_pass, pipeline);
                const lighting_uniforms = render_lighting.packGpuLightingUniforms(
                    self.frame_lighting,
                    draw.receive_shadows,
                    self.light_view_proj,
                    mesh.dissolve_amount,
                    mesh.dissolve_inverted,
                );
                sdl_gpu.SDL_PushGPUFragmentUniformData(cmdbuf, 0, &lighting_uniforms, @intCast(@sizeOf(render_lighting.GpuLightingUniforms)));
            },
            .material_preview => {
                const pipeline = if (draw.double_sided)
                    frame_pipelines.activeDoubleSidedMeshPipeline(self)
                else
                    frame_pipelines.activeMeshPipeline(self);
                sdl_gpu.SDL_BindGPUGraphicsPipeline(render_pass, pipeline);
            },
            .solid => {
                const pipeline = if (draw.double_sided)
                    frame_pipelines.activeDoubleSidedSolidMeshPipeline(self)
                else
                    frame_pipelines.activeSolidMeshPipeline(self);
                sdl_gpu.SDL_BindGPUGraphicsPipeline(render_pass, pipeline);
            },
        }
    }

    const vertex_bindings = [_]sdl_gpu.SDL_GPUBufferBinding{.{ .buffer = vertex_buffer, .offset = 0 }};
    sdl_gpu.SDL_BindGPUVertexBuffers(render_pass, 0, &vertex_bindings, 1);
    const index_binding = sdl_gpu.SDL_GPUBufferBinding{ .buffer = index_buffer, .offset = 0 };
    sdl_gpu.SDL_BindGPUIndexBuffer(render_pass, &index_binding, sdl_gpu.SDL_GPU_INDEXELEMENTSIZE_32BIT);

    const texture = mesh.texture orelse self.white_texture;
    if (draw.surface == .water) {
        const sampler_bindings = [_]sdl_gpu.SDL_GPUTextureSamplerBinding{.{ .texture = texture, .sampler = self.sampler }};
        sdl_gpu.SDL_BindGPUFragmentSamplers(render_pass, 0, &sampler_bindings, 1);
    } else if (shading == .rendered) {
        const shadow_texture = self.shadow_map_texture orelse return error.MissingShadowMapTexture;
        const sampler_bindings = [_]sdl_gpu.SDL_GPUTextureSamplerBinding{
            .{ .texture = texture, .sampler = textureSampler(self, mesh.texture_usage) },
            .{ .texture = shadow_texture, .sampler = self.shadow_compare_sampler },
        };
        sdl_gpu.SDL_BindGPUFragmentSamplers(render_pass, 0, &sampler_bindings, 2);
    } else if (shading == .material_preview) {
        const sampler_bindings = [_]sdl_gpu.SDL_GPUTextureSamplerBinding{.{ .texture = texture, .sampler = textureSampler(self, mesh.texture_usage) }};
        sdl_gpu.SDL_BindGPUFragmentSamplers(render_pass, 0, &sampler_bindings, 1);
    }
    sdl_gpu.SDL_DrawGPUIndexedPrimitives(render_pass, mesh.index_count, 1, 0, 0, 0);
}

pub const InstancedSceneUniforms = extern struct {
    view_proj: [16]f32,
};

fn normalizedColor(color: [4]u8) [4]f32 {
    return .{
        @as(f32, @floatFromInt(color[0])) / 255.0,
        @as(f32, @floatFromInt(color[1])) / 255.0,
        @as(f32, @floatFromInt(color[2])) / 255.0,
        @as(f32, @floatFromInt(color[3])) / 255.0,
    };
}

pub fn drawGrassDraw(self: anytype, command_buffer: *render_commands.CommandBuffer, draw: render_commands.GrassDraw) !void {
    const cmdbuf = self.cmdbuf orelse return;
    const instances = command_buffer.grassInstances(draw);
    if (instances.len == 0) return;
    sdl_gpu.SDL_InsertGPUDebugLabel(cmdbuf, "grass");

    var gpu_instances = try self.allocator.alloc(types.GpuGrassInstance, instances.len);
    defer self.allocator.free(gpu_instances);
    for (instances, 0..) |instance, idx| {
        gpu_instances[idx] = .{
            .position = .{ instance.position[0], instance.position[1], instance.position[2], 1.0 },
            .normal_height = .{ instance.normal[0], instance.normal[1], instance.normal[2], instance.height },
            .color = normalizedColor(instance.color),
            .blade = .{ instance.width, instance.yaw, instance.phase, @floatFromInt(instance.variant) },
        };
    }
    if (self.render_pass) |pass| {
        sdl_gpu.SDL_EndGPURenderPass(pass);
        self.render_pass = null;
    }
    const instance_buffer = try gpu_instance_buffer.uploadGrassInstancesOnCommandBuffer(self, cmdbuf, gpu_instances);
    try shadow.resumeMainRenderPass(self, sdl_gpu.SDL_GPU_LOADOP_LOAD, sdl_gpu.SDL_GPU_LOADOP_LOAD);
    const render_pass = self.render_pass orelse return error.RenderPassMissing;

    const aspect = @as(f32, @floatFromInt(self.width)) / @max(1.0, @as(f32, @floatFromInt(self.height)));
    const view = draw.camera.viewMatrix();
    const proj = editor_math.projectionMatrix(draw.camera, aspect, .perspective);
    const view_proj = editor_math.Mat4.mul(proj, view);
    var uniforms = types.GpuGrassUniforms{
        .view_proj = view_proj.m,
        .wind = .{ @cos(std.math.degreesToRadians(draw.wind_direction_deg)), @sin(std.math.degreesToRadians(draw.wind_direction_deg)), draw.wind_speed_mps, self.grass_time_seconds },
        .controls = .{ draw.wind_strength, draw.bend_strength, draw.stiffness, draw.cull_fade },
        .influencers = [_]types.GpuGrassInfluencer{.{ .position_radius = .{ 0, 0, 0, 0 }, .velocity_strength = .{ 0, 0, 0, 0 } }} ** 16,
        .counts = .{ @min(draw.influencer_count, 16), 0, 0, 0 },
    };
    const influencers = command_buffer.grassInfluencers(draw);
    const influencer_count = @min(influencers.len, 16);
    for (influencers[0..influencer_count], 0..) |influencer, idx| {
        uniforms.influencers[idx] = .{
            .position_radius = .{ influencer.position[0], influencer.position[1], influencer.position[2], influencer.radius },
            .velocity_strength = .{ influencer.velocity_dir[0], influencer.velocity_dir[1], influencer.velocity_dir[2], influencer.strength },
        };
    }
    uniforms.counts[0] = @intCast(influencer_count);

    sdl_gpu.SDL_PushGPUVertexUniformData(cmdbuf, 0, &uniforms, @intCast(@sizeOf(types.GpuGrassUniforms)));
    sdl_gpu.SDL_BindGPUGraphicsPipeline(render_pass, frame_pipelines.activeGrassPipeline(self));
    const vertex_bindings = [_]sdl_gpu.SDL_GPUBufferBinding{.{ .buffer = instance_buffer, .offset = 0 }};
    sdl_gpu.SDL_BindGPUVertexBuffers(render_pass, 0, &vertex_bindings, 1);
    sdl_gpu.SDL_DrawGPUPrimitives(render_pass, 6, @intCast(instances.len), 0, 0);
}

pub fn drawInstancedMeshDraw(self: anytype, command_buffer: *render_commands.CommandBuffer, draw: render_commands.InstancedMeshDraw) !void {
    const index = draw.mesh_index;
    if (index >= self.meshes.items.len) return;
    const render_pass = self.render_pass orelse return;
    const cmdbuf = self.cmdbuf orelse return;
    const mesh = &self.meshes.items[index];
    if (mesh.index_count == 0) return;
    const vertex_buffer = mesh.vertex_buffer orelse return;
    const index_buffer = mesh.index_buffer orelse return;
    sdl_gpu.SDL_InsertGPUDebugLabel(cmdbuf, "instanced_mesh");

    const transforms = command_buffer.instanceTransforms(draw);
    var instances = try self.allocator.alloc(types.GpuMeshInstance, transforms.len);
    defer self.allocator.free(instances);
    for (transforms, 0..) |transform, idx| {
        instances[idx] = .{ .model = transform };
    }
    const instance_buffer = try gpu_instance_buffer.uploadInstancesOnCommandBuffer(self, cmdbuf, instances);

    const aspect = @as(f32, @floatFromInt(self.width)) / @as(f32, @floatFromInt(self.height));
    const view = draw.camera.viewMatrix();
    const proj = editor_math.projectionMatrix(draw.camera, aspect, .perspective);
    const view_proj = editor_math.Mat4.mul(proj, view);
    const uniforms = InstancedSceneUniforms{ .view_proj = view_proj.m };
    sdl_gpu.SDL_PushGPUVertexUniformData(cmdbuf, 0, &uniforms, @intCast(@sizeOf(InstancedSceneUniforms)));

    const shading = effectiveMeshShading(self, draw.shading);
    switch (shading) {
        .rendered => {
            sdl_gpu.SDL_BindGPUGraphicsPipeline(render_pass, frame_pipelines.activeLitInstancedMeshPipeline(self));
            const lighting_uniforms = render_lighting.packGpuLightingUniforms(
                self.frame_lighting,
                draw.receive_shadows,
                self.light_view_proj,
                mesh.dissolve_amount,
                mesh.dissolve_inverted,
            );
            sdl_gpu.SDL_PushGPUFragmentUniformData(cmdbuf, 0, &lighting_uniforms, @intCast(@sizeOf(render_lighting.GpuLightingUniforms)));
        },
        .material_preview => sdl_gpu.SDL_BindGPUGraphicsPipeline(render_pass, frame_pipelines.activeInstancedMeshPipeline(self)),
        .solid => sdl_gpu.SDL_BindGPUGraphicsPipeline(render_pass, frame_pipelines.activeSolidInstancedMeshPipeline(self)),
    }

    const vertex_bindings = [_]sdl_gpu.SDL_GPUBufferBinding{
        .{ .buffer = vertex_buffer, .offset = 0 },
        .{ .buffer = instance_buffer, .offset = 0 },
    };
    sdl_gpu.SDL_BindGPUVertexBuffers(render_pass, 0, &vertex_bindings, 2);
    const index_binding = sdl_gpu.SDL_GPUBufferBinding{ .buffer = index_buffer, .offset = 0 };
    sdl_gpu.SDL_BindGPUIndexBuffer(render_pass, &index_binding, sdl_gpu.SDL_GPU_INDEXELEMENTSIZE_32BIT);

    const texture = mesh.texture orelse self.white_texture;
    if (shading == .rendered) {
        const shadow_texture = self.shadow_map_texture orelse return error.MissingShadowMapTexture;
        const sampler_bindings = [_]sdl_gpu.SDL_GPUTextureSamplerBinding{
            .{ .texture = texture, .sampler = textureSampler(self, mesh.texture_usage) },
            .{ .texture = shadow_texture, .sampler = self.shadow_compare_sampler },
        };
        sdl_gpu.SDL_BindGPUFragmentSamplers(render_pass, 0, &sampler_bindings, 2);
    } else if (shading == .material_preview) {
        const sampler_bindings = [_]sdl_gpu.SDL_GPUTextureSamplerBinding{.{ .texture = texture, .sampler = textureSampler(self, mesh.texture_usage) }};
        sdl_gpu.SDL_BindGPUFragmentSamplers(render_pass, 0, &sampler_bindings, 1);
    }
    sdl_gpu.SDL_DrawGPUIndexedPrimitives(render_pass, mesh.index_count, draw.instance_count, 0, 0, 0);
}

test "terrain mask textures use clamp sampler kind" {
    try std.testing.expectEqual(TextureSamplerKind.clamp_to_edge, textureSamplerKind(.terrain_mask));
}

pub fn drawMeshWireframeByIndex(
    self: anytype,
    index: usize,
    transform: [16]f32,
    camera: editor_math.OrbitCamera,
    projection_mode: editor_math.ProjectionMode,
) void {
    if (index >= self.meshes.items.len) return;
    const mesh = &self.meshes.items[index];
    if (mesh.wireframe_index_count < 2) return;
    const vertex_buffer = mesh.vertex_buffer orelse return;
    const wireframe_index_buffer = mesh.wireframe_index_buffer orelse return;
    const render_pass = self.render_pass orelse return;
    const cmdbuf = self.cmdbuf orelse return;
    sdl_gpu.SDL_InsertGPUDebugLabel(cmdbuf, "wireframe");

    const aspect = @as(f32, @floatFromInt(self.width)) / @as(f32, @floatFromInt(self.height));
    const view = camera.viewMatrix();
    const proj = editor_math.projectionMatrix(camera, aspect, projection_mode);
    const vp = editor_math.Mat4.mul(proj, view);
    const model = pipelines.mat4FromFlat(transform);
    const mvp = editor_math.Mat4.mul(vp, model);

    sdl_gpu.SDL_PushGPUVertexUniformData(cmdbuf, 0, &mvp.m, @intCast(@sizeOf([16]f32)));
    sdl_gpu.SDL_BindGPUGraphicsPipeline(render_pass, frame_pipelines.activeWireframePipeline(self));
    const vertex_bindings = [_]sdl_gpu.SDL_GPUBufferBinding{.{ .buffer = vertex_buffer, .offset = 0 }};
    sdl_gpu.SDL_BindGPUVertexBuffers(render_pass, 0, &vertex_bindings, 1);
    const index_binding = sdl_gpu.SDL_GPUBufferBinding{ .buffer = wireframe_index_buffer, .offset = 0 };
    sdl_gpu.SDL_BindGPUIndexBuffer(render_pass, &index_binding, sdl_gpu.SDL_GPU_INDEXELEMENTSIZE_32BIT);
    sdl_gpu.SDL_DrawGPUIndexedPrimitives(render_pass, mesh.wireframe_index_count, 1, 0, 0, 0);
}

pub fn drawOverlayQuads(self: anytype, quads: []const gpu_scene.OverlayQuad) !void {
    try overlay.drawOverlayQuads(self, quads);
}

pub fn submitCommands(self: anytype, command_buffer: *render_commands.CommandBuffer) !void {
    if (!command_buffer.sorted) command_buffer.sort();
    try command_buffer.markSubmitted();
    const stats = command_buffer.stats();
    self.last_command_stats = stats;
    if (hasLitDraws(command_buffer)) {
        try shadow.ensureShadowMap(self, self.settings.shadows.mapResolution());
    }

    const cmdbuf = self.cmdbuf orelse return error.NoActiveCommandBuffer;
    sdl_gpu.SDL_PushGPUDebugGroup(cmdbuf, "sorted render commands");
    defer sdl_gpu.SDL_PopGPUDebugGroup(cmdbuf);

    var scene_meshes: std.ArrayList(render_visibility.SceneMesh) = .empty;
    defer scene_meshes.deinit(self.allocator);
    for (command_buffer.entries.items) |entry| {
        switch (entry.command) {
            .mesh => |draw| {
                if (draw.surface == .water) continue;
                try scene_meshes.append(self.allocator, .{
                    .transform = draw.transform,
                    .bounds = render_visibility.boundsFromTransform(draw.transform),
                });
            },
            .instanced_mesh => |draw| {
                for (command_buffer.instanceTransforms(draw)) |transform| {
                    try scene_meshes.append(self.allocator, .{
                        .transform = transform,
                        .bounds = render_visibility.boundsFromTransform(transform),
                    });
                }
            },
            else => {},
        }
    }

    const render_shadows = wantsShadowPass(self, command_buffer);
    const render_water = hasWaterDraws(command_buffer);
    var frame_plan = try render_graph.buildFramePlan(self.allocator, .{
        .shadows = render_shadows,
        .water = render_water,
        .overlays = stats.overlays > 0,
    });
    defer frame_plan.deinit(self.allocator);

    const scene_bounds = if (render_shadows) render_lighting.mergeSceneBounds(scene_meshes.items) else undefined;

    for (frame_plan.order) |pass| switch (pass) {
        .shadow_depth => try shadow.renderShadowPass(self, command_buffer, scene_bounds),
        .main_depth_scene => try drawMainScenePass(self, command_buffer),
        .water_surface => {
            try drawWaterDepthPrepass(self, command_buffer);
            try drawWaterSurfacePass(self, command_buffer);
        },
        .overlay => {
            try hdr.finishHdrSceneForComposite(self);
            try drawOverlayPass(self, command_buffer);
        },
        .readback, .present => {},
    };
    try hdr.finishHdrSceneForComposite(self);
}

fn drawMainScenePass(self: anytype, command_buffer: *render_commands.CommandBuffer) !void {
    if (hasDepthSceneDraws(command_buffer)) {
        try drawSkyColorOnlyBeforeScene(self);
    }
    for (command_buffer.entries.items) |entry| {
        switch (entry.command) {
            .clear => return error.UnsupportedBackendCommandVariant,
            .grid => |draw| drawGrid(self, draw),
            .mesh => |draw| {
                if (draw.surface == .water) continue;
                if (draw.instance_count != 1) return error.InvalidRenderBatchInstanceCount;
                try drawMeshDraw(self, draw);
            },
            .instanced_mesh => |draw| try drawInstancedMeshDraw(self, command_buffer, draw),
            .grass => |draw| try drawGrassDraw(self, command_buffer, draw),
            .wireframe_mesh => |draw| {
                drawMeshWireframeByIndex(self, draw.mesh_index, draw.transform, draw.camera, draw.projection_mode);
            },
            .overlay => {},
            .copy => return error.UnsupportedBackendCommandVariant,
        }
    }
}

fn drawWaterDepthPrepass(self: anytype, command_buffer: *render_commands.CommandBuffer) !void {
    if (!sceneUsesMsaa(self)) return;
    try @import("gpu_backend_sdl_frame_textures.zig").ensureWaterDepthTexture(self);

    const cmdbuf = self.cmdbuf orelse return error.NoActiveCommandBuffer;
    if (self.render_pass) |pass| {
        sdl_gpu.SDL_EndGPURenderPass(pass);
        self.render_pass = null;
    }

    var depth_target = sdl_gpu.SDL_GPUDepthStencilTargetInfo{
        .texture = self.water_depth_texture,
        .clear_depth = 1,
        .load_op = sdl_gpu.SDL_GPU_LOADOP_CLEAR,
        .store_op = sdl_gpu.SDL_GPU_STOREOP_STORE,
        .stencil_load_op = sdl_gpu.SDL_GPU_LOADOP_DONT_CARE,
        .stencil_store_op = sdl_gpu.SDL_GPU_STOREOP_DONT_CARE,
    };
    const pass = sdl_gpu.SDL_BeginGPURenderPass(cmdbuf, null, 0, &depth_target) orelse return error.RenderPassFailed;
    defer sdl_gpu.SDL_EndGPURenderPass(pass);

    const viewport = sdl_gpu.SDL_GPUViewport{
        .x = 0,
        .y = 0,
        .w = @floatFromInt(self.width),
        .h = @floatFromInt(self.height),
        .min_depth = 0,
        .max_depth = 1,
    };
    sdl_gpu.SDL_SetGPUViewport(pass, &viewport);

    for (command_buffer.entries.items) |entry| {
        switch (entry.command) {
            .mesh => |draw| {
                if (draw.surface == .water) continue;
                if (draw.instance_count != 1) return error.InvalidRenderBatchInstanceCount;
                drawMeshDepthOnly(self, pass, cmdbuf, draw);
            },
            .instanced_mesh => |draw| try drawInstancedMeshDepthOnly(self, pass, cmdbuf, command_buffer, draw),
            else => {},
        }
    }
}

fn drawMeshDepthOnly(
    self: anytype,
    pass: *sdl_gpu.SDL_GPURenderPass,
    cmdbuf: *sdl_gpu.SDL_GPUCommandBuffer,
    draw: render_commands.MeshDraw,
) void {
    const index = draw.mesh_index;
    if (index >= self.meshes.items.len) return;
    const mesh = &self.meshes.items[index];
    if (mesh.index_count == 0) return;
    const vertex_buffer = mesh.vertex_buffer orelse return;
    const index_buffer = mesh.index_buffer orelse return;

    const aspect = @as(f32, @floatFromInt(self.width)) / @as(f32, @floatFromInt(self.height));
    const view = draw.camera.viewMatrix();
    const proj = editor_math.projectionMatrix(draw.camera, aspect, .perspective);
    const vp = editor_math.Mat4.mul(proj, view);
    const model = pipelines.mat4FromFlat(draw.transform);
    const mvp = editor_math.Mat4.mul(vp, model);
    const uniforms = shadow.MeshVertexUniforms{ .mvp = mvp.m, .model = model.m };
    sdl_gpu.SDL_PushGPUVertexUniformData(cmdbuf, 0, &uniforms, @intCast(@sizeOf(shadow.MeshVertexUniforms)));
    sdl_gpu.SDL_BindGPUGraphicsPipeline(pass, self.depth_prepass_pipeline);

    const vertex_bindings = [_]sdl_gpu.SDL_GPUBufferBinding{.{ .buffer = vertex_buffer, .offset = 0 }};
    sdl_gpu.SDL_BindGPUVertexBuffers(pass, 0, &vertex_bindings, 1);
    const index_binding = sdl_gpu.SDL_GPUBufferBinding{ .buffer = index_buffer, .offset = 0 };
    sdl_gpu.SDL_BindGPUIndexBuffer(pass, &index_binding, sdl_gpu.SDL_GPU_INDEXELEMENTSIZE_32BIT);
    sdl_gpu.SDL_DrawGPUIndexedPrimitives(pass, mesh.index_count, 1, 0, 0, 0);
}

fn drawInstancedMeshDepthOnly(
    self: anytype,
    pass: *sdl_gpu.SDL_GPURenderPass,
    cmdbuf: *sdl_gpu.SDL_GPUCommandBuffer,
    command_buffer: *render_commands.CommandBuffer,
    draw: render_commands.InstancedMeshDraw,
) !void {
    const index = draw.mesh_index;
    if (index >= self.meshes.items.len or draw.instance_count == 0) return;
    const mesh = &self.meshes.items[index];
    if (mesh.index_count == 0) return;
    const vertex_buffer = mesh.vertex_buffer orelse return;
    const index_buffer = mesh.index_buffer orelse return;
    const transforms = command_buffer.instanceTransforms(draw);
    var instances = try self.allocator.alloc(types.GpuMeshInstance, transforms.len);
    defer self.allocator.free(instances);
    for (transforms, 0..) |transform, idx| instances[idx] = .{ .model = transform };
    const instance_buffer = try gpu_instance_buffer.uploadInstancesOnCommandBuffer(self, cmdbuf, instances);

    const aspect = @as(f32, @floatFromInt(self.width)) / @as(f32, @floatFromInt(self.height));
    const view = draw.camera.viewMatrix();
    const proj = editor_math.projectionMatrix(draw.camera, aspect, .perspective);
    const view_proj = editor_math.Mat4.mul(proj, view);
    const uniforms = InstancedSceneUniforms{ .view_proj = view_proj.m };
    sdl_gpu.SDL_PushGPUVertexUniformData(cmdbuf, 0, &uniforms, @intCast(@sizeOf(InstancedSceneUniforms)));
    sdl_gpu.SDL_BindGPUGraphicsPipeline(pass, self.instanced_depth_prepass_pipeline);

    const vertex_bindings = [_]sdl_gpu.SDL_GPUBufferBinding{
        .{ .buffer = vertex_buffer, .offset = 0 },
        .{ .buffer = instance_buffer, .offset = 0 },
    };
    sdl_gpu.SDL_BindGPUVertexBuffers(pass, 0, &vertex_bindings, 2);
    const index_binding = sdl_gpu.SDL_GPUBufferBinding{ .buffer = index_buffer, .offset = 0 };
    sdl_gpu.SDL_BindGPUIndexBuffer(pass, &index_binding, sdl_gpu.SDL_GPU_INDEXELEMENTSIZE_32BIT);
    sdl_gpu.SDL_DrawGPUIndexedPrimitives(pass, mesh.index_count, draw.instance_count, 0, 0, 0);
}

fn sceneUsesMsaa(self: anytype) bool {
    const sample_count = if (self.in_offscreen_frame) self.offscreen_sample_count else self.settings.sampleCount();
    return sample_count != sdl_gpu.SDL_GPU_SAMPLECOUNT_1;
}

fn drawWaterSurfacePass(self: anytype, command_buffer: *render_commands.CommandBuffer) !void {
    const cmdbuf = self.cmdbuf orelse return error.NoActiveCommandBuffer;
    if (self.render_pass) |pass| {
        sdl_gpu.SDL_EndGPURenderPass(pass);
        self.render_pass = null;
    }
    self.render_pass = try beginWaterRenderPass(self, cmdbuf);
    for (command_buffer.entries.items) |entry| {
        switch (entry.command) {
            .mesh => |draw| {
                if (draw.surface != .water) continue;
                if (draw.instance_count != 1) return error.InvalidRenderBatchInstanceCount;
                try drawMeshDraw(self, draw);
            },
            else => {},
        }
    }
}

fn drawOverlayPass(self: anytype, command_buffer: *render_commands.CommandBuffer) !void {
    for (command_buffer.entries.items) |entry| {
        switch (entry.command) {
            .overlay => |draw| try drawOverlayQuads(self, draw.quads),
            else => {},
        }
    }
}

fn beginWaterRenderPass(self: anytype, cmdbuf: *sdl_gpu.SDL_GPUCommandBuffer) !*sdl_gpu.SDL_GPURenderPass {
    const color_texture = if (self.scene_color_hdr_active)
        self.hdr_color_texture
    else if (self.in_offscreen_frame) self.offscreen_color_texture else self.swapchain_texture;
    const color_target = sdl_gpu.SDL_GPUColorTargetInfo{
        .texture = color_texture,
        .load_op = sdl_gpu.SDL_GPU_LOADOP_LOAD,
        .store_op = sdl_gpu.SDL_GPU_STOREOP_STORE,
    };
    const color_targets = [_]sdl_gpu.SDL_GPUColorTargetInfo{color_target};
    const depth_texture = if (sceneUsesMsaa(self))
        self.water_depth_texture orelse return error.MissingDepthTexture
    else
        self.depth_texture orelse return error.MissingDepthTexture;
    var depth_target = sdl_gpu.SDL_GPUDepthStencilTargetInfo{
        .texture = depth_texture,
        .clear_depth = 1,
        .load_op = sdl_gpu.SDL_GPU_LOADOP_LOAD,
        .store_op = sdl_gpu.SDL_GPU_STOREOP_DONT_CARE,
        .stencil_load_op = sdl_gpu.SDL_GPU_LOADOP_DONT_CARE,
        .stencil_store_op = sdl_gpu.SDL_GPU_STOREOP_DONT_CARE,
    };
    const render_pass = sdl_gpu.SDL_BeginGPURenderPass(cmdbuf, &color_targets, 1, &depth_target) orelse return error.RenderPassFailed;

    const viewport = sdl_gpu.SDL_GPUViewport{
        .x = 0,
        .y = 0,
        .w = @floatFromInt(self.width),
        .h = @floatFromInt(self.height),
        .min_depth = 0,
        .max_depth = 1,
    };
    sdl_gpu.SDL_SetGPUViewport(render_pass, &viewport);
    return render_pass;
}

fn wantsShadowPass(self: anytype, command_buffer: *const render_commands.CommandBuffer) bool {
    if (!self.settings.shadowsEnabled()) return false;
    if (!self.frame_lighting.shadows_enabled or !self.frame_lighting.shading_lit) return false;
    if (self.shadow_map_texture == null) return false;

    for (command_buffer.entries.items) |entry| switch (entry.command) {
        .mesh => |draw| if (draw.cast_shadows and effectiveMeshShading(self, draw.shading).castsShadows()) return true,
        .instanced_mesh => |draw| if (draw.cast_shadows and effectiveMeshShading(self, draw.shading).castsShadows() and draw.instance_count > 0) return true,
        else => {},
    };
    return false;
}

fn hasWaterDraws(command_buffer: *const render_commands.CommandBuffer) bool {
    for (command_buffer.entries.items) |entry| switch (entry.command) {
        .mesh => |draw| if (draw.surface == .water) return true,
        else => {},
    };
    return false;
}

fn hasDepthSceneDraws(command_buffer: *const render_commands.CommandBuffer) bool {
    for (command_buffer.entries.items) |entry| switch (entry.command) {
        .grid, .instanced_mesh, .grass, .wireframe_mesh => return true,
        .mesh => |draw| if (draw.surface != .water) return true,
        else => {},
    };
    return false;
}

fn hasLitDraws(command_buffer: *const render_commands.CommandBuffer) bool {
    for (command_buffer.entries.items) |entry| switch (entry.command) {
        .mesh => |draw| if (draw.surface != .water and draw.shading.castsShadows()) return true,
        .instanced_mesh => |draw| if (draw.shading.castsShadows() and draw.instance_count > 0) return true,
        else => {},
    };
    return false;
}

fn effectiveMeshShading(self: anytype, shading: render_commands.MeshShadingMode) render_commands.MeshShadingMode {
    if (shading == .rendered and !self.frame_lighting.shading_lit) return .material_preview;
    return shading;
}

pub fn clearOverlayScratch(self: anytype) void {
    overlay.clearOverlayScratch(self);
}
