const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const scene_io = shared.scene_io;
const shared_color = shared.color;
const editor_math = shared.editor_math;
const geometry = shared.geometry;
const scene_spawn = friendly_engine.game.scene_spawn;
const scene_animation = shared.scene_animation;
const scene_skinning = shared.scene_skinning;
const fps_controller = friendly_engine.modules.fps_player_controller;
const physics3d = friendly_engine.modules.physics3d;
const game_physics = friendly_engine.game.physics;
const luajit = friendly_engine.modules.luajit;

pub const TextureSize: u32 = 128;
const player_start_tag = "player_start";
const startup_camera_role = "startup_camera";
const fps_controller_component = "controller:fps";
const fps_camera_distance: f32 = 0.05;
const scripted_look_sensitivity: f32 = 0.0025;
const camera_collider_radius_m: f32 = 0.32;
const camera_spring_arm_samples: usize = 12;
const camera_spring_arm_margin_m: f32 = 0.08;
const debug_capsule_name = "__debug_scripted_controller_capsule";
const grass_influencer_property = "grass_influencer";

pub const CameraAngleStops = struct {
    min_pitch_rad: f32 = -1.2,
    max_pitch_rad: f32 = 1.2,
};

pub const NearCameraDissolveConfig = struct {
    dissolve_start_m: f32 = 1.25,
    dissolve_end_m: f32 = 0.35,
};

pub const camera_angle_stops = CameraAngleStops{};
pub const near_camera_dissolve = NearCameraDissolveConfig{};

pub const SceneObject = struct {
    id: u64 = 0,
    name: []u8 = "",
    mesh: geometry.Mesh,
    position: editor_math.Vec3,
    rotation: editor_math.Vec3 = .{ .x = 0, .y = 0, .z = 0 },
    scale: editor_math.Vec3,
    texture: []u8,
    base_color: shared_color.Color,
    properties: []shared.scene_document.Property = &.{},
    layer: []u8 = "",
    scatter_cull: ?friendly_engine.game.scatter_clusters.ScatterCull = null,
    skeleton_asset: ?[]u8 = null,
    bone_pose: []scene_animation.Transform = &.{},

    pub fn deinit(self: *SceneObject, allocator: std.mem.Allocator) void {
        if (self.name.len > 0) allocator.free(self.name);
        self.mesh.deinit(allocator);
        allocator.free(self.texture);
        for (self.properties) |*property| property.deinit(allocator);
        allocator.free(self.properties);
        if (self.layer.len > 0) allocator.free(self.layer);
        if (self.skeleton_asset) |asset| allocator.free(asset);
        allocator.free(self.bone_pose);
    }

    pub fn transform(self: *const SceneObject) editor_math.Mat4 {
        return editor_math.Mat4.mul(
            editor_math.Mat4.translation(self.position),
            editor_math.Mat4.mul(editor_math.Mat4.rotationEuler(self.rotation), editor_math.Mat4.scale(self.scale)),
        );
    }
};

