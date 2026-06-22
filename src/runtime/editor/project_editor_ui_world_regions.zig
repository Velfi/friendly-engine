const std = @import("std");
const friendly_engine = @import("friendly_engine");

const project_editor_state = @import("project_editor_state.zig");
const project_editor_types = @import("project_editor_types.zig");
const project_editor_ui_widgets = @import("project_editor_ui_widgets.zig");
const project_editor_ui_world_dirty = @import("project_editor_ui_world_dirty.zig");
const world_manifest_authoring = @import("project_editor_world_authoring_manifest.zig");

const core_ui = friendly_engine.modules.core_ui;
const ProjectEditorState = project_editor_state.ProjectEditorState;
const ui_widgets = project_editor_ui_widgets;
const world = friendly_engine.world;

const max_terrain_cell_rows = 128;
pub const unassigned_region_id = "__unassigned";

pub fn buildTerrainCellsPanel(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    _ = try ui_widgets.treeRow(ui, "Map Areas", &state.show_world_cells_group);
    if (!state.show_world_cells_group) return;

    const world_cache = state.ensureWorldCache() catch {
        try ui_widgets.compactInfo(ui, "World manifest failed to load");
        return;
    };
    const loaded_manifest = world_cache.manifest;
    const loaded_regions = world_cache.regions;

    var cell_region_lookup = std.AutoHashMap(world.cell.CellId, usize).init(state.allocator);
    defer cell_region_lookup.deinit();
    if (loaded_regions) |regions| {
        for (regions.regions, 0..) |region, index| {
            for (region.cells) |id| try cell_region_lookup.put(id, index);
        }
    }
    var resident_lookup = std.AutoHashMap(world.cell.CellId, void).init(state.allocator);
    defer resident_lookup.deinit();
    try resident_lookup.ensureTotalCapacity(@intCast(state.terrain_preview.entries.items.len));
    for (state.terrain_preview.entries.items) |entry| {
        resident_lookup.putAssumeCapacity(entry.snapshot.cell, {});
    }

    var summaries = try buildRegionSummaries(state, loaded_manifest, loaded_regions, &cell_region_lookup, &resident_lookup);
    defer summaries.deinit(state.allocator);

    const real_region_count: usize = if (loaded_regions) |regions| regions.regions.len else 0;
    var count_buf: [96]u8 = undefined;
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(
        &count_buf,
        "{d} areas  {d} cells  {d:.0}m grid  {d} loaded",
        .{ real_region_count, loaded_manifest.cells.len, loaded_manifest.cell_size_m, state.terrain_preview.entries.items.len },
    ) catch "Map areas");

    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.button(ui, "ed-world-new-region", "New Area", 96, false)).clicked) {
        createEmptyWorldRegion(state) catch project_editor_state.setStatus(state, "Region create failed");
        return;
    }
    if ((try ui_widgets.button(ui, "ed-world-region-paint-toggle", "Paint Area", 104, state.world_region_paint_enabled)).clicked) {
        state.world_region_paint_enabled = !state.world_region_paint_enabled;
        switchToPaintTool(state);
    }
    try core_ui.layout.endSameLine(ui);

    if (try buildSelectedRegionControls(ui, state, loaded_regions)) return;

    for (summaries.items) |summary| {
        try buildTerrainRegionRow(ui, state, summary);
    }
    if (try buildRegionContextMenu(ui, state, loaded_regions)) return;

    const selected_region = selectedRegionId(state) orelse return;
    var shown: usize = 0;
    var hidden: usize = 0;
    for (loaded_manifest.cells) |entry| {
        if (!cellBelongsToSelectedRegion(entry.id, selected_region, loaded_regions, &cell_region_lookup)) continue;
        if (shown >= max_terrain_cell_rows) {
            hidden += 1;
            continue;
        }
        try buildTerrainCellRow(ui, state, entry, resident_lookup.contains(entry.id));
        shown += 1;
    }
    if (shown > 0 or hidden > 0) {
        var cell_buf: [96]u8 = undefined;
        try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&cell_buf, "{d} shown  {d} hidden in selected area", .{ shown, hidden }) catch "Selected area cells");
    }
}

