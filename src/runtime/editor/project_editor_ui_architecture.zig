const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const command_ids = shared.editor_command_ids;
const project_editor_blockout = @import("project_editor_blockout.zig");
const project_editor_architecture = @import("project_editor_architecture.zig");
const project_editor_edit = @import("project_editor_edit.zig");
const project_editor_material_apply = @import("project_editor_material_apply.zig");
const project_editor_material_faces = @import("project_editor_material_faces.zig");
const project_editor_surface_faces = @import("project_editor_surface_faces.zig");
const project_editor_materials = @import("project_editor_materials.zig");
const project_editor_physics = @import("project_editor_physics.zig");
const project_editor_scene = @import("project_editor_scene.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_texture_paint = @import("project_editor_texture_paint.zig");
const project_editor_types = @import("project_editor_types.zig");
const architecture_curve = @import("project_editor_architecture_curve.zig");
const ui_widgets = @import("project_editor_ui_widgets.zig");
const project_editor_mode_config = @import("project_editor_mode_config.zig");

const core_ui = friendly_engine.modules.core_ui;
const ProjectEditorState = project_editor_state.ProjectEditorState;
const ArchitectureTool = project_editor_types.ArchitectureTool;
const BlockoutBrushShape = project_editor_types.BlockoutBrushShape;
const SceneObject = @import("editor_scene_object.zig").SceneObject;

pub fn registerEditor(registry: *project_editor_mode_config.EditorRegistry) !void {
    try registry.registerMode(project_editor_mode_config.descForMode(.architecture_creation).*);
}

pub fn selectTool(state: *ProjectEditorState, tool: ArchitectureTool) void {
    if (state.architecture_tool == .wall and tool != .wall) {
        project_editor_blockout.clearWallOutline(state);
    }
    if (state.architecture_tool == .curve and tool != .curve) {
        architecture_curve.clearDraft(state);
    }
    state.architecture_tool = tool;
    switch (tool) {
        .add => state.blockout_op = .add,
        .subtract => state.blockout_op = .subtract,
        .vertex, .edge, .face, .extrude, .inset => {
            if (tool.editTool()) |edit_tool| state.edit_tool = edit_tool;
            state.selected_vertex = null;
            state.selected_edge = null;
            state.selected_face = null;
        },
        else => {},
    }
    project_editor_state.setStatus(state, toolStatus(tool));
}

fn toolStatus(tool: ArchitectureTool) []const u8 {
    return switch (tool) {
        .floorplan => "Floor tool: drag to draw a slab",
        .wall => "Wall tool: click points to draw an outline",
        .door => "Door tool: drag across a wall to cut an opening",
        .window => "Window tool: drag across a wall to cut a window",
        .curve => "Curve tool: drag on surfaces to solidify rope or pipe",
        .brush => "Brush tool: drag to shape blockout",
        .add => "Add tool: drag to add geometry",
        .subtract => "Subtract tool: drag to cut geometry",
        .ramp => "Ramp tool: click viewport to place ramp",
        .material => "Material tool: paint or assign materials",
        else => tool.label(),
    };
}

pub fn buildToolbar(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    try toolbarGroupTab(ui, state, "ed-arch-group-draw", "Draw", .wall, activeArchitectureGroup(state) == .draw);
    try toolbarGroupTab(ui, state, "ed-arch-group-shape", "Shape", .brush, activeArchitectureGroup(state) == .shape);
    try toolbarGroupTab(ui, state, "ed-arch-group-edit", "Edit", .face, activeArchitectureGroup(state) == .edit);
    try toolbarGroupTab(ui, state, "ed-arch-group-paint", "Paint", .material, activeArchitectureGroup(state) == .paint);
    try core_ui.layout.endSameLine(ui);
    try core_ui.layout.sameLine(ui);
    switch (activeArchitectureGroup(state)) {
        .draw => try buildToolbarGroup(ui, state, &architecture_draw_tools),
        .shape => try buildToolbarGroup(ui, state, &architecture_shape_tools),
        .edit => try buildToolbarGroup(ui, state, &architecture_edit_tools),
        .paint => try buildToolbarGroup(ui, state, &architecture_paint_tools),
    }
}

const architecture_draw_tools = [_]ArchitectureTool{ .network, .shell, .foundation, .cutout, .wall, .opening, .roof, .door, .window, .curve };
const architecture_shape_tools = [_]ArchitectureTool{ .brush, .add, .subtract, .ramp };
const architecture_edit_tools = [_]ArchitectureTool{ .vertex, .edge, .face, .extrude, .inset };
const architecture_paint_tools = [_]ArchitectureTool{ .material };

const ArchitectureToolGroup = enum { draw, shape, edit, paint };

fn activeArchitectureGroup(state: *const ProjectEditorState) ArchitectureToolGroup {
    const tool = state.architecture_tool;
    if (groupHasTool(architecture_shape_tools, tool)) return .shape;
    if (groupHasTool(architecture_edit_tools, tool)) return .edit;
    if (groupHasTool(architecture_paint_tools, tool)) return .paint;
    return .draw;
}

fn toolbarGroupTab(ui: *core_ui.UiContext, state: *ProjectEditorState, id: []const u8, label: []const u8, default_tool: ArchitectureTool, active: bool) !void {
    if ((try ui_widgets.button(ui, id, label, groupLabelWidth(label), active)).clicked) {
        selectTool(state, default_tool);
    }
}

fn groupLabelWidth(label: []const u8) f32 {
    return @max(44.0, 22.0 + @as(f32, @floatFromInt(label.len)) * 7.0);
}

fn buildToolbarGroup(ui: *core_ui.UiContext, state: *ProjectEditorState, comptime tools: []const ArchitectureTool) !void {
    inline for (tools) |tool| {
        if ((try ui_widgets.button(ui, command_ids.architectureTool(@tagName(tool)), toolbarLabel(tool), toolbarWidth(tool), state.architecture_tool == tool)).clicked) {
            selectTool(state, tool);
        }
    }
}

pub fn buildSecondaryStrip(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    if (state.architecture_tool == .floorplan or state.architecture_tool == .wall or state.architecture_tool == .door or state.architecture_tool == .window or state.architecture_tool == .curve) {
        try buildArchitecturePrimitiveStrip(ui, state);
        return;
    }
    if (state.architecture_tool == .network or state.architecture_tool == .shell or state.architecture_tool == .foundation or state.architecture_tool == .cutout or state.architecture_tool == .opening or state.architecture_tool == .roof) {
        try ui.label(state.architecture_tool.label());
        return;
    }
    if (state.architecture_tool == .material) {
        try ui_widgets.buildMaterialButtons(ui, state);
        return;
    }
    if (state.architecture_tool == .ramp) {
        try ui.label("Ramp");
        return;
    }
    if (state.architecture_tool != .brush and state.architecture_tool != .add and state.architecture_tool != .subtract) return;
    try ui.label("Shape");
    const shapes = [_]BlockoutBrushShape{ .box, .wedge, .ramp, .cylinder };
    inline for (shapes) |shape| {
        if ((try ui_widgets.button(ui, std.fmt.comptimePrint("ed-brush-shape-{s}", .{@tagName(shape)}), shape.label(), 52, state.blockout_brush_shape == shape)).clicked) {
            state.blockout_brush_shape = shape;
            project_editor_state.setStatus(state, switch (shape) {
                .box => "Brush shape: box",
                .wedge => "Brush shape: wedge",
                .ramp => "Brush shape: ramp",
                .cylinder => "Brush shape: cylinder",
            });
        }
    }
    const csg_label = if (state.blockout_op == .add) "CSG Add" else "CSG Sub";
    if ((try ui_widgets.button(ui, "ed-arch-csg-mode", csg_label, 72, true)).clicked) {
        state.blockout_op = if (state.blockout_op == .add) .subtract else .add;
        if (state.architecture_tool == .add or state.architecture_tool == .subtract) {
            state.architecture_tool = if (state.blockout_op == .add) .add else .subtract;
        }
        project_editor_state.setStatus(state, if (state.blockout_op == .add) "CSG additive" else "CSG subtractive");
    }
    if ((try ui_widgets.iconButtonTip(ui, "ed-arch-grid", "grid", state.show_grid, "Grid")).clicked) state.show_grid = !state.show_grid;
    if ((try ui_widgets.button(ui, "ed-arch-csg-preview", if (state.csg_preview_live) "Preview" else "Preview Off", 86, state.csg_preview_live)).clicked) {
        state.csg_preview_live = !state.csg_preview_live;
    }
    const snap_face = try core_ui.widgets_input.checkbox(ui, "Snap Face", "ed-arch-snap-face");
    state.snap_face = snap_face.checked;
}

pub fn buildToolInspector(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    try ui.label("Architecture Tool");
    const tools = [_]ArchitectureTool{ .network, .shell, .foundation, .cutout, .wall, .opening, .roof, .door, .window, .curve, .brush, .add, .subtract, .ramp, .material };
    inline for (tools) |tool| {
        if ((try ui_widgets.button(ui, command_ids.architectureTool(@tagName(tool)), toolbarLabel(tool), toolbarWidth(tool), state.architecture_tool == tool)).clicked) {
            selectTool(state, tool);
        }
    }

    if (state.architecture_tool == .floorplan or state.architecture_tool == .wall or state.architecture_tool == .door or state.architecture_tool == .window or state.architecture_tool == .curve) {
        try buildArchitecturePrimitiveInspector(ui, state);
        return;
    }
    if (state.architecture_tool == .network or state.architecture_tool == .shell or state.architecture_tool == .foundation or state.architecture_tool == .cutout or state.architecture_tool == .opening or state.architecture_tool == .roof) {
        try ui_widgets.compactInfo(ui, state.architecture_tool.label());
        return;
    }
    if (state.architecture_tool == .material) {
        try project_editor_texture_paint.buildToolControls(ui, state, "ed-left-arch-texture-paint");
        return;
    }
    if (state.architecture_tool == .ramp) {
        try ui_widgets.compactInfo(ui, "Click the viewport to place a ramp");
        return;
    }
    if (state.architecture_tool != .brush and state.architecture_tool != .add and state.architecture_tool != .subtract) {
        try ui_widgets.compactInfo(ui, state.architecture_tool.label());
        return;
    }

    try ui.label("Brush Config");
    try core_ui.layout.sameLine(ui);
    const shapes = [_]BlockoutBrushShape{ .box, .wedge, .ramp, .cylinder };
    inline for (shapes) |shape| {
        if ((try ui_widgets.button(ui, std.fmt.comptimePrint("ed-left-brush-shape-{s}", .{@tagName(shape)}), shape.label(), 54, state.blockout_brush_shape == shape)).clicked) {
            state.blockout_brush_shape = shape;
        }
    }
    const csg_label = if (state.blockout_op == .add) "Add" else "Subtract";
    if ((try ui_widgets.button(ui, "ed-left-arch-csg-mode", csg_label, 78, true)).clicked) {
        state.blockout_op = if (state.blockout_op == .add) .subtract else .add;
        if (state.architecture_tool == .add or state.architecture_tool == .subtract) {
            state.architecture_tool = if (state.blockout_op == .add) .add else .subtract;
        }
    }
    try core_ui.layout.endSameLine(ui);

    var brush_buf: [96]u8 = undefined;
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&brush_buf, "Size {d:.1}  {s}", .{
        state.blockout_brush_size,
        state.blockout_brush_shape.label(),
    }) catch "Brush");
    if ((try ui_widgets.syncedCheckbox(ui, "Live CSG Preview", "ed-left-arch-csg-preview", state.csg_preview_live)).clicked) {
        state.csg_preview_live = !state.csg_preview_live;
    }
    const snap_face = try core_ui.widgets_input.checkbox(ui, "Snap Face", "ed-left-arch-snap-face");
    state.snap_face = snap_face.checked;
}

