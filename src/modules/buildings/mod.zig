const std = @import("std");
const core = @import("../../core/mod.zig");
const framework = @import("../../framework/mod.zig");
const world = @import("../../world/mod.zig");
const kdl = @import("kdl");
const layer_kdl = @import("../layer_kdl.zig");

const storage = @import("storage.zig");
pub const module_name = "gem.buildings";
const layer_name = "world.layer.buildings";
const buildings_layer_file = "layers/buildings.kdl";
const tex_size: usize = 128 * 128 * 4;
const default_meters_per_repeat: f32 = 1.0;

pub const BuildingsDoc = struct {
    schema_version: u32 = 1,
    buildings: []const BuildingDef = &.{},
};

pub const BuildingDef = struct {
    id: []const u8,
    cell: []const i32,
    floors: u32,
    footprint: []const []const f32,
    doors: []const DoorDef = &.{},
    windows: []const WindowDef = &.{},
};

pub const DoorDef = struct {
    edge_index: u32,
    offset: f32,
    width: f32,
    height: f32,
};

pub const WindowDef = struct {
    edge_index: u32,
    offset: f32,
    width: f32,
    height: f32,
    sill: f32 = 1.0,
};

pub const authoring_helpers = @import("authoring_helpers.zig");
pub const BuildingKind = authoring_helpers.BuildingKind;
pub const SemanticBuildingDescriptor = authoring_helpers.SemanticBuildingDescriptor;
pub const BuildingDescriptor = authoring_helpers.BuildingDescriptor;
pub const BuildingFootprintScratch = authoring_helpers.BuildingFootprintScratch;
pub const makeRectangularBuilding = authoring_helpers.makeRectangularBuilding;

pub fn register(registry: anytype) !void {
    try registry.registerWorldCompilerLayer(.{
        .name = layer_name,
        .affected_cells = affectedCells,
        .compile_cell = compileCell,
    });
}

pub fn start(engine_world: *framework.World) !void {
    try engine_world.notifications.publish("gem.buildings.started", "{}");
}

pub fn stop(engine_world: *framework.World) !void {
    try engine_world.notifications.publish("gem.buildings.stopped", "{}");
}

fn affectedCells(
    _: ?*anyopaque,
    compile_ctx: *const world.compiler.layer.CompileContext,
    allocator: std.mem.Allocator,
) ![]world.cell.CellId {
    var doc = try storage.loadDoc(allocator, compile_ctx);
    defer doc.deinit();
    var ids = std.ArrayList(world.cell.CellId).empty;
    defer ids.deinit(allocator);
    var lookup = std.AutoHashMap(world.cell.CellId, void).init(allocator);
    defer lookup.deinit();
    for (doc.value.buildings) |entry| {
        const id = try storage.parseCellId(entry.cell);
        if (lookup.contains(id)) continue;
        try lookup.put(id, {});
        try ids.append(allocator, id);
    }
    return ids.toOwnedSlice(allocator);
}

