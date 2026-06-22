const std = @import("std");
const builtin = @import("builtin");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const editor_math = shared.editor_math;
const geometry = shared.geometry;
const shared_color = shared.color;
const scene_io = shared.scene_io;
const editor_display = @import("editor_display.zig");
const editor_draw = @import("editor_draw.zig");
const editor_gesture = @import("editor_gesture.zig");
const editor_selection = @import("editor_selection.zig");
const editor_viewport_gpu = @import("editor_viewport_gpu.zig");
const scene_object = @import("editor_scene_object.zig");
const project_editor_types = @import("project_editor_types.zig");
const project_editor_scene = @import("project_editor_scene.zig");
const project_editor_edit = @import("project_editor_edit.zig");
const project_editor_input = @import("project_editor_input.zig");
const project_editor_render = @import("project_editor_render.zig");
const editor_core_ui = @import("editor_core_ui.zig");
const project_editor_dirty_cells = @import("project_editor_dirty_cells.zig");
const project_editor_terrain_preview = @import("project_editor_terrain_preview.zig");
const project_editor_world_authoring_terrain_batch = @import("project_editor_world_authoring_terrain_batch.zig");
const project_editor_world_authoring_terrain_edge = @import("project_editor_world_authoring_terrain_edge.zig");
const project_editor_world_authoring_terrain_recipe = @import("project_editor_world_authoring_terrain_recipe.zig");
const project_editor_world_authoring_terrain_stretch_smooth = @import("project_editor_world_authoring_terrain_stretch_smooth.zig");
const project_editor_spline_preview = @import("project_editor_spline_preview.zig");
const project_editor_materials = @import("project_editor_materials.zig");
const project_editor_prop_asset = @import("project_editor_prop_asset.zig");
const project_editor_life = @import("project_editor_life.zig");
const project_editor_skinning = @import("project_editor_skinning.zig");
const editor_frame_perf = @import("editor_frame_perf.zig");
const project_editor_mode_config = @import("project_editor_mode_config.zig");
const project_editor_mode_gems = @import("project_editor_mode_gems.zig");

pub const SceneObject = scene_object.SceneObject;
pub const EditorMode = project_editor_types.EditorMode;
pub const BlockoutOp = project_editor_types.BlockoutOp;
pub const EditorAction = project_editor_types.EditorAction;
pub const PropField = project_editor_types.PropField;
pub const LeftRailTab = project_editor_types.LeftRailTab;
pub const ObjectTool = project_editor_types.ObjectTool;
pub const EditTool = project_editor_types.EditTool;
pub const ArchitectureTool = project_editor_types.ArchitectureTool;
pub const BlockoutBrushShape = project_editor_types.BlockoutBrushShape;
pub const PropTool = project_editor_types.PropTool;
pub const PropWorkspaceMode = project_editor_types.PropWorkspaceMode;
pub const PendingPropDialogKind = project_editor_types.PendingPropDialogKind;
pub const PropLibrarySort = project_editor_types.PropLibrarySort;
pub const PropLibraryCategoryFilter = project_editor_types.PropLibraryCategoryFilter;
pub const PropLibrarySourceFilter = project_editor_types.PropLibrarySourceFilter;
pub const SceneObjectFilter = project_editor_types.SceneObjectFilter;
pub const SceneVisibilityFilter = project_editor_types.SceneVisibilityFilter;
pub const PropSketchMode = project_editor_types.PropSketchMode;
pub const TexturePaintBrush = project_editor_types.TexturePaintBrush;
pub const TexturePaintStencil = project_editor_types.TexturePaintStencil;
pub const PropPrimitive = project_editor_types.PropPrimitive;
pub const PropPlacementMode = project_editor_types.PropPlacementMode;
pub const LifeTool = project_editor_types.LifeTool;
pub const LifeInterpolation = project_editor_types.LifeInterpolation;
pub const WorldTool = project_editor_types.WorldTool;
pub const WorldLayerId = project_editor_types.WorldLayerId;
pub const WorldConfigTab = project_editor_types.WorldConfigTab;
pub const WorldGridScale = project_editor_types.WorldGridScale;
pub const GizmoAxis = project_editor_types.GizmoAxis;
pub const MoveAxis = project_editor_types.MoveAxis;
pub const ViewCameraMode = project_editor_types.ViewCameraMode;
pub const ViewOrientation = project_editor_types.ViewOrientation;
pub const ShadingMode = project_editor_types.ShadingMode;
pub const TransformSpace = project_editor_types.TransformSpace;
pub const PivotMode = project_editor_types.PivotMode;
pub const AssetSelection = project_editor_types.AssetSelection;
pub const EditChannel = project_editor_types.EditChannel;
pub const DragMode = project_editor_types.DragMode;
pub const CurveDrawMode = project_editor_types.CurveDrawMode;
pub const ViewNavControl = project_editor_types.ViewNavControl;
pub const PendingObjectDrag = project_editor_types.PendingObjectDrag;
pub const DirtyCellTracker = project_editor_dirty_cells.DirtyCellTracker;
pub const SelectionScope = editor_selection.Scope;

pub const ViewportOverlayPrimitiveKind = enum {
    pixel,
    line,
    square,
    rect,
};

pub const ViewportOverlayPrimitive = struct {
    kind: ViewportOverlayPrimitiveKind,
    color: shared_color.Color,
    x0: f32 = 0,
    y0: f32 = 0,
    x1: f32 = 0,
    y1: f32 = 0,
    w: f32 = 0,
    h: f32 = 0,
    half: i32 = 0,
};

pub const ViewportOverlayRecorder = struct {
    primitives: std.ArrayList(ViewportOverlayPrimitive) = .empty,

    pub fn deinit(self: *ViewportOverlayRecorder, allocator: std.mem.Allocator) void {
        self.primitives.deinit(allocator);
    }

    pub fn record(self: *ViewportOverlayRecorder, allocator: std.mem.Allocator, primitive: ViewportOverlayPrimitive) void {
        self.primitives.append(allocator, primitive) catch {};
    }

    pub fn countKind(self: *const ViewportOverlayRecorder, kind: ViewportOverlayPrimitiveKind) usize {
        var count: usize = 0;
        for (self.primitives.items) |primitive| {
            if (primitive.kind == kind) count += 1;
        }
        return count;
    }

    pub fn countColor(self: *const ViewportOverlayRecorder, color: shared_color.Color) usize {
        var count: usize = 0;
        for (self.primitives.items) |primitive| {
            if (colorsEqual(primitive.color, color)) count += 1;
        }
        return count;
    }
};

fn colorsEqual(a: shared_color.Color, b: shared_color.Color) bool {
    return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a;
}

