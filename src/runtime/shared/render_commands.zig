const std = @import("std");
const gpu_scene = @import("gpu_scene.zig");
const editor_math = @import("editor_math.zig");
const shared_color = @import("color.zig");
const render_visibility = @import("render_visibility.zig");

pub const RenderPass = enum(u4) {
    clear = 0,
    geometry = 4,
    debug = 8,
    ui = 15,

    pub fn label(self: RenderPass) []const u8 {
        return switch (self) {
            .clear => "clear",
            .geometry => "geometry",
            .debug => "debug",
            .ui => "ui",
        };
    }
};

pub const RenderLayer = enum(u4) {
    clear = 0,
    world = 4,
    grid = 8,
    overlay = 15,

    pub fn label(self: RenderLayer) []const u8 {
        return switch (self) {
            .clear => "clear",
            .world => "world",
            .grid => "grid",
            .overlay => "overlay",
        };
    }
};

pub const PipelineId = enum(u8) {
    none = 0,
    mesh = 1,
    grid = 2,
    overlay = 3,
    wireframe = 4,
    water = 5,
    grass = 6,
};

pub const MeshShadingMode = enum {
    material_preview,
    solid,
    rendered,

    pub fn castsShadows(self: MeshShadingMode) bool {
        return self == .rendered;
    }
};

pub const MeshSurfaceKind = enum {
    @"opaque",
    water,
};

pub const MaterialId = struct {
    value: u16 = 0,

    pub const none: MaterialId = .{};

    pub fn init(value: u16) MaterialId {
        return .{ .value = value };
    }
};

pub const SortKey = packed struct(u64) {
    sequence: u16,
    depth_bucket: u16,
    material: u16,
    pipeline: u8,
    layer: u4,
    pass: u4,

    pub fn init(
        pass: RenderPass,
        layer: RenderLayer,
        pipeline: PipelineId,
        material: MaterialId,
        depth_bucket: u16,
        sequence: u16,
    ) SortKey {
        return .{
            .pass = @intFromEnum(pass),
            .layer = @intFromEnum(layer),
            .pipeline = @intFromEnum(pipeline),
            .material = material.value,
            .depth_bucket = depth_bucket,
            .sequence = sequence,
        };
    }

    pub fn value(self: SortKey) u64 {
        return @bitCast(self);
    }

    pub fn layerId(self: SortKey) u8 {
        return self.layer;
    }

    pub fn materialId(self: SortKey) MaterialId {
        return MaterialId.init(self.material);
    }
};

pub const MeshDraw = struct {
    mesh_index: u32,
    material_id: MaterialId = .none,
    transform: [16]f32,
    camera: editor_math.OrbitCamera,
    instance_count: u32 = 1,
    cast_shadows: bool = true,
    receive_shadows: bool = true,
    shading: MeshShadingMode = .rendered,
    double_sided: bool = false,
    projection_mode: editor_math.ProjectionMode = .perspective,
    surface: MeshSurfaceKind = .@"opaque",
};

pub const InstancedMeshDraw = struct {
    mesh_index: u32,
    material_id: MaterialId = .none,
    instance_transform_offset: u32,
    instance_count: u32,
    camera: editor_math.OrbitCamera,
    cast_shadows: bool = true,
    receive_shadows: bool = true,
    shading: MeshShadingMode = .rendered,
    projection_mode: editor_math.ProjectionMode = .perspective,
};

pub const GrassInstance = extern struct {
    position: [3]f32,
    normal: [3]f32,
    color: [4]u8,
    height: f32,
    width: f32,
    yaw: f32,
    phase: f32,
    variant: u32,
};

pub const GrassInfluencer = extern struct {
    position: [3]f32,
    radius: f32,
    strength: f32,
    velocity_dir: [3]f32,
};

pub const GrassDraw = struct {
    instance_offset: u32,
    instance_count: u32,
    influencer_offset: u32,
    influencer_count: u32,
    camera: editor_math.OrbitCamera,
    cull_fade: f32 = 1.0,
    wind_direction_deg: f32,
    wind_speed_mps: f32,
    wind_strength: f32,
    bend_strength: f32,
    stiffness: f32,
};

