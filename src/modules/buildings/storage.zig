const std = @import("std");
const world = @import("../../world/mod.zig");
const kdl = @import("kdl");
const layer_kdl = @import("../layer_kdl.zig");
const building_mod = @import("mod.zig");

const BuildingDef = building_mod.BuildingDef;
const DoorDef = building_mod.DoorDef;
const WindowDef = building_mod.WindowDef;
const BuildingsDoc = building_mod.BuildingsDoc;
const buildings_layer_file = "layers/buildings.kdl";

pub fn parseCellId(values: []const i32) !world.cell.CellId {
    if (values.len != 2 and values.len != 3) return error.InvalidBuildingCell;
    return .{
        .x = @intCast(values[0]),
        .y = @intCast(values[1]),
        .z = if (values.len == 3) @intCast(values[2]) else 0,
    };
}

pub fn loadDoc(
    allocator: std.mem.Allocator,
    compile_ctx: *const world.compiler.layer.CompileContext,
) !OwnedBuildingsDoc {
    const path = try layerPath(allocator, compile_ctx.manifest_path);
    defer allocator.free(path);
    var project_dir = try openProjectDir(compile_ctx.io, compile_ctx.project_path);
    defer project_dir.close(compile_ctx.io);
    const bytes = try project_dir.readFileAlloc(compile_ctx.io, path, allocator, .limited(8 * 1024 * 1024));
    defer allocator.free(bytes);
    var parsed = try parseBuildingsKdl(allocator, bytes);
    errdefer parsed.deinit();
    if (parsed.value.schema_version != 1) return error.UnsupportedBuildingsSchemaVersion;
    for (parsed.value.buildings) |building| {
        try building_mod.validateBuilding(building);
    }
    return parsed;
}

const OwnedBuildingsDoc = struct {
    value: BuildingsDoc,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *OwnedBuildingsDoc) void {
        for (self.value.buildings) |building| freeBuilding(self.allocator, building);
        self.allocator.free(self.value.buildings);
    }
};

fn parseBuildingsKdl(allocator: std.mem.Allocator, bytes: []const u8) !OwnedBuildingsDoc {
    const buffer = try allocator.allocSentinel(u8, bytes.len, 0);
    defer allocator.free(buffer);
    @memcpy(buffer, bytes);

    var parser = kdl.Parser.init(buffer);
    var buildings = std.ArrayList(BuildingDef).empty;
    errdefer {
        for (buildings.items) |building| freeBuilding(allocator, building);
        buildings.deinit(allocator);
    }

    var schema_version: u32 = 1;
    var depth: i32 = 0;
    var root_seen = false;
    var builder: ?BuildingBuilder = null;
    errdefer if (builder) |*building| building.deinit(allocator);

    while (true) {
        const event = try parser.next();
        switch (event) {
            .node => |node| {
                if (depth == 0) {
                    if (root_seen or !std.mem.eql(u8, node.val, "buildings")) return error.InvalidBuildingsDocument;
                    root_seen = true;
                    continue;
                }
                if (depth == 1) {
                    if (!std.mem.eql(u8, node.val, "building")) return error.UnknownField;
                    if (builder) |*building| try buildings.append(allocator, try building.finish(allocator));
                    builder = .{};
                    continue;
                }
                if (depth == 2) {
                    var building = &(builder orelse return error.InvalidBuildingsDocument);
                    if (std.mem.eql(u8, node.val, "door")) {
                        try building.doors.append(allocator, .{ .edge_index = 0, .offset = 0, .width = 0, .height = 0 });
                    } else if (std.mem.eql(u8, node.val, "window")) {
                        try building.windows.append(allocator, .{ .edge_index = 0, .offset = 0, .width = 0, .height = 0, .sill = 1.0 });
                    } else return error.UnknownField;
                    continue;
                }
                return error.InvalidBuildingsDocument;
            },
            .prop => |prop| {
                const value = try layer_kdl.decodeValue(allocator, prop.val);
                defer allocator.free(value);
                if (depth == 0) {
                    if (std.mem.eql(u8, prop.key, "version")) schema_version = try std.fmt.parseInt(u32, value, 10) else return error.UnknownField;
                } else if (depth == 1) {
                    var building = &(builder orelse return error.InvalidBuildingsDocument);
                    try building.apply(allocator, prop.key, value);
                } else if (depth == 2) {
                    var building = &(builder orelse return error.InvalidBuildingsDocument);
                    if (building.doors.items.len > 0 and building.windows.items.len == 0) {
                        try applyDoorProp(&building.doors.items[building.doors.items.len - 1], prop.key, value);
                    } else if (building.windows.items.len > 0) {
                        try applyWindowProp(&building.windows.items[building.windows.items.len - 1], prop.key, value);
                    } else return error.InvalidBuildingsDocument;
                } else return error.InvalidBuildingsDocument;
            },
            .child_block_begin => depth += 1,
            .child_block_end => {
                if (depth == 1) {
                    if (builder) |*building| {
                        try buildings.append(allocator, try building.finish(allocator));
                        builder = null;
                    }
                }
                depth -= 1;
                if (depth < 0) return error.InvalidBuildingsDocument;
            },
            .arg, .invalid => return error.InvalidBuildingsDocument,
            .eof => break,
        }
    }
    if (builder) |*building| try buildings.append(allocator, try building.finish(allocator));
    if (!root_seen or depth != 0) return error.InvalidBuildingsDocument;
    return .{
        .allocator = allocator,
        .value = .{
            .schema_version = schema_version,
            .buildings = try buildings.toOwnedSlice(allocator),
        },
    };
}

