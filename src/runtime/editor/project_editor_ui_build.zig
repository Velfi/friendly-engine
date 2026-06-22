const std = @import("std");
const builtin = @import("builtin");
const build_info = @import("build_info");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const sdl = shared.sdl;
const command_ids = shared.editor_command_ids;
const scene_marker = shared.scene_marker;
const editor_math = shared.editor_math;
const project_editor_edit = @import("project_editor_edit.zig");
const project_editor_build = @import("project_editor_build.zig");
const project_editor_scene = @import("project_editor_scene.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_types = @import("project_editor_types.zig");
const project_editor_view_nav = @import("project_editor_view_nav.zig");
const editor_frame_perf = @import("editor_frame_perf.zig");
const project_editor_ui_life = @import("project_editor_ui_life.zig");
const ui_world = @import("project_editor_ui_world.zig");
const project_editor_ui_prop = @import("project_editor_ui_prop.zig");
const project_editor_preferences = @import("project_editor_preferences.zig");
const viewport_context_menu = @import("project_editor_viewport_context_menu.zig");
const ui_build_left = @import("project_editor_ui_build_left.zig");
const ui_build_palette = @import("project_editor_ui_build_palette.zig");
const project_editor_modes = @import("project_editor_modes.zig");
const shape_source = @import("shape_source.zig");
const shape_operation = @import("shape_operation.zig");

const core_ui = friendly_engine.modules.core_ui;
const ProjectEditorState = project_editor_state.ProjectEditorState;
const ui_widgets = @import("project_editor_ui_widgets.zig");
const ui_inspector = @import("project_editor_ui_inspector.zig");
const ui_architecture = @import("project_editor_ui_architecture.zig");
const ui_layout = @import("project_editor_ui_layout.zig");

pub const Layout = struct {
    top: core_ui.Rect,
    left: core_ui.Rect,
    viewport: core_ui.Rect,
    inspector: core_ui.Rect,
    timeline: core_ui.Rect,
    bottom: core_ui.Rect,
};

pub fn computeLayout(window_w: f32, window_h: f32, state: *const ProjectEditorState) Layout {
    const pad: f32 = 10;
    const gap: f32 = 6;
    const menubar_h: f32 = if (builtin.os.tag != .macos) 30 else 0;
    const top_h: f32 = 52;
    const bottom_h: f32 = 30;
    const timeline_h: f32 = if (state.mode == .life) project_editor_ui_life.timeline_height else 0;
    const timeline_gap: f32 = if (state.mode == .life) gap else 0;
    const left_w: f32 = if (state.show_tool_inspector) 256 else 0;
    const inspector_w: f32 = if (state.show_project_inspector) 276 else 0;
    const left_gap: f32 = if (state.show_tool_inspector) gap else 0;
    const inspector_gap: f32 = if (state.show_project_inspector) gap else 0;
    const top_y = pad + menubar_h;
    const content_y = top_y + top_h + gap;
    const content_h = @max(220, window_h - content_y - bottom_h - pad - gap - timeline_h - timeline_gap);
    const viewport_w = @max(320, window_w - pad * 2 - left_w - inspector_w - left_gap - inspector_gap);
    const left = core_ui.Rect{ .x = pad, .y = content_y, .w = left_w, .h = content_h };
    const viewport = core_ui.Rect{ .x = left.x + left.w + left_gap, .y = content_y, .w = viewport_w, .h = content_h };
    const timeline_y = content_y + content_h + gap;
    const bottom_y = timeline_y + timeline_h + timeline_gap;
    return .{
        .top = .{ .x = pad, .y = top_y, .w = window_w - pad * 2, .h = top_h },
        .left = left,
        .viewport = viewport,
        .inspector = .{ .x = viewport.x + viewport.w + inspector_gap, .y = content_y, .w = inspector_w, .h = content_h },
        .timeline = .{ .x = pad, .y = timeline_y, .w = window_w - pad * 2, .h = timeline_h },
        .bottom = .{ .x = pad, .y = bottom_y, .w = window_w - pad * 2, .h = bottom_h },
    };
}

pub fn build(ui: *core_ui.UiContext, state: *ProjectEditorState, layout: Layout, preferences: ?*project_editor_preferences.Context) !void {
    var start_ns = friendly_engine.core.diagnostics.scopedTimerStart();
    try buildTopBar(ui, state, layout.top);
    recordUiSection(state, .ui_top_bar, start_ns);

    start_ns = friendly_engine.core.diagnostics.scopedTimerStart();
    if (state.show_tool_inspector) try ui_build_left.buildLeftInspector(ui, state, layout.left);
    recordUiSection(state, .ui_left_panel, start_ns);

    start_ns = friendly_engine.core.diagnostics.scopedTimerStart();
    try buildViewportToolbar(ui, state, layout.viewport);
    recordUiSection(state, .ui_viewport_toolbar, start_ns);

    start_ns = friendly_engine.core.diagnostics.scopedTimerStart();
    if (state.show_project_inspector) try ui_inspector.buildRightInspector(ui, state, layout.inspector);
    recordUiSection(state, .ui_right_inspector, start_ns);

    start_ns = friendly_engine.core.diagnostics.scopedTimerStart();
    if (state.mode == .life and layout.timeline.h > 0) {
        try project_editor_ui_life.buildTimeline(ui, state, layout.timeline);
    }
    recordUiSection(state, .ui_timeline, start_ns);

    start_ns = friendly_engine.core.diagnostics.scopedTimerStart();
    try buildBottomStrip(ui, state, layout.bottom);
    recordUiSection(state, .ui_bottom_strip, start_ns);

    start_ns = friendly_engine.core.diagnostics.scopedTimerStart();
    if (preferences) |ctx| try project_editor_preferences.build(ui, state, ctx);
    recordUiSection(state, .ui_preferences, start_ns);

    _ = try viewport_context_menu.build(ui, state);

    if (state.editor_error_detail != null) {
        try buildEditorErrorModal(ui, state);
    }
}

fn recordUiSection(state: *ProjectEditorState, scope: editor_frame_perf.Scope, start_ns: i128) void {
    const elapsed_ns = friendly_engine.core.diagnostics.scopedTimerElapsedNs(start_ns);
    state.frame_perf.recordScope(scope, @as(f64, @floatFromInt(elapsed_ns)) / std.time.ns_per_ms);
}

fn buildTopBar(ui: *core_ui.UiContext, state: *ProjectEditorState, rect: core_ui.Rect) !void {
    try ui.beginPanel(.{ .id = "ed-top", .rect = rect, .row_height = 26, .padding = 7, .spacing = 6 });
    var title_buf: [288]u8 = undefined;
    const title_text = if (build_info.show_build_hash)
        std.fmt.bufPrint(&title_buf, "{s} #{s}", .{ state.project_name, build_info.build_hash }) catch state.project_name
    else
        state.project_name;
    try ui_widgets.text(ui, "ed-title", .{ .x = rect.x + 12, .y = rect.y + 6, .w = 240, .h = 18 }, title_text, false);
    try ui_widgets.text(ui, "ed-scene", .{ .x = rect.x + 12, .y = rect.y + 28, .w = 240, .h = 14 }, if (state.scene_dirty) "main scene *" else "main scene", true);
    var mode_buf: [96]u8 = undefined;
    try ui_widgets.text(ui, "ed-current-tool", .{ .x = rect.x + 268, .y = rect.y + 14, .w = 176, .h = 18 }, std.fmt.bufPrint(&mode_buf, "{s} / {s}", .{ state.mode.label(), project_editor_modes.toolLabel(state) }) catch state.mode.label(), true);
    const mode_buttons_w: f32 = 724;
    const start_x = @max(rect.x + 456, rect.x + rect.w - mode_buttons_w);
    try ui_widgets.rowAt(ui, start_x, rect.y + 10);
    if ((try ui_widgets.iconButtonTip(ui, "ed-save", "save", false, "Ctrl+S Save")).clicked) try ui_widgets.saveScene(state);
    if ((try ui_widgets.iconButtonTip(ui, command_ids.play_scene, "play", state.is_playing, "Play scene")).clicked) {
        state.is_playing = true;
        defer state.is_playing = false;
        project_editor_build.runPlayScene(state) catch |err| {
            if (state.editor_error_detail == null) {
                var buf: [96]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "Play scene failed: {s}", .{@errorName(err)}) catch "Play scene failed";
                project_editor_state.setStatus(state, msg);
            }
        };
    }
    if ((try ui_widgets.iconButtonTip(ui, "ed-build", "build", false, "Build")).clicked) project_editor_build.runBuild(state);
    if ((try ui_widgets.iconButtonTip(ui, "ed-preferences-open", "settings", state.preferences_open, "Preferences")).clicked) {
        state.preferences_open = !state.preferences_open;
    }
    if ((try ui_widgets.iconButtonTip(ui, "ed-show-me-mode", if (state.show_me_mode_enabled) "eye" else "eye-closed", state.show_me_mode_enabled, if (state.show_me_mode_enabled) "Show me mode on" else "Show me mode off")).clicked) {
        state.show_me_mode_enabled = !state.show_me_mode_enabled;
        project_editor_state.setStatus(state, if (state.show_me_mode_enabled) "Show me mode on" else "Show me mode off");
    }
    if ((try ui_widgets.iconButtonTip(ui, command_ids.toggle_tool_inspector, if (state.show_tool_inspector) "eye" else "eye-closed", state.show_tool_inspector, if (state.show_tool_inspector) "Hide tool inspector" else "Show tool inspector")).clicked) {
        state.show_tool_inspector = !state.show_tool_inspector;
    }
    if ((try ui_widgets.iconButtonTip(ui, command_ids.toggle_project_inspector, if (state.show_project_inspector) "eye" else "eye-closed", state.show_project_inspector, if (state.show_project_inspector) "Hide project inspector" else "Show project inspector")).clicked) {
        state.show_project_inspector = !state.show_project_inspector;
    }
    for (project_editor_modes.all) |mode_desc| {
        if (!project_editor_modes.enabled(state, mode_desc.mode)) continue;
        const mode_w: f32 = switch (mode_desc.mode) {
            .world_creation => 74,
            .layout => 72,
            .architecture_creation => 116,
            .prop_creation => 60,
            .life => 56,
        };
        if ((try ui_widgets.button(ui, mode_desc.command_id, mode_desc.label, mode_w, state.mode == mode_desc.mode)).clicked) {
            _ = project_editor_modes.activate(state, mode_desc.mode);
        }
    }
    try core_ui.layout.endSameLine(ui);
    ui.endPanel();
}

