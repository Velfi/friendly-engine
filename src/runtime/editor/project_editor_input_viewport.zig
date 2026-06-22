const friendly_engine = @import("friendly_engine");
const std = @import("std");
const shared = @import("runtime_shared");
const editor_draw = @import("editor_draw.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_edit = @import("project_editor_edit.zig");
const project_editor_scene = @import("project_editor_scene.zig");
const project_editor_types = @import("project_editor_types.zig");
const project_editor_view_nav = @import("project_editor_view_nav.zig");
const project_editor_life = @import("project_editor_life.zig");
const project_editor_architecture_curve = @import("project_editor_architecture_curve.zig");
const project_editor_ui_world = @import("project_editor_ui_world.zig");
const viewport_context_menu = @import("project_editor_viewport_context_menu.zig");

const core_ui = friendly_engine.modules.core_ui;
const ProjectEditorState = project_editor_state.ProjectEditorState;

pub fn applyViewportScroll(state: *ProjectEditorState, ui: *core_ui.UiContext) void {
    const scroll_x = ui.input.scroll_delta_x;
    const scroll_y = ui.input.scroll_delta_y;
    if (scroll_x == 0 and scroll_y == 0) return;
    if (core_ui.input_tree.blocksViewportScroll(ui)) return;
    const mouse = ui.input.mouse_position;
    if (!project_editor_scene.pointInViewport(state, mouse.x, mouse.y)) return;

    const ctrl = (ui.input.keyboard_mods & editor_draw.SDL_KMOD_CTRL) != 0 or
        (ui.input.keyboard_mods & editor_draw.SDL_KMOD_GUI) != 0;
    const shift = (ui.input.keyboard_mods & editor_draw.SDL_KMOD_SHIFT) != 0;
    if (ctrl) {
        state.camera.zoom(scroll_y);
    } else if (shift) {
        state.camera.pan(scroll_x * 18.0, -scroll_y * 18.0);
    } else if (ui.input.scroll_is_precise or scroll_x != 0) {
        state.camera.orbit(scroll_x * 24.0, -scroll_y * 24.0);
        state.view_orientation = .free;
    } else {
        state.camera.zoom(scroll_y);
    }
}

pub fn viewportAcceptsPointer(state: *ProjectEditorState, ui: *core_ui.UiContext, x: f32, y: f32) bool {
    if (core_ui.input_tree.blocksPointerAt(ui, .{ .x = x, .y = y })) return false;
    return project_editor_scene.pointInViewport(state, x, y);
}

pub fn applyViewportPointerRelease(state: *ProjectEditorState, ui: *core_ui.UiContext, input: core_ui.InputState) !void {
    const mouse = input.mouse_position;

    if (input.primary_released) {
        if (state.active_view_nav != .none) {
            state.drag_mode = .none;
            state.active_view_nav = .none;
            return;
        }
        if (state.pending_object_drag != .none and state.drag_mode == .none) {
            if (state.mode == .layout and viewportAcceptsPointer(state, ui, mouse.x, mouse.y)) {
                if (state.pending_object_drag == .move_object) {
                    const local_x = mouse.x - state.viewport_screen_rect.x;
                    const local_y = mouse.y - state.viewport_screen_rect.y;
                    project_editor_scene.pickObject(state, local_x, local_y, state.viewport_screen_rect.w, state.viewport_screen_rect.h);
                }
            }
        }
        state.pending_object_drag = .none;
        state.pending_gizmo_axis = null;
        const had_pose_drag = state.drag_moved;
        state.drag_moved = false;
        if (state.drag_mode == .move_object or state.drag_mode == .gizmo_move) {
            if (project_editor_life.transformToolActive(state) and had_pose_drag) {
                project_editor_life.autoKeyframeAfterPoseEdit(state);
            }
            state.drag_mode = .none;
            state.gizmo_drag_axis = null;
        } else if (state.drag_mode == .move_vertex or state.drag_mode == .move_edge or state.drag_mode == .move_face) {
            state.active_gesture.commit();
            state.drag_mode = .none;
        } else if (state.drag_mode == .blockout_brush) {
            project_editor_scene.finishBlockoutBrush(state);
            state.active_gesture.commit();
            state.drag_mode = .none;
            state.blockout_drag_start = null;
            state.blockout_drag_end = null;
        } else if (state.drag_mode == .architecture_curve) {
            project_editor_architecture_curve.finishPlacement(state) catch {
                state.active_gesture.cancel();
                project_editor_state.setStatus(state, "Curve solidify failed");
            };
            if (state.active_gesture.phase != .cancelled) state.active_gesture.commit();
            state.drag_mode = .none;
        } else if (state.drag_mode == .blockout_face_resize) {
            @import("project_editor_blockout_resize.zig").finishFaceResize(state);
            state.active_gesture.commit();
        } else if (state.drag_mode == .world_paint) {
            state.drag_mode = .none;
        } else if (state.drag_mode == .world_scatter_zone) {
            project_editor_ui_world.finishScatterZoneDrag(state);
            state.drag_mode = .none;
        } else if (state.drag_mode == .world_scatter_density) {
            project_editor_ui_world.finishScatterDensityPaint(state);
            state.drag_mode = .none;
        } else if (state.drag_mode == .world_road) {
            project_editor_ui_world.finishRoadDrag(state, had_pose_drag, input.primary_click_count);
            state.drag_mode = .none;
        } else if (state.drag_mode == .world_curve_gizmo) {
            project_editor_ui_world.finishWorldCurveGizmoDrag(state);
            state.drag_mode = .none;
        } else if (state.drag_mode == .selection_box) {
            const had_box_drag = state.selection_box_active or had_pose_drag;
            state.drag_mode = .none;
            state.selection_box_active = false;
            if (had_box_drag) {
                project_editor_scene.dragBoxSelect(state, state.selection_box_start, state.selection_box_end, state.viewport_screen_rect.w, state.viewport_screen_rect.h);
                state.active_gesture.commit();
            } else if (viewportAcceptsPointer(state, ui, mouse.x, mouse.y)) {
                state.active_gesture.cancel();
                pickViewportClick(state, mouse.x, mouse.y);
            }
        } else if (viewportAcceptsPointer(state, ui, mouse.x, mouse.y)) {
            pickViewportClick(state, mouse.x, mouse.y);
        }
    }

    if (input.middle_released or input.right_button_released) {
        if (state.drag_mode == .camera_orbit or state.drag_mode == .camera_pan or state.drag_mode == .camera_zoom) {
            if (input.right_button_released and state.drag_mode == .camera_pan and !state.drag_moved and viewportAcceptsPointer(state, ui, mouse.x, mouse.y)) {
                viewport_context_menu.openAtScreen(state, mouse.x, mouse.y);
            }
            state.drag_mode = .none;
            state.drag_moved = false;
        }
    }

    if (state.drag_mode == .paint_texture and !input.primary_down) {
        state.drag_mode = .none;
    }
    if (state.drag_mode == .world_paint and !input.primary_down) {
        state.drag_mode = .none;
    }
    if (state.drag_mode == .world_scatter_zone and !input.primary_down) {
        project_editor_ui_world.finishScatterZoneDrag(state);
        state.drag_mode = .none;
    }
    if (state.drag_mode == .world_scatter_density and !input.primary_down) {
        project_editor_ui_world.finishScatterDensityPaint(state);
        state.drag_mode = .none;
    }
    if (state.drag_mode == .world_road and !input.primary_down) {
        const had_road_drag = state.drag_moved;
        state.drag_moved = false;
        project_editor_ui_world.finishRoadDrag(state, had_road_drag, 0);
        state.drag_mode = .none;
    }
    if (state.drag_mode == .world_curve_gizmo and !input.primary_down) {
        project_editor_ui_world.finishWorldCurveGizmoDrag(state);
        state.drag_mode = .none;
    }
}

pub fn applyViewportPointerPress(state: *ProjectEditorState, ui: *core_ui.UiContext, input: core_ui.InputState) !void {
    const mouse = input.mouse_position;

    if (input.middle_pressed) {
        const ctrl = (input.keyboard_mods & editor_draw.SDL_KMOD_CTRL) != 0 or
            (input.keyboard_mods & editor_draw.SDL_KMOD_GUI) != 0;
        const shift = (input.keyboard_mods & editor_draw.SDL_KMOD_SHIFT) != 0;
        if (viewportAcceptsPointer(state, ui, mouse.x, mouse.y)) {
            state.drag_mode = if (ctrl) .camera_zoom else if (shift) .camera_pan else .camera_orbit;
            state.drag_last_x = mouse.x;
            state.drag_last_y = mouse.y;
        }
    } else if (input.right_button_pressed) {
        if (viewportAcceptsPointer(state, ui, mouse.x, mouse.y)) {
            state.drag_mode = if (state.walk_mode) .none else .camera_pan;
            state.click_start_x = mouse.x;
            state.click_start_y = mouse.y;
            state.drag_last_x = mouse.x;
            state.drag_last_y = mouse.y;
            state.drag_moved = false;
        }
    } else if (input.primary_pressed) {
        if (viewportAcceptsPointer(state, ui, mouse.x, mouse.y)) {
            switch (project_editor_view_nav.hitTest(state, mouse.x, mouse.y)) {
                .none => {},
                .axis => |orientation| {
                    project_editor_view_nav.applyAxisSnap(state, orientation);
                    return;
                },
                .control => |control| {
                    state.active_view_nav = control;
                    state.drag_mode = switch (control) {
                        .none => .none,
                        .orbit => .camera_orbit,
                        .zoom => .camera_zoom,
                        .pan => .camera_pan,
                    };
                    state.drag_last_x = mouse.x;
                    state.drag_last_y = mouse.y;
                    return;
                },
            }
            switch (state.mode) {
                .layout => if (state.selected_object != null and state.object_tool != .select and !selectedObjectLocked(state)) {
                    const local_x = mouse.x - state.viewport_screen_rect.x;
                    const local_y = mouse.y - state.viewport_screen_rect.y;
                    state.click_start_x = mouse.x;
                    state.click_start_y = mouse.y;
                    if (project_editor_edit.pickGizmoAxis(state, local_x, local_y, state.viewport_screen_rect.w, state.viewport_screen_rect.h)) |axis| {
                        state.pending_object_drag = .gizmo;
                        state.pending_gizmo_axis = axis;
                    } else {
                        state.pending_object_drag = .move_object;
                        state.pending_gizmo_axis = null;
                    }
                    state.drag_moved = false;
                },
                .architecture_creation => switch (state.architecture_tool) {
                    .floorplan, .wall, .door, .window, .brush, .add, .subtract => {
                        project_editor_edit.pushUndoSnapshot(state);
                        state.drag_mode = .blockout_brush;
                        state.drag_last_x = mouse.x;
                        state.drag_last_y = mouse.y;
                        project_editor_scene.beginBlockoutDrag(state, mouse.x, mouse.y);
                    },
                    .curve => {
                        switch (state.architecture_curve_draw_mode) {
                            .freehand => {
                                project_editor_edit.pushUndoSnapshot(state);
                                state.drag_mode = .architecture_curve;
                                state.drag_last_x = mouse.x;
                                state.drag_last_y = mouse.y;
                                project_editor_architecture_curve.beginFreehandDrag(state, mouse.x, mouse.y);
                            },
                            .point_by_point => {
                                project_editor_architecture_curve.addPointAtScreen(state, mouse.x, mouse.y);
                                project_editor_architecture_curve.updatePointPreview(state, mouse.x, mouse.y);
                                if (input.primary_click_count >= 2) {
                                    project_editor_edit.pushUndoSnapshot(state);
                                    project_editor_architecture_curve.finishPlacement(state) catch {
                                        project_editor_state.setStatus(state, "Curve solidify failed");
                                    };
                                }
                                return;
                            },
                        }
                    },
                    .ramp => {},
                    .material => {
                        project_editor_edit.pushUndoSnapshot(state);
                        state.drag_mode = .paint_texture;
                        state.drag_last_x = mouse.x;
                        state.drag_last_y = mouse.y;
                        project_editor_scene.paintAtScreen(state, mouse.x, mouse.y);
                    },
                    else => if (state.selected_vertex != null) {
                        project_editor_edit.pushUndoSnapshot(state);
                        state.drag_mode = .move_vertex;
                        state.drag_last_x = mouse.x;
                        state.drag_last_y = mouse.y;
                        state.drag_moved = false;
                    } else if (state.architecture_tool == .face and state.selected_object != null) {
                        if (@import("project_editor_blockout_resize.zig").beginFaceResize(state, mouse.x, mouse.y)) {
                            project_editor_edit.pushUndoSnapshot(state);
                            state.drag_last_x = mouse.x;
                            state.drag_last_y = mouse.y;
                        }
                    },
                },
                .prop_creation => switch (state.prop_tool) {
                    .material => {
                        project_editor_edit.pushUndoSnapshot(state);
                        state.drag_mode = .paint_texture;
                        state.drag_last_x = mouse.x;
                        state.drag_last_y = mouse.y;
                        project_editor_scene.paintAtScreen(state, mouse.x, mouse.y);
                    },
                    .edit => if (beginPropMeshDrag(state, mouse.x, mouse.y)) return,
                    else => {},
                },
                .life => if (project_editor_life.transformToolActive(state) and state.selected_object != null and !selectedObjectLocked(state)) {
                    const local_x = mouse.x - state.viewport_screen_rect.x;
                    const local_y = mouse.y - state.viewport_screen_rect.y;
                    state.click_start_x = mouse.x;
                    state.click_start_y = mouse.y;
                    if (project_editor_edit.pickGizmoAxis(state, local_x, local_y, state.viewport_screen_rect.w, state.viewport_screen_rect.h)) |axis| {
                        state.pending_object_drag = .gizmo;
                        state.pending_gizmo_axis = axis;
                    } else {
                        state.pending_object_drag = .move_object;
                        state.pending_gizmo_axis = null;
                    }
                    state.drag_moved = false;
                },
                .world_creation => switch (state.world_tool) {
                    .terrain => project_editor_ui_world.selectCellAtScreen(state, mouse.x, mouse.y),
                    .paint => {
                        state.drag_mode = .world_paint;
                        state.drag_last_x = mouse.x;
                        state.drag_last_y = mouse.y;
                        project_editor_ui_world.handleViewportPaintDrag(state, mouse.x, mouse.y);
                    },
                    .measure, .atmosphere => {},
                    .water => {
                        switch (project_editor_ui_world.beginWaterVolumeInteraction(state, mouse.x, mouse.y, input.primary_click_count)) {
                            .none => {},
                            .handled => return,
                            .drag => {
                                state.drag_mode = .world_curve_gizmo;
                                state.click_start_x = mouse.x;
                                state.click_start_y = mouse.y;
                                state.drag_last_x = mouse.x;
                                state.drag_last_y = mouse.y;
                                state.drag_moved = false;
                            },
                        }
                    },
                    .ocean => {
                        switch (project_editor_ui_world.beginOceanClipInteraction(state, mouse.x, mouse.y, input.primary_click_count)) {
                            .none => {},
                            .handled => return,
                            .drag => {
                                state.drag_mode = .world_curve_gizmo;
                                state.click_start_x = mouse.x;
                                state.click_start_y = mouse.y;
                                state.drag_last_x = mouse.x;
                                state.drag_last_y = mouse.y;
                                state.drag_moved = false;
                            },
                        }
                    },
                    .roads => {
                        if (!project_editor_ui_world.roadViewportWantsPointer(state, mouse.x, mouse.y)) return;
                        state.drag_mode = .world_road;
                        state.click_start_x = mouse.x;
                        state.click_start_y = mouse.y;
                        state.drag_last_x = mouse.x;
                        state.drag_last_y = mouse.y;
                        state.drag_moved = false;
                        project_editor_ui_world.beginRoadDrag(state, mouse.x, mouse.y);
                    },
                    .scatter => if (state.selected_world_layer == .scatter_density_mask) {
                        state.drag_mode = .world_scatter_density;
                        state.drag_last_x = mouse.x;
                        state.drag_last_y = mouse.y;
                        project_editor_ui_world.beginScatterDensityPaint(state);
                        project_editor_ui_world.handleViewportScatterDensityDrag(state, mouse.x, mouse.y);
                    } else if (project_editor_ui_world.beginScatterZoneInteraction(state, mouse.x, mouse.y)) {
                        state.drag_mode = .world_curve_gizmo;
                        state.click_start_x = mouse.x;
                        state.click_start_y = mouse.y;
                        state.drag_last_x = mouse.x;
                        state.drag_last_y = mouse.y;
                        state.drag_moved = false;
                    } else {
                        state.drag_mode = .world_scatter_zone;
                        state.drag_last_x = mouse.x;
                        state.drag_last_y = mouse.y;
                        project_editor_ui_world.beginScatterZoneDrag(state, mouse.x, mouse.y);
                    },
                },
            }
            if (state.drag_mode == .none and state.pending_object_drag == .none and selectionBoxWantsPointer(state)) {
                beginSelectionBox(state, mouse.x, mouse.y);
            }
        }
    }
}

pub fn applyViewportPointer(state: *ProjectEditorState, ui: *core_ui.UiContext, input: core_ui.InputState) !void {
    try applyViewportPointerRelease(state, ui, input);
    try applyViewportPointerPress(state, ui, input);
    updateCurvePointPreview(state, ui, input);
}

pub fn updateViewportHover(state: *ProjectEditorState, ui: *core_ui.UiContext, input: core_ui.InputState) void {
    if (input.primary_down or input.middle_down or input.right_button_down or state.drag_mode != .none) {
        project_editor_scene.clearHover(state);
        return;
    }
    const mouse = input.mouse_position;
    if (!viewportAcceptsPointer(state, ui, mouse.x, mouse.y)) {
        project_editor_scene.clearHover(state);
        return;
    }
    project_editor_scene.updateHover(
        state,
        mouse.x - state.viewport_screen_rect.x,
        mouse.y - state.viewport_screen_rect.y,
        state.viewport_screen_rect.w,
        state.viewport_screen_rect.h,
    );
}

fn updateCurvePointPreview(state: *ProjectEditorState, ui: *core_ui.UiContext, input: core_ui.InputState) void {
    if (input.primary_down or input.middle_down or input.right_button_down) return;
    const mouse = input.mouse_position;
    if (!viewportAcceptsPointer(state, ui, mouse.x, mouse.y)) {
        if (state.mode == .world_creation) project_editor_ui_world.clearWorldCurveHover(state);
        return;
    }
    if (state.mode == .world_creation) project_editor_ui_world.updateWorldCurveHover(state, mouse.x, mouse.y);
    if (state.mode == .world_creation and state.world_tool == .roads and state.world_road_draw_mode == .point_by_point and state.world_road_points.items.len > 0) {
        @import("project_editor_ui_world.zig").updateRoadPointPreview(state, mouse.x, mouse.y);
    } else if (state.mode == .architecture_creation and state.architecture_tool == .curve and state.architecture_curve_draw_mode == .point_by_point and state.architecture_curve_points.items.len > 0) {
        project_editor_architecture_curve.updatePointPreview(state, mouse.x, mouse.y);
    }
}

fn pickViewportClick(state: *ProjectEditorState, x: f32, y: f32) void {
    const local_x = x - state.viewport_screen_rect.x;
    const local_y = y - state.viewport_screen_rect.y;
    switch (state.mode) {
        .layout => if (state.pending_object_drag == .none and (state.object_tool == .select or state.selected_object == null)) {
            project_editor_scene.pickObject(state, local_x, local_y, state.viewport_screen_rect.w, state.viewport_screen_rect.h);
        },
        .architecture_creation => switch (state.architecture_tool) {
            .brush, .add, .subtract, .material => {},
            .wall => @import("project_editor_blockout.zig").placeWallOutlinePointAtScreen(state, x, y) catch {
                project_editor_state.setStatus(state, "Wall point failed");
            },
            .ramp => @import("project_editor_ui_architecture.zig").placeRampAtClick(state, x, y),
            else => project_editor_scene.pickMeshHit(state, local_x, local_y, state.viewport_screen_rect.w, state.viewport_screen_rect.h),
        },
        .prop_creation => switch (state.prop_tool) {
            .select => project_editor_scene.pickObject(state, local_x, local_y, state.viewport_screen_rect.w, state.viewport_screen_rect.h),
            .edit => {
                if (@import("project_editor_prop.zig").placeSketchPointAtScreen(state, x, y) catch false) return;
                project_editor_scene.pickMeshHit(state, local_x, local_y, state.viewport_screen_rect.w, state.viewport_screen_rect.h);
            },
            .create, .asset => @import("project_editor_prop.zig").placeAtScreen(state, x, y) catch {
                project_editor_state.setStatus(state, "Prop placement failed");
            },
            .variants => {
                project_editor_scene.pickObject(state, local_x, local_y, state.viewport_screen_rect.w, state.viewport_screen_rect.h);
                @import("project_editor_prop.zig").cycleSelectedVariant(state);
            },
            else => {},
        },
        .life => {
            if (project_editor_life.bonePickActive(state) and
                project_editor_life.pickBoneAtScreen(state, local_x, local_y, state.viewport_screen_rect.w, state.viewport_screen_rect.h))
            {
                return;
            }
            project_editor_scene.pickObject(state, local_x, local_y, state.viewport_screen_rect.w, state.viewport_screen_rect.h);
        },
        .world_creation => if (state.drag_mode == .none) {
            project_editor_ui_world.handleViewportClick(state, x, y);
        },
    }
}

fn selectionBoxWantsPointer(state: *const ProjectEditorState) bool {
    return switch (state.mode) {
        .layout => state.object_tool == .select or state.selected_object == null,
        .prop_creation => state.prop_tool == .select or (state.prop_tool == .edit and meshOrShapeScopeActive(state)),
        .life => !project_editor_life.transformToolActive(state),
        .architecture_creation => meshScopeActive(state) and state.architecture_tool.editTool() != null,
        .world_creation => false,
    };
}

fn meshOrShapeScopeActive(state: *const ProjectEditorState) bool {
    return meshScopeActive(state) or state.selection_scope == .source or state.selection_scope == .operation;
}

fn meshScopeActive(state: *const ProjectEditorState) bool {
    return state.selection_scope == .face or state.selection_scope == .edge or state.selection_scope == .point;
}

fn beginSelectionBox(state: *ProjectEditorState, x: f32, y: f32) void {
    const local = shared.editor_math.Vec2{
        .x = x - state.viewport_screen_rect.x,
        .y = y - state.viewport_screen_rect.y,
    };
    state.drag_mode = .selection_box;
    state.active_gesture.begin(.select_box);
    state.click_start_x = x;
    state.click_start_y = y;
    state.drag_last_x = x;
    state.drag_last_y = y;
    state.drag_moved = false;
    state.selection_box_active = false;
    state.selection_box_start = local;
    state.selection_box_end = local;
}

fn beginPropMeshDrag(state: *ProjectEditorState, x: f32, y: f32) bool {
    if (state.selected_object == null or selectedObjectLocked(state)) return false;
    const drag_mode: project_editor_types.DragMode = if (state.selected_vertex != null)
        .move_vertex
    else if (state.selected_edge != null)
        .move_edge
    else if (state.selected_face != null)
        .move_face
    else
        return false;
    project_editor_edit.pushUndoSnapshot(state);
    state.drag_mode = drag_mode;
    state.active_gesture.begin(.shape_handle);
    state.drag_last_x = x;
    state.drag_last_y = y;
    state.drag_moved = false;
    return true;
}

fn selectedObjectLocked(state: *const ProjectEditorState) bool {
    const idx = state.selected_object orelse return false;
    return !state.objects.items[idx].canModifyObject();
}

test "viewport precise scroll orbits like a laptop trackpad" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .viewport_screen_rect = .{ .x = 0, .y = 0, .w = 200, .h = 120 },
        .view_orientation = .front,
    };

    var ui = core_ui.UiContext.init(std.testing.allocator);
    defer ui.deinit();
    ui.beginFrame(.{
        .mouse_position = .{ .x = 100, .y = 60 },
        .scroll_delta_x = 0.25,
        .scroll_delta_y = -0.5,
        .scroll_is_precise = true,
    });

    const yaw_before = state.camera.yaw;
    const pitch_before = state.camera.pitch;
    const distance_before = state.camera.distance;
    applyViewportScroll(&state, &ui);

    try std.testing.expect(state.camera.yaw != yaw_before);
    try std.testing.expect(state.camera.pitch != pitch_before);
    try std.testing.expectEqual(distance_before, state.camera.distance);
    try std.testing.expectEqual(project_editor_types.ViewOrientation.free, state.view_orientation);
}

