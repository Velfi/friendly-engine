const std = @import("std");
const friendly_engine = @import("friendly_engine");
const editor_core_ui_input = @import("editor_core_ui_input.zig");
const editor_draw = @import("editor_draw.zig");
const editor_shortcuts = @import("editor_shortcuts.zig");
const project_editor_command_palette = @import("project_editor_command_palette.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_edit = @import("project_editor_edit.zig");
const project_editor_scene = @import("project_editor_scene.zig");
const project_editor_input_cancel = @import("project_editor_input_cancel.zig");

const core_ui = friendly_engine.modules.core_ui;
const ProjectEditorState = project_editor_state.ProjectEditorState;

pub fn applyFieldKeys(state: *ProjectEditorState, input: core_ui.InputState) !void {
    if (input.escape_pressed) project_editor_edit.cancelFieldEdit(state);
    if (input.enter_pressed) project_editor_edit.applyFieldEdit(state);
    if (input.backspace_pressed) project_editor_edit.popFieldInput(state);
    if (input.tab_pressed) project_editor_edit.cycleFieldTab(state);
}

pub fn applyCommandPaletteInput(
    state: *ProjectEditorState,
    acc: *editor_core_ui_input.Accumulator,
    input: core_ui.InputState,
) !void {
    for (acc.key_events.items) |event| {
        if (!event.down or event.repeat) continue;
        if (editor_shortcuts.shortcutModifierPressed(event.mod) and event.key == 0x70) { // P
            project_editor_command_palette.toggle(state);
            return;
        }
        if (event.key == 0x1b) { // Escape
            project_editor_command_palette.close(state);
            project_editor_state.setStatus(state, "Command palette closed");
            return;
        }
        if (event.key == editor_draw.SDLK_BACKSPACE) {
            project_editor_command_palette.popFilterChar(state);
            return;
        }
        if (event.key == editor_draw.SDLK_RETURN) {
            _ = project_editor_command_palette.executeHighlighted(state);
            return;
        }
        if (event.key == editor_draw.SDLK_TAB) {
            _ = project_editor_command_palette.autocompleteFilter(state);
            return;
        }
        if (event.key == editor_draw.SDLK_UP) {
            project_editor_command_palette.moveHighlight(state, -1);
            return;
        }
        if (event.key == editor_draw.SDLK_DOWN) {
            project_editor_command_palette.moveHighlight(state, 1);
            return;
        }
        if (event.key == editor_draw.SDLK_RIGHT) {
            _ = project_editor_command_palette.autocompleteFilter(state);
            return;
        }
    }
    if (input.escape_pressed) {
        project_editor_command_palette.close(state);
        project_editor_state.setStatus(state, "Command palette closed");
        return;
    }
    if (input.enter_pressed) _ = project_editor_command_palette.executeHighlighted(state);
    if (input.tab_pressed) _ = project_editor_command_palette.autocompleteFilter(state);
    if (input.up_pressed) project_editor_command_palette.moveHighlight(state, -1);
    if (input.down_pressed) project_editor_command_palette.moveHighlight(state, 1);
    if (input.right_pressed) _ = project_editor_command_palette.autocompleteFilter(state);
    if (input.backspace_pressed) project_editor_command_palette.popFilterChar(state);
    if (input.key_chars.len > 0) project_editor_command_palette.appendFilterText(state, input.key_chars);
}

pub fn applyKeyboard(state: *ProjectEditorState, acc: *editor_core_ui_input.Accumulator) !void {
    for (acc.key_events.items) |event| {
        if (!event.down or event.repeat) continue;
        const mod = event.mod;
        const ctrl = (mod & editor_draw.SDL_KMOD_CTRL) != 0 or (mod & editor_draw.SDL_KMOD_GUI) != 0;
        const shift = (mod & editor_draw.SDL_KMOD_SHIFT) != 0;
        state.walk_fast = shift;
        if (shift and event.key == 0x60) {
            @import("project_editor_input_walk.zig").toggleWalkMode(state);
            return;
        }

        if (editor_shortcuts.shortcutModifierPressed(mod) and event.key == 0x70) { // P
            project_editor_command_palette.toggle(state);
            return;
        }
        if (ctrl and event.key == 0x73) { // S
            state.saveSceneToDisk() catch {
                project_editor_state.setStatus(state, "Scene save failed");
                return;
            };
            project_editor_state.setStatus(state, "Scene saved");
            return;
        }
        if (ctrl and shift and event.key == 0x7a) { // Z
            project_editor_edit.redo(state);
            return;
        }
        if (ctrl and event.key == 0x79) { // Y
            project_editor_edit.redo(state);
            return;
        }
        if (ctrl and event.key == 0x7a) { // Z
            project_editor_edit.undo(state);
            return;
        }
        if (ctrl and event.key == 0x64) { // D
            try project_editor_scene.duplicateSelected(state);
            return;
        }
        if (state.shading_hotkey_open) {
            if (applyBlenderShadingSelection(state, event.key)) return;
            if (event.key == 0x1b) { // Escape
                state.shading_hotkey_open = false;
                project_editor_state.setStatus(state, "Shading selection canceled");
                return;
            }
            state.shading_hotkey_open = false;
            project_editor_state.setStatus(state, "Shading selection canceled");
            return;
        }
        if (!ctrl and shift and event.key == 0x7a) { // Shift+Z
            toggleRenderedShading(state);
            return;
        }
        if (!ctrl and event.key == 0x7a) { // Z
            state.shading_hotkey_open = true;
            project_editor_state.setStatus(state, "Z shading: 2 Wire, 3 Solid, 4 Material, 5 Rendered");
            return;
        }
        switch (event.key) {
            0x1b => project_editor_input_cancel.cancelOngoingAction(state), // Escape
            editor_draw.SDLK_RETURN => {
                if (state.mode == .world_creation and state.world_tool == .roads) {
                    @import("project_editor_ui_world.zig").finishRoadPlacement(state);
                    return;
                }
                if (state.mode == .architecture_creation and state.architecture_tool == .curve) {
                    project_editor_edit.pushUndoSnapshot(state);
                    @import("project_editor_architecture_curve.zig").finishPlacement(state) catch {
                        project_editor_state.setStatus(state, "Curve solidify failed");
                    };
                    return;
                }
            },
            0x09 => project_editor_scene.cycleSelectionScope(state), // Tab
            0x7f => { // Delete
                try project_editor_scene.deleteSelected(state);
            },
            0x66 => @import("project_editor_input_drag.zig").frameSelected(state), // F
            0x31 => project_editor_scene.setMode(state, .world_creation),
            0x32 => project_editor_scene.setMode(state, .layout),
            0x33 => project_editor_scene.setMode(state, .architecture_creation),
            0x34 => project_editor_scene.setMode(state, .prop_creation),
            0x35 => project_editor_scene.setMode(state, .life),
            0x61 => {
                if (state.mode == .architecture_creation) @import("project_editor_ui_architecture.zig").selectTool(state, .add);
            }, // A
            0x73 => {
                if (state.mode == .architecture_creation and !ctrl) @import("project_editor_ui_architecture.zig").selectTool(state, .subtract);
            }, // S (without ctrl)
            0x67 => project_editor_edit.toggleSnap(state), // G
            0x77 => {
                state.edit_channel = .position;
                if (state.mode == .layout) state.object_tool = .move;
            }, // W
            0x65 => {
                if (state.mode == .layout) state.object_tool = .rotate;
            }, // E
            0x72 => {
                state.edit_channel = .scale;
                if (state.mode == .layout) state.object_tool = .scale;
            }, // R
            0x4000003a => state.move_axis = .x, // F1
            0x4000003b => state.move_axis = .y, // F2
            0x4000003c => state.move_axis = .z, // F3
            0x4000003d => state.move_axis = .xz, // F4
            0x40000050 => project_editor_edit.nudgeAxis(state, .x, -1, shift), // Left
            0x40000051 => project_editor_edit.nudgeAxis(state, .x, 1, shift), // Right
            0x40000052 => project_editor_edit.nudgeAxis(state, .z, -1, shift), // Up
            0x40000053 => project_editor_edit.nudgeAxis(state, .z, 1, shift), // Down
            0x2d, 0x5b => project_editor_scene.adjustBrushOrSelection(state, -1, shift), // -, [
            0x3d, 0x5d => project_editor_scene.adjustBrushOrSelection(state, 1, shift), // =, ]
            else => {},
        }
    }
}

fn applyBlenderShadingSelection(state: *ProjectEditorState, key: editor_draw.SDL_Keycode) bool {
    switch (key) {
        0x32 => setShadingMode(state, .wireframe, "Wireframe"), // 2
        0x33 => setShadingMode(state, .solid, "Solid"), // 3
        0x34 => setShadingMode(state, .material_preview, "Material Preview"), // 4
        0x35 => setShadingMode(state, .rendered, "Rendered"), // 5
        else => return false,
    }
    return true;
}

fn toggleRenderedShading(state: *ProjectEditorState) void {
    if (state.shading_mode == .rendered) {
        setShadingMode(state, .solid, "Solid");
    } else {
        setShadingMode(state, .rendered, "Rendered");
    }
}

fn setShadingMode(
    state: *ProjectEditorState,
    mode: project_editor_state.ShadingMode,
    label: []const u8,
) void {
    state.shading_hotkey_open = false;
    state.shading_mode = mode;
    project_editor_state.setStatus(state, label);
}

comptime {
    _ = @import("project_editor_input_cancel_tests.zig");
}

test "z hotkey opens blender shading selection and number keys choose modes" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
    };
    var acc = editor_core_ui_input.Accumulator.init(std.testing.allocator);
    defer acc.deinit();

    try acc.key_events.append(std.testing.allocator, .{
        .key = 0x7a,
        .mod = 0,
        .down = true,
        .repeat = false,
    });
    try applyKeyboard(&state, &acc);
    try std.testing.expect(state.shading_hotkey_open);

    acc.beginFrame();
    try acc.key_events.append(std.testing.allocator, .{
        .key = 0x32,
        .mod = 0,
        .down = true,
        .repeat = false,
    });
    try applyKeyboard(&state, &acc);
    try std.testing.expect(!state.shading_hotkey_open);
    try std.testing.expectEqual(project_editor_state.ShadingMode.wireframe, state.shading_mode);

    acc.beginFrame();
    try acc.key_events.append(std.testing.allocator, .{
        .key = 0x7a,
        .mod = 0,
        .down = true,
        .repeat = false,
    });
    try applyKeyboard(&state, &acc);
    acc.beginFrame();
    try acc.key_events.append(std.testing.allocator, .{
        .key = 0x33,
        .mod = 0,
        .down = true,
        .repeat = false,
    });
    try applyKeyboard(&state, &acc);
    try std.testing.expectEqual(project_editor_state.ShadingMode.solid, state.shading_mode);

    acc.beginFrame();
    try acc.key_events.append(std.testing.allocator, .{
        .key = 0x7a,
        .mod = 0,
        .down = true,
        .repeat = false,
    });
    try applyKeyboard(&state, &acc);
    acc.beginFrame();
    try acc.key_events.append(std.testing.allocator, .{
        .key = 0x34,
        .mod = 0,
        .down = true,
        .repeat = false,
    });
    try applyKeyboard(&state, &acc);
    try std.testing.expectEqual(project_editor_state.ShadingMode.material_preview, state.shading_mode);

    acc.beginFrame();
    try acc.key_events.append(std.testing.allocator, .{
        .key = 0x7a,
        .mod = 0,
        .down = true,
        .repeat = false,
    });
    try applyKeyboard(&state, &acc);
    acc.beginFrame();
    try acc.key_events.append(std.testing.allocator, .{
        .key = 0x35,
        .mod = 0,
        .down = true,
        .repeat = false,
    });
    try applyKeyboard(&state, &acc);
    try std.testing.expectEqual(project_editor_state.ShadingMode.rendered, state.shading_mode);
}

