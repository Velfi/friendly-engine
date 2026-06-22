const std = @import("std");
const core = @import("../../core/mod.zig");
const cell = @import("../cell.zig");
pub const layer = @import("layer.zig");

pub const SceneObjectInput = struct {
    id: u64,
    name: []const u8,
    prop_asset_id: ?[]const u8 = null,
    variant: u32 = 0,
    interactable: bool = false,
    vertices: []const cell.RenderVertex,
    indices: []const u32,
    texture: []const u8,
    base_color: cell.CellColor,
    position: core.math.Vec3f,
    scale: core.math.Vec3f,
};

pub fn compileSceneLayerCell(
    allocator: std.mem.Allocator,
    id: cell.CellId,
    cell_size_m: f32,
    objects: []const SceneObjectInput,
    neighbors: []const cell.CellId,
) !cell.WorldCellData {
    var mesh_count: usize = 0;
    var prop_count: usize = 0;
    for (objects) |object| {
        if (object.prop_asset_id) |_| {
            prop_count += 1;
        } else {
            mesh_count += 1;
        }
    }

    var render_meshes = try allocator.alloc(cell.RenderMesh, mesh_count);
    var initialized_meshes: usize = 0;
    errdefer {
        for (render_meshes[0..initialized_meshes]) |*mesh| mesh.deinit(allocator);
        allocator.free(render_meshes);
    }

    const collision_placeholders = try allocator.alloc(cell.CollisionPlaceholder, mesh_count);
    errdefer allocator.free(collision_placeholders);
    const collision_shapes = try allocator.alloc(cell.CollisionShape, mesh_count);
    errdefer allocator.free(collision_shapes);
    const instances = try allocator.alloc(cell.InstanceRecord, mesh_count);
    errdefer allocator.free(instances);
    const prop_instances = try allocator.alloc(cell.PropInstanceRecord, prop_count);
    var initialized_props: usize = 0;
    errdefer {
        for (prop_instances[0..initialized_props]) |*instance| instance.deinit(allocator);
        allocator.free(prop_instances);
    }
    const dependencies = try allocator.alloc(cell.CellDependency, objects.len * 3);
    var initialized_dependencies: usize = 0;
    errdefer {
        for (dependencies[0..initialized_dependencies]) |*dependency| dependency.deinit(allocator);
        allocator.free(dependencies);
    }

    const probe_count: usize = @max(mesh_count, 1);
    const light_probes = try allocator.alloc(cell.LightProbeMeta, probe_count);
    errdefer allocator.free(light_probes);

    var nav_vertices = std.ArrayList(core.math.Vec3f).empty;
    errdefer nav_vertices.deinit(allocator);
    var nav_indices = std.ArrayList(u32).empty;
    errdefer nav_indices.deinit(allocator);

    var mesh_index: usize = 0;
    for (objects) |object| {
        if (object.prop_asset_id) |asset_id| {
            prop_instances[initialized_props] = .{
                .instance_id = object.id,
                .prop_asset_id = try allocator.dupe(u8, asset_id),
                .variant = object.variant,
                .position = object.position,
                .scale = object.scale,
                .base_color = object.base_color,
                .interactable = object.interactable,
            };
            initialized_props += 1;

            dependencies[initialized_dependencies] = .{
                .kind = try allocator.dupe(u8, "prop"),
                .path = try allocator.dupe(u8, asset_id),
            };
            initialized_dependencies += 1;
            continue;
        }

        render_meshes[mesh_index] = .{
            .name = try allocator.dupe(u8, object.name),
            .vertices = try allocator.dupe(cell.RenderVertex, object.vertices),
            .indices = try allocator.dupe(u32, object.indices),
            .texture = try allocator.dupe(u8, object.texture),
            .base_color = object.base_color,
            .position = object.position,
            .scale = object.scale,
        };
        initialized_meshes = mesh_index + 1;

        const half = core.math.Vec3f.scale(object.scale, 0.5);
        collision_placeholders[mesh_index] = .{
            .min = core.math.Vec3f.sub(object.position, half),
            .max = core.math.Vec3f.add(object.position, half),
        };
        collision_shapes[mesh_index] = .{
            .kind = .aabb,
            .min = collision_placeholders[mesh_index].min,
            .max = collision_placeholders[mesh_index].max,
        };
        instances[mesh_index] = .{
            .mesh_index = @intCast(mesh_index),
            .position = object.position,
            .scale = object.scale,
        };
        light_probes[mesh_index] = .{
            .position = .{
                .x = object.position.x,
                .y = object.position.y + (object.scale.y * 0.5),
                .z = object.position.z,
            },
            .intensity = 1.0,
        };

        dependencies[initialized_dependencies] = .{
            .kind = try allocator.dupe(u8, "mesh"),
            .path = try std.fmt.allocPrint(allocator, "world/object/{d}/mesh", .{object.id}),
        };
        initialized_dependencies += 1;
        dependencies[initialized_dependencies] = .{
            .kind = try allocator.dupe(u8, "material"),
            .path = try std.fmt.allocPrint(allocator, "world/object/{d}/material", .{object.id}),
        };
        initialized_dependencies += 1;

        try appendWalkableTriangles(allocator, &nav_vertices, &nav_indices, object);
        mesh_index += 1;
    }

    if (mesh_count == 0) {
        const bounds = cell.boundsForCell(id, cell_size_m, cell.default_cell_height_m);
        light_probes[0] = .{
            .position = .{
                .x = (bounds.min.x + bounds.max.x) * 0.5,
                .y = 2.0,
                .z = (bounds.min.z + bounds.max.z) * 0.5,
            },
            .intensity = 0.5,
        };
    }

    const neighbors_copy = try allocator.dupe(cell.CellId, neighbors);
    errdefer allocator.free(neighbors_copy);
    const dependencies_copy = try allocator.dupe(cell.CellDependency, dependencies[0..initialized_dependencies]);
    allocator.free(dependencies);
    initialized_dependencies = 0;
    errdefer {
        for (dependencies_copy) |*dependency| dependency.deinit(allocator);
        allocator.free(dependencies_copy);
    }
    const nav_vertices_slice = try nav_vertices.toOwnedSlice(allocator);
    errdefer allocator.free(nav_vertices_slice);
    const nav_indices_slice = try nav_indices.toOwnedSlice(allocator);
    errdefer allocator.free(nav_indices_slice);
    const blobs = try allocator.alloc(cell.CellBlob, 0);
    errdefer allocator.free(blobs);

    return .{
        .id = id,
        .cell_size_m = cell_size_m,
        .render_meshes = render_meshes,
        .collisions = collision_placeholders,
        .collision_shapes = collision_shapes,
        .instances = instances,
        .light_probes = light_probes,
        .neighbors = neighbors_copy,
        .nav_vertices = nav_vertices_slice,
        .nav_indices = nav_indices_slice,
        .dependencies = dependencies_copy,
        .prop_instances = prop_instances,
        .blobs = blobs,
    };
}