const RegionSummary = struct {
    id: []const u8,
    name: []const u8,
    cells: usize = 0,
    resident: usize = 0,
    dirty: usize = 0,
    min_x: i32 = std.math.maxInt(i32),
    max_x: i32 = std.math.minInt(i32),
    min_y: i32 = std.math.maxInt(i32),
    max_y: i32 = std.math.minInt(i32),
    preview_mask: u16 = 0,
};

fn buildRegionSummaries(
    state: *ProjectEditorState,
    manifest: *const world.manifest.OwnedWorldManifest,
    regions: ?*const world.regions.OwnedRegions,
    cell_region_lookup: *const std.AutoHashMap(world.cell.CellId, usize),
    resident_lookup: *const std.AutoHashMap(world.cell.CellId, void),
) !std.ArrayList(RegionSummary) {
    var summaries = std.ArrayList(RegionSummary).empty;
    errdefer summaries.deinit(state.allocator);

    if (regions) |owned| {
        for (owned.regions) |region| {
            try summaries.append(state.allocator, .{ .id = region.id, .name = region.name });
        }
    }
    const unassigned_index = summaries.items.len;
    try summaries.append(state.allocator, .{ .id = unassigned_region_id, .name = "Cells with no area" });

    for (manifest.cells) |entry| {
        const summary_index = cell_region_lookup.get(entry.id) orelse unassigned_index;
        updateRegionSummary(&summaries.items[summary_index], state, entry.id, resident_lookup.contains(entry.id));
    }
    for (manifest.cells) |entry| {
        const summary_index = cell_region_lookup.get(entry.id) orelse unassigned_index;
        updateRegionPreview(&summaries.items[summary_index], entry.id);
    }
    return summaries;
}

fn updateRegionSummary(summary: *RegionSummary, state: *const ProjectEditorState, id: world.cell.CellId, resident: bool) void {
    summary.cells += 1;
    if (resident) summary.resident += 1;
    if (project_editor_ui_world_dirty.dirtyForCell(&state.dirty_cells, id) != null) summary.dirty += 1;
    summary.min_x = @min(summary.min_x, id.x);
    summary.max_x = @max(summary.max_x, id.x);
    summary.min_y = @min(summary.min_y, id.y);
    summary.max_y = @max(summary.max_y, id.y);
}

fn updateRegionPreview(summary: *RegionSummary, id: world.cell.CellId) void {
    if (summary.cells == 0) return;
    const span_x = @max(1, summary.max_x - summary.min_x + 1);
    const span_y = @max(1, summary.max_y - summary.min_y + 1);
    const local_x = id.x - summary.min_x;
    const local_y = id.y - summary.min_y;
    const grid_x: usize = @intCast(@divTrunc(local_x * 4, span_x));
    const grid_y: usize = @intCast(@divTrunc(local_y * 4, span_y));
    const clamped_x = @min(grid_x, 3);
    const clamped_y = @min(grid_y, 3);
    const bit: u4 = @intCast(clamped_y * @as(usize, 4) + clamped_x);
    summary.preview_mask |= @as(u16, 1) << bit;
}

