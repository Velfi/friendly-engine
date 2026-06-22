//! First-class semantic model for procedural buildings.
//!
//! A building is authored as semantic data — a plan of vertices and walls, the
//! openings cut into those walls, freestanding features, and an optional roof.
//! This data is the source of truth; the render mesh is a disposable output
//! regenerated from it (see `project_editor_blockout.zig`).
//!
//! The model is serialized as the string `components` carried by the building's
//! scene object, so it round-trips through the existing scene save format with
//! no separate schema. The codec lives here so parsing and formatting stay in
//! one place instead of being duplicated across every edit operation.

const std = @import("std");
const editor_math = @import("editor_math.zig");

const Vec3 = editor_math.Vec3;

pub const building_marker = "architecture:building";

const vertex_prefix = "arch.vertex:";
const wall_prefix = "arch.wall:";
const opening_prefix = "arch.opening:";
const feature_prefix = "arch.feature:";
const roof_prefix = "arch.roof:";
const floors_prefix = "arch.floors:";
const shell_prefix = "arch.shell:";
const foundation_prefix = "arch.foundation:";
const cutout_prefix = "arch.cutout:";

pub fn isSerializedBuildingComponent(component: []const u8) bool {
    return std.mem.eql(u8, component, building_marker) or
        std.mem.startsWith(u8, component, vertex_prefix) or
        std.mem.startsWith(u8, component, wall_prefix) or
        std.mem.startsWith(u8, component, opening_prefix) or
        std.mem.startsWith(u8, component, feature_prefix) or
        std.mem.startsWith(u8, component, roof_prefix) or
        std.mem.startsWith(u8, component, floors_prefix) or
        std.mem.startsWith(u8, component, shell_prefix) or
        std.mem.startsWith(u8, component, foundation_prefix) or
        std.mem.startsWith(u8, component, cutout_prefix);
}

pub const eps: f32 = 0.001;

pub const OpeningKind = enum {
    door,
    window,
    arch_opening,
    cutout,

    pub fn token(self: OpeningKind) []const u8 {
        return switch (self) {
            .door => "door",
            .window => "window",
            .arch_opening => "arch",
            .cutout => "cutout",
        };
    }

    pub fn parse(token_str: []const u8) !OpeningKind {
        if (std.mem.eql(u8, token_str, "door")) return .door;
        if (std.mem.eql(u8, token_str, "window")) return .window;
        if (std.mem.eql(u8, token_str, "arch")) return .arch_opening;
        if (std.mem.eql(u8, token_str, "cutout")) return .cutout;
        return error.InvalidOpeningKind;
    }

    pub fn label(self: OpeningKind) []const u8 {
        return switch (self) {
            .door => "Door",
            .window => "Window",
            .arch_opening => "Arch",
            .cutout => "Cutout",
        };
    }
};

pub const FeatureKind = enum {
    column,
    beam,
    stair,
    spiral_stair,
    bartizan,
    arch,

    pub fn token(self: FeatureKind) []const u8 {
        return @tagName(self);
    }

    pub fn parse(token_str: []const u8) !FeatureKind {
        return std.meta.stringToEnum(FeatureKind, token_str) orelse error.InvalidFeatureKind;
    }

    pub fn label(self: FeatureKind) []const u8 {
        return switch (self) {
            .column => "Column",
            .beam => "Beam",
            .stair => "Stair",
            .spiral_stair => "Spiral Stair",
            .bartizan => "Bartizan",
            .arch => "Arch",
        };
    }
};

pub const RoofKind = enum {
    flat,
    shed,
    gable,
    conical,

    pub fn token(self: RoofKind) []const u8 {
        return @tagName(self);
    }

    pub fn parse(token_str: []const u8) !RoofKind {
        return std.meta.stringToEnum(RoofKind, token_str) orelse error.InvalidRoofKind;
    }

    pub fn label(self: RoofKind) []const u8 {
        return switch (self) {
            .flat => "Flat",
            .shed => "Shed",
            .gable => "Gable",
            .conical => "Conical",
        };
    }
};

pub const Floors = struct {
    count: u32 = 1,
    height: f32 = 3.0,
    slab_thickness: f32 = 0.12,
};

pub const WallHeightMode = enum {
    explicit,
    to_floor,

    pub fn token(self: WallHeightMode) []const u8 {
        return @tagName(self);
    }

    pub fn parse(token_str: []const u8) !WallHeightMode {
        return std.meta.stringToEnum(WallHeightMode, token_str) orelse error.InvalidWallHeightMode;
    }
};

/// Ground-plane plan vertex. `y` is always 0; buildings are extruded upward.
pub const PlanVertex = struct {
    id: u32,
    x: f32,
    z: f32,

    pub fn point(self: PlanVertex) Vec3 {
        return .{ .x = self.x, .y = 0, .z = self.z };
    }
};

