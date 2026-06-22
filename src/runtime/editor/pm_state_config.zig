const std = @import("std");
const pm_presets = @import("pm_presets.zig");
const pm_util = @import("pm_util.zig");
const pm_state = @import("pm_state.zig");

pub fn saveConfig(state: *pm_state.ProjectManagerState) !void {
    const Persisted = struct {
        schema_version: u32 = 1,
        selected_index: usize,
        projects: []const PersistedProject,
        presets: []const PersistedPreset,
        last_preset: []const u8,

        const PersistedProject = struct {
            name: []const u8,
            path: []const u8,
            renderer: []const u8,
            tags: []const u8,
            last_opened: []const u8,
            status: []const u8,
        };

        const PersistedPreset = struct {
            name: []const u8,
            modules: []const []const u8,
        };
    };

    var persisted_projects = try state.allocator.alloc(Persisted.PersistedProject, state.projects.items.len);
    defer state.allocator.free(persisted_projects);
    for (state.projects.items, 0..) |entry, idx| {
        persisted_projects[idx] = .{
            .name = entry.name,
            .path = entry.path,
            .renderer = entry.renderer,
            .tags = entry.tags,
            .last_opened = entry.last_opened,
            .status = entry.status,
        };
    }
    var persisted_presets = try state.allocator.alloc(Persisted.PersistedPreset, state.user_presets.items.len);
    defer state.allocator.free(persisted_presets);
    for (state.user_presets.items, 0..) |preset, idx| {
        persisted_presets[idx] = .{
            .name = preset.name,
            .modules = preset.modules,
        };
    }

    const payload = Persisted{
        .selected_index = state.selected_index,
        .projects = persisted_projects,
        .presets = persisted_presets,
        .last_preset = state.selectedCreatePresetName(),
    };
    const json = try std.fmt.allocPrint(
        state.allocator,
        "{f}\n",
        .{std.json.fmt(payload, .{ .whitespace = .indent_2 })},
    );
    defer state.allocator.free(json);

    try std.Io.Dir.cwd().writeFile(state.io, .{
        .sub_path = state.state_file_path,
        .data = json,
    });
}

