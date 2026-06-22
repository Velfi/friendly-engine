const std = @import("std");
const friendly_engine = @import("friendly_engine");
const framework = friendly_engine.framework;
const shared = @import("runtime_shared");
const display = @import("client_display.zig");
const scene_view = @import("scene_view.zig");
const client_atmosphere = @import("client_atmosphere.zig");
const keyboard_mouse = friendly_engine.modules.keyboard_mouse_controller;
const controller_input = friendly_engine.modules.controller_input;
const fps_controller = friendly_engine.modules.fps_player_controller;
const luajit = friendly_engine.modules.luajit;

const log = std.log.scoped(.client);

const SDL_INIT_VIDEO: u32 = display.SDL_INIT_VIDEO;
const SDL_INIT_GAMEPAD: u32 = display.SDL_INIT_GAMEPAD;
const SDL_QUIT: u32 = display.SDL_QUIT;
const SDL_EVENT_MOUSE_MOTION: u32 = display.SDL_EVENT_MOUSE_MOTION;
const SDL_EVENT_MOUSE_BUTTON_DOWN: u32 = display.SDL_EVENT_MOUSE_BUTTON_DOWN;
const SDL_EVENT_MOUSE_BUTTON_UP: u32 = display.SDL_EVENT_MOUSE_BUTTON_UP;
const SDL_EVENT_KEY_DOWN: u32 = display.SDL_EVENT_KEY_DOWN;
const SDL_EVENT_KEY_UP: u32 = display.SDL_EVENT_KEY_UP;
const SDL_EVENT_GAMEPAD_ADDED: u32 = display.SDL_EVENT_GAMEPAD_ADDED;
const SDL_EVENT_GAMEPAD_REMOVED: u32 = display.SDL_EVENT_GAMEPAD_REMOVED;
const SDL_EVENT_GAMEPAD_AXIS_MOTION: u32 = display.SDL_EVENT_GAMEPAD_AXIS_MOTION;
const SDL_EVENT_GAMEPAD_BUTTON_DOWN: u32 = display.SDL_EVENT_GAMEPAD_BUTTON_DOWN;
const SDL_EVENT_GAMEPAD_BUTTON_UP: u32 = display.SDL_EVENT_GAMEPAD_BUTTON_UP;
const SDL_BUTTON_LEFT: u8 = display.SDL_BUTTON_LEFT;
const SDL_BUTTON_MIDDLE: u8 = display.SDL_BUTTON_MIDDLE;
const SDL_BUTTON_RIGHT: u8 = display.SDL_BUTTON_RIGHT;
const gamepad_look_speed_units_per_second: f32 = 900.0;
const gamepad_look_deadzone: f32 = 0.15;

pub const DesktopWindow = struct {
    title: []const u8,
    width: u16,
    height: u16,

    pub fn init(title: []const u8, width: u16, height: u16) DesktopWindow {
        return .{
            .title = title,
            .width = width,
            .height = height,
        };
    }
};

