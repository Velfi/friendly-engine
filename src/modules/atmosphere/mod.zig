const std = @import("std");
const core = @import("../../core/mod.zig");
const framework = @import("../../framework/mod.zig");
const world = @import("../../world/mod.zig");
const types = @import("types.zig");
const storage = @import("storage.zig");

pub const module_name = "gem.atmosphere";
const layer_name = "world.layer.atmosphere";

pub const AtmosphereDoc = types.AtmosphereDoc;
pub const SkyTone = types.SkyTone;
pub const CloudTone = types.CloudTone;
pub const FogBank = types.FogBank;
pub const CellFogBank = types.CellFogBank;
pub const resolveFogForCell = types.resolveFogForCell;
pub const hasCellFogOverride = types.hasCellFogOverride;
pub const defaultDoc = types.defaultDoc;
pub const authoring = @import("authoring.zig");
pub const runtime = @import("runtime.zig");
pub const fog_math = @import("fog_math.zig");

pub fn register(registry: anytype) !void {
    try registry.registerWorldCompilerLayer(.{
        .name = layer_name,
        .affected_cells = affectedCells,
        .compile_cell = compileCell,
    });
}

pub fn start(engine_world: *framework.World) !void {
    try engine_world.notifications.publish("gem.atmosphere.started", "{}");
}

pub fn stop(engine_world: *framework.World) !void {
    try engine_world.notifications.publish("gem.atmosphere.stopped", "{}");
}

fn affectedCells(
    _: ?*anyopaque,
    compile_ctx: *const world.compiler.layer.CompileContext,
    allocator: std.mem.Allocator,
) ![]world.cell.CellId {
    const cells = compile_ctx.loaded_manifest.cells;
    var ids = try allocator.alloc(world.cell.CellId, cells.len);
    for (cells, 0..) |entry, index| ids[index] = entry.id;
    return ids;
}

pub fn compileCell(
    _: ?*anyopaque,
    compile_ctx: *const world.compiler.layer.CompileContext,
    id: world.cell.CellId,
    allocator: std.mem.Allocator,
) !world.compiler.layer.CellLayerOutput {
    var doc = try storage.loadDoc(allocator, compile_ctx);
    defer doc.deinit();

    var blobs = std.ArrayList(world.cell.CellBlob).empty;
    errdefer {
        for (blobs.items) |*blob| blob.deinit(allocator);
        blobs.deinit(allocator);
    }

    const bounds = world.cell.boundsForCell(id, compile_ctx.loaded_manifest.cell_size_m, world.cell.default_cell_height_m);
    const center = core.math.Vec3f{
        .x = (bounds.min.x + bounds.max.x) * 0.5,
        .y = (bounds.min.y + bounds.max.y) * 0.5,
        .z = (bounds.min.z + bounds.max.z) * 0.5,
    };

    const sun_intensity = sunIntensity(doc.value.sky_tone);
    const probes = try allocator.dupe(world.cell.LightProbeMeta, &.{.{
        .position = center,
        .intensity = sun_intensity,
    }});
    errdefer allocator.free(probes);

    const fog = types.resolveFogForCell(doc.value, id);
    try world.compiler.layer.appendBlobJson(allocator, &blobs, "atmosphere.settings", .{
        .cell = .{ id.x, id.y, id.z },
        .sky_tone = doc.value.sky_tone,
        .clouds = doc.value.clouds,
        .fog_bank = .{
            .enabled = fog.enabled,
            .color = .{ fog.color_r, fog.color_g, fog.color_b },
            .start_m = fog.start_m,
            .end_m = fog.end_m,
        },
    });

    return .{
        .light_probes = probes,
        .blobs = try blobs.toOwnedSlice(allocator),
    };
}

fn sunIntensity(sky: types.SkyTone) f32 {
    if (!sky.sun_enabled) return if (sky.moon_enabled) 0.35 else 0.15;
    const normalized = std.math.clamp((sky.sun_elevation_deg + 10.0) / 95.0, 0.0, 1.0);
    return 0.15 + normalized * 1.1;
}

