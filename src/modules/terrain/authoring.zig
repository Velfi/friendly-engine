const std = @import("std");
const kdl = @import("kdl");
const world = @import("../../world/mod.zig");
const layer_kdl = @import("../layer_kdl.zig");
const chunk_store = @import("chunk_store.zig");

const terrain_layer_dir = "layers/terrain";
const terrain_index_file = "layers/terrain/index.kdl";
const max_terrain_doc_bytes = 8 * 1024 * 1024;

pub const TerrainTileInput = struct {
    cell: world.cell.CellId,
    size: u32,
    lod_levels: []const u32,
    heights: []const f32,
    splat_size: u32,
    splat: []const u8,
    paint_layers: []const []const u8,
    paint_colors: []const [4]u8,
    paint_albedo_textures: []const []const u8,
    paint_roughness_textures: []const []const u8,
    paint_specular_textures: []const []const u8,
    paint_displacement_textures: []const []const u8,
    material: []const u8 = "terrain.default",
};

pub const OwnedTerrainTile = struct {
    cell: [3]i32,
    size: u32,
    lod_levels: []u32,
    heights: []f32,
    splat_size: u32,
    splat: []u8,
    paint_layers: [][]u8,
    paint_colors: [][4]u8,
    paint_albedo_textures: [][]u8,
    paint_roughness_textures: [][]u8,
    paint_specular_textures: [][]u8,
    paint_displacement_textures: [][]u8,
    material: []u8,

    fn init(allocator: std.mem.Allocator, input: TerrainTileInput) !OwnedTerrainTile {
        try validateTileInput(input);
        const lod_levels = try allocator.dupe(u32, input.lod_levels);
        errdefer allocator.free(lod_levels);
        const heights = try allocator.dupe(f32, input.heights);
        errdefer allocator.free(heights);
        const splat = try allocator.dupe(u8, input.splat);
        errdefer allocator.free(splat);
        const paint_layers = try dupePaintLayers(allocator, input.paint_layers);
        errdefer freePaintLayers(allocator, paint_layers);
        const paint_colors = try allocator.dupe([4]u8, input.paint_colors);
        errdefer allocator.free(paint_colors);
        const paint_albedo_textures = try dupePaintLayers(allocator, input.paint_albedo_textures);
        errdefer freePaintLayers(allocator, paint_albedo_textures);
        const paint_roughness_textures = try dupePaintLayers(allocator, input.paint_roughness_textures);
        errdefer freePaintLayers(allocator, paint_roughness_textures);
        const paint_specular_textures = try dupePaintLayers(allocator, input.paint_specular_textures);
        errdefer freePaintLayers(allocator, paint_specular_textures);
        const paint_displacement_textures = try dupePaintLayers(allocator, input.paint_displacement_textures);
        errdefer freePaintLayers(allocator, paint_displacement_textures);
        const material = try allocator.dupe(u8, input.material);
        errdefer allocator.free(material);
        return .{
            .cell = .{ input.cell.x, input.cell.y, input.cell.z },
            .size = input.size,
            .lod_levels = lod_levels,
            .heights = heights,
            .splat_size = input.splat_size,
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

    pub fn deinit(self: *OwnedTerrainTile, allocator: std.mem.Allocator) void {
        allocator.free(self.lod_levels);
        allocator.free(self.heights);
        allocator.free(self.splat);
        freePaintLayers(allocator, self.paint_layers);
        allocator.free(self.paint_colors);
        freePaintLayers(allocator, self.paint_albedo_textures);
        freePaintLayers(allocator, self.paint_roughness_textures);
        freePaintLayers(allocator, self.paint_specular_textures);
        freePaintLayers(allocator, self.paint_displacement_textures);
        allocator.free(self.material);
    }

    fn sameCell(self: OwnedTerrainTile, cell: world.cell.CellId) bool {
        return self.cell[0] == cell.x and self.cell[1] == cell.y and self.cell[2] == cell.z;
    }

    pub fn id(self: OwnedTerrainTile) world.cell.CellId {
        return .{ .x = self.cell[0], .y = self.cell[1], .z = self.cell[2] };
    }
};

pub const TerrainIndexEntry = struct {
    cell: world.cell.CellId,
    path: []u8,
};

pub const TerrainIndex = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayList(TerrainIndexEntry),

    pub fn init(allocator: std.mem.Allocator) TerrainIndex {
        return .{ .allocator = allocator, .entries = .empty };
    }

    pub fn deinit(self: *TerrainIndex) void {
        for (self.entries.items) |entry| self.allocator.free(entry.path);
        self.entries.deinit(self.allocator);
    }

    pub fn findPath(self: TerrainIndex, cell: world.cell.CellId) ?[]const u8 {
        for (self.entries.items) |entry| {
            if (entry.cell.eql(cell)) return entry.path;
        }
        return null;
    }

    pub fn upsert(self: *TerrainIndex, cell: world.cell.CellId, path: []const u8) !void {
        for (self.entries.items) |*entry| {
            if (!entry.cell.eql(cell)) continue;
            const copy = try self.allocator.dupe(u8, path);
            self.allocator.free(entry.path);
            entry.path = copy;
            return;
        }
        try self.entries.append(self.allocator, .{
            .cell = cell,
            .path = try self.allocator.dupe(u8, path),
        });
    }

    pub fn remove(self: *TerrainIndex, cell: world.cell.CellId) ?[]u8 {
        for (self.entries.items, 0..) |entry, index| {
            if (!entry.cell.eql(cell)) continue;
            const removed = self.entries.orderedRemove(index);
            return removed.path;
        }
        return null;
    }
};

pub const TerrainAuthoringDoc = struct {
    allocator: std.mem.Allocator,
    tiles: std.ArrayList(OwnedTerrainTile),

    pub fn init(allocator: std.mem.Allocator) TerrainAuthoringDoc {
        return .{ .allocator = allocator, .tiles = .empty };
    }

    pub fn deinit(self: *TerrainAuthoringDoc) void {
        for (self.tiles.items) |*tile| tile.deinit(self.allocator);
        self.tiles.deinit(self.allocator);
    }

    pub fn upsertTile(self: *TerrainAuthoringDoc, input: TerrainTileInput) !void {
        var owned = try OwnedTerrainTile.init(self.allocator, input);
        errdefer owned.deinit(self.allocator);
        for (self.tiles.items) |*tile| {
            if (!tile.sameCell(input.cell)) continue;
            tile.deinit(self.allocator);
            tile.* = owned;
            return;
        }
        try self.tiles.append(self.allocator, owned);
    }

    pub fn deleteTile(self: *TerrainAuthoringDoc, cell_id: world.cell.CellId) bool {
        for (self.tiles.items, 0..) |tile, index| {
            if (!tile.sameCell(cell_id)) continue;
            var removed = self.tiles.orderedRemove(index);
            removed.deinit(self.allocator);
            return true;
        }
        return false;
    }
};

pub const SeamValidationReport = struct {
    seam_count: usize = 0,
    incompatible_seams: usize = 0,
    mismatched_seams: usize = 0,
    max_delta: f32 = 0,
};

pub fn load(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    manifest_path: []const u8,
) !TerrainAuthoringDoc {
    var index = try loadIndex(allocator, io, project_path, manifest_path);
    defer index.deinit();
    var doc = TerrainAuthoringDoc.init(allocator);
    errdefer doc.deinit();
    for (index.entries.items) |entry| {
        var tile_doc = (try loadCell(allocator, io, project_path, manifest_path, entry.cell)) orelse return error.TerrainTileNotFound;
        defer tile_doc.deinit();
        if (tile_doc.tiles.items.len != 1) return error.InvalidTerrainDocument;
        if (!tile_doc.tiles.items[0].id().eql(entry.cell)) return error.InvalidTerrainDocument;
        try doc.upsertTile(try tileInputFromOwned(tile_doc.tiles.items[0]));
    }
    return doc;
}

pub fn save(
    doc: TerrainAuthoringDoc,
    io: std.Io,
    project_path: []const u8,
    manifest_path: []const u8,
) !void {
    var project_dir = try openProjectDir(io, project_path);
    defer project_dir.close(io);

    var index = TerrainIndex.init(doc.allocator);
    defer index.deinit();
    for (doc.tiles.items) |tile| {
        const path = try tilePath(doc.allocator, tile.id());
        defer doc.allocator.free(path);
        try writeSingleTile(doc.allocator, io, &project_dir, path, tile);
        try index.upsert(tile.id(), path);
    }
    try saveIndex(doc.allocator, io, project_path, manifest_path, index);
}

pub fn upsertTileFile(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    manifest_path: []const u8,
    input: TerrainTileInput,
) !void {
    var index = try loadIndex(allocator, io, project_path, manifest_path);
    defer index.deinit();
    const path = try chunk_store.upsertTile(allocator, io, project_path, input);
    defer allocator.free(path);
    try index.upsert(input.cell, path);
    try saveIndex(allocator, io, project_path, manifest_path, index);
}

pub fn deleteTileFile(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    manifest_path: []const u8,
    cell_id: world.cell.CellId,
) !bool {
    var index = try loadIndex(allocator, io, project_path, manifest_path);
    defer index.deinit();
    const removed_path = index.remove(cell_id) orelse return false;
    defer allocator.free(removed_path);
    var project_dir = try openProjectDir(io, project_path);
    defer project_dir.close(io);
    project_dir.deleteFile(io, removed_path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };
    try saveIndex(allocator, io, project_path, manifest_path, index);
    return true;
}

pub fn loadIndex(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    manifest_path: []const u8,
) !TerrainIndex {
    const path = try indexPath(allocator, manifest_path);
    defer allocator.free(path);
    var project_dir = try openProjectDir(io, project_path);
    defer project_dir.close(io);
    const bytes = project_dir.readFileAlloc(io, path, allocator, .limited(max_terrain_doc_bytes)) catch |err| switch (err) {
        error.FileNotFound => return TerrainIndex.init(allocator),
        else => return err,
    };
    defer allocator.free(bytes);
    return parseIndexKdl(allocator, bytes);
}

pub fn saveIndex(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    manifest_path: []const u8,
    index: TerrainIndex,
) !void {
    const path = try indexPath(allocator, manifest_path);
    defer allocator.free(path);
    var project_dir = try openProjectDir(io, project_path);
    defer project_dir.close(io);
    if (std.fs.path.dirname(path)) |parent| try project_dir.createDirPath(io, parent);
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    try writeIndexKdl(&out.writer, index);
    const bytes = try out.toOwnedSlice();
    defer allocator.free(bytes);
    try project_dir.writeFile(io, .{ .sub_path = path, .data = bytes });
}

pub fn loadCell(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    manifest_path: []const u8,
    cell_id: world.cell.CellId,
) !?TerrainAuthoringDoc {
    var index = try loadIndex(allocator, io, project_path, manifest_path);
    defer index.deinit();
    const path = index.findPath(cell_id) orelse return null;
    if (isRegionPath(path)) {
        return chunk_store.loadTile(allocator, io, project_path, path, cell_id);
    }
    var project_dir = try openProjectDir(io, project_path);
    defer project_dir.close(io);
    var doc = try loadTileDocFromPath(allocator, io, &project_dir, path);
    errdefer doc.deinit();
    if (doc.tiles.items.len != 1) return error.InvalidTerrainDocument;
    if (!doc.tiles.items[0].id().eql(cell_id)) return error.InvalidTerrainDocument;
    return doc;
}

pub fn validateSeamsFile(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    manifest_path: []const u8,
) !SeamValidationReport {
    var doc = try load(allocator, io, project_path, manifest_path);
    defer doc.deinit();
    return validateSeams(doc);
}

fn validateSeams(doc: TerrainAuthoringDoc) SeamValidationReport {
    var report = SeamValidationReport{};
    visitAdjacentTiles(doc, &report);
    return report;
}

fn visitAdjacentTiles(doc: TerrainAuthoringDoc, report: *SeamValidationReport) void {
    for (doc.tiles.items, 0..) |*tile, index| {
        for (doc.tiles.items[index + 1 ..]) |*other| {
            const dx = other.cell[0] - tile.cell[0];
            const dy = other.cell[1] - tile.cell[1];
            const dz = other.cell[2] - tile.cell[2];
            if (dz != 0) continue;
            if (dy == 0 and @abs(dx) == 1) {
                if (dx == 1) {
                    compareX(tile, other, report);
                } else {
                    compareX(other, tile, report);
                }
            } else if (dx == 0 and @abs(dy) == 1) {
                if (dy == 1) {
                    compareY(tile, other, report);
                } else {
                    compareY(other, tile, report);
                }
            }
        }
    }
}

fn compareX(left: *OwnedTerrainTile, right: *OwnedTerrainTile, report: *SeamValidationReport) void {
    report.seam_count += 1;
    if (left.size != right.size) {
        report.incompatible_seams += 1;
        return;
    }
    const size: usize = @intCast(left.size);
    var mismatched = false;
    var row: usize = 0;
    while (row < size) : (row += 1) {
        const li = row * size + (size - 1);
        const ri = row * size;
        const delta = @abs(left.heights[li] - right.heights[ri]);
        report.max_delta = @max(report.max_delta, delta);
        if (delta != 0) mismatched = true;
    }
    if (mismatched) report.mismatched_seams += 1;
}

fn compareY(south: *OwnedTerrainTile, north: *OwnedTerrainTile, report: *SeamValidationReport) void {
    report.seam_count += 1;
    if (south.size != north.size) {
        report.incompatible_seams += 1;
        return;
    }
    const size: usize = @intCast(south.size);
    var mismatched = false;
    var col: usize = 0;
    while (col < size) : (col += 1) {
        const si = (size - 1) * size + col;
        const ni = col;
        const delta = @abs(south.heights[si] - north.heights[ni]);
        report.max_delta = @max(report.max_delta, delta);
        if (delta != 0) mismatched = true;
    }
    if (mismatched) report.mismatched_seams += 1;
}

fn validateTileInput(input: TerrainTileInput) !void {
    if (input.size < 2) return error.InvalidTerrainTile;
    if (input.material.len == 0) return error.InvalidTerrainTile;
    if (input.lod_levels.len < 2) return error.InvalidTerrainTile;
    for (input.lod_levels) |lod| {
        if (lod < 2 or lod > input.size) return error.InvalidTerrainTile;
    }
    const sample_count = @as(usize, input.size) * @as(usize, input.size);
    if (input.heights.len != sample_count) return error.InvalidTerrainHeightCount;
    for (input.heights) |height| {
        if (!std.math.isFinite(height)) return error.InvalidTerrainHeight;
    }
    if (input.paint_layers.len < 2 or input.paint_layers.len != input.paint_colors.len) return error.InvalidTerrainPaintLayers;
    if (input.paint_albedo_textures.len != input.paint_layers.len or
        input.paint_roughness_textures.len != input.paint_layers.len or
        input.paint_specular_textures.len != input.paint_layers.len or
        input.paint_displacement_textures.len != input.paint_layers.len) return error.InvalidTerrainPaintLayers;
    for (input.paint_layers, 0..) |layer, index| {
        if (layer.len == 0) return error.InvalidTerrainPaintLayers;
        for (input.paint_layers[index + 1 ..]) |other| {
            if (std.mem.eql(u8, layer, other)) return error.InvalidTerrainPaintLayers;
        }
    }
    const paint_sample_count = @as(usize, input.splat_size) * @as(usize, input.splat_size);
    if (input.splat_size < 2 or input.splat.len != paint_sample_count * input.paint_layers.len) return error.InvalidTerrainSplatCount;
}

fn dupePaintLayers(allocator: std.mem.Allocator, layers: []const []const u8) ![][]u8 {
    const owned = try allocator.alloc([]u8, layers.len);
    errdefer allocator.free(owned);
    var written: usize = 0;
    errdefer {
        for (owned[0..written]) |layer| allocator.free(layer);
    }
    for (layers, 0..) |layer, index| {
        owned[index] = try allocator.dupe(u8, layer);
        written += 1;
    }
    return owned;
}

fn freePaintLayers(allocator: std.mem.Allocator, layers: [][]u8) void {
    for (layers) |layer| allocator.free(layer);
    allocator.free(layers);
}

const TileBuilder = struct {
    cell: ?world.cell.CellId = null,
    size: ?u32 = null,
    lod_levels: ?[]u32 = null,
    heights: ?[]f32 = null,
    splat_size: ?u32 = null,
    splat: ?[]u8 = null,
    paint_layers: ?[][]u8 = null,
    paint_colors: ?[][4]u8 = null,
    paint_albedo_textures: ?[][]u8 = null,
    paint_roughness_textures: ?[][]u8 = null,
    paint_specular_textures: ?[][]u8 = null,
    paint_displacement_textures: ?[][]u8 = null,
    material: ?[]u8 = null,

    fn deinit(self: *TileBuilder, allocator: std.mem.Allocator) void {
        if (self.lod_levels) |value| allocator.free(value);
        if (self.heights) |value| allocator.free(value);
        if (self.splat) |value| allocator.free(value);
        if (self.paint_layers) |value| freePaintLayers(allocator, value);
        if (self.paint_colors) |value| allocator.free(value);
        if (self.paint_albedo_textures) |value| freePaintLayers(allocator, value);
        if (self.paint_roughness_textures) |value| freePaintLayers(allocator, value);
        if (self.paint_specular_textures) |value| freePaintLayers(allocator, value);
        if (self.paint_displacement_textures) |value| freePaintLayers(allocator, value);
        if (self.material) |value| allocator.free(value);
        self.* = .{};
    }

    fn apply(self: *TileBuilder, allocator: std.mem.Allocator, key: []const u8, value: []const u8) !void {
        if (std.mem.eql(u8, key, "cell")) {
            const parsed = try layer_kdl.parseI32Triple(value);
            self.cell = .{ .x = parsed[0], .y = parsed[1], .z = parsed[2] };
        } else if (std.mem.eql(u8, key, "size")) self.size = try std.fmt.parseInt(u32, value, 10) else if (std.mem.eql(u8, key, "lod_levels")) {
            if (self.lod_levels) |existing| allocator.free(existing);
            self.lod_levels = try layer_kdl.parseU32List(allocator, value);
        } else if (std.mem.eql(u8, key, "heights")) {
            if (self.heights) |existing| allocator.free(existing);
            self.heights = try layer_kdl.parseF32List(allocator, value);
        } else if (std.mem.eql(u8, key, "splat_size")) self.splat_size = try std.fmt.parseInt(u32, value, 10) else if (std.mem.eql(u8, key, "splat")) {
            if (self.splat) |existing| allocator.free(existing);
            self.splat = try layer_kdl.parseU8List(allocator, value);
        } else if (std.mem.eql(u8, key, "paint_layers")) {
            if (self.paint_layers) |existing| freePaintLayers(allocator, existing);
            self.paint_layers = try layer_kdl.parseStringList(allocator, value);
        } else if (std.mem.eql(u8, key, "paint_colors")) {
            if (self.paint_colors) |existing| allocator.free(existing);
            self.paint_colors = try layer_kdl.parseU8QuadList(allocator, value);
        } else if (std.mem.eql(u8, key, "paint_albedo_textures")) {
            if (self.paint_albedo_textures) |existing| freePaintLayers(allocator, existing);
            self.paint_albedo_textures = try layer_kdl.parseStringList(allocator, value);
        } else if (std.mem.eql(u8, key, "paint_roughness_textures")) {
            if (self.paint_roughness_textures) |existing| freePaintLayers(allocator, existing);
            self.paint_roughness_textures = try layer_kdl.parseStringList(allocator, value);
        } else if (std.mem.eql(u8, key, "paint_specular_textures")) {
            if (self.paint_specular_textures) |existing| freePaintLayers(allocator, existing);
            self.paint_specular_textures = try layer_kdl.parseStringList(allocator, value);
        } else if (std.mem.eql(u8, key, "paint_displacement_textures")) {
            if (self.paint_displacement_textures) |existing| freePaintLayers(allocator, existing);
            self.paint_displacement_textures = try layer_kdl.parseStringList(allocator, value);
        } else if (std.mem.eql(u8, key, "material")) {
            if (self.material) |existing| allocator.free(existing);
            self.material = try allocator.dupe(u8, value);
        } else return error.UnknownField;
    }
};

fn appendBuilder(allocator: std.mem.Allocator, doc: *TerrainAuthoringDoc, builder: *TileBuilder) !void {
    const input = TerrainTileInput{
        .cell = builder.cell orelse return error.InvalidTerrainDocument,
        .size = builder.size orelse return error.InvalidTerrainDocument,
        .lod_levels = builder.lod_levels orelse return error.InvalidTerrainDocument,
        .heights = builder.heights orelse return error.InvalidTerrainDocument,
        .splat_size = builder.splat_size orelse return error.InvalidTerrainDocument,
        .splat = builder.splat orelse return error.InvalidTerrainDocument,
        .paint_layers = builder.paint_layers orelse return error.InvalidTerrainDocument,
        .paint_colors = builder.paint_colors orelse return error.InvalidTerrainDocument,
        .paint_albedo_textures = builder.paint_albedo_textures orelse return error.InvalidTerrainDocument,
        .paint_roughness_textures = builder.paint_roughness_textures orelse return error.InvalidTerrainDocument,
        .paint_specular_textures = builder.paint_specular_textures orelse return error.InvalidTerrainDocument,
        .paint_displacement_textures = builder.paint_displacement_textures orelse return error.InvalidTerrainDocument,
        .material = builder.material orelse "terrain.default",
    };
    defer builder.deinit(allocator);
    try doc.upsertTile(input);
}

fn parseDocKdl(allocator: std.mem.Allocator, bytes: []const u8) !TerrainAuthoringDoc {
    const buffer = try allocator.allocSentinel(u8, bytes.len, 0);
    defer allocator.free(buffer);
    @memcpy(buffer, bytes);

    var parser = kdl.Parser.init(buffer);
    var doc = TerrainAuthoringDoc.init(allocator);
    errdefer doc.deinit();

    var depth: i32 = 0;
    var root_seen = false;
    var builder: ?TileBuilder = null;
    errdefer if (builder) |*tile| tile.deinit(allocator);

    while (true) {
        const event = try parser.next();
        switch (event) {
            .node => |node| {
                if (depth == 0) {
                    if (root_seen or !std.mem.eql(u8, node.val, "terrain")) return error.InvalidTerrainDocument;
                    root_seen = true;
                    continue;
                }
                if (depth == 1) {
                    if (!std.mem.eql(u8, node.val, "tile")) return error.UnknownField;
                    if (builder) |*tile| try appendBuilder(allocator, &doc, tile);
                    builder = .{};
                    continue;
                }
                return error.InvalidTerrainDocument;
            },
            .prop => |prop| {
                const value = try layer_kdl.decodeValue(allocator, prop.val);
                defer allocator.free(value);
                if (depth == 0) {
                    if (!std.mem.eql(u8, prop.key, "version")) return error.UnknownField;
                    if (try std.fmt.parseInt(u32, value, 10) != 1) return error.UnsupportedTerrainSchemaVersion;
                    continue;
                }
                if (depth == 1) {
                    var tile = &(builder orelse return error.InvalidTerrainDocument);
                    try tile.apply(allocator, prop.key, value);
                    continue;
                }
                return error.InvalidTerrainDocument;
            },
            .child_block_begin => depth += 1,
            .child_block_end => {
                if (depth == 1) {
                    if (builder) |*tile| {
                        try appendBuilder(allocator, &doc, tile);
                        builder = null;
                    }
                }
                depth -= 1;
                if (depth < 0) return error.InvalidTerrainDocument;
            },
            .arg, .invalid => return error.InvalidTerrainDocument,
            .eof => break,
        }
    }
    if (builder) |*tile| try appendBuilder(allocator, &doc, tile);
    if (!root_seen or depth != 0) return error.InvalidTerrainDocument;
    return doc;
}

fn writeDocKdl(writer: *std.Io.Writer, doc: TerrainAuthoringDoc) !void {
    try writer.writeAll("terrain version=1 {\n");
    for (doc.tiles.items) |tile| {
        try writer.print("  tile cell=\"{d},{d},{d}\" size={d} lod_levels=\"", .{ tile.cell[0], tile.cell[1], tile.cell[2], tile.size });
        try layer_kdl.writeU32List(writer, tile.lod_levels);
        try writer.writeAll("\" heights=\"");
        try layer_kdl.writeF32List(writer, tile.heights);
        try writer.print("\" splat_size={d} paint_layers=\"", .{tile.splat_size});
        try layer_kdl.writeStringList(writer, tile.paint_layers);
        try writer.writeAll("\" paint_colors=\"");
        try layer_kdl.writeU8QuadList(writer, tile.paint_colors);
        try writer.writeAll("\" paint_albedo_textures=\"");
        try layer_kdl.writeStringList(writer, tile.paint_albedo_textures);
        try writer.writeAll("\" paint_roughness_textures=\"");
        try layer_kdl.writeStringList(writer, tile.paint_roughness_textures);
        try writer.writeAll("\" paint_specular_textures=\"");
        try layer_kdl.writeStringList(writer, tile.paint_specular_textures);
        try writer.writeAll("\" paint_displacement_textures=\"");
        try layer_kdl.writeStringList(writer, tile.paint_displacement_textures);
        try writer.writeAll("\" splat=\"");
        try layer_kdl.writeU8List(writer, tile.splat);
        try writer.print("\" material=\"{s}\"\n", .{tile.material});
    }
    try writer.writeAll("}\n");
}

fn tileInputFromOwned(tile: OwnedTerrainTile) !TerrainTileInput {
    return .{
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
    };
}

fn loadTileDocFromPath(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_dir: *std.Io.Dir,
    path: []const u8,
) !TerrainAuthoringDoc {
    const bytes = try project_dir.readFileAlloc(io, path, allocator, .limited(max_terrain_doc_bytes));
    defer allocator.free(bytes);
    return parseDocKdl(allocator, bytes);
}

fn writeSingleTile(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_dir: *std.Io.Dir,
    path: []const u8,
    tile: OwnedTerrainTile,
) !void {
    if (std.fs.path.dirname(path)) |parent| try project_dir.createDirPath(io, parent);
    var doc = TerrainAuthoringDoc.init(allocator);
    defer doc.deinit();
    try doc.upsertTile(try tileInputFromOwned(tile));
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    try writeDocKdl(&out.writer, doc);
    const bytes = try out.toOwnedSlice();
    defer allocator.free(bytes);
    try project_dir.writeFile(io, .{ .sub_path = path, .data = bytes });
}

fn indexPath(allocator: std.mem.Allocator, manifest_path: []const u8) ![]u8 {
    const dir = std.fs.path.dirname(manifest_path) orelse "";
    if (dir.len == 0) return allocator.dupe(u8, terrain_index_file);
    return std.fs.path.join(allocator, &.{ dir, terrain_index_file });
}

pub fn tilePath(allocator: std.mem.Allocator, cell_id: world.cell.CellId) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}/cell_{d}_{d}_{d}.kdl", .{
        terrain_layer_dir,
        cell_id.x,
        cell_id.y,
        cell_id.z,
    });
}

