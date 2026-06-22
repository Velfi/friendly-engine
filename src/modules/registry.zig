const std = @import("std");
const core = @import("../core/mod.zig");
const framework = @import("../framework/mod.zig");
const world_mod = @import("../world/mod.zig");

pub const RequestCatalogEntry = struct {
    name: []const u8,
    description: []const u8,
};

pub const ServiceRegistry = struct {
    allocator: std.mem.Allocator,
    pending_requests: std.ArrayList(PendingRequest),
    catalog: std.ArrayList(RequestCatalogEntry),
    world_layers: std.ArrayList(world_mod.compiler.layer.WorldCompilerLayer),

    const PendingRequest = struct {
        name: []u8,
        description: []u8,
        handler: core.RequestHandler,
    };

    pub fn init(allocator: std.mem.Allocator) ServiceRegistry {
        return .{
            .allocator = allocator,
            .pending_requests = .empty,
            .catalog = .empty,
            .world_layers = .empty,
        };
    }

    pub fn deinit(self: *ServiceRegistry) void {
        for (self.pending_requests.items) |entry| {
            self.allocator.free(entry.name);
            self.allocator.free(entry.description);
        }
        self.pending_requests.deinit(self.allocator);
        self.catalog.deinit(self.allocator);
        self.world_layers.deinit(self.allocator);
    }

    pub fn registerRequest(
        self: *ServiceRegistry,
        name: []const u8,
        description: []const u8,
        handler: core.RequestHandler,
    ) !void {
        for (self.pending_requests.items) |entry| {
            if (std.mem.eql(u8, entry.name, name)) return error.RequestAlreadyRegistered;
        }

        const owned_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned_name);
        const owned_description = try self.allocator.dupe(u8, description);
        errdefer self.allocator.free(owned_description);

        try self.pending_requests.append(self.allocator, .{
            .name = owned_name,
            .description = owned_description,
            .handler = handler,
        });
        try self.catalog.append(self.allocator, .{
            .name = owned_name,
            .description = owned_description,
        });
    }

    pub fn applyToWorld(self: *ServiceRegistry, world: *framework.World) !void {
        for (self.pending_requests.items) |entry| {
            try world.requests.register(entry.name, entry.handler);
        }
    }

    pub fn catalogEntries(self: *const ServiceRegistry) []const RequestCatalogEntry {
        return self.catalog.items;
    }

    pub fn registerWorldCompilerLayer(
        self: *ServiceRegistry,
        desc: world_mod.compiler.layer.WorldCompilerLayer,
    ) !void {
        for (self.world_layers.items) |existing| {
            if (std.mem.eql(u8, existing.name, desc.name)) return error.WorldLayerAlreadyRegistered;
        }
        try self.world_layers.append(self.allocator, desc);
    }

    pub fn worldCompilerLayers(self: *const ServiceRegistry) []const world_mod.compiler.layer.WorldCompilerLayer {
        return self.world_layers.items;
    }
};

pub const ModuleScope = enum(u8) {
    // ordinal = lifetime narrowness; lower = broader/longer-lived.
    // engine (process) ⊃ project (open project/world) ⊃ editor (editor session)
    engine = 0,
    project = 1,
    editor = 2,
};

