const std = @import("std");
const sdl_gpu = @import("sdl_gpu.zig");
const editor_math = @import("editor_math.zig");
const shared_color = @import("color.zig");
const gpu_scene = @import("gpu_scene.zig");
const types = @import("gpu_backend_sdl_types.zig");

pub fn activeOverlayPipeline(self: anytype, material: gpu_scene.OverlayMaterial) *sdl_gpu.SDL_GPUGraphicsPipeline {
    return switch (material) {
        .rgba => if (self.in_offscreen_frame) self.offscreen_overlay_pipeline else self.overlay_pipeline,
        .coverage_mask => if (self.in_offscreen_frame) self.offscreen_overlay_mask_pipeline else self.overlay_mask_pipeline,
        .distance_field => if (self.in_offscreen_frame) self.offscreen_overlay_sdf_pipeline else self.overlay_sdf_pipeline,
    };
}

fn quadMaterial(quad: gpu_scene.OverlayQuad) gpu_scene.OverlayMaterial {
    if (quad.material != .rgba) return quad.material;
    if (quad.mask_texture) return .coverage_mask;
    return .rgba;
}

fn sameOverlayMaterial(a: gpu_scene.OverlayQuad, b: gpu_scene.OverlayQuad) bool {
    return quadMaterial(a) == quadMaterial(b);
}

fn overlaySampler(self: anytype, material: gpu_scene.OverlayMaterial) *sdl_gpu.SDL_GPUSampler {
    return switch (material) {
        .rgba => self.sampler,
        .coverage_mask, .distance_field => self.mask_sampler,
    };
}

fn overlayDebugLabel(material: gpu_scene.OverlayMaterial) [*:0]const u8 {
    return switch (material) {
        .rgba => "overlay",
        .coverage_mask => "overlay-mask",
        .distance_field => "overlay-sdf",
    };
}

fn checkSdfQuad(quad: gpu_scene.OverlayQuad) void {
    if (quad.material == .distance_field) {
        // TODO(sdf-shader): carry per-quad px_range, atlas kind, outline, and shadow uniforms.
    }
}

pub fn drawOverlayQuads(self: anytype, quads: []const gpu_scene.OverlayQuad) !void {
    if (quads.len == 0) return;
    const cmdbuf = self.cmdbuf orelse return;

    if (self.render_pass) |pass| {
        sdl_gpu.SDL_EndGPURenderPass(pass);
        self.render_pass = null;
    }

    const vertex_count = quads.len * 6;
    const vertices = try self.allocator.alloc(types.OverlayVertex, vertex_count);
    defer self.allocator.free(vertices);

    for (quads, 0..) |quad, quad_index| {
        checkSdfQuad(quad);
        writeOverlayQuadVertices(vertices[quad_index * 6 ..][0..6], quad, self.width, self.height);
    }

    try ensureOverlayVertexBuffer(self, @intCast(vertex_count * @sizeOf(types.OverlayVertex)));
    try uploadToBufferOnCommandBuffer(
        self,
        cmdbuf,
        self.overlay_vertex_buffer.?,
        std.mem.sliceAsBytes(vertices),
    );

    const render_pass = try beginOverlayRenderPass(self, cmdbuf);
    self.render_pass = render_pass;

    const identity = editor_math.Mat4.identity();
    sdl_gpu.SDL_PushGPUVertexUniformData(cmdbuf, 0, &identity.m, @intCast(@sizeOf([16]f32)));
    const vertex_bindings = [_]sdl_gpu.SDL_GPUBufferBinding{.{ .buffer = self.overlay_vertex_buffer, .offset = 0 }};
    sdl_gpu.SDL_BindGPUVertexBuffers(render_pass, 0, &vertex_bindings, 1);

    var quad_index: usize = 0;
    while (quad_index < quads.len) {
        const quad = quads[quad_index];
        if (quad.gpu_texture) |opaque_tex| {
            const texture: *sdl_gpu.SDL_GPUTexture = @ptrCast(@alignCast(opaque_tex));
            const start = quad_index;
            quad_index += 1;
            while (quad_index < quads.len and quads[quad_index].gpu_texture == opaque_tex and sameOverlayMaterial(quads[quad_index], quad)) : (quad_index += 1) {}
            try drawOverlayRun(self, render_pass, texture, quadMaterial(quad), start, quad_index - start);
        } else if (quad.texture) |source| {
            const texture = try createOverlayTextureFromSource(self, cmdbuf, source, quad.color);
            try self.overlay_textures.append(self.allocator, texture);
            const start = quad_index;
            quad_index += 1;
            while (quad_index < quads.len) {
                const next = quads[quad_index];
                const same_source = if (next.texture) |next_source|
                    std.mem.eql(u8, next_source, source)
                else
                    false;
                if (next.gpu_texture != null or !same_source or !sameOverlayMaterial(next, quad)) break;
                quad_index += 1;
            }
            try drawOverlayRun(self, render_pass, texture, quadMaterial(quad), start, quad_index - start);
        } else {
            const start = quad_index;
            quad_index += 1;
            while (quad_index < quads.len and quads[quad_index].texture == null and quads[quad_index].gpu_texture == null and sameOverlayMaterial(quads[quad_index], quad)) : (quad_index += 1) {}
            try drawOverlayRun(self, render_pass, self.white_texture, quadMaterial(quad), start, quad_index - start);
        }
    }
}

