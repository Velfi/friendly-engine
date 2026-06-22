const std = @import("std");
const kdl = @import("kdl");
const core = @import("../../core/mod.zig");
const layer_kdl = @import("../layer_kdl.zig");

const splines_layer_file = "layers/splines.kdl";
const max_splines_doc_bytes = 8 * 1024 * 1024;

pub const RoadNodeKind = enum {
    endpoint,
    junction,

    pub fn parse(value: []const u8) !RoadNodeKind {
        if (std.mem.eql(u8, value, "endpoint")) return .endpoint;
        if (std.mem.eql(u8, value, "junction")) return .junction;
        return error.InvalidRoadNodeKind;
    }

    pub fn name(self: RoadNodeKind) []const u8 {
        return switch (self) {
            .endpoint => "endpoint",
            .junction => "junction",
        };
    }
};

pub const RoadTerrainMode = enum {
    conform,
    floating,
    tunnel_reserved,

    pub fn parse(value: []const u8) !RoadTerrainMode {
        if (std.mem.eql(u8, value, "conform")) return .conform;
        if (std.mem.eql(u8, value, "floating")) return .floating;
        if (std.mem.eql(u8, value, "tunnel_reserved")) return .tunnel_reserved;
        return error.InvalidRoadTerrainMode;
    }

    pub fn name(self: RoadTerrainMode) []const u8 {
        return switch (self) {
            .conform => "conform",
            .floating => "floating",
            .tunnel_reserved => "tunnel_reserved",
        };
    }
};

pub const RoadRenderMode = enum {
    decal,
    prop_sections,

    pub fn parse(value: []const u8) !RoadRenderMode {
        if (std.mem.eql(u8, value, "decal")) return .decal;
        if (std.mem.eql(u8, value, "prop_sections")) return .prop_sections;
        return error.InvalidRoadRenderMode;
    }

    pub fn name(self: RoadRenderMode) []const u8 {
        return switch (self) {
            .decal => "decal",
            .prop_sections => "prop_sections",
        };
    }
};

pub const RoadNodeInput = struct {
    id: []const u8,
    position: core.math.Vec3f,
    kind: RoadNodeKind = .endpoint,
    terrain_mode: RoadTerrainMode = .conform,
};

pub const RoadEdgeInput = struct {
    id: []const u8,
    start_node_id: []const u8,
    end_node_id: []const u8,
    handle_start: core.math.Vec3f,
    handle_end: core.math.Vec3f,
    width: f32,
    elevation: f32 = 0.02,
    material_mask_value: u8 = 255,
    render_mode: RoadRenderMode = .decal,
    terrain_mode: RoadTerrainMode = .conform,
    decal_material: []const u8 = "road.dirt",
    prop_asset_id: []const u8 = "",
};

pub const ValidationIssue = struct {
    code: []const u8,
    id: []const u8,
};

pub const OwnedRoadNode = struct {
    id: []u8,
    position: core.math.Vec3f,
    kind: RoadNodeKind,
    terrain_mode: RoadTerrainMode,

    fn init(allocator: std.mem.Allocator, input: RoadNodeInput) !OwnedRoadNode {
        if (input.id.len == 0) return error.InvalidRoadNode;
        try validateVec3(input.position);
        return .{
            .id = try allocator.dupe(u8, input.id),
            .position = input.position,
            .kind = input.kind,
            .terrain_mode = input.terrain_mode,
        };
    }

    fn deinit(self: *OwnedRoadNode, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
    }
};

pub const OwnedRoadEdge = struct {
    id: []u8,
    start_node_id: []u8,
    end_node_id: []u8,
    handle_start: core.math.Vec3f,
    handle_end: core.math.Vec3f,
    width: f32,
    elevation: f32,
    material_mask_value: u8,
    render_mode: RoadRenderMode,
    terrain_mode: RoadTerrainMode,
    decal_material: []u8,
    prop_asset_id: []u8,

    fn init(allocator: std.mem.Allocator, input: RoadEdgeInput) !OwnedRoadEdge {
        try validateRoadEdgeInput(input);
        return .{
            .id = try allocator.dupe(u8, input.id),
            .start_node_id = try allocator.dupe(u8, input.start_node_id),
            .end_node_id = try allocator.dupe(u8, input.end_node_id),
            .handle_start = input.handle_start,
            .handle_end = input.handle_end,
            .width = input.width,
            .elevation = input.elevation,
            .material_mask_value = input.material_mask_value,
            .render_mode = input.render_mode,
            .terrain_mode = input.terrain_mode,
            .decal_material = try allocator.dupe(u8, input.decal_material),
            .prop_asset_id = try allocator.dupe(u8, input.prop_asset_id),
        };
    }

    fn deinit(self: *OwnedRoadEdge, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.start_node_id);
        allocator.free(self.end_node_id);
        allocator.free(self.decal_material);
        allocator.free(self.prop_asset_id);
    }
};

