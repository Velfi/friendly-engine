const std = @import("std");
const core = @import("../../core/mod.zig");
const framework = @import("../../framework/mod.zig");

pub const module_name = "gem.keyboard_mouse_controller";
pub const dependencies = [_][]const u8{};

pub const event_topic = "input.keyboard_mouse.event";

pub const Key = enum(u16) {
    unknown = 0,
    w,
    a,
    s,
    d,
    q,
    e,
    space,
    left_shift,
    left_ctrl,
    escape,
    tab,
    enter,
    up,
    down,
    left,
    right,
};

pub const MouseButton = enum(u8) {
    left,
    middle,
    right,
    extra1,
    extra2,
};

pub const Trigger = union(enum) {
    key: Key,
    mouse_button: MouseButton,
};

pub const Binding = struct {
    action_name: []const u8,
    trigger: Trigger,
};

pub const InputEvent = union(enum) {
    key_down: KeyEvent,
    key_up: KeyEvent,
    mouse_button_down: MouseButtonEvent,
    mouse_button_up: MouseButtonEvent,
    mouse_motion: MouseMotionEvent,
    mouse_wheel: MouseWheelEvent,

    pub const KeyEvent = struct {
        key: Key,
        repeat: bool = false,
    };

    pub const MouseButtonEvent = struct {
        button: MouseButton,
        x: f32 = 0.0,
        y: f32 = 0.0,
        clicks: u8 = 1,
    };

    pub const MouseMotionEvent = struct {
        x: f32,
        y: f32,
        delta_x: f32,
        delta_y: f32,
    };

    pub const MouseWheelEvent = struct {
        delta_x: f32,
        delta_y: f32,
        precise: bool = false,
    };
};

pub const PointerState = struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
    delta_x: f32 = 0.0,
    delta_y: f32 = 0.0,
    wheel_delta_x: f32 = 0.0,
    wheel_delta_y: f32 = 0.0,
};

pub const Controller = struct {
    allocator: std.mem.Allocator,
    bindings: std.ArrayList(OwnedBinding),
    key_down: std.AutoHashMap(Key, void),
    mouse_button_down: std.AutoHashMap(MouseButton, void),
    pointer: PointerState = .{},

    const OwnedBinding = struct {
        action_name: []u8,
        trigger: Trigger,
    };

    pub fn init(allocator: std.mem.Allocator) Controller {
        return .{
            .allocator = allocator,
            .bindings = .empty,
            .key_down = std.AutoHashMap(Key, void).init(allocator),
            .mouse_button_down = std.AutoHashMap(MouseButton, void).init(allocator),
        };
    }

    pub fn deinit(self: *Controller) void {
        self.clearBindings();
        self.bindings.deinit(self.allocator);
        self.mouse_button_down.deinit();
        self.key_down.deinit();
    }

    pub fn beginFrame(self: *Controller) void {
        self.pointer.delta_x = 0.0;
        self.pointer.delta_y = 0.0;
        self.pointer.wheel_delta_x = 0.0;
        self.pointer.wheel_delta_y = 0.0;
    }

    pub fn bind(self: *Controller, binding: Binding) !void {
        if (binding.action_name.len == 0) return error.InvalidBinding;
        for (self.bindings.items) |existing| {
            if (sameTrigger(existing.trigger, binding.trigger) and std.mem.eql(u8, existing.action_name, binding.action_name)) {
                return error.DuplicateBinding;
            }
        }
        try self.bindings.append(self.allocator, .{
            .action_name = try self.allocator.dupe(u8, binding.action_name),
            .trigger = binding.trigger,
        });
    }

    pub fn clearBindings(self: *Controller) void {
        for (self.bindings.items) |binding| self.allocator.free(binding.action_name);
        self.bindings.clearRetainingCapacity();
    }

    pub fn feed(self: *Controller, world: *framework.World, event: InputEvent) !void {
        try self.applyEvent(event);
        try publishInputEvent(world, event);
        try self.applyBindings(&world.input, event);
    }

    pub fn applyBindings(self: *Controller, input: *framework.input.InputSystem, event: InputEvent) !void {
        for (self.bindings.items) |binding| {
            if (!eventMatchesTrigger(event, binding.trigger)) continue;
            const state: framework.input.ActionState = switch (event) {
                .key_down => |key_event| if (key_event.repeat) .held else .pressed,
                .mouse_button_down => .pressed,
                .key_up, .mouse_button_up => .released,
                .mouse_motion, .mouse_wheel => continue,
            };
            try input.setActionStateByName(binding.action_name, state);
        }
    }

    pub fn settleActionStates(self: *Controller, input: *framework.input.InputSystem) !void {
        for (self.bindings.items) |binding| {
            const action_state = input.getActionState(framework.input.InputSystem.actionId(binding.action_name));
            const down = self.triggerIsDown(binding.trigger);
            const next: framework.input.ActionState = switch (action_state) {
                .pressed => if (down) .held else .released,
                .held => if (down) .held else .released,
                .released => if (down) .pressed else .up,
                .up => if (down) .pressed else .up,
            };
            try input.setActionStateByName(binding.action_name, next);
        }
    }

    pub fn triggerIsDown(self: *const Controller, trigger: Trigger) bool {
        return switch (trigger) {
            .key => |key| self.key_down.contains(key),
            .mouse_button => |button| self.mouse_button_down.contains(button),
        };
    }

    fn applyEvent(self: *Controller, event: InputEvent) !void {
        switch (event) {
            .key_down => |key_event| try self.key_down.put(key_event.key, {}),
            .key_up => |key_event| _ = self.key_down.remove(key_event.key),
            .mouse_button_down => |button_event| {
                self.pointer.x = button_event.x;
                self.pointer.y = button_event.y;
                try self.mouse_button_down.put(button_event.button, {});
            },
            .mouse_button_up => |button_event| {
                self.pointer.x = button_event.x;
                self.pointer.y = button_event.y;
                _ = self.mouse_button_down.remove(button_event.button);
            },
            .mouse_motion => |motion| {
                self.pointer.x = motion.x;
                self.pointer.y = motion.y;
                self.pointer.delta_x += motion.delta_x;
                self.pointer.delta_y += motion.delta_y;
            },
            .mouse_wheel => |wheel| {
                self.pointer.wheel_delta_x += wheel.delta_x;
                self.pointer.wheel_delta_y += wheel.delta_y;
            },
        }
    }
};

