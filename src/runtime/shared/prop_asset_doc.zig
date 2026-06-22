const std = @import("std");
const kdl = @import("kdl");
const editor_math = @import("editor_math.zig");
const geometry = @import("geometry.zig");
const shared_color = @import("color.zig");
const scene_kdl_values = @import("scene_kdl_values.zig");
const scene_texture = @import("scene_texture.zig");

pub const schema_version: u32 = 1;

pub const PropAssetDocument = struct {
    id: []u8,
    label: []u8,
    tags: []u8,
    deleted: bool,
    mesh_path: []u8,
    recipe: Recipe,
    base_color: shared_color.Color,
    material_path: ?[]u8 = null,
    texture_path: ?[]u8 = null,
    face_materials: []scene_texture.FaceMaterial = &.{},
    variant_count: u32,

    pub fn deinit(self: *PropAssetDocument, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.label);
        allocator.free(self.tags);
        allocator.free(self.mesh_path);
        self.recipe.deinit(allocator);
        if (self.material_path) |path| allocator.free(path);
        if (self.texture_path) |path| allocator.free(path);
        for (self.face_materials) |*face| face.deinit(allocator);
        allocator.free(self.face_materials);
    }
};

pub const Recipe = struct {
    sources: []Source = &.{},
    modifiers: []Modifier = &.{},
    shape_intents: []ShapeIntent = &.{},

    pub fn deinit(self: *Recipe, allocator: std.mem.Allocator) void {
        for (self.sources) |*source| source.deinit(allocator);
        for (self.modifiers) |*modifier| modifier.deinit(allocator);
        for (self.shape_intents) |*intent| intent.deinit(allocator);
        allocator.free(self.sources);
        allocator.free(self.modifiers);
        allocator.free(self.shape_intents);
        self.sources = &.{};
        self.modifiers = &.{};
        self.shape_intents = &.{};
    }
};

pub const Source = struct {
    id: []u8,
    kind: SourceKind,
    position: [3]f32,
    rotation: [4]f32,
    scale: [3]f32,
    radius: f32,
    segments: u32,
    rings: u32,

    pub fn deinit(self: *Source, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
    }
};

pub const SourceKind = enum {
    sphere,
};

pub const ShapeIntent = struct {
    id: []u8,
    source_kind: ShapeSourceKind,
    operation_kind: ShapeOperationKind,
    amount: f32 = 1.0,
    segments: u32 = 24,
    primitive_kind: geometry.PrimitiveKind = .box,
    primitive_params: geometry.PrimitiveParams = .{},
    points: []editor_math.Vec3,

    pub fn deinit(self: *ShapeIntent, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.points);
    }
};

pub const ShapeSourceKind = enum {
    closed_face,
    open_profile,
    path,
    primitive_seed,
    existing_mesh,
};

pub const ShapeOperationKind = enum {
    extrude,
    solidify,
    revolve,
    cut,
    inset,
    bevel,
    mirror,
    array,
};

pub const Modifier = struct {
    id: []u8,
    source_id: []u8,
    kind: ModifierKind,
    data: ModifierData,

    pub fn deinit(self: *Modifier, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.source_id);
        switch (self.data) {
            .lattice => |*lattice| allocator.free(lattice.points),
            else => {},
        }
    }
};

pub const ModifierKind = enum {
    bend,
    taper,
    lattice,
};

pub const Axis = enum {
    x,
    y,
    z,
};

pub const ModifierData = union(ModifierKind) {
    bend: Bend,
    taper: Taper,
    lattice: Lattice,
};

pub const Bend = struct {
    axis: Axis,
    amount: f32,
};

pub const Taper = struct {
    axis: Axis,
    amount: f32,
};

pub const Lattice = struct {
    dimensions: [3]u32,
    points: []LatticePoint,
};

pub const LatticePoint = struct {
    index: [3]u32,
    offset: [3]f32,
};

pub fn documentPath(allocator: std.mem.Allocator, id: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "props/{s}.kdl", .{id});
}

pub fn meshPath(allocator: std.mem.Allocator, id: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "props/meshes/{s}.fmesh", .{id});
}

pub fn texturePath(allocator: std.mem.Allocator, id: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "props/textures/{s}.rgba", .{id});
}