pub fn compileCell(
    _: ?*anyopaque,
    compile_ctx: *const world.compiler.layer.CompileContext,
    id: world.cell.CellId,
    allocator: std.mem.Allocator,
) !world.compiler.layer.CellLayerOutput {
    var doc = try storage.loadDoc(allocator, compile_ctx);
    defer doc.deinit();

    var meshes = std.ArrayList(world.cell.RenderMesh).empty;
    var collisions = std.ArrayList(world.cell.CollisionPlaceholder).empty;
    var collision_shapes = std.ArrayList(world.cell.CollisionShape).empty;
    var nav_vertices = std.ArrayList(core.math.Vec3f).empty;
    var nav_indices = std.ArrayList(u32).empty;
    var visibility = std.ArrayList(world.cell.VisibilityLink).empty;
    var blobs = std.ArrayList(world.cell.CellBlob).empty;
    errdefer {
        for (meshes.items) |*mesh| mesh.deinit(allocator);
        meshes.deinit(allocator);
        collisions.deinit(allocator);
        collision_shapes.deinit(allocator);
        nav_vertices.deinit(allocator);
        nav_indices.deinit(allocator);
        visibility.deinit(allocator);
        for (blobs.items) |*blob| blob.deinit(allocator);
        blobs.deinit(allocator);
    }

    var matched = false;
    for (doc.value.buildings) |building| {
        if (!(try storage.parseCellId(building.cell)).eql(id)) continue;
        matched = true;
        try validateBuilding(building);
        try buildBuildingMeshes(allocator, &meshes, &collisions, &collision_shapes, &nav_vertices, &nav_indices, building);
        try appendDoorVisibility(allocator, &visibility, id, building);

        try world.compiler.layer.appendBlobJson(allocator, &blobs, "building.portals", .{
            .building_id = building.id,
            .cell = .{ id.x, id.y, id.z },
            .doors = building.doors,
        });
        try world.compiler.layer.appendBlobJson(allocator, &blobs, "building.lod_shell", .{
            .building_id = building.id,
            .cell = .{ id.x, id.y, id.z },
            .floors = building.floors,
            .footprint = building.footprint,
        });
    }
    if (!matched) return .{};

    return .{
        .render_meshes = try meshes.toOwnedSlice(allocator),
        .collisions = try collisions.toOwnedSlice(allocator),
        .collision_shapes = try collision_shapes.toOwnedSlice(allocator),
        .nav_vertices = try nav_vertices.toOwnedSlice(allocator),
        .nav_indices = try nav_indices.toOwnedSlice(allocator),
        .visibility = try visibility.toOwnedSlice(allocator),
        .blobs = try blobs.toOwnedSlice(allocator),
    };
}

fn buildBuildingMeshes(
    allocator: std.mem.Allocator,
    meshes: *std.ArrayList(world.cell.RenderMesh),
    collisions: *std.ArrayList(world.cell.CollisionPlaceholder),
    collision_shapes: *std.ArrayList(world.cell.CollisionShape),
    nav_vertices: *std.ArrayList(core.math.Vec3f),
    nav_indices: *std.ArrayList(u32),
    building: BuildingDef,
) !void {
    const floor_h: f32 = 3.0;
    const height = @as(f32, @floatFromInt(building.floors)) * floor_h;

    try buildExteriorShell(allocator, meshes, building, height);
    try buildInteriorFloors(allocator, meshes, building, floor_h);
    try buildDoorTrims(allocator, meshes, building, height);
    try buildWindowMeshes(allocator, meshes, building);
    try buildLodShell(allocator, meshes, building, height);

    var min_x = std.math.floatMax(f32);
    var max_x = -std.math.floatMax(f32);
    var min_z = std.math.floatMax(f32);
    var max_z = -std.math.floatMax(f32);
    for (building.footprint) |point| {
        min_x = @min(min_x, point[0]);
        max_x = @max(max_x, point[0]);
        min_z = @min(min_z, point[1]);
        max_z = @max(max_z, point[1]);
    }
    try collisions.append(allocator, .{
        .min = .{ .x = min_x, .y = 0, .z = min_z },
        .max = .{ .x = max_x, .y = height, .z = max_z },
    });
    try collision_shapes.append(allocator, .{
        .kind = .aabb,
        .min = .{ .x = min_x, .y = 0, .z = min_z },
        .max = .{ .x = max_x, .y = height, .z = max_z },
    });
    try appendBuildingNav(allocator, nav_vertices, nav_indices, building, floor_h);
}

fn appendBuildingNav(
    allocator: std.mem.Allocator,
    nav_vertices: *std.ArrayList(core.math.Vec3f),
    nav_indices: *std.ArrayList(u32),
    building: BuildingDef,
    floor_height: f32,
) !void {
    var floor_index: u32 = 0;
    while (floor_index < building.floors) : (floor_index += 1) {
        const y = @as(f32, @floatFromInt(floor_index)) * floor_height;
        const base: u32 = @intCast(nav_vertices.items.len);
        for (building.footprint) |point| {
            try nav_vertices.append(allocator, .{
                .x = point[0],
                .y = y,
                .z = point[1],
            });
        }
        var i: usize = 1;
        while (i + 1 < building.footprint.len) : (i += 1) {
            try nav_indices.appendSlice(allocator, &.{
                base,
                base + @as(u32, @intCast(i)),
                base + @as(u32, @intCast(i + 1)),
            });
        }
    }
}

