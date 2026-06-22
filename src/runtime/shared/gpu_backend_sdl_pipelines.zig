const std = @import("std");
const sdl_gpu = @import("sdl_gpu.zig");
const editor_math = @import("editor_math.zig");
const types = @import("gpu_backend_sdl_types.zig");

pub fn mat4FromFlat(flat: [16]f32) editor_math.Mat4 {
    return .{ .m = flat };
}

pub fn createShader(
    device: *sdl_gpu.SDL_GPUDevice,
    comptime path: []const u8,
    stage: sdl_gpu.SDL_GPUShaderStage,
    num_samplers: u32,
    num_uniform_buffers: u32,
) !*sdl_gpu.SDL_GPUShader {
    const bytes = sdl_gpu.shaderBytes(path);
    var info = sdl_gpu.SDL_GPUShaderCreateInfo{
        .code_size = bytes.code.len,
        .code = bytes.code.ptr,
        .entrypoint = bytes.entrypoint,
        .format = bytes.format,
        .stage = stage,
        .num_samplers = num_samplers,
        .num_storage_textures = 0,
        .num_storage_buffers = 0,
        .num_uniform_buffers = num_uniform_buffers,
        .props = 0,
    };
    return sdl_gpu.SDL_CreateGPUShader(device, &info) orelse error.ShaderCreateFailed;
}

fn initMeshVertexInput(
    vb_descs: *[1]sdl_gpu.SDL_GPUVertexBufferDescription,
    attrs: *[3]sdl_gpu.SDL_GPUVertexAttribute,
) sdl_gpu.SDL_GPUVertexInputState {
    vb_descs.* = .{.{
        .slot = 0,
        .pitch = @sizeOf(types.SdlGpuVertex),
        .input_rate = sdl_gpu.SDL_GPU_VERTEXINPUTRATE_VERTEX,
        .instance_step_rate = 0,
    }};
    attrs.* = .{
        .{ .location = 0, .buffer_slot = 0, .format = sdl_gpu.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4, .offset = 0 },
        .{ .location = 1, .buffer_slot = 0, .format = sdl_gpu.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3, .offset = @offsetOf(types.SdlGpuVertex, "nx") },
        .{ .location = 2, .buffer_slot = 0, .format = sdl_gpu.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2, .offset = @offsetOf(types.SdlGpuVertex, "u") },
    };
    return .{
        .vertex_buffer_descriptions = @ptrCast(vb_descs),
        .num_vertex_buffers = 1,
        .vertex_attributes = @ptrCast(attrs),
        .num_vertex_attributes = 3,
    };
}

fn initInstancedMeshVertexInput(
    vb_descs: *[2]sdl_gpu.SDL_GPUVertexBufferDescription,
    attrs: *[7]sdl_gpu.SDL_GPUVertexAttribute,
) sdl_gpu.SDL_GPUVertexInputState {
    vb_descs.* = .{
        .{
            .slot = 0,
            .pitch = @sizeOf(types.SdlGpuVertex),
            .input_rate = sdl_gpu.SDL_GPU_VERTEXINPUTRATE_VERTEX,
            .instance_step_rate = 0,
        },
        .{
            .slot = 1,
            .pitch = @sizeOf(types.GpuMeshInstance),
            .input_rate = sdl_gpu.SDL_GPU_VERTEXINPUTRATE_INSTANCE,
            .instance_step_rate = 0,
        },
    };
    attrs.* = .{
        .{ .location = 0, .buffer_slot = 0, .format = sdl_gpu.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4, .offset = 0 },
        .{ .location = 1, .buffer_slot = 0, .format = sdl_gpu.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3, .offset = @offsetOf(types.SdlGpuVertex, "nx") },
        .{ .location = 2, .buffer_slot = 0, .format = sdl_gpu.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2, .offset = @offsetOf(types.SdlGpuVertex, "u") },
        .{ .location = 3, .buffer_slot = 1, .format = sdl_gpu.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4, .offset = 0 },
        .{ .location = 4, .buffer_slot = 1, .format = sdl_gpu.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4, .offset = 16 },
        .{ .location = 5, .buffer_slot = 1, .format = sdl_gpu.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4, .offset = 32 },
        .{ .location = 6, .buffer_slot = 1, .format = sdl_gpu.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4, .offset = 48 },
    };
    return .{
        .vertex_buffer_descriptions = @ptrCast(vb_descs),
        .num_vertex_buffers = 2,
        .vertex_attributes = @ptrCast(attrs),
        .num_vertex_attributes = 7,
    };
}


fn initGrassVertexInput(
    vb_descs: *[1]sdl_gpu.SDL_GPUVertexBufferDescription,
    attrs: *[4]sdl_gpu.SDL_GPUVertexAttribute,
) sdl_gpu.SDL_GPUVertexInputState {
    vb_descs.* = .{.{
        .slot = 0,
        .pitch = @sizeOf(types.GpuGrassInstance),
        .input_rate = sdl_gpu.SDL_GPU_VERTEXINPUTRATE_INSTANCE,
        .instance_step_rate = 0,
    }};
    attrs.* = .{
        .{ .location = 0, .buffer_slot = 0, .format = sdl_gpu.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4, .offset = @offsetOf(types.GpuGrassInstance, "position") },
        .{ .location = 1, .buffer_slot = 0, .format = sdl_gpu.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4, .offset = @offsetOf(types.GpuGrassInstance, "normal_height") },
        .{ .location = 2, .buffer_slot = 0, .format = sdl_gpu.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4, .offset = @offsetOf(types.GpuGrassInstance, "color") },
        .{ .location = 3, .buffer_slot = 0, .format = sdl_gpu.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4, .offset = @offsetOf(types.GpuGrassInstance, "blade") },
    };
    return .{
        .vertex_buffer_descriptions = @ptrCast(vb_descs),
        .num_vertex_buffers = 1,
        .vertex_attributes = @ptrCast(attrs),
        .num_vertex_attributes = 4,
    };
}

fn initMeshTargetInfo(
    color_targets: *[1]sdl_gpu.SDL_GPUColorTargetDescription,
    swapchain_format: sdl_gpu.SDL_GPUTextureFormat,
) sdl_gpu.SDL_GPUGraphicsPipelineTargetInfo {
    color_targets.* = .{.{ .format = swapchain_format }};
    return .{
        .color_target_descriptions = @ptrCast(color_targets),
        .num_color_targets = 1,
        .depth_stencil_format = sdl_gpu.SDL_GPU_TEXTUREFORMAT_D32_FLOAT,
        .has_depth_stencil_target = true,
    };
}

