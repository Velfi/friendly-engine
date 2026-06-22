const std = @import("std");
const shared = @import("runtime_shared");
const editor_core_ui = @import("editor_core_ui.zig");
const editor_draw = @import("editor_draw.zig");
const editor_viewport_gpu = @import("editor_viewport_gpu.zig");
const editor_command_file = @import("editor_command_file.zig");
const editor_control_server = @import("editor_control_server.zig");
const editor_commands_catalog = @import("editor_commands_catalog.zig");
const editor_commands_map_export = @import("editor_commands_map_export.zig");
const editor_commands_ocean_water = @import("editor_commands_ocean_water.zig");
const editor_commands_road_graph = @import("editor_commands_road_graph.zig");
const editor_commands_terrain_status = @import("editor_commands_terrain_status.zig");
const editor_commands_view_camera = @import("editor_commands_view_camera.zig");
const editor_commands_world_regions = @import("editor_commands_world_regions.zig");
const editor_commands_project_manager = @import("editor_commands_project_manager.zig");
const editor_commands_prop = @import("editor_commands_prop.zig");
const editor_commands_object = @import("editor_commands_object.zig");
const editor_commands_terrain_recipe_parse = @import("editor_commands_terrain_recipe_parse.zig");
const project_editor_concept_paint = @import("project_editor_concept_paint.zig");
const pm_presets = @import("pm_presets.zig");
const pm_state = @import("pm_state.zig");
const project_editor_command_dispatch = @import("project_editor_command_dispatch.zig");
const project_editor_blockout = @import("project_editor_blockout.zig");
const project_editor_build = @import("project_editor_build.zig");
const project_editor_edit = @import("project_editor_edit.zig");
const project_editor_architecture = @import("project_editor_architecture.zig");
const project_editor_scene = @import("project_editor_scene.zig");
const project_editor_view_nav = @import("project_editor_view_nav.zig");
const project_editor_world_authoring = @import("project_editor_world_authoring.zig");
const project_editor_world_authoring_manifest = @import("project_editor_world_authoring_manifest.zig");
const project_editor_world_authoring_ocean = @import("project_editor_world_authoring_ocean.zig");
const project_editor_world_authoring_terrain = @import("project_editor_world_authoring_terrain.zig");
const project_editor_world_authoring_terrain_batch = @import("project_editor_world_authoring_terrain_batch.zig");
const project_editor_world_authoring_terrain_edge = @import("project_editor_world_authoring_terrain_edge.zig");
const project_editor_world_authoring_terrain_recipe = @import("project_editor_world_authoring_terrain_recipe.zig");
const project_editor_world_authoring_terrain_stretch_smooth = @import("project_editor_world_authoring_terrain_stretch_smooth.zig");
const project_editor_world_authoring_heightmap_batch = @import("project_editor_world_authoring_heightmap_batch.zig");
const project_editor_terrain_undo_store = @import("project_editor_terrain_undo_store.zig");
const project_editor_terrain_preview = @import("project_editor_terrain_preview.zig");
const editor_scene_object = @import("editor_scene_object.zig");
const editor_scene_hierarchy = @import("editor_scene_hierarchy.zig");
const project_editor_spline_targets = @import("project_editor_spline_targets.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_types = @import("project_editor_types.zig");
const project_editor_modes = @import("project_editor_modes.zig");
const shape_operation = @import("shape_operation.zig");
const shape_source = @import("shape_source.zig");

const editor_math = shared.editor_math;
const arch = shared.architecture;
const geometry = shared.geometry;
const prop_asset_doc = shared.prop_asset_doc;
const scene_marker = shared.scene_marker;
const sdl = shared.sdl;
const friendly_engine = @import("friendly_engine");
const time = friendly_engine.core.time;
const ProjectEditorState = project_editor_state.ProjectEditorState;
const SceneObject = project_editor_state.SceneObject;
pub const CommandFile = editor_command_file.CommandFile;
pub const ControlRequest = editor_control_server.ControlRequest;
pub const ControlStats = editor_control_server.ControlStats;
pub const ControlServer = editor_control_server.ControlServer;

pub const control_port = editor_control_server.control_port;
const command_root = ".friendly-engine/editor-control";
const screenshot_dir = command_root ++ "/screenshots";
const turntable_dir = command_root ++ "/turntables";
const export_dir = command_root ++ "/exports";
const max_command_bytes = editor_control_server.max_command_bytes;
const control_request_budget_ns: i128 = 2 * std.time.ns_per_ms;

pub const PendingScreenshot = struct {
    id: []u8,
    command_name: []u8,
    project_path: []u8,
    absolute_path: []u8,
    crop: ?sdl.SDL_Rect = null,
    clean_viewport: bool = false,
    command_start_camera: ?editor_math.OrbitCamera = null,
    control_request: ?*ControlRequest = null,
    control_server: ?*ControlServer = null,

    pub fn deinit(self: *PendingScreenshot, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.command_name);
        allocator.free(self.project_path);
        allocator.free(self.absolute_path);
        self.* = undefined;
    }
};

pub const PendingTurntableCapture = struct {
    id: []u8,
    command_name: []u8,
    object_name: []u8,
    project_path: []u8,
    project_name: []u8,
    output_dir: []u8,
    manifest_path: []u8,
    encoded_path: []u8,
    format: []u8,
    frame_paths: std.ArrayList([]u8),
    frame_index: u32 = 0,
    frame_count: u32,
    fps: u32,
    original_camera: editor_math.OrbitCamera,
    target: editor_math.Vec3,
    radius: f32,
    pitch: f32,
    start_yaw: f32,
    control_request: ?*ControlRequest = null,
    control_server: ?*ControlServer = null,

    pub fn deinit(self: *PendingTurntableCapture, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.command_name);
        allocator.free(self.object_name);
        allocator.free(self.project_path);
        allocator.free(self.project_name);
        allocator.free(self.output_dir);
        allocator.free(self.manifest_path);
        allocator.free(self.encoded_path);
        allocator.free(self.format);
        for (self.frame_paths.items) |path| allocator.free(path);
        self.frame_paths.deinit(allocator);
        self.* = undefined;
    }
};

const ProcessContext = struct {
    project_path: []const u8,
    project_name: []const u8,
    editor_state: ?*ProjectEditorState,
    project_manager: ?*pm_state.ProjectManagerState,
    renderer: *editor_draw.SDL_Renderer,
    viewport_gpu: *const editor_viewport_gpu.EditorViewportGpu,
    host: *editor_core_ui.Host,
    pending_screenshot: *?PendingScreenshot,
    pending_turntable: ?*?PendingTurntableCapture,
    control_server: ?*ControlServer,
};

pub fn ensureProjectDirs(io: std.Io, project_path: []const u8) !void {
    try makeProjectPath(io, project_path, command_root);
    try makeProjectPath(io, project_path, screenshot_dir);
    try makeProjectPath(io, project_path, turntable_dir);
    try makeProjectPath(io, project_path, export_dir);
}

pub fn processPending(
    allocator: std.mem.Allocator,
    io: std.Io,
    control_server: *ControlServer,
    state: *ProjectEditorState,
    renderer: *editor_draw.SDL_Renderer,
    viewport_gpu: *const editor_viewport_gpu.EditorViewportGpu,
    host: *editor_core_ui.Host,
    pending_screenshot: *?PendingScreenshot,
    pending_turntable: *?PendingTurntableCapture,
) !void {
    try processPendingControl(allocator, io, control_server, state.project_path, state.project_name, state, null, renderer, viewport_gpu, host, pending_screenshot, pending_turntable);
}

pub fn processPendingWorkspace(
    allocator: std.mem.Allocator,
    io: std.Io,
    control_server: *ControlServer,
    project_path: []const u8,
    project_name: []const u8,
    renderer: *editor_draw.SDL_Renderer,
    viewport_gpu: *const editor_viewport_gpu.EditorViewportGpu,
    host: *editor_core_ui.Host,
    pending_screenshot: *?PendingScreenshot,
) !void {
    try processPendingControl(allocator, io, control_server, project_path, project_name, null, null, renderer, viewport_gpu, host, pending_screenshot, null);
}

pub fn processPendingProjectManager(
    allocator: std.mem.Allocator,
    io: std.Io,
    control_server: *ControlServer,
    project_manager: *pm_state.ProjectManagerState,
    project_path: []const u8,
    project_name: []const u8,
    renderer: *editor_draw.SDL_Renderer,
    viewport_gpu: *const editor_viewport_gpu.EditorViewportGpu,
    host: *editor_core_ui.Host,
    pending_screenshot: *?PendingScreenshot,
) !void {
    try processPendingControl(allocator, io, control_server, project_path, project_name, null, project_manager, renderer, viewport_gpu, host, pending_screenshot, null);
}

fn processPendingControl(
    allocator: std.mem.Allocator,
    io: std.Io,
    control_server: *ControlServer,
    project_path: []const u8,
    project_name: []const u8,
    editor_state: ?*ProjectEditorState,
    project_manager: ?*pm_state.ProjectManagerState,
    renderer: *editor_draw.SDL_Renderer,
    viewport_gpu: *const editor_viewport_gpu.EditorViewportGpu,
    host: *editor_core_ui.Host,
    pending_screenshot: *?PendingScreenshot,
    pending_turntable: ?*?PendingTurntableCapture,
) !void {
    try ensureProjectDirs(io, project_path);
    const ctx = ProcessContext{
        .project_path = project_path,
        .project_name = project_name,
        .editor_state = editor_state,
        .project_manager = project_manager,
        .renderer = renderer,
        .viewport_gpu = viewport_gpu,
        .host = host,
        .pending_screenshot = pending_screenshot,
        .pending_turntable = pending_turntable,
        .control_server = control_server,
    };
    const started_ns = time.monotonicNs();
    const drain_all = control_server.takeDrainAllFrame();
    var processed: u32 = 0;
    while (true) {
        control_server.mutex.lockUncancelable(control_server.io);
        const request = control_server.popRequest() orelse {
            control_server.mutex.unlock(control_server.io);
            return;
        };
        control_server.mutex.unlock(control_server.io);
        try processOne(allocator, io, ctx, request);
        processed += 1;
        if (!drain_all and processed > 0 and time.monotonicNs() - started_ns >= control_request_budget_ns) {
            return;
        }
    }
}

pub fn completePendingScreenshot(
    allocator: std.mem.Allocator,
    io: std.Io,
    renderer: *editor_draw.SDL_Renderer,
    gpu: ?*shared.gpu_api.GpuRenderer,
    use_gpu: bool,
    pending_slot: *?PendingScreenshot,
) !void {
    var pending = pending_slot.* orelse return;
    pending_slot.* = null;
    defer pending.deinit(allocator);
    const result = try captureScreenshot(
        allocator,
        io,
        renderer,
        gpu,
        use_gpu,
        pending.project_path,
        pending.absolute_path,
        pending.crop,
        pending.command_name,
    );
    if (pending.control_request) |request| {
        completeControlRequest(pending.control_server orelse return error.EditorControlServerMissing, request, result);
    } else {
        allocator.free(result);
    }
}

pub fn completePendingTurntableCapture(
    allocator: std.mem.Allocator,
    io: std.Io,
    renderer: *editor_draw.SDL_Renderer,
    gpu: ?*shared.gpu_api.GpuRenderer,
    use_gpu: bool,
    state: *ProjectEditorState,
    pending_slot: *?PendingTurntableCapture,
) !void {
    var pending = pending_slot.* orelse return;
    const frame_path = try turntableFramePath(allocator, pending.output_dir, pending.frame_index);
    errdefer allocator.free(frame_path);
    try captureFrameToPath(
        allocator,
        renderer,
        gpu,
        use_gpu,
        frame_path,
        screenshotCrop("screenshot-viewport", state),
    );
    try pending.frame_paths.append(allocator, frame_path);
    pending.frame_index += 1;

    if (pending.frame_index >= pending.frame_count) {
        state.camera = pending.original_camera;
        try encodeTurntable(allocator, io, &pending);
        const result = try writeTurntableManifest(allocator, io, &pending);
        if (pending.control_request) |request| {
            completeControlRequest(pending.control_server orelse return error.EditorControlServerMissing, request, result);
        } else {
            allocator.free(result);
        }
        pending_slot.* = null;
        pending.deinit(allocator);
        return;
    }

    applyTurntableCamera(state, &pending);
    pending_slot.* = pending;
}

fn processOne(
    allocator: std.mem.Allocator,
    io: std.Io,
    ctx: ProcessContext,
    request: *ControlRequest,
) !void {
    if (request.bytes.len > max_command_bytes) {
        const result = try std.fmt.allocPrint(allocator, "{{\"ok\":false,\"error\":\"EditorControlRequestTooLarge\"}}\n", .{});
        completeControlRequest(ctx.control_server orelse return error.EditorControlServerMissing, request, result);
        return;
    }

    var parsed = std.json.parseFromSlice(CommandFile, allocator, request.bytes, .{ .ignore_unknown_fields = true }) catch |err| {
        const result = try std.fmt.allocPrint(allocator, "{{\"ok\":false,\"error\":\"{s}\"}}\n", .{@errorName(err)});
        completeControlRequest(ctx.control_server orelse return error.EditorControlServerMissing, request, result);
        return;
    };
    defer parsed.deinit();

    if (std.mem.eql(u8, parsed.value.name, "map.top-down-capture")) {
        const editor_state = ctx.editor_state orelse {
            const result = try std.fmt.allocPrint(allocator, "{{\"ok\":false,\"id\":\"{s}\",\"command\":\"{s}\",\"error\":\"EditorStateRequired\"}}\n", .{ parsed.value.id, parsed.value.name });
            completeControlRequest(ctx.control_server orelse return error.EditorControlServerMissing, request, result);
            return;
        };
        try editor_commands_map_export.frameWorldTopDown(editor_state);
        if (ctx.pending_screenshot.*) |*pending| pending.deinit(allocator);
        ctx.pending_screenshot.* = try enqueueScreenshot(
            allocator,
            io,
            ctx.project_path,
            ctx.project_name,
            parsed.value,
            screenshotCrop(parsed.value.name, ctx.editor_state),
            ctx.editor_state,
            request,
            ctx.control_server,
        );
        return;
    }

    if (isDeferredScreenshot(parsed.value.name, ctx.editor_state)) {
        if (ctx.pending_screenshot.*) |*pending| pending.deinit(allocator);
        ctx.pending_screenshot.* = try enqueueScreenshot(
            allocator,
            io,
            ctx.project_path,
            ctx.project_name,
            parsed.value,
            screenshotCrop(parsed.value.name, ctx.editor_state),
            ctx.editor_state,
            request,
            ctx.control_server,
        );
        return;
    }

    if (std.mem.eql(u8, parsed.value.name, "turntable-capture")) {
        const editor_state = ctx.editor_state orelse {
            const result = try std.fmt.allocPrint(allocator, "{{\"ok\":false,\"id\":\"{s}\",\"command\":\"{s}\",\"error\":\"EditorStateRequired\"}}\n", .{ parsed.value.id, parsed.value.name });
            completeControlRequest(ctx.control_server orelse return error.EditorControlServerMissing, request, result);
            return;
        };
        const pending_slot = ctx.pending_turntable orelse {
            const result = try std.fmt.allocPrint(allocator, "{{\"ok\":false,\"id\":\"{s}\",\"command\":\"{s}\",\"error\":\"TurntableCaptureUnavailable\"}}\n", .{ parsed.value.id, parsed.value.name });
            completeControlRequest(ctx.control_server orelse return error.EditorControlServerMissing, request, result);
            return;
        };
        if (pending_slot.*) |*pending| pending.deinit(allocator);
        pending_slot.* = try enqueueTurntableCapture(
            allocator,
            io,
            editor_state,
            parsed.value,
            request,
            ctx.control_server,
        );
        return;
    }

    if (ctx.editor_state) |editor_state| editor_commands_view_camera.applyShowMeHint(editor_state, parsed.value);

    const control_stats = if (ctx.control_server) |server| server.statsSnapshot() else ControlStats{};
    const result = executeCommand(allocator, io, ctx.project_path, ctx.project_name, ctx.editor_state, ctx.project_manager, ctx.renderer, ctx.viewport_gpu, ctx.host, control_stats, parsed.value) catch |err|
        try std.fmt.allocPrint(allocator, "{{\"ok\":false,\"id\":\"{s}\",\"command\":\"{s}\",\"error\":\"{s}\"}}\n", .{
            parsed.value.id,
            parsed.value.name,
            @errorName(err),
        });
    completeControlRequest(ctx.control_server orelse return error.EditorControlServerMissing, request, result);
}

fn isDeferredScreenshot(command_name: []const u8, editor_state: ?*ProjectEditorState) bool {
    if (std.mem.eql(u8, command_name, "screenshot-editor")) return true;
    return (std.mem.eql(u8, command_name, "screenshot-viewport") or
        std.mem.eql(u8, command_name, "screenshot-viewport-clean") or
        std.mem.eql(u8, command_name, "map.top-down-capture")) and editor_state != null;
}

fn screenshotCrop(command_name: []const u8, editor_state: ?*ProjectEditorState) ?sdl.SDL_Rect {
    if (!std.mem.eql(u8, command_name, "screenshot-viewport") and
        !std.mem.eql(u8, command_name, "screenshot-viewport-clean") and
        !std.mem.eql(u8, command_name, "map.top-down-capture")) return null;
    const state = editor_state orelse return null;
    return scaledSdlRectFromFRect(state.viewport_screen_rect, state.display_scale);
}

fn enqueueScreenshot(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    project_name: []const u8,
    command: CommandFile,
    crop: ?sdl.SDL_Rect,
    editor_state: ?*ProjectEditorState,
    request: ?*ControlRequest,
    control_server: ?*ControlServer,
) !PendingScreenshot {
    const absolute_path = try screenshotAbsolutePath(allocator, io, project_path, project_name, command.id);
    const clean_viewport = std.mem.eql(u8, command.name, "screenshot-viewport-clean");
    return .{
        .id = try allocator.dupe(u8, command.id),
        .command_name = try allocator.dupe(u8, command.name),
        .project_path = try allocator.dupe(u8, project_path),
        .absolute_path = absolute_path,
        .crop = crop,
        .clean_viewport = clean_viewport,
        .command_start_camera = if (clean_viewport) (editor_state orelse return error.EditorStateRequired).camera else null,
        .control_request = request,
        .control_server = control_server,
    };
}

fn completeControlRequest(
    control_server: *ControlServer,
    request: *ControlRequest,
    result: []u8,
) void {
    control_server.mutex.lockUncancelable(control_server.io);
    defer control_server.mutex.unlock(control_server.io);
    request.result = result;
    request.done = true;
    if (control_server.active_count > 0) control_server.active_count -= 1;
    control_server.executed_count += 1;
    request.condition.signal(control_server.io);
}

fn screenshotAbsolutePath(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    project_name: []const u8,
    command_id: []const u8,
) ![]u8 {
    try ensureProjectDirs(io, project_path);
    const project_dir_name = try sanitizedProjectName(allocator, project_name);
    defer allocator.free(project_dir_name);
    const project_screenshot_dir = try std.fs.path.join(allocator, &.{ screenshot_dir, project_dir_name });
    defer allocator.free(project_screenshot_dir);
    try makeProjectPath(io, project_path, project_screenshot_dir);

    const file_name = try std.fmt.allocPrint(allocator, "{s}.png", .{command_id});
    defer allocator.free(file_name);
    const rel_path = try std.fs.path.join(allocator, &.{ project_screenshot_dir, file_name });
    defer allocator.free(rel_path);
    return std.fs.path.join(allocator, &.{ project_path, rel_path });
}

fn captureScreenshot(
    allocator: std.mem.Allocator,
    io: std.Io,
    renderer: *editor_draw.SDL_Renderer,
    gpu: ?*shared.gpu_api.GpuRenderer,
    use_gpu: bool,
    project_path: []const u8,
    absolute_path: []const u8,
    crop: ?sdl.SDL_Rect,
    command_name: []const u8,
) ![]u8 {
    _ = project_path;
    _ = io;
    try captureFrameToPath(allocator, renderer, gpu, use_gpu, absolute_path, crop);

    const command_id = std.fs.path.basename(absolute_path);
    const id_without_ext = command_id[0 .. command_id.len - 4];
    return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"path\":\"{s}\"}}\n", .{
        id_without_ext,
        command_name,
        absolute_path,
    });
}

fn captureFrameToPath(
    allocator: std.mem.Allocator,
    renderer: *editor_draw.SDL_Renderer,
    gpu: ?*shared.gpu_api.GpuRenderer,
    use_gpu: bool,
    absolute_path: []const u8,
    crop: ?sdl.SDL_Rect,
) !void {
    const absolute_path_z = try allocator.dupeZ(u8, absolute_path);
    defer allocator.free(absolute_path_z);

    if (use_gpu) {
        const gpu_renderer = gpu orelse return error.GpuRendererUnavailable;
        var output_w: c_int = 0;
        var output_h: c_int = 0;
        if (!editor_draw.SDL_GetRenderOutputSize(renderer, &output_w, &output_h)) return error.SdlRenderOutputSizeFailed;
        const pixel_count = @as(usize, @intCast(@max(1, output_w))) * @as(usize, @intCast(@max(1, output_h))) * 4;
        const pixels = try allocator.alloc(u8, pixel_count);
        defer allocator.free(pixels);
        try gpu_renderer.capturePresentedFrameAndEndFrame(pixels);
        try saveRgbaPng(allocator, pixels, @intCast(output_w), @intCast(output_h), crop, absolute_path_z.ptr);
    } else {
        const surface = sdl.SDL_RenderReadPixels(renderer, if (crop) |rect| &rect else null) orelse return error.SdlRenderReadPixelsFailed;
        defer sdl.SDL_DestroySurface(surface);
        if (!sdl.SDL_SavePNG(surface, absolute_path_z.ptr)) return error.SdlSavePngFailed;
    }
}