fn buildEditorErrorModal(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    const window_w = state.window_w;
    const window_h = state.window_h;
    const backdrop = core_ui.Rect{ .x = 0, .y = 0, .w = window_w, .h = window_h };
    try core_ui.input_tree.pushOverlay(ui, backdrop);
    defer core_ui.input_tree.pop(ui);
    try ui.pushCommand(.{ .panel = .{ .id = 9001, .rect = backdrop } });

    const modal_w = @min(760.0, @max(420.0, window_w - 80.0));
    const modal_h = @min(520.0, @max(300.0, window_h - 80.0));
    const rect = core_ui.Rect{ .x = (window_w - modal_w) * 0.5, .y = (window_h - modal_h) * 0.5, .w = modal_w, .h = modal_h };
    try ui.beginPanel(.{ .id = "ed-error-modal", .rect = rect, .row_height = 26, .padding = 12, .spacing = 8 });
    defer ui.endPanel();

    try ui.label(state.editor_error_title orelse "Editor Error");
    try core_ui.widgets_feedback.statusLabel(ui, "Copy the details below when reporting this failure.");

    const detail = state.editor_error_detail orelse "";
    const detail_rect = try ui.allocFullWidthRow(@max(140.0, modal_h - 132.0));
    try ui.pushCommand(.{ .panel = .{ .id = 9002, .rect = detail_rect } });
    try renderErrorDetailLines(ui, detail_rect, detail);

    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.button(ui, "ed-error-copy", "Copy Details", 116, false)).clicked) {
        const owned_z = try state.allocator.dupeZ(u8, detail);
        defer state.allocator.free(owned_z);
        if (sdl.SDL_SetClipboardText(owned_z.ptr)) {
            project_editor_state.setStatus(state, "Failure details copied");
        } else {
            project_editor_state.setStatus(state, "Copy failed");
        }
    }
    if ((try ui_widgets.button(ui, "ed-error-close", "Close", 82, false)).clicked) {
        project_editor_state.clearEditorErrorDetail(state);
    }
    try core_ui.layout.endSameLine(ui);
}

fn renderErrorDetailLines(ui: *core_ui.UiContext, rect: core_ui.Rect, detail: []const u8) !void {
    const line_h: f32 = 15.0;
    const max_lines: usize = @intFromFloat(@max(1.0, @floor((rect.h - 12.0) / line_h)));
    var line_iter = std.mem.splitScalar(u8, detail, '\n');
    var line_index: usize = 0;
    while (line_iter.next()) |line| {
        if (line_index >= max_lines) break;
        var id_buf: [48]u8 = undefined;
        const id = std.fmt.bufPrint(&id_buf, "ed-error-line-{d}", .{line_index}) catch "ed-error-line";
        const line_rect = core_ui.Rect{
            .x = rect.x + 10.0,
            .y = rect.y + 8.0 + (@as(f32, @floatFromInt(line_index)) * line_h),
            .w = rect.w - 20.0,
            .h = line_h,
        };
        try ui_widgets.text(ui, id, line_rect, truncateLine(line, 150), false);
        line_index += 1;
    }
}

