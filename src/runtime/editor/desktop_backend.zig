const std = @import("std");
const friendly_engine = @import("friendly_engine");
const framework = friendly_engine.framework;

const default_window_w = 1920;
const default_window_h = 1080;

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

    pub fn pumpEvents(self: *DesktopWindow) void {
        _ = self;
    }
};

pub const DesktopClientBackend = struct {
    window: DesktopWindow,
    polled_frames: u64 = 0,
    rendered_frames: u64 = 0,
    submitted_commands: usize = 0,

    pub fn init() DesktopClientBackend {
        return .{
            .window = DesktopWindow.init("friendly-engine editor", default_window_w, default_window_h),
        };
    }

    pub fn install(self: *DesktopClientBackend, world: *framework.World, enable_renderer: bool) void {
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

    fn pollInput(context: *anyopaque, input_system: *framework.input.InputSystem) !void {
        const backend: *DesktopClientBackend = @ptrCast(@alignCast(context));
        backend.window.pumpEvents();
        backend.polled_frames += 1;

        const frame_action: framework.input.ActionState = if (backend.polled_frames == 1) .pressed else .held;
        try input_system.setActionStateByName("desktop.frame_advanced", frame_action);
    }

    fn beginFrame(context: *anyopaque) !void {
        const backend: *DesktopClientBackend = @ptrCast(@alignCast(context));
        backend.rendered_frames += 1;
    }

    // Editor draws its viewport outside the render-system flush path.
    fn submit(context: *anyopaque, command: framework.render.RenderCommand, instance_transforms: []const [16]f32) !void {
        const backend: *DesktopClientBackend = @ptrCast(@alignCast(context));
        _ = command;
        _ = instance_transforms;
        backend.submitted_commands += 1;
    }

    fn endFrame(context: *anyopaque) !void {
        _ = context;
    }
};

const input_backend_vtable = framework.input.BackendVTable{
    .poll = DesktopClientBackend.pollInput,
};

const render_backend_vtable = framework.render.BackendVTable{
    .beginFrame = DesktopClientBackend.beginFrame,
    .submit = DesktopClientBackend.submit,
    .endFrame = DesktopClientBackend.endFrame,
};

test "editor desktop backend defaults to 1080p" {
    const backend = DesktopClientBackend.init();
    try std.testing.expectEqual(@as(u16, 1920), backend.window.width);
    try std.testing.expectEqual(@as(u16, 1080), backend.window.height);
}