fn appendWalkableTriangles(
    allocator: std.mem.Allocator,
    nav_vertices: *std.ArrayList(core.math.Vec3f),
    nav_indices: *std.ArrayList(u32),
    object: SceneObjectInput,
) !void {
    if (object.indices.len % 3 != 0) return error.InvalidNavmeshSourceIndex;

    var index: usize = 0;
    while (index + 2 < object.indices.len) : (index += 3) {
        const ia = object.indices[index];
        const ib = object.indices[index + 1];
        const ic = object.indices[index + 2];
        const a_index: usize = @intCast(ia);
        const b_index: usize = @intCast(ib);
        const c_index: usize = @intCast(ic);
        if (a_index >= object.vertices.len or b_index >= object.vertices.len or c_index >= object.vertices.len) {
            return error.InvalidNavmeshSourceIndex;
        }

        const a = transformVertex(object.vertices[a_index].position, object.position, object.scale);
        const b = transformVertex(object.vertices[b_index].position, object.position, object.scale);
        const c = transformVertex(object.vertices[c_index].position, object.position, object.scale);
        const normal = triangleNormal(a, b, c);
        if (normal.y < 0.65) continue;

        const base: u32 = @intCast(nav_vertices.items.len);
        try nav_vertices.append(allocator, a);
        try nav_vertices.append(allocator, b);
        try nav_vertices.append(allocator, c);
        try nav_indices.appendSlice(allocator, &.{ base, base + 1, base + 2 });
    }
}