fn truncateLine(line: []const u8, max_len: usize) []const u8 {
    if (line.len <= max_len) return line;
    return line[0..max_len];
}

fn buildViewportToolbar(ui: *core_ui.UiContext, state: *ProjectEditorState, viewport: core_ui.Rect) !void {
    if (!state.show_viewport_toolbar) {
        return;
    }

    const has_primary_tool_panel = true;
    if (has_primary_tool_panel) {
        const tool_w: f32 = if (state.selection_scope == .marker)
            viewport.w - 16
        else
            project_editor_modes.desc(state.mode).toolbar_width + 288;
        const tool_h: f32 = switch (state.mode) {
            .prop_creation, .architecture_creation => 62,
            else => 34,
        };
        const primary_h: f32 = if (state.selection_scope == .marker) 62 else tool_h;
        const tool_rect = core_ui.Rect{ .x = viewport.x + 8, .y = viewport.y + 8, .w = @min(tool_w, viewport.w - 16), .h = primary_h };
        try ui.beginPanel(.{ .id = "ed-viewport-tools", .rect = tool_rect, .row_height = 24, .padding = 5, .spacing = 4 });
        try core_ui.layout.sameLine(ui);
        try buildSelectionScopeStrip(ui, state);
        if (state.selection_scope == .marker) {
            try core_ui.layout.endSameLine(ui);
            try core_ui.layout.sameLine(ui);
            try buildGameMarkerTools(ui, state);
        } else {
            try buildModeToolButtons(ui, state);
        }
        try core_ui.layout.endSameLine(ui);
        ui.endPanel();
    }

    const secondary_offset: f32 = if (state.selection_scope == .marker or state.mode == .prop_creation or state.mode == .architecture_creation) 76.0 else 48.0;
    const secondary_y: f32 = if (has_primary_tool_panel) viewport.y + secondary_offset else viewport.y + 8;
    const view_y: f32 = if (state.mode == .architecture_creation) viewport.y + 116 else secondary_y;
    if (state.mode == .architecture_creation) {
        const secondary_rect = core_ui.Rect{ .x = viewport.x + 8, .y = secondary_y, .w = @min(560, viewport.w - 16), .h = 34 };
        try ui.beginPanel(.{ .id = "ed-viewport-arch-secondary", .rect = secondary_rect, .row_height = 24, .padding = 5, .spacing = 4 });
        try core_ui.layout.sameLine(ui);
        try ui_architecture.buildSecondaryStrip(ui, state);
        try core_ui.layout.endSameLine(ui);
        ui.endPanel();
    }

    if (state.mode == .prop_creation) {
        try buildPropViewportViewControls(ui, state, viewport, secondary_y);
        try buildViewportStateHud(ui, state, viewport);
        try buildViewportCornerControls(ui, state, viewport);
        return;
    }

    const view_w: f32 = @min(560, viewport.w - 16);
    const view_rect = core_ui.Rect{ .x = viewport.x + 8, .y = view_y, .w = view_w, .h = 34 };
    try ui.beginPanel(.{ .id = "ed-viewport-view", .rect = view_rect, .row_height = 24, .padding = 5, .spacing = 4 });
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.iconButtonTip(ui, "ed-view-camera", if (state.view_camera_mode == .perspective) "perspective" else "orthographic", false, state.view_camera_mode.label())).clicked) {
        state.view_camera_mode = if (state.view_camera_mode == .perspective) .orthographic else .perspective;
        project_editor_state.setStatus(state, state.view_camera_mode.label());
    }
    if ((try ui_widgets.iconButtonTip(ui, "ed-view-orient", "world", false, state.view_orientation.label())).clicked) {
        const next_orientation: project_editor_types.ViewOrientation = switch (state.view_orientation) {
            .free => .top,
            .top => .front,
            .front => .side,
            .side => .free,
        };
        project_editor_view_nav.applyAxisSnap(state, next_orientation);
    }
    if ((try ui_widgets.iconButtonTip(ui, "ed-shading", "material", false, state.shading_mode.label())).clicked) {
        state.shading_mode = switch (state.shading_mode) {
            .rendered => .material_preview,
            .material_preview => .solid,
            .solid => .wireframe,
            .wireframe => .rendered,
        };
        project_editor_state.setStatus(state, state.shading_mode.label());
    }
    if ((try ui_widgets.iconButtonTip(ui, "ed-view-grid", "grid", state.show_grid, "Grid")).clicked) state.show_grid = !state.show_grid;
    if ((try ui_widgets.iconButtonTip(ui, "ed-view-gizmo", "gizmo", state.show_gizmo, "Gizmo")).clicked) state.show_gizmo = !state.show_gizmo;
    if (state.mode != .layout) {
        if ((try ui_widgets.iconButtonTip(ui, "ed-space", "world", false, state.transform_space.label())).clicked) {
            state.transform_space = if (state.transform_space == .world) .local else .world;
        }
        if ((try ui_widgets.iconButtonTip(ui, "ed-pivot", "pivot", false, state.pivot_mode.label())).clicked) {
            state.pivot_mode = if (state.pivot_mode == .pivot) .center else .pivot;
        }
        if ((try ui_widgets.iconButtonTip(ui, "ed-snap", "snap", state.snap_enabled, "G Grid snap")).clicked) project_editor_edit.toggleSnap(state);
        if ((try ui_widgets.button(ui, "ed-grid-minus", "-", 24, false)).clicked) state.snap_size = @max(0.25, state.snap_size * 0.5);
        var snap_buf: [16]u8 = undefined;
        _ = try ui_widgets.button(ui, "ed-grid-label", std.fmt.bufPrint(&snap_buf, "{d:.1}", .{state.snap_size}) catch "1.0", 38, false);
        if ((try ui_widgets.button(ui, "ed-grid-plus", "+", 24, false)).clicked) state.snap_size = @min(16, state.snap_size * 2);
    }
    if ((try ui_widgets.button(ui, "ed-axis", project_editor_state.moveAxisLabel(state), 46, false)).clicked) project_editor_scene.cycleMoveAxis(state);
    if ((try ui_widgets.button(ui, "ed-cam-minus", "-", 24, false)).clicked) state.camera_speed = @max(1, state.camera_speed - 1);
    var cam_buf: [16]u8 = undefined;
    _ = try ui_widgets.button(ui, "ed-cam-speed", std.fmt.bufPrint(&cam_buf, "{d:.0}", .{state.camera_speed}) catch "6", 28, false);
    if ((try ui_widgets.button(ui, "ed-cam-plus", "+", 24, false)).clicked) state.camera_speed = @min(20, state.camera_speed + 1);
    try core_ui.layout.endSameLine(ui);
    ui.endPanel();

    try buildMarkerOverlayCard(ui, state, viewport);
    try buildViewportStateHud(ui, state, viewport);
    try buildViewportCornerControls(ui, state, viewport);
}

