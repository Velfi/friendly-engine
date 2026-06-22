const std = @import("std");
const core = @import("../core/mod.zig");
const framework = @import("../framework/mod.zig");
const world_mod = @import("../world/mod.zig");
pub const level_scene = @import("level_scene.zig");
pub const scene_spawn = @import("scene_spawn.zig");
pub const cell_spawn = @import("cell_spawn.zig");
pub const physics = @import("physics.zig");
pub const physics_types = @import("physics_types.zig");
pub const prop_asset_cache = @import("prop_asset_cache.zig");
pub const scatter_clusters = @import("scatter_clusters.zig");
pub const scatter_cull = @import("scatter_cull.zig");
pub const grass_clusters = @import("grass_clusters.zig");
const scatter_instancing = @import("scatter_instancing.zig");

const log = std.log.scoped(.game);

var active_scene: ?*scene_spawn.SceneSpawnState = null;
var active_cells: ?*cell_spawn.CellSpawnState = null;
var active_stream: ?*world_mod.stream.StreamManager = null;
var active_world: ?*framework.World = null;
var active_physics: ?*physics.GamePhysicsState = null;
var active_client_camera: ?core.math.Vec3f = null;
var active_grass_influencers: []const grass_clusters.Influencer = &.{};

pub fn setSceneState(state: ?*scene_spawn.SceneSpawnState) void {
    active_scene = state;
}

pub fn sceneState() ?*scene_spawn.SceneSpawnState {
    return active_scene;
}

pub fn setCellState(state: ?*cell_spawn.CellSpawnState) void {
    active_cells = state;
}

pub fn cellState() ?*cell_spawn.CellSpawnState {
    return active_cells;
}

pub fn setStreamManager(manager: ?*world_mod.stream.StreamManager) void {
    active_stream = manager;
}

pub fn streamManager() ?*world_mod.stream.StreamManager {
    return active_stream;
}

pub fn setActiveWorld(world: ?*framework.World) void {
    active_world = world;
}

pub fn activeWorld() ?*framework.World {
    return active_world;
}

pub fn syncPhysicsAfterCellChange() !void {
    const state = sceneState() orelse return;
    if (physicsState()) |physics_state| {
        try physics_state.syncScene(state);
    }
}

pub fn setPhysicsState(state: ?*physics.GamePhysicsState) void {
    active_physics = state;
}

pub fn physicsState() ?*physics.GamePhysicsState {
    return active_physics;
}

pub fn setClientCameraPosition(position: ?core.math.Vec3f) void {
    active_client_camera = position;
}

pub fn clientCameraPosition() ?core.math.Vec3f {
    return active_client_camera;
}

pub fn setGrassInfluencers(influencers: []const grass_clusters.Influencer) void {
    active_grass_influencers = influencers;
}

pub const ScatterDrawSubmission = struct {
    transform: [16]f32,
    color_alpha: f32,
};

pub fn scatterDrawSubmission(
    batch: scene_spawn.SceneSpawnState.DrawBatch,
    camera: ?core.math.Vec3f,
) ?ScatterDrawSubmission {
    var scale = batch.scale;
    var color_alpha: f32 = 1.0;
    if (batch.scatter_cull) |cull| {
        if (camera) |cam| {
            const fade = scatter_cull.scatterBatchFadeFactor(cull, cam, batch.position) orelse return null;
            scale = scatter_cull.uniformFadeScale(scale, fade);
            color_alpha = fade;
        }
    }
    return .{
        .transform = scene_spawn.objectTransformMatrix(.{
            .position = batch.position,
            .scale = scale,
        }),
        .color_alpha = color_alpha,
    };
}

pub fn shouldSubmitDrawBatch(batch: scene_spawn.SceneSpawnState.DrawBatch, camera: ?core.math.Vec3f) bool {
    return scatterDrawSubmission(batch, camera) != null;
}

pub fn registerDefaults(world: *framework.World) !void {
    try framework.components.registerBuiltinComponents(&world.component_registry);
    _ = world.spawnEntity();
    try world.notifications.publish("game.defaults_registered", "{}");
}

pub fn tickClient(world: *framework.World) !void {
    try tickClientLifecycle(world, false);
}

