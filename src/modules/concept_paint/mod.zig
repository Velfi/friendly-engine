const std = @import("std");
const framework = @import("../../framework/mod.zig");
const registry = @import("../registry.zig");

pub const module_name = "gem.concept_paint";
pub const dependencies = [_][]const u8{
    "gem.editor_world",
    "gem.editor_layout",
    "gem.editor_architecture",
    "gem.editor_prop",
};

pub fn register(_: *registry.ServiceRegistry) !void {}

pub fn start(world: *framework.World) !void {
    try world.notifications.publish("gem.concept_paint.started", "{}");
}

pub fn stop(world: *framework.World) !void {
    try world.notifications.publish("gem.concept_paint.stopped", "{}");
}

test "concept paint gem has stable name" {
    try std.testing.expectEqualStrings("gem.concept_paint", module_name);
}
