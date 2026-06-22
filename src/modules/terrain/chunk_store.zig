const std = @import("std");
const world = @import("../../world/mod.zig");
const authoring = @import("authoring.zig");

const region_dir = "layers/terrain/regions";
pub const region_size_cells = 16;
const region_magic = "FETRREG1\n";
const chunk_magic = "FETRCHK1";
const format_version: u16 = 1;
const max_region_bytes = 64 * 1024 * 1024;

pub fn regionPath(allocator: std.mem.Allocator, cell: world.cell.CellId) ![]u8 {
    const region = regionIdForCell(cell);
    const rx = region.x;
    const ry = region.y;
    return std.fmt.allocPrint(allocator, "{s}/region_{d}_{d}.fetr", .{ region_dir, rx, ry });
}

pub const RegionId = struct {
    x: i32,
    y: i32,

    pub fn eql(self: RegionId, other: RegionId) bool {
        return self.x == other.x and self.y == other.y;
    }
};

pub fn regionIdForCell(cell: world.cell.CellId) RegionId {
    return .{ .x = regionCoord(cell.x), .y = regionCoord(cell.y) };
}

pub fn regionMinCell(region: RegionId) world.cell.CellId {
    return .{ .x = region.x * region_size_cells, .y = region.y * region_size_cells, .z = 0 };
}

pub fn upsertTile(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    input: authoring.TerrainTileInput,
) ![]u8 {
    const path = try regionPath(allocator, input.cell);
    errdefer allocator.free(path);

    var project_dir = try openProjectDir(io, project_path);
    defer project_dir.close(io);
    if (std.fs.path.dirname(path)) |parent| try project_dir.createDirPath(io, parent);

    var file = try project_dir.createFile(io, path, .{ .read = true, .truncate = false });
    defer file.close(io);
    const file_len = try file.length(io);
    if (file_len == 0) {
        var write_buf: [8192]u8 = undefined;
        var file_writer = file.writer(io, &write_buf);
        try file_writer.interface.writeAll(region_magic);
        try writeChunkRecord(&file_writer.interface, input);
        try file_writer.interface.flush();
    } else {
        var header: [region_magic.len]u8 = undefined;
        const read_count = try file.readPositionalAll(io, &header, 0);
        if (read_count != header.len or !std.mem.eql(u8, &header, region_magic)) return error.InvalidTerrainRegion;
        var write_buf: [8192]u8 = undefined;
        var file_writer = file.writer(io, &write_buf);
        try file_writer.seekTo(file_len);
        try writeChunkRecord(&file_writer.interface, input);
        try file_writer.interface.flush();
    }
    return path;
}

pub fn loadTile(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    region_path: []const u8,
    cell: world.cell.CellId,
) !?authoring.TerrainAuthoringDoc {
    var project_dir = try openProjectDir(io, project_path);
    defer project_dir.close(io);
    const bytes = project_dir.readFileAlloc(io, region_path, allocator, .limited(max_region_bytes)) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer allocator.free(bytes);
    return parseLatestTile(allocator, bytes, cell);
}

pub fn loadRegion(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    region_path: []const u8,
) !authoring.TerrainAuthoringDoc {
    var project_dir = try openProjectDir(io, project_path);
    defer project_dir.close(io);
    const bytes = try project_dir.readFileAlloc(io, region_path, allocator, .limited(max_region_bytes));
    defer allocator.free(bytes);
    return parseLatestRegion(allocator, bytes);
}

pub fn loadRegionTiles(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    region_path: []const u8,
    cells: []const world.cell.CellId,
) !authoring.TerrainAuthoringDoc {
    var project_dir = try openProjectDir(io, project_path);
    defer project_dir.close(io);
    const bytes = try project_dir.readFileAlloc(io, region_path, allocator, .limited(max_region_bytes));
    defer allocator.free(bytes);
    return parseLatestRegionTiles(allocator, bytes, cells);
}