fn toolbarLabel(tool: ArchitectureTool) []const u8 {
    return switch (tool) {
        .network => "Net",
        .foundation => "Found",
        .cutout => "Cutout",
        .opening => "Open",
        .vertex => "Point",
        .extrude => "Extr",
        .window => "Win",
        .curve => "Curve",
        .subtract => "Cut",
        .material => "Mat",
        else => tool.label(),
    };
}

fn toolbarWidth(tool: ArchitectureTool) f32 {
    return switch (tool) {
        .floorplan => 54,
        .network, .wall, .door, .window, .add, .ramp => 48,
        .foundation, .opening, .vertex, .extrude => 56,
        .cutout => 60,
        .curve => 58,
        .brush => 56,
        .subtract => 44,
        .material => 42,
        else => 54,
    };
}

test "architecture viewport toolbar exposes grouped editing loop" {
    try std.testing.expect(groupHasTool(architecture_draw_tools, .wall));
    try std.testing.expect(groupHasTool(architecture_draw_tools, .curve));
    try std.testing.expect(groupHasTool(architecture_shape_tools, .brush));
    try std.testing.expect(groupHasTool(architecture_shape_tools, .subtract));
    try std.testing.expect(groupHasTool(architecture_edit_tools, .vertex));
    try std.testing.expect(groupHasTool(architecture_edit_tools, .edge));
    try std.testing.expect(groupHasTool(architecture_edit_tools, .face));
    try std.testing.expect(groupHasTool(architecture_edit_tools, .extrude));
    try std.testing.expect(groupHasTool(architecture_edit_tools, .inset));
    try std.testing.expect(groupHasTool(architecture_paint_tools, .material));
}