pub fn createMeshPipeline(
    device: *sdl_gpu.SDL_GPUDevice,
    swapchain_format: sdl_gpu.SDL_GPUTextureFormat,
    sample_count: sdl_gpu.SDL_GPUSampleCount,
) !*sdl_gpu.SDL_GPUGraphicsPipeline {
    return createMeshPipelineWithCullMode(device, swapchain_format, sample_count, sdl_gpu.SDL_GPU_CULLMODE_BACK);
}

pub fn createDoubleSidedMeshPipeline(
    device: *sdl_gpu.SDL_GPUDevice,
    swapchain_format: sdl_gpu.SDL_GPUTextureFormat,
    sample_count: sdl_gpu.SDL_GPUSampleCount,
) !*sdl_gpu.SDL_GPUGraphicsPipeline {
    return createMeshPipelineWithCullMode(device, swapchain_format, sample_count, sdl_gpu.SDL_GPU_CULLMODE_NONE);
}

pub fn createWaterPipeline(
    device: *sdl_gpu.SDL_GPUDevice,
    swapchain_format: sdl_gpu.SDL_GPUTextureFormat,
    sample_count: sdl_gpu.SDL_GPUSampleCount,
) !*sdl_gpu.SDL_GPUGraphicsPipeline {
    const vertex_shader = try createShader(device, "TexturedQuadWithMatrix.vert", sdl_gpu.SDL_GPU_SHADERSTAGE_VERTEX, 0, 1);
    defer sdl_gpu.SDL_ReleaseGPUShader(device, vertex_shader);
    const fragment_shader = try createShader(device, "WaterSurface.frag", sdl_gpu.SDL_GPU_SHADERSTAGE_FRAGMENT, 1, 0);
    defer sdl_gpu.SDL_ReleaseGPUShader(device, fragment_shader);

    var vb_descs: [1]sdl_gpu.SDL_GPUVertexBufferDescription = undefined;
    var attrs: [3]sdl_gpu.SDL_GPUVertexAttribute = undefined;
    const blend = sdl_gpu.SDL_GPUColorTargetBlendState{
        .src_color_blendfactor = sdl_gpu.SDL_GPU_BLENDFACTOR_SRC_ALPHA,
        .dst_color_blendfactor = sdl_gpu.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
        .color_blend_op = sdl_gpu.SDL_GPU_BLENDOP_ADD,
        .src_alpha_blendfactor = sdl_gpu.SDL_GPU_BLENDFACTOR_ONE,
        .dst_alpha_blendfactor = sdl_gpu.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
        .alpha_blend_op = sdl_gpu.SDL_GPU_BLENDOP_ADD,
        .enable_blend = true,
    };
    var color_targets = [1]sdl_gpu.SDL_GPUColorTargetDescription{
        .{ .format = swapchain_format, .blend_state = blend },
    };

    var pipeline_info = sdl_gpu.SDL_GPUGraphicsPipelineCreateInfo{
        .vertex_shader = vertex_shader,
        .fragment_shader = fragment_shader,
        .vertex_input_state = initMeshVertexInput(&vb_descs, &attrs),
        .primitive_type = sdl_gpu.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .rasterizer_state = .{
            .cull_mode = sdl_gpu.SDL_GPU_CULLMODE_NONE,
            .front_face = sdl_gpu.SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE,
        },
        .depth_stencil_state = .{
            .enable_depth_test = true,
            .enable_depth_write = false,
            .compare_op = sdl_gpu.SDL_GPU_COMPAREOP_LESS_OR_EQUAL,
        },
        .multisample_state = .{ .sample_count = sample_count },
        .target_info = .{
            .color_target_descriptions = @ptrCast(&color_targets),
            .num_color_targets = 1,
            .depth_stencil_format = sdl_gpu.SDL_GPU_TEXTUREFORMAT_D32_FLOAT,
            .has_depth_stencil_target = true,
        },
    };

    return sdl_gpu.SDL_CreateGPUGraphicsPipeline(device, &pipeline_info) orelse error.PipelineCreateFailed;
}

fn createMeshPipelineWithCullMode(
    device: *sdl_gpu.SDL_GPUDevice,
    swapchain_format: sdl_gpu.SDL_GPUTextureFormat,
    sample_count: sdl_gpu.SDL_GPUSampleCount,
    cull_mode: sdl_gpu.SDL_GPUCullMode,
) !*sdl_gpu.SDL_GPUGraphicsPipeline {
    const vertex_shader = try createShader(device, "TexturedQuadWithMatrix.vert", sdl_gpu.SDL_GPU_SHADERSTAGE_VERTEX, 0, 1);
    defer sdl_gpu.SDL_ReleaseGPUShader(device, vertex_shader);
    const fragment_shader = try createShader(device, "TexturedQuad.frag", sdl_gpu.SDL_GPU_SHADERSTAGE_FRAGMENT, 1, 0);
    defer sdl_gpu.SDL_ReleaseGPUShader(device, fragment_shader);

    var vb_descs: [1]sdl_gpu.SDL_GPUVertexBufferDescription = undefined;
    var attrs: [3]sdl_gpu.SDL_GPUVertexAttribute = undefined;
    var color_targets: [1]sdl_gpu.SDL_GPUColorTargetDescription = undefined;

    var pipeline_info = sdl_gpu.SDL_GPUGraphicsPipelineCreateInfo{
        .vertex_shader = vertex_shader,
        .fragment_shader = fragment_shader,
        .vertex_input_state = initMeshVertexInput(&vb_descs, &attrs),
        .primitive_type = sdl_gpu.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .rasterizer_state = .{
            .cull_mode = cull_mode,
            .front_face = sdl_gpu.SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE,
        },
        .depth_stencil_state = .{
            .enable_depth_test = true,
            .enable_depth_write = true,
            .compare_op = sdl_gpu.SDL_GPU_COMPAREOP_LESS,
        },
        .multisample_state = .{ .sample_count = sample_count },
        .target_info = initMeshTargetInfo(&color_targets, swapchain_format),
    };

    return sdl_gpu.SDL_CreateGPUGraphicsPipeline(device, &pipeline_info) orelse error.PipelineCreateFailed;
}

pub fn createLitMeshPipeline(
    device: *sdl_gpu.SDL_GPUDevice,
    swapchain_format: sdl_gpu.SDL_GPUTextureFormat,
    sample_count: sdl_gpu.SDL_GPUSampleCount,
) !*sdl_gpu.SDL_GPUGraphicsPipeline {
    return createLitMeshPipelineWithCullMode(device, swapchain_format, sample_count, sdl_gpu.SDL_GPU_CULLMODE_BACK);
}

