const std = @import("std");
const editor_math = @import("editor_math.zig");
const shared_color = @import("color.zig");
const scene_document = @import("scene_document.zig");
const render_visibility = @import("render_visibility.zig");
const render_fog = @import("render_fog.zig");

pub const max_point_lights = 4;

pub const SceneLight = struct {
    position: editor_math.Vec3,
    color: shared_color.Color,
    intensity: f32 = 1.0,
};

pub const FrameLighting = struct {
    shading_lit: bool = true,
    sun_direction: editor_math.Vec3 = defaultSunDirection(),
    sun_color: shared_color.Color = .{ .r = 255, .g = 248, .b = 230, .a = 255 },
    sun_intensity: f32 = 0.85,
    ambient: f32 = 0.22,
    point_lights: [max_point_lights]SceneLight = defaultPointLights(),
    point_light_count: u32 = 0,
    shadows_enabled: bool = true,
    fog: render_fog.FrameFog = .{},
    camera_position: editor_math.Vec3 = .{ .x = 0, .y = 0, .z = 0 },
};

fn defaultPointLights() [max_point_lights]SceneLight {
    const off: SceneLight = .{
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .color = .{ .r = 0, .g = 0, .b = 0, .a = 255 },
    };
    return [_]SceneLight{off} ** max_point_lights;
}

pub const GpuLightingUniforms = extern struct {
    ambient: [4]f32,
    sun_direction: [4]f32,
    sun_color: [4]f32,
    point_light_count: u32,
    receive_shadows: u32,
    shadows_enabled: u32,
    fog_enabled: u32,
    point_positions: [max_point_lights][4]f32,
    point_colors: [max_point_lights][4]f32,
    light_view_proj: [16]f32,
    fog_color: [4]f32,
    fog_distances: [4]f32,
    camera_position: [4]f32,
    material: [4]f32,
};

pub fn defaultSunDirection() editor_math.Vec3 {
    return editor_math.Vec3.normalized(.{ .x = 0.35, .y = -0.85, .z = 0.25 });
}

pub fn sunDirectionFromPreview(origin: editor_math.Vec3, target: editor_math.Vec3) editor_math.Vec3 {
    const delta = editor_math.Vec3.sub(target, origin);
    if (editor_math.Vec3.lengthSquared(delta) < 0.0001) return defaultSunDirection();
    return editor_math.Vec3.normalized(delta);
}

pub fn gatherEditorLights(
    lighting: *FrameLighting,
    objects: []const EditorLightObject,
    sun_origin: ?editor_math.Vec3,
    sun_target: ?editor_math.Vec3,
) void {
    if (sun_origin) |origin| {
        if (sun_target) |target| {
            lighting.sun_direction = sunDirectionFromPreview(origin, target);
        }
    }

    lighting.point_light_count = 0;
    for (objects) |obj| {
        if (!obj.enabled or obj.object_kind != .light) continue;
        if (lighting.point_light_count >= max_point_lights) break;
        const idx = lighting.point_light_count;
        lighting.point_lights[idx] = .{
            .position = obj.position,
            .color = obj.base_color,
            .intensity = 1.2,
        };
        lighting.point_light_count += 1;
    }
}

pub const EditorLightObject = struct {
    object_kind: scene_document.ObjectKind,
    enabled: bool,
    position: editor_math.Vec3,
    base_color: shared_color.Color,
};

