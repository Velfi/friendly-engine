const std = @import("std");
const time = @import("friendly_engine").core.time;

pub const Scope = enum {
    events,
    simulation,
    editor_update,
    render_ui_build,
    ui_top_bar,
    ui_left_panel,
    ui_viewport_toolbar,
    ui_right_inspector,
    ui_timeline,
    ui_bottom_strip,
    ui_preferences,
    render_input,
    render_viewport,
    render_viewport_gpu,
    gpu_begin_frame,
    gpu_collect_scene,
    gpu_sync_scene,
    gpu_lighting,
    gpu_build_commands,
    gpu_submit_commands,
    gpu_end_frame,
    gpu_swapchain_acquire,
    render_viewport_software,
    render_viewport_texture,
    render_viewport_overlays,
    render_ui_draw,
    render_present,
    project_manager_render,
    frame_sleep,

    pub fn label(self: Scope) []const u8 {
        return switch (self) {
            .events => "events_ms",
            .simulation => "simulation_ms",
            .editor_update => "editor_update_ms",
            .render_ui_build => "render_ui_build_ms",
            .ui_top_bar => "ui_top_bar_ms",
            .ui_left_panel => "ui_left_panel_ms",
            .ui_viewport_toolbar => "ui_viewport_toolbar_ms",
            .ui_right_inspector => "ui_right_inspector_ms",
            .ui_timeline => "ui_timeline_ms",
            .ui_bottom_strip => "ui_bottom_strip_ms",
            .ui_preferences => "ui_preferences_ms",
            .render_input => "render_input_ms",
            .render_viewport => "render_viewport_ms",
            .render_viewport_gpu => "render_viewport_gpu_ms",
            .gpu_begin_frame => "gpu_begin_frame_ms",
            .gpu_collect_scene => "gpu_collect_scene_ms",
            .gpu_sync_scene => "gpu_sync_scene_ms",
            .gpu_lighting => "gpu_lighting_ms",
            .gpu_build_commands => "gpu_build_commands_ms",
            .gpu_submit_commands => "gpu_submit_commands_ms",
            .gpu_end_frame => "gpu_end_frame_ms",
            .gpu_swapchain_acquire => "gpu_swapchain_acquire_ms",
            .render_viewport_software => "render_viewport_software_ms",
            .render_viewport_texture => "render_viewport_texture_ms",
            .render_viewport_overlays => "render_viewport_overlays_ms",
            .render_ui_draw => "render_ui_draw_ms",
            .render_present => "render_present_ms",
            .project_manager_render => "project_manager_render_ms",
            .frame_sleep => "frame_sleep_ms",
        };
    }
};

pub const SnapshotContext = struct {
    screen: []const u8 = "unknown",
    viewport_backend: []const u8 = "none",
    gpu_backend: []const u8 = "none",
    viewport_w: u32 = 0,
    viewport_h: u32 = 0,
    object_count: u32 = 0,
    render_commands: u32 = 0,
    render_grids: u32 = 0,
    render_meshes: u32 = 0,
    render_instanced_meshes: u32 = 0,
    render_mesh_instances: u32 = 0,
    render_overlays: u32 = 0,
    render_copies: u32 = 0,
    llm_commands_executed: u64 = 0,
    llm_commands_inflight: u32 = 0,
    dirty_world_cells: u32 = 0,
    visible_meshes: u32 = 0,
    total_meshes: u32 = 0,
    gpu_uploaded_meshes: u32 = 0,
    gpu_indexed_primitives: u64 = 0,
    gpu_wireframe_indices: u64 = 0,
    ui_commands: u32 = 0,
    uses_gpu_texture_wrap: bool = false,
    uses_gpu_ui: bool = false,
};

