const std = @import("std");
const framework = @import("../../framework/mod.zig");
const world = @import("../../world/mod.zig");
const kdl = @import("kdl");
const layer_kdl = @import("../layer_kdl.zig");

const document = @import("document.zig");
pub const solid = @import("solid.zig");
pub const module_name = "gem.local_csg";
const layer_name = "world.layer.local_csg";
const local_csg_layer_file = "layers/local_csg.kdl";
const tex_size: usize = 128 * 128 * 4;

pub const Aabb = solid.Aabb;
pub const Brush = solid.Brush;
pub const ConvexPrism = solid.ConvexPrism;
pub const Point2 = solid.Point2;
pub const Solid = solid.Solid;
pub const boxBrush = solid.boxBrush;
pub const convexPrismBrush = solid.convexPrismBrush;
pub const deinitBrush = solid.deinitBrush;

pub const OperationKind = enum {
    add_block,
    add_wedge,
    add_prism,
    subtract_block,
    subtract_wedge,
    subtract_prism,
    doorway_subtract,

    pub fn jsonName(self: OperationKind) []const u8 {
        return switch (self) {
            .add_block => "add_block",
            .add_wedge => "add_wedge",
            .add_prism => "add_prism",
            .subtract_block => "subtract_block",
            .subtract_wedge => "subtract_wedge",
            .subtract_prism => "subtract_prism",
            .doorway_subtract => "doorway_subtract",
        };
    }

    pub fn parse(value: []const u8) !OperationKind {
        const trimmed = std.mem.trim(u8, value, " \t\r\n");
        if (std.mem.eql(u8, trimmed, "add_block")) return .add_block;
        if (std.mem.eql(u8, trimmed, "add_wedge")) return .add_wedge;
        if (std.mem.eql(u8, trimmed, "add_prism")) return .add_prism;
        if (std.mem.eql(u8, trimmed, "subtract_block")) return .subtract_block;
        if (std.mem.eql(u8, trimmed, "subtract_wedge")) return .subtract_wedge;
        if (std.mem.eql(u8, trimmed, "subtract_prism")) return .subtract_prism;
        if (std.mem.eql(u8, trimmed, "doorway_subtract")) return .doorway_subtract;
        return error.InvalidCsgOperation;
    }
};

pub const LayerOperation = struct {
    cell: world.cell.CellId,
    kind: OperationKind,
    bounds: Aabb,
    wall: ?Aabb = null,
    footprint: []Point2 = &.{},

    pub fn deinit(self: *LayerOperation, allocator: std.mem.Allocator) void {
        allocator.free(self.footprint);
        self.footprint = &.{};
    }
};

pub const LayerDocument = struct {
    operations: []LayerOperation,

    pub fn deinit(self: *LayerDocument, allocator: std.mem.Allocator) void {
        for (self.operations) |*operation| operation.deinit(allocator);
        allocator.free(self.operations);
        self.* = .{ .operations = &.{} };
    }
};

pub const DoorwaySplit = struct {
    segments: [3]?Aabb,
    opening: Aabb,
};

const LocalCsgDoc = struct {
    schema_version: u32 = 1,
    operations: []const CsgOperation = &.{},
};

const CsgOperation = struct {
    cell: []const i32,
    op: []const u8,
    min: []const f32,
    max: []const f32,
    wall_min: ?[]const f32 = null,
    wall_max: ?[]const f32 = null,
};

pub const FormattedCsgDoc = struct {
    schema_version: u32 = 1,
    operations: []const FormattedCsgOperation,
};

pub const FormattedCsgOperation = struct {
    cell: [3]i32,
    op: []const u8,
    min: [3]f32,
    max: [3]f32,
    wall_min: ?[3]f32 = null,
    wall_max: ?[3]f32 = null,
    footprint: ?[]const Point2 = null,
};

pub fn register(registry: anytype) !void {
    try registry.registerWorldCompilerLayer(.{
        .name = layer_name,
        .affected_cells = affectedCells,
        .compile_cell = compileCell,
    });
}

pub fn start(engine_world: *framework.World) !void {
    try engine_world.notifications.publish("gem.local_csg.started", "{}");
}

pub fn stop(engine_world: *framework.World) !void {
    try engine_world.notifications.publish("gem.local_csg.stopped", "{}");
}