const BuildingBuilder = struct {
    id: ?[]u8 = null,
    cell: ?[]i32 = null,
    floors: ?u32 = null,
    footprint: ?[]const []const f32 = null,
    doors: std.ArrayList(DoorDef) = .empty,
    windows: std.ArrayList(WindowDef) = .empty,

    fn deinit(self: *BuildingBuilder, allocator: std.mem.Allocator) void {
        if (self.id) |value| allocator.free(value);
        if (self.cell) |value| allocator.free(value);
        if (self.footprint) |value| layer_kdl.freeNestedF32(allocator, value);
        self.doors.deinit(allocator);
        self.windows.deinit(allocator);
    }

    fn apply(self: *BuildingBuilder, allocator: std.mem.Allocator, key: []const u8, value: []const u8) !void {
        if (std.mem.eql(u8, key, "id")) self.id = try replaceString(allocator, self.id, value) else if (std.mem.eql(u8, key, "cell")) self.cell = try replaceCell(allocator, self.cell, value) else if (std.mem.eql(u8, key, "floors")) self.floors = try std.fmt.parseInt(u32, value, 10) else if (std.mem.eql(u8, key, "footprint")) {
            if (self.footprint) |existing| layer_kdl.freeNestedF32(allocator, existing);
            self.footprint = try layer_kdl.parsePoint2List(allocator, value);
        } else return error.UnknownField;
    }

    fn finish(self: *BuildingBuilder, allocator: std.mem.Allocator) !BuildingDef {
        const result = BuildingDef{
            .id = self.id orelse return error.InvalidBuildingDefinition,
            .cell = self.cell orelse return error.InvalidBuildingDefinition,
            .floors = self.floors orelse return error.InvalidBuildingDefinition,
            .footprint = self.footprint orelse return error.InvalidBuildingDefinition,
            .doors = try self.doors.toOwnedSlice(allocator),
            .windows = try self.windows.toOwnedSlice(allocator),
        };
        self.id = null;
        self.cell = null;
        self.footprint = null;
        return result;
    }
};

fn applyDoorProp(door: *DoorDef, key: []const u8, value: []const u8) !void {
    if (std.mem.eql(u8, key, "edge_index")) door.edge_index = try std.fmt.parseInt(u32, value, 10) else if (std.mem.eql(u8, key, "offset")) door.offset = try std.fmt.parseFloat(f32, value) else if (std.mem.eql(u8, key, "width")) door.width = try std.fmt.parseFloat(f32, value) else if (std.mem.eql(u8, key, "height")) door.height = try std.fmt.parseFloat(f32, value) else return error.UnknownField;
}

fn applyWindowProp(window: *WindowDef, key: []const u8, value: []const u8) !void {
    if (std.mem.eql(u8, key, "edge_index")) window.edge_index = try std.fmt.parseInt(u32, value, 10) else if (std.mem.eql(u8, key, "offset")) window.offset = try std.fmt.parseFloat(f32, value) else if (std.mem.eql(u8, key, "width")) window.width = try std.fmt.parseFloat(f32, value) else if (std.mem.eql(u8, key, "height")) window.height = try std.fmt.parseFloat(f32, value) else if (std.mem.eql(u8, key, "sill")) window.sill = try std.fmt.parseFloat(f32, value) else return error.UnknownField;
}

fn replaceString(allocator: std.mem.Allocator, existing: ?[]u8, value: []const u8) ![]u8 {
    if (existing) |old| allocator.free(old);
    return allocator.dupe(u8, value);
}

fn replaceCell(allocator: std.mem.Allocator, existing: ?[]i32, value: []const u8) ![]i32 {
    if (existing) |old| allocator.free(old);
    const parsed = try layer_kdl.parseI32Triple(value);
    return allocator.dupe(i32, &parsed);
}

fn freeBuilding(allocator: std.mem.Allocator, building: BuildingDef) void {
    allocator.free(building.id);
    allocator.free(building.cell);
    layer_kdl.freeNestedF32(allocator, building.footprint);
    allocator.free(building.doors);
    allocator.free(building.windows);
}

fn layerPath(allocator: std.mem.Allocator, manifest_path: []const u8) ![]u8 {
    const dir = std.fs.path.dirname(manifest_path) orelse "";
    if (dir.len == 0) return allocator.dupe(u8, buildings_layer_file);
    return std.fs.path.join(allocator, &.{ dir, buildings_layer_file });
}

fn openProjectDir(io: std.Io, project_path: []const u8) !std.Io.Dir {
    if (std.fs.path.isAbsolute(project_path)) return std.Io.Dir.openDirAbsolute(io, project_path, .{});
    return std.Io.Dir.cwd().openDir(io, project_path, .{});
}