test "architecture active toolbar group follows selected tool" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
    };
    state.architecture_tool = .wall;
    try std.testing.expectEqual(ArchitectureToolGroup.draw, activeArchitectureGroup(&state));
    state.architecture_tool = .brush;
    try std.testing.expectEqual(ArchitectureToolGroup.shape, activeArchitectureGroup(&state));
    state.architecture_tool = .face;
    try std.testing.expectEqual(ArchitectureToolGroup.edit, activeArchitectureGroup(&state));
    state.architecture_tool = .material;
    try std.testing.expectEqual(ArchitectureToolGroup.paint, activeArchitectureGroup(&state));
}

fn groupHasTool(comptime tools: anytype, target: ArchitectureTool) bool {
    inline for (tools) |tool| {
        if (tool == target) return true;
    }
    return false;
}

fn buildArchitecturePrimitiveStrip(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    var buf: [96]u8 = undefined;
    switch (state.architecture_tool) {
        .floorplan => {
            try ui.label(std.fmt.bufPrint(&buf, "Floor  Thick {d:.2}", .{state.architecture_floor_thickness}) catch "Floor");
        },
        .wall => {
            try ui.label(std.fmt.bufPrint(&buf, "Wall  H {d:.2}  T {d:.2}", .{ state.architecture_wall_height, state.architecture_wall_thickness }) catch "Wall");
        },
        .door => {
            try ui.label(std.fmt.bufPrint(&buf, "Door  H {d:.2}", .{state.architecture_door_height}) catch "Door");
        },
        .window => {
            try ui.label(std.fmt.bufPrint(&buf, "Window  Sill {d:.2}  H {d:.2}", .{ state.architecture_window_sill, state.architecture_window_height }) catch "Window");
        },
        .curve => {
            try ui.label(std.fmt.bufPrint(&buf, "Curve  R {d:.2}  Lift {d:.2}", .{ state.architecture_curve_radius, state.architecture_curve_surface_offset }) catch "Curve");
        },
        else => {},
    }
    if ((try ui_widgets.iconButtonTip(ui, "ed-arch-grid", "grid", state.show_grid, "Grid")).clicked) state.show_grid = !state.show_grid;
}

