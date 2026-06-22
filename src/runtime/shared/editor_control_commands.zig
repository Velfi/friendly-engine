const std = @import("std");

pub const ExposureTier = enum {
    stable,
    experimental,
    destructive,
    internal,

    pub fn label(self: ExposureTier) []const u8 {
        return switch (self) {
            .stable => "stable",
            .experimental => "experimental",
            .destructive => "destructive",
            .internal => "internal",
        };
    }
};

pub const Owner = enum {
    project_manager,
    editor,
    selection,
    commands,
    world,
    terrain,
    view,
    camera,
    play,
    capture,
    concept_paint,
    architecture,
    prop,

    pub fn label(self: Owner) []const u8 {
        return switch (self) {
            .project_manager => "project_manager",
            .editor => "editor",
            .selection => "selection",
            .commands => "commands",
            .world => "world",
            .terrain => "terrain",
            .view => "view",
            .camera => "camera",
            .play => "play",
            .capture => "capture",
            .concept_paint => "concept_paint",
            .architecture => "architecture",
            .prop => "prop",
        };
    }
};

pub const ArgumentPolicy = enum {
    empty,
    fields,
    object_string,
    strict_json_object,
};

pub const FieldKind = enum {
    string,
    number,
    boolean,
    json,
};

pub const Field = struct {
    name: []const u8,
    kind: FieldKind,
};

pub const Entry = struct {
    command_name: []const u8,
    mcp_tool_name: []const u8,
    title: []const u8,
    description: []const u8,
    tier: ExposureTier,
    owner: Owner,
    argument_policy: ArgumentPolicy,
    input_schema: []const u8,
    fields: []const Field = &.{},

    pub fn exposedToMcp(self: Entry) bool {
        return self.tier != .internal;
    }
};

