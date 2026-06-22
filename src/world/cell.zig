const std = @import("std");
const core = @import("../core/mod.zig");

pub const default_cell_size_m: f32 = 256.0;
pub const default_cell_height_m: f32 = 256.0;

pub const CellId = struct {
    x: i32,
    y: i32,
    z: i32 = 0,

    pub fn eql(a: CellId, b: CellId) bool {
        return a.x == b.x and a.y == b.y and a.z == b.z;
    }
};

pub fn idAtPosition(x: f32, z: f32, y: f32, cell_size_m: f32, cell_height_m: f32, vertical: bool) CellId {
    return .{
        .x = coordForPosition(x, cell_size_m),
        .y = coordForPosition(z, cell_size_m),
        .z = if (vertical) coordForPosition(y, cell_height_m) else 0,
    };
}

fn coordForPosition(value: f32, cell_size_m: f32) i32 {
    return @intFromFloat(@floor(value / cell_size_m));
}

pub const CellBounds = struct {
    min: core.math.Vec3f,
    max: core.math.Vec3f,
};

pub fn boundsForCell(id: CellId, cell_size_m: f32, cell_height_m: f32) CellBounds {
    const min_x = @as(f32, @floatFromInt(id.x)) * cell_size_m;
    const min_z = @as(f32, @floatFromInt(id.y)) * cell_size_m;
    return .{
        .min = .{ .x = min_x, .y = 0, .z = min_z },
        .max = .{
            .x = min_x + cell_size_m,
            .y = cell_height_m,
            .z = min_z + cell_size_m,
        },
    };
}

pub const CellColor = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

pub const RenderVertex = struct {
    position: core.math.Vec3f,
    normal: core.math.Vec3f,
    uv: core.math.Vec2f,
};

pub const RenderMesh = struct {
    name: []u8,
    vertices: []RenderVertex,
    indices: []u32,
    texture: []u8,
    base_color: CellColor,
    position: core.math.Vec3f,
    scale: core.math.Vec3f,

    pub fn deinit(self: *RenderMesh, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.vertices);
        allocator.free(self.indices);
        allocator.free(self.texture);
    }
};

pub const CollisionPlaceholder = struct {
    min: core.math.Vec3f,
    max: core.math.Vec3f,
};

pub const CollisionShapeKind = enum(u8) {
    aabb = 1,
    sphere = 2,
    heightfield = 3,
};

pub const CollisionShape = struct {
    kind: CollisionShapeKind,
    min: core.math.Vec3f = .{ .x = 0, .y = 0, .z = 0 },
    max: core.math.Vec3f = .{ .x = 0, .y = 0, .z = 0 },
    center: core.math.Vec3f = .{ .x = 0, .y = 0, .z = 0 },
    radius: f32 = 0,
};

pub const InstanceRecord = struct {
    mesh_index: u32,
    position: core.math.Vec3f,
    scale: core.math.Vec3f,
};

pub const PropInstanceRecord = struct {
    instance_id: u64,
    prop_asset_id: []u8,
    variant: u32 = 0,
    position: core.math.Vec3f,
    rotation: core.math.Vec3f = .{ .x = 0, .y = 0, .z = 0 },
    scale: core.math.Vec3f,
    base_color: CellColor,
    interactable: bool = false,

    pub fn deinit(self: *PropInstanceRecord, allocator: std.mem.Allocator) void {
        allocator.free(self.prop_asset_id);
        self.prop_asset_id = "";
    }
};

pub const LightProbeMeta = struct {
    position: core.math.Vec3f,
    intensity: f32,
};

pub const CellBlob = struct {
    kind: []u8,
    payload: []u8,

    pub fn deinit(self: *CellBlob, allocator: std.mem.Allocator) void {
        allocator.free(self.kind);
        allocator.free(self.payload);
    }
};

pub const VisibilityLink = struct {
    target: CellId,
    min: core.math.Vec3f,
    max: core.math.Vec3f,
};

pub const CellDependency = struct {
    kind: []u8,
    path: []u8,

    pub fn deinit(self: *CellDependency, allocator: std.mem.Allocator) void {
        allocator.free(self.kind);
        allocator.free(self.path);
    }
};

pub const WorldCellData = struct {
    id: CellId,
    cell_size_m: f32 = default_cell_size_m,
    render_meshes: []RenderMesh,
    collisions: []CollisionPlaceholder,
    collision_shapes: []CollisionShape = &.{},
    instances: []InstanceRecord,
    light_probes: []LightProbeMeta,
    neighbors: []CellId,
    nav_vertices: []core.math.Vec3f = &.{},
    nav_indices: []u32 = &.{},
    visibility: []VisibilityLink = &.{},
    dependencies: []CellDependency = &.{},
    prop_instances: []PropInstanceRecord = &.{},
    blobs: []CellBlob = &.{},

    pub fn deinit(self: *WorldCellData, allocator: std.mem.Allocator) void {
        for (self.render_meshes) |*mesh| mesh.deinit(allocator);
        for (self.dependencies) |*dependency| dependency.deinit(allocator);
        for (self.prop_instances) |*instance| instance.deinit(allocator);
        for (self.blobs) |*blob| blob.deinit(allocator);
        if (self.render_meshes.len > 0) allocator.free(self.render_meshes);
        if (self.collisions.len > 0) allocator.free(self.collisions);
        if (self.collision_shapes.len > 0) allocator.free(self.collision_shapes);
        if (self.instances.len > 0) allocator.free(self.instances);
        if (self.light_probes.len > 0) allocator.free(self.light_probes);
        if (self.neighbors.len > 0) allocator.free(self.neighbors);
        if (self.nav_vertices.len > 0) allocator.free(self.nav_vertices);
        if (self.nav_indices.len > 0) allocator.free(self.nav_indices);
        if (self.visibility.len > 0) allocator.free(self.visibility);
        if (self.dependencies.len > 0) allocator.free(self.dependencies);
        if (self.prop_instances.len > 0) allocator.free(self.prop_instances);
        if (self.blobs.len > 0) allocator.free(self.blobs);
    }
};

test "cell bounds map to world space" {
    const bounds = boundsForCell(.{ .x = 2, .y = -1, .z = 0 }, 256.0, 128.0);
    try std.testing.expectEqual(@as(f32, 512), bounds.min.x);
    try std.testing.expectEqual(@as(f32, -256), bounds.min.z);
    try std.testing.expectEqual(@as(f32, 768), bounds.max.x);
    try std.testing.expectEqual(@as(f32, 0), bounds.min.y);
    try std.testing.expectEqual(@as(f32, 128), bounds.max.y);
}
