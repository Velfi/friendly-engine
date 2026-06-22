const std = @import("std");
const shared = @import("runtime_shared");
const friendly_engine = @import("friendly_engine");
const editor_scene_object = @import("editor_scene_object.zig");
const project_editor_edit = @import("project_editor_edit.zig");
const project_editor_state = @import("project_editor_state.zig");

const geometry = shared.geometry;
const ProjectEditorState = project_editor_state.ProjectEditorState;
const fps_controller_component = "controller:fps";
const player_start_tag = "player_start";
pub const player_spawn_ground_clearance_m: f32 = 0.16;
const client_exe_env_var = "FRIENDLY_ENGINE_CLIENT_EXE";
const log = std.log.scoped(.editor_play);

pub fn runBuild(state: *ProjectEditorState) void {
    project_editor_state.clearPlayErrorDetail(state);
    project_editor_state.setStatus(state, "Build started");
    const argv = &.{ "zig", "build" };
    const result = std.process.run(state.allocator, state.io, .{
        .argv = argv,
        .cwd = .{ .path = state.project_path },
        .stdout_limit = .limited(32 * 1024),
        .stderr_limit = .limited(32 * 1024),
    }) catch |err| {
        project_editor_state.setStatus(state, "Build failed to start");
        setBuildErrorDetail(state, argv, null, err, "", "") catch {};
        return;
    };
    defer state.allocator.free(result.stdout);
    defer state.allocator.free(result.stderr);

    switch (result.term) {
        .exited => |code| {
            if (code == 0) {
                project_editor_state.setStatus(state, "Build succeeded");
            } else {
                log.err("build failed exit_code={d} stderr_tail=\"{s}\" stdout_tail=\"{s}\"", .{
                    code,
                    tailText(result.stderr, 2048),
                    tailText(result.stdout, 1024),
                });
                project_editor_state.setStatus(state, "Build failed: details available");
                setBuildErrorDetail(state, argv, code, null, result.stderr, result.stdout) catch {};
            }
        },
        .signal, .stopped, .unknown => {
            project_editor_state.setStatus(state, "Build stopped: details available");
            setBuildErrorDetail(state, argv, null, error.BuildStopped, result.stderr, result.stdout) catch {};
        },
    }
}

pub fn runPlayScene(state: *ProjectEditorState) !void {
    try runPlaySceneWithFrameLimit(state, null);
}

pub fn runPlaySceneWithFrameLimit(state: *ProjectEditorState, frame_limit: ?u64) !void {
    project_editor_state.clearPlayErrorDetail(state);
    project_editor_state.setStatus(state, "Saving scene for play");
    state.saveSceneToDisk() catch |err| {
        project_editor_state.setStatus(state, "Play failed: could not save scene");
        setPlaySceneSetupErrorDetail(state, "saving scene", err) catch {};
        return err;
    };
    state.scene_dirty = false;

    var frame_arg: ?[]u8 = null;
    defer if (frame_arg) |arg| state.allocator.free(arg);
    var config = friendly_engine.modules.loadProjectConfigInProject(
        state.allocator,
        state.io,
        state.project_path,
        "engine.kdl",
    ) catch |err| {
        project_editor_state.setStatus(state, "Play failed: could not load engine.kdl");
        setPlaySceneSetupErrorDetail(state, "loading project config", err) catch {};
        return err;
    };
    defer config.deinit();

    const client_path = clientExecutablePath(state.allocator, state.io) catch |err| {
        project_editor_state.setStatus(state, "Play failed: friendly_engine_client not found");
        setPlaySceneSetupErrorDetail(state, "locating friendly_engine_client", err) catch {};
        return err;
    };
    defer state.allocator.free(client_path);
    var argv_buf: [6][]const u8 = undefined;
    const argv = try playSceneArgv(state.allocator, &argv_buf, client_path, state.project_path, config.startupScene(), frame_limit, &frame_arg);
    project_editor_state.setStatus(state, "Play scene running");
    const result = std.process.run(state.allocator, state.io, .{
        .argv = argv,
        .stdout_limit = .limited(64 * 1024),
        .stderr_limit = .limited(64 * 1024),
    }) catch |err| {
        project_editor_state.setStatus(state, "Play scene failed to start");
        setPlaySceneErrorDetail(state, argv, null, err, "", "") catch {};
        return error.PlaySceneLaunchFailed;
    };
    defer state.allocator.free(result.stdout);
    defer state.allocator.free(result.stderr);

    switch (result.term) {
        .exited => |code| {
            if (code == 0) {
                project_editor_state.setStatus(state, "Play scene ended");
            } else {
                log.err("play scene failed exit_code={d} stderr_tail=\"{s}\" stdout_tail=\"{s}\"", .{
                    code,
                    tailText(result.stderr, 2048),
                    tailText(result.stdout, 1024),
                });
                project_editor_state.setStatus(state, playSceneFailureStatus(result.stderr, result.stdout));
                setPlaySceneErrorDetail(state, argv, code, null, result.stderr, result.stdout) catch {};
                return error.PlaySceneFailed;
            }
        },
        .signal, .stopped, .unknown => {
            project_editor_state.setStatus(state, "Play scene stopped");
            setPlaySceneErrorDetail(state, argv, null, error.PlaySceneStopped, result.stderr, result.stdout) catch {};
            return error.PlaySceneStopped;
        },
    }
}

