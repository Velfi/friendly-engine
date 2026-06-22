const std = @import("std");

/// Texture placement in world units (one repeat spans `scale_world` meters).
pub const Transform = struct {
    scale_world: f32 = 1.0,
    rotation_deg: f32 = 0.0,
    offset_u: f32 = 0.0,
    offset_v: f32 = 0.0,
    align_u: f32 = 0.0,
    align_v: f32 = 0.0,

    pub fn duplicate(_: std.mem.Allocator, source: Transform) Transform {
        return source;
    }

    pub fn fitToFace(face_width: f32, face_height: f32) Transform {
        const span = @max(0.01, @max(face_width, face_height));
        return .{ .scale_world = span };
    }

    pub fn alignToFace(face_width: f32, face_height: f32) Transform {
        return .{
            .scale_world = @max(0.01, @max(face_width, face_height)),
            .align_u = face_width * 0.5,
            .align_v = face_height * 0.5,
        };
    }
};

pub const FaceMaterial = struct {
    face_index: usize,
    material_path: []u8,
    transform: Transform,

    pub fn deinit(self: *FaceMaterial, allocator: std.mem.Allocator) void {
        allocator.free(self.material_path);
    }

    pub fn duplicate(allocator: std.mem.Allocator, source: FaceMaterial) !FaceMaterial {
        return .{
            .face_index = source.face_index,
            .material_path = try allocator.dupe(u8, source.material_path),
            .transform = source.transform,
        };
    }
};

pub const MaterialError = struct {
    path: []u8,
    reason: []const u8,

    pub fn deinit(self: *MaterialError, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
    }
};

pub fn validateMaterialPath(path: []const u8) ?[]const u8 {
    if (path.len == 0) return "Material path is empty";
    if (std.mem.indexOfScalar(u8, path, '\\') != null) return "Material path must use forward slashes";
    return null;
}

test "texture transform fit uses largest face dimension" {
    const fit = Transform.fitToFace(2.0, 4.0);
    try std.testing.expectEqual(@as(f32, 4.0), fit.scale_world);
}

test "material path validation rejects empty and backslashes" {
    try std.testing.expectEqualStrings("Material path is empty", validateMaterialPath("").?);
    try std.testing.expectEqualStrings("Material path must use forward slashes", validateMaterialPath("textures\\wall.png").?);
    try std.testing.expect(validateMaterialPath("textures/wall.png") == null);
}
