const std = @import("std");
const shared = @import("runtime_shared");

const editor_command_file = @import("editor_command_file.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_terrain_undo_store = @import("project_editor_terrain_undo_store.zig");
const project_editor_world_authoring_heightmap_batch = @import("project_editor_world_authoring_heightmap_batch.zig");
const project_editor_world_authoring_terrain = @import("project_editor_world_authoring_terrain.zig");

const CommandFile = editor_command_file.CommandFile;
const ProjectEditorState = project_editor_state.ProjectEditorState;
const editor_math = shared.editor_math;

pub fn commandTerrainPoint(command: CommandFile) !editor_math.Vec3 {
    return .{
        .x = command.point_x orelse return error.MissingPoint,
        .y = command.point_y orelse 0,
        .z = command.point_z orelse return error.MissingPoint,
    };
}

pub fn terrainPointStatusJson(
    allocator: std.mem.Allocator,
    command: CommandFile,
    state: *ProjectEditorState,
    point: editor_math.Vec3,
) ![]u8 {
    return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"point\":{{\"x\":{d:.6},\"y\":{d:.6},\"z\":{d:.6}}},\"dirty_cells\":{d},\"status\":\"{s}\"}}\n", .{
        command.id,
        command.name,
        point.x,
        point.y,
        point.z,
        state.dirty_cells.count,
        state.status_buf[0..state.status_len],
    });
}

pub fn terrainHeightmapStatusJson(
    allocator: std.mem.Allocator,
    command: CommandFile,
    state: *ProjectEditorState,
    path: []const u8,
    point: editor_math.Vec3,
    result: project_editor_world_authoring_terrain.HeightmapLoadResult,
) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, 384);
    defer out.deinit(allocator);
    try appendFmt(allocator, &out, "{{\"ok\":true,\"id\":", .{});
    try appendJsonString(allocator, &out, command.id);
    try appendFmt(allocator, &out, ",\"command\":", .{});
    try appendJsonString(allocator, &out, command.name);
    try appendFmt(allocator, &out, ",\"path\":", .{});
    try appendJsonString(allocator, &out, path);
    try appendFmt(allocator, &out, ",\"point\":{{\"x\":{d:.6},\"y\":{d:.6},\"z\":{d:.6}}},\"cell\":{{\"x\":{d},\"y\":{d},\"z\":{d}}},\"height_range\":{{\"min\":{d:.6},\"max\":{d:.6}}},\"source\":{{\"width\":{d},\"height\":{d}}},\"dirty_cells\":{d},\"status\":", .{
        point.x,
        point.y,
        point.z,
        result.cell.x,
        result.cell.y,
        result.cell.z,
        result.min_height,
        result.max_height,
        result.source_width,
        result.source_height,
        state.dirty_cells.count,
    });
    try appendJsonString(allocator, &out, state.status_buf[0..state.status_len]);
    try appendFmt(allocator, &out, "}}\n", .{});
    return out.toOwnedSlice(allocator);
}

pub fn terrainHeightmapBatchStatusJson(
    allocator: std.mem.Allocator,
    command: CommandFile,
    state: *ProjectEditorState,
    path: []const u8,
    result: project_editor_world_authoring_heightmap_batch.BatchResult,
) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, 512);
    defer out.deinit(allocator);
    try appendFmt(allocator, &out, "{{\"ok\":true,\"id\":", .{});
    try appendJsonString(allocator, &out, command.id);
    try appendFmt(allocator, &out, ",\"command\":", .{});
    try appendJsonString(allocator, &out, command.name);
    try appendFmt(allocator, &out, ",\"path\":", .{});
    try appendJsonString(allocator, &out, path);
    try appendFmt(allocator, &out, ",\"bounds\":{{\"min_x\":{d},\"max_x\":{d},\"min_z\":{d},\"max_z\":{d}}},\"cell_size_m\":{d:.6},\"cells\":{d},\"height_range\":{{\"min\":{d:.6},\"max\":{d:.6}}},\"source\":{{\"width\":{d},\"height\":{d}}},\"albedo_source\":{{\"width\":{d},\"height\":{d}}},\"dirty_cells\":{d},\"dirty_overflow\":{},\"status\":", .{
        result.min_x,
        result.max_x,
        result.min_z,
        result.max_z,
        result.cell_size_m,
        result.cells,
        result.min_height,
        result.max_height,
        result.source_width,
        result.source_height,
        result.albedo_source_width,
        result.albedo_source_height,
        state.dirty_cells.count,
        result.dirty_overflow,
    });
    try appendJsonString(allocator, &out, state.status_buf[0..state.status_len]);
    try appendFmt(allocator, &out, "}}\n", .{});
    return out.toOwnedSlice(allocator);
}