fn buildArchitecturePrimitiveInspector(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    try ui.label("Draw Config");
    switch (state.architecture_tool) {
        .floorplan => try stepValue(ui, "ed-left-arch-floor-thick", "Thick", &state.architecture_floor_thickness, 0.04, 0.5, 0.04),
        .wall => {
            try stepValue(ui, "ed-left-arch-wall-height", "H", &state.architecture_wall_height, 0.5, 8.0, 0.25);
            try stepValue(ui, "ed-left-arch-wall-thick", "T", &state.architecture_wall_thickness, 0.05, 1.0, 0.05);
            if ((try ui_widgets.button(ui, "ed-left-arch-apply-wall-defaults", "Apply Selected", 122, false)).clicked) {
                try project_editor_blockout.applyArchitectureWallDefaultsToSelected(state);
            }
            try core_ui.layout.sameLine(ui);
            if ((try ui_widgets.button(ui, "ed-left-arch-split-wall", "Split", 58, false)).clicked) {
                try project_editor_blockout.splitLongestArchitectureWallSelected(state);
            }
            if ((try ui_widgets.button(ui, "ed-left-arch-delete-wall", "Delete", 68, false)).clicked) {
                try project_editor_blockout.deleteLastArchitectureWallSelected(state);
            }
            try core_ui.layout.endSameLine(ui);
        },
        .door => try stepValue(ui, "ed-left-arch-door-height", "H", &state.architecture_door_height, 0.5, 4.0, 0.1),
        .window => {
            try stepValue(ui, "ed-left-arch-window-sill", "Sill", &state.architecture_window_sill, 0.0, 3.0, 0.1);
            try stepValue(ui, "ed-left-arch-window-height", "H", &state.architecture_window_height, 0.25, 3.0, 0.1);
        },
        .curve => {
            try stepValue(ui, "ed-left-arch-curve-radius", "Radius", &state.architecture_curve_radius, 0.02, 0.5, 0.02);
            try stepValue(ui, "ed-left-arch-curve-offset", "Lift", &state.architecture_curve_surface_offset, 0.0, 0.3, 0.01);
            try core_ui.layout.sameLine(ui);
            if ((try ui_widgets.button(ui, "ed-left-arch-curve-freehand", "Freehand", 84, state.architecture_curve_draw_mode == .freehand)).clicked) {
                state.architecture_curve_draw_mode = .freehand;
                architecture_curve.clearDraft(state);
            }
            if ((try ui_widgets.button(ui, "ed-left-arch-curve-point", "Point", 58, state.architecture_curve_draw_mode == .point_by_point)).clicked) {
                state.architecture_curve_draw_mode = .point_by_point;
                architecture_curve.clearDraft(state);
            }
            try core_ui.layout.endSameLine(ui);
            try core_ui.layout.sameLine(ui);
            if ((try ui_widgets.button(ui, "ed-left-arch-finish-curve", "Finish", 68, false)).clicked) {
                project_editor_edit.pushUndoSnapshot(state);
                architecture_curve.finishPlacement(state) catch {
                    project_editor_state.setStatus(state, "Curve solidify failed");
                };
            }
            if ((try ui_widgets.button(ui, "ed-left-arch-clear-curve", "Clear Draft", 112, false)).clicked) {
                architecture_curve.clearDraft(state);
            }
            try core_ui.layout.endSameLine(ui);
        },
        else => {},
    }
    try ui_widgets.compactInfo(ui, switch (state.architecture_tool) {
        .floorplan => "Drag a room or building footprint",
        .wall => "Click points. Click the first point to close.",
        .door => "Drag opening width across a wall",
        .window => "Drag opening width across a wall",
        .curve => if (state.architecture_curve_draw_mode == .freehand) "Drag on surfaces to create a solid rope or pipe" else "Click surface points. Finish or double-click to solidify.",
        else => "Architecture",
    });
    if (state.architecture_tool == .floorplan) {
        if ((try ui_widgets.button(ui, command_ids.architecture_floor_cell, "Floor Cell", 104, false)).clicked) {
            try project_editor_blockout.addFloorplanCell(state);
        }
        if ((try ui_widgets.button(ui, command_ids.architecture_extrude_room, "Extrude Room", 118, false)).clicked) {
            try project_editor_blockout.extrudeSelectedFloorplanToRoom(state);
        }
        if ((try ui_widgets.button(ui, command_ids.architecture_add_roof, "Add Roof", 92, false)).clicked) {
            try project_editor_blockout.addRoofForFloorplans(state);
        }
        if ((try ui_widgets.button(ui, command_ids.architecture_player_start, "Player Start", 118, false)).clicked) {
            try project_editor_blockout.addPlayerStartSpawner(state);
        }
        try core_ui.layout.sameLine(ui);
        if ((try ui_widgets.button(ui, "ed-architecture-roof-flat", "Flat", 54, false)).clicked) {
            try project_editor_blockout.setArchitectureRoofSelected(state, .flat);
        }
        if ((try ui_widgets.button(ui, "ed-architecture-roof-shed", "Shed", 58, false)).clicked) {
            try project_editor_blockout.setArchitectureRoofSelected(state, .shed);
        }
        if ((try ui_widgets.button(ui, "ed-architecture-roof-gable", "Gable", 66, false)).clicked) {
            try project_editor_blockout.setArchitectureRoofSelected(state, .gable);
        }
        if ((try ui_widgets.button(ui, "ed-architecture-roof-conical", "Conical", 78, false)).clicked) {
            try project_editor_blockout.setArchitectureRoofSelected(state, .conical);
        }
        try core_ui.layout.endSameLine(ui);
        try core_ui.layout.sameLine(ui);
        if ((try ui_widgets.button(ui, "ed-architecture-add-column", "Column", 74, false)).clicked) {
            try project_editor_blockout.addArchitectureFeatureToSelected(state, .column);
        }
        if ((try ui_widgets.button(ui, "ed-architecture-add-beam", "Beam", 60, false)).clicked) {
            try project_editor_blockout.addArchitectureFeatureToSelected(state, .beam);
        }
        if ((try ui_widgets.button(ui, "ed-architecture-add-stair", "Stair", 58, false)).clicked) {
            try project_editor_blockout.addArchitectureFeatureToSelected(state, .stair);
        }
        if ((try ui_widgets.button(ui, "ed-architecture-add-arch", "Arch", 56, false)).clicked) {
            try project_editor_blockout.addArchitectureFeatureToSelected(state, .arch);
        }
        try core_ui.layout.endSameLine(ui);
    }
}

