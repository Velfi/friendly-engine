const std = @import("std");
const shared = @import("runtime_shared");

const editor_math = shared.editor_math;

pub const TerrainFormationKind = enum {
    base,
    slope,
    ridge,
    basin,
    valley,
    shelf,
    noise,

    pub fn parse(value: []const u8) !TerrainFormationKind {
        inline for (std.meta.fields(TerrainFormationKind)) |field| {
            if (std.mem.eql(u8, value, field.name)) return @enumFromInt(field.value);
        }
        return error.InvalidTerrainFormationKind;
    }
};

pub const ConceptPaintBlendMode = enum {
    normal,
    multiply,

    pub fn parse(value: []const u8) !ConceptPaintBlendMode {
        if (std.mem.eql(u8, value, "normal")) return .normal;
        if (std.mem.eql(u8, value, "multiply")) return .multiply;
        return error.InvalidConceptPaintBlendMode;
    }

    pub fn label(self: ConceptPaintBlendMode) []const u8 {
        return switch (self) {
            .normal => "normal",
            .multiply => "multiply",
        };
    }
};

pub const ConceptPaintScope = enum {
    terrain,
    prop,
    architecture,
    layout,

    pub fn label(self: ConceptPaintScope) []const u8 {
        return switch (self) {
            .terrain => "terrain",
            .prop => "prop",
            .architecture => "architecture",
            .layout => "layout",
        };
    }
};

pub const ConceptPaintSession = struct {
    id: u64 = 0,
    mode: EditorMode = .layout,
    scope: ConceptPaintScope = .layout,
    camera: editor_math.OrbitCamera = .{},
    projection_mode: editor_math.ProjectionMode = .perspective,
    viewport_w: u32 = 1,
    viewport_h: u32 = 1,
    screenshot_path: []u8 = &.{},
    styled_path: []u8 = &.{},
    prompt: []u8 = &.{},
    provider: []u8 = &.{},
    desired_style: []u8 = &.{},
    output_path: []u8 = &.{},
    opacity: f32 = 1.0,
    blend_mode: ConceptPaintBlendMode = .normal,
    status: [160]u8 = [_]u8{0} ** 160,
    status_len: usize = 0,

    pub fn deinit(self: *ConceptPaintSession, allocator: std.mem.Allocator) void {
        if (self.screenshot_path.len > 0) allocator.free(self.screenshot_path);
        if (self.styled_path.len > 0) allocator.free(self.styled_path);
        if (self.prompt.len > 0) allocator.free(self.prompt);
        if (self.provider.len > 0) allocator.free(self.provider);
        if (self.desired_style.len > 0) allocator.free(self.desired_style);
        if (self.output_path.len > 0) allocator.free(self.output_path);
        self.* = .{};
    }

    pub fn setStatus(self: *ConceptPaintSession, message: []const u8) void {
        self.status_len = @min(message.len, self.status.len);
        @memcpy(self.status[0..self.status_len], message[0..self.status_len]);
    }

    pub fn statusText(self: *const ConceptPaintSession) []const u8 {
        return self.status[0..self.status_len];
    }
};

pub const TerrainFormation = struct {
    kind: TerrainFormationKind = .base,
    x: f32 = 0,
    z: f32 = 0,
    radius: f32 = 1,
    width: f32 = 1,
    height: f32 = 0,
    scale: f32 = 1,
    axis: u8 = 'z',
    start: f32 = 0,
    end: f32 = 1,
};