pub const ModuleHooks = struct {
    name: []const u8,
    dependencies: []const []const u8 = &.{},
    scope: ModuleScope = .engine,
    // True for project-supplied gems (custom Lua gems) that can be removed from
    // the graph on a project switch. Built-in gems are permanent.
    removable: bool = false,
    register: *const fn (*ServiceRegistry) anyerror!void,
    start: *const fn (*framework.World) anyerror!void,
    stop: *const fn (*framework.World) anyerror!void,
    context: ?*anyopaque = null,
    register_context: ?*const fn (*anyopaque, *ServiceRegistry) anyerror!void = null,
    start_context: ?*const fn (*anyopaque, *framework.World) anyerror!void = null,
    stop_context: ?*const fn (*anyopaque, *framework.World) anyerror!void = null,
    deinit_context: ?*const fn (*anyopaque, std.mem.Allocator) void = null,

    pub fn registerModule(self: ModuleHooks, registry: *ServiceRegistry) !void {
        if (self.context) |ctx| {
            if (self.register_context) |call| return call(ctx, registry);
        }
        return self.register(registry);
    }

    pub fn startModule(self: ModuleHooks, world: *framework.World) !void {
        if (self.context) |ctx| {
            if (self.start_context) |call| return call(ctx, world);
        }
        return self.start(world);
    }

    pub fn stopModule(self: ModuleHooks, world: *framework.World) !void {
        if (self.context) |ctx| {
            if (self.stop_context) |call| return call(ctx, world);
        }
        return self.stop(world);
    }

    pub fn deinitModule(self: ModuleHooks, allocator: std.mem.Allocator) void {
        if (self.context) |ctx| {
            if (self.deinit_context) |call| call(ctx, allocator);
        }
    }
};

