const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const desktop_backend = @import("desktop_backend.zig");
const editor_commands = @import("editor_commands.zig");
const editor_core_ui = @import("editor_core_ui.zig");
const editor_display = @import("editor_display.zig");
const editor_draw = @import("editor_draw.zig");
const editor_frame_perf = @import("editor_frame_perf.zig");
const editor_settings = @import("editor_settings.zig");
const editor_viewport_gpu = @import("editor_viewport_gpu.zig");
const project_editor = @import("project_editor.zig");
const project_editor_preferences = @import("project_editor_preferences.zig");
const project_editor_prop_dialog = @import("project_editor_prop_dialog.zig");
const menu = @import("menu.zig");
const options = @import("options.zig");
const pm_state = @import("pm_state.zig");
const pm_ui = @import("pm_ui.zig");
const pm_util = @import("pm_util.zig");

const log = std.log.scoped(.editor);
const core_ui = friendly_engine.modules.core_ui;

const SDL_INIT_VIDEO = editor_draw.SDL_INIT_VIDEO;
const SDL_INIT_GAMEPAD = editor_draw.SDL_INIT_GAMEPAD;
const loading_screen_delay_s = 2.0;

const SDL_Window = editor_draw.SDL_Window;
const SDL_Renderer = editor_draw.SDL_Renderer;
const SDL_Event = editor_draw.SDL_Event;

const SDL_Init = editor_draw.SDL_Init;
const SDL_Quit = editor_draw.SDL_Quit;
const SDL_CreateWindow = editor_draw.SDL_CreateWindow;
const SDL_DestroyWindow = editor_draw.SDL_DestroyWindow;
const SDL_CreateRenderer = editor_draw.SDL_CreateRenderer;
const SDL_CreateGPURenderer = editor_draw.SDL_CreateGPURenderer;
const SDL_DestroyRenderer = editor_draw.SDL_DestroyRenderer;
const SDL_Delay = editor_draw.SDL_Delay;
const SDL_PollEvent = editor_draw.SDL_PollEvent;
const SDL_StartTextInput = editor_draw.SDL_StartTextInput;
const SDL_StopTextInput = editor_draw.SDL_StopTextInput;
const default_window_w = 1920;
const default_window_h = 1080;