test "viewport wheel scroll still zooms" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .viewport_screen_rect = .{ .x = 0, .y = 0, .w = 200, .h = 120 },
    };

    var ui = core_ui.UiContext.init(std.testing.allocator);
    defer ui.deinit();
    ui.beginFrame(.{
        .mouse_position = .{ .x = 100, .y = 60 },
        .scroll_delta_y = 1.0,
    });

    const yaw_before = state.camera.yaw;
    const distance_before = state.camera.distance;
    applyViewportScroll(&state, &ui);

    try std.testing.expectEqual(yaw_before, state.camera.yaw);
    try std.testing.expect(state.camera.distance < distance_before);
}

test "world curve hover clears when pointer leaves viewport" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .mode = .world_creation,
        .world_tool = .water,
        .viewport_screen_rect = .{ .x = 0, .y = 0, .w = 200, .h = 120 },
        .hovered_world_curve_hit = .{ .target = .water_volume, .element = .point, .index = 3 },
    };

    var ui = core_ui.UiContext.init(std.testing.allocator);
    defer ui.deinit();
    ui.beginFrame(.{
        .mouse_position = .{ .x = 260, .y = 60 },
    });

    updateCurvePointPreview(&state, &ui, ui.input);

    try std.testing.expect(state.hovered_world_curve_hit.isNone());
}

