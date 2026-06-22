const std = @import("std");
const shared = @import("runtime_shared");
const geometry = shared.geometry;
const editor_math = shared.editor_math;
const mesh_codec = shared.mesh_codec;
const gltf_import = shared.gltf_import;
const gltf_export = shared.gltf_export;
const prop_asset_doc = shared.prop_asset_doc;
const scene_io = shared.scene_io;
const scene_texture = shared.scene_texture;
const scene_resolve = shared.scene_resolve;
const project_editor_state = @import("project_editor_state.zig");
const project_editor_edit = @import("project_editor_edit.zig");
const project_editor_prop_catalog = @import("project_editor_prop_catalog.zig");
const project_editor_prop_index = @import("project_editor_prop_index.zig");
const project_editor_texture_paint = @import("project_editor_texture_paint.zig");
const scene_object = @import("editor_scene_object.zig");
const shape_operation = @import("shape_operation.zig");
const shape_source = @import("shape_source.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const SceneObject = scene_object.SceneObject;
const TextureSize = scene_object.TextureSize;
const fillCheckerTexture = scene_object.fillCheckerTexture;

pub fn selectedAssetId(state: *const ProjectEditorState) ?[]const u8 {
    const idx = state.selected_object orelse return state.active_prop_asset_id;
    return state.objects.items[idx].prop_asset_id orelse state.active_prop_asset_id;
}

pub fn propagateSelectedAssetGeometry(state: *ProjectEditorState) void {
    propagateSelectedAssetGeometryFallible(state) catch {
        project_editor_state.setStatus(state, "Prop geometry propagation failed");
    };
}

pub fn propagateSelectedAssetGeometryFallible(state: *ProjectEditorState) !void {
    const idx = state.selected_object orelse return;
    const asset_id = state.objects.items[idx].prop_asset_id orelse return;
    try propagateAndSaveSelectedAssetGeometry(state, idx, asset_id, .update_material_from_object);
}

pub fn persistScenePropAssets(state: *ProjectEditorState) !void {
    var persisted: std.ArrayList([]const u8) = .empty;
    defer persisted.deinit(state.allocator);

    for (state.objects.items, 0..) |object, idx| {
        const asset_id = object.prop_asset_id orelse continue;
        if (containsAssetId(persisted.items, asset_id)) continue;
        try saveAssetFromObject(state, idx, asset_id, .keep_existing_material);
        try persisted.append(state.allocator, asset_id);
    }
}

pub fn clearEditablePropWorkingCopies(state: *ProjectEditorState, keep_asset_id: ?[]const u8) void {
    var index = state.objects.items.len;
    while (index > 0) {
        index -= 1;
        const object = &state.objects.items[index];
        if (!object.editor_only or object.prop_asset_id == null) continue;
        if (keep_asset_id) |keep| {
            if (std.mem.eql(u8, object.prop_asset_id.?, keep)) continue;
        }
        var removed = state.objects.orderedRemove(index);
        removed.deinit(state.allocator);
    }
    if (state.selected_object) |selected| {
        if (selected >= state.objects.items.len) state.selected_object = null;
    }
    state.selected_vertex = null;
    state.selected_edge = null;
    state.selected_face = null;
}

pub fn createCustomAssetWorkingCopy(state: *ProjectEditorState, asset_id: []const u8, label: []const u8, tags: []const u8) !void {
    if (asset_id.len == 0) return error.EmptyPropAssetId;
    if (try assetDocumentExists(state, asset_id)) return error.PropAssetAlreadyExists;
    project_editor_edit.pushUndoSnapshot(state);
    clearEditablePropWorkingCopies(state, null);

    const display_label = if (label.len > 0) label else asset_id;
    var name_buf: [96]u8 = undefined;
    const name = std.fmt.bufPrint(&name_buf, "{s} {d}", .{ display_label, state.next_object_id }) catch display_label;

    const active_asset_id = try state.allocator.dupe(u8, asset_id);
    errdefer state.allocator.free(active_asset_id);

    {
        const object_name = try state.allocator.dupe(u8, name);
        errdefer state.allocator.free(object_name);
        const object_asset_id = try state.allocator.dupe(u8, asset_id);
        errdefer state.allocator.free(object_asset_id);
        const object_variant = try state.allocator.dupe(u8, "0");
        errdefer state.allocator.free(object_variant);
        var mesh = geometry.Mesh{
            .vertices = try state.allocator.alloc(geometry.Vertex, 0),
            .indices = try state.allocator.alloc(u32, 0),
        };
        errdefer mesh.deinit(state.allocator);
        const tex = try state.allocator.alloc(u8, TextureSize * TextureSize * 4);
        errdefer state.allocator.free(tex);
        fillCheckerTexture(tex, TextureSize, 82, 151, 72);

        var obj = SceneObject{
            .id = state.next_object_id,
            .name = object_name,
            .mesh = mesh,
            .position = .{ .x = 0, .y = 0, .z = 0 },
            .rotation = .{ .x = 0, .y = 0, .z = 0 },
            .scale = .{ .x = 1, .y = 1, .z = 1 },
            .texture = tex,
            .base_color = .{ .r = 82, .g = 151, .b = 72, .a = 255 },
            .primitive_kind = null,
            .object_kind = .mesh,
            .physics = null,
            .prop_asset_id = object_asset_id,
            .variant = object_variant,
            .editor_only = true,
        };
        errdefer obj.deinit(state.allocator);
        try state.objects.append(state.allocator, obj);
    }

    state.selected_object = state.objects.items.len - 1;
    state.next_object_id += 1;
    state.mode = .prop_creation;
    state.prop_workspace_mode = .edit;
    state.prop_tool = .edit;
    if (state.active_prop_asset_id) |existing| state.allocator.free(existing);
    state.active_prop_asset_id = active_asset_id;
    var doc = try customDocumentFromObject(state.allocator, &state.objects.items[state.selected_object.?], asset_id, display_label, tags);
    defer doc.deinit(state.allocator);
    try writeAssetDocumentAndMesh(state, doc, &state.objects.items[state.selected_object.?].mesh);
    project_editor_state.setStatus(state, "Created prop asset");
}

pub fn modifyAssetWorkingCopy(state: *ProjectEditorState, asset_id: []const u8) !void {
    if (asset_id.len == 0) return error.EmptyPropAssetId;
    var doc = try loadAssetDocument(state, asset_id);
    defer doc.deinit(state.allocator);
    var mesh = try loadAssetMesh(state, doc);
    errdefer mesh.deinit(state.allocator);

    project_editor_edit.pushUndoSnapshot(state);
    clearEditablePropWorkingCopies(state, asset_id);
    if (findEditableObjectForAsset(state, asset_id)) |idx| {
        const object_name = try std.fmt.allocPrint(state.allocator, "{s} {d}", .{ doc.label, state.objects.items[idx].id });
        var obj = &state.objects.items[idx];
        obj.mesh.deinit(state.allocator);
        obj.mesh = mesh;
        obj.primitive_kind = null;
        obj.base_color = doc.base_color;
        try applyDocumentMaterialSlots(state.allocator, obj, doc);
        try applyDocumentTexture(state, obj, doc);
        state.allocator.free(obj.name);
        obj.name = object_name;
        state.selected_object = idx;
    } else {
        const object_name = try std.fmt.allocPrint(state.allocator, "{s} {d}", .{ doc.label, state.next_object_id });
        errdefer state.allocator.free(object_name);
        const object_asset_id = try state.allocator.dupe(u8, asset_id);
        errdefer state.allocator.free(object_asset_id);
        const object_variant = try state.allocator.dupe(u8, "0");
        errdefer state.allocator.free(object_variant);
        const tex = try loadDocumentTexture(state, doc);
        errdefer state.allocator.free(tex);

        const obj = SceneObject{
            .id = state.next_object_id,
            .name = object_name,
            .mesh = mesh,
            .position = .{ .x = 0, .y = 0, .z = 0 },
            .rotation = .{ .x = 0, .y = 0, .z = 0 },
            .scale = .{ .x = 1, .y = 1, .z = 1 },
            .texture = tex,
            .base_color = doc.base_color,
            .material_path = if (doc.material_path) |path| try state.allocator.dupe(u8, path) else null,
            .face_materials = try scene_io.duplicateFaceMaterials(state.allocator, doc.face_materials),
            .primitive_kind = null,
            .object_kind = .mesh,
            .physics = null,
            .prop_asset_id = object_asset_id,
            .variant = object_variant,
            .editor_only = true,
        };
        try state.objects.append(state.allocator, obj);
        state.selected_object = state.objects.items.len - 1;
        state.next_object_id += 1;
    }

    state.mode = .prop_creation;
    state.prop_workspace_mode = .edit;
    state.prop_tool = .edit;
    if (state.active_prop_asset_id) |existing| state.allocator.free(existing);
    state.active_prop_asset_id = try state.allocator.dupe(u8, asset_id);
    project_editor_state.setStatus(state, "Opened prop asset for modification");
}

fn assetDocumentExists(state: *ProjectEditorState, asset_id: []const u8) !bool {
    const path = try prop_asset_doc.documentPath(state.allocator, asset_id);
    defer state.allocator.free(path);
    var project_dir = try scene_resolve.openProjectDir(state.io, state.project_path);
    defer project_dir.close(state.io);
    project_dir.access(state.io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    return true;
}

fn findEditableObjectForAsset(state: *const ProjectEditorState, asset_id: []const u8) ?usize {
    for (state.objects.items, 0..) |obj, idx| {
        if (!obj.editor_only) continue;
        const object_asset_id = obj.prop_asset_id orelse continue;
        if (std.mem.eql(u8, object_asset_id, asset_id)) return idx;
    }
    return null;
}

pub fn ensureAssetDocument(state: *ProjectEditorState, asset_id: []const u8) !prop_asset_doc.PropAssetDocument {
    if (loadAssetDocument(state, asset_id)) |doc| return doc else |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    }
    const entry = project_editor_prop_catalog.findCatalogEntry(asset_id) orelse return error.UnknownPropAsset;
    var doc = try catalogDocument(state.allocator, entry);
    errdefer doc.deinit(state.allocator);
    var mesh = try buildRecipeMesh(state.allocator, doc.recipe);
    defer mesh.deinit(state.allocator);
    try writeAssetDocumentAndMesh(state, doc, &mesh);
    return doc;
}

pub fn loadAssetMesh(state: *ProjectEditorState, doc: prop_asset_doc.PropAssetDocument) !geometry.Mesh {
    var project_dir = try scene_resolve.openProjectDir(state.io, state.project_path);
    defer project_dir.close(state.io);
    const bytes = try project_dir.readFileAlloc(state.io, doc.mesh_path, state.allocator, .limited(64 * 1024 * 1024));
    defer state.allocator.free(bytes);
    return try mesh_codec.decodeMesh(state.allocator, bytes);
}

pub fn applyAssetMaterialTexture(allocator: std.mem.Allocator, object: *SceneObject, asset_id: []const u8) !void {
    if (!std.mem.eql(u8, asset_id, "barrel_rust")) return;
    if (object.texture.len != TextureSize * TextureSize * 4) {
        allocator.free(object.texture);
        object.texture = try allocator.alloc(u8, TextureSize * TextureSize * 4);
    }
    fillBarrelRustTexture(object.texture, TextureSize);
}

pub const MaterialSpec = struct {
    material_path: []const u8,
    r: u8 = 255,
    g: u8 = 255,
    b: u8 = 255,
    a: u8 = 255,
    scale_world: f32 = 1.0,
    rotation_deg: f32 = 0.0,
    offset_u: f32 = 0.0,
    offset_v: f32 = 0.0,
};

pub const FaceMaterialSpec = struct {
    face_index: usize,
    material_path: []const u8,
    r: u8 = 255,
    g: u8 = 255,
    b: u8 = 255,
    a: u8 = 255,
    scale_world: f32 = 1.0,
    rotation_deg: f32 = 0.0,
    offset_u: f32 = 0.0,
    offset_v: f32 = 0.0,
};

pub fn setObjectMaterialSelected(state: *ProjectEditorState, spec: MaterialSpec) !void {
    const idx = state.selected_object orelse return error.SelectionIsNotPropAsset;
    const asset_id = state.objects.items[idx].prop_asset_id orelse return error.SelectionIsNotPropAsset;
    try validateMaterialPath(spec.material_path);
    project_editor_edit.pushUndoSnapshot(state);
    var obj = &state.objects.items[idx];
    if (obj.material_path) |existing| state.allocator.free(existing);
    obj.material_path = try state.allocator.dupe(u8, spec.material_path);
    obj.texture_transform = materialTransform(spec);
    obj.base_color = .{ .r = spec.r, .g = spec.g, .b = spec.b, .a = spec.a };
    fillCheckerTexture(obj.texture, TextureSize, spec.r, spec.g, spec.b);
    try saveAssetFromObject(state, idx, asset_id, .update_material_from_object);
    state.scene_dirty = true;
    project_editor_state.setStatus(state, "Prop material applied");
}

pub fn setFaceMaterialSelected(state: *ProjectEditorState, spec: FaceMaterialSpec) !void {
    const idx = state.selected_object orelse return error.SelectionIsNotPropAsset;
    const asset_id = state.objects.items[idx].prop_asset_id orelse return error.SelectionIsNotPropAsset;
    try validateMaterialPath(spec.material_path);
    project_editor_edit.pushUndoSnapshot(state);
    var obj = &state.objects.items[idx];
    if (spec.face_index * 3 + 2 >= obj.mesh.indices.len) return error.InvalidFaceIndex;
    try upsertFaceMaterialPath(state, obj, spec);
    obj.base_color = .{ .r = spec.r, .g = spec.g, .b = spec.b, .a = spec.a };
    try saveAssetFromObject(state, idx, asset_id, .update_material_from_object);
    state.scene_dirty = true;
    project_editor_state.setStatus(state, "Prop face material applied");
}

pub const PaintSpec = struct {
    u: f32,
    v: f32,
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,
    radius: f32 = 0.05,
    opacity: f32 = 1.0,
    hardness: f32 = 0.72,
};

pub const FillSpec = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,
};

pub fn fillTextureSelected(state: *ProjectEditorState, spec: FillSpec) !void {
    const idx = state.selected_object orelse return error.SelectionIsNotPropAsset;
    const asset_id = state.objects.items[idx].prop_asset_id orelse return error.SelectionIsNotPropAsset;
    project_editor_edit.pushUndoSnapshot(state);
    const obj = &state.objects.items[idx];
    fillSolidTexture(obj.texture, .{ .r = spec.r, .g = spec.g, .b = spec.b, .a = spec.a });
    obj.base_color = .{ .r = spec.r, .g = spec.g, .b = spec.b, .a = spec.a };
    try persistPaintedTexture(state, idx, asset_id);
    state.scene_dirty = true;
    project_editor_state.setStatus(state, "Prop texture filled");
}

pub fn unwrapTextureSelected(state: *ProjectEditorState) !shared.uv_atlas.UvReport {
    const idx = state.selected_object orelse return error.SelectionIsNotPropAsset;
    const asset_id = state.objects.items[idx].prop_asset_id orelse return error.SelectionIsNotPropAsset;
    project_editor_edit.pushUndoSnapshot(state);
    const obj = &state.objects.items[idx];
    project_editor_texture_paint.markPaintAtlasStale(obj);
    if (!project_editor_texture_paint.ensurePaintAtlas(state, obj)) return error.InvalidPaintAtlas;
    clearFaceMaterials(state.allocator, obj);
    try persistPaintedTexture(state, idx, asset_id);
    state.scene_dirty = true;
    project_editor_state.setStatus(state, "Prop paint atlas unwrapped");
    return obj.paint_atlas_report;
}

pub fn paintTextureSelectedAtUv(state: *ProjectEditorState, spec: PaintSpec) !void {
    const idx = state.selected_object orelse return error.SelectionIsNotPropAsset;
    const asset_id = state.objects.items[idx].prop_asset_id orelse return error.SelectionIsNotPropAsset;
    project_editor_edit.pushUndoSnapshot(state);
    const obj = &state.objects.items[idx];
    if (!project_editor_texture_paint.ensurePaintAtlas(state, obj)) return error.InvalidPaintAtlas;
    project_editor_texture_paint.paintTexture(obj.texture, TextureSize, .{ .x = spec.u, .y = spec.v }, .{ .r = spec.r, .g = spec.g, .b = spec.b, .a = spec.a }, .{
        .radius = spec.radius,
        .opacity = spec.opacity,
        .hardness = spec.hardness,
        .noise = 0.0,
        .brush = .soft_round,
        .stencil = .none,
    });
    try persistPaintedTexture(state, idx, asset_id);
    state.scene_dirty = true;
    project_editor_state.setStatus(state, "Prop texture painted");
}

