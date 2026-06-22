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

pub const LuaBackend = struct {
    allocator: std.mem.Allocator,
    state: *c.lua_State,

    pub fn init(allocator: std.mem.Allocator) !*LuaBackend {
        const L = c.luaL_newstate() orelse return error.LuaJitStateCreateFailed;
        c.luaL_openlibs(L);
        try ensureGlobalTable(L, gems_global);
        try ensureGlobalTable(L, states_global);
        try installFeApi(L);

        const created = try allocator.create(LuaBackend);
        created.* = .{
            .allocator = allocator,
            .state = L,
        };
        return created;
    }

    pub fn backend(self: *LuaBackend) luajit.Backend {
        return .{
            .context = self,
            .vtable = &vtable,
        };
    }

    fn deinit(self: *LuaBackend) void {
        c.lua_close(self.state);
        const allocator = self.allocator;
        allocator.destroy(self);
    }

    fn loadGem(self: *LuaBackend, name: []const u8, source: []const u8) !void {
        const name_z = try self.allocator.dupeZ(u8, name);
        defer self.allocator.free(name_z);
        const top = c.lua_gettop(self.state);
        defer c.lua_settop(self.state, top);

        if (c.luaL_loadbuffer(self.state, source.ptr, source.len, name_z.ptr) != 0) {
            logLuaError(self.state, "Lua gem load failed");
            return error.LuaGemLoadFailed;
        }
        if (c.lua_pcall(self.state, 0, 1, 0) != 0) {
            logLuaError(self.state, "Lua gem run failed");
            return error.LuaGemRunFailed;
        }
        if (c.lua_type(self.state, -1) != c.LUA_TTABLE) return error.LuaGemMustReturnTable;

        getGlobalTable(self.state, gems_global);
        c.lua_pushvalue(self.state, -2);
        c.lua_setfield(self.state, -2, name_z.ptr);
    }

    fn eval(self: *LuaBackend, source: []const u8) !void {
        const top = c.lua_gettop(self.state);
        defer c.lua_settop(self.state, top);
        if (c.luaL_loadbuffer(self.state, source.ptr, source.len, "luajit.eval") != 0) {
            logLuaError(self.state, "Lua eval load failed");
            return error.LuaEvalLoadFailed;
        }
        if (c.lua_pcall(self.state, 0, 0, 0) != 0) {
            logLuaError(self.state, "Lua eval run failed");
            return error.LuaEvalRunFailed;
        }
    }

    fn callGem(
        self: *LuaBackend,
        gem_name: []const u8,
        function_name: []const u8,
        payload: []const u8,
        allocator: std.mem.Allocator,
    ) ![]u8 {
        const gem_name_z = try self.allocator.dupeZ(u8, gem_name);
        defer self.allocator.free(gem_name_z);
        const function_name_z = try self.allocator.dupeZ(u8, function_name);
        defer self.allocator.free(function_name_z);
        const top = c.lua_gettop(self.state);
        defer c.lua_settop(self.state, top);

        try pushGemTable(self.state, gem_name_z.ptr);
        const gem_index = c.lua_gettop(self.state);
        c.lua_getfield(self.state, gem_index, function_name_z.ptr);
        if (c.lua_type(self.state, -1) != c.LUA_TFUNCTION) return error.MissingLuaGemFunction;
        c.lua_pushlstring(self.state, payload.ptr, payload.len);
        if (c.lua_pcall(self.state, 1, 1, 0) != 0) {
            logLuaError(self.state, "Lua gem call failed");
            return error.LuaGemCallFailed;
        }

        var out = std.ArrayList(u8).empty;
        errdefer out.deinit(allocator);
        try appendLuaJson(self.state, allocator, &out, -1);
        return out.toOwnedSlice(allocator);
    }

    fn controllerActions(self: *LuaBackend, gem_name: []const u8, allocator: std.mem.Allocator) !luajit.ScriptedControllerActions {
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
        self: *LuaBackend,
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

        if (c.lua_pcall(self.state, 4, 1, 0) != 0) {
            logLuaError(self.state, "Lua controller update failed");
            return error.LuaControllerUpdateFailed;
        }
        if (c.lua_type(self.state, -1) != c.LUA_TTABLE) return error.InvalidLuaControllerResult;
        return readResult(self.state, allocator);
    }
};

