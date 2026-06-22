const std = @import("std");
const framework = @import("mod.zig");
const game = @import("../game/mod.zig");
const world_cell_requests = @import("world_cell_requests.zig");

pub const RequestCatalogEntry = struct {
    name: []const u8,
    description: []const u8,
};

pub fn registerIntrospection(registry: anytype) !void {
    try registry.registerRequest("world.describe", "Summarize runtime entity count and component names", .{
        .call = worldDescribe,
    });
    try registry.registerRequest("world.listEntities", "List alive entity ids as JSON array", .{
        .call = worldListEntities,
    });
    try registry.registerRequest("scene.describe", "Summarize active scene spawn state", .{
        .call = sceneDescribe,
    });
    try registry.registerRequest("world.cells.describe", "Summarize active streamed world cell state", .{
        .call = world_cell_requests.describe,
    });
    try registry.registerRequest("world.cells.reload", "Reload one active streamed world cell from its baked fcell", .{
        .call = world_cell_requests.reload,
    });
    try registry.registerRequest("world.cells.reloadAll", "Reload all active streamed world cells from baked fcells", .{
        .call = world_cell_requests.reloadAll,
    });
    try registry.registerRequest("physics.describe", "Summarize active physics body and contact counts", .{
        .call = physicsDescribe,
    });
}

pub fn requestCatalog() []const RequestCatalogEntry {
    return &.{
        .{ .name = "world.describe", .description = "Summarize runtime entity count and component names" },
        .{ .name = "world.listEntities", .description = "List alive entity ids as JSON array" },
        .{ .name = "scene.describe", .description = "Summarize active scene spawn state" },
        .{ .name = "world.cells.describe", .description = "Summarize active streamed world cell state" },
        .{ .name = "world.cells.reload", .description = "Reload one active streamed world cell from its baked fcell" },
        .{ .name = "world.cells.reloadAll", .description = "Reload all active streamed world cells from baked fcells" },
        .{ .name = "physics.describe", .description = "Summarize active physics body and contact counts" },
    };
}

fn worldDescribe(_: ?*anyopaque, allocator: std.mem.Allocator, payload: []const u8) ![]u8 {
    _ = payload;
    const world_ptr = game.activeWorld() orelse {
        return allocator.dupe(u8, "{\"entity_count\":0,\"components\":[]}");
    };
    const world = world_ptr.*;

    var components = std.ArrayList([]const u8).empty;
    defer components.deinit(allocator);
    for (world.component_registry.entries()) |entry| {
        try components.append(allocator, entry.name);
    }

    const quoted = try joinQuoted(allocator, components.items);
    defer if (quoted.len > 0) allocator.free(quoted);

    return std.fmt.allocPrint(allocator, "{{\"entity_count\":{d},\"components\":[{s}]}}", .{
        world.ecs_world.entityCount(),
        quoted,
    });
}

fn worldListEntities(_: ?*anyopaque, allocator: std.mem.Allocator, payload: []const u8) ![]u8 {
    _ = payload;
    const world_ptr = game.activeWorld() orelse {
        return allocator.dupe(u8, "{\"entities\":[]}");
    };
    const world = world_ptr.*;

    var ids = std.ArrayList(u64).empty;
    defer ids.deinit(allocator);

    var iter = world.ecs_world.alive_entities.keyIterator();
    while (iter.next()) |entity_id| {
        try ids.append(allocator, entity_id.*);
    }

    var builder = std.ArrayList(u8).empty;
    defer builder.deinit(allocator);
    try builder.appendSlice(allocator, "{\"entities\":[");
    for (ids.items, 0..) |entity_id, idx| {
        if (idx != 0) try builder.appendSlice(allocator, ",");
        var num_buf: [32]u8 = undefined;
        const num = try std.fmt.bufPrint(&num_buf, "{d}", .{entity_id});
        try builder.appendSlice(allocator, num);
    }
    try builder.appendSlice(allocator, "]}");
    return builder.toOwnedSlice(allocator);
}

fn sceneDescribe(_: ?*anyopaque, allocator: std.mem.Allocator, payload: []const u8) ![]u8 {
    _ = payload;
    const state = game.sceneState() orelse {
        return allocator.dupe(u8, "{\"object_count\":0,\"mesh_count\":0}");
    };

    return std.fmt.allocPrint(allocator, "{{\"object_count\":{d},\"mesh_count\":{d}}}", .{
        state.entities.items.len,
        state.meshes.items.len,
    });
}

fn physicsDescribe(_: ?*anyopaque, allocator: std.mem.Allocator, payload: []const u8) ![]u8 {
    _ = payload;
    const physics = game.physicsState() orelse {
        return allocator.dupe(u8, "{\"body_count\":0,\"raw_body_count\":0,\"contact_count\":0}");
    };

    return std.fmt.allocPrint(
        allocator,
        "{{\"body_count\":{d},\"raw_body_count\":{d},\"contact_count\":{d}}}",
        .{
            physics.bodyCount(),
            physics.physics_world.bodies.items.len,
            physics.physics_world.getContacts().len,
        },
    );
}

fn joinQuoted(allocator: std.mem.Allocator, items: []const []const u8) ![]u8 {
    if (items.len == 0) return try allocator.dupe(u8, "");
    var builder = std.ArrayList(u8).empty;
    defer builder.deinit(allocator);
    for (items, 0..) |item, idx| {
        if (idx != 0) try builder.appendSlice(allocator, ",");
        const quoted = try std.fmt.allocPrint(allocator, "\"{s}\"", .{item});
        defer allocator.free(quoted);
        try builder.appendSlice(allocator, quoted);
    }
    return builder.toOwnedSlice(allocator);
}

test "scene describe returns object count" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();
    game.setActiveWorld(&world);

    const response = try sceneDescribe(null, std.testing.allocator, "{}");
    defer std.testing.allocator.free(response);
    try std.testing.expect(std.mem.indexOf(u8, response, "object_count") != null);
}

test "physics describe returns body count shape" {
    const response = try physicsDescribe(null, std.testing.allocator, "{}");
    defer std.testing.allocator.free(response);
    try std.testing.expect(std.mem.indexOf(u8, response, "body_count") != null);
}
