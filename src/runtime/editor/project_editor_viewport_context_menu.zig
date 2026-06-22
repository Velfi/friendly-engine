const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_terrain_preview = @import("project_editor_terrain_preview.zig");
const ui_widgets = @import("project_editor_ui_widgets.zig");

const core_ui = friendly_engine.modules.core_ui;
const editor_math = shared.editor_math;
const ProjectEditorState = project_editor_state.ProjectEditorState;

const player_eye_height_m: f32 = 1.65;
const player_view_distance_m: f32 = 1.0;

pub fn openAtScreen(state: *ProjectEditorState, screen_x: f32, screen_y: f32) void {
    const target = terrainPointAtScreen(state, screen_x, screen_y) orelse {
        project_editor_state.setStatus(state, "No terrain under cursor");
        return;
    };
    state.viewport_context_menu_open = true;
    state.viewport_context_menu_x = screen_x;
    state.viewport_context_menu_y = screen_y;
    state.viewport_context_menu_target = target;
    selectCellForTarget(state, target);
}

pub fn build(ui: *core_ui.UiContext, state: *ProjectEditorState) !bool {
    if (!state.viewport_context_menu_open) return false;

    const menu_w: f32 = 214;
    const row_h: f32 = 26;
    const menu_h: f32 = row_h * 2 + 10;
    const x = clampMenuX(ui, state.viewport_context_menu_x, menu_w);
    const y = clampMenuY(ui, state.viewport_context_menu_y, menu_h);
    const rect = core_ui.Rect{ .x = x, .y = y, .w = menu_w, .h = menu_h };

    if ((ui.input.primary_pressed or ui.input.right_button_pressed) and !rect.contains(ui.input.mouse_position)) {
        close(state);
        return false;
    }

    try ui.beginPanel(.{
        .id = "ed-viewport-context-menu",
        .rect = rect,
        .row_height = row_h,
        .padding = 5,
        .spacing = 2,
    });
    defer ui.endPanel();

    if ((try ui_widgets.button(ui, "ed-viewport-menu-player-view", "Zoom To Player View", menu_w - 10, false)).clicked) {
        zoomToPlayerView(state, state.viewport_context_menu_target);
        close(state);
        return false;
    }
    if ((try ui_widgets.button(ui, "ed-viewport-menu-close", "Close", menu_w - 10, false)).clicked) {
        close(state);
        return false;
    }
    return true;
}

fn zoomToPlayerView(state: *ProjectEditorState, point: editor_math.Vec3) void {
    state.view_camera_mode = .perspective;
    state.view_orientation = .free;
    state.camera.pitch = 0.0;
    state.camera.distance = @max(player_view_distance_m, state.camera.min_distance);
    const eye = editor_math.Vec3{ .x = point.x, .y = point.y + player_eye_height_m, .z = point.z };
    state.camera.target = editor_math.Vec3.add(eye, editor_math.Vec3.scale(state.camera.forward(), state.camera.distance));
    selectCellForTarget(state, point);
    project_editor_state.setStatus(state, "Zoomed to player view");
}

fn terrainPointAtScreen(state: *ProjectEditorState, screen_x: f32, screen_y: f32) ?editor_math.Vec3 {
    if (!@import("project_editor_scene.zig").pointInViewport(state, screen_x, screen_y)) return null;
    const local_x = screen_x - state.viewport_screen_rect.x;
    const local_y = screen_y - state.viewport_screen_rect.y;
    const ray = project_editor_state.rayFromViewport(
        state,
        local_x,
        local_y,
        state.viewport_screen_rect.w,
        state.viewport_screen_rect.h,
    );
    return raycastResidentTerrain(state, ray) orelse terrainPlaneFallback(state, ray);
}

fn raycastResidentTerrain(state: *const ProjectEditorState, ray: editor_math.Ray) ?editor_math.Vec3 {
    const max_t = @min(8192.0, @max(state.camera.distance + state.world_cell_size_m * 8.0, state.world_cell_size_m * 2.0));
    const steps: usize = 96;
    var prev_t: f32 = 0.0;
    var prev_diff: ?f32 = null;

    for (0..steps + 1) |i| {
        const t = max_t * (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps)));
        const point = editor_math.Vec3.add(ray.origin, editor_math.Vec3.scale(ray.dir, t));
        const terrain_y = project_editor_terrain_preview.sampleResidentHeightAtPoint(state, point) orelse continue;
        const diff = point.y - terrain_y;
        if (prev_diff) |last| {
            if (last >= 0.0 and diff <= 0.0) {
                return refineTerrainHit(state, ray, prev_t, t);
            }
        }
        prev_t = t;
        prev_diff = diff;
    }
    return null;
}

fn refineTerrainHit(state: *const ProjectEditorState, ray: editor_math.Ray, start_t: f32, end_t: f32) ?editor_math.Vec3 {
    var lo = start_t;
    var hi = end_t;
    var best: ?editor_math.Vec3 = null;
    for (0..12) |_| {
        const mid = (lo + hi) * 0.5;
        const point = editor_math.Vec3.add(ray.origin, editor_math.Vec3.scale(ray.dir, mid));
        const terrain_y = project_editor_terrain_preview.sampleResidentHeightAtPoint(state, point) orelse return best;
        const snapped = editor_math.Vec3{ .x = point.x, .y = terrain_y, .z = point.z };
        best = snapped;
        if (point.y > terrain_y) {
            lo = mid;
        } else {
            hi = mid;
        }
    }
    return best;
}

fn terrainPlaneFallback(state: *const ProjectEditorState, ray: editor_math.Ray) ?editor_math.Vec3 {
    const ground = editor_math.rayIntersectPlane(ray.origin, ray.dir, 0.0) orelse return null;
    if (project_editor_terrain_preview.sampleResidentHeightAtPoint(state, ground)) |height| {
        return .{ .x = ground.x, .y = height, .z = ground.z };
    }
    return ground;
}

fn selectCellForTarget(state: *ProjectEditorState, point: editor_math.Vec3) void {
    const cell_size = @max(0.001, state.world_cell_size_m);
    state.selected_world_cell = .{
        .x = @intFromFloat(@floor(point.x / cell_size)),
        .y = @intFromFloat(@floor(point.z / cell_size)),
        .z = 0,
    };
}

fn close(state: *ProjectEditorState) void {
    state.viewport_context_menu_open = false;
}

fn clampMenuX(ui: *const core_ui.UiContext, x: f32, w: f32) f32 {
    if (ui.frame_bounds.w <= 0) return x;
    return @min(@max(ui.frame_bounds.x, x), @max(ui.frame_bounds.x, ui.frame_bounds.x + ui.frame_bounds.w - w - 4));
}

fn clampMenuY(ui: *const core_ui.UiContext, y: f32, h: f32) f32 {
    if (ui.frame_bounds.h <= 0) return y;
    return @min(@max(ui.frame_bounds.y, y), @max(ui.frame_bounds.y, ui.frame_bounds.y + ui.frame_bounds.h - h - 4));
}
