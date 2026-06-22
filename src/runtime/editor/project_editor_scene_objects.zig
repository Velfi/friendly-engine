const std = @import("std");
const shared = @import("runtime_shared");
const friendly_engine = @import("friendly_engine");
const scene_document = shared.scene_document;
const scene_marker = shared.scene_marker;
const scene_resolve = shared.scene_resolve;
const geometry = shared.geometry;
const editor_math = shared.editor_math;
const shared_color = shared.color;
const scene_io = shared.scene_io;
const project_editor_state = @import("project_editor_state.zig");
const project_editor_types = @import("project_editor_types.zig");
const project_editor_edit = @import("project_editor_edit.zig");
const world_authoring = @import("project_editor_world_authoring.zig");

const SceneObject = @import("editor_scene_object.zig").SceneObject;
const TextureSize = @import("editor_scene_object.zig").TextureSize;
const fillCheckerTexture = @import("editor_scene_object.zig").fillCheckerTexture;
const snapValue = @import("editor_raycast.zig").snapValue;

const ProjectEditorState = project_editor_state.ProjectEditorState;

pub fn addPrimitive(state: *ProjectEditorState, kind: geometry.PrimitiveKind, label: []const u8) !void {
    project_editor_edit.pushUndoSnapshot(state);
    const params = geometry.PrimitiveParams{};
    const mesh = try geometry.buildPrimitive(state.allocator, kind, params);
    const tex = try state.allocator.alloc(u8, TextureSize * TextureSize * 4);
    fillCheckerTexture(tex, TextureSize, 200, 210, 220);

    var name_buf: [64]u8 = undefined;
    const name = std.fmt.bufPrint(&name_buf, "{s} {d}", .{ label, state.next_object_id }) catch label;
    const ground_y = geometry.groundOffsetY(kind, params, 1.0);

    try state.objects.append(state.allocator, .{
        .id = state.next_object_id,
        .name = try state.allocator.dupe(u8, name),
        .mesh = mesh,
        .position = .{
            .x = snapValue(@as(f32, @floatFromInt(state.objects.items.len)) * 1.5, if (state.snap_enabled) state.snap_size else 0),
            .y = ground_y,
            .z = 0,
        },
        .rotation = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = tex,
        .base_color = .{ .r = 170, .g = 180, .b = 195, .a = 255 },
        .primitive_kind = kind,
        .object_kind = .mesh,
        .physics = null,
        .editor_only = state.mode == .prop_creation,
    });
    state.next_object_id += 1;
    state.selected_object = state.objects.items.len - 1;
    state.selected_vertex = null;
    state.selected_edge = null;
    state.selected_face = null;
    state.scene_dirty = true;
    project_editor_state.setStatus(state, "Added shape with auto UVs");
}

pub fn addEditorObject(state: *ProjectEditorState, kind: scene_document.ObjectKind) !void {
    project_editor_edit.pushUndoSnapshot(state);
    const shape = placeholderShape(kind);
    var mesh = try geometry.buildPrimitive(state.allocator, shape.kind, shape.params);
    errdefer mesh.deinit(state.allocator);
    const tex = try state.allocator.alloc(u8, TextureSize * TextureSize * 4);
    errdefer state.allocator.free(tex);
    fillCheckerTexture(tex, TextureSize, shape.color.r, shape.color.g, shape.color.b);

    var name_buf: [64]u8 = undefined;
    const name = std.fmt.bufPrint(&name_buf, "{s} {d}", .{ kind.label(), state.next_object_id }) catch kind.label();
    const physics: ?shared.scene_physics.Body = if (kind == .trigger) .{
        .kind = .static,
        .collider = .box,
        .mass = 0,
        .friction = 0,
        .restitution = 0,
    } else null;

    try appendObject(state, .{
        .id = state.next_object_id,
        .name = try state.allocator.dupe(u8, name),
        .mesh = mesh,
        .position = nextObjectPosition(state, 0),
        .rotation = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = tex,
        .base_color = shape.color,
        .primitive_kind = shape.kind,
        .object_kind = kind,
        .renderer_visible = kind != .empty,
        .cast_shadows = kind == .mesh or kind == .prefab,
        .receive_shadows = kind == .mesh or kind == .prefab,
        .components = &.{},
        .physics = physics,
    });
    project_editor_state.setStatus(state, "Added editor object");
}

