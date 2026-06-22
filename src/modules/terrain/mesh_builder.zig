const std = @import("std");
const world = @import("../../world/mod.zig");

pub const terrain_texture_size: usize = 128 * 128 * 4;

pub const HeightTile = struct {
    size: u32,
    heights: []const f32,
};

pub const HeightNeighbors = struct {
    west: ?HeightTile = null,
    east: ?HeightTile = null,
    south: ?HeightTile = null,
    north: ?HeightTile = null,
};

pub const CutoutRect = struct {
    min_x: f32,
    min_z: f32,
    max_x: f32,
    max_z: f32,

    pub fn containsPoint(self: CutoutRect, x: f32, z: f32) bool {
        return x >= self.min_x and x <= self.max_x and z >= self.min_z and z <= self.max_z;
    }
};

pub fn buildLodMesh(
    allocator: std.mem.Allocator,
    bounds: world.cell.CellBounds,
    tile: HeightTile,
    lod_size: u32,
    lod_index: usize,
    neighbors: ?HeightNeighbors,
) !world.cell.RenderMesh {
    return buildLodMeshWithCutouts(allocator, bounds, tile, lod_size, lod_index, neighbors, &.{});
}

pub fn buildLodMeshWithCutouts(
    allocator: std.mem.Allocator,
    bounds: world.cell.CellBounds,
    tile: HeightTile,
    lod_size: u32,
    lod_index: usize,
    neighbors: ?HeightNeighbors,
    cutouts: []const CutoutRect,
) !world.cell.RenderMesh {
    const size: usize = @intCast(lod_size);
    const vert_count = size * size;
    const max_index_count = (size - 1) * (size - 1) * 6;

    const vertices = try allocator.alloc(world.cell.RenderVertex, vert_count);
    errdefer allocator.free(vertices);
    var indices_list = try std.ArrayList(u32).initCapacity(allocator, max_index_count);
    defer indices_list.deinit(allocator);

    var idx: usize = 0;
    var z: usize = 0;
    while (z < size) : (z += 1) {
        var x: usize = 0;
        while (x < size) : (x += 1) {
            const u = @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(size - 1));
            const v = @as(f32, @floatFromInt(z)) / @as(f32, @floatFromInt(size - 1));
            const source = sampleHeight(tile, x, z, size);
            vertices[idx] = .{
                .position = .{
                    .x = bounds.min.x + (bounds.max.x - bounds.min.x) * u,
                    .y = source,
                    .z = bounds.min.z + (bounds.max.z - bounds.min.z) * v,
                },
                .normal = .{ .x = 0, .y = 1, .z = 0 },
                .uv = .{ .x = u, .y = v },
            };
            idx += 1;
        }
    }

    computeGridNormals(vertices, size, tile, bounds, neighbors orelse .{});

    z = 0;
    while (z + 1 < size) : (z += 1) {
        var x: usize = 0;
        while (x + 1 < size) : (x += 1) {
            const a: u32 = @intCast(z * size + x);
            const b: u32 = @intCast(a + 1);
            const c: u32 = @intCast((z + 1) * size + x + 1);
            const d: u32 = @intCast((z + 1) * size + x);
            if (triangleCutOut(vertices, a, c, b, cutouts)) {
                try indices_list.appendSlice(allocator, &.{ a, c, b });
            }
            if (triangleCutOut(vertices, a, d, c, cutouts)) {
                try indices_list.appendSlice(allocator, &.{ a, d, c });
            }
        }
    }

    const texture = try allocator.alloc(u8, terrain_texture_size);
    @memset(texture, @as(u8, @intCast(90 + @as(i32, @intCast(lod_index)) * 20)));
    errdefer allocator.free(texture);

    const name = try std.fmt.allocPrint(allocator, "terrain.lod{d}", .{lod_index});
    errdefer allocator.free(name);

    const indices = try indices_list.toOwnedSlice(allocator);
    errdefer allocator.free(indices);

    return .{
        .name = name,
        .vertices = vertices,
        .indices = indices,
        .texture = texture,
        .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
    };
}

