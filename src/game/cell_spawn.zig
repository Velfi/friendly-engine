const std = @import("std");
const core = @import("../core/mod.zig");
const framework = @import("../framework/mod.zig");
const world_mod = @import("../world/mod.zig");
const game_physics = @import("physics.zig");
const scene_spawn = @import("scene_spawn.zig");
const physics_types = @import("physics_types.zig");
const prop_asset_cache = @import("prop_asset_cache.zig");

const cell_collision = @import("cell_collision.zig");
const helpers = @import("cell_spawn_helpers.zig");
pub const CellSpawnState = struct {
    allocator: std.mem.Allocator,
    scene_state: scene_spawn.SceneSpawnState,
    active_cells: std.ArrayList(world_mod.cell.CellId),
    nav_vertices: std.ArrayList(core.math.Vec3f),
    nav_indices: std.ArrayList(u32),
    visibility_links: std.ArrayList(world_mod.cell.VisibilityLink),
    dependencies: std.ArrayList(world_mod.cell.CellDependency),
    light_probes: std.ArrayList(world_mod.cell.LightProbeMeta),
    neighbor_links: std.ArrayList(world_mod.cell.CellId),
    prop_cache: prop_asset_cache.PropAssetCache,
    spawned_cells: std.AutoHashMap(world_mod.cell.CellId, SpawnedCell),
    collision_placeholder_count: usize = 0,
    collision_shape_count: usize = 0,
    instance_count: usize = 0,
    light_probe_count: usize = 0,
    neighbor_link_count: usize = 0,
    nav_triangle_count: usize = 0,
    visibility_link_count: usize = 0,
    dependency_count: usize = 0,
    scatter_cluster_count: usize = 0,
    grass_cluster_count: usize = 0,
    prop_instance_count: usize = 0,
    prop_asset_count: usize = 0,
    culled_cells: usize = 0,
    visible_mesh_count: usize = 0,

    const SpawnedCell = struct {
        entities: []framework.ecs.Entity,
        draw_batch_start: usize,
        draw_batch_count: usize,
        collision_placeholder_count: usize,
        collision_shape_count: usize,
        instance_count: usize,
        light_probe_start: usize,
        light_probe_count: usize,
        neighbor_link_start: usize,
        neighbor_link_count: usize,
        nav_vertex_start: usize,
        nav_vertex_count: usize,
        nav_index_start: usize,
        nav_index_count: usize,
        visibility_link_start: usize,
        visibility_link_count: usize,
        dependency_start: usize,
        dependency_count: usize,
        scatter_cluster_count: usize,
        grass_batch_start: usize,
        grass_batch_count: usize,
        grass_cluster_count: usize,
        prop_asset_ids: [][]u8,
        prop_instance_count: usize,

        fn deinit(self: *SpawnedCell, allocator: std.mem.Allocator) void {
            allocator.free(self.entities);
            self.entities = &.{};
            for (self.prop_asset_ids) |asset_id| allocator.free(asset_id);
            allocator.free(self.prop_asset_ids);
            self.prop_asset_ids = &.{};
        }
    };

    pub fn init(allocator: std.mem.Allocator) CellSpawnState {
        return .{
            .allocator = allocator,
            .scene_state = scene_spawn.SceneSpawnState.init(allocator),
            .active_cells = .empty,
            .nav_vertices = .empty,
            .nav_indices = .empty,
            .visibility_links = .empty,
            .dependencies = .empty,
            .light_probes = .empty,
            .neighbor_links = .empty,
            .prop_cache = prop_asset_cache.PropAssetCache.init(allocator),
            .spawned_cells = std.AutoHashMap(world_mod.cell.CellId, SpawnedCell).init(allocator),
        };
    }

    pub fn initWithProject(allocator: std.mem.Allocator, io: std.Io, project_path: []const u8) !CellSpawnState {
        var state = init(allocator);
        errdefer state.deinit();
        state.prop_cache.deinit();
        state.prop_cache = try prop_asset_cache.PropAssetCache.initWithProject(allocator, io, project_path);
        return state;
    }

    pub fn deinit(self: *CellSpawnState) void {
        var iter = self.spawned_cells.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.spawned_cells.deinit();
        for (self.dependencies.items) |*dependency| dependency.deinit(self.allocator);
        self.dependencies.deinit(self.allocator);
        self.visibility_links.deinit(self.allocator);
        self.nav_indices.deinit(self.allocator);
        self.nav_vertices.deinit(self.allocator);
        self.light_probes.deinit(self.allocator);
        self.neighbor_links.deinit(self.allocator);
        self.prop_cache.deinit();
        self.scene_state.deinit();
        self.active_cells.deinit(self.allocator);
    }

    pub fn syncFromStream(
        self: *CellSpawnState,
        world: *framework.World,
        manager: *world_mod.stream.StreamManager,
    ) !void {
        var cells = std.ArrayList(*const world_mod.cell.WorldCellData).empty;
        defer cells.deinit(self.allocator);

        var iter = manager.active_cells.iterator();
        while (iter.next()) |entry| {
            try cells.append(self.allocator, entry.value_ptr);
        }

        try self.syncFromActiveCells(world, cells.items);
    }

    pub fn reloadFromStream(
        self: *CellSpawnState,
        world: *framework.World,
        manager: *world_mod.stream.StreamManager,
    ) !void {
        var iter = manager.active_cells.iterator();
        while (iter.next()) |entry| {
            try self.reloadActiveCell(world, entry.value_ptr);
        }
    }

    pub fn syncFromActiveCells(
        self: *CellSpawnState,
        world: *framework.World,
        cells: []const *const world_mod.cell.WorldCellData,
    ) !void {
        var desired = std.AutoHashMap(world_mod.cell.CellId, *const world_mod.cell.WorldCellData).init(self.allocator);
        defer desired.deinit();

        for (cells) |world_cell| {
            try desired.put(world_cell.id, world_cell);
        }

        var remove_ids = std.ArrayList(world_mod.cell.CellId).empty;
        defer remove_ids.deinit(self.allocator);
        var spawned_iter = self.spawned_cells.iterator();
        while (spawned_iter.next()) |entry| {
            if (!desired.contains(entry.key_ptr.*)) {
                try remove_ids.append(self.allocator, entry.key_ptr.*);
            }
        }

        for (remove_ids.items) |id| {
            try self.unloadCell(world, id);
        }

        for (cells) |world_cell| {
            if (self.spawned_cells.contains(world_cell.id)) continue;
            try self.loadCell(world, world_cell);
        }

        try self.rebuildActiveSummary();
    }

    pub fn reloadActiveCell(
        self: *CellSpawnState,
        world: *framework.World,
        world_cell: *const world_mod.cell.WorldCellData,
    ) !void {
        if (self.spawned_cells.contains(world_cell.id)) {
            try self.unloadCell(world, world_cell.id);
        }
        try self.loadCell(world, world_cell);
        try self.rebuildActiveSummary();
    }

    fn loadCell(
        self: *CellSpawnState,
        world: *framework.World,
        world_cell: *const world_mod.cell.WorldCellData,
    ) !void {
        const entity_start = self.scene_state.entities.items.len;
        const draw_batch_start = self.scene_state.draw_batches.items.len;
        const grass_batch_start = self.scene_state.grass_batches.items.len;
        const light_probe_start = self.light_probes.items.len;
        const neighbor_link_start = self.neighbor_links.items.len;
        const nav_vertex_start = self.nav_vertices.items.len;
        const nav_index_start = self.nav_indices.items.len;
        const visibility_link_start = self.visibility_links.items.len;
        const dependency_start = self.dependencies.items.len;
        var metadata_committed = false;
        errdefer {
            if (!metadata_committed) {
                self.truncateMetadata(
                    light_probe_start,
                    neighbor_link_start,
                    nav_vertex_start,
                    nav_index_start,
                    visibility_link_start,
                    dependency_start,
                );
            }
        }

        try helpers.validateCellMetadata(world_cell);

        var mesh_lookup = std.StringHashMap(u32).init(self.allocator);
        defer mesh_lookup.deinit();

        for (world_cell.render_meshes) |mesh| {
            const verts = try self.allocator.alloc(scene_spawn.StoredVertex, mesh.vertices.len);
            defer self.allocator.free(verts);
            for (mesh.vertices, 0..) |src, i| {
                verts[i] = .{
                    .position = src.position,
                    .normal = src.normal,
                    .uv = src.uv,
                };
            }

            const entity = try self.scene_state.spawnObject(world, .{
                .position = mesh.position,
                .scale = mesh.scale,
                .vertices = verts,
                .indices = mesh.indices,
                .texture = mesh.texture,
                .base_color = .{
                    .r = mesh.base_color.r,
                    .g = mesh.base_color.g,
                    .b = mesh.base_color.b,
                    .a = mesh.base_color.a,
                },
                .source_kind = meshSourceKind(mesh.name),
            });
            const drawable = self.scene_state.drawables.get(entity) orelse return error.MissingSceneDrawable;
            try mesh_lookup.put(mesh.name, drawable.mesh_index);
        }

        const collision_shape_count = try cell_collision.spawnCollisionShapes(
            &self.scene_state,
            world,
            world_cell.collision_shapes,
            world_cell.blobs,
        );

        const scatter_cluster_count = try helpers.appendScatterDrawBatches(self, world_cell, &mesh_lookup);
        const grass_cluster_count = try helpers.appendGrassBatches(self, world_cell);
        const prop_asset_ids = try self.appendPropDrawBatches(world, world_cell);
        errdefer {
            for (prop_asset_ids) |asset_id| {
                self.prop_cache.releaseMesh(asset_id) catch {};
                self.allocator.free(asset_id);
            }
            self.allocator.free(prop_asset_ids);
        }
        try self.appendCellMetadata(world_cell);

        const entities = try self.allocator.dupe(framework.ecs.Entity, self.scene_state.entities.items[entity_start..]);
        errdefer self.allocator.free(entities);

        try self.spawned_cells.put(world_cell.id, .{
            .entities = entities,
            .draw_batch_start = draw_batch_start,
            .draw_batch_count = self.scene_state.draw_batches.items.len - draw_batch_start,
            .collision_placeholder_count = world_cell.collisions.len,
            .collision_shape_count = collision_shape_count,
            .instance_count = world_cell.instances.len,
            .light_probe_start = light_probe_start,
            .light_probe_count = world_cell.light_probes.len,
            .neighbor_link_start = neighbor_link_start,
            .neighbor_link_count = world_cell.neighbors.len,
            .nav_vertex_start = nav_vertex_start,
            .nav_vertex_count = world_cell.nav_vertices.len,
            .nav_index_start = nav_index_start,
            .nav_index_count = world_cell.nav_indices.len,
            .visibility_link_start = visibility_link_start,
            .visibility_link_count = world_cell.visibility.len,
            .dependency_start = dependency_start,
            .dependency_count = world_cell.dependencies.len,
            .scatter_cluster_count = scatter_cluster_count,
            .grass_batch_start = grass_batch_start,
            .grass_batch_count = self.scene_state.grass_batches.items.len - grass_batch_start,
            .grass_cluster_count = grass_cluster_count,
            .prop_asset_ids = prop_asset_ids,
            .prop_instance_count = world_cell.prop_instances.len,
        });
        metadata_committed = true;
    }

    fn unloadCell(self: *CellSpawnState, world: *framework.World, id: world_mod.cell.CellId) !void {
        var removed = self.spawned_cells.fetchRemove(id) orelse return;
        defer removed.value.deinit(self.allocator);

        for (removed.value.entities) |entity| {
            self.scene_state.deinitPhysicsBody(entity);
            _ = world.destroyEntity(entity);
            _ = self.scene_state.transforms.remove(entity);
            _ = self.scene_state.drawables.remove(entity);
            helpers.removeEntityId(&self.scene_state.entities, entity);
        }

        if (removed.value.grass_batch_count > 0) {
            const start = removed.value.grass_batch_start;
            const end = start + removed.value.grass_batch_count;
            if (end > self.scene_state.grass_batches.items.len) return error.InvalidCellGrassBatchRange;
            for (self.scene_state.grass_batches.items[start..end]) |*batch| batch.deinit(self.allocator);
            self.scene_state.grass_batches.replaceRangeAssumeCapacity(start, removed.value.grass_batch_count, &.{});
            var grass_iter = self.spawned_cells.iterator();
            while (grass_iter.next()) |entry| {
                if (entry.value_ptr.grass_batch_start > start) entry.value_ptr.grass_batch_start -= removed.value.grass_batch_count;
            }
        }

        if (removed.value.draw_batch_count > 0) {
            const start = removed.value.draw_batch_start;
            const end = start + removed.value.draw_batch_count;
            if (end > self.scene_state.draw_batches.items.len) return error.InvalidCellDrawBatchRange;
            self.scene_state.draw_batches.replaceRangeAssumeCapacity(start, removed.value.draw_batch_count, &.{});

            var iter = self.spawned_cells.iterator();
            while (iter.next()) |entry| {
                if (entry.value_ptr.draw_batch_start > start) {
                    entry.value_ptr.draw_batch_start -= removed.value.draw_batch_count;
                }
            }
        }

        for (removed.value.prop_asset_ids) |asset_id| {
            try self.prop_cache.releaseMesh(asset_id);
        }

        try self.removeLightProbes(removed.value.light_probe_start, removed.value.light_probe_count);
        try self.removeNeighborLinks(removed.value.neighbor_link_start, removed.value.neighbor_link_count);
        try self.removeNavVertices(removed.value.nav_vertex_start, removed.value.nav_vertex_count);
        try self.removeNavIndices(removed.value.nav_index_start, removed.value.nav_index_count);
        try self.removeVisibilityLinks(removed.value.visibility_link_start, removed.value.visibility_link_count);
        try self.removeDependencies(removed.value.dependency_start, removed.value.dependency_count);
    }

    fn rebuildActiveSummary(self: *CellSpawnState) !void {
        self.active_cells.clearRetainingCapacity();
        self.collision_placeholder_count = 0;
        self.collision_shape_count = 0;
        self.instance_count = 0;
        self.prop_instance_count = 0;

        var iter = self.spawned_cells.iterator();
        while (iter.next()) |entry| {
            try self.active_cells.append(self.allocator, entry.key_ptr.*);
            self.collision_placeholder_count += entry.value_ptr.collision_placeholder_count;
            self.collision_shape_count += entry.value_ptr.collision_shape_count;
            self.instance_count += entry.value_ptr.instance_count;
            self.prop_instance_count += entry.value_ptr.prop_instance_count;
        }
        self.prop_asset_count = self.prop_cache.activeAssetCount();
        self.light_probe_count = self.light_probes.items.len;
        self.neighbor_link_count = self.neighbor_links.items.len;
        self.nav_triangle_count = self.nav_indices.items.len / 3;
        self.visibility_link_count = self.visibility_links.items.len;
        self.dependency_count = self.dependencies.items.len;
        self.scatter_cluster_count = 0;
        self.grass_cluster_count = 0;
        var scatter_iter = self.spawned_cells.iterator();
        while (scatter_iter.next()) |entry| {
            self.scatter_cluster_count += entry.value_ptr.scatter_cluster_count;
            self.grass_cluster_count += entry.value_ptr.grass_cluster_count;
        }
        var visible: usize = 0;
        var mesh_iter = self.spawned_cells.iterator();
        while (mesh_iter.next()) |entry| visible += entry.value_ptr.draw_batch_count;
        self.visible_mesh_count = visible;
        self.culled_cells = 0;
    }

    fn appendCellMetadata(self: *CellSpawnState, world_cell: *const world_mod.cell.WorldCellData) !void {
        try self.light_probes.appendSlice(self.allocator, world_cell.light_probes);
        try self.neighbor_links.appendSlice(self.allocator, world_cell.neighbors);
        try self.nav_vertices.appendSlice(self.allocator, world_cell.nav_vertices);
        try helpers.appendOffsetNavIndices(self.allocator, &self.nav_indices, world_cell.nav_indices, self.nav_vertices.items.len - world_cell.nav_vertices.len);
        try self.visibility_links.appendSlice(self.allocator, world_cell.visibility);
        try helpers.appendDependencies(self.allocator, &self.dependencies, world_cell.dependencies);
    }

    fn appendPropDrawBatches(
        self: *CellSpawnState,
        world: *framework.World,
        world_cell: *const world_mod.cell.WorldCellData,
    ) ![][]u8 {
        const prop_asset_ids = try self.allocator.alloc([]u8, world_cell.prop_instances.len);
        var retained_count: usize = 0;
        errdefer {
            for (prop_asset_ids[0..retained_count]) |asset_id| {
                self.prop_cache.releaseMesh(asset_id) catch {};
                self.allocator.free(asset_id);
            }
            self.allocator.free(prop_asset_ids);
        }

        for (world_cell.prop_instances) |instance| {
            const base_color: scene_spawn.SceneColor = .{
                .r = instance.base_color.r,
                .g = instance.base_color.g,
                .b = instance.base_color.b,
                .a = instance.base_color.a,
            };
            const owned_id = try self.allocator.dupe(u8, instance.prop_asset_id);
            const mesh_index = self.prop_cache.retainMesh(&self.scene_state, world, instance.prop_asset_id, base_color) catch |err| {
                self.allocator.free(owned_id);
                return err;
            };
            prop_asset_ids[retained_count] = owned_id;
            retained_count += 1;
            try self.scene_state.addDrawBatch(mesh_index, instance.position, instance.scale, null);
        }

        return prop_asset_ids;
    }

    fn removeLightProbes(self: *CellSpawnState, start: usize, count: usize) !void {
        try helpers.removePlainRange(world_mod.cell.LightProbeMeta, &self.light_probes, start, count);
        helpers.shiftCellStarts(self, .light_probe, start, count);
    }

    fn removeNeighborLinks(self: *CellSpawnState, start: usize, count: usize) !void {
        try helpers.removePlainRange(world_mod.cell.CellId, &self.neighbor_links, start, count);
        helpers.shiftCellStarts(self, .neighbor_link, start, count);
    }

    fn removeNavVertices(self: *CellSpawnState, start: usize, count: usize) !void {
        try helpers.removePlainRange(core.math.Vec3f, &self.nav_vertices, start, count);
        helpers.shiftCellStarts(self, .nav_vertex, start, count);
        for (self.nav_indices.items) |*index| {
            if (index.* >= start + count) {
                index.* -= @intCast(count);
            }
        }
    }

    fn removeNavIndices(self: *CellSpawnState, start: usize, count: usize) !void {
        try helpers.removePlainRange(u32, &self.nav_indices, start, count);
        helpers.shiftCellStarts(self, .nav_index, start, count);
    }

    fn removeVisibilityLinks(self: *CellSpawnState, start: usize, count: usize) !void {
        try helpers.removePlainRange(world_mod.cell.VisibilityLink, &self.visibility_links, start, count);
        helpers.shiftCellStarts(self, .visibility_link, start, count);
    }

    fn removeDependencies(self: *CellSpawnState, start: usize, count: usize) !void {
        if (count == 0) return;
        if (start + count > self.dependencies.items.len) return error.InvalidCellDependencyRange;
        for (self.dependencies.items[start .. start + count]) |*dependency| {
            dependency.deinit(self.allocator);
        }
        self.dependencies.replaceRangeAssumeCapacity(start, count, &.{});
        helpers.shiftCellStarts(self, .dependency, start, count);
    }

    fn truncateMetadata(
        self: *CellSpawnState,
        light_probe_start: usize,
        neighbor_link_start: usize,
        nav_vertex_start: usize,
        nav_index_start: usize,
        visibility_link_start: usize,
        dependency_start: usize,
    ) void {
        for (self.dependencies.items[dependency_start..]) |*dependency| {
            dependency.deinit(self.allocator);
        }
        self.dependencies.shrinkRetainingCapacity(dependency_start);
        self.visibility_links.shrinkRetainingCapacity(visibility_link_start);
        self.nav_indices.shrinkRetainingCapacity(nav_index_start);
        self.nav_vertices.shrinkRetainingCapacity(nav_vertex_start);
        self.neighbor_links.shrinkRetainingCapacity(neighbor_link_start);
        self.light_probes.shrinkRetainingCapacity(light_probe_start);
    }
};

fn meshSourceKind(name: []const u8) scene_spawn.MeshSourceKind {
    if (std.mem.startsWith(u8, name, "terrain.")) return .terrain;
    if (std.mem.startsWith(u8, name, "water.")) return .water;
    if (std.mem.startsWith(u8, name, "__")) return .internal;
    return .generic;
}

comptime {
    _ = @import("cell_spawn_tests.zig");
}
