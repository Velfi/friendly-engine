const std = @import("std");
const core = @import("../../core/mod.zig");
const framework = @import("../../framework/mod.zig");
const world = @import("../../world/mod.zig");
const kdl = @import("kdl");
const layer_kdl = @import("../layer_kdl.zig");

pub const authoring = @import("authoring.zig");
pub const deformation = @import("deformation.zig");
pub const road_mesh = @import("road_mesh.zig");

pub const module_name = "gem.splines";
const layer_name = "world.layer.splines";
const splines_layer_file = "layers/splines.kdl";
const road_edge_samples = 16;

pub const SplinesDoc = struct {
    schema_version: u32 = 2,
    road_nodes: []const RoadNodeDef = &.{},
    road_edges: []const RoadEdgeDef = &.{},
};

pub const RoadNodeDef = struct {
    id: []const u8,
    position: core.math.Vec3f,
    kind: authoring.RoadNodeKind = .endpoint,
    terrain_mode: authoring.RoadTerrainMode = .conform,
};

pub const RoadEdgeDef = struct {
    id: []const u8,
    start_node_id: []const u8,
    end_node_id: []const u8,
    handle_start: core.math.Vec3f,
    handle_end: core.math.Vec3f,
    width: f32,
    elevation: f32 = 0.02,
    material_mask_value: u8 = 255,
    render_mode: authoring.RoadRenderMode = .decal,
    terrain_mode: authoring.RoadTerrainMode = .conform,
    decal_material: []const u8 = "road.dirt",
    prop_asset_id: []const u8 = "",
};

pub fn register(registry: anytype) !void {
    try registry.registerWorldCompilerLayer(.{
        .name = layer_name,
        .affected_cells = affectedCells,
        .compile_cell = compileCell,
    });
}

pub fn start(engine_world: *framework.World) !void {
    try engine_world.notifications.publish("gem.splines.started", "{}");
}

pub fn stop(engine_world: *framework.World) !void {
    try engine_world.notifications.publish("gem.splines.stopped", "{}");
}

fn affectedCells(
    _: ?*anyopaque,
    compile_ctx: *const world.compiler.layer.CompileContext,
    allocator: std.mem.Allocator,
) ![]world.cell.CellId {
    var doc = try loadSplinesDoc(allocator, compile_ctx);
    defer doc.deinit();
    if (doc.value.road_edges.len == 0) return allocator.alloc(world.cell.CellId, 0);

    var lookup = std.AutoHashMap(world.cell.CellId, void).init(allocator);
    defer lookup.deinit();
    var cells = std.ArrayList(world.cell.CellId).empty;
    defer cells.deinit(allocator);

    for (compile_ctx.loaded_manifest.cells) |manifest_cell| {
        const bounds = world.cell.boundsForCell(manifest_cell.id, compile_ctx.loaded_manifest.cell_size_m, world.cell.default_cell_height_m);
        if (!try anyRoadIntersectsCell(doc.value, bounds)) continue;
        if (lookup.contains(manifest_cell.id)) continue;
        try lookup.put(manifest_cell.id, {});
        try cells.append(allocator, manifest_cell.id);
    }

    return cells.toOwnedSlice(allocator);
}