pub const DesktopClientBackend = struct {
    allocator: std.mem.Allocator,
    window: DesktopWindow,
    render_settings: shared.gpu_api.RenderSettings = .{},
    polled_frames: u64 = 0,
    rendered_frames: u64 = 0,
    submitted_commands: usize = 0,
    submitted_draw_mesh: usize = 0,
    should_quit: bool = false,
    sdl_window: ?*display.SDL_Window = null,
    gpu_device: ?*shared.sdl_gpu.SDL_GPUDevice = null,
    gpu_renderer: ?shared.gpu_api.GpuRenderer = null,
    gpu_backend_name: shared.gpu_api.GpuBackendName = .unknown,
    world: ?*framework.World = null,
    scene_view: ?*scene_view.SceneView = null,
    client_atmosphere: ?*client_atmosphere.ClientAtmosphereState = null,
    input_controller: keyboard_mouse.Controller,
    gamepad_controller: controller_input.Controller,
    gamepads: std.AutoHashMap(controller_input.DeviceId, *display.SDL_Gamepad),
    drag_mode: DragMode = .none,
    drag_last_x: f32 = 0,
    drag_last_y: f32 = 0,
    output_width: u32 = 1280,
    output_height: u32 = 720,
    frame_clear: framework.render.ClearColor = .{ .r = 0.02, .g = 0.02, .b = 0.04, .a = 1.0 },
    gpu_commands: shared.render_commands.CommandBuffer,
    render_command_stats: shared.render_commands.Stats = .{},
    visibility_stats: shared.render_visibility.VisibilityStats = .{},
    pending_screenshot_path: ?[]u8 = null,

    const DragMode = enum {
        none,
        orbit,
        pan,
    };

    pub fn init(allocator: std.mem.Allocator) DesktopClientBackend {
        return .{
            .allocator = allocator,
            .window = DesktopWindow.init("friendly-engine", 1280, 720),
            .input_controller = keyboard_mouse.Controller.init(allocator),
            .gamepad_controller = controller_input.Controller.init(allocator),
            .gamepads = std.AutoHashMap(controller_input.DeviceId, *display.SDL_Gamepad).init(allocator),
            .gpu_commands = shared.render_commands.CommandBuffer.init(allocator),
        };
    }

    pub fn setRenderSettings(self: *DesktopClientBackend, settings: shared.gpu_api.RenderSettings) !void {
        self.render_settings = settings;
        if (self.gpu_renderer) |*gpu| {
            try gpu.setRenderSettings(settings);
        }
    }

    pub fn attachSceneView(self: *DesktopClientBackend, view: *scene_view.SceneView) void {
        self.scene_view = view;
    }

    pub fn attachClientAtmosphere(self: *DesktopClientBackend, state: *client_atmosphere.ClientAtmosphereState) void {
        self.client_atmosphere = state;
    }

    /// Queues a screenshot of the GPU-presented frame. The capture happens during the
    /// next `endFrame()` call, since reading back the swapchain texture must occur
    /// before the frame is submitted/presented.
    pub fn queueScreenshot(self: *DesktopClientBackend, path: []const u8) !void {
        if (self.pending_screenshot_path) |existing| self.allocator.free(existing);
        self.pending_screenshot_path = try self.allocator.dupe(u8, path);
    }

    pub fn lookDeltaX(self: *const DesktopClientBackend, dt_seconds: f32) f32 {
        return self.input_controller.pointer.delta_x + stickLookDelta(self.gamepad_controller.axisValue(.right_x), dt_seconds);
    }

    pub fn lookDeltaY(self: *const DesktopClientBackend, dt_seconds: f32) f32 {
        return self.input_controller.pointer.delta_y + stickLookDelta(self.gamepad_controller.axisValue(.right_y), dt_seconds);
    }

    fn captureGpuScreenshot(self: *DesktopClientBackend, gpu: *shared.gpu_api.GpuRenderer, path: []const u8) !void {
        const path_z = try self.allocator.dupeZ(u8, path);
        defer self.allocator.free(path_z);

        const pixel_count = @as(usize, self.output_width) * @as(usize, self.output_height) * 4;
        const pixels = try self.allocator.alloc(u8, pixel_count);
        defer self.allocator.free(pixels);
        try gpu.capturePresentedFrameAndEndFrame(pixels);

        const surface = display.SDL_CreateSurfaceFrom(
            @intCast(self.output_width),
            @intCast(self.output_height),
            display.SDL_PIXELFORMAT_RGBA32,
            pixels.ptr,
            @intCast(self.output_width * 4),
        ) orelse return error.SdlSurfaceCreateFailed;
        defer display.SDL_DestroySurface(surface);
        if (!display.SDL_SavePNG(surface, path_z.ptr)) return error.SdlSavePngFailed;
    }

    pub fn initWindow(self: *DesktopClientBackend) !void {
        if (self.sdl_window != null) return;

        if (!display.SDL_Init(SDL_INIT_VIDEO | SDL_INIT_GAMEPAD)) {
            return error.SdlInitFailed;
        }

        try self.initSdlGpuWindow();
        log.info("{s} GPU renderer enabled (SDL3 GPU API)", .{self.gpu_backend_name.label()});
    }

    fn initSdlGpuWindow(self: *DesktopClientBackend) !void {
        const window = display.SDL_CreateWindow(
            "friendly-engine",
            @intCast(self.window.width),
            @intCast(self.window.height),
            0,
        ) orelse return error.SdlWindowCreationFailed;
        const gpu_window = @as(*shared.sdl_gpu.SDL_Window, @ptrCast(window));
        errdefer display.SDL_DestroyWindow(window);

        const device = shared.sdl_gpu.SDL_CreateGPUDevice(
            shared.sdl_gpu.preferredShaderFormats(),
            true,
            null,
        ) orelse {
            display.SDL_DestroyWindow(window);
            return error.GpuRendererUnavailable;
        };
        errdefer shared.sdl_gpu.SDL_DestroyGPUDevice(device);

        if (!shared.sdl_gpu.SDL_ClaimWindowForGPUDevice(device, gpu_window)) {
            shared.sdl_gpu.SDL_DestroyGPUDevice(device);
            display.SDL_DestroyWindow(window);
            return error.GpuWindowClaimFailed;
        }

        var gpu = shared.gpu_api.GpuRenderer.initSdlGpuWithSettings(self.allocator, device, gpu_window, self.render_settings) catch |err| {
            log.err("SDL GPU init failed ({s})", .{@errorName(err)});
            shared.sdl_gpu.SDL_ReleaseWindowFromGPUDevice(device, gpu_window);
            shared.sdl_gpu.SDL_DestroyGPUDevice(device);
            display.SDL_DestroyWindow(window);
            return err;
        };
        errdefer gpu.deinit();

        self.sdl_window = window;
        self.gpu_device = device;
        self.gpu_renderer = gpu;
        self.gpu_backend_name = gpu.backendName();
        self.updateOutputSize();
    }

    pub fn deinit(self: *DesktopClientBackend) void {
        self.input_controller.deinit();
        self.gamepad_controller.deinit();
        var gamepad_iter = self.gamepads.iterator();
        while (gamepad_iter.next()) |entry| display.SDL_CloseGamepad(entry.value_ptr.*);
        self.gamepads.deinit();
        self.gpu_commands.deinit();
        if (self.pending_screenshot_path) |path| {
            self.allocator.free(path);
            self.pending_screenshot_path = null;
        }
        if (self.gpu_renderer) |*gpu| {
            gpu.deinit();
            self.gpu_renderer = null;
        }
        if (self.gpu_device) |device| {
            if (self.sdl_window) |sdl_window| {
                const gpu_window = @as(*shared.sdl_gpu.SDL_Window, @ptrCast(sdl_window));
                shared.sdl_gpu.SDL_ReleaseWindowFromGPUDevice(device, gpu_window);
            }
            shared.sdl_gpu.SDL_DestroyGPUDevice(device);
            self.gpu_device = null;
        }
        if (self.sdl_window) |window| {
            display.SDL_DestroyWindow(window);
            self.sdl_window = null;
            display.SDL_Quit();
        }
    }

    pub fn install(self: *DesktopClientBackend, world: *framework.World, enable_renderer: bool) !void {
        self.world = world;
        try self.installNoGameplayInputBindings();
        world.input.setBackend(.{
            .context = self,
            .vtable = &input_backend_vtable,
        });
        if (enable_renderer) {
            world.renderer.setBackend(.{
                .context = self,
                .vtable = &render_backend_vtable,
            });
        }
    }

    pub fn installInputBindingsForScene(self: *DesktopClientBackend, view: *const scene_view.SceneView) !void {
        switch (view.activeControllerKind()) {
            .none => try self.installNoGameplayInputBindings(),
            .fps => try self.installFpsInputBindings(),
            .scripted_lua => {
                const actions = view.scriptedActions() orelse return error.MissingScriptedControllerActions;
                try self.installScriptedInputBindings(actions);
            },
        }
    }

    fn installNoGameplayInputBindings(self: *DesktopClientBackend) !void {
        self.input_controller.clearBindings();
        self.gamepad_controller.clearBindings();
        try self.input_controller.bind(.{ .action_name = "desktop.quit", .trigger = .{ .key = .escape } });
    }

    fn installFpsInputBindings(self: *DesktopClientBackend) !void {
        try self.installKeyboardGameplayBindings(.{
            .move_forward = fps_controller.ActionNames.move_forward,
            .move_backward = fps_controller.ActionNames.move_backward,
            .strafe_left = fps_controller.ActionNames.strafe_left,
            .strafe_right = fps_controller.ActionNames.strafe_right,
            .sprint = fps_controller.ActionNames.sprint,
            .crouch = fps_controller.ActionNames.crouch,
            .jump = fps_controller.ActionNames.jump,
            .climb = null,
            .ascend = fps_controller.ActionNames.ascend,
            .descend = fps_controller.ActionNames.descend,
            .interact = fps_controller.ActionNames.interact,
        });
    }

    fn installScriptedInputBindings(self: *DesktopClientBackend, actions: *const luajit.ScriptedControllerActions) !void {
        try self.installKeyboardGameplayBindings(.{
            .move_forward = actions.move_forward,
            .move_backward = actions.move_backward,
            .strafe_left = actions.strafe_left,
            .strafe_right = actions.strafe_right,
            .sprint = actions.sprint,
            .crouch = actions.crouch,
            .jump = actions.jump,
            .climb = actions.climb,
            .ascend = actions.ascend,
            .descend = actions.descend,
            .interact = actions.interact,
        });
    }

    const GameplayActionNames = struct {
        move_forward: []const u8,
        move_backward: []const u8,
        strafe_left: []const u8,
        strafe_right: []const u8,
        sprint: []const u8,
        crouch: []const u8,
        jump: []const u8,
        climb: ?[]const u8,
        ascend: []const u8,
        descend: []const u8,
        interact: []const u8,
    };

    fn installKeyboardGameplayBindings(self: *DesktopClientBackend, actions: GameplayActionNames) !void {
        try self.installNoGameplayInputBindings();
        try self.input_controller.bind(.{ .action_name = actions.move_forward, .trigger = .{ .key = .w } });
        try self.input_controller.bind(.{ .action_name = actions.move_backward, .trigger = .{ .key = .s } });
        try self.input_controller.bind(.{ .action_name = actions.strafe_left, .trigger = .{ .key = .a } });
        try self.input_controller.bind(.{ .action_name = actions.strafe_right, .trigger = .{ .key = .d } });
        try self.input_controller.bind(.{ .action_name = actions.sprint, .trigger = .{ .key = .left_shift } });
        try self.input_controller.bind(.{ .action_name = actions.crouch, .trigger = .{ .key = .left_ctrl } });
        try self.input_controller.bind(.{ .action_name = actions.jump, .trigger = .{ .key = .space } });
        try self.input_controller.bind(.{ .action_name = actions.ascend, .trigger = .{ .key = .space } });
        try self.input_controller.bind(.{ .action_name = actions.descend, .trigger = .{ .key = .q } });
        try self.input_controller.bind(.{ .action_name = actions.interact, .trigger = .{ .key = .e } });

        try self.gamepad_controller.bind(.{ .action_name = actions.move_forward, .trigger = .{ .axis = .{ .axis = .left_y, .direction = .negative } } });
        try self.gamepad_controller.bind(.{ .action_name = actions.move_backward, .trigger = .{ .axis = .{ .axis = .left_y, .direction = .positive } } });
        try self.gamepad_controller.bind(.{ .action_name = actions.strafe_left, .trigger = .{ .axis = .{ .axis = .left_x, .direction = .negative } } });
        try self.gamepad_controller.bind(.{ .action_name = actions.strafe_right, .trigger = .{ .axis = .{ .axis = .left_x, .direction = .positive } } });
        try self.gamepad_controller.bind(.{ .action_name = actions.sprint, .trigger = .{ .button = .right_shoulder } });
        try self.gamepad_controller.bind(.{ .action_name = actions.crouch, .trigger = .{ .button = .left_shoulder } });
        try self.gamepad_controller.bind(.{ .action_name = actions.jump, .trigger = .{ .button = .south } });
        try self.gamepad_controller.bind(.{ .action_name = actions.ascend, .trigger = .{ .button = .south } });
        try self.gamepad_controller.bind(.{ .action_name = actions.descend, .trigger = .{ .button = .left_shoulder } });
        try self.gamepad_controller.bind(.{ .action_name = actions.interact, .trigger = .{ .button = .east } });
        if (actions.climb) |climb| try self.gamepad_controller.bind(.{ .action_name = climb, .trigger = .{ .button = .north } });
    }

    fn updateOutputSize(self: *DesktopClientBackend) void {
        const window = self.sdl_window orelse return;
        var output_w: c_int = 0;
        var output_h: c_int = 0;
        if (display.SDL_GetWindowSizeInPixels(window, &output_w, &output_h)) {
            self.output_width = @intCast(@max(1, output_w));
            self.output_height = @intCast(@max(1, output_h));
        }
    }

    fn pumpEvents(self: *DesktopClientBackend) !void {
        if (self.sdl_window == null) return;

        self.input_controller.beginFrame();
        var event: display.SDL_Event = undefined;
        while (display.SDL_PollEvent(&event)) {
            switch (event.type) {
                SDL_QUIT => self.should_quit = true,
                SDL_EVENT_KEY_DOWN => {
                    if (isFullscreenShortcut(event.key.key, event.key.mod, event.key.repeat)) {
                        self.toggleFullscreen();
                        continue;
                    }
                    const world = self.world orelse return error.MissingInputWorld;
                    if (keyFromSdl(event.key.key)) |key| {
                        try self.input_controller.feed(world, .{ .key_down = .{
                            .key = key,
                            .repeat = event.key.repeat,
                        } });
                        if (key == .escape) self.should_quit = true;
                    }
                },
                SDL_EVENT_KEY_UP => {
                    const world = self.world orelse return error.MissingInputWorld;
                    if (keyFromSdl(event.key.key)) |key| {
                        try self.input_controller.feed(world, .{ .key_up = .{
                            .key = key,
                            .repeat = false,
                        } });
                    }
                },
                SDL_EVENT_MOUSE_BUTTON_DOWN => {
                    if (!event.button.down) continue;
                    const world = self.world orelse return error.MissingInputWorld;
                    if (mouseButtonFromSdl(event.button.button)) |button| {
                        try self.input_controller.feed(world, .{ .mouse_button_down = .{
                            .button = button,
                            .x = event.button.x,
                            .y = event.button.y,
                            .clicks = event.button.clicks,
                        } });
                    }
                    self.drag_last_x = event.button.x;
                    self.drag_last_y = event.button.y;
                    const fps_active = if (self.scene_view) |view| view.fpsActive() else false;
                    if (!fps_active) {
                        self.drag_mode = switch (event.button.button) {
                            SDL_BUTTON_LEFT => .orbit,
                            SDL_BUTTON_MIDDLE, SDL_BUTTON_RIGHT => .pan,
                            else => .none,
                        };
                    }
                },
                SDL_EVENT_MOUSE_BUTTON_UP => {
                    const world = self.world orelse return error.MissingInputWorld;
                    if (mouseButtonFromSdl(event.button.button)) |button| {
                        try self.input_controller.feed(world, .{ .mouse_button_up = .{
                            .button = button,
                            .x = event.button.x,
                            .y = event.button.y,
                            .clicks = event.button.clicks,
                        } });
                    }
                    if (event.button.button == SDL_BUTTON_LEFT or
                        event.button.button == SDL_BUTTON_MIDDLE or
                        event.button.button == SDL_BUTTON_RIGHT)
                    {
                        self.drag_mode = .none;
                    }
                },
                SDL_EVENT_MOUSE_MOTION => {
                    const world = self.world orelse return error.MissingInputWorld;
                    const x = event.motion.x;
                    const y = event.motion.y;
                    const dx = event.motion.xrel;
                    const dy = event.motion.yrel;
                    try self.input_controller.feed(world, .{ .mouse_motion = .{
                        .x = x,
                        .y = y,
                        .delta_x = dx,
                        .delta_y = dy,
                    } });
                    if (self.scene_view == null or self.drag_mode == .none) continue;
                    self.drag_last_x = x;
                    self.drag_last_y = y;
                    const view = self.scene_view.?;
                    switch (self.drag_mode) {
                        .orbit => view.camera.orbit(dx, dy),
                        .pan => view.camera.pan(dx, dy),
                        .none => {},
                    }
                },
                SDL_EVENT_GAMEPAD_ADDED => {
                    const world = self.world orelse return error.MissingInputWorld;
                    const device_id: controller_input.DeviceId = event.gdevice.which;
                    if (!self.gamepads.contains(device_id)) {
                        if (display.SDL_OpenGamepad(@intCast(event.gdevice.which))) |gamepad| {
                            try self.gamepads.put(device_id, gamepad);
                        } else {
                            log.warn("SDL gamepad open failed id={} err={s}", .{ device_id, display.errorMessage() });
                            continue;
                        }
                    }
                    try self.gamepad_controller.feed(world, .{ .connected = .{ .device_id = device_id } });
                },
                SDL_EVENT_GAMEPAD_REMOVED => {
                    const world = self.world orelse return error.MissingInputWorld;
                    const device_id: controller_input.DeviceId = event.gdevice.which;
                    if (self.gamepads.fetchRemove(device_id)) |removed| display.SDL_CloseGamepad(removed.value);
                    try self.gamepad_controller.feed(world, .{ .disconnected = .{ .device_id = device_id } });
                },
                SDL_EVENT_GAMEPAD_AXIS_MOTION => {
                    const world = self.world orelse return error.MissingInputWorld;
                    if (gamepadAxisFromSdl(event.gaxis.axis)) |axis| {
                        try self.gamepad_controller.feed(world, .{ .axis_motion = .{
                            .device_id = event.gaxis.which,
                            .axis = axis,
                            .value = normalizeGamepadAxis(event.gaxis.value),
                        } });
                    }
                },
                SDL_EVENT_GAMEPAD_BUTTON_DOWN, SDL_EVENT_GAMEPAD_BUTTON_UP => {
                    const world = self.world orelse return error.MissingInputWorld;
                    if (gamepadButtonFromSdl(event.gbutton.button)) |button| {
                        const button_event = controller_input.InputEvent.ButtonEvent{
                            .device_id = event.gbutton.which,
                            .button = button,
                        };
                        if (event.type == SDL_EVENT_GAMEPAD_BUTTON_DOWN and event.gbutton.down) {
                            try self.gamepad_controller.feed(world, .{ .button_down = button_event });
                        } else {
                            try self.gamepad_controller.feed(world, .{ .button_up = button_event });
                        }
                    }
                },
                else => {},
            }
        }
    }

    fn toggleFullscreen(self: *DesktopClientBackend) void {
        const window = self.sdl_window orelse return;
        const fullscreen = (display.SDL_GetWindowFlags(window) & display.SDL_WINDOW_FULLSCREEN) != 0;
        if (!display.SDL_SetWindowFullscreen(window, !fullscreen)) {
            log.warn("SDL_SetWindowFullscreen failed: {s}", .{display.errorMessage()});
            return;
        }
        self.updateOutputSize();
    }

    fn syncGpuScene(self: *DesktopClientBackend) !void {
        const gpu = &self.gpu_renderer.?;
        const view = self.scene_view orelse return;

        var gpu_objects: std.ArrayList(shared.gpu_api.SceneGpuObject) = .empty;
        defer gpu_objects.deinit(self.allocator);

        const camera_eye = view.camera.eye();
        for (view.objects.items) |*obj| {
            const dissolve_amount = if (scene_view.shouldDissolveSceneObject(obj))
                scene_view.nearCameraDissolveAmount(sceneObjectCameraDistance(obj, camera_eye))
            else
                0.0;
            try gpu_objects.append(self.allocator, .{
                .mesh = &obj.mesh,
                .texture = obj.texture,
                .base_color = obj.base_color,
                .dissolve_amount = dissolve_amount,
            });
        }
        try gpu.syncSceneObjects(gpu_objects.items);
    }

    fn sceneObjectCameraDistance(obj: *const scene_view.SceneObject, camera_eye: shared.editor_math.Vec3) f32 {
        if (obj.local_bounds.empty) return shared.editor_math.Vec3.length(shared.editor_math.Vec3.sub(obj.position, camera_eye));
        const local_center = shared.editor_math.Vec3.scale(shared.editor_math.Vec3.add(obj.local_bounds.min, obj.local_bounds.max), 0.5);
        const world_center = obj.transform().transformPoint(local_center);
        const half_extents = shared.editor_math.Vec3.scale(shared.editor_math.Vec3.sub(obj.local_bounds.max, obj.local_bounds.min), 0.5);
        const radius = @sqrt(
            (half_extents.x * obj.scale.x) * (half_extents.x * obj.scale.x) +
                (half_extents.y * obj.scale.y) * (half_extents.y * obj.scale.y) +
                (half_extents.z * obj.scale.z) * (half_extents.z * obj.scale.z),
        );
        return @max(0.0, shared.editor_math.Vec3.length(shared.editor_math.Vec3.sub(world_center, camera_eye)) - radius);
    }

    fn pollInput(context: *anyopaque, input_system: *framework.input.InputSystem) !void {
        const backend: *DesktopClientBackend = @ptrCast(@alignCast(context));
        try backend.pumpEvents();
        try backend.input_controller.settleActionStates(input_system);
        try backend.gamepad_controller.settleActionStates(input_system);
        backend.polled_frames += 1;

        const frame_action: framework.input.ActionState = if (backend.polled_frames == 1) .pressed else .held;
        try input_system.setActionStateByName("desktop.frame_advanced", frame_action);
        if (backend.should_quit) {
            try input_system.setActionStateByName("desktop.quit", .pressed);
        }
    }

    fn beginFrame(context: *anyopaque) !void {
        const backend: *DesktopClientBackend = @ptrCast(@alignCast(context));
        backend.rendered_frames += 1;

        if (backend.gpu_renderer == null or backend.sdl_window == null) return;
        backend.updateOutputSize();
        const gpu = &backend.gpu_renderer.?;
        if (backend.scene_view) |view| {
            try backend.syncGpuScene();
            const lighting = backend.clientFrameLighting(view);
            gpu.setFrameLighting(lighting);
            gpu.setFrameSky(backend.clientFrameSky(view));
            const clear = backend.clientSkyColor();
            try gpu.beginFrame(
                backend.output_width,
                backend.output_height,
                clear,
            );
            backend.gpu_commands.clearRetainingCapacity();
            try backend.gpu_commands.appendGrid(view.camera);
            if (view.scriptedDebugCapsuleDraw()) |capsule| {
                try backend.gpu_commands.appendWireframeMesh(capsule.mesh_index, capsule.transform, view.camera, 0);
            }
        } else {
            const clear = backend.clientSkyColor();
            try gpu.beginFrame(
                backend.output_width,
                backend.output_height,
                clear,
            );
        }
    }

    fn clientSkyTone(self: *DesktopClientBackend) ?friendly_engine.modules.atmosphere.SkyTone {
        if (self.client_atmosphere) |atmosphere| return atmosphere.skyTone();
        return null;
    }

    fn clientFrameLighting(self: *DesktopClientBackend, view: *scene_view.SceneView) shared.render_lighting.FrameLighting {
        if (self.client_atmosphere) |atmosphere| {
            return atmosphere.buildFrameLighting(view.camera);
        }
        return .{ .shading_lit = true, .camera_position = view.camera.eye() };
    }

    fn clientFrameSky(self: *DesktopClientBackend, view: *scene_view.SceneView) shared.render_sky.FrameSky {
        if (self.clientSkyTone()) |sky_tone| {
            const clouds = if (self.client_atmosphere) |atmosphere| atmosphere.cloudTone() else friendly_engine.modules.atmosphere.CloudTone{};
            return shared.atmosphere_render.buildFrameSky(sky_tone, clouds, view.camera, view.life_time);
        }
        var sky: shared.render_sky.FrameSky = .{};
        sky.camera = view.camera;
        return sky;
    }

    fn clientSkyColor(self: *DesktopClientBackend) shared.color.Color {
        if (self.client_atmosphere) |atmosphere| return atmosphere.skyColor();
        const clear = self.frame_clear;
        return .{
            .r = @intFromFloat(@min(255.0, @max(0.0, clear.r * 255.0))),
            .g = @intFromFloat(@min(255.0, @max(0.0, clear.g * 255.0))),
            .b = @intFromFloat(@min(255.0, @max(0.0, clear.b * 255.0))),
            .a = @intFromFloat(@min(255.0, @max(0.0, clear.a * 255.0))),
        };
    }

    fn submit(context: *anyopaque, command: framework.render.RenderCommand, instance_transforms: []const [16]f32) !void {
        const backend: *DesktopClientBackend = @ptrCast(@alignCast(context));
        backend.submitted_commands += 1;

        switch (command) {
            .clear => |color| {
                backend.frame_clear = color;
            },
            .draw_mesh => |draw| {
                backend.submitted_draw_mesh += 1;

                const view = backend.scene_view orelse return;
                const idx = @as(usize, @intCast(draw.mesh_asset)) - 1;
                if (draw.surface == .water) {
                    try backend.gpu_commands.appendWaterMesh(idx, .{
                        .transform = draw.transform,
                        .bounds = shared.render_visibility.boundsFromTransform(draw.transform),
                        .cast_shadows = false,
                        .receive_shadows = false,
                        .projection_mode = .perspective,
                    }, view.camera, 0);
                } else if (draw.double_sided) {
                    try backend.gpu_commands.appendDoubleSidedMeshWithProjection(idx, draw.transform, view.camera, 0, .perspective);
                } else {
                    try backend.gpu_commands.appendMesh(idx, draw.transform, view.camera, 0);
                }
            },
            .draw_mesh_instanced => |draw| {
                backend.submitted_draw_mesh += draw.transform_count;

                const view = backend.scene_view orelse return;
                const idx = @as(usize, @intCast(draw.mesh_asset)) - 1;
                const start = draw.transform_offset;
                const end = start + draw.transform_count;
                if (end > instance_transforms.len) return error.MissingInstanceTransforms;
                if (draw.surface == .water) {
                    for (instance_transforms[start..end]) |transform| {
                        try backend.gpu_commands.appendWaterMesh(idx, .{
                            .transform = transform,
                            .bounds = shared.render_visibility.boundsFromTransform(transform),
                            .cast_shadows = false,
                            .receive_shadows = false,
                            .projection_mode = .perspective,
                        }, view.camera, 0);
                    }
                } else {
                    try backend.gpu_commands.appendInstancedMesh(
                        idx,
                        instance_transforms[start..end],
                        view.camera,
                        0,
                    );
                }
            },
            .draw_grass => |draw| {
                backend.submitted_draw_mesh += draw.instances.len;
                const view = backend.scene_view orelse return;
                var instances = try backend.allocator.alloc(shared.render_commands.GrassInstance, draw.instances.len);
                defer backend.allocator.free(instances);
                for (draw.instances, 0..) |instance, idx| {
                    instances[idx] = .{
                        .position = instance.position,
                        .normal = instance.normal,
                        .color = instance.color,
                        .height = instance.height,
                        .width = instance.width,
                        .yaw = instance.yaw,
                        .phase = instance.phase,
                        .variant = instance.variant,
                    };
                }
                var influencers = try backend.allocator.alloc(shared.render_commands.GrassInfluencer, draw.influencers.len);
                defer backend.allocator.free(influencers);
                for (draw.influencers, 0..) |influencer, idx| {
                    influencers[idx] = .{
                        .position = influencer.position,
                        .radius = influencer.radius,
                        .strength = influencer.strength,
                        .velocity_dir = influencer.velocity_dir,
                    };
                }
                try backend.gpu_commands.appendGrass(instances, influencers, view.camera, .{
                    .instance_offset = 0,
                    .instance_count = 0,
                    .influencer_offset = 0,
                    .influencer_count = 0,
                    .camera = view.camera,
                    .cull_fade = draw.cull_fade,
                    .wind_direction_deg = draw.wind_direction_deg,
                    .wind_speed_mps = draw.wind_speed_mps,
                    .wind_strength = draw.wind_strength,
                    .bend_strength = draw.bend_strength,
                    .stiffness = draw.stiffness,
                }, 0);
            },
            .draw_quad => return error.GpuOverlayQuadUnsupported,
            .draw_text => return error.DesktopTextRenderUnsupported,
        }
    }

    fn endFrame(context: *anyopaque) !void {
        const backend: *DesktopClientBackend = @ptrCast(@alignCast(context));

        const gpu = &backend.gpu_renderer.?;
        try gpu.submitCommands(&backend.gpu_commands);
        backend.render_command_stats = gpu.lastCommandStats();

        if (backend.pending_screenshot_path) |path| {
            defer {
                backend.allocator.free(path);
                backend.pending_screenshot_path = null;
            }
            try backend.captureGpuScreenshot(gpu, path);
            return;
        }

        try gpu.endFrame();
    }
};

