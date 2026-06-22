const std = @import("std");
const core = @import("../../core/mod.zig");
const world = @import("../../world/mod.zig");
const types = @import("types.zig");
const storage = @import("storage.zig");

pub const blob_kind = "water.volumes";

pub fn queryDoc(doc: types.WaterDoc, point: core.math.Vec3f) types.WaterQuery {
    return types.queryPoint(doc.volumes, point);
}

pub fn parseVolumesBlob(allocator: std.mem.Allocator, payload: []const u8) !types.WaterDoc {
    return storage.parseWaterKdl(allocator, payload);
}

pub fn queryCellBlobs(allocator: std.mem.Allocator, blobs: []const world.cell.CellBlob, point: core.math.Vec3f) !types.WaterQuery {
    var best: types.WaterQuery = .{};
    for (blobs) |blob| {
        if (!std.mem.eql(u8, blob.kind, blob_kind)) continue;
        var doc = try parseVolumesBlob(allocator, blob.payload);
        defer doc.deinit(allocator);
        const query = queryDoc(doc, point);
        if (query.in_water and (!best.in_water or query.surface_y > best.surface_y)) best = query;
    }
    return best;
}

test "query cell blobs ignores missing water blobs" {
    const query = try queryCellBlobs(std.testing.allocator, &.{}, .{ .x = 0, .y = 0, .z = 0 });
    try std.testing.expect(!query.in_water);
}