pub fn terrainGeologyStatusJson(
    allocator: std.mem.Allocator,
    command: CommandFile,
    state: *ProjectEditorState,
) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, 512);
    defer out.deinit(allocator);
    try appendFmt(allocator, &out, "{{\"ok\":true,\"id\":", .{});
    try appendJsonString(allocator, &out, command.id);
    try appendFmt(allocator, &out, ",\"command\":", .{});
    try appendJsonString(allocator, &out, command.name);
    if (state.terrain_batch_job) |job| {
        const percent = if (job.total == 0) 100 else (@as(f64, @floatFromInt(job.next_offset)) / @as(f64, @floatFromInt(job.total))) * 100.0;
        const avg_cell_ns = if (job.profiled_cells == 0) 0 else job.total_total_ns / job.profiled_cells;
        const remaining_cells = if (job.total > job.next_offset) job.total - job.next_offset else 0;
        const elapsed_ns = durationSince(job.started_ns, commandNowNs(state));
        const avg_wall_cell_ns = if (job.next_offset == 0) @as(u64, 0) else elapsed_ns / job.next_offset;
        const remaining_wall_ns = avg_wall_cell_ns *| remaining_cells;
        const total_wall_ns = avg_wall_cell_ns *| job.total;
        try appendFmt(allocator, &out, ",\"job\":{{\"id\":{d},\"active\":{},\"complete\":{},\"cancelled\":{},\"failed\":{},\"processed\":{d},\"total\":{d},\"percent\":{d:.2},\"batch_size\":{d},\"cell_size_m\":{d:.3},\"bounds\":{{\"min_x\":{d},\"max_x\":{d},\"min_z\":{d},\"max_z\":{d}}},\"height_range\":{{\"min\":{d:.3},\"max\":{d:.3}}},\"formations\":{d}", .{
            job.id,
            job.active,
            job.complete,
            job.cancelled,
            job.failed,
            job.next_offset,
            job.total,
            percent,
            job.batch_size,
            job.cell_size_m,
            job.min_x,
            job.max_x,
            job.min_z,
            job.max_z,
            if (std.math.isFinite(job.min_height)) job.min_height else 0,
            if (std.math.isFinite(job.max_height)) job.max_height else 0,
            job.formation_count,
        });
        try appendFmt(allocator, &out, ",\"profile\":{{\"cells\":{d},\"last_ms\":{{\"scene\":{d:.3},\"tile\":{d:.3},\"manifest\":{d:.3},\"index\":{d:.3},\"dirty\":{d:.3},\"total\":{d:.3}}}", .{
            job.profiled_cells,
            nsToMs(job.last_scene_ns),
            nsToMs(job.last_tile_ns),
            nsToMs(job.last_manifest_ns),
            nsToMs(job.last_index_ns),
            nsToMs(job.last_dirty_ns),
            nsToMs(job.last_total_ns),
        });
        try appendFmt(allocator, &out, ",\"avg_ms\":{{\"scene\":{d:.3},\"tile\":{d:.3},\"manifest\":{d:.3},\"index\":{d:.3},\"dirty\":{d:.3},\"total\":{d:.3}}},\"eta\":{{\"remaining_cells\":{d},\"elapsed_seconds\":{d:.1},\"remaining_seconds\":{d:.1},\"total_seconds\":{d:.1},\"work_total_seconds\":{d:.1}}}", .{
            avgNsToMs(job.total_scene_ns, job.profiled_cells),
            avgNsToMs(job.total_tile_ns, job.profiled_cells),
            avgNsToMs(job.total_manifest_ns, job.profiled_cells),
            avgNsToMs(job.total_index_ns, job.profiled_cells),
            avgNsToMs(job.total_dirty_ns, job.profiled_cells),
            avgNsToMs(job.total_total_ns, job.profiled_cells),
            remaining_cells,
            nsToSeconds(elapsed_ns),
            nsToSeconds(remaining_wall_ns),
            nsToSeconds(total_wall_ns),
            nsToSeconds(avg_cell_ns *| job.total),
        });
        try out.append(allocator, '}');
        try appendFmt(allocator, &out, ",\"scheduler\":{{\"tick_budget_ms\":{d:.3},\"flush_interval_cells\":{d},\"flushed_cells\":{d},\"last_tick_cells\":{d},\"last_tick_ms\":{d:.3},\"avg_tick_ms\":{d:.3},\"flushes\":{d},\"last_flush_ms\":{d:.3},\"avg_flush_ms\":{d:.3}}}", .{
            nsToMs(job.tick_budget_ns),
            job.flush_interval_cells,
            job.flushed_offset,
            job.last_tick_cells,
            nsToMs(job.last_tick_ns),
            avgNsToMs(job.total_tick_ns, job.profiled_ticks),
            job.profiled_flushes,
            nsToMs(job.last_flush_ns),
            avgNsToMs(job.total_flush_ns, job.profiled_flushes),
        });
        try out.appendSlice(allocator, ",\"status\":");
        try appendJsonString(allocator, &out, job.status());
        try appendFmt(allocator, &out, "}}", .{});
    } else {
        try appendFmt(allocator, &out, ",\"job\":null", .{});
    }
    try appendFmt(allocator, &out, "}}\n", .{});
    return out.toOwnedSlice(allocator);
}