pub fn splitAabbForDoorway(wall: Aabb, opening: Aabb) DoorwaySplit {
    var segments: [3]?Aabb = .{ null, null, null };
    const wall_x = wall.max[0] - wall.min[0];
    const wall_z = wall.max[2] - wall.min[2];
    const split_axis: usize = if (wall_z > wall_x) 2 else 0;

    if (opening.min[split_axis] > wall.min[split_axis]) {
        var max = wall.max;
        max[split_axis] = opening.min[split_axis];
        segments[0] = .{
            .min = wall.min,
            .max = max,
        };
    }
    if (opening.max[split_axis] < wall.max[split_axis]) {
        var min = wall.min;
        min[split_axis] = opening.max[split_axis];
        segments[1] = .{
            .min = min,
            .max = wall.max,
        };
    }
    if (opening.max[1] < wall.max[1]) {
        var min = wall.min;
        var max = wall.max;
        min[split_axis] = opening.min[split_axis];
        min[1] = opening.max[1];
        max[split_axis] = opening.max[split_axis];
        segments[2] = .{
            .min = min,
            .max = max,
        };
    }
    return .{
        .segments = segments,
        .opening = opening,
    };
}

pub fn makeAddBlockOperation(cell_id: world.cell.CellId, bounds: Aabb) !LayerOperation {
    const operation: LayerOperation = .{
        .cell = cell_id,
        .kind = .add_block,
        .bounds = bounds,
    };
    try validateLayerOperation(operation);
    return operation;
}

pub fn makeAddWedgeOperation(cell_id: world.cell.CellId, bounds: Aabb) !LayerOperation {
    const operation: LayerOperation = .{
        .cell = cell_id,
        .kind = .add_wedge,
        .bounds = bounds,
    };
    try validateLayerOperation(operation);
    return operation;
}

pub fn makeAddPrismOperation(allocator: std.mem.Allocator, cell_id: world.cell.CellId, footprint: []const Point2, min_y: f32, max_y: f32) !LayerOperation {
    try solid.validateConvexPrism(footprint, min_y, max_y);
    const bounds = prismBoundsFromFootprint(footprint, min_y, max_y);
    const operation: LayerOperation = .{
        .cell = cell_id,
        .kind = .add_prism,
        .bounds = bounds,
        .footprint = try allocator.dupe(Point2, footprint),
    };
    errdefer allocator.free(operation.footprint);
    try validateLayerOperation(operation);
    return operation;
}

pub fn makeDoorwaySubtractOperation(cell_id: world.cell.CellId, opening: Aabb, wall: Aabb) !LayerOperation {
    const operation: LayerOperation = .{
        .cell = cell_id,
        .kind = .doorway_subtract,
        .bounds = opening,
        .wall = wall,
    };
    try validateLayerOperation(operation);
    return operation;
}

pub fn makeSubtractBlockOperation(cell_id: world.cell.CellId, cut: Aabb, source: Aabb) !LayerOperation {
    const operation: LayerOperation = .{
        .cell = cell_id,
        .kind = .subtract_block,
        .bounds = cut,
        .wall = source,
    };
    try validateLayerOperation(operation);
    return operation;
}

pub fn makeSubtractWedgeOperation(cell_id: world.cell.CellId, cut: Aabb, source: Aabb) !LayerOperation {
    const operation: LayerOperation = .{
        .cell = cell_id,
        .kind = .subtract_wedge,
        .bounds = cut,
        .wall = source,
    };
    try validateLayerOperation(operation);
    return operation;
}

pub fn makeSubtractPrismOperation(allocator: std.mem.Allocator, cell_id: world.cell.CellId, footprint: []const Point2, min_y: f32, max_y: f32, source: Aabb) !LayerOperation {
    try solid.validateConvexPrism(footprint, min_y, max_y);
    const bounds = prismBoundsFromFootprint(footprint, min_y, max_y);
    const operation: LayerOperation = .{
        .cell = cell_id,
        .kind = .subtract_prism,
        .bounds = bounds,
        .wall = source,
        .footprint = try allocator.dupe(Point2, footprint),
    };
    errdefer allocator.free(operation.footprint);
    try validateLayerOperation(operation);
    return operation;
}