pub fn packGpuLightingUniforms(
    lighting: FrameLighting,
    receive_shadows: bool,
    light_view_proj: editor_math.Mat4,
    dissolve_amount: f32,
    dissolve_inverted: bool,
) GpuLightingUniforms {
    var uniforms = std.mem.zeroes(GpuLightingUniforms);
    uniforms.ambient = .{ lighting.ambient, lighting.ambient, lighting.ambient, 1 };
    uniforms.sun_direction = .{
        lighting.sun_direction.x,
        lighting.sun_direction.y,
        lighting.sun_direction.z,
        lighting.sun_intensity,
    };
    uniforms.sun_color = colorToFloat4(lighting.sun_color);
    uniforms.point_light_count = lighting.point_light_count;
    uniforms.receive_shadows = if (receive_shadows) 1 else 0;
    uniforms.shadows_enabled = if (lighting.shadows_enabled) 1 else 0;
    uniforms.fog_enabled = if (lighting.fog.enabled) 1 else 0;
    uniforms.light_view_proj = light_view_proj.m;
    uniforms.fog_color = .{
        @as(f32, @floatFromInt(lighting.fog.color.r)) / 255.0,
        @as(f32, @floatFromInt(lighting.fog.color.g)) / 255.0,
        @as(f32, @floatFromInt(lighting.fog.color.b)) / 255.0,
        1,
    };
    const fog_density = render_fog.fogDensityFromSpan(lighting.fog.start_m, lighting.fog.end_m) catch 0;
    uniforms.fog_distances = .{
        lighting.fog.start_m,
        lighting.fog.end_m,
        fog_density,
        lighting.fog.height_falloff_k,
    };
    uniforms.camera_position = .{
        lighting.camera_position.x,
        lighting.camera_position.y,
        lighting.camera_position.z,
        1,
    };
    uniforms.material = .{ sanitizeUnit(dissolve_amount), if (dissolve_inverted) 1 else 0, 0, 0 };

    var i: u32 = 0;
    while (i < max_point_lights) : (i += 1) {
        const light = lighting.point_lights[i];
        uniforms.point_positions[i] = .{ light.position.x, light.position.y, light.position.z, 1 };
        uniforms.point_colors[i] = .{
            @as(f32, @floatFromInt(light.color.r)) / 255.0 * light.intensity,
            @as(f32, @floatFromInt(light.color.g)) / 255.0 * light.intensity,
            @as(f32, @floatFromInt(light.color.b)) / 255.0 * light.intensity,
            light.intensity,
        };
    }
    return uniforms;
}

pub fn directionalLightViewProjection(bounds: render_visibility.Bounds, sun_direction: editor_math.Vec3) editor_math.Mat4 {
    const center = bounds.center();
    const extent = boundsExtent(bounds);
    const half = @max(extent.x, @max(extent.y, extent.z)) + 8.0;
    const eye = editor_math.Vec3.add(center, editor_math.Vec3.scale(sun_direction, half * 2.0));
    const up: editor_math.Vec3 = if (@abs(sun_direction.y) > 0.95)
        .{ .x = 0, .y = 0, .z = 1 }
    else
        .{ .x = 0, .y = 1, .z = 0 };
    const view = editor_math.lookAt(eye, center, up);
    const ortho = editor_math.orthographic(-half, half, -half, half, 0.1, half * 4.0);
    return editor_math.Mat4.mul(ortho, view);
}

pub fn mergeSceneBounds(meshes: []const render_visibility.SceneMesh) render_visibility.Bounds {
    if (meshes.len == 0) {
        return .{
            .min = .{ .x = -4, .y = -1, .z = -4 },
            .max = .{ .x = 4, .y = 8, .z = 4 },
        };
    }
    var merged = meshes[0].bounds;
    for (meshes[1..]) |mesh| {
        merged.min.x = @min(merged.min.x, mesh.bounds.min.x);
        merged.min.y = @min(merged.min.y, mesh.bounds.min.y);
        merged.min.z = @min(merged.min.z, mesh.bounds.min.z);
        merged.max.x = @max(merged.max.x, mesh.bounds.max.x);
        merged.max.y = @max(merged.max.y, mesh.bounds.max.y);
        merged.max.z = @max(merged.max.z, mesh.bounds.max.z);
    }
    return merged;
}

pub fn shadeDiffuse(
    lighting: FrameLighting,
    world_pos: editor_math.Vec3,
    world_normal: editor_math.Vec3,
    base: shared_color.Color,
) shared_color.Color {
    if (!lighting.shading_lit) return base;

    const n = editor_math.Vec3.normalized(world_normal);
    var total: [3]f32 = .{
        lighting.ambient,
        lighting.ambient,
        lighting.ambient,
    };

    const sun = editor_math.Vec3.normalized(lighting.sun_direction);
    const sun_ndotl = @max(0, editor_math.Vec3.dot(n, editor_math.Vec3.scale(sun, -1)));
    total[0] += sun_ndotl * lighting.sun_intensity * @as(f32, @floatFromInt(lighting.sun_color.r)) / 255.0;
    total[1] += sun_ndotl * lighting.sun_intensity * @as(f32, @floatFromInt(lighting.sun_color.g)) / 255.0;
    total[2] += sun_ndotl * lighting.sun_intensity * @as(f32, @floatFromInt(lighting.sun_color.b)) / 255.0;

    var i: u32 = 0;
    while (i < lighting.point_light_count) : (i += 1) {
        const light = lighting.point_lights[i];
        const to_light = editor_math.Vec3.sub(light.position, world_pos);
        const dist_sq = editor_math.Vec3.lengthSquared(to_light);
        if (dist_sq < 0.0001) continue;
        const atten = 1.0 / (1.0 + dist_sq * 0.02);
        const l = editor_math.Vec3.scale(to_light, 1.0 / @sqrt(dist_sq));
        const ndotl = @max(0, editor_math.Vec3.dot(n, l));
        total[0] += ndotl * atten * @as(f32, @floatFromInt(light.color.r)) / 255.0 * light.intensity;
        total[1] += ndotl * atten * @as(f32, @floatFromInt(light.color.g)) / 255.0 * light.intensity;
        total[2] += ndotl * atten * @as(f32, @floatFromInt(light.color.b)) / 255.0 * light.intensity;
    }

    return .{
        .r = scaleChannel(base.r, total[0]),
        .g = scaleChannel(base.g, total[1]),
        .b = scaleChannel(base.b, total[2]),
        .a = base.a,
    };
}