pub const SceneView = struct {
    allocator: std.mem.Allocator,
    camera: editor_math.OrbitCamera = .{},
    objects: std.ArrayList(SceneObject),
    skeletons: std.ArrayList(scene_animation.Skeleton),
    animations: std.ArrayList(scene_animation.Clip),
    active_clip: ?usize = null,
    life_time: f32 = 0,
    life_playing: bool = false,
    controller_kind: ControllerKind = .none,
    fps_body_position: editor_math.Vec3 = .{ .x = 0, .y = 0, .z = 0 },
    fps_state: fps_controller.ControllerState = .{},
    fps_config: fps_controller.Config = .{
        .gravity_enabled = true,
        .walk_speed_mps = 4.0,
        .sprint_speed_mps = 9.0,
        .crouch_speed_mps = 2.0,
        .fly_speed_mps = 5.0,
    },
    fps_character: ?physics3d.character.Character = null,
    scripted_gem_name: ?[]u8 = null,
    scripted_component_name: ?[]u8 = null,
    scripted_actions: ?luajit.ScriptedControllerActions = null,
    scripted_body_position: editor_math.Vec3 = .{ .x = 0, .y = 0, .z = 0 },
    scripted_camera_yaw_rad: f32 = 0,
    scripted_camera_pitch_rad: f32 = 0.1,
    scripted_character: ?physics3d.character.Character = null,
    scripted_debug_capsule_index: ?usize = null,

    pub const ControllerKind = enum {
        none,
        fps,
        scripted_lua,
    };

    pub const DebugCapsuleDraw = struct {
        mesh_index: usize,
        transform: [16]f32,
    };

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32) !SceneView {
        _ = width;
        _ = height;
        return .{
            .allocator = allocator,
            .objects = .empty,
            .skeletons = .empty,
            .animations = .empty,
        };
    }

    pub fn deinit(self: *SceneView) void {
        for (self.objects.items) |*obj| obj.deinit(self.allocator);
        self.objects.deinit(self.allocator);
        for (self.skeletons.items) |*skeleton| skeleton.deinit(self.allocator);
        self.skeletons.deinit(self.allocator);
        for (self.animations.items) |*clip| clip.deinit(self.allocator);
        self.animations.deinit(self.allocator);
        self.destroyCharacters();
    }

    /// Tears down the live Jolt characters. Only call this on a genuine scene
    /// (re)load, not from `clearSceneData`/streaming syncs — those need the
    /// characters (and their velocity/ground-state continuity) to survive.
    fn destroyCharacters(self: *SceneView) void {
        if (self.fps_character) |*character| character.deinit();
        self.fps_character = null;
        if (self.scripted_character) |*character| character.deinit();
        self.scripted_character = null;
    }

    pub fn loadFromProject(
        self: *SceneView,
        io: std.Io,
        project_path: []const u8,
        scene_rel_path: []const u8,
        bundle: ?*const friendly_engine.framework.bundle_loader.RuntimeBundle,
    ) !void {
        var loaded = try scene_io.loadScene(self.allocator, io, project_path, scene_rel_path, bundle);
        defer loaded.deinit(self.allocator);
        try self.loadFromScene(loaded);
    }

    pub fn loadFromScene(self: *SceneView, loaded: scene_io.LoadedScene) !void {
        self.destroyCharacters();
        self.clearSceneData();
        try self.applyStartupControl(loaded.objects);

        for (loaded.objects) |entry| {
            if (!shouldRenderSceneObject(entry)) continue;
            try self.objects.append(self.allocator, .{
                .id = entry.id,
                .name = try self.allocator.dupe(u8, entry.name),
                .mesh = try geometry.duplicateMesh(self.allocator, &entry.mesh),
                .position = entry.position,
                .rotation = entry.rotation,
                .scale = entry.scale,
                .texture = try self.allocator.dupe(u8, entry.texture),
                .base_color = entry.base_color,
                .properties = try duplicateProperties(self.allocator, entry.properties),
                .layer = if (entry.layer.len > 0) try self.allocator.dupe(u8, entry.layer) else "",
                .skeleton_asset = if (entry.skeleton_asset) |asset| try self.allocator.dupe(u8, asset) else null,
                .bone_pose = try self.allocator.dupe(scene_animation.Transform, entry.bone_pose),
            });
        }
        for (loaded.skeletons) |skeleton| {
            const copies = try scene_animation.duplicateSkeletons(self.allocator, &.{skeleton});
            defer self.allocator.free(copies);
            try self.skeletons.append(self.allocator, copies[0]);
        }
        for (loaded.animations) |clip| {
            const copies = try scene_animation.duplicateClips(self.allocator, &.{clip});
            defer self.allocator.free(copies);
            try self.animations.append(self.allocator, copies[0]);
        }
        self.active_clip = if (self.animations.items.len > 0) 0 else null;
        self.life_time = 0;
        self.life_playing = self.active_clip != null;
        if (self.objects.items.len == 0) return error.EmptyScene;
        self.refreshSkinning();
    }

    fn applyStartupControl(self: *SceneView, objects: []const scene_io.SceneObjectData) !void {
        var found = false;
        var startup_camera: ?scene_io.SceneObjectData = null;
        for (objects) |entry| {
            if (isStartupCamera(entry)) startup_camera = entry;
            const gameplay = entry.gameplay orelse continue;
            if (!std.mem.eql(u8, gameplay.tag, player_start_tag)) continue;
            if (found) return error.DuplicatePlayerStart;
            found = true;

            if (propertyValue(entry, "controller_gem")) |gem_name| {
                const component_name = propertyValue(entry, "controller_component") orelse {
                    std.log.err(
                        "player start id={d} name=\"{s}\" uses controller_gem={s} but has no controller_component property",
                        .{ entry.id, entry.name, gem_name },
                    );
                    return error.MissingScriptedControllerComponent;
                };
                if (!hasComponent(entry.components, component_name)) {
                    std.log.err(
                        "player start id={d} name=\"{s}\" references controller_component={s} but does not list that component",
                        .{ entry.id, entry.name, component_name },
                    );
                    return error.MissingScriptedControllerComponent;
                }
                self.controller_kind = .scripted_lua;
                self.scripted_gem_name = try self.allocator.dupe(u8, gem_name);
                self.scripted_component_name = try self.allocator.dupe(u8, component_name);
                self.scripted_actions = try luajit.runtime().controllerActions(gem_name, self.allocator);
                self.scripted_body_position = entry.position;
                self.scripted_camera_yaw_rad = entry.rotation.y;
                self.scripted_camera_pitch_rad = clampCameraPitch(entry.rotation.x);
                self.camera.yaw = entry.rotation.y;
                self.camera.pitch = self.scripted_camera_pitch_rad;
                self.camera.distance = 5.2;
                self.camera.target = .{ .x = entry.position.x, .y = entry.position.y + 1.45, .z = entry.position.z };
                try self.ensureScriptedDebugCapsule();
                return;
            }

            if (!hasComponent(entry.components, fps_controller_component)) continue;
            self.camera.yaw = entry.rotation.y;
            self.camera.pitch = clampCameraPitch(entry.rotation.x);
            self.camera.distance = fps_camera_distance;
            self.controller_kind = .fps;
            self.fps_body_position = entry.position;
            self.fps_state = .{
                .yaw_rad = self.camera.yaw,
                .pitch_rad = self.camera.pitch,
                .grounded = true,
            };
            self.syncCameraFromFps();
            return;
        }

        if (startup_camera) |camera_object| {
            applyStartupCamera(self, camera_object);
            return;
        }
        return error.MissingStartupCamera;
    }

    pub fn fpsActive(self: *const SceneView) bool {
        return self.controller_kind == .fps;
    }

    pub fn activeControllerKind(self: *const SceneView) ControllerKind {
        return self.controller_kind;
    }

    pub fn scriptedActions(self: *const SceneView) ?*const luajit.ScriptedControllerActions {
        if (self.scripted_actions) |*actions| return actions;
        return null;
    }

    pub fn grassInfluencers(self: *const SceneView, out: []friendly_engine.game.grass_clusters.Influencer) []const friendly_engine.game.grass_clusters.Influencer {
        var count: usize = 0;
        const player_position = switch (self.controller_kind) {
            .none => null,
            .fps => self.fps_body_position,
            .scripted_lua => self.scripted_body_position,
        };
        if (player_position) |position| {
            appendGrassInfluencer(out, &count, position, 1.85, 1.0);
        }
        for (self.objects.items) |obj| {
            if (!sceneObjectGrassInfluencer(&obj)) continue;
            appendGrassInfluencer(out, &count, obj.position, 1.5 * @max(0.5, obj.scale.x), 0.85);
        }
        return out[0..count];
    }

    pub fn updateActiveController(
        self: *SceneView,
        input_system: *const friendly_engine.framework.input.InputSystem,
        dt_seconds: f32,
        look_delta_x: f32,
        look_delta_y: f32,
        physics: ?*game_physics.GamePhysicsState,
    ) !void {
        switch (self.controller_kind) {
            .none => return,
            .fps => try self.updateFpsController(input_system, dt_seconds, look_delta_x, look_delta_y, physics),
            .scripted_lua => try self.updateScriptedController(input_system, dt_seconds, look_delta_x, look_delta_y, physics),
        }
        if (physics) |state| self.applyCameraSpringArm(state);
    }

    fn updateFpsController(
        self: *SceneView,
        input_system: *const friendly_engine.framework.input.InputSystem,
        dt_seconds: f32,
        look_delta_x: f32,
        look_delta_y: f32,
        physics: ?*game_physics.GamePhysicsState,
    ) !void {
        const grounded = groundedFromCharacter(&self.fps_character);

        var input = fps_controller.inputFromActions(input_system, dt_seconds, grounded);
        input.look_delta_x = look_delta_x;
        input.look_delta_y = look_delta_y;
        const result = try fps_controller.updateController(
            &self.fps_state,
            self.fps_body_position,
            input,
            self.fps_config,
        );

        const gravity: friendly_engine.core.math.Vec3f = if (self.fps_config.gravity_enabled)
            .{ .x = 0, .y = self.fps_config.gravity_mps2, .z = 0 }
        else
            .{ .x = 0, .y = 0, .z = 0 };
        try stepCharacter(&self.fps_character, physics, &self.fps_body_position, result.velocity_mps, dt_seconds, gravity);
        self.syncCameraFromFps();
    }

    fn updateScriptedController(
        self: *SceneView,
        input_system: *const friendly_engine.framework.input.InputSystem,
        dt_seconds: f32,
        look_delta_x: f32,
        look_delta_y: f32,
        physics: ?*game_physics.GamePhysicsState,
    ) !void {
        const gem_name = self.scripted_gem_name orelse return;
        const actions = if (self.scripted_actions) |*value| value else return;
        self.scripted_camera_yaw_rad += look_delta_x * scripted_look_sensitivity;
        self.scripted_camera_pitch_rad = clampCameraPitch(self.scripted_camera_pitch_rad - look_delta_y * scripted_look_sensitivity);
        const grounded = groundedFromCharacter(&self.scripted_character);
        const position: friendly_engine.core.math.Vec3f = .{
            .x = self.scripted_body_position.x,
            .y = self.scripted_body_position.y,
            .z = self.scripted_body_position.z,
        };
        var result = try luajit.runtime().updateController(gem_name, .{
            .dt_seconds = dt_seconds,
            .position = position,
            .camera_yaw_rad = self.scripted_camera_yaw_rad,
            .camera_pitch_rad = self.scripted_camera_pitch_rad,
            .move_forward = isDown(input_system, actions.move_forward),
            .move_backward = isDown(input_system, actions.move_backward),
            .strafe_left = isDown(input_system, actions.strafe_left),
            .strafe_right = isDown(input_system, actions.strafe_right),
            .sprint = isDown(input_system, actions.sprint),
            .crouch = isDown(input_system, actions.crouch),
            .jump_pressed = isPressed(input_system, actions.jump),
            .climb = if (actions.climb) |action| isDown(input_system, action) else false,
            .ascend = isDown(input_system, actions.ascend),
            .descend = isDown(input_system, actions.descend),
            .interact_pressed = isPressed(input_system, actions.interact),
            .grounded = grounded,
        }, self.allocator);
        defer result.deinit(self.allocator);

        try stepCharacter(
            &self.scripted_character,
            physics,
            &self.scripted_body_position,
            result.velocity_mps,
            dt_seconds,
            .{ .x = 0, .y = 0, .z = 0 },
        );
        if (result.camera) |camera_result| {
            applyScriptedCamera(self, camera_result);
        }
        self.updateScriptedDebugCapsule();
    }

    fn syncCameraFromFps(self: *SceneView) void {
        self.camera.yaw = self.fps_state.yaw_rad;
        self.camera.pitch = self.fps_state.pitch_rad;
        self.camera.distance = fps_camera_distance;
        const eye = fps_controller.eyePosition(self.fps_body_position, self.fps_state, self.fps_config);
        self.camera.target = editor_math.Vec3.add(eye, editor_math.Vec3.scale(self.camera.forward(), self.camera.distance));
    }

    fn applyCameraSpringArm(self: *SceneView, physics: *const game_physics.GamePhysicsState) void {
        const desired_distance = self.camera.distance;
        if (!std.math.isFinite(desired_distance) or desired_distance <= self.camera.min_distance) return;

        const target = self.camera.target;
        const ideal_eye = self.camera.eye();
        const arm = editor_math.Vec3.sub(ideal_eye, target);
        var safe_t: f32 = 1.0;
        var previous_t: f32 = 0.0;
        var sample_index: usize = 1;
        while (sample_index <= camera_spring_arm_samples) : (sample_index += 1) {
            const t = @as(f32, @floatFromInt(sample_index)) / @as(f32, @floatFromInt(camera_spring_arm_samples));
            const point = editor_math.Vec3.add(target, editor_math.Vec3.scale(arm, t));
            if (cameraPointPenetrates(physics, point, camera_collider_radius_m)) {
                safe_t = refineCameraArmT(physics, target, arm, previous_t, t);
                break;
            }
            previous_t = t;
        }

        if (safe_t >= 0.999) return;
        const compressed = @max(self.camera.min_distance, desired_distance * safe_t - camera_spring_arm_margin_m);
        self.camera.distance = compressed;
    }

    pub fn loadDefault(self: *SceneView) !void {
        self.destroyCharacters();
        self.clearSceneData();

        const mesh = try geometry.buildPrimitive(self.allocator, .box, .{});
        const tex = try self.allocator.alloc(u8, TextureSize * TextureSize * 4);
        @memset(tex, 170);

        try self.objects.append(self.allocator, .{
            .mesh = mesh,
            .position = .{ .x = 0, .y = 0.5, .z = 0 },
            .scale = .{ .x = 1, .y = 1, .z = 1 },
            .texture = tex,
            .base_color = .{ .r = 170, .g = 180, .b = 195, .a = 255 },
        });
    }

    pub fn syncFromSpawnState(self: *SceneView, state: *scene_spawn.SceneSpawnState) !void {
        self.clearSceneData();

        for (state.meshes.items) |*stored| {
            const verts = try self.allocator.alloc(geometry.Vertex, stored.vertices.len);
            errdefer self.allocator.free(verts);
            for (stored.vertices, 0..) |src, i| {
                verts[i] = .{
                    .position = src.position,
                    .normal = src.normal,
                    .uv = src.uv,
                };
            }
            const indices = try self.allocator.dupe(u32, stored.indices);
            errdefer self.allocator.free(indices);

            try self.objects.append(self.allocator, .{
                .mesh = .{ .vertices = verts, .indices = indices },
                .position = .{ .x = 0, .y = 0, .z = 0 },
                .scale = .{ .x = 1, .y = 1, .z = 1 },
                .texture = try self.allocator.dupe(u8, stored.texture),
                .base_color = .{
                    .r = stored.base_color.r,
                    .g = stored.base_color.g,
                    .b = stored.base_color.b,
                    .a = stored.base_color.a,
                },
                .properties = &.{},
                .layer = if (spawnMeshLayer(stored.source_kind)) |layer| try self.allocator.dupe(u8, layer) else "",
            });
        }
    }

    pub fn syncFromSpawnStatePreservingPlayerCamera(self: *SceneView, state: *scene_spawn.SceneSpawnState) !void {
        const controller_kind = self.controller_kind;
        const saved_camera = self.camera;
        const saved_body_position = self.fps_body_position;
        const saved_fps_state = self.fps_state;
        const saved_fps_config = self.fps_config;
        const saved_scripted_position = self.scripted_body_position;
        const saved_scripted_camera_yaw = self.scripted_camera_yaw_rad;
        const saved_scripted_camera_pitch = self.scripted_camera_pitch_rad;
        const saved_scripted_gem_name = self.scripted_gem_name;
        const saved_scripted_component_name = self.scripted_component_name;
        const saved_scripted_actions = self.scripted_actions;
        self.scripted_gem_name = null;
        self.scripted_component_name = null;
        self.scripted_actions = null;

        try self.syncFromSpawnState(state);

        if (controller_kind != .none) {
            self.controller_kind = controller_kind;
            self.camera = saved_camera;
            self.fps_body_position = saved_body_position;
            self.fps_state = saved_fps_state;
            self.fps_config = saved_fps_config;
            self.scripted_body_position = saved_scripted_position;
            self.scripted_camera_yaw_rad = saved_scripted_camera_yaw;
            self.scripted_camera_pitch_rad = saved_scripted_camera_pitch;
            self.scripted_gem_name = saved_scripted_gem_name;
            self.scripted_component_name = saved_scripted_component_name;
            self.scripted_actions = saved_scripted_actions;
            if (controller_kind == .scripted_lua) {
                try self.ensureScriptedDebugCapsule();
                self.updateScriptedDebugCapsule();
            }
        } else {
            if (saved_scripted_gem_name) |name| self.allocator.free(name);
            if (saved_scripted_component_name) |name| self.allocator.free(name);
            if (saved_scripted_actions) |actions_value| {
                var actions = actions_value;
                actions.deinit(self.allocator);
            }
        }
    }

    pub fn update(self: *SceneView, dt: f32) void {
        if (!self.life_playing) return;
        const clip_idx = self.active_clip orelse return;
        if (clip_idx >= self.animations.items.len) return;
        const clip = self.animations.items[clip_idx];
        self.life_time += dt;
        if (self.life_time > clip.duration) {
            self.life_time = if (clip.looping) @mod(self.life_time, clip.duration) else clip.duration;
            if (!clip.looping) self.life_playing = false;
        }
        applyClip(self, clip);
        self.refreshSkinning();
    }

    pub fn refreshSkinning(self: *SceneView) void {
        for (self.objects.items) |*obj| {
            if (obj.mesh.skin == null) continue;
            const asset = obj.skeleton_asset orelse continue;
            const skeleton = scene_skinning.findSkeletonForAsset(self.skeletons.items, asset) orelse continue;
            scene_skinning.deformMesh(&obj.mesh, skeleton, obj.bone_pose);
        }
    }

    fn clearSceneData(self: *SceneView) void {
        for (self.objects.items) |*obj| obj.deinit(self.allocator);
        self.objects.clearRetainingCapacity();
        for (self.skeletons.items) |*skeleton| skeleton.deinit(self.allocator);
        self.skeletons.clearRetainingCapacity();
        for (self.animations.items) |*clip| clip.deinit(self.allocator);
        self.animations.clearRetainingCapacity();
        self.active_clip = null;
        self.life_time = 0;
        self.life_playing = false;
        self.controller_kind = .none;
        self.fps_state = .{};
        self.fps_body_position = .{ .x = 0, .y = 0, .z = 0 };
        if (self.scripted_gem_name) |name| self.allocator.free(name);
        if (self.scripted_component_name) |name| self.allocator.free(name);
        if (self.scripted_actions) |*actions| actions.deinit(self.allocator);
        self.scripted_gem_name = null;
        self.scripted_component_name = null;
        self.scripted_actions = null;
        self.scripted_body_position = .{ .x = 0, .y = 0, .z = 0 };
        self.scripted_camera_yaw_rad = 0;
        self.scripted_camera_pitch_rad = 0.1;
        self.scripted_debug_capsule_index = null;
    }

    pub fn scriptedDebugCapsuleDraw(self: *const SceneView) ?DebugCapsuleDraw {
        const index = self.scripted_debug_capsule_index orelse return null;
        if (index >= self.objects.items.len) return null;
        return .{
            .mesh_index = index,
            .transform = self.objects.items[index].transform().m,
        };
    }

    fn ensureScriptedDebugCapsule(self: *SceneView) !void {
        if (self.scripted_debug_capsule_index) |index| {
            if (index < self.objects.items.len) return;
        }

        const config = physics3d.character.CharacterConfig{};
        const texture = try self.allocator.alloc(u8, TextureSize * TextureSize * 4);
        errdefer self.allocator.free(texture);
        var px: usize = 0;
        while (px < texture.len) : (px += 4) {
            texture[px + 0] = 80;
            texture[px + 1] = 230;
            texture[px + 2] = 170;
            texture[px + 3] = 255;
        }

        const index = self.objects.items.len;
        try self.objects.append(self.allocator, .{
            .name = try self.allocator.dupe(u8, debug_capsule_name),
            .mesh = try geometry.buildCapsuleFeetOrigin(self.allocator, config.radius, config.standing_half_height, 24),
            .position = self.scripted_body_position,
            .scale = .{ .x = 1, .y = 1, .z = 1 },
            .texture = texture,
            .base_color = .{ .r = 80, .g = 230, .b = 170, .a = 255 },
        });
        self.scripted_debug_capsule_index = index;
    }

    fn updateScriptedDebugCapsule(self: *SceneView) void {
        const index = self.scripted_debug_capsule_index orelse return;
        if (index >= self.objects.items.len) return;
        self.objects.items[index].position = self.scripted_body_position;
    }
};