fn transformVertex(
    position: core.math.Vec3f,
    object_position: core.math.Vec3f,
    object_scale: core.math.Vec3f,
) core.math.Vec3f {
    return .{
        .x = object_position.x + (position.x * object_scale.x),
        .y = object_position.y + (position.y * object_scale.y),
        .z = object_position.z + (position.z * object_scale.z),
    };
}

fn triangleNormal(a: core.math.Vec3f, b: core.math.Vec3f, c: core.math.Vec3f) core.math.Vec3f {
    const ab = core.math.Vec3f.sub(b, a);
    const ac = core.math.Vec3f.sub(c, a);
    return core.math.Vec3f.normalized(.{
        .x = (ab.y * ac.z) - (ab.z * ac.y),
        .y = (ab.z * ac.x) - (ab.x * ac.z),
        .z = (ab.x * ac.y) - (ab.y * ac.x),
    });
}

pub fn mergeLayerOutput(
    allocator: std.mem.Allocator,
    target: *cell.WorldCellData,
    output: *layer.CellLayerOutput,
) !void {
    const nav_vertex_base = target.nav_vertices.len;
    try appendOwnedList(cell.RenderMesh, allocator, &target.render_meshes, &output.render_meshes);
    try appendOwnedList(cell.CollisionPlaceholder, allocator, &target.collisions, &output.collisions);
    try appendOwnedList(cell.CollisionShape, allocator, &target.collision_shapes, &output.collision_shapes);
    try appendOwnedList(cell.InstanceRecord, allocator, &target.instances, &output.instances);
    try appendOwnedList(cell.LightProbeMeta, allocator, &target.light_probes, &output.light_probes);
    try appendOwnedList(cell.CellId, allocator, &target.neighbors, &output.neighbors);
    try appendOwnedList(core.math.Vec3f, allocator, &target.nav_vertices, &output.nav_vertices);
    try appendOffsetIndices(allocator, &target.nav_indices, &output.nav_indices, nav_vertex_base);
    try appendOwnedList(cell.VisibilityLink, allocator, &target.visibility, &output.visibility);
    try appendOwnedList(cell.CellDependency, allocator, &target.dependencies, &output.dependencies);
    try appendOwnedList(cell.PropInstanceRecord, allocator, &target.prop_instances, &output.prop_instances);
    try appendOwnedList(cell.CellBlob, allocator, &target.blobs, &output.blobs);
    try dedupeNeighbors(allocator, target);
}

fn appendOwnedList(
    comptime T: type,
    allocator: std.mem.Allocator,
    target: *[]T,
    extra: *[]T,
) !void {
    if (extra.*.len == 0) {
        extra.* = &.{};
        return;
    }

    const old_len = target.*.len;
    const merged = try allocator.alloc(T, old_len + extra.*.len);
    @memcpy(merged[0..old_len], target.*);
    @memcpy(merged[old_len..], extra.*);
    allocator.free(target.*);
    allocator.free(extra.*);
    target.* = merged;
    extra.* = &.{};
}

fn appendOffsetIndices(
    allocator: std.mem.Allocator,
    target: *[]u32,
    extra: *[]u32,
    vertex_base: usize,
) !void {
    if (extra.*.len == 0) {
        extra.* = &.{};
        return;
    }

    const old_len = target.*.len;
    const merged = try allocator.alloc(u32, old_len + extra.*.len);
    @memcpy(merged[0..old_len], target.*);
    for (extra.*, 0..) |index, i| {
        merged[old_len + i] = try std.math.add(u32, index, @intCast(vertex_base));
    }
    allocator.free(target.*);
    allocator.free(extra.*);
    target.* = merged;
    extra.* = &.{};
}

fn dedupeNeighbors(allocator: std.mem.Allocator, target: *cell.WorldCellData) !void {
    var lookup = std.AutoHashMap(cell.CellId, void).init(allocator);
    defer lookup.deinit();

    var deduped = std.ArrayList(cell.CellId).empty;
    defer deduped.deinit(allocator);

    for (target.neighbors) |neighbor| {
        if (lookup.contains(neighbor)) continue;
        try lookup.put(neighbor, {});
        try deduped.append(allocator, neighbor);
    }

    allocator.free(target.neighbors);
    target.neighbors = try deduped.toOwnedSlice(allocator);
}

