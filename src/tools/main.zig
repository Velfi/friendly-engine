const std = @import("std");
const tools = @import("mod.zig");

pub fn main(init: std.process.Init) !void {
    var args_iter = std.process.Args.Iterator.init(init.minimal.args);
    var args = std.array_list.Managed([]const u8).init(init.gpa);
    defer args.deinit();
    while (args_iter.next()) |arg| {
        try args.append(arg);
    }

    tools.runCli(init.gpa, init.io, args.items) catch |err| {
        std.debug.print("friendly_engine_tools error: {s}\n", .{@errorName(err)});
        if (err == error.InvalidArguments) std.process.exit(1);
        return err;
    };
}