/// Wall centerline from vertex `a` to vertex `b`, extruded to `height` with
/// the given `thickness` straddling the centerline.
pub const WallEdge = struct {
    id: u32,
    a: u32,
    b: u32,
    height: f32,
    thickness: f32,
    height_mode: WallHeightMode = .explicit,
    floor_index: u32 = 1,
};

/// Opening attached to a wall. `t` is the normalized center position along the
/// wall (0..1). `width`/`height`/`sill` are in meters.
pub const WallOpening = struct {
    id: u32,
    wall_id: u32,
    kind: OpeningKind,
    t: f32,
    width: f32,
    height: f32,
    sill: f32,
};

/// Freestanding parametric feature placed on the ground plane.
pub const Feature = struct {
    id: u32,
    kind: FeatureKind,
    x: f32,
    z: f32,
    height: f32,
    width: f32,
    depth: f32 = 0.25,
    dir_x: f32 = 1.0,
    dir_z: f32 = 0.0,
    steps: u32 = 8,
};

pub const Roof = struct {
    kind: RoofKind,
    pitch: f32 = 0.5,
    overhang: f32 = 0.15,
};

pub const Shell = struct {
    id: u32,
    walls: std.ArrayList(u32) = .empty,

    pub fn deinit(self: *Shell, allocator: std.mem.Allocator) void {
        self.walls.deinit(allocator);
    }
};

pub const Foundation = struct {
    id: u32,
    min_x: f32,
    min_z: f32,
    max_x: f32,
    max_z: f32,
    top_y: f32,
    clearance: f32 = 0.05,
    grid_step: f32 = 1.0,
};

pub const TerrainCutout = struct {
    id: u32,
    min_x: f32,
    min_y: f32,
    min_z: f32,
    max_x: f32,
    max_y: f32,
    max_z: f32,
};