pub const ProjectEditorState = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []u8,
    project_name: []u8,
    active_scene_path: []const u8 = &.{},
    active_world_manifest_path: []const u8 = &.{},
    active_scene_path_owned: bool = false,
    active_world_manifest_path_owned: bool = false,
    objects: std.ArrayList(SceneObject),
    selected_object: ?usize = null,
    selected_object_ids: std.ArrayList(u64) = .empty,
    scene_object_context_menu_open: bool = false,
    scene_object_context_menu_id: u64 = 0,
    scene_object_context_menu_x: f32 = 0,
    scene_object_context_menu_y: f32 = 0,
    selected_vertex: ?u32 = null,
    selected_edge: ?[2]u32 = null,
    selected_face: ?usize = null,
    selection_scope: SelectionScope = .object,
    selection_cycle_index: usize = 0,
    active_gesture: editor_gesture.Gesture = .{},
    hovered_object: ?usize = null,
    hovered_selection_scope: SelectionScope = .object,
    selected_shape_source: bool = false,
    selected_shape_operation: bool = false,
    hovered_shape_source: bool = false,
    hovered_shape_operation: bool = false,
    enabled_editor_modes: project_editor_mode_config.ModeFlags = project_editor_mode_config.defaultFlags(),
    mode: EditorMode = .world_creation,
    left_tab: LeftRailTab = .scene,
    object_tool: ObjectTool = .move,
    edit_tool: EditTool = .vertex,
    architecture_tool: ArchitectureTool = .brush,
    prop_workspace_mode: PropWorkspaceMode = .display,
    prop_tool: PropTool = .select,
    prop_primitive: PropPrimitive = .cube,
    prop_placement_mode: PropPlacementMode = .surface,
    prop_collider_preview: bool = true,
    prop_align_to_surface: bool = false,
    prop_random_yaw: bool = false,
    prop_drop_to_ground: bool = false,
    prop_loop_mode: bool = false,
    prop_sketch_mode: PropSketchMode = .face,
    prop_selected_asset: []const u8 = "crate_wood",
    prop_library_sort: PropLibrarySort = .name,
    prop_library_source_filter: PropLibrarySourceFilter = .all,
    prop_library_category_filter: PropLibraryCategoryFilter = .all,
    prop_library_tag_filter_buf: [64]u8 = [_]u8{0} ** 64,
    prop_library_tag_filter_len: usize = 0,
    prop_asset_index: std.ArrayList(project_editor_types.PropAssetIndexRow) = .empty,
    prop_asset_index_valid: bool = false,
    prop_delete_confirm_asset: ?[]const u8 = null,
    prop_metadata_editor_open: bool = false,
    active_prop_asset_id: ?[]u8 = null,
    prop_variant_index: u32 = 0,
    prop_placement_preview: ?editor_math.Vec3 = null,
    prop_placement_preview_bounds: ?struct { min: editor_math.Vec3, max: editor_math.Vec3 } = null,
    prop_preview_mesh: ?geometry.Mesh = null,
    prop_preview_mesh_id: ?[]u8 = null,
    prop_sketch_points: std.ArrayList(editor_math.Vec3) = .empty,
    prop_sketch_amount: f32 = 0.08,
    prop_sketch_segments: u32 = 24,
    prop_recent_ids: std.ArrayList([]u8) = .empty,
    life_tool: LifeTool = .select,
    world_tool: WorldTool = .terrain,
    world_config_tab: WorldConfigTab = .atmosphere,
    selected_world_layer: ?WorldLayerId = .terrain_base_height,
    selected_world_cell: ?friendly_engine.world.cell.CellId = null,
    selected_world_region_id: [64]u8 = [_]u8{0} ** 64,
    selected_world_region_id_len: usize = 0,
    world_region_context_menu_open: bool = false,
    world_region_context_menu_id: [64]u8 = [_]u8{0} ** 64,
    world_region_context_menu_id_len: usize = 0,
    world_region_context_menu_x: f32 = 0,
    world_region_context_menu_y: f32 = 0,
    viewport_context_menu_open: bool = false,
    viewport_context_menu_x: f32 = 0,
    viewport_context_menu_y: f32 = 0,
    viewport_context_menu_target: editor_math.Vec3 = .{ .x = 0, .y = 0, .z = 0 },
    world_region_rename_active: bool = false,
    world_region_rename_id: [64]u8 = [_]u8{0} ** 64,
    world_region_rename_id_len: usize = 0,
    selected_ocean_clip_point: ?usize = null,
    world_draw_distance_m: f32 = editor_math.editor_camera_far_m,
    world_brush_size: f32 = 8.0,
    world_brush_strength: f32 = 0.65,
    world_brush_falloff: f32 = 0.75,
    world_brush_material: u8 = 0,
    world_brush_tile: u8 = 0,
    world_affects_height: bool = true,
    world_affects_material: bool = true,
    world_region_paint_enabled: bool = false,
    world_region_paint_erase: bool = false,
    world_grid_scale: WorldGridScale = .one_m,
    world_cell_size_m: f32 = friendly_engine.world.cell.default_cell_size_m,
    terrain_batch_job: ?project_editor_types.TerrainBatchJob = null,
    terrain_edge_cliff_job: ?project_editor_types.TerrainEdgeCliffJob = null,
    terrain_recipe_job: ?project_editor_types.TerrainRecipeJob = null,
    terrain_stretch_smooth_job: ?project_editor_types.TerrainStretchSmoothJob = null,
    world_sky_visible: bool = true,
    world_ocean_visible: bool = true,
    world_fog_preview: bool = false,
    world_lighting_preview: bool = true,
    world_sun_enabled: bool = true,
    world_sun_azimuth_deg: f32 = 135.0,
    world_sun_elevation_deg: f32 = 48.0,
    world_moon_enabled: bool = false,
    world_moon_azimuth_deg: f32 = 315.0,
    world_moon_elevation_deg: f32 = 35.0,
    world_star_seed: u32 = 2745,
    world_clouds_enabled: bool = true,
    world_cloud_coverage: f32 = 0.42,
    world_cloud_softness: f32 = 0.68,
    world_cloud_scale: f32 = 0.85,
    world_cloud_height_bias: f32 = 0.55,
    world_cloud_drift_dir_x: f32 = 1.0,
    world_cloud_drift_dir_y: f32 = 0.18,
    world_cloud_drift_speed: f32 = 0.015,
    world_cloud_seed: u32 = 2745,
    world_cloud_parallax_enabled: bool = true,
    show_world_group: bool = true,
    show_world_cells_group: bool = true,
    show_world_terrain_group: bool = true,
    show_world_splines_group: bool = true,
    show_world_scatter_group: bool = true,
    show_world_atmosphere_group: bool = true,
    show_world_ocean_group: bool = true,
    show_world_water_group: bool = true,
    is_playing: bool = false,
    scene_dirty: bool = false,
    view_camera_mode: ViewCameraMode = .perspective,
    view_orientation: ViewOrientation = .free,
    shading_mode: ShadingMode = .rendered,
    shading_hotkey_open: bool = false,
    show_grid: bool = true,
    show_gizmo: bool = true,
    transform_space: TransformSpace = .world,
    pivot_mode: PivotMode = .pivot,
    show_scene_group: bool = true,
    scene_object_filter: SceneObjectFilter = .all,
    scene_visibility_filter: SceneVisibilityFilter = .all,
    scene_layer_filter_buf: [64]u8 = [_]u8{0} ** 64,
    scene_layer_filter_len: usize = 0,
    scene_tag_filter_buf: [64]u8 = [_]u8{0} ** 64,
    scene_tag_filter_len: usize = 0,
    object_enabled: bool = true,
    renderer_visible: bool = true,
    inspector_lock_uniform_scale: bool = true,
    world_fog_enabled: bool = false,
    world_fog_start_m: f32 = 8.0,
    world_fog_end_m: f32 = 80.0,
    world_fog_color_r: u8 = 0x88,
    world_fog_color_g: u8 = 0x94,
    world_fog_color_b: u8 = 0xa8,
    atmosphere_default_fog: friendly_engine.modules.atmosphere.FogBank = .{},
    atmosphere_cell_fogs: std.ArrayList(friendly_engine.modules.atmosphere.CellFogBank) = .empty,
    atmosphere_fog_edit_cell: friendly_engine.world.cell.CellId = .{ .x = 0, .y = 0, .z = 0 },
    ocean_sea_level_m: f32 = 0.0,
    ocean_render_min_distance_m: f32 = 1800.0,
    ocean_fade_in_start_m: f32 = 1400.0,
    ocean_fade_in_end_m: f32 = 2600.0,
    ocean_wind_enabled: bool = true,
    ocean_wind_direction_deg: f32 = 225.0,
    ocean_wind_speed_mps: f32 = 8.0,
    ocean_waves_amplitude_m: f32 = 0.8,
    ocean_waves_length_m: f32 = 42.0,
    ocean_waves_speed_mps: f32 = 6.0,
    water_surface_y: f32 = 0.0,
    water_bottom_y: f32 = -4.0,
    water_current_x: f32 = 0.0,
    water_current_y: f32 = 0.0,
    water_current_z: f32 = 0.0,
    water_swimmable: bool = true,
    water_linked_to_ocean: bool = false,
    world_measure_a: ?editor_math.Vec3 = null,
    world_measure_b: ?editor_math.Vec3 = null,
    world_road_mode: project_editor_types.RoadToolMode = .draw,
    world_road_draw_mode: project_editor_types.CurveDrawMode = .point_by_point,
    world_road_surface_mode: project_editor_types.RoadSurfaceMode = .decal,
    world_road_terrain_mode: project_editor_types.RoadTerrainMode = .conform,
    world_road_width: f32 = 4.0,
    world_road_shoulder_fade: f32 = 0.6,
    world_road_conform_offset: f32 = 0.08,
    world_road_prop_spacing: f32 = 4.0,
    selected_road_node_id: ?[]u8 = null,
    selected_road_edge_id: ?[]u8 = null,
    selected_road_handle: enum { none, start, end } = .none,
    hovered_world_curve_hit: project_editor_types.WorldCurveHit = .{},
    selected_world_curve_hit: project_editor_types.WorldCurveHit = .{},
    world_curve_drag_state: project_editor_types.WorldCurveDragState = .{},
    world_curve_drag_anchor: ?editor_math.Vec3 = null,
    world_road_points: std.ArrayList(editor_math.Vec3) = .empty,
    world_road_preview_end: ?editor_math.Vec3 = null,
    world_road_drag_anchor: ?editor_math.Vec3 = null,
    world_scatter_drag_start: ?editor_math.Vec3 = null,
    world_scatter_drag_end: ?editor_math.Vec3 = null,
    asset_grid_view: bool = false,
    selected_asset: AssetSelection = .mesh_box,
    blockout_op: BlockoutOp = .add,
    blockout_brush_shape: project_editor_types.BlockoutBrushShape = .box,
    blockout_brush_size: f32 = 1.0,
    architecture_floor_thickness: f32 = 0.12,
    architecture_wall_height: f32 = 3.0,
    architecture_wall_thickness: f32 = 0.25,
    architecture_door_height: f32 = 2.2,
    architecture_window_sill: f32 = 1.0,
    architecture_window_height: f32 = 1.0,
    architecture_curve_radius: f32 = 0.08,
    architecture_curve_surface_offset: f32 = 0.035,
    architecture_curve_draw_mode: project_editor_types.CurveDrawMode = .freehand,
    wall_outline_points: std.ArrayList(editor_math.Vec3) = .empty,
    architecture_curve_points: std.ArrayList(editor_math.Vec3) = .empty,
    architecture_curve_preview_end: ?editor_math.Vec3 = null,
    active_building_id: ?u64 = null,
    csg_preview_live: bool = true,
    snap_face: bool = false,
    show_arch_buildings: bool = true,
    show_arch_blockout: bool = true,
    show_arch_brushes: bool = true,
    show_arch_materials: bool = true,
    show_arch_collision: bool = true,
    blockout_drag_start: ?editor_math.Vec3 = null,
    blockout_drag_end: ?editor_math.Vec3 = null,
    blockout_resize_face: ?@import("project_editor_blockout_resize.zig").FaceAxis = null,
    blockout_resize_start: ?editor_math.Vec3 = null,
    blockout_resize_base_scale: ?editor_math.Vec3 = null,
    blockout_resize_preview: ?struct { w: f32, h: f32, d: f32 } = null,
    command_palette_open: bool = false,
    preferences_open: bool = false,
    command_palette_filter: [64]u8 = [_]u8{0} ** 64,
    command_palette_filter_len: usize = 0,
    command_palette_highlight: usize = 0,
    ui_tree_open: bool = false,
    show_tool_inspector: bool = true,
    show_project_inspector: bool = true,
    show_viewport_toolbar: bool = true,
    show_me_mode_enabled: bool = true,
    show_me_focus_radius: f32 = 12.0,
    show_cell_bounds: bool = true,
    baked_cell_count: usize = 0,
    camera: editor_math.OrbitCamera = .{},
    window_w: f32 = 1920,
    window_h: f32 = 1080,
    window: ?*editor_draw.SDL_Window = null,
    pending_prop_dialog_path_buf: [1024]u8 = undefined,
    pending_prop_dialog_path_len: std.atomic.Value(u16) = std.atomic.Value(u16).init(0),
    pending_prop_dialog_kind_atomic: std.atomic.Value(u8) = std.atomic.Value(u8).init(0),
    display_scale: f32 = 1,
    viewport_screen_rect: editor_draw.SDL_FRect = .{ .x = 0, .y = 0, .w = 640, .h = 480 },
    next_object_id: u64 = 1,
    status_buf: [256]u8 = [_]u8{0} ** 256,
    status_len: usize = 0,
    editor_error_title: ?[]u8 = null,
    editor_error_detail: ?[]u8 = null,
    mouse_x: f32 = 0,
    mouse_y: f32 = 0,
    keyboard_mods: u16 = 0,
    drag_mode: DragMode = .none,
    drag_last_x: f32 = 0,
    drag_last_y: f32 = 0,
    brush_color: shared_color.Color = .{ .r = 200, .g = 80, .b = 60, .a = 255 },
    selected_material: project_editor_materials.MaterialId = .red,
    brush_radius: f32 = 0.04,
    prop_texture_quality: u8 = 2,
    texture_paint_brush: TexturePaintBrush = .soft_round,
    texture_paint_stencil: TexturePaintStencil = .none,
    texture_paint_opacity: f32 = 1.0,
    texture_paint_hardness: f32 = 0.72,
    texture_paint_noise: f32 = 0.35,
    concept_paint_session: ?project_editor_types.ConceptPaintSession = null,
    should_quit: bool = false,
    should_close: bool = false,
    viewport_texture: ?*editor_draw.SDL_Texture = null,
    viewport_texture_w: u32 = 0,
    viewport_texture_h: u32 = 0,
    viewport_texture_gpu_source: ?*shared.sdl_gpu.SDL_GPUTexture = null,
    viewport_overlay_renderer: ?*editor_draw.SDL_Renderer = null,
    viewport_overlay_rect: editor_draw.SDL_FRect = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
    viewport_overlay_recorder: ?*ViewportOverlayRecorder = null,
    snap_enabled: bool = true,
    snap_size: f32 = 1.0,
    rotation_snap: f32 = 15.0,
    scale_snap: f32 = 0.1,
    camera_speed: f32 = 5.0,
    fps: f32 = 0,
    frame_perf: editor_frame_perf.FramePerf = .{},
    uses_gpu_viewport_texture: bool = false,
    uses_gpu_ui: bool = false,
    move_axis: MoveAxis = .xz,
    edit_channel: EditChannel = .position,
    undo_stack: std.ArrayList(project_editor_edit.SceneSnapshot) = .empty,
    redo_stack: std.ArrayList(project_editor_edit.SceneSnapshot) = .empty,
    undo_batch_depth: u32 = 0,
    undo_batch_snapshot_taken: bool = false,
    undo_batch_label_len: usize = 0,
    undo_batch_label_buf: [64]u8 = undefined,
    terrain_undo_limit_mb: u64 = 1024,
    drag_moved: bool = false,
    walk_mode: bool = false,
    walk_forward: bool = false,
    walk_back: bool = false,
    walk_left: bool = false,
    walk_right: bool = false,
    walk_up: bool = false,
    walk_down: bool = false,
    walk_fast: bool = false,
    focused_field: PropField = .none,
    field_input_buf: [32]u8 = [_]u8{0} ** 32,
    field_input_len: usize = 0,
    gizmo_drag_axis: ?GizmoAxis = null,
    pending_object_drag: PendingObjectDrag = .none,
    pending_gizmo_axis: ?GizmoAxis = null,
    active_view_nav: ViewNavControl = .none,
    click_start_x: f32 = 0,
    click_start_y: f32 = 0,
    selection_box_active: bool = false,
    selection_box_start: editor_math.Vec2 = .{ .x = 0, .y = 0 },
    selection_box_end: editor_math.Vec2 = .{ .x = 0, .y = 0 },
    render_command_stats: shared.render_commands.Stats = .{},
    control_stats: @import("editor_commands.zig").ControlStats = .{},
    visibility_stats: shared.render_visibility.VisibilityStats = .{},
    dirty_cells: DirtyCellTracker = .{},
    world_manifest_cache: ?friendly_engine.world.manifest.OwnedWorldManifest = null,
    world_regions_cache: ?friendly_engine.world.regions.OwnedRegions = null,
    terrain_index_cache: ?friendly_engine.modules.terrain.authoring.TerrainIndex = null,
    world_cache_valid: bool = false,
    terrain_preview: project_editor_terrain_preview.Cache = .{},
    terrain_preview_stale: bool = false,
    terrain_loading_active: bool = false,
    terrain_loading_start_ns: i128 = 0,
    terrain_loading_start_resident: usize = 0,
    terrain_loading_elapsed_s: f64 = 0,
    terrain_loading_rate_cells_per_s: f64 = 0,
    terrain_loading_eta_s: f64 = 0,
    terrain_bake_delay_s: f32 = 0,
    spline_preview: project_editor_spline_preview.Cache = .{},
    spline_preview_stale: bool = false,
    scatter_preview: @import("project_editor_scatter_preview.zig").Cache = .{},
    scatter_preview_stale: bool = true,
    terrain_clip_cell: project_editor_dirty_cells.CellId = .{ .x = std.math.minInt(i32), .y = std.math.minInt(i32), .z = 0 },
    terrain_clip_radius_cells: i32 = 0,
    animations: std.ArrayList(shared.scene_animation.Clip) = .empty,
    skeletons: std.ArrayList(shared.scene_animation.Skeleton) = .empty,
    active_clip: ?usize = null,
    life_time: f32 = 0,
    life_playing: bool = false,
    life_auto_key: bool = false,
    life_recording: bool = false,
    life_playback_speed: f32 = 1.0,
    life_key_position: bool = true,
    life_key_rotation: bool = true,
    life_key_scale: bool = true,
    life_interpolation: LifeInterpolation = .linear,
    life_selected_track: ?usize = null,
    life_selected_keyframe: ?usize = null,
    show_life_clips: bool = true,
    show_life_tracks: bool = true,
    show_life_poses: bool = true,
    show_life_bones: bool = true,
    selected_bone: ?u32 = null,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, project_path: []const u8, project_name: []const u8) !ProjectEditorState {
        var state = ProjectEditorState{
            .allocator = allocator,
            .io = io,
            .project_path = try allocator.dupe(u8, project_path),
            .project_name = try allocator.dupe(u8, project_name),
            .active_scene_path = &.{},
            .active_world_manifest_path = &.{},
            .objects = .empty,
        };
        try loadActiveProjectPaths(&state);
        try loadSceneFromDisk(&state);
        try centerInitialWorldCamera(&state);
        state.terrain_preview_stale = true;
        state.spline_preview_stale = true;
        setStatus(&state, "Scene loaded from project folder");
        return state;
    }

    pub fn deinit(self: *ProjectEditorState) void {
        if (self.viewport_texture) |tex| {
            editor_draw.SDL_DestroyTexture(tex);
        }
        for (self.objects.items) |*obj| {
            obj.deinit(self.allocator);
        }
        self.objects.deinit(self.allocator);
        self.selected_object_ids.deinit(self.allocator);
        for (self.animations.items) |*clip| clip.deinit(self.allocator);
        self.animations.deinit(self.allocator);
        for (self.skeletons.items) |*skeleton| skeleton.deinit(self.allocator);
        self.skeletons.deinit(self.allocator);
        project_editor_edit.clearUndoHistory(self);
        self.invalidateWorldCache();
        self.terrain_preview.deinit(self.allocator);
        self.spline_preview.deinit(self.allocator);
        if (self.selected_road_node_id) |id| self.allocator.free(id);
        if (self.selected_road_edge_id) |id| self.allocator.free(id);
        self.world_road_points.deinit(self.allocator);
        self.wall_outline_points.deinit(self.allocator);
        self.architecture_curve_points.deinit(self.allocator);
        self.scatter_preview.deinit(self.allocator);
        self.atmosphere_cell_fogs.deinit(self.allocator);
        if (self.prop_preview_mesh) |*mesh| mesh.deinit(self.allocator);
        if (self.prop_preview_mesh_id) |id| self.allocator.free(id);
        self.prop_sketch_points.deinit(self.allocator);
        if (self.active_prop_asset_id) |id| self.allocator.free(id);
        for (self.prop_recent_ids.items) |id| self.allocator.free(id);
        self.prop_recent_ids.deinit(self.allocator);
        for (self.prop_asset_index.items) |*row| row.deinit(self.allocator);
        self.prop_asset_index.clearRetainingCapacity();
        self.prop_asset_index.deinit(self.allocator);
        self.allocator.free(self.project_path);
        self.allocator.free(self.project_name);
        if (self.active_scene_path_owned) self.allocator.free(self.active_scene_path);
        if (self.active_world_manifest_path_owned) self.allocator.free(self.active_world_manifest_path);
        if (self.concept_paint_session) |*session| session.deinit(self.allocator);
        clearEditorErrorDetail(self);
    }

    pub const WorldCacheView = struct {
        manifest: *const friendly_engine.world.manifest.OwnedWorldManifest,
        regions: ?*const friendly_engine.world.regions.OwnedRegions,
        terrain_index: *const friendly_engine.modules.terrain.authoring.TerrainIndex,
    };

    pub fn ensureWorldCache(self: *ProjectEditorState) !WorldCacheView {
        if (!self.world_cache_valid) {
            self.invalidateWorldCache();
            var manifest = try friendly_engine.world.manifest.loadManifest(
                self.allocator,
                self.io,
                self.project_path,
                self.active_world_manifest_path,
            );
            errdefer manifest.deinit();
            var regions = try friendly_engine.world.regions.loadRegions(
                self.allocator,
                self.io,
                self.project_path,
                friendly_engine.world.regions.default_regions_path,
            );
            errdefer if (regions) |*owned| owned.deinit();
            var terrain_index = try friendly_engine.modules.terrain.authoring.loadIndex(
                self.allocator,
                self.io,
                self.project_path,
                self.active_world_manifest_path,
            );
            errdefer terrain_index.deinit();

            self.world_cell_size_m = manifest.cell_size_m;
            self.world_manifest_cache = manifest;
            self.world_regions_cache = regions;
            self.terrain_index_cache = terrain_index;
            self.world_cache_valid = true;
        }
        const manifest = if (self.world_manifest_cache) |*manifest| manifest else return error.InvalidWorldManifest;
        const terrain_index = if (self.terrain_index_cache) |*index| index else return error.InvalidTerrainIndex;
        return .{
            .manifest = manifest,
            .regions = if (self.world_regions_cache) |*regions| regions else null,
            .terrain_index = terrain_index,
        };
    }

    pub fn invalidateWorldCache(self: *ProjectEditorState) void {
        if (self.world_manifest_cache) |*manifest| manifest.deinit();
        if (self.world_regions_cache) |*regions| regions.deinit();
        if (self.terrain_index_cache) |*index| index.deinit();
        self.world_manifest_cache = null;
        self.world_regions_cache = null;
        self.terrain_index_cache = null;
        self.world_cache_valid = false;
    }

    pub fn saveSceneToDisk(self: *ProjectEditorState) !void {
        try project_editor_prop_asset.persistScenePropAssets(self);
        var object_data: std.ArrayList(scene_io.SceneObjectData) = .empty;
        defer object_data.deinit(self.allocator);
        for (self.objects.items) |*obj| {
            if (obj.editor_only) continue;
            obj.enforceImmutableInvariants();
            try object_data.append(self.allocator, try project_editor_edit.duplicateObjectData(self.allocator, obj));
        }
        defer {
            for (object_data.items) |*obj| obj.deinit(self.allocator);
        }
        try scene_io.saveScene(
            self.allocator,
            self.io,
            self.project_path,
            self.active_scene_path,
            object_data.items,
            self.next_object_id,
            self.animations.items,
            self.skeletons.items,
        );
    }

    pub fn handleEvent(self: *ProjectEditorState, host: *editor_core_ui.Host) !EditorAction {
        return project_editor_input.applyFrameInput(self, &host.ui, &host.input);
    }

    pub fn update(self: *ProjectEditorState, dt: f32) void {
        recordFrameDelta(self, dt);
        project_editor_input.update(self, dt);
        project_editor_life.update(self, dt);
        project_editor_skinning.refreshSkinning(self);
        project_editor_world_authoring_terrain_batch.tick(self) catch |err| {
            var buf: [160]u8 = undefined;
            const message = std.fmt.bufPrint(&buf, "Terrain batch failed: {s}", .{@errorName(err)}) catch "Terrain batch failed";
            setStatus(self, message);
        };
        project_editor_world_authoring_terrain_edge.tick(self) catch |err| {
            var buf: [160]u8 = undefined;
            const message = std.fmt.bufPrint(&buf, "Terrain edge cliff failed: {s}", .{@errorName(err)}) catch "Terrain edge cliff failed";
            setStatus(self, message);
        };
        project_editor_world_authoring_terrain_recipe.tick(self) catch |err| {
            var buf: [160]u8 = undefined;
            const message = std.fmt.bufPrint(&buf, "Terrain recipe failed: {s}", .{@errorName(err)}) catch "Terrain recipe failed";
            setStatus(self, message);
        };
        project_editor_world_authoring_terrain_stretch_smooth.tick(self) catch |err| {
            var buf: [160]u8 = undefined;
            const message = std.fmt.bufPrint(&buf, "Terrain stretch smoothing failed: {s}", .{@errorName(err)}) catch "Terrain stretch smoothing failed";
            setStatus(self, message);
        };
        project_editor_terrain_preview.maintainPreview(self) catch |err| {
            var buf: [160]u8 = undefined;
            const message = std.fmt.bufPrint(&buf, "Terrain preview failed: {s}", .{@errorName(err)}) catch "Terrain preview failed";
            setStatus(self, message);
        };
        project_editor_terrain_preview.tickLodTransitions(self, dt);
        project_editor_terrain_preview.tickBake(self, dt);
    }

    pub fn render(
        self: *ProjectEditorState,
        renderer: *editor_draw.SDL_Renderer,
        text_renderer: *editor_draw.TextRenderer,
        display: editor_display.Metrics,
        viewport_gpu: ?*editor_viewport_gpu.EditorViewportGpu,
        host: *editor_core_ui.Host,
        preferences: ?*@import("project_editor_preferences.zig").Context,
        pending_screenshot: *?@import("editor_commands.zig").PendingScreenshot,
        pending_turntable: *?@import("editor_commands.zig").PendingTurntableCapture,
    ) !EditorAction {
        return project_editor_render.render(self, renderer, text_renderer, display, viewport_gpu, host, preferences, pending_screenshot, pending_turntable);
    }
};

