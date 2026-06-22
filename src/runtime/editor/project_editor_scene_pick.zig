const std = @import("std");
const shared = @import("runtime_shared");
const editor_math = shared.editor_math;
const editor_selection = @import("editor_selection.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_edit = @import("project_editor_edit.zig");
const shape_operation = @import("shape_operation.zig");
const shape_source = @import("shape_source.zig");
const scene_mesh_edit = @import("project_editor_scene_mesh_edit.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const SceneObject = @import("editor_scene_object.zig").SceneObject;
const intersectRayTriangle = @import("editor_raycast.zig").intersectRayTriangle;
const pointToSegmentDist = @import("editor_raycast.zig").pointToSegmentDist;
const raycastMesh = @import("editor_raycast.zig").raycastMesh;
const scene_hierarchy = @import("editor_scene_hierarchy.zig");

const marker_hover_radius: f32 = 20.0;

pub fn pickObject(state: *ProjectEditorState, local_x: f32, local_y: f32, vp_w: f32, vp_h: f32) void {
    if (state.selection_scope == .source or state.selection_scope == .operation) {
        if (selectShapeIntent(state, state.selection_scope)) return;
    }
    if (state.selection_scope == .marker) {
        if (pickMarkerObject(state, local_x, local_y, vp_w, vp_h)) return;
    }

    const ray = project_editor_state.rayFromViewport(state, local_x, local_y, vp_w, vp_h);
    var hits: std.ArrayList(editor_selection.Hit) = .empty;
    defer hits.deinit(state.allocator);

    for (state.objects.items, 0..) |*obj, idx| {
        if (!project_editor_state.objectVisible(state, obj)) continue;
        const world_xf = scene_hierarchy.objectWorldTransform(state.objects.items, idx);
        const hit = raycastMesh(ray.origin, ray.dir, obj, world_xf);
        if (hit) |h| {
            if (h.t <= 0) continue;
            hits.append(state.allocator, .{
                .scope = .object,
                .target = .{ .object = obj.id },
                .screen_distance_sq = 0,
                .depth = h.t,
                .screen = .{ .x = local_x, .y = local_y },
                .world = editor_math.Vec3.add(ray.origin, editor_math.Vec3.scale(ray.dir, h.t)),
            }) catch continue;
        }
    }
    editor_selection.sortHits(hits.items);

    if (hits.items.len == 0) {
        if (pickMarkerObject(state, local_x, local_y, vp_w, vp_h)) return;
        state.selected_object = null;
        clearObjectMultiSelection(state);
        clearMeshSelection(state);
        clearShapeIntentSelection(state);
        state.selection_cycle_index = 0;
        project_editor_state.setStatus(state, "Selection cleared");
        return;
    }

    const result = editor_selection.nextHitForScope(hits.items, .object, state.selection_cycle_index) orelse return;
    selectObjectById(state, result.hit.target.object, result.cycle, "Object selected");
}

pub fn updateHover(state: *ProjectEditorState, local_x: f32, local_y: f32, vp_w: f32, vp_h: f32) void {
    state.hovered_object = null;
    state.hovered_selection_scope = state.selection_scope;
    state.hovered_shape_source = false;
    state.hovered_shape_operation = false;
    if (state.selection_scope == .source or state.selection_scope == .operation) {
        if (hasActiveShapeIntent(state)) {
            state.hovered_shape_source = state.selection_scope == .source;
            state.hovered_shape_operation = state.selection_scope == .operation;
        }
        return;
    }
    const scope: editor_selection.Scope = if (state.selection_scope == .marker) .marker else .object;
    const hit = if (scope == .marker)
        nearestMarkerHit(state, local_x, local_y, vp_w, vp_h)
    else
        nearestObjectHit(state, local_x, local_y, vp_w, vp_h) orelse nearestMarkerHit(state, local_x, local_y, vp_w, vp_h);
    const resolved = hit orelse return;
    const object_id = switch (resolved.target) {
        .object => |id| id,
        .marker => |id| id,
        else => return,
    };
    state.hovered_object = objectIndexById(state, object_id);
    state.hovered_selection_scope = resolved.scope;
}

pub fn clearHover(state: *ProjectEditorState) void {
    state.hovered_object = null;
    state.hovered_shape_source = false;
    state.hovered_shape_operation = false;
}

pub fn dragBoxSelect(state: *ProjectEditorState, start: editor_math.Vec2, end: editor_math.Vec2, vp_w: f32, vp_h: f32) void {
    if (state.selection_scope == .source or state.selection_scope == .operation) {
        _ = selectShapeIntent(state, state.selection_scope);
        return;
    }

    if (state.selection_scope == .face or state.selection_scope == .edge or state.selection_scope == .point) {
        dragBoxSelectMeshElement(state, start, end, vp_w, vp_h);
        return;
    }

    const scope: editor_selection.Scope = if (state.selection_scope == .marker) .marker else .object;
    var hits: std.ArrayList(editor_selection.Hit) = .empty;
    defer hits.deinit(state.allocator);
    appendObjectScreenHits(state, &hits, scope, vp_w, vp_h) catch {
        project_editor_state.setStatus(state, "Box selection failed");
        return;
    };

    var selected: std.ArrayList(editor_selection.Hit) = .empty;
    defer selected.deinit(state.allocator);
    editor_selection.appendDragBoxHits(state.allocator, &selected, hits.items, scope, editor_selection.ScreenRect.fromDrag(start, end)) catch {
        project_editor_state.setStatus(state, "Box selection failed");
        return;
    };

    if (selected.items.len == 0) {
        state.selected_object = null;
        clearObjectMultiSelection(state);
        clearMeshSelection(state);
        clearShapeIntentSelection(state);
        state.selection_cycle_index = 0;
        project_editor_state.setStatus(state, "Box selection empty");
        return;
    }

    const hit = selected.items[0];
    const object_id = switch (hit.target) {
        .object => |id| id,
        .marker => |id| id,
        else => return,
    };
    const idx = objectIndexById(state, object_id) orelse return;
    state.selected_object = idx;
    replaceObjectMultiSelectionWithHits(state, selected.items);
    clearMeshSelection(state);
    clearShapeIntentSelection(state);
    state.selection_cycle_index = 0;

    var buf: [128]u8 = undefined;
    if (scope == .marker and state.objects.items[idx].marker != null) {
        const marker = state.objects.items[idx].marker.?;
        project_editor_state.setStatus(state, std.fmt.bufPrint(&buf, "Box selected {s} marker ({d} hit{s})", .{ marker.kind.label(), selected.items.len, if (selected.items.len == 1) "" else "s" }) catch "Box selected marker");
    } else {
        project_editor_state.setStatus(state, std.fmt.bufPrint(&buf, "Box selected object ({d} hit{s})", .{ selected.items.len, if (selected.items.len == 1) "" else "s" }) catch "Box selected object");
    }
}

fn dragBoxSelectMeshElement(state: *ProjectEditorState, start: editor_math.Vec2, end: editor_math.Vec2, vp_w: f32, vp_h: f32) void {
    const obj_idx = state.selected_object orelse {
        project_editor_state.setStatus(state, "Box selection needs a selected object");
        return;
    };
    if (obj_idx >= state.objects.items.len) {
        state.selected_object = null;
        project_editor_state.setStatus(state, "Box selection needs a selected object");
        return;
    }
    const obj = &state.objects.items[obj_idx];
    if (!project_editor_state.objectVisible(state, obj)) {
        project_editor_state.setStatus(state, "Box selection object hidden");
        return;
    }

    var hits: std.ArrayList(editor_selection.Hit) = .empty;
    defer hits.deinit(state.allocator);
    appendMeshScreenHits(state, &hits, obj, state.selection_scope, vp_w, vp_h) catch {
        project_editor_state.setStatus(state, "Box selection failed");
        return;
    };

    var selected: std.ArrayList(editor_selection.Hit) = .empty;
    defer selected.deinit(state.allocator);
    editor_selection.appendDragBoxHits(state.allocator, &selected, hits.items, state.selection_scope, editor_selection.ScreenRect.fromDrag(start, end)) catch {
        project_editor_state.setStatus(state, "Box selection failed");
        return;
    };

    if (selected.items.len == 0) {
        clearMeshSelection(state);
        clearShapeIntentSelection(state);
        state.selection_cycle_index = 0;
        project_editor_state.setStatus(state, "Box selection empty");
        return;
    }

    selectMeshHit(state, selected.items[0], selected.items.len, "Box selected");
}

fn appendMeshScreenHits(
    state: *ProjectEditorState,
    hits: *std.ArrayList(editor_selection.Hit),
    obj: *const SceneObject,
    scope: editor_selection.Scope,
    vp_w: f32,
    vp_h: f32,
) !void {
    switch (scope) {
        .face => try appendFaceScreenHits(state, hits, obj, vp_w, vp_h),
        .edge => try appendEdgeScreenHits(state, hits, obj, vp_w, vp_h),
        .point => try appendPointScreenHits(state, hits, obj, vp_w, vp_h),
        else => {},
    }
    editor_selection.sortHits(hits.items);
}

fn appendFaceScreenHits(
    state: *ProjectEditorState,
    hits: *std.ArrayList(editor_selection.Hit),
    obj: *const SceneObject,
    vp_w: f32,
    vp_h: f32,
) !void {
    const xf = obj.transform();
    var tri: usize = 0;
    while (tri + 2 < obj.mesh.indices.len) : (tri += 3) {
        const vi0 = obj.mesh.indices[tri];
        const vi1 = obj.mesh.indices[tri + 1];
        const vi2 = obj.mesh.indices[tri + 2];
        if (vi0 >= obj.mesh.vertices.len or vi1 >= obj.mesh.vertices.len or vi2 >= obj.mesh.vertices.len) continue;
        const w0 = xf.transformPoint(obj.mesh.vertices[vi0].position);
        const w1 = xf.transformPoint(obj.mesh.vertices[vi1].position);
        const w2 = xf.transformPoint(obj.mesh.vertices[vi2].position);
        const world: editor_math.Vec3 = .{
            .x = (w0.x + w1.x + w2.x) / 3.0,
            .y = (w0.y + w1.y + w2.y) / 3.0,
            .z = (w0.z + w1.z + w2.z) / 3.0,
        };
        const screen = project_editor_state.projectViewportPoint(state, world, vp_w, vp_h) orelse continue;
        try hits.append(state.allocator, .{
            .scope = .face,
            .target = .{ .face = .{ .object_id = obj.id, .face_index = tri } },
            .screen_distance_sq = 0,
            .depth = worldDepth(state, world),
            .screen = screen,
            .world = world,
        });
    }
}

fn appendEdgeScreenHits(
    state: *ProjectEditorState,
    hits: *std.ArrayList(editor_selection.Hit),
    obj: *const SceneObject,
    vp_w: f32,
    vp_h: f32,
) !void {
    const xf = obj.transform();
    var tri: usize = 0;
    while (tri + 2 < obj.mesh.indices.len) : (tri += 3) {
        const edges = [_][2]u32{
            .{ obj.mesh.indices[tri], obj.mesh.indices[tri + 1] },
            .{ obj.mesh.indices[tri + 1], obj.mesh.indices[tri + 2] },
            .{ obj.mesh.indices[tri + 2], obj.mesh.indices[tri] },
        };
        for (edges) |edge| {
            if (edge[0] >= obj.mesh.vertices.len or edge[1] >= obj.mesh.vertices.len) continue;
            const p0 = xf.transformPoint(obj.mesh.vertices[edge[0]].position);
            const p1 = xf.transformPoint(obj.mesh.vertices[edge[1]].position);
            const s0 = project_editor_state.projectViewportPoint(state, p0, vp_w, vp_h) orelse continue;
            const s1 = project_editor_state.projectViewportPoint(state, p1, vp_w, vp_h) orelse continue;
            try appendUniqueEdgeHit(state, hits, obj.id, edge, 0, @min(worldDepth(state, p0), worldDepth(state, p1)), midpoint2(s0, s1), midpoint3(p0, p1));
        }
    }
}

fn appendPointScreenHits(
    state: *ProjectEditorState,
    hits: *std.ArrayList(editor_selection.Hit),
    obj: *const SceneObject,
    vp_w: f32,
    vp_h: f32,
) !void {
    const xf = obj.transform();
    for (obj.mesh.vertices, 0..) |vert, vi| {
        const world = xf.transformPoint(vert.position);
        const screen = project_editor_state.projectViewportPoint(state, world, vp_w, vp_h) orelse continue;
        try hits.append(state.allocator, .{
            .scope = .point,
            .target = .{ .point = .{ .object_id = obj.id, .index = @intCast(vi) } },
            .screen_distance_sq = 0,
            .depth = worldDepth(state, world),
            .screen = screen,
            .world = world,
        });
    }
}

fn selectMeshHit(state: *ProjectEditorState, hit: editor_selection.Hit, count: usize, prefix: []const u8) void {
    clearShapeIntentSelection(state);
    state.selection_cycle_index = 0;
    var buf: [96]u8 = undefined;
    switch (hit.target) {
        .face => |face| {
            state.selected_face = face.face_index;
            state.selected_vertex = null;
            state.selected_edge = null;
            project_editor_state.setStatus(state, std.fmt.bufPrint(&buf, "{s} face ({d} hit{s})", .{ prefix, count, if (count == 1) "" else "s" }) catch "Face selected");
        },
        .edge => |edge| {
            state.selected_edge = .{ edge.a, edge.b };
            state.selected_vertex = null;
            state.selected_face = null;
            project_editor_state.setStatus(state, std.fmt.bufPrint(&buf, "{s} edge ({d} hit{s})", .{ prefix, count, if (count == 1) "" else "s" }) catch "Edge selected");
        },
        .point => |point| {
            state.selected_vertex = point.index;
            state.selected_edge = null;
            state.selected_face = null;
            project_editor_state.setStatus(state, std.fmt.bufPrint(&buf, "{s} point ({d} hit{s})", .{ prefix, count, if (count == 1) "" else "s" }) catch "Point selected");
        },
        else => {},
    }
}

pub fn pickMeshHit(state: *ProjectEditorState, local_x: f32, local_y: f32, vp_w: f32, vp_h: f32) void {
    if (state.selection_scope == .object or state.selection_scope == .marker or state.selection_scope == .source or state.selection_scope == .operation) {
        pickObject(state, local_x, local_y, vp_w, vp_h);
        return;
    }

    const obj_idx = state.selected_object orelse {
        pickObject(state, local_x, local_y, vp_w, vp_h);
        return;
    };
    const obj = &state.objects.items[obj_idx];
    if (!project_editor_state.objectVisible(state, obj)) {
        state.selected_object = null;
        pickObject(state, local_x, local_y, vp_w, vp_h);
        return;
    }
    const ray = project_editor_state.rayFromViewport(state, local_x, local_y, vp_w, vp_h);

    if (state.edit_tool == .vertex) {
        if (pickPoint(state, obj, local_x, local_y, vp_w, vp_h)) return;
    } else if (state.edit_tool == .edge) {
        if (pickEdge(state, obj, local_x, local_y, vp_w, vp_h)) return;
    } else if (state.edit_tool != .face and state.edit_tool != .extrude and state.edit_tool != .inset) {
        project_editor_state.setStatus(state, "Pick a mesh element");
        return;
    }

    const world_xf = scene_hierarchy.objectWorldTransform(state.objects.items, obj_idx);
    if (!pickFace(state, obj, world_xf, ray, local_x, local_y)) {
        state.selected_face = null;
        state.selected_vertex = null;
        state.selected_edge = null;
        clearShapeIntentSelection(state);
        project_editor_state.setStatus(state, "Selection cleared");
    }
}

pub fn pickVertex(state: *ProjectEditorState, local_x: f32, local_y: f32, vp_w: f32, vp_h: f32) void {
    pickMeshHit(state, local_x, local_y, vp_w, vp_h);
}

fn pickFace(
    state: *ProjectEditorState,
    obj: *const SceneObject,
    world_xf: editor_math.Mat4,
    ray: editor_math.Ray,
    local_x: f32,
    local_y: f32,
) bool {
    var hits: std.ArrayList(editor_selection.Hit) = .empty;
    defer hits.deinit(state.allocator);
    appendFaceHits(state, &hits, obj, world_xf, ray, local_x, local_y) catch return false;
    if (hits.items.len == 0) return false;
    editor_selection.sortHits(hits.items);
    const result = editor_selection.nextHitForScope(hits.items, .face, state.selection_cycle_index) orelse return false;
    state.selected_face = result.hit.target.face.face_index;
    state.selected_vertex = null;
    state.selected_edge = null;
    clearShapeIntentSelection(state);
    state.selection_cycle_index = result.cycle;
    if (state.edit_tool == .extrude) {
        scene_mesh_edit.extrudeSelectedFace(state) catch project_editor_state.setStatus(state, "Extrude failed");
    } else if (state.edit_tool == .inset) {
        scene_mesh_edit.insetSelectedFace(state) catch project_editor_state.setStatus(state, "Inset failed");
    } else {
        var buf: [96]u8 = undefined;
        project_editor_state.setStatus(state, std.fmt.bufPrint(&buf, "Face selected ({d} hit{s})", .{ hits.items.len, if (hits.items.len == 1) "" else "s" }) catch "Face selected");
    }
    return true;
}

fn appendFaceHits(
    state: *ProjectEditorState,
    hits: *std.ArrayList(editor_selection.Hit),
    obj: *const SceneObject,
    world_xf: editor_math.Mat4,
    ray: editor_math.Ray,
    local_x: f32,
    local_y: f32,
) !void {
    const mesh = obj.mesh;
    var tri: usize = 0;
    while (tri + 2 < mesh.indices.len) : (tri += 3) {
        const vi0 = mesh.indices[tri];
        const vi1 = mesh.indices[tri + 1];
        const vi2 = mesh.indices[tri + 2];
        const w0 = world_xf.transformPoint(mesh.vertices[vi0].position);
        const w1 = world_xf.transformPoint(mesh.vertices[vi1].position);
        const w2 = world_xf.transformPoint(mesh.vertices[vi2].position);
        const uv0 = mesh.vertices[vi0].uv;
        const uv1 = mesh.vertices[vi1].uv;
        const uv2 = mesh.vertices[vi2].uv;
        const hit = intersectRayTriangle(ray.origin, ray.dir, w0, w1, w2, uv0, uv1, uv2) orelse continue;
        const world = editor_math.Vec3.add(ray.origin, editor_math.Vec3.scale(ray.dir, hit.t));
        try hits.append(state.allocator, .{
            .scope = .face,
            .target = .{ .face = .{ .object_id = obj.id, .face_index = tri } },
            .screen_distance_sq = 0,
            .depth = hit.t,
            .screen = .{ .x = local_x, .y = local_y },
            .world = world,
        });
    }
}

fn pickPoint(state: *ProjectEditorState, obj: *const SceneObject, local_x: f32, local_y: f32, vp_w: f32, vp_h: f32) bool {
    var hits: std.ArrayList(editor_selection.Hit) = .empty;
    defer hits.deinit(state.allocator);
    const xf = obj.transform();
    for (obj.mesh.vertices, 0..) |vert, vi| {
        const world = xf.transformPoint(vert.position);
        const screen = project_editor_state.projectViewportPoint(state, world, vp_w, vp_h) orelse continue;
        const dx = screen.x - local_x;
        const dy = screen.y - local_y;
        const dist_sq = dx * dx + dy * dy;
        if (dist_sq > 12.0 * 12.0) continue;
        hits.append(state.allocator, .{
            .scope = .point,
            .target = .{ .point = .{ .object_id = obj.id, .index = @intCast(vi) } },
            .screen_distance_sq = dist_sq,
            .depth = worldDepth(state, world),
            .screen = screen,
            .world = world,
        }) catch continue;
    }
    if (hits.items.len == 0) return false;
    editor_selection.sortHits(hits.items);
    const result = editor_selection.nextHitForScope(hits.items, .point, state.selection_cycle_index) orelse return false;
    state.selected_vertex = result.hit.target.point.index;
    state.selected_edge = null;
    state.selected_face = null;
    clearShapeIntentSelection(state);
    state.selection_cycle_index = result.cycle;
    var buf: [96]u8 = undefined;
    project_editor_state.setStatus(state, std.fmt.bufPrint(&buf, "Point selected ({d} hit{s})", .{ hits.items.len, if (hits.items.len == 1) "" else "s" }) catch "Point selected");
    return true;
}

fn pickEdge(state: *ProjectEditorState, obj: *const SceneObject, local_x: f32, local_y: f32, vp_w: f32, vp_h: f32) bool {
    var hits: std.ArrayList(editor_selection.Hit) = .empty;
    defer hits.deinit(state.allocator);
    const xf = obj.transform();
    var tri: usize = 0;
    while (tri + 2 < obj.mesh.indices.len) : (tri += 3) {
        const edges = [_][2]u32{
            .{ obj.mesh.indices[tri], obj.mesh.indices[tri + 1] },
            .{ obj.mesh.indices[tri + 1], obj.mesh.indices[tri + 2] },
            .{ obj.mesh.indices[tri + 2], obj.mesh.indices[tri] },
        };
        for (edges) |edge| {
            const p0 = xf.transformPoint(obj.mesh.vertices[edge[0]].position);
            const p1 = xf.transformPoint(obj.mesh.vertices[edge[1]].position);
            const s0 = project_editor_state.projectViewportPoint(state, p0, vp_w, vp_h) orelse continue;
            const s1 = project_editor_state.projectViewportPoint(state, p1, vp_w, vp_h) orelse continue;
            const dist = pointToSegmentDist(local_x, local_y, s0.x, s0.y, s1.x, s1.y);
            if (dist > 10.0) continue;
            appendUniqueEdgeHit(state, &hits, obj.id, edge, dist * dist, @min(worldDepth(state, p0), worldDepth(state, p1)), midpoint2(s0, s1), midpoint3(p0, p1)) catch continue;
        }
    }
    if (hits.items.len == 0) return false;
    editor_selection.sortHits(hits.items);
    const result = editor_selection.nextHitForScope(hits.items, .edge, state.selection_cycle_index) orelse return false;
    const edge = result.hit.target.edge;
    state.selected_edge = .{ edge.a, edge.b };
    state.selected_vertex = null;
    state.selected_face = null;
    clearShapeIntentSelection(state);
    state.selection_cycle_index = result.cycle;
    var buf: [96]u8 = undefined;
    project_editor_state.setStatus(state, std.fmt.bufPrint(&buf, "Edge selected ({d} hit{s})", .{ hits.items.len, if (hits.items.len == 1) "" else "s" }) catch "Edge selected");
    return true;
}

fn appendUniqueEdgeHit(
    state: *ProjectEditorState,
    hits: *std.ArrayList(editor_selection.Hit),
    object_id: u64,
    edge: [2]u32,
    dist_sq: f32,
    depth: f32,
    screen: editor_math.Vec2,
    world: editor_math.Vec3,
) !void {
    const a = @min(edge[0], edge[1]);
    const b = @max(edge[0], edge[1]);
    for (hits.items) |hit| {
        if (hit.scope != .edge) continue;
        const existing = hit.target.edge;
        const ea = @min(existing.a, existing.b);
        const eb = @max(existing.a, existing.b);
        if (existing.object_id == object_id and ea == a and eb == b) return;
    }
    try hits.append(state.allocator, .{
        .scope = .edge,
        .target = .{ .edge = .{ .object_id = object_id, .a = edge[0], .b = edge[1] } },
        .screen_distance_sq = dist_sq,
        .depth = depth,
        .screen = screen,
        .world = world,
    });
}

fn midpoint2(a: editor_math.Vec2, b: editor_math.Vec2) editor_math.Vec2 {
    return .{
        .x = (a.x + b.x) * 0.5,
        .y = (a.y + b.y) * 0.5,
    };
}

fn midpoint3(a: editor_math.Vec3, b: editor_math.Vec3) editor_math.Vec3 {
    return .{
        .x = (a.x + b.x) * 0.5,
        .y = (a.y + b.y) * 0.5,
        .z = (a.z + b.z) * 0.5,
    };
}

fn pickMarkerObject(state: *ProjectEditorState, local_x: f32, local_y: f32, vp_w: f32, vp_h: f32) bool {
    var hits = markerHitsAt(state, local_x, local_y, vp_w, vp_h) catch return false;
    defer hits.deinit(state.allocator);
    if (hits.items.len == 0) return false;
    editor_selection.sortHits(hits.items);
    const result = editor_selection.nextHitForScope(hits.items, .marker, state.selection_cycle_index) orelse return false;
    const idx = objectIndexById(state, result.hit.target.marker) orelse return false;
    state.selected_object = idx;
    setSingleObjectSelection(state, state.objects.items[idx].id);
    clearMeshSelection(state);
    clearShapeIntentSelection(state);
    state.selection_cycle_index = result.cycle;
    var buf: [96]u8 = undefined;
    const marker = state.objects.items[idx].marker.?;
    project_editor_state.setStatus(state, std.fmt.bufPrint(&buf, "{s} marker selected", .{marker.kind.label()}) catch "Marker selected");
    return true;
}

fn nearestObjectHit(state: *ProjectEditorState, local_x: f32, local_y: f32, vp_w: f32, vp_h: f32) ?editor_selection.Hit {
    const ray = project_editor_state.rayFromViewport(state, local_x, local_y, vp_w, vp_h);
    var hits: std.ArrayList(editor_selection.Hit) = .empty;
    defer hits.deinit(state.allocator);
    for (state.objects.items, 0..) |*obj, idx| {
        if (obj.marker != null) continue;
        if (!project_editor_state.objectVisible(state, obj)) continue;
        const world_xf = scene_hierarchy.objectWorldTransform(state.objects.items, idx);
        const hit = raycastMesh(ray.origin, ray.dir, obj, world_xf) orelse continue;
        if (hit.t <= 0) continue;
        hits.append(state.allocator, .{
            .scope = .object,
            .target = .{ .object = obj.id },
            .screen_distance_sq = 0,
            .depth = hit.t,
            .screen = .{ .x = local_x, .y = local_y },
            .world = editor_math.Vec3.add(ray.origin, editor_math.Vec3.scale(ray.dir, hit.t)),
        }) catch continue;
    }
    if (hits.items.len == 0) return null;
    editor_selection.sortHits(hits.items);
    return hits.items[0];
}

fn nearestMarkerHit(state: *ProjectEditorState, local_x: f32, local_y: f32, vp_w: f32, vp_h: f32) ?editor_selection.Hit {
    var hits = markerHitsAt(state, local_x, local_y, vp_w, vp_h) catch return null;
    defer hits.deinit(state.allocator);
    if (hits.items.len == 0) return null;
    editor_selection.sortHits(hits.items);
    return hits.items[0];
}

fn markerHitsAt(state: *ProjectEditorState, local_x: f32, local_y: f32, vp_w: f32, vp_h: f32) !std.ArrayList(editor_selection.Hit) {
    var hits: std.ArrayList(editor_selection.Hit) = .empty;
    errdefer hits.deinit(state.allocator);
    for (state.objects.items, 0..) |*obj, idx| {
        if (obj.marker == null) continue;
        if (!project_editor_state.objectVisible(state, obj)) continue;
        const world = scene_hierarchy.objectWorldTransform(state.objects.items, idx).transformPoint(.{ .x = 0, .y = 0, .z = 0 });
        const screen = project_editor_state.projectViewportPoint(state, world, vp_w, vp_h) orelse continue;
        const dx = screen.x - local_x;
        const dy = screen.y - local_y;
        const dist_sq = dx * dx + dy * dy;
        if (dist_sq > marker_hover_radius * marker_hover_radius) continue;
        try hits.append(state.allocator, .{
            .scope = .marker,
            .target = .{ .marker = obj.id },
            .screen_distance_sq = dist_sq,
            .depth = worldDepth(state, world),
            .screen = screen,
            .world = world,
        });
    }
    return hits;
}

fn appendObjectScreenHits(state: *ProjectEditorState, hits: *std.ArrayList(editor_selection.Hit), scope: editor_selection.Scope, vp_w: f32, vp_h: f32) !void {
    for (state.objects.items, 0..) |*obj, idx| {
        if (!project_editor_state.objectVisible(state, obj)) continue;
        if (!obj.enabled) continue;
        if (scope == .marker) {
            if (obj.marker == null) continue;
        } else if (obj.marker != null) {
            continue;
        }
        const world = scene_hierarchy.objectWorldPosition(state.objects.items, idx);
        const screen = project_editor_state.projectViewportPoint(state, world, vp_w, vp_h) orelse continue;
        try hits.append(state.allocator, .{
            .scope = scope,
            .target = switch (scope) {
                .marker => .{ .marker = obj.id },
                else => .{ .object = obj.id },
            },
            .screen_distance_sq = 0,
            .depth = worldDepth(state, world),
            .screen = screen,
            .world = world,
        });
    }
    editor_selection.sortHits(hits.items);
}

fn selectObjectById(state: *ProjectEditorState, id: u64, cycle: usize, status: []const u8) void {
    const idx = objectIndexById(state, id) orelse return;
    state.selected_object = idx;
    setSingleObjectSelection(state, id);
    clearMeshSelection(state);
    clearShapeIntentSelection(state);
    state.selection_cycle_index = cycle;
    project_editor_state.setStatus(state, status);
}

fn objectIndexById(state: *const ProjectEditorState, id: u64) ?usize {
    for (state.objects.items, 0..) |obj, idx| {
        if (obj.id == id) return idx;
    }
    return null;
}

fn clearMeshSelection(state: *ProjectEditorState) void {
    state.selected_vertex = null;
    state.selected_edge = null;
    state.selected_face = null;
}

fn clearObjectMultiSelection(state: *ProjectEditorState) void {
    state.selected_object_ids.clearRetainingCapacity();
}

fn setSingleObjectSelection(state: *ProjectEditorState, object_id: u64) void {
    state.selected_object_ids.clearRetainingCapacity();
    state.selected_object_ids.append(state.allocator, object_id) catch {
        project_editor_state.setStatus(state, "Selection list update failed");
    };
}

fn replaceObjectMultiSelectionWithHits(state: *ProjectEditorState, hits: []const editor_selection.Hit) void {
    state.selected_object_ids.clearRetainingCapacity();
    for (hits) |hit| {
        const object_id = switch (hit.target) {
            .object => |id| id,
            .marker => |id| id,
            else => continue,
        };
        if (objectIdAlreadySelected(state, object_id)) continue;
        state.selected_object_ids.append(state.allocator, object_id) catch {
            project_editor_state.setStatus(state, "Selection list update failed");
            return;
        };
    }
}

fn objectIdAlreadySelected(state: *const ProjectEditorState, object_id: u64) bool {
    for (state.selected_object_ids.items) |selected_id| {
        if (selected_id == object_id) return true;
    }
    return false;
}

fn clearShapeIntentSelection(state: *ProjectEditorState) void {
    state.selected_shape_source = false;
    state.selected_shape_operation = false;
}

fn selectShapeIntent(state: *ProjectEditorState, scope: editor_selection.Scope) bool {
    if (!hasActiveShapeIntent(state)) {
        project_editor_state.setStatus(state, "No active shape source");
        return true;
    }
    state.selected_shape_source = scope == .source;
    state.selected_shape_operation = scope == .operation;
    state.selection_cycle_index = 0;
    state.selected_vertex = null;
    state.selected_edge = null;
    state.selected_face = null;

    const source = currentShapeSource(state) orelse {
        project_editor_state.setStatus(state, "No active shape source");
        return true;
    };
    const operation = currentShapeOperation(state);
    if (scope == .source) {
        source.validate() catch |err| {
            var buf: [96]u8 = undefined;
            project_editor_state.setStatus(state, std.fmt.bufPrint(&buf, "Shape source invalid: {s}", .{@errorName(err)}) catch "Shape source invalid");
            return true;
        };
        project_editor_state.setStatus(state, "Shape source selected");
        return true;
    }
    operation.validateForSource(source) catch |err| {
        var buf: [104]u8 = undefined;
        project_editor_state.setStatus(state, std.fmt.bufPrint(&buf, "Shape operation invalid: {s}", .{@errorName(err)}) catch "Shape operation invalid");
        return true;
    };
    project_editor_state.setStatus(state, "Shape operation selected");
    return true;
}

fn hasActiveShapeIntent(state: *const ProjectEditorState) bool {
    return state.mode == .prop_creation and state.prop_tool == .edit and state.prop_sketch_mode != .none and state.prop_sketch_points.items.len > 0;
}

fn currentShapeSource(state: *const ProjectEditorState) ?shape_source.Source {
    if (state.prop_sketch_mode == .none) return null;
    return .{
        .kind = switch (state.prop_sketch_mode) {
            .face => .closed_face,
            .curve => .open_profile,
            .path => .path,
            .none => .primitive_seed,
        },
        .points = state.prop_sketch_points.items,
    };
}

fn currentShapeOperation(state: *const ProjectEditorState) shape_operation.Operation {
    return .{
        .kind = switch (state.prop_sketch_mode) {
            .face => .solidify,
            .curve => .revolve,
            .path => .extrude,
            .none => .extrude,
        },
        .segments = state.prop_sketch_segments,
        .amount = state.prop_sketch_amount,
    };
}

fn worldDepth(state: *const ProjectEditorState, world: editor_math.Vec3) f32 {
    const eye = state.camera.eye();
    const delta = editor_math.Vec3.sub(world, eye);
    return @sqrt(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z);
}

test "marker hover resolves object without changing selection" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .viewport_screen_rect = .{ .x = 0, .y = 0, .w = 320, .h = 200 },
        .selection_scope = .marker,
    };
    var marker = try shared.scene_marker.defaultForKind(std.testing.allocator, .spawn_point);
    defer marker.deinit(std.testing.allocator);
    try state.objects.append(std.testing.allocator, .{
        .id = 77,
        .name = try std.testing.allocator.dupe(u8, "Hover Spawn"),
        .mesh = .{ .vertices = &.{}, .indices = &.{} },
        .position = .{ .x = 0, .y = 0.5, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = &.{},
        .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .object_kind = .marker,
        .marker = try shared.scene_marker.Marker.duplicate(std.testing.allocator, marker),
    });
    defer {
        for (state.objects.items) |*obj| obj.deinit(std.testing.allocator);
        state.objects.deinit(std.testing.allocator);
    }

    const screen = project_editor_state.projectViewportPoint(&state, state.objects.items[0].position, state.viewport_screen_rect.w, state.viewport_screen_rect.h).?;
    updateHover(&state, screen.x, screen.y, state.viewport_screen_rect.w, state.viewport_screen_rect.h);

    try std.testing.expectEqual(@as(?usize, 0), state.hovered_object);
    try std.testing.expectEqual(editor_selection.Scope.marker, state.hovered_selection_scope);
    try std.testing.expectEqual(@as(?usize, null), state.selected_object);
}

test "shape source scope selects active prop sketch source" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .mode = .prop_creation,
        .prop_tool = .edit,
        .prop_sketch_mode = .face,
        .selection_scope = .source,
    };
    defer state.prop_sketch_points.deinit(std.testing.allocator);
    try state.prop_sketch_points.append(std.testing.allocator, .{ .x = 0, .y = 0, .z = 0 });
    try state.prop_sketch_points.append(std.testing.allocator, .{ .x = 1, .y = 0, .z = 0 });
    try state.prop_sketch_points.append(std.testing.allocator, .{ .x = 0, .y = 0, .z = 1 });

    pickObject(&state, 0, 0, 320, 200);

    try std.testing.expect(state.selected_shape_source);
    try std.testing.expect(!state.selected_shape_operation);
    try std.testing.expectEqual(@as(?usize, null), state.selected_object);
}

