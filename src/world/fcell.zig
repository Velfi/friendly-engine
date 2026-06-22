const std = @import("std");
const cell = @import("cell.zig");
const core = @import("../core/mod.zig");

pub const magic: [4]u8 = .{ 'F', 'C', 'E', 'L' };
pub const version: u32 = 3;

pub fn bakedCellPath(
    allocator: std.mem.Allocator,
    target: []const u8,
    world_id: []const u8,
    id: cell.CellId,
) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "assets/cache/{s}/world/{s}/cells/{d}_{d}_{d}.fcell",
        .{ target, world_id, id.x, id.y, id.z },
    );
}

pub fn encodeCell(allocator: std.mem.Allocator, world_cell: cell.WorldCellData) ![]u8 {
    var list = std.ArrayList(u8).empty;
    errdefer list.deinit(allocator);

    try list.appendSlice(allocator, &magic);
    try appendU32(&list, allocator, version);
    try appendI32(&list, allocator, world_cell.id.x);
    try appendI32(&list, allocator, world_cell.id.y);
    try appendI32(&list, allocator, world_cell.id.z);
    try appendF32(&list, allocator, world_cell.cell_size_m);
    try appendU32(&list, allocator, @intCast(world_cell.render_meshes.len));
    try appendU32(&list, allocator, @intCast(world_cell.collisions.len));
    try appendU32(&list, allocator, @intCast(world_cell.instances.len));
    try appendU32(&list, allocator, @intCast(world_cell.light_probes.len));
    try appendU32(&list, allocator, @intCast(world_cell.neighbors.len));
    try appendU32(&list, allocator, @intCast(world_cell.blobs.len));
    try appendU32(&list, allocator, @intCast(world_cell.collision_shapes.len));
    try appendU32(&list, allocator, @intCast(world_cell.nav_vertices.len));
    try appendU32(&list, allocator, @intCast(world_cell.nav_indices.len));
    try appendU32(&list, allocator, @intCast(world_cell.visibility.len));
    try appendU32(&list, allocator, @intCast(world_cell.dependencies.len));
    try appendU32(&list, allocator, @intCast(world_cell.prop_instances.len));

    for (world_cell.render_meshes) |mesh| {
        try appendString(&list, allocator, mesh.name);
        try appendVec3(&list, allocator, mesh.position);
        try appendVec3(&list, allocator, mesh.scale);
        try list.appendSlice(allocator, &.{ mesh.base_color.r, mesh.base_color.g, mesh.base_color.b, mesh.base_color.a });
        try appendU32(&list, allocator, @intCast(mesh.texture.len));
        try list.appendSlice(allocator, mesh.texture);
        try appendU32(&list, allocator, @intCast(mesh.vertices.len));
        try appendU32(&list, allocator, @intCast(mesh.indices.len));
        try list.appendSlice(allocator, std.mem.sliceAsBytes(mesh.vertices));
        try list.appendSlice(allocator, std.mem.sliceAsBytes(mesh.indices));
    }

    for (world_cell.collisions) |entry| {
        try appendVec3(&list, allocator, entry.min);
        try appendVec3(&list, allocator, entry.max);
    }
    for (world_cell.collision_shapes) |entry| {
        try list.append(allocator, @intFromEnum(entry.kind));
        try appendVec3(&list, allocator, entry.min);
        try appendVec3(&list, allocator, entry.max);
        try appendVec3(&list, allocator, entry.center);
        try appendF32(&list, allocator, entry.radius);
    }
    for (world_cell.instances) |entry| {
        try appendU32(&list, allocator, entry.mesh_index);
        try appendVec3(&list, allocator, entry.position);
        try appendVec3(&list, allocator, entry.scale);
    }
    for (world_cell.light_probes) |entry| {
        try appendVec3(&list, allocator, entry.position);
        try appendF32(&list, allocator, entry.intensity);
    }
    for (world_cell.neighbors) |neighbor| {
        try appendI32(&list, allocator, neighbor.x);
        try appendI32(&list, allocator, neighbor.y);
        try appendI32(&list, allocator, neighbor.z);
    }
    for (world_cell.nav_vertices) |vertex| {
        try appendVec3(&list, allocator, vertex);
    }
    for (world_cell.nav_indices) |index| {
        try appendU32(&list, allocator, index);
    }
    for (world_cell.visibility) |link| {
        try appendI32(&list, allocator, link.target.x);
        try appendI32(&list, allocator, link.target.y);
        try appendI32(&list, allocator, link.target.z);
        try appendVec3(&list, allocator, link.min);
        try appendVec3(&list, allocator, link.max);
    }
    for (world_cell.dependencies) |dependency| {
        try appendString(&list, allocator, dependency.kind);
        try appendString(&list, allocator, dependency.path);
    }
    for (world_cell.prop_instances) |instance| {
        try appendU64(&list, allocator, instance.instance_id);
        try appendString(&list, allocator, instance.prop_asset_id);
        try appendU32(&list, allocator, instance.variant);
        try appendVec3(&list, allocator, instance.position);
        try appendVec3(&list, allocator, instance.rotation);
        try appendVec3(&list, allocator, instance.scale);
        try list.appendSlice(allocator, &.{ instance.base_color.r, instance.base_color.g, instance.base_color.b, instance.base_color.a });
        try list.append(allocator, if (instance.interactable) 1 else 0);
    }
    for (world_cell.blobs) |blob| {
        try appendString(&list, allocator, blob.kind);
        try appendU32(&list, allocator, @intCast(blob.payload.len));
        try list.appendSlice(allocator, blob.payload);
    }

    return try list.toOwnedSlice(allocator);
}

