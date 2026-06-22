const std = @import("std");
const shared = @import("runtime_shared");
const root = @import("project_editor_scene.zig");
const blockout = @import("project_editor_blockout.zig");
const blockout_primitives = @import("project_editor_blockout_primitives.zig");
const scene_object = @import("editor_scene_object.zig");
const editor_raycast = @import("editor_raycast.zig");
const project_editor_edit = @import("project_editor_edit.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_types = @import("project_editor_types.zig");
const world_authoring_manifest = @import("project_editor_world_authoring_manifest.zig");

const editor_math = shared.editor_math;
const geometry = shared.geometry;
const scene_marker = shared.scene_marker;
const blockoutBrushAabb = root.blockoutBrushAabb;
const architectureDragPreviewAabb = blockout.architectureDragPreviewAabb;
const subtractBlockoutBox = root.subtractBlockoutBox;
const subtractBlockoutWedge = root.subtractBlockoutWedge;
const addBlockoutBoxInternal = blockout.addBlockoutBoxInternal;
const addBlockoutRamp = blockout.addBlockoutRamp;
const addBlockoutRampAt = blockout.addBlockoutRampAt;
const addBlockoutCylinderAt = blockout.addBlockoutCylinderAt;
const finishBlockoutBrush = blockout.finishBlockoutBrush;
const addFloorplanCell = blockout.addFloorplanCell;
const extrudeSelectedFloorplanToRoom = blockout.extrudeSelectedFloorplanToRoom;
const addRoofForFloorplans = blockout.addRoofForFloorplans;
const addPlayerStartSpawner = blockout.addPlayerStartSpawner;
const placeWallOutlinePointAt = blockout.placeWallOutlinePointAt;
const addDoorwayPrimitive = blockout_primitives.addDoorway;
const raycastScene = editor_raycast.raycastScene;
const raycastMesh = editor_raycast.raycastMesh;
const SceneObject = scene_object.SceneObject;

test "marker selection scope clears incompatible mesh selection" {
    var state = project_editor_state.ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
    };
    defer {
        for (state.objects.items) |*obj| obj.deinit(std.testing.allocator);
        state.objects.deinit(std.testing.allocator);
        state.selected_object_ids.deinit(std.testing.allocator);
    }

    try state.objects.append(std.testing.allocator, try testOwnedObject(1, "mesh", null));
    try state.objects.append(std.testing.allocator, try testOwnedObject(2, "marker", try scene_marker.defaultForKind(std.testing.allocator, .objective)));
    state.selected_object = 0;
    try state.selected_object_ids.append(std.testing.allocator, 1);
    try state.selected_object_ids.append(std.testing.allocator, 2);

    root.setSelectionScope(&state, .marker);

    try std.testing.expectEqual(@as(?usize, null), state.selected_object);
    try std.testing.expectEqual(@as(usize, 1), state.selected_object_ids.items.len);
    try std.testing.expectEqual(@as(u64, 2), state.selected_object_ids.items[0]);
}

test "marker selection scope keeps selected marker" {
    var state = project_editor_state.ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
    };
    defer {
        for (state.objects.items) |*obj| obj.deinit(std.testing.allocator);
        state.objects.deinit(std.testing.allocator);
    }

    try state.objects.append(std.testing.allocator, try testOwnedObject(1, "marker", try scene_marker.defaultForKind(std.testing.allocator, .spawn_point)));
    state.selected_object = 0;

    root.setSelectionScope(&state, .marker);

    try std.testing.expectEqual(@as(?usize, 0), state.selected_object);
}

test "shape source scope clears incompatible object selection" {
    var state = project_editor_state.ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
    };
    defer {
        for (state.objects.items) |*obj| obj.deinit(std.testing.allocator);
        state.objects.deinit(std.testing.allocator);
        state.selected_object_ids.deinit(std.testing.allocator);
    }

    try state.objects.append(std.testing.allocator, try testOwnedObject(1, "mesh", null));
    state.selected_object = 0;
    try state.selected_object_ids.append(std.testing.allocator, 1);

    root.setSelectionScope(&state, .source);

    try std.testing.expectEqual(project_editor_state.EditorMode.prop_creation, state.mode);
    try std.testing.expectEqual(@as(?usize, null), state.selected_object);
    try std.testing.expectEqual(@as(usize, 0), state.selected_object_ids.items.len);
    try std.testing.expect(!state.selected_shape_source);
}

test "shape operation scope keeps active operation selection but clears object selection" {
    var state = project_editor_state.ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .prop_sketch_mode = .face,
    };
    defer {
        for (state.objects.items) |*obj| obj.deinit(std.testing.allocator);
        state.objects.deinit(std.testing.allocator);
        state.selected_object_ids.deinit(std.testing.allocator);
        state.prop_sketch_points.deinit(std.testing.allocator);
    }

    try state.objects.append(std.testing.allocator, try testOwnedObject(1, "mesh", null));
    try state.prop_sketch_points.append(std.testing.allocator, .{ .x = 0, .y = 0, .z = 0 });
    try state.prop_sketch_points.append(std.testing.allocator, .{ .x = 1, .y = 0, .z = 0 });
    try state.prop_sketch_points.append(std.testing.allocator, .{ .x = 0, .y = 0, .z = 1 });
    state.selected_object = 0;
    try state.selected_object_ids.append(std.testing.allocator, 1);

    root.setSelectionScope(&state, .operation);

    try std.testing.expectEqual(@as(?usize, null), state.selected_object);
    try std.testing.expectEqual(@as(usize, 0), state.selected_object_ids.items.len);
    try std.testing.expect(!state.selected_shape_source);
    try std.testing.expect(state.selected_shape_operation);
}