pub const empty_schema = "{\"type\":\"object\",\"additionalProperties\":false}";
pub const optional_object_schema = "{\"type\":\"object\",\"properties\":{\"object\":{\"type\":\"string\"}},\"additionalProperties\":false}";
pub const undo_batch_schema = "{\"type\":\"object\",\"properties\":{\"label\":{\"type\":\"string\",\"description\":\"Human readable label for the grouped LLM-authored action\"},\"object\":{\"type\":\"string\",\"description\":\"Optional fallback label\"}},\"additionalProperties\":false}";
pub const project_path_schema = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\",\"description\":\"Project folder path, absolute or relative to the Project Manager workspace\"}},\"required\":[\"path\"],\"additionalProperties\":false}";
pub const project_create_schema = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\",\"description\":\"Project folder path, absolute or relative to the Project Manager workspace\"},\"preset\":{\"type\":\"string\",\"description\":\"Optional gem preset name, such as Minimal, Full, or a custom preset\"}},\"required\":[\"path\"],\"additionalProperties\":false}";
pub const objects_list_schema = "{\"type\":\"object\",\"properties\":{\"offset\":{\"type\":\"integer\",\"minimum\":0,\"description\":\"Zero-based object index to start from\"},\"limit\":{\"type\":\"integer\",\"minimum\":1,\"description\":\"Maximum objects to return\"}},\"additionalProperties\":false}";
pub const terrain_footprint_list_schema = "{\"type\":\"object\",\"properties\":{\"offset\":{\"type\":\"integer\",\"minimum\":0,\"description\":\"Zero-based resident terrain cell index to start from\"},\"limit\":{\"type\":\"integer\",\"minimum\":1,\"description\":\"Maximum terrain cells to return\"}},\"additionalProperties\":false}";
pub const object_schema = "{\"type\":\"object\",\"properties\":{\"object\":{\"type\":\"string\"}},\"required\":[\"object\"],\"additionalProperties\":false}";
pub const object_parent_schema = "{\"type\":\"object\",\"properties\":{\"object\":{\"type\":\"string\"},\"parent\":{\"type\":\"string\"}},\"required\":[\"object\",\"parent\"],\"additionalProperties\":false}";
pub const property_bag_schema = "{\"type\":\"object\",\"minProperties\":1,\"additionalProperties\":{\"oneOf\":[{\"type\":\"string\"},{\"type\":\"number\"},{\"type\":\"boolean\"}]}}";
pub const object_properties_schema = "{\"type\":\"object\",\"properties\":{\"object\":{\"type\":\"string\"},\"properties\":" ++ property_bag_schema ++ "},\"required\":[\"object\",\"properties\"],\"additionalProperties\":false}";
pub const object_gameplay_schema = "{\"type\":\"object\",\"properties\":{\"object\":{\"type\":\"string\"},\"tag\":{\"type\":\"string\"},\"health\":{\"type\":\"number\"},\"score\":{\"type\":\"integer\"},\"team\":{\"type\":\"integer\"},\"interactable\":{\"type\":\"boolean\"}},\"required\":[\"object\",\"tag\"],\"additionalProperties\":false}";
pub const marker_create_schema = "{\"type\":\"object\",\"properties\":{\"kind\":{\"type\":\"string\",\"enum\":[\"player_start\",\"checkpoint\",\"spawn_point\",\"encounter_spawn\",\"item_spawn\",\"objective\",\"interactable_anchor\",\"trigger_volume\",\"camera_point\",\"audio_emitter\",\"nav_point\",\"patrol_point\",\"region_anchor\"]},\"object\":{\"type\":\"string\",\"description\":\"Optional editor object name\"},\"shape\":{\"type\":\"string\",\"enum\":[\"point\",\"box\",\"sphere\",\"path\"]},\"marker_id\":{\"type\":\"string\"},\"group\":{\"type\":\"string\"},\"binding\":{\"type\":\"string\"},\"radius\":{\"type\":\"number\",\"minimum\":0.001},\"order\":{\"type\":\"integer\"},\"point_x\":{\"type\":\"number\"},\"point_y\":{\"type\":\"number\"},\"point_z\":{\"type\":\"number\"}},\"required\":[\"kind\"],\"additionalProperties\":false}";
pub const marker_update_schema = "{\"type\":\"object\",\"properties\":{\"object\":{\"type\":\"string\",\"description\":\"Object id or name of the marker to update\"},\"kind\":{\"type\":\"string\",\"enum\":[\"player_start\",\"checkpoint\",\"spawn_point\",\"encounter_spawn\",\"item_spawn\",\"objective\",\"interactable_anchor\",\"trigger_volume\",\"camera_point\",\"audio_emitter\",\"nav_point\",\"patrol_point\",\"region_anchor\"]},\"shape\":{\"type\":\"string\",\"enum\":[\"point\",\"box\",\"sphere\",\"path\"]},\"marker_id\":{\"type\":\"string\"},\"group\":{\"type\":\"string\"},\"binding\":{\"type\":\"string\"},\"radius\":{\"type\":\"number\",\"minimum\":0.001},\"order\":{\"type\":\"integer\"},\"point_x\":{\"type\":\"number\"},\"point_y\":{\"type\":\"number\"},\"point_z\":{\"type\":\"number\"}},\"required\":[\"object\"],\"additionalProperties\":false}";
pub const plot_create_schema = "{\"type\":\"object\",\"properties\":{\"object\":{\"type\":\"string\",\"description\":\"Descriptive plot name shown in the editor\"},\"properties\":" ++ property_bag_schema ++ ",\"point_x\":{\"type\":\"number\"},\"point_y\":{\"type\":\"number\",\"description\":\"Vertical offset above sampled terrain, in meters\"},\"point_z\":{\"type\":\"number\"},\"width\":{\"type\":\"number\",\"minimum\":0.001},\"depth\":{\"type\":\"number\",\"minimum\":0.001}},\"required\":[\"object\",\"properties\",\"point_x\",\"point_z\",\"width\",\"depth\"],\"additionalProperties\":false}";
pub const plot_align_schema = "{\"type\":\"object\",\"properties\":{\"object\":{\"type\":\"string\",\"description\":\"Optional plot name or id. Omit to align every plot root.\"},\"point_y\":{\"type\":\"number\",\"description\":\"Vertical offset above sampled terrain, in meters\"}},\"additionalProperties\":false}";
pub const prop_source_sphere_schema = "{\"type\":\"object\",\"properties\":{\"source_id\":{\"type\":\"string\"},\"position\":{\"type\":\"array\",\"items\":{\"type\":\"number\"},\"minItems\":3,\"maxItems\":3},\"rotation\":{\"type\":\"array\",\"items\":{\"type\":\"number\"},\"minItems\":4,\"maxItems\":4},\"scale\":{\"type\":\"array\",\"items\":{\"type\":\"number\"},\"minItems\":3,\"maxItems\":3},\"radius\":{\"type\":\"number\"},\"segments\":{\"type\":\"integer\",\"minimum\":4},\"rings\":{\"type\":\"integer\",\"minimum\":4}},\"required\":[\"source_id\",\"position\",\"rotation\",\"scale\",\"radius\",\"segments\",\"rings\"],\"additionalProperties\":false}";
pub const prop_source_transform_schema = "{\"type\":\"object\",\"properties\":{\"source_id\":{\"type\":\"string\"},\"position\":{\"type\":\"array\",\"items\":{\"type\":\"number\"},\"minItems\":3,\"maxItems\":3},\"rotation\":{\"type\":\"array\",\"items\":{\"type\":\"number\"},\"minItems\":4,\"maxItems\":4},\"scale\":{\"type\":\"array\",\"items\":{\"type\":\"number\"},\"minItems\":3,\"maxItems\":3}},\"required\":[\"source_id\"],\"additionalProperties\":false}";
pub const prop_source_delete_schema = "{\"type\":\"object\",\"properties\":{\"source_id\":{\"type\":\"string\"}},\"required\":[\"source_id\"],\"additionalProperties\":false}";
pub const prop_modifier_axis_schema = "{\"type\":\"object\",\"properties\":{\"modifier_id\":{\"type\":\"string\"},\"source_id\":{\"type\":\"string\"},\"axis\":{\"type\":\"string\",\"enum\":[\"x\",\"y\",\"z\"]},\"amount\":{\"type\":\"number\"}},\"required\":[\"modifier_id\",\"source_id\",\"axis\",\"amount\"],\"additionalProperties\":false}";
pub const prop_modifier_lattice_schema = "{\"type\":\"object\",\"properties\":{\"modifier_id\":{\"type\":\"string\"},\"source_id\":{\"type\":\"string\"},\"dimensions\":{\"type\":\"array\",\"items\":{\"type\":\"integer\"},\"minItems\":3,\"maxItems\":3},\"points\":{\"type\":\"array\",\"items\":{\"type\":\"object\",\"properties\":{\"index\":{\"type\":\"array\",\"items\":{\"type\":\"integer\"},\"minItems\":3,\"maxItems\":3},\"offset\":{\"type\":\"array\",\"items\":{\"type\":\"number\"},\"minItems\":3,\"maxItems\":3}},\"required\":[\"index\",\"offset\"],\"additionalProperties\":false}}},\"required\":[\"modifier_id\",\"source_id\",\"dimensions\",\"points\"],\"additionalProperties\":false}";
pub const prop_modifier_update_schema = "{\"type\":\"object\",\"properties\":{\"modifier_id\":{\"type\":\"string\"},\"source_id\":{\"type\":\"string\"},\"kind\":{\"type\":\"string\",\"enum\":[\"bend\",\"taper\",\"lattice\"]},\"axis\":{\"type\":\"string\",\"enum\":[\"x\",\"y\",\"z\"]},\"amount\":{\"type\":\"number\"},\"dimensions\":{\"type\":\"array\",\"items\":{\"type\":\"integer\"},\"minItems\":3,\"maxItems\":3},\"points\":{\"type\":\"array\",\"items\":{\"type\":\"object\",\"properties\":{\"index\":{\"type\":\"array\",\"items\":{\"type\":\"integer\"},\"minItems\":3,\"maxItems\":3},\"offset\":{\"type\":\"array\",\"items\":{\"type\":\"number\"},\"minItems\":3,\"maxItems\":3}},\"required\":[\"index\",\"offset\"],\"additionalProperties\":false}}},\"required\":[\"modifier_id\",\"source_id\",\"kind\"],\"additionalProperties\":false}";
pub const prop_modifier_delete_schema = "{\"type\":\"object\",\"properties\":{\"modifier_id\":{\"type\":\"string\"}},\"required\":[\"modifier_id\"],\"additionalProperties\":false}";
pub const prop_primitive_seed_schema = "{\"type\":\"object\",\"properties\":{\"primitive\":{\"type\":\"string\",\"enum\":[\"box\",\"plane\",\"cylinder\",\"sphere\"]},\"width\":{\"type\":\"number\",\"minimum\":0.001},\"height\":{\"type\":\"number\",\"minimum\":0.001},\"depth\":{\"type\":\"number\",\"minimum\":0.001},\"radius\":{\"type\":\"number\",\"minimum\":0.001},\"segments\":{\"type\":\"integer\",\"minimum\":3}},\"required\":[\"primitive\"],\"additionalProperties\":false}";
pub const prop_sketch_point_update_schema = "{\"type\":\"object\",\"properties\":{\"vertex\":{\"type\":\"integer\",\"minimum\":0,\"description\":\"Zero-based source point index\"},\"point_x\":{\"type\":\"number\"},\"point_y\":{\"type\":\"number\"},\"point_z\":{\"type\":\"number\"}},\"required\":[\"vertex\"],\"additionalProperties\":false}";
pub const prop_sketch_operation_schema = "{\"type\":\"object\",\"properties\":{\"amount\":{\"type\":\"number\",\"minimum\":0.001},\"segments\":{\"type\":\"integer\",\"minimum\":3,\"maximum\":128}},\"additionalProperties\":false}";
pub const prop_material_object_schema = "{\"type\":\"object\",\"properties\":{\"material_path\":{\"type\":\"string\"},\"r\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":255},\"g\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":255},\"b\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":255},\"a\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":255},\"scale_world\":{\"type\":\"number\"},\"rotation_deg\":{\"type\":\"number\"},\"offset_u\":{\"type\":\"number\"},\"offset_v\":{\"type\":\"number\"}},\"required\":[\"material_path\"],\"additionalProperties\":false}";
pub const prop_material_face_schema = "{\"type\":\"object\",\"properties\":{\"face_index\":{\"type\":\"integer\",\"minimum\":0},\"material_path\":{\"type\":\"string\"},\"r\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":255},\"g\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":255},\"b\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":255},\"a\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":255},\"scale_world\":{\"type\":\"number\"},\"rotation_deg\":{\"type\":\"number\"},\"offset_u\":{\"type\":\"number\"},\"offset_v\":{\"type\":\"number\"}},\"required\":[\"face_index\",\"material_path\"],\"additionalProperties\":false}";
pub const prop_texture_fill_schema = "{\"type\":\"object\",\"properties\":{\"r\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":255},\"g\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":255},\"b\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":255},\"a\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":255}},\"required\":[\"r\",\"g\",\"b\"],\"additionalProperties\":false}";
pub const prop_texture_quality_schema = "{\"type\":\"object\",\"properties\":{\"object\":{\"type\":\"string\",\"enum\":[\"1x\",\"2x\",\"4x\"]}},\"required\":[\"object\"],\"additionalProperties\":false}";
pub const prop_texture_paint_uv_schema = "{\"type\":\"object\",\"properties\":{\"u\":{\"type\":\"number\",\"minimum\":0,\"maximum\":1},\"v\":{\"type\":\"number\",\"minimum\":0,\"maximum\":1},\"r\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":255},\"g\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":255},\"b\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":255},\"a\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":255},\"radius\":{\"type\":\"number\",\"minimum\":0.001,\"maximum\":1},\"opacity\":{\"type\":\"number\",\"minimum\":0,\"maximum\":1},\"hardness\":{\"type\":\"number\",\"minimum\":0.01,\"maximum\":1}},\"required\":[\"u\",\"v\",\"r\",\"g\",\"b\"],\"additionalProperties\":false}";
pub const concept_paint_capture_schema = "{\"type\":\"object\",\"properties\":{\"screenshot_path\":{\"type\":\"string\",\"description\":\"PNG/JPEG viewport screenshot path produced by screenshot_viewport, absolute or relative to the project\"},\"prompt\":{\"type\":\"string\"},\"provider\":{\"type\":\"string\"},\"desired_style\":{\"type\":\"string\"},\"output_path\":{\"type\":\"string\",\"description\":\"Where an external provider should write the styled PNG/JPEG\"},\"opacity\":{\"type\":\"number\",\"minimum\":0,\"maximum\":1},\"blend_mode\":{\"type\":\"string\",\"enum\":[\"normal\",\"multiply\"]}},\"required\":[\"screenshot_path\"],\"additionalProperties\":false}";
pub const concept_paint_import_schema = "{\"type\":\"object\",\"properties\":{\"styled_path\":{\"type\":\"string\",\"description\":\"PNG/JPEG styled concept image path, absolute or relative to the project\"}},\"required\":[\"styled_path\"],\"additionalProperties\":false}";
pub const command_schema = "{\"type\":\"object\",\"properties\":{\"command\":{\"type\":\"string\"}},\"required\":[\"command\"],\"additionalProperties\":false}";
pub const selection_scope_schema = "{\"type\":\"object\",\"properties\":{\"scope\":{\"type\":\"string\",\"enum\":[\"object\",\"face\",\"edge\",\"point\",\"source\",\"operation\",\"marker\"]}},\"required\":[\"scope\"],\"additionalProperties\":false}";
pub const selection_pick_schema = "{\"type\":\"object\",\"properties\":{\"screen_x\":{\"type\":\"number\",\"description\":\"Viewport-local X coordinate in pixels\"},\"screen_y\":{\"type\":\"number\",\"description\":\"Viewport-local Y coordinate in pixels\"}},\"required\":[\"screen_x\",\"screen_y\"],\"additionalProperties\":false}";
pub const selection_box_schema = "{\"type\":\"object\",\"properties\":{\"screen_x\":{\"type\":\"number\",\"description\":\"Viewport-local drag start X coordinate in pixels\"},\"screen_y\":{\"type\":\"number\",\"description\":\"Viewport-local drag start Y coordinate in pixels\"},\"end_x\":{\"type\":\"number\",\"description\":\"Viewport-local drag end X coordinate in pixels\"},\"end_y\":{\"type\":\"number\",\"description\":\"Viewport-local drag end Y coordinate in pixels\"}},\"required\":[\"screen_x\",\"screen_y\",\"end_x\",\"end_y\"],\"additionalProperties\":false}";
pub const selection_pick_world_schema = "{\"type\":\"object\",\"properties\":{\"point_x\":{\"type\":\"number\"},\"point_y\":{\"type\":\"number\"},\"point_z\":{\"type\":\"number\"}},\"required\":[\"point_x\",\"point_y\",\"point_z\"],\"additionalProperties\":false}";
pub const scene_new_schema = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\",\"description\":\"Scene path relative to the open project, such as scenes/architecture.kdl\"}},\"additionalProperties\":false}";
pub const startup_scene_schema = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\",\"description\":\"Project scene path to boot when Play is clicked, such as scenes/main.kdl\"}},\"required\":[\"path\"],\"additionalProperties\":false}";
pub const player_start_schema = "{\"type\":\"object\",\"properties\":{\"object\":{\"type\":\"string\",\"description\":\"Player start object name\"},\"point_x\":{\"type\":\"number\"},\"point_y\":{\"type\":\"number\"},\"point_z\":{\"type\":\"number\"},\"yaw\":{\"type\":\"number\"},\"pitch\":{\"type\":\"number\"}},\"required\":[\"point_x\",\"point_z\"],\"additionalProperties\":false}";
pub const terrain_point_schema = "{\"type\":\"object\",\"properties\":{\"point_x\":{\"type\":\"number\"},\"point_y\":{\"type\":\"number\"},\"point_z\":{\"type\":\"number\"}},\"required\":[\"point_x\",\"point_z\"],\"additionalProperties\":false}";
pub const terrain_geology_start_schema = "{\"type\":\"object\",\"properties\":{\"min_x\":{\"type\":\"integer\",\"description\":\"Minimum cell X coordinate, inclusive\"},\"max_x\":{\"type\":\"integer\",\"description\":\"Maximum cell X coordinate, inclusive\"},\"min_z\":{\"type\":\"integer\",\"description\":\"Minimum cell Z coordinate, inclusive\"},\"max_z\":{\"type\":\"integer\",\"description\":\"Maximum cell Z coordinate, inclusive\"},\"cell_size_m\":{\"type\":\"number\",\"minimum\":1},\"batch_size\":{\"type\":\"integer\",\"const\":1,\"description\":\"Terrain batch jobs stream one generated cell per editor tick\"},\"seed\":{\"type\":\"integer\",\"minimum\":0},\"properties\":{\"type\":\"object\",\"additionalProperties\":true,\"description\":\"Geological formation recipe. Use formations: [{kind: base|slope|ridge|basin|valley|shelf|noise, ...numeric fields...}]\"}},\"required\":[\"min_x\",\"max_x\",\"min_z\",\"max_z\",\"cell_size_m\",\"batch_size\",\"properties\"],\"additionalProperties\":false}";
pub const terrain_recipe_schema = "{\"type\":\"object\",\"properties\":{\"operation\":{\"type\":\"string\",\"enum\":[\"replace_heights_keep_cells\"]},\"min_x\":{\"type\":\"integer\"},\"max_x\":{\"type\":\"integer\"},\"min_z\":{\"type\":\"integer\"},\"max_z\":{\"type\":\"integer\"},\"cell_size_m\":{\"type\":\"number\",\"minimum\":1},\"seed\":{\"type\":\"integer\",\"minimum\":0},\"sea_level\":{\"type\":\"number\",\"description\":\"Sea level in meters\"},\"ocean_floor\":{\"type\":\"number\",\"description\":\"Ocean floor height in meters\"},\"features\":{\"type\":\"array\",\"maxItems\":128,\"items\":{\"type\":\"object\",\"additionalProperties\":true}},\"materials\":{\"type\":\"array\",\"items\":{\"type\":\"object\",\"additionalProperties\":true}},\"roads\":{\"type\":\"array\",\"items\":{\"type\":\"object\",\"additionalProperties\":true}}},\"required\":[\"operation\",\"min_x\",\"max_x\",\"min_z\",\"max_z\",\"cell_size_m\",\"features\"],\"additionalProperties\":false}";
pub const world_region_upsert_schema = "{\"type\":\"object\",\"properties\":{\"object\":{\"type\":\"string\",\"description\":\"Stable region id\"},\"parent\":{\"type\":\"string\",\"description\":\"Human readable region name\"},\"properties\":{\"type\":\"object\",\"additionalProperties\":true,\"description\":\"Region prop bag persisted as key=value metadata\"},\"cells\":{\"type\":\"string\",\"description\":\"Semicolon-separated cell coordinates, e.g. 0,0,0;1,0,0;1,1,0\"}},\"required\":[\"object\",\"cells\"],\"additionalProperties\":false}";
pub const world_region_paint_schema = "{\"type\":\"object\",\"properties\":{\"object\":{\"type\":\"string\",\"description\":\"Stable region id\"},\"parent\":{\"type\":\"string\",\"description\":\"Human readable region name\"},\"operation\":{\"type\":\"string\",\"enum\":[\"assign\",\"erase\"]},\"point_x\":{\"type\":\"number\"},\"point_y\":{\"type\":\"number\"},\"point_z\":{\"type\":\"number\"},\"radius\":{\"type\":\"number\",\"minimum\":0}},\"required\":[\"object\",\"point_x\",\"point_y\",\"point_z\"],\"additionalProperties\":false}";
pub const world_region_delete_schema = "{\"type\":\"object\",\"properties\":{\"object\":{\"type\":\"string\",\"description\":\"Stable region id to delete\"}},\"required\":[\"object\"],\"additionalProperties\":false}";
pub const ocean_clip_update_schema = "{\"type\":\"object\",\"properties\":{\"points\":{\"type\":\"string\",\"description\":\"Semicolon-separated X,Z ocean exclusion polygon points, e.g. 0,0;100,0;100,100;0,100. Use an empty string to clear the exclusion and render ocean everywhere.\"}},\"required\":[\"points\"],\"additionalProperties\":false}";
pub const ocean_clip_point_schema = "{\"type\":\"object\",\"properties\":{\"point_x\":{\"type\":\"number\"},\"point_z\":{\"type\":\"number\"}},\"required\":[\"point_x\",\"point_z\"],\"additionalProperties\":false}";
pub const water_volume_schema = "{\"type\":\"object\",\"properties\":{\"object\":{\"type\":\"string\",\"description\":\"Stable water volume id\"},\"kind\":{\"type\":\"string\",\"enum\":[\"ocean_near\",\"lake\",\"pond\",\"river\",\"interior\"]},\"material\":{\"type\":\"string\"},\"points\":{\"type\":\"string\",\"description\":\"Semicolon-separated X,Z polygon points, e.g. 0,0;32,0;32,32;0,32\"},\"surface_y\":{\"type\":\"number\"},\"bottom_y\":{\"type\":\"number\"},\"swimmable\":{\"type\":\"boolean\"},\"linked_to_ocean\":{\"type\":\"boolean\"},\"current_x\":{\"type\":\"number\"},\"current_y\":{\"type\":\"number\"},\"current_z\":{\"type\":\"number\"}},\"required\":[\"object\"],\"additionalProperties\":false}";
pub const water_query_schema = "{\"type\":\"object\",\"properties\":{\"point_x\":{\"type\":\"number\"},\"point_y\":{\"type\":\"number\"},\"point_z\":{\"type\":\"number\"}},\"required\":[\"point_x\",\"point_y\",\"point_z\"],\"additionalProperties\":false}";
pub const terrain_sculpt_schema = "{\"type\":\"object\",\"properties\":{\"point_x\":{\"type\":\"number\"},\"point_y\":{\"type\":\"number\"},\"point_z\":{\"type\":\"number\"},\"operation\":{\"type\":\"string\",\"enum\":[\"raise\",\"lower\",\"smooth\"]},\"radius\":{\"type\":\"number\",\"minimum\":0.001},\"opacity\":{\"type\":\"number\",\"minimum\":0,\"maximum\":1},\"hardness\":{\"type\":\"number\",\"minimum\":0.05,\"maximum\":1}},\"required\":[\"point_x\",\"point_z\",\"operation\"],\"additionalProperties\":false}";
pub const terrain_material_paint_schema = "{\"type\":\"object\",\"properties\":{\"object\":{\"type\":\"string\",\"enum\":[\"grass\",\"dirt\",\"stone\",\"rock\",\"gravel\",\"road\",\"abyss\",\"shelf\",\"beach\",\"ash\",\"chalk\",\"rust\",\"marsh\"],\"description\":\"Terrain material layer to paint\"},\"point_x\":{\"type\":\"number\"},\"point_y\":{\"type\":\"number\"},\"point_z\":{\"type\":\"number\"},\"radius\":{\"type\":\"number\",\"minimum\":0.001},\"opacity\":{\"type\":\"number\",\"minimum\":0,\"maximum\":1},\"hardness\":{\"type\":\"number\",\"minimum\":0.05,\"maximum\":1}},\"required\":[\"object\",\"point_x\",\"point_z\"],\"additionalProperties\":false}";
pub const terrain_edge_cliff_schema = "{\"type\":\"object\",\"properties\":{\"height\":{\"type\":\"number\",\"description\":\"Bottom height at the world edge, in meters\"},\"width\":{\"type\":\"number\",\"minimum\":0.001,\"description\":\"Inward cliff rim width, in meters\"}},\"required\":[\"height\",\"width\"],\"additionalProperties\":false}";
pub const terrain_stretch_smooth_schema = "{\"type\":\"object\",\"properties\":{\"threshold\":{\"type\":\"number\",\"minimum\":0.001,\"description\":\"Minimum local height delta in meters before a sample is considered stretched\"},\"strength\":{\"type\":\"number\",\"minimum\":0.001,\"maximum\":1,\"description\":\"Blend amount toward neighbor average for selected samples\"},\"iterations\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":16},\"max_samples_per_cell\":{\"type\":\"integer\",\"minimum\":1,\"description\":\"Only the worst N samples per cell are smoothed each iteration\"},\"min_height\":{\"type\":\"number\",\"description\":\"Optional lower height bound for smoothing candidates\"},\"max_height\":{\"type\":\"number\",\"description\":\"Optional upper height bound for smoothing candidates\"}},\"additionalProperties\":false}";
pub const terrain_heightmap_schema = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\",\"description\":\"PNG heightmap path, absolute or relative to the open project\"},\"point_x\":{\"type\":\"number\"},\"point_y\":{\"type\":\"number\"},\"point_z\":{\"type\":\"number\"},\"min_height\":{\"type\":\"number\"},\"max_height\":{\"type\":\"number\"},\"material_path\":{\"type\":\"string\"}},\"required\":[\"path\",\"point_x\",\"point_z\"],\"additionalProperties\":false}";
pub const terrain_heightmap_batch_schema = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\",\"description\":\"PNG heightmap path, absolute or relative to the open project\"},\"albedo_path\":{\"type\":\"string\",\"description\":\"Optional PNG albedo/color map path sampled across the same cell range for terrain paint layers\"},\"min_x\":{\"type\":\"integer\",\"description\":\"Minimum cell X coordinate, inclusive\"},\"max_x\":{\"type\":\"integer\",\"description\":\"Maximum cell X coordinate, inclusive\"},\"min_z\":{\"type\":\"integer\",\"description\":\"Minimum cell Z coordinate, inclusive\"},\"max_z\":{\"type\":\"integer\",\"description\":\"Maximum cell Z coordinate, inclusive\"},\"cell_size_m\":{\"type\":\"number\",\"minimum\":1},\"min_height\":{\"type\":\"number\"},\"max_height\":{\"type\":\"number\"},\"material_path\":{\"type\":\"string\"}},\"required\":[\"path\",\"min_x\",\"max_x\",\"min_z\",\"max_z\",\"cell_size_m\",\"min_height\",\"max_height\"],\"additionalProperties\":false}";
pub const terrain_heightmap_export_schema = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\",\"description\":\"Output PNG path, absolute or relative to the open project\"},\"min_height\":{\"type\":\"number\",\"description\":\"Optional normalization lower bound in meters\"},\"max_height\":{\"type\":\"number\",\"description\":\"Optional normalization upper bound in meters\"}},\"additionalProperties\":false}";
pub const view_schema = "{\"type\":\"object\",\"properties\":{\"view\":{\"type\":\"string\",\"enum\":[\"perspective\",\"orthographic\"]},\"orientation\":{\"type\":\"string\",\"enum\":[\"free\",\"top\",\"front\",\"side\"]}},\"additionalProperties\":false}";
pub const camera_schema = "{\"type\":\"object\",\"properties\":{\"target_x\":{\"type\":\"number\"},\"target_y\":{\"type\":\"number\"},\"target_z\":{\"type\":\"number\"},\"yaw\":{\"type\":\"number\"},\"pitch\":{\"type\":\"number\"},\"distance\":{\"type\":\"number\"}},\"additionalProperties\":false}";
pub const show_me_schema = "{\"type\":\"object\",\"properties\":{\"enabled\":{\"type\":\"boolean\"},\"point_x\":{\"type\":\"number\"},\"point_y\":{\"type\":\"number\"},\"point_z\":{\"type\":\"number\"},\"radius\":{\"type\":\"number\",\"minimum\":0.001},\"distance\":{\"type\":\"number\",\"minimum\":0.001}},\"required\":[\"enabled\"],\"additionalProperties\":false}";
pub const camera_random_schema = "{\"type\":\"object\",\"properties\":{\"seed\":{\"type\":\"integer\",\"minimum\":0}},\"additionalProperties\":false}";
pub const play_scene_schema = "{\"type\":\"object\",\"properties\":{\"frames\":{\"type\":\"integer\",\"minimum\":1}},\"additionalProperties\":false}";
pub const turntable_capture_schema = "{\"type\":\"object\",\"properties\":{\"object\":{\"type\":\"string\"},\"frames\":{\"type\":\"integer\",\"minimum\":2,\"maximum\":180},\"fps\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":120},\"format\":{\"type\":\"string\",\"enum\":[\"mp4\",\"gif\"]}},\"additionalProperties\":false}";
pub const architecture_building_schema = "{\"type\":\"object\",\"properties\":{\"object\":{\"type\":\"string\",\"description\":\"Descriptive building object name shown in the editor\"},\"parent\":{\"type\":\"string\",\"description\":\"Plot root object id or name\"},\"properties\":" ++ property_bag_schema ++ ",\"point_x\":{\"type\":\"number\",\"description\":\"Local X offset within the plot\"},\"point_y\":{\"type\":\"number\",\"description\":\"Local Y offset within the plot\"},\"point_z\":{\"type\":\"number\",\"description\":\"Local Z offset within the plot\"},\"width\":{\"type\":\"number\",\"minimum\":0.001},\"depth\":{\"type\":\"number\",\"minimum\":0.001},\"height\":{\"type\":\"number\",\"minimum\":0.001,\"description\":\"Floor height in meters\"},\"thickness\":{\"type\":\"number\",\"minimum\":0.001,\"description\":\"Wall thickness in meters\"},\"floors\":{\"type\":\"integer\",\"minimum\":1},\"roof\":{\"type\":\"string\",\"enum\":[\"flat\",\"shed\",\"gable\",\"conical\"]}},\"required\":[\"object\",\"parent\",\"properties\",\"point_x\",\"point_z\",\"width\",\"depth\",\"height\",\"thickness\",\"floors\",\"roof\"],\"additionalProperties\":false}";
pub const wall_point_schema = "{\"type\":\"object\",\"properties\":{\"point_x\":{\"type\":\"number\"},\"point_y\":{\"type\":\"number\"},\"point_z\":{\"type\":\"number\"}},\"required\":[\"point_x\",\"point_z\"],\"additionalProperties\":false}";
pub const opening_schema = "{\"type\":\"object\",\"properties\":{\"point_x\":{\"type\":\"number\"},\"point_y\":{\"type\":\"number\"},\"point_z\":{\"type\":\"number\"},\"end_x\":{\"type\":\"number\"},\"end_y\":{\"type\":\"number\"},\"end_z\":{\"type\":\"number\"}},\"required\":[\"point_x\",\"point_z\",\"end_x\",\"end_z\"],\"additionalProperties\":false}";
pub const architecture_network_schema = "{\"type\":\"object\",\"properties\":{\"object\":{\"type\":\"string\"},\"parent\":{\"type\":\"string\"},\"properties\":" ++ property_bag_schema ++ ",\"point_x\":{\"type\":\"number\"},\"point_y\":{\"type\":\"number\"},\"point_z\":{\"type\":\"number\"},\"height\":{\"type\":\"number\",\"minimum\":0.001},\"thickness\":{\"type\":\"number\",\"minimum\":0.001},\"floors\":{\"type\":\"integer\",\"minimum\":1}},\"required\":[\"object\",\"parent\",\"properties\",\"point_x\",\"point_z\"],\"additionalProperties\":false}";
pub const architecture_object_schema = "{\"type\":\"object\",\"properties\":{\"object\":{\"type\":\"string\"}},\"required\":[\"object\"],\"additionalProperties\":false}";
pub const architecture_node_schema = "{\"type\":\"object\",\"properties\":{\"object\":{\"type\":\"string\"},\"vertex\":{\"type\":\"integer\",\"minimum\":0},\"point_x\":{\"type\":\"number\"},\"point_z\":{\"type\":\"number\"}},\"required\":[\"object\",\"point_x\",\"point_z\"],\"additionalProperties\":false}";
pub const architecture_node_delete_schema = "{\"type\":\"object\",\"properties\":{\"object\":{\"type\":\"string\"},\"vertex\":{\"type\":\"integer\",\"minimum\":0}},\"required\":[\"object\",\"vertex\"],\"additionalProperties\":false}";
pub const architecture_edge_schema = "{\"type\":\"object\",\"properties\":{\"object\":{\"type\":\"string\"},\"edge_a\":{\"type\":\"integer\",\"minimum\":0},\"edge_b\":{\"type\":\"integer\",\"minimum\":0},\"height\":{\"type\":\"number\",\"minimum\":0.001},\"thickness\":{\"type\":\"number\",\"minimum\":0.001},\"operation\":{\"type\":\"string\",\"enum\":[\"explicit\",\"to_floor\"]},\"floors\":{\"type\":\"integer\",\"minimum\":1}},\"required\":[\"object\",\"edge_a\",\"edge_b\"],\"additionalProperties\":false}";
pub const architecture_edge_id_schema = "{\"type\":\"object\",\"properties\":{\"object\":{\"type\":\"string\"},\"edge_a\":{\"type\":\"integer\",\"minimum\":0}},\"required\":[\"object\",\"edge_a\"],\"additionalProperties\":false}";
pub const architecture_edge_split_schema = "{\"type\":\"object\",\"properties\":{\"object\":{\"type\":\"string\"},\"edge_a\":{\"type\":\"integer\",\"minimum\":0},\"point_x\":{\"type\":\"number\"},\"point_z\":{\"type\":\"number\"}},\"required\":[\"object\",\"edge_a\",\"point_x\",\"point_z\"],\"additionalProperties\":false}";
pub const architecture_shell_schema = "{\"type\":\"object\",\"properties\":{\"object\":{\"type\":\"string\"},\"path\":{\"type\":\"string\",\"description\":\"Comma-separated wall ids in shell order\"}},\"required\":[\"object\",\"path\"],\"additionalProperties\":false}";
pub const architecture_id_schema = "{\"type\":\"object\",\"properties\":{\"object\":{\"type\":\"string\"},\"edge_a\":{\"type\":\"integer\",\"minimum\":0}},\"required\":[\"object\",\"edge_a\"],\"additionalProperties\":false}";
pub const architecture_wall_height_schema = "{\"type\":\"object\",\"properties\":{\"object\":{\"type\":\"string\"},\"edge_a\":{\"type\":\"integer\",\"minimum\":0},\"height\":{\"type\":\"number\",\"minimum\":0.001},\"operation\":{\"type\":\"string\",\"enum\":[\"explicit\",\"to_floor\"]},\"floors\":{\"type\":\"integer\",\"minimum\":1}},\"required\":[\"object\",\"edge_a\",\"operation\"],\"additionalProperties\":false}";
pub const architecture_floor_schema = "{\"type\":\"object\",\"properties\":{\"object\":{\"type\":\"string\"},\"height\":{\"type\":\"number\",\"minimum\":0.001},\"thickness\":{\"type\":\"number\",\"minimum\":0.001},\"floors\":{\"type\":\"integer\",\"minimum\":1}},\"required\":[\"object\",\"height\",\"thickness\",\"floors\"],\"additionalProperties\":false}";
pub const architecture_foundation_schema = "{\"type\":\"object\",\"properties\":{\"object\":{\"type\":\"string\"},\"edge_a\":{\"type\":\"integer\",\"minimum\":0},\"point_x\":{\"type\":\"number\"},\"point_z\":{\"type\":\"number\"},\"end_x\":{\"type\":\"number\"},\"end_z\":{\"type\":\"number\"},\"height\":{\"type\":\"number\"},\"thickness\":{\"type\":\"number\",\"minimum\":0.001},\"radius\":{\"type\":\"number\",\"minimum\":0.001}},\"required\":[\"object\",\"point_x\",\"point_z\",\"end_x\",\"end_z\"],\"additionalProperties\":false}";
pub const architecture_cutout_schema = "{\"type\":\"object\",\"properties\":{\"object\":{\"type\":\"string\"},\"edge_a\":{\"type\":\"integer\",\"minimum\":0},\"point_x\":{\"type\":\"number\"},\"point_y\":{\"type\":\"number\"},\"point_z\":{\"type\":\"number\"},\"end_x\":{\"type\":\"number\"},\"end_y\":{\"type\":\"number\"},\"end_z\":{\"type\":\"number\"}},\"required\":[\"object\",\"point_x\",\"point_z\",\"end_x\",\"end_z\"],\"additionalProperties\":false}";
pub const architecture_roof_schema = "{\"type\":\"object\",\"properties\":{\"object\":{\"type\":\"string\"},\"roof\":{\"type\":\"string\",\"enum\":[\"flat\",\"shed\",\"gable\",\"conical\"]},\"height\":{\"type\":\"number\"},\"thickness\":{\"type\":\"number\"}},\"required\":[\"object\",\"roof\"],\"additionalProperties\":false}";
pub const architecture_opening_schema = "{\"type\":\"object\",\"properties\":{\"object\":{\"type\":\"string\"},\"edge_a\":{\"type\":\"integer\",\"minimum\":0},\"operation\":{\"type\":\"string\",\"enum\":[\"door\",\"window\",\"arch\",\"cutout\"]},\"u\":{\"type\":\"number\",\"minimum\":0,\"maximum\":1},\"width\":{\"type\":\"number\",\"minimum\":0.001},\"height\":{\"type\":\"number\",\"minimum\":0.001},\"point_y\":{\"type\":\"number\"}},\"required\":[\"object\",\"edge_a\",\"operation\",\"u\",\"width\",\"height\"],\"additionalProperties\":false}";
pub const road_node_schema = "{\"type\":\"object\",\"properties\":{\"object\":{\"type\":\"string\",\"description\":\"Road node id\"},\"point_x\":{\"type\":\"number\"},\"point_y\":{\"type\":\"number\"},\"point_z\":{\"type\":\"number\"},\"terrain_mode\":{\"type\":\"string\",\"enum\":[\"conform\",\"floating\",\"tunnel_reserved\"]},\"operation\":{\"type\":\"string\",\"enum\":[\"endpoint\",\"junction\"]}},\"required\":[\"object\",\"point_x\",\"point_z\"],\"additionalProperties\":false}";
pub const road_object_schema = "{\"type\":\"object\",\"properties\":{\"object\":{\"type\":\"string\"}},\"required\":[\"object\"],\"additionalProperties\":false}";
pub const road_node_merge_schema = "{\"type\":\"object\",\"properties\":{\"object\":{\"type\":\"string\",\"description\":\"Node id to keep\"},\"parent\":{\"type\":\"string\",\"description\":\"Node id to merge/remove\"}},\"required\":[\"object\",\"parent\"],\"additionalProperties\":false}";
pub const road_edge_schema = "{\"type\":\"object\",\"properties\":{\"object\":{\"type\":\"string\",\"description\":\"Road edge id\"},\"parent\":{\"type\":\"string\",\"description\":\"Start node id\"},\"element\":{\"type\":\"string\",\"description\":\"End node id\"},\"width\":{\"type\":\"number\",\"minimum\":0.001},\"height\":{\"type\":\"number\",\"description\":\"Conform elevation/offset\"},\"a\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":255,\"description\":\"Material mask value\"},\"terrain_mode\":{\"type\":\"string\",\"enum\":[\"conform\",\"floating\",\"tunnel_reserved\"]},\"render_mode\":{\"type\":\"string\",\"enum\":[\"decal\",\"prop_sections\"]},\"material_path\":{\"type\":\"string\",\"description\":\"Decal material path\"},\"asset\":{\"type\":\"string\",\"description\":\"Prop section asset id\"}},\"required\":[\"object\",\"parent\",\"element\",\"width\"],\"additionalProperties\":false}";
pub const road_edge_update_schema = "{\"type\":\"object\",\"properties\":{\"object\":{\"type\":\"string\",\"description\":\"Road edge id\"},\"parent\":{\"type\":\"string\",\"description\":\"Optional replacement start node id\"},\"element\":{\"type\":\"string\",\"description\":\"Optional replacement end node id\"},\"width\":{\"type\":\"number\",\"minimum\":0.001},\"height\":{\"type\":\"number\",\"description\":\"Conform elevation/offset\"},\"a\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":255,\"description\":\"Material mask value\"},\"terrain_mode\":{\"type\":\"string\",\"enum\":[\"conform\",\"floating\",\"tunnel_reserved\"]},\"render_mode\":{\"type\":\"string\",\"enum\":[\"decal\",\"prop_sections\"]},\"material_path\":{\"type\":\"string\"},\"asset\":{\"type\":\"string\"}},\"required\":[\"object\"],\"additionalProperties\":false}";
pub const road_edge_split_schema = "{\"type\":\"object\",\"properties\":{\"object\":{\"type\":\"string\",\"description\":\"Road edge id to split\"},\"parent\":{\"type\":\"string\",\"description\":\"New node id\"},\"element\":{\"type\":\"string\",\"description\":\"New edge id\"},\"point_x\":{\"type\":\"number\"},\"point_y\":{\"type\":\"number\"},\"point_z\":{\"type\":\"number\"}},\"required\":[\"object\",\"parent\",\"element\",\"point_x\",\"point_z\"],\"additionalProperties\":false}";
pub const road_graph_list_schema = "{\"type\":\"object\",\"properties\":{\"offset\":{\"type\":\"integer\",\"minimum\":0},\"limit\":{\"type\":\"integer\",\"minimum\":1}},\"additionalProperties\":false}";

