const std = @import("std");
const shared = @import("runtime_shared");

pub const Scope = enum {
    object,
    face,
    edge,
    point,
    source,
    operation,
    marker,

    pub fn label(self: Scope) []const u8 {
        return switch (self) {
            .object => "Object",
            .face => "Face",
            .edge => "Edge",
            .point => "Point",
            .source => "Source",
            .operation => "Operation",
            .marker => "Marker",
        };
    }

    pub fn next(self: Scope) Scope {
        return switch (self) {
            .object => .face,
            .face => .edge,
            .edge => .point,
            .point => .source,
            .source => .operation,
            .operation => .marker,
            .marker => .object,
        };
    }
};

pub const HitTarget = union(enum) {
    object: u64,
    face: struct { object_id: u64, face_index: usize },
    edge: struct { object_id: u64, a: u32, b: u32 },
    point: struct { object_id: u64, index: u32 },
    source: u64,
    operation: u64,
    marker: u64,
};

pub const Hit = struct {
    scope: Scope,
    target: HitTarget,
    screen_distance_sq: f32,
    depth: f32,
    screen: shared.editor_math.Vec2 = .{ .x = 0, .y = 0 },
    world: shared.editor_math.Vec3 = .{ .x = 0, .y = 0, .z = 0 },
};

pub const ScreenRect = struct {
    min_x: f32,
    min_y: f32,
    max_x: f32,
    max_y: f32,

    pub fn fromDrag(a: shared.editor_math.Vec2, b: shared.editor_math.Vec2) ScreenRect {
        return .{
            .min_x = @min(a.x, b.x),
            .min_y = @min(a.y, b.y),
            .max_x = @max(a.x, b.x),
            .max_y = @max(a.y, b.y),
        };
    }

    pub fn contains(self: ScreenRect, p: shared.editor_math.Vec2) bool {
        return p.x >= self.min_x and p.x <= self.max_x and p.y >= self.min_y and p.y <= self.max_y;
    }
};

pub const Set = struct {
    scope: Scope = .object,
    primary: ?HitTarget = null,
    cycle_index: usize = 0,

    pub fn clear(self: *Set) void {
        self.primary = null;
        self.cycle_index = 0;
    }
};

pub fn sortHits(hits: []Hit) void {
    std.mem.sort(Hit, hits, {}, lessHit);
}

fn lessHit(_: void, a: Hit, b: Hit) bool {
    if (a.screen_distance_sq != b.screen_distance_sq) return a.screen_distance_sq < b.screen_distance_sq;
    return a.depth < b.depth;
}

pub fn nextHitForScope(hits: []const Hit, scope: Scope, previous_cycle: usize) ?struct { hit: Hit, cycle: usize } {
    var count: usize = 0;
    for (hits) |hit| {
        if (hit.scope != scope) continue;
        if (count == previous_cycle) return .{ .hit = hit, .cycle = count + 1 };
        count += 1;
    }
    if (count == 0) return null;
    for (hits) |hit| {
        if (hit.scope == scope) return .{ .hit = hit, .cycle = 1 };
    }
    return null;
}

pub fn appendDragBoxHits(allocator: std.mem.Allocator, out: *std.ArrayList(Hit), hits: []const Hit, scope: Scope, rect: ScreenRect) !void {
    for (hits) |hit| {
        if (hit.scope != scope) continue;
        if (!rect.contains(hit.screen)) continue;
        try out.append(allocator, hit);
    }
    sortHits(out.items);
}

pub fn countHitsForScope(hits: []const Hit, scope: Scope) usize {
    var count: usize = 0;
    for (hits) |hit| {
        if (hit.scope == scope) count += 1;
    }
    return count;
}

test "selection scopes cycle in canonical order" {
    try std.testing.expectEqual(Scope.face, Scope.object.next());
    try std.testing.expectEqual(Scope.object, Scope.marker.next());
}

test "hit sorting prefers nearest screen hit then depth" {
    var hits = [_]Hit{
        .{ .scope = .object, .target = .{ .object = 1 }, .screen_distance_sq = 4, .depth = 2 },
        .{ .scope = .object, .target = .{ .object = 2 }, .screen_distance_sq = 2, .depth = 4 },
        .{ .scope = .object, .target = .{ .object = 3 }, .screen_distance_sq = 2, .depth = 1 },
    };
    sortHits(&hits);
    try std.testing.expectEqual(@as(u64, 3), hits[0].target.object);
}

test "overlap cycling wraps within the active scope" {
    const hits = [_]Hit{
        .{ .scope = .marker, .target = .{ .marker = 10 }, .screen_distance_sq = 1, .depth = 1 },
        .{ .scope = .object, .target = .{ .object = 20 }, .screen_distance_sq = 1, .depth = 1 },
        .{ .scope = .marker, .target = .{ .marker = 30 }, .screen_distance_sq = 2, .depth = 1 },
    };
    const first = nextHitForScope(&hits, .marker, 0).?;
    const second = nextHitForScope(&hits, .marker, first.cycle).?;
    const wrapped = nextHitForScope(&hits, .marker, second.cycle).?;
    try std.testing.expectEqual(@as(u64, 10), first.hit.target.marker);
    try std.testing.expectEqual(@as(u64, 30), second.hit.target.marker);
    try std.testing.expectEqual(@as(u64, 10), wrapped.hit.target.marker);
}

test "drag box filters and sorts hits for current scope" {
    const hits = [_]Hit{
        .{ .scope = .object, .target = .{ .object = 1 }, .screen_distance_sq = 5, .depth = 1, .screen = .{ .x = 20, .y = 20 } },
        .{ .scope = .object, .target = .{ .object = 2 }, .screen_distance_sq = 1, .depth = 1, .screen = .{ .x = 40, .y = 40 } },
        .{ .scope = .marker, .target = .{ .marker = 3 }, .screen_distance_sq = 0, .depth = 1, .screen = .{ .x = 30, .y = 30 } },
        .{ .scope = .object, .target = .{ .object = 4 }, .screen_distance_sq = 0, .depth = 1, .screen = .{ .x = 90, .y = 90 } },
    };
    var selected: std.ArrayList(Hit) = .empty;
    defer selected.deinit(std.testing.allocator);
    try appendDragBoxHits(std.testing.allocator, &selected, &hits, .object, ScreenRect.fromDrag(.{ .x = 10, .y = 10 }, .{ .x = 50, .y = 50 }));
    try std.testing.expectEqual(@as(usize, 2), selected.items.len);
    try std.testing.expectEqual(@as(u64, 2), selected.items[0].target.object);
    try std.testing.expectEqual(@as(u64, 1), selected.items[1].target.object);
}