test "scene layer compile emits placeholder data" {
    const inputs = [_]SceneObjectInput{.{
        .id = 1,
        .name = "box",
        .vertices = &.{.{
            .position = .{ .x = -0.5, .y = 0, .z = -0.5 },
            .normal = .{ .x = 0, .y = 1, .z = 0 },
            .uv = .{ .x = 0, .y = 0 },
        }},
        .indices = &.{ 0, 0, 0 },
        .texture = &.{ 1, 2, 3, 4 },
        .base_color = .{ .r = 90, .g = 100, .b = 110, .a = 255 },
        .position = .{ .x = 0, .y = 0.5, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
    }};

    var compiled = try compileSceneLayerCell(
        std.testing.allocator,
        .{ .x = 0, .y = 0, .z = 0 },
        256.0,
        &inputs,
        &.{.{ .x = 1, .y = 0, .z = 0 }},
    );
    defer compiled.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), compiled.render_meshes.len);
    try std.testing.expectEqual(@as(usize, 1), compiled.collisions.len);
    try std.testing.expectEqual(@as(usize, 1), compiled.collision_shapes.len);
    try std.testing.expectEqual(@as(usize, 1), compiled.instances.len);
    try std.testing.expectEqual(@as(usize, 1), compiled.light_probes.len);
    try std.testing.expectEqual(@as(usize, 1), compiled.neighbors.len);
    try std.testing.expectEqual(@as(usize, 2), compiled.dependencies.len);
    try std.testing.expectEqual(@as(usize, 0), compiled.blobs.len);
}

test "scene layer compile keeps prop instances out of baked geometry" {
    const inputs = [_]SceneObjectInput{.{
        .id = 9,
        .name = "crate instance",
        .prop_asset_id = "crate_wood",
        .variant = 2,
        .interactable = true,
        .vertices = &.{},
        .indices = &.{},
        .texture = &.{},
        .base_color = .{ .r = 140, .g = 95, .b = 45, .a = 255 },
        .position = .{ .x = 3, .y = 0.5, .z = 4 },
        .scale = .{ .x = 1, .y = 2, .z = 1 },
    }};

    var compiled = try compileSceneLayerCell(
        std.testing.allocator,
        .{ .x = 0, .y = 0, .z = 0 },
        256.0,
        &inputs,
        &.{},
    );
    defer compiled.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), compiled.render_meshes.len);
    try std.testing.expectEqual(@as(usize, 0), compiled.instances.len);
    try std.testing.expectEqual(@as(usize, 1), compiled.light_probes.len);
    try std.testing.expectEqual(@as(usize, 1), compiled.prop_instances.len);
    try std.testing.expectEqual(@as(u64, 9), compiled.prop_instances[0].instance_id);
    try std.testing.expectEqualStrings("crate_wood", compiled.prop_instances[0].prop_asset_id);
    try std.testing.expectEqual(@as(u32, 2), compiled.prop_instances[0].variant);
    try std.testing.expect(compiled.prop_instances[0].interactable);
    try std.testing.expectEqual(@as(usize, 1), compiled.dependencies.len);
    try std.testing.expectEqualStrings("prop", compiled.dependencies[0].kind);
    try std.testing.expectEqualStrings("crate_wood", compiled.dependencies[0].path);
}

test "scene layer compile emits walkable navmesh triangles" {
    const inputs = [_]SceneObjectInput{.{
        .id = 7,
        .name = "floor",
        .vertices = &.{
            .{
                .position = .{ .x = 0, .y = 0, .z = 0 },
                .normal = .{ .x = 0, .y = 1, .z = 0 },
                .uv = .{ .x = 0, .y = 0 },
            },
            .{
                .position = .{ .x = 1, .y = 0, .z = 0 },
                .normal = .{ .x = 0, .y = 1, .z = 0 },
                .uv = .{ .x = 1, .y = 0 },
            },
            .{
                .position = .{ .x = 0, .y = 0, .z = 1 },
                .normal = .{ .x = 0, .y = 1, .z = 0 },
                .uv = .{ .x = 0, .y = 1 },
            },
        },
        .indices = &.{ 0, 2, 1 },
        .texture = &.{},
        .base_color = .{ .r = 90, .g = 100, .b = 110, .a = 255 },
        .position = .{ .x = 4, .y = 1, .z = 8 },
        .scale = .{ .x = 2, .y = 1, .z = 3 },
    }};

    var compiled = try compileSceneLayerCell(
        std.testing.allocator,
        .{ .x = 0, .y = 0, .z = 0 },
        256.0,
        &inputs,
        &.{},
    );
    defer compiled.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), compiled.nav_vertices.len);
    try std.testing.expectEqual(@as(usize, 3), compiled.nav_indices.len);
    try std.testing.expectEqual(@as(f32, 4), compiled.nav_vertices[0].x);
    try std.testing.expectEqual(@as(f32, 1), compiled.nav_vertices[0].y);
    try std.testing.expectEqual(@as(f32, 8), compiled.nav_vertices[0].z);
}

