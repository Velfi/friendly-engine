const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const project_editor_state = @import("project_editor_state.zig");

const atmosphere_render = shared.atmosphere_render;
const shared_color = shared.color;
const ProjectEditorState = project_editor_state.ProjectEditorState;
const AtmosphereDoc = friendly_engine.modules.atmosphere.AtmosphereDoc;
const CloudTone = friendly_engine.modules.atmosphere.CloudTone;
const FogBank = friendly_engine.modules.atmosphere.FogBank;
const world_cell = friendly_engine.world.cell;

pub const min_elevation_deg = atmosphere_render.min_elevation_deg;
pub const max_elevation_deg = atmosphere_render.max_elevation_deg;

pub fn buildFrameLighting(state: *const ProjectEditorState) shared.render_lighting.FrameLighting {
    const fog = atmosphere_render.frameFogFromBank(.{
        .enabled = state.world_fog_enabled,
        .color_r = state.world_fog_color_r,
        .color_g = state.world_fog_color_g,
        .color_b = state.world_fog_color_b,
        .start_m = state.world_fog_start_m,
        .end_m = state.world_fog_end_m,
    });
    return atmosphere_render.buildFrameLighting(toSkyTone(state), fog, state.camera);
}

pub fn skyColor(state: *const ProjectEditorState) shared_color.Color {
    return atmosphere_render.skyColor(toSkyTone(state));
}

pub fn paintSky(
    pixels: []u8,
    width: u32,
    height: u32,
    camera: shared.editor_math.OrbitCamera,
    state: *const ProjectEditorState,
) void {
    atmosphere_render.paintSky(pixels, width, height, camera, toSkyTone(state));
}

pub fn buildFrameSky(state: *const ProjectEditorState) shared.render_sky.FrameSky {
    return atmosphere_render.buildFrameSky(toSkyTone(state), toCloudTone(state), state.camera, state.life_time);
}

pub fn ambientLevel(state: *const ProjectEditorState) f32 {
    return atmosphere_render.ambientLevel(toSkyTone(state));
}

pub fn sunSkyVector(state: *const ProjectEditorState) shared.editor_math.Vec3 {
    return atmosphere_render.sunSkyVector(toSkyTone(state));
}

pub fn moonSkyVector(state: *const ProjectEditorState) shared.editor_math.Vec3 {
    return atmosphere_render.moonSkyVector(toSkyTone(state));
}

pub fn clampElevation(value: f32) f32 {
    return atmosphere_render.clampElevation(value);
}

pub fn wrapAzimuth(value: f32) f32 {
    return atmosphere_render.wrapAzimuth(value);
}

pub fn editingCell(state: *const ProjectEditorState) world_cell.CellId {
    const target = state.camera.target;
    return world_cell.idAtPosition(
        target.x,
        target.z,
        target.y,
        state.world_cell_size_m,
        world_cell.default_cell_height_m,
        false,
    );
}

pub fn applyDoc(state: *ProjectEditorState, doc: AtmosphereDoc) !void {
    state.world_sun_enabled = doc.sky_tone.sun_enabled;
    state.world_sun_azimuth_deg = doc.sky_tone.sun_azimuth_deg;
    state.world_sun_elevation_deg = doc.sky_tone.sun_elevation_deg;
    state.world_moon_enabled = doc.sky_tone.moon_enabled;
    state.world_moon_azimuth_deg = doc.sky_tone.moon_azimuth_deg;
    state.world_moon_elevation_deg = doc.sky_tone.moon_elevation_deg;
    state.world_star_seed = doc.sky_tone.star_seed;
    state.world_clouds_enabled = doc.clouds.enabled;
    state.world_cloud_coverage = doc.clouds.coverage;
    state.world_cloud_softness = doc.clouds.softness;
    state.world_cloud_scale = doc.clouds.scale;
    state.world_cloud_height_bias = doc.clouds.height_bias;
    state.world_cloud_drift_dir_x = doc.clouds.drift_dir_x;
    state.world_cloud_drift_dir_y = doc.clouds.drift_dir_y;
    state.world_cloud_drift_speed = doc.clouds.drift_speed;
    state.world_cloud_seed = doc.clouds.seed;
    state.world_cloud_parallax_enabled = doc.clouds.parallax_enabled;
    state.atmosphere_default_fog = doc.fog_bank;

    state.atmosphere_cell_fogs.clearRetainingCapacity();
    try state.atmosphere_cell_fogs.ensureTotalCapacity(state.allocator, doc.cell_fog_banks.len);
    for (doc.cell_fog_banks) |entry| {
        try state.atmosphere_cell_fogs.append(state.allocator, entry);
    }

    syncFogFieldsForEditingCell(state);
}

