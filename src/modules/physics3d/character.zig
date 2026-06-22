const std = @import("std");
const core = @import("../../core/mod.zig");
const zphy = @import("zphysics");
const world_mod = @import("mod.zig");

pub const GroundState = zphy.CharacterGroundState;

pub fn isGrounded(state: GroundState) bool {
    return state == .on_ground;
}

pub const CharacterConfig = struct {
    radius: f32 = 0.35,
    standing_half_height: f32 = 0.55,
    mass: f32 = 80.0,
    max_slope_deg: f32 = 50.0,
};

pub const Character = struct {
    handle: *zphy.CharacterVirtual,

    pub fn create(world: *world_mod.World, initial_position: core.math.Vec3f, config: CharacterConfig) !Character {
        const system = try world.ensureJoltSystem();

        const capsule_settings = try zphy.CapsuleShapeSettings.create(config.standing_half_height, config.radius);
        defer capsule_settings.asShapeSettings().release();
        const shape = try capsule_settings.asShapeSettings().createShape();
        errdefer shape.release();

        const settings = try zphy.CharacterVirtualSettings.create();
        defer settings.release();
        settings.base.up = .{ 0, 1, 0, 0 };
        settings.base.shape = shape;
        settings.base.max_slope_angle = std.math.degreesToRadians(config.max_slope_deg);
        settings.mass = config.mass;
        // CharacterVirtual tracks the base of the capsule, not its center; shift the
        // shape up by its half-extent so callers can pass/read a feet-level position
        // (matching fps_player_controller's body_position convention).
        const half_extent = config.standing_half_height + config.radius;
        settings.shape_offset = .{ 0, half_extent, 0, 0 };

        const handle = try zphy.CharacterVirtual.create(
            settings,
            .{ initial_position.x, initial_position.y, initial_position.z },
            .{ 0, 0, 0, 1 },
            system,
        );
        return .{ .handle = handle };
    }

    pub fn deinit(self: *Character) void {
        self.handle.destroy();
    }

    pub fn position(self: *const Character) core.math.Vec3f {
        const p = self.handle.getPosition();
        return .{ .x = @floatCast(p[0]), .y = @floatCast(p[1]), .z = @floatCast(p[2]) };
    }

    pub fn setLinearVelocity(self: *Character, velocity: core.math.Vec3f) void {
        self.handle.setLinearVelocity(.{ velocity.x, velocity.y, velocity.z });
    }

    pub fn groundState(self: *Character) GroundState {
        return self.handle.getGroundState();
    }

    pub fn update(self: *Character, dt: f32, gravity: core.math.Vec3f) void {
        self.handle.update(dt, .{ gravity.x, gravity.y, gravity.z }, .{});
    }
};