fn groundedFromCharacter(character_slot: *?physics3d.character.Character) bool {
    if (character_slot.*) |*character| return physics3d.character.isGrounded(character.groundState());
    return true;
}

/// Drives a player capsule through the real physics world when `physics` is
/// available, falling back to plain kinematic integration otherwise. Shared by
/// `updateFpsController` and `updateScriptedController` so the two controllers'
/// character lifecycle (and any future tuning) can't drift apart.
fn stepCharacter(
    character_slot: *?physics3d.character.Character,
    physics: ?*game_physics.GamePhysicsState,
    body_position: *editor_math.Vec3,
    velocity_mps: friendly_engine.core.math.Vec3f,
    dt_seconds: f32,
    gravity: friendly_engine.core.math.Vec3f,
) !void {
    if (physics) |state| {
        if (character_slot.* == null) {
            character_slot.* = try physics3d.character.Character.create(&state.physics_world, body_position.*, .{});
        }
        var character = &character_slot.*.?;
        character.setLinearVelocity(velocity_mps);
        character.update(dt_seconds, gravity);
        body_position.* = character.position();
    } else {
        try fps_controller.integratePosition(body_position, velocity_mps, dt_seconds);
    }
}

fn shouldRenderSceneObject(entry: scene_io.SceneObjectData) bool {
    if (isPlayerStart(entry)) return false;
    return shared.scene_marker_query.shouldRenderDrawable(entry);
}