fn testOwnedObject(id: u64, name: []const u8, marker: ?scene_marker.Marker) !SceneObject {
    return .{
        .id = id,
        .name = try std.testing.allocator.dupe(u8, name),
        .mesh = try geometry.buildPrimitive(std.testing.allocator, .box, .{ .width = 1, .height = 1, .depth = 1 }),
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = try std.testing.allocator.alloc(u8, 0),
        .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .object_kind = if (marker != null) .marker else .mesh,
        .marker = marker,
    };
}

test "blockout brush aabb from drag" {
    var state = project_editor_state.ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
    };
    state.blockout_drag_start = .{ .x = 0, .y = 0, .z = 0 };
    state.blockout_drag_end = .{ .x = 2, .y = 0, .z = 1 };
    state.blockout_brush_size = 2;
    const bounds = blockoutBrushAabb(&state).?;
    try std.testing.expectApproxEqAbs(@as(f32, 2), bounds.max.x - bounds.min.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1), bounds.max.z - bounds.min.z, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2), bounds.max.y, 0.001);
}

test "architecture drag preview uses primitive dimensions" {
    var state = project_editor_state.ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
    };

    state.blockout_drag_start = .{ .x = 0, .y = 0, .z = 0 };
    state.blockout_drag_end = .{ .x = 3, .y = 0, .z = 2 };
    state.blockout_brush_size = 1;
    state.architecture_wall_height = 3.25;
    state.architecture_door_height = 2.1;
    state.architecture_window_sill = 0.9;
    state.architecture_window_height = 1.2;

    state.architecture_tool = .floorplan;
    var bounds = architectureDragPreviewAabb(&state).?;
    try std.testing.expectApproxEqAbs(@as(f32, 3.25), bounds.max.y, 0.001);

    state.architecture_tool = .door;
    bounds = architectureDragPreviewAabb(&state).?;
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), bounds.min.y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2.1), bounds.max.y, 0.001);

    state.architecture_tool = .window;
    bounds = architectureDragPreviewAabb(&state).?;
    try std.testing.expectApproxEqAbs(@as(f32, 0.9), bounds.min.y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2.1), bounds.max.y, 0.001);
}

test "delete selected prefers visible world curve selection over object" {
    var state = project_editor_state.ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .mode = .world_creation,
        .world_tool = .water,
        .selected_object = 0,
        .selected_world_curve_hit = .{ .target = .water_volume, .element = .handle_start },
    };
    defer {
        for (state.objects.items) |*obj| obj.deinit(std.testing.allocator);
        state.objects.deinit(std.testing.allocator);
    }

    const mesh = try geometry.buildPrimitive(std.testing.allocator, .box, .{ .width = 1, .height = 1, .depth = 1 });
    try state.objects.append(std.testing.allocator, .{
        .id = 1,
        .name = try std.testing.allocator.dupe(u8, "Box"),
        .mesh = mesh,
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = &.{},
        .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .primitive_kind = .box,
    });

    try root.deleteSelected(&state);

    try std.testing.expectEqual(@as(usize, 1), state.objects.items.len);
    try std.testing.expectEqual(@as(?usize, 0), state.selected_object);
    try std.testing.expectEqualStrings("Drag the surface handle to change water height", state.status_buf[0..state.status_len]);
}

test "blockout subtract rebuilds doorway wall segments" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = world_authoring_manifest.world_manifest_path,
        .data =
        \\world version=1 id="main" cell_size_m=64 {
        \\  cell coord="0,0,0" authoring="scenes/main.kdl"
        \\}
        \\
        ,
    });
    var project_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const project_path_len = try tmp.dir.realPath(std.testing.io, &project_path_buf);
    const project_path = try std.testing.allocator.dupe(u8, project_path_buf[0..project_path_len]);
    defer std.testing.allocator.free(project_path);

    var state = project_editor_state.ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = project_path,
        .active_world_manifest_path = world_authoring_manifest.world_manifest_path,
        .project_name = "",
        .objects = .empty,
    };
    defer {
        for (state.objects.items) |*obj| obj.deinit(std.testing.allocator);
        state.objects.deinit(std.testing.allocator);
    }

    try addBlockoutBoxInternal(
        &state,
        .{ .x = 0, .y = 0, .z = 0 },
        .{ .x = 6, .y = 3, .z = 1 },
        false,
    );
    try std.testing.expectEqual(@as(usize, 1), state.objects.items.len);

    try subtractBlockoutBox(
        &state,
        .{ .x = 2, .y = 0, .z = 0 },
        .{ .x = 4, .y = 2.2, .z = 1 },
    );
    try std.testing.expectEqual(@as(usize, 3), state.objects.items.len);
    const csg_bytes = try tmp.dir.readFileAlloc(std.testing.io, "layers/local_csg.kdl", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(csg_bytes);
    try std.testing.expect(std.mem.indexOf(u8, csg_bytes, "op=\"subtract_block\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, csg_bytes, "op=\"doorway_subtract\"") == null);
}