fn drawOverlayRun(
    self: anytype,
    render_pass: *sdl_gpu.SDL_GPURenderPass,
    texture: *sdl_gpu.SDL_GPUTexture,
    material: gpu_scene.OverlayMaterial,
    start_quad: usize,
    quad_count: usize,
) !void {
    if (quad_count == 0) return;
    const cmdbuf = self.cmdbuf orelse return error.NoActiveCommandBuffer;
    sdl_gpu.SDL_InsertGPUDebugLabel(cmdbuf, overlayDebugLabel(material));
    sdl_gpu.SDL_BindGPUGraphicsPipeline(render_pass, activeOverlayPipeline(self, material));
    const sampler = overlaySampler(self, material);
    const sampler_bindings = [_]sdl_gpu.SDL_GPUTextureSamplerBinding{.{ .texture = texture, .sampler = sampler }};
    sdl_gpu.SDL_BindGPUFragmentSamplers(render_pass, 0, &sampler_bindings, 1);
    sdl_gpu.SDL_DrawGPUPrimitives(render_pass, @intCast(quad_count * 6), 1, @intCast(start_quad * 6), 0);
}

pub fn clearOverlayScratch(self: anytype) void {
    clearOverlayTextures(self);
    self.overlay_textures.deinit(self.allocator);
    if (self.overlay_vertex_buffer) |buffer| {
        sdl_gpu.SDL_ReleaseGPUBuffer(self.device, buffer);
        self.overlay_vertex_buffer = null;
    }
    self.overlay_vertex_capacity_bytes = 0;
}

fn clearOverlayTextures(self: anytype) void {
    for (self.overlay_textures.items) |texture| {
        sdl_gpu.SDL_ReleaseGPUTexture(self.device, texture);
    }
    self.overlay_textures.clearRetainingCapacity();
}

fn ensureOverlayVertexBuffer(self: anytype, required_bytes: u32) !void {
    if (self.overlay_vertex_buffer != null and self.overlay_vertex_capacity_bytes >= required_bytes) return;
    if (self.overlay_vertex_buffer) |buffer| {
        sdl_gpu.SDL_ReleaseGPUBuffer(self.device, buffer);
        self.overlay_vertex_buffer = null;
    }
    const buffer = sdl_gpu.SDL_CreateGPUBuffer(self.device, &.{
        .usage = sdl_gpu.SDL_GPU_BUFFERUSAGE_VERTEX,
        .size = required_bytes,
    }) orelse return error.BufferCreateFailed;
    self.overlay_vertex_buffer = buffer;
    self.overlay_vertex_capacity_bytes = required_bytes;
}

