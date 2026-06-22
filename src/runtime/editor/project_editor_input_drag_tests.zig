const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const project_editor_input_drag = @import("project_editor_input_drag.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_edit = @import("project_editor_edit.zig");

const core_ui = friendly_engine.modules.core_ui;

test "pending object drag does not start without primary held" {
    var state = project_editor_state.ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .mode = .layout,
        .object_tool = .move,
        .selected_object = 0,
        .pending_object_drag = .move_object,
        .click_start_x = 0,
        .click_start_y = 0,
    };

    try state.objects.append(std.testing.allocator, .{
        .id = 1,
        .name = try std.testing.allocator.dupe(u8, "Box"),
        .mesh = .{ .vertices = &.{}, .indices = &.{} },
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = &.{},
        .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    });
    defer {
        for (state.objects.items) |*obj| obj.deinit(std.testing.allocator);
        state.objects.deinit(std.testing.allocator);
    }

    project_editor_input_drag.handleDrag(&state, .{
        .mouse_position = .{ .x = 100, .y = 100 },
        .primary_down = false,
    });

    try std.testing.expect(state.drag_mode == .none);
    try std.testing.expectEqual(@as(f32, 0), state.objects.items[0].position.x);
}

test "pending object drag starts only after threshold while primary held" {
    var state = project_editor_state.ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .mode = .layout,
        .object_tool = .move,
        .selected_object = 0,
        .pending_object_drag = .move_object,
        .click_start_x = 0,
        .click_start_y = 0,
    };

    try state.objects.append(std.testing.allocator, .{
        .id = 1,
        .name = try std.testing.allocator.dupe(u8, "Box"),
        .mesh = .{ .vertices = &.{}, .indices = &.{} },
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = &.{},
        .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    });
    defer {
        project_editor_edit.clearUndoHistory(&state);
        for (state.objects.items) |*obj| obj.deinit(std.testing.allocator);
        state.objects.deinit(std.testing.allocator);
    }

    project_editor_input_drag.handleDrag(&state, .{
        .mouse_position = .{ .x = 10, .y = 0 },
        .primary_down = true,
    });

    try std.testing.expect(state.drag_mode == .move_object);
}

test "view nav pan button drags opposite regular camera pan" {
    var regular = project_editor_state.ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .drag_mode = .camera_pan,
        .drag_last_x = 0,
        .drag_last_y = 0,
    };
    var nav_button = regular;
    nav_button.active_view_nav = .pan;
    const start = regular.camera.target;

    project_editor_input_drag.handleDrag(&regular, .{
        .mouse_position = .{ .x = 20, .y = 12 },
    });
    project_editor_input_drag.handleDrag(&nav_button, .{
        .mouse_position = .{ .x = 20, .y = 12 },
    });

    try std.testing.expectApproxEqAbs(start.x - regular.camera.target.x, nav_button.camera.target.x - start.x, 0.0001);
    try std.testing.expectApproxEqAbs(start.y - regular.camera.target.y, nav_button.camera.target.y - start.y, 0.0001);
    try std.testing.expectApproxEqAbs(start.z - regular.camera.target.z, nav_button.camera.target.z - start.z, 0.0001);
}

test "selection box drag becomes active after threshold" {
    var state = project_editor_state.ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .drag_mode = .selection_box,
        .viewport_screen_rect = .{ .x = 10, .y = 20, .w = 200, .h = 100 },
        .click_start_x = 30,
        .click_start_y = 45,
        .drag_last_x = 30,
        .drag_last_y = 45,
        .selection_box_start = .{ .x = 20, .y = 25 },
        .selection_box_end = .{ .x = 20, .y = 25 },
    };
    state.active_gesture.begin(.select_box);

    project_editor_input_drag.handleDrag(&state, .{
        .mouse_position = .{ .x = 55, .y = 80 },
        .primary_down = true,
    });

    try std.testing.expect(state.selection_box_active);
    try std.testing.expect(state.drag_moved);
    try std.testing.expectEqual(.select_box, state.active_gesture.kind);
    try std.testing.expectEqual(.dragging, state.active_gesture.phase);
    try std.testing.expectEqual(@as(f32, 45), state.selection_box_end.x);
    try std.testing.expectEqual(@as(f32, 60), state.selection_box_end.y);
}
