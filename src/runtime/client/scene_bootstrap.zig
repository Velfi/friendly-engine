const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const scene_spawn = friendly_engine.game.scene_spawn;
const scene_io = shared.scene_io;
const scene_marker_query = shared.scene_marker_query;
const player_start_tag = "player_start";

pub fn spawnFromLoaded(
    state: *scene_spawn.SceneSpawnState,
    world: *friendly_engine.framework.World,
    loaded: *scene_io.LoadedScene,
) !void {
    for (loaded.objects) |obj| {
        if (!shouldSpawnSceneObject(obj)) continue;
        if (!obj.renderer_visible) {
            if (authoredPhysics(obj.physics, obj.scale)) |physics_body| {
                _ = try state.spawnPhysicsBody(world, .{
                    .position = obj.position,
                    .scale = obj.scale,
                }, physics_body);
            }
            continue;
        }
        var verts: std.ArrayList(scene_spawn.StoredVertex) = .empty;
        defer verts.deinit(state.allocator);
        for (obj.mesh.vertices) |vert| {
            try verts.append(state.allocator, .{
                .position = vert.position,
                .normal = vert.normal,
                .uv = vert.uv,
            });
        }

        _ = try state.spawnObject(world, .{
            .position = obj.position,
            .scale = obj.scale,
            .vertices = verts.items,
            .indices = obj.mesh.indices,
            .texture = obj.texture,
            .base_color = .{
                .r = obj.base_color.r,
                .g = obj.base_color.g,
                .b = obj.base_color.b,
                .a = obj.base_color.a,
            },
            .physics = authoredPhysics(obj.physics, obj.scale),
        });
    }
}

fn shouldSpawnSceneObject(obj: scene_io.SceneObjectData) bool {
    if (isPlayerStart(obj)) return false;
    return scene_marker_query.shouldSpawnDrawable(obj);
}

fn isPlayerStart(obj: scene_io.SceneObjectData) bool {
    if (scene_marker_query.hasMarkerKind(obj, .player_start)) return true;
    const gameplay = obj.gameplay orelse return false;
    return std.mem.eql(u8, gameplay.tag, player_start_tag);
}

fn authoredPhysics(body: ?shared.scene_physics.Body, scale: shared.editor_math.Vec3) ?scene_spawn.ScenePhysicsBody {
    const authored = body orelse return null;
    const extents = friendly_engine.core.math.Vec3f{ .x = scale.x, .y = scale.y, .z = scale.z };
    return switch (authored.kind) {
        .static => scene_spawn.ScenePhysicsBody.staticAabb(extents),
        .dynamic => scene_spawn.ScenePhysicsBody.dynamicAabb(extents),
        .kinematic => .{
            .kind = .kinematic,
            .mass = 0.0,
            .shape = friendly_engine.game.physics_types.PhysicsShape.fromScale(extents),
        },
    };
}

test "scene bootstrap skips empty player start marker" {
    var world = friendly_engine.framework.World.init(std.testing.allocator);
    defer world.deinit();
    var state = scene_spawn.SceneSpawnState.init(std.testing.allocator);
    defer state.deinit();

    const objects = try std.testing.allocator.alloc(scene_io.SceneObjectData, 2);
    objects[0] = try makeBootstrapTestObject(std.testing.allocator, 1, "Floor", .mesh, &.{}, null);
    objects[1] = try makeBootstrapTestObject(std.testing.allocator, 2, "Player Start", .empty, &.{ "spawner", "controller:fps" }, player_start_tag);
    var loaded = scene_io.LoadedScene{
        .objects = objects,
        .next_object_id = 3,
        .animations = try std.testing.allocator.alloc(shared.scene_animation.Clip, 0),
        .skeletons = try std.testing.allocator.alloc(shared.scene_animation.Skeleton, 0),
    };
    defer loaded.deinit(std.testing.allocator);

    try spawnFromLoaded(&state, &world, &loaded);

    try std.testing.expectEqual(@as(usize, 1), state.entities.items.len);
    try std.testing.expectEqual(@as(usize, 1), state.meshes.items.len);
}