pub const parseLayerDocument = document.parseLayerDocument;
pub const formatLayerDocument = document.formatLayerDocument;
pub const appendOperationToBytes = document.appendOperationToBytes;
pub const readLayerDocument = document.readLayerDocument;
pub const writeLayerDocument = document.writeLayerDocument;
pub const appendLayerOperation = document.appendLayerOperation;

fn affectedCells(
    _: ?*anyopaque,
    compile_ctx: *const world.compiler.layer.CompileContext,
    allocator: std.mem.Allocator,
) ![]world.cell.CellId {
    var doc = try loadLayerDocumentForCompile(allocator, compile_ctx);
    defer doc.deinit(allocator);
    var cells = std.ArrayList(world.cell.CellId).empty;
    defer cells.deinit(allocator);
    var lookup = std.AutoHashMap(world.cell.CellId, void).init(allocator);
    defer lookup.deinit();
    for (doc.operations) |operation| {
        const id = operation.cell;
        if (lookup.contains(id)) continue;
        try lookup.put(id, {});
        try cells.append(allocator, id);
    }
    return cells.toOwnedSlice(allocator);
}

pub fn compileCell(
    _: ?*anyopaque,
    compile_ctx: *const world.compiler.layer.CompileContext,
    id: world.cell.CellId,
    allocator: std.mem.Allocator,
) !world.compiler.layer.CellLayerOutput {
    var doc = try loadLayerDocumentForCompile(allocator, compile_ctx);
    defer doc.deinit(allocator);

    var meshes = std.ArrayList(world.cell.RenderMesh).empty;
    var collisions = std.ArrayList(world.cell.CollisionPlaceholder).empty;
    var collision_shapes = std.ArrayList(world.cell.CollisionShape).empty;
    var visibility = std.ArrayList(world.cell.VisibilityLink).empty;
    var blobs = std.ArrayList(world.cell.CellBlob).empty;
    var add_solid = Solid{};
    defer add_solid.deinit(allocator);
    var has_add_solid = false;
    errdefer {
        for (meshes.items) |*mesh| mesh.deinit(allocator);
        meshes.deinit(allocator);
        collisions.deinit(allocator);
        collision_shapes.deinit(allocator);
        visibility.deinit(allocator);
        for (blobs.items) |*blob| blob.deinit(allocator);
        blobs.deinit(allocator);
    }

    var matched = false;
    for (doc.operations) |operation| {
        if (!operation.cell.eql(id)) continue;
        matched = true;
        const cut = operation.bounds;
        if (operation.kind == .add_block) {
            var block_solid = try Solid.fromBox(allocator, cut);
            defer block_solid.deinit(allocator);
            try unionInto(allocator, &add_solid, block_solid);
            has_add_solid = true;
            continue;
        }
        if (operation.kind == .add_wedge) {
            var wedge_solid = try wedgeSolidFromBounds(allocator, cut);
            defer wedge_solid.deinit(allocator);
            try unionInto(allocator, &add_solid, wedge_solid);
            has_add_solid = true;
            continue;
        }
        if (operation.kind == .add_prism) {
            var prism_solid = try Solid.fromConvexPrism(allocator, operation.footprint, operation.bounds.min[1], operation.bounds.max[1]);
            defer prism_solid.deinit(allocator);
            try unionInto(allocator, &add_solid, prism_solid);
            has_add_solid = true;
            continue;
        }

        const wall = operation.wall orelse return error.InvalidCsgOperation;
        if (has_add_solid) {
            try subtractInto(allocator, &add_solid, operation);
        } else {
            var source_solid = try Solid.fromBox(allocator, wall);
            defer source_solid.deinit(allocator);
            var remainder = try subtractFromSolid(allocator, source_solid, operation);
            defer remainder.deinit(allocator);
            if (solidHasGeometry(remainder)) {
                try appendSolidRenderMesh(allocator, &meshes, remainder, "local_csg.remainder");
            }
            try appendSolidCollisions(allocator, &collisions, &collision_shapes, remainder);
        }
        if (operation.kind == .doorway_subtract) {
            try appendTrim(allocator, &meshes, cut);
            try appendDoorwayVisibility(allocator, &visibility, id, cut);
            try world.compiler.layer.appendBlobJson(allocator, &blobs, "local_csg.semantic", .{
                .cell = .{ id.x, id.y, id.z },
                .wall = wall,
                .opening = cut,
                .portal = .{
                    .min = cut.min,
                    .max = cut.max,
                },
            });
        }
    }

    if (!matched) return .{};
    if (has_add_solid and solidHasGeometry(add_solid)) {
        try appendSolidRenderMesh(allocator, &meshes, add_solid, "local_csg.additive");
        try appendSolidCollisions(allocator, &collisions, &collision_shapes, add_solid);
    }
    return .{
        .render_meshes = try meshes.toOwnedSlice(allocator),
        .collisions = try collisions.toOwnedSlice(allocator),
        .collision_shapes = try collision_shapes.toOwnedSlice(allocator),
        .visibility = try visibility.toOwnedSlice(allocator),
        .blobs = try blobs.toOwnedSlice(allocator),
    };
}

