const std = @import("std");
const core = @import("../core/mod.zig");
const framework = @import("../framework/mod.zig");
const physics_types = @import("physics_types.zig");
const scatter_clusters = @import("scatter_clusters.zig");
const grass_clusters = @import("grass_clusters.zig");

pub const ScenePhysicsBody = physics_types.ScenePhysicsBody;

pub const SceneColor = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

pub const SceneTransform = struct {
    position: core.math.Vec3f,
    scale: core.math.Vec3f,
};

pub const SceneDrawable = struct {
    mesh_index: u32,
    mesh_asset: core.AssetId,
    material_asset: core.AssetId,
};

pub const StoredVertex = struct {
    position: core.math.Vec3f,
    normal: core.math.Vec3f,
    uv: core.math.Vec2f,
};

pub const StoredMesh = struct {
    vertices: []StoredVertex,
    indices: []u32,
    texture: []u8,
    base_color: SceneColor,
    source_kind: MeshSourceKind = .generic,

    pub fn init(allocator: std.mem.Allocator, desc: ObjectDesc) !StoredMesh {
        const vertices = try allocator.alloc(StoredVertex, desc.vertices.len);
        errdefer allocator.free(vertices);
        @memcpy(vertices, desc.vertices);

        const indices = try allocator.dupe(u32, desc.indices);
        errdefer allocator.free(indices);

        const texture = try allocator.dupe(u8, desc.texture);
        errdefer allocator.free(texture);

        return .{
            .vertices = vertices,
            .indices = indices,
            .texture = texture,
            .base_color = desc.base_color,
            .source_kind = desc.source_kind,
        };
    }

    pub fn deinit(self: *StoredMesh, allocator: std.mem.Allocator) void {
        allocator.free(self.vertices);
        allocator.free(self.indices);
        allocator.free(self.texture);
        self.vertices = &.{};
        self.indices = &.{};
        self.texture = &.{};
    }
};

pub const MeshSourceKind = enum {
    generic,
    terrain,
    water,
    internal,
};

pub const ObjectDesc = struct {
    position: core.math.Vec3f,
    scale: core.math.Vec3f,
    vertices: []const StoredVertex,
    indices: []const u32,
    texture: []const u8,
    base_color: SceneColor,
    source_kind: MeshSourceKind = .generic,
    physics: ?ScenePhysicsBody = null,
};