pub fn toDoc(state: *const ProjectEditorState) AtmosphereDoc {
    return .{
        .sky_tone = toSkyTone(state),
        .clouds = toCloudTone(state),
        .fog_bank = state.atmosphere_default_fog,
        .cell_fog_banks = state.atmosphere_cell_fogs.items,
    };
}

pub fn syncFogFieldsForEditingCell(state: *ProjectEditorState) void {
    const cell = editingCell(state);
    if (state.atmosphere_fog_edit_cell.eql(cell)) return;
    state.atmosphere_fog_edit_cell = cell;
    applyFogBank(state, fogForCell(state, cell));
}

pub fn upsertEditingCellFog(state: *ProjectEditorState) !void {
    const cell = editingCell(state);
    const fog = fogFromState(state);
    for (state.atmosphere_cell_fogs.items, 0..) |entry, index| {
        if (world_cell.CellId.eql(world_cell.CellId{ .x = entry.cell[0], .y = entry.cell[1], .z = entry.cell[2] }, cell)) {
            state.atmosphere_cell_fogs.items[index].fog = fog;
            return;
        }
    }
    try state.atmosphere_cell_fogs.append(state.allocator, .{
        .cell = .{ cell.x, cell.y, cell.z },
        .fog = fog,
    });
}

pub fn fogScopeLabel(state: *const ProjectEditorState, buf: []u8) ![]const u8 {
    const cell = editingCell(state);
    const override = hasFogOverride(state, cell);
    return std.fmt.bufPrint(buf, "Cell {d},{d},{d}{s}", .{
        cell.x,
        cell.y,
        cell.z,
        if (override) " override" else " default",
    });
}

pub fn fogColor(state: *const ProjectEditorState) shared_color.Color {
    return .{
        .r = state.world_fog_color_r,
        .g = state.world_fog_color_g,
        .b = state.world_fog_color_b,
        .a = 255,
    };
}

pub fn setStatus(state: *ProjectEditorState) void {
    var buf: [160]u8 = undefined;
    const cell = editingCell(state);
    const text = std.fmt.bufPrint(
        &buf,
        "Sky sun {s} {d:.0}/{d:.0}  moon {s} {d:.0}/{d:.0}  stars {d}  clouds {s} {d:.2}  fog {s} {d:.0}-{d:.0}m cell {d},{d},{d}  ambient {d:.2}",
        .{
            if (state.world_sun_enabled) "on" else "off",
            state.world_sun_azimuth_deg,
            state.world_sun_elevation_deg,
            if (state.world_moon_enabled) "on" else "off",
            state.world_moon_azimuth_deg,
            state.world_moon_elevation_deg,
            state.world_star_seed,
            if (state.world_clouds_enabled) "on" else "off",
            state.world_cloud_coverage,
            if (state.world_fog_enabled) "on" else "off",
            state.world_fog_start_m,
            state.world_fog_end_m,
            cell.x,
            cell.y,
            cell.z,
            ambientLevel(state),
        },
    ) catch "Sky updated";
    project_editor_state.setStatus(state, text);
}

fn fogForCell(state: *const ProjectEditorState, cell: world_cell.CellId) FogBank {
    for (state.atmosphere_cell_fogs.items) |entry| {
        const entry_id = world_cell.CellId{ .x = entry.cell[0], .y = entry.cell[1], .z = entry.cell[2] };
        if (entry_id.eql(cell)) return entry.fog;
    }
    return state.atmosphere_default_fog;
}

fn hasFogOverride(state: *const ProjectEditorState, cell: world_cell.CellId) bool {
    for (state.atmosphere_cell_fogs.items) |entry| {
        const entry_id = world_cell.CellId{ .x = entry.cell[0], .y = entry.cell[1], .z = entry.cell[2] };
        if (entry_id.eql(cell)) return true;
    }
    return false;
}

