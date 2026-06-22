const std = @import("std");
const friendly_engine = @import("friendly_engine");
const pm_presets = @import("pm_presets.zig");
const pm_types = @import("pm_types.zig");
const pm_util = @import("pm_util.zig");
const pm_state = @import("pm_state.zig");
const pm_state_config = @import("pm_state_config.zig");
const scene_io = @import("runtime_shared").scene_io;

const starter_agents_md =
    \\# Friendly Engine Project Notes
    \\
    \\This is a Friendly Engine project. The authored project files live here, while
    \\the engine and editor commands are run from the friendly-engine checkout.
    \\
    \\## Repair Loop
    \\
    \\When project files are broken, run the project doctor from the engine checkout:
    \\
    \\```sh
    \\zig build doctor -- --project /absolute/path/to/this/project
    \\```
    \\
    \\If your shell is already in this project folder, use:
    \\
    \\```sh
    \\zig build doctor -- --project .
    \\```
    \\
    \\Doctor checks `engine.kdl`, world manifests, scene KDL files, and referenced
    \\scene meshes/textures. Fix the first concrete file it reports, then rerun it.
    \\Use `--bake` when you also need the world compiler to validate layer output.
    \\
    \\## Running Play Scene
    \\
    \\The editor launches `friendly_engine_client` for Play Scene. If it cannot find
    \\the client executable, build the engine and set:
    \\
    \\```sh
    \\export FRIENDLY_ENGINE_CLIENT_EXE=/absolute/path/to/friendly_engine_client
    \\```
    \\
    \\Common local build path from the engine checkout:
    \\
    \\```sh
    \\zig build
    \\export FRIENDLY_ENGINE_CLIENT_EXE=/absolute/path/to/friendly-engine/zig-out/bin/friendly_engine_client
    \\```
    \\
    \\Keep project changes small and explicit. Broken project data should fail loudly;
    \\do not paper over invalid KDL or missing assets with silent defaults.
    \\
;

pub fn openSelectedProject(state: *pm_state.ProjectManagerState) !void {
    if (state.projects.items.len == 0) {
        state.setStatus("Open failed: no project selected");
        return;
    }
    const idx = state.selected_index;
    var entry = state.projects.items[idx];
    if (isStaleProject(&entry)) {
        state.setStatus("Open failed: project missing on disk");
        return error.FileNotFound;
    }
    state.allocator.free(entry.last_opened);
    entry.last_opened = try state.allocator.dupe(u8, "Opened just now");
    state.allocator.free(entry.status);
    entry.status = try state.allocator.dupe(u8, "Opened in Project Manager");
    state.projects.items[idx] = entry;

    if (idx != 0) {
        std.mem.swap(@TypeOf(entry), &state.projects.items[0], &state.projects.items[idx]);
        state.selected_index = 0;
    }

    try pm_state_config.saveConfig(state);
    state.pending_open_editor = true;
    const msg = try std.fmt.allocPrint(state.allocator, "Opening {s}", .{state.projects.items[state.selected_index].name});
    defer state.allocator.free(msg);
    state.setStatus(msg);
}

pub fn openProject(state: *pm_state.ProjectManagerState, target: ?[]const u8) !void {
    if (state.projects.items.len == 0) return error.ProjectNotFound;
    if (target) |raw| {
        const trimmed = std.mem.trim(u8, raw, " \t\r\n");
        if (trimmed.len > 0) {
            state.selected_index = findProjectIndex(state, trimmed) orelse return error.ProjectNotFound;
        }
    }
    try openSelectedProject(state);
}

pub fn removeSelectedProject(state: *pm_state.ProjectManagerState) !void {
    try removeProject(state, null);
}

pub fn removeProject(state: *pm_state.ProjectManagerState, target: ?[]const u8) !void {
    if (state.projects.items.len == 0) {
        state.setStatus("Remove failed: no project selected");
        return;
    }
    if (target) |raw| {
        const trimmed = std.mem.trim(u8, raw, " \t\r\n");
        if (trimmed.len > 0) {
            state.selected_index = findProjectIndex(state, trimmed) orelse return error.ProjectNotFound;
        }
    }
    var removed = state.projects.orderedRemove(state.selected_index);
    pm_util.deinitProjectEntry(state.allocator, &removed);
    if (state.selected_index >= state.projects.items.len and state.projects.items.len > 0) {
        state.selected_index = state.projects.items.len - 1;
    }
    try pm_state_config.saveConfig(state);
    state.setStatus("Project removed from list");
}