fn appendDoorVisibility(
    allocator: std.mem.Allocator,
    visibility: *std.ArrayList(world.cell.VisibilityLink),
    cell_id: world.cell.CellId,
    building: BuildingDef,
) !void {
    for (building.doors) |door| {
        const edge_index: usize = @intCast(door.edge_index);
        const a = building.footprint[edge_index];
        const b = building.footprint[(edge_index + 1) % building.footprint.len];
        const center_x = a[0] + (b[0] - a[0]) * door.offset;
        const center_z = a[1] + (b[1] - a[1]) * door.offset;
        const half_w = door.width * 0.5;
        try visibility.append(allocator, .{
            .target = cell_id,
            .min = .{ .x = center_x - half_w, .y = 0, .z = center_z - 0.1 },
            .max = .{ .x = center_x + half_w, .y = door.height, .z = center_z + 0.1 },
        });
    }
}

fn buildExteriorShell(
    allocator: std.mem.Allocator,
    meshes: *std.ArrayList(world.cell.RenderMesh),
    building: BuildingDef,
    height: f32,
) !void {
    var i: usize = 0;
    while (i < building.footprint.len) : (i += 1) {
        const a = building.footprint[i];
        const b = building.footprint[(i + 1) % building.footprint.len];
        const wall_width = pointDistance2(a, b) / default_meters_per_repeat;
        const wall_height = height / default_meters_per_repeat;
        const verts = try allocator.dupe(world.cell.RenderVertex, &.{
            .{ .position = .{ .x = a[0], .y = 0, .z = a[1] }, .normal = .{ .x = 0, .y = 0, .z = 1 }, .uv = .{ .x = 0, .y = 0 } },
            .{ .position = .{ .x = b[0], .y = 0, .z = b[1] }, .normal = .{ .x = 0, .y = 0, .z = 1 }, .uv = .{ .x = wall_width, .y = 0 } },
            .{ .position = .{ .x = b[0], .y = height, .z = b[1] }, .normal = .{ .x = 0, .y = 0, .z = 1 }, .uv = .{ .x = wall_width, .y = wall_height } },
            .{ .position = .{ .x = a[0], .y = height, .z = a[1] }, .normal = .{ .x = 0, .y = 0, .z = 1 }, .uv = .{ .x = 0, .y = wall_height } },
        });
        errdefer allocator.free(verts);
        const indices = try allocator.dupe(u32, &.{ 0, 1, 2, 0, 2, 3 });
        errdefer allocator.free(indices);
        const texture = try allocator.alloc(u8, tex_size);
        @memset(texture, 140);
        errdefer allocator.free(texture);
        try meshes.append(allocator, .{
            .name = try allocator.dupe(u8, "building.exterior"),
            .vertices = verts,
            .indices = indices,
            .texture = texture,
            .base_color = .{ .r = 165, .g = 160, .b = 150, .a = 255 },
            .position = .{ .x = 0, .y = 0, .z = 0 },
            .scale = .{ .x = 1, .y = 1, .z = 1 },
        });
    }
}