pub fn addMarkerObject(state: *ProjectEditorState, kind: scene_marker.Kind) !void {
    state.active_gesture.begin(.marker_place);
    errdefer state.active_gesture.cancel();
    project_editor_edit.pushUndoSnapshot(state);
    const marker = try scene_marker.defaultForKind(state.allocator, kind);
    errdefer {
        var owned = marker;
        owned.deinit(state.allocator);
    }
    const shape = markerPlaceholderShape(kind);
    var mesh = try geometry.buildPrimitive(state.allocator, shape.kind, shape.params);
    errdefer mesh.deinit(state.allocator);
    const tex = try state.allocator.alloc(u8, TextureSize * TextureSize * 4);
    errdefer state.allocator.free(tex);
    fillCheckerTexture(tex, TextureSize, shape.color.r, shape.color.g, shape.color.b);

    var name_buf: [80]u8 = undefined;
    const name = std.fmt.bufPrint(&name_buf, "{s} {d}", .{ kind.label(), state.next_object_id }) catch kind.label();
    var gameplay: ?shared.scene_gameplay.Component = if (kind == .player_start) blk: {
        const tag = try state.allocator.dupe(u8, "player_start");
        break :blk shared.scene_gameplay.Component{ .tag = tag };
    } else null;
    errdefer if (gameplay) |*component| component.deinit(state.allocator);

    try appendObject(state, .{
        .id = state.next_object_id,
        .name = try state.allocator.dupe(u8, name),
        .mesh = mesh,
        .position = nextObjectPosition(state, 0),
        .rotation = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = shape.scale.x, .y = shape.scale.y, .z = shape.scale.z },
        .texture = tex,
        .base_color = shape.color,
        .primitive_kind = shape.kind,
        .object_kind = .marker,
        .renderer_visible = true,
        .cast_shadows = false,
        .receive_shadows = false,
        .components = &.{},
        .physics = if (kind == .trigger_volume) .{ .kind = .static, .collider = .box, .mass = 0, .trigger = true } else null,
        .gameplay = gameplay,
        .marker = marker,
    });
    state.active_gesture.commit();
    project_editor_state.setStatus(state, "Added gameplay marker");
}

pub fn instantiateSelectedAsset(state: *ProjectEditorState) !void {
    switch (state.selected_asset) {
        .mesh_box => try instantiateMeshAsset(state, "assets/source/meshes/box.glb", "Box Asset"),
        .scene_main => project_editor_state.setStatus(state, "Scene asset selected; open from project browser"),
    }
}

pub fn instantiatePropAsset(state: *ProjectEditorState, catalog_id: []const u8) !void {
    try @import("project_editor_prop.zig").instantiatePropAsset(state, catalog_id);
}

