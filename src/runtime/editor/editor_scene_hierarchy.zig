const std = @import("std");
const shared = @import("runtime_shared");
const editor_math = shared.editor_math;
const SceneObject = @import("editor_scene_object.zig").SceneObject;

pub const TreeEntry = struct {
    idx: usize,
    depth: u32,
};

pub fn objectIndexById(objects: []const SceneObject, id: u64) ?usize {
    for (objects, 0..) |obj, idx| {
        if (obj.id == id) return idx;
    }
    return null;
}

pub fn isDescendant(objects: []const SceneObject, ancestor_id: u64, candidate_id: u64) bool {
    var current: ?u64 = candidate_id;
    var guard: usize = 0;
    while (current) |cid| {
        if (guard > objects.len) return false;
        guard += 1;
        if (cid == ancestor_id) return true;
        const idx = objectIndexById(objects, cid) orelse return false;
        current = objects[idx].parent_id;
    }
    return false;
}

pub fn canSetParent(objects: []const SceneObject, self_id: u64, new_parent_id: ?u64) bool {
    if (new_parent_id == null) return true;
    const parent_id = new_parent_id.?;
    if (parent_id == self_id) return false;
    if (objectIndexById(objects, parent_id) == null) return false;
    if (isDescendant(objects, self_id, parent_id)) return false;
    return true;
}

pub fn objectWorldTransform(objects: []const SceneObject, idx: usize) editor_math.Mat4 {
    const obj = objects[idx];
    const local = obj.transform();
    if (obj.parent_id) |parent_id| {
        if (objectIndexById(objects, parent_id)) |parent_idx| {
            return editor_math.Mat4.mul(objectWorldTransform(objects, parent_idx), local);
        }
    }
    return local;
}

pub fn objectWorldPosition(objects: []const SceneObject, idx: usize) editor_math.Vec3 {
    const xf = objectWorldTransform(objects, idx);
    return .{ .x = xf.m[12], .y = xf.m[13], .z = xf.m[14] };
}

pub fn objectWorldBounds(objects: []const SceneObject, idx: usize) struct { min: editor_math.Vec3, max: editor_math.Vec3 } {
    const obj = objects[idx];
    const xf = objectWorldTransform(objects, idx);
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

pub fn clearParentReferences(objects: []SceneObject, removed_id: u64) void {
    for (objects) |*obj| {
        if (obj.parent_id == removed_id) obj.parent_id = null;
    }
}

pub fn collectTreeEntries(objects: []const SceneObject, out: []TreeEntry) usize {
    var count: usize = 0;
    appendChildren(objects, null, out, &count, 0);
    return count;
}

pub fn collectTreeEntriesAlloc(allocator: std.mem.Allocator, objects: []const SceneObject) ![]TreeEntry {
    var out = std.ArrayList(TreeEntry).empty;
    errdefer out.deinit(allocator);
    try appendChildrenAlloc(allocator, objects, null, &out, 0);
    return try out.toOwnedSlice(allocator);
}

fn appendChildren(objects: []const SceneObject, parent_id: ?u64, out: []TreeEntry, count: *usize, depth: u32) void {
    for (objects, 0..) |obj, idx| {
        if (!belongsUnderParent(objects, obj, parent_id)) continue;
        if (count.* >= out.len) return;
        out[count.*] = .{ .idx = idx, .depth = depth };
        count.* += 1;
        appendChildren(objects, obj.id, out, count, depth + 1);
    }
}

fn appendChildrenAlloc(allocator: std.mem.Allocator, objects: []const SceneObject, parent_id: ?u64, out: *std.ArrayList(TreeEntry), depth: u32) !void {
    for (objects, 0..) |obj, idx| {
        if (!belongsUnderParent(objects, obj, parent_id)) continue;
        try out.append(allocator, .{ .idx = idx, .depth = depth });
        try appendChildrenAlloc(allocator, objects, obj.id, out, depth + 1);
    }
}

fn belongsUnderParent(objects: []const SceneObject, obj: SceneObject, parent_id: ?u64) bool {
    if (parent_id == null) {
        if (obj.parent_id == null) return true;
        if (objectIndexById(objects, obj.parent_id.?)) |_| return false;
        return true;
    }
    return obj.parent_id == parent_id;
}

test "canSetParent rejects self and descendant cycles" {
    const objects = [_]SceneObject{
        .{ .id = 1, .name = @constCast("root"), .mesh = .{ .vertices = &.{}, .indices = &.{} }, .position = .{ .x = 0, .y = 0, .z = 0 }, .scale = .{ .x = 1, .y = 1, .z = 1 }, .texture = &.{}, .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 } },
        .{ .id = 2, .name = @constCast("child"), .mesh = .{ .vertices = &.{}, .indices = &.{} }, .position = .{ .x = 0, .y = 0, .z = 0 }, .scale = .{ .x = 1, .y = 1, .z = 1 }, .texture = &.{}, .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 } },
        .{ .id = 3, .name = @constCast("grandchild"), .mesh = .{ .vertices = &.{}, .indices = &.{} }, .position = .{ .x = 0, .y = 0, .z = 0 }, .scale = .{ .x = 1, .y = 1, .z = 1 }, .texture = &.{}, .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 } },
    };
    const child: SceneObject = .{ .id = 2, .name = @constCast("child"), .mesh = .{ .vertices = &.{}, .indices = &.{} }, .position = .{ .x = 0, .y = 0, .z = 0 }, .scale = .{ .x = 1, .y = 1, .z = 1 }, .texture = &.{}, .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 } };
    const grandchild: SceneObject = .{ .id = 3, .name = @constCast("grandchild"), .mesh = .{ .vertices = &.{}, .indices = &.{} }, .position = .{ .x = 0, .y = 0, .z = 0 }, .scale = .{ .x = 1, .y = 1, .z = 1 }, .texture = &.{}, .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 } };
    var linked = [_]SceneObject{
        objects[0],
        child,
        grandchild,
    };
    linked[1].parent_id = 1;
    linked[2].parent_id = 2;

    try std.testing.expect(!canSetParent(&linked, 1, 2));
    try std.testing.expect(!canSetParent(&linked, 1, 1));
    try std.testing.expect(!canSetParent(&linked, 1, 3));
    try std.testing.expect(canSetParent(&linked, 3, 1));
    try std.testing.expect(!canSetParent(&linked, 2, 3));
}

