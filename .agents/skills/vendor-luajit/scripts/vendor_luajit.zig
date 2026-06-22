const std = @import("std");

const Payload = [_][]const u8{
    "COPYRIGHT",
    "Makefile",
    "README",
    "doc",
    "dynasm",
    "etc",
    "src",
};

const Required = [_][]const u8{
    "COPYRIGHT",
    "README",
    "src/lua.h",
    "src/luajit.c",
    "src/ljamalg.c",
    "dynasm/dynasm.lua",
    "doc/install.html",
};

const Options = struct {
    repo: []const u8 = "https://luajit.org/git/luajit.git",
    branch: []const u8 = "v2.1",
    target: []const u8 = "third_party/luajit",
    source: ?[]const u8 = null,
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
        } else if (std.mem.eql(u8, arg, "--branch")) {
            i += 1;
            if (i >= args.len) return usageError("missing value for --branch");
            options.branch = args[i];
        } else if (std.mem.eql(u8, arg, "--target")) {
            i += 1;
            if (i >= args.len) return usageError("missing value for --target");
            options.target = args[i];
        } else if (std.mem.eql(u8, arg, "--source")) {
            i += 1;
            if (i >= args.len) return usageError("missing value for --source");
            options.source = args[i];
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
        \\usage: zig run .agents/skills/vendor-luajit/scripts/vendor_luajit.zig -- [options]
        \\
        \\Options:
        \\  --repo <url>       LuaJIT git repo (default: https://luajit.org/git/luajit.git)
        \\  --branch <name>    LuaJIT branch (default: v2.1)
        \\  --target <path>    Destination directory (default: third_party/luajit)
        \\  --source <path>    Existing LuaJIT checkout to copy instead of cloning
        \\  --replace          Delete the target before copying
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
    defer allocator.free(clone_path);
    if (exists(cwd, io, clone_path)) try cwd.deleteTree(io, clone_path);
    defer if (exists(cwd, io, clone_path)) cwd.deleteTree(io, clone_path) catch {};

    try runCheck(allocator, io, &.{ "git", "clone", "--branch", options.branch, options.repo, clone_path }, .inherit);
    try vendorFromSource(allocator, io, options, clone_path);
}

fn vendorFromSource(allocator: std.mem.Allocator, io: std.Io, options: Options, source: []const u8) !void {
    const commit = try runCapture(allocator, io, &.{ "git", "rev-parse", "HEAD" }, .{ .path = source });
    const branch_output = try runCapture(allocator, io, &.{ "git", "branch", "--show-current" }, .{ .path = source });
    const branch = if (branch_output.len == 0) options.branch else branch_output;

    const cwd = std.Io.Dir.cwd();
    try copyPayload(allocator, io, cwd, source, options.target);
    try writeProvenance(allocator, io, cwd, options.target, options.repo, branch, commit);
    try verify(allocator, io, cwd, options.target);
    std.debug.print("vendored LuaJIT {s} from {s} into {s}\n", .{ commit, source, options.target });
}

fn exists(dir: std.Io.Dir, io: std.Io, path: []const u8) bool {
    dir.access(io, path, .{}) catch return false;
    return true;
}

fn copyPayload(
    allocator: std.mem.Allocator,
    io: std.Io,
    cwd: std.Io.Dir,
    source_root: []const u8,
    target_root: []const u8,
) !void {
    try cwd.createDirPath(io, target_root);
    for (Payload) |name| {
        const source = try std.fs.path.join(allocator, &.{ source_root, name });
        const target = try std.fs.path.join(allocator, &.{ target_root, name });
        const stat = cwd.statFile(io, source, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                std.debug.print("required LuaJIT payload missing: {s}\n", .{source});
                return error.PayloadMissing;
            },
            else => return err,
        };
        switch (stat.kind) {
            .file => try cwd.copyFile(source, cwd, target, io, .{}),
            .directory => try copyTree(allocator, io, cwd, source, target),
            else => return error.UnsupportedPayloadKind,
        }
    }
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
        if (std.mem.eql(u8, entry.name, ".git")) continue;
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

fn writeProvenance(
    allocator: std.mem.Allocator,
    io: std.Io,
    cwd: std.Io.Dir,
    target_root: []const u8,
    repo: []const u8,
    branch: []const u8,
    commit: []const u8,
) !void {
    const path = try std.fs.path.join(allocator, &.{ target_root, "FRIENDLY_ENGINE_VENDORING.md" });
    const text = try std.fmt.allocPrint(allocator,
        \\# LuaJIT Vendoring
        \\
        \\Source: {s}
        \\Branch: {s}
        \\Revision: {s}
        \\
        \\LuaJIT is source-only and uses rolling releases. The official download page
        \\directs consumers to clone the public git repository and avoid third-party
        \\tarballs or pseudo-releases.
        \\
        \\To refresh this tree, use the `vendor-luajit` contributor skill in
        \\`.agents/skills/vendor-luajit`.
        \\
    , .{ repo, branch, commit });
    try cwd.writeFile(io, .{ .sub_path = path, .data = text });
}

fn verify(allocator: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir, target_root: []const u8) !void {
    for (Required) |name| {
        const path = try std.fs.path.join(allocator, &.{ target_root, name });
        cwd.access(io, path, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                std.debug.print("vendored LuaJIT verification failed; missing {s}\n", .{path});
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