pub fn compileCell(
    _: ?*anyopaque,
    compile_ctx: *const world.compiler.layer.CompileContext,
    id: world.cell.CellId,
    allocator: std.mem.Allocator,
) !world.compiler.layer.CellLayerOutput {
    var doc = try loadSplinesDoc(allocator, compile_ctx);
    defer doc.deinit();

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

    const bounds = world.cell.boundsForCell(id, compile_ctx.loaded_manifest.cell_size_m, world.cell.default_cell_height_m);
    var crossed_roads = std.ArrayList([]const u8).empty;
    defer crossed_roads.deinit(allocator);

    for (doc.value.road_edges) |edge| {
        try validateRoadEdge(doc.value, edge);
        const start_node = findNode(doc.value, edge.start_node_id) orelse return error.MissingRoadNode;
        const end_node = findNode(doc.value, edge.end_node_id) orelse return error.MissingRoadNode;
        var segment_index: usize = 0;
        while (segment_index < road_edge_samples) : (segment_index += 1) {
            const a = sampleRoadEdge(start_node.position, edge.handle_start, edge.handle_end, end_node.position, @as(f32, @floatFromInt(segment_index)) / road_edge_samples);
            const b = sampleRoadEdge(start_node.position, edge.handle_start, edge.handle_end, end_node.position, @as(f32, @floatFromInt(segment_index + 1)) / road_edge_samples);
            if (!road_mesh.segmentIntersectsCell(a, b, bounds)) continue;
            if (edge.render_mode == .prop_sections) continue;

            const generated = try road_mesh.buildRoadSegmentMesh(allocator, edge.id, edge.width, edge.elevation, segment_index, a, b);
            try appendMeshNav(allocator, &nav_vertices, &nav_indices, generated.mesh.vertices, generated.mesh.indices);
            try collision_shapes.append(allocator, .{
                .kind = .aabb,
                .min = generated.collision.min,
                .max = generated.collision.max,
            });
            try meshes.append(allocator, generated.mesh);
            try collisions.append(allocator, generated.collision);
            if (edge.terrain_mode == .conform) try crossed_roads.append(allocator, edge.id);
        }
    }

    if (crossed_roads.items.len == 0) return .{
        .render_meshes = try meshes.toOwnedSlice(allocator),
        .collisions = try collisions.toOwnedSlice(allocator),
        .collision_shapes = try collision_shapes.toOwnedSlice(allocator),
        .nav_vertices = try nav_vertices.toOwnedSlice(allocator),
        .nav_indices = try nav_indices.toOwnedSlice(allocator),
    };
    try world.compiler.layer.appendBlobJson(allocator, &blobs, "terrain.deformation", .{
        .cell = .{ id.x, id.y, id.z },
        .roads = crossed_roads.items,
        .operation = "raise_to_road",
    });
    try world.compiler.layer.appendBlobJson(allocator, &blobs, "terrain.material_mask", .{
        .cell = .{ id.x, id.y, id.z },
        .roads = crossed_roads.items,
        .channel = "road",
    });

    return .{
        .render_meshes = try meshes.toOwnedSlice(allocator),
        .collisions = try collisions.toOwnedSlice(allocator),
        .collision_shapes = try collision_shapes.toOwnedSlice(allocator),
        .nav_vertices = try nav_vertices.toOwnedSlice(allocator),
        .nav_indices = try nav_indices.toOwnedSlice(allocator),
        .blobs = try blobs.toOwnedSlice(allocator),
    };
}

fn appendMeshNav(
    allocator: std.mem.Allocator,
    nav_vertices: *std.ArrayList(core.math.Vec3f),
    nav_indices: *std.ArrayList(u32),
    vertices: []const world.cell.RenderVertex,
    indices: []const u32,
) !void {
    const base: u32 = @intCast(nav_vertices.items.len);
    for (vertices) |vertex| try nav_vertices.append(allocator, vertex.position);
    for (indices) |index| try nav_indices.append(allocator, base + index);
}

fn anyRoadIntersectsCell(doc: SplinesDoc, bounds: world.cell.CellBounds) !bool {
    for (doc.road_edges) |edge| {
        try validateRoadEdge(doc, edge);
        const start_node = findNode(doc, edge.start_node_id) orelse return error.MissingRoadNode;
        const end_node = findNode(doc, edge.end_node_id) orelse return error.MissingRoadNode;
        var i: usize = 0;
        while (i < road_edge_samples) : (i += 1) {
            const a = sampleRoadEdge(start_node.position, edge.handle_start, edge.handle_end, end_node.position, @as(f32, @floatFromInt(i)) / road_edge_samples);
            const b = sampleRoadEdge(start_node.position, edge.handle_start, edge.handle_end, end_node.position, @as(f32, @floatFromInt(i + 1)) / road_edge_samples);
            if (road_mesh.segmentIntersectsCell(a, b, bounds)) return true;
        }
    }
    return false;
}

fn sampleRoadEdge(a: core.math.Vec3f, h0: core.math.Vec3f, h1: core.math.Vec3f, b: core.math.Vec3f, t: f32) core.math.Vec3f {
    const inv = 1.0 - t;
    const aa = inv * inv * inv;
    const bb = 3.0 * inv * inv * t;
    const cc = 3.0 * inv * t * t;
    const dd = t * t * t;
    return .{
        .x = a.x * aa + h0.x * bb + h1.x * cc + b.x * dd,
        .y = a.y * aa + h0.y * bb + h1.y * cc + b.y * dd,
        .z = a.z * aa + h0.z * bb + h1.z * cc + b.z * dd,
    };
}

fn findNode(doc: SplinesDoc, id: []const u8) ?RoadNodeDef {
    for (doc.road_nodes) |node| {
        if (std.mem.eql(u8, node.id, id)) return node;
    }
    return null;
}

pub fn validateRoadNode(node: RoadNodeDef) !void {
    if (node.id.len == 0) return error.InvalidRoadNode;
    if (!std.math.isFinite(node.position.x) or !std.math.isFinite(node.position.y) or !std.math.isFinite(node.position.z)) return error.InvalidRoadPoint;
}

