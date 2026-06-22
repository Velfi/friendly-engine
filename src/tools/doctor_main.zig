const std = @import("std");
const friendly_engine = @import("friendly_engine");
const runtime_shared = @import("runtime_shared");
const world_bake = @import("world_bake.zig");

const modules = friendly_engine.modules;
const world = friendly_engine.world;
const scene_kdl = runtime_shared.scene_kdl;
const scene_resolve = runtime_shared.scene_resolve;

const max_file_bytes: usize = 16 * 1024 * 1024;
const player_start_tag = "player_start";

pub fn main(init: std.process.Init) !void {
    var args_iter = std.process.Args.Iterator.init(init.minimal.args);
    var args = std.array_list.Managed([]const u8).init(init.gpa);
    defer args.deinit();
    while (args_iter.next()) |arg| {
        try args.append(arg);
    }

    runCli(init.gpa, init.io, args.items) catch |err| switch (err) {
        error.InvalidArguments, error.DoctorFailed => std.process.exit(1),
        else => return err,
    };
}

pub fn runCli(allocator: std.mem.Allocator, io: std.Io, args: []const []const u8) !void {
    var options = Options{};
    if (try parseArgs(&options, args[1..])) {
        printUsage();
        return;
    }

    var doctor = Doctor.init(allocator, io, options);
    defer doctor.deinit();
    try doctor.run();
}

const Options = struct {
    project_path: []const u8 = ".",
    engine_path: []const u8 = "engine.kdl",
    world_path: ?[]const u8 = null,
    target: []const u8 = "client-debug",
    bake: bool = false,
};

const DoctorBakeProgress = struct {
    world_path: []const u8,
};

fn printBakeProgress(ctx: ?*anyopaque, progress: world_bake.BakeProgress) void {
    const doctor_ctx: *DoctorBakeProgress = @ptrCast(@alignCast(ctx orelse return));
    switch (progress.stage) {
        .planning_layers => std.debug.print("bake progress: planning compiler layers for {s}\n", .{doctor_ctx.world_path}),
        .baking_cell => {
            const cell = progress.cell orelse return;
            std.debug.print(
                "bake progress: cell {d}/{d} {d},{d},{d} scene={s}\n",
                .{ progress.current, progress.total, cell.x, cell.y, cell.z, progress.scene_path },
            );
        },
        .compiling_layer => {
            const cell = progress.cell orelse return;
            if (progress.current > 2 and progress.current % 100 != 0) return;
            std.debug.print(
                "bake progress:   layer {s} for cell {d},{d},{d}\n",
                .{ progress.layer_name, cell.x, cell.y, cell.z },
            );
        },
        .writing_prefetch => std.debug.print("bake progress: writing prefetch for {d} cells\n", .{progress.current}),
    }
}