fn buildViewportStateHud(ui: *core_ui.UiContext, state: *ProjectEditorState, viewport: core_ui.Rect) !void {
    const hud_w: f32 = @min(448.0, @max(320.0, viewport.w - 92.0));
    const hud_h: f32 = 146.0;
    const card = core_ui.Rect{
        .x = viewport.x + viewport.w - hud_w - 58.0,
        .y = viewport.y + 14.0,
        .w = hud_w,
        .h = hud_h,
    };
    try ui.beginPanel(.{ .id = "ed-viewport-state-hud", .rect = card, .row_height = 22, .padding = 8, .spacing = 3 });
    defer ui.endPanel();

    var title_buf: [128]u8 = undefined;
    try ui.label(std.fmt.bufPrint(&title_buf, "{s} / {s}", .{ state.mode.label(), project_editor_modes.toolLabel(state) }) catch state.mode.label());

    var next_buf: [180]u8 = undefined;
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&next_buf, "Next: {s}", .{toolIntentHint(state)}) catch "Next action");

    var selection_buf: [192]u8 = undefined;
    try ui_widgets.compactInfo(ui, selectionReadout(state, &selection_buf));

    var state_buf: [192]u8 = undefined;
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(
        &state_buf,
        "Snap {s} {d:.1}  Grid {s}  File {s}",
        .{
            if (state.snap_enabled) "on" else "off",
            state.snap_size,
            if (state.show_grid) "on" else "off",
            if (state.scene_dirty or state.dirty_cells.count > 0) "dirty" else "clean",
        },
    ) catch "Session state");

    var validation_buf: [192]u8 = undefined;
    try core_ui.widgets_feedback.statusLabel(ui, validationSummary(state, &validation_buf));

    var view_buf: [192]u8 = undefined;
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(
        &view_buf,
        "View {s} / {s}  Play {s}",
        .{ state.view_camera_mode.label(), state.shading_mode.label(), if (state.is_playing) "running" else "edit" },
    ) catch "View state");
}

fn toolIntentHint(state: *const ProjectEditorState) []const u8 {
    return switch (state.mode) {
        .world_creation => ui_world.modeHint(state),
        .layout => switch (state.object_tool) {
            .select => "Click an object to select it.",
            .move => if (state.selected_object == null) "Select an object to move." else "Drag the gizmo axis to move.",
            .rotate => if (state.selected_object == null) "Select an object to rotate." else "Drag the rotation handle.",
            .scale => if (state.selected_object == null) "Select an object to scale." else "Drag scale handles.",
        },
        .architecture_creation => architectureIntentHint(state),
        .prop_creation => propIntentHint(state),
        .life => lifeIntentHint(state),
    };
}

fn architectureIntentHint(state: *const ProjectEditorState) []const u8 {
    return switch (state.architecture_tool) {
        .brush => "Drag a blockout brush on the grid.",
        .floorplan => "Drag a floor rectangle.",
        .wall => "Draw wall segments on the grid.",
        .door => "Pick a wall, then place a door.",
        .window => "Pick a wall, then place a window.",
        .curve => "Click points to shape a curved wall.",
        .add => "Drag additive blockout volume.",
        .subtract => "Drag subtractive cut volume.",
        .ramp => "Drag a ramp footprint.",
        .vertex => "Select an editable point.",
        .edge => "Select an editable edge.",
        .face => "Select an editable face.",
        .extrude => "Select a face, then drag outward.",
        .inset => "Select a face, then inset it.",
        .material => "Select a face, then apply material.",
        .network => "Edit connected building walls.",
        .shell => "Select wall loops for a shell.",
        .foundation => "Place foundation supports.",
        .cutout => "Draw a cutout volume.",
        .opening => "Place an opening on a wall.",
        .roof => "Choose roof shape for building.",
    };
}

fn propIntentHint(state: *const ProjectEditorState) []const u8 {
    return switch (state.prop_tool) {
        .select => "Orbit the opened prop asset.",
        .create => "Choose a source, then draw shape.",
        .asset => "Pick a prop asset from Library.",
        .primitive => "Place a primitive source.",
        .edit => "Edit source points or operations.",
        .material => "Paint on visible prop surfaces.",
        .collider => "Preview and tune prop collider.",
        .variants => "Select or create a prop variant.",
    };
}

fn lifeIntentHint(state: *const ProjectEditorState) []const u8 {
    return switch (state.life_tool) {
        .select => "Select an actor or animated object.",
        .pose => "Select a bone or control to pose.",
        .keyframe => "Pick a property and add key.",
        .record => "Arm recording, then move controls.",
        .playback => "Scrub or play the active clip.",
        .clips => "Select or manage animation clips.",
        .bones => "Inspect skeleton bones.",
        .curves => "Edit animation curves.",
    };
}

fn validationSummary(state: *const ProjectEditorState, buf: []u8) []const u8 {
    if (state.editor_error_detail != null) return "Validation: editor error open";
    if (state.mode == .architecture_creation) {
        switch (state.architecture_tool) {
            .door, .window, .extrude, .inset, .material => {
                if (state.selected_object == null and state.selected_face == null) return "Validation: select a target first";
            },
            .vertex => if (state.selected_vertex == null) return "Validation: select a point first",
            .edge => if (state.selected_edge == null) return "Validation: select an edge first",
            .face => if (state.selected_face == null) return "Validation: select a face first",
            else => {},
        }
    }
    if (state.mode == .prop_creation) {
        if (state.active_prop_asset_id == null and state.prop_selected_asset.len == 0) return "Validation: open or select a prop";
    }
    if (state.mode == .life and state.animations.items.len == 0) return "Validation: no active clip";
    return std.fmt.bufPrint(buf, "Validation: ready  Errors 0  Dirty cells {d}", .{state.dirty_cells.count}) catch "Validation: ready";
}

