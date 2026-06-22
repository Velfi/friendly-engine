const std = @import("std");
const friendly_engine = @import("friendly_engine");
const editor_command_file = @import("editor_command_file.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_world_ocean = @import("project_editor_world_ocean.zig");

const CommandFile = editor_command_file.CommandFile;
const ProjectEditorState = project_editor_state.ProjectEditorState;

pub const OceanClipPointMutation = enum { add, move_nearest, delete_nearest };

pub fn listOceanClip(allocator: std.mem.Allocator, command: CommandFile, state: *ProjectEditorState) ![]u8 {
    const index = project_editor_world_ocean.findOceanObjectIndex(state) orelse return error.OceanObjectNotFound;
    var clip = try project_editor_world_ocean.loadClip(allocator, &state.objects.items[index]);
    defer clip.deinit(allocator);
    return oceanClipJson(allocator, command, state, index, clip.points, clip.outer_half_extent_m, "Ocean exclusion listed");
}

pub fn updateOceanClip(allocator: std.mem.Allocator, command: CommandFile, state: *ProjectEditorState) ![]u8 {
    const points = try project_editor_world_ocean.parseClipPoints(allocator, command.points orelse return error.MissingPoints);
    defer allocator.free(points);
    try project_editor_world_ocean.replaceClip(state, points);
    return listOceanClip(allocator, command, state);
}

pub fn mutateOceanClipPoint(
    allocator: std.mem.Allocator,
    command: CommandFile,
    state: *ProjectEditorState,
    mutation: OceanClipPointMutation,
) ![]u8 {
    const point = project_editor_world_ocean.ClipPoint{
        .x = command.point_x orelse return error.MissingPoint,
        .z = command.point_z orelse return error.MissingPoint,
    };
    switch (mutation) {
        .add => try project_editor_world_ocean.addClipPoint(state, point),
        .move_nearest => try project_editor_world_ocean.moveNearestClipPoint(state, point),
        .delete_nearest => try project_editor_world_ocean.removeNearestClipPoint(state, point),
    }
    return listOceanClip(allocator, command, state);
}

fn oceanClipJson(
    allocator: std.mem.Allocator,
    command: CommandFile,
    state: *const ProjectEditorState,
    object_index: usize,
    points: []const project_editor_world_ocean.ClipPoint,
    outer_half_extent_m: f32,
    status: []const u8,
) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, 2048);
    defer out.deinit(allocator);
    try appendFmt(allocator, &out, "{{\"ok\":true,\"id\":", .{});
    try appendJsonString(allocator, &out, command.id);
    try appendFmt(allocator, &out, ",\"command\":", .{});
    try appendJsonString(allocator, &out, command.name);
    try appendFmt(allocator, &out, ",\"object_id\":{d},\"object_name\":", .{state.objects.items[object_index].id});
    try appendJsonString(allocator, &out, state.objects.items[object_index].name);
    try appendFmt(allocator, &out, ",\"outer_half_extent_m\":{d:.6},\"exclusion_active\":{},\"point_count\":{d},\"points\":[", .{ outer_half_extent_m, points.len >= 3, points.len });
    for (points, 0..) |point, index| {
        if (index != 0) try appendFmt(allocator, &out, ",", .{});
        try appendFmt(allocator, &out, "{{\"index\":{d},\"x\":{d:.6},\"z\":{d:.6}}}", .{ index, point.x, point.z });
    }
    try appendFmt(allocator, &out, "],\"status\":", .{});
    try appendJsonString(allocator, &out, status);
    try appendFmt(allocator, &out, "}}\n", .{});
    return out.toOwnedSlice(allocator);
}

