const std = @import("std");
const core = @import("../core/mod.zig");

pub const ClearColor = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,
};

pub const GrassInstance = struct {
    position: [3]f32,
    normal: [3]f32,
    color: [4]u8,
    height: f32,
    width: f32,
    yaw: f32,
    phase: f32,
    variant: u32,
};

pub const GrassInfluencer = struct {
    position: [3]f32,
    radius: f32,
    strength: f32,
    velocity_dir: [3]f32,
};

pub const GrassCluster = struct {
    instances: []const GrassInstance,
    influencers: []const GrassInfluencer = &.{},
    cull_fade: f32 = 1.0,
    wind_direction_deg: f32,
    wind_speed_mps: f32,
    wind_strength: f32,
    bend_strength: f32,
    stiffness: f32,
};

pub const SurfaceKind = enum {
    @"opaque",
    water,
};

pub const DrawMesh = struct {
    mesh_asset: core.AssetId,
    material_asset: core.AssetId,
    transform: [16]f32,
    double_sided: bool = false,
    surface: SurfaceKind = .@"opaque",
};

pub const DrawMeshInstanced = struct {
    mesh_asset: core.AssetId,
    material_asset: core.AssetId,
    transform_offset: u32,
    transform_count: u32,
    surface: SurfaceKind = .@"opaque",
};

pub const DrawQuad = struct {
    rect: [4]f32,
    color: [4]f32,
    texture_asset: ?core.AssetId = null,
};

pub const DrawText = struct {
    font_asset: core.AssetId,
    text: []const u8,
    position: [2]f32,
    size: f32,
    color: [4]f32,
};

pub const RenderCommand = union(enum) {
    clear: ClearColor,
    draw_mesh: DrawMesh,
    draw_mesh_instanced: DrawMeshInstanced,
    draw_grass: GrassCluster,
    draw_quad: DrawQuad,
    draw_text: DrawText,
};

pub const BackendVTable = struct {
    beginFrame: *const fn (context: *anyopaque) anyerror!void,
    submit: *const fn (context: *anyopaque, command: RenderCommand, instance_transforms: []const [16]f32) anyerror!void,
    endFrame: *const fn (context: *anyopaque) anyerror!void,
};

pub const Backend = struct {
    context: *anyopaque,
    vtable: *const BackendVTable,
};

pub const RenderSystem = struct {
    allocator: std.mem.Allocator,
    backend: ?Backend = null,
    commands: std.ArrayList(RenderCommand),
    owned_texts: std.ArrayList([]u8),
    owned_instance_transforms: std.ArrayList([16]f32),
    owned_grass_instances: std.ArrayList([]GrassInstance),
    owned_grass_influencers: std.ArrayList([]GrassInfluencer),

    pub fn init(allocator: std.mem.Allocator) RenderSystem {
        return .{
            .allocator = allocator,
            .commands = .empty,
            .owned_texts = .empty,
            .owned_instance_transforms = .empty,
            .owned_grass_instances = .empty,
            .owned_grass_influencers = .empty,
        };
    }

    pub fn deinit(self: *RenderSystem) void {
        self.clearCommands();
        self.owned_texts.deinit(self.allocator);
        self.owned_instance_transforms.deinit(self.allocator);
        self.owned_grass_instances.deinit(self.allocator);
        self.owned_grass_influencers.deinit(self.allocator);
        self.commands.deinit(self.allocator);
    }

    pub fn setBackend(self: *RenderSystem, backend: Backend) void {
        self.backend = backend;
    }

    pub fn queue(self: *RenderSystem, command: RenderCommand) !void {
        try self.commands.append(self.allocator, command);
    }

    pub fn queueMeshInstanced(
        self: *RenderSystem,
        mesh_asset: core.AssetId,
        material_asset: core.AssetId,
        transforms: []const [16]f32,
    ) !void {
        if (transforms.len == 0) return error.EmptyInstanceBatch;
        if (transforms.len == 1) {
            try self.queue(.{
                .draw_mesh = .{
                    .mesh_asset = mesh_asset,
                    .material_asset = material_asset,
                    .transform = transforms[0],
                    .surface = .@"opaque",
                },
            });
            return;
        }
        const transform_offset: u32 = @intCast(self.owned_instance_transforms.items.len);
        if (transform_offset + transforms.len > std.math.maxInt(u32)) return error.InstanceTransformOverflow;
        try self.owned_instance_transforms.appendSlice(self.allocator, transforms);
        try self.queue(.{
            .draw_mesh_instanced = .{
                .mesh_asset = mesh_asset,
                .material_asset = material_asset,
                .transform_offset = transform_offset,
                .transform_count = @intCast(transforms.len),
                .surface = .@"opaque",
            },
        });
    }

    pub fn queueGrass(
        self: *RenderSystem,
        instances: anytype,
        meta: anytype,
        influencers: anytype,
        cull_fade: f32,
    ) !void {
        if (instances.len == 0) return error.EmptyGrassBatch;
        const owned_instances = try self.allocator.alloc(GrassInstance, instances.len);
        errdefer self.allocator.free(owned_instances);
        for (instances, 0..) |instance, i| {
            owned_instances[i] = .{
                .position = instance.position,
                .normal = instance.normal,
                .color = instance.color,
                .height = instance.height,
                .width = instance.width,
                .yaw = instance.yaw,
                .phase = instance.phase,
                .variant = instance.variant,
            };
        }
        const influencer_count = @min(influencers.len, 16);
        const owned_influencers = try self.allocator.alloc(GrassInfluencer, influencer_count);
        errdefer self.allocator.free(owned_influencers);
        for (influencers[0..influencer_count], 0..) |influencer, i| {
            owned_influencers[i] = .{
                .position = influencer.position,
                .radius = influencer.radius,
                .strength = influencer.strength,
                .velocity_dir = influencer.velocity_dir,
            };
        }
        try self.owned_grass_instances.append(self.allocator, owned_instances);
        errdefer _ = self.owned_grass_instances.pop();
        try self.owned_grass_influencers.append(self.allocator, owned_influencers);
        try self.commands.append(self.allocator, .{
            .draw_grass = .{
                .instances = owned_instances,
                .influencers = owned_influencers,
                .cull_fade = cull_fade,
                .wind_direction_deg = meta.controls.wind_direction_deg,
                .wind_speed_mps = meta.controls.wind_speed_mps,
                .wind_strength = meta.controls.wind_strength,
                .bend_strength = meta.controls.bend_strength,
                .stiffness = meta.controls.stiffness,
            },
        });
    }

    pub fn queueText(
        self: *RenderSystem,
        font_asset: core.AssetId,
        text: []const u8,
        position: [2]f32,
        size: f32,
        color: [4]f32,
    ) !void {
        const owned_text = try self.allocator.dupe(u8, text);
        errdefer self.allocator.free(owned_text);
        try self.owned_texts.append(self.allocator, owned_text);
        try self.commands.append(self.allocator, .{
            .draw_text = .{
                .font_asset = font_asset,
                .text = owned_text,
                .position = position,
                .size = size,
                .color = color,
            },
        });
    }

    pub fn flush(self: *RenderSystem) !void {
        if (self.backend) |backend| {
            try backend.vtable.beginFrame(backend.context);
            const instance_transforms = self.owned_instance_transforms.items;
            for (self.commands.items) |command| {
                try backend.vtable.submit(backend.context, command, instance_transforms);
            }
            try backend.vtable.endFrame(backend.context);
        }
        self.clearCommands();
    }

    fn clearCommands(self: *RenderSystem) void {
        for (self.owned_texts.items) |text| {
            self.allocator.free(text);
        }
        self.owned_texts.clearRetainingCapacity();
        for (self.owned_grass_instances.items) |items| self.allocator.free(items);
        for (self.owned_grass_influencers.items) |items| self.allocator.free(items);
        self.owned_grass_instances.clearRetainingCapacity();
        self.owned_grass_influencers.clearRetainingCapacity();
        self.owned_instance_transforms.clearRetainingCapacity();
        self.commands.clearRetainingCapacity();
    }
};

