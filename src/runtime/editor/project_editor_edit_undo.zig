const std = @import("std");
const shared = @import("runtime_shared");
const geometry = shared.geometry;
const scene_io = shared.scene_io;
const shared_color = shared.color;
const project_editor_state = @import("project_editor_state.zig");
const project_editor_types = @import("project_editor_types.zig");
const project_editor_terrain_preview = @import("project_editor_terrain_preview.zig");

const scene_gameplay = shared.scene_gameplay;
const scene_marker = shared.scene_marker;
const ProjectEditorState = project_editor_state.ProjectEditorState;
const GizmoAxis = project_editor_types.GizmoAxis;
const SceneObject = @import("editor_scene_object.zig").SceneObject;

const max_world_curve_layer_bytes = 8 * 1024 * 1024;
const world_curve_layer_paths = [_][]const u8{
    "layers/splines.kdl",
    "layers/ocean.kdl",
    "layers/water.kdl",
    "layers/scatter.kdl",
};

pub fn pushUndoSnapshot(state: *ProjectEditorState) void {
    if (state.undo_batch_depth > 0 and state.undo_batch_snapshot_taken) return;
    var snapshot = captureSnapshot(state) catch @panic("failed to capture undo snapshot");
    state.scene_dirty = true;
    for (state.redo_stack.items) |*snap| snap.deinit(state.allocator);
    state.redo_stack.clearRetainingCapacity();
    state.undo_stack.append(state.allocator, snapshot) catch {
        snapshot.deinit(state.allocator);
        @panic("failed to store undo snapshot");
    };
    while (state.undo_stack.items.len > 32) {
        var old = state.undo_stack.orderedRemove(0);
        old.deinit(state.allocator);
    }
    if (state.undo_batch_depth > 0) state.undo_batch_snapshot_taken = true;
}

pub fn beginUndoBatch(state: *ProjectEditorState, label: []const u8) void {
    if (state.undo_batch_depth == 0) {
        state.undo_batch_snapshot_taken = false;
        state.undo_batch_label_len = @min(label.len, state.undo_batch_label_buf.len);
        @memcpy(state.undo_batch_label_buf[0..state.undo_batch_label_len], label[0..state.undo_batch_label_len]);
    }
    state.undo_batch_depth += 1;
    project_editor_state.setStatus(state, "Undo batch started");
}

pub fn endUndoBatch(state: *ProjectEditorState) void {
    if (state.undo_batch_depth == 0) {
        project_editor_state.setStatus(state, "No undo batch active");
        return;
    }
    state.undo_batch_depth -= 1;
    if (state.undo_batch_depth == 0) {
        const status = if (state.undo_batch_snapshot_taken) "Undo batch ended" else "Undo batch ended with no undo snapshot";
        project_editor_state.setStatus(state, status);
        state.undo_batch_label_len = 0;
        state.undo_batch_snapshot_taken = false;
    }
}

pub fn cancelUndoBatch(state: *ProjectEditorState) void {
    if (state.undo_batch_depth == 0) {
        project_editor_state.setStatus(state, "No undo batch active");
        return;
    }
    state.undo_batch_depth = 0;
    state.undo_batch_label_len = 0;
    state.undo_batch_snapshot_taken = false;
    project_editor_state.setStatus(state, "Undo batch cancelled");
}

pub fn undo(state: *ProjectEditorState) void {
    var snapshot = state.undo_stack.pop() orelse {
        project_editor_state.setStatus(state, "Nothing to undo");
        return;
    };
    var current = captureSnapshot(state) catch {
        state.undo_stack.append(state.allocator, snapshot) catch snapshot.deinit(state.allocator);
        project_editor_state.setStatus(state, "Undo failed");
        return;
    };
    state.redo_stack.append(state.allocator, current) catch current.deinit(state.allocator);
    applySnapshot(state, snapshot) catch |err| std.debug.panic("failed to apply undo snapshot: {s}", .{@errorName(err)});
    snapshot.deinit(state.allocator);
    state.scene_dirty = true;
    project_editor_state.setStatus(state, "Undo");
}

