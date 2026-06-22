const std = @import("std");
const world = @import("../../world/mod.zig");
const kdl = @import("kdl");
const layer_kdl = @import("../layer_kdl.zig");
const sectors = @import("mod.zig");

const SectorsDoc = sectors.SectorsDoc;
const InteriorDef = sectors.InteriorDef;
const SectorDef = sectors.SectorDef;
const PortalDef = sectors.PortalDef;
const sectors_layer_file = "layers/sectors.kdl";

pub fn parseCellId(values: []const i32) !world.cell.CellId {
    if (values.len != 2 and values.len != 3) return error.InvalidInteriorCell;
    return .{
        .x = @intCast(values[0]),
        .y = @intCast(values[1]),
        .z = if (values.len == 3) @intCast(values[2]) else 0,
    };
}

pub fn loadSectorsDoc(
    allocator: std.mem.Allocator,
    compile_ctx: *const world.compiler.layer.CompileContext,
) !OwnedSectorsDoc {
    const path = try layerPath(allocator, compile_ctx.manifest_path);
    defer allocator.free(path);
    var project_dir = try openProjectDir(compile_ctx.io, compile_ctx.project_path);
    defer project_dir.close(compile_ctx.io);
    const bytes = try project_dir.readFileAlloc(compile_ctx.io, path, allocator, .limited(8 * 1024 * 1024));
    defer allocator.free(bytes);

    var parsed = try parseSectorsKdl(allocator, bytes);
    errdefer parsed.deinit();
    if (parsed.value.schema_version != 1) return error.UnsupportedSectorsSchemaVersion;
    for (parsed.value.interiors) |interior| {
        try sectors.validateInterior(allocator, interior);
    }
    return parsed;
}

const OwnedSectorsDoc = struct {
    value: SectorsDoc,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *OwnedSectorsDoc) void {
        for (self.value.interiors) |interior| {
            self.allocator.free(interior.cell);
            self.allocator.free(interior.parent_cell);
            for (interior.sectors) |sector| {
                freeSector(self.allocator, sector);
            }
            self.allocator.free(interior.sectors);
        }
        self.allocator.free(self.value.interiors);
    }
};

