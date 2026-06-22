const std = @import("std");
const pm_presets = @import("pm_presets.zig");
const pm_state = @import("pm_state.zig");
const pm_state_projects = @import("pm_state_projects.zig");
const editor_command_file = @import("editor_command_file.zig");

const CommandFile = editor_command_file.CommandFile;

pub fn handles(command_name: []const u8) bool {
    return std.mem.eql(u8, command_name, "open-project") or
        std.mem.eql(u8, command_name, "project.create") or
        std.mem.eql(u8, command_name, "project.import") or
        std.mem.eql(u8, command_name, "project.remove") or
        std.mem.eql(u8, command_name, "project.init-existing") or
        std.mem.eql(u8, command_name, "project.reset-selected");
}

pub fn execute(
    allocator: std.mem.Allocator,
    command: CommandFile,
    editor_state_present: bool,
    project_manager: ?*pm_state.ProjectManagerState,
) ![]u8 {
    if (editor_state_present) return error.ProjectManagerStateRequired;
    const manager = project_manager orelse return error.ProjectManagerStateRequired;

    if (std.mem.eql(u8, command.name, "open-project")) {
        try pm_state_projects.openProject(manager, command.object);
        const entry = manager.projects.items[manager.selected_index];
        return projectManagerResponse(allocator, command, entry.name, entry.path, manager.status());
    }
    if (std.mem.eql(u8, command.name, "project.create")) {
        const preset = if (command.preset) |name|
            pm_presets.findPreset(manager, name) orelse return error.UnknownPreset
        else
            pm_presets.findPreset(manager, manager.selectedCreatePresetName()) orelse pm_presets.builtinPresets()[0];
        try manager.selectCreatePreset(presetIndex(manager, preset.name) orelse 0);
        try pm_state_projects.createProjectAtPathWithModules(manager, command.path orelse return error.MissingPath, preset.modules);
        const entry = manager.projects.items[manager.selected_index];
        return projectManagerResponse(allocator, command, entry.name, entry.path, manager.status());
    }
    if (std.mem.eql(u8, command.name, "project.import")) {
        try pm_state_projects.importProjectPathInput(manager, command.path orelse return error.MissingPath);
        const entry = manager.projects.items[manager.selected_index];
        return projectManagerResponse(allocator, command, entry.name, entry.path, manager.status());
    }
    if (std.mem.eql(u8, command.name, "project.remove")) {
        if (manager.projects.items.len == 0) return error.ProjectNotFound;
        const removed_index = projectManagerTargetIndex(manager, command.object) orelse return error.ProjectNotFound;
        const removed_name = try allocator.dupe(u8, manager.projects.items[removed_index].name);
        defer allocator.free(removed_name);
        const removed_path = try allocator.dupe(u8, manager.projects.items[removed_index].path);
        defer allocator.free(removed_path);
        try pm_state_projects.removeProject(manager, command.object);
        return projectManagerResponse(allocator, command, removed_name, removed_path, manager.status());
    }
    if (std.mem.eql(u8, command.name, "project.init-existing")) {
        try pm_state_projects.initExistingProjectAtPath(manager, command.path orelse return error.MissingPath);
        const entry = manager.projects.items[manager.selected_index];
        return projectManagerResponse(allocator, command, entry.name, entry.path, manager.status());
    }
    if (std.mem.eql(u8, command.name, "project.reset-selected")) {
        try pm_state_projects.resetSelectedProjectToStarter(manager);
        const entry = manager.projects.items[manager.selected_index];
        return projectManagerResponse(allocator, command, entry.name, entry.path, manager.status());
    }

    return error.UnknownEditorCommand;
}

fn projectManagerTargetIndex(manager: *const pm_state.ProjectManagerState, target: ?[]const u8) ?usize {
    if (target) |raw| {
        const trimmed = std.mem.trim(u8, raw, " \t\r\n");
        if (trimmed.len > 0) {
            for (manager.projects.items, 0..) |entry, index| {
                if (std.mem.eql(u8, entry.path, trimmed) or std.mem.eql(u8, entry.name, trimmed)) return index;
            }
            return null;
        }
    }
    if (manager.projects.items.len == 0) return null;
    return manager.selected_index;
}

fn presetIndex(manager: *const pm_state.ProjectManagerState, name: []const u8) ?usize {
    var i: usize = 0;
    while (i < manager.presetCount()) : (i += 1) {
        if (std.mem.eql(u8, manager.presetAt(i).name, name)) return i;
    }
    return null;
}

fn projectManagerResponse(
    allocator: std.mem.Allocator,
    command: CommandFile,
    project_name: []const u8,
    project_path: []const u8,
    status: []const u8,
) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, 256);
    defer out.deinit(allocator);
    try out.appendSlice(allocator, "{\"ok\":true,\"id\":");
    try appendJsonString(allocator, &out, command.id);
    try out.appendSlice(allocator, ",\"command\":");
    try appendJsonString(allocator, &out, command.name);
    try out.appendSlice(allocator, ",\"project\":");
    try appendJsonString(allocator, &out, project_name);
    try out.appendSlice(allocator, ",\"path\":");
    try appendJsonString(allocator, &out, project_path);
    try out.appendSlice(allocator, ",\"status\":");
    try appendJsonString(allocator, &out, status);
    try out.appendSlice(allocator, "}\n");
    return out.toOwnedSlice(allocator);
}

fn appendJsonString(allocator: std.mem.Allocator, out: *std.ArrayList(u8), value: []const u8) !void {
    const encoded = try std.json.Stringify.valueAlloc(allocator, value, .{});
    defer allocator.free(encoded);
    try out.appendSlice(allocator, encoded);
}