const object_fields = &.{Field{ .name = "object", .kind = .string }};
const path_fields = &.{Field{ .name = "path", .kind = .string }};
const project_create_fields = &.{
    Field{ .name = "path", .kind = .string },
    Field{ .name = "preset", .kind = .string },
};
const objects_list_fields = &.{
    Field{ .name = "offset", .kind = .number },
    Field{ .name = "limit", .kind = .number },
};
const terrain_footprint_list_fields = objects_list_fields;
const terrain_heightmap_export_fields = &.{
    Field{ .name = "path", .kind = .string },
    Field{ .name = "min_height", .kind = .number },
    Field{ .name = "max_height", .kind = .number },
};
const object_parent_fields = &.{
    Field{ .name = "object", .kind = .string },
    Field{ .name = "parent", .kind = .string },
};
const object_properties_fields = &.{
    Field{ .name = "object", .kind = .string },
    Field{ .name = "properties", .kind = .json },
};
const object_gameplay_fields = &.{
    Field{ .name = "object", .kind = .string },
    Field{ .name = "tag", .kind = .string },
    Field{ .name = "health", .kind = .number },
    Field{ .name = "score", .kind = .number },
    Field{ .name = "team", .kind = .number },
    Field{ .name = "interactable", .kind = .boolean },
};
const marker_create_fields = &.{
    Field{ .name = "kind", .kind = .string },
    Field{ .name = "object", .kind = .string },
    Field{ .name = "shape", .kind = .string },
    Field{ .name = "marker_id", .kind = .string },
    Field{ .name = "group", .kind = .string },
    Field{ .name = "binding", .kind = .string },
    Field{ .name = "radius", .kind = .number },
    Field{ .name = "order", .kind = .number },
    Field{ .name = "point_x", .kind = .number },
    Field{ .name = "point_y", .kind = .number },
    Field{ .name = "point_z", .kind = .number },
};
const marker_update_fields = &.{
    Field{ .name = "object", .kind = .string },
    Field{ .name = "kind", .kind = .string },
    Field{ .name = "shape", .kind = .string },
    Field{ .name = "marker_id", .kind = .string },
    Field{ .name = "group", .kind = .string },
    Field{ .name = "binding", .kind = .string },
    Field{ .name = "radius", .kind = .number },
    Field{ .name = "order", .kind = .number },
    Field{ .name = "point_x", .kind = .number },
    Field{ .name = "point_y", .kind = .number },
    Field{ .name = "point_z", .kind = .number },
};
const command_fields = &.{Field{ .name = "command", .kind = .string }};
const selection_scope_fields = &.{Field{ .name = "scope", .kind = .string }};
const selection_pick_fields = &.{
    Field{ .name = "screen_x", .kind = .number },
    Field{ .name = "screen_y", .kind = .number },
};
const selection_box_fields = &.{
    Field{ .name = "screen_x", .kind = .number },
    Field{ .name = "screen_y", .kind = .number },
    Field{ .name = "end_x", .kind = .number },
    Field{ .name = "end_y", .kind = .number },
};
const selection_pick_world_fields = &.{
    Field{ .name = "point_x", .kind = .number },
    Field{ .name = "point_y", .kind = .number },
    Field{ .name = "point_z", .kind = .number },
};
const undo_batch_fields = &.{
    Field{ .name = "label", .kind = .string },
    Field{ .name = "object", .kind = .string },
};
const scene_new_fields = &.{Field{ .name = "path", .kind = .string }};
const player_start_fields = &.{
    Field{ .name = "object", .kind = .string },
    Field{ .name = "point_x", .kind = .number },
    Field{ .name = "point_y", .kind = .number },
    Field{ .name = "point_z", .kind = .number },
    Field{ .name = "yaw", .kind = .number },
    Field{ .name = "pitch", .kind = .number },
};
const view_fields = &.{
    Field{ .name = "view", .kind = .string },
    Field{ .name = "orientation", .kind = .string },
};
const camera_fields = &.{
    Field{ .name = "target_x", .kind = .number },
    Field{ .name = "target_y", .kind = .number },
    Field{ .name = "target_z", .kind = .number },
    Field{ .name = "yaw", .kind = .number },
    Field{ .name = "pitch", .kind = .number },
    Field{ .name = "distance", .kind = .number },
};
const show_me_fields = &.{
    Field{ .name = "enabled", .kind = .boolean },
    Field{ .name = "point_x", .kind = .number },
    Field{ .name = "point_y", .kind = .number },
    Field{ .name = "point_z", .kind = .number },
    Field{ .name = "radius", .kind = .number },
    Field{ .name = "distance", .kind = .number },
};
const random_camera_fields = &.{Field{ .name = "seed", .kind = .number }};
const play_scene_fields = &.{Field{ .name = "frames", .kind = .number }};
const turntable_fields = &.{
    Field{ .name = "object", .kind = .string },
    Field{ .name = "frames", .kind = .number },
    Field{ .name = "fps", .kind = .number },
    Field{ .name = "format", .kind = .string },
};
const point_fields = &.{
    Field{ .name = "point_x", .kind = .number },
    Field{ .name = "point_y", .kind = .number },
    Field{ .name = "point_z", .kind = .number },
};
const prop_sketch_operation_fields = &.{
    Field{ .name = "amount", .kind = .number },
    Field{ .name = "segments", .kind = .number },
};
const prop_sketch_point_update_fields = &.{
    Field{ .name = "vertex", .kind = .number },
    Field{ .name = "point_x", .kind = .number },
    Field{ .name = "point_y", .kind = .number },
    Field{ .name = "point_z", .kind = .number },
};
const terrain_edge_cliff_fields = &.{
    Field{ .name = "height", .kind = .number },
    Field{ .name = "width", .kind = .number },
};
const terrain_stretch_smooth_fields = &.{
    Field{ .name = "threshold", .kind = .number },
    Field{ .name = "strength", .kind = .number },
    Field{ .name = "iterations", .kind = .number },
    Field{ .name = "max_samples_per_cell", .kind = .number },
    Field{ .name = "min_height", .kind = .number },
    Field{ .name = "max_height", .kind = .number },
};
const terrain_geology_start_fields = &.{
    Field{ .name = "min_x", .kind = .number },
    Field{ .name = "max_x", .kind = .number },
    Field{ .name = "min_z", .kind = .number },
    Field{ .name = "max_z", .kind = .number },
    Field{ .name = "cell_size_m", .kind = .number },
    Field{ .name = "batch_size", .kind = .number },
    Field{ .name = "seed", .kind = .number },
    Field{ .name = "properties", .kind = .json },
};
const terrain_recipe_fields = &.{
    Field{ .name = "operation", .kind = .string },
    Field{ .name = "min_x", .kind = .number },
    Field{ .name = "max_x", .kind = .number },
    Field{ .name = "min_z", .kind = .number },
    Field{ .name = "max_z", .kind = .number },
    Field{ .name = "cell_size_m", .kind = .number },
    Field{ .name = "seed", .kind = .number },
    Field{ .name = "sea_level", .kind = .number },
    Field{ .name = "ocean_floor", .kind = .number },
    Field{ .name = "features", .kind = .json },
    Field{ .name = "materials", .kind = .json },
    Field{ .name = "roads", .kind = .json },
};
const world_region_upsert_fields = &.{
    Field{ .name = "object", .kind = .string },
    Field{ .name = "parent", .kind = .string },
    Field{ .name = "properties", .kind = .json },
    Field{ .name = "cells", .kind = .string },
};
const world_region_delete_fields = &.{Field{ .name = "object", .kind = .string }};
const world_region_paint_fields = &.{
    Field{ .name = "object", .kind = .string },
    Field{ .name = "parent", .kind = .string },
    Field{ .name = "operation", .kind = .string },
    Field{ .name = "point_x", .kind = .number },
    Field{ .name = "point_y", .kind = .number },
    Field{ .name = "point_z", .kind = .number },
    Field{ .name = "radius", .kind = .number },
};
const ocean_clip_update_fields = &.{Field{ .name = "points", .kind = .string }};
const ocean_clip_point_fields = &.{
    Field{ .name = "point_x", .kind = .number },
    Field{ .name = "point_z", .kind = .number },
};
const water_volume_fields = &.{
    Field{ .name = "object", .kind = .string },
    Field{ .name = "kind", .kind = .string },
    Field{ .name = "material", .kind = .string },
    Field{ .name = "points", .kind = .string },
    Field{ .name = "surface_y", .kind = .number },
    Field{ .name = "bottom_y", .kind = .number },
    Field{ .name = "swimmable", .kind = .boolean },
    Field{ .name = "linked_to_ocean", .kind = .boolean },
    Field{ .name = "current_x", .kind = .number },
    Field{ .name = "current_y", .kind = .number },
    Field{ .name = "current_z", .kind = .number },
};
const water_query_fields = &.{
    Field{ .name = "point_x", .kind = .number },
    Field{ .name = "point_y", .kind = .number },
    Field{ .name = "point_z", .kind = .number },
};
const plot_create_fields = &.{
    Field{ .name = "object", .kind = .string },
    Field{ .name = "properties", .kind = .json },
    Field{ .name = "point_x", .kind = .number },
    Field{ .name = "point_y", .kind = .number },
    Field{ .name = "point_z", .kind = .number },
    Field{ .name = "width", .kind = .number },
    Field{ .name = "depth", .kind = .number },
};
const plot_align_fields = &.{
    Field{ .name = "object", .kind = .string },
    Field{ .name = "point_y", .kind = .number },
};
const opening_fields = &.{
    Field{ .name = "point_x", .kind = .number },
    Field{ .name = "point_y", .kind = .number },
    Field{ .name = "point_z", .kind = .number },
    Field{ .name = "end_x", .kind = .number },
    Field{ .name = "end_y", .kind = .number },
    Field{ .name = "end_z", .kind = .number },
};
const architecture_building_fields = &.{
    Field{ .name = "object", .kind = .string },
    Field{ .name = "parent", .kind = .string },
    Field{ .name = "properties", .kind = .json },
    Field{ .name = "point_x", .kind = .number },
    Field{ .name = "point_y", .kind = .number },
    Field{ .name = "point_z", .kind = .number },
    Field{ .name = "width", .kind = .number },
    Field{ .name = "depth", .kind = .number },
    Field{ .name = "height", .kind = .number },
    Field{ .name = "thickness", .kind = .number },
    Field{ .name = "floors", .kind = .number },
    Field{ .name = "roof", .kind = .string },
};
const architecture_network_fields = &.{
    Field{ .name = "object", .kind = .string },
    Field{ .name = "parent", .kind = .string },
    Field{ .name = "properties", .kind = .json },
    Field{ .name = "point_x", .kind = .number },
    Field{ .name = "point_y", .kind = .number },
    Field{ .name = "point_z", .kind = .number },
    Field{ .name = "height", .kind = .number },
    Field{ .name = "thickness", .kind = .number },
    Field{ .name = "floors", .kind = .number },
};
const architecture_node_fields = &.{
    Field{ .name = "object", .kind = .string },
    Field{ .name = "vertex", .kind = .number },
    Field{ .name = "point_x", .kind = .number },
    Field{ .name = "point_z", .kind = .number },
};
const architecture_edge_fields = &.{
    Field{ .name = "object", .kind = .string },
    Field{ .name = "edge_a", .kind = .number },
    Field{ .name = "edge_b", .kind = .number },
    Field{ .name = "height", .kind = .number },
    Field{ .name = "thickness", .kind = .number },
    Field{ .name = "operation", .kind = .string },
    Field{ .name = "floors", .kind = .number },
};
const architecture_edge_id_fields = &.{
    Field{ .name = "object", .kind = .string },
    Field{ .name = "edge_a", .kind = .number },
};
const architecture_edge_split_fields = &.{
    Field{ .name = "object", .kind = .string },
    Field{ .name = "edge_a", .kind = .number },
    Field{ .name = "point_x", .kind = .number },
    Field{ .name = "point_z", .kind = .number },
};
const architecture_shell_fields = &.{
    Field{ .name = "object", .kind = .string },
    Field{ .name = "path", .kind = .string },
};
const architecture_wall_height_fields = &.{
    Field{ .name = "object", .kind = .string },
    Field{ .name = "edge_a", .kind = .number },
    Field{ .name = "height", .kind = .number },
    Field{ .name = "operation", .kind = .string },
    Field{ .name = "floors", .kind = .number },
};
const architecture_floor_fields = &.{
    Field{ .name = "object", .kind = .string },
    Field{ .name = "height", .kind = .number },
    Field{ .name = "thickness", .kind = .number },
    Field{ .name = "floors", .kind = .number },
};
const architecture_foundation_fields = &.{
    Field{ .name = "object", .kind = .string },
    Field{ .name = "edge_a", .kind = .number },
    Field{ .name = "point_x", .kind = .number },
    Field{ .name = "point_z", .kind = .number },
    Field{ .name = "end_x", .kind = .number },
    Field{ .name = "end_z", .kind = .number },
    Field{ .name = "height", .kind = .number },
    Field{ .name = "thickness", .kind = .number },
    Field{ .name = "radius", .kind = .number },
};
const architecture_cutout_fields = &.{
    Field{ .name = "object", .kind = .string },
    Field{ .name = "edge_a", .kind = .number },
    Field{ .name = "point_x", .kind = .number },
    Field{ .name = "point_y", .kind = .number },
    Field{ .name = "point_z", .kind = .number },
    Field{ .name = "end_x", .kind = .number },
    Field{ .name = "end_y", .kind = .number },
    Field{ .name = "end_z", .kind = .number },
};
const architecture_roof_fields = &.{
    Field{ .name = "object", .kind = .string },
    Field{ .name = "roof", .kind = .string },
    Field{ .name = "height", .kind = .number },
    Field{ .name = "thickness", .kind = .number },
};
const architecture_opening_fields = &.{
    Field{ .name = "object", .kind = .string },
    Field{ .name = "edge_a", .kind = .number },
    Field{ .name = "operation", .kind = .string },
    Field{ .name = "u", .kind = .number },
    Field{ .name = "width", .kind = .number },
    Field{ .name = "height", .kind = .number },
    Field{ .name = "point_y", .kind = .number },
};
const road_node_fields = &.{
    Field{ .name = "object", .kind = .string },
    Field{ .name = "point_x", .kind = .number },
    Field{ .name = "point_y", .kind = .number },
    Field{ .name = "point_z", .kind = .number },
    Field{ .name = "terrain_mode", .kind = .string },
    Field{ .name = "operation", .kind = .string },
};
const road_node_merge_fields = &.{
    Field{ .name = "object", .kind = .string },
    Field{ .name = "parent", .kind = .string },
};
const road_edge_fields = &.{
    Field{ .name = "object", .kind = .string },
    Field{ .name = "parent", .kind = .string },
    Field{ .name = "element", .kind = .string },
    Field{ .name = "width", .kind = .number },
    Field{ .name = "height", .kind = .number },
    Field{ .name = "a", .kind = .number },
    Field{ .name = "terrain_mode", .kind = .string },
    Field{ .name = "render_mode", .kind = .string },
    Field{ .name = "material_path", .kind = .string },
    Field{ .name = "asset", .kind = .string },
};
const road_edge_split_fields = &.{
    Field{ .name = "object", .kind = .string },
    Field{ .name = "parent", .kind = .string },
    Field{ .name = "element", .kind = .string },
    Field{ .name = "point_x", .kind = .number },
    Field{ .name = "point_y", .kind = .number },
    Field{ .name = "point_z", .kind = .number },
};
const road_graph_list_fields = &.{
    Field{ .name = "offset", .kind = .number },
    Field{ .name = "limit", .kind = .number },
};
const terrain_sculpt_fields = &.{
    Field{ .name = "point_x", .kind = .number },
    Field{ .name = "point_y", .kind = .number },
    Field{ .name = "point_z", .kind = .number },
    Field{ .name = "operation", .kind = .string },
    Field{ .name = "radius", .kind = .number },
    Field{ .name = "opacity", .kind = .number },
    Field{ .name = "hardness", .kind = .number },
};
const terrain_material_paint_fields = &.{
    Field{ .name = "object", .kind = .string },
    Field{ .name = "point_x", .kind = .number },
    Field{ .name = "point_y", .kind = .number },
    Field{ .name = "point_z", .kind = .number },
    Field{ .name = "radius", .kind = .number },
    Field{ .name = "opacity", .kind = .number },
    Field{ .name = "hardness", .kind = .number },
};
const terrain_heightmap_fields = &.{
    Field{ .name = "path", .kind = .string },
    Field{ .name = "point_x", .kind = .number },
    Field{ .name = "point_y", .kind = .number },
    Field{ .name = "point_z", .kind = .number },
    Field{ .name = "min_height", .kind = .number },
    Field{ .name = "max_height", .kind = .number },
    Field{ .name = "material_path", .kind = .string },
};
const terrain_heightmap_batch_fields = &.{
    Field{ .name = "path", .kind = .string },
    Field{ .name = "albedo_path", .kind = .string },
    Field{ .name = "min_x", .kind = .number },
    Field{ .name = "max_x", .kind = .number },
    Field{ .name = "min_z", .kind = .number },
    Field{ .name = "max_z", .kind = .number },
    Field{ .name = "cell_size_m", .kind = .number },
    Field{ .name = "min_height", .kind = .number },
    Field{ .name = "max_height", .kind = .number },
    Field{ .name = "material_path", .kind = .string },
};
const material_object_fields = &.{
    Field{ .name = "material_path", .kind = .string },
    Field{ .name = "r", .kind = .number },
    Field{ .name = "g", .kind = .number },
    Field{ .name = "b", .kind = .number },
    Field{ .name = "a", .kind = .number },
    Field{ .name = "scale_world", .kind = .number },
    Field{ .name = "rotation_deg", .kind = .number },
    Field{ .name = "offset_u", .kind = .number },
    Field{ .name = "offset_v", .kind = .number },
};
const material_face_fields = &.{
    Field{ .name = "face_index", .kind = .number },
    Field{ .name = "material_path", .kind = .string },
    Field{ .name = "r", .kind = .number },
    Field{ .name = "g", .kind = .number },
    Field{ .name = "b", .kind = .number },
    Field{ .name = "a", .kind = .number },
    Field{ .name = "scale_world", .kind = .number },
    Field{ .name = "rotation_deg", .kind = .number },
    Field{ .name = "offset_u", .kind = .number },
    Field{ .name = "offset_v", .kind = .number },
};
const texture_fill_fields = &.{
    Field{ .name = "r", .kind = .number },
    Field{ .name = "g", .kind = .number },
    Field{ .name = "b", .kind = .number },
    Field{ .name = "a", .kind = .number },
};
const texture_paint_fields = &.{
    Field{ .name = "u", .kind = .number },
    Field{ .name = "v", .kind = .number },
    Field{ .name = "r", .kind = .number },
    Field{ .name = "g", .kind = .number },
    Field{ .name = "b", .kind = .number },
    Field{ .name = "a", .kind = .number },
    Field{ .name = "radius", .kind = .number },
    Field{ .name = "opacity", .kind = .number },
    Field{ .name = "hardness", .kind = .number },
};
const prop_primitive_seed_fields = &.{
    Field{ .name = "primitive", .kind = .string },
    Field{ .name = "width", .kind = .number },
    Field{ .name = "height", .kind = .number },
    Field{ .name = "depth", .kind = .number },
    Field{ .name = "radius", .kind = .number },
    Field{ .name = "segments", .kind = .number },
};
const concept_paint_capture_fields = &.{
    Field{ .name = "screenshot_path", .kind = .string },
    Field{ .name = "prompt", .kind = .string },
    Field{ .name = "provider", .kind = .string },
    Field{ .name = "desired_style", .kind = .string },
    Field{ .name = "output_path", .kind = .string },
    Field{ .name = "opacity", .kind = .number },
    Field{ .name = "blend_mode", .kind = .string },
};
const concept_paint_import_fields = &.{
    Field{ .name = "styled_path", .kind = .string },
};