const vtable = luajit.BackendVTable{
    .deinit = deinitThunk,
    .load_gem = loadGemThunk,
    .eval = evalThunk,
    .call_gem = callGemThunk,
    .controller_actions = controllerActionsThunk,
    .update_controller = updateControllerThunk,
};

fn deinitThunk(context: *anyopaque) void {
    const self: *LuaBackend = @ptrCast(@alignCast(context));
    self.deinit();
}

fn loadGemThunk(context: *anyopaque, name: []const u8, source: []const u8) !void {
    const self: *LuaBackend = @ptrCast(@alignCast(context));
    try self.loadGem(name, source);
}

fn evalThunk(context: *anyopaque, source: []const u8) !void {
    const self: *LuaBackend = @ptrCast(@alignCast(context));
    try self.eval(source);
}

fn callGemThunk(context: *anyopaque, gem_name: []const u8, function_name: []const u8, payload: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const self: *LuaBackend = @ptrCast(@alignCast(context));
    return self.callGem(gem_name, function_name, payload, allocator);
}

fn controllerActionsThunk(context: *anyopaque, gem_name: []const u8, allocator: std.mem.Allocator) !luajit.ScriptedControllerActions {
    const self: *LuaBackend = @ptrCast(@alignCast(context));
    return self.controllerActions(gem_name, allocator);
}

