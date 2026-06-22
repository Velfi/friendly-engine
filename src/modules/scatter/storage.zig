const std = @import("std");
const world = @import("../../world/mod.zig");
const types = @import("types.zig");
const kdl = @import("kdl");
const layer_kdl = @import("../layer_kdl.zig");
const scatter = @import("mod.zig");

const ScatterDoc = types.ScatterDoc;
const ScatterRule = types.ScatterRule;
const DensityMask = types.DensityMask;
const ExclusionZone = types.ExclusionZone;
const BiomeRule = types.BiomeRule;
const RuntimeControls = types.RuntimeControls;
const scatter_layer_file = "layers/scatter.kdl";

pub fn loadProject(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    manifest_path: []const u8,
) !OwnedScatterDoc {
    const path = try layerPath(allocator, manifest_path);
    defer allocator.free(path);
    var project_dir = try openProjectDir(io, project_path);
    defer project_dir.close(io);
    const bytes = project_dir.readFileAlloc(io, path, allocator, .limited(8 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return emptyScatterDoc(allocator),
        else => return err,
    };
    defer allocator.free(bytes);
    return parseScatterKdl(allocator, bytes);
}

pub fn loadDoc(
    allocator: std.mem.Allocator,
    compile_ctx: *const world.compiler.layer.CompileContext,
) !OwnedScatterDoc {
    var parsed = try loadProject(allocator, compile_ctx.io, compile_ctx.project_path, compile_ctx.manifest_path);
    errdefer parsed.deinit();
    if (parsed.value.schema_version != types.schema_version) return error.UnsupportedScatterSchemaVersion;
    for (parsed.value.rules) |rule| {
        try types.validateRule(rule);
        _ = try scatter.resolveBiomeRule(parsed.value.biome_rules, rule);
    }
    for (parsed.value.density_masks) |mask| {
        try types.validateMask(mask);
    }
    for (parsed.value.exclusions) |zone| {
        try types.validateExclusion(zone);
    }
    for (parsed.value.biome_rules) |rule| {
        try types.validateBiomeRule(rule);
    }
    try types.validateRuntimeControls(parsed.value.runtime_controls);
    return parsed;
}

const OwnedScatterDoc = struct {
    value: ScatterDoc,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *OwnedScatterDoc) void {
        for (self.value.rules) |rule| {
            self.allocator.free(rule.id);
            self.allocator.free(rule.cell);
            self.allocator.free(rule.prototype);
            self.allocator.free(rule.biome);
        }
        for (self.value.density_masks) |mask| {
            self.allocator.free(mask.cell);
            self.allocator.free(mask.values);
        }
        for (self.value.exclusions) |zone| {
            self.allocator.free(zone.cell);
            self.allocator.free(zone.min);
            self.allocator.free(zone.max);
        }
        for (self.value.biome_rules) |rule| {
            self.allocator.free(rule.id);
        }
        self.allocator.free(self.value.rules);
        self.allocator.free(self.value.density_masks);
        self.allocator.free(self.value.exclusions);
        self.allocator.free(self.value.biome_rules);
    }
};