fn saveRgbaPng(
    allocator: std.mem.Allocator,
    pixels: []const u8,
    width: u32,
    height: u32,
    crop: ?sdl.SDL_Rect,
    path: [*:0]const u8,
) !void {
    if (crop) |rect| {
        if (rect.w <= 0 or rect.h <= 0) return error.InvalidScreenshotCrop;
        var cropped = try allocator.alloc(u8, @as(usize, @intCast(rect.w)) * @as(usize, @intCast(rect.h)) * 4);
        defer allocator.free(cropped);
        const src_w: usize = @intCast(width);
        const src_x: usize = @intCast(@max(0, rect.x));
        const src_y: usize = @intCast(@max(0, rect.y));
        const copy_w: usize = @intCast(rect.w);
        const copy_h: usize = @intCast(rect.h);
        var row: usize = 0;
        while (row < copy_h) : (row += 1) {
            const src = ((src_y + row) * src_w + src_x) * 4;
            const dst = row * copy_w * 4;
            @memcpy(cropped[dst .. dst + copy_w * 4], pixels[src .. src + copy_w * 4]);
        }
        const surface = sdl.SDL_CreateSurfaceFrom(@intCast(rect.w), @intCast(rect.h), sdl.SDL_PIXELFORMAT_RGBA32, cropped.ptr, @intCast(rect.w * 4)) orelse return error.SdlSurfaceCreateFailed;
        defer sdl.SDL_DestroySurface(surface);
        if (!sdl.SDL_SavePNG(surface, path)) return error.SdlSavePngFailed;
        return;
    }

    const surface = sdl.SDL_CreateSurfaceFrom(@intCast(width), @intCast(height), sdl.SDL_PIXELFORMAT_RGBA32, @constCast(pixels.ptr), @intCast(width * 4)) orelse return error.SdlSurfaceCreateFailed;
    defer sdl.SDL_DestroySurface(surface);
    if (!sdl.SDL_SavePNG(surface, path)) return error.SdlSavePngFailed;
}

fn executeCommand(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    project_name: []const u8,
    state: ?*ProjectEditorState,
    project_manager: ?*pm_state.ProjectManagerState,
    renderer: *editor_draw.SDL_Renderer,
    viewport_gpu: *const editor_viewport_gpu.EditorViewportGpu,
    host: *editor_core_ui.Host,
    control_stats: ControlStats,
    command: CommandFile,
) ![]u8 {
    if (editor_commands_project_manager.handles(command.name)) {
        return editor_commands_project_manager.execute(allocator, command, state != null, project_manager);
    }
    if (std.mem.eql(u8, command.name, "perf.describe")) {
        const editor_state = state orelse return error.EditorStateRequired;
        const ctx = project_editor_state.perfSnapshotContext(editor_state, @intCast(host.ui.renderCommands().len), viewport_gpu, control_stats);
        return editor_state.frame_perf.describeJson(allocator, ctx);
    }
    if (std.mem.eql(u8, command.name, "editor.describe")) {
        const editor_state = state orelse return error.EditorStateRequired;
        return describeEditorState(allocator, command, editor_state, host, viewport_gpu, control_stats);
    }
    if (std.mem.eql(u8, command.name, "objects.list")) {
        const editor_state = state orelse return error.EditorStateRequired;
        return describeObjects(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "terrain.footprint-list")) {
        const editor_state = state orelse return error.EditorStateRequired;
        return describeTerrainFootprint(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "terrain.heightmap-export")) {
        const editor_state = state orelse return error.EditorStateRequired;
        return editor_commands_map_export.exportTerrainHeightmap(allocator, io, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "commands.list")) {
        return editor_commands_catalog.describeCommands(allocator, command, state, project_manager);
    }
    if (std.mem.eql(u8, command.name, "commands.scene-map")) {
        return editor_commands_catalog.describeSceneMap(allocator, command, state, project_manager);
    }
    if (state) |editor_state| {
        try requireModeForMcpCommand(editor_state, command.name);
    }
    if (std.mem.eql(u8, command.name, "undo.batch-begin")) {
        const editor_state = state orelse return error.EditorStateRequired;
        project_editor_edit.beginUndoBatch(editor_state, command.label orelse command.object orelse "LLM action");
        return undoBatchStatusJson(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "undo.batch-end")) {
        const editor_state = state orelse return error.EditorStateRequired;
        project_editor_edit.endUndoBatch(editor_state);
        return undoBatchStatusJson(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "undo.batch-cancel")) {
        const editor_state = state orelse return error.EditorStateRequired;
        project_editor_edit.cancelUndoBatch(editor_state);
        return undoBatchStatusJson(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "world.sky-toggle")) {
        const editor_state = state orelse return error.EditorStateRequired;
        editor_state.world_sky_visible = !editor_state.world_sky_visible;
        project_editor_state.setStatus(editor_state, if (editor_state.world_sky_visible) "Sky on" else "Sky off");
        return describeEditorState(allocator, command, editor_state, host, viewport_gpu, control_stats);
    }
    if (std.mem.eql(u8, command.name, "world.ocean-toggle")) {
        const editor_state = state orelse return error.EditorStateRequired;
        editor_state.world_ocean_visible = !editor_state.world_ocean_visible;
        project_editor_world_authoring_ocean.persistFromState(editor_state) catch {};
        project_editor_state.setStatus(editor_state, if (editor_state.world_ocean_visible) "Ocean on" else "Ocean off");
        return describeEditorState(allocator, command, editor_state, host, viewport_gpu, control_stats);
    }
    if (std.mem.eql(u8, command.name, "world.region-list")) {
        const editor_state = state orelse return error.EditorStateRequired;
        return editor_commands_world_regions.describe(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "world.region-upsert")) {
        const editor_state = state orelse return error.EditorStateRequired;
        return editor_commands_world_regions.upsert(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "world.region-paint")) {
        const editor_state = state orelse return error.EditorStateRequired;
        return editor_commands_world_regions.paint(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "world.region-delete")) {
        const editor_state = state orelse return error.EditorStateRequired;
        return editor_commands_world_regions.delete(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "ocean.clip-list") or std.mem.eql(u8, command.name, "ocean.exclusion-list")) {
        const editor_state = state orelse return error.EditorStateRequired;
        return editor_commands_ocean_water.listOceanClip(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "ocean.clip-update") or std.mem.eql(u8, command.name, "ocean.exclusion-update")) {
        const editor_state = state orelse return error.EditorStateRequired;
        return editor_commands_ocean_water.updateOceanClip(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "ocean.clip-point-add") or std.mem.eql(u8, command.name, "ocean.exclusion-point-add")) {
        const editor_state = state orelse return error.EditorStateRequired;
        return editor_commands_ocean_water.mutateOceanClipPoint(allocator, command, editor_state, .add);
    }
    if (std.mem.eql(u8, command.name, "ocean.clip-point-move-nearest") or std.mem.eql(u8, command.name, "ocean.exclusion-point-move-nearest")) {
        const editor_state = state orelse return error.EditorStateRequired;
        return editor_commands_ocean_water.mutateOceanClipPoint(allocator, command, editor_state, .move_nearest);
    }
    if (std.mem.eql(u8, command.name, "ocean.clip-point-delete-nearest") or std.mem.eql(u8, command.name, "ocean.exclusion-point-delete-nearest")) {
        const editor_state = state orelse return error.EditorStateRequired;
        return editor_commands_ocean_water.mutateOceanClipPoint(allocator, command, editor_state, .delete_nearest);
    }
    if (std.mem.eql(u8, command.name, "water.volume-list")) {
        const editor_state = state orelse return error.EditorStateRequired;
        return editor_commands_ocean_water.listWaterVolumes(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "water.volume-create") or std.mem.eql(u8, command.name, "water.volume-update")) {
        const editor_state = state orelse return error.EditorStateRequired;
        return editor_commands_ocean_water.upsertWaterVolume(allocator, command, editor_state, std.mem.eql(u8, command.name, "water.volume-create"));
    }
    if (std.mem.eql(u8, command.name, "water.volume-delete")) {
        const editor_state = state orelse return error.EditorStateRequired;
        return editor_commands_ocean_water.deleteWaterVolume(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "water.query-point")) {
        const editor_state = state orelse return error.EditorStateRequired;
        return editor_commands_ocean_water.queryWaterPoint(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "plot.create")) {
        const editor_state = state orelse return error.EditorStateRequired;
        return createPlotRoot(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "plot.align-to-terrain")) {
        const editor_state = state orelse return error.EditorStateRequired;
        return alignPlotsToTerrain(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "scene.new-architecture")) {
        const editor_state = state orelse return error.EditorStateRequired;
        const scene_path = command.path orelse "scenes/architecture.kdl";
        try createNewArchitectureScene(editor_state, scene_path);
        return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"scene\":\"{s}\",\"mode\":\"architecture_creation\",\"objects\":{d},\"status\":\"New architecture scene ready\"}}\n", .{
            command.id,
            command.name,
            editor_state.active_scene_path,
            editor_state.objects.items.len,
        });
    }
    if (std.mem.eql(u8, command.name, "object.select")) {
        const editor_state = state orelse return error.EditorStateRequired;
        const idx = try findObjectIndex(editor_state, command.object orelse return error.MissingObject);
        selectObject(editor_state, idx);
        return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"object\":\"{s}\",\"object_id\":{d}}}\n", .{
            command.id,
            command.name,
            editor_state.objects.items[idx].name,
            editor_state.objects.items[idx].id,
        });
    }
    if (std.mem.eql(u8, command.name, "object.parent-set")) {
        const editor_state = state orelse return error.EditorStateRequired;
        return editor_commands_object.setParent(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "object.properties-set")) {
        const editor_state = state orelse return error.EditorStateRequired;
        return editor_commands_object.setProperties(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "object.gameplay-set")) {
        const editor_state = state orelse return error.EditorStateRequired;
        return editor_commands_object.setGameplay(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "selection.scope-set")) {
        const editor_state = state orelse return error.EditorStateRequired;
        const scope_name = command.scope orelse return error.MissingSelectionScope;
        const scope = selectionScopeFromName(scope_name) orelse return error.InvalidSelectionScope;
        project_editor_scene.setSelectionScope(editor_state, scope);
        return describeEditorState(allocator, command, editor_state, host, viewport_gpu, control_stats);
    }
    if (std.mem.eql(u8, command.name, "selection.scope-cycle")) {
        const editor_state = state orelse return error.EditorStateRequired;
        project_editor_scene.cycleSelectionScope(editor_state);
        return describeEditorState(allocator, command, editor_state, host, viewport_gpu, control_stats);
    }
    if (std.mem.eql(u8, command.name, "selection.pick")) {
        const editor_state = state orelse return error.EditorStateRequired;
        const x = command.screen_x orelse return error.MissingScreenPoint;
        const y = command.screen_y orelse return error.MissingScreenPoint;
        try pickViewportLocal(editor_state, x, y);
        return describeEditorState(allocator, command, editor_state, host, viewport_gpu, control_stats);
    }
    if (std.mem.eql(u8, command.name, "selection.box-select")) {
        const editor_state = state orelse return error.EditorStateRequired;
        const start_x = command.screen_x orelse return error.MissingScreenPoint;
        const start_y = command.screen_y orelse return error.MissingScreenPoint;
        const end_x = command.end_x orelse return error.MissingScreenPoint;
        const end_y = command.end_y orelse return error.MissingScreenPoint;
        try boxSelectViewportLocal(editor_state, start_x, start_y, end_x, end_y);
        return describeEditorState(allocator, command, editor_state, host, viewport_gpu, control_stats);
    }
    if (std.mem.eql(u8, command.name, "selection.pick-world")) {
        const editor_state = state orelse return error.EditorStateRequired;
        const world = shared.editor_math.Vec3{
            .x = command.point_x orelse return error.MissingPoint,
            .y = command.point_y orelse return error.MissingPoint,
            .z = command.point_z orelse return error.MissingPoint,
        };
        const screen = project_editor_state.projectViewportPoint(editor_state, world, editor_state.viewport_screen_rect.w, editor_state.viewport_screen_rect.h) orelse return error.WorldPointOutsideViewport;
        try pickViewportLocal(editor_state, screen.x, screen.y);
        return describeEditorState(allocator, command, editor_state, host, viewport_gpu, control_stats);
    }
    if (std.mem.eql(u8, command.name, "marker.create")) {
        const editor_state = state orelse return error.EditorStateRequired;
        return createGameplayMarker(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "marker.update")) {
        const editor_state = state orelse return error.EditorStateRequired;
        return updateGameplayMarker(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "object.clear-selection")) {
        const editor_state = state orelse return error.EditorStateRequired;
        editor_state.selected_object = null;
        editor_state.selected_vertex = null;
        editor_state.selected_edge = null;
        editor_state.selected_face = null;
        editor_state.selected_shape_source = false;
        editor_state.selected_shape_operation = false;
        project_editor_state.setStatus(editor_state, "Selection cleared");
        return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"status\":\"Selection cleared\"}}\n", .{
            command.id,
            command.name,
        });
    }
    if (std.mem.eql(u8, command.name, "command.run")) {
        const editor_state = state orelse return error.EditorStateRequired;
        const command_id = command.command orelse return error.MissingCommand;
        try project_editor_command_dispatch.executeCommandId(editor_state, command_id);
        return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"ran\":\"{s}\"}}\n", .{
            command.id,
            command.name,
            command_id,
        });
    }
    if (std.mem.eql(u8, command.name, "view.set")) {
        const editor_state = state orelse return error.EditorStateRequired;
        try editor_commands_view_camera.applyViewCommand(editor_state, command);
        return describeEditorState(allocator, command, editor_state, host, viewport_gpu, control_stats);
    }
    if (std.mem.eql(u8, command.name, "camera.set")) {
        const editor_state = state orelse return error.EditorStateRequired;
        try editor_commands_view_camera.applyCameraCommand(editor_state, command);
        return describeEditorState(allocator, command, editor_state, host, viewport_gpu, control_stats);
    }
    if (std.mem.eql(u8, command.name, "show-me")) {
        const editor_state = state orelse return error.EditorStateRequired;
        try editor_commands_view_camera.applyShowMeCommand(editor_state, command);
        return describeEditorState(allocator, command, editor_state, host, viewport_gpu, control_stats);
    }
    if (std.mem.eql(u8, command.name, "camera.preset")) {
        const editor_state = state orelse return error.EditorStateRequired;
        try editor_commands_view_camera.applyCameraPreset(editor_state, command.object orelse return error.MissingObject);
        return describeEditorState(allocator, command, editor_state, host, viewport_gpu, control_stats);
    }
    if (std.mem.eql(u8, command.name, "camera.random-angle")) {
        const editor_state = state orelse return error.EditorStateRequired;
        try editor_commands_view_camera.applyRandomCameraAngle(editor_state, command.seed);
        return describeEditorState(allocator, command, editor_state, host, viewport_gpu, control_stats);
    }
    if (std.mem.eql(u8, command.name, "architecture.building-create")) {
        const editor_state = state orelse return error.EditorStateRequired;
        editor_state.mode = .architecture_creation;
        return createPlotLocalBuilding(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "architecture.wall-point")) {
        const editor_state = state orelse return error.EditorStateRequired;
        const x = command.point_x orelse return error.MissingPoint;
        const z = command.point_z orelse return error.MissingPoint;
        editor_state.mode = .architecture_creation;
        editor_state.architecture_tool = .wall;
        try project_editor_blockout.placeWallOutlinePointAt(editor_state, .{ .x = x, .y = command.point_y orelse 0, .z = z });
        var out = try std.ArrayList(u8).initCapacity(allocator, 256);
        defer out.deinit(allocator);
        try appendFmt(allocator, &out, "{{\"ok\":true,\"id\":", .{});
        try appendJsonString(allocator, &out, command.id);
        try appendFmt(allocator, &out, ",\"command\":", .{});
        try appendJsonString(allocator, &out, command.name);
        try appendFmt(allocator, &out, ",\"point\":{{\"x\":{d:.6},\"y\":{d:.6},\"z\":{d:.6}}},\"wall_points\":{d},\"objects\":{d},\"status\":", .{
            x,
            command.point_y orelse 0,
            z,
            editor_state.wall_outline_points.items.len,
            editor_state.objects.items.len,
        });
        try appendJsonString(allocator, &out, editor_state.status_buf[0..editor_state.status_len]);
        try appendFmt(allocator, &out, "}}\n", .{});
        return out.toOwnedSlice(allocator);
    }
    if (std.mem.eql(u8, command.name, "architecture.door-cut") or std.mem.eql(u8, command.name, "architecture.window-cut")) {
        const editor_state = state orelse return error.EditorStateRequired;
        const x = command.point_x orelse return error.MissingPoint;
        const z = command.point_z orelse return error.MissingPoint;
        const end_x = command.end_x orelse return error.MissingPoint;
        const end_z = command.end_z orelse return error.MissingPoint;
        editor_state.mode = .architecture_creation;
        if (project_editor_architecture.selectedBuildingIndex(editor_state)) |idx| {
            project_editor_architecture.setActiveBuilding(editor_state, editor_state.objects.items[idx].id);
        }
        if (std.mem.eql(u8, command.name, "architecture.door-cut")) {
            editor_state.architecture_tool = .door;
            try project_editor_blockout.cutDoorOpeningAtPoints(
                editor_state,
                .{ .x = x, .y = command.point_y orelse 0, .z = z },
                .{ .x = end_x, .y = command.end_y orelse 0, .z = end_z },
            );
        } else {
            editor_state.architecture_tool = .window;
            try project_editor_blockout.cutWindowOpeningAtPoints(
                editor_state,
                .{ .x = x, .y = command.point_y orelse 0, .z = z },
                .{ .x = end_x, .y = command.end_y orelse 0, .z = end_z },
            );
        }
        var out = try std.ArrayList(u8).initCapacity(allocator, 256);
        defer out.deinit(allocator);
        try appendFmt(allocator, &out, "{{\"ok\":true,\"id\":", .{});
        try appendJsonString(allocator, &out, command.id);
        try appendFmt(allocator, &out, ",\"command\":", .{});
        try appendJsonString(allocator, &out, command.name);
        try appendFmt(allocator, &out, ",\"start\":{{\"x\":{d:.6},\"y\":{d:.6},\"z\":{d:.6}}},\"end\":{{\"x\":{d:.6},\"y\":{d:.6},\"z\":{d:.6}}},\"objects\":{d},\"status\":", .{
            x,
            command.point_y orelse 0,
            z,
            end_x,
            command.end_y orelse 0,
            end_z,
            editor_state.objects.items.len,
        });
        try appendJsonString(allocator, &out, editor_state.status_buf[0..editor_state.status_len]);
        try appendFmt(allocator, &out, "}}\n", .{});
        return out.toOwnedSlice(allocator);
    }
    if (std.mem.startsWith(u8, command.name, "architecture.network-") or
        std.mem.startsWith(u8, command.name, "architecture.node-") or
        std.mem.startsWith(u8, command.name, "architecture.edge-") or
        std.mem.startsWith(u8, command.name, "architecture.shell-") or
        std.mem.startsWith(u8, command.name, "architecture.wall-height-") or
        std.mem.startsWith(u8, command.name, "architecture.floor-") or
        std.mem.startsWith(u8, command.name, "architecture.foundation-") or
        std.mem.startsWith(u8, command.name, "architecture.cutout-") or
        std.mem.startsWith(u8, command.name, "architecture.roof-") or
        std.mem.startsWith(u8, command.name, "architecture.opening-"))
    {
        const editor_state = state orelse return error.EditorStateRequired;
        editor_state.mode = .architecture_creation;
        return handleArchitectureNetworkCommand(allocator, command, editor_state);
    }
    if (std.mem.startsWith(u8, command.name, "road.network-") or
        std.mem.startsWith(u8, command.name, "road.graph-") or
        std.mem.startsWith(u8, command.name, "road.node-") or
        std.mem.startsWith(u8, command.name, "road.edge-"))
    {
        const editor_state = state orelse return error.EditorStateRequired;
        editor_state.mode = .world_creation;
        editor_state.world_tool = .roads;
        return editor_commands_road_graph.handle(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "terrain.geology-start")) {
        const editor_state = state orelse return error.EditorStateRequired;
        const min_x = command.min_x orelse return error.MissingTerrainBatchBounds;
        const max_x = command.max_x orelse return error.MissingTerrainBatchBounds;
        const min_z = command.min_z orelse return error.MissingTerrainBatchBounds;
        const max_z = command.max_z orelse return error.MissingTerrainBatchBounds;
        const cell_size_m = command.cell_size_m orelse return error.InvalidTerrainBatchCellSize;
        const batch_size_raw = command.batch_size orelse return error.InvalidTerrainBatchSize;
        if (batch_size_raw == 0 or batch_size_raw > std.math.maxInt(u32)) return error.InvalidTerrainBatchSize;
        const formations = try editor_commands_terrain_recipe_parse.parseFormations(allocator, command.properties orelse return error.InvalidTerrainFormationRecipe);
        defer allocator.free(formations);
        try project_editor_world_authoring_terrain_batch.start(editor_state, .{
            .min_x = min_x,
            .max_x = max_x,
            .min_z = min_z,
            .max_z = max_z,
            .cell_size_m = cell_size_m,
            .batch_size = @intCast(batch_size_raw),
            .seed = command.seed orelse 0,
            .formations = formations,
        });
        return editor_commands_terrain_status.terrainGeologyStatusJson(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "terrain.geology-status")) {
        const editor_state = state orelse return error.EditorStateRequired;
        return editor_commands_terrain_status.terrainGeologyStatusJson(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "terrain.geology-cancel")) {
        const editor_state = state orelse return error.EditorStateRequired;
        project_editor_world_authoring_terrain_batch.cancel(editor_state);
        return editor_commands_terrain_status.terrainGeologyStatusJson(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "terrain.recipe-apply")) {
        const editor_state = state orelse return error.EditorStateRequired;
        if (!std.mem.eql(u8, command.operation orelse return error.InvalidTerrainRecipeOperation, "replace_heights_keep_cells")) return error.InvalidTerrainRecipeOperation;
        const min_x = command.min_x orelse return error.MissingTerrainBatchBounds;
        const max_x = command.max_x orelse return error.MissingTerrainBatchBounds;
        const min_z = command.min_z orelse return error.MissingTerrainBatchBounds;
        const max_z = command.max_z orelse return error.MissingTerrainBatchBounds;
        const cell_size_m = command.cell_size_m orelse return error.InvalidTerrainBatchCellSize;
        const features = try editor_commands_terrain_recipe_parse.parseFeatures(allocator, command.features orelse return error.InvalidTerrainRecipe);
        defer allocator.free(features);
        try project_editor_world_authoring_terrain_recipe.start(editor_state, .{
            .min_x = min_x,
            .max_x = max_x,
            .min_z = min_z,
            .max_z = max_z,
            .cell_size_m = cell_size_m,
            .seed = command.seed orelse 0,
            .sea_level = command.sea_level orelse 0,
            .ocean_floor = command.ocean_floor orelse -120,
            .features = features,
        });
        return editor_commands_terrain_status.terrainRecipeStatusJson(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "terrain.recipe-status")) {
        const editor_state = state orelse return error.EditorStateRequired;
        return editor_commands_terrain_status.terrainRecipeStatusJson(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "terrain.recipe-cancel")) {
        const editor_state = state orelse return error.EditorStateRequired;
        project_editor_world_authoring_terrain_recipe.cancel(editor_state);
        return editor_commands_terrain_status.terrainRecipeStatusJson(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "terrain.cell-create")) {
        const editor_state = state orelse return error.EditorStateRequired;
        const point = try editor_commands_terrain_status.commandTerrainPoint(command);
        editor_state.mode = .world_creation;
        try project_editor_world_authoring.createTerrainCellAt(editor_state, point);
        return editor_commands_terrain_status.terrainPointStatusJson(allocator, command, editor_state, point);
    }
    if (std.mem.eql(u8, command.name, "terrain.cell-delete")) {
        const editor_state = state orelse return error.EditorStateRequired;
        const point = try editor_commands_terrain_status.commandTerrainPoint(command);
        editor_state.mode = .world_creation;
        try project_editor_world_authoring.deleteTerrainCellAt(editor_state, point);
        return editor_commands_terrain_status.terrainPointStatusJson(allocator, command, editor_state, point);
    }
    if (std.mem.eql(u8, command.name, "terrain.sculpt")) {
        const editor_state = state orelse return error.EditorStateRequired;
        const point = try editor_commands_terrain_status.commandTerrainPoint(command);
        const mode_name = command.operation orelse return error.MissingOperation;
        const mode = try project_editor_world_authoring_terrain.TerrainSculptMode.parse(mode_name);
        if (command.radius) |radius| editor_state.world_brush_size = radius;
        if (command.opacity) |opacity| editor_state.world_brush_strength = opacity;
        if (command.hardness) |hardness| editor_state.world_brush_falloff = hardness;
        editor_state.mode = .world_creation;
        editor_state.world_tool = .terrain;
        editor_state.selected_world_layer = .terrain_base_height;
        editor_state.world_affects_height = true;
        const result = try project_editor_world_authoring_terrain.sculptTerrainAt(editor_state, point, mode, "terrain sculpt");
        return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"operation\":\"{s}\",\"point\":{{\"x\":{d:.6},\"y\":{d:.6},\"z\":{d:.6}}},\"cell\":{{\"x\":{d},\"y\":{d},\"z\":{d}}},\"brush\":{{\"radius\":{d:.3},\"opacity\":{d:.3},\"hardness\":{d:.3}}},\"affected_samples\":{d},\"peak_delta\":{d:.6},\"status\":\"{s}\"}}\n", .{
            command.id,
            command.name,
            mode.label(),
            point.x,
            point.y,
            point.z,
            result.cell.x,
            result.cell.y,
            result.cell.z,
            editor_state.world_brush_size,
            editor_state.world_brush_strength,
            editor_state.world_brush_falloff,
            result.affected_samples,
            result.peak_delta,
            editor_state.status_buf[0..editor_state.status_len],
        });
    }
    if (std.mem.eql(u8, command.name, "terrain.material-paint")) {
        const editor_state = state orelse return error.EditorStateRequired;
        const point = try editor_commands_terrain_status.commandTerrainPoint(command);
        const layer_name = command.object orelse return error.InvalidTerrainPaintLayer;
        if (command.radius) |radius| editor_state.world_brush_size = radius;
        if (command.opacity) |opacity| editor_state.world_brush_strength = opacity;
        if (command.hardness) |hardness| editor_state.world_brush_falloff = hardness;
        editor_state.mode = .world_creation;
        const result = try project_editor_world_authoring_terrain.paintMaterialLayerAt(editor_state, point, layer_name);
        return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"layer\":\"{s}\",\"point\":{{\"x\":{d:.6},\"y\":{d:.6},\"z\":{d:.6}}},\"cell\":{{\"x\":{d},\"y\":{d},\"z\":{d}}},\"brush\":{{\"radius\":{d:.3},\"opacity\":{d:.3},\"hardness\":{d:.3}}},\"affected_samples\":{d},\"target_layer\":{d:.0},\"status\":\"{s}\"}}\n", .{
            command.id,
            command.name,
            layer_name,
            point.x,
            point.y,
            point.z,
            result.cell.x,
            result.cell.y,
            result.cell.z,
            editor_state.world_brush_size,
            editor_state.world_brush_strength,
            editor_state.world_brush_falloff,
            result.affected_samples,
            result.peak_delta,
            editor_state.status_buf[0..editor_state.status_len],
        });
    }
    if (std.mem.eql(u8, command.name, "terrain.edge-cliff")) {
        const editor_state = state orelse return error.EditorStateRequired;
        const bottom_height = command.height orelse return error.InvalidTerrainEdgeCliffHeight;
        const width_m = command.width orelse return error.InvalidTerrainEdgeCliffWidth;
        editor_state.mode = .world_creation;
        editor_state.world_tool = .terrain;
        editor_state.selected_world_layer = .terrain_base_height;
        try project_editor_world_authoring_terrain_edge.start(editor_state, bottom_height, width_m);
        return editor_commands_terrain_status.terrainEdgeCliffStatusJson(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "terrain.edge-cliff-status")) {
        const editor_state = state orelse return error.EditorStateRequired;
        return editor_commands_terrain_status.terrainEdgeCliffStatusJson(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "terrain.edge-cliff-cancel")) {
        const editor_state = state orelse return error.EditorStateRequired;
        project_editor_world_authoring_terrain_edge.cancel(editor_state);
        return editor_commands_terrain_status.terrainEdgeCliffStatusJson(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "terrain.stretch-smooth")) {
        const editor_state = state orelse return error.EditorStateRequired;
        try project_editor_world_authoring_terrain_stretch_smooth.start(editor_state, .{
            .threshold_m = command.threshold orelse 180,
            .strength = command.strength orelse 0.35,
            .iterations = command.iterations orelse 1,
            .max_samples_per_cell = command.max_samples_per_cell orelse 12,
            .min_height = command.min_height orelse -std.math.inf(f32),
            .max_height = command.max_height orelse std.math.inf(f32),
        });
        return editor_commands_terrain_status.terrainStretchSmoothStatusJson(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "terrain.stretch-smooth-status")) {
        const editor_state = state orelse return error.EditorStateRequired;
        return editor_commands_terrain_status.terrainStretchSmoothStatusJson(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "terrain.stretch-smooth-cancel")) {
        const editor_state = state orelse return error.EditorStateRequired;
        project_editor_world_authoring_terrain_stretch_smooth.cancel(editor_state);
        return editor_commands_terrain_status.terrainStretchSmoothStatusJson(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "terrain.undo-latest")) {
        const editor_state = state orelse return error.EditorStateRequired;
        if (editor_commands_terrain_status.terrainJobActive(editor_state)) return error.TerrainUndoBlockedByActiveJob;
        const restored = try project_editor_terrain_undo_store.restoreLatest(allocator, editor_state.io, editor_state.project_path);
        if (restored != null) {
            editor_state.terrain_preview_stale = true;
            project_editor_terrain_preview.scheduleBake(editor_state);
            project_editor_state.setStatus(editor_state, "Terrain undo restored");
        } else {
            project_editor_state.setStatus(editor_state, "No terrain undo transaction");
        }
        return editor_commands_terrain_status.terrainUndoStatusJson(allocator, command, editor_state, restored);
    }
    if (std.mem.eql(u8, command.name, "terrain.heightmap-load")) {
        const editor_state = state orelse return error.EditorStateRequired;
        const point = try editor_commands_terrain_status.commandTerrainPoint(command);
        const path = command.path orelse command.object orelse return error.InvalidHeightmapPath;
        const min_height = command.min_height orelse 0;
        const max_height = command.max_height orelse 8;
        const material = command.material_path orelse "terrain.editor";
        editor_state.mode = .world_creation;
        const result = try project_editor_world_authoring_terrain.loadHeightmapAt(editor_state, point, path, min_height, max_height, material);
        return editor_commands_terrain_status.terrainHeightmapStatusJson(allocator, command, editor_state, path, point, result);
    }
    if (std.mem.eql(u8, command.name, "terrain.heightmap-batch-load")) {
        const editor_state = state orelse return error.EditorStateRequired;
        const path = command.path orelse command.object orelse return error.InvalidHeightmapPath;
        const result = try project_editor_world_authoring_heightmap_batch.loadBatch(editor_state, .{
            .path = path,
            .albedo_path = command.albedo_path,
            .min_x = command.min_x orelse return error.InvalidTerrainBatchBounds,
            .max_x = command.max_x orelse return error.InvalidTerrainBatchBounds,
            .min_z = command.min_z orelse return error.InvalidTerrainBatchBounds,
            .max_z = command.max_z orelse return error.InvalidTerrainBatchBounds,
            .cell_size_m = command.cell_size_m orelse return error.InvalidTerrainBatchCellSize,
            .min_height = command.min_height orelse return error.InvalidHeightmapRange,
            .max_height = command.max_height orelse return error.InvalidHeightmapRange,
            .material = command.material_path orelse "terrain.editor",
        });
        return editor_commands_terrain_status.terrainHeightmapBatchStatusJson(allocator, command, editor_state, path, result);
    }
    if (editor_commands_prop.handles(command.name)) {
        const editor_state = state orelse return error.EditorStateRequired;
        return editor_commands_prop.execute(allocator, command, editor_state);
    }
    if (std.mem.startsWith(u8, command.name, "concept-paint.")) {
        const editor_state = state orelse return error.EditorStateRequired;
        return executeConceptPaintCommand(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "play-scene")) {
        const editor_state = state orelse return error.EditorStateRequired;
        editor_state.is_playing = true;
        defer editor_state.is_playing = false;
        try project_editor_build.runPlaySceneWithFrameLimit(editor_state, command.frames);
        return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"frames\":{d},\"status\":\"{s}\"}}\n", .{
            command.id,
            command.name,
            command.frames orelse 0,
            editor_state.status_buf[0..editor_state.status_len],
        });
    }
    if (std.mem.eql(u8, command.name, "project.startup-scene-set")) {
        const editor_state = state orelse return error.EditorStateRequired;
        const path = command.path orelse return error.MissingPath;
        try project_editor_build.setProjectStartupScene(editor_state, path);
        return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"path\":\"{s}\",\"status\":\"{s}\"}}\n", .{
            command.id,
            command.name,
            path,
            editor_state.status_buf[0..editor_state.status_len],
        });
    }
    if (std.mem.eql(u8, command.name, "play.player-start-set")) {
        const editor_state = state orelse return error.EditorStateRequired;
        const point_x = command.point_x orelse return error.MissingPoint;
        const point_z = command.point_z orelse return error.MissingPoint;
        const point_y = command.point_y orelse 0;
        const object_name = try project_editor_build.setPlayerStart(
            editor_state,
            command.object,
            .{ .x = point_x, .y = point_y, .z = point_z },
            command.yaw orelse 0,
            command.pitch orelse 0,
        );
        return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"object\":\"{s}\",\"status\":\"{s}\"}}\n", .{
            command.id,
            command.name,
            object_name,
            editor_state.status_buf[0..editor_state.status_len],
        });
    }
    if (std.mem.eql(u8, command.name, "turntable-capture")) {
        return error.TurntableCaptureRequiresDeferredRender;
    }
    if (std.mem.eql(u8, command.name, "screenshot-editor")) {
        if (state) |editor_state| {
            return screenshotImmediate(allocator, io, editor_state.project_path, editor_state.project_name, renderer, command, null);
        }
        return screenshotImmediate(allocator, io, project_path, project_name, renderer, command, null);
    }
    if (std.mem.eql(u8, command.name, "screenshot-viewport")) {
        const editor_state = state orelse return error.EditorStateRequired;
        const rect = scaledSdlRectFromFRect(editor_state.viewport_screen_rect, editor_state.display_scale);
        return screenshotImmediate(allocator, io, editor_state.project_path, editor_state.project_name, renderer, command, &rect);
    }
    if (std.mem.eql(u8, command.name, "screenshot-viewport-clean")) {
        return error.CleanViewportCaptureRequiresDeferredRender;
    }
    if (std.mem.eql(u8, command.name, "map.top-down-capture")) {
        return error.TopDownCaptureRequiresDeferredRender;
    }
    if (std.mem.eql(u8, command.name, "focus-in-viewport")) {
        const editor_state = state orelse return error.EditorStateRequired;
        const idx = try findObjectIndex(editor_state, command.object orelse return error.MissingObject);
        try focusCameraOnObject(editor_state, idx, false);
        return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"object\":\"{s}\"}}\n", .{
            command.id,
            command.name,
            editor_state.objects.items[idx].name,
        });
    }
    if (std.mem.eql(u8, command.name, "zoom-to-focus")) {
        const editor_state = state orelse return error.EditorStateRequired;
        const idx = try findObjectIndex(editor_state, command.object orelse return error.MissingObject);
        try focusCameraOnObject(editor_state, idx, true);
        return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"object\":\"{s}\"}}\n", .{
            command.id,
            command.name,
            editor_state.objects.items[idx].name,
        });
    }
    return error.UnknownEditorCommand;
}