fn instantiateMeshAsset(state: *ProjectEditorState, mesh_ref: []const u8, label: []const u8) !void {
    project_editor_edit.pushUndoSnapshot(state);
    var project_dir = try scene_resolve.openProjectDir(state.io, state.project_path);
    defer project_dir.close(state.io);
    const resolver = scene_resolve.AssetResolver{
        .io = state.io,
        .project_dir = project_dir,
        .cache_target = "client-debug",
    };
    var mesh = try resolver.readMesh(state.allocator, mesh_ref);
    errdefer mesh.deinit(state.allocator);
    const tex = try resolver.readTexture(state.allocator, "assets/source/textures/default.png");
    errdefer state.allocator.free(tex);

    var skeleton_asset: ?[]u8 = null;
    var bone_pose: []shared.scene_animation.Transform = &.{};
    if (mesh.skin != null) {
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
    const name = std.fmt.bufPrint(&name_buf, "{s} {d}", .{ label, state.next_object_id }) catch label;

    try appendObject(state, .{
        .id = state.next_object_id,
        .name = try state.allocator.dupe(u8, name),
        .mesh = mesh,
        .position = nextObjectPosition(state, 0),
        .rotation = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = tex,
        .base_color = .{ .r = 170, .g = 180, .b = 195, .a = 255 },
        .primitive_kind = null,
        .object_kind = .mesh,
        .components = &.{},
        .physics = null,
        .skeleton_asset = skeleton_asset,
        .bone_pose = bone_pose,
    });
    project_editor_state.setStatus(state, "Instanced mesh asset");
}

fn ensureSkeletonInScene(state: *ProjectEditorState, skeleton: shared.scene_animation.Skeleton) !void {
    for (state.skeletons.items) |existing| {
        if (std.mem.eql(u8, existing.asset, skeleton.asset)) return;
    }
    const copies = try shared.scene_animation.duplicateSkeletons(state.allocator, &.{skeleton});
    defer state.allocator.free(copies);
    try state.skeletons.append(state.allocator, copies[0]);
}

pub fn duplicateSelected(state: *ProjectEditorState) !void {
    const idx = state.selected_object orelse {
        project_editor_state.setStatus(state, "Nothing selected");
        return;
    };
    if (state.objects.items[idx].isImmutable()) {
        project_editor_state.setStatus(state, "Object is immutable");
        return;
    }
    project_editor_edit.pushUndoSnapshot(state);
    var copy = try project_editor_edit.duplicateSceneObject(state.allocator, &state.objects.items[idx]);
    errdefer copy.deinit(state.allocator);
    copy.id = state.next_object_id;
    state.next_object_id += 1;
    const name = try std.fmt.allocPrint(state.allocator, "{s} copy", .{state.objects.items[idx].name});
    defer state.allocator.free(name);
    state.allocator.free(copy.name);
    copy.name = try state.allocator.dupe(u8, name);
    copy.position.x += if (state.snap_enabled) state.snap_size else 0.5;
    copy.position.z += if (state.snap_enabled) state.snap_size else 0.5;
    try state.objects.append(state.allocator, copy);
    state.selected_object = state.objects.items.len - 1;
    state.selected_vertex = null;
    state.selected_edge = null;
    state.selected_face = null;
    project_editor_state.setStatus(state, "Object duplicated");
}

fn appendObject(state: *ProjectEditorState, object: SceneObject) !void {
    try state.objects.append(state.allocator, object);
    state.next_object_id += 1;
    state.selected_object = state.objects.items.len - 1;
    state.selected_vertex = null;
    state.selected_edge = null;
    state.selected_face = null;
    state.scene_dirty = true;
}

fn nextObjectPosition(state: *ProjectEditorState, y: f32) editor_math.Vec3 {
    return .{
        .x = snapValue(@as(f32, @floatFromInt(state.objects.items.len)) * 1.5, if (state.snap_enabled) state.snap_size else 0),
        .y = y,
        .z = 0,
    };
}

fn placeholderShape(kind: scene_document.ObjectKind) struct {
    kind: geometry.PrimitiveKind,
    params: geometry.PrimitiveParams,
    color: shared_color.Color,
} {
    return switch (kind) {
        .empty => .{
            .kind = .box,
            .params = .{ .width = 0.18, .height = 0.18, .depth = 0.18 },
            .color = .{ .r = 160, .g = 172, .b = 190, .a = 255 },
        },
        .light => .{
            .kind = .sphere,
            .params = .{ .radius = 0.22, .segments = 12 },
            .color = .{ .r = 255, .g = 222, .b = 120, .a = 255 },
        },
        .camera => .{
            .kind = .box,
            .params = .{ .width = 0.45, .height = 0.28, .depth = 0.32 },
            .color = .{ .r = 120, .g = 190, .b = 255, .a = 255 },
        },
        .trigger => .{
            .kind = .box,
            .params = .{ .width = 1.0, .height = 1.0, .depth = 1.0 },
            .color = .{ .r = 180, .g = 120, .b = 255, .a = 160 },
        },
        .audio => .{
            .kind = .sphere,
            .params = .{ .radius = 0.28, .segments = 12 },
            .color = .{ .r = 125, .g = 230, .b = 210, .a = 255 },
        },
        .prefab => .{
            .kind = .box,
            .params = .{ .width = 0.8, .height = 0.8, .depth = 0.8 },
            .color = .{ .r = 220, .g = 165, .b = 90, .a = 255 },
        },
        .marker => .{
            .kind = .sphere,
            .params = .{ .radius = 0.24, .segments = 12 },
            .color = .{ .r = 90, .g = 210, .b = 255, .a = 255 },
        },
        .mesh => .{
            .kind = .box,
            .params = .{},
            .color = .{ .r = 170, .g = 180, .b = 195, .a = 255 },
        },
    };
}

fn markerPlaceholderShape(kind: scene_marker.Kind) struct {
    kind: geometry.PrimitiveKind,
    params: geometry.PrimitiveParams,
    scale: editor_math.Vec3,
    color: shared_color.Color,
} {
    return switch (kind) {
        .trigger_volume, .region_anchor => .{
            .kind = .box,
            .params = .{ .width = 1.0, .height = 1.0, .depth = 1.0 },
            .scale = .{ .x = 2, .y = 2, .z = 2 },
            .color = .{ .r = 185, .g = 125, .b = 255, .a = 150 },
        },
        .audio_emitter => .{
            .kind = .sphere,
            .params = .{ .radius = 0.35, .segments = 12 },
            .scale = .{ .x = 1, .y = 1, .z = 1 },
            .color = .{ .r = 110, .g = 230, .b = 210, .a = 230 },
        },
        .camera_point => .{
            .kind = .box,
            .params = .{ .width = 0.52, .height = 0.28, .depth = 0.36 },
            .scale = .{ .x = 1, .y = 1, .z = 1 },
            .color = .{ .r = 105, .g = 185, .b = 255, .a = 255 },
        },
        else => .{
            .kind = .sphere,
            .params = .{ .radius = 0.24, .segments = 12 },
            .scale = .{ .x = 1, .y = 1, .z = 1 },
            .color = .{ .r = 255, .g = 215, .b = 105, .a = 255 },
        },
    };
}