test "shape operation scope stays selected when sketch is invalid" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .mode = .prop_creation,
        .prop_tool = .edit,
        .prop_sketch_mode = .face,
        .selection_scope = .operation,
    };
    defer state.prop_sketch_points.deinit(std.testing.allocator);
    try state.prop_sketch_points.append(std.testing.allocator, .{ .x = 0, .y = 0, .z = 0 });
    try state.prop_sketch_points.append(std.testing.allocator, .{ .x = 1, .y = 0, .z = 0 });

    pickObject(&state, 0, 0, 320, 200);

    try std.testing.expect(!state.selected_shape_source);
    try std.testing.expect(state.selected_shape_operation);
    try std.testing.expect(std.mem.indexOf(u8, state.status_buf[0..state.status_len], "invalid") != null);
}

test "edge hit collector collapses duplicate triangle edges" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
    };
    var hits: std.ArrayList(editor_selection.Hit) = .empty;
    defer hits.deinit(std.testing.allocator);

    try appendUniqueEdgeHit(&state, &hits, 10, .{ 2, 1 }, 4, 5, .{ .x = 1, .y = 2 }, .{ .x = 0, .y = 0, .z = 0 });
    try appendUniqueEdgeHit(&state, &hits, 10, .{ 1, 2 }, 1, 2, .{ .x = 3, .y = 4 }, .{ .x = 1, .y = 0, .z = 0 });
    try appendUniqueEdgeHit(&state, &hits, 11, .{ 1, 2 }, 1, 2, .{ .x = 3, .y = 4 }, .{ .x = 1, .y = 0, .z = 0 });

    try std.testing.expectEqual(@as(usize, 2), hits.items.len);
    try std.testing.expectEqual(@as(u64, 10), hits.items[0].target.edge.object_id);
    try std.testing.expectEqual(@as(u32, 2), hits.items[0].target.edge.a);
    try std.testing.expectEqual(@as(u32, 1), hits.items[0].target.edge.b);
}

