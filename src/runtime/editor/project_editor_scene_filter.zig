const std = @import("std");
const friendly_engine = @import("friendly_engine");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_types = @import("project_editor_types.zig");
const project_editor_prop_index = @import("project_editor_prop_index.zig");
const scene_hierarchy = @import("editor_scene_hierarchy.zig");
const ui_widgets = @import("project_editor_ui_widgets.zig");

const core_ui = friendly_engine.modules.core_ui;
const ProjectEditorState = project_editor_state.ProjectEditorState;
const SceneObject = project_editor_state.SceneObject;
const TreeEntry = scene_hierarchy.TreeEntry;

pub fn collectVisibleRows(allocator: std.mem.Allocator, ui: *core_ui.UiContext, state: *ProjectEditorState) ![]TreeEntry {
    const entries = try scene_hierarchy.collectTreeEntriesAlloc(allocator, state.objects.items);
    errdefer allocator.free(entries);
    var include = try allocator.alloc(bool, entries.len);
    defer allocator.free(include);
    @memset(include, false);

    for (entries, 0..) |entry, entry_idx| {
        if (!objectMatches(ui, state, entry.idx)) continue;
        include[entry_idx] = true;
        markAncestors(entries, state.objects.items, entry_idx, include);
    }

    var out = std.ArrayList(TreeEntry).empty;
    errdefer out.deinit(allocator);
    for (entries, include) |entry, keep| {
        if (keep) try out.append(allocator, entry);
    }
    allocator.free(entries);
    return try out.toOwnedSlice(allocator);
}

pub fn objectMatches(ui: *core_ui.UiContext, state: *ProjectEditorState, idx: usize) bool {
    const obj = &state.objects.items[idx];
    if (!project_editor_state.objectVisible(state, obj)) return false;
    if (!matchesObjectFacet(obj, state.scene_object_filter)) return false;
    if (!matchesVisibilityFacet(obj, state.scene_visibility_filter)) return false;
    if (state.scene_layer_filter_len > 0 and !std.ascii.eqlIgnoreCase(obj.layer, sceneLayerFilter(state))) return false;
    if (state.scene_tag_filter_len > 0 and !objectHasTag(state, obj, sceneTagFilter(state))) return false;
    return objectMatchesSearch(ui, state, obj);
}

pub fn clearFilters(state: *ProjectEditorState) void {
    state.scene_object_filter = .all;
    state.scene_visibility_filter = .all;
    state.scene_layer_filter_len = 0;
    state.scene_tag_filter_len = 0;
}

