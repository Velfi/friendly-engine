const std = @import("std");

pub const PassId = u32;
pub const ResourceId = u32;

pub const ResourceUsage = enum {
    imported,
    sampled_texture,
    color_target,
    color_target_load,
    depth_target,
    copy_source,
    copy_dest,

    pub fn isWrite(self: ResourceUsage) bool {
        return switch (self) {
            .color_target, .color_target_load, .depth_target, .copy_dest => true,
            .imported, .sampled_texture, .copy_source => false,
        };
    }

    pub fn isRead(self: ResourceUsage) bool {
        return switch (self) {
            .sampled_texture, .color_target_load, .copy_source => true,
            .imported, .color_target, .depth_target, .copy_dest => false,
        };
    }
};

pub const Resource = struct {
    id: ResourceId,
    name: []const u8,
    imported: bool = false,
};

pub const Access = struct {
    resource: ResourceId,
    usage: ResourceUsage,
};

pub const Pass = struct {
    id: PassId,
    name: []const u8,
    accesses: std.ArrayList(Access) = .empty,
    root: bool = false,

    pub fn reads(self: *Pass, allocator: std.mem.Allocator, resource: ResourceId, usage: ResourceUsage) !void {
        if (!usage.isRead()) return error.InvalidReadUsage;
        try self.accesses.append(allocator, .{ .resource = resource, .usage = usage });
    }

    pub fn writes(self: *Pass, allocator: std.mem.Allocator, resource: ResourceId, usage: ResourceUsage) !void {
        if (!usage.isWrite()) return error.InvalidWriteUsage;
        try self.accesses.append(allocator, .{ .resource = resource, .usage = usage });
    }

    pub fn deinit(self: *Pass, allocator: std.mem.Allocator) void {
        self.accesses.deinit(allocator);
    }
};

pub const BuiltGraph = struct {
    pass_order: []PassId,

    pub fn deinit(self: *BuiltGraph, allocator: std.mem.Allocator) void {
        allocator.free(self.pass_order);
        self.pass_order = &.{};
    }
};

