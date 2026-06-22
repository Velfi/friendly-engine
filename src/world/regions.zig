const std = @import("std");
const kdl = @import("kdl");
const cell = @import("cell.zig");

const max_regions_bytes: usize = 1024 * 1024;

pub const default_regions_path = "world_regions.kdl";

pub const Region = struct {
    id: []u8,
    name: []u8,
    props: []u8 = &.{},
    cells: []cell.CellId,
};

pub const OwnedRegions = struct {
    allocator: std.mem.Allocator,
    regions: []Region,

    pub fn deinit(self: *OwnedRegions) void {
        for (self.regions) |region| {
            self.allocator.free(region.id);
            self.allocator.free(region.name);
            self.allocator.free(region.props);
            self.allocator.free(region.cells);
        }
        self.allocator.free(self.regions);
    }

    pub fn regionForCell(self: *const OwnedRegions, id: cell.CellId) ?usize {
        for (self.regions, 0..) |region, index| {
            for (region.cells) |member| {
                if (member.eql(id)) return index;
            }
        }
        return null;
    }
};

pub const RegionInput = struct {
    id: []const u8,
    name: []const u8,
    props: []const u8 = "",
    cells: []const cell.CellId,
};

pub const PaintMode = enum {
    assign,
    erase,
};

pub fn loadRegions(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    rel_path: []const u8,
) !?OwnedRegions {
    var project_dir = try openProjectDir(io, project_path);
    defer project_dir.close(io);

    const bytes = project_dir.readFileAlloc(io, rel_path, allocator, .limited(max_regions_bytes)) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer allocator.free(bytes);

    return try parseRegionsBytes(allocator, bytes);
}

pub fn loadOrEmpty(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    rel_path: []const u8,
) !OwnedRegions {
    return (try loadRegions(allocator, io, project_path, rel_path)) orelse .{
        .allocator = allocator,
        .regions = try allocator.alloc(Region, 0),
    };
}

pub fn saveRegions(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    rel_path: []const u8,
    regions: []const RegionInput,
) !void {
    var bytes: std.Io.Writer.Allocating = .init(allocator);
    defer bytes.deinit();
    const writer = &bytes.writer;
    try writer.writeAll("world_regions version=1 {\n");
    for (regions) |region| {
        try validateRegionText(region.id);
        try validateRegionText(region.name);
        try writer.writeAll("  region id=");
        try writeQuotedString(writer, region.id);
        try writer.writeAll(" name=");
        try writeQuotedString(writer, region.name);
        if (region.props.len > 0) {
            try validateRegionText(region.props);
            try writer.writeAll(" props=");
            try writeQuotedString(writer, region.props);
        }
        try writer.writeAll(" {\n");
        for (region.cells) |id| {
            try writer.print("    cell coord=\"{d},{d},{d}\"\n", .{ id.x, id.y, id.z });
        }
        try writer.writeAll("  }\n");
    }
    try writer.writeAll("}\n");

    var project_dir = try openProjectDir(io, project_path);
    defer project_dir.close(io);
    if (std.fs.path.dirname(rel_path)) |parent| try project_dir.createDirPath(io, parent);
    try project_dir.writeFile(io, .{ .sub_path = rel_path, .data = bytes.written() });
}

fn writeQuotedString(writer: *std.Io.Writer, value: []const u8) !void {
    try writer.writeByte('"');
    for (value) |byte| {
        switch (byte) {
            '\\' => try writer.writeAll("\\\\"),
            '"' => try writer.writeAll("\\\""),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => try writer.writeByte(byte),
        }
    }
    try writer.writeByte('"');
}

fn validateRegionText(value: []const u8) !void {
    for (value) |byte| {
        if (byte < 0x20) return error.InvalidWorldRegionText;
        if (byte == '"' or byte == '\\') return error.InvalidWorldRegionText;
    }
}

