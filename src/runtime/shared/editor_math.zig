const std = @import("std");
const core = @import("friendly_engine").core;

pub const Vec3 = core.math.Vec3f;
pub const Vec2 = core.math.Vec2f;
pub const editor_camera_near_m: f32 = 0.1;
pub const editor_camera_far_m: f32 = 32768.0;
pub const editor_camera_max_distance_m: f32 = 32768.0;

pub const Quat = struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,
    w: f32 = 1,

    pub fn identity() Quat {
        return .{};
    }

    pub fn normalized(q: Quat) !Quat {
        const len = @sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w);
        if (len <= std.math.floatEps(f32)) return error.InvalidArguments;
        const inv = 1.0 / len;
        return .{ .x = q.x * inv, .y = q.y * inv, .z = q.z * inv, .w = q.w * inv };
    }

    pub fn rotateVec3(q_raw: Quat, v: Vec3) !Vec3 {
        const q = try normalized(q_raw);
        const u: Vec3 = .{ .x = q.x, .y = q.y, .z = q.z };
        const uv = cross(u, v);
        const uuv = cross(u, uv);
        return Vec3.add(v, Vec3.add(Vec3.scale(uv, 2.0 * q.w), Vec3.scale(uuv, 2.0)));
    }
};

pub const Ray = struct {
    origin: Vec3,
    dir: Vec3,
};

pub const Mat4 = struct {
    m: [16]f32,

    pub fn identity() Mat4 {
        return .{ .m = .{
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1,
        } };
    }

    pub fn translation(v: Vec3) Mat4 {
        return .{ .m = .{
            1,   0,   0,   0,
            0,   1,   0,   0,
            0,   0,   1,   0,
            v.x, v.y, v.z, 1,
        } };
    }

    pub fn scale(v: Vec3) Mat4 {
        return .{ .m = .{
            v.x, 0,   0,   0,
            0,   v.y, 0,   0,
            0,   0,   v.z, 0,
            0,   0,   0,   1,
        } };
    }

    pub fn rotationX(angle: f32) Mat4 {
        const c = @cos(angle);
        const s = @sin(angle);
        return .{ .m = .{
            1, 0,  0, 0,
            0, c,  s, 0,
            0, -s, c, 0,
            0, 0,  0, 1,
        } };
    }

    pub fn rotationY(angle: f32) Mat4 {
        const c = @cos(angle);
        const s = @sin(angle);
        return .{ .m = .{
            c, 0, -s, 0,
            0, 1, 0,  0,
            s, 0, c,  0,
            0, 0, 0,  1,
        } };
    }

    pub fn rotationZ(angle: f32) Mat4 {
        const c = @cos(angle);
        const s = @sin(angle);
        return .{ .m = .{
            c,  s, 0, 0,
            -s, c, 0, 0,
            0,  0, 1, 0,
            0,  0, 0, 1,
        } };
    }

    pub fn rotationEuler(v: Vec3) Mat4 {
        return Mat4.mul(Mat4.rotationZ(v.z), Mat4.mul(Mat4.rotationY(v.y), Mat4.rotationX(v.x)));
    }

    pub fn mul(a: Mat4, b: Mat4) Mat4 {
        var out: Mat4 = .{ .m = undefined };
        for (0..4) |col| {
            for (0..4) |row| {
                var sum: f32 = 0;
                for (0..4) |k| {
                    sum += a.m[k * 4 + row] * b.m[col * 4 + k];
                }
                out.m[col * 4 + row] = sum;
            }
        }
        return out;
    }

    pub fn transformPoint(self: Mat4, p: Vec3) Vec3 {
        const x = p.x * self.m[0] + p.y * self.m[4] + p.z * self.m[8] + self.m[12];
        const y = p.x * self.m[1] + p.y * self.m[5] + p.z * self.m[9] + self.m[13];
        const z = p.x * self.m[2] + p.y * self.m[6] + p.z * self.m[10] + self.m[14];
        return .{ .x = x, .y = y, .z = z };
    }

    pub fn transformDir(self: Mat4, d: Vec3) Vec3 {
        const x = d.x * self.m[0] + d.y * self.m[4] + d.z * self.m[8];
        const y = d.x * self.m[1] + d.y * self.m[5] + d.z * self.m[9];
        const z = d.x * self.m[2] + d.y * self.m[6] + d.z * self.m[10];
        return .{ .x = x, .y = y, .z = z };
    }
};

