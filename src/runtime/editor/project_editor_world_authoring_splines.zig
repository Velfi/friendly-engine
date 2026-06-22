const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const editor_math = shared.editor_math;

const project_editor_state = @import("project_editor_state.zig");
const project_editor_types = @import("project_editor_types.zig");
const project_editor_terrain_preview = @import("project_editor_terrain_preview.zig");
const manifest = @import("project_editor_world_authoring_manifest.zig");
const terrain_authoring = @import("project_editor_world_authoring_terrain.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const WorldLayerId = project_editor_types.WorldLayerId;
const modules = friendly_engine.modules;
const world = friendly_engine.world;

pub fn commitRoadBetween(
    state: *ProjectEditorState,
    start: editor_math.Vec3,
    end: editor_math.Vec3,
) ![]u8 {
    const points = [_]editor_math.Vec3{ start, end };
    return try commitRoadPath(state, &points);
}

pub fn commitRoadPath(
    state: *ProjectEditorState,
    points: []const editor_math.Vec3,
) ![]u8 {
    if (points.len < 2) return error.InvalidRoadSegment;

    const layer = resolveSplineLayer(state);
    if (layer != .spline_road_main and layer != .spline_path_side) {
        project_editor_state.setStatus(state, "Select spline layer: road_main or path_side");
        return manifest.WorldLayerNotSpline;
    }

    const width = @max(0.5, state.world_road_width);
    const elevation: f32 = state.world_road_conform_offset;
    const material_mask: u8 = if (layer == .spline_path_side) 200 else 255;
    const render_mode: modules.splines.authoring.RoadRenderMode = switch (state.world_road_surface_mode) {
        .decal => .decal,
        .prop_sections => .prop_sections,
    };
    const terrain_mode: modules.splines.authoring.RoadTerrainMode = switch (state.world_road_terrain_mode) {
        .conform => .conform,
        .floating => .floating,
        .tunnel_reserved => .tunnel_reserved,
    };

    var world_manifest = try world.manifest.loadManifest(state.allocator, state.io, state.project_path, try manifest.pathForState(state));
    defer world_manifest.deinit();

    var doc = try modules.splines.authoring.load(state.allocator, state.io, state.project_path, try manifest.pathForState(state));
    defer doc.deinit();

    var id_buf: [96]u8 = undefined;
    const anchor = try manifest.cellForPoint(state, points[0]);
    const base_id = try std.fmt.bufPrint(&id_buf, "{s}_{d}_{d}_{d}_{d}", .{
        if (layer == .spline_path_side) "path" else "road",
        anchor.x,
        anchor.y,
        anchor.z,
        doc.road_edges.items.len,
    });

    var nodes = std.ArrayList(modules.splines.authoring.RoadNodeInput).empty;
    defer {
        for (nodes.items) |node| state.allocator.free(node.id);
        nodes.deinit(state.allocator);
    }
    var edges = std.ArrayList(modules.splines.authoring.RoadEdgeInput).empty;
    defer {
        for (edges.items) |edge| {
            state.allocator.free(edge.id);
            state.allocator.free(edge.start_node_id);
            state.allocator.free(edge.end_node_id);
        }
        edges.deinit(state.allocator);
    }
    var road_points = std.ArrayList(friendly_engine.core.math.Vec3f).empty;
    defer road_points.deinit(state.allocator);

    var path_length: f32 = 0;
    for (points, 0..) |point, index| {
        const current: friendly_engine.core.math.Vec3f = .{ .x = point.x, .y = point.y, .z = point.z };
        try road_points.append(state.allocator, current);
        if (index > 0) {
            const prev = points[index - 1];
            const dx = point.x - prev.x;
            const dz = point.z - prev.z;
            if (@sqrt(dx * dx + dz * dz) <= 0.001) return error.InvalidRoadSegment;
            path_length += @sqrt(dx * dx + dz * dz);
        }
        const node_id = try std.fmt.allocPrint(state.allocator, "{s}.node.{d}", .{ base_id, index });
        try nodes.append(state.allocator, .{
            .id = node_id,
            .position = current,
            .kind = if (index > 0 and index + 1 < points.len) .junction else .endpoint,
            .terrain_mode = terrain_mode,
        });
    }

    var segment_index: usize = 0;
    while (segment_index + 1 < points.len) : (segment_index += 1) {
        const a = road_points.items[segment_index];
        const b = road_points.items[segment_index + 1];
        const edge_id = try std.fmt.allocPrint(state.allocator, "{s}.edge.{d}", .{ base_id, segment_index });
        const start_id = try std.fmt.allocPrint(state.allocator, "{s}.node.{d}", .{ base_id, segment_index });
        const end_id = try std.fmt.allocPrint(state.allocator, "{s}.node.{d}", .{ base_id, segment_index + 1 });
        try edges.append(state.allocator, .{
            .id = edge_id,
            .start_node_id = start_id,
            .end_node_id = end_id,
            .handle_start = lerp(a, b, 0.33),
            .handle_end = lerp(a, b, 0.66),
            .width = width,
            .elevation = elevation,
            .material_mask_value = material_mask,
            .render_mode = render_mode,
            .terrain_mode = terrain_mode,
            .decal_material = "road.dirt",
            .prop_asset_id = "",
        });
    }

    for (nodes.items) |node| try doc.upsertRoadNode(node);
    for (edges.items) |edge| try doc.upsertRoadEdge(edge);
    const selected_edge_id = try state.allocator.dupe(u8, edges.items[0].id);
    errdefer state.allocator.free(selected_edge_id);
    try modules.splines.authoring.save(doc, state.io, state.project_path, try manifest.pathForState(state));

    const change: []const u8 = if (layer == .spline_path_side) "path road graph" else "road graph";
    var marked_spline = false;
    for (world_manifest.cells) |entry| {
        const bounds = world.cell.boundsForCell(entry.id, world_manifest.cell_size_m, world.cell.default_cell_height_m);
        if (terrain_mode != .conform) continue;
        if (!modules.splines.deformation.roadCrossesCell(.{
            .points = road_points.items,
            .width = width,
            .elevation = elevation,
            .material_mask_value = material_mask,
        }, bounds)) continue;
        try project_editor_state.markDirtyCell(state, "Splines", entry.id, change);
        marked_spline = true;
        try deformTerrainTileForRoad(state, entry.id, world_manifest.cell_size_m, road_points.items, width, elevation, material_mask);
    }
    if (!marked_spline) {
        try project_editor_state.markDirtyCell(state, "Splines", anchor, change);
        if (terrain_mode == .conform) try deformTerrainTileForRoad(state, anchor, world_manifest.cell_size_m, road_points.items, width, elevation, material_mask);
    }

    state.spline_preview_stale = true;
    state.terrain_preview_stale = true;
    project_editor_terrain_preview.scheduleBake(state);

    var status_buf: [180]u8 = undefined;
    project_editor_state.setStatus(state, std.fmt.bufPrint(
        &status_buf,
        "Road graph {s}: {d:.1}m wide, {d:.1}m long, {d} node(s), {d} edge(s)",
        .{ base_id, width, path_length, nodes.items.len, edges.items.len },
    ) catch "Road graph saved");
    return selected_edge_id;
}

pub fn persistRoadGraphDoc(
    state: *ProjectEditorState,
    doc: modules.splines.authoring.SplinesAuthoringDoc,
    change: []const u8,
    require_terrain: bool,
) !void {
    if (require_terrain) try validateConformingRoadTerrain(state, &doc);
    try modules.splines.authoring.save(doc, state.io, state.project_path, try manifest.pathForState(state));
    try markRoadGraphDirty(state, &doc, change);
    state.spline_preview_stale = true;
    state.terrain_preview_stale = true;
    project_editor_terrain_preview.scheduleBake(state);
    project_editor_state.setStatus(state, change);
}

pub fn roadWidthForLayer(layer: WorldLayerId, brush_size: f32) f32 {
    return if (layer == .spline_path_side) 2 else std.math.clamp(brush_size * 0.5, 4, 16);
}

pub fn resolveSplineLayer(state: *const ProjectEditorState) WorldLayerId {
    const layer = state.selected_world_layer orelse .spline_road_main;
    if (layer == .spline_road_main or layer == .spline_path_side) return layer;
    return .spline_road_main;
}

fn lerp(a: friendly_engine.core.math.Vec3f, b: friendly_engine.core.math.Vec3f, t: f32) friendly_engine.core.math.Vec3f {
    return .{
        .x = a.x + (b.x - a.x) * t,
        .y = a.y + (b.y - a.y) * t,
        .z = a.z + (b.z - a.z) * t,
    };
}

fn deformTerrainTileForRoad(
    state: *ProjectEditorState,
    id: world.cell.CellId,
    cell_size_m: f32,
    points: []const friendly_engine.core.math.Vec3f,
    width: f32,
    elevation: f32,
    material_mask_value: u8,
) !void {
    const existing_tile = try modules.terrain.authoring.loadCell(state.allocator, state.io, state.project_path, try manifest.pathForState(state), id);
    if (existing_tile == null) return;
    var owned_tile = existing_tile.?;
    defer owned_tile.deinit();

    const bounds = world.cell.boundsForCell(id, cell_size_m, world.cell.default_cell_height_m);
    const heights = try loadOrDefaultHeights(state, id);
    defer state.allocator.free(heights);
    var palette = try terrain_authoring.loadOrDefaultPaintPalette(state, id);
    defer palette.deinit(state.allocator);
    const splat = try terrain_authoring.loadOrDefaultSplat(state, id);
    defer state.allocator.free(splat);
    if (palette.layers.len < 2) return error.InvalidTerrainPaintLayers;

    modules.splines.deformation.applyRoadDeformation(bounds, cell_size_m, terrain_authoring.terrain_tile_size, heights, splat, .{
        .points = points,
        .width = width,
        .elevation = elevation,
        .material_mask_value = material_mask_value,
        .paint_layer_index = palette.layers.len - 1,
        .paint_layer_count = palette.layers.len,
    });

    const material = try loadTileMaterial(state, id);
    defer state.allocator.free(material);
    try terrain_authoring.snapshotTerrainEdit(state, id, nowNs(state));
    try terrain_authoring.upsertTerrainTile(state, id, heights, splat, material);
    terrain_authoring.pruneTerrainUndo(state);
    try project_editor_state.markDirtyCell(state, "Terrain", id, "road deformation");
}

fn nowNs(state: *ProjectEditorState) u64 {
    const ns = std.Io.Clock.awake.now(state.io).nanoseconds;
    if (ns <= 0) return 0;
    return @intCast(ns);
}

pub fn validateConformingRoadTerrain(state: *ProjectEditorState, doc: *const modules.splines.authoring.SplinesAuthoringDoc) !void {
    var world_manifest = try world.manifest.loadManifest(state.allocator, state.io, state.project_path, try manifest.pathForState(state));
    defer world_manifest.deinit();

    for (doc.road_edges.items) |edge| {
        if (edge.terrain_mode != .conform) continue;
        const start = doc.road_nodes.items[doc.nodeIndexById(edge.start_node_id) orelse return error.MissingRoadNode].position;
        const end = doc.road_nodes.items[doc.nodeIndexById(edge.end_node_id) orelse return error.MissingRoadNode].position;
        const points = [_]friendly_engine.core.math.Vec3f{ start, end };
        var found_cell = false;
        for (world_manifest.cells) |entry| {
            const bounds = world.cell.boundsForCell(entry.id, world_manifest.cell_size_m, world.cell.default_cell_height_m);
            if (!modules.splines.deformation.roadCrossesCell(.{
                .points = &points,
                .width = edge.width,
                .elevation = edge.elevation,
                .material_mask_value = edge.material_mask_value,
            }, bounds)) continue;
            found_cell = true;
            const terrain_doc = try modules.terrain.authoring.loadCell(state.allocator, state.io, state.project_path, try manifest.pathForState(state), entry.id);
            if (terrain_doc == null) return error.TerrainTileNotFound;
            var owned = terrain_doc.?;
            owned.deinit();
        }
        if (!found_cell) return error.WorldCellNotInManifest;
    }
}

fn markRoadGraphDirty(state: *ProjectEditorState, doc: *const modules.splines.authoring.SplinesAuthoringDoc, change: []const u8) !void {
    var world_manifest = try world.manifest.loadManifest(state.allocator, state.io, state.project_path, try manifest.pathForState(state));
    defer world_manifest.deinit();

    var marked_any = false;
    for (doc.road_edges.items) |edge| {
        const start = doc.road_nodes.items[doc.nodeIndexById(edge.start_node_id) orelse return error.MissingRoadNode].position;
        const end = doc.road_nodes.items[doc.nodeIndexById(edge.end_node_id) orelse return error.MissingRoadNode].position;
        const points = [_]friendly_engine.core.math.Vec3f{ start, end };
        for (world_manifest.cells) |entry| {
            const bounds = world.cell.boundsForCell(entry.id, world_manifest.cell_size_m, world.cell.default_cell_height_m);
            if (!modules.splines.deformation.roadCrossesCell(.{
                .points = &points,
                .width = edge.width,
                .elevation = edge.elevation,
                .material_mask_value = edge.material_mask_value,
            }, bounds)) continue;
            try project_editor_state.markDirtyCell(state, "Splines", entry.id, change);
            marked_any = true;
            if (edge.terrain_mode == .conform) {
                try deformTerrainTileForRoad(state, entry.id, world_manifest.cell_size_m, &points, edge.width, edge.elevation, edge.material_mask_value);
            }
        }
    }
    if (!marked_any) {
        try project_editor_state.markDirtyCell(state, "Splines", .{ .x = 0, .y = 0, .z = 0 }, change);
    }
}

fn loadOrDefaultHeights(state: *ProjectEditorState, id: world.cell.CellId) ![]f32 {
    const sample_count = @as(usize, terrain_authoring.terrain_tile_size) * @as(usize, terrain_authoring.terrain_tile_size);
    const doc = try modules.terrain.authoring.loadCell(state.allocator, state.io, state.project_path, try manifest.pathForState(state), id);
    if (doc) |loaded| {
        var owned_doc = loaded;
        defer owned_doc.deinit();
        if (owned_doc.tiles.items.len != 1) return error.InvalidTerrainDocument;
        const tile = owned_doc.tiles.items[0];
        return terrain_authoring.heightsForEditing(state.allocator, tile.size, tile.heights, terrain_authoring.terrain_tile_size);
    }
    const heights = try state.allocator.alloc(f32, sample_count);
    @memset(heights, 0);
    return heights;
}

fn loadTileMaterial(state: *ProjectEditorState, id: world.cell.CellId) ![]u8 {
    const doc = try modules.terrain.authoring.loadCell(state.allocator, state.io, state.project_path, try manifest.pathForState(state), id);
    if (doc) |loaded| {
        var owned_doc = loaded;
        defer owned_doc.deinit();
        if (owned_doc.tiles.items.len != 1) return error.InvalidTerrainDocument;
        return state.allocator.dupe(u8, owned_doc.tiles.items[0].material);
    }
    return state.allocator.dupe(u8, "terrain.editor");
}

test "road width follows selected spline layer" {
    try std.testing.expectEqual(@as(f32, 4), roadWidthForLayer(.spline_road_main, 8));
    try std.testing.expectEqual(@as(f32, 2), roadWidthForLayer(.spline_path_side, 8));
}

test "committed road path returns first edge id for selection" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = manifest.world_manifest_path,
        .data =
        \\world version=1 id="main" cell_size_m=64 {
        \\  cell coord="0,0,0" authoring="scenes/main.kdl"
        \\}
        \\
        ,
    });
    const project_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(project_path);
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = @constCast(project_path),
        .active_world_manifest_path = manifest.world_manifest_path,
        .project_name = "",
        .objects = .empty,
        .selected_world_layer = .spline_road_main,
        .world_road_width = 6,
    };

    const edge_id = try commitRoadPath(&state, &.{
        .{ .x = 4, .y = 0, .z = 8 },
        .{ .x = 40, .y = 0, .z = 8 },
        .{ .x = 56, .y = 0, .z = 20 },
    });
    defer std.testing.allocator.free(edge_id);

    try std.testing.expectEqualStrings("road_0_0_0_0.edge.0", edge_id);
    const bytes = try tmp.dir.readFileAlloc(std.testing.io, "layers/splines.kdl", std.testing.allocator, .limited(8192));
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "road_0_0_0_0.edge.0") != null);
    try std.testing.expectEqualStrings("road graph", state.dirty_cells.last().?.last_change);
}