fn parseLatestRegion(allocator: std.mem.Allocator, bytes: []const u8) !authoring.TerrainAuthoringDoc {
    if (!std.mem.startsWith(u8, bytes, region_magic)) return error.InvalidTerrainRegion;
    var doc = authoring.TerrainAuthoringDoc.init(allocator);
    errdefer doc.deinit();
    var offset: usize = region_magic.len;
    while (offset < bytes.len) {
        var parsed = try readChunkRecord(allocator, bytes, &offset);
        defer parsed.deinit(allocator);
        try doc.upsertTile(.{
            .cell = parsed.id(),
            .size = parsed.size,
            .lod_levels = parsed.lod_levels,
            .heights = parsed.heights,
            .splat_size = parsed.splat_size,
            .splat = parsed.splat,
            .paint_layers = parsed.paint_layers,
            .paint_colors = parsed.paint_colors,
            .paint_albedo_textures = parsed.paint_albedo_textures,
            .paint_roughness_textures = parsed.paint_roughness_textures,
            .paint_specular_textures = parsed.paint_specular_textures,
            .paint_displacement_textures = parsed.paint_displacement_textures,
            .material = parsed.material,
        });
    }
    return doc;
}

fn parseLatestRegionTiles(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    cells: []const world.cell.CellId,
) !authoring.TerrainAuthoringDoc {
    if (!std.mem.startsWith(u8, bytes, region_magic)) return error.InvalidTerrainRegion;
    var doc = authoring.TerrainAuthoringDoc.init(allocator);
    errdefer doc.deinit();
    var offset: usize = region_magic.len;
    while (offset < bytes.len) {
        const parsed = try readChunkRecordIfWanted(allocator, bytes, &offset, cells);
        if (parsed) |tile_value| {
            var tile = tile_value;
            defer tile.deinit(allocator);
            try doc.upsertTile(.{
                .cell = tile.id(),
                .size = tile.size,
                .lod_levels = tile.lod_levels,
                .heights = tile.heights,
                .splat_size = tile.splat_size,
                .splat = tile.splat,
                .paint_layers = tile.paint_layers,
                .paint_colors = tile.paint_colors,
                .paint_albedo_textures = tile.paint_albedo_textures,
                .paint_roughness_textures = tile.paint_roughness_textures,
                .paint_specular_textures = tile.paint_specular_textures,
                .paint_displacement_textures = tile.paint_displacement_textures,
                .material = tile.material,
            });
        }
    }
    return doc;
}

fn parseLatestTile(allocator: std.mem.Allocator, bytes: []const u8, cell: world.cell.CellId) !?authoring.TerrainAuthoringDoc {
    if (!std.mem.startsWith(u8, bytes, region_magic)) return error.InvalidTerrainRegion;
    var offset: usize = region_magic.len;
    var latest: ?authoring.OwnedTerrainTile = null;
    errdefer if (latest) |*tile| tile.deinit(allocator);

    while (offset < bytes.len) {
        const parsed = try readChunkRecord(allocator, bytes, &offset);
        if (parsed.id().eql(cell)) {
            if (latest) |*tile| tile.deinit(allocator);
            latest = parsed;
        } else {
            var discard = parsed;
            discard.deinit(allocator);
        }
    }

    var tile = latest orelse return null;
    latest = null;
    defer tile.deinit(allocator);
    var doc = authoring.TerrainAuthoringDoc.init(allocator);
    errdefer doc.deinit();
    try doc.upsertTile(.{
        .cell = tile.id(),
        .size = tile.size,
        .lod_levels = tile.lod_levels,
        .heights = tile.heights,
        .splat_size = tile.splat_size,
        .splat = tile.splat,
        .paint_layers = tile.paint_layers,
        .paint_colors = tile.paint_colors,
        .paint_albedo_textures = tile.paint_albedo_textures,
        .paint_roughness_textures = tile.paint_roughness_textures,
        .paint_specular_textures = tile.paint_specular_textures,
        .paint_displacement_textures = tile.paint_displacement_textures,
        .material = tile.material,
    });
    return doc;
}