const Doctor = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    options: Options,
    failures: usize = 0,
    worlds: std.ArrayList([]u8),
    scenes: std.ArrayList([]u8),

    fn init(allocator: std.mem.Allocator, io: std.Io, options: Options) Doctor {
        return .{
            .allocator = allocator,
            .io = io,
            .options = options,
            .worlds = .empty,
            .scenes = .empty,
        };
    }

    fn deinit(self: *Doctor) void {
        for (self.worlds.items) |path| self.allocator.free(path);
        self.worlds.deinit(self.allocator);
        for (self.scenes.items) |path| self.allocator.free(path);
        self.scenes.deinit(self.allocator);
    }

    fn run(self: *Doctor) !void {
        std.debug.print("doctor: project={s} target={s}\n", .{ self.options.project_path, self.options.target });

        try self.checkEngineConfig();
        if (self.options.world_path) |path| try self.addUnique(&self.worlds, path);
        try self.checkWorlds();
        try self.checkScenes();
        if (self.options.bake) try self.checkWorldBake();

        if (self.failures > 0) {
            std.debug.print("\ndoctor failed: {d} project issue(s) found\n", .{self.failures});
            std.debug.print("LLM repair loop: fix the first listed file, then rerun `zig build doctor -- --project {s}`.\n", .{self.options.project_path});
            return error.DoctorFailed;
        }

        std.debug.print("\ndoctor ok: project files parse and referenced scene assets resolve\n", .{});
    }

    fn checkEngineConfig(self: *Doctor) !void {
        const path = self.options.engine_path;
        std.debug.print("\n== doctor:engine ==\n{s}\n", .{path});
        var config = modules.loadProjectConfigInProject(self.allocator, self.io, self.options.project_path, path) catch |err| {
            self.fail(path, "load engine config", err);
            return;
        };
        defer config.deinit();

        std.debug.print("ok: startup_scene={s} scenes={d} modules={d}\n", .{
            config.startupScene(),
            config.sceneEntries().len,
            config.enabledModules().len,
        });
        try self.checkEngineModules(path, config.enabledModules());

        for (config.sceneEntries()) |entry| {
            try self.addUnique(&self.scenes, entry.path);
            try self.addUnique(&self.worlds, entry.world);
        }
    }

    fn checkEngineModules(self: *Doctor, path: []const u8, enabled_modules: []const []const u8) !void {
        var graph = modules.initBuiltinGraph(self.allocator) catch |err| {
            self.fail(path, "initialize module registry", err);
            return;
        };
        defer graph.deinit();

        modules.addProjectCustomGems(&graph, self.allocator, self.io, self.options.project_path) catch |err| {
            self.fail(path, "load project gems", err);
            return;
        };

        var missing_enabled = false;
        for (enabled_modules) |module_name| {
            if (!graph.hasModule(module_name)) {
                missing_enabled = true;
                self.failUnknownModule(path, module_name);
            }
        }
        if (missing_enabled) return;

        graph.resolveEnabled(enabled_modules) catch |err| {
            switch (err) {
                error.MissingModuleDependency => if (graph.lastMissingDependency()) |missing| {
                    self.failMissingModuleDependency(path, missing.module_name, missing.dependency_name);
                    return;
                },
                else => {},
            }
            self.fail(path, "resolve enabled modules", err);
            return;
        };
    }

    fn checkWorlds(self: *Doctor) !void {
        if (self.worlds.items.len == 0) {
            self.failMessage(self.options.engine_path, "no world manifests referenced by engine config");
            return;
        }

        std.debug.print("\n== doctor:worlds ==\n", .{});
        for (self.worlds.items) |path| {
            var manifest = world.manifest.loadManifest(self.allocator, self.io, self.options.project_path, path) catch |err| {
                self.fail(path, "load world manifest", err);
                continue;
            };
            defer manifest.deinit();

            std.debug.print("ok: {s} world_id={s} cells={d}\n", .{ path, manifest.world_id, manifest.cells.len });
            for (manifest.cells) |cell| {
                if (!try self.projectFileExists(cell.authoring_path)) {
                    self.failMessage(cell.authoring_path, "world cell authoring scene is missing");
                    continue;
                }
                try self.addUnique(&self.scenes, cell.authoring_path);
            }
        }
    }

    fn checkScenes(self: *Doctor) !void {
        std.debug.print("\n== doctor:scenes ==\n", .{});
        if (self.scenes.items.len == 0) {
            self.failMessage(self.options.engine_path, "no scenes referenced by engine or world manifests");
            return;
        }

        for (self.scenes.items) |path| {
            const bytes = self.readProjectFile(path) catch |err| {
                self.fail(path, "read scene", err);
                continue;
            };
            defer self.allocator.free(bytes);

            var document = scene_kdl.parseSceneDocument(self.allocator, bytes) catch |err| {
                self.fail(path, "parse scene KDL", err);
                continue;
            };
            defer document.deinit(self.allocator);

            self.checkSceneIds(path, document);
            self.checkStartupControl(path, document);

            var project_dir = openProjectDir(self.io, self.options.project_path) catch |err| {
                self.fail(self.options.project_path, "open project for asset resolution", err);
                continue;
            };
            defer project_dir.close(self.io);

            const resolver = scene_resolve.AssetResolver{
                .io = self.io,
                .project_dir = project_dir,
                .cache_target = self.options.target,
            };
            var loaded = scene_resolve.resolveDocument(self.allocator, document, resolver) catch |err| {
                self.fail(path, "resolve scene meshes/textures", err);
                continue;
            };
            defer loaded.deinit(self.allocator);

            std.debug.print("ok: {s} entities={d}\n", .{ path, document.entities.len });
        }
    }

    fn checkStartupControl(self: *Doctor, path: []const u8, document: runtime_shared.scene_document.SceneDocument) void {
        for (document.entities) |entity| {
            const gameplay = entity.gameplay orelse continue;
            if (!std.mem.eql(u8, gameplay.tag, player_start_tag)) continue;

            const gem_name = scenePropertyValue(entity, "controller_gem") orelse continue;
            const component_name = scenePropertyValue(entity, "controller_component") orelse {
                self.failPlayerStartMissingControllerProperty(path, entity.id, entity.name, gem_name);
                continue;
            };
            if (!sceneHasComponent(entity.components, component_name)) {
                self.failPlayerStartMissingControllerComponent(path, entity.id, entity.name, component_name);
            }
        }
    }

    fn checkSceneIds(self: *Doctor, path: []const u8, document: runtime_shared.scene_document.SceneDocument) void {
        var ids = std.AutoHashMap(u64, void).init(self.allocator);
        defer ids.deinit();

        var max_id: u64 = 0;
        for (document.entities) |entity| {
            if (ids.contains(entity.id)) {
                self.failMessage(path, "duplicate entity id in scene");
            } else {
                ids.put(entity.id, {}) catch {
                    self.failMessage(path, "out of memory while checking scene ids");
                    return;
                };
            }
            if (entity.id > max_id) max_id = entity.id;
        }
        if (document.next_object_id <= max_id) {
            self.failMessage(path, "next_object_id must be greater than every entity id");
        }
    }

    fn checkWorldBake(self: *Doctor) !void {
        std.debug.print("\n== doctor:bake ==\n", .{});
        for (self.worlds.items) |path| {
            var progress_ctx = DoctorBakeProgress{ .world_path = path };
            var summary = world_bake.bakeWorldWithOptions(
                self.allocator,
                self.io,
                self.options.project_path,
                path,
                self.options.target,
                .{
                    .progress_context = &progress_ctx,
                    .progress = printBakeProgress,
                },
            ) catch |err| {
                self.fail(path, "bake world", err);
                continue;
            };
            defer summary.deinit(self.allocator);
            std.debug.print("ok: baked {d} cells for {s}\n", .{ summary.written_cells, path });
        }
    }

    fn readProjectFile(self: *Doctor, path: []const u8) ![]u8 {
        if (std.fs.path.isAbsolute(path)) {
            const dir_path = std.fs.path.dirname(path) orelse return error.InvalidPath;
            const file_name = std.fs.path.basename(path);
            var dir = try std.Io.Dir.openDirAbsolute(self.io, dir_path, .{});
            defer dir.close(self.io);
            return dir.readFileAlloc(self.io, file_name, self.allocator, .limited(max_file_bytes));
        }

        var project_dir = try openProjectDir(self.io, self.options.project_path);
        defer project_dir.close(self.io);
        return project_dir.readFileAlloc(self.io, path, self.allocator, .limited(max_file_bytes));
    }

    fn projectFileExists(self: *Doctor, path: []const u8) !bool {
        if (std.fs.path.isAbsolute(path)) {
            const dir_path = std.fs.path.dirname(path) orelse return error.InvalidPath;
            const file_name = std.fs.path.basename(path);
            var dir = try std.Io.Dir.openDirAbsolute(self.io, dir_path, .{});
            defer dir.close(self.io);
            dir.access(self.io, file_name, .{}) catch |err| switch (err) {
                error.FileNotFound => return false,
                else => return err,
            };
            return true;
        }

        var project_dir = try openProjectDir(self.io, self.options.project_path);
        defer project_dir.close(self.io);
        project_dir.access(self.io, path, .{}) catch |err| switch (err) {
            error.FileNotFound => return false,
            else => return err,
        };
        return true;
    }

    fn addUnique(self: *Doctor, list: *std.ArrayList([]u8), path: []const u8) !void {
        for (list.items) |existing| {
            if (std.mem.eql(u8, existing, path)) return;
        }
        try list.append(self.allocator, try self.allocator.dupe(u8, path));
    }

    fn fail(self: *Doctor, path: []const u8, action: []const u8, err: anyerror) void {
        self.failures += 1;
        std.debug.print("fail: {s}: {s}: {s}\n", .{ path, action, @errorName(err) });
    }

    fn failMessage(self: *Doctor, path: []const u8, message: []const u8) void {
        self.failures += 1;
        std.debug.print("fail: {s}: {s}\n", .{ path, message });
    }

    fn failUnknownModule(self: *Doctor, path: []const u8, module_name: []const u8) void {
        self.failures += 1;
        std.debug.print("fail: {s}: unknown enabled module: {s}\n", .{ path, module_name });
    }

    fn failMissingModuleDependency(self: *Doctor, path: []const u8, module_name: []const u8, dependency_name: []const u8) void {
        self.failures += 1;
        std.debug.print("fail: {s}: module {s} depends on unknown module: {s}\n", .{ path, module_name, dependency_name });
    }

    fn failPlayerStartMissingControllerProperty(self: *Doctor, path: []const u8, id: u64, name: []const u8, gem_name: []const u8) void {
        self.failures += 1;
        std.debug.print(
            "fail: {s}: player start id={d} name=\"{s}\" uses controller_gem={s} but has no controller_component property\n",
            .{ path, id, name, gem_name },
        );
    }

    fn failPlayerStartMissingControllerComponent(self: *Doctor, path: []const u8, id: u64, name: []const u8, component_name: []const u8) void {
        self.failures += 1;
        std.debug.print(
            "fail: {s}: player start id={d} name=\"{s}\" references controller_component={s} but does not list that component\n",
            .{ path, id, name, component_name },
        );
    }
};