pub const SplinesAuthoringDoc = struct {
    allocator: std.mem.Allocator,
    road_nodes: std.ArrayList(OwnedRoadNode),
    road_edges: std.ArrayList(OwnedRoadEdge),

    pub fn init(allocator: std.mem.Allocator) SplinesAuthoringDoc {
        return .{ .allocator = allocator, .road_nodes = .empty, .road_edges = .empty };
    }

    pub fn deinit(self: *SplinesAuthoringDoc) void {
        for (self.road_nodes.items) |*node| node.deinit(self.allocator);
        self.road_nodes.deinit(self.allocator);
        for (self.road_edges.items) |*edge| edge.deinit(self.allocator);
        self.road_edges.deinit(self.allocator);
    }

    pub fn upsertRoadNode(self: *SplinesAuthoringDoc, input: RoadNodeInput) !void {
        var owned = try OwnedRoadNode.init(self.allocator, input);
        errdefer owned.deinit(self.allocator);
        for (self.road_nodes.items) |*node| {
            if (!std.mem.eql(u8, node.id, input.id)) continue;
            node.deinit(self.allocator);
            node.* = owned;
            return;
        }
        try self.road_nodes.append(self.allocator, owned);
    }

    pub fn upsertRoadEdge(self: *SplinesAuthoringDoc, input: RoadEdgeInput) !void {
        if (self.nodeIndexById(input.start_node_id) == null or self.nodeIndexById(input.end_node_id) == null) return error.MissingRoadNode;
        var owned = try OwnedRoadEdge.init(self.allocator, input);
        errdefer owned.deinit(self.allocator);
        for (self.road_edges.items) |*edge| {
            if (!std.mem.eql(u8, edge.id, input.id)) continue;
            edge.deinit(self.allocator);
            edge.* = owned;
            return;
        }
        try self.road_edges.append(self.allocator, owned);
    }

    pub fn deleteRoadEdge(self: *SplinesAuthoringDoc, edge_id: []const u8) !void {
        for (self.road_edges.items, 0..) |edge, index| {
            if (!std.mem.eql(u8, edge.id, edge_id)) continue;
            var removed = self.road_edges.swapRemove(index);
            removed.deinit(self.allocator);
            self.deleteOrphanEndpointNodes();
            return;
        }
        return error.MissingRoadEdge;
    }

    pub fn roadEdgePtr(self: *SplinesAuthoringDoc, edge_id: []const u8) ?*OwnedRoadEdge {
        for (self.road_edges.items) |*edge| {
            if (std.mem.eql(u8, edge.id, edge_id)) return edge;
        }
        return null;
    }

    pub fn roadEdgePtrConst(self: *const SplinesAuthoringDoc, edge_id: []const u8) ?*const OwnedRoadEdge {
        for (self.road_edges.items) |*edge| {
            if (std.mem.eql(u8, edge.id, edge_id)) return edge;
        }
        return null;
    }

    pub fn deleteRoadNode(self: *SplinesAuthoringDoc, node_id: []const u8) !void {
        if (self.nodeDegree(node_id) > 0) return error.RoadNodeStillConnected;
        const index = self.nodeIndexById(node_id) orelse return error.MissingRoadNode;
        var removed = self.road_nodes.swapRemove(index);
        removed.deinit(self.allocator);
    }

    pub fn deleteRoadNodeCascade(self: *SplinesAuthoringDoc, node_id: []const u8) !usize {
        const index = self.nodeIndexById(node_id) orelse return error.MissingRoadNode;
        var removed_edges: usize = 0;
        var edge_index: usize = 0;
        while (edge_index < self.road_edges.items.len) {
            const edge = self.road_edges.items[edge_index];
            if (!std.mem.eql(u8, edge.start_node_id, node_id) and !std.mem.eql(u8, edge.end_node_id, node_id)) {
                edge_index += 1;
                continue;
            }
            var removed = self.road_edges.swapRemove(edge_index);
            removed.deinit(self.allocator);
            removed_edges += 1;
        }
        var removed_node = self.road_nodes.swapRemove(index);
        removed_node.deinit(self.allocator);
        self.deleteOrphanEndpointNodes();
        return removed_edges;
    }

    pub fn mergeRoadNodes(self: *SplinesAuthoringDoc, keep_id: []const u8, remove_id: []const u8) !void {
        if (std.mem.eql(u8, keep_id, remove_id)) return;
        const keep_idx = self.nodeIndexById(keep_id) orelse return error.MissingRoadNode;
        const remove_idx = self.nodeIndexById(remove_id) orelse return error.MissingRoadNode;
        for (self.road_edges.items) |*edge| {
            if (std.mem.eql(u8, edge.start_node_id, remove_id)) {
                self.allocator.free(edge.start_node_id);
                edge.start_node_id = try self.allocator.dupe(u8, keep_id);
            }
            if (std.mem.eql(u8, edge.end_node_id, remove_id)) {
                self.allocator.free(edge.end_node_id);
                edge.end_node_id = try self.allocator.dupe(u8, keep_id);
            }
        }
        self.road_nodes.items[keep_idx].kind = .junction;
        var removed = self.road_nodes.swapRemove(remove_idx);
        removed.deinit(self.allocator);
    }

    pub fn moveRoadNode(self: *SplinesAuthoringDoc, node_id: []const u8, position: core.math.Vec3f) !void {
        try validateVec3(position);
        const index = self.nodeIndexById(node_id) orelse return error.MissingRoadNode;
        self.road_nodes.items[index].position = position;
    }

    pub fn promoteRoadNode(self: *SplinesAuthoringDoc, node_id: []const u8) !void {
        const index = self.nodeIndexById(node_id) orelse return error.MissingRoadNode;
        self.road_nodes.items[index].kind = .junction;
    }

    pub fn updateRoadEdge(self: *SplinesAuthoringDoc, input: RoadEdgeInput) !void {
        try validateRoadEdgeInput(input);
        if (self.nodeIndexById(input.start_node_id) == null or self.nodeIndexById(input.end_node_id) == null) return error.MissingRoadNode;
        const edge = self.roadEdgePtr(input.id) orelse return error.MissingRoadEdge;
        self.allocator.free(edge.start_node_id);
        self.allocator.free(edge.end_node_id);
        self.allocator.free(edge.decal_material);
        self.allocator.free(edge.prop_asset_id);
        edge.start_node_id = try self.allocator.dupe(u8, input.start_node_id);
        edge.end_node_id = try self.allocator.dupe(u8, input.end_node_id);
        edge.handle_start = input.handle_start;
        edge.handle_end = input.handle_end;
        edge.width = input.width;
        edge.elevation = input.elevation;
        edge.material_mask_value = input.material_mask_value;
        edge.render_mode = input.render_mode;
        edge.terrain_mode = input.terrain_mode;
        edge.decal_material = try self.allocator.dupe(u8, input.decal_material);
        edge.prop_asset_id = try self.allocator.dupe(u8, input.prop_asset_id);
    }

    pub fn splitRoadEdge(self: *SplinesAuthoringDoc, edge_id: []const u8, new_node_id: []const u8, new_edge_id: []const u8, point: core.math.Vec3f) !void {
        if (self.nodeIndexById(new_node_id) != null) return error.DuplicateRoadNode;
        if (self.roadEdgePtrConst(new_edge_id) != null) return error.DuplicateRoadEdge;
        const edge = self.roadEdgePtr(edge_id) orelse return error.MissingRoadEdge;
        const old_end = try self.allocator.dupe(u8, edge.end_node_id);
        defer self.allocator.free(old_end);
        const old_handle_end = edge.handle_end;
        const new_position = point;
        try self.upsertRoadNode(.{ .id = new_node_id, .position = new_position, .kind = .junction, .terrain_mode = edge.terrain_mode });
        self.allocator.free(edge.end_node_id);
        edge.end_node_id = try self.allocator.dupe(u8, new_node_id);
        edge.handle_end = new_position;
        try self.upsertRoadEdge(.{
            .id = new_edge_id,
            .start_node_id = new_node_id,
            .end_node_id = old_end,
            .handle_start = new_position,
            .handle_end = old_handle_end,
            .width = edge.width,
            .elevation = edge.elevation,
            .material_mask_value = edge.material_mask_value,
            .render_mode = edge.render_mode,
            .terrain_mode = edge.terrain_mode,
            .decal_material = edge.decal_material,
            .prop_asset_id = edge.prop_asset_id,
        });
    }

    pub fn validateGraph(self: *const SplinesAuthoringDoc, allocator: std.mem.Allocator) ![]ValidationIssue {
        var issues = std.ArrayList(ValidationIssue).empty;
        errdefer issues.deinit(allocator);
        for (self.road_nodes.items, 0..) |node, index| {
            validateRoadNodeInput(.{ .id = node.id, .position = node.position, .kind = node.kind, .terrain_mode = node.terrain_mode }) catch try issues.append(allocator, .{ .code = "invalid_node", .id = node.id });
            var other_index = index + 1;
            while (other_index < self.road_nodes.items.len) : (other_index += 1) {
                const other = self.road_nodes.items[other_index];
                if (std.mem.eql(u8, node.id, other.id)) try issues.append(allocator, .{ .code = "duplicate_node", .id = node.id });
                const dx = node.position.x - other.position.x;
                const dz = node.position.z - other.position.z;
                if (@sqrt(dx * dx + dz * dz) <= 0.25 and !std.mem.eql(u8, node.id, other.id)) try issues.append(allocator, .{ .code = "overlapping_junction_candidate", .id = node.id });
            }
        }
        for (self.road_edges.items, 0..) |edge, index| {
            validateRoadEdgeInput(.{
                .id = edge.id,
                .start_node_id = edge.start_node_id,
                .end_node_id = edge.end_node_id,
                .handle_start = edge.handle_start,
                .handle_end = edge.handle_end,
                .width = edge.width,
                .elevation = edge.elevation,
                .material_mask_value = edge.material_mask_value,
                .render_mode = edge.render_mode,
                .terrain_mode = edge.terrain_mode,
                .decal_material = edge.decal_material,
                .prop_asset_id = edge.prop_asset_id,
            }) catch try issues.append(allocator, .{ .code = "invalid_edge", .id = edge.id });
            const start_node = self.nodeIndexById(edge.start_node_id);
            const end_node = self.nodeIndexById(edge.end_node_id);
            if (start_node == null or end_node == null) {
                try issues.append(allocator, .{ .code = "missing_node", .id = edge.id });
            } else {
                const a = self.road_nodes.items[start_node.?].position;
                const b = self.road_nodes.items[end_node.?].position;
                const dx = a.x - b.x;
                const dz = a.z - b.z;
                if (@sqrt(dx * dx + dz * dz) <= 0.001) try issues.append(allocator, .{ .code = "zero_length_edge", .id = edge.id });
            }
            var other_index = index + 1;
            while (other_index < self.road_edges.items.len) : (other_index += 1) {
                if (std.mem.eql(u8, edge.id, self.road_edges.items[other_index].id)) try issues.append(allocator, .{ .code = "duplicate_edge", .id = edge.id });
            }
        }
        if (self.road_nodes.items.len > 1) {
            const visited = try allocator.alloc(bool, self.road_nodes.items.len);
            defer allocator.free(visited);
            @memset(visited, false);
            var stack = std.ArrayList(usize).empty;
            defer stack.deinit(allocator);
            try stack.append(allocator, 0);
            visited[0] = true;
            while (stack.pop()) |node_index| {
                const node_id = self.road_nodes.items[node_index].id;
                for (self.road_edges.items) |edge| {
                    var neighbor_id: ?[]const u8 = null;
                    if (std.mem.eql(u8, edge.start_node_id, node_id)) neighbor_id = edge.end_node_id;
                    if (std.mem.eql(u8, edge.end_node_id, node_id)) neighbor_id = edge.start_node_id;
                    const neighbor = neighbor_id orelse continue;
                    const neighbor_index = self.nodeIndexById(neighbor) orelse continue;
                    if (visited[neighbor_index]) continue;
                    visited[neighbor_index] = true;
                    try stack.append(allocator, neighbor_index);
                }
            }
            for (visited, 0..) |was_visited, index| {
                if (!was_visited) try issues.append(allocator, .{ .code = "disconnected_component", .id = self.road_nodes.items[index].id });
            }
        }
        return issues.toOwnedSlice(allocator);
    }

    pub fn nodeDegree(self: *const SplinesAuthoringDoc, node_id: []const u8) usize {
        var count: usize = 0;
        for (self.road_edges.items) |edge| {
            if (std.mem.eql(u8, edge.start_node_id, node_id) or std.mem.eql(u8, edge.end_node_id, node_id)) count += 1;
        }
        return count;
    }

    pub fn nodeIndexById(self: *const SplinesAuthoringDoc, node_id: []const u8) ?usize {
        for (self.road_nodes.items, 0..) |node, index| {
            if (std.mem.eql(u8, node.id, node_id)) return index;
        }
        return null;
    }

    fn deleteOrphanEndpointNodes(self: *SplinesAuthoringDoc) void {
        var index: usize = 0;
        while (index < self.road_nodes.items.len) {
            const node = self.road_nodes.items[index];
            if (node.kind == .junction or self.nodeDegree(node.id) > 0) {
                index += 1;
                continue;
            }
            var removed = self.road_nodes.swapRemove(index);
            removed.deinit(self.allocator);
        }
    }
};