fn loadActiveProjectPaths(self: *ProjectEditorState) !void {
    var config = try friendly_engine.modules.loadProjectConfigInProject(
        self.allocator,
        self.io,
        self.project_path,
        "engine.kdl",
    );
    defer config.deinit();

    self.active_scene_path = try self.allocator.dupe(u8, config.startupScene());
    self.active_scene_path_owned = true;
    errdefer {
        if (self.active_scene_path_owned) self.allocator.free(self.active_scene_path);
        self.active_scene_path = &.{};
        self.active_scene_path_owned = false;
    }
    self.active_world_manifest_path = try self.allocator.dupe(u8, try config.worldForScene(config.startupScene()));
    self.active_world_manifest_path_owned = true;
    self.enabled_editor_modes = try project_editor_mode_gems.flagsFromEnabledModules(self.allocator, config.enabledModules());
    if (!project_editor_mode_config.modeEnabled(self.enabled_editor_modes, self.mode)) {
        self.mode = project_editor_mode_config.firstEnabledMode(self.enabled_editor_modes) orelse return error.NoEditorModesEnabled;
    }
}

pub fn loadSceneFromDisk(self: *ProjectEditorState) !void {
    var loaded = try scene_io.loadScene(self.allocator, self.io, self.project_path, self.active_scene_path, null);
    defer loaded.deinit(self.allocator);
    if (loaded.objects.len == 0) return error.EmptyScene;

    for (loaded.objects) |entry| {
        const mesh = try geometry.duplicateMesh(self.allocator, &entry.mesh);
        const texture = try self.allocator.dupe(u8, entry.texture);
        const object_index = self.objects.items.len;
        try self.objects.append(self.allocator, .{
            .id = entry.id,
            .name = try self.allocator.dupe(u8, entry.name),
            .mesh = mesh,
            .position = entry.position,
            .rotation = entry.rotation,
            .scale = entry.scale,
            .texture = texture,
            .base_color = entry.base_color,
            .primitive_kind = entry.primitive_kind,
            .object_kind = entry.object_kind,
            .enabled = entry.enabled,
            .renderer_visible = entry.renderer_visible,
            .cast_shadows = entry.cast_shadows,
            .receive_shadows = entry.receive_shadows,
            .components = try scene_io.duplicateComponents(self.allocator, entry.components),
            .properties = try scene_io.duplicateProperties(self.allocator, entry.properties),
            .physics = entry.physics,
            .blockout_intent = if (entry.blockout_intent) |intent| try shared.scene_blockout.Intent.duplicate(self.allocator, intent) else null,
            .texture_transform = entry.texture_transform,
            .face_materials = try scene_io.duplicateFaceMaterials(self.allocator, entry.face_materials),
            .face_surfaces = try scene_io.duplicateFaceSurfaces(self.allocator, entry.face_surfaces),
            .gameplay = if (entry.gameplay) |gameplay| try shared.scene_gameplay.Component.duplicate(self.allocator, gameplay) else null,
            .marker = if (entry.marker) |marker| try shared.scene_marker.Marker.duplicate(self.allocator, marker) else null,
            .lightmap_path = if (entry.lightmap_path) |path| try self.allocator.dupe(u8, path) else null,
            .skeleton_asset = if (entry.skeleton_asset) |asset| try self.allocator.dupe(u8, asset) else null,
            .bone_pose = if (entry.bone_pose.len > 0)
                try self.allocator.dupe(shared.scene_animation.Transform, entry.bone_pose)
            else if (entry.skeleton_asset) |asset|
                try shared.scene_skinning.initBonePoseForAsset(self.allocator, asset, loaded.skeletons)
            else
                try self.allocator.dupe(shared.scene_animation.Transform, &.{}),
            .parent_id = entry.parent_id,
            .layer = if (entry.layer.len > 0) try self.allocator.dupe(u8, entry.layer) else "",
            .variant = if (entry.variant) |variant| try self.allocator.dupe(u8, variant) else null,
            .prop_asset_id = if (entry.prop_asset_id) |asset_id| try self.allocator.dupe(u8, asset_id) else null,
        });
        self.objects.items[object_index].enforceImmutableInvariants();
    }
    self.next_object_id = loaded.next_object_id;
    for (loaded.animations) |clip| {
        const copies = try shared.scene_animation.duplicateClips(self.allocator, &.{clip});
        defer self.allocator.free(copies);
        try self.animations.append(self.allocator, copies[0]);
    }
    for (loaded.skeletons) |skeleton| {
        const copies = try shared.scene_animation.duplicateSkeletons(self.allocator, &.{skeleton});
        defer self.allocator.free(copies);
        try self.skeletons.append(self.allocator, copies[0]);
    }
    self.active_clip = if (self.animations.items.len > 0) 0 else null;
    self.selected_object = 0;
    try self.selected_object_ids.append(self.allocator, self.objects.items[0].id);
    @import("project_editor_prop.zig").rebuildRecentFromObjects(self);
}