pub fn parse(allocator: std.mem.Allocator, source: []const u8) !PropAssetDocument {
    const buffer = try allocator.allocSentinel(u8, source.len, 0);
    defer allocator.free(buffer);
    @memcpy(buffer, source);

    var parser = kdl.Parser.init(buffer);
    var depth: i32 = 0;
    var id: ?[]u8 = null;
    var label: ?[]u8 = null;
    var tags: ?[]u8 = null;
    var deleted = false;
    var mesh_path_value: ?[]u8 = null;
    var recipe_sources: std.ArrayList(Source) = .empty;
    defer recipe_sources.deinit(allocator);
    var recipe_modifiers: std.ArrayList(Modifier) = .empty;
    defer recipe_modifiers.deinit(allocator);
    var recipe_shape_intents: std.ArrayList(ShapeIntent) = .empty;
    defer recipe_shape_intents.deinit(allocator);
    var base_color: shared_color.Color = .{ .r = 255, .g = 255, .b = 255, .a = 255 };
    var material_path_value: ?[]u8 = null;
    var texture_path_value: ?[]u8 = null;
    var face_materials: std.ArrayList(scene_texture.FaceMaterial) = .empty;
    defer face_materials.deinit(allocator);
    var pending_face: ?scene_texture.FaceMaterial = null;
    var variant_count: u32 = 1;
    var section: ?[]const u8 = null;
    var recipe_node: ?[]const u8 = null;
    var pending_source: ?Source = null;
    var pending_modifier: ?Modifier = null;
    var pending_shape_intent: ?ShapeIntent = null;
    errdefer {
        if (id) |value| allocator.free(value);
        if (label) |value| allocator.free(value);
        if (tags) |value| allocator.free(value);
        if (mesh_path_value) |value| allocator.free(value);
        if (material_path_value) |value| allocator.free(value);
        if (texture_path_value) |value| allocator.free(value);
        if (pending_face) |*value| value.deinit(allocator);
        for (face_materials.items) |*value| value.deinit(allocator);
        if (pending_source) |*value| value.deinit(allocator);
        if (pending_modifier) |*value| value.deinit(allocator);
        if (pending_shape_intent) |*value| value.deinit(allocator);
        for (recipe_sources.items) |*value| value.deinit(allocator);
        for (recipe_modifiers.items) |*value| value.deinit(allocator);
        for (recipe_shape_intents.items) |*value| value.deinit(allocator);
    }

    while (true) {
        const event = try parser.next();
        switch (event) {
            .node => |node| {
                if (depth == 0) {
                    if (!std.mem.eql(u8, node.val, "prop_asset")) return error.InvalidPropAssetDocument;
                } else if (depth == 1) {
                    if (section != null and std.mem.eql(u8, section.?, "face")) {
                        try finishPendingFace(allocator, &face_materials, &pending_face);
                    }
                    section = node.val;
                    if (std.mem.eql(u8, section.?, "recipe")) recipe_node = null;
                } else if (depth == 2) {
                    const section_name = section orelse return error.InvalidPropAssetDocument;
                    if (std.mem.eql(u8, section_name, "recipe")) {
                        try finishPendingRecipeNode(allocator, &recipe_sources, &recipe_modifiers, &recipe_shape_intents, &pending_source, &pending_modifier, &pending_shape_intent);
                        recipe_node = node.val;
                        if (std.mem.eql(u8, node.val, "source")) {
                            if (pending_source != null) return error.InvalidPropAssetDocument;
                            pending_source = .{
                                .id = try allocator.dupe(u8, ""),
                                .kind = .sphere,
                                .position = undefined,
                                .rotation = undefined,
                                .scale = undefined,
                                .radius = 0,
                                .segments = 0,
                                .rings = 0,
                            };
                        } else if (std.mem.eql(u8, node.val, "modifier")) {
                            if (pending_modifier != null) return error.InvalidPropAssetDocument;
                            pending_modifier = .{
                                .id = try allocator.dupe(u8, ""),
                                .source_id = try allocator.dupe(u8, ""),
                                .kind = .bend,
                                .data = .{ .bend = .{ .axis = .x, .amount = 0 } },
                            };
                        } else if (std.mem.eql(u8, node.val, "shape")) {
                            if (pending_shape_intent != null) return error.InvalidPropAssetDocument;
                            pending_shape_intent = .{
                                .id = try allocator.dupe(u8, ""),
                                .source_kind = .closed_face,
                                .operation_kind = .extrude,
                                .points = &.{},
                            };
                        } else {
                            return error.InvalidPropAssetDocument;
                        }
                    }
                }
            },
            .prop => |prop| {
                const value = try scene_kdl_values.decodeValue(allocator, prop.val);
                defer allocator.free(value);
                if (depth == 0) {
                    if (std.mem.eql(u8, prop.key, "id")) {
                        if (id) |existing| allocator.free(existing);
                        id = try allocator.dupe(u8, value);
                    } else if (std.mem.eql(u8, prop.key, "label")) {
                        if (label) |existing| allocator.free(existing);
                        label = try allocator.dupe(u8, value);
                    } else if (std.mem.eql(u8, prop.key, "tags")) {
                        if (tags) |existing| allocator.free(existing);
                        tags = try allocator.dupe(u8, value);
                    } else if (std.mem.eql(u8, prop.key, "deleted")) {
                        deleted = std.ascii.eqlIgnoreCase(value, "true");
                    }
                    continue;
                }
                if (depth == 2) {
                    const section_name = section orelse return error.InvalidPropAssetDocument;
                    const node_name = recipe_node orelse return error.InvalidPropAssetDocument;
                    if (!std.mem.eql(u8, section_name, "recipe")) return error.InvalidPropAssetDocument;
                    if (std.mem.eql(u8, node_name, "source")) {
                        var pending = &(pending_source orelse return error.InvalidPropAssetDocument);
                        if (std.mem.eql(u8, prop.key, "id")) {
                            allocator.free(pending.id);
                            pending.id = try allocator.dupe(u8, value);
                        } else if (std.mem.eql(u8, prop.key, "kind")) {
                            pending.kind = sourceKindFromName(value) orelse return error.InvalidValue;
                        } else if (std.mem.eql(u8, prop.key, "position")) {
                            pending.position = try scene_kdl_values.parseFloatTriple(value);
                        } else if (std.mem.eql(u8, prop.key, "rotation")) {
                            pending.rotation = try parseFloatQuad(value);
                        } else if (std.mem.eql(u8, prop.key, "scale")) {
                            pending.scale = try scene_kdl_values.parseFloatTriple(value);
                        } else if (std.mem.eql(u8, prop.key, "radius")) {
                            pending.radius = try scene_kdl_values.parseF32(value);
                        } else if (std.mem.eql(u8, prop.key, "segments")) {
                            pending.segments = try scene_kdl_values.parseU32(value);
                        } else if (std.mem.eql(u8, prop.key, "rings")) {
                            pending.rings = try scene_kdl_values.parseU32(value);
                        }
                    } else if (std.mem.eql(u8, node_name, "modifier")) {
                        var modifier = &(pending_modifier orelse return error.InvalidPropAssetDocument);
                        if (std.mem.eql(u8, prop.key, "id")) {
                            allocator.free(modifier.id);
                            modifier.id = try allocator.dupe(u8, value);
                        } else if (std.mem.eql(u8, prop.key, "source")) {
                            allocator.free(modifier.source_id);
                            modifier.source_id = try allocator.dupe(u8, value);
                        } else if (std.mem.eql(u8, prop.key, "kind")) {
                            modifier.kind = modifierKindFromName(value) orelse return error.InvalidValue;
                            modifier.data = switch (modifier.kind) {
                                .bend => .{ .bend = .{ .axis = .x, .amount = 0 } },
                                .taper => .{ .taper = .{ .axis = .y, .amount = 0 } },
                                .lattice => .{ .lattice = .{ .dimensions = .{ 0, 0, 0 }, .points = &.{} } },
                            };
                        } else if (std.mem.eql(u8, prop.key, "axis")) {
                            const axis = axisFromName(value) orelse return error.InvalidValue;
                            switch (modifier.data) {
                                .bend => |*bend| bend.axis = axis,
                                .taper => |*taper| taper.axis = axis,
                                .lattice => return error.InvalidPropAssetDocument,
                            }
                        } else if (std.mem.eql(u8, prop.key, "amount")) {
                            const amount = try scene_kdl_values.parseF32(value);
                            switch (modifier.data) {
                                .bend => |*bend| bend.amount = amount,
                                .taper => |*taper| taper.amount = amount,
                                .lattice => return error.InvalidPropAssetDocument,
                            }
                        } else if (std.mem.eql(u8, prop.key, "dimensions")) {
                            switch (modifier.data) {
                                .lattice => |*lattice| lattice.dimensions = try parseU32Triple(value),
                                else => return error.InvalidPropAssetDocument,
                            }
                        } else if (std.mem.eql(u8, prop.key, "points")) {
                            switch (modifier.data) {
                                .lattice => |*lattice| lattice.points = try parseLatticePoints(allocator, value),
                                else => return error.InvalidPropAssetDocument,
                            }
                        }
                    } else if (std.mem.eql(u8, node_name, "shape")) {
                        var intent = &(pending_shape_intent orelse return error.InvalidPropAssetDocument);
                        if (std.mem.eql(u8, prop.key, "id")) {
                            allocator.free(intent.id);
                            intent.id = try allocator.dupe(u8, value);
                        } else if (std.mem.eql(u8, prop.key, "source")) {
                            intent.source_kind = shapeSourceKindFromName(value) orelse return error.InvalidValue;
                        } else if (std.mem.eql(u8, prop.key, "operation")) {
                            intent.operation_kind = shapeOperationKindFromName(value) orelse return error.InvalidValue;
                        } else if (std.mem.eql(u8, prop.key, "amount")) {
                            intent.amount = try scene_kdl_values.parseF32(value);
                        } else if (std.mem.eql(u8, prop.key, "segments")) {
                            intent.segments = try scene_kdl_values.parseU32(value);
                            intent.primitive_params.segments = intent.segments;
                        } else if (std.mem.eql(u8, prop.key, "primitive")) {
                            intent.primitive_kind = primitiveKindFromName(value) orelse return error.InvalidValue;
                        } else if (std.mem.eql(u8, prop.key, "width")) {
                            intent.primitive_params.width = try scene_kdl_values.parseF32(value);
                        } else if (std.mem.eql(u8, prop.key, "height")) {
                            intent.primitive_params.height = try scene_kdl_values.parseF32(value);
                        } else if (std.mem.eql(u8, prop.key, "depth")) {
                            intent.primitive_params.depth = try scene_kdl_values.parseF32(value);
                        } else if (std.mem.eql(u8, prop.key, "radius")) {
                            intent.primitive_params.radius = try scene_kdl_values.parseF32(value);
                        } else if (std.mem.eql(u8, prop.key, "points")) {
                            allocator.free(intent.points);
                            intent.points = try parseShapePoints(allocator, value);
                        }
                    }
                    continue;
                }
                if (depth != 1) continue;
                const section_name = section orelse return error.InvalidPropAssetDocument;
                if (std.mem.eql(u8, section_name, "recipe")) {
                    return error.InvalidPropAssetDocument;
                } else if (std.mem.eql(u8, section_name, "mesh")) {
                    if (std.mem.eql(u8, prop.key, "asset")) {
                        if (mesh_path_value) |existing| allocator.free(existing);
                        mesh_path_value = try allocator.dupe(u8, value);
                    }
                } else if (std.mem.eql(u8, section_name, "material")) {
                    if (std.mem.eql(u8, prop.key, "base_color")) {
                        const color = try scene_kdl_values.parseU8Quad(value);
                        base_color = .{ .r = color[0], .g = color[1], .b = color[2], .a = color[3] };
                    } else if (std.mem.eql(u8, prop.key, "path")) {
                        if (material_path_value) |existing| allocator.free(existing);
                        material_path_value = try allocator.dupe(u8, value);
                    } else if (std.mem.eql(u8, prop.key, "texture")) {
                        if (texture_path_value) |existing| allocator.free(existing);
                        texture_path_value = try allocator.dupe(u8, value);
                    }
                } else if (std.mem.eql(u8, section_name, "face")) {
                    if (pending_face == null) {
                        pending_face = .{
                            .face_index = 0,
                            .material_path = try allocator.dupe(u8, ""),
                            .transform = .{},
                        };
                    }
                    var face = &(pending_face orelse return error.InvalidPropAssetDocument);
                    if (std.mem.eql(u8, prop.key, "index")) {
                        face.face_index = try std.fmt.parseInt(usize, value, 10);
                    } else if (std.mem.eql(u8, prop.key, "material")) {
                        allocator.free(face.material_path);
                        face.material_path = try allocator.dupe(u8, value);
                    } else if (std.mem.eql(u8, prop.key, "scale_world")) {
                        face.transform.scale_world = try scene_kdl_values.parseF32(value);
                    } else if (std.mem.eql(u8, prop.key, "rotation_deg")) {
                        face.transform.rotation_deg = try scene_kdl_values.parseF32(value);
                    } else if (std.mem.eql(u8, prop.key, "offset_u")) {
                        face.transform.offset_u = try scene_kdl_values.parseF32(value);
                    } else if (std.mem.eql(u8, prop.key, "offset_v")) {
                        face.transform.offset_v = try scene_kdl_values.parseF32(value);
                    }
                } else if (std.mem.eql(u8, section_name, "variants")) {
                    if (std.mem.eql(u8, prop.key, "count")) {
                        variant_count = try scene_kdl_values.parseU32(value);
                    }
                }
            },
            .child_block_begin => depth += 1,
            .child_block_end => {
                if (depth == 2 and section != null and std.mem.eql(u8, section.?, "recipe")) {
                    try finishPendingRecipeNode(allocator, &recipe_sources, &recipe_modifiers, &recipe_shape_intents, &pending_source, &pending_modifier, &pending_shape_intent);
                    recipe_node = null;
                }
                if (depth == 1 and section != null and std.mem.eql(u8, section.?, "face")) {
                    try finishPendingFace(allocator, &face_materials, &pending_face);
                }
                depth -= 1;
                if (depth == 0) section = null;
            },
            .arg, .invalid => return error.InvalidPropAssetDocument,
            .eof => break,
        }
    }
    if (depth != 0) return error.InvalidPropAssetDocument;
    const sources = try recipe_sources.toOwnedSlice(allocator);
    errdefer {
        for (sources) |*source_item| source_item.deinit(allocator);
        allocator.free(sources);
    }
    const modifiers = try recipe_modifiers.toOwnedSlice(allocator);
    errdefer {
        for (modifiers) |*modifier| modifier.deinit(allocator);
        allocator.free(modifiers);
    }
    const shape_intents = try recipe_shape_intents.toOwnedSlice(allocator);
    errdefer {
        for (shape_intents) |*intent| intent.deinit(allocator);
        allocator.free(shape_intents);
    }
    const faces = try face_materials.toOwnedSlice(allocator);
    errdefer {
        for (faces) |*face| face.deinit(allocator);
        allocator.free(faces);
    }
    return .{
        .id = id orelse return error.MissingPropAssetId,
        .label = label orelse return error.MissingPropAssetLabel,
        .tags = tags orelse try allocator.dupe(u8, ""),
        .deleted = deleted,
        .mesh_path = mesh_path_value orelse return error.MissingPropAssetMesh,
        .recipe = .{ .sources = sources, .modifiers = modifiers, .shape_intents = shape_intents },
        .base_color = base_color,
        .material_path = material_path_value,
        .texture_path = texture_path_value,
        .face_materials = faces,
        .variant_count = variant_count,
    };
}

