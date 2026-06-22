const std = @import("std");
const framework = @import("../../framework/mod.zig");

pub const module_name = "gem.controller_input";
pub const dependencies = [_][]const u8{};

pub const event_topic = "input.controller.event";

pub const DeviceId = u32;

pub const Button = enum(u8) {
    south,
    east,
    west,
    north,
    back,
    guide,
    start,
    left_stick,
    right_stick,
    left_shoulder,
    right_shoulder,
    dpad_up,
    dpad_down,
    dpad_left,
    dpad_right,
    misc1,
};

pub const Axis = enum(u8) {
    left_x,
    left_y,
    right_x,
    right_y,
    left_trigger,
    right_trigger,
};

pub const AxisDirection = enum(i8) {
    negative = -1,
    positive = 1,
};

pub const AxisTrigger = struct {
    axis: Axis,
    direction: AxisDirection,
    threshold: f32 = 0.5,
};

pub const Trigger = union(enum) {
    button: Button,
    axis: AxisTrigger,
};

pub const Binding = struct {
    action_name: []const u8,
    trigger: Trigger,
};

pub const InputEvent = union(enum) {
    connected: DeviceEvent,
    disconnected: DeviceEvent,
    button_down: ButtonEvent,
    button_up: ButtonEvent,
    axis_motion: AxisEvent,

    pub const DeviceEvent = struct {
        device_id: DeviceId,
    };

    pub const ButtonEvent = struct {
        device_id: DeviceId,
        button: Button,
    };

    pub const AxisEvent = struct {
        device_id: DeviceId,
        axis: Axis,
        value: f32,
    };
};

pub const ControllerState = struct {
    device_id: DeviceId,
    buttons_down: std.AutoHashMap(Button, void),
    axes: AxisValues = .{},

    pub fn init(allocator: std.mem.Allocator, device_id: DeviceId) ControllerState {
        return .{
            .device_id = device_id,
            .buttons_down = std.AutoHashMap(Button, void).init(allocator),
        };
    }

    pub fn deinit(self: *ControllerState) void {
        self.buttons_down.deinit();
    }
};

pub const AxisValues = struct {
    left_x: f32 = 0.0,
    left_y: f32 = 0.0,
    right_x: f32 = 0.0,
    right_y: f32 = 0.0,
    left_trigger: f32 = 0.0,
    right_trigger: f32 = 0.0,

    pub fn get(self: AxisValues, axis: Axis) f32 {
        return switch (axis) {
            .left_x => self.left_x,
            .left_y => self.left_y,
            .right_x => self.right_x,
            .right_y => self.right_y,
            .left_trigger => self.left_trigger,
            .right_trigger => self.right_trigger,
        };
    }

    pub fn set(self: *AxisValues, axis: Axis, value: f32) void {
        switch (axis) {
            .left_x => self.left_x = value,
            .left_y => self.left_y = value,
            .right_x => self.right_x = value,
            .right_y => self.right_y = value,
            .left_trigger => self.left_trigger = value,
            .right_trigger => self.right_trigger = value,
        }
    }
};

pub const Controller = struct {
    allocator: std.mem.Allocator,
    bindings: std.ArrayList(OwnedBinding),
    devices: std.AutoHashMap(DeviceId, ControllerState),

    const OwnedBinding = struct {
        action_name: []u8,
        trigger: Trigger,
    };

    pub fn init(allocator: std.mem.Allocator) Controller {
        return .{
            .allocator = allocator,
            .bindings = .empty,
            .devices = std.AutoHashMap(DeviceId, ControllerState).init(allocator),
        };
    }

    pub fn deinit(self: *Controller) void {
        self.clearBindings();
        self.bindings.deinit(self.allocator);
        var iter = self.devices.iterator();
        while (iter.next()) |entry| entry.value_ptr.deinit();
        self.devices.deinit();
    }

    pub fn bind(self: *Controller, binding: Binding) !void {
        if (binding.action_name.len == 0) return error.InvalidBinding;
        try validateTrigger(binding.trigger);
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
            try input.setActionStateByName(binding.action_name, nextStateForTrigger(input, binding.action_name, self.triggerIsDown(binding.trigger)));
        }
    }

    pub fn settleActionStates(self: *Controller, input: *framework.input.InputSystem) !void {
        for (self.bindings.items) |binding| {
            try input.setActionStateByName(binding.action_name, nextStateForTrigger(input, binding.action_name, self.triggerIsDown(binding.trigger)));
        }
    }

    pub fn triggerIsDown(self: *const Controller, trigger: Trigger) bool {
        var iter = self.devices.iterator();
        while (iter.next()) |entry| {
            const state = entry.value_ptr;
            switch (trigger) {
                .button => |button| if (state.buttons_down.contains(button)) return true,
                .axis => |axis_trigger| if (axisTriggerActive(state.axes.get(axis_trigger.axis), axis_trigger)) return true,
            }
        }
        return false;
    }

    pub fn axisValue(self: *const Controller, axis: Axis) f32 {
        var strongest: f32 = 0.0;
        var iter = self.devices.iterator();
        while (iter.next()) |entry| {
            const value = entry.value_ptr.axes.get(axis);
            if (@abs(value) > @abs(strongest)) strongest = value;
        }
        return strongest;
    }

    fn applyEvent(self: *Controller, event: InputEvent) !void {
        switch (event) {
            .connected => |device| {
                if (self.devices.contains(device.device_id)) return;
                try self.devices.put(device.device_id, ControllerState.init(self.allocator, device.device_id));
            },
            .disconnected => |device| {
                if (self.devices.fetchRemove(device.device_id)) |removed| {
                    var state = removed.value;
                    state.deinit();
                }
            },
            .button_down => |button_event| {
                const state = try self.ensureDevice(button_event.device_id);
                try state.buttons_down.put(button_event.button, {});
            },
            .button_up => |button_event| {
                const state = try self.ensureDevice(button_event.device_id);
                _ = state.buttons_down.remove(button_event.button);
            },
            .axis_motion => |axis_event| {
                if (!std.math.isFinite(axis_event.value)) return error.InvalidAxisValue;
                const state = try self.ensureDevice(axis_event.device_id);
                state.axes.set(axis_event.axis, std.math.clamp(axis_event.value, -1.0, 1.0));
            },
        }
    }

    fn ensureDevice(self: *Controller, device_id: DeviceId) !*ControllerState {
        if (!self.devices.contains(device_id)) {
            try self.devices.put(device_id, ControllerState.init(self.allocator, device_id));
        }
        return self.devices.getPtr(device_id).?;
    }
};