fn triangleCutOut(vertices: []const world.cell.RenderVertex, ia: u32, ib: u32, ic: u32, cutouts: []const CutoutRect) bool {
    if (cutouts.len == 0) return true;
    const a = vertices[@intCast(ia)].position;
    const b = vertices[@intCast(ib)].position;
    const c = vertices[@intCast(ic)].position;
    const cx = (a.x + b.x + c.x) / 3.0;
    const cz = (a.z + b.z + c.z) / 3.0;
    for (cutouts) |cutout| {
        if (cutout.containsPoint(cx, cz)) return false;
    }
    return true;
}

pub fn sampleHeight(tile: HeightTile, x: usize, z: usize, lod_size: usize) f32 {
    const src_size: usize = @intCast(tile.size);
    if (src_size == lod_size) return tile.heights[z * src_size + x];

    const x_range = sourceFootprint(x, lod_size, src_size);
    const z_range = sourceFootprint(z, lod_size, src_size);
    var sum: f32 = 0;
    var min_height = std.math.floatMax(f32);
    var max_height = -std.math.floatMax(f32);
    var count: usize = 0;

    var src_z = z_range.min;
    while (src_z <= z_range.max) : (src_z += 1) {
        var src_x = x_range.min;
        while (src_x <= x_range.max) : (src_x += 1) {
            const height = tile.heights[src_z * src_size + src_x];
            sum += height;
            min_height = @min(min_height, height);
            max_height = @max(max_height, height);
            count += 1;
        }
    }

    if (count == 0) return sampleNearest(tile, x, z, lod_size);
    const average = sum / @as(f32, @floatFromInt(count));
    const dominant = if (@abs(max_height - average) >= @abs(min_height - average)) max_height else min_height;
    return average + (dominant - average) * 0.25;
}

const SourceRange = struct {
    min: usize,
    max: usize,
};

fn sourceFootprint(coord: usize, lod_size: usize, src_size: usize) SourceRange {
    if (coord == 0 or coord + 1 == lod_size) {
        const exact = nearestSourceCoord(coord, lod_size, src_size);
        return .{ .min = exact, .max = exact };
    }

    const max_src = src_size - 1;
    const center = @as(f32, @floatFromInt(coord)) / @as(f32, @floatFromInt(lod_size - 1));
    const half_step = 0.5 / @as(f32, @floatFromInt(lod_size - 1));
    const min_norm = @max(0, center - half_step);
    const max_norm = @min(1, center + half_step);
    const min_index: usize = @intFromFloat(@floor(min_norm * @as(f32, @floatFromInt(max_src))));
    const max_index: usize = @intFromFloat(@ceil(max_norm * @as(f32, @floatFromInt(max_src))));
    return .{ .min = @min(min_index, max_src), .max = @min(max_index, max_src) };
}

fn sampleNearest(tile: HeightTile, x: usize, z: usize, lod_size: usize) f32 {
    const src_size: usize = @intCast(tile.size);
    return tile.heights[nearestSourceCoord(z, lod_size, src_size) * src_size + nearestSourceCoord(x, lod_size, src_size)];
}

fn nearestSourceCoord(coord: usize, lod_size: usize, src_size: usize) usize {
    return @min(src_size - 1, (coord * (src_size - 1)) / @max(lod_size - 1, 1));
}

