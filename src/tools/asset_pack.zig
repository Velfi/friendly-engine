const std = @import("std");

pub const PackEntry = struct {
    asset_id: u64,
    artifact_path: []const u8,
    kind: []const u8,
    content_hash: u64,
    offset: u64,
    size: u64,
    dependencies: []const []const u8,
};

pub const PackSummary = struct {
    pack_file: []u8,
    index_file: []u8,
    byte_count: u64,

    pub fn deinit(self: *PackSummary, allocator: std.mem.Allocator) void {
        allocator.free(self.pack_file);
        allocator.free(self.index_file);
    }
};

pub fn writePack(
    io: std.Io,
    root_dir: std.Io.Dir,
    allocator: std.mem.Allocator,
    target: []const u8,
    bundle_dir: []const u8,
    assets: []PackEntry,
) !PackSummary {
    const target_dir = try std.fs.path.join(allocator, &.{ bundle_dir, target });
    defer allocator.free(target_dir);
    try root_dir.createDirPath(io, target_dir);

    const pack_file = try std.fs.path.join(allocator, &.{ target_dir, "game.fpack" });
    errdefer allocator.free(pack_file);
    const index_file = try std.fs.path.join(allocator, &.{ target_dir, "game.fpack.index.json" });
    errdefer allocator.free(index_file);

    var pack_bytes = std.ArrayList(u8).empty;
    defer pack_bytes.deinit(allocator);
    for (assets, 0..) |asset, index| {
        const offset = pack_bytes.items.len;
        const bytes = try root_dir.readFileAlloc(io, asset.artifact_path, allocator, .limited(64 * 1024 * 1024));
        defer allocator.free(bytes);
        try pack_bytes.appendSlice(allocator, bytes);
        assets[index].offset = @intCast(offset);
        assets[index].size = @intCast(bytes.len);
    }

    try root_dir.writeFile(io, .{ .sub_path = pack_file, .data = pack_bytes.items });
    try writeIndex(io, root_dir, allocator, index_file, target, pack_file, assets);
    return .{
        .pack_file = pack_file,
        .index_file = index_file,
        .byte_count = @intCast(pack_bytes.items.len),
    };
}

fn writeIndex(
    io: std.Io,
    root_dir: std.Io.Dir,
    allocator: std.mem.Allocator,
    index_file: []const u8,
    target: []const u8,
    pack_file: []const u8,
    entries: []const PackEntry,
) !void {
    const doc = .{
        .schema_version = @as(u16, 1),
        .target = target,
        .pack_file = pack_file,
        .asset_count = entries.len,
        .assets = entries,
    };
    const json = try std.fmt.allocPrint(
        allocator,
        "{f}\n",
        .{std.json.fmt(doc, .{ .whitespace = .indent_2 })},
    );
    defer allocator.free(json);
    try root_dir.writeFile(io, .{ .sub_path = index_file, .data = json });
}
