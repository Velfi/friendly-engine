const std = @import("std");

pub const EntityId = u64;
pub const ComponentTypeId = u32;
pub const SceneId = u64;
pub const AssetId = u64;
pub const ActionId = u64;
pub const ConnectionId = u32;

pub const IdGenerator = struct {
    next: u64 = 1,

    pub fn init(start: u64) IdGenerator {
        return .{ .next = start };
    }

    pub fn nextId(self: *IdGenerator) u64 {
        const id = self.next;
        self.next += 1;
        return id;
    }
};

pub fn hashString64(bytes: []const u8) u64 {
    return std.hash.Wyhash.hash(0, bytes);
}

pub fn componentTypeId(comptime T: type) ComponentTypeId {
    const hash = hashString64(@typeName(T));
    return @as(ComponentTypeId, @intCast(hash & std.math.maxInt(ComponentTypeId)));
}

test "id generator emits monotonic ids" {
    var generator = IdGenerator.init(41);
    try std.testing.expectEqual(@as(u64, 41), generator.nextId());
    try std.testing.expectEqual(@as(u64, 42), generator.nextId());
}

test "string hashing is stable" {
    const a = hashString64("entity.player");
    const b = hashString64("entity.player");
    const c = hashString64("entity.enemy");
    try std.testing.expectEqual(a, b);
    try std.testing.expect(a != c);
}

test "component type ids are deterministic" {
    const Transform = struct { x: f32 };
    const id_a = componentTypeId(Transform);
    const id_b = componentTypeId(Transform);
    try std.testing.expectEqual(id_a, id_b);
}