fn buildSelectedRegionControls(ui: *core_ui.UiContext, state: *ProjectEditorState, regions: ?*const world.regions.OwnedRegions) !bool {
    const selected_region = selectedRegionId(state) orelse return false;
    if (std.mem.eql(u8, selected_region, unassigned_region_id)) {
        try ui_widgets.compactInfo(ui, "These cells are not assigned to an area yet");
        return false;
    }
    const owned = regions orelse return false;
    const region = findRegionById(owned, selected_region) orelse return false;

    var label_buf: [96]u8 = undefined;
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&label_buf, "Selected area: {s}", .{region.name}) catch "Selected area");
    var count_buf: [96]u8 = undefined;
    try ui_widgets.compactInfo(ui, areaCellCountText(&count_buf, region.cells.len));

    var confirm_id_buf: [112]u8 = undefined;
    const confirm_id = std.fmt.bufPrint(&confirm_id_buf, "ed-world-region-delete-confirm-{s}", .{region.id}) catch "ed-world-region-delete-confirm";
    const confirm_key = try ui.stableId(confirm_id, confirm_id);
    var confirm_delete = try ui.getBoolState(confirm_key, false);

    var changed = false;

    if (renameActiveForRegion(state, region.id)) {
        var input_id_buf: [96]u8 = undefined;
        const input_id = std.fmt.bufPrint(&input_id_buf, "ed-world-region-name-{s}", .{region.id}) catch "ed-world-region-name";
        const name_input = try core_ui.widgets_input.textInput(ui, .{ .id = input_id, .default_text = region.name });
        if (name_input.submitted) {
            if (try saveRegionName(state, region.id, name_input.text)) {
                state.world_region_rename_active = false;
                try ui.setBoolState(confirm_key, false);
                changed = true;
            }
        }
        try core_ui.layout.sameLine(ui);
        if ((try ui_widgets.button(ui, "ed-world-region-rename", "Save Name", 92, false)).clicked) {
            if (try saveRegionName(state, region.id, name_input.text)) {
                state.world_region_rename_active = false;
                try ui.setBoolState(confirm_key, false);
                changed = true;
            }
        }
        if ((try ui_widgets.button(ui, "ed-world-region-rename-cancel", "Cancel", 70, false)).clicked) {
            state.world_region_rename_active = false;
            project_editor_state.setStatus(state, "Rename canceled");
        }
        try core_ui.layout.endSameLine(ui);
        return changed;
    }

    try ui_widgets.compactInfo(ui, "Right-click an area for Rename, Delete, and Paint actions");

    try core_ui.layout.sameLine(ui);
    const delete_label: []const u8 = if (confirm_delete) "Delete Now" else "Delete Area";
    if ((try ui_widgets.button(ui, "ed-world-region-delete", delete_label, 104, confirm_delete)).clicked) {
        if (confirm_delete) {
            deleteWorldRegion(state, region.id) catch project_editor_state.setStatus(state, "Area delete failed");
            try ui.setBoolState(confirm_key, false);
            changed = true;
        } else {
            confirm_delete = true;
            try ui.setBoolState(confirm_key, true);
            project_editor_state.setStatus(state, if (region.cells.len == 0) "Click Delete Now to remove this empty area" else "Click Delete Now to remove this area; its cells will become unassigned");
        }
    }
    if (confirm_delete and (try ui_widgets.button(ui, "ed-world-region-delete-cancel", "Cancel", 70, false)).clicked) {
        confirm_delete = false;
        try ui.setBoolState(confirm_key, false);
        project_editor_state.setStatus(state, "Delete canceled");
    }
    try core_ui.layout.endSameLine(ui);
    if (confirm_delete) {
        try ui_widgets.compactInfo(ui, if (region.cells.len == 0) "This empty area will be removed." else "Deleting keeps the terrain cells, but removes them from this area.");
    }
    return changed;
}