fn buildMarkerOverlayCard(ui: *core_ui.UiContext, state: *ProjectEditorState, viewport: core_ui.Rect) !void {
    if (state.selection_scope != .marker) return;
    const idx = state.selected_object orelse return;
    if (idx >= state.objects.items.len) return;
    const obj = &state.objects.items[idx];
    const marker = obj.marker orelse return;

    const card = core_ui.Rect{ .x = viewport.x + 14, .y = viewport.y + 120, .w = @min(360, viewport.w - 28), .h = 134 };
    try ui.beginPanel(.{ .id = "ed-marker-overlay-card", .rect = card, .row_height = 21, .padding = 7, .spacing = 3 });
    defer ui.endPanel();

    var title_buf: [128]u8 = undefined;
    try ui.label(markerHudTitle(marker, obj.name, &title_buf));
    var shape_buf: [80]u8 = undefined;
    try ui_widgets.compactInfo(ui, markerHudShape(marker, &shape_buf));
    var group_buf: [128]u8 = undefined;
    try ui_widgets.compactInfo(ui, markerHudIdentity(marker, &group_buf));
    var radius_buf: [96]u8 = undefined;
    try ui_widgets.compactInfo(ui, markerHudRadiusOrder(marker, &radius_buf));
    marker.validate() catch |err| {
        var err_buf: [80]u8 = undefined;
        try core_ui.widgets_feedback.statusLabel(ui, std.fmt.bufPrint(&err_buf, "Invalid: {s}", .{@errorName(err)}) catch "Invalid marker");
        return;
    };
    try core_ui.widgets_feedback.statusLabel(ui, "Marker valid");
}

fn markerHudTitle(marker: scene_marker.Marker, name: []const u8, buf: []u8) []const u8 {
    return std.fmt.bufPrint(buf, "{s}: {s}", .{ marker.kind.label(), truncateHudText(name, 54) }) catch marker.kind.label();
}

fn markerHudShape(marker: scene_marker.Marker, buf: []u8) []const u8 {
    return std.fmt.bufPrint(buf, "Shape {s}", .{marker.shape.name()}) catch "Shape";
}

fn markerHudIdentity(marker: scene_marker.Marker, buf: []u8) []const u8 {
    if (marker.marker_id.len > 0) return std.fmt.bufPrint(buf, "Id {s}", .{truncateHudText(marker.marker_id, 58)}) catch "Id";
    if (marker.group.len > 0) return std.fmt.bufPrint(buf, "Group {s}", .{truncateHudText(marker.group, 54)}) catch "Group";
    if (marker.binding.len > 0) return std.fmt.bufPrint(buf, "Binding {s}", .{truncateHudText(marker.binding, 50)}) catch "Binding";
    return "No id/group/binding";
}

fn markerHudRadiusOrder(marker: scene_marker.Marker, buf: []u8) []const u8 {
    return std.fmt.bufPrint(buf, "Radius {d:.1}  Order {d}", .{ marker.radius, marker.order }) catch "Radius and order";
}

fn truncateHudText(text: []const u8, max_len: usize) []const u8 {
    if (text.len <= max_len) return text;
    return text[0..max_len];
}

fn buildPropViewportViewControls(ui: *core_ui.UiContext, state: *ProjectEditorState, viewport: core_ui.Rect, y: f32) !void {
    const view_w: f32 = @min(276, viewport.w - 16);
    const view_rect = core_ui.Rect{ .x = viewport.x + 8, .y = y, .w = view_w, .h = 34 };
    try ui.beginPanel(.{ .id = "ed-viewport-prop-view", .rect = view_rect, .row_height = 24, .padding = 5, .spacing = 4 });
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.iconButtonTip(ui, "ed-prop-view-grid", "grid", state.show_grid, "Grid")).clicked) state.show_grid = !state.show_grid;
    if ((try ui_widgets.button(ui, "ed-prop-view-frame", "Frame", 62, false)).clicked) ui_widgets.frameSelected(state);
    if ((try ui_widgets.button(ui, "ed-prop-cam-minus", "-", 24, false)).clicked) state.camera_speed = @max(1, state.camera_speed - 1);
    var cam_buf: [16]u8 = undefined;
    _ = try ui_widgets.button(ui, "ed-prop-cam-speed", std.fmt.bufPrint(&cam_buf, "{d:.0}", .{state.camera_speed}) catch "6", 28, false);
    if ((try ui_widgets.button(ui, "ed-prop-cam-plus", "+", 24, false)).clicked) state.camera_speed = @min(20, state.camera_speed + 1);
    try core_ui.layout.endSameLine(ui);
    ui.endPanel();
    try buildPropDisplayPreviewCard(ui, state, viewport);
    try buildPropSketchPreviewCard(ui, state, viewport);
    try buildPropPaintPreviewCard(ui, state, viewport);
}

fn buildPropDisplayPreviewCard(ui: *core_ui.UiContext, state: *ProjectEditorState, viewport: core_ui.Rect) !void {
    if (state.prop_workspace_mode != .display) return;
    const card = core_ui.Rect{ .x = viewport.x + 14, .y = viewport.y + 120, .w = 194, .h = 108 };
    try ui.beginPanel(.{ .id = "ed-prop-display-preview", .rect = card, .row_height = 21, .padding = 7, .spacing = 3 });
    try ui.label("Object Studio");
    try ui_widgets.compactInfo(ui, "Drag to orbit");
    try ui_widgets.compactInfo(ui, "Wheel to zoom");
    try ui_widgets.compactInfo(ui, "Studio lighting");
    ui.endPanel();
}

fn buildPropSketchPreviewCard(ui: *core_ui.UiContext, state: *ProjectEditorState, viewport: core_ui.Rect) !void {
    if (state.prop_tool != .edit) return;
    const card = core_ui.Rect{ .x = viewport.x + 14, .y = viewport.y + 120, .w = 226, .h = 172 };
    try ui.beginPanel(.{ .id = "ed-prop-sketch-preview", .rect = card, .row_height = 21, .padding = 7, .spacing = 3 });
    try ui.label("Shape Builder");
    try ui_widgets.compactInfo(ui, "Sketch to solid mesh");
    try ui_widgets.compactInfo(ui, sketchModeHint(state));
    var point_buf: [48]u8 = undefined;
    try ui_widgets.compactInfo(ui, sketchPointHint(state, &point_buf));
    var dimensions_buf: [80]u8 = undefined;
    if (sketchDimensionsHint(state, &dimensions_buf)) |dimensions| try ui_widgets.compactInfo(ui, dimensions);
    try ui_widgets.compactInfo(ui, sketchFinishHint(state));
    var validation_buf: [96]u8 = undefined;
    try core_ui.widgets_feedback.statusLabel(ui, sketchValidationHint(state, &validation_buf));
    ui.endPanel();
}

fn sketchModeHint(state: *const ProjectEditorState) []const u8 {
    return switch (state.prop_sketch_mode) {
        .none => "Pick Draw Face, Curve, or Path",
        .face => "Draw flat face",
        .curve => "Draw revolve curve",
        .path => "Draw path source",
    };
}

