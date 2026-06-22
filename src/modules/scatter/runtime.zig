const std = @import("std");
const types = @import("types.zig");
const world = @import("../../world/mod.zig");

pub const RuntimeControls = types.RuntimeControls;

pub const ClusterMetadata = struct {
    cell: [3]i32,
    instance_count: usize,
    prototype_count: usize,
    biome_count: usize,
    controls: RuntimeControls,
};

pub fn buildClusterMetadata(
    allocator: std.mem.Allocator,
    id: world.cell.CellId,
    instances: []const types.ClusterInstance,
    rules: []const types.ScatterRule,
    controls: RuntimeControls,
) !ClusterMetadata {
    try types.validateRuntimeControls(controls);

    var prototypes = std.StringHashMap(void).init(allocator);
    defer prototypes.deinit();
    for (instances) |instance| {
        try prototypes.put(instance.prototype, {});
    }

    var biomes = std.StringHashMap(void).init(allocator);
    defer biomes.deinit();
    for (rules) |rule| {
        const rule_cell = try types.parseCellId(rule.cell);
        if (!rule_cell.eql(id)) continue;
        try biomes.put(rule.biome, {});
    }

    return .{
        .cell = .{ id.x, id.y, id.z },
        .instance_count = instances.len,
        .prototype_count = prototypes.count(),
        .biome_count = biomes.count(),
        .controls = controls,
    };
}

pub fn enforceClusterLimit(current_count: usize, controls: RuntimeControls) !bool {
    try types.validateRuntimeControls(controls);
    return current_count < controls.max_instances_per_cluster;
}

test "scatter runtime metadata counts prototypes and biomes" {
    const instances = [_]types.ClusterInstance{
        .{ .prototype = "scatter.grass", .position = .{ 0, 0, 0 }, .scale = 1 },
        .{ .prototype = "scatter.flower", .position = .{ 1, 0, 0 }, .scale = 1 },
        .{ .prototype = "scatter.grass", .position = .{ 2, 0, 0 }, .scale = 1 },
    };
    const rules = [_]types.ScatterRule{
        .{ .id = "grass", .cell = &.{ 0, 0, 0 }, .prototype = "scatter.grass", .density = 1, .biome = "meadow" },
        .{ .id = "flower", .cell = &.{ 0, 0, 0 }, .prototype = "scatter.flower", .density = 1, .biome = "field" },
    };
    const meta = try buildClusterMetadata(std.testing.allocator, .{ .x = 0, .y = 0, .z = 0 }, &instances, &rules, .{});
    try std.testing.expectEqual(@as(usize, 3), meta.instance_count);
    try std.testing.expectEqual(@as(usize, 2), meta.prototype_count);
    try std.testing.expectEqual(@as(usize, 2), meta.biome_count);
}

test "scatter runtime controls enforce cluster instance limits" {
    const controls = RuntimeControls{ .max_instances_per_cluster = 2 };
    try std.testing.expect(try enforceClusterLimit(0, controls));
    try std.testing.expect(try enforceClusterLimit(1, controls));
    try std.testing.expect(!(try enforceClusterLimit(2, controls)));
}
