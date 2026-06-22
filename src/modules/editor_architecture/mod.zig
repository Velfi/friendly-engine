const std = @import("std");
const framework = @import("../../framework/mod.zig");
const registry = @import("../registry.zig");

pub const module_name = "gem.editor_architecture";
pub const dependencies = [_][]const u8{
    "gem.sectors",
    "gem.buildings",
    "gem.local_csg",
};

pub fn register(_: *registry.ServiceRegistry) !void {}

pub fn start(world: *framework.World) !void {
    try world.notifications.publish("gem.editor_architecture.started", "{}");
}

pub fn stop(world: *framework.World) !void {
    try world.notifications.publish("gem.editor_architecture.stopped", "{}");
}

test "editor architecture gem has stable name" {
    try std.testing.expectEqualStrings("gem.editor_architecture", module_name);
}