test "compile cell uses per-cell fog override when present" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "layers");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "layers/atmosphere.kdl",
        .data =
        \\atmosphere version=1 {
        \\  sky_tone sun_enabled=true sun_azimuth_deg=135 sun_elevation_deg=48 moon_enabled=false moon_azimuth_deg=315 moon_elevation_deg=35 star_seed=2745
        \\  clouds enabled=true coverage=0.48 softness=0.68 scale=0.85 height_bias=0.55 drift_dir="1,0.18" drift_speed=0.015 seed=2745 parallax_enabled=true
        \\  fog_bank enabled=false color="#8894a8" start_m=8 end_m=80
        \\  cell_fog_bank cell="1,0,0" enabled=true color="#445566" start_m=4 end_m=40
        \\}
        \\
        ,
    });

    var manifest = world.manifest.OwnedWorldManifest{
        .allocator = std.testing.allocator,
        .world_id = try std.testing.allocator.dupe(u8, "main"),
        .manifest_path = try std.testing.allocator.dupe(u8, "world.kdl"),
        .cell_size_m = 64,
        .cells = try std.testing.allocator.dupe(world.manifest.ManifestCell, &.{
            .{ .id = .{ .x = 0, .y = 0, .z = 0 }, .authoring_path = try std.testing.allocator.dupe(u8, "scenes/main.kdl") },
            .{ .id = .{ .x = 1, .y = 0, .z = 0 }, .authoring_path = try std.testing.allocator.dupe(u8, "scenes/cell.kdl") },
        }),
        .lookup = std.AutoHashMap(world.cell.CellId, usize).init(std.testing.allocator),
    };
    defer manifest.deinit();
    try manifest.lookup.put(.{ .x = 0, .y = 0, .z = 0 }, 0);
    try manifest.lookup.put(.{ .x = 1, .y = 0, .z = 0 }, 1);

    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);
    const compile_ctx = world.compiler.layer.CompileContext{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = project_path,
        .target = "client-debug",
        .manifest_path = "world.kdl",
        .loaded_manifest = &manifest,
    };

    var default_out = try compileCell(null, &compile_ctx, .{ .x = 0, .y = 0, .z = 0 }, std.testing.allocator);
    defer default_out.deinit(std.testing.allocator);
    var override_out = try compileCell(null, &compile_ctx, .{ .x = 1, .y = 0, .z = 0 }, std.testing.allocator);
    defer override_out.deinit(std.testing.allocator);

    const default_settings = try runtime.requireSettingsBlob(default_out.blobs);
    const override_settings = try runtime.requireSettingsBlob(override_out.blobs);
    try std.testing.expect(!default_settings.fog_bank.enabled);
    try std.testing.expectEqual(@as(f32, 0.48), default_settings.clouds.coverage);
    try std.testing.expect(override_settings.fog_bank.enabled);
    try std.testing.expectEqual(@as(u8, 0x44), override_settings.fog_bank.color[0]);
    try std.testing.expectEqual(@as(f32, 40), override_settings.fog_bank.end_m);
}

test "atmosphere compiler marks every manifest cell affected" {
    var manifest = world.manifest.OwnedWorldManifest{
        .allocator = std.testing.allocator,
        .world_id = try std.testing.allocator.dupe(u8, "main"),
        .manifest_path = try std.testing.allocator.dupe(u8, "world.kdl"),
        .cell_size_m = 256,
        .cells = try std.testing.allocator.dupe(world.manifest.ManifestCell, &.{
            .{ .id = .{ .x = 0, .y = 0, .z = 0 }, .authoring_path = try std.testing.allocator.dupe(u8, "scenes/main.kdl") },
            .{ .id = .{ .x = 1, .y = 0, .z = 0 }, .authoring_path = try std.testing.allocator.dupe(u8, "scenes/cell.kdl") },
        }),
        .lookup = std.AutoHashMap(world.cell.CellId, usize).init(std.testing.allocator),
    };
    defer manifest.deinit();
    try manifest.lookup.put(.{ .x = 0, .y = 0, .z = 0 }, 0);
    try manifest.lookup.put(.{ .x = 1, .y = 0, .z = 0 }, 1);

    const compile_ctx = world.compiler.layer.CompileContext{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = ".",
        .target = "client-debug",
        .manifest_path = "world.kdl",
        .loaded_manifest = &manifest,
    };
    const ids = try affectedCells(null, &compile_ctx, std.testing.allocator);
    defer std.testing.allocator.free(ids);
    try std.testing.expectEqual(@as(usize, 2), ids.len);
}