fn sceneHasComponent(components: []const []const u8, needle: []const u8) bool {
    for (components) |component| {
        if (std.mem.eql(u8, component, needle)) return true;
    }
    return false;
}

fn scenePropertyValue(entity: runtime_shared.scene_document.SceneEntity, key: []const u8) ?[]const u8 {
    for (entity.properties) |property| {
        if (std.mem.eql(u8, property.key, key)) return property.value;
    }
    return null;
}

fn parseArgs(options: *Options, args: []const []const u8) !bool {
    var i: usize = 0;
    while (i < args.len) {
        const arg = args[i];
        i += 1;

        if (std.mem.eql(u8, arg, "help") or std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            return true;
        }
        if (std.mem.eql(u8, arg, "--bake")) {
            options.bake = true;
            continue;
        }

        if (i >= args.len) return error.InvalidArguments;
        const value = args[i];
        i += 1;

        if (std.mem.eql(u8, arg, "--project")) {
            options.project_path = value;
            continue;
        }
        if (std.mem.eql(u8, arg, "--engine")) {
            options.engine_path = value;
            continue;
        }
        if (std.mem.eql(u8, arg, "--world")) {
            options.world_path = value;
            continue;
        }
        if (std.mem.eql(u8, arg, "--target")) {
            options.target = value;
            continue;
        }
        return error.InvalidArguments;
    }
    return false;
}

