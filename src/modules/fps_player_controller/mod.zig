const std = @import("std");
const core = @import("../../core/mod.zig");
const framework = @import("../../framework/mod.zig");
const ecs = @import("../ecs/mod.zig");
const physics3d = @import("../physics3d/mod.zig");
const water = @import("../water/mod.zig");

pub const module_name = "gem.fps_player_controller";
pub const dependencies = [_][]const u8{ecs.module_name};
pub const component_name = "controller:fps";
pub const interaction_request_name = "gameplay.interact";

pub const ActionNames = struct {
    pub const move_forward = "fps.move_forward";
    pub const move_backward = "fps.move_backward";
    pub const strafe_left = "fps.strafe_left";
    pub const strafe_right = "fps.strafe_right";
    pub const sprint = "fps.sprint";
    pub const crouch = "fps.crouch";
    pub const jump = "fps.jump";
    pub const interact = "fps.interact";
    pub const ascend = "fps.ascend";
    pub const descend = "fps.descend";
};

pub const LocomotionMode = enum {
    idle,
    walking,
    sprinting,
    crouching,
    airborne,
    swimming,
};

pub const Config = struct {
    walk_speed_mps: f32 = 4.0,
    sprint_speed_mps: f32 = 7.5,
    crouch_speed_mps: f32 = 1.8,
    air_control_speed_mps: f32 = 3.0,
    fly_speed_mps: f32 = 8.0,
    swim_speed_mps: f32 = 3.2,
    swim_vertical_speed_mps: f32 = 2.4,
    water_drag: f32 = 0.65,
    float_surface_offset_m: f32 = 0.35,
    breath_seconds: f32 = 30.0,
    jump_velocity_mps: f32 = 5.4,
    gravity_mps2: f32 = -16.0,
    stand_eye_height_m: f32 = 1.62,
    crouch_eye_height_m: f32 = 1.05,
    terrain_spawn_clearance_m: f32 = 0.16,
    look_sensitivity: f32 = 0.0025,
    invert_look_x: bool = true,
    invert_look_y: bool = true,
    max_pitch_rad: f32 = 1.45,
    interact_range_m: f32 = 3.0,
    gravity_enabled: bool = true,
};

pub const InputState = struct {
    dt_seconds: f32,
    look_delta_x: f32 = 0.0,
    look_delta_y: f32 = 0.0,
    move_forward: bool = false,
    move_backward: bool = false,
    strafe_left: bool = false,
    strafe_right: bool = false,
    sprint: bool = false,
    crouch: bool = false,
    jump_pressed: bool = false,
    interact_pressed: bool = false,
    ascend: bool = false,
    descend: bool = false,
    grounded: bool = false,
    water_query: ?water.WaterQuery = null,
};

pub const ControllerState = struct {
    yaw_rad: f32 = 0.0,
    pitch_rad: f32 = 0.0,
    vertical_velocity_mps: f32 = 0.0,
    breath_remaining_seconds: f32 = 30.0,
    grounded: bool = false,
    crouching: bool = false,
};

pub const Component = struct {
    config: Config = .{},
    state: ControllerState = .{},
};

pub const EcsState = struct {
    allocator: std.mem.Allocator,
    controllers: ecs.ComponentStorage(Component),

    pub fn init(allocator: std.mem.Allocator) EcsState {
        return .{
            .allocator = allocator,
            .controllers = ecs.ComponentStorage(Component).init(allocator),
        };
    }

    pub fn deinit(self: *EcsState) void {
        self.controllers.deinit();
    }

    pub fn attach(self: *EcsState, world: *const framework.World, entity: ecs.Entity, component: Component) !void {
        if (!world.ecs_world.isAlive(entity)) return error.UnknownEntity;
        try self.controllers.set(entity, component);
    }

    pub fn remove(self: *EcsState, entity: ecs.Entity) bool {
        return self.controllers.remove(entity);
    }

    pub fn get(self: *EcsState, entity: ecs.Entity) ?Component {
        return self.controllers.get(entity);
    }

    pub fn updateEntityPosition(
        self: *EcsState,
        entity: ecs.Entity,
        body_position: *core.math.Vec3f,
        input: InputState,
    ) !FrameResult {
        const controller = self.controllers.getPtr(entity) orelse return error.MissingFpsPlayerController;
        const result = try updateController(&controller.state, body_position.*, input, controller.config);
        try integratePosition(body_position, result.velocity_mps, input.dt_seconds);
        return result;
    }

    pub fn updatePhysicsBody(
        self: *EcsState,
        entity: ecs.Entity,
        body: *physics3d.RigidBody,
        input: InputState,
    ) !FrameResult {
        const controller = self.controllers.getPtr(entity) orelse return error.MissingFpsPlayerController;
        const result = try updateController(&controller.state, body.position, input, controller.config);
        applyVelocityToBody(body, result.velocity_mps);
        return result;
    }
};