fn parseIndexKdl(allocator: std.mem.Allocator, bytes: []const u8) !TerrainIndex {
    const buffer = try allocator.allocSentinel(u8, bytes.len, 0);
    defer allocator.free(buffer);
    @memcpy(buffer, bytes);

    var parser = kdl.Parser.init(buffer);
    var index = TerrainIndex.init(allocator);
    errdefer index.deinit();

    var depth: i32 = 0;
    var root_seen = false;
    var cell: ?world.cell.CellId = null;
    var path: ?[]u8 = null;
    errdefer if (path) |owned| allocator.free(owned);

    while (true) {
        const event = try parser.next();
        switch (event) {
            .node => |node| {
                if (depth == 0) {
                    if (root_seen or !std.mem.eql(u8, node.val, "terrain_index")) return error.InvalidTerrainIndex;
                    root_seen = true;
                    continue;
                }
                if (depth == 1) {
                    if (!std.mem.eql(u8, node.val, "tile")) return error.UnknownField;
                    if (cell) |id| {
                        const owned_path = path orelse return error.InvalidTerrainIndex;
                        try index.upsert(id, owned_path);
                        allocator.free(owned_path);
                        cell = null;
                        path = null;
                    }
                    continue;
                }
                return error.InvalidTerrainIndex;
            },
            .prop => |prop| {
                const value = try layer_kdl.decodeValue(allocator, prop.val);
                defer allocator.free(value);
                if (depth == 0) {
                    if (!std.mem.eql(u8, prop.key, "version")) return error.UnknownField;
                    if (try std.fmt.parseInt(u32, value, 10) != 1) return error.UnsupportedTerrainSchemaVersion;
                    continue;
                }
                if (depth == 1) {
                    if (std.mem.eql(u8, prop.key, "cell")) {
                        const parsed = try layer_kdl.parseI32Triple(value);
                        cell = .{ .x = parsed[0], .y = parsed[1], .z = parsed[2] };
                    } else if (std.mem.eql(u8, prop.key, "path")) {
                        if (path) |owned| allocator.free(owned);
                        path = try allocator.dupe(u8, value);
                    } else return error.UnknownField;
                    continue;
                }
                return error.InvalidTerrainIndex;
            },
            .child_block_begin => depth += 1,
            .child_block_end => {
                if (depth == 1) {
                    if (cell) |id| {
                        const owned_path = path orelse return error.InvalidTerrainIndex;
                        try index.upsert(id, owned_path);
                        allocator.free(owned_path);
                        cell = null;
                        path = null;
                    }
                }
                depth -= 1;
                if (depth < 0) return error.InvalidTerrainIndex;
            },
            .arg, .invalid => return error.InvalidTerrainIndex,
            .eof => break,
        }
    }
    if (cell) |id| {
        const owned_path = path orelse return error.InvalidTerrainIndex;
        try index.upsert(id, owned_path);
        allocator.free(owned_path);
        path = null;
    }
    if (!root_seen or depth != 0) return error.InvalidTerrainIndex;
    return index;
}

