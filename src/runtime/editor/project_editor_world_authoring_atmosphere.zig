const std = @import("std");
const friendly_engine = @import("friendly_engine");

const project_editor_state = @import("project_editor_state.zig");
const project_editor_types = @import("project_editor_types.zig");
const project_editor_terrain_preview = @import("project_editor_terrain_preview.zig");
const manifest = @import("project_editor_world_authoring_manifest.zig");
const world_atmosphere = @import("project_editor_world_atmosphere.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const WorldLayerId = project_editor_types.WorldLayerId;
const modules = friendly_engine.modules;
const atmosphere_types = modules.atmosphere;

pub fn loadIntoState(state: *ProjectEditorState) !void {
    const doc = try atmosphere_types.authoring.loadProject(
        state.allocator,
        state.io,
        state.project_path,
        try manifest.pathForState(state),
    );
    try world_atmosphere.applyDoc(state, doc);
}

pub fn persistFromState(state: *ProjectEditorState) !void {
    try persistSkyTone(state);
    try persistFogBank(state);
}

pub fn persistSkyTone(state: *ProjectEditorState) !void {
    const doc = world_atmosphere.toDoc(state);
    try atmosphere_types.authoring.saveProject(
        state.allocator,
        state.io,
        state.project_path,
        try manifest.pathForState(state),
        doc,
    );
    try markAllCellsDirty(state, "sky tone");
    world_atmosphere.setStatus(state);
}

pub fn persistFogBank(state: *ProjectEditorState) !void {
    try world_atmosphere.upsertEditingCellFog(state);
    const doc = world_atmosphere.toDoc(state);
    try atmosphere_types.authoring.saveProject(
        state.allocator,
        state.io,
        state.project_path,
        try manifest.pathForState(state),
        doc,
    );
    const cell = world_atmosphere.editingCell(state);
    try project_editor_state.markDirtyCell(state, "Atmosphere", .{
        .x = cell.x,
        .y = cell.y,
        .z = cell.z,
    }, "fog bank");
    project_editor_terrain_preview.scheduleBake(state);
    world_atmosphere.setStatus(state);
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
        try project_editor_state.markDirtyCell(state, "Atmosphere", .{
            .x = entry.id.x,
            .y = entry.id.y,
            .z = entry.id.z,
        }, change);
    }
    project_editor_terrain_preview.scheduleBake(state);
}

test "persist atmosphere writes layer file and marks cells dirty" {
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
        .world_sun_azimuth_deg = 210,
        .world_fog_enabled = true,
        .world_fog_start_m = 12,
        .world_fog_end_m = 96,
        .selected_world_layer = .atmosphere_fog_bank,
    };
    defer state.deinit();

    try persistSkyTone(&state);
    try std.testing.expectEqual(@as(usize, 2), state.dirty_cells.count);

    state.dirty_cells.count = 0;
    try persistFogBank(&state);
    try std.testing.expectEqual(@as(usize, 1), state.dirty_cells.count);

    const bytes = try tmp.dir.readFileAlloc(std.testing.io, "layers/atmosphere.kdl", std.testing.allocator, .limited(4096));
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "sun_azimuth_deg=210") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "cell_fog_bank") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "start_m=12") != null);
}

test "persist fog bank writes cell override kdl" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = manifest.world_manifest_path,
        .data =
        \\world version=1 id="main" cell_size_m=64 {
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
        .world_cell_size_m = 64,
        .world_fog_enabled = true,
        .world_fog_start_m = 5,
        .world_fog_end_m = 55,
        .world_fog_color_r = 0x44,
        .world_fog_color_g = 0x55,
        .world_fog_color_b = 0x66,
    };
    defer state.deinit();
    state.camera.target = .{ .x = 96, .y = 0, .z = 32 };

    try persistFogBank(&state);
    const bytes = try tmp.dir.readFileAlloc(std.testing.io, "layers/atmosphere.kdl", std.testing.allocator, .limited(4096));
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "cell_fog_bank cell=\"1,0,0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "color=\"#445566\"") != null);
}