fn updateControllerThunk(
    context: *anyopaque,
    gem_name: []const u8,
    input: luajit.ScriptedControllerInput,
    allocator: std.mem.Allocator,
) !luajit.ScriptedControllerResult {
    const self: *LuaBackend = @ptrCast(@alignCast(context));
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

fn installFeApi(L: *c.lua_State) !void {
    const source =
        \\fe = fe or {}
        \\fe.time = fe.time or {}
        \\fe.log = fe.log or {}
        \\fe.assets = fe.assets or {}
        \\fe.entities = fe.entities or {}
        \\fe.input = fe.input or {}
        \\fe.ui = fe.ui or {}
        \\fe.audio = fe.audio or {}
        \\fe.persistence = fe.persistence or {}
        \\fe.scene = fe.scene or {}
        \\local function missing(name)
        \\  return function()
        \\    error("Friendly Engine Lua API not implemented: " .. name, 2)
        \\  end
        \\end
        \\fe.time.now = fe.time.now or function() return os.clock() end
        \\fe.log.info = fe.log.info or function(message) print("[fe][info] " .. tostring(message)) end
        \\fe.log.warn = fe.log.warn or function(message) print("[fe][warn] " .. tostring(message)) end
        \\fe.log.error = fe.log.error or function(message) print("[fe][error] " .. tostring(message)) end
        \\fe.assets.exists = fe.assets.exists or missing("assets.exists")
        \\fe.assets.resolve = fe.assets.resolve or missing("assets.resolve")
        \\fe.entities.spawn = fe.entities.spawn or missing("entities.spawn")
        \\fe.entities.destroy = fe.entities.destroy or missing("entities.destroy")
        \\fe.entities.set_transform = fe.entities.set_transform or missing("entities.set_transform")
        \\fe.entities.set_material = fe.entities.set_material or missing("entities.set_material")
        \\fe.input.snapshot = fe.input.snapshot or missing("input.snapshot")
        \\fe.input.ray_pick = fe.input.ray_pick or missing("input.ray_pick")
        \\fe.ui.begin = fe.ui.begin or missing("ui.begin")
        \\fe.ui.text = fe.ui.text or missing("ui.text")
        \\fe.ui.button = fe.ui.button or missing("ui.button")
        \\fe.ui.panel = fe.ui.panel or missing("ui.panel")
        \\fe.ui.finish = fe.ui.finish or missing("ui.finish")
        \\fe.audio.play = fe.audio.play or missing("audio.play")
        \\fe.persistence.save = fe.persistence.save or missing("persistence.save")
        \\fe.persistence.load = fe.persistence.load or missing("persistence.load")
        \\fe.scene.switch = fe.scene.switch or missing("scene.switch")
    ;
    if (c.luaL_loadbuffer(L, source.ptr, source.len, "fe.api") != 0) return error.LuaFeApiLoadFailed;
    if (c.lua_pcall(L, 0, 0, 0) != 0) return error.LuaFeApiInstallFailed;
}

fn logLuaError(L: *c.lua_State, context: []const u8) void {
    var len: usize = 0;
    const ptr = c.lua_tolstring(L, -1, &len);
    if (ptr) |message| {
        std.debug.print("{s}: {s}\n", .{ context, message[0..len] });
    } else {
        std.debug.print("{s}: <non-string Lua error>\n", .{context});
    }
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

fn appendLuaJson(L: *c.lua_State, allocator: std.mem.Allocator, out: *std.ArrayList(u8), index: c_int) anyerror!void {
    const abs_index = absoluteLuaIndex(L, index);
    switch (c.lua_type(L, abs_index)) {
        c.LUA_TNIL => try out.appendSlice(allocator, "null"),
        c.LUA_TBOOLEAN => try out.appendSlice(allocator, if (c.lua_toboolean(L, abs_index) != 0) "true" else "false"),
        c.LUA_TNUMBER => {
            const number_text = try std.fmt.allocPrint(allocator, "{d}", .{c.lua_tonumber(L, abs_index)});
            defer allocator.free(number_text);
            try out.appendSlice(allocator, number_text);
        },
        c.LUA_TSTRING => {
            var len: usize = 0;
            const ptr = c.lua_tolstring(L, abs_index, &len) orelse return error.InvalidLuaStringField;
            try appendJsonString(allocator, out, ptr[0..len]);
        },
        c.LUA_TTABLE => try appendLuaTableJson(L, allocator, out, abs_index),
        else => try appendJsonString(allocator, out, "<unsupported lua value>"),
    }
}

fn appendLuaTableJson(L: *c.lua_State, allocator: std.mem.Allocator, out: *std.ArrayList(u8), index: c_int) anyerror!void {
    const abs_index = absoluteLuaIndex(L, index);
    const array_len = c.lua_objlen(L, abs_index);
    if (array_len > 0) {
        try out.append(allocator, '[');
        var i: usize = 1;
        while (i <= array_len) : (i += 1) {
            if (i > 1) try out.append(allocator, ',');
            c.lua_rawgeti(L, abs_index, @intCast(i));
            try appendLuaJson(L, allocator, out, -1);
            c.lua_pop(L, 1);
        }
        try out.append(allocator, ']');
        return;
    }

    try out.append(allocator, '{');
    var first = true;
    c.lua_pushnil(L);
    while (c.lua_next(L, abs_index) != 0) {
        if (!first) try out.append(allocator, ',');
        first = false;

        if (c.lua_type(L, -2) == c.LUA_TSTRING) {
            var len: usize = 0;
            const key_ptr = c.lua_tolstring(L, -2, &len) orelse return error.InvalidLuaStringField;
            try appendJsonString(allocator, out, key_ptr[0..len]);
        } else if (c.lua_type(L, -2) == c.LUA_TNUMBER) {
            const key_text = try std.fmt.allocPrint(allocator, "\"{d}\"", .{c.lua_tonumber(L, -2)});
            defer allocator.free(key_text);
            try out.appendSlice(allocator, key_text);
        } else {
            try appendJsonString(allocator, out, "unsupported_key");
        }
        try out.append(allocator, ':');
        try appendLuaJson(L, allocator, out, -1);
        c.lua_pop(L, 1);
    }
    try out.append(allocator, '}');
}

fn absoluteLuaIndex(L: *c.lua_State, index: c_int) c_int {
    if (index > 0) return index;
    return c.lua_gettop(L) + index + 1;
}

fn appendJsonString(allocator: std.mem.Allocator, out: *std.ArrayList(u8), value: []const u8) !void {
    try out.append(allocator, '"');
    for (value) |ch| {
        switch (ch) {
            '"' => try out.appendSlice(allocator, "\\\""),
            '\\' => try out.appendSlice(allocator, "\\\\"),
            '\n' => try out.appendSlice(allocator, "\\n"),
            '\r' => try out.appendSlice(allocator, "\\r"),
            '\t' => try out.appendSlice(allocator, "\\t"),
            else => try out.append(allocator, ch),
        }
    }
    try out.append(allocator, '"');
}