pub fn runEditor(init: std.process.Init) !void {
    const run_options = try options.parseOptions(init.minimal.args, std.heap.page_allocator);
    if (run_options.help) {
        std.debug.print(
            \\ friendly_engine_editor options:
            \\  --frames <n>   Run for n frames then exit.
            \\  --gpu          Require SDL3 GPU viewport (Metal/Vulkan/D3D12).
            \\  --software     Force software viewport rasterizer.
            \\  --render-settings <k=v,...>
            \\                 Render settings, e.g. antialiasing=4x.
            \\  --open-current Open the current workspace directly in the editor.
            \\  --help         Show this help text.
            \\
        , .{});
        return;
    }
    log.info("starting runtime open_current={} render={s}", .{
        run_options.open_current,
        @tagName(run_options.render_mode),
    });

    const config = friendly_engine.EngineConfig{
        .runtime = .editor,
    };

    var boot = if (run_options.open_current)
        try friendly_engine.bootstrap.bootWorld(
            std.heap.page_allocator,
            init.io,
            config,
            "engine.kdl",
        )
    else
        try friendly_engine.bootstrap.bootEngineOnly(
            std.heap.page_allocator,
            init.io,
            config,
        );
    defer boot.deinit();
    const world = &boot.world;
    friendly_engine.game.setActiveWorld(world);

    const current_project_path = try std.process.currentPathAlloc(init.io, std.heap.page_allocator);
    defer std.heap.page_allocator.free(current_project_path);
    var boot_project_open = run_options.open_current;

    var persistence_backend = try shared.file_persistence.FilePersistenceBackend.init(
        std.heap.page_allocator,
        init.io,
        current_project_path,
    );
    defer persistence_backend.deinit();
    persistence_backend.install(world);

    var audio_backend = shared.sdl_audio.SdlAudioBackend.init(std.heap.page_allocator);
    defer audio_backend.deinit();
    if (config.enable_audio) {
        audio_backend.install(world);
    }

    var backend = desktop_backend.DesktopClientBackend.init();
    backend.install(world, config.enable_renderer);

    if (!SDL_Init(SDL_INIT_VIDEO | SDL_INIT_GAMEPAD)) {
        log.err("SDL init failed: {s}", .{pm_util.sdlError()});
        return error.SdlInitFailed;
    }
    defer SDL_Quit();

    const window = SDL_CreateWindow(
        "friendly-engine editor",
        default_window_w,
        default_window_h,
        editor_draw.SDL_WINDOW_RESIZABLE | editor_draw.SDL_WINDOW_HIGH_PIXEL_DENSITY,
    ) orelse {
        log.err("SDL window creation failed: {s}", .{pm_util.sdlError()});
        return error.SdlWindowCreationFailed;
    };
    defer SDL_DestroyWindow(window);

    var viewport_gpu = editor_viewport_gpu.EditorViewportGpu.init(std.heap.page_allocator, run_options.render_mode);
    try viewport_gpu.setRenderSettings(run_options.render_settings);
    defer viewport_gpu.deinit();
    try viewport_gpu.initForWindow(window);
    viewport_gpu.logRenderBackend();

    const renderer = if (viewport_gpu.gpu_device) |gpu_device| blk: {
        break :blk SDL_CreateGPURenderer(@ptrCast(gpu_device), window) orelse {
            log.err("SDL GPU renderer creation failed: {s}", .{pm_util.sdlError()});
            return error.SdlGpuRendererCreationFailed;
        };
    } else blk: {
        break :blk SDL_CreateRenderer(window, null) orelse {
            log.err("SDL renderer creation failed: {s}", .{pm_util.sdlError()});
            return error.SdlRendererCreationFailed;
        };
    };
    defer SDL_DestroyRenderer(renderer);

    const ui_font_path = try std.fs.path.join(std.heap.page_allocator, &.{
        current_project_path,
        editor_draw.required_ui_font_path,
    });
    defer std.heap.page_allocator.free(ui_font_path);
    var text_renderer = try editor_draw.initRequiredTextRenderer(std.heap.page_allocator, init.io, renderer, ui_font_path, 18);
    defer text_renderer.deinit();

    var core_ui_host = editor_core_ui.Host.init(std.heap.page_allocator);
    defer core_ui_host.deinit();
    defer {
        var maybe_gpu: ?*shared.gpu_api.GpuRenderer = null;
        if (viewport_gpu.gpu_renderer) |*gpu| maybe_gpu = gpu;
        core_ui_host.deinitGpu(maybe_gpu);
    }

    var settings = try editor_settings.load(
        std.heap.page_allocator,
        init.io,
        init.environ_map,
    );
    defer settings.deinit(std.heap.page_allocator);
    core_ui_host.style = settings.style;
    log.info("loaded editor settings={s} theme={s}", .{ settings.settings_file_path, settings.theme_path });
    var preferences = project_editor_preferences.Context{
        .allocator = std.heap.page_allocator,
        .io = init.io,
        .host = &core_ui_host,
        .settings = &settings,
    };

    // New projects start from the explicit default gem set (minimal engine core
    // + editor modes), not the editor's own full config.
    var starter_config = try friendly_engine.modules.defaultProjectConfig(std.heap.page_allocator);
    defer starter_config.deinit();
    var pm = try pm_state.ProjectManagerState.init(
        std.heap.page_allocator,
        init.io,
        init.environ_map,
        current_project_path,
        starter_config.enabledModules(),
        config.enable_renderer,
    );
    defer pm.deinit();

    pm.window = window;
    menu.fe_menubar_install();

    if (!SDL_StartTextInput(window)) {
        log.warn("SDL text input start failed: {s}", .{pm_util.sdlError()});
    }
    defer _ = SDL_StopTextInput(window);

    const AppScreen = enum {
        project_manager,
        project_editor,
    };

    var screen: AppScreen = if (run_options.open_current) .project_editor else .project_manager;
    var editor_state: ?project_editor.ProjectEditorState = null;
    defer if (editor_state) |*ed| ed.deinit();
    var loading_project: ?*LoadingProject = null;
    defer if (loading_project) |loading| loading.deinit();
    if (run_options.open_current) {
        loading_project = try LoadingProject.start(
            std.heap.page_allocator,
            init.io,
            current_project_path,
            std.fs.path.basename(current_project_path),
        );
    }

    var frame_count: u64 = 0;
    var pending_screenshot: ?editor_commands.PendingScreenshot = null;
    defer if (pending_screenshot) |*pending| pending.deinit(std.heap.page_allocator);
    var pending_turntable: ?editor_commands.PendingTurntableCapture = null;
    defer if (pending_turntable) |*pending| pending.deinit(std.heap.page_allocator);
    var control_server = try editor_commands.ControlServer.init(std.heap.page_allocator, init.io);
    try control_server.start();
    defer control_server.deinit();
    var frame_clock = friendly_engine.core.time.FrameClock.init();
    var frame_timer = friendly_engine.core.time.Stopwatch.start();
    var pm_frame_perf = editor_frame_perf.FramePerf{};
    var running = true;
    while (running) {
        frame_timer.restart();
        frame_clock.tick();
        const active_perf: *editor_frame_perf.FramePerf = blk: {
            if (screen == .project_editor) {
                if (editor_state) |*ed| break :blk &ed.frame_perf;
            }
            break :blk &pm_frame_perf;
        };
        active_perf.beginFrame();
        core_ui_host.beginEventFrame();
        var event: SDL_Event = undefined;
        while (SDL_PollEvent(&event)) {
            try core_ui_host.feedEvent(&event);
        }
        if (!running) break;
        active_perf.mark(.events);

        if (screen == .project_manager) {
            running = try pm.processPending(window);
            if (!running) break;

            if (pm.pending_open_editor) {
                pm.pending_open_editor = false;
                if (loading_project == null) {
                    const entry = pm.projects.items[pm.selected_index];
                    loading_project = try LoadingProject.start(
                        std.heap.page_allocator,
                        init.io,
                        entry.path,
                        entry.name,
                    );
                }
            }
        }

        if (loading_project) |loading| {
            if (loading.isDone()) {
                var loaded = try loading.takeResult();
                loaded.window = window;
                try editor_commands.ensureProjectDirs(init.io, loaded.project_path);
                if (editor_state) |*ed| ed.deinit();
                loaded.terrain_undo_limit_mb = settings.terrain_undo_limit_mb;
                const opened_project_path = loaded.project_path;
                editor_state = loaded;
                loading.deinit();
                loading_project = null;
                screen = .project_editor;
                // Re-resolve project + editor gems from the opened project's
                // engine.kdl over the persistent engine scope, so switching
                // projects honors each project's enabled gem set.
                if (!boot_project_open or !std.mem.eql(u8, opened_project_path, current_project_path)) {
                    try boot.reloadProjectModules(std.heap.page_allocator, init.io, opened_project_path);
                    boot_project_open = true;
                }
            }
        }

        try friendly_engine.game.tickClient(world);
        try world.tick();
        active_perf.mark(.simulation);
        core_ui_host.beginFrame();
        frame_count += 1;

        const display = try editor_display.query(window, renderer);
        const show_loading_screen = if (loading_project) |loading| loading.shouldShowLoadingScreen() else false;

        if (show_loading_screen) {
            try renderLoadingScreen(renderer, &text_renderer, &core_ui_host, &viewport_gpu, display, loading_project.?);
        } else switch (screen) {
            .project_manager => {
                active_perf.mark(.project_manager_render);
                running = try pm_ui.renderEditorUi(
                    std.heap.page_allocator,
                    init.io,
                    renderer,
                    &text_renderer,
                    &pm,
                    &core_ui_host,
                    &viewport_gpu,
                    display,
                    &pending_screenshot,
                );
                const workspace_name = std.fs.path.basename(current_project_path);
                try editor_commands.processPendingProjectManager(
                    std.heap.page_allocator,
                    init.io,
                    &control_server,
                    &pm,
                    current_project_path,
                    workspace_name,
                    renderer,
                    &viewport_gpu,
                    &core_ui_host,
                    &pending_screenshot,
                );
            },
            .project_editor => {
                if (editor_state) |*ed| {
                    ed.control_stats = control_server.statsSnapshot();
                    active_perf.mark(.editor_update);
                    ed.update(@floatCast(frame_clock.delta_seconds));
                    project_editor_prop_dialog.processPendingPropDialog(ed);
                    const action = try ed.render(renderer, &text_renderer, display, &viewport_gpu, &core_ui_host, &preferences, &pending_screenshot, &pending_turntable);
                    try editor_commands.processPending(std.heap.page_allocator, init.io, &control_server, ed, renderer, &viewport_gpu, &core_ui_host, &pending_screenshot, &pending_turntable);
                    ed.control_stats = control_server.statsSnapshot();
                    switch (action) {
                        .continue_ => {},
                        .close_project => {
                            ed.deinit();
                            editor_state = null;
                            screen = .project_manager;
                            pm.setStatus("Returned to Project Manager");
                            // Tear down editor + project gems; engine scope keeps running.
                            try boot.closeProject();
                        },
                        .quit_app => running = false,
                    }
                } else {
                    try renderBlankFrame(renderer, &viewport_gpu, display);
                }
            },
        }

        if (run_options.frame_limit) |limit| {
            if (frame_count >= limit) {
                running = false;
            }
        }

        const frame_ms = frame_timer.elapsedSeconds() * 1000.0;
        const frame_fps = if (frame_clock.delta_seconds > 0) 1.0 / frame_clock.delta_seconds else 0;
        var sleep_ms: f64 = 0;
        if (targetFrameMs(settings.refresh_rate_hz)) |target_ms| {
            const remaining_ms = target_ms - frame_ms;
            if (remaining_ms > 1.0) {
                const sleep_start = friendly_engine.core.time.Stopwatch.start();
                SDL_Delay(@intFromFloat(remaining_ms));
                sleep_ms = sleep_start.elapsedSeconds() * 1000.0;
            }
        }
        active_perf.recordScope(.frame_sleep, sleep_ms);
        active_perf.endFrame(frame_ms + sleep_ms, frame_fps);
    }

    log.info(
        "runtime stopped frames={d} font={s}",
        .{ frame_count, ui_font_path },
    );
}

