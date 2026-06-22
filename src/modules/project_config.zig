const std = @import("std");
const kdl = @import("kdl");

const max_project_config_bytes: usize = 1024 * 64;
const default_startup_scene = "scenes/main.kdl";
const default_startup_bundle = "assets/bundles/client-debug/bundle.json";

pub const SceneEntry = struct {
    path: []const u8,
    world: []const u8,

    pub fn deinit(self: *SceneEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        allocator.free(self.world);
        self.* = .{ .path = &.{}, .world = &.{} };
    }
};

pub const OwnedProjectConfig = struct {
    allocator: std.mem.Allocator,
    enabled_modules: [][]u8,
    scenes: []SceneEntry,
    startup_scene: []u8,
    startup_bundle: []u8,

    pub fn deinit(self: *OwnedProjectConfig) void {
        for (self.enabled_modules) |module_name| {
            self.allocator.free(module_name);
        }
        self.allocator.free(self.enabled_modules);
        self.enabled_modules = &.{};
        for (self.scenes) |*scene| scene.deinit(self.allocator);
        self.allocator.free(self.scenes);
        self.scenes = &.{};
        self.allocator.free(self.startup_scene);
        self.startup_scene = &.{};
        self.allocator.free(self.startup_bundle);
        self.startup_bundle = &.{};
    }

    pub fn enabledModules(self: *const OwnedProjectConfig) []const []const u8 {
        return self.enabled_modules;
    }

    pub fn sceneEntries(self: *const OwnedProjectConfig) []const SceneEntry {
        return self.scenes;
    }

    pub fn startupScene(self: *const OwnedProjectConfig) []const u8 {
        return self.startup_scene;
    }

    pub fn startupBundle(self: *const OwnedProjectConfig) []const u8 {
        return self.startup_bundle;
    }

    pub fn worldForScene(self: *const OwnedProjectConfig, scene_path: []const u8) ![]const u8 {
        for (self.scenes) |entry| {
            if (std.mem.eql(u8, entry.path, scene_path)) return entry.world;
        }
        return error.SceneWorldNotConfigured;
    }

    pub fn hasStartupBundle(self: *const OwnedProjectConfig) bool {
        return self.startup_bundle.len > 0;
    }
};

pub fn defaultProjectConfig(allocator: std.mem.Allocator, default_module_names: []const []const u8) !OwnedProjectConfig {
    var enabled_modules = try allocator.alloc([]u8, default_module_names.len);
    var i: usize = 0;
    errdefer {
        while (i > 0) {
            i -= 1;
            allocator.free(enabled_modules[i]);
        }
        allocator.free(enabled_modules);
    }

    for (default_module_names) |module_name| {
        enabled_modules[i] = try allocator.dupe(u8, module_name);
        i += 1;
    }
    var scenes = try allocator.alloc(SceneEntry, 1);
    errdefer allocator.free(scenes);
    scenes[0] = .{
        .path = try allocator.dupe(u8, default_startup_scene),
        .world = try allocator.dupe(u8, "world.kdl"),
    };
    return .{
        .allocator = allocator,
        .enabled_modules = enabled_modules,
        .scenes = scenes,
        .startup_scene = try allocator.dupe(u8, default_startup_scene),
        .startup_bundle = try allocator.dupe(u8, default_startup_bundle),
    };
}

const SceneBuilder = struct {
    path: ?[]u8 = null,
    world: ?[]u8 = null,

    fn deinit(self: *SceneBuilder, allocator: std.mem.Allocator) void {
        if (self.path) |path| allocator.free(path);
        if (self.world) |world| allocator.free(world);
        self.* = .{};
    }

    fn finish(self: *SceneBuilder) !SceneEntry {
        const path = self.path orelse return error.InvalidProjectConfig;
        const world = self.world orelse return error.InvalidProjectConfig;
        if (path.len == 0 or world.len == 0) return error.InvalidProjectConfig;
        self.path = null;
        self.world = null;
        return .{ .path = path, .world = world };
    }
};