/// Owned, mutable building. Construct with `parse`, edit the lists in place,
/// then `serialize` back to components. Always `deinit` it.
pub const Building = struct {
    vertices: std.ArrayList(PlanVertex) = .empty,
    walls: std.ArrayList(WallEdge) = .empty,
    openings: std.ArrayList(WallOpening) = .empty,
    features: std.ArrayList(Feature) = .empty,
    shells: std.ArrayList(Shell) = .empty,
    foundations: std.ArrayList(Foundation) = .empty,
    cutouts: std.ArrayList(TerrainCutout) = .empty,
    floors: Floors = .{},
    roof: ?Roof = null,

    pub fn deinit(self: *Building, allocator: std.mem.Allocator) void {
        for (self.shells.items) |*shell| shell.deinit(allocator);
        self.vertices.deinit(allocator);
        self.walls.deinit(allocator);
        self.openings.deinit(allocator);
        self.features.deinit(allocator);
        self.shells.deinit(allocator);
        self.foundations.deinit(allocator);
        self.cutouts.deinit(allocator);
    }

    pub fn isBuildingComponents(components: []const []const u8) bool {
        for (components) |component| {
            if (std.mem.eql(u8, component, building_marker)) return true;
        }
        return false;
    }

    /// Rebuild the model from a scene object's components. Fails loudly on a
    /// malformed building rather than silently dropping data.
    pub fn parse(allocator: std.mem.Allocator, components: []const []const u8) !Building {
        var self = Building{};
        errdefer self.deinit(allocator);
        var seen_marker = false;
        for (components) |component| {
            if (std.mem.eql(u8, component, building_marker)) {
                seen_marker = true;
            } else if (std.mem.startsWith(u8, component, vertex_prefix)) {
                try self.vertices.append(allocator, try parseVertex(component[vertex_prefix.len..]));
            } else if (std.mem.startsWith(u8, component, wall_prefix)) {
                try self.walls.append(allocator, try parseWall(component[wall_prefix.len..]));
            } else if (std.mem.startsWith(u8, component, opening_prefix)) {
                try self.openings.append(allocator, try parseOpening(component[opening_prefix.len..]));
            } else if (std.mem.startsWith(u8, component, feature_prefix)) {
                try self.features.append(allocator, try parseFeature(component[feature_prefix.len..]));
            } else if (std.mem.startsWith(u8, component, floors_prefix)) {
                self.floors = try parseFloors(component[floors_prefix.len..]);
            } else if (std.mem.startsWith(u8, component, roof_prefix)) {
                self.roof = try parseRoof(component[roof_prefix.len..]);
            } else if (std.mem.startsWith(u8, component, shell_prefix)) {
                try self.shells.append(allocator, try parseShell(allocator, component[shell_prefix.len..]));
            } else if (std.mem.startsWith(u8, component, foundation_prefix)) {
                try self.foundations.append(allocator, try parseFoundation(component[foundation_prefix.len..]));
            } else if (std.mem.startsWith(u8, component, cutout_prefix)) {
                try self.cutouts.append(allocator, try parseCutout(component[cutout_prefix.len..]));
            }
        }
        if (!seen_marker) {
            return error.InvalidBuilding;
        }
        return self;
    }

    /// Serialize to freshly-allocated component strings. Caller owns the slice
    /// and every string in it. Wall order is preserved so the closed-footprint
    /// solver keeps a consistent traversal.
    pub fn serialize(self: *const Building, allocator: std.mem.Allocator) ![][]u8 {
        var out: std.ArrayList([]u8) = .empty;
        errdefer {
            for (out.items) |s| allocator.free(s);
            out.deinit(allocator);
        }
        try out.append(allocator, try allocator.dupe(u8, building_marker));
        for (self.vertices.items) |v| {
            try out.append(allocator, try std.fmt.allocPrint(allocator, vertex_prefix ++ "{d}|{d}|{d}", .{ v.id, v.x, v.z }));
        }
        for (self.walls.items) |w| {
            try out.append(allocator, try std.fmt.allocPrint(allocator, wall_prefix ++ "{d}|{d}|{d}|{d}|{d}|{s}|{d}", .{ w.id, w.a, w.b, w.height, w.thickness, w.height_mode.token(), w.floor_index }));
        }
        for (self.openings.items) |o| {
            try out.append(allocator, try std.fmt.allocPrint(allocator, opening_prefix ++ "{d}|{d}|{s}|{d}|{d}|{d}|{d}", .{ o.id, o.wall_id, o.kind.token(), o.t, o.width, o.height, o.sill }));
        }
        for (self.features.items) |f| {
            try out.append(allocator, try std.fmt.allocPrint(allocator, feature_prefix ++ "{d}|{s}|{d}|{d}|{d}|{d}|{d}|{d}|{d}|{d}", .{ f.id, f.kind.token(), f.x, f.z, f.height, f.width, f.depth, f.dir_x, f.dir_z, f.steps }));
        }
        try out.append(allocator, try std.fmt.allocPrint(allocator, floors_prefix ++ "{d}|{d}|{d}", .{ self.floors.count, self.floors.height, self.floors.slab_thickness }));
        if (self.roof) |r| {
            try out.append(allocator, try std.fmt.allocPrint(allocator, roof_prefix ++ "{s}|{d}|{d}", .{ r.kind.token(), r.pitch, r.overhang }));
        }
        for (self.shells.items) |shell| {
            var walls_buf: std.ArrayList(u8) = .empty;
            defer walls_buf.deinit(allocator);
            for (shell.walls.items, 0..) |wall_id, idx| {
                if (idx > 0) try walls_buf.append(allocator, ',');
                const wall_text = try std.fmt.allocPrint(allocator, "{d}", .{wall_id});
                defer allocator.free(wall_text);
                try walls_buf.appendSlice(allocator, wall_text);
            }
            try out.append(allocator, try std.fmt.allocPrint(allocator, shell_prefix ++ "{d}|{s}", .{ shell.id, walls_buf.items }));
        }
        for (self.foundations.items) |foundation| {
            try out.append(allocator, try std.fmt.allocPrint(allocator, foundation_prefix ++ "{d}|{d}|{d}|{d}|{d}|{d}|{d}|{d}", .{
                foundation.id,
                foundation.min_x,
                foundation.min_z,
                foundation.max_x,
                foundation.max_z,
                foundation.top_y,
                foundation.clearance,
                foundation.grid_step,
            }));
        }
        for (self.cutouts.items) |cutout| {
            try out.append(allocator, try std.fmt.allocPrint(allocator, cutout_prefix ++ "{d}|{d}|{d}|{d}|{d}|{d}|{d}", .{
                cutout.id,
                cutout.min_x,
                cutout.min_y,
                cutout.min_z,
                cutout.max_x,
                cutout.max_y,
                cutout.max_z,
            }));
        }
        return out.toOwnedSlice(allocator);
    }

    pub fn findVertex(self: *const Building, id: u32) ?PlanVertex {
        for (self.vertices.items) |v| {
            if (v.id == id) return v;
        }
        return null;
    }

    pub fn vertexPtr(self: *Building, id: u32) ?*PlanVertex {
        for (self.vertices.items) |*v| {
            if (v.id == id) return v;
        }
        return null;
    }

    pub fn wallPtr(self: *Building, id: u32) ?*WallEdge {
        for (self.walls.items) |*w| {
            if (w.id == id) return w;
        }
        return null;
    }

    pub fn wallPtrConst(self: *const Building, id: u32) ?WallEdge {
        for (self.walls.items) |w| {
            if (w.id == id) return w;
        }
        return null;
    }

    pub fn shellPtr(self: *Building, id: u32) ?*Shell {
        for (self.shells.items) |*shell| {
            if (shell.id == id) return shell;
        }
        return null;
    }

    pub fn foundationPtr(self: *Building, id: u32) ?*Foundation {
        for (self.foundations.items) |*foundation| {
            if (foundation.id == id) return foundation;
        }
        return null;
    }

    pub fn cutoutPtr(self: *Building, id: u32) ?*TerrainCutout {
        for (self.cutouts.items) |*cutout| {
            if (cutout.id == id) return cutout;
        }
        return null;
    }

    pub fn openingPtr(self: *Building, id: u32) ?*WallOpening {
        for (self.openings.items) |*o| {
            if (o.id == id) return o;
        }
        return null;
    }

    pub fn featurePtr(self: *Building, id: u32) ?*Feature {
        for (self.features.items) |*f| {
            if (f.id == id) return f;
        }
        return null;
    }

    pub fn removeOpening(self: *Building, id: u32) bool {
        for (self.openings.items, 0..) |o, idx| {
            if (o.id == id) {
                _ = self.openings.orderedRemove(idx);
                return true;
            }
        }
        return false;
    }

    pub fn removeFeature(self: *Building, id: u32) bool {
        for (self.features.items, 0..) |f, idx| {
            if (f.id == id) {
                _ = self.features.orderedRemove(idx);
                return true;
            }
        }
        return false;
    }

    pub fn removeWallCascade(self: *Building, allocator: std.mem.Allocator, id: u32) struct { removed_wall: bool, removed_openings: u32, removed_shells: u32 } {
        var removed_wall = false;
        for (self.walls.items, 0..) |w, idx| {
            if (w.id == id) {
                _ = self.walls.orderedRemove(idx);
                removed_wall = true;
                break;
            }
        }
        if (!removed_wall) return .{ .removed_wall = false, .removed_openings = 0, .removed_shells = 0 };

        var removed_openings: u32 = 0;
        var opening_idx: usize = 0;
        while (opening_idx < self.openings.items.len) {
            if (self.openings.items[opening_idx].wall_id == id) {
                _ = self.openings.orderedRemove(opening_idx);
                removed_openings += 1;
            } else {
                opening_idx += 1;
            }
        }

        var removed_shells: u32 = 0;
        var shell_idx: usize = 0;
        while (shell_idx < self.shells.items.len) {
            if (shellContainsWall(&self.shells.items[shell_idx], id)) {
                self.shells.items[shell_idx].deinit(allocator);
                _ = self.shells.orderedRemove(shell_idx);
                removed_shells += 1;
            } else {
                shell_idx += 1;
            }
        }
        if (removed_shells > 0) self.roof = null;
        return .{ .removed_wall = true, .removed_openings = removed_openings, .removed_shells = removed_shells };
    }

    pub fn removeVertexCascade(self: *Building, allocator: std.mem.Allocator, id: u32) struct { removed_vertex: bool, removed_edges: u32, removed_openings: u32, removed_shells: u32 } {
        var removed_vertex = false;
        for (self.vertices.items, 0..) |v, idx| {
            if (v.id == id) {
                _ = self.vertices.orderedRemove(idx);
                removed_vertex = true;
                break;
            }
        }
        if (!removed_vertex) return .{ .removed_vertex = false, .removed_edges = 0, .removed_openings = 0, .removed_shells = 0 };

        var removed_edges: u32 = 0;
        var removed_openings: u32 = 0;
        var removed_shells: u32 = 0;
        var wall_idx: usize = 0;
        while (wall_idx < self.walls.items.len) {
            const wall = self.walls.items[wall_idx];
            if (wall.a == id or wall.b == id) {
                const removed = self.removeWallCascade(allocator, wall.id);
                if (removed.removed_wall) removed_edges += 1;
                removed_openings += removed.removed_openings;
                removed_shells += removed.removed_shells;
            } else {
                wall_idx += 1;
            }
        }
        return .{ .removed_vertex = true, .removed_edges = removed_edges, .removed_openings = removed_openings, .removed_shells = removed_shells };
    }

    pub fn removeShell(self: *Building, id: u32, allocator: std.mem.Allocator) bool {
        for (self.shells.items, 0..) |*shell, idx| {
            if (shell.id == id) {
                shell.deinit(allocator);
                _ = self.shells.orderedRemove(idx);
                if (self.shells.items.len == 0) self.roof = null;
                return true;
            }
        }
        return false;
    }

    pub fn removeFoundation(self: *Building, id: u32) bool {
        for (self.foundations.items, 0..) |foundation, idx| {
            if (foundation.id == id) {
                _ = self.foundations.orderedRemove(idx);
                return true;
            }
        }
        return false;
    }

    pub fn removeCutout(self: *Building, id: u32) bool {
        for (self.cutouts.items, 0..) |cutout, idx| {
            if (cutout.id == id) {
                _ = self.cutouts.orderedRemove(idx);
                return true;
            }
        }
        return false;
    }

    pub fn nextVertexId(self: *const Building) u32 {
        var next: u32 = 0;
        for (self.vertices.items) |v| next = @max(next, v.id + 1);
        return next;
    }

    pub fn nextWallId(self: *const Building) u32 {
        var next: u32 = 0;
        for (self.walls.items) |w| next = @max(next, w.id + 1);
        return next;
    }

    pub fn nextOpeningId(self: *const Building) u32 {
        var next: u32 = 0;
        for (self.openings.items) |o| next = @max(next, o.id + 1);
        return next;
    }

    pub fn nextFeatureId(self: *const Building) u32 {
        var next: u32 = 0;
        for (self.features.items) |f| next = @max(next, f.id + 1);
        return next;
    }

    pub fn nextShellId(self: *const Building) u32 {
        var next: u32 = 0;
        for (self.shells.items) |shell| next = @max(next, shell.id + 1);
        return next;
    }

    pub fn nextFoundationId(self: *const Building) u32 {
        var next: u32 = 0;
        for (self.foundations.items) |foundation| next = @max(next, foundation.id + 1);
        return next;
    }

    pub fn nextCutoutId(self: *const Building) u32 {
        var next: u32 = 0;
        for (self.cutouts.items) |cutout| next = @max(next, cutout.id + 1);
        return next;
    }

    /// Length of a wall in meters, or null if its endpoints are missing/degenerate.
    pub fn wallLength(self: *const Building, wall: WallEdge) ?f32 {
        const a = self.findVertex(wall.a) orelse return null;
        const b = self.findVertex(wall.b) orelse return null;
        const dx = b.x - a.x;
        const dz = b.z - a.z;
        const len = @sqrt(dx * dx + dz * dz);
        if (len <= eps) return null;
        return len;
    }

    pub fn maxWallHeight(self: *const Building) f32 {
        var height: f32 = 0;
        for (self.walls.items) |w| height = @max(height, w.height);
        if (self.floors.count > 0) {
            height = @max(height, @as(f32, @floatFromInt(self.floors.count)) * self.floors.height);
        }
        return height;
    }

    pub fn center(self: *const Building) Vec3 {
        if (self.vertices.items.len == 0) return .{ .x = 0, .y = 0, .z = 0 };
        var sum_x: f32 = 0;
        var sum_z: f32 = 0;
        for (self.vertices.items) |v| {
            sum_x += v.x;
            sum_z += v.z;
        }
        const n: f32 = @floatFromInt(self.vertices.items.len);
        return .{ .x = sum_x / n, .y = 0, .z = sum_z / n };
    }
};

