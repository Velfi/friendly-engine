const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const geometry = shared.geometry;
const editor_math = shared.editor_math;
const command_ids = shared.editor_command_ids;
const scene_resolve = shared.scene_resolve;
const prop_asset_doc = shared.prop_asset_doc;
const project_editor_edit = @import("project_editor_edit.zig");
const project_editor_materials = @import("project_editor_materials.zig");
const project_editor_physics = @import("project_editor_physics.zig");
const project_editor_prop = @import("project_editor_prop.zig");
const project_editor_prop_asset = @import("project_editor_prop_asset.zig");
const project_editor_prop_dialog = @import("project_editor_prop_dialog.zig");
const project_editor_prop_index = @import("project_editor_prop_index.zig");
const project_editor_scene = @import("project_editor_scene.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_texture_paint = @import("project_editor_texture_paint.zig");
const project_editor_types = @import("project_editor_types.zig");
const project_editor_viewport = @import("project_editor_viewport.zig");
const editor_raycast = @import("editor_raycast.zig");
const project_editor_mode_config = @import("project_editor_mode_config.zig");
const shape_operation = @import("shape_operation.zig");
const shape_source = @import("shape_source.zig");

const core_ui = friendly_engine.modules.core_ui;
const ProjectEditorState = project_editor_state.ProjectEditorState;
const OverlayQuad = shared.gpu_scene.OverlayQuad;
const PropTool = project_editor_types.PropTool;
const PropPrimitive = project_editor_types.PropPrimitive;
const PropPlacementMode = project_editor_types.PropPlacementMode;
const PropLibrarySort = project_editor_types.PropLibrarySort;
const PropLibraryCategoryFilter = project_editor_types.PropLibraryCategoryFilter;
const PropLibrarySourceFilter = project_editor_types.PropLibrarySourceFilter;
const PropAssetIndexRow = project_editor_types.PropAssetIndexRow;
const EditTool = project_editor_types.EditTool;
const ShadingMode = project_editor_types.ShadingMode;
const ui_widgets = @import("project_editor_ui_widgets.zig");

const max_display_library_rows = 16;

pub fn registerEditor(registry: *project_editor_mode_config.EditorRegistry) !void {
    try registry.registerMode(project_editor_mode_config.descForMode(.prop_creation).*);
}

const ProjectPropRow = struct {
    id: []u8,
    label: []u8,
    tags: []u8,
    color: shared.color.Color,
    source_count: usize,

    fn deinit(self: *ProjectPropRow, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.label);
        allocator.free(self.tags);
    }
};

pub fn buildBrowser(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    const rows = try project_editor_prop_index.ensure(state);
    var summary_buf: [80]u8 = undefined;
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&summary_buf, "{d} props  open + manage", .{visibleCatalogCount(state)}) catch "Props");
    var mode_buf: [96]u8 = undefined;
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&mode_buf, "Sort: {s}  Source: {s}", .{ librarySortLabel(state.prop_library_sort), librarySourceFilterLabel(state.prop_library_source_filter) }) catch "Library filters");
    try ui.label("Search");
    _ = try core_ui.widgets_input.searchInput(ui, "ed-prop-search");
    try ui.label("Create + Manage");
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.iconButtonTip(ui, "ed-prop-library-new", "box", false, "Create a new prop")).clicked) {
        setPropTool(state, .primitive);
    }
    if ((try ui_widgets.iconButtonTip(ui, "ed-prop-sort-name", "list-select", state.prop_library_sort == .name, "Sort by name")).clicked) {
        state.prop_library_sort = .name;
        project_editor_state.setStatus(state, "Props sorted by name");
    }
    if ((try ui_widgets.iconButtonTip(ui, "ed-prop-sort-recent", "rotate-camera-right", state.prop_library_sort == .recent, "Sort by recent edits")).clicked) {
        state.prop_library_sort = .recent;
        project_editor_state.setStatus(state, "Props sorted by recent edits");
    }
    if ((try ui_widgets.iconButtonTip(ui, "ed-prop-filter-tags", "component", hasPropTagFilter(state) or state.prop_library_category_filter != .all or state.prop_library_source_filter != .all, "Clear filters")).clicked) {
        clearPropFilters(state);
    }
    if ((try ui_widgets.iconButtonTip(ui, "ed-prop-library-delete", "trash", state.prop_delete_confirm_asset != null, "Delete selected prop")).clicked) requestPropDelete(state);
    try core_ui.layout.endSameLine(ui);

    try buildLibrarySelectedSummary(ui, state);

    try buildPropFacetControls(ui, state, rows);

    try ui.label("Assets");
    try buildAssetRows(ui, state, null);

    try ui.label("Recent");
    if (state.prop_recent_ids.items.len == 0) {
        try ui_widgets.compactInfo(ui, "No recent props");
    } else {
        var visible_recent: usize = 0;
        for (state.prop_recent_ids.items, 0..) |name, idx| {
            if (project_editor_prop_asset.assetDeleted(state, name)) continue;
            if (!ui_widgets.matchesFilter(ui, "ed-prop-search", name) and !ui_widgets.matchesFilter(ui, "ed-prop-search", project_editor_prop.catalogLabel(name))) continue;
            visible_recent += 1;
            var id_buf: [48]u8 = undefined;
            const row_id = std.fmt.bufPrint(&id_buf, "prop-recent-{d}", .{idx}) catch name;
            const label = project_editor_prop.catalogLabel(name);
            const entry = project_editor_prop.findCatalogEntry(name);
            var detail_buf: [128]u8 = undefined;
            if ((try ui_widgets.assetPreview(ui, .{
                .id = row_id,
                .label = label,
                .detail = if (entry) |catalog_entry| propAssetDetail(catalog_entry, &detail_buf) else name,
                .fill_color = if (entry) |catalog_entry| catalog_entry.color else .{ .r = 150, .g = 160, .b = 176, .a = 255 },
                .shape = if (entry) |catalog_entry| propPreviewShape(catalog_entry.kind) else .box,
                .selected = false,
            })).clicked) {
                openAsset(state, name);
            }
        }
        if (visible_recent == 0) try ui_widgets.compactInfo(ui, "No recent props match filters");
    }

    try ui.label("Primitives");
    inline for (std.meta.fields(PropPrimitive)) |field| {
        const prim: PropPrimitive = @field(PropPrimitive, field.name);
        try primitiveStarterPreview(ui, state, prim);
    }
}

fn buildAssetRows(ui: *core_ui.UiContext, state: *ProjectEditorState, max_rows: ?usize) !void {
    const rows = try project_editor_prop_index.ensure(state);
    var matches = std.ArrayList(usize).empty;
    defer matches.deinit(state.allocator);
    try collectVisiblePropRows(ui, state, rows, &matches);
    sortVisiblePropRows(state, rows, matches.items);
    const total_visible = matches.items.len;
    var count_buf: [80]u8 = undefined;
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&count_buf, "{d} of {d} props", .{ total_visible, visibleCatalogCount(state) }) catch "Props");
    if (total_visible == 0) {
        try ui_widgets.compactInfo(ui, "No props match filters");
        return;
    }

    const draw_total = if (max_rows) |limit| @min(limit, total_visible) else total_visible;
    if (max_rows) |_| {
        try drawPropRows(ui, state, rows, matches.items[0..draw_total]);
    } else {
        const scroll_h = @min(420.0, @max(140.0, try core_ui.layout.remainingPanelContentHeight(ui)));
        try core_ui.layout.beginScrollArea(ui, .{ .id = "ed-prop-results-scroll", .height = scroll_h, .input = core_ui.layout.panel_scroll_input });
        const range = try core_ui.layout.virtualListRange(ui, draw_total, 44);
        try core_ui.layout.virtualListSpacer(ui, range.top_padding);
        try drawPropRows(ui, state, rows, matches.items[range.start..range.end]);
        try core_ui.layout.virtualListSpacer(ui, range.bottom_padding);
        try core_ui.layout.endScrollArea(ui);
    }

    if (max_rows) |limit| {
        if (total_visible > limit) {
            var more_buf: [80]u8 = undefined;
            try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&more_buf, "{d} more props in Asset tool", .{total_visible - limit}) catch "More props in Asset tool");
        }
    }
}

fn drawPropRows(ui: *core_ui.UiContext, state: *ProjectEditorState, rows: []const PropAssetIndexRow, indices: []const usize) !void {
    for (indices) |row_idx| {
        const row = rows[row_idx];
        var detail_buf: [160]u8 = undefined;
        if ((try propLibraryRow(ui, row.id, row.label, indexedPropDetail(row, &detail_buf), assetSelected(state, row.id))).clicked) {
            openAsset(state, row.id);
        }
    }
}

fn visibleCatalogCount(state: *ProjectEditorState) usize {
    const rows = project_editor_prop_index.ensure(state) catch return project_editor_prop.catalog.len;
    var count: usize = 0;
    for (rows) |row| {
        if (!row.deleted) count += 1;
    }
    return count;
}

fn buildPropFacetControls(ui: *core_ui.UiContext, state: *ProjectEditorState, rows: []const PropAssetIndexRow) !void {
    try ui.label("Source");
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.button(ui, "ed-prop-source-all", "All", 44, state.prop_library_source_filter == .all)).clicked) state.prop_library_source_filter = .all;
    if ((try ui_widgets.button(ui, "ed-prop-source-builtin", "Built-in", 74, state.prop_library_source_filter == .builtin)).clicked) state.prop_library_source_filter = .builtin;
    if ((try ui_widgets.button(ui, "ed-prop-source-project", "Project", 70, state.prop_library_source_filter == .project)).clicked) state.prop_library_source_filter = .project;
    try core_ui.layout.endSameLine(ui);

    try ui.label("Category");
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.button(ui, "ed-prop-category-all", "All", 44, state.prop_library_category_filter == .all)).clicked) toggleLibraryCategoryFilter(state, .all);
    if ((try ui_widgets.button(ui, "ed-prop-category-painted", "#paint", 66, state.prop_library_category_filter == .paint)).clicked) toggleLibraryCategoryFilter(state, .paint);
    if ((try ui_widgets.button(ui, "ed-prop-category-shape", "#shape", 70, state.prop_library_category_filter == .shape)).clicked) toggleLibraryCategoryFilter(state, .shape);
    if ((try ui_widgets.button(ui, "ed-prop-category-game", "#game", 66, state.prop_library_category_filter == .game)).clicked) toggleLibraryCategoryFilter(state, .game);
    try core_ui.layout.endSameLine(ui);

    try ui.label("Tags");
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.button(ui, "ed-prop-tag-all", "All", 44, !hasPropTagFilter(state))).clicked) clearPropTagFilter(state);
    var tags: [6][32]u8 = undefined;
    var tag_lens: [6]usize = [_]usize{0} ** 6;
    const tag_count = collectPropTagChips(rows, &tags, &tag_lens);
    for (0..tag_count) |idx| {
        const tag = tags[idx][0..tag_lens[idx]];
        var id_buf: [64]u8 = undefined;
        if ((try ui_widgets.button(ui, std.fmt.bufPrint(&id_buf, "ed-prop-tag-{s}", .{tag}) catch "ed-prop-tag", tag, @min(@as(f32, 88), 32 + @as(f32, @floatFromInt(tag.len)) * 7), propTagFilterEquals(state, tag))).clicked) {
            setPropTagFilter(state, tag);
        }
    }
    try core_ui.layout.endSameLine(ui);
}

fn collectVisiblePropRows(ui: *core_ui.UiContext, state: *ProjectEditorState, rows: []const PropAssetIndexRow, out: *std.ArrayList(usize)) !void {
    for (rows, 0..) |row, idx| {
        if (row.deleted) continue;
        if (!propRowMatchesSource(row, state.prop_library_source_filter)) continue;
        if (!propRowMatchesCategory(row, state.prop_library_category_filter)) continue;
        if (hasPropTagFilter(state) and !containsTag(row.tags, propTagFilter(state))) continue;
        if (!propRowMatchesSearch(ui, row)) continue;
        try out.append(state.allocator, idx);
    }
}

fn propRowMatchesSearch(ui: *core_ui.UiContext, row: PropAssetIndexRow) bool {
    return ui_widgets.matchesFilter(ui, "ed-prop-search", row.label) or
        ui_widgets.matchesFilter(ui, "ed-prop-search", row.tags) or
        ui_widgets.matchesFilter(ui, "ed-prop-search", row.id) or
        ui_widgets.matchesFilter(ui, "ed-prop-search", row.kind) or
        ui_widgets.matchesFilter(ui, "ed-prop-search", project_editor_prop_index.sourceLabel(row.source));
}

fn propRowMatchesSource(row: PropAssetIndexRow, filter: PropLibrarySourceFilter) bool {
    return switch (filter) {
        .all => true,
        .builtin => row.source == .builtin,
        .project => row.source == .project,
    };
}

fn propRowMatchesCategory(row: PropAssetIndexRow, filter: PropLibraryCategoryFilter) bool {
    return switch (filter) {
        .all => true,
        .paint => containsAnyIgnoreCase(row.tags, &.{ "paint", "material", "texture" }) or std.ascii.indexOfIgnoreCase(row.kind, "paint") != null,
        .shape => row.source_count > 0 or containsAnyIgnoreCase(row.tags, &.{ "shape", "mesh", "prop" }),
        .game => containsAnyIgnoreCase(row.tags, &.{ "game", "door", "lamp", "trigger", "cover" }) or containsAnyIgnoreCase(row.id, &.{ "door", "lamp" }),
    };
}

fn sortVisiblePropRows(state: *const ProjectEditorState, rows: []const PropAssetIndexRow, indices: []usize) void {
    var i: usize = 1;
    while (i < indices.len) : (i += 1) {
        const value = indices[i];
        var j = i;
        while (j > 0 and indexedPropBefore(state, rows[value], rows[indices[j - 1]])) : (j -= 1) {
            indices[j] = indices[j - 1];
        }
        indices[j] = value;
    }
}

fn indexedPropBefore(state: *const ProjectEditorState, a: PropAssetIndexRow, b: PropAssetIndexRow) bool {
    if (state.prop_library_sort == .recent) {
        const a_recent = recentRank(state, a.id);
        const b_recent = recentRank(state, b.id);
        if (a_recent != b_recent) return a_recent < b_recent;
    }
    return std.ascii.lessThanIgnoreCase(a.label, b.label);
}

fn indexedPropDetail(row: PropAssetIndexRow, buf: []u8) []const u8 {
    var tag_buf: [80]u8 = undefined;
    return std.fmt.bufPrint(buf, "{s}  {s}  {d} source{s}  {d} variant{s}", .{
        project_editor_prop_index.sourceLabel(row.source),
        propPersistedTagLine(row.tags, &tag_buf),
        row.source_count,
        if (row.source_count == 1) "" else "s",
        row.variant_count,
        if (row.variant_count == 1) "" else "s",
    }) catch row.id;
}