pub fn load(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    manifest_path: []const u8,
) !SplinesAuthoringDoc {
    const path = try layerPath(allocator, manifest_path);
    defer allocator.free(path);

    var project_dir = try openProjectDir(io, project_path);
    defer project_dir.close(io);

    const bytes = project_dir.readFileAlloc(io, path, allocator, .limited(max_splines_doc_bytes)) catch |err| switch (err) {
        error.FileNotFound => return SplinesAuthoringDoc.init(allocator),
        else => return err,
    };
    defer allocator.free(bytes);
    return parseDocKdl(allocator, bytes);
}

pub fn save(
    doc: SplinesAuthoringDoc,
    io: std.Io,
    project_path: []const u8,
    manifest_path: []const u8,
) !void {
    const path = try layerPath(doc.allocator, manifest_path);
    defer doc.allocator.free(path);

    var project_dir = try openProjectDir(io, project_path);
    defer project_dir.close(io);
    if (std.fs.path.dirname(path)) |parent| try project_dir.createDirPath(io, parent);

    var out: std.Io.Writer.Allocating = .init(doc.allocator);
    defer out.deinit();
    try writeDocKdl(&out.writer, doc);
    const bytes = try out.toOwnedSlice();
    defer doc.allocator.free(bytes);
    try project_dir.writeFile(io, .{ .sub_path = path, .data = bytes });
}

