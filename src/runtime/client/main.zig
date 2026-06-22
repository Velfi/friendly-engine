const std = @import("std");
const friendly_engine = @import("friendly_engine");
const desktop_backend = @import("desktop_backend.zig");
const lua_controller_backend = @import("lua_controller_backend.zig");
const scene_view = @import("scene_view.zig");
const scene_bootstrap = @import("scene_bootstrap.zig");
const client_atmosphere = @import("client_atmosphere.zig");
const shared = @import("runtime_shared");
const sdl = shared.sdl;

pub const std_options: std.Options = .{
    .logFn = friendly_engine.core.logging.logFn,
};

const log = std.log.scoped(.client);

const LifecycleStage = struct {
    name: []const u8,
    start_ns: i128,

    fn begin(comptime name: []const u8) LifecycleStage {
        log.info("startup.{s}.begin", .{name});
        return .{
            .name = name,
            .start_ns = friendly_engine.core.diagnostics.scopedTimerStart(),
        };
    }

    fn end(self: LifecycleStage) void {
        log.info("startup.{s}.end elapsed_ms={d:.3}", .{
            self.name,
            elapsedMs(self.start_ns),
        });
    }

    fn fail(self: LifecycleStage, err: anyerror) void {
        log.err("startup.{s}.fail err={s} elapsed_ms={d:.3}", .{
            self.name,
            @errorName(err),
            elapsedMs(self.start_ns),
        });
    }
};

fn elapsedMs(start_ns: i128) f64 {
    const elapsed_ns = friendly_engine.core.diagnostics.scopedTimerElapsedNs(start_ns);
    return @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, @floatFromInt(std.time.ns_per_ms));
}

pub fn main(init: std.process.Init) !void {
    run(init) catch |err| {
        log.err("runtime exited with error: {s}", .{@errorName(err)});
        return err;
    };
}