pub const ModuleGraph = struct {
    pub const MissingDependency = struct {
        module_name: []const u8,
        dependency_name: []const u8,
    };

    const VisitState = enum(u8) {
        unvisited,
        visiting,
        visited,
    };

    allocator: std.mem.Allocator,
    modules: std.ArrayList(ModuleHooks),
    module_lookup: std.StringHashMap(usize),
    resolved_order: std.ArrayList(usize),
    started: std.ArrayList(bool),
    last_unknown_module: ?[]const u8,
    last_missing_dependency: ?MissingDependency,

    pub fn init(allocator: std.mem.Allocator) ModuleGraph {
        return .{
            .allocator = allocator,
            .modules = .empty,
            .module_lookup = std.StringHashMap(usize).init(allocator),
            .resolved_order = .empty,
            .started = .empty,
            .last_unknown_module = null,
            .last_missing_dependency = null,
        };
    }

    pub fn deinit(self: *ModuleGraph) void {
        for (self.modules.items) |hooks| hooks.deinitModule(self.allocator);
        self.started.deinit(self.allocator);
        self.resolved_order.deinit(self.allocator);
        self.module_lookup.deinit();
        self.modules.deinit(self.allocator);
    }

    pub fn add(self: *ModuleGraph, hooks: ModuleHooks) !void {
        if (self.module_lookup.contains(hooks.name)) {
            return error.DuplicateModuleName;
        }
        const index = self.modules.items.len;
        try self.modules.append(self.allocator, hooks);
        try self.module_lookup.put(hooks.name, index);
    }

    /// Name of the first removable (project-supplied) module still in the graph,
    /// or null. Used to drain custom gems one at a time on a project switch.
    pub fn firstRemovableModuleName(self: *const ModuleGraph) ?[]const u8 {
        for (self.modules.items) |hooks| {
            if (hooks.removable) return hooks.name;
        }
        return null;
    }

    /// Remove a single module, freeing resources it owns (e.g. a custom LuaGem
    /// context). Indices shift, so the name lookup is rebuilt and any prior
    /// resolution is discarded — callers must re-resolve afterward. The caller
    /// must stop the module and unregister its world requests beforehand.
    pub fn removeModule(self: *ModuleGraph, name: []const u8) !bool {
        const index = self.module_lookup.get(name) orelse return false;
        self.modules.items[index].deinitModule(self.allocator);
        _ = self.modules.orderedRemove(index);
        if (index < self.started.items.len) _ = self.started.orderedRemove(index);
        try self.rebuildLookup();
        self.resolved_order.clearRetainingCapacity();
        return true;
    }

    fn rebuildLookup(self: *ModuleGraph) !void {
        self.module_lookup.clearRetainingCapacity();
        for (self.modules.items, 0..) |hooks, idx| {
            try self.module_lookup.put(hooks.name, idx);
        }
    }

    pub fn hasModule(self: *const ModuleGraph, module_name: []const u8) bool {
        return self.module_lookup.contains(module_name);
    }

    pub fn lastUnknownModule(self: *const ModuleGraph) ?[]const u8 {
        return self.last_unknown_module;
    }

    pub fn lastMissingDependency(self: *const ModuleGraph) ?MissingDependency {
        return self.last_missing_dependency;
    }

    pub fn resolveEnabled(self: *ModuleGraph, enabled_modules: []const []const u8) !void {
        self.resolved_order.clearRetainingCapacity();
        self.last_unknown_module = null;
        self.last_missing_dependency = null;

        const states = try self.allocator.alloc(VisitState, self.modules.items.len);
        defer self.allocator.free(states);
        @memset(states, .unvisited);

        for (enabled_modules) |module_name| {
            const module_index = self.module_lookup.get(module_name) orelse {
                self.last_unknown_module = module_name;
                return error.UnknownModule;
            };
            try self.resolveFrom(module_index, states);
        }
    }

    /// Explicitly resolve every module in the graph (dependency-ordered). Use
    /// this for whole-engine tooling (asset bake, introspection); project
    /// loading must list its gems explicitly via resolveEnabled.
    pub fn resolveAll(self: *ModuleGraph) !void {
        self.resolved_order.clearRetainingCapacity();

        const states = try self.allocator.alloc(VisitState, self.modules.items.len);
        defer self.allocator.free(states);
        @memset(states, .unvisited);

        for (self.modules.items, 0..) |_, idx| {
            try self.resolveFrom(idx, states);
        }
    }

    /// Re-resolve the graph for a project switch: keep every currently-started
    /// engine-scope gem (process lifetime) and add the requested modules that
    /// exist in the graph. Modules not present (e.g. another project's custom
    /// gems, or gems filtered out at boot) are skipped rather than erroring, so
    /// switching projects is robust. Does not mutate started state — callers
    /// stop the old project/editor scopes before, and start the new ones after.
    pub fn resolveEnabledForProjectSwitch(self: *ModuleGraph, enabled_modules: []const []const u8) !void {
        try self.ensureStartedSized();
        var keep = std.ArrayList([]const u8).empty;
        defer keep.deinit(self.allocator);

        for (self.modules.items, 0..) |hooks, idx| {
            if (hooks.scope == .engine and self.started.items[idx]) {
                try keep.append(self.allocator, hooks.name);
            }
        }
        for (enabled_modules) |module_name| {
            if (self.module_lookup.contains(module_name)) {
                try keep.append(self.allocator, module_name);
            }
        }
        // resolveEnabled dedups via its visit-state walk, so duplicate names
        // (an engine gem also listed in enabled_modules) are harmless.
        try self.resolveEnabled(keep.items);
    }

    fn resolveFrom(self: *ModuleGraph, module_index: usize, states: []VisitState) !void {
        const current_state = states[module_index];
        switch (current_state) {
            .visited => return,
            .visiting => return error.ModuleDependencyCycle,
            .unvisited => {},
        }

        states[module_index] = .visiting;
        const module = self.modules.items[module_index];
        for (module.dependencies) |dependency_name| {
            const dependency_index = self.module_lookup.get(dependency_name) orelse {
                self.last_missing_dependency = .{
                    .module_name = module.name,
                    .dependency_name = dependency_name,
                };
                return error.MissingModuleDependency;
            };
            // A gem may only depend on gems whose scope is the same or broader
            // (lower ordinal). Depending on a shorter-lived scope is a lifetime bug.
            if (@intFromEnum(self.modules.items[dependency_index].scope) > @intFromEnum(module.scope)) {
                return error.CrossScopeDependency;
            }
            try self.resolveFrom(dependency_index, states);
        }
        states[module_index] = .visited;
        try self.resolved_order.append(self.allocator, module_index);
    }

    pub fn resolvedCount(self: *const ModuleGraph) usize {
        return self.resolved_order.items.len;
    }

    pub fn resolvedAtName(self: *const ModuleGraph, index: usize) []const u8 {
        return self.modules.items[self.resolved_order.items[index]].name;
    }

    pub fn registerAll(self: *ModuleGraph, registry: *ServiceRegistry) !void {
        for (self.resolved_order.items) |module_index| {
            const hooks = self.modules.items[module_index];
            try hooks.registerModule(registry);
        }
    }

    fn ensureStartedSized(self: *ModuleGraph) !void {
        while (self.started.items.len < self.modules.items.len) {
            try self.started.append(self.allocator, false);
        }
    }

    // Lifecycle iterates the topologically resolved order. Nothing is started
    // until resolveEnabled/resolveAll has populated it.
    fn orderedCount(self: *const ModuleGraph) usize {
        return self.resolved_order.items.len;
    }

    fn orderedModuleIndex(self: *const ModuleGraph, position: usize) usize {
        return self.resolved_order.items[position];
    }

    pub fn startScope(self: *ModuleGraph, scope: ModuleScope, world: *framework.World) !void {
        try self.ensureStartedSized();
        const count = self.orderedCount();
        var position: usize = 0;
        while (position < count) : (position += 1) {
            const module_index = self.orderedModuleIndex(position);
            const hooks = self.modules.items[module_index];
            if (hooks.scope != scope or self.started.items[module_index]) continue;
            try hooks.startModule(world);
            self.started.items[module_index] = true;
        }
    }

    pub fn stopScope(self: *ModuleGraph, scope: ModuleScope, world: *framework.World) !void {
        try self.ensureStartedSized();
        var position = self.orderedCount();
        while (position > 0) {
            position -= 1;
            const module_index = self.orderedModuleIndex(position);
            const hooks = self.modules.items[module_index];
            if (hooks.scope != scope or !self.started.items[module_index]) continue;
            try hooks.stopModule(world);
            self.started.items[module_index] = false;
        }
    }

    pub fn isStarted(self: *const ModuleGraph, module_name: []const u8) bool {
        const index = self.module_lookup.get(module_name) orelse return false;
        if (index >= self.started.items.len) return false;
        return self.started.items[index];
    }

    pub fn startAll(self: *ModuleGraph, world: *framework.World) !void {
        try self.startScope(.engine, world);
        try self.startScope(.project, world);
        try self.startScope(.editor, world);
    }

    pub fn stopAll(self: *ModuleGraph, world: *framework.World) !void {
        try self.stopScope(.editor, world);
        try self.stopScope(.project, world);
        try self.stopScope(.engine, world);
    }
};