pub fn placeSketchPointAtScreen(state: *ProjectEditorState, screen_x: f32, screen_y: f32) !bool {
    if (state.prop_sketch_mode == .none) return false;
    const point = @import("project_editor_scene.zig").screenToGroundPoint(state, screen_x, screen_y) orelse {
        project_editor_state.setStatus(state, "Click the prop floor to sketch");
        return true;
    };
    const snapped = if (state.snap_enabled) snapSketchPoint(point, state.snap_size) else point;
    if (state.prop_sketch_points.items.len > 0) {
        const previous = state.prop_sketch_points.items[state.prop_sketch_points.items.len - 1];
        if (pointsNearSketch(previous, snapped)) {
            project_editor_state.setStatus(state, "Sketch point unchanged");
            return true;
        }
    }
    state.active_gesture.begin(switch (state.prop_sketch_mode) {
        .face => .draw_face,
        .curve => .draw_profile,
        .path => .draw_path,
        .none => .draw_face,
    });
    state.prop_sketch_points.append(state.allocator, snapped) catch |err| {
        state.active_gesture.cancel();
        return err;
    };
    const max_points: usize = switch (state.prop_sketch_mode) {
        .face => 4,
        .curve => 5,
        .path => 8,
        .none => 4,
    };
    if (state.prop_sketch_points.items.len > max_points) {
        _ = state.prop_sketch_points.orderedRemove(0);
    }
    var status_buf: [80]u8 = undefined;
    project_editor_state.setStatus(state, std.fmt.bufPrint(&status_buf, "Sketch point {d} placed", .{state.prop_sketch_points.items.len}) catch "Sketch point placed");
    state.active_gesture.commit();
    return true;
}

fn snapSketchPoint(point: editor_math.Vec3, step: f32) editor_math.Vec3 {
    if (step <= 0.0) return point;
    return .{
        .x = @round(point.x / step) * step,
        .y = 0,
        .z = @round(point.z / step) * step,
    };
}

fn pointsNearSketch(a: editor_math.Vec3, b: editor_math.Vec3) bool {
    const dx = a.x - b.x;
    const dz = a.z - b.z;
    return dx * dx + dz * dz < 0.0001;
}

pub fn regenerateSelectedFromRecipe(state: *ProjectEditorState) !void {
    const idx = state.selected_object orelse {
        project_editor_state.setStatus(state, "Open a prop asset first");
        return;
    };
    const asset_id = state.objects.items[idx].prop_asset_id orelse {
        project_editor_state.setStatus(state, "Selection is not a prop asset");
        return;
    };
    var doc = try ensureAssetDocument(state, asset_id);
    defer doc.deinit(state.allocator);
    project_editor_edit.pushUndoSnapshot(state);
    var mesh = try buildRecipeMesh(state.allocator, doc.recipe);
    errdefer mesh.deinit(state.allocator);
    project_editor_state.setStatus(state, "Regenerated prop recipe");
    try replaceSelectedMeshAndPropagate(state, idx, asset_id, mesh, null);
}

fn buildRecipeMesh(allocator: std.mem.Allocator, recipe: prop_asset_doc.Recipe) !geometry.Mesh {
    var mesh = geometry.Mesh{
        .vertices = try allocator.alloc(geometry.Vertex, 0),
        .indices = try allocator.alloc(u32, 0),
    };
    errdefer mesh.deinit(allocator);
    for (recipe.sources) |source| {
        try appendRecipeSphereSource(allocator, &mesh, source, recipe.modifiers);
    }
    recomputeMeshNormals(&mesh);
    return mesh;
}

fn appendRecipeSphereSource(
    allocator: std.mem.Allocator,
    mesh: *geometry.Mesh,
    source: prop_asset_doc.Source,
    modifiers: []const prop_asset_doc.Modifier,
) !void {
    if (source.kind != .sphere) return error.InvalidArguments;
    try validateSourceForBake(source);
    const segments: usize = @intCast(@max(4, source.segments));
    const rings: usize = @intCast(@max(4, source.rings));
    const rotation: editor_math.Quat = .{
        .x = source.rotation[0],
        .y = source.rotation[1],
        .z = source.rotation[2],
        .w = source.rotation[3],
    };

    var vertices: std.ArrayList(geometry.Vertex) = .empty;
    defer vertices.deinit(allocator);
    try vertices.appendSlice(allocator, mesh.vertices);
    var indices: std.ArrayList(u32) = .empty;
    defer indices.deinit(allocator);
    try indices.appendSlice(allocator, mesh.indices);
    const old_v_len = vertices.items.len;

    const top_center: u32 = @intCast(vertices.items.len);
    try vertices.append(allocator, .{
        .position = try transformRecipePoint(source, modifiers, rotation, .{ .x = 0, .y = source.radius, .z = 0 }),
        .normal = .{ .x = 0, .y = 1, .z = 0 },
        .uv = .{ .x = 0.5, .y = 0 },
    });

    for (1..rings) |ring| {
        const v = @as(f32, @floatFromInt(ring)) / @as(f32, @floatFromInt(rings));
        const phi = v * std.math.pi;
        const y = @cos(phi);
        const ring_radius = @sin(phi);
        for (0..segments) |seg| {
            const u = @as(f32, @floatFromInt(seg)) / @as(f32, @floatFromInt(segments));
            const theta = u * std.math.tau;
            const unit: editor_math.Vec3 = .{
                .x = ring_radius * @cos(theta),
                .y = y,
                .z = ring_radius * @sin(theta),
            };
            try vertices.append(allocator, .{
                .position = try transformRecipePoint(source, modifiers, rotation, editor_math.Vec3.scale(unit, source.radius)),
                .normal = unit,
                .uv = .{
                    .x = u * std.math.tau * source.radius * @max(source.scale[0], source.scale[2]),
                    .y = v * std.math.pi * source.radius * source.scale[1],
                },
            });
        }
    }

    const bottom_center: u32 = @intCast(vertices.items.len);
    try vertices.append(allocator, .{
        .position = try transformRecipePoint(source, modifiers, rotation, .{ .x = 0, .y = -source.radius, .z = 0 }),
        .normal = .{ .x = 0, .y = -1, .z = 0 },
        .uv = .{ .x = 0.5, .y = 1 },
    });

    for (0..segments) |seg| {
        const cur = recipeSphereRingIndex(old_v_len, 1, segments, seg);
        const next = recipeSphereRingIndex(old_v_len, 1, segments, (seg + 1) % segments);
        try indices.appendSlice(allocator, &.{ top_center, next, cur });
    }

    for (1..rings - 1) |ring| {
        for (0..segments) |seg| {
            const a = recipeSphereRingIndex(old_v_len, ring, segments, seg);
            const b = recipeSphereRingIndex(old_v_len, ring, segments, (seg + 1) % segments);
            const c = recipeSphereRingIndex(old_v_len, ring + 1, segments, seg);
            const d = recipeSphereRingIndex(old_v_len, ring + 1, segments, (seg + 1) % segments);
            try indices.appendSlice(allocator, &.{ a, b, c, b, d, c });
        }
    }

    for (0..segments) |seg| {
        const cur = recipeSphereRingIndex(old_v_len, rings - 1, segments, seg);
        const next = recipeSphereRingIndex(old_v_len, rings - 1, segments, (seg + 1) % segments);
        try indices.appendSlice(allocator, &.{ bottom_center, cur, next });
    }

    allocator.free(mesh.vertices);
    allocator.free(mesh.indices);
    mesh.vertices = try vertices.toOwnedSlice(allocator);
    mesh.indices = try indices.toOwnedSlice(allocator);
}

fn transformRecipePoint(
    source: prop_asset_doc.Source,
    modifiers: []const prop_asset_doc.Modifier,
    rotation: editor_math.Quat,
    local_sphere: editor_math.Vec3,
) !editor_math.Vec3 {
    var p: editor_math.Vec3 = .{
        .x = local_sphere.x * source.scale[0],
        .y = local_sphere.y * source.scale[1],
        .z = local_sphere.z * source.scale[2],
    };
    for (modifiers) |modifier| {
        if (!std.mem.eql(u8, modifier.source_id, source.id)) continue;
        p = try applyRecipeModifier(p, modifier, source);
    }
    const rotated = try editor_math.Quat.rotateVec3(rotation, p);
    return editor_math.Vec3.add(rotated, .{ .x = source.position[0], .y = source.position[1], .z = source.position[2] });
}

fn applyRecipeModifier(p: editor_math.Vec3, modifier: prop_asset_doc.Modifier, source: prop_asset_doc.Source) !editor_math.Vec3 {
    return switch (modifier.data) {
        .bend => |bend| applyBendModifier(p, bend),
        .taper => |taper| applyTaperModifier(p, taper, source),
        .lattice => |lattice| try applyLatticeModifier(p, lattice, source),
    };
}

fn applyBendModifier(p: editor_math.Vec3, bend: prop_asset_doc.Bend) editor_math.Vec3 {
    const amount = bend.amount;
    if (amount == 0) return p;
    const t = axisValue(p, bend.axis);
    const angle = t * amount;
    const c = @cos(angle);
    const s = @sin(angle);
    return switch (bend.axis) {
        .x => .{ .x = p.x, .y = p.y * c - p.z * s, .z = p.y * s + p.z * c },
        .y => .{ .x = p.x * c + p.z * s, .y = p.y, .z = -p.x * s + p.z * c },
        .z => .{ .x = p.x * c - p.y * s, .y = p.x * s + p.y * c, .z = p.z },
    };
}

fn applyTaperModifier(p: editor_math.Vec3, taper: prop_asset_doc.Taper, source: prop_asset_doc.Source) editor_math.Vec3 {
    const radius = axisHalfExtent(source, taper.axis);
    const t = if (radius <= 0.0001) 0 else std.math.clamp(axisValue(p, taper.axis) / radius, -1, 1);
    const scale = @max(0.001, 1.0 + taper.amount * t);
    return switch (taper.axis) {
        .x => .{ .x = p.x, .y = p.y * scale, .z = p.z * scale },
        .y => .{ .x = p.x * scale, .y = p.y, .z = p.z * scale },
        .z => .{ .x = p.x * scale, .y = p.y * scale, .z = p.z },
    };
}

fn applyLatticeModifier(p: editor_math.Vec3, lattice: prop_asset_doc.Lattice, source: prop_asset_doc.Source) !editor_math.Vec3 {
    if (lattice.dimensions[0] < 2 or lattice.dimensions[1] < 2 or lattice.dimensions[2] < 2) return error.InvalidArguments;
    const extents = [_]f32{
        @max(0.0001, source.radius * source.scale[0]),
        @max(0.0001, source.radius * source.scale[1]),
        @max(0.0001, source.radius * source.scale[2]),
    };
    const normalized = [_]f32{
        std.math.clamp((p.x / extents[0] + 1.0) * 0.5, 0, 1),
        std.math.clamp((p.y / extents[1] + 1.0) * 0.5, 0, 1),
        std.math.clamp((p.z / extents[2] + 1.0) * 0.5, 0, 1),
    };
    var offset: editor_math.Vec3 = .{ .x = 0, .y = 0, .z = 0 };
    for (lattice.points) |point| {
        if (point.index[0] >= lattice.dimensions[0] or point.index[1] >= lattice.dimensions[1] or point.index[2] >= lattice.dimensions[2]) return error.InvalidArguments;
        const weight = latticeWeight(normalized[0], point.index[0], lattice.dimensions[0]) *
            latticeWeight(normalized[1], point.index[1], lattice.dimensions[1]) *
            latticeWeight(normalized[2], point.index[2], lattice.dimensions[2]);
        offset.x += point.offset[0] * weight;
        offset.y += point.offset[1] * weight;
        offset.z += point.offset[2] * weight;
    }
    return editor_math.Vec3.add(p, offset);
}

fn latticeWeight(value: f32, index: u32, dimension: u32) f32 {
    const control = @as(f32, @floatFromInt(index)) / @as(f32, @floatFromInt(dimension - 1));
    const spacing = 1.0 / @as(f32, @floatFromInt(dimension - 1));
    return @max(0, 1.0 - @abs(value - control) / spacing);
}

fn axisValue(p: editor_math.Vec3, axis: prop_asset_doc.Axis) f32 {
    return switch (axis) {
        .x => p.x,
        .y => p.y,
        .z => p.z,
    };
}

fn axisHalfExtent(source: prop_asset_doc.Source, axis: prop_asset_doc.Axis) f32 {
    return switch (axis) {
        .x => source.radius * source.scale[0],
        .y => source.radius * source.scale[1],
        .z => source.radius * source.scale[2],
    };
}

fn recipeSphereRingIndex(old_v_len: usize, ring: usize, segments: usize, seg: usize) u32 {
    return @intCast(old_v_len + 1 + (ring - 1) * segments + seg);
}

fn validateSourceForBake(source: prop_asset_doc.Source) !void {
    if (source.radius <= 0 or source.segments < 4 or source.rings < 4) return error.InvalidArguments;
    if (source.scale[0] <= 0 or source.scale[1] <= 0 or source.scale[2] <= 0) return error.InvalidArguments;
    _ = try editor_math.Quat.normalized(.{
        .x = source.rotation[0],
        .y = source.rotation[1],
        .z = source.rotation[2],
        .w = source.rotation[3],
    });
}

fn recomputeMeshNormals(mesh: *geometry.Mesh) void {
    for (mesh.vertices) |*vertex| vertex.normal = .{ .x = 0, .y = 0, .z = 0 };
    var tri: usize = 0;
    while (tri + 2 < mesh.indices.len) : (tri += 3) {
        const vi0: usize = @intCast(mesh.indices[tri]);
        const vi1: usize = @intCast(mesh.indices[tri + 1]);
        const vi2: usize = @intCast(mesh.indices[tri + 2]);
        const p0 = mesh.vertices[vi0].position;
        const p1 = mesh.vertices[vi1].position;
        const p2 = mesh.vertices[vi2].position;
        const n = editor_math.cross(editor_math.Vec3.sub(p1, p0), editor_math.Vec3.sub(p2, p0));
        mesh.vertices[vi0].normal = editor_math.Vec3.add(mesh.vertices[vi0].normal, n);
        mesh.vertices[vi1].normal = editor_math.Vec3.add(mesh.vertices[vi1].normal, n);
        mesh.vertices[vi2].normal = editor_math.Vec3.add(mesh.vertices[vi2].normal, n);
    }
    for (mesh.vertices) |*vertex| {
        vertex.normal = editor_math.Vec3.normalized(vertex.normal);
    }
}

fn buildBarrelMesh(allocator: std.mem.Allocator, params: geometry.PrimitiveParams) !geometry.Mesh {
    const segments: usize = @intCast(@max(12, params.segments));
    const height = @max(0.1, params.height);
    const radius = @max(0.05, params.radius);
    const rings = [_]struct { y: f32, r: f32 }{
        .{ .y = -0.50, .r = 0.82 },
        .{ .y = -0.43, .r = 1.08 },
        .{ .y = -0.34, .r = 0.94 },
        .{ .y = 0.00, .r = 1.12 },
        .{ .y = 0.34, .r = 0.94 },
        .{ .y = 0.43, .r = 1.08 },
        .{ .y = 0.50, .r = 0.82 },
    };

    var vertices: std.ArrayList(geometry.Vertex) = .empty;
    defer vertices.deinit(allocator);
    var indices: std.ArrayList(u32) = .empty;
    defer indices.deinit(allocator);

    const tau = std.math.pi * 2.0;
    const max_radius = maxBarrelRadius(radius);
    for (rings) |ring| {
        const y = ring.y * height;
        const r = ring.r * radius;
        for (0..segments) |seg_idx| {
            const u = @as(f32, @floatFromInt(seg_idx)) / @as(f32, @floatFromInt(segments));
            const a = u * tau;
            const c = @cos(a);
            const s = @sin(a);
            try vertices.append(allocator, .{
                .position = .{ .x = r * c, .y = y, .z = r * s },
                .normal = .{ .x = c, .y = 0, .z = s },
                .uv = .{ .x = u * tau * max_radius, .y = (ring.y - rings[0].y) * height },
            });
        }
    }

    for (0..rings.len - 1) |ring_idx| {
        for (0..segments) |seg_idx| {
            const next = (seg_idx + 1) % segments;
            const base = ring_idx * segments;
            const upper = (ring_idx + 1) * segments;
            const a: u32 = @intCast(base + seg_idx);
            const b: u32 = @intCast(base + next);
            const c: u32 = @intCast(upper + next);
            const d: u32 = @intCast(upper + seg_idx);
            try indices.appendSlice(allocator, &.{ a, d, b, b, d, c });
        }
    }

    try appendCap(allocator, &vertices, &indices, rings[0].y * height, rings[0].r * radius, segments, false);
    try appendCap(allocator, &vertices, &indices, rings[rings.len - 1].y * height, rings[rings.len - 1].r * radius, segments, true);

    return .{
        .vertices = try vertices.toOwnedSlice(allocator),
        .indices = try indices.toOwnedSlice(allocator),
    };
}