test "doorway primitive persists doorway subtract semantics" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = world_authoring_manifest.world_manifest_path,
        .data =
        \\world version=1 id="main" cell_size_m=64 {
        \\  cell coord="0,0,0" authoring="scenes/main.kdl"
        \\}
        \\
        ,
    });
    var project_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const project_path_len = try tmp.dir.realPath(std.testing.io, &project_path_buf);
    const project_path = try std.testing.allocator.dupe(u8, project_path_buf[0..project_path_len]);
    defer std.testing.allocator.free(project_path);

    var state = project_editor_state.ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = project_path,
        .active_world_manifest_path = world_authoring_manifest.world_manifest_path,
        .project_name = "",
        .objects = .empty,
    };
    defer {
        project_editor_edit.clearUndoHistory(&state);
        for (state.objects.items) |*obj| obj.deinit(std.testing.allocator);
        state.objects.deinit(std.testing.allocator);
    }

    try addDoorwayPrimitive(&state);
    const csg_bytes = try tmp.dir.readFileAlloc(std.testing.io, "layers/local_csg.kdl", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(csg_bytes);
    try std.testing.expect(std.mem.indexOf(u8, csg_bytes, "op=\"doorway_subtract\"") != null);
}

test "selected floorplan extrudes into four room walls with collision" {
    // The drag-based `.floorplan` architecture tool now builds a semantic
    // `arch.Building` (see `finishArchitecturePrimitiveDrag`), not the legacy
    // box-primitive "Floorplan N" object that `extrudeSelectedFloorplanToRoom`
    // operates on. The floor-cell command path (`addFloorplanCell`) is the only
    // remaining way to create that legacy floorplan, so use it here.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = world_authoring_manifest.world_manifest_path,
        .data =
        \\world version=1 id="main" cell_size_m=64 {
        \\  cell coord="0,0,0" authoring="scenes/main.kdl"
        \\}
        \\
        ,
    });
    var project_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const project_path_len = try tmp.dir.realPath(std.testing.io, &project_path_buf);
    const project_path = try std.testing.allocator.dupe(u8, project_path_buf[0..project_path_len]);
    defer std.testing.allocator.free(project_path);

    var state = project_editor_state.ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = project_path,
        .active_world_manifest_path = world_authoring_manifest.world_manifest_path,
        .project_name = "",
        .objects = .empty,
    };
    defer {
        project_editor_edit.clearUndoHistory(&state);
        for (state.objects.items) |*obj| obj.deinit(std.testing.allocator);
        state.objects.deinit(std.testing.allocator);
    }

    state.architecture_wall_height = 3;
    state.architecture_wall_thickness = 0.25;
    try addFloorplanCell(&state);

    try std.testing.expectEqual(@as(usize, 1), state.objects.items.len);
    try std.testing.expectEqualStrings("Floorplan 1", state.objects.items[0].name);
    try std.testing.expect(state.objects.items[0].physics != null);

    try extrudeSelectedFloorplanToRoom(&state);

    try std.testing.expectEqual(@as(usize, 5), state.objects.items.len);
    try std.testing.expectEqualStrings("Room Wall 2", state.objects.items[1].name);
    try std.testing.expect(state.objects.items[1].physics != null);
    // Room walls are transient (not persisted), so addRoomWallSegment never
    // sets blockout_intent on them; verify the wall height from its placement
    // instead (it's centered at half the configured wall height).
    try std.testing.expectEqual(@as(?shared.scene_blockout.Intent, null), state.objects.items[1].blockout_intent);
    try std.testing.expectApproxEqAbs(@as(f32, 1.5), state.objects.items[1].position.y, 0.001);
    project_editor_edit.undo(&state);
    try std.testing.expectEqual(@as(usize, 1), state.objects.items.len);
}

test "adjacent floorplans extrude with shared edge open" {
    // As above: the legacy "Floorplan N" object that room extrusion targets
    // only comes from `addFloorplanCell` now; the drag tool builds a Building.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = world_authoring_manifest.world_manifest_path,
        .data =
        \\world version=1 id="main" cell_size_m=64 {
        \\  cell coord="0,0,0" authoring="scenes/main.kdl"
        \\}
        \\
        ,
    });
    var project_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const project_path_len = try tmp.dir.realPath(std.testing.io, &project_path_buf);
    const project_path = try std.testing.allocator.dupe(u8, project_path_buf[0..project_path_len]);
    defer std.testing.allocator.free(project_path);

    var state = project_editor_state.ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = project_path,
        .active_world_manifest_path = world_authoring_manifest.world_manifest_path,
        .project_name = "",
        .objects = .empty,
    };
    defer {
        project_editor_edit.clearUndoHistory(&state);
        for (state.objects.items) |*obj| obj.deinit(std.testing.allocator);
        state.objects.deinit(std.testing.allocator);
    }

    state.architecture_wall_height = 3;
    state.architecture_wall_thickness = 0.25;
    try addFloorplanCell(&state);
    try addFloorplanCell(&state);

    state.selected_object = 0;
    try extrudeSelectedFloorplanToRoom(&state);
    state.selected_object = 1;
    try extrudeSelectedFloorplanToRoom(&state);

    try std.testing.expectEqual(@as(usize, 8), state.objects.items.len);
    try std.testing.expectEqual(@as(usize, 0), countInternalSharedWalls(state.objects.items));
}