fn centerInitialWorldCamera(self: *ProjectEditorState) !void {
    var loaded_manifest = try friendly_engine.world.manifest.loadManifest(
        self.allocator,
        self.io,
        self.project_path,
        self.active_world_manifest_path,
    );
    defer loaded_manifest.deinit();
    self.world_cell_size_m = loaded_manifest.cell_size_m;
    @import("project_editor_world_authoring_atmosphere.zig").loadIntoState(self) catch {};
    @import("project_editor_world_authoring_ocean.zig").loadIntoState(self) catch {};

    const bounds = try worldBounds(&loaded_manifest);
    self.camera.target = .{ .x = 0, .y = 0, .z = 0 };
    const extent_x = bounds.max_x - bounds.min_x;
    const extent_z = bounds.max_z - bounds.min_z;
    const span = @max(loaded_manifest.cell_size_m, @max(extent_x, extent_z));
    const diagonal = @max(loaded_manifest.cell_size_m, @sqrt(extent_x * extent_x + extent_z * extent_z));
    self.camera.distance = @max(6.0, span * 0.72);
    self.camera.max_distance = @max(6.0, diagonal * 1.25);
    self.world_draw_distance_m = @max(loaded_manifest.cell_size_m * 2.0, diagonal * 1.75);
    self.camera.far_clip_m = self.world_draw_distance_m;
    const initial_height = project_editor_terrain_preview.sampleHeightAtPoint(self, self.camera.target) catch |err| switch (err) {
        error.WorldCellNotInManifest, error.TerrainTileNotFound => 0.0,
        else => return err,
    };
    self.camera.target.y = initial_height + 6.0;
    self.view_orientation = .free;
}

