const std = @import("std");
const core = @import("../../core/mod.zig");
const framework = @import("../../framework/mod.zig");
const world = @import("../../world/mod.zig");
const project_config = @import("../project_config.zig");

pub const authoring = @import("authoring.zig");
pub const chunk_store = @import("chunk_store.zig");
pub const residency = @import("residency.zig");
pub const mesh_builder = @import("mesh_builder.zig");
pub const splat_texture = @import("splat_texture.zig");
pub const lod_pick = @import("lod_pick.zig");

pub const module_name = "gem.terrain";
const layer_name = "world.layer.terrain";

const TerrainCutout = struct {
    min: core.math.Vec3f,
    max: core.math.Vec3f,

    fn rect(self: TerrainCutout) mesh_builder.CutoutRect {
        return .{ .min_x = self.min.x, .min_z = self.min.z, .max_x = self.max.x, .max_z = self.max.z };
    }
};

pub const TerrainTile = struct {
    cell: [3]i32,
    size: u32,
    lod_levels: []const u32,
    heights: []const f32,
    splat_size: u32,
    splat: []const u8,
    paint_layers: []const []const u8,
    paint_colors: []const [4]u8,
    paint_albedo_textures: []const []const u8,
    paint_roughness_textures: []const []const u8,
    paint_specular_textures: []const []const u8,
    paint_displacement_textures: []const []const u8,
    material: []const u8 = "terrain.default",
};

pub fn register(registry: anytype) !void {
    try registry.registerWorldCompilerLayer(.{
        .name = layer_name,
        .affected_cells = affectedCells,
        .compile_cell = compileCell,
    });
}

pub fn start(engine_world: *framework.World) !void {
    try engine_world.notifications.publish("gem.terrain.started", "{}");
}

pub fn stop(engine_world: *framework.World) !void {
    try engine_world.notifications.publish("gem.terrain.stopped", "{}");
}