pub const entries = [_]Entry{
    .{ .command_name = "open-project", .mcp_tool_name = "open_project", .title = "Open Project", .description = "Ask the project manager to open the selected or named project.", .tier = .stable, .owner = .project_manager, .argument_policy = .fields, .input_schema = optional_object_schema, .fields = object_fields },
    .{ .command_name = "project.create", .mcp_tool_name = "project_create", .title = "Create Project", .description = "From Project Manager only, create a starter project folder and register it.", .tier = .stable, .owner = .project_manager, .argument_policy = .fields, .input_schema = project_create_schema, .fields = project_create_fields },
    .{ .command_name = "project.import", .mcp_tool_name = "project_import", .title = "Import Project", .description = "From Project Manager only, register an existing folder without creating project files.", .tier = .stable, .owner = .project_manager, .argument_policy = .fields, .input_schema = project_path_schema, .fields = path_fields },
    .{ .command_name = "project.remove", .mcp_tool_name = "project_remove", .title = "Remove Project From List", .description = "From Project Manager only, remove the selected or named project from the list without deleting files.", .tier = .stable, .owner = .project_manager, .argument_policy = .fields, .input_schema = optional_object_schema, .fields = object_fields },
    .{ .command_name = "project.init-existing", .mcp_tool_name = "project_init_existing", .title = "Initialize Existing Folder", .description = "From Project Manager only, add missing starter project files to an existing folder and register it.", .tier = .stable, .owner = .project_manager, .argument_policy = .fields, .input_schema = project_path_schema, .fields = path_fields },
    .{ .command_name = "project.reset-selected", .mcp_tool_name = "project_reset_selected", .title = "Reset Selected Project", .description = "From Project Manager only, delete authored game data in the selected project and recreate the clean starter project.", .tier = .destructive, .owner = .project_manager, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "editor.describe", .mcp_tool_name = "editor_describe", .title = "Describe Editor", .description = "Return project, mode, tool, viewport, camera, selection, counts, and status JSON.", .tier = .stable, .owner = .editor, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "objects.list", .mcp_tool_name = "objects_list", .title = "List Objects", .description = "Return scene objects with ids, names, transforms, visibility, selection, and page metadata. Use offset and limit for large scenes.", .tier = .stable, .owner = .selection, .argument_policy = .fields, .input_schema = objects_list_schema, .fields = objects_list_fields },
    .{ .command_name = "object.select", .mcp_tool_name = "object_select", .title = "Select Object", .description = "Select an object by numeric id or name.", .tier = .stable, .owner = .selection, .argument_policy = .fields, .input_schema = object_schema, .fields = object_fields },
    .{ .command_name = "object.parent-set", .mcp_tool_name = "object_parent_set", .title = "Set Object Parent", .description = "Parent one scene object under another by id or name. Fails on missing objects or cycles.", .tier = .stable, .owner = .selection, .argument_policy = .fields, .input_schema = object_parent_schema, .fields = object_parent_fields },
    .{ .command_name = "object.properties-set", .mcp_tool_name = "object_properties_set", .title = "Set Object Properties", .description = "Replace an object's scenario property bag with validated key/value metadata.", .tier = .stable, .owner = .selection, .argument_policy = .fields, .input_schema = object_properties_schema, .fields = object_properties_fields },
    .{ .command_name = "object.gameplay-set", .mcp_tool_name = "object_gameplay_set", .title = "Set Object Gameplay", .description = "Set an object's gameplay tag and interactable metadata.", .tier = .stable, .owner = .selection, .argument_policy = .fields, .input_schema = object_gameplay_schema, .fields = object_gameplay_fields },
    .{ .command_name = "selection.scope-set", .mcp_tool_name = "selection_scope_set", .title = "Set Selection Scope", .description = "Set the shared editor selection scope: object, face, edge, point, source, operation, or marker.", .tier = .stable, .owner = .selection, .argument_policy = .fields, .input_schema = selection_scope_schema, .fields = selection_scope_fields },
    .{ .command_name = "selection.scope-cycle", .mcp_tool_name = "selection_scope_cycle", .title = "Cycle Selection Scope", .description = "Advance the shared editor selection scope in the same canonical order as the Tab shortcut.", .tier = .stable, .owner = .selection, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "selection.pick", .mcp_tool_name = "selection_pick", .title = "Pick In Viewport", .description = "Pick at a viewport-local pixel coordinate using the active shared selection scope and cycling state.", .tier = .stable, .owner = .selection, .argument_policy = .fields, .input_schema = selection_pick_schema, .fields = selection_pick_fields },
    .{ .command_name = "selection.box-select", .mcp_tool_name = "selection_box_select", .title = "Box Select In Viewport", .description = "Drag-select a viewport-local rectangle using the active shared selection scope.", .tier = .stable, .owner = .selection, .argument_policy = .fields, .input_schema = selection_box_schema, .fields = selection_box_fields },
    .{ .command_name = "selection.pick-world", .mcp_tool_name = "selection_pick_world", .title = "Pick World Point", .description = "Project a world point into the viewport, then pick there using the active shared selection scope and cycling state.", .tier = .stable, .owner = .selection, .argument_policy = .fields, .input_schema = selection_pick_world_schema, .fields = selection_pick_world_fields },
    .{ .command_name = "marker.create", .mcp_tool_name = "marker_create", .title = "Create Gameplay Marker", .description = "Create a persisted gameplay marker primitive with editor-only visual overlays and selectable marker data.", .tier = .stable, .owner = .editor, .argument_policy = .fields, .input_schema = marker_create_schema, .fields = marker_create_fields },
    .{ .command_name = "marker.update", .mcp_tool_name = "marker_update", .title = "Update Gameplay Marker", .description = "Update marker primitive data and position by marker object id or name.", .tier = .stable, .owner = .editor, .argument_policy = .fields, .input_schema = marker_update_schema, .fields = marker_update_fields },
    .{ .command_name = "object.clear-selection", .mcp_tool_name = "object_clear_selection", .title = "Clear Selection", .description = "Clear object, vertex, edge, and face selection.", .tier = .stable, .owner = .selection, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "commands.list", .mcp_tool_name = "commands_list", .title = "List Commands", .description = "Return user-visible editor command ids, labels, screens, and sections.", .tier = .stable, .owner = .commands, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "commands.scene-map", .mcp_tool_name = "commands_scene_map", .title = "Command Scene Map", .description = "Return app scenes, scene transitions, current-scene commands, and commands only available from other scenes.", .tier = .stable, .owner = .commands, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "command.run", .mcp_tool_name = "command_run", .title = "Run Command", .description = "Run a user-visible editor command id.", .tier = .stable, .owner = .commands, .argument_policy = .fields, .input_schema = command_schema, .fields = command_fields },
    .{ .command_name = "undo.batch-begin", .mcp_tool_name = "undo_batch_begin", .title = "Begin Undo Batch", .description = "Begin grouping subsequent undo snapshots so one undo reverses a complete LLM-authored action.", .tier = .stable, .owner = .commands, .argument_policy = .fields, .input_schema = undo_batch_schema, .fields = undo_batch_fields },
    .{ .command_name = "undo.batch-end", .mcp_tool_name = "undo_batch_end", .title = "End Undo Batch", .description = "End the current grouped undo batch.", .tier = .stable, .owner = .commands, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "undo.batch-cancel", .mcp_tool_name = "undo_batch_cancel", .title = "Cancel Undo Batch Grouping", .description = "Stop grouping future undo snapshots without reverting edits already made.", .tier = .stable, .owner = .commands, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "scene.new-architecture", .mcp_tool_name = "scene_new_architecture", .title = "New Architecture Scene", .description = "Create a fresh in-memory scene for architecture-first blockout work and switch the editor to Architecture mode.", .tier = .destructive, .owner = .editor, .argument_policy = .fields, .input_schema = scene_new_schema, .fields = scene_new_fields },
    .{ .command_name = "project.startup-scene-set", .mcp_tool_name = "project_startup_scene_set", .title = "Set Project Startup Scene", .description = "Set the project-specific scene path used by Play and runtime boot.", .tier = .stable, .owner = .play, .argument_policy = .fields, .input_schema = startup_scene_schema, .fields = scene_new_fields },
    .{ .command_name = "world.sky-toggle", .mcp_tool_name = "world_sky_toggle", .title = "Toggle World Sky", .description = "Toggle atmosphere sky rendering in the world viewport.", .tier = .stable, .owner = .world, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "world.ocean-toggle", .mcp_tool_name = "world_ocean_toggle", .title = "Toggle World Ocean", .description = "Toggle far ocean rendering in the world viewport and persist the ocean layer setting.", .tier = .stable, .owner = .world, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "world.region-list", .mcp_tool_name = "world_region_list", .title = "List World Regions", .description = "List semantic world regions with irregular cell membership, resident counts, dirty counts, bounds, and unassigned cells.", .tier = .stable, .owner = .world, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "world.region-upsert", .mcp_tool_name = "world_region_upsert", .title = "Create Or Update World Region", .description = "Create or replace a semantic region from an arbitrary semicolon-separated set of cell coordinates.", .tier = .stable, .owner = .world, .argument_policy = .fields, .input_schema = world_region_upsert_schema, .fields = world_region_upsert_fields },
    .{ .command_name = "world.region-paint", .mcp_tool_name = "world_region_paint", .title = "Paint World Region Membership", .description = "Assign or erase region membership by brushing manifest cells around a world point and radius.", .tier = .stable, .owner = .world, .argument_policy = .fields, .input_schema = world_region_paint_schema, .fields = world_region_paint_fields },
    .{ .command_name = "world.region-delete", .mcp_tool_name = "world_region_delete", .title = "Delete World Region", .description = "Delete a semantic world region. Its cells become unassigned.", .tier = .destructive, .owner = .world, .argument_policy = .fields, .input_schema = world_region_delete_schema, .fields = world_region_delete_fields },
    .{ .command_name = "ocean.exclusion-list", .mcp_tool_name = "ocean_exclusion_list", .title = "List Ocean Exclusion", .description = "List the designer-authored far-ocean exclusion polygon. Ocean exists everywhere except inside this shape.", .tier = .stable, .owner = .world, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "ocean.exclusion-update", .mcp_tool_name = "ocean_exclusion_update", .title = "Update Ocean Exclusion", .description = "Replace the far-ocean exclusion polygon and regenerate the ocean mesh. Empty points clear the exclusion.", .tier = .stable, .owner = .world, .argument_policy = .fields, .input_schema = ocean_clip_update_schema, .fields = ocean_clip_update_fields },
    .{ .command_name = "ocean.exclusion-point-add", .mcp_tool_name = "ocean_exclusion_point_add", .title = "Add Ocean Exclusion Point", .description = "Append one point to the far-ocean exclusion polygon, or create a starter exclusion if none exists.", .tier = .stable, .owner = .world, .argument_policy = .fields, .input_schema = ocean_clip_point_schema, .fields = ocean_clip_point_fields },
    .{ .command_name = "ocean.exclusion-point-move-nearest", .mcp_tool_name = "ocean_exclusion_point_move_nearest", .title = "Move Nearest Ocean Exclusion Point", .description = "Move the nearest ocean exclusion vertex to a world X/Z point.", .tier = .stable, .owner = .world, .argument_policy = .fields, .input_schema = ocean_clip_point_schema, .fields = ocean_clip_point_fields },
    .{ .command_name = "ocean.exclusion-point-delete-nearest", .mcp_tool_name = "ocean_exclusion_point_delete_nearest", .title = "Delete Nearest Ocean Exclusion Point", .description = "Delete the nearest ocean exclusion vertex. Deleting a triangle clears the exclusion.", .tier = .destructive, .owner = .world, .argument_policy = .fields, .input_schema = ocean_clip_point_schema, .fields = ocean_clip_point_fields },
    .{ .command_name = "ocean.clip-list", .mcp_tool_name = "ocean_clip_list", .title = "List Ocean Clip", .description = "Compatibility alias for ocean.exclusion-list.", .tier = .stable, .owner = .world, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "ocean.clip-update", .mcp_tool_name = "ocean_clip_update", .title = "Update Ocean Clip", .description = "Compatibility alias for ocean.exclusion-update.", .tier = .stable, .owner = .world, .argument_policy = .fields, .input_schema = ocean_clip_update_schema, .fields = ocean_clip_update_fields },
    .{ .command_name = "ocean.clip-point-add", .mcp_tool_name = "ocean_clip_point_add", .title = "Add Ocean Clip Point", .description = "Compatibility alias for ocean.exclusion-point-add.", .tier = .stable, .owner = .world, .argument_policy = .fields, .input_schema = ocean_clip_point_schema, .fields = ocean_clip_point_fields },
    .{ .command_name = "ocean.clip-point-move-nearest", .mcp_tool_name = "ocean_clip_point_move_nearest", .title = "Move Nearest Ocean Clip Point", .description = "Compatibility alias for ocean.exclusion-point-move-nearest.", .tier = .stable, .owner = .world, .argument_policy = .fields, .input_schema = ocean_clip_point_schema, .fields = ocean_clip_point_fields },
    .{ .command_name = "ocean.clip-point-delete-nearest", .mcp_tool_name = "ocean_clip_point_delete_nearest", .title = "Delete Nearest Ocean Clip Point", .description = "Compatibility alias for ocean.exclusion-point-delete-nearest.", .tier = .destructive, .owner = .world, .argument_policy = .fields, .input_schema = ocean_clip_point_schema, .fields = ocean_clip_point_fields },
    .{ .command_name = "water.volume-list", .mcp_tool_name = "water_volume_list", .title = "List Water Volumes", .description = "List local swimmable water polygon-prism volumes.", .tier = .stable, .owner = .world, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "water.volume-create", .mcp_tool_name = "water_volume_create", .title = "Create Water Volume", .description = "Create a local water polygon-prism volume in layers/water.kdl.", .tier = .stable, .owner = .world, .argument_policy = .fields, .input_schema = water_volume_schema, .fields = water_volume_fields },
    .{ .command_name = "water.volume-update", .mcp_tool_name = "water_volume_update", .title = "Update Water Volume", .description = "Update an existing local water polygon-prism volume.", .tier = .stable, .owner = .world, .argument_policy = .fields, .input_schema = water_volume_schema, .fields = water_volume_fields },
    .{ .command_name = "water.volume-delete", .mcp_tool_name = "water_volume_delete", .title = "Delete Water Volume", .description = "Delete a local water volume by id.", .tier = .destructive, .owner = .world, .argument_policy = .fields, .input_schema = object_schema, .fields = object_fields },
    .{ .command_name = "water.query-point", .mcp_tool_name = "water_query_point", .title = "Query Water Point", .description = "Query local water volumes at a world-space point.", .tier = .stable, .owner = .world, .argument_policy = .fields, .input_schema = water_query_schema, .fields = water_query_fields },
    .{ .command_name = "play.player-start-set", .mcp_tool_name = "play_player_start_set", .title = "Set Player Start", .description = "Create or update an empty player-start spawner with FPS controller components.", .tier = .stable, .owner = .play, .argument_policy = .fields, .input_schema = player_start_schema, .fields = player_start_fields },
    .{ .command_name = "plot.create", .mcp_tool_name = "plot_create", .title = "Create Plot Root", .description = "Create a movable plot root rectangle at a world coordinate for parenting a building and its prop instances.", .tier = .stable, .owner = .world, .argument_policy = .fields, .input_schema = plot_create_schema, .fields = plot_create_fields },
    .{ .command_name = "plot.align-to-terrain", .mcp_tool_name = "plot_align_to_terrain", .title = "Conform Plot To Terrain", .description = "Rebuild one or all plot root meshes so their footprints follow the sampled terrain surface.", .tier = .stable, .owner = .world, .argument_policy = .fields, .input_schema = plot_align_schema, .fields = plot_align_fields },
    .{ .command_name = "terrain.geology-start", .mcp_tool_name = "terrain_geology_start", .title = "Start Geological Terrain Job", .description = "Start a large-scale streaming terrain job from geological formation primitives. Poll terrain.geology-status for progress.", .tier = .stable, .owner = .terrain, .argument_policy = .fields, .input_schema = terrain_geology_start_schema, .fields = terrain_geology_start_fields },
    .{ .command_name = "terrain.geology-status", .mcp_tool_name = "terrain_geology_status", .title = "Geological Terrain Job Status", .description = "Return progress for the active or most recent geological terrain job.", .tier = .stable, .owner = .terrain, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "terrain.footprint-list", .mcp_tool_name = "terrain_footprint_list", .title = "List Terrain Footprint", .description = "Return terrain loading readiness plus paginated resident terrain cell bounds, material, and height summaries for region alignment.", .tier = .stable, .owner = .terrain, .argument_policy = .fields, .input_schema = terrain_footprint_list_schema, .fields = terrain_footprint_list_fields },
    .{ .command_name = "terrain.geology-cancel", .mcp_tool_name = "terrain_geology_cancel", .title = "Cancel Geological Terrain Job", .description = "Cancel the active geological terrain job.", .tier = .stable, .owner = .terrain, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "terrain.recipe-apply", .mcp_tool_name = "terrain_recipe_apply", .title = "Apply Terrain Recipe", .description = "Apply a named-brush island terrain recipe across an existing cell range while preserving cell membership.", .tier = .stable, .owner = .terrain, .argument_policy = .fields, .input_schema = terrain_recipe_schema, .fields = terrain_recipe_fields },
    .{ .command_name = "terrain.recipe-status", .mcp_tool_name = "terrain_recipe_status", .title = "Terrain Recipe Status", .description = "Return progress for the active or most recent terrain recipe job.", .tier = .stable, .owner = .terrain, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "terrain.recipe-cancel", .mcp_tool_name = "terrain_recipe_cancel", .title = "Cancel Terrain Recipe", .description = "Cancel the active terrain recipe job.", .tier = .stable, .owner = .terrain, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "terrain.cell-create", .mcp_tool_name = "terrain_cell_create", .title = "Create Terrain Cell", .description = "Create or ensure a terrain tile at a world coordinate.", .tier = .stable, .owner = .terrain, .argument_policy = .fields, .input_schema = terrain_point_schema, .fields = point_fields },
    .{ .command_name = "terrain.cell-delete", .mcp_tool_name = "terrain_cell_delete", .title = "Delete Terrain Cell", .description = "Delete the terrain tile at a world coordinate.", .tier = .destructive, .owner = .terrain, .argument_policy = .fields, .input_schema = terrain_point_schema, .fields = point_fields },
    .{ .command_name = "terrain.sculpt", .mcp_tool_name = "terrain_sculpt", .title = "Sculpt Terrain", .description = "Raise, lower, or smooth terrain at a world coordinate with optional brush radius, opacity, and hardness.", .tier = .stable, .owner = .terrain, .argument_policy = .fields, .input_schema = terrain_sculpt_schema, .fields = terrain_sculpt_fields },
    .{ .command_name = "terrain.material-paint", .mcp_tool_name = "terrain_material_paint", .title = "Paint Terrain Material", .description = "Paint a named terrain material layer at a world coordinate with optional brush radius, opacity, and hardness.", .tier = .stable, .owner = .terrain, .argument_policy = .fields, .input_schema = terrain_material_paint_schema, .fields = terrain_material_paint_fields },
    .{ .command_name = "terrain.edge-cliff", .mcp_tool_name = "terrain_edge_cliff", .title = "Sculpt World Edge Cliff", .description = "Lower the perimeter of the current terrain world to a bottom height across an inward rim width.", .tier = .stable, .owner = .terrain, .argument_policy = .fields, .input_schema = terrain_edge_cliff_schema, .fields = terrain_edge_cliff_fields },
    .{ .command_name = "terrain.edge-cliff-status", .mcp_tool_name = "terrain_edge_cliff_status", .title = "World Edge Cliff Status", .description = "Return progress for the active or most recent world edge cliff job.", .tier = .stable, .owner = .terrain, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "terrain.edge-cliff-cancel", .mcp_tool_name = "terrain_edge_cliff_cancel", .title = "Cancel World Edge Cliff", .description = "Cancel the active world edge cliff job.", .tier = .stable, .owner = .terrain, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "terrain.stretch-smooth", .mcp_tool_name = "terrain_stretch_smooth", .title = "Smooth Stretched Terrain Samples", .description = "Smooth only the worst local height discontinuities in terrain tiles using tunable threshold, strength, iterations, and per-cell sample cap.", .tier = .stable, .owner = .terrain, .argument_policy = .fields, .input_schema = terrain_stretch_smooth_schema, .fields = terrain_stretch_smooth_fields },
    .{ .command_name = "terrain.stretch-smooth-status", .mcp_tool_name = "terrain_stretch_smooth_status", .title = "Stretched Terrain Smoothing Status", .description = "Return progress for the active or most recent stretched terrain smoothing job.", .tier = .stable, .owner = .terrain, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "terrain.stretch-smooth-cancel", .mcp_tool_name = "terrain_stretch_smooth_cancel", .title = "Cancel Stretched Terrain Smoothing", .description = "Cancel the active stretched terrain smoothing job.", .tier = .stable, .owner = .terrain, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "terrain.undo-latest", .mcp_tool_name = "terrain_undo_latest", .title = "Undo Latest Terrain Transaction", .description = "Restore the newest terrain undo transaction and remove it from the terrain undo store.", .tier = .stable, .owner = .terrain, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "terrain.heightmap-load", .mcp_tool_name = "terrain_heightmap_load", .title = "Load Terrain Heightmap", .description = "Load a PNG heightmap into the terrain tile at a world coordinate. Heights are resampled to the editor terrain grid.", .tier = .experimental, .owner = .terrain, .argument_policy = .fields, .input_schema = terrain_heightmap_schema, .fields = terrain_heightmap_fields },
    .{ .command_name = "terrain.heightmap-batch-load", .mcp_tool_name = "terrain_heightmap_batch_load", .title = "Batch Load Terrain Heightmap", .description = "Load one PNG heightmap across a rectangular terrain-cell range with shared-edge sampling.", .tier = .experimental, .owner = .terrain, .argument_policy = .fields, .input_schema = terrain_heightmap_batch_schema, .fields = terrain_heightmap_batch_fields },
    .{ .command_name = "terrain.heightmap-export", .mcp_tool_name = "terrain_heightmap_export", .title = "Export Terrain Heightmap", .description = "Export the current authored terrain cells as an 8-bit grayscale PNG heightmap. Omit path to write under .friendly-engine/editor-control/exports.", .tier = .stable, .owner = .terrain, .argument_policy = .fields, .input_schema = terrain_heightmap_export_schema, .fields = terrain_heightmap_export_fields },
    .{ .command_name = "view.set", .mcp_tool_name = "view_set", .title = "Set View", .description = "Set viewport camera mode and/or orientation.", .tier = .stable, .owner = .view, .argument_policy = .fields, .input_schema = view_schema, .fields = view_fields },
    .{ .command_name = "camera.set", .mcp_tool_name = "camera_set", .title = "Set Camera", .description = "Set editor camera target, yaw, pitch, or distance.", .tier = .stable, .owner = .camera, .argument_policy = .fields, .input_schema = camera_schema, .fields = camera_fields },
    .{ .command_name = "show-me", .mcp_tool_name = "show_me", .title = "Show Me Mode", .description = "Enable or disable camera framing for LLM-authored world changes. When enabled, optional point and radius pre-frame a batch work area.", .tier = .stable, .owner = .camera, .argument_policy = .fields, .input_schema = show_me_schema, .fields = show_me_fields },
    .{ .command_name = "camera.preset", .mcp_tool_name = "camera_preset", .title = "Camera Preset", .description = "Set a named review camera preset for repeatable screenshot review.", .tier = .stable, .owner = .camera, .argument_policy = .fields, .input_schema = object_schema, .fields = object_fields },
    .{ .command_name = "camera.random-angle", .mcp_tool_name = "camera_random_angle", .title = "Random Review Camera", .description = "Set a scene-aware randomized review camera angle. Pass seed for a reproducible angle.", .tier = .stable, .owner = .camera, .argument_policy = .fields, .input_schema = camera_random_schema, .fields = random_camera_fields },
    .{ .command_name = "play-scene", .mcp_tool_name = "play_scene", .title = "Play Scene", .description = "Save and launch the current scene through the editor Play Scene path.", .tier = .stable, .owner = .play, .argument_policy = .fields, .input_schema = play_scene_schema, .fields = play_scene_fields },
    .{ .command_name = "turntable-capture", .mcp_tool_name = "turntable_capture", .title = "Turntable Capture", .description = "Orbit the camera 360 degrees around the selected or named object at the current object distance and encode an MP4 or GIF.", .tier = .experimental, .owner = .capture, .argument_policy = .fields, .input_schema = turntable_capture_schema, .fields = turntable_fields },
    .{ .command_name = "architecture.building-create", .mcp_tool_name = "architecture_building_create", .title = "Create Plot-Local Building", .description = "Create a semantic architecture building under a plot root using local plot coordinates.", .tier = .stable, .owner = .architecture, .argument_policy = .fields, .input_schema = architecture_building_schema, .fields = architecture_building_fields },
    .{ .command_name = "architecture.wall-point", .mcp_tool_name = "architecture_wall_point", .title = "Place Wall Point", .description = "Place a point in the Architecture Wall outline tool using world coordinates.", .tier = .stable, .owner = .architecture, .argument_policy = .fields, .input_schema = wall_point_schema, .fields = point_fields },
    .{ .command_name = "architecture.door-cut", .mcp_tool_name = "architecture_door_cut", .title = "Cut Door", .description = "Cut a door into the selected wall segment using two world-coordinate points.", .tier = .stable, .owner = .architecture, .argument_policy = .fields, .input_schema = opening_schema, .fields = opening_fields },
    .{ .command_name = "architecture.window-cut", .mcp_tool_name = "architecture_window_cut", .title = "Cut Window", .description = "Cut a window into the selected wall segment using two world-coordinate points.", .tier = .stable, .owner = .architecture, .argument_policy = .fields, .input_schema = opening_schema, .fields = opening_fields },
    .{ .command_name = "architecture.network-create", .mcp_tool_name = "architecture_network_create", .title = "Create Wall Network", .description = "Create an empty plot-owned architecture wall network.", .tier = .stable, .owner = .architecture, .argument_policy = .fields, .input_schema = architecture_network_schema, .fields = architecture_network_fields },
    .{ .command_name = "architecture.network-delete", .mcp_tool_name = "architecture_network_delete", .title = "Delete Wall Network", .description = "Delete a wall network object by id or name.", .tier = .destructive, .owner = .architecture, .argument_policy = .fields, .input_schema = architecture_object_schema, .fields = object_fields },
    .{ .command_name = "architecture.node-add", .mcp_tool_name = "architecture_node_add", .title = "Add Architecture Node", .description = "Add a node to a wall network in local network coordinates.", .tier = .stable, .owner = .architecture, .argument_policy = .fields, .input_schema = architecture_node_schema, .fields = architecture_node_fields },
    .{ .command_name = "architecture.node-move", .mcp_tool_name = "architecture_node_move", .title = "Move Architecture Node", .description = "Move an existing wall network node.", .tier = .stable, .owner = .architecture, .argument_policy = .fields, .input_schema = architecture_node_schema, .fields = architecture_node_fields },
    .{ .command_name = "architecture.node-delete", .mcp_tool_name = "architecture_node_delete", .title = "Delete Architecture Node", .description = "Delete a node and all incident edges from a wall network.", .tier = .destructive, .owner = .architecture, .argument_policy = .fields, .input_schema = architecture_node_delete_schema, .fields = architecture_node_fields },
    .{ .command_name = "architecture.edge-add", .mcp_tool_name = "architecture_edge_add", .title = "Add Architecture Edge", .description = "Add a wall edge between two existing nodes.", .tier = .stable, .owner = .architecture, .argument_policy = .fields, .input_schema = architecture_edge_schema, .fields = architecture_edge_fields },
    .{ .command_name = "architecture.edge-split", .mcp_tool_name = "architecture_edge_split", .title = "Split Architecture Edge", .description = "Split a wall edge by inserting a node.", .tier = .stable, .owner = .architecture, .argument_policy = .fields, .input_schema = architecture_edge_split_schema, .fields = architecture_edge_split_fields },
    .{ .command_name = "architecture.edge-delete", .mcp_tool_name = "architecture_edge_delete", .title = "Delete Architecture Edge", .description = "Delete a wall edge and invalidate dependent shells, roofs, and openings.", .tier = .destructive, .owner = .architecture, .argument_policy = .fields, .input_schema = architecture_edge_id_schema, .fields = architecture_edge_id_fields },
    .{ .command_name = "architecture.shell-create", .mcp_tool_name = "architecture_shell_create", .title = "Create Architecture Shell", .description = "Create a closed shell from ordered wall ids.", .tier = .stable, .owner = .architecture, .argument_policy = .fields, .input_schema = architecture_shell_schema, .fields = architecture_shell_fields },
    .{ .command_name = "architecture.shell-delete", .mcp_tool_name = "architecture_shell_delete", .title = "Delete Architecture Shell", .description = "Delete a shell by id while keeping its walls.", .tier = .destructive, .owner = .architecture, .argument_policy = .fields, .input_schema = architecture_id_schema, .fields = architecture_edge_id_fields },
    .{ .command_name = "architecture.wall-height-set", .mcp_tool_name = "architecture_wall_height_set", .title = "Set Wall Height", .description = "Set explicit or floor-derived wall height for an edge.", .tier = .stable, .owner = .architecture, .argument_policy = .fields, .input_schema = architecture_wall_height_schema, .fields = architecture_wall_height_fields },
    .{ .command_name = "architecture.floor-set", .mcp_tool_name = "architecture_floor_set", .title = "Set Architecture Floors", .description = "Set network floor count, height, and slab thickness.", .tier = .stable, .owner = .architecture, .argument_policy = .fields, .input_schema = architecture_floor_schema, .fields = architecture_floor_fields },
    .{ .command_name = "architecture.foundation-create", .mcp_tool_name = "architecture_foundation_create", .title = "Create Foundation", .description = "Create a flat foundation lattice footprint that samples terrain for its underside.", .tier = .stable, .owner = .architecture, .argument_policy = .fields, .input_schema = architecture_foundation_schema, .fields = architecture_foundation_fields },
    .{ .command_name = "architecture.foundation-update", .mcp_tool_name = "architecture_foundation_update", .title = "Update Foundation", .description = "Replace a foundation footprint and elevation settings.", .tier = .stable, .owner = .architecture, .argument_policy = .fields, .input_schema = architecture_foundation_schema, .fields = architecture_foundation_fields },
    .{ .command_name = "architecture.foundation-delete", .mcp_tool_name = "architecture_foundation_delete", .title = "Delete Foundation", .description = "Delete a foundation by id.", .tier = .destructive, .owner = .architecture, .argument_policy = .fields, .input_schema = architecture_id_schema, .fields = architecture_edge_id_fields },
    .{ .command_name = "architecture.cutout-create", .mcp_tool_name = "architecture_cutout_create", .title = "Create Terrain Cutout", .description = "Create a rectangular terrain cutout volume for basements.", .tier = .stable, .owner = .architecture, .argument_policy = .fields, .input_schema = architecture_cutout_schema, .fields = architecture_cutout_fields },
    .{ .command_name = "architecture.cutout-update", .mcp_tool_name = "architecture_cutout_update", .title = "Update Terrain Cutout", .description = "Replace a terrain cutout volume.", .tier = .stable, .owner = .architecture, .argument_policy = .fields, .input_schema = architecture_cutout_schema, .fields = architecture_cutout_fields },
    .{ .command_name = "architecture.cutout-delete", .mcp_tool_name = "architecture_cutout_delete", .title = "Delete Terrain Cutout", .description = "Delete a terrain cutout by id.", .tier = .destructive, .owner = .architecture, .argument_policy = .fields, .input_schema = architecture_id_schema, .fields = architecture_edge_id_fields },
    .{ .command_name = "architecture.roof-set", .mcp_tool_name = "architecture_roof_set", .title = "Set Shell Roof", .description = "Set the roof kind for a closed shell network.", .tier = .stable, .owner = .architecture, .argument_policy = .fields, .input_schema = architecture_roof_schema, .fields = architecture_roof_fields },
    .{ .command_name = "architecture.roof-delete", .mcp_tool_name = "architecture_roof_delete", .title = "Delete Shell Roof", .description = "Remove roof settings from a network.", .tier = .destructive, .owner = .architecture, .argument_policy = .fields, .input_schema = architecture_object_schema, .fields = object_fields },
    .{ .command_name = "architecture.opening-create", .mcp_tool_name = "architecture_opening_create", .title = "Create Wall Opening", .description = "Create a door, window, arch, or cutout opening on a wall edge.", .tier = .stable, .owner = .architecture, .argument_policy = .fields, .input_schema = architecture_opening_schema, .fields = architecture_opening_fields },
    .{ .command_name = "architecture.opening-update", .mcp_tool_name = "architecture_opening_update", .title = "Update Wall Opening", .description = "Replace an opening by id. Pass edge_a as the opening id.", .tier = .stable, .owner = .architecture, .argument_policy = .fields, .input_schema = architecture_opening_schema, .fields = architecture_opening_fields },
    .{ .command_name = "architecture.opening-delete", .mcp_tool_name = "architecture_opening_delete", .title = "Delete Wall Opening", .description = "Delete an opening by id. Pass edge_a as the opening id.", .tier = .destructive, .owner = .architecture, .argument_policy = .fields, .input_schema = architecture_id_schema, .fields = architecture_edge_id_fields },
    .{ .command_name = "architecture.network-describe", .mcp_tool_name = "architecture_network_describe", .title = "Describe Wall Network", .description = "Describe semantic wall network ids, counts, dependencies, and mesh summary.", .tier = .stable, .owner = .architecture, .argument_policy = .fields, .input_schema = architecture_object_schema, .fields = object_fields },
    .{ .command_name = "architecture.network-validate", .mcp_tool_name = "architecture_network_validate", .title = "Validate Wall Network", .description = "Validate wall network connectivity, shells, openings, and outward normals.", .tier = .stable, .owner = .architecture, .argument_policy = .fields, .input_schema = architecture_object_schema, .fields = object_fields },
    .{ .command_name = "road.network-describe", .mcp_tool_name = "road_network_describe", .title = "Describe Road Network", .description = "Describe world-layer road graph counts, bounds, layer modes, and dirty state.", .tier = .stable, .owner = .world, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "road.network-validate", .mcp_tool_name = "road_network_validate", .title = "Validate Road Network", .description = "Validate road graph connectivity, ids, widths, lengths, junction candidates, and conforming terrain.", .tier = .stable, .owner = .world, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "road.graph-list", .mcp_tool_name = "road_graph_list", .title = "List Road Graph", .description = "List road graph nodes and edges with pagination for large worlds.", .tier = .stable, .owner = .world, .argument_policy = .fields, .input_schema = road_graph_list_schema, .fields = road_graph_list_fields },
    .{ .command_name = "road.node-add", .mcp_tool_name = "road_node_add", .title = "Add Road Node", .description = "Add a road graph node at a world point.", .tier = .stable, .owner = .world, .argument_policy = .fields, .input_schema = road_node_schema, .fields = road_node_fields },
    .{ .command_name = "road.node-move", .mcp_tool_name = "road_node_move", .title = "Move Road Node", .description = "Move an existing road graph node.", .tier = .stable, .owner = .world, .argument_policy = .fields, .input_schema = road_node_schema, .fields = road_node_fields },
    .{ .command_name = "road.node-delete", .mcp_tool_name = "road_node_delete", .title = "Delete Road Node", .description = "Delete a road node and all incident road edges.", .tier = .destructive, .owner = .world, .argument_policy = .fields, .input_schema = road_object_schema, .fields = object_fields },
    .{ .command_name = "road.node-promote-junction", .mcp_tool_name = "road_node_promote_junction", .title = "Promote Road Junction", .description = "Promote a road endpoint to an explicit junction.", .tier = .stable, .owner = .world, .argument_policy = .fields, .input_schema = road_object_schema, .fields = object_fields },
    .{ .command_name = "road.node-merge", .mcp_tool_name = "road_node_merge", .title = "Merge Road Nodes", .description = "Merge one road node into another and retarget connected edges.", .tier = .stable, .owner = .world, .argument_policy = .fields, .input_schema = road_node_merge_schema, .fields = road_node_merge_fields },
    .{ .command_name = "road.edge-add", .mcp_tool_name = "road_edge_add", .title = "Add Road Edge", .description = "Add a road graph edge between two existing road nodes.", .tier = .stable, .owner = .world, .argument_policy = .fields, .input_schema = road_edge_schema, .fields = road_edge_fields },
    .{ .command_name = "road.edge-update", .mcp_tool_name = "road_edge_update", .title = "Update Road Edge", .description = "Update road edge width, nodes, material, render mode, terrain mode, and elevation.", .tier = .stable, .owner = .world, .argument_policy = .fields, .input_schema = road_edge_update_schema, .fields = road_edge_fields },
    .{ .command_name = "road.edge-delete", .mcp_tool_name = "road_edge_delete", .title = "Delete Road Edge", .description = "Delete a road edge and remove orphan endpoint nodes.", .tier = .destructive, .owner = .world, .argument_policy = .fields, .input_schema = road_object_schema, .fields = object_fields },
    .{ .command_name = "road.edge-split", .mcp_tool_name = "road_edge_split", .title = "Split Road Edge", .description = "Split a road edge by inserting a junction node and a second edge.", .tier = .stable, .owner = .world, .argument_policy = .fields, .input_schema = road_edge_split_schema, .fields = road_edge_split_fields },
    .{ .command_name = "prop.open", .mcp_tool_name = "prop_open", .title = "Open Prop Asset", .description = "Open an existing prop asset for editing.", .tier = .stable, .owner = .prop, .argument_policy = .fields, .input_schema = object_schema, .fields = object_fields },
    .{ .command_name = "prop.new", .mcp_tool_name = "prop_new", .title = "Create Prop Asset", .description = "Create a new custom prop asset. Fails if the asset id already exists.", .tier = .stable, .owner = .prop, .argument_policy = .fields, .input_schema = object_schema, .fields = object_fields },
    .{ .command_name = "prop.modify", .mcp_tool_name = "prop_modify", .title = "Modify Prop Asset", .description = "Open an existing custom prop asset for intentional modification.", .tier = .stable, .owner = .prop, .argument_policy = .fields, .input_schema = object_schema, .fields = object_fields },
    .{ .command_name = "prop.metadata", .mcp_tool_name = "prop_metadata", .title = "Set Prop Metadata", .description = "Set metadata on the active prop asset. Pass object as label|tags.", .tier = .stable, .owner = .prop, .argument_policy = .fields, .input_schema = object_schema, .fields = object_fields },
    .{ .command_name = "prop.delete", .mcp_tool_name = "prop_delete", .title = "Delete Prop Asset", .description = "Mark a prop asset deleted by asset id, or the selected prop when omitted.", .tier = .destructive, .owner = .prop, .argument_policy = .fields, .input_schema = optional_object_schema, .fields = object_fields },
    .{ .command_name = "prop.restore", .mcp_tool_name = "prop_restore", .title = "Restore Prop Asset", .description = "Restore a deleted prop asset by asset id, or the selected prop when omitted.", .tier = .stable, .owner = .prop, .argument_policy = .fields, .input_schema = optional_object_schema, .fields = object_fields },
    .{ .command_name = "prop.mesh-clear", .mcp_tool_name = "prop_mesh_clear", .title = "Clear Prop Mesh", .description = "Explicitly clear the selected prop asset mesh before rebuilding it.", .tier = .destructive, .owner = .prop, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "prop.primitive-seed-add", .mcp_tool_name = "prop_primitive_seed_add", .title = "Add Prop Primitive Seed", .description = "Append a primitive seed source through the shared shape source and operation evaluator.", .tier = .experimental, .owner = .prop, .argument_policy = .fields, .input_schema = prop_primitive_seed_schema, .fields = prop_primitive_seed_fields },
    .{ .command_name = "prop.mesh-mirror", .mcp_tool_name = "prop_mesh_mirror", .title = "Mirror Prop Mesh", .description = "Mirror the selected prop mesh across local X using the shared shape operation evaluator.", .tier = .experimental, .owner = .prop, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "prop.mesh-array", .mcp_tool_name = "prop_mesh_array", .title = "Array Prop Mesh", .description = "Add one ordered X-axis array copy of the selected prop mesh using the shared shape operation evaluator.", .tier = .experimental, .owner = .prop, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "prop.mesh-ellipsoid", .mcp_tool_name = "prop_mesh_ellipsoid", .title = "Add Prop Ellipsoid", .description = "Append a low-poly ellipsoid to the selected prop mesh. Pass object as x,y,z,rx,ry,rz,segments,rings.", .tier = .experimental, .owner = .prop, .argument_policy = .fields, .input_schema = object_schema, .fields = object_fields },
    .{ .command_name = "prop.mesh-cone", .mcp_tool_name = "prop_mesh_cone", .title = "Add Prop Cone", .description = "Append a low-poly cone to the selected prop mesh. Pass object as x,y,z,nx,ny,nz,radius,height,segments.", .tier = .experimental, .owner = .prop, .argument_policy = .fields, .input_schema = object_schema, .fields = object_fields },
    .{ .command_name = "prop.mesh-oval-slab", .mcp_tool_name = "prop_mesh_oval_slab", .title = "Add Prop Oval Slab", .description = "Append a low-poly oval slab to the selected prop mesh. Pass object as px,py,pz,qx,qy,qz,qw,rx,ry,depth,segments.", .tier = .experimental, .owner = .prop, .argument_policy = .fields, .input_schema = object_schema, .fields = object_fields },
    .{ .command_name = "prop.source-sphere-add", .mcp_tool_name = "prop_source_sphere_add", .title = "Add Prop Source Sphere", .description = "Add a strict recipe sphere source to the selected prop asset.", .tier = .stable, .owner = .prop, .argument_policy = .strict_json_object, .input_schema = prop_source_sphere_schema },
    .{ .command_name = "prop.source-transform-update", .mcp_tool_name = "prop_source_transform_update", .title = "Update Prop Source Transform", .description = "Update position, rotation, and/or scale for an existing recipe source.", .tier = .stable, .owner = .prop, .argument_policy = .strict_json_object, .input_schema = prop_source_transform_schema },
    .{ .command_name = "prop.source-delete", .mcp_tool_name = "prop_source_delete", .title = "Delete Prop Source", .description = "Delete an existing recipe source and its attached modifiers.", .tier = .destructive, .owner = .prop, .argument_policy = .strict_json_object, .input_schema = prop_source_delete_schema },
    .{ .command_name = "prop.modifier-bend-add", .mcp_tool_name = "prop_modifier_bend_add", .title = "Add Prop Bend Modifier", .description = "Attach a bend modifier to an existing prop recipe source.", .tier = .stable, .owner = .prop, .argument_policy = .strict_json_object, .input_schema = prop_modifier_axis_schema },
    .{ .command_name = "prop.modifier-taper-add", .mcp_tool_name = "prop_modifier_taper_add", .title = "Add Prop Taper Modifier", .description = "Attach a taper modifier to an existing prop recipe source.", .tier = .stable, .owner = .prop, .argument_policy = .strict_json_object, .input_schema = prop_modifier_axis_schema },
    .{ .command_name = "prop.modifier-lattice-add", .mcp_tool_name = "prop_modifier_lattice_add", .title = "Add Prop Lattice Modifier", .description = "Attach a lattice modifier to an existing prop recipe source.", .tier = .stable, .owner = .prop, .argument_policy = .strict_json_object, .input_schema = prop_modifier_lattice_schema },
    .{ .command_name = "prop.modifier-update", .mcp_tool_name = "prop_modifier_update", .title = "Update Prop Modifier", .description = "Replace an existing modifier intentionally. Include kind and the full modifier fields for that kind.", .tier = .stable, .owner = .prop, .argument_policy = .strict_json_object, .input_schema = prop_modifier_update_schema },
    .{ .command_name = "prop.modifier-delete", .mcp_tool_name = "prop_modifier_delete", .title = "Delete Prop Modifier", .description = "Delete an existing prop recipe modifier.", .tier = .destructive, .owner = .prop, .argument_policy = .strict_json_object, .input_schema = prop_modifier_delete_schema },
    .{ .command_name = "prop.recipe-rebake", .mcp_tool_name = "prop_recipe_rebake", .title = "Rebake Prop Recipe", .description = "Rebuild the selected prop mesh from its strict source/modifier recipe.", .tier = .stable, .owner = .prop, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "prop.material-object", .mcp_tool_name = "prop_material_object", .title = "Set Prop Object Material", .description = "Set the selected prop asset object material path, preview color, and texture transform.", .tier = .stable, .owner = .prop, .argument_policy = .fields, .input_schema = prop_material_object_schema, .fields = material_object_fields },
    .{ .command_name = "prop.material-face", .mcp_tool_name = "prop_material_face", .title = "Set Prop Face Material", .description = "Assign a material path, preview color, and texture transform to a face index on the selected prop asset.", .tier = .stable, .owner = .prop, .argument_policy = .fields, .input_schema = prop_material_face_schema, .fields = material_face_fields },
    .{ .command_name = "prop.texture-fill", .mcp_tool_name = "prop_texture_fill", .title = "Fill Prop Texture", .description = "Fill the selected prop asset texture with a solid RGBA color and persist it.", .tier = .stable, .owner = .prop, .argument_policy = .fields, .input_schema = prop_texture_fill_schema, .fields = texture_fill_fields },
    .{ .command_name = "prop.texture-quality", .mcp_tool_name = "prop_texture_quality", .title = "Set Prop Texture Quality", .description = "Set Prop Paint texture detail. Pass object as 1x, 2x, or 4x.", .tier = .stable, .owner = .prop, .argument_policy = .fields, .input_schema = prop_texture_quality_schema, .fields = object_fields },
    .{ .command_name = "prop.texture-unwrap", .mcp_tool_name = "prop_texture_unwrap", .title = "Unwrap Prop Paint Atlas", .description = "Generate a non-overlapping xatlas paint atlas for the selected prop asset and persist it.", .tier = .stable, .owner = .prop, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "prop.texture-paint-uv", .mcp_tool_name = "prop_texture_paint_uv", .title = "Paint Prop Texture UV", .description = "Paint the selected prop asset texture at a UV coordinate with RGBA color and brush options.", .tier = .stable, .owner = .prop, .argument_policy = .fields, .input_schema = prop_texture_paint_uv_schema, .fields = texture_paint_fields },
    .{ .command_name = "concept-paint.capture", .mcp_tool_name = "concept_paint_capture", .title = "Capture Concept Paint Session", .description = "Record the current camera and a viewport screenshot path for concept paint projection.", .tier = .experimental, .owner = .concept_paint, .argument_policy = .fields, .input_schema = concept_paint_capture_schema, .fields = concept_paint_capture_fields },
    .{ .command_name = "concept-paint.import-styled", .mcp_tool_name = "concept_paint_import_styled", .title = "Import Styled Concept Image", .description = "Attach a styled PNG/JPEG to the active concept paint session.", .tier = .experimental, .owner = .concept_paint, .argument_policy = .fields, .input_schema = concept_paint_import_schema, .fields = concept_paint_import_fields },
    .{ .command_name = "concept-paint.describe", .mcp_tool_name = "concept_paint_describe", .title = "Describe Concept Paint Session", .description = "Return active concept paint session metadata, target scope, and readiness.", .tier = .experimental, .owner = .concept_paint, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "concept-paint.request-package", .mcp_tool_name = "concept_paint_request_package", .title = "Write Concept Paint Provider Package", .description = "Write a JSON request package for an external image provider. Fails when provider is missing.", .tier = .experimental, .owner = .concept_paint, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "concept-paint.apply", .mcp_tool_name = "concept_paint_apply", .title = "Apply Concept Paint Stencil", .description = "Bake the imported styled concept image into editable surfaces for the active mode scope.", .tier = .experimental, .owner = .concept_paint, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "concept-paint.clear", .mcp_tool_name = "concept_paint_clear", .title = "Clear Concept Paint Session", .description = "Clear the active concept paint session and preview metadata.", .tier = .experimental, .owner = .concept_paint, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "prop.sketch-point", .mcp_tool_name = "prop_sketch_point", .title = "Place Prop Sketch Point", .description = "Place a point in the active Prop Shape face sketch using world coordinates.", .tier = .experimental, .owner = .prop, .argument_policy = .fields, .input_schema = wall_point_schema, .fields = point_fields },
    .{ .command_name = "prop.sketch-profile-point", .mcp_tool_name = "prop_sketch_profile_point", .title = "Place Prop Profile Point", .description = "Place a point in the active Prop Shape profile sketch using world coordinates for a revolve operation.", .tier = .experimental, .owner = .prop, .argument_policy = .fields, .input_schema = wall_point_schema, .fields = point_fields },
    .{ .command_name = "prop.sketch-path-point", .mcp_tool_name = "prop_sketch_path_point", .title = "Place Prop Path Point", .description = "Place a point in the active Prop Shape path source using world coordinates.", .tier = .experimental, .owner = .prop, .argument_policy = .fields, .input_schema = wall_point_schema, .fields = point_fields },
    .{ .command_name = "prop.sketch-point-update", .mcp_tool_name = "prop_sketch_point_update", .title = "Update Prop Sketch Point", .description = "Move one point in the active Prop Shape source without clearing the editable source.", .tier = .experimental, .owner = .prop, .argument_policy = .fields, .input_schema = prop_sketch_point_update_schema, .fields = prop_sketch_point_update_fields },
    .{ .command_name = "prop.sketch-clear", .mcp_tool_name = "prop_sketch_clear", .title = "Clear Prop Sketch", .description = "Clear the current Prop Shape sketch draft points.", .tier = .destructive, .owner = .prop, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "prop.sketch-operation", .mcp_tool_name = "prop_sketch_operation", .title = "Set Prop Sketch Operation", .description = "Set the active Prop Shape operation amount and revolve segment count before committing the source.", .tier = .experimental, .owner = .prop, .argument_policy = .fields, .input_schema = prop_sketch_operation_schema, .fields = prop_sketch_operation_fields },
    .{ .command_name = "prop.sketch-extrude", .mcp_tool_name = "prop_sketch_extrude", .title = "Extrude Prop Path", .description = "Extrude the current Prop Shape path sketch into editable rail geometry.", .tier = .experimental, .owner = .prop, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "prop.sketch-solidify", .mcp_tool_name = "prop_sketch_solidify", .title = "Solidify Prop Sketch", .description = "Solidify the current Prop Shape face sketch into prop geometry.", .tier = .experimental, .owner = .prop, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "prop.sketch-inset", .mcp_tool_name = "prop_sketch_inset", .title = "Inset Prop Sketch", .description = "Inset the current Prop Shape face sketch into editable prop geometry.", .tier = .experimental, .owner = .prop, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "prop.sketch-bevel", .mcp_tool_name = "prop_sketch_bevel", .title = "Bevel Prop Sketch", .description = "Bevel the current Prop Shape face sketch into editable prop geometry.", .tier = .experimental, .owner = .prop, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "prop.sketch-cut", .mcp_tool_name = "prop_sketch_cut", .title = "Cut Prop Sketch", .description = "Turn the current Prop Shape face sketch into a subtractive cut volume.", .tier = .experimental, .owner = .prop, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "prop.sketch-revolve", .mcp_tool_name = "prop_sketch_revolve", .title = "Revolve Prop Sketch", .description = "Revolve the current Prop Shape profile sketch into prop geometry.", .tier = .experimental, .owner = .prop, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "prop.render-mode", .mcp_tool_name = "prop_render_mode", .title = "Set Prop Render Mode", .description = "Set Prop Edit render mode. Pass object as wireframe, solid, material_preview, or rendered. Legacy aliases wire, unlit, lit, and full are accepted.", .tier = .stable, .owner = .prop, .argument_policy = .fields, .input_schema = object_schema, .fields = object_fields },
    .{ .command_name = "screenshot-editor", .mcp_tool_name = "screenshot_editor", .title = "Screenshot Editor", .description = "Capture the full editor window and return the PNG path.", .tier = .stable, .owner = .capture, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "screenshot-viewport", .mcp_tool_name = "screenshot_viewport", .title = "Screenshot Viewport", .description = "Capture the 3D viewport and return the PNG path.", .tier = .stable, .owner = .capture, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "screenshot-viewport-clean", .mcp_tool_name = "screenshot_viewport_clean", .title = "Screenshot Clean Viewport", .description = "Capture the 3D viewport before editor overlays, toolbar, and UI are drawn.", .tier = .stable, .owner = .capture, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "map.top-down-capture", .mcp_tool_name = "map_top_down_capture", .title = "Capture Top-Down Map", .description = "Frame the active world from above and capture the current 3D viewport as a PNG.", .tier = .stable, .owner = .capture, .argument_policy = .empty, .input_schema = empty_schema },
    .{ .command_name = "focus-in-viewport", .mcp_tool_name = "focus_in_viewport", .title = "Focus In Viewport", .description = "Turn the editor camera toward an object by id or name.", .tier = .stable, .owner = .camera, .argument_policy = .fields, .input_schema = object_schema, .fields = object_fields },
    .{ .command_name = "zoom-to-focus", .mcp_tool_name = "zoom_to_focus", .title = "Zoom To Focus", .description = "Move the editor camera close to an object by id or name.", .tier = .stable, .owner = .camera, .argument_policy = .fields, .input_schema = object_schema, .fields = object_fields },
    .{ .command_name = "perf.describe", .mcp_tool_name = "perf_describe", .title = "Describe Performance", .description = "Return editor frame timing and render performance metrics.", .tier = .stable, .owner = .editor, .argument_policy = .empty, .input_schema = empty_schema },
};