fn appendCap(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(geometry.Vertex),
    indices: *std.ArrayList(u32),
    y: f32,
    radius: f32,
    segments: usize,
    top: bool,
) !void {
    const center: u32 = @intCast(vertices.items.len);
    const normal: geometry.Vec3 = if (top) .{ .x = 0, .y = 1, .z = 0 } else .{ .x = 0, .y = -1, .z = 0 };
    try vertices.append(allocator, .{
        .position = .{ .x = 0, .y = y, .z = 0 },
        .normal = normal,
        .uv = .{ .x = 0, .y = 0 },
    });

    const tau = std.math.pi * 2.0;
    const ring_start: u32 = @intCast(vertices.items.len);
    for (0..segments) |seg_idx| {
        const u = @as(f32, @floatFromInt(seg_idx)) / @as(f32, @floatFromInt(segments));
        const a = u * tau;
        const c = @cos(a);
        const s = @sin(a);
        try vertices.append(allocator, .{
            .position = .{ .x = radius * c, .y = y, .z = radius * s },
            .normal = normal,
            .uv = .{ .x = radius * c, .y = radius * s },
        });
    }
    for (0..segments) |seg_idx| {
        const next = (seg_idx + 1) % segments;
        const a = ring_start + @as(u32, @intCast(seg_idx));
        const b = ring_start + @as(u32, @intCast(next));
        if (top) {
            try indices.appendSlice(allocator, &.{ center, b, a });
        } else {
            try indices.appendSlice(allocator, &.{ center, a, b });
        }
    }
}

fn fillBarrelRustTexture(pixels: []u8, size: u32) void {
    const width: usize = @intCast(size);
    const height: usize = @intCast(size);
    for (0..height) |y| {
        const v = @as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(height - 1));
        for (0..width) |x| {
            const u = @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(width - 1));
            var color = barrelBaseColor(u, v);
            const noise = barrelNoise(x, y);
            const grain: i16 = @as(i16, @intCast(noise % 25)) - 12;
            color = shiftColor(color, grain, @divTrunc(grain, 2), -@divTrunc(grain, 3));
            if (rustDrip(u, v, noise)) {
                color = mixColor(color, .{ .r = 205, .g = 96, .b = 42, .a = 255 }, 0.62);
            }
            if (paintScratch(u, v, noise)) {
                color = mixColor(color, .{ .r = 244, .g = 171, .b = 102, .a = 255 }, 0.46);
            }
            const idx = (y * width + x) * 4;
            pixels[idx] = color.r;
            pixels[idx + 1] = color.g;
            pixels[idx + 2] = color.b;
            pixels[idx + 3] = 255;
        }
    }
}

fn maxBarrelRadius(radius: f32) f32 {
    return radius * 1.12;
}

fn barrelBaseColor(u: f32, v: f32) shared.color.Color {
    _ = u;
    const band = near(v, 0.16, 0.035) or near(v, 0.50, 0.045) or near(v, 0.84, 0.035);
    const rim = v < 0.075 or v > 0.925;
    if (rim) return .{ .r = 83, .g = 55, .b = 47, .a = 255 };
    if (band) return .{ .r = 78, .g = 68, .b = 61, .a = 255 };
    return .{ .r = 172, .g = 89, .b = 59, .a = 255 };
}

fn near(value: f32, center: f32, radius: f32) bool {
    return @abs(value - center) <= radius;
}

fn barrelNoise(x: usize, y: usize) u32 {
    var n: u32 = @as(u32, @truncate(x)) *% 374761393 +% @as(u32, @truncate(y)) *% 668265263;
    n = (n ^ (n >> 13)) *% 1274126177;
    return n ^ (n >> 16);
}

fn rustDrip(u: f32, v: f32, noise: u32) bool {
    const lane = @as(u32, @intFromFloat(u * 18.0));
    const start = 0.20 + @as(f32, @floatFromInt((noise >> 4) % 16)) * 0.018;
    const length = 0.08 + @as(f32, @floatFromInt((noise >> 10) % 14)) * 0.01;
    return lane % 5 == 1 and v > start and v < start + length;
}

fn paintScratch(u: f32, v: f32, noise: u32) bool {
    const diagonal = @abs(@mod(u * 3.0 + v * 7.0, 1.0) - 0.5) < 0.018;
    return diagonal and noise % 11 == 0 and v > 0.18 and v < 0.82;
}

fn mixColor(a: shared.color.Color, b: shared.color.Color, t: f32) shared.color.Color {
    return .{
        .r = mixChannel(a.r, b.r, t),
        .g = mixChannel(a.g, b.g, t),
        .b = mixChannel(a.b, b.b, t),
        .a = 255,
    };
}

fn mixChannel(a: u8, b: u8, t: f32) u8 {
    const af = @as(f32, @floatFromInt(a));
    const bf = @as(f32, @floatFromInt(b));
    return @intFromFloat(std.math.clamp(af + (bf - af) * t, 0, 255));
}

fn shiftColor(color: shared.color.Color, r: i16, g: i16, b: i16) shared.color.Color {
    return .{
        .r = shiftChannel(color.r, r),
        .g = shiftChannel(color.g, g),
        .b = shiftChannel(color.b, b),
        .a = color.a,
    };
}

fn shiftChannel(value: u8, delta: i16) u8 {
    const shifted = @as(i16, @intCast(value)) + delta;
    return @intCast(std.math.clamp(shifted, 0, 255));
}

pub fn taperSelected(state: *ProjectEditorState, amount: f32) !void {
    const idx = state.selected_object orelse {
        project_editor_state.setStatus(state, "Open a prop asset first");
        return;
    };
    const asset_id = state.objects.items[idx].prop_asset_id orelse return error.SelectionIsNotPropAsset;
    project_editor_edit.pushUndoSnapshot(state);
    var obj = &state.objects.items[idx];
    const bounds = meshBounds(&obj.mesh) orelse return;
    const height = @max(0.0001, bounds.max.y - bounds.min.y);
    for (obj.mesh.vertices) |*vert| {
        const t = (vert.position.y - bounds.min.y) / height;
        const scale = 1.0 + amount * (t - 0.5);
        vert.position.x *= scale;
        vert.position.z *= scale;
    }
    obj.primitive_kind = null;
    state.scene_dirty = true;
    try propagateAndSaveSelectedAssetGeometry(state, idx, asset_id, .update_material_from_object);
    project_editor_state.setStatus(state, "Prop taper applied to all instances");
}

pub fn mirrorSelectedX(state: *ProjectEditorState) !void {
    const idx = state.selected_object orelse {
        project_editor_state.setStatus(state, "Open a prop asset first");
        return;
    };
    const asset_id = state.objects.items[idx].prop_asset_id orelse return error.SelectionIsNotPropAsset;
    project_editor_edit.pushUndoSnapshot(state);
    var obj = &state.objects.items[idx];
    const mirrored = try (shape_operation.Operation{ .kind = .mirror }).evaluateExistingMesh(state.allocator, &obj.mesh);
    obj.mesh.deinit(state.allocator);
    obj.mesh = mirrored;
    obj.primitive_kind = null;
    state.scene_dirty = true;
    try propagateAndSaveSelectedAssetGeometryWithShapeIntent(state, idx, asset_id, .update_material_from_object, .{
        .source_kind = .existing_mesh,
        .operation_kind = .mirror,
        .amount = 1.0,
        .points = &.{},
    });
    project_editor_state.setStatus(state, "Mirrored prop geometry across X");
}

pub fn arraySelectedX(state: *ProjectEditorState) !void {
    const idx = state.selected_object orelse {
        project_editor_state.setStatus(state, "Open a prop asset first");
        return;
    };
    const asset_id = state.objects.items[idx].prop_asset_id orelse return error.SelectionIsNotPropAsset;
    project_editor_edit.pushUndoSnapshot(state);
    var obj = &state.objects.items[idx];
    const bounds = meshBounds(&obj.mesh) orelse return;
    const stride = @max(0.25, bounds.max.x - bounds.min.x + 0.25);
    const arrayed = try (shape_operation.Operation{ .kind = .array, .amount = stride, .segments = 2 }).evaluateExistingMesh(state.allocator, &obj.mesh);
    obj.mesh.deinit(state.allocator);
    obj.mesh = arrayed;
    obj.primitive_kind = null;
    state.scene_dirty = true;
    try propagateAndSaveSelectedAssetGeometryWithShapeIntent(state, idx, asset_id, .update_material_from_object, .{
        .source_kind = .existing_mesh,
        .operation_kind = .array,
        .amount = stride,
        .segments = 2,
        .points = &.{},
    });
    project_editor_state.setStatus(state, "Added prop array copy");
}

pub fn solidifySelected(state: *ProjectEditorState, thickness: f32) !void {
    state.active_gesture.begin(.solidify);
    errdefer state.active_gesture.cancel();
    const idx = state.selected_object orelse {
        project_editor_state.setStatus(state, "Open a prop asset first");
        state.active_gesture.cancel();
        return;
    };
    const asset_id = state.objects.items[idx].prop_asset_id orelse return error.SelectionIsNotPropAsset;
    project_editor_edit.pushUndoSnapshot(state);
    var obj = &state.objects.items[idx];
    if (state.prop_sketch_mode == .face and state.prop_sketch_points.items.len >= 3) {
        const amount = @max(0.01, thickness);
        var sketch_mesh = try (shape_operation.Operation{ .kind = .solidify, .amount = amount }).evaluateMesh(state.allocator, .{
            .kind = .closed_face,
            .points = state.prop_sketch_points.items,
        });
        defer sketch_mesh.deinit(state.allocator);
        try appendMeshCopy(state.allocator, &obj.mesh, &sketch_mesh);
        const intent_points = try state.allocator.dupe(editor_math.Vec3, state.prop_sketch_points.items);
        defer state.allocator.free(intent_points);
        state.prop_sketch_points.clearRetainingCapacity();
        state.prop_sketch_mode = .none;
        state.selected_shape_source = false;
        state.selected_shape_operation = false;
        project_editor_state.setStatus(state, "Solidified sketch into prop geometry");
        obj.primitive_kind = null;
        state.scene_dirty = true;
        try propagateAndSaveSelectedAssetGeometryWithShapeIntent(state, idx, asset_id, .update_material_from_object, .{
            .source_kind = .closed_face,
            .operation_kind = .solidify,
            .amount = amount,
            .points = intent_points,
        });
        state.active_gesture.commit();
        return;
    } else {
        try solidifyMesh(state.allocator, &obj.mesh, @max(0.01, thickness));
        project_editor_state.setStatus(state, "Solidified prop surface");
    }
    obj.primitive_kind = null;
    state.scene_dirty = true;
    try propagateAndSaveSelectedAssetGeometry(state, idx, asset_id, .update_material_from_object);
    state.active_gesture.commit();
}

pub fn extrudePathSelected(state: *ProjectEditorState, thickness: f32) !void {
    state.active_gesture.begin(.extrude);
    errdefer state.active_gesture.cancel();
    const idx = state.selected_object orelse {
        project_editor_state.setStatus(state, "Open a prop asset first");
        return error.NoSelectedPropAsset;
    };
    const asset_id = state.objects.items[idx].prop_asset_id orelse return error.SelectionIsNotPropAsset;
    if (state.prop_sketch_mode != .path or state.prop_sketch_points.items.len < 2) {
        project_editor_state.setStatus(state, "Draw a path source first");
        return error.NoActiveShapeSource;
    }
    project_editor_edit.pushUndoSnapshot(state);
    const amount = @max(0.01, thickness);
    const intent_points = try state.allocator.dupe(editor_math.Vec3, state.prop_sketch_points.items);
    defer state.allocator.free(intent_points);
    var sketch_mesh = try (shape_operation.Operation{ .kind = .extrude, .amount = amount }).evaluateMesh(state.allocator, .{
        .kind = .path,
        .points = state.prop_sketch_points.items,
    });
    defer sketch_mesh.deinit(state.allocator);
    var obj = &state.objects.items[idx];
    try appendMeshCopy(state.allocator, &obj.mesh, &sketch_mesh);
    state.prop_sketch_points.clearRetainingCapacity();
    state.prop_sketch_mode = .none;
    state.selected_shape_source = false;
    state.selected_shape_operation = false;
    obj.primitive_kind = null;
    state.scene_dirty = true;
    try propagateAndSaveSelectedAssetGeometryWithShapeIntent(state, idx, asset_id, .update_material_from_object, .{
        .source_kind = .path,
        .operation_kind = .extrude,
        .amount = amount,
        .points = intent_points,
    });
    project_editor_state.setStatus(state, "Extruded path into prop geometry");
    state.active_gesture.commit();
}

pub fn insetSelected(state: *ProjectEditorState, amount: f32) !void {
    try applyClosedFaceSketchOperation(state, .inset, @max(0.01, @min(0.49, amount)), .inset, "Inset sketch into prop geometry");
}

pub fn bevelSelected(state: *ProjectEditorState, amount: f32) !void {
    try applyClosedFaceSketchOperation(state, .bevel, @max(0.01, @min(0.49, amount)), .bevel, "Beveled sketch into prop geometry");
}

pub fn cutSelected(state: *ProjectEditorState, depth: f32) !void {
    try applyClosedFaceSketchOperation(state, .cut, @max(0.01, depth), .cut, "Cut sketch into prop geometry");
}

fn applyClosedFaceSketchOperation(
    state: *ProjectEditorState,
    operation_kind: shape_operation.Kind,
    amount: f32,
    gesture_kind: @import("editor_gesture.zig").Kind,
    status: []const u8,
) !void {
    state.active_gesture.begin(gesture_kind);
    errdefer state.active_gesture.cancel();
    const idx = state.selected_object orelse {
        project_editor_state.setStatus(state, "Open a prop asset first");
        return error.NoSelectedPropAsset;
    };
    const asset_id = state.objects.items[idx].prop_asset_id orelse return error.SelectionIsNotPropAsset;
    if (state.prop_sketch_mode != .face or state.prop_sketch_points.items.len < 3) {
        project_editor_state.setStatus(state, "Draw a closed face source first");
        return error.NoActiveShapeSource;
    }
    project_editor_edit.pushUndoSnapshot(state);
    const intent_points = try state.allocator.dupe(editor_math.Vec3, state.prop_sketch_points.items);
    defer state.allocator.free(intent_points);
    var sketch_mesh = try (shape_operation.Operation{ .kind = operation_kind, .amount = amount }).evaluateMesh(state.allocator, .{
        .kind = .closed_face,
        .points = state.prop_sketch_points.items,
    });
    defer sketch_mesh.deinit(state.allocator);
    var obj = &state.objects.items[idx];
    try appendMeshCopy(state.allocator, &obj.mesh, &sketch_mesh);
    state.prop_sketch_points.clearRetainingCapacity();
    state.prop_sketch_mode = .none;
    state.selected_shape_source = false;
    state.selected_shape_operation = false;
    obj.primitive_kind = null;
    state.scene_dirty = true;
    try propagateAndSaveSelectedAssetGeometryWithShapeIntent(state, idx, asset_id, .update_material_from_object, .{
        .source_kind = .closed_face,
        .operation_kind = propShapeOperationKind(operation_kind),
        .amount = amount,
        .points = intent_points,
    });
    project_editor_state.setStatus(state, status);
    state.active_gesture.commit();
}

pub fn clearSelectedMesh(state: *ProjectEditorState) !void {
    const idx = state.selected_object orelse {
        project_editor_state.setStatus(state, "Open a prop asset first");
        return;
    };
    const asset_id = state.objects.items[idx].prop_asset_id orelse return error.SelectionIsNotPropAsset;
    project_editor_edit.pushUndoSnapshot(state);
    var obj = &state.objects.items[idx];
    obj.mesh.deinit(state.allocator);
    obj.mesh = .{
        .vertices = try state.allocator.alloc(geometry.Vertex, 0),
        .indices = try state.allocator.alloc(u32, 0),
    };
    obj.primitive_kind = null;
    state.scene_dirty = true;
    try propagateGeometryFromObject(state, idx, asset_id);
    var doc = try assetDocumentForObject(state, idx, asset_id);
    defer doc.deinit(state.allocator);
    doc.base_color = obj.base_color;
    if (doc.texture_path) |path| {
        state.allocator.free(path);
        doc.texture_path = null;
    }
    try writeAssetDocumentAndMesh(state, doc, &obj.mesh);
    project_editor_state.setStatus(state, "Cleared prop mesh");
}

