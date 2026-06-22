const std = @import("std");
const kdl = @import("runtime_shared").kdl_bridge;

pub const settings_file_name = "project_settings.kdl";
const max_settings_bytes: usize = 1024 * 16;

pub const TerrainPreviewSettings = struct {
    detail_distance_m: f32 = 2048.0,
    landmark_draw_distance_m: f32 = 8192.0,
    max_resident_cells: u32 = 256,
    max_loads_per_refresh: u32 = 16,
};

pub const ProjectSettings = struct {
    terrain_preview: TerrainPreviewSettings = .{},
};

pub fn defaultSettings() ProjectSettings {
    return .{};
}

pub fn loadInProject(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
) !ProjectSettings {
    var project_dir = try openProjectDir(io, project_path);
    defer project_dir.close(io);
    const bytes = try project_dir.readFileAlloc(io, settings_file_name, allocator, .limited(max_settings_bytes));
    defer allocator.free(bytes);
    return parseBytes(allocator, bytes);
}

pub fn ensureDefaultInProject(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
) !void {
    var project_dir = try openProjectDir(io, project_path);
    defer project_dir.close(io);
    project_dir.access(io, settings_file_name, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            const bytes = try formatBytes(allocator, defaultSettings());
            defer allocator.free(bytes);
            try project_dir.writeFile(io, .{ .sub_path = settings_file_name, .data = bytes });
        },
        else => return err,
    };
}

pub fn parseBytes(allocator: std.mem.Allocator, bytes: []const u8) !ProjectSettings {
    const buffer = try allocator.allocSentinel(u8, bytes.len, 0);
    defer allocator.free(buffer);
    @memcpy(buffer, bytes);

    var parser = kdl.Parser.init(buffer);
    var settings = defaultSettings();
    var seen: TerrainPreviewSeen = .{};
    var depth: i32 = 0;
    var root_seen = false;
    var terrain_seen = false;
    var current_node: ?[]const u8 = null;

    while (true) {
        const event = try parser.next();
        switch (event) {
            .node => |node| {
                if (depth == 0) {
                    if (root_seen or !std.mem.eql(u8, node.val, "project_settings")) return error.InvalidProjectSettings;
                    root_seen = true;
                    current_node = node.val;
                    continue;
                }
                if (depth == 1) {
                    if (!std.mem.eql(u8, node.val, "terrain_preview")) return error.UnknownField;
                    if (terrain_seen) return error.InvalidProjectSettings;
                    terrain_seen = true;
                    current_node = node.val;
                    continue;
                }
                return error.InvalidProjectSettings;
            },
            .prop => |prop| {
                const value = try decodeValue(allocator, prop.val);
                defer allocator.free(value);
                if (depth == 0) {
                    if (!std.mem.eql(u8, prop.key, "version")) return error.UnknownField;
                    const version = try std.fmt.parseInt(u32, value, 10);
                    if (version != 1) return error.UnsupportedProjectSettingsVersion;
                    continue;
                }
                if (depth == 1 and std.mem.eql(u8, current_node orelse "", "terrain_preview")) {
                    try applyTerrainPreviewProp(&settings.terrain_preview, &seen, prop.key, value);
                    continue;
                }
                return error.InvalidProjectSettings;
            },
            .child_block_begin => depth += 1,
            .child_block_end => {
                depth -= 1;
                if (depth < 0) return error.InvalidProjectSettings;
                current_node = null;
            },
            .arg, .invalid => return error.InvalidProjectSettings,
            .eof => break,
        }
    }

    if (!root_seen or !terrain_seen or depth != 0) return error.InvalidProjectSettings;
    if (!seen.complete()) return error.InvalidProjectSettings;
    try validate(settings);
    return settings;
}

pub fn formatBytes(allocator: std.mem.Allocator, settings: ProjectSettings) ![]u8 {
    try validate(settings);
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    const writer = &out.writer;
    try writer.writeAll("project_settings version=1 {\n");
    try writer.print(
        "  terrain_preview detail_distance_m={d:.0} landmark_draw_distance_m={d:.0} max_resident_cells={d} max_loads_per_refresh={d}\n",
        .{
            settings.terrain_preview.detail_distance_m,
            settings.terrain_preview.landmark_draw_distance_m,
            settings.terrain_preview.max_resident_cells,
            settings.terrain_preview.max_loads_per_refresh,
        },
    );
    try writer.writeAll("}\n");
    return out.toOwnedSlice();
}

const TerrainPreviewSeen = struct {
    detail_distance_m: bool = false,
    landmark_draw_distance_m: bool = false,
    max_resident_cells: bool = false,
    max_loads_per_refresh: bool = false,

    fn complete(self: TerrainPreviewSeen) bool {
        return self.detail_distance_m and self.landmark_draw_distance_m and self.max_resident_cells and self.max_loads_per_refresh;
    }
};

