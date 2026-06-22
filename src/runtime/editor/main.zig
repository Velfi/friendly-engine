const std = @import("std");
const friendly_engine = @import("friendly_engine");
const app = @import("app.zig");

pub const std_options: std.Options = .{
    .logFn = friendly_engine.core.logging.logFn,
};

const log = std.log.scoped(.editor);

pub fn main(init: std.process.Init) !void {
    app.runEditor(init) catch |err| {
        log.err("runtime exited with error: {s}", .{@errorName(err)});
        return err;
    };
}
