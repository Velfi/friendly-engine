const framework = @import("../../framework/mod.zig");

pub const module_name = "gem.ecs";
pub const dependencies = [_][]const u8{};

pub const Entity = framework.ecs.Entity;
pub const World = framework.ecs.World;
pub const ComponentStorage = framework.ecs.ComponentStorage;

pub fn register(registry: anytype) !void {
    _ = registry;
}

pub fn start(world: *framework.World) !void {
    try world.notifications.publish("gem.ecs.started", "{}");
}

pub fn stop(world: *framework.World) !void {
    try world.notifications.publish("gem.ecs.stopped", "{}");
}

comptime {
    _ = @import("mod_tests.zig");
}
