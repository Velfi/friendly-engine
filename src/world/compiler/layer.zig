const std = @import("std");
const core = @import("../../core/mod.zig");
const cell = @import("../cell.zig");
const manifest = @import("../manifest.zig");

pub const CompileContext = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    target: []const u8,
    manifest_path: []const u8,
    loaded_manifest: *const manifest.OwnedWorldManifest,
};

pub const CellLayerOutput = struct {
    render_meshes: []cell.RenderMesh = &.{},
    collisions: []cell.CollisionPlaceholder = &.{},
    collision_shapes: []cell.CollisionShape = &.{},
    instances: []cell.InstanceRecord = &.{},
    light_probes: []cell.LightProbeMeta = &.{},
    neighbors: []cell.CellId = &.{},
    nav_vertices: []core.math.Vec3f = &.{},
    nav_indices: []u32 = &.{},
    visibility: []cell.VisibilityLink = &.{},
    dependencies: []cell.CellDependency = &.{},
    prop_instances: []cell.PropInstanceRecord = &.{},
    blobs: []cell.CellBlob = &.{},

    pub fn deinit(self: *CellLayerOutput, allocator: std.mem.Allocator) void {
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
        self.* = .{};
    }
};

pub const AffectedCellsFn = *const fn (
    ctx: ?*anyopaque,
    compile_ctx: *const CompileContext,
    allocator: std.mem.Allocator,
) anyerror![]cell.CellId;

pub const CompileCellFn = *const fn (
    ctx: ?*anyopaque,
    compile_ctx: *const CompileContext,
    id: cell.CellId,
    allocator: std.mem.Allocator,
) anyerror!CellLayerOutput;

pub const WorldCompilerLayer = struct {
    name: []const u8,
    ctx: ?*anyopaque = null,
    affected_cells: AffectedCellsFn,
    compile_cell: CompileCellFn,
};

pub fn duplicateCellIds(
    allocator: std.mem.Allocator,
    ids: []const cell.CellId,
) ![]cell.CellId {
    return allocator.dupe(cell.CellId, ids);
}

pub fn appendBlobJson(
    allocator: std.mem.Allocator,
    list: *std.ArrayList(cell.CellBlob),
    kind: []const u8,
    payload: anytype,
) !void {
    const payload_bytes = try std.fmt.allocPrint(
        allocator,
        "{f}",
        .{std.json.fmt(payload, .{})},
    );
    errdefer allocator.free(payload_bytes);
    try list.append(allocator, .{
        .kind = try allocator.dupe(u8, kind),
        .payload = payload_bytes,
    });
}

test "appendBlobJson writes blob payload" {
    var blobs = std.ArrayList(cell.CellBlob).empty;
    defer {
        for (blobs.items) |*blob| blob.deinit(std.testing.allocator);
        blobs.deinit(std.testing.allocator);
    }

    try appendBlobJson(std.testing.allocator, &blobs, "layer.test", .{ .value = 7 });
    try std.testing.expectEqual(@as(usize, 1), blobs.items.len);
    try std.testing.expectEqualStrings("layer.test", blobs.items[0].kind);
    try std.testing.expect(std.mem.indexOf(u8, blobs.items[0].payload, "\"value\":7") != null);
}
