const std = @import("std");
const framework = @import("../../framework/mod.zig");
const controller_rumble = @import("mod.zig");

test "controller rumble queues validated rumble commands" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();

    var queue = controller_rumble.Queue.init(std.testing.allocator);
    defer queue.deinit();

    try queue.submit(&world, .{
        .device_id = 4,
        .low_frequency_strength = 0.25,
        .high_frequency_strength = 0.75,
        .duration_ms = 120,
    });

    try std.testing.expectEqual(@as(usize, 1), queue.commands.items.len);
    try std.testing.expectEqual(@as(controller_rumble.DeviceId, 4), queue.commands.items[0].rumble.device_id);
    try std.testing.expectEqualStrings(controller_rumble.event_topic, world.notifications.events.items[0].name);
    try std.testing.expect(std.mem.indexOf(u8, world.notifications.events.items[0].payload, "\"type\":\"rumble\"") != null);
}

test "controller rumble queues stop commands" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();

    var queue = controller_rumble.Queue.init(std.testing.allocator);
    defer queue.deinit();

    try queue.stopDevice(&world, 3);

    try std.testing.expectEqual(@as(usize, 1), queue.commands.items.len);
    try std.testing.expectEqual(@as(controller_rumble.DeviceId, 3), queue.commands.items[0].stop.device_id);
    try std.testing.expect(std.mem.indexOf(u8, world.notifications.events.items[0].payload, "\"type\":\"stop\"") != null);
}

test "controller rumble rejects invalid rumble commands" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();

    var queue = controller_rumble.Queue.init(std.testing.allocator);
    defer queue.deinit();

    try std.testing.expectError(error.InvalidRumbleCommand, queue.submit(&world, .{
        .device_id = 1,
        .low_frequency_strength = -0.1,
        .high_frequency_strength = 0.5,
        .duration_ms = 100,
    }));
    try std.testing.expectError(error.InvalidRumbleCommand, queue.submit(&world, .{
        .device_id = 1,
        .low_frequency_strength = 0.1,
        .high_frequency_strength = 1.1,
        .duration_ms = 100,
    }));
    try std.testing.expectError(error.InvalidRumbleCommand, queue.submit(&world, .{
        .device_id = 1,
        .low_frequency_strength = 0.1,
        .high_frequency_strength = 0.5,
        .duration_ms = 0,
    }));
    try std.testing.expectEqual(@as(usize, 0), queue.commands.items.len);
}

test "controller rumble gem publishes lifecycle events" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();

    try controller_rumble.start(&world);
    try controller_rumble.stop(&world);

    try std.testing.expectEqualStrings("gem.controller_rumble.started", world.notifications.events.items[0].name);
    try std.testing.expectEqualStrings("gem.controller_rumble.stopped", world.notifications.events.items[1].name);
}
