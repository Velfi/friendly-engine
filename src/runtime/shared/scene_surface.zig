const std = @import("std");

pub const SurfaceType = enum {
    default,
    walkable,
    slippery,

    pub fn label(self: SurfaceType) []const u8 {
        return switch (self) {
            .default => "default",
            .walkable => "walkable",
            .slippery => "slippery",
        };
    }

    pub fn next(self: SurfaceType) SurfaceType {
        return switch (self) {
            .default => .walkable,
            .walkable => .slippery,
            .slippery => .default,
        };
    }

    pub fn fromName(text: []const u8) ?SurfaceType {
        if (std.mem.eql(u8, text, "default")) return .default;
        if (std.mem.eql(u8, text, "walkable")) return .walkable;
        if (std.mem.eql(u8, text, "slippery")) return .slippery;
        return null;
    }
};

pub const FaceSurface = struct {
    face_index: usize,
    surface_type: SurfaceType = .default,

    pub fn duplicate(_: std.mem.Allocator, source: FaceSurface) FaceSurface {
        return source;
    }
};

test "surface type cycles and round-trips names" {
    try std.testing.expectEqual(SurfaceType.walkable, SurfaceType.default.next());
    try std.testing.expectEqual(SurfaceType.default, SurfaceType.fromName("default").?);
    try std.testing.expectEqualStrings("walkable", SurfaceType.walkable.label());
}