fn collectPropTagChips(rows: []const PropAssetIndexRow, tags: *[6][32]u8, tag_lens: *[6]usize) usize {
    var count: usize = 0;
    for (rows) |row| {
        var it = std.mem.tokenizeAny(u8, row.tags, ", #\t\r\n");
        while (it.next()) |raw| {
            const tag = std.mem.trim(u8, raw, " \t\r\n#");
            if (tag.len == 0 or tag.len > tags[0].len) continue;
            if (containsCollectedTag(tags, tag_lens, count, tag)) continue;
            @memcpy(tags[count][0..tag.len], tag);
            tag_lens[count] = tag.len;
            count += 1;
            if (count >= tags.len) return count;
        }
    }
    return count;
}

fn containsCollectedTag(tags: *[6][32]u8, tag_lens: *[6]usize, count: usize, tag: []const u8) bool {
    for (0..count) |idx| {
        if (std.ascii.eqlIgnoreCase(tags[idx][0..tag_lens[idx]], tag)) return true;
    }
    return false;
}

fn containsTag(tags: []const u8, needle: []const u8) bool {
    var it = std.mem.tokenizeAny(u8, tags, ", #\t\r\n");
    while (it.next()) |raw| {
        if (std.ascii.eqlIgnoreCase(std.mem.trim(u8, raw, " \t\r\n#"), needle)) return true;
    }
    return false;
}

fn hasPropTagFilter(state: *const ProjectEditorState) bool {
    return state.prop_library_tag_filter_len > 0;
}

fn propTagFilter(state: *const ProjectEditorState) []const u8 {
    return state.prop_library_tag_filter_buf[0..state.prop_library_tag_filter_len];
}

fn propTagFilterEquals(state: *const ProjectEditorState, tag: []const u8) bool {
    return hasPropTagFilter(state) and std.ascii.eqlIgnoreCase(propTagFilter(state), tag);
}

fn setPropTagFilter(state: *ProjectEditorState, tag: []const u8) void {
    if (propTagFilterEquals(state, tag)) {
        clearPropTagFilter(state);
        return;
    }
    state.prop_library_tag_filter_len = @min(tag.len, state.prop_library_tag_filter_buf.len);
    @memcpy(state.prop_library_tag_filter_buf[0..state.prop_library_tag_filter_len], tag[0..state.prop_library_tag_filter_len]);
    project_editor_state.setStatus(state, "Filtering prop tag");
}

fn clearPropTagFilter(state: *ProjectEditorState) void {
    state.prop_library_tag_filter_len = 0;
}

fn clearPropFilters(state: *ProjectEditorState) void {
    state.prop_library_source_filter = .all;
    state.prop_library_category_filter = .all;
    clearPropTagFilter(state);
    project_editor_state.setStatus(state, "Prop filters cleared");
}

fn collectProjectPropRows(state: *ProjectEditorState) ![]ProjectPropRow {
    var rows = std.ArrayList(ProjectPropRow).empty;
    errdefer {
        for (rows.items) |*row| row.deinit(state.allocator);
        rows.deinit(state.allocator);
    }

    var project_dir = scene_resolve.openProjectDir(state.io, state.project_path) catch |err| switch (err) {
        error.FileNotFound => return try rows.toOwnedSlice(state.allocator),
        else => return err,
    };
    defer project_dir.close(state.io);
    var props_dir = project_dir.openDir(state.io, "props", .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return try rows.toOwnedSlice(state.allocator),
        else => return err,
    };
    defer props_dir.close(state.io);

    var walker = try props_dir.walk(state.allocator);
    defer walker.deinit();
    while (try walker.next(state.io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.path, ".kdl")) continue;
        if (std.fs.path.dirname(entry.path) != null) continue;
        const id = std.fs.path.stem(std.fs.path.basename(entry.path));
        if (project_editor_prop.findCatalogEntry(id) != null) continue;

        var doc = try project_editor_prop_asset.loadAssetDocument(state, id);
        defer doc.deinit(state.allocator);
        if (doc.deleted) continue;
        try rows.append(state.allocator, .{
            .id = try state.allocator.dupe(u8, doc.id),
            .label = try state.allocator.dupe(u8, doc.label),
            .tags = try state.allocator.dupe(u8, doc.tags),
            .color = doc.base_color,
            .source_count = doc.recipe.sources.len,
        });
    }
    return try rows.toOwnedSlice(state.allocator);
}

fn freeProjectPropRows(allocator: std.mem.Allocator, rows: []ProjectPropRow) void {
    for (rows) |*row| row.deinit(allocator);
    allocator.free(rows);
}

fn propLibraryRow(ui: *core_ui.UiContext, id: []const u8, label: []const u8, detail: []const u8, selected: bool) !core_ui.ButtonResult {
    const row_h: f32 = 44;
    const inset: f32 = 12;
    const rect = try ui.allocFullWidthRow(row_h);
    const stable = try ui.stableId(id, label);
    const click = core_ui.input.handleClick(ui, stable, rect);
    try ui.pushCommand(.{ .selectable = .{
        .id = ui.nextCommandId(stable),
        .rect = rect,
        .text = try ui.dupeText(label),
        .text_pad_x = inset,
        .selected = selected,
        .hovered = click.hovered,
        .active = click.active,
    } });
    try ui_widgets.text(ui, detail, .{ .x = rect.x + inset, .y = rect.y + 26, .w = rect.w - inset * 2, .h = 16 }, detail, true);
    return .{ .id = stable, .rect = rect, .hovered = click.hovered, .clicked = click.clicked };
}

fn assetSelected(state: *const ProjectEditorState, asset_id: []const u8) bool {
    if (state.active_prop_asset_id) |active_id| return std.mem.eql(u8, active_id, asset_id);
    return std.mem.eql(u8, state.prop_selected_asset, asset_id);
}

fn sortProjectPropRows(rows: []ProjectPropRow, state: *const ProjectEditorState) void {
    var i: usize = 1;
    while (i < rows.len) : (i += 1) {
        const value = rows[i];
        var j = i;
        while (j > 0 and projectPropBefore(value, rows[j - 1], state)) : (j -= 1) {
            rows[j] = rows[j - 1];
        }
        rows[j] = value;
    }
}

fn projectPropBefore(a: ProjectPropRow, b: ProjectPropRow, state: *const ProjectEditorState) bool {
    if (state.prop_library_sort == .recent) {
        const a_recent = recentRank(state, a.id);
        const b_recent = recentRank(state, b.id);
        if (a_recent != b_recent) return a_recent < b_recent;
    }
    return std.ascii.lessThanIgnoreCase(a.label, b.label);
}

fn projectPropVisible(ui: *core_ui.UiContext, state: *ProjectEditorState, row: ProjectPropRow) bool {
    if (!ui_widgets.matchesFilter(ui, "ed-prop-search", row.label) and !ui_widgets.matchesFilter(ui, "ed-prop-search", row.tags) and !ui_widgets.matchesFilter(ui, "ed-prop-search", row.id)) return false;
    return projectPropMatchesTagFilter(row, state.prop_library_category_filter);
}

fn projectPropMatchesTagFilter(row: ProjectPropRow, filter: PropLibraryCategoryFilter) bool {
    return switch (filter) {
        .all => true,
        .paint => containsAnyIgnoreCase(row.tags, &.{ "paint", "material", "texture" }),
        .shape => row.source_count > 0 or containsAnyIgnoreCase(row.tags, &.{ "shape", "mesh", "prop" }),
        .game => containsAnyIgnoreCase(row.tags, &.{ "game", "door", "lamp", "trigger", "cover" }),
    };
}

fn projectPropDetail(row: ProjectPropRow, buf: []u8) []const u8 {
    var tag_buf: [80]u8 = undefined;
    const tags = propPersistedTagLine(row.tags, &tag_buf);
    return std.fmt.bufPrint(buf, "{d} source{s}  {s}", .{
        row.source_count,
        if (row.source_count == 1) "" else "s",
        tags,
    }) catch row.id;
}

fn projectPropPreviewShape(row: ProjectPropRow) core_ui.commands.AssetPreviewShape {
    if (containsAnyIgnoreCase(row.id, &.{ "wall", "hedge", "fence", "gate", "bridge", "crate", "plank" }) or
        containsAnyIgnoreCase(row.tags, &.{ "wall", "hedge", "fence", "gate", "bridge", "crate" }))
    {
        return .box;
    }
    if (containsAnyIgnoreCase(row.id, &.{ "reed", "grass", "fern", "flower", "ditch", "road", "rut" }) or
        containsAnyIgnoreCase(row.tags, &.{ "reed", "grass", "fern", "flower", "road" }))
    {
        return .plane;
    }
    return .sphere;
}

fn containsAnyIgnoreCase(haystack: []const u8, needles: []const []const u8) bool {
    for (needles) |needle| {
        if (std.ascii.indexOfIgnoreCase(haystack, needle) != null) return true;
    }
    return false;
}

fn sortAssetIndices(indices: []usize, state: *const ProjectEditorState) void {
    var i: usize = 1;
    while (i < indices.len) : (i += 1) {
        const value = indices[i];
        var j = i;
        while (j > 0 and assetBefore(project_editor_prop.catalog[value], project_editor_prop.catalog[indices[j - 1]], state)) : (j -= 1) {
            indices[j] = indices[j - 1];
        }
        indices[j] = value;
    }
}

fn assetBefore(a: project_editor_prop.CatalogEntry, b: project_editor_prop.CatalogEntry, state: *const ProjectEditorState) bool {
    if (state.prop_library_sort == .recent) {
        const a_recent = recentRank(state, a.id);
        const b_recent = recentRank(state, b.id);
        if (a_recent != b_recent) return a_recent < b_recent;
    }
    return std.ascii.lessThanIgnoreCase(a.label, b.label);
}

fn recentRank(state: *const ProjectEditorState, id: []const u8) usize {
    for (state.prop_recent_ids.items, 0..) |recent_id, idx| {
        if (std.mem.eql(u8, recent_id, id)) return idx;
    }
    return std.math.maxInt(usize);
}

fn libraryEntryVisible(ui: *core_ui.UiContext, state: *ProjectEditorState, entry: project_editor_prop.CatalogEntry) bool {
    if (project_editor_prop_asset.assetDeleted(state, entry.id)) return false;
    var doc = project_editor_prop_asset.loadAssetDocument(state, entry.id) catch null;
    defer if (doc) |*loaded| loaded.deinit(state.allocator);
    const label = if (doc) |loaded| loaded.label else entry.label;
    const tags = if (doc) |loaded| loaded.tags else "";
    if (!ui_widgets.matchesFilter(ui, "ed-prop-search", label) and !ui_widgets.matchesFilter(ui, "ed-prop-search", tags) and !ui_widgets.matchesFilter(ui, "ed-prop-search", entry.id)) return false;
    return entryMatchesTagFilter(entry, state.prop_library_category_filter);
}

fn entryMatchesTagFilter(entry: project_editor_prop.CatalogEntry, filter: PropLibraryCategoryFilter) bool {
    return switch (filter) {
        .all => true,
        .paint => recipeContains(entry, "tint") or recipeContains(entry, "mask") or recipeContains(entry, "rust"),
        .shape => entry.recipe.shaping.len > 0,
        .game => std.mem.indexOf(u8, entry.id, "door") != null or std.mem.indexOf(u8, entry.id, "lamp") != null,
    };
}

fn recipeContains(entry: project_editor_prop.CatalogEntry, needle: []const u8) bool {
    for (entry.recipe.shaping) |shape| {
        if (std.ascii.indexOfIgnoreCase(shape, needle) != null) return true;
    }
    return false;
}

fn toggleLibraryCategoryFilter(state: *ProjectEditorState, filter: PropLibraryCategoryFilter) void {
    state.prop_library_category_filter = if (state.prop_library_category_filter == filter) .all else filter;
    project_editor_state.setStatus(state, switch (state.prop_library_category_filter) {
        .all => "Prop tag filter cleared",
        .paint => "Filtering paint props",
        .shape => "Filtering shape props",
        .game => "Filtering gameplay props",
    });
}

fn librarySortLabel(sort: PropLibrarySort) []const u8 {
    return switch (sort) {
        .name => "name",
        .recent => "recent",
    };
}

fn libraryCategoryFilterLabel(filter: PropLibraryCategoryFilter) []const u8 {
    return switch (filter) {
        .all => "all",
        .paint => "#paint",
        .shape => "#shape",
        .game => "#game",
    };
}

fn librarySourceFilterLabel(filter: PropLibrarySourceFilter) []const u8 {
    return switch (filter) {
        .all => "all",
        .builtin => "built-in",
        .project => "project",
    };
}

pub fn requestPropDelete(state: *ProjectEditorState) void {
    state.prop_delete_confirm_asset = if (state.active_prop_asset_id) |asset_id| asset_id else state.prop_selected_asset;
    state.prop_tool = .asset;
    state.prop_workspace_mode = .edit;
    project_editor_state.setStatus(state, "Confirm delete prop");
}

fn cancelPropDelete(state: *ProjectEditorState) void {
    state.prop_delete_confirm_asset = null;
    project_editor_state.setStatus(state, "Delete canceled");
}

fn confirmPropDelete(state: *ProjectEditorState) void {
    const asset_id = state.prop_delete_confirm_asset orelse return;
    state.prop_delete_confirm_asset = null;
    project_editor_prop_asset.setAssetDeleted(state, asset_id, true) catch {
        project_editor_state.setStatus(state, "Prop delete failed");
        return;
    };
    selectFirstVisibleProp(state);
}

fn selectFirstVisibleProp(state: *ProjectEditorState) void {
    for (project_editor_prop.catalog) |entry| {
        if (project_editor_prop_asset.assetDeleted(state, entry.id)) continue;
        state.prop_selected_asset = entry.id;
        return;
    }
}

fn isDeleteConfirming(state: *const ProjectEditorState, asset_id: []const u8) bool {
    const confirm_id = state.prop_delete_confirm_asset orelse return false;
    return std.mem.eql(u8, confirm_id, asset_id);
}

fn buildLibrarySelectedSummary(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    const entry = project_editor_prop.findCatalogEntry(state.prop_selected_asset) orelse return;
    var doc = project_editor_prop_asset.loadAssetDocument(state, entry.id) catch null;
    defer if (doc) |*loaded| loaded.deinit(state.allocator);
    const selected_label = if (doc) |loaded| loaded.label else entry.label;
    const selected_tags = if (doc) |loaded| loaded.tags else null;
    var selected_buf: [128]u8 = undefined;
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&selected_buf, "Selected: {s}", .{selected_label}) catch selected_label);
    if (!state.prop_metadata_editor_open) {
        var tag_buf: [128]u8 = undefined;
        try ui_widgets.compactInfo(ui, if (selected_tags) |tags| propPersistedTagLine(tags, &tag_buf) else propTagLine(entry, &tag_buf));
        try core_ui.layout.sameLine(ui);
        if ((try ui_widgets.iconButtonTip(ui, "ed-prop-library-rename", "selective-tool", false, "Rename selected prop")).clicked) requestPropMetadataEdit(state);
        if ((try ui_widgets.iconButtonTip(ui, "ed-prop-library-tags", "component", false, "Edit selected prop tags")).clicked) requestPropMetadataEdit(state);
        try core_ui.layout.endSameLine(ui);
    }
    if (state.prop_metadata_editor_open) try buildPropMetadataEditor(ui, state, entry, "library");
    if (isDeleteConfirming(state, entry.id)) {
        try ui_widgets.compactInfo(ui, "Delete selected prop?");
        try core_ui.layout.sameLine(ui);
        if ((try ui_widgets.button(ui, "ed-prop-delete-cancel", "Cancel", 66, false)).clicked) cancelPropDelete(state);
        if ((try ui_widgets.button(ui, "ed-prop-delete-confirm", "Delete", 68, true)).clicked) confirmPropDelete(state);
        try core_ui.layout.endSameLine(ui);
    }
}

