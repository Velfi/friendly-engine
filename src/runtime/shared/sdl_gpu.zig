const builtin = @import("builtin");
const types = @import("sdl_gpu_types.zig");

pub const SDL_GPUDevice = types.SDL_GPUDevice;
pub const SDL_GPUBuffer = types.SDL_GPUBuffer;
pub const SDL_GPUTransferBuffer = types.SDL_GPUTransferBuffer;
pub const SDL_GPUTexture = types.SDL_GPUTexture;
pub const SDL_GPUSampler = types.SDL_GPUSampler;
pub const SDL_GPUShader = types.SDL_GPUShader;
pub const SDL_GPUGraphicsPipeline = types.SDL_GPUGraphicsPipeline;
pub const SDL_GPUCommandBuffer = types.SDL_GPUCommandBuffer;
pub const SDL_GPURenderPass = types.SDL_GPURenderPass;
pub const SDL_GPUCopyPass = types.SDL_GPUCopyPass;
pub const SDL_GPUFence = types.SDL_GPUFence;
pub const SDL_Window = types.SDL_Window;
pub const SDL_FColor = types.SDL_FColor;
pub const SDL_GPUPresentMode = types.SDL_GPUPresentMode;
pub const SDL_GPU_PRESENTMODE_VSYNC = types.SDL_GPU_PRESENTMODE_VSYNC;
pub const SDL_GPU_PRESENTMODE_IMMEDIATE = types.SDL_GPU_PRESENTMODE_IMMEDIATE;
pub const SDL_GPU_PRESENTMODE_MAILBOX = types.SDL_GPU_PRESENTMODE_MAILBOX;
pub const SDL_GPUSwapchainComposition = types.SDL_GPUSwapchainComposition;
pub const SDL_GPU_SWAPCHAINCOMPOSITION_SDR = types.SDL_GPU_SWAPCHAINCOMPOSITION_SDR;
pub const SDL_GPUShaderFormat = types.SDL_GPUShaderFormat;
pub const SDL_GPU_SHADERFORMAT_INVALID = types.SDL_GPU_SHADERFORMAT_INVALID;
pub const SDL_GPU_SHADERFORMAT_SPIRV = types.SDL_GPU_SHADERFORMAT_SPIRV;
pub const SDL_GPU_SHADERFORMAT_DXIL = types.SDL_GPU_SHADERFORMAT_DXIL;
pub const SDL_GPU_SHADERFORMAT_MSL = types.SDL_GPU_SHADERFORMAT_MSL;
pub const SDL_GPUShaderStage = types.SDL_GPUShaderStage;
pub const SDL_GPU_SHADERSTAGE_VERTEX = types.SDL_GPU_SHADERSTAGE_VERTEX;
pub const SDL_GPU_SHADERSTAGE_FRAGMENT = types.SDL_GPU_SHADERSTAGE_FRAGMENT;
pub const SDL_GPUPrimitiveType = types.SDL_GPUPrimitiveType;
pub const SDL_GPU_PRIMITIVETYPE_TRIANGLELIST = types.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST;
pub const SDL_GPU_PRIMITIVETYPE_LINELIST = types.SDL_GPU_PRIMITIVETYPE_LINELIST;
pub const SDL_GPULoadOp = types.SDL_GPULoadOp;
pub const SDL_GPU_LOADOP_LOAD = types.SDL_GPU_LOADOP_LOAD;
pub const SDL_GPU_LOADOP_CLEAR = types.SDL_GPU_LOADOP_CLEAR;
pub const SDL_GPU_LOADOP_DONT_CARE = types.SDL_GPU_LOADOP_DONT_CARE;
pub const SDL_GPUStoreOp = types.SDL_GPUStoreOp;
pub const SDL_GPU_STOREOP_STORE = types.SDL_GPU_STOREOP_STORE;
pub const SDL_GPU_STOREOP_DONT_CARE = types.SDL_GPU_STOREOP_DONT_CARE;
pub const SDL_GPU_STOREOP_RESOLVE = types.SDL_GPU_STOREOP_RESOLVE;
pub const SDL_GPU_STOREOP_RESOLVE_AND_STORE = types.SDL_GPU_STOREOP_RESOLVE_AND_STORE;
pub const SDL_GPUIndexElementSize = types.SDL_GPUIndexElementSize;
pub const SDL_GPU_INDEXELEMENTSIZE_32BIT = types.SDL_GPU_INDEXELEMENTSIZE_32BIT;
pub const SDL_GPUVertexInputRate = types.SDL_GPUVertexInputRate;
pub const SDL_GPU_VERTEXINPUTRATE_VERTEX = types.SDL_GPU_VERTEXINPUTRATE_VERTEX;
pub const SDL_GPU_VERTEXINPUTRATE_INSTANCE = types.SDL_GPU_VERTEXINPUTRATE_INSTANCE;
pub const SDL_GPUVertexElementFormat = types.SDL_GPUVertexElementFormat;
pub const SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2 = types.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2;
pub const SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3 = types.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3;
pub const SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4 = types.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4;
pub const SDL_GPU_VERTEXELEMENTFORMAT_UBYTE4_NORM = types.SDL_GPU_VERTEXELEMENTFORMAT_UBYTE4_NORM;
pub const SDL_GPUCullMode = types.SDL_GPUCullMode;
pub const SDL_GPU_CULLMODE_NONE = types.SDL_GPU_CULLMODE_NONE;
pub const SDL_GPU_CULLMODE_BACK = types.SDL_GPU_CULLMODE_BACK;
pub const SDL_GPUFrontFace = types.SDL_GPUFrontFace;
pub const SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE = types.SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE;
pub const SDL_GPUCompareOp = types.SDL_GPUCompareOp;
pub const SDL_GPU_COMPAREOP_LESS = types.SDL_GPU_COMPAREOP_LESS;
pub const SDL_GPU_COMPAREOP_LESS_OR_EQUAL = types.SDL_GPU_COMPAREOP_LESS_OR_EQUAL;
pub const SDL_GPUFillMode = types.SDL_GPUFillMode;
pub const SDL_GPUTextureType = types.SDL_GPUTextureType;
pub const SDL_GPU_TEXTURETYPE_2D = types.SDL_GPU_TEXTURETYPE_2D;
pub const SDL_GPUTextureFormat = types.SDL_GPUTextureFormat;
pub const SDL_GPU_TEXTUREFORMAT_INVALID = types.SDL_GPU_TEXTUREFORMAT_INVALID;
pub const SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM = types.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM;
pub const SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM = types.SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM;
pub const SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM_SRGB = types.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM_SRGB;
pub const SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM_SRGB = types.SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM_SRGB;
pub const SDL_GPU_TEXTUREFORMAT_R16G16B16A16_FLOAT = types.SDL_GPU_TEXTUREFORMAT_R16G16B16A16_FLOAT;
pub const SDL_GPU_TEXTUREFORMAT_R32_FLOAT = types.SDL_GPU_TEXTUREFORMAT_R32_FLOAT;
pub const SDL_GPU_TEXTUREFORMAT_D16_UNORM = types.SDL_GPU_TEXTUREFORMAT_D16_UNORM;
pub const SDL_GPU_TEXTUREFORMAT_D32_FLOAT = types.SDL_GPU_TEXTUREFORMAT_D32_FLOAT;
pub const SDL_GPUTextureUsageFlags = types.SDL_GPUTextureUsageFlags;
pub const SDL_GPU_TEXTUREUSAGE_SAMPLER = types.SDL_GPU_TEXTUREUSAGE_SAMPLER;
pub const SDL_GPU_TEXTUREUSAGE_COLOR_TARGET = types.SDL_GPU_TEXTUREUSAGE_COLOR_TARGET;
pub const SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET = types.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET;
pub const SDL_GPUBufferUsageFlags = types.SDL_GPUBufferUsageFlags;
pub const SDL_GPU_BUFFERUSAGE_VERTEX = types.SDL_GPU_BUFFERUSAGE_VERTEX;
pub const SDL_GPU_BUFFERUSAGE_INDEX = types.SDL_GPU_BUFFERUSAGE_INDEX;
pub const SDL_GPUTransferBufferUsage = types.SDL_GPUTransferBufferUsage;
pub const SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD = types.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD;
pub const SDL_GPU_TRANSFERBUFFERUSAGE_DOWNLOAD = types.SDL_GPU_TRANSFERBUFFERUSAGE_DOWNLOAD;
pub const SDL_GPUFilter = types.SDL_GPUFilter;
pub const SDL_GPU_FILTER_NEAREST = types.SDL_GPU_FILTER_NEAREST;
pub const SDL_GPU_FILTER_LINEAR = types.SDL_GPU_FILTER_LINEAR;
pub const SDL_GPUSamplerMipmapMode = types.SDL_GPUSamplerMipmapMode;
pub const SDL_GPU_SAMPLERMIPMAPMODE_NEAREST = types.SDL_GPU_SAMPLERMIPMAPMODE_NEAREST;
pub const SDL_GPUSamplerAddressMode = types.SDL_GPUSamplerAddressMode;
pub const SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE = types.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE;
pub const SDL_GPU_SAMPLERADDRESSMODE_REPEAT = types.SDL_GPU_SAMPLERADDRESSMODE_REPEAT;
pub const SDL_GPUSampleCount = types.SDL_GPUSampleCount;
pub const SDL_GPU_SAMPLECOUNT_1 = types.SDL_GPU_SAMPLECOUNT_1;
pub const SDL_GPU_SAMPLECOUNT_2 = types.SDL_GPU_SAMPLECOUNT_2;
pub const SDL_GPU_SAMPLECOUNT_4 = types.SDL_GPU_SAMPLECOUNT_4;
pub const SDL_GPU_SAMPLECOUNT_8 = types.SDL_GPU_SAMPLECOUNT_8;
pub const SDL_GPUColorComponentFlags = types.SDL_GPUColorComponentFlags;
pub const SDL_GPU_COLORCOMPONENT_R = types.SDL_GPU_COLORCOMPONENT_R;
pub const SDL_GPU_COLORCOMPONENT_G = types.SDL_GPU_COLORCOMPONENT_G;
pub const SDL_GPU_COLORCOMPONENT_B = types.SDL_GPU_COLORCOMPONENT_B;
pub const SDL_GPU_COLORCOMPONENT_A = types.SDL_GPU_COLORCOMPONENT_A;
pub const SDL_GPU_BLENDFACTOR_ZERO = types.SDL_GPU_BLENDFACTOR_ZERO;
pub const SDL_GPU_BLENDFACTOR_ONE = types.SDL_GPU_BLENDFACTOR_ONE;
pub const SDL_GPU_BLENDFACTOR_SRC_ALPHA = types.SDL_GPU_BLENDFACTOR_SRC_ALPHA;
pub const SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA = types.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA;
pub const SDL_GPU_BLENDOP_ADD = types.SDL_GPU_BLENDOP_ADD;
pub const SDL_GPUShaderCreateInfo = types.SDL_GPUShaderCreateInfo;
pub const SDL_GPUBufferCreateInfo = types.SDL_GPUBufferCreateInfo;
pub const SDL_GPUTransferBufferCreateInfo = types.SDL_GPUTransferBufferCreateInfo;
pub const SDL_GPUTextureCreateInfo = types.SDL_GPUTextureCreateInfo;
pub const SDL_GPUSamplerCreateInfo = types.SDL_GPUSamplerCreateInfo;
pub const SDL_GPUVertexBufferDescription = types.SDL_GPUVertexBufferDescription;
pub const SDL_GPUVertexAttribute = types.SDL_GPUVertexAttribute;
pub const SDL_GPUVertexInputState = types.SDL_GPUVertexInputState;
pub const SDL_GPUStencilOpState = types.SDL_GPUStencilOpState;
pub const SDL_GPUDepthStencilState = types.SDL_GPUDepthStencilState;
pub const SDL_GPURasterizerState = types.SDL_GPURasterizerState;
pub const SDL_GPUMultisampleState = types.SDL_GPUMultisampleState;
pub const SDL_GPUColorTargetBlendState = types.SDL_GPUColorTargetBlendState;
pub const SDL_GPUColorTargetDescription = types.SDL_GPUColorTargetDescription;
pub const SDL_GPUGraphicsPipelineTargetInfo = types.SDL_GPUGraphicsPipelineTargetInfo;
pub const SDL_GPUGraphicsPipelineCreateInfo = types.SDL_GPUGraphicsPipelineCreateInfo;
pub const SDL_GPUColorTargetInfo = types.SDL_GPUColorTargetInfo;
pub const SDL_GPUDepthStencilTargetInfo = types.SDL_GPUDepthStencilTargetInfo;
pub const SDL_GPUBufferBinding = types.SDL_GPUBufferBinding;
pub const SDL_GPUTextureSamplerBinding = types.SDL_GPUTextureSamplerBinding;
pub const SDL_GPUTransferBufferLocation = types.SDL_GPUTransferBufferLocation;
pub const SDL_GPUBufferRegion = types.SDL_GPUBufferRegion;
pub const SDL_GPUTextureTransferInfo = types.SDL_GPUTextureTransferInfo;
pub const SDL_GPUTextureRegion = types.SDL_GPUTextureRegion;
pub const SDL_GPUViewport = types.SDL_GPUViewport;