test "layer merge appends blobs and dedupes neighbors" {
    var compiled = try compileSceneLayerCell(
        std.testing.allocator,
        .{ .x = 0, .y = 0, .z = 0 },
        256.0,
        &.{},
        &.{.{ .x = 1, .y = 0, .z = 0 }},
    );
    defer compiled.deinit(std.testing.allocator);

    var output = layer.CellLayerOutput{
        .neighbors = try std.testing.allocator.dupe(cell.CellId, &.{
            .{ .x = 1, .y = 0, .z = 0 },
            .{ .x = 0, .y = 1, .z = 0 },
        }),
        .blobs = try std.testing.allocator.dupe(cell.CellBlob, &.{.{
            .kind = try std.testing.allocator.dupe(u8, "test.layer"),
            .payload = try std.testing.allocator.dupe(u8, "{}"),
        }}),
    };
    defer output.deinit(std.testing.allocator);

    try mergeLayerOutput(std.testing.allocator, &compiled, &output);
    try std.testing.expectEqual(@as(usize, 2), compiled.neighbors.len);
    try std.testing.expectEqual(@as(usize, 1), compiled.blobs.len);
}

test "layer merge offsets appended nav indices" {
    const inputs = [_]SceneObjectInput{.{
        .id = 1,
        .name = "floor",
        .vertices = &.{
            .{ .position = .{ .x = 0, .y = 0, .z = 0 }, .normal = .{ .x = 0, .y = 1, .z = 0 }, .uv = .{ .x = 0, .y = 0 } },
            .{ .position = .{ .x = 1, .y = 0, .z = 0 }, .normal = .{ .x = 0, .y = 1, .z = 0 }, .uv = .{ .x = 1, .y = 0 } },
            .{ .position = .{ .x = 0, .y = 0, .z = 1 }, .normal = .{ .x = 0, .y = 1, .z = 0 }, .uv = .{ .x = 0, .y = 1 } },
        },
        .indices = &.{ 0, 2, 1 },
        .texture = &.{},
        .base_color = .{ .r = 90, .g = 100, .b = 110, .a = 255 },
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
    }};

    var compiled = try compileSceneLayerCell(
        std.testing.allocator,
        .{ .x = 0, .y = 0, .z = 0 },
        256.0,
        &inputs,
        &.{},
    );
    defer compiled.deinit(std.testing.allocator);

    var output = layer.CellLayerOutput{
        .nav_vertices = try std.testing.allocator.dupe(core.math.Vec3f, &.{
            .{ .x = 10, .y = 0, .z = 10 },
            .{ .x = 11, .y = 0, .z = 10 },
            .{ .x = 10, .y = 0, .z = 11 },
        }),
        .nav_indices = try std.testing.allocator.dupe(u32, &.{ 0, 1, 2 }),
    };
    defer output.deinit(std.testing.allocator);

    try mergeLayerOutput(std.testing.allocator, &compiled, &output);
    try std.testing.expectEqual(@as(usize, 6), compiled.nav_vertices.len);
    try std.testing.expectEqual(@as(usize, 6), compiled.nav_indices.len);
    try std.testing.expectEqual(@as(u32, 3), compiled.nav_indices[3]);
    try std.testing.expectEqual(@as(u32, 4), compiled.nav_indices[4]);
    try std.testing.expectEqual(@as(u32, 5), compiled.nav_indices[5]);
}
