const std = @import("std");

pub const core = @import("core/mod.zig");
pub const framework = @import("framework/mod.zig");
pub const modules = @import("modules/mod.zig");
pub const game = @import("game/mod.zig");
pub const world = @import("world/mod.zig");
pub const bootstrap = @import("runtime/bootstrap.zig");

pub const RuntimeKind = enum {
    client,
    server,
    editor,
};

pub const EngineConfig = struct {
    runtime: RuntimeKind = .client,
    enable_renderer: bool = true,
    enable_audio: bool = true,
    enable_physics: bool = true,
};

pub fn init(config: EngineConfig, allocator: std.mem.Allocator) !framework.World {
    var engine_world = framework.World.init(allocator);
    const runtime_label = switch (config.runtime) {
        .client => "client",
        .server => "server",
        .editor => "editor",
    };
    try engine_world.notifications.publish("engine.runtime.selected", runtime_label);
    if (!config.enable_renderer) {
        try engine_world.notifications.publish("engine.renderer.disabled", "{}");
    }
    if (!config.enable_audio) {
        try engine_world.notifications.publish("engine.audio.disabled", "{}");
    }
    if (!config.enable_physics) {
        try engine_world.notifications.publish("engine.physics.disabled", "{}");
    }
    try game.registerDefaults(&engine_world);
    return engine_world;
}

test "engine can initialize world" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var engine_world = try init(.{}, arena.allocator());
    const entity = engine_world.spawnEntity();
    try std.testing.expect(entity != 0);
}

test "engine init records disabled systems" {
    var engine_world = try init(.{
        .runtime = .server,
        .enable_renderer = false,
        .enable_audio = false,
        .enable_physics = false,
    }, std.testing.allocator);
    defer engine_world.deinit();

    try std.testing.expectEqual(@as(usize, 5), engine_world.notifications.events.items.len);
    try std.testing.expectEqualStrings("engine.runtime.selected", engine_world.notifications.events.items[0].name);
    try std.testing.expectEqualStrings("engine.renderer.disabled", engine_world.notifications.events.items[1].name);
    try std.testing.expectEqualStrings("engine.audio.disabled", engine_world.notifications.events.items[2].name);
    try std.testing.expectEqualStrings("engine.physics.disabled", engine_world.notifications.events.items[3].name);
    try std.testing.expectEqualStrings("game.defaults_registered", engine_world.notifications.events.items[4].name);
}

test "engine can initialize editor runtime" {
    var engine_world = try init(.{
        .runtime = .editor,
    }, std.testing.allocator);
    defer engine_world.deinit();

    try std.testing.expectEqualStrings("engine.runtime.selected", engine_world.notifications.events.items[0].name);
    try std.testing.expectEqualStrings("editor", engine_world.notifications.events.items[0].payload);
}
