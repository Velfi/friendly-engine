const std = @import("std");
const core = @import("../core/mod.zig");
const world_mod = @import("../world/mod.zig");

pub const Controls = struct {
    max_instances_per_cluster: u32,
    cull_distance_m: f32,
    fade_distance_m: f32,
    cast_shadows: bool = false,
    receive_shadows: bool = true,
    lod_bias: f32,

    pub fn cullDistances(self: Controls) ScatterCull {
        return .{
            .cull_distance_m = self.cull_distance_m,
            .fade_distance_m = self.fade_distance_m,
        };
    }
};

pub const ScatterCull = struct {
    cull_distance_m: f32,
    fade_distance_m: f32,
};

pub const ClusterMeta = struct {
    instance_count: usize,
    prototype_count: usize,
    biome_count: usize,
    controls: Controls,
};

pub const Instance = struct {
    prototype: []const u8,
    position: core.math.Vec3f,
    scale: f32,
};

pub const Decoded = struct {
    cluster_count: usize,
    meta: ?ClusterMeta,
    instances: []Instance,

    pub fn deinit(self: *Decoded, allocator: std.mem.Allocator) void {
        for (self.instances) |instance| allocator.free(instance.prototype);
        allocator.free(self.instances);
        self.instances = &.{};
        self.meta = null;
        self.cluster_count = 0;
    }
};

pub fn decode(allocator: std.mem.Allocator, blobs: []const world_mod.cell.CellBlob) !Decoded {
    const ScatterBlob = struct {
        cell: []const i32,
        instances: []const struct {
            prototype: []const u8,
            position: []const f32,
            scale: f32 = 1.0,
        } = &.{},
    };
    const ScatterMetaBlob = struct {
        cell: []const i32,
        instance_count: usize,
        prototype_count: usize,
        biome_count: usize,
        controls: struct {
            max_instances_per_cluster: u32,
            cull_distance_m: f32,
            fade_distance_m: f32,
            cast_shadows: bool = false,
            receive_shadows: bool = true,
            lod_bias: f32,
        },
    };

    var cluster_count: usize = 0;
    var meta: ?ClusterMeta = null;
    var declared_instance_limit: ?u32 = null;
    var declared_instance_count: ?usize = null;

    for (blobs) |blob| {
        if (!std.mem.eql(u8, blob.kind, "scatter.cluster_meta")) continue;
        var parsed = try std.json.parseFromSlice(ScatterMetaBlob, allocator, blob.payload, .{
            .allocate = .alloc_always,
        });
        defer parsed.deinit();
        try validateControls(parsed.value.controls);
        declared_instance_limit = parsed.value.controls.max_instances_per_cluster;
        declared_instance_count = parsed.value.instance_count;
        meta = .{
            .instance_count = parsed.value.instance_count,
            .prototype_count = parsed.value.prototype_count,
            .biome_count = parsed.value.biome_count,
            .controls = .{
                .max_instances_per_cluster = parsed.value.controls.max_instances_per_cluster,
                .cull_distance_m = parsed.value.controls.cull_distance_m,
                .fade_distance_m = parsed.value.controls.fade_distance_m,
                .cast_shadows = parsed.value.controls.cast_shadows,
                .receive_shadows = parsed.value.controls.receive_shadows,
                .lod_bias = parsed.value.controls.lod_bias,
            },
        };
        cluster_count += 1;
    }

    var instances = std.ArrayList(Instance).empty;
    errdefer {
        for (instances.items) |instance| allocator.free(instance.prototype);
        instances.deinit(allocator);
    }

    for (blobs) |blob| {
        if (!std.mem.eql(u8, blob.kind, "scatter.clusters")) continue;
        var parsed = try std.json.parseFromSlice(ScatterBlob, allocator, blob.payload, .{
            .allocate = .alloc_always,
        });
        defer parsed.deinit();
        if (declared_instance_count) |expected| {
            if (expected != parsed.value.instances.len) return error.InvalidScatterClusterMetadata;
        }
        if (declared_instance_limit) |limit| {
            if (parsed.value.instances.len > limit) return error.ScatterClusterInstanceLimitExceeded;
        }

        for (parsed.value.instances) |entry| {
            if (entry.position.len != 3) return error.InvalidScatterClusterInstance;
            if (!std.math.isFinite(entry.scale) or entry.scale <= 0) return error.InvalidScatterClusterInstance;
            const prototype = try allocator.dupe(u8, entry.prototype);
            errdefer allocator.free(prototype);
            try instances.append(allocator, .{
                .prototype = prototype,
                .position = .{
                    .x = entry.position[0],
                    .y = entry.position[1],
                    .z = entry.position[2],
                },
                .scale = entry.scale,
            });
        }
    }

    return .{
        .cluster_count = cluster_count,
        .meta = meta,
        .instances = try instances.toOwnedSlice(allocator),
    };
}

fn validateControls(controls: anytype) !void {
    if (controls.max_instances_per_cluster == 0) return error.InvalidScatterClusterMetadata;
    if (!std.math.isFinite(controls.cull_distance_m) or controls.cull_distance_m <= 0) {
        return error.InvalidScatterClusterMetadata;
    }
    if (!std.math.isFinite(controls.fade_distance_m) or controls.fade_distance_m < 0) {
        return error.InvalidScatterClusterMetadata;
    }
    if (controls.fade_distance_m >= controls.cull_distance_m) return error.InvalidScatterClusterMetadata;
    if (!std.math.isFinite(controls.lod_bias) or controls.lod_bias <= 0) return error.InvalidScatterClusterMetadata;
}