pub const exposed_count = countExposed();

fn countExposed() usize {
    comptime var count: usize = 0;
    inline for (entries) |entry| {
        if (entry.exposedToMcp()) count += 1;
    }
    return count;
}

pub fn findByMcpToolName(name: []const u8) ?Entry {
    for (entries) |entry| {
        if (entry.exposedToMcp() and std.mem.eql(u8, entry.mcp_tool_name, name)) return entry;
    }
    return null;
}

pub fn findByCommandName(name: []const u8) ?Entry {
    for (entries) |entry| {
        if (std.mem.eql(u8, entry.command_name, name)) return entry;
    }
    return null;
}

test "editor control command registry has unique command and MCP names" {
    for (entries, 0..) |entry, idx| {
        try std.testing.expect(entry.command_name.len > 0);
        try std.testing.expect(entry.mcp_tool_name.len > 0);
        try std.testing.expect(entry.title.len > 0);
        try std.testing.expect(entry.description.len > 0);
        try std.testing.expect(entry.owner.label().len > 0);
        try std.testing.expect(entry.tier.label().len > 0);

        for (entries[idx + 1 ..]) |other| {
            try std.testing.expect(!std.mem.eql(u8, entry.command_name, other.command_name));
            try std.testing.expect(!std.mem.eql(u8, entry.mcp_tool_name, other.mcp_tool_name));
        }
    }
}