fn parseScatterKdl(allocator: std.mem.Allocator, bytes: []const u8) !OwnedScatterDoc {
    const buffer = try allocator.allocSentinel(u8, bytes.len, 0);
    defer allocator.free(buffer);
    @memcpy(buffer, bytes);

    var parser = kdl.Parser.init(buffer);
    var rules = std.ArrayList(ScatterRule).empty;
    var masks = std.ArrayList(DensityMask).empty;
    var exclusions = std.ArrayList(ExclusionZone).empty;
    var biomes = std.ArrayList(BiomeRule).empty;
    var controls: RuntimeControls = .{};
    errdefer {
        freeScatterParts(allocator, rules.items, masks.items, exclusions.items, biomes.items);
        rules.deinit(allocator);
        masks.deinit(allocator);
        exclusions.deinit(allocator);
        biomes.deinit(allocator);
    }

    var schema_version: u32 = types.schema_version;
    var depth: i32 = 0;
    var root_seen = false;
    var current_node: ?[]const u8 = null;
    var rule_builder: ?RuleBuilder = null;
    var mask_builder: ?MaskBuilder = null;
    var exclusion_builder: ?ExclusionBuilder = null;
    var biome_builder: ?BiomeBuilder = null;
    errdefer {
        if (rule_builder) |*builder| builder.deinit(allocator);
        if (mask_builder) |*builder| builder.deinit(allocator);
        if (exclusion_builder) |*builder| builder.deinit(allocator);
        if (biome_builder) |*builder| builder.deinit(allocator);
    }

    while (true) {
        const event = try parser.next();
        switch (event) {
            .node => |node| {
                if (depth == 0) {
                    if (root_seen or !std.mem.eql(u8, node.val, "scatter")) return error.InvalidScatterDocument;
                    root_seen = true;
                    continue;
                }
                if (depth == 1) {
                    try finishScatterNode(allocator, current_node, &rules, &masks, &exclusions, &biomes, &rule_builder, &mask_builder, &exclusion_builder, &biome_builder);
                    current_node = node.val;
                    if (std.mem.eql(u8, node.val, "rule")) rule_builder = .{} else if (std.mem.eql(u8, node.val, "density_mask")) mask_builder = .{} else if (std.mem.eql(u8, node.val, "exclusion")) exclusion_builder = .{} else if (std.mem.eql(u8, node.val, "biome")) biome_builder = .{} else if (!std.mem.eql(u8, node.val, "runtime_controls")) return error.UnknownField;
                    continue;
                }
                return error.InvalidScatterDocument;
            },
            .prop => |prop| {
                const value = try layer_kdl.decodeValue(allocator, prop.val);
                defer allocator.free(value);
                if (depth == 0) {
                    if (std.mem.eql(u8, prop.key, "version")) schema_version = try std.fmt.parseInt(u32, value, 10) else return error.UnknownField;
                    continue;
                }
                if (depth == 1) {
                    const node_name = current_node orelse return error.InvalidScatterDocument;
                    if (std.mem.eql(u8, node_name, "rule")) try rule_builder.?.apply(allocator, prop.key, value) else if (std.mem.eql(u8, node_name, "density_mask")) try mask_builder.?.apply(allocator, prop.key, value) else if (std.mem.eql(u8, node_name, "exclusion")) try exclusion_builder.?.apply(allocator, prop.key, value) else if (std.mem.eql(u8, node_name, "biome")) try biome_builder.?.apply(allocator, prop.key, value) else if (std.mem.eql(u8, node_name, "runtime_controls")) try applyRuntimeControl(&controls, prop.key, value) else return error.UnknownField;
                    continue;
                }
                return error.InvalidScatterDocument;
            },
            .child_block_begin => depth += 1,
            .child_block_end => {
                if (depth == 1) {
                    try finishScatterNode(allocator, current_node, &rules, &masks, &exclusions, &biomes, &rule_builder, &mask_builder, &exclusion_builder, &biome_builder);
                    current_node = null;
                }
                depth -= 1;
                if (depth < 0) return error.InvalidScatterDocument;
            },
            .arg, .invalid => return error.InvalidScatterDocument,
            .eof => break,
        }
    }
    try finishScatterNode(allocator, current_node, &rules, &masks, &exclusions, &biomes, &rule_builder, &mask_builder, &exclusion_builder, &biome_builder);
    if (!root_seen or depth != 0) return error.InvalidScatterDocument;
    return .{
        .allocator = allocator,
        .value = .{
            .schema_version = schema_version,
            .rules = try rules.toOwnedSlice(allocator),
            .density_masks = try masks.toOwnedSlice(allocator),
            .exclusions = try exclusions.toOwnedSlice(allocator),
            .biome_rules = try biomes.toOwnedSlice(allocator),
            .runtime_controls = controls,
        },
    };
}

fn freeScatterParts(allocator: std.mem.Allocator, rules: []const ScatterRule, masks: []const DensityMask, exclusions: []const ExclusionZone, biomes: []const BiomeRule) void {
    for (rules) |rule| {
        allocator.free(rule.id);
        allocator.free(rule.cell);
        allocator.free(rule.prototype);
        allocator.free(rule.biome);
    }
    for (masks) |mask| {
        allocator.free(mask.cell);
        allocator.free(mask.values);
    }
    for (exclusions) |zone| {
        allocator.free(zone.cell);
        allocator.free(zone.min);
        allocator.free(zone.max);
    }
    for (biomes) |rule| allocator.free(rule.id);
}

fn finishScatterNode(
    allocator: std.mem.Allocator,
    current_node: ?[]const u8,
    rules: *std.ArrayList(ScatterRule),
    masks: *std.ArrayList(DensityMask),
    exclusions: *std.ArrayList(ExclusionZone),
    biomes: *std.ArrayList(BiomeRule),
    rule_builder: *?RuleBuilder,
    mask_builder: *?MaskBuilder,
    exclusion_builder: *?ExclusionBuilder,
    biome_builder: *?BiomeBuilder,
) !void {
    const node_name = current_node orelse return;
    if (std.mem.eql(u8, node_name, "rule")) {
        try rules.append(allocator, try rule_builder.*.?.finish(allocator));
        rule_builder.* = null;
    } else if (std.mem.eql(u8, node_name, "density_mask")) {
        try masks.append(allocator, try mask_builder.*.?.finish(allocator));
        mask_builder.* = null;
    } else if (std.mem.eql(u8, node_name, "exclusion")) {
        try exclusions.append(allocator, try exclusion_builder.*.?.finish(allocator));
        exclusion_builder.* = null;
    } else if (std.mem.eql(u8, node_name, "biome")) {
        try biomes.append(allocator, try biome_builder.*.?.finish(allocator));
        biome_builder.* = null;
    }
}

