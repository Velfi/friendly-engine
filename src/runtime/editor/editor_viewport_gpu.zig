const std = @import("std");
const shared = @import("runtime_shared");
const editor_draw = @import("editor_draw.zig");

const log = std.log.scoped(.editor);

pub const RenderMode = enum {
    gpu,
    software,
};

pub const EditorViewportGpu = struct {
    allocator: std.mem.Allocator,
    render_mode: RenderMode = .gpu,
    render_settings: shared.gpu_api.RenderSettings = .{},
    use_gpu: bool = false,
    gpu_backend_name: shared.gpu_api.GpuBackendName = .unknown,
    window: ?*editor_draw.SDL_Window = null,
    gpu_device: ?*shared.sdl_gpu.SDL_GPUDevice = null,
    gpu_renderer: ?shared.gpu_backend.GpuRenderer = null,

    pub fn init(allocator: std.mem.Allocator, render_mode: RenderMode) EditorViewportGpu {
        return .{
            .allocator = allocator,
            .render_mode = render_mode,
        };
    }

    pub fn setRenderSettings(self: *EditorViewportGpu, settings: shared.gpu_api.RenderSettings) !void {
        self.render_settings = settings;
        if (self.gpu_renderer) |*gpu| {
            try gpu.setRenderSettings(settings);
        }
    }

    pub fn deinit(self: *EditorViewportGpu) void {
        if (self.gpu_renderer) |*gpu| {
            gpu.deinit();
            self.gpu_renderer = null;
        }
        if (self.gpu_device) |device| {
            if (self.window) |window| {
                const gpu_window = @as(*shared.sdl_gpu.SDL_Window, @ptrCast(window));
                shared.sdl_gpu.SDL_ReleaseWindowFromGPUDevice(device, gpu_window);
            }
            shared.sdl_gpu.SDL_DestroyGPUDevice(device);
            self.gpu_device = null;
        }
        self.window = null;
        self.use_gpu = false;
        self.gpu_backend_name = .unknown;
    }

    pub fn initForWindow(self: *EditorViewportGpu, window: *editor_draw.SDL_Window) !void {
        self.window = window;
        if (self.render_mode == .software) {
            return;
        }

        try self.initSdlGpu(window);
    }

    fn initSdlGpu(self: *EditorViewportGpu, window: *editor_draw.SDL_Window) !void {
        const gpu_window = @as(*shared.sdl_gpu.SDL_Window, @ptrCast(window));

        const device = shared.sdl_gpu.SDL_CreateGPUDevice(
            shared.sdl_gpu.preferredShaderFormats(),
            true,
            null,
        ) orelse return error.GpuRendererUnavailable;
        errdefer shared.sdl_gpu.SDL_DestroyGPUDevice(device);

        if (!shared.sdl_gpu.SDL_ClaimWindowForGPUDevice(device, gpu_window)) {
            shared.sdl_gpu.SDL_DestroyGPUDevice(device);
            return error.GpuWindowClaimFailed;
        }

        var gpu = shared.gpu_backend.GpuRenderer.initSdlGpuWithSettings(self.allocator, device, gpu_window, self.render_settings) catch |err| {
            log.err("SDL GPU init failed ({s})", .{@errorName(err)});
            shared.sdl_gpu.SDL_ReleaseWindowFromGPUDevice(device, gpu_window);
            shared.sdl_gpu.SDL_DestroyGPUDevice(device);
            return err;
        };
        errdefer gpu.deinit();

        self.gpu_device = device;
        self.gpu_renderer = gpu;
        self.gpu_backend_name = gpu.backendName();
        self.use_gpu = true;
        log.info("{s} GPU viewport enabled (SDL3 GPU API)", .{
            self.gpu_backend_name.label(),
        });
    }

    pub fn logRenderBackend(self: *const EditorViewportGpu) void {
        if (self.use_gpu) return;
        log.info("software viewport renderer enabled", .{});
    }
};
