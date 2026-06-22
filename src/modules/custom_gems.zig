const std = @import("std");
const kdl = @import("kdl");
const framework = @import("../framework/mod.zig");
const registry_mod = @import("registry.zig");
const luajit = @import("luajit/mod.zig");

const max_manifest_bytes: usize = 64 * 1024;
const max_lua_source_bytes: usize = 1024 * 1024;

pub const GemKind = enum {
    lua,
};

pub const LuaGem = struct {
    name: []u8,
    dependencies: [][]u8,
    manifest_path: []u8,
    main_path: []u8,
    source: []u8,
    kind: GemKind = .lua,

    pub fn deinit(self: *LuaGem, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        for (self.dependencies) |dependency| allocator.free(dependency);
        allocator.free(self.dependencies);
        allocator.free(self.manifest_path);
        allocator.free(self.main_path);
        allocator.free(self.source);
        allocator.destroy(self);
    }

    pub fn hooks(self: *LuaGem) registry_mod.ModuleHooks {
        return .{
            .name = self.name,
            .scope = .project,
            .removable = true,
            .dependencies = self.dependencies,
            .register = noopRegister,
            .start = noopStart,
            .stop = noopStop,
            .context = self,
            .register_context = registerLuaGem,
            .start_context = startLuaGem,
            .stop_context = stopLuaGem,
            .deinit_context = deinitLuaGem,
        };
    }
};

pub fn addProjectCustomGems(
    graph: *registry_mod.ModuleGraph,
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
) !void {
    try loadProjectCustomGems(graph, null, allocator, io, project_path);
}

/// Swap the graph's custom Lua gems for a different project: remove the gems
/// from the previous project (freeing them and unregistering their live world
/// requests), then load the target project's gems and register their requests.
/// Callers must stop the project/editor scopes first and re-resolve afterward.
pub fn swapProjectCustomGems(
    graph: *registry_mod.ModuleGraph,
    world: *framework.World,
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
) !void {
    while (graph.firstRemovableModuleName()) |name| {
        try unregisterGemRequest(world, name);
        _ = try graph.removeModule(name);
    }
    try loadProjectCustomGems(graph, world, allocator, io, project_path);
}

fn loadProjectCustomGems(
    graph: *registry_mod.ModuleGraph,
    world: ?*framework.World,
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
) !void {
    var project_dir = try openProjectDir(io, project_path);
    defer project_dir.close(io);

    var gems_dir = project_dir.openDir(io, "gems", .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer gems_dir.close(io);

    var walker = try gems_dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.path, "gem.kdl")) continue;

        const manifest_path = try std.fs.path.join(allocator, &.{ "gems", entry.path });
        defer allocator.free(manifest_path);
        const gem = try loadGemManifest(allocator, io, project_dir, manifest_path);
        try graph.add(gem.hooks());
        // When swapping in mid-session, register the gem's describe request
        // directly into the live world (boot routes this through the registry).
        if (world) |w| try registerGemRequest(w, gem.name);
    }
}

fn registerGemRequest(world: *framework.World, gem_name: []const u8) !void {
    const request_name = try std.fmt.allocPrint(world.allocator, "{s}.describe", .{gem_name});
    defer world.allocator.free(request_name);
    try world.requests.register(request_name, .{ .call = describeLuaGem });
}

fn unregisterGemRequest(world: *framework.World, gem_name: []const u8) !void {
    const request_name = try std.fmt.allocPrint(world.allocator, "{s}.describe", .{gem_name});
    defer world.allocator.free(request_name);
    _ = world.requests.unregister(request_name);
}

pub fn loadGemManifest(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_dir: std.Io.Dir,
    manifest_path: []const u8,
) !*LuaGem {
    const bytes = try project_dir.readFileAlloc(io, manifest_path, allocator, .limited(max_manifest_bytes));
    defer allocator.free(bytes);

    var parsed = try parseGemManifestBytes(allocator, manifest_path, bytes);
    errdefer parsed.deinit(allocator);

    const source = try project_dir.readFileAlloc(io, parsed.main_path, allocator, .limited(max_lua_source_bytes));
    errdefer allocator.free(source);
    parsed.source = source;
    return parsed;
}