test "every exposed MCP tool maps to one editor command" {
    const seen = comptime blk: {
        var count: usize = 0;
        for (entries) |entry| {
            if (entry.tier != .internal) count += 1;
        }
        break :blk count;
    };
    for (entries) |entry| {
        if (entry.exposedToMcp()) {
            try std.testing.expect(findByMcpToolName(entry.mcp_tool_name) != null);
            try std.testing.expect(findByCommandName(entry.command_name) != null);
        }
    }
    try std.testing.expectEqual(exposed_count, seen);
}

test "selection scope cycle is exposed as stable MCP command" {
    const entry = findByMcpToolName("selection_scope_cycle").?;
    try std.testing.expectEqualStrings("selection.scope-cycle", entry.command_name);
    try std.testing.expectEqual(ExposureTier.stable, entry.tier);
    try std.testing.expectEqual(Owner.selection, entry.owner);
    try std.testing.expectEqual(ArgumentPolicy.empty, entry.argument_policy);
}

test "prop path sketch command is exposed for MCP drawing" {
    const entry = findByMcpToolName("prop_sketch_path_point").?;
    try std.testing.expectEqualStrings("prop.sketch-path-point", entry.command_name);
    try std.testing.expectEqual(ExposureTier.experimental, entry.tier);
    try std.testing.expectEqual(Owner.prop, entry.owner);
    try std.testing.expectEqual(ArgumentPolicy.fields, entry.argument_policy);
}