pub extern fn SDL_CreateGPUDevice(
    format_flags: SDL_GPUShaderFormat,
    debug_mode: bool,
    name: ?[*:0]const u8,
) ?*SDL_GPUDevice;
pub extern fn SDL_DestroyGPUDevice(device: *SDL_GPUDevice) void;
pub extern fn SDL_GetGPUShaderFormats(device: *SDL_GPUDevice) SDL_GPUShaderFormat;
pub extern fn SDL_GetGPUSwapchainTextureFormat(device: *SDL_GPUDevice, window: *SDL_Window) SDL_GPUTextureFormat;
pub extern fn SDL_ClaimWindowForGPUDevice(device: *SDL_GPUDevice, window: *SDL_Window) bool;
pub extern fn SDL_ReleaseWindowFromGPUDevice(device: *SDL_GPUDevice, window: *SDL_Window) void;
pub extern fn SDL_WindowSupportsGPUPresentMode(device: *SDL_GPUDevice, window: *SDL_Window, present_mode: SDL_GPUPresentMode) bool;
pub extern fn SDL_SetGPUSwapchainParameters(
    device: *SDL_GPUDevice,
    window: *SDL_Window,
    swapchain_composition: SDL_GPUSwapchainComposition,
    present_mode: SDL_GPUPresentMode,
) bool;
pub extern fn SDL_WaitForGPUSwapchain(device: *SDL_GPUDevice, window: *SDL_Window) bool;
pub extern fn SDL_AcquireGPUSwapchainTexture(
    device: *SDL_GPUDevice,
    window: *SDL_Window,
    swapchain_texture: *?*SDL_GPUTexture,
    swapchain_texture_width: *c_uint,
    swapchain_texture_height: *c_uint,
) bool;
pub extern fn SDL_CreateGPUShader(device: *SDL_GPUDevice, create_info: *const SDL_GPUShaderCreateInfo) ?*SDL_GPUShader;
pub extern fn SDL_ReleaseGPUShader(device: *SDL_GPUDevice, shader: *SDL_GPUShader) void;
pub extern fn SDL_CreateGPUGraphicsPipeline(
    device: *SDL_GPUDevice,
    create_info: *const SDL_GPUGraphicsPipelineCreateInfo,
) ?*SDL_GPUGraphicsPipeline;
pub extern fn SDL_ReleaseGPUGraphicsPipeline(device: *SDL_GPUDevice, pipeline: *SDL_GPUGraphicsPipeline) void;
pub extern fn SDL_CreateGPUBuffer(device: *SDL_GPUDevice, create_info: *const SDL_GPUBufferCreateInfo) ?*SDL_GPUBuffer;
pub extern fn SDL_ReleaseGPUBuffer(device: *SDL_GPUDevice, buffer: *SDL_GPUBuffer) void;
pub extern fn SDL_CreateGPUTransferBuffer(
    device: *SDL_GPUDevice,
    create_info: *const SDL_GPUTransferBufferCreateInfo,
) ?*SDL_GPUTransferBuffer;
pub extern fn SDL_ReleaseGPUTransferBuffer(device: *SDL_GPUDevice, transfer_buffer: *SDL_GPUTransferBuffer) void;
pub extern fn SDL_MapGPUTransferBuffer(
    device: *SDL_GPUDevice,
    transfer_buffer: *SDL_GPUTransferBuffer,
    cycle: bool,
) ?*anyopaque;
pub extern fn SDL_UnmapGPUTransferBuffer(device: *SDL_GPUDevice, transfer_buffer: *SDL_GPUTransferBuffer) void;
pub extern fn SDL_CreateGPUTexture(device: *SDL_GPUDevice, create_info: *const SDL_GPUTextureCreateInfo) ?*SDL_GPUTexture;
pub extern fn SDL_ReleaseGPUTexture(device: *SDL_GPUDevice, texture: *SDL_GPUTexture) void;
pub extern fn SDL_GPUTextureSupportsSampleCount(
    device: *SDL_GPUDevice,
    format: SDL_GPUTextureFormat,
    sample_count: SDL_GPUSampleCount,
) bool;
pub extern fn SDL_CreateGPUSampler(device: *SDL_GPUDevice, create_info: *const SDL_GPUSamplerCreateInfo) ?*SDL_GPUSampler;
pub extern fn SDL_ReleaseGPUSampler(device: *SDL_GPUDevice, sampler: *SDL_GPUSampler) void;
pub extern fn SDL_AcquireGPUCommandBuffer(device: *SDL_GPUDevice) ?*SDL_GPUCommandBuffer;
pub extern fn SDL_InsertGPUDebugLabel(command_buffer: *SDL_GPUCommandBuffer, text: [*:0]const u8) void;
pub extern fn SDL_PushGPUDebugGroup(command_buffer: *SDL_GPUCommandBuffer, name: [*:0]const u8) void;
pub extern fn SDL_PopGPUDebugGroup(command_buffer: *SDL_GPUCommandBuffer) void;
pub extern fn SDL_SubmitGPUCommandBuffer(command_buffer: *SDL_GPUCommandBuffer) bool;
pub extern fn SDL_SubmitGPUCommandBufferAndAcquireFence(command_buffer: *SDL_GPUCommandBuffer) ?*SDL_GPUFence;
pub extern fn SDL_WaitForGPUFences(device: *SDL_GPUDevice, wait_all: bool, fences: ?[*]?*SDL_GPUFence, num_fences: c_uint) bool;
pub extern fn SDL_QueryGPUFence(device: *SDL_GPUDevice, fence: *SDL_GPUFence) bool;
pub extern fn SDL_ReleaseGPUFence(device: *SDL_GPUDevice, fence: *SDL_GPUFence) void;
pub extern fn SDL_WaitAndAcquireGPUSwapchainTexture(
    command_buffer: *SDL_GPUCommandBuffer,
    window: *SDL_Window,
    swapchain_texture: *?*SDL_GPUTexture,
    swapchain_texture_width: ?*c_uint,
    swapchain_texture_height: ?*c_uint,
) bool;
pub extern fn SDL_BeginGPURenderPass(
    command_buffer: *SDL_GPUCommandBuffer,
    color_target_infos: ?[*]const SDL_GPUColorTargetInfo,
    num_color_targets: c_uint,
    depth_stencil_target_info: ?*const SDL_GPUDepthStencilTargetInfo,
) ?*SDL_GPURenderPass;
pub extern fn SDL_EndGPURenderPass(render_pass: *SDL_GPURenderPass) void;
pub extern fn SDL_BindGPUGraphicsPipeline(render_pass: *SDL_GPURenderPass, graphics_pipeline: *SDL_GPUGraphicsPipeline) void;
pub extern fn SDL_BindGPUVertexBuffers(
    render_pass: *SDL_GPURenderPass,
    first_slot: c_uint,
    bindings: ?[*]const SDL_GPUBufferBinding,
    num_bindings: c_uint,
) void;
pub extern fn SDL_BindGPUIndexBuffer(
    render_pass: *SDL_GPURenderPass,
    binding: ?*const SDL_GPUBufferBinding,
    index_element_size: SDL_GPUIndexElementSize,
) void;
pub extern fn SDL_BindGPUFragmentSamplers(
    render_pass: *SDL_GPURenderPass,
    first_slot: c_uint,
    texture_sampler_bindings: ?[*]const SDL_GPUTextureSamplerBinding,
    num_bindings: c_uint,
) void;
pub extern fn SDL_SetGPUViewport(render_pass: *SDL_GPURenderPass, viewport: ?*const SDL_GPUViewport) void;
pub extern fn SDL_PushGPUVertexUniformData(
    command_buffer: *SDL_GPUCommandBuffer,
    slot_index: c_uint,
    data: ?*const anyopaque,
    length: c_uint,
) void;
pub extern fn SDL_PushGPUFragmentUniformData(
    command_buffer: *SDL_GPUCommandBuffer,
    slot_index: c_uint,
    data: ?*const anyopaque,
    length: c_uint,
) void;
pub extern fn SDL_DrawGPUIndexedPrimitives(
    render_pass: *SDL_GPURenderPass,
    num_indices: c_uint,
    num_instances: c_uint,
    first_index: c_uint,
    vertex_offset: c_int,
    first_instance: c_uint,
) void;
pub extern fn SDL_BeginGPUCopyPass(command_buffer: *SDL_GPUCommandBuffer) ?*SDL_GPUCopyPass;
pub extern fn SDL_UploadToGPUBuffer(
    copy_pass: *SDL_GPUCopyPass,
    source: *const SDL_GPUTransferBufferLocation,
    destination: *const SDL_GPUBufferRegion,
    cycle: bool,
) void;
pub extern fn SDL_UploadToGPUTexture(
    copy_pass: *SDL_GPUCopyPass,
    source: *const SDL_GPUTextureTransferInfo,
    destination: *const SDL_GPUTextureRegion,
    cycle: bool,
) void;
pub extern fn SDL_DownloadFromGPUTexture(
    copy_pass: *SDL_GPUCopyPass,
    source: *const SDL_GPUTextureRegion,
    destination: *const SDL_GPUTextureTransferInfo,
) void;
pub extern fn SDL_EndGPUCopyPass(copy_pass: *SDL_GPUCopyPass) void;
pub extern fn SDL_DrawGPUPrimitives(
    render_pass: *SDL_GPURenderPass,
    num_vertices: c_uint,
    num_instances: c_uint,
    first_vertex: c_uint,
    first_instance: c_uint,
) void;

