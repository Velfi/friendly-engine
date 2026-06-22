const std = @import("std");
const friendly_engine = @import("friendly_engine");
const luajit = friendly_engine.modules.luajit;

const c = @cImport({
    @cInclude("lua.h");
    @cInclude("lauxlib.h");
    @cInclude("lualib.h");
});

const gems_global = "__friendly_engine_gems";
const states_global = "__friendly_engine_controller_states";

pub const LuaControllerBackend = struct {
    allocator: std.mem.Allocator,
    state: *c.lua_State,

    pub fn init(allocator: std.mem.Allocator) !*LuaControllerBackend {
        const L = c.luaL_newstate() orelse return error.LuaJitStateCreateFailed;
        c.luaL_openlibs(L);
        try ensureGlobalTable(L, gems_global);
        try ensureGlobalTable(L, states_global);

        const created = try allocator.create(LuaControllerBackend);
        created.* = .{
            .allocator = allocator,
            .state = L,
        };
        return created;
    }

    pub fn backend(self: *LuaControllerBackend) luajit.Backend {
        return .{
            .context = self,
            .vtable = &vtable,
        };
    }

    fn deinit(self: *LuaControllerBackend) void {
        c.lua_close(self.state);
        const allocator = self.allocator;
        allocator.destroy(self);
    }

    fn loadGem(self: *LuaControllerBackend, name: []const u8, source: []const u8) !void {
        const name_z = try self.allocator.dupeZ(u8, name);
        defer self.allocator.free(name_z);
        const top = c.lua_gettop(self.state);
        defer c.lua_settop(self.state, top);

        if (c.luaL_loadbuffer(self.state, source.ptr, source.len, name_z.ptr) != 0) return error.LuaGemLoadFailed;
        if (c.lua_pcall(self.state, 0, 1, 0) != 0) return error.LuaGemRunFailed;
        if (c.lua_type(self.state, -1) != c.LUA_TTABLE) return error.LuaGemMustReturnTable;

        getGlobalTable(self.state, gems_global);
        c.lua_pushvalue(self.state, -2);
        c.lua_setfield(self.state, -2, name_z.ptr);
    }

    fn eval(self: *LuaControllerBackend, source: []const u8) !void {
        const top = c.lua_gettop(self.state);
        defer c.lua_settop(self.state, top);
        if (c.luaL_loadbuffer(self.state, source.ptr, source.len, "luajit.eval") != 0) return error.LuaEvalLoadFailed;
        if (c.lua_pcall(self.state, 0, 0, 0) != 0) return error.LuaEvalRunFailed;
    }

    fn controllerActions(self: *LuaControllerBackend, gem_name: []const u8, allocator: std.mem.Allocator) !luajit.ScriptedControllerActions {
        const gem_name_z = try self.allocator.dupeZ(u8, gem_name);
        defer self.allocator.free(gem_name_z);
        const top = c.lua_gettop(self.state);
        defer c.lua_settop(self.state, top);

        try pushGemTable(self.state, gem_name_z.ptr);
        c.lua_getfield(self.state, -1, "actions");
        if (c.lua_type(self.state, -1) != c.LUA_TTABLE) return error.MissingLuaControllerActions;

        var actions = luajit.ScriptedControllerActions{
            .move_forward = try readRequiredString(self.state, allocator, "move_forward"),
            .move_backward = try readRequiredString(self.state, allocator, "move_backward"),
            .strafe_left = try readRequiredString(self.state, allocator, "strafe_left"),
            .strafe_right = try readRequiredString(self.state, allocator, "strafe_right"),
            .sprint = try readRequiredString(self.state, allocator, "sprint"),
            .crouch = try readRequiredString(self.state, allocator, "crouch"),
            .jump = try readRequiredString(self.state, allocator, "jump"),
            .climb = try readOptionalString(self.state, allocator, "climb"),
            .ascend = try readRequiredString(self.state, allocator, "ascend"),
            .descend = try readRequiredString(self.state, allocator, "descend"),
            .interact = try readRequiredString(self.state, allocator, "interact"),
        };
        errdefer actions.deinit(allocator);
        return actions;
    }

    fn updateController(
        self: *LuaControllerBackend,
        gem_name: []const u8,
        input: luajit.ScriptedControllerInput,
        allocator: std.mem.Allocator,
    ) !luajit.ScriptedControllerResult {
        const gem_name_z = try self.allocator.dupeZ(u8, gem_name);
        defer self.allocator.free(gem_name_z);
        const top = c.lua_gettop(self.state);
        defer c.lua_settop(self.state, top);

        try pushGemTable(self.state, gem_name_z.ptr);
        const gem_index = c.lua_gettop(self.state);
        c.lua_getfield(self.state, gem_index, "update");
        if (c.lua_type(self.state, -1) != c.LUA_TFUNCTION) return error.MissingLuaControllerUpdate;
        pushControllerState(self.state, gem_name_z.ptr);
        pushVec3(self.state, input.position);
        pushInput(self.state, input);
        try pushDefaultConfig(self.state, gem_index);

        if (c.lua_pcall(self.state, 4, 1, 0) != 0) return error.LuaControllerUpdateFailed;
        if (c.lua_type(self.state, -1) != c.LUA_TTABLE) return error.InvalidLuaControllerResult;
        return readResult(self.state, allocator);
    }
};

