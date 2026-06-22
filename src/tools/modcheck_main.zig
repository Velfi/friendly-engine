const std = @import("std");
const module_size = @import("module_size.zig");

pub fn main(init: std.process.Init) !void {
    var args_iter = std.process.Args.Iterator.init(init.minimal.args);
    var args = std.array_list.Managed([]const u8).init(init.gpa);
    defer args.deinit();
    while (args_iter.next()) |arg| {
        try args.append(arg);
    }

    module_size.runCli(init.gpa, init.io, args.items) catch |err| switch (err) {
        error.InvalidArguments => std.process.exit(1),
        error.OversizedModules => std.process.exit(1),
        else => return err,
    };
}