const RuleBuilder = struct {
    id: ?[]u8 = null,
    cell: ?[]i32 = null,
    prototype: ?[]u8 = null,
    density: ?f32 = null,
    spacing: f32 = 4.0,
    slope_min: f32 = 0.0,
    slope_max: f32 = 90.0,
    biome: ?[]u8 = null,
    seed: u32 = 1,
    scale_min: f32 = 0.8,
    scale_max: f32 = 1.2,

    fn deinit(self: *RuleBuilder, allocator: std.mem.Allocator) void {
        if (self.id) |value| allocator.free(value);
        if (self.cell) |value| allocator.free(value);
        if (self.prototype) |value| allocator.free(value);
        if (self.biome) |value| allocator.free(value);
    }

    fn apply(self: *RuleBuilder, allocator: std.mem.Allocator, key: []const u8, value: []const u8) !void {
        if (std.mem.eql(u8, key, "id")) self.id = try replaceString(allocator, self.id, value) else if (std.mem.eql(u8, key, "cell")) self.cell = try replaceCell(allocator, self.cell, value) else if (std.mem.eql(u8, key, "prototype")) self.prototype = try replaceString(allocator, self.prototype, value) else if (std.mem.eql(u8, key, "density")) self.density = try std.fmt.parseFloat(f32, value) else if (std.mem.eql(u8, key, "spacing")) self.spacing = try std.fmt.parseFloat(f32, value) else if (std.mem.eql(u8, key, "slope_min")) self.slope_min = try std.fmt.parseFloat(f32, value) else if (std.mem.eql(u8, key, "slope_max")) self.slope_max = try std.fmt.parseFloat(f32, value) else if (std.mem.eql(u8, key, "biome")) self.biome = try replaceString(allocator, self.biome, value) else if (std.mem.eql(u8, key, "seed")) self.seed = try std.fmt.parseInt(u32, value, 10) else if (std.mem.eql(u8, key, "scale_min")) self.scale_min = try std.fmt.parseFloat(f32, value) else if (std.mem.eql(u8, key, "scale_max")) self.scale_max = try std.fmt.parseFloat(f32, value) else return error.UnknownField;
    }

    fn finish(self: *RuleBuilder, allocator: std.mem.Allocator) !ScatterRule {
        const biome = self.biome orelse try allocator.dupe(u8, "default");
        self.biome = null;
        const result = ScatterRule{
            .id = self.id orelse return error.InvalidScatterRule,
            .cell = self.cell orelse return error.InvalidScatterRule,
            .prototype = self.prototype orelse return error.InvalidScatterRule,
            .density = self.density orelse return error.InvalidScatterRule,
            .spacing = self.spacing,
            .slope_min = self.slope_min,
            .slope_max = self.slope_max,
            .biome = biome,
            .seed = self.seed,
            .scale_min = self.scale_min,
            .scale_max = self.scale_max,
        };
        self.id = null;
        self.cell = null;
        self.prototype = null;
        return result;
    }
};

const MaskBuilder = struct {
    cell: ?[]i32 = null,
    size: ?u32 = null,
    values: ?[]u8 = null,

    fn deinit(self: *MaskBuilder, allocator: std.mem.Allocator) void {
        if (self.cell) |value| allocator.free(value);
        if (self.values) |value| allocator.free(value);
    }

    fn apply(self: *MaskBuilder, allocator: std.mem.Allocator, key: []const u8, value: []const u8) !void {
        if (std.mem.eql(u8, key, "cell")) self.cell = try replaceCell(allocator, self.cell, value) else if (std.mem.eql(u8, key, "size")) self.size = try std.fmt.parseInt(u32, value, 10) else if (std.mem.eql(u8, key, "values")) {
            if (self.values) |existing| allocator.free(existing);
            self.values = try layer_kdl.parseU8List(allocator, value);
        } else return error.UnknownField;
    }

    fn finish(self: *MaskBuilder, _: std.mem.Allocator) !DensityMask {
        const result = DensityMask{ .cell = self.cell orelse return error.InvalidDensityMask, .size = self.size orelse return error.InvalidDensityMask, .values = self.values orelse return error.InvalidDensityMask };
        self.cell = null;
        self.values = null;
        return result;
    }
};

