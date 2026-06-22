const geometry = @import("geometry.zig");
const shared_color = @import("color.zig");

pub const TextureSize: u32 = 128;

pub const OverlayMaterial = enum {
    rgba,
    coverage_mask,
    distance_field,
};

pub const TextureUsage = enum {
    material,
    terrain_mask,
};

pub const SceneGpuObject = struct {
    mesh: *const geometry.Mesh,
    texture: ?[]const u8,
    base_color: shared_color.Color,
    texture_usage: TextureUsage = .material,
    dissolve_amount: f32 = 0.0,
    dissolve_inverted: bool = false,
};

pub const OverlayQuad = struct {
    rect: [4]f32,
    uv: [4]f32 = .{ 0, 0, 1, 1 },
    skew_x: f32 = 0,
    texture: ?[]const u8 = null,
    gpu_texture: ?*anyopaque = null,
    color: shared_color.Color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    material: OverlayMaterial = .rgba,
    mask_texture: bool = false,
};
