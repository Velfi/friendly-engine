const std = @import("std");
const world = @import("../../world/mod.zig");
const kdl = @import("kdl");
const layer_kdl = @import("../layer_kdl.zig");
const types = @import("types.zig");

const AtmosphereDoc = types.AtmosphereDoc;
const atmosphere_layer_file = "layers/atmosphere.kdl";

pub fn loadProject(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    manifest_path: []const u8,
) !OwnedAtmosphereDoc {
    const path = try layerPath(allocator, manifest_path);
    defer allocator.free(path);
    var project_dir = try openProjectDir(io, project_path);
    defer project_dir.close(io);
    const bytes = project_dir.readFileAlloc(io, path, allocator, .limited(1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return emptyDoc(allocator),
        else => return err,
    };
    defer allocator.free(bytes);
    return parseAtmosphereKdl(allocator, bytes);
}

pub fn loadDoc(
    allocator: std.mem.Allocator,
    compile_ctx: *const world.compiler.layer.CompileContext,
) !OwnedAtmosphereDoc {
    var parsed = try loadProject(allocator, compile_ctx.io, compile_ctx.project_path, compile_ctx.manifest_path);
    errdefer parsed.deinit();
    try types.validateDoc(parsed.value);
    return parsed;
}

pub const OwnedAtmosphereDoc = struct {
    value: AtmosphereDoc,
    allocator: std.mem.Allocator,
    owned_cell_fog_banks: []types.CellFogBank = &.{},

    pub fn deinit(self: *OwnedAtmosphereDoc) void {
        if (self.owned_cell_fog_banks.len > 0) self.allocator.free(self.owned_cell_fog_banks);
    }
};

const CellFogBuilder = struct {
    cell: ?[3]i32 = null,
    fog: types.FogBank = .{},

    fn apply(self: *CellFogBuilder, key: []const u8, value: []const u8) !void {
        if (std.mem.eql(u8, key, "cell")) {
            self.cell = try types.parseCellCoord(value);
            return;
        }
        try applyFogProp(&self.fog, key, value);
    }

    fn finish(self: *CellFogBuilder, allocator: std.mem.Allocator, out: *std.ArrayList(types.CellFogBank)) !void {
        const cell = self.cell orelse return error.InvalidAtmosphereDocument;
        try out.append(allocator, .{ .cell = cell, .fog = self.fog });
        self.* = .{};
    }
};

fn emptyDoc(allocator: std.mem.Allocator) OwnedAtmosphereDoc {
    return .{ .value = types.defaultDoc(), .allocator = allocator };
}

fn parseAtmosphereKdl(allocator: std.mem.Allocator, bytes: []const u8) !OwnedAtmosphereDoc {
    const buffer = try allocator.allocSentinel(u8, bytes.len, 0);
    defer allocator.free(buffer);
    @memcpy(buffer, bytes);

    var parser = kdl.Parser.init(buffer);
    var doc = types.defaultDoc();
    var cell_fog_banks: std.ArrayList(types.CellFogBank) = .empty;
    errdefer cell_fog_banks.deinit(allocator);
    var cell_fog_builder: ?CellFogBuilder = null;
    var depth: i32 = 0;
    var root_seen = false;
    var section: ?enum { sky_tone, clouds, fog_bank } = null;

    while (true) {
        const event = try parser.next();
        switch (event) {
            .node => |node| {
                if (depth == 0) {
                    if (root_seen or !std.mem.eql(u8, node.val, "atmosphere")) return error.InvalidAtmosphereDocument;
                    root_seen = true;
                    continue;
                }
                if (depth == 1) {
                    if (cell_fog_builder != null) try cell_fog_builder.?.finish(allocator, &cell_fog_banks);
                    section = null;
                    if (std.mem.eql(u8, node.val, "sky_tone")) {
                        section = .sky_tone;
                        continue;
                    }
                    if (std.mem.eql(u8, node.val, "clouds")) {
                        section = .clouds;
                        continue;
                    }
                    if (std.mem.eql(u8, node.val, "fog_bank")) {
                        section = .fog_bank;
                        continue;
                    }
                    if (std.mem.eql(u8, node.val, "cell_fog_bank")) {
                        cell_fog_builder = .{};
                        continue;
                    }
                    return error.UnknownField;
                }
                return error.InvalidAtmosphereDocument;
            },
            .prop => |prop| {
                const value = try layer_kdl.decodeValue(allocator, prop.val);
                defer allocator.free(value);
                if (depth == 0) {
                    if (std.mem.eql(u8, prop.key, "version")) {
                        doc.schema_version = try std.fmt.parseInt(u32, value, 10);
                    } else return error.UnknownField;
                } else if (depth == 1) {
                    if (cell_fog_builder != null) {
                        try cell_fog_builder.?.apply(prop.key, value);
                        continue;
                    }
                    switch (section orelse return error.InvalidAtmosphereDocument) {
                        .sky_tone => try applySkyProp(&doc.sky_tone, prop.key, value),
                        .clouds => try applyCloudProp(&doc.clouds, prop.key, value),
                        .fog_bank => try applyFogProp(&doc.fog_bank, prop.key, value),
                    }
                } else return error.InvalidAtmosphereDocument;
            },
            .child_block_begin => depth += 1,
            .child_block_end => {
                if (depth == 1) section = null;
                depth -= 1;
                if (depth < 0) return error.InvalidAtmosphereDocument;
            },
            .arg, .invalid => return error.InvalidAtmosphereDocument,
            .eof => break,
        }
    }
    if (cell_fog_builder != null) try cell_fog_builder.?.finish(allocator, &cell_fog_banks);
    if (!root_seen or depth != 0) return error.InvalidAtmosphereDocument;

    const owned_cell_fog_banks = try cell_fog_banks.toOwnedSlice(allocator);
    doc.cell_fog_banks = owned_cell_fog_banks;
    try types.validateDoc(doc);
    return .{
        .value = doc,
        .allocator = allocator,
        .owned_cell_fog_banks = owned_cell_fog_banks,
    };
}

fn applySkyProp(sky: *types.SkyTone, key: []const u8, value: []const u8) !void {
    if (std.mem.eql(u8, key, "sun_enabled")) {
        sky.sun_enabled = std.mem.eql(u8, value, "true");
    } else if (std.mem.eql(u8, key, "sun_azimuth_deg")) {
        sky.sun_azimuth_deg = try std.fmt.parseFloat(f32, value);
    } else if (std.mem.eql(u8, key, "sun_elevation_deg")) {
        sky.sun_elevation_deg = try std.fmt.parseFloat(f32, value);
    } else if (std.mem.eql(u8, key, "moon_enabled")) {
        sky.moon_enabled = std.mem.eql(u8, value, "true");
    } else if (std.mem.eql(u8, key, "moon_azimuth_deg")) {
        sky.moon_azimuth_deg = try std.fmt.parseFloat(f32, value);
    } else if (std.mem.eql(u8, key, "moon_elevation_deg")) {
        sky.moon_elevation_deg = try std.fmt.parseFloat(f32, value);
    } else if (std.mem.eql(u8, key, "star_seed")) {
        sky.star_seed = try std.fmt.parseInt(u32, value, 10);
    } else return error.UnknownField;
}

fn applyCloudProp(clouds: *types.CloudTone, key: []const u8, value: []const u8) !void {
    if (std.mem.eql(u8, key, "enabled")) {
        clouds.enabled = std.mem.eql(u8, value, "true");
    } else if (std.mem.eql(u8, key, "coverage")) {
        clouds.coverage = try std.fmt.parseFloat(f32, value);
    } else if (std.mem.eql(u8, key, "softness")) {
        clouds.softness = try std.fmt.parseFloat(f32, value);
    } else if (std.mem.eql(u8, key, "scale")) {
        clouds.scale = try std.fmt.parseFloat(f32, value);
    } else if (std.mem.eql(u8, key, "height_bias")) {
        clouds.height_bias = try std.fmt.parseFloat(f32, value);
    } else if (std.mem.eql(u8, key, "drift_dir")) {
        clouds.* = try parseCloudDriftDir(clouds.*, value);
    } else if (std.mem.eql(u8, key, "drift_speed")) {
        clouds.drift_speed = try std.fmt.parseFloat(f32, value);
    } else if (std.mem.eql(u8, key, "seed")) {
        clouds.seed = try std.fmt.parseInt(u32, value, 10);
    } else if (std.mem.eql(u8, key, "parallax_enabled")) {
        clouds.parallax_enabled = std.mem.eql(u8, value, "true");
    } else return error.UnknownField;
}

fn parseCloudDriftDir(clouds: types.CloudTone, value: []const u8) !types.CloudTone {
    var out = clouds;
    const comma = std.mem.indexOfScalar(u8, value, ',') orelse return error.InvalidAtmosphereValue;
    const x_text = std.mem.trim(u8, value[0..comma], " \t");
    const y_text = std.mem.trim(u8, value[comma + 1 ..], " \t");
    if (x_text.len == 0 or y_text.len == 0) return error.InvalidAtmosphereValue;
    out.drift_dir_x = try std.fmt.parseFloat(f32, x_text);
    out.drift_dir_y = try std.fmt.parseFloat(f32, y_text);
    return out;
}

fn applyFogProp(fog: *types.FogBank, key: []const u8, value: []const u8) !void {
    if (std.mem.eql(u8, key, "enabled")) {
        fog.enabled = std.mem.eql(u8, value, "true");
    } else if (std.mem.eql(u8, key, "color")) {
        const rgb = try types.parseHexColor(value);
        fog.color_r = rgb[0];
        fog.color_g = rgb[1];
        fog.color_b = rgb[2];
    } else if (std.mem.eql(u8, key, "start_m")) {
        fog.start_m = try std.fmt.parseFloat(f32, value);
    } else if (std.mem.eql(u8, key, "end_m")) {
        fog.end_m = try std.fmt.parseFloat(f32, value);
    } else return error.UnknownField;
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

test "parse atmosphere kdl round trip fields" {
    const bytes =
        \\atmosphere version=1 {
        \\  sky_tone sun_enabled=true sun_azimuth_deg=120 sun_elevation_deg=40 moon_enabled=false moon_azimuth_deg=300 moon_elevation_deg=25 star_seed=42
        \\  clouds enabled=true coverage=0.5 softness=0.7 scale=0.9 height_bias=0.6 drift_dir="0.8,0.2" drift_speed=0.02 seed=99 parallax_enabled=true
        \\  fog_bank enabled=true color="#8894a8" start_m=8 end_m=80
        \\  cell_fog_bank cell="1,0,0" enabled=true color="#445566" start_m=4 end_m=40
        \\}
        \\
    ;
    var doc = try parseAtmosphereKdl(std.testing.allocator, bytes);
    defer doc.deinit();
    try std.testing.expect(doc.value.sky_tone.sun_enabled);
    try std.testing.expectEqual(@as(f32, 120), doc.value.sky_tone.sun_azimuth_deg);
    try std.testing.expectEqual(@as(u32, 42), doc.value.sky_tone.star_seed);
    try std.testing.expectEqual(@as(f32, 0.5), doc.value.clouds.coverage);
    try std.testing.expectEqual(@as(f32, 0.8), doc.value.clouds.drift_dir_x);
    try std.testing.expectEqual(@as(u32, 99), doc.value.clouds.seed);
    try std.testing.expect(doc.value.fog_bank.enabled);
    try std.testing.expectEqual(@as(u8, 0x88), doc.value.fog_bank.color_r);
    try std.testing.expectEqual(@as(usize, 1), doc.value.cell_fog_banks.len);
    try std.testing.expectEqual(@as(i32, 1), doc.value.cell_fog_banks[0].cell[0]);
    try std.testing.expectEqual(@as(u8, 0x44), doc.value.cell_fog_banks[0].fog.color_r);
}
