const std = @import("std");
const shared = @import("runtime_shared");
const friendly_engine = @import("friendly_engine");
const editor_math = shared.editor_math;
const geometry = shared.geometry;
const shared_color = shared.color;
const arch = shared.architecture;
const scene_blockout = shared.scene_blockout;
const scene_physics = shared.scene_physics;
const scene_object = @import("editor_scene_object.zig");
const scene_hierarchy = @import("editor_scene_hierarchy.zig");
const editor_raycast = @import("editor_raycast.zig");
const editor_draw = @import("editor_draw.zig");
const project_editor_edit = @import("project_editor_edit.zig");
const project_editor_state = @import("project_editor_state.zig");
const architecture = @import("project_editor_architecture.zig");
const blockout_primitives = @import("project_editor_blockout_primitives.zig");
const world_authoring = @import("project_editor_world_authoring.zig");
const world_authoring_manifest = @import("project_editor_world_authoring_manifest.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const SceneObject = scene_object.SceneObject;
const TextureSize = scene_object.TextureSize;
const fillCheckerTexture = scene_object.fillCheckerTexture;
const snapValue = editor_raycast.snapValue;
const snapVec3 = editor_raycast.snapVec3;
const raycastScene = editor_raycast.raycastScene;
const objectWorldBounds = editor_raycast.objectWorldBounds;
const aabbOverlaps = editor_raycast.aabbOverlaps;
const local_csg = friendly_engine.modules.local_csg;
const Bounds = struct { min: editor_math.Vec3, max: editor_math.Vec3 };
pub const DragPreviewBounds = Bounds;
const static_body = scene_physics.Body{ .kind = .static, .collider = .box, .mass = 0 };
const room_wall_color = shared_color.Color{ .r = 150, .g = 155, .b = 165, .a = 255 };
const wall_plan_color = shared_color.Color{ .r = 190, .g = 196, .b = 205, .a = 255 };
const floorplan_eps: f32 = 0.001;
const wall_close_distance: f32 = 0.35;
const architecture_building_component = arch.building_marker;
pub const addBlockoutBox = blockout_primitives.addBlockoutBox;
pub const addBlockoutBoxInternal = blockout_primitives.addBlockoutBoxInternal;
pub const addBlockoutCylinderAt = blockout_primitives.addBlockoutCylinderAt;
pub const addBlockoutRamp = blockout_primitives.addBlockoutRamp;
pub const addBlockoutRampAt = blockout_primitives.addBlockoutRampAt;
pub const addBlockoutWedgeAt = blockout_primitives.addBlockoutWedgeAt;
pub const subtractBlockoutBox = blockout_primitives.subtractBlockoutBox;
pub const subtractBlockoutWedge = blockout_primitives.subtractBlockoutWedge;
pub const subtractDoorwayBlockoutBox = blockout_primitives.subtractDoorwayBlockoutBox;
const addNamedBlockoutBox = blockout_primitives.addNamedBlockoutBox;
const appendOrientedRampQuad = blockout_primitives.appendOrientedRampQuad;
const appendOrientedRampTri = blockout_primitives.appendOrientedRampTri;
const appendRampQuad = blockout_primitives.appendRampQuad;
const appendRampTri = blockout_primitives.appendRampTri;
const appendRampVertex = blockout_primitives.appendRampVertex;
const buildGableRoofMesh = blockout_primitives.buildGableRoofMesh;
const buildPlayerStartMarkerMesh = blockout_primitives.buildPlayerStartMarkerMesh;
const roofPlaneNormal = blockout_primitives.roofPlaneNormal;

fn pointInViewport(state: *ProjectEditorState, x: f32, y: f32) bool {
    return editor_draw.pointInRect(x, y, state.viewport_screen_rect);
}

pub const brushAabbFromDrag = blockoutBrushAabb;
pub const rayIntersectsAabb = editor_raycast.rayIntersectsAabb;

const face_snap_offset: f32 = 0.001;

fn blockoutPointFromRay(state: *ProjectEditorState, screen_x: f32, screen_y: f32) ?editor_math.Vec3 {
    if (!pointInViewport(state, screen_x, screen_y)) return null;
    const local_x = screen_x - state.viewport_screen_rect.x;
    const local_y = screen_y - state.viewport_screen_rect.y;
    const ray = project_editor_state.rayFromViewport(
        state,
        local_x,
        local_y,
        state.viewport_screen_rect.w,
        state.viewport_screen_rect.h,
    );
    const grid = if (state.snap_enabled) state.snap_size else 0;

    if (state.snap_face) {
        if (raycastScene(ray.origin, ray.dir, state.objects.items)) |hit| {
            const offset = editor_math.Vec3.scale(hit.normal, face_snap_offset);
            return snapVec3(editor_math.Vec3.add(hit.position, offset), grid);
        }
    }

    const ground = editor_math.rayIntersectPlane(ray.origin, ray.dir, 0);
    if (ground) |pt| return snapVec3(pt, grid);
    return null;
}

pub fn screenToGroundPoint(state: *ProjectEditorState, screen_x: f32, screen_y: f32) ?editor_math.Vec3 {
    return blockoutPointFromRay(state, screen_x, screen_y);
}

pub fn beginBlockoutDrag(state: *ProjectEditorState, screen_x: f32, screen_y: f32) void {
    const pt = screenToGroundPoint(state, screen_x, screen_y) orelse return;
    state.blockout_drag_start = pt;
    state.blockout_drag_end = pt;
}

pub fn updateBlockoutDrag(state: *ProjectEditorState, screen_x: f32, screen_y: f32) void {
    const pt = screenToGroundPoint(state, screen_x, screen_y) orelse return;
    state.blockout_drag_end = pt;
}

pub fn blockoutBrushAabb(state: *ProjectEditorState) ?struct { min: editor_math.Vec3, max: editor_math.Vec3 } {
    const start = state.blockout_drag_start orelse return null;
    const end = state.blockout_drag_end orelse return null;
    const grid = if (state.snap_enabled) state.snap_size else 0;
    const min_x = snapValue(@min(start.x, end.x), grid);
    const max_x = snapValue(@max(start.x, end.x), grid);
    const min_z = snapValue(@min(start.z, end.z), grid);
    const max_z = snapValue(@max(start.z, end.z), grid);
    const step = if (state.snap_enabled) state.snap_size else 0.5;
    const width = if (max_x > min_x) max_x - min_x else step;
    const depth = if (max_z > min_z) max_z - min_z else step;

    if (state.snap_face) {
        const min_y = snapValue(@min(start.y, end.y), grid);
        const max_y = snapValue(@max(start.y, end.y), grid);
        const height = if (max_y > min_y) max_y - min_y else state.blockout_brush_size;
        return .{
            .min = .{ .x = min_x, .y = min_y, .z = min_z },
            .max = .{ .x = min_x + width, .y = min_y + height, .z = min_z + depth },
        };
    }

    const height = state.blockout_brush_size;
    return .{
        .min = .{ .x = min_x, .y = 0, .z = min_z },
        .max = .{ .x = min_x + width, .y = height, .z = min_z + depth },
    };
}

pub fn architectureDragPreviewAabb(state: *ProjectEditorState) ?DragPreviewBounds {
    const brush_bounds = blockoutBrushAabb(state) orelse return null;
    var bounds: DragPreviewBounds = .{ .min = brush_bounds.min, .max = brush_bounds.max };
    switch (state.architecture_tool) {
        .floorplan => {
            bounds.min.y = 0.0;
            bounds.max.y = @max(0.25, state.architecture_wall_height);
        },
        .door => {
            bounds.min.y = 0.0;
            bounds.max.y = @max(0.25, state.architecture_door_height);
        },
        .window => {
            bounds.min.y = state.architecture_window_sill;
            bounds.max.y = state.architecture_window_sill + @max(0.25, state.architecture_window_height);
        },
        .brush, .add, .subtract => {},
        else => return null,
    }
    return bounds;
}

pub fn finishBlockoutBrush(state: *ProjectEditorState) void {
    if (finishArchitecturePrimitiveDrag(state)) return;

    const bounds = blockoutBrushAabb(state) orelse return;
    if (state.blockout_op == .subtract) {
        switch (state.blockout_brush_shape) {
            .wedge => {
                subtractBlockoutWedge(state, bounds.min, bounds.max) catch {
                    project_editor_state.setStatus(state, "Wedge subtract failed");
                    return;
                };
                project_editor_state.setStatus(state, "Wedge subtract applied");
            },
            .box, .ramp, .cylinder => {
                subtractBlockoutBox(state, bounds.min, bounds.max) catch {
                    project_editor_state.setStatus(state, "Brush subtract failed");
                    return;
                };
                project_editor_state.setStatus(state, "Brush subtract applied");
            },
        }
        return;
    }

    switch (state.blockout_brush_shape) {
        .box => addBlockoutBox(state, bounds.min, bounds.max) catch {
            project_editor_state.setStatus(state, "Brush add failed");
            return;
        },
        .wedge => addBlockoutWedgeAt(state, bounds.min, bounds.max, true) catch {
            project_editor_state.setStatus(state, "Wedge add failed");
            return;
        },
        .ramp => addBlockoutRampAt(
            state,
            bounds.min,
            bounds.max.x - bounds.min.x,
            bounds.max.y - bounds.min.y,
            bounds.max.z - bounds.min.z,
        ) catch {
            project_editor_state.setStatus(state, "Ramp add failed");
            return;
        },
        .cylinder => addBlockoutCylinderAt(state, bounds.min, bounds.max, true) catch {
            project_editor_state.setStatus(state, "Cylinder add failed");
            return;
        },
    }
    project_editor_state.setStatus(state, switch (state.blockout_brush_shape) {
        .box => "Brush box added",
        .wedge => "Brush wedge added",
        .ramp => "Brush ramp added",
        .cylinder => "Brush cylinder added",
    });
}

fn finishArchitecturePrimitiveDrag(state: *ProjectEditorState) bool {
    switch (state.architecture_tool) {
        .floorplan => {
            addFloorplanFromDrag(state) catch {
                project_editor_state.setStatus(state, "Floorplan add failed");
            };
            return true;
        },
        .wall => {
            addWallFromDrag(state) catch {
                project_editor_state.setStatus(state, "Wall add failed");
            };
            return true;
        },
        .door => {
            cutOpeningFromDrag(state, .door) catch {
                project_editor_state.setStatus(state, "Door cut failed");
            };
            return true;
        },
        .window => {
            cutOpeningFromDrag(state, .window) catch {
                project_editor_state.setStatus(state, "Window cut failed");
            };
            return true;
        },
        else => return false,
    }
}

fn addFloorplanFromDrag(state: *ProjectEditorState) !void {
    const bounds = blockoutBrushAabb(state) orelse return;
    try addArchitectureBuildingFromBounds(state, bounds.min, bounds.max);
    project_editor_state.setStatus(state, "Architecture room drawn");
}

/// Mesh-generation view of one opening on a single wall segment, measured in
/// meters along the segment. Derived from `arch.WallOpening` at build time.
const WallSpanOpening = struct {
    start: f32,
    end: f32,
    bottom: f32,
    top: f32,
};

const WallEndpoint = enum {
    start,
    end,
};

const WallJoinKind = enum {
    miter,
    bevel,
    cap,
};

const WallEndpointJoin = struct {
    front: editor_math.Vec3,
    back: editor_math.Vec3,
    cap: bool,
    kind: WallJoinKind,
};

const JoinedWallSegment = struct {
    wall_id: u32,
    origin: editor_math.Vec3,
    dir: editor_math.Vec3,
    normal: editor_math.Vec3,
    length: f32,
    height: f32,
    thickness: f32,
    start_join: WallEndpointJoin,
    end_join: WallEndpointJoin,
};

const WallJoinGraph = struct {
    segments: []JoinedWallSegment,
    unjoined_crossings: usize = 0,

    pub fn deinit(self: *WallJoinGraph, allocator: std.mem.Allocator) void {
        allocator.free(self.segments);
        self.* = .{ .segments = &.{} };
    }
};

const WallEndpointPair = struct {
    front: editor_math.Vec3,
    back: editor_math.Vec3,
};

// The semantic building model now lives in `shared.architecture`. These aliases
// keep the editor-facing names stable.
pub const ArchFeatureKind = arch.FeatureKind;
pub const ArchRoofKind = arch.RoofKind;
pub const ArchOpeningKind = arch.OpeningKind;
const ArchitectureBuilding = arch.Building;
const ArchVertex = arch.PlanVertex;
const ArchWall = arch.WallEdge;
const roof_overhang: f32 = 0.3;
const roof_body_thickness: f32 = 0.18;
const fps_controller_component = "controller:fps";
const player_start_tag = "player_start";

fn parseArchitectureBuilding(allocator: std.mem.Allocator, components: []const []const u8) !arch.Building {
    return arch.Building.parse(allocator, components);
}

pub const ArchitectureSummary = struct {
    vertices: usize = 0,
    walls: usize = 0,
    openings: usize = 0,
    features: usize = 0,
    has_floor: bool = false,
    has_roof: bool = false,
    max_height: f32 = 0,
};

pub const ArchitectureWarnings = struct {
    wall_too_short: usize = 0,
    invalid_openings: usize = 0,
    overlapping_openings: usize = 0,
    unjoined_crossings: usize = 0,
    open_plan: bool = false,
    roof_unsupported: bool = false,
    steep_stairs: usize = 0,

    pub fn count(self: ArchitectureWarnings) usize {
        return self.wall_too_short + self.invalid_openings + self.overlapping_openings + self.unjoined_crossings + self.steep_stairs +
            @as(usize, if (self.open_plan) 1 else 0) +
            @as(usize, if (self.roof_unsupported) 1 else 0);
    }
};

pub const isArchitectureBuildingObject = architecture.isArchitectureBuildingObject;

fn addArchitectureBuildingFromBounds(state: *ProjectEditorState, min_pt: editor_math.Vec3, max_pt: editor_math.Vec3) !void {
    const min_x = @min(min_pt.x, max_pt.x);
    const max_x = @max(min_pt.x, max_pt.x);
    const min_z = @min(min_pt.z, max_pt.z);
    const max_z = @max(min_pt.z, max_pt.z);
    if (max_x - min_x <= floorplan_eps or max_z - min_z <= floorplan_eps) return error.InvalidArchitecturePlan;

    const height = @max(0.25, state.architecture_wall_height);
    const thickness = @max(0.05, state.architecture_wall_thickness);
    var building = arch.Building{};
    defer building.deinit(state.allocator);
    try building.vertices.append(state.allocator, .{ .id = 0, .x = min_x, .z = min_z });
    try building.vertices.append(state.allocator, .{ .id = 1, .x = max_x, .z = min_z });
    try building.vertices.append(state.allocator, .{ .id = 2, .x = max_x, .z = max_z });
    try building.vertices.append(state.allocator, .{ .id = 3, .x = min_x, .z = max_z });
    try building.walls.append(state.allocator, .{ .id = 0, .a = 0, .b = 1, .height = height, .thickness = thickness });
    try building.walls.append(state.allocator, .{ .id = 1, .a = 1, .b = 2, .height = height, .thickness = thickness });
    try building.walls.append(state.allocator, .{ .id = 2, .a = 2, .b = 3, .height = height, .thickness = thickness });
    try building.walls.append(state.allocator, .{ .id = 3, .a = 3, .b = 0, .height = height, .thickness = thickness });
    building.roof = .{ .kind = .flat, .pitch = 0, .overhang = 0.15 };

    try createBuildingObject(state, &building, "Architecture Building");
}

/// Create a scene object that owns a building: serialize the semantic model into
/// its components and generate the initial render mesh from that same model.
pub fn createBuildingObject(state: *ProjectEditorState, building: *const arch.Building, name_prefix: []const u8) !void {
    const name = try std.fmt.allocPrint(state.allocator, "{s} {d}", .{ name_prefix, state.next_object_id });
    defer state.allocator.free(name);
    _ = try createBuildingObjectWithOptions(state, building, .{ .name = name });
}

pub const BuildingObjectOptions = struct {
    name: []const u8,
    position: editor_math.Vec3 = .{ .x = 0, .y = 0, .z = 0 },
    parent_id: ?u64 = null,
    extra_components: []const []const u8 = &.{},
    properties: []const shared.scene_document.Property = &.{},
};

pub fn createBuildingObjectWithOptions(state: *ProjectEditorState, building: *const arch.Building, options: BuildingObjectOptions) !u64 {
    const components = try building.serialize(state.allocator);
    const merged_components = try mergeBuildingComponents(state.allocator, components, options.extra_components);
    errdefer {
        for (merged_components) |component| state.allocator.free(component);
        state.allocator.free(merged_components);
    }
    var mesh = try buildArchitectureBuildingMesh(state.allocator, building);
    errdefer mesh.deinit(state.allocator);
    const tex = try state.allocator.alloc(u8, TextureSize * TextureSize * 4);
    errdefer state.allocator.free(tex);
    fillCheckerTexture(tex, TextureSize, wall_plan_color.r, wall_plan_color.g, wall_plan_color.b);

    const name = try state.allocator.dupe(u8, options.name);
    errdefer state.allocator.free(name);
    const object_id = state.next_object_id;
    try state.objects.append(state.allocator, .{
        .id = object_id,
        .name = name,
        .mesh = mesh,
        .position = options.position,
        .rotation = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = tex,
        .base_color = wall_plan_color,
        .primitive_kind = null,
        .physics = static_body,
        .components = merged_components,
        .properties = try shared.scene_io.duplicateProperties(state.allocator, options.properties),
        .parent_id = options.parent_id,
        .layer = try state.allocator.dupe(u8, "architecture"),
    });
    architecture.setActiveBuilding(state, object_id);
    state.next_object_id += 1;
    state.selected_object = state.objects.items.len - 1;
    state.selected_vertex = null;
    state.selected_edge = null;
    state.selected_face = null;
    state.scene_dirty = true;
    return object_id;
}

fn mergeBuildingComponents(allocator: std.mem.Allocator, building_components: [][]u8, extra_components: []const []const u8) ![][]u8 {
    errdefer {
        for (building_components) |component| allocator.free(component);
        allocator.free(building_components);
    }
    const merged = try allocator.alloc([]u8, building_components.len + extra_components.len);
    var copied_extra: usize = 0;
    errdefer {
        for (merged[building_components.len..][0..copied_extra]) |component| allocator.free(component);
        allocator.free(merged);
    }
    for (building_components, 0..) |component, idx| merged[idx] = component;
    for (extra_components, 0..) |component, idx| {
        merged[building_components.len + idx] = try allocator.dupe(u8, component);
        copied_extra += 1;
    }
    allocator.free(building_components);
    return merged;
}

fn buildArchitectureBuildingMesh(allocator: std.mem.Allocator, building: *const arch.Building) !geometry.Mesh {
    var vertices: std.ArrayList(geometry.Vertex) = .empty;
    defer vertices.deinit(allocator);
    var indices: std.ArrayList(u32) = .empty;
    defer indices.deinit(allocator);

    if (building.walls.items.len > 0) {
        var join_graph = try buildWallJoinGraph(allocator, building);
        defer join_graph.deinit(allocator);

        for (building.walls.items, 0..) |wall, wall_index| {
            const segment = join_graph.segments[wall_index];
            var wall_openings = std.ArrayList(WallSpanOpening).empty;
            defer wall_openings.deinit(allocator);
            for (building.openings.items) |opening| {
                if (opening.wall_id != wall.id) continue;
                const center_m = opening.t * segment.length;
                const half = opening.width * 0.5;
                try wall_openings.append(allocator, .{
                    .start = std.math.clamp(center_m - half, 0.0, segment.length),
                    .end = std.math.clamp(center_m + half, 0.0, segment.length),
                    .bottom = std.math.clamp(opening.sill, 0.0, segment.height),
                    .top = std.math.clamp(opening.sill + opening.height, 0.0, segment.height),
                });
            }
            sortWallPlanOpenings(wall_openings.items);
            try appendWallPlanSegment(allocator, &vertices, &indices, segment, wall_openings.items);
        }
    }

    if (orderedClosedFootprint(allocator, building)) |footprint| {
        defer allocator.free(footprint);
        var floor: u32 = 0;
        while (floor < @max(@as(u32, 1), building.floors.count)) : (floor += 1) {
            try appendArchitectureFloor(allocator, &vertices, &indices, footprint, @as(f32, @floatFromInt(floor)) * building.floors.height, building.floors.slab_thickness);
        }
        if (building.roof) |roof| {
            try appendArchitectureRoof(allocator, &vertices, &indices, footprint, building.maxWallHeight(), roof);
        }
    } else |_| {}

    for (building.features.items) |feature| {
        switch (feature.kind) {
            .column => try appendColumnFeature(allocator, &vertices, &indices, feature),
            .beam => try appendBeamFeature(allocator, &vertices, &indices, feature),
            .stair => try appendStraightStairFeature(allocator, &vertices, &indices, feature),
            .spiral_stair => try appendSpiralStairFeature(allocator, &vertices, &indices, feature),
            .bartizan => try appendBartizanFeature(allocator, &vertices, &indices, feature),
            .arch => try appendArchFeature(allocator, &vertices, &indices, feature),
        }
    }

    for (building.foundations.items) |foundation| {
        try appendFoundation(allocator, &vertices, &indices, foundation);
    }

    return .{
        .vertices = try vertices.toOwnedSlice(allocator),
        .indices = try indices.toOwnedSlice(allocator),
    };
}

fn buildWallJoinGraph(allocator: std.mem.Allocator, building: *const arch.Building) !WallJoinGraph {
    try validateAuthoredWallIntersections(building);
    const segments = try allocator.alloc(JoinedWallSegment, building.walls.items.len);
    errdefer allocator.free(segments);

    for (building.walls.items, 0..) |wall, wall_index| {
        segments[wall_index] = try joinedWallSegmentFor(building, wall_index, wall);
    }
    return .{ .segments = segments };
}

fn joinedWallSegmentFor(building: *const arch.Building, wall_index: usize, wall: arch.WallEdge) !JoinedWallSegment {
    const a = building.findVertex(wall.a) orelse return error.InvalidArchitectureWall;
    const b = building.findVertex(wall.b) orelse return error.InvalidArchitectureWall;
    const dx = b.x - a.x;
    const dz = b.z - a.z;
    const length = @sqrt(dx * dx + dz * dz);
    if (length <= floorplan_eps) return error.InvalidArchitectureWall;
    const dir: editor_math.Vec3 = .{ .x = dx / length, .y = 0, .z = dz / length };
    const normal: editor_math.Vec3 = .{ .x = -dir.z, .y = 0, .z = dir.x };
    return .{
        .wall_id = wall.id,
        .origin = a.point(),
        .dir = dir,
        .normal = normal,
        .length = length,
        .height = wall.height,
        .thickness = wall.thickness,
        .start_join = try endpointJoinFor(building, wall_index, .start),
        .end_join = try endpointJoinFor(building, wall_index, .end),
    };
}

fn endpointJoinFor(building: *const arch.Building, wall_index: usize, endpoint: WallEndpoint) !WallEndpointJoin {
    const wall = building.walls.items[wall_index];
    const vertex_id = switch (endpoint) {
        .start => wall.a,
        .end => wall.b,
    };
    const vertex = building.findVertex(vertex_id) orelse return error.InvalidArchitectureWall;
    const incident_count = incidentWallCount(building, vertex_id);
    if (incident_count == 1) return capJoinFor(building, wall_index, endpoint);
    if (incident_count > 2) return error.UnsupportedArchitectureWallBranch;
    return miterJoinFor(building, wall_index, endpoint, vertex.point());
}

fn capJoinFor(building: *const arch.Building, wall_index: usize, endpoint: WallEndpoint) !WallEndpointJoin {
    const wall = building.walls.items[wall_index];
    const a = building.findVertex(wall.a) orelse return error.InvalidArchitectureWall;
    const b = building.findVertex(wall.b) orelse return error.InvalidArchitectureWall;
    const dx = b.x - a.x;
    const dz = b.z - a.z;
    const length = @sqrt(dx * dx + dz * dz);
    if (length <= floorplan_eps) return error.InvalidArchitectureWall;
    const dir: editor_math.Vec3 = .{ .x = dx / length, .y = 0, .z = dz / length };
    const normal: editor_math.Vec3 = .{ .x = -dir.z, .y = 0, .z = dir.x };
    const along: f32 = switch (endpoint) {
        .start => 0,
        .end => length,
    };
    const half_t = wallHalfThickness(wall.thickness);
    return .{
        .front = wallPlanPointOffset(a.point(), dir, normal, along, 0, half_t),
        .back = wallPlanPointOffset(a.point(), dir, normal, along, 0, -half_t),
        .cap = true,
        .kind = .cap,
    };
}

fn miterJoinFor(building: *const arch.Building, wall_index: usize, endpoint: WallEndpoint, vertex: editor_math.Vec3) !WallEndpointJoin {
    const wall = building.walls.items[wall_index];
    const other_index = connectedWallIndex(building, wall_index, switch (endpoint) {
        .start => wall.a,
        .end => wall.b,
    }) orelse return error.InvalidArchitectureWall;
    const current = try wallLineGeometry(building, wall_index);
    const other = try wallLineGeometry(building, other_index);
    const half_t = wallHalfThickness(wall.thickness);
    const other_half_t = wallHalfThickness(building.walls.items[other_index].thickness);
    const limit = @max(wall.thickness, building.walls.items[other_index].thickness) * 4.0;

    var kind: WallJoinKind = .miter;
    const front_result = railJoinPoint(vertex, current.dir, current.normal, half_t, other.dir, other.normal, other_half_t, limit) orelse blk: {
        kind = .bevel;
        break :blk RailJoinPoint{ .point = offsetPoint(vertex, current.normal, half_t), .clipped = true };
    };
    const back_result = railJoinPoint(vertex, current.dir, current.normal, -half_t, other.dir, other.normal, other_half_t, limit) orelse blk: {
        kind = .bevel;
        break :blk RailJoinPoint{ .point = offsetPoint(vertex, current.normal, -half_t), .clipped = true };
    };
    if (front_result.clipped or back_result.clipped) kind = .bevel;
    if (dot2d(current.dir, other.dir) < -0.95) kind = .bevel;
    return .{
        .front = front_result.point,
        .back = back_result.point,
        .cap = false,
        .kind = kind,
    };
}

const RailJoinPoint = struct {
    point: editor_math.Vec3,
    clipped: bool = false,
};

const WallLineGeometry = struct {
    dir: editor_math.Vec3,
    normal: editor_math.Vec3,
};

fn wallLineGeometry(building: *const arch.Building, wall_index: usize) !WallLineGeometry {
    const wall = building.walls.items[wall_index];
    const a = building.findVertex(wall.a) orelse return error.InvalidArchitectureWall;
    const b = building.findVertex(wall.b) orelse return error.InvalidArchitectureWall;
    const dx = b.x - a.x;
    const dz = b.z - a.z;
    const length = @sqrt(dx * dx + dz * dz);
    if (length <= floorplan_eps) return error.InvalidArchitectureWall;
    const dir: editor_math.Vec3 = .{ .x = dx / length, .y = 0, .z = dz / length };
    return .{
        .dir = dir,
        .normal = .{ .x = -dir.z, .y = 0, .z = dir.x },
    };
}

fn railJoinPoint(
    vertex: editor_math.Vec3,
    current_dir: editor_math.Vec3,
    current_normal: editor_math.Vec3,
    current_offset: f32,
    other_dir: editor_math.Vec3,
    other_normal: editor_math.Vec3,
    other_half_t: f32,
    limit: f32,
) ?RailJoinPoint {
    const current_base = offsetPoint(vertex, current_normal, current_offset);
    var best: ?editor_math.Vec3 = null;
    var best_dist = std.math.floatMax(f32);
    const signs = [_]f32{ 1, -1 };
    for (signs) |sign| {
        const other_base = offsetPoint(vertex, other_normal, other_half_t * sign);
        const candidate = intersectLines2d(current_base, current_dir, other_base, other_dir) orelse continue;
        const dist = pointDistance2d(vertex, candidate);
        if (dist < best_dist) {
            best = candidate;
            best_dist = dist;
        }
    }
    const selected = best orelse return null;
    if (best_dist <= @max(limit, floorplan_eps)) return .{ .point = selected };

    const base_dist = pointDistance2d(vertex, current_base);
    const remaining = @max(limit - base_dist, 0.0);
    const from_base: editor_math.Vec3 = .{ .x = selected.x - current_base.x, .y = 0, .z = selected.z - current_base.z };
    const len = @sqrt(from_base.x * from_base.x + from_base.z * from_base.z);
    if (len <= floorplan_eps) return .{ .point = current_base, .clipped = true };
    return .{
        .point = .{
            .x = current_base.x + from_base.x / len * remaining,
            .y = 0,
            .z = current_base.z + from_base.z / len * remaining,
        },
        .clipped = true,
    };
}

fn intersectLines2d(a: editor_math.Vec3, dir_a: editor_math.Vec3, b: editor_math.Vec3, dir_b: editor_math.Vec3) ?editor_math.Vec3 {
    const denom = cross2d(dir_a, dir_b);
    if (@abs(denom) <= floorplan_eps) return null;
    const delta: editor_math.Vec3 = .{ .x = b.x - a.x, .y = 0, .z = b.z - a.z };
    const t = cross2d(delta, dir_b) / denom;
    return .{
        .x = a.x + dir_a.x * t,
        .y = 0,
        .z = a.z + dir_a.z * t,
    };
}

fn offsetPoint(point: editor_math.Vec3, normal: editor_math.Vec3, offset: f32) editor_math.Vec3 {
    return .{
        .x = point.x + normal.x * offset,
        .y = 0,
        .z = point.z + normal.z * offset,
    };
}

fn incidentWallCount(building: *const arch.Building, vertex_id: u32) usize {
    var count: usize = 0;
    for (building.walls.items) |wall| {
        if (wall.a == vertex_id or wall.b == vertex_id) count += 1;
    }
    return count;
}

fn connectedWallIndex(building: *const arch.Building, wall_index: usize, vertex_id: u32) ?usize {
    for (building.walls.items, 0..) |wall, idx| {
        if (idx == wall_index) continue;
        if (wall.a == vertex_id or wall.b == vertex_id) return idx;
    }
    return null;
}

fn wallHalfThickness(thickness: f32) f32 {
    return @max(0.02, thickness * 0.5);
}

fn validateAuthoredWallIntersections(building: *const arch.Building) !void {
    for (building.walls.items, 0..) |lhs, lhs_index| {
        const lhs_a = building.findVertex(lhs.a) orelse return error.InvalidArchitectureWall;
        const lhs_b = building.findVertex(lhs.b) orelse return error.InvalidArchitectureWall;
        for (building.walls.items[lhs_index + 1 ..]) |rhs| {
            if (wallsShareAuthoredVertex(lhs, rhs)) continue;
            const rhs_a = building.findVertex(rhs.a) orelse return error.InvalidArchitectureWall;
            const rhs_b = building.findVertex(rhs.b) orelse return error.InvalidArchitectureWall;
            if (segmentsCrossOrOverlap2d(lhs_a.point(), lhs_b.point(), rhs_a.point(), rhs_b.point())) {
                return error.UnjoinedArchitectureWallCrossing;
            }
        }
    }
}

fn wallsShareAuthoredVertex(a: arch.WallEdge, b: arch.WallEdge) bool {
    return a.a == b.a or a.a == b.b or a.b == b.a or a.b == b.b;
}

fn segmentsCrossOrOverlap2d(a0: editor_math.Vec3, a1: editor_math.Vec3, b0: editor_math.Vec3, b1: editor_math.Vec3) bool {
    const a_dir: editor_math.Vec3 = .{ .x = a1.x - a0.x, .y = 0, .z = a1.z - a0.z };
    const b_dir: editor_math.Vec3 = .{ .x = b1.x - b0.x, .y = 0, .z = b1.z - b0.z };
    const denom = cross2d(a_dir, b_dir);
    const delta: editor_math.Vec3 = .{ .x = b0.x - a0.x, .y = 0, .z = b0.z - a0.z };
    if (@abs(denom) > floorplan_eps) {
        const t = cross2d(delta, b_dir) / denom;
        const u = cross2d(delta, a_dir) / denom;
        return t > floorplan_eps and t < 1.0 - floorplan_eps and u > floorplan_eps and u < 1.0 - floorplan_eps;
    }
    if (@abs(cross2d(delta, a_dir)) > floorplan_eps) return false;
    const a_len2 = dot2d(a_dir, a_dir);
    if (a_len2 <= floorplan_eps) return false;
    const t0 = dot2d(.{ .x = b0.x - a0.x, .y = 0, .z = b0.z - a0.z }, a_dir) / a_len2;
    const t1 = dot2d(.{ .x = b1.x - a0.x, .y = 0, .z = b1.z - a0.z }, a_dir) / a_len2;
    const overlap_start = @max(@min(t0, t1), 0.0);
    const overlap_end = @min(@max(t0, t1), 1.0);
    return overlap_end - overlap_start > floorplan_eps;
}

fn cross2d(a: editor_math.Vec3, b: editor_math.Vec3) f32 {
    return a.x * b.z - a.z * b.x;
}

fn dot2d(a: editor_math.Vec3, b: editor_math.Vec3) f32 {
    return a.x * b.x + a.z * b.z;
}

fn pointDistance2d(a: editor_math.Vec3, b: editor_math.Vec3) f32 {
    const dx = b.x - a.x;
    const dz = b.z - a.z;
    return @sqrt(dx * dx + dz * dz);
}

test "architecture connected walls suppress internal caps" {
    var building = arch.Building{};
    defer building.deinit(std.testing.allocator);
    try appendTestArchVertex(&building, 0, 0, 0);
    try appendTestArchVertex(&building, 1, 4, 0);
    try appendTestArchVertex(&building, 2, 4, 3);
    try appendTestArchWall(&building, 0, 0, 1);
    try appendTestArchWall(&building, 1, 1, 2);

    var graph = try buildWallJoinGraph(std.testing.allocator, &building);
    defer graph.deinit(std.testing.allocator);
    try std.testing.expect(!graph.segments[0].end_join.cap);
    try std.testing.expect(!graph.segments[1].start_join.cap);
    try std.testing.expectEqual(WallJoinKind.miter, graph.segments[0].end_join.kind);

    var mesh = try buildArchitectureBuildingMesh(std.testing.allocator, &building);
    defer mesh.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 60), mesh.indices.len);
}

