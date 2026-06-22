const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");

const atmosphere_runtime = friendly_engine.modules.atmosphere.runtime;
const atmosphere_render = shared.atmosphere_render;
const world_mod = friendly_engine.world;

pub const ClientAtmosphereState = struct {
    requires_settings: bool = false,
    settings: ?atmosphere_runtime.CellSettings = null,
    active_cell: ?world_mod.cell.CellId = null,

    pub fn enableWorldPath(self: *ClientAtmosphereState) void {
        self.requires_settings = true;
    }

    pub fn syncFromManager(
        self: *ClientAtmosphereState,
        manager: *world_mod.stream.StreamManager,
        camera: friendly_engine.core.math.Vec3f,
    ) !void {
        if (!self.requires_settings) return;
        const camera_cell = cameraCellId(camera, manager);
        if (self.active_cell) |previous| {
            if (previous.eql(camera_cell) and self.settings != null) return;
        }
        const world_cell = manager.active_cells.get(camera_cell) orelse return error.CameraAtmosphereCellNotLoaded;
        self.settings = try atmosphere_runtime.requireSettingsBlob(world_cell.blobs);
        self.active_cell = camera_cell;
    }

    pub fn skyColor(self: *const ClientAtmosphereState) shared.color.Color {
        const settings = self.settings orelse return .{ .r = 22, .g = 28, .b = 38, .a = 255 };
        return atmosphere_render.skyColor(settings.sky_tone);
    }

    pub fn skyTone(self: *const ClientAtmosphereState) ?friendly_engine.modules.atmosphere.SkyTone {
        const settings = self.settings orelse return null;
        return settings.sky_tone;
    }

    pub fn cloudTone(self: *const ClientAtmosphereState) friendly_engine.modules.atmosphere.CloudTone {
        const settings = self.settings orelse return .{};
        return settings.clouds;
    }

    pub fn paintSky(
        self: *const ClientAtmosphereState,
        pixels: []u8,
        width: u32,
        height: u32,
        camera: shared.editor_math.OrbitCamera,
    ) void {
        const settings = self.settings orelse return;
        atmosphere_render.paintSky(pixels, width, height, camera, settings.sky_tone);
    }

    pub fn buildFrameLighting(self: *const ClientAtmosphereState, camera: shared.editor_math.OrbitCamera) shared.render_lighting.FrameLighting {
        const settings = self.settings orelse return .{ .shading_lit = true, .camera_position = camera.eye() };
        const fog = atmosphere_render.frameFogFromBaked(
            settings.fog_bank.enabled,
            settings.fog_bank.color,
            settings.fog_bank.start_m,
            settings.fog_bank.end_m,
        );
        return atmosphere_render.buildFrameLighting(settings.sky_tone, fog, camera);
    }
};

fn cameraCellId(camera: friendly_engine.core.math.Vec3f, manager: *const world_mod.stream.StreamManager) world_mod.cell.CellId {
    return world_mod.cell.idAtPosition(
        camera.x,
        camera.z,
        camera.y,
        manager.manifest.cell_size_m,
        world_mod.cell.default_cell_height_m,
        manager.stream_vertical_cells,
    );
}

