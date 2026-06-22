const std = @import("std");
const shared = @import("runtime_shared");
const geometry = shared.geometry;
const command_ids = shared.editor_command_ids;
const project_editor_blockout = @import("project_editor_blockout.zig");
const project_editor_architecture = @import("project_editor_architecture.zig");
const blockout_primitives = @import("project_editor_blockout_primitives.zig");
const project_editor_edit = @import("project_editor_edit.zig");
const project_editor_build = @import("project_editor_build.zig");
const project_editor_life = @import("project_editor_life.zig");
const project_editor_material_apply = @import("project_editor_material_apply.zig");
const project_editor_material_faces = @import("project_editor_material_faces.zig");
const project_editor_materials = @import("project_editor_materials.zig");
const project_editor_physics = @import("project_editor_physics.zig");
const project_editor_scene = @import("project_editor_scene.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_types = @import("project_editor_types.zig");
const project_editor_ui_widgets = @import("project_editor_ui_widgets.zig");
const project_editor_world_bake = @import("project_editor_world_bake.zig");
const world_authoring = @import("project_editor_world_authoring.zig");
const editor_commands = @import("editor_commands.zig");
const project_editor_modes = @import("project_editor_modes.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;

pub fn execute(state: *ProjectEditorState, command_id: []const u8) void {
    executeCommandId(state, command_id) catch |err| switch (err) {
        error.CommandUnavailable => setUnavailable(state, command_id),
        error.NoSelection, error.ObjectNotFound => project_editor_state.setStatus(state, "No selection"),
        error.McpOnly => project_editor_state.setStatus(state, "MCP only: use friendly_engine_mcp"),
        error.PlaySceneFailed, error.PlaySceneLaunchFailed, error.PlaySceneStopped => {
            if (state.editor_error_detail == null) {
                var buf: [96]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "Play scene failed: {s}", .{@errorName(err)}) catch "Play scene failed";
                project_editor_state.setStatus(state, msg);
            }
        },
        else => {
            var buf: [96]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "Command failed: {s}", .{@errorName(err)}) catch "Command failed";
            project_editor_state.setStatus(state, msg);
        },
    };
}

pub fn executeCommandId(state: *ProjectEditorState, command_id: []const u8) !void {
    try executeInner(state, command_id);
}