test "architecture wall prisms assign normals per face" {
    var building = arch.Building{};
    defer building.deinit(std.testing.allocator);
    try appendTestArchVertex(&building, 0, 0, 0);
    try appendTestArchVertex(&building, 1, 4, 0);
    try appendTestArchWall(&building, 0, 0, 1);

    var mesh = try buildArchitectureBuildingMesh(std.testing.allocator, &building);
    defer mesh.deinit(std.testing.allocator);
    try std.testing.expect(meshHasNormal(mesh, .{ .x = 0, .y = 0, .z = 1 }));
    try std.testing.expect(meshHasNormal(mesh, .{ .x = 0, .y = 0, .z = -1 }));
    try std.testing.expect(meshHasNormal(mesh, .{ .x = 0, .y = 1, .z = 0 }));
    try std.testing.expect(meshHasNormal(mesh, .{ .x = 0, .y = -1, .z = 0 }));
    try std.testing.expect(meshHasNormal(mesh, .{ .x = 1, .y = 0, .z = 0 }));
    try std.testing.expect(meshHasNormal(mesh, .{ .x = -1, .y = 0, .z = 0 }));
}

test "architecture closed rectangle has merged corners and no internal caps" {
    var building = arch.Building{};
    defer building.deinit(std.testing.allocator);
    try appendTestArchVertex(&building, 0, 0, 0);
    try appendTestArchVertex(&building, 1, 4, 0);
    try appendTestArchVertex(&building, 2, 4, 3);
    try appendTestArchVertex(&building, 3, 0, 3);
    try appendTestArchWall(&building, 0, 0, 1);
    try appendTestArchWall(&building, 1, 1, 2);
    try appendTestArchWall(&building, 2, 2, 3);
    try appendTestArchWall(&building, 3, 3, 0);

    var graph = try buildWallJoinGraph(std.testing.allocator, &building);
    defer graph.deinit(std.testing.allocator);
    for (graph.segments) |segment| {
        try std.testing.expect(!segment.start_join.cap);
        try std.testing.expect(!segment.end_join.cap);
    }

    var mesh = try buildArchitectureBuildingMesh(std.testing.allocator, &building);
    defer mesh.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 132), mesh.indices.len);
}

