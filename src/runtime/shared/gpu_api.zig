const std = @import("std");
const geometry = @import("geometry.zig");
const shared_color = @import("color.zig");
const gpu_scene = @import("gpu_scene.zig");
const core_ui_overlay = @import("core_ui_overlay.zig");
const editor_math = @import("editor_math.zig");
const sdl = @import("gpu_backend_sdl.zig");
const sdl_gpu = @import("sdl_gpu.zig");
const render_settings = @import("render_settings.zig");
const render_commands = @import("render_commands.zig");
const render_lighting = @import("render_lighting.zig");
const render_sky = @import("render_sky.zig");
const gpu_backend_sdl_types = @import("gpu_backend_sdl_types.zig");

pub const TextureSize = gpu_scene.TextureSize;
pub const RenderSettings = render_settings.RenderSettings;
pub const Antialiasing = render_settings.Antialiasing;
pub const ShadowQuality = render_settings.ShadowQuality;
pub const FrameLighting = render_lighting.FrameLighting;
pub const FrameSky = render_sky.FrameSky;
pub const CommandBuffer = render_commands.CommandBuffer;
pub const RenderCommandStats = render_commands.Stats;

pub const SceneGpuObject = gpu_scene.SceneGpuObject;
pub const OverlayQuad = gpu_scene.OverlayQuad;

pub const UploadedMeshStats = gpu_backend_sdl_types.UploadedMeshStats;

pub const GpuBackendKind = enum {
    sdl_gpu,
};

pub const GpuBackendName = enum {
    metal,
    vulkan,
    d3d12,
    unknown,

    pub fn label(self: GpuBackendName) []const u8 {
        return switch (self) {
            .metal => "Metal",
            .vulkan => "Vulkan",
            .d3d12 => "D3D12",
            .unknown => "unknown",
        };
    }
};