test "face hit collector gathers overlapping triangles front to back" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
    };
    var vertices = [_]shared.geometry.Vertex{
        testVertex(.{ .x = -1, .y = -1, .z = 1 }),
        testVertex(.{ .x = 1, .y = -1, .z = 1 }),
        testVertex(.{ .x = 0, .y = 1, .z = 1 }),
        testVertex(.{ .x = -1, .y = -1, .z = 2 }),
        testVertex(.{ .x = 1, .y = -1, .z = 2 }),
        testVertex(.{ .x = 0, .y = 1, .z = 2 }),
    };
    var indices = [_]u32{ 0, 1, 2, 3, 4, 5 };
    const obj = SceneObject{
        .id = 91,
        .name = @constCast("Face Stack"),
        .mesh = .{ .vertices = vertices[0..], .indices = indices[0..] },
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = @constCast(""),
        .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    };
    var hits: std.ArrayList(editor_selection.Hit) = .empty;
    defer hits.deinit(std.testing.allocator);
    try appendFaceHits(&state, &hits, &obj, editor_math.Mat4.identity(), .{
        .origin = .{ .x = 0, .y = 0, .z = 0 },
        .dir = .{ .x = 0, .y = 0, .z = 1 },
    }, 20, 30);
    editor_selection.sortHits(hits.items);

    try std.testing.expectEqual(@as(usize, 2), hits.items.len);
    try std.testing.expectEqual(@as(usize, 0), hits.items[0].target.face.face_index);
    try std.testing.expectEqual(@as(usize, 3), hits.items[1].target.face.face_index);
}