pub fn loadConfig(state: *pm_state.ProjectManagerState) !bool {
    const bytes = std.Io.Dir.cwd().readFileAlloc(
        state.io,
        state.state_file_path,
        state.allocator,
        .limited(512 * 1024),
    ) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    defer state.allocator.free(bytes);

    const Parsed = struct {
        schema_version: u32 = 1,
        selected_index: usize = 0,
        projects: []const struct {
            name: []const u8,
            path: []const u8,
            renderer: []const u8 = "Unknown",
            tags: []const u8 = "none",
            last_opened: []const u8 = "Unknown",
            status: []const u8 = "Imported",
        } = &.{},
        presets: []const struct {
            name: []const u8,
            modules: []const []const u8,
        } = &.{},
        last_preset: []const u8 = "Minimal",
    };

    var parsed = try std.json.parseFromSlice(Parsed, state.allocator, bytes, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    var refreshed_project_summaries = false;
    for (parsed.value.projects) |project| {
        var entry = try pm_util.makeProjectEntry(
            state.allocator,
            project.name,
            project.path,
            project.renderer,
            project.tags,
            project.last_opened,
            project.status,
        );
        errdefer pm_util.deinitProjectEntry(state.allocator, &entry);

        const refreshed_tags = try pm_util.readModulesSummaryForPath(state.allocator, state.io, project.path);
        if (!std.mem.eql(u8, entry.tags, refreshed_tags)) {
            refreshed_project_summaries = true;
        }
        state.allocator.free(entry.tags);
        entry.tags = refreshed_tags;

        try state.projects.append(state.allocator, entry);
    }

    if (state.projects.items.len == 0) {
        state.selected_index = 0;
    } else {
        state.selected_index = @min(parsed.value.selected_index, state.projects.items.len - 1);
    }
    for (parsed.value.presets) |preset| {
        const modules = try pm_presets.dupeModuleList(state.allocator, preset.modules);
        errdefer {
            for (modules) |module| state.allocator.free(module);
            state.allocator.free(modules);
        }
        const owned = pm_presets.GemPreset{
            .name = try state.allocator.dupe(u8, preset.name),
            .modules = modules,
            .builtin = false,
        };
        errdefer state.allocator.free(@constCast(owned.name));
        try state.user_presets.append(state.allocator, owned);
    }
    state.allocator.free(state.create_preset_name);
    state.create_preset_name = try state.allocator.dupe(u8, parsed.value.last_preset);
    if (refreshed_project_summaries) try saveConfig(state);
    return true;
}

test "config round-trips user presets and last preset" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    const workspace_path = try realPathDirAlloc(allocator, tmp.dir);
    defer allocator.free(workspace_path);
    const state_file_path = try std.fs.path.join(allocator, &.{ workspace_path, "project_manager.json" });
    defer allocator.free(state_file_path);

    var state = pm_state.ProjectManagerState{
        .allocator = allocator,
        .io = std.testing.io,
        .workspace_path = try allocator.dupe(u8, workspace_path),
        .state_file_path = try allocator.dupe(u8, state_file_path),
        .projects = .empty,
        .default_enabled_modules_json = try allocator.dupe(u8, ""),
        .default_enabled_modules = try allocator.alloc([]u8, 0),
        .user_presets = .empty,
        .create_preset_name = try allocator.dupe(u8, "Minimal"),
        .preset_edit_modules = try allocator.alloc(bool, pm_presets.catalogModuleNames().len),
    };
    defer state.deinit();

    try state.addPreset("Core-ish", &.{ "gem.ecs", "gem.core_ui" });
    try state.selectCreatePreset(2);
    try saveConfig(&state);

    var loaded = pm_state.ProjectManagerState{
        .allocator = allocator,
        .io = std.testing.io,
        .workspace_path = try allocator.dupe(u8, workspace_path),
        .state_file_path = try allocator.dupe(u8, state_file_path),
        .projects = .empty,
        .default_enabled_modules_json = try allocator.dupe(u8, ""),
        .default_enabled_modules = try allocator.alloc([]u8, 0),
        .user_presets = .empty,
        .create_preset_name = try allocator.dupe(u8, "Minimal"),
        .preset_edit_modules = try allocator.alloc(bool, pm_presets.catalogModuleNames().len),
    };
    defer loaded.deinit();

    try std.testing.expect(try loadConfig(&loaded));
    try std.testing.expectEqual(@as(usize, 1), loaded.user_presets.items.len);
    try std.testing.expectEqualStrings("Core-ish", loaded.user_presets.items[0].name);
    try std.testing.expectEqualStrings("Core-ish", loaded.create_preset_name);
    try std.testing.expectEqualStrings("gem.ecs", loaded.user_presets.items[0].modules[0]);
}

test "config without presets loads as empty back-compat" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    const workspace_path = try realPathDirAlloc(allocator, tmp.dir);
    defer allocator.free(workspace_path);
    const state_file_path = try std.fs.path.join(allocator, &.{ workspace_path, "project_manager.json" });
    defer allocator.free(state_file_path);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{
        .sub_path = state_file_path,
        .data = "{ \"schema_version\": 1, \"selected_index\": 0, \"projects\": [] }\n",
    });

    var state = pm_state.ProjectManagerState{
        .allocator = allocator,
        .io = std.testing.io,
        .workspace_path = try allocator.dupe(u8, workspace_path),
        .state_file_path = try allocator.dupe(u8, state_file_path),
        .projects = .empty,
        .default_enabled_modules_json = try allocator.dupe(u8, ""),
        .default_enabled_modules = try allocator.alloc([]u8, 0),
        .user_presets = .empty,
        .create_preset_name = try allocator.dupe(u8, "Minimal"),
        .preset_edit_modules = try allocator.alloc(bool, pm_presets.catalogModuleNames().len),
    };
    defer state.deinit();

    try std.testing.expect(try loadConfig(&state));
    try std.testing.expectEqual(@as(usize, 0), state.user_presets.items.len);
    try std.testing.expectEqualStrings("Minimal", state.create_preset_name);
}

fn realPathDirAlloc(allocator: std.mem.Allocator, dir: std.Io.Dir) ![]u8 {
    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    const len = try dir.realPath(std.testing.io, &buffer);
    return allocator.dupe(u8, buffer[0..len]);
}