pub fn createDoubleSidedLitMeshPipeline(
    device: *sdl_gpu.SDL_GPUDevice,
    swapchain_format: sdl_gpu.SDL_GPUTextureFormat,
    sample_count: sdl_gpu.SDL_GPUSampleCount,
) !*sdl_gpu.SDL_GPUGraphicsPipeline {
    return createLitMeshPipelineWithCullMode(device, swapchain_format, sample_count, sdl_gpu.SDL_GPU_CULLMODE_NONE);
}

pub fn createSolidMeshPipeline(
    device: *sdl_gpu.SDL_GPUDevice,
    swapchain_format: sdl_gpu.SDL_GPUTextureFormat,
    sample_count: sdl_gpu.SDL_GPUSampleCount,
) !*sdl_gpu.SDL_GPUGraphicsPipeline {
    return createSolidMeshPipelineWithCullMode(device, swapchain_format, sample_count, sdl_gpu.SDL_GPU_CULLMODE_BACK);
}

pub fn createDoubleSidedSolidMeshPipeline(
    device: *sdl_gpu.SDL_GPUDevice,
    swapchain_format: sdl_gpu.SDL_GPUTextureFormat,
    sample_count: sdl_gpu.SDL_GPUSampleCount,
) !*sdl_gpu.SDL_GPUGraphicsPipeline {
    return createSolidMeshPipelineWithCullMode(device, swapchain_format, sample_count, sdl_gpu.SDL_GPU_CULLMODE_NONE);
}

fn createLitMeshPipelineWithCullMode(
    device: *sdl_gpu.SDL_GPUDevice,
    swapchain_format: sdl_gpu.SDL_GPUTextureFormat,
    sample_count: sdl_gpu.SDL_GPUSampleCount,
    cull_mode: sdl_gpu.SDL_GPUCullMode,
) !*sdl_gpu.SDL_GPUGraphicsPipeline {
    const vertex_shader = try createShader(device, "TexturedQuadWithMatrix.vert", sdl_gpu.SDL_GPU_SHADERSTAGE_VERTEX, 0, 1);
    defer sdl_gpu.SDL_ReleaseGPUShader(device, vertex_shader);
    const fragment_shader = try createShader(device, "TexturedQuadLit.frag", sdl_gpu.SDL_GPU_SHADERSTAGE_FRAGMENT, 2, 1);
    defer sdl_gpu.SDL_ReleaseGPUShader(device, fragment_shader);

    var vb_descs: [1]sdl_gpu.SDL_GPUVertexBufferDescription = undefined;
    var attrs: [3]sdl_gpu.SDL_GPUVertexAttribute = undefined;
    var color_targets: [1]sdl_gpu.SDL_GPUColorTargetDescription = undefined;

    var pipeline_info = sdl_gpu.SDL_GPUGraphicsPipelineCreateInfo{
        .vertex_shader = vertex_shader,
        .fragment_shader = fragment_shader,
        .vertex_input_state = initMeshVertexInput(&vb_descs, &attrs),
        .primitive_type = sdl_gpu.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .rasterizer_state = .{
            .cull_mode = cull_mode,
            .front_face = sdl_gpu.SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE,
        },
        .depth_stencil_state = .{
            .enable_depth_test = true,
            .enable_depth_write = true,
            .compare_op = sdl_gpu.SDL_GPU_COMPAREOP_LESS,
        },
        .multisample_state = .{ .sample_count = sample_count },
        .target_info = initMeshTargetInfo(&color_targets, swapchain_format),
    };

    return sdl_gpu.SDL_CreateGPUGraphicsPipeline(device, &pipeline_info) orelse error.PipelineCreateFailed;
}

fn createSolidMeshPipelineWithCullMode(
    device: *sdl_gpu.SDL_GPUDevice,
    swapchain_format: sdl_gpu.SDL_GPUTextureFormat,
    sample_count: sdl_gpu.SDL_GPUSampleCount,
    cull_mode: sdl_gpu.SDL_GPUCullMode,
) !*sdl_gpu.SDL_GPUGraphicsPipeline {
    const vertex_shader = try createShader(device, "TexturedQuadWithMatrix.vert", sdl_gpu.SDL_GPU_SHADERSTAGE_VERTEX, 0, 1);
    defer sdl_gpu.SDL_ReleaseGPUShader(device, vertex_shader);
    const fragment_shader = try createShader(device, "SolidShaded.frag", sdl_gpu.SDL_GPU_SHADERSTAGE_FRAGMENT, 0, 0);
    defer sdl_gpu.SDL_ReleaseGPUShader(device, fragment_shader);

    var vb_descs: [1]sdl_gpu.SDL_GPUVertexBufferDescription = undefined;
    var attrs: [3]sdl_gpu.SDL_GPUVertexAttribute = undefined;
    var color_targets: [1]sdl_gpu.SDL_GPUColorTargetDescription = undefined;

    var pipeline_info = sdl_gpu.SDL_GPUGraphicsPipelineCreateInfo{
        .vertex_shader = vertex_shader,
        .fragment_shader = fragment_shader,
        .vertex_input_state = initMeshVertexInput(&vb_descs, &attrs),
        .primitive_type = sdl_gpu.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .rasterizer_state = .{
            .cull_mode = cull_mode,
            .front_face = sdl_gpu.SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE,
        },
        .depth_stencil_state = .{
            .enable_depth_test = true,
            .enable_depth_write = true,
            .compare_op = sdl_gpu.SDL_GPU_COMPAREOP_LESS,
        },
        .multisample_state = .{ .sample_count = sample_count },
        .target_info = initMeshTargetInfo(&color_targets, swapchain_format),
    };

    return sdl_gpu.SDL_CreateGPUGraphicsPipeline(device, &pipeline_info) orelse error.PipelineCreateFailed;
}


