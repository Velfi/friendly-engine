const std = @import("std");
const command_ids = @import("editor_command_ids.zig");
const editor_control_commands = @import("editor_control_commands.zig");

pub const project_editor_screen = "Project Editor";

pub const Entry = struct {
    id: []const u8,
    label: []const u8,
    screen: []const u8,
    section: []const u8,
};

const ui_entries = [_]Entry{
    .{ .id = "pm-menu-file", .label = "File", .screen = "Project Manager", .section = "window menu" },
    .{ .id = "pm-menu-help", .label = "Help", .screen = "Project Manager", .section = "window menu" },
    .{ .id = "New Project...", .label = "New Project...", .screen = "Project Manager", .section = "window menu" },
    .{ .id = "Import Project...", .label = "Import Project...", .screen = "Project Manager", .section = "window menu" },
    .{ .id = "Open Project", .label = "Open Project", .screen = "Project Manager", .section = "window menu" },
    .{ .id = "Remove from List", .label = "Remove from List", .screen = "Project Manager", .section = "window menu" },
    .{ .id = "Quit", .label = "Quit", .screen = "Project Manager", .section = "window menu" },
    .{ .id = "About friendly-engine editor", .label = "About friendly-engine editor", .screen = "Project Manager", .section = "window menu" },
    .{ .id = "pm-create", .label = "Create", .screen = "Project Manager", .section = "toolbar" },
    .{ .id = "pm-import", .label = "Import", .screen = "Project Manager", .section = "toolbar" },
    .{ .id = "pm-open", .label = "Open", .screen = "Project Manager", .section = "toolbar" },
    .{ .id = "pm-filter-all", .label = "All", .screen = "Project Manager", .section = "project list" },
    .{ .id = "pm-filter-recent", .label = "Recent", .screen = "Project Manager", .section = "project list" },
    .{ .id = "pm-cancel", .label = "Cancel", .screen = "Project Manager", .section = "modal" },
    .{ .id = "pm-confirm", .label = "Create or Close", .screen = "Project Manager", .section = "modal" },

    .{ .id = "ed-close", .label = "Close", .screen = project_editor_screen, .section = "top bar" },
    .{ .id = "ed-save", .label = "Save", .screen = project_editor_screen, .section = "top bar" },
    .{ .id = command_ids.play_scene, .label = "Play Scene", .screen = project_editor_screen, .section = "top bar" },
    .{ .id = command_ids.toggle_tool_inspector, .label = "Toggle Tool Inspector", .screen = project_editor_screen, .section = "top bar" },
    .{ .id = command_ids.toggle_project_inspector, .label = "Toggle Project Inspector", .screen = project_editor_screen, .section = "top bar" },
    .{ .id = command_ids.mode_world_creation, .label = "World", .screen = project_editor_screen, .section = "top bar" },
    .{ .id = command_ids.mode_layout, .label = "Layout", .screen = project_editor_screen, .section = "top bar" },
    .{ .id = command_ids.mode_architecture_creation, .label = "Architecture", .screen = project_editor_screen, .section = "top bar" },
    .{ .id = command_ids.mode_prop_creation, .label = "Prop", .screen = project_editor_screen, .section = "top bar" },
    .{ .id = command_ids.mode_life, .label = "Life", .screen = project_editor_screen, .section = "top bar" },
    .{ .id = command_ids.world_terrain, .label = "Terrain", .screen = project_editor_screen, .section = "world creation" },
    .{ .id = command_ids.world_paint, .label = "Paint", .screen = project_editor_screen, .section = "world creation" },
    .{ .id = command_ids.world_roads, .label = "Roads", .screen = project_editor_screen, .section = "world creation" },
    .{ .id = command_ids.world_scatter, .label = "Scatter", .screen = project_editor_screen, .section = "world creation" },
    .{ .id = command_ids.world_atmosphere, .label = "Atmosphere", .screen = project_editor_screen, .section = "world creation" },
    .{ .id = command_ids.world_ocean, .label = "Ocean", .screen = project_editor_screen, .section = "world creation" },
    .{ .id = command_ids.world_water, .label = "Water", .screen = project_editor_screen, .section = "world creation" },
    .{ .id = command_ids.world_measure, .label = "Measure", .screen = project_editor_screen, .section = "world creation" },
    .{ .id = command_ids.world_curve_delete_selected, .label = "Delete Selected Curve", .screen = project_editor_screen, .section = "world creation" },
    .{ .id = command_ids.world_road_mode_draw, .label = "Road Draw", .screen = project_editor_screen, .section = "world creation" },
    .{ .id = command_ids.world_road_mode_select, .label = "Road Select", .screen = project_editor_screen, .section = "world creation" },
    .{ .id = command_ids.world_road_mode_shape, .label = "Road Shape", .screen = project_editor_screen, .section = "world creation" },
    .{ .id = command_ids.world_road_mode_join, .label = "Road Join", .screen = project_editor_screen, .section = "world creation" },
    .{ .id = command_ids.world_road_mode_surface, .label = "Road Surface", .screen = project_editor_screen, .section = "world creation" },
    .{ .id = command_ids.world_road_draw_point, .label = "Road Point", .screen = project_editor_screen, .section = "world creation" },
    .{ .id = command_ids.world_road_draw_freehand, .label = "Road Freehand", .screen = project_editor_screen, .section = "world creation" },
    .{ .id = command_ids.world_road_finish, .label = "Finish Road", .screen = project_editor_screen, .section = "world creation" },
    .{ .id = command_ids.world_road_clear, .label = "Clear Road Draft", .screen = project_editor_screen, .section = "world creation" },
    .{ .id = command_ids.world_road_delete_selected, .label = "Delete Selected Road", .screen = project_editor_screen, .section = "world creation" },
    .{ .id = command_ids.world_road_split_selected, .label = "Add Point to Road", .screen = project_editor_screen, .section = "world creation" },
    .{ .id = command_ids.world_road_straighten, .label = "Straighten Road", .screen = project_editor_screen, .section = "world creation" },
    .{ .id = command_ids.world_road_soften, .label = "Soften Road", .screen = project_editor_screen, .section = "world creation" },
    .{ .id = command_ids.world_road_rebuild_selected, .label = "Rebuild Selected Road", .screen = project_editor_screen, .section = "world creation" },
    .{ .id = command_ids.world_road_rebuild_all, .label = "Rebuild All Roads", .screen = project_editor_screen, .section = "world creation" },
    .{ .id = command_ids.object_select, .label = "Select", .screen = project_editor_screen, .section = "layout" },
    .{ .id = command_ids.object_move, .label = "Move", .screen = project_editor_screen, .section = "layout" },
    .{ .id = command_ids.object_rotate, .label = "Rotate", .screen = project_editor_screen, .section = "layout" },
    .{ .id = command_ids.object_scale, .label = "Scale", .screen = project_editor_screen, .section = "layout" },
    .{ .id = "ed-duplicate", .label = "Duplicate", .screen = project_editor_screen, .section = "layout" },
    .{ .id = command_ids.architecture_brush, .label = "Brush", .screen = project_editor_screen, .section = "architecture creation" },
    .{ .id = command_ids.architecture_floorplan, .label = "Floor", .screen = project_editor_screen, .section = "architecture creation" },
    .{ .id = command_ids.architecture_wall, .label = "Wall", .screen = project_editor_screen, .section = "architecture creation" },
    .{ .id = command_ids.architecture_door, .label = "Door", .screen = project_editor_screen, .section = "architecture creation" },
    .{ .id = command_ids.architecture_window, .label = "Window", .screen = project_editor_screen, .section = "architecture creation" },
    .{ .id = command_ids.architecture_curve, .label = "Curve", .screen = project_editor_screen, .section = "architecture creation" },
    .{ .id = command_ids.architecture_add, .label = "Add", .screen = project_editor_screen, .section = "architecture creation" },
    .{ .id = command_ids.architecture_subtract, .label = "Subtract", .screen = project_editor_screen, .section = "architecture creation" },
    .{ .id = command_ids.architecture_ramp, .label = "Ramp", .screen = project_editor_screen, .section = "architecture creation" },
    .{ .id = command_ids.architecture_vertex, .label = "Vertex", .screen = project_editor_screen, .section = "architecture creation" },
    .{ .id = command_ids.architecture_edge, .label = "Edge", .screen = project_editor_screen, .section = "architecture creation" },
    .{ .id = command_ids.architecture_face, .label = "Face", .screen = project_editor_screen, .section = "architecture creation" },
    .{ .id = command_ids.architecture_extrude, .label = "Extrude", .screen = project_editor_screen, .section = "architecture creation" },
    .{ .id = command_ids.architecture_inset, .label = "Inset", .screen = project_editor_screen, .section = "architecture creation" },
    .{ .id = command_ids.architecture_material, .label = "Material", .screen = project_editor_screen, .section = "architecture creation" },
    .{ .id = command_ids.architecture_floor_cell, .label = "Floor Cell", .screen = project_editor_screen, .section = "architecture creation" },
    .{ .id = command_ids.architecture_extrude_room, .label = "Extrude Room", .screen = project_editor_screen, .section = "architecture creation" },
    .{ .id = command_ids.architecture_add_roof, .label = "Add Roof", .screen = project_editor_screen, .section = "architecture creation" },
    .{ .id = command_ids.architecture_player_start, .label = "Player Start", .screen = project_editor_screen, .section = "architecture creation" },
    .{ .id = command_ids.architecture_new_building, .label = "New Building", .screen = project_editor_screen, .section = "architecture creation" },
    .{ .id = command_ids.architecture_attach_prop, .label = "Attach Prop To Building", .screen = project_editor_screen, .section = "architecture creation" },
    .{ .id = command_ids.architecture_detach_prop, .label = "Detach Prop From Building", .screen = project_editor_screen, .section = "architecture creation" },
    .{ .id = command_ids.blockout_add, .label = "Add", .screen = project_editor_screen, .section = "architecture creation" },
    .{ .id = command_ids.blockout_subtract, .label = "Subtract", .screen = project_editor_screen, .section = "architecture creation" },
    .{ .id = command_ids.prop_select, .label = "Select", .screen = project_editor_screen, .section = "prop creation" },
    .{ .id = command_ids.prop_create, .label = "Create", .screen = project_editor_screen, .section = "prop creation" },
    .{ .id = command_ids.prop_asset, .label = "Asset", .screen = project_editor_screen, .section = "prop creation" },
    .{ .id = command_ids.prop_primitive, .label = "Primitive", .screen = project_editor_screen, .section = "prop creation" },
    .{ .id = command_ids.prop_edit, .label = "Edit", .screen = project_editor_screen, .section = "prop creation" },
    .{ .id = command_ids.prop_material, .label = "Material", .screen = project_editor_screen, .section = "prop creation" },
    .{ .id = command_ids.prop_collider, .label = "Collider", .screen = project_editor_screen, .section = "prop creation" },
    .{ .id = command_ids.prop_variants, .label = "Variants", .screen = project_editor_screen, .section = "prop creation" },
    .{ .id = command_ids.prop_collider_preview, .label = "Collider Preview", .screen = project_editor_screen, .section = "prop creation" },
    .{ .id = command_ids.prop_placement_mode, .label = "Placement Mode", .screen = project_editor_screen, .section = "prop creation" },
    .{ .id = command_ids.life_select, .label = "Select", .screen = project_editor_screen, .section = "life" },
    .{ .id = command_ids.life_pose, .label = "Pose", .screen = project_editor_screen, .section = "life" },
    .{ .id = command_ids.life_keyframe, .label = "Keyframe", .screen = project_editor_screen, .section = "life" },
    .{ .id = command_ids.life_record, .label = "Record", .screen = project_editor_screen, .section = "life" },
    .{ .id = command_ids.life_playback, .label = "Playback", .screen = project_editor_screen, .section = "life" },
    .{ .id = command_ids.life_clips, .label = "Clips", .screen = project_editor_screen, .section = "life" },
    .{ .id = command_ids.life_bones, .label = "Bones", .screen = project_editor_screen, .section = "life" },
    .{ .id = command_ids.life_curves, .label = "Curves", .screen = project_editor_screen, .section = "life" },
    .{ .id = command_ids.life_add_clip, .label = "Add Clip", .screen = project_editor_screen, .section = "life" },
    .{ .id = command_ids.life_add_keyframe, .label = "Add Keyframe", .screen = project_editor_screen, .section = "life" },
    .{ .id = command_ids.life_play, .label = "Play or Stop Animation", .screen = project_editor_screen, .section = "life" },
    .{ .id = command_ids.life_auto_key, .label = "Auto Key", .screen = project_editor_screen, .section = "life" },
    .{ .id = command_ids.left_scene, .label = "Scene", .screen = project_editor_screen, .section = "left rail" },
    .{ .id = command_ids.left_add, .label = "Add", .screen = project_editor_screen, .section = "left rail" },
    .{ .id = command_ids.left_world, .label = "World", .screen = project_editor_screen, .section = "left rail" },
    .{ .id = command_ids.left_assets, .label = "Assets", .screen = project_editor_screen, .section = "left rail" },
    .{ .id = "ed-copy", .label = "Copy", .screen = project_editor_screen, .section = "left rail" },
    .{ .id = "ed-delete", .label = "Delete", .screen = project_editor_screen, .section = "left rail" },
    .{ .id = "Box", .label = "Box", .screen = project_editor_screen, .section = "left rail" },
    .{ .id = "Plane", .label = "Plane", .screen = project_editor_screen, .section = "left rail" },
    .{ .id = "Cylinder", .label = "Cylinder", .screen = project_editor_screen, .section = "left rail" },
    .{ .id = "Sphere", .label = "Sphere", .screen = project_editor_screen, .section = "left rail" },
    .{ .id = "ed-brush-box", .label = "Brush box", .screen = project_editor_screen, .section = "left rail" },
    .{ .id = command_ids.blockout_ramp, .label = "Ramp", .screen = project_editor_screen, .section = "left rail" },
    .{ .id = "ed-blockout-doorway", .label = "Doorway", .screen = project_editor_screen, .section = "architecture creation" },
    .{ .id = "ed-blockout-stair", .label = "Stair", .screen = project_editor_screen, .section = "architecture creation" },
    .{ .id = "ed-command-palette", .label = "Command Palette (Cmd/Ctrl+P)", .screen = project_editor_screen, .section = "top bar" },
    .{ .id = "ed-preferences", .label = "Preferences", .screen = project_editor_screen, .section = "top bar" },
    .{ .id = "ed-ui-tree", .label = "UI Tree", .screen = project_editor_screen, .section = "left rail" },
    .{ .id = "ed-inspect-ui-copy", .label = "Inspect UI Copy", .screen = project_editor_screen, .section = "ui inspection" },
    .{ .id = "ed-recompile-cells", .label = "Bake Dirty Cells", .screen = project_editor_screen, .section = "left rail" },
    .{ .id = "ed-texture-fit", .label = "Fit", .screen = project_editor_screen, .section = "prop creation" },
    .{ .id = "ed-texture-align", .label = "Align", .screen = project_editor_screen, .section = "prop creation" },
    .{ .id = "ed-add-gameplay", .label = "Add Gameplay", .screen = project_editor_screen, .section = "inspector" },
    .{ .id = "Terrain Tile", .label = "Terrain Tile", .screen = project_editor_screen, .section = "left rail" },
    .{ .id = "Road Graph", .label = "Road", .screen = project_editor_screen, .section = "left rail" },
    .{ .id = "Scatter", .label = "Scatter", .screen = project_editor_screen, .section = "left rail" },
    .{ .id = "Interior Room", .label = "Interior Room", .screen = project_editor_screen, .section = "left rail" },
    .{ .id = "Building", .label = "Building", .screen = project_editor_screen, .section = "left rail" },
    .{ .id = command_ids.material_asset_light, .label = "Light", .screen = project_editor_screen, .section = "left rail" },
    .{ .id = command_ids.material_asset_slate, .label = "Slate", .screen = project_editor_screen, .section = "left rail" },
    .{ .id = command_ids.material_asset_red, .label = "Red", .screen = project_editor_screen, .section = "left rail" },
    .{ .id = command_ids.material_asset_green, .label = "Green", .screen = project_editor_screen, .section = "left rail" },
    .{ .id = command_ids.material_asset_blue, .label = "Blue", .screen = project_editor_screen, .section = "left rail" },
    .{ .id = command_ids.material_asset_gold, .label = "Gold", .screen = project_editor_screen, .section = "left rail" },
    .{ .id = command_ids.material_toolbar_red, .label = "Red", .screen = project_editor_screen, .section = "tool bar" },
    .{ .id = command_ids.material_toolbar_green, .label = "Green", .screen = project_editor_screen, .section = "tool bar" },
    .{ .id = command_ids.material_toolbar_blue, .label = "Blue", .screen = project_editor_screen, .section = "tool bar" },
    .{ .id = command_ids.material_toolbar_gold, .label = "Gold", .screen = project_editor_screen, .section = "tool bar" },
    .{ .id = command_ids.physics_none, .label = "None", .screen = project_editor_screen, .section = "inspector" },
    .{ .id = command_ids.physics_static, .label = "Static", .screen = project_editor_screen, .section = "inspector" },
    .{ .id = command_ids.physics_dynamic, .label = "Dynamic", .screen = project_editor_screen, .section = "inspector" },
    .{ .id = command_ids.physics_kinematic, .label = "Kinematic", .screen = project_editor_screen, .section = "inspector" },
    .{ .id = "ed-snap", .label = "Snap On or Snap Off", .screen = project_editor_screen, .section = "bottom strip" },
    .{ .id = "ed-grid-minus", .label = "-", .screen = project_editor_screen, .section = "bottom strip" },
    .{ .id = "ed-grid-plus", .label = "+", .screen = project_editor_screen, .section = "bottom strip" },
    .{ .id = "ed-axis", .label = "Move axis", .screen = project_editor_screen, .section = "bottom strip" },
};