fn readChunkRecordIfWanted(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    offset: *usize,
    cells: []const world.cell.CellId,
) !?authoring.OwnedTerrainTile {
    try expectAvailable(bytes, offset.*, chunk_magic.len + 34);
    if (!std.mem.eql(u8, bytes[offset.*..][0..chunk_magic.len], chunk_magic)) return error.InvalidTerrainChunk;
    offset.* += chunk_magic.len;
    const version = readInt(u16, bytes, offset);
    if (version != format_version) return error.UnsupportedTerrainChunkVersion;
    const cell: world.cell.CellId = .{
        .x = readInt(i32, bytes, offset),
        .y = readInt(i32, bytes, offset),
        .z = readInt(i32, bytes, offset),
    };
    const size = readInt(u32, bytes, offset);
    const splat_size = readInt(u32, bytes, offset);
    const lod_count = readInt(u32, bytes, offset);
    const layer_count = readInt(u32, bytes, offset);
    const material_len = readInt(u32, bytes, offset);

    if (!cellWanted(cell, cells)) {
        try skipChunkRecordPayload(bytes, offset, size, splat_size, lod_count, layer_count, material_len);
        return null;
    }
    return try readChunkRecordPayload(allocator, bytes, offset, cell, size, splat_size, lod_count, layer_count, material_len);
}

fn writeChunkRecord(writer: *std.Io.Writer, input: authoring.TerrainTileInput) !void {
    try writer.writeAll(chunk_magic);
    var header: [34]u8 = undefined;
    std.mem.writeInt(u16, header[0..2], format_version, .little);
    std.mem.writeInt(i32, header[2..6], input.cell.x, .little);
    std.mem.writeInt(i32, header[6..10], input.cell.y, .little);
    std.mem.writeInt(i32, header[10..14], input.cell.z, .little);
    std.mem.writeInt(u32, header[14..18], input.size, .little);
    std.mem.writeInt(u32, header[18..22], input.splat_size, .little);
    std.mem.writeInt(u32, header[22..26], @intCast(input.lod_levels.len), .little);
    std.mem.writeInt(u32, header[26..30], @intCast(input.paint_layers.len), .little);
    std.mem.writeInt(u32, header[30..34], @intCast(input.material.len), .little);
    try writer.writeAll(&header);

    for (input.lod_levels) |lod| try writeU32(writer, lod);
    for (input.heights) |height| try writeF32(writer, height);
    try writer.writeAll(input.splat);
    for (input.paint_layers) |layer| try writeString(writer, layer);
    for (input.paint_colors) |color| try writer.writeAll(&color);
    for (input.paint_albedo_textures) |value| try writeString(writer, value);
    for (input.paint_roughness_textures) |value| try writeString(writer, value);
    for (input.paint_specular_textures) |value| try writeString(writer, value);
    for (input.paint_displacement_textures) |value| try writeString(writer, value);
    try writer.writeAll(input.material);
}

fn readChunkRecord(allocator: std.mem.Allocator, bytes: []const u8, offset: *usize) !authoring.OwnedTerrainTile {
    try expectAvailable(bytes, offset.*, chunk_magic.len + 34);
    if (!std.mem.eql(u8, bytes[offset.*..][0..chunk_magic.len], chunk_magic)) return error.InvalidTerrainChunk;
    offset.* += chunk_magic.len;
    const version = readInt(u16, bytes, offset);
    if (version != format_version) return error.UnsupportedTerrainChunkVersion;
    const cell: world.cell.CellId = .{
        .x = readInt(i32, bytes, offset),
        .y = readInt(i32, bytes, offset),
        .z = readInt(i32, bytes, offset),
    };
    const size = readInt(u32, bytes, offset);
    const splat_size = readInt(u32, bytes, offset);
    const lod_count = readInt(u32, bytes, offset);
    const layer_count = readInt(u32, bytes, offset);
    const material_len = readInt(u32, bytes, offset);

    return readChunkRecordPayload(allocator, bytes, offset, cell, size, splat_size, lod_count, layer_count, material_len);
}

