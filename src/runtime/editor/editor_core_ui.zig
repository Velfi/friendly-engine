const std = @import("std");
const friendly_engine = @import("friendly_engine");
const editor_core_ui_draw = @import("editor_core_ui_draw.zig");
const editor_core_ui_gpu = @import("editor_core_ui_gpu.zig");
const editor_core_ui_input = @import("editor_core_ui_input.zig");
const editor_draw = @import("editor_draw.zig");
const editor_ui_batch = @import("editor_ui_batch.zig");
const shared = @import("runtime_shared");

const core_ui = friendly_engine.modules.core_ui;

pub const BuildFn = *const fn (ui: *core_ui.UiContext, context: *anyopaque) anyerror!void;

pub const Host = struct {
    ui: core_ui.UiContext,
    input: editor_core_ui_input.Accumulator,
    style: editor_core_ui_draw.Style = .{},
    draw_batch: editor_ui_batch.UiDrawBatch,
    gpu_drawer: ?editor_core_ui_gpu.Renderer = null,

    pub fn init(allocator: std.mem.Allocator) Host {
        return .{
            .ui = core_ui.UiContext.init(allocator),
            .input = editor_core_ui_input.Accumulator.init(allocator),
            .draw_batch = editor_ui_batch.UiDrawBatch.init(allocator),
        };
    }

    pub fn deinit(self: *Host) void {
        std.debug.assert(self.gpu_drawer == null);
        self.draw_batch.deinit();
        self.input.deinit();
        self.ui.deinit();
    }

    pub fn deinitGpu(self: *Host, gpu: ?*shared.gpu_api.GpuRenderer) void {
        if (self.gpu_drawer) |*drawer| {
            drawer.deinit(gpu);
            self.gpu_drawer = null;
        }
    }

    pub fn beginEventFrame(self: *Host) void {
        self.input.beginFrame();
    }

    pub fn feedEvent(self: *Host, event: *const editor_draw.SDL_Event) !void {
        try self.input.feedEvent(event);
    }

    pub fn beginFrame(self: *Host) void {
        self.ui.beginFrame(self.input.snapshot());
    }

    pub fn build(self: *Host, comptime build_fn: BuildFn, context: *anyopaque) !void {
        try build_fn(&self.ui, context);
    }

    pub fn setFrameBounds(self: *Host, bounds: core_ui.Rect) void {
        self.ui.setFrameBounds(bounds);
    }

    pub fn draw(self: *Host, renderer: *editor_draw.SDL_Renderer, text_renderer: *editor_draw.TextRenderer) !void {
        try self.ui.flushTooltips();
        try editor_core_ui_draw.drawCommands(.{
            .renderer = renderer,
            .text_renderer = text_renderer,
            .batch = &self.draw_batch,
            .style = self.style,
        }, self.ui.renderCommands());
    }

    pub fn drawGpu(self: *Host, gpu: *shared.gpu_api.GpuRenderer, text_renderer: *editor_draw.TextRenderer, scale: f32) !void {
        try self.ui.flushTooltips();
        if (self.gpu_drawer == null) {
            self.gpu_drawer = try editor_core_ui_gpu.Renderer.init(self.ui.allocator);
        }
        try self.gpu_drawer.?.draw(gpu, text_renderer, self.ui.renderCommands(), self.style, scale);
    }
};

fn smokeBuild(ui: *core_ui.UiContext, context: *anyopaque) !void {
    const clicked: *bool = @ptrCast(@alignCast(context));
    try ui.beginPanel(.{ .id = "smoke", .rect = .{ .x = 0, .y = 0, .w = 200, .h = 100 } });
    const result = try ui.button("Run");
    if (result.clicked) clicked.* = true;
    ui.endPanel();
}

test "host builds commands from synthetic input" {
    var host = Host.init(std.testing.allocator);
    defer host.deinit();

    host.input.input.mouse_position = .{ .x = 12, .y = 12 };
    host.input.input.primary_down = true;
    host.input.input.primary_pressed = true;
    host.beginFrame();
    var clicked = false;
    try host.build(smokeBuild, &clicked);
    try std.testing.expect(host.ui.renderCommands().len >= 2);

    host.input.beginFrame();
    host.input.input.mouse_position = .{ .x = 12, .y = 12 };
    host.input.input.primary_released = true;
    host.beginFrame();
    try host.build(smokeBuild, &clicked);
    try std.testing.expect(clicked);
}
