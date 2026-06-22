const std = @import("std");

const source_dir = "assets/source/icons/iconoir";
const runtime_dir = "src/runtime/editor/icons/iconoir";
const manifest_path = source_dir ++ "/manifest.json";
const raw_base_url = "https://raw.githubusercontent.com/iconoir-icons/iconoir/main/icons";

const Options = struct {
    icons: []const []const u8,
    aliases: []const Alias,
};

const Alias = struct {
    name: []const u8,
    icon: []const u8,
};

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args_iter = std.process.Args.Iterator.init(init.minimal.args);
    var args = std.array_list.Managed([]const u8).init(allocator);
    while (args_iter.next()) |arg| try args.append(arg);

    try run(allocator, init.io, try parseArgs(allocator, args.items));
}

fn parseArgs(allocator: std.mem.Allocator, args: []const []const u8) !Options {
    var icons = std.array_list.Managed([]const u8).init(allocator);
    var aliases = std.array_list.Managed(Alias).init(allocator);

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printUsage();
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "--alias")) {
            i += 1;
            if (i >= args.len) return usageError("missing value for --alias");
            try aliases.append(try parseAlias(args[i]));
        } else if (std.mem.startsWith(u8, arg, "--alias=")) {
            try aliases.append(try parseAlias(arg["--alias=".len..]));
        } else if (std.mem.startsWith(u8, arg, "-")) {
            return usageError("unknown argument");
        } else {
            try validateIconName(arg);
            try icons.append(arg);
        }
    }

    if (icons.items.len == 0 and aliases.items.len == 0) return usageError("provide at least one icon or alias");
    return .{ .icons = icons.items, .aliases = aliases.items };
}

fn parseAlias(value: []const u8) !Alias {
    const split = std.mem.indexOfScalar(u8, value, '=') orelse return usageError("alias must be name=icon");
    const name = value[0..split];
    const icon = value[split + 1 ..];
    try validateIconName(name);
    try validateIconName(icon);
    return .{ .name = name, .icon = icon };
}

fn validateIconName(name: []const u8) !void {
    if (name.len == 0) return error.InvalidIconName;
    for (name) |ch| {
        if ((ch >= 'a' and ch <= 'z') or (ch >= '0' and ch <= '9') or ch == '-') continue;
        return error.InvalidIconName;
    }
}

fn usageError(message: []const u8) error{InvalidArguments} {
    std.debug.print("{s}\n\n", .{message});
    printUsage();
    return error.InvalidArguments;
}

fn printUsage() void {
    std.debug.print(
        \\usage: zig run .agents/skills/iconoir/scripts/download_iconoir.zig -- <icon>... [--alias name=icon]
        \\
        \\Examples:
        \\  zig run .agents/skills/iconoir/scripts/download_iconoir.zig -- cursor-pointer road --alias cursor=cursor-pointer
        \\  zig run .agents/skills/iconoir/scripts/download_iconoir.zig -- arrow-right --alias next=arrow-right
        \\
    , .{});
}

fn run(allocator: std.mem.Allocator, io: std.Io, options: Options) !void {
    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, source_dir);
    try cwd.createDirPath(io, runtime_dir);

    var fetched = std.StringHashMap([]const u8).init(allocator);
    for (options.icons) |icon| try fetchIcon(allocator, io, cwd, &fetched, icon);
    for (options.aliases) |alias| try fetchIcon(allocator, io, cwd, &fetched, alias.icon);

    var manifest = try loadManifest(allocator, io, cwd);
    defer manifest.deinit();
    for (options.icons) |icon| try manifest.put(icon, try svgFileName(allocator, icon));
    for (options.aliases) |alias| try manifest.put(alias.name, try svgFileName(allocator, alias.icon));
    try writeManifest(allocator, io, cwd, manifest);

    const count = fetched.count();
    std.debug.print("vendored {d} Iconoir icon{s}\n", .{ count, if (count == 1) "" else "s" });
}