pub fn upsertRoadGraphFile(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    manifest_path: []const u8,
    nodes: []const RoadNodeInput,
    edges: []const RoadEdgeInput,
) !void {
    var doc = try load(allocator, io, project_path, manifest_path);
    defer doc.deinit();
    for (nodes) |node| try doc.upsertRoadNode(node);
    for (edges) |edge| try doc.upsertRoadEdge(edge);
    try save(doc, io, project_path, manifest_path);
}

pub fn validateRoadNodeInput(input: RoadNodeInput) !void {
    if (input.id.len == 0) return error.InvalidRoadNode;
    try validateVec3(input.position);
}

pub fn validateRoadEdgeInput(input: RoadEdgeInput) !void {
    if (input.id.len == 0 or input.start_node_id.len == 0 or input.end_node_id.len == 0) return error.InvalidRoadEdge;
    if (std.mem.eql(u8, input.start_node_id, input.end_node_id)) return error.InvalidRoadEdge;
    if (!std.math.isFinite(input.width) or input.width <= 0) return error.InvalidRoadEdge;
    if (!std.math.isFinite(input.elevation)) return error.InvalidRoadEdge;
    if (input.material_mask_value == 0) return error.InvalidRoadEdge;
    try validateVec3(input.handle_start);
    try validateVec3(input.handle_end);
}

