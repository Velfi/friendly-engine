const std = @import("std");
const shared = @import("runtime_shared");
const editor_command_file = @import("editor_command_file.zig");
const pm_state = @import("pm_state.zig");
const project_editor_modes = @import("project_editor_modes.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_types = @import("project_editor_types.zig");

const CommandFile = editor_command_file.CommandFile;
const ProjectEditorState = project_editor_state.ProjectEditorState;

pub fn describeCommands(
    allocator: std.mem.Allocator,
    command: CommandFile,
    editor_state: ?*const ProjectEditorState,
    project_manager: ?*const pm_state.ProjectManagerState,
) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, 8192);
    defer out.deinit(allocator);
    try appendFmt(allocator, &out, "{{\"ok\":true,\"id\":", .{});
    try appendJsonString(allocator, &out, command.id);
    try appendFmt(allocator, &out, ",\"command\":", .{});
    try appendJsonString(allocator, &out, command.name);
    try appendFmt(allocator, &out, ",\"screen\":", .{});
    if (editor_state) |_| {
        try appendJsonString(allocator, &out, shared.editor_command_catalog.project_editor_screen);
    } else if (project_manager) |_| {
        try appendJsonString(allocator, &out, "Project Manager");
    } else {
        return error.EditorStateRequired;
    }
    try appendFmt(allocator, &out, ",\"commands\":[", .{});
    var first = true;
    for (shared.editor_command_catalog.entries) |entry| {
        if (!commandAvailableInContext(entry, editor_state, project_manager)) continue;
        if (!first) try appendFmt(allocator, &out, ",", .{});
        first = false;
        try appendCommandCatalogEntry(allocator, &out, entry);
    }
    try appendFmt(allocator, &out, "],\"mcp_tools\":[", .{});
    first = true;
    for (shared.editor_control_commands.entries) |entry| {
        if (!mcpToolAvailableInContext(entry, editor_state, project_manager)) continue;
        if (!first) try appendFmt(allocator, &out, ",", .{});
        first = false;
        try appendMcpToolEntry(allocator, &out, entry);
    }
    try appendFmt(allocator, &out, "]}}\n", .{});
    return out.toOwnedSlice(allocator);
}

pub fn commandAvailableInContext(
    entry: shared.editor_command_catalog.Entry,
    editor_state: ?*const ProjectEditorState,
    project_manager: ?*const pm_state.ProjectManagerState,
) bool {
    if (project_manager) |manager| {
        if (!std.mem.eql(u8, entry.screen, "Project Manager")) return false;
        if (std.mem.eql(u8, entry.section, "modal")) return manager.mode != .none;
        if (std.mem.eql(u8, entry.id, "Open Project") or
            std.mem.eql(u8, entry.id, "Remove from List") or
            std.mem.eql(u8, entry.id, "pm-open"))
        {
            return manager.projects.items.len > 0;
        }
        return true;
    }

    const state = editor_state orelse return false;
    if (!std.mem.eql(u8, entry.screen, shared.editor_command_catalog.project_editor_screen)) return false;
    if (!project_editor_modes.commandAllowed(state, entry.id, entry.section)) return false;
    if (std.mem.eql(u8, entry.section, "mcp")) return false;
    if (std.mem.eql(u8, entry.section, "top bar") or
        std.mem.eql(u8, entry.section, "bottom strip") or
        std.mem.eql(u8, entry.section, "left rail"))
    {
        if (std.mem.eql(u8, entry.id, "ed-copy")) {
            return state.selected_object != null;
        }
        if (std.mem.eql(u8, entry.id, "ed-delete")) {
            return state.selected_object != null or
                (state.mode == .world_creation and !state.selected_world_curve_hit.isNone());
        }
        return true;
    }
    if (std.mem.eql(u8, entry.section, "layout")) {
        if (state.mode != .layout) return false;
        if (std.mem.eql(u8, entry.id, "ed-duplicate")) return state.selected_object != null;
        return true;
    }
    if (std.mem.eql(u8, entry.section, "world creation")) return state.mode == .world_creation;
    if (std.mem.eql(u8, entry.section, "architecture creation")) return state.mode == .architecture_creation;
    if (std.mem.eql(u8, entry.section, "prop creation")) return state.mode == .prop_creation;
    if (std.mem.eql(u8, entry.section, "life")) return state.mode == .life;
    if (std.mem.eql(u8, entry.section, "inspector")) return state.selected_object != null;
    if (std.mem.eql(u8, entry.section, "ui inspection")) return state.ui_tree_open;
    return false;
}

