const std = @import("std");
const core = @import("../../core/mod.zig");
const framework = @import("../../framework/mod.zig");
const world = @import("../../world/mod.zig");

const storage = @import("storage.zig");
pub const module_name = "gem.sectors";
const layer_name = "world.layer.sectors";
const texture_size: usize = 128 * 128 * 4;

pub const SectorsDoc = struct {
    schema_version: u32 = 1,
    interiors: []const InteriorDef = &.{},
};

pub const InteriorDef = struct {
    cell: []const i32,
    parent_cell: []const i32,
    sectors: []const SectorDef,
};

pub const SectorDef = struct {
    id: u32,
    floor_height: f32,
    ceiling_height: f32,
    polygon: []const []const f32,
    portals: []const PortalDef = &.{},
};

pub const PortalDef = struct {
    to_sector: u32,
    position: []const f32,
    width: f32,
    height: f32,
};

pub const RoomRect = struct {
    id: u32,
    origin: [2]f32,
    size: [2]f32,
    floor_height: f32 = 0,
    ceiling_height: f32 = 3,
};

pub const RoomPlan = RoomRect;

pub const SectorPolygonScratch = struct {
    points: [4][2]f32 = undefined,
    slices: [4][]const f32 = undefined,
};

pub const PortalPositionScratch = struct {
    values: [3]f32 = undefined,
};

pub fn makeRectangularSector(
    scratch: *SectorPolygonScratch,
    room: RoomRect,
    portals: []const PortalDef,
) !SectorDef {
    try validateRoomRect(room);
    const x0 = room.origin[0];
    const z0 = room.origin[1];
    const x1 = x0 + room.size[0];
    const z1 = z0 + room.size[1];
    scratch.points = .{
        .{ x0, z0 },
        .{ x1, z0 },
        .{ x1, z1 },
        .{ x0, z1 },
    };
    for (&scratch.slices, 0..) |*slice, i| {
        slice.* = scratch.points[i][0..];
    }
    const sector = SectorDef{
        .id = room.id,
        .floor_height = room.floor_height,
        .ceiling_height = room.ceiling_height,
        .polygon = scratch.slices[0..],
        .portals = portals,
    };
    try validateSector(sector);
    return sector;
}

pub fn makePortalOnSectorEdge(
    scratch: *PortalPositionScratch,
    sector: SectorDef,
    edge_index: u32,
    to_sector: u32,
    offset: f32,
    width: f32,
    height: f32,
) !PortalDef {
    try validateSector(sector);
    if (edge_index >= sector.polygon.len) return error.InvalidSectorPortal;
    if (!std.math.isFinite(offset) or offset < 0 or offset > 1) return error.InvalidSectorPortal;
    const a = sector.polygon[@intCast(edge_index)];
    const b = sector.polygon[(@as(usize, @intCast(edge_index)) + 1) % sector.polygon.len];
    scratch.values = .{
        a[0] + (b[0] - a[0]) * offset,
        sector.floor_height,
        a[1] + (b[1] - a[1]) * offset,
    };
    const portal = PortalDef{
        .to_sector = to_sector,
        .position = scratch.values[0..],
        .width = width,
        .height = height,
    };
    try validatePortalForSector(sector, portal);
    return portal;
}

pub fn register(registry: anytype) !void {
    try registry.registerWorldCompilerLayer(.{
        .name = layer_name,
        .affected_cells = affectedCells,
        .compile_cell = compileCell,
    });
}

pub fn start(engine_world: *framework.World) !void {
    try engine_world.notifications.publish("gem.sectors.started", "{}");
}

pub fn stop(engine_world: *framework.World) !void {
    try engine_world.notifications.publish("gem.sectors.stopped", "{}");
}

