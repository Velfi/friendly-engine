const std = @import("std");
const shared = @import("runtime_shared");
const geometry = shared.geometry;
const editor_math = shared.editor_math;
const project_editor_state = @import("project_editor_state.zig");
const project_editor_edit = @import("project_editor_edit.zig");
const project_editor_prop_asset = @import("project_editor_prop_asset.zig");
const project_editor_texture_paint = @import("project_editor_texture_paint.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;

pub fn extrudeSelectedFace(state: *ProjectEditorState) !void {
    const obj_idx = state.selected_object orelse return;
    const face_tri = state.selected_face orelse return;
    const obj = &state.objects.items[obj_idx];
    if (face_tri + 2 >= obj.mesh.indices.len) return;
    project_editor_edit.pushUndoSnapshot(state);

    const vi = [3]u32{ obj.mesh.indices[face_tri], obj.mesh.indices[face_tri + 1], obj.mesh.indices[face_tri + 2] };
    const p0 = obj.mesh.vertices[vi[0]].position;
    const p1 = obj.mesh.vertices[vi[1]].position;
    const p2 = obj.mesh.vertices[vi[2]].position;
    const normal = faceNormal(p0, p1, p2);
    const offset = editor_math.Vec3.scale(normal, if (state.snap_enabled) @max(0.25, state.snap_size * 0.5) else 0.35);

    const base: u32 = @intCast(obj.mesh.vertices.len);
    const new_vertices = try state.allocator.alloc(geometry.Vertex, obj.mesh.vertices.len + 3);
    @memcpy(new_vertices[0..obj.mesh.vertices.len], obj.mesh.vertices);
    new_vertices[base] = movedVertex(obj.mesh.vertices[vi[0]], offset);
    new_vertices[base + 1] = movedVertex(obj.mesh.vertices[vi[1]], offset);
    new_vertices[base + 2] = movedVertex(obj.mesh.vertices[vi[2]], offset);

    const new_indices = try state.allocator.alloc(u32, obj.mesh.indices.len + 21);
    @memcpy(new_indices[0..obj.mesh.indices.len], obj.mesh.indices);
    var out = obj.mesh.indices.len;
    appendTri(new_indices, &out, base, base + 1, base + 2);
    appendQuad(new_indices, &out, vi[0], vi[1], base + 1, base);
    appendQuad(new_indices, &out, vi[1], vi[2], base + 2, base + 1);
    appendQuad(new_indices, &out, vi[2], vi[0], base, base + 2);

    state.allocator.free(obj.mesh.vertices);
    state.allocator.free(obj.mesh.indices);
    obj.mesh.vertices = new_vertices;
    obj.mesh.indices = new_indices;
    obj.primitive_kind = null;
    project_editor_texture_paint.markPaintAtlasStale(obj);
    state.selected_face = obj.mesh.indices.len - 21;
    state.scene_dirty = true;
    if (state.mode == .prop_creation) project_editor_prop_asset.propagateSelectedAssetGeometry(state);
    project_editor_state.setStatus(state, "Face extruded");
}

pub fn insetSelectedFace(state: *ProjectEditorState) !void {
    const obj_idx = state.selected_object orelse return;
    const face_tri = state.selected_face orelse return;
    const obj = &state.objects.items[obj_idx];
    if (face_tri + 2 >= obj.mesh.indices.len) return;
    project_editor_edit.pushUndoSnapshot(state);

    const vi = [3]u32{ obj.mesh.indices[face_tri], obj.mesh.indices[face_tri + 1], obj.mesh.indices[face_tri + 2] };
    const p0 = obj.mesh.vertices[vi[0]].position;
    const p1 = obj.mesh.vertices[vi[1]].position;
    const p2 = obj.mesh.vertices[vi[2]].position;
    const center = editor_math.Vec3.scale(editor_math.Vec3.add(editor_math.Vec3.add(p0, p1), p2), 1.0 / 3.0);
    const normal_offset = editor_math.Vec3.scale(faceNormal(p0, p1, p2), 0.01);

    const base: u32 = @intCast(obj.mesh.vertices.len);
    const new_vertices = try state.allocator.alloc(geometry.Vertex, obj.mesh.vertices.len + 3);
    @memcpy(new_vertices[0..obj.mesh.vertices.len], obj.mesh.vertices);
    new_vertices[base] = insetVertex(obj.mesh.vertices[vi[0]], center, normal_offset);
    new_vertices[base + 1] = insetVertex(obj.mesh.vertices[vi[1]], center, normal_offset);
    new_vertices[base + 2] = insetVertex(obj.mesh.vertices[vi[2]], center, normal_offset);

    const new_indices = try state.allocator.alloc(u32, obj.mesh.indices.len + 18);
    @memcpy(new_indices[0..obj.mesh.indices.len], obj.mesh.indices);
    new_indices[face_tri] = base;
    new_indices[face_tri + 1] = base + 1;
    new_indices[face_tri + 2] = base + 2;
    var out = obj.mesh.indices.len;
    appendQuad(new_indices, &out, vi[0], vi[1], base + 1, base);
    appendQuad(new_indices, &out, vi[1], vi[2], base + 2, base + 1);
    appendQuad(new_indices, &out, vi[2], vi[0], base, base + 2);

    state.allocator.free(obj.mesh.vertices);
    state.allocator.free(obj.mesh.indices);
    obj.mesh.vertices = new_vertices;
    obj.mesh.indices = new_indices;
    obj.primitive_kind = null;
    project_editor_texture_paint.markPaintAtlasStale(obj);
    state.scene_dirty = true;
    if (state.mode == .prop_creation) project_editor_prop_asset.propagateSelectedAssetGeometry(state);
    project_editor_state.setStatus(state, "Face inset");
}

pub fn faceNormal(p0: editor_math.Vec3, p1: editor_math.Vec3, p2: editor_math.Vec3) editor_math.Vec3 {
    return editor_math.Vec3.normalized(editor_math.cross(editor_math.Vec3.sub(p1, p0), editor_math.Vec3.sub(p2, p0)));
}

pub fn movedVertex(vertex: geometry.Vertex, offset: editor_math.Vec3) geometry.Vertex {
    var copy = vertex;
    copy.position = editor_math.Vec3.add(vertex.position, offset);
    return copy;
}

pub fn insetVertex(vertex: geometry.Vertex, center: editor_math.Vec3, normal_offset: editor_math.Vec3) geometry.Vertex {
    var copy = vertex;
    const toward_center = editor_math.Vec3.scale(editor_math.Vec3.sub(center, vertex.position), 0.35);
    copy.position = editor_math.Vec3.add(editor_math.Vec3.add(vertex.position, toward_center), normal_offset);
    return copy;
}

pub fn appendTri(indices: []u32, out: *usize, a: u32, b: u32, c: u32) void {
    indices[out.*] = a;
    indices[out.* + 1] = b;
    indices[out.* + 2] = c;
    out.* += 3;
}

pub fn appendQuad(indices: []u32, out: *usize, a: u32, b: u32, c: u32, d: u32) void {
    appendTri(indices, out, a, b, c);
    appendTri(indices, out, a, c, d);
}

pub fn deleteSelectedFace(state: *ProjectEditorState) !void {
    const obj_idx = state.selected_object orelse return;
    const face_tri = state.selected_face orelse return;
    const obj = &state.objects.items[obj_idx];
    if (!obj.canModifyObject()) return;
    project_editor_edit.pushUndoSnapshot(state);
    if (face_tri + 2 >= obj.mesh.indices.len) return;
    const vi0 = obj.mesh.indices[face_tri];
    const vi1 = obj.mesh.indices[face_tri + 1];
    const vi2 = obj.mesh.indices[face_tri + 2];
    var new_indices = std.ArrayList(u32).empty;
    defer new_indices.deinit(state.allocator);
    var tri: usize = 0;
    while (tri + 2 < obj.mesh.indices.len) : (tri += 3) {
        if (tri == face_tri) continue;
        try new_indices.appendSlice(state.allocator, obj.mesh.indices[tri .. tri + 3]);
    }
    state.allocator.free(obj.mesh.indices);
    obj.mesh.indices = try new_indices.toOwnedSlice(state.allocator);
    _ = vi0;
    _ = vi1;
    _ = vi2;
    state.selected_face = null;
    obj.primitive_kind = null;
    project_editor_texture_paint.markPaintAtlasStale(obj);
    state.scene_dirty = true;
    if (state.mode == .prop_creation) project_editor_prop_asset.propagateSelectedAssetGeometry(state);
    project_editor_state.setStatus(state, "Face deleted");
}