pub fn requestPropMetadataEdit(state: *ProjectEditorState) void {
    state.prop_tool = .asset;
    state.prop_workspace_mode = .edit;
    state.prop_metadata_editor_open = true;
    state.prop_delete_confirm_asset = null;
    project_editor_state.setStatus(state, "Edit prop metadata");
}

fn cancelPropMetadataEdit(state: *ProjectEditorState) void {
    state.prop_metadata_editor_open = false;
    project_editor_state.setStatus(state, "Metadata edit canceled");
}

fn applyPropMetadataEdit(state: *ProjectEditorState) void {
    state.prop_metadata_editor_open = false;
    project_editor_state.setStatus(state, "Metadata saved");
}

fn buildPropMetadataEditor(ui: *core_ui.UiContext, state: *ProjectEditorState, entry: project_editor_prop.CatalogEntry, id_prefix: []const u8) !void {
    var doc = project_editor_prop_asset.loadAssetDocument(state, entry.id) catch null;
    defer if (doc) |*loaded| loaded.deinit(state.allocator);
    const current_label = if (doc) |loaded| loaded.label else entry.label;
    const current_tags = if (doc) |loaded| loaded.tags else blk: {
        var fallback_tags_buf: [96]u8 = undefined;
        break :blk propTagInputLine(entry, &fallback_tags_buf);
    };
    try ui.label("Edit Metadata");
    try ui_widgets.compactInfo(ui, "Name");
    var name_id: [80]u8 = undefined;
    const name_input = try core_ui.widgets_input.textInput(ui, .{
        .id = std.fmt.bufPrint(&name_id, "ed-prop-{s}-name", .{id_prefix}) catch "ed-prop-name",
        .default_text = current_label,
    });
    try ui_widgets.compactInfo(ui, "Tags");
    var tags_id: [80]u8 = undefined;
    const tags_input = try core_ui.widgets_input.textInput(ui, .{
        .id = std.fmt.bufPrint(&tags_id, "ed-prop-{s}-tags", .{id_prefix}) catch "ed-prop-tags",
        .default_text = current_tags,
    });
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.button(ui, "ed-prop-metadata-cancel", "Cancel", 66, false)).clicked) cancelPropMetadataEdit(state);
    if ((try ui_widgets.button(ui, "ed-prop-metadata-apply", "Apply", 62, true)).clicked) {
        project_editor_prop_asset.updateAssetMetadata(state, entry.id, name_input.text, tags_input.text) catch |err| {
            project_editor_state.setStatus(state, switch (err) {
                error.EmptyPropLabel => "Prop name cannot be empty",
                else => "Metadata save failed",
            });
            return;
        };
        applyPropMetadataEdit(state);
    }
    try core_ui.layout.endSameLine(ui);
}

pub fn buildToolbar(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    if ((try ui_widgets.button(ui, "ed-prop-display-mode", "Display", 78, state.prop_workspace_mode == .display)).clicked) {
        setPropDisplayMode(state);
    }
    if (state.prop_workspace_mode == .display) {
        if ((try ui_widgets.button(ui, command_ids.propTool("edit"), "Edit", 58, false)).clicked) {
            setPropTool(state, .edit);
        }
        try core_ui.layout.endSameLine(ui);
        try core_ui.layout.sameLine(ui);
        _ = try ui_widgets.button(ui, "ed-prop-toolbar-light-studio", "Studio", 72, true);
        _ = try ui_widgets.button(ui, "ed-prop-toolbar-light-dim", "Dim", 54, false);
        _ = try ui_widgets.button(ui, "ed-prop-toolbar-light-backlit", "Backlit", 82, false);
    } else {
        inline for (prop_tool_groups) |group| {
            if ((try ui_widgets.button(ui, propToolGroupId(group), propToolGroupLabel(group), propToolGroupWidth(group), activePropToolGroup(state) == group)).clicked) {
                activatePropToolGroup(state, group);
            }
        }
        try core_ui.layout.endSameLine(ui);
        try core_ui.layout.sameLine(ui);
        try buildActivePropToolGroup(ui, state, activePropToolGroup(state));
    }
}

const PropToolGroup = enum {
    draw,
    shape,
    edit,
    paint,
};

const prop_tool_groups = [_]PropToolGroup{ .draw, .shape, .edit, .paint };
const prop_draw_tools = [_]PropTool{ .asset, .primitive };
const prop_edit_tools = [_]PropTool{ .select, .edit, .collider, .variants };
const prop_paint_tools = [_]PropTool{.material};

fn activePropToolGroup(state: *const ProjectEditorState) PropToolGroup {
    return switch (state.prop_tool) {
        .create, .asset, .primitive => .draw,
        .material => .paint,
        .select, .collider, .variants => .edit,
        .edit => .shape,
    };
}

fn activatePropToolGroup(state: *ProjectEditorState, group: PropToolGroup) void {
    switch (group) {
        .draw => setPropTool(state, .primitive),
        .shape => setPropTool(state, .edit),
        .edit => setPropTool(state, .select),
        .paint => setPropTool(state, .material),
    }
}

fn buildActivePropToolGroup(ui: *core_ui.UiContext, state: *ProjectEditorState, group: PropToolGroup) !void {
    switch (group) {
        .draw => try buildPropDrawToolbar(ui, state),
        .shape => try buildPropShapeToolbar(ui, state),
        .edit => try buildPropEditToolbar(ui, state),
        .paint => try buildPropPaintToolbar(ui, state),
    }
}

fn buildPropDrawToolbar(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    inline for (prop_draw_tools) |tool| {
        try propToolButton(ui, state, tool);
    }
    if ((try ui_widgets.button(ui, "ed-prop-toolbar-face-source", "Face", 58, state.prop_sketch_mode == .face)).clicked) {
        state.prop_workspace_mode = .edit;
        state.prop_tool = .edit;
        state.prop_sketch_mode = .face;
        state.prop_sketch_points.clearRetainingCapacity();
        project_editor_state.setStatus(state, "Draw face source, then solidify");
    }
    if ((try ui_widgets.button(ui, "ed-prop-toolbar-profile-source", "Profile", 72, state.prop_sketch_mode == .curve)).clicked) {
        state.prop_workspace_mode = .edit;
        state.prop_tool = .edit;
        state.prop_sketch_mode = .curve;
        state.prop_sketch_points.clearRetainingCapacity();
        project_editor_state.setStatus(state, "Draw profile source, then revolve");
    }
    if ((try ui_widgets.button(ui, "ed-prop-toolbar-path-source", "Path", 58, state.prop_sketch_mode == .path)).clicked) {
        state.prop_workspace_mode = .edit;
        state.prop_tool = .edit;
        state.prop_sketch_mode = .path;
        state.prop_sketch_points.clearRetainingCapacity();
        project_editor_state.setStatus(state, "Draw path source");
    }
}

fn buildPropShapeToolbar(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    if ((try ui_widgets.button(ui, "ed-prop-toolbar-solidify", "Solidify", 78, false)).clicked) {
        project_editor_prop.solidifySelected(state, state.prop_sketch_amount) catch project_editor_state.setStatus(state, "Prop solidify failed");
    }
    if ((try ui_widgets.button(ui, "ed-prop-toolbar-revolve", "Revolve", 78, false)).clicked) {
        project_editor_prop.revolveSelected(state) catch project_editor_state.setStatus(state, "Prop revolve failed");
    }
    if ((try ui_widgets.button(ui, "ed-prop-toolbar-extrude", "Extrude", 74, false)).clicked) {
        if (state.prop_sketch_mode == .path and state.prop_sketch_points.items.len >= 2) {
            project_editor_prop.extrudePathSelected(state, state.prop_sketch_amount) catch project_editor_state.setStatus(state, "Path extrude failed");
        } else {
            project_editor_scene.extrudeSelectedFace(state) catch project_editor_state.setStatus(state, "Face extrude failed");
        }
    }
    if ((try ui_widgets.button(ui, "ed-prop-toolbar-inset", "Inset", 62, false)).clicked) {
        if (state.prop_sketch_mode == .face and state.prop_sketch_points.items.len >= 3) {
            project_editor_prop.insetSelected(state, state.prop_sketch_amount) catch project_editor_state.setStatus(state, "Prop inset failed");
        } else {
            project_editor_scene.insetSelectedFace(state) catch project_editor_state.setStatus(state, "Face inset failed");
        }
    }
    if ((try ui_widgets.button(ui, "ed-prop-toolbar-bevel", "Bevel", 62, false)).clicked) {
        project_editor_prop.bevelSelected(state, state.prop_sketch_amount) catch project_editor_state.setStatus(state, "Prop bevel failed");
    }
    if ((try ui_widgets.button(ui, "ed-prop-toolbar-cut", "Cut", 54, false)).clicked) {
        project_editor_prop.cutSelected(state, state.prop_sketch_amount) catch project_editor_state.setStatus(state, "Draw a face source before cutting");
    }
    if ((try ui_widgets.button(ui, "ed-prop-toolbar-taper", "Taper", 62, false)).clicked) {
        project_editor_prop.taperSelected(state, 0.28) catch project_editor_state.setStatus(state, "Prop taper failed");
    }
    if ((try ui_widgets.iconButtonTip(ui, "ed-prop-toolbar-mirror", "copy", false, "Mirror on X")).clicked) {
        project_editor_prop.mirrorSelectedX(state) catch project_editor_state.setStatus(state, "Prop mirror failed");
    }
    if ((try ui_widgets.iconButtonTip(ui, "ed-prop-toolbar-array", "dots-grid-3x3", false, "Array on X")).clicked) {
        project_editor_prop.arraySelectedX(state) catch project_editor_state.setStatus(state, "Prop array failed");
    }
}

fn buildPropEditToolbar(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    try propToolButton(ui, state, .select);
    if ((try ui_widgets.iconButtonTip(ui, editButtonId(.vertex), "select-point-3d", state.prop_tool == .edit and state.edit_tool == .vertex, "Select points")).clicked) setPropEditTool(state, .vertex);
    if ((try ui_widgets.iconButtonTip(ui, editButtonId(.edge), "select-edge-3d", state.prop_tool == .edit and state.edit_tool == .edge, "Select edges")).clicked) setPropEditTool(state, .edge);
    if ((try ui_widgets.iconButtonTip(ui, editButtonId(.face), "select-face-3d", state.prop_tool == .edit and state.edit_tool == .face, "Select faces")).clicked) setPropEditTool(state, .face);
    try propToolButton(ui, state, .collider);
    try propToolButton(ui, state, .variants);
}

fn buildPropPaintToolbar(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    inline for (prop_paint_tools) |tool| {
        try propToolButton(ui, state, tool);
    }
    if ((try ui_widgets.iconButtonTip(ui, "ed-prop-toolbar-unwrap", "mesh", false, "Unwrap paint atlas")).clicked) {
        _ = project_editor_prop_asset.unwrapTextureSelected(state) catch project_editor_state.setStatus(state, "Prop unwrap failed");
    }
}

fn propToolButton(ui: *core_ui.UiContext, state: *ProjectEditorState, tool: PropTool) !void {
    if ((try ui_widgets.iconButtonTip(ui, propToolId(tool), propToolbarIcon(tool), state.prop_tool == tool, propToolbarTip(tool))).clicked) {
        setPropTool(state, tool);
    }
}

fn propToolId(tool: PropTool) []const u8 {
    return switch (tool) {
        .select => command_ids.propTool("select"),
        .create => command_ids.propTool("create"),
        .asset => command_ids.propTool("asset"),
        .primitive => command_ids.propTool("primitive"),
        .edit => command_ids.propTool("edit"),
        .material => command_ids.propTool("material"),
        .collider => command_ids.propTool("collider"),
        .variants => command_ids.propTool("variants"),
    };
}

fn propToolGroupId(group: PropToolGroup) []const u8 {
    return switch (group) {
        .draw => "ed-prop-group-draw",
        .shape => "ed-prop-group-shape",
        .edit => "ed-prop-group-edit",
        .paint => "ed-prop-group-paint",
    };
}

fn propToolGroupLabel(group: PropToolGroup) []const u8 {
    return switch (group) {
        .draw => "Draw",
        .shape => "Shape",
        .edit => "Edit",
        .paint => "Paint",
    };
}

fn propToolGroupWidth(group: PropToolGroup) f32 {
    return switch (group) {
        .shape => 66,
        else => 58,
    };
}

fn propGroupHasTool(comptime tools: []const PropTool, tool: PropTool) bool {
    inline for (tools) |candidate| {
        if (candidate == tool) return true;
    }
    return false;
}

test "prop viewport toolbar exposes grouped source to operation loop" {
    try std.testing.expectEqual(@as(usize, 4), prop_tool_groups.len);
    try std.testing.expect(propGroupHasTool(&prop_draw_tools, .primitive));
    try std.testing.expect(propGroupHasTool(&prop_edit_tools, .select));
    try std.testing.expect(propGroupHasTool(&prop_edit_tools, .collider));
    try std.testing.expect(propGroupHasTool(&prop_paint_tools, .material));
}

pub fn buildToolInspector(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    if (state.selected_object) |idx| {
        try ui.label(state.objects.items[idx].name);
    } else {
        try ui.label("No prop open");
    }

    if (state.prop_workspace_mode == .display) {
        try buildDisplayControls(ui, state);
        return;
    }

    try buildActiveTaskSummary(ui, state);

    switch (state.prop_tool) {
        .select => try ui_widgets.compactInfo(ui, "Click a prop in the viewport"),
        .edit => try buildMeshEditControls(ui, state),
        .material => try project_editor_texture_paint.buildToolControls(ui, state, "ed-left-texture-paint"),
        .asset => try buildBrowser(ui, state),
        .create, .primitive => try buildPlacementAndCreateControls(ui, state),
        .collider => try buildColliderToolControls(ui, state),
        .variants => try ui_widgets.compactInfo(ui, "Click a prop to cycle variants"),
    }
}

fn buildActiveTaskSummary(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    try ui.label(propTaskTitle(state.prop_tool));
    if (state.prop_tool != .material and state.prop_tool != .edit) try ui_widgets.compactInfo(ui, propTaskHint(state.prop_tool));
}

fn buildDisplayControls(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    try ui_widgets.compactInfo(ui, "Orbit and zoom the prop");
    try ui.label("Overlays");
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.iconButtonTip(ui, "ed-display-prop-collider-preview", "cube-scan", state.prop_collider_preview, "Collider preview")).clicked) {
        state.prop_collider_preview = !state.prop_collider_preview;
    }
    if ((try ui_widgets.iconButtonTip(ui, "ed-display-prop-grid", "view-grid", state.show_grid, "Grid")).clicked) {
        state.show_grid = !state.show_grid;
    }
    try core_ui.layout.endSameLine(ui);
    try buildDisplayLibrarySummary(ui, state);
}