const LoadingProject = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []u8,
    project_name: []u8,
    timer: friendly_engine.core.time.Stopwatch,
    done: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    thread: ?std.Thread = null,
    result: ?project_editor.ProjectEditorState = null,
    err: ?anyerror = null,

    fn start(allocator: std.mem.Allocator, io: std.Io, project_path: []const u8, project_name: []const u8) !*LoadingProject {
        const owned_project_path = try allocator.dupe(u8, project_path);
        errdefer allocator.free(owned_project_path);
        const owned_project_name = try allocator.dupe(u8, project_name);
        errdefer allocator.free(owned_project_name);

        const loading = try allocator.create(LoadingProject);
        errdefer allocator.destroy(loading);
        loading.* = .{
            .allocator = allocator,
            .io = io,
            .project_path = owned_project_path,
            .project_name = owned_project_name,
            .timer = friendly_engine.core.time.Stopwatch.start(),
        };
        loading.thread = try std.Thread.spawn(.{}, loadProjectThread, .{loading});
        return loading;
    }

    fn deinit(self: *LoadingProject) void {
        if (self.thread) |thread| thread.join();
        if (self.result) |*state| state.deinit();
        self.allocator.free(self.project_path);
        self.allocator.free(self.project_name);
        self.allocator.destroy(self);
    }

    fn isDone(self: *const LoadingProject) bool {
        return self.done.load(.acquire);
    }

    fn shouldShowLoadingScreen(self: *const LoadingProject) bool {
        return self.timer.elapsedSeconds() >= loading_screen_delay_s;
    }

    fn takeResult(self: *LoadingProject) !project_editor.ProjectEditorState {
        std.debug.assert(self.isDone());
        if (self.thread) |thread| {
            thread.join();
            self.thread = null;
        }
        if (self.err) |err| return err;
        const loaded = self.result orelse return error.ProjectLoadFinishedWithoutState;
        self.result = null;
        return loaded;
    }
};