fn shellContainsWall(shell: *const Shell, wall_id: u32) bool {
    for (shell.walls.items) |candidate| {
        if (candidate == wall_id) return true;
    }
    return false;
}

fn parseVertex(payload: []const u8) !PlanVertex {
    var parts = std.mem.splitScalar(u8, payload, '|');
    const id = try std.fmt.parseInt(u32, nextPart(&parts) orelse return error.InvalidVertex, 10);
    const x = try std.fmt.parseFloat(f32, nextPart(&parts) orelse return error.InvalidVertex);
    const z = try std.fmt.parseFloat(f32, nextPart(&parts) orelse return error.InvalidVertex);
    if (parts.next() != null) return error.InvalidVertex;
    return .{ .id = id, .x = x, .z = z };
}

fn parseWall(payload: []const u8) !WallEdge {
    var parts = std.mem.splitScalar(u8, payload, '|');
    const id = try std.fmt.parseInt(u32, nextPart(&parts) orelse return error.InvalidWall, 10);
    const a = try std.fmt.parseInt(u32, nextPart(&parts) orelse return error.InvalidWall, 10);
    const b = try std.fmt.parseInt(u32, nextPart(&parts) orelse return error.InvalidWall, 10);
    const height = try std.fmt.parseFloat(f32, nextPart(&parts) orelse return error.InvalidWall);
    const thickness = try std.fmt.parseFloat(f32, nextPart(&parts) orelse return error.InvalidWall);
    var height_mode: WallHeightMode = .explicit;
    var floor_index: u32 = 1;
    if (nextPart(&parts)) |raw| height_mode = try WallHeightMode.parse(raw);
    if (nextPart(&parts)) |raw| floor_index = try std.fmt.parseInt(u32, raw, 10);
    if (parts.next() != null) return error.InvalidWall;
    return .{ .id = id, .a = a, .b = b, .height = height, .thickness = thickness, .height_mode = height_mode, .floor_index = floor_index };
}