fn sketchPointHint(state: *const ProjectEditorState, buf: []u8) []const u8 {
    if (state.prop_sketch_points.items.len == 0 and state.prop_sketch_mode != .none) return "Click points in viewport";
    return std.fmt.bufPrint(buf, "{d} placed points", .{state.prop_sketch_points.items.len}) catch "Placed points";
}

fn sketchDimensionsHint(state: *const ProjectEditorState, buf: []u8) ?[]const u8 {
    if (state.prop_sketch_points.items.len < 2) return null;
    const span = sketchSourceSpan(state.prop_sketch_points.items);
    return std.fmt.bufPrint(buf, "Span {d:.2} x {d:.2} x {d:.2}", .{ span.x, span.y, span.z }) catch "Span";
}

fn sketchSourceSpan(points: []const editor_math.Vec3) editor_math.Vec3 {
    if (points.len == 0) return .{ .x = 0, .y = 0, .z = 0 };
    var min = points[0];
    var max = points[0];
    for (points[1..]) |point| {
        min.x = @min(min.x, point.x);
        min.y = @min(min.y, point.y);
        min.z = @min(min.z, point.z);
        max.x = @max(max.x, point.x);
        max.y = @max(max.y, point.y);
        max.z = @max(max.z, point.z);
    }
    return .{ .x = max.x - min.x, .y = max.y - min.y, .z = max.z - min.z };
}

fn sketchFinishHint(state: *const ProjectEditorState) []const u8 {
    return switch (state.prop_sketch_mode) {
        .none => "Start in Shape",
        .face => "Finish: Solidify",
        .curve => "Finish: Revolve",
        .path => "Editable path",
    };
}

fn sketchValidationHint(state: *const ProjectEditorState, buf: []u8) []const u8 {
    if (state.prop_sketch_mode == .none) return "Pick a source";
    const source = sketchSourceForState(state);
    const operation = sketchOperationForState(state);
    operation.validateForSource(source) catch |err| {
        return std.fmt.bufPrint(buf, "Invalid: {s}", .{sketchValidationErrorLabel(err)}) catch "Invalid source";
    };
    return "Valid source";
}

fn sketchValidationErrorLabel(err: anyerror) []const u8 {
    return shape_operation.validationErrorLabel(err);
}

fn sketchSourceForState(state: *const ProjectEditorState) shape_source.Source {
    return .{
        .kind = switch (state.prop_sketch_mode) {
            .face => .closed_face,
            .curve => .open_profile,
            .path => .path,
            .none => .primitive_seed,
        },
        .points = state.prop_sketch_points.items,
    };
}

fn sketchOperationForState(state: *const ProjectEditorState) shape_operation.Operation {
    return .{
        .kind = switch (state.prop_sketch_mode) {
            .face => .solidify,
            .curve => .revolve,
            .path => .extrude,
            .none => .extrude,
        },
        .amount = state.prop_sketch_amount,
        .segments = state.prop_sketch_segments,
    };
}

fn buildPropPaintPreviewCard(ui: *core_ui.UiContext, state: *ProjectEditorState, viewport: core_ui.Rect) !void {
    if (state.prop_tool != .material) return;
    const card = core_ui.Rect{ .x = viewport.x + 14, .y = viewport.y + 120, .w = 192, .h = 128 };
    try ui.beginPanel(.{ .id = "ed-prop-paint-preview", .rect = card, .row_height = 21, .padding = 7, .spacing = 3 });
    try ui.label("Texture Paint");
    try ui_widgets.compactInfo(ui, "Paint on prop");
    try ui_widgets.compactInfo(ui, "No UV setup");
    var quality_buf: [48]u8 = undefined;
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&quality_buf, "{d}x detail", .{state.prop_texture_quality}) catch "Texture detail");
    var brush_buf: [80]u8 = undefined;
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&brush_buf, "{s} brush  {d:.0}% size", .{ state.texture_paint_brush.label(), brushSizePercent(state) }) catch "Brush");
    ui.endPanel();
}

fn brushSizePercent(state: *const ProjectEditorState) f32 {
    return std.math.clamp((state.brush_radius - 0.01) / (0.22 - 0.01), 0.0, 1.0) * 100.0;
}

fn buildViewportCornerControls(ui: *core_ui.UiContext, state: *ProjectEditorState, viewport: core_ui.Rect) !void {
    const size: f32 = 32;
    const inset: f32 = 12;
    const reset_rect = core_ui.Rect{
        .x = viewport.x + viewport.w - size - inset,
        .y = viewport.y + viewport.h - size - inset,
        .w = size,
        .h = size,
    };
    const show_terrain_snap = state.mode == .world_creation and state.world_tool == .terrain;
    const snap_rect = core_ui.Rect{
        .x = reset_rect.x - size - 8,
        .y = reset_rect.y,
        .w = size,
        .h = size,
    };
    const overlay_rect = if (show_terrain_snap) core_ui.Rect{
        .x = snap_rect.x,
        .y = reset_rect.y,
        .w = (reset_rect.x + reset_rect.w) - snap_rect.x,
        .h = size,
    } else reset_rect;

    try core_ui.input_tree.pushOverlay(ui, overlay_rect);
    defer core_ui.input_tree.pop(ui);
    if (show_terrain_snap) {
        const snap = try ui_widgets.iconOverlayButton(ui, "ed-snap-camera-terrain", "magnet", snap_rect, false);
        if (snap.clicked) {
            ui_widgets.snapCameraToTerrainHeight(state) catch |err| switch (err) {
                error.WorldCellNotInManifest => project_editor_state.setStatus(state, "Terrain snap failed: no world cell here"),
                error.TerrainTileNotFound => project_editor_state.setStatus(state, "Terrain snap failed: no terrain tile here"),
                else => project_editor_state.setStatus(state, "Terrain snap failed"),
            };
        }
        try core_ui.widgets_feedback.tooltip(ui, snap_rect, "Snap view 6m above terrain");
    }
    const reset = try ui_widgets.iconOverlayButton(ui, "ed-reset-camera-origin", "gizmo", reset_rect, false);
    if (reset.clicked) ui_widgets.resetCameraToOrigin(state);
    try core_ui.widgets_feedback.tooltip(ui, reset_rect, "Reset view to origin");
}

fn buildModeToolButtons(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    try project_editor_modes.buildViewportTools(ui, state);
}

const GameMarkerTool = struct {
    kind: scene_marker.Kind,
    label: []const u8,
};

const game_marker_tools = [_]GameMarkerTool{
    .{ .kind = .player_start, .label = "Player Start" },
    .{ .kind = .spawn_point, .label = "Spawn" },
    .{ .kind = .trigger_volume, .label = "Trigger" },
    .{ .kind = .objective, .label = "Objective" },
    .{ .kind = .patrol_point, .label = "Patrol" },
    .{ .kind = .camera_point, .label = "Camera" },
    .{ .kind = .audio_emitter, .label = "Audio" },
};

