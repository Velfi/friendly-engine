const std = @import("std");
const shared = @import("runtime_shared");
const geometry = shared.geometry;
const editor_math = shared.editor_math;
const scene_resolve = shared.scene_resolve;
const project_editor_edit = @import("project_editor_edit.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_prop_catalog = @import("project_editor_prop_catalog.zig");
const project_editor_prop_asset = @import("project_editor_prop_asset.zig");
const project_editor_types = @import("project_editor_types.zig");
const scene_object = @import("editor_scene_object.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const SceneObject = scene_object.SceneObject;
const TextureSize = scene_object.TextureSize;
const fillCheckerTexture = scene_object.fillCheckerTexture;
const CatalogEntry = project_editor_prop_catalog.CatalogEntry;
const findCatalogEntry = project_editor_prop_catalog.findCatalogEntry;

const ResolvedPropMesh = struct {
    mesh: geometry.Mesh,
    mesh_ref: []const u8,
};

const PropPrimitive = project_editor_types.PropPrimitive;
const primitive_color = shared.color.Color{ .r = 170, .g = 180, .b = 195, .a = 255 };

pub fn instantiatePropAssetAt(state: *ProjectEditorState, catalog_id: []const u8, point: editor_math.Vec3) !void {
    project_editor_edit.pushUndoSnapshot(state);

    var doc = try project_editor_prop_asset.ensureAssetDocument(state, catalog_id);
    defer doc.deinit(state.allocator);
    var mesh = try project_editor_prop_asset.loadAssetMesh(state, doc);
    errdefer mesh.deinit(state.allocator);
    const catalog_entry = findCatalogEntry(doc.id);
    const mesh_ref = if (catalog_entry) |entry| entry.mesh_ref else doc.mesh_path;

    const tex = try state.allocator.alloc(u8, TextureSize * TextureSize * 4);
    errdefer state.allocator.free(tex);

    var skeleton_asset: ?[]u8 = null;
    var bone_pose: []shared.scene_animation.Transform = &.{};
    if (mesh.skin != null) {
        var project_dir = try scene_resolve.openProjectDir(state.io, state.project_path);
        defer project_dir.close(state.io);
        const glb_bytes = try project_dir.readFileAlloc(state.io, mesh_ref, state.allocator, .limited(64 * 1024 * 1024));
        defer state.allocator.free(glb_bytes);
        const skeletons = try shared.gltf_import.extractSkeletons(state.allocator, glb_bytes, mesh_ref);
        defer {
            for (skeletons) |*skeleton| skeleton.deinit(state.allocator);
            state.allocator.free(skeletons);
        }
        if (skeletons.len == 0) return error.MissingSkeleton;
        try ensureSkeletonInScene(state, skeletons[0]);
        skeleton_asset = try state.allocator.dupe(u8, mesh_ref);
        bone_pose = try shared.scene_skinning.restPoseFromSkeleton(state.allocator, skeletons[0]);
    }

    var name_buf: [64]u8 = undefined;
    const name = std.fmt.bufPrint(&name_buf, "{s} {d}", .{ doc.label, state.next_object_id }) catch doc.label;

    var obj = SceneObject{
        .id = state.next_object_id,
        .name = try state.allocator.dupe(u8, name),
        .mesh = mesh,
        .position = point,
        .rotation = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = tex,
        .base_color = doc.base_color,
        .primitive_kind = null,
        .object_kind = .mesh,
        .physics = null,
        .prop_asset_id = try state.allocator.dupe(u8, doc.id),
        .variant = try std.fmt.allocPrint(state.allocator, "0", .{}),
        .skeleton_asset = skeleton_asset,
        .bone_pose = bone_pose,
        .editor_only = false,
    };
    fillCheckerTexture(obj.texture, TextureSize, doc.base_color.r, doc.base_color.g, doc.base_color.b);
    try project_editor_prop_asset.applyAssetMaterialTexture(state.allocator, &obj, doc.id);
    applyPlacementToggles(state, &obj);
    finalizeGroundPosition(state, &obj);
    try appendPlacedObject(state, obj);
    project_editor_state.setStatus(state, "Placed prop instance");
}

pub fn addPrimitiveProp(state: *ProjectEditorState, primitive: PropPrimitive) !void {
    var point = editor_math.Vec3{
        .x = @as(f32, @floatFromInt(state.objects.items.len)) * 1.5,
        .y = primitiveGroundOffset(primitive),
        .z = 0,
    };
    if (state.snap_enabled) point.x = @round(point.x / state.snap_size) * state.snap_size;
    try placePrimitiveProp(state, point, primitive);
}

pub fn placePrimitiveProp(state: *ProjectEditorState, point: editor_math.Vec3, primitive: PropPrimitive) !void {
    project_editor_edit.pushUndoSnapshot(state);
    var mesh = try buildPrimitivePropMesh(state.allocator, primitive);
    errdefer mesh.deinit(state.allocator);
    const tex = try state.allocator.alloc(u8, TextureSize * TextureSize * 4);
    errdefer state.allocator.free(tex);
    fillCheckerTexture(tex, TextureSize, primitive_color.r, primitive_color.g, primitive_color.b);

    var name_buf: [64]u8 = undefined;
    const label = primitive.label();
    const name = std.fmt.bufPrint(&name_buf, "{s} {d}", .{ label, state.next_object_id }) catch label;

    var obj = SceneObject{
        .id = state.next_object_id,
        .name = try state.allocator.dupe(u8, name),
        .mesh = mesh,
        .position = point,
        .rotation = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = tex,
        .base_color = primitive_color,
        .primitive_kind = primitiveKind(primitive),
        .object_kind = .mesh,
        .physics = null,
        .editor_only = true,
    };
    applyPlacementToggles(state, &obj);
    finalizeGroundPosition(state, &obj);
    try appendPlacedObject(state, obj);
    project_editor_state.setStatus(state, "Placed prop");
}

fn buildPrimitivePropMesh(allocator: std.mem.Allocator, primitive: PropPrimitive) !geometry.Mesh {
    return switch (primitive) {
        .cube => geometry.buildPrimitive(allocator, .box, .{}),
        .cylinder => geometry.buildPrimitive(allocator, .cylinder, .{}),
        .plane => geometry.buildPrimitive(allocator, .plane, .{}),
        .ramp => buildRampPropMesh(allocator, 1.0, 1.0, 1.0),
    };
}

fn primitiveKind(primitive: PropPrimitive) ?geometry.PrimitiveKind {
    return switch (primitive) {
        .cube => .box,
        .cylinder => .cylinder,
        .plane => .plane,
        .ramp => null,
    };
}

fn primitiveGroundOffset(primitive: PropPrimitive) f32 {
    return switch (primitive) {
        .cube, .cylinder, .ramp => 0.5,
        .plane => 0,
    };
}

fn buildRampPropMesh(allocator: std.mem.Allocator, width: f32, height: f32, depth: f32) !geometry.Mesh {
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

fn appendRampQuad(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(geometry.Vertex),
    indices: *std.ArrayList(u32),
    a: editor_math.Vec3,
    b: editor_math.Vec3,
    c: editor_math.Vec3,
    d: editor_math.Vec3,
    normal: editor_math.Vec3,
) !void {
    try geometry.appendWorldQuad(allocator, vertices, indices, a, b, c, d, normal);
}

fn appendRampTri(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(geometry.Vertex),
    indices: *std.ArrayList(u32),
    a: editor_math.Vec3,
    b: editor_math.Vec3,
    c: editor_math.Vec3,
    normal: editor_math.Vec3,
) !void {
    const base: u32 = @intCast(vertices.items.len);
    const uvs = geometry.planarTriangleUvs(a, b, c);
    try vertices.append(allocator, .{ .position = a, .normal = normal, .uv = uvs[0] });
    try vertices.append(allocator, .{ .position = b, .normal = normal, .uv = uvs[1] });
    try vertices.append(allocator, .{ .position = c, .normal = normal, .uv = uvs[2] });
    try indices.appendSlice(allocator, &.{ base, base + 2, base + 1 });
}

fn slopeNormal(height: f32, depth: f32) editor_math.Vec3 {
    const len = @sqrt(height * height + depth * depth);
    return .{ .x = 0, .y = depth / len, .z = -height / len };
}

pub fn resolvePropMesh(state: *ProjectEditorState, entry: CatalogEntry) !ResolvedPropMesh {
    var doc = try project_editor_prop_asset.ensureAssetDocument(state, entry.id);
    defer doc.deinit(state.allocator);
    const mesh = try project_editor_prop_asset.loadAssetMesh(state, doc);
    return .{
        .mesh = mesh,
        .mesh_ref = entry.id,
    };
}

fn ensureSkeletonInScene(state: *ProjectEditorState, skeleton: shared.scene_animation.Skeleton) !void {
    for (state.skeletons.items) |existing| {
        if (std.mem.eql(u8, existing.asset, skeleton.asset)) return;
    }
    const copies = try shared.scene_animation.duplicateSkeletons(state.allocator, &.{skeleton});
    defer state.allocator.free(copies);
    try state.skeletons.append(state.allocator, copies[0]);
}

fn applyPlacementToggles(state: *ProjectEditorState, obj: *SceneObject) void {
    if (state.prop_random_yaw) {
        const seed = @as(u32, @truncate(state.next_object_id * 1103515245 + 12345));
        obj.rotation.y = @as(f32, @floatFromInt(seed % 360)) * 0.0174533;
    }
}

fn finalizeGroundPosition(state: *const ProjectEditorState, obj: *SceneObject) void {
    if (!state.prop_drop_to_ground) return;
    const offset = geometry.meshGroundOffsetY(&obj.mesh, obj.scale.y);
    obj.position.y = offset;
}

pub fn appendPlacedObject(state: *ProjectEditorState, obj: SceneObject) !void {
    try state.objects.append(state.allocator, obj);
    state.next_object_id += 1;
    state.selected_object = state.objects.items.len - 1;
    state.selected_vertex = null;
    state.selected_edge = null;
    state.selected_face = null;
    state.scene_dirty = true;
    if (obj.prop_asset_id) |asset_id| {
        const recent = @import("project_editor_prop_recent.zig");
        recent.recordRecentProp(state, asset_id);
    }
}
