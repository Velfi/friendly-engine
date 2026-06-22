const std = @import("std");
const core = @import("../core/mod.zig");

pub const Entity = core.EntityId;

pub const World = struct {
    allocator: std.mem.Allocator,
    id_generator: core.IdGenerator,
    alive_entities: std.AutoHashMap(Entity, void),

    pub fn init(allocator: std.mem.Allocator) World {
        return .{
            .allocator = allocator,
            .id_generator = core.IdGenerator.init(1),
            .alive_entities = std.AutoHashMap(Entity, void).init(allocator),
        };
    }

    pub fn deinit(self: *World) void {
        self.alive_entities.deinit();
    }

    pub fn spawnEntity(self: *World) Entity {
        const id: Entity = self.id_generator.nextId();
        self.alive_entities.put(id, {}) catch unreachable;
        return id;
    }

    pub fn destroyEntity(self: *World, entity: Entity) bool {
        return self.alive_entities.remove(entity);
    }

    pub fn isAlive(self: *const World, entity: Entity) bool {
        return self.alive_entities.contains(entity);
    }

    pub fn entityCount(self: *const World) usize {
        return self.alive_entities.count();
    }
};

pub fn ComponentStorage(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        values: std.AutoHashMap(Entity, T),

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .values = std.AutoHashMap(Entity, T).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.values.deinit();
        }

        pub fn set(self: *Self, entity: Entity, value: T) !void {
            try self.values.put(entity, value);
        }

        pub fn get(self: *Self, entity: Entity) ?T {
            return self.values.get(entity);
        }

        pub fn getPtr(self: *Self, entity: Entity) ?*T {
            return self.values.getPtr(entity);
        }

        pub fn remove(self: *Self, entity: Entity) bool {
            return self.values.remove(entity);
        }
    };
}

test "ecs world spawns and destroys entities" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const entity = world.spawnEntity();
    try std.testing.expect(world.isAlive(entity));
    try std.testing.expectEqual(@as(usize, 1), world.entityCount());

    const removed = world.destroyEntity(entity);
    try std.testing.expect(removed);
    try std.testing.expect(!world.isAlive(entity));
}

test "component storage tracks per-entity data" {
    const Transform = struct { x: f32, y: f32, z: f32 };
    var storage = ComponentStorage(Transform).init(std.testing.allocator);
    defer storage.deinit();

    try storage.set(7, .{ .x = 1, .y = 2, .z = 3 });
    const value = storage.get(7).?;
    try std.testing.expectEqual(@as(f32, 1), value.x);
}