fn requireModeForMcpCommand(state: *const ProjectEditorState, command_name: []const u8) !void {
    if (std.mem.startsWith(u8, command_name, "terrain.") or
        std.mem.startsWith(u8, command_name, "world.") or
        std.mem.startsWith(u8, command_name, "ocean.") or
        std.mem.startsWith(u8, command_name, "water."))
    {
        if (!project_editor_modes.enabled(state, .world_creation)) return error.EditorModeUnavailable;
    }
    if (std.mem.startsWith(u8, command_name, "architecture.") or
        std.mem.startsWith(u8, command_name, "plot.") or
        std.mem.eql(u8, command_name, "scene.new-architecture"))
    {
        if (!project_editor_modes.enabled(state, .architecture_creation)) return error.EditorModeUnavailable;
    }
    if (std.mem.startsWith(u8, command_name, "prop.")) {
        if (!project_editor_modes.enabled(state, .prop_creation)) return error.EditorModeUnavailable;
    }
}

fn createGameplayMarker(
    allocator: std.mem.Allocator,
    command: CommandFile,
    state: *ProjectEditorState,
) ![]u8 {
    const kind_name = command.kind orelse return error.MissingMarkerKind;
    const kind = scene_marker.Kind.fromName(kind_name) orelse return error.InvalidMarkerKind;
    try project_editor_scene.addMarkerObject(state, kind);
    const idx = state.selected_object orelse return error.ObjectNotFound;
    const obj = &state.objects.items[idx];
    if (command.object) |name| try replaceOwnedString(state.allocator, &obj.name, name);
    try applyMarkerCommandFields(state, obj, command);
    const marker = obj.marker.?;
    setSingleSelection(state, obj.id);
    state.scene_dirty = true;
    project_editor_scene.setSelectionScope(state, .marker);
    setMarkerValidationStatus(state, marker, "Gameplay marker created");
    return markerCommandJson(allocator, command, obj, marker, state);
}

fn updateGameplayMarker(
    allocator: std.mem.Allocator,
    command: CommandFile,
    state: *ProjectEditorState,
) ![]u8 {
    const idx = try findObjectIndex(state, command.object orelse return error.MissingObject);
    const obj = &state.objects.items[idx];
    if (obj.marker == null) return error.MissingMarkerData;
    try applyMarkerCommandFields(state, obj, command);
    const marker = obj.marker.?;
    state.selected_object = idx;
    setSingleSelection(state, obj.id);
    state.selected_vertex = null;
    state.selected_edge = null;
    state.selected_face = null;
    state.scene_dirty = true;
    project_editor_scene.setSelectionScope(state, .marker);
    setMarkerValidationStatus(state, marker, "Gameplay marker updated");
    return markerCommandJson(allocator, command, obj, marker, state);
}

fn applyMarkerCommandFields(state: *ProjectEditorState, obj: *@import("editor_scene_object.zig").SceneObject, command: CommandFile) !void {
    if (command.point_x != null or command.point_y != null or command.point_z != null) {
        obj.position = .{
            .x = command.point_x orelse obj.position.x,
            .y = command.point_y orelse obj.position.y,
            .z = command.point_z orelse obj.position.z,
        };
    }
    const marker = if (obj.marker) |*marker| marker else return error.MissingMarkerData;
    if (command.kind) |kind_name| marker.kind = scene_marker.Kind.fromName(kind_name) orelse return error.InvalidMarkerKind;
    if (command.shape) |shape_name| marker.shape = scene_marker.Shape.fromName(shape_name) orelse return error.InvalidMarkerShape;
    if (command.marker_id) |id| try replaceOwnedString(state.allocator, &marker.marker_id, id);
    if (command.group) |group| try replaceOwnedString(state.allocator, &marker.group, group);
    if (command.binding) |binding| try replaceOwnedString(state.allocator, &marker.binding, binding);
    if (command.radius) |radius| marker.radius = radius;
    if (command.order) |order| marker.order = order;
}

fn setMarkerValidationStatus(state: *ProjectEditorState, marker: scene_marker.Marker, valid_message: []const u8) void {
    marker.validate() catch |err| {
        var buf: [96]u8 = undefined;
        project_editor_state.setStatus(state, std.fmt.bufPrint(&buf, "Invalid marker: {s}", .{@errorName(err)}) catch "Invalid marker");
        return;
    };
    project_editor_state.setStatus(state, valid_message);
}

fn markerCommandJson(
    allocator: std.mem.Allocator,
    command: CommandFile,
    obj: *const @import("editor_scene_object.zig").SceneObject,
    marker: scene_marker.Marker,
    state: *const ProjectEditorState,
) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, 256);
    defer out.deinit(allocator);
    try appendFmt(allocator, &out, "{{\"ok\":true,\"id\":", .{});
    try appendJsonString(allocator, &out, command.id);
    try appendFmt(allocator, &out, ",\"command\":", .{});
    try appendJsonString(allocator, &out, command.name);
    try appendFmt(allocator, &out, ",\"object\":", .{});
    try appendJsonString(allocator, &out, obj.name);
    try appendFmt(allocator, &out, ",\"object_id\":{d},\"kind\":", .{obj.id});
    try appendJsonString(allocator, &out, marker.kind.name());
    try appendFmt(allocator, &out, ",\"shape\":", .{});
    try appendJsonString(allocator, &out, marker.shape.name());
    try appendMarkerValidation(allocator, &out, marker);
    try appendFmt(allocator, &out, ",\"status\":", .{});
    try appendJsonString(allocator, &out, state.status_buf[0..state.status_len]);
    try appendFmt(allocator, &out, "}}\n", .{});
    return out.toOwnedSlice(allocator);
}

fn replaceOwnedString(allocator: std.mem.Allocator, slot: *[]u8, value: []const u8) !void {
    if (slot.len > 0) allocator.free(slot.*);
    slot.* = if (value.len > 0) try allocator.dupe(u8, value) else "";
}