pub fn parseGemManifestBytes(allocator: std.mem.Allocator, manifest_path: []const u8, bytes: []const u8) !*LuaGem {
    const buffer = try allocator.allocSentinel(u8, bytes.len, 0);
    defer allocator.free(buffer);
    @memcpy(buffer, bytes);

    var parser = kdl.Parser.init(buffer);
    var depth: i32 = 0;
    var root_seen = false;
    var current_node: ?[]const u8 = null;
    var name: ?[]u8 = null;
    errdefer if (name) |value| allocator.free(value);
    var kind: ?GemKind = null;
    var main: ?[]u8 = null;
    errdefer if (main) |value| allocator.free(value);
    var dependencies = std.ArrayList([]u8).empty;
    errdefer {
        for (dependencies.items) |dependency| allocator.free(dependency);
        dependencies.deinit(allocator);
    }

    while (true) {
        const event = try parser.next();
        switch (event) {
            .node => |node| {
                if (depth == 0) {
                    if (root_seen or !std.mem.eql(u8, node.val, "gem")) return error.InvalidGemManifest;
                    root_seen = true;
                    current_node = node.val;
                    continue;
                }
                if (depth == 1) {
                    if (!std.mem.eql(u8, node.val, "dependency")) return error.UnknownGemManifestField;
                    current_node = node.val;
                    continue;
                }
                return error.InvalidGemManifest;
            },
            .prop => |prop| {
                const value = try decodeValue(allocator, prop.val);
                defer allocator.free(value);
                if (depth == 0) {
                    if (std.mem.eql(u8, prop.key, "name")) {
                        if (name) |existing| allocator.free(existing);
                        name = try allocator.dupe(u8, value);
                    } else if (std.mem.eql(u8, prop.key, "kind")) {
                        kind = parseKind(value) orelse return error.InvalidGemKind;
                    } else if (std.mem.eql(u8, prop.key, "main")) {
                        if (main) |existing| allocator.free(existing);
                        main = try allocator.dupe(u8, value);
                    } else {
                        return error.UnknownGemManifestField;
                    }
                    continue;
                }
                if (depth == 1 and std.mem.eql(u8, current_node orelse "", "dependency")) {
                    if (!std.mem.eql(u8, prop.key, "name")) return error.UnknownGemManifestField;
                    try dependencies.append(allocator, try allocator.dupe(u8, value));
                    continue;
                }
                return error.InvalidGemManifest;
            },
            .child_block_begin => depth += 1,
            .child_block_end => {
                depth -= 1;
                if (depth < 0) return error.InvalidGemManifest;
                current_node = null;
            },
            .arg, .invalid => return error.InvalidGemManifest,
            .eof => break,
        }
    }

    if (!root_seen or depth != 0) return error.InvalidGemManifest;
    if (kind orelse .lua != .lua) return error.InvalidGemKind;
    const resolved_name = name orelse return error.InvalidGemManifest;
    if (!std.mem.startsWith(u8, resolved_name, "gem.")) return error.InvalidGemName;
    const resolved_main = main orelse return error.InvalidGemManifest;
    if (std.fs.path.isAbsolute(resolved_main)) return error.InvalidGemMainPath;

    const manifest_dir = std.fs.path.dirname(manifest_path) orelse "";
    const main_path = try std.fs.path.join(allocator, &.{ manifest_dir, resolved_main });
    errdefer allocator.free(main_path);
    allocator.free(resolved_main);
    main = null;

    const gem = try allocator.create(LuaGem);
    gem.* = .{
        .name = resolved_name,
        .dependencies = try dependencies.toOwnedSlice(allocator),
        .manifest_path = try allocator.dupe(u8, manifest_path),
        .main_path = main_path,
        .source = &.{},
        .kind = .lua,
    };
    name = null;
    return gem;
}

fn registerLuaGem(ctx: *anyopaque, registry: *registry_mod.ServiceRegistry) !void {
    const gem: *LuaGem = @ptrCast(@alignCast(ctx));
    const request_name = try std.fmt.allocPrint(registry.allocator, "{s}.describe", .{gem.name});
    defer registry.allocator.free(request_name);
    try registry.registerRequest(request_name, "Describe a custom Lua gem", .{ .context = gem, .call = describeLuaGem });
    const call_request_name = try std.fmt.allocPrint(registry.allocator, "{s}.call", .{gem.name});
    defer registry.allocator.free(call_request_name);
    try registry.registerRequest(call_request_name, "Call a function on a custom Lua gem; payload is function name newline optional payload", .{ .context = gem, .call = callLuaGem });
    inline for (.{ "validate", "snapshot", "command" }) |function_name| {
        const function_request_name = try std.fmt.allocPrint(registry.allocator, "{s}.{s}", .{ gem.name, function_name });
        defer registry.allocator.free(function_request_name);
        const lua_function_name = comptime if (std.mem.eql(u8, function_name, "command")) "command_request" else if (std.mem.eql(u8, function_name, "snapshot")) "snapshot_request" else function_name;
        try registry.registerRequest(function_request_name, "Call a standard custom Lua gem function", .{ .context = gem, .call = standardLuaGemCall(lua_function_name) });
    }
}

