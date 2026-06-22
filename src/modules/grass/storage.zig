const std = @import("std");
const kdl = @import("kdl");
const layer_kdl = @import("../layer_kdl.zig");
const types = @import("types.zig");
const ocean_storage = @import("../ocean/storage.zig");

const grass_layer_file = "layers/grass.kdl";

pub const OwnedGrassDoc = struct {
    value: types.GrassDoc,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *OwnedGrassDoc) void {
        for (self.value.patches) |patch| {
            self.allocator.free(patch.id);
            self.allocator.free(patch.cell);
            freeStringList(self.allocator, patch.allowed_materials);
            freeStringList(self.allocator, patch.excluded_materials);
        }
        self.allocator.free(self.value.patches);
        self.value.patches = &.{};
    }
};

pub fn loadDoc(
    allocator: std.mem.Allocator,
    compile_ctx: *const @import("../../world/mod.zig").compiler.layer.CompileContext,
) !OwnedGrassDoc {
    var doc = try loadProject(allocator, compile_ctx.io, compile_ctx.project_path, compile_ctx.manifest_path);
    errdefer doc.deinit();
    if (doc.value.schema_version != types.schema_version) return error.UnsupportedGrassSchemaVersion;
    try types.validateWind(doc.value.global_wind);
    for (doc.value.patches) |patch| try types.validatePatch(patch);
    return doc;
}