pub fn createGrassPipeline(
    device: *sdl_gpu.SDL_GPUDevice,
    swapchain_format: sdl_gpu.SDL_GPUTextureFormat,
    sample_count: sdl_gpu.SDL_GPUSampleCount,
) !*sdl_gpu.SDL_GPUGraphicsPipeline {
    const vertex_shader = try createShader(device, "GrassBlade.vert", sdl_gpu.SDL_GPU_SHADERSTAGE_VERTEX, 0, 1);
    defer sdl_gpu.SDL_ReleaseGPUShader(device, vertex_shader);
    const fragment_shader = try createShader(device, "GrassBlade.frag", sdl_gpu.SDL_GPU_SHADERSTAGE_FRAGMENT, 0, 0);
    defer sdl_gpu.SDL_ReleaseGPUShader(device, fragment_shader);

    var vb_descs: [1]sdl_gpu.SDL_GPUVertexBufferDescription = undefined;
    var attrs: [4]sdl_gpu.SDL_GPUVertexAttribute = undefined;
    const blend = sdl_gpu.SDL_GPUColorTargetBlendState{
        .src_color_blendfactor = sdl_gpu.SDL_GPU_BLENDFACTOR_SRC_ALPHA,
        .dst_color_blendfactor = sdl_gpu.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
        .color_blend_op = sdl_gpu.SDL_GPU_BLENDOP_ADD,
        .src_alpha_blendfactor = sdl_gpu.SDL_GPU_BLENDFACTOR_ONE,
        .dst_alpha_blendfactor = sdl_gpu.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
        .alpha_blend_op = sdl_gpu.SDL_GPU_BLENDOP_ADD,
        .enable_blend = true,
    };
    var color_targets = [1]sdl_gpu.SDL_GPUColorTargetDescription{
        .{ .format = swapchain_format, .blend_state = blend },
    };

    var pipeline_info = sdl_gpu.SDL_GPUGraphicsPipelineCreateInfo{
        .vertex_shader = vertex_shader,
        .fragment_shader = fragment_shader,
        .vertex_input_state = initGrassVertexInput(&vb_descs, &attrs),
        .primitive_type = sdl_gpu.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .rasterizer_state = .{
            .cull_mode = sdl_gpu.SDL_GPU_CULLMODE_NONE,
            .front_face = sdl_gpu.SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE,
        },
        .depth_stencil_state = .{
            .enable_depth_test = true,
            .enable_depth_write = false,
            .compare_op = sdl_gpu.SDL_GPU_COMPAREOP_LESS_OR_EQUAL,
        },
        .multisample_state = .{ .sample_count = sample_count },
        .target_info = .{
            .color_target_descriptions = @ptrCast(&color_targets),
            .num_color_targets = 1,
            .depth_stencil_format = sdl_gpu.SDL_GPU_TEXTUREFORMAT_D32_FLOAT,
            .has_depth_stencil_target = true,
        },
    };

    return sdl_gpu.SDL_CreateGPUGraphicsPipeline(device, &pipeline_info) orelse error.PipelineCreateFailed;
}

pub fn createInstancedMeshPipeline(
    device: *sdl_gpu.SDL_GPUDevice,
    swapchain_format: sdl_gpu.SDL_GPUTextureFormat,
    sample_count: sdl_gpu.SDL_GPUSampleCount,
) !*sdl_gpu.SDL_GPUGraphicsPipeline {
    const vertex_shader = try createShader(device, "TexturedQuadInstanced.vert", sdl_gpu.SDL_GPU_SHADERSTAGE_VERTEX, 0, 1);
    defer sdl_gpu.SDL_ReleaseGPUShader(device, vertex_shader);
    const fragment_shader = try createShader(device, "TexturedQuad.frag", sdl_gpu.SDL_GPU_SHADERSTAGE_FRAGMENT, 1, 0);
    defer sdl_gpu.SDL_ReleaseGPUShader(device, fragment_shader);

    var vb_descs: [2]sdl_gpu.SDL_GPUVertexBufferDescription = undefined;
    var attrs: [7]sdl_gpu.SDL_GPUVertexAttribute = undefined;
    var color_targets: [1]sdl_gpu.SDL_GPUColorTargetDescription = undefined;

    var pipeline_info = sdl_gpu.SDL_GPUGraphicsPipelineCreateInfo{
        .vertex_shader = vertex_shader,
        .fragment_shader = fragment_shader,
        .vertex_input_state = initInstancedMeshVertexInput(&vb_descs, &attrs),
        .primitive_type = sdl_gpu.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .rasterizer_state = .{
            .cull_mode = sdl_gpu.SDL_GPU_CULLMODE_BACK,
            .front_face = sdl_gpu.SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE,
        },
        .depth_stencil_state = .{
            .enable_depth_test = true,
            .enable_depth_write = true,
            .compare_op = sdl_gpu.SDL_GPU_COMPAREOP_LESS,
        },
        .multisample_state = .{ .sample_count = sample_count },
        .target_info = initMeshTargetInfo(&color_targets, swapchain_format),
    };

    return sdl_gpu.SDL_CreateGPUGraphicsPipeline(device, &pipeline_info) orelse error.PipelineCreateFailed;
}

pub fn createSolidInstancedMeshPipeline(
    device: *sdl_gpu.SDL_GPUDevice,
    swapchain_format: sdl_gpu.SDL_GPUTextureFormat,
    sample_count: sdl_gpu.SDL_GPUSampleCount,
) !*sdl_gpu.SDL_GPUGraphicsPipeline {
    const vertex_shader = try createShader(device, "TexturedQuadInstanced.vert", sdl_gpu.SDL_GPU_SHADERSTAGE_VERTEX, 0, 1);
    defer sdl_gpu.SDL_ReleaseGPUShader(device, vertex_shader);
    const fragment_shader = try createShader(device, "SolidShaded.frag", sdl_gpu.SDL_GPU_SHADERSTAGE_FRAGMENT, 0, 0);
    defer sdl_gpu.SDL_ReleaseGPUShader(device, fragment_shader);

    var vb_descs: [2]sdl_gpu.SDL_GPUVertexBufferDescription = undefined;
    var attrs: [7]sdl_gpu.SDL_GPUVertexAttribute = undefined;
    var color_targets: [1]sdl_gpu.SDL_GPUColorTargetDescription = undefined;

    var pipeline_info = sdl_gpu.SDL_GPUGraphicsPipelineCreateInfo{
        .vertex_shader = vertex_shader,
        .fragment_shader = fragment_shader,
        .vertex_input_state = initInstancedMeshVertexInput(&vb_descs, &attrs),
        .primitive_type = sdl_gpu.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .rasterizer_state = .{
            .cull_mode = sdl_gpu.SDL_GPU_CULLMODE_BACK,
            .front_face = sdl_gpu.SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE,
        },
        .depth_stencil_state = .{
            .enable_depth_test = true,
            .enable_depth_write = true,
            .compare_op = sdl_gpu.SDL_GPU_COMPAREOP_LESS,
        },
        .multisample_state = .{ .sample_count = sample_count },
        .target_info = initMeshTargetInfo(&color_targets, swapchain_format),
    };

    return sdl_gpu.SDL_CreateGPUGraphicsPipeline(device, &pipeline_info) orelse error.PipelineCreateFailed;
}

