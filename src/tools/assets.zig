const std = @import("std");
const png_import = @import("png_import.zig");
const gltf_import = @import("gltf_import.zig");
const scene_bake = @import("scene_bake.zig");
const world_bake = @import("world_bake.zig");
const terrain_tools = @import("terrain.zig");
const assets_manifest = @import("assets_manifest.zig");
const asset_pack = @import("asset_pack.zig");
const assets_query = @import("assets_query.zig");

const max_asset_bytes: usize = 64 * 1024 * 1024;

pub const PipelinePaths = struct {
    source_dir: []const u8 = "assets/source",
    cache_dir: []const u8 = "assets/cache",
    bundles_dir: []const u8 = "assets/bundles",
    target: []const u8 = "client-debug",
    scene_path: []const u8 = "scenes/main.kdl",
};

pub const ImportSummary = struct {
    scanned: usize = 0,
    imported: usize = 0,
    skipped: usize = 0,
};

pub const BundleSummary = struct {
    asset_count: usize = 0,
    packed_bytes: u64 = 0,
};

pub fn importAssets(io: std.Io, root_dir: std.Io.Dir, allocator: std.mem.Allocator, paths: PipelinePaths) !ImportSummary {
    var summary = ImportSummary{};
    var collected_assets = std.ArrayList(assets_manifest.ManifestAsset).empty;
    defer {
        for (collected_assets.items) |*asset| {
            asset.deinit(allocator);
        }
        collected_assets.deinit(allocator);
    }

    const cache_target_path = try std.fs.path.join(allocator, &.{ paths.cache_dir, paths.target });
    defer allocator.free(cache_target_path);
    try root_dir.createDirPath(io, cache_target_path);

    var source_dir = try root_dir.openDir(io, paths.source_dir, .{ .iterate = true });
    defer source_dir.close(io);

    var walker = try source_dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (std.mem.endsWith(u8, entry.path, ".deps")) continue;
        summary.scanned += 1;

        const source_path = try std.fs.path.join(allocator, &.{ paths.source_dir, entry.path });
        defer allocator.free(source_path);

        const source_bytes = try root_dir.readFileAlloc(io, source_path, allocator, .limited(max_asset_bytes));
        defer allocator.free(source_bytes);

        const dependencies = try assets_manifest.readDependencies(io, root_dir, allocator, source_path);
        errdefer assets_manifest.freeDependencies(allocator, dependencies);
        const content_hash = assets_manifest.computeContentHash(source_bytes, dependencies);

        const artifact_path = try convertedArtifactPath(allocator, paths.cache_dir, paths.target, entry.path);
        defer allocator.free(artifact_path);
        const metadata_path = try std.fmt.allocPrint(allocator, "{s}.meta.json", .{artifact_path});
        defer allocator.free(metadata_path);

        if (try assets_manifest.loadCachedEntryIfFresh(io, root_dir, allocator, metadata_path, paths.target, content_hash)) |existing| {
            try collected_assets.append(allocator, existing);
            summary.skipped += 1;
            assets_manifest.freeDependencies(allocator, dependencies);
            continue;
        }

        const converted = try convertSourceAsset(allocator, entry.path, source_bytes);
        defer if (converted.owned) |owned| allocator.free(owned);

        if (std.fs.path.dirname(artifact_path)) |artifact_dir| {
            try root_dir.createDirPath(io, artifact_dir);
        }
        try root_dir.writeFile(io, .{
            .sub_path = artifact_path,
            .data = converted.bytes,
        });

        const kind = inferAssetKind(artifact_path);
        var imported_entry = try assets_manifest.buildManifestAsset(
            allocator,
            source_path,
            artifact_path,
            kind,
            content_hash,
            @intCast(converted.bytes.len),
            dependencies,
        );
        errdefer imported_entry.deinit(allocator);
        try assets_manifest.writeMetadata(io, root_dir, allocator, metadata_path, imported_entry, paths.target);
        try collected_assets.append(allocator, imported_entry);
        summary.imported += 1;
    }

    const manifest_path = try std.fs.path.join(allocator, &.{ paths.cache_dir, paths.target, "asset_manifest.json" });
    defer allocator.free(manifest_path);

    const asset_views = try assets_manifest.buildManifestViews(allocator, collected_assets.items);
    defer allocator.free(asset_views);

    const manifest_doc = .{
        .schema_version = @as(u16, 1),
        .target = paths.target,
        .stats = .{
            .scanned = summary.scanned,
            .imported = summary.imported,
            .skipped = summary.skipped,
        },
        .assets = asset_views,
    };
    try assets_manifest.writeJsonFile(io, root_dir, allocator, manifest_path, manifest_doc);
    return summary;
}

