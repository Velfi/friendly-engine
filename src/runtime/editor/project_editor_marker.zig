const std = @import("std");
const shared = @import("runtime_shared");
const project_editor_edit = @import("project_editor_edit.zig");
const project_editor_state = @import("project_editor_state.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const SceneObject = @import("editor_scene_object.zig").SceneObject;
const scene_marker = shared.scene_marker;

pub fn setSelectedKind(state: *ProjectEditorState, kind: scene_marker.Kind) !void {
    const marker = try editableSelectedMarker(state);
    project_editor_edit.pushUndoSnapshot(state);
    marker.kind = kind;
    markChanged(state, marker);
}

pub fn setSelectedShape(state: *ProjectEditorState, shape: scene_marker.Shape) !void {
    const marker = try editableSelectedMarker(state);
    project_editor_edit.pushUndoSnapshot(state);
    marker.shape = shape;
    markChanged(state, marker);
}

pub fn setSelectedMarkerId(state: *ProjectEditorState, value: []const u8) !void {
    const marker = try editableSelectedMarker(state);
    const owned = try normalizedCopy(state.allocator, value);
    errdefer if (owned.len > 0) state.allocator.free(owned);
    project_editor_edit.pushUndoSnapshot(state);
    replaceOwned(state.allocator, &marker.marker_id, owned);
    markChanged(state, marker);
}

pub fn setSelectedGroup(state: *ProjectEditorState, value: []const u8) !void {
    const marker = try editableSelectedMarker(state);
    const owned = try normalizedCopy(state.allocator, value);
    errdefer if (owned.len > 0) state.allocator.free(owned);
    project_editor_edit.pushUndoSnapshot(state);
    replaceOwned(state.allocator, &marker.group, owned);
    markChanged(state, marker);
}

pub fn setSelectedBinding(state: *ProjectEditorState, value: []const u8) !void {
    const marker = try editableSelectedMarker(state);
    const owned = try normalizedCopy(state.allocator, value);
    errdefer if (owned.len > 0) state.allocator.free(owned);
    project_editor_edit.pushUndoSnapshot(state);
    replaceOwned(state.allocator, &marker.binding, owned);
    markChanged(state, marker);
}

pub fn setSelectedRadius(state: *ProjectEditorState, radius: f32) !void {
    if (!std.math.isFinite(radius)) return error.InvalidMarkerRadius;
    const marker = try editableSelectedMarker(state);
    project_editor_edit.pushUndoSnapshot(state);
    marker.radius = radius;
    markChanged(state, marker);
}

pub fn setSelectedOrder(state: *ProjectEditorState, order: i32) !void {
    const marker = try editableSelectedMarker(state);
    project_editor_edit.pushUndoSnapshot(state);
    marker.order = order;
    markChanged(state, marker);
}

fn editableSelectedMarker(state: *ProjectEditorState) !*scene_marker.Marker {
    const idx = state.selected_object orelse return error.NoSelectedMarker;
    if (idx >= state.objects.items.len) return error.NoSelectedMarker;
    const obj = &state.objects.items[idx];
    if (!obj.canModifyObject()) return error.MarkerObjectLocked;
    return if (obj.marker) |*marker| marker else error.NoSelectedMarker;
}

fn markChanged(state: *ProjectEditorState, marker: *scene_marker.Marker) void {
    state.scene_dirty = true;
    marker.validate() catch |err| {
        var buf: [96]u8 = undefined;
        project_editor_state.setStatus(state, std.fmt.bufPrint(&buf, "Invalid marker: {s}", .{@errorName(err)}) catch "Invalid marker");
        return;
    };
    project_editor_state.setStatus(state, "Marker updated");
}

fn normalizedCopy(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    const trimmed = std.mem.trim(u8, value, " \t\r\n");
    return if (trimmed.len > 0) try allocator.dupe(u8, trimmed) else "";
}

fn replaceOwned(allocator: std.mem.Allocator, slot: *[]u8, owned: []u8) void {
    if (slot.len > 0) allocator.free(slot.*);
    slot.* = owned;
}

test "marker text edits can leave invalid data visible and dirty" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
    };
    defer state.deinit();
    var marker = try scene_marker.defaultForKind(std.testing.allocator, .player_start);
    errdefer marker.deinit(std.testing.allocator);
    try state.objects.append(std.testing.allocator, try testMarkerObject(std.testing.allocator, marker));
    state.selected_object = 0;

    try setSelectedBinding(&state, "  \n");

    try std.testing.expect(state.scene_dirty);
    try std.testing.expectEqual(@as(usize, 1), state.undo_stack.items.len);
    try std.testing.expectEqualStrings("", state.objects.items[0].marker.?.binding);
    try std.testing.expectError(error.MissingMarkerBinding, state.objects.items[0].marker.?.validate());
}

test "marker enum and numeric edits update selected marker" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
    };
    defer state.deinit();
    var marker = try scene_marker.defaultForKind(std.testing.allocator, .spawn_point);
    errdefer marker.deinit(std.testing.allocator);
    try state.objects.append(std.testing.allocator, try testMarkerObject(std.testing.allocator, marker));
    state.selected_object = 0;

    try setSelectedShape(&state, .sphere);
    try setSelectedRadius(&state, 3.5);
    try setSelectedOrder(&state, 7);

    const edited = state.objects.items[0].marker.?;
    try std.testing.expectEqual(scene_marker.Shape.sphere, edited.shape);
    try std.testing.expectApproxEqAbs(@as(f32, 3.5), edited.radius, 0.001);
    try std.testing.expectEqual(@as(i32, 7), edited.order);
}

fn testMarkerObject(allocator: std.mem.Allocator, marker: scene_marker.Marker) !SceneObject {
    return .{
        .id = 1,
        .name = try allocator.dupe(u8, "marker"),
        .mesh = .{ .vertices = &.{}, .indices = &.{} },
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = try allocator.dupe(u8, ""),
        .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .object_kind = .marker,
        .marker = marker,
    };
}
