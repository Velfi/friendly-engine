//! Active-building workspace for architecture mode.
//!
//! Architecture edits are always relative to a single "active building": the
//! one scene object that owns a semantic `arch.Building` (walls, openings,
//! features, roof) in its components. Keeping a stable target id — mirroring the
//! prop editor's `active_prop_asset_id` — means every wall, door, window, and
//! feature edit lands on the same building instead of guessing from the current
//! fine-grained selection (which is often a face/vertex inside the building).
//!
//! Because a building is one scene object and props are parented to it through
//! the existing `parent_id` hierarchy, moving the building moves every wall and
//! every attached prop together.

const std = @import("std");
const shared = @import("runtime_shared");
const arch = shared.architecture;
const scene_object = @import("editor_scene_object.zig");
const scene_hierarchy = @import("editor_scene_hierarchy.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_edit = @import("project_editor_edit.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const SceneObject = scene_object.SceneObject;

/// A scene object owns a building when it carries the building marker component.
pub fn isArchitectureBuildingObject(obj: *const SceneObject) bool {
    for (obj.components) |component| {
        if (std.mem.eql(u8, component, arch.building_marker)) return true;
    }
    return false;
}

pub fn setActiveBuilding(state: *ProjectEditorState, building_id: u64) void {
    state.active_building_id = building_id;
}

/// Forget the active building so the next floor/wall draw starts a fresh one.
pub fn clearActiveBuilding(state: *ProjectEditorState) void {
    state.active_building_id = null;
}

/// Begin a new building: drop the active target and selection so the next floor
/// or wall draw starts fresh instead of extending the current building.
pub fn startNewBuilding(state: *ProjectEditorState) void {
    clearActiveBuilding(state);
    state.selected_object = null;
    state.selected_vertex = null;
    state.selected_edge = null;
    state.selected_face = null;
    state.wall_outline_points.clearRetainingCapacity();
    state.architecture_curve_points.clearRetainingCapacity();
    project_editor_state.setStatus(state, "New building: draw a floor or wall to start");
}

/// Resolve the active building to a live object index. The id is cleared when it
/// no longer points at a building (deleted, undone, or otherwise gone) so it can
/// never reference a stale slot.
pub fn activeBuildingIndex(state: *ProjectEditorState) ?usize {
    const id = state.active_building_id orelse return null;
    for (state.objects.items, 0..) |*obj, idx| {
        if (obj.id != id) continue;
        if (isArchitectureBuildingObject(obj)) return idx;
        break;
    }
    state.active_building_id = null;
    return null;
}

pub fn activeBuilding(state: *ProjectEditorState) ?*SceneObject {
    const idx = activeBuildingIndex(state) orelse return null;
    return &state.objects.items[idx];
}

/// The selected object, but only when it is itself a building.
pub fn selectedBuildingIndex(state: *const ProjectEditorState) ?usize {
    const sel = state.selected_object orelse return null;
    if (sel >= state.objects.items.len) return null;
    if (!isArchitectureBuildingObject(&state.objects.items[sel])) return null;
    return sel;
}

fn firstBuildingIndex(state: *const ProjectEditorState) ?usize {
    for (state.objects.items, 0..) |*obj, idx| {
        if (isArchitectureBuildingObject(obj)) return idx;
    }
    return null;
}

/// The building an edit should target, promoting it to the active building so
/// subsequent edits stay on the same one: the active building if it still
/// exists, else the selected building, else the first building in the scene.
pub fn editTargetIndex(state: *ProjectEditorState) ?usize {
    if (activeBuildingIndex(state)) |idx| return idx;
    const idx = selectedBuildingIndex(state) orelse firstBuildingIndex(state) orelse return null;
    setActiveBuilding(state, state.objects.items[idx].id);
    return idx;
}

/// Like `editTargetIndex` but reports why no building is available instead of
/// silently doing nothing.
pub fn editTargetBuilding(state: *ProjectEditorState) ?*SceneObject {
    const idx = editTargetIndex(state) orelse {
        project_editor_state.setStatus(state, "Draw or select a building first");
        return null;
    };
    return &state.objects.items[idx];
}

/// Number of objects parented directly to a building.
pub fn buildingChildCount(state: *const ProjectEditorState, building_id: u64) usize {
    var count: usize = 0;
    for (state.objects.items) |obj| {
        if (obj.parent_id == building_id) count += 1;
    }
    return count;
}

/// Parent the selected object to the active building so the two move together.
/// Props become children of the building; the building is the single thing you
/// then move, rotate, or scale.
pub fn attachSelectedToActiveBuilding(state: *ProjectEditorState) void {
    const sel = state.selected_object orelse {
        project_editor_state.setStatus(state, "Select a prop to attach");
        return;
    };
    const building_idx = activeBuildingIndex(state) orelse {
        project_editor_state.setStatus(state, "No active building to attach to");
        return;
    };
    const building_id = state.objects.items[building_idx].id;
    const obj_id = state.objects.items[sel].id;
    if (obj_id == building_id) {
        project_editor_state.setStatus(state, "A building cannot be attached to itself");
        return;
    }
    if (!scene_hierarchy.canSetParent(state.objects.items, obj_id, building_id)) {
        project_editor_state.setStatus(state, "Cannot attach: would create a parent cycle");
        return;
    }
    project_editor_edit.pushUndoSnapshot(state);
    state.objects.items[sel].parent_id = building_id;
    state.scene_dirty = true;
    project_editor_state.setStatus(state, "Attached to active building");
}

/// Clear the selected object's parent so it no longer moves with a building.
pub fn detachSelected(state: *ProjectEditorState) void {
    const sel = state.selected_object orelse {
        project_editor_state.setStatus(state, "Select an attached prop first");
        return;
    };
    if (state.objects.items[sel].parent_id == null) {
        project_editor_state.setStatus(state, "Selection has no parent");
        return;
    }
    project_editor_edit.pushUndoSnapshot(state);
    state.objects.items[sel].parent_id = null;
    state.scene_dirty = true;
    project_editor_state.setStatus(state, "Detached from building");
}

const testing = std.testing;

fn testBuilding(id: u64) SceneObject {
    return .{
        .id = id,
        .name = @constCast("Building"),
        .mesh = .{ .vertices = &.{}, .indices = &.{} },
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = &.{},
        .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .components = &.{@constCast(arch.building_marker)},
    };
}

fn testProp(id: u64) SceneObject {
    return .{
        .id = id,
        .name = @constCast("Prop"),
        .mesh = .{ .vertices = &.{}, .indices = &.{} },
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = &.{},
        .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    };
}

test "editTargetIndex adopts the selected building and makes it active" {
    var state: ProjectEditorState = undefined;
    state.objects = .empty;
    defer state.objects.deinit(testing.allocator);
    try state.objects.append(testing.allocator, testProp(1));
    try state.objects.append(testing.allocator, testBuilding(2));
    state.active_building_id = null;
    state.selected_object = 1;

    const idx = editTargetIndex(&state);
    try testing.expectEqual(@as(?usize, 1), idx);
    try testing.expectEqual(@as(?u64, 2), state.active_building_id);
}

test "activeBuildingIndex clears a stale id" {
    var state: ProjectEditorState = undefined;
    state.objects = .empty;
    defer state.objects.deinit(testing.allocator);
    try state.objects.append(testing.allocator, testProp(1));
    state.active_building_id = 99;
    state.selected_object = null;

    try testing.expectEqual(@as(?usize, null), activeBuildingIndex(&state));
    try testing.expectEqual(@as(?u64, null), state.active_building_id);
}

test "attachSelectedToActiveBuilding parents the prop to the building" {
    var state: ProjectEditorState = undefined;
    state.allocator = testing.allocator;
    state.objects = .empty;
    defer state.objects.deinit(testing.allocator);
    state.undo_stack = .empty;
    state.redo_stack = .empty;
    defer project_editor_edit.clearUndoHistory(&state);
    state.animations = .empty;
    state.skeletons = .empty;
    state.next_object_id = 3;
    state.status_len = 0;
    state.scene_dirty = false;
    try state.objects.append(testing.allocator, testBuilding(1));
    try state.objects.append(testing.allocator, testProp(2));
    state.active_building_id = 1;
    state.selected_object = 1;

    attachSelectedToActiveBuilding(&state);
    try testing.expectEqual(@as(?u64, 1), state.objects.items[1].parent_id);
    try testing.expectEqual(@as(usize, 1), buildingChildCount(&state, 1));

    detachSelected(&state);
    try testing.expectEqual(@as(?u64, null), state.objects.items[1].parent_id);
}