fn boundsExtent(bounds: render_visibility.Bounds) editor_math.Vec3 {
    return .{
        .x = (bounds.max.x - bounds.min.x) * 0.5,
        .y = (bounds.max.y - bounds.min.y) * 0.5,
        .z = (bounds.max.z - bounds.min.z) * 0.5,
    };
}

fn colorToFloat4(color: shared_color.Color) [4]f32 {
    return .{
        @as(f32, @floatFromInt(color.r)) / 255.0,
        @as(f32, @floatFromInt(color.g)) / 255.0,
        @as(f32, @floatFromInt(color.b)) / 255.0,
        @as(f32, @floatFromInt(color.a)) / 255.0,
    };
}

fn sanitizeUnit(value: f32) f32 {
    if (!std.math.isFinite(value)) return 0.0;
    return std.math.clamp(value, 0.0, 1.0);
}

test "gpu lighting uniforms carry clamped dissolve controls" {
    const uniforms = packGpuLightingUniforms(.{}, true, editor_math.Mat4.identity(), 1.4, true);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), uniforms.material[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), uniforms.material[1], 0.001);

    const none = packGpuLightingUniforms(.{}, true, editor_math.Mat4.identity(), -0.5, false);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), none.material[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), none.material[1], 0.001);
}

fn scaleChannel(channel: u8, factor: f32) u8 {
    return @intFromFloat(@min(255.0, @max(0.0, @as(f32, @floatFromInt(channel)) * factor)));
}

test "default sun direction is normalized" {
    const dir = defaultSunDirection();
    try std.testing.expect(@abs(editor_math.Vec3.length(dir) - 1.0) < 0.001);
}

test "gather editor lights collects point lights" {
    var lighting = FrameLighting{};
    const objects = [_]EditorLightObject{
        .{ .object_kind = .light, .enabled = true, .position = .{ .x = 1, .y = 2, .z = 3 }, .base_color = .{ .r = 255, .g = 200, .b = 100, .a = 255 } },
        .{ .object_kind = .mesh, .enabled = true, .position = .{ .x = 0, .y = 0, .z = 0 }, .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 } },
    };
    gatherEditorLights(&lighting, &objects, null, null);
    try std.testing.expectEqual(@as(u32, 1), lighting.point_light_count);
    try std.testing.expectEqual(@as(f32, 1), lighting.point_lights[0].position.x);
}

test "directional light view projection is finite" {
    const bounds = render_visibility.boundsFromTransform(editor_math.Mat4.identity().m);
    const m = directionalLightViewProjection(bounds, defaultSunDirection());
    for (m.m) |v| try std.testing.expect(std.math.isFinite(v));
}

test "shade diffuse brightens lit faces" {
    const lighting = FrameLighting{ .shading_lit = true };
    const sun_facing_normal = editor_math.Vec3.scale(defaultSunDirection(), -1);
    const lit = shadeDiffuse(lighting, .{ .x = 0, .y = 0, .z = 0 }, sun_facing_normal, .{ .r = 100, .g = 100, .b = 100, .a = 255 });
    const unlit = shadeDiffuse(.{ .shading_lit = false }, .{ .x = 0, .y = 0, .z = 0 }, sun_facing_normal, .{ .r = 100, .g = 100, .b = 100, .a = 255 });
    try std.testing.expect(lit.r > unlit.r);
}
