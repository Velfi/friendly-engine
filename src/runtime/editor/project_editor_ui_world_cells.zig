const std = @import("std");
const friendly_engine = @import("friendly_engine");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_world_authoring = @import("project_editor_world_authoring.zig");
const world_manifest_authoring = @import("project_editor_world_authoring_manifest.zig");
const project_editor_ui_widgets = @import("project_editor_ui_widgets.zig");
const project_editor_ui_world_dirty = @import("project_editor_ui_world_dirty.zig");

const core_ui = friendly_engine.modules.core_ui;
const ProjectEditorState = project_editor_state.ProjectEditorState;
const ui_widgets = project_editor_ui_widgets;
const world = friendly_engine.world;

pub fn buildSelectedCellInspector(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    if ((try ui_widgets.collapsible(ui, "Selected Cell", true))) {
        const id = state.selected_world_cell orelse {
            try ui_widgets.compactInfo(ui, "No cell selected");
            return;
        };

        var coord_buf: [80]u8 = undefined;
        try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&coord_buf, "Coord {d},{d},{d}", .{ id.x, id.y, id.z }) catch "Coord");

        const manifest_stats = loadSelectedCellManifestStats(state, id) catch null;
        if (manifest_stats) |stats| {
            var size_buf: [64]u8 = undefined;
            try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&size_buf, "World cell {d:.0}m", .{stats.cell_size_m}) catch "World cell");
            try ui_widgets.compactInfo(ui, stats.authoring_path);
            state.allocator.free(stats.authoring_path);
        } else {
            try ui_widgets.compactInfo(ui, "Not in manifest");
        }

        const terrain_stats = loadSelectedCellTerrainStats(state, id) catch null;
        if (terrain_stats) |stats| {
            var tile_buf: [96]u8 = undefined;
            try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&tile_buf, "Terrain tile {d}x{d}  LODs {d}", .{ stats.size, stats.size, stats.lod_count }) catch "Terrain tile");
            var height_buf: [128]u8 = undefined;
            try ui_widgets.compactInfo(ui, std.fmt.bufPrint(
                &height_buf,
                "Height min {d:.2}  max {d:.2}  avg {d:.2}",
                .{ stats.min_height, stats.max_height, stats.avg_height },
            ) catch "Height stats");
            var material_buf: [96]u8 = undefined;
            try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&material_buf, "Material {s}", .{stats.material}) catch "Material");
            state.allocator.free(stats.material);
        } else {
            try ui_widgets.compactInfo(ui, "No terrain tile");
        }

        if (project_editor_ui_world_dirty.dirtyForCell(&state.dirty_cells, id)) |dirty| {
            var dirty_buf: [96]u8 = undefined;
            try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&dirty_buf, "Dirty {s}: {s}", .{ dirty.layer_name, project_editor_ui_world_dirty.dirtyChangeDisplayLabel(dirty.last_change) }) catch "Dirty");
        } else {
            try ui_widgets.compactInfo(ui, "Clean");
        }

        try core_ui.layout.sameLine(ui);
        if ((try ui_widgets.buttonTip(ui, "ed-world-selected-create-cell", "Create", 72, false, "Create terrain cell here")).clicked) {
            createSelectedTerrainCell(state) catch {
                project_editor_state.setStatus(state, "Terrain cell create failed");
            };
        }
        if ((try ui_widgets.buttonTip(ui, "ed-world-selected-delete-cell", "Delete", 72, false, "Delete terrain tile here")).clicked) {
            deleteSelectedTerrainCell(state) catch {
                project_editor_state.setStatus(state, "Terrain cell delete failed");
            };
        }
        try core_ui.layout.endSameLine(ui);
    }
}

const SelectedCellManifestStats = struct {
    cell_size_m: f32,
    authoring_path: []u8,
};

fn loadSelectedCellManifestStats(state: *ProjectEditorState, id: world.cell.CellId) !?SelectedCellManifestStats {
    var loaded_manifest = try world.manifest.loadManifest(state.allocator, state.io, state.project_path, try world_manifest_authoring.pathForState(state));
    defer loaded_manifest.deinit();
    state.world_cell_size_m = loaded_manifest.cell_size_m;
    const entry = loaded_manifest.findCell(id) orelse return null;
    return .{
        .cell_size_m = loaded_manifest.cell_size_m,
        .authoring_path = try state.allocator.dupe(u8, entry.authoring_path),
    };
}

const SelectedCellTerrainStats = struct {
    size: u32,
    lod_count: usize,
    min_height: f32,
    max_height: f32,
    avg_height: f32,
    material: []u8,
};

fn loadSelectedCellTerrainStats(state: *ProjectEditorState, id: world.cell.CellId) !?SelectedCellTerrainStats {
    const doc = try friendly_engine.modules.terrain.authoring.loadCell(
        state.allocator,
        state.io,
        state.project_path,
        try world_manifest_authoring.pathForState(state),
        id,
    );
    if (doc == null) return null;
    var owned_doc = doc.?;
    defer owned_doc.deinit();
    if (owned_doc.tiles.items.len != 1) return error.InvalidTerrainDocument;

    const tile = owned_doc.tiles.items[0];
    if (tile.heights.len == 0) return error.InvalidTerrainHeightCount;
    var min_height = tile.heights[0];
    var max_height = tile.heights[0];
    var sum: f32 = 0;
    for (tile.heights) |height| {
        min_height = @min(min_height, height);
        max_height = @max(max_height, height);
        sum += height;
    }
    return .{
        .size = tile.size,
        .lod_count = tile.lod_levels.len,
        .min_height = min_height,
        .max_height = max_height,
        .avg_height = sum / @as(f32, @floatFromInt(tile.heights.len)),
        .material = try state.allocator.dupe(u8, tile.material),
    };
}

fn createSelectedTerrainCell(state: *ProjectEditorState) !void {
    const id = state.selected_world_cell orelse {
        project_editor_state.setStatus(state, "Select a cell first");
        return;
    };
    try project_editor_world_authoring.createTerrainCellAt(state, world_manifest_authoring.cellCenter(id, state.world_cell_size_m));
    state.selected_world_cell = id;
}

fn deleteSelectedTerrainCell(state: *ProjectEditorState) !void {
    const id = state.selected_world_cell orelse {
        project_editor_state.setStatus(state, "Select a cell first");
        return;
    };
    try project_editor_world_authoring.deleteTerrainCellAt(state, world_manifest_authoring.cellCenter(id, state.world_cell_size_m));
    state.selected_world_cell = id;
}