fn executeConceptPaintCommand(
    allocator: std.mem.Allocator,
    command: CommandFile,
    state: *ProjectEditorState,
) ![]u8 {
    if (std.mem.eql(u8, command.name, "concept-paint.capture")) {
        try project_editor_concept_paint.capture(state, .{
            .screenshot_path = command.screenshot_path orelse return error.ConceptPaintScreenshotMissing,
            .prompt = command.prompt orelse "",
            .provider = command.provider orelse "",
            .desired_style = command.desired_style orelse "",
            .output_path = command.output_path orelse "",
            .opacity = command.opacity orelse 1.0,
            .blend_mode = command.blend_mode orelse "normal",
        });
        return conceptStatusJson(allocator, command, state);
    }
    if (std.mem.eql(u8, command.name, "concept-paint.import-styled")) {
        try project_editor_concept_paint.importStyled(state, .{
            .styled_path = command.styled_path orelse return error.ConceptPaintStyledImageMissing,
        });
        return conceptStatusJson(allocator, command, state);
    }
    if (std.mem.eql(u8, command.name, "concept-paint.describe")) {
        return project_editor_concept_paint.describe(allocator, state);
    }
    if (std.mem.eql(u8, command.name, "concept-paint.request-package")) {
        const path = try project_editor_concept_paint.requestPackage(state);
        defer allocator.free(path);
        return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"path\":\"{s}\",\"status\":\"{s}\"}}\n", .{
            command.id,
            command.name,
            path,
            state.status_buf[0..state.status_len],
        });
    }
    if (std.mem.eql(u8, command.name, "concept-paint.apply")) {
        const report = try project_editor_concept_paint.apply(state);
        return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"objects_changed\":{d},\"terrain_cells_changed\":{d},\"samples_changed\":{d},\"status\":\"{s}\"}}\n", .{
            command.id,
            command.name,
            report.objects_changed,
            report.terrain_cells_changed,
            report.samples_changed,
            state.status_buf[0..state.status_len],
        });
    }
    if (std.mem.eql(u8, command.name, "concept-paint.clear")) {
        project_editor_concept_paint.clear(state);
        return conceptStatusJson(allocator, command, state);
    }
    return error.UnknownEditorCommand;
}

fn conceptStatusJson(allocator: std.mem.Allocator, command: CommandFile, state: *const ProjectEditorState) ![]u8 {
    return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"status\":\"{s}\"}}\n", .{
        command.id,
        command.name,
        state.status_buf[0..state.status_len],
    });
}

pub fn focusSelectedObject(state: *ProjectEditorState, zoom: bool) !void {
    const idx = state.selected_object orelse return error.ObjectNotFound;
    try focusCameraOnObject(state, idx, zoom);
}

fn screenshotImmediate(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    project_name: []const u8,
    renderer: *editor_draw.SDL_Renderer,
    command: CommandFile,
    rect: ?*const sdl.SDL_Rect,
) ![]u8 {
    const absolute_path = try screenshotAbsolutePath(allocator, io, project_path, project_name, command.id);
    defer allocator.free(absolute_path);
    const absolute_path_z = try allocator.dupeZ(u8, absolute_path);
    defer allocator.free(absolute_path_z);

    const surface = sdl.SDL_RenderReadPixels(renderer, rect) orelse return error.SdlRenderReadPixelsFailed;
    defer sdl.SDL_DestroySurface(surface);
    if (!sdl.SDL_SavePNG(surface, absolute_path_z.ptr)) return error.SdlSavePngFailed;

    return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"path\":\"{s}\"}}\n", .{
        command.id,
        command.name,
        absolute_path,
    });
}

fn sanitizedProjectName(allocator: std.mem.Allocator, project_name: []const u8) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, @max(project_name.len, 1));
    defer out.deinit(allocator);
    var last_dash = false;
    for (project_name) |ch| {
        const mapped: ?u8 = if (std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '-' or ch == '.')
            ch
        else if (std.ascii.isWhitespace(ch))
            '-'
        else
            null;
        if (mapped) |value| {
            if (value == '-') {
                if (last_dash or out.items.len == 0) continue;
                last_dash = true;
            } else {
                last_dash = false;
            }
            try out.append(allocator, value);
        }
    }
    while (out.items.len > 0 and out.items[out.items.len - 1] == '-') {
        _ = out.pop();
    }
    if (out.items.len == 0) try out.appendSlice(allocator, "project");
    return out.toOwnedSlice(allocator);
}

fn enqueueTurntableCapture(
    allocator: std.mem.Allocator,
    io: std.Io,
    state: *ProjectEditorState,
    command: CommandFile,
    request: ?*ControlRequest,
    control_server: ?*ControlServer,
) !PendingTurntableCapture {
    const idx = if (command.object) |target|
        try findObjectIndex(state, target)
    else
        state.selected_object orelse return error.ObjectNotFound;
    selectObject(state, idx);
    const obj = &state.objects.items[idx];
    const frame_count_u64 = command.frames orelse 36;
    if (frame_count_u64 < 2 or frame_count_u64 > 180) return error.InvalidTurntableFrameCount;
    const frame_count: u32 = @intCast(frame_count_u64);
    const fps_u64 = command.fps orelse 24;
    if (fps_u64 < 1 or fps_u64 > 120) return error.InvalidTurntableFps;
    const fps: u32 = @intCast(fps_u64);
    const format = try parseTurntableFormat(command.format);
    const original_camera = state.camera;
    const target = obj.position;
    const eye = original_camera.eye();
    const offset = editor_math.Vec3.sub(eye, target);
    const radius = @max(1.0, vec3Length(offset));
    const pitch = std.math.clamp(std.math.asin(std.math.clamp(offset.y / radius, -1.0, 1.0)), -1.4, 1.4);
    const start_yaw = std.math.atan2(offset.x, offset.z);
    const output_dir = try turntableOutputDir(allocator, io, state.project_path, state.project_name, command.id);
    errdefer allocator.free(output_dir);
    const manifest_path = try std.fs.path.join(allocator, &.{ output_dir, "manifest.json" });
    errdefer allocator.free(manifest_path);
    const encoded_path = try turntableEncodedPath(allocator, output_dir, format);
    errdefer allocator.free(encoded_path);

    var pending = PendingTurntableCapture{
        .id = try allocator.dupe(u8, command.id),
        .command_name = try allocator.dupe(u8, command.name),
        .object_name = try allocator.dupe(u8, obj.name),
        .project_path = try allocator.dupe(u8, state.project_path),
        .project_name = try allocator.dupe(u8, state.project_name),
        .output_dir = output_dir,
        .manifest_path = manifest_path,
        .encoded_path = encoded_path,
        .format = try allocator.dupe(u8, format),
        .frame_paths = .empty,
        .frame_count = frame_count,
        .fps = fps,
        .original_camera = original_camera,
        .target = target,
        .radius = radius,
        .pitch = pitch,
        .start_yaw = start_yaw,
        .control_request = request,
        .control_server = control_server,
    };
    applyTurntableCamera(state, &pending);
    project_editor_state.setStatus(state, "Turntable capture started");
    return pending;
}

fn applyTurntableCamera(state: *ProjectEditorState, pending: *const PendingTurntableCapture) void {
    const t = @as(f32, @floatFromInt(pending.frame_index)) / @as(f32, @floatFromInt(pending.frame_count));
    state.view_camera_mode = .perspective;
    state.view_orientation = .free;
    state.camera.target = pending.target;
    state.camera.distance = pending.radius;
    state.camera.pitch = pending.pitch;
    state.camera.yaw = pending.start_yaw + std.math.tau * t;
}

fn turntableOutputDir(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    project_name: []const u8,
    command_id: []const u8,
) ![]u8 {
    try ensureProjectDirs(io, project_path);
    const project_dir_name = try sanitizedProjectName(allocator, project_name);
    defer allocator.free(project_dir_name);
    const project_turntable_dir = try std.fs.path.join(allocator, &.{ turntable_dir, project_dir_name });
    defer allocator.free(project_turntable_dir);
    try makeProjectPath(io, project_path, project_turntable_dir);
    const rel_path = try std.fs.path.join(allocator, &.{ project_turntable_dir, command_id });
    defer allocator.free(rel_path);
    const absolute_path = try std.fs.path.join(allocator, &.{ project_path, rel_path });
    try makeProjectPath(io, project_path, rel_path);
    return absolute_path;
}

fn turntableFramePath(allocator: std.mem.Allocator, output_dir: []const u8, frame_index: u32) ![]u8 {
    const file_name = try std.fmt.allocPrint(allocator, "frame-{d:0>3}.png", .{frame_index});
    defer allocator.free(file_name);
    return std.fs.path.join(allocator, &.{ output_dir, file_name });
}

fn turntableEncodedPath(allocator: std.mem.Allocator, output_dir: []const u8, format: []const u8) ![]u8 {
    const file_name = try std.fmt.allocPrint(allocator, "turntable.{s}", .{format});
    defer allocator.free(file_name);
    return std.fs.path.join(allocator, &.{ output_dir, file_name });
}

fn parseTurntableFormat(format: ?[]const u8) ![]const u8 {
    const value = format orelse "mp4";
    if (std.mem.eql(u8, value, "mp4") or std.mem.eql(u8, value, "gif")) return value;
    return error.InvalidTurntableFormat;
}

fn encodeTurntable(
    allocator: std.mem.Allocator,
    io: std.Io,
    pending: *const PendingTurntableCapture,
) !void {
    const input_pattern = try std.fs.path.join(allocator, &.{ pending.output_dir, "frame-%03d.png" });
    defer allocator.free(input_pattern);
    const fps_arg = try std.fmt.allocPrint(allocator, "{d}", .{pending.fps});
    defer allocator.free(fps_arg);

    const argv: []const []const u8 = if (std.mem.eql(u8, pending.format, "mp4"))
        &.{ "ffmpeg", "-y", "-framerate", fps_arg, "-i", input_pattern, "-c:v", "libx264", "-pix_fmt", "yuv420p", pending.encoded_path }
    else
        &.{ "ffmpeg", "-y", "-framerate", fps_arg, "-i", input_pattern, pending.encoded_path };

    const result = std.process.run(allocator, io, .{
        .argv = argv,
        .cwd = .{ .path = pending.project_path },
        .stdout_limit = .limited(32 * 1024),
        .stderr_limit = .limited(32 * 1024),
    }) catch return error.TurntableEncoderLaunchFailed;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .exited => |code| if (code != 0) return error.TurntableEncoderFailed,
        .signal, .stopped, .unknown => return error.TurntableEncoderStopped,
    }
}

fn writeTurntableManifest(
    allocator: std.mem.Allocator,
    io: std.Io,
    pending: *const PendingTurntableCapture,
) ![]u8 {
    var manifest = try std.ArrayList(u8).initCapacity(allocator, 2048);
    defer manifest.deinit(allocator);
    try appendFmt(allocator, &manifest, "{{\"ok\":true,\"id\":", .{});
    try appendJsonString(allocator, &manifest, pending.id);
    try appendFmt(allocator, &manifest, ",\"command\":", .{});
    try appendJsonString(allocator, &manifest, pending.command_name);
    try appendFmt(allocator, &manifest, ",\"object\":", .{});
    try appendJsonString(allocator, &manifest, pending.object_name);
    try appendFmt(allocator, &manifest, ",\"frames\":{d},\"fps\":{d},\"format\":", .{ pending.frame_count, pending.fps });
    try appendJsonString(allocator, &manifest, pending.format);
    try appendFmt(allocator, &manifest, ",\"distance\":{d:.6},\"directory\":", .{pending.radius});
    try appendJsonString(allocator, &manifest, pending.output_dir);
    try appendFmt(allocator, &manifest, ",\"manifest\":", .{});
    try appendJsonString(allocator, &manifest, pending.manifest_path);
    try appendFmt(allocator, &manifest, ",\"encoded_path\":", .{});
    try appendJsonString(allocator, &manifest, pending.encoded_path);
    try appendFmt(allocator, &manifest, ",\"frame_paths\":[", .{});
    for (pending.frame_paths.items, 0..) |path, idx| {
        if (idx != 0) try appendFmt(allocator, &manifest, ",", .{});
        try appendJsonString(allocator, &manifest, path);
    }
    try appendFmt(allocator, &manifest, "]}}\n", .{});

    const manifest_path_z = try allocator.dupeZ(u8, pending.manifest_path);
    defer allocator.free(manifest_path_z);
    const file = try std.Io.Dir.cwd().createFile(io, manifest_path_z, .{});
    defer file.close(io);
    var write_buf: [4096]u8 = undefined;
    var writer_state = file.writer(io, &write_buf);
    try writer_state.interface.writeAll(manifest.items);
    try writer_state.interface.flush();

    return allocator.dupe(u8, manifest.items);
}

fn vec3Length(vec: editor_math.Vec3) f32 {
    return @sqrt(vec.x * vec.x + vec.y * vec.y + vec.z * vec.z);
}

fn focusCameraOnObject(state: *ProjectEditorState, idx: usize, zoom: bool) !void {
    const obj = &state.objects.items[idx];
    selectObject(state, idx);
    state.camera.target = obj.position;
    if (zoom) {
        state.camera.distance = objectFocusDistance(obj);
    }
    project_editor_state.setStatus(state, if (zoom) "Camera zoomed to object" else "Camera focused on object");
}

fn objectFocusDistance(obj: *const SceneObject) f32 {
    const radius = @max(@max(@abs(obj.scale.x), @abs(obj.scale.y)), @abs(obj.scale.z));
    return std.math.clamp(radius * 3.0, 1.5, 80.0);
}

fn createNewArchitectureScene(state: *ProjectEditorState, scene_path: []const u8) !void {
    if (std.fs.path.isAbsolute(scene_path)) return error.InvalidScenePath;
    if (!std.mem.startsWith(u8, scene_path, "scenes/")) return error.InvalidScenePath;
    if (!std.mem.endsWith(u8, scene_path, ".kdl")) return error.InvalidScenePath;

    clearEditorScene(state);
    if (state.active_scene_path_owned) state.allocator.free(state.active_scene_path);
    state.active_scene_path = try state.allocator.dupe(u8, scene_path);
    state.active_scene_path_owned = true;
    state.mode = .architecture_creation;
    state.architecture_tool = .wall;
    state.left_tab = .scene;
    state.snap_enabled = true;
    state.snap_size = 0.5;
    state.architecture_wall_height = 12.0;
    state.architecture_wall_thickness = 1.15;
    state.architecture_door_height = 3.2;
    state.architecture_window_sill = 1.45;
    state.architecture_window_height = 1.8;
    state.camera.target = .{ .x = 0, .y = 2.8, .z = 2.4 };
    state.camera.yaw = -0.55;
    state.camera.pitch = 0.42;
    state.camera.distance = 15.0;
    state.scene_dirty = false;
    project_editor_state.setStatus(state, "New architecture scene ready");
}

fn createPlotRoot(allocator: std.mem.Allocator, command: CommandFile, state: *ProjectEditorState) ![]u8 {
    const name = command.object orelse return error.MissingObject;
    try validatePlotText(name);
    if (editor_commands_object.nameExists(state, name)) return error.DuplicateObjectName;
    const properties = try editor_commands_object.buildProperties(state.allocator, command.properties orelse return error.MissingProperties);
    var properties_owned_by_command = true;
    errdefer if (properties_owned_by_command) editor_commands_object.freeProperties(state.allocator, properties);
    const width = command.width orelse return error.MissingWidth;
    const depth = command.depth orelse return error.MissingDepth;
    if (width <= 0 or depth <= 0) return error.InvalidPlotSize;
    const point_x = command.point_x orelse return error.MissingPoint;
    const point_z = command.point_z orelse return error.MissingPoint;
    const vertical_offset = command.point_y orelse 0.08;
    const root_y = try sampleTerrainHeight(state, point_x, point_z) + vertical_offset;

    project_editor_edit.pushUndoSnapshot(state);
    var mesh = try buildTerrainConformingPlotMesh(state, .{ .x = point_x, .y = root_y, .z = point_z }, width, depth, vertical_offset);
    errdefer mesh.deinit(state.allocator);
    const tex = try state.allocator.alloc(u8, editor_scene_object.TextureSize * editor_scene_object.TextureSize * 4);
    errdefer state.allocator.free(tex);
    editor_scene_object.fillCheckerTexture(tex, editor_scene_object.TextureSize, 102, 136, 86);
    const owned_name = try state.allocator.dupe(u8, name);
    errdefer state.allocator.free(owned_name);
    const owned_layer = try state.allocator.dupe(u8, "plots");
    errdefer state.allocator.free(owned_layer);
    const components = try state.allocator.alloc([]u8, 3);
    errdefer state.allocator.free(components);
    components[0] = try state.allocator.dupe(u8, "plot.root");
    errdefer state.allocator.free(components[0]);
    components[1] = try state.allocator.dupe(u8, "plot.movable");
    errdefer state.allocator.free(components[1]);
    components[2] = try state.allocator.dupe(u8, "hierarchy.root");
    errdefer state.allocator.free(components[2]);

    const object_id = state.next_object_id;
    try state.objects.append(state.allocator, .{
        .id = object_id,
        .name = owned_name,
        .mesh = mesh,
        .position = .{
            .x = point_x,
            .y = root_y,
            .z = point_z,
        },
        .rotation = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = tex,
        .base_color = .{ .r = 102, .g = 136, .b = 86, .a = 255 },
        .primitive_kind = null,
        .object_kind = .mesh,
        .renderer_visible = false,
        .components = components,
        .properties = properties,
        .layer = owned_layer,
        .cast_shadows = false,
        .receive_shadows = false,
    });
    properties_owned_by_command = false;
    state.next_object_id += 1;
    state.selected_object = state.objects.items.len - 1;
    state.selected_vertex = null;
    state.selected_edge = null;
    state.selected_face = null;
    state.scene_dirty = true;
    project_editor_state.setStatus(state, "Plot root created");

    const plot = &state.objects.items[state.objects.items.len - 1];
    return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"object\":\"{s}\",\"properties\":{f},\"object_id\":{d},\"position\":{{\"x\":{d:.6},\"y\":{d:.6},\"z\":{d:.6}}},\"size\":{{\"width\":{d:.6},\"depth\":{d:.6}}},\"status\":\"Plot root created\"}}\n", .{
        command.id,
        command.name,
        name,
        std.json.fmt(command.properties.?, .{}),
        object_id,
        plot.position.x,
        plot.position.y,
        plot.position.z,
        width,
        depth,
    });
}

fn alignPlotsToTerrain(allocator: std.mem.Allocator, command: CommandFile, state: *ProjectEditorState) ![]u8 {
    const vertical_offset = command.point_y orelse 0.08;
    var aligned: usize = 0;
    var selected_idx: ?usize = null;

    project_editor_edit.pushUndoSnapshot(state);
    if (command.object) |target| {
        const idx = try findObjectIndex(state, target);
        try alignPlotAtIndex(state, idx, vertical_offset);
        selected_idx = idx;
        aligned = 1;
    } else {
        for (state.objects.items, 0..) |obj, idx| {
            if (!editor_commands_object.hasComponent(&obj, "plot.root")) continue;
            try alignPlotAtIndex(state, idx, vertical_offset);
            aligned += 1;
        }
    }
    if (aligned == 0) return error.PlotNotFound;

    if (selected_idx) |idx| state.selected_object = idx;
    state.scene_dirty = true;
    project_editor_state.setStatus(state, "Plots conformed to terrain");
    return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"aligned\":{d},\"vertical_offset\":{d:.6},\"status\":\"Plots conformed to terrain\"}}\n", .{
        command.id,
        command.name,
        aligned,
        vertical_offset,
    });
}

fn alignPlotAtIndex(state: *ProjectEditorState, idx: usize, vertical_offset: f32) !void {
    if (!editor_commands_object.hasComponent(&state.objects.items[idx], "plot.root")) return error.ObjectIsNotPlot;
    const world_position = editor_scene_hierarchy.objectWorldPosition(state.objects.items, idx);
    const footprint = try plotFootprint(state, idx);
    const root_y = try sampleTerrainHeight(state, world_position.x, world_position.z) + vertical_offset;
    var new_mesh = try buildTerrainConformingPlotMesh(state, .{ .x = world_position.x, .y = root_y, .z = world_position.z }, footprint.width, footprint.depth, vertical_offset);
    errdefer new_mesh.deinit(state.allocator);
    state.objects.items[idx].mesh.deinit(state.allocator);
    state.objects.items[idx].mesh = new_mesh;
    state.objects.items[idx].position.y = root_y;
    state.objects.items[idx].primitive_kind = null;
}

fn plotFootprint(state: *const ProjectEditorState, idx: usize) !struct { width: f32, depth: f32 } {
    const obj = &state.objects.items[idx];
    if (propertyNumber(obj, "plot_width_m")) |width| {
        if (propertyNumber(obj, "plot_depth_m")) |depth| {
            if (width > 0 and depth > 0) return .{ .width = width, .depth = depth };
        }
    }
    if (obj.mesh.vertices.len == 0) return error.InvalidPlotMesh;
    var min_x: f32 = std.math.inf(f32);
    var max_x: f32 = -std.math.inf(f32);
    var min_z: f32 = std.math.inf(f32);
    var max_z: f32 = -std.math.inf(f32);
    for (obj.mesh.vertices) |vertex| {
        min_x = @min(min_x, vertex.position.x);
        max_x = @max(max_x, vertex.position.x);
        min_z = @min(min_z, vertex.position.z);
        max_z = @max(max_z, vertex.position.z);
    }
    const width = max_x - min_x;
    const depth = max_z - min_z;
    if (width <= 0 or depth <= 0) return error.InvalidPlotMesh;
    return .{ .width = width, .depth = depth };
}

fn propertyNumber(obj: *const SceneObject, key: []const u8) ?f32 {
    for (obj.properties) |property| {
        if (!std.mem.eql(u8, property.key, key)) continue;
        return std.fmt.parseFloat(f32, property.value) catch null;
    }
    return null;
}

fn sampleTerrainHeight(state: *ProjectEditorState, x: f32, z: f32) !f32 {
    return project_editor_terrain_preview.sampleHeightAtPoint(state, .{ .x = x, .y = 0, .z = z });
}

