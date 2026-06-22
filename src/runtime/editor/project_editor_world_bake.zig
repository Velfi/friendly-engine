const std = @import("std");
const friendly_engine = @import("friendly_engine");
const project_editor_state = @import("project_editor_state.zig");

const world = friendly_engine.world;
const ProjectEditorState = project_editor_state.ProjectEditorState;

pub fn recompileDirtyCells(state: *ProjectEditorState) void {
    if (state.dirty_cells.count == 0) {
        project_editor_state.setStatus(state, "No dirty cells to bake");
        return;
    }
    var baked: usize = 0;
    var i: usize = 0;
    while (i < state.dirty_cells.count) {
        const cell = state.dirty_cells.cells[i].cell;
        if (bakeOneCell(state, cell)) {
            baked += 1;
            state.dirty_cells.removeCell(cell);
        } else {
            i += 1;
        }
    }
    state.terrain_preview_stale = true;
    state.spline_preview_stale = true;
    var buf: [96]u8 = undefined;
    project_editor_state.setStatus(state, std.fmt.bufPrint(&buf, "Baked {d} dirty cells", .{baked}) catch "Bake complete");
    verifyBakedCells(state);
}

pub fn bakeOneCell(state: *ProjectEditorState, id: world.cell.CellId) bool {
    var coord_buf: [32]u8 = undefined;
    const coord = std.fmt.bufPrint(&coord_buf, "{d},{d},{d}", .{ id.x, id.y, id.z }) catch return false;
    const result = std.process.run(state.allocator, state.io, .{
        .argv = &.{ "zig", "build", "run-tools", "--", "world-bake", "--cell", coord },
        .cwd = .{ .path = state.project_path },
        .stdout_limit = .limited(16 * 1024),
        .stderr_limit = .limited(16 * 1024),
    }) catch return false;
    defer state.allocator.free(result.stdout);
    defer state.allocator.free(result.stderr);
    return result.term == .exited and result.term.exited == 0;
}

pub fn verifyBakedCells(state: *ProjectEditorState) void {
    var loaded: usize = 0;
    for (state.dirty_cells.cells[0..state.dirty_cells.count]) |entry| {
        const path = world.fcell.bakedCellPath(state.allocator, "client-debug", "main", entry.cell) catch continue;
        defer state.allocator.free(path);
        var dir = std.Io.Dir.cwd().openDir(state.io, state.project_path, .{}) catch continue;
        defer dir.close(state.io);
        if (dir.access(state.io, path, .{})) |_| {
            loaded += 1;
        } else |_| {}
    }
    state.baked_cell_count = loaded;
}

test "coord formatting for targeted bake" {
    var buf: [32]u8 = undefined;
    const coord = try std.fmt.bufPrint(&buf, "{d},{d},{d}", .{ 1, -2, 0 });
    try std.testing.expectEqualStrings("1,-2,0", coord);
}