pub fn terrainEdgeCliffStatusJson(
    allocator: std.mem.Allocator,
    command: CommandFile,
    state: *ProjectEditorState,
) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, 512);
    defer out.deinit(allocator);
    try appendFmt(allocator, &out, "{{\"ok\":true,\"id\":", .{});
    try appendJsonString(allocator, &out, command.id);
    try appendFmt(allocator, &out, ",\"command\":", .{});
    try appendJsonString(allocator, &out, command.name);
    if (state.terrain_edge_cliff_job) |job| {
        const percent = if (job.total == 0) 100 else (@as(f64, @floatFromInt(job.next_offset)) / @as(f64, @floatFromInt(job.total))) * 100.0;
        const elapsed_ns = durationSince(job.started_ns, commandNowNs(state));
        const remaining_offsets = if (job.total > job.next_offset) job.total - job.next_offset else 0;
        const avg_offset_ns = if (job.next_offset == 0) @as(u64, 0) else elapsed_ns / job.next_offset;
        try appendFmt(allocator, &out, ",\"job\":{{\"id\":{d},\"active\":{},\"complete\":{},\"cancelled\":{},\"failed\":{},\"processed\":{d},\"rim_cells_processed\":{d},\"total\":{d},\"percent\":{d:.2},\"cell_size_m\":{d:.3},\"height\":{d:.3},\"width\":{d:.3},\"bounds\":{{\"min_x\":{d},\"max_x\":{d},\"min_z\":{d},\"max_z\":{d}}},\"changed_cells\":{d},\"affected_samples\":{d},\"min_height\":{d:.3},\"max_drop\":{d:.3},\"dirty_overflow\":{}", .{
            job.id,
            job.active,
            job.complete,
            job.cancelled,
            job.failed,
            job.next_offset,
            job.processed_cells,
            job.total,
            percent,
            job.cell_size_m,
            job.bottom_height,
            job.width_m,
            job.min_x,
            job.max_x,
            job.min_z,
            job.max_z,
            job.changed_cells,
            job.changed_samples,
            if (std.math.isFinite(job.min_height)) job.min_height else job.bottom_height,
            job.max_drop,
            job.dirty_overflow,
        });
        try appendFmt(allocator, &out, ",\"scheduler\":{{\"tick_budget_ms\":{d:.3},\"last_tick_cells\":{d},\"last_tick_ms\":{d:.3}}}", .{
            nsToMs(job.tick_budget_ns),
            job.last_tick_cells,
            nsToMs(job.last_tick_ns),
        });
        try appendFmt(allocator, &out, ",\"eta\":{{\"remaining_cells\":{d},\"elapsed_seconds\":{d:.1},\"remaining_seconds\":{d:.1}}}", .{
            remaining_offsets,
            nsToSeconds(elapsed_ns),
            nsToSeconds(avg_offset_ns *| remaining_offsets),
        });
        try out.appendSlice(allocator, ",\"status\":");
        try appendJsonString(allocator, &out, job.status());
        try appendFmt(allocator, &out, "}}", .{});
    } else {
        try appendFmt(allocator, &out, ",\"job\":null", .{});
    }
    try appendFmt(allocator, &out, "}}\n", .{});
    return out.toOwnedSlice(allocator);
}