fn buildGameMarkerTools(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    _ = try ui_widgets.button(ui, "ed-game-marker-group", "Game", 54, true);
    inline for (game_marker_tools) |tool| {
        var id_buf: [80]u8 = undefined;
        if ((try ui_widgets.button(
            ui,
            std.fmt.bufPrint(&id_buf, "ed-game-marker-{s}", .{tool.kind.name()}) catch "ed-game-marker",
            tool.label,
            gameMarkerToolWidth(tool.kind),
            false,
        )).clicked) {
            try project_editor_scene.addMarkerObject(state, tool.kind);
            project_editor_scene.setSelectionScope(state, .marker);
        }
    }
}

fn gameMarkerToolWidth(kind: scene_marker.Kind) f32 {
    return switch (kind) {
        .trigger_volume => 78,
        .player_start => 104,
        .objective => 88,
        .camera_point => 74,
        .spawn_point, .patrol_point => 70,
        .audio_emitter => 64,
        else => 66,
    };
}

fn gameMarkerStripWidth(inline_spacing: f32) f32 {
    var width: f32 = 54;
    width += inline_spacing;
    for (game_marker_tools) |tool| {
        width += gameMarkerToolWidth(tool.kind);
        width += inline_spacing;
    }
    return width;
}

fn gameMarkerToolLabel(kind: scene_marker.Kind) ?[]const u8 {
    for (game_marker_tools) |tool| {
        if (tool.kind == kind) return tool.label;
    }
    return null;
}

fn gameMarkerToolHas(kind: scene_marker.Kind) bool {
    for (game_marker_tools) |tool| {
        if (tool.kind == kind) return true;
    }
    return false;
}

test "viewport game marker strip exposes focused gameplay marker tools" {
    try std.testing.expect(gameMarkerToolHas(.player_start));
    try std.testing.expect(gameMarkerToolHas(.spawn_point));
    try std.testing.expect(gameMarkerToolHas(.trigger_volume));
    try std.testing.expect(gameMarkerToolHas(.objective));
    try std.testing.expect(gameMarkerToolHas(.patrol_point));
    try std.testing.expect(gameMarkerToolHas(.camera_point));
    try std.testing.expect(gameMarkerToolHas(.audio_emitter));
    try std.testing.expectEqual(@as(usize, 7), game_marker_tools.len);
    try std.testing.expectEqualStrings("Player Start", gameMarkerToolLabel(.player_start).?);
    try std.testing.expectEqualStrings("Objective", gameMarkerToolLabel(.objective).?);
    try std.testing.expect(gameMarkerStripWidth(4) <= 640);
}

test "marker viewport card summarizes selected marker intent" {
    const marker = scene_marker.Marker{
        .kind = .patrol_point,
        .shape = .path,
        .group = @constCast("guard"),
        .radius = 1.25,
        .order = 3,
    };
    var title_buf: [128]u8 = undefined;
    var shape_buf: [80]u8 = undefined;
    var id_buf: [128]u8 = undefined;
    var radius_buf: [96]u8 = undefined;
    try std.testing.expectEqualStrings("Patrol Point: Codex Guard Patrol", markerHudTitle(marker, "Codex Guard Patrol", &title_buf));
    try std.testing.expectEqualStrings("Shape path", markerHudShape(marker, &shape_buf));
    try std.testing.expectEqualStrings("Group guard", markerHudIdentity(marker, &id_buf));
    try std.testing.expectEqualStrings("Radius 1.3  Order 3", markerHudRadiusOrder(marker, &radius_buf));
}

fn buildSelectionScopeStrip(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    _ = try ui_widgets.button(ui, "ed-select-scope-group", "Select", 68, true);
    const scopes = [_]project_editor_state.SelectionScope{ .object, .face, .edge, .point, .source, .operation, .marker };
    inline for (scopes) |scope| {
        if ((try ui_widgets.iconButtonTip(ui, selectionScopeId(scope), selectionScopeIcon(scope), state.selection_scope == scope, selectionScopeTip(scope))).clicked) {
            project_editor_scene.setSelectionScope(state, scope);
        }
    }
}

fn selectionScopeId(scope: project_editor_state.SelectionScope) []const u8 {
    return switch (scope) {
        .object => "ed-scope-object",
        .face => "ed-scope-face",
        .edge => "ed-scope-edge",
        .point => "ed-scope-point",
        .source => "ed-scope-source",
        .operation => "ed-scope-operation",
        .marker => "ed-scope-marker",
    };
}

fn selectionScopeIcon(scope: project_editor_state.SelectionScope) []const u8 {
    return switch (scope) {
        .object => "box",
        .face => "select-face-3d",
        .edge => "select-edge-3d",
        .point => "select-point-3d",
        .source => "component",
        .operation => "gizmo",
        .marker => "magnet",
    };
}

fn selectionScopeTip(scope: project_editor_state.SelectionScope) []const u8 {
    return switch (scope) {
        .object => "Select objects",
        .face => "Select faces",
        .edge => "Select edges",
        .point => "Select points",
        .source => "Select shape sources",
        .operation => "Select shape operations",
        .marker => "Select gameplay markers",
    };
}

fn buildBottomStrip(ui: *core_ui.UiContext, state: *ProjectEditorState, rect: core_ui.Rect) !void {
    if (state.mode == .life) {
        try ui.beginPanel(.{ .id = "ed-bottom", .rect = rect, .row_height = 24, .padding = 6, .spacing = 6 });
        const status = if (state.status_len > 0) state.status_buf[0..state.status_len] else project_editor_modes.modeHint(state);
        try buildStatusReadouts(ui, state, rect, status);
        if (state.command_palette_open) try ui_build_palette.buildCommandPalette(ui, state, rect);
        ui.endPanel();
        return;
    }
    if (state.mode == .prop_creation) {
        try ui.beginPanel(.{ .id = "ed-bottom", .rect = rect, .row_height = 24, .padding = 6, .spacing = 6 });
        const status = if (state.status_len > 0) state.status_buf[0..state.status_len] else project_editor_modes.modeHint(state);
        try buildStatusReadouts(ui, state, rect, status);
        if (state.command_palette_open) try ui_build_palette.buildCommandPalette(ui, state, rect);
        ui.endPanel();
        return;
    }
    try ui.beginPanel(.{ .id = "ed-bottom", .rect = rect, .row_height = 24, .padding = 6, .spacing = 6 });
    const status = if (state.status_len > 0) state.status_buf[0..state.status_len] else project_editor_modes.modeHint(state);
    try buildStatusReadouts(ui, state, rect, status);
    if (state.command_palette_open) try ui_build_palette.buildCommandPalette(ui, state, rect);
    ui.endPanel();
}