pub fn relocateProjectAtPath(state: *pm_state.ProjectManagerState, target_index: usize, absolute_path: []const u8) !void {
    if (target_index >= state.projects.items.len) return error.ProjectNotFound;
    if (projectExistsAtOtherIndex(state, absolute_path, target_index)) {
        state.setStatus("Relocate skipped: project already in list");
        return error.ProjectExists;
    }

    var project_dir = try std.Io.Dir.openDirAbsolute(state.io, absolute_path, .{});
    project_dir.close(state.io);

    var entry = state.projects.items[target_index];
    state.allocator.free(entry.name);
    entry.name = try state.allocator.dupe(u8, std.fs.path.basename(absolute_path));
    state.allocator.free(entry.path);
    entry.path = try state.allocator.dupe(u8, absolute_path);
    state.allocator.free(entry.tags);
    entry.tags = try pm_util.readModulesSummaryForPath(state.allocator, state.io, absolute_path);
    state.allocator.free(entry.last_opened);
    entry.last_opened = try state.allocator.dupe(u8, "Relinked just now");
    state.allocator.free(entry.status);
    entry.status = try state.allocator.dupe(u8, "Relinked in Project Manager");
    state.projects.items[target_index] = entry;
    state.selected_index = target_index;
    try pm_state_config.saveConfig(state);
    state.setStatus("Project relinked and saved");
}

pub fn resetSelectedProjectToStarter(state: *pm_state.ProjectManagerState) !void {
    if (state.projects.items.len == 0) return error.ProjectNotFound;

    var entry = &state.projects.items[state.selected_index];
    try resetProjectFiles(state, entry.path);

    state.allocator.free(entry.renderer);
    entry.renderer = try state.allocator.dupe(u8, "Forward+");
    state.allocator.free(entry.tags);
    entry.tags = try pm_util.readModulesSummaryForPath(state.allocator, state.io, entry.path);
    state.allocator.free(entry.last_opened);
    entry.last_opened = try state.allocator.dupe(u8, "Reset just now");
    state.allocator.free(entry.status);
    entry.status = try state.allocator.dupe(u8, "Reset from Project Manager");

    try pm_state_config.saveConfig(state);
    state.setStatus("Project reset to clean starter");
}

pub fn importProjectAtPath(state: *pm_state.ProjectManagerState, absolute_path: []const u8) !void {
    try importProjectResolvedPath(state, absolute_path);
}

pub fn importProjectPathInput(state: *pm_state.ProjectManagerState, raw_path: []const u8) !void {
    const absolute_path = try resolveRequiredProjectPath(state, raw_path, "Import canceled: path cannot be empty");
    defer state.allocator.free(absolute_path);
    try importProjectResolvedPath(state, absolute_path);
}

pub fn createProjectAtPath(state: *pm_state.ProjectManagerState, raw_path: []const u8) !void {
    try createProjectAtPathWithModules(state, raw_path, state.selectedCreateModules());
}

pub fn createProjectAtPathWithModules(state: *pm_state.ProjectManagerState, raw_path: []const u8, enabled_modules: []const []const u8) !void {
    const absolute_path = try resolveRequiredProjectPath(state, raw_path, "Create canceled: path cannot be empty");
    defer state.allocator.free(absolute_path);

    if (projectExists(state, absolute_path)) {
        state.setStatus("Create skipped: project already in list");
        state.cancelMode();
        return;
    }

    const root_dir = std.Io.Dir.cwd();
    try root_dir.createDirPath(state.io, absolute_path);
    try ensureStarterFiles(state, absolute_path, enabled_modules);
    try registerProject(state, absolute_path, "Forward+", "Just created", "Created from Project Manager");
    try pm_state_config.saveConfig(state);
    state.setStatus("Project created and saved");
    state.cancelMode();
}

pub fn initExistingProjectAtPath(state: *pm_state.ProjectManagerState, raw_path: []const u8) !void {
    const absolute_path = try resolveRequiredProjectPath(state, raw_path, "Initialize canceled: path cannot be empty");
    defer state.allocator.free(absolute_path);

    var project_dir = try std.Io.Dir.openDirAbsolute(state.io, absolute_path, .{});
    project_dir.close(state.io);

    if (projectExists(state, absolute_path)) {
        try ensureStarterFiles(state, absolute_path, state.default_enabled_modules);
        state.setStatus("Initialize skipped: project already in list");
        return;
    }

    try ensureStarterFiles(state, absolute_path, state.default_enabled_modules);
    try registerProject(state, absolute_path, "Forward+", "Just initialized", "Initialized existing folder");
    state.setStatus("Existing folder initialized and saved");
}