fn keyFromSdl(key: display.SDL_Keycode) ?keyboard_mouse.Key {
    return if (key == display.SDLK_W)
        .w
    else if (key == display.SDLK_A)
        .a
    else if (key == display.SDLK_S)
        .s
    else if (key == display.SDLK_D)
        .d
    else if (key == display.SDLK_E)
        .e
    else if (key == display.SDLK_Q)
        .q
    else if (key == display.SDLK_SPACE)
        .space
    else if (key == display.SDLK_LSHIFT)
        .left_shift
    else if (key == display.SDLK_LCTRL)
        .left_ctrl
    else if (key == display.SDLK_ESCAPE)
        .escape
    else
        null;
}

fn isFullscreenShortcut(key: display.SDL_Keycode, mod: u16, repeat: bool) bool {
    if (repeat) return false;
    return switch (@import("builtin").target.os.tag) {
        .windows => (mod & display.SDL_KMOD_ALT) != 0 and
            (key == display.SDLK_RETURN or key == display.SDLK_KP_ENTER),
        .macos => (mod & display.SDL_KMOD_CTRL) != 0 and
            (mod & display.SDL_KMOD_GUI) != 0 and
            key == display.SDLK_F,
        else => false,
    };
}

fn mouseButtonFromSdl(button: u8) ?keyboard_mouse.MouseButton {
    return switch (button) {
        SDL_BUTTON_LEFT => .left,
        SDL_BUTTON_MIDDLE => .middle,
        SDL_BUTTON_RIGHT => .right,
        else => null,
    };
}