pub fn decodeCell(allocator: std.mem.Allocator, bytes: []const u8) !cell.WorldCellData {
    if (bytes.len < 48) return error.InvalidCellFormat;
    if (!std.mem.eql(u8, bytes[0..4], &magic)) return error.InvalidCellFormat;

    const file_version = std.mem.readInt(u32, bytes[4..8], .little);
    if (file_version != version) return error.UnsupportedCellVersion;

    var offset: usize = 8;
    const id = cell.CellId{
        .x = try readI32(bytes, &offset),
        .y = try readI32(bytes, &offset),
        .z = try readI32(bytes, &offset),
    };
    const cell_size_m = try readF32(bytes, &offset);
    const mesh_count: usize = @intCast(try readU32(bytes, &offset));
    const collision_count: usize = @intCast(try readU32(bytes, &offset));
    const instance_count: usize = @intCast(try readU32(bytes, &offset));
    const probe_count: usize = @intCast(try readU32(bytes, &offset));
    const neighbor_count: usize = @intCast(try readU32(bytes, &offset));
    const blob_count: usize = @intCast(try readU32(bytes, &offset));
    const collision_shape_count: usize = @intCast(try readU32(bytes, &offset));
    const nav_vertex_count: usize = @intCast(try readU32(bytes, &offset));
    const nav_index_count: usize = @intCast(try readU32(bytes, &offset));
    const visibility_count: usize = @intCast(try readU32(bytes, &offset));
    const dependency_count: usize = @intCast(try readU32(bytes, &offset));
    const prop_instance_count: usize = @intCast(try readU32(bytes, &offset));

    var meshes = try allocator.alloc(cell.RenderMesh, mesh_count);
    errdefer allocator.free(meshes);
    var mesh_index: usize = 0;
    errdefer {
        for (meshes[0..mesh_index]) |*mesh| mesh.deinit(allocator);
    }
    while (mesh_index < mesh_count) : (mesh_index += 1) {
        const name = try readString(allocator, bytes, &offset);
        errdefer allocator.free(name);
        const position = try readVec3(bytes, &offset);
        const scale = try readVec3(bytes, &offset);

        var color: [4]u8 = undefined;
        for (&color) |*component| component.* = try readByte(bytes, &offset);

        const texture_len: usize = @intCast(try readU32(bytes, &offset));
        const texture = try allocator.alloc(u8, texture_len);
        errdefer allocator.free(texture);
        try readExact(bytes, &offset, texture);

        const vertex_count: usize = @intCast(try readU32(bytes, &offset));
        const index_count: usize = @intCast(try readU32(bytes, &offset));
        const vertices = try allocator.alloc(cell.RenderVertex, vertex_count);
        errdefer allocator.free(vertices);
        const indices = try allocator.alloc(u32, index_count);
        errdefer allocator.free(indices);
        try readExact(bytes, &offset, std.mem.sliceAsBytes(vertices));
        try readExact(bytes, &offset, std.mem.sliceAsBytes(indices));

        meshes[mesh_index] = .{
            .name = name,
            .vertices = vertices,
            .indices = indices,
            .texture = texture,
            .base_color = .{
                .r = color[0],
                .g = color[1],
                .b = color[2],
                .a = color[3],
            },
            .position = position,
            .scale = scale,
        };
    }

    const collisions = try allocator.alloc(cell.CollisionPlaceholder, collision_count);
    errdefer allocator.free(collisions);
    for (collisions) |*entry| {
        entry.* = .{
            .min = try readVec3(bytes, &offset),
            .max = try readVec3(bytes, &offset),
        };
    }

    const collision_shapes = try allocator.alloc(cell.CollisionShape, collision_shape_count);
    errdefer allocator.free(collision_shapes);
    for (collision_shapes) |*entry| {
        entry.* = .{
            .kind = try readCollisionShapeKind(bytes, &offset),
            .min = try readVec3(bytes, &offset),
            .max = try readVec3(bytes, &offset),
            .center = try readVec3(bytes, &offset),
            .radius = try readF32(bytes, &offset),
        };
    }

    const instances = try allocator.alloc(cell.InstanceRecord, instance_count);
    errdefer allocator.free(instances);
    for (instances) |*entry| {
        entry.* = .{
            .mesh_index = try readU32(bytes, &offset),
            .position = try readVec3(bytes, &offset),
            .scale = try readVec3(bytes, &offset),
        };
    }

    const probes = try allocator.alloc(cell.LightProbeMeta, probe_count);
    errdefer allocator.free(probes);
    for (probes) |*entry| {
        entry.* = .{
            .position = try readVec3(bytes, &offset),
            .intensity = try readF32(bytes, &offset),
        };
    }

    const neighbors = try allocator.alloc(cell.CellId, neighbor_count);
    errdefer allocator.free(neighbors);
    for (neighbors) |*entry| {
        entry.* = .{
            .x = try readI32(bytes, &offset),
            .y = try readI32(bytes, &offset),
            .z = try readI32(bytes, &offset),
        };
    }

    const nav_vertices = try allocator.alloc(core.math.Vec3f, nav_vertex_count);
    errdefer allocator.free(nav_vertices);
    for (nav_vertices) |*entry| {
        entry.* = try readVec3(bytes, &offset);
    }

    const nav_indices = try allocator.alloc(u32, nav_index_count);
    errdefer allocator.free(nav_indices);
    for (nav_indices) |*entry| {
        entry.* = try readU32(bytes, &offset);
    }

    const visibility = try allocator.alloc(cell.VisibilityLink, visibility_count);
    errdefer allocator.free(visibility);
    for (visibility) |*entry| {
        entry.* = .{
            .target = .{
                .x = try readI32(bytes, &offset),
                .y = try readI32(bytes, &offset),
                .z = try readI32(bytes, &offset),
            },
            .min = try readVec3(bytes, &offset),
            .max = try readVec3(bytes, &offset),
        };
    }

    const dependencies = try allocator.alloc(cell.CellDependency, dependency_count);
    errdefer allocator.free(dependencies);
    var dependency_index: usize = 0;
    errdefer {
        for (dependencies[0..dependency_index]) |*dependency| dependency.deinit(allocator);
    }
    while (dependency_index < dependency_count) : (dependency_index += 1) {
        const kind = try readString(allocator, bytes, &offset);
        errdefer allocator.free(kind);
        const path = try readString(allocator, bytes, &offset);
        errdefer allocator.free(path);
        dependencies[dependency_index] = .{
            .kind = kind,
            .path = path,
        };
    }

    const prop_instances = try allocator.alloc(cell.PropInstanceRecord, prop_instance_count);
    errdefer allocator.free(prop_instances);
    var prop_instance_index: usize = 0;
    errdefer {
        for (prop_instances[0..prop_instance_index]) |*instance| instance.deinit(allocator);
    }
    while (prop_instance_index < prop_instance_count) : (prop_instance_index += 1) {
        const instance_id = try readU64(bytes, &offset);
        const prop_asset_id = try readString(allocator, bytes, &offset);
        errdefer allocator.free(prop_asset_id);
        const variant = try readU32(bytes, &offset);
        const position = try readVec3(bytes, &offset);
        const rotation = try readVec3(bytes, &offset);
        const scale = try readVec3(bytes, &offset);
        var color: [4]u8 = undefined;
        for (&color) |*component| component.* = try readByte(bytes, &offset);
        prop_instances[prop_instance_index] = .{
            .instance_id = instance_id,
            .prop_asset_id = prop_asset_id,
            .variant = variant,
            .position = position,
            .rotation = rotation,
            .scale = scale,
            .base_color = .{ .r = color[0], .g = color[1], .b = color[2], .a = color[3] },
            .interactable = (try readByte(bytes, &offset)) != 0,
        };
    }

    const blobs = try allocator.alloc(cell.CellBlob, blob_count);
    errdefer allocator.free(blobs);
    var blob_index: usize = 0;
    errdefer {
        for (blobs[0..blob_index]) |*blob| blob.deinit(allocator);
    }
    while (blob_index < blob_count) : (blob_index += 1) {
        const kind = try readString(allocator, bytes, &offset);
        errdefer allocator.free(kind);
        const payload_len: usize = @intCast(try readU32(bytes, &offset));
        if (offset + payload_len > bytes.len) return error.InvalidCellFormat;
        const payload = try allocator.dupe(u8, bytes[offset .. offset + payload_len]);
        errdefer allocator.free(payload);
        offset += payload_len;
        blobs[blob_index] = .{
            .kind = kind,
            .payload = payload,
        };
    }

    if (offset != bytes.len) return error.InvalidCellFormat;
    return .{
        .id = id,
        .cell_size_m = cell_size_m,
        .render_meshes = meshes,
        .collisions = collisions,
        .collision_shapes = collision_shapes,
        .instances = instances,
        .light_probes = probes,
        .neighbors = neighbors,
        .nav_vertices = nav_vertices,
        .nav_indices = nav_indices,
        .visibility = visibility,
        .dependencies = dependencies,
        .prop_instances = prop_instances,
        .blobs = blobs,
    };
}