fn unionInto(allocator: std.mem.Allocator, target: *Solid, source: Solid) !void {
    const next = try target.*.unionWith(allocator, source);
    target.deinit(allocator);
    target.* = next;
}

fn subtractInto(allocator: std.mem.Allocator, target: *Solid, operation: LayerOperation) !void {
    const next = try subtractFromSolid(allocator, target.*, operation);
    target.deinit(allocator);
    target.* = next;
}

fn subtractFromSolid(allocator: std.mem.Allocator, source: Solid, operation: LayerOperation) !Solid {
    return switch (operation.kind) {
        .subtract_prism => source.subtractConvexPrism(allocator, operation.footprint, operation.bounds.min[1], operation.bounds.max[1]),
        .subtract_wedge => blk: {
            const footprint = wedgeFootprintFromBounds(operation.bounds);
            break :blk source.subtractConvexPrism(allocator, &footprint, operation.bounds.min[1], operation.bounds.max[1]);
        },
        else => source.subtractBox(allocator, operation.bounds),
    };
}

fn solidHasGeometry(input_solid: Solid) bool {
    return input_solid.boxes.len > 0 or input_solid.prisms.len > 0;
}

fn appendSolidCollisions(
    allocator: std.mem.Allocator,
    collisions: *std.ArrayList(world.cell.CollisionPlaceholder),
    collision_shapes: *std.ArrayList(world.cell.CollisionShape),
    input_solid: Solid,
) !void {
    for (input_solid.boxes) |segment| {
        try appendCollisionAabb(allocator, collisions, collision_shapes, segment);
    }
    for (input_solid.prisms) |prism| {
        try appendCollisionAabb(allocator, collisions, collision_shapes, prismAabb(prism));
    }
}

fn appendBlock(
    allocator: std.mem.Allocator,
    meshes: *std.ArrayList(world.cell.RenderMesh),
    collisions: *std.ArrayList(world.cell.CollisionPlaceholder),
    collision_shapes: *std.ArrayList(world.cell.CollisionShape),
    box: Aabb,
    name: []const u8,
) !void {
    var box_solid = try Solid.fromBox(allocator, box);
    defer box_solid.deinit(allocator);
    try appendSolid(allocator, meshes, collisions, collision_shapes, box_solid, box, name);
}

fn appendWedge(
    allocator: std.mem.Allocator,
    meshes: *std.ArrayList(world.cell.RenderMesh),
    collisions: *std.ArrayList(world.cell.CollisionPlaceholder),
    collision_shapes: *std.ArrayList(world.cell.CollisionShape),
    box: Aabb,
    name: []const u8,
) !void {
    var wedge_solid = try wedgeSolidFromBounds(allocator, box);
    defer wedge_solid.deinit(allocator);
    try appendSolid(allocator, meshes, collisions, collision_shapes, wedge_solid, box, name);
}

fn appendPrism(
    allocator: std.mem.Allocator,
    meshes: *std.ArrayList(world.cell.RenderMesh),
    collisions: *std.ArrayList(world.cell.CollisionPlaceholder),
    collision_shapes: *std.ArrayList(world.cell.CollisionShape),
    prism: ConvexPrism,
    bounds: Aabb,
    name: []const u8,
) !void {
    const prism_solid = Solid{ .prisms = @constCast(&[_]ConvexPrism{prism}) };
    try appendSolid(allocator, meshes, collisions, collision_shapes, prism_solid, bounds, name);
}

fn wedgeSolidFromBounds(allocator: std.mem.Allocator, box: Aabb) !Solid {
    const footprint = wedgeFootprintFromBounds(box);
    return Solid.fromConvexPrism(allocator, &footprint, box.min[1], box.max[1]);
}

