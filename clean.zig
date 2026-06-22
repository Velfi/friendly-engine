const std = @import("std");

const CleanTarget = struct {
    path: []const u8,
    include_in_default: bool = true,
};

const targets = [_]CleanTarget{
    .{ .path = ".zig-cache" },
    .{ .path = "zig-cache" },
    .{ .path = "zig-out" },
    .{ .path = "assets/cache", .include_in_default = false },
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    var dry_run = false;
    var include_all = false;

    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--dry-run") or std.mem.eql(u8, arg, "-n")) {
            dry_run = true;
        } else if (std.mem.eql(u8, arg, "--all") or std.mem.eql(u8, arg, "-a")) {
            include_all = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printUsage();
            return;
        } else {
            std.debug.print("unknown argument: {s}\n\n", .{arg});
            printUsage();
            std.process.exit(1);
        }
    }

    var cwd = std.Io.Dir.cwd();
    var removed_count: usize = 0;

    for (targets) |target| {
        if (!include_all and !target.include_in_default) continue;

        cwd.access(init.io, target.path, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                std.debug.print("skip missing {s}\n", .{target.path});
                continue;
            },
            else => return err,
        };

        if (dry_run) {
            std.debug.print("would remove {s}\n", .{target.path});
        } else {
            try cwd.deleteTree(init.io, target.path);
            std.debug.print("removed {s}\n", .{target.path});
        }

        removed_count += 1;
    }

    if (dry_run) {
        std.debug.print("dry run complete: {d} target(s) matched\n", .{removed_count});
    } else {
        std.debug.print("clean complete: {d} target(s) removed\n", .{removed_count});
    }
}

fn printUsage() void {
    std.debug.print(
        \\Usage: zig run clean.zig -- [options]
        \\
        \\Options:
        \\  -n, --dry-run   Print what would be removed without deleting anything
        \\  -a, --all       Also remove larger project-generated caches
        \\  -h, --help      Show this help message
        \\
        \\Default targets:
        \\  .zig-cache
        \\  zig-cache
        \\  zig-out
        \\
        \\Additional --all targets:
        \\  assets/cache
        \\
    , .{});
}
