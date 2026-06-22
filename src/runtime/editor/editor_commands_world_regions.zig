const std = @import("std");
const shared = @import("runtime_shared");
const friendly_engine = @import("friendly_engine");

const editor_command_file = @import("editor_command_file.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_ui_world_region_paint = @import("project_editor_ui_world_region_paint.zig");

const CommandFile = editor_command_file.CommandFile;
const ProjectEditorState = project_editor_state.ProjectEditorState;
const editor_math = shared.editor_math;

pub fn describe(allocator: std.mem.Allocator, command: CommandFile, state: *ProjectEditorState) ![]u8 {
    const manifest_path = if (state.active_world_manifest_path.len == 0) return error.SceneWorldNotConfigured else state.active_world_manifest_path;
    var manifest = try friendly_engine.world.manifest.loadManifest(allocator, state.io, state.project_path, manifest_path);
    defer manifest.deinit();

    var loaded_regions = try friendly_engine.world.regions.loadOrEmpty(allocator, state.io, state.project_path, friendly_engine.world.regions.default_regions_path);
    defer loaded_regions.deinit();

    var out = try std.ArrayList(u8).initCapacity(allocator, 4096);
    defer out.deinit(allocator);
    try appendFmt(allocator, &out, "{{\"ok\":true,\"id\":", .{});
    try appendJsonString(allocator, &out, command.id);
    try appendFmt(allocator, &out, ",\"command\":", .{});
    try appendJsonString(allocator, &out, command.name);
    try appendFmt(allocator, &out, ",\"regions\":{d},\"manifest_cells\":{d},\"items\":[", .{ loaded_regions.regions.len, manifest.cells.len });
    var assigned_manifest_cells = std.AutoHashMap(friendly_engine.world.cell.CellId, void).init(allocator);
    defer assigned_manifest_cells.deinit();
    for (loaded_regions.regions, 0..) |region, index| {
        if (index != 0) try appendFmt(allocator, &out, ",", .{});
        for (region.cells) |id| {
            if (manifest.hasCell(id)) try assigned_manifest_cells.put(id, {});
        }
        try appendWorldRegionJson(allocator, &out, state, region);
    }
    const assigned_count = assigned_manifest_cells.count();
    try appendFmt(allocator, &out, "],\"unassigned_cells\":{d}}}\n", .{if (manifest.cells.len > assigned_count) manifest.cells.len - assigned_count else 0});
    return out.toOwnedSlice(allocator);
}

pub fn upsert(allocator: std.mem.Allocator, command: CommandFile, state: *ProjectEditorState) ![]u8 {
    const id = command.object orelse return error.MissingObject;
    const name = command.parent orelse id;
    const cells = try parseWorldRegionCells(allocator, command.cells orelse return error.MissingCells);
    defer allocator.free(cells);
    const props = try regionPropsFromJson(allocator, command.properties);
    defer allocator.free(props);
    var loaded = try friendly_engine.world.regions.upsertRegion(allocator, state.io, state.project_path, friendly_engine.world.regions.default_regions_path, .{ .id = id, .name = name, .props = props, .cells = cells });
    defer loaded.deinit();
    setSelectedWorldRegion(state, id);
    state.terrain_preview_stale = true;
    project_editor_state.setStatus(state, "World region saved");
    return regionMutationJson(allocator, command, id, name, cells.len, loaded.regions.len, "World region saved");
}

pub fn paint(allocator: std.mem.Allocator, command: CommandFile, state: *ProjectEditorState) ![]u8 {
    const id = command.object orelse return error.MissingObject;
    const name = command.parent orelse id;
    const point = editor_math.Vec3{
        .x = command.point_x orelse return error.MissingPoint,
        .y = command.point_y orelse return error.MissingPoint,
        .z = command.point_z orelse return error.MissingPoint,
    };
    const radius = command.radius orelse state.world_brush_size;
    const mode: friendly_engine.world.regions.PaintMode = if (command.operation) |operation| blk: {
        if (std.mem.eql(u8, operation, "assign")) break :blk .assign;
        if (std.mem.eql(u8, operation, "erase")) break :blk .erase;
        return error.InvalidWorldRegionPaintOperation;
    } else .assign;
    const touched = try project_editor_ui_world_region_paint.paintForRegion(state, id, name, point, radius, mode);
    var loaded = try friendly_engine.world.regions.loadOrEmpty(allocator, state.io, state.project_path, friendly_engine.world.regions.default_regions_path);
    defer loaded.deinit();
    return regionMutationJson(allocator, command, id, name, touched, loaded.regions.len, if (mode == .erase) "World region erased" else "World region painted");
}

pub fn delete(allocator: std.mem.Allocator, command: CommandFile, state: *ProjectEditorState) ![]u8 {
    const id = command.object orelse return error.MissingObject;
    var loaded = try friendly_engine.world.regions.deleteRegion(allocator, state.io, state.project_path, friendly_engine.world.regions.default_regions_path, id);
    defer loaded.deinit();
    if (selectedWorldRegionEql(state, id)) state.selected_world_region_id_len = 0;
    state.terrain_preview_stale = true;
    project_editor_state.setStatus(state, "World region deleted");
    return regionMutationJson(allocator, command, id, id, 0, loaded.regions.len, "World region deleted");
}

fn appendWorldRegionJson(allocator: std.mem.Allocator, out: *std.ArrayList(u8), state: *const ProjectEditorState, region: friendly_engine.world.regions.Region) !void {
    var min_x: i32 = std.math.maxInt(i32);
    var max_x: i32 = std.math.minInt(i32);
    var min_y: i32 = std.math.maxInt(i32);
    var max_y: i32 = std.math.minInt(i32);
    var resident: usize = 0;
    var dirty: usize = 0;
    for (region.cells) |id| {
        min_x = @min(min_x, id.x);
        max_x = @max(max_x, id.x);
        min_y = @min(min_y, id.y);
        max_y = @max(max_y, id.y);
        if (terrainPreviewHasCell(state, id)) resident += 1;
        if (dirtyWorldCell(state, id)) dirty += 1;
    }
    try appendFmt(allocator, out, "{{\"id\":", .{});
    try appendJsonString(allocator, out, region.id);
    try appendFmt(allocator, out, ",\"name\":", .{});
    try appendJsonString(allocator, out, region.name);
    try appendFmt(allocator, out, ",\"properties_raw\":", .{});
    try appendJsonString(allocator, out, region.props);
    try appendFmt(allocator, out, ",\"cells\":{d},\"resident\":{d},\"dirty\":{d},\"bounds\":", .{ region.cells.len, resident, dirty });
    if (region.cells.len == 0) {
        try appendFmt(allocator, out, "null", .{});
    } else {
        try appendFmt(allocator, out, "{{\"min_x\":{d},\"max_x\":{d},\"min_y\":{d},\"max_y\":{d}}}", .{ min_x, max_x, min_y, max_y });
    }
    try appendFmt(allocator, out, "}}", .{});
}

fn regionMutationJson(allocator: std.mem.Allocator, command: CommandFile, id: []const u8, name: []const u8, touched_cells: usize, region_count: usize, status: []const u8) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, 512);
    defer out.deinit(allocator);
    try appendFmt(allocator, &out, "{{\"ok\":true,\"id\":", .{});
    try appendJsonString(allocator, &out, command.id);
    try appendFmt(allocator, &out, ",\"command\":", .{});
    try appendJsonString(allocator, &out, command.name);
    try appendFmt(allocator, &out, ",\"region\":", .{});
    try appendJsonString(allocator, &out, id);
    try appendFmt(allocator, &out, ",\"name\":", .{});
    try appendJsonString(allocator, &out, name);
    try appendFmt(allocator, &out, ",\"touched_cells\":{d},\"regions\":{d},\"status\":", .{ touched_cells, region_count });
    try appendJsonString(allocator, &out, status);
    try appendFmt(allocator, &out, "}}\n", .{});
    return out.toOwnedSlice(allocator);
}

