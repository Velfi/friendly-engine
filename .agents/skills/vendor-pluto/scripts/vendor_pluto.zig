const std = @import("std");

const PayloadFiles = [_][]const u8{
    "plutosvg/LICENSE",
    "plutosvg/plutosvg.c",
    "plutosvg/plutosvg.h",
    "plutovg/FTL.TXT",
    "plutovg/LICENSE",
    "plutovg/plutovg-blend.c",
    "plutovg/plutovg-canvas.c",
    "plutovg/plutovg-font.c",
    "plutovg/plutovg-ft-math.c",
    "plutovg/plutovg-ft-math.h",
    "plutovg/plutovg-ft-raster.c",
    "plutovg/plutovg-ft-raster.h",
    "plutovg/plutovg-ft-stroker.c",
    "plutovg/plutovg-ft-stroker.h",
    "plutovg/plutovg-ft-types.h",
    "plutovg/plutovg-matrix.c",
    "plutovg/plutovg-paint.c",
    "plutovg/plutovg-path.c",
    "plutovg/plutovg-private.h",
    "plutovg/plutovg-rasterize.c",
    "plutovg/plutovg-stb-image-write.h",
    "plutovg/plutovg-stb-image.h",
    "plutovg/plutovg-stb-truetype.h",
    "plutovg/plutovg-surface.c",
    "plutovg/plutovg-utils.h",
    "plutovg/plutovg.h",
};

const BridgeFiles = [_][]const u8{ "fe_plutosvg_bridge.c", "fe_plutosvg_bridge.h" };
const Required = PayloadFiles ++ BridgeFiles;

const Options = struct {
    source: []const u8 = "third_party/pluto",
    target: []const u8 = "third_party/pluto",
    bridge_source: []const u8 = "third_party/pluto",
    replace: bool = false,
};

const BridgeFile = struct { path: []const u8, bytes: []const u8 };

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
        \\usage: zig run .agents/skills/vendor-pluto/scripts/vendor_pluto.zig -- [options]
        \\
        \\Options:
        \\  --source <path>          Directory containing plutosvg/ and plutovg/
        \\  --target <path>          Destination directory (default: third_party/pluto)
        \\  --bridge-source <path>   Directory containing fe_plutosvg_bridge.*
        \\  --replace                Delete the target before copying
        \\
    , .{});
}

fn run(allocator: std.mem.Allocator, io: std.Io, options: Options) !void {
    const cwd = std.Io.Dir.cwd();
    const bridge_files = try readBridgeFiles(allocator, io, cwd, options.bridge_source);
    const payload = try readFiles(allocator, io, cwd, options.source, &PayloadFiles);
    if (exists(cwd, io, options.target)) {
        if (!options.replace) return error.TargetExists;
        try cwd.deleteTree(io, options.target);
    }
    try cwd.createDirPath(io, options.target);
    try writeFiles(allocator, io, cwd, options.target, payload);
    try writeFiles(allocator, io, cwd, options.target, bridge_files);
    try writeProvenance(allocator, io, cwd, options.target, options.source);
    try verify(allocator, io, cwd, options.target);
    std.debug.print("vendored Pluto from {s} into {s}\n", .{ options.source, options.target });
}

fn readBridgeFiles(allocator: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir, root: []const u8) ![]BridgeFile {
    return readFiles(allocator, io, cwd, root, &BridgeFiles);
}

fn readFiles(allocator: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir, root: []const u8, names: []const []const u8) ![]BridgeFile {
    const files = try allocator.alloc(BridgeFile, names.len);
    for (names, 0..) |name, i| {
        const path = try std.fs.path.join(allocator, &.{ root, name });
        files[i] = .{ .path = name, .bytes = try cwd.readFileAlloc(io, path, allocator, .limited(8 * 1024 * 1024)) };
    }
    return files;
}

fn writeFiles(allocator: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir, root: []const u8, files: []const BridgeFile) !void {
    for (files) |file| {
        const path = try std.fs.path.join(allocator, &.{ root, file.path });
        if (std.fs.path.dirname(path)) |dir| try cwd.createDirPath(io, dir);
        try cwd.writeFile(io, .{ .sub_path = path, .data = file.bytes });
    }
}

fn writeProvenance(allocator: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir, target: []const u8, source: []const u8) !void {
    const path = try std.fs.path.join(allocator, &.{ target, "FRIENDLY_ENGINE_VENDORING.md" });
    const text = try std.fmt.allocPrint(allocator,
        \\# Pluto Vendoring
        \\
        \\Source: {s}
        \\Upstreams: https://github.com/sammycage/plutosvg and https://github.com/sammycage/plutovg
        \\
        \\friendly-engine vendors Pluto SVG/VG source plus a local C bridge for SVG rasterization.
        \\
        \\To refresh this tree, use the `vendor-pluto` contributor skill in
        \\`.agents/skills/vendor-pluto`.
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