const WorldBounds = struct {
    min_x: f32,
    min_z: f32,
    max_x: f32,
    max_z: f32,
};

fn worldBounds(manifest: *const friendly_engine.world.manifest.OwnedWorldManifest) !WorldBounds {
    var min_x: f32 = std.math.floatMax(f32);
    var min_z: f32 = std.math.floatMax(f32);
    var max_x: f32 = -std.math.floatMax(f32);
    var max_z: f32 = -std.math.floatMax(f32);
    for (manifest.cells) |entry| {
        if (entry.id.z != 0) continue;
        const cell_min_x = @as(f32, @floatFromInt(entry.id.x)) * manifest.cell_size_m;
        const cell_min_z = @as(f32, @floatFromInt(entry.id.y)) * manifest.cell_size_m;
        min_x = @min(min_x, cell_min_x);
        min_z = @min(min_z, cell_min_z);
        max_x = @max(max_x, cell_min_x + manifest.cell_size_m);
        max_z = @max(max_z, cell_min_z + manifest.cell_size_m);
    }
    if (!std.math.isFinite(min_x)) return .{ .min_x = 0, .min_z = 0, .max_x = 0, .max_z = 0 };
    return .{ .min_x = min_x, .min_z = min_z, .max_x = max_x, .max_z = max_z };
}