fn buildRegionContextMenu(ui: *core_ui.UiContext, state: *ProjectEditorState, regions: ?*const world.regions.OwnedRegions) !bool {
    if (!state.world_region_context_menu_open) return false;
    const menu_region_id = contextMenuRegionId(state) orelse {
        closeRegionContextMenu(state);
        return false;
    };
    if (std.mem.eql(u8, menu_region_id, unassigned_region_id)) {
        closeRegionContextMenu(state);
        return false;
    }
    const owned = regions orelse {
        closeRegionContextMenu(state);
        return false;
    };
    const region = findRegionById(owned, menu_region_id) orelse {
        closeRegionContextMenu(state);
        return false;
    };

    const menu_w: f32 = 190;
    const row_h: f32 = 26;
    const menu_h: f32 = row_h * 5 + 10;
    const x = clampMenuX(ui, state.world_region_context_menu_x, menu_w);
    const y = clampMenuY(ui, state.world_region_context_menu_y, menu_h);
    const rect = core_ui.Rect{ .x = x, .y = y, .w = menu_w, .h = menu_h };

    if ((ui.input.primary_pressed or ui.input.right_button_pressed) and !rect.contains(ui.input.mouse_position)) {
        closeRegionContextMenu(state);
        return false;
    }

    try ui.beginPanel(.{
        .id = "ed-world-region-context-menu",
        .rect = rect,
        .row_height = row_h,
        .padding = 5,
        .spacing = 2,
    });
    defer ui.endPanel();

    if ((try ui_widgets.button(ui, "ed-world-region-menu-rename", "Rename", menu_w - 10, false)).clicked) {
        beginRenameRegion(state, region.id);
        closeRegionContextMenu(state);
        project_editor_state.setStatus(state, "Rename the area, then save");
        return false;
    }
    if ((try ui_widgets.button(ui, "ed-world-region-menu-zoom", "Zoom To", menu_w - 10, false)).clicked) {
        zoomToRegion(state, region) catch project_editor_state.setStatus(state, "Zoom failed");
        closeRegionContextMenu(state);
        return false;
    }
    if ((try ui_widgets.button(ui, "ed-world-region-menu-paint", "Paint This Area", menu_w - 10, false)).clicked) {
        selectRegion(state, region.id);
        switchToPaintTool(state);
        state.world_region_paint_enabled = true;
        state.world_region_paint_erase = false;
        closeRegionContextMenu(state);
        project_editor_state.setStatus(state, "Paint cells into this area");
        return false;
    }
    if ((try ui_widgets.button(ui, "ed-world-region-menu-remove-cells", "Remove Cells Brush", menu_w - 10, false)).clicked) {
        selectRegion(state, region.id);
        switchToPaintTool(state);
        state.world_region_paint_enabled = true;
        state.world_region_paint_erase = true;
        closeRegionContextMenu(state);
        project_editor_state.setStatus(state, "Brush cells out of this area");
        return false;
    }
    if ((try ui_widgets.button(ui, "ed-world-region-menu-delete", "Delete Area...", menu_w - 10, false)).clicked) {
        var confirm_id_buf: [112]u8 = undefined;
        const confirm_id = std.fmt.bufPrint(&confirm_id_buf, "ed-world-region-delete-confirm-{s}", .{region.id}) catch "ed-world-region-delete-confirm";
        try ui.setBoolState(try ui.stableId(confirm_id, confirm_id), true);
        selectRegion(state, region.id);
        closeRegionContextMenu(state);
        project_editor_state.setStatus(state, if (region.cells.len == 0) "Click Delete Now to remove this empty area" else "Click Delete Now to remove this area; its cells will become unassigned");
        return false;
    }
    return false;
}

fn findRegionById(regions: *const world.regions.OwnedRegions, id: []const u8) ?world.regions.Region {
    for (regions.regions) |region| {
        if (std.mem.eql(u8, region.id, id)) return region;
    }
    return null;
}

fn buildTerrainRegionRow(ui: *core_ui.UiContext, state: *ProjectEditorState, summary: RegionSummary) !void {
    const selected = if (selectedRegionId(state)) |id| std.mem.eql(u8, id, summary.id) else false;
    var detail_buf: [160]u8 = undefined;
    const detail = if (summary.cells == 0)
        std.fmt.bufPrint(&detail_buf, "No cells yet. Select it, then paint cells into this area.", .{}) catch "Map area"
    else
        std.fmt.bufPrint(
            &detail_buf,
            "{d} cells  {d} loaded  {d} unsaved",
            .{ summary.cells, summary.resident, summary.dirty },
        ) catch "Map area";
    var row_id_buf: [96]u8 = undefined;
    const row_id = std.fmt.bufPrint(&row_id_buf, "ed-world-region-{s}", .{summary.id}) catch "ed-world-region";
    const row = try ui_widgets.assetPreview(ui, .{
        .id = row_id,
        .label = summary.name,
        .detail = detail,
        .fill_color = if (summary.dirty > 0)
            .{ .r = 214, .g = 142, .b = 68, .a = 255 }
        else if (summary.resident > 0)
            .{ .r = 78, .g = 124, .b = 55, .a = 255 }
        else
            .{ .r = 73, .g = 81, .b = 92, .a = 255 },
        .shape = .region_map,
        .preview_mask = summary.preview_mask,
        .selected = selected,
    });
    if (row.clicked) {
        selectRegion(state, summary.id);
        closeRegionContextMenu(state);
    }
    if (row.hovered and ui.input.right_button_pressed) {
        selectRegion(state, summary.id);
        if (!std.mem.eql(u8, summary.id, unassigned_region_id)) {
            openRegionContextMenu(state, summary.id, ui.input.mouse_position.x, ui.input.mouse_position.y);
        } else {
            closeRegionContextMenu(state);
            project_editor_state.setStatus(state, "Cells with no area do not have area actions");
        }
    }
}