fn buildStatusReadouts(ui: *core_ui.UiContext, state: *ProjectEditorState, rect: core_ui.Rect, status: []const u8) !void {
    const pad: f32 = 10;
    const gap: f32 = 8;
    const scope_w: f32 = 220;
    const file_w: f32 = 142;
    const llm_w: f32 = 154;
    const render_w: f32 = 190;
    const fps_w = ui_widgets.fps_readout_w;
    const y = rect.y + 5;
    const h: f32 = 22;

    const fps_x = rect.x + rect.w - ui_widgets.fps_readout_right_pad - fps_w;
    const render_x = fps_x - gap - render_w;
    const llm_x = render_x - gap - llm_w;
    const file_x = llm_x - gap - file_w;
    const scope_x = file_x - gap - scope_w;
    const status_w = @max(80, scope_x - rect.x - pad * 2);

    try ui_widgets.text(ui, "ed-status", .{ .x = rect.x + pad, .y = y, .w = status_w, .h = h }, status, true);

    var scope_buf: [160]u8 = undefined;
    try ui_widgets.text(ui, "ed-selection-scope", .{ .x = scope_x, .y = y, .w = scope_w, .h = h }, selectionReadout(state, &scope_buf), true);

    var file_buf: [64]u8 = undefined;
    const dirty = state.scene_dirty or state.dirty_cells.count > 0;
    try ui_widgets.text(ui, "ed-file-status", .{ .x = file_x, .y = y, .w = file_w, .h = h }, std.fmt.bufPrint(&file_buf, "File {s} | C{d}", .{ if (dirty) "dirty" else "clean", state.dirty_cells.count }) catch "File", true);

    var llm_buf: [64]u8 = undefined;
    try ui_widgets.text(ui, "ed-llm-status", .{ .x = llm_x, .y = y, .w = llm_w, .h = h }, std.fmt.bufPrint(&llm_buf, "LLM {d} | In {d}", .{ state.control_stats.executed, state.control_stats.inflight }) catch "LLM", true);

    var render_buf: [96]u8 = undefined;
    try ui_widgets.text(ui, "ed-render-status", .{ .x = render_x, .y = y, .w = render_w, .h = h }, std.fmt.bufPrint(&render_buf, "Render {d} | Vis {d}/{d}", .{ state.render_command_stats.total, state.visibility_stats.visible_meshes, state.objects.items.len }) catch "Render", true);

    try ui_widgets.buildFpsReadout(ui, state, rect);
}

fn selectionReadout(state: *const ProjectEditorState, buf: []u8) []const u8 {
    if (state.selected_object_ids.items.len > 1) {
        var many_buf: [48]u8 = undefined;
        const selected_many = multiSelectionLabel(state, &many_buf);
        return selectionReadoutWithHover(buf, state.selection_scope.label(), selected_many, null);
    }
    const selected = if (state.selected_object) |idx|
        if (idx < state.objects.items.len) state.objects.items[idx].name else "None"
    else
        "None";
    const hover_name = if (state.hovered_object) |idx|
        if (idx < state.objects.items.len) state.objects.items[idx].name else null
    else
        null;
    const hover_readout: ?[]const u8 = if (state.hovered_shape_source)
        "Source"
    else if (state.hovered_shape_operation)
        "Operation"
    else
        hover_name;
    if (state.selected_shape_source) return selectionReadoutWithHover(buf, state.selection_scope.label(), "Source", hover_readout);
    if (state.selected_shape_operation) return selectionReadoutWithHover(buf, state.selection_scope.label(), "Operation", hover_readout);
    if (state.selected_face != null) return selectionReadoutWithHover(buf, state.selection_scope.label(), "Face", hover_name);
    if (state.selected_edge != null) return selectionReadoutWithHover(buf, state.selection_scope.label(), "Edge", hover_name);
    if (state.selected_vertex != null) return selectionReadoutWithHover(buf, state.selection_scope.label(), "Point", hover_name);
    if (state.selected_object) |idx| {
        if (idx < state.objects.items.len and state.objects.items[idx].marker != null) {
            return selectionReadoutWithHover(buf, state.selection_scope.label(), "Marker", hover_name);
        }
    }
    return selectionReadoutWithHover(buf, state.selection_scope.label(), selected, hover_readout);
}

fn multiSelectionLabel(state: *const ProjectEditorState, buf: []u8) []const u8 {
    return std.fmt.bufPrint(buf, "{d} selected", .{state.selected_object_ids.items.len}) catch "Many selected";
}

fn selectionReadoutWithHover(buf: []u8, scope: []const u8, selected: []const u8, hover_name: ?[]const u8) []const u8 {
    if (hover_name) |name| {
        return std.fmt.bufPrint(buf, "{s}: {s} | Hover {s}", .{ scope, selected, name }) catch scope;
    }
    return std.fmt.bufPrint(buf, "{s}: {s}", .{ scope, selected }) catch scope;
}

test "selection readout surfaces drag box multi selection count" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .selection_scope = .marker,
    };
    defer state.selected_object_ids.deinit(std.testing.allocator);
    try state.selected_object_ids.append(std.testing.allocator, 10);
    try state.selected_object_ids.append(std.testing.allocator, 20);

    var buf: [160]u8 = undefined;
    try std.testing.expectEqualStrings("Marker: 2 selected", selectionReadout(&state, &buf));
}

test "shape builder viewport validation reports invalid and valid sources" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .prop_tool = .edit,
        .prop_sketch_mode = .face,
    };
    defer state.prop_sketch_points.deinit(std.testing.allocator);

    var buf: [96]u8 = undefined;
    try std.testing.expectEqualStrings("Invalid: Need more points", sketchValidationHint(&state, &buf));

    try state.prop_sketch_points.append(std.testing.allocator, .{ .x = 0, .y = 0, .z = 0 });
    try state.prop_sketch_points.append(std.testing.allocator, .{ .x = 1, .y = 0, .z = 0 });
    try state.prop_sketch_points.append(std.testing.allocator, .{ .x = 0, .y = 0, .z = 1 });
    try std.testing.expectEqualStrings("Valid source", sketchValidationHint(&state, &buf));

    state.prop_sketch_amount = 0;
    try std.testing.expectEqualStrings("Invalid: Bad amount", sketchValidationHint(&state, &buf));

    var dimensions_buf: [80]u8 = undefined;
    try std.testing.expectEqualStrings("Span 1.00 x 0.00 x 1.00", sketchDimensionsHint(&state, &dimensions_buf).?);
}