fn buildDisplayLibrarySummary(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    const rows = try project_editor_prop_index.ensure(state);
    try ui.label("Library");
    var summary_buf: [80]u8 = undefined;
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&summary_buf, "{d} props  searchable library", .{visibleCatalogCount(state)}) catch "Searchable prop library");
    _ = try core_ui.widgets_input.searchInput(ui, "ed-prop-search");
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.iconButtonTip(ui, "ed-prop-display-new", "box", false, "Create a new prop")).clicked) {
        setPropTool(state, .primitive);
    }
    if ((try ui_widgets.iconButtonTip(ui, "ed-prop-display-sort", "list-select", state.prop_library_sort == .name, "Sort by name")).clicked) {
        state.prop_library_sort = .name;
        project_editor_state.setStatus(state, "Props sorted by name");
    }
    if ((try ui_widgets.iconButtonTip(ui, "ed-prop-display-recent", "rotate-camera-right", state.prop_library_sort == .recent, "Sort by recent edits")).clicked) {
        state.prop_library_sort = .recent;
        project_editor_state.setStatus(state, "Props sorted by recent edits");
    }
    if ((try ui_widgets.iconButtonTip(ui, "ed-prop-display-tags", "component", hasPropTagFilter(state) or state.prop_library_category_filter != .all or state.prop_library_source_filter != .all, "Clear filters")).clicked) {
        clearPropFilters(state);
    }
    if ((try ui_widgets.iconButtonTip(ui, "ed-prop-display-delete", "trash", state.prop_delete_confirm_asset != null, "Delete prop")).clicked) requestPropDelete(state);
    try core_ui.layout.endSameLine(ui);
    try buildPropFacetControls(ui, state, rows);
    try buildAssetRows(ui, state, max_display_library_rows);
}

fn buildPlacementAndCreateControls(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    try ui.label("1  Pick Base");
    try ui_widgets.compactInfo(ui, "Start from a primitive or open prop");
    try core_ui.layout.sameLine(ui);
    try primitiveButton(ui, state, .cube);
    try primitiveButton(ui, state, .cylinder);
    try core_ui.layout.endSameLine(ui);
    try core_ui.layout.sameLine(ui);
    try primitiveButton(ui, state, .plane);
    try primitiveButton(ui, state, .ramp);
    try core_ui.layout.endSameLine(ui);

    try ui.label("2  Sketch Shape");
    try ui_widgets.compactInfo(ui, "Draw a face, profile, or path directly in the viewport");
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.button(ui, "ed-prop-sketch-face", "Face -> Solid", 106, state.prop_sketch_mode == .face)).clicked) {
        startSketchFromPrimitive(state, .plane, .face);
    }
    if ((try ui_widgets.button(ui, "ed-prop-sketch-profile", "Curve -> Lathe", 114, state.prop_sketch_mode == .curve)).clicked) {
        startSketchFromPrimitive(state, .cylinder, .curve);
    }
    if ((try ui_widgets.button(ui, "ed-prop-sketch-path", "Path", 58, state.prop_sketch_mode == .path)).clicked) {
        startSketchFromPrimitive(state, .plane, .path);
    }
    try core_ui.layout.endSameLine(ui);

    try ui.label("3  Make Solid");
    try ui_widgets.compactInfo(ui, "Extrude, revolve, or thicken a flat face");
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.button(ui, "ed-prop-create-extrude", "Extrude", 74, false)).clicked) {
        project_editor_scene.extrudeSelectedFace(state) catch project_editor_state.setStatus(state, "Select a face to extrude");
    }
    if ((try ui_widgets.button(ui, "ed-prop-create-revolve", "Revolve", 78, false)).clicked) {
        project_editor_prop.revolveSelected(state) catch project_editor_state.setStatus(state, "Open a prop to revolve");
    }
    if ((try ui_widgets.button(ui, "ed-prop-create-solidify", "Solidify", 78, false)).clicked) {
        project_editor_prop.solidifySelected(state, state.prop_sketch_amount) catch project_editor_state.setStatus(state, "Open a prop to solidify");
    }
    try core_ui.layout.endSameLine(ui);

    try ui.label("Drop Into World");
    if ((try ui_widgets.button(ui, command_ids.prop_placement_mode, state.prop_placement_mode.label(), 86, false)).clicked) {
        cyclePlacementMode(state);
    }
    const align_surface = try core_ui.widgets_input.checkbox(ui, "Align To Surface", "ed-left-prop-align-surface");
    if (align_surface.checked != state.prop_align_to_surface) {
        state.prop_align_to_surface = align_surface.checked;
        project_editor_state.setStatus(state, if (align_surface.checked) "Align to surface on" else "Align to surface off");
    }
    const yaw = try core_ui.widgets_input.checkbox(ui, "Random Yaw", "ed-left-prop-random-yaw");
    if (yaw.checked != state.prop_random_yaw) {
        state.prop_random_yaw = yaw.checked;
        project_editor_state.setStatus(state, if (yaw.checked) "Random yaw on" else "Random yaw off");
    }
    const drop = try core_ui.widgets_input.checkbox(ui, "Drop To Ground", "ed-left-prop-drop-ground");
    if (drop.checked != state.prop_drop_to_ground) {
        state.prop_drop_to_ground = drop.checked;
        project_editor_state.setStatus(state, if (drop.checked) "Drop to ground on" else "Drop to ground off");
    }

    if ((try ui_widgets.syncedCheckbox(ui, "Collider Preview", "ed-left-prop-collider-preview", state.prop_collider_preview)).clicked) {
        state.prop_collider_preview = !state.prop_collider_preview;
    }
}

fn buildColliderToolControls(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    try ui.label("Collider");
    if ((try ui_widgets.syncedCheckbox(ui, "Preview", "ed-left-prop-collider-preview", state.prop_collider_preview)).clicked) {
        state.prop_collider_preview = !state.prop_collider_preview;
    }
    if (state.selected_object) |idx| {
        const obj = &state.objects.items[idx];
        try core_ui.widgets_feedback.statusLabel(ui, project_editor_physics.label(obj.physics));
    } else {
        try ui_widgets.compactInfo(ui, "Select a prop to edit collider");
    }
}

fn buildMeshEditControls(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    try ui.label("1  Sketch Shape");
    try ui_widgets.compactInfo(ui, if (state.prop_sketch_mode == .face) "Draw a flat face, then thicken it" else if (state.prop_sketch_mode == .curve) "Draw a profile, then revolve it" else if (state.prop_sketch_mode == .path) "Draw an editable path source" else "Choose a sketch type");
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.button(ui, "ed-prop-shape-draw-face", "Face", 58, state.prop_sketch_mode == .face)).clicked) {
        state.prop_sketch_mode = .face;
        state.prop_sketch_points.clearRetainingCapacity();
        project_editor_state.setStatus(state, "Draw face, then solidify");
    }
    if ((try ui_widgets.button(ui, "ed-prop-shape-draw-curve", "Curve", 66, state.prop_sketch_mode == .curve)).clicked) {
        state.prop_sketch_mode = .curve;
        state.prop_sketch_points.clearRetainingCapacity();
        project_editor_state.setStatus(state, "Draw curve, then revolve");
    }
    if ((try ui_widgets.button(ui, "ed-prop-shape-draw-path", "Path", 58, state.prop_sketch_mode == .path)).clicked) {
        state.prop_sketch_mode = .path;
        state.prop_sketch_points.clearRetainingCapacity();
        project_editor_state.setStatus(state, "Draw path source");
    }
    try core_ui.layout.endSameLine(ui);
    if ((try ui_widgets.button(ui, "ed-prop-shape-clear", "Clear", 58, false)).clicked) {
        state.prop_sketch_points.clearRetainingCapacity();
        project_editor_state.setStatus(state, "Sketch cleared");
    }
    var sketch_buf: [64]u8 = undefined;
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&sketch_buf, "Points placed {d}", .{state.prop_sketch_points.items.len}) catch "Points placed");
    try ui_widgets.compactInfo(ui, sketchActionHint(state));

    try ui.label("2  Select Geometry");
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.iconButtonTip(ui, editButtonId(.vertex), "select-point-3d", state.prop_tool == .edit and state.edit_tool == .vertex, "Select vertices")).clicked) setPropEditTool(state, .vertex);
    if ((try ui_widgets.iconButtonTip(ui, editButtonId(.edge), "select-edge-3d", state.prop_tool == .edit and state.edit_tool == .edge, "Select edges")).clicked) setPropEditTool(state, .edge);
    if ((try ui_widgets.iconButtonTip(ui, editButtonId(.face), "select-face-3d", state.prop_tool == .edit and state.edit_tool == .face, "Select faces")).clicked) setPropEditTool(state, .face);
    if ((try ui_widgets.iconButtonTip(ui, "ed-prop-edit-loop", "rotate-camera-right", state.prop_loop_mode, "Edge loop")).clicked) {
        togglePropLoopMode(state);
    }
    try core_ui.layout.endSameLine(ui);

    try ui.label("3  Shape Actions");
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.button(ui, "ed-prop-face-extrude", "Extrude", 72, false)).clicked) {
        if (state.prop_sketch_mode == .path and state.prop_sketch_points.items.len >= 2) {
            project_editor_prop.extrudePathSelected(state, state.prop_sketch_amount) catch project_editor_state.setStatus(state, "Path extrude failed");
        } else {
            project_editor_scene.extrudeSelectedFace(state) catch project_editor_state.setStatus(state, "Face extrude failed");
        }
    }
    if ((try ui_widgets.button(ui, "ed-prop-face-inset", "Inset", 62, false)).clicked) {
        if (state.prop_sketch_mode == .face and state.prop_sketch_points.items.len >= 3) {
            project_editor_prop.insetSelected(state, state.prop_sketch_amount) catch project_editor_state.setStatus(state, "Prop inset failed");
        } else {
            project_editor_scene.insetSelectedFace(state) catch project_editor_state.setStatus(state, "Face inset failed");
        }
    }
    if ((try ui_widgets.button(ui, "ed-prop-face-bevel", "Bevel", 62, false)).clicked) {
        project_editor_prop.bevelSelected(state, state.prop_sketch_amount) catch project_editor_state.setStatus(state, "Prop bevel failed");
    }
    if ((try ui_widgets.button(ui, "ed-prop-face-cut", "Cut", 54, false)).clicked) {
        project_editor_prop.cutSelected(state, state.prop_sketch_amount) catch project_editor_state.setStatus(state, "Draw a face source before cutting");
    }
    if ((try ui_widgets.button(ui, "ed-prop-face-solidify", "Solidify", 78, false)).clicked) {
        project_editor_prop.solidifySelected(state, state.prop_sketch_amount) catch project_editor_state.setStatus(state, "Prop solidify failed");
    }
    try core_ui.layout.endSameLine(ui);

    try ui.label("4  Repeat And Finish");
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.button(ui, "ed-prop-shape-taper-left", "Taper", 62, false)).clicked) {
        project_editor_prop.taperSelected(state, 0.28) catch project_editor_state.setStatus(state, "Prop taper failed");
    }
    if ((try ui_widgets.iconButtonTip(ui, "ed-prop-shape-mirror-left", "copy", false, "Mirror on X")).clicked) {
        project_editor_prop.mirrorSelectedX(state) catch project_editor_state.setStatus(state, "Prop mirror failed");
    }
    if ((try ui_widgets.iconButtonTip(ui, "ed-prop-shape-array-left", "dots-grid-3x3", false, "Array on X")).clicked) {
        project_editor_prop.arraySelectedX(state) catch project_editor_state.setStatus(state, "Prop array failed");
    }
    try core_ui.layout.endSameLine(ui);

    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.button(ui, "ed-prop-face-revolve", "Revolve", 78, false)).clicked) {
        project_editor_prop.revolveSelected(state) catch project_editor_state.setStatus(state, "Prop revolve failed");
    }
    if ((try ui_widgets.button(ui, "ed-prop-face-delete", "Delete", 64, false)).clicked) {
        project_editor_scene.deleteSelectedFace(state) catch project_editor_state.setStatus(state, "Face delete failed");
    }
    try core_ui.layout.endSameLine(ui);

    const selection = if (state.selected_face != null)
        "Face selected"
    else if (state.selected_edge != null)
        if (state.prop_loop_mode) "Edge loop ready" else "Edge selected"
    else if (state.selected_vertex != null)
        "Vertex selected"
    else
        "Select geometry to edit";
    try ui_widgets.compactInfo(ui, selection);

    try ui.label("5  Import / Export");
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.button(ui, "ed-prop-glb-import", "Import GLB", 92, false)).clicked) {
        if (state.window) |window| project_editor_prop_dialog.requestImportPropGlbDialog(state, window);
    }
    if ((try ui_widgets.button(ui, "ed-prop-glb-export", "Export GLB", 92, false)).clicked) {
        if (state.window) |window| project_editor_prop_dialog.requestExportPropGlbDialog(state, window);
    }
    try core_ui.layout.endSameLine(ui);
}

fn togglePropLoopMode(state: *ProjectEditorState) void {
    state.prop_loop_mode = !state.prop_loop_mode;
    state.prop_tool = .edit;
    state.edit_tool = .edge;
    state.selected_vertex = null;
    state.selected_face = null;
    project_editor_state.setStatus(state, if (state.prop_loop_mode) "Prop edge loop drag on" else "Prop edge loop drag off");
}

