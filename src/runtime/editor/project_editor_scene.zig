const std = @import("std");
const shared = @import("runtime_shared");
const friendly_engine = @import("friendly_engine");
const blockout = @import("project_editor_blockout.zig");
const editor_math = shared.editor_math;
const geometry = shared.geometry;
const scene_io = shared.scene_io;
const scene_document = shared.scene_document;
const scene_resolve = shared.scene_resolve;
const editor_draw = @import("editor_draw.zig");
const editor_selection = @import("editor_selection.zig");
const scene_object = @import("editor_scene_object.zig");
const editor_raycast = @import("editor_raycast.zig");
const scene_hierarchy = @import("editor_scene_hierarchy.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_types = @import("project_editor_types.zig");
const project_editor_edit = @import("project_editor_edit.zig");
const project_editor_texture_paint = @import("project_editor_texture_paint.zig");
const world_authoring = @import("project_editor_world_authoring.zig");
const ui_world = @import("project_editor_ui_world.zig");
const project_editor_prop_asset = @import("project_editor_prop_asset.zig");
const project_editor_mode_config = @import("project_editor_mode_config.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const SceneObject = scene_object.SceneObject;
const TextureSize = scene_object.TextureSize;
const fillCheckerTexture = scene_object.fillCheckerTexture;
const snapValue = editor_raycast.snapValue;
const snapVec3 = editor_raycast.snapVec3;
const objectWorldBounds = editor_raycast.objectWorldBounds;
const aabbOverlaps = editor_raycast.aabbOverlaps;
const pointToSegmentDist = editor_raycast.pointToSegmentDist;
const raycastMesh = editor_raycast.raycastMesh;
const local_csg = friendly_engine.modules.local_csg;
const PropField = project_editor_types.PropField;
const GizmoAxis = project_editor_types.GizmoAxis;
const MoveAxis = project_editor_types.MoveAxis;
const EditChannel = project_editor_types.EditChannel;

pub fn setMode(state: *ProjectEditorState, mode: project_editor_types.EditorMode) void {
    if (state.mode == mode) return;
    if (!project_editor_state.editorModeEnabled(state, mode)) {
        project_editor_state.setStatus(state, "Editor mode unavailable in this project");
        return;
    }
    state.mode = mode;
    onModeChanged(state);
}

pub fn setObjectTool(state: *ProjectEditorState, tool: project_editor_types.ObjectTool) void {
    if (!project_editor_state.editorModeEnabled(state, .layout)) {
        project_editor_state.setStatus(state, "Layout mode unavailable in this project");
        return;
    }
    state.mode = .layout;
    clearSelectionIfHiddenInMode(state);
    state.object_tool = tool;
    state.edit_channel = switch (tool) {
        .scale => .scale,
        else => .position,
    };
    state.drag_mode = .none;
    state.pending_object_drag = .none;
    state.gizmo_drag_axis = null;
    project_editor_state.setStatus(state, switch (tool) {
        .select => "Select tool",
        .move => "Move tool",
        .rotate => "Rotate tool",
        .scale => "Scale tool",
    });
}

pub fn setEditTool(state: *ProjectEditorState, tool: project_editor_types.EditTool) void {
    if (!project_editor_state.editorModeEnabled(state, .architecture_creation)) {
        project_editor_state.setStatus(state, "Architecture mode unavailable in this project");
        return;
    }
    state.mode = .architecture_creation;
    clearSelectionIfHiddenInMode(state);
    state.edit_tool = tool;
    state.architecture_tool = switch (tool) {
        .vertex => .vertex,
        .edge => .edge,
        .face => .face,
        .extrude => .extrude,
        .inset => .inset,
    };
    state.selected_vertex = null;
    state.selected_edge = null;
    state.selected_face = null;
    project_editor_state.setStatus(state, switch (tool) {
        .vertex => "Vertex edit tool",
        .edge => "Edge edit tool",
        .face => "Face edit tool",
        .extrude => "Extrude: click a face",
        .inset => "Inset: click a face",
    });
}

const scene_objects = @import("project_editor_scene_objects.zig");

pub const addPrimitive = scene_objects.addPrimitive;
pub const addEditorObject = scene_objects.addEditorObject;
pub const addMarkerObject = scene_objects.addMarkerObject;
pub const instantiateSelectedAsset = scene_objects.instantiateSelectedAsset;
pub const instantiatePropAsset = scene_objects.instantiatePropAsset;
pub const duplicateSelected = scene_objects.duplicateSelected;

pub fn cycleMoveAxis(state: *ProjectEditorState) void {
    state.move_axis = switch (state.move_axis) {
        .xz => .x,
        .x => .y,
        .y => .z,
        .z => .xy,
        .xy => .yz,
        .yz => .xz,
    };
    project_editor_state.setStatus(state, "Axis changed");
}

pub fn deleteSelected(state: *ProjectEditorState) !void {
    if (state.mode == .world_creation and !state.selected_world_curve_hit.isNone()) {
        _ = ui_world.deleteSelectedWorldCurvePart(state);
        return;
    }
    if (state.mode == .architecture_creation and state.selected_face != null) {
        try deleteSelectedFace(state);
        return;
    }
    const idx = state.selected_object orelse {
        project_editor_state.setStatus(state, "Nothing selected");
        return;
    };
    if (state.objects.items[idx].isImmutable()) {
        project_editor_state.setStatus(state, "Object is immutable");
        return;
    }
    project_editor_edit.pushUndoSnapshot(state);
    const removed_id = state.objects.items[idx].id;
    var removed = state.objects.orderedRemove(idx);
    removed.deinit(state.allocator);
    scene_hierarchy.clearParentReferences(state.objects.items, removed_id);
    if (state.objects.items.len == 0) {
        state.selected_object = null;
    } else if (idx >= state.objects.items.len) {
        state.selected_object = state.objects.items.len - 1;
    }
    state.selected_vertex = null;
    state.selected_edge = null;
    state.selected_face = null;
    project_editor_state.setStatus(state, "Object deleted");
}

pub fn cycleMode(state: *ProjectEditorState) void {
    const current_idx = project_editor_mode_config.modeIndex(state.mode);
    var offset: usize = 1;
    while (offset <= project_editor_mode_config.mode_count) : (offset += 1) {
        const idx = (current_idx + offset) % project_editor_mode_config.mode_count;
        const candidate = project_editor_mode_config.all_mode_descs[idx].mode;
        if (project_editor_state.editorModeEnabled(state, candidate)) {
            state.mode = candidate;
            onModeChanged(state);
            return;
        }
    }
    project_editor_state.setStatus(state, "No editor modes enabled");
}

pub fn cycleSelectionScope(state: *ProjectEditorState) void {
    setSelectionScope(state, state.selection_scope.next());
}

pub fn setSelectionScope(state: *ProjectEditorState, scope: editor_selection.Scope) void {
    state.selection_scope = scope;
    state.selection_cycle_index = 0;
    state.selected_vertex = null;
    state.selected_edge = null;
    state.selected_face = null;
    state.selected_shape_source = false;
    state.selected_shape_operation = false;
    switch (scope) {
        .object => {
            state.object_tool = .select;
        },
        .face => {
            state.edit_tool = .face;
            state.architecture_tool = .face;
        },
        .edge => {
            state.edit_tool = .edge;
            state.architecture_tool = .edge;
        },
        .point => {
            state.edit_tool = .vertex;
            state.architecture_tool = .vertex;
        },
        .source, .operation => {
            state.mode = .prop_creation;
            state.prop_workspace_mode = .edit;
            state.prop_tool = .edit;
            clearObjectSelection(state);
            const has_shape_source = state.prop_sketch_mode != .none and state.prop_sketch_points.items.len > 0;
            state.selected_shape_source = has_shape_source and scope == .source;
            state.selected_shape_operation = has_shape_source and scope == .operation;
        },
        .marker => {
            state.left_tab = .add;
            normalizeMarkerScopeSelection(state);
        },
    }
    var buf: [64]u8 = undefined;
    project_editor_state.setStatus(state, std.fmt.bufPrint(&buf, "Selection scope: {s}", .{scope.label()}) catch "Selection scope changed");
}

fn clearObjectSelection(state: *ProjectEditorState) void {
    state.selected_object = null;
    state.selected_object_ids.clearRetainingCapacity();
}

fn normalizeMarkerScopeSelection(state: *ProjectEditorState) void {
    if (state.selected_object) |idx| {
        if (idx >= state.objects.items.len or state.objects.items[idx].marker == null) {
            state.selected_object = null;
        }
    }

    var write: usize = 0;
    for (state.selected_object_ids.items) |object_id| {
        if (markerObjectIndexById(state, object_id) == null) continue;
        state.selected_object_ids.items[write] = object_id;
        write += 1;
    }
    state.selected_object_ids.shrinkRetainingCapacity(write);
}

fn markerObjectIndexById(state: *const ProjectEditorState, object_id: u64) ?usize {
    for (state.objects.items, 0..) |obj, idx| {
        if (obj.id == object_id and obj.marker != null) return idx;
    }
    return null;
}

pub fn onModeChanged(state: *ProjectEditorState) void {
    clearSelectionIfHiddenInMode(state);
    state.selected_vertex = null;
    state.selected_edge = null;
    state.selected_face = null;
    state.drag_mode = .none;
    state.pending_object_drag = .none;
    state.pending_gizmo_axis = null;
    state.gizmo_drag_axis = null;
    state.blockout_drag_start = null;
    state.blockout_drag_end = null;
    const msg = switch (state.mode) {
        .world_creation => blk: {
            state.left_tab = .world;
            break :blk ui_world.modeHint(state);
        },
        .layout => "Layout mode: select and transform objects",
        .architecture_creation => "Architecture mode: build, cut, texture, and tune colliders",
        .prop_creation => "Prop mode: create, texture, edit, and configure props",
        .life => "Life mode: pose and animate objects or bones",
    };
    if (state.mode == .prop_creation) state.left_tab = .assets;
    project_editor_state.setStatus(state, msg);
}

fn clearSelectionIfHiddenInMode(state: *ProjectEditorState) void {
    const idx = state.selected_object orelse return;
    if (idx >= state.objects.items.len or !project_editor_state.objectVisible(state, &state.objects.items[idx])) {
        state.selected_object = null;
    }
}

pub fn pointInViewport(state: *ProjectEditorState, x: f32, y: f32) bool {
    return editor_draw.pointInRect(x, y, state.viewport_screen_rect);
}

pub fn paintAtScreen(state: *ProjectEditorState, x: f32, y: f32) void {
    if (!pointInViewport(state, x, y)) return;
    const local_x = x - state.viewport_screen_rect.x;
    const local_y = y - state.viewport_screen_rect.y;
    paintAt(state, local_x, local_y, state.viewport_screen_rect.w, state.viewport_screen_rect.h);
}

const scene_pick = @import("project_editor_scene_pick.zig");
const scene_mesh_edit = @import("project_editor_scene_mesh_edit.zig");

pub const pickObject = scene_pick.pickObject;
pub const dragBoxSelect = scene_pick.dragBoxSelect;
pub const updateHover = scene_pick.updateHover;
pub const clearHover = scene_pick.clearHover;
pub const pickMeshHit = scene_pick.pickMeshHit;
pub const pickVertex = scene_pick.pickVertex;
pub const extrudeSelectedFace = scene_mesh_edit.extrudeSelectedFace;
pub const insetSelectedFace = scene_mesh_edit.insetSelectedFace;
pub const deleteSelectedFace = scene_mesh_edit.deleteSelectedFace;

pub fn adjustBrushOrSelection(state: *ProjectEditorState, sign: i32, all_axes: bool) void {
    if (state.mode == .architecture_creation and state.architecture_tool.isBlockoutDrawTool()) {
        const step = if (state.snap_enabled) state.snap_size else 0.5;
        const delta = @as(f32, @floatFromInt(sign)) * step;
        state.blockout_brush_size = @max(step, state.blockout_brush_size + delta);
        project_editor_state.setStatus(state, "Brush size updated");
        return;
    }
    project_editor_edit.adjustSelected(state, sign, all_axes);
}

pub const screenToGroundPoint = blockout.screenToGroundPoint;
pub const beginBlockoutDrag = blockout.beginBlockoutDrag;
pub const updateBlockoutDrag = blockout.updateBlockoutDrag;
pub const blockoutBrushAabb = blockout.blockoutBrushAabb;
pub const architectureDragPreviewAabb = blockout.architectureDragPreviewAabb;
pub const finishBlockoutBrush = blockout.finishBlockoutBrush;
pub const addBlockoutBox = blockout.addBlockoutBox;
pub const subtractBlockoutBox = blockout.subtractBlockoutBox;
pub const subtractBlockoutWedge = blockout.subtractBlockoutWedge;
pub const brushAabbFromDrag = blockout.brushAabbFromDrag;
pub const rayIntersectsAabb = blockout.rayIntersectsAabb;

pub fn moveSelectedObject(state: *ProjectEditorState, dx: f32, dy: f32) void {
    const idx = state.selected_object orelse return;
    const obj = &state.objects.items[idx];
    if (!obj.canModifyObject()) return;
    const scale = state.camera.distance * 0.003;
    const delta_x = dx * scale;
    const delta_y = -dy * scale;
    const delta_z = -dy * scale;

    if (state.edit_channel == .scale) {
        const scale_delta = -dy * scale * 0.02;
        switch (state.move_axis) {
            .xz => {
                obj.scale.x = @max(0.01, obj.scale.x + scale_delta);
                obj.scale.y = @max(0.01, obj.scale.y + scale_delta);
                obj.scale.z = @max(0.01, obj.scale.z + scale_delta);
            },
            .x => obj.scale.x = @max(0.01, obj.scale.x + scale_delta),
            .y => obj.scale.y = @max(0.01, obj.scale.y + scale_delta),
            .z => obj.scale.z = @max(0.01, obj.scale.z + scale_delta),
            .xy => {
                obj.scale.x = @max(0.01, obj.scale.x + scale_delta);
                obj.scale.y = @max(0.01, obj.scale.y + scale_delta);
            },
            .yz => {
                obj.scale.y = @max(0.01, obj.scale.y + scale_delta);
                obj.scale.z = @max(0.01, obj.scale.z + scale_delta);
            },
        }
        state.drag_moved = true;
        return;
    }

    switch (state.move_axis) {
        .xz => {
            obj.position.x += delta_x;
            obj.position.z += delta_z;
        },
        .x => obj.position.x += delta_x,
        .y => obj.position.y += delta_y,
        .z => obj.position.z += delta_z,
        .xy => {
            obj.position.x += delta_x;
            obj.position.y += delta_y;
        },
        .yz => {
            obj.position.y += delta_y;
            obj.position.z += delta_z;
        },
    }

    if (state.snap_enabled) {
        if (state.move_axis == .xz or state.move_axis == .x or state.move_axis == .xy) {
            obj.position.x = snapValue(obj.position.x, state.snap_size);
        }
        if (state.move_axis == .y or state.move_axis == .xy or state.move_axis == .yz) {
            obj.position.y = snapValue(obj.position.y, state.snap_size);
        }
        if (state.move_axis == .xz or state.move_axis == .z or state.move_axis == .yz) {
            obj.position.z = snapValue(obj.position.z, state.snap_size);
        }
    }
    state.drag_moved = true;
}

pub fn moveSelectedVertex(state: *ProjectEditorState, dx: f32, dy: f32) void {
    const obj_idx = state.selected_object orelse return;
    const vi = state.selected_vertex orelse return;
    const obj = &state.objects.items[obj_idx];
    if (!obj.canModifyObject()) return;
    if (vi >= obj.mesh.vertices.len) return;
    const offset = meshDragOffset(state, obj, dx, dy);
    if (blockout.moveArchitectureVertexByMeshVertex(state, obj_idx, vi, offset) catch false) return;
    applyVertexOffset(state, obj, &.{vi}, offset);
}

pub fn moveSelectedEdge(state: *ProjectEditorState, dx: f32, dy: f32) void {
    const obj_idx = state.selected_object orelse return;
    const edge = state.selected_edge orelse return;
    const obj = &state.objects.items[obj_idx];
    if (!obj.canModifyObject()) return;
    if (edge[0] >= obj.mesh.vertices.len or edge[1] >= obj.mesh.vertices.len) return;
    if (state.prop_loop_mode and state.mode == .prop_creation) {
        moveSelectedEdgeLoop(state, obj, edge, meshDragOffset(state, obj, dx, dy));
        return;
    }
    applyVertexOffset(state, obj, &.{ edge[0], edge[1] }, meshDragOffset(state, obj, dx, dy));
}

pub fn moveSelectedFace(state: *ProjectEditorState, dx: f32, dy: f32) void {
    const obj_idx = state.selected_object orelse return;
    const face_tri = state.selected_face orelse return;
    const obj = &state.objects.items[obj_idx];
    if (!obj.canModifyObject()) return;
    if (face_tri + 2 >= obj.mesh.indices.len) return;
    applyVertexOffset(state, obj, &.{
        obj.mesh.indices[face_tri],
        obj.mesh.indices[face_tri + 1],
        obj.mesh.indices[face_tri + 2],
    }, meshDragOffset(state, obj, dx, dy));
}

pub fn offsetSelectedVertex(state: *ProjectEditorState, offset: editor_math.Vec3) void {
    const obj_idx = state.selected_object orelse return;
    const vi = state.selected_vertex orelse return;
    const obj = &state.objects.items[obj_idx];
    if (!obj.canModifyObject()) return;
    if (vi >= obj.mesh.vertices.len) return;
    applyVertexOffset(state, obj, &.{vi}, offset);
}

pub fn offsetSelectedEdge(state: *ProjectEditorState, offset: editor_math.Vec3) void {
    const obj_idx = state.selected_object orelse return;
    const edge = state.selected_edge orelse return;
    const obj = &state.objects.items[obj_idx];
    if (!obj.canModifyObject()) return;
    if (edge[0] >= obj.mesh.vertices.len or edge[1] >= obj.mesh.vertices.len) return;
    if (state.prop_loop_mode and state.mode == .prop_creation) {
        moveSelectedEdgeLoop(state, obj, edge, offset);
        return;
    }
    applyVertexOffset(state, obj, &.{ edge[0], edge[1] }, offset);
}

pub fn offsetSelectedFace(state: *ProjectEditorState, offset: editor_math.Vec3) void {
    const obj_idx = state.selected_object orelse return;
    const face_tri = state.selected_face orelse return;
    const obj = &state.objects.items[obj_idx];
    if (!obj.canModifyObject()) return;
    if (face_tri + 2 >= obj.mesh.indices.len) return;
    applyVertexOffset(state, obj, &.{
        obj.mesh.indices[face_tri],
        obj.mesh.indices[face_tri + 1],
        obj.mesh.indices[face_tri + 2],
    }, offset);
}

fn meshDragOffset(state: *const ProjectEditorState, obj: *const SceneObject, dx: f32, dy: f32) editor_math.Vec3 {
    const scale = state.camera.distance * 0.002 / @max(0.1, obj.scale.x);
    return .{ .x = dx * scale, .y = 0.0, .z = -dy * scale };
}

fn applyVertexOffset(state: *ProjectEditorState, obj: *SceneObject, vertices: []const u32, offset: editor_math.Vec3) void {
    for (vertices) |vi| {
        if (vi >= obj.mesh.vertices.len) continue;
        obj.mesh.vertices[vi].position = editor_math.Vec3.add(obj.mesh.vertices[vi].position, offset);
    }
    obj.primitive_kind = null;
    project_editor_texture_paint.markPaintAtlasStale(obj);
    state.scene_dirty = true;
    state.drag_moved = true;
    if (state.mode == .prop_creation) project_editor_prop_asset.propagateSelectedAssetGeometry(state);
}

fn moveSelectedEdgeLoop(state: *ProjectEditorState, obj: *SceneObject, edge: [2]u32, offset: editor_math.Vec3) void {
    const marks = state.allocator.alloc(bool, obj.mesh.vertices.len) catch return;
    defer state.allocator.free(marks);
    @memset(marks, false);
    marks[edge[0]] = true;
    marks[edge[1]] = true;

    const dir = edgeDirection(obj, edge) orelse return;
    var changed = true;
    while (changed) {
        changed = false;
        var tri: usize = 0;
        while (tri + 2 < obj.mesh.indices.len) : (tri += 3) {
            const tri_touches_loop = marks[obj.mesh.indices[tri]] or marks[obj.mesh.indices[tri + 1]] or marks[obj.mesh.indices[tri + 2]];
            if (!tri_touches_loop) continue;
            const tri_edges = [_][2]u32{
                .{ obj.mesh.indices[tri], obj.mesh.indices[tri + 1] },
                .{ obj.mesh.indices[tri + 1], obj.mesh.indices[tri + 2] },
                .{ obj.mesh.indices[tri + 2], obj.mesh.indices[tri] },
            };
            for (tri_edges) |candidate| {
                if (!edgeParallelTo(obj, candidate, dir)) continue;
                if (!marks[candidate[0]]) {
                    marks[candidate[0]] = true;
                    changed = true;
                }
                if (!marks[candidate[1]]) {
                    marks[candidate[1]] = true;
                    changed = true;
                }
            }
        }
    }

    for (marks, 0..) |marked, vi| {
        if (!marked) continue;
        obj.mesh.vertices[vi].position = editor_math.Vec3.add(obj.mesh.vertices[vi].position, offset);
    }
    obj.primitive_kind = null;
    project_editor_texture_paint.markPaintAtlasStale(obj);
    state.scene_dirty = true;
    state.drag_moved = true;
    project_editor_prop_asset.propagateSelectedAssetGeometry(state);
}

fn edgeDirection(obj: *const SceneObject, edge: [2]u32) ?editor_math.Vec3 {
    if (edge[0] >= obj.mesh.vertices.len or edge[1] >= obj.mesh.vertices.len) return null;
    const delta = editor_math.Vec3.sub(obj.mesh.vertices[edge[1]].position, obj.mesh.vertices[edge[0]].position);
    const len_sq = editor_math.Vec3.dot(delta, delta);
    if (len_sq < 0.000001) return null;
    return editor_math.Vec3.scale(delta, 1.0 / @sqrt(len_sq));
}

fn edgeParallelTo(obj: *const SceneObject, edge: [2]u32, dir: editor_math.Vec3) bool {
    const candidate = edgeDirection(obj, edge) orelse return false;
    return @abs(editor_math.Vec3.dot(candidate, dir)) > 0.94;
}

pub fn paintAtMouse(state: *ProjectEditorState, x: f32, y: f32) void {
    paintAtScreen(state, x, y);
}

pub fn paintAt(state: *ProjectEditorState, local_x: f32, local_y: f32, vp_w: f32, vp_h: f32) void {
    const idx = state.selected_object orelse return;
    const obj = &state.objects.items[idx];
    if (!obj.canModifyObject()) return;
    if (!project_editor_texture_paint.ensurePaintAtlas(state, obj)) return;
    const ray = project_editor_state.rayFromViewport(state, local_x, local_y, vp_w, vp_h);
    const hit = raycastMesh(ray.origin, ray.dir, obj, scene_hierarchy.objectWorldTransform(state.objects.items, idx));
    if (hit == null) return;
    const uv = hit.?.uv;
    project_editor_texture_paint.paintAtUv(state, obj, uv);
}

comptime {
    _ = @import("project_editor_scene_tests.zig");
}