fn parseOpening(payload: []const u8) !WallOpening {
    var parts = std.mem.splitScalar(u8, payload, '|');
    const id = try std.fmt.parseInt(u32, nextPart(&parts) orelse return error.InvalidOpening, 10);
    const wall_id = try std.fmt.parseInt(u32, nextPart(&parts) orelse return error.InvalidOpening, 10);
    const kind = try OpeningKind.parse(nextPart(&parts) orelse return error.InvalidOpening);
    const t = try std.fmt.parseFloat(f32, nextPart(&parts) orelse return error.InvalidOpening);
    const width = try std.fmt.parseFloat(f32, nextPart(&parts) orelse return error.InvalidOpening);
    const height = try std.fmt.parseFloat(f32, nextPart(&parts) orelse return error.InvalidOpening);
    const sill = try std.fmt.parseFloat(f32, nextPart(&parts) orelse return error.InvalidOpening);
    if (parts.next() != null) return error.InvalidOpening;
    return .{ .id = id, .wall_id = wall_id, .kind = kind, .t = t, .width = width, .height = height, .sill = sill };
}

fn parseFeature(payload: []const u8) !Feature {
    var parts = std.mem.splitScalar(u8, payload, '|');
    const id = try std.fmt.parseInt(u32, nextPart(&parts) orelse return error.InvalidFeature, 10);
    const kind = try FeatureKind.parse(nextPart(&parts) orelse return error.InvalidFeature);
    var result = Feature{
        .id = id,
        .kind = kind,
        .x = try std.fmt.parseFloat(f32, nextPart(&parts) orelse return error.InvalidFeature),
        .z = try std.fmt.parseFloat(f32, nextPart(&parts) orelse return error.InvalidFeature),
        .height = try std.fmt.parseFloat(f32, nextPart(&parts) orelse return error.InvalidFeature),
        .width = try std.fmt.parseFloat(f32, nextPart(&parts) orelse return error.InvalidFeature),
    };
    if (nextPart(&parts)) |raw| result.depth = try std.fmt.parseFloat(f32, raw);
    if (nextPart(&parts)) |raw| result.dir_x = try std.fmt.parseFloat(f32, raw);
    if (nextPart(&parts)) |raw| result.dir_z = try std.fmt.parseFloat(f32, raw);
    if (nextPart(&parts)) |raw| result.steps = try std.fmt.parseInt(u32, raw, 10);
    if (parts.next() != null) return error.InvalidFeature;
    return result;
}