pub fn recordFrameDelta(self: *ProjectEditorState, dt: f32) void {
    if (dt <= 0) return;
    const instant_fps = 1.0 / dt;
    if (self.fps <= 0) {
        self.fps = instant_fps;
    } else {
        self.fps = self.fps * 0.85 + instant_fps * 0.15;
    }
}

pub fn perfSnapshotContext(
    self: *const ProjectEditorState,
    ui_command_count: u32,
    viewport_gpu: ?*const @import("editor_viewport_gpu.zig").EditorViewportGpu,
    control_stats: @import("editor_commands.zig").ControlStats,
) editor_frame_perf.SnapshotContext {
    const use_gpu = if (viewport_gpu) |gpu| gpu.use_gpu and self.view_camera_mode == .perspective else false;
    const uploaded_stats: shared.gpu_api.UploadedMeshStats = if (viewport_gpu) |gpu|
        if (gpu.gpu_renderer) |renderer| renderer.uploadedMeshStats() else .{}
    else
        .{};
    return .{
        .screen = "project_editor",
        .viewport_backend = if (use_gpu) "gpu" else if (self.view_camera_mode == .perspective) "software" else "orthographic",
        .gpu_backend = if (viewport_gpu) |g| if (g.use_gpu) g.gpu_backend_name.label() else "none" else "none",
        .viewport_w = @intFromFloat(@max(1, self.viewport_screen_rect.w)),
        .viewport_h = @intFromFloat(@max(1, self.viewport_screen_rect.h)),
        .object_count = @intCast(self.objects.items.len),
        .render_commands = @intCast(self.render_command_stats.total),
        .render_grids = @intCast(self.render_command_stats.grids),
        .render_meshes = @intCast(self.render_command_stats.meshes),
        .render_instanced_meshes = @intCast(self.render_command_stats.instanced_meshes),
        .render_mesh_instances = @intCast(self.render_command_stats.mesh_instances),
        .render_overlays = @intCast(self.render_command_stats.overlays),
        .render_copies = @intCast(self.render_command_stats.copies),
        .llm_commands_executed = control_stats.executed,
        .llm_commands_inflight = control_stats.inflight,
        .dirty_world_cells = @intCast(self.dirty_cells.count),
        .visible_meshes = @intCast(self.visibility_stats.visible_meshes),
        .total_meshes = @intCast(self.render_command_stats.meshes),
        .gpu_uploaded_meshes = uploaded_stats.meshes,
        .gpu_indexed_primitives = uploaded_stats.indexed_primitives,
        .gpu_wireframe_indices = uploaded_stats.wireframe_indices,
        .ui_commands = ui_command_count,
        .uses_gpu_texture_wrap = self.uses_gpu_viewport_texture,
        .uses_gpu_ui = self.uses_gpu_ui,
    };
}