fn appendU32(list: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u32) !void {
    var buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &buf, value, .little);
    try list.appendSlice(allocator, &buf);
}

fn appendU64(list: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u64) !void {
    var buf: [8]u8 = undefined;
    std.mem.writeInt(u64, &buf, value, .little);
    try list.appendSlice(allocator, &buf);
}

fn appendI32(list: *std.ArrayList(u8), allocator: std.mem.Allocator, value: i32) !void {
    var buf: [4]u8 = undefined;
    std.mem.writeInt(i32, &buf, value, .little);
    try list.appendSlice(allocator, &buf);
}

fn appendF32(list: *std.ArrayList(u8), allocator: std.mem.Allocator, value: f32) !void {
    const bits: u32 = @bitCast(value);
    try appendU32(list, allocator, bits);
}

fn appendString(list: *std.ArrayList(u8), allocator: std.mem.Allocator, value: []const u8) !void {
    try appendU32(list, allocator, @intCast(value.len));
    try list.appendSlice(allocator, value);
}

fn appendVec3(list: *std.ArrayList(u8), allocator: std.mem.Allocator, value: core.math.Vec3f) !void {
    try appendF32(list, allocator, value.x);
    try appendF32(list, allocator, value.y);
    try appendF32(list, allocator, value.z);
}

