const std = @import("std");
const kdl = @import("kdl");
const layer_kdl = @import("../layer_kdl.zig");
const types = @import("types.zig");

pub const water_layer_file = "layers/water.kdl";

pub fn loadProject(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    manifest_path: []const u8,
) !types.WaterDoc {
    const path = try layerPath(allocator, manifest_path);
    defer allocator.free(path);
    var project_dir = try openProjectDir(io, project_path);
    defer project_dir.close(io);
    const bytes = project_dir.readFileAlloc(io, path, allocator, .limited(1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return .{},
        else => return err,
    };
    defer allocator.free(bytes);
    return parseWaterKdl(allocator, bytes);
}

pub fn parseWaterKdl(allocator: std.mem.Allocator, bytes: []const u8) !types.WaterDoc {
    const buffer = try allocator.allocSentinel(u8, bytes.len, 0);
    defer allocator.free(buffer);
    @memcpy(buffer, bytes);

    var parser = kdl.Parser.init(buffer);
    var volumes = std.ArrayList(types.WaterVolume).empty;
    errdefer {
        for (volumes.items) |*volume| volume.deinit(allocator);
        volumes.deinit(allocator);
    }
    var doc = types.WaterDoc{};
    var root_seen = false;
    var depth: i32 = 0;
    var current: ?types.WaterVolume = null;

    while (true) {
        const event = try parser.next();
        switch (event) {
            .node => |node| {
                if (depth == 0) {
                    if (root_seen or !std.mem.eql(u8, node.val, "water")) return error.InvalidWaterDocument;
                    root_seen = true;
                    continue;
                }
                if (depth == 1) {
                    if (!std.mem.eql(u8, node.val, "volume")) return error.InvalidWaterDocument;
                    if (current != null) try finishVolume(allocator, &current, &volumes);
                    current = .{
                        .id = try allocator.dupe(u8, ""),
                        .material = try allocator.dupe(u8, ""),
                        .surface_y = 0,
                        .bottom_y = -1,
                        .points = &.{},
                    };
                    continue;
                }
                return error.InvalidWaterDocument;
            },
            .prop => |prop| {
                const value = try layer_kdl.decodeValue(allocator, prop.val);
                defer allocator.free(value);
                if (depth == 0) {
                    if (std.mem.eql(u8, prop.key, "version")) {
                        doc.schema_version = try std.fmt.parseInt(u32, value, 10);
                    } else return error.UnknownField;
                } else if (depth == 1) {
                    try applyVolumeProp(allocator, &(current orelse return error.InvalidWaterDocument), prop.key, value);
                } else return error.InvalidWaterDocument;
            },
            .child_block_begin => depth += 1,
            .child_block_end => {
                if (depth == 1) {
                    if (current != null) try finishVolume(allocator, &current, &volumes);
                }
                depth -= 1;
                if (depth < 0) return error.InvalidWaterDocument;
            },
            .arg, .invalid => return error.InvalidWaterDocument,
            .eof => break,
        }
    }
    if (!root_seen or depth != 0 or current != null) return error.InvalidWaterDocument;
    doc.volumes = try volumes.toOwnedSlice(allocator);
    try types.validateDoc(doc);
    return doc;
}

fn finishVolume(allocator: std.mem.Allocator, volume: *?types.WaterVolume, volumes: *std.ArrayList(types.WaterVolume)) !void {
    var finished = volume.* orelse return error.InvalidWaterDocument;
    if (finished.material.len == 0) {
        allocator.free(finished.material);
        finished.material = try allocator.dupe(u8, types.defaultMaterial(finished.kind));
    }
    try types.validateVolume(finished);
    try volumes.append(allocator, finished);
    volume.* = null;
}

fn applyVolumeProp(allocator: std.mem.Allocator, volume: *types.WaterVolume, key: []const u8, value: []const u8) !void {
    if (std.mem.eql(u8, key, "id")) {
        allocator.free(volume.id);
        volume.id = try allocator.dupe(u8, value);
    } else if (std.mem.eql(u8, key, "kind")) {
        volume.kind = types.kindFromName(value) orelse return error.InvalidWaterVolume;
    } else if (std.mem.eql(u8, key, "material")) {
        allocator.free(volume.material);
        volume.material = try allocator.dupe(u8, value);
    } else if (std.mem.eql(u8, key, "surface_y")) {
        volume.surface_y = try std.fmt.parseFloat(f32, value);
    } else if (std.mem.eql(u8, key, "bottom_y")) {
        volume.bottom_y = try std.fmt.parseFloat(f32, value);
    } else if (std.mem.eql(u8, key, "swimmable")) {
        volume.swimmable = std.mem.eql(u8, value, "true");
    } else if (std.mem.eql(u8, key, "linked_to_ocean")) {
        volume.linked_to_ocean = std.mem.eql(u8, value, "true");
    } else if (std.mem.eql(u8, key, "current")) {
        const current = try layer_kdl.parseF32Triple(value);
        volume.current = .{ .x = current[0], .y = current[1], .z = current[2] };
    } else if (std.mem.eql(u8, key, "points")) {
        if (volume.points.len > 0) allocator.free(volume.points);
        volume.points = try parsePoints(allocator, value);
    } else return error.UnknownField;
}

pub fn parsePoints(allocator: std.mem.Allocator, text: []const u8) ![][2]f32 {
    const rows = try layer_kdl.parsePoint2List(allocator, text);
    defer layer_kdl.freeNestedF32(allocator, rows);
    var points = try allocator.alloc([2]f32, rows.len);
    for (rows, 0..) |row, index| points[index] = .{ row[0], row[1] };
    return points;
}

pub fn layerPath(allocator: std.mem.Allocator, manifest_path: []const u8) ![]u8 {
    const dir = std.fs.path.dirname(manifest_path) orelse "";
    if (dir.len == 0) return allocator.dupe(u8, water_layer_file);
    return std.fs.path.join(allocator, &.{ dir, water_layer_file });
}

fn openProjectDir(io: std.Io, project_path: []const u8) !std.Io.Dir {
    if (std.fs.path.isAbsolute(project_path)) return std.Io.Dir.openDirAbsolute(io, project_path, .{});
    return std.Io.Dir.cwd().openDir(io, project_path, .{});
}

test "parse water kdl supports sibling volumes" {
    const bytes =
        \\water version=1 {
        \\  volume id="pond" kind="pond" material="water.pond.clear" surface_y=12 bottom_y=3 swimmable=true linked_to_ocean=false current="0,0,0" points="0,0; 8,0; 8,8; 0,8"
        \\  volume id="lake" kind="lake" material="water.lake.clear" surface_y=2 bottom_y=-4 swimmable=true linked_to_ocean=false current="0,0,0" points="16,0; 24,0; 24,8; 16,8"
        \\}
        \\
    ;
    var doc = try parseWaterKdl(std.testing.allocator, bytes);
    defer doc.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), doc.volumes.len);
    try std.testing.expectEqualStrings("pond", doc.volumes[0].id);
    try std.testing.expectEqualStrings("lake", doc.volumes[1].id);
}

test "parse water kdl round trip fields" {
    const bytes =
        \\water version=1 {
        \\  volume id="pond" kind="pond" material="water.pond.clear" surface_y=12 bottom_y=3 swimmable=true linked_to_ocean=false current="0,0,0" points="0,0; 8,0; 8,8; 0,8"
        \\}
        \\
    ;
    var doc = try parseWaterKdl(std.testing.allocator, bytes);
    defer doc.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), doc.volumes.len);
    try std.testing.expectEqual(types.WaterKind.pond, doc.volumes[0].kind);
    try std.testing.expectEqual(@as(f32, 12), doc.volumes[0].surface_y);
}