pub const GpuRenderer = struct {
    allocator: std.mem.Allocator,
    kind: GpuBackendKind,
    sdl: ?sdl.GpuRenderer = null,

    pub fn initSdlGpu(
        allocator: std.mem.Allocator,
        device: *sdl_gpu.SDL_GPUDevice,
        window: *sdl_gpu.SDL_Window,
    ) !GpuRenderer {
        return initSdlGpuWithSettings(allocator, device, window, .{});
    }

    pub fn initSdlGpuWithSettings(
        allocator: std.mem.Allocator,
        device: *sdl_gpu.SDL_GPUDevice,
        window: *sdl_gpu.SDL_Window,
        settings: RenderSettings,
    ) !GpuRenderer {
        return .{
            .allocator = allocator,
            .kind = .sdl_gpu,
            .sdl = try sdl.GpuRenderer.initWithSettings(allocator, device, window, settings),
        };
    }

    pub fn deinit(self: *GpuRenderer) void {
        if (self.sdl) |*renderer| renderer.deinit();
        self.sdl = null;
    }

    pub fn backendName(self: *const GpuRenderer) GpuBackendName {
        const name = self.sdl.?.backendName();
        return if (std.mem.eql(u8, name, "Metal"))
            .metal
        else if (std.mem.eql(u8, name, "Vulkan"))
            .vulkan
        else if (std.mem.eql(u8, name, "D3D12"))
            .d3d12
        else
            .unknown;
    }

    pub fn renderSettings(self: *const GpuRenderer) RenderSettings {
        return self.sdl.?.renderSettings();
    }

    pub fn setRenderSettings(self: *GpuRenderer, settings: RenderSettings) !void {
        try self.sdl.?.setRenderSettings(settings);
    }

    pub fn setFrameLighting(self: *GpuRenderer, lighting: FrameLighting) void {
        self.sdl.?.setFrameLighting(lighting);
    }

    pub fn setFrameSky(self: *GpuRenderer, sky: FrameSky) void {
        self.sdl.?.setFrameSky(sky);
    }

    pub fn beginFrame(self: *GpuRenderer, width: u32, height: u32, clear: shared_color.Color) !void {
        try self.sdl.?.beginFrame(width, height, clear);
    }

    pub fn drawGrid(self: *GpuRenderer, camera: editor_math.OrbitCamera) !void {
        var commands = CommandBuffer.init(self.allocator);
        defer commands.deinit();
        try commands.appendGrid(camera);
        try self.submitCommands(&commands);
    }

    pub fn syncSceneObjects(self: *GpuRenderer, objects: []const SceneGpuObject) !void {
        try self.sdl.?.syncSceneObjects(objects);
    }

    pub fn drawMeshByIndex(self: *GpuRenderer, index: usize, transform: [16]f32, camera: editor_math.OrbitCamera) !void {
        var commands = CommandBuffer.init(self.allocator);
        defer commands.deinit();
        try commands.appendMesh(index, transform, camera, 0);
        try self.submitCommands(&commands);
    }

    pub fn drawOverlayQuads(self: *GpuRenderer, quads: []const OverlayQuad) !void {
        var commands = CommandBuffer.init(self.allocator);
        defer commands.deinit();
        try commands.appendOverlay(quads);
        try self.submitCommands(&commands);
    }

    pub fn createOverlayTextureFromRgba(self: *GpuRenderer, rgba: []const u8, width: u32, height: u32) !*sdl_gpu.SDL_GPUTexture {
        return self.sdl.?.createOverlayTextureFromRgba(rgba, width, height);
    }

    pub fn updateOverlayTextureFromRgba(self: *GpuRenderer, texture: *sdl_gpu.SDL_GPUTexture, rgba: []const u8, width: u32, height: u32) !void {
        try self.sdl.?.updateOverlayTextureFromRgba(texture, rgba, width, height);
    }

    pub fn releaseOverlayTexture(self: *GpuRenderer, texture: *sdl_gpu.SDL_GPUTexture) void {
        self.sdl.?.releaseOverlayTexture(texture);
    }

    pub fn drawCoreUiOverlay(
        self: *GpuRenderer,
        allocator: std.mem.Allocator,
        commands: []const @import("friendly_engine").modules.core_ui.RenderCommand,
        style: core_ui_overlay.Style,
    ) !void {
        var quads: std.ArrayList(OverlayQuad) = .empty;
        defer quads.deinit(allocator);

        try core_ui_overlay.appendCoreUiOverlayQuads(allocator, commands, style, &quads);
        try self.drawOverlayQuads(quads.items);
    }

    pub fn drawGpuTextureRect(
        self: *GpuRenderer,
        texture: *sdl_gpu.SDL_GPUTexture,
        x: f32,
        y: f32,
        w: f32,
        h: f32,
    ) !void {
        const quad = OverlayQuad{
            .rect = .{ x, y, w, h },
            .uv = .{ 0, 0, 1, 1 },
            .gpu_texture = @ptrCast(texture),
            .color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        };
        try self.drawOverlayQuads(&.{quad});
    }

    pub fn submitCommands(self: *GpuRenderer, command_buffer: *CommandBuffer) !void {
        try self.sdl.?.submitCommands(command_buffer);
    }

    pub fn lastCommandStats(self: *const GpuRenderer) RenderCommandStats {
        return self.sdl.?.lastCommandStats();
    }

    pub fn uploadedMeshStats(self: *const GpuRenderer) UploadedMeshStats {
        return self.sdl.?.uploadedMeshStats();
    }

    pub fn endFrame(self: *GpuRenderer) !void {
        try self.sdl.?.endFrame();
    }

    pub fn lastSwapchainAcquireMs(self: *const GpuRenderer) f64 {
        return self.sdl.?.lastSwapchainAcquireMs();
    }

    pub fn capturePresentedFrameAndEndFrame(self: *GpuRenderer, dest: []u8) !void {
        try self.sdl.?.capturePresentedFrameAndEndFrame(dest);
    }

    pub fn beginOffscreenFrame(self: *GpuRenderer, width: u32, height: u32, clear: shared_color.Color) !void {
        try self.sdl.?.beginOffscreenFrame(width, height, clear);
    }

    pub fn endOffscreenFrame(self: *GpuRenderer) void {
        self.sdl.?.endOffscreenFrame();
    }

    pub fn readOffscreenPixels(self: *GpuRenderer, dest: []u8) void {
        self.sdl.?.readOffscreenPixels(dest);
    }

    pub fn offscreenColorTexture(self: *const GpuRenderer) ?*sdl_gpu.SDL_GPUTexture {
        return self.sdl.?.offscreenColorTexture();
    }

    pub fn offscreenWidth(self: *const GpuRenderer) u32 {
        return self.sdl.?.offscreenWidth();
    }

    pub fn offscreenHeight(self: *const GpuRenderer) u32 {
        return self.sdl.?.offscreenHeight();
    }
};

test "gpu api scene object alias" {
    try std.testing.expectEqual(@as(u32, 128), TextureSize);
}