fn affectedCells(
    _: ?*anyopaque,
    compile_ctx: *const world.compiler.layer.CompileContext,
    allocator: std.mem.Allocator,
) ![]world.cell.CellId {
    var index = try authoring.loadIndex(allocator, compile_ctx.io, compile_ctx.project_path, compile_ctx.manifest_path);
    defer index.deinit();
    if (index.entries.items.len == 0) return allocator.alloc(world.cell.CellId, 0);

    var cells = std.ArrayList(world.cell.CellId).empty;
    defer cells.deinit(allocator);
    var lookup = std.AutoHashMap(world.cell.CellId, void).init(allocator);
    defer lookup.deinit();

    for (index.entries.items) |entry| {
        const id = entry.cell;
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
    const maybe_doc = try authoring.loadCell(allocator, compile_ctx.io, compile_ctx.project_path, compile_ctx.manifest_path, id);
    if (maybe_doc == null) return .{};
    var doc = maybe_doc.?;
    defer doc.deinit();
    if (doc.tiles.items.len != 1) return error.InvalidTerrainDocument;

    var meshes = std.ArrayList(world.cell.RenderMesh).empty;
    var collisions = std.ArrayList(world.cell.CollisionPlaceholder).empty;
    var collision_shapes = std.ArrayList(world.cell.CollisionShape).empty;
    var nav_vertices = std.ArrayList(core.math.Vec3f).empty;
    var nav_indices = std.ArrayList(u32).empty;
    var blobs = std.ArrayList(world.cell.CellBlob).empty;
    errdefer {
        for (meshes.items) |*mesh| mesh.deinit(allocator);
        meshes.deinit(allocator);
        collisions.deinit(allocator);
        collision_shapes.deinit(allocator);
        nav_vertices.deinit(allocator);
        nav_indices.deinit(allocator);
        for (blobs.items) |*blob| blob.deinit(allocator);
        blobs.deinit(allocator);
    }

    const tile = doc.tiles.items[0];
    if (!tile.id().eql(id)) return error.InvalidTerrainDocument;
    try compileTerrainTile(
        allocator,
        compile_ctx,
        id,
        tile,
        &meshes,
        &collisions,
        &collision_shapes,
        &nav_vertices,
        &nav_indices,
        &blobs,
    );

    return .{
        .render_meshes = try meshes.toOwnedSlice(allocator),
        .collisions = try collisions.toOwnedSlice(allocator),
        .collision_shapes = try collision_shapes.toOwnedSlice(allocator),
        .nav_vertices = try nav_vertices.toOwnedSlice(allocator),
        .nav_indices = try nav_indices.toOwnedSlice(allocator),
        .blobs = try blobs.toOwnedSlice(allocator),
    };
}

fn compileTerrainTile(
    allocator: std.mem.Allocator,
    compile_ctx: *const world.compiler.layer.CompileContext,
    id: world.cell.CellId,
    tile: authoring.OwnedTerrainTile,
    meshes: *std.ArrayList(world.cell.RenderMesh),
    collisions: *std.ArrayList(world.cell.CollisionPlaceholder),
    collision_shapes: *std.ArrayList(world.cell.CollisionShape),
    nav_vertices: *std.ArrayList(core.math.Vec3f),
    nav_indices: *std.ArrayList(u32),
    blobs: *std.ArrayList(world.cell.CellBlob),
) !void {
    const compile_tile = TerrainTile{
        .cell = tile.cell,
        .size = tile.size,
        .lod_levels = tile.lod_levels,
        .heights = tile.heights,
        .splat_size = tile.splat_size,
        .splat = tile.splat,
        .paint_layers = tile.paint_layers,
        .paint_colors = tile.paint_colors,
        .paint_albedo_textures = tile.paint_albedo_textures,
        .paint_roughness_textures = tile.paint_roughness_textures,
        .paint_specular_textures = tile.paint_specular_textures,
        .paint_displacement_textures = tile.paint_displacement_textures,
        .material = tile.material,
    };
    try validateTile(compile_tile);

    const bounds = world.cell.boundsForCell(id, compile_ctx.loaded_manifest.cell_size_m, world.cell.default_cell_height_m);
    const cutouts = try loadTerrainCutoutsForCell(allocator, compile_ctx, id, bounds);
    defer allocator.free(cutouts);
    var min_height = std.math.floatMax(f32);
    var max_height = -std.math.floatMax(f32);

    var cutout_rects = try allocator.alloc(mesh_builder.CutoutRect, cutouts.len);
    defer allocator.free(cutout_rects);
    for (cutouts, 0..) |cutout, index| cutout_rects[index] = cutout.rect();

    for (tile.lod_levels, 0..) |lod_size, lod_index| {
        var mesh = try mesh_builder.buildLodMeshWithCutouts(
            allocator,
            bounds,
            .{ .size = tile.size, .heights = tile.heights },
            lod_size,
            lod_index,
            null,
            cutout_rects,
        );
        errdefer mesh.deinit(allocator);

        const texture = try splat_texture.buildLayerTexture(
            allocator,
            tile.splat_size,
            tile.paint_layers,
            tile.paint_colors,
            tile.splat,
        );
        allocator.free(mesh.texture);
        mesh.texture = texture;

        try meshes.append(allocator, mesh);
    }

    for (tile.heights) |sample| {
        min_height = @min(min_height, sample);
        max_height = @max(max_height, sample);
    }
    try appendTerrainCollision(allocator, id, bounds, compile_tile, cutouts, min_height, max_height, collisions, collision_shapes, blobs);
    try appendTerrainNav(allocator, nav_vertices, nav_indices, bounds, compile_tile, cutout_rects);

    try world.compiler.layer.appendBlobJson(allocator, blobs, "terrain.patch", .{
        .cell = .{ id.x, id.y, id.z },
        .lod_levels = tile.lod_levels,
        .sample_size = tile.size,
        .material = tile.material,
        .height_count = tile.heights.len,
        .cutout_count = cutouts.len,
    });
    try world.compiler.layer.appendBlobJson(allocator, blobs, "terrain.splat", .{
        .cell = .{ id.x, id.y, id.z },
        .size = tile.splat_size,
        .layers = tile.paint_layers,
        .colors = tile.paint_colors,
        .albedo_textures = tile.paint_albedo_textures,
        .roughness_textures = tile.paint_roughness_textures,
        .specular_textures = tile.paint_specular_textures,
        .displacement_textures = tile.paint_displacement_textures,
        .material = tile.material,
        .values = tile.splat,
    });
}

fn appendTerrainCollision(
    allocator: std.mem.Allocator,
    id: world.cell.CellId,
    bounds: world.cell.CellBounds,
    tile: TerrainTile,
    cutouts: []const TerrainCutout,
    source_min_height: f32,
    source_max_height: f32,
    collisions: *std.ArrayList(world.cell.CollisionPlaceholder),
    collision_shapes: *std.ArrayList(world.cell.CollisionShape),
    blobs: *std.ArrayList(world.cell.CellBlob),
) !void {
    const heights = try allocator.dupe(f32, tile.heights);
    defer allocator.free(heights);
    applyCutoutsToHeights(bounds, tile.size, heights, cutouts);

    var min_height = source_min_height;
    var max_height = source_max_height;
    if (cutouts.len > 0) {
        min_height = std.math.floatMax(f32);
        max_height = -std.math.floatMax(f32);
        for (heights) |height| {
            min_height = @min(min_height, height);
            max_height = @max(max_height, height);
        }
    }

    try collisions.append(allocator, .{
        .min = .{ .x = bounds.min.x, .y = min_height, .z = bounds.min.z },
        .max = .{ .x = bounds.max.x, .y = max_height, .z = bounds.max.z },
    });
    try collision_shapes.append(allocator, .{
        .kind = .heightfield,
        .min = .{ .x = bounds.min.x, .y = min_height, .z = bounds.min.z },
        .max = .{ .x = bounds.max.x, .y = max_height, .z = bounds.max.z },
    });

    try world.compiler.layer.appendBlobJson(allocator, blobs, "terrain.heightfield", .{
        .cell = .{ id.x, id.y, id.z },
        .size = tile.size,
        .min_y = min_height,
        .max_y = max_height,
        .bounds = .{ .min_x = bounds.min.x, .min_z = bounds.min.z, .max_x = bounds.max.x, .max_z = bounds.max.z },
        .cutout_count = cutouts.len,
        .heights = heights,
    });
}

fn applyCutoutsToHeights(bounds: world.cell.CellBounds, size_u32: u32, heights: []f32, cutouts: []const TerrainCutout) void {
    if (cutouts.len == 0) return;
    const size: usize = @intCast(size_u32);
    const span = @as(f32, @floatFromInt(size - 1));
    for (0..size) |z| {
        const vz = @as(f32, @floatFromInt(z)) / span;
        const world_z = bounds.min.z + (bounds.max.z - bounds.min.z) * vz;
        for (0..size) |x| {
            const ux = @as(f32, @floatFromInt(x)) / span;
            const world_x = bounds.min.x + (bounds.max.x - bounds.min.x) * ux;
            for (cutouts) |cutout| {
                if (world_x >= cutout.min.x and world_x <= cutout.max.x and world_z >= cutout.min.z and world_z <= cutout.max.z) {
                    heights[z * size + x] = cutout.min.y;
                    break;
                }
            }
        }
    }
}

fn appendTerrainNav(
    allocator: std.mem.Allocator,
    nav_vertices: *std.ArrayList(core.math.Vec3f),
    nav_indices: *std.ArrayList(u32),
    bounds: world.cell.CellBounds,
    tile: TerrainTile,
    cutouts: []const mesh_builder.CutoutRect,
) !void {
    const size: usize = @intCast(tile.size);
    const base: u32 = @intCast(nav_vertices.items.len);

    var z: usize = 0;
    while (z < size) : (z += 1) {
        var x: usize = 0;
        while (x < size) : (x += 1) {
            const u = @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(size - 1));
            const v = @as(f32, @floatFromInt(z)) / @as(f32, @floatFromInt(size - 1));
            try nav_vertices.append(allocator, .{
                .x = bounds.min.x + (bounds.max.x - bounds.min.x) * u,
                .y = mesh_builder.sampleHeight(.{ .size = tile.size, .heights = tile.heights }, x, z, size),
                .z = bounds.min.z + (bounds.max.z - bounds.min.z) * v,
            });
        }
    }

    z = 0;
    while (z + 1 < size) : (z += 1) {
        var x: usize = 0;
        while (x + 1 < size) : (x += 1) {
            const a: u32 = base + @as(u32, @intCast(z * size + x));
            const b: u32 = a + 1;
            const c: u32 = base + @as(u32, @intCast((z + 1) * size + x + 1));
            const d: u32 = base + @as(u32, @intCast((z + 1) * size + x));
            if (!navTriangleInsideCutout(nav_vertices.items, a, c, b, cutouts)) try nav_indices.appendSlice(allocator, &.{ a, c, b });
            if (!navTriangleInsideCutout(nav_vertices.items, a, d, c, cutouts)) try nav_indices.appendSlice(allocator, &.{ a, d, c });
        }
    }
}

