const std = @import("std");
const core = @import("../core/mod.zig");

pub const AssetState = enum(u8) {
    unloaded,
    loaded,
};

pub const AssetRecord = struct {
    id: core.AssetId,
    path: []const u8,
    kind: []const u8,
    state: AssetState = .unloaded,
};

pub const AssetSystem = struct {
    allocator: std.mem.Allocator,
    assets: std.AutoHashMap(core.AssetId, AssetRecord),

    pub fn init(allocator: std.mem.Allocator) AssetSystem {
        return .{
            .allocator = allocator,
            .assets = std.AutoHashMap(core.AssetId, AssetRecord).init(allocator),
        };
    }

    pub fn deinit(self: *AssetSystem) void {
        var iter = self.assets.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.path);
            self.allocator.free(entry.value_ptr.kind);
        }
        self.assets.deinit();
    }

    pub fn register(self: *AssetSystem, kind: []const u8, path: []const u8) !core.AssetId {
        const id = core.ids.hashString64(path);
        if (self.assets.get(id) != null) return id;

        const owned_path = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(owned_path);
        const owned_kind = try self.allocator.dupe(u8, kind);
        errdefer self.allocator.free(owned_kind);

        try self.assets.put(id, .{
            .id = id,
            .path = owned_path,
            .kind = owned_kind,
            .state = .unloaded,
        });
        return id;
    }

    pub fn setState(self: *AssetSystem, asset_id: core.AssetId, state: AssetState) bool {
        if (self.assets.getPtr(asset_id)) |record| {
            record.state = state;
            return true;
        }
        return false;
    }

    pub fn get(self: *const AssetSystem, asset_id: core.AssetId) ?AssetRecord {
        return self.assets.get(asset_id);
    }

    pub fn count(self: *const AssetSystem) usize {
        return self.assets.count();
    }
};

test "asset system registers and tracks state" {
    var assets = AssetSystem.init(std.testing.allocator);
    defer assets.deinit();

    const id = try assets.register("texture", "assets/source/wall.png");
    try std.testing.expectEqual(@as(usize, 1), assets.count());

    const loaded = assets.setState(id, .loaded);
    try std.testing.expect(loaded);

    const record = assets.get(id).?;
    try std.testing.expectEqualStrings("texture", record.kind);
    try std.testing.expectEqual(.loaded, record.state);
}

test "asset system deduplicates by path id" {
    var assets = AssetSystem.init(std.testing.allocator);
    defer assets.deinit();

    const a = try assets.register("mesh", "assets/source/crate.glb");
    const b = try assets.register("mesh", "assets/source/crate.glb");
    try std.testing.expectEqual(a, b);
    try std.testing.expectEqual(@as(usize, 1), assets.count());
}
