const std = @import("std");

const DefaultSource = "zig-pkg/sdl-0.5.1+3.4.10-SDL--kbMpgGMXke11Ujh5HUPKch7G_SUAS12LI0QFoqj";
const DefaultRepo = "https://github.com/castholm/SDL.git";
const DefaultBranch = "release-3.4.x";
const DefaultRevision = "018241066ffdae90d8b11f8bdc6242202f0f5451";
const DefaultHash = "sdl-0.5.1+3.4.10-SDL--kbMpgGMXke11Ujh5HUPKch7G_SUAS12LI0QFoqj";

const Required = [_][]const u8{
    "build.zig",
    "build.zig.zon",
    "LICENSE.txt",
    "REUSE.toml",
    "include/SDL3/SDL.h",
    "src/SDL.c",
    "src/video",
};

const Ignored = [_][]const u8{
    ".git",
    ".zig-cache",
    "zig-cache",
    "zig-out",
};

const Options = struct {
    repo: []const u8 = DefaultRepo,
    branch: []const u8 = DefaultBranch,
    revision: []const u8 = DefaultRevision,
    hash: []const u8 = DefaultHash,
    target: []const u8 = "third_party/sdl3",
    source: ?[]const u8 = DefaultSource,
    replace: bool = false,
    clone: bool = false,
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
        } else if (std.mem.eql(u8, arg, "--clone")) {
            options.clone = true;
            options.source = null;
        } else if (std.mem.eql(u8, arg, "--repo")) {
            i += 1;
            if (i >= args.len) return usageError("missing value for --repo");
            options.repo = args[i];
        } else if (std.mem.eql(u8, arg, "--branch")) {
            i += 1;
            if (i >= args.len) return usageError("missing value for --branch");
            options.branch = args[i];
        } else if (std.mem.eql(u8, arg, "--revision")) {
            i += 1;
            if (i >= args.len) return usageError("missing value for --revision");
            options.revision = args[i];
        } else if (std.mem.eql(u8, arg, "--hash")) {
            i += 1;
            if (i >= args.len) return usageError("missing value for --hash");
            options.hash = args[i];
        } else if (std.mem.eql(u8, arg, "--target")) {
            i += 1;
            if (i >= args.len) return usageError("missing value for --target");
            options.target = args[i];
        } else if (std.mem.eql(u8, arg, "--source")) {
            i += 1;
            if (i >= args.len) return usageError("missing value for --source");
            options.source = args[i];
            options.clone = false;
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
        \\usage: zig run .agents/skills/vendor-sdl3/scripts/vendor_sdl3.zig -- [options]
        \\
        \\Options:
        \\  --source <path>      Existing SDL Zig package to copy
        \\                       (default: zig-pkg/sdl-0.5.1+3.4.10-SDL--kbMpgGMXke11Ujh5HUPKch7G_SUAS12LI0QFoqj)
        \\  --clone              Clone from the configured repo instead of copying --source
        \\  --repo <url>         SDL Zig package repo (default: https://github.com/castholm/SDL.git)
        \\  --branch <name>      Repo branch (default: release-3.4.x)
        \\  --revision <sha>     Commit to check out and record
        \\  --hash <hash>        Zig package hash to record in provenance
        \\  --target <path>      Destination directory (default: third_party/sdl3)
        \\  --replace            Delete the target before copying
        \\
    , .{});
}

fn run(allocator: std.mem.Allocator, io: std.Io, options: Options) !void {
    const cwd = std.Io.Dir.cwd();
    if (exists(cwd, io, options.target)) {
        if (!options.replace) {
            std.debug.print("{s} exists; pass --replace to refresh it\n", .{options.target});
            return error.TargetExists;
        }
        try cwd.deleteTree(io, options.target);
    }

    if (options.source) |source| {
        try vendorFromSource(allocator, io, options, source);
        return;
    }

    const clone_path = try std.fmt.allocPrint(allocator, "{s}.clone-tmp", .{options.target});
    if (exists(cwd, io, clone_path)) try cwd.deleteTree(io, clone_path);
    defer if (exists(cwd, io, clone_path)) cwd.deleteTree(io, clone_path) catch {};

    try runCheck(allocator, io, &.{ "git", "clone", "--branch", options.branch, options.repo, clone_path }, .inherit);
    try runCheck(allocator, io, &.{ "git", "checkout", options.revision }, .{ .path = clone_path });
    try vendorFromSource(allocator, io, options, clone_path);
}

fn vendorFromSource(allocator: std.mem.Allocator, io: std.Io, options: Options, source: []const u8) !void {
    const cwd = std.Io.Dir.cwd();
    const revision = revisionFromSource(allocator, io, options, source) catch options.revision;

    try copyTree(allocator, io, cwd, source, options.target);
    try writeProvenance(allocator, io, cwd, options, source, revision);
    try verify(allocator, io, cwd, options.target);
    std.debug.print("vendored SDL3 {s} from {s} into {s}\n", .{ revision, source, options.target });
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

fn copyTree(
    allocator: std.mem.Allocator,
    io: std.Io,
    cwd: std.Io.Dir,
    source: []const u8,
    target: []const u8,
) !void {
    try cwd.createDirPath(io, target);
    var source_dir = try cwd.openDir(io, source, .{ .iterate = true });
    defer source_dir.close(io);

    var iter = source_dir.iterate();
    while (try iter.next(io)) |entry| {
        if (isIgnored(entry.name)) continue;

        const child_source = try std.fs.path.join(allocator, &.{ source, entry.name });
        const child_target = try std.fs.path.join(allocator, &.{ target, entry.name });
        switch (entry.kind) {
            .file => try cwd.copyFile(child_source, cwd, child_target, io, .{}),
            .directory => try copyTree(allocator, io, cwd, child_source, child_target),
            .sym_link => {},
            else => return error.UnsupportedPayloadKind,
        }
    }
}

fn isIgnored(name: []const u8) bool {
    for (Ignored) |ignored| {
        if (std.mem.eql(u8, name, ignored)) return true;
    }
    return false;
}

fn writeProvenance(
    allocator: std.mem.Allocator,
    io: std.Io,
    cwd: std.Io.Dir,
    options: Options,
    source: []const u8,
    revision: []const u8,
) !void {
    const path = try std.fs.path.join(allocator, &.{ options.target, "FRIENDLY_ENGINE_VENDORING.md" });
    const text = try std.fmt.allocPrint(allocator,
        \\# SDL3 Vendoring
        \\
        \\Source: {s}
        \\Branch: {s}
        \\Revision: {s}
        \\Zig package hash: {s}
        \\Vendored from: {s}
        \\
        \\friendly-engine vendors the SDL3 Zig package used by `build.zig`,
        \\because the build links the package's `SDL3` artifact directly.
        \\
        \\To refresh this tree, use the `vendor-sdl3` contributor skill in
        \\`.agents/skills/vendor-sdl3`.
        \\
    , .{ options.repo, options.branch, revision, options.hash, source });
    try cwd.writeFile(io, .{ .sub_path = path, .data = text });
}

fn verify(allocator: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir, target_root: []const u8) !void {
    for (Required) |name| {
        const path = try std.fs.path.join(allocator, &.{ target_root, name });
        cwd.access(io, path, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                std.debug.print("vendored SDL3 verification failed; missing {s}\n", .{path});
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