fn finishPendingFace(
    allocator: std.mem.Allocator,
    faces: *std.ArrayList(scene_texture.FaceMaterial),
    pending_face: *?scene_texture.FaceMaterial,
) !void {
    if (pending_face.*) |face_value| {
        if (face_value.material_path.len == 0) return error.InvalidPropAssetDocument;
        try faces.append(allocator, face_value);
        pending_face.* = null;
    }
}

fn finishPendingRecipeNode(
    allocator: std.mem.Allocator,
    sources: *std.ArrayList(Source),
    modifiers: *std.ArrayList(Modifier),
    shape_intents: *std.ArrayList(ShapeIntent),
    pending_source: *?Source,
    pending_modifier: *?Modifier,
    pending_shape_intent: *?ShapeIntent,
) !void {
    if (pending_source.*) |source_value| {
        try validateSource(source_value);
        try sources.append(allocator, source_value);
        pending_source.* = null;
    }
    if (pending_modifier.*) |modifier_value| {
        try validateModifier(modifier_value);
        try modifiers.append(allocator, modifier_value);
        pending_modifier.* = null;
    }
    if (pending_shape_intent.*) |intent_value| {
        try validateShapeIntent(intent_value);
        try shape_intents.append(allocator, intent_value);
        pending_shape_intent.* = null;
    }
}

