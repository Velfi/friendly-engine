const std = @import("std");

pub fn main() void {
    std.debug.print(
        "Use `zig build run-client`, `zig build run-server`, or `zig build run-tools -- <command>`.\n",
        .{},
    );
}
