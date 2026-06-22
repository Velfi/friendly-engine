const std = @import("std");
const core = @import("../../core/mod.zig");
const framework = @import("../../framework/mod.zig");
const game = @import("../../game/mod.zig");

pub const module_name = "gem.luajit";
pub const dependencies = [_][]const u8{};

pub const ScriptedControllerActions = struct {
    move_forward: []u8,
    move_backward: []u8,
    strafe_left: []u8,
    strafe_right: []u8,
    sprint: []u8,
    crouch: []u8,
    jump: []u8,
    climb: ?[]u8 = null,
    ascend: []u8,
    descend: []u8,
    interact: []u8,

    pub fn deinit(self: *ScriptedControllerActions, allocator: std.mem.Allocator) void {
        allocator.free(self.move_forward);
        allocator.free(self.move_backward);
        allocator.free(self.strafe_left);
        allocator.free(self.strafe_right);
        allocator.free(self.sprint);
        allocator.free(self.crouch);
        allocator.free(self.jump);
        if (self.climb) |value| allocator.free(value);
        allocator.free(self.ascend);
        allocator.free(self.descend);
        allocator.free(self.interact);
        self.* = undefined;
    }
};

pub const ScriptedControllerInput = struct {
    dt_seconds: f32,
    position: core.math.Vec3f,
    camera_yaw_rad: f32 = 0.0,
    camera_pitch_rad: f32 = 0.0,
    move_forward: bool = false,
    move_backward: bool = false,
    strafe_left: bool = false,
    strafe_right: bool = false,
    sprint: bool = false,
    crouch: bool = false,
    jump_pressed: bool = false,
    climb: bool = false,
    ascend: bool = false,
    descend: bool = false,
    interact_pressed: bool = false,
    grounded: bool = true,
};

pub const ScriptedCamera = struct {
    target: core.math.Vec3f,
    offset: core.math.Vec3f,
};

pub const ScriptedControllerResult = struct {
    mode: ?[]u8 = null,
    velocity_mps: core.math.Vec3f = .{ .x = 0, .y = 0, .z = 0 },
    camera: ?ScriptedCamera = null,
    jumped: bool = false,
    stamina_seconds: f32 = 0.0,
    interact_requested: bool = false,

    pub fn deinit(self: *ScriptedControllerResult, allocator: std.mem.Allocator) void {
        if (self.mode) |mode| allocator.free(mode);
        self.* = undefined;
    }
};

pub const BackendVTable = struct {
    deinit: *const fn (context: *anyopaque) void,
    load_gem: *const fn (context: *anyopaque, name: []const u8, source: []const u8) anyerror!void,
    eval: *const fn (context: *anyopaque, source: []const u8) anyerror!void,
    call_gem: *const fn (context: *anyopaque, gem_name: []const u8, function_name: []const u8, payload: []const u8, allocator: std.mem.Allocator) anyerror![]u8,
    controller_actions: *const fn (context: *anyopaque, gem_name: []const u8, allocator: std.mem.Allocator) anyerror!ScriptedControllerActions,
    update_controller: *const fn (context: *anyopaque, gem_name: []const u8, input: ScriptedControllerInput, allocator: std.mem.Allocator) anyerror!ScriptedControllerResult,
};

pub const Backend = struct {
    context: *anyopaque,
    vtable: *const BackendVTable,
};