fn validateVec3(point: core.math.Vec3f) !void {
    if (!std.math.isFinite(point.x) or !std.math.isFinite(point.y) or !std.math.isFinite(point.z)) return error.InvalidRoadPoint;
}

const RoadNodeBuilder = struct {
    id: ?[]u8 = null,
    position: ?core.math.Vec3f = null,
    kind: RoadNodeKind = .endpoint,
    terrain_mode: RoadTerrainMode = .conform,

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
        } else if (std.mem.eql(u8, key, "kind")) self.kind = try RoadNodeKind.parse(value) else if (std.mem.eql(u8, key, "terrain_mode")) self.terrain_mode = try RoadTerrainMode.parse(value) else return error.UnknownField;
    }

    fn finish(self: *RoadNodeBuilder) !RoadNodeInput {
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
    render_mode: RoadRenderMode = .decal,
    terrain_mode: RoadTerrainMode = .conform,
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
        } else if (std.mem.eql(u8, key, "width")) self.width = try std.fmt.parseFloat(f32, value) else if (std.mem.eql(u8, key, "elevation")) self.elevation = try std.fmt.parseFloat(f32, value) else if (std.mem.eql(u8, key, "material_mask_value")) self.material_mask_value = @intCast(try std.fmt.parseInt(u16, value, 10)) else if (std.mem.eql(u8, key, "render_mode")) self.render_mode = try RoadRenderMode.parse(value) else if (std.mem.eql(u8, key, "terrain_mode")) self.terrain_mode = try RoadTerrainMode.parse(value) else if (std.mem.eql(u8, key, "decal_material")) {
            if (self.decal_material) |existing| allocator.free(existing);
            self.decal_material = try allocator.dupe(u8, value);
        } else if (std.mem.eql(u8, key, "prop_asset_id")) {
            if (self.prop_asset_id) |existing| allocator.free(existing);
            self.prop_asset_id = try allocator.dupe(u8, value);
        } else return error.UnknownField;
    }

    fn finish(self: *RoadEdgeBuilder, allocator: std.mem.Allocator) !RoadEdgeInput {
        const id = self.id orelse return error.InvalidSplinesDocument;
        const start = self.start_node_id orelse return error.InvalidSplinesDocument;
        const end = self.end_node_id orelse return error.InvalidSplinesDocument;
        const decal = if (self.decal_material) |value| blk: {
            self.decal_material = null;
            break :blk value;
        } else try allocator.dupe(u8, "road.dirt");
        const prop = if (self.prop_asset_id) |value| blk: {
            self.prop_asset_id = null;
            break :blk value;
        } else try allocator.dupe(u8, "");
        self.id = null;
        self.start_node_id = null;
        self.end_node_id = null;
        return .{
            .id = id,
            .start_node_id = start,
            .end_node_id = end,
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

fn parseDocKdl(allocator: std.mem.Allocator, bytes: []const u8) !SplinesAuthoringDoc {
    const buffer = try allocator.allocSentinel(u8, bytes.len, 0);
    defer allocator.free(buffer);
    @memcpy(buffer, bytes);

    var parser = kdl.Parser.init(buffer);
    var doc = SplinesAuthoringDoc.init(allocator);
    errdefer doc.deinit();

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
                    try finishPendingBuilder(allocator, &doc, &node_builder, &edge_builder);
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
                    if (try std.fmt.parseInt(u32, value, 10) != 2) return error.UnsupportedSplineSchemaVersion;
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
                if (depth == 1) try finishPendingBuilder(allocator, &doc, &node_builder, &edge_builder);
                depth -= 1;
                if (depth < 0) return error.InvalidSplinesDocument;
            },
            .arg, .invalid => return error.InvalidSplinesDocument,
            .eof => break,
        }
    }
    try finishPendingBuilder(allocator, &doc, &node_builder, &edge_builder);
    if (!root_seen or depth != 0) return error.InvalidSplinesDocument;
    return doc;
}

