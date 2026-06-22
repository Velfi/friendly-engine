const std = @import("std");
const friendly_engine = @import("friendly_engine");
const editor_math = @import("editor_math.zig");
const render_commands = @import("render_commands.zig");

const cell = friendly_engine.world.cell;
const Vec3 = friendly_engine.core.math.Vec3f;

pub const Bounds = struct {
    min: Vec3,
    max: Vec3,

    pub fn center(self: Bounds) Vec3 {
        return .{
            .x = (self.min.x + self.max.x) * 0.5,
            .y = (self.min.y + self.max.y) * 0.5,
            .z = (self.min.z + self.max.z) * 0.5,
        };
    }
};

pub const VisibilityStats = struct {
    active_cells: usize = 0,
    visible_cells: usize = 0,
    culled_cells: usize = 0,
    visible_meshes: usize = 0,
    emitted_batches: usize = 0,
};

pub const SceneMesh = struct {
    transform: [16]f32,
    bounds: Bounds,
    cast_shadows: bool = true,
    receive_shadows: bool = true,
    shading: render_commands.MeshShadingMode = .rendered,
    double_sided: bool = false,
    projection_mode: editor_math.ProjectionMode = .perspective,
    surface: render_commands.MeshSurfaceKind = .@"opaque",
};

pub const ViewInput = struct {
    camera: editor_math.OrbitCamera,
    max_distance: f32 = editor_math.editor_camera_far_m,
};

pub fn prepareSceneMeshes(
    command_buffer: *render_commands.CommandBuffer,
    meshes: []const SceneMesh,
    view: ViewInput,
) !VisibilityStats {
    var stats = VisibilityStats{ .active_cells = 1, .visible_cells = 1 };
    const eye = view.camera.eye();
    for (meshes, 0..) |mesh, index| {
        try validateBounds(mesh.bounds);
        if (!withinDistance(mesh.bounds, eye, view.max_distance)) continue;
        const depth = depthBucket(mesh.bounds, eye);
        if (mesh.surface == .water) {
            try command_buffer.appendWaterMesh(index, mesh, view.camera, depth);
        } else {
            try command_buffer.appendSceneMesh(index, mesh, view.camera, depth);
        }
        stats.visible_meshes += 1;
        stats.emitted_batches += 1;
    }
    if (stats.visible_meshes == 0) {
        stats.visible_cells = 0;
        stats.culled_cells = 1;
    }
    return stats;
}

pub fn prepareWorldCells(
    command_buffer: *render_commands.CommandBuffer,
    cells: []const *const cell.WorldCellData,
    view: ViewInput,
) !VisibilityStats {
    var stats = VisibilityStats{ .active_cells = cells.len };
    const eye = view.camera.eye();
    var mesh_index: usize = 0;
    for (cells) |world_cell| {
        const cell_bounds = cellBounds(world_cell);
        try validateBounds(cell_bounds);
        if (!withinDistance(cell_bounds, eye, view.max_distance)) {
            stats.culled_cells += 1;
            mesh_index += world_cell.render_meshes.len;
            continue;
        }
        stats.visible_cells += 1;
        for (world_cell.render_meshes) |mesh| {
            const mesh_bounds = renderMeshBounds(mesh);
            try validateBounds(mesh_bounds);
            if (!withinDistance(mesh_bounds, eye, view.max_distance)) {
                mesh_index += 1;
                continue;
            }
            const transform = editor_math.Mat4.mul(
                editor_math.Mat4.translation(mesh.position),
                editor_math.Mat4.scale(mesh.scale),
            );
            try command_buffer.appendMesh(mesh_index, transform.m, view.camera, depthBucket(mesh_bounds, eye));
            stats.visible_meshes += 1;
            stats.emitted_batches += 1;
            mesh_index += 1;
        }
    }
    return stats;
}

pub fn boundsFromTransform(transform: [16]f32) Bounds {
    const center: Vec3 = .{ .x = transform[12], .y = transform[13], .z = transform[14] };
    const extent: Vec3 = .{
        .x = @max(0.01, @abs(transform[0]) * 0.75),
        .y = @max(0.01, @abs(transform[5]) * 0.75),
        .z = @max(0.01, @abs(transform[10]) * 0.75),
    };
    return .{
        .min = .{ .x = center.x - extent.x, .y = center.y - extent.y, .z = center.z - extent.z },
        .max = .{ .x = center.x + extent.x, .y = center.y + extent.y, .z = center.z + extent.z },
    };
}

fn cellBounds(world_cell: *const cell.WorldCellData) Bounds {
    const raw = cell.boundsForCell(world_cell.id, world_cell.cell_size_m, cell.default_cell_height_m);
    return .{ .min = raw.min, .max = raw.max };
}