fn openProjectDir(io: std.Io, project_path: []const u8) !std.Io.Dir {
    if (std.fs.path.isAbsolute(project_path)) {
        return try std.Io.Dir.openDirAbsolute(io, project_path, .{});
    }
    return try std.Io.Dir.cwd().openDir(io, project_path, .{});
}

fn printUsage() void {
    std.debug.print(
        "usage: friendly_engine_doctor [--project path] [--engine engine.kdl] [--world world.kdl] [--target client-debug] [--bake]\n" ++
            "       zig build doctor -- [options]\n\n" ++
            "Checks a Friendly Engine project for broken KDL files and references:\n" ++
            "  - parses engine.kdl and referenced world manifests\n" ++
            "  - parses scene KDL files referenced by engine/world manifests\n" ++
            "  - resolves scene meshes and textures against the selected asset cache target\n" ++
            "  - with --bake, runs the world compiler for deeper layer validation\n",
        .{},
    );
}

test "parseArgs reads project doctor options" {
    var options = Options{};
    const help = try parseArgs(&options, &.{ "--project", "demo", "--engine", "engine.kdl", "--world", "worlds/main.kdl", "--target", "client-test", "--bake" });
    try std.testing.expect(!help);
    try std.testing.expectEqualStrings("demo", options.project_path);
    try std.testing.expectEqualStrings("engine.kdl", options.engine_path);
    try std.testing.expectEqualStrings("worlds/main.kdl", options.world_path.?);
    try std.testing.expectEqualStrings("client-test", options.target);
    try std.testing.expect(options.bake);
}

test "parseArgs rejects unknown flags" {
    var options = Options{};
    try std.testing.expectError(error.InvalidArguments, parseArgs(&options, &.{"--wat"}));
}

test "parseArgs reports help" {
    var options = Options{};
    try std.testing.expect(try parseArgs(&options, &.{"--help"}));
}