fn parseFloors(payload: []const u8) !Floors {
    var parts = std.mem.splitScalar(u8, payload, '|');
    const count = try std.fmt.parseInt(u32, nextPart(&parts) orelse return error.InvalidFloors, 10);
    const height = try std.fmt.parseFloat(f32, nextPart(&parts) orelse return error.InvalidFloors);
    var result = Floors{ .count = @max(1, count), .height = @max(0.25, height) };
    if (nextPart(&parts)) |raw| result.slab_thickness = @max(0.02, try std.fmt.parseFloat(f32, raw));
    if (parts.next() != null) return error.InvalidFloors;
    return result;
}

fn parseRoof(payload: []const u8) !Roof {
    var parts = std.mem.splitScalar(u8, payload, '|');
    const kind = try RoofKind.parse(nextPart(&parts) orelse return error.InvalidRoof);
    const pitch = try std.fmt.parseFloat(f32, nextPart(&parts) orelse return error.InvalidRoof);
    const overhang = try std.fmt.parseFloat(f32, nextPart(&parts) orelse return error.InvalidRoof);
    if (parts.next() != null) return error.InvalidRoof;
    return .{ .kind = kind, .pitch = pitch, .overhang = overhang };
}

fn parseShell(allocator: std.mem.Allocator, payload: []const u8) !Shell {
    var parts = std.mem.splitScalar(u8, payload, '|');
    var result = Shell{
        .id = try std.fmt.parseInt(u32, nextPart(&parts) orelse return error.InvalidShell, 10),
    };
    errdefer result.deinit(allocator);
    const walls_raw = nextPart(&parts) orelse return error.InvalidShell;
    var wall_parts = std.mem.splitScalar(u8, walls_raw, ',');
    while (wall_parts.next()) |raw| {
        if (raw.len == 0) return error.InvalidShell;
        try result.walls.append(allocator, try std.fmt.parseInt(u32, raw, 10));
    }
    if (result.walls.items.len < 3) return error.InvalidShell;
    if (parts.next() != null) return error.InvalidShell;
    return result;
}

fn parseFoundation(payload: []const u8) !Foundation {
    var parts = std.mem.splitScalar(u8, payload, '|');
    const result = Foundation{
        .id = try std.fmt.parseInt(u32, nextPart(&parts) orelse return error.InvalidFoundation, 10),
        .min_x = try std.fmt.parseFloat(f32, nextPart(&parts) orelse return error.InvalidFoundation),
        .min_z = try std.fmt.parseFloat(f32, nextPart(&parts) orelse return error.InvalidFoundation),
        .max_x = try std.fmt.parseFloat(f32, nextPart(&parts) orelse return error.InvalidFoundation),
        .max_z = try std.fmt.parseFloat(f32, nextPart(&parts) orelse return error.InvalidFoundation),
        .top_y = try std.fmt.parseFloat(f32, nextPart(&parts) orelse return error.InvalidFoundation),
        .clearance = try std.fmt.parseFloat(f32, nextPart(&parts) orelse return error.InvalidFoundation),
        .grid_step = try std.fmt.parseFloat(f32, nextPart(&parts) orelse return error.InvalidFoundation),
    };
    if (parts.next() != null) return error.InvalidFoundation;
    if (result.max_x <= result.min_x or result.max_z <= result.min_z or result.grid_step <= 0) return error.InvalidFoundation;
    return result;
}