fn gamepadAxisFromSdl(axis: u8) ?controller_input.Axis {
    return if (axis == @as(u8, @intCast(display.SDL_GAMEPAD_AXIS_LEFTX)))
        .left_x
    else if (axis == @as(u8, @intCast(display.SDL_GAMEPAD_AXIS_LEFTY)))
        .left_y
    else if (axis == @as(u8, @intCast(display.SDL_GAMEPAD_AXIS_RIGHTX)))
        .right_x
    else if (axis == @as(u8, @intCast(display.SDL_GAMEPAD_AXIS_RIGHTY)))
        .right_y
    else if (axis == @as(u8, @intCast(display.SDL_GAMEPAD_AXIS_LEFT_TRIGGER)))
        .left_trigger
    else if (axis == @as(u8, @intCast(display.SDL_GAMEPAD_AXIS_RIGHT_TRIGGER)))
        .right_trigger
    else
        null;
}

fn gamepadButtonFromSdl(button: u8) ?controller_input.Button {
    return if (button == @as(u8, @intCast(display.SDL_GAMEPAD_BUTTON_SOUTH)))
        .south
    else if (button == @as(u8, @intCast(display.SDL_GAMEPAD_BUTTON_EAST)))
        .east
    else if (button == @as(u8, @intCast(display.SDL_GAMEPAD_BUTTON_WEST)))
        .west
    else if (button == @as(u8, @intCast(display.SDL_GAMEPAD_BUTTON_NORTH)))
        .north
    else if (button == @as(u8, @intCast(display.SDL_GAMEPAD_BUTTON_BACK)))
        .back
    else if (button == @as(u8, @intCast(display.SDL_GAMEPAD_BUTTON_GUIDE)))
        .guide
    else if (button == @as(u8, @intCast(display.SDL_GAMEPAD_BUTTON_START)))
        .start
    else if (button == @as(u8, @intCast(display.SDL_GAMEPAD_BUTTON_LEFT_STICK)))
        .left_stick
    else if (button == @as(u8, @intCast(display.SDL_GAMEPAD_BUTTON_RIGHT_STICK)))
        .right_stick
    else if (button == @as(u8, @intCast(display.SDL_GAMEPAD_BUTTON_LEFT_SHOULDER)))
        .left_shoulder
    else if (button == @as(u8, @intCast(display.SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER)))
        .right_shoulder
    else if (button == @as(u8, @intCast(display.SDL_GAMEPAD_BUTTON_DPAD_UP)))
        .dpad_up
    else if (button == @as(u8, @intCast(display.SDL_GAMEPAD_BUTTON_DPAD_DOWN)))
        .dpad_down
    else if (button == @as(u8, @intCast(display.SDL_GAMEPAD_BUTTON_DPAD_LEFT)))
        .dpad_left
    else if (button == @as(u8, @intCast(display.SDL_GAMEPAD_BUTTON_DPAD_RIGHT)))
        .dpad_right
    else if (button == @as(u8, @intCast(display.SDL_GAMEPAD_BUTTON_MISC1)))
        .misc1
    else
        null;
}