fn importProjectResolvedPath(state: *pm_state.ProjectManagerState, absolute_path: []const u8) !void {
    if (projectExists(state, absolute_path)) {
        state.setStatus("Import skipped: project already in list");
        return;
    }

    var imported_dir = try std.Io.Dir.openDirAbsolute(state.io, absolute_path, .{});
    imported_dir.close(state.io);

    const modules_summary = try pm_util.readModulesSummaryForPath(state.allocator, state.io, absolute_path);
    defer state.allocator.free(modules_summary);
    const import_status = if (std.mem.eql(u8, modules_summary, "none")) "Imported (no engine.kdl)" else "Imported";
    try registerProjectWithModules(state, absolute_path, "Unknown", modules_summary, "Just imported", import_status);
    state.setStatus("Project imported and saved");
}

pub fn createProjectFromInput(state: *pm_state.ProjectManagerState) !void {
    try createProjectAtPath(state, state.inputText());
}

fn ensureStarterFiles(state: *pm_state.ProjectManagerState, absolute_path: []const u8, enabled_modules: []const []const u8) !void {
    const engine_kdl_path = try std.fs.path.join(state.allocator, &.{ absolute_path, "engine.kdl" });
    defer state.allocator.free(engine_kdl_path);

    const root_dir = std.Io.Dir.cwd();
    root_dir.access(state.io, engine_kdl_path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            const scene_entries = [_]friendly_engine.modules.SceneEntry{
                .{ .path = "scenes/main.kdl", .world = "world.kdl" },
            };
            const engine_kdl_data = try friendly_engine.modules.formatProjectConfig(
                state.allocator,
                enabled_modules,
                "scenes/main.kdl",
                "",
                &scene_entries,
            );
            defer state.allocator.free(engine_kdl_data);

            try root_dir.writeFile(state.io, .{
                .sub_path = engine_kdl_path,
                .data = engine_kdl_data,
            });
        },
        else => return err,
    };
    try scene_io.ensureSampleScene(state.allocator, state.io, absolute_path, "scenes/main.kdl");
    try ensureSampleWorld(state, absolute_path);
    try ensureStarterAgents(state, absolute_path);
}

fn registerProject(
    state: *pm_state.ProjectManagerState,
    absolute_path: []const u8,
    renderer: []const u8,
    last_opened: []const u8,
    status: []const u8,
) !void {
    const modules_summary = try pm_util.readModulesSummaryForPath(state.allocator, state.io, absolute_path);
    defer state.allocator.free(modules_summary);
    try registerProjectWithModules(state, absolute_path, renderer, modules_summary, last_opened, status);
}

fn registerProjectWithModules(
    state: *pm_state.ProjectManagerState,
    absolute_path: []const u8,
    renderer: []const u8,
    modules_summary: []const u8,
    last_opened: []const u8,
    status: []const u8,
) !void {
    const entry = try pm_util.makeProjectEntry(
        state.allocator,
        std.fs.path.basename(absolute_path),
        absolute_path,
        renderer,
        modules_summary,
        last_opened,
        status,
    );
    try state.projects.append(state.allocator, entry);
    state.selected_index = state.projects.items.len - 1;
    try pm_state_config.saveConfig(state);
}

fn ensureSampleWorld(state: *pm_state.ProjectManagerState, project_path: []const u8) !void {
    const world_path = try std.fs.path.join(state.allocator, &.{ project_path, "world.kdl" });
    defer state.allocator.free(world_path);
    const root_dir = std.Io.Dir.cwd();
    root_dir.access(state.io, world_path, .{}) catch |err| switch (err) {
        error.FileNotFound => try root_dir.writeFile(state.io, .{
            .sub_path = world_path,
            .data =
            \\world version=1 id="main" cell_size_m=256 {
            \\  cell coord="0,0,0" authoring="scenes/main.kdl"
            \\}
            \\
            ,
        }),
        else => return err,
    };
}