pub fn validateRoadEdge(doc: SplinesDoc, edge: RoadEdgeDef) !void {
    if (edge.id.len == 0 or edge.start_node_id.len == 0 or edge.end_node_id.len == 0) return error.InvalidRoadEdge;
    if (std.mem.eql(u8, edge.start_node_id, edge.end_node_id)) return error.InvalidRoadEdge;
    if (findNode(doc, edge.start_node_id) == null or findNode(doc, edge.end_node_id) == null) return error.MissingRoadNode;
    if (!std.math.isFinite(edge.width) or edge.width <= 0) return error.InvalidRoadEdge;
    if (!std.math.isFinite(edge.elevation)) return error.InvalidRoadEdge;
    for ([_]core.math.Vec3f{ edge.handle_start, edge.handle_end }) |point| {
        if (!std.math.isFinite(point.x) or !std.math.isFinite(point.y) or !std.math.isFinite(point.z)) return error.InvalidRoadPoint;
    }
    const a = findNode(doc, edge.start_node_id).?.position;
    const b = findNode(doc, edge.end_node_id).?.position;
    const dx = b.x - a.x;
    const dz = b.z - a.z;
    if (@sqrt(dx * dx + dz * dz) <= 0.001) return error.InvalidRoadSegment;
}

fn loadSplinesDoc(
    allocator: std.mem.Allocator,
    compile_ctx: *const world.compiler.layer.CompileContext,
) !OwnedSplinesDoc {
    const path = try layerPath(allocator, compile_ctx.manifest_path);
    defer allocator.free(path);

    var project_dir = try openProjectDir(compile_ctx.io, compile_ctx.project_path);
    defer project_dir.close(compile_ctx.io);
    const bytes = try project_dir.readFileAlloc(compile_ctx.io, path, allocator, .limited(8 * 1024 * 1024));
    defer allocator.free(bytes);

    var parsed = try parseSplinesKdl(allocator, bytes);
    errdefer parsed.deinit();
    if (parsed.value.schema_version != 2) return error.UnsupportedSplineSchemaVersion;
    for (parsed.value.road_nodes) |node| try validateRoadNode(node);
    for (parsed.value.road_edges) |edge| try validateRoadEdge(parsed.value, edge);
    return parsed;
}

const OwnedSplinesDoc = struct {
    value: SplinesDoc,
    allocator: std.mem.Allocator,

    fn deinit(self: *OwnedSplinesDoc) void {
        for (self.value.road_nodes) |node| self.allocator.free(node.id);
        self.allocator.free(self.value.road_nodes);
        for (self.value.road_edges) |edge| {
            self.allocator.free(edge.id);
            self.allocator.free(edge.start_node_id);
            self.allocator.free(edge.end_node_id);
            self.allocator.free(edge.decal_material);
            self.allocator.free(edge.prop_asset_id);
        }
        self.allocator.free(self.value.road_edges);
    }
};

fn parseSplinesKdl(allocator: std.mem.Allocator, bytes: []const u8) !OwnedSplinesDoc {
    const buffer = try allocator.allocSentinel(u8, bytes.len, 0);
    defer allocator.free(buffer);
    @memcpy(buffer, bytes);

    var parser = kdl.Parser.init(buffer);
    var nodes = std.ArrayList(RoadNodeDef).empty;
    var edges = std.ArrayList(RoadEdgeDef).empty;
    errdefer {
        for (nodes.items) |node| allocator.free(node.id);
        nodes.deinit(allocator);
        for (edges.items) |edge| freeEdge(allocator, edge);
        edges.deinit(allocator);
    }

    var schema_version: u32 = 2;
    var depth: i32 = 0;
    var root_seen = false;
    var node_builder: ?RoadNodeBuilder = null;
    var edge_builder: ?RoadEdgeBuilder = null;
    errdefer {
        if (node_builder) |*node| node.deinit(allocator);
        if (edge_builder) |*edge| edge.deinit(allocator);
    }

    while (true) {
        const event = try parser.next();
        switch (event) {
            .node => |node| {
                if (depth == 0) {
                    if (root_seen or !std.mem.eql(u8, node.val, "splines")) return error.InvalidSplinesDocument;
                    root_seen = true;
                    continue;
                }
                if (depth == 1) {
                    try finishRuntimeBuilder(allocator, &nodes, &edges, &node_builder, &edge_builder);
                    if (std.mem.eql(u8, node.val, "road_node")) node_builder = .{} else if (std.mem.eql(u8, node.val, "road_edge")) edge_builder = .{} else return error.UnknownField;
                    continue;
                }
                return error.InvalidSplinesDocument;
            },
            .prop => |prop| {
                const value = try layer_kdl.decodeValue(allocator, prop.val);
                defer allocator.free(value);
                if (depth == 0) {
                    if (!std.mem.eql(u8, prop.key, "version")) return error.UnknownField;
                    schema_version = try std.fmt.parseInt(u32, value, 10);
                    if (schema_version != 2) return error.UnsupportedSplineSchemaVersion;
                    continue;
                }
                if (depth == 1) {
                    if (node_builder) |*node| try node.apply(allocator, prop.key, value) else if (edge_builder) |*edge| try edge.apply(allocator, prop.key, value) else return error.InvalidSplinesDocument;
                    continue;
                }
                return error.InvalidSplinesDocument;
            },
            .child_block_begin => depth += 1,
            .child_block_end => {
                if (depth == 1) try finishRuntimeBuilder(allocator, &nodes, &edges, &node_builder, &edge_builder);
                depth -= 1;
                if (depth < 0) return error.InvalidSplinesDocument;
            },
            .arg, .invalid => return error.InvalidSplinesDocument,
            .eof => break,
        }
    }
    try finishRuntimeBuilder(allocator, &nodes, &edges, &node_builder, &edge_builder);
    if (!root_seen or depth != 0) return error.InvalidSplinesDocument;
    return .{
        .allocator = allocator,
        .value = .{
            .schema_version = schema_version,
            .road_nodes = try nodes.toOwnedSlice(allocator),
            .road_edges = try edges.toOwnedSlice(allocator),
        },
    };
}