pub const OverlayDraw = struct {
    quads: []const gpu_scene.OverlayQuad,
};

pub const Clear = struct {
    color: shared_color.Color,
};

pub const Copy = struct {
    label: []const u8,
};

pub const RenderCommand = union(enum) {
    clear: Clear,
    grid: editor_math.GridDraw,
    mesh: MeshDraw,
    instanced_mesh: InstancedMeshDraw,
    grass: GrassDraw,
    wireframe_mesh: MeshDraw,
    overlay: OverlayDraw,
    copy: Copy,
};

pub const CommandEntry = struct {
    sort_key: SortKey,
    command: RenderCommand,
};

pub const Stats = struct {
    total: usize = 0,
    clears: usize = 0,
    grids: usize = 0,
    meshes: usize = 0,
    instanced_meshes: usize = 0,
    mesh_instances: usize = 0,
    grass_batches: usize = 0,
    grass_instances: usize = 0,
    overlays: usize = 0,
    copies: usize = 0,
};

pub const CommandBuffer = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayList(CommandEntry) = .empty,
    owned_instance_transforms: std.ArrayList([16]f32) = .empty,
    owned_grass_instances: std.ArrayList(GrassInstance) = .empty,
    owned_grass_influencers: std.ArrayList(GrassInfluencer) = .empty,
    next_sequence: u16 = 0,
    sorted: bool = false,
    submitted: bool = false,

    pub fn init(allocator: std.mem.Allocator) CommandBuffer {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *CommandBuffer) void {
        const allocator = self.allocator;
        self.entries.deinit(self.allocator);
        self.owned_instance_transforms.deinit(self.allocator);
        self.owned_grass_instances.deinit(self.allocator);
        self.owned_grass_influencers.deinit(self.allocator);
        self.* = .{ .allocator = allocator };
    }

    pub fn clearRetainingCapacity(self: *CommandBuffer) void {
        self.entries.clearRetainingCapacity();
        self.owned_instance_transforms.clearRetainingCapacity();
        self.owned_grass_instances.clearRetainingCapacity();
        self.owned_grass_influencers.clearRetainingCapacity();
        self.next_sequence = 0;
        self.sorted = false;
        self.submitted = false;
    }

    pub fn appendClear(self: *CommandBuffer, color: shared_color.Color) !void {
        try self.append(.clear, .clear, .none, .none, 0, .{ .clear = .{ .color = color } });
    }

    pub fn appendGrid(self: *CommandBuffer, camera: editor_math.OrbitCamera) !void {
        try self.appendGridDraw(editor_math.GridDraw.anchored(camera, camera.target, 1.0));
    }

    pub fn appendGridDraw(self: *CommandBuffer, draw: editor_math.GridDraw) !void {
        try self.append(.debug, .grid, .grid, .none, 0, .{ .grid = draw });
    }

    pub fn appendMesh(
        self: *CommandBuffer,
        mesh_index: usize,
        transform: [16]f32,
        camera: editor_math.OrbitCamera,
        depth_bucket: u16,
    ) !void {
        try self.appendMeshWithProjection(mesh_index, transform, camera, depth_bucket, .perspective);
    }

    pub fn appendMeshWithProjection(
        self: *CommandBuffer,
        mesh_index: usize,
        transform: [16]f32,
        camera: editor_math.OrbitCamera,
        depth_bucket: u16,
        projection_mode: editor_math.ProjectionMode,
    ) !void {
        try self.appendSceneMesh(mesh_index, .{
            .transform = transform,
            .bounds = render_visibility.boundsFromTransform(transform),
            .shading = .rendered,
            .projection_mode = projection_mode,
        }, camera, depth_bucket);
    }

    pub fn appendSceneMesh(
        self: *CommandBuffer,
        mesh_index: usize,
        mesh: render_visibility.SceneMesh,
        camera: editor_math.OrbitCamera,
        depth_bucket: u16,
    ) !void {
        try self.appendMeshDraw(mesh_index, mesh, camera, depth_bucket, .mesh);
    }

    pub fn appendWaterMesh(
        self: *CommandBuffer,
        mesh_index: usize,
        mesh: render_visibility.SceneMesh,
        camera: editor_math.OrbitCamera,
        depth_bucket: u16,
    ) !void {
        var water_mesh = mesh;
        water_mesh.surface = .water;
        water_mesh.cast_shadows = false;
        water_mesh.receive_shadows = false;
        try self.appendMeshDraw(mesh_index, water_mesh, camera, depth_bucket, .water);
    }

    fn appendMeshDraw(
        self: *CommandBuffer,
        mesh_index: usize,
        mesh: render_visibility.SceneMesh,
        camera: editor_math.OrbitCamera,
        depth_bucket: u16,
        pipeline: PipelineId,
    ) !void {
        if (mesh_index > std.math.maxInt(u32)) return error.MeshIndexTooLarge;
        try self.append(.geometry, .world, pipeline, .none, depth_bucket, .{
            .mesh = .{
                .mesh_index = @intCast(mesh_index),
                .transform = mesh.transform,
                .camera = camera,
                .cast_shadows = mesh.cast_shadows,
                .receive_shadows = mesh.receive_shadows,
                .shading = mesh.shading,
                .double_sided = mesh.double_sided,
                .projection_mode = mesh.projection_mode,
                .surface = mesh.surface,
            },
        });
    }

    pub fn appendDoubleSidedMeshWithProjection(
        self: *CommandBuffer,
        mesh_index: usize,
        transform: [16]f32,
        camera: editor_math.OrbitCamera,
        depth_bucket: u16,
        projection_mode: editor_math.ProjectionMode,
    ) !void {
        try self.appendSceneMesh(mesh_index, .{
            .transform = transform,
            .bounds = render_visibility.boundsFromTransform(transform),
            .double_sided = true,
            .projection_mode = projection_mode,
        }, camera, depth_bucket);
    }

    pub fn appendMeshWithMaterial(
        self: *CommandBuffer,
        mesh_index: usize,
        material_id: MaterialId,
        transform: [16]f32,
        camera: editor_math.OrbitCamera,
        depth_bucket: u16,
    ) !void {
        if (mesh_index > std.math.maxInt(u32)) return error.MeshIndexTooLarge;
        try self.append(.geometry, .world, .mesh, material_id, depth_bucket, .{
            .mesh = .{
                .mesh_index = @intCast(mesh_index),
                .material_id = material_id,
                .transform = transform,
                .camera = camera,
            },
        });
    }

    pub fn appendInstancedMesh(
        self: *CommandBuffer,
        mesh_index: usize,
        transforms: []const [16]f32,
        camera: editor_math.OrbitCamera,
        depth_bucket: u16,
    ) !void {
        if (transforms.len < 2) return error.InstancedDrawRequiresMultipleInstances;
        if (mesh_index > std.math.maxInt(u32)) return error.MeshIndexTooLarge;
        const offset: u32 = @intCast(self.owned_instance_transforms.items.len);
        if (offset + transforms.len > std.math.maxInt(u32)) return error.InstanceTransformOverflow;
        try self.owned_instance_transforms.appendSlice(self.allocator, transforms);
        try self.append(.geometry, .world, .mesh, .none, depth_bucket, .{
            .instanced_mesh = .{
                .mesh_index = @intCast(mesh_index),
                .instance_transform_offset = offset,
                .instance_count = @intCast(transforms.len),
                .camera = camera,
            },
        });
    }

    pub fn instanceTransforms(self: *const CommandBuffer, draw: InstancedMeshDraw) []const [16]f32 {
        const start = draw.instance_transform_offset;
        const end = start + draw.instance_count;
        return self.owned_instance_transforms.items[start..end];
    }

    pub fn appendGrass(
        self: *CommandBuffer,
        instances: []const GrassInstance,
        influencers: []const GrassInfluencer,
        camera: editor_math.OrbitCamera,
        controls: GrassDraw,
        depth_bucket: u16,
    ) !void {
        if (instances.len == 0) return error.EmptyGrassBatch;
        const instance_offset: u32 = @intCast(self.owned_grass_instances.items.len);
        const influencer_offset: u32 = @intCast(self.owned_grass_influencers.items.len);
        if (instance_offset + instances.len > std.math.maxInt(u32)) return error.GrassInstanceOverflow;
        if (influencer_offset + influencers.len > std.math.maxInt(u32)) return error.GrassInfluencerOverflow;
        try self.owned_grass_instances.appendSlice(self.allocator, instances);
        try self.owned_grass_influencers.appendSlice(self.allocator, influencers);
        var draw = controls;
        draw.instance_offset = instance_offset;
        draw.instance_count = @intCast(instances.len);
        draw.influencer_offset = influencer_offset;
        draw.influencer_count = @intCast(influencers.len);
        draw.camera = camera;
        try self.append(.geometry, .world, .grass, .none, depth_bucket, .{ .grass = draw });
    }

    pub fn grassInstances(self: *const CommandBuffer, draw: GrassDraw) []const GrassInstance {
        const start = draw.instance_offset;
        const end = start + draw.instance_count;
        return self.owned_grass_instances.items[start..end];
    }

    pub fn grassInfluencers(self: *const CommandBuffer, draw: GrassDraw) []const GrassInfluencer {
        const start = draw.influencer_offset;
        const end = start + draw.influencer_count;
        return self.owned_grass_influencers.items[start..end];
    }

    pub fn appendWireframeMesh(
        self: *CommandBuffer,
        mesh_index: usize,
        transform: [16]f32,
        camera: editor_math.OrbitCamera,
        depth_bucket: u16,
    ) !void {
        try self.appendWireframeMeshWithProjection(mesh_index, transform, camera, depth_bucket, .perspective);
    }

    pub fn appendWireframeMeshWithProjection(
        self: *CommandBuffer,
        mesh_index: usize,
        transform: [16]f32,
        camera: editor_math.OrbitCamera,
        depth_bucket: u16,
        projection_mode: editor_math.ProjectionMode,
    ) !void {
        if (mesh_index > std.math.maxInt(u32)) return error.MeshIndexTooLarge;
        try self.append(.debug, .overlay, .wireframe, .none, depth_bucket, .{
            .wireframe_mesh = .{
                .mesh_index = @intCast(mesh_index),
                .transform = transform,
                .camera = camera,
                .projection_mode = projection_mode,
            },
        });
    }

    pub fn appendOverlay(self: *CommandBuffer, quads: []const gpu_scene.OverlayQuad) !void {
        try self.append(.ui, .overlay, .overlay, .none, 0, .{ .overlay = .{ .quads = quads } });
    }

    pub fn appendCopy(self: *CommandBuffer, label: []const u8) !void {
        try self.append(.ui, .overlay, .none, .none, 0, .{ .copy = .{ .label = label } });
    }

    pub fn sort(self: *CommandBuffer) void {
        std.mem.sort(CommandEntry, self.entries.items, {}, compareEntries);
        self.sorted = true;
    }

    pub fn markSubmitted(self: *CommandBuffer) !void {
        if (self.submitted) return error.CommandBufferSubmittedTwice;
        self.submitted = true;
    }

    pub fn stats(self: *const CommandBuffer) Stats {
        var result = Stats{ .total = self.entries.items.len };
        for (self.entries.items) |entry| switch (entry.command) {
            .clear => result.clears += 1,
            .grid => result.grids += 1,
            .mesh => result.meshes += 1,
            .instanced_mesh => |draw| {
                result.instanced_meshes += 1;
                result.mesh_instances += draw.instance_count;
            },
            .grass => |draw| {
                result.grass_batches += 1;
                result.grass_instances += draw.instance_count;
            },
            .wireframe_mesh => result.meshes += 1,
            .overlay => result.overlays += 1,
            .copy => result.copies += 1,
        };
        return result;
    }

    fn append(
        self: *CommandBuffer,
        pass: RenderPass,
        layer: RenderLayer,
        pipeline: PipelineId,
        material: MaterialId,
        depth_bucket: u16,
        command: RenderCommand,
    ) !void {
        if (self.sorted) return error.CommandBufferAlreadySorted;
        if (self.submitted) return error.CommandBufferAlreadySubmitted;
        const sequence = self.next_sequence;
        if (sequence == std.math.maxInt(u16)) return error.CommandBufferSequenceOverflow;
        self.next_sequence += 1;
        try self.entries.append(self.allocator, .{
            .sort_key = SortKey.init(pass, layer, pipeline, material, depth_bucket, sequence),
            .command = command,
        });
    }
};