pub fn buildControls(ui: *core_ui.UiContext, state: *ProjectEditorState, prefix: []const u8) !void {
    try ui.label("Scene Filters");
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.button(ui, controlId(prefix, "object-all"), "All", 42, state.scene_object_filter == .all)).clicked) state.scene_object_filter = .all;
    if ((try ui_widgets.button(ui, controlId(prefix, "object-props"), "Props", 58, state.scene_object_filter == .props)).clicked) state.scene_object_filter = .props;
    if ((try ui_widgets.button(ui, controlId(prefix, "object-non-props"), "Other", 58, state.scene_object_filter == .non_props)).clicked) state.scene_object_filter = .non_props;
    try core_ui.layout.endSameLine(ui);

    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.button(ui, controlId(prefix, "vis-all"), "All", 42, state.scene_visibility_filter == .all)).clicked) state.scene_visibility_filter = .all;
    if ((try ui_widgets.button(ui, controlId(prefix, "vis-visible"), "Visible", 68, state.scene_visibility_filter == .visible)).clicked) state.scene_visibility_filter = .visible;
    if ((try ui_widgets.button(ui, controlId(prefix, "vis-hidden"), "Hidden", 66, state.scene_visibility_filter == .hidden)).clicked) state.scene_visibility_filter = .hidden;
    if ((try ui_widgets.button(ui, controlId(prefix, "vis-locked"), "Locked", 66, state.scene_visibility_filter == .locked)).clicked) state.scene_visibility_filter = .locked;
    try core_ui.layout.endSameLine(ui);

    var layers: [5][32]u8 = undefined;
    var layer_lens: [5]usize = [_]usize{0} ** 5;
    const layer_count = collectLayerChips(state, &layers, &layer_lens);
    if (layer_count > 0) {
        try core_ui.layout.sameLine(ui);
        if ((try ui_widgets.button(ui, controlId(prefix, "layer-all"), "Layers", 66, state.scene_layer_filter_len == 0)).clicked) state.scene_layer_filter_len = 0;
        for (0..layer_count) |idx| {
            const layer = layers[idx][0..layer_lens[idx]];
            if ((try ui_widgets.button(ui, controlId(prefix, layer), layer, @min(@as(f32, 88), 34 + @as(f32, @floatFromInt(layer.len)) * 7), state.scene_layer_filter_len > 0 and std.ascii.eqlIgnoreCase(sceneLayerFilter(state), layer))).clicked) setLayerFilter(state, layer);
        }
        try core_ui.layout.endSameLine(ui);
    }

    var tags: [5][32]u8 = undefined;
    var tag_lens: [5]usize = [_]usize{0} ** 5;
    const tag_count = collectTagChips(state, &tags, &tag_lens);
    if (tag_count > 0) {
        try core_ui.layout.sameLine(ui);
        if ((try ui_widgets.button(ui, controlId(prefix, "tag-all"), "Tags", 54, state.scene_tag_filter_len == 0)).clicked) state.scene_tag_filter_len = 0;
        for (0..tag_count) |idx| {
            const tag = tags[idx][0..tag_lens[idx]];
            if ((try ui_widgets.button(ui, controlId(prefix, tag), tag, @min(@as(f32, 88), 34 + @as(f32, @floatFromInt(tag.len)) * 7), state.scene_tag_filter_len > 0 and std.ascii.eqlIgnoreCase(sceneTagFilter(state), tag))).clicked) setTagFilter(state, tag);
        }
        try core_ui.layout.endSameLine(ui);
    }

    if (state.scene_object_filter != .all or state.scene_visibility_filter != .all or state.scene_layer_filter_len > 0 or state.scene_tag_filter_len > 0) {
        if ((try ui_widgets.button(ui, controlId(prefix, "clear"), "Clear", 58, false)).clicked) clearFilters(state);
    }
}

pub fn sceneLayerFilter(state: *const ProjectEditorState) []const u8 {
    return state.scene_layer_filter_buf[0..state.scene_layer_filter_len];
}

pub fn sceneTagFilter(state: *const ProjectEditorState) []const u8 {
    return state.scene_tag_filter_buf[0..state.scene_tag_filter_len];
}

pub fn setLayerFilter(state: *ProjectEditorState, layer: []const u8) void {
    if (state.scene_layer_filter_len == layer.len and std.ascii.eqlIgnoreCase(sceneLayerFilter(state), layer)) {
        state.scene_layer_filter_len = 0;
        return;
    }
    state.scene_layer_filter_len = @min(layer.len, state.scene_layer_filter_buf.len);
    @memcpy(state.scene_layer_filter_buf[0..state.scene_layer_filter_len], layer[0..state.scene_layer_filter_len]);
}

pub fn setTagFilter(state: *ProjectEditorState, tag: []const u8) void {
    if (state.scene_tag_filter_len == tag.len and std.ascii.eqlIgnoreCase(sceneTagFilter(state), tag)) {
        state.scene_tag_filter_len = 0;
        return;
    }
    state.scene_tag_filter_len = @min(tag.len, state.scene_tag_filter_buf.len);
    @memcpy(state.scene_tag_filter_buf[0..state.scene_tag_filter_len], tag[0..state.scene_tag_filter_len]);
}