const RoadNodeBuilder = struct {
    id: ?[]u8 = null,
    position: ?core.math.Vec3f = null,
    kind: authoring.RoadNodeKind = .endpoint,
    terrain_mode: authoring.RoadTerrainMode = .conform,

    fn deinit(self: *RoadNodeBuilder, allocator: std.mem.Allocator) void {
        if (self.id) |value| allocator.free(value);
        self.* = .{};
    }

    fn apply(self: *RoadNodeBuilder, allocator: std.mem.Allocator, key: []const u8, value: []const u8) !void {
        if (std.mem.eql(u8, key, "id")) {
            if (self.id) |existing| allocator.free(existing);
            self.id = try allocator.dupe(u8, value);
        } else if (std.mem.eql(u8, key, "position")) {
            const row = try layer_kdl.parseF32Triple(value);
            self.position = .{ .x = row[0], .y = row[1], .z = row[2] };
        } else if (std.mem.eql(u8, key, "kind")) self.kind = try authoring.RoadNodeKind.parse(value) else if (std.mem.eql(u8, key, "terrain_mode")) self.terrain_mode = try authoring.RoadTerrainMode.parse(value) else return error.UnknownField;
    }

    fn finish(self: *RoadNodeBuilder) !RoadNodeDef {
        const id = self.id orelse return error.InvalidSplinesDocument;
        self.id = null;
        return .{
            .id = id,
            .position = self.position orelse return error.InvalidSplinesDocument,
            .kind = self.kind,
            .terrain_mode = self.terrain_mode,
        };
    }
};

