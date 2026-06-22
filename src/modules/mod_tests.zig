const std = @import("std");
const framework = @import("../framework/mod.zig");
const modules = @import("mod.zig");

fn noopRegister(registry: *modules.ServiceRegistry) !void {
    _ = registry;
}

fn noopStart(world: *framework.World) !void {
    _ = world;
}

fn noopStop(world: *framework.World) !void {
    _ = world;
}

test "builtin modules register and publish lifecycle events" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();

    var graph = try modules.initBuiltinGraph(std.testing.allocator);
    defer graph.deinit();

    var config = try modules.defaultProjectConfig(std.testing.allocator);
    defer config.deinit();
    try graph.resolveEnabled(config.enabledModules());

    var services = modules.ServiceRegistry.init(std.testing.allocator);
    defer services.deinit();
    try graph.registerAll(&services);
    try services.applyToWorld(&world);
    try graph.startAll(&world);
    try graph.stopAll(&world);

    try std.testing.expect(world.notifications.events.items.len >= 8);
    try std.testing.expectEqualStrings("gem.ecs.started", world.notifications.events.items[0].name);
    try std.testing.expectEqualStrings(
        "gem.ecs.stopped",
        world.notifications.events.items[world.notifications.events.items.len - 1].name,
    );
}

test "builtin module config can disable physics" {
    var graph = try modules.initBuiltinGraphWithConfig(std.testing.allocator, .{
        .enable_physics = false,
        .enable_core_ui = true,
        .enable_audio = true,
        .enable_persistence = true,
    });
    defer graph.deinit();

    try std.testing.expectEqual(@as(usize, modules.moduleCatalogEntries().len - 1), graph.modules.items.len);
    for (graph.modules.items) |entry| {
        try std.testing.expect(!std.mem.eql(u8, entry.name, modules.physics3d.module_name));
    }
}

test "module graph resolves dependencies in topological order" {
    var graph = modules.ModuleGraph.init(std.testing.allocator);
    defer graph.deinit();

    try graph.add(.{
        .name = "module.gamma",
        .dependencies = &.{"module.beta"},
        .register = noopRegister,
        .start = noopStart,
        .stop = noopStop,
    });
    try graph.add(.{
        .name = "module.beta",
        .dependencies = &.{"module.alpha"},
        .register = noopRegister,
        .start = noopStart,
        .stop = noopStop,
    });
    try graph.add(.{
        .name = "module.alpha",
        .register = noopRegister,
        .start = noopStart,
        .stop = noopStop,
    });

    try graph.resolveEnabled(&.{"module.gamma"});
    try std.testing.expectEqual(@as(usize, 3), graph.resolvedCount());
    try std.testing.expectEqualStrings("module.alpha", graph.resolvedAtName(0));
    try std.testing.expectEqualStrings("module.beta", graph.resolvedAtName(1));
    try std.testing.expectEqualStrings("module.gamma", graph.resolvedAtName(2));
}

test "module graph reports dependency cycles" {
    var graph = modules.ModuleGraph.init(std.testing.allocator);
    defer graph.deinit();

    try graph.add(.{
        .name = "module.a",
        .dependencies = &.{"module.b"},
        .register = noopRegister,
        .start = noopStart,
        .stop = noopStop,
    });
    try graph.add(.{
        .name = "module.b",
        .dependencies = &.{"module.a"},
        .register = noopRegister,
        .start = noopStart,
        .stop = noopStop,
    });

    try std.testing.expectError(error.ModuleDependencyCycle, graph.resolveEnabled(&.{"module.a"}));
}

test "module graph reports missing dependencies" {
    var graph = modules.ModuleGraph.init(std.testing.allocator);
    defer graph.deinit();

    try graph.add(.{
        .name = "module.render",
        .dependencies = &.{"module.window"},
        .register = noopRegister,
        .start = noopStart,
        .stop = noopStop,
    });
    try std.testing.expectError(error.MissingModuleDependency, graph.resolveEnabled(&.{"module.render"}));
    const missing = graph.lastMissingDependency().?;
    try std.testing.expectEqualStrings("module.render", missing.module_name);
    try std.testing.expectEqualStrings("module.window", missing.dependency_name);
}