pub const TerrainBatchJob = struct {
    id: u64 = 0,
    started_ns: u64 = 0,
    min_x: i32 = 0,
    max_x: i32 = 0,
    min_z: i32 = 0,
    max_z: i32 = 0,
    cell_size_m: f32 = 256,
    next_offset: u64 = 0,
    flushed_offset: u64 = 0,
    total: u64 = 0,
    batch_size: u32 = 1,
    tick_budget_ns: u64 = 40 * std.time.ns_per_ms,
    flush_interval_cells: u32 = 32,
    seed: u64 = 0,
    undo_transaction_id: u64 = 0,
    undo_snapshots: u32 = 0,
    formations: [16]TerrainFormation = undefined,
    formation_count: u8 = 0,
    min_height: f32 = std.math.inf(f32),
    max_height: f32 = -std.math.inf(f32),
    profiled_cells: u64 = 0,
    last_total_ns: u64 = 0,
    last_scene_ns: u64 = 0,
    last_tile_ns: u64 = 0,
    last_manifest_ns: u64 = 0,
    last_index_ns: u64 = 0,
    last_dirty_ns: u64 = 0,
    last_tick_cells: u32 = 0,
    last_tick_ns: u64 = 0,
    last_flush_ns: u64 = 0,
    total_total_ns: u64 = 0,
    total_scene_ns: u64 = 0,
    total_tile_ns: u64 = 0,
    total_manifest_ns: u64 = 0,
    total_index_ns: u64 = 0,
    total_dirty_ns: u64 = 0,
    total_tick_ns: u64 = 0,
    total_flush_ns: u64 = 0,
    profiled_ticks: u64 = 0,
    profiled_flushes: u64 = 0,
    active: bool = false,
    complete: bool = false,
    cancelled: bool = false,
    failed: bool = false,
    status_len: usize = 0,
    status_buf: [160]u8 = undefined,

    pub fn setStatus(self: *TerrainBatchJob, message: []const u8) void {
        self.status_len = @min(message.len, self.status_buf.len);
        @memcpy(self.status_buf[0..self.status_len], message[0..self.status_len]);
    }

    pub fn status(self: *const TerrainBatchJob) []const u8 {
        return self.status_buf[0..self.status_len];
    }
};

pub const TerrainEdgeCliffJob = struct {
    id: u64 = 0,
    started_ns: u64 = 0,
    min_x: i32 = 0,
    max_x: i32 = 0,
    min_z: i32 = 0,
    max_z: i32 = 0,
    cell_size_m: f32 = 512,
    bottom_height: f32 = -900,
    width_m: f32 = 1024,
    undo_transaction_id: u64 = 0,
    undo_snapshots: u32 = 0,
    next_offset: u64 = 0,
    total: u64 = 0,
    current_pass: u32 = 1,
    pass_changed_cells: u64 = 0,
    pass_changed_samples: u64 = 0,
    processed_cells: u64 = 0,
    changed_cells: u64 = 0,
    changed_samples: u64 = 0,
    min_height: f32 = std.math.inf(f32),
    max_drop: f32 = 0,
    tick_budget_ns: u64 = 40 * std.time.ns_per_ms,
    last_tick_cells: u32 = 0,
    last_tick_ns: u64 = 0,
    dirty_overflow: bool = false,
    active: bool = false,
    complete: bool = false,
    cancelled: bool = false,
    failed: bool = false,
    status_len: usize = 0,
    status_buf: [160]u8 = undefined,

    pub fn setStatus(self: *TerrainEdgeCliffJob, message: []const u8) void {
        self.status_len = @min(message.len, self.status_buf.len);
        @memcpy(self.status_buf[0..self.status_len], message[0..self.status_len]);
    }

    pub fn status(self: *const TerrainEdgeCliffJob) []const u8 {
        return self.status_buf[0..self.status_len];
    }
};

pub const TerrainStretchSmoothJob = struct {
    id: u64 = 0,
    started_ns: u64 = 0,
    min_x: i32 = 0,
    max_x: i32 = 0,
    min_z: i32 = 0,
    max_z: i32 = 0,
    cell_size_m: f32 = 256,
    threshold_m: f32 = 180,
    strength: f32 = 0.35,
    iterations: u32 = 1,
    max_samples_per_cell: u32 = 12,
    min_height: f32 = -std.math.inf(f32),
    max_height: f32 = std.math.inf(f32),
    undo_transaction_id: u64 = 0,
    undo_snapshots: u32 = 0,
    current_pass: u32 = 1,
    pass_changed_cells: u64 = 0,
    pass_changed_samples: u64 = 0,
    next_offset: u64 = 0,
    total: u64 = 0,
    processed_cells: u64 = 0,
    changed_cells: u64 = 0,
    changed_samples: u64 = 0,
    max_delta: f32 = 0,
    total_delta: f32 = 0,
    tick_budget_ns: u64 = 40 * std.time.ns_per_ms,
    last_tick_cells: u32 = 0,
    last_tick_ns: u64 = 0,
    dirty_overflow: bool = false,
    active: bool = false,
    complete: bool = false,
    cancelled: bool = false,
    failed: bool = false,
    status_len: usize = 0,
    status_buf: [160]u8 = undefined,

    pub fn setStatus(self: *TerrainStretchSmoothJob, message: []const u8) void {
        self.status_len = @min(message.len, self.status_buf.len);
        @memcpy(self.status_buf[0..self.status_len], message[0..self.status_len]);
    }

    pub fn status(self: *const TerrainStretchSmoothJob) []const u8 {
        return self.status_buf[0..self.status_len];
    }
};