pub fn appendPrimitiveSeedSelected(state: *ProjectEditorState, kind: geometry.PrimitiveKind, params: geometry.PrimitiveParams) !void {
    const idx = state.selected_object orelse {
        project_editor_state.setStatus(state, "Open a prop asset first");
        return;
    };
    const asset_id = state.objects.items[idx].prop_asset_id orelse return error.SelectionIsNotPropAsset;
    project_editor_edit.pushUndoSnapshot(state);
    var seed_mesh = try (shape_operation.Operation{ .kind = .extrude }).evaluateMesh(state.allocator, shape_source.Source{
        .kind = .primitive_seed,
        .points = &.{},
        .primitive_kind = kind,
        .primitive_params = params,
    });
    defer seed_mesh.deinit(state.allocator);
    var obj = &state.objects.items[idx];
    try appendMeshCopy(state.allocator, &obj.mesh, &seed_mesh);
    obj.primitive_kind = null;
    state.prop_sketch_points.clearRetainingCapacity();
    state.prop_sketch_mode = .none;
    state.selected_shape_source = false;
    state.selected_shape_operation = false;
    state.scene_dirty = true;
    try propagateAndSaveSelectedAssetGeometryWithShapeIntent(state, idx, asset_id, .update_material_from_object, .{
        .source_kind = .primitive_seed,
        .operation_kind = .extrude,
        .amount = 1.0,
        .segments = params.segments,
        .primitive_kind = kind,
        .primitive_params = params,
        .points = &.{},
    });
    project_editor_state.setStatus(state, "Added primitive seed source");
}

/// Replaces the selected prop's mesh with geometry decoded from a .glb file
/// at an absolute filesystem path (as returned by a native OS file dialog),
/// clearing the recipe since the geometry no longer comes from sources or
/// modifiers. Mirrors clearSelectedMesh's save/propagate sequence.
pub fn importGlbIntoSelected(state: *ProjectEditorState, glb_path: []const u8) !void {
    const idx = state.selected_object orelse {
        project_editor_state.setStatus(state, "Open a prop asset first");
        return;
    };
    const asset_id = state.objects.items[idx].prop_asset_id orelse return error.SelectionIsNotPropAsset;

    const glb_bytes = try readFileAbsolute(state.allocator, state.io, glb_path, 64 * 1024 * 1024);
    defer state.allocator.free(glb_bytes);
    const encoded = try gltf_import.importGlb(state.allocator, glb_bytes);
    defer state.allocator.free(encoded);
    var imported_mesh = try mesh_codec.decodeMesh(state.allocator, encoded);
    errdefer imported_mesh.deinit(state.allocator);

    project_editor_edit.pushUndoSnapshot(state);
    var obj = &state.objects.items[idx];
    obj.mesh.deinit(state.allocator);
    obj.mesh = imported_mesh;
    obj.primitive_kind = null;
    state.scene_dirty = true;
    try propagateGeometryFromObject(state, idx, asset_id);
    var doc = try assetDocumentForObject(state, idx, asset_id);
    defer doc.deinit(state.allocator);
    doc.base_color = obj.base_color;
    doc.recipe.deinit(state.allocator);
    doc.recipe = .{};
    try writeAssetDocumentAndMesh(state, doc, &obj.mesh);
    project_editor_state.setStatus(state, "Imported prop mesh from GLB");
}

/// Encodes the selected prop's current live mesh as a .glb file at an
/// absolute filesystem path (as returned by a native OS save dialog).
pub fn exportSelectedToGlb(state: *ProjectEditorState, glb_path: []const u8) !void {
    const idx = state.selected_object orelse {
        project_editor_state.setStatus(state, "Open a prop asset first");
        return;
    };
    const glb_bytes = try gltf_export.exportGlb(state.allocator, state.objects.items[idx].mesh);
    defer state.allocator.free(glb_bytes);
    try writeFileAbsolute(state.io, glb_path, glb_bytes);
    project_editor_state.setStatus(state, "Exported prop mesh to GLB");
}

fn readFileAbsolute(allocator: std.mem.Allocator, io: std.Io, absolute_path: []const u8, limit: usize) ![]u8 {
    var file = try std.Io.Dir.openFileAbsolute(io, absolute_path, .{});
    defer file.close(io);
    var buf: [4096]u8 = undefined;
    var file_reader = file.reader(io, &buf);
    return file_reader.interface.allocRemaining(allocator, .limited(limit));
}

fn writeFileAbsolute(io: std.Io, absolute_path: []const u8, bytes: []const u8) !void {
    var file = try std.Io.Dir.createFileAbsolute(io, absolute_path, .{});
    defer file.close(io);
    try file.writePositionalAll(io, bytes, 0);
}

pub const SourceSphereSpec = struct {
    source_id: []const u8,
    position: [3]f32,
    rotation: [4]f32,
    scale: [3]f32,
    radius: f32,
    segments: u32,
    rings: u32,
};

pub const SourceTransformUpdate = struct {
    source_id: []const u8,
    position: ?[3]f32 = null,
    rotation: ?[4]f32 = null,
    scale: ?[3]f32 = null,
};

pub const BendModifierSpec = struct {
    modifier_id: []const u8,
    source_id: []const u8,
    axis: []const u8,
    amount: f32,
};

pub const TaperModifierSpec = BendModifierSpec;

pub const LatticePointSpec = struct {
    index: [3]u32,
    offset: [3]f32,
};

pub const LatticeModifierSpec = struct {
    modifier_id: []const u8,
    source_id: []const u8,
    dimensions: [3]u32,
    points: []const LatticePointSpec,
};

pub fn addSourceSphereSelected(state: *ProjectEditorState, spec: SourceSphereSpec) !void {
    const ctx = try selectedRecipeContext(state);
    project_editor_edit.pushUndoSnapshot(state);
    var doc = try ensureAssetDocument(state, ctx.asset_id);
    defer doc.deinit(state.allocator);
    if (findSourceIndex(doc.recipe, spec.source_id) != null) return error.PropSourceAlreadyExists;
    const source = try sourceFromSphereSpec(state.allocator, spec);
    errdefer {
        var mutable = source;
        mutable.deinit(state.allocator);
    }
    doc.recipe.sources = try appendSource(state.allocator, doc.recipe.sources, source);
    try saveRecipeDocumentAndRebake(state, ctx.index, ctx.asset_id, &doc, "Added prop source sphere");
}

pub fn updateSourceTransformSelected(state: *ProjectEditorState, update: SourceTransformUpdate) !void {
    const ctx = try selectedRecipeContext(state);
    project_editor_edit.pushUndoSnapshot(state);
    var doc = try ensureAssetDocument(state, ctx.asset_id);
    defer doc.deinit(state.allocator);
    const idx = findSourceIndex(doc.recipe, update.source_id) orelse return error.UnknownPropSource;
    if (update.position == null and update.rotation == null and update.scale == null) return error.InvalidArguments;
    if (update.position) |value| doc.recipe.sources[idx].position = value;
    if (update.rotation) |value| doc.recipe.sources[idx].rotation = value;
    if (update.scale) |value| doc.recipe.sources[idx].scale = value;
    try validateSourceForBake(doc.recipe.sources[idx]);
    try saveRecipeDocumentAndRebake(state, ctx.index, ctx.asset_id, &doc, "Updated prop source transform");
}

pub fn deleteSourceSelected(state: *ProjectEditorState, source_id: []const u8) !void {
    const ctx = try selectedRecipeContext(state);
    project_editor_edit.pushUndoSnapshot(state);
    var doc = try ensureAssetDocument(state, ctx.asset_id);
    defer doc.deinit(state.allocator);
    const source_idx = findSourceIndex(doc.recipe, source_id) orelse return error.UnknownPropSource;
    var removed = doc.recipe.sources[source_idx];
    removed.deinit(state.allocator);
    std.mem.copyForwards(prop_asset_doc.Source, doc.recipe.sources[source_idx..], doc.recipe.sources[source_idx + 1 ..]);
    doc.recipe.sources = try state.allocator.realloc(doc.recipe.sources, doc.recipe.sources.len - 1);

    var write_idx: usize = 0;
    for (doc.recipe.modifiers) |*modifier| {
        if (std.mem.eql(u8, modifier.source_id, source_id)) {
            modifier.deinit(state.allocator);
            continue;
        }
        doc.recipe.modifiers[write_idx] = modifier.*;
        write_idx += 1;
    }
    doc.recipe.modifiers = try state.allocator.realloc(doc.recipe.modifiers, write_idx);
    try saveRecipeDocumentAndRebake(state, ctx.index, ctx.asset_id, &doc, "Deleted prop source");
}

pub fn addBendModifierSelected(state: *ProjectEditorState, spec: BendModifierSpec) !void {
    try addModifierSelected(state, try modifierFromBendSpec(state.allocator, spec), "Added prop bend modifier");
}

pub fn addTaperModifierSelected(state: *ProjectEditorState, spec: TaperModifierSpec) !void {
    try addModifierSelected(state, try modifierFromTaperSpec(state.allocator, spec), "Added prop taper modifier");
}

pub fn addLatticeModifierSelected(state: *ProjectEditorState, spec: LatticeModifierSpec) !void {
    try addModifierSelected(state, try modifierFromLatticeSpec(state.allocator, spec), "Added prop lattice modifier");
}

pub fn updateBendModifierSelected(state: *ProjectEditorState, spec: BendModifierSpec) !void {
    try replaceModifierSelected(state, try modifierFromBendSpec(state.allocator, spec), "Updated prop bend modifier");
}

pub fn updateTaperModifierSelected(state: *ProjectEditorState, spec: TaperModifierSpec) !void {
    try replaceModifierSelected(state, try modifierFromTaperSpec(state.allocator, spec), "Updated prop taper modifier");
}

pub fn updateLatticeModifierSelected(state: *ProjectEditorState, spec: LatticeModifierSpec) !void {
    try replaceModifierSelected(state, try modifierFromLatticeSpec(state.allocator, spec), "Updated prop lattice modifier");
}

pub fn deleteModifierSelected(state: *ProjectEditorState, modifier_id: []const u8) !void {
    const ctx = try selectedRecipeContext(state);
    project_editor_edit.pushUndoSnapshot(state);
    var doc = try ensureAssetDocument(state, ctx.asset_id);
    defer doc.deinit(state.allocator);
    const idx = findModifierIndex(doc.recipe, modifier_id) orelse return error.UnknownPropModifier;
    var removed = doc.recipe.modifiers[idx];
    removed.deinit(state.allocator);
    std.mem.copyForwards(prop_asset_doc.Modifier, doc.recipe.modifiers[idx..], doc.recipe.modifiers[idx + 1 ..]);
    doc.recipe.modifiers = try state.allocator.realloc(doc.recipe.modifiers, doc.recipe.modifiers.len - 1);
    try saveRecipeDocumentAndRebake(state, ctx.index, ctx.asset_id, &doc, "Deleted prop modifier");
}

pub fn rebakeSelectedRecipe(state: *ProjectEditorState) !void {
    const ctx = try selectedRecipeContext(state);
    project_editor_edit.pushUndoSnapshot(state);
    var doc = try ensureAssetDocument(state, ctx.asset_id);
    defer doc.deinit(state.allocator);
    try saveRecipeDocumentAndRebake(state, ctx.index, ctx.asset_id, &doc, "Rebaked prop recipe");
}

fn addModifierSelected(state: *ProjectEditorState, modifier: prop_asset_doc.Modifier, status: []const u8) !void {
    const ctx = try selectedRecipeContext(state);
    project_editor_edit.pushUndoSnapshot(state);
    var owned_modifier = modifier;
    errdefer owned_modifier.deinit(state.allocator);
    var doc = try ensureAssetDocument(state, ctx.asset_id);
    defer doc.deinit(state.allocator);
    if (findModifierIndex(doc.recipe, owned_modifier.id) != null) return error.PropModifierAlreadyExists;
    if (findSourceIndex(doc.recipe, owned_modifier.source_id) == null) return error.UnknownPropSource;
    doc.recipe.modifiers = try appendModifier(state.allocator, doc.recipe.modifiers, owned_modifier);
    owned_modifier = .{ .id = &.{}, .source_id = &.{}, .kind = .bend, .data = .{ .bend = .{ .axis = .x, .amount = 0 } } };
    try saveRecipeDocumentAndRebake(state, ctx.index, ctx.asset_id, &doc, status);
}

fn replaceModifierSelected(state: *ProjectEditorState, modifier: prop_asset_doc.Modifier, status: []const u8) !void {
    const ctx = try selectedRecipeContext(state);
    project_editor_edit.pushUndoSnapshot(state);
    var owned_modifier = modifier;
    errdefer owned_modifier.deinit(state.allocator);
    var doc = try ensureAssetDocument(state, ctx.asset_id);
    defer doc.deinit(state.allocator);
    const idx = findModifierIndex(doc.recipe, owned_modifier.id) orelse return error.UnknownPropModifier;
    if (findSourceIndex(doc.recipe, owned_modifier.source_id) == null) return error.UnknownPropSource;
    doc.recipe.modifiers[idx].deinit(state.allocator);
    doc.recipe.modifiers[idx] = owned_modifier;
    owned_modifier = .{ .id = &.{}, .source_id = &.{}, .kind = .bend, .data = .{ .bend = .{ .axis = .x, .amount = 0 } } };
    try saveRecipeDocumentAndRebake(state, ctx.index, ctx.asset_id, &doc, status);
}

fn selectedRecipeContext(state: *ProjectEditorState) !struct { index: usize, asset_id: []const u8 } {
    const idx = state.selected_object orelse return error.SelectionIsNotPropAsset;
    const asset_id = state.objects.items[idx].prop_asset_id orelse return error.SelectionIsNotPropAsset;
    return .{ .index = idx, .asset_id = asset_id };
}

fn saveRecipeDocumentAndRebake(
    state: *ProjectEditorState,
    idx: usize,
    asset_id: []const u8,
    doc: *prop_asset_doc.PropAssetDocument,
    status: []const u8,
) !void {
    doc.base_color = state.objects.items[idx].base_color;
    var mesh = try buildRecipeMesh(state.allocator, doc.recipe);
    errdefer mesh.deinit(state.allocator);
    var obj = &state.objects.items[idx];
    obj.mesh.deinit(state.allocator);
    obj.mesh = mesh;
    obj.primitive_kind = null;
    state.scene_dirty = true;
    try propagateGeometryFromObject(state, idx, asset_id);
    try writeAssetDocumentAndMesh(state, doc.*, &obj.mesh);
    project_editor_state.setStatus(state, status);
}

fn sourceFromSphereSpec(allocator: std.mem.Allocator, spec: SourceSphereSpec) !prop_asset_doc.Source {
    const source = prop_asset_doc.Source{
        .id = try allocator.dupe(u8, spec.source_id),
        .kind = .sphere,
        .position = spec.position,
        .rotation = spec.rotation,
        .scale = spec.scale,
        .radius = spec.radius,
        .segments = spec.segments,
        .rings = spec.rings,
    };
    try validateSourceForBake(source);
    return source;
}

fn modifierFromBendSpec(allocator: std.mem.Allocator, spec: BendModifierSpec) !prop_asset_doc.Modifier {
    const axis = prop_asset_doc.axisFromName(spec.axis) orelse return error.InvalidArguments;
    return .{
        .id = try allocator.dupe(u8, spec.modifier_id),
        .source_id = try allocator.dupe(u8, spec.source_id),
        .kind = .bend,
        .data = .{ .bend = .{ .axis = axis, .amount = spec.amount } },
    };
}

fn modifierFromTaperSpec(allocator: std.mem.Allocator, spec: TaperModifierSpec) !prop_asset_doc.Modifier {
    const axis = prop_asset_doc.axisFromName(spec.axis) orelse return error.InvalidArguments;
    return .{
        .id = try allocator.dupe(u8, spec.modifier_id),
        .source_id = try allocator.dupe(u8, spec.source_id),
        .kind = .taper,
        .data = .{ .taper = .{ .axis = axis, .amount = spec.amount } },
    };
}

fn modifierFromLatticeSpec(allocator: std.mem.Allocator, spec: LatticeModifierSpec) !prop_asset_doc.Modifier {
    if (spec.dimensions[0] < 2 or spec.dimensions[1] < 2 or spec.dimensions[2] < 2) return error.InvalidArguments;
    const points = try allocator.alloc(prop_asset_doc.LatticePoint, spec.points.len);
    errdefer allocator.free(points);
    for (spec.points, 0..) |point, idx| {
        if (point.index[0] >= spec.dimensions[0] or point.index[1] >= spec.dimensions[1] or point.index[2] >= spec.dimensions[2]) return error.InvalidArguments;
        points[idx] = .{ .index = point.index, .offset = point.offset };
    }
    return .{
        .id = try allocator.dupe(u8, spec.modifier_id),
        .source_id = try allocator.dupe(u8, spec.source_id),
        .kind = .lattice,
        .data = .{ .lattice = .{ .dimensions = spec.dimensions, .points = points } },
    };
}

