const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const editor_math = shared.editor_math;
const geometry = shared.geometry;
const scene_blockout = shared.scene_blockout;
const scene_physics = shared.scene_physics;
const shared_color = shared.color;
const scene_object = @import("editor_scene_object.zig");
const editor_raycast = @import("editor_raycast.zig");
const project_editor_edit = @import("project_editor_edit.zig");
const project_editor_state = @import("project_editor_state.zig");
const world_authoring = @import("project_editor_world_authoring.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const TextureSize = scene_object.TextureSize;
const fillCheckerTexture = scene_object.fillCheckerTexture;
const snapValue = editor_raycast.snapValue;
const objectWorldBounds = editor_raycast.objectWorldBounds;
const aabbOverlaps = editor_raycast.aabbOverlaps;
const local_csg = friendly_engine.modules.local_csg;
const static_body = scene_physics.Body{ .kind = .static, .collider = .box, .mass = 0 };

pub fn addBlockoutBox(state: *ProjectEditorState, min_pt: editor_math.Vec3, max_pt: editor_math.Vec3) !void {
    try addBlockoutBoxInternal(state, min_pt, max_pt, true);
}

pub fn addDoorway(state: *ProjectEditorState) !void {
    project_editor_edit.pushUndoSnapshot(state);
    const wall_min: editor_math.Vec3 = .{ .x = 0, .y = 0, .z = 0 };
    const wall_max: editor_math.Vec3 = .{ .x = 6, .y = @max(2.5, state.architecture_door_height + 0.5), .z = 1 };
    try addBlockoutBoxInternal(state, wall_min, wall_max, true);
    const opening_min: editor_math.Vec3 = .{ .x = 2, .y = 0, .z = 0 };
    const opening_max: editor_math.Vec3 = .{ .x = 4, .y = @max(0.25, state.architecture_door_height), .z = 1 };
    try subtractDoorwayBlockoutBox(state, opening_min, opening_max);
    project_editor_state.setStatus(state, "Doorway added");
}

pub fn addStair(state: *ProjectEditorState) !void {
    try addBlockoutRamp(state);
}

pub fn addBlockoutCylinderAt(
    state: *ProjectEditorState,
    min_pt: editor_math.Vec3,
    max_pt: editor_math.Vec3,
    persist: bool,
) !void {
    const width = max_pt.x - min_pt.x;
    const height = @max(max_pt.y - min_pt.y, 0.25);
    const depth = max_pt.z - min_pt.z;
    const radius = @max(@max(width, depth) * 0.5, 0.25);
    const mesh = try geometry.buildPrimitive(state.allocator, .cylinder, .{
        .radius = radius,
        .height = height,
        .segments = 16,
    });
    const tex = try state.allocator.alloc(u8, TextureSize * TextureSize * 4);
    fillCheckerTexture(tex, TextureSize, 150, 170, 185);

    const name = try std.fmt.allocPrint(state.allocator, "Brush {d}", .{state.next_object_id});
    defer state.allocator.free(name);

    try state.objects.append(state.allocator, .{
        .id = state.next_object_id,
        .name = try state.allocator.dupe(u8, name),
        .mesh = mesh,
        .position = .{
            .x = min_pt.x + width * 0.5,
            .y = min_pt.y + height * 0.5,
            .z = min_pt.z + depth * 0.5,
        },
        .rotation = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = tex,
        .base_color = .{ .r = 150, .g = 165, .b = 190, .a = 255 },
        .primitive_kind = .cylinder,
    });
    state.next_object_id += 1;
    state.selected_object = state.objects.items.len - 1;
    state.selected_vertex = null;
    state.selected_edge = null;
    state.selected_face = null;
    state.objects.items[state.selected_object.?].blockout_intent = .{
        .kind = .box_add,
        .min = min_pt,
        .max = max_pt,
    };
    if (persist) {
        try world_authoring.persistAddBlockout(state, min_pt, max_pt);
    }
}

pub fn addBlockoutWedgeAt(
    state: *ProjectEditorState,
    min_pt: editor_math.Vec3,
    max_pt: editor_math.Vec3,
    persist: bool,
) !void {
    const width = max_pt.x - min_pt.x;
    const height = @max(max_pt.y - min_pt.y, 0.25);
    const depth = max_pt.z - min_pt.z;
    const hx = width * 0.5;
    const hy = height * 0.5;
    const hz = depth * 0.5;
    const footprint = [_]local_csg.Point2{
        .{ -hx, -hz },
        .{ hx, -hz },
        .{ -hx, hz },
    };
    var wedge_solid = try local_csg.Solid.fromConvexPrism(state.allocator, &footprint, -hy, hy);
    defer wedge_solid.deinit(state.allocator);
    var csg_mesh = try wedge_solid.toMesh(state.allocator);
    defer csg_mesh.deinit(state.allocator);
    var mesh = try csgMeshToGeometry(state.allocator, csg_mesh);
    errdefer mesh.deinit(state.allocator);
    const tex = try state.allocator.alloc(u8, TextureSize * TextureSize * 4);
    errdefer state.allocator.free(tex);
    fillCheckerTexture(tex, TextureSize, 160, 150, 190);

    const name = try std.fmt.allocPrint(state.allocator, "Brush {d}", .{state.next_object_id});
    defer state.allocator.free(name);

    try state.objects.append(state.allocator, .{
        .id = state.next_object_id,
        .name = try state.allocator.dupe(u8, name),
        .mesh = mesh,
        .position = .{
            .x = min_pt.x + width * 0.5,
            .y = min_pt.y + height * 0.5,
            .z = min_pt.z + depth * 0.5,
        },
        .rotation = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = tex,
        .base_color = .{ .r = 160, .g = 145, .b = 190, .a = 255 },
        .primitive_kind = null,
        .physics = static_body,
        .blockout_intent = .{
            .kind = .wedge_add,
            .min = min_pt,
            .max = max_pt,
        },
    });
    state.next_object_id += 1;
    state.selected_object = state.objects.items.len - 1;
    state.selected_vertex = null;
    state.selected_edge = null;
    state.selected_face = null;
    if (persist) {
        try world_authoring.persistAddWedgeBlockout(state, min_pt, max_pt);
    }
}

fn csgMeshToGeometry(allocator: std.mem.Allocator, csg_mesh: local_csg.solid.Mesh) !geometry.Mesh {
    const vertices = try allocator.alloc(geometry.Vertex, csg_mesh.vertices.len);
    errdefer allocator.free(vertices);
    for (csg_mesh.vertices, 0..) |vertex, idx| {
        vertices[idx] = .{
            .position = .{ .x = vertex.position[0], .y = vertex.position[1], .z = vertex.position[2] },
            .normal = .{ .x = vertex.normal[0], .y = vertex.normal[1], .z = vertex.normal[2] },
            .uv = .{ .x = vertex.uv[0], .y = vertex.uv[1] },
        };
    }
    return .{
        .vertices = vertices,
        .indices = try allocator.dupe(u32, csg_mesh.indices),
    };
}

pub fn addBlockoutRamp(state: *ProjectEditorState) !void {
    project_editor_edit.pushUndoSnapshot(state);
    const width = @max(1.0, state.snap_size * 2.0);
    const height = @max(1.0, state.blockout_brush_size);
    const depth = @max(1.0, state.snap_size * 3.0);
    const x = snapValue(@as(f32, @floatFromInt(state.objects.items.len)) * 1.5, if (state.snap_enabled) state.snap_size else 0);
    try addBlockoutRampAt(state, .{ .x = x, .y = 0, .z = 0 }, width, height, depth);
}

pub fn addBlockoutRampAt(state: *ProjectEditorState, min_pt: editor_math.Vec3, width: f32, height: f32, depth: f32) !void {
    var mesh = try buildRampMesh(state.allocator, width, height, depth);
    errdefer mesh.deinit(state.allocator);
    const tex = try state.allocator.alloc(u8, TextureSize * TextureSize * 4);
    errdefer state.allocator.free(tex);
    fillCheckerTexture(tex, TextureSize, 145, 180, 150);

    const name = try std.fmt.allocPrint(state.allocator, "Ramp {d}", .{state.next_object_id});
    defer state.allocator.free(name);

    try state.objects.append(state.allocator, .{
        .id = state.next_object_id,
        .name = try state.allocator.dupe(u8, name),
        .mesh = mesh,
        .position = .{
            .x = min_pt.x + width * 0.5,
            .y = min_pt.y + height * 0.5,
            .z = min_pt.z + depth * 0.5,
        },
        .rotation = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = tex,
        .base_color = .{ .r = 120, .g = 165, .b = 135, .a = 255 },
        .primitive_kind = null,
    });
    state.next_object_id += 1;
    state.selected_object = state.objects.items.len - 1;
    state.selected_vertex = null;
    state.selected_edge = null;
    state.selected_face = null;
    state.objects.items[state.selected_object.?].blockout_intent = .{
        .kind = .ramp,
        .min = min_pt,
        .max = .{ .x = min_pt.x + width, .y = min_pt.y + height, .z = min_pt.z + depth },
    };
    project_editor_state.setStatus(state, "Blockout ramp added");
}

pub fn addBlockoutBoxInternal(state: *ProjectEditorState, min_pt: editor_math.Vec3, max_pt: editor_math.Vec3, persist: bool) !void {
    try addNamedBlockoutBox(state, min_pt, max_pt, "Brush", .{ .r = 140, .g = 155, .b = 175, .a = 255 }, persist);
}

pub fn addNamedBlockoutBox(
    state: *ProjectEditorState,
    min_pt: editor_math.Vec3,
    max_pt: editor_math.Vec3,
    name_prefix: []const u8,
    color: shared_color.Color,
    persist: bool,
) !void {
    const width = max_pt.x - min_pt.x;
    const height = max_pt.y - min_pt.y;
    const depth = max_pt.z - min_pt.z;
    const mesh = try geometry.buildPrimitive(state.allocator, .box, .{
        .width = width,
        .height = height,
        .depth = depth,
    });
    const tex = try state.allocator.alloc(u8, TextureSize * TextureSize * 4);
    fillCheckerTexture(tex, TextureSize, color.r, color.g, color.b);

    const name = try std.fmt.allocPrint(state.allocator, "{s} {d}", .{ name_prefix, state.next_object_id });
    defer state.allocator.free(name);

    try state.objects.append(state.allocator, .{
        .id = state.next_object_id,
        .name = try state.allocator.dupe(u8, name),
        .mesh = mesh,
        .position = .{
            .x = min_pt.x + width * 0.5,
            .y = min_pt.y + height * 0.5,
            .z = min_pt.z + depth * 0.5,
        },
        .rotation = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = tex,
        .base_color = color,
        .primitive_kind = .box,
        .physics = static_body,
    });
    state.next_object_id += 1;
    state.selected_object = state.objects.items.len - 1;
    state.selected_vertex = null;
    state.selected_edge = null;
    state.selected_face = null;
    if (persist) {
        state.objects.items[state.selected_object.?].blockout_intent = .{
            .kind = .box_add,
            .min = min_pt,
            .max = max_pt,
        };
        try world_authoring.persistAddBlockout(state, min_pt, max_pt);
    }
}

fn buildRampMesh(allocator: std.mem.Allocator, width: f32, height: f32, depth: f32) !geometry.Mesh {
    var vertices: std.ArrayList(geometry.Vertex) = .empty;
    defer vertices.deinit(allocator);
    var indices: std.ArrayList(u32) = .empty;
    defer indices.deinit(allocator);

    const hx = width * 0.5;
    const hy = height * 0.5;
    const hz = depth * 0.5;
    const low_l: editor_math.Vec3 = .{ .x = -hx, .y = -hy, .z = -hz };
    const low_r: editor_math.Vec3 = .{ .x = hx, .y = -hy, .z = -hz };
    const high_l: editor_math.Vec3 = .{ .x = -hx, .y = hy, .z = hz };
    const high_r: editor_math.Vec3 = .{ .x = hx, .y = hy, .z = hz };
    const back_l: editor_math.Vec3 = .{ .x = -hx, .y = -hy, .z = hz };
    const back_r: editor_math.Vec3 = .{ .x = hx, .y = -hy, .z = hz };

    try appendRampQuad(allocator, &vertices, &indices, low_l, low_r, high_r, high_l, slopeNormal(height, depth));
    try appendRampQuad(allocator, &vertices, &indices, back_r, back_l, high_l, high_r, .{ .x = 0, .y = 0, .z = 1 });
    try appendRampQuad(allocator, &vertices, &indices, back_l, back_r, low_r, low_l, .{ .x = 0, .y = -1, .z = 0 });
    try appendRampTri(allocator, &vertices, &indices, low_l, high_l, back_l, .{ .x = -1, .y = 0, .z = 0 });
    try appendRampTri(allocator, &vertices, &indices, low_r, back_r, high_r, .{ .x = 1, .y = 0, .z = 0 });

    return .{
        .vertices = try vertices.toOwnedSlice(allocator),
        .indices = try indices.toOwnedSlice(allocator),
    };
}

pub fn buildGableRoofMesh(allocator: std.mem.Allocator, width: f32, depth: f32, rise: f32) !geometry.Mesh {
    var vertices: std.ArrayList(geometry.Vertex) = .empty;
    defer vertices.deinit(allocator);
    var indices: std.ArrayList(u32) = .empty;
    defer indices.deinit(allocator);

    const hx = width * 0.5;
    const hz = depth * 0.5;
    const left_front: editor_math.Vec3 = .{ .x = -hx, .y = 0, .z = -hz };
    const right_front: editor_math.Vec3 = .{ .x = hx, .y = 0, .z = -hz };
    const left_back: editor_math.Vec3 = .{ .x = -hx, .y = 0, .z = hz };
    const right_back: editor_math.Vec3 = .{ .x = hx, .y = 0, .z = hz };
    const ridge_front: editor_math.Vec3 = .{ .x = 0, .y = rise, .z = -hz };
    const ridge_back: editor_math.Vec3 = .{ .x = 0, .y = rise, .z = hz };

    try appendRampQuad(allocator, &vertices, &indices, left_front, ridge_front, ridge_back, left_back, roofPlaneNormal(-1, rise, hx));
    try appendRampQuad(allocator, &vertices, &indices, ridge_front, right_front, right_back, ridge_back, roofPlaneNormal(1, rise, hx));
    try appendRampTri(allocator, &vertices, &indices, left_front, ridge_front, right_front, .{ .x = 0, .y = 0, .z = -1 });
    try appendRampTri(allocator, &vertices, &indices, right_back, ridge_back, left_back, .{ .x = 0, .y = 0, .z = 1 });

    return .{
        .vertices = try vertices.toOwnedSlice(allocator),
        .indices = try indices.toOwnedSlice(allocator),
    };
}

pub fn roofPlaneNormal(sign: f32, rise: f32, half_width: f32) editor_math.Vec3 {
    const len = @sqrt(rise * rise + half_width * half_width);
    return .{ .x = sign * rise / len, .y = half_width / len, .z = 0 };
}

pub fn buildPlayerStartMarkerMesh(allocator: std.mem.Allocator) !geometry.Mesh {
    var vertices: std.ArrayList(geometry.Vertex) = .empty;
    defer vertices.deinit(allocator);
    var indices: std.ArrayList(u32) = .empty;
    defer indices.deinit(allocator);

    const y: f32 = 0;
    try appendRampQuad(
        allocator,
        &vertices,
        &indices,
        .{ .x = -0.12, .y = y, .z = -0.45 },
        .{ .x = 0.12, .y = y, .z = -0.45 },
        .{ .x = 0.12, .y = y, .z = 0.08 },
        .{ .x = -0.12, .y = y, .z = 0.08 },
        .{ .x = 0, .y = 1, .z = 0 },
    );
    try appendRampTri(
        allocator,
        &vertices,
        &indices,
        .{ .x = -0.38, .y = y, .z = 0.02 },
        .{ .x = 0, .y = y, .z = 0.58 },
        .{ .x = 0.38, .y = y, .z = 0.02 },
        .{ .x = 0, .y = 1, .z = 0 },
    );

    return .{
        .vertices = try vertices.toOwnedSlice(allocator),
        .indices = try indices.toOwnedSlice(allocator),
    };
}

fn slopeNormal(height: f32, depth: f32) editor_math.Vec3 {
    const len = @sqrt(height * height + depth * depth);
    return .{ .x = 0, .y = depth / len, .z = -height / len };
}

pub fn appendRampVertex(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(geometry.Vertex),
    position: editor_math.Vec3,
    normal: editor_math.Vec3,
    uv: editor_math.Vec2,
) !void {
    try vertices.append(allocator, .{ .position = position, .normal = normal, .uv = uv });
}

pub fn appendRampQuad(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(geometry.Vertex),
    indices: *std.ArrayList(u32),
    p0: editor_math.Vec3,
    p1: editor_math.Vec3,
    p2: editor_math.Vec3,
    p3: editor_math.Vec3,
    normal: editor_math.Vec3,
) !void {
    const base: u32 = @intCast(vertices.items.len);
    try appendRampVertex(allocator, vertices, p0, normal, .{ .x = 0, .y = 0 });
    try appendRampVertex(allocator, vertices, p1, normal, .{ .x = 1, .y = 0 });
    try appendRampVertex(allocator, vertices, p2, normal, .{ .x = 1, .y = 1 });
    try appendRampVertex(allocator, vertices, p3, normal, .{ .x = 0, .y = 1 });
    try indices.appendSlice(allocator, &.{ base, base + 2, base + 1, base, base + 3, base + 2 });
}

pub fn appendOrientedRampQuad(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(geometry.Vertex),
    indices: *std.ArrayList(u32),
    p0: editor_math.Vec3,
    p1: editor_math.Vec3,
    p2: editor_math.Vec3,
    p3: editor_math.Vec3,
    normal: editor_math.Vec3,
) !void {
    const winding_normal = roofTriangleNormal(p0, p2, p1);
    if (editor_math.Vec3.dot(winding_normal, normal) >= 0) {
        try appendRampQuad(allocator, vertices, indices, p0, p1, p2, p3, normal);
    } else {
        try appendRampQuad(allocator, vertices, indices, p0, p3, p2, p1, normal);
    }
}

pub fn appendRampTri(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(geometry.Vertex),
    indices: *std.ArrayList(u32),
    p0: editor_math.Vec3,
    p1: editor_math.Vec3,
    p2: editor_math.Vec3,
    normal: editor_math.Vec3,
) !void {
    const base: u32 = @intCast(vertices.items.len);
    try appendRampVertex(allocator, vertices, p0, normal, .{ .x = 0, .y = 0 });
    try appendRampVertex(allocator, vertices, p1, normal, .{ .x = 0.5, .y = 1 });
    try appendRampVertex(allocator, vertices, p2, normal, .{ .x = 1, .y = 0 });
    try indices.appendSlice(allocator, &.{ base, base + 2, base + 1 });
}

pub fn appendOrientedRampTri(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(geometry.Vertex),
    indices: *std.ArrayList(u32),
    p0: editor_math.Vec3,
    p1: editor_math.Vec3,
    p2: editor_math.Vec3,
    normal: editor_math.Vec3,
) !void {
    const winding_normal = roofTriangleNormal(p0, p2, p1);
    if (editor_math.Vec3.dot(winding_normal, normal) >= 0) {
        try appendRampTri(allocator, vertices, indices, p0, p1, p2, normal);
    } else {
        try appendRampTri(allocator, vertices, indices, p0, p2, p1, normal);
    }
}

fn roofTriangleNormal(p0: editor_math.Vec3, p1: editor_math.Vec3, p2: editor_math.Vec3) editor_math.Vec3 {
    const u = editor_math.Vec3.sub(p1, p0);
    const v = editor_math.Vec3.sub(p2, p0);
    return editor_math.Vec3.normalized(editor_math.cross(u, v));
}

pub fn subtractBlockoutBox(state: *ProjectEditorState, min_pt: editor_math.Vec3, max_pt: editor_math.Vec3) !void {
    try subtractBlockoutBoxSemantic(state, min_pt, max_pt, .subtract_block);
}

pub fn subtractBlockoutWedge(state: *ProjectEditorState, min_pt: editor_math.Vec3, max_pt: editor_math.Vec3) !void {
    const footprint = wedgeFootprintFromBounds(min_pt, max_pt);
    try subtractBlockoutPrismSemantic(state, &footprint, min_pt.y, max_pt.y, .subtract_prism);
}

pub fn subtractDoorwayBlockoutBox(state: *ProjectEditorState, min_pt: editor_math.Vec3, max_pt: editor_math.Vec3) !void {
    try subtractBlockoutBoxSemantic(state, min_pt, max_pt, .doorway_subtract);
}

fn subtractBlockoutBoxSemantic(
    state: *ProjectEditorState,
    min_pt: editor_math.Vec3,
    max_pt: editor_math.Vec3,
    semantic: scene_blockout.Kind,
) !void {
    var idx: usize = state.objects.items.len;
    while (idx > 0) {
        idx -= 1;
        const bounds = objectWorldBounds(&state.objects.items[idx]);
        if (aabbOverlaps(min_pt, max_pt, bounds.min, bounds.max)) {
            const cut_min: editor_math.Vec3 = .{
                .x = @max(min_pt.x, bounds.min.x),
                .y = @max(min_pt.y, bounds.min.y),
                .z = @max(min_pt.z, bounds.min.z),
            };
            const cut_max: editor_math.Vec3 = .{
                .x = @min(max_pt.x, bounds.max.x),
                .y = @min(max_pt.y, bounds.max.y),
                .z = @min(max_pt.z, bounds.max.z),
            };
            const cut_full = cut_min.x <= bounds.min.x and cut_max.x >= bounds.max.x and
                cut_min.y <= bounds.min.y and cut_max.y >= bounds.max.y and
                cut_min.z <= bounds.min.z and cut_max.z >= bounds.max.z;
            if (!cut_full) {
                switch (semantic) {
                    .subtract_block => try world_authoring.persistSubtractBlockout(state, cut_min, cut_max, bounds.min, bounds.max),
                    .doorway_subtract => try world_authoring.persistDoorwaySubtract(state, cut_min, cut_max, bounds.min, bounds.max),
                    else => return error.InvalidCsgOperation,
                }
            }

            var removed = state.objects.orderedRemove(idx);
            removed.deinit(state.allocator);
            if (!cut_full) {
                var wall_solid = try local_csg.Solid.fromBox(
                    state.allocator,
                    .{
                        .min = .{ bounds.min.x, bounds.min.y, bounds.min.z },
                        .max = .{ bounds.max.x, bounds.max.y, bounds.max.z },
                    },
                );
                defer wall_solid.deinit(state.allocator);
                var remainder = try wall_solid.subtractBox(
                    state.allocator,
                    .{
                        .min = .{ cut_min.x, cut_min.y, cut_min.z },
                        .max = .{ cut_max.x, cut_max.y, cut_max.z },
                    },
                );
                defer remainder.deinit(state.allocator);
                for (remainder.boxes) |segment| {
                    try addBlockoutBoxInternal(
                        state,
                        .{ .x = segment.min[0], .y = segment.min[1], .z = segment.min[2] },
                        .{ .x = segment.max[0], .y = segment.max[1], .z = segment.max[2] },
                        false,
                    );
                }
            }
            if (state.selected_object) |sel| {
                if (sel == idx or sel >= state.objects.items.len) {
                    state.selected_object = if (state.objects.items.len > 0) state.objects.items.len - 1 else null;
                    state.selected_vertex = null;
                    state.selected_edge = null;
                    state.selected_face = null;
                } else if (sel > idx) {
                    state.selected_object = sel - 1;
                }
            }
        }
    }
}

fn subtractBlockoutPrismSemantic(
    state: *ProjectEditorState,
    footprint: []const local_csg.Point2,
    min_y: f32,
    max_y: f32,
    semantic: scene_blockout.Kind,
) !void {
    if (semantic != .subtract_prism) return error.InvalidCsgOperation;
    const cut_bounds = prismBoundsFromFootprint(footprint, min_y, max_y);
    var idx: usize = state.objects.items.len;
    while (idx > 0) {
        idx -= 1;
        const bounds = objectWorldBounds(&state.objects.items[idx]);
        if (aabbOverlaps(cut_bounds.min, cut_bounds.max, bounds.min, bounds.max)) {
            try world_authoring.persistSubtractPrismBlockout(state, footprint, min_y, max_y, bounds.min, bounds.max);

            var removed = state.objects.orderedRemove(idx);
            removed.deinit(state.allocator);

            var source_solid = try local_csg.Solid.fromBox(
                state.allocator,
                .{
                    .min = .{ bounds.min.x, bounds.min.y, bounds.min.z },
                    .max = .{ bounds.max.x, bounds.max.y, bounds.max.z },
                },
            );
            defer source_solid.deinit(state.allocator);
            var remainder = try source_solid.subtractConvexPrism(state.allocator, footprint, min_y, max_y);
            defer remainder.deinit(state.allocator);
            for (remainder.boxes) |segment| {
                try addBlockoutBoxInternal(
                    state,
                    .{ .x = segment.min[0], .y = segment.min[1], .z = segment.min[2] },
                    .{ .x = segment.max[0], .y = segment.max[1], .z = segment.max[2] },
                    false,
                );
            }
            for (remainder.prisms) |fragment| {
                try addBlockoutPrismFragment(state, fragment, prismAabb(fragment));
            }
            if (state.selected_object) |sel| {
                if (sel == idx or sel >= state.objects.items.len) {
                    state.selected_object = if (state.objects.items.len > 0) state.objects.items.len - 1 else null;
                    state.selected_vertex = null;
                    state.selected_edge = null;
                    state.selected_face = null;
                } else if (sel > idx) {
                    state.selected_object = sel - 1;
                }
            }
        }
    }
}

fn addBlockoutPrismFragment(
    state: *ProjectEditorState,
    prism: local_csg.ConvexPrism,
    bounds: local_csg.Aabb,
) !void {
    const prism_solid = local_csg.Solid{ .prisms = @constCast(&[_]local_csg.ConvexPrism{prism}) };
    var csg_mesh = try prism_solid.toMesh(state.allocator);
    defer csg_mesh.deinit(state.allocator);
    var mesh = try csgMeshToGeometry(state.allocator, csg_mesh);
    errdefer mesh.deinit(state.allocator);
    const tex = try state.allocator.alloc(u8, TextureSize * TextureSize * 4);
    errdefer state.allocator.free(tex);
    fillCheckerTexture(tex, TextureSize, 150, 145, 180);

    const name = try std.fmt.allocPrint(state.allocator, "Brush {d}", .{state.next_object_id});
    defer state.allocator.free(name);
    try state.objects.append(state.allocator, .{
        .id = state.next_object_id,
        .name = try state.allocator.dupe(u8, name),
        .mesh = mesh,
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .rotation = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = tex,
        .base_color = .{ .r = 150, .g = 145, .b = 180, .a = 255 },
        .primitive_kind = null,
        .physics = static_body,
    });
    state.next_object_id += 1;
    state.selected_object = state.objects.items.len - 1;
    state.selected_vertex = null;
    state.selected_edge = null;
    state.selected_face = null;
    _ = bounds;
}

fn wedgeFootprintFromBounds(min_pt: editor_math.Vec3, max_pt: editor_math.Vec3) [3]local_csg.Point2 {
    return .{
        .{ min_pt.x, min_pt.z },
        .{ max_pt.x, min_pt.z },
        .{ min_pt.x, max_pt.z },
    };
}

fn prismBoundsFromFootprint(footprint: []const local_csg.Point2, min_y: f32, max_y: f32) struct { min: editor_math.Vec3, max: editor_math.Vec3 } {
    var min_x = footprint[0][0];
    var max_x = min_x;
    var min_z = footprint[0][1];
    var max_z = min_z;
    for (footprint[1..]) |point| {
        min_x = @min(min_x, point[0]);
        max_x = @max(max_x, point[0]);
        min_z = @min(min_z, point[1]);
        max_z = @max(max_z, point[1]);
    }
    return .{
        .min = .{ .x = min_x, .y = min_y, .z = min_z },
        .max = .{ .x = max_x, .y = max_y, .z = max_z },
    };
}

fn prismAabb(prism: local_csg.ConvexPrism) local_csg.Aabb {
    var min_x = prism.footprint[0][0];
    var max_x = min_x;
    var min_z = prism.footprint[0][1];
    var max_z = min_z;
    for (prism.footprint[1..]) |point| {
        min_x = @min(min_x, point[0]);
        max_x = @max(max_x, point[0]);
        min_z = @min(min_z, point[1]);
        max_z = @max(max_z, point[1]);
    }
    return .{
        .min = .{ min_x, prism.min_y, min_z },
        .max = .{ max_x, prism.max_y, max_z },
    };
}
