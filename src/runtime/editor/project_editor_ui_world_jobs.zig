const std = @import("std");
const friendly_engine = @import("friendly_engine");

const project_editor_state = @import("project_editor_state.zig");
const ui_widgets = @import("project_editor_ui_widgets.zig");

const core_ui = friendly_engine.modules.core_ui;
const ProjectEditorState = project_editor_state.ProjectEditorState;

pub fn buildTerrainJobLoader(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    const job = &(state.terrain_batch_job orelse return);
    if (!job.active and !job.complete and !job.cancelled and !job.failed) return;

    var title_buf: [160]u8 = undefined;
    const title = if (job.active)
        std.fmt.bufPrint(&title_buf, "Generating terrain {d}/{d} cells", .{ job.next_offset, job.total }) catch "Generating terrain"
    else if (job.complete)
        std.fmt.bufPrint(&title_buf, "Terrain complete {d} cells", .{job.total}) catch "Terrain complete"
    else if (job.cancelled)
        std.fmt.bufPrint(&title_buf, "Terrain cancelled {d}/{d} cells", .{ job.next_offset, job.total }) catch "Terrain cancelled"
    else
        "Terrain generation failed";
    try core_ui.widgets_feedback.statusLabel(ui, title);

    const progress = if (job.total == 0) 1.0 else @as(f32, @floatFromInt(job.next_offset)) / @as(f32, @floatFromInt(job.total));
    try core_ui.widgets_feedback.progressBar(ui, "ed-world-terrain-geology-progress", progress);

    var detail_buf: [160]u8 = undefined;
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(
        &detail_buf,
        "{d:.0}m cells  formations {d}  height {d:.1}-{d:.1}m",
        .{
            job.cell_size_m,
            job.formation_count,
            if (std.math.isFinite(job.min_height)) job.min_height else 0,
            if (std.math.isFinite(job.max_height)) job.max_height else 0,
        },
    ) catch "Terrain job details");

    var timing_buf: [160]u8 = undefined;
    const elapsed_ns = durationSince(job.started_ns, nowNs(state));
    const remaining_cells = if (job.total > job.next_offset) job.total - job.next_offset else 0;
    const avg_wall_cell_ns = if (job.next_offset == 0) @as(u64, 0) else elapsed_ns / job.next_offset;
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(
        &timing_buf,
        "elapsed {d:.1}s  remaining {d:.1}s  last tick {d} cells  flushes {d}",
        .{
            nsToSeconds(elapsed_ns),
            nsToSeconds(avg_wall_cell_ns *| remaining_cells),
            job.last_tick_cells,
            job.profiled_flushes,
        },
    ) catch "Terrain timing");

    if (job.active) {
        try core_ui.layout.sameLine(ui);
        if ((try ui_widgets.button(ui, "ed-world-terrain-geology-cancel", "Cancel", 68, false)).clicked) {
            if (state.terrain_batch_job) |*active_job| {
                active_job.active = false;
                active_job.cancelled = true;
                active_job.setStatus("Terrain batch cancelled");
                project_editor_state.setStatus(state, "Terrain batch cancelled");
            }
        }
        try core_ui.layout.endSameLine(ui);
    }
}

fn nowNs(state: *ProjectEditorState) u64 {
    const ns = std.Io.Clock.awake.now(state.io).nanoseconds;
    if (ns <= 0) return 0;
    return @intCast(ns);
}

fn durationSince(start_ns: u64, end_ns: u64) u64 {
    if (end_ns <= start_ns) return 0;
    return end_ns - start_ns;
}

fn nsToSeconds(ns: u64) f64 {
    return @as(f64, @floatFromInt(ns)) / @as(f64, @floatFromInt(std.time.ns_per_s));
}