pub const OrbitCamera = struct {
    target: Vec3 = .{ .x = 0, .y = 0.5, .z = 0 },
    yaw: f32 = 0.6,
    pitch: f32 = 0.35,
    distance: f32 = 6.0,
    fov_y: f32 = 1.0,
    min_distance: f32 = 1.0,
    max_distance: f32 = editor_camera_max_distance_m,
    near_clip_m: f32 = editor_camera_near_m,
    far_clip_m: f32 = editor_camera_far_m,

    pub fn eye(self: OrbitCamera) Vec3 {
        return Vec3.add(self.target, Vec3.scale(self.back(), self.distance));
    }

    pub fn viewMatrix(self: OrbitCamera) Mat4 {
        return lookAt(self.eye(), self.target, .{ .x = 0, .y = 1, .z = 0 });
    }

    pub fn orbit(self: *OrbitCamera, dx: f32, dy: f32) void {
        self.yaw -= dx * 0.005;
        self.pitch = core.math.clamp(self.pitch + dy * 0.005, -1.4, 1.4);
    }

    pub fn lookInPlace(self: *OrbitCamera, dx: f32, dy: f32) void {
        const eye_pos = self.eye();
        self.yaw -= dx * 0.005;
        self.pitch = core.math.clamp(self.pitch + dy * 0.005, -1.4, 1.4);
        self.target = Vec3.add(eye_pos, Vec3.scale(self.forward(), self.distance));
    }

    pub fn pan(self: *OrbitCamera, dx: f32, dy: f32) void {
        const eye_pos = self.eye();
        const view_forward = Vec3.normalized(Vec3.sub(self.target, eye_pos));
        const world_up: Vec3 = .{ .x = 0, .y = 1, .z = 0 };
        const view_right = Vec3.normalized(cross(view_forward, world_up));
        const view_up = Vec3.normalized(cross(view_right, view_forward));
        const scale = self.distance * 0.002;
        const delta = Vec3.add(Vec3.scale(view_right, -dx * scale), Vec3.scale(view_up, dy * scale));
        self.target = Vec3.add(self.target, delta);
    }

    pub fn zoom(self: *OrbitCamera, delta: f32) void {
        self.distance = core.math.clamp(self.distance * (1.0 - delta * 0.1), self.min_distance, self.max_distance);
    }

    pub fn walk(self: *OrbitCamera, local: Vec3, amount: f32) void {
        var delta: Vec3 = .{ .x = 0, .y = 0, .z = 0 };
        delta = Vec3.add(delta, Vec3.scale(self.forward(), local.z * amount));
        delta = Vec3.add(delta, Vec3.scale(self.right(), local.x * amount));
        delta = Vec3.add(delta, Vec3.scale(.{ .x = 0, .y = 1, .z = 0 }, local.y * amount));
        self.target = Vec3.add(self.target, delta);
    }

    pub fn forward(self: OrbitCamera) Vec3 {
        return Vec3.scale(self.back(), -1.0);
    }

    pub fn right(self: OrbitCamera) Vec3 {
        return Vec3.normalized(cross(self.forward(), .{ .x = 0, .y = 1, .z = 0 }));
    }

    fn back(self: OrbitCamera) Vec3 {
        const cp = @cos(self.pitch);
        const sp = @sin(self.pitch);
        const cy = @cos(self.yaw);
        const sy = @sin(self.yaw);
        return .{
            .x = cp * sy,
            .y = sp,
            .z = cp * cy,
        };
    }
};

pub const grid_line_extent: i32 = 10;