fn isPlayerStart(entry: scene_io.SceneObjectData) bool {
    if (shared.scene_marker_query.hasMarkerKind(entry, .player_start)) return true;
    const gameplay = entry.gameplay orelse return false;
    return std.mem.eql(u8, gameplay.tag, player_start_tag);
}

fn hasComponent(components: []const []const u8, needle: []const u8) bool {
    for (components) |component| {
        if (std.mem.eql(u8, component, needle)) return true;
    }
    return false;
}

fn propertyValue(entry: scene_io.SceneObjectData, key: []const u8) ?[]const u8 {
    for (entry.properties) |property| {
        if (std.mem.eql(u8, property.key, key)) return property.value;
    }
    return null;
}

fn isStartupCamera(entry: scene_io.SceneObjectData) bool {
    if (entry.marker != null and shared.scene_marker_query.findFirstBinding(&.{entry}, .camera_point, startup_camera_role) != null) return true;
    return if (propertyValue(entry, "role")) |role| std.mem.eql(u8, role, startup_camera_role) else false;
}

fn propertyF32(entry: scene_io.SceneObjectData, key: []const u8) ?f32 {
    const value = propertyValue(entry, key) orelse return null;
    return std.fmt.parseFloat(f32, value) catch null;
}

fn isDown(input: *const friendly_engine.framework.input.InputSystem, action_name: []const u8) bool {
    return switch (input.getActionState(friendly_engine.framework.input.InputSystem.actionId(action_name))) {
        .pressed, .held => true,
        .up, .released => false,
    };
}