const mcp_entries = buildMcpEntries();
pub const entries = ui_entries ++ mcp_entries;

fn buildMcpEntries() [editor_control_commands.exposed_count]Entry {
    var out: [editor_control_commands.exposed_count]Entry = undefined;
    var index: usize = 0;
    for (editor_control_commands.entries) |entry| {
        if (!entry.exposedToMcp()) continue;
        out[index] = .{
            .id = entry.command_name,
            .label = entry.title,
            .screen = project_editor_screen,
            .section = "mcp",
        };
        index += 1;
    }
    return out;
}

pub fn isProjectEditorEntry(entry: Entry) bool {
    return std.mem.eql(u8, entry.screen, project_editor_screen);
}

pub fn sourceForEntry(entry: Entry) []const u8 {
    if (std.mem.eql(u8, entry.screen, "Project Manager")) return "src/runtime/editor/pm_ui_build.zig";
    if (std.mem.eql(u8, entry.screen, project_editor_screen)) return sourceForProjectEditorSection(entry.section);
    @panic("editor command screen has no source owner");
}

fn sourceForProjectEditorSection(section: []const u8) []const u8 {
    if (std.mem.eql(u8, section, "top bar")) return "src/runtime/editor/project_editor_ui_build.zig";
    if (std.mem.eql(u8, section, "tool bar")) return "src/runtime/editor/project_editor_ui_build.zig";
    if (std.mem.eql(u8, section, "bottom strip")) return "src/runtime/editor/project_editor_ui_build.zig";
    if (std.mem.eql(u8, section, "left rail")) return "src/runtime/editor/project_editor_ui_build_left.zig";
    if (std.mem.eql(u8, section, "layout")) return "src/runtime/editor/project_editor_ui_layout.zig";
    if (std.mem.eql(u8, section, "inspector")) return "src/runtime/editor/project_editor_ui_inspector.zig";
    if (std.mem.eql(u8, section, "world creation")) return "src/runtime/editor/project_editor_ui_world.zig";
    if (std.mem.eql(u8, section, "architecture creation")) return "src/runtime/editor/project_editor_ui_architecture.zig";
    if (std.mem.eql(u8, section, "prop creation")) return "src/runtime/editor/project_editor_ui_prop.zig";
    if (std.mem.eql(u8, section, "life")) return "src/runtime/editor/project_editor_ui_life.zig";
    if (std.mem.eql(u8, section, "ui inspection")) return "src/runtime/editor/project_editor_ui_tree.zig";
    if (std.mem.eql(u8, section, "mcp")) return "src/runtime/editor/editor_commands.zig";
    @panic("project editor command section has no source owner");
}

