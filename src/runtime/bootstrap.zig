const std = @import("std");
const framework = @import("../framework/mod.zig");
const modules = @import("../modules/mod.zig");

pub const BootResult = struct {
    world: framework.World,
    module_graph: modules.ModuleGraph,
    services: modules.ServiceRegistry,
    project_config: modules.OwnedProjectConfig,

    pub fn deinit(self: *BootResult) void {
        self.module_graph.stopAll(&self.world) catch |err| std.debug.panic("module stop failed: {s}", .{@errorName(err)});
        self.project_config.deinit();
        self.module_graph.deinit();
        self.services.deinit();
        self.world.deinit();
    }

    /// Tear down editor- and project-scoped gems while leaving engine-scoped
    /// gems (ecs, luajit, physics, ...) running. Safe to call repeatedly.
    pub fn closeProject(self: *BootResult) !void {
        try self.module_graph.stopScope(.editor, &self.world);
        try self.module_graph.stopScope(.project, &self.world);
    }

    /// Restart project- and editor-scoped gems over the still-running engine
    /// scope. Mirrors closeProject; safe to call repeatedly.
    pub fn openProject(self: *BootResult) !void {
        try self.module_graph.startScope(.project, &self.world);
        try self.module_graph.startScope(.editor, &self.world);
    }

    /// Switch to a different project: tear down the current project + editor
    /// scopes, swap the project's custom Lua gems (removing the previous
    /// project's, loading the target's), re-resolve the gem set from the target
    /// project's engine.kdl (keeping the persistent engine scope), then start
    /// the new project + editor scopes. Engine-scoped gems stay running across
    /// the switch.
    pub fn reloadProjectModules(
        self: *BootResult,
        allocator: std.mem.Allocator,
        io: std.Io,
        project_path: []const u8,
    ) !void {
        try self.module_graph.stopScope(.editor, &self.world);
        try self.module_graph.stopScope(.project, &self.world);

        try modules.swapProjectCustomGems(&self.module_graph, &self.world, allocator, io, project_path);

        var new_config = try modules.loadProjectConfigInProject(allocator, io, project_path, "engine.kdl");
        defer new_config.deinit();

        try self.module_graph.resolveEnabledForProjectSwitch(new_config.enabledModules());

        try self.module_graph.startScope(.engine, &self.world);
        try self.module_graph.startScope(.project, &self.world);
        try self.module_graph.startScope(.editor, &self.world);
    }
};

pub fn bootWorld(
    allocator: std.mem.Allocator,
    io: std.Io,
    config: @import("../root.zig").EngineConfig,
    project_config_path: []const u8,
) !BootResult {
    return bootWorldWithConfigLoader(
        allocator,
        io,
        config,
        .cwd,
        "",
        project_config_path,
    );
}

pub fn bootWorldInProject(
    allocator: std.mem.Allocator,
    io: std.Io,
    config: @import("../root.zig").EngineConfig,
    project_path: []const u8,
    project_config_path: []const u8,
) !BootResult {
    return bootWorldWithConfigLoader(
        allocator,
        io,
        config,
        .project,
        project_path,
        project_config_path,
    );
}

const ConfigLoadMode = enum {
    cwd,
    project,
};

fn bootWorldWithConfigLoader(
    allocator: std.mem.Allocator,
    io: std.Io,
    config: @import("../root.zig").EngineConfig,
    config_load_mode: ConfigLoadMode,
    project_path: []const u8,
    project_config_path: []const u8,
) !BootResult {
    const engine = @import("../root.zig");
    var world = try engine.init(config, allocator);
    errdefer world.deinit();

    var project_config = switch (config_load_mode) {
        .cwd => try modules.loadProjectConfig(
            allocator,
            io,
            project_config_path,
        ),
        .project => try modules.loadProjectConfigInProject(
            allocator,
            io,
            project_path,
            project_config_path,
        ),
    };
    errdefer project_config.deinit();

    var module_graph = try modules.initBuiltinGraphWithConfig(allocator, .{
        .enable_physics = config.enable_physics,
        .enable_core_ui = true,
        .enable_audio = config.enable_audio,
        .enable_persistence = true,
    });
    errdefer module_graph.deinit();

    const custom_gem_project_path = switch (config_load_mode) {
        .cwd => ".",
        .project => project_path,
    };
    try modules.addProjectCustomGems(&module_graph, allocator, io, custom_gem_project_path);

    var enabled_modules = std.ArrayList([]const u8).empty;
    defer enabled_modules.deinit(allocator);
    for (project_config.enabledModules()) |module_name| {
        if (!config.enable_physics and std.mem.eql(u8, module_name, modules.physics3d.module_name)) {
            continue;
        }
        if (!config.enable_audio and std.mem.eql(u8, module_name, modules.audio.module_name)) {
            continue;
        }
        try enabled_modules.append(allocator, module_name);
    }
    module_graph.resolveEnabled(enabled_modules.items) catch |err| {
        switch (err) {
            error.UnknownModule => if (module_graph.lastUnknownModule()) |module_name| {
                std.log.err("unknown enabled module: {s}", .{module_name});
            },
            error.MissingModuleDependency => if (module_graph.lastMissingDependency()) |missing| {
                std.log.err(
                    "module {s} depends on unknown module: {s}",
                    .{ missing.module_name, missing.dependency_name },
                );
            },
            else => {},
        }
        return err;
    };

    var services = modules.ServiceRegistry.init(allocator);
    errdefer services.deinit();
    try module_graph.registerAll(&services);
    try framework.introspection.registerIntrospection(&services);
    try services.applyToWorld(&world);
    // Start in lifetime-breadth order: engine (process) then project then editor.
    try module_graph.startScope(.engine, &world);
    try module_graph.startScope(.project, &world);
    try module_graph.startScope(.editor, &world);

    return .{
        .world = world,
        .module_graph = module_graph,
        .services = services,
        .project_config = project_config,
    };
}

