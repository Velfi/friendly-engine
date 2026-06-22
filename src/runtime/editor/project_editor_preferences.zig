const std = @import("std");
const friendly_engine = @import("friendly_engine");
const editor_core_ui = @import("editor_core_ui.zig");
const editor_settings = @import("editor_settings.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_terrain_undo_store = @import("project_editor_terrain_undo_store.zig");
const ui_widgets = @import("project_editor_ui_widgets.zig");

const core_ui = friendly_engine.modules.core_ui;
const ProjectEditorState = project_editor_state.ProjectEditorState;

pub const Context = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    host: *editor_core_ui.Host,
    settings: *editor_settings.OwnedEditorSettings,
};

pub fn build(ui: *core_ui.UiContext, state: *ProjectEditorState, ctx: *Context) !void {
    if (!state.preferences_open) return;

    const bounds = ui.frame_bounds;
    const width: f32 = @min(420, bounds.w - 48);
    const height: f32 = 388;
    const rect = core_ui.Rect{
        .x = bounds.x + (bounds.w - width) * 0.5,
        .y = bounds.y + @max(36, (bounds.h - height) * 0.30),
        .w = width,
        .h = height,
    };

    try core_ui.input_tree.pushOverlay(ui, rect);
    defer core_ui.input_tree.pop(ui);

    try ui.beginPanel(.{ .id = "ed-preferences", .rect = rect, .row_height = 26, .padding = 12, .spacing = 7 });
    try ui.label("Preferences");
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.button(ui, "ed-preferences-close", "Close", 64, false)).clicked) {
        state.preferences_open = false;
    }
    try core_ui.layout.endSameLine(ui);

    const scroll_h = try core_ui.layout.remainingPanelContentHeight(ui);
    try core_ui.layout.beginScrollArea(ui, .{ .id = "ed-preferences-scroll", .height = scroll_h, .input = core_ui.layout.panel_scroll_input });

    try core_ui.widgets_feedback.statusLabel(ui, "Theme");
    for (editor_settings.builtin_theme_choices) |choice| {
        const active = std.mem.eql(u8, ctx.settings.theme_file, choice.file);
        if ((try ui_widgets.buttonTip(ui, choice.file, choice.label, 120, active, choice.file)).clicked) {
            applyTheme(state, ctx, choice.file, choice.label);
        }
    }

    try core_ui.widgets_feedback.statusLabel(ui, "Active theme");
    try core_ui.widgets_feedback.statusLabel(ui, editor_settings.currentThemeLabel(ctx.settings.*));

    try core_ui.widgets_feedback.statusLabel(ui, "Refresh rate");
    try core_ui.layout.sameLine(ui);
    try refreshRateButton(ui, state, ctx, null, "Uncapped", 94);
    try refreshRateButton(ui, state, ctx, 30, "30", 48);
    try refreshRateButton(ui, state, ctx, 60, "60", 48);
    try refreshRateButton(ui, state, ctx, 90, "90", 48);
    try refreshRateButton(ui, state, ctx, 120, "120", 54);
    try refreshRateButton(ui, state, ctx, 144, "144", 54);
    try core_ui.layout.endSameLine(ui);

    try core_ui.widgets_feedback.statusLabel(ui, "Active refresh rate");
    try core_ui.widgets_feedback.statusLabel(ui, editor_settings.refreshRateLabel(ctx.settings.refresh_rate_hz));

    try core_ui.widgets_feedback.statusLabel(ui, "Terrain undo limit");
    try core_ui.layout.sameLine(ui);
    try terrainUndoLimitButton(ui, state, ctx, 0, "Unlimited", 94);
    try terrainUndoLimitButton(ui, state, ctx, 256, "256", 48);
    try terrainUndoLimitButton(ui, state, ctx, 512, "512", 48);
    try terrainUndoLimitButton(ui, state, ctx, 1024, "1 GB", 54);
    try terrainUndoLimitButton(ui, state, ctx, 2048, "2 GB", 54);
    try core_ui.layout.endSameLine(ui);

    try core_ui.widgets_feedback.statusLabel(ui, "Terrain undo usage");
    var usage_buf: [128]u8 = undefined;
    try core_ui.widgets_feedback.statusLabel(ui, terrainUndoUsageLabel(state, ctx, &usage_buf));

    try core_ui.layout.endScrollArea(ui);
    ui.endPanel();
}

fn applyTheme(
    state: *ProjectEditorState,
    ctx: *Context,
    theme_file: []const u8,
    label: []const u8,
) void {
    editor_settings.applyThemeFile(ctx.allocator, ctx.io, ctx.settings, theme_file) catch |err| {
        var buf: [96]u8 = undefined;
        const text = std.fmt.bufPrint(&buf, "Theme failed: {s}", .{@errorName(err)}) catch "Theme failed";
        project_editor_state.setStatus(state, text);
        return;
    };
    ctx.host.style = ctx.settings.style;

    var buf: [96]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "Theme set: {s}", .{label}) catch "Theme set";
    project_editor_state.setStatus(state, text);
}