pub fn register(registry: anytype) !void {
    _ = registry;
}

pub fn start(world: *framework.World) !void {
    try world.notifications.publish("gem.keyboard_mouse_controller.started", "{}");
}

pub fn stop(world: *framework.World) !void {
    try world.notifications.publish("gem.keyboard_mouse_controller.stopped", "{}");
}

pub fn publishInputEvent(world: *framework.World, event: InputEvent) !void {
    var buf: [256]u8 = undefined;
    const payload = try eventPayload(&buf, event);
    try world.notifications.publish(event_topic, payload);
}

fn eventPayload(buf: []u8, event: InputEvent) ![]const u8 {
    return switch (event) {
        .key_down => |key_event| std.fmt.bufPrint(buf, "{{\"type\":\"key_down\",\"key\":\"{s}\",\"repeat\":{s}}}", .{
            keyName(key_event.key),
            boolName(key_event.repeat),
        }),
        .key_up => |key_event| std.fmt.bufPrint(buf, "{{\"type\":\"key_up\",\"key\":\"{s}\",\"repeat\":{s}}}", .{
            keyName(key_event.key),
            boolName(key_event.repeat),
        }),
        .mouse_button_down => |button_event| std.fmt.bufPrint(buf, "{{\"type\":\"mouse_button_down\",\"button\":\"{s}\",\"x\":{d:.2},\"y\":{d:.2},\"clicks\":{d}}}", .{
            mouseButtonName(button_event.button),
            button_event.x,
            button_event.y,
            button_event.clicks,
        }),
        .mouse_button_up => |button_event| std.fmt.bufPrint(buf, "{{\"type\":\"mouse_button_up\",\"button\":\"{s}\",\"x\":{d:.2},\"y\":{d:.2},\"clicks\":{d}}}", .{
            mouseButtonName(button_event.button),
            button_event.x,
            button_event.y,
            button_event.clicks,
        }),
        .mouse_motion => |motion| std.fmt.bufPrint(buf, "{{\"type\":\"mouse_motion\",\"x\":{d:.2},\"y\":{d:.2},\"delta\":[{d:.2},{d:.2}]}}", .{
            motion.x,
            motion.y,
            motion.delta_x,
            motion.delta_y,
        }),
        .mouse_wheel => |wheel| std.fmt.bufPrint(buf, "{{\"type\":\"mouse_wheel\",\"delta\":[{d:.2},{d:.2}],\"precise\":{s}}}", .{
            wheel.delta_x,
            wheel.delta_y,
            boolName(wheel.precise),
        }),
    };
}

fn eventMatchesTrigger(event: InputEvent, trigger: Trigger) bool {
    return switch (event) {
        .key_down => |key_event| switch (trigger) {
            .key => |key| key == key_event.key,
            .mouse_button => false,
        },
        .key_up => |key_event| switch (trigger) {
            .key => |key| key == key_event.key,
            .mouse_button => false,
        },
        .mouse_button_down => |button_event| switch (trigger) {
            .key => false,
            .mouse_button => |button| button == button_event.button,
        },
        .mouse_button_up => |button_event| switch (trigger) {
            .key => false,
            .mouse_button => |button| button == button_event.button,
        },
        .mouse_motion, .mouse_wheel => false,
    };
}

fn sameTrigger(a: Trigger, b: Trigger) bool {
    return switch (a) {
        .key => |a_key| switch (b) {
            .key => |b_key| a_key == b_key,
            .mouse_button => false,
        },
        .mouse_button => |a_button| switch (b) {
            .key => false,
            .mouse_button => |b_button| a_button == b_button,
        },
    };
}

fn keyName(key: Key) []const u8 {
    return switch (key) {
        .unknown => "unknown",
        .w => "w",
        .a => "a",
        .s => "s",
        .d => "d",
        .q => "q",
        .e => "e",
        .space => "space",
        .left_shift => "left_shift",
        .left_ctrl => "left_ctrl",
        .escape => "escape",
        .tab => "tab",
        .enter => "enter",
        .up => "up",
        .down => "down",
        .left => "left",
        .right => "right",
    };
}

fn mouseButtonName(button: MouseButton) []const u8 {
    return switch (button) {
        .left => "left",
        .middle => "middle",
        .right => "right",
        .extra1 => "extra1",
        .extra2 => "extra2",
    };
}

fn boolName(value: bool) []const u8 {
    return if (value) "true" else "false";
}

comptime {
    _ = @import("mod_tests.zig");
}