pub const TerrainRecipeBrush = enum {
    irregular_island_mask,
    caldera_complex,
    radial_volcanic_ridges,
    ashland_badlands,
    marsh_delta,
    broken_highland_craters,
    fjord_horn_coast,
    chalk_plateau_massif,
    dry_basin_washes,
    coastal_hook_shelves,
    volcanic_outlier,
    sea_wall_dropoff,

    pub fn parse(value: []const u8) !TerrainRecipeBrush {
        inline for (std.meta.fields(TerrainRecipeBrush)) |field| {
            if (std.mem.eql(u8, value, field.name)) return @enumFromInt(field.value);
        }
        return error.InvalidTerrainRecipeBrush;
    }
};

pub const TerrainRecipeFeature = struct {
    brush: TerrainRecipeBrush,
    center_x: f32 = 0,
    center_z: f32 = 0,
    radius_x: f32 = 1,
    radius_z: f32 = 1,
    height: f32 = 0,
    coast_noise: f32 = 0,
    outer_radius: f32 = 1,
    rim_height: f32 = 0,
    inner_radius: f32 = 1,
    crater_floor: f32 = 0,
    plug_radius: f32 = 0,
    plug_height: f32 = 0,
    breaches: u32 = 0,
    count: u32 = 0,
    width: f32 = 1,
    erosion: f32 = 0,
    gully_density: f32 = 0,
    basalt_roughness: f32 = 0,
    channel_depth: f32 = 0,
    channel_count: u32 = 0,
    craters: u32 = 0,
    weathering: f32 = 0,
    horn_count: u32 = 0,
    cliff_height: f32 = 0,
    plateau_height: f32 = 0,
    terraces: u32 = 0,
    badland_apron: f32 = 0,
    wash_count: u32 = 0,
    crack_density: f32 = 0,
    hooks: u32 = 0,
    beach_pockets: u32 = 0,
    coast_jaggedness: f32 = 0,
    bottom_height: f32 = -120,
    rim_width: f32 = 180,
    cliff_top_min: f32 = 35,
};

pub const TerrainRecipeJob = struct {
    id: u64 = 0,
    started_ns: u64 = 0,
    min_x: i32 = 0,
    max_x: i32 = 0,
    min_z: i32 = 0,
    max_z: i32 = 0,
    cell_size_m: f32 = 256,
    next_offset: u64 = 0,
    total: u64 = 0,
    seed: u64 = 0,
    sea_level: f32 = 0,
    ocean_floor: f32 = -120,
    features: [128]TerrainRecipeFeature = undefined,
    feature_count: u8 = 0,
    undo_transaction_id: u64 = 0,
    undo_snapshots: u32 = 0,
    min_height: f32 = std.math.inf(f32),
    max_height: f32 = -std.math.inf(f32),
    changed_cells: u64 = 0,
    tick_budget_ns: u64 = 40 * std.time.ns_per_ms,
    last_tick_cells: u32 = 0,
    last_tick_ns: u64 = 0,
    dirty_overflow: bool = false,
    active: bool = false,
    complete: bool = false,
    cancelled: bool = false,
    failed: bool = false,
    status_len: usize = 0,
    status_buf: [160]u8 = undefined,

    pub fn setStatus(self: *TerrainRecipeJob, message: []const u8) void {
        self.status_len = @min(message.len, self.status_buf.len);
        @memcpy(self.status_buf[0..self.status_len], message[0..self.status_len]);
    }

    pub fn status(self: *const TerrainRecipeJob) []const u8 {
        return self.status_buf[0..self.status_len];
    }
};

