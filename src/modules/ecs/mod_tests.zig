const std = @import("std");
const framework = @import("../../framework/mod.zig");
const ecs = @import("mod.zig");

test "ecs gem re-exports framework entity storage" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();

    const entity = world.spawnEntity();
    var storage = ecs.ComponentStorage(struct { value: u32 }).init(std.testing.allocator);
    defer storage.deinit();

    try storage.set(entity, .{ .value = 42 });
    try std.testing.expectEqual(@as(u32, 42), storage.get(entity).?.value);
}

test "ecs gem publishes lifecycle events" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();

    try ecs.start(&world);
    try ecs.stop(&world);

    try std.testing.expectEqualStrings("gem.ecs.started", world.notifications.events.items[0].name);
    try std.testing.expectEqualStrings("gem.ecs.stopped", world.notifications.events.items[1].name);
}
