const std = @import("std");

pub const Entry = struct {
    asset_id: u64,
    source_path: []u8,
    artifact_path: []u8,
    kind: []u8,
    runtime_size_bytes: u64,

    pub fn deinit(self: *Entry, allocator: std.mem.Allocator) void {
        allocator.free(self.source_path);
        allocator.free(self.artifact_path);
        allocator.free(self.kind);
    }
};

pub const Catalog = struct {
    entries: []Entry,

    pub fn deinit(self: *Catalog, allocator: std.mem.Allocator) void {
        for (self.entries) |*entry| entry.deinit(allocator);
        allocator.free(self.entries);
    }

    pub fn findEntryBySourcePath(self: *const Catalog, source_path: []const u8) ?Entry {
        for (self.entries) |entry| {
            if (std.mem.eql(u8, entry.source_path, source_path)) return entry;
        }
        return null;
    }

    pub fn hasImportedMesh(self: *const Catalog, source_path: []const u8) bool {
        const entry = self.findEntryBySourcePath(source_path);
        return entry != null and std.mem.eql(u8, entry.?.kind, "mesh");
    }
};

pub fn load(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    target: []const u8,
) !Catalog {
    var dir = if (std.fs.path.isAbsolute(project_path))
        try std.Io.Dir.openDirAbsolute(io, project_path, .{})
    else
        try std.Io.Dir.cwd().openDir(io, project_path, .{});
    defer dir.close(io);

    const manifest_path = try std.fmt.allocPrint(allocator, "assets/cache/{s}/asset_manifest.json", .{target});
    defer allocator.free(manifest_path);
    const bytes = try dir.readFileAlloc(io, manifest_path, allocator, .limited(1024 * 1024));
    defer allocator.free(bytes);

    const Parsed = struct {
        assets: []const struct {
            asset_id: u64,
            source_path: []const u8,
            artifact_path: []const u8,
            kind: []const u8,
            runtime_size_bytes: u64,
        },
    };
    var parsed = try std.json.parseFromSlice(Parsed, allocator, bytes, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    var entries = try allocator.alloc(Entry, parsed.value.assets.len);
    errdefer allocator.free(entries);
    var initialized: usize = 0;
    errdefer {
        for (entries[0..initialized]) |*entry| entry.deinit(allocator);
    }
    for (parsed.value.assets, 0..) |asset, i| {
        entries[i] = .{
            .asset_id = asset.asset_id,
            .source_path = try allocator.dupe(u8, asset.source_path),
            .artifact_path = try allocator.dupe(u8, asset.artifact_path),
            .kind = try allocator.dupe(u8, asset.kind),
            .runtime_size_bytes = asset.runtime_size_bytes,
        };
        initialized = i + 1;
    }
    return .{ .entries = entries };
}