fn applyTerrainPreviewProp(settings: *TerrainPreviewSettings, seen: *TerrainPreviewSeen, key: []const u8, value: []const u8) !void {
    if (std.mem.eql(u8, key, "detail_distance_m")) {
        if (seen.detail_distance_m) return error.InvalidProjectSettings;
        seen.detail_distance_m = true;
        settings.detail_distance_m = try parsePositiveF32(value);
    } else if (std.mem.eql(u8, key, "landmark_draw_distance_m")) {
        if (seen.landmark_draw_distance_m) return error.InvalidProjectSettings;
        seen.landmark_draw_distance_m = true;
        settings.landmark_draw_distance_m = try parsePositiveF32(value);
    } else if (std.mem.eql(u8, key, "max_resident_cells")) {
        if (seen.max_resident_cells) return error.InvalidProjectSettings;
        seen.max_resident_cells = true;
        settings.max_resident_cells = try parsePositiveU32(value);
    } else if (std.mem.eql(u8, key, "max_loads_per_refresh")) {
        if (seen.max_loads_per_refresh) return error.InvalidProjectSettings;
        seen.max_loads_per_refresh = true;
        settings.max_loads_per_refresh = try parsePositiveU32(value);
    } else {
        return error.UnknownField;
    }
}

fn parsePositiveF32(value: []const u8) !f32 {
    const parsed = try std.fmt.parseFloat(f32, value);
    if (!std.math.isFinite(parsed) or parsed <= 0.0) return error.InvalidProjectSettings;
    return parsed;
}

fn parsePositiveU32(value: []const u8) !u32 {
    const parsed = try std.fmt.parseInt(u32, value, 10);
    if (parsed == 0) return error.InvalidProjectSettings;
    return parsed;
}

fn validate(settings: ProjectSettings) !void {
    const terrain = settings.terrain_preview;
    if (!std.math.isFinite(terrain.detail_distance_m) or terrain.detail_distance_m <= 0.0) return error.InvalidProjectSettings;
    if (!std.math.isFinite(terrain.landmark_draw_distance_m) or terrain.landmark_draw_distance_m <= 0.0) return error.InvalidProjectSettings;
    if (terrain.max_resident_cells == 0) return error.InvalidProjectSettings;
    if (terrain.max_loads_per_refresh == 0) return error.InvalidProjectSettings;
}

fn openProjectDir(io: std.Io, project_path: []const u8) !std.Io.Dir {
    if (std.fs.path.isAbsolute(project_path)) {
        return try std.Io.Dir.openDirAbsolute(io, project_path, .{});
    }
    return try std.Io.Dir.cwd().openDir(io, project_path, .{});
}

fn decodeValue(allocator: std.mem.Allocator, raw: []const u8) ![]const u8 {
    return kdl.string_utils.makeRealString(allocator, raw);
}

test "project settings parser reads terrain preview budget" {
    const bytes =
        \\project_settings version=1 {
        \\  terrain_preview detail_distance_m=1536 landmark_draw_distance_m=12000 max_resident_cells=144 max_loads_per_refresh=12
        \\}
    ;
    const settings = try parseBytes(std.testing.allocator, bytes);
    try std.testing.expectApproxEqAbs(@as(f32, 1536), settings.terrain_preview.detail_distance_m, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 12000), settings.terrain_preview.landmark_draw_distance_m, 0.001);
    try std.testing.expectEqual(@as(u32, 144), settings.terrain_preview.max_resident_cells);
    try std.testing.expectEqual(@as(u32, 12), settings.terrain_preview.max_loads_per_refresh);
}

test "project settings formatter preserves terrain preview budget" {
    const bytes = try formatBytes(std.testing.allocator, .{
        .terrain_preview = .{
            .detail_distance_m = 1536,
            .landmark_draw_distance_m = 12000,
            .max_resident_cells = 144,
            .max_loads_per_refresh = 12,
        },
    });
    defer std.testing.allocator.free(bytes);

    const parsed = try parseBytes(std.testing.allocator, bytes);
    try std.testing.expectApproxEqAbs(@as(f32, 1536), parsed.terrain_preview.detail_distance_m, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 12000), parsed.terrain_preview.landmark_draw_distance_m, 0.001);
    try std.testing.expectEqual(@as(u32, 144), parsed.terrain_preview.max_resident_cells);
    try std.testing.expectEqual(@as(u32, 12), parsed.terrain_preview.max_loads_per_refresh);
}

test "project settings parser rejects invalid terrain preview budget" {
    const bytes =
        \\project_settings version=1 {
        \\  terrain_preview detail_distance_m=0
        \\}
    ;
    try std.testing.expectError(error.InvalidProjectSettings, parseBytes(std.testing.allocator, bytes));
}