fn resetProjectFiles(state: *pm_state.ProjectManagerState, project_path: []const u8) !void {
    const root_dir = std.Io.Dir.cwd();
    try root_dir.createDirPath(state.io, project_path);

    const authored_dirs = [_][]const u8{
        "scenes",
        "layers",
        "worlds",
        "props",
        "assets/cache",
        "assets/bundles",
    };
    for (authored_dirs) |rel_path| try deleteProjectTreeIfPresent(state, project_path, rel_path);

    const authored_files = [_][]const u8{
        "engine.kdl",
        "world.kdl",
        "main.kdl",
    };
    for (authored_files) |rel_path| try deleteProjectFileIfPresent(state, project_path, rel_path);

    const scene_entries = [_]friendly_engine.modules.SceneEntry{
        .{ .path = "scenes/main.kdl", .world = "world.kdl" },
    };
    const engine_kdl_data = try friendly_engine.modules.formatProjectConfig(
        state.allocator,
        state.default_enabled_modules,
        "scenes/main.kdl",
        "",
        &scene_entries,
    );
    defer state.allocator.free(engine_kdl_data);

    const engine_kdl_path = try std.fs.path.join(state.allocator, &.{ project_path, "engine.kdl" });
    defer state.allocator.free(engine_kdl_path);
    try root_dir.writeFile(state.io, .{
        .sub_path = engine_kdl_path,
        .data = engine_kdl_data,
    });

    try scene_io.ensureSampleScene(state.allocator, state.io, project_path, "scenes/main.kdl");
    try ensureSampleWorld(state, project_path);
    try ensureStarterAgents(state, project_path);
}

fn ensureStarterAgents(state: *pm_state.ProjectManagerState, project_path: []const u8) !void {
    const agents_path = try std.fs.path.join(state.allocator, &.{ project_path, "AGENTS.md" });
    defer state.allocator.free(agents_path);
    const root_dir = std.Io.Dir.cwd();
    root_dir.access(state.io, agents_path, .{}) catch |err| switch (err) {
        error.FileNotFound => try root_dir.writeFile(state.io, .{
            .sub_path = agents_path,
            .data = starter_agents_md,
        }),
        else => return err,
    };
}

fn deleteProjectTreeIfPresent(state: *pm_state.ProjectManagerState, project_path: []const u8, rel_path: []const u8) !void {
    const path = try std.fs.path.join(state.allocator, &.{ project_path, rel_path });
    defer state.allocator.free(path);
    std.Io.Dir.cwd().access(state.io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    try std.Io.Dir.cwd().deleteTree(state.io, path);
}

fn deleteProjectFileIfPresent(state: *pm_state.ProjectManagerState, project_path: []const u8, rel_path: []const u8) !void {
    const path = try std.fs.path.join(state.allocator, &.{ project_path, rel_path });
    defer state.allocator.free(path);
    std.Io.Dir.cwd().deleteFile(state.io, path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };
}

fn resolveProjectPath(state: *pm_state.ProjectManagerState, input: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(input)) {
        return state.allocator.dupe(u8, input);
    }
    return std.fs.path.join(state.allocator, &.{ state.workspace_path, input });
}

fn resolveRequiredProjectPath(state: *pm_state.ProjectManagerState, raw_path: []const u8, empty_status: []const u8) ![]u8 {
    const trimmed = std.mem.trim(u8, raw_path, " \t\r\n");
    if (trimmed.len == 0) {
        state.setStatus(empty_status);
        return error.MissingPath;
    }
    return resolveProjectPath(state, trimmed);
}

fn projectExists(state: *const pm_state.ProjectManagerState, path: []const u8) bool {
    for (state.projects.items) |entry| {
        if (std.mem.eql(u8, entry.path, path)) {
            return true;
        }
    }
    return false;
}

fn projectExistsAtOtherIndex(state: *const pm_state.ProjectManagerState, path: []const u8, ignore_index: usize) bool {
    for (state.projects.items, 0..) |entry, index| {
        if (index == ignore_index) continue;
        if (std.mem.eql(u8, entry.path, path)) return true;
    }
    return false;
}

fn isStaleProject(entry: *const pm_types.ProjectManagerEntry) bool {
    return std.mem.startsWith(u8, entry.status, "Stale");
}

fn findProjectIndex(state: *const pm_state.ProjectManagerState, target: []const u8) ?usize {
    for (state.projects.items, 0..) |entry, index| {
        if (std.mem.eql(u8, entry.path, target) or std.mem.eql(u8, entry.name, target)) {
            return index;
        }
    }
    return null;
}