fn isPressed(input: *const friendly_engine.framework.input.InputSystem, action_name: []const u8) bool {
    return input.getActionState(friendly_engine.framework.input.InputSystem.actionId(action_name)) == .pressed;
}

fn refineCameraArmT(
    physics: *const game_physics.GamePhysicsState,
    target: editor_math.Vec3,
    arm: editor_math.Vec3,
    safe_start: f32,
    hit_start: f32,
) f32 {
    var safe = safe_start;
    var hit = hit_start;
    for (0..6) |_| {
        const mid = (safe + hit) * 0.5;
        const point = editor_math.Vec3.add(target, editor_math.Vec3.scale(arm, mid));
        if (cameraPointPenetrates(physics, point, camera_collider_radius_m)) {
            hit = mid;
        } else {
            safe = mid;
        }
    }
    return safe;
}

fn cameraPointPenetrates(physics: *const game_physics.GamePhysicsState, point: editor_math.Vec3, radius: f32) bool {
    const surface = cameraCollisionSurfaceY(physics, point) orelse return false;
    return point.y < surface + radius;
}

fn cameraCollisionSurfaceY(physics: *const game_physics.GamePhysicsState, point: editor_math.Vec3) ?f32 {
    var best: ?f32 = null;
    for (physics.physics_world.bodies.items) |body| {
        if (!body.is_static) continue;
        const surface = switch (body.shape) {
            .heightfield => |heightfield| sampleHeightfield(body.position, heightfield, point.x, point.z),
            .aabb => |aabb| sampleAabbTop(body.position, aabb, point.x, point.z),
            .sphere => null,
        } orelse continue;
        if (best == null or surface > best.?) best = surface;
    }
    return best;
}

fn sampleAabbTop(position: editor_math.Vec3, aabb: physics3d.Aabb, x: f32, z: f32) ?f32 {
    if (x < position.x - aabb.half_extents.x or x > position.x + aabb.half_extents.x) return null;
    if (z < position.z - aabb.half_extents.z or z > position.z + aabb.half_extents.z) return null;
    return position.y + aabb.half_extents.y;
}

fn sampleHeightfield(position: editor_math.Vec3, heightfield: physics3d.HeightField, x: f32, z: f32) ?f32 {
    if (heightfield.size < 2) return null;
    const span = @as(f32, @floatFromInt(heightfield.size - 1));
    if (heightfield.scale.x <= std.math.floatEps(f32) or heightfield.scale.z <= std.math.floatEps(f32)) return null;

    const local_x = (x - position.x - heightfield.offset.x) / heightfield.scale.x;
    const local_z = (z - position.z - heightfield.offset.z) / heightfield.scale.z;
    if (local_x < 0.0 or local_z < 0.0 or local_x > span or local_z > span) return null;

    const x0_float = @floor(local_x);
    const z0_float = @floor(local_z);
    const x0: usize = @intFromFloat(@min(x0_float, span - 1.0));
    const z0: usize = @intFromFloat(@min(z0_float, span - 1.0));
    const max_index: usize = @intCast(heightfield.size - 1);
    const x1 = @min(x0 + 1, max_index);
    const z1 = @min(z0 + 1, max_index);
    const tx = local_x - @as(f32, @floatFromInt(x0));
    const tz = local_z - @as(f32, @floatFromInt(z0));
    const size: usize = @intCast(heightfield.size);
    if (heightfield.heights.len < size * size) return null;

    const h00 = heightfield.heights[z0 * size + x0];
    const h10 = heightfield.heights[z0 * size + x1];
    const h01 = heightfield.heights[z1 * size + x0];
    const h11 = heightfield.heights[z1 * size + x1];
    const hx0 = std.math.lerp(h00, h10, tx);
    const hx1 = std.math.lerp(h01, h11, tx);
    return position.y + heightfield.offset.y + std.math.lerp(hx0, hx1, tz) * heightfield.scale.y;
}