fn loadProjectThread(loading: *LoadingProject) void {
    loading.result = project_editor.ProjectEditorState.init(
        loading.allocator,
        loading.io,
        loading.project_path,
        loading.project_name,
    ) catch |err| {
        loading.err = err;
        loading.done.store(true, .release);
        return;
    };
    loading.done.store(true, .release);
}

fn renderLoadingScreen(
    renderer: *SDL_Renderer,
    text_renderer: *editor_draw.TextRenderer,
    host: *editor_core_ui.Host,
    viewport_gpu: ?*editor_viewport_gpu.EditorViewportGpu,
    display: editor_display.Metrics,
    loading: *const LoadingProject,
) !void {
    host.setFrameBounds(.{ .x = 0, .y = 0, .w = display.logical_w, .h = display.logical_h });
    try buildLoadingUi(&host.ui, @constCast(loading));

    const bg = shared.color.Color{ .r = 18, .g = 22, .b = 30, .a = 255 };
    if (viewport_gpu != null and viewport_gpu.?.use_gpu) {
        const gpu = &viewport_gpu.?.gpu_renderer.?;
        try gpu.beginFrame(display.pixel_w, display.pixel_h, bg);
        try host.drawGpu(gpu, text_renderer, display.scale);
        try gpu.endFrame();
        return;
    }

    try editor_display.applySdlScale(renderer, display.scale);
    if (!editor_draw.SDL_SetRenderDrawColor(renderer, bg.r, bg.g, bg.b, bg.a)) return error.SdlColorSetFailed;
    if (!editor_draw.SDL_RenderClear(renderer)) return error.SdlClearFailed;
    try host.draw(renderer, text_renderer);
    if (!editor_draw.SDL_RenderPresent(renderer)) return error.SdlPresentFailed;
}