const ExclusionBuilder = struct {
    cell: ?[]i32 = null,
    min: ?[]f32 = null,
    max: ?[]f32 = null,

    fn deinit(self: *ExclusionBuilder, allocator: std.mem.Allocator) void {
        if (self.cell) |value| allocator.free(value);
        if (self.min) |value| allocator.free(value);
        if (self.max) |value| allocator.free(value);
    }

    fn apply(self: *ExclusionBuilder, allocator: std.mem.Allocator, key: []const u8, value: []const u8) !void {
        if (std.mem.eql(u8, key, "cell")) self.cell = try replaceCell(allocator, self.cell, value) else if (std.mem.eql(u8, key, "min")) self.min = try replaceF32TripleSlice(allocator, self.min, value) else if (std.mem.eql(u8, key, "max")) self.max = try replaceF32TripleSlice(allocator, self.max, value) else return error.UnknownField;
    }

    fn finish(self: *ExclusionBuilder, _: std.mem.Allocator) !ExclusionZone {
        const result = ExclusionZone{ .cell = self.cell orelse return error.InvalidExclusionZone, .min = self.min orelse return error.InvalidExclusionZone, .max = self.max orelse return error.InvalidExclusionZone };
        self.cell = null;
        self.min = null;
        self.max = null;
        return result;
    }
};

const BiomeBuilder = struct {
    id: ?[]u8 = null,
    density_multiplier: f32 = 1.0,
    spacing_multiplier: f32 = 1.0,
    scale_multiplier: f32 = 1.0,

    fn deinit(self: *BiomeBuilder, allocator: std.mem.Allocator) void {
        if (self.id) |value| allocator.free(value);
    }

    fn apply(self: *BiomeBuilder, allocator: std.mem.Allocator, key: []const u8, value: []const u8) !void {
        if (std.mem.eql(u8, key, "id")) self.id = try replaceString(allocator, self.id, value) else if (std.mem.eql(u8, key, "density_multiplier")) self.density_multiplier = try std.fmt.parseFloat(f32, value) else if (std.mem.eql(u8, key, "spacing_multiplier")) self.spacing_multiplier = try std.fmt.parseFloat(f32, value) else if (std.mem.eql(u8, key, "scale_multiplier")) self.scale_multiplier = try std.fmt.parseFloat(f32, value) else return error.UnknownField;
    }

    fn finish(self: *BiomeBuilder, _: std.mem.Allocator) !BiomeRule {
        const result = BiomeRule{ .id = self.id orelse return error.InvalidScatterBiomeRule, .density_multiplier = self.density_multiplier, .spacing_multiplier = self.spacing_multiplier, .scale_multiplier = self.scale_multiplier };
        self.id = null;
        return result;
    }
};

fn applyRuntimeControl(controls: *RuntimeControls, key: []const u8, value: []const u8) !void {
    if (std.mem.eql(u8, key, "cull_distance_m")) controls.cull_distance_m = try std.fmt.parseFloat(f32, value) else if (std.mem.eql(u8, key, "fade_distance_m")) controls.fade_distance_m = try std.fmt.parseFloat(f32, value) else if (std.mem.eql(u8, key, "max_instances_per_cluster")) controls.max_instances_per_cluster = try std.fmt.parseInt(u32, value, 10) else if (std.mem.eql(u8, key, "cast_shadows")) controls.cast_shadows = try parseBool(value) else if (std.mem.eql(u8, key, "receive_shadows")) controls.receive_shadows = try parseBool(value) else if (std.mem.eql(u8, key, "lod_bias")) controls.lod_bias = try std.fmt.parseFloat(f32, value) else return error.UnknownField;
}

fn replaceString(allocator: std.mem.Allocator, existing: ?[]u8, value: []const u8) ![]u8 {
    if (existing) |old| allocator.free(old);
    return allocator.dupe(u8, value);
}

fn replaceCell(allocator: std.mem.Allocator, existing: ?[]i32, value: []const u8) ![]i32 {
    if (existing) |old| allocator.free(old);
    const parsed = try layer_kdl.parseI32Triple(value);
    return allocator.dupe(i32, &parsed);
}

fn replaceF32TripleSlice(allocator: std.mem.Allocator, existing: ?[]f32, value: []const u8) ![]f32 {
    if (existing) |old| allocator.free(old);
    const parsed = try layer_kdl.parseF32Triple(value);
    return allocator.dupe(f32, &parsed);
}

fn parseBool(value: []const u8) !bool {
    if (std.mem.eql(u8, value, "true")) return true;
    if (std.mem.eql(u8, value, "false")) return false;
    return error.InvalidLayerValue;
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

fn emptyScatterDoc(allocator: std.mem.Allocator) OwnedScatterDoc {
    return .{
        .allocator = allocator,
        .value = .{
            .schema_version = types.schema_version,
            .rules = &.{},
            .density_masks = &.{},
            .exclusions = &.{},
            .biome_rules = &.{},
            .runtime_controls = .{},
        },
    };
}
