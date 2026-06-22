const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const project_editor_state = @import("project_editor_state.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const OceanDoc = friendly_engine.modules.ocean.OceanDoc;
const SceneObject = project_editor_state.SceneObject;
const editor_math = shared.editor_math;
const geometry = shared.geometry;
const scene_document = shared.scene_document;

const default_outer_half_extent_m: f32 = 24000.0;
const ocean_uv_scale_m: f32 = 1024.0;

pub const ClipPoint = struct {
    x: f32,
    z: f32,
};

pub const OceanClip = struct {
    points: []ClipPoint,
    outer_half_extent_m: f32,

    pub fn deinit(self: *OceanClip, allocator: std.mem.Allocator) void {
        allocator.free(self.points);
        self.points = &.{};
    }

    pub fn hasExclusion(self: OceanClip) bool {
        return self.points.len >= 3;
    }
};

pub fn applyDoc(state: *ProjectEditorState, doc: OceanDoc) void {
    state.world_ocean_visible = doc.enabled;
    state.ocean_sea_level_m = doc.sea_level_m;
    state.ocean_render_min_distance_m = doc.render_min_distance_m;
    state.ocean_fade_in_start_m = doc.fade_in_start_m;
    state.ocean_fade_in_end_m = doc.fade_in_end_m;
    state.ocean_wind_enabled = doc.wind.enabled;
    state.ocean_wind_direction_deg = doc.wind.direction_deg;
    state.ocean_wind_speed_mps = doc.wind.speed_mps;
    state.ocean_waves_amplitude_m = doc.waves.amplitude_m;
    state.ocean_waves_length_m = doc.waves.length_m;
    state.ocean_waves_speed_mps = doc.waves.speed_mps;
}

pub fn toDoc(state: *const ProjectEditorState) OceanDoc {
    return .{
        .enabled = state.world_ocean_visible,
        .sea_level_m = state.ocean_sea_level_m,
        .render_min_distance_m = state.ocean_render_min_distance_m,
        .fade_in_start_m = state.ocean_fade_in_start_m,
        .fade_in_end_m = state.ocean_fade_in_end_m,
        .wind = .{
            .enabled = state.ocean_wind_enabled,
            .direction_deg = state.ocean_wind_direction_deg,
            .speed_mps = state.ocean_wind_speed_mps,
        },
        .waves = .{
            .enabled = state.world_ocean_visible,
            .amplitude_m = state.ocean_waves_amplitude_m,
            .length_m = state.ocean_waves_length_m,
            .speed_mps = state.ocean_waves_speed_mps,
        },
    };
}

pub fn setStatus(state: *ProjectEditorState) void {
    var buf: [160]u8 = undefined;
    const text = std.fmt.bufPrint(
        &buf,
        "Ocean {s}  sea {d:.1}m  wind {d:.0}deg {d:.1}m/s  waves {d:.1}m/{d:.0}m",
        .{
            if (state.world_ocean_visible) "on" else "off",
            state.ocean_sea_level_m,
            state.ocean_wind_direction_deg,
            state.ocean_wind_speed_mps,
            state.ocean_waves_amplitude_m,
            state.ocean_waves_length_m,
        },
    ) catch "Ocean updated";
    project_editor_state.setStatus(state, text);
}

pub fn wrapDirection(value: f32) f32 {
    var out = @mod(value, 360.0);
    if (out < 0) out += 360.0;
    return out;
}

pub fn isOceanObject(obj: anytype) bool {
    if (std.mem.eql(u8, obj.layer, "world.water")) return true;
    for (obj.properties) |property| {
        if (std.mem.eql(u8, property.key, "role") and std.mem.eql(u8, property.value, "distant_ocean")) return true;
        if (std.mem.eql(u8, property.key, "water_body") and std.mem.eql(u8, property.value, "sea")) return true;
    }
    return false;
}

pub fn objectVisible(state: *const ProjectEditorState, obj: anytype) bool {
    if (!obj.enabled or !obj.renderer_visible) return false;
    if (!state.world_ocean_visible and isOceanObject(obj)) return false;
    return true;
}

pub fn findOceanObjectIndex(state: *const ProjectEditorState) ?usize {
    for (state.objects.items, 0..) |obj, index| {
        if (isOceanObject(obj)) return index;
    }
    return null;
}

pub fn loadClip(allocator: std.mem.Allocator, obj: *const SceneObject) !OceanClip {
    const points = if (propertyValue(obj, "cutout_0_points")) |points_text|
        try parseClipPoints(allocator, points_text)
    else
        try allocator.alloc(ClipPoint, 0);
    errdefer allocator.free(points);
    const outer = if (propertyValue(obj, "outer_half_extent_m")) |value|
        std.fmt.parseFloat(f32, value) catch default_outer_half_extent_m
    else
        default_outer_half_extent_m;
    if (!std.math.isFinite(outer) or outer <= 0) return error.InvalidOceanClip;
    return .{ .points = points, .outer_half_extent_m = outer };
}

pub fn replaceClip(state: *ProjectEditorState, points: []const ClipPoint) !void {
    if (points.len < 3) return error.InvalidOceanClip;
    try validateExclusionPoints(points);
    const index = findOceanObjectIndex(state) orelse return error.OceanObjectNotFound;
    var clip = try loadClip(state.allocator, &state.objects.items[index]);
    defer clip.deinit(state.allocator);
    try applyClip(state, index, points, clip.outer_half_extent_m);
}

pub fn refreshClipMesh(state: *ProjectEditorState) !void {
    const index = findOceanObjectIndex(state) orelse return error.OceanObjectNotFound;
    var clip = try loadClip(state.allocator, &state.objects.items[index]);
    defer clip.deinit(state.allocator);
    try applyClip(state, index, clip.points, clip.outer_half_extent_m);
}

pub fn addClipPointAtTarget(state: *ProjectEditorState) !void {
    try addClipPoint(state, .{ .x = state.camera.target.x, .z = state.camera.target.z });
}

pub fn addClipPoint(state: *ProjectEditorState, point: ClipPoint) !void {
    const index = findOceanObjectIndex(state) orelse return error.OceanObjectNotFound;
    var clip = try loadClip(state.allocator, &state.objects.items[index]);
    defer clip.deinit(state.allocator);
    if (!clip.hasExclusion()) {
        const half: f32 = 512.0;
        const points = [_]ClipPoint{
            .{ .x = point.x - half, .z = point.z - half },
            .{ .x = point.x + half, .z = point.z - half },
            .{ .x = point.x + half, .z = point.z + half },
            .{ .x = point.x - half, .z = point.z + half },
        };
        try applyClip(state, index, &points, clip.outer_half_extent_m);
        state.selected_ocean_clip_point = 0;
        return;
    }
    var points = try state.allocator.alloc(ClipPoint, clip.points.len + 1);
    defer state.allocator.free(points);
    @memcpy(points[0..clip.points.len], clip.points);
    points[clip.points.len] = point;
    try applyClip(state, index, points, clip.outer_half_extent_m);
}

pub fn moveNearestClipPointToTarget(state: *ProjectEditorState) !void {
    try moveNearestClipPoint(state, .{ .x = state.camera.target.x, .z = state.camera.target.z });
}

pub fn moveClipPointAtIndex(state: *ProjectEditorState, point_index: usize, point: ClipPoint) !void {
    const index = findOceanObjectIndex(state) orelse return error.OceanObjectNotFound;
    var clip = try loadClip(state.allocator, &state.objects.items[index]);
    defer clip.deinit(state.allocator);
    if (point_index >= clip.points.len) return error.InvalidOceanClipPoint;
    var points = try state.allocator.alloc(ClipPoint, clip.points.len);
    defer state.allocator.free(points);
    @memcpy(points, clip.points);
    points[point_index] = point;
    try applyClip(state, index, points, clip.outer_half_extent_m);
}

pub fn moveNearestClipPoint(state: *ProjectEditorState, point: ClipPoint) !void {
    const index = findOceanObjectIndex(state) orelse return error.OceanObjectNotFound;
    var clip = try loadClip(state.allocator, &state.objects.items[index]);
    defer clip.deinit(state.allocator);
    if (!clip.hasExclusion()) return error.InvalidOceanClip;
    var points = try state.allocator.alloc(ClipPoint, clip.points.len);
    defer state.allocator.free(points);
    @memcpy(points, clip.points);
    points[nearestPointIndex(points, point)] = point;
    try applyClip(state, index, points, clip.outer_half_extent_m);
}

pub fn insertClipPointAfterIndex(state: *ProjectEditorState, after_index: usize, point: ClipPoint) !void {
    const index = findOceanObjectIndex(state) orelse return error.OceanObjectNotFound;
    var clip = try loadClip(state.allocator, &state.objects.items[index]);
    defer clip.deinit(state.allocator);
    if (!clip.hasExclusion() or after_index >= clip.points.len) return error.InvalidOceanClipPoint;
    var points = try state.allocator.alloc(ClipPoint, clip.points.len + 1);
    defer state.allocator.free(points);
    const insert_index = after_index + 1;
    @memcpy(points[0..insert_index], clip.points[0..insert_index]);
    points[insert_index] = point;
    @memcpy(points[insert_index + 1 ..], clip.points[insert_index..]);
    try applyClip(state, index, points, clip.outer_half_extent_m);
    state.selected_ocean_clip_point = insert_index;
}

pub fn removeNearestClipPointToTarget(state: *ProjectEditorState) !void {
    try removeNearestClipPoint(state, .{ .x = state.camera.target.x, .z = state.camera.target.z });
}

pub fn removeClipPointAtIndex(state: *ProjectEditorState, point_index: usize) !void {
    const index = findOceanObjectIndex(state) orelse return error.OceanObjectNotFound;
    var clip = try loadClip(state.allocator, &state.objects.items[index]);
    defer clip.deinit(state.allocator);
    if (!clip.hasExclusion() or point_index >= clip.points.len) return error.InvalidOceanClip;
    if (clip.points.len <= 3) {
        try applyClip(state, index, &.{}, clip.outer_half_extent_m);
        state.selected_ocean_clip_point = null;
        return;
    }
    var points = try state.allocator.alloc(ClipPoint, clip.points.len - 1);
    defer state.allocator.free(points);
    var out: usize = 0;
    for (clip.points, 0..) |clip_point, idx| {
        if (idx == point_index) continue;
        points[out] = clip_point;
        out += 1;
    }
    try applyClip(state, index, points, clip.outer_half_extent_m);
    state.selected_ocean_clip_point = if (points.len == 0) null else @min(point_index, points.len - 1);
}

pub fn removeNearestClipPoint(state: *ProjectEditorState, point: ClipPoint) !void {
    const index = findOceanObjectIndex(state) orelse return error.OceanObjectNotFound;
    var clip = try loadClip(state.allocator, &state.objects.items[index]);
    defer clip.deinit(state.allocator);
    if (!clip.hasExclusion()) return error.InvalidOceanClip;
    const remove_index = nearestPointIndex(clip.points, point);
    if (clip.points.len <= 3) {
        try applyClip(state, index, &.{}, clip.outer_half_extent_m);
        state.selected_ocean_clip_point = null;
        return;
    }
    var points = try state.allocator.alloc(ClipPoint, clip.points.len - 1);
    defer state.allocator.free(points);
    var out: usize = 0;
    for (clip.points, 0..) |clip_point, idx| {
        if (idx == remove_index) continue;
        points[out] = clip_point;
        out += 1;
    }
    try applyClip(state, index, points, clip.outer_half_extent_m);
}

pub fn applyClip(state: *ProjectEditorState, object_index: usize, points: []const ClipPoint, outer_half_extent_m: f32) !void {
    try validateExclusionPoints(points);
    var mesh = try buildFarOceanMesh(state.allocator, points, outer_half_extent_m, state.ocean_sea_level_m);
    errdefer mesh.deinit(state.allocator);
    const points_text = try formatClipPoints(state.allocator, points);
    defer state.allocator.free(points_text);

    var obj = &state.objects.items[object_index];
    obj.mesh.deinit(state.allocator);
    obj.mesh = mesh;
    obj.primitive_kind = null;
    try setProperty(state.allocator, obj, "cutout_0_points", points_text);
    try setProperty(state.allocator, obj, "cutout_count", if (points.len == 0) "0" else "1");
    try setProperty(state.allocator, obj, "cutout_mode", "designer_2d_slices");
    const outer_text = try formatOwnedFloat(state.allocator, outer_half_extent_m);
    defer state.allocator.free(outer_text);
    try setProperty(state.allocator, obj, "outer_half_extent_m", outer_text);
    try state.saveSceneToDisk();
    project_editor_state.setStatus(state, if (points.len == 0) "Ocean exclusion cleared" else "Ocean exclusion updated");
}

pub fn parseClipPoints(allocator: std.mem.Allocator, text: []const u8) ![]ClipPoint {
    var points: std.ArrayList(ClipPoint) = .empty;
    errdefer points.deinit(allocator);
    var tokens = std.mem.tokenizeScalar(u8, text, ';');
    while (tokens.next()) |token_raw| {
        const token = std.mem.trim(u8, token_raw, " \t\r\n");
        if (token.len == 0) continue;
        const comma = std.mem.indexOfScalar(u8, token, ',') orelse return error.InvalidOceanClip;
        const x_text = std.mem.trim(u8, token[0..comma], " \t\r\n");
        const z_text = std.mem.trim(u8, token[comma + 1 ..], " \t\r\n");
        const x = try std.fmt.parseFloat(f32, x_text);
        const z = try std.fmt.parseFloat(f32, z_text);
        if (!std.math.isFinite(x) or !std.math.isFinite(z)) return error.InvalidOceanClip;
        try points.append(allocator, .{ .x = x, .z = z });
    }
    try validateExclusionPoints(points.items);
    return points.toOwnedSlice(allocator);
}

pub fn formatClipPoints(allocator: std.mem.Allocator, points: []const ClipPoint) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    const writer = &out.writer;
    for (points, 0..) |point, index| {
        if (index > 0) try writer.writeAll("; ");
        try writer.print("{d},{d}", .{ point.x, point.z });
    }
    return out.toOwnedSlice();
}

