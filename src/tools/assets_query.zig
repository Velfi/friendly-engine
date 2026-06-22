const std = @import("std");
const assets_manifest = @import("assets_manifest.zig");

pub const QueryPaths = struct {
    cache_dir: []const u8 = "assets/cache",
    target: []const u8 = "client-debug",
};

const AssetView = struct {
    asset_id: u64,
    source_path: []const u8,
    artifact_path: []const u8,
    kind: []const u8,
    content_hash: u64,
    runtime_size_bytes: u64,
    dependencies: []const []const u8 = &.{},
    used_by_count: usize,
};

pub fn describeAssets(
    io: std.Io,
    root_dir: std.Io.Dir,
    allocator: std.mem.Allocator,
    paths: QueryPaths,
) ![]u8 {
    const manifest_path = try std.fs.path.join(allocator, &.{ paths.cache_dir, paths.target, "asset_manifest.json" });
    defer allocator.free(manifest_path);
    const bytes = try root_dir.readFileAlloc(io, manifest_path, allocator, .limited(assets_manifest.max_metadata_bytes));
    defer allocator.free(bytes);

    const ParsedManifest = struct {
        schema_version: u16 = 1,
        target: []const u8,
        stats: struct { scanned: usize = 0, imported: usize = 0, skipped: usize = 0 } = .{},
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

    var parsed = try std.json.parseFromSlice(ParsedManifest, allocator, bytes, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    var views = try allocator.alloc(AssetView, parsed.value.assets.len);
    defer allocator.free(views);
    for (parsed.value.assets, 0..) |asset, i| {
        views[i] = .{
            .asset_id = asset.asset_id,
            .source_path = asset.source_path,
            .artifact_path = asset.artifact_path,
            .kind = asset.kind,
            .content_hash = asset.content_hash,
            .runtime_size_bytes = asset.runtime_size_bytes,
            .dependencies = asset.dependencies,
            .used_by_count = countUsers(parsed.value.assets, asset.source_path),
        };
    }

    const doc = .{
        .schema_version = @as(u16, 1),
        .target = parsed.value.target,
        .stats = parsed.value.stats,
        .asset_count = views.len,
        .assets = views,
    };
    return std.fmt.allocPrint(allocator, "{f}\n", .{std.json.fmt(doc, .{ .whitespace = .indent_2 })});
}

fn countUsers(assets: anytype, source_path: []const u8) usize {
    var count: usize = 0;
    for (assets) |asset| {
        for (asset.dependencies) |dependency| {
            if (std.mem.eql(u8, dependency, source_path) or std.mem.endsWith(u8, source_path, dependency)) {
                count += 1;
                break;
            }
        }
    }
    return count;
}

pub fn runCli(allocator: std.mem.Allocator, io: std.Io, args: []const []const u8) !void {
    var paths = QueryPaths{};
    var i: usize = 0;
    while (i < args.len) {
        const flag = args[i];
        i += 1;
        if (i >= args.len) return error.InvalidArguments;
        const value = args[i];
        i += 1;
        if (std.mem.eql(u8, flag, "--cache")) {
            paths.cache_dir = value;
        } else if (std.mem.eql(u8, flag, "--target")) {
            paths.target = value;
        } else {
            return error.InvalidArguments;
        }
    }
    const json = try describeAssets(io, std.Io.Dir.cwd(), allocator, paths);
    defer allocator.free(json);
    std.debug.print("{s}", .{json});
}
