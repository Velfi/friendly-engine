const std = @import("std");

const max_file_bytes: usize = 16 * 1024 * 1024;
pub const default_max_lines: usize = 700;

pub const Config = struct {
    root_dir: []const u8 = "src",
    extension: []const u8 = ".zig",
    max_lines: usize = default_max_lines,
};

pub const FileReport = struct {
    path: []u8,
    line_count: usize,
};

pub const ScanResult = struct {
    allocator: std.mem.Allocator,
    oversized: []FileReport,
    scanned: usize,
    largest_lines: usize,

    pub fn deinit(self: *ScanResult) void {
        for (self.oversized) |file| {
            self.allocator.free(file.path);
        }
        self.allocator.free(self.oversized);
        self.* = undefined;
    }
};

pub fn scan(
    io: std.Io,
    root_dir: std.Io.Dir,
    allocator: std.mem.Allocator,
    config: Config,
) !ScanResult {
    var oversized = std.ArrayList(FileReport).empty;
    errdefer {
        for (oversized.items) |file| {
            allocator.free(file.path);
        }
        oversized.deinit(allocator);
    }

    var scanned: usize = 0;
    var largest_lines: usize = 0;

    var dir = try root_dir.openDir(io, config.root_dir, .{ .iterate = true });
    defer dir.close(io);

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.path, config.extension)) continue;
        scanned += 1;

        const full_path = try std.fs.path.join(allocator, &.{ config.root_dir, entry.path });
        defer allocator.free(full_path);

        const bytes = try root_dir.readFileAlloc(io, full_path, allocator, .limited(max_file_bytes));
        defer allocator.free(bytes);

        const line_count = countLines(bytes);
        if (line_count > largest_lines) largest_lines = line_count;
        if (line_count <= config.max_lines) continue;

        try oversized.append(allocator, .{
            .path = try allocator.dupe(u8, full_path),
            .line_count = line_count,
        });
    }

    const owned = try oversized.toOwnedSlice(allocator);
    std.mem.sort(FileReport, owned, {}, lineCountDesc);

    return .{
        .allocator = allocator,
        .oversized = owned,
        .scanned = scanned,
        .largest_lines = largest_lines,
    };
}

fn lineCountDesc(_: void, a: FileReport, b: FileReport) bool {
    return a.line_count > b.line_count;
}

fn countLines(bytes: []const u8) usize {
    if (bytes.len == 0) return 0;
    var count: usize = 0;
    for (bytes) |byte| {
        if (byte == '\n') count += 1;
    }
    // Count a trailing line that is not newline-terminated.
    if (bytes[bytes.len - 1] != '\n') count += 1;
    return count;
}

pub fn runCli(allocator: std.mem.Allocator, io: std.Io, args: []const []const u8) !void {
    var config = Config{};
    if (try applyCliFlags(&config, args[1..])) {
        printUsage();
        return;
    }

    var result = try scan(io, std.Io.Dir.cwd(), allocator, config);
    defer result.deinit();

    if (result.oversized.len == 0) {
        std.debug.print(
            "modcheck ok: {d} {s} file(s) scanned in {s}/, all <= {d} lines (largest {d})\n",
            .{ result.scanned, config.extension, config.root_dir, config.max_lines, result.largest_lines },
        );
        return;
    }

    std.debug.print(
        "modcheck found {d} oversized module(s) (> {d} lines) in {s}/:\n",
        .{ result.oversized.len, config.max_lines, config.root_dir },
    );
    for (result.oversized) |file| {
        std.debug.print("  {d:>6} lines  {s}\n", .{ file.line_count, file.path });
    }
    std.debug.print(
        "Split these into smaller files (see AGENTS.md: \"Small files, happy developers\").\n",
        .{},
    );
    return error.OversizedModules;
}

fn applyCliFlags(config: *Config, flags: []const []const u8) !bool {
    var i: usize = 0;
    while (i < flags.len) {
        const flag = flags[i];
        i += 1;

        if (std.mem.eql(u8, flag, "help") or std.mem.eql(u8, flag, "--help") or std.mem.eql(u8, flag, "-h")) {
            return true;
        }

        if (i >= flags.len) return error.InvalidArguments;
        const value = flags[i];
        i += 1;

        if (std.mem.eql(u8, flag, "--dir")) {
            config.root_dir = value;
            continue;
        }
        if (std.mem.eql(u8, flag, "--ext")) {
            config.extension = value;
            continue;
        }
        if (std.mem.eql(u8, flag, "--max")) {
            config.max_lines = std.fmt.parseInt(usize, value, 10) catch return error.InvalidArguments;
            continue;
        }
        return error.InvalidArguments;
    }
    return false;
}

fn printUsage() void {
    std.debug.print(
        "usage: friendly_engine_modcheck [--dir path] [--ext .zig] [--max lines]\n" ++
            "  Reports source files larger than the line threshold (default {d}).\n" ++
            "  Exits non-zero when any oversized module is found.\n",
        .{default_max_lines},
    );
}

test "scan flags oversized files and sorts by line count" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, "src/sub");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "src/small.zig",
        .data = "a\nb\nc\n",
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "src/big.zig",
        .data = "x\n" ** 10,
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "src/sub/huge.zig",
        .data = "y\n" ** 20,
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "src/ignored.txt",
        .data = "z\n" ** 100,
    });

    var result = try scan(std.testing.io, tmp.dir, std.testing.allocator, .{ .max_lines = 5 });
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 3), result.scanned);
    try std.testing.expectEqual(@as(usize, 20), result.largest_lines);
    try std.testing.expectEqual(@as(usize, 2), result.oversized.len);
    try std.testing.expectEqual(@as(usize, 20), result.oversized[0].line_count);
    try std.testing.expect(std.mem.endsWith(u8, result.oversized[0].path, "huge.zig"));
    try std.testing.expectEqual(@as(usize, 10), result.oversized[1].line_count);
}

test "countLines handles missing trailing newline" {
    try std.testing.expectEqual(@as(usize, 0), countLines(""));
    try std.testing.expectEqual(@as(usize, 1), countLines("one line"));
    try std.testing.expectEqual(@as(usize, 2), countLines("a\nb"));
    try std.testing.expectEqual(@as(usize, 2), countLines("a\nb\n"));
}
