const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const geometry = shared.geometry;
const shared_color = shared.color;
const gpu_scene = shared.gpu_scene;
const project_editor_state = @import("project_editor_state.zig");
const project_editor_world_authoring_manifest = @import("project_editor_world_authoring_manifest.zig");
const project_editor_terrain_preview = @import("project_editor_terrain_preview.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const modules = friendly_engine.modules;
const world = friendly_engine.world;

pub const Entry = struct {
    mesh: geometry.Mesh,
    texture: []u8,
    base_color: shared_color.Color,

    pub fn deinit(self: *Entry, allocator: std.mem.Allocator) void {
        self.mesh.deinit(allocator);
        allocator.free(self.texture);
        self.* = undefined;
    }
};

pub const Cache = struct {
    entries: std.ArrayList(Entry) = .empty,

    pub fn deinit(self: *Cache, allocator: std.mem.Allocator) void {
        for (self.entries.items) |*entry| entry.deinit(allocator);
        self.entries.deinit(allocator);
    }

    pub fn clear(self: *Cache, allocator: std.mem.Allocator) void {
        for (self.entries.items) |*entry| entry.deinit(allocator);
        self.entries.clearRetainingCapacity();
    }
};

pub fn refreshIfStale(state: *ProjectEditorState) !void {
    if (!state.spline_preview_stale) return;
    try refresh(state);
    state.spline_preview_stale = false;
}

pub fn refresh(state: *ProjectEditorState) !void {
    state.spline_preview.clear(state.allocator);

    var world_manifest = try world.manifest.loadManifest(
        state.allocator,
        state.io,
        state.project_path,
        try project_editor_world_authoring_manifest.pathForState(state),
    );
    defer world_manifest.deinit();

    var doc = try modules.splines.authoring.load(
        state.allocator,
        state.io,
        state.project_path,
        try project_editor_world_authoring_manifest.pathForState(state),
    );
    defer doc.deinit();

    const camera_target = cameraTargetVec(state);
    const draw_distance_m = project_editor_terrain_preview.effectiveDrawDistance(state);

    for (doc.road_edges.items) |edge| {
        if (edge.render_mode == .prop_sections) continue;
        const start_node = findRoadNode(doc, edge.start_node_id) orelse return error.MissingRoadNode;
        const end_node = findRoadNode(doc, edge.end_node_id) orelse return error.MissingRoadNode;
        var segment_index: usize = 0;
        while (segment_index < 16) : (segment_index += 1) {
            const a = sampleRoadEdge(start_node.position, edge.handle_start, edge.handle_end, end_node.position, @as(f32, @floatFromInt(segment_index)) / 16.0);
            const b = sampleRoadEdge(start_node.position, edge.handle_start, edge.handle_end, end_node.position, @as(f32, @floatFromInt(segment_index + 1)) / 16.0);
            for (world_manifest.cells) |entry| {
                if (!cellInClipmap(entry.id, camera_target, world_manifest.cell_size_m, draw_distance_m)) continue;
                const bounds = world.cell.boundsForCell(entry.id, world_manifest.cell_size_m, world.cell.default_cell_height_m);
                if (!modules.splines.road_mesh.segmentIntersectsCell(a, b, bounds)) continue;
                var generated = try modules.splines.road_mesh.buildRoadSegmentMesh(
                    state.allocator,
                    edge.id,
                    edge.width,
                    edge.elevation,
                    segment_index,
                    a,
                    b,
                );
                errdefer generated.mesh.deinit(state.allocator);
                const entry_mesh = try renderMeshToEntry(state.allocator, generated.mesh);
                try state.spline_preview.entries.append(state.allocator, entry_mesh);
            }
        }
    }
}

fn findRoadNode(doc: modules.splines.authoring.SplinesAuthoringDoc, id: []const u8) ?modules.splines.authoring.OwnedRoadNode {
    for (doc.road_nodes.items) |node| {
        if (std.mem.eql(u8, node.id, id)) return node;
    }
    return null;
}

fn sampleRoadEdge(
    a: friendly_engine.core.math.Vec3f,
    h0: friendly_engine.core.math.Vec3f,
    h1: friendly_engine.core.math.Vec3f,
    b: friendly_engine.core.math.Vec3f,
    t: f32,
) friendly_engine.core.math.Vec3f {
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

pub fn appendGpuObjects(state: *ProjectEditorState, gpu_objects: *std.ArrayList(gpu_scene.SceneGpuObject)) !void {
    if (!project_editor_state.worldContextVisible(state)) return;
    try refreshIfStale(state);
    for (state.spline_preview.entries.items) |*entry| {
        try gpu_objects.append(state.allocator, .{
            .mesh = &entry.mesh,
            .texture = entry.texture,
            .base_color = entry.base_color,
        });
    }
}

fn renderMeshToEntry(allocator: std.mem.Allocator, input_render_mesh: world.cell.RenderMesh) !Entry {
    var render_mesh = input_render_mesh;
    errdefer render_mesh.deinit(allocator);
    var mesh = geometry.Mesh{
        .vertices = try allocator.alloc(geometry.Vertex, render_mesh.vertices.len),
        .indices = try allocator.dupe(u32, render_mesh.indices),
    };
    errdefer mesh.deinit(allocator);
    for (render_mesh.vertices, 0..) |vertex, idx| {
        mesh.vertices[idx] = .{
            .position = .{ .x = vertex.position.x, .y = vertex.position.y, .z = vertex.position.z },
            .normal = .{ .x = vertex.normal.x, .y = vertex.normal.y, .z = vertex.normal.z },
            .uv = .{ .x = vertex.uv.x, .y = vertex.uv.y },
        };
    }
    const texture = try allocator.dupe(u8, render_mesh.texture);
    const base_color = shared_color.Color{
        .r = render_mesh.base_color.r,
        .g = render_mesh.base_color.g,
        .b = render_mesh.base_color.b,
        .a = render_mesh.base_color.a,
    };
    render_mesh.deinit(allocator);
    return .{ .mesh = mesh, .texture = texture, .base_color = base_color };
}

fn cameraTargetVec(state: *const ProjectEditorState) friendly_engine.core.math.Vec3f {
    return .{
        .x = state.camera.target.x,
        .y = state.camera.target.y,
        .z = state.camera.target.z,
    };
}

fn cellInClipmap(id: world.cell.CellId, camera: friendly_engine.core.math.Vec3f, cell_size_m: f32, draw_distance_m: f32) bool {
    const radius = project_editor_terrain_preview.clipmapRadiusCells(cell_size_m, draw_distance_m);
    const cx = @as(i32, @intFromFloat(@floor(camera.x / cell_size_m)));
    const cy = @as(i32, @intFromFloat(@floor(camera.z / cell_size_m)));
    const dx = @abs(id.x - cx);
    const dy = @abs(id.y - cy);
    return dx <= radius and dy <= radius;
}