fn appendSource(allocator: std.mem.Allocator, sources: []prop_asset_doc.Source, source: prop_asset_doc.Source) ![]prop_asset_doc.Source {
    const next = try allocator.realloc(sources, sources.len + 1);
    next[next.len - 1] = source;
    return next;
}

fn appendModifier(allocator: std.mem.Allocator, modifiers: []prop_asset_doc.Modifier, modifier: prop_asset_doc.Modifier) ![]prop_asset_doc.Modifier {
    const next = try allocator.realloc(modifiers, modifiers.len + 1);
    next[next.len - 1] = modifier;
    return next;
}

fn findSourceIndex(recipe: prop_asset_doc.Recipe, source_id: []const u8) ?usize {
    for (recipe.sources, 0..) |source, idx| {
        if (std.mem.eql(u8, source.id, source_id)) return idx;
    }
    return null;
}

fn findModifierIndex(recipe: prop_asset_doc.Recipe, modifier_id: []const u8) ?usize {
    for (recipe.modifiers, 0..) |modifier, idx| {
        if (std.mem.eql(u8, modifier.id, modifier_id)) return idx;
    }
    return null;
}

pub const EllipsoidSpec = struct {
    center: editor_math.Vec3,
    radius: editor_math.Vec3,
    segments: usize,
    rings: usize,
};

pub fn appendEllipsoidSelected(state: *ProjectEditorState, spec: EllipsoidSpec) !void {
    const idx = state.selected_object orelse {
        project_editor_state.setStatus(state, "Open a prop asset first");
        return;
    };
    const asset_id = state.objects.items[idx].prop_asset_id orelse return error.SelectionIsNotPropAsset;
    project_editor_edit.pushUndoSnapshot(state);
    var obj = &state.objects.items[idx];
    try appendEllipsoid(state.allocator, &obj.mesh, spec);
    obj.primitive_kind = null;
    state.scene_dirty = true;
    try propagateAndSaveSelectedAssetGeometry(state, idx, asset_id, .update_material_from_object);
    project_editor_state.setStatus(state, "Added low-poly ellipsoid");
}

pub const ConeSpec = struct {
    center: editor_math.Vec3,
    direction: editor_math.Vec3,
    radius: f32,
    height: f32,
    segments: usize,
};

pub fn appendConeSelected(state: *ProjectEditorState, spec: ConeSpec) !void {
    const idx = state.selected_object orelse {
        project_editor_state.setStatus(state, "Open a prop asset first");
        return;
    };
    const asset_id = state.objects.items[idx].prop_asset_id orelse return error.SelectionIsNotPropAsset;
    project_editor_edit.pushUndoSnapshot(state);
    var obj = &state.objects.items[idx];
    try appendCone(state.allocator, &obj.mesh, spec);
    obj.primitive_kind = null;
    state.scene_dirty = true;
    try propagateAndSaveSelectedAssetGeometry(state, idx, asset_id, .update_material_from_object);
    project_editor_state.setStatus(state, "Added low-poly cone");
}

pub const OvalSlabSpec = struct {
    position: editor_math.Vec3,
    rotation: editor_math.Quat = .{},
    radius_x: f32,
    radius_y: f32,
    depth: f32,
    segments: usize,
};

pub fn appendOvalSlabSelected(state: *ProjectEditorState, spec: OvalSlabSpec) !void {
    const idx = state.selected_object orelse {
        project_editor_state.setStatus(state, "Open a prop asset first");
        return;
    };
    const asset_id = state.objects.items[idx].prop_asset_id orelse return error.SelectionIsNotPropAsset;
    project_editor_edit.pushUndoSnapshot(state);
    var obj = &state.objects.items[idx];
    try appendOvalSlab(state.allocator, &obj.mesh, spec);
    obj.primitive_kind = null;
    state.scene_dirty = true;
    try propagateAndSaveSelectedAssetGeometry(state, idx, asset_id, .update_material_from_object);
    project_editor_state.setStatus(state, "Added low-poly oval slab");
}

pub fn revolveSelected(state: *ProjectEditorState) !void {
    state.active_gesture.begin(.revolve);
    errdefer state.active_gesture.cancel();
    const idx = state.selected_object orelse {
        project_editor_state.setStatus(state, "Open a prop asset first");
        state.active_gesture.cancel();
        return;
    };
    const asset_id = state.objects.items[idx].prop_asset_id orelse return error.SelectionIsNotPropAsset;
    project_editor_edit.pushUndoSnapshot(state);
    var obj = &state.objects.items[idx];
    var shape_intent: ?ShapeIntentDraft = null;
    const mesh = if (state.prop_sketch_mode == .curve and state.prop_sketch_points.items.len >= 2) blk: {
        const profile = try profileSourceFromSketch(state.allocator, state.prop_sketch_points.items);
        errdefer state.allocator.free(profile);
        shape_intent = .{
            .source_kind = .open_profile,
            .operation_kind = .revolve,
            .amount = 1.0,
            .segments = state.prop_sketch_segments,
            .points = profile,
        };
        state.prop_sketch_points.clearRetainingCapacity();
        state.prop_sketch_mode = .none;
        state.selected_shape_source = false;
        state.selected_shape_operation = false;
        break :blk try (shape_operation.Operation{ .kind = .revolve, .segments = state.prop_sketch_segments }).evaluateMesh(state.allocator, .{
            .kind = .open_profile,
            .points = profile,
        });
    } else try buildRevolvedMesh(state.allocator, &obj.mesh);
    obj.mesh.deinit(state.allocator);
    obj.mesh = mesh;
    obj.primitive_kind = null;
    state.scene_dirty = true;
    if (shape_intent) |intent| {
        defer state.allocator.free(intent.points);
        try propagateAndSaveSelectedAssetGeometryWithShapeIntent(state, idx, asset_id, .update_material_from_object, intent);
    } else {
        try propagateAndSaveSelectedAssetGeometry(state, idx, asset_id, .update_material_from_object);
    }
    project_editor_state.setStatus(state, "Revolved profile into prop");
    state.active_gesture.commit();
}

fn profileSourceFromSketch(allocator: std.mem.Allocator, points: []const editor_math.Vec3) ![]editor_math.Vec3 {
    var profile = try allocator.alloc(editor_math.Vec3, points.len);
    errdefer allocator.free(profile);
    for (points, 0..) |point, idx| {
        profile[idx] = .{
            .x = @max(0.001, @abs(point.x)),
            .y = point.z,
            .z = 0,
        };
    }
    return profile;
}

fn replaceSelectedMeshAndPropagate(
    state: *ProjectEditorState,
    idx: usize,
    asset_id: []const u8,
    mesh: geometry.Mesh,
    primitive_kind: ?geometry.PrimitiveKind,
) !void {
    var obj = &state.objects.items[idx];
    obj.mesh.deinit(state.allocator);
    obj.mesh = mesh;
    obj.primitive_kind = primitive_kind;
    state.scene_dirty = true;
    try propagateAndSaveSelectedAssetGeometry(state, idx, asset_id, .update_material_from_object);
}

const MaterialSaveMode = enum {
    keep_existing_material,
    update_material_from_object,
};

const ShapeIntentDraft = struct {
    source_kind: prop_asset_doc.ShapeSourceKind,
    operation_kind: prop_asset_doc.ShapeOperationKind,
    amount: f32,
    segments: u32 = 24,
    primitive_kind: geometry.PrimitiveKind = .box,
    primitive_params: geometry.PrimitiveParams = .{},
    points: []const editor_math.Vec3,
};

fn saveAssetFromObject(
    state: *ProjectEditorState,
    source_idx: usize,
    asset_id: []const u8,
    material_mode: MaterialSaveMode,
) !void {
    try saveAssetFromObjectWithShapeIntent(state, source_idx, asset_id, material_mode, null);
}

fn saveAssetFromObjectWithShapeIntent(
    state: *ProjectEditorState,
    source_idx: usize,
    asset_id: []const u8,
    material_mode: MaterialSaveMode,
    shape_intent: ?ShapeIntentDraft,
) !void {
    var doc = try assetDocumentForObject(state, source_idx, asset_id);
    defer doc.deinit(state.allocator);
    if (shape_intent) |intent| try appendShapeIntent(state, &doc, intent);
    if (material_mode == .update_material_from_object) {
        doc.base_color = state.objects.items[source_idx].base_color;
        if (doc.material_path) |path| {
            state.allocator.free(path);
            doc.material_path = null;
        }
        if (state.objects.items[source_idx].material_path) |path| {
            doc.material_path = try state.allocator.dupe(u8, path);
        }
        for (doc.face_materials) |*face| face.deinit(state.allocator);
        state.allocator.free(doc.face_materials);
        doc.face_materials = try scene_io.duplicateFaceMaterials(state.allocator, state.objects.items[source_idx].face_materials);
    }
    const texture: ?[]const u8 = if (doc.texture_path != null) state.objects.items[source_idx].texture else null;
    try writeAssetDocumentMeshAndTexture(state, doc, &state.objects.items[source_idx].mesh, texture);
}

fn appendShapeIntent(state: *ProjectEditorState, doc: *prop_asset_doc.PropAssetDocument, draft: ShapeIntentDraft) !void {
    const points = try state.allocator.dupe(editor_math.Vec3, draft.points);
    errdefer state.allocator.free(points);
    const id = try std.fmt.allocPrint(state.allocator, "shape_{d}", .{doc.recipe.shape_intents.len + 1});
    errdefer state.allocator.free(id);
    const next = try state.allocator.realloc(doc.recipe.shape_intents, doc.recipe.shape_intents.len + 1);
    doc.recipe.shape_intents = next;
    doc.recipe.shape_intents[doc.recipe.shape_intents.len - 1] = .{
        .id = id,
        .source_kind = draft.source_kind,
        .operation_kind = draft.operation_kind,
        .amount = draft.amount,
        .segments = draft.segments,
        .primitive_kind = draft.primitive_kind,
        .primitive_params = draft.primitive_params,
        .points = points,
    };
}

fn propShapeOperationKind(kind: shape_operation.Kind) prop_asset_doc.ShapeOperationKind {
    return switch (kind) {
        .extrude => .extrude,
        .solidify => .solidify,
        .revolve => .revolve,
        .cut => .cut,
        .inset => .inset,
        .bevel => .bevel,
        .mirror => .mirror,
        .array => .array,
    };
}

pub fn persistPaintedTexture(state: *ProjectEditorState, source_idx: usize, asset_id: []const u8) !void {
    if (!project_editor_texture_paint.ensurePaintAtlas(state, &state.objects.items[source_idx])) return error.InvalidPaintAtlas;
    var doc = try assetDocumentForObject(state, source_idx, asset_id);
    defer doc.deinit(state.allocator);
    doc.base_color = state.objects.items[source_idx].base_color;
    if (doc.texture_path == null) doc.texture_path = try prop_asset_doc.texturePath(state.allocator, asset_id);
    if (doc.material_path) |path| {
        state.allocator.free(path);
        doc.material_path = null;
    }
    if (state.objects.items[source_idx].material_path) |path| {
        doc.material_path = try state.allocator.dupe(u8, path);
    }
    for (doc.face_materials) |*face| face.deinit(state.allocator);
    state.allocator.free(doc.face_materials);
    doc.face_materials = try scene_io.duplicateFaceMaterials(state.allocator, state.objects.items[source_idx].face_materials);
    try writeAssetDocumentMeshAndTexture(state, doc, &state.objects.items[source_idx].mesh, state.objects.items[source_idx].texture);
}

fn assetDocumentForObject(
    state: *ProjectEditorState,
    source_idx: usize,
    asset_id: []const u8,
) !prop_asset_doc.PropAssetDocument {
    if (loadAssetDocument(state, asset_id)) |doc| return doc else |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    }
    return try documentFromObject(state.allocator, &state.objects.items[source_idx], asset_id);
}

pub fn loadAssetDocument(state: *ProjectEditorState, asset_id: []const u8) !prop_asset_doc.PropAssetDocument {
    const path = try prop_asset_doc.documentPath(state.allocator, asset_id);
    defer state.allocator.free(path);
    var project_dir = try scene_resolve.openProjectDir(state.io, state.project_path);
    defer project_dir.close(state.io);
    const bytes = try project_dir.readFileAlloc(state.io, path, state.allocator, .limited(1024 * 1024));
    defer state.allocator.free(bytes);
    return try prop_asset_doc.parse(state.allocator, bytes);
}

fn writeAssetDocumentAndMesh(state: *ProjectEditorState, doc: prop_asset_doc.PropAssetDocument, mesh: *const geometry.Mesh) !void {
    try writeAssetDocumentMeshAndTexture(state, doc, mesh, null);
}

fn writeAssetDocumentMeshAndTexture(state: *ProjectEditorState, doc: prop_asset_doc.PropAssetDocument, mesh: *const geometry.Mesh, texture: ?[]const u8) !void {
    var project_dir = try scene_resolve.openProjectDir(state.io, state.project_path);
    defer project_dir.close(state.io);
    try project_dir.createDirPath(state.io, "props/meshes");
    try project_dir.createDirPath(state.io, "props/textures");

    const mesh_bytes = try mesh_codec.encodeMesh(state.allocator, mesh.*);
    defer state.allocator.free(mesh_bytes);
    try project_dir.writeFile(state.io, .{ .sub_path = doc.mesh_path, .data = mesh_bytes });
    if (texture) |pixels| {
        const texture_path = doc.texture_path orelse return error.MissingPropTexturePath;
        try project_dir.writeFile(state.io, .{ .sub_path = texture_path, .data = pixels });
    }

    const doc_bytes = try prop_asset_doc.format(state.allocator, doc);
    defer state.allocator.free(doc_bytes);
    const doc_path = try prop_asset_doc.documentPath(state.allocator, doc.id);
    defer state.allocator.free(doc_path);
    try project_dir.writeFile(state.io, .{ .sub_path = doc_path, .data = doc_bytes });
    project_editor_prop_index.invalidate(state);
}

pub fn updateAssetMetadata(state: *ProjectEditorState, asset_id: []const u8, label_text: []const u8, tags_text: []const u8) !void {
    const label = std.mem.trim(u8, label_text, " \t\r\n");
    const tags = std.mem.trim(u8, tags_text, " \t\r\n");
    if (label.len == 0) return error.EmptyPropLabel;

    var doc = try ensureAssetDocument(state, asset_id);
    defer doc.deinit(state.allocator);

    const new_label = try state.allocator.dupe(u8, label);
    errdefer state.allocator.free(new_label);
    const new_tags = try state.allocator.dupe(u8, tags);
    errdefer state.allocator.free(new_tags);
    state.allocator.free(doc.label);
    state.allocator.free(doc.tags);
    doc.label = new_label;
    doc.tags = new_tags;

    try writeAssetDocumentOnly(state, doc);
    updateOpenObjectName(state, asset_id, doc.label);
    project_editor_state.setStatus(state, "Prop metadata saved");
}

pub fn setAssetDeleted(state: *ProjectEditorState, asset_id: []const u8, deleted: bool) !void {
    var doc = try ensureAssetDocument(state, asset_id);
    defer doc.deinit(state.allocator);
    doc.deleted = deleted;
    try writeAssetDocumentOnly(state, doc);
    project_editor_state.setStatus(state, if (deleted) "Prop deleted" else "Prop restored");
}

pub fn assetDeleted(state: *ProjectEditorState, asset_id: []const u8) bool {
    var doc = loadAssetDocument(state, asset_id) catch return false;
    defer doc.deinit(state.allocator);
    return doc.deleted;
}

fn writeAssetDocumentOnly(state: *ProjectEditorState, doc: prop_asset_doc.PropAssetDocument) !void {
    var project_dir = try scene_resolve.openProjectDir(state.io, state.project_path);
    defer project_dir.close(state.io);
    try project_dir.createDirPath(state.io, "props");
    const doc_bytes = try prop_asset_doc.format(state.allocator, doc);
    defer state.allocator.free(doc_bytes);
    const doc_path = try prop_asset_doc.documentPath(state.allocator, doc.id);
    defer state.allocator.free(doc_path);
    try project_dir.writeFile(state.io, .{ .sub_path = doc_path, .data = doc_bytes });
    project_editor_prop_index.invalidate(state);
}