fn navTriangleInsideCutout(vertices: []const core.math.Vec3f, ia: u32, ib: u32, ic: u32, cutouts: []const mesh_builder.CutoutRect) bool {
    if (cutouts.len == 0) return false;
    const a = vertices[@intCast(ia)];
    const b = vertices[@intCast(ib)];
    const c = vertices[@intCast(ic)];
    const cx = (a.x + b.x + c.x) / 3.0;
    const cz = (a.z + b.z + c.z) / 3.0;
    for (cutouts) |cutout| {
        if (cutout.containsPoint(cx, cz)) return true;
    }
    return false;
}

fn loadTerrainCutoutsForCell(
    allocator: std.mem.Allocator,
    compile_ctx: *const world.compiler.layer.CompileContext,
    id: world.cell.CellId,
    bounds: world.cell.CellBounds,
) ![]TerrainCutout {
    var config = try project_config.loadProjectConfigInProject(
        allocator,
        compile_ctx.io,
        compile_ctx.project_path,
        "engine.kdl",
    );
    defer config.deinit();

    var cutouts = std.ArrayList(TerrainCutout).empty;
    errdefer cutouts.deinit(allocator);
    for (config.sceneEntries()) |scene| {
        try appendSceneCutoutsForCell(allocator, compile_ctx, scene.path, bounds, &cutouts);
    }
    _ = id;
    return cutouts.toOwnedSlice(allocator);
}