fn computeGridNormals(
    vertices: []world.cell.RenderVertex,
    size: usize,
    tile: HeightTile,
    bounds: world.cell.CellBounds,
    neighbors: HeightNeighbors,
) void {
    const cell_width = @max(0.001, bounds.max.x - bounds.min.x);
    const cell_depth = @max(0.001, bounds.max.z - bounds.min.z);
    const step_x = cell_width / @as(f32, @floatFromInt(size - 1));
    const step_z = cell_depth / @as(f32, @floatFromInt(size - 1));
    var z: usize = 0;
    while (z < size) : (z += 1) {
        var x: usize = 0;
        while (x < size) : (x += 1) {
            const idx = z * size + x;
            const here = vertices[idx].position;
            const left = if (x > 0) vertices[idx - 1].position else borderSample(.west, tile, neighbors.west, x, z, size, here, step_x, step_z);
            const right = if (x + 1 < size) vertices[idx + 1].position else borderSample(.east, tile, neighbors.east, x, z, size, here, step_x, step_z);
            const back = if (z > 0) vertices[idx - size].position else borderSample(.south, tile, neighbors.south, x, z, size, here, step_x, step_z);
            const forward = if (z + 1 < size) vertices[idx + size].position else borderSample(.north, tile, neighbors.north, x, z, size, here, step_x, step_z);
            const dx = (right.y - left.y) / @max(0.001, right.x - left.x);
            const dz = (forward.y - back.y) / @max(0.001, forward.z - back.z);
            const nx = -dx;
            const ny = 1.0;
            const nz = -dz;
            const len = @sqrt(nx * nx + ny * ny + nz * nz);
            if (len > 0.0001) {
                vertices[idx].normal = .{ .x = nx / len, .y = ny / len, .z = nz / len };
            }
        }
    }
}

const BorderDirection = enum { west, east, south, north };

fn borderSample(
    direction: BorderDirection,
    tile: HeightTile,
    neighbor: ?HeightTile,
    x: usize,
    z: usize,
    lod_size: usize,
    here: @import("../../core/mod.zig").math.Vec3f,
    step_x: f32,
    step_z: f32,
) @import("../../core/mod.zig").math.Vec3f {
    const h = switch (direction) {
        .west => if (neighbor) |other| sampleHeight(other, lod_size - 2, z, lod_size) else sampleHeight(tile, 0, z, lod_size),
        .east => if (neighbor) |other| sampleHeight(other, 1, z, lod_size) else sampleHeight(tile, lod_size - 1, z, lod_size),
        .south => if (neighbor) |other| sampleHeight(other, x, lod_size - 2, lod_size) else sampleHeight(tile, x, 0, lod_size),
        .north => if (neighbor) |other| sampleHeight(other, x, 1, lod_size) else sampleHeight(tile, x, lod_size - 1, lod_size),
    };
    return switch (direction) {
        .west => .{ .x = here.x - step_x, .y = h, .z = here.z },
        .east => .{ .x = here.x + step_x, .y = h, .z = here.z },
        .south => .{ .x = here.x, .y = h, .z = here.z - step_z },
        .north => .{ .x = here.x, .y = h, .z = here.z + step_z },
    };
}

test "sampleHeight keeps full-resolution samples exact" {
    const heights = [_]f32{
        0, 1, 2,
        3, 4, 5,
        6, 7, 8,
    };
    const tile = HeightTile{ .size = 3, .heights = &heights };
    try std.testing.expectEqual(@as(f32, 4), sampleHeight(tile, 1, 1, 3));
    try std.testing.expectEqual(@as(f32, 8), sampleHeight(tile, 2, 2, 3));
}

test "sampleHeight filters coarse interior samples while preserving features" {
    const heights = [_]f32{
        0, 0, 0,  0, 0,
        0, 0, 0,  0, 0,
        0, 0, 10, 0, 0,
        0, 0, 0,  0, 0,
        0, 0, 0,  0, 0,
    };
    const tile = HeightTile{ .size = 5, .heights = &heights };
    try std.testing.expectApproxEqAbs(@as(f32, 3.3333333), sampleHeight(tile, 1, 1, 3), 0.0001);
}