fn affectedCells(
    _: ?*anyopaque,
    compile_ctx: *const world.compiler.layer.CompileContext,
    allocator: std.mem.Allocator,
) ![]world.cell.CellId {
    var doc = try storage.loadSectorsDoc(allocator, compile_ctx);
    defer doc.deinit();
    var cells = std.ArrayList(world.cell.CellId).empty;
    defer cells.deinit(allocator);
    var lookup = std.AutoHashMap(world.cell.CellId, void).init(allocator);
    defer lookup.deinit();
    for (doc.value.interiors) |interior| {
        const id = try storage.parseCellId(interior.cell);
        if (lookup.contains(id)) continue;
        try lookup.put(id, {});
        try cells.append(allocator, id);
    }
    return cells.toOwnedSlice(allocator);
}

pub fn compileCell(
    _: ?*anyopaque,
    compile_ctx: *const world.compiler.layer.CompileContext,
    id: world.cell.CellId,
    allocator: std.mem.Allocator,
) !world.compiler.layer.CellLayerOutput {
    var doc = try storage.loadSectorsDoc(allocator, compile_ctx);
    defer doc.deinit();

    var meshes = std.ArrayList(world.cell.RenderMesh).empty;
    var collisions = std.ArrayList(world.cell.CollisionPlaceholder).empty;
    var collision_shapes = std.ArrayList(world.cell.CollisionShape).empty;
    var neighbors = std.ArrayList(world.cell.CellId).empty;
    var nav_vertices = std.ArrayList(core.math.Vec3f).empty;
    var nav_indices = std.ArrayList(u32).empty;
    var visibility = std.ArrayList(world.cell.VisibilityLink).empty;
    var blobs = std.ArrayList(world.cell.CellBlob).empty;
    errdefer {
        for (meshes.items) |*mesh| mesh.deinit(allocator);
        meshes.deinit(allocator);
        collisions.deinit(allocator);
        collision_shapes.deinit(allocator);
        neighbors.deinit(allocator);
        nav_vertices.deinit(allocator);
        nav_indices.deinit(allocator);
        visibility.deinit(allocator);
        for (blobs.items) |*blob| blob.deinit(allocator);
        blobs.deinit(allocator);
    }

    var matched = false;
    for (doc.value.interiors) |interior| {
        const interior_cell = try storage.parseCellId(interior.cell);
        if (!interior_cell.eql(id)) continue;
        matched = true;
        const parent = try storage.parseCellId(interior.parent_cell);
        try neighbors.append(allocator, parent);
        try world.compiler.layer.appendBlobJson(allocator, &blobs, "interior.parent", .{
            .cell = .{ id.x, id.y, id.z },
            .parent_cell = .{ parent.x, parent.y, parent.z },
        });

        for (interior.sectors) |sector| {
            try validateSector(sector);
            try buildSectorMeshes(allocator, &meshes, &collisions, &collision_shapes, &nav_vertices, &nav_indices, sector);
            try appendPortalVisibility(allocator, &visibility, id, sector);
        }

        try world.compiler.layer.appendBlobJson(allocator, &blobs, "sector.occlusion", .{
            .cell = .{ id.x, id.y, id.z },
            .sectors = interior.sectors,
        });
        try world.compiler.layer.appendBlobJson(allocator, &blobs, "navmesh.tile", .{
            .cell = .{ id.x, id.y, id.z },
            .floors = interior.sectors,
        });
    }

    if (!matched) return .{};
    return .{
        .render_meshes = try meshes.toOwnedSlice(allocator),
        .collisions = try collisions.toOwnedSlice(allocator),
        .collision_shapes = try collision_shapes.toOwnedSlice(allocator),
        .neighbors = try neighbors.toOwnedSlice(allocator),
        .nav_vertices = try nav_vertices.toOwnedSlice(allocator),
        .nav_indices = try nav_indices.toOwnedSlice(allocator),
        .visibility = try visibility.toOwnedSlice(allocator),
        .blobs = try blobs.toOwnedSlice(allocator),
    };
}

