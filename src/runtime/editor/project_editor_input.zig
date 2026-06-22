const friendly_engine = @import("friendly_engine");
const editor_core_ui_input = @import("editor_core_ui_input.zig");
const project_editor_edit = @import("project_editor_edit.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_types = @import("project_editor_types.zig");
const input_keyboard = @import("project_editor_input_keyboard.zig");
const input_viewport = @import("project_editor_input_viewport.zig");
const input_drag = @import("project_editor_input_drag.zig");
const input_walk = @import("project_editor_input_walk.zig");

const core_ui = friendly_engine.modules.core_ui;
const ProjectEditorState = project_editor_state.ProjectEditorState;
const EditorAction = project_editor_types.EditorAction;

pub fn applyFrameInput(
    state: *ProjectEditorState,
    ui: *core_ui.UiContext,
    acc: *editor_core_ui_input.Accumulator,
) !EditorAction {
    if (acc.quit_requested) state.should_quit = true;

    const input = ui.input;
    state.mouse_x = input.mouse_position.x;
    state.mouse_y = input.mouse_position.y;
    state.keyboard_mods = input.keyboard_mods;

    if (input.key_chars.len > 0 and state.focused_field != .none) {
        project_editor_edit.appendFieldInput(state, input.key_chars);
    }

    if (state.walk_mode) {
        if (input.motion_delta_x != 0 or input.motion_delta_y != 0) {
            state.camera.lookInPlace(input.motion_delta_x, input.motion_delta_y);
        }
        try input_walk.applyWalkKeys(state, acc);
        return currentAction(state);
    }

    try input_viewport.applyViewportPointerRelease(state, ui, input);
    if (state.drag_mode != .none or input_drag.viewportDragActive(state)) {
        input_drag.handleDrag(state, input);
    } else if (!core_ui.input_tree.blocksViewportPointer(ui)) {
        try input_viewport.applyViewportPointerPress(state, ui, input);
    }
    input_viewport.updateViewportHover(state, ui, input);

    if (state.focused_field == .none and !core_ui.input_tree.blocksKeyboard(ui)) {
        if (state.command_palette_open) {
            try input_keyboard.applyCommandPaletteInput(state, acc, input);
        } else {
            try input_keyboard.applyKeyboard(state, acc);
        }
    } else if (state.focused_field != .none) {
        try input_keyboard.applyFieldKeys(state, input);
    }

    input_viewport.applyViewportScroll(state, ui);
    return currentAction(state);
}

pub fn currentAction(state: *ProjectEditorState) EditorAction {
    if (state.should_quit) return .quit_app;
    if (state.should_close) return .close_project;
    return .continue_;
}

pub const update = input_walk.update;
pub const tryStartPendingDrag = input_drag.tryStartPendingDrag;