test "sampleHeight filters along borders for seam-stable edge lods" {
    const heights = [_]f32{
        0,  0, 0, 0, 0,
        0,  0, 0, 0, 0,
        10, 0, 0, 0, 0,
        0,  0, 0, 0, 0,
        0,  0, 0, 0, 0,
    };
    const tile = HeightTile{ .size = 5, .heights = &heights };
    try std.testing.expectApproxEqAbs(@as(f32, 5), sampleHeight(tile, 0, 1, 3), 0.0001);
    try std.testing.expectEqual(@as(f32, 0), sampleHeight(tile, 0, 0, 3));
}

test "buildLodMesh produces finite heights" {
    const heights = [_]f32{ 0, 1, 2, 3, 4, 5, 6, 7, 8 };
    const tile = HeightTile{ .size = 3, .heights = &heights };
    const bounds = world.cell.boundsForCell(.{ .x = 0, .y = 0, .z = 0 }, 64, 32);
    var mesh = try buildLodMesh(std.testing.allocator, bounds, tile, 3, 0, null);
    defer mesh.deinit(std.testing.allocator);
    try std.testing.expect(mesh.vertices.len == 9);
    try std.testing.expect(mesh.indices.len == 24);
    try std.testing.expect(std.math.isFinite(mesh.vertices[4].position.y));
}

test "buildLodMesh emits upward-facing terrain triangles" {
    const heights = [_]f32{ 0, 0, 0, 0 };
    const tile = HeightTile{ .size = 2, .heights = &heights };
    const bounds = world.cell.boundsForCell(.{ .x = 0, .y = 0, .z = 0 }, 64, 32);
    var mesh = try buildLodMesh(std.testing.allocator, bounds, tile, 2, 0, null);
    defer mesh.deinit(std.testing.allocator);

    try std.testing.expect(triangleNormalY(mesh.vertices, mesh.indices[0..3]) > 0.99);
    try std.testing.expect(triangleNormalY(mesh.vertices, mesh.indices[3..6]) > 0.99);
}

test "buildLodMesh computes unit upward normals for flat terrain" {
    const heights = [_]f32{
        4, 4, 4,
        4, 4, 4,
        4, 4, 4,
    };
    const tile = HeightTile{ .size = 3, .heights = &heights };
    const bounds = world.cell.boundsForCell(.{ .x = 0, .y = 0, .z = 0 }, 64, 32);
    var mesh = try buildLodMesh(std.testing.allocator, bounds, tile, 3, 0, null);
    defer mesh.deinit(std.testing.allocator);

    for (mesh.vertices) |vertex| {
        try expectVec3Approx(vertex.normal, 0, 1, 0, 0.0001);
        try expectUnitNormal(vertex.normal);
    }
}

test "buildLodMesh computes expected normal for planar x slope" {
    const heights = [_]f32{
        0, 8, 16,
        0, 8, 16,
        0, 8, 16,
    };
    const tile = HeightTile{ .size = 3, .heights = &heights };
    const bounds = world.cell.boundsForCell(.{ .x = 0, .y = 0, .z = 0 }, 64, 32);
    var mesh = try buildLodMesh(std.testing.allocator, bounds, tile, 3, 0, null);
    defer mesh.deinit(std.testing.allocator);

    const expected = normalizedVec3(-0.25, 1, 0);
    try expectVec3Approx(mesh.vertices[4].normal, expected.x, expected.y, expected.z, 0.0001);
    try expectUnitNormal(mesh.vertices[4].normal);
}

test "buildLodMesh computes expected normal for planar z slope" {
    const heights = [_]f32{
        0,  0,  0,
        8,  8,  8,
        16, 16, 16,
    };
    const tile = HeightTile{ .size = 3, .heights = &heights };
    const bounds = world.cell.boundsForCell(.{ .x = 0, .y = 0, .z = 0 }, 64, 32);
    var mesh = try buildLodMesh(std.testing.allocator, bounds, tile, 3, 0, null);
    defer mesh.deinit(std.testing.allocator);

    const expected = normalizedVec3(0, 1, -0.25);
    try expectVec3Approx(mesh.vertices[4].normal, expected.x, expected.y, expected.z, 0.0001);
    try expectUnitNormal(mesh.vertices[4].normal);
}