fn stepValue(
    ui: *core_ui.UiContext,
    comptime id: []const u8,
    label: []const u8,
    value: *f32,
    min_value: f32,
    max_value: f32,
    step: f32,
) !void {
    var minus_id: [96]u8 = undefined;
    var label_id: [96]u8 = undefined;
    var plus_id: [96]u8 = undefined;
    try core_ui.layout.sameLine(ui);
    if ((try ui_widgets.button(ui, std.fmt.bufPrint(&minus_id, "{s}-minus", .{id}) catch id, "-", 24, false)).clicked) value.* = @max(min_value, value.* - step);
    var buf: [48]u8 = undefined;
    _ = try ui_widgets.button(ui, std.fmt.bufPrint(&label_id, "{s}-label", .{id}) catch id, std.fmt.bufPrint(&buf, "{s} {d:.2}", .{ label, value.* }) catch label, 82, false);
    if ((try ui_widgets.button(ui, std.fmt.bufPrint(&plus_id, "{s}-plus", .{id}) catch id, "+", 24, false)).clicked) value.* = @min(max_value, value.* + step);
    try core_ui.layout.endSameLine(ui);
}

pub fn buildArchitectureTree(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    try ui.label("Architecture");
    _ = try ui_widgets.treeRow(ui, "Buildings", &state.show_arch_buildings);
    if (state.show_arch_buildings) {
        try buildBuildingRows(ui, state);
    }
    _ = try ui_widgets.treeRow(ui, "Blockout", &state.show_arch_blockout);
    if (state.show_arch_blockout) {
        for (state.objects.items, 0..) |obj, idx| {
            if (!isBlockoutEntry(&obj)) continue;
            try architectureObjectRow(ui, state, idx, &obj);
        }
    }
    _ = try ui_widgets.treeRow(ui, "Brushes", &state.show_arch_brushes);
    if (state.show_arch_brushes) {
        for (state.objects.items, 0..) |obj, idx| {
            if (!isBrushEntry(&obj)) continue;
            try brushObjectRow(ui, state, idx, &obj);
        }
    }
    _ = try ui_widgets.treeRow(ui, "Materials", &state.show_arch_materials);
    if (state.show_arch_materials) {
        try buildMaterialRows(ui, state);
    }
    _ = try ui_widgets.treeRow(ui, "Collision", &state.show_arch_collision);
    if (state.show_arch_collision) {
        try buildCollisionRows(ui, state);
    }
}

fn buildBuildingRows(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    const active_idx = project_editor_architecture.activeBuildingIndex(state);
    var found = false;
    for (state.objects.items, 0..) |obj, idx| {
        if (!project_editor_architecture.isArchitectureBuildingObject(&obj)) continue;
        found = true;
        const is_active = if (active_idx) |ai| ai == idx else false;
        const children = project_editor_architecture.buildingChildCount(state, obj.id);
        var label_buf: [176]u8 = undefined;
        const label = std.fmt.bufPrint(&label_buf, "{s}{s}  ({d} props)", .{
            if (is_active) "* " else "  ",
            obj.name,
            children,
        }) catch obj.name;
        var id_buf: [64]u8 = undefined;
        const row_id = std.fmt.bufPrint(&id_buf, "arch-building-{d}", .{obj.id}) catch obj.name;
        if ((try ui_widgets.row(ui, row_id, label, state.selected_object == idx or is_active)).clicked) {
            state.selected_object = idx;
            state.selected_vertex = null;
            state.selected_edge = null;
            state.selected_face = null;
            project_editor_architecture.setActiveBuilding(state, obj.id);
            project_editor_state.setStatus(state, "Active building set");
        }
    }
    if (!found) {
        _ = try ui_widgets.row(ui, "arch-building-none", "  none yet — draw a floor or wall", false);
    }
    if ((try ui_widgets.button(ui, command_ids.architecture_new_building, "New Building", 118, false)).clicked) {
        project_editor_architecture.startNewBuilding(state);
    }
}

fn isBlockoutEntry(obj: *const SceneObject) bool {
    if (obj.blockout_intent) |intent| {
        return switch (intent.kind) {
            .ramp, .stair, .subtract_block, .subtract_prism, .doorway_subtract => true,
            .box_add, .wedge_add => false,
        };
    }
    return std.mem.startsWith(u8, obj.name, "Ramp") or
        std.mem.startsWith(u8, obj.name, "Stair") or
        std.mem.startsWith(u8, obj.name, "Door");
}

fn isBrushEntry(obj: *const SceneObject) bool {
    if (obj.blockout_intent) |intent| return intent.kind == .box_add;
    if (obj.primitive_kind == .cylinder) return true;
    return std.mem.startsWith(u8, obj.name, "Brush");
}

