const std = @import("std");
const shared = @import("runtime_shared");
const editor_math = shared.editor_math;
const geometry = shared.geometry;
const scene_physics = shared.scene_physics;
const shared_color = shared.color;
const editor_draw = @import("editor_draw.zig");
const editor_raycast = @import("editor_raycast.zig");
const scene_object = @import("editor_scene_object.zig");
const project_editor_state = @import("project_editor_state.zig");
const curve_drawing = @import("project_editor_curve_drawing.zig");
const project_editor_architecture = @import("project_editor_architecture.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const TextureSize = scene_object.TextureSize;
const solid_curve_component = "architecture:solid_curve";
const min_point_spacing: f32 = 0.08;
const tube_segments: usize = 8;
const curve_color = shared_color.Color{ .r = 116, .g = 198, .b = 212, .a = 255 };
const static_body = scene_physics.Body{ .kind = .static, .collider = .box, .mass = 0 };

pub fn clearDraft(state: *ProjectEditorState) void {
    curve_drawing.clear(curveDraft(state));
}

pub fn beginFreehandDrag(state: *ProjectEditorState, screen_x: f32, screen_y: f32) void {
    const point = surfacePointFromRay(state, screen_x, screen_y) orelse return;
    curve_drawing.beginFreehand(state.allocator, curveDraft(state), point) catch {
        project_editor_state.setStatus(state, "Curve point failed");
    };
}

pub fn updateFreehandDrag(state: *ProjectEditorState, screen_x: f32, screen_y: f32) void {
    const point = surfacePointFromRay(state, screen_x, screen_y) orelse return;
    curve_drawing.sampleFreehand(state.allocator, curveDraft(state), point, minPointSpacing(state)) catch |err| switch (err) {
        error.PointTooClose => {},
        else => project_editor_state.setStatus(state, "Curve point failed"),
    };
}

pub fn addPointAtScreen(state: *ProjectEditorState, screen_x: f32, screen_y: f32) void {
    const point = surfacePointFromRay(state, screen_x, screen_y) orelse {
        project_editor_state.setStatus(state, "Curve point missed surface");
        return;
    };
    curve_drawing.addPoint(state.allocator, curveDraft(state), point, minPointSpacing(state)) catch |err| switch (err) {
        error.PointTooClose => project_editor_state.setStatus(state, "Curve point too close to previous"),
        else => project_editor_state.setStatus(state, "Curve point failed"),
    };
    setDraftStatus(state);
}

pub fn updatePointPreview(state: *ProjectEditorState, screen_x: f32, screen_y: f32) void {
    curve_drawing.setPreview(curveDraft(state), surfacePointFromRay(state, screen_x, screen_y));
}

pub fn finishPlacement(state: *ProjectEditorState) !void {
    const points = curve_drawing.finishablePoints(curveDraft(state)) catch {
        clearDraft(state);
        project_editor_state.setStatus(state, "Curve needs at least two surface points");
        return;
    };
    var mesh = try buildTubeMesh(state.allocator, points, @max(0.02, state.architecture_curve_radius));
    errdefer mesh.deinit(state.allocator);

    const tex = try state.allocator.alloc(u8, TextureSize * TextureSize * 4);
    errdefer state.allocator.free(tex);
    scene_object.fillCheckerTexture(tex, TextureSize, curve_color.r, curve_color.g, curve_color.b);

    const name = try std.fmt.allocPrint(state.allocator, "Architecture Curve {d}", .{state.next_object_id});
    errdefer state.allocator.free(name);
    const components = try state.allocator.alloc([]u8, 1);
    errdefer state.allocator.free(components);
    components[0] = try state.allocator.dupe(u8, solid_curve_component);
    errdefer state.allocator.free(components[0]);

    const parent_id = if (project_editor_architecture.activeBuilding(state)) |building| building.id else null;
    try state.objects.append(state.allocator, .{
        .id = state.next_object_id,
        .name = name,
        .mesh = mesh,
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .rotation = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = tex,
        .base_color = curve_color,
        .primitive_kind = null,
        .physics = static_body,
        .components = components,
        .parent_id = parent_id,
    });
    state.selected_object = state.objects.items.len - 1;
    state.next_object_id += 1;
    state.scene_dirty = true;
    clearDraft(state);
    project_editor_state.setStatus(state, "Curve solidified");
}

pub fn drawDraft(state: *ProjectEditorState, vp_w: f32, vp_h: f32) void {
    const point_color = shared_color.Color{ .r = 255, .g = 240, .b = 150, .a = 255 };
    const line_color = shared_color.Color{ .r = 116, .g = 220, .b = 238, .a = 230 };
    const preview_color = shared_color.Color{ .r = 116, .g = 220, .b = 238, .a = 170 };
    curve_drawing.drawDraft(state, curveDraft(state), vp_w, vp_h, line_color, point_color, preview_color);
}

fn minPointSpacing(state: *const ProjectEditorState) f32 {
    return @max(min_point_spacing, state.architecture_curve_radius * 0.55);
}

fn curveDraft(state: *ProjectEditorState) curve_drawing.Draft {
    return .{ .points = &state.architecture_curve_points, .preview_end = &state.architecture_curve_preview_end };
}

fn setDraftStatus(state: *ProjectEditorState) void {
    var buf: [128]u8 = undefined;
    project_editor_state.setStatus(state, std.fmt.bufPrint(
        &buf,
        "Curve: {d} point(s), Finish or double-click to solidify",
        .{state.architecture_curve_points.items.len},
    ) catch "Curve point added");
}

fn surfacePointFromRay(state: *ProjectEditorState, screen_x: f32, screen_y: f32) ?editor_math.Vec3 {
    if (!editor_draw.pointInRect(screen_x, screen_y, state.viewport_screen_rect)) return null;
    const local_x = screen_x - state.viewport_screen_rect.x;
    const local_y = screen_y - state.viewport_screen_rect.y;
    const ray = project_editor_state.rayFromViewport(
        state,
        local_x,
        local_y,
        state.viewport_screen_rect.w,
        state.viewport_screen_rect.h,
    );
    const hit = editor_raycast.raycastScene(ray.origin, ray.dir, state.objects.items) orelse return null;
    const offset = editor_math.Vec3.scale(hit.normal, @max(0.0, state.architecture_curve_surface_offset));
    return editor_math.Vec3.add(hit.position, offset);
}

pub fn buildTubeMesh(allocator: std.mem.Allocator, points: []const editor_math.Vec3, radius: f32) !geometry.Mesh {
    if (points.len < 2) return error.InvalidCurvePath;
    var vertices: std.ArrayList(geometry.Vertex) = .empty;
    defer vertices.deinit(allocator);
    var indices: std.ArrayList(u32) = .empty;
    defer indices.deinit(allocator);

    var path_distance: f32 = 0;
    for (points, 0..) |point, i| {
        if (i > 0) path_distance += geometry.edgeLength(points[i - 1], point);
        const tangent = pathTangent(points, i);
        const up = frameUp(tangent);
        const right = editor_math.Vec3.normalized(editor_math.cross(tangent, up));
        var segment: usize = 0;
        while (segment < tube_segments) : (segment += 1) {
            const angle = (std.math.tau * @as(f32, @floatFromInt(segment))) / @as(f32, @floatFromInt(tube_segments));
            const c = @cos(angle);
            const s = @sin(angle);
            const normal = editor_math.Vec3.normalized(editor_math.Vec3.add(editor_math.Vec3.scale(up, c), editor_math.Vec3.scale(right, s)));
            try vertices.append(allocator, .{
                .position = editor_math.Vec3.add(point, editor_math.Vec3.scale(normal, radius)),
                .normal = normal,
                .uv = .{
                    .x = (@as(f32, @floatFromInt(segment)) / @as(f32, @floatFromInt(tube_segments))) * std.math.tau * radius,
                    .y = path_distance,
                },
            });
        }
    }

    var ring: usize = 0;
    while (ring + 1 < points.len) : (ring += 1) {
        var segment: usize = 0;
        while (segment < tube_segments) : (segment += 1) {
            const next_segment = (segment + 1) % tube_segments;
            const a: u32 = @intCast(ring * tube_segments + segment);
            const b: u32 = @intCast(ring * tube_segments + next_segment);
            const c: u32 = @intCast((ring + 1) * tube_segments + next_segment);
            const d: u32 = @intCast((ring + 1) * tube_segments + segment);
            try indices.appendSlice(allocator, &.{ a, c, b, a, d, c });
        }
    }

    try appendCap(allocator, &vertices, &indices, points[0], editor_math.Vec3.scale(pathTangent(points, 0), -1), 0);
    try appendCap(allocator, &vertices, &indices, points[points.len - 1], pathTangent(points, points.len - 1), (points.len - 1) * tube_segments);

    return .{
        .vertices = try vertices.toOwnedSlice(allocator),
        .indices = try indices.toOwnedSlice(allocator),
    };
}

fn appendCap(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(geometry.Vertex),
    indices: *std.ArrayList(u32),
    center: editor_math.Vec3,
    normal: editor_math.Vec3,
    ring_base: usize,
) !void {
    const center_index: u32 = @intCast(vertices.items.len);
    try vertices.append(allocator, .{ .position = center, .normal = normal, .uv = .{ .x = 0.5, .y = 0.5 } });
    var segment: usize = 0;
    while (segment < tube_segments) : (segment += 1) {
        const next_segment = (segment + 1) % tube_segments;
        try indices.appendSlice(allocator, &.{
            center_index,
            @as(u32, @intCast(ring_base + segment)),
            @as(u32, @intCast(ring_base + next_segment)),
        });
    }
}

fn pathTangent(points: []const editor_math.Vec3, index: usize) editor_math.Vec3 {
    if (index == 0) return editor_math.Vec3.normalized(editor_math.Vec3.sub(points[1], points[0]));
    if (index + 1 == points.len) return editor_math.Vec3.normalized(editor_math.Vec3.sub(points[index], points[index - 1]));
    return editor_math.Vec3.normalized(editor_math.Vec3.sub(points[index + 1], points[index - 1]));
}

fn frameUp(tangent: editor_math.Vec3) editor_math.Vec3 {
    const world_up = editor_math.Vec3{ .x = 0, .y = 1, .z = 0 };
    if (@abs(editor_math.Vec3.dot(tangent, world_up)) < 0.88) return world_up;
    return .{ .x = 1, .y = 0, .z = 0 };
}

test "tube mesh builds rings and caps for a surface curve" {
    const points = [_]editor_math.Vec3{
        .{ .x = 0, .y = 1, .z = 0 },
        .{ .x = 1, .y = 1, .z = 0 },
        .{ .x = 1, .y = 2, .z = 0 },
    };
    var mesh = try buildTubeMesh(std.testing.allocator, &points, 0.1);
    defer mesh.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, points.len * tube_segments + 2), mesh.vertices.len);
    try std.testing.expect(mesh.indices.len > 0);
}

test "tube mesh uv span follows length and radius" {
    const short_points = [_]editor_math.Vec3{
        .{ .x = 0, .y = 1, .z = 0 },
        .{ .x = 1, .y = 1, .z = 0 },
    };
    const long_points = [_]editor_math.Vec3{
        .{ .x = 0, .y = 1, .z = 0 },
        .{ .x = 2, .y = 1, .z = 0 },
    };
    var short_mesh = try buildTubeMesh(std.testing.allocator, &short_points, 0.1);
    defer short_mesh.deinit(std.testing.allocator);
    var long_mesh = try buildTubeMesh(std.testing.allocator, &long_points, 0.2);
    defer long_mesh.deinit(std.testing.allocator);

    try std.testing.expectApproxEqAbs(@as(f32, 1.0), short_mesh.vertices[tube_segments].uv.y, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), long_mesh.vertices[tube_segments].uv.y, 0.0001);
    try std.testing.expectApproxEqAbs(short_mesh.vertices[1].uv.x * 2.0, long_mesh.vertices[1].uv.x, 0.0001);
}