test "point picking cycles overlapping vertices" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .viewport_screen_rect = .{ .x = 0, .y = 0, .w = 320, .h = 200 },
        .mode = .prop_creation,
        .prop_tool = .edit,
        .edit_tool = .vertex,
        .selection_scope = .point,
    };
    var vertices = try std.testing.allocator.alloc(shared.geometry.Vertex, 2);
    vertices[0] = testVertex(.{ .x = 0, .y = 0.5, .z = 0 });
    vertices[1] = testVertex(.{ .x = 0.01, .y = 0.5, .z = 0 });
    const indices = try std.testing.allocator.alloc(u32, 0);
    const texture = try std.testing.allocator.alloc(u8, 0);
    try state.objects.append(std.testing.allocator, .{
        .id = 41,
        .name = try std.testing.allocator.dupe(u8, "Overlapping Points"),
        .mesh = .{ .vertices = vertices, .indices = indices },
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = texture,
        .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .editor_only = true,
    });
    defer {
        for (state.objects.items) |*obj| obj.deinit(std.testing.allocator);
        state.objects.deinit(std.testing.allocator);
    }
    state.selected_object = 0;

    const screen = project_editor_state.projectViewportPoint(&state, vertices[0].position, state.viewport_screen_rect.w, state.viewport_screen_rect.h).?;
    pickMeshHit(&state, screen.x, screen.y, state.viewport_screen_rect.w, state.viewport_screen_rect.h);
    const first = state.selected_vertex;
    pickMeshHit(&state, screen.x, screen.y, state.viewport_screen_rect.w, state.viewport_screen_rect.h);
    const second = state.selected_vertex;

    try std.testing.expect(first != null);
    try std.testing.expect(second != null);
    try std.testing.expect(first.? != second.?);
}