fn fetchIcon(
    allocator: std.mem.Allocator,
    io: std.Io,
    cwd: std.Io.Dir,
    fetched: *std.StringHashMap([]const u8),
    icon: []const u8,
) !void {
    if (fetched.contains(icon)) return;

    const file_name = try svgFileName(allocator, icon);
    const url = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ raw_base_url, file_name });
    const svg = try runCapture(allocator, io, &.{ "curl", "-fsSL", url }, .{ .path = "." });
    if (!std.mem.startsWith(u8, std.mem.trim(u8, svg, " \t\r\n"), "<svg")) return error.InvalidIconSvg;

    const source_path = try std.fs.path.join(allocator, &.{ source_dir, file_name });
    const runtime_path = try std.fs.path.join(allocator, &.{ runtime_dir, file_name });
    try cwd.writeFile(io, .{ .sub_path = source_path, .data = svg });
    try cwd.writeFile(io, .{ .sub_path = runtime_path, .data = svg });
    try fetched.put(icon, file_name);
}

fn svgFileName(allocator: std.mem.Allocator, icon: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}.svg", .{icon});
}

const Manifest = struct {
    allocator: std.mem.Allocator,
    source: []const u8 = "Iconoir",
    source_url: []const u8 = "https://iconoir.com",
    repository: []const u8 = "https://github.com/iconoir-icons/iconoir",
    license: []const u8 = "MIT",
    style: []const u8 = "regular",
    icons: std.array_hash_map.String([]const u8),

    fn deinit(self: *Manifest) void {
        self.icons.deinit(self.allocator);
    }

    fn put(self: *Manifest, key: []const u8, value: []const u8) !void {
        try self.icons.put(self.allocator, key, value);
    }
};

fn loadManifest(allocator: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir) !Manifest {
    var manifest = Manifest{ .allocator = allocator, .icons = .empty };
    const bytes = cwd.readFileAlloc(io, manifest_path, allocator, .limited(1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return manifest,
        else => return err,
    };

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{});
    defer parsed.deinit();
    const root = parsed.value.object;
    manifest.source = readString(root, "source") orelse manifest.source;
    manifest.source_url = readString(root, "source_url") orelse manifest.source_url;
    manifest.repository = readString(root, "repository") orelse manifest.repository;
    manifest.license = readString(root, "license") orelse manifest.license;
    manifest.style = readString(root, "style") orelse manifest.style;
    const icons_value = root.get("icons") orelse return manifest;
    var iter = icons_value.object.iterator();
    while (iter.next()) |entry| {
        try manifest.put(entry.key_ptr.*, entry.value_ptr.string);
    }
    return manifest;
}

fn readString(root: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const value = root.get(key) orelse return null;
    return switch (value) {
        .string => |text| text,
        else => null,
    };
}

fn writeManifest(allocator: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir, manifest: Manifest) !void {
    var out = std.array_list.Managed(u8).init(allocator);
    try out.print(
        \\{{
        \\  "source": "{s}",
        \\  "source_url": "{s}",
        \\  "repository": "{s}",
        \\  "license": "{s}",
        \\  "style": "{s}",
        \\  "icons": {{
        \\
    , .{ manifest.source, manifest.source_url, manifest.repository, manifest.license, manifest.style });

    var iter = manifest.icons.iterator();
    var index: usize = 0;
    while (iter.next()) |entry| : (index += 1) {
        const comma = if (index + 1 == manifest.icons.count()) "" else ",";
        try out.print("    \"{s}\": \"{s}\"{s}\n", .{ entry.key_ptr.*, entry.value_ptr.*, comma });
    }

    try out.appendSlice(
        \\  }
        \\}
        \\
    );
    try cwd.writeFile(io, .{ .sub_path = manifest_path, .data = out.items });
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
        .stdout_limit = .limited(256 * 1024),
        .stderr_limit = .limited(128 * 1024),
    });
    switch (result.term) {
        .exited => |code| if (code == 0) return result.stdout,
        .signal, .stopped, .unknown => {},
    }
    std.debug.print("{s}", .{result.stderr});
    return error.CommandFailed;
}