pub fn format(allocator: std.mem.Allocator, doc: PropAssetDocument) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    const writer = &out.writer;
    try writer.print("prop_asset version={d} id=\"{s}\" label=\"{s}\" tags=\"{s}\" deleted={s} {{\n", .{ schema_version, doc.id, doc.label, doc.tags, if (doc.deleted) "true" else "false" });
    try writer.writeAll("  recipe {\n");
    for (doc.recipe.sources) |source| {
        try writer.print("    source id=\"{s}\" kind={s} position=\"{d},{d},{d}\" rotation=\"{d},{d},{d},{d}\" scale=\"{d},{d},{d}\" radius={d} segments={d} rings={d}\n", .{
            source.id,
            sourceKindName(source.kind),
            source.position[0],
            source.position[1],
            source.position[2],
            source.rotation[0],
            source.rotation[1],
            source.rotation[2],
            source.rotation[3],
            source.scale[0],
            source.scale[1],
            source.scale[2],
            source.radius,
            source.segments,
            source.rings,
        });
    }
    for (doc.recipe.modifiers) |modifier| {
        switch (modifier.data) {
            .bend => |bend| try writer.print("    modifier id=\"{s}\" source=\"{s}\" kind=bend axis={s} amount={d}\n", .{ modifier.id, modifier.source_id, axisName(bend.axis), bend.amount }),
            .taper => |taper| try writer.print("    modifier id=\"{s}\" source=\"{s}\" kind=taper axis={s} amount={d}\n", .{ modifier.id, modifier.source_id, axisName(taper.axis), taper.amount }),
            .lattice => |lattice| {
                try writer.print("    modifier id=\"{s}\" source=\"{s}\" kind=lattice dimensions=\"{d},{d},{d}\" points=\"", .{ modifier.id, modifier.source_id, lattice.dimensions[0], lattice.dimensions[1], lattice.dimensions[2] });
                for (lattice.points, 0..) |point, idx| {
                    if (idx != 0) try writer.writeAll(";");
                    try writer.print("{d},{d},{d}:{d},{d},{d}", .{ point.index[0], point.index[1], point.index[2], point.offset[0], point.offset[1], point.offset[2] });
                }
                try writer.writeAll("\"\n");
            },
        }
    }
    for (doc.recipe.shape_intents) |intent| {
        try writer.print("    shape id=\"{s}\" source={s} operation={s} amount={d} segments={d}", .{
            intent.id,
            shapeSourceKindName(intent.source_kind),
            shapeOperationKindName(intent.operation_kind),
            intent.amount,
            intent.segments,
        });
        if (intent.source_kind == .primitive_seed) {
            try writer.print(" primitive={s} width={d} height={d} depth={d} radius={d}", .{
                primitiveKindName(intent.primitive_kind),
                intent.primitive_params.width,
                intent.primitive_params.height,
                intent.primitive_params.depth,
                intent.primitive_params.radius,
            });
        }
        try writer.writeAll(" points=\"");
        for (intent.points, 0..) |point, idx| {
            if (idx != 0) try writer.writeAll(";");
            try writer.print("{d},{d},{d}", .{ point.x, point.y, point.z });
        }
        try writer.writeAll("\"\n");
    }
    try writer.writeAll("  }\n");
    try writer.print("  mesh asset=\"{s}\"\n", .{doc.mesh_path});
    try writer.print("  material base_color=\"{d},{d},{d},{d}\"", .{ doc.base_color.r, doc.base_color.g, doc.base_color.b, doc.base_color.a });
    if (doc.material_path) |path| try writer.print(" path=\"{s}\"", .{path});
    if (doc.texture_path) |path| try writer.print(" texture=\"{s}\"", .{path});
    try writer.writeAll("\n");
    for (doc.face_materials) |face| {
        try writer.print(
            "  face index={d} material=\"{s}\" scale_world={d} rotation_deg={d} offset_u={d} offset_v={d}\n",
            .{ face.face_index, face.material_path, face.transform.scale_world, face.transform.rotation_deg, face.transform.offset_u, face.transform.offset_v },
        );
    }
    try writer.print("  variants count={d}\n", .{doc.variant_count});
    try writer.writeAll("}\n");
    return out.toOwnedSlice();
}

