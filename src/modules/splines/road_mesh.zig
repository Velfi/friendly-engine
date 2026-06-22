const std = @import("std");
const core = @import("../../core/mod.zig");
const world = @import("../../world/mod.zig");

const road_texture_size: usize = 128 * 128 * 4;

pub const GeneratedRoadSegment = struct {
    mesh: world.cell.RenderMesh,
    collision: world.cell.CollisionPlaceholder,
};

pub fn buildRoadSegmentMesh(
    allocator: std.mem.Allocator,
    road_id: []const u8,
    width: f32,
    elevation: f32,
    segment_index: usize,
    a: core.math.Vec3f,
    b: core.math.Vec3f,
) !GeneratedRoadSegment {
    const half = width * 0.5;
    var dir_x = b.x - a.x;
    var dir_z = b.z - a.z;
    const length = @sqrt(dir_x * dir_x + dir_z * dir_z);
    if (length <= 0.001) return error.InvalidRoadSegment;
    dir_x /= length;
    dir_z /= length;
    const side_x = -dir_z * half;
    const side_z = dir_x * half;
    const up = elevation;

    const verts = try allocator.dupe(world.cell.RenderVertex, &.{
        .{
            .position = .{ .x = a.x - side_x, .y = a.y + up, .z = a.z - side_z },
            .normal = .{ .x = 0, .y = 1, .z = 0 },
            .uv = .{ .x = 0, .y = 0 },
        },
        .{
            .position = .{ .x = a.x + side_x, .y = a.y + up, .z = a.z + side_z },
            .normal = .{ .x = 0, .y = 1, .z = 0 },
            .uv = .{ .x = 1, .y = 0 },
        },
        .{
            .position = .{ .x = b.x + side_x, .y = b.y + up, .z = b.z + side_z },
            .normal = .{ .x = 0, .y = 1, .z = 0 },
            .uv = .{ .x = 1, .y = 1 },
        },
        .{
            .position = .{ .x = b.x - side_x, .y = b.y + up, .z = b.z - side_z },
            .normal = .{ .x = 0, .y = 1, .z = 0 },
            .uv = .{ .x = 0, .y = 1 },
        },
    });
    errdefer allocator.free(verts);
    const indices = try allocator.dupe(u32, &.{ 0, 1, 2, 0, 2, 3 });
    errdefer allocator.free(indices);
    const texture = try allocator.alloc(u8, road_texture_size);
    @memset(texture, 65);
    errdefer allocator.free(texture);

    const name = try std.fmt.allocPrint(allocator, "road.{s}.{d}", .{ road_id, segment_index });
    errdefer allocator.free(name);

    const min: core.math.Vec3f = .{
        .x = @min(@min(verts[0].position.x, verts[1].position.x), @min(verts[2].position.x, verts[3].position.x)),
        .y = @min(@min(verts[0].position.y, verts[1].position.y), @min(verts[2].position.y, verts[3].position.y)) - 0.1,
        .z = @min(@min(verts[0].position.z, verts[1].position.z), @min(verts[2].position.z, verts[3].position.z)),
    };
    const max: core.math.Vec3f = .{
        .x = @max(@max(verts[0].position.x, verts[1].position.x), @max(verts[2].position.x, verts[3].position.x)),
        .y = @max(@max(verts[0].position.y, verts[1].position.y), @max(verts[2].position.y, verts[3].position.y)) + 0.1,
        .z = @max(@max(verts[0].position.z, verts[1].position.z), @max(verts[2].position.z, verts[3].position.z)),
    };

    return .{
        .mesh = .{
            .name = name,
            .vertices = verts,
            .indices = indices,
            .texture = texture,
            .base_color = .{ .r = 80, .g = 80, .b = 84, .a = 255 },
            .position = .{ .x = 0, .y = 0, .z = 0 },
            .scale = .{ .x = 1, .y = 1, .z = 1 },
        },
        .collision = .{ .min = min, .max = max },
    };
}

pub fn segmentIntersectsCell(a: core.math.Vec3f, b: core.math.Vec3f, bounds: world.cell.CellBounds) bool {
    const min_x = @min(a.x, b.x);
    const max_x = @max(a.x, b.x);
    const min_z = @min(a.z, b.z);
    const max_z = @max(a.z, b.z);
    if (max_x < bounds.min.x or min_x > bounds.max.x) return false;
    if (max_z < bounds.min.z or min_z > bounds.max.z) return false;
    return true;
}

test "road mesh builds segment mesh for sampled middle segment" {
    const generated = try buildRoadSegmentMesh(
        std.testing.allocator,
        "main",
        4,
        0.1,
        1,
        .{ .x = 0, .y = 0, .z = 0 },
        .{ .x = 48, .y = 0, .z = 0 },
    );
    defer generated.mesh.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 4), generated.mesh.vertices.len);
    try std.testing.expectEqual(@as(usize, 6), generated.mesh.indices.len);
    try std.testing.expect(generated.mesh.vertices[2].position.x > 47);
}
