const std = @import("std");

pub const store_dir = ".friendly-engine/terrain-undo";

pub const Usage = struct {
    bytes: u64 = 0,
    transactions: u64 = 0,
};

pub const Transaction = struct {
    id: u64,
};

const max_snapshot_bytes = 256 * 1024 * 1024;

const TransactionEntry = struct {
    path: []u8,
    bytes: u64,
    mtime_ns: i96,
};

pub fn usage(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
) !Usage {
    var project_dir = try openProjectDir(io, project_path);
    defer project_dir.close(io);

    var undo_dir = project_dir.openDir(io, store_dir, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return .{},
        else => return err,
    };
    defer undo_dir.close(io);

    var result = Usage{};
    var seen_transactions = std.StringHashMap(void).init(allocator);
    defer {
        var it = seen_transactions.keyIterator();
        while (it.next()) |key| allocator.free(key.*);
        seen_transactions.deinit();
    }

    var walker = try undo_dir.walk(allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind == .directory and entry.depth() == 1) {
            const owned = try allocator.dupe(u8, entry.path);
            errdefer allocator.free(owned);
            try seen_transactions.put(owned, {});
        }
        if (entry.kind != .file) continue;
        const stat = try undo_dir.statFile(io, entry.path, .{});
        result.bytes += stat.size;
    }
    result.transactions = seen_transactions.count();
    return result;
}

pub fn enforceBudget(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    limit_mb: u64,
) !Usage {
    if (limit_mb == 0) return usage(allocator, io, project_path);
    const limit_bytes = limit_mb * 1024 * 1024;
    var project_dir = try openProjectDir(io, project_path);
    defer project_dir.close(io);

    var undo_dir = project_dir.openDir(io, store_dir, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return .{},
        else => return err,
    };
    defer undo_dir.close(io);

    var entries: std.ArrayList(TransactionEntry) = .empty;
    defer {
        for (entries.items) |entry| allocator.free(entry.path);
        entries.deinit(allocator);
    }

    var it = undo_dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .directory) continue;
        const stat = try undo_dir.statFile(io, entry.name, .{});
        const owned = try allocator.dupe(u8, entry.name);
        errdefer allocator.free(owned);
        try entries.append(allocator, .{
            .path = owned,
            .bytes = try directorySize(allocator, io, undo_dir, entry.name),
            .mtime_ns = stat.mtime.nanoseconds,
        });
    }

    var total: u64 = 0;
    for (entries.items) |entry| total += entry.bytes;
    std.mem.sort(TransactionEntry, entries.items, {}, transactionOlderThan);

    for (entries.items) |entry| {
        if (total <= limit_bytes) break;
        try undo_dir.deleteTree(io, entry.path);
        total -|= entry.bytes;
    }

    return usage(allocator, io, project_path);
}

pub fn beginTransaction(id: u64) Transaction {
    return .{ .id = id };
}

pub fn snapshotFileOnce(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    tx: Transaction,
    relative_path: []const u8,
) !bool {
    var project_dir = try openProjectDir(io, project_path);
    defer project_dir.close(io);

    const backup_path = try backupRelativePath(allocator, tx, relative_path);
    defer allocator.free(backup_path);

    if (project_dir.access(io, backup_path, .{})) |_| return false else |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    }

    const bytes = project_dir.readFileAlloc(io, relative_path, allocator, .limited(max_snapshot_bytes)) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    defer allocator.free(bytes);

    if (std.fs.path.dirname(backup_path)) |parent| try project_dir.createDirPath(io, parent);
    try project_dir.writeFile(io, .{ .sub_path = backup_path, .data = bytes });
    return true;
}

pub fn snapshotTerrainRegionsForReplace(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    tx: Transaction,
) !u32 {
    var project_dir = try openProjectDir(io, project_path);
    defer project_dir.close(io);

    const marker_path = try replaceTerrainRegionsMarkerPath(allocator, tx);
    defer allocator.free(marker_path);
    if (std.fs.path.dirname(marker_path)) |parent| try project_dir.createDirPath(io, parent);
    try project_dir.writeFile(io, .{ .sub_path = marker_path, .data = "1\n" });

    var regions_dir = project_dir.openDir(io, "layers/terrain/regions", .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return 0,
        else => return err,
    };
    defer regions_dir.close(io);

    var snapshots: u32 = 0;
    var walker = try regions_dir.walk(allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        const relative_path = try std.fmt.allocPrint(allocator, "layers/terrain/regions/{s}", .{entry.path});
        defer allocator.free(relative_path);
        if (try snapshotFileOnce(allocator, io, project_path, tx, relative_path)) snapshots += 1;
    }
    return snapshots;
}