fn applyScriptedCamera(self: *SceneView, camera: luajit.ScriptedCamera) void {
    const distance = @sqrt(camera.offset.x * camera.offset.x + camera.offset.y * camera.offset.y + camera.offset.z * camera.offset.z);
    self.camera.target = .{ .x = camera.target.x, .y = camera.target.y, .z = camera.target.z };
    self.camera.distance = @max(distance, 0.05);
    const inv_distance = 1.0 / self.camera.distance;
    self.camera.pitch = clampCameraPitch(std.math.asin(camera.offset.y * inv_distance));
    self.camera.yaw = std.math.atan2(camera.offset.x, camera.offset.z);
}

fn applyStartupCamera(self: *SceneView, entry: scene_io.SceneObjectData) void {
    self.camera.target = entry.position;
    self.camera.yaw = entry.rotation.y;
    self.camera.pitch = clampCameraPitch(entry.rotation.x);
    self.camera.distance = propertyF32(entry, "camera_distance_m") orelse 8.0;
}

pub fn clampCameraPitch(pitch_rad: f32) f32 {
    return std.math.clamp(pitch_rad, camera_angle_stops.min_pitch_rad, camera_angle_stops.max_pitch_rad);
}

pub fn nearCameraDissolveAmount(distance_m: f32) f32 {
    const start = near_camera_dissolve.dissolve_start_m;
    const end = near_camera_dissolve.dissolve_end_m;
    if (!std.math.isFinite(distance_m) or start <= end) return 0.0;
    if (distance_m >= start) return 0.0;
    if (distance_m <= end) return 1.0;
    const t = std.math.clamp((start - distance_m) / (start - end), 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

pub fn shouldDissolveSceneObject(obj: *const SceneObject) bool {
    if (obj.name.len > 0 and std.mem.eql(u8, obj.name, debug_capsule_name)) return false;
    if (isTerrainSceneObject(obj)) return false;
    if (isNonDissolveLayer(obj.layer)) return false;
    return obj.mesh.vertices.len > 0 and obj.mesh.indices.len > 0;
}

fn isTerrainSceneObject(obj: *const SceneObject) bool {
    if (equalsIgnoreCase(obj.layer, "terrain")) return true;
    if (equalsIgnoreCase(obj.layer, "world.terrain")) return true;
    for (obj.properties) |property| {
        if (equalsIgnoreCase(property.key, "terrain") and isTruthy(property.value)) return true;
        if (equalsIgnoreCase(property.key, "type") and equalsIgnoreCase(property.value, "terrain")) return true;
        if (equalsIgnoreCase(property.key, "kind") and equalsIgnoreCase(property.value, "terrain")) return true;
        if (equalsIgnoreCase(property.key, "role") and equalsIgnoreCase(property.value, "terrain")) return true;
        if (equalsIgnoreCase(property.key, "spawn_surface") and equalsIgnoreCase(property.value, "terrain")) return true;
    }
    return false;
}

fn appendGrassInfluencer(
    out: []friendly_engine.game.grass_clusters.Influencer,
    count: *usize,
    position: editor_math.Vec3,
    radius: f32,
    strength: f32,
) void {
    if (count.* >= out.len) return;
    out[count.*] = .{
        .position = .{ position.x, position.y, position.z },
        .radius = radius,
        .strength = strength,
        .velocity_dir = .{ 0, 0, 0 },
    };
    count.* += 1;
}

fn sceneObjectGrassInfluencer(obj: *const SceneObject) bool {
    for (obj.properties) |property| {
        if (equalsIgnoreCase(property.key, grass_influencer_property) and isTruthy(property.value)) return true;
    }
    return false;
}

fn spawnMeshLayer(kind: scene_spawn.MeshSourceKind) ?[]const u8 {
    return switch (kind) {
        .generic => null,
        .terrain => "terrain",
        .water => "world.water",
        .internal => "internal",
    };
}

fn isNonDissolveLayer(layer: []const u8) bool {
    return equalsIgnoreCase(layer, "world.water") or
        equalsIgnoreCase(layer, "water") or
        equalsIgnoreCase(layer, "sky") or
        equalsIgnoreCase(layer, "debug") or
        equalsIgnoreCase(layer, "internal");
}

fn equalsIgnoreCase(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}

fn isTruthy(value: []const u8) bool {
    return equalsIgnoreCase(value, "true") or
        equalsIgnoreCase(value, "1") or
        equalsIgnoreCase(value, "yes");
}

fn duplicateProperties(allocator: std.mem.Allocator, properties: []const shared.scene_document.Property) ![]shared.scene_document.Property {
    var copy = try allocator.alloc(shared.scene_document.Property, properties.len);
    errdefer allocator.free(copy);
    var count: usize = 0;
    errdefer {
        for (copy[0..count]) |*property| property.deinit(allocator);
    }
    for (properties) |property| {
        copy[count] = try shared.scene_document.Property.duplicate(allocator, property);
        count += 1;
    }
    return copy;
}

fn applyClip(view: *SceneView, clip: scene_animation.Clip) void {
    for (clip.tracks) |track| {
        const transform = scene_animation.evaluateTrack(track, view.life_time) orelse continue;
        switch (track.target) {
            .object => |id| if (findObjectById(view, id)) |idx| {
                view.objects.items[idx].position = transform.position;
                view.objects.items[idx].rotation = transform.rotation;
                view.objects.items[idx].scale = transform.scale;
            },
            .bone => |target| if (findObjectById(view, target.object_id)) |idx| {
                if (target.bone_index < view.objects.items[idx].bone_pose.len) {
                    view.objects.items[idx].bone_pose[target.bone_index] = transform;
                }
            },
        }
    }
}

fn findObjectById(view: *SceneView, id: u64) ?usize {
    for (view.objects.items, 0..) |obj, idx| {
        if (obj.id == id) return idx;
    }
    return null;
}

test "scene view loads default scene" {
    var view = try SceneView.init(std.testing.allocator, 320, 240);
    defer view.deinit();

    try view.loadDefault();
    try std.testing.expectEqual(@as(usize, 1), view.objects.items.len);
}

test "camera pitch stops clamp below and above configured limits" {
    try std.testing.expectApproxEqAbs(camera_angle_stops.min_pitch_rad, clampCameraPitch(camera_angle_stops.min_pitch_rad - 1.0), 0.001);
    try std.testing.expectApproxEqAbs(camera_angle_stops.max_pitch_rad, clampCameraPitch(camera_angle_stops.max_pitch_rad + 1.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), clampCameraPitch(0.25), 0.001);
}

test "near camera dissolve amount is smooth and monotonic" {
    const start = near_camera_dissolve.dissolve_start_m;
    const end = near_camera_dissolve.dissolve_end_m;
    try std.testing.expectApproxEqAbs(@as(f32, 0), nearCameraDissolveAmount(start + 0.1), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1), nearCameraDissolveAmount(end - 0.1), 0.001);
    const far_mid = nearCameraDissolveAmount(start - 0.2);
    const near_mid = nearCameraDissolveAmount(end + 0.2);
    try std.testing.expect(far_mid > 0.0 and far_mid < 1.0);
    try std.testing.expect(near_mid > far_mid and near_mid < 1.0);
}

test "near camera dissolve excludes terrain objects" {
    var obj = try makeSceneViewTestObject(std.testing.allocator, 1, "Terrain", .mesh, .{ .x = 0, .y = 0, .z = 0 }, null, &.{});
    defer obj.deinit(std.testing.allocator);
    obj.properties = try makeProperties(std.testing.allocator, &.{
        .{ .key = "role", .value = "terrain" },
    });

    try std.testing.expect(!shouldDissolveSceneObject(&obj));
}

test "streamed terrain meshes keep terrain layer for dissolve exclusion" {
    var state = scene_spawn.SceneSpawnState.init(std.testing.allocator);
    defer state.deinit();

    const vertices = [_]scene_spawn.StoredVertex{
        .{ .position = .{ .x = 0, .y = 0, .z = 0 }, .normal = .{ .x = 0, .y = 1, .z = 0 }, .uv = .{ .x = 0, .y = 0 } },
        .{ .position = .{ .x = 1, .y = 0, .z = 0 }, .normal = .{ .x = 0, .y = 1, .z = 0 }, .uv = .{ .x = 1, .y = 0 } },
        .{ .position = .{ .x = 0, .y = 0, .z = 1 }, .normal = .{ .x = 0, .y = 1, .z = 0 }, .uv = .{ .x = 0, .y = 1 } },
    };
    const indices = [_]u32{ 0, 1, 2 };
    const texture = [_]u8{ 255, 255, 255, 255 };
    try state.meshes.append(std.testing.allocator, try scene_spawn.StoredMesh.init(std.testing.allocator, .{
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .vertices = &vertices,
        .indices = &indices,
        .texture = &texture,
        .base_color = .{ .r = 120, .g = 140, .b = 90, .a = 255 },
        .source_kind = .terrain,
    }));

    var view = try SceneView.init(std.testing.allocator, 320, 240);
    defer view.deinit();
    try view.syncFromSpawnState(&state);

    try std.testing.expectEqual(@as(usize, 1), view.objects.items.len);
    try std.testing.expectEqualStrings("terrain", view.objects.items[0].layer);
    try std.testing.expect(!shouldDissolveSceneObject(&view.objects.items[0]));
}

test "scene view starts camera at explicit fps player start and hides marker" {
    const objects = try std.testing.allocator.alloc(scene_io.SceneObjectData, 2);
    objects[0] = try makeSceneViewTestObject(std.testing.allocator, 1, "Floor", .mesh, .{ .x = 0, .y = 0, .z = 0 }, null, &.{});
    objects[1] = try makeSceneViewTestObject(std.testing.allocator, 2, "Player Start", .empty, .{ .x = 2, .y = 0.16, .z = 3 }, player_start_tag, &.{fps_controller_component});
    objects[1].rotation = .{ .x = 0.2, .y = -1.0, .z = 0 };
    var loaded = scene_io.LoadedScene{
        .objects = objects,
        .next_object_id = 3,
        .animations = try std.testing.allocator.alloc(scene_animation.Clip, 0),
        .skeletons = try std.testing.allocator.alloc(scene_animation.Skeleton, 0),
    };
    defer loaded.deinit(std.testing.allocator);

    var view = try SceneView.init(std.testing.allocator, 320, 240);
    defer view.deinit();

    try view.loadFromScene(loaded);

    try std.testing.expectEqual(@as(usize, 1), view.objects.items.len);
    try std.testing.expectEqual(@as(u64, 1), view.objects.items[0].id);
    const eye = view.camera.eye();
    try std.testing.expectApproxEqAbs(@as(f32, 2), eye.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.76), eye.y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 3), eye.z, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.2), view.camera.pitch, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), view.camera.yaw, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.05), view.camera.distance, 0.001);
}

