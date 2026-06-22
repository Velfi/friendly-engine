const std = @import("std");
const types = @import("types.zig");
const storage = @import("storage.zig");

const scatter_layer_file = "layers/scatter.kdl";

pub const RuleInput = struct {
    id: []const u8,
    cell: [3]i32,
    prototype: []const u8,
    density: f32,
    spacing: f32 = 4.0,
    slope_min: f32 = 0.0,
    slope_max: f32 = 90.0,
    biome: []const u8 = "default",
    seed: u32 = 1,
    scale_min: f32 = 0.8,
    scale_max: f32 = 1.2,
};

pub const ExclusionInput = struct {
    cell: [3]i32,
    min: [3]f32,
    max: [3]f32,
};

pub const BiomeRuleInput = struct {
    id: []const u8,
    density_multiplier: f32 = 1.0,
    spacing_multiplier: f32 = 1.0,
    scale_multiplier: f32 = 1.0,
};

pub const DocumentBuilder = struct {
    allocator: std.mem.Allocator,
    rules: std.ArrayList(types.ScatterRule),
    density_masks: std.ArrayList(types.DensityMask),
    exclusions: std.ArrayList(types.ExclusionZone),
    biome_rules: std.ArrayList(types.BiomeRule),
    runtime_controls: types.RuntimeControls = .{},

    pub fn init(allocator: std.mem.Allocator) DocumentBuilder {
        return .{
            .allocator = allocator,
            .rules = .empty,
            .density_masks = .empty,
            .exclusions = .empty,
            .biome_rules = .empty,
        };
    }

    pub fn deinit(self: *DocumentBuilder) void {
        for (self.rules.items) |rule| {
            self.allocator.free(rule.id);
            self.allocator.free(rule.cell);
            self.allocator.free(rule.prototype);
            self.allocator.free(rule.biome);
        }
        self.rules.deinit(self.allocator);
        for (self.density_masks.items) |mask| {
            self.allocator.free(mask.cell);
            self.allocator.free(mask.values);
        }
        self.density_masks.deinit(self.allocator);
        for (self.exclusions.items) |zone| {
            self.allocator.free(zone.cell);
            self.allocator.free(zone.min);
            self.allocator.free(zone.max);
        }
        self.exclusions.deinit(self.allocator);
        for (self.biome_rules.items) |rule| {
            self.allocator.free(rule.id);
        }
        self.biome_rules.deinit(self.allocator);
    }

    pub fn setRuntimeControls(self: *DocumentBuilder, controls: types.RuntimeControls) !void {
        try types.validateRuntimeControls(controls);
        self.runtime_controls = controls;
    }

    pub fn addRule(self: *DocumentBuilder, input: RuleInput) !void {
        const rule = types.ScatterRule{
            .id = try self.allocator.dupe(u8, input.id),
            .cell = try self.allocator.dupe(i32, &input.cell),
            .prototype = try self.allocator.dupe(u8, input.prototype),
            .density = input.density,
            .spacing = input.spacing,
            .slope_min = input.slope_min,
            .slope_max = input.slope_max,
            .biome = try self.allocator.dupe(u8, input.biome),
            .seed = input.seed,
            .scale_min = input.scale_min,
            .scale_max = input.scale_max,
        };
        errdefer {
            self.allocator.free(rule.id);
            self.allocator.free(rule.cell);
            self.allocator.free(rule.prototype);
            self.allocator.free(rule.biome);
        }
        try types.validateRule(rule);
        try self.rules.append(self.allocator, rule);
    }

    pub fn addDensityMaskWeights(self: *DocumentBuilder, cell: [3]i32, size: u32, weights: []const f32) !void {
        if (size < 1) return error.InvalidDensityMask;
        const sample_count = @as(usize, size) * @as(usize, size);
        if (weights.len != sample_count) return error.InvalidDensityMask;
        const values = try self.allocator.alloc(u8, sample_count);
        errdefer self.allocator.free(values);
        for (weights, 0..) |weight, index| {
            if (!std.math.isFinite(weight) or weight < 0 or weight > 1) return error.InvalidDensityMask;
            values[index] = @intFromFloat(@round(weight * 255.0));
        }
        try self.upsertDensityMaskBytes(cell, size, values);
        self.allocator.free(values);
    }

    pub fn upsertDensityMaskBytes(self: *DocumentBuilder, cell: [3]i32, size: u32, values: []const u8) !void {
        if (size < 1) return error.InvalidDensityMask;
        const sample_count = @as(usize, size) * @as(usize, size);
        if (values.len != sample_count) return error.InvalidDensityMask;

        var index: usize = 0;
        while (index < self.density_masks.items.len) {
            const mask = self.density_masks.items[index];
            if (mask.cell[0] == cell[0] and mask.cell[1] == cell[1] and mask.cell[2] == cell[2]) {
                self.allocator.free(mask.cell);
                self.allocator.free(mask.values);
                _ = self.density_masks.swapRemove(index);
                continue;
            }
            index += 1;
        }

        const mask = types.DensityMask{
            .cell = try self.allocator.dupe(i32, &cell),
            .size = size,
            .values = try self.allocator.dupe(u8, values),
        };
        errdefer {
            self.allocator.free(mask.cell);
            self.allocator.free(mask.values);
        }
        try types.validateMask(mask);
        try self.density_masks.append(self.allocator, mask);
    }

    pub fn addExclusionZone(self: *DocumentBuilder, input: ExclusionInput) !void {
        const zone = types.ExclusionZone{
            .cell = try self.allocator.dupe(i32, &input.cell),
            .min = try self.allocator.dupe(f32, &input.min),
            .max = try self.allocator.dupe(f32, &input.max),
        };
        errdefer {
            self.allocator.free(zone.cell);
            self.allocator.free(zone.min);
            self.allocator.free(zone.max);
        }
        try types.validateExclusion(zone);
        try self.exclusions.append(self.allocator, zone);
    }

    pub fn addBiomeRule(self: *DocumentBuilder, input: BiomeRuleInput) !void {
        const rule = types.BiomeRule{
            .id = try self.allocator.dupe(u8, input.id),
            .density_multiplier = input.density_multiplier,
            .spacing_multiplier = input.spacing_multiplier,
            .scale_multiplier = input.scale_multiplier,
        };
        errdefer self.allocator.free(rule.id);
        try types.validateBiomeRule(rule);
        try self.biome_rules.append(self.allocator, rule);
    }

    pub fn toDoc(self: *const DocumentBuilder) types.ScatterDoc {
        return .{
            .rules = self.rules.items,
            .density_masks = self.density_masks.items,
            .exclusions = self.exclusions.items,
            .biome_rules = self.biome_rules.items,
            .runtime_controls = self.runtime_controls,
        };
    }

    pub fn toKdlAlloc(self: *const DocumentBuilder) ![]u8 {
        var out: std.Io.Writer.Allocating = .init(self.allocator);
        defer out.deinit();
        const writer = &out.writer;
        const doc = self.toDoc();
        try writer.writeAll("scatter version=1 {\n");
        for (doc.biome_rules) |rule| {
            try writer.print("  biome id=\"{s}\" density_multiplier={d} spacing_multiplier={d} scale_multiplier={d}\n", .{ rule.id, rule.density_multiplier, rule.spacing_multiplier, rule.scale_multiplier });
        }
        for (doc.rules) |rule| {
            try writer.print("  rule id=\"{s}\" cell=\"{d},{d},{d}\" prototype=\"{s}\" density={d} spacing={d} slope_min={d} slope_max={d} biome=\"{s}\" seed={d} scale_min={d} scale_max={d}\n", .{
                rule.id,
                rule.cell[0],
                rule.cell[1],
                if (rule.cell.len == 3) rule.cell[2] else 0,
                rule.prototype,
                rule.density,
                rule.spacing,
                rule.slope_min,
                rule.slope_max,
                rule.biome,
                rule.seed,
                rule.scale_min,
                rule.scale_max,
            });
        }
        for (doc.density_masks) |mask| {
            try writer.print("  density_mask cell=\"{d},{d},{d}\" size={d} values=\"", .{ mask.cell[0], mask.cell[1], if (mask.cell.len == 3) mask.cell[2] else 0, mask.size });
            for (mask.values, 0..) |value, index| {
                if (index > 0) try writer.writeByte(',');
                try writer.print("{d}", .{value});
            }
            try writer.writeAll("\"\n");
        }
        for (doc.exclusions) |zone| {
            try writer.print("  exclusion cell=\"{d},{d},{d}\" min=\"{d},{d},{d}\" max=\"{d},{d},{d}\"\n", .{
                zone.cell[0],
                zone.cell[1],
                if (zone.cell.len == 3) zone.cell[2] else 0,
                zone.min[0],
                zone.min[1],
                zone.min[2],
                zone.max[0],
                zone.max[1],
                zone.max[2],
            });
        }
        try writer.print("  runtime_controls cull_distance_m={d} fade_distance_m={d} max_instances_per_cluster={d} cast_shadows={any} receive_shadows={any} lod_bias={d}\n", .{
            doc.runtime_controls.cull_distance_m,
            doc.runtime_controls.fade_distance_m,
            doc.runtime_controls.max_instances_per_cluster,
            doc.runtime_controls.cast_shadows,
            doc.runtime_controls.receive_shadows,
            doc.runtime_controls.lod_bias,
        });
        try writer.writeAll("}\n");
        return out.toOwnedSlice();
    }

    pub fn upsertRule(self: *DocumentBuilder, input: RuleInput) !void {
        for (self.rules.items, 0..) |rule, index| {
            if (!std.mem.eql(u8, rule.id, input.id)) continue;
            self.allocator.free(rule.id);
            self.allocator.free(rule.cell);
            self.allocator.free(rule.prototype);
            self.allocator.free(rule.biome);
            _ = self.rules.swapRemove(index);
            break;
        }
        try self.addRule(input);
    }

    pub fn ensureBiomeRule(self: *DocumentBuilder, input: BiomeRuleInput) !void {
        for (self.biome_rules.items) |rule| {
            if (std.mem.eql(u8, rule.id, input.id)) return;
        }
        try self.addBiomeRule(input);
    }
};

