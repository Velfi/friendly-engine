const std = @import("std");
const scene_io = @import("scene_io.zig");
const scene_marker = @import("scene_marker.zig");

pub const MarkerRef = struct {
    object_index: usize,
    object_id: u64,
    name: []const u8,
    position: @import("editor_math.zig").Vec3,
    scale: @import("editor_math.zig").Vec3,
    kind: scene_marker.Kind,
    shape: scene_marker.Shape,
    marker_id: []const u8,
    group: []const u8,
    binding: []const u8,
    radius: f32,
    order: i32,
};

pub fn isMarkerObject(object: scene_io.SceneObjectData) bool {
    return object.object_kind == .marker or object.marker != null;
}

pub fn shouldConsumeMarker(object: scene_io.SceneObjectData) bool {
    return object.enabled and object.marker != null;
}

pub fn shouldSpawnDrawable(object: scene_io.SceneObjectData) bool {
    return object.enabled and object.object_kind != .empty and !isMarkerObject(object);
}

pub fn shouldRenderDrawable(object: scene_io.SceneObjectData) bool {
    return shouldSpawnDrawable(object) and object.renderer_visible;
}

pub fn hasMarkerKind(object: scene_io.SceneObjectData, kind: scene_marker.Kind) bool {
    const marker = object.marker orelse return false;
    return marker.kind == kind;
}

pub fn markerRefAt(objects: []const scene_io.SceneObjectData, index: usize) ?MarkerRef {
    if (index >= objects.len) return null;
    const object = objects[index];
    if (!shouldConsumeMarker(object)) return null;
    const marker = object.marker.?;
    return .{
        .object_index = index,
        .object_id = object.id,
        .name = object.name,
        .position = object.position,
        .scale = object.scale,
        .kind = marker.kind,
        .shape = marker.shape,
        .marker_id = marker.marker_id,
        .group = marker.group,
        .binding = marker.binding,
        .radius = marker.radius,
        .order = marker.order,
    };
}

pub fn findFirst(objects: []const scene_io.SceneObjectData, kind: scene_marker.Kind) ?usize {
    for (objects, 0..) |object, index| {
        if (shouldConsumeMarker(object) and hasMarkerKind(object, kind)) return index;
    }
    return null;
}

pub fn findFirstBinding(objects: []const scene_io.SceneObjectData, kind: scene_marker.Kind, binding: []const u8) ?usize {
    for (objects, 0..) |object, index| {
        if (!shouldConsumeMarker(object)) continue;
        const marker = object.marker orelse continue;
        if (marker.kind == kind and std.mem.eql(u8, marker.binding, binding)) return index;
    }
    return null;
}

pub fn findFirstGroup(objects: []const scene_io.SceneObjectData, kind: scene_marker.Kind, group: []const u8) ?usize {
    for (objects, 0..) |object, index| {
        if (!shouldConsumeMarker(object)) continue;
        const marker = object.marker orelse continue;
        if (marker.kind == kind and std.mem.eql(u8, marker.group, group)) return index;
    }
    return null;
}

pub fn findFirstRef(objects: []const scene_io.SceneObjectData, kind: scene_marker.Kind) ?MarkerRef {
    return markerRefAt(objects, findFirst(objects, kind) orelse return null);
}

pub fn findFirstBindingRef(objects: []const scene_io.SceneObjectData, kind: scene_marker.Kind, binding: []const u8) ?MarkerRef {
    return markerRefAt(objects, findFirstBinding(objects, kind, binding) orelse return null);
}

pub fn findFirstGroupRef(objects: []const scene_io.SceneObjectData, kind: scene_marker.Kind, group: []const u8) ?MarkerRef {
    return markerRefAt(objects, findFirstGroup(objects, kind, group) orelse return null);
}

pub fn countKind(objects: []const scene_io.SceneObjectData, kind: scene_marker.Kind) usize {
    var count: usize = 0;
    for (objects) |object| {
        if (shouldConsumeMarker(object) and hasMarkerKind(object, kind)) count += 1;
    }
    return count;
}