test "architecture closed floors emit solid slabs" {
    var building = arch.Building{};
    defer building.deinit(std.testing.allocator);
    building.floors = .{ .count = 1, .height = 3.0, .slab_thickness = 0.22 };
    try appendTestArchVertex(&building, 0, 0, 0);
    try appendTestArchVertex(&building, 1, 4, 0);
    try appendTestArchVertex(&building, 2, 4, 3);
    try appendTestArchVertex(&building, 3, 0, 3);
    try appendTestArchWall(&building, 0, 0, 1);
    try appendTestArchWall(&building, 1, 1, 2);
    try appendTestArchWall(&building, 2, 2, 3);
    try appendTestArchWall(&building, 3, 3, 0);

    var mesh = try buildArchitectureBuildingMesh(std.testing.allocator, &building);
    defer mesh.deinit(std.testing.allocator);
    try std.testing.expect(meshHasVertexAtY(mesh, 0.0));
    try std.testing.expect(meshHasVertexAtY(mesh, -0.22));
    try std.testing.expect(meshHasVertexWithNormalAtY(mesh, -0.22, .{ .x = 0, .y = -1, .z = 0 }));
    try std.testing.expect(meshHasVertexWithHorizontalNormalAtY(mesh, -0.22));
}

test "architecture concave floors do not span open notches" {
    const footprint = [_]editor_math.Vec3{
        .{ .x = -25.5, .y = 0, .z = -5.2 },
        .{ .x = -7.0, .y = 0, .z = -5.2 },
        .{ .x = -7.0, .y = 0, .z = 0.0 },
        .{ .x = 7.0, .y = 0, .z = 0.0 },
        .{ .x = 7.0, .y = 0, .z = -5.2 },
        .{ .x = 25.5, .y = 0, .z = -5.2 },
        .{ .x = 25.5, .y = 0, .z = 13.6 },
        .{ .x = 7.0, .y = 0, .z = 13.6 },
        .{ .x = 7.0, .y = 0, .z = 8.4 },
        .{ .x = -7.0, .y = 0, .z = 8.4 },
        .{ .x = -7.0, .y = 0, .z = 13.6 },
        .{ .x = -25.5, .y = 0, .z = 13.6 },
    };
    var vertices: std.ArrayList(geometry.Vertex) = .empty;
    defer vertices.deinit(std.testing.allocator);
    var indices: std.ArrayList(u32) = .empty;
    defer indices.deinit(std.testing.allocator);
    try appendArchitectureFloor(std.testing.allocator, &vertices, &indices, &footprint, 0.0, 0.22);
    var mesh = geometry.Mesh{
        .vertices = try vertices.toOwnedSlice(std.testing.allocator),
        .indices = try indices.toOwnedSlice(std.testing.allocator),
    };
    defer mesh.deinit(std.testing.allocator);
    try std.testing.expect(!meshHasUpwardTriangleCentroidInRect(mesh, 0.0, -6.8, 6.8, -5.0, -0.2));
    try std.testing.expect(!meshHasUpwardTriangleCentroidInRect(mesh, 0.0, -6.8, 6.8, 8.6, 13.3));
}

test "architecture wall prism winding matches emitted normals" {
    var building = arch.Building{};
    defer building.deinit(std.testing.allocator);
    try appendTestArchVertex(&building, 0, 0, 0);
    try appendTestArchVertex(&building, 1, 4, 0);
    try appendTestArchWall(&building, 0, 0, 1);

    var mesh = try buildArchitectureBuildingMesh(std.testing.allocator, &building);
    defer mesh.deinit(std.testing.allocator);
    try std.testing.expect(meshTriangleWindingMatchesNormals(mesh));
}

test "architecture joined wall prism winding matches emitted normals" {
    var building = arch.Building{};
    defer building.deinit(std.testing.allocator);
    try appendTestArchVertex(&building, 0, 0, 0);
    try appendTestArchVertex(&building, 1, 4, 0);
    try appendTestArchVertex(&building, 2, 4, 3);
    try appendTestArchVertex(&building, 3, 0, 3);
    try appendTestArchWall(&building, 0, 0, 1);
    try appendTestArchWall(&building, 1, 1, 2);
    try appendTestArchWall(&building, 2, 2, 3);
    try appendTestArchWall(&building, 3, 3, 0);

    var mesh = try buildArchitectureBuildingMesh(std.testing.allocator, &building);
    defer mesh.deinit(std.testing.allocator);
    try std.testing.expect(meshTriangleWindingMatchesNormals(mesh));
}

test "architecture open chain keeps caps only at chain ends" {
    var building = arch.Building{};
    defer building.deinit(std.testing.allocator);
    try appendTestArchVertex(&building, 0, 0, 0);
    try appendTestArchVertex(&building, 1, 3, 0);
    try appendTestArchVertex(&building, 2, 3, 3);
    try appendTestArchVertex(&building, 3, 6, 3);
    try appendTestArchWall(&building, 0, 0, 1);
    try appendTestArchWall(&building, 1, 1, 2);
    try appendTestArchWall(&building, 2, 2, 3);

    var graph = try buildWallJoinGraph(std.testing.allocator, &building);
    defer graph.deinit(std.testing.allocator);
    try std.testing.expect(graph.segments[0].start_join.cap);
    try std.testing.expect(!graph.segments[0].end_join.cap);
    try std.testing.expect(!graph.segments[1].start_join.cap);
    try std.testing.expect(!graph.segments[1].end_join.cap);
    try std.testing.expect(!graph.segments[2].start_join.cap);
    try std.testing.expect(graph.segments[2].end_join.cap);

    var mesh = try buildArchitectureBuildingMesh(std.testing.allocator, &building);
    defer mesh.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 84), mesh.indices.len);
}

test "architecture acute angle uses bevel safety limit" {
    var building = arch.Building{};
    defer building.deinit(std.testing.allocator);
    try appendTestArchVertex(&building, 0, 0, 0);
    try appendTestArchVertex(&building, 1, 4, 0);
    try appendTestArchVertex(&building, 2, 0.2, 0.25);
    try appendTestArchWall(&building, 0, 0, 1);
    try appendTestArchWall(&building, 1, 1, 2);

    var graph = try buildWallJoinGraph(std.testing.allocator, &building);
    defer graph.deinit(std.testing.allocator);
    try std.testing.expectEqual(WallJoinKind.bevel, graph.segments[0].end_join.kind);
    try std.testing.expect(pointDistance2d(.{ .x = 4, .y = 0, .z = 0 }, graph.segments[0].end_join.front) <= 1.2);
}

test "architecture door and window openings keep joined wall thickness faces" {
    var building = arch.Building{};
    defer building.deinit(std.testing.allocator);
    try appendTestArchVertex(&building, 0, 0, 0);
    try appendTestArchVertex(&building, 1, 5, 0);
    try appendTestArchVertex(&building, 2, 5, 4);
    try appendTestArchWall(&building, 0, 0, 1);
    try appendTestArchWall(&building, 1, 1, 2);
    try building.openings.append(std.testing.allocator, .{ .id = 0, .wall_id = 0, .kind = .door, .t = 0.18, .width = 0.9, .height = 2.1, .sill = 0 });
    try building.openings.append(std.testing.allocator, .{ .id = 1, .wall_id = 1, .kind = .window, .t = 0.5, .width = 0.9, .height = 1.0, .sill = 0.9 });

    var mesh = try buildArchitectureBuildingMesh(std.testing.allocator, &building);
    defer mesh.deinit(std.testing.allocator);
    try std.testing.expect(mesh.indices.len > 84);
    try std.testing.expect(meshHasVertexAtY(mesh, 0.9));
    try std.testing.expect(meshHasVertexAtY(mesh, 1.9));
}

test "architecture crossing walls without shared vertices are rejected" {
    var building = arch.Building{};
    defer building.deinit(std.testing.allocator);
    try appendTestArchVertex(&building, 0, 0, 0);
    try appendTestArchVertex(&building, 1, 4, 0);
    try appendTestArchVertex(&building, 2, 2, -1);
    try appendTestArchVertex(&building, 3, 2, 1);
    try appendTestArchWall(&building, 0, 0, 1);
    try appendTestArchWall(&building, 1, 2, 3);

    try std.testing.expectError(error.UnjoinedArchitectureWallCrossing, buildArchitectureBuildingMesh(std.testing.allocator, &building));
}

test "architecture roofs emit solid bodies with matching windings" {
    inline for (.{ ArchRoofKind.flat, ArchRoofKind.shed, ArchRoofKind.gable, ArchRoofKind.conical }) |kind| {
        var building = arch.Building{};
        defer building.deinit(std.testing.allocator);
        try appendTestArchVertex(&building, 0, 0, 0);
        try appendTestArchVertex(&building, 1, 4, 0);
        try appendTestArchVertex(&building, 2, 4, 3);
        try appendTestArchVertex(&building, 3, 0, 3);
        try appendTestArchWall(&building, 0, 0, 1);
        try appendTestArchWall(&building, 1, 1, 2);
        try appendTestArchWall(&building, 2, 2, 3);
        try appendTestArchWall(&building, 3, 3, 0);
        building.roof = .{ .kind = kind, .pitch = 0.55, .overhang = 0.2 };

        var mesh = try buildArchitectureBuildingMesh(std.testing.allocator, &building);
        defer mesh.deinit(std.testing.allocator);
        try std.testing.expect(meshTriangleWindingMatchesNormals(mesh));
        try std.testing.expect(meshHasVertexWithNormalAboveY(mesh, building.maxWallHeight() - 0.15, .{ .x = 0, .y = -1, .z = 0 }));
        try std.testing.expect(meshHasVertexWithHorizontalNormalAboveY(mesh, building.maxWallHeight() - 0.15));
    }
}

fn appendTestArchVertex(building: *arch.Building, id: u32, x: f32, z: f32) !void {
    try building.vertices.append(std.testing.allocator, .{ .id = id, .x = x, .z = z });
}

fn appendTestArchWall(building: *arch.Building, id: u32, a: u32, b: u32) !void {
    try building.walls.append(std.testing.allocator, .{ .id = id, .a = a, .b = b, .height = 3.0, .thickness = 0.3 });
}

fn meshHasVertexAtY(mesh: geometry.Mesh, y: f32) bool {
    for (mesh.vertices) |vertex| {
        if (@abs(vertex.position.y - y) <= 0.001) return true;
    }
    return false;
}

fn meshHasVertexWithNormalAtY(mesh: geometry.Mesh, y: f32, normal: editor_math.Vec3) bool {
    for (mesh.vertices) |vertex| {
        if (@abs(vertex.position.y - y) > 0.001) continue;
        if (vec3AlmostEqual(vertex.normal, normal)) return true;
    }
    return false;
}

fn meshHasVertexWithHorizontalNormalAtY(mesh: geometry.Mesh, y: f32) bool {
    for (mesh.vertices) |vertex| {
        if (@abs(vertex.position.y - y) > 0.001) continue;
        if (@abs(vertex.normal.y) <= 0.001 and editor_math.Vec3.length(vertex.normal) > 0.99) return true;
    }
    return false;
}

fn meshHasVertexWithNormalAboveY(mesh: geometry.Mesh, y: f32, normal: editor_math.Vec3) bool {
    for (mesh.vertices) |vertex| {
        if (vertex.position.y <= y) continue;
        if (vec3AlmostEqual(vertex.normal, normal)) return true;
    }
    return false;
}

fn meshHasVertexWithHorizontalNormalAboveY(mesh: geometry.Mesh, y: f32) bool {
    for (mesh.vertices) |vertex| {
        if (vertex.position.y <= y) continue;
        if (@abs(vertex.normal.y) <= 0.001 and editor_math.Vec3.length(vertex.normal) > 0.99) return true;
    }
    return false;
}

fn meshHasNormal(mesh: geometry.Mesh, normal: editor_math.Vec3) bool {
    for (mesh.vertices) |vertex| {
        if (vec3AlmostEqual(vertex.normal, normal)) return true;
    }
    return false;
}

fn meshHasUpwardTriangleCentroidInRect(mesh: geometry.Mesh, y: f32, min_x: f32, max_x: f32, min_z: f32, max_z: f32) bool {
    var tri: usize = 0;
    while (tri + 2 < mesh.indices.len) : (tri += 3) {
        const v0 = mesh.vertices[mesh.indices[tri]];
        const v1 = mesh.vertices[mesh.indices[tri + 1]];
        const v2 = mesh.vertices[mesh.indices[tri + 2]];
        if (v0.normal.y < 0.9 or v1.normal.y < 0.9 or v2.normal.y < 0.9) continue;
        const center = editor_math.Vec3.scale(editor_math.Vec3.add(editor_math.Vec3.add(v0.position, v1.position), v2.position), 1.0 / 3.0);
        if (@abs(center.y - y) > 0.001) continue;
        if (center.x >= min_x and center.x <= max_x and center.z >= min_z and center.z <= max_z) return true;
    }
    return false;
}

fn meshTriangleWindingMatchesNormals(mesh: geometry.Mesh) bool {
    var tri: usize = 0;
    while (tri + 2 < mesh.indices.len) : (tri += 3) {
        const v0 = mesh.vertices[mesh.indices[tri]];
        const v1 = mesh.vertices[mesh.indices[tri + 1]];
        const v2 = mesh.vertices[mesh.indices[tri + 2]];
        const winding_normal = roofTriangleNormal(v0.position, v1.position, v2.position);
        if (editor_math.Vec3.dot(winding_normal, v0.normal) <= 0.5) return false;
        if (editor_math.Vec3.dot(winding_normal, v1.normal) <= 0.5) return false;
        if (editor_math.Vec3.dot(winding_normal, v2.normal) <= 0.5) return false;
    }
    return mesh.indices.len > 0;
}

fn vec3AlmostEqual(a: editor_math.Vec3, b: editor_math.Vec3) bool {
    return @abs(a.x - b.x) <= 0.001 and @abs(a.y - b.y) <= 0.001 and @abs(a.z - b.z) <= 0.001;
}