test "tab hotkey cycles shared selection scope" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .selection_scope = .object,
        .selected_face = 2,
    };
    var acc = editor_core_ui_input.Accumulator.init(std.testing.allocator);
    defer acc.deinit();

    try acc.key_events.append(std.testing.allocator, .{
        .key = editor_draw.SDLK_TAB,
        .mod = 0,
        .down = true,
        .repeat = false,
    });
    try applyKeyboard(&state, &acc);

    try std.testing.expectEqual(project_editor_state.SelectionScope.face, state.selection_scope);
    try std.testing.expect(state.selected_face == null);
    try std.testing.expectEqualStrings("Selection scope: Face", state.status_buf[0..state.status_len]);
}

test "tab cycles selection scope instead of editor mode" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
    };
    var acc = editor_core_ui_input.Accumulator.init(std.testing.allocator);
    defer acc.deinit();

    try acc.key_events.append(std.testing.allocator, .{
        .key = 0x09,
        .mod = 0,
        .down = true,
        .repeat = false,
    });
    try applyKeyboard(&state, &acc);
    try std.testing.expectEqual(project_editor_state.SelectionScope.face, state.selection_scope);
    try std.testing.expectEqual(project_editor_state.EditorMode.world_creation, state.mode);
}

test "shift z toggles rendered shading without blocking undo shortcuts" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
    };
    var acc = editor_core_ui_input.Accumulator.init(std.testing.allocator);
    defer acc.deinit();

    try acc.key_events.append(std.testing.allocator, .{
        .key = 0x7a,
        .mod = editor_draw.SDL_KMOD_SHIFT,
        .down = true,
        .repeat = false,
    });
    try applyKeyboard(&state, &acc);
    try std.testing.expectEqual(project_editor_state.ShadingMode.solid, state.shading_mode);

    acc.beginFrame();
    try acc.key_events.append(std.testing.allocator, .{
        .key = 0x7a,
        .mod = editor_draw.SDL_KMOD_SHIFT,
        .down = true,
        .repeat = false,
    });
    try applyKeyboard(&state, &acc);
    try std.testing.expectEqual(project_editor_state.ShadingMode.rendered, state.shading_mode);

    acc.beginFrame();
    try acc.key_events.append(std.testing.allocator, .{
        .key = 0x7a,
        .mod = editor_draw.SDL_KMOD_CTRL | editor_draw.SDL_KMOD_SHIFT,
        .down = true,
        .repeat = false,
    });
    try applyKeyboard(&state, &acc);
    try std.testing.expect(!state.shading_hotkey_open);
}
