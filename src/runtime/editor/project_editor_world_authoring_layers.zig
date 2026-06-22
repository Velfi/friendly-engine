const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const editor_math = shared.editor_math;

const project_editor_state = @import("project_editor_state.zig");
const manifest = @import("project_editor_world_authoring_manifest.zig");
const splines = @import("project_editor_world_authoring_splines.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const modules = friendly_engine.modules;
const world = friendly_engine.world;

pub fn drawRoadThroughCell(state: *ProjectEditorState) !void {
    const id = try manifest.cellForPoint(state, state.camera.target);
    var world_manifest = try world.manifest.loadManifest(state.allocator, state.io, state.project_path, try manifest.pathForState(state));
    defer world_manifest.deinit();
    const bounds = world.cell.boundsForCell(id, world_manifest.cell_size_m, world.cell.default_cell_height_m);
    const z = (bounds.min.z + bounds.max.z) * 0.5;
    const edge_id = try splines.commitRoadBetween(state, .{
        .x = bounds.min.x + 4,
        .y = state.camera.target.y,
        .z = z,
    }, .{
        .x = bounds.max.x - 4,
        .y = state.camera.target.y,
        .z = z,
    });
    state.allocator.free(edge_id);
}

pub fn drawRoadAt(state: *ProjectEditorState, point: editor_math.Vec3) !void {
    _ = point;
    project_editor_state.setStatus(state, "Roads tool: click two points or drag a spline in the viewport");
}

pub fn authorInteriorRoom(state: *ProjectEditorState) !void {
    const parent = try manifest.cellForPoint(state, state.camera.target);
    const id = try manifest.interiorChildForCell(state, parent);
    const room = modules.sectors.RoomPlan{
        .id = 1,
        .origin = .{ 0, 0 },
        .size = .{ 8, 8 },
        .floor_height = 0,
        .ceiling_height = 3,
    };
    var scratch = modules.sectors.SectorPolygonScratch{};
    const sector = try modules.sectors.makeRectangularSector(&scratch, room, &.{});
    try modules.sectors.validateSector(sector);

    var kdl_out: std.Io.Writer.Allocating = .init(state.allocator);
    defer kdl_out.deinit();
    const writer = &kdl_out.writer;
    try writer.print(
        "sectors version=1 {{\n  interior cell=\"{d},{d},{d}\" parent_cell=\"{d},{d},0\" {{\n",
        .{ id.x, id.y, id.z, parent.x, parent.y },
    );
    try writer.writeAll("    sector id=1 floor_height=0 ceiling_height=3 polygon=\"0,0; 8,0; 8,8; 0,8\"\n");
    try writer.writeAll("  }\n}\n");
    const bytes = try kdl_out.toOwnedSlice();
    defer state.allocator.free(bytes);
    try manifest.writeLayerBytes(state, "layers/sectors.kdl", bytes);
}

pub fn authorBuilding(state: *ProjectEditorState) !void {
    const id = try manifest.cellForPoint(state, state.camera.target);
    const doors = [_]modules.buildings.DoorDef{.{ .edge_index = 0, .offset = 0.5, .width = 1.5, .height = 2.2 }};
    const windows = [_]modules.buildings.WindowDef{.{ .edge_index = 1, .offset = 0.5, .width = 1.2, .height = 1.0, .sill = 1.1 }};
    const descriptor = modules.buildings.BuildingDescriptor{
        .id = "editor_building",
        .cell = .{ id.x, id.y, id.z },
        .kind = .house,
        .origin = .{ 10, 2 },
        .size = .{ 8, 6 },
        .floors = 2,
        .doors = &doors,
        .windows = &windows,
    };
    var scratch = modules.buildings.BuildingFootprintScratch{};
    const building = try modules.buildings.makeRectangularBuilding(&scratch, descriptor);
    try modules.buildings.validateBuilding(building);

    var kdl_out: std.Io.Writer.Allocating = .init(state.allocator);
    defer kdl_out.deinit();
    try kdl_out.writer.print(
        "buildings version=1 {{\n  building id=\"editor_building\" cell=\"{d},{d},{d}\" floors=2 footprint=\"10,2; 18,2; 18,8; 10,8\" {{\n    door edge_index=0 offset=0.5 width=1.5 height=2.2\n    window edge_index=1 offset=0.5 width=1.2 height=1.0 sill=1.1\n  }}\n}}\n",
        .{ id.x, id.y, id.z },
    );
    const bytes = try kdl_out.toOwnedSlice();
    defer state.allocator.free(bytes);
    try manifest.writeLayerBytes(state, "layers/buildings.kdl", bytes);
}