fn readChunkRecordPayload(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    offset: *usize,
    cell: world.cell.CellId,
    size: u32,
    splat_size: u32,
    lod_count: u32,
    layer_count: u32,
    material_len: u32,
) !authoring.OwnedTerrainTile {
    const lod_levels = try allocator.alloc(u32, lod_count);
    errdefer allocator.free(lod_levels);
    for (lod_levels) |*lod| lod.* = readInt(u32, bytes, offset);

    const sample_count = @as(usize, size) * @as(usize, size);
    const heights = try allocator.alloc(f32, sample_count);
    errdefer allocator.free(heights);
    for (heights) |*height| height.* = readF32(bytes, offset);

    const splat_count = @as(usize, splat_size) * @as(usize, splat_size) * @as(usize, layer_count);
    try expectAvailable(bytes, offset.*, splat_count);
    const splat = try allocator.dupe(u8, bytes[offset.*..][0..splat_count]);
    errdefer allocator.free(splat);
    offset.* += splat_count;

    const paint_layers = try readStringList(allocator, bytes, offset, layer_count);
    errdefer freeStringList(allocator, paint_layers);

    const paint_colors = try allocator.alloc([4]u8, layer_count);
    errdefer allocator.free(paint_colors);
    for (paint_colors) |*color| {
        try expectAvailable(bytes, offset.*, 4);
        color.* = bytes[offset.*..][0..4].*;
        offset.* += 4;
    }

    const paint_albedo_textures = try readStringList(allocator, bytes, offset, layer_count);
    errdefer freeStringList(allocator, paint_albedo_textures);
    const paint_roughness_textures = try readStringList(allocator, bytes, offset, layer_count);
    errdefer freeStringList(allocator, paint_roughness_textures);
    const paint_specular_textures = try readStringList(allocator, bytes, offset, layer_count);
    errdefer freeStringList(allocator, paint_specular_textures);
    const paint_displacement_textures = try readStringList(allocator, bytes, offset, layer_count);
    errdefer freeStringList(allocator, paint_displacement_textures);

    try expectAvailable(bytes, offset.*, material_len);
    const material = try allocator.dupe(u8, bytes[offset.*..][0..material_len]);
    errdefer allocator.free(material);
    offset.* += material_len;

    return .{
        .cell = .{ cell.x, cell.y, cell.z },
        .size = size,
        .lod_levels = lod_levels,
        .heights = heights,
        .splat_size = splat_size,
        .splat = splat,
        .paint_layers = paint_layers,
        .paint_colors = paint_colors,
        .paint_albedo_textures = paint_albedo_textures,
        .paint_roughness_textures = paint_roughness_textures,
        .paint_specular_textures = paint_specular_textures,
        .paint_displacement_textures = paint_displacement_textures,
        .material = material,
    };
}

fn skipChunkRecordPayload(
    bytes: []const u8,
    offset: *usize,
    size: u32,
    splat_size: u32,
    lod_count: u32,
    layer_count: u32,
    material_len: u32,
) !void {
    try skipBytes(bytes, offset, @as(usize, lod_count) * @sizeOf(u32));
    try skipBytes(bytes, offset, @as(usize, size) * @as(usize, size) * @sizeOf(f32));
    try skipBytes(bytes, offset, @as(usize, splat_size) * @as(usize, splat_size) * @as(usize, layer_count));
    try skipStringList(bytes, offset, layer_count);
    try skipBytes(bytes, offset, @as(usize, layer_count) * 4);
    try skipStringList(bytes, offset, layer_count);
    try skipStringList(bytes, offset, layer_count);
    try skipStringList(bytes, offset, layer_count);
    try skipStringList(bytes, offset, layer_count);
    try skipBytes(bytes, offset, material_len);
}

fn cellWanted(cell: world.cell.CellId, cells: []const world.cell.CellId) bool {
    for (cells) |candidate| {
        if (candidate.eql(cell)) return true;
    }
    return false;
}

fn writeString(writer: *std.Io.Writer, value: []const u8) !void {
    try writeU32(writer, @intCast(value.len));
    try writer.writeAll(value);
}

fn readStringList(allocator: std.mem.Allocator, bytes: []const u8, offset: *usize, count: u32) ![][]u8 {
    const strings = try allocator.alloc([]u8, count);
    errdefer allocator.free(strings);
    var written: usize = 0;
    errdefer {
        for (strings[0..written]) |value| allocator.free(value);
    }
    for (strings) |*value| {
        const len = readInt(u32, bytes, offset);
        try expectAvailable(bytes, offset.*, len);
        value.* = try allocator.dupe(u8, bytes[offset.*..][0..len]);
        offset.* += len;
        written += 1;
    }
    return strings;
}

