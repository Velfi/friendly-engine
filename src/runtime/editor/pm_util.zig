const std = @import("std");
const builtin = @import("builtin");
const friendly_engine = @import("friendly_engine");
const editor_draw = @import("editor_draw.zig");
const pm_types = @import("pm_types.zig");

pub fn sdlError() []const u8 {
    return editor_draw.sdlError();
}

pub fn folderDialogCallback(userdata: ?*anyopaque, filelist: ?[*]const ?[*:0]const u8, filter: c_int) callconv(.c) void {
    _ = filter;
    const state = @as(*@import("pm_state.zig").ProjectManagerState, @ptrCast(@alignCast(userdata.?)));
    if (filelist == null or filelist.?[0] == null) return;
    const kind = state.pending_dialog_kind_request;
    const project_index = switch (kind) {
        .relocate_folder => state.pending_dialog_project_index,
        else => null,
    };
    state.queueDialogPath(std.mem.span(filelist.?[0].?), kind, project_index);
}

pub fn makeProjectEntry(
    allocator: std.mem.Allocator,
    name: []const u8,
    path: []const u8,
    renderer: []const u8,
    tags: []const u8,
    last_opened: []const u8,
    status: []const u8,
) !pm_types.ProjectManagerEntry {
    return .{
        .name = try allocator.dupe(u8, name),
        .path = try allocator.dupe(u8, path),
        .renderer = try allocator.dupe(u8, renderer),
        .tags = try allocator.dupe(u8, tags),
        .last_opened = try allocator.dupe(u8, last_opened),
        .status = try allocator.dupe(u8, status),
    };
}

pub fn deinitProjectEntry(allocator: std.mem.Allocator, entry: *pm_types.ProjectManagerEntry) void {
    allocator.free(entry.name);
    allocator.free(entry.path);
    allocator.free(entry.renderer);
    allocator.free(entry.tags);
    allocator.free(entry.last_opened);
    allocator.free(entry.status);
}

pub fn resolveProjectManagerStatePath(allocator: std.mem.Allocator, environ_map: *const std.process.Environ.Map) ![]u8 {
    const app_data_dir = try resolveAppDataDirectory(allocator, environ_map, "friendly-engine");
    defer allocator.free(app_data_dir);
    return std.fs.path.join(allocator, &.{ app_data_dir, "project_manager.json" });
}

pub fn resolveAppDataDirectory(
    allocator: std.mem.Allocator,
    environ_map: *const std.process.Environ.Map,
    app_folder_name: []const u8,
) ![]u8 {
    switch (builtin.os.tag) {
        .macos => {
            const home = environ_map.get("HOME") orelse return error.MissingHomeDirectory;
            return std.fs.path.join(allocator, &.{ home, "Library", "Application Support", app_folder_name });
        },
        .windows => {
            const local_app_data = environ_map.get("LOCALAPPDATA") orelse
                environ_map.get("APPDATA") orelse
                return error.MissingLocalAppDataDirectory;
            return std.fs.path.join(allocator, &.{ local_app_data, app_folder_name });
        },
        else => {
            if (environ_map.get("XDG_DATA_HOME")) |xdg_data_home| {
                return std.fs.path.join(allocator, &.{ xdg_data_home, app_folder_name });
            }
            const home = environ_map.get("HOME") orelse return error.MissingHomeDirectory;
            return std.fs.path.join(allocator, &.{ home, ".local", "share", app_folder_name });
        },
    }
}

pub fn readModulesSummaryForPath(allocator: std.mem.Allocator, io: std.Io, absolute_path: []const u8) ![]u8 {
    var project_dir = try std.Io.Dir.openDirAbsolute(io, absolute_path, .{});
    defer project_dir.close(io);

    const bytes = project_dir.readFileAlloc(io, "engine.kdl", allocator, .limited(64 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return allocator.dupe(u8, "none"),
        else => return err,
    };
    defer allocator.free(bytes);

    var parsed = friendly_engine.modules.parseProjectConfigBytes(allocator, bytes) catch {
        return allocator.dupe(u8, "none");
    };
    defer parsed.deinit();
    return formatEnabledModules(allocator, parsed.enabledModules());
}

pub fn formatEnabledModules(allocator: std.mem.Allocator, modules: []const []const u8) ![]u8 {
    if (modules.len == 0) {
        return allocator.dupe(u8, "none");
    }
    var builder = std.ArrayList(u8).empty;
    defer builder.deinit(allocator);

    for (modules, 0..) |module_name, idx| {
        if (idx != 0) {
            try builder.appendSlice(allocator, ", ");
        }
        try builder.appendSlice(allocator, module_name);
    }
    return builder.toOwnedSlice(allocator);
}

pub fn formatEnabledModulesJson(allocator: std.mem.Allocator, modules: []const []const u8) ![]u8 {
    if (modules.len == 0) {
        return allocator.dupe(u8, "");
    }
    var builder = std.ArrayList(u8).empty;
    defer builder.deinit(allocator);

    for (modules, 0..) |module_name, idx| {
        if (idx != 0) {
            try builder.appendSlice(allocator, ", ");
        }
        const escaped = try std.fmt.allocPrint(allocator, "\"{s}\"", .{module_name});
        defer allocator.free(escaped);
        try builder.appendSlice(allocator, escaped);
    }
    return builder.toOwnedSlice(allocator);
}