fn orderedClosedFootprint(allocator: std.mem.Allocator, building: *const arch.Building) ![]editor_math.Vec3 {
    if (building.walls.items.len < 3) return error.OpenArchitecturePlan;
    var points = try allocator.alloc(editor_math.Vec3, building.walls.items.len);
    errdefer allocator.free(points);
    var current = building.walls.items[0].a;
    for (building.walls.items, 0..) |wall, idx| {
        if (wall.a != current) return error.OpenArchitecturePlan;
        const vertex = building.findVertex(wall.a) orelse return error.InvalidArchitectureWall;
        points[idx] = vertex.point();
        current = wall.b;
    }
    if (current != building.walls.items[0].a) return error.OpenArchitecturePlan;
    return points;
}

fn appendArchitectureFloor(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(geometry.Vertex),
    indices: *std.ArrayList(u32),
    footprint: []const editor_math.Vec3,
    y: f32,
    slab_thickness: f32,
) !void {
    if (footprint.len < 3) return;
    const triangles = try triangulateFootprint(allocator, footprint);
    defer allocator.free(triangles);
    const ccw = footprintSignedArea(footprint) >= 0;
    const top_y = y;
    const bottom_y = y - @max(0.02, slab_thickness);
    const top_base: u32 = @intCast(vertices.items.len);
    for (footprint) |point| {
        try appendRampVertex(allocator, vertices, .{ .x = point.x, .y = top_y, .z = point.z }, .{ .x = 0, .y = 1, .z = 0 }, .{ .x = point.x, .y = point.z });
    }
    for (triangles) |tri| {
        try appendFloorTriangle(indices, allocator, top_base, tri, ccw, true);
    }

    const bottom_base: u32 = @intCast(vertices.items.len);
    for (footprint) |point| {
        try appendRampVertex(allocator, vertices, .{ .x = point.x, .y = bottom_y, .z = point.z }, .{ .x = 0, .y = -1, .z = 0 }, .{ .x = point.x, .y = point.z });
    }
    for (triangles) |tri| {
        try appendFloorTriangle(indices, allocator, bottom_base, tri, ccw, false);
    }

    for (footprint, 0..) |point, idx| {
        const next = footprint[(idx + 1) % footprint.len];
        const dx = next.x - point.x;
        const dz = next.z - point.z;
        const len = @sqrt(dx * dx + dz * dz);
        if (len <= floorplan_eps) continue;
        const normal: editor_math.Vec3 = if (ccw)
            .{ .x = dz / len, .y = 0, .z = -dx / len }
        else
            .{ .x = -dz / len, .y = 0, .z = dx / len };
        try appendRampQuad(
            allocator,
            vertices,
            indices,
            .{ .x = point.x, .y = bottom_y, .z = point.z },
            .{ .x = next.x, .y = bottom_y, .z = next.z },
            .{ .x = next.x, .y = top_y, .z = next.z },
            .{ .x = point.x, .y = top_y, .z = point.z },
            normal,
        );
    }
}

const FloorTriangle = struct {
    a: usize,
    b: usize,
    c: usize,
};

fn appendFloorTriangle(
    indices: *std.ArrayList(u32),
    allocator: std.mem.Allocator,
    base: u32,
    tri: FloorTriangle,
    ccw: bool,
    top: bool,
) !void {
    const a = base + @as(u32, @intCast(tri.a));
    const b = base + @as(u32, @intCast(tri.b));
    const c = base + @as(u32, @intCast(tri.c));
    if (top == ccw) {
        try indices.appendSlice(allocator, &.{ a, c, b });
    } else {
        try indices.appendSlice(allocator, &.{ a, b, c });
    }
}

fn triangulateFootprint(allocator: std.mem.Allocator, footprint: []const editor_math.Vec3) ![]FloorTriangle {
    if (footprint.len < 3) return error.InvalidArchitectureFloor;
    var order = try allocator.alloc(usize, footprint.len);
    defer allocator.free(order);
    for (order, 0..) |*entry, idx| entry.* = idx;
    var remaining = footprint.len;
    const ccw = footprintSignedArea(footprint) >= 0;
    var triangles: std.ArrayList(FloorTriangle) = .empty;
    errdefer triangles.deinit(allocator);
    var guard: usize = 0;
    while (remaining > 3) {
        guard += 1;
        if (guard > footprint.len * footprint.len) return error.InvalidArchitectureFloor;
        var clipped = false;
        var i: usize = 0;
        while (i < remaining) : (i += 1) {
            const prev = order[(i + remaining - 1) % remaining];
            const current = order[i];
            const next = order[(i + 1) % remaining];
            if (!isFootprintEar(footprint, order[0..remaining], prev, current, next, ccw)) continue;
            try triangles.append(allocator, .{ .a = prev, .b = current, .c = next });
            var move = i;
            while (move + 1 < remaining) : (move += 1) {
                order[move] = order[move + 1];
            }
            remaining -= 1;
            clipped = true;
            break;
        }
        if (!clipped) return error.InvalidArchitectureFloor;
    }
    try triangles.append(allocator, .{ .a = order[0], .b = order[1], .c = order[2] });
    return triangles.toOwnedSlice(allocator);
}

fn isFootprintEar(
    footprint: []const editor_math.Vec3,
    order: []const usize,
    prev: usize,
    current: usize,
    next: usize,
    ccw: bool,
) bool {
    if (!isFootprintConvex(footprint[prev], footprint[current], footprint[next], ccw)) return false;
    for (order) |idx| {
        if (idx == prev or idx == current or idx == next) continue;
        if (pointInsideFootprintTriangle(footprint[idx], footprint[prev], footprint[current], footprint[next])) return false;
    }
    return true;
}

fn isFootprintConvex(a: editor_math.Vec3, b: editor_math.Vec3, c: editor_math.Vec3, ccw: bool) bool {
    const ab: editor_math.Vec3 = .{ .x = b.x - a.x, .y = 0, .z = b.z - a.z };
    const bc: editor_math.Vec3 = .{ .x = c.x - b.x, .y = 0, .z = c.z - b.z };
    const cross = cross2d(ab, bc);
    return if (ccw) cross > floorplan_eps else cross < -floorplan_eps;
}

fn pointInsideFootprintTriangle(p: editor_math.Vec3, a: editor_math.Vec3, b: editor_math.Vec3, c: editor_math.Vec3) bool {
    const d0 = cross2d(.{ .x = b.x - a.x, .y = 0, .z = b.z - a.z }, .{ .x = p.x - a.x, .y = 0, .z = p.z - a.z });
    const d1 = cross2d(.{ .x = c.x - b.x, .y = 0, .z = c.z - b.z }, .{ .x = p.x - b.x, .y = 0, .z = p.z - b.z });
    const d2 = cross2d(.{ .x = a.x - c.x, .y = 0, .z = a.z - c.z }, .{ .x = p.x - c.x, .y = 0, .z = p.z - c.z });
    const has_neg = d0 < -floorplan_eps or d1 < -floorplan_eps or d2 < -floorplan_eps;
    const has_pos = d0 > floorplan_eps or d1 > floorplan_eps or d2 > floorplan_eps;
    return !(has_neg and has_pos);
}

fn footprintSignedArea(footprint: []const editor_math.Vec3) f32 {
    var area: f32 = 0;
    for (footprint, 0..) |point, idx| {
        const next = footprint[(idx + 1) % footprint.len];
        area += point.x * next.z - next.x * point.z;
    }
    return area * 0.5;
}

fn appendArchitectureRoof(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(geometry.Vertex),
    indices: *std.ArrayList(u32),
    footprint: []const editor_math.Vec3,
    height: f32,
    roof: arch.Roof,
) !void {
    const overhang = @max(0.0, roof.overhang);
    const roof_base_y = height + 0.08;
    if (roof.kind == .conical) {
        try appendConicalRoof(allocator, vertices, indices, footprint, height, roof);
        return;
    }
    if (roof.kind == .shed or roof.kind == .gable) {
        const bounds = footprintBounds(footprint) orelse return;
        const min_x = bounds.min.x - overhang;
        const max_x = bounds.max.x + overhang;
        const min_z = bounds.min.z - overhang;
        const max_z = bounds.max.z + overhang;
        const width = max_x - min_x;
        const depth = max_z - min_z;
        const rise = @max(0.2, @tan(roof.pitch) * @min(width, depth) * 0.5);
        if (roof.kind == .gable) {
            try appendGableRoofAtBounds(allocator, vertices, indices, min_x, max_x, min_z, max_z, roof_base_y, rise);
        } else {
            try appendShedRoofAtBounds(allocator, vertices, indices, min_x, max_x, min_z, max_z, roof_base_y, rise);
        }
        return;
    }
    const expanded = try expandedFootprint(allocator, footprint, overhang, roof_base_y + roof_body_thickness);
    defer allocator.free(expanded);
    try appendArchitectureFloor(allocator, vertices, indices, expanded, roof_base_y + roof_body_thickness, roof_body_thickness);
}

fn appendConicalRoof(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(geometry.Vertex),
    indices: *std.ArrayList(u32),
    footprint: []const editor_math.Vec3,
    height: f32,
    roof: arch.Roof,
) !void {
    if (footprint.len < 3) return;
    const center: editor_math.Vec3 = .{ .x = footprintCenterX(footprint), .y = height + 0.08, .z = footprintCenterZ(footprint) };
    var avg_radius: f32 = 0;
    for (footprint) |point| {
        const dx = point.x - center.x;
        const dz = point.z - center.z;
        avg_radius += @sqrt(dx * dx + dz * dz);
    }
    avg_radius /= @as(f32, @floatFromInt(footprint.len));
    const apex: editor_math.Vec3 = .{ .x = center.x, .y = center.y + @max(1.0, @tan(roof.pitch) * avg_radius), .z = center.z };
    var expanded = try allocator.alloc(editor_math.Vec3, footprint.len);
    defer allocator.free(expanded);
    for (footprint, 0..) |point, idx| {
        const dx = point.x - center.x;
        const dz = point.z - center.z;
        const len = @max(0.001, @sqrt(dx * dx + dz * dz));
        expanded[idx] = .{
            .x = point.x + (dx / len) * roof.overhang,
            .y = center.y,
            .z = point.z + (dz / len) * roof.overhang,
        };
    }
    for (expanded, 0..) |point, idx| {
        const next = expanded[(idx + 1) % expanded.len];
        const normal = roofTriangleNormal(point, apex, next);
        try appendOrientedRampTri(allocator, vertices, indices, point, next, apex, normal);
        const bottom = withY(point, center.y - roof_body_thickness);
        const next_bottom = withY(next, center.y - roof_body_thickness);
        const fascia_normal = editor_math.Vec3.normalized(.{ .x = normal.x, .y = 0, .z = normal.z });
        try appendOrientedRampQuad(allocator, vertices, indices, next_bottom, bottom, point, next, fascia_normal);
    }
    try appendBottomCap(allocator, vertices, indices, expanded, center.y - roof_body_thickness);
}

fn roofTriangleNormal(p0: editor_math.Vec3, p1: editor_math.Vec3, p2: editor_math.Vec3) editor_math.Vec3 {
    const ab = editor_math.Vec3.sub(p1, p0);
    const ac = editor_math.Vec3.sub(p2, p0);
    return editor_math.Vec3.normalized(editor_math.cross(ab, ac));
}

fn appendShedRoofAtBounds(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(geometry.Vertex),
    indices: *std.ArrayList(u32),
    min_x: f32,
    max_x: f32,
    min_z: f32,
    max_z: f32,
    y: f32,
    rise: f32,
) !void {
    const bottom_y = y - roof_body_thickness;
    const low_front: editor_math.Vec3 = .{ .x = min_x, .y = y, .z = min_z };
    const high_front: editor_math.Vec3 = .{ .x = max_x, .y = y + rise, .z = min_z };
    const high_back: editor_math.Vec3 = .{ .x = max_x, .y = y + rise, .z = max_z };
    const low_back: editor_math.Vec3 = .{ .x = min_x, .y = y, .z = max_z };
    const low_front_bottom: editor_math.Vec3 = .{ .x = min_x, .y = bottom_y, .z = min_z };
    const high_front_bottom: editor_math.Vec3 = .{ .x = max_x, .y = bottom_y, .z = min_z };
    const high_back_bottom: editor_math.Vec3 = .{ .x = max_x, .y = bottom_y, .z = max_z };
    const low_back_bottom: editor_math.Vec3 = .{ .x = min_x, .y = bottom_y, .z = max_z };
    try appendOrientedRampQuad(
        allocator,
        vertices,
        indices,
        low_front,
        high_front,
        high_back,
        low_back,
        .{ .x = -rise, .y = max_x - min_x, .z = 0 },
    );
    try appendOrientedRampQuad(allocator, vertices, indices, low_back_bottom, high_back_bottom, high_front_bottom, low_front_bottom, .{ .x = 0, .y = -1, .z = 0 });
    try appendOrientedRampQuad(allocator, vertices, indices, low_back_bottom, low_front_bottom, low_front, low_back, .{ .x = -1, .y = 0, .z = 0 });
    try appendOrientedRampQuad(allocator, vertices, indices, high_front_bottom, high_back_bottom, high_back, high_front, .{ .x = 1, .y = 0, .z = 0 });
    try appendOrientedRampQuad(allocator, vertices, indices, low_front_bottom, high_front_bottom, high_front, low_front, .{ .x = 0, .y = 0, .z = -1 });
    try appendOrientedRampQuad(allocator, vertices, indices, high_back_bottom, low_back_bottom, low_back, high_back, .{ .x = 0, .y = 0, .z = 1 });
}

fn appendGableRoofAtBounds(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(geometry.Vertex),
    indices: *std.ArrayList(u32),
    min_x: f32,
    max_x: f32,
    min_z: f32,
    max_z: f32,
    y: f32,
    rise: f32,
) !void {
    const ridge_x = (min_x + max_x) * 0.5;
    const bottom_y = y - roof_body_thickness;
    const left_front: editor_math.Vec3 = .{ .x = min_x, .y = y, .z = min_z };
    const right_front: editor_math.Vec3 = .{ .x = max_x, .y = y, .z = min_z };
    const left_back: editor_math.Vec3 = .{ .x = min_x, .y = y, .z = max_z };
    const right_back: editor_math.Vec3 = .{ .x = max_x, .y = y, .z = max_z };
    const ridge_front: editor_math.Vec3 = .{ .x = ridge_x, .y = y + rise, .z = min_z };
    const ridge_back: editor_math.Vec3 = .{ .x = ridge_x, .y = y + rise, .z = max_z };
    const left_front_bottom: editor_math.Vec3 = .{ .x = min_x, .y = bottom_y, .z = min_z };
    const right_front_bottom: editor_math.Vec3 = .{ .x = max_x, .y = bottom_y, .z = min_z };
    const left_back_bottom: editor_math.Vec3 = .{ .x = min_x, .y = bottom_y, .z = max_z };
    const right_back_bottom: editor_math.Vec3 = .{ .x = max_x, .y = bottom_y, .z = max_z };

    try appendOrientedRampQuad(allocator, vertices, indices, left_front, ridge_front, ridge_back, left_back, roofPlaneNormal(-1, rise, ridge_x - min_x));
    try appendOrientedRampQuad(allocator, vertices, indices, ridge_front, right_front, right_back, ridge_back, roofPlaneNormal(1, rise, max_x - ridge_x));
    try appendOrientedRampQuad(allocator, vertices, indices, left_back_bottom, right_back_bottom, right_front_bottom, left_front_bottom, .{ .x = 0, .y = -1, .z = 0 });
    try appendOrientedRampQuad(allocator, vertices, indices, left_back_bottom, left_front_bottom, left_front, left_back, .{ .x = -1, .y = 0, .z = 0 });
    try appendOrientedRampQuad(allocator, vertices, indices, right_front_bottom, right_back_bottom, right_back, right_front, .{ .x = 1, .y = 0, .z = 0 });
    try appendGableEnd(allocator, vertices, indices, .{ left_front_bottom, left_front, ridge_front, right_front, right_front_bottom }, .{ .x = 0, .y = 0, .z = -1 });
    try appendGableEnd(allocator, vertices, indices, .{ right_back_bottom, right_back, ridge_back, left_back, left_back_bottom }, .{ .x = 0, .y = 0, .z = 1 });
}

fn expandedFootprint(
    allocator: std.mem.Allocator,
    footprint: []const editor_math.Vec3,
    overhang: f32,
    y: f32,
) ![]editor_math.Vec3 {
    const center: editor_math.Vec3 = .{ .x = footprintCenterX(footprint), .y = y, .z = footprintCenterZ(footprint) };
    const expanded = try allocator.alloc(editor_math.Vec3, footprint.len);
    for (footprint, 0..) |point, idx| {
        const dx = point.x - center.x;
        const dz = point.z - center.z;
        const len = @sqrt(dx * dx + dz * dz);
        if (len <= floorplan_eps) {
            expanded[idx] = .{ .x = point.x, .y = y, .z = point.z };
        } else {
            expanded[idx] = .{
                .x = point.x + dx / len * overhang,
                .y = y,
                .z = point.z + dz / len * overhang,
            };
        }
    }
    return expanded;
}

