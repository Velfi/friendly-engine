const std = @import("std");
const kdl = @import("kdl");
const cell = @import("cell.zig");

const max_manifest_bytes: usize = 1024 * 1024;

pub const ManifestCell = struct {
    id: cell.CellId,
    authoring_path: []u8,
    interior_parent: ?cell.CellId = null,
};

pub const OwnedWorldManifest = struct {
    allocator: std.mem.Allocator,
    world_id: []u8,
    manifest_path: []u8,
    cell_size_m: f32,
    cells: []ManifestCell,
    lookup: std.AutoHashMap(cell.CellId, usize),

    pub fn deinit(self: *OwnedWorldManifest) void {
        for (self.cells) |entry| {
            self.allocator.free(entry.authoring_path);
        }
        self.allocator.free(self.cells);
        self.lookup.deinit();
        self.allocator.free(self.world_id);
        self.allocator.free(self.manifest_path);
    }

    pub fn hasCell(self: *const OwnedWorldManifest, id: cell.CellId) bool {
        return self.lookup.contains(id);
    }

    pub fn findCell(self: *const OwnedWorldManifest, id: cell.CellId) ?ManifestCell {
        const index = self.lookup.get(id) orelse return null;
        return self.cells[index];
    }
};

pub fn loadManifest(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    manifest_rel_path: []const u8,
) !OwnedWorldManifest {
    var project_dir = try openProjectDir(io, project_path);
    defer project_dir.close(io);

    const bytes = try project_dir.readFileAlloc(io, manifest_rel_path, allocator, .limited(max_manifest_bytes));
    defer allocator.free(bytes);

    const parsed = try parseManifestBytes(allocator, bytes);
    defer parsed.deinit(allocator);

    if (parsed.schema_version != 1) return error.UnsupportedWorldManifestVersion;
    if (!std.math.isFinite(parsed.cell_size_m) or parsed.cell_size_m <= 0) return error.InvalidWorldManifest;

    const manifest_dir = std.fs.path.dirname(manifest_rel_path) orelse "";
    const world_id_slice = parsed.world_id orelse std.fs.path.stem(std.fs.path.basename(manifest_rel_path));
    if (world_id_slice.len == 0) return error.InvalidWorldManifest;

    var cells = try allocator.alloc(ManifestCell, parsed.cells.items.len);
    var initialized_cells: usize = 0;
    errdefer {
        for (cells[0..initialized_cells]) |entry| allocator.free(entry.authoring_path);
        allocator.free(cells);
    }

    var lookup = std.AutoHashMap(cell.CellId, usize).init(allocator);
    errdefer lookup.deinit();

    for (parsed.cells.items, 0..) |entry, index| {
        const id = entry.id;
        const resolved_path = if (std.fs.path.isAbsolute(entry.authoring))
            try allocator.dupe(u8, entry.authoring)
        else if (manifest_dir.len == 0)
            try allocator.dupe(u8, entry.authoring)
        else
            try std.fs.path.join(allocator, &.{ manifest_dir, entry.authoring });

        cells[index] = .{
            .id = id,
            .authoring_path = resolved_path,
            .interior_parent = entry.interior_parent,
        };
        initialized_cells = index + 1;

        if (lookup.contains(id)) return error.DuplicateCellCoordinate;
        try lookup.put(id, index);
    }

    for (cells) |entry| {
        if (entry.interior_parent) |parent| {
            if (!lookup.contains(parent)) return error.InvalidWorldManifest;
            if (parent.eql(entry.id)) return error.InvalidWorldManifest;
        }
    }

    return .{
        .allocator = allocator,
        .world_id = try allocator.dupe(u8, world_id_slice),
        .manifest_path = try allocator.dupe(u8, manifest_rel_path),
        .cell_size_m = parsed.cell_size_m,
        .cells = cells,
        .lookup = lookup,
    };
}

fn openProjectDir(io: std.Io, project_path: []const u8) !std.Io.Dir {
    if (std.fs.path.isAbsolute(project_path)) {
        return try std.Io.Dir.openDirAbsolute(io, project_path, .{});
    }
    return try std.Io.Dir.cwd().openDir(io, project_path, .{});
}

const ParsedManifestCell = struct {
    id: cell.CellId,
    authoring: []u8,
    interior_parent: ?cell.CellId = null,
};