test "scene bootstrap skips stale visible player start marker" {
    var world = friendly_engine.framework.World.init(std.testing.allocator);
    defer world.deinit();
    var state = scene_spawn.SceneSpawnState.init(std.testing.allocator);
    defer state.deinit();

    const objects = try std.testing.allocator.alloc(scene_io.SceneObjectData, 2);
    objects[0] = try makeBootstrapTestObject(std.testing.allocator, 1, "Floor", .mesh, &.{}, null);
    objects[1] = try makeBootstrapTestObject(std.testing.allocator, 2, "Player Start", .mesh, &.{ "spawner", "controller:third_person" }, player_start_tag);
    objects[1].renderer_visible = true;
    objects[1].physics = .{ .kind = .static, .collider = .box, .mass = 0 };
    var loaded = scene_io.LoadedScene{
        .objects = objects,
        .next_object_id = 3,
        .animations = try std.testing.allocator.alloc(shared.scene_animation.Clip, 0),
        .skeletons = try std.testing.allocator.alloc(shared.scene_animation.Skeleton, 0),
    };
    defer loaded.deinit(std.testing.allocator);

    try spawnFromLoaded(&state, &world, &loaded);

    try std.testing.expectEqual(@as(usize, 1), state.entities.items.len);
    try std.testing.expectEqual(@as(usize, 1), state.meshes.items.len);
}

test "scene bootstrap keeps hidden collision without drawable mesh" {
    var world = friendly_engine.framework.World.init(std.testing.allocator);
    defer world.deinit();
    var state = scene_spawn.SceneSpawnState.init(std.testing.allocator);
    defer state.deinit();

    const objects = try std.testing.allocator.alloc(scene_io.SceneObjectData, 1);
    objects[0] = try makeBootstrapTestObject(std.testing.allocator, 1, "Hidden Wall Collision", .mesh, &.{}, null);
    objects[0].renderer_visible = false;
    objects[0].physics = .{ .kind = .static, .collider = .box, .mass = 0 };
    var loaded = scene_io.LoadedScene{
        .objects = objects,
        .next_object_id = 2,
        .animations = try std.testing.allocator.alloc(shared.scene_animation.Clip, 0),
        .skeletons = try std.testing.allocator.alloc(shared.scene_animation.Skeleton, 0),
    };
    defer loaded.deinit(std.testing.allocator);

    try spawnFromLoaded(&state, &world, &loaded);

    try std.testing.expectEqual(@as(usize, 1), state.entities.items.len);
    try std.testing.expectEqual(@as(usize, 0), state.meshes.items.len);
    try std.testing.expect(state.physics_bodies.get(state.entities.items[0]) != null);
    try std.testing.expect(state.drawables.get(state.entities.items[0]) == null);
}

fn makeBootstrapTestObject(
    allocator: std.mem.Allocator,
    id: u64,
    name: []const u8,
    object_kind: shared.scene_document.ObjectKind,
    component_names: []const []const u8,
    gameplay_tag: ?[]const u8,
) !scene_io.SceneObjectData {
    const tex = try allocator.alloc(u8, 128 * 128 * 4);
    errdefer allocator.free(tex);
    @memset(tex, 170);

    var components = try allocator.alloc([]u8, component_names.len);
    errdefer allocator.free(components);
    var component_count: usize = 0;
    errdefer {
        for (components[0..component_count]) |component| allocator.free(component);
    }
    for (component_names) |component| {
        components[component_count] = try allocator.dupe(u8, component);
        component_count += 1;
    }

    var gameplay: ?shared.scene_gameplay.Component = null;
    if (gameplay_tag) |tag| {
        gameplay = .{ .tag = try allocator.dupe(u8, tag) };
    }
    errdefer if (gameplay) |*component| component.deinit(allocator);

    return .{
        .id = id,
        .name = try allocator.dupe(u8, name),
        .mesh = try shared.geometry.buildPrimitive(allocator, .box, .{}),
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = tex,
        .base_color = .{ .r = 170, .g = 180, .b = 195, .a = 255 },
        .object_kind = object_kind,
        .components = components,
        .gameplay = gameplay,
        .bone_pose = try allocator.alloc(shared.scene_animation.Transform, 0),
    };
}

pub fn loadAndSpawn(
    allocator: std.mem.Allocator,
    io: std.Io,
    state: *scene_spawn.SceneSpawnState,
    world: *friendly_engine.framework.World,
    project_path: []const u8,
    scene_rel_path: []const u8,
    bundle: ?*const friendly_engine.framework.bundle_loader.RuntimeBundle,
) !void {
    var loaded = try scene_io.loadScene(allocator, io, project_path, scene_rel_path, bundle);
    defer loaded.deinit(allocator);
    try spawnFromLoaded(state, world, &loaded);
    if (state.entities.items.len == 0) return error.EmptyScene;
}
