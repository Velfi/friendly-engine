const sdl_gpu = @import("sdl_gpu.zig");

fn useHdrScene(self: anytype) bool {
    return self.scene_color_hdr_active;
}

pub fn activeGridPipeline(self: anytype) *sdl_gpu.SDL_GPUGraphicsPipeline {
    if (useHdrScene(self)) return self.hdr_grid_pipeline.?;
    return if (self.in_offscreen_frame) self.offscreen_grid_pipeline else self.grid_pipeline;
}

pub fn activeWireframePipeline(self: anytype) *sdl_gpu.SDL_GPUGraphicsPipeline {
    if (useHdrScene(self)) return self.hdr_wireframe_pipeline.?;
    return if (self.in_offscreen_frame) self.offscreen_wireframe_pipeline else self.wireframe_pipeline;
}

pub fn activeLitMeshPipeline(self: anytype) *sdl_gpu.SDL_GPUGraphicsPipeline {
    if (useHdrScene(self)) return self.hdr_lit_mesh_pipeline.?;
    return if (self.in_offscreen_frame) self.offscreen_lit_mesh_pipeline else self.lit_mesh_pipeline;
}

pub fn activeDoubleSidedLitMeshPipeline(self: anytype) *sdl_gpu.SDL_GPUGraphicsPipeline {
    if (useHdrScene(self)) return self.hdr_double_sided_lit_mesh_pipeline.?;
    return if (self.in_offscreen_frame) self.offscreen_double_sided_lit_mesh_pipeline else self.double_sided_lit_mesh_pipeline;
}

pub fn activeSolidMeshPipeline(self: anytype) *sdl_gpu.SDL_GPUGraphicsPipeline {
    if (useHdrScene(self)) return self.hdr_solid_mesh_pipeline.?;
    return if (self.in_offscreen_frame) self.offscreen_solid_mesh_pipeline else self.solid_mesh_pipeline;
}

pub fn activeDoubleSidedSolidMeshPipeline(self: anytype) *sdl_gpu.SDL_GPUGraphicsPipeline {
    if (useHdrScene(self)) return self.hdr_double_sided_solid_mesh_pipeline.?;
    return if (self.in_offscreen_frame) self.offscreen_double_sided_solid_mesh_pipeline else self.double_sided_solid_mesh_pipeline;
}

pub fn activeInstancedMeshPipeline(self: anytype) *sdl_gpu.SDL_GPUGraphicsPipeline {
    if (useHdrScene(self)) return self.hdr_instanced_mesh_pipeline.?;
    return if (self.in_offscreen_frame) self.offscreen_instanced_mesh_pipeline else self.instanced_mesh_pipeline;
}

pub fn activeLitInstancedMeshPipeline(self: anytype) *sdl_gpu.SDL_GPUGraphicsPipeline {
    if (useHdrScene(self)) return self.hdr_lit_instanced_mesh_pipeline.?;
    return if (self.in_offscreen_frame) self.offscreen_lit_instanced_mesh_pipeline else self.lit_instanced_mesh_pipeline;
}

pub fn activeSolidInstancedMeshPipeline(self: anytype) *sdl_gpu.SDL_GPUGraphicsPipeline {
    if (useHdrScene(self)) return self.hdr_solid_instanced_mesh_pipeline.?;
    return if (self.in_offscreen_frame) self.offscreen_solid_instanced_mesh_pipeline else self.solid_instanced_mesh_pipeline;
}

pub fn activeMeshPipeline(self: anytype) *sdl_gpu.SDL_GPUGraphicsPipeline {
    if (useHdrScene(self)) return self.hdr_mesh_pipeline.?;
    return if (self.in_offscreen_frame) self.offscreen_mesh_pipeline else self.mesh_pipeline;
}

pub fn activeDoubleSidedMeshPipeline(self: anytype) *sdl_gpu.SDL_GPUGraphicsPipeline {
    if (useHdrScene(self)) return self.hdr_double_sided_mesh_pipeline.?;
    return if (self.in_offscreen_frame) self.offscreen_double_sided_mesh_pipeline else self.double_sided_mesh_pipeline;
}

pub fn activeWaterPipeline(self: anytype) *sdl_gpu.SDL_GPUGraphicsPipeline {
    if (useHdrScene(self)) return self.hdr_water_pipeline.?;
    return if (self.in_offscreen_frame) self.offscreen_water_pipeline else self.water_pipeline;
}

pub fn activeGrassPipeline(self: anytype) *sdl_gpu.SDL_GPUGraphicsPipeline {
    if (useHdrScene(self)) {
        if (self.hdr_grass_pipeline) |pipeline| return pipeline;
    }
    return if (self.in_offscreen_frame) self.offscreen_grass_pipeline else self.grass_pipeline;
}

pub fn activeSkyPipeline(self: anytype) *sdl_gpu.SDL_GPUGraphicsPipeline {
    if (useHdrScene(self)) return self.hdr_sky_pipeline.?;
    return if (self.in_offscreen_frame) self.offscreen_sky_pipeline else self.sky_pipeline;
}