fn createEmptyWorldRegion(state: *ProjectEditorState) !void {
    var loaded = try world.regions.loadOrEmpty(state.allocator, state.io, state.project_path, world.regions.default_regions_path);
    defer loaded.deinit();

    var id_buf: [64]u8 = undefined;
    var name_buf: [64]u8 = undefined;
    var index: usize = loaded.regions.len + 1;
    while (true) : (index += 1) {
        const id = try std.fmt.bufPrint(&id_buf, "region-{d}", .{index});
        var exists = false;
        for (loaded.regions) |region| {
            if (std.mem.eql(u8, region.id, id)) {
                exists = true;
                break;
            }
        }
        if (exists) continue;

        const name = try std.fmt.bufPrint(&name_buf, "Region {d}", .{index});
        const empty_cells = [_]world.cell.CellId{};
        var saved = try world.regions.upsertRegion(state.allocator, state.io, state.project_path, world.regions.default_regions_path, .{
            .id = id,
            .name = name,
            .cells = &empty_cells,
        });
        defer saved.deinit();
        selectRegion(state, id);
        switchToPaintTool(state);
        state.world_region_paint_enabled = true;
        state.world_region_paint_erase = false;
        state.terrain_preview_stale = true;
        state.invalidateWorldCache();
        project_editor_state.setStatus(state, "New map area ready to paint");
        return;
    }
}

fn saveRegionName(state: *ProjectEditorState, id: []const u8, raw_name: []const u8) !bool {
    const trimmed = std.mem.trim(u8, raw_name, " \t\r\n");
    if (trimmed.len == 0) {
        project_editor_state.setStatus(state, "Area name cannot be empty");
        return false;
    }
    renameWorldRegion(state, id, trimmed) catch {
        project_editor_state.setStatus(state, "Area rename failed");
        return false;
    };
    return true;
}

fn renameWorldRegion(state: *ProjectEditorState, id: []const u8, new_name: []const u8) !void {
    var loaded = try world.regions.loadOrEmpty(state.allocator, state.io, state.project_path, world.regions.default_regions_path);
    defer loaded.deinit();
    const region = findRegionById(&loaded, id) orelse return error.WorldRegionNotFound;
    var saved = try world.regions.upsertRegion(state.allocator, state.io, state.project_path, world.regions.default_regions_path, .{
        .id = region.id,
        .name = new_name,
        .props = region.props,
        .cells = region.cells,
    });
    defer saved.deinit();
    selectRegion(state, id);
    state.invalidateWorldCache();
    project_editor_state.setStatus(state, "Map area renamed");
}

fn deleteWorldRegion(state: *ProjectEditorState, id: []const u8) !void {
    var saved = try world.regions.deleteRegion(state.allocator, state.io, state.project_path, world.regions.default_regions_path, id);
    defer saved.deinit();
    if (selectedRegionId(state)) |selected| {
        if (std.mem.eql(u8, selected, id)) state.selected_world_region_id_len = 0;
    }
    state.world_region_paint_enabled = false;
    state.invalidateWorldCache();
    project_editor_state.setStatus(state, "Map area deleted");
}

pub fn selectedRegionId(state: *const ProjectEditorState) ?[]const u8 {
    if (state.selected_world_region_id_len == 0) return null;
    return state.selected_world_region_id[0..state.selected_world_region_id_len];
}

