const project_editor_edit = @import("project_editor_edit.zig");
const project_editor_materials = @import("project_editor_materials.zig");
const project_editor_state = @import("project_editor_state.zig");
const scene_object = @import("editor_scene_object.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const TextureSize = scene_object.TextureSize;
const fillCheckerTexture = scene_object.fillCheckerTexture;

pub fn select(state: *ProjectEditorState, id: project_editor_materials.MaterialId) void {
    const material = project_editor_materials.get(id);
    state.selected_material = id;
    state.brush_color = material.color;
    project_editor_state.setStatus(state, material.label);
}

pub fn apply(state: *ProjectEditorState, id: project_editor_materials.MaterialId) void {
    const material = project_editor_materials.get(id);
    state.selected_material = id;
    state.brush_color = material.color;
    const idx = state.selected_object orelse {
        project_editor_state.setStatus(state, material.label);
        return;
    };
    project_editor_edit.pushUndoSnapshot(state);
    const obj = &state.objects.items[idx];
    obj.base_color = material.color;
    fillCheckerTexture(obj.texture, TextureSize, material.color.r, material.color.g, material.color.b);
    project_editor_state.setStatus(state, "Material applied");
}
