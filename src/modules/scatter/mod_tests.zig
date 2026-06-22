const std = @import("std");
const world = @import("../../world/mod.zig");
const types = @import("types.zig");
const root = @import("mod.zig");
const compileCell = root.compileCell;
const validateRule = root.validateRule;
const ScatterRule = root.ScatterRule;
const DensityMask = root.DensityMask;
const ExclusionZone = root.ExclusionZone;
const BiomeRule = root.BiomeRule;
const parseCellId = root.parseCellId;
const resolveBiomeRule = root.resolveBiomeRule;

test "scatter layer applies mask override and emits clusters" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "layers");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "layers/scatter.kdl",
        .data =
        \\scatter version=1 {
        \\  biome id="meadow" density_multiplier=1 spacing_multiplier=1 scale_multiplier=1
        \\  rule id="grass_a" cell="0,0,0" prototype="scatter.grass" density=0.9 spacing=16 slope_min=0 slope_max=45 biome="meadow" seed=2
        \\  density_mask cell="0,0,0" size=2 values="255,0,255,0"
        \\  exclusion cell="0,0,0" min="0,0,0" max="10,2,10"
        \\  runtime_controls cull_distance_m=96 fade_distance_m=12 max_instances_per_cluster=32 cast_shadows=false receive_shadows=true lod_bias=1
        \\}
        \\
        ,
    });

    var manifest_value = world.manifest.OwnedWorldManifest{
        .allocator = std.testing.allocator,
        .world_id = try std.testing.allocator.dupe(u8, "main"),
        .manifest_path = try std.testing.allocator.dupe(u8, "world.kdl"),
        .cell_size_m = 64,
        .cells = try std.testing.allocator.alloc(world.manifest.ManifestCell, 0),
        .lookup = std.AutoHashMap(world.cell.CellId, usize).init(std.testing.allocator),
    };
    defer manifest_value.deinit();
    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);
    const ctx = world.compiler.layer.CompileContext{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = project_path,
        .target = "client-debug",
        .manifest_path = "world.kdl",
        .loaded_manifest = &manifest_value,
    };

    var output = try compileCell(null, &ctx, .{ .x = 0, .y = 0, .z = 0 }, std.testing.allocator);
    defer output.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), output.render_meshes.len);
    try std.testing.expectEqual(@as(usize, 3), output.blobs.len);
}

test "scatter validation rejects invalid masks and exclusion bounds" {
    try std.testing.expectError(error.InvalidDensityMask, types.validateMask(.{
        .cell = &.{ 0, 0, 0 },
        .size = 2,
        .values = &.{ 255, 0, 255 },
    }));
    try std.testing.expectError(error.InvalidExclusionZone, types.validateExclusion(.{
        .cell = &.{ 0, 0, 0 },
        .min = &.{ 4, 0, 0 },
        .max = &.{ 1, 2, 1 },
    }));
}

test "scatter validation requires explicit non-default biome rule data" {
    try std.testing.expectError(error.MissingScatterBiomeRule, resolveBiomeRule(&.{}, .{
        .id = "grass_a",
        .cell = &.{ 0, 0, 0 },
        .prototype = "scatter.grass",
        .density = 0.5,
        .biome = "meadow",
    }));
    try std.testing.expect((try resolveBiomeRule(&.{.{ .id = "meadow" }}, .{
        .id = "grass_a",
        .cell = &.{ 0, 0, 0 },
        .prototype = "scatter.grass",
        .density = 0.5,
        .biome = "meadow",
    })) != null);
}

test "scatter affected cells dedupe repeated rule cells" {
    var lookup = std.AutoHashMap(world.cell.CellId, void).init(std.testing.allocator);
    defer lookup.deinit();
    var affected = std.ArrayList(world.cell.CellId).empty;
    defer affected.deinit(std.testing.allocator);

    const cells = [_][]const i32{ &.{ 0, 0, 0 }, &.{ 0, 0, 0 } };
    for (cells) |raw_cell| {
        const id = try types.parseCellId(raw_cell);
        if (lookup.contains(id)) continue;
        try lookup.put(id, {});
        try affected.append(std.testing.allocator, id);
    }
    try std.testing.expectEqual(@as(usize, 1), affected.items.len);
}