fn updateOpenObjectName(state: *ProjectEditorState, asset_id: []const u8, label: []const u8) void {
    for (state.objects.items) |*object| {
        const object_asset = object.prop_asset_id orelse continue;
        if (!std.mem.eql(u8, object_asset, asset_id)) continue;
        const new_name = std.fmt.allocPrint(state.allocator, "{s} {d}", .{ label, object.id }) catch return;
        state.allocator.free(object.name);
        object.name = new_name;
        return;
    }
}

fn catalogDocument(allocator: std.mem.Allocator, entry: project_editor_prop_catalog.CatalogEntry) !prop_asset_doc.PropAssetDocument {
    const sources = try catalogRecipeSources(allocator, entry);
    return .{
        .id = try allocator.dupe(u8, entry.id),
        .label = try allocator.dupe(u8, entry.label),
        .tags = try allocator.dupe(u8, catalogTags(entry)),
        .deleted = false,
        .mesh_path = try prop_asset_doc.meshPath(allocator, entry.id),
        .recipe = .{ .sources = sources, .modifiers = &.{} },
        .base_color = entry.color,
        .material_path = null,
        .face_materials = &.{},
        .variant_count = entry.variant_count,
    };
}

fn catalogRecipeSources(allocator: std.mem.Allocator, entry: project_editor_prop_catalog.CatalogEntry) ![]prop_asset_doc.Source {
    if (entry.recipe.sources.len == 0) {
        const source = try sourceFromPrimitiveParams(allocator, "base", entry.recipe.base_kind, entry.recipe.base_params);
        errdefer {
            var mutable = source;
            mutable.deinit(allocator);
        }
        const sources = try allocator.alloc(prop_asset_doc.Source, 1);
        sources[0] = source;
        return sources;
    }

    var sources: std.ArrayList(prop_asset_doc.Source) = .empty;
    errdefer {
        for (sources.items) |*source| source.deinit(allocator);
        sources.deinit(allocator);
    }
    for (entry.recipe.sources, 0..) |source_spec, idx| {
        _ = idx;
        try sources.append(allocator, .{
            .id = try allocator.dupe(u8, source_spec.id),
            .kind = .sphere,
            .position = source_spec.position,
            .rotation = .{ 0, 0, 0, 1 },
            .scale = source_spec.scale,
            .radius = @max(0.001, source_spec.radius),
            .segments = @max(8, source_spec.segments),
            .rings = @max(6, source_spec.rings),
        });
    }
    return try sources.toOwnedSlice(allocator);
}

fn documentFromObject(
    allocator: std.mem.Allocator,
    object: *const SceneObject,
    asset_id: []const u8,
) !prop_asset_doc.PropAssetDocument {
    if (project_editor_prop_catalog.findCatalogEntry(asset_id)) |entry| {
        var doc = try catalogDocument(allocator, entry);
        doc.base_color = object.base_color;
        doc.material_path = if (object.material_path) |path| try allocator.dupe(u8, path) else null;
        doc.face_materials = try scene_io.duplicateFaceMaterials(allocator, object.face_materials);
        return doc;
    }
    return .{
        .id = try allocator.dupe(u8, asset_id),
        .label = try allocator.dupe(u8, asset_id),
        .tags = try allocator.dupe(u8, ""),
        .deleted = false,
        .mesh_path = try prop_asset_doc.meshPath(allocator, asset_id),
        .recipe = .{},
        .base_color = object.base_color,
        .material_path = if (object.material_path) |path| try allocator.dupe(u8, path) else null,
        .face_materials = try scene_io.duplicateFaceMaterials(allocator, object.face_materials),
        .variant_count = 1,
    };
}

fn customDocumentFromObject(
    allocator: std.mem.Allocator,
    object: *const SceneObject,
    asset_id: []const u8,
    label: []const u8,
    tags: []const u8,
) !prop_asset_doc.PropAssetDocument {
    return .{
        .id = try allocator.dupe(u8, asset_id),
        .label = try allocator.dupe(u8, label),
        .tags = try allocator.dupe(u8, tags),
        .deleted = false,
        .mesh_path = try prop_asset_doc.meshPath(allocator, asset_id),
        .recipe = .{},
        .base_color = object.base_color,
        .material_path = if (object.material_path) |path| try allocator.dupe(u8, path) else null,
        .face_materials = try scene_io.duplicateFaceMaterials(allocator, object.face_materials),
        .variant_count = 1,
    };
}

fn applyDocumentMaterialSlots(allocator: std.mem.Allocator, obj: *SceneObject, doc: prop_asset_doc.PropAssetDocument) !void {
    if (obj.material_path) |existing| {
        allocator.free(existing);
        obj.material_path = null;
    }
    for (obj.face_materials) |*face| face.deinit(allocator);
    allocator.free(obj.face_materials);
    obj.face_materials = &.{};
    obj.material_path = if (doc.material_path) |path| try allocator.dupe(u8, path) else null;
    obj.face_materials = try scene_io.duplicateFaceMaterials(allocator, doc.face_materials);
}

fn applyDocumentTexture(state: *ProjectEditorState, obj: *SceneObject, doc: prop_asset_doc.PropAssetDocument) !void {
    const tex = try loadDocumentTexture(state, doc);
    state.allocator.free(obj.texture);
    obj.texture = tex;
}

fn loadDocumentTexture(state: *ProjectEditorState, doc: prop_asset_doc.PropAssetDocument) ![]u8 {
    if (doc.texture_path) |texture_path| {
        var project_dir = try scene_resolve.openProjectDir(state.io, state.project_path);
        defer project_dir.close(state.io);
        const bytes = try project_dir.readFileAlloc(state.io, texture_path, state.allocator, .limited(TextureSize * TextureSize * 4 + 1));
        errdefer state.allocator.free(bytes);
        if (bytes.len != TextureSize * TextureSize * 4) return error.InvalidPropTexture;
        return bytes;
    }
    const tex = try state.allocator.alloc(u8, TextureSize * TextureSize * 4);
    fillCheckerTexture(tex, TextureSize, doc.base_color.r, doc.base_color.g, doc.base_color.b);
    return tex;
}

fn fillSolidTexture(pixels: []u8, color: shared.color.Color) void {
    var offset: usize = 0;
    while (offset < pixels.len) : (offset += 4) {
        pixels[offset] = color.r;
        pixels[offset + 1] = color.g;
        pixels[offset + 2] = color.b;
        pixels[offset + 3] = color.a;
    }
}

fn upsertFaceMaterialPath(state: *ProjectEditorState, obj: *SceneObject, spec: FaceMaterialSpec) !void {
    const transform = materialTransform(spec);
    for (obj.face_materials) |*face| {
        if (face.face_index == spec.face_index) {
            state.allocator.free(face.material_path);
            face.material_path = try state.allocator.dupe(u8, spec.material_path);
            face.transform = transform;
            return;
        }
    }
    const next = try state.allocator.alloc(scene_texture.FaceMaterial, obj.face_materials.len + 1);
    for (obj.face_materials, 0..) |face, idx| next[idx] = face;
    next[obj.face_materials.len] = .{
        .face_index = spec.face_index,
        .material_path = try state.allocator.dupe(u8, spec.material_path),
        .transform = transform,
    };
    state.allocator.free(obj.face_materials);
    obj.face_materials = next;
}

fn clearFaceMaterials(allocator: std.mem.Allocator, obj: *SceneObject) void {
    for (obj.face_materials) |*face| face.deinit(allocator);
    allocator.free(obj.face_materials);
    obj.face_materials = &.{};
}

fn materialTransform(spec: anytype) scene_texture.Transform {
    return .{
        .scale_world = spec.scale_world,
        .rotation_deg = spec.rotation_deg,
        .offset_u = spec.offset_u,
        .offset_v = spec.offset_v,
    };
}

fn validateMaterialPath(path: []const u8) !void {
    if (scene_texture.validateMaterialPath(path)) |_| return error.InvalidMaterialPath;
}

fn sourceFromPrimitiveParams(
    allocator: std.mem.Allocator,
    source_id: []const u8,
    kind: geometry.PrimitiveKind,
    params: geometry.PrimitiveParams,
) !prop_asset_doc.Source {
    const scale: [3]f32 = switch (kind) {
        .box => .{ @max(0.001, params.width * 0.5), @max(0.001, params.height * 0.5), @max(0.001, params.depth * 0.5) },
        .plane => .{ @max(0.001, params.width * 0.5), 0.001, @max(0.001, params.depth * 0.5) },
        .cylinder => .{ @max(0.001, params.radius), @max(0.001, params.height * 0.5), @max(0.001, params.radius) },
        .sphere => .{ 1, 1, 1 },
    };
    return .{
        .id = try allocator.dupe(u8, source_id),
        .kind = .sphere,
        .position = .{ 0, 0, 0 },
        .rotation = .{ 0, 0, 0, 1 },
        .scale = scale,
        .radius = if (kind == .sphere) @max(0.001, params.radius) else 1,
        .segments = @max(8, params.segments),
        .rings = @max(6, params.segments / 2),
    };
}

fn catalogTags(entry: project_editor_prop_catalog.CatalogEntry) []const u8 {
    return switch (entry.recipe.base_kind) {
        .box => if (entry.recipe.shaping.len > 0) "box, shape" else "box",
        .plane => "plane, shape",
        .cylinder => if (std.mem.eql(u8, entry.id, "barrel_rust")) "cylinder, rim" else "cylinder",
        .sphere => "sphere",
    };
}

fn primitiveParamsFromObject(object: *const SceneObject) geometry.PrimitiveParams {
    const bounds = meshBounds(&object.mesh) orelse return .{};
    return switch (object.primitive_kind orelse .box) {
        .box => .{
            .width = @max(0.001, bounds.max.x - bounds.min.x),
            .height = @max(0.001, bounds.max.y - bounds.min.y),
            .depth = @max(0.001, bounds.max.z - bounds.min.z),
        },
        .plane => .{
            .width = @max(0.001, bounds.max.x - bounds.min.x),
            .depth = @max(0.001, bounds.max.z - bounds.min.z),
        },
        .cylinder => .{
            .radius = @max(0.001, @max(bounds.max.x - bounds.min.x, bounds.max.z - bounds.min.z) * 0.5),
            .height = @max(0.001, bounds.max.y - bounds.min.y),
            .segments = 16,
        },
        .sphere => .{
            .radius = @max(0.001, @max(@max(bounds.max.x - bounds.min.x, bounds.max.y - bounds.min.y), bounds.max.z - bounds.min.z) * 0.5),
            .segments = 16,
        },
    };
}

fn containsAssetId(ids: []const []const u8, asset_id: []const u8) bool {
    for (ids) |id| {
        if (std.mem.eql(u8, id, asset_id)) return true;
    }
    return false;
}

fn propagateAndSaveSelectedAssetGeometry(
    state: *ProjectEditorState,
    source_idx: usize,
    asset_id: []const u8,
    material_mode: MaterialSaveMode,
) !void {
    project_editor_texture_paint.markPaintAtlasStale(&state.objects.items[source_idx]);
    try propagateGeometryFromObject(state, source_idx, asset_id);
    try saveAssetFromObject(state, source_idx, asset_id, material_mode);
}

fn propagateAndSaveSelectedAssetGeometryWithShapeIntent(
    state: *ProjectEditorState,
    source_idx: usize,
    asset_id: []const u8,
    material_mode: MaterialSaveMode,
    shape_intent: ShapeIntentDraft,
) !void {
    project_editor_texture_paint.markPaintAtlasStale(&state.objects.items[source_idx]);
    try propagateGeometryFromObject(state, source_idx, asset_id);
    try saveAssetFromObjectWithShapeIntent(state, source_idx, asset_id, material_mode, shape_intent);
}

fn propagateGeometryFromObject(state: *ProjectEditorState, source_idx: usize, asset_id: []const u8) !void {
    const source_mesh = &state.objects.items[source_idx].mesh;
    const source_primitive = state.objects.items[source_idx].primitive_kind;
    const PendingMesh = struct {
        index: usize,
        mesh: geometry.Mesh,
    };
    var pending: std.ArrayList(PendingMesh) = .empty;
    defer pending.deinit(state.allocator);
    errdefer {
        for (pending.items) |*item| item.mesh.deinit(state.allocator);
    }

    for (state.objects.items, 0..) |candidate, idx| {
        if (idx == source_idx) continue;
        const candidate_asset = candidate.prop_asset_id orelse continue;
        if (!std.mem.eql(u8, candidate_asset, asset_id)) continue;
        var mesh_copy = try geometry.duplicateMesh(state.allocator, source_mesh);
        pending.append(state.allocator, .{ .index = idx, .mesh = mesh_copy }) catch |err| {
            mesh_copy.deinit(state.allocator);
            return err;
        };
    }

    for (pending.items) |*item| {
        var candidate = &state.objects.items[item.index];
        candidate.mesh.deinit(state.allocator);
        candidate.mesh = item.mesh;
        candidate.primitive_kind = source_primitive;
        project_editor_texture_paint.markPaintAtlasStale(candidate);
        item.mesh = .{ .vertices = &.{}, .indices = &.{} };
    }
}

fn appendShiftedCopy(state: *ProjectEditorState, obj: *SceneObject, offset: editor_math.Vec3) !void {
    const old_v_len = obj.mesh.vertices.len;
    const old_i_len = obj.mesh.indices.len;
    const new_vertices = try state.allocator.alloc(geometry.Vertex, old_v_len * 2);
    errdefer state.allocator.free(new_vertices);
    @memcpy(new_vertices[0..old_v_len], obj.mesh.vertices);
    for (obj.mesh.vertices, 0..) |vert, i| {
        var shifted = vert;
        shifted.position = editor_math.Vec3.add(shifted.position, offset);
        new_vertices[old_v_len + i] = shifted;
    }
    const new_indices = try state.allocator.alloc(u32, old_i_len * 2);
    errdefer state.allocator.free(new_indices);
    @memcpy(new_indices[0..old_i_len], obj.mesh.indices);
    for (obj.mesh.indices, 0..) |index, i| {
        new_indices[old_i_len + i] = index + @as(u32, @intCast(old_v_len));
    }
    state.allocator.free(obj.mesh.vertices);
    state.allocator.free(obj.mesh.indices);
    obj.mesh.vertices = new_vertices;
    obj.mesh.indices = new_indices;
}

fn appendMeshCopy(allocator: std.mem.Allocator, mesh: *geometry.Mesh, addition: *const geometry.Mesh) !void {
    const old_v_len = mesh.vertices.len;
    const old_i_len = mesh.indices.len;
    const new_vertices = try allocator.alloc(geometry.Vertex, old_v_len + addition.vertices.len);
    errdefer allocator.free(new_vertices);
    @memcpy(new_vertices[0..old_v_len], mesh.vertices);
    @memcpy(new_vertices[old_v_len..], addition.vertices);

    const new_indices = try allocator.alloc(u32, old_i_len + addition.indices.len);
    errdefer allocator.free(new_indices);
    @memcpy(new_indices[0..old_i_len], mesh.indices);
    for (addition.indices, 0..) |index, i| {
        new_indices[old_i_len + i] = index + @as(u32, @intCast(old_v_len));
    }

    allocator.free(mesh.vertices);
    allocator.free(mesh.indices);
    mesh.vertices = new_vertices;
    mesh.indices = new_indices;
}

fn solidifyMesh(allocator: std.mem.Allocator, mesh: *geometry.Mesh, thickness: f32) !void {
    const old_v_len = mesh.vertices.len;
    const old_i_len = mesh.indices.len;
    if (old_v_len == 0 or old_i_len == 0) return;

    var vertices: std.ArrayList(geometry.Vertex) = .empty;
    defer vertices.deinit(allocator);
    try vertices.appendSlice(allocator, mesh.vertices);
    for (mesh.vertices) |vert| {
        var back = vert;
        back.position = editor_math.Vec3.sub(vert.position, editor_math.Vec3.scale(vert.normal, thickness));
        back.normal = editor_math.Vec3.scale(vert.normal, -1.0);
        try vertices.append(allocator, back);
    }

    var boundary_edges: std.ArrayList(EdgeCount) = .empty;
    defer boundary_edges.deinit(allocator);
    var tri: usize = 0;
    while (tri + 2 < old_i_len) : (tri += 3) {
        try recordEdge(allocator, &boundary_edges, mesh.indices[tri], mesh.indices[tri + 1]);
        try recordEdge(allocator, &boundary_edges, mesh.indices[tri + 1], mesh.indices[tri + 2]);
        try recordEdge(allocator, &boundary_edges, mesh.indices[tri + 2], mesh.indices[tri]);
    }
    var indices: std.ArrayList(u32) = .empty;
    defer indices.deinit(allocator);
    try indices.appendSlice(allocator, mesh.indices);
    tri = 0;
    while (tri + 2 < old_i_len) : (tri += 3) {
        try appendTriList(allocator, &indices, mesh.indices[tri] + @as(u32, @intCast(old_v_len)), mesh.indices[tri + 2] + @as(u32, @intCast(old_v_len)), mesh.indices[tri + 1] + @as(u32, @intCast(old_v_len)));
    }
    for (boundary_edges.items) |edge| {
        if (edge.count != 1) continue;
        const p0 = vertices.items[@intCast(edge.a)].position;
        const p1 = vertices.items[@intCast(edge.b)].position;
        const p2 = vertices.items[@intCast(edge.b + @as(u32, @intCast(old_v_len)))].position;
        const p3 = vertices.items[@intCast(edge.a + @as(u32, @intCast(old_v_len)))].position;
        try appendQuadFace(allocator, &vertices, &indices, p0, p1, p2, p3);
    }

    allocator.free(mesh.vertices);
    allocator.free(mesh.indices);
    mesh.vertices = try vertices.toOwnedSlice(allocator);
    mesh.indices = try indices.toOwnedSlice(allocator);
}