test "floor cell command path creates adjacent floorplans for room extrusion" {
    // addFloorplanCell persists to the world manifest, so it needs a real
    // project directory rather than the empty project_path used elsewhere.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = world_authoring_manifest.world_manifest_path,
        .data =
        \\world version=1 id="main" cell_size_m=64 {
        \\  cell coord="0,0,0" authoring="scenes/main.kdl"
        \\}
        \\
        ,
    });
    var project_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const project_path_len = try tmp.dir.realPath(std.testing.io, &project_path_buf);
    const project_path = try std.testing.allocator.dupe(u8, project_path_buf[0..project_path_len]);
    defer std.testing.allocator.free(project_path);

    var state = project_editor_state.ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = project_path,
        .active_world_manifest_path = world_authoring_manifest.world_manifest_path,
        .project_name = "",
        .objects = .empty,
    };
    defer {
        project_editor_edit.clearUndoHistory(&state);
        for (state.objects.items) |*obj| obj.deinit(std.testing.allocator);
        state.objects.deinit(std.testing.allocator);
    }

    try addFloorplanCell(&state);
    try addFloorplanCell(&state);

    try std.testing.expectEqual(@as(usize, 2), state.objects.items.len);
    try std.testing.expectEqualStrings("Floorplan 1", state.objects.items[0].name);
    try std.testing.expectEqualStrings("Floorplan 2", state.objects.items[1].name);
    try std.testing.expectApproxEqAbs(@as(f32, 0), state.objects.items[0].blockout_intent.?.min.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 4), state.objects.items[0].blockout_intent.?.max.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 4), state.objects.items[1].blockout_intent.?.min.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 8), state.objects.items[1].blockout_intent.?.max.x, 0.001);

    state.selected_object = 0;
    try extrudeSelectedFloorplanToRoom(&state);
    state.selected_object = 1;
    try extrudeSelectedFloorplanToRoom(&state);

    try std.testing.expectEqual(@as(usize, 8), state.objects.items.len);
    try std.testing.expectEqual(@as(usize, 0), countInternalSharedWalls(state.objects.items));
}

test "wall outline places arbitrary connected wall segments" {
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
        state.wall_outline_points.deinit(std.testing.allocator);
    }

    state.mode = .architecture_creation;
    state.architecture_tool = .wall;
    state.architecture_wall_height = 3;
    state.architecture_wall_thickness = 0.25;
    try placeWallOutlinePointAt(&state, .{ .x = 0, .y = 0, .z = 0 });
    try placeWallOutlinePointAt(&state, .{ .x = 3, .y = 0, .z = 4 });

    try std.testing.expectEqual(@as(usize, 1), state.objects.items.len);
    try std.testing.expectEqual(@as(usize, 2), state.wall_outline_points.items.len);
    const wall = &state.objects.items[0];
    try std.testing.expectEqualStrings("Architecture Wall Chain 1", wall.name);
    try std.testing.expect(wall.physics != null);

    var building = try shared.architecture.Building.parse(std.testing.allocator, wall.components);
    defer building.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), building.vertices.items.len);
    try std.testing.expectEqual(@as(usize, 1), building.walls.items.len);
    const segment = building.walls.items[0];
    const a = building.findVertex(segment.a).?;
    const b = building.findVertex(segment.b).?;
    try std.testing.expectApproxEqAbs(@as(f32, 0), a.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), a.z, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 3), b.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 4), b.z, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 3), segment.height, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), segment.thickness, 0.001);
}

test "wall drag raises a wall segment" {
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

    state.mode = .architecture_creation;
    state.architecture_tool = .wall;
    state.architecture_wall_height = 3;
    state.architecture_wall_thickness = 0.25;
    state.blockout_drag_start = .{ .x = 0, .y = 0, .z = 0 };
    state.blockout_drag_end = .{ .x = 3, .y = 0, .z = 4 };
    finishBlockoutBrush(&state);

    try std.testing.expectEqual(@as(usize, 1), state.objects.items.len);
    try std.testing.expectEqualStrings("Architecture Wall Chain 1", state.objects.items[0].name);
    try std.testing.expect(state.objects.items[0].physics != null);
}

test "zero length wall drag remains a wall outline click" {
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
        state.wall_outline_points.deinit(std.testing.allocator);
    }

    state.mode = .architecture_creation;
    state.architecture_tool = .wall;
    state.blockout_drag_start = .{ .x = 1, .y = 0, .z = 2 };
    state.blockout_drag_end = .{ .x = 1, .y = 0, .z = 2 };
    finishBlockoutBrush(&state);

    try std.testing.expectEqual(@as(usize, 0), state.objects.items.len);
    try std.testing.expectEqual(@as(usize, 1), state.wall_outline_points.items.len);
}