fn wedgeFootprintFromBounds(box: Aabb) [3]Point2 {
    return .{
        .{ box.min[0], box.min[2] },
        .{ box.max[0], box.min[2] },
        .{ box.min[0], box.max[2] },
    };
}

fn appendSolid(
    allocator: std.mem.Allocator,
    meshes: *std.ArrayList(world.cell.RenderMesh),
    collisions: *std.ArrayList(world.cell.CollisionPlaceholder),
    collision_shapes: *std.ArrayList(world.cell.CollisionShape),
    input_solid: Solid,
    bounds: Aabb,
    name: []const u8,
) !void {
    try appendSolidRenderMesh(allocator, meshes, input_solid, name);
    try appendCollisionAabb(allocator, collisions, collision_shapes, bounds);
}

fn appendSolidRenderMesh(
    allocator: std.mem.Allocator,
    meshes: *std.ArrayList(world.cell.RenderMesh),
    input_solid: Solid,
    name: []const u8,
) !void {
    var mesh = try input_solid.toMesh(allocator);
    defer mesh.deinit(allocator);
    const verts = try allocator.alloc(world.cell.RenderVertex, mesh.vertices.len);
    errdefer allocator.free(verts);
    for (mesh.vertices, 0..) |vertex, idx| {
        verts[idx] = .{
            .position = .{ .x = vertex.position[0], .y = vertex.position[1], .z = vertex.position[2] },
            .normal = .{ .x = vertex.normal[0], .y = vertex.normal[1], .z = vertex.normal[2] },
            .uv = .{ .x = vertex.uv[0], .y = vertex.uv[1] },
        };
    }
    const indices = try allocator.dupe(u32, mesh.indices);
    errdefer allocator.free(indices);
    const texture = try allocator.alloc(u8, tex_size);
    @memset(texture, 145);
    errdefer allocator.free(texture);
    try meshes.append(allocator, .{
        .name = try allocator.dupe(u8, name),
        .vertices = verts,
        .indices = indices,
        .texture = texture,
        .base_color = .{ .r = 175, .g = 170, .b = 165, .a = 255 },
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
    });
}

fn appendCollisionAabb(
    allocator: std.mem.Allocator,
    collisions: *std.ArrayList(world.cell.CollisionPlaceholder),
    collision_shapes: *std.ArrayList(world.cell.CollisionShape),
    bounds: Aabb,
) !void {
    try collisions.append(allocator, .{
        .min = .{ .x = bounds.min[0], .y = bounds.min[1], .z = bounds.min[2] },
        .max = .{ .x = bounds.max[0], .y = bounds.max[1], .z = bounds.max[2] },
    });
    try collision_shapes.append(allocator, .{
        .kind = .aabb,
        .min = .{ .x = bounds.min[0], .y = bounds.min[1], .z = bounds.min[2] },
        .max = .{ .x = bounds.max[0], .y = bounds.max[1], .z = bounds.max[2] },
    });
}

fn appendDoorwayVisibility(
    allocator: std.mem.Allocator,
    visibility: *std.ArrayList(world.cell.VisibilityLink),
    cell_id: world.cell.CellId,
    opening: Aabb,
) !void {
    try visibility.append(allocator, .{
        .target = cell_id,
        .min = .{
            .x = opening.min[0],
            .y = opening.min[1],
            .z = opening.min[2],
        },
        .max = .{
            .x = opening.max[0],
            .y = opening.max[1],
            .z = opening.max[2],
        },
    });
}

