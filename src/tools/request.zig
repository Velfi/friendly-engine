const std = @import("std");
const friendly_engine = @import("friendly_engine");
const lua_backend_mod = @import("lua_backend");

const Options = struct {
    project_path: []const u8 = ".",
    config_path: []const u8 = "engine.kdl",
    name: []const u8 = "",
    payload: []const u8 = "{}",
};

pub fn runCli(allocator: std.mem.Allocator, io: std.Io, args: []const []const u8) !void {
    var options = Options{};
    try parseArgs(&options, args);
    if (options.name.len == 0) return error.InvalidArguments;

    var boot = try friendly_engine.bootstrap.bootWorldInProject(allocator, io, .{
        .enable_renderer = false,
        .enable_physics = false,
    }, options.project_path, options.config_path);
    defer boot.deinit();

    var lua_backend = try lua_backend_mod.LuaBackend.init(allocator);
    try friendly_engine.modules.luajit.runtime().attachBackend(lua_backend.backend());

    const response = try boot.world.requests.request(options.name, options.payload);
    defer allocator.free(response);
    std.debug.print("{s}\n", .{response});
}

fn parseArgs(options: *Options, args: []const []const u8) !void {
    var i: usize = 0;
    while (i < args.len) {
        const flag = args[i];
        i += 1;
        if (i >= args.len) return error.InvalidArguments;
        const value = args[i];
        i += 1;

        if (std.mem.eql(u8, flag, "--project")) {
            options.project_path = value;
        } else if (std.mem.eql(u8, flag, "--config")) {
            options.config_path = value;
        } else if (std.mem.eql(u8, flag, "--name")) {
            options.name = value;
        } else if (std.mem.eql(u8, flag, "--payload")) {
            options.payload = value;
        } else {
            return error.InvalidArguments;
        }
    }
}