fn appendBottomCap(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(geometry.Vertex),
    indices: *std.ArrayList(u32),
    footprint: []const editor_math.Vec3,
    y: f32,
) !void {
    const triangles = try triangulateFootprint(allocator, footprint);
    defer allocator.free(triangles);
    const ccw = footprintSignedArea(footprint) >= 0;
    const base: u32 = @intCast(vertices.items.len);
    for (footprint) |point| {
        try appendRampVertex(allocator, vertices, withY(point, y), .{ .x = 0, .y = -1, .z = 0 }, .{ .x = point.x, .y = point.z });
    }
    for (triangles) |tri| {
        try appendFloorTriangle(indices, allocator, base, tri, ccw, false);
    }
}

fn appendGableEnd(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(geometry.Vertex),
    indices: *std.ArrayList(u32),
    points: [5]editor_math.Vec3,
    normal: editor_math.Vec3,
) !void {
    try appendOrientedRampTri(allocator, vertices, indices, points[0], points[1], points[2], normal);
    try appendOrientedRampTri(allocator, vertices, indices, points[0], points[2], points[3], normal);
    try appendOrientedRampTri(allocator, vertices, indices, points[0], points[3], points[4], normal);
}

fn footprintBounds(points: []const editor_math.Vec3) ?FloorplanBounds {
    if (points.len == 0) return null;
    var min = points[0];
    var max = points[0];
    for (points[1..]) |point| {
        min.x = @min(min.x, point.x);
        min.z = @min(min.z, point.z);
        max.x = @max(max.x, point.x);
        max.z = @max(max.z, point.z);
    }
    min.y = 0;
    max.y = 0;
    return .{ .min = min, .max = max };
}

fn appendColumnFeature(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(geometry.Vertex),
    indices: *std.ArrayList(u32),
    feature: arch.Feature,
) !void {
    const half = @max(0.05, feature.width) * 0.5;
    const h = @max(0.1, feature.height);
    const min: editor_math.Vec3 = .{ .x = feature.x - half, .y = 0, .z = feature.z - half };
    const max: editor_math.Vec3 = .{ .x = feature.x + half, .y = h, .z = feature.z + half };
    try appendBoxMesh(allocator, vertices, indices, min, max);
}

fn appendBeamFeature(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(geometry.Vertex),
    indices: *std.ArrayList(u32),
    feature: arch.Feature,
) !void {
    const dir = normalizedPlanDir(feature.dir_x, feature.dir_z);
    const normal: editor_math.Vec3 = .{ .x = -dir.z, .y = 0, .z = dir.x };
    const half_len = @max(0.1, feature.width) * 0.5;
    const half_depth = @max(0.05, feature.depth) * 0.5;
    const bottom = @max(0.0, feature.height - @max(0.05, feature.depth));
    const top = @max(bottom + 0.05, feature.height);
    const center: editor_math.Vec3 = .{ .x = feature.x, .y = 0, .z = feature.z };
    const min_a = editor_math.Vec3.add(center, editor_math.Vec3.scale(dir, -half_len));
    const max_a = editor_math.Vec3.add(center, editor_math.Vec3.scale(dir, half_len));
    const p0 = editor_math.Vec3.add(min_a, editor_math.Vec3.scale(normal, -half_depth));
    const p1 = editor_math.Vec3.add(max_a, editor_math.Vec3.scale(normal, -half_depth));
    const p2 = editor_math.Vec3.add(max_a, editor_math.Vec3.scale(normal, half_depth));
    const p3 = editor_math.Vec3.add(min_a, editor_math.Vec3.scale(normal, half_depth));
    try appendPrismFromPlanQuad(allocator, vertices, indices, p0, p1, p2, p3, bottom, top);
}

fn appendStraightStairFeature(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(geometry.Vertex),
    indices: *std.ArrayList(u32),
    feature: arch.Feature,
) !void {
    const steps = @max(1, feature.steps);
    const dir = normalizedPlanDir(feature.dir_x, feature.dir_z);
    const normal: editor_math.Vec3 = .{ .x = -dir.z, .y = 0, .z = dir.x };
    const width = @max(0.25, feature.width);
    const run = @max(0.25, feature.depth);
    const rise = @max(0.1, feature.height);
    const step_run = run / @as(f32, @floatFromInt(steps));
    const step_rise = rise / @as(f32, @floatFromInt(steps));
    const origin: editor_math.Vec3 = .{ .x = feature.x, .y = 0, .z = feature.z };
    var i: u32 = 0;
    while (i < steps) : (i += 1) {
        const start = @as(f32, @floatFromInt(i)) * step_run;
        const end = start + step_run;
        const top = @as(f32, @floatFromInt(i + 1)) * step_rise;
        const center_a = editor_math.Vec3.add(origin, editor_math.Vec3.scale(dir, start));
        const center_b = editor_math.Vec3.add(origin, editor_math.Vec3.scale(dir, end));
        const p0 = editor_math.Vec3.add(center_a, editor_math.Vec3.scale(normal, -width * 0.5));
        const p1 = editor_math.Vec3.add(center_b, editor_math.Vec3.scale(normal, -width * 0.5));
        const p2 = editor_math.Vec3.add(center_b, editor_math.Vec3.scale(normal, width * 0.5));
        const p3 = editor_math.Vec3.add(center_a, editor_math.Vec3.scale(normal, width * 0.5));
        try appendPrismFromPlanQuad(allocator, vertices, indices, p0, p1, p2, p3, 0, top);
    }
}

fn appendSpiralStairFeature(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(geometry.Vertex),
    indices: *std.ArrayList(u32),
    feature: arch.Feature,
) !void {
    const steps = @max(6, feature.steps);
    const radius = @max(0.5, feature.width);
    const tread_width = @max(0.25, feature.depth);
    const total_rise = @max(0.5, feature.height);
    const sweep = std.math.tau * 2.35;
    const start_angle = std.math.atan2(feature.dir_z, feature.dir_x);
    const center: editor_math.Vec3 = .{ .x = feature.x, .y = 0, .z = feature.z };
    var i: u32 = 0;
    while (i < steps) : (i += 1) {
        const a0 = start_angle + sweep * (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps)));
        const a1 = start_angle + sweep * (@as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(steps)));
        const y0 = total_rise * (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps)));
        const y1 = total_rise * (@as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(steps)));
        const inner = @max(0.1, radius - tread_width * 0.5);
        const outer = radius + tread_width * 0.5;
        const p0: editor_math.Vec3 = .{ .x = center.x + @cos(a0) * inner, .y = y0, .z = center.z + @sin(a0) * inner };
        const p1: editor_math.Vec3 = .{ .x = center.x + @cos(a1) * inner, .y = y1, .z = center.z + @sin(a1) * inner };
        const p2: editor_math.Vec3 = .{ .x = center.x + @cos(a1) * outer, .y = y1, .z = center.z + @sin(a1) * outer };
        const p3: editor_math.Vec3 = .{ .x = center.x + @cos(a0) * outer, .y = y0, .z = center.z + @sin(a0) * outer };
        try appendPrismFromSlopedQuad(allocator, vertices, indices, p0, p1, p2, p3, 0.08);
    }
    try appendCylinderShell(allocator, vertices, indices, center.x, center.z, 0, total_rise, 0.12, 12);
}

fn appendBartizanFeature(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(geometry.Vertex),
    indices: *std.ArrayList(u32),
    feature: arch.Feature,
) !void {
    const segments = @max(@as(u32, 8), feature.steps);
    const radius = @max(0.35, feature.width);
    const bottom = @max(0.0, feature.height);
    const top = bottom + @max(0.5, feature.depth);
    try appendCylinderShell(allocator, vertices, indices, feature.x, feature.z, bottom, top, radius, segments);
    var footprint = try allocator.alloc(editor_math.Vec3, segments);
    defer allocator.free(footprint);
    var i: u32 = 0;
    while (i < segments) : (i += 1) {
        const angle = (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(segments))) * std.math.tau;
        footprint[i] = .{ .x = feature.x + @cos(angle) * radius, .y = top, .z = feature.z + @sin(angle) * radius };
    }
    try appendConicalRoof(allocator, vertices, indices, footprint, top, .{ .kind = .conical, .pitch = 0.85, .overhang = 0.12 });
}

fn appendCylinderShell(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(geometry.Vertex),
    indices: *std.ArrayList(u32),
    x: f32,
    z: f32,
    bottom: f32,
    top: f32,
    radius: f32,
    segments: u32,
) !void {
    const segs = @max(@as(u32, 6), segments);
    var i: u32 = 0;
    while (i < segs) : (i += 1) {
        const a0 = (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(segs))) * std.math.tau;
        const a1 = (@as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(segs))) * std.math.tau;
        const p0: editor_math.Vec3 = .{ .x = x + @cos(a0) * radius, .y = bottom, .z = z + @sin(a0) * radius };
        const p1: editor_math.Vec3 = .{ .x = x + @cos(a1) * radius, .y = bottom, .z = z + @sin(a1) * radius };
        const p2: editor_math.Vec3 = .{ .x = x + @cos(a1) * radius, .y = top, .z = z + @sin(a1) * radius };
        const p3: editor_math.Vec3 = .{ .x = x + @cos(a0) * radius, .y = top, .z = z + @sin(a0) * radius };
        const normal: editor_math.Vec3 = .{ .x = @cos((a0 + a1) * 0.5), .y = 0, .z = @sin((a0 + a1) * 0.5) };
        try appendRampQuad(allocator, vertices, indices, p0, p1, p2, p3, normal);
    }
}

fn appendPrismFromSlopedQuad(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(geometry.Vertex),
    indices: *std.ArrayList(u32),
    p0: editor_math.Vec3,
    p1: editor_math.Vec3,
    p2: editor_math.Vec3,
    p3: editor_math.Vec3,
    thickness: f32,
) !void {
    const down: editor_math.Vec3 = .{ .x = 0, .y = -@max(0.02, thickness), .z = 0 };
    const b0 = editor_math.Vec3.add(p0, down);
    const b1 = editor_math.Vec3.add(p1, down);
    const b2 = editor_math.Vec3.add(p2, down);
    const b3 = editor_math.Vec3.add(p3, down);
    try appendRampQuad(allocator, vertices, indices, p0, p1, p2, p3, .{ .x = 0, .y = 1, .z = 0 });
    try appendRampQuad(allocator, vertices, indices, b3, b2, b1, b0, .{ .x = 0, .y = -1, .z = 0 });
    try appendRampQuad(allocator, vertices, indices, b0, b1, p1, p0, .{ .x = 0, .y = 0, .z = -1 });
    try appendRampQuad(allocator, vertices, indices, b1, b2, p2, p1, .{ .x = 1, .y = 0, .z = 0 });
    try appendRampQuad(allocator, vertices, indices, b2, b3, p3, p2, .{ .x = 0, .y = 0, .z = 1 });
    try appendRampQuad(allocator, vertices, indices, b3, b0, p0, p3, .{ .x = -1, .y = 0, .z = 0 });
}

fn appendArchFeature(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(geometry.Vertex),
    indices: *std.ArrayList(u32),
    feature: arch.Feature,
) !void {
    const dir = normalizedPlanDir(feature.dir_x, feature.dir_z);
    const normal: editor_math.Vec3 = .{ .x = -dir.z, .y = 0, .z = dir.x };
    const width = @max(0.5, feature.width);
    const depth = @max(0.08, feature.depth);
    const spring = @max(0.2, feature.height);
    const arch_height = @max(0.2, depth * 2.0);
    const center: editor_math.Vec3 = .{ .x = feature.x, .y = 0, .z = feature.z };
    const left = editor_math.Vec3.add(center, editor_math.Vec3.scale(dir, -width * 0.5));
    const right = editor_math.Vec3.add(center, editor_math.Vec3.scale(dir, width * 0.5));
    const p0 = editor_math.Vec3.add(left, editor_math.Vec3.scale(normal, -depth * 0.5));
    const p1 = editor_math.Vec3.add(left, editor_math.Vec3.scale(normal, depth * 0.5));
    const p2 = editor_math.Vec3.add(right, editor_math.Vec3.scale(normal, -depth * 0.5));
    const p3 = editor_math.Vec3.add(right, editor_math.Vec3.scale(normal, depth * 0.5));
    try appendPrismFromPlanQuad(allocator, vertices, indices, p0, p1, editor_math.Vec3.add(p1, editor_math.Vec3.scale(dir, depth)), editor_math.Vec3.add(p0, editor_math.Vec3.scale(dir, depth)), 0, spring);
    try appendPrismFromPlanQuad(allocator, vertices, indices, p2, p3, editor_math.Vec3.add(p3, editor_math.Vec3.scale(dir, -depth)), editor_math.Vec3.add(p2, editor_math.Vec3.scale(dir, -depth)), 0, spring);
    const top0 = editor_math.Vec3.add(center, editor_math.Vec3.scale(normal, -depth * 0.5));
    const top1 = editor_math.Vec3.add(center, editor_math.Vec3.scale(normal, depth * 0.5));
    const top2 = editor_math.Vec3.add(top1, editor_math.Vec3.scale(dir, width * 0.5));
    const top3 = editor_math.Vec3.add(top0, editor_math.Vec3.scale(dir, width * 0.5));
    try appendPrismFromPlanQuad(allocator, vertices, indices, top0, top1, top2, top3, spring, spring + arch_height);
}

fn appendPrismFromPlanQuad(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(geometry.Vertex),
    indices: *std.ArrayList(u32),
    p0: editor_math.Vec3,
    p1: editor_math.Vec3,
    p2: editor_math.Vec3,
    p3: editor_math.Vec3,
    bottom: f32,
    top: f32,
) !void {
    const b0: editor_math.Vec3 = .{ .x = p0.x, .y = bottom, .z = p0.z };
    const b1: editor_math.Vec3 = .{ .x = p1.x, .y = bottom, .z = p1.z };
    const b2: editor_math.Vec3 = .{ .x = p2.x, .y = bottom, .z = p2.z };
    const b3: editor_math.Vec3 = .{ .x = p3.x, .y = bottom, .z = p3.z };
    const t0: editor_math.Vec3 = .{ .x = p0.x, .y = top, .z = p0.z };
    const t1: editor_math.Vec3 = .{ .x = p1.x, .y = top, .z = p1.z };
    const t2: editor_math.Vec3 = .{ .x = p2.x, .y = top, .z = p2.z };
    const t3: editor_math.Vec3 = .{ .x = p3.x, .y = top, .z = p3.z };
    try appendRampQuad(allocator, vertices, indices, b0, b1, t1, t0, .{ .x = 0, .y = 0, .z = -1 });
    try appendRampQuad(allocator, vertices, indices, b1, b2, t2, t1, .{ .x = 1, .y = 0, .z = 0 });
    try appendRampQuad(allocator, vertices, indices, b2, b3, t3, t2, .{ .x = 0, .y = 0, .z = 1 });
    try appendRampQuad(allocator, vertices, indices, b3, b0, t0, t3, .{ .x = -1, .y = 0, .z = 0 });
    try appendRampQuad(allocator, vertices, indices, t0, t1, t2, t3, .{ .x = 0, .y = 1, .z = 0 });
}

fn normalizedPlanDir(x: f32, z: f32) editor_math.Vec3 {
    const len = @sqrt(x * x + z * z);
    if (len <= floorplan_eps) return .{ .x = 1, .y = 0, .z = 0 };
    return .{ .x = x / len, .y = 0, .z = z / len };
}

fn appendBoxMesh(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(geometry.Vertex),
    indices: *std.ArrayList(u32),
    min: editor_math.Vec3,
    max: editor_math.Vec3,
) !void {
    try appendRampQuad(allocator, vertices, indices, .{ .x = min.x, .y = min.y, .z = max.z }, .{ .x = max.x, .y = min.y, .z = max.z }, .{ .x = max.x, .y = max.y, .z = max.z }, .{ .x = min.x, .y = max.y, .z = max.z }, .{ .x = 0, .y = 0, .z = 1 });
    try appendRampQuad(allocator, vertices, indices, .{ .x = max.x, .y = min.y, .z = min.z }, .{ .x = min.x, .y = min.y, .z = min.z }, .{ .x = min.x, .y = max.y, .z = min.z }, .{ .x = max.x, .y = max.y, .z = min.z }, .{ .x = 0, .y = 0, .z = -1 });
    try appendRampQuad(allocator, vertices, indices, .{ .x = max.x, .y = min.y, .z = max.z }, .{ .x = max.x, .y = min.y, .z = min.z }, .{ .x = max.x, .y = max.y, .z = min.z }, .{ .x = max.x, .y = max.y, .z = max.z }, .{ .x = 1, .y = 0, .z = 0 });
    try appendRampQuad(allocator, vertices, indices, .{ .x = min.x, .y = min.y, .z = min.z }, .{ .x = min.x, .y = min.y, .z = max.z }, .{ .x = min.x, .y = max.y, .z = max.z }, .{ .x = min.x, .y = max.y, .z = min.z }, .{ .x = -1, .y = 0, .z = 0 });
    try appendRampQuad(allocator, vertices, indices, .{ .x = min.x, .y = max.y, .z = max.z }, .{ .x = max.x, .y = max.y, .z = max.z }, .{ .x = max.x, .y = max.y, .z = min.z }, .{ .x = min.x, .y = max.y, .z = min.z }, .{ .x = 0, .y = 1, .z = 0 });
}