const SceneEntityCutouts = struct {
    id: u64,
    parent_id: ?u64,
    position: core.math.Vec3f,
    rotation: core.math.Vec3f = .{ .x = 0, .y = 0, .z = 0 },
    scale: core.math.Vec3f = .{ .x = 1, .y = 1, .z = 1 },
    cutouts: std.ArrayList(TerrainCutout) = .empty,

    fn deinit(self: *SceneEntityCutouts, allocator: std.mem.Allocator) void {
        self.cutouts.deinit(allocator);
    }
};

fn appendSceneCutoutsForCell(
    allocator: std.mem.Allocator,
    compile_ctx: *const world.compiler.layer.CompileContext,
    scene_path: []const u8,
    bounds: world.cell.CellBounds,
    out: *std.ArrayList(TerrainCutout),
) !void {
    var project_dir = try openProjectDir(compile_ctx.io, compile_ctx.project_path);
    defer project_dir.close(compile_ctx.io);
    const bytes = try project_dir.readFileAlloc(compile_ctx.io, scene_path, allocator, .limited(1024 * 1024));
    defer allocator.free(bytes);

    var entities = std.ArrayList(SceneEntityCutouts).empty;
    defer {
        for (entities.items) |*entity| entity.deinit(allocator);
        entities.deinit(allocator);
    }

    var current: ?usize = null;
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (std.mem.startsWith(u8, line, "entity ")) {
            const entity_id = try parseEntityId(line);
            try entities.append(allocator, .{
                .id = entity_id,
                .parent_id = null,
                .position = .{ .x = 0, .y = 0, .z = 0 },
            });
            current = entities.items.len - 1;
            continue;
        }
        const index = current orelse continue;
        if (std.mem.eql(u8, line, "}")) {
            current = null;
            continue;
        }
        if (std.mem.startsWith(u8, line, "transform ")) {
            entities.items[index].position = try parseVec3Property(line, "position");
            entities.items[index].rotation = try parseVec3Property(line, "rotation");
            entities.items[index].scale = try parseVec3Property(line, "scale");
            continue;
        }
        if (std.mem.startsWith(u8, line, "meta ")) {
            entities.items[index].parent_id = try parseOptionalU64Property(line, "parent_id");
            continue;
        }
        if (std.mem.startsWith(u8, line, "components ")) {
            try appendCutoutComponents(allocator, line, &entities.items[index].cutouts);
        }
    }

    for (entities.items, 0..) |entity, index| {
        if (entity.cutouts.items.len == 0) continue;
        try ensureAxisAlignedCutoutTransform(entity);
        const origin = try worldPositionForEntity(entities.items, index, 0);
        for (entity.cutouts.items) |cutout| {
            const world_cutout = TerrainCutout{
                .min = .{ .x = origin.x + cutout.min.x, .y = origin.y + cutout.min.y, .z = origin.z + cutout.min.z },
                .max = .{ .x = origin.x + cutout.max.x, .y = origin.y + cutout.max.y, .z = origin.z + cutout.max.z },
            };
            if (cutoutIntersectsBounds(world_cutout, bounds)) try out.append(allocator, world_cutout);
        }
    }
}