test "drag box selects point in active point scope" {
    var state = try testMeshSelectionState(.point);
    defer deinitTestMeshSelectionState(&state);

    const target_world = state.objects.items[0].mesh.vertices[1].position;
    const screen = project_editor_state.projectViewportPoint(&state, target_world, state.viewport_screen_rect.w, state.viewport_screen_rect.h).?;
    dragBoxSelect(&state, .{ .x = screen.x - 4, .y = screen.y - 4 }, .{ .x = screen.x + 4, .y = screen.y + 4 }, state.viewport_screen_rect.w, state.viewport_screen_rect.h);

    try std.testing.expectEqual(@as(?u32, 1), state.selected_vertex);
    try std.testing.expectEqual(@as(?[2]u32, null), state.selected_edge);
    try std.testing.expectEqual(@as(?usize, null), state.selected_face);
}

test "drag box selects edge in active edge scope" {
    var state = try testMeshSelectionState(.edge);
    defer deinitTestMeshSelectionState(&state);

    const p0 = state.objects.items[0].mesh.vertices[0].position;
    const p1 = state.objects.items[0].mesh.vertices[1].position;
    const midpoint = midpoint3(p0, p1);
    const screen = project_editor_state.projectViewportPoint(&state, midpoint, state.viewport_screen_rect.w, state.viewport_screen_rect.h).?;
    dragBoxSelect(&state, .{ .x = screen.x - 6, .y = screen.y - 6 }, .{ .x = screen.x + 6, .y = screen.y + 6 }, state.viewport_screen_rect.w, state.viewport_screen_rect.h);

    try std.testing.expect(state.selected_edge != null);
    try std.testing.expectEqual(@as(?u32, null), state.selected_vertex);
    try std.testing.expectEqual(@as(?usize, null), state.selected_face);
}

