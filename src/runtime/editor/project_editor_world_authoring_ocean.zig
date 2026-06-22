const std = @import("std");
const friendly_engine = @import("friendly_engine");

const project_editor_state = @import("project_editor_state.zig");
const project_editor_terrain_preview = @import("project_editor_terrain_preview.zig");
const manifest = @import("project_editor_world_authoring_manifest.zig");
const world_ocean = @import("project_editor_world_ocean.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const ocean_types = friendly_engine.modules.ocean;

pub fn loadIntoState(state: *ProjectEditorState) !void {
    const doc = try ocean_types.authoring.loadProject(
        state.allocator,
        state.io,
        state.project_path,
        try manifest.pathForState(state),
    );
    world_ocean.applyDoc(state, doc);
}

pub fn persistFromState(state: *ProjectEditorState) !void {
    const doc = world_ocean.toDoc(state);
    try ocean_types.authoring.saveProject(
        state.allocator,
        state.io,
        state.project_path,
        try manifest.pathForState(state),
        doc,
    );
    try markAllCellsDirty(state, "waves");
    world_ocean.setStatus(state);
}

fn markAllCellsDirty(state: *ProjectEditorState, change: []const u8) !void {
    var loaded = try friendly_engine.world.manifest.loadManifest(
        state.allocator,
        state.io,
        state.project_path,
        try manifest.pathForState(state),
    );
    defer loaded.deinit();
    for (loaded.cells) |entry| {
        try project_editor_state.markDirtyCell(state, "Ocean", .{
            .x = entry.id.x,
            .y = entry.id.y,
            .z = entry.id.z,
        }, change);
    }
    project_editor_terrain_preview.scheduleBake(state);
}

test "persist ocean writes layer file and marks cells dirty" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = manifest.world_manifest_path,
        .data =
        \\world version=1 id="main" cell_size_m=64 {
        \\  cell coord="0,0,0" authoring="scenes/main.kdl"
        \\  cell coord="1,0,0" authoring="scenes/cell.kdl"
        \\}
        \\
        ,
    });
    var project_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const project_path_len = try tmp.dir.realPath(std.testing.io, &project_path_buf);
    const project_path = try std.testing.allocator.dupe(u8, project_path_buf[0..project_path_len]);

    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = project_path,
        .active_world_manifest_path = manifest.world_manifest_path,
        .project_name = "",
        .objects = .empty,
        .world_ocean_visible = false,
        .ocean_wind_speed_mps = 11,
    };
    defer state.deinit();

    try persistFromState(&state);
    try std.testing.expectEqual(@as(usize, 2), state.dirty_cells.count);

    const bytes = try tmp.dir.readFileAlloc(std.testing.io, "layers/ocean.kdl", std.testing.allocator, .limited(4096));
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "waves enabled=false") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "speed_mps=11") != null);
}