pub fn buildFarOceanMesh(allocator: std.mem.Allocator, points: []const ClipPoint, outer_half_extent_m: f32, sea_level_m: f32) !geometry.Mesh {
    if (!std.math.isFinite(outer_half_extent_m) or outer_half_extent_m <= 0) return error.InvalidOceanClip;
    try validateExclusionPoints(points);
    if (points.len == 0) return buildFullOceanPlaneMesh(allocator, outer_half_extent_m, sea_level_m);
    var vertices = try allocator.alloc(geometry.Vertex, points.len * 2);
    errdefer allocator.free(vertices);
    var indices = try allocator.alloc(u32, points.len * 6);
    errdefer allocator.free(indices);

    const ccw = polygonArea(points) >= 0;
    for (points, 0..) |point, index| {
        const clip_point = if (ccw) point else points[points.len - 1 - index];
        const outer = projectToOuter(clip_point, outer_half_extent_m);
        vertices[index * 2] = oceanVertex(clip_point.x, sea_level_m, clip_point.z);
        vertices[index * 2 + 1] = oceanVertex(outer.x, sea_level_m, outer.z);
    }

    var out: usize = 0;
    for (0..points.len) |index| {
        const next = (index + 1) % points.len;
        const inner_a: u32 = @intCast(index * 2);
        const outer_a: u32 = @intCast(index * 2 + 1);
        const inner_b: u32 = @intCast(next * 2);
        const outer_b: u32 = @intCast(next * 2 + 1);
        indices[out] = inner_a;
        indices[out + 1] = outer_b;
        indices[out + 2] = outer_a;
        indices[out + 3] = inner_a;
        indices[out + 4] = inner_b;
        indices[out + 5] = outer_b;
        out += 6;
    }

    return .{ .vertices = vertices, .indices = indices };
}