test "drag box selects face in active face scope" {
    var state = try testMeshSelectionState(.face);
    defer deinitTestMeshSelectionState(&state);

    const mesh = state.objects.items[0].mesh;
    const w0 = mesh.vertices[mesh.indices[3]].position;
    const w1 = mesh.vertices[mesh.indices[4]].position;
    const w2 = mesh.vertices[mesh.indices[5]].position;
    const centroid: editor_math.Vec3 = .{
        .x = (w0.x + w1.x + w2.x) / 3.0,
        .y = (w0.y + w1.y + w2.y) / 3.0,
        .z = (w0.z + w1.z + w2.z) / 3.0,
    };
    const screen = project_editor_state.projectViewportPoint(&state, centroid, state.viewport_screen_rect.w, state.viewport_screen_rect.h).?;
    dragBoxSelect(&state, .{ .x = screen.x - 8, .y = screen.y - 8 }, .{ .x = screen.x + 8, .y = screen.y + 8 }, state.viewport_screen_rect.w, state.viewport_screen_rect.h);

    try std.testing.expectEqual(@as(?usize, 3), state.selected_face);
    try std.testing.expectEqual(@as(?u32, null), state.selected_vertex);
    try std.testing.expectEqual(@as(?[2]u32, null), state.selected_edge);
}