fn makeTestState(allocator: std.mem.Allocator, workspace_path: []const u8, state_file_path: []const u8) !pm_state.ProjectManagerState {
    return .{
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
}

fn expectPathExists(path: []const u8) !void {
    try std.Io.Dir.cwd().access(std.testing.io, path, .{});
}

fn realPathDirAlloc(allocator: std.mem.Allocator, dir: std.Io.Dir) ![]u8 {
    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    const len = try dir.realPath(std.testing.io, &buffer);
    return allocator.dupe(u8, buffer[0..len]);
}

test "project create creates starter files and registers project" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    const workspace_path = try realPathDirAlloc(allocator, tmp.dir);
    defer allocator.free(workspace_path);
    const state_file_path = try std.fs.path.join(allocator, &.{ workspace_path, "project_manager.json" });
    defer allocator.free(state_file_path);

    var state = try makeTestState(allocator, workspace_path, state_file_path);
    defer state.deinit();

    const project_path = try std.fs.path.join(allocator, &.{ workspace_path, "created" });
    defer allocator.free(project_path);
    try createProjectAtPath(&state, project_path);

    try std.testing.expectEqual(@as(usize, 1), state.projects.items.len);
    try std.testing.expectEqual(@as(usize, 0), state.selected_index);
    try std.testing.expectEqualStrings("created", state.projects.items[0].name);
    try std.testing.expectEqualStrings(project_path, state.projects.items[0].path);

    const engine_path = try std.fs.path.join(allocator, &.{ project_path, "engine.kdl" });
    defer allocator.free(engine_path);
    const world_path = try std.fs.path.join(allocator, &.{ project_path, "world.kdl" });
    defer allocator.free(world_path);
    const scene_path = try std.fs.path.join(allocator, &.{ project_path, "scenes/main.kdl" });
    defer allocator.free(scene_path);
    const agents_path = try std.fs.path.join(allocator, &.{ project_path, "AGENTS.md" });
    defer allocator.free(agents_path);
    try expectPathExists(engine_path);
    try expectPathExists(world_path);
    try expectPathExists(scene_path);
    try expectPathExists(agents_path);
    try expectPathExists(state_file_path);

    const engine_bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, engine_path, allocator, .limited(4096));
    defer allocator.free(engine_bytes);
    var parsed = try friendly_engine.modules.parseProjectConfigBytes(allocator, engine_bytes);
    defer parsed.deinit();
    const minimal = pm_presets.builtinPresets()[0].modules;
    try std.testing.expectEqual(minimal.len, parsed.enabledModules().len);
    for (minimal, parsed.enabledModules()) |expected, actual| {
        try std.testing.expectEqualStrings(expected, actual);
    }

    const agents_bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, agents_path, allocator, .limited(8192));
    defer allocator.free(agents_bytes);
    try std.testing.expect(std.mem.indexOf(u8, agents_bytes, "zig build doctor -- --project") != null);
    try std.testing.expect(std.mem.indexOf(u8, agents_bytes, "FRIENDLY_ENGINE_CLIENT_EXE") != null);
}

test "project import registers existing folder without creating starter files" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    const workspace_path = try realPathDirAlloc(allocator, tmp.dir);
    defer allocator.free(workspace_path);
    const state_file_path = try std.fs.path.join(allocator, &.{ workspace_path, "project_manager.json" });
    defer allocator.free(state_file_path);
    try tmp.dir.createDirPath(std.testing.io, "imported");
    const project_path = try tmp.dir.realPathFileAlloc(std.testing.io, "imported", allocator);
    defer allocator.free(project_path);

    var state = try makeTestState(allocator, workspace_path, state_file_path);
    defer state.deinit();

    try importProjectAtPath(&state, project_path);

    try std.testing.expectEqual(@as(usize, 1), state.projects.items.len);
    try std.testing.expectEqualStrings(project_path, state.projects.items[0].path);
    try std.testing.expectEqualStrings("Imported (no engine.kdl)", state.projects.items[0].status);

    const engine_path = try std.fs.path.join(allocator, &.{ project_path, "engine.kdl" });
    defer allocator.free(engine_path);
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().access(std.testing.io, engine_path, .{}));
}