test "wall outline closes when placing near the first point" {
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
        state.wall_outline_points.deinit(std.testing.allocator);
    }

    state.mode = .architecture_creation;
    state.architecture_tool = .wall;
    try placeWallOutlinePointAt(&state, .{ .x = 0, .y = 0, .z = 0 });
    try placeWallOutlinePointAt(&state, .{ .x = 4, .y = 0, .z = 0 });
    try placeWallOutlinePointAt(&state, .{ .x = 4, .y = 0, .z = 3 });
    try placeWallOutlinePointAt(&state, .{ .x = 0.1, .y = 0, .z = 0.1 });

    // All three segments extend the same building (walls never start a new
    // disconnected object once one exists), so the closed loop is one object.
    try std.testing.expectEqual(@as(usize, 1), state.objects.items.len);
    try std.testing.expectEqual(@as(usize, 0), state.wall_outline_points.items.len);
    try std.testing.expectEqualStrings("Wall loop closed", state.status_buf[0..state.status_len]);

    const obj = &state.objects.items[0];
    try std.testing.expectEqualStrings("Architecture Wall Chain 1", obj.name);
    var building = try shared.architecture.Building.parse(std.testing.allocator, obj.components);
    defer building.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 3), building.vertices.items.len);
    try std.testing.expectEqual(@as(usize, 3), building.walls.items.len);
    try std.testing.expect(building.roof != null);
}

test "door cuts selected outline wall into walkable pieces" {
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
        state.wall_outline_points.deinit(std.testing.allocator);
    }

    state.mode = .architecture_creation;
    state.architecture_tool = .wall;
    state.architecture_wall_height = 3;
    try placeWallOutlinePointAt(&state, .{ .x = 0, .y = 0, .z = 0 });
    try placeWallOutlinePointAt(&state, .{ .x = 4, .y = 0, .z = 0 });
    state.selected_object = 0;
    state.architecture_tool = .door;
    state.architecture_door_height = 2.2;
    state.blockout_drag_start = .{ .x = 1.5, .y = 0, .z = 0 };
    state.blockout_drag_end = .{ .x = 2.5, .y = 0, .z = 0 };

    finishBlockoutBrush(&state);

    // The door is cut into the building's wall as a semantic opening, not a
    // separate wall-piece object: the building stays one object.
    try std.testing.expectEqual(@as(usize, 1), state.objects.items.len);
    try std.testing.expectEqualStrings("Door attached to wall", state.status_buf[0..state.status_len]);
    for (state.objects.items) |obj| try std.testing.expect(obj.physics != null);

    var building = try shared.architecture.Building.parse(std.testing.allocator, state.objects.items[0].components);
    defer building.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), building.openings.items.len);
    const opening = building.openings.items[0];
    try std.testing.expectEqual(shared.architecture.OpeningKind.door, opening.kind);
    try std.testing.expectApproxEqAbs(@as(f32, 0), opening.sill, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2.2), opening.height, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), opening.t, 0.001);
}

test "window cuts selected outline wall with sill and lintel pieces" {
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
        state.wall_outline_points.deinit(std.testing.allocator);
    }

    state.mode = .architecture_creation;
    state.architecture_tool = .wall;
    state.architecture_wall_height = 3;
    try placeWallOutlinePointAt(&state, .{ .x = 0, .y = 0, .z = 0 });
    try placeWallOutlinePointAt(&state, .{ .x = 4, .y = 0, .z = 0 });
    state.selected_object = 0;
    state.architecture_tool = .window;
    state.architecture_window_sill = 1.0;
    state.architecture_window_height = 1.0;
    state.blockout_drag_start = .{ .x = 1.5, .y = 0, .z = 0 };
    state.blockout_drag_end = .{ .x = 2.5, .y = 0, .z = 0 };

    finishBlockoutBrush(&state);

    // Same as the door case: the window becomes a semantic opening on the
    // building's wall instead of splitting it into separate sill/lintel objects.
    try std.testing.expectEqual(@as(usize, 1), state.objects.items.len);
    try std.testing.expectEqualStrings("Window attached to wall", state.status_buf[0..state.status_len]);
    for (state.objects.items) |obj| try std.testing.expect(obj.physics != null);

    var building = try shared.architecture.Building.parse(std.testing.allocator, state.objects.items[0].components);
    defer building.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), building.openings.items.len);
    const opening = building.openings.items[0];
    try std.testing.expectEqual(shared.architecture.OpeningKind.window, opening.kind);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), opening.sill, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), opening.height, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), opening.t, 0.001);
}