fn readU32(bytes: []const u8, offset: *usize) !u32 {
    if (offset.* + 4 > bytes.len) return error.InvalidCellFormat;
    const value = std.mem.readInt(u32, bytes[offset.*..][0..4], .little);
    offset.* += 4;
    return value;
}

fn readU64(bytes: []const u8, offset: *usize) !u64 {
    if (offset.* + 8 > bytes.len) return error.InvalidCellFormat;
    const value = std.mem.readInt(u64, bytes[offset.*..][0..8], .little);
    offset.* += 8;
    return value;
}

fn readI32(bytes: []const u8, offset: *usize) !i32 {
    if (offset.* + 4 > bytes.len) return error.InvalidCellFormat;
    const value = std.mem.readInt(i32, bytes[offset.*..][0..4], .little);
    offset.* += 4;
    return value;
}

fn readF32(bytes: []const u8, offset: *usize) !f32 {
    const bits = try readU32(bytes, offset);
    return @bitCast(bits);
}

fn readByte(bytes: []const u8, offset: *usize) !u8 {
    if (offset.* >= bytes.len) return error.InvalidCellFormat;
    const value = bytes[offset.*];
    offset.* += 1;
    return value;
}

fn readString(allocator: std.mem.Allocator, bytes: []const u8, offset: *usize) ![]u8 {
    const len: usize = @intCast(try readU32(bytes, offset));
    if (offset.* + len > bytes.len) return error.InvalidCellFormat;
    const value = try allocator.dupe(u8, bytes[offset.* .. offset.* + len]);
    offset.* += len;
    return value;
}