pub fn upsertRegion(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    rel_path: []const u8,
    input: RegionInput,
) !OwnedRegions {
    var loaded = try loadOrEmpty(allocator, io, project_path, rel_path);
    defer loaded.deinit();

    var inputs = std.ArrayList(RegionInput).empty;
    defer inputs.deinit(allocator);
    var filtered_cell_sets = std.ArrayList([]cell.CellId).empty;
    defer {
        for (filtered_cell_sets.items) |cells| allocator.free(cells);
        filtered_cell_sets.deinit(allocator);
    }
    var replaced = false;
    for (loaded.regions) |region| {
        if (std.mem.eql(u8, region.id, input.id)) {
            try inputs.append(allocator, input);
            replaced = true;
        } else {
            const filtered = try cellsWithout(allocator, region.cells, input.cells);
            try filtered_cell_sets.append(allocator, filtered);
            try inputs.append(allocator, .{ .id = region.id, .name = region.name, .props = region.props, .cells = filtered });
        }
    }
    if (!replaced) try inputs.append(allocator, input);

    try saveRegions(allocator, io, project_path, rel_path, inputs.items);
    return try loadOrEmpty(allocator, io, project_path, rel_path);
}

fn cellsWithout(allocator: std.mem.Allocator, source: []const cell.CellId, removed: []const cell.CellId) ![]cell.CellId {
    var out = std.ArrayList(cell.CellId).empty;
    errdefer out.deinit(allocator);
    for (source) |candidate| {
        if (containsCell(removed, candidate)) continue;
        try out.append(allocator, candidate);
    }
    return out.toOwnedSlice(allocator);
}

fn containsCell(cells: []const cell.CellId, id: cell.CellId) bool {
    for (cells) |candidate| {
        if (candidate.eql(id)) return true;
    }
    return false;
}

fn unionCells(allocator: std.mem.Allocator, a: []const cell.CellId, b: []const cell.CellId) ![]cell.CellId {
    var out = std.ArrayList(cell.CellId).empty;
    errdefer out.deinit(allocator);
    for (a) |id| {
        if (!containsCell(out.items, id)) try out.append(allocator, id);
    }
    for (b) |id| {
        if (!containsCell(out.items, id)) try out.append(allocator, id);
    }
    return out.toOwnedSlice(allocator);
}

fn uniqueCells(allocator: std.mem.Allocator, cells: []const cell.CellId) ![]cell.CellId {
    return unionCells(allocator, &.{}, cells);
}

pub fn deleteRegion(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    rel_path: []const u8,
    id: []const u8,
) !OwnedRegions {
    var loaded = try loadOrEmpty(allocator, io, project_path, rel_path);
    defer loaded.deinit();

    var inputs = std.ArrayList(RegionInput).empty;
    defer inputs.deinit(allocator);
    var removed = false;
    for (loaded.regions) |region| {
        if (std.mem.eql(u8, region.id, id)) {
            removed = true;
            continue;
        }
        try inputs.append(allocator, .{ .id = region.id, .name = region.name, .props = region.props, .cells = region.cells });
    }
    if (!removed) return error.WorldRegionNotFound;

    try saveRegions(allocator, io, project_path, rel_path, inputs.items);
    return try loadOrEmpty(allocator, io, project_path, rel_path);
}