pub fn loadProject(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    manifest_path: []const u8,
) !OwnedGrassDoc {
    const path = try layerPath(allocator, manifest_path);
    defer allocator.free(path);
    var project_dir = try openProjectDir(io, project_path);
    defer project_dir.close(io);
    const bytes = project_dir.readFileAlloc(io, path, allocator, .limited(2 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return emptyDoc(allocator),
        else => return err,
    };
    defer allocator.free(bytes);
    var doc = try parseGrassKdl(allocator, bytes);
    errdefer doc.deinit();
    if (!doc.value.global_wind.enabled) {
        var ocean = ocean_storage.loadProject(allocator, io, project_path, manifest_path) catch null;
        if (ocean) |*ocean_doc| {
            defer ocean_doc.deinit();
            if (ocean_doc.value.wind.enabled) {
                doc.value.global_wind = .{ .enabled = true, .direction_deg = ocean_doc.value.wind.direction_deg, .speed_mps = ocean_doc.value.wind.speed_mps };
            }
        }
    }
    return doc;
}

fn emptyDoc(allocator: std.mem.Allocator) !OwnedGrassDoc {
    return .{ .allocator = allocator, .value = .{ .patches = try allocator.alloc(types.GrassPatch, 0) } };
}

pub fn parseGrassKdl(allocator: std.mem.Allocator, bytes: []const u8) !OwnedGrassDoc {
    const buffer = try allocator.allocSentinel(u8, bytes.len, 0);
    defer allocator.free(buffer);
    @memcpy(buffer, bytes);

    var parser = kdl.Parser.init(buffer);
    var schema_version: u32 = types.schema_version;
    var wind: types.WindSettings = .{ .enabled = false };
    var patches = std.ArrayList(types.GrassPatch).empty;
    errdefer {
        for (patches.items) |patch| freePatch(allocator, patch);
        patches.deinit(allocator);
    }

    var depth: i32 = 0;
    var root_seen = false;
    var current: ?enum { wind, patch } = null;
    var patch_builder: ?PatchBuilder = null;
    errdefer if (patch_builder) |*builder| builder.deinit(allocator);

    while (true) {
        const event = try parser.next();
        switch (event) {
            .node => |node| {
                if (depth == 0) {
                    if (root_seen or !std.mem.eql(u8, node.val, "grass")) return error.InvalidGrassDocument;
                    root_seen = true;
                    continue;
                }
                if (depth == 1) {
                    try finishPatch(allocator, &patches, &patch_builder);
                    if (std.mem.eql(u8, node.val, "wind")) {
                        current = .wind;
                    } else if (std.mem.eql(u8, node.val, "patch")) {
                        current = .patch;
                        patch_builder = .{};
                    } else return error.UnknownField;
                    continue;
                }
                return error.InvalidGrassDocument;
            },
            .prop => |prop| {
                const value = try layer_kdl.decodeValue(allocator, prop.val);
                defer allocator.free(value);
                if (depth == 0) {
                    if (std.mem.eql(u8, prop.key, "version")) schema_version = try std.fmt.parseInt(u32, value, 10) else return error.UnknownField;
                    continue;
                }
                if (depth == 1) {
                    switch (current orelse return error.InvalidGrassDocument) {
                        .wind => try applyWind(&wind, prop.key, value),
                        .patch => try patch_builder.?.apply(allocator, prop.key, value),
                    }
                    continue;
                }
                return error.InvalidGrassDocument;
            },
            .child_block_begin => depth += 1,
            .child_block_end => {
                if (depth == 1) {
                    try finishPatch(allocator, &patches, &patch_builder);
                    current = null;
                }
                depth -= 1;
                if (depth < 0) return error.InvalidGrassDocument;
            },
            .arg, .invalid => return error.InvalidGrassDocument,
            .eof => break,
        }
    }
    try finishPatch(allocator, &patches, &patch_builder);
    if (!root_seen or depth != 0) return error.InvalidGrassDocument;
    return .{ .allocator = allocator, .value = .{ .schema_version = schema_version, .global_wind = wind, .patches = try patches.toOwnedSlice(allocator) } };
}

fn applyWind(wind: *types.WindSettings, key: []const u8, value: []const u8) !void {
    if (std.mem.eql(u8, key, "enabled")) wind.enabled = std.mem.eql(u8, value, "true") else if (std.mem.eql(u8, key, "direction_deg")) wind.direction_deg = try std.fmt.parseFloat(f32, value) else if (std.mem.eql(u8, key, "speed_mps")) wind.speed_mps = try std.fmt.parseFloat(f32, value) else return error.UnknownField;
}

const PatchBuilder = struct {
    id: ?[]u8 = null,
    cell: ?[]i32 = null,
    density: ?f32 = null,
    spacing: ?f32 = null,
    seed: u32 = 1,
    allowed_materials: ?[][]u8 = null,
    excluded_materials: ?[][]u8 = null,
    height_min: f32 = 0.42,
    height_max: f32 = 1.1,
    width_min: f32 = 0.035,
    width_max: f32 = 0.09,
    wind_strength: f32 = 0.55,
    bend_strength: f32 = 0.85,
    stiffness: f32 = 0.72,
    cull_distance_m: f32 = 96.0,
    fade_distance_m: f32 = 18.0,

    fn deinit(self: *PatchBuilder, allocator: std.mem.Allocator) void {
        if (self.id) |v| allocator.free(v);
        if (self.cell) |v| allocator.free(v);
        if (self.allowed_materials) |v| freeStringList(allocator, v);
        if (self.excluded_materials) |v| freeStringList(allocator, v);
    }

    fn apply(self: *PatchBuilder, allocator: std.mem.Allocator, key: []const u8, value: []const u8) !void {
        if (std.mem.eql(u8, key, "id")) self.id = try replaceString(allocator, self.id, value) else if (std.mem.eql(u8, key, "cell")) self.cell = try replaceCell(allocator, self.cell, value) else if (std.mem.eql(u8, key, "density")) self.density = try std.fmt.parseFloat(f32, value) else if (std.mem.eql(u8, key, "spacing")) self.spacing = try std.fmt.parseFloat(f32, value) else if (std.mem.eql(u8, key, "seed")) self.seed = try std.fmt.parseInt(u32, value, 10) else if (std.mem.eql(u8, key, "allowed_materials")) self.allowed_materials = try replaceStringList(allocator, self.allowed_materials, value) else if (std.mem.eql(u8, key, "excluded_materials")) self.excluded_materials = try replaceStringList(allocator, self.excluded_materials, value) else if (std.mem.eql(u8, key, "height_min")) self.height_min = try std.fmt.parseFloat(f32, value) else if (std.mem.eql(u8, key, "height_max")) self.height_max = try std.fmt.parseFloat(f32, value) else if (std.mem.eql(u8, key, "width_min")) self.width_min = try std.fmt.parseFloat(f32, value) else if (std.mem.eql(u8, key, "width_max")) self.width_max = try std.fmt.parseFloat(f32, value) else if (std.mem.eql(u8, key, "wind_strength")) self.wind_strength = try std.fmt.parseFloat(f32, value) else if (std.mem.eql(u8, key, "bend_strength")) self.bend_strength = try std.fmt.parseFloat(f32, value) else if (std.mem.eql(u8, key, "stiffness")) self.stiffness = try std.fmt.parseFloat(f32, value) else if (std.mem.eql(u8, key, "cull_distance_m")) self.cull_distance_m = try std.fmt.parseFloat(f32, value) else if (std.mem.eql(u8, key, "fade_distance_m")) self.fade_distance_m = try std.fmt.parseFloat(f32, value) else return error.UnknownField;
    }

    fn finish(self: *PatchBuilder, allocator: std.mem.Allocator) !types.GrassPatch {
        const allowed = if (self.allowed_materials) |v| v else try duplicateStringList(allocator, types.default_allowed_materials);
        self.allowed_materials = null;
        const excluded = if (self.excluded_materials) |v| v else try duplicateStringList(allocator, types.default_excluded_materials);
        self.excluded_materials = null;
        const result = types.GrassPatch{
            .id = self.id orelse return error.InvalidGrassPatch,
            .cell = self.cell orelse return error.InvalidGrassPatch,
            .density = self.density orelse return error.InvalidGrassPatch,
            .spacing = self.spacing orelse return error.InvalidGrassPatch,
            .seed = self.seed,
            .allowed_materials = allowed,
            .excluded_materials = excluded,
            .height_min = self.height_min,
            .height_max = self.height_max,
            .width_min = self.width_min,
            .width_max = self.width_max,
            .wind_strength = self.wind_strength,
            .bend_strength = self.bend_strength,
            .stiffness = self.stiffness,
            .cull_distance_m = self.cull_distance_m,
            .fade_distance_m = self.fade_distance_m,
        };
        self.id = null;
        self.cell = null;
        return result;
    }
};

fn finishPatch(allocator: std.mem.Allocator, patches: *std.ArrayList(types.GrassPatch), builder: *?PatchBuilder) !void {
    if (builder.*) |*value| {
        try patches.append(allocator, try value.finish(allocator));
        builder.* = null;
    }
}

fn replaceString(allocator: std.mem.Allocator, current: ?[]u8, value: []const u8) ![]u8 {
    if (current) |existing| allocator.free(existing);
    return allocator.dupe(u8, value);
}

fn replaceCell(allocator: std.mem.Allocator, current: ?[]i32, value: []const u8) ![]i32 {
    if (current) |existing| allocator.free(existing);
    const triple = try layer_kdl.parseI32Triple(value);
    const out = try allocator.alloc(i32, 3);
    out[0] = triple[0];
    out[1] = triple[1];
    out[2] = triple[2];
    return out;
}

fn replaceStringList(allocator: std.mem.Allocator, current: ?[][]u8, value: []const u8) ![][]u8 {
    if (current) |existing| freeStringList(allocator, existing);
    var list = std.ArrayList([]u8).empty;
    errdefer {
        for (list.items) |item| allocator.free(item);
        list.deinit(allocator);
    }
    var it = std.mem.splitScalar(u8, value, ',');
    while (it.next()) |raw| {
        const trimmed = std.mem.trim(u8, raw, " \t\r\n");
        if (trimmed.len == 0) continue;
        try list.append(allocator, try allocator.dupe(u8, trimmed));
    }
    if (list.items.len == 0) return error.InvalidGrassPatch;
    return list.toOwnedSlice(allocator);
}

fn duplicateStringList(allocator: std.mem.Allocator, values: []const []const u8) ![][]u8 {
    var list = try allocator.alloc([]u8, values.len);
    var initialized: usize = 0;
    errdefer {
        for (list[0..initialized]) |item| allocator.free(item);
        allocator.free(list);
    }
    for (values, 0..) |value, i| {
        list[i] = try allocator.dupe(u8, value);
        initialized += 1;
    }
    return list;
}

fn freeStringList(allocator: std.mem.Allocator, values: []const []const u8) void {
    for (values) |value| allocator.free(value);
    allocator.free(values);
}

fn freePatch(allocator: std.mem.Allocator, patch: types.GrassPatch) void {
    allocator.free(patch.id);
    allocator.free(patch.cell);
    freeStringList(allocator, patch.allowed_materials);
    freeStringList(allocator, patch.excluded_materials);
}

pub fn layerPath(allocator: std.mem.Allocator, manifest_path: []const u8) ![]u8 {
    const dir = std.fs.path.dirname(manifest_path) orelse "";
    if (dir.len == 0) return allocator.dupe(u8, grass_layer_file);
    return std.fs.path.join(allocator, &.{ dir, grass_layer_file });
}

fn openProjectDir(io: std.Io, project_path: []const u8) !std.Io.Dir {
    if (std.fs.path.isAbsolute(project_path)) return std.Io.Dir.openDirAbsolute(io, project_path, .{});
    return std.Io.Dir.cwd().openDir(io, project_path, .{});
}

test "parse grass kdl with wind and patch lists" {
    const bytes =
        \\grass version=1 {
        \\  wind enabled=true direction_deg=210 speed_mps=7
        \\  patch id="south" cell="0,0,0" density=0.75 spacing=2 seed=9 allowed_materials="grass,marsh" excluded_materials="road,stone" height_min=0.4 height_max=1.2 width_min=0.03 width_max=0.08 wind_strength=0.6 bend_strength=0.9 stiffness=0.7 cull_distance_m=80 fade_distance_m=12
        \\}
        \\
    ;
    var doc = try parseGrassKdl(std.testing.allocator, bytes);
    defer doc.deinit();
    try std.testing.expectEqual(@as(usize, 1), doc.value.patches.len);
    try std.testing.expectEqual(@as(f32, 210), doc.value.global_wind.direction_deg);
    try std.testing.expectEqualStrings("marsh", doc.value.patches[0].allowed_materials[1]);
}