pub fn sourceKindName(kind: SourceKind) []const u8 {
    return switch (kind) {
        .sphere => "sphere",
    };
}

pub fn sourceKindFromName(name: []const u8) ?SourceKind {
    if (std.mem.eql(u8, name, "sphere")) return .sphere;
    return null;
}

pub fn shapeSourceKindName(kind: ShapeSourceKind) []const u8 {
    return switch (kind) {
        .closed_face => "closed_face",
        .open_profile => "open_profile",
        .path => "path",
        .primitive_seed => "primitive_seed",
        .existing_mesh => "existing_mesh",
    };
}

pub fn shapeSourceKindFromName(name: []const u8) ?ShapeSourceKind {
    inline for (std.meta.fields(ShapeSourceKind)) |field| {
        if (std.mem.eql(u8, name, field.name)) return @enumFromInt(field.value);
    }
    return null;
}

pub fn shapeOperationKindName(kind: ShapeOperationKind) []const u8 {
    return switch (kind) {
        .extrude => "extrude",
        .solidify => "solidify",
        .revolve => "revolve",
        .cut => "cut",
        .inset => "inset",
        .bevel => "bevel",
        .mirror => "mirror",
        .array => "array",
    };
}

pub fn shapeOperationKindFromName(name: []const u8) ?ShapeOperationKind {
    inline for (std.meta.fields(ShapeOperationKind)) |field| {
        if (std.mem.eql(u8, name, field.name)) return @enumFromInt(field.value);
    }
    return null;
}

pub fn primitiveKindName(kind: geometry.PrimitiveKind) []const u8 {
    return switch (kind) {
        .box => "box",
        .plane => "plane",
        .cylinder => "cylinder",
        .sphere => "sphere",
    };
}