pub fn countKindGroup(objects: []const scene_io.SceneObjectData, kind: scene_marker.Kind, group: []const u8) usize {
    var count: usize = 0;
    for (objects) |object| {
        if (!shouldConsumeMarker(object)) continue;
        const marker = object.marker orelse continue;
        if (marker.kind == kind and std.mem.eql(u8, marker.group, group)) count += 1;
    }
    return count;
}

pub fn collectKind(allocator: std.mem.Allocator, objects: []const scene_io.SceneObjectData, kind: scene_marker.Kind) ![]MarkerRef {
    var refs: std.ArrayList(MarkerRef) = .empty;
    errdefer refs.deinit(allocator);
    for (objects, 0..) |object, index| {
        if (!shouldConsumeMarker(object)) continue;
        if (!hasMarkerKind(object, kind)) continue;
        try refs.append(allocator, markerRefAt(objects, index).?);
    }
    std.mem.sort(MarkerRef, refs.items, {}, markerRefLessThan);
    return refs.toOwnedSlice(allocator);
}

pub fn collectKindGroup(allocator: std.mem.Allocator, objects: []const scene_io.SceneObjectData, kind: scene_marker.Kind, group: []const u8) ![]MarkerRef {
    var refs: std.ArrayList(MarkerRef) = .empty;
    errdefer refs.deinit(allocator);
    for (objects, 0..) |object, index| {
        if (!shouldConsumeMarker(object)) continue;
        const marker = object.marker orelse continue;
        if (marker.kind != kind) continue;
        if (!std.mem.eql(u8, marker.group, group)) continue;
        try refs.append(allocator, markerRefAt(objects, index).?);
    }
    std.mem.sort(MarkerRef, refs.items, {}, markerRefLessThan);
    return refs.toOwnedSlice(allocator);
}

fn markerRefLessThan(_: void, lhs: MarkerRef, rhs: MarkerRef) bool {
    if (lhs.order != rhs.order) return lhs.order < rhs.order;
    return lhs.object_id < rhs.object_id;
}

test "marker query separates gameplay intent from drawable objects" {
    var objects = [_]scene_io.SceneObjectData{
        .{
            .id = 1,
            .name = @constCast("Visible Box"),
            .object_kind = .mesh,
            .renderer_visible = true,
            .enabled = true,
            .mesh = .{ .vertices = &.{}, .indices = &.{} },
            .position = .{ .x = 0, .y = 0, .z = 0 },
            .scale = .{ .x = 1, .y = 1, .z = 1 },
            .texture = &.{},
            .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        },
        .{
            .id = 2,
            .name = @constCast("Player Start"),
            .object_kind = .marker,
            .renderer_visible = true,
            .enabled = true,
            .mesh = .{ .vertices = &.{}, .indices = &.{} },
            .position = .{ .x = 0, .y = 0, .z = 0 },
            .scale = .{ .x = 1, .y = 1, .z = 1 },
            .texture = &.{},
            .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
            .marker = .{ .kind = .player_start, .binding = @constCast("controller:fps") },
        },
        .{
            .id = 3,
            .name = @constCast("Startup Camera"),
            .object_kind = .marker,
            .renderer_visible = false,
            .enabled = true,
            .mesh = .{ .vertices = &.{}, .indices = &.{} },
            .position = .{ .x = 0, .y = 0, .z = 0 },
            .scale = .{ .x = 1, .y = 1, .z = 1 },
            .texture = &.{},
            .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
            .marker = .{ .kind = .camera_point, .binding = @constCast("startup") },
        },
    };

    try std.testing.expect(shouldRenderDrawable(objects[0]));
    try std.testing.expect(!shouldRenderDrawable(objects[1]));
    try std.testing.expectEqual(@as(?usize, 1), findFirst(&objects, .player_start));
    try std.testing.expectEqual(@as(?usize, 2), findFirstBinding(&objects, .camera_point, "startup"));
    try std.testing.expectEqual(@as(usize, 1), countKind(&objects, .player_start));
}