fn executeInner(state: *ProjectEditorState, command_id: []const u8) !void {
    if (std.mem.eql(u8, command_id, "ed-close")) {
        state.should_close = true;
        return;
    }
    if (std.mem.eql(u8, command_id, "ed-save")) {
        try project_editor_ui_widgets.saveScene(state);
        return;
    }
    if (std.mem.eql(u8, command_id, command_ids.play_scene)) {
        state.is_playing = true;
        defer state.is_playing = false;
        try project_editor_build.runPlayScene(state);
        return;
    }
    if (std.mem.eql(u8, command_id, "ed-command-palette")) {
        @import("project_editor_command_palette.zig").toggle(state);
        return;
    }
    if (std.mem.eql(u8, command_id, "ed-ui-tree")) {
        state.ui_tree_open = !state.ui_tree_open;
        project_editor_state.setStatus(state, if (state.ui_tree_open) "UI tree open" else "UI tree closed");
        return;
    }
    if (std.mem.eql(u8, command_id, "ed-preferences")) {
        state.preferences_open = !state.preferences_open;
        project_editor_state.setStatus(state, if (state.preferences_open) "Preferences open" else "Preferences closed");
        return;
    }
    if (std.mem.eql(u8, command_id, command_ids.toggle_tool_inspector)) {
        state.show_tool_inspector = !state.show_tool_inspector;
        project_editor_state.setStatus(state, if (state.show_tool_inspector) "Tool inspector shown" else "Tool inspector hidden");
        return;
    }
    if (std.mem.eql(u8, command_id, command_ids.toggle_project_inspector)) {
        state.show_project_inspector = !state.show_project_inspector;
        project_editor_state.setStatus(state, if (state.show_project_inspector) "Project inspector shown" else "Project inspector hidden");
        return;
    }
    if (std.mem.eql(u8, command_id, "ed-inspect-ui-copy")) {
        state.ui_tree_open = true;
        state.left_tab = .world;
        project_editor_state.setStatus(state, "Inspecting UI copy ownership");
        return;
    }
    if (std.mem.eql(u8, command_id, "ed-recompile-cells")) {
        project_editor_world_bake.recompileDirtyCells(state);
        return;
    }
    if (std.mem.eql(u8, command_id, "ed-duplicate") or std.mem.eql(u8, command_id, "ed-copy")) {
        try project_editor_scene.duplicateSelected(state);
        return;
    }
    if (std.mem.eql(u8, command_id, "ed-delete")) {
        try project_editor_scene.deleteSelected(state);
        return;
    }
    if (std.mem.eql(u8, command_id, "ed-snap")) {
        project_editor_edit.toggleSnap(state);
        return;
    }
    if (std.mem.eql(u8, command_id, "ed-grid-minus")) {
        state.snap_size = @max(0.25, state.snap_size * 0.5);
        return;
    }
    if (std.mem.eql(u8, command_id, "ed-grid-plus")) {
        state.snap_size = @min(16, state.snap_size * 2);
        return;
    }
    if (std.mem.eql(u8, command_id, "ed-axis")) {
        project_editor_scene.cycleMoveAxis(state);
        return;
    }
    if (std.mem.eql(u8, command_id, "ed-texture-fit")) {
        project_editor_material_faces.fitTexture(state);
        return;
    }
    if (std.mem.eql(u8, command_id, "ed-texture-align")) {
        project_editor_material_faces.alignTexture(state);
        return;
    }
    if (std.mem.eql(u8, command_id, "ed-add-gameplay")) {
        try addGameplay(state);
        return;
    }
    if (std.mem.eql(u8, command_id, command_ids.architecture_extrude_room)) {
        try project_editor_blockout.extrudeSelectedFloorplanToRoom(state);
        return;
    }
    if (std.mem.eql(u8, command_id, command_ids.architecture_add_roof)) {
        try project_editor_blockout.addRoofForFloorplans(state);
        return;
    }
    if (std.mem.eql(u8, command_id, command_ids.architecture_player_start)) {
        try project_editor_blockout.addPlayerStartSpawner(state);
        return;
    }
    if (std.mem.eql(u8, command_id, command_ids.architecture_floor_cell)) {
        try project_editor_blockout.addFloorplanCell(state);
        return;
    }
    if (std.mem.eql(u8, command_id, command_ids.architecture_new_building)) {
        project_editor_architecture.startNewBuilding(state);
        return;
    }
    if (std.mem.eql(u8, command_id, command_ids.architecture_attach_prop)) {
        project_editor_architecture.attachSelectedToActiveBuilding(state);
        return;
    }
    if (std.mem.eql(u8, command_id, command_ids.architecture_detach_prop)) {
        project_editor_architecture.detachSelected(state);
        return;
    }
    if (std.mem.eql(u8, command_id, "ed-blockout-doorway")) {
        try blockout_primitives.addDoorway(state);
        return;
    }
    if (std.mem.eql(u8, command_id, "ed-blockout-stair")) {
        try blockout_primitives.addStair(state);
        return;
    }
    if (std.mem.eql(u8, command_id, command_ids.blockout_ramp)) {
        try project_editor_blockout.addBlockoutRamp(state);
        return;
    }
    if (std.mem.eql(u8, command_id, "ed-brush-box")) {
        state.mode = .architecture_creation;
        state.architecture_tool = .brush;
        project_editor_scene.onModeChanged(state);
        return;
    }
    if (std.mem.eql(u8, command_id, "focus-in-viewport")) {
        try editor_commands.focusSelectedObject(state, false);
        return;
    }
    if (std.mem.eql(u8, command_id, "zoom-to-focus")) {
        try editor_commands.focusSelectedObject(state, true);
        return;
    }
    if (std.mem.eql(u8, command_id, "screenshot-editor") or std.mem.eql(u8, command_id, "screenshot-viewport")) {
        return error.McpOnly;
    }

    if (try dispatchMode(state, command_id)) return;
    if (try dispatchObjectTool(state, command_id)) return;
    if (try dispatchArchitectureTool(state, command_id)) return;
    if (try dispatchBlockoutOp(state, command_id)) return;
    if (try dispatchPropTool(state, command_id)) return;
    if (try dispatchLifeTool(state, command_id)) return;
    if (try dispatchWorldTool(state, command_id)) return;
    if (try dispatchWorldCurveAction(state, command_id)) return;
    if (try dispatchWorldRoadMode(state, command_id)) return;
    if (try dispatchWorldRoadDrawMode(state, command_id)) return;
    if (try dispatchWorldRoadAction(state, command_id)) return;
    if (try dispatchLeftTab(state, command_id)) return;
    if (try dispatchPrimitive(state, command_id)) return;
    if (try dispatchWorldLayer(state, command_id)) return;
    if (try dispatchMaterial(state, command_id)) return;
    if (try dispatchPhysics(state, command_id)) return;
    if (try dispatchLifeAction(state, command_id)) return;

    return error.CommandUnavailable;
}

