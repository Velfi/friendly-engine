const project_editor_state = @import("project_editor_state.zig");
const project_editor_types = @import("project_editor_types.zig");
const world_ocean = @import("project_editor_world_ocean.zig");
const world_authoring_ocean = @import("project_editor_world_authoring_ocean.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const WorldLayerId = project_editor_types.WorldLayerId;

pub fn commitOceanChange(state: *ProjectEditorState) !void {
    if (state.world_tool != .ocean and (state.selected_world_layer == null or !isOceanLayer(state.selected_world_layer.?))) {
        world_ocean.setStatus(state);
        return;
    }
    try world_authoring_ocean.persistFromState(state);
    world_ocean.refreshClipMesh(state) catch {};
}

pub fn toggleOcean(state: *ProjectEditorState) !void {
    state.world_ocean_visible = !state.world_ocean_visible;
    try commitOceanChange(state);
}

pub fn isOceanLayer(layer: WorldLayerId) bool {
    return switch (layer) {
        .ocean_wind, .ocean_waves => true,
        else => false,
    };
}