test "scatter clusters decode instances from baked blobs" {
    const blobs = [_]world_mod.cell.CellBlob{
        .{
            .kind = try std.testing.allocator.dupe(u8, "scatter.cluster_meta"),
            .payload = try std.testing.allocator.dupe(
                u8,
                \\{"cell":[0,0,0],"instance_count":2,"prototype_count":1,"biome_count":1,"controls":{"max_instances_per_cluster":32,"cull_distance_m":96,"fade_distance_m":12,"cast_shadows":false,"receive_shadows":true,"lod_bias":1}}
                ,
            ),
        },
        .{
            .kind = try std.testing.allocator.dupe(u8, "scatter.clusters"),
            .payload = try std.testing.allocator.dupe(
                u8,
                \\{"cell":[0,0,0],"instances":[{"prototype":"scatter.grass","position":[1,0,2],"scale":1.2},{"prototype":"scatter.grass","position":[3,0,4],"scale":0.9}]}
                ,
            ),
        },
    };
    defer for (blobs) |blob| {
        std.testing.allocator.free(blob.kind);
        std.testing.allocator.free(blob.payload);
    };

    var decoded = try decode(std.testing.allocator, &blobs);
    defer decoded.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), decoded.cluster_count);
    try std.testing.expect(decoded.meta != null);
    try std.testing.expectEqual(@as(usize, 2), decoded.instances.len);
    try std.testing.expectEqualStrings("scatter.grass", decoded.instances[0].prototype);
    try std.testing.expectEqual(@as(f32, 1.2), decoded.instances[0].scale);
    try std.testing.expectEqual(@as(f32, 3), decoded.instances[1].position.x);
}

test "scatter clusters decode rejects metadata instance count mismatch" {
    const blobs = [_]world_mod.cell.CellBlob{
        .{
            .kind = try std.testing.allocator.dupe(u8, "scatter.cluster_meta"),
            .payload = try std.testing.allocator.dupe(
                u8,
                \\{"cell":[0,0,0],"instance_count":2,"prototype_count":1,"biome_count":1,"controls":{"max_instances_per_cluster":32,"cull_distance_m":96,"fade_distance_m":12,"lod_bias":1}}
                ,
            ),
        },
        .{
            .kind = try std.testing.allocator.dupe(u8, "scatter.clusters"),
            .payload = try std.testing.allocator.dupe(
                u8,
                \\{"cell":[0,0,0],"instances":[{"prototype":"scatter.grass","position":[1,0,2],"scale":1}]}
                ,
            ),
        },
    };
    defer for (blobs) |blob| {
        std.testing.allocator.free(blob.kind);
        std.testing.allocator.free(blob.payload);
    };

    try std.testing.expectError(
        error.InvalidScatterClusterMetadata,
        decode(std.testing.allocator, &blobs),
    );
}

test "scatter clusters survive fcell encode and decode round trip" {
    const scatter = @import("../modules/scatter/mod.zig");
    const world = @import("../world/mod.zig");

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "layers");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "layers/scatter.kdl",
        .data =
        \\scatter version=1 {
        \\  biome id="meadow" density_multiplier=1 spacing_multiplier=1 scale_multiplier=1
        \\  rule id="grass_a" cell="0,0,0" prototype="scatter.grass" density=0.9 spacing=16 slope_min=0 slope_max=45 biome="meadow" seed=2
        \\  runtime_controls cull_distance_m=96 fade_distance_m=12 max_instances_per_cluster=64 cast_shadows=false receive_shadows=true lod_bias=1
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
        .lookup = std.AutoHashMap(world.cell.CellId, void).init(std.testing.allocator),
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

    var output = try scatter.compileCell(null, &ctx, .{ .x = 0, .y = 0, .z = 0 }, std.testing.allocator);
    defer output.deinit(std.testing.allocator);
    try std.testing.expect(output.blobs.len >= 2);

    const world_cell = world.cell.WorldCellData{
        .id = .{ .x = 0, .y = 0, .z = 0 },
        .cell_size_m = 64,
        .render_meshes = output.render_meshes,
        .blobs = output.blobs,
    };
    output.render_meshes = &.{};
    output.blobs = &.{};

    const encoded = try world.fcell.encodeCell(std.testing.allocator, world_cell);
    defer std.testing.allocator.free(encoded);
    var decoded_cell = try world.fcell.decodeCell(std.testing.allocator, encoded);
    defer decoded_cell.deinit(std.testing.allocator);
    world_cell.deinit(std.testing.allocator);

    var decoded_scatter = try decode(std.testing.allocator, decoded_cell.blobs);
    defer decoded_scatter.deinit(std.testing.allocator);

    try std.testing.expect(decoded_scatter.cluster_count >= 1);
    try std.testing.expect(decoded_scatter.instances.len > 0);
    try std.testing.expect(decoded_scatter.meta != null);
    try std.testing.expectEqual(decoded_scatter.meta.?.instance_count, decoded_scatter.instances.len);
}