test "buildLodMesh uses neighbor heights for border normals" {
    const heights = [_]f32{
        0, 0,
        0, 0,
    };
    const east_heights = [_]f32{
        0, 10,
        0, 10,
    };
    const tile = HeightTile{ .size = 2, .heights = &heights };
    const east = HeightTile{ .size = 2, .heights = &east_heights };
    const bounds = world.cell.boundsForCell(.{ .x = 0, .y = 0, .z = 0 }, 64, 32);
    var mesh = try buildLodMesh(std.testing.allocator, bounds, tile, 2, 0, .{ .east = east });
    defer mesh.deinit(std.testing.allocator);
    try std.testing.expect(mesh.vertices[1].normal.x < -0.01);
}

test "buildLodMesh border normals use west and east neighbor slopes symmetrically" {
    const heights = [_]f32{
        0, 0, 0,
        0, 0, 0,
        0, 0, 0,
    };
    const west_heights = [_]f32{
        8, 0, 0,
        8, 0, 0,
        8, 0, 0,
    };
    const east_heights = [_]f32{
        0, 8, 0,
        0, 8, 0,
        0, 8, 0,
    };
    const tile = HeightTile{ .size = 3, .heights = &heights };
    const west = HeightTile{ .size = 3, .heights = &west_heights };
    const east = HeightTile{ .size = 3, .heights = &east_heights };
    const bounds = world.cell.boundsForCell(.{ .x = 0, .y = 0, .z = 0 }, 64, 32);
    var mesh = try buildLodMesh(std.testing.allocator, bounds, tile, 3, 0, .{ .west = west, .east = east });
    defer mesh.deinit(std.testing.allocator);

    try std.testing.expect(mesh.vertices[3].normal.x > 0.01);
    try std.testing.expect(mesh.vertices[5].normal.x < -0.01);
    try expectUnitNormal(mesh.vertices[3].normal);
    try expectUnitNormal(mesh.vertices[5].normal);
    try std.testing.expect(mesh.vertices[3].normal.y > 0.98);
    try std.testing.expect(mesh.vertices[5].normal.y > 0.98);
}

fn triangleNormalY(vertices: []const world.cell.RenderVertex, indices: []const u32) f32 {
    const a = vertices[indices[0]].position;
    const b = vertices[indices[1]].position;
    const c = vertices[indices[2]].position;
    const ab = .{ .x = b.x - a.x, .y = b.y - a.y, .z = b.z - a.z };
    const ac = .{ .x = c.x - a.x, .y = c.y - a.y, .z = c.z - a.z };
    const y = (ab.z * ac.x) - (ab.x * ac.z);
    const len = @sqrt(
        std.math.pow(f32, (ab.y * ac.z) - (ab.z * ac.y), 2) +
            std.math.pow(f32, y, 2) +
            std.math.pow(f32, (ab.x * ac.y) - (ab.y * ac.x), 2),
    );
    return y / len;
}

fn normalizedVec3(x: f32, y: f32, z: f32) @import("../../core/mod.zig").math.Vec3f {
    const len = @sqrt(x * x + y * y + z * z);
    return .{ .x = x / len, .y = y / len, .z = z / len };
}

fn expectVec3Approx(actual: @import("../../core/mod.zig").math.Vec3f, x: f32, y: f32, z: f32, tolerance: f32) !void {
    try std.testing.expectApproxEqAbs(x, actual.x, tolerance);
    try std.testing.expectApproxEqAbs(y, actual.y, tolerance);
    try std.testing.expectApproxEqAbs(z, actual.z, tolerance);
}

fn expectUnitNormal(normal: @import("../../core/mod.zig").math.Vec3f) !void {
    const len = @sqrt(normal.x * normal.x + normal.y * normal.y + normal.z * normal.z);
    try std.testing.expectApproxEqAbs(@as(f32, 1), len, 0.0001);
    try std.testing.expect(normal.y > 0);
}
