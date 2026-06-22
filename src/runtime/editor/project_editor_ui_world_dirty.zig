const std = @import("std");

const project_editor_dirty_cells = @import("project_editor_dirty_cells.zig");
const project_editor_types = @import("project_editor_types.zig");
const friendly_engine = @import("friendly_engine");

const DirtyCell = project_editor_dirty_cells.DirtyCell;
const DirtyCellTracker = project_editor_dirty_cells.DirtyCellTracker;
const WorldLayerId = project_editor_types.WorldLayerId;
const world = friendly_engine.world;

pub fn dirtyGroupCount(tracker: *const DirtyCellTracker, group_label: []const u8) usize {
    var count: usize = 0;
    for (tracker.cells[0..tracker.count]) |dirty| {
        if (std.mem.eql(u8, dirty.layer_name, group_label)) count += 1;
    }
    return count;
}

pub fn formatLayerDirtyBadge(tracker: *const DirtyCellTracker, layer: WorldLayerId, buf: []u8) !?[]const u8 {
    const dirty = latestDirtyForLayer(tracker, layer) orelse return null;
    return try std.fmt.bufPrint(buf, "dirty {d},{d}", .{ dirty.cell.x, dirty.cell.y });
}

pub fn formatLayerDirtyStatus(tracker: *const DirtyCellTracker, layer: WorldLayerId, buf: []u8) !?[]const u8 {
    const dirty = latestDirtyForLayer(tracker, layer) orelse return null;
    return try std.fmt.bufPrint(buf, "Pending bake: cell {d},{d},{d} ({s})", .{
        dirty.cell.x,
        dirty.cell.y,
        dirty.cell.z,
        dirtyChangeDisplayLabel(dirty.last_change),
    });
}

pub fn dirtyChangeDisplayLabel(change: []const u8) []const u8 {
    if (std.mem.eql(u8, change, "road graph")) return "road";
    if (std.mem.eql(u8, change, "path spline")) return "path";
    if (std.mem.eql(u8, change, "exclusion zone")) return "blocked scatter area";
    if (std.mem.eql(u8, change, "volumes")) return "water shape";
    return change;
}

pub fn dirtyForCell(tracker: *const DirtyCellTracker, id: world.cell.CellId) ?DirtyCell {
    var latest: ?DirtyCell = null;
    for (tracker.cells[0..tracker.count]) |dirty| {
        if (!dirty.cell.eql(id)) continue;
        if (latest == null or dirty.sequence > latest.?.sequence) latest = dirty;
    }
    return latest;
}

fn latestDirtyForLayer(tracker: *const DirtyCellTracker, layer: WorldLayerId) ?DirtyCell {
    var latest: ?DirtyCell = null;
    for (tracker.cells[0..tracker.count]) |dirty| {
        if (!dirtyMatchesLayer(dirty, layer)) continue;
        if (latest == null or dirty.sequence > latest.?.sequence) latest = dirty;
    }
    return latest;
}

fn dirtyMatchesLayer(dirty: DirtyCell, layer: WorldLayerId) bool {
    if (!std.mem.eql(u8, dirty.layer_name, layer.groupLabel())) return false;
    return switch (layer) {
        .terrain_base_height => std.mem.eql(u8, dirty.last_change, "height brush") or std.mem.eql(u8, dirty.last_change, "new cell") or std.mem.eql(u8, dirty.last_change, "deleted cell"),
        .terrain_erosion_mask => std.mem.eql(u8, dirty.last_change, "erosion brush"),
        .terrain_material_tiles => std.mem.eql(u8, dirty.last_change, "material tile"),
        .spline_road_main => std.mem.eql(u8, dirty.last_change, "road graph"),
        .spline_path_side => std.mem.eql(u8, dirty.last_change, "path spline"),
        .scatter_grass_low, .scatter_pine_cluster, .scatter_rocks_medium => std.mem.eql(u8, dirty.last_change, layer.label()) or std.mem.eql(u8, dirty.last_change, "exclusion zone"),
        .scatter_density_mask => std.mem.eql(u8, dirty.last_change, "density mask"),
        .atmosphere_fog_bank => std.mem.eql(u8, dirty.last_change, "fog bank"),
        .atmosphere_sky_tone => std.mem.eql(u8, dirty.last_change, "sky tone"),
        .ocean_wind => std.mem.eql(u8, dirty.last_change, "wind") or std.mem.eql(u8, dirty.last_change, "waves"),
        .ocean_waves => std.mem.eql(u8, dirty.last_change, "waves"),
        .water_volumes => std.mem.eql(u8, dirty.last_change, "volumes"),
        .water_surface => std.mem.eql(u8, dirty.last_change, "surface") or std.mem.eql(u8, dirty.last_change, "volumes"),
        .water_currents => std.mem.eql(u8, dirty.last_change, "currents") or std.mem.eql(u8, dirty.last_change, "volumes"),
    };
}

test "world layer dirty badge matches exact authored layer" {
    var tracker = DirtyCellTracker{};
    try tracker.mark("Terrain", .{ .x = 1, .y = 2, .z = 0 }, "height brush");
    try tracker.mark("Terrain", .{ .x = 3, .y = 4, .z = 0 }, "material tile");
    try tracker.mark("Scatter", .{ .x = 5, .y = 6, .z = 0 }, "pine_cluster");

    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("dirty 1,2", (try formatLayerDirtyBadge(&tracker, .terrain_base_height, &buf)).?);
    try std.testing.expectEqualStrings("dirty 3,4", (try formatLayerDirtyBadge(&tracker, .terrain_material_tiles, &buf)).?);
    try std.testing.expectEqualStrings("dirty 5,6", (try formatLayerDirtyBadge(&tracker, .scatter_pine_cluster, &buf)).?);
    try std.testing.expect((try formatLayerDirtyBadge(&tracker, .terrain_erosion_mask, &buf)) == null);
    try std.testing.expect((try formatLayerDirtyBadge(&tracker, .scatter_grass_low, &buf)) == null);
}

test "world layer dirty status uses newest matching change" {
    var tracker = DirtyCellTracker{};
    try tracker.mark("Splines", .{ .x = 0, .y = 0, .z = 0 }, "road graph");
    try tracker.mark("Splines", .{ .x = 2, .y = 1, .z = 0 }, "path spline");
    try tracker.mark("Splines", .{ .x = 4, .y = 3, .z = 0 }, "road graph");

    var buf: [96]u8 = undefined;
    try std.testing.expectEqualStrings(
        "Pending bake: cell 4,3,0 (road)",
        (try formatLayerDirtyStatus(&tracker, .spline_road_main, &buf)).?,
    );
    try std.testing.expectEqualStrings(
        "Pending bake: cell 2,1,0 (path)",
        (try formatLayerDirtyStatus(&tracker, .spline_path_side, &buf)).?,
    );
}