pub fn parseProjectConfigBytes(allocator: std.mem.Allocator, bytes: []const u8) !OwnedProjectConfig {
    const buffer = try allocator.allocSentinel(u8, bytes.len, 0);
    defer allocator.free(buffer);
    @memcpy(buffer, bytes);

    var parser = kdl.Parser.init(buffer);
    var enabled_modules = std.ArrayList([]u8).empty;
    errdefer {
        for (enabled_modules.items) |module_name| {
            allocator.free(module_name);
        }
        enabled_modules.deinit(allocator);
    }
    var scenes = std.ArrayList(SceneEntry).empty;
    errdefer {
        for (scenes.items) |*scene| scene.deinit(allocator);
        scenes.deinit(allocator);
    }

    var startup_scene: ?[]u8 = null;
    errdefer if (startup_scene) |value| allocator.free(value);
    var startup_bundle: ?[]u8 = null;
    errdefer if (startup_bundle) |value| allocator.free(value);

    var depth: i32 = 0;
    var root_seen = false;
    var current_node: ?[]const u8 = null;
    var pending_scene: ?SceneBuilder = null;
    errdefer if (pending_scene) |*scene| scene.deinit(allocator);

    while (true) {
        const event = try parser.next();
        switch (event) {
            .node => |node| {
                if (depth == 0) {
                    if (root_seen or !std.mem.eql(u8, node.val, "engine")) return error.InvalidProjectConfig;
                    root_seen = true;
                    current_node = node.val;
                    continue;
                }
                if (depth == 1) {
                    if (std.mem.eql(u8, node.val, "scene")) {
                        if (pending_scene) |*scene| {
                            try scenes.append(allocator, try scene.finish());
                        }
                        pending_scene = .{};
                    } else if (!std.mem.eql(u8, node.val, "module")) return error.UnknownField;
                    current_node = node.val;
                    continue;
                }
                return error.InvalidProjectConfig;
            },
            .prop => |prop| {
                const value = try decodeValue(allocator, prop.val);
                defer allocator.free(value);
                if (depth == 0) {
                    if (std.mem.eql(u8, prop.key, "startup_scene")) {
                        if (startup_scene) |existing| allocator.free(existing);
                        startup_scene = try allocator.dupe(u8, value);
                    } else if (std.mem.eql(u8, prop.key, "startup_bundle")) {
                        if (startup_bundle) |existing| allocator.free(existing);
                        startup_bundle = try allocator.dupe(u8, value);
                    } else {
                        return error.UnknownField;
                    }
                    continue;
                }
                if (depth == 1 and std.mem.eql(u8, current_node orelse "", "module")) {
                    if (!std.mem.eql(u8, prop.key, "name")) return error.UnknownField;
                    try enabled_modules.append(allocator, try allocator.dupe(u8, value));
                    continue;
                }
                if (depth == 1 and std.mem.eql(u8, current_node orelse "", "scene")) {
                    var scene = &(pending_scene orelse return error.InvalidProjectConfig);
                    if (std.mem.eql(u8, prop.key, "path")) {
                        if (scene.path) |existing| allocator.free(existing);
                        scene.path = try allocator.dupe(u8, value);
                    } else if (std.mem.eql(u8, prop.key, "world")) {
                        if (scene.world) |existing| allocator.free(existing);
                        scene.world = try allocator.dupe(u8, value);
                    } else {
                        return error.UnknownField;
                    }
                    continue;
                }
                return error.InvalidProjectConfig;
            },
            .child_block_begin => depth += 1,
            .child_block_end => {
                depth -= 1;
                if (depth < 0) return error.InvalidProjectConfig;
                current_node = null;
            },
            .arg, .invalid => return error.InvalidProjectConfig,
            .eof => break,
        }
    }

    if (!root_seen or depth != 0) return error.InvalidProjectConfig;
    if (pending_scene) |*scene| {
        try scenes.append(allocator, try scene.finish());
        pending_scene = null;
    }
    const final_startup_scene = startup_scene orelse try allocator.dupe(u8, default_startup_scene);
    startup_scene = null;
    errdefer allocator.free(final_startup_scene);

    for (scenes.items, 0..) |entry, index| {
        for (scenes.items[0..index]) |previous| {
            if (std.mem.eql(u8, previous.path, entry.path)) return error.DuplicateSceneConfig;
        }
    }
    var startup_scene_configured = false;
    for (scenes.items) |entry| {
        if (std.mem.eql(u8, entry.path, final_startup_scene)) {
            startup_scene_configured = true;
            break;
        }
    }
    if (!startup_scene_configured) return error.SceneWorldNotConfigured;

    return .{
        .allocator = allocator,
        .enabled_modules = try enabled_modules.toOwnedSlice(allocator),
        .scenes = try scenes.toOwnedSlice(allocator),
        .startup_scene = final_startup_scene,
        .startup_bundle = startup_bundle orelse try allocator.dupe(u8, default_startup_bundle),
    };
}