fn buildTerrainConformingPlotMesh(
    state: *ProjectEditorState,
    root: editor_math.Vec3,
    width: f32,
    depth: f32,
    vertical_offset: f32,
) !geometry.Mesh {
    const subdivisions: usize = 8;
    const side = subdivisions + 1;
    const vertex_count = side * side;
    const index_count = subdivisions * subdivisions * 6;
    const vertices = try state.allocator.alloc(geometry.Vertex, vertex_count);
    errdefer state.allocator.free(vertices);
    const indices = try state.allocator.alloc(u32, index_count);
    errdefer state.allocator.free(indices);

    const half_w = width * 0.5;
    const half_d = depth * 0.5;
    for (0..side) |z_i| {
        const vz = @as(f32, @floatFromInt(z_i)) / @as(f32, @floatFromInt(subdivisions));
        const local_z = -half_d + depth * vz;
        for (0..side) |x_i| {
            const ux = @as(f32, @floatFromInt(x_i)) / @as(f32, @floatFromInt(subdivisions));
            const local_x = -half_w + width * ux;
            const terrain_y = try sampleTerrainHeight(state, root.x + local_x, root.z + local_z) + vertical_offset;
            vertices[z_i * side + x_i] = .{
                .position = .{ .x = local_x, .y = terrain_y - root.y, .z = local_z },
                .normal = .{ .x = 0, .y = 1, .z = 0 },
                .uv = .{ .x = ux, .y = vz },
            };
        }
    }

    var out: usize = 0;
    for (0..subdivisions) |z_i| {
        for (0..subdivisions) |x_i| {
            const v0: u32 = @intCast(z_i * side + x_i);
            const v1: u32 = @intCast(z_i * side + x_i + 1);
            const v2: u32 = @intCast((z_i + 1) * side + x_i + 1);
            const v3: u32 = @intCast((z_i + 1) * side + x_i);
            indices[out + 0] = v0;
            indices[out + 1] = v1;
            indices[out + 2] = v2;
            indices[out + 3] = v0;
            indices[out + 4] = v2;
            indices[out + 5] = v3;
            out += 6;
        }
    }

    return .{ .vertices = vertices, .indices = indices };
}

fn createPlotLocalBuilding(allocator: std.mem.Allocator, command: CommandFile, state: *ProjectEditorState) ![]u8 {
    const name = command.object orelse return error.MissingObject;
    const parent_name = command.parent orelse return error.MissingParent;
    try validatePlotText(name);
    if (editor_commands_object.nameExists(state, name)) return error.DuplicateObjectName;
    const properties = try editor_commands_object.buildProperties(state.allocator, command.properties orelse return error.MissingProperties);
    defer editor_commands_object.freeProperties(state.allocator, properties);

    const parent_idx = try findObjectIndex(state, parent_name);
    const parent = &state.objects.items[parent_idx];
    if (!editor_commands_object.hasComponent(parent, "plot.root")) return error.ParentIsNotPlot;
    const parent_id = parent.id;
    const parent_object_name = parent.name;

    const width = command.width orelse return error.MissingWidth;
    const depth = command.depth orelse return error.MissingDepth;
    const floor_height = command.height orelse return error.MissingHeight;
    const thickness = command.thickness orelse return error.MissingThickness;
    const floors = command.floors orelse return error.MissingFloors;
    if (width <= 0 or depth <= 0 or floor_height <= 0 or thickness <= 0 or floors == 0) return error.InvalidBuildingDimensions;
    const roof_kind = try parseRoofKind(command.roof orelse return error.MissingRoof);

    var building = arch.Building{};
    defer building.deinit(state.allocator);
    const half_w = width * 0.5;
    const half_d = depth * 0.5;
    const wall_height = floor_height * @as(f32, @floatFromInt(floors));
    try building.vertices.append(state.allocator, .{ .id = 0, .x = -half_w, .z = -half_d });
    try building.vertices.append(state.allocator, .{ .id = 1, .x = half_w, .z = -half_d });
    try building.vertices.append(state.allocator, .{ .id = 2, .x = half_w, .z = half_d });
    try building.vertices.append(state.allocator, .{ .id = 3, .x = -half_w, .z = half_d });
    try building.walls.append(state.allocator, .{ .id = 0, .a = 0, .b = 1, .height = wall_height, .thickness = thickness });
    try building.walls.append(state.allocator, .{ .id = 1, .a = 1, .b = 2, .height = wall_height, .thickness = thickness });
    try building.walls.append(state.allocator, .{ .id = 2, .a = 2, .b = 3, .height = wall_height, .thickness = thickness });
    try building.walls.append(state.allocator, .{ .id = 3, .a = 3, .b = 0, .height = wall_height, .thickness = thickness });
    building.floors = .{ .count = floors, .height = floor_height, .slab_thickness = 0.12 };
    building.roof = .{
        .kind = roof_kind,
        .pitch = if (roof_kind == .flat) 0 else 0.55,
        .overhang = if (roof_kind == .flat) 0.15 else 0.3,
    };

    const extra_components = try state.allocator.alloc([]const u8, 2);
    defer state.allocator.free(extra_components);
    extra_components[0] = "architecture.intent:editable";
    extra_components[1] = "plot.child:building";

    project_editor_edit.pushUndoSnapshot(state);
    const object_id = try project_editor_blockout.createBuildingObjectWithOptions(state, &building, .{
        .name = name,
        .position = .{
            .x = command.point_x orelse return error.MissingPoint,
            .y = command.point_y orelse 0,
            .z = command.point_z orelse return error.MissingPoint,
        },
        .parent_id = parent_id,
        .extra_components = extra_components,
        .properties = properties,
    });
    project_editor_state.setStatus(state, "Plot-local building created");

    const obj = &state.objects.items[state.objects.items.len - 1];
    return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"object\":\"{s}\",\"properties\":{f},\"object_id\":{d},\"parent\":\"{s}\",\"parent_id\":{d},\"local_position\":{{\"x\":{d:.6},\"y\":{d:.6},\"z\":{d:.6}}},\"size\":{{\"width\":{d:.6},\"depth\":{d:.6},\"floor_height\":{d:.6},\"floors\":{d},\"wall_thickness\":{d:.6}}},\"roof\":\"{s}\",\"status\":\"Plot-local building created\"}}\n", .{
        command.id,
        command.name,
        name,
        std.json.fmt(command.properties.?, .{}),
        object_id,
        parent_object_name,
        parent_id,
        obj.position.x,
        obj.position.y,
        obj.position.z,
        width,
        depth,
        floor_height,
        floors,
        thickness,
        roof_kind.token(),
    });
}

fn handleArchitectureNetworkCommand(allocator: std.mem.Allocator, command: CommandFile, state: *ProjectEditorState) ![]u8 {
    if (std.mem.eql(u8, command.name, "architecture.network-create")) return createArchitectureNetwork(allocator, command, state);
    if (std.mem.eql(u8, command.name, "architecture.network-delete")) return deleteArchitectureNetwork(allocator, command, state);

    const target = command.object orelse return error.MissingObject;
    const idx = try findObjectIndex(state, target);
    if (!project_editor_architecture.isArchitectureBuildingObject(&state.objects.items[idx])) return error.ObjectIsNotArchitectureNetwork;
    var building = try arch.Building.parse(state.allocator, state.objects.items[idx].components);
    defer building.deinit(state.allocator);

    var changed = false;
    var status: []const u8 = "Architecture network unchanged";
    var primary_id: u32 = 0;
    var removed_edges: u32 = 0;
    var removed_openings: u32 = 0;
    var removed_shells: u32 = 0;

    if (std.mem.eql(u8, command.name, "architecture.node-add")) {
        const id = if (command.vertex) |vertex| vertex else building.nextVertexId();
        if (building.findVertex(id) != null) return error.DuplicateArchitectureNode;
        try building.vertices.append(state.allocator, .{ .id = id, .x = command.point_x orelse return error.MissingPoint, .z = command.point_z orelse return error.MissingPoint });
        primary_id = id;
        changed = true;
        status = "Architecture node added";
    } else if (std.mem.eql(u8, command.name, "architecture.node-move")) {
        const vertex_id = command.vertex orelse return error.MissingVertex;
        const vertex = building.vertexPtr(vertex_id) orelse return error.ArchitectureNodeNotFound;
        vertex.x = command.point_x orelse return error.MissingPoint;
        vertex.z = command.point_z orelse return error.MissingPoint;
        primary_id = vertex_id;
        changed = true;
        status = "Architecture node moved";
    } else if (std.mem.eql(u8, command.name, "architecture.node-delete")) {
        const vertex_id = command.vertex orelse return error.MissingVertex;
        const removed = building.removeVertexCascade(state.allocator, vertex_id);
        if (!removed.removed_vertex) return error.ArchitectureNodeNotFound;
        primary_id = vertex_id;
        removed_edges = removed.removed_edges;
        removed_openings = removed.removed_openings;
        removed_shells = removed.removed_shells;
        changed = true;
        status = "Architecture node deleted";
    } else if (std.mem.eql(u8, command.name, "architecture.edge-add")) {
        const a = command.edge_a orelse return error.MissingEdge;
        const b = command.edge_b orelse return error.MissingEdge;
        if (a == b) return error.InvalidArchitectureEdge;
        if (building.findVertex(a) == null or building.findVertex(b) == null) return error.ArchitectureNodeNotFound;
        const id = building.nextWallId();
        const height_mode = parseWallHeightMode(command.operation orelse "explicit");
        const floor_index = command.floors orelse 1;
        const height = resolvedWallHeight(command.height, height_mode, floor_index, building.floors);
        try building.walls.append(state.allocator, .{
            .id = id,
            .a = a,
            .b = b,
            .height = height,
            .thickness = command.thickness orelse state.architecture_wall_thickness,
            .height_mode = height_mode,
            .floor_index = floor_index,
        });
        primary_id = id;
        changed = true;
        status = "Architecture edge added";
    } else if (std.mem.eql(u8, command.name, "architecture.edge-split")) {
        const wall_id = command.edge_a orelse return error.MissingEdge;
        const wall = building.wallPtr(wall_id) orelse return error.ArchitectureEdgeNotFound;
        const old_b = wall.b;
        const new_vertex_id = building.nextVertexId();
        const new_wall_id = building.nextWallId();
        try building.vertices.append(state.allocator, .{ .id = new_vertex_id, .x = command.point_x orelse return error.MissingPoint, .z = command.point_z orelse return error.MissingPoint });
        wall.b = new_vertex_id;
        try building.walls.append(state.allocator, .{
            .id = new_wall_id,
            .a = new_vertex_id,
            .b = old_b,
            .height = wall.height,
            .thickness = wall.thickness,
            .height_mode = wall.height_mode,
            .floor_index = wall.floor_index,
        });
        invalidateShellsAndRoof(&building, state.allocator);
        primary_id = new_vertex_id;
        changed = true;
        status = "Architecture edge split";
    } else if (std.mem.eql(u8, command.name, "architecture.edge-delete")) {
        const wall_id = command.edge_a orelse return error.MissingEdge;
        const removed = building.removeWallCascade(state.allocator, wall_id);
        if (!removed.removed_wall) return error.ArchitectureEdgeNotFound;
        primary_id = wall_id;
        removed_openings = removed.removed_openings;
        removed_shells = removed.removed_shells;
        changed = true;
        status = "Architecture edge deleted";
    } else if (std.mem.eql(u8, command.name, "architecture.shell-create")) {
        var shell = arch.Shell{ .id = building.nextShellId() };
        errdefer shell.deinit(state.allocator);
        try parseShellPath(state.allocator, command.path orelse return error.MissingPath, &shell);
        try validateShellPath(&building, &shell);
        primary_id = shell.id;
        try building.shells.append(state.allocator, shell);
        changed = true;
        status = "Architecture shell created";
    } else if (std.mem.eql(u8, command.name, "architecture.shell-delete")) {
        const shell_id = command.edge_a orelse return error.MissingShell;
        if (!building.removeShell(shell_id, state.allocator)) return error.ArchitectureShellNotFound;
        primary_id = shell_id;
        removed_shells = 1;
        changed = true;
        status = "Architecture shell deleted";
    } else if (std.mem.eql(u8, command.name, "architecture.wall-height-set")) {
        const wall_id = command.edge_a orelse return error.MissingEdge;
        const wall = building.wallPtr(wall_id) orelse return error.ArchitectureEdgeNotFound;
        wall.height_mode = parseWallHeightMode(command.operation orelse return error.MissingOperation);
        wall.floor_index = command.floors orelse wall.floor_index;
        wall.height = resolvedWallHeight(command.height, wall.height_mode, wall.floor_index, building.floors);
        primary_id = wall_id;
        changed = true;
        status = "Architecture wall height set";
    } else if (std.mem.eql(u8, command.name, "architecture.floor-set")) {
        building.floors = .{
            .count = command.floors orelse return error.MissingFloors,
            .height = command.height orelse return error.MissingHeight,
            .slab_thickness = command.thickness orelse return error.MissingThickness,
        };
        for (building.walls.items) |*wall| {
            if (wall.height_mode == .to_floor) wall.height = resolvedWallHeight(null, .to_floor, wall.floor_index, building.floors);
        }
        changed = true;
        status = "Architecture floors set";
    } else if (std.mem.eql(u8, command.name, "architecture.foundation-create") or std.mem.eql(u8, command.name, "architecture.foundation-update")) {
        const foundation = try commandFoundation(state, command, idx);
        if (std.mem.eql(u8, command.name, "architecture.foundation-update")) {
            const foundation_id = command.edge_a orelse return error.MissingFoundation;
            const existing = building.foundationPtr(foundation_id) orelse return error.ArchitectureFoundationNotFound;
            existing.* = foundation;
            existing.id = foundation_id;
            primary_id = foundation_id;
            status = "Architecture foundation updated";
        } else {
            var new_foundation = foundation;
            new_foundation.id = building.nextFoundationId();
            primary_id = new_foundation.id;
            try building.foundations.append(state.allocator, new_foundation);
            status = "Architecture foundation created";
        }
        changed = true;
    } else if (std.mem.eql(u8, command.name, "architecture.foundation-delete")) {
        const foundation_id = command.edge_a orelse return error.MissingFoundation;
        if (!building.removeFoundation(foundation_id)) return error.ArchitectureFoundationNotFound;
        primary_id = foundation_id;
        changed = true;
        status = "Architecture foundation deleted";
    } else if (std.mem.eql(u8, command.name, "architecture.cutout-create") or std.mem.eql(u8, command.name, "architecture.cutout-update")) {
        const cutout = try commandCutout(command);
        if (std.mem.eql(u8, command.name, "architecture.cutout-update")) {
            const cutout_id = command.edge_a orelse return error.MissingCutout;
            const existing = building.cutoutPtr(cutout_id) orelse return error.ArchitectureCutoutNotFound;
            existing.* = cutout;
            existing.id = cutout_id;
            primary_id = cutout_id;
            status = "Architecture cutout updated";
        } else {
            var new_cutout = cutout;
            new_cutout.id = building.nextCutoutId();
            primary_id = new_cutout.id;
            try building.cutouts.append(state.allocator, new_cutout);
            status = "Architecture cutout created";
        }
        changed = true;
    } else if (std.mem.eql(u8, command.name, "architecture.cutout-delete")) {
        const cutout_id = command.edge_a orelse return error.MissingCutout;
        if (!building.removeCutout(cutout_id)) return error.ArchitectureCutoutNotFound;
        primary_id = cutout_id;
        changed = true;
        status = "Architecture cutout deleted";
    } else if (std.mem.eql(u8, command.name, "architecture.roof-set")) {
        if (building.shells.items.len == 0) return error.ArchitectureShellRequired;
        const roof_kind = try parseRoofKind(command.roof orelse return error.MissingRoof);
        building.roof = .{
            .kind = roof_kind,
            .pitch = command.height orelse if (roof_kind == .flat) 0 else 0.55,
            .overhang = command.thickness orelse if (roof_kind == .flat) 0.15 else 0.3,
        };
        changed = true;
        status = "Architecture roof set";
    } else if (std.mem.eql(u8, command.name, "architecture.roof-delete")) {
        building.roof = null;
        changed = true;
        status = "Architecture roof deleted";
    } else if (std.mem.eql(u8, command.name, "architecture.opening-create") or std.mem.eql(u8, command.name, "architecture.opening-update")) {
        if (std.mem.eql(u8, command.name, "architecture.opening-update")) {
            const opening_id = command.edge_a orelse return error.MissingOpening;
            const existing = building.openingPtr(opening_id) orelse return error.ArchitectureOpeningNotFound;
            const opening = try commandOpeningForWall(command, &building, existing.wall_id);
            existing.* = opening;
            existing.id = opening_id;
            primary_id = opening_id;
            status = "Architecture opening updated";
        } else {
            const wall_id = command.edge_a orelse return error.MissingEdge;
            var new_opening = try commandOpeningForWall(command, &building, wall_id);
            new_opening.id = building.nextOpeningId();
            primary_id = new_opening.id;
            try building.openings.append(state.allocator, new_opening);
            status = "Architecture opening created";
        }
        changed = true;
    } else if (std.mem.eql(u8, command.name, "architecture.opening-delete")) {
        const opening_id = command.edge_a orelse return error.MissingOpening;
        if (!building.removeOpening(opening_id)) return error.ArchitectureOpeningNotFound;
        primary_id = opening_id;
        changed = true;
        status = "Architecture opening deleted";
    } else if (std.mem.eql(u8, command.name, "architecture.network-describe")) {
        return describeArchitectureNetwork(allocator, command, &state.objects.items[idx], &building, "Architecture network described", null);
    } else if (std.mem.eql(u8, command.name, "architecture.network-validate")) {
        const validation_error: ?[]const u8 = if (validateArchitectureNetwork(&building)) null else |err| @errorName(err);
        return describeArchitectureNetwork(allocator, command, &state.objects.items[idx], &building, "Architecture network validated", validation_error);
    } else {
        return error.UnknownArchitectureNetworkCommand;
    }

    if (changed) {
        project_editor_edit.pushUndoSnapshot(state);
        try project_editor_blockout.writeBackBuilding(state, &state.objects.items[idx], &building);
        state.selected_object = idx;
        project_editor_architecture.setActiveBuilding(state, state.objects.items[idx].id);
        project_editor_state.setStatus(state, status);
    }
    return architectureMutationJson(allocator, command, &state.objects.items[idx], &building, status, primary_id, removed_edges, removed_openings, removed_shells);
}

fn createArchitectureNetwork(allocator: std.mem.Allocator, command: CommandFile, state: *ProjectEditorState) ![]u8 {
    const name = command.object orelse return error.MissingObject;
    const parent_name = command.parent orelse return error.MissingParent;
    try validatePlotText(name);
    if (editor_commands_object.nameExists(state, name)) return error.DuplicateObjectName;
    const properties = try editor_commands_object.buildProperties(state.allocator, command.properties orelse return error.MissingProperties);
    var properties_owned = true;
    errdefer if (properties_owned) editor_commands_object.freeProperties(state.allocator, properties);
    const parent_idx = try findObjectIndex(state, parent_name);
    const parent = &state.objects.items[parent_idx];
    if (!editor_commands_object.hasComponent(parent, "plot.root")) return error.ParentIsNotPlot;

    var building = arch.Building{};
    defer building.deinit(state.allocator);
    building.floors = .{
        .count = command.floors orelse 1,
        .height = command.height orelse state.architecture_wall_height,
        .slab_thickness = command.thickness orelse 0.12,
    };
    const components = try building.serialize(state.allocator);
    errdefer {
        for (components) |component| state.allocator.free(component);
        state.allocator.free(components);
    }
    const merged_components = try state.allocator.alloc([]u8, components.len + 2);
    errdefer state.allocator.free(merged_components);
    for (components, 0..) |component, i| merged_components[i] = component;
    merged_components[components.len] = try state.allocator.dupe(u8, "architecture.intent:editable");
    errdefer state.allocator.free(merged_components[components.len]);
    merged_components[components.len + 1] = try state.allocator.dupe(u8, "plot.child:wall-network");
    errdefer state.allocator.free(merged_components[components.len + 1]);
    state.allocator.free(components);

    const tex = try state.allocator.alloc(u8, editor_scene_object.TextureSize * editor_scene_object.TextureSize * 4);
    errdefer state.allocator.free(tex);
    editor_scene_object.fillCheckerTexture(tex, editor_scene_object.TextureSize, 92, 92, 96);
    const owned_name = try state.allocator.dupe(u8, name);
    errdefer state.allocator.free(owned_name);
    const object_id = state.next_object_id;
    project_editor_edit.pushUndoSnapshot(state);
    const empty_vertices = try state.allocator.alloc(geometry.Vertex, 0);
    errdefer state.allocator.free(empty_vertices);
    const empty_indices = try state.allocator.alloc(u32, 0);
    errdefer state.allocator.free(empty_indices);
    try state.objects.append(state.allocator, .{
        .id = object_id,
        .name = owned_name,
        .mesh = .{ .vertices = empty_vertices, .indices = empty_indices },
        .position = .{ .x = command.point_x orelse return error.MissingPoint, .y = command.point_y orelse 0, .z = command.point_z orelse return error.MissingPoint },
        .rotation = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = tex,
        .base_color = .{ .r = 92, .g = 92, .b = 96, .a = 255 },
        .primitive_kind = null,
        .object_kind = .mesh,
        .physics = null,
        .components = merged_components,
        .properties = properties,
        .parent_id = parent.id,
    });
    properties_owned = false;
    state.next_object_id += 1;
    state.selected_object = state.objects.items.len - 1;
    project_editor_architecture.setActiveBuilding(state, object_id);
    state.scene_dirty = true;
    project_editor_state.setStatus(state, "Architecture network created");
    return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"object\":\"{s}\",\"object_id\":{d},\"parent\":\"{s}\",\"parent_id\":{d},\"status\":\"Architecture network created\"}}\n", .{
        command.id,
        command.name,
        name,
        object_id,
        parent.name,
        parent.id,
    });
}