fn mcpToolAvailableInContext(
    entry: shared.editor_control_commands.Entry,
    editor_state: ?*const ProjectEditorState,
    project_manager: ?*const pm_state.ProjectManagerState,
) bool {
    if (!entry.exposedToMcp()) return false;
    if (project_manager != null) {
        return entry.owner == .project_manager or
            entry.owner == .commands or
            entry.owner == .capture;
    }
    const state = editor_state orelse return false;
    return switch (entry.owner) {
        .project_manager => false,
        .editor, .commands, .capture, .concept_paint, .view, .camera, .play => true,
        .selection => state.objects.items.len > 0,
        .world, .terrain => project_editor_modes.enabled(state, .world_creation) and state.mode == .world_creation,
        .architecture => project_editor_modes.enabled(state, .architecture_creation) and state.mode == .architecture_creation,
        .prop => project_editor_modes.enabled(state, .prop_creation) and state.mode == .prop_creation,
    };
}

fn appendCommandCatalogEntry(allocator: std.mem.Allocator, out: *std.ArrayList(u8), entry: shared.editor_command_catalog.Entry) !void {
    try appendFmt(allocator, out, "{{\"id\":", .{});
    try appendJsonString(allocator, out, entry.id);
    try appendFmt(allocator, out, ",\"label\":", .{});
    try appendJsonString(allocator, out, entry.label);
    try appendFmt(allocator, out, ",\"screen\":", .{});
    try appendJsonString(allocator, out, entry.screen);
    try appendFmt(allocator, out, ",\"section\":", .{});
    try appendJsonString(allocator, out, entry.section);
    try appendFmt(allocator, out, "}}", .{});
}

fn appendMcpToolEntry(allocator: std.mem.Allocator, out: *std.ArrayList(u8), entry: shared.editor_control_commands.Entry) !void {
    try appendFmt(allocator, out, "{{\"tool\":", .{});
    try appendJsonString(allocator, out, entry.mcp_tool_name);
    try appendFmt(allocator, out, ",\"command\":", .{});
    try appendJsonString(allocator, out, entry.command_name);
    try appendFmt(allocator, out, ",\"title\":", .{});
    try appendJsonString(allocator, out, entry.title);
    try appendFmt(allocator, out, ",\"owner\":", .{});
    try appendJsonString(allocator, out, entry.owner.label());
    try appendFmt(allocator, out, ",\"tier\":", .{});
    try appendJsonString(allocator, out, entry.tier.label());
    try appendFmt(allocator, out, "}}", .{});
}

const SceneMapEntry = struct {
    id: []const u8,
    title: []const u8,
    enter_command: ?[]const u8,
};

const scene_map_entries = [_]SceneMapEntry{
    .{ .id = "project_manager", .title = "Project Manager", .enter_command = "ed-close" },
    .{ .id = "project_editor_world", .title = "Project Editor: World", .enter_command = shared.editor_command_ids.mode_world_creation },
    .{ .id = "project_editor_layout", .title = "Project Editor: Layout", .enter_command = shared.editor_command_ids.mode_layout },
    .{ .id = "project_editor_architecture", .title = "Project Editor: Architecture", .enter_command = shared.editor_command_ids.mode_architecture_creation },
    .{ .id = "project_editor_prop", .title = "Project Editor: Prop", .enter_command = shared.editor_command_ids.mode_prop_creation },
    .{ .id = "project_editor_life", .title = "Project Editor: Life", .enter_command = shared.editor_command_ids.mode_life },
};