fn contextMenuRegionId(state: *const ProjectEditorState) ?[]const u8 {
    if (state.world_region_context_menu_id_len == 0) return null;
    return state.world_region_context_menu_id[0..state.world_region_context_menu_id_len];
}

pub fn selectRegion(state: *ProjectEditorState, id: []const u8) void {
    state.selected_world_region_id_len = @min(id.len, state.selected_world_region_id.len);
    @memcpy(state.selected_world_region_id[0..state.selected_world_region_id_len], id[0..state.selected_world_region_id_len]);
    var buf: [128]u8 = undefined;
    project_editor_state.setStatus(state, std.fmt.bufPrint(&buf, "Selected map area {s}", .{id}) catch "Selected map area");
}

fn openRegionContextMenu(state: *ProjectEditorState, id: []const u8, x: f32, y: f32) void {
    state.world_region_context_menu_open = true;
    state.world_region_context_menu_id_len = @min(id.len, state.world_region_context_menu_id.len);
    @memcpy(state.world_region_context_menu_id[0..state.world_region_context_menu_id_len], id[0..state.world_region_context_menu_id_len]);
    state.world_region_context_menu_x = x;
    state.world_region_context_menu_y = y;
}

fn closeRegionContextMenu(state: *ProjectEditorState) void {
    state.world_region_context_menu_open = false;
    state.world_region_context_menu_id_len = 0;
}

fn beginRenameRegion(state: *ProjectEditorState, id: []const u8) void {
    selectRegion(state, id);
    state.world_region_rename_active = true;
    state.world_region_rename_id_len = @min(id.len, state.world_region_rename_id.len);
    @memcpy(state.world_region_rename_id[0..state.world_region_rename_id_len], id[0..state.world_region_rename_id_len]);
}

fn renameActiveForRegion(state: *const ProjectEditorState, id: []const u8) bool {
    return state.world_region_rename_active and
        state.world_region_rename_id_len == id.len and
        std.mem.eql(u8, state.world_region_rename_id[0..state.world_region_rename_id_len], id);
}

fn zoomToRegion(state: *ProjectEditorState, region: world.regions.Region) !void {
    if (region.cells.len == 0) {
        selectRegion(state, region.id);
        project_editor_state.setStatus(state, "This area has no cells to zoom to yet");
        return;
    }

    var min_x: i32 = std.math.maxInt(i32);
    var max_x: i32 = std.math.minInt(i32);
    var min_y: i32 = std.math.maxInt(i32);
    var max_y: i32 = std.math.minInt(i32);
    for (region.cells) |cell| {
        min_x = @min(min_x, cell.x);
        max_x = @max(max_x, cell.x);
        min_y = @min(min_y, cell.y);
        max_y = @max(max_y, cell.y);
    }

    const min_center = world_manifest_authoring.cellCenter(.{ .x = min_x, .y = min_y, .z = 0 }, state.world_cell_size_m);
    const max_center = world_manifest_authoring.cellCenter(.{ .x = max_x, .y = max_y, .z = 0 }, state.world_cell_size_m);
    state.camera.target = .{
        .x = (min_center.x + max_center.x) * 0.5,
        .y = 0,
        .z = (min_center.z + max_center.z) * 0.5,
    };

    const span_x = @max(state.world_cell_size_m, @abs(max_center.x - min_center.x) + state.world_cell_size_m);
    const span_z = @max(state.world_cell_size_m, @abs(max_center.z - min_center.z) + state.world_cell_size_m);
    const radius = @max(span_x, span_z) * 0.5;
    state.camera.distance = std.math.clamp(@max(radius * 2.8, 12.0), state.camera.min_distance, state.camera.max_distance);
    selectRegion(state, region.id);
    state.view_orientation = .free;
    project_editor_state.setStatus(state, "Zoomed to map area");
}

fn clampMenuX(ui: *const core_ui.UiContext, x: f32, w: f32) f32 {
    if (ui.frame_bounds.w <= 0) return x;
    return @min(@max(ui.frame_bounds.x, x), @max(ui.frame_bounds.x, ui.frame_bounds.x + ui.frame_bounds.w - w - 4));
}