pub fn terrainStretchSmoothStatusJson(
    allocator: std.mem.Allocator,
    command: CommandFile,
    state: *ProjectEditorState,
) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, 640);
    defer out.deinit(allocator);
    try appendFmt(allocator, &out, "{{\"ok\":true,\"id\":", .{});
    try appendJsonString(allocator, &out, command.id);
    try appendFmt(allocator, &out, ",\"command\":", .{});
    try appendJsonString(allocator, &out, command.name);
    if (state.terrain_stretch_smooth_job) |job| {
        const percent = if (job.total == 0) 100 else (@as(f64, @floatFromInt(job.next_offset)) / @as(f64, @floatFromInt(job.total))) * 100.0;
        const elapsed_ns = durationSince(job.started_ns, commandNowNs(state));
        const remaining_cells = if (job.total > job.next_offset) job.total - job.next_offset else 0;
        const avg_cell_ns = if (job.next_offset == 0) @as(u64, 0) else elapsed_ns / job.next_offset;
        const avg_delta = if (job.changed_samples == 0) @as(f32, 0) else job.total_delta / @as(f32, @floatFromInt(job.changed_samples));
        const min_height = if (std.math.isFinite(job.min_height)) job.min_height else -999999.0;
        const max_height = if (std.math.isFinite(job.max_height)) job.max_height else 999999.0;
        try appendFmt(allocator, &out, ",\"job\":{{\"id\":{d},\"active\":{},\"complete\":{},\"cancelled\":{},\"failed\":{},\"processed\":{d},\"inspected_cells\":{d},\"total\":{d},\"percent\":{d:.2},\"cell_size_m\":{d:.3},\"threshold\":{d:.3},\"strength\":{d:.3},\"iterations\":{d},\"current_pass\":{d},\"max_samples_per_cell\":{d},\"height_filter\":{{\"min\":{d:.3},\"max\":{d:.3}}},\"bounds\":{{\"min_x\":{d},\"max_x\":{d},\"min_z\":{d},\"max_z\":{d}}},\"changed_cells\":{d},\"changed_samples\":{d},\"pass_changed_cells\":{d},\"pass_changed_samples\":{d},\"undo_transaction_id\":{d},\"undo_snapshots\":{d},\"max_detected_delta\":{d:.3},\"average_height_change\":{d:.3},\"dirty_overflow\":{}", .{
            job.id,
            job.active,
            job.complete,
            job.cancelled,
            job.failed,
            job.next_offset,
            job.processed_cells,
            job.total,
            percent,
            job.cell_size_m,
            job.threshold_m,
            job.strength,
            job.iterations,
            job.current_pass,
            job.max_samples_per_cell,
            min_height,
            max_height,
            job.min_x,
            job.max_x,
            job.min_z,
            job.max_z,
            job.changed_cells,
            job.changed_samples,
            job.pass_changed_cells,
            job.pass_changed_samples,
            job.undo_transaction_id,
            job.undo_snapshots,
            job.max_delta,
            avg_delta,
            job.dirty_overflow,
        });
        try appendFmt(allocator, &out, ",\"scheduler\":{{\"tick_budget_ms\":{d:.3},\"last_tick_cells\":{d},\"last_tick_ms\":{d:.3}}}", .{
            nsToMs(job.tick_budget_ns),
            job.last_tick_cells,
            nsToMs(job.last_tick_ns),
        });
        try appendFmt(allocator, &out, ",\"eta\":{{\"remaining_cells\":{d},\"elapsed_seconds\":{d:.1},\"remaining_seconds\":{d:.1}}}", .{
            remaining_cells,
            nsToSeconds(elapsed_ns),
            nsToSeconds(avg_cell_ns *| remaining_cells),
        });
        try out.appendSlice(allocator, ",\"status\":");
        try appendJsonString(allocator, &out, job.status());
        try appendFmt(allocator, &out, "}}", .{});
    } else {
        try appendFmt(allocator, &out, ",\"job\":null", .{});
    }
    try appendFmt(allocator, &out, "}}\n", .{});
    return out.toOwnedSlice(allocator);
}