pub const SceneSpawnState = struct {
    allocator: std.mem.Allocator,
    transforms: framework.ecs.ComponentStorage(SceneTransform),
    drawables: framework.ecs.ComponentStorage(SceneDrawable),
    physics_bodies: framework.ecs.ComponentStorage(ScenePhysicsBody),
    entities: std.ArrayList(framework.ecs.Entity),
    meshes: std.ArrayList(StoredMesh),
    draw_batches: std.ArrayList(DrawBatch),
    grass_batches: std.ArrayList(GrassBatch),

    pub const DrawBatch = struct {
        mesh_index: u32,
        position: core.math.Vec3f,
        scale: core.math.Vec3f,
        scatter_cull: ?scatter_clusters.ScatterCull = null,
    };

    pub const GrassBatch = struct {
        center: core.math.Vec3f,
        instances: []grass_clusters.Instance,
        meta: grass_clusters.ClusterMeta,
        cull: grass_clusters.GrassCull,

        pub fn deinit(self: *GrassBatch, allocator: std.mem.Allocator) void {
            for (self.instances) |instance| allocator.free(instance.material);
            allocator.free(self.instances);
            self.instances = &.{};
        }
    };

    pub fn init(allocator: std.mem.Allocator) SceneSpawnState {
        return .{
            .allocator = allocator,
            .transforms = framework.ecs.ComponentStorage(SceneTransform).init(allocator),
            .drawables = framework.ecs.ComponentStorage(SceneDrawable).init(allocator),
            .physics_bodies = framework.ecs.ComponentStorage(ScenePhysicsBody).init(allocator),
            .entities = .empty,
            .meshes = .empty,
            .draw_batches = .empty,
            .grass_batches = .empty,
        };
    }

    pub fn deinit(self: *SceneSpawnState) void {
        for (self.meshes.items) |*mesh| mesh.deinit(self.allocator);
        self.meshes.deinit(self.allocator);
        self.entities.deinit(self.allocator);
        for (self.grass_batches.items) |*batch| batch.deinit(self.allocator);
        self.grass_batches.deinit(self.allocator);
        self.draw_batches.deinit(self.allocator);
        self.physics_bodies.deinit();
        self.drawables.deinit();
        self.transforms.deinit();
    }

    pub fn deinitPhysicsBody(self: *SceneSpawnState, entity: framework.ecs.Entity) void {
        if (self.physics_bodies.getPtr(entity)) |physics_body| {
            physics_body.deinit(self.allocator);
        }
        _ = self.physics_bodies.remove(entity);
    }

    pub fn clearEntities(self: *SceneSpawnState, world: *framework.World) void {
        for (self.entities.items) |entity| {
            self.deinitPhysicsBody(entity);
            _ = world.destroyEntity(entity);
            _ = self.transforms.remove(entity);
            _ = self.drawables.remove(entity);
        }
        self.entities.clearRetainingCapacity();
    }

    pub fn reset(self: *SceneSpawnState, world: *framework.World) void {
        self.clearEntities(world);
        for (self.meshes.items) |*mesh| mesh.deinit(self.allocator);
        self.meshes.clearRetainingCapacity();
        for (self.grass_batches.items) |*batch| batch.deinit(self.allocator);
        self.grass_batches.clearRetainingCapacity();
        self.draw_batches.clearRetainingCapacity();
    }

    pub fn spawnObject(self: *SceneSpawnState, world: *framework.World, desc: ObjectDesc) !framework.ecs.Entity {
        const mesh_index = try self.appendMesh(world, desc);
        const mesh_asset = meshAssetId(mesh_index);
        const material_asset = materialAssetId(mesh_index);

        const entity = world.spawnEntity();
        try self.transforms.set(entity, .{
            .position = desc.position,
            .scale = desc.scale,
        });
        try self.drawables.set(entity, .{
            .mesh_index = mesh_index,
            .mesh_asset = mesh_asset,
            .material_asset = material_asset,
        });
        if (desc.physics) |physics_body| {
            try self.physics_bodies.set(entity, physics_body);
        }
        try self.entities.append(self.allocator, entity);
        return entity;
    }

    pub fn appendMesh(self: *SceneSpawnState, world: *framework.World, desc: ObjectDesc) !u32 {
        const mesh_index: u32 = @intCast(self.meshes.items.len);
        try self.meshes.append(self.allocator, try StoredMesh.init(self.allocator, desc));
        errdefer {
            var mesh = self.meshes.pop().?;
            mesh.deinit(self.allocator);
        }

        var mesh_path_buf: [64]u8 = undefined;
        const mesh_path = meshAssetPath(&mesh_path_buf, mesh_index);
        var material_path_buf: [64]u8 = undefined;
        const material_path = materialAssetPath(&material_path_buf, mesh_index);

        _ = try world.assets.register("mesh", mesh_path);
        _ = try world.assets.register("material", material_path);
        return mesh_index;
    }

    pub fn spawnPhysicsBody(
        self: *SceneSpawnState,
        world: *framework.World,
        transform: SceneTransform,
        physics_body: ScenePhysicsBody,
    ) !framework.ecs.Entity {
        const entity = world.spawnEntity();
        try self.transforms.set(entity, transform);
        try self.physics_bodies.set(entity, physics_body);
        try self.entities.append(self.allocator, entity);
        return entity;
    }

    pub fn spawnDefault(self: *SceneSpawnState, world: *framework.World) !void {
        const box_verts = [_]StoredVertex{
            .{ .position = .{ .x = -0.5, .y = 0, .z = -0.5 }, .normal = .{ .x = 0, .y = 0, .z = -1 }, .uv = .{ .x = 0, .y = 0 } },
            .{ .position = .{ .x = 0.5, .y = 0, .z = -0.5 }, .normal = .{ .x = 0, .y = 0, .z = -1 }, .uv = .{ .x = 1, .y = 0 } },
            .{ .position = .{ .x = 0.5, .y = 1, .z = -0.5 }, .normal = .{ .x = 0, .y = 0, .z = -1 }, .uv = .{ .x = 1, .y = 1 } },
            .{ .position = .{ .x = -0.5, .y = 1, .z = -0.5 }, .normal = .{ .x = 0, .y = 0, .z = -1 }, .uv = .{ .x = 0, .y = 1 } },
            .{ .position = .{ .x = -0.5, .y = 0, .z = 0.5 }, .normal = .{ .x = 0, .y = 0, .z = 1 }, .uv = .{ .x = 0, .y = 0 } },
            .{ .position = .{ .x = 0.5, .y = 0, .z = 0.5 }, .normal = .{ .x = 0, .y = 0, .z = 1 }, .uv = .{ .x = 1, .y = 0 } },
            .{ .position = .{ .x = 0.5, .y = 1, .z = 0.5 }, .normal = .{ .x = 0, .y = 0, .z = 1 }, .uv = .{ .x = 1, .y = 1 } },
            .{ .position = .{ .x = -0.5, .y = 1, .z = 0.5 }, .normal = .{ .x = 0, .y = 0, .z = 1 }, .uv = .{ .x = 0, .y = 1 } },
        };
        const box_indices = [_]u32{ 0, 1, 2, 0, 2, 3, 4, 6, 5, 4, 7, 6, 0, 4, 5, 0, 5, 1, 1, 5, 6, 1, 6, 2, 2, 6, 7, 2, 7, 3, 3, 7, 4, 3, 4, 0 };
        const tex = try self.allocator.alloc(u8, 128 * 128 * 4);
        defer self.allocator.free(tex);
        @memset(tex, 170);

        _ = try self.spawnObject(world, .{
            .position = .{ .x = 0, .y = 0.5, .z = 0 },
            .scale = .{ .x = 1, .y = 1, .z = 1 },
            .vertices = &box_verts,
            .indices = &box_indices,
            .texture = tex,
            .base_color = .{ .r = 170, .g = 180, .b = 195, .a = 255 },
            .physics = ScenePhysicsBody.dynamicAabb(.{ .x = 1, .y = 1, .z = 1 }),
        });
    }

    pub fn addGrassBatch(
        self: *SceneSpawnState,
        center: core.math.Vec3f,
        instances: []grass_clusters.Instance,
        meta: grass_clusters.ClusterMeta,
    ) !void {
        errdefer {
            for (instances) |instance| self.allocator.free(instance.material);
            self.allocator.free(instances);
        }
        try self.grass_batches.append(self.allocator, .{
            .center = center,
            .instances = instances,
            .meta = meta,
            .cull = grass_clusters.cullDistances(meta),
        });
    }

    pub fn addDrawBatch(
        self: *SceneSpawnState,
        mesh_index: u32,
        position: core.math.Vec3f,
        scale: core.math.Vec3f,
        scatter_cull: ?scatter_clusters.ScatterCull,
    ) !void {
        try self.draw_batches.append(self.allocator, .{
            .mesh_index = mesh_index,
            .position = position,
            .scale = scale,
            .scatter_cull = scatter_cull,
        });
    }
};