fn buildSectorMeshes(
    allocator: std.mem.Allocator,
    meshes: *std.ArrayList(world.cell.RenderMesh),
    collisions: *std.ArrayList(world.cell.CollisionPlaceholder),
    collision_shapes: *std.ArrayList(world.cell.CollisionShape),
    nav_vertices: *std.ArrayList(core.math.Vec3f),
    nav_indices: *std.ArrayList(u32),
    sector: SectorDef,
) !void {
    const floor_mesh = try buildPolygonMesh(allocator, sector, true);
    try meshes.append(allocator, floor_mesh);
    const ceiling_mesh = try buildPolygonMesh(allocator, sector, false);
    try meshes.append(allocator, ceiling_mesh);
    try buildWallMeshes(allocator, meshes, sector);

    var min_x = std.math.floatMax(f32);
    var max_x = -std.math.floatMax(f32);
    var min_z = std.math.floatMax(f32);
    var max_z = -std.math.floatMax(f32);
    for (sector.polygon) |point| {
        min_x = @min(min_x, point[0]);
        max_x = @max(max_x, point[0]);
        min_z = @min(min_z, point[1]);
        max_z = @max(max_z, point[1]);
    }
    try collisions.append(allocator, .{
        .min = .{ .x = min_x, .y = sector.floor_height, .z = min_z },
        .max = .{ .x = max_x, .y = sector.ceiling_height, .z = max_z },
    });
    try collision_shapes.append(allocator, .{
        .kind = .aabb,
        .min = .{ .x = min_x, .y = sector.floor_height, .z = min_z },
        .max = .{ .x = max_x, .y = sector.ceiling_height, .z = max_z },
    });
    try appendSectorNav(nav_vertices, nav_indices, allocator, sector);
}

fn appendSectorNav(
    nav_vertices: *std.ArrayList(core.math.Vec3f),
    nav_indices: *std.ArrayList(u32),
    allocator: std.mem.Allocator,
    sector: SectorDef,
) !void {
    const base: u32 = @intCast(nav_vertices.items.len);
    for (sector.polygon) |point| {
        try nav_vertices.append(allocator, .{
            .x = point[0],
            .y = sector.floor_height,
            .z = point[1],
        });
    }

    var i: usize = 1;
    while (i + 1 < sector.polygon.len) : (i += 1) {
        try nav_indices.appendSlice(allocator, &.{
            base,
            base + @as(u32, @intCast(i)),
            base + @as(u32, @intCast(i + 1)),
        });
    }
}

fn appendPortalVisibility(
    allocator: std.mem.Allocator,
    visibility: *std.ArrayList(world.cell.VisibilityLink),
    cell_id: world.cell.CellId,
    sector: SectorDef,
) !void {
    for (sector.portals) |portal| {
        const pos = try parsePortalPosition(portal.position);
        const half_w = portal.width * 0.5;
        try visibility.append(allocator, .{
            .target = cell_id,
            .min = .{
                .x = pos.x - half_w,
                .y = pos.y,
                .z = pos.z - 0.1,
            },
            .max = .{
                .x = pos.x + half_w,
                .y = pos.y + portal.height,
                .z = pos.z + 0.1,
            },
        });
    }
}

fn parsePortalPosition(values: []const f32) !core.math.Vec3f {
    if (values.len != 3) return error.InvalidSectorPortal;
    for (values) |value| {
        if (!std.math.isFinite(value)) return error.InvalidSectorPortal;
    }
    return .{ .x = values[0], .y = values[1], .z = values[2] };
}

