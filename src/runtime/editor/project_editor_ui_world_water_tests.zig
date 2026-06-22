const std = @import("std");
const friendly_engine = @import("friendly_engine");
const curve_drawing = @import("project_editor_curve_drawing.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_ui_world_water = @import("project_editor_ui_world_water.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;

test "water height handles show hover and selected states" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .world_tool = .water,
        .selected_world_curve_hit = .{ .target = .water_volume, .element = .handle_start, .index = 2 },
        .hovered_world_curve_hit = .{ .target = .water_volume, .element = .handle_end, .index = 2 },
    };

    try std.testing.expectEqual(curve_drawing.HandleState.selected, project_editor_ui_world_water.heightHandleState(&state, 2, .handle_start));
    try std.testing.expectEqual(curve_drawing.HandleState.hover, project_editor_ui_world_water.heightHandleState(&state, 2, .handle_end));
    try std.testing.expectEqual(curve_drawing.HandleState.preview, project_editor_ui_world_water.heightHandleState(&state, 3, .handle_start));
    try std.testing.expectEqual(curve_drawing.HandleState.preview, project_editor_ui_world_water.heightHandleState(&state, 2, .point));
}

test "water edge delete removes the following footprint point" {
    try std.testing.expectEqual(
        @as(?usize, 2),
        project_editor_ui_world_water.deletePointIndexForHit(.{ .target = .water_volume, .element = .segment, .sub_index = 1 }, 4),
    );
    try std.testing.expectEqual(
        @as(?usize, 0),
        project_editor_ui_world_water.deletePointIndexForHit(.{ .target = .water_volume, .element = .segment, .sub_index = 3 }, 4),
    );
    try std.testing.expectEqual(
        @as(?usize, null),
        project_editor_ui_world_water.deletePointIndexForHit(.{ .target = .water_volume, .element = .segment, .sub_index = 0 }, 3),
    );
}

test "water footprint point removal preserves polygon order" {
    const allocator = std.testing.allocator;
    var points = try allocator.alloc([2]f32, 4);
    points[0] = .{ 0, 0 };
    points[1] = .{ 8, 0 };
    points[2] = .{ 8, 8 };
    points[3] = .{ 0, 8 };
    var volume = friendly_engine.modules.water.WaterVolume{
        .id = @constCast("test"),
        .points = points,
        .surface_y = 4,
        .bottom_y = 0,
        .material = @constCast("water.lake.clear"),
    };
    defer allocator.free(volume.points);

    try project_editor_ui_world_water.removePointAt(allocator, &volume, 1);

    try std.testing.expectEqual(@as(usize, 3), volume.points.len);
    try std.testing.expectEqual(@as(f32, 0), volume.points[0][0]);
    try std.testing.expectEqual(@as(f32, 0), volume.points[0][1]);
    try std.testing.expectEqual(@as(f32, 8), volume.points[1][0]);
    try std.testing.expectEqual(@as(f32, 8), volume.points[1][1]);
    try std.testing.expectEqual(@as(f32, 0), volume.points[2][0]);
    try std.testing.expectEqual(@as(f32, 8), volume.points[2][1]);
}

test "water state applies to selected volume settings" {
    const allocator = std.testing.allocator;
    var state = ProjectEditorState{
        .allocator = allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .water_surface_y = 7.5,
        .water_bottom_y = 9.0,
        .water_swimmable = false,
        .water_linked_to_ocean = true,
        .water_current_x = 1.25,
        .water_current_y = 0.5,
        .water_current_z = -2.0,
    };
    var points = try allocator.alloc([2]f32, 4);
    points[0] = .{ 0, 0 };
    points[1] = .{ 8, 0 };
    points[2] = .{ 8, 8 };
    points[3] = .{ 0, 8 };
    var volume = friendly_engine.modules.water.WaterVolume{
        .id = try allocator.dupe(u8, "pond"),
        .kind = .lake,
        .material = try allocator.dupe(u8, "water.lake.clear"),
        .surface_y = 2.0,
        .bottom_y = 0.0,
        .points = points,
    };
    defer volume.deinit(allocator);

    try project_editor_ui_world_water.applyStateToVolume(allocator, &state, &volume);

    try std.testing.expectEqual(@as(f32, 7.5), volume.surface_y);
    try std.testing.expectEqual(@as(f32, 7.25), volume.bottom_y);
    try std.testing.expectEqual(@as(f32, 7.25), state.water_bottom_y);
    try std.testing.expect(!volume.swimmable);
    try std.testing.expect(volume.linked_to_ocean);
    try std.testing.expectEqual(friendly_engine.modules.water.WaterKind.ocean_near, volume.kind);
    try std.testing.expectEqualStrings("water.ocean.near", volume.material);
    try std.testing.expectEqual(@as(f32, 1.25), volume.current.x);
    try std.testing.expectEqual(@as(f32, 0.5), volume.current.y);
    try std.testing.expectEqual(@as(f32, -2.0), volume.current.z);
}