fn dispatchMode(state: *ProjectEditorState, command_id: []const u8) !bool {
    const modes = [_]struct { id: []const u8, mode: project_editor_types.EditorMode }{
        .{ .id = command_ids.mode_world_creation, .mode = .world_creation },
        .{ .id = command_ids.mode_layout, .mode = .layout },
        .{ .id = command_ids.mode_architecture_creation, .mode = .architecture_creation },
        .{ .id = command_ids.mode_prop_creation, .mode = .prop_creation },
        .{ .id = command_ids.mode_life, .mode = .life },
    };
    for (modes) |entry| {
        if (std.mem.eql(u8, command_id, entry.id)) {
            if (!project_editor_modes.enabled(state, entry.mode)) return error.CommandUnavailable;
            project_editor_scene.setMode(state, entry.mode);
            return true;
        }
    }
    return false;
}

fn dispatchObjectTool(state: *ProjectEditorState, command_id: []const u8) !bool {
    const tools = [_]struct { id: []const u8, tool: project_editor_types.ObjectTool }{
        .{ .id = command_ids.object_select, .tool = .select },
        .{ .id = command_ids.object_move, .tool = .move },
        .{ .id = command_ids.object_rotate, .tool = .rotate },
        .{ .id = command_ids.object_scale, .tool = .scale },
    };
    for (tools) |entry| {
        if (std.mem.eql(u8, command_id, entry.id)) {
            project_editor_scene.setObjectTool(state, entry.tool);
            return true;
        }
    }
    return false;
}

fn dispatchArchitectureTool(state: *ProjectEditorState, command_id: []const u8) !bool {
    const ui_architecture = @import("project_editor_ui_architecture.zig");
    const tools = [_]project_editor_types.ArchitectureTool{ .network, .floorplan, .shell, .foundation, .cutout, .wall, .opening, .roof, .door, .window, .curve, .brush, .add, .subtract, .vertex, .edge, .face, .extrude, .inset, .ramp, .material };
    inline for (tools) |tool| {
        if (std.mem.eql(u8, command_id, command_ids.architectureTool(@tagName(tool)))) {
            ui_architecture.selectTool(state, tool);
            return true;
        }
    }
    return false;
}

fn dispatchBlockoutOp(state: *ProjectEditorState, command_id: []const u8) !bool {
    const ops = [_]project_editor_types.BlockoutOp{ .add, .subtract };
    inline for (ops) |op| {
        if (std.mem.eql(u8, command_id, command_ids.blockoutOp(@tagName(op)))) {
            state.blockout_op = op;
            return true;
        }
    }
    return false;
}