fn compareEntries(_: void, a: CommandEntry, b: CommandEntry) bool {
    return a.sort_key.value() < b.sort_key.value();
}

test "sort key orders pass then layer" {
    var buffer = CommandBuffer.init(std.testing.allocator);
    defer buffer.deinit();

    try buffer.appendOverlay(&.{});
    try buffer.appendGrid(.{});
    try buffer.appendMesh(1, [_]f32{1} ** 16, .{}, 10);
    try buffer.appendClear(.{ .r = 1, .g = 2, .b = 3, .a = 255 });
    buffer.sort();

    try std.testing.expectEqual(@as(u8, @intFromEnum(RenderLayer.clear)), buffer.entries.items[0].sort_key.layerId());
    try std.testing.expectEqual(@as(u8, @intFromEnum(RenderLayer.world)), buffer.entries.items[1].sort_key.layerId());
    try std.testing.expectEqual(@as(u8, @intFromEnum(RenderLayer.grid)), buffer.entries.items[2].sort_key.layerId());
    try std.testing.expectEqual(@as(u8, @intFromEnum(RenderLayer.overlay)), buffer.entries.items[3].sort_key.layerId());
}

test "sort key orders pipeline and material identity before depth" {
    var buffer = CommandBuffer.init(std.testing.allocator);
    defer buffer.deinit();

    try buffer.appendMeshWithMaterial(4, MaterialId.init(9), [_]f32{4} ** 16, .{}, 1);
    try buffer.appendMeshWithMaterial(1, MaterialId.init(3), [_]f32{1} ** 16, .{}, 99);
    try buffer.appendMeshWithMaterial(3, MaterialId.init(3), [_]f32{3} ** 16, .{}, 2);
    try buffer.appendMeshWithMaterial(2, MaterialId.init(7), [_]f32{2} ** 16, .{}, 0);
    buffer.sort();

    try std.testing.expectEqual(@as(u32, 3), buffer.entries.items[0].command.mesh.mesh_index);
    try std.testing.expectEqual(@as(u32, 1), buffer.entries.items[1].command.mesh.mesh_index);
    try std.testing.expectEqual(@as(u32, 2), buffer.entries.items[2].command.mesh.mesh_index);
    try std.testing.expectEqual(@as(u32, 4), buffer.entries.items[3].command.mesh.mesh_index);
    try std.testing.expectEqual(@as(u16, 3), buffer.entries.items[0].sort_key.materialId().value);
}

