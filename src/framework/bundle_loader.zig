const std = @import("std");
const assets = @import("assets.zig");
const pack_file = @import("pack_file.zig");

/// Maximum size for `bundle.json` metadata.
pub const max_bundle_bytes: usize = 1024 * 1024;
/// Maximum size for a single bundled artifact payload.
pub const max_artifact_bytes: usize = 64 * 1024 * 1024;

/// One entry from `bundle.json` (`schema_version` 1).
///
/// Tools write bundles to `assets/bundles/<target>/bundle.json` with:
/// - `schema_version`: u16
/// - `target`: bundle target name (e.g. `client-debug`)
/// - `asset_count`: number of assets
/// - `assets[]`: `{ artifact_path, content_hash, dependencies[] }`
///
/// `artifact_path` points at processed cache output (e.g. `assets/cache/client-debug/...`).
pub const BundleAsset = struct {
    asset_id: u64,
    artifact_path: []u8,
    kind: []u8,
    content_hash: u64,
    runtime_size_bytes: u64,
    pack_offset: ?u64 = null,
    pack_size: ?u64 = null,
    dependencies: [][]u8,

    pub fn deinit(self: *BundleAsset, allocator: std.mem.Allocator) void {
        allocator.free(self.artifact_path);
        allocator.free(self.kind);
        for (self.dependencies) |dependency| {
            allocator.free(dependency);
        }
        allocator.free(self.dependencies);
    }
};

pub const RuntimeBundle = struct {
    allocator: std.mem.Allocator,
    target: []u8,
    pack_file: ?[]u8 = null,
    index_file: ?[]u8 = null,
    assets: []BundleAsset,
    by_artifact_basename: std.StringHashMap(usize),
    by_dependency_basename: std.StringHashMap(usize),

    pub fn load(
        allocator: std.mem.Allocator,
        io: std.Io,
        project_path: []const u8,
        bundle_rel_path: []const u8,
    ) !RuntimeBundle {
        if (bundle_rel_path.len == 0) return error.MissingBundlePath;

        var project_dir = try openProjectDir(io, project_path);
        defer project_dir.close(io);

        const bytes = try project_dir.readFileAlloc(io, bundle_rel_path, allocator, .limited(max_bundle_bytes));
        defer allocator.free(bytes);

        return try parseBundleDoc(allocator, bytes);
    }

    pub fn deinit(self: *RuntimeBundle) void {
        for (self.assets) |*asset| {
            asset.deinit(self.allocator);
        }
        self.allocator.free(self.assets);
        self.allocator.free(self.target);
        if (self.pack_file) |path| self.allocator.free(path);
        if (self.index_file) |path| self.allocator.free(path);
        var artifact_keys = self.by_artifact_basename.keyIterator();
        while (artifact_keys.next()) |key| self.allocator.free(key.*);
        self.by_artifact_basename.deinit();
        var dependency_keys = self.by_dependency_basename.keyIterator();
        while (dependency_keys.next()) |key| self.allocator.free(key.*);
        self.by_dependency_basename.deinit();
    }

    pub fn assetCount(self: *const RuntimeBundle) usize {
        return self.assets.len;
    }

    pub fn findAssetForRef(self: *const RuntimeBundle, ref: []const u8) ?*const BundleAsset {
        const basename = std.fs.path.basename(ref);
        if (self.by_dependency_basename.get(basename)) |index| {
            return &self.assets[index];
        }
        if (self.by_artifact_basename.get(basename)) |index| {
            return &self.assets[index];
        }

        for (self.assets) |*asset| {
            if (sameStemBasename(asset.artifact_path, ref)) {
                return asset;
            }
            for (asset.dependencies) |dependency| {
                if (std.mem.eql(u8, dependency, ref) or std.mem.endsWith(u8, dependency, ref)) {
                    return asset;
                }
            }
            if (std.mem.endsWith(u8, asset.artifact_path, ref)) {
                return asset;
            }
        }
        return null;
    }

    pub fn readArtifact(
        self: *const RuntimeBundle,
        io: std.Io,
        project_path: []const u8,
        asset: *const BundleAsset,
        allocator: std.mem.Allocator,
    ) ![]u8 {
        var project_dir = try openProjectDir(io, project_path);
        defer project_dir.close(io);

        if (self.pack_file) |path| {
            if (asset.pack_offset) |offset| {
                const size = asset.pack_size orelse return error.InvalidPackIndex;
                return pack_file.readEntry(allocator, io, project_dir, path, offset, size);
            }
        }
        return project_dir.readFileAlloc(io, asset.artifact_path, allocator, .limited(max_artifact_bytes));
    }

    pub fn readBytesForRef(
        self: *const RuntimeBundle,
        io: std.Io,
        project_path: []const u8,
        ref: []const u8,
        allocator: std.mem.Allocator,
    ) !?[]u8 {
        const asset = self.findAssetForRef(ref) orelse return null;
        return try self.readArtifact(io, project_path, asset, allocator);
    }

    pub fn registerAssets(self: *const RuntimeBundle, asset_system: *assets.AssetSystem) !void {
        for (self.assets) |asset| {
            const kind = inferAssetKind(asset.artifact_path);
            const id = try asset_system.register(kind, asset.artifact_path);
            _ = asset_system.setState(id, .loaded);
        }
    }
};