pub fn preferredShaderFormats() SDL_GPUShaderFormat {
    return SDL_GPU_SHADERFORMAT_SPIRV | SDL_GPU_SHADERFORMAT_DXIL | SDL_GPU_SHADERFORMAT_MSL;
}

pub fn shaderEntrypoint(format: SDL_GPUShaderFormat) [*:0]const u8 {
    if (format & SDL_GPU_SHADERFORMAT_MSL != 0) return "main_";
    return "main";
}

pub fn activeShaderFormat(device: *SDL_GPUDevice) SDL_GPUShaderFormat {
    const formats = SDL_GetGPUShaderFormats(device);
    if (formats & SDL_GPU_SHADERFORMAT_MSL != 0) return SDL_GPU_SHADERFORMAT_MSL;
    if (formats & SDL_GPU_SHADERFORMAT_SPIRV != 0) return SDL_GPU_SHADERFORMAT_SPIRV;
    if (formats & SDL_GPU_SHADERFORMAT_DXIL != 0) return SDL_GPU_SHADERFORMAT_DXIL;
    return SDL_GPU_SHADERFORMAT_INVALID;
}

pub fn backendName(format: SDL_GPUShaderFormat) []const u8 {
    if (format & SDL_GPU_SHADERFORMAT_MSL != 0) return "Metal";
    if (format & SDL_GPU_SHADERFORMAT_SPIRV != 0) return "Vulkan";
    if (format & SDL_GPU_SHADERFORMAT_DXIL != 0) return "D3D12";
    return "unknown";
}