fn clampMenuY(ui: *const core_ui.UiContext, y: f32, h: f32) f32 {
    if (ui.frame_bounds.h <= 0) return y;
    return @min(@max(ui.frame_bounds.y, y), @max(ui.frame_bounds.y, ui.frame_bounds.y + ui.frame_bounds.h - h - 4));
}

fn areaCellCountText(buf: []u8, count: usize) []const u8 {
    if (count == 0) return "No cells yet";
    return std.fmt.bufPrint(buf, "{d} {s} in this area", .{ count, if (count == 1) "cell" else "cells" }) catch "Area cells";
}

fn cellBelongsToSelectedRegion(
    id: world.cell.CellId,
    selected_region: []const u8,
    regions: ?*const world.regions.OwnedRegions,
    cell_region_lookup: *const std.AutoHashMap(world.cell.CellId, usize),
) bool {
    if (std.mem.eql(u8, selected_region, unassigned_region_id)) return cell_region_lookup.get(id) == null;
    const owned = regions orelse return false;
    const region_index = cell_region_lookup.get(id) orelse return false;
    return std.mem.eql(u8, owned.regions[region_index].id, selected_region);
}

fn buildTerrainCellRow(
    ui: *core_ui.UiContext,
    state: *ProjectEditorState,
    entry: world.manifest.ManifestCell,
    resident: bool,
) !void {
    const id = entry.id;
    const selected = if (state.selected_world_cell) |selected_id| selected_id.eql(id) else false;
    const dirty = project_editor_ui_world_dirty.dirtyForCell(&state.dirty_cells, id);

    var label_buf: [96]u8 = undefined;
    const label = std.fmt.bufPrint(
        &label_buf,
        "Cell {d},{d},{d}",
        .{
            id.x,
            id.y,
            id.z,
        },
    ) catch "  cell";
    var detail_buf: [192]u8 = undefined;
    const detail = std.fmt.bufPrint(
        &detail_buf,
        "{s}{s}  {s}",
        .{
            if (resident) "resident" else "streamable",
            if (dirty != null) "  dirty" else "",
            entry.authoring_path,
        },
    ) catch entry.authoring_path;
    var row_id_buf: [64]u8 = undefined;
    const row_id = std.fmt.bufPrint(&row_id_buf, "ed-world-cell-{d}-{d}-{d}", .{ id.x, id.y, id.z }) catch "ed-world-cell";
    const row = try ui_widgets.assetPreview(ui, .{
        .id = row_id,
        .label = label,
        .detail = detail,
        .fill_color = if (dirty != null)
            .{ .r = 214, .g = 142, .b = 68, .a = 255 }
        else if (resident)
            .{ .r = 78, .g = 124, .b = 55, .a = 255 }
        else
            .{ .r = 73, .g = 81, .b = 92, .a = 255 },
        .shape = .plane,
        .selected = selected,
    });
    if (row.clicked) selectManifestCell(state, id);
}

fn selectManifestCell(state: *ProjectEditorState, id: world.cell.CellId) void {
    state.selected_world_cell = id;
    state.camera.target = world_manifest_authoring.cellCenter(id, state.world_cell_size_m);
    var buf: [96]u8 = undefined;
    project_editor_state.setStatus(state, std.fmt.bufPrint(
        &buf,
        "Selected terrain cell {d},{d},{d}",
        .{ id.x, id.y, id.z },
    ) catch "Selected terrain cell");
}

fn switchToPaintTool(state: *ProjectEditorState) void {
    if (state.world_tool == .paint) return;
    state.hovered_world_curve_hit = .{};
    state.world_curve_drag_state = .{};
    state.world_curve_drag_anchor = null;
    if (state.selected_road_edge_id) |id| state.allocator.free(id);
    state.selected_road_edge_id = null;
    if (state.selected_road_node_id) |id| state.allocator.free(id);
    state.selected_road_node_id = null;
    state.selected_road_handle = .none;
    state.selected_ocean_clip_point = null;
    state.selected_world_curve_hit = .{};
    state.world_road_points.clearRetainingCapacity();
    state.world_road_preview_end = null;
    state.world_tool = .paint;
}