fn buildFullOceanPlaneMesh(allocator: std.mem.Allocator, outer_half_extent_m: f32, sea_level_m: f32) !geometry.Mesh {
    const half = outer_half_extent_m;
    var vertices = try allocator.alloc(geometry.Vertex, 4);
    errdefer allocator.free(vertices);
    var indices = try allocator.alloc(u32, 6);
    errdefer allocator.free(indices);
    vertices[0] = oceanVertex(-half, sea_level_m, -half);
    vertices[1] = oceanVertex(half, sea_level_m, -half);
    vertices[2] = oceanVertex(half, sea_level_m, half);
    vertices[3] = oceanVertex(-half, sea_level_m, half);
    indices[0] = 0;
    indices[1] = 2;
    indices[2] = 1;
    indices[3] = 0;
    indices[4] = 3;
    indices[5] = 2;
    return .{ .vertices = vertices, .indices = indices };
}

fn validateExclusionPoints(points: []const ClipPoint) !void {
    if (points.len != 0 and points.len < 3) return error.InvalidOceanClip;
    for (points) |point| {
        if (!std.math.isFinite(point.x) or !std.math.isFinite(point.z)) return error.InvalidOceanClip;
    }
}

fn propertyValue(obj: *const SceneObject, key: []const u8) ?[]const u8 {
    for (obj.properties) |property| {
        if (std.mem.eql(u8, property.key, key)) return property.value;
    }
    return null;
}