pub fn createLitInstancedMeshPipeline(
    device: *sdl_gpu.SDL_GPUDevice,
    swapchain_format: sdl_gpu.SDL_GPUTextureFormat,
    sample_count: sdl_gpu.SDL_GPUSampleCount,
) !*sdl_gpu.SDL_GPUGraphicsPipeline {
    const vertex_shader = try createShader(device, "TexturedQuadInstanced.vert", sdl_gpu.SDL_GPU_SHADERSTAGE_VERTEX, 0, 1);
    defer sdl_gpu.SDL_ReleaseGPUShader(device, vertex_shader);
    const fragment_shader = try createShader(device, "TexturedQuadLit.frag", sdl_gpu.SDL_GPU_SHADERSTAGE_FRAGMENT, 2, 1);
    defer sdl_gpu.SDL_ReleaseGPUShader(device, fragment_shader);

    var vb_descs: [2]sdl_gpu.SDL_GPUVertexBufferDescription = undefined;
    var attrs: [7]sdl_gpu.SDL_GPUVertexAttribute = undefined;
    var color_targets: [1]sdl_gpu.SDL_GPUColorTargetDescription = undefined;

    var pipeline_info = sdl_gpu.SDL_GPUGraphicsPipelineCreateInfo{
        .vertex_shader = vertex_shader,
        .fragment_shader = fragment_shader,
        .vertex_input_state = initInstancedMeshVertexInput(&vb_descs, &attrs),
        .primitive_type = sdl_gpu.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .rasterizer_state = .{
            .cull_mode = sdl_gpu.SDL_GPU_CULLMODE_BACK,
            .front_face = sdl_gpu.SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE,
        },
        .depth_stencil_state = .{
            .enable_depth_test = true,
            .enable_depth_write = true,
            .compare_op = sdl_gpu.SDL_GPU_COMPAREOP_LESS,
        },
        .multisample_state = .{ .sample_count = sample_count },
        .target_info = initMeshTargetInfo(&color_targets, swapchain_format),
    };

    return sdl_gpu.SDL_CreateGPUGraphicsPipeline(device, &pipeline_info) orelse error.PipelineCreateFailed;
}

pub fn createInstancedShadowPipeline(device: *sdl_gpu.SDL_GPUDevice) !*sdl_gpu.SDL_GPUGraphicsPipeline {
    const vertex_shader = try createShader(device, "ShadowDepthInstanced.vert", sdl_gpu.SDL_GPU_SHADERSTAGE_VERTEX, 0, 1);
    defer sdl_gpu.SDL_ReleaseGPUShader(device, vertex_shader);
    const fragment_shader = try createShader(device, "ShadowDepth.frag", sdl_gpu.SDL_GPU_SHADERSTAGE_FRAGMENT, 0, 0);
    defer sdl_gpu.SDL_ReleaseGPUShader(device, fragment_shader);

    const target_info = sdl_gpu.SDL_GPUGraphicsPipelineTargetInfo{
        .color_target_descriptions = null,
        .num_color_targets = 0,
        .depth_stencil_format = sdl_gpu.SDL_GPU_TEXTUREFORMAT_D16_UNORM,
        .has_depth_stencil_target = true,
    };

    var vb_descs: [2]sdl_gpu.SDL_GPUVertexBufferDescription = undefined;
    var attrs: [7]sdl_gpu.SDL_GPUVertexAttribute = undefined;

    var pipeline_info = sdl_gpu.SDL_GPUGraphicsPipelineCreateInfo{
        .vertex_shader = vertex_shader,
        .fragment_shader = fragment_shader,
        .vertex_input_state = initInstancedMeshVertexInput(&vb_descs, &attrs),
        .primitive_type = sdl_gpu.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .rasterizer_state = .{
            .cull_mode = sdl_gpu.SDL_GPU_CULLMODE_BACK,
            .front_face = sdl_gpu.SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE,
        },
        .depth_stencil_state = .{
            .enable_depth_test = true,
            .enable_depth_write = true,
            .compare_op = sdl_gpu.SDL_GPU_COMPAREOP_LESS_OR_EQUAL,
        },
        .target_info = target_info,
    };

    return sdl_gpu.SDL_CreateGPUGraphicsPipeline(device, &pipeline_info) orelse error.PipelineCreateFailed;
}

pub fn createShadowPipeline(device: *sdl_gpu.SDL_GPUDevice) !*sdl_gpu.SDL_GPUGraphicsPipeline {
    const vertex_shader = try createShader(device, "ShadowDepth.vert", sdl_gpu.SDL_GPU_SHADERSTAGE_VERTEX, 0, 1);
    defer sdl_gpu.SDL_ReleaseGPUShader(device, vertex_shader);
    const fragment_shader = try createShader(device, "ShadowDepth.frag", sdl_gpu.SDL_GPU_SHADERSTAGE_FRAGMENT, 0, 0);
    defer sdl_gpu.SDL_ReleaseGPUShader(device, fragment_shader);

    const target_info = sdl_gpu.SDL_GPUGraphicsPipelineTargetInfo{
        .color_target_descriptions = null,
        .num_color_targets = 0,
        .depth_stencil_format = sdl_gpu.SDL_GPU_TEXTUREFORMAT_D16_UNORM,
        .has_depth_stencil_target = true,
    };

    var vb_descs: [1]sdl_gpu.SDL_GPUVertexBufferDescription = undefined;
    var attrs: [3]sdl_gpu.SDL_GPUVertexAttribute = undefined;

    var pipeline_info = sdl_gpu.SDL_GPUGraphicsPipelineCreateInfo{
        .vertex_shader = vertex_shader,
        .fragment_shader = fragment_shader,
        .vertex_input_state = initMeshVertexInput(&vb_descs, &attrs),
        .primitive_type = sdl_gpu.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .rasterizer_state = .{
            .cull_mode = sdl_gpu.SDL_GPU_CULLMODE_BACK,
            .front_face = sdl_gpu.SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE,
        },
        .depth_stencil_state = .{
            .enable_depth_test = true,
            .enable_depth_write = true,
            .compare_op = sdl_gpu.SDL_GPU_COMPAREOP_LESS_OR_EQUAL,
        },
        .target_info = target_info,
    };

    return sdl_gpu.SDL_CreateGPUGraphicsPipeline(device, &pipeline_info) orelse error.PipelineCreateFailed;
}

pub fn createOverlayPipeline(
    device: *sdl_gpu.SDL_GPUDevice,
    swapchain_format: sdl_gpu.SDL_GPUTextureFormat,
) !*sdl_gpu.SDL_GPUGraphicsPipeline {
    return createOverlayPipelineWithFragment(device, swapchain_format, "OverlayQuad.frag");
}

pub fn createOverlayMaskPipeline(
    device: *sdl_gpu.SDL_GPUDevice,
    swapchain_format: sdl_gpu.SDL_GPUTextureFormat,
) !*sdl_gpu.SDL_GPUGraphicsPipeline {
    return createOverlayPipelineWithFragment(device, swapchain_format, "OverlayMaskQuad.frag");
}