test "roof derives from adjacent floorplan footprint and stays non colliding" {
    // addRoofForFloorplans reads the legacy "Floorplan N" footprint, which only
    // addFloorplanCell produces now (the drag tool builds an arch.Building).
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = world_authoring_manifest.world_manifest_path,
        .data =
        \\world version=1 id="main" cell_size_m=64 {
        \\  cell coord="0,0,0" authoring="scenes/main.kdl"
        \\}
        \\
        ,
    });
    var project_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const project_path_len = try tmp.dir.realPath(std.testing.io, &project_path_buf);
    const project_path = try std.testing.allocator.dupe(u8, project_path_buf[0..project_path_len]);
    defer std.testing.allocator.free(project_path);

    var state = project_editor_state.ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = project_path,
        .active_world_manifest_path = world_authoring_manifest.world_manifest_path,
        .project_name = "",
        .objects = .empty,
    };
    defer {
        project_editor_edit.clearUndoHistory(&state);
        for (state.objects.items) |*obj| obj.deinit(std.testing.allocator);
        state.objects.deinit(std.testing.allocator);
    }

    state.architecture_wall_height = 3;
    try addFloorplanCell(&state);
    try addFloorplanCell(&state);

    try addRoofForFloorplans(&state);

    try std.testing.expectEqual(@as(usize, 3), state.objects.items.len);
    const roof = &state.objects.items[2];
    try std.testing.expectEqualStrings("Roof 3", roof.name);
    try std.testing.expectEqual(@as(?geometry.PrimitiveKind, null), roof.primitive_kind);
    try std.testing.expect(roof.physics == null);
    try std.testing.expectEqual(@as(usize, 14), roof.mesh.vertices.len);
    try std.testing.expectEqual(@as(usize, 18), roof.mesh.indices.len);
    try std.testing.expectApproxEqAbs(@as(f32, 4), roof.position.x, 0.001);
    // addFloorplanCell uses a fixed 4x4 footprint (instead of the old 4x3 drag
    // rectangle), so the combined two-cell footprint is 8x4 and centers at z=2.
    try std.testing.expectApproxEqAbs(@as(f32, 2), roof.position.z, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 3.12), roof.position.y, 0.001);
}

test "player start spawner derives from floorplan and carries fps binding" {
    // addPlayerStartSpawner reads the legacy "Floorplan N" footprint, which
    // only addFloorplanCell produces now (the drag tool builds an
    // arch.Building), so it needs a real project directory to persist into.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = world_authoring_manifest.world_manifest_path,
        .data =
        \\world version=1 id="main" cell_size_m=64 {
        \\  cell coord="0,0,0" authoring="scenes/main.kdl"
        \\}
        \\
        ,
    });
    var project_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const project_path_len = try tmp.dir.realPath(std.testing.io, &project_path_buf);
    const project_path = try std.testing.allocator.dupe(u8, project_path_buf[0..project_path_len]);
    defer std.testing.allocator.free(project_path);

    var state = project_editor_state.ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = project_path,
        .active_world_manifest_path = world_authoring_manifest.world_manifest_path,
        .project_name = "",
        .objects = .empty,
    };
    defer {
        project_editor_edit.clearUndoHistory(&state);
        for (state.objects.items) |*obj| obj.deinit(std.testing.allocator);
        state.objects.deinit(std.testing.allocator);
    }

    try addPlayerStartSpawner(&state);
    try std.testing.expectEqual(@as(usize, 0), state.objects.items.len);
    try std.testing.expectEqualStrings("Draw a floorplan first", state.status_buf[0..state.status_len]);

    state.architecture_floor_thickness = 0.12;
    try addFloorplanCell(&state);

    try addPlayerStartSpawner(&state);

    try std.testing.expectEqual(@as(usize, 2), state.objects.items.len);
    const start = &state.objects.items[1];
    try std.testing.expectEqualStrings("Player Start 2", start.name);
    try std.testing.expectEqual(@as(?geometry.PrimitiveKind, null), start.primitive_kind);
    try std.testing.expectEqual(shared.scene_document.ObjectKind.empty, start.object_kind);
    try std.testing.expect(start.physics == null);
    try std.testing.expect(start.gameplay != null);
    try std.testing.expectEqualStrings("player_start", start.gameplay.?.tag);
    try std.testing.expectEqual(@as(usize, 2), start.components.len);
    try std.testing.expectEqualStrings("spawner", start.components[0]);
    try std.testing.expectEqualStrings("controller:fps", start.components[1]);
    try std.testing.expectEqual(@as(usize, 7), start.mesh.vertices.len);
    try std.testing.expectEqual(@as(usize, 9), start.mesh.indices.len);
    try std.testing.expectApproxEqAbs(@as(f32, 2), start.position.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.16), start.position.y, 0.001);
    // addFloorplanCell's fixed 4x4 footprint (not the old 4x3 drag rectangle)
    // moves the spawn point (80% along the footprint depth) from 2.4 to 3.2.
    try std.testing.expectApproxEqAbs(@as(f32, 3.2), start.position.z, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.02), start.rotation.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), start.rotation.y, 0.001);
}

// Room walls are transient (created with persist=false), so they never carry
// a blockout_intent; recover their world-space footprint from the box mesh's
// local extents plus the object's position instead.
fn roomWallXZBounds(obj: *const SceneObject) ?struct { min_x: f32, max_x: f32, min_z: f32, max_z: f32 } {
    if (obj.mesh.vertices.len == 0) return null;
    var min_x = obj.mesh.vertices[0].position.x;
    var max_x = min_x;
    var min_z = obj.mesh.vertices[0].position.z;
    var max_z = min_z;
    for (obj.mesh.vertices[1..]) |vertex| {
        min_x = @min(min_x, vertex.position.x);
        max_x = @max(max_x, vertex.position.x);
        min_z = @min(min_z, vertex.position.z);
        max_z = @max(max_z, vertex.position.z);
    }
    return .{
        .min_x = obj.position.x + min_x,
        .max_x = obj.position.x + max_x,
        .min_z = obj.position.z + min_z,
        .max_z = obj.position.z + max_z,
    };
}