fn dispatchPropTool(state: *ProjectEditorState, command_id: []const u8) !bool {
    const tools = [_]project_editor_types.PropTool{ .select, .create, .asset, .primitive, .edit, .material, .collider, .variants };
    inline for (tools) |tool| {
        if (std.mem.eql(u8, command_id, command_ids.propTool(@tagName(tool)))) {
            state.prop_tool = tool;
            state.prop_workspace_mode = if (tool == .select) .display else .edit;
            if (state.prop_workspace_mode == .display) state.shading_mode = .rendered;
            project_editor_state.setStatus(state, switch (tool) {
                .select => "Display mode",
                .create, .primitive => "Draw shape: pick base, sketch, make solid",
                .asset => "Browse props: find, tag, sort, or open",
                .edit => "Shape Builder",
                .material => "Texture Paint: no UV setup",
                .collider => "Collider Fit",
                .variants => "Prop variants",
            });
            return true;
        }
    }
    if (std.mem.eql(u8, command_id, command_ids.prop_collider_preview)) {
        state.prop_collider_preview = !state.prop_collider_preview;
        return true;
    }
    if (std.mem.eql(u8, command_id, command_ids.prop_placement_mode)) {
        state.prop_placement_mode = switch (state.prop_placement_mode) {
            .surface => .ground,
            .ground => .free,
            .free => .surface,
        };
        return true;
    }
    if (std.mem.eql(u8, command_id, "ed-prop-delete") or std.mem.eql(u8, command_id, "ed-prop-library-delete")) {
        @import("project_editor_ui_prop.zig").requestPropDelete(state);
        return true;
    }
    if (std.mem.eql(u8, command_id, "ed-prop-rename") or
        std.mem.eql(u8, command_id, "ed-prop-tags") or
        std.mem.eql(u8, command_id, "ed-prop-library-rename") or
        std.mem.eql(u8, command_id, "ed-prop-library-tags"))
    {
        @import("project_editor_ui_prop.zig").requestPropMetadataEdit(state);
        return true;
    }
    return false;
}

fn dispatchLifeTool(state: *ProjectEditorState, command_id: []const u8) !bool {
    const tools = [_]project_editor_types.LifeTool{ .select, .pose, .keyframe, .record, .playback, .clips, .bones, .curves };
    inline for (tools) |tool| {
        if (std.mem.eql(u8, command_id, command_ids.lifeTool(@tagName(tool)))) {
            state.life_tool = tool;
            project_editor_life.onToolActivated(state, tool);
            return true;
        }
    }
    return false;
}

fn dispatchLifeAction(state: *ProjectEditorState, command_id: []const u8) !bool {
    if (std.mem.eql(u8, command_id, command_ids.life_add_clip)) {
        try project_editor_life.addClip(state);
        return true;
    }
    if (std.mem.eql(u8, command_id, command_ids.life_add_keyframe)) {
        try project_editor_life.addObjectKeyframe(state);
        return true;
    }
    if (std.mem.eql(u8, command_id, command_ids.life_play)) {
        project_editor_life.togglePlayback(state);
        return true;
    }
    if (std.mem.eql(u8, command_id, command_ids.life_auto_key)) {
        state.life_auto_key = !state.life_auto_key;
        state.life_recording = state.life_auto_key;
        project_editor_state.setStatus(state, if (state.life_auto_key) "Auto Key on" else "Auto Key off");
        return true;
    }
    return false;
}

fn dispatchWorldTool(state: *ProjectEditorState, command_id: []const u8) !bool {
    const ui_world = @import("project_editor_ui_world.zig");
    const tools = [_]project_editor_types.WorldTool{ .terrain, .paint, .roads, .scatter, .atmosphere, .ocean, .water, .measure };
    inline for (tools) |tool| {
        if (std.mem.eql(u8, command_id, command_ids.worldTool(@tagName(tool)))) {
            state.mode = .world_creation;
            ui_world.setWorldTool(state, tool);
            return true;
        }
    }
    return false;
}

fn dispatchWorldCurveAction(state: *ProjectEditorState, command_id: []const u8) !bool {
    const ui_world = @import("project_editor_ui_world.zig");
    if (std.mem.eql(u8, command_id, command_ids.world_curve_delete_selected)) {
        state.mode = .world_creation;
        _ = ui_world.deleteSelectedWorldCurvePart(state);
        return true;
    }
    return false;
}

fn dispatchWorldRoadMode(state: *ProjectEditorState, command_id: []const u8) !bool {
    const ui_world = @import("project_editor_ui_world.zig");
    const modes = [_]project_editor_types.RoadToolMode{ .draw, .select, .shape, .join, .surface };
    inline for (modes) |mode| {
        if (std.mem.eql(u8, command_id, command_ids.worldRoadMode(@tagName(mode)))) {
            state.mode = .world_creation;
            ui_world.setWorldTool(state, .roads);
            ui_world.setRoadMode(state, mode);
            return true;
        }
    }
    return false;
}

