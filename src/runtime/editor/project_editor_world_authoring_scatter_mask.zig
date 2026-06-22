const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const editor_math = shared.editor_math;

const project_editor_state = @import("project_editor_state.zig");
const project_editor_scatter_preview = @import("project_editor_scatter_preview.zig");
const manifest = @import("project_editor_world_authoring_manifest.zig");
const terrain = @import("project_editor_world_authoring_terrain.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const modules = friendly_engine.modules;
const world = friendly_engine.world;

pub const mask_tile_size = terrain.terrain_tile_size;

pub fn paintDensityMaskAt(state: *ProjectEditorState, point: editor_math.Vec3) !void {
    const id = try manifest.cellForPoint(state, point);
    var world_manifest = try world.manifest.loadManifest(state.allocator, state.io, state.project_path, try manifest.pathForState(state));
    defer world_manifest.deinit();
    const cell_size_m = world_manifest.cell_size_m;
    const bounds = world.cell.boundsForCell(id, cell_size_m, world.cell.default_cell_height_m);

    const size = mask_tile_size;
    const sample_count = @as(usize, size) * @as(usize, size);
    var values = try loadOrDefaultMask(state, id, sample_count);
    defer state.allocator.free(values);

    const center = terrain.brushCenterSamples(point, bounds, cell_size_m, size);
    const radius_samples = @max(0.5, (state.world_brush_size / cell_size_m) * @as(f32, @floatFromInt(size)));

    var affected_samples: usize = 0;
    var peak_value: u8 = 0;
    var y: usize = 0;
    while (y < size) : (y += 1) {
        var x: usize = 0;
        while (x < size) : (x += 1) {
            const weight = terrain.brushWeightAt(
                x,
                y,
                center.x,
                center.y,
                radius_samples,
                state.world_brush_falloff,
                state.world_brush_strength,
            );
            if (weight <= 0) continue;
            const idx = y * @as(usize, size) + x;
            affected_samples += 1;
            const blended = @as(f32, @floatFromInt(values[idx])) + weight * (255.0 - @as(f32, @floatFromInt(values[idx])));
            values[idx] = @intFromFloat(@round(std.math.clamp(blended, 0, 255)));
            peak_value = @max(peak_value, values[idx]);
        }
    }

    try modules.scatter.authoring.upsertDensityMaskFile(
        state.allocator,
        state.io,
        state.project_path,
        try manifest.pathForState(state),
        .{ id.x, id.y, id.z },
        size,
        values,
    );
    project_editor_scatter_preview.markStale(state);
    try project_editor_state.markDirtyCell(state, "Scatter", id, "density mask");
    setPaintStatus(state, id, affected_samples, peak_value);
}

fn loadOrDefaultMask(state: *ProjectEditorState, id: world.cell.CellId, sample_count: usize) ![]u8 {
    var doc = try modules.scatter.authoring.loadProject(state.allocator, state.io, state.project_path, try manifest.pathForState(state));
    defer doc.deinit();
    for (doc.density_masks.items) |mask| {
        if (mask.cell[0] == id.x and mask.cell[1] == id.y and mask.cell[2] == id.z) {
            if (mask.size != mask_tile_size or mask.values.len != sample_count) return error.InvalidDensityMask;
            return state.allocator.dupe(u8, mask.values);
        }
    }
    const values = try state.allocator.alloc(u8, sample_count);
    @memset(values, 0);
    return values;
}

fn setPaintStatus(state: *ProjectEditorState, id: world.cell.CellId, affected_samples: usize, peak_value: u8) void {
    var buf: [160]u8 = undefined;
    const message = std.fmt.bufPrint(
        &buf,
        "Scatter density mask: cell {d},{d},{d}, {d} samples, peak {d}",
        .{ id.x, id.y, id.z, affected_samples, peak_value },
    ) catch "Scatter density mask applied";
    project_editor_state.setStatus(state, message);
}

test "scatter density mask paint writes kdl and marks dirty" {
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
        .camera = .{ .target = .{ .x = 32, .y = 0, .z = 32 } },
        .selected_world_layer = .scatter_density_mask,
        .world_brush_size = 32.0,
        .world_brush_strength = 1.0,
        .world_brush_falloff = 0.5,
    };

    try paintDensityMaskAt(&state, .{ .x = 32, .y = 0, .z = 32 });

    try std.testing.expectEqual(@as(usize, 1), state.dirty_cells.count);
    try std.testing.expectEqualStrings("density mask", state.dirty_cells.last().?.last_change);
    const bytes = try tmp.dir.readFileAlloc(std.testing.io, "layers/scatter.kdl", std.testing.allocator, .limited(65536));
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "density_mask ") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, std.fmt.comptimePrint("size={d}", .{mask_tile_size})) != null);
}