fn parseCutout(payload: []const u8) !TerrainCutout {
    var parts = std.mem.splitScalar(u8, payload, '|');
    const result = TerrainCutout{
        .id = try std.fmt.parseInt(u32, nextPart(&parts) orelse return error.InvalidCutout, 10),
        .min_x = try std.fmt.parseFloat(f32, nextPart(&parts) orelse return error.InvalidCutout),
        .min_y = try std.fmt.parseFloat(f32, nextPart(&parts) orelse return error.InvalidCutout),
        .min_z = try std.fmt.parseFloat(f32, nextPart(&parts) orelse return error.InvalidCutout),
        .max_x = try std.fmt.parseFloat(f32, nextPart(&parts) orelse return error.InvalidCutout),
        .max_y = try std.fmt.parseFloat(f32, nextPart(&parts) orelse return error.InvalidCutout),
        .max_z = try std.fmt.parseFloat(f32, nextPart(&parts) orelse return error.InvalidCutout),
    };
    if (parts.next() != null) return error.InvalidCutout;
    if (result.max_x <= result.min_x or result.max_y <= result.min_y or result.max_z <= result.min_z) return error.InvalidCutout;
    return result;
}

fn nextPart(parts: *std.mem.SplitIterator(u8, .scalar)) ?[]const u8 {
    return parts.next();
}

test "building round-trips through serialize and parse" {
    const allocator = std.testing.allocator;
    var building = Building{};
    defer building.deinit(allocator);
    try building.vertices.append(allocator, .{ .id = 0, .x = 0, .z = 0 });
    try building.vertices.append(allocator, .{ .id = 1, .x = 6, .z = 0 });
    try building.vertices.append(allocator, .{ .id = 2, .x = 6, .z = 4 });
    try building.vertices.append(allocator, .{ .id = 3, .x = 0, .z = 4 });
    try building.walls.append(allocator, .{ .id = 0, .a = 0, .b = 1, .height = 3, .thickness = 0.25 });
    try building.walls.append(allocator, .{ .id = 1, .a = 1, .b = 2, .height = 3, .thickness = 0.25 });
    try building.openings.append(allocator, .{ .id = 0, .wall_id = 0, .kind = .door, .t = 0.5, .width = 1.0, .height = 2.1, .sill = 0 });
    try building.features.append(allocator, .{ .id = 0, .kind = .column, .x = 3, .z = 2, .height = 3, .width = 0.4 });
    try building.features.append(allocator, .{ .id = 1, .kind = .spiral_stair, .x = 3, .z = 2, .height = 9, .width = 1.5, .depth = 0.7, .steps = 24 });
    building.floors = .{ .count = 3, .height = 3, .slab_thickness = 0.12 };
    building.roof = .{ .kind = .conical, .pitch = 0.75, .overhang = 0.2 };

    const components = try building.serialize(allocator);
    defer {
        for (components) |c| allocator.free(c);
        allocator.free(components);
    }

    var const_components = try allocator.alloc([]const u8, components.len);
    defer allocator.free(const_components);
    for (components, 0..) |c, i| const_components[i] = c;

    var parsed = try Building.parse(allocator, const_components);
    defer parsed.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 4), parsed.vertices.items.len);
    try std.testing.expectEqual(@as(usize, 2), parsed.walls.items.len);
    try std.testing.expectEqual(@as(usize, 1), parsed.openings.items.len);
    try std.testing.expectEqual(OpeningKind.door, parsed.openings.items[0].kind);
    try std.testing.expectApproxEqAbs(@as(f32, 2.1), parsed.openings.items[0].height, eps);
    try std.testing.expectEqual(@as(u32, 3), parsed.floors.count);
    try std.testing.expectApproxEqAbs(@as(f32, 3), parsed.floors.height, eps);
    try std.testing.expectEqual(@as(usize, 2), parsed.features.items.len);
    try std.testing.expectEqual(FeatureKind.column, parsed.features.items[0].kind);
    try std.testing.expectEqual(FeatureKind.spiral_stair, parsed.features.items[1].kind);
    try std.testing.expect(parsed.roof != null);
    try std.testing.expectEqual(RoofKind.conical, parsed.roof.?.kind);
}