test "bootstrap loads default project config and starts modules" {
    var boot = try bootWorld(std.testing.allocator, std.testing.io, .{}, "engine.kdl");
    defer boot.deinit();

    try std.testing.expect(boot.project_config.enabledModules().len >= 1);
    try std.testing.expect(boot.module_graph.resolvedCount() >= 1);
}

test "closeProject and openProject cycle project scope while engine persists" {
    var boot = try bootWorld(std.testing.allocator, std.testing.io, .{}, "engine.kdl");
    defer boot.deinit();

    // All scopes start at boot.
    try std.testing.expect(boot.module_graph.isStarted("gem.ecs"));
    try std.testing.expect(boot.module_graph.isStarted("gem.terrain"));
    try std.testing.expect(boot.module_graph.isStarted("gem.editor_world"));

    try boot.closeProject();
    try std.testing.expect(boot.module_graph.isStarted("gem.ecs")); // engine persists
    try std.testing.expect(!boot.module_graph.isStarted("gem.terrain")); // project torn down
    try std.testing.expect(!boot.module_graph.isStarted("gem.editor_world")); // editor torn down

    try boot.openProject();
    try std.testing.expect(boot.module_graph.isStarted("gem.terrain"));
    try std.testing.expect(boot.module_graph.isStarted("gem.editor_world"));
}

test "reloadProjectModules honors the target project's enabled gem set" {
    var boot = try bootWorld(std.testing.allocator, std.testing.io, .{}, "engine.kdl");
    defer boot.deinit();

    // Boot enables the full default set.
    try std.testing.expect(boot.module_graph.isStarted("gem.water"));
    try std.testing.expect(boot.module_graph.isStarted("gem.editor_world"));

    // A different project that enables only a subset of project gems.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "engine.kdl",
        .data =
        \\engine startup_scene="scenes/main.kdl" {
        \\  module name="gem.ecs"
        \\  module name="gem.terrain"
        \\  module name="gem.fps_player_controller"
        \\  scene path="scenes/main.kdl" world="world.kdl"
        \\}
        \\
        ,
    });
    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);

    try boot.reloadProjectModules(std.testing.allocator, std.testing.io, project_path);

    // Engine scope persists; the new project's project gem starts; gems the new
    // project does not enable are torn down.
    try std.testing.expect(boot.module_graph.isStarted("gem.ecs"));
    try std.testing.expect(boot.module_graph.isStarted("gem.terrain"));
    try std.testing.expect(boot.module_graph.isStarted("gem.fps_player_controller"));
    try std.testing.expect(!boot.module_graph.isStarted("gem.water"));
    try std.testing.expect(!boot.module_graph.isStarted("gem.editor_world"));
    try std.testing.expectEqual(@as(usize, 1), countComponentsNamed(
        &boot.world,
        modules.fps_player_controller.component_name,
    ));
}

fn countComponentsNamed(world: *const framework.World, name: []const u8) usize {
    var count: usize = 0;
    for (world.component_registry.entries()) |entry| {
        if (std.mem.eql(u8, entry.name, name)) count += 1;
    }
    return count;
}