fn buildInteriorFloors(
    allocator: std.mem.Allocator,
    meshes: *std.ArrayList(world.cell.RenderMesh),
    building: BuildingDef,
    floor_height: f32,
) !void {
    const tri_count = building.footprint.len - 2;
    var floor_index: u32 = 0;
    while (floor_index < building.floors) : (floor_index += 1) {
        const y = @as(f32, @floatFromInt(floor_index)) * floor_height;
        const verts = try allocator.alloc(world.cell.RenderVertex, building.footprint.len);
        errdefer allocator.free(verts);
        for (building.footprint, 0..) |point, i| {
            verts[i] = .{
                .position = .{ .x = point[0], .y = y, .z = point[1] },
                .normal = .{ .x = 0, .y = 1, .z = 0 },
                .uv = .{ .x = point[0], .y = point[1] },
            };
        }
        const indices = try allocator.alloc(u32, tri_count * 3);
        errdefer allocator.free(indices);
        var t: usize = 0;
        var i: usize = 1;
        while (i + 1 < building.footprint.len) : (i += 1) {
            indices[t + 0] = 0;
            indices[t + 1] = @intCast(i);
            indices[t + 2] = @intCast(i + 1);
            t += 3;
        }
        const texture = try allocator.alloc(u8, tex_size);
        @memset(texture, 118);
        errdefer allocator.free(texture);
        try meshes.append(allocator, .{
            .name = try allocator.dupe(u8, "building.interior.floor"),
            .vertices = verts,
            .indices = indices,
            .texture = texture,
            .base_color = .{ .r = 150, .g = 150, .b = 150, .a = 255 },
            .position = .{ .x = 0, .y = 0, .z = 0 },
            .scale = .{ .x = 1, .y = 1, .z = 1 },
        });
    }
}

fn buildDoorTrims(
    allocator: std.mem.Allocator,
    meshes: *std.ArrayList(world.cell.RenderMesh),
    building: BuildingDef,
    height: f32,
) !void {
    _ = height;
    for (building.doors) |door| {
        const edge_index: usize = @intCast(door.edge_index);
        const a = building.footprint[edge_index];
        const b = building.footprint[(edge_index + 1) % building.footprint.len];
        const center_x = a[0] + (b[0] - a[0]) * door.offset;
        const center_z = a[1] + (b[1] - a[1]) * door.offset;
        const half_w = door.width * 0.5;
        const door_u = door.width / default_meters_per_repeat;
        const door_v = door.height / default_meters_per_repeat;
        const verts = try allocator.dupe(world.cell.RenderVertex, &.{
            .{ .position = .{ .x = center_x - half_w, .y = 0, .z = center_z }, .normal = .{ .x = 0, .y = 0, .z = 1 }, .uv = .{ .x = 0, .y = 0 } },
            .{ .position = .{ .x = center_x + half_w, .y = 0, .z = center_z }, .normal = .{ .x = 0, .y = 0, .z = 1 }, .uv = .{ .x = door_u, .y = 0 } },
            .{ .position = .{ .x = center_x + half_w, .y = door.height, .z = center_z }, .normal = .{ .x = 0, .y = 0, .z = 1 }, .uv = .{ .x = door_u, .y = door_v } },
            .{ .position = .{ .x = center_x - half_w, .y = door.height, .z = center_z }, .normal = .{ .x = 0, .y = 0, .z = 1 }, .uv = .{ .x = 0, .y = door_v } },
        });
        errdefer allocator.free(verts);
        const indices = try allocator.dupe(u32, &.{ 0, 1, 2, 0, 2, 3 });
        errdefer allocator.free(indices);
        const texture = try allocator.alloc(u8, tex_size);
        @memset(texture, 180);
        errdefer allocator.free(texture);
        try meshes.append(allocator, .{
            .name = try allocator.dupe(u8, "building.door.trim"),
            .vertices = verts,
            .indices = indices,
            .texture = texture,
            .base_color = .{ .r = 190, .g = 170, .b = 140, .a = 255 },
            .position = .{ .x = 0, .y = 0, .z = 0 },
            .scale = .{ .x = 1, .y = 1, .z = 1 },
        });
    }
}

