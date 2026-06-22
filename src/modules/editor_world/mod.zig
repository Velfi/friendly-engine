const std = @import("std");
const framework = @import("../../framework/mod.zig");
const registry = @import("../registry.zig");

pub const module_name = "gem.editor_world";
pub const dependencies = [_][]const u8{
    "gem.terrain",
    "gem.splines",
    "gem.scatter",
    "gem.atmosphere",
    "gem.sectors",
    "gem.buildings",
};

pub fn register(_: *registry.ServiceRegistry) !void {}

pub fn start(world: *framework.World) !void {
    try world.notifications.publish("gem.editor_world.started", "{}");
}

pub fn stop(world: *framework.World) !void {
    try world.notifications.publish("gem.editor_world.stopped", "{}");
}

test "editor world gem has stable name" {
    try std.testing.expectEqualStrings("gem.editor_world", module_name);
}