pub const EditorMode = enum {
    world_creation,
    layout,
    architecture_creation,
    prop_creation,
    life,

    pub fn label(self: EditorMode) []const u8 {
        return switch (self) {
            .world_creation => "World",
            .layout => "Layout",
            .architecture_creation => "Architecture",
            .prop_creation => "Prop",
            .life => "Life",
        };
    }
};

pub const LeftRailTab = enum {
    scene,
    add,
    world,
    assets,

    pub fn label(self: LeftRailTab) []const u8 {
        return switch (self) {
            .scene => "Scene",
            .add => "Create",
            .world => "World",
            .assets => "Assets",
        };
    }
};

pub const AssetSelection = enum {
    mesh_box,
    scene_main,
};

pub const PendingPropDialogKind = enum {
    none,
    import_prop_glb,
    export_prop_glb,
};

pub const ObjectTool = enum {
    select,
    move,
    rotate,
    scale,

    pub fn label(self: ObjectTool) []const u8 {
        return switch (self) {
            .select => "Select",
            .move => "Move",
            .rotate => "Rotate",
            .scale => "Scale",
        };
    }
};

pub const EditTool = enum {
    vertex,
    edge,
    face,
    extrude,
    inset,

    pub fn label(self: EditTool) []const u8 {
        return switch (self) {
            .vertex => "Vertex",
            .edge => "Edge",
            .face => "Face",
            .extrude => "Extrude",
            .inset => "Inset",
        };
    }
};

pub const ArchitectureTool = enum {
    network,
    floorplan,
    shell,
    foundation,
    cutout,
    wall,
    opening,
    roof,
    door,
    window,
    curve,
    brush,
    add,
    subtract,
    vertex,
    edge,
    face,
    extrude,
    inset,
    ramp,
    material,

    pub fn label(self: ArchitectureTool) []const u8 {
        return switch (self) {
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
            .brush => "Brush",
            .add => "Add",
            .subtract => "Subtract",
            .vertex => "Vertex",
            .edge => "Edge",
            .face => "Face",
            .extrude => "Extrude",
            .inset => "Inset",
            .ramp => "Ramp",
            .material => "Material",
        };
    }

    pub fn editTool(self: ArchitectureTool) ?EditTool {
        return switch (self) {
            .vertex => .vertex,
            .edge => .edge,
            .face => .face,
            .extrude => .extrude,
            .inset => .inset,
            else => null,
        };
    }

    pub fn isBlockoutDrawTool(self: ArchitectureTool) bool {
        return self == .floorplan or self == .wall or self == .door or self == .window or
            self == .curve or self == .brush or self == .add or self == .subtract;
    }
};

pub const BlockoutBrushShape = enum {
    box,
    wedge,
    ramp,
    cylinder,

    pub fn label(self: BlockoutBrushShape) []const u8 {
        return switch (self) {
            .box => "Box",
            .wedge => "Wedge",
            .ramp => "Ramp",
            .cylinder => "Cyl",
        };
    }
};

pub const PropTool = enum {
    select,
    create,
    asset,
    primitive,
    edit,
    material,
    collider,
    variants,

    pub fn label(self: PropTool) []const u8 {
        return switch (self) {
            .select => "Select",
            .create => "Create",
            .asset => "Asset",
            .primitive => "Primitive",
            .edit => "Edit",
            .material => "Material",
            .collider => "Collider",
            .variants => "Variants",
        };
    }
};

pub const PropWorkspaceMode = enum {
    display,
    edit,

    pub fn label(self: PropWorkspaceMode) []const u8 {
        return switch (self) {
            .display => "Display",
            .edit => "Edit",
        };
    }
};

pub const PropLibrarySort = enum {
    name,
    recent,
};

pub const PropLibraryCategoryFilter = enum {
    all,
    paint,
    shape,
    game,
};

pub const PropLibrarySourceFilter = enum {
    all,
    builtin,
    project,
};

pub const PropAssetSource = enum {
    builtin,
    project,
};