fn appendFoundation(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(geometry.Vertex),
    indices: *std.ArrayList(u32),
    foundation: arch.Foundation,
) !void {
    const bottom_y = foundation.top_y - @max(0.05, foundation.clearance + 0.25);
    try appendBoxMesh(
        allocator,
        vertices,
        indices,
        .{ .x = foundation.min_x, .y = bottom_y, .z = foundation.min_z },
        .{ .x = foundation.max_x, .y = foundation.top_y, .z = foundation.max_z },
    );
}

fn footprintCenterX(points: []const editor_math.Vec3) f32 {
    var sum: f32 = 0;
    for (points) |point| sum += point.x;
    return sum / @as(f32, @floatFromInt(points.len));
}

fn footprintCenterZ(points: []const editor_math.Vec3) f32 {
    var sum: f32 = 0;
    for (points) |point| sum += point.z;
    return sum / @as(f32, @floatFromInt(points.len));
}

fn rebuildArchitectureBuildingObject(state: *ProjectEditorState, obj: *SceneObject) !void {
    var building = try arch.Building.parse(state.allocator, obj.components);
    defer building.deinit(state.allocator);
    try rebuildMeshFromBuilding(state, obj, &building);
}

fn rebuildMeshFromBuilding(state: *ProjectEditorState, obj: *SceneObject, building: *const arch.Building) !void {
    var mesh = if (building.walls.items.len == 0 and building.foundations.items.len == 0)
        geometry.Mesh{
            .vertices = try state.allocator.alloc(geometry.Vertex, 0),
            .indices = try state.allocator.alloc(u32, 0),
        }
    else
        try buildArchitectureBuildingMesh(state.allocator, building);
    errdefer mesh.deinit(state.allocator);
    obj.mesh.deinit(state.allocator);
    obj.mesh = mesh;
    obj.primitive_kind = null;
    obj.physics = static_body;
    state.scene_dirty = true;
}

/// The single write path for every building edit: serialize the mutated model
/// into `obj.components` and regenerate the render mesh from it. Semantic data
/// stays the source of truth; the mesh is always a fresh disposable output.
pub fn writeBackBuilding(state: *ProjectEditorState, obj: *SceneObject, building: *const arch.Building) !void {
    const serialized_components = try building.serialize(state.allocator);
    errdefer {
        for (serialized_components) |component| state.allocator.free(component);
        state.allocator.free(serialized_components);
    }
    try rebuildMeshFromBuilding(state, obj, building);
    const components = try mergePreservedBuildingMetadata(state.allocator, serialized_components, obj.components);
    for (obj.components) |component| state.allocator.free(component);
    state.allocator.free(obj.components);
    obj.components = components;
}

fn mergePreservedBuildingMetadata(allocator: std.mem.Allocator, serialized_components: [][]u8, previous_components: []const []const u8) ![][]u8 {
    var preserved_count: usize = 0;
    for (previous_components) |component| {
        if (!arch.isSerializedBuildingComponent(component)) preserved_count += 1;
    }
    const merged = try allocator.alloc([]u8, serialized_components.len + preserved_count);
    var copied_preserved: usize = 0;
    errdefer {
        for (merged[serialized_components.len..][0..copied_preserved]) |component| allocator.free(component);
        allocator.free(merged);
    }
    for (serialized_components, 0..) |component, idx| merged[idx] = component;
    for (previous_components) |component| {
        if (arch.isSerializedBuildingComponent(component)) continue;
        merged[serialized_components.len + copied_preserved] = try allocator.dupe(u8, component);
        copied_preserved += 1;
    }
    allocator.free(serialized_components);
    return merged;
}

/// Resolve the building an edit targets. Every architecture edit goes through
/// the active building (see `project_editor_architecture.zig`) so all parts of
/// one building stay together; reports why it cannot instead of guessing.
fn selectedBuilding(state: *ProjectEditorState) ?*SceneObject {
    return architecture.editTargetBuilding(state);
}

pub fn applyArchitectureWallDefaultsToSelected(state: *ProjectEditorState) !void {
    const obj = selectedBuilding(state) orelse return;
    var building = try arch.Building.parse(state.allocator, obj.components);
    defer building.deinit(state.allocator);
    project_editor_edit.pushUndoSnapshot(state);
    for (building.walls.items) |*wall| {
        wall.height = @max(0.25, state.architecture_wall_height);
        wall.thickness = @max(0.05, state.architecture_wall_thickness);
    }
    try writeBackBuilding(state, obj, &building);
    project_editor_state.setStatus(state, "Building wall defaults applied");
}

pub fn moveArchitectureVertexByMeshVertex(
    state: *ProjectEditorState,
    obj_index: usize,
    mesh_vertex_index: u32,
    offset: editor_math.Vec3,
) !bool {
    if (obj_index >= state.objects.items.len) return false;
    const obj = &state.objects.items[obj_index];
    if (!isArchitectureBuildingObject(obj)) return false;
    if (mesh_vertex_index >= obj.mesh.vertices.len) return false;
    var building = try arch.Building.parse(state.allocator, obj.components);
    defer building.deinit(state.allocator);
    const picked = obj.mesh.vertices[mesh_vertex_index].position;
    var best_id: ?u32 = null;
    var best_distance = std.math.floatMax(f32);
    for (building.vertices.items) |vertex| {
        const dx = vertex.x - picked.x;
        const dz = vertex.z - picked.z;
        const dist = dx * dx + dz * dz;
        if (dist < best_distance) {
            best_distance = dist;
            best_id = vertex.id;
        }
    }
    const vertex_id = best_id orelse return false;
    if (best_distance > 0.75 * 0.75) return false;

    const vertex = building.vertexPtr(vertex_id) orelse return false;
    vertex.x += offset.x;
    vertex.z += offset.z;
    try writeBackBuilding(state, obj, &building);
    state.drag_moved = true;
    project_editor_state.setStatus(state, "Architecture vertex moved");
    return true;
}

pub fn deleteLastArchitectureWallSelected(state: *ProjectEditorState) !void {
    const obj = selectedBuilding(state) orelse return;
    var building = try arch.Building.parse(state.allocator, obj.components);
    defer building.deinit(state.allocator);
    if (building.walls.items.len == 0) return;
    const remove_id = building.walls.items[building.walls.items.len - 1].id;
    project_editor_edit.pushUndoSnapshot(state);
    _ = building.walls.pop();
    // Drop openings that belonged to the removed wall.
    var i: usize = building.openings.items.len;
    while (i > 0) {
        i -= 1;
        if (building.openings.items[i].wall_id == remove_id) _ = building.openings.orderedRemove(i);
    }
    try writeBackBuilding(state, obj, &building);
    project_editor_state.setStatus(state, "Last architecture wall deleted");
}

pub fn splitLongestArchitectureWallSelected(state: *ProjectEditorState) !void {
    const obj = selectedBuilding(state) orelse return;
    var building = try arch.Building.parse(state.allocator, obj.components);
    defer building.deinit(state.allocator);
    const picked = longestWall(&building) orelse return;
    const wall = building.walls.items[picked];
    const a = building.findVertex(wall.a) orelse return error.InvalidArchitectureWall;
    const b = building.findVertex(wall.b) orelse return error.InvalidArchitectureWall;
    const mid_id = building.nextVertexId();
    const mid_x = (a.x + b.x) * 0.5;
    const mid_z = (a.z + b.z) * 0.5;

    project_editor_edit.pushUndoSnapshot(state);
    try building.vertices.append(state.allocator, .{ .id = mid_id, .x = mid_x, .z = mid_z });
    const first_id = building.nextWallId();
    // Reuse the picked slot for the first half and append the second half so the
    // closed-footprint traversal order is preserved.
    building.walls.items[picked] = .{ .id = first_id, .a = wall.a, .b = mid_id, .height = wall.height, .thickness = wall.thickness };
    try building.walls.insert(state.allocator, picked + 1, .{ .id = first_id + 1, .a = mid_id, .b = wall.b, .height = wall.height, .thickness = wall.thickness });
    try writeBackBuilding(state, obj, &building);
    project_editor_state.setStatus(state, "Longest architecture wall split");
}

pub fn addArchitectureFeatureToSelected(state: *ProjectEditorState, kind: ArchFeatureKind) !void {
    const obj = selectedBuilding(state) orelse return;
    var building = try arch.Building.parse(state.allocator, obj.components);
    defer building.deinit(state.allocator);
    const c = building.center();
    const id = building.nextFeatureId();
    const feature: arch.Feature = switch (kind) {
        .column => .{ .id = id, .kind = .column, .x = c.x, .z = c.z, .height = @max(0.25, state.architecture_wall_height), .width = @max(0.2, state.architecture_wall_thickness * 2.0) },
        .beam => .{ .id = id, .kind = .beam, .x = c.x, .z = c.z, .height = @max(0.25, state.architecture_wall_height), .width = 3.0, .depth = @max(0.15, state.architecture_wall_thickness), .dir_x = 1, .dir_z = 0 },
        .stair => .{ .id = id, .kind = .stair, .x = c.x, .z = c.z, .height = @max(1.0, state.architecture_wall_height), .width = 1.2, .depth = 3.0, .dir_x = 1, .dir_z = 0, .steps = 8 },
        .spiral_stair => .{ .id = id, .kind = .spiral_stair, .x = c.x, .z = c.z, .height = @max(3.0, state.architecture_wall_height), .width = 1.5, .depth = 0.65, .dir_x = 1, .dir_z = 0, .steps = 24 },
        .bartizan => .{ .id = id, .kind = .bartizan, .x = c.x + 3.0, .z = c.z, .height = @max(2.5, state.architecture_wall_height * 0.5), .width = 0.85, .depth = 2.2, .dir_x = 1, .dir_z = 0, .steps = 12 },
        .arch => .{ .id = id, .kind = .arch, .x = c.x, .z = c.z, .height = 2.0, .width = 2.0, .depth = @max(0.2, state.architecture_wall_thickness), .dir_x = 1, .dir_z = 0 },
    };
    project_editor_edit.pushUndoSnapshot(state);
    try building.features.append(state.allocator, feature);
    try writeBackBuilding(state, obj, &building);
    project_editor_state.setStatus(state, switch (kind) {
        .column => "Column added",
        .beam => "Beam added",
        .stair => "Straight stair added",
        .spiral_stair => "Spiral stair added",
        .bartizan => "Bartizan added",
        .arch => "Arch added",
    });
}

pub fn setArchitectureRoofSelected(state: *ProjectEditorState, kind: ArchRoofKind) !void {
    const obj = selectedBuilding(state) orelse return;
    var building = try arch.Building.parse(state.allocator, obj.components);
    defer building.deinit(state.allocator);
    project_editor_edit.pushUndoSnapshot(state);
    const existing = building.roof orelse arch.Roof{ .kind = kind };
    building.roof = .{ .kind = kind, .pitch = existing.pitch, .overhang = existing.overhang };
    try writeBackBuilding(state, obj, &building);
    project_editor_state.setStatus(state, switch (kind) {
        .flat => "Flat roof applied",
        .shed => "Shed roof applied",
        .gable => "Gable roof applied",
        .conical => "Conical roof applied",
    });
}

fn longestWall(building: *const arch.Building) ?usize {
    var best: ?usize = null;
    var best_len: f32 = 0;
    for (building.walls.items, 0..) |wall, idx| {
        const len = building.wallLength(wall) orelse continue;
        if (len > best_len) {
            best_len = len;
            best = idx;
        }
    }
    return best;
}

fn sortWallPlanOpenings(openings: []WallSpanOpening) void {
    std.mem.sort(WallSpanOpening, openings, {}, struct {
        fn lessThan(_: void, lhs: WallSpanOpening, rhs: WallSpanOpening) bool {
            return lhs.start < rhs.start;
        }
    }.lessThan);
}

fn appendWallPlanSegment(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(geometry.Vertex),
    indices: *std.ArrayList(u32),
    segment: JoinedWallSegment,
    openings: []const WallSpanOpening,
) !void {
    var cursor: f32 = 0;
    for (openings) |opening| {
        if (opening.start - cursor > floorplan_eps) {
            try appendWallPlanQuadSpan(
                allocator,
                vertices,
                indices,
                segment,
                cursor,
                opening.start,
                0,
                segment.height,
                wallSpanStartCap(segment, cursor),
                true,
            );
        }
        if (opening.bottom > floorplan_eps) {
            try appendWallPlanQuadSpan(allocator, vertices, indices, segment, opening.start, opening.end, 0, opening.bottom, true, true);
        }
        if (segment.height - opening.top > floorplan_eps) {
            try appendWallPlanQuadSpan(allocator, vertices, indices, segment, opening.start, opening.end, opening.top, segment.height, true, true);
        }
        cursor = @max(cursor, opening.end);
    }
    if (segment.length - cursor > floorplan_eps) {
        try appendWallPlanQuadSpan(
            allocator,
            vertices,
            indices,
            segment,
            cursor,
            segment.length,
            0,
            segment.height,
            wallSpanStartCap(segment, cursor),
            segment.end_join.cap,
        );
    }
}

fn appendWallPlanQuadSpan(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(geometry.Vertex),
    indices: *std.ArrayList(u32),
    segment: JoinedWallSegment,
    start: f32,
    end: f32,
    bottom: f32,
    top: f32,
    cap_start: bool,
    cap_end: bool,
) !void {
    if (end - start <= floorplan_eps or top - bottom <= floorplan_eps) return;
    const start_bottom = wallPlanEndpointPair(segment, start, bottom);
    const end_bottom = wallPlanEndpointPair(segment, end, bottom);
    const start_top = wallPlanEndpointPair(segment, start, top);
    const end_top = wallPlanEndpointPair(segment, end, top);
    const front0 = start_bottom.front;
    const front1 = end_bottom.front;
    const front2 = end_top.front;
    const front3 = start_top.front;
    const back0 = start_bottom.back;
    const back1 = end_bottom.back;
    const back2 = end_top.back;
    const back3 = start_top.back;
    const front_normal = segment.normal;
    const back_normal: editor_math.Vec3 = .{ .x = -segment.normal.x, .y = 0, .z = -segment.normal.z };
    const end_normal = segment.dir;
    const start_normal: editor_math.Vec3 = .{ .x = -segment.dir.x, .y = 0, .z = -segment.dir.z };
    try appendOrientedRampQuad(allocator, vertices, indices, front1, front0, front3, front2, front_normal);
    try appendOrientedRampQuad(allocator, vertices, indices, back0, back1, back2, back3, back_normal);
    try appendOrientedRampQuad(allocator, vertices, indices, front2, front3, back3, back2, .{ .x = 0, .y = 1, .z = 0 });
    try appendOrientedRampQuad(allocator, vertices, indices, front0, front1, back1, back0, .{ .x = 0, .y = -1, .z = 0 });
    if (cap_end) try appendOrientedRampQuad(allocator, vertices, indices, back1, front1, front2, back2, end_normal);
    if (cap_start) try appendOrientedRampQuad(allocator, vertices, indices, front0, back0, back3, front3, start_normal);
}

fn wallSpanStartCap(segment: JoinedWallSegment, cursor: f32) bool {
    if (cursor <= floorplan_eps) return segment.start_join.cap;
    return true;
}

fn wallPlanEndpointPair(segment: JoinedWallSegment, along: f32, y: f32) WallEndpointPair {
    if (along <= floorplan_eps) {
        return .{
            .front = withY(segment.start_join.front, y),
            .back = withY(segment.start_join.back, y),
        };
    }
    if (segment.length - along <= floorplan_eps) {
        return .{
            .front = withY(segment.end_join.front, y),
            .back = withY(segment.end_join.back, y),
        };
    }
    const half_t = wallHalfThickness(segment.thickness);
    return .{
        .front = wallPlanPointOffset(segment.origin, segment.dir, segment.normal, along, y, half_t),
        .back = wallPlanPointOffset(segment.origin, segment.dir, segment.normal, along, y, -half_t),
    };
}

fn withY(point: editor_math.Vec3, y: f32) editor_math.Vec3 {
    return .{ .x = point.x, .y = y, .z = point.z };
}

fn wallPlanPoint(origin: editor_math.Vec3, dir: editor_math.Vec3, along: f32, y: f32) editor_math.Vec3 {
    return .{
        .x = origin.x + dir.x * along,
        .y = y,
        .z = origin.z + dir.z * along,
    };
}

fn wallPlanPointOffset(origin: editor_math.Vec3, dir: editor_math.Vec3, normal: editor_math.Vec3, along: f32, y: f32, offset: f32) editor_math.Vec3 {
    const point = wallPlanPoint(origin, dir, along, y);
    return .{
        .x = point.x + normal.x * offset,
        .y = point.y,
        .z = point.z + normal.z * offset,
    };
}

