const std = @import("std");
const shared = @import("runtime_shared");
const command_palette_fuzzy = @import("command_palette_fuzzy.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_types = @import("project_editor_types.zig");
const project_editor_modes = @import("project_editor_modes.zig");

const catalog = shared.editor_command_catalog;
const command_ids = shared.editor_command_ids;
const ProjectEditorState = project_editor_state.ProjectEditorState;

pub const max_matches = 256;
pub const visible_matches = 50;

pub const Match = struct {
    entry: catalog.Entry,
    score: u32,
    unavailable: bool,
    unavailable_suffix: []const u8,
};

pub fn rankMatches(state: *const ProjectEditorState, out: []Match) usize {
    const filter = state.command_palette_filter[0..state.command_palette_filter_len];
    var count: usize = 0;
    for (catalog.entries) |entry| {
        if (!catalog.isProjectEditorEntry(entry)) continue;
        if (!project_editor_modes.commandAllowed(state, entry.id, entry.section)) continue;
        const fuzzy = command_palette_fuzzy.scoreFields(entry.label, entry.id, entry.section, catalog.sourceForEntry(entry), filter);
        if (fuzzy == 0 and filter.len > 0) continue;
        const availability = commandAvailability(state, entry);
        var score = fuzzy + contextBoost(state, entry);
        if (availability.unavailable) score = score / 2;
        if (std.mem.eql(u8, entry.section, "mcp") and filter.len == 0) score = score / 4;
        if (std.mem.eql(u8, entry.section, "mcp") and filter.len > 0 and fuzzy < 80) score = score / 2;
        if (count >= out.len) break;
        out[count] = .{
            .entry = entry,
            .score = score,
            .unavailable = availability.unavailable,
            .unavailable_suffix = availability.suffix,
        };
        count += 1;
    }
    sortMatches(out[0..count]);
    return count;
}

pub fn commandAvailability(state: *const ProjectEditorState, entry: catalog.Entry) struct { unavailable: bool, suffix: []const u8 } {
    if (needsSelection(entry.id) and state.selected_object == null) {
        return .{ .unavailable = true, .suffix = " · needs selection" };
    }
    return .{ .unavailable = false, .suffix = "" };
}

pub fn needsSelection(command_id: []const u8) bool {
    if (isPhysicsCommand(command_id)) return true;
    return std.mem.eql(u8, command_id, "ed-duplicate") or
        std.mem.eql(u8, command_id, "ed-copy") or
        std.mem.eql(u8, command_id, "ed-delete") or
        std.mem.eql(u8, command_id, "ed-add-gameplay") or
        std.mem.eql(u8, command_id, "focus-in-viewport") or
        std.mem.eql(u8, command_id, "zoom-to-focus") or
        std.mem.eql(u8, command_id, "ed-texture-fit") or
        std.mem.eql(u8, command_id, "ed-texture-align") or
        isMaterialCommand(command_id);
}

fn isPhysicsCommand(command_id: []const u8) bool {
    return std.mem.eql(u8, command_id, command_ids.physics_none) or
        std.mem.eql(u8, command_id, command_ids.physics_static) or
        std.mem.eql(u8, command_id, command_ids.physics_dynamic) or
        std.mem.eql(u8, command_id, command_ids.physics_kinematic);
}

fn isMaterialCommand(command_id: []const u8) bool {
    inline for (.{
        command_ids.material_asset_light,
        command_ids.material_asset_slate,
        command_ids.material_asset_red,
        command_ids.material_asset_green,
        command_ids.material_asset_blue,
        command_ids.material_asset_gold,
        command_ids.material_toolbar_red,
        command_ids.material_toolbar_green,
        command_ids.material_toolbar_blue,
        command_ids.material_toolbar_gold,
    }) |id| {
        if (std.mem.eql(u8, command_id, id)) return true;
    }
    return false;
}

fn contextBoost(state: *const ProjectEditorState, entry: catalog.Entry) u32 {
    var boost: u32 = 0;
    if (std.mem.eql(u8, entry.section, modeSection(state.mode))) boost +%= 500;
    boost +%= toolBoost(state, entry);
    boost +%= tabBoost(state, entry);
    if (state.mode == .layout and std.mem.eql(u8, entry.section, "layout")) boost +%= 200;
    if (state.mode == .architecture_creation and std.mem.eql(u8, entry.section, "architecture creation")) boost +%= 200;
    if (state.mode == .prop_creation and std.mem.eql(u8, entry.section, "prop creation")) boost +%= 200;
    if (state.mode == .life and std.mem.eql(u8, entry.section, "life")) boost +%= 200;
    return boost;
}

fn modeSection(mode: project_editor_types.EditorMode) []const u8 {
    return switch (mode) {
        .world_creation => "left rail",
        .layout => "layout",
        .architecture_creation => "architecture creation",
        .prop_creation => "prop creation",
        .life => "life",
    };
}

fn toolBoost(state: *const ProjectEditorState, entry: catalog.Entry) u32 {
    return switch (state.mode) {
        .layout => if (std.mem.eql(u8, entry.id, objectToolId(state.object_tool))) 300 else 0,
        .architecture_creation => blk: {
            if (std.mem.eql(u8, entry.id, architectureToolId(state.architecture_tool))) break :blk 300;
            if (std.mem.eql(u8, entry.id, blockoutOpId(state.blockout_op))) break :blk 150;
            break :blk 0;
        },
        .prop_creation => if (std.mem.eql(u8, entry.id, propToolId(state.prop_tool))) 300 else 0,
        .life => if (std.mem.eql(u8, entry.id, lifeToolId(state.life_tool))) 300 else 0,
        .world_creation => 0,
    };
}

fn architectureToolId(tool: project_editor_types.ArchitectureTool) []const u8 {
    return switch (tool) {
        .network => command_ids.architectureTool("network"),
        .floorplan => command_ids.architecture_floorplan,
        .shell => command_ids.architectureTool("shell"),
        .foundation => command_ids.architectureTool("foundation"),
        .cutout => command_ids.architectureTool("cutout"),
        .wall => command_ids.architecture_wall,
        .opening => command_ids.architectureTool("opening"),
        .roof => command_ids.architectureTool("roof"),
        .door => command_ids.architecture_door,
        .window => command_ids.architecture_window,
        .curve => command_ids.architecture_curve,
        .brush => command_ids.architecture_brush,
        .add => command_ids.architecture_add,
        .subtract => command_ids.architecture_subtract,
        .ramp => command_ids.architecture_ramp,
        .vertex => command_ids.architecture_vertex,
        .edge => command_ids.architecture_edge,
        .face => command_ids.architecture_face,
        .extrude => command_ids.architecture_extrude,
        .inset => command_ids.architecture_inset,
        .material => command_ids.architecture_material,
    };
}

fn blockoutOpId(op: project_editor_types.BlockoutOp) []const u8 {
    return switch (op) {
        .add => command_ids.blockout_add,
        .subtract => command_ids.blockout_subtract,
    };
}

fn propToolId(tool: project_editor_types.PropTool) []const u8 {
    return switch (tool) {
        .select => command_ids.prop_select,
        .create => command_ids.prop_create,
        .asset => command_ids.prop_asset,
        .primitive => command_ids.prop_primitive,
        .edit => command_ids.prop_edit,
        .material => command_ids.prop_material,
        .collider => command_ids.prop_collider,
        .variants => command_ids.prop_variants,
    };
}

fn lifeToolId(tool: project_editor_types.LifeTool) []const u8 {
    return switch (tool) {
        .select => command_ids.life_select,
        .pose => command_ids.life_pose,
        .keyframe => command_ids.life_keyframe,
        .record => command_ids.life_record,
        .playback => command_ids.life_playback,
        .clips => command_ids.life_clips,
        .bones => command_ids.life_bones,
        .curves => command_ids.life_curves,
    };
}

fn objectToolId(tool: project_editor_types.ObjectTool) []const u8 {
    return switch (tool) {
        .select => command_ids.object_select,
        .move => command_ids.object_move,
        .rotate => command_ids.object_rotate,
        .scale => command_ids.object_scale,
    };
}

fn tabBoost(state: *const ProjectEditorState, entry: catalog.Entry) u32 {
    if (!std.mem.eql(u8, entry.section, "left rail")) return 0;
    const active = switch (state.left_tab) {
        .scene => command_ids.left_scene,
        .add => command_ids.left_add,
        .world => command_ids.left_world,
        .assets => command_ids.left_assets,
    };
    return if (std.mem.eql(u8, entry.id, active)) 100 else 0;
}

pub fn ghostSuffix(filter: []const u8, matches: []const Match) []const u8 {
    if (filter.len == 0 or matches.len == 0) return "";
    const prefix = commonPrefix(matches);
    if (prefix.len <= filter.len) return "";
    if (!startsWithIgnoreCase(prefix, filter)) return "";
    return prefix[filter.len..];
}

pub fn completionSuffix(filter: []const u8, matches: []const Match) []const u8 {
    return ghostSuffix(filter, matches);
}

fn commonPrefix(matches: []const Match) []const u8 {
    if (matches.len == 0) return "";
    var prefix = matches[0].entry.label;
    for (matches[1..]) |match| {
        prefix = sharedPrefix(prefix, match.entry.label);
        if (prefix.len == 0) return "";
    }
    return prefix;
}

fn sharedPrefix(a: []const u8, b: []const u8) []const u8 {
    const len = @min(a.len, b.len);
    var i: usize = 0;
    while (i < len and std.ascii.toLower(a[i]) == std.ascii.toLower(b[i])) : (i += 1) {}
    return a[0..i];
}

fn startsWithIgnoreCase(text: []const u8, prefix: []const u8) bool {
    if (prefix.len > text.len) return false;
    for (prefix, 0..) |ch, i| {
        if (std.ascii.toLower(text[i]) != std.ascii.toLower(ch)) return false;
    }
    return true;
}

fn sortMatches(matches: []Match) void {
    std.mem.sort(Match, matches, {}, matchLessThan);
}

fn matchLessThan(_: void, a: Match, b: Match) bool {
    if (a.score != b.score) return a.score > b.score;
    return std.mem.order(u8, a.entry.label, b.entry.label) == .lt;
}

test "architecture mode boosts brush commands" {
    const testing = std.testing;
    var state = ProjectEditorState{
        .allocator = testing.allocator,
        .io = testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .mode = .architecture_creation,
        .architecture_tool = .brush,
    };

    var matches: [catalog.entries.len]Match = undefined;
    const count = rankMatches(&state, &matches);
    try testing.expect(count > 0);
    try testing.expect(std.mem.eql(u8, matches[0].entry.id, command_ids.architecture_brush));
}

test "physics commands need selection" {
    const testing = std.testing;
    try testing.expect(needsSelection(command_ids.physics_static));
    const availability = commandAvailability(&ProjectEditorState{
        .allocator = testing.allocator,
        .io = testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .selected_object = null,
    }, .{
        .id = command_ids.physics_static,
        .label = "Static",
        .screen = catalog.project_editor_screen,
        .section = "inspector",
    });
    try testing.expect(availability.unavailable);
    try testing.expectEqualStrings(" · needs selection", availability.suffix);
}

test "mcp commands rank lower with empty filter" {
    const testing = std.testing;
    var state = ProjectEditorState{
        .allocator = testing.allocator,
        .io = testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
    };

    var matches: [catalog.entries.len]Match = undefined;
    const count = rankMatches(&state, &matches);
    var screenshot_rank: ?usize = null;
    var save_rank: ?usize = null;
    for (matches[0..count], 0..) |match, i| {
        if (std.mem.eql(u8, match.entry.id, "screenshot-editor")) screenshot_rank = i;
        if (std.mem.eql(u8, match.entry.id, "ed-save")) save_rank = i;
    }
    try testing.expect(save_rank != null);
    try testing.expect(screenshot_rank != null);
    try testing.expect(save_rank.? < screenshot_rank.?);
}

test "ghost suffix completes save prefix" {
    const testing = std.testing;
    const matches = [_]Match{
        .{ .entry = .{ .id = "ed-save", .label = "Save", .screen = catalog.project_editor_screen, .section = "top bar" }, .score = 100, .unavailable = false, .unavailable_suffix = "" },
    };
    try testing.expectEqualStrings("ave", ghostSuffix("s", &matches));
}