pub const FramePerf = struct {
    latest_ms: [@typeInfo(Scope).@"enum".fields.len]f64 = [_]f64{0} ** @typeInfo(Scope).@"enum".fields.len,
    avg_ms: [@typeInfo(Scope).@"enum".fields.len]f64 = [_]f64{0} ** @typeInfo(Scope).@"enum".fields.len,
    frames: u64 = 0,
    frame_ms: f64 = 0,
    fps: f64 = 0,

    mark_start_ns: i128 = 0,
    last_scope: ?Scope = null,

    pub fn beginFrame(self: *FramePerf) void {
        self.frames += 1;
        self.mark_start_ns = time.monotonicNs();
        self.last_scope = null;
    }

    pub fn mark(self: *FramePerf, scope: Scope) void {
        const now = time.monotonicNs();
        if (self.last_scope) |prev| {
            self.record(prev, nsToMs(now - self.mark_start_ns));
        }
        self.last_scope = scope;
        self.mark_start_ns = now;
    }

    pub fn recordScope(self: *FramePerf, scope: Scope, ms: f64) void {
        self.record(scope, ms);
    }

    pub fn endFrame(self: *FramePerf, frame_ms: f64, fps: f64) void {
        const now = time.monotonicNs();
        if (self.last_scope) |prev| {
            self.record(prev, nsToMs(now - self.mark_start_ns));
        }
        self.last_scope = null;
        self.frame_ms = frame_ms;
        self.fps = fps;
    }

    pub fn describeJson(self: *const FramePerf, allocator: std.mem.Allocator, ctx: SnapshotContext) ![]u8 {
        var scopes = std.ArrayList(u8).empty;
        defer scopes.deinit(allocator);
        try scopes.appendSlice(allocator, "{");
        inline for (std.meta.fields(Scope)) |field| {
            const scope: Scope = @enumFromInt(@intFromEnum(@field(Scope, field.name)));
            const idx = @intFromEnum(scope);
            if (idx != 0) try scopes.appendSlice(allocator, ",");
            var entry_buf: [96]u8 = undefined;
            const entry = try std.fmt.bufPrint(&entry_buf, "\"{s}\":{{\"latest\":{d:.3},\"avg\":{d:.3}}}", .{
                scope.label(),
                self.latest_ms[idx],
                self.avg_ms[idx],
            });
            try scopes.appendSlice(allocator, entry);
        }
        try scopes.appendSlice(allocator, "}");

        return std.fmt.allocPrint(
            allocator,
            \\{{"ok":true,"command":"perf.describe","frames":{d},"fps":{d:.1},"frame_ms":{d:.3},"scopes":{s},"context":{{"screen":"{s}","viewport_backend":"{s}","gpu_backend":"{s}","viewport_w":{d},"viewport_h":{d},"object_count":{d},"render_commands":{d},"render_grids":{d},"render_meshes":{d},"render_instanced_meshes":{d},"render_mesh_instances":{d},"render_overlays":{d},"render_copies":{d},"llm_commands_executed":{d},"llm_commands_inflight":{d},"dirty_world_cells":{d},"visible_meshes":{d},"total_meshes":{d},"gpu_uploaded_meshes":{d},"gpu_indexed_primitives":{d},"gpu_wireframe_indices":{d},"ui_commands":{d},"uses_gpu_texture_wrap":{},"uses_gpu_ui":{}}}}}
        ,
            .{
                self.frames,
                self.fps,
                self.frame_ms,
                scopes.items,
                ctx.screen,
                ctx.viewport_backend,
                ctx.gpu_backend,
                ctx.viewport_w,
                ctx.viewport_h,
                ctx.object_count,
                ctx.render_commands,
                ctx.render_grids,
                ctx.render_meshes,
                ctx.render_instanced_meshes,
                ctx.render_mesh_instances,
                ctx.render_overlays,
                ctx.render_copies,
                ctx.llm_commands_executed,
                ctx.llm_commands_inflight,
                ctx.dirty_world_cells,
                ctx.visible_meshes,
                ctx.total_meshes,
                ctx.gpu_uploaded_meshes,
                ctx.gpu_indexed_primitives,
                ctx.gpu_wireframe_indices,
                ctx.ui_commands,
                ctx.uses_gpu_texture_wrap,
                ctx.uses_gpu_ui,
            },
        );
    }

    fn record(self: *FramePerf, scope: Scope, ms: f64) void {
        const idx = @intFromEnum(scope);
        self.latest_ms[idx] = ms;
        if (self.frames <= 1) {
            self.avg_ms[idx] = ms;
        } else {
            self.avg_ms[idx] = self.avg_ms[idx] * 0.85 + ms * 0.15;
        }
    }

    fn nsToMs(ns: i128) f64 {
        if (ns <= 0) return 0;
        return @as(f64, @floatFromInt(ns)) / @as(f64, @floatFromInt(std.time.ns_per_ms));
    }
};

test "frame perf describe includes scope timings" {
    var perf = FramePerf{};
    perf.beginFrame();
    perf.recordScope(.events, 1.2);
    perf.recordScope(.render_viewport, 8.5);
    perf.endFrame(12.0, 83.3);

    const json = try perf.describeJson(std.testing.allocator, .{
        .screen = "project_editor",
        .viewport_backend = "gpu",
        .gpu_backend = "Metal",
    });
    defer std.testing.allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "perf.describe") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "render_viewport_ms") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "uses_gpu_texture_wrap") != null);
}