fn parseSectorsKdl(allocator: std.mem.Allocator, bytes: []const u8) !OwnedSectorsDoc {
    const buffer = try allocator.allocSentinel(u8, bytes.len, 0);
    defer allocator.free(buffer);
    @memcpy(buffer, bytes);

    var parser = kdl.Parser.init(buffer);
    var interiors = std.ArrayList(InteriorDef).empty;
    errdefer {
        for (interiors.items) |interior| freeInterior(allocator, interior);
        interiors.deinit(allocator);
    }

    var schema_version: u32 = 1;
    var depth: i32 = 0;
    var root_seen = false;
    var interior_builder: ?InteriorBuilder = null;
    var sector_builder: ?SectorBuilder = null;
    errdefer {
        if (interior_builder) |*builder| builder.deinit(allocator);
        if (sector_builder) |*builder| builder.deinit(allocator);
    }

    while (true) {
        const event = try parser.next();
        switch (event) {
            .node => |node| {
                if (depth == 0) {
                    if (root_seen or !std.mem.eql(u8, node.val, "sectors")) return error.InvalidSectorsDocument;
                    root_seen = true;
                    continue;
                }
                if (depth == 1) {
                    if (!std.mem.eql(u8, node.val, "interior")) return error.UnknownField;
                    if (interior_builder) |*builder| try interiors.append(allocator, try builder.finish(allocator));
                    interior_builder = .{};
                    continue;
                }
                if (depth == 2) {
                    if (!std.mem.eql(u8, node.val, "sector")) return error.UnknownField;
                    if (sector_builder) |*builder| {
                        try interior_builder.?.sectors.append(allocator, try builder.finish(allocator));
                    }
                    sector_builder = .{};
                    continue;
                }
                if (depth == 3) {
                    if (!std.mem.eql(u8, node.val, "portal")) return error.UnknownField;
                    try sector_builder.?.portals.append(allocator, .{ .to_sector = 0, .position = &.{}, .width = 0, .height = 0 });
                    continue;
                }
                return error.InvalidSectorsDocument;
            },
            .prop => |prop| {
                const value = try layer_kdl.decodeValue(allocator, prop.val);
                defer allocator.free(value);
                if (depth == 0) {
                    if (std.mem.eql(u8, prop.key, "version")) schema_version = try std.fmt.parseInt(u32, value, 10) else return error.UnknownField;
                } else if (depth == 1) {
                    var builder = &(interior_builder orelse return error.InvalidSectorsDocument);
                    try builder.apply(allocator, prop.key, value);
                } else if (depth == 2) {
                    var builder = &(sector_builder orelse return error.InvalidSectorsDocument);
                    try builder.apply(allocator, prop.key, value);
                } else if (depth == 3) {
                    var builder = &(sector_builder orelse return error.InvalidSectorsDocument);
                    if (builder.portals.items.len == 0) return error.InvalidSectorsDocument;
                    try applyPortalProp(allocator, &builder.portals.items[builder.portals.items.len - 1], prop.key, value);
                } else return error.InvalidSectorsDocument;
            },
            .child_block_begin => depth += 1,
            .child_block_end => {
                if (depth == 2) {
                    if (sector_builder) |*builder| {
                        try interior_builder.?.sectors.append(allocator, try builder.finish(allocator));
                        sector_builder = null;
                    }
                } else if (depth == 1) {
                    if (interior_builder) |*builder| {
                        try interiors.append(allocator, try builder.finish(allocator));
                        interior_builder = null;
                    }
                }
                depth -= 1;
                if (depth < 0) return error.InvalidSectorsDocument;
            },
            .arg, .invalid => return error.InvalidSectorsDocument,
            .eof => break,
        }
    }
    if (sector_builder) |*builder| try interior_builder.?.sectors.append(allocator, try builder.finish(allocator));
    if (interior_builder) |*builder| try interiors.append(allocator, try builder.finish(allocator));
    if (!root_seen or depth != 0) return error.InvalidSectorsDocument;
    return .{
        .allocator = allocator,
        .value = .{
            .schema_version = schema_version,
            .interiors = try interiors.toOwnedSlice(allocator),
        },
    };
}

const InteriorBuilder = struct {
    cell: ?[]i32 = null,
    parent_cell: ?[]i32 = null,
    sectors: std.ArrayList(SectorDef) = .empty,

    fn deinit(self: *InteriorBuilder, allocator: std.mem.Allocator) void {
        if (self.cell) |value| allocator.free(value);
        if (self.parent_cell) |value| allocator.free(value);
        for (self.sectors.items) |sector| {
            freeSector(allocator, sector);
        }
        self.sectors.deinit(allocator);
    }

    fn apply(self: *InteriorBuilder, allocator: std.mem.Allocator, key: []const u8, value: []const u8) !void {
        if (std.mem.eql(u8, key, "cell")) self.cell = try replaceCell(allocator, self.cell, value) else if (std.mem.eql(u8, key, "parent_cell")) self.parent_cell = try replaceCell(allocator, self.parent_cell, value) else return error.UnknownField;
    }

    fn finish(self: *InteriorBuilder, allocator: std.mem.Allocator) !InteriorDef {
        const result = InteriorDef{
            .cell = self.cell orelse return error.InvalidInteriorCell,
            .parent_cell = self.parent_cell orelse return error.InvalidInteriorCell,
            .sectors = try self.sectors.toOwnedSlice(allocator),
        };
        self.cell = null;
        self.parent_cell = null;
        return result;
    }
};