fn sameStemBasename(a: []const u8, b: []const u8) bool {
    const a_base = std.fs.path.basename(a);
    const b_base = std.fs.path.basename(b);
    return std.mem.eql(u8, std.fs.path.stem(a_base), std.fs.path.stem(b_base));
}

fn openProjectDir(io: std.Io, project_path: []const u8) !std.Io.Dir {
    if (std.fs.path.isAbsolute(project_path)) {
        return try std.Io.Dir.openDirAbsolute(io, project_path, .{});
    }
    return try std.Io.Dir.cwd().openDir(io, project_path, .{});
}

fn parseBundleDoc(allocator: std.mem.Allocator, bytes: []const u8) !RuntimeBundle {
    const ParsedBundle = struct {
        schema_version: u16 = 1,
        target: []const u8,
        pack_file: ?[]const u8 = null,
        index_file: ?[]const u8 = null,
        assets: []const struct {
            asset_id: u64 = 0,
            artifact_path: []const u8,
            kind: []const u8 = "asset",
            content_hash: u64,
            runtime_size_bytes: u64 = 0,
            offset: ?u64 = null,
            size: ?u64 = null,
            dependencies: []const []const u8 = &.{},
        },
    };

    var parsed = try std.json.parseFromSlice(ParsedBundle, allocator, bytes, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    _ = parsed.value.schema_version;

    var owned_assets = try allocator.alloc(BundleAsset, parsed.value.assets.len);
    errdefer {
        var i: usize = 0;
        while (i > 0) {
            i -= 1;
            owned_assets[i].deinit(allocator);
        }
        allocator.free(owned_assets);
    }

    for (parsed.value.assets, 0..) |asset, index| {
        const dependencies = try allocator.alloc([]u8, asset.dependencies.len);
        errdefer {
            var i: usize = 0;
            while (i < index) {
                owned_assets[i].deinit(allocator);
                i += 1;
            }
            allocator.free(dependencies);
        }

        var dep_index: usize = 0;
        errdefer {
            while (dep_index > 0) {
                dep_index -= 1;
                allocator.free(dependencies[dep_index]);
            }
            allocator.free(dependencies);
        }
        for (asset.dependencies) |dependency| {
            dependencies[dep_index] = try allocator.dupe(u8, dependency);
            dep_index += 1;
        }

        owned_assets[index] = .{
            .asset_id = asset.asset_id,
            .artifact_path = try allocator.dupe(u8, asset.artifact_path),
            .kind = try allocator.dupe(u8, asset.kind),
            .content_hash = asset.content_hash,
            .runtime_size_bytes = asset.runtime_size_bytes,
            .pack_offset = asset.offset,
            .pack_size = asset.size,
            .dependencies = dependencies,
        };
    }

    var bundle = RuntimeBundle{
        .allocator = allocator,
        .target = try allocator.dupe(u8, parsed.value.target),
        .pack_file = if (parsed.value.pack_file) |path| try allocator.dupe(u8, path) else null,
        .index_file = if (parsed.value.index_file) |path| try allocator.dupe(u8, path) else null,
        .assets = owned_assets,
        .by_artifact_basename = std.StringHashMap(usize).init(allocator),
        .by_dependency_basename = std.StringHashMap(usize).init(allocator),
    };
    errdefer bundle.deinit();

    for (owned_assets, 0..) |asset, index| {
        const artifact_basename = std.fs.path.basename(asset.artifact_path);
        try bundle.by_artifact_basename.put(try allocator.dupe(u8, artifact_basename), index);
        for (asset.dependencies) |dependency| {
            const dependency_basename = std.fs.path.basename(dependency);
            try bundle.by_dependency_basename.put(try allocator.dupe(u8, dependency_basename), index);
        }
    }

    return bundle;
}

fn inferAssetKind(path: []const u8) []const u8 {
    const ext = std.fs.path.extension(path);
    if (std.mem.eql(u8, ext, ".png") or std.mem.eql(u8, ext, ".rgba") or std.mem.eql(u8, ext, ".jpg")) {
        return "texture";
    }
    if (std.mem.eql(u8, ext, ".obj") or std.mem.eql(u8, ext, ".glb") or std.mem.eql(u8, ext, ".fmesh")) {
        return "mesh";
    }
    return "asset";
}

test "runtime bundle load round trip reads artifacts" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, "assets/cache/client-debug/textures");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "assets/cache/client-debug/textures/wall.rgba",
        .data = "processed-texture-bytes",
    });

    const bundle_json =
        \\{
        \\  "schema_version": 1,
        \\  "target": "client-debug",
        \\  "asset_count": 1,
        \\  "assets": [
        \\    {
        \\      "artifact_path": "assets/cache/client-debug/textures/wall.rgba",
        \\      "content_hash": 1234,
        \\      "dependencies": ["textures/wall.png"]
        \\    }
        \\  ]
        \\}
        \\
    ;
    try tmp.dir.createDirPath(std.testing.io, "assets/bundles/client-debug");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "assets/bundles/client-debug/bundle.json",
        .data = bundle_json,
    });

    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);

    var bundle = try RuntimeBundle.load(
        std.testing.allocator,
        std.testing.io,
        project_path,
        "assets/bundles/client-debug/bundle.json",
    );
    defer bundle.deinit();

    try std.testing.expectEqual(@as(usize, 1), bundle.assetCount());
    try std.testing.expectEqualStrings("client-debug", bundle.target);

    const asset = bundle.findAssetForRef("textures/wall.png").?;
    try std.testing.expectEqual(@as(u64, 1234), asset.content_hash);

    const bytes = (try bundle.readBytesForRef(
        std.testing.io,
        project_path,
        "textures/wall.png",
        std.testing.allocator,
    )).?;
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualStrings("processed-texture-bytes", bytes);

    var asset_system = assets.AssetSystem.init(std.testing.allocator);
    defer asset_system.deinit();
    try bundle.registerAssets(&asset_system);
    try std.testing.expectEqual(@as(usize, 1), asset_system.count());
}