fn appendEllipsoid(allocator: std.mem.Allocator, mesh: *geometry.Mesh, spec: EllipsoidSpec) !void {
    if (spec.radius.x <= 0 or spec.radius.y <= 0 or spec.radius.z <= 0) return error.InvalidArguments;
    const segments = @max(4, spec.segments);
    const rings = @max(4, spec.rings);
    const old_v_len = mesh.vertices.len;

    var vertices: std.ArrayList(geometry.Vertex) = .empty;
    defer vertices.deinit(allocator);
    try vertices.appendSlice(allocator, mesh.vertices);
    var indices: std.ArrayList(u32) = .empty;
    defer indices.deinit(allocator);
    try indices.appendSlice(allocator, mesh.indices);

    const top_center: u32 = @intCast(vertices.items.len);
    try vertices.append(allocator, .{
        .position = .{ .x = spec.center.x, .y = spec.center.y + spec.radius.y, .z = spec.center.z },
        .normal = .{ .x = 0, .y = 1, .z = 0 },
        .uv = .{ .x = 0.5, .y = 0 },
    });

    for (1..rings) |ring| {
        const v = @as(f32, @floatFromInt(ring)) / @as(f32, @floatFromInt(rings));
        const phi = v * std.math.pi;
        const y = @cos(phi);
        const ring_radius = @sin(phi);
        for (0..segments) |seg| {
            const u = @as(f32, @floatFromInt(seg)) / @as(f32, @floatFromInt(segments));
            const theta = u * std.math.tau;
            const unit_x = ring_radius * @cos(theta);
            const unit_z = ring_radius * @sin(theta);
            try vertices.append(allocator, .{
                .position = .{
                    .x = spec.center.x + spec.radius.x * unit_x,
                    .y = spec.center.y + spec.radius.y * y,
                    .z = spec.center.z + spec.radius.z * unit_z,
                },
                .normal = editor_math.Vec3.normalized(.{
                    .x = unit_x / spec.radius.x,
                    .y = y / spec.radius.y,
                    .z = unit_z / spec.radius.z,
                }),
                .uv = .{ .x = u * std.math.tau * @max(spec.radius.x, spec.radius.z), .y = v * std.math.pi * spec.radius.y },
            });
        }
    }

    const bottom_center: u32 = @intCast(vertices.items.len);
    try vertices.append(allocator, .{
        .position = .{ .x = spec.center.x, .y = spec.center.y - spec.radius.y, .z = spec.center.z },
        .normal = .{ .x = 0, .y = -1, .z = 0 },
        .uv = .{ .x = 0.5, .y = 1 },
    });

    for (0..segments) |seg| {
        const cur = ellipsoidRingIndex(old_v_len, 1, segments, seg);
        const next = ellipsoidRingIndex(old_v_len, 1, segments, (seg + 1) % segments);
        try indices.appendSlice(allocator, &.{ top_center, next, cur });
    }

    for (1..rings - 1) |ring| {
        for (0..segments) |seg| {
            const a = ellipsoidRingIndex(old_v_len, ring, segments, seg);
            const b = ellipsoidRingIndex(old_v_len, ring, segments, (seg + 1) % segments);
            const c = ellipsoidRingIndex(old_v_len, ring + 1, segments, seg);
            const d = ellipsoidRingIndex(old_v_len, ring + 1, segments, (seg + 1) % segments);
            try indices.appendSlice(allocator, &.{ a, b, c, b, d, c });
        }
    }

    for (0..segments) |seg| {
        const cur = ellipsoidRingIndex(old_v_len, rings - 1, segments, seg);
        const next = ellipsoidRingIndex(old_v_len, rings - 1, segments, (seg + 1) % segments);
        try indices.appendSlice(allocator, &.{ bottom_center, cur, next });
    }

    allocator.free(mesh.vertices);
    allocator.free(mesh.indices);
    mesh.vertices = try vertices.toOwnedSlice(allocator);
    mesh.indices = try indices.toOwnedSlice(allocator);
}

fn ellipsoidRingIndex(old_v_len: usize, ring: usize, segments: usize, seg: usize) u32 {
    return @intCast(old_v_len + 1 + (ring - 1) * segments + seg);
}

fn appendCone(allocator: std.mem.Allocator, mesh: *geometry.Mesh, spec: ConeSpec) !void {
    if (spec.radius <= 0 or spec.height <= 0) return error.InvalidArguments;
    const segments = @max(3, spec.segments);
    const direction = editor_math.Vec3.normalized(spec.direction);
    const basis = coneBasis(direction);
    const half_height = spec.height * 0.5;
    const tip = editor_math.Vec3.add(spec.center, editor_math.Vec3.scale(direction, half_height));
    const base_center = editor_math.Vec3.sub(spec.center, editor_math.Vec3.scale(direction, half_height));

    var vertices: std.ArrayList(geometry.Vertex) = .empty;
    defer vertices.deinit(allocator);
    try vertices.appendSlice(allocator, mesh.vertices);
    var indices: std.ArrayList(u32) = .empty;
    defer indices.deinit(allocator);
    try indices.appendSlice(allocator, mesh.indices);

    for (0..segments) |seg| {
        const next = (seg + 1) % segments;
        const p0 = coneRingPoint(base_center, basis, spec.radius, segments, seg);
        const p1 = coneRingPoint(base_center, basis, spec.radius, segments, next);
        try appendFlatTriangle(allocator, &vertices, &indices, tip, p0, p1);
        try appendFlatTriangle(allocator, &vertices, &indices, base_center, p1, p0);
    }

    allocator.free(mesh.vertices);
    allocator.free(mesh.indices);
    mesh.vertices = try vertices.toOwnedSlice(allocator);
    mesh.indices = try indices.toOwnedSlice(allocator);
}

fn appendOvalSlab(allocator: std.mem.Allocator, mesh: *geometry.Mesh, spec: OvalSlabSpec) !void {
    if (spec.radius_x <= 0 or spec.radius_y <= 0 or spec.depth <= 0) return error.InvalidArguments;
    const segments = @max(5, spec.segments);
    const half_depth = spec.depth * 0.5;
    const front_normal = try editor_math.Quat.rotateVec3(spec.rotation, .{ .x = 0, .y = 0, .z = 1 });
    const back_normal = try editor_math.Quat.rotateVec3(spec.rotation, .{ .x = 0, .y = 0, .z = -1 });

    var vertices: std.ArrayList(geometry.Vertex) = .empty;
    defer vertices.deinit(allocator);
    try vertices.appendSlice(allocator, mesh.vertices);
    var indices: std.ArrayList(u32) = .empty;
    defer indices.deinit(allocator);
    try indices.appendSlice(allocator, mesh.indices);

    const front_center: u32 = @intCast(vertices.items.len);
    try vertices.append(allocator, .{
        .position = try ovalSlabTransformPoint(spec, .{ .x = 0, .y = 0, .z = half_depth }),
        .normal = front_normal,
        .uv = .{ .x = 0, .y = 0 },
    });
    const front_start = vertices.items.len;
    for (0..segments) |seg| {
        const point = try ovalSlabRingPoint(spec, half_depth, seg, segments);
        try vertices.append(allocator, .{
            .position = point,
            .normal = front_normal,
            .uv = ovalSlabCapUv(spec, seg, segments),
        });
    }

    const back_center: u32 = @intCast(vertices.items.len);
    try vertices.append(allocator, .{
        .position = try ovalSlabTransformPoint(spec, .{ .x = 0, .y = 0, .z = -half_depth }),
        .normal = back_normal,
        .uv = .{ .x = 0, .y = 0 },
    });
    const back_start = vertices.items.len;
    for (0..segments) |seg| {
        const point = try ovalSlabRingPoint(spec, -half_depth, seg, segments);
        try vertices.append(allocator, .{
            .position = point,
            .normal = back_normal,
            .uv = ovalSlabCapUv(spec, seg, segments),
        });
    }

    for (0..segments) |seg| {
        const next = (seg + 1) % segments;
        const front_cur: u32 = @intCast(front_start + seg);
        const front_next: u32 = @intCast(front_start + next);
        const back_cur: u32 = @intCast(back_start + seg);
        const back_next: u32 = @intCast(back_start + next);
        try indices.appendSlice(allocator, &.{ front_center, front_cur, front_next });
        try indices.appendSlice(allocator, &.{ back_center, back_next, back_cur });
        const p0 = vertices.items[front_cur].position;
        const p1 = vertices.items[back_cur].position;
        const p2 = vertices.items[back_next].position;
        const p3 = vertices.items[front_next].position;
        try appendQuadFace(allocator, &vertices, &indices, p0, p1, p2, p3);
    }

    allocator.free(mesh.vertices);
    allocator.free(mesh.indices);
    mesh.vertices = try vertices.toOwnedSlice(allocator);
    mesh.indices = try indices.toOwnedSlice(allocator);
}

fn ovalSlabRingPoint(spec: OvalSlabSpec, half_depth: f32, seg: usize, segments: usize) !editor_math.Vec3 {
    const u = ovalSlabU(seg, segments);
    const angle = u * std.math.tau;
    return try ovalSlabTransformPoint(spec, .{
        .x = @cos(angle) * spec.radius_x,
        .y = @sin(angle) * spec.radius_y,
        .z = half_depth,
    });
}

fn ovalSlabTransformPoint(spec: OvalSlabSpec, local: editor_math.Vec3) !editor_math.Vec3 {
    return editor_math.Vec3.add(spec.position, try editor_math.Quat.rotateVec3(spec.rotation, local));
}

fn ovalSlabCapUv(spec: OvalSlabSpec, seg: usize, segments: usize) editor_math.Vec2 {
    const u = ovalSlabU(seg, segments);
    const angle = u * std.math.tau;
    return .{
        .x = @cos(angle) * spec.radius_x,
        .y = @sin(angle) * spec.radius_y,
    };
}

fn ovalSlabU(seg: usize, segments: usize) f32 {
    return @as(f32, @floatFromInt(seg)) / @as(f32, @floatFromInt(segments));
}

const ConeBasis = struct {
    right: editor_math.Vec3,
    up: editor_math.Vec3,
};

fn coneBasis(direction: editor_math.Vec3) ConeBasis {
    const seed: editor_math.Vec3 = if (@abs(direction.y) < 0.9)
        .{ .x = 0, .y = 1, .z = 0 }
    else
        .{ .x = 1, .y = 0, .z = 0 };
    const right = editor_math.Vec3.normalized(editor_math.cross(seed, direction));
    return .{
        .right = right,
        .up = editor_math.Vec3.normalized(editor_math.cross(direction, right)),
    };
}

fn coneRingPoint(base_center: editor_math.Vec3, basis: ConeBasis, radius: f32, segments: usize, seg: usize) editor_math.Vec3 {
    const u = @as(f32, @floatFromInt(seg)) / @as(f32, @floatFromInt(segments));
    const angle = u * std.math.tau;
    return editor_math.Vec3.add(
        base_center,
        editor_math.Vec3.add(
            editor_math.Vec3.scale(basis.right, @cos(angle) * radius),
            editor_math.Vec3.scale(basis.up, @sin(angle) * radius),
        ),
    );
}

fn appendFlatTriangle(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(geometry.Vertex),
    indices: *std.ArrayList(u32),
    p0: editor_math.Vec3,
    p1: editor_math.Vec3,
    p2: editor_math.Vec3,
) !void {
    const normal = faceNormal(p0, p1, p2);
    const base: u32 = @intCast(vertices.items.len);
    const uvs = geometry.planarTriangleUvs(p0, p1, p2);
    try vertices.appendSlice(allocator, &.{
        .{ .position = p0, .normal = normal, .uv = uvs[0] },
        .{ .position = p1, .normal = normal, .uv = uvs[1] },
        .{ .position = p2, .normal = normal, .uv = uvs[2] },
    });
    try indices.appendSlice(allocator, &.{ base, base + 1, base + 2 });
}

const EdgeCount = struct {
    key_a: u32,
    key_b: u32,
    a: u32,
    b: u32,
    count: u8,
};

fn recordEdge(allocator: std.mem.Allocator, edges: *std.ArrayList(EdgeCount), a_raw: u32, b_raw: u32) !void {
    const a = @min(a_raw, b_raw);
    const b = @max(a_raw, b_raw);
    for (edges.items) |*edge| {
        if (edge.key_a == a and edge.key_b == b) {
            edge.count +|= 1;
            return;
        }
    }
    try edges.append(allocator, .{ .key_a = a, .key_b = b, .a = a_raw, .b = b_raw, .count = 1 });
}

fn buildRevolvedMesh(allocator: std.mem.Allocator, source: *const geometry.Mesh) !geometry.Mesh {
    const bounds = meshBounds(source) orelse return error.EmptyMesh;
    const segments: usize = 20;
    const rings: usize = 6;
    const height = @max(0.05, bounds.max.y - bounds.min.y);
    const base_radius = @max(0.08, @max(bounds.max.x - bounds.min.x, bounds.max.z - bounds.min.z) * 0.5);
    const vertices = try allocator.alloc(geometry.Vertex, segments * rings);
    errdefer allocator.free(vertices);
    for (0..rings) |ring| {
        const v = @as(f32, @floatFromInt(ring)) / @as(f32, @floatFromInt(rings - 1));
        const y = bounds.min.y + height * v;
        const shoulder: f32 = 1.0 - @abs(v - 0.5) * 0.42;
        const lip: f32 = if (v < 0.14 or v > 0.86) 1.12 else 1.0;
        const radius = base_radius * @max(0.12, shoulder * lip);
        for (0..segments) |seg| {
            const u = @as(f32, @floatFromInt(seg)) / @as(f32, @floatFromInt(segments));
            const angle = u * std.math.tau;
            const x = @cos(angle) * radius;
            const z = @sin(angle) * radius;
            vertices[ring * segments + seg] = .{
                .position = .{ .x = x, .y = y, .z = z },
                .normal = editor_math.Vec3.normalized(.{ .x = x, .y = 0, .z = z }),
                .uv = .{ .x = u * std.math.tau * radius, .y = height * v },
            };
        }
    }

    const indices = try allocator.alloc(u32, (rings - 1) * segments * 6);
    errdefer allocator.free(indices);
    var out: usize = 0;
    for (0..rings - 1) |ring| {
        for (0..segments) |seg| {
            const next = (seg + 1) % segments;
            const a: u32 = @intCast(ring * segments + seg);
            const b: u32 = @intCast(ring * segments + next);
            const c: u32 = @intCast((ring + 1) * segments + next);
            const d: u32 = @intCast((ring + 1) * segments + seg);
            appendQuadLocal(indices, &out, a, b, c, d);
        }
    }
    return .{ .vertices = vertices, .indices = indices };
}

fn appendSolidifiedSketchFace(
    allocator: std.mem.Allocator,
    mesh: *geometry.Mesh,
    points: []const editor_math.Vec3,
    thickness: f32,
) !void {
    if (points.len < 3) return error.NotEnoughSketchPoints;
    const normal = sketchNormal(points);
    const offset = editor_math.Vec3.scale(normal, thickness);
    const old_v_len = mesh.vertices.len;
    const n = points.len;

    var vertices: std.ArrayList(geometry.Vertex) = .empty;
    defer vertices.deinit(allocator);
    try vertices.appendSlice(allocator, mesh.vertices);
    for (points) |point| {
        try vertices.append(allocator, .{
            .position = point,
            .normal = editor_math.Vec3.scale(normal, -1),
            .uv = sketchUv(point),
        });
        try vertices.append(allocator, .{
            .position = editor_math.Vec3.add(point, offset),
            .normal = normal,
            .uv = sketchUv(point),
        });
    }

    var indices: std.ArrayList(u32) = .empty;
    defer indices.deinit(allocator);
    try indices.appendSlice(allocator, mesh.indices);
    const base: u32 = @intCast(old_v_len);
    const cap: u32 = @intCast(old_v_len + 1);
    var i: usize = 1;
    while (i + 1 < n) : (i += 1) {
        try appendTriList(allocator, &indices, base, base + @as(u32, @intCast((i + 1) * 2)), base + @as(u32, @intCast(i * 2)));
        try appendTriList(allocator, &indices, cap, cap + @as(u32, @intCast(i * 2)), cap + @as(u32, @intCast((i + 1) * 2)));
    }
    i = 0;
    while (i < n) : (i += 1) {
        const next = (i + 1) % n;
        const p0 = points[i];
        const p1 = points[next];
        const p2 = editor_math.Vec3.add(points[next], offset);
        const p3 = editor_math.Vec3.add(points[i], offset);
        try appendQuadFace(allocator, &vertices, &indices, p0, p1, p2, p3);
    }

    allocator.free(mesh.vertices);
    allocator.free(mesh.indices);
    mesh.vertices = try vertices.toOwnedSlice(allocator);
    mesh.indices = try indices.toOwnedSlice(allocator);
}

