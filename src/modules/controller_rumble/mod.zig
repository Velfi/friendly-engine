const std = @import("std");
const framework = @import("../../framework/mod.zig");
const controller_input = @import("../controller_input/mod.zig");

pub const module_name = "gem.controller_rumble";
pub const dependencies = [_][]const u8{controller_input.module_name};

pub const event_topic = "input.controller.rumble";

pub const DeviceId = controller_input.DeviceId;

pub const RumbleCommand = struct {
    device_id: DeviceId,
    low_frequency_strength: f32,
    high_frequency_strength: f32,
    duration_ms: u32,
};

pub const StopCommand = struct {
    device_id: DeviceId,
};

pub const Command = union(enum) {
    rumble: RumbleCommand,
    stop: StopCommand,
};

pub const Queue = struct {
    allocator: std.mem.Allocator,
    commands: std.ArrayList(Command),

    pub fn init(allocator: std.mem.Allocator) Queue {
        return .{
            .allocator = allocator,
            .commands = .empty,
        };
    }

    pub fn deinit(self: *Queue) void {
        self.commands.deinit(self.allocator);
    }

    pub fn submit(self: *Queue, world: *framework.World, command: RumbleCommand) !void {
        try validateRumble(command);
        try self.commands.append(self.allocator, .{ .rumble = command });
        try publishRumbleCommand(world, command);
    }

    pub fn stopDevice(self: *Queue, world: *framework.World, device_id: DeviceId) !void {
        const command = StopCommand{ .device_id = device_id };
        try self.commands.append(self.allocator, .{ .stop = command });
        try publishStopCommand(world, command);
    }

    pub fn clear(self: *Queue) void {
        self.commands.clearRetainingCapacity();
    }
};

pub fn register(registry: anytype) !void {
    _ = registry;
}

pub fn start(world: *framework.World) !void {
    try world.notifications.publish("gem.controller_rumble.started", "{}");
}

pub fn stop(world: *framework.World) !void {
    try world.notifications.publish("gem.controller_rumble.stopped", "{}");
}

pub fn validateRumble(command: RumbleCommand) !void {
    if (command.duration_ms == 0) return error.InvalidRumbleCommand;
    try validateStrength(command.low_frequency_strength);
    try validateStrength(command.high_frequency_strength);
}

fn validateStrength(value: f32) !void {
    if (!std.math.isFinite(value) or value < 0.0 or value > 1.0) return error.InvalidRumbleCommand;
}

pub fn publishRumbleCommand(world: *framework.World, command: RumbleCommand) !void {
    var buf: [256]u8 = undefined;
    const payload = try std.fmt.bufPrint(
        &buf,
        "{{\"type\":\"rumble\",\"device_id\":{d},\"low\":{d:.3},\"high\":{d:.3},\"duration_ms\":{d}}}",
        .{
            command.device_id,
            command.low_frequency_strength,
            command.high_frequency_strength,
            command.duration_ms,
        },
    );
    try world.notifications.publish(event_topic, payload);
}

pub fn publishStopCommand(world: *framework.World, command: StopCommand) !void {
    var buf: [128]u8 = undefined;
    const payload = try std.fmt.bufPrint(
        &buf,
        "{{\"type\":\"stop\",\"device_id\":{d}}}",
        .{command.device_id},
    );
    try world.notifications.publish(event_topic, payload);
}

comptime {
    _ = @import("mod_tests.zig");
}