pub fn buildInspector(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    if (state.selected_object) |idx| {
        const obj = &state.objects.items[idx];
        if ((try ui_widgets.collapsible(ui, "Prop", true))) {
            if (obj.prop_asset_id) |asset_id| {
                if (project_editor_prop.findCatalogEntry(asset_id)) |entry| {
                    var doc = project_editor_prop_asset.loadAssetDocument(state, entry.id) catch null;
                    defer if (doc) |*loaded| loaded.deinit(state.allocator);
                    const selected_label = if (doc) |loaded| loaded.label else entry.label;
                    const selected_tags = if (doc) |loaded| loaded.tags else null;
                    var detail_buf: [128]u8 = undefined;
                    _ = try ui_widgets.assetPreview(ui, .{
                        .id = "ed-prop-selected-summary",
                        .label = selected_label,
                        .detail = selectedPropSummary(entry, &detail_buf),
                        .fill_color = entry.color,
                        .shape = propPreviewShape(entry.kind),
                        .selected = true,
                    });
                    var recipe_buf: [128]u8 = undefined;
                    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&recipe_buf, "Recipe: {s}", .{shortRecipeLabel(entry)}) catch "Recipe");
                    var tag_buf: [128]u8 = undefined;
                    try ui_widgets.compactInfo(ui, if (selected_tags) |tags| propPersistedTagLine(tags, &tag_buf) else propTagLine(entry, &tag_buf));
                    try ui.label("Manage Asset");
                    try core_ui.layout.sameLine(ui);
                    if ((try ui_widgets.iconButtonTip(ui, "ed-prop-rename", "selective-tool", state.prop_metadata_editor_open, "Rename prop")).clicked) requestPropMetadataEdit(state);
                    if ((try ui_widgets.iconButtonTip(ui, "ed-prop-tags", "component", state.prop_metadata_editor_open, "Edit prop tags")).clicked) requestPropMetadataEdit(state);
                    if ((try ui_widgets.iconButtonTip(ui, "ed-prop-delete", "trash", isDeleteConfirming(state, entry.id), "Delete prop")).clicked) requestPropDelete(state);
                    try core_ui.layout.endSameLine(ui);
                    if (state.prop_tool != .asset and state.prop_metadata_editor_open) try buildPropMetadataEditor(ui, state, entry, "inspector");
                    if (state.prop_tool != .asset and isDeleteConfirming(state, entry.id)) {
                        try ui_widgets.compactInfo(ui, "Delete selected prop?");
                        try core_ui.layout.sameLine(ui);
                        if ((try ui_widgets.button(ui, "ed-prop-inspector-delete-cancel", "Cancel", 66, false)).clicked) cancelPropDelete(state);
                        if ((try ui_widgets.button(ui, "ed-prop-inspector-delete-confirm", "Delete", 68, true)).clicked) confirmPropDelete(state);
                        try core_ui.layout.endSameLine(ui);
                    }
                    try ui.label("Current Task");
                    try ui_widgets.compactInfo(ui, propTaskTitle(state.prop_tool));
                    try buildShapeSourceInspector(ui, state);
                    if (doc) |loaded| try buildPersistedShapeIntentInspector(ui, loaded);
                    if (state.prop_workspace_mode == .edit) {
                        if ((try ui_widgets.collapsible(ui, "Asset Actions", false))) {
                            try core_ui.layout.sameLine(ui);
                            if ((try ui_widgets.button(ui, "ed-prop-recipe-reset", "Regen", 62, false)).clicked) {
                                project_editor_prop.regenerateSelectedFromRecipe(state) catch project_editor_state.setStatus(state, "Recipe rebuild failed");
                            }
                            if ((try ui_widgets.button(ui, "ed-prop-sync-all", "Sync", 56, false)).clicked) {
                                project_editor_prop.propagateSelectedAssetGeometry(state);
                                project_editor_state.setStatus(state, "Prop instances synced");
                            }
                            try core_ui.layout.endSameLine(ui);
                            try core_ui.layout.sameLine(ui);
                            if ((try ui_widgets.button(ui, "ed-prop-shape-taper", "Taper", 62, false)).clicked) {
                                project_editor_prop.taperSelected(state, 0.28) catch project_editor_state.setStatus(state, "Prop taper failed");
                            }
                            if ((try ui_widgets.button(ui, "ed-prop-shape-mirror-x", "Mirror X", 78, false)).clicked) {
                                project_editor_prop.mirrorSelectedX(state) catch project_editor_state.setStatus(state, "Prop mirror failed");
                            }
                            if ((try ui_widgets.button(ui, "ed-prop-shape-array-x", "Array X", 70, false)).clicked) {
                                project_editor_prop.arraySelectedX(state) catch project_editor_state.setStatus(state, "Prop array failed");
                            }
                            try core_ui.layout.endSameLine(ui);
                        }
                    }
                } else {
                    var doc = project_editor_prop_asset.loadAssetDocument(state, asset_id) catch null;
                    defer if (doc) |*loaded| loaded.deinit(state.allocator);
                    if (doc) |loaded| {
                        _ = try ui_widgets.assetPreview(ui, .{
                            .id = "ed-prop-selected-project-summary",
                            .label = loaded.label,
                            .detail = "Project shape asset",
                            .fill_color = loaded.base_color,
                            .shape = propPreviewShape(.box),
                            .selected = true,
                        });
                        var tag_buf: [128]u8 = undefined;
                        try ui_widgets.compactInfo(ui, propPersistedTagLine(loaded.tags, &tag_buf));
                        try ui.label("Current Task");
                        try ui_widgets.compactInfo(ui, propTaskTitle(state.prop_tool));
                        try buildShapeSourceInspector(ui, state);
                        try buildPersistedShapeIntentInspector(ui, loaded);
                    } else {
                        var missing_buf: [128]u8 = undefined;
                        try core_ui.widgets_feedback.statusLabel(ui, std.fmt.bufPrint(
                            &missing_buf,
                            "Missing prop asset: {s}",
                            .{asset_id},
                        ) catch "Missing prop asset");
                    }
                }
            } else {
                try ui_widgets.compactInfo(ui, if (obj.primitive_kind == null) "Mesh: imported asset" else "Mesh: generated primitive");
            }
        }
        if (state.prop_workspace_mode == .edit and (try ui_widgets.collapsible(ui, "Paint", false))) {
            try ui_widgets.compactInfo(ui, "Paint directly on mesh");
            var quality_buf: [48]u8 = undefined;
            try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&quality_buf, "Quality {d}x  no UV setup", .{state.prop_texture_quality}) catch "Quality no UV setup");
            const variant_index = if (obj.variant) |variant| std.fmt.parseInt(u32, variant, 10) catch 0 else 0;
            state.prop_variant_index = variant_index;
            var variant_buf: [64]u8 = undefined;
            try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&variant_buf, "Variant {d}", .{variant_index}) catch "Variant");
            if ((try ui_widgets.button(ui, "ed-prop-cycle-variant", "Cycle Variant", 110, false)).clicked) {
                project_editor_prop.cycleSelectedVariant(state);
            }
        }
        if (state.prop_workspace_mode == .edit and (try ui_widgets.collapsible(ui, "Placement", false))) {
            try ui_widgets.compactInfo(ui, "Instance transform and tint");
            const align_surface = try core_ui.widgets_input.checkbox(ui, "Align To Surface", "ed-prop-align-surface");
            if (align_surface.checked != state.prop_align_to_surface) {
                state.prop_align_to_surface = align_surface.checked;
                project_editor_state.setStatus(state, if (align_surface.checked) "Align to surface on" else "Align to surface off");
            }
            const yaw = try core_ui.widgets_input.checkbox(ui, "Random Yaw", "ed-prop-random-yaw");
            if (yaw.checked != state.prop_random_yaw) {
                state.prop_random_yaw = yaw.checked;
                project_editor_state.setStatus(state, if (yaw.checked) "Random yaw on" else "Random yaw off");
            }
            const drop = try core_ui.widgets_input.checkbox(ui, "Drop To Ground", "ed-prop-drop-ground");
            if (drop.checked != state.prop_drop_to_ground) {
                state.prop_drop_to_ground = drop.checked;
                project_editor_state.setStatus(state, if (drop.checked) "Drop to ground on" else "Drop to ground off");
            }
        }
        if (state.prop_workspace_mode == .edit and (try ui_widgets.collapsible(ui, "Collider", state.prop_tool == .collider))) {
            try core_ui.widgets_feedback.statusLabel(ui, project_editor_physics.label(obj.physics));
            if (obj.physics) |body| {
                var collider_buf: [96]u8 = undefined;
                try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&collider_buf, "Type {s}", .{body.collider.label()}) catch "Collider");
                try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&collider_buf, "Size {d:.2} x {d:.2} x {d:.2}", .{ obj.scale.x, obj.scale.y, obj.scale.z }) catch "Size");
            } else {
                try ui_widgets.compactInfo(ui, "No collider on selection");
            }
            const trigger_checked = if (obj.physics) |body| body.trigger else false;
            if ((try ui_widgets.syncedCheckbox(ui, "Trigger", "ed-prop-trigger", trigger_checked)).clicked) {
                project_editor_prop.setTrigger(state, !trigger_checked);
            }
            try core_ui.layout.sameLine(ui);
            if ((try ui_widgets.button(ui, command_ids.physics_none, "None", 52, obj.physics == null)).clicked) project_editor_physics.setSelectedBody(state, null);
            if ((try ui_widgets.button(ui, command_ids.physics_static, "Static", 58, physicsSelected(obj, .static))).clicked) project_editor_physics.setSelectedBody(state, project_editor_physics.withKind(obj.physics, .static));
            if ((try ui_widgets.button(ui, "ed-collider-cycle", "Type", 58, false)).clicked) project_editor_physics.cycleCollider(state);
            try core_ui.layout.endSameLine(ui);
        }
        if (state.prop_workspace_mode == .edit and (try ui_widgets.collapsible(ui, "Gameplay", false))) {
            const interactable_checked = if (obj.gameplay) |gameplay| gameplay.interactable else false;
            if ((try ui_widgets.syncedCheckbox(ui, "Interactable", "ed-prop-interactable", interactable_checked)).clicked) {
                project_editor_prop.setInteractable(state, !interactable_checked);
            }
            if (obj.gameplay) |gameplay| {
                try ui.label("Tag");
                var tag_id_buf: [48]u8 = undefined;
                const tag_input = try core_ui.widgets_input.textInput(ui, .{
                    .id = std.fmt.bufPrint(&tag_id_buf, "ed-prop-gameplay-tag-{d}", .{obj.id}) catch "ed-prop-gameplay-tag",
                    .default_text = gameplay.tag,
                });
                if (tag_input.submitted) {
                    project_editor_prop.setGameplayTag(state, tag_input.text) catch |err| {
                        project_editor_state.setStatus(state, switch (err) {
                            error.EmptyGameplayTag => "Gameplay tag cannot be empty",
                            else => "Gameplay tag update failed",
                        });
                    };
                }
            } else {
                try core_ui.widgets_feedback.statusLabel(ui, "No gameplay tags");
                if ((try ui_widgets.button(ui, "ed-prop-add-gameplay", "Add Tags", 100, false)).clicked) try addGameplay(state, idx);
            }
        }
    } else {
        try buildShapeSourceInspector(ui, state);
        try core_ui.widgets_feedback.statusLabel(ui, "Select a prop to inspect placement and colliders");
    }
}

fn buildShapeSourceInspector(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    if (state.prop_workspace_mode != .edit or state.prop_tool != .edit) return;
    if (state.prop_sketch_mode == .none and state.prop_sketch_points.items.len == 0) return;
    const focus = shapeInspectorFocus(state);
    if (!(try ui_widgets.collapsible(ui, shapeInspectorTitleForFocus(focus), true))) return;

    const source_kind = activeShapeSourceKind(state);
    const operation_kind = activeShapeOperationKind(state);
    const source = activeShapeSource(state, source_kind);
    const operation = activeShapeOperation(state, operation_kind);

    switch (focus) {
        .source => {
            try shapeSourceSummary(ui, state, source_kind);
            try shapeSourcePointControls(ui, state);
            try shapeOperationSummary(ui, operation_kind);
            try shapeValidationStatus(ui, source, operation);
        },
        .operation => {
            try shapeOperationSummary(ui, operation_kind);
            try shapeOperationParameterControls(ui, state, operation_kind);
            try shapeValidationStatus(ui, source, operation);
            try shapeSourceSummary(ui, state, source_kind);
        },
        .mixed => {
            try shapeSourceSummary(ui, state, source_kind);
            try shapeSourcePointControls(ui, state);
            try shapeOperationSummary(ui, operation_kind);
            try shapeOperationParameterControls(ui, state, operation_kind);
            try shapeValidationStatus(ui, source, operation);
        },
    }
}

const ShapeInspectorFocus = enum {
    source,
    operation,
    mixed,
};

fn shapeInspectorFocus(state: *const ProjectEditorState) ShapeInspectorFocus {
    if (state.selected_shape_operation or state.selection_scope == .operation) return .operation;
    if (state.selected_shape_source or state.selection_scope == .source) return .source;
    return .mixed;
}

fn shapeInspectorTitle(state: *const ProjectEditorState) []const u8 {
    return shapeInspectorTitleForFocus(shapeInspectorFocus(state));
}

fn shapeInspectorTitleForFocus(focus: ShapeInspectorFocus) []const u8 {
    return switch (focus) {
        .source => "Shape Source",
        .operation => "Shape Operation",
        .mixed => "Shape Source / Operation",
    };
}

fn activeShapeSourceKind(state: *const ProjectEditorState) shape_source.Kind {
    return switch (state.prop_sketch_mode) {
        .face => .closed_face,
        .curve => .open_profile,
        .path => .path,
        .none => .primitive_seed,
    };
}

fn activeShapeOperationKind(state: *const ProjectEditorState) shape_operation.Kind {
    return switch (state.prop_sketch_mode) {
        .face => .solidify,
        .curve => .revolve,
        .path => .extrude,
        .none => .extrude,
    };
}

fn activeShapeSource(state: *const ProjectEditorState, source_kind: shape_source.Kind) shape_source.Source {
    return .{ .kind = source_kind, .points = state.prop_sketch_points.items };
}

fn activeShapeOperation(state: *const ProjectEditorState, operation_kind: shape_operation.Kind) shape_operation.Operation {
    return .{ .kind = operation_kind, .segments = state.prop_sketch_segments, .amount = state.prop_sketch_amount };
}

fn shapeSourceSummary(ui: *core_ui.UiContext, state: *const ProjectEditorState, source_kind: shape_source.Kind) !void {
    var source_buf: [96]u8 = undefined;
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(
        &source_buf,
        "{s}  {d} points",
        .{ shapeSourceLabel(source_kind), state.prop_sketch_points.items.len },
    ) catch "Shape source");
}

fn shapeOperationSummary(ui: *core_ui.UiContext, operation_kind: shape_operation.Kind) !void {
    var op_buf: [96]u8 = undefined;
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(
        &op_buf,
        "Operation {s}",
        .{shapeOperationLabel(operation_kind)},
    ) catch "Shape operation");
}

fn shapeValidationStatus(ui: *core_ui.UiContext, source: shape_source.Source, operation: shape_operation.Operation) !void {
    var validation_buf: [96]u8 = undefined;
    try core_ui.widgets_feedback.statusLabel(ui, shapeValidationText(source, operation, &validation_buf));
}

fn shapeValidationText(source: shape_source.Source, operation: shape_operation.Operation, buf: []u8) []const u8 {
    operation.validateForSource(source) catch |err| {
        return std.fmt.bufPrint(buf, "Invalid: {s}", .{shape_operation.validationErrorLabel(err)}) catch "Invalid source";
    };
    return "Valid source";
}

fn shapeSourcePointControls(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    if (state.prop_sketch_points.items.len == 0) return;
    try ui.label("Source Points");
    const max_visible_points: usize = 4;
    const visible_points = @min(state.prop_sketch_points.items.len, max_visible_points);
    for (state.prop_sketch_points.items[0..visible_points], 0..) |*point, index| {
        var point_buf: [32]u8 = undefined;
        try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&point_buf, "P{d}", .{index}) catch "Point");
        try shapePointCoordinateInput(ui, state, point, index, "x", .x);
        try shapePointCoordinateInput(ui, state, point, index, "y", .y);
        try shapePointCoordinateInput(ui, state, point, index, "z", .z);
    }
    if (state.prop_sketch_points.items.len > max_visible_points) {
        var more_buf: [48]u8 = undefined;
        try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&more_buf, "{d} more points", .{state.prop_sketch_points.items.len - max_visible_points}) catch "More points");
    }
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.button(ui, "ed-prop-sketch-remove-last", "Remove Last", 104, false)).clicked) {
        _ = state.prop_sketch_points.pop();
        project_editor_state.setStatus(state, "Sketch point removed");
    }
    if ((try ui_widgets.button(ui, "ed-prop-sketch-clear-inspector", "Clear", 58, false)).clicked) {
        state.prop_sketch_points.clearRetainingCapacity();
        state.selected_shape_source = false;
        state.selected_shape_operation = false;
        project_editor_state.setStatus(state, "Sketch cleared");
    }
    try core_ui.layout.endSameLine(ui);
}