fn finishPendingBuilder(
    allocator: std.mem.Allocator,
    doc: *SplinesAuthoringDoc,
    node_builder: *?RoadNodeBuilder,
    edge_builder: *?RoadEdgeBuilder,
) !void {
    if (node_builder.*) |*node| {
        const input = try node.finish();
        defer allocator.free(input.id);
        try doc.upsertRoadNode(input);
        node.deinit(allocator);
        node_builder.* = null;
    }
    if (edge_builder.*) |*edge| {
        const input = try edge.finish(allocator);
        defer allocator.free(input.id);
        defer allocator.free(input.start_node_id);
        defer allocator.free(input.end_node_id);
        defer allocator.free(input.decal_material);
        defer allocator.free(input.prop_asset_id);
        try doc.upsertRoadEdge(input);
        edge.deinit(allocator);
        edge_builder.* = null;
    }
}

fn writeDocKdl(writer: *std.Io.Writer, doc: SplinesAuthoringDoc) !void {
    try writer.writeAll("splines version=2 {\n");
    for (doc.road_nodes.items) |node| {
        try writer.print("  road_node id=\"{s}\" position=\"{d},{d},{d}\" kind=\"{s}\" terrain_mode=\"{s}\"\n", .{
            node.id,
            node.position.x,
            node.position.y,
            node.position.z,
            node.kind.name(),
            node.terrain_mode.name(),
        });
    }
    for (doc.road_edges.items) |edge| {
        try writer.print("  road_edge id=\"{s}\" start=\"{s}\" end=\"{s}\" handle_start=\"{d},{d},{d}\" handle_end=\"{d},{d},{d}\" width={d} elevation={d} material_mask_value={d} render_mode=\"{s}\" terrain_mode=\"{s}\" decal_material=\"{s}\" prop_asset_id=\"{s}\"\n", .{
            edge.id,
            edge.start_node_id,
            edge.end_node_id,
            edge.handle_start.x,
            edge.handle_start.y,
            edge.handle_start.z,
            edge.handle_end.x,
            edge.handle_end.y,
            edge.handle_end.z,
            edge.width,
            edge.elevation,
            edge.material_mask_value,
            edge.render_mode.name(),
            edge.terrain_mode.name(),
            edge.decal_material,
            edge.prop_asset_id,
        });
    }
    try writer.writeAll("}\n");
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

test "splines authoring writes v2 road graph only" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);

    try upsertRoadGraphFile(std.testing.allocator, std.testing.io, project_path, "world.kdl", &.{
        .{ .id = "n0", .position = .{ .x = 0, .y = 0, .z = 0 } },
        .{ .id = "n1", .position = .{ .x = 16, .y = 0, .z = 0 }, .kind = .junction },
    }, &.{
        .{ .id = "e0", .start_node_id = "n0", .end_node_id = "n1", .handle_start = .{ .x = 4, .y = 0, .z = 0 }, .handle_end = .{ .x = 12, .y = 0, .z = 0 }, .width = 3 },
    });

    var doc = try load(std.testing.allocator, std.testing.io, project_path, "world.kdl");
    defer doc.deinit();
    try std.testing.expectEqual(@as(usize, 2), doc.road_nodes.items.len);
    try std.testing.expectEqual(@as(usize, 1), doc.road_edges.items.len);
    try std.testing.expectEqual(RoadNodeKind.junction, doc.road_nodes.items[1].kind);
    try std.testing.expectEqual(RoadRenderMode.decal, doc.road_edges.items[0].render_mode);
}

test "splines authoring rejects unsupported schema versions" {
    try std.testing.expectError(error.UnsupportedSplineSchemaVersion, parseDocKdl(std.testing.allocator,
        \\splines version=0 {}
        \\
    ));
}

test "deleting segment removes orphan endpoints but preserves shared junction" {
    var doc = SplinesAuthoringDoc.init(std.testing.allocator);
    defer doc.deinit();
    try doc.upsertRoadNode(.{ .id = "a", .position = .{ .x = 0, .y = 0, .z = 0 } });
    try doc.upsertRoadNode(.{ .id = "b", .position = .{ .x = 8, .y = 0, .z = 0 }, .kind = .junction });
    try doc.upsertRoadNode(.{ .id = "c", .position = .{ .x = 16, .y = 0, .z = 0 } });
    try doc.upsertRoadEdge(.{ .id = "ab", .start_node_id = "a", .end_node_id = "b", .handle_start = .{ .x = 2, .y = 0, .z = 0 }, .handle_end = .{ .x = 6, .y = 0, .z = 0 }, .width = 4 });
    try doc.upsertRoadEdge(.{ .id = "bc", .start_node_id = "b", .end_node_id = "c", .handle_start = .{ .x = 10, .y = 0, .z = 0 }, .handle_end = .{ .x = 14, .y = 0, .z = 0 }, .width = 4 });

    try doc.deleteRoadEdge("ab");
    try std.testing.expect(doc.nodeIndexById("a") == null);
    try std.testing.expect(doc.nodeIndexById("b") != null);
    try std.testing.expect(doc.nodeIndexById("c") != null);
    try std.testing.expectEqual(@as(usize, 1), doc.road_edges.items.len);
}