pub const GridDraw = struct {
    camera: OrbitCamera,
    anchor: Vec3 = .{ .x = 0, .y = 0, .z = 0 },
    step: f32 = 1.0,
    projection_mode: ProjectionMode = .perspective,

    pub fn centeredOnOrigin(camera: OrbitCamera, step: f32) GridDraw {
        return .{
            .camera = camera,
            .step = step,
        };
    }

    pub fn anchored(camera: OrbitCamera, target: Vec3, step: f32) GridDraw {
        return .{
            .camera = camera,
            .anchor = gridAnchorOrigin(target, step),
            .step = step,
        };
    }

    pub fn worldPoint(self: GridDraw, local_x: f32, local_z: f32) Vec3 {
        return .{
            .x = self.anchor.x + local_x * self.step,
            .y = 0,
            .z = self.anchor.z + local_z * self.step,
        };
    }

    pub fn modelMatrix(self: GridDraw) Mat4 {
        return Mat4.mul(Mat4.translation(self.anchor), Mat4.scale(.{ .x = self.step, .y = 1, .z = self.step }));
    }
};

pub fn gridAnchorOrigin(target: Vec3, step: f32) Vec3 {
    const spacing = @max(0.001, step);
    const half_extent = @as(f32, @floatFromInt(grid_line_extent)) * spacing;
    return .{
        .x = @floor((target.x - half_extent) / spacing) * spacing,
        .y = 0,
        .z = @floor((target.z - half_extent) / spacing) * spacing,
    };
}

pub fn cross(a: Vec3, b: Vec3) Vec3 {
    return .{
        .x = a.y * b.z - a.z * b.y,
        .y = a.z * b.x - a.x * b.z,
        .z = a.x * b.y - a.y * b.x,
    };
}

pub fn lookAt(eye: Vec3, center: Vec3, up: Vec3) Mat4 {
    const f = Vec3.normalized(Vec3.sub(center, eye));
    const s = Vec3.normalized(cross(f, up));
    const u = cross(s, f);

    return .{ .m = .{
        s.x,               u.x,               -f.x,             0,
        s.y,               u.y,               -f.y,             0,
        s.z,               u.z,               -f.z,             0,
        -Vec3.dot(s, eye), -Vec3.dot(u, eye), Vec3.dot(f, eye), 1,
    } };
}

pub const ProjectionMode = enum {
    perspective,
    orthographic,
};

pub fn projectionMatrix(camera: OrbitCamera, aspect: f32, mode: ProjectionMode) Mat4 {
    const near_clip = effectiveNearClip(camera);
    const far_clip = effectiveFarClip(camera);
    return switch (mode) {
        .perspective => perspective(camera.fov_y, aspect, near_clip, far_clip),
        .orthographic => blk: {
            const height = @max(1.0, camera.distance);
            const width = height * aspect;
            // Symmetric near/far keeps visible geometry in positive NDC z for the software renderer.
            break :blk orthographic(-width, width, -height, height, -far_clip, far_clip);
        },
    };
}

pub fn effectiveNearClip(camera: OrbitCamera) f32 {
    const scaled = camera.distance / 4096.0;
    return core.math.clamp(@max(camera.near_clip_m, scaled), camera.near_clip_m, 8.0);
}

pub fn effectiveFarClip(camera: OrbitCamera) f32 {
    const near_clip = effectiveNearClip(camera);
    return @max(camera.far_clip_m, camera.distance + camera.max_distance + near_clip);
}

pub fn viewProjectionMatrix(camera: OrbitCamera, aspect: f32, mode: ProjectionMode) Mat4 {
    const view = camera.viewMatrix();
    const proj = projectionMatrix(camera, aspect, mode);
    return Mat4.mul(proj, view);
}

pub fn projectWorldPoint(
    camera: OrbitCamera,
    world: Vec3,
    viewport_w: f32,
    viewport_h: f32,
    projection_mode: ProjectionMode,
) ?Vec2 {
    const aspect = viewport_w / @max(1.0, viewport_h);
    const vp = viewProjectionMatrix(camera, aspect, projection_mode);
    const x = world.x * vp.m[0] + world.y * vp.m[4] + world.z * vp.m[8] + vp.m[12];
    const y = world.x * vp.m[1] + world.y * vp.m[5] + world.z * vp.m[9] + vp.m[13];
    const z = world.x * vp.m[2] + world.y * vp.m[6] + world.z * vp.m[10] + vp.m[14];
    const w = world.x * vp.m[3] + world.y * vp.m[7] + world.z * vp.m[11] + vp.m[15];
    if (w <= 0.0001) return null;
    const inv_w = 1.0 / w;
    const ndc_z = z * inv_w;
    if (ndc_z < 0) return null;
    const ndc_x = x * inv_w;
    const ndc_y = y * inv_w;
    return .{
        .x = (ndc_x + 1.0) * 0.5 * viewport_w,
        .y = (1.0 - ndc_y) * 0.5 * viewport_h,
    };
}