fn ensureAxisAlignedCutoutTransform(entity: SceneEntityCutouts) !void {
    if (@abs(entity.rotation.x) > 0.0001 or @abs(entity.rotation.y) > 0.0001 or @abs(entity.rotation.z) > 0.0001) return error.UnsupportedTerrainCutoutTransform;
    if (@abs(entity.scale.x - 1) > 0.0001 or @abs(entity.scale.y - 1) > 0.0001 or @abs(entity.scale.z - 1) > 0.0001) return error.UnsupportedTerrainCutoutTransform;
}

fn parseEntityId(line: []const u8) !u64 {
    const id_key = "id=";
    const value_start = (std.mem.indexOf(u8, line, id_key) orelse return error.InvalidSceneEntity) + id_key.len;
    var end = value_start;
    while (end < line.len and std.ascii.isDigit(line[end])) : (end += 1) {}
    if (end == value_start) return error.InvalidSceneEntity;
    return try std.fmt.parseUnsigned(u64, line[value_start..end], 10);
}

fn parseVec3Property(line: []const u8, key: []const u8) !core.math.Vec3f {
    const value_start = try propertyValueStart(line, key);
    const end = std.mem.indexOfScalarPos(u8, line, value_start, '"') orelse return error.InvalidSceneProperty;
    var parts = std.mem.splitScalar(u8, line[value_start..end], ',');
    const x = try std.fmt.parseFloat(f32, parts.next() orelse return error.InvalidSceneProperty);
    const y = try std.fmt.parseFloat(f32, parts.next() orelse return error.InvalidSceneProperty);
    const z = try std.fmt.parseFloat(f32, parts.next() orelse return error.InvalidSceneProperty);
    if (parts.next() != null) return error.InvalidSceneProperty;
    return .{ .x = x, .y = y, .z = z };
}

fn parseOptionalU64Property(line: []const u8, key: []const u8) !?u64 {
    const key_start = std.mem.indexOf(u8, line, key) orelse return null;
    if (key_start + key.len >= line.len or line[key_start + key.len] != '=') return null;
    const value_start = key_start + key.len + 1;
    var end = value_start;
    while (end < line.len and std.ascii.isDigit(line[end])) : (end += 1) {}
    if (end == value_start) return error.InvalidSceneProperty;
    return try std.fmt.parseUnsigned(u64, line[value_start..end], 10);
}

fn propertyValueStart(line: []const u8, key: []const u8) !usize {
    const key_start = std.mem.indexOf(u8, line, key) orelse return error.InvalidSceneProperty;
    if (key_start + key.len + 1 >= line.len or line[key_start + key.len] != '=' or line[key_start + key.len + 1] != '"') return error.InvalidSceneProperty;
    return key_start + key.len + 2;
}

fn appendCutoutComponents(allocator: std.mem.Allocator, line: []const u8, out: *std.ArrayList(TerrainCutout)) !void {
    const prefix = "arch.cutout:";
    var search_start: usize = 0;
    while (std.mem.indexOfPos(u8, line, search_start, prefix)) |match_start| {
        const payload_start = match_start + prefix.len;
        var payload_end = payload_start;
        while (payload_end < line.len and line[payload_end] != ',' and line[payload_end] != '"') : (payload_end += 1) {}
        try out.append(allocator, try parseCutoutPayload(line[payload_start..payload_end]));
        search_start = payload_end;
    }
}

fn parseCutoutPayload(payload: []const u8) !TerrainCutout {
    var parts = std.mem.splitScalar(u8, payload, '|');
    _ = try std.fmt.parseUnsigned(u32, parts.next() orelse return error.InvalidArchitectureCutout, 10);
    const min_x = try std.fmt.parseFloat(f32, parts.next() orelse return error.InvalidArchitectureCutout);
    const min_y = try std.fmt.parseFloat(f32, parts.next() orelse return error.InvalidArchitectureCutout);
    const min_z = try std.fmt.parseFloat(f32, parts.next() orelse return error.InvalidArchitectureCutout);
    const max_x = try std.fmt.parseFloat(f32, parts.next() orelse return error.InvalidArchitectureCutout);
    const max_y = try std.fmt.parseFloat(f32, parts.next() orelse return error.InvalidArchitectureCutout);
    const max_z = try std.fmt.parseFloat(f32, parts.next() orelse return error.InvalidArchitectureCutout);
    if (parts.next() != null or max_x <= min_x or max_y <= min_y or max_z <= min_z) return error.InvalidArchitectureCutout;
    return .{
        .min = .{ .x = min_x, .y = min_y, .z = min_z },
        .max = .{ .x = max_x, .y = max_y, .z = max_z },
    };
}