const vtable = luajit.BackendVTable{
    .deinit = deinitThunk,
    .load_gem = loadGemThunk,
    .eval = evalThunk,
    .controller_actions = controllerActionsThunk,
    .update_controller = updateControllerThunk,
};

fn deinitThunk(context: *anyopaque) void {
    const self: *LuaControllerBackend = @ptrCast(@alignCast(context));
    self.deinit();
}

fn loadGemThunk(context: *anyopaque, name: []const u8, source: []const u8) !void {
    const self: *LuaControllerBackend = @ptrCast(@alignCast(context));
    try self.loadGem(name, source);
}

fn evalThunk(context: *anyopaque, source: []const u8) !void {
    const self: *LuaControllerBackend = @ptrCast(@alignCast(context));
    try self.eval(source);
}

fn controllerActionsThunk(context: *anyopaque, gem_name: []const u8, allocator: std.mem.Allocator) !luajit.ScriptedControllerActions {
    const self: *LuaControllerBackend = @ptrCast(@alignCast(context));
    return self.controllerActions(gem_name, allocator);
}

fn updateControllerThunk(
    context: *anyopaque,
    gem_name: []const u8,
    input: luajit.ScriptedControllerInput,
    allocator: std.mem.Allocator,
) !luajit.ScriptedControllerResult {
    const self: *LuaControllerBackend = @ptrCast(@alignCast(context));
    return self.updateController(gem_name, input, allocator);
}

fn ensureGlobalTable(L: *c.lua_State, name: [:0]const u8) !void {
    c.lua_getfield(L, c.LUA_GLOBALSINDEX, name.ptr);
    if (c.lua_type(L, -1) == c.LUA_TTABLE) {
        c.lua_settop(L, -2);
        return;
    }
    c.lua_settop(L, -2);
    c.lua_createtable(L, 0, 8);
    c.lua_setfield(L, c.LUA_GLOBALSINDEX, name.ptr);
}

fn getGlobalTable(L: *c.lua_State, name: [:0]const u8) void {
    c.lua_getfield(L, c.LUA_GLOBALSINDEX, name.ptr);
}

fn pushGemTable(L: *c.lua_State, gem_name: [*:0]const u8) !void {
    getGlobalTable(L, gems_global);
    c.lua_getfield(L, -1, gem_name);
    if (c.lua_type(L, -1) != c.LUA_TTABLE) return error.UnknownLuaGem;
}

fn pushControllerState(L: *c.lua_State, gem_name: [*:0]const u8) void {
    getGlobalTable(L, states_global);
    c.lua_getfield(L, -1, gem_name);
    if (c.lua_type(L, -1) != c.LUA_TTABLE) {
        c.lua_settop(L, -2);
        c.lua_createtable(L, 0, 8);
        c.lua_pushvalue(L, -1);
        c.lua_setfield(L, -3, gem_name);
    }
    c.lua_remove(L, -2);
}

fn pushDefaultConfig(L: *c.lua_State, gem_index: c_int) !void {
    c.lua_getfield(L, gem_index, "default_config");
    if (c.lua_type(L, -1) != c.LUA_TFUNCTION) return error.MissingLuaControllerConfig;
    if (c.lua_pcall(L, 0, 1, 0) != 0) return error.LuaControllerConfigFailed;
    if (c.lua_type(L, -1) != c.LUA_TTABLE) return error.InvalidLuaControllerConfig;
}

fn pushVec3(L: *c.lua_State, value: friendly_engine.core.math.Vec3f) void {
    c.lua_createtable(L, 0, 3);
    pushNumberField(L, "x", value.x);
    pushNumberField(L, "y", value.y);
    pushNumberField(L, "z", value.z);
}