const ShapePointAxis = enum { x, y, z };

fn shapePointCoordinateInput(ui: *core_ui.UiContext, state: *ProjectEditorState, point: *editor_math.Vec3, index: usize, axis_label: []const u8, axis: ShapePointAxis) !void {
    try ui_widgets.compactInfo(ui, axis_label);
    var id_buf: [64]u8 = undefined;
    const value = switch (axis) {
        .x => point.x,
        .y => point.y,
        .z => point.z,
    };
    const input = try core_ui.widgets_input.numberInput(ui, .{
        .id = std.fmt.bufPrint(&id_buf, "ed-prop-sketch-point-{d}-{s}", .{ index, axis_label }) catch "ed-prop-sketch-point",
        .value = value,
        .min = -1000.0,
        .max = 1000.0,
        .speed = 0.05,
    });
    if (input.changed and @abs(input.value - value) > 0.0001) {
        switch (axis) {
            .x => point.x = input.value,
            .y => point.y = input.value,
            .z => point.z = input.value,
        }
        project_editor_state.setStatus(state, "Sketch point updated");
    }
}

fn shapeOperationParameterControls(ui: *core_ui.UiContext, state: *ProjectEditorState, operation_kind: shape_operation.Kind) !void {
    try ui.label("Parameters");
    try ui_widgets.compactInfo(ui, "Amount");
    const amount = try core_ui.widgets_input.numberInput(ui, .{
        .id = "ed-prop-sketch-amount",
        .value = state.prop_sketch_amount,
        .min = 0.001,
        .max = if (operation_kind == .inset or operation_kind == .bevel) 0.49 else 100.0,
        .speed = 0.01,
    });
    if (amount.changed and @abs(amount.value - state.prop_sketch_amount) > 0.0001) {
        state.prop_sketch_amount = amount.value;
        project_editor_state.setStatus(state, "Shape amount updated");
    }
    if (operation_kind == .revolve) {
        try ui_widgets.compactInfo(ui, "Segments");
        const segments = try core_ui.widgets_input.numberInput(ui, .{
            .id = "ed-prop-sketch-segments",
            .value = @floatFromInt(state.prop_sketch_segments),
            .min = 3.0,
            .max = 128.0,
            .speed = 1.0,
        });
        const next_segments: u32 = @intFromFloat(@round(segments.value));
        if (segments.changed and next_segments != state.prop_sketch_segments) {
            state.prop_sketch_segments = next_segments;
            project_editor_state.setStatus(state, "Shape segments updated");
        }
    }
}

fn buildPersistedShapeIntentInspector(ui: *core_ui.UiContext, doc: prop_asset_doc.PropAssetDocument) !void {
    if (doc.recipe.shape_intents.len == 0) return;
    if (!(try ui_widgets.collapsible(ui, "Saved Shape Intent", true))) return;

    const latest = doc.recipe.shape_intents[doc.recipe.shape_intents.len - 1];
    var op_buf: [96]u8 = undefined;
    var source_label_buf: [64]u8 = undefined;
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(
        &op_buf,
        "{s} from {s}",
        .{
            shapeOperationIntentLabel(latest.operation_kind),
            shapeIntentSourceLabel(latest, &source_label_buf),
        },
    ) catch "Saved operation");

    var size_buf: [96]u8 = undefined;
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(
        &size_buf,
        "{d} point{s}  amount {d:.2}",
        .{
            latest.points.len,
            if (latest.points.len == 1) "" else "s",
            latest.amount,
        },
    ) catch "Saved source points");

    var count_buf: [96]u8 = undefined;
    try core_ui.widgets_feedback.statusLabel(ui, std.fmt.bufPrint(
        &count_buf,
        "{d} saved shape intent{s}",
        .{
            doc.recipe.shape_intents.len,
            if (doc.recipe.shape_intents.len == 1) "" else "s",
        },
    ) catch "Saved shape intent");
}

fn shapeSourceLabel(kind: shape_source.Kind) []const u8 {
    return switch (kind) {
        .closed_face => "Closed face",
        .open_profile => "Open profile",
        .path => "Path",
        .primitive_seed => "Primitive seed",
    };
}

fn shapeSourceIntentLabel(kind: prop_asset_doc.ShapeSourceKind) []const u8 {
    return switch (kind) {
        .closed_face => "Closed face",
        .open_profile => "Open profile",
        .path => "Path",
        .primitive_seed => "Primitive seed",
        .existing_mesh => "Existing mesh",
    };
}

fn shapeIntentSourceLabel(intent: prop_asset_doc.ShapeIntent, buf: []u8) []const u8 {
    if (intent.source_kind == .primitive_seed) {
        return std.fmt.bufPrint(buf, "{s} seed", .{prop_asset_doc.primitiveKindName(intent.primitive_kind)}) catch "Primitive seed";
    }
    return shapeSourceIntentLabel(intent.source_kind);
}

fn shapeOperationLabel(kind: shape_operation.Kind) []const u8 {
    return switch (kind) {
        .extrude => "Extrude",
        .solidify => "Solidify",
        .revolve => "Revolve",
        .cut => "Cut",
        .inset => "Inset",
        .bevel => "Bevel",
        .mirror => "Mirror",
        .array => "Array",
    };
}

fn shapeOperationIntentLabel(kind: prop_asset_doc.ShapeOperationKind) []const u8 {
    return switch (kind) {
        .extrude => "Extrude",
        .solidify => "Solidify",
        .revolve => "Revolve",
        .cut => "Cut",
        .inset => "Inset",
        .bevel => "Bevel",
        .mirror => "Mirror",
        .array => "Array",
    };
}

pub fn buildBottomStrip(ui: *core_ui.UiContext, state: *ProjectEditorState, rect: core_ui.Rect) !void {
    _ = ui;
    _ = state;
    _ = rect;
}

pub fn drawViewportOverlays(state: *ProjectEditorState, vp_w: f32, vp_h: f32) void {
    if (state.prop_tool == .edit) drawSketchPreview(state, vp_w, vp_h);
    if (state.prop_collider_preview) drawColliderPreviews(state, vp_w, vp_h);
    if (showsPlacementGhost(state)) drawPlacementGhost(state, vp_w, vp_h);
    project_editor_prop.refreshPlacementPreview(state);
}

pub fn appendGpuViewportOverlays(state: *ProjectEditorState, allocator: std.mem.Allocator, out: *std.ArrayList(OverlayQuad)) !void {
    if (state.mode != .prop_creation) return;
    const vp_w = state.viewport_screen_rect.w;
    const vp_h = state.viewport_screen_rect.h;
    if (state.prop_tool == .edit) try appendGpuSketchPreview(state, allocator, out, vp_w, vp_h);
    if (state.prop_tool == .material) try appendGpuPaintPreview(state, allocator, out, vp_w, vp_h);
}

fn drawSketchPreview(state: *ProjectEditorState, vp_w: f32, vp_h: f32) void {
    if (state.prop_sketch_mode == .none) return;
    if (state.prop_sketch_points.items.len == 0) return;
    const idx = state.selected_object orelse return;
    const obj = &state.objects.items[idx];
    const bounds = editor_raycast.objectWorldBounds(obj);
    const center = editor_math.Vec3.scale(editor_math.Vec3.add(bounds.min, bounds.max), 0.5);
    const screen_center = project_editor_state.projectViewportPoint(state, center, vp_w, vp_h) orelse return;
    const scale = @max(44.0, @min(vp_w, vp_h) * 0.105);
    const x = @max(54.0, screen_center.x - scale * 2.2);
    const y = screen_center.y - scale * 0.55;
    switch (state.prop_sketch_mode) {
        .none => {},
        .face => {
            const pts = [_]editor_math.Vec2{
                .{ .x = x - scale * 0.58, .y = y - scale * 0.34 },
                .{ .x = x + scale * 0.62, .y = y - scale * 0.22 },
                .{ .x = x + scale * 0.48, .y = y + scale * 0.42 },
                .{ .x = x - scale * 0.66, .y = y + scale * 0.30 },
            };
            drawScreenLoop(state, pts[0..], .{ .r = 125, .g = 223, .b = 247, .a = 245 });
            for (pts) |pt| project_editor_viewport.drawViewportSquare(state, pt.x, pt.y, 4, .{ .r = 255, .g = 240, .b = 150, .a = 255 });
        },
        .curve => {
            const pts = [_]editor_math.Vec2{
                .{ .x = x - scale * 0.18, .y = y - scale * 0.66 },
                .{ .x = x + scale * 0.42, .y = y - scale * 0.26 },
                .{ .x = x + scale * 0.22, .y = y + scale * 0.18 },
                .{ .x = x + scale * 0.56, .y = y + scale * 0.62 },
            };
            drawScreenPolyline(state, pts[0..], .{ .r = 125, .g = 223, .b = 247, .a = 245 });
            drawRevolveAxis(state, x - scale * 0.34, y - scale * 0.78, y + scale * 0.76);
            for (pts) |pt| project_editor_viewport.drawViewportSquare(state, pt.x, pt.y, 4, .{ .r = 255, .g = 240, .b = 150, .a = 255 });
        },
        .path => {
            const pts = [_]editor_math.Vec2{
                .{ .x = x - scale * 0.62, .y = y - scale * 0.22 },
                .{ .x = x - scale * 0.18, .y = y + scale * 0.12 },
                .{ .x = x + scale * 0.26, .y = y - scale * 0.04 },
                .{ .x = x + scale * 0.68, .y = y + scale * 0.34 },
            };
            drawScreenPolyline(state, pts[0..], .{ .r = 125, .g = 223, .b = 247, .a = 245 });
            for (pts) |pt| project_editor_viewport.drawViewportSquare(state, pt.x, pt.y, 4, .{ .r = 255, .g = 240, .b = 150, .a = 255 });
        },
    }
}

fn appendGpuSketchPreview(
    state: *ProjectEditorState,
    allocator: std.mem.Allocator,
    out: *std.ArrayList(OverlayQuad),
    vp_w: f32,
    vp_h: f32,
) !void {
    if (state.prop_sketch_mode == .none) return;
    if (state.prop_sketch_points.items.len > 0) {
        try appendGpuPlacedSketch(state, allocator, out, vp_w, vp_h);
        return;
    }
}

fn appendGpuPaintPreview(
    state: *ProjectEditorState,
    allocator: std.mem.Allocator,
    out: *std.ArrayList(OverlayQuad),
    vp_w: f32,
    vp_h: f32,
) !void {
    const center = paintPreviewCenter(state, vp_w, vp_h) orelse return;
    const radius = std.math.clamp(state.brush_radius * @min(vp_w, vp_h) * 2.1, 18.0, 86.0);
    const color: shared.color.Color = .{
        .r = state.brush_color.r,
        .g = state.brush_color.g,
        .b = state.brush_color.b,
        .a = 230,
    };
    const soft: shared.color.Color = .{ .r = color.r, .g = color.g, .b = color.b, .a = 82 };
    try appendGpuScreenCircle(state, allocator, out, center, radius, soft, 7.0);
    try appendGpuScreenCircle(state, allocator, out, center, radius, color, 3.0);
    try appendGpuScreenLine(state, allocator, out, .{ .x = center.x - radius * 0.32, .y = center.y }, .{ .x = center.x + radius * 0.32, .y = center.y }, color, 3.0);
    try appendGpuScreenLine(state, allocator, out, .{ .x = center.x, .y = center.y - radius * 0.32 }, .{ .x = center.x, .y = center.y + radius * 0.32 }, color, 3.0);
    try appendGpuScreenSquare(state, allocator, out, center, .{ .r = 255, .g = 255, .b = 255, .a = 230 }, 5.0);
}

fn paintPreviewCenter(state: *ProjectEditorState, vp_w: f32, vp_h: f32) ?editor_math.Vec2 {
    const fallback = editor_math.Vec2{ .x = vp_w * 0.5, .y = vp_h * 0.5 };
    const prop_center = selectedPropScreenCenter(state, vp_w, vp_h) orelse fallback;
    const local_mouse = editor_math.Vec2{
        .x = state.mouse_x - state.viewport_screen_rect.x,
        .y = state.mouse_y - state.viewport_screen_rect.y,
    };
    if (local_mouse.x >= 0 and local_mouse.y >= 0 and local_mouse.x <= vp_w and local_mouse.y <= vp_h) {
        const dx = local_mouse.x - prop_center.x;
        const dy = local_mouse.y - prop_center.y;
        const max_dist = @min(vp_w, vp_h) * 0.10;
        if (dx * dx + dy * dy <= max_dist * max_dist) return local_mouse;
    }
    return prop_center;
}

fn selectedPropScreenCenter(state: *ProjectEditorState, vp_w: f32, vp_h: f32) ?editor_math.Vec2 {
    const fallback = editor_math.Vec2{ .x = vp_w * 0.5, .y = vp_h * 0.5 };
    const idx = state.selected_object orelse return fallback;
    const obj = &state.objects.items[idx];
    const bounds = editor_raycast.objectWorldBounds(obj);
    const center_world = editor_math.Vec3.scale(editor_math.Vec3.add(bounds.min, bounds.max), 0.5);
    return project_editor_state.projectViewportPoint(state, center_world, vp_w, vp_h) orelse fallback;
}

fn appendGpuScreenCircle(
    state: *ProjectEditorState,
    allocator: std.mem.Allocator,
    out: *std.ArrayList(OverlayQuad),
    center: editor_math.Vec2,
    radius: f32,
    color: shared.color.Color,
    size: f32,
) !void {
    var prev: ?editor_math.Vec2 = null;
    var i: usize = 0;
    while (i <= 72) : (i += 1) {
        const angle = (@as(f32, @floatFromInt(i)) / 72.0) * std.math.tau;
        const point = editor_math.Vec2{
            .x = center.x + @cos(angle) * radius,
            .y = center.y + @sin(angle) * radius,
        };
        if (prev) |p| try appendGpuScreenLine(state, allocator, out, p, point, color, size);
        prev = point;
    }
}