pub const PropAssetIndexRow = struct {
    id: []u8,
    label: []u8,
    tags: []u8,
    source: PropAssetSource,
    kind: []u8,
    variant_count: u32,
    source_count: usize,
    deleted: bool,
    color: @import("runtime_shared").color.Color,

    pub fn deinit(self: *PropAssetIndexRow, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.label);
        allocator.free(self.tags);
        allocator.free(self.kind);
    }
};

pub const SceneObjectFilter = enum {
    all,
    props,
    non_props,
};

pub const SceneVisibilityFilter = enum {
    all,
    visible,
    hidden,
    locked,
};

pub const PropSketchMode = enum {
    none,
    face,
    curve,
    path,
};

pub const TexturePaintBrush = enum {
    soft_round,
    hard_square,
    noise,

    pub fn label(self: TexturePaintBrush) []const u8 {
        return switch (self) {
            .soft_round => "Soft",
            .hard_square => "Square",
            .noise => "Noise",
        };
    }

    pub fn next(self: TexturePaintBrush) TexturePaintBrush {
        return switch (self) {
            .soft_round => .hard_square,
            .hard_square => .noise,
            .noise => .soft_round,
        };
    }
};

pub const TexturePaintStencil = enum {
    none,
    checker,
    stripes,
    edge_wear,

    pub fn label(self: TexturePaintStencil) []const u8 {
        return switch (self) {
            .none => "None",
            .checker => "Checker",
            .stripes => "Stripes",
            .edge_wear => "Edge",
        };
    }

    pub fn next(self: TexturePaintStencil) TexturePaintStencil {
        return switch (self) {
            .none => .checker,
            .checker => .stripes,
            .stripes => .edge_wear,
            .edge_wear => .none,
        };
    }
};

pub const PropPrimitive = enum {
    cube,
    cylinder,
    plane,
    ramp,

    pub fn label(self: PropPrimitive) []const u8 {
        return switch (self) {
            .cube => "Cube",
            .cylinder => "Cylinder",
            .plane => "Plane",
            .ramp => "Ramp",
        };
    }
};

pub const PropPlacementMode = enum {
    surface,
    ground,
    free,

    pub fn label(self: PropPlacementMode) []const u8 {
        return switch (self) {
            .surface => "Surface",
            .ground => "Ground",
            .free => "Free",
        };
    }
};

pub const LifeTool = enum {
    select,
    pose,
    keyframe,
    record,
    playback,
    clips,
    bones,
    curves,

    pub fn label(self: LifeTool) []const u8 {
        return switch (self) {
            .select => "Select",
            .pose => "Pose",
            .keyframe => "Keyframe",
            .record => "Record",
            .playback => "Playback",
            .clips => "Clips",
            .bones => "Bones",
            .curves => "Curves",
        };
    }
};

pub const LifeInterpolation = enum {
    linear,
    ease_in,
    ease_out,
    hold,

    pub fn label(self: LifeInterpolation) []const u8 {
        return switch (self) {
            .linear => "Linear",
            .ease_in => "Ease In",
            .ease_out => "Ease Out",
            .hold => "Hold",
        };
    }

    pub fn next(self: LifeInterpolation) LifeInterpolation {
        return switch (self) {
            .linear => .ease_in,
            .ease_in => .ease_out,
            .ease_out => .hold,
            .hold => .linear,
        };
    }
};

pub const WorldTool = enum {
    terrain,
    paint,
    roads,
    scatter,
    atmosphere,
    ocean,
    water,
    measure,

    pub fn label(self: WorldTool) []const u8 {
        return switch (self) {
            .terrain => "Terrain",
            .paint => "Paint",
            .roads => "Roads",
            .scatter => "Scatter",
            .atmosphere => "Atmosphere",
            .ocean => "Ocean",
            .water => "Water",
            .measure => "Measure",
        };
    }
};

pub const WorldConfigTab = enum {
    atmosphere,
    wind,
    waves,

    pub fn label(self: WorldConfigTab) []const u8 {
        return switch (self) {
            .atmosphere => "Atmosphere",
            .wind => "Wind",
            .waves => "Waves",
        };
    }
};