test "runtime marker refs skip disabled markers and sort by order" {
    var objects = [_]scene_io.SceneObjectData{
        .{
            .id = 10,
            .name = @constCast("Disabled Patrol"),
            .object_kind = .marker,
            .renderer_visible = true,
            .enabled = false,
            .mesh = .{ .vertices = &.{}, .indices = &.{} },
            .position = .{ .x = 9, .y = 0, .z = 9 },
            .scale = .{ .x = 1, .y = 1, .z = 1 },
            .texture = &.{},
            .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
            .marker = .{ .kind = .patrol_point, .shape = .path, .group = @constCast("guard"), .order = 1 },
        },
        .{
            .id = 11,
            .name = @constCast("Patrol B"),
            .object_kind = .marker,
            .renderer_visible = true,
            .enabled = true,
            .mesh = .{ .vertices = &.{}, .indices = &.{} },
            .position = .{ .x = 2, .y = 0, .z = 0 },
            .scale = .{ .x = 1, .y = 1, .z = 1 },
            .texture = &.{},
            .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
            .marker = .{ .kind = .patrol_point, .shape = .path, .group = @constCast("guard"), .order = 2 },
        },
        .{
            .id = 12,
            .name = @constCast("Patrol A"),
            .object_kind = .marker,
            .renderer_visible = false,
            .enabled = true,
            .mesh = .{ .vertices = &.{}, .indices = &.{} },
            .position = .{ .x = 1, .y = 0, .z = 0 },
            .scale = .{ .x = 1, .y = 1, .z = 1 },
            .texture = &.{},
            .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
            .marker = .{ .kind = .patrol_point, .shape = .path, .group = @constCast("guard"), .order = 1 },
        },
        .{
            .id = 13,
            .name = @constCast("Patrol Other Group"),
            .object_kind = .marker,
            .renderer_visible = false,
            .enabled = true,
            .mesh = .{ .vertices = &.{}, .indices = &.{} },
            .position = .{ .x = 4, .y = 0, .z = 0 },
            .scale = .{ .x = 1, .y = 1, .z = 1 },
            .texture = &.{},
            .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
            .marker = .{ .kind = .patrol_point, .shape = .path, .group = @constCast("merchant"), .order = 0 },
        },
    };

    try std.testing.expect(!shouldConsumeMarker(objects[0]));
    try std.testing.expect(!shouldRenderDrawable(objects[1]));
    try std.testing.expectEqual(@as(?usize, 1), findFirst(&objects, .patrol_point));
    try std.testing.expectEqual(@as(?usize, 1), findFirstGroup(&objects, .patrol_point, "guard"));
    try std.testing.expectEqual(@as(?usize, 3), findFirstGroup(&objects, .patrol_point, "merchant"));

    const first_scene_ref = findFirstRef(&objects, .patrol_point).?;
    try std.testing.expectEqual(@as(u64, 11), first_scene_ref.object_id);
    try std.testing.expectEqualStrings("guard", first_scene_ref.group);
    const merchant_ref = findFirstGroupRef(&objects, .patrol_point, "merchant").?;
    try std.testing.expectEqual(@as(u64, 13), merchant_ref.object_id);

    const refs = try collectKind(std.testing.allocator, &objects, .patrol_point);
    defer std.testing.allocator.free(refs);
    try std.testing.expectEqual(@as(usize, 3), refs.len);
    try std.testing.expectEqual(@as(u64, 13), refs[0].object_id);
    try std.testing.expectEqual(@as(u64, 12), refs[1].object_id);
    try std.testing.expectEqual(@as(u64, 11), refs[2].object_id);

    try std.testing.expectEqual(@as(usize, 2), countKindGroup(&objects, .patrol_point, "guard"));
    const guard_refs = try collectKindGroup(std.testing.allocator, &objects, .patrol_point, "guard");
    defer std.testing.allocator.free(guard_refs);
    try std.testing.expectEqual(@as(usize, 2), guard_refs.len);
    try std.testing.expectEqual(@as(u64, 12), guard_refs[0].object_id);
    try std.testing.expectEqual(@as(u64, 11), guard_refs[1].object_id);
}