test "moving and merging endpoints updates graph references" {
    var doc = SplinesAuthoringDoc.init(std.testing.allocator);
    defer doc.deinit();
    try doc.upsertRoadNode(.{ .id = "a", .position = .{ .x = 0, .y = 0, .z = 0 } });
    try doc.upsertRoadNode(.{ .id = "b", .position = .{ .x = 8, .y = 0, .z = 0 } });
    try doc.upsertRoadNode(.{ .id = "c", .position = .{ .x = 8, .y = 0, .z = 8 } });
    try doc.upsertRoadEdge(.{ .id = "ab", .start_node_id = "a", .end_node_id = "b", .handle_start = .{ .x = 2, .y = 0, .z = 0 }, .handle_end = .{ .x = 6, .y = 0, .z = 0 }, .width = 4 });
    try doc.upsertRoadEdge(.{ .id = "ac", .start_node_id = "a", .end_node_id = "c", .handle_start = .{ .x = 2, .y = 0, .z = 2 }, .handle_end = .{ .x = 6, .y = 0, .z = 6 }, .width = 4 });

    try doc.moveRoadNode("a", .{ .x = -4, .y = 0, .z = 0 });
    try std.testing.expectEqual(@as(f32, -4), doc.road_nodes.items[doc.nodeIndexById("a").?].position.x);
    try doc.mergeRoadNodes("b", "c");
    try std.testing.expect(doc.nodeIndexById("c") == null);
    try std.testing.expectEqual(RoadNodeKind.junction, doc.road_nodes.items[doc.nodeIndexById("b").?].kind);
    try std.testing.expect(std.mem.eql(u8, doc.road_edges.items[1].end_node_id, "b"));
}

test "splitting edge inserts junction and preserves road settings" {
    var doc = SplinesAuthoringDoc.init(std.testing.allocator);
    defer doc.deinit();
    try doc.upsertRoadNode(.{ .id = "a", .position = .{ .x = 0, .y = 0, .z = 0 } });
    try doc.upsertRoadNode(.{ .id = "b", .position = .{ .x = 12, .y = 0, .z = 0 } });
    try doc.upsertRoadEdge(.{
        .id = "ab",
        .start_node_id = "a",
        .end_node_id = "b",
        .handle_start = .{ .x = 3, .y = 0, .z = 0 },
        .handle_end = .{ .x = 9, .y = 0, .z = 0 },
        .width = 5,
        .elevation = 0.12,
        .material_mask_value = 200,
        .render_mode = .prop_sections,
        .terrain_mode = .floating,
        .decal_material = "road.gravel",
        .prop_asset_id = "road_section_straight",
    });

    try doc.splitRoadEdge("ab", "mid", "mid_b", .{ .x = 6, .y = 0, .z = 0 });

    const mid = doc.road_nodes.items[doc.nodeIndexById("mid").?];
    try std.testing.expectEqual(RoadNodeKind.junction, mid.kind);
    const first = doc.roadEdgePtrConst("ab").?;
    const second = doc.roadEdgePtrConst("mid_b").?;
    try std.testing.expectEqualStrings("mid", first.end_node_id);
    try std.testing.expectEqualStrings("mid", second.start_node_id);
    try std.testing.expectEqual(@as(f32, 5), second.width);
    try std.testing.expectEqual(@as(f32, 0.12), second.elevation);
    try std.testing.expectEqual(@as(u8, 200), second.material_mask_value);
    try std.testing.expectEqual(RoadRenderMode.prop_sections, second.render_mode);
    try std.testing.expectEqual(RoadTerrainMode.floating, second.terrain_mode);
    try std.testing.expectEqualStrings("road.gravel", second.decal_material);
    try std.testing.expectEqualStrings("road_section_straight", second.prop_asset_id);
}