fn appendTrim(
    allocator: std.mem.Allocator,
    meshes: *std.ArrayList(world.cell.RenderMesh),
    opening: Aabb,
) !void {
    const frame = Aabb{
        .min = .{ opening.min[0] - 0.1, opening.min[1], opening.min[2] - 0.02 },
        .max = .{ opening.max[0] + 0.1, opening.max[1] + 0.1, opening.max[2] + 0.02 },
    };
    const verts = try allocator.dupe(world.cell.RenderVertex, &.{
        .{ .position = .{ .x = frame.min[0], .y = frame.min[1], .z = frame.min[2] }, .normal = .{ .x = 0, .y = 0, .z = 1 }, .uv = .{ .x = 0, .y = 0 } },
        .{ .position = .{ .x = frame.max[0], .y = frame.min[1], .z = frame.min[2] }, .normal = .{ .x = 0, .y = 0, .z = 1 }, .uv = .{ .x = 1, .y = 0 } },
        .{ .position = .{ .x = frame.max[0], .y = frame.max[1], .z = frame.max[2] }, .normal = .{ .x = 0, .y = 0, .z = 1 }, .uv = .{ .x = 1, .y = 1 } },
        .{ .position = .{ .x = frame.min[0], .y = frame.max[1], .z = frame.max[2] }, .normal = .{ .x = 0, .y = 0, .z = 1 }, .uv = .{ .x = 0, .y = 1 } },
    });
    errdefer allocator.free(verts);
    const indices = try allocator.dupe(u32, &.{ 0, 1, 2, 0, 2, 3 });
    errdefer allocator.free(indices);
    const texture = try allocator.alloc(u8, tex_size);
    @memset(texture, 210);
    errdefer allocator.free(texture);
    try meshes.append(allocator, .{
        .name = try allocator.dupe(u8, "local_csg.trim"),
        .vertices = verts,
        .indices = indices,
        .texture = texture,
        .base_color = .{ .r = 205, .g = 190, .b = 155, .a = 255 },
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
    });
}

pub fn parseAabb(min_values: []const f32, max_values: []const f32) !Aabb {
    if (min_values.len != 3 or max_values.len != 3) return error.InvalidAabb;
    for (min_values, max_values) |min_value, max_value| {
        if (!std.math.isFinite(min_value) or !std.math.isFinite(max_value)) return error.InvalidAabb;
        if (min_value >= max_value) return error.InvalidAabb;
    }
    return .{
        .min = .{ min_values[0], min_values[1], min_values[2] },
        .max = .{ max_values[0], max_values[1], max_values[2] },
    };
}

pub fn parseJsonOperation(operation: CsgOperation) !LayerOperation {
    const cell_id = try parseCellId(operation.cell);
    const cut = try parseAabb(operation.min, operation.max);
    const kind = try OperationKind.parse(operation.op);
    if (kind == .add_block or kind == .add_wedge) {
        if (operation.wall_min != null or operation.wall_max != null) return error.InvalidCsgOperation;
        return .{
            .cell = cell_id,
            .kind = kind,
            .bounds = cut,
        };
    }

    const wall = try parseAabb(operation.wall_min orelse return error.InvalidCsgOperation, operation.wall_max orelse return error.InvalidCsgOperation);
    const parsed: LayerOperation = .{
        .cell = cell_id,
        .kind = kind,
        .bounds = cut,
        .wall = wall,
    };
    try validateLayerOperation(parsed);
    return parsed;
}

pub fn validateLayerOperation(operation: LayerOperation) !void {
    _ = try parseAabb(&operation.bounds.min, &operation.bounds.max);
    switch (operation.kind) {
        .add_block => {
            if (operation.wall != null) return error.InvalidCsgOperation;
        },
        .add_wedge => {
            if (operation.wall != null) return error.InvalidCsgOperation;
        },
        .add_prism => {
            if (operation.wall != null or operation.footprint.len < 3) return error.InvalidCsgOperation;
            try solid.validateConvexPrism(operation.footprint, operation.bounds.min[1], operation.bounds.max[1]);
            const expected = prismBoundsFromFootprint(operation.footprint, operation.bounds.min[1], operation.bounds.max[1]);
            if (!aabbNear(operation.bounds, expected)) return error.InvalidCsgOperation;
        },
        .subtract_block, .subtract_wedge, .doorway_subtract => {
            const wall = operation.wall orelse return error.InvalidCsgOperation;
            const cut = operation.bounds;
            _ = try parseAabb(&wall.min, &wall.max);
            if (cut.min[0] < wall.min[0] or cut.max[0] > wall.max[0]) return error.InvalidCsgOperation;
            if (cut.min[1] < wall.min[1] or cut.max[1] > wall.max[1]) return error.InvalidCsgOperation;
            if (cut.min[2] < wall.min[2] or cut.max[2] > wall.max[2]) return error.InvalidCsgOperation;
            if (operation.footprint.len != 0) return error.InvalidCsgOperation;
        },
        .subtract_prism => {
            const wall = operation.wall orelse return error.InvalidCsgOperation;
            const cut = operation.bounds;
            _ = try parseAabb(&wall.min, &wall.max);
            if (operation.footprint.len < 3) return error.InvalidCsgOperation;
            try solid.validateConvexPrism(operation.footprint, cut.min[1], cut.max[1]);
            const expected = prismBoundsFromFootprint(operation.footprint, cut.min[1], cut.max[1]);
            if (!aabbNear(cut, expected)) return error.InvalidCsgOperation;
            if (solid.aabbIntersection(cut, wall) == null) return error.InvalidCsgOperation;
        },
    }
}