fn deleteArchitectureNetwork(allocator: std.mem.Allocator, command: CommandFile, state: *ProjectEditorState) ![]u8 {
    const target = command.object orelse return error.MissingObject;
    const idx = try findObjectIndex(state, target);
    if (!project_editor_architecture.isArchitectureBuildingObject(&state.objects.items[idx])) return error.ObjectIsNotArchitectureNetwork;
    const object_id = state.objects.items[idx].id;
    const owned_name = try allocator.dupe(u8, state.objects.items[idx].name);
    defer allocator.free(owned_name);
    project_editor_edit.pushUndoSnapshot(state);
    state.objects.items[idx].deinit(state.allocator);
    _ = state.objects.orderedRemove(idx);
    state.selected_object = null;
    project_editor_architecture.clearActiveBuilding(state);
    state.scene_dirty = true;
    project_editor_state.setStatus(state, "Architecture network deleted");
    return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"object\":\"{s}\",\"object_id\":{d},\"status\":\"Architecture network deleted\"}}\n", .{ command.id, command.name, owned_name, object_id });
}

fn parseWallHeightMode(token: []const u8) arch.WallHeightMode {
    if (std.mem.eql(u8, token, "explicit")) return .explicit;
    if (std.mem.eql(u8, token, "to_floor")) return .to_floor;
    @panic("invalid wall height mode passed through schema");
}

fn resolvedWallHeight(explicit_height: ?f32, mode: arch.WallHeightMode, floor_index: u32, floors: arch.Floors) f32 {
    return switch (mode) {
        .explicit => explicit_height orelse floors.height * @as(f32, @floatFromInt(@max(@as(u32, 1), floor_index))),
        .to_floor => floors.height * @as(f32, @floatFromInt(@max(@as(u32, 1), floor_index))),
    };
}

fn parseShellPath(allocator: std.mem.Allocator, raw: []const u8, shell: *arch.Shell) !void {
    var parts = std.mem.splitScalar(u8, raw, ',');
    while (parts.next()) |part| {
        const trimmed = std.mem.trim(u8, part, " \t\r\n");
        if (trimmed.len == 0) return error.InvalidArchitectureShell;
        try shell.walls.append(allocator, try std.fmt.parseInt(u32, trimmed, 10));
    }
    if (shell.walls.items.len < 3) return error.InvalidArchitectureShell;
}

fn validateShellPath(building: *const arch.Building, shell: *const arch.Shell) !void {
    var expected_start: ?u32 = null;
    var previous_end: ?u32 = null;
    for (shell.walls.items) |wall_id| {
        const wall = building.wallPtrConst(wall_id) orelse return error.ArchitectureEdgeNotFound;
        if (expected_start == null) expected_start = wall.a;
        if (previous_end) |end| {
            if (wall.a != end) return error.InvalidArchitectureShell;
        }
        previous_end = wall.b;
    }
    if (expected_start == null or previous_end == null or expected_start.? != previous_end.?) return error.InvalidArchitectureShell;
}

fn invalidateShellsAndRoof(building: *arch.Building, allocator: std.mem.Allocator) void {
    for (building.shells.items) |*shell| shell.deinit(allocator);
    building.shells.clearRetainingCapacity();
    building.roof = null;
}

fn commandFoundation(state: *ProjectEditorState, command: CommandFile, obj_idx: usize) !arch.Foundation {
    const min_x = @min(command.point_x orelse return error.MissingPoint, command.end_x orelse return error.MissingPoint);
    const max_x = @max(command.point_x orelse return error.MissingPoint, command.end_x orelse return error.MissingPoint);
    const min_z = @min(command.point_z orelse return error.MissingPoint, command.end_z orelse return error.MissingPoint);
    const max_z = @max(command.point_z orelse return error.MissingPoint, command.end_z orelse return error.MissingPoint);
    if (max_x <= min_x or max_z <= min_z) return error.InvalidFoundation;
    var top_y = command.height;
    if (top_y == null) {
        const world_position = editor_scene_hierarchy.objectWorldPosition(state.objects.items, obj_idx);
        const samples = [_]editor_math.Vec3{
            .{ .x = world_position.x + min_x, .y = 0, .z = world_position.z + min_z },
            .{ .x = world_position.x + max_x, .y = 0, .z = world_position.z + min_z },
            .{ .x = world_position.x + max_x, .y = 0, .z = world_position.z + max_z },
            .{ .x = world_position.x + min_x, .y = 0, .z = world_position.z + max_z },
            .{ .x = world_position.x + (min_x + max_x) * 0.5, .y = 0, .z = world_position.z + (min_z + max_z) * 0.5 },
        };
        var max_sample = -std.math.inf(f32);
        for (samples) |sample| max_sample = @max(max_sample, try sampleTerrainHeight(state, sample.x, sample.z) - world_position.y);
        top_y = max_sample + 0.05;
    }
    return .{
        .id = command.edge_a orelse 0,
        .min_x = min_x,
        .min_z = min_z,
        .max_x = max_x,
        .max_z = max_z,
        .top_y = top_y.?,
        .clearance = 0.05,
        .grid_step = command.radius orelse 1.0,
    };
}

fn commandCutout(command: CommandFile) !arch.TerrainCutout {
    const min_x = @min(command.point_x orelse return error.MissingPoint, command.end_x orelse return error.MissingPoint);
    const max_x = @max(command.point_x orelse return error.MissingPoint, command.end_x orelse return error.MissingPoint);
    const min_z = @min(command.point_z orelse return error.MissingPoint, command.end_z orelse return error.MissingPoint);
    const max_z = @max(command.point_z orelse return error.MissingPoint, command.end_z orelse return error.MissingPoint);
    const min_y = @min(command.point_y orelse -3.0, command.end_y orelse 0.0);
    const max_y = @max(command.point_y orelse -3.0, command.end_y orelse 0.0);
    if (max_x <= min_x or max_y <= min_y or max_z <= min_z) return error.InvalidCutout;
    return .{ .id = command.edge_a orelse 0, .min_x = min_x, .min_y = min_y, .min_z = min_z, .max_x = max_x, .max_y = max_y, .max_z = max_z };
}

fn commandOpeningForWall(command: CommandFile, building: *const arch.Building, wall_id: u32) !arch.WallOpening {
    const wall = building.wallPtrConst(wall_id) orelse return error.ArchitectureEdgeNotFound;
    const kind = try arch.OpeningKind.parse(command.operation orelse return error.MissingOperation);
    const t = command.u orelse return error.MissingOpeningOffset;
    const width = command.width orelse return error.MissingWidth;
    const height = command.height orelse return error.MissingHeight;
    const sill = command.point_y orelse if (kind == .door) @as(f32, 0) else @as(f32, 1.0);
    if (t < 0 or t > 1 or width <= 0 or height <= 0 or sill < 0 or sill + height > wall.height) return error.InvalidArchitectureOpening;
    return .{ .id = command.edge_a orelse 0, .wall_id = wall_id, .kind = kind, .t = t, .width = width, .height = height, .sill = sill };
}

fn validateArchitectureNetwork(building: *const arch.Building) !void {
    for (building.walls.items) |wall| {
        if (building.findVertex(wall.a) == null or building.findVertex(wall.b) == null) return error.ArchitectureDanglingEdge;
        if (wall.a == wall.b or wall.height <= 0 or wall.thickness <= 0) return error.InvalidArchitectureEdge;
    }
    for (building.openings.items) |opening| {
        const wall = building.wallPtrConst(opening.wall_id) orelse return error.ArchitectureOpeningDanglingEdge;
        if (opening.t < 0 or opening.t > 1 or opening.width <= 0 or opening.height <= 0 or opening.sill < 0 or opening.sill + opening.height > wall.height) return error.InvalidArchitectureOpening;
    }
    for (building.shells.items) |shell| try validateShellPath(building, &shell);
    try validateOutwardNormals(building);
}

fn validateOutwardNormals(building: *const arch.Building) !void {
    for (building.shells.items) |shell| {
        var area: f32 = 0;
        for (shell.walls.items) |wall_id| {
            const wall = building.wallPtrConst(wall_id) orelse return error.ArchitectureEdgeNotFound;
            const a = building.findVertex(wall.a) orelse return error.ArchitectureNodeNotFound;
            const b = building.findVertex(wall.b) orelse return error.ArchitectureNodeNotFound;
            area += a.x * b.z - b.x * a.z;
        }
        if (@abs(area) <= arch.eps) return error.InvalidArchitectureShell;
    }
}

fn describeArchitectureNetwork(
    allocator: std.mem.Allocator,
    command: CommandFile,
    obj: *const SceneObject,
    building: *const arch.Building,
    status: []const u8,
    validation_error: ?[]const u8,
) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, 512);
    defer out.deinit(allocator);
    try appendArchitectureSummary(allocator, &out, command, obj, building, status, 0, 0, 0, 0);
    if (validation_error) |err| {
        _ = out.pop();
        _ = out.pop();
        try appendFmt(allocator, &out, ",\"valid\":false,\"validation_errors\":[", .{});
        try appendJsonString(allocator, &out, err);
        try appendFmt(allocator, &out, "]}}\n", .{});
    }
    return out.toOwnedSlice(allocator);
}

fn architectureMutationJson(
    allocator: std.mem.Allocator,
    command: CommandFile,
    obj: *const SceneObject,
    building: *const arch.Building,
    status: []const u8,
    primary_id: u32,
    removed_edges: u32,
    removed_openings: u32,
    removed_shells: u32,
) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, 512);
    defer out.deinit(allocator);
    try appendArchitectureSummary(allocator, &out, command, obj, building, status, primary_id, removed_edges, removed_openings, removed_shells);
    return out.toOwnedSlice(allocator);
}

fn appendArchitectureSummary(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    command: CommandFile,
    obj: *const SceneObject,
    building: *const arch.Building,
    status: []const u8,
    primary_id: u32,
    removed_edges: u32,
    removed_openings: u32,
    removed_shells: u32,
) !void {
    try appendFmt(allocator, out, "{{\"ok\":true,\"id\":", .{});
    try appendJsonString(allocator, out, command.id);
    try appendFmt(allocator, out, ",\"command\":", .{});
    try appendJsonString(allocator, out, command.name);
    try appendFmt(allocator, out, ",\"object\":", .{});
    try appendJsonString(allocator, out, obj.name);
    try appendFmt(allocator, out, ",\"object_id\":{d},\"changed_id\":{d},\"counts\":{{\"nodes\":{d},\"edges\":{d},\"openings\":{d},\"shells\":{d},\"foundations\":{d},\"cutouts\":{d}}},\"invalidated\":{{\"edges\":{d},\"openings\":{d},\"shells\":{d}}},\"mesh\":{{\"vertices\":{d},\"indices\":{d}}},\"status\":", .{
        obj.id,
        primary_id,
        building.vertices.items.len,
        building.walls.items.len,
        building.openings.items.len,
        building.shells.items.len,
        building.foundations.items.len,
        building.cutouts.items.len,
        removed_edges,
        removed_openings,
        removed_shells,
        obj.mesh.vertices.len,
        obj.mesh.indices.len,
    });
    try appendJsonString(allocator, out, status);
    try appendFmt(allocator, out, "}}\n", .{});
}

fn validatePlotText(value: []const u8) !void {
    const trimmed = std.mem.trim(u8, value, " \t\r\n");
    if (trimmed.len == 0) return error.InvalidPlotText;
    if (std.mem.indexOfAny(u8, value, ",\r\n") != null) return error.InvalidPlotText;
}

fn parseRoofKind(value: []const u8) !arch.RoofKind {
    return arch.RoofKind.parse(value);
}

fn pickViewportLocal(state: *ProjectEditorState, x: f32, y: f32) !void {
    if (x < 0 or y < 0 or x > state.viewport_screen_rect.w or y > state.viewport_screen_rect.h) return error.ScreenPointOutsideViewport;
    project_editor_scene.pickMeshHit(state, x, y, state.viewport_screen_rect.w, state.viewport_screen_rect.h);
}

fn boxSelectViewportLocal(state: *ProjectEditorState, start_x: f32, start_y: f32, end_x: f32, end_y: f32) !void {
    if (!viewportPointInside(state, start_x, start_y) or !viewportPointInside(state, end_x, end_y)) return error.ScreenPointOutsideViewport;
    project_editor_scene.dragBoxSelect(
        state,
        .{ .x = start_x, .y = start_y },
        .{ .x = end_x, .y = end_y },
        state.viewport_screen_rect.w,
        state.viewport_screen_rect.h,
    );
}

fn viewportPointInside(state: *const ProjectEditorState, x: f32, y: f32) bool {
    return x >= 0 and y >= 0 and x <= state.viewport_screen_rect.w and y <= state.viewport_screen_rect.h;
}

fn clearEditorScene(state: *ProjectEditorState) void {
    for (state.objects.items) |*obj| obj.deinit(state.allocator);
    state.objects.clearRetainingCapacity();
    for (state.animations.items) |*clip| clip.deinit(state.allocator);
    state.animations.clearRetainingCapacity();
    for (state.skeletons.items) |*skeleton| skeleton.deinit(state.allocator);
    state.skeletons.clearRetainingCapacity();
    project_editor_edit.clearUndoHistory(state);
    state.wall_outline_points.clearRetainingCapacity();
    state.architecture_curve_points.clearRetainingCapacity();
    state.selected_object = null;
    state.selected_object_ids.clearRetainingCapacity();
    state.selected_vertex = null;
    state.selected_edge = null;
    state.selected_face = null;
    state.next_object_id = 1;
}

fn setSingleSelection(state: *ProjectEditorState, object_id: u64) void {
    state.selected_object_ids.clearRetainingCapacity();
    state.selected_object_ids.append(state.allocator, object_id) catch {};
}

fn describeEditorState(
    allocator: std.mem.Allocator,
    command: CommandFile,
    state: *const ProjectEditorState,
    host: *editor_core_ui.Host,
    viewport_gpu: *const editor_viewport_gpu.EditorViewportGpu,
    control_stats: ControlStats,
) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, 2048);
    defer out.deinit(allocator);
    const uploaded_stats: shared.gpu_api.UploadedMeshStats = if (viewport_gpu.gpu_renderer) |renderer| renderer.uploadedMeshStats() else .{};
    try appendFmt(allocator, &out, "{{\"ok\":true,\"id\":", .{});
    try appendJsonString(allocator, &out, command.id);
    try appendFmt(allocator, &out, ",\"command\":", .{});
    try appendJsonString(allocator, &out, command.name);
    try appendFmt(allocator, &out, ",\"mode\":", .{});
    try appendJsonString(allocator, &out, @tagName(state.mode));
    try appendFmt(allocator, &out, ",\"mode_label\":", .{});
    try appendJsonString(allocator, &out, state.mode.label());
    try appendFmt(allocator, &out, ",\"tool\":", .{});
    try appendJsonString(allocator, &out, activeToolTag(state));
    try appendFmt(allocator, &out, ",\"tool_label\":", .{});
    try appendJsonString(allocator, &out, project_editor_modes.toolLabel(state));
    try appendFmt(allocator, &out, ",\"left_tab\":", .{});
    try appendJsonString(allocator, &out, @tagName(state.left_tab));
    try appendFmt(allocator, &out, ",\"left_tab_label\":", .{});
    try appendJsonString(allocator, &out, state.left_tab.label());
    try appendFmt(allocator, &out, ",\"selection_scope\":", .{});
    try appendJsonString(allocator, &out, state.selection_scope.label());
    try appendFmt(allocator, &out, ",\"snap\":{{\"enabled\":{},\"size\":{d:.3}}}", .{ state.snap_enabled, state.snap_size });
    try appendFmt(allocator, &out, ",\"file_state\":{{\"dirty\":{},\"dirty_cells\":{d},\"playing\":{}}}", .{ state.scene_dirty or state.dirty_cells.count > 0, state.dirty_cells.count, state.is_playing });
    try appendFmt(allocator, &out, ",\"project\":{{\"name\":", .{});
    try appendJsonString(allocator, &out, state.project_name);
    try appendFmt(allocator, &out, ",\"path\":", .{});
    try appendJsonString(allocator, &out, state.project_path);
    try appendFmt(allocator, &out, "}},\"editor\":{{\"mode\":", .{});
    try appendJsonString(allocator, &out, @tagName(state.mode));
    try appendFmt(allocator, &out, ",\"enabled_modes\":[", .{});
    for (project_editor_modes.all, 0..) |mode_desc, idx| {
        if (idx != 0) try appendFmt(allocator, &out, ",", .{});
        try appendFmt(allocator, &out, "{{\"id\":", .{});
        try appendJsonString(allocator, &out, @tagName(mode_desc.mode));
        try appendFmt(allocator, &out, ",\"label\":", .{});
        try appendJsonString(allocator, &out, mode_desc.label);
        try appendFmt(allocator, &out, ",\"module\":", .{});
        try appendJsonString(allocator, &out, mode_desc.module_name);
        try appendFmt(allocator, &out, ",\"enabled\":{}}}", .{project_editor_modes.enabled(state, mode_desc.mode)});
    }
    try appendFmt(allocator, &out, "]", .{});
    try appendFmt(allocator, &out, ",\"left_tab\":", .{});
    try appendJsonString(allocator, &out, @tagName(state.left_tab));
    try appendFmt(allocator, &out, ",\"object_tool\":", .{});
    try appendJsonString(allocator, &out, @tagName(state.object_tool));
    try appendFmt(allocator, &out, ",\"architecture_tool\":", .{});
    try appendJsonString(allocator, &out, @tagName(state.architecture_tool));
    try appendFmt(allocator, &out, ",\"prop_tool\":", .{});
    try appendJsonString(allocator, &out, @tagName(state.prop_tool));
    try appendFmt(allocator, &out, ",\"life_tool\":", .{});
    try appendJsonString(allocator, &out, @tagName(state.life_tool));
    try appendFmt(allocator, &out, ",\"scene_dirty\":{},\"is_playing\":{},\"show_tool_inspector\":{},\"show_project_inspector\":{},\"show_me_mode\":{},\"show_me_focus_radius\":{d:.3},\"snap_enabled\":{},\"snap_size\":{d:.3}}}", .{
        state.scene_dirty,
        state.is_playing,
        state.show_tool_inspector,
        state.show_project_inspector,
        state.show_me_mode_enabled,
        state.show_me_focus_radius,
        state.snap_enabled,
        state.snap_size,
    });
    try appendFmt(allocator, &out, ",\"viewport\":{{\"x\":{d:.1},\"y\":{d:.1},\"w\":{d:.1},\"h\":{d:.1},\"camera_mode\":", .{
        state.viewport_screen_rect.x,
        state.viewport_screen_rect.y,
        state.viewport_screen_rect.w,
        state.viewport_screen_rect.h,
    });
    try appendJsonString(allocator, &out, @tagName(state.view_camera_mode));
    try appendFmt(allocator, &out, ",\"orientation\":", .{});
    try appendJsonString(allocator, &out, @tagName(state.view_orientation));
    try appendFmt(allocator, &out, ",\"backend\":", .{});
    try appendJsonString(allocator, &out, if (viewport_gpu.use_gpu and state.view_camera_mode == .perspective) "gpu" else if (state.view_camera_mode == .perspective) "software" else "orthographic");
    try appendFmt(allocator, &out, "}},\"camera\":{{\"target\":", .{});
    try appendVec3(allocator, &out, state.camera.target);
    try appendFmt(allocator, &out, ",\"yaw\":{d:.6},\"pitch\":{d:.6},\"distance\":{d:.3}}}", .{
        state.camera.yaw,
        state.camera.pitch,
        state.camera.distance,
    });
    try appendFmt(allocator, &out, ",\"selection\":", .{});
    try appendSelection(allocator, &out, state);
    try appendFmt(allocator, &out, ",\"world\":", .{});
    try appendWorldEditorState(allocator, &out, state);
    try appendFmt(allocator, &out, ",\"counts\":{{\"objects\":{d},\"ui_render_commands\":{d},\"visible_meshes\":{d},\"total_meshes\":{d},\"gpu_uploaded_meshes\":{d},\"gpu_indexed_primitives\":{d},\"gpu_wireframe_indices\":{d},\"llm_commands_executed\":{d},\"llm_commands_inflight\":{d},\"llm_commands_queued\":{d},\"llm_command_queued_bytes\":{d},\"dirty_world_cells\":{d},\"terrain_resident_cells\":{d},\"terrain_desired_cells\":{d},\"terrain_pending_loads\":{d},\"terrain_last_loaded\":{d},\"terrain_last_unloaded\":{d}}}", .{
        state.objects.items.len,
        host.ui.renderCommands().len,
        state.visibility_stats.visible_meshes,
        state.render_command_stats.meshes,
        uploaded_stats.meshes,
        uploaded_stats.indexed_primitives,
        uploaded_stats.wireframe_indices,
        control_stats.executed,
        control_stats.inflight,
        control_stats.queued,
        control_stats.queued_bytes,
        state.dirty_cells.count,
        state.terrain_preview.entries.items.len,
        state.terrain_preview.last_desired_cells,
        state.terrain_preview.last_pending_loads,
        state.terrain_preview.last_loaded,
        state.terrain_preview.last_unloaded,
    });
    try appendFmt(allocator, &out, ",\"status\":", .{});
    try appendJsonString(allocator, &out, state.status_buf[0..state.status_len]);
    try appendFmt(allocator, &out, "}}\n", .{});
    return out.toOwnedSlice(allocator);
}

fn activeToolTag(state: *const ProjectEditorState) []const u8 {
    return switch (state.mode) {
        .world_creation => @tagName(state.world_tool),
        .layout => @tagName(state.object_tool),
        .architecture_creation => @tagName(state.architecture_tool),
        .prop_creation => @tagName(state.prop_tool),
        .life => @tagName(state.life_tool),
    };
}

