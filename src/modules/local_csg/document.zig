const std = @import("std");
const world = @import("../../world/mod.zig");
const kdl = @import("kdl");
const layer_kdl = @import("../layer_kdl.zig");
const csg = @import("mod.zig");

const Aabb = csg.Aabb;
const Point2 = csg.Point2;
const OperationKind = csg.OperationKind;
const LayerOperation = csg.LayerOperation;
const LayerDocument = csg.LayerDocument;
const FormattedCsgDoc = csg.FormattedCsgDoc;
const FormattedCsgOperation = csg.FormattedCsgOperation;
const local_csg_layer_file = "layers/local_csg.kdl";

pub fn parseLayerDocument(allocator: std.mem.Allocator, bytes: []const u8) !LayerDocument {
    const buffer = try allocator.allocSentinel(u8, bytes.len, 0);
    defer allocator.free(buffer);
    @memcpy(buffer, bytes);

    var parser = kdl.Parser.init(buffer);
    var operations = std.ArrayList(LayerOperation).empty;
    errdefer {
        for (operations.items) |*operation| operation.deinit(allocator);
        operations.deinit(allocator);
    }

    var depth: i32 = 0;
    var root_seen = false;
    var builder: ?OperationBuilder = null;
    errdefer {
        if (builder) |*operation| operation.deinit();
    }

    while (true) {
        const event = try parser.next();
        switch (event) {
            .node => |node| {
                if (depth == 0) {
                    if (root_seen or !std.mem.eql(u8, node.val, "local_csg")) return error.InvalidLocalCsgDocument;
                    root_seen = true;
                    continue;
                }
                if (depth == 1) {
                    if (!std.mem.eql(u8, node.val, "operation")) return error.UnknownField;
                    if (builder) |*operation| {
                        try appendFinishedOperation(allocator, &operations, operation);
                    }
                    builder = .{ .allocator = allocator };
                    continue;
                }
                return error.InvalidLocalCsgDocument;
            },
            .prop => |prop| {
                const value = try layer_kdl.decodeValue(allocator, prop.val);
                defer allocator.free(value);
                if (depth == 0) {
                    if (!std.mem.eql(u8, prop.key, "version")) return error.UnknownField;
                    if (try std.fmt.parseInt(u32, value, 10) != 1) return error.UnsupportedLocalCsgSchemaVersion;
                    continue;
                }
                if (depth == 1) {
                    var operation = &(builder orelse return error.InvalidLocalCsgDocument);
                    try operation.apply(prop.key, value);
                    continue;
                }
                return error.InvalidLocalCsgDocument;
            },
            .child_block_begin => depth += 1,
            .child_block_end => {
                if (depth == 1) {
                    if (builder) |*operation| {
                        try appendFinishedOperation(allocator, &operations, operation);
                        builder = null;
                    }
                }
                depth -= 1;
                if (depth < 0) return error.InvalidLocalCsgDocument;
            },
            .arg, .invalid => return error.InvalidLocalCsgDocument,
            .eof => break,
        }
    }
    if (builder) |*operation| {
        try appendFinishedOperation(allocator, &operations, operation);
    }
    if (!root_seen or depth != 0) return error.InvalidLocalCsgDocument;
    return .{ .operations = try operations.toOwnedSlice(allocator) };
}

fn appendFinishedOperation(
    allocator: std.mem.Allocator,
    operations: *std.ArrayList(LayerOperation),
    builder: *OperationBuilder,
) !void {
    var operation = try builder.finish();
    errdefer operation.deinit(allocator);
    try operations.append(allocator, operation);
    builder.deinit();
}

pub fn formatLayerDocument(allocator: std.mem.Allocator, operations: []const LayerOperation) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    const writer = &out.writer;
    try writer.writeAll("local_csg version=1 {\n");
    for (operations) |operation| {
        try csg.validateLayerOperation(operation);
        try writer.print("  operation cell=\"{d},{d},{d}\" op=\"{s}\" min=\"", .{ operation.cell.x, operation.cell.y, operation.cell.z, operation.kind.jsonName() });
        try layer_kdl.writeF32Triple(writer, operation.bounds.min);
        try writer.writeAll("\" max=\"");
        try layer_kdl.writeF32Triple(writer, operation.bounds.max);
        if (operation.wall) |wall| {
            try writer.writeAll("\" wall_min=\"");
            try layer_kdl.writeF32Triple(writer, wall.min);
            try writer.writeAll("\" wall_max=\"");
            try layer_kdl.writeF32Triple(writer, wall.max);
        }
        if (operation.footprint.len > 0) {
            try writer.writeAll("\" footprint=\"");
            try layer_kdl.writeF32PairList(writer, operation.footprint);
        }
        try writer.writeAll("\"\n");
    }
    try writer.writeAll("}\n");
    return out.toOwnedSlice();
}