fn prismBoundsFromFootprint(footprint: []const Point2, min_y: f32, max_y: f32) Aabb {
    var min_x = footprint[0][0];
    var max_x = min_x;
    var min_z = footprint[0][1];
    var max_z = min_z;
    for (footprint[1..]) |point| {
        min_x = @min(min_x, point[0]);
        max_x = @max(max_x, point[0]);
        min_z = @min(min_z, point[1]);
        max_z = @max(max_z, point[1]);
    }
    return .{ .min = .{ min_x, min_y, min_z }, .max = .{ max_x, max_y, max_z } };
}

fn aabbNear(a: Aabb, b: Aabb) bool {
    return point3Near(a.min, b.min) and point3Near(a.max, b.max);
}

fn point3Near(a: [3]f32, b: [3]f32) bool {
    return @abs(a[0] - b[0]) <= 0.0001 and @abs(a[1] - b[1]) <= 0.0001 and @abs(a[2] - b[2]) <= 0.0001;
}

fn prismAabb(prism: ConvexPrism) Aabb {
    var min_x = prism.footprint[0][0];
    var max_x = min_x;
    var min_z = prism.footprint[0][1];
    var max_z = min_z;
    for (prism.footprint[1..]) |point| {
        min_x = @min(min_x, point[0]);
        max_x = @max(max_x, point[0]);
        min_z = @min(min_z, point[1]);
        max_z = @max(max_z, point[1]);
    }
    return .{
        .min = .{ min_x, prism.min_y, min_z },
        .max = .{ max_x, prism.max_y, max_z },
    };
}

pub fn formatOperation(operation: LayerOperation) FormattedCsgOperation {
    return .{
        .cell = .{ operation.cell.x, operation.cell.y, operation.cell.z },
        .op = operation.kind.jsonName(),
        .min = operation.bounds.min,
        .max = operation.bounds.max,
        .wall_min = if (operation.wall) |wall| wall.min else null,
        .wall_max = if (operation.wall) |wall| wall.max else null,
        .footprint = if (operation.footprint.len > 0) operation.footprint else null,
    };
}

fn parseCellId(values: []const i32) !world.cell.CellId {
    if (values.len != 2 and values.len != 3) return error.InvalidLocalCsgCell;
    return .{
        .x = @intCast(values[0]),
        .y = @intCast(values[1]),
        .z = if (values.len == 3) @intCast(values[2]) else 0,
    };
}

fn loadLayerDocumentForCompile(
    allocator: std.mem.Allocator,
    compile_ctx: *const world.compiler.layer.CompileContext,
) !LayerDocument {
    const path = try layerPath(allocator, compile_ctx.manifest_path);
    defer allocator.free(path);
    var project_dir = try openProjectDir(compile_ctx.io, compile_ctx.project_path);
    defer project_dir.close(compile_ctx.io);
    const bytes = project_dir.readFileAlloc(compile_ctx.io, path, allocator, .limited(8 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => try allocator.dupe(u8, "local_csg version=1 {\n}\n"),
        else => return err,
    };
    defer allocator.free(bytes);
    return document.parseLayerDocument(allocator, bytes);
}

fn layerPath(allocator: std.mem.Allocator, manifest_path: []const u8) ![]u8 {
    const dir = std.fs.path.dirname(manifest_path) orelse "";
    if (dir.len == 0) return allocator.dupe(u8, local_csg_layer_file);
    return std.fs.path.join(allocator, &.{ dir, local_csg_layer_file });
}

fn openProjectDir(io: std.Io, project_path: []const u8) !std.Io.Dir {
    if (std.fs.path.isAbsolute(project_path)) return std.Io.Dir.openDirAbsolute(io, project_path, .{});
    return std.Io.Dir.cwd().openDir(io, project_path, .{});
}

comptime {
    _ = @import("mod_tests.zig");
}