pub const WorldLayerId = enum {
    terrain_base_height,
    terrain_erosion_mask,
    terrain_material_tiles,
    spline_road_main,
    spline_path_side,
    scatter_grass_low,
    scatter_pine_cluster,
    scatter_rocks_medium,
    scatter_density_mask,
    atmosphere_fog_bank,
    atmosphere_sky_tone,
    ocean_wind,
    ocean_waves,
    water_volumes,
    water_surface,
    water_currents,

    pub fn label(self: WorldLayerId) []const u8 {
        return switch (self) {
            .terrain_base_height => "base_height",
            .terrain_erosion_mask => "erosion_mask",
            .terrain_material_tiles => "material_tiles",
            .spline_road_main => "road_main",
            .spline_path_side => "path_side",
            .scatter_grass_low => "grass_low",
            .scatter_pine_cluster => "pine_cluster",
            .scatter_rocks_medium => "rocks_medium",
            .scatter_density_mask => "density_mask",
            .atmosphere_fog_bank => "fog_bank",
            .atmosphere_sky_tone => "sky_tone",
            .ocean_wind => "wind",
            .ocean_waves => "waves",
            .water_volumes => "volumes",
            .water_surface => "surface",
            .water_currents => "currents",
        };
    }

    pub fn groupLabel(self: WorldLayerId) []const u8 {
        return switch (self) {
            .terrain_base_height, .terrain_erosion_mask, .terrain_material_tiles => "Terrain",
            .spline_road_main, .spline_path_side => "Splines",
            .scatter_grass_low, .scatter_pine_cluster, .scatter_rocks_medium, .scatter_density_mask => "Scatter",
            .atmosphere_fog_bank, .atmosphere_sky_tone => "Atmosphere",
            .ocean_wind, .ocean_waves => "Ocean",
            .water_volumes, .water_surface, .water_currents => "Water",
        };
    }
};

pub const WorldGridScale = enum {
    one_m,
    eight_m,
    thirty_two_m,

    pub fn label(self: WorldGridScale) []const u8 {
        return switch (self) {
            .one_m => "1m",
            .eight_m => "8m",
            .thirty_two_m => "32m",
        };
    }

    pub fn meters(self: WorldGridScale) f32 {
        return switch (self) {
            .one_m => 1.0,
            .eight_m => 8.0,
            .thirty_two_m => 32.0,
        };
    }

    pub fn tip(self: WorldGridScale) []const u8 {
        return switch (self) {
            .one_m => "1 meter grid snap",
            .eight_m => "8 meter grid snap",
            .thirty_two_m => "32 meter grid snap",
        };
    }
};

pub const WorldCurveHitTarget = enum {
    none,
    road,
    ocean_clip,
    water_volume,
    scatter_zone,
};

pub const WorldCurveHitElement = enum {
    none,
    point,
    segment,
    handle_start,
    handle_end,
    width_rail,
};

pub const WorldCurveHit = struct {
    target: WorldCurveHitTarget = .none,
    element: WorldCurveHitElement = .none,
    index: usize = 0,
    sub_index: usize = 0,
    distance_sq: f32 = std.math.inf(f32),

    pub fn isNone(self: WorldCurveHit) bool {
        return self.target == .none or self.element == .none;
    }

    pub fn sameElement(a: WorldCurveHit, b: WorldCurveHit) bool {
        return a.target == b.target and
            a.element == b.element and
            a.index == b.index and
            a.sub_index == b.sub_index;
    }
};

pub const WorldCurveDragState = struct {
    hit: WorldCurveHit = .{},
    start_x: f32 = 0,
    start_y: f32 = 0,
    start_value: f32 = 0,
};

pub const BlockoutOp = enum {
    add,
    subtract,

    pub fn label(self: BlockoutOp) []const u8 {
        return switch (self) {
            .add => "Add",
            .subtract => "Subtract",
        };
    }
};

pub const EditorAction = enum {
    continue_,
    close_project,
    quit_app,
};

