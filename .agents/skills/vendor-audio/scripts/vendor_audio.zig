const std = @import("std");

const PayloadFiles = [_][]const u8{ "miniaudio.h", "stb_vorbis.c" };
const BridgeFiles = [_][]const u8{ "fe_audio_decode.c", "fe_audio_decode.h" };
const Required = PayloadFiles ++ BridgeFiles;

const Options = struct {
    source: []const u8 = "third_party/audio",
    target: []const u8 = "third_party/audio",
    bridge_source: []const u8 = "third_party/audio",
    replace: bool = false,
};

const FileBlob = struct { path: []const u8, bytes: []const u8 };

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const allocator = arena.allocator();
    var args_iter = std.process.Args.Iterator.init(init.minimal.args);
    var args = std.array_list.Managed([]const u8).init(allocator);
    while (args_iter.next()) |arg| try args.append(arg);
    try run(allocator, init.io, try parseArgs(args.items));
}

fn parseArgs(args: []const []const u8) !Options {
    var options = Options{};
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--replace")) options.replace = true else if (std.mem.eql(u8, arg, "--source")) {
            i += 1;
            if (i >= args.len) return usageError("missing value for --source");
            options.source = args[i];
        } else if (std.mem.eql(u8, arg, "--target")) {
            i += 1;
            if (i >= args.len) return usageError("missing value for --target");
            options.target = args[i];
        } else if (std.mem.eql(u8, arg, "--bridge-source")) {
            i += 1;
            if (i >= args.len) return usageError("missing value for --bridge-source");
            options.bridge_source = args[i];
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
        \\usage: zig run .agents/skills/vendor-audio/scripts/vendor_audio.zig -- [options]
        \\
        \\Options:
        \\  --source <path>          Directory containing miniaudio.h and stb_vorbis.c
        \\  --target <path>          Destination directory (default: third_party/audio)
        \\  --bridge-source <path>   Directory containing fe_audio_decode.*
        \\  --replace                Delete the target before copying
        \\
    , .{});
}

fn run(allocator: std.mem.Allocator, io: std.Io, options: Options) !void {
    const cwd = std.Io.Dir.cwd();
    const payload = try readFiles(allocator, io, cwd, options.source, &PayloadFiles);
    const bridge = try readFiles(allocator, io, cwd, options.bridge_source, &BridgeFiles);
    if (exists(cwd, io, options.target)) {
        if (!options.replace) return error.TargetExists;
        try cwd.deleteTree(io, options.target);
    }
    try cwd.createDirPath(io, options.target);
    try writeFiles(allocator, io, cwd, options.target, payload);
    try writeFiles(allocator, io, cwd, options.target, bridge);
    try writeProvenance(allocator, io, cwd, options.target, options.source);
    try verify(allocator, io, cwd, options.target);
    std.debug.print("vendored audio libraries from {s} into {s}\n", .{ options.source, options.target });
}

fn readFiles(allocator: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir, root: []const u8, names: []const []const u8) ![]FileBlob {
    const files = try allocator.alloc(FileBlob, names.len);
    for (names, 0..) |name, i| {
        const path = try std.fs.path.join(allocator, &.{ root, name });
        files[i] = .{ .path = name, .bytes = try cwd.readFileAlloc(io, path, allocator, .limited(8 * 1024 * 1024)) };
    }
    return files;
}

fn writeFiles(allocator: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir, root: []const u8, files: []const FileBlob) !void {
    for (files) |file| {
        const path = try std.fs.path.join(allocator, &.{ root, file.path });
        try cwd.writeFile(io, .{ .sub_path = path, .data = file.bytes });
    }
}

fn writeProvenance(allocator: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir, target: []const u8, source: []const u8) !void {
    const path = try std.fs.path.join(allocator, &.{ target, "FRIENDLY_ENGINE_VENDORING.md" });
    const text = try std.fmt.allocPrint(allocator,
        \\# Audio Vendoring
        \\
        \\Source: {s}
        \\Upstreams: https://github.com/mackron/miniaudio and https://github.com/nothings/stb
        \\
        \\friendly-engine vendors miniaudio, stb_vorbis, and a local C decode bridge.
        \\
        \\To refresh this tree, use the `vendor-audio` contributor skill in
        \\`.agents/skills/vendor-audio`.
        \\
    , .{source});
    try cwd.writeFile(io, .{ .sub_path = path, .data = text });
}

fn verify(allocator: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir, target: []const u8) !void {
    for (Required) |name| {
        const path = try std.fs.path.join(allocator, &.{ target, name });
        cwd.access(io, path, .{}) catch return error.VerifyFailed;
    }
}

fn exists(dir: std.Io.Dir, io: std.Io, path: []const u8) bool {
    dir.access(io, path, .{}) catch return false;
    return true;
}
