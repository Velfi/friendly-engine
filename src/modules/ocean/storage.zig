const std = @import("std");
const kdl = @import("kdl");
const layer_kdl = @import("../layer_kdl.zig");
const types = @import("types.zig");

const ocean_layer_file = "layers/ocean.kdl";

pub const OwnedOceanDoc = struct {
    value: types.OceanDoc,

    pub fn deinit(_: *OwnedOceanDoc) void {}
};

pub fn loadProject(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    manifest_path: []const u8,
) !OwnedOceanDoc {
    const path = try layerPath(allocator, manifest_path);
    defer allocator.free(path);
    var project_dir = try openProjectDir(io, project_path);
    defer project_dir.close(io);
    const bytes = project_dir.readFileAlloc(io, path, allocator, .limited(1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return .{ .value = types.defaultDoc() },
        else => return err,
    };
    defer allocator.free(bytes);
    return parseOceanKdl(allocator, bytes);
}

pub fn parseOceanKdl(allocator: std.mem.Allocator, bytes: []const u8) !OwnedOceanDoc {
    const buffer = try allocator.allocSentinel(u8, bytes.len, 0);
    defer allocator.free(buffer);
    @memcpy(buffer, bytes);

    var parser = kdl.Parser.init(buffer);
    var doc = types.defaultDoc();
    var depth: i32 = 0;
    var root_seen = false;
    var section: ?enum { wind, waves } = null;

    while (true) {
        const event = try parser.next();
        switch (event) {
            .node => |node| {
                if (depth == 0) {
                    if (root_seen or !std.mem.eql(u8, node.val, "ocean")) return error.InvalidOceanDocument;
                    root_seen = true;
                    continue;
                }
                if (depth == 1) {
                    section = null;
                    if (std.mem.eql(u8, node.val, "wind")) {
                        section = .wind;
                        continue;
                    }
                    if (std.mem.eql(u8, node.val, "waves")) {
                        section = .waves;
                        continue;
                    }
                    return error.UnknownField;
                }
                return error.InvalidOceanDocument;
            },
            .prop => |prop| {
                const value = try layer_kdl.decodeValue(allocator, prop.val);
                defer allocator.free(value);
                if (depth == 0) {
                    if (std.mem.eql(u8, prop.key, "version")) {
                        doc.schema_version = try std.fmt.parseInt(u32, value, 10);
                    } else return error.UnknownField;
                } else if (depth == 1) {
                    switch (section orelse return error.InvalidOceanDocument) {
                        .wind => try applyWindProp(&doc.wind, prop.key, value),
                        .waves => try applyWaveProp(&doc, prop.key, value),
                    }
                } else return error.InvalidOceanDocument;
            },
            .child_block_begin => depth += 1,
            .child_block_end => {
                if (depth == 1) section = null;
                depth -= 1;
                if (depth < 0) return error.InvalidOceanDocument;
            },
            .arg, .invalid => return error.InvalidOceanDocument,
            .eof => break,
        }
    }
    if (!root_seen or depth != 0) return error.InvalidOceanDocument;
    try types.validateDoc(doc);
    return .{ .value = doc };
}

fn applyWindProp(wind: *types.WindSettings, key: []const u8, value: []const u8) !void {
    if (std.mem.eql(u8, key, "enabled")) {
        wind.enabled = std.mem.eql(u8, value, "true");
    } else if (std.mem.eql(u8, key, "direction_deg")) {
        wind.direction_deg = try std.fmt.parseFloat(f32, value);
    } else if (std.mem.eql(u8, key, "speed_mps")) {
        wind.speed_mps = try std.fmt.parseFloat(f32, value);
    } else return error.UnknownField;
}

fn applyWaveProp(doc: *types.OceanDoc, key: []const u8, value: []const u8) !void {
    if (std.mem.eql(u8, key, "enabled")) {
        doc.enabled = std.mem.eql(u8, value, "true");
        doc.waves.enabled = doc.enabled;
    } else if (std.mem.eql(u8, key, "sea_level_m")) {
        doc.sea_level_m = try std.fmt.parseFloat(f32, value);
    } else if (std.mem.eql(u8, key, "render_min_distance_m")) {
        doc.render_min_distance_m = try std.fmt.parseFloat(f32, value);
    } else if (std.mem.eql(u8, key, "fade_in_start_m")) {
        doc.fade_in_start_m = try std.fmt.parseFloat(f32, value);
    } else if (std.mem.eql(u8, key, "fade_in_end_m")) {
        doc.fade_in_end_m = try std.fmt.parseFloat(f32, value);
    } else if (std.mem.eql(u8, key, "amplitude_m")) {
        doc.waves.amplitude_m = try std.fmt.parseFloat(f32, value);
    } else if (std.mem.eql(u8, key, "length_m")) {
        doc.waves.length_m = try std.fmt.parseFloat(f32, value);
    } else if (std.mem.eql(u8, key, "speed_mps")) {
        doc.waves.speed_mps = try std.fmt.parseFloat(f32, value);
    } else return error.UnknownField;
}

pub fn layerPath(allocator: std.mem.Allocator, manifest_path: []const u8) ![]u8 {
    const dir = std.fs.path.dirname(manifest_path) orelse "";
    if (dir.len == 0) return allocator.dupe(u8, ocean_layer_file);
    return std.fs.path.join(allocator, &.{ dir, ocean_layer_file });
}

fn openProjectDir(io: std.Io, project_path: []const u8) !std.Io.Dir {
    if (std.fs.path.isAbsolute(project_path)) return std.Io.Dir.openDirAbsolute(io, project_path, .{});
    return std.Io.Dir.cwd().openDir(io, project_path, .{});
}

test "parse ocean kdl round trip fields" {
    const bytes =
        \\ocean version=1 {
        \\  wind enabled=true direction_deg=210 speed_mps=9
        \\  waves enabled=false sea_level_m=0 render_min_distance_m=1800 fade_in_start_m=1400 fade_in_end_m=2600 amplitude_m=0.5 length_m=38 speed_mps=4
        \\}
        \\
    ;
    var doc = try parseOceanKdl(std.testing.allocator, bytes);
    defer doc.deinit();
    try std.testing.expect(!doc.value.enabled);
    try std.testing.expectEqual(@as(f32, 210), doc.value.wind.direction_deg);
    try std.testing.expectEqual(@as(f32, 0.5), doc.value.waves.amplitude_m);
}