test "sort key keeps append sequence stable inside identical buckets" {
    var buffer = CommandBuffer.init(std.testing.allocator);
    defer buffer.deinit();

    try buffer.appendMeshWithMaterial(2, MaterialId.init(5), [_]f32{2} ** 16, .{}, 20);
    try buffer.appendMeshWithMaterial(1, MaterialId.init(5), [_]f32{1} ** 16, .{}, 20);
    try buffer.appendMeshWithMaterial(3, MaterialId.init(5), [_]f32{3} ** 16, .{}, 20);
    buffer.sort();

    try std.testing.expectEqual(@as(u32, 2), buffer.entries.items[0].command.mesh.mesh_index);
    try std.testing.expectEqual(@as(u32, 1), buffer.entries.items[1].command.mesh.mesh_index);
    try std.testing.expectEqual(@as(u32, 3), buffer.entries.items[2].command.mesh.mesh_index);
}

test "sort key orders water after opaque world mesh before debug and ui" {
    var buffer = CommandBuffer.init(std.testing.allocator);
    defer buffer.deinit();

    const water_transform = [_]f32{2} ** 16;
    try buffer.appendOverlay(&.{});
    try buffer.appendGrid(.{});
    try buffer.appendWaterMesh(2, .{
        .transform = water_transform,
        .bounds = render_visibility.boundsFromTransform(water_transform),
    }, .{}, 0);
    try buffer.appendMesh(1, [_]f32{1} ** 16, .{}, 0);
    buffer.sort();

    try std.testing.expectEqual(PipelineId.mesh, @as(PipelineId, @enumFromInt(buffer.entries.items[0].sort_key.pipeline)));
    try std.testing.expectEqual(PipelineId.water, @as(PipelineId, @enumFromInt(buffer.entries.items[1].sort_key.pipeline)));
    try std.testing.expectEqual(RenderLayer.grid, @as(RenderLayer, @enumFromInt(buffer.entries.items[2].sort_key.layer)));
    try std.testing.expectEqual(RenderPass.ui, @as(RenderPass, @enumFromInt(buffer.entries.items[3].sort_key.pass)));
    try std.testing.expectEqual(MeshSurfaceKind.water, buffer.entries.items[1].command.mesh.surface);
}