pub fn register(registry: anytype) !void {
    _ = registry;
}

pub fn start(world: *framework.World) !void {
    try world.notifications.publish("gem.controller_input.started", "{}");
}

pub fn stop(world: *framework.World) !void {
    try world.notifications.publish("gem.controller_input.stopped", "{}");
}

pub fn publishInputEvent(world: *framework.World, event: InputEvent) !void {
    var buf: [256]u8 = undefined;
    const payload = try eventPayload(&buf, event);
    try world.notifications.publish(event_topic, payload);
}

fn nextStateForTrigger(input: *const framework.input.InputSystem, action_name: []const u8, down: bool) framework.input.ActionState {
    const current = input.getActionState(framework.input.InputSystem.actionId(action_name));
    return switch (current) {
        .pressed => if (down) .held else .released,
        .held => if (down) .held else .released,
        .released => if (down) .pressed else .up,
        .up => if (down) .pressed else .up,
    };
}

fn axisTriggerActive(value: f32, trigger: AxisTrigger) bool {
    return switch (trigger.direction) {
        .negative => value <= -trigger.threshold,
        .positive => value >= trigger.threshold,
    };
}

fn eventMatchesTrigger(event: InputEvent, trigger: Trigger) bool {
    return switch (event) {
        .button_down => |button_event| switch (trigger) {
            .button => |button| button == button_event.button,
            .axis => false,
        },
        .button_up => |button_event| switch (trigger) {
            .button => |button| button == button_event.button,
            .axis => false,
        },
        .axis_motion => |axis_event| switch (trigger) {
            .button => false,
            .axis => |axis_trigger| axis_trigger.axis == axis_event.axis,
        },
        .connected, .disconnected => false,
    };
}

fn validateTrigger(trigger: Trigger) !void {
    switch (trigger) {
        .button => {},
        .axis => |axis_trigger| {
            if (!std.math.isFinite(axis_trigger.threshold) or axis_trigger.threshold <= 0.0 or axis_trigger.threshold > 1.0) {
                return error.InvalidBinding;
            }
        },
    }
}

fn sameTrigger(a: Trigger, b: Trigger) bool {
    return switch (a) {
        .button => |a_button| switch (b) {
            .button => |b_button| a_button == b_button,
            .axis => false,
        },
        .axis => |a_axis| switch (b) {
            .button => false,
            .axis => |b_axis| a_axis.axis == b_axis.axis and
                a_axis.direction == b_axis.direction and
                a_axis.threshold == b_axis.threshold,
        },
    };
}

fn eventPayload(buf: []u8, event: InputEvent) ![]const u8 {
    return switch (event) {
        .connected => |device| std.fmt.bufPrint(buf, "{{\"type\":\"connected\",\"device_id\":{d}}}", .{device.device_id}),
        .disconnected => |device| std.fmt.bufPrint(buf, "{{\"type\":\"disconnected\",\"device_id\":{d}}}", .{device.device_id}),
        .button_down => |button_event| std.fmt.bufPrint(buf, "{{\"type\":\"button_down\",\"device_id\":{d},\"button\":\"{s}\"}}", .{
            button_event.device_id,
            buttonName(button_event.button),
        }),
        .button_up => |button_event| std.fmt.bufPrint(buf, "{{\"type\":\"button_up\",\"device_id\":{d},\"button\":\"{s}\"}}", .{
            button_event.device_id,
            buttonName(button_event.button),
        }),
        .axis_motion => |axis_event| std.fmt.bufPrint(buf, "{{\"type\":\"axis_motion\",\"device_id\":{d},\"axis\":\"{s}\",\"value\":{d:.3}}}", .{
            axis_event.device_id,
            axisName(axis_event.axis),
            axis_event.value,
        }),
    };
}

fn buttonName(button: Button) []const u8 {
    return switch (button) {
        .south => "south",
        .east => "east",
        .west => "west",
        .north => "north",
        .back => "back",
        .guide => "guide",
        .start => "start",
        .left_stick => "left_stick",
        .right_stick => "right_stick",
        .left_shoulder => "left_shoulder",
        .right_shoulder => "right_shoulder",
        .dpad_up => "dpad_up",
        .dpad_down => "dpad_down",
        .dpad_left => "dpad_left",
        .dpad_right => "dpad_right",
        .misc1 => "misc1",
    };
}

fn axisName(axis: Axis) []const u8 {
    return switch (axis) {
        .left_x => "left_x",
        .left_y => "left_y",
        .right_x => "right_x",
        .right_y => "right_y",
        .left_trigger => "left_trigger",
        .right_trigger => "right_trigger",
    };
}

comptime {
    _ = @import("mod_tests.zig");
}