pub fn paintRegionCells(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    rel_path: []const u8,
    region_id: []const u8,
    region_name: []const u8,
    cells: []const cell.CellId,
    mode: PaintMode,
) !OwnedRegions {
    var loaded = try loadOrEmpty(allocator, io, project_path, rel_path);
    defer loaded.deinit();

    var inputs = std.ArrayList(RegionInput).empty;
    defer inputs.deinit(allocator);
    var scratch_sets = std.ArrayList([]cell.CellId).empty;
    defer {
        for (scratch_sets.items) |owned_cells| allocator.free(owned_cells);
        scratch_sets.deinit(allocator);
    }
    var found_target = false;
    for (loaded.regions) |region| {
        if (std.mem.eql(u8, region.id, region_id)) {
            found_target = true;
            const updated = switch (mode) {
                .assign => try unionCells(allocator, region.cells, cells),
                .erase => try cellsWithout(allocator, region.cells, cells),
            };
            try scratch_sets.append(allocator, updated);
            try inputs.append(allocator, .{ .id = region.id, .name = region.name, .props = region.props, .cells = updated });
            continue;
        }
        const updated = switch (mode) {
            .assign => try cellsWithout(allocator, region.cells, cells),
            .erase => try allocator.dupe(cell.CellId, region.cells),
        };
        try scratch_sets.append(allocator, updated);
        try inputs.append(allocator, .{ .id = region.id, .name = region.name, .props = region.props, .cells = updated });
    }
    if (!found_target and mode == .assign) {
        const unique = try uniqueCells(allocator, cells);
        try scratch_sets.append(allocator, unique);
        try inputs.append(allocator, .{ .id = region_id, .name = region_name, .cells = unique });
    }
    if (!found_target and mode == .erase) return error.WorldRegionNotFound;

    try saveRegions(allocator, io, project_path, rel_path, inputs.items);
    return try loadOrEmpty(allocator, io, project_path, rel_path);
}

fn parseRegionsBytes(allocator: std.mem.Allocator, bytes: []const u8) !OwnedRegions {
    const buffer = try allocator.allocSentinel(u8, bytes.len, 0);
    defer allocator.free(buffer);
    @memcpy(buffer, bytes);

    var parser = kdl.Parser.init(buffer);
    var regions = std.ArrayList(RegionBuilder).empty;
    errdefer {
        for (regions.items) |*region| region.deinit(allocator);
        regions.deinit(allocator);
    }

    var depth: i32 = 0;
    var root_seen = false;
    var current_region: ?RegionBuilder = null;
    errdefer if (current_region) |*region| region.deinit(allocator);

    while (true) {
        const event = try parser.next();
        switch (event) {
            .node => |node| {
                if (depth == 0) {
                    if (root_seen or !std.mem.eql(u8, node.val, "world_regions")) return error.InvalidWorldRegions;
                    root_seen = true;
                    continue;
                }
                if (depth == 1) {
                    if (!std.mem.eql(u8, node.val, "region")) return error.UnknownField;
                    if (current_region) |*region| {
                        try regions.append(allocator, region.*);
                    }
                    current_region = .{ .cells = .empty };
                    continue;
                }
                if (depth == 2) {
                    if (!std.mem.eql(u8, node.val, "cell")) return error.UnknownField;
                    continue;
                }
                return error.InvalidWorldRegions;
            },
            .prop => |prop| {
                const value = try decodeValue(allocator, prop.val);
                defer allocator.free(value);
                if (depth == 0) {
                    if (std.mem.eql(u8, prop.key, "version")) continue;
                    return error.UnknownField;
                }
                if (depth == 1) {
                    var region = &(current_region orelse return error.InvalidWorldRegions);
                    if (std.mem.eql(u8, prop.key, "id")) {
                        if (region.id) |existing| allocator.free(existing);
                        region.id = try allocator.dupe(u8, value);
                    } else if (std.mem.eql(u8, prop.key, "name")) {
                        if (region.name) |existing| allocator.free(existing);
                        region.name = try allocator.dupe(u8, value);
                    } else if (std.mem.eql(u8, prop.key, "props")) {
                        if (region.props) |existing| allocator.free(existing);
                        region.props = try allocator.dupe(u8, value);
                    } else {
                        return error.UnknownField;
                    }
                    continue;
                }
                if (depth == 2) {
                    if (!std.mem.eql(u8, prop.key, "coord")) return error.UnknownField;
                    var region = &(current_region orelse return error.InvalidWorldRegions);
                    try region.cells.append(allocator, try parseCellId(value));
                    continue;
                }
                return error.InvalidWorldRegions;
            },
            .child_block_begin => depth += 1,
            .child_block_end => {
                if (depth == 1) {
                    if (current_region) |*region| {
                        try regions.append(allocator, region.*);
                        current_region = null;
                    }
                }
                depth -= 1;
                if (depth < 0) return error.InvalidWorldRegions;
            },
            .arg, .invalid => return error.InvalidWorldRegions,
            .eof => break,
        }
    }

    if (current_region) |*region| {
        try regions.append(allocator, region.*);
        current_region = null;
    }
    if (!root_seen or depth != 0) return error.InvalidWorldRegions;

    var owned = try allocator.alloc(Region, regions.items.len);
    errdefer allocator.free(owned);
    for (regions.items, 0..) |*builder, index| {
        owned[index] = try builder.finish(allocator);
    }
    regions.deinit(allocator);
    return .{ .allocator = allocator, .regions = owned };
}