fn run(init: std.process.Init) !void {
    const options = try parseOptions(init.minimal.args, std.heap.page_allocator);
    if (options.help) {
        std.debug.print(
            \\ friendly_engine_client options:
            \\  --project <path>  Project folder to load (default: current directory).
            \\  --startup-scene <path>
            \\                    Override the project startup scene for this run.
            \\  --no-startup-world
            \\                    Boot the startup scene directly without streaming its configured world.
            \\  --no-startup-bundle
            \\                    Load scene assets from project files instead of startup_bundle.
            \\  --frames <n>      Run for n frames then exit.
            \\  --screenshot <path>
            \\                    Save the final presented GPU-rendered frame.
            \\  --headless        Skip window creation and run fixed ticks.
            \\  --render-settings <k=v,...>
            \\                    Render settings, e.g. antialiasing=4x.
            \\  --help            Show this help text.
            \\
        , .{});
        return;
    }
    log.info("startup.runtime.begin project={s} headless={} frame_limit={s}", .{
        options.project_path,
        options.headless,
        if (options.frame_limit == null) "none" else "set",
    });

    const config = friendly_engine.EngineConfig{
        .runtime = .client,
    };

    const bootstrap_stage = LifecycleStage.begin("bootstrap");
    var boot = friendly_engine.bootstrap.bootWorldInProject(
        std.heap.page_allocator,
        init.io,
        config,
        options.project_path,
        "engine.kdl",
    ) catch |err| {
        bootstrap_stage.fail(err);
        return err;
    };
    bootstrap_stage.end();
    defer boot.deinit();
    const world = &boot.world;
    friendly_engine.game.setActiveWorld(world);
    var lua_backend = try lua_controller_backend.LuaControllerBackend.init(std.heap.page_allocator);
    try friendly_engine.modules.luajit.runtime().attachBackend(lua_backend.backend());
    const project_config = boot.project_config;
    const startup_scene = options.startup_scene_override orelse project_config.startupScene();
    const configured_world = try project_config.worldForScene(startup_scene);
    const stream_configured_world = !options.no_startup_world;
    const use_startup_bundle = project_config.hasStartupBundle() and !options.no_startup_bundle;
    log.info("startup.config scene={s} world={s} bundle={s} stream_world={} use_bundle={}", .{
        startup_scene,
        configured_world,
        project_config.startupBundle(),
        stream_configured_world,
        use_startup_bundle,
    });

    const services_stage = LifecycleStage.begin("services");
    var persistence_backend = shared.file_persistence.FilePersistenceBackend.init(
        std.heap.page_allocator,
        init.io,
        options.project_path,
    ) catch |err| {
        services_stage.fail(err);
        return err;
    };
    defer persistence_backend.deinit();
    persistence_backend.install(world);

    var audio_backend = shared.sdl_audio.SdlAudioBackend.init(std.heap.page_allocator);
    defer audio_backend.deinit();
    if (config.enable_audio) {
        audio_backend.install(world);
    }

    var backend = desktop_backend.DesktopClientBackend.init(std.heap.page_allocator);
    defer backend.deinit();
    try backend.setRenderSettings(options.render_settings);
    backend.install(world, config.enable_renderer and !options.headless) catch |err| {
        services_stage.fail(err);
        return err;
    };

    var view = try scene_view.SceneView.init(std.heap.page_allocator, backend.window.width, backend.window.height);
    var view_deinit_scheduled = false;
    errdefer if (!view_deinit_scheduled) view.deinit();
    backend.attachSceneView(&view);
    services_stage.end();

    var atmosphere_state = client_atmosphere.ClientAtmosphereState{};

    var runtime_bundle: ?friendly_engine.framework.bundle_loader.RuntimeBundle = null;
    if (use_startup_bundle) {
        const bundle_stage = LifecycleStage.begin("loading_assets");
        runtime_bundle = friendly_engine.framework.bundle_loader.RuntimeBundle.load(
            std.heap.page_allocator,
            init.io,
            options.project_path,
            project_config.startupBundle(),
        ) catch |err| {
            bundle_stage.fail(err);
            return err;
        };
        bundle_stage.end();
    }
    defer if (runtime_bundle) |*bundle| bundle.deinit();

    if (runtime_bundle) |*bundle| {
        const register_stage = LifecycleStage.begin("registering_assets");
        try bundle.registerAssets(&world.assets);
        register_stage.end();
    } else {
        log.info("startup.loading_assets.skip reason=no_startup_bundle", .{});
    }

    var scene_state = friendly_engine.game.scene_spawn.SceneSpawnState.init(std.heap.page_allocator);
    defer scene_state.deinit();
    var active_scene_state: *friendly_engine.game.scene_spawn.SceneSpawnState = &scene_state;

    var world_manifest: ?friendly_engine.world.manifest.OwnedWorldManifest = null;
    defer if (world_manifest) |*loaded_manifest| loaded_manifest.deinit();

    var stream_manager: ?friendly_engine.world.stream.StreamManager = null;
    defer {
        friendly_engine.game.setStreamManager(null);
        if (stream_manager) |*manager| manager.deinit();
    }

    var cell_state: ?friendly_engine.game.cell_spawn.CellSpawnState = null;
    defer {
        friendly_engine.game.setCellState(null);
        if (cell_state) |*state| state.deinit();
    }

    if (stream_configured_world) {
        atmosphere_state.enableWorldPath();
        backend.attachClientAtmosphere(&atmosphere_state);
        const manifest_stage = LifecycleStage.begin("loading_world_manifest");
        world_manifest = friendly_engine.world.manifest.loadManifest(
            std.heap.page_allocator,
            init.io,
            options.project_path,
            configured_world,
        ) catch |err| {
            manifest_stage.fail(err);
            return err;
        };
        manifest_stage.end();
        log.info("startup.loading_world_manifest.cells count={d} cell_size_m={d}", .{
            world_manifest.?.cells.len,
            world_manifest.?.cell_size_m,
        });
        const stream_stage = LifecycleStage.begin("creating_stream_manager");
        stream_manager = friendly_engine.world.stream.StreamManager.init(
            std.heap.page_allocator,
            init.io,
            options.project_path,
            if (runtime_bundle) |bundle| bundle.target else "client-debug",
            &world_manifest.?,
        ) catch |err| {
            stream_stage.fail(err);
            return err;
        };
        stream_stage.end();
        friendly_engine.game.setStreamManager(&stream_manager.?);
        cell_state = try friendly_engine.game.cell_spawn.CellSpawnState.initWithProject(std.heap.page_allocator, init.io, options.project_path);
        friendly_engine.game.setCellState(&cell_state.?);

        if (cell_state) |*state| {
            const scene_stage = LifecycleStage.begin("loading_scene");
            scene_bootstrap.loadAndSpawn(
                std.heap.page_allocator,
                init.io,
                &state.scene_state,
                world,
                options.project_path,
                startup_scene,
                if (runtime_bundle) |*bundle| bundle else null,
            ) catch |err| {
                scene_stage.fail(err);
                return err;
            };
            active_scene_state = &state.scene_state;
            view.loadFromProject(
                init.io,
                options.project_path,
                startup_scene,
                if (runtime_bundle) |*bundle| bundle else null,
            ) catch |err| {
                scene_stage.fail(err);
                return err;
            };
            try backend.installInputBindingsForScene(&view);
            scene_stage.end();
        } else unreachable;

        if (stream_manager) |*manager| {
            const initial_stream_stage = LifecycleStage.begin("loading_initial_cells");
            const update = manager.updateAroundPosition(cameraTargetPosition(&view)) catch |err| {
                if (err == error.FileNotFound) {
                    log.err("startup.loading_initial_cells.help reason=missing_baked_cell action=\"Run Recompile Cells in the editor, or run `zig build run-tools -- world-bake --project {s} --world {s} --target client-debug` before Play. The world_file_io log line above names the exact missing cell.\"", .{
                        options.project_path,
                        configured_world,
                    });
                }
                initial_stream_stage.fail(err);
                return err;
            };
            atmosphere_state.syncFromManager(manager, cameraTargetPosition(&view)) catch |err| {
                initial_stream_stage.fail(err);
                return err;
            };
            if (cell_state) |*state| {
                state.syncFromStream(world, manager) catch |err| {
                    initial_stream_stage.fail(err);
                    return err;
                };
                active_scene_state = &state.scene_state;
            } else unreachable;
            log.info("startup.loading_initial_cells.result loaded={d} unloaded={d} pending={d} active={d}", .{
                update.loaded,
                update.unloaded,
                update.pending_loads,
                manager.activeCellCount(),
            });
            initial_stream_stage.end();
        } else unreachable;
    } else {
        const scene_stage = LifecycleStage.begin("loading_scene");
        scene_bootstrap.loadAndSpawn(
            std.heap.page_allocator,
            init.io,
            &scene_state,
            world,
            options.project_path,
            startup_scene,
            if (runtime_bundle) |*bundle| bundle else null,
        ) catch |err| {
            scene_stage.fail(err);
            return err;
        };
        scene_stage.end();
    }
    friendly_engine.game.setSceneState(active_scene_state);
    var physics_ptr: ?*friendly_engine.game.physics.GamePhysicsState = null;
    defer {
        if (physics_ptr) |physics| {
            physics.deinit();
            std.heap.page_allocator.destroy(physics);
        }
    }
    view_deinit_scheduled = true;
    defer view.deinit();
    if (config.enable_physics) {
        const physics_stage = LifecycleStage.begin("initializing_physics");
        const physics = try std.heap.page_allocator.create(friendly_engine.game.physics.GamePhysicsState);
        physics.* = friendly_engine.game.physics.GamePhysicsState.init(std.heap.page_allocator);
        physics_ptr = physics;
        physics.syncScene(active_scene_state) catch |err| {
            physics_stage.fail(err);
            return err;
        };
        friendly_engine.game.setPhysicsState(physics);
        physics_stage.end();
    }
    defer friendly_engine.game.setPhysicsState(null);
    const camera_stage = LifecycleStage.begin("initializing_camera");
    if (stream_configured_world) {
        view.syncFromSpawnStatePreservingPlayerCamera(active_scene_state) catch |err| {
            camera_stage.fail(err);
            return err;
        };
    } else {
        view.loadFromProject(
            init.io,
            options.project_path,
            startup_scene,
            if (runtime_bundle) |*bundle| bundle else null,
        ) catch |err| {
            camera_stage.fail(err);
            return err;
        };
    }
    try backend.installInputBindingsForScene(&view);
    log.info(
        "startup.initializing_camera.result fps_active={} eye={d:.2},{d:.2},{d:.2} target={d:.2},{d:.2},{d:.2} yaw={d:.3} pitch={d:.3} view_objects={d}",
        .{
            view.fpsActive(),
            view.camera.eye().x,
            view.camera.eye().y,
            view.camera.eye().z,
            view.camera.target.x,
            view.camera.target.y,
            view.camera.target.z,
            view.camera.yaw,
            view.camera.pitch,
            view.objects.items.len,
        },
    );
    camera_stage.end();

    const scene_summary = try std.fmt.allocPrint(
        std.heap.page_allocator,
        "{d} objects",
        .{active_scene_state.entities.items.len},
    );
    defer std.heap.page_allocator.free(scene_summary);
    log.info("scene loaded: {s}", .{scene_summary});

    if (!options.headless) {
        const window_stage = LifecycleStage.begin("opening_window");
        backend.initWindow() catch |err| {
            window_stage.fail(err);
            return err;
        };
        window_stage.end();
    }

    var frame_clock = friendly_engine.core.time.FrameClock.init();
    var fixed_step = friendly_engine.core.time.FixedStep.init(1.0 / 60.0);
    var frame_count: u64 = 0;
    var running = true;
    var first_frame_logged = false;
    var screenshot_queued = false;

    while (running) {
        const first_frame_stage = if (!first_frame_logged) LifecycleStage.begin("first_frame") else null;
        errdefer if (first_frame_stage) |stage| stage.fail(error.FirstFrameFailed);
        {
            const stage = if (!first_frame_logged) LifecycleStage.begin("first_frame.clock") else null;
            frame_clock.tick();
            _ = fixed_step.pushDelta(frame_clock.delta_seconds);
            if (stage) |s| s.end();
        }

        {
            const stage = if (!first_frame_logged) LifecycleStage.begin("first_frame.input") else null;
            try world.input.poll();
            try view.updateActiveController(
                &world.input,
                @floatCast(frame_clock.delta_seconds),
                backend.lookDeltaX(@floatCast(frame_clock.delta_seconds)),
                backend.lookDeltaY(@floatCast(frame_clock.delta_seconds)),
                physics_ptr,
            );
            var grass_influencer_buffer: [friendly_engine.modules.grass.types.max_influencers]friendly_engine.game.grass_clusters.Influencer = undefined;
            friendly_engine.game.setGrassInfluencers(view.grassInfluencers(&grass_influencer_buffer));
            if (stage) |s| s.end();
        }

        {
            const stage = if (!first_frame_logged) LifecycleStage.begin("first_frame.streaming") else null;
            if (stream_manager) |*manager| {
                const update = try manager.updateAroundPosition(cameraTargetPosition(&view));
                try atmosphere_state.syncFromManager(manager, cameraTargetPosition(&view));
                if (update.changed()) {
                    if (cell_state) |*state| {
                        try state.syncFromStream(world, manager);
                        active_scene_state = &state.scene_state;
                        friendly_engine.game.setSceneState(active_scene_state);
                        if (physics_ptr) |physics| {
                            try physics.syncScene(active_scene_state);
                        }
                        try view.syncFromSpawnStatePreservingPlayerCamera(&state.scene_state);
                    } else unreachable;
                }
            }
            if (stage) |s| s.end();
        }

        friendly_engine.game.setClientCameraPosition(view.camera.eye());
        {
            const stage = if (!first_frame_logged) LifecycleStage.begin("first_frame.game_tick") else null;
            try friendly_engine.game.tickClientLifecycle(world, !first_frame_logged);
            if (stage) |s| s.end();
        }
        {
            const stage = if (!first_frame_logged) LifecycleStage.begin("first_frame.update_scene") else null;
            try world.updateScene();
            if (stage) |s| s.end();
        }
        {
            const stage = if (!first_frame_logged) LifecycleStage.begin("first_frame.network") else null;
            try world.network.drainOutgoing();
            if (stage) |s| s.end();
        }
        {
            const stage = if (!first_frame_logged) LifecycleStage.begin("first_frame.audio") else null;
            try world.audio.flush();
            if (stage) |s| s.end();
        }
        {
            const stage = if (!first_frame_logged) LifecycleStage.begin("first_frame.renderer_flush") else null;
            if (!screenshot_queued) {
                if (options.screenshot_path) |path| {
                    if (options.frame_limit) |limit| {
                        if (frame_count + 1 >= limit) {
                            try ensureParentDirectory(init.io, path);
                            try backend.queueScreenshot(path);
                            screenshot_queued = true;
                        }
                    }
                }
            }
            try world.renderer.flush();
            if (stage) |s| s.end();
        }
        {
            const stage = if (!first_frame_logged) LifecycleStage.begin("first_frame.view_update") else null;
            view.update(@floatCast(frame_clock.delta_seconds));
            if (stage) |s| s.end();
        }

        if (backend.should_quit) running = false;
        frame_count += 1;

        if (options.frame_limit) |limit| {
            if (frame_count >= limit) running = false;
        } else if (options.headless) {
            if (frame_count >= default_headless_ticks) running = false;
        } else {
            sdl.SDL_Delay(16);
        }
        if (first_frame_stage) |stage| {
            stage.end();
            first_frame_logged = true;
        }
    }

    log.info(
        "startup.runtime.end frames={d} dt={d:.3}s",
        .{ frame_count, frame_clock.delta_seconds },
    );

    if (options.screenshot_path) |path| {
        if (screenshot_queued) {
            log.info("saved screenshot path={s}", .{path});
            return;
        }
        if (options.headless) return error.ScreenshotRequiresWindow;
        try ensureParentDirectory(init.io, path);
        try backend.queueScreenshot(path);
        try world.renderer.flush();
        log.info("saved screenshot path={s}", .{path});
    }
}

