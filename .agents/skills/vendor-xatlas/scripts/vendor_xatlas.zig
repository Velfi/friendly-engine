const std = @import("std");

const DefaultRepo = "https://github.com/jpcy/xatlas.git";
const DefaultRevision = "f700c7790aaa030e794b52ba7791a05c085faf0c";

const UpstreamFiles = [_]CopyFile{
    .{ .source = "LICENSE", .target = "LICENSE" },
    .{ .source = "source/xatlas/xatlas.cpp", .target = "source/xatlas/xatlas.cpp" },
    .{ .source = "source/xatlas/xatlas.h", .target = "source/xatlas/xatlas.h" },
};

const BridgeFiles = [_][]const u8{
    "fe_xatlas_bridge.cpp",
    "fe_xatlas_bridge.h",
};

const Required = [_][]const u8{
    "LICENSE",
    "README.md",
    "fe_xatlas_bridge.cpp",
    "fe_xatlas_bridge.h",
    "source/xatlas/xatlas.cpp",
    "source/xatlas/xatlas.h",
};

const CopyFile = struct {
    source: []const u8,
    target: []const u8,
};

const BridgeFile = struct {
    path: []const u8,
    bytes: []const u8,
};

const Options = struct {
    repo: []const u8 = DefaultRepo,
    revision: []const u8 = DefaultRevision,
    target: []const u8 = "third_party/xatlas",
    source: ?[]const u8 = null,
    bridge_source: []const u8 = "third_party/xatlas",
    replace: bool = false,
};

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args_iter = std.process.Args.Iterator.init(init.minimal.args);
    var args = std.array_list.Managed([]const u8).init(allocator);
    defer args.deinit();
    while (args_iter.next()) |arg| {
        try args.append(arg);
    }

    const options = try parseArgs(args.items);
    try run(allocator, init.io, options);
}

fn parseArgs(args: []const []const u8) !Options {
    var options = Options{};
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--replace")) {
            options.replace = true;
        } else if (std.mem.eql(u8, arg, "--repo")) {
            i += 1;
            if (i >= args.len) return usageError("missing value for --repo");
            options.repo = args[i];
        } else if (std.mem.eql(u8, arg, "--revision")) {
            i += 1;
            if (i >= args.len) return usageError("missing value for --revision");
            options.revision = args[i];
        } else if (std.mem.eql(u8, arg, "--target")) {
            i += 1;
            if (i >= args.len) return usageError("missing value for --target");
            options.target = args[i];
        } else if (std.mem.eql(u8, arg, "--source")) {
            i += 1;
            if (i >= args.len) return usageError("missing value for --source");
            options.source = args[i];
        } else if (std.mem.eql(u8, arg, "--bridge-source")) {
            i += 1;
            if (i >= args.len) return usageError("missing value for --bridge-source");
            options.bridge_source = args[i];
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printUsage();
            std.process.exit(0);
        } else {
            return usageError("unknown argument");
        }
    }
    return options;
}

fn usageError(message: []const u8) error{InvalidArguments} {
    std.debug.print("{s}\n\n", .{message});
    printUsage();
    return error.InvalidArguments;
}

fn printUsage() void {
    std.debug.print(
        \\usage: zig run .agents/skills/vendor-xatlas/scripts/vendor_xatlas.zig -- [options]
        \\
        \\Options:
        \\  --repo <url>             xatlas git repo (default: https://github.com/jpcy/xatlas.git)
        \\  --revision <sha>         Commit to check out and record
        \\  --target <path>          Destination directory (default: third_party/xatlas)
        \\  --source <path>          Existing xatlas checkout to copy instead of cloning
        \\  --bridge-source <path>   Directory containing fe_xatlas_bridge.* (default: third_party/xatlas)
        \\  --replace                Delete the target before copying
        \\
    , .{});
}

fn run(allocator: std.mem.Allocator, io: std.Io, options: Options) !void {
    const cwd = std.Io.Dir.cwd();
    const bridge_files = try readBridgeFiles(allocator, io, cwd, options.bridge_source);

    if (exists(cwd, io, options.target)) {
        if (!options.replace) {
            std.debug.print("{s} exists; pass --replace to refresh it\n", .{options.target});
            return error.TargetExists;
        }
        try cwd.deleteTree(io, options.target);
    }

    if (options.source) |source| {
        try vendorFromSource(allocator, io, options, source, bridge_files);
        return;
    }

    const clone_path = try std.fmt.allocPrint(allocator, "{s}.clone-tmp", .{options.target});
    if (exists(cwd, io, clone_path)) try cwd.deleteTree(io, clone_path);
    defer if (exists(cwd, io, clone_path)) cwd.deleteTree(io, clone_path) catch {};

    try runCheck(allocator, io, &.{ "git", "clone", options.repo, clone_path }, .inherit);
    try runCheck(allocator, io, &.{ "git", "checkout", options.revision }, .{ .path = clone_path });
    try vendorFromSource(allocator, io, options, clone_path, bridge_files);
}

fn readBridgeFiles(
    allocator: std.mem.Allocator,
    io: std.Io,
    cwd: std.Io.Dir,
    bridge_source: []const u8,
) ![]BridgeFile {
    var files = try allocator.alloc(BridgeFile, BridgeFiles.len);
    for (BridgeFiles, 0..) |name, i| {
        const path = try std.fs.path.join(allocator, &.{ bridge_source, name });
        files[i] = .{
            .path = name,
            .bytes = cwd.readFileAlloc(io, path, allocator, .limited(1024 * 1024)) catch |err| switch (err) {
                error.FileNotFound => {
                    std.debug.print("required xatlas bridge file missing: {s}\n", .{path});
                    return error.BridgeMissing;
                },
                else => return err,
            },
        };
    }
    return files;
}

fn vendorFromSource(
    allocator: std.mem.Allocator,
    io: std.Io,
    options: Options,
    source: []const u8,
    bridge_files: []const BridgeFile,
) !void {
    const revision = revisionFromSource(allocator, io, options, source) catch options.revision;
    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, options.target);
    for (UpstreamFiles) |file| {
        const source_path = try std.fs.path.join(allocator, &.{ source, file.source });
        const target_path = try std.fs.path.join(allocator, &.{ options.target, file.target });
        if (std.fs.path.dirname(target_path)) |dirname| {
            try cwd.createDirPath(io, dirname);
        }
        cwd.copyFile(source_path, cwd, target_path, io, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                std.debug.print("required xatlas source file missing: {s}\n", .{source_path});
                return error.SourceMissing;
            },
            else => return err,
        };
    }

    for (bridge_files) |file| {
        const target_path = try std.fs.path.join(allocator, &.{ options.target, file.path });
        try cwd.writeFile(io, .{ .sub_path = target_path, .data = file.bytes });
    }

    try writeReadme(allocator, io, cwd, options, revision);
    try verify(allocator, io, cwd, options.target);
    std.debug.print("vendored xatlas {s} from {s} into {s}\n", .{ revision, source, options.target });
}