fn appendGpuPlacedSketch(
    state: *ProjectEditorState,
    allocator: std.mem.Allocator,
    out: *std.ArrayList(OverlayQuad),
    vp_w: f32,
    vp_h: f32,
) !void {
    const line_color: shared.color.Color = .{ .r = 108, .g = 222, .b = 246, .a = 245 };
    const handle_color: shared.color.Color = .{ .r = 255, .g = 236, .b = 132, .a = 255 };
    const ghost_color: shared.color.Color = .{ .r = 108, .g = 222, .b = 246, .a = 96 };
    const pts = state.prop_sketch_points.items;

    var prev: ?editor_math.Vec3 = null;
    for (pts) |pt| {
        if (prev) |p| try appendGpuWorldLine(state, allocator, out, p, pt, vp_w, vp_h, line_color, 4.0);
        try appendGpuProjectedSquare(state, allocator, out, pt, vp_w, vp_h, .{ .r = 20, .g = 24, .b = 28, .a = 230 }, 13.0);
        try appendGpuProjectedSquare(state, allocator, out, pt, vp_w, vp_h, handle_color, 8.0);
        prev = pt;
    }

    if (state.prop_sketch_mode == .face and pts.len >= 3) {
        try appendGpuSketchFaceFill(state, allocator, out, pts, vp_w, vp_h, .{ .r = 108, .g = 222, .b = 246, .a = 58 });
        try appendGpuWorldLine(state, allocator, out, pts[pts.len - 1], pts[0], vp_w, vp_h, line_color, 4.0);
        const lift = editor_math.Vec3{ .x = 0, .y = 0.38, .z = 0 };
        for (pts) |pt| {
            const lifted = editor_math.Vec3.add(pt, lift);
            try appendGpuWorldLine(state, allocator, out, pt, lifted, vp_w, vp_h, ghost_color, 3.0);
            try appendGpuProjectedSquare(state, allocator, out, lifted, vp_w, vp_h, ghost_color, 6.0);
        }
        var i: usize = 0;
        while (i < pts.len) : (i += 1) {
            const a = editor_math.Vec3.add(pts[i], lift);
            const b = editor_math.Vec3.add(pts[(i + 1) % pts.len], lift);
            try appendGpuWorldLine(state, allocator, out, a, b, vp_w, vp_h, ghost_color, 3.0);
        }
    } else if (state.prop_sketch_mode == .curve and pts.len >= 2) {
        const x = pts[0].x;
        const min_z = minSketchZ(pts);
        const max_z = maxSketchZ(pts);
        const a = editor_math.Vec3{ .x = x - 0.35, .y = 0, .z = min_z - 0.2 };
        const b = editor_math.Vec3{ .x = x - 0.35, .y = 0, .z = max_z + 0.2 };
        try appendGpuWorldLine(state, allocator, out, a, b, vp_w, vp_h, .{ .r = 255, .g = 236, .b = 132, .a = 225 }, 4.0);
        try appendGpuProjectedSquare(state, allocator, out, a, vp_w, vp_h, handle_color, 7.0);
        try appendGpuProjectedSquare(state, allocator, out, b, vp_w, vp_h, handle_color, 7.0);
    }
}

fn appendGpuSketchFaceFill(
    state: *ProjectEditorState,
    allocator: std.mem.Allocator,
    out: *std.ArrayList(OverlayQuad),
    pts: []const editor_math.Vec3,
    vp_w: f32,
    vp_h: f32,
    color: shared.color.Color,
) !void {
    if (pts.len < 3) return;
    var min_x: f32 = std.math.floatMax(f32);
    var min_y: f32 = std.math.floatMax(f32);
    var max_x: f32 = -std.math.floatMax(f32);
    var max_y: f32 = -std.math.floatMax(f32);
    for (pts) |pt| {
        const screen = project_editor_state.projectViewportPoint(state, pt, vp_w, vp_h) orelse return;
        if (!std.math.isFinite(screen.x) or !std.math.isFinite(screen.y)) return;
        min_x = @min(min_x, screen.x);
        min_y = @min(min_y, screen.y);
        max_x = @max(max_x, screen.x);
        max_y = @max(max_y, screen.y);
    }
    const rect = .{
        state.viewport_screen_rect.x + min_x,
        state.viewport_screen_rect.y + min_y,
        @max(1.0, max_x - min_x),
        @max(1.0, max_y - min_y),
    };
    try out.append(allocator, .{ .rect = rect, .color = color });
}

fn appendGpuGhostSketch(
    state: *ProjectEditorState,
    allocator: std.mem.Allocator,
    out: *std.ArrayList(OverlayQuad),
    vp_w: f32,
    vp_h: f32,
) !void {
    const idx = state.selected_object orelse return;
    const obj = &state.objects.items[idx];
    const bounds = editor_raycast.objectWorldBounds(obj);
    const center = editor_math.Vec3.scale(editor_math.Vec3.add(bounds.min, bounds.max), 0.5);
    const half_x = @max(0.28, (bounds.max.x - bounds.min.x) * 0.42);
    const z = bounds.max.z + 0.28;
    const base_y = bounds.min.y + @max(0.18, (bounds.max.y - bounds.min.y) * 0.16);
    const color: shared.color.Color = .{ .r = 108, .g = 222, .b = 246, .a = 92 };
    const handle_color: shared.color.Color = .{ .r = 255, .g = 236, .b = 132, .a = 150 };

    switch (state.prop_sketch_mode) {
        .none => {},
        .face => {
            const pts = [_]editor_math.Vec3{
                .{ .x = center.x - half_x, .y = base_y, .z = z },
                .{ .x = center.x + half_x, .y = base_y, .z = z },
                .{ .x = center.x + half_x * 0.7, .y = base_y + 0.42, .z = z },
                .{ .x = center.x - half_x * 0.85, .y = base_y + 0.34, .z = z },
            };
            try appendGpuWorldLoop(state, allocator, out, pts[0..], vp_w, vp_h, color, 2.0);
            for (pts) |pt| try appendGpuProjectedSquare(state, allocator, out, pt, vp_w, vp_h, handle_color, 5.0);
        },
        .curve => {
            const pts = [_]editor_math.Vec3{
                .{ .x = center.x - half_x * 0.35, .y = base_y, .z = z - 0.32 },
                .{ .x = center.x + half_x * 0.38, .y = base_y + 0.18, .z = z - 0.08 },
                .{ .x = center.x + half_x * 0.16, .y = base_y + 0.38, .z = z + 0.16 },
                .{ .x = center.x + half_x * 0.55, .y = base_y + 0.58, .z = z + 0.36 },
            };
            try appendGpuWorldPolyline(state, allocator, out, pts[0..], vp_w, vp_h, color, 2.0);
            const axis_a = editor_math.Vec3{ .x = center.x - half_x * 0.58, .y = base_y - 0.05, .z = z - 0.42 };
            const axis_b = editor_math.Vec3{ .x = center.x - half_x * 0.58, .y = base_y + 0.66, .z = z + 0.42 };
            try appendGpuWorldLine(state, allocator, out, axis_a, axis_b, vp_w, vp_h, handle_color, 2.0);
            for (pts) |pt| try appendGpuProjectedSquare(state, allocator, out, pt, vp_w, vp_h, handle_color, 5.0);
        },
        .path => {
            const pts = [_]editor_math.Vec3{
                .{ .x = center.x - half_x * 0.7, .y = base_y, .z = z - 0.4 },
                .{ .x = center.x - half_x * 0.1, .y = base_y + 0.1, .z = z - 0.1 },
                .{ .x = center.x + half_x * 0.45, .y = base_y + 0.05, .z = z + 0.2 },
                .{ .x = center.x + half_x * 0.72, .y = base_y + 0.16, .z = z + 0.48 },
            };
            try appendGpuWorldPolyline(state, allocator, out, pts[0..], vp_w, vp_h, color, 2.0);
            for (pts) |pt| try appendGpuProjectedSquare(state, allocator, out, pt, vp_w, vp_h, handle_color, 5.0);
        },
    }
}

fn appendGpuWorldLoop(
    state: *ProjectEditorState,
    allocator: std.mem.Allocator,
    out: *std.ArrayList(OverlayQuad),
    pts: []const editor_math.Vec3,
    vp_w: f32,
    vp_h: f32,
    color: shared.color.Color,
    size: f32,
) !void {
    try appendGpuWorldPolyline(state, allocator, out, pts, vp_w, vp_h, color, size);
    if (pts.len >= 2) try appendGpuWorldLine(state, allocator, out, pts[pts.len - 1], pts[0], vp_w, vp_h, color, size);
}

fn appendGpuWorldPolyline(
    state: *ProjectEditorState,
    allocator: std.mem.Allocator,
    out: *std.ArrayList(OverlayQuad),
    pts: []const editor_math.Vec3,
    vp_w: f32,
    vp_h: f32,
    color: shared.color.Color,
    size: f32,
) !void {
    if (pts.len < 2) return;
    var prev = pts[0];
    for (pts[1..]) |pt| {
        try appendGpuWorldLine(state, allocator, out, prev, pt, vp_w, vp_h, color, size);
        prev = pt;
    }
}

fn appendGpuWorldLine(
    state: *ProjectEditorState,
    allocator: std.mem.Allocator,
    out: *std.ArrayList(OverlayQuad),
    a: editor_math.Vec3,
    b: editor_math.Vec3,
    vp_w: f32,
    vp_h: f32,
    color: shared.color.Color,
    size: f32,
) !void {
    const s0 = project_editor_state.projectViewportPoint(state, a, vp_w, vp_h) orelse return;
    const s1 = project_editor_state.projectViewportPoint(state, b, vp_w, vp_h) orelse return;
    try appendGpuScreenLine(state, allocator, out, s0, s1, color, size);
}

fn appendGpuScreenLine(
    state: *ProjectEditorState,
    allocator: std.mem.Allocator,
    out: *std.ArrayList(OverlayQuad),
    a: editor_math.Vec2,
    b: editor_math.Vec2,
    color: shared.color.Color,
    size: f32,
) !void {
    if (!std.math.isFinite(a.x) or !std.math.isFinite(a.y) or !std.math.isFinite(b.x) or !std.math.isFinite(b.y)) return;
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    const dist = @sqrt(dx * dx + dy * dy);
    const steps: usize = @intFromFloat(@max(1.0, @ceil(dist / @max(2.0, size * 0.65))));
    var i: usize = 0;
    while (i <= steps) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps));
        try appendGpuScreenSquare(state, allocator, out, .{ .x = a.x + dx * t, .y = a.y + dy * t }, color, size);
    }
}

fn appendGpuProjectedSquare(
    state: *ProjectEditorState,
    allocator: std.mem.Allocator,
    out: *std.ArrayList(OverlayQuad),
    point: editor_math.Vec3,
    vp_w: f32,
    vp_h: f32,
    color: shared.color.Color,
    size: f32,
) !void {
    const screen = project_editor_state.projectViewportPoint(state, point, vp_w, vp_h) orelse return;
    try appendGpuScreenSquare(state, allocator, out, screen, color, size);
}

fn appendGpuScreenSquare(
    state: *ProjectEditorState,
    allocator: std.mem.Allocator,
    out: *std.ArrayList(OverlayQuad),
    screen: editor_math.Vec2,
    color: shared.color.Color,
    size: f32,
) !void {
    if (!std.math.isFinite(screen.x) or !std.math.isFinite(screen.y)) return;
    if (screen.x < -size or screen.y < -size or screen.x > state.viewport_screen_rect.w + size or screen.y > state.viewport_screen_rect.h + size) return;
    const half = size * 0.5;
    try out.append(allocator, .{
        .rect = .{
            state.viewport_screen_rect.x + screen.x - half,
            state.viewport_screen_rect.y + screen.y - half,
            size,
            size,
        },
        .color = color,
    });
}

fn minSketchZ(pts: []const editor_math.Vec3) f32 {
    var value = pts[0].z;
    for (pts[1..]) |pt| value = @min(value, pt.z);
    return value;
}

fn maxSketchZ(pts: []const editor_math.Vec3) f32 {
    var value = pts[0].z;
    for (pts[1..]) |pt| value = @max(value, pt.z);
    return value;
}

fn drawScreenLoop(state: *ProjectEditorState, pts: []const editor_math.Vec2, color: shared.color.Color) void {
    drawScreenPolyline(state, pts, color);
    if (pts.len < 2) return;
    const a = pts[pts.len - 1];
    const b = pts[0];
    project_editor_viewport.drawViewportLine(state, a.x, a.y, b.x, b.y, color);
}

fn drawScreenPolyline(state: *ProjectEditorState, pts: []const editor_math.Vec2, color: shared.color.Color) void {
    if (pts.len < 2) return;
    var prev = pts[0];
    for (pts[1..]) |pt| {
        project_editor_viewport.drawViewportLine(state, prev.x, prev.y, pt.x, pt.y, color);
        prev = pt;
    }
}

fn drawRevolveAxis(state: *ProjectEditorState, x: f32, y0: f32, y1: f32) void {
    const color: shared.color.Color = .{ .r = 255, .g = 240, .b = 150, .a = 220 };
    project_editor_viewport.drawViewportLine(state, x, y0, x, y1, color);
    project_editor_viewport.drawViewportSquare(state, x, y0, 3, color);
    project_editor_viewport.drawViewportSquare(state, x, y1, 3, color);
}

fn setPropTool(state: *ProjectEditorState, tool: PropTool) void {
    state.prop_workspace_mode = .edit;
    state.prop_tool = tool;
    project_editor_state.setStatus(state, switch (tool) {
        .select => "Prop select tool",
        .create => "Prop create tool",
        .asset => "Browse props: click an asset to open it",
        .primitive => "Prop primitive placement tool",
        .edit => "Prop edit tool",
        .material => "Prop material tool",
        .collider => "Prop collider tool",
        .variants => "Prop variants tool: click a prop to cycle",
    });
}

fn setPropDisplayMode(state: *ProjectEditorState) void {
    state.prop_workspace_mode = .display;
    state.prop_tool = .select;
    state.shading_mode = .rendered;
    state.selected_vertex = null;
    state.selected_edge = null;
    state.selected_face = null;
    project_editor_state.setStatus(state, "Display mode");
}

fn setPropEditTool(state: *ProjectEditorState, tool: EditTool) void {
    state.prop_workspace_mode = .edit;
    state.prop_tool = .edit;
    state.edit_tool = tool;
    state.selected_vertex = null;
    state.selected_edge = null;
    state.selected_face = null;
    if (tool != .edge) state.prop_loop_mode = false;
    project_editor_state.setStatus(state, switch (tool) {
        .vertex => "Prop vertex edit: click and drag vertices",
        .edge => if (state.prop_loop_mode) "Prop edge loop edit: click and drag edges" else "Prop edge edit: click and drag edges",
        .face => "Prop face edit: click and drag faces",
        .extrude => "Prop face extrude",
        .inset => "Prop face inset",
    });
}

fn propToolbarIcon(tool: PropTool) []const u8 {
    return switch (tool) {
        .select => "select",
        .create => "add",
        .asset => "assets",
        .primitive => "box",
        .edit => "mesh",
        .material => "material",
        .collider => "physics",
        .variants => "duplicate",
    };
}

fn propToolbarTip(tool: PropTool) []const u8 {
    return switch (tool) {
        .select => "Select prop",
        .create => "New prop",
        .asset => "Prop library",
        .primitive => "Draw shape",
        .edit => "Shape builder",
        .material => "Texture paint",
        .collider => "Collider fit",
        .variants => "Variants",
    };
}

fn propTaskTitle(tool: PropTool) []const u8 {
    return switch (tool) {
        .select => "Select Prop",
        .create, .primitive => "Draw Shape",
        .asset => "Prop Library",
        .edit => "Shape Builder",
        .material => "Texture Paint",
        .collider => "Collider Fit",
        .variants => "Variants",
    };
}