pub fn bundleAssets(io: std.Io, root_dir: std.Io.Dir, allocator: std.mem.Allocator, paths: PipelinePaths) !BundleSummary {
    const manifest_path = try std.fs.path.join(allocator, &.{ paths.cache_dir, paths.target, "asset_manifest.json" });
    defer allocator.free(manifest_path);

    const manifest_bytes = try root_dir.readFileAlloc(io, manifest_path, allocator, .limited(assets_manifest.max_metadata_bytes));
    defer allocator.free(manifest_bytes);

    const ManifestDoc = struct {
        schema_version: u16 = 1,
        target: []const u8,
        assets: []const struct {
            asset_id: u64,
            source_path: []const u8,
            artifact_path: []const u8,
            kind: []const u8,
            content_hash: u64,
            runtime_size_bytes: u64,
            dependencies: []const []const u8 = &.{},
        },
    };

    var parsed_manifest = try std.json.parseFromSlice(ManifestDoc, allocator, manifest_bytes, .{
        .ignore_unknown_fields = true,
    });
    defer parsed_manifest.deinit();

    var pack_entries = try allocator.alloc(asset_pack.PackEntry, parsed_manifest.value.assets.len);
    defer allocator.free(pack_entries);

    for (parsed_manifest.value.assets, 0..) |asset, idx| {
        _ = asset.source_path;
        pack_entries[idx] = .{
            .asset_id = asset.asset_id,
            .artifact_path = asset.artifact_path,
            .kind = asset.kind,
            .content_hash = asset.content_hash,
            .offset = 0,
            .size = asset.runtime_size_bytes,
            .dependencies = asset.dependencies,
        };
    }

    var pack = try asset_pack.writePack(io, root_dir, allocator, paths.target, paths.bundles_dir, pack_entries);
    defer pack.deinit(allocator);

    const bundle_doc = .{
        .schema_version = @as(u16, 1),
        .target = parsed_manifest.value.target,
        .pack_file = pack.pack_file,
        .index_file = pack.index_file,
        .asset_count = pack_entries.len,
        .assets = pack_entries,
    };

    const bundle_path = try std.fs.path.join(allocator, &.{ paths.bundles_dir, paths.target, "bundle.json" });
    defer allocator.free(bundle_path);
    try assets_manifest.writeJsonFile(io, root_dir, allocator, bundle_path, bundle_doc);
    return .{ .asset_count = pack_entries.len, .packed_bytes = pack.byte_count };
}