test "joining endpoint into segment splits edge and preserves valid junction" {
    var doc = SplinesAuthoringDoc.init(std.testing.allocator);
    defer doc.deinit();
    try doc.upsertRoadNode(.{ .id = "a", .position = .{ .x = 0, .y = 0, .z = 0 } });
    try doc.upsertRoadNode(.{ .id = "b", .position = .{ .x = 12, .y = 0, .z = 0 } });
    try doc.upsertRoadNode(.{ .id = "spur", .position = .{ .x = 6, .y = 0, .z = 5 } });
    try doc.upsertRoadNode(.{ .id = "loose", .position = .{ .x = 6, .y = 0, .z = 2 } });
    try doc.upsertRoadEdge(.{ .id = "ab", .start_node_id = "a", .end_node_id = "b", .handle_start = .{ .x = 3, .y = 0, .z = 0 }, .handle_end = .{ .x = 9, .y = 0, .z = 0 }, .width = 5 });
    try doc.upsertRoadEdge(.{ .id = "spur_loose", .start_node_id = "spur", .end_node_id = "loose", .handle_start = .{ .x = 6, .y = 0, .z = 4 }, .handle_end = .{ .x = 6, .y = 0, .z = 3 }, .width = 3 });

    try doc.splitRoadEdge("ab", "mid", "mid_b", .{ .x = 6, .y = 0, .z = 0 });
    try doc.mergeRoadNodes("mid", "loose");

    try std.testing.expect(doc.nodeIndexById("loose") == null);
    try std.testing.expectEqual(RoadNodeKind.junction, doc.road_nodes.items[doc.nodeIndexById("mid").?].kind);
    try std.testing.expectEqualStrings("mid", doc.roadEdgePtrConst("ab").?.end_node_id);
    try std.testing.expectEqualStrings("mid", doc.roadEdgePtrConst("mid_b").?.start_node_id);
    try std.testing.expectEqualStrings("mid", doc.roadEdgePtrConst("spur_loose").?.end_node_id);
    const issues = try doc.validateGraph(std.testing.allocator);
    defer std.testing.allocator.free(issues);
    try std.testing.expectEqual(@as(usize, 0), issues.len);
}

test "cascade node delete removes incident edges" {
    var doc = SplinesAuthoringDoc.init(std.testing.allocator);
    defer doc.deinit();
    try doc.upsertRoadNode(.{ .id = "a", .position = .{ .x = 0, .y = 0, .z = 0 } });
    try doc.upsertRoadNode(.{ .id = "b", .position = .{ .x = 8, .y = 0, .z = 0 }, .kind = .junction });
    try doc.upsertRoadNode(.{ .id = "c", .position = .{ .x = 8, .y = 0, .z = 8 } });
    try doc.upsertRoadEdge(.{ .id = "ab", .start_node_id = "a", .end_node_id = "b", .handle_start = .{ .x = 2, .y = 0, .z = 0 }, .handle_end = .{ .x = 6, .y = 0, .z = 0 }, .width = 4 });
    try doc.upsertRoadEdge(.{ .id = "bc", .start_node_id = "b", .end_node_id = "c", .handle_start = .{ .x = 8, .y = 0, .z = 2 }, .handle_end = .{ .x = 8, .y = 0, .z = 6 }, .width = 4 });

    const removed_edges = try doc.deleteRoadNodeCascade("b");

    try std.testing.expectEqual(@as(usize, 2), removed_edges);
    try std.testing.expect(doc.nodeIndexById("b") == null);
    try std.testing.expectEqual(@as(usize, 0), doc.road_edges.items.len);
    try std.testing.expectEqual(@as(usize, 0), doc.road_nodes.items.len);
}

test "road graph validation reports overlapping junction candidates" {
    var doc = SplinesAuthoringDoc.init(std.testing.allocator);
    defer doc.deinit();
    try doc.upsertRoadNode(.{ .id = "a", .position = .{ .x = 0, .y = 0, .z = 0 } });
    try doc.upsertRoadNode(.{ .id = "b", .position = .{ .x = 0.1, .y = 0, .z = 0.1 } });

    const issues = try doc.validateGraph(std.testing.allocator);
    defer std.testing.allocator.free(issues);

    var found_overlap = false;
    for (issues) |issue| {
        if (std.mem.eql(u8, issue.code, "overlapping_junction_candidate") and std.mem.eql(u8, issue.id, "a")) found_overlap = true;
    }
    try std.testing.expect(found_overlap);
}

test "road graph validation reports disconnected components" {
    var doc = SplinesAuthoringDoc.init(std.testing.allocator);
    defer doc.deinit();
    try doc.upsertRoadNode(.{ .id = "a", .position = .{ .x = 0, .y = 0, .z = 0 } });
    try doc.upsertRoadNode(.{ .id = "b", .position = .{ .x = 8, .y = 0, .z = 0 } });
    try doc.upsertRoadNode(.{ .id = "c", .position = .{ .x = 100, .y = 0, .z = 0 } });
    try doc.upsertRoadEdge(.{ .id = "ab", .start_node_id = "a", .end_node_id = "b", .handle_start = .{ .x = 2, .y = 0, .z = 0 }, .handle_end = .{ .x = 6, .y = 0, .z = 0 }, .width = 4 });

    const issues = try doc.validateGraph(std.testing.allocator);
    defer std.testing.allocator.free(issues);

    var found_disconnected = false;
    for (issues) |issue| {
        if (std.mem.eql(u8, issue.code, "disconnected_component") and std.mem.eql(u8, issue.id, "c")) found_disconnected = true;
    }
    try std.testing.expect(found_disconnected);
}
