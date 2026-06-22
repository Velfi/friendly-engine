const std = @import("std");

pub const mode_world_creation = "ed-mode-world-creation";
pub const mode_layout = "ed-mode-layout";
pub const mode_architecture_creation = "ed-mode-architecture-creation";
pub const mode_prop_creation = "ed-mode-prop-creation";
pub const mode_life = "ed-mode-life";

pub const object_select = "ed-object-select";
pub const object_move = "ed-object-move";
pub const object_rotate = "ed-object-rotate";
pub const object_scale = "ed-object-scale";

pub const blockout_add = "ed-blockout-add";
pub const blockout_subtract = "ed-blockout-subtract";
pub const blockout_ramp = "ed-blockout-ramp";

pub const architecture_brush = "ed-architecture-brush";
pub const architecture_network = "ed-architecture-network";
pub const architecture_floorplan = "ed-architecture-floorplan";
pub const architecture_shell = "ed-architecture-shell";
pub const architecture_foundation = "ed-architecture-foundation";
pub const architecture_cutout = "ed-architecture-cutout";
pub const architecture_wall = "ed-architecture-wall";
pub const architecture_opening = "ed-architecture-opening";
pub const architecture_roof = "ed-architecture-roof";
pub const architecture_door = "ed-architecture-door";
pub const architecture_window = "ed-architecture-window";
pub const architecture_curve = "ed-architecture-curve";
pub const architecture_add = "ed-architecture-add";
pub const architecture_subtract = "ed-architecture-subtract";
pub const architecture_ramp = "ed-architecture-ramp";
pub const architecture_vertex = "ed-architecture-vertex";
pub const architecture_edge = "ed-architecture-edge";
pub const architecture_face = "ed-architecture-face";
pub const architecture_extrude = "ed-architecture-extrude";
pub const architecture_inset = "ed-architecture-inset";
pub const architecture_material = "ed-architecture-material";
pub const architecture_floor_cell = "ed-architecture-floor-cell";
pub const architecture_extrude_room = "ed-architecture-extrude-room";
pub const architecture_add_roof = "ed-architecture-add-roof";
pub const architecture_player_start = "ed-architecture-player-start";
pub const architecture_new_building = "ed-architecture-new-building";
pub const architecture_attach_prop = "ed-architecture-attach-prop";
pub const architecture_detach_prop = "ed-architecture-detach-prop";

pub const prop_select = "ed-prop-select";
pub const prop_create = "ed-prop-create";
pub const prop_asset = "ed-prop-asset";
pub const prop_primitive = "ed-prop-primitive";
pub const prop_edit = "ed-prop-edit";
pub const prop_material = "ed-prop-material";
pub const prop_collider = "ed-prop-collider";
pub const prop_variants = "ed-prop-variants";
pub const prop_collider_preview = "ed-prop-collider-preview";
pub const prop_placement_mode = "ed-prop-placement-mode";

pub const life_select = "ed-life-select";
pub const life_pose = "ed-life-pose";
pub const life_keyframe = "ed-life-keyframe";
pub const life_record = "ed-life-record";
pub const life_playback = "ed-life-playback";
pub const life_clips = "ed-life-clips";
pub const life_bones = "ed-life-bones";
pub const life_curves = "ed-life-curves";
pub const life_add_clip = "ed-life-add-clip";
pub const life_add_keyframe = "ed-life-add-keyframe";
pub const life_play = "ed-life-play";
pub const life_auto_key = "ed-life-auto-key";

pub const world_terrain = "ed-world-terrain";
pub const world_paint = "ed-world-paint";
pub const world_roads = "ed-world-roads";
pub const world_scatter = "ed-world-scatter";
pub const world_atmosphere = "ed-world-atmosphere";
pub const world_ocean = "ed-world-ocean";
pub const world_water = "ed-world-water";
pub const world_measure = "ed-world-measure";
pub const world_curve_delete_selected = "ed-world-curve-delete-selected";
pub const world_road_mode_draw = "ed-world-road-mode-draw";
pub const world_road_mode_select = "ed-world-road-mode-select";
pub const world_road_mode_shape = "ed-world-road-mode-shape";
pub const world_road_mode_join = "ed-world-road-mode-join";
pub const world_road_mode_surface = "ed-world-road-mode-surface";
pub const world_road_draw_point = "ed-world-road-point";
pub const world_road_draw_freehand = "ed-world-road-freehand";
pub const world_road_finish = "ed-world-tool-road-finish";
pub const world_road_clear = "ed-world-tool-road-clear";
pub const world_road_delete_selected = "ed-world-road-delete-selected";
pub const world_road_split_selected = "ed-world-road-split-selected";
pub const world_road_straighten = "ed-world-road-shape-straighten";
pub const world_road_soften = "ed-world-road-shape-soften";
pub const world_road_rebuild_selected = "ed-world-road-regenerate-selected";
pub const world_road_rebuild_all = "ed-world-road-regenerate-all";

