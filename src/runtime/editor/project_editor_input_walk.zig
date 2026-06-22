const std = @import("std");
const friendly_engine = @import("friendly_engine");
const editor_draw = @import("editor_draw.zig");
const editor_core_ui_input = @import("editor_core_ui_input.zig");
const project_editor_state = @import("project_editor_state.zig");
const editor_math = @import("runtime_shared").editor_math;

const core_ui = friendly_engine.modules.core_ui;
const ProjectEditorState = project_editor_state.ProjectEditorState;

pub fn applyWalkKeys(state: *ProjectEditorState, acc: *editor_core_ui_input.Accumulator) !void {
    for (acc.key_events.items) |event| {
        if (!event.down or event.repeat) continue;
        if (event.key == 0x1b) {
            toggleWalkMode(state);
            return;
        }
        setWalkKey(state, event.key, true);
    }
    for (acc.key_events.items) |event| {
        if (event.down) continue;
        setWalkKey(state, event.key, false);
    }
}

pub fn update(state: *ProjectEditorState, dt: f32) void {
    if (!state.walk_mode) return;
    var local: editor_math.Vec3 = .{ .x = 0, .y = 0, .z = 0 };
    if (state.walk_forward) local.z += 1.0;
    if (state.walk_back) local.z -= 1.0;
    if (state.walk_right) local.x += 1.0;
    if (state.walk_left) local.x -= 1.0;
    if (state.walk_up) local.y += 1.0;
    if (state.walk_down) local.y -= 1.0;
    if (local.x == 0 and local.y == 0 and local.z == 0) return;
    const speed: f32 = if (state.walk_fast) 12.0 else 4.0;
    state.camera.walk(editor_math.Vec3.normalized(local), speed * dt);
}

pub fn toggleWalkMode(state: *ProjectEditorState) void {
    state.walk_mode = !state.walk_mode;
    state.drag_mode = .none;
    clearWalkKeys(state);
    project_editor_state.setStatus(state, if (state.walk_mode) "Walk mode" else "Walk mode ended");
}

fn setWalkKey(state: *ProjectEditorState, key: editor_draw.SDL_Keycode, down: bool) void {
    switch (key) {
        0x77 => state.walk_forward = down, // W
        0x73 => state.walk_back = down, // S
        0x61 => state.walk_left = down, // A
        0x64 => state.walk_right = down, // D
        0x65 => state.walk_up = down, // E
        0x71 => state.walk_down = down, // Q
        else => {},
    }
}

fn clearWalkKeys(state: *ProjectEditorState) void {
    state.walk_forward = false;
    state.walk_back = false;
    state.walk_left = false;
    state.walk_right = false;
    state.walk_up = false;
    state.walk_down = false;
    state.walk_fast = false;
}