const SectorBuilder = struct {
    id: ?u32 = null,
    floor_height: ?f32 = null,
    ceiling_height: ?f32 = null,
    polygon: ?[]const []const f32 = null,
    portals: std.ArrayList(PortalDef) = .empty,

    fn deinit(self: *SectorBuilder, allocator: std.mem.Allocator) void {
        if (self.polygon) |value| layer_kdl.freeNestedF32(allocator, value);
        for (self.portals.items) |portal| allocator.free(portal.position);
        self.portals.deinit(allocator);
    }

    fn apply(self: *SectorBuilder, allocator: std.mem.Allocator, key: []const u8, value: []const u8) !void {
        if (std.mem.eql(u8, key, "id")) self.id = try std.fmt.parseInt(u32, value, 10) else if (std.mem.eql(u8, key, "floor_height")) self.floor_height = try std.fmt.parseFloat(f32, value) else if (std.mem.eql(u8, key, "ceiling_height")) self.ceiling_height = try std.fmt.parseFloat(f32, value) else if (std.mem.eql(u8, key, "polygon")) {
            if (self.polygon) |existing| layer_kdl.freeNestedF32(allocator, existing);
            self.polygon = try layer_kdl.parsePoint2List(allocator, value);
        } else return error.UnknownField;
    }

    fn finish(self: *SectorBuilder, allocator: std.mem.Allocator) !SectorDef {
        const result = SectorDef{
            .id = self.id orelse return error.InvalidSectorDefinition,
            .floor_height = self.floor_height orelse return error.InvalidSectorDefinition,
            .ceiling_height = self.ceiling_height orelse return error.InvalidSectorDefinition,
            .polygon = self.polygon orelse return error.InvalidSectorDefinition,
            .portals = try self.portals.toOwnedSlice(allocator),
        };
        self.polygon = null;
        return result;
    }
};

fn applyPortalProp(allocator: std.mem.Allocator, portal: *PortalDef, key: []const u8, value: []const u8) !void {
    if (std.mem.eql(u8, key, "to_sector")) portal.to_sector = try std.fmt.parseInt(u32, value, 10) else if (std.mem.eql(u8, key, "position")) {
        if (portal.position.len > 0) allocator.free(portal.position);
        const parsed = try layer_kdl.parseF32Triple(value);
        portal.position = try allocator.dupe(f32, &parsed);
    } else if (std.mem.eql(u8, key, "width")) portal.width = try std.fmt.parseFloat(f32, value) else if (std.mem.eql(u8, key, "height")) portal.height = try std.fmt.parseFloat(f32, value) else return error.UnknownField;
}

fn replaceCell(allocator: std.mem.Allocator, existing: ?[]i32, value: []const u8) ![]i32 {
    if (existing) |old| allocator.free(old);
    const parsed = try layer_kdl.parseI32Triple(value);
    return allocator.dupe(i32, &parsed);
}

fn freeInterior(allocator: std.mem.Allocator, interior: InteriorDef) void {
    allocator.free(interior.cell);
    allocator.free(interior.parent_cell);
    for (interior.sectors) |sector| {
        freeSector(allocator, sector);
    }
    allocator.free(interior.sectors);
}

fn freeSector(allocator: std.mem.Allocator, sector: SectorDef) void {
    layer_kdl.freeNestedF32(allocator, sector.polygon);
    for (sector.portals) |portal| {
        if (portal.position.len > 0) allocator.free(portal.position);
    }
    allocator.free(sector.portals);
}

fn layerPath(allocator: std.mem.Allocator, manifest_path: []const u8) ![]u8 {
    const dir = std.fs.path.dirname(manifest_path) orelse "";
    if (dir.len == 0) return allocator.dupe(u8, sectors_layer_file);
    return std.fs.path.join(allocator, &.{ dir, sectors_layer_file });
}

fn openProjectDir(io: std.Io, project_path: []const u8) !std.Io.Dir {
    if (std.fs.path.isAbsolute(project_path)) return std.Io.Dir.openDirAbsolute(io, project_path, .{});
    return std.Io.Dir.cwd().openDir(io, project_path, .{});
}