fn appendWorldEditorState(allocator: std.mem.Allocator, out: *std.ArrayList(u8), state: *const ProjectEditorState) !void {
    try appendFmt(allocator, out, "{{\"tool\":", .{});
    try appendJsonString(allocator, out, @tagName(state.world_tool));
    try appendFmt(allocator, out, ",\"layer\":", .{});
    if (state.selected_world_layer) |layer| {
        try appendJsonString(allocator, out, @tagName(layer));
    } else {
        try appendFmt(allocator, out, "null", .{});
    }
    try appendFmt(allocator, out, ",\"road_mode\":", .{});
    try appendJsonString(allocator, out, @tagName(state.world_road_mode));
    try appendFmt(allocator, out, ",\"road_draw_mode\":", .{});
    try appendJsonString(allocator, out, @tagName(state.world_road_draw_mode));
    try appendFmt(allocator, out, ",\"road_surface_mode\":", .{});
    try appendJsonString(allocator, out, @tagName(state.world_road_surface_mode));
    try appendFmt(allocator, out, ",\"road_terrain_mode\":", .{});
    try appendJsonString(allocator, out, @tagName(state.world_road_terrain_mode));
    try appendFmt(allocator, out, ",\"road_draft_points\":{d},\"selected_road_node\":", .{state.world_road_points.items.len});
    if (state.selected_road_node_id) |id| {
        try appendJsonString(allocator, out, id);
    } else {
        try appendFmt(allocator, out, "null", .{});
    }
    try appendFmt(allocator, out, ",\"selected_road_edge\":", .{});
    if (state.selected_road_edge_id) |id| {
        try appendJsonString(allocator, out, id);
    } else {
        try appendFmt(allocator, out, "null", .{});
    }
    try appendFmt(allocator, out, ",\"selected_road_handle\":", .{});
    try appendJsonString(allocator, out, @tagName(state.selected_road_handle));
    try appendFmt(allocator, out, ",\"hovered_curve_hit\":", .{});
    try appendWorldCurveHit(allocator, out, state.hovered_world_curve_hit);
    try appendFmt(allocator, out, ",\"selected_curve_hit\":", .{});
    try appendWorldCurveHit(allocator, out, state.selected_world_curve_hit);
    try appendFmt(allocator, out, ",\"drag_curve_hit\":", .{});
    try appendWorldCurveHit(allocator, out, state.world_curve_drag_state.hit);
    try appendFmt(allocator, out, "}}", .{});
}

fn appendWorldCurveHit(allocator: std.mem.Allocator, out: *std.ArrayList(u8), hit: project_editor_types.WorldCurveHit) !void {
    try appendFmt(allocator, out, "{{\"target\":", .{});
    try appendJsonString(allocator, out, @tagName(hit.target));
    try appendFmt(allocator, out, ",\"element\":", .{});
    try appendJsonString(allocator, out, @tagName(hit.element));
    try appendFmt(allocator, out, ",\"index\":{d},\"sub_index\":{d},\"distance_sq\":", .{ hit.index, hit.sub_index });
    if (std.math.isFinite(hit.distance_sq)) {
        try appendFmt(allocator, out, "{d:.3}", .{hit.distance_sq});
    } else {
        try appendFmt(allocator, out, "null", .{});
    }
    try appendFmt(allocator, out, "}}", .{});
}

fn describeObjects(allocator: std.mem.Allocator, command: CommandFile, state: *const ProjectEditorState) ![]u8 {
    const default_limit: usize = 64;
    const max_limit: usize = 512;
    const total = state.objects.items.len;
    const offset: usize = if (command.offset) |value| @intCast(@min(value, total)) else 0;
    const requested_limit: usize = if (command.limit) |value| @intCast(@min(value, max_limit)) else @min(default_limit, max_limit);
    const end = @min(total, offset + requested_limit);
    const returned = end - offset;

    var out = try std.ArrayList(u8).initCapacity(allocator, 4096);
    defer out.deinit(allocator);
    try appendFmt(allocator, &out, "{{\"ok\":true,\"id\":", .{});
    try appendJsonString(allocator, &out, command.id);
    try appendFmt(allocator, &out, ",\"command\":", .{});
    try appendJsonString(allocator, &out, command.name);
    try appendFmt(allocator, &out, ",\"count\":{d},\"offset\":{d},\"limit\":{d},\"returned\":{d},\"has_more\":{},\"selected_index\":", .{
        total,
        offset,
        requested_limit,
        returned,
        end < total,
    });
    if (state.selected_object) |idx| {
        try appendFmt(allocator, &out, "{d}", .{idx});
    } else {
        try appendFmt(allocator, &out, "null", .{});
    }
    try appendFmt(allocator, &out, ",\"objects\":[", .{});
    for (state.objects.items[offset..end], offset..) |obj, idx| {
        if (idx != offset) try appendFmt(allocator, &out, ",", .{});
        try appendFmt(allocator, &out, "{{\"index\":{d},\"id\":{d},\"name\":", .{ idx, obj.id });
        try appendJsonString(allocator, &out, obj.name);
        try appendFmt(allocator, &out, ",\"kind\":", .{});
        try appendJsonString(allocator, &out, @tagName(obj.object_kind));
        try appendFmt(allocator, &out, ",\"primitive\":", .{});
        if (obj.primitive_kind) |kind| {
            try appendJsonString(allocator, &out, @tagName(kind));
        } else {
            try appendFmt(allocator, &out, "null", .{});
        }
        try appendFmt(allocator, &out, ",\"position\":", .{});
        try appendVec3(allocator, &out, obj.position);
        try appendFmt(allocator, &out, ",\"rotation\":", .{});
        try appendVec3(allocator, &out, obj.rotation);
        try appendFmt(allocator, &out, ",\"scale\":", .{});
        try appendVec3(allocator, &out, obj.scale);
        try appendFmt(allocator, &out, ",\"enabled\":{},\"visible\":{},\"locked\":{},\"immutable\":{}}}", .{
            obj.enabled,
            obj.renderer_visible,
            obj.locked,
            obj.isImmutable(),
        });
    }
    try appendFmt(allocator, &out, "]}}\n", .{});
    return out.toOwnedSlice(allocator);
}

fn describeTerrainFootprint(allocator: std.mem.Allocator, command: CommandFile, state: *const ProjectEditorState) ![]u8 {
    const default_limit: usize = 128;
    const max_limit: usize = 256;
    const entries = state.terrain_preview.entries.items;
    const total = entries.len;
    const offset: usize = if (command.offset) |value| @intCast(@min(value, total)) else 0;
    const requested_limit: usize = if (command.limit) |value| @intCast(@min(value, max_limit)) else @min(default_limit, max_limit);
    const end = @min(total, offset + requested_limit);
    const returned = end - offset;
    const desired = state.terrain_preview.last_desired_cells;
    const pending = state.terrain_preview.last_pending_loads;
    const ready = pending == 0 and total == desired;

    var out = try std.ArrayList(u8).initCapacity(allocator, 8192);
    defer out.deinit(allocator);
    try appendFmt(allocator, &out, "{{\"ok\":true,\"id\":", .{});
    try appendJsonString(allocator, &out, command.id);
    try appendFmt(allocator, &out, ",\"command\":", .{});
    try appendJsonString(allocator, &out, command.name);
    try appendFmt(allocator, &out, ",\"ready\":{},\"resident_cells\":{d},\"desired_cells\":{d},\"pending_loads\":{d},\"last_loaded\":{d},\"last_unloaded\":{d},\"offset\":{d},\"limit\":{d},\"returned\":{d},\"has_more\":{},\"next_offset\":", .{
        ready,
        total,
        desired,
        pending,
        state.terrain_preview.last_loaded,
        state.terrain_preview.last_unloaded,
        offset,
        requested_limit,
        returned,
        end < total,
    });
    if (end < total) {
        try appendFmt(allocator, &out, "{d}", .{end});
    } else {
        try appendFmt(allocator, &out, "null", .{});
    }
    try appendFmt(allocator, &out, ",\"cells\":[", .{});
    for (entries[offset..end], offset..) |entry, idx| {
        if (idx != offset) try appendFmt(allocator, &out, ",", .{});
        const snapshot = entry.snapshot;
        const heights = snapshot.heights;
        var min_height: f32 = 0;
        var max_height: f32 = 0;
        var avg_height: f32 = 0;
        var center_height: f32 = 0;
        if (heights.len > 0) {
            min_height = heights[0];
            max_height = heights[0];
            var sum_height: f32 = 0;
            for (heights) |height_value| {
                min_height = @min(min_height, height_value);
                max_height = @max(max_height, height_value);
                sum_height += height_value;
            }
            avg_height = sum_height / @as(f32, @floatFromInt(heights.len));
            const grid: usize = @intCast(snapshot.size);
            const center_index = ((grid / 2) * grid) + (grid / 2);
            center_height = heights[@min(center_index, heights.len - 1)];
        }
        try appendFmt(allocator, &out, "{{\"index\":{d},\"cell\":{{\"x\":{d},\"y\":{d},\"z\":{d}}},\"bounds\":{{\"min_x\":{d:.3},\"min_z\":{d:.3},\"max_x\":{d:.3},\"max_z\":{d:.3}}},\"height\":{{\"min\":{d:.3},\"max\":{d:.3},\"avg\":{d:.3},\"center\":{d:.3},\"samples\":{d}}},\"material\":", .{
            idx,
            snapshot.cell.x,
            snapshot.cell.y,
            snapshot.cell.z,
            snapshot.bounds.min.x,
            snapshot.bounds.min.z,
            snapshot.bounds.max.x,
            snapshot.bounds.max.z,
            min_height,
            max_height,
            avg_height,
            center_height,
            heights.len,
        });
        try appendJsonString(allocator, &out, snapshot.material);
        try appendFmt(allocator, &out, ",\"paint_layers\":{d},\"splat_size\":{d},\"lod_index\":{d},\"lod_levels\":{d}}}", .{
            snapshot.paint_layers.len,
            snapshot.splat_size,
            entry.lod_index,
            snapshot.lod_levels.len,
        });
    }
    try appendFmt(allocator, &out, "]}}\n", .{});
    return out.toOwnedSlice(allocator);
}

fn undoBatchStatusJson(allocator: std.mem.Allocator, command: CommandFile, state: *const ProjectEditorState) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, 256);
    defer out.deinit(allocator);
    try appendFmt(allocator, &out, "{{\"ok\":true,\"id\":", .{});
    try appendJsonString(allocator, &out, command.id);
    try appendFmt(allocator, &out, ",\"command\":", .{});
    try appendJsonString(allocator, &out, command.name);
    try appendFmt(allocator, &out, ",\"undo_batch\":{{\"active\":{},\"depth\":{d},\"snapshot_taken\":{},\"label\":", .{
        state.undo_batch_depth > 0,
        state.undo_batch_depth,
        state.undo_batch_snapshot_taken,
    });
    try appendJsonString(allocator, &out, state.undo_batch_label_buf[0..state.undo_batch_label_len]);
    try appendFmt(allocator, &out, "}},\"undo_depth\":{d},\"redo_depth\":{d},\"status\":", .{
        state.undo_stack.items.len,
        state.redo_stack.items.len,
    });
    try appendJsonString(allocator, &out, state.status_buf[0..state.status_len]);
    try appendFmt(allocator, &out, "}}\n", .{});
    return out.toOwnedSlice(allocator);
}

fn appendSelection(allocator: std.mem.Allocator, out: *std.ArrayList(u8), state: *const ProjectEditorState) !void {
    try appendFmt(allocator, out, "{{\"scope\":", .{});
    try appendJsonString(allocator, out, state.selection_scope.label());
    try appendFmt(allocator, out, ",\"selected\":", .{});
    try appendSelectionObject(allocator, out, state, state.selected_object);
    try appendSelectionObjects(allocator, out, state);
    try appendFmt(allocator, out, ",\"hovered\":", .{});
    try appendSelectionObject(allocator, out, state, state.hovered_object);
    try appendMeshElementSelection(allocator, out, state);
    try appendShapeSourceSelection(allocator, out, state);
    try appendShapeOperationSelection(allocator, out, state);
    try appendGestureSelection(allocator, out, state);
    try appendFmt(allocator, out, "}}", .{});
}

fn appendMeshElementSelection(allocator: std.mem.Allocator, out: *std.ArrayList(u8), state: *const ProjectEditorState) !void {
    try appendFmt(allocator, out, ",\"element\":", .{});
    if (state.selected_face) |face| {
        try appendFmt(allocator, out, "{{\"kind\":\"face\",\"face_index\":{d}}}", .{face});
        return;
    }
    if (state.selected_edge) |edge| {
        try appendFmt(allocator, out, "{{\"kind\":\"edge\",\"a\":{d},\"b\":{d}}}", .{ edge[0], edge[1] });
        return;
    }
    if (state.selected_vertex) |vertex| {
        try appendFmt(allocator, out, "{{\"kind\":\"point\",\"index\":{d}}}", .{vertex});
        return;
    }
    try appendFmt(allocator, out, "null", .{});
}

fn appendShapeSourceSelection(allocator: std.mem.Allocator, out: *std.ArrayList(u8), state: *const ProjectEditorState) !void {
    try appendFmt(allocator, out, ",\"shape_source\":{{\"selected\":{},\"hovered\":{}", .{ state.selected_shape_source, state.hovered_shape_source });
    const source = shapeSourceForState(state);
    if (source) |value| {
        try appendFmt(allocator, out, ",\"active\":true,\"kind\":", .{});
        try appendJsonString(allocator, out, @tagName(value.kind));
        try appendFmt(allocator, out, ",\"points\":{d}", .{value.points.len});
        try appendShapeSourcePointItems(allocator, out, value.points);
        try appendShapeSourceBounds(allocator, out, value.points);
        if (value.validate()) |_| {
            try appendFmt(allocator, out, ",\"valid\":true,\"error\":null", .{});
        } else |err| {
            try appendFmt(allocator, out, ",\"valid\":false,\"error\":", .{});
            try appendJsonString(allocator, out, @errorName(err));
        }
    } else {
        try appendFmt(allocator, out, ",\"active\":false,\"kind\":null,\"points\":0,\"valid\":false,\"error\":\"NoActiveShapeSource\"", .{});
    }
    try appendFmt(allocator, out, "}}", .{});
}

fn appendShapeSourcePointItems(allocator: std.mem.Allocator, out: *std.ArrayList(u8), points: []const editor_math.Vec3) !void {
    try appendFmt(allocator, out, ",\"point_items\":[", .{});
    for (points, 0..) |point, index| {
        if (index > 0) try appendFmt(allocator, out, ",", .{});
        try appendFmt(allocator, out, "{{\"index\":{d},\"position\":", .{index});
        try appendVec3(allocator, out, point);
        try appendFmt(allocator, out, "}}", .{});
    }
    try appendFmt(allocator, out, "]", .{});
}

fn appendShapeSourceBounds(allocator: std.mem.Allocator, out: *std.ArrayList(u8), points: []const editor_math.Vec3) !void {
    if (points.len == 0) {
        try appendFmt(allocator, out, ",\"bounds\":null", .{});
        return;
    }
    var min = points[0];
    var max = points[0];
    for (points[1..]) |point| {
        min.x = @min(min.x, point.x);
        min.y = @min(min.y, point.y);
        min.z = @min(min.z, point.z);
        max.x = @max(max.x, point.x);
        max.y = @max(max.y, point.y);
        max.z = @max(max.z, point.z);
    }
    const span = editor_math.Vec3{ .x = max.x - min.x, .y = max.y - min.y, .z = max.z - min.z };
    try appendFmt(allocator, out, ",\"bounds\":{{\"min\":", .{});
    try appendVec3(allocator, out, min);
    try appendFmt(allocator, out, ",\"max\":", .{});
    try appendVec3(allocator, out, max);
    try appendFmt(allocator, out, ",\"span\":", .{});
    try appendVec3(allocator, out, span);
    try appendFmt(allocator, out, "}}", .{});
}

fn appendShapeOperationSelection(allocator: std.mem.Allocator, out: *std.ArrayList(u8), state: *const ProjectEditorState) !void {
    try appendFmt(allocator, out, ",\"shape_operation\":{{\"selected\":{},\"hovered\":{}", .{ state.selected_shape_operation, state.hovered_shape_operation });
    const operation = shapeOperationForState(state);
    try appendFmt(allocator, out, ",\"kind\":", .{});
    try appendJsonString(allocator, out, @tagName(operation.kind));
    try appendFmt(allocator, out, ",\"amount\":{d:.6},\"segments\":{d}", .{ operation.amount, operation.segments });
    if (shapeSourceForState(state)) |source| {
        if (operation.validateForSource(source)) |_| {
            try appendFmt(allocator, out, ",\"valid\":true,\"error\":null", .{});
        } else |err| {
            try appendFmt(allocator, out, ",\"valid\":false,\"error\":", .{});
            try appendJsonString(allocator, out, @errorName(err));
        }
    } else {
        try appendFmt(allocator, out, ",\"valid\":false,\"error\":\"NoActiveShapeSource\"", .{});
    }
    try appendFmt(allocator, out, "}}", .{});
}

fn appendGestureSelection(allocator: std.mem.Allocator, out: *std.ArrayList(u8), state: *const ProjectEditorState) !void {
    try appendFmt(allocator, out, ",\"gesture\":{{\"kind\":", .{});
    try appendJsonString(allocator, out, @tagName(state.active_gesture.kind));
    try appendFmt(allocator, out, ",\"phase\":", .{});
    try appendJsonString(allocator, out, @tagName(state.active_gesture.phase));
    if (state.active_gesture.numeric_override) |value| {
        try appendFmt(allocator, out, ",\"numeric_override\":{d:.6}", .{value});
    } else {
        try appendFmt(allocator, out, ",\"numeric_override\":null", .{});
    }
    try appendFmt(allocator, out, "}}", .{});
}

fn shapeSourceForState(state: *const ProjectEditorState) ?shape_source.Source {
    if (state.mode != .prop_creation or state.prop_tool != .edit) return null;
    if (state.prop_sketch_mode == .none) return null;
    if (state.prop_sketch_points.items.len == 0) return null;
    return .{
        .kind = switch (state.prop_sketch_mode) {
            .face => .closed_face,
            .curve => .open_profile,
            .path => .path,
            .none => .primitive_seed,
        },
        .points = state.prop_sketch_points.items,
    };
}

fn shapeOperationForState(state: *const ProjectEditorState) shape_operation.Operation {
    return .{
        .kind = switch (state.prop_sketch_mode) {
            .face => .solidify,
            .curve => .revolve,
            .path => .extrude,
            .none => .extrude,
        },
        .segments = state.prop_sketch_segments,
        .amount = state.prop_sketch_amount,
    };
}

fn selectionScopeFromName(name: []const u8) ?project_editor_state.SelectionScope {
    if (std.mem.eql(u8, name, "object")) return .object;
    if (std.mem.eql(u8, name, "face")) return .face;
    if (std.mem.eql(u8, name, "edge")) return .edge;
    if (std.mem.eql(u8, name, "point")) return .point;
    if (std.mem.eql(u8, name, "source")) return .source;
    if (std.mem.eql(u8, name, "operation")) return .operation;
    if (std.mem.eql(u8, name, "marker")) return .marker;
    return null;
}

fn appendSelectionObject(allocator: std.mem.Allocator, out: *std.ArrayList(u8), state: *const ProjectEditorState, index: ?usize) !void {
    const idx = index orelse {
        try appendFmt(allocator, out, "null", .{});
        return;
    };
    if (idx >= state.objects.items.len) return error.InvalidSelection;
    const obj = state.objects.items[idx];
    try appendFmt(allocator, out, "{{\"index\":{d},\"id\":{d},\"name\":", .{ idx, obj.id });
    try appendJsonString(allocator, out, obj.name);
    try appendFmt(allocator, out, ",\"kind\":", .{});
    try appendJsonString(allocator, out, if (obj.marker != null) "marker" else @tagName(obj.object_kind));
    if (obj.prop_asset_id) |asset_id| try appendPropShapeIntents(allocator, out, state, asset_id);
    if (obj.marker) |marker| {
        try appendFmt(allocator, out, ",\"marker\":{{\"kind\":", .{});
        try appendJsonString(allocator, out, marker.kind.name());
        try appendFmt(allocator, out, ",\"label\":", .{});
        try appendJsonString(allocator, out, marker.kind.label());
        try appendFmt(allocator, out, ",\"shape\":", .{});
        try appendJsonString(allocator, out, marker.shape.name());
        try appendFmt(allocator, out, ",\"marker_id\":", .{});
        try appendJsonString(allocator, out, marker.marker_id);
        try appendFmt(allocator, out, ",\"group\":", .{});
        try appendJsonString(allocator, out, marker.group);
        try appendFmt(allocator, out, ",\"binding\":", .{});
        try appendJsonString(allocator, out, marker.binding);
        try appendFmt(allocator, out, ",\"radius\":{d:.6},\"order\":{d}", .{ marker.radius, marker.order });
        try appendMarkerValidation(allocator, out, marker);
        try appendFmt(allocator, out, "}}", .{});
    }
    try appendFmt(allocator, out, "}}", .{});
}

fn appendSelectionObjects(allocator: std.mem.Allocator, out: *std.ArrayList(u8), state: *const ProjectEditorState) !void {
    try appendFmt(allocator, out, ",\"selected_many\":[", .{});
    var emitted: usize = 0;
    for (state.selected_object_ids.items) |object_id| {
        const idx = objectIndexByIdForSelection(state, object_id) orelse continue;
        if (emitted > 0) try appendFmt(allocator, out, ",", .{});
        try appendSelectionObject(allocator, out, state, idx);
        emitted += 1;
    }
    try appendFmt(allocator, out, "],\"selected_count\":{d}", .{emitted});
}