test "drag box records every selected object while keeping primary selection" {
    var state = try testMeshSelectionState(.object);
    defer deinitTestMeshSelectionState(&state);
    try appendTestObject(&state, 252, "Second Box Select Mesh", .{ .x = 0.25, .y = 0, .z = 0 });

    dragBoxSelect(&state, .{ .x = 0, .y = 0 }, .{ .x = state.viewport_screen_rect.w, .y = state.viewport_screen_rect.h }, state.viewport_screen_rect.w, state.viewport_screen_rect.h);

    try std.testing.expect(state.selected_object != null);
    try std.testing.expectEqual(@as(usize, 2), state.selected_object_ids.items.len);
    try std.testing.expect(testSelectionContains(&state, 151));
    try std.testing.expect(testSelectionContains(&state, 252));
}

fn testMeshSelectionState(scope: editor_selection.Scope) !ProjectEditorState {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .viewport_screen_rect = .{ .x = 0, .y = 0, .w = 360, .h = 240 },
        .mode = .prop_creation,
        .prop_tool = .edit,
        .selection_scope = scope,
    };
    var vertices = try std.testing.allocator.alloc(shared.geometry.Vertex, 6);
    vertices[0] = testVertex(.{ .x = -0.9, .y = 0.5, .z = 0 });
    vertices[1] = testVertex(.{ .x = -0.5, .y = 0.5, .z = 0 });
    vertices[2] = testVertex(.{ .x = -0.7, .y = 0.9, .z = 0 });
    vertices[3] = testVertex(.{ .x = 0.45, .y = 0.5, .z = 0 });
    vertices[4] = testVertex(.{ .x = 0.95, .y = 0.5, .z = 0 });
    vertices[5] = testVertex(.{ .x = 0.7, .y = 0.95, .z = 0 });
    const indices = try std.testing.allocator.dupe(u32, &[_]u32{ 0, 1, 2, 3, 4, 5 });
    const texture = try std.testing.allocator.alloc(u8, 0);
    try state.objects.append(std.testing.allocator, .{
        .id = 151,
        .name = try std.testing.allocator.dupe(u8, "Box Select Mesh"),
        .mesh = .{ .vertices = vertices, .indices = indices },
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = texture,
        .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .editor_only = true,
    });
    state.selected_object = 0;
    return state;
}