test "world tool commands are discoverable in the project editor catalog" {
    const world_commands = [_]struct { id: []const u8, label: []const u8 }{
        .{ .id = command_ids.world_terrain, .label = "Terrain" },
        .{ .id = command_ids.world_paint, .label = "Paint" },
        .{ .id = command_ids.world_roads, .label = "Roads" },
        .{ .id = command_ids.world_scatter, .label = "Scatter" },
        .{ .id = command_ids.world_atmosphere, .label = "Atmosphere" },
        .{ .id = command_ids.world_ocean, .label = "Ocean" },
        .{ .id = command_ids.world_water, .label = "Water" },
        .{ .id = command_ids.world_measure, .label = "Measure" },
        .{ .id = command_ids.world_curve_delete_selected, .label = "Delete Selected Curve" },
        .{ .id = command_ids.world_road_mode_draw, .label = "Road Draw" },
        .{ .id = command_ids.world_road_mode_select, .label = "Road Select" },
        .{ .id = command_ids.world_road_mode_shape, .label = "Road Shape" },
        .{ .id = command_ids.world_road_mode_join, .label = "Road Join" },
        .{ .id = command_ids.world_road_mode_surface, .label = "Road Surface" },
        .{ .id = command_ids.world_road_draw_point, .label = "Road Point" },
        .{ .id = command_ids.world_road_draw_freehand, .label = "Road Freehand" },
        .{ .id = command_ids.world_road_finish, .label = "Finish Road" },
        .{ .id = command_ids.world_road_clear, .label = "Clear Road Draft" },
        .{ .id = command_ids.world_road_delete_selected, .label = "Delete Selected Road" },
        .{ .id = command_ids.world_road_split_selected, .label = "Add Point to Road" },
        .{ .id = command_ids.world_road_straighten, .label = "Straighten Road" },
        .{ .id = command_ids.world_road_soften, .label = "Soften Road" },
        .{ .id = command_ids.world_road_rebuild_selected, .label = "Rebuild Selected Road" },
        .{ .id = command_ids.world_road_rebuild_all, .label = "Rebuild All Roads" },
    };

    for (world_commands) |expected| {
        var found: ?Entry = null;
        for (entries) |entry| {
            if (std.mem.eql(u8, entry.id, expected.id)) {
                found = entry;
                break;
            }
        }
        const entry = found orelse return error.MissingWorldToolCommand;
        try std.testing.expectEqualStrings(expected.label, entry.label);
        try std.testing.expectEqualStrings(project_editor_screen, entry.screen);
        try std.testing.expectEqualStrings("world creation", entry.section);
        try std.testing.expectEqualStrings("src/runtime/editor/project_editor_ui_world.zig", sourceForEntry(entry));
    }
}