pub fn perspective(fov_y: f32, aspect: f32, near: f32, far: f32) Mat4 {
    const f = 1.0 / @tan(fov_y * 0.5);
    const nf = 1.0 / (near - far);
    return .{ .m = .{
        f / aspect, 0, 0,                   0,
        0,          f, 0,                   0,
        0,          0, (far + near) * nf,   -1,
        0,          0, 2 * far * near * nf, 0,
    } };
}

pub fn orthographic(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) Mat4 {
    return .{ .m = .{
        2.0 / (right - left),               0,                                  0,                              0,
        0,                                  2.0 / (top - bottom),               0,                              0,
        0,                                  0,                                  -2.0 / (far - near),            0,
        -((right + left) / (right - left)), -((top + bottom) / (top - bottom)), -((far + near) / (far - near)), 1,
    } };
}

pub fn rayIntersectPlane(
    origin: Vec3,
    dir: Vec3,
    plane_y: f32,
) ?Vec3 {
    if (@abs(dir.y) < 0.000001) return null;
    const t = (plane_y - origin.y) / dir.y;
    if (t < 0) return null;
    return Vec3.add(origin, Vec3.scale(dir, t));
}

pub fn rayFromScreen(
    camera: OrbitCamera,
    screen_x: f32,
    screen_y: f32,
    viewport_w: f32,
    viewport_h: f32,
    projection_mode: ProjectionMode,
) Ray {
    const ndc_x = (2.0 * screen_x / viewport_w) - 1.0;
    const ndc_y = 1.0 - (2.0 * screen_y / viewport_h);
    const aspect = viewport_w / @max(1.0, viewport_h);
    const view = camera.viewMatrix();
    const inv_view = invertRigid(view);

    return switch (projection_mode) {
        .perspective => {
            const proj = perspective(camera.fov_y, aspect, effectiveNearClip(camera), effectiveFarClip(camera));
            const inv_proj = invertPerspective(proj);
            const ray_clip: Vec3 = .{ .x = ndc_x, .y = ndc_y, .z = 1.0 };
            const ray_eye = inv_proj.transformDir(ray_clip);
            const ray_world = inv_view.transformDir(.{ .x = ray_eye.x, .y = ray_eye.y, .z = -1.0 });
            return .{
                .origin = camera.eye(),
                .dir = Vec3.normalized(ray_world),
            };
        },
        .orthographic => {
            const height = @max(1.0, camera.distance);
            const width = height * aspect;
            const origin = inv_view.transformPoint(.{
                .x = ndc_x * width,
                .y = ndc_y * height,
                .z = 0,
            });
            const dir = Vec3.normalized(inv_view.transformDir(.{ .x = 0, .y = 0, .z = -1 }));
            return .{ .origin = origin, .dir = dir };
        },
    };
}

fn invertRigid(m: Mat4) Mat4 {
    const tx = m.m[12];
    const ty = m.m[13];
    const tz = m.m[14];
    return .{ .m = .{
        m.m[0],                                     m.m[4],                                     m.m[8],                                      0,
        m.m[1],                                     m.m[5],                                     m.m[9],                                      0,
        m.m[2],                                     m.m[6],                                     m.m[10],                                     0,
        -(m.m[0] * tx + m.m[1] * ty + m.m[2] * tz), -(m.m[4] * tx + m.m[5] * ty + m.m[6] * tz), -(m.m[8] * tx + m.m[9] * ty + m.m[10] * tz), 1,
    } };
}

fn invertPerspective(m: Mat4) Mat4 {
    const a = m.m[0];
    const b = m.m[5];
    const c = m.m[10];
    const d = m.m[11];
    const e = m.m[14];
    return .{ .m = .{
        1.0 / a, 0,       0,       0,
        0,       1.0 / b, 0,       0,
        0,       0,       0,       1.0 / e,
        0,       0,       1.0 / d, -c / (d * e),
    } };
}

