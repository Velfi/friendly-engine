const std = @import("std");
const framework = @import("../../framework/mod.zig");
const registry = @import("../registry.zig");

pub const module_name = "gem.editor_prop";
pub const dependencies = [_][]const u8{};

pub fn register(_: *registry.ServiceRegistry) !void {}

pub fn start(world: *framework.World) !void {
    try world.notifications.publish("gem.editor_prop.started", "{}");
}

pub fn stop(world: *framework.World) !void {
    try world.notifications.publish("gem.editor_prop.stopped", "{}");
}

test "editor prop gem has stable name" {
    try std.testing.expectEqualStrings("gem.editor_prop", module_name);
}