pub fn objectTransformMatrix(transform: SceneTransform) [16]f32 {
    const t = translationMatrix(transform.position);
    const s = scaleMatrix(transform.scale);
    return multiplyMatrix(t, s);
}

fn meshAssetId(index: u32) core.AssetId {
    return @as(core.AssetId, @intCast(index)) + 1;
}

fn materialAssetId(index: u32) core.AssetId {
    return @as(core.AssetId, @intCast(index)) + 0x1_0000_0000;
}

fn meshAssetPath(buf: []u8, index: u32) []const u8 {
    return std.fmt.bufPrint(buf, "scene/mesh/{d}", .{index}) catch unreachable;
}

fn materialAssetPath(buf: []u8, index: u32) []const u8 {
    return std.fmt.bufPrint(buf, "scene/material/{d}", .{index}) catch unreachable;
}

fn translationMatrix(v: core.math.Vec3f) [16]f32 {
    return .{
        1,   0,   0,   0,
        0,   1,   0,   0,
        0,   0,   1,   0,
        v.x, v.y, v.z, 1,
    };
}

fn scaleMatrix(v: core.math.Vec3f) [16]f32 {
    return .{
        v.x, 0,   0,   0,
        0,   v.y, 0,   0,
        0,   0,   v.z, 0,
        0,   0,   0,   1,
    };
}

fn multiplyMatrix(a: [16]f32, b: [16]f32) [16]f32 {
    var out: [16]f32 = undefined;
    for (0..4) |col| {
        for (0..4) |row| {
            var sum: f32 = 0;
            for (0..4) |k| {
                sum += a[k * 4 + row] * b[col * 4 + k];
            }
            out[col * 4 + row] = sum;
        }
    }
    return out;
}

test "scene spawn creates entities with components" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();

    var state = SceneSpawnState.init(std.testing.allocator);
    defer state.deinit();

    try state.spawnDefault(&world);
    try std.testing.expectEqual(@as(usize, 1), state.entities.items.len);
    try std.testing.expectEqual(@as(usize, 1), world.ecs_world.entityCount());

    const entity = state.entities.items[0];
    const transform = state.transforms.get(entity).?;
    try std.testing.expectEqual(@as(f32, 0.5), transform.position.y);

    const drawable = state.drawables.get(entity).?;
    try std.testing.expectEqual(@as(u32, 0), drawable.mesh_index);
    try std.testing.expect(state.physics_bodies.get(entity) != null);
    try std.testing.expectEqual(@as(usize, 2), world.assets.count());
    try state.addDrawBatch(0, .{ .x = 2, .y = 0, .z = 0 }, .{ .x = 1, .y = 1, .z = 1 }, null);
    try std.testing.expectEqual(@as(usize, 1), state.draw_batches.items.len);
    try std.testing.expectEqual(@as(usize, 0), state.grass_batches.items.len);
}