fn uploadToBufferOnCommandBuffer(
    self: anytype,
    cmdbuf: *sdl_gpu.SDL_GPUCommandBuffer,
    buffer: *sdl_gpu.SDL_GPUBuffer,
    bytes: []const u8,
) !void {
    const transfer = sdl_gpu.SDL_CreateGPUTransferBuffer(self.device, &.{
        .usage = sdl_gpu.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = @intCast(bytes.len),
    }) orelse return error.TransferBufferCreateFailed;
    defer sdl_gpu.SDL_ReleaseGPUTransferBuffer(self.device, transfer);

    const mapped = sdl_gpu.SDL_MapGPUTransferBuffer(self.device, transfer, false) orelse return error.TransferMapFailed;
    const mapped_bytes = @as([*]u8, @ptrCast(mapped))[0..bytes.len];
    @memcpy(mapped_bytes, bytes);
    sdl_gpu.SDL_UnmapGPUTransferBuffer(self.device, transfer);

    const copy_pass = sdl_gpu.SDL_BeginGPUCopyPass(cmdbuf) orelse return error.CopyPassFailed;
    sdl_gpu.SDL_UploadToGPUBuffer(copy_pass, &.{
        .transfer_buffer = transfer,
        .offset = 0,
    }, &.{
        .buffer = buffer,
        .offset = 0,
        .size = @intCast(bytes.len),
    }, false);
    sdl_gpu.SDL_EndGPUCopyPass(copy_pass);
}

fn createOverlayTextureFromSource(
    self: anytype,
    cmdbuf: *sdl_gpu.SDL_GPUCommandBuffer,
    source: []const u8,
    color: shared_color.Color,
) !*sdl_gpu.SDL_GPUTexture {
    const texture = sdl_gpu.SDL_CreateGPUTexture(self.device, &.{
        .type = sdl_gpu.SDL_GPU_TEXTURETYPE_2D,
        .format = sdl_gpu.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
        .usage = sdl_gpu.SDL_GPU_TEXTUREUSAGE_SAMPLER,
        .width = gpu_scene.TextureSize,
        .height = gpu_scene.TextureSize,
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .sample_count = sdl_gpu.SDL_GPU_SAMPLECOUNT_1,
    }) orelse return error.TextureCreateFailed;
    errdefer sdl_gpu.SDL_ReleaseGPUTexture(self.device, texture);

    const rgba = try self.allocator.alloc(u8, gpu_scene.TextureSize * gpu_scene.TextureSize * 4);
    defer self.allocator.free(rgba);
    fillOverlayTexture(rgba, source, color);
    try uploadToTextureOnCommandBuffer(self, cmdbuf, texture, rgba, gpu_scene.TextureSize, gpu_scene.TextureSize);
    return texture;
}

pub fn createOverlayTextureFromRgba(
    self: anytype,
    rgba: []const u8,
    width: u32,
    height: u32,
) !*sdl_gpu.SDL_GPUTexture {
    const cmdbuf = self.cmdbuf orelse return error.NoActiveCommandBuffer;
    if (rgba.len != @as(usize, width) * @as(usize, height) * 4) return error.InvalidTextureUploadSize;
    endActiveRenderPass(self);
    const texture = sdl_gpu.SDL_CreateGPUTexture(self.device, &.{
        .type = sdl_gpu.SDL_GPU_TEXTURETYPE_2D,
        .format = sdl_gpu.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
        .usage = sdl_gpu.SDL_GPU_TEXTUREUSAGE_SAMPLER,
        .width = width,
        .height = height,
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .sample_count = sdl_gpu.SDL_GPU_SAMPLECOUNT_1,
    }) orelse return error.TextureCreateFailed;
    errdefer sdl_gpu.SDL_ReleaseGPUTexture(self.device, texture);

    try uploadToTextureOnCommandBuffer(self, cmdbuf, texture, rgba, width, height);
    return texture;
}