fn architectureObjectRow(ui: *core_ui.UiContext, state: *ProjectEditorState, idx: usize, obj: *const SceneObject) !void {
    var label_buf: [128]u8 = undefined;
    const label = std.fmt.bufPrint(&label_buf, "  {s}", .{obj.name}) catch obj.name;
    if ((try ui_widgets.row(ui, obj.name, label, state.selected_object == idx)).clicked) {
        state.selected_object = idx;
        state.selected_vertex = null;
        state.selected_edge = null;
        state.selected_face = null;
    }
}

fn brushObjectRow(ui: *core_ui.UiContext, state: *ProjectEditorState, idx: usize, obj: *const SceneObject) !void {
    var label_buf: [160]u8 = undefined;
    const op = if (obj.blockout_intent) |intent| switch (intent.kind) {
        .box_add => "additive",
        .wedge_add => "wedge",
        .subtract_block => "csg cut",
        .subtract_prism => "prism cut",
        .doorway_subtract => "subtract",
        else => "brush",
    } else "brush";
    const label = std.fmt.bufPrint(&label_buf, "  {s} {s}", .{ obj.name, op }) catch obj.name;
    var id_buf: [64]u8 = undefined;
    const row_id = std.fmt.bufPrint(&id_buf, "arch-brush-{d}", .{obj.id}) catch obj.name;
    if ((try ui_widgets.row(ui, row_id, label, state.selected_object == idx)).clicked) {
        state.selected_object = idx;
        state.selected_vertex = null;
        state.selected_edge = null;
        state.selected_face = null;
    }
}

fn buildMaterialRows(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    const catalog_len = project_editor_materials.catalog.len;
    var seen: [catalog_len + 8]bool = std.mem.zeroes([catalog_len + 8]bool);
    var custom_count: usize = 0;
    for (state.objects.items) |obj| {
        if (obj.material_path) |path| {
            try appendMaterialRow(ui, path, &seen, &custom_count);
        }
        for (obj.face_materials) |face| {
            try appendMaterialRow(ui, face.material_path, &seen, &custom_count);
        }
    }
    if (custom_count == 0 and !seen[0]) {
        for (project_editor_materials.catalog[0..2]) |material| {
            var label_buf: [128]u8 = undefined;
            const basename = std.fs.path.basename(material.path);
            const label = std.fmt.bufPrint(&label_buf, "  {s}", .{basename}) catch material.label;
            var id_buf: [64]u8 = undefined;
            const row_id = std.fmt.bufPrint(&id_buf, "arch-mat-{s}", .{material.label}) catch material.path;
            _ = try ui_widgets.row(ui, row_id, label, false);
        }
    }
}

fn appendMaterialRow(ui: *core_ui.UiContext, path: []const u8, seen: []bool, custom_count: *usize) !void {
    for (project_editor_materials.catalog, 0..) |material, material_idx| {
        if (std.mem.eql(u8, path, material.path)) {
            if (seen[material_idx]) return;
            seen[material_idx] = true;
            var label_buf: [128]u8 = undefined;
            const basename = std.fs.path.basename(material.path);
            const label = std.fmt.bufPrint(&label_buf, "  {s}", .{basename}) catch material.label;
            var id_buf: [64]u8 = undefined;
            const row_id = std.fmt.bufPrint(&id_buf, "arch-mat-{s}", .{material.label}) catch material.path;
            _ = try ui_widgets.row(ui, row_id, label, false);
            return;
        }
    }
    if (custom_count.* >= seen.len - project_editor_materials.catalog.len) return;
    const slot = project_editor_materials.catalog.len + custom_count.*;
    if (seen[slot]) return;
    seen[slot] = true;
    custom_count.* += 1;
    var label_buf: [128]u8 = undefined;
    const basename = std.fs.path.basename(path);
    const label = std.fmt.bufPrint(&label_buf, "  {s}", .{basename}) catch path;
    var id_buf: [64]u8 = undefined;
    const row_id = std.fmt.bufPrint(&id_buf, "arch-mat-custom-{d}", .{custom_count.*}) catch path;
    _ = try ui_widgets.row(ui, row_id, label, false);
}

fn buildCollisionRows(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    var auto_count: usize = 0;
    for (state.objects.items) |obj| {
        if (obj.physics != null) {
            var label_buf: [128]u8 = undefined;
            const label = std.fmt.bufPrint(&label_buf, "  {s}  {s}", .{ obj.name, obj.physics.?.collider.label() }) catch obj.name;
            var id_buf: [64]u8 = undefined;
            const row_id = std.fmt.bufPrint(&id_buf, "arch-collider-{d}", .{obj.id}) catch obj.name;
            _ = try ui_widgets.row(ui, row_id, label, false);
        } else if (obj.blockout_intent != null or obj.primitive_kind != null) {
            auto_count += 1;
        }
    }
    if (auto_count > 0) {
        var label_buf: [96]u8 = undefined;
        const label = std.fmt.bufPrint(&label_buf, "  auto_generated ({d})", .{auto_count}) catch "auto_generated";
        _ = try ui_widgets.row(ui, "arch-collider-auto", label, false);
    } else {
        _ = try ui_widgets.row(ui, "arch-collider-auto", "  auto_generated", false);
    }
}