fn writeIndexKdl(writer: *std.Io.Writer, index: TerrainIndex) !void {
    try writer.writeAll("terrain_index version=1 {\n");
    for (index.entries.items) |entry| {
        try writer.print("  tile cell=\"{d},{d},{d}\" path=\"{s}\"\n", .{ entry.cell.x, entry.cell.y, entry.cell.z, entry.path });
    }
    try writer.writeAll("}\n");
}

fn openProjectDir(io: std.Io, project_path: []const u8) !std.Io.Dir {
    if (std.fs.path.isAbsolute(project_path)) return std.Io.Dir.openDirAbsolute(io, project_path, .{});
    return std.Io.Dir.cwd().openDir(io, project_path, .{});
}

fn isRegionPath(path: []const u8) bool {
    return std.mem.endsWith(u8, path, ".fetr");
}

const test_paint_layers = [_][]const u8{ "base", "detail" };
const test_paint_colors = [_][4]u8{ .{ 32, 96, 32, 255 }, .{ 120, 96, 64, 255 } };
const test_paint_textures = [_][]const u8{ "", "" };
const test_splat_2 = [_]u8{ 255, 0, 255, 0, 255, 0, 255, 0 };

test "terrain authoring upserts tile file and preserves KDL schema" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);

    try upsertTileFile(std.testing.allocator, std.testing.io, project_path, "world.kdl", .{
        .cell = .{ .x = 2, .y = -1, .z = 0 },
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

    var doc = try load(std.testing.allocator, std.testing.io, project_path, "world.kdl");
    defer doc.deinit();
    try std.testing.expectEqual(@as(usize, 1), doc.tiles.items.len);
    try std.testing.expectEqual(@as(i32, 2), doc.tiles.items[0].cell[0]);
    try std.testing.expectEqualStrings("grass", doc.tiles.items[0].material);
}

test "terrain authoring replaces tile for matching cell" {
    var doc = TerrainAuthoringDoc.init(std.testing.allocator);
    defer doc.deinit();
    try doc.upsertTile(.{
        .cell = .{ .x = 0, .y = 0, .z = 0 },
        .size = 2,
        .lod_levels = &.{ 2, 2 },
        .heights = &.{ 0, 0, 0, 0 },
        .splat_size = 2,
        .splat = &test_splat_2,
        .paint_layers = &test_paint_layers,
        .paint_colors = &test_paint_colors,
        .paint_albedo_textures = &test_paint_textures,
        .paint_roughness_textures = &test_paint_textures,
        .paint_specular_textures = &test_paint_textures,
        .paint_displacement_textures = &test_paint_textures,
    });
    try doc.upsertTile(.{
        .cell = .{ .x = 0, .y = 0, .z = 0 },
        .size = 2,
        .lod_levels = &.{ 2, 2 },
        .heights = &.{ 4, 4, 4, 4 },
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
    try std.testing.expectEqual(@as(usize, 1), doc.tiles.items.len);
    try std.testing.expectEqual(@as(f32, 4), doc.tiles.items[0].heights[0]);
    try std.testing.expectEqualStrings("mud", doc.tiles.items[0].material);
}

test "terrain authoring deletes tile for matching cell" {
    var doc = TerrainAuthoringDoc.init(std.testing.allocator);
    defer doc.deinit();
    try doc.upsertTile(.{
        .cell = .{ .x = 0, .y = 0, .z = 0 },
        .size = 2,
        .lod_levels = &.{ 2, 2 },
        .heights = &.{ 0, 0, 0, 0 },
        .splat_size = 2,
        .splat = &test_splat_2,
        .paint_layers = &test_paint_layers,
        .paint_colors = &test_paint_colors,
        .paint_albedo_textures = &test_paint_textures,
        .paint_roughness_textures = &test_paint_textures,
        .paint_specular_textures = &test_paint_textures,
        .paint_displacement_textures = &test_paint_textures,
    });
    try doc.upsertTile(.{
        .cell = .{ .x = 1, .y = 0, .z = 0 },
        .size = 2,
        .lod_levels = &.{ 2, 2 },
        .heights = &.{ 2, 2, 2, 2 },
        .splat_size = 2,
        .splat = &test_splat_2,
        .paint_layers = &test_paint_layers,
        .paint_colors = &test_paint_colors,
        .paint_albedo_textures = &test_paint_textures,
        .paint_roughness_textures = &test_paint_textures,
        .paint_specular_textures = &test_paint_textures,
        .paint_displacement_textures = &test_paint_textures,
    });

    try std.testing.expect(doc.deleteTile(.{ .x = 0, .y = 0, .z = 0 }));
    try std.testing.expect(!doc.deleteTile(.{ .x = 0, .y = 0, .z = 0 }));
    try std.testing.expectEqual(@as(usize, 1), doc.tiles.items.len);
    try std.testing.expectEqual(@as(i32, 1), doc.tiles.items[0].cell[0]);
}

test "terrain authoring rejects invalid height count" {
    var doc = TerrainAuthoringDoc.init(std.testing.allocator);
    defer doc.deinit();
    try std.testing.expectError(error.InvalidTerrainHeightCount, doc.upsertTile(.{
        .cell = .{ .x = 0, .y = 0, .z = 0 },
        .size = 2,
        .lod_levels = &.{ 2, 2 },
        .heights = &.{ 0, 0, 0 },
        .splat_size = 2,
        .splat = &test_splat_2,
        .paint_layers = &test_paint_layers,
        .paint_colors = &test_paint_colors,
        .paint_albedo_textures = &test_paint_textures,
        .paint_roughness_textures = &test_paint_textures,
        .paint_specular_textures = &test_paint_textures,
        .paint_displacement_textures = &test_paint_textures,
    }));
}

test "terrain seam validation accepts identical shared edge samples" {
    var doc = TerrainAuthoringDoc.init(std.testing.allocator);
    defer doc.deinit();
    try doc.upsertTile(.{
        .cell = .{ .x = 0, .y = 0, .z = 0 },
        .size = 2,
        .lod_levels = &.{ 2, 2 },
        .heights = &.{ 0, 10, 1, 11 },
        .splat_size = 2,
        .splat = &test_splat_2,
        .paint_layers = &test_paint_layers,
        .paint_colors = &test_paint_colors,
        .paint_albedo_textures = &test_paint_textures,
        .paint_roughness_textures = &test_paint_textures,
        .paint_specular_textures = &test_paint_textures,
        .paint_displacement_textures = &test_paint_textures,
    });
    try doc.upsertTile(.{
        .cell = .{ .x = 1, .y = 0, .z = 0 },
        .size = 2,
        .lod_levels = &.{ 2, 2 },
        .heights = &.{ 10, 20, 11, 21 },
        .splat_size = 2,
        .splat = &test_splat_2,
        .paint_layers = &test_paint_layers,
        .paint_colors = &test_paint_colors,
        .paint_albedo_textures = &test_paint_textures,
        .paint_roughness_textures = &test_paint_textures,
        .paint_specular_textures = &test_paint_textures,
        .paint_displacement_textures = &test_paint_textures,
    });

    const report = validateSeams(doc);
    try std.testing.expectEqual(@as(usize, 1), report.seam_count);
    try std.testing.expectEqual(@as(usize, 0), report.incompatible_seams);
    try std.testing.expectEqual(@as(usize, 0), report.mismatched_seams);
    try std.testing.expectEqual(@as(f32, 0), report.max_delta);
}

test "terrain seam validation reports mismatched shared edge samples" {
    var doc = TerrainAuthoringDoc.init(std.testing.allocator);
    defer doc.deinit();
    try doc.upsertTile(.{
        .cell = .{ .x = 0, .y = 0, .z = 0 },
        .size = 2,
        .lod_levels = &.{ 2, 2 },
        .heights = &.{ 0, 10, 1, 11 },
        .splat_size = 2,
        .splat = &test_splat_2,
        .paint_layers = &test_paint_layers,
        .paint_colors = &test_paint_colors,
        .paint_albedo_textures = &test_paint_textures,
        .paint_roughness_textures = &test_paint_textures,
        .paint_specular_textures = &test_paint_textures,
        .paint_displacement_textures = &test_paint_textures,
    });
    try doc.upsertTile(.{
        .cell = .{ .x = 1, .y = 0, .z = 0 },
        .size = 2,
        .lod_levels = &.{ 2, 2 },
        .heights = &.{ 10.25, 20, 11, 21 },
        .splat_size = 2,
        .splat = &test_splat_2,
        .paint_layers = &test_paint_layers,
        .paint_colors = &test_paint_colors,
        .paint_albedo_textures = &test_paint_textures,
        .paint_roughness_textures = &test_paint_textures,
        .paint_specular_textures = &test_paint_textures,
        .paint_displacement_textures = &test_paint_textures,
    });

    const report = validateSeams(doc);
    try std.testing.expectEqual(@as(usize, 1), report.seam_count);
    try std.testing.expectEqual(@as(usize, 0), report.incompatible_seams);
    try std.testing.expectEqual(@as(usize, 1), report.mismatched_seams);
    try std.testing.expectEqual(@as(f32, 0.25), report.max_delta);
}