pub fn setStatus(self: *ProjectEditorState, message: []const u8) void {
    self.status_len = @min(message.len, self.status_buf.len);
    @memcpy(self.status_buf[0..self.status_len], message[0..self.status_len]);
}

pub fn setEditorErrorDetail(self: *ProjectEditorState, title: []const u8, message: []const u8) !void {
    clearEditorErrorDetail(self);
    errdefer clearEditorErrorDetail(self);
    self.editor_error_title = try self.allocator.dupe(u8, title);
    self.editor_error_detail = try self.allocator.dupe(u8, message);
}

pub fn clearEditorErrorDetail(self: *ProjectEditorState) void {
    if (self.editor_error_title) |title| self.allocator.free(title);
    if (self.editor_error_detail) |detail| self.allocator.free(detail);
    self.editor_error_title = null;
    self.editor_error_detail = null;
}

pub fn setPlayErrorDetail(self: *ProjectEditorState, message: []const u8) !void {
    try setEditorErrorDetail(self, "Run Failed", message);
}

pub fn clearPlayErrorDetail(self: *ProjectEditorState) void {
    clearEditorErrorDetail(self);
}

/// Stashes a path picked from a native OS file dialog so the next frame's
/// poll (see editor_commands.processPending) can act on it. Safe to call
/// from the dialog's own callback thread; the buffer/atomics provide the
/// handoff to the main loop, mirroring pm_state.zig's queueDialogPath.
pub fn queuePropDialogPath(self: *ProjectEditorState, path: []const u8, kind: project_editor_types.PendingPropDialogKind) void {
    const len = @min(path.len, self.pending_prop_dialog_path_buf.len);
    @memcpy(self.pending_prop_dialog_path_buf[0..len], path[0..len]);
    self.pending_prop_dialog_kind_atomic.store(@intFromEnum(kind), .release);
    self.pending_prop_dialog_path_len.store(@intCast(len), .release);
}