fn countInternalSharedWalls(objects: []const SceneObject) usize {
    var count: usize = 0;
    for (objects) |obj| {
        if (!std.mem.startsWith(u8, obj.name, "Room Wall")) continue;
        const bounds = roomWallXZBounds(&obj) orelse continue;
        const center_x = (bounds.min_x + bounds.max_x) * 0.5;
        if (@abs(center_x - 4.0) > 0.001) continue;
        if (bounds.min_z > 0.001 and bounds.max_z < 3.999) count += 1;
    }
    return count;
}

test "blockout ramp creates triangular prism object" {
    var state = project_editor_state.ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
    };
    defer {
        for (state.objects.items) |*obj| obj.deinit(std.testing.allocator);
        state.objects.deinit(std.testing.allocator);
    }

    try addBlockoutRampAt(&state, .{ .x = 0, .y = 0, .z = 0 }, 2, 1, 3);

    try std.testing.expectEqual(@as(usize, 1), state.objects.items.len);
    const ramp = &state.objects.items[0];
    try std.testing.expectEqual(@as(?geometry.PrimitiveKind, null), ramp.primitive_kind);
    try std.testing.expectEqual(@as(usize, 18), ramp.mesh.vertices.len);
    try std.testing.expectEqual(@as(usize, 24), ramp.mesh.indices.len);
    try std.testing.expectEqual(@as(?usize, 0), state.selected_object);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), ramp.position.y, 0.001);
}

test "blockout ramp participates in undo redo snapshots" {
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

    try addBlockoutRamp(&state);
    try std.testing.expectEqual(@as(usize, 1), state.objects.items.len);
    project_editor_edit.undo(&state);
    try std.testing.expectEqual(@as(usize, 0), state.objects.items.len);
    project_editor_edit.redo(&state);
    try std.testing.expectEqual(@as(usize, 1), state.objects.items.len);
}

test "blockout brush drag creates cylinder when shape is cylinder" {
    var state = project_editor_state.ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
    };
    defer {
        for (state.objects.items) |*obj| obj.deinit(std.testing.allocator);
        state.objects.deinit(std.testing.allocator);
    }

    state.blockout_brush_shape = .cylinder;
    state.blockout_drag_start = .{ .x = 0, .y = 0, .z = 0 };
    state.blockout_drag_end = .{ .x = 2, .y = 0, .z = 2 };
    state.blockout_brush_size = 2;
    finishBlockoutBrush(&state);

    try std.testing.expectEqual(@as(usize, 1), state.objects.items.len);
    const brush = &state.objects.items[0];
    try std.testing.expectEqual(geometry.PrimitiveKind.cylinder, brush.primitive_kind.?);
}

test "blockout brush drag creates wedge from csg prism" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = world_authoring_manifest.world_manifest_path,
        .data =
        \\world version=1 id="main" cell_size_m=64 {
        \\  cell coord="0,0,0" authoring="scenes/main.kdl"
        \\}
        \\
        ,
    });
    var project_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const project_path_len = try tmp.dir.realPath(std.testing.io, &project_path_buf);
    const project_path = try std.testing.allocator.dupe(u8, project_path_buf[0..project_path_len]);
    defer std.testing.allocator.free(project_path);

    var state = project_editor_state.ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = project_path,
        .active_world_manifest_path = world_authoring_manifest.world_manifest_path,
        .project_name = "",
        .objects = .empty,
    };
    defer {
        for (state.objects.items) |*obj| obj.deinit(std.testing.allocator);
        state.objects.deinit(std.testing.allocator);
    }

    state.blockout_brush_shape = .wedge;
    state.blockout_drag_start = .{ .x = 0, .y = 0, .z = 0 };
    state.blockout_drag_end = .{ .x = 2, .y = 0, .z = 2 };
    state.blockout_brush_size = 1;
    finishBlockoutBrush(&state);

    try std.testing.expectEqual(@as(usize, 1), state.objects.items.len);
    const brush = &state.objects.items[0];
    try std.testing.expectEqual(@as(?geometry.PrimitiveKind, null), brush.primitive_kind);
    try std.testing.expectEqual(@as(usize, 18), brush.mesh.vertices.len);
    try std.testing.expectEqual(@as(usize, 24), brush.mesh.indices.len);
    try std.testing.expectEqual(shared.scene_blockout.Kind.wedge_add, brush.blockout_intent.?.kind);
    const csg_bytes = try tmp.dir.readFileAlloc(std.testing.io, "layers/local_csg.kdl", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(csg_bytes);
    try std.testing.expect(std.mem.indexOf(u8, csg_bytes, "op=\"add_wedge\"") != null);
}

