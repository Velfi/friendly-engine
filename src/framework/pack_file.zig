const std = @import("std");

pub const max_pack_bytes: usize = 512 * 1024 * 1024;

pub fn readEntry(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_dir: std.Io.Dir,
    pack_path: []const u8,
    offset: u64,
    size: u64,
) ![]u8 {
    const pack_bytes = try project_dir.readFileAlloc(io, pack_path, allocator, .limited(max_pack_bytes));
    defer allocator.free(pack_bytes);

    const start: usize = @intCast(offset);
    const len: usize = @intCast(size);
    if (start > pack_bytes.len or len > pack_bytes.len - start) return error.InvalidPackIndex;
    return allocator.dupe(u8, pack_bytes[start .. start + len]);
}

test "pack file reads indexed byte range" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "game.fpack",
        .data = "aaabbbbcc",
    });
    const bytes = try readEntry(std.testing.allocator, std.testing.io, tmp.dir, "game.fpack", 3, 4);
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualStrings("bbbb", bytes);
}
