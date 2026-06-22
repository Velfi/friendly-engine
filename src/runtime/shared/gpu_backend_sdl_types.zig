const sdl_gpu = @import("sdl_gpu.zig");
const gpu_scene = @import("gpu_scene.zig");

pub const SdlGpuVertex = extern struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32,
    nx: f32,
    ny: f32,
    nz: f32,
    u: f32,
    v: f32,
};

pub const GridColorVertex = extern struct {
    x: f32,
    y: f32,
    z: f32,
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

pub const OverlayVertex = extern struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32,
    u: f32,
    v: f32,
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

pub const GpuMeshInstance = extern struct {
    model: [16]f32,
};

pub const GpuGrassInstance = extern struct {
    position: [4]f32,
    normal_height: [4]f32,
    color: [4]f32,
    blade: [4]f32,
};

pub const GpuGrassInfluencer = extern struct {
    position_radius: [4]f32,
    velocity_strength: [4]f32,
};

pub const GpuGrassUniforms = extern struct {
    view_proj: [16]f32,
    wind: [4]f32,
    controls: [4]f32,
    influencers: [16]GpuGrassInfluencer,
    counts: [4]u32,
};

pub const UploadedMeshStats = struct {
    meshes: u32 = 0,
    indexed_primitives: u64 = 0,
    wireframe_indices: u64 = 0,
};

pub const SdlGpuMesh = struct {
    vertex_buffer: ?*sdl_gpu.SDL_GPUBuffer,
    index_buffer: ?*sdl_gpu.SDL_GPUBuffer,
    wireframe_index_buffer: ?*sdl_gpu.SDL_GPUBuffer,
    texture: ?*sdl_gpu.SDL_GPUTexture,
    index_count: u32,
    wireframe_index_count: u32,
    has_texture: bool,
    texture_usage: gpu_scene.TextureUsage,
    base_color: [4]f32,
    dissolve_amount: f32,
    dissolve_inverted: bool,
};