test "scene view hides stale visible player start marker" {
    const objects = try std.testing.allocator.alloc(scene_io.SceneObjectData, 2);
    objects[0] = try makeSceneViewTestObject(std.testing.allocator, 1, "Floor", .mesh, .{ .x = 0, .y = 0, .z = 0 }, null, &.{});
    objects[1] = try makeSceneViewTestObject(std.testing.allocator, 2, "Player Start", .mesh, .{ .x = 2, .y = 0.16, .z = 3 }, player_start_tag, &.{fps_controller_component});
    objects[1].renderer_visible = true;
    var loaded = scene_io.LoadedScene{
        .objects = objects,
        .next_object_id = 3,
        .animations = try std.testing.allocator.alloc(scene_animation.Clip, 0),
        .skeletons = try std.testing.allocator.alloc(scene_animation.Skeleton, 0),
    };
    defer loaded.deinit(std.testing.allocator);

    var view = try SceneView.init(std.testing.allocator, 320, 240);
    defer view.deinit();

    try view.loadFromScene(loaded);

    try std.testing.expectEqual(@as(usize, 1), view.objects.items.len);
    try std.testing.expectEqual(@as(u64, 1), view.objects.items[0].id);
}

test "scene view allows no controller when startup camera is explicit" {
    const objects = try std.testing.allocator.alloc(scene_io.SceneObjectData, 2);
    objects[0] = try makeSceneViewTestObject(std.testing.allocator, 1, "Floor", .mesh, .{ .x = 0, .y = 0, .z = 0 }, null, &.{});
    objects[1] = try makeSceneViewTestObject(std.testing.allocator, 2, "Player Start", .empty, .{ .x = 2, .y = 0.16, .z = 3 }, player_start_tag, &.{});
    objects[1].properties = try makeProperties(std.testing.allocator, &.{
        .{ .key = "role", .value = startup_camera_role },
        .{ .key = "camera_distance_m", .value = "12" },
    });
    objects[1].rotation = .{ .x = 0.4, .y = 1.2, .z = 0 };
    var loaded = scene_io.LoadedScene{
        .objects = objects,
        .next_object_id = 3,
        .animations = try std.testing.allocator.alloc(scene_animation.Clip, 0),
        .skeletons = try std.testing.allocator.alloc(scene_animation.Skeleton, 0),
    };
    defer loaded.deinit(std.testing.allocator);

    var view = try SceneView.init(std.testing.allocator, 320, 240);
    defer view.deinit();

    try view.loadFromScene(loaded);

    try std.testing.expectEqual(SceneView.ControllerKind.none, view.activeControllerKind());
    try std.testing.expectApproxEqAbs(@as(f32, 12), view.camera.distance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.4), view.camera.pitch, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.2), view.camera.yaw, 0.001);
}