test "orthographic ray stays parallel to camera forward" {
    const camera = OrbitCamera{ .distance = 8.0 };
    const left = rayFromScreen(camera, 100, 200, 400, 400, .orthographic);
    const right = rayFromScreen(camera, 300, 200, 400, 400, .orthographic);
    const forward = camera.forward();
    try std.testing.expectApproxEqAbs(forward.x, left.dir.x, 0.001);
    try std.testing.expectApproxEqAbs(forward.y, left.dir.y, 0.001);
    try std.testing.expectApproxEqAbs(forward.z, left.dir.z, 0.001);
    try std.testing.expectApproxEqAbs(left.dir.x, right.dir.x, 0.001);
    try std.testing.expectApproxEqAbs(left.dir.y, right.dir.y, 0.001);
    try std.testing.expectApproxEqAbs(left.dir.z, right.dir.z, 0.001);
    try std.testing.expect(left.origin.x != right.origin.x or left.origin.y != right.origin.y);
}

test "orthographic projection maps target to screen center" {
    const camera = OrbitCamera{ .target = .{ .x = 0, .y = 0.5, .z = 0 }, .distance = 6.0 };
    const vp = viewProjectionMatrix(camera, 1.0, .orthographic);
    const x = camera.target.x * vp.m[0] + camera.target.y * vp.m[4] + camera.target.z * vp.m[8] + vp.m[12];
    const y = camera.target.x * vp.m[1] + camera.target.y * vp.m[5] + camera.target.z * vp.m[9] + vp.m[13];
    const z = camera.target.x * vp.m[2] + camera.target.y * vp.m[6] + camera.target.z * vp.m[10] + vp.m[14];
    try std.testing.expectApproxEqAbs(0, x, 0.05);
    try std.testing.expectApproxEqAbs(0, y, 0.05);
    try std.testing.expect(z > 0);
}

test "large editor overview camera raises near clip for depth precision" {
    const camera = OrbitCamera{
        .distance = 8847.0,
        .max_distance = 21722.0,
        .far_clip_m = 30000.0,
    };
    try std.testing.expect(effectiveNearClip(camera) > editor_camera_near_m);
    try std.testing.expect(effectiveFarClip(camera) > camera.far_clip_m);
}

test "ray intersects ground plane" {
    const hit = rayIntersectPlane(
        .{ .x = 0, .y = 5, .z = 0 },
        .{ .x = 0, .y = -1, .z = 0 },
        0,
    );
    try std.testing.expect(hit != null);
    try std.testing.expectApproxEqAbs(@as(f32, 0), hit.?.y, 0.001);
}

test "mat4 identity transform" {
    const p = Vec3.init(1, 2, 3);
    const out = Mat4.identity().transformPoint(p);
    try std.testing.expectEqual(p.x, out.x);
    try std.testing.expectEqual(p.y, out.y);
    try std.testing.expectEqual(p.z, out.z);
}

test "grid anchor keeps target inside drawn extent" {
    const target = Vec3.init(128, 0, -32);
    const step: f32 = 8.0;
    const anchor = gridAnchorOrigin(target, step);
    const half_extent = @as(f32, @floatFromInt(grid_line_extent)) * step;
    try std.testing.expect(target.x >= anchor.x);
    try std.testing.expect(target.x <= anchor.x + 2 * half_extent);
    try std.testing.expect(target.z >= anchor.z);
    try std.testing.expect(target.z <= anchor.z + 2 * half_extent);
}

test "origin-centered grid keeps origin at mesh center" {
    const camera = OrbitCamera{};
    const step: f32 = 1.0;
    const grid = GridDraw.centeredOnOrigin(camera, step);
    try std.testing.expectEqual(@as(f32, 0), grid.anchor.x);
    try std.testing.expectEqual(@as(f32, 0), grid.anchor.y);
    try std.testing.expectEqual(@as(f32, 0), grid.anchor.z);
    try std.testing.expectEqual(@as(f32, -10), grid.worldPoint(-10, -10).x);
    try std.testing.expectEqual(@as(f32, -10), grid.worldPoint(-10, -10).z);
    try std.testing.expectEqual(@as(f32, 10), grid.worldPoint(10, 10).x);
    try std.testing.expectEqual(@as(f32, 10), grid.worldPoint(10, 10).z);
}
