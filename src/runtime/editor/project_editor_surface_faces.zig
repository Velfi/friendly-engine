const std = @import("std");
const project_editor_edit = @import("project_editor_edit.zig");
const project_editor_state = @import("project_editor_state.zig");

const scene_surface = @import("runtime_shared").scene_surface;
const ProjectEditorState = project_editor_state.ProjectEditorState;
const SceneObject = @import("editor_scene_object.zig").SceneObject;

pub fn cycleSelectedFace(state: *ProjectEditorState) void {
    const idx = state.selected_object orelse {
        project_editor_state.setStatus(state, "No selection");
        return;
    };
    const face = state.selected_face orelse {
        project_editor_state.setStatus(state, "Select a face");
        return;
    };
    project_editor_edit.pushUndoSnapshot(state);
    const obj = &state.objects.items[idx];
    const current = findFaceSurface(obj, face) orelse scene_surface.SurfaceType.default;
    upsertFaceSurface(state, obj, face, current.next());
    project_editor_state.setStatus(state, "Surface type updated");
}

pub fn surfaceLabel(obj: *const SceneObject, face_index: ?usize) []const u8 {
    if (face_index) |fi| {
        if (findFaceSurface(obj, fi)) |surface_type| return surface_type.label();
    }
    return scene_surface.SurfaceType.default.label();
}

pub fn findFaceSurface(obj: *const SceneObject, face_index: usize) ?scene_surface.SurfaceType {
    for (obj.face_surfaces) |face| {
        if (face.face_index == face_index) return face.surface_type;
    }
    return null;
}

fn upsertFaceSurface(
    state: *ProjectEditorState,
    obj: *SceneObject,
    face_index: usize,
    surface_type: scene_surface.SurfaceType,
) void {
    for (obj.face_surfaces, 0..) |*face, idx| {
        if (face.face_index == face_index) {
            face.surface_type = surface_type;
            return;
        }
        _ = idx;
    }
    const next = state.allocator.alloc(scene_surface.FaceSurface, obj.face_surfaces.len + 1) catch return;
    for (obj.face_surfaces, 0..) |face, i| next[i] = face;
    next[obj.face_surfaces.len] = .{
        .face_index = face_index,
        .surface_type = surface_type,
    };
    state.allocator.free(obj.face_surfaces);
    obj.face_surfaces = next;
}

pub fn duplicateFaceSurfaces(allocator: std.mem.Allocator, faces: []const scene_surface.FaceSurface) ![]scene_surface.FaceSurface {
    const copy = try allocator.alloc(scene_surface.FaceSurface, faces.len);
    for (faces, 0..) |face, idx| {
        copy[idx] = scene_surface.FaceSurface.duplicate(allocator, face);
    }
    return copy;
}
