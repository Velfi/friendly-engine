const std = @import("std");

const DefaultSource = "zig-pkg/zphysics-0.2.0-dev-nZDEANvfQgD04nOPqL9KMokfgjzs_wPtHpoLscZScaOa";
const DefaultHash = "zphysics-0.2.0-dev-nZDEANvfQgD04nOPqL9KMokfgjzs_wPtHpoLscZScaOa";
const DefaultRepo = "https://github.com/zig-gamedev/zig-gamedev/tree/main/libs/zphysics";

const Required = [_][]const u8{
    "build.zig",
    "build.zig.zon",
    "src/zphysics.zig",
    "libs/Jolt/Jolt.h",
    "libs/JoltC/JoltPhysicsC.h",
    "LICENSE",
    "README.md",
};

const Ignored = [_][]const u8{ ".git", ".zig-cache", "zig-cache", "zig-out" };

const Options = struct {
    source: []const u8 = DefaultSource,
    target: []const u8 = "third_party/zphysics",
    package_hash: []const u8 = DefaultHash,
    source_note: []const u8 = DefaultRepo,
    replace: bool = false,
};

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args_iter = std.process.Args.Iterator.init(init.minimal.args);
    var args = std.array_list.Managed([]const u8).init(allocator);
    while (args_iter.next()) |arg| try args.append(arg);

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
        } else if (std.mem.eql(u8, arg, "--source")) {
            i += 1;
            if (i >= args.len) return usageError("missing value for --source");
            options.source = args[i];
        } else if (std.mem.eql(u8, arg, "--target")) {
            i += 1;
            if (i >= args.len) return usageError("missing value for --target");
            options.target = args[i];
        } else if (std.mem.eql(u8, arg, "--package-hash")) {
            i += 1;
            if (i >= args.len) return usageError("missing value for --package-hash");
            options.package_hash = args[i];
        } else if (std.mem.eql(u8, arg, "--source-note")) {
            i += 1;
            if (i >= args.len) return usageError("missing value for --source-note");
            options.source_note = args[i];
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printUsage();
            std.process.exit(0);
        } else return usageError("unknown argument");
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
        \\usage: zig run .agents/skills/vendor-zphysics/scripts/vendor_zphysics.zig -- [options]
        \\
        \\Options:
        \\  --source <path>        Existing zphysics package to copy
        \\  --target <path>        Destination directory (default: third_party/zphysics)
        \\  --package-hash <hash>  Zig package hash to record
        \\  --source-note <text>   Source/provenance note to record
        \\  --replace              Delete the target before copying
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
    try copyTree(allocator, io, cwd, options.source, options.target);
    try writeProvenance(allocator, io, cwd, options);
    try verify(allocator, io, cwd, options.target);
    std.debug.print("vendored zphysics from {s} into {s}\n", .{ options.source, options.target });
}

fn copyTree(allocator: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir, source: []const u8, target: []const u8) !void {
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

fn writeProvenance(allocator: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir, options: Options) !void {
    const path = try std.fs.path.join(allocator, &.{ options.target, "FRIENDLY_ENGINE_VENDORING.md" });
    const text = try std.fmt.allocPrint(allocator,
        \\# zphysics Vendoring
        \\
        \\Source: {s}
        \\Zig package hash: {s}
        \\Vendored from: {s}
        \\
        \\friendly-engine vendors zphysics because `build.zig.zon` points the
        \\`zphysics` dependency at `third_party/zphysics`.
        \\
        \\To refresh this tree, use the `vendor-zphysics` contributor skill in
        \\`.agents/skills/vendor-zphysics`.
        \\
    , .{ options.source_note, options.package_hash, options.source });
    try cwd.writeFile(io, .{ .sub_path = path, .data = text });
}

fn verify(allocator: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir, target: []const u8) !void {
    for (Required) |name| {
        const path = try std.fs.path.join(allocator, &.{ target, name });
        cwd.access(io, path, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                std.debug.print("vendored zphysics verification failed; missing {s}\n", .{path});
                return error.VerifyFailed;
            },
            else => return err,
        };
    }
}

fn exists(dir: std.Io.Dir, io: std.Io, path: []const u8) bool {
    dir.access(io, path, .{}) catch return false;
    return true;
}

fn isIgnored(name: []const u8) bool {
    for (Ignored) |ignored| if (std.mem.eql(u8, name, ignored)) return true;
    return false;
}
