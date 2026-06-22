const std = @import("std");
const friendly_engine = @import("friendly_engine");
const framework = friendly_engine.framework;

const storage_dir = ".friendly-engine/persistence";
const max_save_bytes = 16 * 1024 * 1024;

pub const FilePersistenceBackend = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, project_path: []const u8) !FilePersistenceBackend {
        return .{
            .allocator = allocator,
            .io = io,
            .project_path = try allocator.dupe(u8, project_path),
        };
    }

    pub fn deinit(self: *FilePersistenceBackend) void {
        self.allocator.free(self.project_path);
    }

    pub fn install(self: *FilePersistenceBackend, world: *framework.World) void {
        world.persistence.setBackend(.{
            .context = self,
            .vtable = &backend_vtable,
        });
    }

    fn save(context: *anyopaque, allocator: std.mem.Allocator, payload: framework.persistence.SavePayload) !void {
        _ = allocator;
        const self: *FilePersistenceBackend = @ptrCast(@alignCast(context));
        try validateSlot(payload.slot);
        const dir_path = try std.fs.path.join(self.allocator, &.{ self.project_path, storage_dir });
        defer self.allocator.free(dir_path);
        try std.Io.Dir.cwd().createDirPath(self.io, dir_path);

        const file_path = try storagePath(self.allocator, self.project_path, payload.slot);
        defer self.allocator.free(file_path);
        try std.Io.Dir.cwd().writeFile(self.io, .{
            .sub_path = file_path,
            .data = payload.bytes,
        });
    }

    fn load(context: *anyopaque, allocator: std.mem.Allocator, slot: []const u8) ![]u8 {
        const self: *FilePersistenceBackend = @ptrCast(@alignCast(context));
        try validateSlot(slot);
        const file_path = try storagePath(self.allocator, self.project_path, slot);
        defer self.allocator.free(file_path);
        return std.Io.Dir.cwd().readFileAlloc(
            self.io,
            file_path,
            allocator,
            .limited(max_save_bytes),
        );
    }
};

const backend_vtable = framework.persistence.BackendVTable{
    .save = FilePersistenceBackend.save,
    .load = FilePersistenceBackend.load,
};

fn storagePath(allocator: std.mem.Allocator, project_path: []const u8, slot: []const u8) ![]u8 {
    const file_name = try std.fmt.allocPrint(allocator, "{s}.bin", .{slot});
    defer allocator.free(file_name);
    return std.fs.path.join(allocator, &.{ project_path, storage_dir, file_name });
}

fn validateSlot(slot: []const u8) !void {
    if (slot.len == 0 or slot.len > 80) return error.InvalidPersistenceSlot;
    for (slot) |ch| {
        const ok = std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '-' or ch == '.';
        if (!ok) return error.InvalidPersistenceSlot;
    }
}

test "file persistence validates slot names" {
    try validateSlot("profile-1");
    try std.testing.expectError(error.InvalidPersistenceSlot, validateSlot("../profile"));
    try std.testing.expectError(error.InvalidPersistenceSlot, validateSlot(""));
}

test "file persistence saves and loads bytes" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    var backend = try FilePersistenceBackend.init(std.testing.allocator, std.testing.io, root);
    defer backend.deinit();
    try FilePersistenceBackend.save(&backend, std.testing.allocator, .{
        .slot = "profile",
        .bytes = "{\"ok\":true}",
    });
    const loaded = try FilePersistenceBackend.load(&backend, std.testing.allocator, "profile");
    defer std.testing.allocator.free(loaded);
    try std.testing.expectEqualStrings("{\"ok\":true}", loaded);
}