const RegionBuilder = struct {
    id: ?[]u8 = null,
    name: ?[]u8 = null,
    props: ?[]u8 = null,
    cells: std.ArrayList(cell.CellId),

    fn deinit(self: *RegionBuilder, allocator: std.mem.Allocator) void {
        if (self.id) |id| allocator.free(id);
        if (self.name) |name| allocator.free(name);
        if (self.props) |props| allocator.free(props);
        self.cells.deinit(allocator);
        self.* = .{ .cells = .empty };
    }

    fn finish(self: *RegionBuilder, allocator: std.mem.Allocator) !Region {
        const id = self.id orelse return error.InvalidWorldRegions;
        const name = self.name orelse try allocator.dupe(u8, id);
        const props = self.props orelse try allocator.alloc(u8, 0);
        const cells = try self.cells.toOwnedSlice(allocator);
        self.id = null;
        self.name = null;
        self.props = null;
        return .{ .id = id, .name = name, .props = props, .cells = cells };
    }
};

fn decodeValue(allocator: std.mem.Allocator, raw: []const u8) ![]const u8 {
    return kdl.string_utils.makeRealString(allocator, raw);
}

fn parseCellId(text: []const u8) !cell.CellId {
    var it = std.mem.splitScalar(u8, text, ',');
    const x_text = it.next() orelse return error.InvalidCellCoordinate;
    const y_text = it.next() orelse return error.InvalidCellCoordinate;
    const z_text = it.next() orelse return error.InvalidCellCoordinate;
    if (it.next() != null) return error.InvalidCellCoordinate;
    return .{
        .x = try std.fmt.parseInt(i32, x_text, 10),
        .y = try std.fmt.parseInt(i32, y_text, 10),
        .z = try std.fmt.parseInt(i32, z_text, 10),
    };
}

fn openProjectDir(io: std.Io, project_path: []const u8) !std.Io.Dir {
    if (std.fs.path.isAbsolute(project_path)) return std.Io.Dir.openDirAbsolute(io, project_path, .{});
    return std.Io.Dir.cwd().openDir(io, project_path, .{});
}

test "world regions support irregular cell membership" {
    const bytes =
        \\world_regions version=1 {
        \\  region id="green" name="Village Green" {
        \\    cell coord="0,0,0"
        \\    cell coord="1,0,0"
        \\    cell coord="1,1,0"
        \\  }
        \\  region id="fell" name="Fell Edge" {
        \\    cell coord="-4,2,0"
        \\  }
        \\}
        \\
    ;
    var regions = try parseRegionsBytes(std.testing.allocator, bytes);
    defer regions.deinit();
    try std.testing.expectEqual(@as(usize, 2), regions.regions.len);
    try std.testing.expectEqual(@as(usize, 3), regions.regions[0].cells.len);
    try std.testing.expectEqual(@as(usize, 1), regions.regionForCell(.{ .x = -4, .y = 2, .z = 0 }).?);
}