test "reloadProjectModules swaps per-project custom Lua gems" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Project A enables custom gem.alpha; project B enables custom gem.beta.
    try tmp.dir.makePath("a/gems/alpha");
    try tmp.dir.makePath("b/gems/beta");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "a/engine.kdl",
        .data =
        \\engine startup_scene="scenes/main.kdl" {
        \\  module name="gem.luajit"
        \\  module name="gem.alpha"
        \\  scene path="scenes/main.kdl" world="world.kdl"
        \\}
        \\
        ,
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "a/gems/alpha/gem.kdl",
        .data =
        \\gem name="gem.alpha" kind="lua" main="main.lua" {
        \\  dependency name="gem.luajit"
        \\}
        \\
        ,
    });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "a/gems/alpha/main.lua", .data = "return { name = 'alpha' }\n" });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "b/engine.kdl",
        .data =
        \\engine startup_scene="scenes/main.kdl" {
        \\  module name="gem.luajit"
        \\  module name="gem.beta"
        \\  scene path="scenes/main.kdl" world="world.kdl"
        \\}
        \\
        ,
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "b/gems/beta/gem.kdl",
        .data =
        \\gem name="gem.beta" kind="lua" main="main.lua" {
        \\  dependency name="gem.luajit"
        \\}
        \\
        ,
    });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "b/gems/beta/main.lua", .data = "return { name = 'beta' }\n" });

    const path_a = try tmp.dir.realpathAlloc(std.testing.allocator, "a");
    defer std.testing.allocator.free(path_a);
    const path_b = try tmp.dir.realpathAlloc(std.testing.allocator, "b");
    defer std.testing.allocator.free(path_b);

    var boot = try bootWorldInProject(std.testing.allocator, std.testing.io, .{}, path_a, "engine.kdl");
    defer boot.deinit();

    // Project A's custom gem is started and its describe request is live.
    try std.testing.expect(boot.module_graph.isStarted("gem.alpha"));
    const alpha_desc = try boot.world.requests.request("gem.alpha.describe", "{}");
    std.testing.allocator.free(alpha_desc);

    try boot.reloadProjectModules(std.testing.allocator, std.testing.io, path_b);

    // Project A's gem is gone (unregistered + removed); project B's gem is live.
    try std.testing.expect(!boot.module_graph.isStarted("gem.alpha"));
    try std.testing.expect(boot.module_graph.isStarted("gem.beta"));
    try std.testing.expectError(error.UnknownRequest, boot.world.requests.request("gem.alpha.describe", "{}"));
    const beta_desc = try boot.world.requests.request("gem.beta.describe", "{}");
    std.testing.allocator.free(beta_desc);
}

test "reloadProjectModules starts newly resolved engine dependencies before custom Lua gems" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makePath("a");
    try tmp.dir.makePath("b/gems/controller");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "a/engine.kdl",
        .data =
        \\engine startup_scene="scenes/main.kdl" {
        \\  module name="gem.terrain"
        \\  scene path="scenes/main.kdl" world="world.kdl"
        \\}
        \\
        ,
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "b/engine.kdl",
        .data =
        \\engine startup_scene="scenes/main.kdl" {
        \\  module name="gem.controller"
        \\  scene path="scenes/main.kdl" world="world.kdl"
        \\}
        \\
        ,
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "b/gems/controller/gem.kdl",
        .data =
        \\gem name="gem.controller" kind="lua" main="main.lua" {
        \\  dependency name="gem.luajit"
        \\}
        \\
        ,
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "b/gems/controller/main.lua",
        .data = "return { name = 'controller' }\n",
    });

    const path_a = try tmp.dir.realpathAlloc(std.testing.allocator, "a");
    defer std.testing.allocator.free(path_a);
    const path_b = try tmp.dir.realpathAlloc(std.testing.allocator, "b");
    defer std.testing.allocator.free(path_b);

    var boot = try bootWorldInProject(std.testing.allocator, std.testing.io, .{}, path_a, "engine.kdl");
    defer boot.deinit();

    try std.testing.expect(!boot.module_graph.isStarted("gem.luajit"));

    try boot.reloadProjectModules(std.testing.allocator, std.testing.io, path_b);

    try std.testing.expect(boot.module_graph.isStarted("gem.luajit"));
    try std.testing.expect(boot.module_graph.isStarted("gem.controller"));
}

test "bootstrap loads custom lua gem from project gems directory" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makePath("gems/test_controller");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "engine.kdl",
        .data =
        \\engine startup_scene="scenes/main.kdl" {
        \\  module name="gem.test_controller"
        \\  scene path="scenes/main.kdl" world="world.kdl"
        \\}
        \\
        ,
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "gems/test_controller/gem.kdl",
        .data =
        \\gem name="gem.test_controller" kind="lua" main="main.lua" {
        \\  dependency name="gem.luajit"
        \\}
        \\
        ,
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "gems/test_controller/main.lua",
        .data = "return { name = 'test_controller' }\n",
    });

    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);

    var boot = try bootWorldInProject(std.testing.allocator, std.testing.io, .{}, project_path, "engine.kdl");
    defer boot.deinit();

    try std.testing.expectEqual(@as(usize, 2), boot.module_graph.resolvedCount());
    try std.testing.expectEqualStrings("gem.luajit", boot.module_graph.resolvedAtName(0));
    try std.testing.expectEqualStrings("gem.test_controller", boot.module_graph.resolvedAtName(1));
}

test "bootstrap loads project config from explicit project path" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "engine.kdl",
        .data =
        \\engine startup_scene="scenes/main.kdl" {
        \\  module name="gem.core_ui"
        \\  scene path="scenes/main.kdl" world="world.kdl"
        \\}
        \\
        ,
    });

    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);

    var boot = try bootWorldInProject(std.testing.allocator, std.testing.io, .{}, project_path, "engine.kdl");
    defer boot.deinit();

    try std.testing.expectEqualStrings("world.kdl", try boot.project_config.worldForScene(boot.project_config.startupScene()));
}