fn normalizeGamepadAxis(value: i16) f32 {
    if (value < 0) return @as(f32, @floatFromInt(value)) / 32768.0;
    return @as(f32, @floatFromInt(value)) / 32767.0;
}

fn stickLookDelta(axis_value: f32, dt_seconds: f32) f32 {
    const magnitude = @abs(axis_value);
    if (magnitude <= gamepad_look_deadzone) return 0.0;
    const normalized = (magnitude - gamepad_look_deadzone) / (1.0 - gamepad_look_deadzone);
    return std.math.sign(axis_value) * normalized * gamepad_look_speed_units_per_second * dt_seconds;
}

const input_backend_vtable = framework.input.BackendVTable{
    .poll = DesktopClientBackend.pollInput,
};

const render_backend_vtable = framework.render.BackendVTable{
    .beginFrame = DesktopClientBackend.beginFrame,
    .submit = DesktopClientBackend.submit,
    .endFrame = DesktopClientBackend.endFrame,
};

test "desktop backend installs into world systems" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();

    var backend = DesktopClientBackend.init(std.testing.allocator);
    defer backend.deinit();
    try backend.install(&world, true);

    try world.input.poll();
    try world.renderer.queue(.{
        .clear = .{ .r = 0.05, .g = 0.05, .b = 0.1, .a = 1.0 },
    });
    try world.renderer.flush();

    try std.testing.expectEqual(@as(u64, 1), backend.polled_frames);
    try std.testing.expectEqual(@as(u64, 1), backend.rendered_frames);
    try std.testing.expectEqual(@as(usize, 1), backend.submitted_commands);
}