fn propTaskHint(tool: PropTool) []const u8 {
    return switch (tool) {
        .select => "Click a prop to inspect it",
        .create, .primitive => "Pick base, sketch, make solid",
        .asset => "Find, tag, sort, or open props",
        .edit => "Faces, edges, extrude, solidify",
        .material => "Paint directly on the prop",
        .collider => "Preview and fit gameplay collision",
        .variants => "Create quick prop alternates",
    };
}

fn sketchActionHint(state: *const ProjectEditorState) []const u8 {
    return switch (state.prop_sketch_mode) {
        .none => "Choose Draw Face, Curve, or Path",
        .face => if (state.prop_sketch_points.items.len >= 3) "Ready: Solidify" else "Click 3+ points",
        .curve => if (state.prop_sketch_points.items.len >= 2) "Ready: Revolve" else "Click 2+ points",
        .path => if (state.prop_sketch_points.items.len >= 2) "Ready: Extrude" else "Click 2+ points",
    };
}

fn propRenderModeLabel(mode: ShadingMode) []const u8 {
    return switch (mode) {
        .wireframe => "Wire",
        .solid => "Solid",
        .material_preview => "Material",
        .lod_debug => "LOD",
        .rendered => "Rendered",
    };
}

fn propRenderModeId(mode: ShadingMode) []const u8 {
    return switch (mode) {
        .wireframe => "ed-prop-view-wireframe",
        .solid => "ed-prop-view-solid",
        .material_preview => "ed-prop-view-material-preview",
        .lod_debug => "ed-prop-view-lod-debug",
        .rendered => "ed-prop-view-rendered",
    };
}

fn propRenderModeWidth(mode: ShadingMode) f32 {
    return switch (mode) {
        .wireframe, .solid => 58,
        .material_preview => 74,
        .lod_debug => 58,
        .rendered => 84,
    };
}

fn editButtonId(tool: EditTool) []const u8 {
    return switch (tool) {
        .vertex => "ed-prop-edit-vertex",
        .edge => "ed-prop-edit-edge",
        .face => "ed-prop-edit-face",
        .extrude => "ed-prop-edit-extrude",
        .inset => "ed-prop-edit-inset",
    };
}

fn primitiveToolbarLabel(prim: PropPrimitive) []const u8 {
    return switch (prim) {
        .cube => "Cube",
        .cylinder => "Cyl",
        .plane => "Plane",
        .ramp => "Ramp",
    };
}

fn primitiveButton(ui: *core_ui.UiContext, state: *ProjectEditorState, prim: PropPrimitive) !void {
    if ((try ui_widgets.button(ui, primitiveButtonId(prim), primitiveToolbarLabel(prim), 62, state.prop_primitive == prim)).clicked) {
        selectPrimitive(state, prim);
    }
}

fn primitiveStarterPreview(ui: *core_ui.UiContext, state: *ProjectEditorState, prim: PropPrimitive) !void {
    if ((try ui_widgets.assetPreview(ui, .{
        .id = primitiveButtonId(prim),
        .label = prim.label(),
        .detail = primitiveStarterDetail(prim),
        .fill_color = primitiveStarterColor(prim),
        .shape = primitiveStarterShape(prim),
        .selected = state.prop_primitive == prim,
    })).clicked) {
        selectPrimitive(state, prim);
    }
}

fn primitiveStarterDetail(prim: PropPrimitive) []const u8 {
    return switch (prim) {
        .cube => "Solid block",
        .cylinder => "Barrel or post",
        .plane => "Face to solidify",
        .ramp => "Sloped wedge",
    };
}

fn primitiveStarterColor(prim: PropPrimitive) shared.color.Color {
    return switch (prim) {
        .cube => .{ .r = 150, .g = 180, .b = 220, .a = 255 },
        .cylinder => .{ .r = 210, .g = 150, .b = 90, .a = 255 },
        .plane => .{ .r = 90, .g = 190, .b = 170, .a = 255 },
        .ramp => .{ .r = 190, .g = 170, .b = 100, .a = 255 },
    };
}

fn primitiveStarterShape(prim: PropPrimitive) core_ui.commands.AssetPreviewShape {
    return switch (prim) {
        .cube => .box,
        .cylinder => .cylinder,
        .plane, .ramp => .plane,
    };
}

pub fn propAssetDetail(entry: project_editor_prop.CatalogEntry, buf: []u8) []const u8 {
    return std.fmt.bufPrint(buf, "{s}  {d} alt{s}", .{
        project_editor_prop.primitiveLabel(entry.recipe.base_kind),
        entry.variant_count,
        if (entry.variant_count == 1) "" else "s",
    }) catch entry.id;
}

fn selectedPropSummary(entry: project_editor_prop.CatalogEntry, buf: []u8) []const u8 {
    return std.fmt.bufPrint(buf, "{s}  {d} alt{s}", .{
        project_editor_prop.primitiveLabel(entry.recipe.base_kind),
        entry.variant_count,
        if (entry.variant_count == 1) "" else "s",
    }) catch entry.id;
}

fn shortRecipeLabel(entry: project_editor_prop.CatalogEntry) []const u8 {
    if (entry.recipe.shaping.len > 0) return entry.recipe.shaping[0];
    return switch (entry.recipe.base_kind) {
        .box => "box starter",
        .plane => "face starter",
        .cylinder => "cylinder starter",
        .sphere => "sphere starter",
    };
}

fn propTagLine(entry: project_editor_prop.CatalogEntry, buf: []u8) []const u8 {
    return propCompactTags(entry, buf);
}

fn propPersistedTagLine(tags: []const u8, buf: []u8) []const u8 {
    const trimmed = std.mem.trim(u8, tags, " \t\r\n");
    if (trimmed.len == 0) return "#prop";
    var written: usize = 0;
    var parts = std.mem.splitScalar(u8, trimmed, ',');
    while (parts.next()) |raw| {
        const part = std.mem.trim(u8, raw, " \t\r\n");
        if (part.len == 0) continue;
        if (written > 0 and written < buf.len) {
            buf[written] = ' ';
            written += 1;
        }
        if (written < buf.len) {
            buf[written] = '#';
            written += 1;
        }
        for (part) |ch| {
            if (written >= buf.len) break;
            buf[written] = if (ch == ' ') '-' else ch;
            written += 1;
        }
        if (written >= buf.len) break;
    }
    if (written == 0) return "#prop";
    return buf[0..written];
}

fn propCompactTags(entry: project_editor_prop.CatalogEntry, buf: []u8) []const u8 {
    const shape = if (entry.recipe.shaping.len > 0) entry.recipe.shaping[0] else "generated";
    return std.fmt.bufPrint(buf, "#{s}  #{s}", .{
        lowerKindTag(entry.recipe.base_kind),
        compactTag(shape),
    }) catch "#prop";
}

fn propTagInputLine(entry: project_editor_prop.CatalogEntry, buf: []u8) []const u8 {
    const shape = if (entry.recipe.shaping.len > 0) entry.recipe.shaping[0] else "generated";
    return std.fmt.bufPrint(buf, "{s}, {s}", .{
        lowerKindTag(entry.recipe.base_kind),
        compactTag(shape),
    }) catch "prop";
}

fn lowerKindTag(kind: geometry.PrimitiveKind) []const u8 {
    return switch (kind) {
        .box => "box",
        .plane => "plane",
        .cylinder => "cylinder",
        .sphere => "sphere",
    };
}

fn compactTag(value: []const u8) []const u8 {
    if (std.mem.indexOfScalar(u8, value, ' ')) |space| return value[0..space];
    return value;
}

pub fn propPreviewShape(kind: geometry.PrimitiveKind) core_ui.commands.AssetPreviewShape {
    return switch (kind) {
        .box => .box,
        .plane => .plane,
        .cylinder => .cylinder,
        .sphere => .sphere,
    };
}

fn primitiveButtonId(prim: PropPrimitive) []const u8 {
    return switch (prim) {
        .cube => "ed-left-prop-prim-cube",
        .cylinder => "ed-left-prop-prim-cylinder",
        .plane => "ed-left-prop-prim-plane",
        .ramp => "ed-left-prop-prim-ramp",
    };
}

fn selectPrimitive(state: *ProjectEditorState, prim: PropPrimitive) void {
    state.prop_primitive = prim;
    state.prop_tool = .primitive;
    project_editor_prop.addPrimitiveProp(state, prim) catch {
        project_editor_state.setStatus(state, "Add primitive failed");
    };
}

fn startSketchFromPrimitive(state: *ProjectEditorState, prim: PropPrimitive, sketch: project_editor_types.PropSketchMode) void {
    selectPrimitive(state, prim);
    state.prop_workspace_mode = .edit;
    state.prop_tool = .edit;
    state.prop_sketch_mode = sketch;
    state.prop_sketch_points.clearRetainingCapacity();
    state.selected_vertex = null;
    state.selected_edge = null;
    state.selected_face = null;
    project_editor_state.setStatus(state, switch (sketch) {
        .none => "Choose a sketch type",
        .face => "Draw a flat face, then solidify it",
        .curve => "Draw a curve, then revolve it",
        .path => "Draw an editable path source",
    });
}

fn selectAsset(state: *ProjectEditorState, name: []const u8) void {
    openAsset(state, name);
}

fn openAsset(state: *ProjectEditorState, name: []const u8) void {
    if (project_editor_prop.findCatalogEntry(name) != null) {
        project_editor_prop.openAssetForEditing(state, name) catch |err| {
            project_editor_prop.setOpenAssetErrorDetail(state, name, err, @errorReturnTrace()) catch {};
            project_editor_state.setStatus(state, "Open prop asset failed");
        };
        return;
    }
    project_editor_prop_asset.modifyAssetWorkingCopy(state, name) catch |err| {
        project_editor_prop.setOpenAssetErrorDetail(state, name, err, @errorReturnTrace()) catch {};
        project_editor_state.setStatus(state, "Open prop asset failed");
        return;
    };
    project_editor_prop.recordRecentProp(state, name);
}

fn cyclePlacementMode(state: *ProjectEditorState) void {
    state.prop_placement_mode = switch (state.prop_placement_mode) {
        .surface => .ground,
        .ground => .free,
        .free => .surface,
    };
    project_editor_state.setStatus(state, state.prop_placement_mode.label());
}

fn showsPlacementGhost(state: *const ProjectEditorState) bool {
    return state.prop_tool == .create;
}

fn drawPlacementGhost(state: *ProjectEditorState, vp_w: f32, vp_h: f32) void {
    const bounds = state.prop_placement_preview_bounds orelse {
        const center = state.prop_placement_preview orelse return;
        const half: f32 = 0.5;
        const min_pt = editor_math.Vec3{ .x = center.x - half, .y = center.y, .z = center.z - half };
        const max_pt = editor_math.Vec3{ .x = center.x + half, .y = center.y + half, .z = center.z + half };
        const color: shared.color.Color = .{ .r = 180, .g = 220, .b = 255, .a = 180 };
        project_editor_viewport.drawAabbWireframe(state, min_pt, max_pt, vp_w, vp_h, color);
        return;
    };
    const color: shared.color.Color = .{ .r = 180, .g = 220, .b = 255, .a = 180 };
    project_editor_viewport.drawAabbWireframe(state, bounds.min, bounds.max, vp_w, vp_h, color);
}

fn drawColliderPreviews(state: *ProjectEditorState, vp_w: f32, vp_h: f32) void {
    const color: shared.color.Color = .{ .r = 120, .g = 220, .b = 160, .a = 220 };
    if (state.selected_object) |idx| {
        const obj = &state.objects.items[idx];
        if (obj.physics == null) return;
        const bounds = editor_raycast.objectWorldBounds(obj);
        project_editor_viewport.drawAabbWireframe(state, bounds.min, bounds.max, vp_w, vp_h, color);
        return;
    }
    for (state.objects.items) |*obj| {
        if (obj.physics == null) continue;
        const bounds = editor_raycast.objectWorldBounds(obj);
        project_editor_viewport.drawAabbWireframe(state, bounds.min, bounds.max, vp_w, vp_h, color);
    }
}

fn physicsSelected(obj: *const @import("editor_scene_object.zig").SceneObject, kind: shared.scene_physics.BodyKind) bool {
    return if (obj.physics) |body| body.kind == kind else false;
}

fn addGameplay(state: *ProjectEditorState, idx: usize) !void {
    project_editor_edit.pushUndoSnapshot(state);
    const obj = &state.objects.items[idx];
    obj.gameplay = try shared.scene_gameplay.Component.duplicate(state.allocator, .{
        .tag = try shared.scene_gameplay.Component.defaultTag(state.allocator),
    });
    state.scene_dirty = true;
    project_editor_state.setStatus(state, "Gameplay tags added");
}

test "prop browser emits prop library rows without fake previews" {
    var ui = core_ui.UiContext.init(std.testing.allocator);
    defer ui.deinit();
    ui.beginFrame(.{});
    try ui.beginPanel(.{ .id = "test-props", .rect = .{ .x = 0, .y = 0, .w = 260, .h = 480 } });
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = try std.testing.allocator.dupe(u8, ""),
        .project_name = try std.testing.allocator.dupe(u8, ""),
        .objects = .empty,
    };
    defer state.deinit();

    try buildBrowser(&ui, &state);
    ui.endPanel();

    var prop_rows: usize = 0;
    var previews: usize = 0;
    for (ui.renderCommands()) |command| {
        if (command == .selectable) prop_rows += 1;
        if (command == .asset_preview) previews += 1;
    }
    try std.testing.expect(prop_rows > 0);
    try std.testing.expect(prop_rows < project_editor_prop.catalog.len);
    try std.testing.expectEqual(@typeInfo(PropPrimitive).@"enum".fields.len, previews);
}

test "shape inspector title follows selected source or operation scope" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = try std.testing.allocator.dupe(u8, ""),
        .project_name = try std.testing.allocator.dupe(u8, ""),
        .objects = .empty,
    };
    defer state.deinit();

    state.prop_workspace_mode = .edit;
    state.prop_tool = .edit;
    state.prop_sketch_mode = .face;
    state.selection_scope = .source;
    try std.testing.expectEqualStrings("Shape Source", shapeInspectorTitle(&state));

    state.selection_scope = .operation;
    try std.testing.expectEqualStrings("Shape Operation", shapeInspectorTitle(&state));

    state.selection_scope = .object;
    state.selected_shape_source = true;
    try std.testing.expectEqualStrings("Shape Source", shapeInspectorTitle(&state));

    state.selected_shape_source = false;
    state.selected_shape_operation = true;
    try std.testing.expectEqualStrings("Shape Operation", shapeInspectorTitle(&state));

    state.selected_shape_operation = false;
    try std.testing.expectEqualStrings("Shape Source / Operation", shapeInspectorTitle(&state));
}

test "shape inspector validation uses concise editor labels" {
    const pts = [_]editor_math.Vec3{
        .{ .x = 0, .y = 0, .z = 0 },
    };
    const source = shape_source.Source{ .kind = .closed_face, .points = &pts };
    const operation = shape_operation.Operation{ .kind = .solidify, .amount = 0.08 };
    var buf: [96]u8 = undefined;
    try std.testing.expectEqualStrings("Invalid: Need more points", shapeValidationText(source, operation, &buf));
}