pub fn updateOverlayTextureFromRgba(
    self: anytype,
    texture: *sdl_gpu.SDL_GPUTexture,
    rgba: []const u8,
    width: u32,
    height: u32,
) !void {
    const cmdbuf = self.cmdbuf orelse return error.NoActiveCommandBuffer;
    if (rgba.len != @as(usize, width) * @as(usize, height) * 4) return error.InvalidTextureUploadSize;
    endActiveRenderPass(self);
    try uploadToTextureOnCommandBuffer(self, cmdbuf, texture, rgba, width, height);
}

fn endActiveRenderPass(self: anytype) void {
    if (self.render_pass) |pass| {
        sdl_gpu.SDL_EndGPURenderPass(pass);
        self.render_pass = null;
    }
}

fn uploadToTextureOnCommandBuffer(
    self: anytype,
    cmdbuf: *sdl_gpu.SDL_GPUCommandBuffer,
    texture: *sdl_gpu.SDL_GPUTexture,
    rgba: []const u8,
    width: u32,
    height: u32,
) !void {
    const transfer = sdl_gpu.SDL_CreateGPUTransferBuffer(self.device, &.{
        .usage = sdl_gpu.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = @intCast(rgba.len),
    }) orelse return error.TransferBufferCreateFailed;
    defer sdl_gpu.SDL_ReleaseGPUTransferBuffer(self.device, transfer);

    const mapped = sdl_gpu.SDL_MapGPUTransferBuffer(self.device, transfer, false) orelse return error.TransferMapFailed;
    const mapped_rgba = @as([*]u8, @ptrCast(mapped))[0..rgba.len];
    @memcpy(mapped_rgba, rgba);
    sdl_gpu.SDL_UnmapGPUTransferBuffer(self.device, transfer);

    const copy_pass = sdl_gpu.SDL_BeginGPUCopyPass(cmdbuf) orelse return error.CopyPassFailed;
    sdl_gpu.SDL_UploadToGPUTexture(copy_pass, &.{
        .transfer_buffer = transfer,
        .offset = 0,
        .pixels_per_row = width,
        .rows_per_layer = height,
    }, &.{
        .texture = texture,
        .w = width,
        .h = height,
        .d = 1,
    }, false);
    sdl_gpu.SDL_EndGPUCopyPass(copy_pass);
}