pub fn primitiveKindFromName(name: []const u8) ?geometry.PrimitiveKind {
    if (std.mem.eql(u8, name, "box")) return .box;
    if (std.mem.eql(u8, name, "plane")) return .plane;
    if (std.mem.eql(u8, name, "cylinder")) return .cylinder;
    if (std.mem.eql(u8, name, "sphere")) return .sphere;
    return null;
}

pub fn modifierKindFromName(name: []const u8) ?ModifierKind {
    if (std.mem.eql(u8, name, "bend")) return .bend;
    if (std.mem.eql(u8, name, "taper")) return .taper;
    if (std.mem.eql(u8, name, "lattice")) return .lattice;
    return null;
}

pub fn axisName(axis: Axis) []const u8 {
    return switch (axis) {
        .x => "x",
        .y => "y",
        .z => "z",
    };
}

pub fn axisFromName(name: []const u8) ?Axis {
    if (std.mem.eql(u8, name, "x")) return .x;
    if (std.mem.eql(u8, name, "y")) return .y;
    if (std.mem.eql(u8, name, "z")) return .z;
    return null;
}

fn parseFloatQuad(text: []const u8) ![4]f32 {
    var parts: [4]f32 = undefined;
    var iter = std.mem.splitScalar(u8, text, ',');
    var i: usize = 0;
    while (iter.next()) |part| {
        if (i >= 4) return error.InvalidValue;
        parts[i] = try std.fmt.parseFloat(f32, std.mem.trim(u8, part, " \t"));
        i += 1;
    }
    if (i != 4) return error.InvalidValue;
    return parts;
}

fn parseU32Triple(text: []const u8) ![3]u32 {
    var parts: [3]u32 = undefined;
    var iter = std.mem.splitScalar(u8, text, ',');
    var i: usize = 0;
    while (iter.next()) |part| {
        if (i >= 3) return error.InvalidValue;
        parts[i] = try std.fmt.parseInt(u32, std.mem.trim(u8, part, " \t"), 10);
        i += 1;
    }
    if (i != 3) return error.InvalidValue;
    return parts;
}

fn parseLatticePoints(allocator: std.mem.Allocator, text: []const u8) ![]LatticePoint {
    var points: std.ArrayList(LatticePoint) = .empty;
    defer points.deinit(allocator);
    if (text.len == 0) return try points.toOwnedSlice(allocator);
    var point_iter = std.mem.splitScalar(u8, text, ';');
    while (point_iter.next()) |raw_point| {
        const trimmed = std.mem.trim(u8, raw_point, " \t\r\n");
        if (trimmed.len == 0) return error.InvalidValue;
        const split = std.mem.indexOfScalar(u8, trimmed, ':') orelse return error.InvalidValue;
        try points.append(allocator, .{
            .index = try parseU32Triple(trimmed[0..split]),
            .offset = try scene_kdl_values.parseFloatTriple(trimmed[split + 1 ..]),
        });
    }
    return try points.toOwnedSlice(allocator);
}

fn parseShapePoints(allocator: std.mem.Allocator, text: []const u8) ![]editor_math.Vec3 {
    var points: std.ArrayList(editor_math.Vec3) = .empty;
    defer points.deinit(allocator);
    if (text.len == 0) return try points.toOwnedSlice(allocator);
    var point_iter = std.mem.splitScalar(u8, text, ';');
    while (point_iter.next()) |raw_point| {
        const trimmed = std.mem.trim(u8, raw_point, " \t\r\n");
        if (trimmed.len == 0) return error.InvalidValue;
        const parsed = try scene_kdl_values.parseFloatTriple(trimmed);
        try points.append(allocator, .{ .x = parsed[0], .y = parsed[1], .z = parsed[2] });
    }
    return try points.toOwnedSlice(allocator);
}

fn validateSource(source: Source) !void {
    if (source.id.len == 0) return error.InvalidPropAssetDocument;
    if (source.radius <= 0 or source.segments == 0 or source.rings == 0) return error.InvalidPropAssetDocument;
    if (source.scale[0] <= 0 or source.scale[1] <= 0 or source.scale[2] <= 0) return error.InvalidPropAssetDocument;
    const len = @sqrt(source.rotation[0] * source.rotation[0] + source.rotation[1] * source.rotation[1] + source.rotation[2] * source.rotation[2] + source.rotation[3] * source.rotation[3]);
    if (len <= std.math.floatEps(f32)) return error.InvalidPropAssetDocument;
}

fn validateModifier(modifier: Modifier) !void {
    if (modifier.id.len == 0 or modifier.source_id.len == 0) return error.InvalidPropAssetDocument;
    switch (modifier.data) {
        .lattice => |lattice| {
            if (lattice.dimensions[0] < 2 or lattice.dimensions[1] < 2 or lattice.dimensions[2] < 2) return error.InvalidPropAssetDocument;
            for (lattice.points) |point| {
                if (point.index[0] >= lattice.dimensions[0] or point.index[1] >= lattice.dimensions[1] or point.index[2] >= lattice.dimensions[2]) return error.InvalidPropAssetDocument;
            }
        },
        else => {},
    }
}