test "runtime bundle reads packed artifact byte ranges" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, "assets/bundles/client-debug");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "assets/bundles/client-debug/game.fpack",
        .data = "aaaapacked-texturezz",
    });
    const bundle_json =
        \\{
        \\  "schema_version": 1,
        \\  "target": "client-debug",
        \\  "pack_file": "assets/bundles/client-debug/game.fpack",
        \\  "asset_count": 1,
        \\  "assets": [
        \\    {
        \\      "asset_id": 99,
        \\      "artifact_path": "assets/cache/client-debug/textures/wall.rgba",
        \\      "kind": "texture",
        \\      "content_hash": 1234,
        \\      "runtime_size_bytes": 14,
        \\      "offset": 4,
        \\      "size": 14,
        \\      "dependencies": ["textures/wall.png"]
        \\    }
        \\  ]
        \\}
        \\
    ;
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "assets/bundles/client-debug/bundle.json",
        .data = bundle_json,
    });

    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);
    var bundle = try RuntimeBundle.load(
        std.testing.allocator,
        std.testing.io,
        project_path,
        "assets/bundles/client-debug/bundle.json",
    );
    defer bundle.deinit();

    const bytes = (try bundle.readBytesForRef(
        std.testing.io,
        project_path,
        "textures/wall.png",
        std.testing.allocator,
    )).?;
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualStrings("packed-texture", bytes);
}