test "world regions save and upsert irregular regions" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);

    var regions = try upsertRegion(std.testing.allocator, std.testing.io, project_path, default_regions_path, .{
        .id = "fell",
        .name = "Fell Edge",
        .cells = &.{
            .{ .x = -1, .y = 0, .z = 0 },
            .{ .x = -1, .y = 1, .z = 0 },
            .{ .x = 3, .y = 4, .z = 0 },
        },
    });
    defer regions.deinit();
    try std.testing.expectEqual(@as(usize, 1), regions.regions.len);
    try std.testing.expectEqual(@as(usize, 3), regions.regions[0].cells.len);

    var replaced = try upsertRegion(std.testing.allocator, std.testing.io, project_path, default_regions_path, .{
        .id = "fell",
        .name = "Fell Edge",
        .cells = &.{.{ .x = 8, .y = 9, .z = 0 }},
    });
    defer replaced.deinit();
    try std.testing.expectEqual(@as(usize, 1), replaced.regions.len);
    try std.testing.expectEqual(@as(usize, 1), replaced.regions[0].cells.len);
    try std.testing.expectEqual(cell.CellId{ .x = 8, .y = 9, .z = 0 }, replaced.regions[0].cells[0]);
}

test "world regions persist empty regions and reject unsafe names" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);

    var saved = try upsertRegion(std.testing.allocator, std.testing.io, project_path, default_regions_path, .{
        .id = "region-empty",
        .name = "North Fell Edge",
        .cells = &.{},
    });
    saved.deinit();

    var loaded = try loadOrEmpty(std.testing.allocator, std.testing.io, project_path, default_regions_path);
    defer loaded.deinit();
    try std.testing.expectEqual(@as(usize, 1), loaded.regions.len);
    try std.testing.expectEqualStrings("region-empty", loaded.regions[0].id);
    try std.testing.expectEqualStrings("North Fell Edge", loaded.regions[0].name);
    try std.testing.expectEqual(@as(usize, 0), loaded.regions[0].cells.len);

    try std.testing.expectError(error.InvalidWorldRegionText, upsertRegion(std.testing.allocator, std.testing.io, project_path, default_regions_path, .{
        .id = "line\nbreak",
        .name = "Line Break",
        .cells = &.{},
    }));
    try std.testing.expectError(error.InvalidWorldRegionText, upsertRegion(std.testing.allocator, std.testing.io, project_path, default_regions_path, .{
        .id = "quote\"break",
        .name = "Quote Break",
        .cells = &.{},
    }));
    try std.testing.expectError(error.InvalidWorldRegionText, upsertRegion(std.testing.allocator, std.testing.io, project_path, default_regions_path, .{
        .id = "slash\\break",
        .name = "Slash Break",
        .cells = &.{},
    }));

    var dashed = try upsertRegion(std.testing.allocator, std.testing.io, project_path, default_regions_path, .{
        .id = "village-core",
        .name = "Village Core",
        .cells = &.{},
    });
    dashed.deinit();

    var project_dir = try openProjectDir(std.testing.io, project_path);
    defer project_dir.close(std.testing.io);
    const bytes = try project_dir.readFileAlloc(std.testing.io, default_regions_path, std.testing.allocator, .limited(max_regions_bytes));
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "id=\"village-core\"") != null);
}

test "world region upsert moves cells out of previous regions" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);

    var first = try upsertRegion(std.testing.allocator, std.testing.io, project_path, default_regions_path, .{
        .id = "north",
        .name = "North",
        .cells = &.{ .{ .x = 0, .y = 0, .z = 0 }, .{ .x = 1, .y = 0, .z = 0 } },
    });
    first.deinit();

    var second = try upsertRegion(std.testing.allocator, std.testing.io, project_path, default_regions_path, .{
        .id = "green",
        .name = "Green",
        .cells = &.{.{ .x = 1, .y = 0, .z = 0 }},
    });
    defer second.deinit();
    try std.testing.expectEqual(@as(usize, 2), second.regions.len);
    try std.testing.expectEqual(@as(usize, 1), second.regions[0].cells.len);
    try std.testing.expectEqual(cell.CellId{ .x = 0, .y = 0, .z = 0 }, second.regions[0].cells[0]);
    try std.testing.expectEqual(cell.CellId{ .x = 1, .y = 0, .z = 0 }, second.regions[1].cells[0]);

    var emptied = try upsertRegion(std.testing.allocator, std.testing.io, project_path, default_regions_path, .{
        .id = "south",
        .name = "South",
        .cells = &.{.{ .x = 0, .y = 0, .z = 0 }},
    });
    defer emptied.deinit();
    try std.testing.expectEqual(@as(usize, 3), emptied.regions.len);
    try std.testing.expectEqualStrings("north", emptied.regions[0].id);
    try std.testing.expectEqual(@as(usize, 0), emptied.regions[0].cells.len);
    try std.testing.expectEqualStrings("south", emptied.regions[2].id);
    try std.testing.expectEqual(@as(usize, 1), emptied.regions[2].cells.len);
}

