const std = @import("std");
const shared = @import("runtime_shared");
const project_editor_edit = @import("project_editor_edit.zig");
const project_editor_materials = @import("project_editor_materials.zig");
const project_editor_state = @import("project_editor_state.zig");

const scene_texture = shared.scene_texture;
const ProjectEditorState = project_editor_state.ProjectEditorState;

pub fn applyToSelectedFace(state: *ProjectEditorState, material_id: project_editor_materials.MaterialId) void {
    const idx = state.selected_object orelse {
        project_editor_state.setStatus(state, "No selection");
        return;
    };
    const face = state.selected_face orelse {
        applyObjectMaterial(state, material_id);
        return;
    };
    project_editor_edit.pushUndoSnapshot(state);
    const material = project_editor_materials.get(material_id);
    const obj = &state.objects.items[idx];
    if (scene_texture.validateMaterialPath(material.path)) |reason| {
        setMaterialError(state, obj, reason);
        return;
    }
    clearMaterialError(state, obj);
    upsertFaceMaterial(state, obj, face, material.path, material.color);
    project_editor_state.setStatus(state, "Face material applied");
}

pub fn applyObjectMaterial(state: *ProjectEditorState, material_id: project_editor_materials.MaterialId) void {
    const idx = state.selected_object orelse return;
    project_editor_edit.pushUndoSnapshot(state);
    const material = project_editor_materials.get(material_id);
    const obj = &state.objects.items[idx];
    if (scene_texture.validateMaterialPath(material.path)) |reason| {
        setMaterialError(state, obj, reason);
        return;
    }
    clearMaterialError(state, obj);
    if (obj.material_path) |existing| state.allocator.free(existing);
    obj.material_path = tryDupPath(state, material.path) catch return;
    obj.base_color = material.color;
    @import("editor_scene_object.zig").fillCheckerTexture(obj.texture, @import("editor_scene_object.zig").TextureSize, material.color.r, material.color.g, material.color.b);
    project_editor_state.setStatus(state, "Material applied");
}

pub fn fitTexture(state: *ProjectEditorState) void {
    const idx = state.selected_object orelse return;
    project_editor_edit.pushUndoSnapshot(state);
    const obj = &state.objects.items[idx];
    obj.texture_transform = scene_texture.Transform.fitToFace(obj.scale.x, obj.scale.y);
    project_editor_state.setStatus(state, "Texture fit");
}

pub fn alignTexture(state: *ProjectEditorState) void {
    const idx = state.selected_object orelse return;
    project_editor_edit.pushUndoSnapshot(state);
    const obj = &state.objects.items[idx];
    obj.texture_transform = scene_texture.Transform.alignToFace(obj.scale.x, obj.scale.y);
    project_editor_state.setStatus(state, "Texture aligned");
}

pub fn rotateTexture(state: *ProjectEditorState, delta_deg: f32) void {
    const idx = state.selected_object orelse return;
    project_editor_edit.pushUndoSnapshot(state);
    state.objects.items[idx].texture_transform.rotation_deg += delta_deg;
    project_editor_state.setStatus(state, "Texture rotated");
}

pub fn scaleTexture(state: *ProjectEditorState, delta: f32) void {
    const idx = state.selected_object orelse return;
    project_editor_edit.pushUndoSnapshot(state);
    const transform = &state.objects.items[idx].texture_transform;
    transform.scale_world = @max(0.05, transform.scale_world + delta);
    project_editor_state.setStatus(state, "Texture scale changed");
}

fn upsertFaceMaterial(
    state: *ProjectEditorState,
    obj: *@import("editor_scene_object.zig").SceneObject,
    face_index: usize,
    path: []const u8,
    color: shared.color.Color,
) void {
    for (obj.face_materials, 0..) |*face, idx| {
        if (face.face_index == face_index) {
            state.allocator.free(face.material_path);
            face.material_path = tryDupPath(state, path) catch return;
            face.transform = obj.texture_transform;
            obj.base_color = color;
            return;
        }
        _ = idx;
    }
    const path_copy = tryDupPath(state, path) catch return;
    const next = state.allocator.alloc(scene_texture.FaceMaterial, obj.face_materials.len + 1) catch return;
    for (obj.face_materials, 0..) |face, i| next[i] = face;
    next[obj.face_materials.len] = .{
        .face_index = face_index,
        .material_path = path_copy,
        .transform = obj.texture_transform,
    };
    state.allocator.free(obj.face_materials);
    obj.face_materials = next;
    obj.base_color = color;
}

fn setMaterialError(state: *ProjectEditorState, obj: *@import("editor_scene_object.zig").SceneObject, reason: []const u8) void {
    if (obj.material_error) |existing| state.allocator.free(existing);
    obj.material_error = state.allocator.dupe(u8, reason) catch null;
    project_editor_state.setStatus(state, reason);
}

fn clearMaterialError(state: *ProjectEditorState, obj: *@import("editor_scene_object.zig").SceneObject) void {
    if (obj.material_error) |existing| {
        state.allocator.free(existing);
        obj.material_error = null;
    }
}

fn tryDupPath(state: *ProjectEditorState, path: []const u8) ![]u8 {
    return try state.allocator.dupe(u8, path);
}