test "sync uses camera cell atmosphere settings blob" {
    var state = ClientAtmosphereState{ .requires_settings = true };
    const default_payload =
        \\{"cell":[0,0,0],"sky_tone":{"sun_enabled":true,"sun_azimuth_deg":135,"sun_elevation_deg":48,"moon_enabled":false,"moon_azimuth_deg":315,"moon_elevation_deg":35},"fog_bank":{"enabled":false,"color":[136,148,168],"start_m":8,"end_m":80}}
        \\
    ;
    const override_payload =
        \\{"cell":[1,0,0],"sky_tone":{"sun_enabled":true,"sun_azimuth_deg":135,"sun_elevation_deg":48,"moon_enabled":false,"moon_azimuth_deg":315,"moon_elevation_deg":35},"fog_bank":{"enabled":true,"color":[68,85,102],"start_m":4,"end_m":40}}
        \\
    ;
    var manifest = world_mod.manifest.OwnedWorldManifest{
        .allocator = std.testing.allocator,
        .world_id = try std.testing.allocator.dupe(u8, "main"),
        .manifest_path = try std.testing.allocator.dupe(u8, "world.kdl"),
        .cell_size_m = 64,
        .cells = try std.testing.allocator.dupe(world_mod.manifest.ManifestCell, &.{
            .{ .id = .{ .x = 0, .y = 0, .z = 0 }, .authoring_path = try std.testing.allocator.dupe(u8, "scenes/main.kdl") },
            .{ .id = .{ .x = 1, .y = 0, .z = 0 }, .authoring_path = try std.testing.allocator.dupe(u8, "scenes/cell.kdl") },
        }),
        .lookup = std.AutoHashMap(world_mod.cell.CellId, usize).init(std.testing.allocator),
    };
    defer manifest.deinit();
    try manifest.lookup.put(.{ .x = 0, .y = 0, .z = 0 }, 0);
    try manifest.lookup.put(.{ .x = 1, .y = 0, .z = 0 }, 1);

    var manager = try world_mod.stream.StreamManager.init(
        std.testing.allocator,
        std.testing.io,
        ".",
        "client-debug",
        &manifest,
    );
    defer manager.deinit();
    try manager.active_cells.put(.{ .x = 0, .y = 0, .z = 0 }, .{
        .id = .{ .x = 0, .y = 0, .z = 0 },
        .blobs = &.{
            .{ .kind = atmosphere_runtime.settings_blob_kind, .payload = default_payload },
        },
    });
    try manager.active_cells.put(.{ .x = 1, .y = 0, .z = 0 }, .{
        .id = .{ .x = 1, .y = 0, .z = 0 },
        .blobs = &.{
            .{ .kind = atmosphere_runtime.settings_blob_kind, .payload = override_payload },
        },
    });

    try state.syncFromManager(&manager, .{ .x = 96, .y = 0, .z = 32 });
    try std.testing.expect(state.settings != null);
    try std.testing.expect(!state.settings.?.fog_bank.enabled);

    try state.syncFromManager(&manager, .{ .x = 96, .y = 0, .z = 96 });
    try std.testing.expect(state.settings.?.fog_bank.enabled);
    try std.testing.expectEqual(@as(u8, 68), state.settings.?.fog_bank.color[0]);
}

test "sync fails when atmosphere blob missing" {
    var state = ClientAtmosphereState{ .requires_settings = true };
    var manifest = world_mod.manifest.OwnedWorldManifest{
        .allocator = std.testing.allocator,
        .world_id = try std.testing.allocator.dupe(u8, "main"),
        .manifest_path = try std.testing.allocator.dupe(u8, "world.kdl"),
        .cell_size_m = 64,
        .cells = try std.testing.allocator.dupe(world_mod.manifest.ManifestCell, &.{
            .{ .id = .{ .x = 0, .y = 0, .z = 0 }, .authoring_path = try std.testing.allocator.dupe(u8, "scenes/main.kdl") },
        }),
        .lookup = std.AutoHashMap(world_mod.cell.CellId, usize).init(std.testing.allocator),
    };
    defer manifest.deinit();
    try manifest.lookup.put(.{ .x = 0, .y = 0, .z = 0 }, 0);

    var manager = try world_mod.stream.StreamManager.init(
        std.testing.allocator,
        std.testing.io,
        ".",
        "client-debug",
        &manifest,
    );
    defer manager.deinit();
    try manager.active_cells.put(.{ .x = 0, .y = 0, .z = 0 }, .{
        .id = .{ .x = 0, .y = 0, .z = 0 },
        .blobs = &.{},
    });

    try std.testing.expectError(error.MissingAtmosphereSettingsBlob, state.syncFromManager(&manager, .{ .x = 32, .y = 0, .z = 32 }));
}

test "sync fails when camera cell is not loaded" {
    var state = ClientAtmosphereState{ .requires_settings = true };
    var manifest = world_mod.manifest.OwnedWorldManifest{
        .allocator = std.testing.allocator,
        .world_id = try std.testing.allocator.dupe(u8, "main"),
        .manifest_path = try std.testing.allocator.dupe(u8, "world.kdl"),
        .cell_size_m = 64,
        .cells = try std.testing.allocator.dupe(world_mod.manifest.ManifestCell, &.{
            .{ .id = .{ .x = 0, .y = 0, .z = 0 }, .authoring_path = try std.testing.allocator.dupe(u8, "scenes/main.kdl") },
            .{ .id = .{ .x = 1, .y = 0, .z = 0 }, .authoring_path = try std.testing.allocator.dupe(u8, "scenes/cell.kdl") },
        }),
        .lookup = std.AutoHashMap(world_mod.cell.CellId, usize).init(std.testing.allocator),
    };
    defer manifest.deinit();
    try manifest.lookup.put(.{ .x = 0, .y = 0, .z = 0 }, 0);
    try manifest.lookup.put(.{ .x = 1, .y = 0, .z = 0 }, 1);

    var manager = try world_mod.stream.StreamManager.init(
        std.testing.allocator,
        std.testing.io,
        ".",
        "client-debug",
        &manifest,
    );
    defer manager.deinit();

    try std.testing.expectError(error.CameraAtmosphereCellNotLoaded, state.syncFromManager(&manager, .{ .x = 96, .y = 0, .z = 96 }));
}