pub fn buildInspectorSections(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    if (state.selected_object) |idx| {
        const obj = &state.objects.items[idx];
        if (project_editor_architecture.isArchitectureBuildingObject(obj)) {
            try buildBuildingHeaderSection(ui, state, idx, obj);
            if ((try ui_widgets.collapsible(ui, "Architecture", true))) {
                try buildFaceBrushInspector(ui, state, obj);
            }
            return;
        }
        try buildAttachSection(ui, state, obj);
        return;
    }
    if (state.architecture_tool.isBlockoutDrawTool()) {
        if ((try ui_widgets.collapsible(ui, "Brush", true))) {
            var buf: [128]u8 = undefined;
            const text = switch (state.architecture_tool) {
                .floorplan => std.fmt.bufPrint(&buf, "Floor thickness {d:.2}", .{state.architecture_floor_thickness}) catch "Floor",
                .wall => std.fmt.bufPrint(&buf, "Wall height {d:.2}  thickness {d:.2}", .{ state.architecture_wall_height, state.architecture_wall_thickness }) catch "Wall",
                .door => std.fmt.bufPrint(&buf, "Door height {d:.2}", .{state.architecture_door_height}) catch "Door",
                .window => std.fmt.bufPrint(&buf, "Window sill {d:.2}  height {d:.2}", .{ state.architecture_window_sill, state.architecture_window_height }) catch "Window",
                .curve => std.fmt.bufPrint(&buf, "Curve radius {d:.2}  lift {d:.2}", .{ state.architecture_curve_radius, state.architecture_curve_surface_offset }) catch "Curve",
                else => std.fmt.bufPrint(&buf, "Size {d:.1}  {s}  {s}", .{
                    state.blockout_brush_size,
                    state.blockout_op.label(),
                    state.blockout_brush_shape.label(),
                }) catch "Brush",
            };
            try core_ui.widgets_feedback.statusLabel(ui, text);
        }
    }
}

fn buildBuildingHeaderSection(ui: *core_ui.UiContext, state: *ProjectEditorState, idx: usize, obj: *SceneObject) !void {
    if (!(try ui_widgets.collapsible(ui, "Building", true))) return;
    const active_idx = project_editor_architecture.activeBuildingIndex(state);
    const is_active = if (active_idx) |ai| ai == idx else false;
    const children = project_editor_architecture.buildingChildCount(state, obj.id);
    var buf: [128]u8 = undefined;
    try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&buf, "{s}  {d} attached", .{
        if (is_active) "Active" else "Inactive",
        children,
    }) catch "Building");
    if (!is_active) {
        if ((try ui_widgets.button(ui, "ed-arch-make-active", "Make Active", 118, false)).clicked) {
            project_editor_architecture.setActiveBuilding(state, obj.id);
            project_editor_state.setStatus(state, "Active building set");
        }
    }
}

/// Inspector for a non-building object selected in architecture mode: link it to
/// the active building so the two move together, or break that link.
fn buildAttachSection(ui: *core_ui.UiContext, state: *ProjectEditorState, obj: *SceneObject) !void {
    if (!(try ui_widgets.collapsible(ui, "Building Link", true))) return;
    var buf: [128]u8 = undefined;
    if (obj.parent_id) |pid| {
        const parent_name = objectNameById(state, pid) orelse "building";
        try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&buf, "Attached to {s}", .{parent_name}) catch "Attached");
        if ((try ui_widgets.button(ui, command_ids.architecture_detach_prop, "Detach", 70, false)).clicked) {
            project_editor_architecture.detachSelected(state);
        }
        return;
    }
    if (project_editor_architecture.activeBuilding(state)) |building| {
        try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&buf, "Active: {s}", .{building.name}) catch "Active building");
        if ((try ui_widgets.button(ui, command_ids.architecture_attach_prop, "Attach to Building", 150, false)).clicked) {
            project_editor_architecture.attachSelectedToActiveBuilding(state);
        }
    } else {
        try ui_widgets.compactInfo(ui, "No active building. Pick one in Buildings.");
    }
}

fn objectNameById(state: *const ProjectEditorState, id: u64) ?[]const u8 {
    for (state.objects.items) |candidate| {
        if (candidate.id == id) return candidate.name;
    }
    return null;
}

