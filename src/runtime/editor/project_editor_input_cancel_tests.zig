const std = @import("std");
const shared = @import("runtime_shared");
const blockout = @import("project_editor_blockout.zig");
const project_editor_edit = @import("project_editor_edit.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_input_cancel = @import("project_editor_input_cancel.zig");

test "escape cancels active move drag and restores snapshot" {
    var state = project_editor_state.ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
    };
    defer {
        project_editor_edit.clearUndoHistory(&state);
        for (state.objects.items) |*obj| obj.deinit(std.testing.allocator);
        state.objects.deinit(std.testing.allocator);
    }

    try blockout.addBlockoutRamp(&state);
    const original_x = state.objects.items[0].position.x;
    project_editor_edit.pushUndoSnapshot(&state);
    state.objects.items[0].position.x = 99;
    state.drag_mode = .move_object;
    state.active_gesture.begin(.shape_handle);
    state.active_gesture.drag();

    project_editor_input_cancel.cancelOngoingAction(&state);

    try std.testing.expectEqual(original_x, state.objects.items[0].position.x);
    try std.testing.expect(state.drag_mode == .none);
    try std.testing.expectEqual(.shape_handle, state.active_gesture.kind);
    try std.testing.expectEqual(.cancelled, state.active_gesture.phase);
}

test "clear undo history leaves stacks reusable" {
    var state = project_editor_state.ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
    };
    defer {
        project_editor_edit.clearUndoHistory(&state);
        for (state.objects.items) |*obj| obj.deinit(std.testing.allocator);
        state.objects.deinit(std.testing.allocator);
    }

    try blockout.addBlockoutRamp(&state);
    try std.testing.expectEqual(@as(usize, 1), state.undo_stack.items.len);

    project_editor_edit.clearUndoHistory(&state);
    try std.testing.expectEqual(@as(usize, 0), state.undo_stack.items.len);
    try std.testing.expectEqual(@as(usize, 0), state.redo_stack.items.len);

    project_editor_edit.pushUndoSnapshot(&state);
    try std.testing.expectEqual(@as(usize, 1), state.undo_stack.items.len);
}

test "escape clears sub-selection before object selection" {
    var state = project_editor_state.ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
    };

    state.selected_object = 0;
    state.selected_face = 2;

    project_editor_input_cancel.cancelOngoingAction(&state);

    try std.testing.expect(state.selected_face == null);
    try std.testing.expect(state.selected_object == 0);
}

test "escape clears world curve selection before object selection" {
    var state = project_editor_state.ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .selected_object = 0,
        .selected_world_curve_hit = .{ .target = .road, .element = .segment },
        .selected_road_edge_id = try std.testing.allocator.dupe(u8, "road.edge.1"),
    };

    project_editor_input_cancel.cancelOngoingAction(&state);

    try std.testing.expect(state.selected_world_curve_hit.isNone());
    try std.testing.expect(state.selected_road_edge_id == null);
    try std.testing.expect(state.selected_object == 0);
    try std.testing.expectEqualStrings("Selection cleared", state.status_buf[0..state.status_len]);
}

test "escape stops play preview" {
    var state = project_editor_state.ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
    };

    state.is_playing = true;
    project_editor_input_cancel.cancelOngoingAction(&state);
    try std.testing.expect(!state.is_playing);
}

test "escape cancels world curve gizmo drag and restores snapshot" {
    var state = project_editor_state.ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
    };
    defer {
        project_editor_edit.clearUndoHistory(&state);
        for (state.objects.items) |*obj| obj.deinit(std.testing.allocator);
        state.objects.deinit(std.testing.allocator);
    }

    const mesh = try shared.geometry.buildPrimitive(std.testing.allocator, .box, .{ .width = 1, .height = 1, .depth = 1 });
    try state.objects.append(std.testing.allocator, .{
        .id = 1,
        .name = try std.testing.allocator.dupe(u8, "Box"),
        .mesh = mesh,
        .position = .{ .x = 2, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = &.{},
        .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .primitive_kind = .box,
    });

    project_editor_edit.beginUndoBatch(&state, "World curve edit");
    project_editor_edit.pushUndoSnapshot(&state);
    state.objects.items[0].position.x = 42;
    state.drag_mode = .world_curve_gizmo;
    state.world_curve_drag_anchor = .{ .x = 1, .y = 0, .z = 2 };
    state.world_curve_drag_state = .{ .hit = .{ .target = .water_volume, .element = .point } };

    project_editor_input_cancel.cancelOngoingAction(&state);

    try std.testing.expectEqual(@as(f32, 2), state.objects.items[0].position.x);
    try std.testing.expectEqual(@as(u32, 0), state.undo_batch_depth);
    try std.testing.expect(!state.undo_batch_snapshot_taken);
    try std.testing.expect(state.drag_mode == .none);
    try std.testing.expect(state.world_curve_drag_anchor == null);
    try std.testing.expect(state.world_curve_drag_state.hit.isNone());
    try std.testing.expectEqualStrings("Cancelled", state.status_buf[0..state.status_len]);
}

test "escape cancels scatter zone drag and closes empty undo batch" {
    var state = project_editor_state.ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .drag_mode = .world_scatter_zone,
        .world_scatter_drag_start = .{ .x = 1, .y = 0, .z = 2 },
        .world_scatter_drag_end = .{ .x = 4, .y = 0, .z = 5 },
    };
    defer project_editor_edit.clearUndoHistory(&state);

    project_editor_edit.beginUndoBatch(&state, "World curve edit");

    project_editor_input_cancel.cancelOngoingAction(&state);

    try std.testing.expectEqual(@as(u32, 0), state.undo_batch_depth);
    try std.testing.expect(!state.undo_batch_snapshot_taken);
    try std.testing.expectEqual(@as(usize, 0), state.undo_stack.items.len);
    try std.testing.expect(state.world_scatter_drag_start == null);
    try std.testing.expect(state.world_scatter_drag_end == null);
    try std.testing.expect(state.drag_mode == .none);
    try std.testing.expectEqualStrings("Cancelled", state.status_buf[0..state.status_len]);
}

test "escape cancels scatter density paint and restores snapshot" {
    var state = project_editor_state.ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .drag_mode = .world_scatter_density,
    };
    defer {
        project_editor_edit.clearUndoHistory(&state);
        for (state.objects.items) |*obj| obj.deinit(std.testing.allocator);
        state.objects.deinit(std.testing.allocator);
    }

    const mesh = try shared.geometry.buildPrimitive(std.testing.allocator, .box, .{ .width = 1, .height = 1, .depth = 1 });
    try state.objects.append(std.testing.allocator, .{
        .id = 1,
        .name = try std.testing.allocator.dupe(u8, "Density Probe"),
        .mesh = mesh,
        .position = .{ .x = 3, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = &.{},
        .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .primitive_kind = .box,
    });

    project_editor_edit.beginUndoBatch(&state, "World curve edit");
    project_editor_edit.pushUndoSnapshot(&state);
    state.objects.items[0].position.x = 99;

    project_editor_input_cancel.cancelOngoingAction(&state);

    try std.testing.expectEqual(@as(f32, 3), state.objects.items[0].position.x);
    try std.testing.expectEqual(@as(u32, 0), state.undo_batch_depth);
    try std.testing.expect(!state.undo_batch_snapshot_taken);
    try std.testing.expect(state.drag_mode == .none);
    try std.testing.expectEqualStrings("Cancelled", state.status_buf[0..state.status_len]);
}