pub fn terrainUndoStatusJson(
    allocator: std.mem.Allocator,
    command: CommandFile,
    state: *ProjectEditorState,
    restored: ?project_editor_terrain_undo_store.Transaction,
) ![]u8 {
    const usage = try project_editor_terrain_undo_store.usage(allocator, state.io, state.project_path);
    var out = try std.ArrayList(u8).initCapacity(allocator, 256);
    defer out.deinit(allocator);
    try appendFmt(allocator, &out, "{{\"ok\":true,\"id\":", .{});
    try appendJsonString(allocator, &out, command.id);
    try appendFmt(allocator, &out, ",\"command\":", .{});
    try appendJsonString(allocator, &out, command.name);
    if (restored) |tx| {
        try appendFmt(allocator, &out, ",\"restored\":true,\"transaction_id\":{d}", .{tx.id});
    } else {
        try appendFmt(allocator, &out, ",\"restored\":false", .{});
    }
    try appendFmt(allocator, &out, ",\"usage\":{{\"bytes\":{d},\"transactions\":{d},\"limit_mb\":{d}}},\"status\":", .{
        usage.bytes,
        usage.transactions,
        state.terrain_undo_limit_mb,
    });
    try appendJsonString(allocator, &out, state.status_buf[0..state.status_len]);
    try appendFmt(allocator, &out, "}}\n", .{});
    return out.toOwnedSlice(allocator);
}

pub fn terrainJobActive(state: *const ProjectEditorState) bool {
    if (state.terrain_batch_job) |job| if (job.active and !job.complete and !job.cancelled and !job.failed) return true;
    if (state.terrain_edge_cliff_job) |job| if (job.active and !job.complete and !job.cancelled and !job.failed) return true;
    if (state.terrain_recipe_job) |job| if (job.active and !job.complete and !job.cancelled and !job.failed) return true;
    if (state.terrain_stretch_smooth_job) |job| if (job.active and !job.complete and !job.cancelled and !job.failed) return true;
    return false;
}