pub fn loadProject(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    manifest_path: []const u8,
) !DocumentBuilder {
    var owned = try storage.loadProject(allocator, io, project_path, manifest_path);
    defer owned.deinit();
    return try fromOwnedDoc(allocator, owned.value);
}

pub fn saveProject(
    doc: *const DocumentBuilder,
    io: std.Io,
    project_path: []const u8,
    manifest_path: []const u8,
) !void {
    const path = try layerPath(doc.allocator, manifest_path);
    defer doc.allocator.free(path);

    var project_dir = try openProjectDir(io, project_path);
    defer project_dir.close(io);
    if (std.fs.path.dirname(path)) |parent| try project_dir.createDirPath(io, parent);

    const bytes = try doc.toKdlAlloc();
    defer doc.allocator.free(bytes);
    try project_dir.writeFile(io, .{ .sub_path = path, .data = bytes });
}

pub fn upsertRuleFile(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    manifest_path: []const u8,
    input: RuleInput,
) !void {
    var doc = try loadProject(allocator, io, project_path, manifest_path);
    defer doc.deinit();
    try doc.ensureBiomeRule(.{ .id = input.biome, .density_multiplier = 1.15 });
    try doc.upsertRule(input);
    try saveProject(&doc, io, project_path, manifest_path);
}