pub fn createOverlaySdfPipeline(
    device: *sdl_gpu.SDL_GPUDevice,
    swapchain_format: sdl_gpu.SDL_GPUTextureFormat,
) !*sdl_gpu.SDL_GPUGraphicsPipeline {
    return createOverlayPipelineWithFragment(device, swapchain_format, "OverlaySdfQuad.frag");
}

fn createOverlayPipelineWithFragment(
    device: *sdl_gpu.SDL_GPUDevice,
    swapchain_format: sdl_gpu.SDL_GPUTextureFormat,
    comptime fragment_path: []const u8,
) !*sdl_gpu.SDL_GPUGraphicsPipeline {
    const vertex_shader = try createShader(device, "OverlayQuad.vert", sdl_gpu.SDL_GPU_SHADERSTAGE_VERTEX, 0, 1);
    defer sdl_gpu.SDL_ReleaseGPUShader(device, vertex_shader);
    const fragment_shader = try createShader(device, fragment_path, sdl_gpu.SDL_GPU_SHADERSTAGE_FRAGMENT, 1, 0);
    defer sdl_gpu.SDL_ReleaseGPUShader(device, fragment_shader);

    const blend = sdl_gpu.SDL_GPUColorTargetBlendState{
        .src_color_blendfactor = sdl_gpu.SDL_GPU_BLENDFACTOR_SRC_ALPHA,
        .dst_color_blendfactor = sdl_gpu.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
        .color_blend_op = sdl_gpu.SDL_GPU_BLENDOP_ADD,
        .src_alpha_blendfactor = sdl_gpu.SDL_GPU_BLENDFACTOR_ONE,
        .dst_alpha_blendfactor = sdl_gpu.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
        .alpha_blend_op = sdl_gpu.SDL_GPU_BLENDOP_ADD,
        .enable_blend = true,
    };
    var color_targets = [1]sdl_gpu.SDL_GPUColorTargetDescription{
        .{ .format = swapchain_format, .blend_state = blend },
    };
    const target_info = sdl_gpu.SDL_GPUGraphicsPipelineTargetInfo{
        .color_target_descriptions = @ptrCast(&color_targets),
        .num_color_targets = 1,
        .has_depth_stencil_target = false,
    };

    var vb_descs = [1]sdl_gpu.SDL_GPUVertexBufferDescription{
        .{
            .slot = 0,
            .pitch = @sizeOf(types.OverlayVertex),
            .input_rate = sdl_gpu.SDL_GPU_VERTEXINPUTRATE_VERTEX,
            .instance_step_rate = 0,
        },
    };
    var attrs = [3]sdl_gpu.SDL_GPUVertexAttribute{
        .{ .location = 0, .buffer_slot = 0, .format = sdl_gpu.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4, .offset = 0 },
        .{ .location = 1, .buffer_slot = 0, .format = sdl_gpu.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2, .offset = @offsetOf(types.OverlayVertex, "u") },
        .{ .location = 2, .buffer_slot = 0, .format = sdl_gpu.SDL_GPU_VERTEXELEMENTFORMAT_UBYTE4_NORM, .offset = @offsetOf(types.OverlayVertex, "r") },
    };
    const vertex_input = sdl_gpu.SDL_GPUVertexInputState{
        .vertex_buffer_descriptions = @ptrCast(&vb_descs),
        .num_vertex_buffers = 1,
        .vertex_attributes = @ptrCast(&attrs),
        .num_vertex_attributes = 3,
    };

    var pipeline_info = sdl_gpu.SDL_GPUGraphicsPipelineCreateInfo{
        .vertex_shader = vertex_shader,
        .fragment_shader = fragment_shader,
        .vertex_input_state = vertex_input,
        .primitive_type = sdl_gpu.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .rasterizer_state = .{
            .cull_mode = sdl_gpu.SDL_GPU_CULLMODE_NONE,
            .front_face = sdl_gpu.SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE,
        },
        .target_info = target_info,
    };

    return sdl_gpu.SDL_CreateGPUGraphicsPipeline(device, &pipeline_info) orelse error.PipelineCreateFailed;
}

pub fn createWireframePipeline(
    device: *sdl_gpu.SDL_GPUDevice,
    swapchain_format: sdl_gpu.SDL_GPUTextureFormat,
    sample_count: sdl_gpu.SDL_GPUSampleCount,
) !*sdl_gpu.SDL_GPUGraphicsPipeline {
    const vertex_shader = try createShader(device, "Wireframe.vert", sdl_gpu.SDL_GPU_SHADERSTAGE_VERTEX, 0, 1);
    defer sdl_gpu.SDL_ReleaseGPUShader(device, vertex_shader);
    const fragment_shader = try createShader(device, "SolidColor.frag", sdl_gpu.SDL_GPU_SHADERSTAGE_FRAGMENT, 0, 0);
    defer sdl_gpu.SDL_ReleaseGPUShader(device, fragment_shader);

    var color_targets = [1]sdl_gpu.SDL_GPUColorTargetDescription{
        .{ .format = swapchain_format },
    };
    const target_info = sdl_gpu.SDL_GPUGraphicsPipelineTargetInfo{
        .color_target_descriptions = @ptrCast(&color_targets),
        .num_color_targets = 1,
        .depth_stencil_format = sdl_gpu.SDL_GPU_TEXTUREFORMAT_D32_FLOAT,
        .has_depth_stencil_target = true,
    };

    var vb_descs = [1]sdl_gpu.SDL_GPUVertexBufferDescription{
        .{
            .slot = 0,
            .pitch = @sizeOf(types.SdlGpuVertex),
            .input_rate = sdl_gpu.SDL_GPU_VERTEXINPUTRATE_VERTEX,
            .instance_step_rate = 0,
        },
    };
    var attrs = [1]sdl_gpu.SDL_GPUVertexAttribute{
        .{ .location = 0, .buffer_slot = 0, .format = sdl_gpu.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4, .offset = 0 },
    };
    const vertex_input = sdl_gpu.SDL_GPUVertexInputState{
        .vertex_buffer_descriptions = @ptrCast(&vb_descs),
        .num_vertex_buffers = 1,
        .vertex_attributes = @ptrCast(&attrs),
        .num_vertex_attributes = 1,
    };

    var pipeline_info = sdl_gpu.SDL_GPUGraphicsPipelineCreateInfo{
        .vertex_shader = vertex_shader,
        .fragment_shader = fragment_shader,
        .vertex_input_state = vertex_input,
        .primitive_type = sdl_gpu.SDL_GPU_PRIMITIVETYPE_LINELIST,
        .depth_stencil_state = .{
            .enable_depth_test = false,
            .enable_depth_write = false,
            .compare_op = sdl_gpu.SDL_GPU_COMPAREOP_LESS,
        },
        .multisample_state = .{ .sample_count = sample_count },
        .target_info = target_info,
    };

    return sdl_gpu.SDL_CreateGPUGraphicsPipeline(device, &pipeline_info) orelse error.PipelineCreateFailed;
}