test "blockout wedge subtract persists prism cutter and rebuilds fragments" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = world_authoring_manifest.world_manifest_path,
        .data =
        \\world version=1 id="main" cell_size_m=64 {
        \\  cell coord="0,0,0" authoring="scenes/main.kdl"
        \\}
        \\
        ,
    });
    var project_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const project_path_len = try tmp.dir.realPath(std.testing.io, &project_path_buf);
    const project_path = try std.testing.allocator.dupe(u8, project_path_buf[0..project_path_len]);
    defer std.testing.allocator.free(project_path);

    var state = project_editor_state.ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = project_path,
        .active_world_manifest_path = world_authoring_manifest.world_manifest_path,
        .project_name = "",
        .objects = .empty,
    };
    defer {
        for (state.objects.items) |*obj| obj.deinit(std.testing.allocator);
        state.objects.deinit(std.testing.allocator);
    }

    try addBlockoutBoxInternal(
        &state,
        .{ .x = 0, .y = 0, .z = 0 },
        .{ .x = 2, .y = 2, .z = 2 },
        false,
    );

    state.blockout_op = .subtract;
    state.blockout_brush_shape = .wedge;
    state.blockout_drag_start = .{ .x = 0.5, .y = 0, .z = 0.5 };
    state.blockout_drag_end = .{ .x = 1.5, .y = 0, .z = 1.5 };
    state.blockout_brush_size = 2;
    finishBlockoutBrush(&state);

    try std.testing.expect(state.objects.items.len > 0);
    var found_prism_fragment = false;
    for (state.objects.items) |obj| {
        if (obj.primitive_kind == null and obj.mesh.vertices.len > 0) found_prism_fragment = true;
    }
    try std.testing.expect(found_prism_fragment);
    const csg_bytes = try tmp.dir.readFileAlloc(std.testing.io, "layers/local_csg.kdl", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(csg_bytes);
    try std.testing.expect(std.mem.indexOf(u8, csg_bytes, "op=\"subtract_prism\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, csg_bytes, "footprint=\"") != null);
}

test "raycast scene returns nearest mesh hit" {
    var mesh = try geometry.buildPrimitive(std.testing.allocator, .box, .{ .width = 1, .height = 1, .depth = 1 });
    defer mesh.deinit(std.testing.allocator);
    const obj = SceneObject{
        .id = 1,
        .name = try std.testing.allocator.dupe(u8, "box"),
        .mesh = mesh,
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = &.{},
        .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    };
    defer std.testing.allocator.free(obj.name);
    const objects = [_]SceneObject{obj};
    const hit = raycastScene(
        .{ .x = 0, .y = 0, .z = 5 },
        .{ .x = 0, .y = 0, .z = -1 },
        &objects,
    );
    try std.testing.expect(hit != null);
    try std.testing.expectApproxEqAbs(@as(f32, 4.5), hit.?.t, 0.01);
}

test "ray intersects unit box face" {
    var mesh = try geometry.buildPrimitive(std.testing.allocator, .box, .{ .width = 1, .height = 1, .depth = 1 });
    defer mesh.deinit(std.testing.allocator);
    const obj = SceneObject{
        .id = 1,
        .name = try std.testing.allocator.dupe(u8, "box"),
        .mesh = mesh,
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = &.{},
        .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    };
    defer std.testing.allocator.free(obj.name);
    const hit = raycastMesh(
        .{ .x = 0, .y = 0, .z = 5 },
        .{ .x = 0, .y = 0, .z = -1 },
        &obj,
        obj.transform(),
    );
    try std.testing.expect(hit != null);
}

test "prop edge drag can expand to a loop on one selected prop" {
    var state = project_editor_state.ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .mode = .prop_creation,
        .prop_tool = .edit,
        .edit_tool = .edge,
        .selected_object = 0,
    };
    defer {
        for (state.objects.items) |*obj| obj.deinit(std.testing.allocator);
        state.objects.deinit(std.testing.allocator);
    }

    const mesh = try geometry.buildPrimitive(std.testing.allocator, .box, .{ .width = 1, .height = 1, .depth = 1 });
    try state.objects.append(std.testing.allocator, .{
        .id = 1,
        .name = try std.testing.allocator.dupe(u8, "Prop"),
        .mesh = mesh,
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = &.{},
        .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .primitive_kind = .box,
    });

    const obj = &state.objects.items[0];
    state.selected_edge = .{ obj.mesh.indices[0], obj.mesh.indices[2] };
    const before = try std.testing.allocator.alloc(shared.editor_math.Vec3, obj.mesh.vertices.len);
    defer std.testing.allocator.free(before);
    for (obj.mesh.vertices, 0..) |vertex, vi| before[vi] = vertex.position;

    root.moveSelectedEdge(&state, 10, 0);
    try std.testing.expectEqual(@as(usize, 2), movedVertexCount(obj, before));
    for (obj.mesh.vertices, 0..) |*vertex, vi| vertex.position = before[vi];

    state.prop_loop_mode = true;
    root.moveSelectedEdge(&state, 10, 0);
    try std.testing.expect(movedVertexCount(obj, before) > 2);
    try std.testing.expectEqual(@as(?geometry.PrimitiveKind, null), obj.primitive_kind);
    try std.testing.expect(state.scene_dirty);
}

fn movedVertexCount(obj: *const SceneObject, before: []const shared.editor_math.Vec3) usize {
    var count: usize = 0;
    for (obj.mesh.vertices, 0..) |vertex, vi| {
        if (@abs(vertex.position.x - before[vi].x) > 0.001 or
            @abs(vertex.position.y - before[vi].y) > 0.001 or
            @abs(vertex.position.z - before[vi].z) > 0.001)
        {
            count += 1;
        }
    }
    return count;
}