fn cameraTargetPosition(view: *const scene_view.SceneView) friendly_engine.core.math.Vec3f {
    return .{
        .x = view.camera.target.x,
        .y = view.camera.target.y,
        .z = view.camera.target.z,
    };
}

const default_headless_ticks: u64 = 3;

const ClientRunOptions = struct {
    project_path: []const u8 = ".",
    startup_scene_override: ?[]const u8 = null,
    no_startup_world: bool = false,
    no_startup_bundle: bool = false,
    frame_limit: ?u64 = null,
    screenshot_path: ?[]const u8 = null,
    headless: bool = false,
    render_settings: shared.gpu_api.RenderSettings = .{},
    help: bool = false,
};

fn parseOptions(args: std.process.Args, allocator: std.mem.Allocator) !ClientRunOptions {
    var arg_it = try args.iterateAllocator(allocator);
    defer arg_it.deinit();

    _ = arg_it.next();
    var options = ClientRunOptions{};
    while (arg_it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            options.help = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--headless")) {
            options.headless = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--no-startup-world")) {
            options.no_startup_world = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--no-startup-bundle")) {
            options.no_startup_bundle = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--gpu")) {
            // GPU rendering is the only supported mode; flag kept for compatibility.
            continue;
        }
        if (std.mem.eql(u8, arg, "--render-settings")) {
            const next_arg = arg_it.next() orelse return error.MissingRenderSettingsValue;
            try options.render_settings.parseOverrides(next_arg);
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--render-settings=")) {
            try options.render_settings.parseOverrides(arg["--render-settings=".len..]);
            continue;
        }
        if (std.mem.eql(u8, arg, "--project")) {
            const next_arg = arg_it.next() orelse return error.MissingProjectPath;
            options.project_path = next_arg;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--project=")) {
            options.project_path = arg["--project=".len..];
            continue;
        }
        if (std.mem.eql(u8, arg, "--startup-scene")) {
            const next_arg = arg_it.next() orelse return error.MissingStartupScenePath;
            options.startup_scene_override = next_arg;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--startup-scene=")) {
            options.startup_scene_override = arg["--startup-scene=".len..];
            continue;
        }
        if (std.mem.eql(u8, arg, "--frames")) {
            const next_arg = arg_it.next() orelse return error.MissingFramesValue;
            options.frame_limit = try std.fmt.parseUnsigned(u64, next_arg, 10);
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--frames=")) {
            options.frame_limit = try std.fmt.parseUnsigned(u64, arg["--frames=".len..], 10);
            continue;
        }
        if (std.mem.eql(u8, arg, "--screenshot")) {
            options.screenshot_path = arg_it.next() orelse return error.MissingScreenshotPath;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--screenshot=")) {
            options.screenshot_path = arg["--screenshot=".len..];
            continue;
        }

        log.err("unknown argument: {s}", .{arg});
        return error.UnknownArgument;
    }

    return options;
}

fn ensureParentDirectory(io: std.Io, path: []const u8) !void {
    const parent = std.fs.path.dirname(path) orelse return;
    if (parent.len == 0) return;
    try std.Io.Dir.cwd().createDirPath(io, parent);
}

test "client options parse screenshot path" {
    var args = try std.process.ArgIteratorGeneral(.{}).init(std.testing.allocator, "friendly_engine_client --frames=5 --gpu --screenshot .friendly-engine/runtime-screenshots/player.png");
    defer args.deinit();

    const options = try parseOptions(args, std.testing.allocator);

    try std.testing.expectEqual(@as(?u64, 5), options.frame_limit);
    try std.testing.expectEqualStrings(".friendly-engine/runtime-screenshots/player.png", options.screenshot_path.?);
}

test "client options require screenshot path value" {
    var args = try std.process.ArgIteratorGeneral(.{}).init(std.testing.allocator, "friendly_engine_client --screenshot");
    defer args.deinit();

    try std.testing.expectError(error.MissingScreenshotPath, parseOptions(args, std.testing.allocator));
}