test "command buffer batches instanced mesh transforms" {
    var buffer = CommandBuffer.init(std.testing.allocator);
    defer buffer.deinit();

    const transforms = [_][16]f32{ [_]f32{1} ** 16, [_]f32{2} ** 16 };
    try buffer.appendInstancedMesh(3, &transforms, .{}, 0);
    try std.testing.expectEqual(@as(usize, 1), buffer.entries.items.len);
    try std.testing.expectEqual(@as(u32, 2), buffer.entries.items[0].command.instanced_mesh.instance_count);
    try std.testing.expectEqual(@as(usize, 2), buffer.owned_instance_transforms.items.len);
}

test "command buffer fails after sort or submit" {
    var buffer = CommandBuffer.init(std.testing.allocator);
    defer buffer.deinit();

    try buffer.appendGrid(.{});
    buffer.sort();
    try std.testing.expectError(error.CommandBufferAlreadySorted, buffer.appendGrid(.{}));
    try buffer.markSubmitted();
    try std.testing.expectError(error.CommandBufferSubmittedTwice, buffer.markSubmitted());
}


test "command buffer owns grass instances and influencers" {
    var buffer = CommandBuffer.init(std.testing.allocator);
    defer buffer.deinit();

    const instances = [_]GrassInstance{
        .{ .position = .{ 0, 0, 0 }, .normal = .{ 0, 1, 0 }, .color = .{ 80, 150, 70, 255 }, .height = 1, .width = 0.05, .yaw = 0, .phase = 0, .variant = 0 },
        .{ .position = .{ 1, 0, 0 }, .normal = .{ 0, 1, 0 }, .color = .{ 70, 140, 70, 255 }, .height = 0.8, .width = 0.04, .yaw = 1, .phase = 2, .variant = 1 },
    };
    const influencers = [_]GrassInfluencer{.{ .position = .{ 0, 0, 1 }, .radius = 1.5, .strength = 1, .velocity_dir = .{ 1, 0, 0 } }};
    try buffer.appendGrass(&instances, &influencers, .{}, .{
        .instance_offset = 0,
        .instance_count = 0,
        .influencer_offset = 0,
        .influencer_count = 0,
        .camera = .{},
        .wind_direction_deg = 225,
        .wind_speed_mps = 4,
        .wind_strength = 0.5,
        .bend_strength = 0.8,
        .stiffness = 0.7,
    }, 0);

    try std.testing.expectEqual(@as(usize, 1), buffer.entries.items.len);
    try std.testing.expectEqual(@as(usize, 2), buffer.grassInstances(buffer.entries.items[0].command.grass).len);
    try std.testing.expectEqual(@as(usize, 1), buffer.grassInfluencers(buffer.entries.items[0].command.grass).len);
    const stats_result = buffer.stats();
    try std.testing.expectEqual(@as(usize, 1), stats_result.grass_batches);
    try std.testing.expectEqual(@as(usize, 2), stats_result.grass_instances);
}

test "command buffer rejects empty grass batches" {
    var buffer = CommandBuffer.init(std.testing.allocator);
    defer buffer.deinit();

    try std.testing.expectError(error.EmptyGrassBatch, buffer.appendGrass(&.{}, &.{}, .{}, .{
        .instance_offset = 0,
        .instance_count = 0,
        .influencer_offset = 0,
        .influencer_count = 0,
        .camera = .{},
        .wind_direction_deg = 225,
        .wind_speed_mps = 4,
        .wind_strength = 0.5,
        .bend_strength = 0.8,
        .stiffness = 0.7,
    }, 0));
}