fn setProperty(allocator: std.mem.Allocator, obj: *SceneObject, key: []const u8, value: []const u8) !void {
    for (obj.properties) |*property| {
        if (!std.mem.eql(u8, property.key, key)) continue;
        allocator.free(property.value);
        property.value = try allocator.dupe(u8, value);
        return;
    }
    const next = try allocator.alloc(scene_document.Property, obj.properties.len + 1);
    errdefer allocator.free(next);
    @memcpy(next[0..obj.properties.len], obj.properties);
    next[obj.properties.len] = .{
        .key = try allocator.dupe(u8, key),
        .value = try allocator.dupe(u8, value),
    };
    allocator.free(obj.properties);
    obj.properties = next;
}

fn nearestPointIndex(points: []const ClipPoint, point: ClipPoint) usize {
    var best_index: usize = 0;
    var best_distance: f32 = std.math.inf(f32);
    for (points, 0..) |clip_point, index| {
        const dx = clip_point.x - point.x;
        const dz = clip_point.z - point.z;
        const distance = dx * dx + dz * dz;
        if (distance < best_distance) {
            best_distance = distance;
            best_index = index;
        }
    }
    return best_index;
}

fn projectToOuter(point: ClipPoint, outer_half_extent_m: f32) ClipPoint {
    const max_axis = @max(@abs(point.x), @abs(point.z));
    if (max_axis <= 0.0001) return .{ .x = outer_half_extent_m, .z = 0 };
    const scale = outer_half_extent_m / max_axis;
    return .{ .x = point.x * scale, .z = point.z * scale };
}