test "scripted controller bindings use Lua action names for keyboard and gamepad" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();

    var backend = DesktopClientBackend.init(std.testing.allocator);
    defer backend.deinit();
    try backend.install(&world, false);

    var actions = try testScriptedActions(std.testing.allocator);
    defer actions.deinit(std.testing.allocator);
    try backend.installScriptedInputBindings(&actions);

    try backend.input_controller.feed(&world, .{ .key_down = .{ .key = .w, .repeat = false } });
    try std.testing.expectEqual(
        framework.input.ActionState.pressed,
        world.input.getActionState(framework.input.InputSystem.actionId("third_person.move_forward")),
    );

    try backend.gamepad_controller.feed(&world, .{ .connected = .{ .device_id = 1 } });
    try backend.gamepad_controller.feed(&world, .{ .axis_motion = .{
        .device_id = 1,
        .axis = .left_y,
        .value = 1.0,
    } });
    try std.testing.expectEqual(
        framework.input.ActionState.pressed,
        world.input.getActionState(framework.input.InputSystem.actionId("third_person.move_backward")),
    );

    try backend.gamepad_controller.feed(&world, .{ .button_down = .{
        .device_id = 1,
        .button = .right_shoulder,
    } });
    try std.testing.expectEqual(
        framework.input.ActionState.pressed,
        world.input.getActionState(framework.input.InputSystem.actionId("third_person.sprint")),
    );
}