test "wall network metadata round-trips through building components" {
    const allocator = std.testing.allocator;
    var building = Building{};
    defer building.deinit(allocator);

    try building.vertices.append(allocator, .{ .id = 10, .x = 0, .z = 0 });
    try building.vertices.append(allocator, .{ .id = 11, .x = 4, .z = 0 });
    try building.vertices.append(allocator, .{ .id = 12, .x = 4, .z = 4 });
    try building.vertices.append(allocator, .{ .id = 13, .x = 0, .z = 4 });
    try building.walls.append(allocator, .{ .id = 20, .a = 10, .b = 11, .height = 3, .thickness = 0.25, .height_mode = .to_floor, .floor_index = 1 });
    try building.walls.append(allocator, .{ .id = 21, .a = 11, .b = 12, .height = 6, .thickness = 0.25, .height_mode = .explicit, .floor_index = 2 });
    try building.walls.append(allocator, .{ .id = 22, .a = 12, .b = 13, .height = 3, .thickness = 0.25 });
    try building.walls.append(allocator, .{ .id = 23, .a = 13, .b = 10, .height = 3, .thickness = 0.25 });
    var shell = Shell{ .id = 30 };
    try shell.walls.append(allocator, 20);
    try shell.walls.append(allocator, 21);
    try shell.walls.append(allocator, 22);
    try shell.walls.append(allocator, 23);
    try building.shells.append(allocator, shell);
    try building.foundations.append(allocator, .{ .id = 40, .min_x = 0, .min_z = 0, .max_x = 4, .max_z = 4, .top_y = 0.5 });
    try building.cutouts.append(allocator, .{ .id = 50, .min_x = 1, .min_y = -3, .min_z = 1, .max_x = 3, .max_y = 0, .max_z = 3 });

    const components = try building.serialize(allocator);
    defer {
        for (components) |component| allocator.free(component);
        allocator.free(components);
    }
    var const_components = try allocator.alloc([]const u8, components.len);
    defer allocator.free(const_components);
    for (components, 0..) |component, idx| const_components[idx] = component;

    var parsed = try Building.parse(allocator, const_components);
    defer parsed.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 4), parsed.vertices.items.len);
    try std.testing.expectEqual(@as(usize, 4), parsed.walls.items.len);
    try std.testing.expectEqual(WallHeightMode.to_floor, parsed.walls.items[0].height_mode);
    try std.testing.expectEqual(@as(u32, 1), parsed.walls.items[0].floor_index);
    try std.testing.expectEqual(@as(usize, 1), parsed.shells.items.len);
    try std.testing.expectEqual(@as(u32, 23), parsed.shells.items[0].walls.items[3]);
    try std.testing.expectEqual(@as(usize, 1), parsed.foundations.items.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), parsed.foundations.items[0].top_y, eps);
    try std.testing.expectEqual(@as(usize, 1), parsed.cutouts.items.len);
}

test "deleting wall and node invalidates dependent openings and shells" {
    const allocator = std.testing.allocator;
    var building = Building{};
    defer building.deinit(allocator);

    try building.vertices.append(allocator, .{ .id = 0, .x = 0, .z = 0 });
    try building.vertices.append(allocator, .{ .id = 1, .x = 2, .z = 0 });
    try building.vertices.append(allocator, .{ .id = 2, .x = 2, .z = 2 });
    try building.vertices.append(allocator, .{ .id = 3, .x = 0, .z = 2 });
    try building.walls.append(allocator, .{ .id = 0, .a = 0, .b = 1, .height = 3, .thickness = 0.2 });
    try building.walls.append(allocator, .{ .id = 1, .a = 1, .b = 2, .height = 3, .thickness = 0.2 });
    try building.walls.append(allocator, .{ .id = 2, .a = 2, .b = 3, .height = 3, .thickness = 0.2 });
    try building.walls.append(allocator, .{ .id = 3, .a = 3, .b = 0, .height = 3, .thickness = 0.2 });
    try building.openings.append(allocator, .{ .id = 0, .wall_id = 1, .kind = .window, .t = 0.5, .width = 0.8, .height = 1, .sill = 1 });
    var shell = Shell{ .id = 0 };
    try shell.walls.append(allocator, 0);
    try shell.walls.append(allocator, 1);
    try shell.walls.append(allocator, 2);
    try shell.walls.append(allocator, 3);
    try building.shells.append(allocator, shell);
    building.roof = .{ .kind = .flat, .pitch = 0, .overhang = 0.15 };

    const removed_wall = building.removeWallCascade(allocator, 1);
    try std.testing.expect(removed_wall.removed_wall);
    try std.testing.expectEqual(@as(u32, 1), removed_wall.removed_openings);
    try std.testing.expectEqual(@as(u32, 1), removed_wall.removed_shells);
    try std.testing.expectEqual(@as(usize, 3), building.walls.items.len);
    try std.testing.expectEqual(@as(usize, 0), building.openings.items.len);
    try std.testing.expectEqual(@as(usize, 0), building.shells.items.len);
    try std.testing.expect(building.roof == null);

    const removed_node = building.removeVertexCascade(allocator, 0);
    try std.testing.expect(removed_node.removed_vertex);
    try std.testing.expectEqual(@as(u32, 2), removed_node.removed_edges);
}
