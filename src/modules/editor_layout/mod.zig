const std = @import("std");
const framework = @import("../../framework/mod.zig");
const registry = @import("../registry.zig");

pub const module_name = "gem.editor_layout";
pub const dependencies = [_][]const u8{};

pub fn register(_: *registry.ServiceRegistry) !void {}

pub fn start(world: *framework.World) !void {
    try world.notifications.publish("gem.editor_layout.started", "{}");
}

pub fn stop(world: *framework.World) !void {
    try world.notifications.publish("gem.editor_layout.stopped", "{}");
}

test "editor layout gem has stable name" {
    try std.testing.expectEqualStrings("gem.editor_layout", module_name);
}