fn addFloorplanBounds(state: *ProjectEditorState, min_pt: editor_math.Vec3, max_pt: editor_math.Vec3) !void {
    const floor_max: editor_math.Vec3 = .{
        .x = max_pt.x,
        .y = min_pt.y + @max(0.04, state.architecture_floor_thickness),
        .z = max_pt.z,
    };
    try addNamedBlockoutBox(
        state,
        min_pt,
        floor_max,
        "Floorplan",
        .{ .r = 120, .g = 135, .b = 150, .a = 255 },
        true,
    );
}

pub fn addFloorplanCell(state: *ProjectEditorState) !void {
    project_editor_edit.pushUndoSnapshot(state);
    const cell_size: f32 = 4.0;
    const min_x = if (floorplanFootprintBounds(state)) |bounds| bounds.max.x else 0.0;
    try addFloorplanBounds(
        state,
        .{ .x = min_x, .y = 0, .z = 0 },
        .{ .x = min_x + cell_size, .y = 0, .z = cell_size },
    );
    project_editor_state.setStatus(state, "Floorplan cell added");
}

fn isFloorplanObject(obj: *const SceneObject) bool {
    if (!std.mem.startsWith(u8, obj.name, "Floorplan")) return false;
    const intent = obj.blockout_intent orelse return false;
    return intent.kind == .box_add;
}

pub fn extrudeSelectedFloorplanToRoom(state: *ProjectEditorState) !void {
    const idx = state.selected_object orelse {
        project_editor_state.setStatus(state, "Select a floorplan first");
        return;
    };
    if (idx >= state.objects.items.len) return error.InvalidSelection;
    const floor = &state.objects.items[idx];
    if (!isFloorplanObject(floor)) {
        project_editor_state.setStatus(state, "Selected object is not a floorplan");
        return;
    }
    const intent = floor.blockout_intent.?;
    project_editor_edit.pushUndoSnapshot(state);

    const min = intent.min;
    const max = intent.max;
    const height = @max(0.25, state.architecture_wall_height);
    const half_t = @max(0.05, state.architecture_wall_thickness) * 0.5;

    if (!hasSharedFloorplanEdge(state, idx, .south)) {
        try addRoomWallSegment(state, .{ .x = min.x - half_t, .y = 0, .z = min.z - half_t }, .{ .x = max.x + half_t, .y = height, .z = min.z + half_t });
    }
    if (!hasSharedFloorplanEdge(state, idx, .north)) {
        try addRoomWallSegment(state, .{ .x = min.x - half_t, .y = 0, .z = max.z - half_t }, .{ .x = max.x + half_t, .y = height, .z = max.z + half_t });
    }
    if (!hasSharedFloorplanEdge(state, idx, .west)) {
        try addRoomWallSegment(state, .{ .x = min.x - half_t, .y = 0, .z = min.z - half_t }, .{ .x = min.x + half_t, .y = height, .z = max.z + half_t });
    }
    if (!hasSharedFloorplanEdge(state, idx, .east)) {
        try addRoomWallSegment(state, .{ .x = max.x - half_t, .y = 0, .z = min.z - half_t }, .{ .x = max.x + half_t, .y = height, .z = max.z + half_t });
    }
    project_editor_state.setStatus(state, "Room extruded from floorplan");
}

const FloorplanEdge = enum { south, north, west, east };

fn hasSharedFloorplanEdge(state: *const ProjectEditorState, floor_idx: usize, edge: FloorplanEdge) bool {
    const intent = state.objects.items[floor_idx].blockout_intent orelse return false;
    for (state.objects.items, 0..) |other, idx| {
        if (idx == floor_idx or !isFloorplanObject(&other)) continue;
        const other_intent = other.blockout_intent.?;
        switch (edge) {
            .south => if (sameSpan(intent.min.x, intent.max.x, other_intent.min.x, other_intent.max.x) and near(intent.min.z, other_intent.max.z)) return true,
            .north => if (sameSpan(intent.min.x, intent.max.x, other_intent.min.x, other_intent.max.x) and near(intent.max.z, other_intent.min.z)) return true,
            .west => if (sameSpan(intent.min.z, intent.max.z, other_intent.min.z, other_intent.max.z) and near(intent.min.x, other_intent.max.x)) return true,
            .east => if (sameSpan(intent.min.z, intent.max.z, other_intent.min.z, other_intent.max.z) and near(intent.max.x, other_intent.min.x)) return true,
        }
    }
    return false;
}

fn addRoomWallSegment(state: *ProjectEditorState, min: editor_math.Vec3, max: editor_math.Vec3) !void {
    try addNamedBlockoutBox(state, min, max, "Room Wall", room_wall_color, false);
}

fn near(a: f32, b: f32) bool {
    return @abs(a - b) <= floorplan_eps;
}

fn sameSpan(a0: f32, a1: f32, b0: f32, b1: f32) bool {
    return near(a0, b0) and near(a1, b1);
}

fn clearSceneObjects(state: *ProjectEditorState) void {
    for (state.objects.items) |*obj| obj.deinit(state.allocator);
    state.objects.clearRetainingCapacity();
}

const FloorplanBounds = struct {
    min: editor_math.Vec3,
    max: editor_math.Vec3,
};

fn floorplanFootprintBounds(state: *const ProjectEditorState) ?FloorplanBounds {
    var result: ?FloorplanBounds = null;
    for (state.objects.items) |obj| {
        if (!isFloorplanObject(&obj)) continue;
        const intent = obj.blockout_intent.?;
        if (result) |*bounds| {
            bounds.min.x = @min(bounds.min.x, intent.min.x);
            bounds.min.z = @min(bounds.min.z, intent.min.z);
            bounds.max.x = @max(bounds.max.x, intent.max.x);
            bounds.max.z = @max(bounds.max.z, intent.max.z);
        } else {
            result = .{
                .min = .{ .x = intent.min.x, .y = 0, .z = intent.min.z },
                .max = .{ .x = intent.max.x, .y = 0, .z = intent.max.z },
            };
        }
    }
    return result;
}

pub fn addRoofForFloorplans(state: *ProjectEditorState) !void {
    const bounds = floorplanFootprintBounds(state) orelse {
        project_editor_state.setStatus(state, "Draw a floorplan first");
        return;
    };
    project_editor_edit.pushUndoSnapshot(state);

    const min_x = bounds.min.x - roof_overhang;
    const max_x = bounds.max.x + roof_overhang;
    const min_z = bounds.min.z - roof_overhang;
    const max_z = bounds.max.z + roof_overhang;
    const width = max_x - min_x;
    const depth = max_z - min_z;
    const rise = @max(0.6, @min(width, depth) * 0.25);
    const eave_y = @max(0.25, state.architecture_wall_height) + 0.12;
    var mesh = try buildGableRoofMesh(state.allocator, width, depth, rise);
    errdefer mesh.deinit(state.allocator);
    const tex = try state.allocator.alloc(u8, TextureSize * TextureSize * 4);
    errdefer state.allocator.free(tex);
    fillCheckerTexture(tex, TextureSize, 115, 78, 68);

    const name = try std.fmt.allocPrint(state.allocator, "Roof {d}", .{state.next_object_id});
    errdefer state.allocator.free(name);

    try state.objects.append(state.allocator, .{
        .id = state.next_object_id,
        .name = name,
        .mesh = mesh,
        .position = .{
            .x = (min_x + max_x) * 0.5,
            .y = eave_y,
            .z = (min_z + max_z) * 0.5,
        },
        .rotation = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = tex,
        .base_color = .{ .r = 120, .g = 80, .b = 70, .a = 255 },
        .primitive_kind = null,
        .physics = null,
    });
    state.next_object_id += 1;
    state.selected_object = state.objects.items.len - 1;
    state.selected_vertex = null;
    state.selected_edge = null;
    state.selected_face = null;
    state.scene_dirty = true;
    project_editor_state.setStatus(state, "Roof added from floorplan");
}