pub const FrameResult = struct {
    velocity_mps: core.math.Vec3f,
    eye_position: core.math.Vec3f,
    forward: core.math.Vec3f,
    mode: LocomotionMode,
    jumped: bool,
    interact_requested: bool,
    breath_remaining_seconds: f32 = 0,
    out_of_breath: bool = false,
};

pub const InteractionTarget = struct {
    entity_id: core.EntityId,
    object_id: u64 = 0,
};

pub const TerrainHeightfield = struct {
    position: core.math.Vec3f,
    size: u32,
    offset: core.math.Vec3f,
    scale: core.math.Vec3f,
    heights: []const f32,
};

const component_fields = [_]framework.components.FieldDesc{
    .{ .name = "walk_speed_mps", .kind = .f32 },
    .{ .name = "sprint_speed_mps", .kind = .f32 },
    .{ .name = "crouch_speed_mps", .kind = .f32 },
    .{ .name = "swim_speed_mps", .kind = .f32 },
    .{ .name = "swim_vertical_speed_mps", .kind = .f32 },
    .{ .name = "water_drag", .kind = .f32 },
    .{ .name = "float_surface_offset_m", .kind = .f32 },
    .{ .name = "breath_seconds", .kind = .f32 },
    .{ .name = "jump_velocity_mps", .kind = .f32 },
    .{ .name = "stand_eye_height_m", .kind = .f32 },
    .{ .name = "crouch_eye_height_m", .kind = .f32 },
    .{ .name = "terrain_spawn_clearance_m", .kind = .f32 },
    .{ .name = "look_sensitivity", .kind = .f32 },
    .{ .name = "invert_look_x", .kind = .bool },
    .{ .name = "invert_look_y", .kind = .bool },
    .{ .name = "interact_range_m", .kind = .f32 },
    .{ .name = "gravity_enabled", .kind = .bool },
};

pub fn register(registry: anytype) !void {
    _ = registry;
}

pub fn start(world: *framework.World) !void {
    try world.component_registry.register(.{
        .name = component_name,
        .fields = &component_fields,
    });
    try world.input.routeActionByName(ActionNames.move_forward, component_name, 20, true);
    try world.input.routeActionByName(ActionNames.move_backward, component_name, 20, true);
    try world.input.routeActionByName(ActionNames.strafe_left, component_name, 20, true);
    try world.input.routeActionByName(ActionNames.strafe_right, component_name, 20, true);
    try world.input.routeActionByName(ActionNames.sprint, component_name, 20, true);
    try world.input.routeActionByName(ActionNames.crouch, component_name, 20, true);
    try world.input.routeActionByName(ActionNames.jump, component_name, 20, true);
    try world.input.routeActionByName(ActionNames.ascend, component_name, 20, true);
    try world.input.routeActionByName(ActionNames.descend, component_name, 20, true);
    try world.input.routeActionByName(ActionNames.interact, component_name, 20, true);
    try world.notifications.publish("gem.fps_player_controller.started", "{}");
}

pub fn stop(world: *framework.World) !void {
    world.input.clearRoutesForOwner(component_name);
    try world.component_registry.unregister(component_name);
    try world.notifications.publish("gem.fps_player_controller.stopped", "{}");
}

pub fn inputFromActions(input: *const framework.input.InputSystem, dt_seconds: f32, grounded: bool) InputState {
    return .{
        .dt_seconds = dt_seconds,
        .move_forward = isDown(input, ActionNames.move_forward),
        .move_backward = isDown(input, ActionNames.move_backward),
        .strafe_left = isDown(input, ActionNames.strafe_left),
        .strafe_right = isDown(input, ActionNames.strafe_right),
        .sprint = isDown(input, ActionNames.sprint),
        .crouch = isDown(input, ActionNames.crouch),
        .jump_pressed = input.getActionState(framework.input.InputSystem.actionId(ActionNames.jump)) == .pressed,
        .interact_pressed = input.getActionState(framework.input.InputSystem.actionId(ActionNames.interact)) == .pressed,
        .ascend = isDown(input, ActionNames.ascend),
        .descend = isDown(input, ActionNames.descend),
        .grounded = grounded,
    };
}

