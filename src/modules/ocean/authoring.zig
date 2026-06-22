const std = @import("std");
const types = @import("types.zig");
const storage = @import("storage.zig");

pub fn loadProject(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    manifest_path: []const u8,
) !types.OceanDoc {
    var owned = try storage.loadProject(allocator, io, project_path, manifest_path);
    defer owned.deinit();
    return owned.value;
}

pub fn saveProject(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    manifest_path: []const u8,
    doc: types.OceanDoc,
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

pub fn formatKdl(allocator: std.mem.Allocator, doc: types.OceanDoc) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    const writer = &out.writer;
    try writer.print(
        "ocean version=1 {{\n  wind enabled={any} direction_deg={d} speed_mps={d}\n  waves enabled={any} sea_level_m={d} render_min_distance_m={d} fade_in_start_m={d} fade_in_end_m={d} amplitude_m={d} length_m={d} speed_mps={d}\n}}\n",
        .{
            doc.wind.enabled,
            doc.wind.direction_deg,
            doc.wind.speed_mps,
            doc.enabled,
            doc.sea_level_m,
            doc.render_min_distance_m,
            doc.fade_in_start_m,
            doc.fade_in_end_m,
            doc.waves.amplitude_m,
            doc.waves.length_m,
            doc.waves.speed_mps,
        },
    );
    return out.toOwnedSlice();
}

fn openProjectDir(io: std.Io, project_path: []const u8) !std.Io.Dir {
    if (std.fs.path.isAbsolute(project_path)) return std.Io.Dir.openDirAbsolute(io, project_path, .{});
    return std.Io.Dir.cwd().openDir(io, project_path, .{});
}

test "format ocean kdl writes wind and waves" {
    var doc = types.defaultDoc();
    doc.enabled = false;
    doc.wind.speed_mps = 12;
    const bytes = try formatKdl(std.testing.allocator, doc);
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "wind enabled=true") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "waves enabled=false") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "speed_mps=12") != null);
}
