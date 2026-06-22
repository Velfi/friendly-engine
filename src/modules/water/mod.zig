const std = @import("std");
const core = @import("../../core/mod.zig");
const framework = @import("../../framework/mod.zig");
const world = @import("../../world/mod.zig");
const types = @import("types.zig");
const storage = @import("storage.zig");
const authoring_mod = @import("authoring.zig");
const runtime_mod = @import("runtime.zig");

pub const module_name = "gem.water";
const layer_name = "world.layer.water";

pub const WaterKind = types.WaterKind;
pub const WaterVolume = types.WaterVolume;
pub const WaterDoc = types.WaterDoc;
pub const WaterQuery = types.WaterQuery;
pub const kindFromName = types.kindFromName;
pub const queryPoint = types.queryPoint;
pub const pointInPolygon = types.pointInPolygon;
pub const bounds = types.bounds;
pub const validateDoc = types.validateDoc;
pub const validateVolume = types.validateVolume;
pub const parsePoints = storage.parsePoints;
pub const authoring = authoring_mod;
pub const runtime = runtime_mod;

pub fn register(registry: anytype) !void {
    try registry.registerWorldCompilerLayer(.{
        .name = layer_name,
        .affected_cells = affectedCells,
        .compile_cell = compileCell,
    });
}

pub fn start(engine_world: *framework.World) !void {
    try engine_world.notifications.publish("gem.water.started", "{}");
}

pub fn stop(engine_world: *framework.World) !void {
    try engine_world.notifications.publish("gem.water.stopped", "{}");
}

fn affectedCells(_: ?*anyopaque, compile_ctx: *const world.compiler.layer.CompileContext, allocator: std.mem.Allocator) ![]world.cell.CellId {
    var doc = try storage.loadProject(allocator, compile_ctx.io, compile_ctx.project_path, compile_ctx.manifest_path);
    defer doc.deinit(allocator);
    var ids = std.ArrayList(world.cell.CellId).empty;
    errdefer ids.deinit(allocator);
    for (doc.volumes) |volume| {
        const b = types.bounds(volume);
        const min_id = world.cell.idAtPosition(b.min_x, b.min_z, volume.bottom_y, compile_ctx.loaded_manifest.cell_size_m, world.cell.default_cell_height_m, false);
        const max_id = world.cell.idAtPosition(b.max_x, b.max_z, volume.surface_y, compile_ctx.loaded_manifest.cell_size_m, world.cell.default_cell_height_m, false);
        var x = min_id.x;
        while (x <= max_id.x) : (x += 1) {
            var y = min_id.y;
            while (y <= max_id.y) : (y += 1) {
                const id = world.cell.CellId{ .x = x, .y = y, .z = 0 };
                if (!compile_ctx.loaded_manifest.hasCell(id)) continue;
                if (!containsCell(ids.items, id)) try ids.append(allocator, id);
            }
        }
    }
    return ids.toOwnedSlice(allocator);
}

fn compileCell(_: ?*anyopaque, compile_ctx: *const world.compiler.layer.CompileContext, id: world.cell.CellId, allocator: std.mem.Allocator) !world.compiler.layer.CellLayerOutput {
    var doc = try storage.loadProject(allocator, compile_ctx.io, compile_ctx.project_path, compile_ctx.manifest_path);
    defer doc.deinit(allocator);
    var cell_volumes = std.ArrayList(types.WaterVolume).empty;
    errdefer {
        for (cell_volumes.items) |*volume| volume.deinit(allocator);
        cell_volumes.deinit(allocator);
    }
    for (doc.volumes) |volume| {
        if (volumeAffectsCell(volume, id, compile_ctx.loaded_manifest.cell_size_m)) {
            try cell_volumes.append(allocator, try types.WaterVolume.duplicate(allocator, volume));
        }
    }
    if (cell_volumes.items.len == 0) return .{};
    const owned_volumes = try cell_volumes.toOwnedSlice(allocator);
    var cell_doc = types.WaterDoc{ .volumes = owned_volumes };
    defer cell_doc.deinit(allocator);

    var blobs = std.ArrayList(world.cell.CellBlob).empty;
    errdefer {
        for (blobs.items) |*blob| blob.deinit(allocator);
        blobs.deinit(allocator);
    }
    const blob_payload = try authoring_mod.formatKdl(allocator, cell_doc);
    errdefer allocator.free(blob_payload);
    try blobs.append(allocator, .{
        .kind = try allocator.dupe(u8, runtime_mod.blob_kind),
        .payload = blob_payload,
    });

    var render_meshes = std.ArrayList(world.cell.RenderMesh).empty;
    errdefer {
        for (render_meshes.items) |*mesh| mesh.deinit(allocator);
        render_meshes.deinit(allocator);
    }
    for (owned_volumes) |volume| {
        try render_meshes.append(allocator, try surfaceMesh(allocator, volume));
    }

    return .{
        .render_meshes = try render_meshes.toOwnedSlice(allocator),
        .blobs = try blobs.toOwnedSlice(allocator),
    };
}