pub fn describeSceneMap(
    allocator: std.mem.Allocator,
    command: CommandFile,
    editor_state: ?*const ProjectEditorState,
    project_manager: ?*const pm_state.ProjectManagerState,
) ![]u8 {
    const current_scene = currentSceneId(editor_state, project_manager) orelse return error.EditorStateRequired;
    var out = try std.ArrayList(u8).initCapacity(allocator, 16384);
    defer out.deinit(allocator);

    try appendFmt(allocator, &out, "{{\"ok\":true,\"id\":", .{});
    try appendJsonString(allocator, &out, command.id);
    try appendFmt(allocator, &out, ",\"command\":", .{});
    try appendJsonString(allocator, &out, command.name);
    try appendFmt(allocator, &out, ",\"current_scene\":", .{});
    try appendJsonString(allocator, &out, current_scene);
    try appendFmt(allocator, &out, ",\"scenes\":[", .{});
    var first_scene = true;
    for (scene_map_entries) |scene| {
        if (!sceneReachable(scene.id, editor_state, project_manager)) continue;
        if (!first_scene) try appendFmt(allocator, &out, ",", .{});
        first_scene = false;
        try appendSceneMapEntry(allocator, &out, scene, current_scene, editor_state, project_manager);
    }
    try appendFmt(allocator, &out, "],\"navigation\":[", .{});
    try appendNavigationEdges(allocator, &out, current_scene, editor_state, project_manager);
    try appendFmt(allocator, &out, "],\"current_actions\":[", .{});
    try appendSceneActions(allocator, &out, current_scene, editor_state, project_manager, true);
    try appendFmt(allocator, &out, "],\"other_scene_actions\":[", .{});
    try appendSceneActions(allocator, &out, current_scene, editor_state, project_manager, false);
    try appendFmt(allocator, &out, "]}}\n", .{});
    return out.toOwnedSlice(allocator);
}

fn appendSceneMapEntry(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    scene: SceneMapEntry,
    current_scene: []const u8,
    editor_state: ?*const ProjectEditorState,
    project_manager: ?*const pm_state.ProjectManagerState,
) !void {
    try appendFmt(allocator, out, "{{\"id\":", .{});
    try appendJsonString(allocator, out, scene.id);
    try appendFmt(allocator, out, ",\"title\":", .{});
    try appendJsonString(allocator, out, scene.title);
    try appendFmt(allocator, out, ",\"current\":{},\"reachable\":{}", .{
        std.mem.eql(u8, scene.id, current_scene),
        sceneReachable(scene.id, editor_state, project_manager),
    });
    try appendFmt(allocator, out, ",\"enter_command\":", .{});
    if (scene.enter_command) |enter_command| {
        try appendJsonString(allocator, out, enter_command);
    } else {
        try appendFmt(allocator, out, "null", .{});
    }
    try appendFmt(allocator, out, "}}", .{});
}

fn appendNavigationEdges(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    current_scene: []const u8,
    editor_state: ?*const ProjectEditorState,
    project_manager: ?*const pm_state.ProjectManagerState,
) !void {
    var first = true;
    if (project_manager) |manager| {
        if (manager.projects.items.len > 0) {
            try appendNavigationEdge(allocator, out, &first, current_scene, "project_editor_world", "open_project", "Open selected project");
        }
        return;
    }
    if (editor_state != null) {
        try appendNavigationEdge(allocator, out, &first, current_scene, "project_manager", "ed-close", "Close project to Project Manager");
        for (scene_map_entries) |scene| {
            if (std.mem.startsWith(u8, scene.id, "project_editor_") and !std.mem.eql(u8, scene.id, current_scene)) {
                if (!sceneReachable(scene.id, editor_state, project_manager)) continue;
                try appendNavigationEdge(allocator, out, &first, current_scene, scene.id, scene.enter_command orelse continue, scene.title);
            }
        }
    }
}