pub fn listWaterVolumes(allocator: std.mem.Allocator, command: CommandFile, state: *ProjectEditorState) ![]u8 {
    const water_mod = friendly_engine.modules.water;
    var doc = try water_mod.authoring.loadProject(allocator, state.io, state.project_path, state.active_world_manifest_path);
    defer doc.deinit(allocator);
    var out = try std.ArrayList(u8).initCapacity(allocator, 512);
    defer out.deinit(allocator);
    try appendFmt(allocator, &out, "{{\"ok\":true,\"id\":", .{});
    try appendJsonString(allocator, &out, command.id);
    try appendFmt(allocator, &out, ",\"command\":", .{});
    try appendJsonString(allocator, &out, command.name);
    try appendFmt(allocator, &out, ",\"volumes\":[", .{});
    for (doc.volumes, 0..) |volume, index| {
        if (index > 0) try appendFmt(allocator, &out, ",", .{});
        try appendWaterVolumeJson(allocator, &out, volume);
    }
    try appendFmt(allocator, &out, "]}}\n", .{});
    return out.toOwnedSlice(allocator);
}

pub fn upsertWaterVolume(allocator: std.mem.Allocator, command: CommandFile, state: *ProjectEditorState, create: bool) ![]u8 {
    const water_mod = friendly_engine.modules.water;
    const id = command.object orelse return error.MissingObject;
    var doc = try water_mod.authoring.loadProject(allocator, state.io, state.project_path, state.active_world_manifest_path);
    defer doc.deinit(allocator);
    const existing_index = waterVolumeIndex(doc, id);
    if (create and existing_index != null) return error.DuplicateWaterVolumeId;
    if (!create and existing_index == null) return error.MissingObject;

    var volumes = std.ArrayList(water_mod.WaterVolume).empty;
    defer {
        for (volumes.items) |*volume| volume.deinit(allocator);
        volumes.deinit(allocator);
    }
    for (doc.volumes, 0..) |volume, index| {
        if (existing_index != null and index == existing_index.?) continue;
        try volumes.append(allocator, try water_mod.WaterVolume.duplicate(allocator, volume));
    }
    const base = if (existing_index) |index| doc.volumes[index] else water_mod.WaterVolume{
        .id = @constCast(id),
        .kind = .lake,
        .material = @constCast("water.lake.clear"),
        .surface_y = command.surface_y orelse 0,
        .bottom_y = command.bottom_y orelse -4,
        .points = &.{},
    };
    var next = try water_mod.WaterVolume.duplicate(allocator, base);
    errdefer next.deinit(allocator);
    try applyWaterCommandFields(allocator, &next, command);
    try water_mod.validateVolume(next);
    try volumes.append(allocator, next);
    const owned = try volumes.toOwnedSlice(allocator);
    volumes = .empty;
    var out_doc = water_mod.WaterDoc{ .volumes = owned };
    defer out_doc.deinit(allocator);
    try water_mod.authoring.saveProject(allocator, state.io, state.project_path, state.active_world_manifest_path, out_doc);
    const touched = try markWaterDirtyForVolume(allocator, state, next);
    project_editor_state.setStatus(state, if (create) "Water volume created" else "Water volume updated");
    return waterMutationJson(allocator, command, next, touched, state.status_buf[0..state.status_len]);
}

pub fn deleteWaterVolume(allocator: std.mem.Allocator, command: CommandFile, state: *ProjectEditorState) ![]u8 {
    const water_mod = friendly_engine.modules.water;
    const id = command.object orelse return error.MissingObject;
    var doc = try water_mod.authoring.loadProject(allocator, state.io, state.project_path, state.active_world_manifest_path);
    defer doc.deinit(allocator);
    const index = waterVolumeIndex(doc, id) orelse return error.MissingObject;
    const deleted = doc.volumes[index];
    var volumes = std.ArrayList(water_mod.WaterVolume).empty;
    defer {
        for (volumes.items) |*volume| volume.deinit(allocator);
        volumes.deinit(allocator);
    }
    for (doc.volumes, 0..) |volume, volume_index| {
        if (volume_index == index) continue;
        try volumes.append(allocator, try water_mod.WaterVolume.duplicate(allocator, volume));
    }
    const owned = try volumes.toOwnedSlice(allocator);
    volumes = .empty;
    var out_doc = water_mod.WaterDoc{ .volumes = owned };
    defer out_doc.deinit(allocator);
    try water_mod.authoring.saveProject(allocator, state.io, state.project_path, state.active_world_manifest_path, out_doc);
    const touched = try markWaterDirtyForVolume(allocator, state, deleted);
    project_editor_state.setStatus(state, "Water volume deleted");
    return waterDeleteJson(allocator, command, id, touched, state.status_buf[0..state.status_len]);
}