fn markAncestors(entries: []const TreeEntry, objects: []const SceneObject, entry_idx: usize, include: []bool) void {
    var parent_id = objects[entries[entry_idx].idx].parent_id;
    while (parent_id) |pid| {
        var found = false;
        for (entries, 0..) |candidate, idx| {
            if (objects[candidate.idx].id != pid) continue;
            include[idx] = true;
            parent_id = objects[candidate.idx].parent_id;
            found = true;
            break;
        }
        if (!found) break;
    }
}

fn matchesObjectFacet(obj: *const SceneObject, filter: project_editor_types.SceneObjectFilter) bool {
    return switch (filter) {
        .all => true,
        .props => obj.prop_asset_id != null,
        .non_props => obj.prop_asset_id == null,
    };
}

fn matchesVisibilityFacet(obj: *const SceneObject, filter: project_editor_types.SceneVisibilityFilter) bool {
    return switch (filter) {
        .all => true,
        .visible => obj.renderer_visible,
        .hidden => !obj.renderer_visible,
        .locked => obj.locked or obj.isImmutable(),
    };
}

fn objectMatchesSearch(ui: *core_ui.UiContext, state: *ProjectEditorState, obj: *const SceneObject) bool {
    if (ui_widgets.matchesFilter(ui, "ed-scene-search", obj.name)) return true;
    if (ui_widgets.matchesFilter(ui, "ed-scene-search", ui_widgets.objectTypeLabel(obj))) return true;
    if (obj.layer.len > 0 and ui_widgets.matchesFilter(ui, "ed-scene-search", obj.layer)) return true;
    if (obj.prop_asset_id) |asset_id| {
        if (ui_widgets.matchesFilter(ui, "ed-scene-search", asset_id)) return true;
        if (findPropRow(state, asset_id)) |row| {
            if (ui_widgets.matchesFilter(ui, "ed-scene-search", row.label)) return true;
            if (ui_widgets.matchesFilter(ui, "ed-scene-search", row.tags)) return true;
        }
    }
    if (obj.gameplay) |gameplay| {
        if (ui_widgets.matchesFilter(ui, "ed-scene-search", gameplay.tag)) return true;
    }
    if (obj.marker) |marker| {
        if (ui_widgets.matchesFilter(ui, "ed-scene-search", marker.kind.label())) return true;
        if (ui_widgets.matchesFilter(ui, "ed-scene-search", marker.kind.name())) return true;
        if (ui_widgets.matchesFilter(ui, "ed-scene-search", marker.shape.name())) return true;
        if (marker.marker_id.len > 0 and ui_widgets.matchesFilter(ui, "ed-scene-search", marker.marker_id)) return true;
        if (marker.group.len > 0 and ui_widgets.matchesFilter(ui, "ed-scene-search", marker.group)) return true;
        if (marker.binding.len > 0 and ui_widgets.matchesFilter(ui, "ed-scene-search", marker.binding)) return true;
    }
    if (obj.renderer_visible and ui_widgets.matchesFilter(ui, "ed-scene-search", "visible")) return true;
    if (!obj.renderer_visible and ui_widgets.matchesFilter(ui, "ed-scene-search", "hidden")) return true;
    if ((obj.locked or obj.isImmutable()) and ui_widgets.matchesFilter(ui, "ed-scene-search", "locked")) return true;
    return false;
}

fn objectHasTag(state: *ProjectEditorState, obj: *const SceneObject, tag: []const u8) bool {
    if (obj.gameplay) |gameplay| {
        if (std.ascii.eqlIgnoreCase(gameplay.tag, tag)) return true;
    }
    const asset_id = obj.prop_asset_id orelse return false;
    const row = findPropRow(state, asset_id) orelse return false;
    var it = std.mem.tokenizeAny(u8, row.tags, ", #\t\r\n");
    while (it.next()) |raw| {
        if (std.ascii.eqlIgnoreCase(std.mem.trim(u8, raw, " \t\r\n#"), tag)) return true;
    }
    return false;
}