fn targetFrameMs(refresh_rate_hz: ?u32) ?f64 {
    const hz = refresh_rate_hz orelse return null;
    return 1000.0 / @as(f64, @floatFromInt(hz));
}

fn buildLoadingUi(ui: *core_ui.UiContext, context: *anyopaque) !void {
    const loading: *const LoadingProject = @ptrCast(@alignCast(context));
    const bounds = ui.frame_bounds;
    const panel_w = @min(360.0, @max(280.0, bounds.w - 48.0));
    const panel_h = 96.0;
    try ui.beginPanel(.{
        .id = "loading-project",
        .rect = .{
            .x = @max(24.0, (bounds.w - panel_w) * 0.5),
            .y = @max(24.0, (bounds.h - panel_h) * 0.5),
            .w = panel_w,
            .h = panel_h,
        },
        .row_height = 24.0,
    });
    try ui.label("Loading scene");
    try ui.label(loading.project_name);
    ui.endPanel();
}

fn renderBlankFrame(
    renderer: *SDL_Renderer,
    viewport_gpu: ?*editor_viewport_gpu.EditorViewportGpu,
    display: editor_display.Metrics,
) !void {
    const bg = shared.color.Color{ .r = 18, .g = 22, .b = 30, .a = 255 };
    if (viewport_gpu != null and viewport_gpu.?.use_gpu) {
        const gpu = &viewport_gpu.?.gpu_renderer.?;
        try gpu.beginFrame(display.pixel_w, display.pixel_h, bg);
        try gpu.endFrame();
        return;
    }

    try editor_display.applySdlScale(renderer, display.scale);
    if (!editor_draw.SDL_SetRenderDrawColor(renderer, bg.r, bg.g, bg.b, bg.a)) return error.SdlColorSetFailed;
    if (!editor_draw.SDL_RenderClear(renderer)) return error.SdlClearFailed;
    if (!editor_draw.SDL_RenderPresent(renderer)) return error.SdlPresentFailed;
}