fn volumeAffectsCell(volume: types.WaterVolume, id: world.cell.CellId, cell_size_m: f32) bool {
    const b = types.bounds(volume);
    const min_x = @as(f32, @floatFromInt(id.x)) * cell_size_m;
    const min_z = @as(f32, @floatFromInt(id.y)) * cell_size_m;
    const max_x = min_x + cell_size_m;
    const max_z = min_z + cell_size_m;
    return b.max_x >= min_x and b.min_x <= max_x and b.max_z >= min_z and b.min_z <= max_z;
}

fn containsCell(ids: []const world.cell.CellId, id: world.cell.CellId) bool {
    for (ids) |existing| if (existing.eql(id)) return true;
    return false;
}

fn surfaceMesh(allocator: std.mem.Allocator, volume: types.WaterVolume) !world.cell.RenderMesh {
    const vertex_count = volume.points.len;
    const index_count = (vertex_count - 2) * 3;
    var vertices = try allocator.alloc(world.cell.RenderVertex, vertex_count);
    errdefer allocator.free(vertices);
    var indices = try allocator.alloc(u32, index_count);
    errdefer allocator.free(indices);
    const b = types.bounds(volume);
    const width = @max(1.0, b.max_x - b.min_x);
    const depth = @max(1.0, b.max_z - b.min_z);
    for (volume.points, 0..) |point, index| {
        vertices[index] = .{
            .position = .{ .x = point[0], .y = volume.surface_y, .z = point[1] },
            .normal = .{ .x = 0, .y = 1, .z = 0 },
            .uv = .{ .x = (point[0] - b.min_x) / width, .y = (point[1] - b.min_z) / depth },
        };
    }
    var out: usize = 0;
    var i: usize = 1;
    while (i + 1 < vertex_count) : (i += 1) {
        indices[out] = 0;
        indices[out + 1] = @intCast(i + 1);
        indices[out + 2] = @intCast(i);
        out += 3;
    }
    return .{
        .name = try std.fmt.allocPrint(allocator, "water.{s}", .{volume.id}),
        .vertices = vertices,
        .indices = indices,
        .texture = try allocator.dupe(u8, volume.material),
        .base_color = waterColor(volume.kind),
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
    };
}

fn waterColor(kind: types.WaterKind) world.cell.CellColor {
    return switch (kind) {
        .ocean_near => .{ .r = 45, .g = 145, .b = 185, .a = 185 },
        .lake => .{ .r = 42, .g = 130, .b = 165, .a = 185 },
        .pond => .{ .r = 55, .g = 150, .b = 135, .a = 185 },
        .river => .{ .r = 60, .g = 155, .b = 190, .a = 185 },
        .interior => .{ .r = 38, .g = 110, .b = 135, .a = 180 },
    };
}

test "affected cells includes volume bbox cells" {
    const volume = types.WaterVolume{
        .id = @constCast("pond"),
        .material = @constCast("water.pond.clear"),
        .surface_y = 1,
        .bottom_y = -2,
        .points = @constCast(&[_][2]f32{ .{ 0, 0 }, .{ 300, 0 }, .{ 300, 20 }, .{ 0, 20 } }),
    };
    try std.testing.expect(volumeAffectsCell(volume, .{ .x = 1, .y = 0, .z = 0 }, 256));
    try std.testing.expect(!volumeAffectsCell(volume, .{ .x = 2, .y = 0, .z = 0 }, 256));
}

test "surface mesh triangles face upward" {
    const volume = types.WaterVolume{
        .id = @constCast("pond"),
        .material = @constCast("water.pond.clear"),
        .surface_y = 1,
        .bottom_y = -2,
        .points = @constCast(&[_][2]f32{ .{ 0, 0 }, .{ 4, 0 }, .{ 4, 4 }, .{ 0, 4 } }),
    };
    var mesh = try surfaceMesh(std.testing.allocator, volume);
    defer mesh.deinit(std.testing.allocator);

    const a = mesh.vertices[mesh.indices[0]].position;
    const b = mesh.vertices[mesh.indices[1]].position;
    const c = mesh.vertices[mesh.indices[2]].position;
    const ab = core.math.Vec3f.sub(b, a);
    const ac = core.math.Vec3f.sub(c, a);
    const n = core.math.Vec3f.cross(ab, ac);
    try std.testing.expect(n.y > 0);
}