pub const ShaderBytes = struct {
    code: []const u8 align(1),
    format: SDL_GPUShaderFormat,
    entrypoint: [*:0]const u8,
};

pub fn shaderBytes(comptime path: []const u8) ShaderBytes {
    if (comptime builtin.os.tag == .macos) {
        return .{
            .code = @embedFile("shaders/metal/" ++ path ++ ".metal"),
            .format = SDL_GPU_SHADERFORMAT_MSL,
            .entrypoint = "main_",
        };
    }
    return .{
        .code = @embedFile("shaders/spirv/" ++ path ++ ".spv"),
        .format = SDL_GPU_SHADERFORMAT_SPIRV,
        .entrypoint = "main",
    };
}

test "sdl gpu struct layout matches SDL3" {
    const testing = @import("std").testing;
    try testing.expectEqual(@as(usize, 168), @sizeOf(SDL_GPUGraphicsPipelineCreateInfo));
    try testing.expectEqual(@as(usize, 24), @sizeOf(SDL_GPUGraphicsPipelineTargetInfo));
    try testing.expectEqual(@as(usize, 32), @sizeOf(SDL_GPUVertexInputState));
    try testing.expectEqual(@as(usize, 28), @sizeOf(SDL_GPURasterizerState));
    try testing.expectEqual(@as(usize, 44), @sizeOf(SDL_GPUDepthStencilState));
    try testing.expectEqual(@as(usize, 12), @sizeOf(SDL_GPUMultisampleState));
    try testing.expectEqual(@as(usize, 56), @sizeOf(SDL_GPUShaderCreateInfo));
    try testing.expectEqual(@as(usize, 64), @sizeOf(SDL_GPUColorTargetInfo));
    try testing.expectEqual(@as(usize, 32), @sizeOf(SDL_GPUDepthStencilTargetInfo));
    try testing.expectEqual(@as(usize, 16), @sizeOf(SDL_GPUVertexBufferDescription));
    try testing.expectEqual(@as(usize, 16), @sizeOf(SDL_GPUVertexAttribute));
}

test "sdl gpu shader format selection" {
    const testing = @import("std").testing;
    const bytes = shaderBytes("SolidColor.frag");
    if (comptime builtin.os.tag == .macos) {
        try testing.expect(bytes.format == SDL_GPU_SHADERFORMAT_MSL);
    } else {
        try testing.expect(bytes.format == SDL_GPU_SHADERFORMAT_SPIRV);
    }
}