test "collectTreeEntries preserves parent-child order" {
    const root: SceneObject = .{ .id = 1, .name = @constCast("root"), .mesh = .{ .vertices = &.{}, .indices = &.{} }, .position = .{ .x = 0, .y = 0, .z = 0 }, .scale = .{ .x = 1, .y = 1, .z = 1 }, .texture = &.{}, .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 } };
    const child: SceneObject = .{ .id = 2, .name = @constCast("child"), .mesh = .{ .vertices = &.{}, .indices = &.{} }, .position = .{ .x = 0, .y = 0, .z = 0 }, .scale = .{ .x = 1, .y = 1, .z = 1 }, .texture = &.{}, .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 } };
    const other: SceneObject = .{ .id = 3, .name = @constCast("other"), .mesh = .{ .vertices = &.{}, .indices = &.{} }, .position = .{ .x = 0, .y = 0, .z = 0 }, .scale = .{ .x = 1, .y = 1, .z = 1 }, .texture = &.{}, .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 } };
    var objects = [_]SceneObject{ root, child, other };
    objects[1].parent_id = 1;

    var entries: [8]TreeEntry = undefined;
    const count = collectTreeEntries(&objects, &entries);
    try std.testing.expectEqual(@as(usize, 3), count);
    try std.testing.expectEqual(@as(usize, 0), entries[0].idx);
    try std.testing.expectEqual(@as(u32, 0), entries[0].depth);
    try std.testing.expectEqual(@as(usize, 1), entries[1].idx);
    try std.testing.expectEqual(@as(u32, 1), entries[1].depth);
}

test "objectWorldTransform composes parent chain" {
    const root: SceneObject = .{ .id = 1, .name = @constCast("root"), .mesh = .{ .vertices = &.{}, .indices = &.{} }, .position = .{ .x = 1, .y = 0, .z = 0 }, .scale = .{ .x = 1, .y = 1, .z = 1 }, .texture = &.{}, .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 } };
    var child: SceneObject = .{ .id = 2, .name = @constCast("child"), .mesh = .{ .vertices = &.{}, .indices = &.{} }, .position = .{ .x = 2, .y = 0, .z = 0 }, .scale = .{ .x = 1, .y = 1, .z = 1 }, .texture = &.{}, .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 } };
    child.parent_id = 1;
    const objects = [_]SceneObject{ root, child };
    const world = objectWorldPosition(&objects, 1);
    try std.testing.expectApproxEqAbs(@as(f32, 3), world.x, 0.001);
}