fn buildPolygonMesh(allocator: std.mem.Allocator, sector: SectorDef, floor: bool) !world.cell.RenderMesh {
    const vert_count = sector.polygon.len;
    const tri_count = vert_count - 2;
    const vertices = try allocator.alloc(world.cell.RenderVertex, vert_count);
    errdefer allocator.free(vertices);
    const indices = try allocator.alloc(u32, tri_count * 3);
    errdefer allocator.free(indices);

    const y = if (floor) sector.floor_height else sector.ceiling_height;
    for (sector.polygon, 0..) |point, i| {
        vertices[i] = .{
            .position = .{ .x = point[0], .y = y, .z = point[1] },
            .normal = if (floor) .{ .x = 0, .y = 1, .z = 0 } else .{ .x = 0, .y = -1, .z = 0 },
            .uv = .{ .x = point[0], .y = point[1] },
        };
    }
    var idx: usize = 0;
    var i: usize = 1;
    while (i + 1 < vert_count) : (i += 1) {
        if (floor) {
            indices[idx + 0] = 0;
            indices[idx + 1] = @intCast(i);
            indices[idx + 2] = @intCast(i + 1);
        } else {
            indices[idx + 0] = 0;
            indices[idx + 1] = @intCast(i + 1);
            indices[idx + 2] = @intCast(i);
        }
        idx += 3;
    }

    const texture = try allocator.alloc(u8, texture_size);
    @memset(texture, if (floor) 120 else 90);
    const name = try allocator.dupe(u8, if (floor) "sector.floor" else "sector.ceiling");
    return .{
        .name = name,
        .vertices = vertices,
        .indices = indices,
        .texture = texture,
        .base_color = if (floor)
            .{ .r = 130, .g = 130, .b = 135, .a = 255 }
        else
            .{ .r = 95, .g = 95, .b = 105, .a = 255 },
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
    };
}

fn buildWallMeshes(
    allocator: std.mem.Allocator,
    meshes: *std.ArrayList(world.cell.RenderMesh),
    sector: SectorDef,
) !void {
    var i: usize = 0;
    while (i < sector.polygon.len) : (i += 1) {
        const a = sector.polygon[i];
        const b = sector.polygon[(i + 1) % sector.polygon.len];
        const verts = try allocator.dupe(world.cell.RenderVertex, &.{
            .{
                .position = .{ .x = a[0], .y = sector.floor_height, .z = a[1] },
                .normal = .{ .x = 0, .y = 0, .z = 1 },
                .uv = .{ .x = 0, .y = 0 },
            },
            .{
                .position = .{ .x = b[0], .y = sector.floor_height, .z = b[1] },
                .normal = .{ .x = 0, .y = 0, .z = 1 },
                .uv = .{ .x = 1, .y = 0 },
            },
            .{
                .position = .{ .x = b[0], .y = sector.ceiling_height, .z = b[1] },
                .normal = .{ .x = 0, .y = 0, .z = 1 },
                .uv = .{ .x = 1, .y = 1 },
            },
            .{
                .position = .{ .x = a[0], .y = sector.ceiling_height, .z = a[1] },
                .normal = .{ .x = 0, .y = 0, .z = 1 },
                .uv = .{ .x = 0, .y = 1 },
            },
        });
        errdefer allocator.free(verts);
        const indices = try allocator.dupe(u32, &.{ 0, 1, 2, 0, 2, 3 });
        errdefer allocator.free(indices);
        const texture = try allocator.alloc(u8, texture_size);
        @memset(texture, 110);
        errdefer allocator.free(texture);
        try meshes.append(allocator, .{
            .name = try allocator.dupe(u8, "sector.wall"),
            .vertices = verts,
            .indices = indices,
            .texture = texture,
            .base_color = .{ .r = 160, .g = 160, .b = 165, .a = 255 },
            .position = .{ .x = 0, .y = 0, .z = 0 },
            .scale = .{ .x = 1, .y = 1, .z = 1 },
        });
    }
}