fn validateShapeIntent(intent: ShapeIntent) !void {
    if (intent.id.len == 0) return error.InvalidPropAssetDocument;
    if (!std.math.isFinite(intent.amount) or intent.amount <= 0) return error.InvalidPropAssetDocument;
    switch (intent.source_kind) {
        .closed_face => if (intent.points.len < 3) return error.InvalidPropAssetDocument,
        .open_profile, .path => if (intent.points.len < 2) return error.InvalidPropAssetDocument,
        .primitive_seed => try validatePrimitiveIntent(intent.primitive_kind, intent.primitive_params),
        .existing_mesh => {},
    }
    switch (intent.operation_kind) {
        .revolve => if (intent.segments < 3) return error.InvalidPropAssetDocument,
        .array => if (intent.segments < 2) return error.InvalidPropAssetDocument,
        else => {},
    }
    for (intent.points) |point| {
        if (!std.math.isFinite(point.x) or !std.math.isFinite(point.y) or !std.math.isFinite(point.z)) return error.InvalidPropAssetDocument;
    }
}

fn validatePrimitiveIntent(kind: geometry.PrimitiveKind, params: geometry.PrimitiveParams) !void {
    if (!std.math.isFinite(params.width) or !std.math.isFinite(params.height) or !std.math.isFinite(params.depth) or !std.math.isFinite(params.radius)) return error.InvalidPropAssetDocument;
    switch (kind) {
        .box => if (params.width <= 0 or params.height <= 0 or params.depth <= 0) return error.InvalidPropAssetDocument,
        .plane => if (params.width <= 0 or params.depth <= 0) return error.InvalidPropAssetDocument,
        .cylinder => if (params.radius <= 0 or params.height <= 0 or params.segments < 3) return error.InvalidPropAssetDocument,
        .sphere => if (params.radius <= 0 or params.segments < 3) return error.InvalidPropAssetDocument,
    }
}

test "prop asset document round trip" {
    var doc = PropAssetDocument{
        .id = try std.testing.allocator.dupe(u8, "crate_wood"),
        .label = try std.testing.allocator.dupe(u8, "Crate Wood"),
        .tags = try std.testing.allocator.dupe(u8, "box, panel"),
        .deleted = true,
        .mesh_path = try std.testing.allocator.dupe(u8, "props/meshes/crate_wood.fmesh"),
        .recipe = .{
            .sources = try std.testing.allocator.dupe(Source, &.{
                .{
                    .id = try std.testing.allocator.dupe(u8, "pad"),
                    .kind = .sphere,
                    .position = .{ 0, 0.8, 0 },
                    .rotation = .{ 0, 0, 0, 1 },
                    .scale = .{ 0.4, 0.8, 0.12 },
                    .radius = 1,
                    .segments = 12,
                    .rings = 8,
                },
            }),
            .modifiers = try std.testing.allocator.dupe(Modifier, &.{
                .{
                    .id = try std.testing.allocator.dupe(u8, "pad_bend"),
                    .source_id = try std.testing.allocator.dupe(u8, "pad"),
                    .kind = .bend,
                    .data = .{ .bend = .{ .axis = .x, .amount = 0.12 } },
                },
            }),
            .shape_intents = try std.testing.allocator.dupe(ShapeIntent, &.{
                .{
                    .id = try std.testing.allocator.dupe(u8, "shape_1"),
                    .source_kind = .closed_face,
                    .operation_kind = .cut,
                    .amount = 0.35,
                    .segments = 24,
                    .points = try std.testing.allocator.dupe(editor_math.Vec3, &.{
                        .{ .x = -1, .y = 0, .z = -1 },
                        .{ .x = 1, .y = 0, .z = -1 },
                        .{ .x = 1, .y = 0, .z = 1 },
                    }),
                },
            }),
        },
        .base_color = .{ .r = 165, .g = 130, .b = 85, .a = 255 },
        .material_path = try std.testing.allocator.dupe(u8, "materials/editor/slate.checker"),
        .texture_path = try std.testing.allocator.dupe(u8, "props/textures/crate_wood.rgba"),
        .face_materials = try std.testing.allocator.dupe(scene_texture.FaceMaterial, &.{
            .{
                .face_index = 4,
                .material_path = try std.testing.allocator.dupe(u8, "materials/editor/red.checker"),
                .transform = .{ .scale_world = 2.0, .rotation_deg = 15.0, .offset_u = 0.25 },
            },
        }),
        .variant_count = 3,
    };
    defer doc.deinit(std.testing.allocator);

    const bytes = try format(std.testing.allocator, doc);
    defer std.testing.allocator.free(bytes);
    var parsed = try parse(std.testing.allocator, bytes);
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("crate_wood", parsed.id);
    try std.testing.expectEqualStrings("box, panel", parsed.tags);
    try std.testing.expect(parsed.deleted);
    try std.testing.expectEqualStrings("props/meshes/crate_wood.fmesh", parsed.mesh_path);
    try std.testing.expectEqualStrings("materials/editor/slate.checker", parsed.material_path.?);
    try std.testing.expectEqualStrings("props/textures/crate_wood.rgba", parsed.texture_path.?);
    try std.testing.expectEqual(@as(usize, 1), parsed.face_materials.len);
    try std.testing.expectEqual(@as(usize, 4), parsed.face_materials[0].face_index);
    try std.testing.expectEqualStrings("materials/editor/red.checker", parsed.face_materials[0].material_path);
    try std.testing.expectApproxEqAbs(@as(f32, 15.0), parsed.face_materials[0].transform.rotation_deg, 0.001);
    try std.testing.expectEqual(@as(usize, 1), parsed.recipe.sources.len);
    try std.testing.expectEqualStrings("pad", parsed.recipe.sources[0].id);
    try std.testing.expectApproxEqAbs(@as(f32, 0.4), parsed.recipe.sources[0].scale[0], 0.001);
    try std.testing.expectEqual(@as(usize, 1), parsed.recipe.modifiers.len);
    try std.testing.expectEqual(ModifierKind.bend, parsed.recipe.modifiers[0].kind);
    try std.testing.expectEqual(@as(usize, 1), parsed.recipe.shape_intents.len);
    try std.testing.expectEqual(ShapeOperationKind.cut, parsed.recipe.shape_intents[0].operation_kind);
    try std.testing.expectApproxEqAbs(@as(f32, 1), parsed.recipe.shape_intents[0].points[1].x, 0.001);
    try std.testing.expectEqual(@as(u32, 3), parsed.variant_count);
}