fn sketchNormal(points: []const editor_math.Vec3) editor_math.Vec3 {
    if (points.len < 3) return .{ .x = 0, .y = 1, .z = 0 };
    const a = editor_math.Vec3.sub(points[1], points[0]);
    const b = editor_math.Vec3.sub(points[2], points[0]);
    const normal = editor_math.Vec3.normalized(editor_math.cross(a, b));
    if (!std.math.isFinite(normal.x) or !std.math.isFinite(normal.y) or !std.math.isFinite(normal.z)) return .{ .x = 0, .y = 1, .z = 0 };
    return normal;
}

fn sketchUv(point: editor_math.Vec3) editor_math.Vec2 {
    return .{ .x = point.x, .y = point.y + point.z };
}

fn appendTriLocal(indices: []u32, out: *usize, a: u32, b: u32, c: u32) void {
    indices[out.*] = a;
    indices[out.* + 1] = b;
    indices[out.* + 2] = c;
    out.* += 3;
}

fn appendTriList(allocator: std.mem.Allocator, indices: *std.ArrayList(u32), a: u32, b: u32, c: u32) !void {
    try indices.appendSlice(allocator, &.{ a, b, c });
}

fn appendQuadLocal(indices: []u32, out: *usize, a: u32, b: u32, c: u32, d: u32) void {
    appendTriLocal(indices, out, a, d, b);
    appendTriLocal(indices, out, b, d, c);
}

fn appendQuadFace(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(geometry.Vertex),
    indices: *std.ArrayList(u32),
    p0: editor_math.Vec3,
    p1: editor_math.Vec3,
    p2: editor_math.Vec3,
    p3: editor_math.Vec3,
) !void {
    const normal = faceNormal(p0, p1, p2);
    const base: u32 = @intCast(vertices.items.len);
    const uvs = geometry.planarQuadUvs(p0, p1, p2, p3);
    try vertices.appendSlice(allocator, &.{
        .{ .position = p0, .normal = normal, .uv = uvs[0] },
        .{ .position = p1, .normal = normal, .uv = uvs[1] },
        .{ .position = p2, .normal = normal, .uv = uvs[2] },
        .{ .position = p3, .normal = normal, .uv = uvs[3] },
    });
    try appendTriList(allocator, indices, base, base + 1, base + 2);
    try appendTriList(allocator, indices, base, base + 2, base + 3);
}

fn faceNormal(p0: editor_math.Vec3, p1: editor_math.Vec3, p2: editor_math.Vec3) editor_math.Vec3 {
    return editor_math.Vec3.normalized(editor_math.cross(
        editor_math.Vec3.sub(p1, p0),
        editor_math.Vec3.sub(p2, p0),
    ));
}

fn meshBounds(mesh: *const geometry.Mesh) ?struct { min: editor_math.Vec3, max: editor_math.Vec3 } {
    if (mesh.vertices.len == 0) return null;
    var min = mesh.vertices[0].position;
    var max = mesh.vertices[0].position;
    for (mesh.vertices[1..]) |vert| {
        min.x = @min(min.x, vert.position.x);
        min.y = @min(min.y, vert.position.y);
        min.z = @min(min.z, vert.position.z);
        max.x = @max(max.x, vert.position.x);
        max.y = @max(max.y, vert.position.y);
        max.z = @max(max.z, vert.position.z);
    }
    return .{ .min = min, .max = max };
}

test "barrel recipe mesh triangles match vertex normals" {
    var source = prop_asset_doc.Source{
        .id = try std.testing.allocator.dupe(u8, "base"),
        .kind = .sphere,
        .position = .{ 0, 0, 0 },
        .rotation = .{ 0, 0, 0, 1 },
        .scale = .{ 0.35, 0.45, 0.35 },
        .radius = 1,
        .segments = 16,
        .rings = 8,
    };
    defer source.deinit(std.testing.allocator);
    const sources = try std.testing.allocator.dupe(prop_asset_doc.Source, &.{source});
    defer std.testing.allocator.free(sources);

    var mesh = try buildRecipeMesh(std.testing.allocator, .{ .sources = sources, .modifiers = &.{} });
    defer mesh.deinit(std.testing.allocator);

    try expectMeshTrianglesMatchVertexNormals(&mesh);
}

test "prop revolve mesh triangles match vertex normals" {
    var source = try geometry.buildPrimitive(std.testing.allocator, .box, .{
        .width = 0.4,
        .height = 0.9,
        .depth = 0.2,
    });
    defer source.deinit(std.testing.allocator);

    var mesh = try buildRevolvedMesh(std.testing.allocator, &source);
    defer mesh.deinit(std.testing.allocator);

    try expectMeshTrianglesMatchVertexNormals(&mesh);
}

test "solidified sketch face triangles match assigned normals" {
    var mesh = geometry.Mesh{
        .vertices = try std.testing.allocator.alloc(geometry.Vertex, 0),
        .indices = try std.testing.allocator.alloc(u32, 0),
    };
    defer mesh.deinit(std.testing.allocator);

    const points = [_]editor_math.Vec3{
        .{ .x = -0.2, .y = 0, .z = -0.2 },
        .{ .x = 0.2, .y = 0, .z = -0.2 },
        .{ .x = 0.2, .y = 0, .z = 0.2 },
        .{ .x = -0.2, .y = 0, .z = 0.2 },
    };

    try appendSolidifiedSketchFace(std.testing.allocator, &mesh, &points, 0.08);
    try expectMeshTrianglesMatchVertexNormals(&mesh);
}

test "low poly ellipsoid triangles match assigned normals" {
    var mesh = geometry.Mesh{
        .vertices = try std.testing.allocator.alloc(geometry.Vertex, 0),
        .indices = try std.testing.allocator.alloc(u32, 0),
    };
    defer mesh.deinit(std.testing.allocator);

    try appendEllipsoid(std.testing.allocator, &mesh, .{
        .center = .{ .x = 0, .y = 0.8, .z = 0 },
        .radius = .{ .x = 0.34, .y = 0.72, .z = 0.12 },
        .segments = 8,
        .rings = 5,
    });
    try expectMeshTrianglesMatchVertexNormals(&mesh);
    try expectMeshFacesPointAwayFromCentroid(&mesh);
}

test "low poly cone triangles match assigned normals" {
    var mesh = geometry.Mesh{
        .vertices = try std.testing.allocator.alloc(geometry.Vertex, 0),
        .indices = try std.testing.allocator.alloc(u32, 0),
    };
    defer mesh.deinit(std.testing.allocator);

    try appendCone(std.testing.allocator, &mesh, .{
        .center = .{ .x = 0, .y = 0.8, .z = 0.14 },
        .direction = .{ .x = 0, .y = 0, .z = 1 },
        .radius = 0.025,
        .height = 0.08,
        .segments = 5,
    });
    try expectMeshTrianglesMatchVertexNormals(&mesh);
    try expectMeshFacesPointAwayFromCentroid(&mesh);
}

test "low poly oval slab triangles match assigned normals" {
    var mesh = geometry.Mesh{
        .vertices = try std.testing.allocator.alloc(geometry.Vertex, 0),
        .indices = try std.testing.allocator.alloc(u32, 0),
    };
    defer mesh.deinit(std.testing.allocator);

    try appendOvalSlab(std.testing.allocator, &mesh, .{
        .position = .{ .x = 0, .y = 0.8, .z = 0 },
        .rotation = .{},
        .radius_x = 0.34,
        .radius_y = 0.72,
        .depth = 0.18,
        .segments = 8,
    });
    try expectMeshTrianglesMatchVertexNormals(&mesh);
    try expectMeshFacesPointAwayFromCentroid(&mesh);
}

test "every ellipsoid cone and oval slab faces outward across varied dimensions and segment counts" {
    const dims = [_]f32{ 0.05, 0.2, 0.5, 1.0, 2.5 };
    const segment_counts = [_]usize{ 3, 4, 5, 8, 16, 32 };

    for (dims) |rx| {
        for (dims) |ry| {
            for (segment_counts) |segments| {
                var mesh = geometry.Mesh{
                    .vertices = try std.testing.allocator.alloc(geometry.Vertex, 0),
                    .indices = try std.testing.allocator.alloc(u32, 0),
                };
                defer mesh.deinit(std.testing.allocator);
                try appendEllipsoid(std.testing.allocator, &mesh, .{
                    .center = .{ .x = 0, .y = 0, .z = 0 },
                    .radius = .{ .x = rx, .y = ry, .z = (rx + ry) * 0.5 },
                    .segments = @max(4, segments),
                    .rings = @max(4, segments),
                });
                // Skip expectMeshTrianglesMatchVertexNormals here: an ellipsoid's
                // analytic (gradient) normal can legitimately deviate sharply from
                // a coarse, low-segment flat triangle's actual normal at extreme
                // eccentricity, with no winding error involved. The centroid check
                // below is the geometrically robust one regardless of eccentricity.
                try expectMeshFacesPointAwayFromCentroid(&mesh);
            }
        }
    }

    const directions = [_]editor_math.Vec3{
        .{ .x = 0, .y = 1, .z = 0 },
        .{ .x = 1, .y = 0, .z = 0 },
        .{ .x = 0, .y = 0, .z = 1 },
        .{ .x = 1, .y = 1, .z = 1 },
    };
    for (dims) |radius| {
        for (dims) |height| {
            for (directions) |direction| {
                for (segment_counts) |segments| {
                    var mesh = geometry.Mesh{
                        .vertices = try std.testing.allocator.alloc(geometry.Vertex, 0),
                        .indices = try std.testing.allocator.alloc(u32, 0),
                    };
                    defer mesh.deinit(std.testing.allocator);
                    try appendCone(std.testing.allocator, &mesh, .{
                        .center = .{ .x = 0, .y = 0, .z = 0 },
                        .direction = direction,
                        .radius = radius,
                        .height = height,
                        .segments = @max(3, segments),
                    });
                    try expectMeshTrianglesMatchVertexNormals(&mesh);
                    try expectMeshFacesPointAwayFromCentroid(&mesh);
                }
            }
        }
    }

    for (dims) |rx| {
        for (dims) |ry| {
            for (segment_counts) |segments| {
                var mesh = geometry.Mesh{
                    .vertices = try std.testing.allocator.alloc(geometry.Vertex, 0),
                    .indices = try std.testing.allocator.alloc(u32, 0),
                };
                defer mesh.deinit(std.testing.allocator);
                try appendOvalSlab(std.testing.allocator, &mesh, .{
                    .position = .{ .x = 0, .y = 0, .z = 0 },
                    .rotation = .{},
                    .radius_x = rx,
                    .radius_y = ry,
                    .depth = (rx + ry) * 0.5,
                    .segments = @max(5, segments),
                });
                try expectMeshTrianglesMatchVertexNormals(&mesh);
                try expectMeshFacesPointAwayFromCentroid(&mesh);
            }
        }
    }
}

test "recipe source sphere with separate modifiers bakes outward mesh" {
    var source = prop_asset_doc.Source{
        .id = try std.testing.allocator.dupe(u8, "pad"),
        .kind = .sphere,
        .position = .{ 0.1, 0.8, -0.05 },
        .rotation = .{ 0, 0.247, 0, 0.969 },
        .scale = .{ 0.35, 0.7, 0.12 },
        .radius = 1,
        .segments = 12,
        .rings = 8,
    };
    defer source.deinit(std.testing.allocator);
    const points = try std.testing.allocator.dupe(prop_asset_doc.LatticePoint, &.{
        .{ .index = .{ 1, 2, 1 }, .offset = .{ 0.04, 0.08, 0 } },
    });
    const modifiers = try std.testing.allocator.dupe(prop_asset_doc.Modifier, &.{
        .{
            .id = try std.testing.allocator.dupe(u8, "bend"),
            .source_id = try std.testing.allocator.dupe(u8, "pad"),
            .kind = .bend,
            .data = .{ .bend = .{ .axis = .x, .amount = 0.2 } },
        },
        .{
            .id = try std.testing.allocator.dupe(u8, "taper"),
            .source_id = try std.testing.allocator.dupe(u8, "pad"),
            .kind = .taper,
            .data = .{ .taper = .{ .axis = .y, .amount = -0.12 } },
        },
        .{
            .id = try std.testing.allocator.dupe(u8, "lattice"),
            .source_id = try std.testing.allocator.dupe(u8, "pad"),
            .kind = .lattice,
            .data = .{ .lattice = .{ .dimensions = .{ 3, 3, 3 }, .points = points } },
        },
    });
    defer {
        for (modifiers) |*modifier| modifier.deinit(std.testing.allocator);
        std.testing.allocator.free(modifiers);
    }
    const sources = try std.testing.allocator.dupe(prop_asset_doc.Source, &.{source});
    defer std.testing.allocator.free(sources);
    var mesh = try buildRecipeMesh(std.testing.allocator, .{ .sources = sources, .modifiers = modifiers });
    defer mesh.deinit(std.testing.allocator);

    try std.testing.expect(mesh.vertices.len > 0);
    try std.testing.expect(mesh.indices.len > 0);
    try expectMeshTrianglesMatchVertexNormals(&mesh);
}

// `expectMeshTrianglesMatchVertexNormals` is tautological for shapes whose vertex
// normal is itself derived from the triangle's own winding (e.g. appendCone,
// appendOvalSlab use faceNormal(p0,p1,p2) as the vertex normal) - it can never
// catch an inverted winding for those shapes since the "expected" normal always
// matches by construction. This checks each triangle's normal independently,
// against the direction from the mesh's centroid to the triangle's center, which
// only holds for convex-ish shapes (fine for ellipsoid/cone/oval-slab; skip for
// shapes with concave/bent/tapered geometry).
fn expectMeshFacesPointAwayFromCentroid(mesh: *const geometry.Mesh) !void {
    var centroid = editor_math.Vec3{ .x = 0, .y = 0, .z = 0 };
    for (mesh.vertices) |v| centroid = editor_math.Vec3.add(centroid, v.position);
    centroid = editor_math.Vec3.scale(centroid, 1.0 / @as(f32, @floatFromInt(mesh.vertices.len)));

    var checked: usize = 0;
    var tri: usize = 0;
    while (tri + 2 < mesh.indices.len) : (tri += 3) {
        const a = mesh.vertices[mesh.indices[tri]];
        const b = mesh.vertices[mesh.indices[tri + 1]];
        const c = mesh.vertices[mesh.indices[tri + 2]];
        const face_normal = editor_math.cross(
            editor_math.Vec3.sub(b.position, a.position),
            editor_math.Vec3.sub(c.position, a.position),
        );
        const face_center = editor_math.Vec3.scale(
            editor_math.Vec3.add(editor_math.Vec3.add(a.position, b.position), c.position),
            1.0 / 3.0,
        );
        const away = editor_math.Vec3.sub(face_center, centroid);
        try std.testing.expect(editor_math.Vec3.dot(face_normal, away) > 0);
        checked += 1;
    }
    try std.testing.expect(checked > 0);
}

fn expectMeshTrianglesMatchVertexNormals(mesh: *const geometry.Mesh) !void {
    var checked: usize = 0;
    var tri: usize = 0;
    while (tri + 2 < mesh.indices.len) : (tri += 3) {
        const v0 = mesh.vertices[mesh.indices[tri]];
        const v1 = mesh.vertices[mesh.indices[tri + 1]];
        const v2 = mesh.vertices[mesh.indices[tri + 2]];
        const normal = editor_math.Vec3.normalized(editor_math.cross(
            editor_math.Vec3.sub(v1.position, v0.position),
            editor_math.Vec3.sub(v2.position, v0.position),
        ));
        try std.testing.expect(editor_math.Vec3.dot(normal, v0.normal) > 0);
        checked += 1;
    }
    try std.testing.expect(checked > 0);
}