test "project relocate keeps entry and updates path" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    const workspace_path = try realPathDirAlloc(allocator, tmp.dir);
    defer allocator.free(workspace_path);
    const state_file_path = try std.fs.path.join(allocator, &.{ workspace_path, "project_manager.json" });
    defer allocator.free(state_file_path);

    var state = try makeTestState(allocator, workspace_path, state_file_path);
    defer state.deinit();

    const stale_path = try std.fs.path.join(allocator, &.{ workspace_path, "stale-project" });
    defer allocator.free(stale_path);
    const relocated_dir = try std.fs.path.join(allocator, &.{ workspace_path, "relocated-project" });
    defer allocator.free(relocated_dir);
    try tmp.dir.createDirPath(std.testing.io, "relocated-project");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "relocated-project/engine.kdl",
        .data =
        \\engine startup_scene="scenes/main.kdl" {
        \\}
        \\
        ,
    });

    const entry = try pm_util.makeProjectEntry(
        allocator,
        "stale-project",
        stale_path,
        "Forward+",
        "gem.core_ui",
        "Just imported",
        "Stale: missing on disk",
    );
    try state.projects.append(allocator, entry);
    state.selected_index = 0;

    try relocateProjectAtPath(&state, 0, relocated_dir);

    try std.testing.expectEqual(@as(usize, 1), state.projects.items.len);
    try std.testing.expectEqualStrings(relocated_dir, state.projects.items[0].path);
    try std.testing.expectEqualStrings("relocated-project", state.projects.items[0].name);
    try std.testing.expectEqualStrings("Relinked in Project Manager", state.projects.items[0].status);
}

test "project remove updates list only" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    const workspace_path = try realPathDirAlloc(allocator, tmp.dir);
    defer allocator.free(workspace_path);
    const state_file_path = try std.fs.path.join(allocator, &.{ workspace_path, "project_manager.json" });
    defer allocator.free(state_file_path);

    var state = try makeTestState(allocator, workspace_path, state_file_path);
    defer state.deinit();

    const project_path = try std.fs.path.join(allocator, &.{ workspace_path, "remove-me" });
    defer allocator.free(project_path);
    try createProjectAtPath(&state, project_path);
    try removeProject(&state, "remove-me");

    try std.testing.expectEqual(@as(usize, 0), state.projects.items.len);
    try expectPathExists(project_path);
}

test "project init existing requires a folder" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    const workspace_path = try realPathDirAlloc(allocator, tmp.dir);
    defer allocator.free(workspace_path);
    const state_file_path = try std.fs.path.join(allocator, &.{ workspace_path, "project_manager.json" });
    defer allocator.free(state_file_path);

    var state = try makeTestState(allocator, workspace_path, state_file_path);
    defer state.deinit();

    const missing_path = try std.fs.path.join(allocator, &.{ workspace_path, "missing" });
    defer allocator.free(missing_path);
    try std.testing.expectError(error.FileNotFound, initExistingProjectAtPath(&state, missing_path));
}

test "project init existing preserves files and fills missing starter files" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    const workspace_path = try realPathDirAlloc(allocator, tmp.dir);
    defer allocator.free(workspace_path);
    const state_file_path = try std.fs.path.join(allocator, &.{ workspace_path, "project_manager.json" });
    defer allocator.free(state_file_path);
    try tmp.dir.createDirPath(std.testing.io, "existing");
    const project_path = try tmp.dir.realPathFileAlloc(std.testing.io, "existing", allocator);
    defer allocator.free(project_path);

    const custom_engine =
        \\engine startup_scene="custom.kdl" {
        \\}
        \\
    ;
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "existing/engine.kdl", .data = custom_engine });

    var state = try makeTestState(allocator, workspace_path, state_file_path);
    defer state.deinit();

    try initExistingProjectAtPath(&state, project_path);

    try std.testing.expectEqual(@as(usize, 1), state.projects.items.len);
    try std.testing.expectEqualStrings(project_path, state.projects.items[0].path);

    const engine_bytes = try tmp.dir.readFileAlloc(std.testing.io, "existing/engine.kdl", allocator, .limited(4096));
    defer allocator.free(engine_bytes);
    try std.testing.expectEqualStrings(custom_engine, engine_bytes);

    const world_path = try std.fs.path.join(allocator, &.{ project_path, "world.kdl" });
    defer allocator.free(world_path);
    const scene_path = try std.fs.path.join(allocator, &.{ project_path, "scenes/main.kdl" });
    defer allocator.free(scene_path);
    const agents_path = try std.fs.path.join(allocator, &.{ project_path, "AGENTS.md" });
    defer allocator.free(agents_path);
    try expectPathExists(world_path);
    try expectPathExists(scene_path);
    try expectPathExists(agents_path);
}