pub fn redo(state: *ProjectEditorState) void {
    var snapshot = state.redo_stack.pop() orelse {
        project_editor_state.setStatus(state, "Nothing to redo");
        return;
    };
    var current = captureSnapshot(state) catch {
        state.redo_stack.append(state.allocator, snapshot) catch snapshot.deinit(state.allocator);
        project_editor_state.setStatus(state, "Redo failed");
        return;
    };
    state.undo_stack.append(state.allocator, current) catch current.deinit(state.allocator);
    applySnapshot(state, snapshot) catch |err| std.debug.panic("failed to apply undo snapshot: {s}", .{@errorName(err)});
    snapshot.deinit(state.allocator);
    state.scene_dirty = true;
    project_editor_state.setStatus(state, "Redo");
}

pub fn clearUndoHistory(state: *ProjectEditorState) void {
    for (state.undo_stack.items) |*snap| snap.deinit(state.allocator);
    state.undo_stack.deinit(state.allocator);
    state.undo_stack = .empty;
    for (state.redo_stack.items) |*snap| snap.deinit(state.allocator);
    state.redo_stack.deinit(state.allocator);
    state.redo_stack = .empty;
    state.undo_batch_depth = 0;
    state.undo_batch_snapshot_taken = false;
    state.undo_batch_label_len = 0;
}
pub fn gizmoAxisColor(axis: GizmoAxis, active: bool) shared_color.Color {
    const alpha: u8 = if (active) 255 else 90;
    return switch (axis) {
        .x => .{ .r = 230, .g = 70, .b = 70, .a = alpha },
        .y => .{ .r = 90, .g = 210, .b = 90, .a = alpha },
        .z => .{ .r = 80, .g = 130, .b = 230, .a = alpha },
    };
}

pub const SceneSnapshot = struct {
    objects: []SceneObject,
    animations: []shared.scene_animation.Clip,
    skeletons: []shared.scene_animation.Skeleton,
    world_layer_files: []WorldLayerFileSnapshot,
    selected_object: ?usize,
    selected_vertex: ?u32,
    selected_edge: ?[2]u32,
    next_object_id: u64,
    active_clip: ?usize,
    life_time: f32,
    selected_bone: ?u32,

    fn deinit(self: *SceneSnapshot, allocator: std.mem.Allocator) void {
        for (self.objects) |*obj| obj.deinit(allocator);
        allocator.free(self.objects);
        for (self.animations) |*clip| clip.deinit(allocator);
        allocator.free(self.animations);
        for (self.skeletons) |*skeleton| skeleton.deinit(allocator);
        allocator.free(self.skeletons);
        for (self.world_layer_files) |*file| file.deinit(allocator);
        allocator.free(self.world_layer_files);
    }
};

pub const WorldLayerFileSnapshot = struct {
    path: []u8,
    bytes: ?[]u8,

    fn deinit(self: *WorldLayerFileSnapshot, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        if (self.bytes) |bytes| allocator.free(bytes);
    }
};