const RenderTestContext = struct {
    submitted_count: usize = 0,
};

fn mockBeginFrame(context: *anyopaque) !void {
    _ = context;
}

fn mockSubmit(context: *anyopaque, command: RenderCommand, instance_transforms: []const [16]f32) !void {
    _ = command;
    _ = instance_transforms;
    const typed_context: *RenderTestContext = @ptrCast(@alignCast(context));
    typed_context.submitted_count += 1;
}

fn mockEndFrame(context: *anyopaque) !void {
    _ = context;
}

const mock_backend_vtable = BackendVTable{
    .beginFrame = mockBeginFrame,
    .submit = mockSubmit,
    .endFrame = mockEndFrame,
};

test "render abstraction queues and submits commands" {
    var renderer = RenderSystem.init(std.testing.allocator);
    defer renderer.deinit();

    var context = RenderTestContext{};
    renderer.setBackend(.{
        .context = &context,
        .vtable = &mock_backend_vtable,
    });

    try renderer.queue(.{
        .clear = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
    });
    try renderer.queue(.{
        .draw_mesh = .{
            .mesh_asset = 1,
            .material_asset = 2,
            .transform = [_]f32{1} ** 16,
        },
    });
    try renderer.queue(.{
        .draw_quad = .{
            .rect = .{ 0, 0, 100, 40 },
            .color = .{ 1, 1, 1, 1 },
        },
    });
    try renderer.flush();

    try std.testing.expectEqual(@as(usize, 3), context.submitted_count);
    try std.testing.expectEqual(@as(usize, 0), renderer.commands.items.len);
}

test "render abstraction owns queued text" {
    var renderer = RenderSystem.init(std.testing.allocator);
    defer renderer.deinit();

    try renderer.queueText(4, "Mahjuro", .{ 16, 24 }, 18, .{ 1, 1, 1, 1 });
    try std.testing.expectEqual(@as(usize, 1), renderer.commands.items.len);
    try renderer.flush();
    try std.testing.expectEqual(@as(usize, 0), renderer.commands.items.len);
}


test "render abstraction queues and owns grass batches" {
    var renderer = RenderSystem.init(std.testing.allocator);
    defer renderer.deinit();
    const instances = [_]GrassInstance{.{ .position = .{ 0, 0, 0 }, .normal = .{ 0, 1, 0 }, .color = .{ 80, 150, 70, 255 }, .height = 1, .width = 0.05, .yaw = 0, .phase = 0, .variant = 0 }};
    const Meta = struct { controls: struct { wind_direction_deg: f32, wind_speed_mps: f32, wind_strength: f32, bend_strength: f32, stiffness: f32 } };
    const meta = Meta{ .controls = .{ .wind_direction_deg = 225, .wind_speed_mps = 5, .wind_strength = 0.5, .bend_strength = 0.8, .stiffness = 0.7 } };
    try renderer.queueGrass(&instances, meta, &[_]GrassInfluencer{}, 1.0);
    try std.testing.expectEqual(@as(usize, 1), renderer.commands.items.len);
    try renderer.flush();
    try std.testing.expectEqual(@as(usize, 0), renderer.commands.items.len);
}