pub const Runtime = struct {
    allocator: ?std.mem.Allocator = null,
    backend: ?Backend = null,
    eval_count: usize = 0,
    loaded_gems: std.ArrayList(LoadedGem) = .empty,

    pub const LoadedGem = struct {
        name: []u8,
        source: []u8,

        pub fn deinit(self: *LoadedGem, allocator: std.mem.Allocator) void {
            allocator.free(self.name);
            allocator.free(self.source);
        }
    };

    pub fn init(allocator: std.mem.Allocator) Runtime {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Runtime) void {
        self.detachBackend();
        const allocator = self.allocator orelse return;
        for (self.loaded_gems.items) |*gem| gem.deinit(allocator);
        self.loaded_gems.deinit(allocator);
        self.* = .{};
    }

    pub fn attachBackend(self: *Runtime, backend: Backend) !void {
        self.detachBackend();
        self.backend = backend;
        for (self.loaded_gems.items) |gem| {
            try backend.vtable.load_gem(backend.context, gem.name, gem.source);
        }
    }

    pub fn detachBackend(self: *Runtime) void {
        if (self.backend) |backend| backend.vtable.deinit(backend.context);
        self.backend = null;
    }

    pub fn hasBackend(self: Runtime) bool {
        return self.backend != null;
    }

    pub fn eval(self: *Runtime, source: []const u8) !void {
        if (source.len == 0) return error.EmptyScript;
        const backend = self.backend orelse return error.LuaJitBackendMissing;
        try backend.vtable.eval(backend.context, source);
        self.eval_count += 1;
    }

    pub fn loadGem(self: *Runtime, name: []const u8, source: []const u8) !void {
        if (name.len == 0) return error.InvalidLuaGemName;
        if (source.len == 0) return error.EmptyScript;
        const allocator = self.allocator orelse return error.LuaJitRuntimeNotStarted;
        for (self.loaded_gems.items) |existing| {
            if (std.mem.eql(u8, existing.name, name)) return error.LuaGemAlreadyLoaded;
        }
        try self.loaded_gems.append(allocator, .{
            .name = try allocator.dupe(u8, name),
            .source = try allocator.dupe(u8, source),
        });
        if (self.backend) |backend| try backend.vtable.load_gem(backend.context, name, source);
    }

    pub fn unloadGem(self: *Runtime, name: []const u8) void {
        const allocator = self.allocator orelse return;
        for (self.loaded_gems.items, 0..) |*existing, index| {
            if (!std.mem.eql(u8, existing.name, name)) continue;
            existing.deinit(allocator);
            _ = self.loaded_gems.orderedRemove(index);
            return;
        }
    }

    pub fn loadedGemCount(self: Runtime) usize {
        return self.loaded_gems.items.len;
    }

    pub fn controllerActions(self: *Runtime, gem_name: []const u8, allocator: std.mem.Allocator) !ScriptedControllerActions {
        const backend = self.backend orelse return error.LuaJitBackendMissing;
        return backend.vtable.controller_actions(backend.context, gem_name, allocator);
    }

    pub fn callGem(self: *Runtime, gem_name: []const u8, function_name: []const u8, payload: []const u8, allocator: std.mem.Allocator) ![]u8 {
        const backend = self.backend orelse return error.LuaJitBackendMissing;
        return backend.vtable.call_gem(backend.context, gem_name, function_name, payload, allocator);
    }

    pub fn updateController(self: *Runtime, gem_name: []const u8, input: ScriptedControllerInput, allocator: std.mem.Allocator) !ScriptedControllerResult {
        const backend = self.backend orelse return error.LuaJitBackendMissing;
        return backend.vtable.update_controller(backend.context, gem_name, input, allocator);
    }
};

var runtime_state = Runtime{};

pub fn runtime() *Runtime {
    return &runtime_state;
}

pub fn register(registry: anytype) !void {
    try registry.registerRequest("luajit.describe", "Summarize LuaJIT scripting runtime state", .{
        .call = luajitDescribe,
    });
    try registry.registerRequest("luajit.eval", "Evaluate a LuaJIT script chunk; payload is script source", .{
        .call = luajitEval,
    });
}

pub fn start(world: *framework.World) !void {
    runtime_state.deinit();
    runtime_state = Runtime.init(world.allocator);
    try world.notifications.publish("gem.luajit.started", "{}");
}

pub fn stop(world: *framework.World) !void {
    runtime_state.detachBackend();
    runtime_state.deinit();
    try world.notifications.publish("gem.luajit.stopped", "{}");
}

fn luajitDescribe(_: ?*anyopaque, allocator: std.mem.Allocator, payload: []const u8) ![]u8 {
    _ = payload;
    const active = game.activeWorld() != null;
    return std.fmt.allocPrint(
        allocator,
        "{{\"active_world\":{},\"backend\":\"LuaJIT\",\"backend_attached\":{},\"eval_count\":{d},\"loaded_gem_count\":{d}}}",
        .{ active, runtime_state.hasBackend(), runtime_state.eval_count, runtime_state.loadedGemCount() },
    );
}

fn luajitEval(_: ?*anyopaque, allocator: std.mem.Allocator, payload: []const u8) ![]u8 {
    _ = game.activeWorld() orelse return error.NoActiveWorld;
    try runtime_state.eval(payload);
    return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"eval_count\":{d}}}", .{runtime_state.eval_count});
}

test "luajit gem has stable name" {
    try std.testing.expectEqualStrings("gem.luajit", module_name);
}

test "luajit describe reports missing backend loudly" {
    runtime_state = .{};

    const response = try luajitDescribe(null, std.testing.allocator, "{}");
    defer std.testing.allocator.free(response);

    try std.testing.expect(std.mem.indexOf(u8, response, "\"backend\":\"LuaJIT\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "\"backend_attached\":false") != null);
}

test "luajit eval requires an attached backend" {
    runtime_state = .{};
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();
    game.setActiveWorld(&world);

    try std.testing.expectError(
        error.LuaJitBackendMissing,
        luajitEval(null, std.testing.allocator, "return 42"),
    );
}
