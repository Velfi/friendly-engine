const std = @import("std");
const framework = @import("../../framework/mod.zig");
const keyboard_mouse = @import("mod.zig");

test "keyboard mouse controller maps key events to actions" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();

    var controller = keyboard_mouse.Controller.init(std.testing.allocator);
    defer controller.deinit();
    try controller.bind(.{ .action_name = "move.forward", .trigger = .{ .key = .w } });

    try controller.feed(&world, .{ .key_down = .{ .key = .w } });
    try std.testing.expectEqual(
        framework.input.ActionState.pressed,
        world.input.getActionState(framework.input.InputSystem.actionId("move.forward")),
    );
    try std.testing.expect(controller.triggerIsDown(.{ .key = .w }));

    try controller.settleActionStates(&world.input);
    try std.testing.expectEqual(
        framework.input.ActionState.held,
        world.input.getActionState(framework.input.InputSystem.actionId("move.forward")),
    );

    try controller.feed(&world, .{ .key_up = .{ .key = .w } });
    try std.testing.expectEqual(
        framework.input.ActionState.released,
        world.input.getActionState(framework.input.InputSystem.actionId("move.forward")),
    );
}

test "keyboard mouse controller maps mouse buttons and accumulates pointer motion" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();

    var controller = keyboard_mouse.Controller.init(std.testing.allocator);
    defer controller.deinit();
    try controller.bind(.{ .action_name = "fire", .trigger = .{ .mouse_button = .left } });

    try controller.feed(&world, .{ .mouse_button_down = .{ .button = .left, .x = 10, .y = 20 } });
    try std.testing.expectEqual(
        framework.input.ActionState.pressed,
        world.input.getActionState(framework.input.InputSystem.actionId("fire")),
    );

    try controller.feed(&world, .{ .mouse_motion = .{ .x = 12, .y = 24, .delta_x = 2, .delta_y = 4 } });
    try controller.feed(&world, .{ .mouse_wheel = .{ .delta_x = 0.5, .delta_y = -1.0, .precise = true } });
    try std.testing.expectApproxEqAbs(@as(f32, 12), controller.pointer.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 4), controller.pointer.delta_y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, -1), controller.pointer.wheel_delta_y, 0.001);

    controller.beginFrame();
    try std.testing.expectApproxEqAbs(@as(f32, 0), controller.pointer.delta_y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), controller.pointer.wheel_delta_y, 0.001);
}

test "keyboard mouse controller publishes input events" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();

    var controller = keyboard_mouse.Controller.init(std.testing.allocator);
    defer controller.deinit();

    try controller.feed(&world, .{ .key_down = .{ .key = .e } });

    try std.testing.expectEqual(@as(usize, 1), world.notifications.events.items.len);
    try std.testing.expectEqualStrings(keyboard_mouse.event_topic, world.notifications.events.items[0].name);
    try std.testing.expect(std.mem.indexOf(u8, world.notifications.events.items[0].payload, "\"key\":\"e\"") != null);
}

test "keyboard mouse controller rejects duplicate bindings" {
    var controller = keyboard_mouse.Controller.init(std.testing.allocator);
    defer controller.deinit();

    try controller.bind(.{ .action_name = "use", .trigger = .{ .key = .e } });
    try std.testing.expectError(error.DuplicateBinding, controller.bind(.{ .action_name = "use", .trigger = .{ .key = .e } }));
    try std.testing.expectError(error.InvalidBinding, controller.bind(.{ .action_name = "", .trigger = .{ .key = .e } }));
}

test "keyboard mouse gem publishes lifecycle events" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();

    try keyboard_mouse.start(&world);
    try keyboard_mouse.stop(&world);

    try std.testing.expectEqualStrings("gem.keyboard_mouse_controller.started", world.notifications.events.items[0].name);
    try std.testing.expectEqualStrings("gem.keyboard_mouse_controller.stopped", world.notifications.events.items[1].name);
}