fn regionPropsFromJson(allocator: std.mem.Allocator, value: ?std.json.Value) ![]u8 {
    const json_value = value orelse return allocator.alloc(u8, 0);
    const object = switch (json_value) {
        .object => |object| object,
        else => return error.InvalidWorldRegionProperties,
    };
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    var it = object.iterator();
    var first = true;
    while (it.next()) |entry| {
        if (!first) try out.append(allocator, ';');
        first = false;
        try appendRegionPropToken(allocator, &out, entry.key_ptr.*);
        try out.append(allocator, '=');
        switch (entry.value_ptr.*) {
            .string => |string| try appendRegionPropToken(allocator, &out, string),
            .integer => |integer| try appendFmt(allocator, &out, "{d}", .{integer}),
            .float => |float| try appendFmt(allocator, &out, "{d}", .{float}),
            .bool => |boolean| try out.appendSlice(allocator, if (boolean) "true" else "false"),
            .null => try out.appendSlice(allocator, "null"),
            else => return error.InvalidWorldRegionProperties,
        }
    }
    return out.toOwnedSlice(allocator);
}

fn appendRegionPropToken(allocator: std.mem.Allocator, out: *std.ArrayList(u8), value: []const u8) !void {
    for (value) |byte| {
        if (byte < 0x20 or byte == ';' or byte == '=') return error.InvalidWorldRegionProperties;
        try out.append(allocator, byte);
    }
}