fn refreshRateButton(
    ui: *core_ui.UiContext,
    state: *ProjectEditorState,
    ctx: *Context,
    refresh_rate_hz: ?u32,
    label: []const u8,
    width: f32,
) !void {
    const active = equalRefreshRate(ctx.settings.refresh_rate_hz, refresh_rate_hz);
    var id_buf: [32]u8 = undefined;
    const id = if (refresh_rate_hz) |hz|
        std.fmt.bufPrint(&id_buf, "ed-refresh-{d}", .{hz}) catch "ed-refresh"
    else
        "ed-refresh-uncapped";

    if ((try ui_widgets.buttonTip(ui, id, label, width, active, label)).clicked) {
        applyRefreshRate(state, ctx, refresh_rate_hz);
    }
}

fn applyRefreshRate(
    state: *ProjectEditorState,
    ctx: *Context,
    refresh_rate_hz: ?u32,
) void {
    editor_settings.applyRefreshRate(ctx.allocator, ctx.io, ctx.settings, refresh_rate_hz) catch |err| {
        var buf: [96]u8 = undefined;
        const text = std.fmt.bufPrint(&buf, "Refresh rate failed: {s}", .{@errorName(err)}) catch "Refresh rate failed";
        project_editor_state.setStatus(state, text);
        return;
    };

    var buf: [96]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "Refresh rate set: {s}", .{editor_settings.refreshRateLabel(refresh_rate_hz)}) catch "Refresh rate set";
    project_editor_state.setStatus(state, text);
}

fn equalRefreshRate(a: ?u32, b: ?u32) bool {
    if (a) |a_hz| {
        if (b) |b_hz| return a_hz == b_hz;
        return false;
    }
    return b == null;
}

fn terrainUndoLimitButton(
    ui: *core_ui.UiContext,
    state: *ProjectEditorState,
    ctx: *Context,
    limit_mb: u64,
    label: []const u8,
    width: f32,
) !void {
    const active = ctx.settings.terrain_undo_limit_mb == limit_mb;
    var id_buf: [40]u8 = undefined;
    const id = std.fmt.bufPrint(&id_buf, "ed-terrain-undo-{d}", .{limit_mb}) catch "ed-terrain-undo";
    if ((try ui_widgets.buttonTip(ui, id, label, width, active, editor_settings.terrainUndoLimitLabel(limit_mb))).clicked) {
        applyTerrainUndoLimit(state, ctx, limit_mb);
    }
}

fn applyTerrainUndoLimit(
    state: *ProjectEditorState,
    ctx: *Context,
    limit_mb: u64,
) void {
    editor_settings.applyTerrainUndoLimitMb(ctx.allocator, ctx.io, ctx.settings, limit_mb) catch |err| {
        var buf: [96]u8 = undefined;
        const text = std.fmt.bufPrint(&buf, "Terrain undo limit failed: {s}", .{@errorName(err)}) catch "Terrain undo limit failed";
        project_editor_state.setStatus(state, text);
        return;
    };
    state.terrain_undo_limit_mb = limit_mb;
    _ = project_editor_terrain_undo_store.enforceBudget(ctx.allocator, ctx.io, state.project_path, limit_mb) catch |err| {
        var buf: [96]u8 = undefined;
        const text = std.fmt.bufPrint(&buf, "Terrain undo prune failed: {s}", .{@errorName(err)}) catch "Terrain undo prune failed";
        project_editor_state.setStatus(state, text);
        return;
    };

    var buf: [96]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "Terrain undo limit set: {s}", .{editor_settings.terrainUndoLimitLabel(limit_mb)}) catch "Terrain undo limit set";
    project_editor_state.setStatus(state, text);
}

fn terrainUndoUsageLabel(state: *ProjectEditorState, ctx: *Context, buf: []u8) []const u8 {
    const usage = project_editor_terrain_undo_store.usage(ctx.allocator, ctx.io, state.project_path) catch |err| {
        return std.fmt.bufPrint(buf, "Unavailable: {s}", .{@errorName(err)}) catch "Unavailable";
    };
    var bytes_buf: [32]u8 = undefined;
    const bytes = project_editor_terrain_undo_store.formatBytes(&bytes_buf, usage.bytes);
    if (ctx.settings.terrain_undo_limit_mb == 0) {
        return std.fmt.bufPrint(buf, "{s} in {d} actions / unlimited", .{ bytes, usage.transactions }) catch "Terrain undo usage";
    }
    return std.fmt.bufPrint(buf, "{s} in {d} actions / {s}", .{
        bytes,
        usage.transactions,
        editor_settings.terrainUndoLimitLabel(ctx.settings.terrain_undo_limit_mb),
    }) catch "Terrain undo usage";
}