pub fn appendExclusionFile(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    manifest_path: []const u8,
    input: ExclusionInput,
) !void {
    var doc = try loadProject(allocator, io, project_path, manifest_path);
    defer doc.deinit();
    try doc.addExclusionZone(input);
    try saveProject(&doc, io, project_path, manifest_path);
}

pub fn upsertDensityMaskFile(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    manifest_path: []const u8,
    cell: [3]i32,
    size: u32,
    values: []const u8,
) !void {
    var doc = try loadProject(allocator, io, project_path, manifest_path);
    defer doc.deinit();
    try doc.upsertDensityMaskBytes(cell, size, values);
    try saveProject(&doc, io, project_path, manifest_path);
}

fn fromOwnedDoc(allocator: std.mem.Allocator, doc: types.ScatterDoc) !DocumentBuilder {
    var builder = DocumentBuilder.init(allocator);
    errdefer builder.deinit();
    for (doc.biome_rules) |rule| {
        try builder.addBiomeRule(.{
            .id = rule.id,
            .density_multiplier = rule.density_multiplier,
            .spacing_multiplier = rule.spacing_multiplier,
            .scale_multiplier = rule.scale_multiplier,
        });
    }
    for (doc.rules) |rule| {
        try builder.addRule(.{
            .id = rule.id,
            .cell = .{ rule.cell[0], rule.cell[1], if (rule.cell.len == 3) rule.cell[2] else 0 },
            .prototype = rule.prototype,
            .density = rule.density,
            .spacing = rule.spacing,
            .slope_min = rule.slope_min,
            .slope_max = rule.slope_max,
            .biome = rule.biome,
            .seed = rule.seed,
            .scale_min = rule.scale_min,
            .scale_max = rule.scale_max,
        });
    }
    for (doc.density_masks) |mask| {
        var weights = try allocator.alloc(f32, mask.values.len);
        defer allocator.free(weights);
        for (mask.values, 0..) |value, index| weights[index] = @as(f32, @floatFromInt(value)) / 255.0;
        try builder.addDensityMaskWeights(
            .{ mask.cell[0], mask.cell[1], if (mask.cell.len == 3) mask.cell[2] else 0 },
            mask.size,
            weights,
        );
    }
    for (doc.exclusions) |zone| {
        try builder.addExclusionZone(.{
            .cell = .{ zone.cell[0], zone.cell[1], if (zone.cell.len == 3) zone.cell[2] else 0 },
            .min = .{ zone.min[0], zone.min[1], zone.min[2] },
            .max = .{ zone.max[0], zone.max[1], zone.max[2] },
        });
    }
    try builder.setRuntimeControls(doc.runtime_controls);
    return builder;
}