pub fn runCli(allocator: std.mem.Allocator, io: std.Io, args: []const []const u8) !void {
    if (args.len < 2) {
        printUsage();
        return error.InvalidArguments;
    }

    const command = args[1];
    if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h")) {
        printUsage();
        return;
    }
    if (std.mem.eql(u8, command, "world-bake")) {
        try world_bake.runCli(allocator, io, args[2..]);
        return;
    }
    if (std.mem.eql(u8, command, "terrain")) {
        try terrain_tools.runCli(allocator, io, args[2..]);
        return;
    }
    if (std.mem.eql(u8, command, "assets.describe")) {
        try assets_query.runCli(allocator, io, args[2..]);
        return;
    }

    var paths = PipelinePaths{};
    try applyCliFlags(&paths, args[2..]);

    if (std.mem.eql(u8, command, "import")) {
        const summary = try importAssets(io, std.Io.Dir.cwd(), allocator, paths);
        std.debug.print(
            "import complete: scanned={d} imported={d} skipped={d}\n",
            .{ summary.scanned, summary.imported, summary.skipped },
        );
        return;
    }
    if (std.mem.eql(u8, command, "bundle")) {
        const summary = try bundleAssets(io, std.Io.Dir.cwd(), allocator, paths);
        std.debug.print("bundle complete: assets={d} packed_bytes={d}\n", .{ summary.asset_count, summary.packed_bytes });
        return;
    }
    if (std.mem.eql(u8, command, "bake-scene")) {
        const bundle_path = try std.fs.path.join(allocator, &.{ paths.bundles_dir, paths.target, "bundle.json" });
        defer allocator.free(bundle_path);
        const summary = try scene_bake.bakeScene(
            allocator,
            io,
            std.Io.Dir.cwd(),
            ".",
            paths.scene_path,
            paths.target,
            bundle_path,
        );
        std.debug.print(
            "bake-scene complete: scene={s} baked={s} objects={d}\n",
            .{ summary.scene_path, summary.baked_path, summary.object_count },
        );
        allocator.free(summary.scene_path);
        allocator.free(summary.baked_path);
        return;
    }
    if (std.mem.eql(u8, command, "bake")) {
        const import_summary = try importAssets(io, std.Io.Dir.cwd(), allocator, paths);
        const bundle_summary = try bundleAssets(io, std.Io.Dir.cwd(), allocator, paths);
        const bundle_path = try std.fs.path.join(allocator, &.{ paths.bundles_dir, paths.target, "bundle.json" });
        defer allocator.free(bundle_path);
        const scene_summary = try scene_bake.bakeScene(
            allocator,
            io,
            std.Io.Dir.cwd(),
            ".",
            paths.scene_path,
            paths.target,
            bundle_path,
        );
        std.debug.print(
            "bake complete: imported={d} bundled={d} scene_objects={d} baked={s}\n",
            .{ import_summary.imported, bundle_summary.asset_count, scene_summary.object_count, scene_summary.baked_path },
        );
        allocator.free(scene_summary.scene_path);
        allocator.free(scene_summary.baked_path);
        return;
    }
    if (std.mem.eql(u8, command, "describe")) {
        try @import("describe.zig").runDescribe(allocator);
        return;
    }
    if (std.mem.eql(u8, command, "write-schemas")) {
        try @import("schemas.zig").writeSchemaFiles(allocator, io);
        std.debug.print("schemas written to docs/schema/\n", .{});
        return;
    }

    printUsage();
    return error.InvalidArguments;
}

fn applyCliFlags(paths: *PipelinePaths, flags: []const []const u8) !void {
    var i: usize = 0;
    while (i < flags.len) {
        const flag = flags[i];
        i += 1;
        if (i >= flags.len) return error.InvalidArguments;
        const value = flags[i];
        i += 1;

        if (std.mem.eql(u8, flag, "--source")) {
            paths.source_dir = value;
            continue;
        }
        if (std.mem.eql(u8, flag, "--cache")) {
            paths.cache_dir = value;
            continue;
        }
        if (std.mem.eql(u8, flag, "--bundles")) {
            paths.bundles_dir = value;
            continue;
        }
        if (std.mem.eql(u8, flag, "--target")) {
            paths.target = value;
            continue;
        }
        if (std.mem.eql(u8, flag, "--scene")) {
            paths.scene_path = value;
            continue;
        }
        return error.InvalidArguments;
    }
}

fn printUsage() void {
    std.debug.print(
        "usage: friendly_engine_tools <import|bundle|bake-scene|world-bake|terrain|bake|describe|assets.describe|write-schemas> [--source dir] [--cache dir] [--bundles dir] [--target name] [--scene path] [--cell x,y,z]\n",
        .{},
    );
    std.debug.print(
        "       friendly_engine_tools terrain validate [--project dir] [--world path]\n",
        .{},
    );
}

const ConvertedAsset = struct {
    bytes: []const u8,
    owned: ?[]u8,
};