fn dispatchWorldRoadDrawMode(state: *ProjectEditorState, command_id: []const u8) !bool {
    const ui_world = @import("project_editor_ui_world.zig");
    const modes = [_]project_editor_types.CurveDrawMode{ .point_by_point, .freehand };
    inline for (modes) |mode| {
        if (std.mem.eql(u8, command_id, command_ids.worldRoadDrawMode(@tagName(mode)))) {
            state.mode = .world_creation;
            ui_world.setWorldTool(state, .roads);
            ui_world.setRoadDrawMode(state, mode);
            return true;
        }
    }
    return false;
}

fn dispatchWorldRoadAction(state: *ProjectEditorState, command_id: []const u8) !bool {
    const ui_world = @import("project_editor_ui_world.zig");
    if (!isWorldRoadAction(command_id)) return false;
    state.mode = .world_creation;
    ui_world.setWorldTool(state, .roads);

    if (std.mem.eql(u8, command_id, command_ids.world_road_finish)) {
        ui_world.finishRoadPlacement(state);
        return true;
    }
    if (std.mem.eql(u8, command_id, command_ids.world_road_clear)) {
        ui_world.clearRoadPlacement(state);
        project_editor_state.setStatus(state, "Road draft cleared");
        return true;
    }
    if (std.mem.eql(u8, command_id, command_ids.world_road_delete_selected)) {
        if (state.selected_road_edge_id != null) {
            try ui_world.deleteSelectedRoadEdge(state);
            return true;
        }
        if (state.selected_road_node_id != null) {
            try ui_world.deleteSelectedRoadJunction(state);
            return true;
        }
        project_editor_state.setStatus(state, "Select part of a road first");
        return true;
    }
    if (std.mem.eql(u8, command_id, command_ids.world_road_split_selected)) {
        try ui_world.splitSelectedRoadEdgeAtScreen(state, state.mouse_x, state.mouse_y);
        return true;
    }
    if (std.mem.eql(u8, command_id, command_ids.world_road_straighten)) {
        try ui_world.straightenSelectedRoadSegment(state);
        return true;
    }
    if (std.mem.eql(u8, command_id, command_ids.world_road_soften)) {
        try ui_world.softenSelectedRoadSegment(state);
        return true;
    }
    if (std.mem.eql(u8, command_id, command_ids.world_road_rebuild_selected)) {
        try ui_world.regenerateSelectedRoad(state);
        return true;
    }
    if (std.mem.eql(u8, command_id, command_ids.world_road_rebuild_all)) {
        try ui_world.regenerateAllRoads(state);
        return true;
    }
    return false;
}

fn isWorldRoadAction(command_id: []const u8) bool {
    return std.mem.eql(u8, command_id, command_ids.world_road_finish) or
        std.mem.eql(u8, command_id, command_ids.world_road_clear) or
        std.mem.eql(u8, command_id, command_ids.world_road_delete_selected) or
        std.mem.eql(u8, command_id, command_ids.world_road_split_selected) or
        std.mem.eql(u8, command_id, command_ids.world_road_straighten) or
        std.mem.eql(u8, command_id, command_ids.world_road_soften) or
        std.mem.eql(u8, command_id, command_ids.world_road_rebuild_selected) or
        std.mem.eql(u8, command_id, command_ids.world_road_rebuild_all);
}

fn dispatchLeftTab(state: *ProjectEditorState, command_id: []const u8) !bool {
    const tabs = [_]struct { id: []const u8, tab: project_editor_types.LeftRailTab }{
        .{ .id = command_ids.left_scene, .tab = .scene },
        .{ .id = command_ids.left_add, .tab = .add },
        .{ .id = command_ids.left_world, .tab = .world },
        .{ .id = command_ids.left_assets, .tab = .assets },
    };
    for (tabs) |entry| {
        if (std.mem.eql(u8, command_id, entry.id)) {
            state.left_tab = entry.tab;
            return true;
        }
    }
    return false;
}

fn dispatchPrimitive(state: *ProjectEditorState, command_id: []const u8) !bool {
    const primitives = [_]struct { id: []const u8, kind: geometry.PrimitiveKind, label: []const u8 }{
        .{ .id = "Box", .kind = .box, .label = "Box" },
        .{ .id = "Plane", .kind = .plane, .label = "Plane" },
        .{ .id = "Cylinder", .kind = .cylinder, .label = "Cylinder" },
        .{ .id = "Sphere", .kind = .sphere, .label = "Sphere" },
    };
    for (primitives) |prim| {
        if (std.mem.eql(u8, command_id, prim.id)) {
            try project_editor_scene.addPrimitive(state, prim.kind, prim.label);
            return true;
        }
    }
    return false;
}