pub const physics_none = "ed-physics-none";
pub const physics_static = "ed-physics-static";
pub const physics_dynamic = "ed-physics-dynamic";
pub const physics_kinematic = "ed-physics-kinematic";
pub const play_scene = "ed-play-scene";
pub const toggle_tool_inspector = "ed-toggle-tool-inspector";
pub const toggle_project_inspector = "ed-toggle-project-inspector";

pub const edit_vertex = "ed-edit-vertex";
pub const edit_edge = "ed-edit-edge";
pub const edit_face = "ed-edit-face";
pub const edit_extrude = "ed-edit-extrude";
pub const edit_inset = "ed-edit-inset";

pub const left_scene = "ed-left-scene";
pub const left_add = "ed-left-add";
pub const left_world = "ed-left-world";
pub const left_assets = "ed-left-assets";

pub const material_asset_light = "ed-material-asset-light";
pub const material_asset_slate = "ed-material-asset-slate";
pub const material_asset_red = "ed-material-asset-red";
pub const material_asset_green = "ed-material-asset-green";
pub const material_asset_blue = "ed-material-asset-blue";
pub const material_asset_gold = "ed-material-asset-gold";

pub const material_toolbar_light = "ed-material-toolbar-light";
pub const material_toolbar_slate = "ed-material-toolbar-slate";
pub const material_toolbar_red = "ed-material-toolbar-red";
pub const material_toolbar_green = "ed-material-toolbar-green";
pub const material_toolbar_blue = "ed-material-toolbar-blue";
pub const material_toolbar_gold = "ed-material-toolbar-gold";

pub fn mode(comptime tag: []const u8) []const u8 {
    if (comptime is(tag, "world_creation")) return mode_world_creation;
    if (comptime is(tag, "layout")) return mode_layout;
    if (comptime is(tag, "architecture_creation")) return mode_architecture_creation;
    if (comptime is(tag, "prop_creation")) return mode_prop_creation;
    if (comptime is(tag, "life")) return mode_life;
    @compileError("unknown editor mode command id");
}

pub fn objectTool(comptime tag: []const u8) []const u8 {
    if (comptime is(tag, "select")) return object_select;
    if (comptime is(tag, "move")) return object_move;
    if (comptime is(tag, "rotate")) return object_rotate;
    if (comptime is(tag, "scale")) return object_scale;
    @compileError("unknown object tool command id");
}

pub fn blockoutOp(comptime tag: []const u8) []const u8 {
    if (comptime is(tag, "add")) return blockout_add;
    if (comptime is(tag, "subtract")) return blockout_subtract;
    @compileError("unknown blockout op command id");
}

pub fn editTool(comptime tag: []const u8) []const u8 {
    if (comptime is(tag, "vertex")) return edit_vertex;
    if (comptime is(tag, "edge")) return edit_edge;
    if (comptime is(tag, "face")) return edit_face;
    if (comptime is(tag, "extrude")) return edit_extrude;
    if (comptime is(tag, "inset")) return edit_inset;
    @compileError("unknown edit tool command id");
}

pub fn architectureTool(comptime tag: []const u8) []const u8 {
    if (comptime is(tag, "network")) return architecture_network;
    if (comptime is(tag, "floorplan")) return architecture_floorplan;
    if (comptime is(tag, "shell")) return architecture_shell;
    if (comptime is(tag, "foundation")) return architecture_foundation;
    if (comptime is(tag, "cutout")) return architecture_cutout;
    if (comptime is(tag, "wall")) return architecture_wall;
    if (comptime is(tag, "opening")) return architecture_opening;
    if (comptime is(tag, "roof")) return architecture_roof;
    if (comptime is(tag, "door")) return architecture_door;
    if (comptime is(tag, "window")) return architecture_window;
    if (comptime is(tag, "curve")) return architecture_curve;
    if (comptime is(tag, "brush")) return architecture_brush;
    if (comptime is(tag, "add")) return architecture_add;
    if (comptime is(tag, "subtract")) return architecture_subtract;
    if (comptime is(tag, "ramp")) return architecture_ramp;
    if (comptime is(tag, "vertex")) return architecture_vertex;
    if (comptime is(tag, "edge")) return architecture_edge;
    if (comptime is(tag, "face")) return architecture_face;
    if (comptime is(tag, "extrude")) return architecture_extrude;
    if (comptime is(tag, "inset")) return architecture_inset;
    if (comptime is(tag, "material")) return architecture_material;
    @compileError("unknown architecture tool command id");
}

pub fn propTool(comptime tag: []const u8) []const u8 {
    if (comptime is(tag, "select")) return prop_select;
    if (comptime is(tag, "create")) return prop_create;
    if (comptime is(tag, "asset")) return prop_asset;
    if (comptime is(tag, "primitive")) return prop_primitive;
    if (comptime is(tag, "edit")) return prop_edit;
    if (comptime is(tag, "material")) return prop_material;
    if (comptime is(tag, "collider")) return prop_collider;
    if (comptime is(tag, "variants")) return prop_variants;
    @compileError("unknown prop tool command id");
}