fn buildFaceBrushInspector(ui: *core_ui.UiContext, state: *ProjectEditorState, obj: *SceneObject) !void {
    const face_idx = state.selected_face;
    if ((try ui_widgets.collapsible(ui, "Material", true))) {
        if (face_idx) |fi| {
            const face_mat = findFaceMaterial(obj, fi);
            const path = if (face_mat) |fm| fm.material_path else obj.material_path orelse project_editor_materials.get(state.selected_material).path;
            try ui_widgets.compactInfo(ui, path);
            try core_ui.layout.sameLine(ui);
            for (project_editor_materials.catalog[0..3]) |material| {
                if ((try ui_widgets.button(ui, material.toolbar_command_id, material.label, 62, false)).clicked) {
                    project_editor_material_apply.apply(state, material.id);
                }
            }
            try core_ui.layout.endSameLine(ui);
        } else {
            try ui_widgets.compactInfo(ui, obj.material_path orelse project_editor_materials.get(state.selected_material).path);
            try core_ui.layout.sameLine(ui);
            for (project_editor_materials.catalog[0..3]) |material| {
                if ((try ui_widgets.button(ui, material.toolbar_command_id, material.label, 62, state.selected_material == material.id)).clicked) {
                    project_editor_material_apply.apply(state, material.id);
                }
            }
            try core_ui.layout.endSameLine(ui);
        }
    }
    if ((try ui_widgets.collapsible(ui, "UV", true))) {
        const transform = if (face_idx) |fi| blk: {
            if (findFaceMaterial(obj, fi)) |fm| break :blk fm.transform;
            break :blk obj.texture_transform;
        } else obj.texture_transform;
        var uv_buf: [128]u8 = undefined;
        try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&uv_buf, "Scale {d:.2}m  Offset {d:.2},{d:.2}", .{
            transform.scale_world,
            transform.offset_u,
            transform.offset_v,
        }) catch "UV");
        try core_ui.layout.sameLine(ui);
        if ((try ui_widgets.button(ui, "ed-arch-uv-fit", "Fit", 48, false)).clicked) project_editor_material_faces.fitTexture(state);
        if ((try ui_widgets.button(ui, "ed-arch-uv-align", "Align", 58, false)).clicked) project_editor_material_faces.alignTexture(state);
        if ((try ui_widgets.button(ui, "ed-arch-uv-scale-minus", "S-", 38, false)).clicked) project_editor_material_faces.scaleTexture(state, -0.25);
        if ((try ui_widgets.button(ui, "ed-arch-uv-scale-plus", "S+", 38, false)).clicked) project_editor_material_faces.scaleTexture(state, 0.25);
        try core_ui.layout.endSameLine(ui);
    }
    if ((try ui_widgets.collapsible(ui, "Collision", false))) {
        if (obj.physics) |body| {
            var physics_buf: [128]u8 = undefined;
            try ui_widgets.compactInfo(ui, std.fmt.bufPrint(&physics_buf, "{s}  {s}", .{ body.kind.label(), body.collider.label() }) catch "Physics");
            try core_ui.layout.sameLine(ui);
            if ((try ui_widgets.button(ui, command_ids.physics_static, "Static", 58, body.kind == .static)).clicked) {
                project_editor_physics.setSelectedBody(state, project_editor_physics.withKind(obj.physics, .static));
            }
            if ((try ui_widgets.button(ui, command_ids.physics_none, "None", 52, false)).clicked) project_editor_physics.setSelectedBody(state, null);
            try core_ui.layout.endSameLine(ui);
        } else {
            try ui_widgets.compactInfo(ui, "auto_generated");
            if ((try ui_widgets.button(ui, "ed-arch-add-collider", "Add Collider", 120, false)).clicked) {
                project_editor_physics.setSelectedBody(state, project_editor_physics.withKind(null, .static));
            }
        }
    }
    if ((try ui_widgets.collapsible(ui, "Surface", false))) {
        const surface_label = project_editor_surface_faces.surfaceLabel(obj, face_idx);
        try ui_widgets.compactInfo(ui, surface_label);
        if (face_idx != null) {
            try core_ui.layout.sameLine(ui);
            if ((try ui_widgets.button(ui, "ed-arch-surface-cycle", "Cycle", 58, false)).clicked) {
                project_editor_surface_faces.cycleSelectedFace(state);
            }
            try core_ui.layout.endSameLine(ui);
        }
    }
    if ((try ui_widgets.collapsible(ui, "Lightmap", false))) {
        const lightmap_label = if (obj.lightmap_path) |path| path else "none";
        try ui_widgets.compactInfo(ui, lightmap_label);
    }
}

fn findFaceMaterial(obj: *const SceneObject, face_index: usize) ?@import("runtime_shared").scene_texture.FaceMaterial {
    for (obj.face_materials) |face| {
        if (face.face_index == face_index) return face;
    }
    return null;
}

pub fn formatBottomSelection(buf: []u8, state: *const ProjectEditorState) ?[]const u8 {
    const selection = selectionTypeLabel(state);
    return std.fmt.bufPrint(buf, "Sel {s} | Grid {d:.2} | CSG {s}", .{
        selection,
        state.snap_size,
        if (state.csg_preview_live) "Live" else "Off",
    }) catch null;
}

pub fn selectionTypeLabel(state: *const ProjectEditorState) []const u8 {
    if (state.selected_face != null) return "Face";
    if (state.selected_edge != null) return "Edge";
    if (state.selected_vertex != null) return "Vertex";
    return switch (state.architecture_tool) {
        .network => "Network",
        .floorplan => "Floor",
        .shell => "Shell",
        .foundation => "Foundation",
        .cutout => "Cutout",
        .wall => "Wall",
        .opening => "Opening",
        .roof => "Roof",
        .door => "Door",
        .window => "Window",
        .curve => "Curve",
        .brush, .add, .subtract => "Brush",
        .vertex => "Vertex",
        .edge => "Edge",
        .face, .extrude, .inset => "Face",
        .ramp => "Ramp",
        .material => "Material",
    };
}

pub fn placeRampAtClick(state: *ProjectEditorState, screen_x: f32, screen_y: f32) void {
    const pt = project_editor_scene.screenToGroundPoint(state, screen_x, screen_y) orelse {
        project_editor_state.setStatus(state, "Ramp needs ground hit");
        return;
    };
    project_editor_edit.pushUndoSnapshot(state);
    project_editor_blockout.addBlockoutRampAt(state, pt, @max(1.0, state.snap_size * 2.0), @max(1.0, state.blockout_brush_size), @max(1.0, state.snap_size * 3.0)) catch {
        project_editor_state.setStatus(state, "Ramp add failed");
        return;
    };
}