fn layerPath(allocator: std.mem.Allocator, manifest_path: []const u8) ![]u8 {
    const dir = std.fs.path.dirname(manifest_path) orelse "";
    if (dir.len == 0) return allocator.dupe(u8, scatter_layer_file);
    return std.fs.path.join(allocator, &.{ dir, scatter_layer_file });
}

fn openProjectDir(io: std.Io, project_path: []const u8) !std.Io.Dir {
    if (std.fs.path.isAbsolute(project_path)) return std.Io.Dir.openDirAbsolute(io, project_path, .{});
    return std.Io.Dir.cwd().openDir(io, project_path, .{});
}

test "scatter authoring builder creates masks exclusions biome data and controls" {
    var builder = DocumentBuilder.init(std.testing.allocator);
    defer builder.deinit();

    try builder.addBiomeRule(.{ .id = "meadow", .density_multiplier = 1.25 });
    try builder.addRule(.{
        .id = "grass_a",
        .cell = .{ 0, 0, 0 },
        .prototype = "scatter.grass",
        .density = 0.4,
        .biome = "meadow",
    });
    try builder.addDensityMaskWeights(.{ 0, 0, 0 }, 2, &.{ 1.0, 0.5, 0.25, 0.0 });
    try builder.addExclusionZone(.{
        .cell = .{ 0, 0, 0 },
        .min = .{ 1, 0, 1 },
        .max = .{ 2, 4, 2 },
    });
    try builder.setRuntimeControls(.{ .cull_distance_m = 96, .fade_distance_m = 12, .max_instances_per_cluster = 64 });

    const doc = builder.toDoc();
    try std.testing.expectEqual(@as(usize, 1), doc.rules.len);
    try std.testing.expectEqual(@as(u8, 128), doc.density_masks[0].values[1]);
    try std.testing.expectEqual(@as(u32, 64), doc.runtime_controls.max_instances_per_cluster);

    const kdl_bytes = try builder.toKdlAlloc();
    defer std.testing.allocator.free(kdl_bytes);
    try std.testing.expect(std.mem.indexOf(u8, kdl_bytes, "biome ") != null);
    try std.testing.expect(std.mem.indexOf(u8, kdl_bytes, "runtime_controls") != null);
}

