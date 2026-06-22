const std = @import("std");
const shared = @import("runtime_shared");
const editor_math = shared.editor_math;
const SceneObject = @import("editor_scene_object.zig").SceneObject;
const scene_hierarchy = @import("editor_scene_hierarchy.zig");

pub const RayHit = struct {
    t: f32,
    uv: editor_math.Vec2,
    triangle: usize,
};

pub const SceneRayHit = struct {
    t: f32,
    uv: editor_math.Vec2,
    triangle: usize,
    position: editor_math.Vec3,
    normal: editor_math.Vec3,
    object_index: usize,
};

pub const RayTriangleHit = struct {
    t: f32,
    uv: editor_math.Vec2,
};

pub fn snapValue(value: f32, grid: f32) f32 {
    if (grid <= 0) return value;
    return @round(value / grid) * grid;
}

pub fn snapVec3(v: editor_math.Vec3, grid: f32) editor_math.Vec3 {
    if (grid <= 0) return v;
    return .{
        .x = snapValue(v.x, grid),
        .y = snapValue(v.y, grid),
        .z = snapValue(v.z, grid),
    };
}

pub fn objectWorldBounds(obj: *const SceneObject) struct { min: editor_math.Vec3, max: editor_math.Vec3 } {
    const xf = obj.transform();
    var min_v = editor_math.Vec3{ .x = std.math.inf(f32), .y = std.math.inf(f32), .z = std.math.inf(f32) };
    var max_v = editor_math.Vec3{ .x = -std.math.inf(f32), .y = -std.math.inf(f32), .z = -std.math.inf(f32) };
    for (obj.mesh.vertices) |vert| {
        const w = xf.transformPoint(vert.position);
        min_v.x = @min(min_v.x, w.x);
        min_v.y = @min(min_v.y, w.y);
        min_v.z = @min(min_v.z, w.z);
        max_v.x = @max(max_v.x, w.x);
        max_v.y = @max(max_v.y, w.y);
        max_v.z = @max(max_v.z, w.z);
    }
    return .{ .min = min_v, .max = max_v };
}

pub fn aabbOverlaps(
    a_min: editor_math.Vec3,
    a_max: editor_math.Vec3,
    b_min: editor_math.Vec3,
    b_max: editor_math.Vec3,
) bool {
    return a_min.x <= b_max.x and a_max.x >= b_min.x and
        a_min.y <= b_max.y and a_max.y >= b_min.y and
        a_min.z <= b_max.z and a_max.z >= b_min.z;
}

pub fn rayIntersectsAabb(
    origin: editor_math.Vec3,
    dir: editor_math.Vec3,
    min_v: editor_math.Vec3,
    max_v: editor_math.Vec3,
) bool {
    var t_min: f32 = 0;
    var t_max: f32 = std.math.inf(f32);
    const Axis = struct { o: f32, d: f32, min_a: f32, max_a: f32 };
    const axes = [_]Axis{
        .{ .o = origin.x, .d = dir.x, .min_a = min_v.x, .max_a = max_v.x },
        .{ .o = origin.y, .d = dir.y, .min_a = min_v.y, .max_a = max_v.y },
        .{ .o = origin.z, .d = dir.z, .min_a = min_v.z, .max_a = max_v.z },
    };
    for (axes) |axis| {
        const o = axis.o;
        const d = axis.d;
        const min_a = axis.min_a;
        const max_a = axis.max_a;
        if (@abs(d) < 0.000001) {
            if (o < min_a or o > max_a) return false;
            continue;
        }
        const inv_d = 1.0 / d;
        var t0 = (min_a - o) * inv_d;
        var t1 = (max_a - o) * inv_d;
        if (t0 > t1) std.mem.swap(f32, &t0, &t1);
        t_min = @max(t_min, t0);
        t_max = @min(t_max, t1);
        if (t_min > t_max) return false;
    }
    return t_max >= 0;
}

pub fn pointToSegmentDist(px: f32, py: f32, x0: f32, y0: f32, x1: f32, y1: f32) f32 {
    const dx = x1 - x0;
    const dy = y1 - y0;
    const len_sq = dx * dx + dy * dy;
    if (len_sq < 0.0001) {
        const ex = px - x0;
        const ey = py - y0;
        return @sqrt(ex * ex + ey * ey);
    }
    const t_raw = ((px - x0) * dx + (py - y0) * dy) / len_sq;
    const t = @max(0.0, @min(1.0, t_raw));
    const cx = x0 + dx * t;
    const cy = y0 + dy * t;
    const ex = px - cx;
    const ey = py - cy;
    return @sqrt(ex * ex + ey * ey);
}

