const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const project_editor_mode_config = @import("project_editor_mode_config.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_types = @import("project_editor_types.zig");
const project_editor_ui_layout = @import("project_editor_ui_layout.zig");
const project_editor_ui_life = @import("project_editor_ui_life.zig");
const project_editor_ui_prop = @import("project_editor_ui_prop.zig");
const project_editor_ui_world = @import("project_editor_ui_world.zig");
const project_editor_ui_architecture = @import("project_editor_ui_architecture.zig");

const core_ui = friendly_engine.modules.core_ui;
const ProjectEditorState = project_editor_state.ProjectEditorState;
const EditorMode = project_editor_types.EditorMode;
const OverlayQuad = shared.gpu_scene.OverlayQuad;

pub const all = project_editor_mode_config.all_mode_descs;

pub fn enabled(state: *const ProjectEditorState, mode: EditorMode) bool {
    return project_editor_state.editorModeEnabled(state, mode);
}

pub fn desc(mode: EditorMode) *const project_editor_mode_config.EditorModeDesc {
    return project_editor_mode_config.descForMode(mode);
}

pub fn toolLabel(state: *const ProjectEditorState) []const u8 {
    return switch (state.mode) {
        .world_creation => project_editor_ui_world.currentToolLabel(state),
        .layout => state.object_tool.label(),
        .architecture_creation => state.architecture_tool.label(),
        .prop_creation => state.prop_tool.label(),
        .life => state.life_tool.label(),
    };
}

pub fn modeHint(state: *const ProjectEditorState) []const u8 {
    return switch (state.mode) {
        .world_creation => project_editor_ui_world.modeHint(state),
        .layout => project_editor_ui_layout.modeStatus,
        .architecture_creation => "Architecture mode: build, cut, texture, and tune colliders",
        .prop_creation => "Prop mode: create, texture, edit, and configure props",
        .life => "Life mode: pose and animate objects or bones",
    };
}

pub fn activate(state: *ProjectEditorState, mode: EditorMode) bool {
    if (!enabled(state, mode)) {
        project_editor_state.setStatus(state, "Editor mode unavailable in this project");
        return false;
    }
    @import("project_editor_scene.zig").setMode(state, mode);
    return true;
}

pub fn buildViewportTools(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    switch (state.mode) {
        .world_creation => try project_editor_ui_world.buildViewportTools(ui, state),
        .layout => try project_editor_ui_layout.buildViewportTools(ui, state),
        .architecture_creation => try project_editor_ui_architecture.buildToolbar(ui, state),
        .prop_creation => try project_editor_ui_prop.buildToolbar(ui, state),
        .life => try project_editor_ui_life.buildToolbar(ui, state),
    }
}

pub fn buildToolInspector(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    switch (state.mode) {
        .world_creation => try project_editor_ui_world.buildToolInspector(ui, state),
        .layout => try project_editor_ui_layout.buildToolInspector(ui, state),
        .architecture_creation => try project_editor_ui_architecture.buildToolInspector(ui, state),
        .prop_creation => try project_editor_ui_prop.buildToolInspector(ui, state),
        .life => try project_editor_ui_life.buildToolInspector(ui, state),
    }
}

pub fn buildLeftPanel(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    switch (state.mode) {
        .world_creation => try project_editor_ui_world.buildLayersPanel(ui, state),
        .architecture_creation => try project_editor_ui_architecture.buildArchitectureTree(ui, state),
        .prop_creation => try project_editor_ui_prop.buildBrowser(ui, state),
        .life => try project_editor_ui_life.buildLeftPanel(ui, state),
        .layout => unreachable,
    }
}

pub fn drawViewportOverlays(state: *ProjectEditorState, vp_w: f32, vp_h: f32) void {
    switch (state.mode) {
        .world_creation => project_editor_ui_world.drawViewportOverlays(state, vp_w, vp_h),
        .prop_creation => project_editor_ui_prop.drawViewportOverlays(state, vp_w, vp_h),
        else => {},
    }
}

pub fn appendGpuViewportOverlays(
    state: *ProjectEditorState,
    allocator: std.mem.Allocator,
    out: *std.ArrayList(OverlayQuad),
) !void {
    switch (state.mode) {
        .world_creation => try project_editor_ui_world.appendGpuViewportOverlays(state, allocator, out),
        .prop_creation => try project_editor_ui_prop.appendGpuViewportOverlays(state, allocator, out),
        else => {},
    }
}

pub fn commandAllowed(state: *const ProjectEditorState, command_id: []const u8, section: []const u8) bool {
    if (project_editor_mode_config.descForCommand(command_id)) |mode_desc| {
        return enabled(state, mode_desc.mode);
    }
    if (std.mem.eql(u8, section, "world creation")) return enabled(state, .world_creation);
    if (std.mem.eql(u8, section, "layout")) return enabled(state, .layout);
    if (std.mem.eql(u8, section, "architecture creation")) return enabled(state, .architecture_creation);
    if (std.mem.eql(u8, section, "prop creation")) return enabled(state, .prop_creation);
    if (std.mem.eql(u8, section, "life")) return enabled(state, .life);
    return true;
}