fn buildWindowMeshes(
    allocator: std.mem.Allocator,
    meshes: *std.ArrayList(world.cell.RenderMesh),
    building: BuildingDef,
) !void {
    for (building.windows) |window| {
        const edge_index: usize = @intCast(window.edge_index);
        const a = building.footprint[edge_index];
        const b = building.footprint[(edge_index + 1) % building.footprint.len];
        const center_x = a[0] + (b[0] - a[0]) * window.offset;
        const center_z = a[1] + (b[1] - a[1]) * window.offset;
        const half_w = window.width * 0.5;
        const window_u = window.width / default_meters_per_repeat;
        const window_v = window.height / default_meters_per_repeat;
        const verts = try allocator.dupe(world.cell.RenderVertex, &.{
            .{ .position = .{ .x = center_x - half_w, .y = window.sill, .z = center_z }, .normal = .{ .x = 0, .y = 0, .z = 1 }, .uv = .{ .x = 0, .y = 0 } },
            .{ .position = .{ .x = center_x + half_w, .y = window.sill, .z = center_z }, .normal = .{ .x = 0, .y = 0, .z = 1 }, .uv = .{ .x = window_u, .y = 0 } },
            .{ .position = .{ .x = center_x + half_w, .y = window.sill + window.height, .z = center_z }, .normal = .{ .x = 0, .y = 0, .z = 1 }, .uv = .{ .x = window_u, .y = window_v } },
            .{ .position = .{ .x = center_x - half_w, .y = window.sill + window.height, .z = center_z }, .normal = .{ .x = 0, .y = 0, .z = 1 }, .uv = .{ .x = 0, .y = window_v } },
        });
        errdefer allocator.free(verts);
        const indices = try allocator.dupe(u32, &.{ 0, 1, 2, 0, 2, 3 });
        errdefer allocator.free(indices);
        const texture = try allocator.alloc(u8, tex_size);
        @memset(texture, 205);
        errdefer allocator.free(texture);
        try meshes.append(allocator, .{
            .name = try allocator.dupe(u8, "building.window"),
            .vertices = verts,
            .indices = indices,
            .texture = texture,
            .base_color = .{ .r = 160, .g = 190, .b = 220, .a = 255 },
            .position = .{ .x = 0, .y = 0, .z = 0 },
            .scale = .{ .x = 1, .y = 1, .z = 1 },
        });
    }
}

fn buildLodShell(
    allocator: std.mem.Allocator,
    meshes: *std.ArrayList(world.cell.RenderMesh),
    building: BuildingDef,
    height: f32,
) !void {
    var min_x = std.math.floatMax(f32);
    var max_x = -std.math.floatMax(f32);
    var min_z = std.math.floatMax(f32);
    var max_z = -std.math.floatMax(f32);
    for (building.footprint) |point| {
        min_x = @min(min_x, point[0]);
        max_x = @max(max_x, point[0]);
        min_z = @min(min_z, point[1]);
        max_z = @max(max_z, point[1]);
    }
    const shell_u = (max_x - min_x) / default_meters_per_repeat;
    const shell_v = @sqrt((max_z - min_z) * (max_z - min_z) + height * height) / default_meters_per_repeat;
    const verts = try allocator.dupe(world.cell.RenderVertex, &.{
        .{ .position = .{ .x = min_x, .y = 0, .z = min_z }, .normal = .{ .x = 0, .y = 1, .z = 0 }, .uv = .{ .x = 0, .y = 0 } },
        .{ .position = .{ .x = max_x, .y = 0, .z = min_z }, .normal = .{ .x = 0, .y = 1, .z = 0 }, .uv = .{ .x = shell_u, .y = 0 } },
        .{ .position = .{ .x = max_x, .y = height, .z = max_z }, .normal = .{ .x = 0, .y = 1, .z = 0 }, .uv = .{ .x = shell_u, .y = shell_v } },
        .{ .position = .{ .x = min_x, .y = height, .z = max_z }, .normal = .{ .x = 0, .y = 1, .z = 0 }, .uv = .{ .x = 0, .y = shell_v } },
    });
    errdefer allocator.free(verts);
    const indices = try allocator.dupe(u32, &.{ 0, 1, 2, 0, 2, 3 });
    errdefer allocator.free(indices);
    const texture = try allocator.alloc(u8, tex_size);
    @memset(texture, 80);
    errdefer allocator.free(texture);
    try meshes.append(allocator, .{
        .name = try allocator.dupe(u8, "building.lod.shell"),
        .vertices = verts,
        .indices = indices,
        .texture = texture,
        .base_color = .{ .r = 120, .g = 120, .b = 120, .a = 255 },
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
    });
}

