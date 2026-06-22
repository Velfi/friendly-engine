const std = @import("std");

pub const SavePayload = struct {
    slot: []const u8,
    bytes: []const u8,
};

pub const BackendVTable = struct {
    save: *const fn (context: *anyopaque, allocator: std.mem.Allocator, payload: SavePayload) anyerror!void,
    load: *const fn (context: *anyopaque, allocator: std.mem.Allocator, slot: []const u8) anyerror![]u8,
};

pub const Backend = struct {
    context: *anyopaque,
    vtable: *const BackendVTable,
};

pub const PersistenceSystem = struct {
    allocator: std.mem.Allocator,
    backend: ?Backend = null,
    root_label: []const u8,
    save_count: u64 = 0,
    load_count: u64 = 0,

    pub fn init(allocator: std.mem.Allocator) PersistenceSystem {
        return .{
            .allocator = allocator,
            .root_label = "",
        };
    }

    pub fn deinit(self: *PersistenceSystem) void {
        if (self.root_label.len > 0) self.allocator.free(self.root_label);
    }

    pub fn setBackend(self: *PersistenceSystem, backend: Backend) void {
        self.backend = backend;
    }

    pub fn setRootLabel(self: *PersistenceSystem, root_label: []const u8) !void {
        if (self.root_label.len > 0) self.allocator.free(self.root_label);
        self.root_label = try self.allocator.dupe(u8, root_label);
    }

    pub fn save(self: *PersistenceSystem, slot: []const u8, bytes: []const u8) !void {
        const backend = self.backend orelse return error.PersistenceBackendMissing;
        try backend.vtable.save(backend.context, self.allocator, .{
            .slot = slot,
            .bytes = bytes,
        });
        self.save_count += 1;
    }

    pub fn load(self: *PersistenceSystem, slot: []const u8) ![]u8 {
        const backend = self.backend orelse return error.PersistenceBackendMissing;
        const bytes = try backend.vtable.load(backend.context, self.allocator, slot);
        self.load_count += 1;
        return bytes;
    }
};

const PersistenceTestContext = struct {
    saved_slot: ?[]const u8 = null,
    saved_bytes: ?[]const u8 = null,
};

fn mockSave(context: *anyopaque, allocator: std.mem.Allocator, payload: SavePayload) !void {
    const typed_context: *PersistenceTestContext = @ptrCast(@alignCast(context));
    typed_context.saved_slot = try allocator.dupe(u8, payload.slot);
    typed_context.saved_bytes = try allocator.dupe(u8, payload.bytes);
}

fn mockLoad(context: *anyopaque, allocator: std.mem.Allocator, slot: []const u8) ![]u8 {
    _ = context;
    return std.fmt.allocPrint(allocator, "loaded:{s}", .{slot});
}

const mock_backend_vtable = BackendVTable{
    .save = mockSave,
    .load = mockLoad,
};

test "persistence system fails loudly without storage backend" {
    var persistence = PersistenceSystem.init(std.testing.allocator);
    defer persistence.deinit();

    try std.testing.expectError(error.PersistenceBackendMissing, persistence.save("profile", "{}"));
    try std.testing.expectError(error.PersistenceBackendMissing, persistence.load("profile"));
}

test "persistence system routes through backend" {
    var persistence = PersistenceSystem.init(std.testing.allocator);
    defer persistence.deinit();

    var context = PersistenceTestContext{};
    defer if (context.saved_slot) |slot| std.testing.allocator.free(slot);
    defer if (context.saved_bytes) |bytes| std.testing.allocator.free(bytes);
    persistence.setBackend(.{
        .context = &context,
        .vtable = &mock_backend_vtable,
    });

    try persistence.save("profile", "{\"ok\":true}");
    const loaded = try persistence.load("profile");
    defer std.testing.allocator.free(loaded);

    try std.testing.expectEqualStrings("profile", context.saved_slot.?);
    try std.testing.expectEqualStrings("{\"ok\":true}", context.saved_bytes.?);
    try std.testing.expectEqualStrings("loaded:profile", loaded);
    try std.testing.expectEqual(@as(u64, 1), persistence.save_count);
    try std.testing.expectEqual(@as(u64, 1), persistence.load_count);
}