const ParsedManifest = struct {
    schema_version: u32 = 1,
    world_id: ?[]u8 = null,
    cell_size_m: f32 = cell.default_cell_size_m,
    cells: std.ArrayList(ParsedManifestCell),

    fn deinit(self: *const ParsedManifest, allocator: std.mem.Allocator) void {
        if (self.world_id) |world_id| allocator.free(world_id);
        for (self.cells.items) |entry| {
            allocator.free(entry.authoring);
        }
        var cells = self.cells;
        cells.deinit(allocator);
    }
};

const CellBuilder = struct {
    id: ?cell.CellId = null,
    authoring: ?[]u8 = null,
    interior_parent: ?cell.CellId = null,

    fn deinit(self: *CellBuilder, allocator: std.mem.Allocator) void {
        if (self.authoring) |authoring| allocator.free(authoring);
        self.* = .{};
    }

    fn finish(self: *CellBuilder) !ParsedManifestCell {
        const id = self.id orelse return error.InvalidWorldManifest;
        const authoring = self.authoring orelse return error.InvalidWorldManifest;
        self.authoring = null;
        return .{
            .id = id,
            .authoring = authoring,
            .interior_parent = self.interior_parent,
        };
    }
};

fn parseManifestBytes(allocator: std.mem.Allocator, bytes: []const u8) !ParsedManifest {
    const buffer = try allocator.allocSentinel(u8, bytes.len, 0);
    defer allocator.free(buffer);
    @memcpy(buffer, bytes);

    var parser = kdl.Parser.init(buffer);
    var parsed = ParsedManifest{
        .cells = .empty,
    };
    errdefer parsed.deinit(allocator);

    var depth: i32 = 0;
    var root_seen = false;
    var current_node: ?[]const u8 = null;
    var pending_cell: ?CellBuilder = null;
    errdefer if (pending_cell) |*builder| builder.deinit(allocator);

    while (true) {
        const event = try parser.next();
        switch (event) {
            .node => |node| {
                if (depth == 0) {
                    if (root_seen or !std.mem.eql(u8, node.val, "world")) return error.InvalidWorldManifest;
                    root_seen = true;
                    current_node = node.val;
                    continue;
                }
                if (depth == 1) {
                    if (!std.mem.eql(u8, node.val, "cell")) return error.UnknownField;
                    if (pending_cell) |*builder| {
                        try parsed.cells.append(allocator, try builder.finish());
                    }
                    pending_cell = .{};
                    current_node = node.val;
                    continue;
                }
                return error.InvalidWorldManifest;
            },
            .prop => |prop| {
                const value = try decodeValue(allocator, prop.val);
                defer allocator.free(value);
                if (depth == 0) {
                    if (std.mem.eql(u8, prop.key, "version")) {
                        parsed.schema_version = try std.fmt.parseInt(u32, value, 10);
                    } else if (std.mem.eql(u8, prop.key, "id")) {
                        if (parsed.world_id) |existing| allocator.free(existing);
                        parsed.world_id = try allocator.dupe(u8, value);
                    } else if (std.mem.eql(u8, prop.key, "cell_size_m")) {
                        parsed.cell_size_m = try std.fmt.parseFloat(f32, value);
                    } else {
                        return error.UnknownField;
                    }
                    continue;
                }
                if (depth == 1 and std.mem.eql(u8, current_node orelse "", "cell")) {
                    var builder = &(pending_cell orelse return error.InvalidWorldManifest);
                    if (std.mem.eql(u8, prop.key, "coord")) {
                        builder.id = try parseCellId(value);
                    } else if (std.mem.eql(u8, prop.key, "authoring")) {
                        if (builder.authoring) |existing| allocator.free(existing);
                        builder.authoring = try allocator.dupe(u8, value);
                    } else if (std.mem.eql(u8, prop.key, "interior_parent")) {
                        builder.interior_parent = try parseCellId(value);
                    } else {
                        return error.UnknownField;
                    }
                    continue;
                }
                return error.InvalidWorldManifest;
            },
            .child_block_begin => depth += 1,
            .child_block_end => {
                if (depth == 1) {
                    if (pending_cell) |*builder| {
                        try parsed.cells.append(allocator, try builder.finish());
                        pending_cell = null;
                    }
                }
                depth -= 1;
                if (depth < 0) return error.InvalidWorldManifest;
                current_node = null;
            },
            .arg, .invalid => return error.InvalidWorldManifest,
            .eof => break,
        }
    }

    if (pending_cell) |*builder| {
        try parsed.cells.append(allocator, try builder.finish());
        pending_cell = null;
    }
    if (!root_seen or depth != 0) return error.InvalidWorldManifest;
    return parsed;
}