pub fn parseWorldRegionCells(allocator: std.mem.Allocator, text: []const u8) ![]friendly_engine.world.cell.CellId {
    var cells = std.ArrayList(friendly_engine.world.cell.CellId).empty;
    errdefer cells.deinit(allocator);
    var groups = std.mem.splitScalar(u8, text, ';');
    while (groups.next()) |raw| {
        const group = std.mem.trim(u8, raw, " \t\r\n");
        if (group.len == 0) continue;
        const id = try parseWorldRegionCell(group);
        for (cells.items) |existing| if (existing.eql(id)) return error.DuplicateWorldRegionCell;
        try cells.append(allocator, id);
    }
    return cells.toOwnedSlice(allocator);
}

fn parseWorldRegionCell(text: []const u8) !friendly_engine.world.cell.CellId {
    var parts = std.mem.splitScalar(u8, text, ',');
    const x = std.mem.trim(u8, parts.next() orelse return error.InvalidCellCoordinate, " \t\r\n");
    const y = std.mem.trim(u8, parts.next() orelse return error.InvalidCellCoordinate, " \t\r\n");
    const z = std.mem.trim(u8, parts.next() orelse return error.InvalidCellCoordinate, " \t\r\n");
    if (parts.next() != null) return error.InvalidCellCoordinate;
    return .{ .x = try std.fmt.parseInt(i32, x, 10), .y = try std.fmt.parseInt(i32, y, 10), .z = try std.fmt.parseInt(i32, z, 10) };
}

fn terrainPreviewHasCell(state: *const ProjectEditorState, id: friendly_engine.world.cell.CellId) bool {
    for (state.terrain_preview.entries.items) |entry| if (entry.snapshot.cell.eql(id)) return true;
    return false;
}

fn dirtyWorldCell(state: *const ProjectEditorState, id: friendly_engine.world.cell.CellId) bool {
    for (state.dirty_cells.cells[0..state.dirty_cells.count]) |entry| if (entry.cell.eql(id)) return true;
    return false;
}

fn setSelectedWorldRegion(state: *ProjectEditorState, id: []const u8) void {
    state.selected_world_region_id_len = @min(id.len, state.selected_world_region_id.len);
    @memcpy(state.selected_world_region_id[0..state.selected_world_region_id_len], id[0..state.selected_world_region_id_len]);
}

fn selectedWorldRegionEql(state: *const ProjectEditorState, id: []const u8) bool {
    return state.selected_world_region_id_len == id.len and std.mem.eql(u8, state.selected_world_region_id[0..state.selected_world_region_id_len], id);
}

fn appendJsonString(allocator: std.mem.Allocator, out: *std.ArrayList(u8), value: []const u8) !void {
    try out.append(allocator, '"');
    for (value) |ch| {
        switch (ch) {
            '"' => try out.appendSlice(allocator, "\\\""),
            '\\' => try out.appendSlice(allocator, "\\\\"),
            '\n' => try out.appendSlice(allocator, "\\n"),
            '\r' => try out.appendSlice(allocator, "\\r"),
            '\t' => try out.appendSlice(allocator, "\\t"),
            else => if (ch < 0x20) {
                try appendFmt(allocator, out, "\\u{x:0>4}", .{ch});
            } else {
                try out.append(allocator, ch);
            },
        }
    }
    try out.append(allocator, '"');
}

fn appendFmt(allocator: std.mem.Allocator, out: *std.ArrayList(u8), comptime fmt: []const u8, args: anytype) !void {
    const text = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(text);
    try out.appendSlice(allocator, text);
}