pub fn terrainRecipeStatusJson(
    allocator: std.mem.Allocator,
    command: CommandFile,
    state: *ProjectEditorState,
) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, 512);
    defer out.deinit(allocator);
    try appendFmt(allocator, &out, "{{\"ok\":true,\"id\":", .{});
    try appendJsonString(allocator, &out, command.id);
    try appendFmt(allocator, &out, ",\"command\":", .{});
    try appendJsonString(allocator, &out, command.name);
    if (state.terrain_recipe_job) |job| {
        const percent = if (job.total == 0) 100 else (@as(f64, @floatFromInt(job.next_offset)) / @as(f64, @floatFromInt(job.total))) * 100.0;
        const elapsed_ns = durationSince(job.started_ns, commandNowNs(state));
        const remaining_cells = if (job.total > job.next_offset) job.total - job.next_offset else 0;
        const avg_cell_ns = if (job.next_offset == 0) @as(u64, 0) else elapsed_ns / job.next_offset;
        try appendFmt(allocator, &out, ",\"job\":{{\"id\":{d},\"active\":{},\"complete\":{},\"cancelled\":{},\"failed\":{},\"processed\":{d},\"total\":{d},\"percent\":{d:.2},\"cell_size_m\":{d:.3},\"seed\":{d},\"sea_level\":{d:.3},\"ocean_floor\":{d:.3},\"bounds\":{{\"min_x\":{d},\"max_x\":{d},\"min_z\":{d},\"max_z\":{d}}},\"height_range\":{{\"min\":{d:.3},\"max\":{d:.3}}},\"features\":{d},\"changed_cells\":{d},\"dirty_overflow\":{}", .{
            job.id,
            job.active,
            job.complete,
            job.cancelled,
            job.failed,
            job.next_offset,
            job.total,
            percent,
            job.cell_size_m,
            job.seed,
            job.sea_level,
            job.ocean_floor,
            job.min_x,
            job.max_x,
            job.min_z,
            job.max_z,
            if (std.math.isFinite(job.min_height)) job.min_height else 0,
            if (std.math.isFinite(job.max_height)) job.max_height else 0,
            job.feature_count,
            job.changed_cells,
            job.dirty_overflow,
        });
        try appendFmt(allocator, &out, ",\"scheduler\":{{\"tick_budget_ms\":{d:.3},\"last_tick_cells\":{d},\"last_tick_ms\":{d:.3}}}", .{
            nsToMs(job.tick_budget_ns),
            job.last_tick_cells,
            nsToMs(job.last_tick_ns),
        });
        try appendFmt(allocator, &out, ",\"eta\":{{\"remaining_cells\":{d},\"elapsed_seconds\":{d:.1},\"remaining_seconds\":{d:.1}}}", .{
            remaining_cells,
            nsToSeconds(elapsed_ns),
            nsToSeconds(avg_cell_ns *| remaining_cells),
        });
        try out.appendSlice(allocator, ",\"status\":");
        try appendJsonString(allocator, &out, job.status());
        try appendFmt(allocator, &out, "}}", .{});
    } else {
        try appendFmt(allocator, &out, ",\"job\":null", .{});
    }
    try appendFmt(allocator, &out, "}}\n", .{});
    return out.toOwnedSlice(allocator);
}

fn nsToMs(ns: u64) f64 {
    return @as(f64, @floatFromInt(ns)) / @as(f64, @floatFromInt(std.time.ns_per_ms));
}

fn avgNsToMs(total_ns: u64, count: u64) f64 {
    if (count == 0) return 0;
    return nsToMs(total_ns / count);
}

fn nsToSeconds(ns: u64) f64 {
    return @as(f64, @floatFromInt(ns)) / @as(f64, @floatFromInt(std.time.ns_per_s));
}

fn commandNowNs(state: *ProjectEditorState) u64 {
    const ns = std.Io.Clock.awake.now(state.io).nanoseconds;
    if (ns <= 0) return 0;
    return @intCast(ns);
}

fn durationSince(start_ns: u64, end_ns: u64) u64 {
    if (end_ns <= start_ns) return 0;
    return end_ns - start_ns;
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