pub fn duplicateObjectData(allocator: std.mem.Allocator, src: *const SceneObject) !scene_io.SceneObjectData {
    return .{
        .id = src.id,
        .name = try allocator.dupe(u8, src.name),
        .mesh = try geometry.duplicateMesh(allocator, &src.mesh),
        .position = src.position,
        .rotation = src.rotation,
        .scale = src.scale,
        .texture = try allocator.dupe(u8, src.texture),
        .base_color = src.base_color,
        .primitive_kind = src.primitive_kind,
        .object_kind = src.object_kind,
        .enabled = src.enabled,
        .renderer_visible = src.renderer_visible,
        .cast_shadows = src.cast_shadows,
        .receive_shadows = src.receive_shadows,
        .components = try scene_io.duplicateComponents(allocator, src.components),
        .properties = try scene_io.duplicateProperties(allocator, src.properties),
        .physics = src.physics,
        .blockout_intent = if (src.blockout_intent) |intent| try shared.scene_blockout.Intent.duplicate(allocator, intent) else null,
        .texture_transform = src.texture_transform,
        .face_materials = try scene_io.duplicateFaceMaterials(allocator, src.face_materials),
        .face_surfaces = try scene_io.duplicateFaceSurfaces(allocator, src.face_surfaces),
        .gameplay = if (src.gameplay) |gameplay| try scene_gameplay.Component.duplicate(allocator, gameplay) else null,
        .marker = if (src.marker) |marker| try scene_marker.Marker.duplicate(allocator, marker) else null,
        .lightmap_path = if (src.lightmap_path) |path| try allocator.dupe(u8, path) else null,
        .skeleton_asset = if (src.skeleton_asset) |asset| try allocator.dupe(u8, asset) else null,
        .bone_pose = try allocator.dupe(shared.scene_animation.Transform, src.bone_pose),
        .parent_id = src.parent_id,
        .layer = if (src.layer.len > 0) try allocator.dupe(u8, src.layer) else "",
        .variant = if (src.variant) |variant| try allocator.dupe(u8, variant) else null,
        .prop_asset_id = if (src.prop_asset_id) |asset_id| try allocator.dupe(u8, asset_id) else null,
    };
}

const project_editor_surface_faces = @import("project_editor_surface_faces.zig");

pub fn duplicateSceneObject(allocator: std.mem.Allocator, src: *const SceneObject) !SceneObject {
    const face_materials = try scene_io.duplicateFaceMaterials(allocator, src.face_materials);
    errdefer {
        for (face_materials) |*face| face.deinit(allocator);
        allocator.free(face_materials);
    }
    const face_surfaces = try project_editor_surface_faces.duplicateFaceSurfaces(allocator, src.face_surfaces);
    errdefer allocator.free(face_surfaces);
    return .{
        .id = src.id,
        .name = try allocator.dupe(u8, src.name),
        .mesh = try geometry.duplicateMesh(allocator, &src.mesh),
        .position = src.position,
        .rotation = src.rotation,
        .scale = src.scale,
        .texture = try allocator.dupe(u8, src.texture),
        .base_color = src.base_color,
        .primitive_kind = src.primitive_kind,
        .object_kind = src.object_kind,
        .enabled = src.enabled,
        .renderer_visible = src.renderer_visible,
        .locked = src.locked,
        .cast_shadows = src.cast_shadows,
        .receive_shadows = src.receive_shadows,
        .components = try scene_io.duplicateComponents(allocator, src.components),
        .properties = try scene_io.duplicateProperties(allocator, src.properties),
        .physics = src.physics,
        .blockout_intent = if (src.blockout_intent) |intent| try shared.scene_blockout.Intent.duplicate(allocator, intent) else null,
        .texture_transform = src.texture_transform,
        .face_materials = face_materials,
        .face_surfaces = face_surfaces,
        .gameplay = if (src.gameplay) |gameplay| try scene_gameplay.Component.duplicate(allocator, gameplay) else null,
        .marker = if (src.marker) |marker| try scene_marker.Marker.duplicate(allocator, marker) else null,
        .material_path = if (src.material_path) |path| try allocator.dupe(u8, path) else null,
        .material_error = if (src.material_error) |err| try allocator.dupe(u8, err) else null,
        .lightmap_path = if (src.lightmap_path) |path| try allocator.dupe(u8, path) else null,
        .skeleton_asset = if (src.skeleton_asset) |asset| try allocator.dupe(u8, asset) else null,
        .bone_pose = try allocator.dupe(shared.scene_animation.Transform, src.bone_pose),
        .parent_id = src.parent_id,
        .layer = if (src.layer.len > 0) try allocator.dupe(u8, src.layer) else "",
        .variant = if (src.variant) |variant| try allocator.dupe(u8, variant) else null,
        .prop_asset_id = if (src.prop_asset_id) |asset_id| try allocator.dupe(u8, asset_id) else null,
        .editor_only = src.editor_only,
    };
}