pub fn pruneAfterTransaction(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    limit_mb: u64,
) !Usage {
    return enforceBudget(allocator, io, project_path, limit_mb);
}

pub fn restoreLatest(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
) !?Transaction {
    var project_dir = try openProjectDir(io, project_path);
    defer project_dir.close(io);

    var undo_dir = project_dir.openDir(io, store_dir, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer undo_dir.close(io);

    const latest = try latestTransaction(allocator, io, undo_dir) orelse return null;
    defer allocator.free(latest.path);

    const marker_path = try std.fmt.allocPrint(allocator, "{s}/replace_terrain_regions", .{latest.path});
    defer allocator.free(marker_path);
    if (undo_dir.access(io, marker_path, .{})) |_| {
        try project_dir.deleteTree(io, "layers/terrain/regions");
    } else |_| {}

    const before_path = try std.fmt.allocPrint(allocator, "{s}/before", .{latest.path});
    defer allocator.free(before_path);
    var before_dir = try undo_dir.openDir(io, before_path, .{ .iterate = true });
    defer before_dir.close(io);

    var walker = try before_dir.walk(allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        const bytes = try before_dir.readFileAlloc(io, entry.path, allocator, .limited(max_snapshot_bytes));
        defer allocator.free(bytes);
        if (std.fs.path.dirname(entry.path)) |parent| try project_dir.createDirPath(io, parent);
        try project_dir.writeFile(io, .{ .sub_path = entry.path, .data = bytes });
    }

    try undo_dir.deleteTree(io, latest.path);
    return .{ .id = parseTransactionId(latest.path) orelse 0 };
}

pub fn formatBytes(buf: []u8, bytes: u64) []const u8 {
    const mib = @as(f64, @floatFromInt(bytes)) / (1024.0 * 1024.0);
    if (bytes < 1024 * 1024) {
        const kib = @as(f64, @floatFromInt(bytes)) / 1024.0;
        return std.fmt.bufPrint(buf, "{d:.1} KB", .{kib}) catch "usage";
    }
    if (mib < 1024.0) return std.fmt.bufPrint(buf, "{d:.1} MB", .{mib}) catch "usage";
    return std.fmt.bufPrint(buf, "{d:.2} GB", .{mib / 1024.0}) catch "usage";
}

fn directorySize(
    allocator: std.mem.Allocator,
    io: std.Io,
    parent: std.Io.Dir,
    sub_path: []const u8,
) !u64 {
    var dir = try parent.openDir(io, sub_path, .{ .iterate = true });
    defer dir.close(io);
    var walker = try dir.walk(allocator);
    defer walker.deinit();

    var total: u64 = 0;
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        total += (try dir.statFile(io, entry.path, .{})).size;
    }
    return total;
}

fn latestTransaction(
    allocator: std.mem.Allocator,
    io: std.Io,
    undo_dir: std.Io.Dir,
) !?TransactionEntry {
    var best: ?TransactionEntry = null;
    errdefer if (best) |entry| allocator.free(entry.path);

    var it = undo_dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .directory) continue;
        const stat = try undo_dir.statFile(io, entry.name, .{});
        if (best == null or stat.mtime.nanoseconds > best.?.mtime_ns) {
            if (best) |old| allocator.free(old.path);
            const owned = try allocator.dupe(u8, entry.name);
            best = .{
                .path = owned,
                .bytes = 0,
                .mtime_ns = stat.mtime.nanoseconds,
            };
        }
    }
    return best;
}

fn openProjectDir(io: std.Io, project_path: []const u8) !std.Io.Dir {
    if (std.fs.path.isAbsolute(project_path)) {
        return try std.Io.Dir.openDirAbsolute(io, project_path, .{});
    }
    return try std.Io.Dir.cwd().openDir(io, project_path, .{});
}

fn backupRelativePath(allocator: std.mem.Allocator, tx: Transaction, relative_path: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}/{d}/before/{s}", .{ store_dir, tx.id, relative_path });
}

fn replaceTerrainRegionsMarkerPath(allocator: std.mem.Allocator, tx: Transaction) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}/{d}/replace_terrain_regions", .{ store_dir, tx.id });
}

fn transactionOlderThan(_: void, a: TransactionEntry, b: TransactionEntry) bool {
    return a.mtime_ns < b.mtime_ns;
}

fn parseTransactionId(text: []const u8) ?u64 {
    return std.fmt.parseInt(u64, text, 10) catch null;
}

test "format bytes uses human units" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("1.0 KB", formatBytes(&buf, 1024));
    try std.testing.expectEqualStrings("1.0 MB", formatBytes(&buf, 1024 * 1024));
    try std.testing.expectEqualStrings("1.00 GB", formatBytes(&buf, 1024 * 1024 * 1024));
}