fn convertSourceAsset(allocator: std.mem.Allocator, source_rel_path: []const u8, source_bytes: []const u8) !ConvertedAsset {
    const ext = std.fs.path.extension(source_rel_path);
    if (std.ascii.eqlIgnoreCase(ext, ".png")) {
        const rgba = try png_import.decodePngToRgba128(allocator, source_bytes);
        return .{ .bytes = rgba, .owned = rgba };
    }
    if (std.ascii.eqlIgnoreCase(ext, ".glb") or std.ascii.eqlIgnoreCase(ext, ".gltf")) {
        const mesh_bytes = try gltf_import.importGlb(allocator, source_bytes);
        return .{ .bytes = mesh_bytes, .owned = mesh_bytes };
    }
    return .{ .bytes = source_bytes, .owned = null };
}

fn convertedArtifactPath(allocator: std.mem.Allocator, cache_dir: []const u8, target: []const u8, source_rel_path: []const u8) ![]u8 {
    const ext = std.fs.path.extension(source_rel_path);
    const stem_path = if (ext.len > 0)
        source_rel_path[0 .. source_rel_path.len - ext.len]
    else
        source_rel_path;

    const out_ext: []const u8 = if (std.ascii.eqlIgnoreCase(ext, ".png"))
        ".rgba"
    else if (std.ascii.eqlIgnoreCase(ext, ".glb") or std.ascii.eqlIgnoreCase(ext, ".gltf"))
        ".fmesh"
    else
        ext;

    const rel_with_ext = if (out_ext.len > 0)
        try std.fmt.allocPrint(allocator, "{s}{s}", .{ stem_path, out_ext })
    else
        try allocator.dupe(u8, source_rel_path);
    defer allocator.free(rel_with_ext);

    return std.fs.path.join(allocator, &.{ cache_dir, target, rel_with_ext });
}

fn inferAssetKind(path: []const u8) []const u8 {
    const ext = std.fs.path.extension(path);
    if (std.ascii.eqlIgnoreCase(ext, ".rgba") or std.ascii.eqlIgnoreCase(ext, ".png") or std.ascii.eqlIgnoreCase(ext, ".jpg")) {
        return "texture";
    }
    if (std.ascii.eqlIgnoreCase(ext, ".fmesh") or std.ascii.eqlIgnoreCase(ext, ".glb") or std.ascii.eqlIgnoreCase(ext, ".gltf")) {
        return "mesh";
    }
    if (std.ascii.eqlIgnoreCase(ext, ".fscene") or std.ascii.eqlIgnoreCase(ext, ".kdl")) {
        return "scene";
    }
    return "asset";
}

test "asset pipeline imports incrementally and bundles outputs" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, "assets/source/textures");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "assets/source/mesh.obj",
        .data = "mesh-data-v1",
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "assets/source/mesh.obj.deps",
        .data = "textures/wall.png\n",
    });

    const paths = PipelinePaths{
        .source_dir = "assets/source",
        .cache_dir = "assets/cache",
        .bundles_dir = "assets/bundles",
        .target = "client-debug",
    };

    const first = try importAssets(std.testing.io, tmp.dir, std.testing.allocator, paths);
    try std.testing.expectEqual(@as(usize, 1), first.scanned);
    try std.testing.expectEqual(@as(usize, 1), first.imported);
    try std.testing.expectEqual(@as(usize, 0), first.skipped);

    const second = try importAssets(std.testing.io, tmp.dir, std.testing.allocator, paths);
    try std.testing.expectEqual(@as(usize, 1), second.scanned);
    try std.testing.expectEqual(@as(usize, 0), second.imported);
    try std.testing.expectEqual(@as(usize, 1), second.skipped);

    const bundle = try bundleAssets(std.testing.io, tmp.dir, std.testing.allocator, paths);
    try std.testing.expectEqual(@as(usize, 1), bundle.asset_count);

    const bundle_bytes = try tmp.dir.readFileAlloc(
        std.testing.io,
        "assets/bundles/client-debug/bundle.json",
        std.testing.allocator,
        .limited(assets_manifest.max_metadata_bytes),
    );
    defer std.testing.allocator.free(bundle_bytes);
    try std.testing.expect(std.mem.indexOf(u8, bundle_bytes, "textures/wall.png") != null);
}
