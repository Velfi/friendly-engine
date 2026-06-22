const std = @import("std");
const ecs = @import("ecs.zig");

pub const FieldKind = enum {
    f32,
    u32,
    u64,
    bool,
    vec3f,
    asset_id,
};

pub const FieldDesc = struct {
    name: []const u8,
    kind: FieldKind,
};

pub const ComponentDesc = struct {
    name: []const u8,
    fields: []const FieldDesc,
};

pub const ComponentRegistry = struct {
    allocator: std.mem.Allocator,
    components: std.ArrayList(ComponentDesc),

    pub fn init(allocator: std.mem.Allocator) ComponentRegistry {
        return .{
            .allocator = allocator,
            .components = .empty,
        };
    }

    pub fn deinit(self: *ComponentRegistry) void {
        self.components.deinit(self.allocator);
    }

    pub fn register(self: *ComponentRegistry, desc: ComponentDesc) !void {
        for (self.components.items) |existing| {
            if (std.mem.eql(u8, existing.name, desc.name)) return error.DuplicateComponentName;
        }
        try self.components.append(self.allocator, desc);
    }

    pub fn unregister(self: *ComponentRegistry, name: []const u8) !void {
        for (self.components.items, 0..) |existing, index| {
            if (std.mem.eql(u8, existing.name, name)) {
                _ = self.components.swapRemove(index);
                return;
            }
        }
        return error.UnknownComponentName;
    }

    pub fn entries(self: *const ComponentRegistry) []const ComponentDesc {
        return self.components.items;
    }
};

pub fn registerBuiltinComponents(registry: *ComponentRegistry) !void {
    try registry.register(.{
        .name = "game.scene_transform",
        .fields = &.{
            .{ .name = "position", .kind = .vec3f },
            .{ .name = "scale", .kind = .vec3f },
        },
    });
    try registry.register(.{
        .name = "game.scene_drawable",
        .fields = &.{
            .{ .name = "mesh_index", .kind = .u32 },
            .{ .name = "mesh_asset", .kind = .asset_id },
            .{ .name = "material_asset", .kind = .asset_id },
        },
    });
    try registry.register(.{
        .name = "game.physics_body",
        .fields = &.{
            .{ .name = "kind", .kind = .u32 },
            .{ .name = "mass", .kind = .f32 },
            .{ .name = "velocity", .kind = .vec3f },
            .{ .name = "friction", .kind = .f32 },
            .{ .name = "can_sleep", .kind = .bool },
            .{ .name = "continuous_collision", .kind = .bool },
            .{ .name = "half_extents", .kind = .vec3f },
        },
    });
}

test "component registry rejects duplicate names" {
    var registry = ComponentRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try registry.register(.{
        .name = "test.component",
        .fields = &.{},
    });
    try std.testing.expectError(error.DuplicateComponentName, registry.register(.{
        .name = "test.component",
        .fields = &.{},
    }));
}

test "component registry unregister removes names" {
    var registry = ComponentRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try registry.register(.{
        .name = "test.component",
        .fields = &.{},
    });
    try registry.unregister("test.component");
    try std.testing.expectEqual(@as(usize, 0), registry.entries().len);
    try std.testing.expectError(error.UnknownComponentName, registry.unregister("test.component"));
}

test "builtin components are registered" {
    var registry = ComponentRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try registerBuiltinComponents(&registry);
    try std.testing.expectEqual(@as(usize, 3), registry.entries().len);
    try std.testing.expectEqualStrings("game.scene_transform", registry.entries()[0].name);
}