fn beginOverlayRenderPass(self: anytype, cmdbuf: *sdl_gpu.SDL_GPUCommandBuffer) !*sdl_gpu.SDL_GPURenderPass {
    const color_texture = if (self.in_offscreen_frame) self.offscreen_color_texture else self.swapchain_texture;
    const color_target = sdl_gpu.SDL_GPUColorTargetInfo{
        .texture = color_texture,
        .load_op = sdl_gpu.SDL_GPU_LOADOP_LOAD,
        .store_op = sdl_gpu.SDL_GPU_STOREOP_STORE,
    };
    const color_targets = [_]sdl_gpu.SDL_GPUColorTargetInfo{color_target};
    const render_pass = sdl_gpu.SDL_BeginGPURenderPass(cmdbuf, &color_targets, 1, null) orelse return error.RenderPassFailed;

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

pub fn writeOverlayQuadVertices(
    out: []types.OverlayVertex,
    quad: gpu_scene.OverlayQuad,
    width: u32,
    height: u32,
) void {
    std.debug.assert(out.len >= 6);
    const x = quad.rect[0];
    const y = quad.rect[1];
    const w = quad.rect[2];
    const h = quad.rect[3];
    const left = pixelXToClip(x, width);
    const right = pixelXToClip(x + w, width);
    const skewed_left = pixelXToClip(x + quad.skew_x, width);
    const skewed_right = pixelXToClip(x + w + quad.skew_x, width);
    const top = pixelYToClip(y, height);
    const bottom = pixelYToClip(y + h, height);

    const uv_left = quad.uv[0];
    const uv_top = quad.uv[1];
    const uv_right = quad.uv[2];
    const uv_bottom = quad.uv[3];
    const color = quad.color;

    out[0] = overlayVertex(skewed_left, top, uv_left, uv_top, color);
    out[1] = overlayVertex(skewed_right, top, uv_right, uv_top, color);
    out[2] = overlayVertex(right, bottom, uv_right, uv_bottom, color);
    out[3] = overlayVertex(skewed_left, top, uv_left, uv_top, color);
    out[4] = overlayVertex(right, bottom, uv_right, uv_bottom, color);
    out[5] = overlayVertex(left, bottom, uv_left, uv_bottom, color);
}

fn overlayVertex(x: f32, y: f32, u: f32, v: f32, color: shared_color.Color) types.OverlayVertex {
    return .{
        .x = x,
        .y = y,
        .z = 0,
        .w = 1,
        .u = u,
        .v = v,
        .r = color.r,
        .g = color.g,
        .b = color.b,
        .a = color.a,
    };
}

fn pixelXToClip(x: f32, width: u32) f32 {
    return (x / @as(f32, @floatFromInt(@max(1, width)))) * 2.0 - 1.0;
}

fn pixelYToClip(y: f32, height: u32) f32 {
    return 1.0 - (y / @as(f32, @floatFromInt(@max(1, height)))) * 2.0;
}

pub fn fillSolidOverlayTexture(dest: []u8, color: shared_color.Color) void {
    var i: usize = 0;
    while (i + 3 < dest.len) : (i += 4) {
        dest[i] = 255;
        dest[i + 1] = 255;
        dest[i + 2] = 255;
        dest[i + 3] = 255;
    }
    _ = color;
}

pub fn fillOverlayTexture(dest: []u8, source: []const u8, color: shared_color.Color) void {
    const len = @min(dest.len, source.len);
    var i: usize = 0;
    while (i + 3 < len) : (i += 4) {
        dest[i] = source[i];
        dest[i + 1] = source[i + 1];
        dest[i + 2] = source[i + 2];
        dest[i + 3] = source[i + 3];
    }
    while (i + 3 < dest.len) : (i += 4) {
        dest[i] = 0;
        dest[i + 1] = 0;
        dest[i + 2] = 0;
        dest[i + 3] = 0;
    }
    _ = color;
}

test "overlay quad vertices convert pixel rect to clip space" {
    var vertices: [6]types.OverlayVertex = undefined;
    writeOverlayQuadVertices(&vertices, .{
        .rect = .{ 0, 0, 100, 50 },
        .uv = .{ 0.25, 0.5, 0.75, 1.0 },
        .color = .{ .r = 10, .g = 20, .b = 30, .a = 40 },
    }, 200, 100);

    try std.testing.expectEqual(@as(f32, -1.0), vertices[0].x);
    try std.testing.expectEqual(@as(f32, 1.0), vertices[0].y);
    try std.testing.expectEqual(@as(f32, 0.0), vertices[2].x);
    try std.testing.expectEqual(@as(f32, 0.0), vertices[2].y);
    try std.testing.expectEqual(@as(f32, 0.25), vertices[0].u);
    try std.testing.expectEqual(@as(f32, 1.0), vertices[2].v);
    try std.testing.expectEqual(@as(u8, 40), vertices[5].a);
}

test "overlay texture fill copies source and pads missing pixels" {
    const source = [_]u8{ 1, 2, 3, 4 };
    var pixels: [8]u8 = undefined;
    fillOverlayTexture(&pixels, &source, .{ .r = 255, .g = 255, .b = 255, .a = 255 });

    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4 }, pixels[0..4]);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0 }, pixels[4..8]);
}