fn findPropRow(state: *ProjectEditorState, asset_id: []const u8) ?project_editor_types.PropAssetIndexRow {
    const rows = project_editor_prop_index.ensure(state) catch return null;
    for (rows) |row| {
        if (std.mem.eql(u8, row.id, asset_id)) return row;
    }
    return null;
}

fn controlId(prefix: []const u8, suffix: []const u8) []const u8 {
    _ = prefix;
    return suffix;
}

fn collectLayerChips(state: *ProjectEditorState, layers: *[5][32]u8, lens: *[5]usize) usize {
    var count: usize = 0;
    for (state.objects.items) |obj| {
        if (obj.layer.len == 0 or obj.layer.len > layers[0].len) continue;
        if (containsCollected(layers, lens, count, obj.layer)) continue;
        @memcpy(layers[count][0..obj.layer.len], obj.layer);
        lens[count] = obj.layer.len;
        count += 1;
        if (count >= layers.len) return count;
    }
    return count;
}

fn collectTagChips(state: *ProjectEditorState, tags: *[5][32]u8, lens: *[5]usize) usize {
    var count: usize = 0;
    for (state.objects.items) |obj| {
        if (obj.gameplay) |gameplay| {
            count = appendChip(tags, lens, count, gameplay.tag);
            if (count >= tags.len) return count;
        }
        if (obj.prop_asset_id) |asset_id| {
            if (findPropRow(state, asset_id)) |row| {
                var it = std.mem.tokenizeAny(u8, row.tags, ", #\t\r\n");
                while (it.next()) |raw| {
                    count = appendChip(tags, lens, count, std.mem.trim(u8, raw, " \t\r\n#"));
                    if (count >= tags.len) return count;
                }
            }
        }
    }
    return count;
}

fn appendChip(chips: *[5][32]u8, lens: *[5]usize, count: usize, value: []const u8) usize {
    if (count >= chips.len or value.len == 0 or value.len > chips[0].len) return count;
    if (containsCollected(chips, lens, count, value)) return count;
    @memcpy(chips[count][0..value.len], value);
    lens[count] = value.len;
    return count + 1;
}

fn containsCollected(chips: anytype, lens: anytype, count: usize, value: []const u8) bool {
    for (0..count) |idx| {
        if (std.ascii.eqlIgnoreCase(chips[idx][0..lens[idx]], value)) return true;
    }
    return false;
}

test "scene prop search matches asset id and layer" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = try std.testing.allocator.dupe(u8, ""),
        .project_name = try std.testing.allocator.dupe(u8, ""),
        .objects = .empty,
    };
    defer state.deinit();
    try state.objects.append(std.testing.allocator, .{
        .id = 1,
        .name = try std.testing.allocator.dupe(u8, "Chair instance"),
        .mesh = .{ .vertices = &.{}, .indices = &.{} },
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = &.{},
        .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .prop_asset_id = try std.testing.allocator.dupe(u8, "chair_old"),
        .layer = try std.testing.allocator.dupe(u8, "interior"),
    });
    var ui = core_ui.UiContext.init(std.testing.allocator);
    defer ui.deinit();
    ui.beginFrame(.{});
    try ui.beginPanel(.{ .id = "scene-filter-test", .rect = .{ .x = 0, .y = 0, .w = 320, .h = 240 } });
    _ = try core_ui.widgets_input.searchInput(&ui, "ed-scene-search");
    try ui.resetTextState(try ui.stableId("ed-scene-search", "ed-scene-search"), "chair_old");
    try std.testing.expect(objectMatches(&ui, &state, 0));
    try ui.resetTextState(try ui.stableId("ed-scene-search", "ed-scene-search"), "interior");
    try std.testing.expect(objectMatches(&ui, &state, 0));
    ui.endPanel();
}
