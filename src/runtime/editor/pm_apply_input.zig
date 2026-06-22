const std = @import("std");
const friendly_engine = @import("friendly_engine");
const editor_core_ui_input = @import("editor_core_ui_input.zig");
const editor_draw = @import("editor_draw.zig");
const editor_shortcuts = @import("editor_shortcuts.zig");
const pm_state = @import("pm_state.zig");

const core_ui = friendly_engine.modules.core_ui;

pub fn applyFrameInput(
    state: *pm_state.ProjectManagerState,
    ui: *core_ui.UiContext,
    acc: *editor_core_ui_input.Accumulator,
) !bool {
    if (acc.quit_requested) state.should_quit = true;

    const input = ui.input;
    if (input.key_chars.len > 0 and (state.mode == .create or state.mode == .preset_name)) {
        appendInput(state, input.key_chars);
    }

    if (state.mode != .none) {
        try applyModalKeys(state, input);
        if (state.should_quit) return false;
        return true;
    }

    if (!core_ui.input_tree.blocksKeyboard(ui)) {
        try applyShortcuts(state, acc);
    }

    if (input.enter_pressed and state.window != null) {
        try state.openSelectedProject();
    }

    if (state.should_quit) return false;
    return true;
}

fn applyModalKeys(state: *pm_state.ProjectManagerState, input: core_ui.InputState) !void {
    if (input.escape_pressed) {
        if (state.mode == .preset_name) {
            state.mode = .manage_presets;
            state.input_len = 0;
            state.preset_name_action = .none;
        } else {
            state.cancelMode();
        }
    }
    if ((state.mode == .create or state.mode == .preset_name) and input.backspace_pressed) popInput(state);
    if (input.enter_pressed) try state.submitInput();
}

fn applyShortcuts(state: *pm_state.ProjectManagerState, acc: *editor_core_ui_input.Accumulator) !void {
    const window = state.window orelse return;
    for (acc.key_events.items) |event| {
        if (!event.down or event.repeat) continue;
        if (!editor_shortcuts.shortcutModifierPressed(event.mod)) continue;
        switch (event.key) {
            editor_draw.SDLK_N => state.beginMode(.create, "new_project"),
            editor_draw.SDLK_I => try state.requestImportFolderDialog(window),
            editor_draw.SDLK_O => try state.openSelectedProject(),
            editor_draw.SDLK_Q => state.should_quit = true,
            else => {},
        }
    }
}

fn appendInput(state: *pm_state.ProjectManagerState, text: []const u8) void {
    const available = state.input_buf.len - state.input_len;
    if (available == 0) return;
    const to_copy = @min(available, text.len);
    @memcpy(state.input_buf[state.input_len .. state.input_len + to_copy], text[0..to_copy]);
    state.input_len += to_copy;
}

fn popInput(state: *pm_state.ProjectManagerState) void {
    if (state.input_len > 0) state.input_len -= 1;
}
