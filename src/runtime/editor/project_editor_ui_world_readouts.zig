const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_types = @import("project_editor_types.zig");
const project_editor_ui_widgets = @import("project_editor_ui_widgets.zig");
const project_editor_ui_world_ocean_actions = @import("project_editor_ui_world_ocean_actions.zig");

const core_ui = friendly_engine.modules.core_ui;
const editor_math = shared.editor_math;
const ProjectEditorState = project_editor_state.ProjectEditorState;
const WorldGridScale = project_editor_types.WorldGridScale;
const ui_widgets = project_editor_ui_widgets;

pub fn buildBottomReadouts(ui: *core_ui.UiContext, state: *ProjectEditorState, rect: core_ui.Rect) !void {
    const chunk = chunkCoords(state);
    var chunk_buf: [64]u8 = undefined;
    const chunk_text = std.fmt.bufPrint(&chunk_buf, "Cell {d},{d},{d}", .{ chunk.x, chunk.y, chunk.z }) catch "Cell";

    var render_buf: [128]u8 = undefined;
    const render_text = std.fmt.bufPrint(&render_buf, "Cam {d:.0} | Cmds {d} | Vis {d}/{d}", .{
        state.camera_speed,
        state.render_command_stats.total,
        state.visibility_stats.visible_meshes,
        state.objects.items.len,
    }) catch "Stats";

    const spacing: f32 = 6;
    const grid_button_w: f32 = 38;
    const grid_w = grid_button_w * 3 + spacing * 2;
    const sky_w: f32 = 54;
    const fog_w: f32 = 92;
    const ocean_w: f32 = 72;
    const light_w: f32 = 98;
    const controls_w = grid_w + spacing + sky_w + spacing + fog_w + spacing + ocean_w + spacing + light_w;
    const cell_w: f32 = 130;
    const render_w: f32 = 240;
    const section_gap: f32 = 16;
    const right_pad: f32 = 10;
    const total_w = render_w + section_gap + cell_w + section_gap + controls_w + ui_widgets.fps_readout_reserved_w + right_pad;
    const base_x = rect.x + rect.w - total_w;
    const text_y = rect.y + 5;

    try ui_widgets.text(ui, "ed-render-status", .{ .x = base_x, .y = text_y, .w = render_w, .h = 22 }, render_text, true);
    try ui_widgets.text(ui, "ed-world-cell", .{ .x = base_x + render_w + section_gap, .y = text_y, .w = cell_w, .h = 22 }, chunk_text, true);

    try ui_widgets.rowAt(ui, base_x + render_w + section_gap + cell_w + section_gap, rect.y + 3);
    inline for (std.meta.fields(WorldGridScale)) |field| {
        const scale: WorldGridScale = @enumFromInt(@intFromEnum(@field(WorldGridScale, field.name)));
        var id_buf: [32]u8 = undefined;
        const id = std.fmt.bufPrint(&id_buf, "ed-world-grid-{s}", .{field.name}) catch "ed-world-grid";
        if ((try ui_widgets.buttonTip(ui, id, scale.label(), grid_button_w, state.world_grid_scale == scale, scale.tip())).clicked) {
            state.world_grid_scale = scale;
            state.snap_size = scale.meters();
            project_editor_state.setStatus(state, scale.label());
        }
    }
    if ((try ui_widgets.buttonTip(ui, "ed-world-sky-toggle", "Sky", sky_w, state.world_sky_visible, "Toggle sky rendering")).clicked) {
        state.world_sky_visible = !state.world_sky_visible;
        project_editor_state.setStatus(state, if (state.world_sky_visible) "Sky on" else "Sky off");
    }
    if ((try ui_widgets.buttonTip(ui, "ed-world-fog-preview", "Fog Prev", fog_w, fogPreviewActive(state), "Toggle fog preview")).clicked) {
        state.world_fog_preview = !state.world_fog_preview;
        state.world_fog_enabled = state.world_fog_preview;
        project_editor_state.setStatus(state, if (state.world_fog_enabled) "Fog preview on" else "Fog preview off");
    }
    if ((try ui_widgets.buttonTip(ui, "ed-world-ocean-toggle", "Ocean", ocean_w, state.world_ocean_visible, "Toggle ocean rendering")).clicked) {
        project_editor_ui_world_ocean_actions.toggleOcean(state) catch {};
    }
    if ((try ui_widgets.buttonTip(ui, "ed-world-light-preview", "Light Prev", light_w, state.world_lighting_preview, "Toggle lighting preview")).clicked) {
        state.world_lighting_preview = !state.world_lighting_preview;
    }
    try core_ui.layout.endSameLine(ui);
    try ui_widgets.buildFpsReadout(ui, state, rect);
}

pub fn fogPreviewActive(state: *const ProjectEditorState) bool {
    return state.world_fog_preview or state.world_fog_enabled;
}

pub fn chunkCoords(state: *const ProjectEditorState) editor_math.Vec3 {
    const target = state.camera.target;
    return .{
        .x = @floor(target.x / state.world_cell_size_m),
        .y = @floor(target.z / state.world_cell_size_m),
        .z = 0,
    };
}