pub fn updateController(
    state: *ControllerState,
    body_position: core.math.Vec3f,
    input: InputState,
    config: Config,
) !FrameResult {
    try validateConfig(config);
    if (!std.math.isFinite(input.dt_seconds) or input.dt_seconds < 0.0) return error.InvalidDeltaTime;

    const look_x_sign: f32 = if (config.invert_look_x) -1.0 else 1.0;
    const look_y_sign: f32 = if (config.invert_look_y) 1.0 else -1.0;
    state.yaw_rad += input.look_delta_x * config.look_sensitivity * look_x_sign;
    state.pitch_rad = std.math.clamp(
        state.pitch_rad + (input.look_delta_y * config.look_sensitivity * look_y_sign),
        -config.max_pitch_rad,
        config.max_pitch_rad,
    );
    state.grounded = input.grounded;
    state.crouching = input.crouch;

    const horizontal = horizontalMove(input, state.yaw_rad);
    const moving = core.math.Vec3f.lengthSquared(horizontal) > std.math.floatEps(f32);
    if (input.water_query) |query| {
        if (query.in_water and query.swimmable) {
            return updateSwimming(state, body_position, input, config, query, horizontal);
        }
    }
    state.breath_remaining_seconds = config.breath_seconds;
    var mode: LocomotionMode = .idle;
    var horizontal_speed = config.walk_speed_mps;
    if (state.crouching) {
        mode = .crouching;
        horizontal_speed = config.crouch_speed_mps;
    } else if (!state.grounded and config.gravity_enabled) {
        mode = .airborne;
        horizontal_speed = config.air_control_speed_mps;
    } else if (input.sprint and moving) {
        mode = .sprinting;
        horizontal_speed = config.sprint_speed_mps;
    } else if (moving) {
        mode = .walking;
    }

    var velocity = core.math.Vec3f.scale(horizontal, horizontal_speed);
    var jumped = false;
    if (config.gravity_enabled) {
        if (state.grounded and state.vertical_velocity_mps < 0.0) state.vertical_velocity_mps = 0.0;
        if (input.jump_pressed and state.grounded and !state.crouching) {
            state.vertical_velocity_mps = config.jump_velocity_mps;
            state.grounded = false;
            jumped = true;
            mode = .airborne;
        } else if (!state.grounded) {
            state.vertical_velocity_mps += config.gravity_mps2 * input.dt_seconds;
            mode = .airborne;
        }
        velocity.y = state.vertical_velocity_mps;
    } else {
        var vertical: f32 = 0.0;
        if (input.jump_pressed or input.ascend) vertical += 1.0;
        if (input.descend) vertical -= 1.0;
        velocity.y = vertical * config.fly_speed_mps;
    }

    return .{
        .velocity_mps = velocity,
        .eye_position = eyePosition(body_position, state.*, config),
        .forward = viewForward(state.*),
        .mode = mode,
        .jumped = jumped,
        .interact_requested = input.interact_pressed,
        .breath_remaining_seconds = state.breath_remaining_seconds,
        .out_of_breath = false,
    };
}

