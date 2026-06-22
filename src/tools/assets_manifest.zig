const std = @import("std");

pub const max_metadata_bytes: usize = 1024 * 1024;

pub const ManifestAsset = struct {
    asset_id: u64,
    source_path: []u8,
    artifact_path: []u8,
    kind: []u8,
    content_hash: u64,
    runtime_size_bytes: u64,
    dependencies: [][]u8,

    pub fn deinit(self: *ManifestAsset, allocator: std.mem.Allocator) void {
        allocator.free(self.source_path);
        allocator.free(self.artifact_path);
        allocator.free(self.kind);
        for (self.dependencies) |dependency| {
            allocator.free(dependency);
        }
        allocator.free(self.dependencies);
        self.* = undefined;
    }
};

const CacheEntryMeta = struct {
    schema_version: u16 = 1,
    asset_id: u64,
    source_path: []const u8,
    artifact_path: []const u8,
    kind: []const u8,
    target: []const u8,
    content_hash: u64,
    runtime_size_bytes: u64,
    dependencies: []const []const u8 = &.{},
};

const ManifestAssetView = struct {
    asset_id: u64,
    source_path: []const u8,
    artifact_path: []const u8,
    kind: []const u8,
    content_hash: u64,
    runtime_size_bytes: u64,
    dependencies: []const []const u8,
};

pub const BundleAssetView = struct {
    asset_id: u64,
    artifact_path: []const u8,
    kind: []const u8,
    content_hash: u64,
    runtime_size_bytes: u64,
    dependencies: []const []const u8,
};

pub fn computeAssetId(path: []const u8) u64 {
    return std.hash.Wyhash.hash(0x4652415353455449, path);
}

pub fn computeContentHash(bytes: []const u8, dependencies: []const []const u8) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(bytes);
    for (dependencies) |dependency| {
        hasher.update(dependency);
        hasher.update("\n");
    }
    return hasher.final();
}

pub fn readDependencies(io: std.Io, root_dir: std.Io.Dir, allocator: std.mem.Allocator, source_path: []const u8) ![][]u8 {
    const deps_path = try std.fmt.allocPrint(allocator, "{s}.deps", .{source_path});
    defer allocator.free(deps_path);

    const deps_bytes = root_dir.readFileAlloc(io, deps_path, allocator, .limited(max_metadata_bytes)) catch |err| switch (err) {
        error.FileNotFound => return allocator.alloc([]u8, 0),
        else => return err,
    };
    defer allocator.free(deps_bytes);

    var dependencies = std.ArrayList([]u8).empty;
    errdefer {
        for (dependencies.items) |dependency| {
            allocator.free(dependency);
        }
        dependencies.deinit(allocator);
    }

    var lines = std.mem.splitScalar(u8, deps_bytes, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        if (trimmed[0] == '#') continue;
        try dependencies.append(allocator, try allocator.dupe(u8, trimmed));
    }
    return dependencies.toOwnedSlice(allocator);
}

pub fn freeDependencies(allocator: std.mem.Allocator, dependencies: [][]u8) void {
    for (dependencies) |dependency| {
        allocator.free(dependency);
    }
    allocator.free(dependencies);
}