const OperationBuilder = struct {
    allocator: std.mem.Allocator,
    cell: ?world.cell.CellId = null,
    kind: ?OperationKind = null,
    min: ?[3]f32 = null,
    max: ?[3]f32 = null,
    wall_min: ?[3]f32 = null,
    wall_max: ?[3]f32 = null,
    footprint: []Point2 = &.{},

    fn deinit(self: *OperationBuilder) void {
        self.allocator.free(self.footprint);
        self.footprint = &.{};
    }

    fn apply(self: *OperationBuilder, key: []const u8, value: []const u8) !void {
        if (std.mem.eql(u8, key, "cell")) {
            const parsed = try layer_kdl.parseI32Triple(value);
            self.cell = .{ .x = parsed[0], .y = parsed[1], .z = parsed[2] };
        } else if (std.mem.eql(u8, key, "op")) self.kind = try OperationKind.parse(value) else if (std.mem.eql(u8, key, "min")) self.min = try layer_kdl.parseF32Triple(value) else if (std.mem.eql(u8, key, "max")) self.max = try layer_kdl.parseF32Triple(value) else if (std.mem.eql(u8, key, "wall_min")) self.wall_min = try layer_kdl.parseF32Triple(value) else if (std.mem.eql(u8, key, "wall_max")) self.wall_max = try layer_kdl.parseF32Triple(value) else if (std.mem.eql(u8, key, "footprint")) {
            self.allocator.free(self.footprint);
            self.footprint = try parsePoint2Owned(self.allocator, value);
        } else return error.UnknownField;
    }

    fn finish(self: *OperationBuilder) !LayerOperation {
        const wall = if (self.wall_min != null or self.wall_max != null) Aabb{
            .min = self.wall_min orelse return error.InvalidCsgOperation,
            .max = self.wall_max orelse return error.InvalidCsgOperation,
        } else null;
        const operation = LayerOperation{
            .cell = self.cell orelse return error.InvalidCsgOperation,
            .kind = self.kind orelse return error.InvalidCsgOperation,
            .bounds = .{
                .min = self.min orelse return error.InvalidCsgOperation,
                .max = self.max orelse return error.InvalidCsgOperation,
            },
            .wall = wall,
            .footprint = self.footprint,
        };
        self.footprint = &.{};
        try csg.validateLayerOperation(operation);
        return operation;
    }
};

fn parsePoint2Owned(allocator: std.mem.Allocator, value: []const u8) ![]Point2 {
    const rows = try layer_kdl.parsePoint2List(allocator, value);
    defer layer_kdl.freeNestedF32(allocator, rows);
    var out = try allocator.alloc(Point2, rows.len);
    errdefer allocator.free(out);
    for (rows, 0..) |row, idx| {
        out[idx] = .{ row[0], row[1] };
    }
    return out;
}

pub fn appendOperationToBytes(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    operation: LayerOperation,
) ![]u8 {
    var doc = try parseLayerDocument(allocator, bytes);
    defer doc.deinit(allocator);
    try csg.validateLayerOperation(operation);

    var next = try allocator.alloc(LayerOperation, doc.operations.len + 1);
    defer allocator.free(next);
    @memcpy(next[0..doc.operations.len], doc.operations);
    next[doc.operations.len] = operation;
    return formatLayerDocument(allocator, next);
}

pub fn readLayerDocument(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    manifest_path: []const u8,
) !LayerDocument {
    const path = try layerPath(allocator, manifest_path);
    defer allocator.free(path);
    var project_dir = try openProjectDir(io, project_path);
    defer project_dir.close(io);
    const bytes = try project_dir.readFileAlloc(io, path, allocator, .limited(8 * 1024 * 1024));
    defer allocator.free(bytes);
    return parseLayerDocument(allocator, bytes);
}

pub fn writeLayerDocument(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    manifest_path: []const u8,
    operations: []const LayerOperation,
) !void {
    const path = try layerPath(allocator, manifest_path);
    defer allocator.free(path);
    const bytes = try formatLayerDocument(allocator, operations);
    defer allocator.free(bytes);

    var project_dir = try openProjectDir(io, project_path);
    defer project_dir.close(io);
    if (std.fs.path.dirname(path)) |parent| {
        try project_dir.createDirPath(io, parent);
    }
    try project_dir.writeFile(io, .{ .sub_path = path, .data = bytes });
}

pub fn appendLayerOperation(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    manifest_path: []const u8,
    operation: LayerOperation,
) !void {
    const path = try layerPath(allocator, manifest_path);
    defer allocator.free(path);
    var project_dir = try openProjectDir(io, project_path);
    defer project_dir.close(io);

    const existing = project_dir.readFileAlloc(io, path, allocator, .limited(8 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => try allocator.dupe(u8, "local_csg version=1 {\n}\n"),
        else => return err,
    };
    defer allocator.free(existing);
    const updated = try appendOperationToBytes(allocator, existing, operation);
    defer allocator.free(updated);

    if (std.fs.path.dirname(path)) |parent| {
        try project_dir.createDirPath(io, parent);
    }
    try project_dir.writeFile(io, .{ .sub_path = path, .data = updated });
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
