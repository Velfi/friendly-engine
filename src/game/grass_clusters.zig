const std = @import("std");
const core = @import("../core/mod.zig");
const modules = @import("../modules/mod.zig");

pub const Instance = modules.grass.types.GrassInstance;
pub const ClusterMeta = modules.grass.types.ClusterMetadata;
pub const Influencer = modules.grass.types.GrassInfluencer;
pub const GrassCull = modules.grass.runtime.GrassCull;
pub const Decoded = modules.grass.runtime.Decoded;

pub fn decode(allocator: std.mem.Allocator, blobs: []const @import("../world/mod.zig").cell.CellBlob) !Decoded {
    return modules.grass.runtime.decode(allocator, blobs);
}

pub fn cullDistances(meta: ClusterMeta) GrassCull {
    return .{ .cull_distance_m = meta.controls.cull_distance_m, .fade_distance_m = meta.controls.fade_distance_m };
}

pub fn batchFadeFactor(cull: GrassCull, camera: core.math.Vec3f, center: core.math.Vec3f) ?f32 {
    return modules.grass.runtime.batchFadeFactor(cull, camera, center);
}