test "service registry tracks request catalog" {
    var registry = ServiceRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try registry.registerRequest("test.echo", "Echo payload", .{
        .call = struct {
            fn call(_: ?*anyopaque, allocator: std.mem.Allocator, payload: []const u8) ![]u8 {
                return allocator.dupe(u8, payload);
            }
        }.call,
    });

    try std.testing.expectEqual(@as(usize, 1), registry.catalogEntries().len);
    try std.testing.expectEqualStrings("test.echo", registry.catalogEntries()[0].name);
}

test "service registry tracks world compiler layers" {
    var registry = ServiceRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try registry.registerWorldCompilerLayer(.{
        .name = "layer.test",
        .affected_cells = struct {
            fn call(_: ?*anyopaque, _: *const world_mod.compiler.layer.CompileContext, allocator: std.mem.Allocator) ![]world_mod.cell.CellId {
                return allocator.alloc(world_mod.cell.CellId, 0);
            }
        }.call,
        .compile_cell = struct {
            fn call(
                _: ?*anyopaque,
                _: *const world_mod.compiler.layer.CompileContext,
                _: world_mod.cell.CellId,
                _: std.mem.Allocator,
            ) !world_mod.compiler.layer.CellLayerOutput {
                return .{};
            }
        }.call,
    });

    try std.testing.expectEqual(@as(usize, 1), registry.worldCompilerLayers().len);
}