fn setPlaySceneSetupErrorDetail(
    state: *ProjectEditorState,
    stage: []const u8,
    err: anyerror,
) !void {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(state.allocator);
    try out.appendSlice(state.allocator, "Play Scene failed\n\nStage: ");
    try out.appendSlice(state.allocator, stage);
    try appendFmt(state.allocator, &out, "\n\nError: {s}", .{@errorName(err)});
    if (err == error.FileNotFound and std.mem.eql(u8, stage, "locating friendly_engine_client")) {
        try out.appendSlice(state.allocator, "\n\nThe editor could not find the runtime client executable. Build friendly_engine_client or set FRIENDLY_ENGINE_CLIENT_EXE to its full path before pressing Play Scene.");
    }
    try project_editor_state.setPlayErrorDetail(state, out.items);
}

fn setBuildErrorDetail(
    state: *ProjectEditorState,
    argv: []const []const u8,
    exit_code: ?u8,
    launch_error: ?anyerror,
    stderr: []const u8,
    stdout: []const u8,
) !void {
    const detail = try formatProcessErrorDetail(
        state.allocator,
        "Build failed",
        argv,
        exit_code,
        launch_error,
        stderr,
        stdout,
        8192,
        4096,
    );
    defer state.allocator.free(detail);
    try project_editor_state.setPlayErrorDetail(state, detail);
}

fn setPlaySceneErrorDetail(
    state: *ProjectEditorState,
    argv: []const []const u8,
    exit_code: ?u8,
    launch_error: ?anyerror,
    stderr: []const u8,
    stdout: []const u8,
) !void {
    const detail = try formatProcessErrorDetail(
        state.allocator,
        "Play Scene failed",
        argv,
        exit_code,
        launch_error,
        stderr,
        stdout,
        8192,
        4096,
    );
    defer state.allocator.free(detail);
    try project_editor_state.setPlayErrorDetail(state, detail);
}

fn formatProcessErrorDetail(
    allocator: std.mem.Allocator,
    title: []const u8,
    argv: []const []const u8,
    exit_code: ?u8,
    launch_error: ?anyerror,
    stderr: []const u8,
    stdout: []const u8,
    stderr_tail_len: usize,
    stdout_tail_len: usize,
) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, title);
    try out.appendSlice(allocator, "\n\nCommand:\n");
    for (argv, 0..) |arg, idx| {
        if (idx > 0) try out.append(allocator, ' ');
        try appendShellArg(allocator, &out, arg);
    }
    if (exit_code) |code| {
        try appendFmt(allocator, &out, "\n\nExit code: {d}", .{code});
    }
    if (launch_error) |err| {
        try appendFmt(allocator, &out, "\n\nError: {s}", .{@errorName(err)});
    }
    try out.appendSlice(allocator, "\n\nstderr tail:\n");
    try appendOutputTail(allocator, &out, stderr, stderr_tail_len);
    try out.appendSlice(allocator, "\n\nstdout tail:\n");
    try appendOutputTail(allocator, &out, stdout, stdout_tail_len);
    return try out.toOwnedSlice(allocator);
}

fn appendFmt(allocator: std.mem.Allocator, out: *std.ArrayList(u8), comptime fmt: []const u8, args: anytype) !void {
    const text = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(text);
    try out.appendSlice(allocator, text);
}