pub fn queryWaterPoint(allocator: std.mem.Allocator, command: CommandFile, state: *ProjectEditorState) ![]u8 {
    const water_mod = friendly_engine.modules.water;
    const point = friendly_engine.core.math.Vec3f{
        .x = command.point_x orelse return error.MissingPoint,
        .y = command.point_y orelse return error.MissingPoint,
        .z = command.point_z orelse return error.MissingPoint,
    };
    var doc = try water_mod.authoring.loadProject(allocator, state.io, state.project_path, state.active_world_manifest_path);
    defer doc.deinit(allocator);
    const query = water_mod.queryPoint(doc.volumes, point);
    var out = try std.ArrayList(u8).initCapacity(allocator, 384);
    defer out.deinit(allocator);
    try appendFmt(allocator, &out, "{{\"ok\":true,\"id\":", .{});
    try appendJsonString(allocator, &out, command.id);
    try appendFmt(allocator, &out, ",\"command\":", .{});
    try appendJsonString(allocator, &out, command.name);
    try appendFmt(allocator, &out, ",\"point\":{{\"x\":{d:.6},\"y\":{d:.6},\"z\":{d:.6}}},\"query\":{{\"in_water\":{},\"swimmable\":{},\"surface_y\":{d:.6},\"bottom_y\":{d:.6},\"submerged_depth\":{d:.6},\"current\":{{\"x\":{d:.6},\"y\":{d:.6},\"z\":{d:.6}}},\"volume_id\":", .{
        point.x,
        point.y,
        point.z,
        query.in_water,
        query.swimmable,
        query.surface_y,
        query.bottom_y,
        query.submerged_depth,
        query.current.x,
        query.current.y,
        query.current.z,
    });
    try appendJsonString(allocator, &out, query.volume_id);
    try appendFmt(allocator, &out, ",\"material\":", .{});
    try appendJsonString(allocator, &out, query.material);
    try appendFmt(allocator, &out, "}}}}\n", .{});
    return out.toOwnedSlice(allocator);
}

fn applyWaterCommandFields(allocator: std.mem.Allocator, volume: *friendly_engine.modules.water.WaterVolume, command: CommandFile) !void {
    const water_mod = friendly_engine.modules.water;
    if (command.kind) |kind| volume.kind = water_mod.kindFromName(kind) orelse return error.InvalidArguments;
    if (command.material) |material| {
        allocator.free(volume.material);
        volume.material = try allocator.dupe(u8, material);
    }
    if (command.points) |points| {
        if (volume.points.len > 0) allocator.free(volume.points);
        volume.points = try water_mod.parsePoints(allocator, points);
    }
    if (command.surface_y) |value| volume.surface_y = value;
    if (command.bottom_y) |value| volume.bottom_y = value;
    if (command.swimmable) |value| volume.swimmable = value;
    if (command.linked_to_ocean) |value| volume.linked_to_ocean = value;
    if (command.current_x) |value| volume.current.x = value;
    if (command.current_y) |value| volume.current.y = value;
    if (command.current_z) |value| volume.current.z = value;
}

fn waterVolumeIndex(doc: friendly_engine.modules.water.WaterDoc, id: []const u8) ?usize {
    for (doc.volumes, 0..) |volume, index| if (std.mem.eql(u8, volume.id, id)) return index;
    return null;
}

