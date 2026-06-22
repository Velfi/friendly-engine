const std = @import("std");
const core = @import("../core/mod.zig");
const ecs = @import("ecs.zig");

pub const ComponentAssignment = struct {
    name: []const u8,
    payload: []const u8,
};

pub const PrefabDesc = struct {
    name: []const u8,
    components: []const ComponentAssignment = &.{},
};

pub const PrefabInstance = struct {
    prefab_name: []const u8,
    entity: ecs.Entity,
};

pub const PrefabLibrary = struct {
    allocator: std.mem.Allocator,
    prefabs: std.ArrayList(PrefabDesc),

    pub fn init(allocator: std.mem.Allocator) PrefabLibrary {
        return .{
            .allocator = allocator,
            .prefabs = .empty,
        };
    }

    pub fn deinit(self: *PrefabLibrary) void {
        for (self.prefabs.items) |prefab| {
            self.allocator.free(prefab.name);
            for (prefab.components) |component| {
                self.allocator.free(component.name);
                self.allocator.free(component.payload);
            }
            self.allocator.free(prefab.components);
        }
        self.prefabs.deinit(self.allocator);
    }

    pub fn register(self: *PrefabLibrary, desc: PrefabDesc) !void {
        if (desc.name.len == 0) return error.InvalidPrefabName;
        if (self.find(desc.name) != null) return error.DuplicatePrefabName;

        const owned_name = try self.allocator.dupe(u8, desc.name);
        errdefer self.allocator.free(owned_name);

        const owned_components = try self.allocator.alloc(ComponentAssignment, desc.components.len);
        errdefer self.allocator.free(owned_components);

        var initialized: usize = 0;
        errdefer {
            for (owned_components[0..initialized]) |component| {
                self.allocator.free(component.name);
                self.allocator.free(component.payload);
            }
        }

        for (desc.components, 0..) |component, index| {
            owned_components[index] = .{
                .name = try self.allocator.dupe(u8, component.name),
                .payload = try self.allocator.dupe(u8, component.payload),
            };
            initialized = index + 1;
        }

        try self.prefabs.append(self.allocator, .{
            .name = owned_name,
            .components = owned_components,
        });
    }

    pub fn find(self: *const PrefabLibrary, name: []const u8) ?*const PrefabDesc {
        for (self.prefabs.items) |*prefab| {
            if (std.mem.eql(u8, prefab.name, name)) return prefab;
        }
        return null;
    }

    pub fn instantiate(self: *const PrefabLibrary, world: *ecs.World, name: []const u8) !PrefabInstance {
        const prefab = self.find(name) orelse return error.UnknownPrefab;
        return .{
            .prefab_name = prefab.name,
            .entity = world.spawnEntity(),
        };
    }
};

pub const SpawnableDesc = struct {
    prefab_name: []const u8,
    stable_id: core.EntityId = 0,
};

test "prefab library registers and instantiates spawnables" {
    var library = PrefabLibrary.init(std.testing.allocator);
    defer library.deinit();

    try library.register(.{
        .name = "crate",
        .components = &.{
            .{ .name = "game.scene_transform", .payload = "{\"position\":[0,1,0]}" },
        },
    });

    var world = ecs.World.init(std.testing.allocator);
    defer world.deinit();

    const instance = try library.instantiate(&world, "crate");
    try std.testing.expect(world.isAlive(instance.entity));
    try std.testing.expectEqualStrings("crate", instance.prefab_name);
}

test "prefab library rejects duplicate names" {
    var library = PrefabLibrary.init(std.testing.allocator);
    defer library.deinit();

    try library.register(.{ .name = "crate" });
    try std.testing.expectError(error.DuplicatePrefabName, library.register(.{ .name = "crate" }));
}