test "prop sketch point update command is exposed for editable sources" {
    const entry = findByMcpToolName("prop_sketch_point_update").?;
    try std.testing.expectEqualStrings("prop.sketch-point-update", entry.command_name);
    try std.testing.expectEqual(ExposureTier.experimental, entry.tier);
    try std.testing.expectEqual(Owner.prop, entry.owner);
    try std.testing.expectEqual(ArgumentPolicy.fields, entry.argument_policy);
    try std.testing.expect(std.mem.indexOf(u8, entry.input_schema, "\"vertex\"") != null);
}

test "prop path extrude command is exposed for MCP shaping" {
    const entry = findByMcpToolName("prop_sketch_extrude").?;
    try std.testing.expectEqualStrings("prop.sketch-extrude", entry.command_name);
    try std.testing.expectEqual(ExposureTier.experimental, entry.tier);
    try std.testing.expectEqual(Owner.prop, entry.owner);
    try std.testing.expectEqual(ArgumentPolicy.empty, entry.argument_policy);
    try std.testing.expect(std.mem.indexOf(u8, entry.description, "path sketch") != null);
}

test "prop sketch operation command is exposed for MCP parameter editing" {
    const entry = findByMcpToolName("prop_sketch_operation").?;
    try std.testing.expectEqualStrings("prop.sketch-operation", entry.command_name);
    try std.testing.expectEqual(ExposureTier.experimental, entry.tier);
    try std.testing.expectEqual(Owner.prop, entry.owner);
    try std.testing.expectEqual(ArgumentPolicy.fields, entry.argument_policy);
    try std.testing.expect(std.mem.indexOf(u8, entry.input_schema, "\"amount\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, entry.input_schema, "\"segments\"") != null);
}