fn markWaterDirtyForVolume(allocator: std.mem.Allocator, state: *ProjectEditorState, volume: friendly_engine.modules.water.WaterVolume) !usize {
    var manifest = try friendly_engine.world.manifest.loadManifest(allocator, state.io, state.project_path, state.active_world_manifest_path);
    defer manifest.deinit();
    const b = friendly_engine.modules.water.bounds(volume);
    const min_id = friendly_engine.world.cell.idAtPosition(b.min_x, b.min_z, volume.bottom_y, manifest.cell_size_m, friendly_engine.world.cell.default_cell_height_m, false);
    const max_id = friendly_engine.world.cell.idAtPosition(b.max_x, b.max_z, volume.surface_y, manifest.cell_size_m, friendly_engine.world.cell.default_cell_height_m, false);
    var touched: usize = 0;
    var x = min_id.x;
    while (x <= max_id.x) : (x += 1) {
        var y = min_id.y;
        while (y <= max_id.y) : (y += 1) {
            const cell = friendly_engine.world.cell.CellId{ .x = x, .y = y, .z = 0 };
            if (!manifest.hasCell(cell)) continue;
            try project_editor_state.markDirtyCell(state, "Water", cell, "volumes");
            touched += 1;
        }
    }
    return touched;
}

fn appendWaterVolumeJson(allocator: std.mem.Allocator, out: *std.ArrayList(u8), volume: friendly_engine.modules.water.WaterVolume) !void {
    try appendFmt(allocator, out, "{{\"id\":", .{});
    try appendJsonString(allocator, out, volume.id);
    try appendFmt(allocator, out, ",\"kind\":\"{s}\",\"material\":", .{volume.kind.label()});
    try appendJsonString(allocator, out, volume.material);
    try appendFmt(allocator, out, ",\"surface_y\":{d:.6},\"bottom_y\":{d:.6},\"swimmable\":{},\"linked_to_ocean\":{},\"current\":{{\"x\":{d:.6},\"y\":{d:.6},\"z\":{d:.6}}},\"points\":[", .{
        volume.surface_y,
        volume.bottom_y,
        volume.swimmable,
        volume.linked_to_ocean,
        volume.current.x,
        volume.current.y,
        volume.current.z,
    });
    for (volume.points, 0..) |point, index| {
        if (index > 0) try appendFmt(allocator, out, ",", .{});
        try appendFmt(allocator, out, "{{\"x\":{d:.6},\"z\":{d:.6}}}", .{ point[0], point[1] });
    }
    try appendFmt(allocator, out, "]}}", .{});
}

fn waterMutationJson(allocator: std.mem.Allocator, command: CommandFile, volume: friendly_engine.modules.water.WaterVolume, touched: usize, status: []const u8) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, 512);
    defer out.deinit(allocator);
    try appendFmt(allocator, &out, "{{\"ok\":true,\"id\":", .{});
    try appendJsonString(allocator, &out, command.id);
    try appendFmt(allocator, &out, ",\"command\":", .{});
    try appendJsonString(allocator, &out, command.name);
    try appendFmt(allocator, &out, ",\"volume\":", .{});
    try appendWaterVolumeJson(allocator, &out, volume);
    try appendFmt(allocator, &out, ",\"touched_cells\":{d},\"status\":", .{touched});
    try appendJsonString(allocator, &out, status);
    try appendFmt(allocator, &out, "}}\n", .{});
    return out.toOwnedSlice(allocator);
}

fn waterDeleteJson(allocator: std.mem.Allocator, command: CommandFile, id: []const u8, touched: usize, status: []const u8) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, 256);
    defer out.deinit(allocator);
    try appendFmt(allocator, &out, "{{\"ok\":true,\"id\":", .{});
    try appendJsonString(allocator, &out, command.id);
    try appendFmt(allocator, &out, ",\"command\":", .{});
    try appendJsonString(allocator, &out, command.name);
    try appendFmt(allocator, &out, ",\"volume_id\":", .{});
    try appendJsonString(allocator, &out, id);
    try appendFmt(allocator, &out, ",\"touched_cells\":{d},\"status\":", .{touched});
    try appendJsonString(allocator, &out, status);
    try appendFmt(allocator, &out, "}}\n", .{});
    return out.toOwnedSlice(allocator);
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