fn polygonArea(points: []const ClipPoint) f32 {
    var area: f32 = 0;
    for (points, 0..) |point, index| {
        const next = points[(index + 1) % points.len];
        area += point.x * next.z - next.x * point.z;
    }
    return area * 0.5;
}

fn oceanVertex(x: f32, y: f32, z: f32) geometry.Vertex {
    return .{
        .position = .{ .x = x, .y = y, .z = z },
        .normal = .{ .x = 0, .y = 1, .z = 0 },
        .uv = .{ .x = x / ocean_uv_scale_m, .y = z / ocean_uv_scale_m },
    };
}

fn formatOwnedFloat(allocator: std.mem.Allocator, value: f32) ![]u8 {
    return std.fmt.allocPrint(allocator, "{d}", .{value});
}

test "ocean object detection uses water layer and role property" {
    const property = shared.scene_document.Property{ .key = @constCast("role"), .value = @constCast("distant_ocean") };
    const Obj = struct {
        enabled: bool = true,
        renderer_visible: bool = true,
        layer: []const u8 = "",
        properties: []const shared.scene_document.Property = &.{},
    };
    try std.testing.expect(isOceanObject(Obj{ .properties = &.{property} }));
    try std.testing.expect(isOceanObject(Obj{ .layer = "world.water" }));
}

