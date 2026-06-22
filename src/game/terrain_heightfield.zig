const std = @import("std");
const core = @import("../core/mod.zig");
const world_mod = @import("../world/mod.zig");

pub const Decoded = struct {
    size: u32,
    block_size: u32,
    offset: core.math.Vec3f,
    scale: core.math.Vec3f,
    envelope_half: core.math.Vec3f,
    heights: []f32,

    pub fn deinit(self: *Decoded, allocator: std.mem.Allocator) void {
        allocator.free(self.heights);
        self.heights = &.{};
    }
};

pub fn findHeightfieldBlob(blobs: []const world_mod.cell.CellBlob) ?[]const u8 {
    for (blobs) |blob| {
        if (std.mem.eql(u8, blob.kind, "terrain.heightfield")) return blob.payload;
    }
    return null;
}

pub fn findHeightfieldBlobForShape(blobs: []const world_mod.cell.CellBlob, min: core.math.Vec3f, max: core.math.Vec3f) ?[]const u8 {
    var first: ?[]const u8 = null;
    var terrain_blob_count: usize = 0;
    for (blobs) |blob| {
        if (!std.mem.eql(u8, blob.kind, "terrain.heightfield")) continue;
        terrain_blob_count += 1;
        if (first == null) first = blob.payload;
        if (heightfieldBlobMatchesBounds(blob.payload, min, max) catch false) return blob.payload;
    }
    if (terrain_blob_count == 1) return first;
    return null;
}

fn heightfieldBlobMatchesBounds(payload: []const u8, min: core.math.Vec3f, max: core.math.Vec3f) !bool {
    const Bounds = struct {
        min_x: f32,
        min_z: f32,
        max_x: f32,
        max_z: f32,
    };
    const JsonBlob = struct {
        bounds: ?Bounds = null,
    };
    var buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    var parsed = try std.json.parseFromSlice(JsonBlob, fba.allocator(), payload, .{
        .allocate = .alloc_if_needed,
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    const bounds = parsed.value.bounds orelse return false;
    const eps: f32 = 0.01;
    return @abs(bounds.min_x - min.x) <= eps and
        @abs(bounds.min_z - min.z) <= eps and
        @abs(bounds.max_x - max.x) <= eps and
        @abs(bounds.max_z - max.z) <= eps;
}

pub fn decodeBlob(
    allocator: std.mem.Allocator,
    payload: []const u8,
    envelope_min: core.math.Vec3f,
    envelope_max: core.math.Vec3f,
) !Decoded {
    const JsonBlob = struct {
        size: u32,
        min_y: f32,
        max_y: f32,
        heights: []const f32,
    };

    var parsed = try std.json.parseFromSlice(JsonBlob, allocator, payload, .{
        .allocate = .alloc_if_needed,
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    const size = parsed.value.size;
    try validateJoltHeightfieldSize(size, default_block_size);

    const expected = @as(usize, size) * @as(usize, size);
    if (parsed.value.heights.len != expected) return error.InvalidTerrainHeightfieldBlob;

    for (parsed.value.heights) |height| {
        if (!std.math.isFinite(height)) return error.InvalidTerrainHeightfieldBlob;
    }
    if (!std.math.isFinite(parsed.value.min_y) or !std.math.isFinite(parsed.value.max_y)) {
        return error.InvalidTerrainHeightfieldBlob;
    }

    const width = envelope_max.x - envelope_min.x;
    const depth = envelope_max.z - envelope_min.z;
    if (width <= std.math.floatEps(f32) or depth <= std.math.floatEps(f32)) {
        return error.InvalidTerrainHeightfieldBlob;
    }

    const span = @max(size - 1, 1);
    const scale = core.math.Vec3f{
        .x = width / @as(f32, @floatFromInt(span)),
        .y = 1.0,
        .z = depth / @as(f32, @floatFromInt(span)),
    };
    const body_center = core.math.Vec3f{
        .x = (envelope_min.x + envelope_max.x) * 0.5,
        .y = 0.0,
        .z = (envelope_min.z + envelope_max.z) * 0.5,
    };
    const offset = core.math.Vec3f{
        .x = envelope_min.x - body_center.x,
        .y = 0.0,
        .z = envelope_min.z - body_center.z,
    };
    const envelope_half = core.math.Vec3f{
        .x = width * 0.5,
        .y = (envelope_max.y - envelope_min.y) * 0.5,
        .z = depth * 0.5,
    };

    const heights = try allocator.dupe(f32, parsed.value.heights);

    return .{
        .size = size,
        .block_size = default_block_size,
        .offset = offset,
        .scale = scale,
        .envelope_half = envelope_half,
        .heights = heights,
    };
}

pub fn validateJoltHeightfieldSize(size: u32, block_size: u32) !void {
    if (size < 2 or block_size < 2 or block_size > 8) return error.InvalidTerrainHeightfieldSize;
    if (size % block_size != 0) return error.InvalidTerrainHeightfieldSize;
    const blocks = size / block_size;
    if (blocks < 2 or !std.math.isPowerOfTwo(blocks)) return error.InvalidTerrainHeightfieldSize;
}

const default_block_size: u32 = 2;

comptime {
    _ = @import("terrain_heightfield_tests.zig");
}