pub fn lifeTool(comptime tag: []const u8) []const u8 {
    if (comptime is(tag, "select")) return life_select;
    if (comptime is(tag, "pose")) return life_pose;
    if (comptime is(tag, "keyframe")) return life_keyframe;
    if (comptime is(tag, "record")) return life_record;
    if (comptime is(tag, "playback")) return life_playback;
    if (comptime is(tag, "clips")) return life_clips;
    if (comptime is(tag, "bones")) return life_bones;
    if (comptime is(tag, "curves")) return life_curves;
    @compileError("unknown life tool command id");
}

pub fn worldTool(comptime tag: []const u8) []const u8 {
    if (comptime is(tag, "terrain")) return world_terrain;
    if (comptime is(tag, "paint")) return world_paint;
    if (comptime is(tag, "roads")) return world_roads;
    if (comptime is(tag, "scatter")) return world_scatter;
    if (comptime is(tag, "atmosphere")) return world_atmosphere;
    if (comptime is(tag, "ocean")) return world_ocean;
    if (comptime is(tag, "water")) return world_water;
    if (comptime is(tag, "measure")) return world_measure;
    @compileError("unknown world tool command id");
}

pub fn worldRoadMode(comptime tag: []const u8) []const u8 {
    if (comptime is(tag, "draw")) return world_road_mode_draw;
    if (comptime is(tag, "select")) return world_road_mode_select;
    if (comptime is(tag, "shape")) return world_road_mode_shape;
    if (comptime is(tag, "join")) return world_road_mode_join;
    if (comptime is(tag, "surface")) return world_road_mode_surface;
    @compileError("unknown world road mode command id");
}

pub fn worldRoadDrawMode(comptime tag: []const u8) []const u8 {
    if (comptime is(tag, "point_by_point")) return world_road_draw_point;
    if (comptime is(tag, "freehand")) return world_road_draw_freehand;
    @compileError("unknown world road draw mode command id");
}

pub fn worldRoadAction(comptime tag: []const u8) []const u8 {
    if (comptime is(tag, "finish")) return world_road_finish;
    if (comptime is(tag, "clear")) return world_road_clear;
    if (comptime is(tag, "delete_selected")) return world_road_delete_selected;
    if (comptime is(tag, "split_selected")) return world_road_split_selected;
    if (comptime is(tag, "straighten")) return world_road_straighten;
    if (comptime is(tag, "soften")) return world_road_soften;
    if (comptime is(tag, "rebuild_selected")) return world_road_rebuild_selected;
    if (comptime is(tag, "rebuild_all")) return world_road_rebuild_all;
    @compileError("unknown world road action command id");
}

pub fn leftTab(comptime tag: []const u8) []const u8 {
    if (comptime is(tag, "scene")) return left_scene;
    if (comptime is(tag, "add")) return left_add;
    if (comptime is(tag, "world")) return left_world;
    if (comptime is(tag, "assets")) return left_assets;
    @compileError("unknown left tab command id");
}

pub fn materialAsset(comptime tag: []const u8) []const u8 {
    if (comptime is(tag, "light")) return material_asset_light;
    if (comptime is(tag, "slate")) return material_asset_slate;
    if (comptime is(tag, "red")) return material_asset_red;
    if (comptime is(tag, "green")) return material_asset_green;
    if (comptime is(tag, "blue")) return material_asset_blue;
    if (comptime is(tag, "gold")) return material_asset_gold;
    @compileError("unknown material asset command id");
}

pub fn materialToolbar(comptime tag: []const u8) []const u8 {
    if (comptime is(tag, "light")) return material_toolbar_light;
    if (comptime is(tag, "slate")) return material_toolbar_slate;
    if (comptime is(tag, "red")) return material_toolbar_red;
    if (comptime is(tag, "green")) return material_toolbar_green;
    if (comptime is(tag, "blue")) return material_toolbar_blue;
    if (comptime is(tag, "gold")) return material_toolbar_gold;
    @compileError("unknown material toolbar command id");
}

fn is(comptime a: []const u8, comptime b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

test "editor command id generator keeps stable families" {
    const testing = @import("std").testing;
    try testing.expectEqualStrings("ed-mode-world-creation", mode("world_creation"));
    try testing.expectEqualStrings("ed-material-toolbar-red", materialToolbar("red"));
    try testing.expectEqualStrings("ed-life-keyframe", lifeTool("keyframe"));
    try testing.expectEqualStrings("ed-world-road-mode-shape", worldRoadMode("shape"));
    try testing.expectEqualStrings("ed-world-road-freehand", worldRoadDrawMode("freehand"));
    try testing.expectEqualStrings("ed-world-road-shape-soften", worldRoadAction("soften"));
}