fn objectIndexByIdForSelection(state: *const ProjectEditorState, object_id: u64) ?usize {
    for (state.objects.items, 0..) |obj, idx| {
        if (obj.id == object_id) return idx;
    }
    return null;
}

fn appendPropShapeIntents(allocator: std.mem.Allocator, out: *std.ArrayList(u8), state: *const ProjectEditorState, asset_id: []const u8) !void {
    try appendFmt(allocator, out, ",\"prop_asset_id\":", .{});
    try appendJsonString(allocator, out, asset_id);
    try appendFmt(allocator, out, ",\"shape_intents\":", .{});
    var doc = loadPropAssetDocumentForDescribe(allocator, state, asset_id) catch |err| {
        try appendFmt(allocator, out, "{{\"count\":0,\"error\":", .{});
        try appendJsonString(allocator, out, @errorName(err));
        try appendFmt(allocator, out, "}}", .{});
        return;
    };
    defer doc.deinit(allocator);

    try appendFmt(allocator, out, "{{\"count\":{d}", .{doc.recipe.shape_intents.len});
    if (doc.recipe.shape_intents.len > 0) {
        const latest = doc.recipe.shape_intents[doc.recipe.shape_intents.len - 1];
        try appendFmt(allocator, out, ",\"latest\":{{\"id\":", .{});
        try appendJsonString(allocator, out, latest.id);
        try appendFmt(allocator, out, ",\"source\":", .{});
        try appendJsonString(allocator, out, prop_asset_doc.shapeSourceKindName(latest.source_kind));
        try appendFmt(allocator, out, ",\"operation\":", .{});
        try appendJsonString(allocator, out, prop_asset_doc.shapeOperationKindName(latest.operation_kind));
        try appendFmt(allocator, out, ",\"amount\":{d:.6},\"segments\":{d},\"points\":{d}", .{
            latest.amount,
            latest.segments,
            latest.points.len,
        });
        if (latest.source_kind == .primitive_seed) {
            try appendFmt(allocator, out, ",\"primitive\":", .{});
            try appendJsonString(allocator, out, prop_asset_doc.primitiveKindName(latest.primitive_kind));
            try appendFmt(allocator, out, ",\"primitive_params\":{{\"width\":{d:.6},\"height\":{d:.6},\"depth\":{d:.6},\"radius\":{d:.6},\"segments\":{d}}}", .{
                latest.primitive_params.width,
                latest.primitive_params.height,
                latest.primitive_params.depth,
                latest.primitive_params.radius,
                latest.primitive_params.segments,
            });
        }
        try appendFmt(allocator, out, "}}", .{});
    } else {
        try appendFmt(allocator, out, ",\"latest\":null", .{});
    }
    try appendFmt(allocator, out, "}}", .{});
}

fn loadPropAssetDocumentForDescribe(allocator: std.mem.Allocator, state: *const ProjectEditorState, asset_id: []const u8) !prop_asset_doc.PropAssetDocument {
    const path = try prop_asset_doc.documentPath(allocator, asset_id);
    defer allocator.free(path);
    var project_dir = try shared.scene_resolve.openProjectDir(state.io, state.project_path);
    defer project_dir.close(state.io);
    const bytes = try project_dir.readFileAlloc(state.io, path, allocator, .limited(1024 * 1024));
    defer allocator.free(bytes);
    return prop_asset_doc.parse(allocator, bytes);
}

fn appendMarkerValidation(allocator: std.mem.Allocator, out: *std.ArrayList(u8), marker: scene_marker.Marker) !void {
    if (marker.validate()) |_| {
        try appendFmt(allocator, out, ",\"valid\":true,\"error\":null", .{});
    } else |err| {
        try appendFmt(allocator, out, ",\"valid\":false,\"error\":", .{});
        try appendJsonString(allocator, out, @errorName(err));
    }
}

fn appendVec3(allocator: std.mem.Allocator, out: *std.ArrayList(u8), vec: editor_math.Vec3) !void {
    try appendFmt(allocator, out, "{{\"x\":{d:.6},\"y\":{d:.6},\"z\":{d:.6}}}", .{ vec.x, vec.y, vec.z });
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

fn makeCommandTestManager(allocator: std.mem.Allocator, workspace_path: []const u8, state_file_path: []const u8) !pm_state.ProjectManagerState {
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

test "project.create accepts preset and rejects unknown preset" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const workspace_len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const workspace_path = try allocator.dupe(u8, path_buf[0..workspace_len]);
    defer allocator.free(workspace_path);
    const state_file_path = try std.fs.path.join(allocator, &.{ workspace_path, "project_manager.json" });
    defer allocator.free(state_file_path);

    var manager = try makeCommandTestManager(allocator, workspace_path, state_file_path);
    defer manager.deinit();

    const project_path = try std.fs.path.join(allocator, &.{ workspace_path, "minimal" });
    defer allocator.free(project_path);

    const renderer: *editor_draw.SDL_Renderer = undefined;
    const viewport_gpu: *const editor_viewport_gpu.EditorViewportGpu = undefined;
    const host: *editor_core_ui.Host = undefined;
    const command = CommandFile{ .id = "mcp-test", .name = "project.create", .path = project_path, .preset = "Minimal" };
    const response = try executeCommand(allocator, std.testing.io, workspace_path, "Project Manager", null, &manager, renderer, viewport_gpu, host, .{}, command);
    allocator.free(response);

    const engine_path = try std.fs.path.join(allocator, &.{ project_path, "engine.kdl" });
    defer allocator.free(engine_path);
    const engine_bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, engine_path, allocator, .limited(4096));
    defer allocator.free(engine_bytes);
    var parsed = try friendly_engine.modules.parseProjectConfigBytes(allocator, engine_bytes);
    defer parsed.deinit();
    const minimal = pm_presets.builtinPresets()[0].modules;
    try std.testing.expectEqual(minimal.len, parsed.enabledModules().len);
    for (minimal, parsed.enabledModules()) |expected, actual| try std.testing.expectEqualStrings(expected, actual);

    const bad_command = CommandFile{ .id = "mcp-test-bad", .name = "project.create", .path = project_path, .preset = "Nope" };
    try std.testing.expectError(error.UnknownPreset, executeCommand(allocator, std.testing.io, workspace_path, "Project Manager", null, &manager, renderer, viewport_gpu, host, .{}, bad_command));
}

fn selectObject(state: *ProjectEditorState, idx: usize) void {
    state.selected_object = idx;
    state.selected_vertex = null;
    state.selected_edge = null;
    state.selected_face = null;
    project_editor_state.setStatus(state, "Object selected");
}

fn findObjectIndex(state: *const ProjectEditorState, target: []const u8) !usize {
    if (std.fmt.parseUnsigned(u64, target, 10)) |id| {
        for (state.objects.items, 0..) |obj, idx| {
            if (obj.id == id) return idx;
        }
    } else |_| {}
    for (state.objects.items, 0..) |obj, idx| {
        if (std.mem.eql(u8, obj.name, target)) return idx;
    }
    return error.ObjectNotFound;
}

fn sdlRectFromFRect(rect: editor_draw.SDL_FRect) sdl.SDL_Rect {
    return .{
        .x = @intFromFloat(@round(rect.x)),
        .y = @intFromFloat(@round(rect.y)),
        .w = @intFromFloat(@round(rect.w)),
        .h = @intFromFloat(@round(rect.h)),
    };
}

fn scaledSdlRectFromFRect(rect: editor_draw.SDL_FRect, scale: f32) sdl.SDL_Rect {
    return sdlRectFromFRect(.{
        .x = rect.x * scale,
        .y = rect.y * scale,
        .w = rect.w * scale,
        .h = rect.h * scale,
    });
}

fn makeProjectPath(io: std.Io, project_path: []const u8, rel_path: []const u8) !void {
    const full_path = try std.fs.path.join(std.heap.page_allocator, &.{ project_path, rel_path });
    defer std.heap.page_allocator.free(full_path);
    try std.Io.Dir.cwd().createDirPath(io, full_path);
}

test "findObjectIndex accepts id and name" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = try std.testing.allocator.dupe(u8, "."),
        .project_name = try std.testing.allocator.dupe(u8, "test"),
        .objects = .empty,
    };
    defer state.deinit();
    try state.objects.append(std.testing.allocator, .{
        .id = 42,
        .name = try std.testing.allocator.dupe(u8, "lookup target"),
        .mesh = .{
            .vertices = try std.testing.allocator.alloc(geometry.Vertex, 0),
            .indices = try std.testing.allocator.alloc(u32, 0),
        },
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = try std.testing.allocator.dupe(u8, ""),
        .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    });
    const idx_by_name = try findObjectIndex(&state, state.objects.items[0].name);
    try std.testing.expectEqual(@as(usize, 0), idx_by_name);
    var id_buf: [32]u8 = undefined;
    const id = try std.fmt.bufPrint(&id_buf, "{d}", .{state.objects.items[0].id});
    const idx_by_id = try findObjectIndex(&state, id);
    try std.testing.expectEqual(@as(usize, 0), idx_by_id);
}

test "sanitizedProjectName is readable and path-safe" {
    const name = try sanitizedProjectName(std.testing.allocator, "My Cool Project!");
    defer std.testing.allocator.free(name);
    try std.testing.expectEqualStrings("My-Cool-Project", name);

    const sanitized = try sanitizedProjectName(std.testing.allocator, "!!!");
    defer std.testing.allocator.free(sanitized);
    try std.testing.expectEqualStrings("project", sanitized);
}

test "appendWorldEditorState reports world curve UX state" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .mode = .world_creation,
        .world_tool = .roads,
        .selected_world_layer = .spline_road_main,
        .world_road_mode = .shape,
        .world_road_draw_mode = .freehand,
        .world_road_surface_mode = .prop_sections,
        .world_road_terrain_mode = .floating,
        .selected_road_edge_id = @constCast("main_road.edge.0"),
        .selected_road_handle = .start,
        .hovered_world_curve_hit = .{ .target = .road, .element = .point, .index = 1, .sub_index = 2, .distance_sq = 9 },
        .selected_world_curve_hit = .{ .target = .road, .element = .handle_start, .index = 3, .sub_index = 4, .distance_sq = 16 },
        .world_curve_drag_state = .{ .hit = .{ .target = .road, .element = .handle_start, .index = 3, .sub_index = 4 } },
    };
    try state.world_road_points.append(std.testing.allocator, .{ .x = 1, .y = 0, .z = 2 });
    defer state.world_road_points.deinit(std.testing.allocator);

    var out = try std.ArrayList(u8).initCapacity(std.testing.allocator, 512);
    defer out.deinit(std.testing.allocator);
    try appendWorldEditorState(std.testing.allocator, &out, &state);
    const json = out.items;

    try std.testing.expect(std.mem.indexOf(u8, json, "\"tool\":\"roads\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"layer\":\"spline_road_main\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"road_mode\":\"shape\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"road_draw_mode\":\"freehand\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"road_surface_mode\":\"prop_sections\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"road_terrain_mode\":\"floating\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"road_draft_points\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"selected_road_edge\":\"main_road.edge.0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"selected_road_handle\":\"start\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"hovered_curve_hit\":{\"target\":\"road\",\"element\":\"point\",\"index\":1,\"sub_index\":2,\"distance_sq\":9.000}") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"selected_curve_hit\":{\"target\":\"road\",\"element\":\"handle_start\",\"index\":3,\"sub_index\":4,\"distance_sq\":16.000}") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"drag_curve_hit\":{\"target\":\"road\",\"element\":\"handle_start\",\"index\":3,\"sub_index\":4,\"distance_sq\":null}") != null);
}

test "world tool catalog commands are listed only in world mode" {
    const roads_entry = shared.editor_command_catalog.Entry{
        .id = shared.editor_command_ids.world_roads,
        .label = "Roads",
        .screen = shared.editor_command_catalog.project_editor_screen,
        .section = "world creation",
    };
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .mode = .world_creation,
    };

    try std.testing.expect(editor_commands_catalog.commandAvailableInContext(roads_entry, &state, null));
    state.mode = .layout;
    try std.testing.expect(!editor_commands_catalog.commandAvailableInContext(roads_entry, &state, null));
}

test "delete command is available for visible world curve selection" {
    const delete_entry = shared.editor_command_catalog.Entry{
        .id = "ed-delete",
        .label = "Delete",
        .screen = shared.editor_command_catalog.project_editor_screen,
        .section = "left rail",
    };
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .mode = .world_creation,
        .world_tool = .water,
    };

    try std.testing.expect(!editor_commands_catalog.commandAvailableInContext(delete_entry, &state, null));

    state.selected_world_curve_hit = .{ .target = .water_volume, .element = .handle_start };
    try std.testing.expect(editor_commands_catalog.commandAvailableInContext(delete_entry, &state, null));

    state.mode = .layout;
    try std.testing.expect(!editor_commands_catalog.commandAvailableInContext(delete_entry, &state, null));
}

test "selection describe reports invalid active shape source and operation" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .mode = .prop_creation,
        .prop_tool = .edit,
        .prop_sketch_mode = .face,
        .prop_sketch_amount = 0.125,
        .prop_sketch_segments = 32,
        .selected_shape_source = true,
    };
    defer state.prop_sketch_points.deinit(std.testing.allocator);
    try state.prop_sketch_points.append(std.testing.allocator, .{ .x = 0, .y = 0, .z = 0 });
    try state.prop_sketch_points.append(std.testing.allocator, .{ .x = 1, .y = 0, .z = 0 });

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(std.testing.allocator);
    try appendSelection(std.testing.allocator, &out, &state);

    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"shape_source\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"active\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"valid\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "NotEnoughShapePoints") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"amount\":0.125000") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"segments\":32") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"point_items\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"index\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"span\":{\"x\":1.000000,\"y\":0.000000,\"z\":0.000000}") != null);
}

test "selection describe includes selected mesh element" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .selection_scope = .edge,
        .selected_edge = .{ 2, 5 },
    };

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(std.testing.allocator);
    try appendSelection(std.testing.allocator, &out, &state);

    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"element\":{\"kind\":\"edge\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"a\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"b\":5") != null);
}

test "selection describe includes active gesture lifecycle" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
    };
    state.active_gesture.begin(.marker_place);
    state.active_gesture.commit();

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(std.testing.allocator);
    try appendSelection(std.testing.allocator, &out, &state);

    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"gesture\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"kind\":\"marker_place\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"phase\":\"committed\"") != null);
}

test "selection describe includes selected marker validation details" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .selection_scope = .marker,
    };
    defer state.deinit();
    var marker = try scene_marker.defaultForKind(std.testing.allocator, .player_start);
    errdefer marker.deinit(std.testing.allocator);
    try state.objects.append(std.testing.allocator, .{
        .id = 12,
        .name = try std.testing.allocator.dupe(u8, "Player Start Marker"),
        .mesh = .{ .vertices = &.{}, .indices = &.{} },
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = try std.testing.allocator.dupe(u8, ""),
        .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .object_kind = .marker,
        .marker = marker,
    });
    state.selected_object = 0;

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(std.testing.allocator);
    try appendSelection(std.testing.allocator, &out, &state);

    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"marker\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"kind\":\"player_start\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"valid\":true") != null);
}

test "selection describe includes persisted prop shape intent summary" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "props");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "props/intent_panel.kdl", .data =
        \\prop_asset version=1 id="intent_panel" label="Intent Panel" tags="shape" deleted=false {
        \\  recipe {
        \\    shape id="shape_1" source=closed_face operation=solidify amount=0.08 segments=24 points="-1,0,-1;1,0,-1;1,0,1;-1,0,1"
        \\  }
        \\  mesh asset="props/meshes/intent_panel.fmesh"
        \\  material base_color="255,255,255,255"
        \\  variants count=1
        \\}
        \\
    });
    const project_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(project_path);

    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = try std.testing.allocator.dupe(u8, project_path),
        .project_name = try std.testing.allocator.dupe(u8, ""),
        .objects = .empty,
    };
    defer state.deinit();
    try state.objects.append(std.testing.allocator, .{
        .id = 21,
        .name = try std.testing.allocator.dupe(u8, "Intent Panel"),
        .mesh = .{ .vertices = &.{}, .indices = &.{} },
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = try std.testing.allocator.dupe(u8, ""),
        .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .prop_asset_id = try std.testing.allocator.dupe(u8, "intent_panel"),
    });
    state.selected_object = 0;

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(std.testing.allocator);
    try appendSelection(std.testing.allocator, &out, &state);

    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"prop_asset_id\":\"intent_panel\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"shape_intents\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"source\":\"closed_face\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"operation\":\"solidify\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"points\":4") != null);
}

test "selection describe includes primitive seed metadata for persisted shape intent" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "props");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "props/seed_panel.kdl", .data =
        \\prop_asset version=1 id="seed_panel" label="Seed Panel" tags="shape" deleted=false {
        \\  recipe {
        \\    shape id="shape_1" source=primitive_seed operation=extrude amount=1 segments=12 primitive=cylinder width=1 height=2 depth=1 radius=0.35 points=""
        \\  }
        \\  mesh asset="props/meshes/seed_panel.fmesh"
        \\  material base_color="255,255,255,255"
        \\  variants count=1
        \\}
        \\
    });
    const project_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(project_path);

    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = try std.testing.allocator.dupe(u8, project_path),
        .project_name = try std.testing.allocator.dupe(u8, ""),
        .objects = .empty,
    };
    defer state.deinit();
    try state.objects.append(std.testing.allocator, .{
        .id = 22,
        .name = try std.testing.allocator.dupe(u8, "Seed Panel"),
        .mesh = .{ .vertices = &.{}, .indices = &.{} },
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = try std.testing.allocator.dupe(u8, ""),
        .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .prop_asset_id = try std.testing.allocator.dupe(u8, "seed_panel"),
    });
    state.selected_object = 0;

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(std.testing.allocator);
    try appendSelection(std.testing.allocator, &out, &state);

    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"source\":\"primitive_seed\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"primitive\":\"cylinder\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"radius\":0.350000") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"segments\":12") != null);
}

test "marker update persists invalid data and reports validation" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
    };
    defer state.deinit();
    var marker = try scene_marker.defaultForKind(std.testing.allocator, .player_start);
    errdefer marker.deinit(std.testing.allocator);
    try state.objects.append(std.testing.allocator, .{
        .id = 13,
        .name = try std.testing.allocator.dupe(u8, "Player Start Marker"),
        .mesh = .{ .vertices = &.{}, .indices = &.{} },
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = try std.testing.allocator.dupe(u8, ""),
        .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .object_kind = .marker,
        .marker = marker,
    });

    const command = CommandFile{
        .id = "test-marker-update",
        .name = "marker.update",
        .object = "Player Start Marker",
        .binding = "",
    };
    const json = try updateGameplayMarker(std.testing.allocator, command, &state);
    defer std.testing.allocator.free(json);

    try std.testing.expect(state.scene_dirty);
    try std.testing.expectEqual(@as(?usize, 0), state.selected_object);
    try std.testing.expectError(error.MissingMarkerBinding, state.objects.items[0].marker.?.validate());
    try std.testing.expect(std.mem.indexOf(u8, json, "\"valid\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "MissingMarkerBinding") != null);
}

test "mcp region command fuzz parses or rejects without partial cells" {
    var prng = std.Random.DefaultPrng.init(0x6d63705f636d6431);
    var random = prng.random();
    var payload_buf: [256]u8 = undefined;
    var cells_buf: [96]u8 = undefined;

    var i: usize = 0;
    while (i < 512) : (i += 1) {
        const cells = randomRegionCellText(&random, &cells_buf, i);
        const payload = try std.fmt.bufPrint(
            &payload_buf,
            "{{\"id\":\"fuzz-{d}\",\"name\":\"world.region-upsert\",\"object\":\"region-{d}\",\"cells\":\"{s}\"}}",
            .{ i, i, cells },
        );

        var parsed = std.json.parseFromSlice(CommandFile, std.testing.allocator, payload, .{ .ignore_unknown_fields = true }) catch continue;
        defer parsed.deinit();
        try std.testing.expectEqualStrings("world.region-upsert", parsed.value.name);
        if (parsed.value.cells) |cell_text| {
            const parsed_cells = editor_commands_world_regions.parseWorldRegionCells(std.testing.allocator, cell_text) catch continue;
            defer std.testing.allocator.free(parsed_cells);
            for (parsed_cells, 0..) |cell_id, index| {
                try std.testing.expectEqual(@as(i32, 0), cell_id.z);
                var prior_index: usize = 0;
                while (prior_index < index) : (prior_index += 1) {
                    try std.testing.expect(!parsed_cells[prior_index].eql(cell_id));
                }
            }
        }
    }
}

fn randomRegionCellText(random: *std.Random, out: []u8, iteration: usize) []const u8 {
    const alphabet = "0123456789,-; abcxyz\"\\\n";
    const len = 1 + random.uintLessThan(usize, out.len - 1);
    for (out[0..len]) |*byte| {
        byte.* = alphabet[random.uintLessThan(usize, alphabet.len)];
    }
    if (iteration % 8 == 0) {
        return std.fmt.bufPrint(out, "{d},{d},0;{d},{d},0", .{
            @as(i32, @intCast(iteration % 17)),
            -@as(i32, @intCast(iteration % 13)),
            @as(i32, @intCast((iteration + 3) % 19)),
            @as(i32, @intCast((iteration + 5) % 11)),
        }) catch out[0..len];
    }
    return out[0..len];
}