test "no controller bindings leave gameplay actions unbound" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();

    var backend = DesktopClientBackend.init(std.testing.allocator);
    defer backend.deinit();
    try backend.install(&world, false);
    try backend.installNoGameplayInputBindings();

    try backend.input_controller.feed(&world, .{ .key_down = .{ .key = .w, .repeat = false } });
    try std.testing.expectEqual(
        framework.input.ActionState.up,
        world.input.getActionState(framework.input.InputSystem.actionId("third_person.move_forward")),
    );

    try backend.input_controller.feed(&world, .{ .key_down = .{ .key = .escape, .repeat = false } });
    try std.testing.expectEqual(
        framework.input.ActionState.pressed,
        world.input.getActionState(framework.input.InputSystem.actionId("desktop.quit")),
    );
}

test "right stick contributes camera look delta" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();

    var backend = DesktopClientBackend.init(std.testing.allocator);
    defer backend.deinit();

    try backend.gamepad_controller.feed(&world, .{ .axis_motion = .{
        .device_id = 1,
        .axis = .right_x,
        .value = 1.0,
    } });
    try backend.gamepad_controller.feed(&world, .{ .axis_motion = .{
        .device_id = 1,
        .axis = .right_y,
        .value = -1.0,
    } });

    try std.testing.expect(backend.lookDeltaX(1.0 / 60.0) > 0.0);
    try std.testing.expect(backend.lookDeltaY(1.0 / 60.0) < 0.0);
}

