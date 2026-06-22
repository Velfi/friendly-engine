pub const gpu_api = @import("gpu_api.zig");
pub const gpu_backend = gpu_api;
pub const gpu_backend_sdl = @import("gpu_backend_sdl.zig");
pub const sdl_gpu = @import("sdl_gpu.zig");

pub const TextureSize = gpu_api.TextureSize;
pub const SceneGpuObject = gpu_api.SceneGpuObject;
pub const GpuBackendKind = gpu_api.GpuBackendKind;
pub const GpuBackendName = gpu_api.GpuBackendName;
pub const GpuRenderer = gpu_api.GpuRenderer;

test "gpu backend re-exports api" {
    _ = GpuBackendKind.sdl_gpu;
}
