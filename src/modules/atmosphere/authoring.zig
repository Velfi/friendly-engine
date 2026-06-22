const std = @import("std");
const types = @import("types.zig");
const storage = @import("storage.zig");

const atmosphere_layer_file = "layers/atmosphere.kdl";

pub fn loadProject(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    manifest_path: []const u8,
) !types.AtmosphereDoc {
    var owned = try storage.loadProject(allocator, io, project_path, manifest_path);
    defer owned.deinit();
    return owned.value;
}

pub fn saveProject(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    manifest_path: []const u8,
    doc: types.AtmosphereDoc,
) !void {
    try types.validateDoc(doc);
    const path = try layerPath(allocator, manifest_path);
    defer allocator.free(path);

    var project_dir = try openProjectDir(io, project_path);
    defer project_dir.close(io);
    if (std.fs.path.dirname(path)) |parent| try project_dir.createDirPath(io, parent);

    const bytes = try formatKdl(allocator, doc);
    defer allocator.free(bytes);
    try project_dir.writeFile(io, .{ .sub_path = path, .data = bytes });
}

pub fn formatKdl(allocator: std.mem.Allocator, doc: types.AtmosphereDoc) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    const writer = &out.writer;
    const sky = doc.sky_tone;
    const clouds = doc.clouds;
    const fog = doc.fog_bank;
    try writer.print(
        "atmosphere version=1 {{\n  sky_tone sun_enabled={any} sun_azimuth_deg={d} sun_elevation_deg={d} moon_enabled={any} moon_azimuth_deg={d} moon_elevation_deg={d} star_seed={d}\n  clouds enabled={any} coverage={d} softness={d} scale={d} height_bias={d} drift_dir=\"{d},{d}\" drift_speed={d} seed={d} parallax_enabled={any}\n  fog_bank enabled={any} color=\"#{x:0>2}{x:0>2}{x:0>2}\" start_m={d} end_m={d}\n",
        .{
            sky.sun_enabled,
            sky.sun_azimuth_deg,
            sky.sun_elevation_deg,
            sky.moon_enabled,
            sky.moon_azimuth_deg,
            sky.moon_elevation_deg,
            sky.star_seed,
            clouds.enabled,
            clouds.coverage,
            clouds.softness,
            clouds.scale,
            clouds.height_bias,
            clouds.drift_dir_x,
            clouds.drift_dir_y,
            clouds.drift_speed,
            clouds.seed,
            clouds.parallax_enabled,
            fog.enabled,
            fog.color_r,
            fog.color_g,
            fog.color_b,
            fog.start_m,
            fog.end_m,
        },
    );
    for (doc.cell_fog_banks) |entry| {
        try writer.print(
            "  cell_fog_bank cell=\"{d},{d},{d}\" enabled={any} color=\"#{x:0>2}{x:0>2}{x:0>2}\" start_m={d} end_m={d}\n",
            .{
                entry.cell[0],
                entry.cell[1],
                entry.cell[2],
                entry.fog.enabled,
                entry.fog.color_r,
                entry.fog.color_g,
                entry.fog.color_b,
                entry.fog.start_m,
                entry.fog.end_m,
            },
        );
    }
    try writer.writeAll("}\n");
    return out.toOwnedSlice();
}

fn layerPath(allocator: std.mem.Allocator, manifest_path: []const u8) ![]u8 {
    const dir = std.fs.path.dirname(manifest_path) orelse "";
    if (dir.len == 0) return allocator.dupe(u8, atmosphere_layer_file);
    return std.fs.path.join(allocator, &.{ dir, atmosphere_layer_file });
}

fn openProjectDir(io: std.Io, project_path: []const u8) !std.Io.Dir {
    if (std.fs.path.isAbsolute(project_path)) return std.Io.Dir.openDirAbsolute(io, project_path, .{});
    return std.Io.Dir.cwd().openDir(io, project_path, .{});
}

test "format atmosphere kdl preserves fog color" {
    var doc = types.defaultDoc();
    doc.fog_bank.enabled = true;
    doc.sky_tone.star_seed = 99;
    const bytes = try formatKdl(std.testing.allocator, doc);
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "fog_bank enabled=true") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "clouds enabled=true") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "color=\"#8894a8\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "star_seed=99") != null);
}

test "format atmosphere kdl writes cloud controls" {
    var doc = types.defaultDoc();
    doc.clouds.coverage = 0.5;
    doc.clouds.drift_dir_x = 0.8;
    doc.clouds.drift_dir_y = 0.2;
    doc.clouds.seed = 99;
    const bytes = try formatKdl(std.testing.allocator, doc);
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "coverage=0.5") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "drift_dir=\"0.8,0.2\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "seed=99") != null);
}

test "format atmosphere kdl writes cell fog banks" {
    const doc = types.AtmosphereDoc{
        .cell_fog_banks = &.{
            .{ .cell = .{ 1, 0, 0 }, .fog = .{ .enabled = true, .color_r = 0x44, .color_g = 0x55, .color_b = 0x66, .start_m = 4, .end_m = 40 } },
        },
    };
    const bytes = try formatKdl(std.testing.allocator, doc);
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "cell_fog_bank cell=\"1,0,0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "color=\"#445566\"") != null);
}

test "save and load atmosphere project file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);

    var doc = types.defaultDoc();
    doc.sky_tone.sun_azimuth_deg = 200;
    doc.sky_tone.star_seed = 12345;
    doc.clouds.coverage = 0.57;
    doc.fog_bank.enabled = true;
    doc = types.AtmosphereDoc{
        .schema_version = doc.schema_version,
        .sky_tone = doc.sky_tone,
        .clouds = doc.clouds,
        .fog_bank = doc.fog_bank,
        .cell_fog_banks = &.{
            .{ .cell = .{ 0, 0, 0 }, .fog = .{ .enabled = true, .start_m = 12, .end_m = 96 } },
        },
    };
    try saveProject(std.testing.allocator, std.testing.io, project_path, "world.kdl", doc);

    const loaded = try loadProject(std.testing.allocator, std.testing.io, project_path, "world.kdl");
    try std.testing.expectEqual(@as(f32, 200), loaded.sky_tone.sun_azimuth_deg);
    try std.testing.expectEqual(@as(u32, 12345), loaded.sky_tone.star_seed);
    try std.testing.expectEqual(@as(f32, 0.57), loaded.clouds.coverage);
    try std.testing.expect(loaded.fog_bank.enabled);
    try std.testing.expectEqual(@as(usize, 1), loaded.cell_fog_banks.len);
    try std.testing.expectEqual(@as(f32, 12), loaded.cell_fog_banks[0].fog.start_m);
}