fn dispatchWorldLayer(state: *ProjectEditorState, command_id: []const u8) !bool {
    const layers = [_]struct { id: []const u8, func: *const fn (*ProjectEditorState) anyerror!void, ok: []const u8, err: []const u8 }{
        .{ .id = "Terrain Tile", .func = world_authoring.paintTerrainTile, .ok = "Terrain layer updated", .err = "Terrain layer write failed" },
        .{ .id = "Road Graph", .func = world_authoring.drawRoadThroughCell, .ok = "Road updated", .err = "Road update failed" },
        .{ .id = "Scatter", .func = world_authoring.seedScatter, .ok = "Scatter layer updated", .err = "Scatter layer write failed" },
        .{ .id = "Interior Room", .func = world_authoring.authorInteriorRoom, .ok = "Sector layer updated", .err = "Sector layer write failed" },
        .{ .id = "Building", .func = world_authoring.authorBuilding, .ok = "Building layer updated", .err = "Building layer write failed" },
    };
    for (layers) |layer| {
        if (std.mem.eql(u8, command_id, layer.id)) {
            try project_editor_ui_widgets.writeLayer(state, layer.func, layer.ok, layer.err);
            return true;
        }
    }
    return false;
}

fn dispatchMaterial(state: *ProjectEditorState, command_id: []const u8) !bool {
    for (project_editor_materials.catalog) |material| {
        if (std.mem.eql(u8, command_id, material.asset_command_id) or
            std.mem.eql(u8, command_id, material.toolbar_command_id))
        {
            project_editor_material_apply.apply(state, material.id);
            return true;
        }
    }
    return false;
}

fn dispatchPhysics(state: *ProjectEditorState, command_id: []const u8) !bool {
    if (!isPhysicsCommand(command_id)) return false;
    const idx = state.selected_object orelse return error.NoSelection;
    const obj = &state.objects.items[idx];
    if (std.mem.eql(u8, command_id, command_ids.physics_none)) {
        project_editor_physics.setSelectedBody(state, null);
        return true;
    }
    if (std.mem.eql(u8, command_id, command_ids.physics_static)) {
        project_editor_physics.setSelectedBody(state, project_editor_physics.withKind(obj.physics, .static));
        return true;
    }
    if (std.mem.eql(u8, command_id, command_ids.physics_dynamic)) {
        project_editor_physics.setSelectedBody(state, project_editor_physics.withKind(obj.physics, .dynamic));
        return true;
    }
    if (std.mem.eql(u8, command_id, command_ids.physics_kinematic)) {
        project_editor_physics.setSelectedBody(state, project_editor_physics.withKind(obj.physics, .kinematic));
        return true;
    }
    return false;
}

fn addGameplay(state: *ProjectEditorState) !void {
    const idx = state.selected_object orelse return error.NoSelection;
    project_editor_edit.pushUndoSnapshot(state);
    const obj = &state.objects.items[idx];
    obj.gameplay = try shared.scene_gameplay.Component.duplicate(state.allocator, .{
        .tag = try shared.scene_gameplay.Component.defaultTag(state.allocator),
    });
    state.scene_dirty = true;
    project_editor_state.setStatus(state, "Gameplay added");
}

fn setUnavailable(state: *ProjectEditorState, command_id: []const u8) void {
    var buf: [128]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "Unknown command: {s}", .{command_id}) catch "Unknown command";
    project_editor_state.setStatus(state, msg);
}

fn isPhysicsCommand(command_id: []const u8) bool {
    return std.mem.eql(u8, command_id, command_ids.physics_none) or
        std.mem.eql(u8, command_id, command_ids.physics_static) or
        std.mem.eql(u8, command_id, command_ids.physics_dynamic) or
        std.mem.eql(u8, command_id, command_ids.physics_kinematic);
}