pub fn addPlayerStartSpawner(state: *ProjectEditorState) !void {
    const bounds = floorplanFootprintBounds(state) orelse {
        project_editor_state.setStatus(state, "Draw a floorplan first");
        return;
    };

    project_editor_edit.pushUndoSnapshot(state);
    var mesh = try buildPlayerStartMarkerMesh(state.allocator);
    errdefer mesh.deinit(state.allocator);
    const tex = try state.allocator.alloc(u8, TextureSize * TextureSize * 4);
    errdefer state.allocator.free(tex);
    fillCheckerTexture(tex, TextureSize, 80, 210, 150);

    const name = try std.fmt.allocPrint(state.allocator, "Player Start {d}", .{state.next_object_id});
    errdefer state.allocator.free(name);
    const components = try state.allocator.alloc([]u8, 2);
    errdefer state.allocator.free(components);
    components[0] = try state.allocator.dupe(u8, "spawner");
    errdefer state.allocator.free(components[0]);
    components[1] = try state.allocator.dupe(u8, fps_controller_component);
    errdefer state.allocator.free(components[1]);
    const gameplay_tag = try state.allocator.dupe(u8, player_start_tag);
    errdefer state.allocator.free(gameplay_tag);
    const width = bounds.max.x - bounds.min.x;
    const depth = bounds.max.z - bounds.min.z;

    try state.objects.append(state.allocator, .{
        .id = state.next_object_id,
        .name = name,
        .mesh = mesh,
        .position = .{
            .x = bounds.min.x + width * 0.5,
            .y = @max(0.04, state.architecture_floor_thickness) + 0.04,
            .z = bounds.min.z + depth * 0.8,
        },
        .rotation = .{ .x = 0.02, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = tex,
        .base_color = .{ .r = 80, .g = 210, .b = 150, .a = 255 },
        .primitive_kind = null,
        .object_kind = .empty,
        .renderer_visible = true,
        .cast_shadows = false,
        .receive_shadows = false,
        .components = components,
        .physics = null,
        .gameplay = .{ .tag = gameplay_tag },
    });
    state.next_object_id += 1;
    state.selected_object = state.objects.items.len - 1;
    state.selected_vertex = null;
    state.selected_edge = null;
    state.selected_face = null;
    state.scene_dirty = true;
    project_editor_state.setStatus(state, "Player start added");
}

fn addWallFromDrag(state: *ProjectEditorState) !void {
    const start = state.blockout_drag_start orelse return;
    const end = state.blockout_drag_end orelse return;
    if (pointsNear(start, end, floorplan_eps)) {
        try placeWallOutlinePointAt(state, start);
        return;
    }
    _ = try appendSemanticWallSegment(state, start, end, false);
    project_editor_state.setStatus(state, "Wall raised");
}

pub fn clearWallOutline(state: *ProjectEditorState) void {
    state.wall_outline_points.clearRetainingCapacity();
}

pub fn placeWallOutlinePointAt(state: *ProjectEditorState, point: editor_math.Vec3) !void {
    const snapped = snapVec3(.{ .x = point.x, .y = 0, .z = point.z }, if (state.snap_enabled) state.snap_size else 0);
    if (state.wall_outline_points.items.len == 0) {
        try state.wall_outline_points.append(state.allocator, snapped);
        project_editor_state.setStatus(state, "Wall point placed");
        return;
    }

    const previous = state.wall_outline_points.items[state.wall_outline_points.items.len - 1];
    const first = state.wall_outline_points.items[0];
    const target = if (state.wall_outline_points.items.len >= 2 and pointsNear(snapped, first, wall_close_distance)) first else snapped;
    if (pointsNear(previous, target, floorplan_eps)) {
        project_editor_state.setStatus(state, "Wall point unchanged");
        return;
    }

    project_editor_edit.pushUndoSnapshot(state);
    _ = try appendSemanticWallSegment(state, previous, target, pointsNear(target, first, floorplan_eps));
    if (pointsNear(target, first, floorplan_eps) and state.wall_outline_points.items.len >= 2) {
        clearWallOutline(state);
        project_editor_state.setStatus(state, "Wall loop closed");
    } else {
        try state.wall_outline_points.append(state.allocator, target);
        project_editor_state.setStatus(state, "Wall segment added");
    }
}

pub fn placeWallOutlinePointAtScreen(state: *ProjectEditorState, screen_x: f32, screen_y: f32) !void {
    const point = screenToGroundPoint(state, screen_x, screen_y) orelse {
        project_editor_state.setStatus(state, "Click the ground to place wall points");
        return;
    };
    try placeWallOutlinePointAt(state, point);
}

fn appendSemanticWallSegment(state: *ProjectEditorState, start: editor_math.Vec3, end: editor_math.Vec3, closes_loop: bool) !bool {
    if (state.mode != .architecture_creation or state.architecture_tool != .wall) return false;
    // Extend the active building (or the selected one), otherwise start a fresh
    // building. Walls never create disconnected objects: they belong to a
    // building so they move with it.
    if (architecture.activeBuildingIndex(state) orelse architecture.selectedBuildingIndex(state)) |idx| {
        try appendWallToArchitectureObject(state, idx, start, end, closes_loop);
        return true;
    }
    try createArchitectureWallChainObject(state, start, end);
    return true;
}

fn createArchitectureWallChainObject(state: *ProjectEditorState, start: editor_math.Vec3, end: editor_math.Vec3) !void {
    const height = @max(0.25, state.architecture_wall_height);
    const thickness = @max(0.05, state.architecture_wall_thickness);
    const components = try state.allocator.alloc([]u8, 4);
    errdefer state.allocator.free(components);
    var initialized: usize = 0;
    errdefer {
        for (components[0..initialized]) |component| state.allocator.free(component);
    }
    components[initialized] = try state.allocator.dupe(u8, architecture_building_component);
    initialized += 1;
    components[initialized] = try std.fmt.allocPrint(state.allocator, "arch.vertex:0|{d}|{d}", .{ start.x, start.z });
    initialized += 1;
    components[initialized] = try std.fmt.allocPrint(state.allocator, "arch.vertex:1|{d}|{d}", .{ end.x, end.z });
    initialized += 1;
    components[initialized] = try std.fmt.allocPrint(state.allocator, "arch.wall:0|0|1|{d}|{d}", .{ height, thickness });
    initialized += 1;
    try appendArchitectureObjectFromComponents(state, components, "Architecture Wall Chain");
}

fn appendWallToArchitectureObject(
    state: *ProjectEditorState,
    obj_index: usize,
    start: editor_math.Vec3,
    end: editor_math.Vec3,
    closes_loop: bool,
) !void {
    const obj = &state.objects.items[obj_index];
    var building = try parseArchitectureBuilding(state.allocator, obj.components);
    defer building.deinit(state.allocator);
    const last_wall = building.walls.items[building.walls.items.len - 1];
    const start_vertex = findMatchingArchVertex(building.vertices.items, start) orelse last_wall.b;
    const end_vertex = if (closes_loop) building.walls.items[0].a else building.nextVertexId();
    if (!closes_loop) {
        try building.vertices.append(state.allocator, .{ .id = end_vertex, .x = end.x, .z = end.z });
    }
    try building.walls.append(state.allocator, .{
        .id = building.nextWallId(),
        .a = start_vertex,
        .b = end_vertex,
        .height = @max(0.25, state.architecture_wall_height),
        .thickness = @max(0.05, state.architecture_wall_thickness),
    });
    if (closes_loop and building.roof == null) building.roof = .{ .kind = .flat, .pitch = 0, .overhang = 0.15 };
    try writeBackBuilding(state, obj, &building);
    state.selected_object = obj_index;
    architecture.setActiveBuilding(state, obj.id);
}

fn appendArchitectureObjectFromComponents(state: *ProjectEditorState, components: []const []u8, name_prefix: []const u8) !void {
    var building = try parseArchitectureBuilding(state.allocator, components);
    defer building.deinit(state.allocator);
    var mesh = try buildArchitectureBuildingMesh(state.allocator, &building);
    errdefer mesh.deinit(state.allocator);
    const tex = try state.allocator.alloc(u8, TextureSize * TextureSize * 4);
    errdefer state.allocator.free(tex);
    fillCheckerTexture(tex, TextureSize, wall_plan_color.r, wall_plan_color.g, wall_plan_color.b);
    const name = try std.fmt.allocPrint(state.allocator, "{s} {d}", .{ name_prefix, state.next_object_id });
    errdefer state.allocator.free(name);
    try state.objects.append(state.allocator, .{
        .id = state.next_object_id,
        .name = name,
        .mesh = mesh,
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .rotation = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = tex,
        .base_color = wall_plan_color,
        .primitive_kind = null,
        .physics = static_body,
        .components = components,
    });
    architecture.setActiveBuilding(state, state.next_object_id);
    state.next_object_id += 1;
    state.selected_object = state.objects.items.len - 1;
    state.selected_vertex = null;
    state.selected_edge = null;
    state.selected_face = null;
    state.scene_dirty = true;
}

fn findMatchingArchVertex(vertices: []const ArchVertex, point: editor_math.Vec3) ?u32 {
    for (vertices) |vertex| {
        if (pointsNear(vertex.point(), point, wall_close_distance)) return vertex.id;
    }
    return null;
}

fn nextVertexId(vertices: []const ArchVertex) u32 {
    var next: u32 = 0;
    for (vertices) |vertex| next = @max(next, vertex.id + 1);
    return next;
}

fn nextWallId(walls: []const ArchWall) u32 {
    var next: u32 = 0;
    for (walls) |wall| next = @max(next, wall.id + 1);
    return next;
}

fn hasRoofComponent(components: []const []const u8) bool {
    for (components) |component| {
        if (std.mem.startsWith(u8, component, "arch.roof:")) return true;
    }
    return false;
}

fn addWallSegmentBetween(state: *ProjectEditorState, start: editor_math.Vec3, end: editor_math.Vec3) !void {
    const dx = end.x - start.x;
    const dz = end.z - start.z;
    const length = @sqrt(dx * dx + dz * dz);
    const min_length = if (state.snap_enabled) @max(0.25, state.snap_size) else 0.25;
    if (length < 0.001) return;
    const wall_length = @max(length, min_length);
    const height = @max(0.25, state.architecture_wall_height);
    const thickness = @max(0.05, state.architecture_wall_thickness);
    var mesh = try geometry.buildPrimitive(state.allocator, .box, .{
        .width = wall_length,
        .height = height,
        .depth = thickness,
    });
    errdefer mesh.deinit(state.allocator);
    const tex = try state.allocator.alloc(u8, TextureSize * TextureSize * 4);
    errdefer state.allocator.free(tex);
    fillCheckerTexture(tex, TextureSize, room_wall_color.r, room_wall_color.g, room_wall_color.b);

    const name = try std.fmt.allocPrint(state.allocator, "Wall {d}", .{state.next_object_id});
    defer state.allocator.free(name);

    try state.objects.append(state.allocator, .{
        .id = state.next_object_id,
        .name = try state.allocator.dupe(u8, name),
        .mesh = mesh,
        .position = .{
            .x = (start.x + end.x) * 0.5,
            .y = height * 0.5,
            .z = (start.z + end.z) * 0.5,
        },
        .rotation = .{ .x = 0, .y = -std.math.atan2(dz, dx), .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = tex,
        .base_color = room_wall_color,
        .primitive_kind = .box,
        .physics = static_body,
    });
    state.next_object_id += 1;
    state.selected_object = state.objects.items.len - 1;
    state.selected_vertex = null;
    state.selected_edge = null;
    state.selected_face = null;
    state.scene_dirty = true;
}

fn pointsNear(a: editor_math.Vec3, b: editor_math.Vec3, distance: f32) bool {
    const dx = a.x - b.x;
    const dz = a.z - b.z;
    return dx * dx + dz * dz <= distance * distance;
}

const OpeningKind = enum { door, window };

pub fn cutDoorOpeningAtPoints(state: *ProjectEditorState, start: editor_math.Vec3, end: editor_math.Vec3) !void {
    try cutOpeningAtPoints(state, .door, start, end);
}

pub fn cutWindowOpeningAtPoints(state: *ProjectEditorState, start: editor_math.Vec3, end: editor_math.Vec3) !void {
    try cutOpeningAtPoints(state, .window, start, end);
}

fn cutOpeningAtPoints(state: *ProjectEditorState, kind: OpeningKind, start: editor_math.Vec3, end: editor_math.Vec3) !void {
    state.blockout_drag_start = start;
    state.blockout_drag_end = end;
    try cutOpeningFromDrag(state, kind);
}

fn cutOpeningFromDrag(state: *ProjectEditorState, kind: OpeningKind) !void {
    if (try cutArchitectureBuildingOpeningFromDrag(state, kind)) return;
    if (try cutSelectedWallSegmentOpeningFromDrag(state, kind)) return;

    var bounds = blockoutBrushAabb(state) orelse return;
    bounds.min.y = switch (kind) {
        .door => 0.0,
        .window => state.architecture_window_sill,
    };
    bounds.max.y = switch (kind) {
        .door => @max(0.25, state.architecture_door_height),
        .window => state.architecture_window_sill + @max(0.25, state.architecture_window_height),
    };
    try subtractDoorwayBlockoutBox(state, bounds.min, bounds.max);
    project_editor_state.setStatus(state, switch (kind) {
        .door => "Door cut",
        .window => "Window cut",
    });
}

fn cutArchitectureBuildingOpeningFromDrag(state: *ProjectEditorState, kind: OpeningKind) !bool {
    const idx = architecture.editTargetIndex(state) orelse return false;
    const obj = &state.objects.items[idx];
    const world_start = state.blockout_drag_start orelse return false;
    const world_end = state.blockout_drag_end orelse return false;
    const building_world = scene_hierarchy.objectWorldPosition(state.objects.items, idx);
    const start = editor_math.Vec3.sub(world_start, building_world);
    const end = editor_math.Vec3.sub(world_end, building_world);

    var building = try parseArchitectureBuilding(state.allocator, obj.components);
    defer building.deinit(state.allocator);
    const wall_pick = nearestArchitectureWall(building, start, end) orelse return false;
    const wall = building.walls.items[wall_pick.wall_index];
    const width = @max(wall_pick.width, if (kind == .door) @as(f32, 0.8) else @as(f32, 0.7));
    const wall_len = wall_pick.length;
    if (width >= wall_len - 0.2) return error.InvalidArchitectureOpening;
    const t = std.math.clamp(wall_pick.center_along / wall_len, 0.05, 0.95);
    const bottom: f32 = switch (kind) {
        .door => 0.0,
        .window => std.math.clamp(state.architecture_window_sill, 0.0, wall.height),
    };
    const top: f32 = switch (kind) {
        .door => @min(wall.height, @max(0.25, state.architecture_door_height)),
        .window => @min(wall.height, bottom + @max(0.25, state.architecture_window_height)),
    };
    if (top <= bottom) return error.InvalidArchitectureOpening;
    if (architectureOpeningOverlaps(building.openings.items, wall.id, wall_len, t, width / wall_len)) return error.InvalidArchitectureOpening;

    try building.openings.append(state.allocator, .{
        .id = building.nextOpeningId(),
        .wall_id = wall.id,
        .kind = switch (kind) {
            .door => .door,
            .window => .window,
        },
        .t = t,
        .width = width,
        .height = top - bottom,
        .sill = bottom,
    });
    try writeBackBuilding(state, obj, &building);
    project_editor_state.setStatus(state, switch (kind) {
        .door => "Door attached to wall",
        .window => "Window attached to wall",
    });
    return true;
}

const ArchitectureWallPick = struct {
    wall_index: usize,
    center_along: f32,
    width: f32,
    length: f32,
};

fn nearestArchitectureWall(building: ArchitectureBuilding, start: editor_math.Vec3, end: editor_math.Vec3) ?ArchitectureWallPick {
    var best: ?ArchitectureWallPick = null;
    var best_distance = std.math.floatMax(f32);
    const drag_center: editor_math.Vec3 = .{
        .x = (start.x + end.x) * 0.5,
        .y = 0,
        .z = (start.z + end.z) * 0.5,
    };
    for (building.walls.items, 0..) |wall, idx| {
        const a = building.findVertex(wall.a) orelse continue;
        const b = building.findVertex(wall.b) orelse continue;
        const dx = b.x - a.x;
        const dz = b.z - a.z;
        const length = @sqrt(dx * dx + dz * dz);
        if (length <= floorplan_eps) continue;
        const dir: editor_math.Vec3 = .{ .x = dx / length, .y = 0, .z = dz / length };
        const center_along = std.math.clamp((drag_center.x - a.x) * dir.x + (drag_center.z - a.z) * dir.z, 0.0, length);
        const closest: editor_math.Vec3 = .{ .x = a.x + dir.x * center_along, .y = 0, .z = a.z + dir.z * center_along };
        const dist_x = drag_center.x - closest.x;
        const dist_z = drag_center.z - closest.z;
        const distance = dist_x * dist_x + dist_z * dist_z;
        if (distance >= best_distance) continue;
        const start_along = (start.x - a.x) * dir.x + (start.z - a.z) * dir.z;
        const end_along = (end.x - a.x) * dir.x + (end.z - a.z) * dir.z;
        best_distance = distance;
        best = .{
            .wall_index = idx,
            .center_along = center_along,
            .width = @abs(end_along - start_along),
            .length = length,
        };
    }
    return best;
}

fn architectureOpeningOverlaps(openings: []const arch.WallOpening, wall_id: u32, wall_len: f32, t: f32, width: f32) bool {
    const margin: f32 = 0.04;
    const start = t - width * 0.5 - margin;
    const end = t + width * 0.5 + margin;
    if (start < 0 or end > 1) return true;
    for (openings) |opening| {
        if (opening.wall_id != wall_id) continue;
        const other_width = opening.width / wall_len;
        const other_start = opening.t - other_width * 0.5 - margin;
        const other_end = opening.t + other_width * 0.5 + margin;
        if (start < other_end and end > other_start) return true;
    }
    return false;
}

fn cutSelectedWallSegmentOpeningFromDrag(state: *ProjectEditorState, kind: OpeningKind) !bool {
    const idx = state.selected_object orelse return false;
    if (idx >= state.objects.items.len) return false;
    const wall = &state.objects.items[idx];
    if (!isOutlineWallObject(wall)) return false;
    const start = state.blockout_drag_start orelse return false;
    const end = state.blockout_drag_end orelse return false;
    const dims = meshBoxDimensions(&wall.mesh) orelse return false;
    const half_len = dims.x * 0.5;
    const height = dims.y;
    const thickness = dims.z;
    const dir = wallDirection(wall.rotation.y);
    const start_x = projectAlongWall(start, wall.position, dir);
    const end_x = projectAlongWall(end, wall.position, dir);
    const min_width: f32 = if (kind == .door) 0.8 else 0.7;
    var open_min = @max(-half_len + 0.1, @min(start_x, end_x));
    var open_max = @min(half_len - 0.1, @max(start_x, end_x));
    if (open_max - open_min < min_width) {
        const center = std.math.clamp((open_min + open_max) * 0.5, -half_len + min_width * 0.5, half_len - min_width * 0.5);
        open_min = center - min_width * 0.5;
        open_max = center + min_width * 0.5;
    }
    if (open_max <= open_min or open_min <= -half_len and open_max >= half_len) return false;

    const opening_bottom: f32 = switch (kind) {
        .door => 0.0,
        .window => std.math.clamp(state.architecture_window_sill, 0.0, @max(0.0, height - 0.25)),
    };
    const opening_top: f32 = switch (kind) {
        .door => @min(height, @max(0.25, state.architecture_door_height)),
        .window => @min(height, opening_bottom + @max(0.25, state.architecture_window_height)),
    };
    if (opening_top <= opening_bottom) return false;

    const base = wall.position;
    const rotation = wall.rotation.y;
    try addWallPiece(state, base, dir, rotation, -half_len, open_min, 0, height, thickness);
    try addWallPiece(state, base, dir, rotation, open_max, half_len, 0, height, thickness);
    try addWallPiece(state, base, dir, rotation, open_min, open_max, opening_top, height, thickness);
    try addWallPiece(state, base, dir, rotation, open_min, open_max, 0, opening_bottom, thickness);

    var removed = state.objects.orderedRemove(idx);
    removed.deinit(state.allocator);
    if (state.objects.items.len == 0) {
        state.selected_object = null;
    } else {
        state.selected_object = state.objects.items.len - 1;
    }
    state.selected_vertex = null;
    state.selected_edge = null;
    state.selected_face = null;
    state.scene_dirty = true;
    project_editor_state.setStatus(state, switch (kind) {
        .door => "Door cut into wall",
        .window => "Window cut into wall",
    });
    return true;
}

fn addWallPiece(
    state: *ProjectEditorState,
    base: editor_math.Vec3,
    dir: editor_math.Vec3,
    rotation_y: f32,
    x0: f32,
    x1: f32,
    y0: f32,
    y1: f32,
    thickness: f32,
) !void {
    const length = x1 - x0;
    const height = y1 - y0;
    if (length <= floorplan_eps or height <= floorplan_eps) return;
    var mesh = try geometry.buildPrimitive(state.allocator, .box, .{
        .width = length,
        .height = height,
        .depth = thickness,
    });
    errdefer mesh.deinit(state.allocator);
    const tex = try state.allocator.alloc(u8, TextureSize * TextureSize * 4);
    errdefer state.allocator.free(tex);
    fillCheckerTexture(tex, TextureSize, room_wall_color.r, room_wall_color.g, room_wall_color.b);
    const name = try std.fmt.allocPrint(state.allocator, "Wall {d}", .{state.next_object_id});
    defer state.allocator.free(name);
    const center_x = (x0 + x1) * 0.5;
    try state.objects.append(state.allocator, .{
        .id = state.next_object_id,
        .name = try state.allocator.dupe(u8, name),
        .mesh = mesh,
        .position = .{
            .x = base.x + dir.x * center_x,
            .y = (y0 + y1) * 0.5,
            .z = base.z + dir.z * center_x,
        },
        .rotation = .{ .x = 0, .y = rotation_y, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = tex,
        .base_color = room_wall_color,
        .primitive_kind = .box,
        .physics = static_body,
    });
    state.next_object_id += 1;
    state.selected_object = state.objects.items.len - 1;
}

fn isOutlineWallObject(obj: *const SceneObject) bool {
    return std.mem.startsWith(u8, obj.name, "Wall") and obj.primitive_kind == .box and obj.blockout_intent == null;
}

fn wallDirection(rotation_y: f32) editor_math.Vec3 {
    const angle = -rotation_y;
    return .{ .x = @cos(angle), .y = 0, .z = @sin(angle) };
}

fn projectAlongWall(point: editor_math.Vec3, base: editor_math.Vec3, dir: editor_math.Vec3) f32 {
    return (point.x - base.x) * dir.x + (point.z - base.z) * dir.z;
}

fn meshBoxDimensions(mesh: *const geometry.Mesh) ?editor_math.Vec3 {
    if (mesh.vertices.len == 0) return null;
    var min = mesh.vertices[0].position;
    var max = mesh.vertices[0].position;
    for (mesh.vertices[1..]) |vertex| {
        min.x = @min(min.x, vertex.position.x);
        min.y = @min(min.y, vertex.position.y);
        min.z = @min(min.z, vertex.position.z);
        max.x = @max(max.x, vertex.position.x);
        max.y = @max(max.y, vertex.position.y);
        max.z = @max(max.z, vertex.position.z);
    }
    return .{ .x = max.x - min.x, .y = max.y - min.y, .z = max.z - min.z };
}

test "bartizan conical roof triangles face outward" {
    var vertices: std.ArrayList(geometry.Vertex) = .empty;
    defer vertices.deinit(std.testing.allocator);
    var indices: std.ArrayList(u32) = .empty;
    defer indices.deinit(std.testing.allocator);

    const feature = arch.Feature{
        .id = 1,
        .kind = .bartizan,
        .x = 2.0,
        .z = -1.5,
        .height = 5.0,
        .width = 1.1,
        .depth = 2.2,
        .dir_x = 1,
        .dir_z = 0,
        .steps = 12,
    };
    try appendBartizanFeature(std.testing.allocator, &vertices, &indices, feature);

    const segments: usize = @intCast(@max(@as(u32, 8), feature.steps));
    const shell_index_count = segments * 6;
    try std.testing.expect(indices.items.len > shell_index_count);

    const roof_center: editor_math.Vec3 = .{
        .x = feature.x,
        .y = feature.height + feature.depth + 0.08,
        .z = feature.z,
    };
    var tri = shell_index_count;
    while (tri + 2 < indices.items.len) : (tri += 3) {
        const a = vertices.items[indices.items[tri]];
        const b = vertices.items[indices.items[tri + 1]];
        const c = vertices.items[indices.items[tri + 2]];
        const winding_normal = roofTriangleNormal(a.position, b.position, c.position);
        const centroid: editor_math.Vec3 = .{
            .x = (a.position.x + b.position.x + c.position.x) / 3.0,
            .y = (a.position.y + b.position.y + c.position.y) / 3.0,
            .z = (a.position.z + b.position.z + c.position.z) / 3.0,
        };
        const outward = editor_math.Vec3.normalized(.{
            .x = centroid.x - roof_center.x,
            .y = 0,
            .z = centroid.z - roof_center.z,
        });

        inline for (.{ a, b, c }) |vertex| {
            try std.testing.expect(editor_math.Vec3.dot(vertex.normal, winding_normal) > 0.98);
        }
        if (a.normal.y < -0.9) {
            try std.testing.expect(winding_normal.y < -0.98);
        } else {
            try std.testing.expect(editor_math.Vec3.dot(winding_normal, outward) > 0.35);
            inline for (.{ a, b, c }) |vertex| {
                try std.testing.expect(editor_math.Vec3.dot(vertex.normal, outward) > 0.35);
            }
        }
    }
}