fn decodeValue(allocator: std.mem.Allocator, raw: []const u8) ![]const u8 {
    return kdl.string_utils.makeRealString(allocator, raw);
}

fn parseCellId(text: []const u8) !cell.CellId {
    var values: [3]i32 = .{ 0, 0, 0 };
    var count: usize = 0;
    var parts = std.mem.splitScalar(u8, text, ',');
    while (parts.next()) |part| {
        if (count >= 3) return error.InvalidWorldManifest;
        values[count] = try std.fmt.parseInt(i32, std.mem.trim(u8, part, " \t"), 10);
        count += 1;
    }
    if (count != 2 and count != 3) return error.InvalidWorldManifest;
    return .{
        .x = values[0],
        .y = values[1],
        .z = values[2],
    };
}

test "manifest loads and resolves authoring paths" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, "worlds/cells");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "worlds/main.world.kdl",
        .data =
        \\world version=1 cell_size_m=256 {
        \\  cell coord="0,0" authoring="cells/start.kdl"
        \\}
        \\
        ,
    });

    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);

    var loaded = try loadManifest(
        std.testing.allocator,
        std.testing.io,
        project_path,
        "worlds/main.world.kdl",
    );
    defer loaded.deinit();

    try std.testing.expectEqual(@as(usize, 1), loaded.cells.len);
    try std.testing.expectEqualStrings("main.world", loaded.world_id);
    try std.testing.expectEqualStrings("worlds/cells/start.kdl", loaded.cells[0].authoring_path);
    try std.testing.expect(loaded.hasCell(.{ .x = 0, .y = 0, .z = 0 }));
    try std.testing.expect(loaded.cells[0].interior_parent == null);
}

test "manifest parses interior parent links" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "world.kdl",
        .data =
        \\world version=1 id="main" cell_size_m=256 {
        \\  cell coord="0,0,0" authoring="scenes/outdoor.kdl"
        \\  cell coord="0,0,1" authoring="scenes/interior.kdl" interior_parent="0,0,0"
        \\}
        \\
        ,
    });
    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);
    var loaded = try loadManifest(std.testing.allocator, std.testing.io, project_path, "world.kdl");
    defer loaded.deinit();
    try std.testing.expectEqual(@as(usize, 2), loaded.cells.len);
    try std.testing.expect(loaded.cells[1].interior_parent != null);
    try std.testing.expect(loaded.cells[1].interior_parent.?.eql(.{ .x = 0, .y = 0, .z = 0 }));
}

test "manifest allows zero cells" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "world.kdl",
        .data =
        \\world version=1 id="empty" cell_size_m=256 {
        \\}
        \\
        ,
    });
    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);
    var loaded = try loadManifest(std.testing.allocator, std.testing.io, project_path, "world.kdl");
    defer loaded.deinit();
    try std.testing.expectEqual(@as(usize, 0), loaded.cells.len);
    try std.testing.expectEqualStrings("empty", loaded.world_id);
    try std.testing.expectEqual(@as(f32, 256), loaded.cell_size_m);
}

test "manifest rejects invalid cell size" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "world.kdl",
        .data =
        \\world version=1 id="main" cell_size_m=0 {
        \\  cell coord="0,0,0" authoring="scenes/main.kdl"
        \\}
        \\
        ,
    });

    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);
    try std.testing.expectError(
        error.InvalidWorldManifest,
        loadManifest(std.testing.allocator, std.testing.io, project_path, "world.kdl"),
    );
}

test "manifest rejects dangling interior parent links" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "world.kdl",
        .data =
        \\world version=1 id="main" cell_size_m=256 {
        \\  cell coord="0,0,1" authoring="scenes/interior.kdl" interior_parent="0,0,0"
        \\}
        \\
        ,
    });

    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);
    try std.testing.expectError(
        error.InvalidWorldManifest,
        loadManifest(std.testing.allocator, std.testing.io, project_path, "world.kdl"),
    );
}

test "manifest rejects unknown fields" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "world.kdl",
        .data =
        \\world version=1 id="main" cell_size_m=256 {
        \\  cell coord="0,0,0" authoring="scenes/main.kdl" authroing="typo.kdl"
        \\}
        \\
        ,
    });

    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);
    try std.testing.expectError(
        error.UnknownField,
        loadManifest(std.testing.allocator, std.testing.io, project_path, "world.kdl"),
    );
}