test "world tool command ids switch world tools like toolbar buttons" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .mode = .layout,
        .world_tool = .terrain,
        .selected_world_layer = .terrain_base_height,
    };

    try executeCommandId(&state, command_ids.world_roads);
    try std.testing.expectEqual(project_editor_types.EditorMode.world_creation, state.mode);
    try std.testing.expectEqual(project_editor_types.WorldTool.roads, state.world_tool);
    try std.testing.expectEqual(project_editor_types.WorldLayerId.spline_road_main, state.selected_world_layer.?);
    try std.testing.expectEqualStrings("Click terrain to start a road.", state.status_buf[0..state.status_len]);

    try executeCommandId(&state, command_ids.world_water);
    try std.testing.expectEqual(project_editor_types.WorldTool.water, state.world_tool);
    try std.testing.expectEqual(project_editor_types.WorldLayerId.water_volumes, state.selected_world_layer.?);
    try std.testing.expectEqualStrings("Click a water shape, or create one at the camera target.", state.status_buf[0..state.status_len]);
}

test "road submode command ids switch roads like toolbar buttons" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .mode = .layout,
        .world_tool = .terrain,
        .world_road_mode = .draw,
        .world_road_draw_mode = .point_by_point,
        .selected_world_layer = .terrain_base_height,
    };

    try state.world_road_points.append(std.testing.allocator, .{ .x = 1, .y = 0, .z = 2 });
    defer state.world_road_points.deinit(std.testing.allocator);

    try executeCommandId(&state, command_ids.world_road_mode_shape);
    try std.testing.expectEqual(project_editor_types.EditorMode.world_creation, state.mode);
    try std.testing.expectEqual(project_editor_types.WorldTool.roads, state.world_tool);
    try std.testing.expectEqual(project_editor_types.WorldLayerId.spline_road_main, state.selected_world_layer.?);
    try std.testing.expectEqual(project_editor_types.RoadToolMode.shape, state.world_road_mode);
    try std.testing.expectEqual(@as(usize, 0), state.world_road_points.items.len);
    try std.testing.expectEqualStrings("Shape: drag a yellow point or handle to bend the road", state.status_buf[0..state.status_len]);

    try executeCommandId(&state, command_ids.world_road_draw_freehand);
    try std.testing.expectEqual(project_editor_types.RoadToolMode.draw, state.world_road_mode);
    try std.testing.expectEqual(project_editor_types.CurveDrawMode.freehand, state.world_road_draw_mode);
    try std.testing.expectEqualStrings("Drag on terrain to sketch a road.", state.status_buf[0..state.status_len]);
}

test "road action command ids share toolbar behavior" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .mode = .layout,
        .world_tool = .terrain,
        .world_road_mode = .draw,
        .selected_world_layer = .terrain_base_height,
    };
    try state.world_road_points.append(std.testing.allocator, .{ .x = 1, .y = 0, .z = 2 });
    defer state.world_road_points.deinit(std.testing.allocator);

    try executeCommandId(&state, command_ids.world_road_clear);
    try std.testing.expectEqual(project_editor_types.EditorMode.world_creation, state.mode);
    try std.testing.expectEqual(project_editor_types.WorldTool.roads, state.world_tool);
    try std.testing.expectEqual(project_editor_types.WorldLayerId.spline_road_main, state.selected_world_layer.?);
    try std.testing.expectEqual(@as(usize, 0), state.world_road_points.items.len);
    try std.testing.expectEqualStrings("Road draft cleared", state.status_buf[0..state.status_len]);

    try executeCommandId(&state, command_ids.world_road_delete_selected);
    try std.testing.expectEqualStrings("Select part of a road first", state.status_buf[0..state.status_len]);

    state.selected_road_edge_id = try std.testing.allocator.dupe(u8, "edge-1");
    defer if (state.selected_road_edge_id) |id| std.testing.allocator.free(id);
    try executeCommandId(&state, command_ids.world_road_rebuild_selected);
    try std.testing.expect(state.spline_preview_stale);
    try std.testing.expectEqualStrings("Selected road queued for rebuild", state.status_buf[0..state.status_len]);
}

test "shared world curve delete command uses visible selection rules" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .mode = .layout,
        .world_tool = .water,
        .selected_world_curve_hit = .{ .target = .water_volume, .element = .handle_start },
    };

    try executeCommandId(&state, command_ids.world_curve_delete_selected);
    try std.testing.expectEqual(project_editor_types.EditorMode.world_creation, state.mode);
    try std.testing.expectEqualStrings("Drag the surface handle to change water height", state.status_buf[0..state.status_len]);
}
