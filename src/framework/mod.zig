const std = @import("std");
const core = @import("../core/mod.zig");

pub const ecs = @import("ecs.zig");
pub const components = @import("components.zig");
pub const scene = @import("scene.zig");
pub const assets = @import("assets.zig");
pub const bundle_loader = @import("bundle_loader.zig");
pub const pack_file = @import("pack_file.zig");
pub const prefab = @import("prefab.zig");
pub const input = @import("input.zig");
pub const render = @import("render.zig");
pub const audio = @import("audio.zig");
pub const persistence = @import("persistence.zig");
pub const network = @import("network.zig");
pub const introspection = @import("introspection.zig");

pub const World = struct {
    allocator: std.mem.Allocator,
    ecs_world: ecs.World,
    notifications: core.NotificationBus,
    requests: core.RequestBus,
    scene_manager: scene.SceneManager,
    assets: assets.AssetSystem,
    prefabs: prefab.PrefabLibrary,
    input: input.InputSystem,
    renderer: render.RenderSystem,
    audio: audio.AudioSystem,
    persistence: persistence.PersistenceSystem,
    network: network.NetworkSystem,
    component_registry: components.ComponentRegistry,

    pub fn init(allocator: std.mem.Allocator) World {
        return .{
            .allocator = allocator,
            .ecs_world = ecs.World.init(allocator),
            .notifications = core.NotificationBus.init(allocator),
            .requests = core.RequestBus.init(allocator),
            .scene_manager = scene.SceneManager.init(allocator),
            .assets = assets.AssetSystem.init(allocator),
            .prefabs = prefab.PrefabLibrary.init(allocator),
            .input = input.InputSystem.init(allocator),
            .renderer = render.RenderSystem.init(allocator),
            .audio = audio.AudioSystem.init(allocator),
            .persistence = persistence.PersistenceSystem.init(allocator),
            .network = network.NetworkSystem.init(allocator),
            .component_registry = components.ComponentRegistry.init(allocator),
        };
    }

    pub fn deinit(self: *World) void {
        self.network.deinit();
        self.persistence.deinit();
        self.audio.deinit();
        self.renderer.deinit();
        self.input.deinit();
        self.prefabs.deinit();
        self.assets.deinit();
        self.scene_manager.deinit();
        self.requests.deinit();
        self.notifications.deinit();
        self.component_registry.deinit();
        self.ecs_world.deinit();
    }

    pub fn spawnEntity(self: *World) core.EntityId {
        return self.ecs_world.spawnEntity();
    }

    pub fn destroyEntity(self: *World, entity: core.EntityId) bool {
        return self.ecs_world.destroyEntity(entity);
    }

    pub fn registerScene(self: *World, desc: scene.SceneDesc) !core.SceneId {
        return self.scene_manager.registerScene(desc);
    }

    pub fn activateScene(self: *World, scene_id: core.SceneId) !void {
        try self.scene_manager.activate(scene_id, self);
    }

    pub fn updateScene(self: *World) !void {
        try self.scene_manager.updateActive(self);
    }

    pub fn tick(self: *World) !void {
        // The minimal fixed order mirrors the architecture's runtime phases.
        try self.input.poll();
        try self.updateScene();
        try self.network.drainOutgoing();
        try self.audio.flush();
        try self.renderer.flush();
    }
};

test "framework world exposes core abstractions" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const entity = world.spawnEntity();
    try std.testing.expect(world.ecs_world.isAlive(entity));

    const scene_id = try world.registerScene(.{
        .name = "bootstrap",
    });
    try world.activateScene(scene_id);
    try std.testing.expectEqual(scene_id, world.scene_manager.activeSceneId().?);

    try world.requests.register("test.echo", .{
        .call = struct {
            fn call(_: ?*anyopaque, allocator: std.mem.Allocator, payload: []const u8) ![]u8 {
                return allocator.dupe(u8, payload);
            }
        }.call,
    });
    const response = try world.requests.request("test.echo", "pong");
    defer std.testing.allocator.free(response);
    try std.testing.expectEqualStrings("pong", response);
}