test "world road fallback release finishes drag session" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .mode = .world_creation,
        .world_tool = .roads,
        .drag_mode = .world_road,
        .world_road_mode = .shape,
        .world_road_drag_anchor = .{ .x = 1, .y = 0, .z = 2 },
        .world_road_preview_end = .{ .x = 3, .y = 0, .z = 4 },
        .drag_moved = true,
    };

    var ui = core_ui.UiContext.init(std.testing.allocator);
    defer ui.deinit();
    ui.beginFrame(.{ .mouse_position = .{ .x = 50, .y = 40 } });

    try applyViewportPointerRelease(&state, &ui, ui.input);

    try std.testing.expectEqual(project_editor_types.DragMode.none, state.drag_mode);
    try std.testing.expect(state.world_road_drag_anchor == null);
    try std.testing.expect(state.world_road_preview_end == null);
    try std.testing.expect(!state.drag_moved);
}

test "scatter zone fallback release clears drag handles" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .mode = .world_creation,
        .world_tool = .scatter,
        .drag_mode = .world_scatter_zone,
        .world_scatter_drag_start = .{ .x = 1, .y = 0, .z = 2 },
        .world_scatter_drag_end = .{ .x = 1.1, .y = 0, .z = 2.1 },
    };

    var ui = core_ui.UiContext.init(std.testing.allocator);
    defer ui.deinit();
    ui.beginFrame(.{ .mouse_position = .{ .x = 50, .y = 40 } });

    try applyViewportPointerRelease(&state, &ui, ui.input);

    try std.testing.expectEqual(project_editor_types.DragMode.none, state.drag_mode);
    try std.testing.expect(state.world_scatter_drag_start == null);
    try std.testing.expect(state.world_scatter_drag_end == null);
}