fn skipStringList(bytes: []const u8, offset: *usize, count: u32) !void {
    var index: u32 = 0;
    while (index < count) : (index += 1) {
        const len = readInt(u32, bytes, offset);
        try skipBytes(bytes, offset, len);
    }
}

fn skipBytes(bytes: []const u8, offset: *usize, count: usize) !void {
    try expectAvailable(bytes, offset.*, count);
    offset.* += count;
}

fn freeStringList(allocator: std.mem.Allocator, strings: [][]u8) void {
    for (strings) |value| allocator.free(value);
    allocator.free(strings);
}

fn writeU32(writer: *std.Io.Writer, value: u32) !void {
    var buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &buf, value, .little);
    try writer.writeAll(&buf);
}

fn writeF32(writer: *std.Io.Writer, value: f32) !void {
    var buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &buf, @bitCast(value), .little);
    try writer.writeAll(&buf);
}

fn readInt(comptime T: type, bytes: []const u8, offset: *usize) T {
    const size = @sizeOf(T);
    std.debug.assert(offset.* + size <= bytes.len);
    const value = std.mem.readInt(T, bytes[offset.*..][0..size], .little);
    offset.* += size;
    return value;
}

fn readF32(bytes: []const u8, offset: *usize) f32 {
    const bits = readInt(u32, bytes, offset);
    return @bitCast(bits);
}

fn expectAvailable(bytes: []const u8, offset: usize, count: usize) !void {
    if (offset > bytes.len or bytes.len - offset < count) return error.InvalidTerrainChunk;
}

fn regionCoord(coord: i32) i32 {
    return @divFloor(coord, region_size_cells);
}

fn openProjectDir(io: std.Io, project_path: []const u8) !std.Io.Dir {
    if (std.fs.path.isAbsolute(project_path)) return std.Io.Dir.openDirAbsolute(io, project_path, .{});
    return std.Io.Dir.cwd().openDir(io, project_path, .{});
}

const test_paint_layers = [_][]const u8{ "base", "detail" };
const test_paint_colors = [_][4]u8{ .{ 32, 96, 32, 255 }, .{ 120, 96, 64, 255 } };
const test_paint_textures = [_][]const u8{ "", "" };
const test_splat_2 = [_]u8{ 255, 0, 255, 0, 255, 0, 255, 0 };

test "terrain chunk store appends and loads latest tile" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);

    const cell: world.cell.CellId = .{ .x = 2, .y = -1, .z = 0 };
    const path = try upsertTile(std.testing.allocator, std.testing.io, project_path, .{
        .cell = cell,
        .size = 2,
        .lod_levels = &.{ 2, 2 },
        .heights = &.{ 0, 1, 2, 3 },
        .splat_size = 2,
        .splat = &test_splat_2,
        .paint_layers = &test_paint_layers,
        .paint_colors = &test_paint_colors,
        .paint_albedo_textures = &test_paint_textures,
        .paint_roughness_textures = &test_paint_textures,
        .paint_specular_textures = &test_paint_textures,
        .paint_displacement_textures = &test_paint_textures,
        .material = "grass",
    });
    defer std.testing.allocator.free(path);
    _ = try upsertTile(std.testing.allocator, std.testing.io, project_path, .{
        .cell = cell,
        .size = 2,
        .lod_levels = &.{ 2, 2 },
        .heights = &.{ 4, 5, 6, 7 },
        .splat_size = 2,
        .splat = &test_splat_2,
        .paint_layers = &test_paint_layers,
        .paint_colors = &test_paint_colors,
        .paint_albedo_textures = &test_paint_textures,
        .paint_roughness_textures = &test_paint_textures,
        .paint_specular_textures = &test_paint_textures,
        .paint_displacement_textures = &test_paint_textures,
        .material = "mud",
    });

    var doc = (try loadTile(std.testing.allocator, std.testing.io, project_path, path, cell)).?;
    defer doc.deinit();
    try std.testing.expectEqual(@as(usize, 1), doc.tiles.items.len);
    try std.testing.expectEqual(@as(f32, 4), doc.tiles.items[0].heights[0]);
    try std.testing.expectEqualStrings("mud", doc.tiles.items[0].material);
}