fn appendShellArg(allocator: std.mem.Allocator, out: *std.ArrayList(u8), arg: []const u8) !void {
    if (arg.len == 0) {
        try out.appendSlice(allocator, "''");
        return;
    }
    const safe = for (arg) |ch| {
        if (!std.ascii.isAlphanumeric(ch) and ch != '/' and ch != '.' and ch != '_' and ch != '-' and ch != ':' and ch != '=') break false;
    } else true;
    if (safe) {
        try out.appendSlice(allocator, arg);
        return;
    }
    try out.append(allocator, '\'');
    for (arg) |ch| {
        if (ch == '\'') {
            try out.appendSlice(allocator, "'\\''");
        } else {
            try out.append(allocator, ch);
        }
    }
    try out.append(allocator, '\'');
}

fn appendOutputTail(allocator: std.mem.Allocator, out: *std.ArrayList(u8), text: []const u8, max_len: usize) !void {
    const tail = tailText(text, max_len);
    if (tail.len == 0) {
        try out.appendSlice(allocator, "(empty)");
        return;
    }
    if (tail.len < text.len) try out.appendSlice(allocator, "... truncated ...\n");
    try out.appendSlice(allocator, tail);
}

pub fn playSceneArgv(
    allocator: std.mem.Allocator,
    out: *[6][]const u8,
    client_path: []const u8,
    project_path: []const u8,
    scene_path: []const u8,
    frame_limit: ?u64,
    owned_frame_arg: *?[]u8,
) ![]const []const u8 {
    out[0] = client_path;
    out[1] = "--project";
    out[2] = project_path;
    out[3] = "--startup-scene";
    out[4] = scene_path;
    if (frame_limit) |limit| {
        owned_frame_arg.* = try std.fmt.allocPrint(allocator, "--frames={d}", .{limit});
        out[5] = owned_frame_arg.*.?;
        return out[0..6];
    }
    return out[0..5];
}

fn clientExecutablePath(allocator: std.mem.Allocator, io: std.Io) ![]u8 {
    if (std.c.getenv(client_exe_env_var)) |raw_env_path| {
        const env_path = std.mem.span(raw_env_path);
        if (env_path.len > 0 and fileExists(io, env_path)) return allocator.dupe(u8, env_path);
    }

    const dir = try std.process.executableDirPathAlloc(io, allocator);
    defer allocator.free(dir);

    const adjacent = try std.fs.path.join(allocator, &.{ dir, "friendly_engine_client" });
    if (fileExists(io, adjacent)) return adjacent;
    allocator.free(adjacent);

    const local_install = try std.fs.path.join(allocator, &.{ dir, "zig-out", "bin", "friendly_engine_client" });
    if (fileExists(io, local_install)) return local_install;
    allocator.free(local_install);

    if (cacheRunRoot(dir)) |root| {
        const installed = try std.fs.path.join(allocator, &.{ root, "zig-out", "bin", "friendly_engine_client" });
        if (fileExists(io, installed)) return installed;
        allocator.free(installed);
    }

    return error.FileNotFound;
}

fn cacheRunRoot(exe_dir: []const u8) ?[]const u8 {
    const object_dir = std.fs.path.dirname(exe_dir) orelse return null;
    if (!std.mem.eql(u8, std.fs.path.basename(object_dir), "o")) return null;
    const cache_dir = std.fs.path.dirname(object_dir) orelse return null;
    if (!std.mem.eql(u8, std.fs.path.basename(cache_dir), ".zig-cache")) return null;
    return std.fs.path.dirname(cache_dir);
}

fn fileExists(io: std.Io, path: []const u8) bool {
    var file = std.Io.Dir.openFileAbsolute(io, path, .{}) catch return false;
    file.close(io);
    return true;
}

fn playSceneFailureStatus(stderr: []const u8, stdout: []const u8) []const u8 {
    if (hasPlayOutput(stderr, stdout, "missing baked world cell") or
        hasPlayOutput(stderr, stdout, "startup.loading_initial_cells.fail err=FileNotFound"))
    {
        return "Play failed: missing baked world cells. Recompile Cells, then Play again.";
    }
    if (hasPlayOutput(stderr, stdout, "InvalidWaterDocument")) {
        return "Play failed: invalid water layer. Check layers/water.kdl.";
    }
    if (hasPlayOutput(stderr, stdout, "InvalidBuildingsDocument")) {
        return "Play failed: invalid buildings layer. Check layers/buildings.kdl.";
    }
    if (hasPlayOutput(stderr, stdout, "InvalidScatterDocument")) {
        return "Play failed: invalid scatter layer. Check layers/scatter.kdl.";
    }
    if (hasPlayOutput(stderr, stdout, "InvalidLocalCsgDocument")) {
        return "Play failed: invalid local CSG layer. Check layers/local_csg.kdl.";
    }
    if (hasPlayOutput(stderr, stdout, "startup.loading_scene.fail")) {
        return "Play failed while loading the scene. Check the client log for the missing asset.";
    }
    if (hasPlayOutput(stderr, stdout, "startup.initializing_physics.fail")) {
        return "Play failed while initializing physics. Check scene colliders and physics settings.";
    }
    return "Play scene failed. Check the client log for the failing startup stage.";
}

