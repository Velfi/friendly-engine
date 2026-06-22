const std = @import("std");
const shared = @import("runtime_shared");
const geometry = shared.geometry;
const editor_math = shared.editor_math;
const project_editor_state = @import("project_editor_state.zig");
const project_editor_scene = @import("project_editor_scene.zig");
const project_editor_prop_catalog = @import("project_editor_prop_catalog.zig");
const project_editor_prop_instantiate = @import("project_editor_prop_instantiate.zig");
const editor_raycast = @import("editor_raycast.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const findCatalogEntry = project_editor_prop_catalog.findCatalogEntry;
const snapVec3 = editor_raycast.snapVec3;

pub fn placementPoint(state: *ProjectEditorState, screen_x: f32, screen_y: f32) ?editor_math.Vec3 {
    if (!project_editor_scene.pointInViewport(state, screen_x, screen_y)) return null;
    const local_x = screen_x - state.viewport_screen_rect.x;
    const local_y = screen_y - state.viewport_screen_rect.y;
    const ray = project_editor_state.rayFromViewport(
        state,
        local_x,
        local_y,
        state.viewport_screen_rect.w,
        state.viewport_screen_rect.h,
    );
    const grid = if (state.snap_enabled) state.snap_size else 0;

    if (state.prop_align_to_surface) {
        if (editor_raycast.raycastScene(ray.origin, ray.dir, state.objects.items)) |hit| {
            return snapVec3(hit.position, grid);
        }
    }

    const pt = switch (state.prop_placement_mode) {
        .surface, .ground => editor_math.rayIntersectPlane(ray.origin, ray.dir, 0),
        .free => blk: {
            const t = state.camera.distance * 0.5;
            break :blk editor_math.Vec3.add(ray.origin, editor_math.Vec3.scale(ray.dir, t));
        },
    };
    return if (pt) |value| snapVec3(value, grid) else null;
}

pub fn refreshPlacementPreview(state: *ProjectEditorState) void {
    if (!showsPlacementGhost(state)) {
        state.prop_placement_preview = null;
        state.prop_placement_preview_bounds = null;
        return;
    }
    state.prop_placement_preview = placementPoint(state, state.mouse_x, state.mouse_y);
    updatePlacementPreviewBounds(state);
}

pub fn placeAtScreen(state: *ProjectEditorState, screen_x: f32, screen_y: f32) !void {
    const point = placementPoint(state, screen_x, screen_y) orelse {
        project_editor_state.setStatus(state, "Placement point not found");
        return;
    };
    switch (state.prop_tool) {
        .create => try project_editor_prop_instantiate.placePrimitiveProp(state, point, state.prop_primitive),
        .variants => {
            const edit = @import("project_editor_prop_edit.zig");
            edit.cycleSelectedVariant(state);
        },
        else => {},
    }
}

pub fn instantiatePropAsset(state: *ProjectEditorState, catalog_id: []const u8) !void {
    const point = placementPoint(state, state.mouse_x, state.mouse_y) orelse {
        project_editor_state.setStatus(state, "Placement point not found");
        return;
    };
    try project_editor_prop_instantiate.instantiatePropAssetAt(state, catalog_id, point);
}

fn showsPlacementGhost(state: *const ProjectEditorState) bool {
    return state.prop_tool == .create;
}

fn ensurePropPreviewMesh(state: *ProjectEditorState) void {
    if (state.prop_tool != .asset) return;
    const entry = findCatalogEntry(state.prop_selected_asset) orelse return;
    if (state.prop_preview_mesh_id) |cached_id| {
        if (std.mem.eql(u8, cached_id, entry.id)) return;
    }
    const recent = @import("project_editor_prop_recent.zig");
    recent.invalidatePropPreviewMesh(state);
    var resolved = project_editor_prop_instantiate.resolvePropMesh(state, entry) catch return;
    state.prop_preview_mesh = resolved.mesh;
    state.prop_preview_mesh_id = state.allocator.dupe(u8, entry.id) catch {
        resolved.mesh.deinit(state.allocator);
        return;
    };
}

fn placementPreviewMesh(state: *ProjectEditorState) ?*const geometry.Mesh {
    if (state.prop_tool == .create) {
        return null;
    }
    if (state.prop_tool == .asset) {
        ensurePropPreviewMesh(state);
        return if (state.prop_preview_mesh) |*mesh| mesh else null;
    }
    return null;
}

fn updatePlacementPreviewBounds(state: *ProjectEditorState) void {
    const center = state.prop_placement_preview orelse {
        state.prop_placement_preview_bounds = null;
        return;
    };
    if (state.prop_tool == .create) {
        const half: f32 = 0.5;
        state.prop_placement_preview_bounds = .{
            .min = .{ .x = center.x - half, .y = center.y, .z = center.z - half },
            .max = .{ .x = center.x + half, .y = center.y + half, .z = center.z + half },
        };
        return;
    }
    const mesh = placementPreviewMesh(state) orelse {
        state.prop_placement_preview_bounds = null;
        return;
    };
    var local_min = editor_math.Vec3{ .x = std.math.inf(f32), .y = std.math.inf(f32), .z = std.math.inf(f32) };
    var local_max = editor_math.Vec3{ .x = -std.math.inf(f32), .y = -std.math.inf(f32), .z = -std.math.inf(f32) };
    for (mesh.vertices) |vert| {
        local_min.x = @min(local_min.x, vert.position.x);
        local_min.y = @min(local_min.y, vert.position.y);
        local_min.z = @min(local_min.z, vert.position.z);
        local_max.x = @max(local_max.x, vert.position.x);
        local_max.y = @max(local_max.y, vert.position.y);
        local_max.z = @max(local_max.z, vert.position.z);
    }
    var min_pt = editor_math.Vec3{
        .x = center.x + local_min.x,
        .y = center.y + local_min.y,
        .z = center.z + local_min.z,
    };
    var max_pt = editor_math.Vec3{
        .x = center.x + local_max.x,
        .y = center.y + local_max.y,
        .z = center.z + local_max.z,
    };
    if (state.prop_drop_to_ground) {
        const offset = geometry.meshGroundOffsetY(mesh, 1.0);
        const dy = offset - local_min.y;
        min_pt.y += dy;
        max_pt.y += dy;
    }
    state.prop_placement_preview_bounds = .{ .min = min_pt, .max = max_pt };
}