fn appendTestObject(state: *ProjectEditorState, id: u64, name: []const u8, position: editor_math.Vec3) !void {
    const texture = try std.testing.allocator.alloc(u8, 0);
    try state.objects.append(std.testing.allocator, .{
        .id = id,
        .name = try std.testing.allocator.dupe(u8, name),
        .mesh = .{ .vertices = try std.testing.allocator.alloc(shared.geometry.Vertex, 0), .indices = try std.testing.allocator.alloc(u32, 0) },
        .position = position,
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = texture,
        .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .editor_only = true,
    });
}

fn testSelectionContains(state: *const ProjectEditorState, id: u64) bool {
    for (state.selected_object_ids.items) |selected_id| {
        if (selected_id == id) return true;
    }
    return false;
}

fn deinitTestMeshSelectionState(state: *ProjectEditorState) void {
    for (state.objects.items) |*obj| obj.deinit(std.testing.allocator);
    state.objects.deinit(std.testing.allocator);
    state.selected_object_ids.deinit(std.testing.allocator);
}

fn testVertex(position: editor_math.Vec3) shared.geometry.Vertex {
    return .{
        .position = position,
        .normal = .{ .x = 0, .y = 1, .z = 0 },
        .uv = .{ .x = 0, .y = 0 },
    };
}