fn appendNavigationEdge(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    first: *bool,
    from: []const u8,
    to: []const u8,
    command_id: []const u8,
    label: []const u8,
) !void {
    if (!first.*) try appendFmt(allocator, out, ",", .{});
    first.* = false;
    try appendFmt(allocator, out, "{{\"from\":", .{});
    try appendJsonString(allocator, out, from);
    try appendFmt(allocator, out, ",\"to\":", .{});
    try appendJsonString(allocator, out, to);
    try appendFmt(allocator, out, ",\"command\":", .{});
    try appendJsonString(allocator, out, command_id);
    try appendFmt(allocator, out, ",\"label\":", .{});
    try appendJsonString(allocator, out, label);
    try appendFmt(allocator, out, "}}", .{});
}

fn appendSceneActions(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    current_scene: []const u8,
    editor_state: ?*const ProjectEditorState,
    project_manager: ?*const pm_state.ProjectManagerState,
    include_current: bool,
) !void {
    var first = true;
    for (shared.editor_command_catalog.entries) |entry| {
        const scene_id = sceneIdForCommandEntry(entry);
        const is_current = std.mem.eql(u8, scene_id, current_scene);
        if (is_current != include_current) continue;
        if (include_current and !commandAvailableInContext(entry, editor_state, project_manager)) continue;
        if (!first) try appendFmt(allocator, out, ",", .{});
        first = false;
        try appendFmt(allocator, out, "{{\"scene\":", .{});
        try appendJsonString(allocator, out, scene_id);
        try appendFmt(allocator, out, ",\"id\":", .{});
        try appendJsonString(allocator, out, entry.id);
        try appendFmt(allocator, out, ",\"label\":", .{});
        try appendJsonString(allocator, out, entry.label);
        try appendFmt(allocator, out, ",\"section\":", .{});
        try appendJsonString(allocator, out, entry.section);
        try appendFmt(allocator, out, "}}", .{});
    }
}

fn currentSceneId(editor_state: ?*const ProjectEditorState, project_manager: ?*const pm_state.ProjectManagerState) ?[]const u8 {
    if (project_manager != null) return "project_manager";
    const state = editor_state orelse return null;
    return switch (state.mode) {
        .world_creation => "project_editor_world",
        .layout => "project_editor_layout",
        .architecture_creation => "project_editor_architecture",
        .prop_creation => "project_editor_prop",
        .life => "project_editor_life",
    };
}

fn sceneReachable(scene_id: []const u8, editor_state: ?*const ProjectEditorState, project_manager: ?*const pm_state.ProjectManagerState) bool {
    if (project_manager) |manager| {
        if (std.mem.eql(u8, scene_id, "project_manager")) return true;
        return manager.projects.items.len > 0 and std.mem.startsWith(u8, scene_id, "project_editor_");
    }
    if (editor_state) |state| {
        return modeForSceneId(scene_id) == null or project_editor_modes.enabled(state, modeForSceneId(scene_id).?);
    }
    return false;
}

fn modeForSceneId(scene_id: []const u8) ?project_editor_types.EditorMode {
    if (std.mem.eql(u8, scene_id, "project_editor_world")) return .world_creation;
    if (std.mem.eql(u8, scene_id, "project_editor_layout")) return .layout;
    if (std.mem.eql(u8, scene_id, "project_editor_architecture")) return .architecture_creation;
    if (std.mem.eql(u8, scene_id, "project_editor_prop")) return .prop_creation;
    if (std.mem.eql(u8, scene_id, "project_editor_life")) return .life;
    return null;
}

fn sceneIdForCommandEntry(entry: shared.editor_command_catalog.Entry) []const u8 {
    if (std.mem.eql(u8, entry.screen, "Project Manager")) return "project_manager";
    if (std.mem.eql(u8, entry.section, "architecture creation")) return "project_editor_architecture";
    if (std.mem.eql(u8, entry.section, "prop creation")) return "project_editor_prop";
    if (std.mem.eql(u8, entry.section, "life")) return "project_editor_life";
    if (std.mem.eql(u8, entry.section, "layout")) return "project_editor_layout";
    if (std.mem.eql(u8, entry.section, "ui inspection")) return "project_editor_world";
    return "project_editor_world";
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
