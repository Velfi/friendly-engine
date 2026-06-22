const std = @import("std");

pub fn logFn(
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    std.log.defaultLog(level, scope, "friendly-engine: " ++ format, args);
}