test "prop asset document with empty tags survives repeated round trips" {
    var doc = PropAssetDocument{
        .id = try std.testing.allocator.dupe(u8, "crate_wood"),
        .label = try std.testing.allocator.dupe(u8, "Crate Wood"),
        .tags = try std.testing.allocator.dupe(u8, ""),
        .deleted = false,
        .mesh_path = try std.testing.allocator.dupe(u8, "props/meshes/crate_wood.fmesh"),
        .recipe = .{},
        .base_color = .{ .r = 165, .g = 130, .b = 85, .a = 255 },
        .variant_count = 1,
    };
    defer doc.deinit(std.testing.allocator);

    // Simulate the load -> modify -> save round trip that happens when adding
    // a recipe source to a prop asset with empty tags.
    var bytes = try format(std.testing.allocator, doc);
    var parsed = try parse(std.testing.allocator, bytes);
    std.testing.allocator.free(bytes);
    try std.testing.expectEqualStrings("", parsed.tags);

    bytes = try format(std.testing.allocator, parsed);
    parsed.deinit(std.testing.allocator);
    parsed = try parse(std.testing.allocator, bytes);
    std.testing.allocator.free(bytes);
    try std.testing.expectEqualStrings("", parsed.tags);

    defer parsed.deinit(std.testing.allocator);
}

test "prop asset document rejects legacy one-line recipe" {
    const legacy =
        \\prop_asset version=1 id="old" label="Old" {
        \\  recipe base=box width=1 height=1 depth=1
        \\  mesh asset="props/meshes/old.fmesh"
        \\  material base_color="255,255,255,255"
        \\  variants count=1
        \\}
    ;
    try std.testing.expectError(error.InvalidPropAssetDocument, parse(std.testing.allocator, legacy));
}

test "primitive seed shape intent round trips primitive metadata" {
    const source =
        \\prop_asset version=1 id="seed_panel" label="Seed Panel" tags="shape" deleted=false {
        \\  recipe {
        \\    shape id="shape_1" source=primitive_seed operation=extrude amount=1 segments=12 primitive=cylinder width=1 height=2 depth=1 radius=0.35 points=""
        \\  }
        \\  mesh asset="props/meshes/seed_panel.fmesh"
        \\  material base_color="255,255,255,255"
        \\  variants count=1
        \\}
        \\
    ;
    var parsed = try parse(std.testing.allocator, source);
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), parsed.recipe.shape_intents.len);
    const intent = parsed.recipe.shape_intents[0];
    try std.testing.expectEqual(ShapeSourceKind.primitive_seed, intent.source_kind);
    try std.testing.expectEqual(geometry.PrimitiveKind.cylinder, intent.primitive_kind);
    try std.testing.expectApproxEqAbs(@as(f32, 0.35), intent.primitive_params.radius, 0.001);
    try std.testing.expectEqual(@as(u32, 12), intent.primitive_params.segments);

    const encoded = try format(std.testing.allocator, parsed);
    defer std.testing.allocator.free(encoded);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "source=primitive_seed") != null);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "primitive=cylinder") != null);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "radius=0.35") != null);
}

test "existing mesh shape operation round trips without source points" {
    const source =
        \\prop_asset version=1 id="array_panel" label="Array Panel" tags="shape" deleted=false {
        \\  recipe {
        \\    shape id="shape_1" source=existing_mesh operation=array amount=1.25 segments=2 points=""
        \\  }
        \\  mesh asset="props/meshes/array_panel.fmesh"
        \\  material base_color="255,255,255,255"
        \\  variants count=1
        \\}
        \\
    ;
    var parsed = try parse(std.testing.allocator, source);
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), parsed.recipe.shape_intents.len);
    try std.testing.expectEqual(ShapeSourceKind.existing_mesh, parsed.recipe.shape_intents[0].source_kind);
    try std.testing.expectEqual(ShapeOperationKind.array, parsed.recipe.shape_intents[0].operation_kind);
    try std.testing.expectEqual(@as(usize, 0), parsed.recipe.shape_intents[0].points.len);

    const encoded = try format(std.testing.allocator, parsed);
    defer std.testing.allocator.free(encoded);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "source=existing_mesh") != null);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "operation=array") != null);
}

test "primitive seed shape intent rejects invalid primitive metadata" {
    const source =
        \\prop_asset version=1 id="bad_seed" label="Bad Seed" tags="shape" deleted=false {
        \\  recipe {
        \\    shape id="shape_1" source=primitive_seed operation=extrude amount=1 segments=12 primitive=sphere radius=0 points=""
        \\  }
        \\  mesh asset="props/meshes/bad_seed.fmesh"
        \\  material base_color="255,255,255,255"
        \\  variants count=1
        \\}
        \\
    ;
    try std.testing.expectError(error.InvalidPropAssetDocument, parse(std.testing.allocator, source));
}