pub fn formatProjectConfig(
    allocator: std.mem.Allocator,
    enabled_modules: []const []const u8,
    startup_scene: []const u8,
    startup_bundle: []const u8,
    scenes: []const SceneEntry,
) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    const writer = &out.writer;

    try writer.print(
        "engine startup_scene=\"{s}\" startup_bundle=\"{s}\" {{\n",
        .{ startup_scene, startup_bundle },
    );
    for (enabled_modules) |module_name| {
        try writer.print("  module name=\"{s}\"\n", .{module_name});
    }
    for (scenes) |scene| {
        try writer.print("  scene path=\"{s}\" world=\"{s}\"\n", .{ scene.path, scene.world });
    }
    try writer.writeAll("}\n");
    return out.toOwnedSlice();
}

pub fn loadProjectConfig(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !OwnedProjectConfig {
    const bytes = try readConfigBytes(allocator, io, path);
    defer allocator.free(bytes);
    return parseProjectConfigBytes(allocator, bytes);
}

pub fn loadProjectConfigInProject(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    config_rel_path: []const u8,
) !OwnedProjectConfig {
    var project_dir = try openProjectDir(io, project_path);
    defer project_dir.close(io);

    const bytes = try project_dir.readFileAlloc(
        io,
        config_rel_path,
        allocator,
        .limited(max_project_config_bytes),
    );
    defer allocator.free(bytes);
    return parseProjectConfigBytes(allocator, bytes);
}

fn readConfigBytes(allocator: std.mem.Allocator, io: std.Io, path: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(path)) {
        const dir_path = std.fs.path.dirname(path) orelse return error.InvalidProjectConfigPath;
        const file_name = std.fs.path.basename(path);
        var dir = try std.Io.Dir.openDirAbsolute(io, dir_path, .{});
        defer dir.close(io);
        return try dir.readFileAlloc(io, file_name, allocator, .limited(max_project_config_bytes));
    }

    return try std.Io.Dir.cwd().readFileAlloc(
        io,
        path,
        allocator,
        .limited(max_project_config_bytes),
    );
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

test "project config parser extracts enabled modules" {
    const bytes =
        \\engine {
        \\  module name="gem.core_ui"
        \\  module name="gem.physics3d"
        \\  scene path="scenes/main.kdl" world="world.kdl"
        \\}
    ;
    var config = try parseProjectConfigBytes(std.testing.allocator, bytes);
    defer config.deinit();

    try std.testing.expectEqual(@as(usize, 2), config.enabledModules().len);
    try std.testing.expectEqualStrings("gem.core_ui", config.enabledModules()[0]);
    try std.testing.expectEqualStrings("gem.physics3d", config.enabledModules()[1]);
    try std.testing.expectEqualStrings("world.kdl", try config.worldForScene("scenes/main.kdl"));
}

test "project config parser reads scene worlds" {
    const bytes =
        \\engine startup_scene="scenes/menu.kdl" {
        \\  scene path="scenes/menu.kdl" world="worlds/menu.kdl"
        \\  scene path="scenes/game.kdl" world="worlds/game.kdl"
        \\}
    ;
    var config = try parseProjectConfigBytes(std.testing.allocator, bytes);
    defer config.deinit();

    try std.testing.expectEqualStrings("scenes/menu.kdl", config.startupScene());
    try std.testing.expectEqualStrings("worlds/menu.kdl", try config.worldForScene(config.startupScene()));
    try std.testing.expectEqualStrings("worlds/game.kdl", try config.worldForScene("scenes/game.kdl"));
}

test "project config parser rejects unknown fields" {
    const bytes =
        \\engine startup_woorld="typo.kdl" {
        \\  scene path="scenes/main.kdl" world="world.kdl"
        \\}
    ;
    try std.testing.expectError(
        error.UnknownField,
        parseProjectConfigBytes(std.testing.allocator, bytes),
    );
}

test "project config parser requires startup scene world" {
    const bytes =
        \\engine startup_scene="scenes/missing.kdl" {
        \\  scene path="scenes/main.kdl" world="world.kdl"
        \\}
    ;
    try std.testing.expectError(
        error.SceneWorldNotConfigured,
        parseProjectConfigBytes(std.testing.allocator, bytes),
    );
}

test "project config loads from explicit project path" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "engine.kdl",
        .data =
        \\engine startup_scene="scenes/main.kdl" {
        \\  scene path="scenes/main.kdl" world="world.kdl"
        \\}
        \\
        ,
    });

    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);

    var config = try loadProjectConfigInProject(
        std.testing.allocator,
        std.testing.io,
        project_path,
        "engine.kdl",
    );
    defer config.deinit();

    try std.testing.expectEqualStrings("world.kdl", try config.worldForScene(config.startupScene()));
}