test "ocean clip mesh triangles face upward" {
    const points = [_]ClipPoint{
        .{ .x = -4, .z = -4 },
        .{ .x = 4, .z = -4 },
        .{ .x = 4, .z = 4 },
        .{ .x = -4, .z = 4 },
    };
    var mesh = try buildFarOceanMesh(std.testing.allocator, &points, 16, 0);
    defer mesh.deinit(std.testing.allocator);
    var tri: usize = 0;
    while (tri < mesh.indices.len) : (tri += 3) {
        const a = mesh.vertices[mesh.indices[tri]].position;
        const b = mesh.vertices[mesh.indices[tri + 1]].position;
        const c = mesh.vertices[mesh.indices[tri + 2]].position;
        const ab = editor_math.Vec3.sub(b, a);
        const ac = editor_math.Vec3.sub(c, a);
        const n = editor_math.cross(ab, ac);
        try std.testing.expect(n.y > 0);
    }
}

test "ocean without exclusion builds a full upward plane" {
    var mesh = try buildFarOceanMesh(std.testing.allocator, &.{}, 16, 0);
    defer mesh.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 4), mesh.vertices.len);
    try std.testing.expectEqual(@as(usize, 6), mesh.indices.len);
    var tri: usize = 0;
    while (tri < mesh.indices.len) : (tri += 3) {
        const a = mesh.vertices[mesh.indices[tri]].position;
        const b = mesh.vertices[mesh.indices[tri + 1]].position;
        const c = mesh.vertices[mesh.indices[tri + 2]].position;
        const ab = editor_math.Vec3.sub(b, a);
        const ac = editor_math.Vec3.sub(c, a);
        const n = editor_math.cross(ab, ac);
        try std.testing.expect(n.y > 0);
    }
}

test "ocean clip mesh accepts clockwise points" {
    const points = [_]ClipPoint{
        .{ .x = -4, .z = -4 },
        .{ .x = -4, .z = 4 },
        .{ .x = 4, .z = 4 },
        .{ .x = 4, .z = -4 },
    };
    var mesh = try buildFarOceanMesh(std.testing.allocator, &points, 16, 0);
    defer mesh.deinit(std.testing.allocator);
    const a = mesh.vertices[mesh.indices[0]].position;
    const b = mesh.vertices[mesh.indices[1]].position;
    const c = mesh.vertices[mesh.indices[2]].position;
    const ab = editor_math.Vec3.sub(b, a);
    const ac = editor_math.Vec3.sub(c, a);
    const n = editor_math.cross(ab, ac);
    try std.testing.expect(n.y > 0);
}

test "ocean clip points parse and format" {
    const parsed = try parseClipPoints(std.testing.allocator, "1,2; 3,4; -5,6");
    defer std.testing.allocator.free(parsed);
    try std.testing.expectEqual(@as(usize, 3), parsed.len);
    try std.testing.expectEqual(@as(f32, -5), parsed[2].x);
    const formatted = try formatClipPoints(std.testing.allocator, parsed);
    defer std.testing.allocator.free(formatted);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "3,4") != null);
}

test "ocean exclusion points may be empty" {
    const parsed = try parseClipPoints(std.testing.allocator, "");
    defer std.testing.allocator.free(parsed);
    try std.testing.expectEqual(@as(usize, 0), parsed.len);
    const formatted = try formatClipPoints(std.testing.allocator, parsed);
    defer std.testing.allocator.free(formatted);
    try std.testing.expectEqualStrings("", formatted);
}