pub fn raycastScene(
    origin: editor_math.Vec3,
    dir: editor_math.Vec3,
    objects: []const SceneObject,
) ?SceneRayHit {
    var best: ?SceneRayHit = null;
    for (objects, 0..) |*obj, object_index| {
        if (!obj.enabled or !obj.renderer_visible) continue;
        const world_xf = scene_hierarchy.objectWorldTransform(objects, object_index);
        const hit = raycastMesh(origin, dir, obj, world_xf) orelse continue;
        if (hit.t <= 0) continue;
        if (best != null and hit.t >= best.?.t) continue;
        const normal = triangleWorldNormal(obj, world_xf, hit.triangle);
        best = .{
            .t = hit.t,
            .uv = hit.uv,
            .triangle = hit.triangle,
            .position = editor_math.Vec3.add(origin, editor_math.Vec3.scale(dir, hit.t)),
            .normal = normal,
            .object_index = object_index,
        };
    }
    return best;
}

fn triangleWorldNormal(obj: *const SceneObject, world_xf: editor_math.Mat4, triangle: usize) editor_math.Vec3 {
    const mesh = obj.mesh;
    const vi0 = mesh.indices[triangle];
    const vi1 = mesh.indices[triangle + 1];
    const vi2 = mesh.indices[triangle + 2];
    const xf = world_xf;
    const w0 = xf.transformPoint(mesh.vertices[vi0].position);
    const w1 = xf.transformPoint(mesh.vertices[vi1].position);
    const w2 = xf.transformPoint(mesh.vertices[vi2].position);
    const e1 = editor_math.Vec3.sub(w1, w0);
    const e2 = editor_math.Vec3.sub(w2, w0);
    return editor_math.Vec3.normalized(editor_math.cross(e1, e2));
}

pub fn raycastMesh(origin: editor_math.Vec3, dir: editor_math.Vec3, obj: *const SceneObject, world_xf: editor_math.Mat4) ?RayHit {
    var best: ?RayHit = null;
    const mesh = obj.mesh;
    const xf = world_xf;
    var tri: usize = 0;
    while (tri + 2 < mesh.indices.len) : (tri += 3) {
        const v0 = mesh.vertices[mesh.indices[tri]].position;
        const v1 = mesh.vertices[mesh.indices[tri + 1]].position;
        const v2 = mesh.vertices[mesh.indices[tri + 2]].position;
        const w0 = xf.transformPoint(v0);
        const w1 = xf.transformPoint(v1);
        const w2 = xf.transformPoint(v2);
        const uv0 = mesh.vertices[mesh.indices[tri]].uv;
        const uv1 = mesh.vertices[mesh.indices[tri + 1]].uv;
        const uv2 = mesh.vertices[mesh.indices[tri + 2]].uv;
        if (intersectRayTriangle(origin, dir, w0, w1, w2, uv0, uv1, uv2)) |hit| {
            if (best == null or hit.t < best.?.t) best = .{ .t = hit.t, .uv = hit.uv, .triangle = tri };
        }
    }
    return best;
}

pub fn intersectRayTriangle(
    origin: editor_math.Vec3,
    dir: editor_math.Vec3,
    v0: editor_math.Vec3,
    v1: editor_math.Vec3,
    v2: editor_math.Vec3,
    uv0: editor_math.Vec2,
    uv1: editor_math.Vec2,
    uv2: editor_math.Vec2,
) ?RayTriangleHit {
    const eps: f32 = 0.000001;
    const e1 = editor_math.Vec3.sub(v1, v0);
    const e2 = editor_math.Vec3.sub(v2, v0);
    const pvec = editor_math.cross(dir, e2);
    const det = editor_math.Vec3.dot(e1, pvec);
    if (@abs(det) < eps) return null;
    const inv_det = 1.0 / det;
    const tvec = editor_math.Vec3.sub(origin, v0);
    const u = editor_math.Vec3.dot(tvec, pvec) * inv_det;
    if (u < 0.0 or u > 1.0) return null;
    const qvec = editor_math.cross(tvec, e1);
    const v = editor_math.Vec3.dot(dir, qvec) * inv_det;
    if (v < 0.0 or u + v > 1.0) return null;
    const t = editor_math.Vec3.dot(e2, qvec) * inv_det;
    if (t < eps) return null;
    const uv = editor_math.Vec2{
        .x = uv0.x + (uv1.x - uv0.x) * u + (uv2.x - uv0.x) * v,
        .y = uv0.y + (uv1.y - uv0.y) * u + (uv2.y - uv0.y) * v,
    };
    return .{ .t = t, .uv = uv };
}