pub fn loadCachedEntryIfFresh(
    io: std.Io,
    root_dir: std.Io.Dir,
    allocator: std.mem.Allocator,
    metadata_path: []const u8,
    expected_target: []const u8,
    expected_content_hash: u64,
) !?ManifestAsset {
    const metadata_bytes = root_dir.readFileAlloc(io, metadata_path, allocator, .limited(max_metadata_bytes)) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer allocator.free(metadata_bytes);

    const ParsedMeta = struct {
        schema_version: u16 = 1,
        asset_id: u64,
        source_path: []const u8,
        artifact_path: []const u8,
        kind: []const u8,
        target: []const u8,
        content_hash: u64,
        runtime_size_bytes: u64,
        dependencies: []const []const u8 = &.{},
    };

    var parsed_meta = std.json.parseFromSlice(ParsedMeta, allocator, metadata_bytes, .{
        .ignore_unknown_fields = true,
    }) catch return null;
    defer parsed_meta.deinit();

    _ = parsed_meta.value.schema_version;
    if (!std.mem.eql(u8, parsed_meta.value.target, expected_target)) return null;
    if (parsed_meta.value.content_hash != expected_content_hash) return null;

    root_dir.access(io, parsed_meta.value.artifact_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };

    const dependencies = try duplicateDependencies(allocator, parsed_meta.value.dependencies);
    errdefer freeDependencies(allocator, dependencies);

    return ManifestAsset{
        .asset_id = parsed_meta.value.asset_id,
        .source_path = try allocator.dupe(u8, parsed_meta.value.source_path),
        .artifact_path = try allocator.dupe(u8, parsed_meta.value.artifact_path),
        .kind = try allocator.dupe(u8, parsed_meta.value.kind),
        .content_hash = parsed_meta.value.content_hash,
        .runtime_size_bytes = parsed_meta.value.runtime_size_bytes,
        .dependencies = dependencies,
    };
}

fn duplicateDependencies(allocator: std.mem.Allocator, dependencies: []const []const u8) ![][]u8 {
    var owned_dependencies = try allocator.alloc([]u8, dependencies.len);
    var i: usize = 0;
    errdefer {
        while (i > 0) {
            i -= 1;
            allocator.free(owned_dependencies[i]);
        }
        allocator.free(owned_dependencies);
    }
    for (dependencies) |dependency| {
        owned_dependencies[i] = try allocator.dupe(u8, dependency);
        i += 1;
    }
    return owned_dependencies;
}

pub fn buildManifestAsset(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    artifact_path: []const u8,
    kind: []const u8,
    content_hash: u64,
    runtime_size_bytes: u64,
    dependencies: [][]u8,
) !ManifestAsset {
    return .{
        .asset_id = computeAssetId(source_path),
        .source_path = try allocator.dupe(u8, source_path),
        .artifact_path = try allocator.dupe(u8, artifact_path),
        .kind = try allocator.dupe(u8, kind),
        .content_hash = content_hash,
        .runtime_size_bytes = runtime_size_bytes,
        .dependencies = dependencies,
    };
}

pub fn writeMetadata(
    io: std.Io,
    root_dir: std.Io.Dir,
    allocator: std.mem.Allocator,
    metadata_path: []const u8,
    asset: ManifestAsset,
    target: []const u8,
) !void {
    const meta = CacheEntryMeta{
        .asset_id = asset.asset_id,
        .source_path = asset.source_path,
        .artifact_path = asset.artifact_path,
        .kind = asset.kind,
        .target = target,
        .content_hash = asset.content_hash,
        .runtime_size_bytes = asset.runtime_size_bytes,
        .dependencies = asset.dependencies,
    };
    try writeJsonFile(io, root_dir, allocator, metadata_path, meta);
}

pub fn buildManifestViews(allocator: std.mem.Allocator, assets: []const ManifestAsset) ![]ManifestAssetView {
    var views = try allocator.alloc(ManifestAssetView, assets.len);
    for (assets, 0..) |asset, idx| {
        views[idx] = .{
            .asset_id = asset.asset_id,
            .source_path = asset.source_path,
            .artifact_path = asset.artifact_path,
            .kind = asset.kind,
            .content_hash = asset.content_hash,
            .runtime_size_bytes = asset.runtime_size_bytes,
            .dependencies = asset.dependencies,
        };
    }
    return views;
}

pub fn writeJsonFile(io: std.Io, root_dir: std.Io.Dir, allocator: std.mem.Allocator, path: []const u8, value: anytype) !void {
    if (std.fs.path.dirname(path)) |parent| {
        try root_dir.createDirPath(io, parent);
    }

    const json_bytes = try std.fmt.allocPrint(
        allocator,
        "{f}\n",
        .{std.json.fmt(value, .{ .whitespace = .indent_2 })},
    );
    defer allocator.free(json_bytes);

    try root_dir.writeFile(io, .{
        .sub_path = path,
        .data = json_bytes,
    });
}