test "scene view rejects no-controller scene without startup camera" {
    const objects = try std.testing.allocator.alloc(scene_io.SceneObjectData, 2);
    objects[0] = try makeSceneViewTestObject(std.testing.allocator, 1, "Floor", .mesh, .{ .x = 0, .y = 0, .z = 0 }, null, &.{});
    objects[1] = try makeSceneViewTestObject(std.testing.allocator, 2, "Player Start", .empty, .{ .x = 2, .y = 0.16, .z = 3 }, player_start_tag, &.{});
    var loaded = scene_io.LoadedScene{
        .objects = objects,
        .next_object_id = 3,
        .animations = try std.testing.allocator.alloc(scene_animation.Clip, 0),
        .skeletons = try std.testing.allocator.alloc(scene_animation.Skeleton, 0),
    };
    defer loaded.deinit(std.testing.allocator);

    var view = try SceneView.init(std.testing.allocator, 320, 240);
    defer view.deinit();

    try std.testing.expectError(error.MissingStartupCamera, view.loadFromScene(loaded));
}

test "camera spring arm compresses before static ground collider" {
    var view = try SceneView.init(std.testing.allocator, 320, 240);
    defer view.deinit();
    view.camera.target = .{ .x = 0, .y = 1.0, .z = 0 };
    view.camera.yaw = 0;
    view.camera.pitch = -1.0;
    view.camera.distance = 5.0;

    var physics = game_physics.GamePhysicsState.init(std.testing.allocator);
    defer physics.deinit();
    try physics.physics_world.bodies.append(std.testing.allocator, .{
        .id = 1,
        .position = .{ .x = 0, .y = -0.1, .z = 0 },
        .previous_position = .{ .x = 0, .y = -0.1, .z = 0 },
        .velocity = .{ .x = 0, .y = 0, .z = 0 },
        .inv_mass = 0,
        .is_static = true,
        .friction = 0.6,
        .can_sleep = true,
        .is_sleeping = false,
        .sleep_timer = 0,
        .continuous_collision = true,
        .shape = .{ .aabb = .{ .half_extents = .{ .x = 100, .y = 0.1, .z = 100 } } },
    });

    view.applyCameraSpringArm(&physics);

    try std.testing.expect(view.camera.distance < 5.0);
    try std.testing.expect(view.camera.eye().y >= camera_collider_radius_m - 0.02);
}

fn makeSceneViewTestObject(
    allocator: std.mem.Allocator,
    id: u64,
    name: []const u8,
    object_kind: shared.scene_document.ObjectKind,
    position: editor_math.Vec3,
    gameplay_tag: ?[]const u8,
    component_names: []const []const u8,
) !scene_io.SceneObjectData {
    const tex = try allocator.alloc(u8, TextureSize * TextureSize * 4);
    errdefer allocator.free(tex);
    @memset(tex, 180);

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
        .mesh = try geometry.buildPrimitive(allocator, .box, .{}),
        .position = position,
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = tex,
        .base_color = .{ .r = 170, .g = 180, .b = 195, .a = 255 },
        .object_kind = object_kind,
        .components = components,
        .gameplay = gameplay,
        .bone_pose = try allocator.alloc(scene_animation.Transform, 0),
    };
}

const TestProperty = struct {
    key: []const u8,
    value: []const u8,
};

fn makeProperties(allocator: std.mem.Allocator, values: []const TestProperty) ![]shared.scene_document.Property {
    var properties = try allocator.alloc(shared.scene_document.Property, values.len);
    errdefer allocator.free(properties);
    var count: usize = 0;
    errdefer {
        for (properties[0..count]) |*property| property.deinit(allocator);
    }
    for (values) |value| {
        properties[count] = .{
            .key = try allocator.dupe(u8, value.key),
            .value = try allocator.dupe(u8, value.value),
        };
        count += 1;
    }
    return properties;
}

test "scene view grass influencers include active player" {
    var view = try SceneView.init(std.testing.allocator, 800, 600);
    defer view.deinit();
    view.controller_kind = .scripted_lua;
    view.scripted_body_position = .{ .x = 4, .y = 1, .z = -2 };
    var buffer: [friendly_engine.modules.grass.types.max_influencers]friendly_engine.game.grass_clusters.Influencer = undefined;
    const influencers = view.grassInfluencers(&buffer);
    try std.testing.expectEqual(@as(usize, 1), influencers.len);
    try std.testing.expectApproxEqAbs(@as(f32, 4), influencers[0].position[0], 0.001);
}

test "scene view grass influencers include tagged objects only" {
    var view = try SceneView.init(std.testing.allocator, 800, 600);
    defer view.deinit();
    try view.objects.append(std.testing.allocator, try makeSceneViewTestObject(std.testing.allocator, 10, "Tagged", .empty, .{ .x = 1, .y = 0, .z = 2 }, "", &.{}));
    view.objects.items[0].properties = try makeProperties(std.testing.allocator, &.{.{ "grass_influencer", "true" }});
    try view.objects.append(std.testing.allocator, try makeSceneViewTestObject(std.testing.allocator, 11, "Untagged", .empty, .{ .x = 8, .y = 0, .z = 9 }, "", &.{}));
    var buffer: [friendly_engine.modules.grass.types.max_influencers]friendly_engine.game.grass_clusters.Influencer = undefined;
    const influencers = view.grassInfluencers(&buffer);
    try std.testing.expectEqual(@as(usize, 1), influencers.len);
    try std.testing.expectApproxEqAbs(@as(f32, 1), influencers[0].position[0], 0.001);
}
