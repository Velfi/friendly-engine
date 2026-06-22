const std = @import("std");
const framework = @import("../../framework/mod.zig");
const game = @import("../../game/mod.zig");

pub const module_name = "gem.persistence";

pub fn register(registry: anytype) !void {
    try registry.registerRequest("persistence.describe", "Summarize persistence backend and operation counts", .{
        .call = persistenceDescribe,
    });
    try registry.registerRequest("persistence.save", "Save bytes to a named persistence slot; payload is slot newline bytes", .{
        .call = persistenceSave,
    });
    try registry.registerRequest("persistence.load", "Load bytes from a named persistence slot", .{
        .call = persistenceLoad,
    });
}

pub fn start(world: *framework.World) !void {
    try world.persistence.setRootLabel("profile");
    try world.notifications.publish("gem.persistence.started", "{}");
}

pub fn stop(world: *framework.World) !void {
    try world.notifications.publish("gem.persistence.stopped", "{}");
}

fn persistenceDescribe(_: ?*anyopaque, allocator: std.mem.Allocator, payload: []const u8) ![]u8 {
    _ = payload;
    const world = game.activeWorld() orelse {
        return allocator.dupe(u8, "{\"backend_attached\":false,\"save_count\":0,\"load_count\":0}");
    };
    return std.fmt.allocPrint(
        allocator,
        "{{\"backend_attached\":{},\"root\":\"{s}\",\"save_count\":{d},\"load_count\":{d}}}",
        .{
            world.persistence.backend != null,
            world.persistence.root_label,
            world.persistence.save_count,
            world.persistence.load_count,
        },
    );
}

fn persistenceSave(_: ?*anyopaque, allocator: std.mem.Allocator, payload: []const u8) ![]u8 {
    const world = game.activeWorld() orelse return error.NoActiveWorld;
    const split = std.mem.indexOfScalar(u8, payload, '\n') orelse return error.InvalidPayload;
    if (split == 0) return error.InvalidPayload;
    try world.persistence.save(payload[0..split], payload[split + 1 ..]);
    return allocator.dupe(u8, "{\"saved\":true}");
}

fn persistenceLoad(_: ?*anyopaque, allocator: std.mem.Allocator, payload: []const u8) ![]u8 {
    _ = allocator;
    const world = game.activeWorld() orelse return error.NoActiveWorld;
    if (payload.len == 0) return error.InvalidPayload;
    return world.persistence.load(payload);
}

test "persistence describe returns backend shape" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();
    game.setActiveWorld(&world);

    const response = try persistenceDescribe(null, std.testing.allocator, "{}");
    defer std.testing.allocator.free(response);
    try std.testing.expect(std.mem.indexOf(u8, response, "save_count") != null);
}

test "persistence save fails loudly without backend" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();
    game.setActiveWorld(&world);

    try std.testing.expectError(
        error.PersistenceBackendMissing,
        persistenceSave(null, std.testing.allocator, "profile\n{}"),
    );
}