const RoadEdgeBuilder = struct {
    id: ?[]u8 = null,
    start_node_id: ?[]u8 = null,
    end_node_id: ?[]u8 = null,
    handle_start: ?core.math.Vec3f = null,
    handle_end: ?core.math.Vec3f = null,
    width: ?f32 = null,
    elevation: f32 = 0.02,
    material_mask_value: u8 = 255,
    render_mode: authoring.RoadRenderMode = .decal,
    terrain_mode: authoring.RoadTerrainMode = .conform,
    decal_material: ?[]u8 = null,
    prop_asset_id: ?[]u8 = null,

    fn deinit(self: *RoadEdgeBuilder, allocator: std.mem.Allocator) void {
        if (self.id) |value| allocator.free(value);
        if (self.start_node_id) |value| allocator.free(value);
        if (self.end_node_id) |value| allocator.free(value);
        if (self.decal_material) |value| allocator.free(value);
        if (self.prop_asset_id) |value| allocator.free(value);
        self.* = .{};
    }

    fn apply(self: *RoadEdgeBuilder, allocator: std.mem.Allocator, key: []const u8, value: []const u8) !void {
        if (std.mem.eql(u8, key, "id")) {
            if (self.id) |existing| allocator.free(existing);
            self.id = try allocator.dupe(u8, value);
        } else if (std.mem.eql(u8, key, "start")) {
            if (self.start_node_id) |existing| allocator.free(existing);
            self.start_node_id = try allocator.dupe(u8, value);
        } else if (std.mem.eql(u8, key, "end")) {
            if (self.end_node_id) |existing| allocator.free(existing);
            self.end_node_id = try allocator.dupe(u8, value);
        } else if (std.mem.eql(u8, key, "handle_start")) {
            const row = try layer_kdl.parseF32Triple(value);
            self.handle_start = .{ .x = row[0], .y = row[1], .z = row[2] };
        } else if (std.mem.eql(u8, key, "handle_end")) {
            const row = try layer_kdl.parseF32Triple(value);
            self.handle_end = .{ .x = row[0], .y = row[1], .z = row[2] };
        } else if (std.mem.eql(u8, key, "width")) self.width = try std.fmt.parseFloat(f32, value) else if (std.mem.eql(u8, key, "elevation")) self.elevation = try std.fmt.parseFloat(f32, value) else if (std.mem.eql(u8, key, "material_mask_value")) self.material_mask_value = @intCast(try std.fmt.parseInt(u16, value, 10)) else if (std.mem.eql(u8, key, "render_mode")) self.render_mode = try authoring.RoadRenderMode.parse(value) else if (std.mem.eql(u8, key, "terrain_mode")) self.terrain_mode = try authoring.RoadTerrainMode.parse(value) else if (std.mem.eql(u8, key, "decal_material")) {
            if (self.decal_material) |existing| allocator.free(existing);
            self.decal_material = try allocator.dupe(u8, value);
        } else if (std.mem.eql(u8, key, "prop_asset_id")) {
            if (self.prop_asset_id) |existing| allocator.free(existing);
            self.prop_asset_id = try allocator.dupe(u8, value);
        } else return error.UnknownField;
    }

    fn finish(self: *RoadEdgeBuilder, allocator: std.mem.Allocator) !RoadEdgeDef {
        const id = self.id orelse return error.InvalidSplinesDocument;
        const start_id = self.start_node_id orelse return error.InvalidSplinesDocument;
        const end_id = self.end_node_id orelse return error.InvalidSplinesDocument;
        self.id = null;
        self.start_node_id = null;
        self.end_node_id = null;
        const decal = if (self.decal_material) |value| blk: {
            self.decal_material = null;
            break :blk value;
        } else try allocator.dupe(u8, "road.dirt");
        const prop = if (self.prop_asset_id) |value| blk: {
            self.prop_asset_id = null;
            break :blk value;
        } else try allocator.dupe(u8, "");
        return .{
            .id = id,
            .start_node_id = start_id,
            .end_node_id = end_id,
            .handle_start = self.handle_start orelse return error.InvalidSplinesDocument,
            .handle_end = self.handle_end orelse return error.InvalidSplinesDocument,
            .width = self.width orelse return error.InvalidSplinesDocument,
            .elevation = self.elevation,
            .material_mask_value = self.material_mask_value,
            .render_mode = self.render_mode,
            .terrain_mode = self.terrain_mode,
            .decal_material = decal,
            .prop_asset_id = prop,
        };
    }
};

fn finishRuntimeBuilder(
    allocator: std.mem.Allocator,
    nodes: *std.ArrayList(RoadNodeDef),
    edges: *std.ArrayList(RoadEdgeDef),
    node_builder: *?RoadNodeBuilder,
    edge_builder: *?RoadEdgeBuilder,
) !void {
    if (node_builder.*) |*node| {
        try nodes.append(allocator, try node.finish());
        node.deinit(allocator);
        node_builder.* = null;
    }
    if (edge_builder.*) |*edge| {
        try edges.append(allocator, try edge.finish(allocator));
        edge.deinit(allocator);
        edge_builder.* = null;
    }
}

fn freeEdge(allocator: std.mem.Allocator, edge: RoadEdgeDef) void {
    allocator.free(edge.id);
    allocator.free(edge.start_node_id);
    allocator.free(edge.end_node_id);
    allocator.free(edge.decal_material);
    allocator.free(edge.prop_asset_id);
}

fn layerPath(allocator: std.mem.Allocator, manifest_path: []const u8) ![]u8 {
    const dir = std.fs.path.dirname(manifest_path) orelse "";
    if (dir.len == 0) return allocator.dupe(u8, splines_layer_file);
    return std.fs.path.join(allocator, &.{ dir, splines_layer_file });
}

fn openProjectDir(io: std.Io, project_path: []const u8) !std.Io.Dir {
    if (std.fs.path.isAbsolute(project_path)) return std.Io.Dir.openDirAbsolute(io, project_path, .{});
    return std.Io.Dir.cwd().openDir(io, project_path, .{});
}

comptime {
    _ = @import("mod_tests.zig");
}
