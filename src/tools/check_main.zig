const std = @import("std");
const module_size = @import("module_size.zig");

pub fn main(init: std.process.Init) !void {
    var args_iter = std.process.Args.Iterator.init(init.minimal.args);
    var args = std.array_list.Managed([]const u8).init(init.gpa);
    defer args.deinit();
    while (args_iter.next()) |arg| {
        try args.append(arg);
    }

    runCli(init.gpa, init.io, args.items) catch |err| switch (err) {
        error.OversizedModules => std.process.exit(1),
        error.MissingSchemaFiles => std.process.exit(1),
        else => return err,
    };
}

pub fn runCli(allocator: std.mem.Allocator, io: std.Io, args: []const []const u8) !void {
    if (try applyCliFlags(args[1..])) {
        printUsage();
        return;
    }

    var result = try module_size.scan(io, std.Io.Dir.cwd(), allocator, .{});
    defer result.deinit();
    if (result.oversized.len > 0) {
        for (result.oversized) |file| {
            std.debug.print("check: {d:>6} lines  {s}\n", .{ file.line_count, file.path });
        }
        std.debug.print(
            "check failed: {d} oversized source module(s) exceed the {d}-line budget\n",
            .{ result.oversized.len, module_size.default_max_lines },
        );
        return error.OversizedModules;
    }

    try verifySchemaFiles(io);
    std.debug.print("check ok: source modules fit the {d}-line budget and schema files exist\n", .{module_size.default_max_lines});
}

fn verifySchemaFiles(io: std.Io) !void {
    const paths = [_][]const u8{
        "docs/schema/scene.schema.json",
        "docs/schema/world.schema.json",
        "docs/CODEMAP.md",
    };
    for (paths) |path| {
        std.Io.Dir.cwd().access(io, path, .{}) catch {
            std.debug.print("check failed: missing {s}\n", .{path});
            return error.MissingSchemaFiles;
        };
    }
}

fn applyCliFlags(flags: []const []const u8) !bool {
    for (flags) |flag| {
        if (std.mem.eql(u8, flag, "help") or std.mem.eql(u8, flag, "--help") or std.mem.eql(u8, flag, "-h")) {
            return true;
        }
    }
    return false;
}

fn printUsage() void {
    std.debug.print(
        "usage: friendly_engine_check\n" ++
            "  Verifies source module file sizes (<={d} lines) and docs/schema presence.\n",
        .{module_size.default_max_lines},
    );
}