pub const PropField = enum {
    none,
    pos_x,
    pos_y,
    pos_z,
    rot_x,
    rot_y,
    rot_z,
    scale_x,
    scale_y,
    scale_z,

    pub fn next(self: PropField) PropField {
        return switch (self) {
            .none => .pos_x,
            .pos_x => .pos_y,
            .pos_y => .pos_z,
            .pos_z => .rot_x,
            .rot_x => .rot_y,
            .rot_y => .rot_z,
            .rot_z => .scale_x,
            .scale_x => .scale_y,
            .scale_y => .scale_z,
            .scale_z => .pos_x,
        };
    }
};

pub const GizmoAxis = enum {
    x,
    y,
    z,
};

pub const MoveAxis = enum {
    xz,
    x,
    y,
    z,
    xy,
    yz,
};

pub const ViewCameraMode = enum {
    perspective,
    orthographic,

    pub fn label(self: ViewCameraMode) []const u8 {
        return switch (self) {
            .perspective => "Persp",
            .orthographic => "Ortho",
        };
    }
};

pub const ViewOrientation = enum {
    free,
    top,
    front,
    side,

    pub fn label(self: ViewOrientation) []const u8 {
        return switch (self) {
            .free => "Free",
            .top => "Top",
            .front => "Front",
            .side => "Side",
        };
    }
};

pub const ShadingMode = enum {
    wireframe,
    solid,
    material_preview,
    rendered,

    pub fn label(self: ShadingMode) []const u8 {
        return switch (self) {
            .wireframe => "Wireframe",
            .solid => "Solid",
            .material_preview => "Material Preview",
            .rendered => "Rendered",
        };
    }
};

test "shading mode labels are canonical" {
    try std.testing.expectEqualStrings("Wireframe", ShadingMode.wireframe.label());
    try std.testing.expectEqualStrings("Solid", ShadingMode.solid.label());
    try std.testing.expectEqualStrings("Material Preview", ShadingMode.material_preview.label());
    try std.testing.expectEqualStrings("Rendered", ShadingMode.rendered.label());
}

pub const TransformSpace = enum {
    world,
    local,

    pub fn label(self: TransformSpace) []const u8 {
        return switch (self) {
            .world => "World",
            .local => "Local",
        };
    }
};

pub const PivotMode = enum {
    pivot,
    center,

    pub fn label(self: PivotMode) []const u8 {
        return switch (self) {
            .pivot => "Pivot",
            .center => "Center",
        };
    }
};

pub const EditChannel = enum {
    position,
    scale,
};

pub const DragMode = enum {
    none,
    camera_orbit,
    camera_pan,
    camera_zoom,
    move_object,
    gizmo_move,
    move_vertex,
    move_edge,
    move_face,
    paint_texture,
    blockout_brush,
    architecture_curve,
    blockout_face_resize,
    life_pose,
    world_paint,
    world_scatter_zone,
    world_scatter_density,
    world_road,
    world_curve_gizmo,
    selection_box,
};

pub const CurveDrawMode = enum {
    freehand,
    point_by_point,

    pub fn label(self: CurveDrawMode) []const u8 {
        return switch (self) {
            .freehand => "Freehand",
            .point_by_point => "Point",
        };
    }
};

pub const RoadToolMode = enum {
    draw,
    select,
    shape,
    join,
    surface,

    pub fn label(self: RoadToolMode) []const u8 {
        return switch (self) {
            .draw => "Draw",
            .select => "Select",
            .shape => "Shape",
            .join => "Join",
            .surface => "Surface",
        };
    }
};

pub const RoadSurfaceMode = enum {
    decal,
    prop_sections,

    pub fn label(self: RoadSurfaceMode) []const u8 {
        return switch (self) {
            .decal => "Decal",
            .prop_sections => "Prop Sections",
        };
    }
};

pub const RoadTerrainMode = enum {
    conform,
    floating,
    tunnel_reserved,

    pub fn label(self: RoadTerrainMode) []const u8 {
        return switch (self) {
            .conform => "Conform",
            .floating => "Floating",
            .tunnel_reserved => "Tunnel Intent",
        };
    }
};

pub const ViewNavControl = enum {
    none,
    orbit,
    zoom,
    pan,
};

pub const PendingObjectDrag = enum {
    none,
    gizmo,
    move_object,
};

pub const click_drag_threshold_sq: f32 = 16.0;