pub fn createGridPipeline(
    device: *sdl_gpu.SDL_GPUDevice,
    swapchain_format: sdl_gpu.SDL_GPUTextureFormat,
    sample_count: sdl_gpu.SDL_GPUSampleCount,
) !*sdl_gpu.SDL_GPUGraphicsPipeline {
    const vertex_shader = try createShader(device, "PositionColorTransform.vert", sdl_gpu.SDL_GPU_SHADERSTAGE_VERTEX, 0, 1);
    defer sdl_gpu.SDL_ReleaseGPUShader(device, vertex_shader);
    const fragment_shader = try createShader(device, "SolidColor.frag", sdl_gpu.SDL_GPU_SHADERSTAGE_FRAGMENT, 0, 0);
    defer sdl_gpu.SDL_ReleaseGPUShader(device, fragment_shader);

    var color_targets = [1]sdl_gpu.SDL_GPUColorTargetDescription{
        .{ .format = swapchain_format },
    };
    const target_info = sdl_gpu.SDL_GPUGraphicsPipelineTargetInfo{
        .color_target_descriptions = @ptrCast(&color_targets),
        .num_color_targets = 1,
        .depth_stencil_format = sdl_gpu.SDL_GPU_TEXTUREFORMAT_D32_FLOAT,
        .has_depth_stencil_target = true,
    };

    var vb_descs = [1]sdl_gpu.SDL_GPUVertexBufferDescription{
        .{
            .slot = 0,
            .pitch = @sizeOf(types.GridColorVertex),
            .input_rate = sdl_gpu.SDL_GPU_VERTEXINPUTRATE_VERTEX,
            .instance_step_rate = 0,
        },
    };
    var attrs = [2]sdl_gpu.SDL_GPUVertexAttribute{
        .{ .location = 0, .buffer_slot = 0, .format = sdl_gpu.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3, .offset = 0 },
        .{ .location = 1, .buffer_slot = 0, .format = sdl_gpu.SDL_GPU_VERTEXELEMENTFORMAT_UBYTE4_NORM, .offset = @offsetOf(types.GridColorVertex, "r") },
    };
    const vertex_input = sdl_gpu.SDL_GPUVertexInputState{
        .vertex_buffer_descriptions = @ptrCast(&vb_descs),
        .num_vertex_buffers = 1,
        .vertex_attributes = @ptrCast(&attrs),
        .num_vertex_attributes = 2,
    };

    var pipeline_info = sdl_gpu.SDL_GPUGraphicsPipelineCreateInfo{
        .vertex_shader = vertex_shader,
        .fragment_shader = fragment_shader,
        .vertex_input_state = vertex_input,
        .primitive_type = sdl_gpu.SDL_GPU_PRIMITIVETYPE_LINELIST,
        .depth_stencil_state = .{
            .enable_depth_test = true,
            .enable_depth_write = true,
            .compare_op = sdl_gpu.SDL_GPU_COMPAREOP_LESS,
        },
        .multisample_state = .{ .sample_count = sample_count },
        .target_info = target_info,
    };

    return sdl_gpu.SDL_CreateGPUGraphicsPipeline(device, &pipeline_info) orelse error.PipelineCreateFailed;
}

pub fn createSkyPipeline(
    device: *sdl_gpu.SDL_GPUDevice,
    swapchain_format: sdl_gpu.SDL_GPUTextureFormat,
    sample_count: sdl_gpu.SDL_GPUSampleCount,
) !*sdl_gpu.SDL_GPUGraphicsPipeline {
    const vertex_shader = try createShader(device, "Sky.vert", sdl_gpu.SDL_GPU_SHADERSTAGE_VERTEX, 0, 0);
    defer sdl_gpu.SDL_ReleaseGPUShader(device, vertex_shader);
    const fragment_shader = try createShader(device, "Sky.frag", sdl_gpu.SDL_GPU_SHADERSTAGE_FRAGMENT, 0, 1);
    defer sdl_gpu.SDL_ReleaseGPUShader(device, fragment_shader);

    var color_targets = [1]sdl_gpu.SDL_GPUColorTargetDescription{
        .{ .format = swapchain_format },
    };
    const target_info = sdl_gpu.SDL_GPUGraphicsPipelineTargetInfo{
        .color_target_descriptions = @ptrCast(&color_targets),
        .num_color_targets = 1,
        .depth_stencil_format = sdl_gpu.SDL_GPU_TEXTUREFORMAT_D32_FLOAT,
        .has_depth_stencil_target = true,
    };

    // Fullscreen triangle: no vertex buffers, the vertex shader derives
    // positions purely from @builtin(vertex_index).
    const vertex_input = sdl_gpu.SDL_GPUVertexInputState{};

    var pipeline_info = sdl_gpu.SDL_GPUGraphicsPipelineCreateInfo{
        .vertex_shader = vertex_shader,
        .fragment_shader = fragment_shader,
        .vertex_input_state = vertex_input,
        .primitive_type = sdl_gpu.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .rasterizer_state = .{
            .cull_mode = sdl_gpu.SDL_GPU_CULLMODE_NONE,
            .front_face = sdl_gpu.SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE,
        },
        .depth_stencil_state = .{
            .enable_depth_test = false,
            .enable_depth_write = false,
            .compare_op = sdl_gpu.SDL_GPU_COMPAREOP_LESS,
        },
        .multisample_state = .{ .sample_count = sample_count },
        .target_info = target_info,
    };

    return sdl_gpu.SDL_CreateGPUGraphicsPipeline(device, &pipeline_info) orelse error.PipelineCreateFailed;
}