fn pushInput(L: *c.lua_State, input: luajit.ScriptedControllerInput) void {
    c.lua_createtable(L, 0, 19);
    pushNumberField(L, "dt_seconds", input.dt_seconds);
    pushNumberField(L, "camera_yaw_rad", input.camera_yaw_rad);
    pushNumberField(L, "camera_pitch_rad", input.camera_pitch_rad);
    pushBoolField(L, "move_forward", input.move_forward);
    pushBoolField(L, "move_backward", input.move_backward);
    pushBoolField(L, "strafe_left", input.strafe_left);
    pushBoolField(L, "strafe_right", input.strafe_right);
    pushBoolField(L, "sprint", input.sprint);
    pushBoolField(L, "crouch", input.crouch);
    pushBoolField(L, "jump_pressed", input.jump_pressed);
    pushBoolField(L, "climb", input.climb);
    pushBoolField(L, "ascend", input.ascend);
    pushBoolField(L, "descend", input.descend);
    pushBoolField(L, "interact_pressed", input.interact_pressed);
    pushBoolField(L, "grounded", input.grounded);
}

fn pushNumberField(L: *c.lua_State, field: [:0]const u8, value: f32) void {
    c.lua_pushnumber(L, value);
    c.lua_setfield(L, -2, field.ptr);
}

fn pushBoolField(L: *c.lua_State, field: [:0]const u8, value: bool) void {
    c.lua_pushboolean(L, if (value) 1 else 0);
    c.lua_setfield(L, -2, field.ptr);
}

fn readResult(L: *c.lua_State, allocator: std.mem.Allocator) !luajit.ScriptedControllerResult {
    var result = luajit.ScriptedControllerResult{};
    result.mode = try readOptionalString(L, allocator, "mode");
    result.velocity_mps = try readVec3Field(L, "velocity_mps") orelse result.velocity_mps;
    result.jumped = readBoolField(L, "jumped");
    result.stamina_seconds = readNumberField(L, "stamina_seconds") orelse 0.0;
    result.interact_requested = readBoolField(L, "interact_requested");

    c.lua_getfield(L, -1, "camera");
    if (c.lua_type(L, -1) == c.LUA_TTABLE) {
        const target = try readVec3Field(L, "target") orelse return error.InvalidLuaControllerCamera;
        const offset = try readVec3Field(L, "offset") orelse return error.InvalidLuaControllerCamera;
        result.camera = .{ .target = target, .offset = offset };
    }
    c.lua_settop(L, -2);
    return result;
}

fn readRequiredString(L: *c.lua_State, allocator: std.mem.Allocator, field: [:0]const u8) ![]u8 {
    return (try readOptionalString(L, allocator, field)) orelse return error.MissingLuaStringField;
}

fn readOptionalString(L: *c.lua_State, allocator: std.mem.Allocator, field: [:0]const u8) !?[]u8 {
    c.lua_getfield(L, -1, field.ptr);
    defer c.lua_settop(L, -2);
    if (c.lua_type(L, -1) == c.LUA_TNIL) return null;
    if (c.lua_type(L, -1) != c.LUA_TSTRING) return error.InvalidLuaStringField;
    var len: usize = 0;
    const ptr = c.lua_tolstring(L, -1, &len) orelse return error.InvalidLuaStringField;
    return try allocator.dupe(u8, ptr[0..len]);
}

fn readVec3Field(L: *c.lua_State, field: [:0]const u8) !?friendly_engine.core.math.Vec3f {
    c.lua_getfield(L, -1, field.ptr);
    defer c.lua_settop(L, -2);
    if (c.lua_type(L, -1) == c.LUA_TNIL) return null;
    if (c.lua_type(L, -1) != c.LUA_TTABLE) return error.InvalidLuaVec3Field;
    return .{
        .x = readNumberField(L, "x") orelse return error.InvalidLuaVec3Field,
        .y = readNumberField(L, "y") orelse return error.InvalidLuaVec3Field,
        .z = readNumberField(L, "z") orelse return error.InvalidLuaVec3Field,
    };
}

fn readNumberField(L: *c.lua_State, field: [:0]const u8) ?f32 {
    c.lua_getfield(L, -1, field.ptr);
    defer c.lua_settop(L, -2);
    if (c.lua_type(L, -1) != c.LUA_TNUMBER) return null;
    return @floatCast(c.lua_tonumber(L, -1));
}

fn readBoolField(L: *c.lua_State, field: [:0]const u8) bool {
    c.lua_getfield(L, -1, field.ptr);
    defer c.lua_settop(L, -2);
    return c.lua_toboolean(L, -1) != 0;
}