test "world region paint assigns and erases arbitrary cells" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);

    var first = try paintRegionCells(std.testing.allocator, std.testing.io, project_path, default_regions_path, "green", "Green", &.{
        .{ .x = 0, .y = 0, .z = 0 },
        .{ .x = 1, .y = 0, .z = 0 },
    }, .assign);
    first.deinit();

    var moved = try paintRegionCells(std.testing.allocator, std.testing.io, project_path, default_regions_path, "fell", "Fell", &.{
        .{ .x = 1, .y = 0, .z = 0 },
    }, .assign);
    defer moved.deinit();
    try std.testing.expectEqual(@as(usize, 2), moved.regions.len);
    try std.testing.expectEqual(@as(usize, 1), moved.regions[0].cells.len);
    try std.testing.expectEqual(@as(usize, 1), moved.regions[1].cells.len);

    var erased = try paintRegionCells(std.testing.allocator, std.testing.io, project_path, default_regions_path, "fell", "Fell", &.{
        .{ .x = 1, .y = 0, .z = 0 },
    }, .erase);
    defer erased.deinit();
    try std.testing.expectEqual(@as(usize, 2), erased.regions.len);
    try std.testing.expectEqualStrings("green", erased.regions[0].id);
    try std.testing.expectEqualStrings("fell", erased.regions[1].id);
    try std.testing.expectEqual(@as(usize, 0), erased.regions[1].cells.len);
}

test "world region mutation fuzz keeps invalid text atomic" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);

    var baseline = try upsertRegion(std.testing.allocator, std.testing.io, project_path, default_regions_path, .{
        .id = "baseline",
        .name = "Baseline",
        .cells = &.{.{ .x = 0, .y = 0, .z = 0 }},
    });
    baseline.deinit();

    var project_dir = try openProjectDir(std.testing.io, project_path);
    defer project_dir.close(std.testing.io);
    const before = try project_dir.readFileAlloc(std.testing.io, default_regions_path, std.testing.allocator, .limited(max_regions_bytes));
    defer std.testing.allocator.free(before);

    var prng = std.Random.DefaultPrng.init(0x6d63705f72656731);
    var random = prng.random();
    var id_buf: [32]u8 = undefined;
    var name_buf: [32]u8 = undefined;
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        fillRegionFuzzText(&random, &id_buf);
        fillRegionFuzzText(&random, &name_buf);
        id_buf[random.uintLessThan(usize, id_buf.len)] = switch (i % 3) {
            0 => '\n',
            1 => '"',
            else => '\\',
        };

        try std.testing.expectError(error.InvalidWorldRegionText, upsertRegion(std.testing.allocator, std.testing.io, project_path, default_regions_path, .{
            .id = &id_buf,
            .name = &name_buf,
            .cells = &.{.{ .x = @intCast(i), .y = -@as(i32, @intCast(i % 17)), .z = 0 }},
        }));

        const after = try project_dir.readFileAlloc(std.testing.io, default_regions_path, std.testing.allocator, .limited(max_regions_bytes));
        defer std.testing.allocator.free(after);
        try std.testing.expectEqualStrings(before, after);
    }
}

fn fillRegionFuzzText(random: *std.Random, out: []u8) void {
    for (out) |*byte| {
        byte.* = 'a' + random.uintLessThan(u8, 26);
    }
}