pub const RenderGraph = struct {
    allocator: std.mem.Allocator,
    resources: std.ArrayList(Resource) = .empty,
    passes: std.ArrayList(Pass) = .empty,

    pub fn init(allocator: std.mem.Allocator) RenderGraph {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *RenderGraph) void {
        for (self.passes.items) |*pass| pass.deinit(self.allocator);
        self.passes.deinit(self.allocator);
        self.resources.deinit(self.allocator);
    }

    pub fn addResource(self: *RenderGraph, name: []const u8, imported: bool) !ResourceId {
        for (self.resources.items) |resource| {
            if (std.mem.eql(u8, resource.name, name)) return error.DuplicateGraphResourceName;
        }
        const id: ResourceId = @intCast(self.resources.items.len);
        try self.resources.append(self.allocator, .{ .id = id, .name = name, .imported = imported });
        return id;
    }

    pub fn addPass(self: *RenderGraph, name: []const u8, root: bool) !PassId {
        const id: PassId = @intCast(self.passes.items.len);
        try self.passes.append(self.allocator, .{ .id = id, .name = name, .root = root });
        return id;
    }

    pub fn passPtr(self: *RenderGraph, id: PassId) !*Pass {
        if (id >= self.passes.items.len) return error.MissingGraphPass;
        return &self.passes.items[id];
    }

    pub fn build(self: *RenderGraph) !BuiltGraph {
        try self.validateResourcesExist();
        const pass_count = self.passes.items.len;
        var indegree = try self.allocator.alloc(usize, pass_count);
        defer self.allocator.free(indegree);
        @memset(indegree, 0);

        const adjacency = try self.allocator.alloc(std.ArrayList(PassId), pass_count);
        defer {
            for (adjacency) |*edges| edges.deinit(self.allocator);
            self.allocator.free(adjacency);
        }
        for (adjacency) |*edges| edges.* = .empty;

        try self.buildResourceDependencies(adjacency, indegree);

        var queue = std.ArrayList(PassId).empty;
        defer queue.deinit(self.allocator);
        for (self.passes.items) |pass| {
            if (indegree[pass.id] == 0) try queue.append(self.allocator, pass.id);
        }

        var order = std.ArrayList(PassId).empty;
        errdefer order.deinit(self.allocator);
        var cursor: usize = 0;
        while (cursor < queue.items.len) : (cursor += 1) {
            const id = queue.items[cursor];
            try order.append(self.allocator, id);
            for (adjacency[id].items) |next| {
                indegree[next] -= 1;
                if (indegree[next] == 0) try queue.append(self.allocator, next);
            }
        }

        if (order.items.len != pass_count) return error.RenderGraphCycle;
        return .{ .pass_order = try order.toOwnedSlice(self.allocator) };
    }

    fn validateResourcesExist(self: *const RenderGraph) !void {
        for (self.passes.items) |pass| {
            for (pass.accesses.items) |access| {
                if (access.resource >= self.resources.items.len) return error.MissingGraphResource;
            }
        }
    }

    fn buildResourceDependencies(
        self: *const RenderGraph,
        adjacency: []std.ArrayList(PassId),
        indegree: []usize,
    ) !void {
        const last_writer = try self.allocator.alloc(?PassId, self.resources.items.len);
        defer self.allocator.free(last_writer);
        const last_user = try self.allocator.alloc(?PassId, self.resources.items.len);
        defer self.allocator.free(last_user);
        @memset(last_writer, null);
        @memset(last_user, null);

        for (self.passes.items) |pass| {
            for (pass.accesses.items) |access| {
                const resource = self.resources.items[access.resource];
                if (access.usage.isRead()) {
                    if (!resource.imported and last_writer[access.resource] == null) {
                        return error.ReadBeforeWriteGraphResource;
                    }
                    if (last_writer[access.resource]) |source| {
                        try addDependency(self.allocator, adjacency, indegree, source, pass.id);
                    }
                }
                if (access.usage.isWrite()) {
                    if (last_user[access.resource]) |source| {
                        try addDependency(self.allocator, adjacency, indegree, source, pass.id);
                    }
                    last_writer[access.resource] = pass.id;
                }
                last_user[access.resource] = pass.id;
            }
        }
    }

    fn addDependency(
        allocator: std.mem.Allocator,
        adjacency: []std.ArrayList(PassId),
        indegree: []usize,
        source: PassId,
        dest: PassId,
    ) !void {
        if (source == dest) return;
        for (adjacency[source].items) |existing| {
            if (existing == dest) return;
        }
        try adjacency[source].append(allocator, dest);
        indegree[dest] += 1;
    }
};

pub const FramePassKind = enum {
    shadow_depth,
    main_depth_scene,
    water_surface,
    overlay,
    readback,
    present,
};

pub const FramePlanOptions = struct {
    shadows: bool = false,
    water: bool = false,
    overlays: bool = false,
    readback: bool = false,
};

pub const FramePlan = struct {
    order: []FramePassKind,

    pub fn deinit(self: *FramePlan, allocator: std.mem.Allocator) void {
        allocator.free(self.order);
        self.order = &.{};
    }
};

