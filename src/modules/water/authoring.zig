const std = @import("std");
const types = @import("types.zig");
const storage = @import("storage.zig");

pub const loadProject = storage.loadProject;

pub fn saveProject(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    manifest_path: []const u8,
    doc: types.WaterDoc,
) !void {
    try types.validateDoc(doc);
    const path = try storage.layerPath(allocator, manifest_path);
    defer allocator.free(path);
    var project_dir = try openProjectDir(io, project_path);
    defer project_dir.close(io);
    if (std.fs.path.dirname(path)) |parent| try project_dir.createDirPath(io, parent);
    const bytes = try formatKdl(allocator, doc);
    defer allocator.free(bytes);
    try project_dir.writeFile(io, .{ .sub_path = path, .data = bytes });
}

pub fn formatKdl(allocator: std.mem.Allocator, doc: types.WaterDoc) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    const writer = &out.writer;
    try writer.print("water version={d} {{\n", .{types.schema_version});
    for (doc.volumes) |volume| {
        try writer.print(
            "  volume id=\"{s}\" kind=\"{s}\" material=\"{s}\" surface_y={d} bottom_y={d} swimmable={any} linked_to_ocean={any} current=\"{d},{d},{d}\" points=\"",
            .{
                volume.id,
                volume.kind.label(),
                volume.material,
                volume.surface_y,
                volume.bottom_y,
                volume.swimmable,
                volume.linked_to_ocean,
                volume.current.x,
                volume.current.y,
                volume.current.z,
            },
        );
        for (volume.points, 0..) |point, index| {
            if (index > 0) try writer.writeAll("; ");
            try writer.print("{d},{d}", .{ point[0], point[1] });
        }
        try writer.writeAll("\"\n");
    }
    try writer.writeAll("}\n");
    return out.toOwnedSlice();
}

fn openProjectDir(io: std.Io, project_path: []const u8) !std.Io.Dir {
    if (std.fs.path.isAbsolute(project_path)) return std.Io.Dir.openDirAbsolute(io, project_path, .{});
    return std.Io.Dir.cwd().openDir(io, project_path, .{});
}

test "format water kdl writes volume points" {
    const volume = types.WaterVolume{
        .id = @constCast("lake"),
        .kind = .lake,
        .material = @constCast("water.lake.clear"),
        .surface_y = 20,
        .bottom_y = 5,
        .points = @constCast(&[_][2]f32{ .{ 0, 0 }, .{ 4, 0 }, .{ 4, 4 } }),
    };
    const bytes = try formatKdl(std.testing.allocator, .{ .volumes = @constCast(&[_]types.WaterVolume{volume}) });
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "volume id=\"lake\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "points=\"0,0; 4,0; 4,4\"") != null);
}