test "prop cut sketch command is exposed for MCP shaping" {
    const entry = findByMcpToolName("prop_sketch_cut").?;
    try std.testing.expectEqualStrings("prop.sketch-cut", entry.command_name);
    try std.testing.expectEqual(ExposureTier.experimental, entry.tier);
    try std.testing.expectEqual(Owner.prop, entry.owner);
    try std.testing.expectEqual(ArgumentPolicy.empty, entry.argument_policy);
    try std.testing.expect(std.mem.indexOf(u8, entry.description, "subtractive cut volume") != null);
}

test "prop mirror and array mesh commands are exposed for MCP shaping" {
    const mirror = findByMcpToolName("prop_mesh_mirror").?;
    try std.testing.expectEqualStrings("prop.mesh-mirror", mirror.command_name);
    try std.testing.expectEqual(ExposureTier.experimental, mirror.tier);
    try std.testing.expectEqual(Owner.prop, mirror.owner);
    try std.testing.expectEqual(ArgumentPolicy.empty, mirror.argument_policy);

    const array = findByMcpToolName("prop_mesh_array").?;
    try std.testing.expectEqualStrings("prop.mesh-array", array.command_name);
    try std.testing.expectEqual(ExposureTier.experimental, array.tier);
    try std.testing.expectEqual(Owner.prop, array.owner);
    try std.testing.expectEqual(ArgumentPolicy.empty, array.argument_policy);
}

test "prop primitive seed command is exposed for MCP shape sources" {
    const entry = findByMcpToolName("prop_primitive_seed_add").?;
    try std.testing.expectEqualStrings("prop.primitive-seed-add", entry.command_name);
    try std.testing.expectEqual(ExposureTier.experimental, entry.tier);
    try std.testing.expectEqual(Owner.prop, entry.owner);
    try std.testing.expectEqual(ArgumentPolicy.fields, entry.argument_policy);
    try std.testing.expect(std.mem.indexOf(u8, entry.input_schema, "\"primitive\"") != null);
}

test "prop inset and bevel sketch commands are exposed for MCP shaping" {
    const inset = findByMcpToolName("prop_sketch_inset").?;
    try std.testing.expectEqualStrings("prop.sketch-inset", inset.command_name);
    try std.testing.expectEqual(ExposureTier.experimental, inset.tier);
    try std.testing.expectEqual(Owner.prop, inset.owner);
    try std.testing.expectEqual(ArgumentPolicy.empty, inset.argument_policy);

    const bevel = findByMcpToolName("prop_sketch_bevel").?;
    try std.testing.expectEqualStrings("prop.sketch-bevel", bevel.command_name);
    try std.testing.expectEqual(ExposureTier.experimental, bevel.tier);
    try std.testing.expectEqual(Owner.prop, bevel.owner);
    try std.testing.expectEqual(ArgumentPolicy.empty, bevel.argument_policy);
}