pub fn tickClientLifecycle(world: *framework.World, startup_lifecycle: bool) !void {
    const clear_stage = lifecycleBegin(startup_lifecycle, "startup.game_tick.queue_clear");
    try world.renderer.queue(.{
        .clear = .{ .r = 0.02, .g = 0.02, .b = 0.04, .a = 1.0 },
    });
    lifecycleEnd(clear_stage);

    if (sceneState()) |state| {
        const physics_stage = lifecycleBegin(startup_lifecycle, "startup.game_tick.physics");
        if (physicsState()) |physics_state| {
            _ = try physics_state.stepSceneLifecycle(state, 1.0 / 60.0, startup_lifecycle);
        }
        lifecycleEnd(physics_stage);

        const draw_stage = lifecycleBegin(startup_lifecycle, "startup.game_tick.queue_drawables");
        var queued_drawables: usize = 0;
        for (state.entities.items) |entity| {
            const transform = state.transforms.get(entity) orelse continue;
            const drawable = state.drawables.get(entity) orelse continue;
            try world.renderer.queue(.{
                .draw_mesh = .{
                    .mesh_asset = drawable.mesh_asset,
                    .material_asset = drawable.material_asset,
                    .transform = scene_spawn.objectTransformMatrix(transform),
                    .double_sided = true,
                },
            });
            queued_drawables += 1;
        }
        if (startup_lifecycle) log.info("startup.game_tick.queue_drawables.count objects={d}", .{queued_drawables});
        lifecycleEnd(draw_stage);

        const scatter_stage = lifecycleBegin(startup_lifecycle, "startup.game_tick.queue_scatter");
        var scatter_groups = try scatter_instancing.groupVisibleScatterBatches(
            world.allocator,
            state.draw_batches.items,
            active_client_camera,
        );
        defer scatter_groups.deinit();
        if (startup_lifecycle) log.info("startup.game_tick.queue_scatter.groups count={d}", .{scatter_groups.groups.len});
        for (scatter_groups.groups) |group| {
            const mesh_asset = @as(core.AssetId, @intCast(group.mesh_index)) + 1;
            const material_asset = @as(core.AssetId, @intCast(group.mesh_index)) + 0x1_0000_0000;
            const transforms = scatter_groups.transforms[group.transform_offset .. group.transform_offset + group.transform_count];
            try world.renderer.queueMeshInstanced(mesh_asset, material_asset, transforms);
        }
        lifecycleEnd(scatter_stage);

        const grass_stage = lifecycleBegin(startup_lifecycle, "startup.game_tick.queue_grass");
        if (active_client_camera) |camera| {
            for (state.grass_batches.items) |batch| {
                const fade = grass_clusters.batchFadeFactor(batch.cull, camera, batch.center) orelse continue;
                try world.renderer.queueGrass(batch.instances, batch.meta, active_grass_influencers, fade);
            }
        }
        lifecycleEnd(grass_stage);
    }

    const publish_stage = lifecycleBegin(startup_lifecycle, "startup.game_tick.publish");
    try world.notifications.publish("runtime.client.tick", "{}");
    lifecycleEnd(publish_stage);
}

pub fn tickServer(world: *framework.World) !void {
    if (sceneState()) |state| {
        if (physicsState()) |physics_state| {
            _ = try physics_state.stepScene(state, 1.0 / 60.0);
        }
    }
    try world.notifications.publish("runtime.server.tick", "{}");
}

const LifecycleStage = struct {
    name: []const u8,
    start_ns: i128,
};

fn lifecycleBegin(enabled: bool, comptime name: []const u8) ?LifecycleStage {
    if (!enabled) return null;
    log.info("{s}.begin", .{name});
    return .{
        .name = name,
        .start_ns = core.diagnostics.scopedTimerStart(),
    };
}

fn lifecycleEnd(stage: ?LifecycleStage) void {
    if (stage) |value| {
        const elapsed_ns = core.diagnostics.scopedTimerElapsedNs(value.start_ns);
        const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, @floatFromInt(std.time.ns_per_ms));
        log.info("{s}.end elapsed_ms={d:.3}", .{ value.name, elapsed_ms });
    }
}