pub fn createDepthPrepassPipeline(device: *sdl_gpu.SDL_GPUDevice) !*sdl_gpu.SDL_GPUGraphicsPipeline {
    const vertex_shader = try createShader(device, "TexturedQuadWithMatrix.vert", sdl_gpu.SDL_GPU_SHADERSTAGE_VERTEX, 0, 1);
    defer sdl_gpu.SDL_ReleaseGPUShader(device, vertex_shader);
    const fragment_shader = try createShader(device, "ShadowDepth.frag", sdl_gpu.SDL_GPU_SHADERSTAGE_FRAGMENT, 0, 0);
    defer sdl_gpu.SDL_ReleaseGPUShader(device, fragment_shader);

    var vb_descs: [1]sdl_gpu.SDL_GPUVertexBufferDescription = undefined;
    var attrs: [3]sdl_gpu.SDL_GPUVertexAttribute = undefined;
    const target_info = sdl_gpu.SDL_GPUGraphicsPipelineTargetInfo{
        .color_target_descriptions = null,
        .num_color_targets = 0,
        .depth_stencil_format = sdl_gpu.SDL_GPU_TEXTUREFORMAT_D32_FLOAT,
        .has_depth_stencil_target = true,
    };

    var pipeline_info = sdl_gpu.SDL_GPUGraphicsPipelineCreateInfo{
        .vertex_shader = vertex_shader,
        .fragment_shader = fragment_shader,
        .vertex_input_state = initMeshVertexInput(&vb_descs, &attrs),
        .primitive_type = sdl_gpu.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .rasterizer_state = .{
            .cull_mode = sdl_gpu.SDL_GPU_CULLMODE_NONE,
            .front_face = sdl_gpu.SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE,
        },
        .depth_stencil_state = .{
            .enable_depth_test = true,
            .enable_depth_write = true,
            .compare_op = sdl_gpu.SDL_GPU_COMPAREOP_LESS,
        },
        .target_info = target_info,
    };

    return sdl_gpu.SDL_CreateGPUGraphicsPipeline(device, &pipeline_info) orelse error.PipelineCreateFailed;
}

pub fn createInstancedDepthPrepassPipeline(device: *sdl_gpu.SDL_GPUDevice) !*sdl_gpu.SDL_GPUGraphicsPipeline {
    const vertex_shader = try createShader(device, "TexturedQuadInstanced.vert", sdl_gpu.SDL_GPU_SHADERSTAGE_VERTEX, 0, 1);
    defer sdl_gpu.SDL_ReleaseGPUShader(device, vertex_shader);
    const fragment_shader = try createShader(device, "ShadowDepth.frag", sdl_gpu.SDL_GPU_SHADERSTAGE_FRAGMENT, 0, 0);
    defer sdl_gpu.SDL_ReleaseGPUShader(device, fragment_shader);

    var vb_descs: [2]sdl_gpu.SDL_GPUVertexBufferDescription = undefined;
    var attrs: [7]sdl_gpu.SDL_GPUVertexAttribute = undefined;
    const target_info = sdl_gpu.SDL_GPUGraphicsPipelineTargetInfo{
        .color_target_descriptions = null,
        .num_color_targets = 0,
        .depth_stencil_format = sdl_gpu.SDL_GPU_TEXTUREFORMAT_D32_FLOAT,
        .has_depth_stencil_target = true,
    };

    var pipeline_info = sdl_gpu.SDL_GPUGraphicsPipelineCreateInfo{
        .vertex_shader = vertex_shader,
        .fragment_shader = fragment_shader,
        .vertex_input_state = initInstancedMeshVertexInput(&vb_descs, &attrs),
        .primitive_type = sdl_gpu.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .rasterizer_state = .{
            .cull_mode = sdl_gpu.SDL_GPU_CULLMODE_BACK,
            .front_face = sdl_gpu.SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE,
        },
        .depth_stencil_state = .{
            .enable_depth_test = true,
            .enable_depth_write = true,
            .compare_op = sdl_gpu.SDL_GPU_COMPAREOP_LESS,
        },
        .target_info = target_info,
    };

    return sdl_gpu.SDL_CreateGPUGraphicsPipeline(device, &pipeline_info) orelse error.PipelineCreateFailed;
}

pub fn createTonemapPipeline(
    device: *sdl_gpu.SDL_GPUDevice,
    output_format: sdl_gpu.SDL_GPUTextureFormat,
) !*sdl_gpu.SDL_GPUGraphicsPipeline {
    return createFullscreenPipeline(device, output_format, "Tonemap.frag", 1, 1);
}

pub fn createLuminancePipeline(device: *sdl_gpu.SDL_GPUDevice) !*sdl_gpu.SDL_GPUGraphicsPipeline {
    return createFullscreenPipeline(device, sdl_gpu.SDL_GPU_TEXTUREFORMAT_R32_FLOAT, "LuminanceDownsample.frag", 1, 0);
}

fn createFullscreenPipeline(
    device: *sdl_gpu.SDL_GPUDevice,
    output_format: sdl_gpu.SDL_GPUTextureFormat,
    comptime fragment_path: []const u8,
    num_samplers: u32,
    num_uniform_buffers: u32,
) !*sdl_gpu.SDL_GPUGraphicsPipeline {
    const vertex_shader = try createShader(device, "Sky.vert", sdl_gpu.SDL_GPU_SHADERSTAGE_VERTEX, 0, 0);
    defer sdl_gpu.SDL_ReleaseGPUShader(device, vertex_shader);
    const fragment_shader = try createShader(device, fragment_path, sdl_gpu.SDL_GPU_SHADERSTAGE_FRAGMENT, num_samplers, num_uniform_buffers);
    defer sdl_gpu.SDL_ReleaseGPUShader(device, fragment_shader);

    var color_targets = [1]sdl_gpu.SDL_GPUColorTargetDescription{.{ .format = output_format }};
    const target_info = sdl_gpu.SDL_GPUGraphicsPipelineTargetInfo{
        .color_target_descriptions = @ptrCast(&color_targets),
        .num_color_targets = 1,
        .has_depth_stencil_target = false,
    };

    var pipeline_info = sdl_gpu.SDL_GPUGraphicsPipelineCreateInfo{
        .vertex_shader = vertex_shader,
        .fragment_shader = fragment_shader,
        .vertex_input_state = .{},
        .primitive_type = sdl_gpu.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .rasterizer_state = .{
            .cull_mode = sdl_gpu.SDL_GPU_CULLMODE_NONE,
            .front_face = sdl_gpu.SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE,
        },
        .depth_stencil_state = .{
            .enable_depth_test = false,
            .enable_depth_write = false,
            .compare_op = sdl_gpu.SDL_GPU_COMPAREOP_LESS,
        },
        .target_info = target_info,
    };

    return sdl_gpu.SDL_CreateGPUGraphicsPipeline(device, &pipeline_info) orelse error.PipelineCreateFailed;
}

test "sdl gpu vertex layout size" {
    try std.testing.expectEqual(@as(usize, 36), @sizeOf(types.SdlGpuVertex));
    try std.testing.expectEqual(@as(usize, 28), @sizeOf(types.OverlayVertex));
}