fn updateSwimming(
    state: *ControllerState,
    body_position: core.math.Vec3f,
    input: InputState,
    config: Config,
    query: water.WaterQuery,
    horizontal: core.math.Vec3f,
) FrameResult {
    state.grounded = false;
    state.crouching = false;
    state.vertical_velocity_mps = 0;

    var velocity = core.math.Vec3f.scale(horizontal, config.swim_speed_mps * config.water_drag);
    var vertical: f32 = 0;
    if (input.jump_pressed or input.ascend) vertical += 1;
    if (input.descend or input.crouch) vertical -= 1;
    if (vertical == 0 and body_position.y > query.surface_y - config.float_surface_offset_m) {
        velocity.y = @min(0, (query.surface_y - config.float_surface_offset_m) - body_position.y);
    } else {
        velocity.y = vertical * config.swim_vertical_speed_mps;
    }
    velocity = core.math.Vec3f.add(velocity, query.current);

    const eye_is_underwater = eyePosition(body_position, state.*, config).y < query.surface_y;
    if (eye_is_underwater) {
        state.breath_remaining_seconds = @max(0, state.breath_remaining_seconds - input.dt_seconds);
    } else {
        state.breath_remaining_seconds = @min(config.breath_seconds, state.breath_remaining_seconds + input.dt_seconds * 2);
    }

    return .{
        .velocity_mps = velocity,
        .eye_position = eyePosition(body_position, state.*, config),
        .forward = viewForward(state.*),
        .mode = .swimming,
        .jumped = false,
        .interact_requested = input.interact_pressed,
        .breath_remaining_seconds = state.breath_remaining_seconds,
        .out_of_breath = state.breath_remaining_seconds <= 0,
    };
}

pub fn integratePosition(position: *core.math.Vec3f, velocity_mps: core.math.Vec3f, dt_seconds: f32) !void {
    if (!std.math.isFinite(dt_seconds) or dt_seconds < 0.0) return error.InvalidDeltaTime;
    position.* = core.math.Vec3f.add(position.*, core.math.Vec3f.scale(velocity_mps, dt_seconds));
}

pub fn applyVelocityToBody(body: *physics3d.RigidBody, velocity_mps: core.math.Vec3f) void {
    body.velocity = velocity_mps;
    body.is_sleeping = false;
    body.sleep_timer = 0.0;
}

pub fn resolveTerrainSpawnPosition(
    authored_position: core.math.Vec3f,
    terrain_height_m: f32,
    config: Config,
) !core.math.Vec3f {
    try validateConfig(config);
    if (!std.math.isFinite(terrain_height_m)) return error.InvalidTerrainHeight;
    return .{
        .x = authored_position.x,
        .y = terrain_height_m + config.terrain_spawn_clearance_m,
        .z = authored_position.z,
    };
}

pub fn sampleTerrainHeightfield(surface: TerrainHeightfield, x: f32, z: f32) ?f32 {
    if (surface.size < 2) return null;
    if (surface.scale.x <= std.math.floatEps(f32) or surface.scale.z <= std.math.floatEps(f32)) return null;
    const span = @as(f32, @floatFromInt(surface.size - 1));
    const local_x = (x - surface.position.x - surface.offset.x) / surface.scale.x;
    const local_z = (z - surface.position.z - surface.offset.z) / surface.scale.z;
    if (local_x < 0.0 or local_z < 0.0 or local_x > span or local_z > span) return null;

    const x0_float = @floor(local_x);
    const z0_float = @floor(local_z);
    const x0: usize = @intFromFloat(@min(x0_float, span - 1.0));
    const z0: usize = @intFromFloat(@min(z0_float, span - 1.0));
    const max_index: usize = @intCast(surface.size - 1);
    const x1 = @min(x0 + 1, max_index);
    const z1 = @min(z0 + 1, max_index);
    const tx = local_x - @as(f32, @floatFromInt(x0));
    const tz = local_z - @as(f32, @floatFromInt(z0));
    const size: usize = @intCast(surface.size);
    if (surface.heights.len < size * size) return null;

    const h00 = surface.heights[z0 * size + x0];
    const h10 = surface.heights[z0 * size + x1];
    const h01 = surface.heights[z1 * size + x0];
    const h11 = surface.heights[z1 * size + x1];
    const hx0 = std.math.lerp(h00, h10, tx);
    const hx1 = std.math.lerp(h01, h11, tx);
    return surface.position.y + surface.offset.y + std.math.lerp(hx0, hx1, tz) * surface.scale.y;
}

pub fn sendInteractionRequest(
    world: *framework.World,
    target: InteractionTarget,
    origin: core.math.Vec3f,
    forward: core.math.Vec3f,
) ![]u8 {
    const payload = try interactionPayload(world.allocator, target, origin, forward);
    defer world.allocator.free(payload);
    return world.requests.request(interaction_request_name, payload);
}