fn startLuaGem(ctx: *anyopaque, world: *framework.World) !void {
    const gem: *LuaGem = @ptrCast(@alignCast(ctx));
    try luajit.runtime().loadGem(gem.name, gem.source);
    const event_name = try std.fmt.allocPrint(world.allocator, "{s}.started", .{gem.name});
    defer world.allocator.free(event_name);
    try world.notifications.publish(event_name, "{}");
}

fn stopLuaGem(ctx: *anyopaque, world: *framework.World) !void {
    const gem: *LuaGem = @ptrCast(@alignCast(ctx));
    const event_name = try std.fmt.allocPrint(world.allocator, "{s}.stopped", .{gem.name});
    defer world.allocator.free(event_name);
    try world.notifications.publish(event_name, "{}");
    luajit.runtime().unloadGem(gem.name);
}

fn deinitLuaGem(ctx: *anyopaque, allocator: std.mem.Allocator) void {
    const gem: *LuaGem = @ptrCast(@alignCast(ctx));
    gem.deinit(allocator);
}

fn describeLuaGem(ctx: ?*anyopaque, allocator: std.mem.Allocator, _: []const u8) ![]u8 {
    const gem: ?*LuaGem = if (ctx) |value| @ptrCast(@alignCast(value)) else null;
    if (gem) |resolved| {
        return std.fmt.allocPrint(allocator, "{{\"kind\":\"lua\",\"name\":\"{s}\",\"main\":\"{s}\"}}", .{ resolved.name, resolved.main_path });
    }
    return allocator.dupe(u8, "{\"kind\":\"lua\"}");
}

fn callLuaGem(ctx: ?*anyopaque, allocator: std.mem.Allocator, payload: []const u8) ![]u8 {
    const gem: *LuaGem = @ptrCast(@alignCast(ctx orelse return error.MissingLuaGemContext));
    const split = std.mem.indexOfScalar(u8, payload, '\n');
    const raw_function_name = if (split) |idx| payload[0..idx] else payload;
    const function_payload = if (split) |idx| payload[idx + 1 ..] else "";
    const function_name = std.mem.trim(u8, raw_function_name, " \t\r\n");
    if (function_name.len == 0) return error.MissingLuaGemFunction;
    return luajit.runtime().callGem(gem.name, function_name, function_payload, allocator);
}

fn standardLuaGemCall(comptime function_name: []const u8) fn (?*anyopaque, std.mem.Allocator, []const u8) anyerror![]u8 {
    return struct {
        fn call(ctx: ?*anyopaque, allocator: std.mem.Allocator, payload: []const u8) ![]u8 {
            const gem: *LuaGem = @ptrCast(@alignCast(ctx orelse return error.MissingLuaGemContext));
            return luajit.runtime().callGem(gem.name, function_name, payload, allocator);
        }
    }.call;
}

fn noopRegister(_: *registry_mod.ServiceRegistry) !void {}
fn noopStart(_: *framework.World) !void {}
fn noopStop(_: *framework.World) !void {}

fn parseKind(value: []const u8) ?GemKind {
    if (std.mem.eql(u8, value, "lua")) return .lua;
    return null;
}

fn decodeValue(allocator: std.mem.Allocator, raw: []const u8) ![]const u8 {
    return kdl.string_utils.makeRealString(allocator, raw);
}

fn openProjectDir(io: std.Io, project_path: []const u8) !std.Io.Dir {
    if (project_path.len == 0) return try std.Io.Dir.cwd().openDir(io, ".", .{});
    if (std.fs.path.isAbsolute(project_path)) {
        return try std.Io.Dir.openDirAbsolute(io, project_path, .{});
    }
    return try std.Io.Dir.cwd().openDir(io, project_path, .{});
}

test "custom gem manifest parses lua module" {
    const bytes =
        \\gem name="gem.test_controller" kind="lua" main="main.lua" {
        \\  dependency name="gem.luajit"
        \\  dependency name="gem.ecs"
        \\}
        \\
    ;
    var gem = try parseGemManifestBytes(std.testing.allocator, "gems/test/gem.kdl", bytes);
    defer gem.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("gem.test_controller", gem.name);
    try std.testing.expectEqualStrings("gems/test/main.lua", gem.main_path);
    try std.testing.expectEqual(@as(usize, 2), gem.dependencies.len);
    try std.testing.expectEqualStrings("gem.luajit", gem.dependencies[0]);
}