pub fn captureSnapshot(state: *ProjectEditorState) !SceneSnapshot {
    var objects = try state.allocator.alloc(SceneObject, state.objects.items.len);
    var initialized_objects: usize = 0;
    errdefer {
        for (objects[0..initialized_objects]) |*obj| obj.deinit(state.allocator);
        state.allocator.free(objects);
    }
    for (state.objects.items, 0..) |obj, idx| {
        objects[idx] = try duplicateSceneObject(state.allocator, &obj);
        initialized_objects += 1;
    }
    return .{
        .objects = objects,
        .animations = try shared.scene_animation.duplicateClips(state.allocator, state.animations.items),
        .skeletons = try shared.scene_animation.duplicateSkeletons(state.allocator, state.skeletons.items),
        .world_layer_files = try captureWorldLayerFiles(state),
        .selected_object = state.selected_object,
        .selected_vertex = state.selected_vertex,
        .selected_edge = state.selected_edge,
        .next_object_id = state.next_object_id,
        .active_clip = state.active_clip,
        .life_time = state.life_time,
        .selected_bone = state.selected_bone,
    };
}

pub fn applySnapshot(state: *ProjectEditorState, snapshot: SceneSnapshot) !void {
    for (state.objects.items) |*obj| obj.deinit(state.allocator);
    state.objects.clearRetainingCapacity();
    for (snapshot.objects) |obj| {
        const copy = try duplicateSceneObject(state.allocator, &obj);
        try state.objects.append(state.allocator, copy);
    }
    state.selected_object = snapshot.selected_object;
    if (state.selected_object) |sel| {
        if (sel >= state.objects.items.len) state.selected_object = if (state.objects.items.len > 0) state.objects.items.len - 1 else null;
    }
    state.selected_vertex = snapshot.selected_vertex;
    state.selected_edge = snapshot.selected_edge;
    state.next_object_id = snapshot.next_object_id;
    for (state.animations.items) |*clip| clip.deinit(state.allocator);
    state.animations.clearRetainingCapacity();
    for (snapshot.animations) |clip| {
        const copies = try shared.scene_animation.duplicateClips(state.allocator, &.{clip});
        defer state.allocator.free(copies);
        try state.animations.append(state.allocator, copies[0]);
    }
    for (state.skeletons.items) |*skeleton| skeleton.deinit(state.allocator);
    state.skeletons.clearRetainingCapacity();
    for (snapshot.skeletons) |skeleton| {
        const copies = try shared.scene_animation.duplicateSkeletons(state.allocator, &.{skeleton});
        defer state.allocator.free(copies);
        try state.skeletons.append(state.allocator, copies[0]);
    }
    state.active_clip = snapshot.active_clip;
    if (state.active_clip) |clip_idx| {
        if (clip_idx >= state.animations.items.len) state.active_clip = null;
    }
    state.life_time = snapshot.life_time;
    state.selected_bone = snapshot.selected_bone;
    try restoreWorldLayerFiles(state, snapshot.world_layer_files);
}

fn captureWorldLayerFiles(state: *ProjectEditorState) ![]WorldLayerFileSnapshot {
    if (!worldLayerSnapshotStateReady(state)) return try state.allocator.alloc(WorldLayerFileSnapshot, 0);
    var project_dir = openProjectDir(state.io, state.project_path) catch return try state.allocator.alloc(WorldLayerFileSnapshot, 0);
    defer project_dir.close(state.io);

    var files = std.ArrayList(WorldLayerFileSnapshot).empty;
    errdefer {
        for (files.items) |*file| file.deinit(state.allocator);
        files.deinit(state.allocator);
    }

    for (world_curve_layer_paths) |layer_path| {
        const path = try worldLayerPathForManifest(state.allocator, state.active_world_manifest_path, layer_path);
        errdefer state.allocator.free(path);
        const bytes: ?[]u8 = project_dir.readFileAlloc(state.io, path, state.allocator, .limited(max_world_curve_layer_bytes)) catch |err| switch (err) {
            error.FileNotFound => null,
            else => return err,
        };
        try files.append(state.allocator, .{ .path = path, .bytes = bytes });
    }

    return files.toOwnedSlice(state.allocator);
}