fn applyFogBank(state: *ProjectEditorState, fog: FogBank) void {
    state.world_fog_enabled = fog.enabled;
    state.world_fog_preview = fog.enabled;
    state.world_fog_start_m = fog.start_m;
    state.world_fog_end_m = fog.end_m;
    state.world_fog_color_r = fog.color_r;
    state.world_fog_color_g = fog.color_g;
    state.world_fog_color_b = fog.color_b;
}

fn fogFromState(state: *const ProjectEditorState) FogBank {
    return .{
        .enabled = state.world_fog_enabled,
        .color_r = state.world_fog_color_r,
        .color_g = state.world_fog_color_g,
        .color_b = state.world_fog_color_b,
        .start_m = state.world_fog_start_m,
        .end_m = state.world_fog_end_m,
    };
}

fn toSkyTone(state: *const ProjectEditorState) friendly_engine.modules.atmosphere.SkyTone {
    return .{
        .sun_enabled = state.world_sun_enabled,
        .sun_azimuth_deg = state.world_sun_azimuth_deg,
        .sun_elevation_deg = state.world_sun_elevation_deg,
        .moon_enabled = state.world_moon_enabled,
        .moon_azimuth_deg = state.world_moon_azimuth_deg,
        .moon_elevation_deg = state.world_moon_elevation_deg,
        .star_seed = state.world_star_seed,
    };
}

fn toCloudTone(state: *const ProjectEditorState) CloudTone {
    return .{
        .enabled = state.world_clouds_enabled,
        .coverage = state.world_cloud_coverage,
        .softness = state.world_cloud_softness,
        .scale = state.world_cloud_scale,
        .height_bias = state.world_cloud_height_bias,
        .drift_dir_x = state.world_cloud_drift_dir_x,
        .drift_dir_y = state.world_cloud_drift_dir_y,
        .drift_speed = state.world_cloud_drift_speed,
        .seed = state.world_cloud_seed,
        .parallax_enabled = state.world_cloud_parallax_enabled,
    };
}

test "applyDoc and toDoc round trip editor atmosphere fields" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = @constCast(""),
        .project_name = "",
        .objects = .empty,
    };
    defer state.deinit();
    var doc = AtmosphereDoc{};
    doc.sky_tone.sun_azimuth_deg = 90;
    doc.sky_tone.star_seed = 88;
    doc.clouds.coverage = 0.52;
    doc.fog_bank.enabled = true;
    doc.fog_bank.start_m = 16;
    doc.cell_fog_banks = &.{
        .{ .cell = .{ 1, 0, 0 }, .fog = .{ .enabled = true, .start_m = 4, .end_m = 40 } },
    };
    try applyDoc(&state, doc);
    const out = toDoc(&state);
    try std.testing.expectEqual(@as(f32, 90), out.sky_tone.sun_azimuth_deg);
    try std.testing.expectEqual(@as(u32, 88), out.sky_tone.star_seed);
    try std.testing.expectEqual(@as(f32, 0.52), out.clouds.coverage);
    try std.testing.expect(out.fog_bank.enabled);
    try std.testing.expectEqual(@as(f32, 16), out.fog_bank.start_m);
    try std.testing.expectEqual(@as(usize, 1), out.cell_fog_banks.len);
}

test "syncFogFieldsForEditingCell loads cell override" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = @constCast(""),
        .project_name = "",
        .objects = .empty,
        .world_cell_size_m = 64,
        .atmosphere_default_fog = .{ .enabled = false, .start_m = 8, .end_m = 80 },
    };
    defer state.deinit();
    try state.atmosphere_cell_fogs.append(std.testing.allocator, .{
        .cell = .{ 1, 0, 0 },
        .fog = .{ .enabled = true, .start_m = 4, .end_m = 40 },
    });
    state.camera.target = .{ .x = 96, .y = 0, .z = 32 };
    syncFogFieldsForEditingCell(&state);
    try std.testing.expect(state.world_fog_enabled);
    try std.testing.expectEqual(@as(f32, 4), state.world_fog_start_m);
}

test "no sun or moon makes atmosphere very dark" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = @constCast(""),
        .project_name = "",
        .objects = .empty,
        .world_sun_enabled = false,
        .world_moon_enabled = false,
    };
    defer state.deinit();
    try std.testing.expect(ambientLevel(&state) <= 0.05);
    try std.testing.expect(buildFrameLighting(&state).sun_intensity == 0.0);
}
