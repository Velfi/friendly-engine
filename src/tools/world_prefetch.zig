const std = @import("std");
const friendly_engine = @import("friendly_engine");

const world = friendly_engine.world;

pub const CellEntry = struct {
    cell: [3]i32,
    dependencies: []const Dependency,
};

pub const Dependency = struct {
    kind: []const u8,
    path: []const u8,
};

pub fn write(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_dir: std.Io.Dir,
    target: []const u8,
    world_id: []const u8,
    cells: []const CellEntry,
) !void {
    const path = try std.fmt.allocPrint(allocator, "assets/cache/{s}/world/{s}/prefetch.json", .{ target, world_id });
    defer allocator.free(path);
    if (std.fs.path.dirname(path)) |parent| try project_dir.createDirPath(io, parent);

    const doc = .{
        .schema_version = @as(u16, 1),
        .target = target,
        .world_id = world_id,
        .cell_count = cells.len,
        .cells = cells,
    };
    const json = try std.fmt.allocPrint(
        allocator,
        "{f}\n",
        .{std.json.fmt(doc, .{ .whitespace = .indent_2 })},
    );
    defer allocator.free(json);
    try project_dir.writeFile(io, .{ .sub_path = path, .data = json });
}

pub fn copyCellEntry(
    allocator: std.mem.Allocator,
    id: world.cell.CellId,
    dependencies: []const world.cell.CellDependency,
) !CellEntry {
    var deps = try allocator.alloc(Dependency, dependencies.len);
    errdefer allocator.free(deps);
    for (dependencies, 0..) |dependency, i| {
        deps[i] = .{
            .kind = try allocator.dupe(u8, dependency.kind),
            .path = try allocator.dupe(u8, dependency.path),
        };
    }
    return .{
        .cell = .{ id.x, id.y, id.z },
        .dependencies = deps,
    };
}

pub fn freeEntries(allocator: std.mem.Allocator, entries: []CellEntry) void {
    for (entries) |entry| {
        for (entry.dependencies) |dependency| {
            allocator.free(dependency.kind);
            allocator.free(dependency.path);
        }
        allocator.free(entry.dependencies);
    }
    allocator.free(entries);
}