pub fn buildFramePlan(allocator: std.mem.Allocator, options: FramePlanOptions) !FramePlan {
    var graph = RenderGraph.init(allocator);
    defer graph.deinit();

    const frame_color = try graph.addResource("frame.color", true);
    const frame_depth = try graph.addResource("frame.depth", true);
    const shadow_map = try graph.addResource("shadow.depth", false);
    const readback_buffer = try graph.addResource("frame.readback", false);
    const present_target = try graph.addResource("present.target", true);

    var pass_kinds = std.ArrayList(FramePassKind).empty;
    defer pass_kinds.deinit(allocator);

    if (options.shadows) {
        const shadow = try graph.addPass("shadow depth", false);
        try pass_kinds.append(allocator, .shadow_depth);
        try (try graph.passPtr(shadow)).writes(allocator, shadow_map, .depth_target);
    }

    const scene = try graph.addPass("main depth scene", false);
    try pass_kinds.append(allocator, .main_depth_scene);
    try (try graph.passPtr(scene)).writes(allocator, frame_color, .color_target);
    try (try graph.passPtr(scene)).writes(allocator, frame_depth, .depth_target);
    if (options.shadows) try (try graph.passPtr(scene)).reads(allocator, shadow_map, .sampled_texture);

    if (options.water) {
        const water = try graph.addPass("water surface", false);
        try pass_kinds.append(allocator, .water_surface);
        try (try graph.passPtr(water)).reads(allocator, frame_color, .color_target_load);
        try (try graph.passPtr(water)).reads(allocator, frame_depth, .sampled_texture);
        try (try graph.passPtr(water)).writes(allocator, frame_color, .color_target);
    }

    if (options.overlays) {
        const overlay = try graph.addPass("overlay", false);
        try pass_kinds.append(allocator, .overlay);
        try (try graph.passPtr(overlay)).writes(allocator, frame_color, .color_target_load);
    }

    if (options.readback) {
        const readback = try graph.addPass("readback", false);
        try pass_kinds.append(allocator, .readback);
        try (try graph.passPtr(readback)).reads(allocator, frame_color, .copy_source);
        try (try graph.passPtr(readback)).writes(allocator, readback_buffer, .copy_dest);
    }

    const present = try graph.addPass("present", true);
    try pass_kinds.append(allocator, .present);
    try (try graph.passPtr(present)).reads(allocator, frame_color, .sampled_texture);
    try (try graph.passPtr(present)).writes(allocator, present_target, .color_target);

    var built = try graph.build();
    defer built.deinit(allocator);

    const order = try allocator.alloc(FramePassKind, built.pass_order.len);
    errdefer allocator.free(order);
    for (built.pass_order, 0..) |pass_id, index| {
        order[index] = pass_kinds.items[pass_id];
    }
    return .{ .order = order };
}

test "render graph validates simple dependency order" {
    var graph = RenderGraph.init(std.testing.allocator);
    defer graph.deinit();

    const color = try graph.addResource("color", false);
    const lighting = try graph.addPass("lighting", false);
    try (try graph.passPtr(lighting)).writes(std.testing.allocator, color, .color_target);
    const present = try graph.addPass("present", true);
    try (try graph.passPtr(present)).reads(std.testing.allocator, color, .sampled_texture);

    var built = try graph.build();
    defer built.deinit(std.testing.allocator);
    try std.testing.expectEqualSlices(PassId, &.{ lighting, present }, built.pass_order);
}

test "render graph rejects duplicate resources and read before write" {
    var graph = RenderGraph.init(std.testing.allocator);
    defer graph.deinit();

    const color = try graph.addResource("color", false);
    try std.testing.expectError(error.DuplicateGraphResourceName, graph.addResource("color", false));
    const present = try graph.addPass("present", true);
    try (try graph.passPtr(present)).reads(std.testing.allocator, color, .sampled_texture);
    try std.testing.expectError(error.ReadBeforeWriteGraphResource, graph.build());
}

test "render graph orders repeated render target writes" {
    var graph = RenderGraph.init(std.testing.allocator);
    defer graph.deinit();

    const color = try graph.addResource("color", true);
    const scene = try graph.addPass("scene", false);
    try (try graph.passPtr(scene)).writes(std.testing.allocator, color, .color_target);
    const overlay = try graph.addPass("overlay", false);
    try (try graph.passPtr(overlay)).reads(std.testing.allocator, color, .color_target_load);
    try (try graph.passPtr(overlay)).writes(std.testing.allocator, color, .color_target);

    var built = try graph.build();
    defer built.deinit(std.testing.allocator);
    try std.testing.expectEqualSlices(PassId, &.{ scene, overlay }, built.pass_order);
}

test "frame graph orders shadows before depth scene and overlays" {
    var plan = try buildFramePlan(std.testing.allocator, .{
        .shadows = true,
        .water = true,
        .overlays = true,
        .readback = true,
    });
    defer plan.deinit(std.testing.allocator);

    try std.testing.expectEqualSlices(FramePassKind, &.{
        .shadow_depth,
        .main_depth_scene,
        .water_surface,
        .overlay,
        .readback,
        .present,
    }, plan.order);
}