pub fn markDirtyCell(
    self: *ProjectEditorState,
    layer_name: []const u8,
    cell: project_editor_dirty_cells.CellId,
    change: []const u8,
) !void {
    try self.dirty_cells.mark(layer_name, cell, change);
    if (std.mem.eql(u8, layer_name, "Terrain")) {
        self.terrain_preview_stale = true;
        project_editor_terrain_preview.scheduleBake(self);
    }
    if (std.mem.eql(u8, layer_name, "Splines")) {
        self.spline_preview_stale = true;
        self.terrain_preview_stale = true;
        project_editor_terrain_preview.scheduleBake(self);
    } else if (std.mem.eql(u8, layer_name, "Scatter")) {
        self.scatter_preview_stale = true;
        project_editor_terrain_preview.scheduleBake(self);
    } else if (std.mem.eql(u8, layer_name, "Atmosphere")) {
        project_editor_terrain_preview.scheduleBake(self);
    }
    var buf: [256]u8 = undefined;
    setStatus(self, try self.dirty_cells.formatStatus(&buf));
}

pub fn computeViewportRect(window_w: f32, window_h: f32) editor_draw.SDL_FRect {
    const outer_pad: f32 = 10.0;
    const menubar_h: f32 = if (builtin.os.tag != .macos) 30.0 else 0.0;
    const top_h: f32 = 46.0;
    const tool_h: f32 = 42.0;
    const bottom_h: f32 = 30.0;
    const gap: f32 = 6.0;
    const sidebar_w: f32 = 244.0;
    const props_w: f32 = 276.0;
    const content_top = outer_pad + menubar_h + top_h + gap + tool_h + gap;
    const content_h = @max(220.0, window_h - content_top - bottom_h - outer_pad - gap);
    const viewport_w = @max(320.0, window_w - (outer_pad * 2.0) - sidebar_w - props_w - (gap * 2.0));
    return .{
        .x = outer_pad + sidebar_w + gap,
        .y = content_top,
        .w = viewport_w,
        .h = content_h,
    };
}

pub fn projectionMode(state: *const ProjectEditorState) editor_math.ProjectionMode {
    return switch (state.view_camera_mode) {
        .perspective => .perspective,
        .orthographic => .orthographic,
    };
}

pub fn rayFromViewport(
    state: *const ProjectEditorState,
    local_x: f32,
    local_y: f32,
    vp_w: f32,
    vp_h: f32,
) editor_math.Ray {
    return editor_math.rayFromScreen(state.camera, local_x, local_y, vp_w, vp_h, projectionMode(state));
}

pub fn projectViewportPoint(
    state: *const ProjectEditorState,
    world: editor_math.Vec3,
    vp_w: f32,
    vp_h: f32,
) ?editor_math.Vec2 {
    return editor_math.projectWorldPoint(state.camera, world, vp_w, vp_h, projectionMode(state));
}

pub fn objectVisibleInMode(mode: EditorMode, obj: *const SceneObject) bool {
    return if (mode == .prop_creation) obj.editor_only else !obj.editor_only;
}

pub fn objectVisible(state: *const ProjectEditorState, obj: *const SceneObject) bool {
    if (!objectVisibleInMode(state.mode, obj)) return false;
    if (!state.world_ocean_visible and objectIsWaterSurface(obj)) return false;
    return true;
}

pub fn objectIsWaterSurface(obj: *const SceneObject) bool {
    if (std.mem.eql(u8, obj.layer, "world.water")) return true;
    for (obj.properties) |property| {
        if (std.mem.eql(u8, property.key, "role") and std.mem.eql(u8, property.value, "distant_ocean")) return true;
        if (std.mem.eql(u8, property.key, "water_body") and std.mem.eql(u8, property.value, "sea")) return true;
        if (std.mem.eql(u8, property.key, "water_surface") and property.value.len > 0) return true;
    }
    return false;
}

fn testSceneObject(layer: []const u8, properties: []shared.scene_document.Property) SceneObject {
    return .{
        .id = 1,
        .name = @constCast("test"),
        .mesh = .{ .vertices = &.{}, .indices = &.{} },
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = @constCast(""),
        .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .layer = @constCast(layer),
        .properties = properties,
    };
}

test "object water classification uses water layer" {
    var properties = [_]shared.scene_document.Property{};
    const obj = testSceneObject("world.water", properties[0..]);

    try std.testing.expect(objectIsWaterSurface(&obj));
}

test "object water classification uses distant ocean role" {
    var properties = [_]shared.scene_document.Property{
        .{ .key = @constCast("role"), .value = @constCast("distant_ocean") },
    };
    const obj = testSceneObject("", properties[0..]);

    try std.testing.expect(objectIsWaterSurface(&obj));
}

test "object water classification uses sea body and water surface marker" {
    var sea_properties = [_]shared.scene_document.Property{
        .{ .key = @constCast("water_body"), .value = @constCast("sea") },
    };
    const sea = testSceneObject("", sea_properties[0..]);
    try std.testing.expect(objectIsWaterSurface(&sea));

    var marker_properties = [_]shared.scene_document.Property{
        .{ .key = @constCast("water_surface"), .value = @constCast("lake") },
    };
    const marker = testSceneObject("", marker_properties[0..]);
    try std.testing.expect(objectIsWaterSurface(&marker));
}

test "object water classification leaves ordinary meshes opaque" {
    var properties = [_]shared.scene_document.Property{
        .{ .key = @constCast("role"), .value = @constCast("building") },
    };
    const obj = testSceneObject("world.architecture", properties[0..]);

    try std.testing.expect(!objectIsWaterSurface(&obj));
}

pub fn editorModeEnabled(state: *const ProjectEditorState, mode: EditorMode) bool {
    return project_editor_mode_config.modeEnabled(state.enabled_editor_modes, mode);
}

pub fn firstEnabledEditorMode(state: *const ProjectEditorState) ?EditorMode {
    return project_editor_mode_config.firstEnabledMode(state.enabled_editor_modes);
}

pub fn worldContextVisibleInMode(mode: EditorMode) bool {
    return mode == .world_creation or mode == .layout or mode == .architecture_creation;
}

pub fn worldContextVisible(state: *const ProjectEditorState) bool {
    return editorModeEnabled(state, .world_creation) and worldContextVisibleInMode(state.mode);
}

test "world context is visible in world layout and architecture modes" {
    try std.testing.expect(worldContextVisibleInMode(.world_creation));
    try std.testing.expect(worldContextVisibleInMode(.layout));
    try std.testing.expect(worldContextVisibleInMode(.architecture_creation));
    try std.testing.expect(!worldContextVisibleInMode(.prop_creation));
    try std.testing.expect(!worldContextVisibleInMode(.life));
}

pub fn moveAxisLabel(self: *const ProjectEditorState) []const u8 {
    return switch (self.move_axis) {
        .xz => "XZ",
        .x => "X",
        .y => "Y",
        .z => "Z",
        .xy => "XY",
        .yz => "YZ",
    };
}
