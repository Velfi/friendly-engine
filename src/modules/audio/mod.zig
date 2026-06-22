const std = @import("std");
const core = @import("../../core/mod.zig");
const framework = @import("../../framework/mod.zig");
const game = @import("../../game/mod.zig");

pub const module_name = "gem.audio";

pub fn register(registry: anytype) !void {
    try registry.registerRequest("audio.describe", "Summarize audio backend and queued command state", .{
        .call = audioDescribe,
    });
    try registry.registerRequest("audio.play", "Queue an audio asset path for playback", .{
        .call = audioPlay,
    });
}

pub fn start(world: *framework.World) !void {
    try world.notifications.publish("gem.audio.started", "{}");
}

pub fn stop(world: *framework.World) !void {
    try world.notifications.publish("gem.audio.stopped", "{}");
}

fn audioDescribe(_: ?*anyopaque, allocator: std.mem.Allocator, payload: []const u8) ![]u8 {
    _ = payload;
    const world = game.activeWorld() orelse {
        return allocator.dupe(u8, "{\"backend_attached\":false,\"pending_commands\":0}");
    };
    return std.fmt.allocPrint(allocator, "{{\"backend_attached\":{},\"pending_commands\":{d}}}", .{
        world.audio.backend != null,
        world.audio.pendingCount(),
    });
}

fn audioPlay(_: ?*anyopaque, allocator: std.mem.Allocator, payload: []const u8) ![]u8 {
    const world = game.activeWorld() orelse return error.NoActiveWorld;
    if (payload.len == 0) return error.InvalidPayload;

    const asset_id = try world.assets.register("audio", payload);
    try world.audio.playSound(asset_id, 1.0);
    return std.fmt.allocPrint(allocator, "{{\"queued\":true,\"asset_id\":{d}}}", .{asset_id});
}

test "audio describe returns queued command shape" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();
    game.setActiveWorld(&world);

    const response = try audioDescribe(null, std.testing.allocator, "{}");
    defer std.testing.allocator.free(response);
    try std.testing.expect(std.mem.indexOf(u8, response, "pending_commands") != null);
}

test "audio play registers asset and queues command" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();
    game.setActiveWorld(&world);

    const response = try audioPlay(null, std.testing.allocator, "assets/audio/click.ogg");
    defer std.testing.allocator.free(response);
    try std.testing.expectEqual(@as(usize, 1), world.assets.count());
    try std.testing.expectEqual(@as(usize, 1), world.audio.pendingCount());
}