fn renderMeshBounds(mesh: cell.RenderMesh) Bounds {
    var bounds = Bounds{
        .min = .{
            .x = std.math.inf(f32),
            .y = std.math.inf(f32),
            .z = std.math.inf(f32),
        },
        .max = .{
            .x = -std.math.inf(f32),
            .y = -std.math.inf(f32),
            .z = -std.math.inf(f32),
        },
    };
    for (mesh.vertices) |vertex| {
        const p = Vec3{
            .x = mesh.position.x + vertex.position.x * mesh.scale.x,
            .y = mesh.position.y + vertex.position.y * mesh.scale.y,
            .z = mesh.position.z + vertex.position.z * mesh.scale.z,
        };
        bounds.min.x = @min(bounds.min.x, p.x);
        bounds.min.y = @min(bounds.min.y, p.y);
        bounds.min.z = @min(bounds.min.z, p.z);
        bounds.max.x = @max(bounds.max.x, p.x);
        bounds.max.y = @max(bounds.max.y, p.y);
        bounds.max.z = @max(bounds.max.z, p.z);
    }
    if (mesh.vertices.len == 0) {
        bounds.min = mesh.position;
        bounds.max = mesh.position;
    }
    return bounds;
}

fn validateBounds(bounds: Bounds) !void {
    if (!finiteVec3(bounds.min) or !finiteVec3(bounds.max)) return error.InvalidVisibilityBounds;
    if (bounds.min.x > bounds.max.x or bounds.min.y > bounds.max.y or bounds.min.z > bounds.max.z) {
        return error.InvalidVisibilityBounds;
    }
}

fn finiteVec3(v: Vec3) bool {
    return std.math.isFinite(v.x) and std.math.isFinite(v.y) and std.math.isFinite(v.z);
}

fn withinDistance(bounds: Bounds, eye: Vec3, max_distance: f32) bool {
    const c = bounds.center();
    const dx = c.x - eye.x;
    const dy = c.y - eye.y;
    const dz = c.z - eye.z;
    return dx * dx + dy * dy + dz * dz <= max_distance * max_distance;
}

fn depthBucket(bounds: Bounds, eye: Vec3) u16 {
    const c = bounds.center();
    const dx = c.x - eye.x;
    const dy = c.y - eye.y;
    const dz = c.z - eye.z;
    const distance = @sqrt(dx * dx + dy * dy + dz * dz);
    return @intFromFloat(@min(@as(f32, std.math.maxInt(u16)), distance * 16.0));
}

test "scene mesh flags propagate into draw commands" {
    var commands = render_commands.CommandBuffer.init(std.testing.allocator);
    defer commands.deinit();

    const transform = editor_math.Mat4.translation(.{ .x = 0, .y = 0, .z = 0 }).m;
    const meshes = [_]SceneMesh{.{
        .transform = transform,
        .bounds = boundsFromTransform(transform),
        .cast_shadows = false,
        .receive_shadows = false,
        .shading = .material_preview,
        .double_sided = true,
    }};
    _ = try prepareSceneMeshes(&commands, &meshes, .{ .camera = .{} });
    try std.testing.expectEqual(@as(usize, 1), commands.stats().meshes);
    const draw = commands.entries.items[0].command.mesh;
    try std.testing.expect(!draw.cast_shadows);
    try std.testing.expect(!draw.receive_shadows);
    try std.testing.expectEqual(render_commands.MeshShadingMode.material_preview, draw.shading);
    try std.testing.expect(draw.double_sided);
}

test "scene visibility emits mesh commands by distance" {
    var commands = render_commands.CommandBuffer.init(std.testing.allocator);
    defer commands.deinit();

    const near = editor_math.Mat4.translation(.{ .x = 0, .y = 0, .z = 0 }).m;
    const far = editor_math.Mat4.translation(.{ .x = 1000, .y = 0, .z = 0 }).m;
    const meshes = [_]SceneMesh{
        .{ .transform = near, .bounds = boundsFromTransform(near) },
        .{ .transform = far, .bounds = boundsFromTransform(far) },
    };
    const stats = try prepareSceneMeshes(&commands, &meshes, .{ .camera = .{}, .max_distance = 64 });
    try std.testing.expectEqual(@as(usize, 1), stats.visible_meshes);
    try std.testing.expectEqual(@as(usize, 1), commands.stats().meshes);
}

test "visibility rejects inverted bounds" {
    var commands = render_commands.CommandBuffer.init(std.testing.allocator);
    defer commands.deinit();

    const meshes = [_]SceneMesh{.{
        .transform = editor_math.Mat4.identity().m,
        .bounds = .{
            .min = .{ .x = 1, .y = 0, .z = 0 },
            .max = .{ .x = 0, .y = 0, .z = 0 },
        },
    }};
    try std.testing.expectError(error.InvalidVisibilityBounds, prepareSceneMeshes(&commands, &meshes, .{ .camera = .{} }));
}