fn worldLayerSnapshotStateReady(state: *const ProjectEditorState) bool {
    return state.project_path.len > 0 and
        state.project_path.len <= std.fs.max_path_bytes and
        state.active_world_manifest_path.len > 0 and
        state.active_world_manifest_path.len <= std.fs.max_path_bytes;
}

fn restoreWorldLayerFiles(state: *ProjectEditorState, files: []const WorldLayerFileSnapshot) !void {
    if (files.len == 0) return;
    var project_dir = try openProjectDir(state.io, state.project_path);
    defer project_dir.close(state.io);
    for (files) |file| {
        if (file.bytes) |bytes| {
            if (std.fs.path.dirname(file.path)) |parent| try project_dir.createDirPath(state.io, parent);
            try project_dir.writeFile(state.io, .{ .sub_path = file.path, .data = bytes });
        } else {
            project_dir.deleteFile(state.io, file.path) catch |err| switch (err) {
                error.FileNotFound => {},
                else => return err,
            };
        }
    }
    state.invalidateWorldCache();
    state.spline_preview_stale = true;
    state.terrain_preview_stale = true;
    project_editor_terrain_preview.scheduleBake(state);
}

fn worldLayerPathForManifest(allocator: std.mem.Allocator, manifest_path: []const u8, layer_path: []const u8) ![]u8 {
    const dir = std.fs.path.dirname(manifest_path) orelse "";
    if (dir.len == 0) return allocator.dupe(u8, layer_path);
    return std.fs.path.join(allocator, &.{ dir, layer_path });
}

fn openProjectDir(io: std.Io, project_path: []const u8) !std.Io.Dir {
    if (std.fs.path.isAbsolute(project_path)) return std.Io.Dir.openDirAbsolute(io, project_path, .{});
    return std.Io.Dir.cwd().openDir(io, project_path, .{});
}

test "undo batch coalesces repeated snapshots" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .active_scene_path = "",
        .active_world_manifest_path = "",
        .objects = .empty,
    };
    defer clearUndoHistory(&state);

    beginUndoBatch(&state, "LLM test action");
    pushUndoSnapshot(&state);
    pushUndoSnapshot(&state);
    try std.testing.expectEqual(@as(usize, 1), state.undo_stack.items.len);
    try std.testing.expect(state.undo_batch_snapshot_taken);
    endUndoBatch(&state);
    try std.testing.expectEqual(@as(u32, 0), state.undo_batch_depth);
    try std.testing.expect(!state.undo_batch_snapshot_taken);

    pushUndoSnapshot(&state);
    try std.testing.expectEqual(@as(usize, 2), state.undo_stack.items.len);
}

test "undo snapshot restores world curve layer files" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "layers");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "layers/splines.kdl", .data = "splines version=1 {}\n" });

    var project_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const project_path_len = try tmp.dir.realPath(std.testing.io, &project_path_buf);
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = try std.testing.allocator.dupe(u8, project_path_buf[0..project_path_len]),
        .project_name = try std.testing.allocator.dupe(u8, ""),
        .active_scene_path = "",
        .active_world_manifest_path = "world.kdl",
        .objects = .empty,
    };
    defer state.deinit();

    var snapshot = try captureSnapshot(&state);
    defer snapshot.deinit(std.testing.allocator);

    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "layers/splines.kdl", .data = "splines version=1 { changed }\n" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "layers/water.kdl", .data = "water version=1 {}\n" });

    try applySnapshot(&state, snapshot);

    const splines = try tmp.dir.readFileAlloc(std.testing.io, "layers/splines.kdl", std.testing.allocator, .limited(4096));
    defer std.testing.allocator.free(splines);
    try std.testing.expectEqualStrings("splines version=1 {}\n", splines);
    try std.testing.expectError(error.FileNotFound, tmp.dir.access(std.testing.io, "layers/water.kdl", .{}));
}