fn readVec3(bytes: []const u8, offset: *usize) !core.math.Vec3f {
    return .{
        .x = try readF32(bytes, offset),
        .y = try readF32(bytes, offset),
        .z = try readF32(bytes, offset),
    };
}

fn readCollisionShapeKind(bytes: []const u8, offset: *usize) !cell.CollisionShapeKind {
    const value = try readByte(bytes, offset);
    return switch (value) {
        @intFromEnum(cell.CollisionShapeKind.aabb) => .aabb,
        @intFromEnum(cell.CollisionShapeKind.sphere) => .sphere,
        @intFromEnum(cell.CollisionShapeKind.heightfield) => .heightfield,
        else => error.InvalidCellFormat,
    };
}

fn readExact(bytes: []const u8, offset: *usize, out: []u8) !void {
    if (offset.* + out.len > bytes.len) return error.InvalidCellFormat;
    @memcpy(out, bytes[offset.* .. offset.* + out.len]);
    offset.* += out.len;
}

test "fcell binary round trip" {
    const vertices = try std.testing.allocator.alloc(cell.RenderVertex, 1);
    defer std.testing.allocator.free(vertices);
    vertices[0] = .{
        .position = .{ .x = 1, .y = 2, .z = 3 },
        .normal = .{ .x = 0, .y = 1, .z = 0 },
        .uv = .{ .x = 0.5, .y = 0.25 },
    };
    const indices = try std.testing.allocator.dupe(u32, &.{0});
    defer std.testing.allocator.free(indices);
    const texture = try std.testing.allocator.dupe(u8, &.{ 1, 2, 3, 4 });
    defer std.testing.allocator.free(texture);

    const mesh = cell.RenderMesh{
        .name = try std.testing.allocator.dupe(u8, "box"),
        .vertices = try std.testing.allocator.dupe(cell.RenderVertex, vertices),
        .indices = try std.testing.allocator.dupe(u32, indices),
        .texture = try std.testing.allocator.dupe(u8, texture),
        .base_color = .{ .r = 10, .g = 20, .b = 30, .a = 255 },
        .position = .{ .x = 0, .y = 0.5, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
    };

    const meshes = try std.testing.allocator.alloc(cell.RenderMesh, 1);
    meshes[0] = mesh;

    var world_cell = cell.WorldCellData{
        .id = .{ .x = 0, .y = 0, .z = 0 },
        .cell_size_m = 256.0,
        .render_meshes = meshes,
        .collisions = try std.testing.allocator.dupe(cell.CollisionPlaceholder, &.{.{
            .min = .{ .x = -0.5, .y = 0, .z = -0.5 },
            .max = .{ .x = 0.5, .y = 1, .z = 0.5 },
        }}),
        .collision_shapes = try std.testing.allocator.dupe(cell.CollisionShape, &.{.{
            .kind = .aabb,
            .min = .{ .x = -0.5, .y = 0, .z = -0.5 },
            .max = .{ .x = 0.5, .y = 1, .z = 0.5 },
        }}),
        .instances = try std.testing.allocator.dupe(cell.InstanceRecord, &.{.{
            .mesh_index = 0,
            .position = .{ .x = 0, .y = 0.5, .z = 0 },
            .scale = .{ .x = 1, .y = 1, .z = 1 },
        }}),
        .light_probes = try std.testing.allocator.dupe(cell.LightProbeMeta, &.{.{
            .position = .{ .x = 0, .y = 2, .z = 0 },
            .intensity = 1.0,
        }}),
        .neighbors = try std.testing.allocator.dupe(cell.CellId, &.{.{ .x = 1, .y = 0, .z = 0 }}),
        .nav_vertices = try std.testing.allocator.dupe(core.math.Vec3f, &.{
            .{ .x = 0, .y = 0, .z = 0 },
            .{ .x = 1, .y = 0, .z = 0 },
            .{ .x = 0, .y = 0, .z = 1 },
        }),
        .nav_indices = try std.testing.allocator.dupe(u32, &.{ 0, 1, 2 }),
        .visibility = try std.testing.allocator.dupe(cell.VisibilityLink, &.{.{
            .target = .{ .x = 1, .y = 0, .z = 0 },
            .min = .{ .x = 0, .y = 0, .z = 0 },
            .max = .{ .x = 1, .y = 2, .z = 1 },
        }}),
        .dependencies = try std.testing.allocator.dupe(cell.CellDependency, &.{.{
            .kind = try std.testing.allocator.dupe(u8, "mesh"),
            .path = try std.testing.allocator.dupe(u8, "world/object/1/mesh"),
        }}),
        .prop_instances = try std.testing.allocator.dupe(cell.PropInstanceRecord, &.{.{
            .instance_id = 42,
            .prop_asset_id = try std.testing.allocator.dupe(u8, "crate_wood"),
            .variant = 2,
            .position = .{ .x = 3, .y = 0.5, .z = 4 },
            .scale = .{ .x = 1, .y = 2, .z = 1 },
            .base_color = .{ .r = 100, .g = 110, .b = 120, .a = 255 },
            .interactable = true,
        }}),
        .blobs = try std.testing.allocator.dupe(cell.CellBlob, &.{.{
            .kind = try std.testing.allocator.dupe(u8, "test.blob"),
            .payload = try std.testing.allocator.dupe(u8, "{ \"ok\": true }"),
        }}),
    };
    defer world_cell.deinit(std.testing.allocator);

    const encoded = try encodeCell(std.testing.allocator, world_cell);
    defer std.testing.allocator.free(encoded);

    var decoded = try decodeCell(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), decoded.render_meshes.len);
    try std.testing.expectEqualStrings("box", decoded.render_meshes[0].name);
    try std.testing.expectEqual(@as(usize, 1), decoded.collision_shapes.len);
    try std.testing.expectEqual(cell.CollisionShapeKind.aabb, decoded.collision_shapes[0].kind);
    try std.testing.expectEqual(@as(usize, 1), decoded.instances.len);
    try std.testing.expectEqual(@as(i32, 1), decoded.neighbors[0].x);
    try std.testing.expectEqual(@as(usize, 3), decoded.nav_vertices.len);
    try std.testing.expectEqual(@as(usize, 3), decoded.nav_indices.len);
    try std.testing.expectEqual(@as(usize, 1), decoded.visibility.len);
    try std.testing.expectEqual(@as(usize, 1), decoded.dependencies.len);
    try std.testing.expectEqualStrings("world/object/1/mesh", decoded.dependencies[0].path);
    try std.testing.expectEqual(@as(usize, 1), decoded.prop_instances.len);
    try std.testing.expectEqualStrings("crate_wood", decoded.prop_instances[0].prop_asset_id);
    try std.testing.expectEqual(@as(u32, 2), decoded.prop_instances[0].variant);
    try std.testing.expect(decoded.prop_instances[0].interactable);
    try std.testing.expectEqual(@as(usize, 1), decoded.blobs.len);
    try std.testing.expectEqualStrings("test.blob", decoded.blobs[0].kind);
}