test "fullscreen shortcut follows desktop OS conventions" {
    const os = @import("builtin").target.os.tag;
    if (os == .windows) {
        try std.testing.expect(isFullscreenShortcut(display.SDLK_RETURN, display.SDL_KMOD_ALT, false));
        try std.testing.expect(isFullscreenShortcut(display.SDLK_KP_ENTER, display.SDL_KMOD_ALT, false));
        try std.testing.expect(!isFullscreenShortcut(display.SDLK_RETURN, display.SDL_KMOD_ALT, true));
        try std.testing.expect(!isFullscreenShortcut(display.SDLK_F, display.SDL_KMOD_CTRL | display.SDL_KMOD_GUI, false));
    } else if (os == .macos) {
        try std.testing.expect(isFullscreenShortcut(display.SDLK_F, display.SDL_KMOD_CTRL | display.SDL_KMOD_GUI, false));
        try std.testing.expect(!isFullscreenShortcut(display.SDLK_F, display.SDL_KMOD_CTRL | display.SDL_KMOD_GUI, true));
        try std.testing.expect(!isFullscreenShortcut(display.SDLK_RETURN, display.SDL_KMOD_ALT, false));
    } else {
        try std.testing.expect(!isFullscreenShortcut(display.SDLK_RETURN, display.SDL_KMOD_ALT, false));
        try std.testing.expect(!isFullscreenShortcut(display.SDLK_F, display.SDL_KMOD_CTRL | display.SDL_KMOD_GUI, false));
    }
}

fn testScriptedActions(allocator: std.mem.Allocator) !luajit.ScriptedControllerActions {
    return .{
        .move_forward = try allocator.dupe(u8, "third_person.move_forward"),
        .move_backward = try allocator.dupe(u8, "third_person.move_backward"),
        .strafe_left = try allocator.dupe(u8, "third_person.strafe_left"),
        .strafe_right = try allocator.dupe(u8, "third_person.strafe_right"),
        .sprint = try allocator.dupe(u8, "third_person.sprint"),
        .crouch = try allocator.dupe(u8, "third_person.crouch"),
        .jump = try allocator.dupe(u8, "third_person.jump"),
        .climb = try allocator.dupe(u8, "third_person.climb"),
        .ascend = try allocator.dupe(u8, "third_person.ascend"),
        .descend = try allocator.dupe(u8, "third_person.descend"),
        .interact = try allocator.dupe(u8, "third_person.interact"),
    };
}
