const std = @import("std");

pub const TempArena = struct {
    arena: std.heap.ArenaAllocator,

    pub fn init(backing_allocator: std.mem.Allocator) TempArena {
        return .{
            .arena = std.heap.ArenaAllocator.init(backing_allocator),
        };
    }

    pub fn allocator(self: *TempArena) std.mem.Allocator {
        return self.arena.allocator();
    }

    pub fn reset(self: *TempArena) void {
        _ = self.arena.reset(.retain_capacity);
    }

    pub fn deinit(self: *TempArena) void {
        self.arena.deinit();
    }
};

pub fn zeroedAlloc(allocator: std.mem.Allocator, comptime T: type, count: usize) ![]T {
    const items = try allocator.alloc(T, count);
    @memset(items, std.mem.zeroes(T));
    return items;
}

pub fn dupeBytes(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    return allocator.dupe(u8, bytes);
}

pub const OwnedBytes = struct {
    allocator: std.mem.Allocator,
    bytes: []u8,

    pub fn fromSlice(allocator: std.mem.Allocator, source: []const u8) !OwnedBytes {
        return .{
            .allocator = allocator,
            .bytes = try allocator.dupe(u8, source),
        };
    }

    pub fn deinit(self: *OwnedBytes) void {
        self.allocator.free(self.bytes);
        self.bytes = &.{};
    }
};

test "zeroed alloc returns initialized memory" {
    const allocator = std.testing.allocator;
    const values = try zeroedAlloc(allocator, u32, 4);
    defer allocator.free(values);

    for (values) |value| {
        try std.testing.expectEqual(@as(u32, 0), value);
    }
}

test "temp arena reset frees temporaries" {
    var arena = TempArena.init(std.testing.allocator);
    defer arena.deinit();

    const tmp = try arena.allocator().alloc(u8, 32);
    @memset(tmp, 0xAB);
    arena.reset();

    const tmp2 = try arena.allocator().alloc(u8, 16);
    try std.testing.expectEqual(@as(usize, 16), tmp2.len);
}

test "owned bytes duplicates source" {
    var owned = try OwnedBytes.fromSlice(std.testing.allocator, "abc");
    defer owned.deinit();

    try std.testing.expectEqualStrings("abc", owned.bytes);
}
