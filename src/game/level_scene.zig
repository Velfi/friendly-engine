const std = @import("std");

pub fn sceneSummary(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    scene_rel_path: []const u8,
) ![]u8 {
    _ = project_path;

    const scene_dir_part = std.fs.path.dirname(scene_rel_path) orelse return error.InvalidScenePath;
    const scene_file_part = std.fs.path.basename(scene_rel_path);

    var scenes_dir = try std.Io.Dir.cwd().openDir(io, scene_dir_part, .{});
    defer scenes_dir.close(io);

    const bytes = try scenes_dir.readFileAlloc(io, scene_file_part, allocator, .limited(1024 * 1024));
    defer allocator.free(bytes);

    var count: usize = 0;
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (std.mem.startsWith(u8, trimmed, "entity ")) count += 1;
    }

    return try std.fmt.allocPrint(allocator, "{d} objects", .{count});
}

test "level scene summary counts objects" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, "scenes");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "scenes/main.kdl",
        .data =
        \\scene version=1 next_object_id=3 {
        \\  entity id=1 name="A" {}
        \\  entity id=2 name="B" {}
        \\}
        \\
        ,
    });

    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);

    const summary = try sceneSummary(std.testing.allocator, std.testing.io, project_path, "scenes/main.kdl");
    defer std.testing.allocator.free(summary);
    try std.testing.expectEqualStrings("2 objects", summary);
}