test "scatter authoring rejects invalid density weights" {
    var builder = DocumentBuilder.init(std.testing.allocator);
    defer builder.deinit();
    try std.testing.expectError(error.InvalidDensityMask, builder.addDensityMaskWeights(.{ 0, 0, 0 }, 1, &.{1.25}));
}

test "scatter authoring upsert replaces rule by id" {
    var builder = DocumentBuilder.init(std.testing.allocator);
    defer builder.deinit();
    try builder.addBiomeRule(.{ .id = "meadow" });
    try builder.upsertRule(.{
        .id = "grass_a",
        .cell = .{ 0, 0, 0 },
        .prototype = "scatter.grass",
        .density = 0.4,
        .biome = "meadow",
    });
    try builder.upsertRule(.{
        .id = "grass_a",
        .cell = .{ 1, 0, 0 },
        .prototype = "scatter.grass",
        .density = 0.8,
        .biome = "meadow",
    });
    try std.testing.expectEqual(@as(usize, 1), builder.rules.items.len);
    try std.testing.expectEqual(@as(f32, 0.8), builder.rules.items[0].density);
}

test "scatter density mask kdl round trip preserves byte values" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);

    const sample_count = @as(usize, 4) * @as(usize, 4);
    const values = try std.testing.allocator.alloc(u8, sample_count);
    defer std.testing.allocator.free(values);
    for (values, 0..) |*value, index| value.* = @intCast((index * 17) % 256);

    try upsertDensityMaskFile(std.testing.allocator, std.testing.io, project_path, "world.kdl", .{ 2, 3, 0 }, 4, values);
    var doc = try loadProject(std.testing.allocator, std.testing.io, project_path, "world.kdl");
    defer doc.deinit();

    try std.testing.expectEqual(@as(usize, 1), doc.density_masks.items.len);
    const mask = doc.density_masks.items[0];
    try std.testing.expectEqual(@as(i32, 2), mask.cell[0]);
    try std.testing.expectEqual(@as(i32, 3), mask.cell[1]);
    try std.testing.expectEqual(@as(u32, 4), mask.size);
    try std.testing.expectEqualSlices(u8, values, mask.values);

    const kdl_bytes = try doc.toKdlAlloc();
    defer std.testing.allocator.free(kdl_bytes);
    var reloaded = try loadProject(std.testing.allocator, std.testing.io, project_path, "world.kdl");
    defer reloaded.deinit();
    try std.testing.expectEqualSlices(u8, mask.values, reloaded.density_masks.items[0].values);
}

test "scatter authoring round trip preserves existing rules on upsert file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);

    try upsertRuleFile(std.testing.allocator, std.testing.io, project_path, "world.kdl", .{
        .id = "grass_a",
        .cell = .{ 0, 0, 0 },
        .prototype = "scatter.grass",
        .density = 0.4,
        .biome = "meadow",
    });
    try upsertRuleFile(std.testing.allocator, std.testing.io, project_path, "world.kdl", .{
        .id = "pine_a",
        .cell = .{ 1, 0, 0 },
        .prototype = "scatter.pine",
        .density = 0.3,
        .biome = "meadow",
    });

    var doc = try loadProject(std.testing.allocator, std.testing.io, project_path, "world.kdl");
    defer doc.deinit();
    try std.testing.expectEqual(@as(usize, 2), doc.rules.items.len);
}