pub fn validateBuilding(building: BuildingDef) !void {
    _ = try storage.parseCellId(building.cell);
    if (building.id.len == 0) return error.InvalidBuildingDefinition;
    if (building.floors == 0) return error.InvalidBuildingDefinition;
    if (building.footprint.len < 3) return error.InvalidBuildingDefinition;
    for (building.footprint) |point| {
        if (point.len != 2) return error.InvalidBuildingFootprint;
        if (!std.math.isFinite(point[0]) or !std.math.isFinite(point[1])) return error.InvalidBuildingFootprint;
    }
    const height = @as(f32, @floatFromInt(building.floors)) * 3.0;
    for (building.doors) |door| {
        if (door.edge_index >= building.footprint.len) return error.InvalidBuildingOpening;
        if (!std.math.isFinite(door.offset) or door.offset < 0 or door.offset > 1) return error.InvalidBuildingOpening;
        if (!std.math.isFinite(door.width) or !std.math.isFinite(door.height)) return error.InvalidBuildingOpening;
        if (door.width <= 0 or door.height <= 0) return error.InvalidBuildingOpening;
        if (door.height > height) return error.InvalidBuildingOpening;
        if (!openingFitsEdge(building.footprint, door.edge_index, door.offset, door.width)) return error.InvalidBuildingOpening;
    }
    for (building.windows) |window| {
        if (window.edge_index >= building.footprint.len) return error.InvalidBuildingOpening;
        if (!std.math.isFinite(window.offset) or window.offset < 0 or window.offset > 1) return error.InvalidBuildingOpening;
        if (!std.math.isFinite(window.width) or !std.math.isFinite(window.height) or !std.math.isFinite(window.sill)) return error.InvalidBuildingOpening;
        if (window.width <= 0 or window.height <= 0 or window.sill < 0) return error.InvalidBuildingOpening;
        if (window.sill + window.height > height) return error.InvalidBuildingOpening;
        if (!openingFitsEdge(building.footprint, window.edge_index, window.offset, window.width)) return error.InvalidBuildingOpening;
    }
}

fn pointDistance2(a: []const f32, b: []const f32) f32 {
    const dx = b[0] - a[0];
    const dz = b[1] - a[1];
    return @sqrt(dx * dx + dz * dz);
}

pub fn validateSemanticBuildingDescriptor(descriptor: SemanticBuildingDescriptor) !void {
    _ = descriptor.kind;
    if (descriptor.id.len == 0) return error.InvalidBuildingDefinition;
    if (descriptor.floors == 0) return error.InvalidBuildingDefinition;
    if (!std.math.isFinite(descriptor.origin[0]) or !std.math.isFinite(descriptor.origin[1])) return error.InvalidBuildingDefinition;
    if (!std.math.isFinite(descriptor.size[0]) or !std.math.isFinite(descriptor.size[1])) return error.InvalidBuildingDefinition;
    if (descriptor.size[0] <= 0 or descriptor.size[1] <= 0) return error.InvalidBuildingDefinition;
}

fn openingFitsEdge(footprint: []const []const f32, edge_index_raw: u32, offset: f32, width: f32) bool {
    const edge_index: usize = @intCast(edge_index_raw);
    const a = footprint[edge_index];
    const b = footprint[(edge_index + 1) % footprint.len];
    const dx = b[0] - a[0];
    const dz = b[1] - a[1];
    const len = @sqrt(dx * dx + dz * dz);
    if (len <= 0) return false;
    const center = len * offset;
    const half_width = width * 0.5;
    return center >= half_width and len - center >= half_width;
}

comptime {
    _ = @import("mod_tests.zig");
}
comptime {
    _ = @import("mod_tests.zig");
}