pub fn interactionPayload(
    allocator: std.mem.Allocator,
    target: InteractionTarget,
    origin: core.math.Vec3f,
    forward: core.math.Vec3f,
) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "{{\"entity_id\":{d},\"object_id\":{d},\"origin\":[{d:.4},{d:.4},{d:.4}],\"forward\":[{d:.4},{d:.4},{d:.4}]}}",
        .{
            target.entity_id,
            target.object_id,
            origin.x,
            origin.y,
            origin.z,
            forward.x,
            forward.y,
            forward.z,
        },
    );
}

pub fn eyePosition(body_position: core.math.Vec3f, state: ControllerState, config: Config) core.math.Vec3f {
    const eye_height = if (state.crouching) config.crouch_eye_height_m else config.stand_eye_height_m;
    return .{ .x = body_position.x, .y = body_position.y + eye_height, .z = body_position.z };
}

pub fn viewForward(state: ControllerState) core.math.Vec3f {
    const pitch_cos = @cos(state.pitch_rad);
    return core.math.Vec3f.normalized(.{
        .x = -@sin(state.yaw_rad) * pitch_cos,
        .y = @sin(state.pitch_rad),
        .z = -@cos(state.yaw_rad) * pitch_cos,
    });
}

fn horizontalMove(input: InputState, yaw_rad: f32) core.math.Vec3f {
    var x: f32 = 0.0;
    var z: f32 = 0.0;
    if (input.move_forward) z -= 1.0;
    if (input.move_backward) z += 1.0;
    if (input.strafe_left) x -= 1.0;
    if (input.strafe_right) x += 1.0;
    const local = core.math.Vec3f.normalized(.{ .x = x, .y = 0.0, .z = z });
    const s = @sin(yaw_rad);
    const c = @cos(yaw_rad);
    return .{
        .x = (local.x * c) + (local.z * s),
        .y = 0.0,
        .z = (-local.x * s) + (local.z * c),
    };
}

fn isDown(input: *const framework.input.InputSystem, action_name: []const u8) bool {
    return switch (input.getActionState(framework.input.InputSystem.actionId(action_name))) {
        .pressed, .held => true,
        .up, .released => false,
    };
}

fn validateConfig(config: Config) !void {
    if (!std.math.isFinite(config.walk_speed_mps) or config.walk_speed_mps < 0.0) return error.InvalidConfig;
    if (!std.math.isFinite(config.sprint_speed_mps) or config.sprint_speed_mps < 0.0) return error.InvalidConfig;
    if (!std.math.isFinite(config.crouch_speed_mps) or config.crouch_speed_mps < 0.0) return error.InvalidConfig;
    if (!std.math.isFinite(config.air_control_speed_mps) or config.air_control_speed_mps < 0.0) return error.InvalidConfig;
    if (!std.math.isFinite(config.fly_speed_mps) or config.fly_speed_mps < 0.0) return error.InvalidConfig;
    if (!std.math.isFinite(config.swim_speed_mps) or config.swim_speed_mps < 0.0) return error.InvalidConfig;
    if (!std.math.isFinite(config.swim_vertical_speed_mps) or config.swim_vertical_speed_mps < 0.0) return error.InvalidConfig;
    if (!std.math.isFinite(config.water_drag) or config.water_drag < 0.0 or config.water_drag > 1.0) return error.InvalidConfig;
    if (!std.math.isFinite(config.float_surface_offset_m) or config.float_surface_offset_m < 0.0) return error.InvalidConfig;
    if (!std.math.isFinite(config.breath_seconds) or config.breath_seconds <= 0.0) return error.InvalidConfig;
    if (!std.math.isFinite(config.jump_velocity_mps) or config.jump_velocity_mps < 0.0) return error.InvalidConfig;
    if (!std.math.isFinite(config.gravity_mps2)) return error.InvalidConfig;
    if (!std.math.isFinite(config.terrain_spawn_clearance_m) or config.terrain_spawn_clearance_m < 0.0) return error.InvalidConfig;
    if (!std.math.isFinite(config.look_sensitivity) or config.look_sensitivity < 0.0) return error.InvalidConfig;
    if (!std.math.isFinite(config.max_pitch_rad) or config.max_pitch_rad <= 0.0) return error.InvalidConfig;
    if (!std.math.isFinite(config.interact_range_m) or config.interact_range_m <= 0.0) return error.InvalidConfig;
    if (config.crouch_eye_height_m > config.stand_eye_height_m) return error.InvalidConfig;
}

comptime {
    _ = @import("mod_tests.zig");
}