pub fn validateSector(sector: SectorDef) !void {
    if (sector.polygon.len < 3) return error.InvalidSectorPolygon;
    if (sector.ceiling_height <= sector.floor_height) return error.InvalidSectorHeightRange;
    if (!std.math.isFinite(sector.floor_height) or !std.math.isFinite(sector.ceiling_height)) return error.InvalidSectorHeightRange;
    for (sector.polygon) |point| {
        if (point.len != 2) return error.InvalidSectorPolygon;
        if (!std.math.isFinite(point[0]) or !std.math.isFinite(point[1])) return error.InvalidSectorPolygon;
    }
    for (sector.portals) |portal| {
        try validatePortalForSector(sector, portal);
    }
}

pub fn validatePortal(portal: PortalDef) !void {
    if (portal.position.len != 3) return error.InvalidSectorPortal;
    for (portal.position) |value| {
        if (!std.math.isFinite(value)) return error.InvalidSectorPortal;
    }
    if (!std.math.isFinite(portal.width) or !std.math.isFinite(portal.height)) return error.InvalidSectorPortal;
    if (portal.width <= 0 or portal.height <= 0) return error.InvalidSectorPortal;
}

pub fn validatePortalForSector(sector: SectorDef, portal: PortalDef) !void {
    try validatePortal(portal);
    const pos = try parsePortalPosition(portal.position);
    if (pos.y < sector.floor_height or pos.y + portal.height > sector.ceiling_height) return error.InvalidSectorPortal;
    var edge_index: usize = 0;
    while (edge_index < sector.polygon.len) : (edge_index += 1) {
        const a = sector.polygon[edge_index];
        const b = sector.polygon[(edge_index + 1) % sector.polygon.len];
        if (portalFitsEdge(a, b, pos.x, pos.z, portal.width)) return;
    }
    return error.InvalidSectorPortal;
}

fn validateRoomRect(room: RoomRect) !void {
    if (room.id == 0) return error.InvalidSectorDefinition;
    if (!std.math.isFinite(room.origin[0]) or !std.math.isFinite(room.origin[1])) return error.InvalidSectorDefinition;
    if (!std.math.isFinite(room.size[0]) or !std.math.isFinite(room.size[1])) return error.InvalidSectorDefinition;
    if (room.size[0] <= 0 or room.size[1] <= 0) return error.InvalidSectorDefinition;
    if (!std.math.isFinite(room.floor_height) or !std.math.isFinite(room.ceiling_height)) return error.InvalidSectorHeightRange;
    if (room.ceiling_height <= room.floor_height) return error.InvalidSectorHeightRange;
}

fn portalFitsEdge(a: []const f32, b: []const f32, x: f32, z: f32, width: f32) bool {
    const dx = b[0] - a[0];
    const dz = b[1] - a[1];
    const len_sq = dx * dx + dz * dz;
    if (len_sq <= 0) return false;
    const rel_x = x - a[0];
    const rel_z = z - a[1];
    const cross = rel_x * dz - rel_z * dx;
    if (@abs(cross) > 0.001) return false;
    const dot = rel_x * dx + rel_z * dz;
    if (dot < 0 or dot > len_sq) return false;
    const len = @sqrt(len_sq);
    const along = dot / len;
    const half_width = width * 0.5;
    return along >= half_width and len - along >= half_width;
}

pub fn validateInterior(allocator: std.mem.Allocator, interior: InteriorDef) !void {
    _ = try storage.parseCellId(interior.cell);
    _ = try storage.parseCellId(interior.parent_cell);
    if (interior.sectors.len == 0) return error.InvalidInteriorDefinition;
    var sector_ids = std.AutoHashMap(u32, void).init(allocator);
    defer sector_ids.deinit();
    for (interior.sectors) |sector| {
        if (sector_ids.contains(sector.id)) return error.DuplicateSectorId;
        try sector_ids.put(sector.id, {});
        try validateSector(sector);
    }
    for (interior.sectors) |sector| {
        for (sector.portals) |portal| {
            if (!sector_ids.contains(portal.to_sector)) return error.InvalidSectorPortal;
        }
    }
}

comptime {
    _ = @import("mod_tests.zig");
}
comptime {
    _ = @import("mod_tests.zig");
}