test "module graph remembers unknown enabled module" {
    var graph = modules.ModuleGraph.init(std.testing.allocator);
    defer graph.deinit();

    try std.testing.expectError(error.UnknownModule, graph.resolveEnabled(&.{"module.missing"}));
    try std.testing.expectEqualStrings("module.missing", graph.lastUnknownModule().?);
}

test "resolveEnabled with no modules resolves and starts nothing" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();

    var graph = try modules.initBuiltinGraph(std.testing.allocator);
    defer graph.deinit();

    try graph.resolveEnabled(&.{});
    try std.testing.expectEqual(@as(usize, 0), graph.resolvedCount());

    try graph.startScope(.engine, &world);
    try std.testing.expect(!graph.isStarted("gem.ecs"));
}

test "resolveAll resolves every module in the graph" {
    var graph = try modules.initBuiltinGraph(std.testing.allocator);
    defer graph.deinit();

    try graph.resolveAll();
    try std.testing.expectEqual(graph.modules.items.len, graph.resolvedCount());
}

test "module graph rejects dependency on a shorter-lived scope" {
    var graph = modules.ModuleGraph.init(std.testing.allocator);
    defer graph.deinit();

    try graph.add(.{
        .name = "module.engine",
        .scope = .engine,
        .dependencies = &.{"module.project"},
        .register = noopRegister,
        .start = noopStart,
        .stop = noopStop,
    });
    try graph.add(.{
        .name = "module.project",
        .scope = .project,
        .register = noopRegister,
        .start = noopStart,
        .stop = noopStop,
    });
    try std.testing.expectError(error.CrossScopeDependency, graph.resolveEnabled(&.{"module.engine"}));
}

test "module graph allows dependency on a broader scope" {
    var graph = modules.ModuleGraph.init(std.testing.allocator);
    defer graph.deinit();

    try graph.add(.{
        .name = "module.project",
        .scope = .project,
        .dependencies = &.{"module.engine"},
        .register = noopRegister,
        .start = noopStart,
        .stop = noopStop,
    });
    try graph.add(.{
        .name = "module.engine",
        .scope = .engine,
        .register = noopRegister,
        .start = noopStart,
        .stop = noopStop,
    });

    try graph.resolveEnabled(&.{"module.project"});
    try std.testing.expectEqual(@as(usize, 2), graph.resolvedCount());
    try std.testing.expectEqualStrings("module.engine", graph.resolvedAtName(0));
    try std.testing.expectEqualStrings("module.project", graph.resolvedAtName(1));
}

test "scope-aware start and stop isolate gem lifetimes" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();

    var graph = modules.ModuleGraph.init(std.testing.allocator);
    defer graph.deinit();

    try graph.add(.{
        .name = "module.engine",
        .scope = .engine,
        .register = noopRegister,
        .start = noopStart,
        .stop = noopStop,
    });
    try graph.add(.{
        .name = "module.project",
        .scope = .project,
        .register = noopRegister,
        .start = noopStart,
        .stop = noopStop,
    });
    try graph.add(.{
        .name = "module.editor",
        .scope = .editor,
        .register = noopRegister,
        .start = noopStart,
        .stop = noopStop,
    });
    try graph.resolveEnabled(&.{ "module.engine", "module.project", "module.editor" });

    // Starting one scope leaves the others untouched.
    try graph.startScope(.engine, &world);
    try std.testing.expect(graph.isStarted("module.engine"));
    try std.testing.expect(!graph.isStarted("module.project"));
    try std.testing.expect(!graph.isStarted("module.editor"));

    try graph.startScope(.project, &world);
    try graph.startScope(.editor, &world);
    try std.testing.expect(graph.isStarted("module.project"));
    try std.testing.expect(graph.isStarted("module.editor"));

    // Closing a project tears down editor + project; engine persists.
    try graph.stopScope(.editor, &world);
    try graph.stopScope(.project, &world);
    try std.testing.expect(graph.isStarted("module.engine"));
    try std.testing.expect(!graph.isStarted("module.project"));
    try std.testing.expect(!graph.isStarted("module.editor"));

    // Reopening restarts the project scope idempotently.
    try graph.startScope(.project, &world);
    try std.testing.expect(graph.isStarted("module.project"));
    try std.testing.expect(graph.isStarted("module.engine"));
}