fn hasPlayOutput(stderr: []const u8, stdout: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, stderr, needle) != null or std.mem.indexOf(u8, stdout, needle) != null;
}

fn tailText(text: []const u8, max_len: usize) []const u8 {
    if (text.len <= max_len) return text;
    return text[text.len - max_len ..];
}

test "formatProcessErrorDetail includes command exit code and output tails" {
    const detail = try formatProcessErrorDetail(
        std.testing.allocator,
        "Build failed",
        &.{ "zig", "build", "-Dbad option" },
        2,
        null,
        "compile error\nsecond line",
        "build summary",
        1024,
        1024,
    );
    defer std.testing.allocator.free(detail);

    try std.testing.expect(std.mem.indexOf(u8, detail, "Build failed") != null);
    try std.testing.expect(std.mem.indexOf(u8, detail, "zig build '-Dbad option'") != null);
    try std.testing.expect(std.mem.indexOf(u8, detail, "Exit code: 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, detail, "compile error") != null);
    try std.testing.expect(std.mem.indexOf(u8, detail, "build summary") != null);
}

pub fn setProjectStartupScene(state: *ProjectEditorState, scene_path: []const u8) !void {
    var config = try friendly_engine.modules.loadProjectConfigInProject(
        state.allocator,
        state.io,
        state.project_path,
        "engine.kdl",
    );
    defer config.deinit();
    const world_path = try config.worldForScene(scene_path);

    const engine_kdl = try friendly_engine.modules.formatProjectConfig(
        state.allocator,
        config.enabledModules(),
        scene_path,
        config.startupBundle(),
        config.sceneEntries(),
    );
    defer state.allocator.free(engine_kdl);

    var project_dir = try shared.scene_resolve.openProjectDir(state.io, state.project_path);
    defer project_dir.close(state.io);
    try project_dir.writeFile(state.io, .{ .sub_path = "engine.kdl", .data = engine_kdl });

    if (state.active_world_manifest_path_owned) state.allocator.free(state.active_world_manifest_path);
    state.active_world_manifest_path = try state.allocator.dupe(u8, world_path);
    state.active_world_manifest_path_owned = true;
    project_editor_state.setStatus(state, "Project startup scene set");
}

pub fn setPlayerStart(
    state: *ProjectEditorState,
    name: ?[]const u8,
    position: shared.editor_math.Vec3,
    yaw: f32,
    pitch: f32,
) ![]const u8 {
    const object_name = name orelse "Village Player Start";
    const existing_index = findObjectByName(state, object_name);

    project_editor_edit.pushUndoSnapshot(state);
    if (existing_index) |idx| {
        try ensurePlayerStartTarget(state, idx);
        var obj = &state.objects.items[idx];
        obj.position = position;
        obj.rotation = .{ .x = pitch, .y = yaw, .z = 0 };
        obj.scale = .{ .x = 1, .y = 1, .z = 1 };
        obj.object_kind = .empty;
        obj.renderer_visible = false;
        obj.cast_shadows = false;
        obj.receive_shadows = false;
        try replaceMeshAndTextureWithEmpty(state, obj);
        try replacePlayerStartMetadata(state, obj);
        state.selected_object = idx;
        state.scene_dirty = true;
        project_editor_state.setStatus(state, "Player start updated");
        return obj.name;
    }

    var mesh = try emptyMesh(state.allocator);
    errdefer mesh.deinit(state.allocator);
    const tex = try playerStartTexture(state.allocator);
    errdefer state.allocator.free(tex);
    const owned_name = try state.allocator.dupe(u8, object_name);
    errdefer state.allocator.free(owned_name);
    const components = try playerStartComponents(state.allocator);
    errdefer freeComponents(state.allocator, components);
    const gameplay_tag = try state.allocator.dupe(u8, player_start_tag);
    errdefer state.allocator.free(gameplay_tag);

    try state.objects.append(state.allocator, .{
        .id = state.next_object_id,
        .name = owned_name,
        .mesh = mesh,
        .position = position,
        .rotation = .{ .x = pitch, .y = yaw, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = tex,
        .base_color = .{ .r = 80, .g = 210, .b = 150, .a = 255 },
        .primitive_kind = null,
        .object_kind = .empty,
        .renderer_visible = false,
        .cast_shadows = false,
        .receive_shadows = false,
        .components = components,
        .physics = null,
        .gameplay = .{ .tag = gameplay_tag },
    });
    state.next_object_id += 1;
    state.selected_object = state.objects.items.len - 1;
    state.selected_vertex = null;
    state.selected_edge = null;
    state.selected_face = null;
    state.scene_dirty = true;
    project_editor_state.setStatus(state, "Player start created");
    return state.objects.items[state.selected_object.?].name;
}

fn findObjectByName(state: *const ProjectEditorState, name: []const u8) ?usize {
    for (state.objects.items, 0..) |obj, idx| {
        if (std.mem.eql(u8, obj.name, name)) return idx;
    }
    return null;
}

fn ensurePlayerStartTarget(state: *const ProjectEditorState, index: usize) !void {
    const obj = state.objects.items[index];
    if (obj.gameplay) |gameplay| {
        if (std.mem.eql(u8, gameplay.tag, player_start_tag)) return;
    }
    return error.InvalidPlayerStartTarget;
}

fn replaceMeshAndTextureWithEmpty(state: *ProjectEditorState, obj: *project_editor_state.SceneObject) !void {
    obj.mesh.deinit(state.allocator);
    obj.mesh = try emptyMesh(state.allocator);
    state.allocator.free(obj.texture);
    obj.texture = try playerStartTexture(state.allocator);
}

fn replacePlayerStartMetadata(state: *ProjectEditorState, obj: *project_editor_state.SceneObject) !void {
    for (obj.components) |component| state.allocator.free(component);
    state.allocator.free(obj.components);
    obj.components = try playerStartComponents(state.allocator);
    if (obj.gameplay) |*gameplay| gameplay.deinit(state.allocator);
    obj.gameplay = .{ .tag = try state.allocator.dupe(u8, player_start_tag) };
}

fn playerStartComponents(allocator: std.mem.Allocator) ![][]u8 {
    const components = try allocator.alloc([]u8, 2);
    errdefer allocator.free(components);
    components[0] = try allocator.dupe(u8, "spawner");
    errdefer allocator.free(components[0]);
    components[1] = try allocator.dupe(u8, fps_controller_component);
    return components;
}

fn freeComponents(allocator: std.mem.Allocator, components: [][]u8) void {
    for (components) |component| allocator.free(component);
    allocator.free(components);
}

fn emptyMesh(allocator: std.mem.Allocator) !geometry.Mesh {
    return .{
        .vertices = try allocator.alloc(geometry.Vertex, 0),
        .indices = try allocator.alloc(u32, 0),
    };
}

fn playerStartTexture(allocator: std.mem.Allocator) ![]u8 {
    const tex = try allocator.alloc(u8, editor_scene_object.TextureSize * editor_scene_object.TextureSize * 4);
    @memset(tex, 0);
    return tex;
}

test "play scene argv launches configured scene with startup world enabled" {
    var argv_buf: [6][]const u8 = undefined;
    var frame_arg: ?[]u8 = null;
    const argv = try playSceneArgv(std.testing.allocator, &argv_buf, "friendly_engine_client", "/tmp/project", shared.scene_io.default_scene_path, null, &frame_arg);
    defer if (frame_arg) |arg| std.testing.allocator.free(arg);
    try std.testing.expectEqualStrings("friendly_engine_client", argv[0]);
    try std.testing.expectEqualStrings("--project", argv[1]);
    try std.testing.expectEqualStrings("/tmp/project", argv[2]);
    try std.testing.expectEqualStrings("--startup-scene", argv[3]);
    try std.testing.expectEqualStrings("scenes/main.kdl", argv[4]);
}

test "play scene argv includes optional frame limit" {
    var argv_buf: [6][]const u8 = undefined;
    var frame_arg: ?[]u8 = null;
    const argv = try playSceneArgv(std.testing.allocator, &argv_buf, "friendly_engine_client", "/tmp/project", "scenes/arena.kdl", 5, &frame_arg);
    defer if (frame_arg) |arg| std.testing.allocator.free(arg);
    try std.testing.expectEqual(@as(usize, 6), argv.len);
    try std.testing.expectEqualStrings("--frames=5", argv[5]);
}