fn worldPositionForEntity(entities: []const SceneEntityCutouts, index: usize, depth: u32) !core.math.Vec3f {
    if (depth > 64) return error.SceneParentCycle;
    const entity = entities[index];
    if (entity.parent_id) |parent_id| {
        const parent_index = findEntityById(entities, parent_id) orelse return error.SceneParentMissing;
        try ensureAxisAlignedCutoutTransform(entities[parent_index]);
        const parent_pos = try worldPositionForEntity(entities, parent_index, depth + 1);
        return .{ .x = parent_pos.x + entity.position.x, .y = parent_pos.y + entity.position.y, .z = parent_pos.z + entity.position.z };
    }
    return entity.position;
}

fn findEntityById(entities: []const SceneEntityCutouts, id: u64) ?usize {
    for (entities, 0..) |entity, index| {
        if (entity.id == id) return index;
    }
    return null;
}

fn cutoutIntersectsBounds(cutout: TerrainCutout, bounds: world.cell.CellBounds) bool {
    return cutout.max.x > bounds.min.x and cutout.min.x < bounds.max.x and
        cutout.max.z > bounds.min.z and cutout.min.z < bounds.max.z;
}

fn openProjectDir(io: std.Io, project_path: []const u8) !std.Io.Dir {
    if (std.fs.path.isAbsolute(project_path)) {
        return try std.Io.Dir.openDirAbsolute(io, project_path, .{});
    }
    return try std.Io.Dir.cwd().openDir(io, project_path, .{});
}

pub fn validateTile(tile: TerrainTile) !void {
    if (tile.cell.len != 3 and tile.cell.len != 2) return error.InvalidTerrainCell;
    if (tile.size < 2) return error.InvalidTerrainTile;
    if (tile.material.len == 0) return error.InvalidTerrainTile;
    if (tile.lod_levels.len < 2) return error.InvalidTerrainTile;
    for (tile.lod_levels) |lod| {
        if (lod < 2) return error.InvalidTerrainTile;
        if (lod > tile.size) return error.InvalidTerrainTile;
    }
    const sample_count = @as(usize, tile.size) * @as(usize, tile.size);
    if (tile.heights.len != sample_count) return error.InvalidTerrainHeightCount;
    for (tile.heights) |height| {
        if (!std.math.isFinite(height)) return error.InvalidTerrainHeight;
    }
    if (tile.paint_layers.len < 2 or tile.paint_layers.len != tile.paint_colors.len) return error.InvalidTerrainPaintLayers;
    if (tile.paint_albedo_textures.len != tile.paint_layers.len or
        tile.paint_roughness_textures.len != tile.paint_layers.len or
        tile.paint_specular_textures.len != tile.paint_layers.len or
        tile.paint_displacement_textures.len != tile.paint_layers.len) return error.InvalidTerrainPaintLayers;
    for (tile.paint_layers, 0..) |layer, index| {
        if (layer.len == 0) return error.InvalidTerrainPaintLayers;
        for (tile.paint_layers[index + 1 ..]) |other| {
            if (std.mem.eql(u8, layer, other)) return error.InvalidTerrainPaintLayers;
        }
    }
    const splat_count = @as(usize, tile.splat_size) * @as(usize, tile.splat_size) * tile.paint_layers.len;
    if (tile.splat_size < 2 or tile.splat.len != splat_count) return error.InvalidTerrainSplatCount;
}

pub fn parseCellId(values: []const i32) !world.cell.CellId {
    if (values.len != 2 and values.len != 3) return error.InvalidTerrainCell;
    return .{
        .x = @intCast(values[0]),
        .y = @intCast(values[1]),
        .z = if (values.len == 3) @intCast(values[2]) else 0,
    };
}

comptime {
    _ = @import("mod_tests.zig");
}
