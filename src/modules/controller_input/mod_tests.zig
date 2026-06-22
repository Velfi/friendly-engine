const std = @import("std");
const framework = @import("../../framework/mod.zig");
const controller_input = @import("mod.zig");

test "controller input maps button events to actions" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();

    var controller = controller_input.Controller.init(std.testing.allocator);
    defer controller.deinit();
    try controller.bind(.{ .action_name = "jump", .trigger = .{ .button = .south } });

    try controller.feed(&world, .{ .button_down = .{ .device_id = 1, .button = .south } });
    try std.testing.expectEqual(
        framework.input.ActionState.pressed,
        world.input.getActionState(framework.input.InputSystem.actionId("jump")),
    );
    try std.testing.expect(controller.triggerIsDown(.{ .button = .south }));

    try controller.settleActionStates(&world.input);
    try std.testing.expectEqual(
        framework.input.ActionState.held,
        world.input.getActionState(framework.input.InputSystem.actionId("jump")),
    );

    try controller.feed(&world, .{ .button_up = .{ .device_id = 1, .button = .south } });
    try std.testing.expectEqual(
        framework.input.ActionState.released,
        world.input.getActionState(framework.input.InputSystem.actionId("jump")),
    );
}

test "controller input maps axis thresholds to actions" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();

    var controller = controller_input.Controller.init(std.testing.allocator);
    defer controller.deinit();
    try controller.bind(.{
        .action_name = "move.right",
        .trigger = .{ .axis = .{ .axis = .left_x, .direction = .positive, .threshold = 0.4 } },
    });

    try controller.feed(&world, .{ .axis_motion = .{ .device_id = 7, .axis = .left_x, .value = 0.2 } });
    try std.testing.expectEqual(
        framework.input.ActionState.up,
        world.input.getActionState(framework.input.InputSystem.actionId("move.right")),
    );

    try controller.feed(&world, .{ .axis_motion = .{ .device_id = 7, .axis = .left_x, .value = 0.7 } });
    try std.testing.expectEqual(
        framework.input.ActionState.pressed,
        world.input.getActionState(framework.input.InputSystem.actionId("move.right")),
    );

    try controller.feed(&world, .{ .axis_motion = .{ .device_id = 7, .axis = .left_x, .value = 0.8 } });
    try std.testing.expectEqual(
        framework.input.ActionState.held,
        world.input.getActionState(framework.input.InputSystem.actionId("move.right")),
    );

    try controller.feed(&world, .{ .axis_motion = .{ .device_id = 7, .axis = .left_x, .value = 0.0 } });
    try std.testing.expectEqual(
        framework.input.ActionState.released,
        world.input.getActionState(framework.input.InputSystem.actionId("move.right")),
    );
}

test "controller input publishes events and tracks device lifetime" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();

    var controller = controller_input.Controller.init(std.testing.allocator);
    defer controller.deinit();

    try controller.feed(&world, .{ .connected = .{ .device_id = 2 } });
    try controller.feed(&world, .{ .axis_motion = .{ .device_id = 2, .axis = .right_y, .value = -0.5 } });
    try std.testing.expectEqual(@as(usize, 1), controller.devices.count());
    try std.testing.expectEqual(@as(usize, 2), world.notifications.events.items.len);
    try std.testing.expectEqualStrings(controller_input.event_topic, world.notifications.events.items[1].name);
    try std.testing.expect(std.mem.indexOf(u8, world.notifications.events.items[1].payload, "\"axis\":\"right_y\"") != null);

    try controller.feed(&world, .{ .disconnected = .{ .device_id = 2 } });
    try std.testing.expectEqual(@as(usize, 0), controller.devices.count());
}

test "controller input rejects invalid and duplicate bindings" {
    var controller = controller_input.Controller.init(std.testing.allocator);
    defer controller.deinit();

    try controller.bind(.{ .action_name = "use", .trigger = .{ .button = .east } });
    try std.testing.expectError(error.DuplicateBinding, controller.bind(.{ .action_name = "use", .trigger = .{ .button = .east } }));
    try std.testing.expectError(error.InvalidBinding, controller.bind(.{ .action_name = "", .trigger = .{ .button = .east } }));
    try std.testing.expectError(error.InvalidBinding, controller.bind(.{
        .action_name = "bad",
        .trigger = .{ .axis = .{ .axis = .left_trigger, .direction = .positive, .threshold = 2.0 } },
    }));
}

test "controller input gem publishes lifecycle events" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();

    try controller_input.start(&world);
    try controller_input.stop(&world);

    try std.testing.expectEqualStrings("gem.controller_input.started", world.notifications.events.items[0].name);
    try std.testing.expectEqualStrings("gem.controller_input.stopped", world.notifications.events.items[1].name);
}