fn revisionFromSource(
    allocator: std.mem.Allocator,
    io: std.Io,
    options: Options,
    source: []const u8,
) ![]const u8 {
    if (!exists(std.Io.Dir.cwd(), io, try std.fs.path.join(allocator, &.{ source, ".git" }))) {
        return options.revision;
    }
    return runCapture(allocator, io, &.{ "git", "rev-parse", "HEAD" }, .{ .path = source });
}

fn exists(dir: std.Io.Dir, io: std.Io, path: []const u8) bool {
    dir.access(io, path, .{}) catch return false;
    return true;
}

fn writeReadme(
    allocator: std.mem.Allocator,
    io: std.Io,
    cwd: std.Io.Dir,
    options: Options,
    revision: []const u8,
) !void {
    const path = try std.fs.path.join(allocator, &.{ options.target, "README.md" });
    const text = try std.fmt.allocPrint(allocator,
        \\# xatlas
        \\
        \\Vendored from `jpcy/xatlas`.
        \\
        \\- Upstream: {s}
        \\- Commit: `{s}`
        \\- License: MIT, see `LICENSE`.
        \\
        \\Only the library source required for engine integration is vendored:
        \\
        \\- `source/xatlas/xatlas.h`
        \\- `source/xatlas/xatlas.cpp`
        \\- `fe_xatlas_bridge.h`
        \\- `fe_xatlas_bridge.cpp`
        \\
        \\The bridge exposes a small C ABI so Zig code does not depend directly on C++
        \\namespace types.
        \\
        \\To refresh this tree, use the `vendor-xatlas` contributor skill in
        \\`.agents/skills/vendor-xatlas`.
        \\
    , .{ options.repo, revision });
    try cwd.writeFile(io, .{ .sub_path = path, .data = text });
}

fn verify(allocator: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir, target_root: []const u8) !void {
    for (Required) |name| {
        const path = try std.fs.path.join(allocator, &.{ target_root, name });
        cwd.access(io, path, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                std.debug.print("vendored xatlas verification failed; missing {s}\n", .{path});
                return error.VerifyFailed;
            },
            else => return err,
        };
    }
}

fn runCheck(
    allocator: std.mem.Allocator,
    io: std.Io,
    argv: []const []const u8,
    cwd: std.process.Child.Cwd,
) !void {
    const result = try std.process.run(allocator, io, .{
        .argv = argv,
        .cwd = cwd,
        .stdout_limit = .limited(128 * 1024),
        .stderr_limit = .limited(128 * 1024),
    });
    switch (result.term) {
        .exited => |code| if (code == 0) return,
        .signal, .stopped, .unknown => {},
    }
    std.debug.print("{s}", .{result.stdout});
    std.debug.print("{s}", .{result.stderr});
    return error.CommandFailed;
}

fn runCapture(
    allocator: std.mem.Allocator,
    io: std.Io,
    argv: []const []const u8,
    cwd: std.process.Child.Cwd,
) ![]const u8 {
    const result = try std.process.run(allocator, io, .{
        .argv = argv,
        .cwd = cwd,
        .stdout_limit = .limited(128 * 1024),
        .stderr_limit = .limited(128 * 1024),
    });
    switch (result.term) {
        .exited => |code| if (code == 0) return std.mem.trim(u8, result.stdout, " \t\r\n"),
        .signal, .stopped, .unknown => {},
    }
    std.debug.print("{s}", .{result.stderr});
    return error.CommandFailed;
}
