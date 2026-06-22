const std = @import("std");
const world = @import("../../world/mod.zig");

pub const Candidate = struct {
    id: world.cell.CellId,
    distance_m: f32,
};

pub const Resident = struct {
    id: world.cell.CellId,
    distance_m: f32,
};

pub const Budget = struct {
    max_loads: usize,
    max_resident: usize,
};

pub const Plan = struct {
    allocator: std.mem.Allocator,
    requests: []world.cell.CellId,
    evictions: []world.cell.CellId,
    desired_count: usize,
    resident_before: usize,
    resident_after: usize,
    pending_loads: usize,

    pub fn deinit(self: *Plan) void {
        self.allocator.free(self.requests);
        self.allocator.free(self.evictions);
        self.* = .{
            .allocator = self.allocator,
            .requests = &.{},
            .evictions = &.{},
            .desired_count = 0,
            .resident_before = 0,
            .resident_after = 0,
            .pending_loads = 0,
        };
    }
};

pub fn planUpdate(
    allocator: std.mem.Allocator,
    candidates: []const Candidate,
    residents: []const Resident,
    budget: Budget,
) !Plan {
    if (budget.max_resident == 0) return error.InvalidTerrainResidencyBudget;

    var sorted_candidates = try allocator.dupe(Candidate, candidates);
    defer allocator.free(sorted_candidates);
    std.mem.sort(Candidate, sorted_candidates, {}, compareCandidateDistance);

    const desired_count = @min(sorted_candidates.len, budget.max_resident);

    var desired_lookup = std.AutoHashMap(world.cell.CellId, f32).init(allocator);
    defer desired_lookup.deinit();
    for (sorted_candidates[0..desired_count]) |candidate| {
        if (!std.math.isFinite(candidate.distance_m)) return error.InvalidTerrainResidencyCandidate;
        try desired_lookup.put(candidate.id, candidate.distance_m);
    }

    var resident_lookup = std.AutoHashMap(world.cell.CellId, void).init(allocator);
    defer resident_lookup.deinit();
    for (residents) |resident| try resident_lookup.put(resident.id, {});

    var eviction_candidates = std.ArrayList(Candidate).empty;
    defer eviction_candidates.deinit(allocator);
    for (residents) |resident| {
        const desired_distance = desired_lookup.get(resident.id) orelse {
            try eviction_candidates.append(allocator, .{ .id = resident.id, .distance_m = std.math.inf(f32) });
            continue;
        };
        try eviction_candidates.append(allocator, .{ .id = resident.id, .distance_m = desired_distance });
    }
    std.mem.sort(Candidate, eviction_candidates.items, {}, compareEvictionPriority);

    var eviction_count: usize = 0;
    for (eviction_candidates.items) |candidate| {
        if (desired_lookup.contains(candidate.id)) break;
        eviction_count += 1;
    }

    const evictions = try allocator.alloc(world.cell.CellId, eviction_count);
    errdefer allocator.free(evictions);
    for (evictions, 0..) |*id, index| id.* = eviction_candidates.items[index].id;

    const resident_after_evictions = residents.len - eviction_count;
    const available_resident_slots = budget.max_resident - @min(budget.max_resident, resident_after_evictions);
    const request_budget = @min(budget.max_loads, available_resident_slots);
    var request_list = std.ArrayList(world.cell.CellId).empty;
    errdefer request_list.deinit(allocator);
    var pending_loads: usize = 0;
    for (sorted_candidates[0..desired_count]) |candidate| {
        if (resident_lookup.contains(candidate.id)) continue;
        if (request_list.items.len < request_budget) {
            try request_list.append(allocator, candidate.id);
        } else {
            pending_loads += 1;
        }
    }

    const requests = try request_list.toOwnedSlice(allocator);
    errdefer allocator.free(requests);
    return .{
        .allocator = allocator,
        .requests = requests,
        .evictions = evictions,
        .desired_count = desired_count,
        .resident_before = residents.len,
        .resident_after = residentAfter(residents.len, requests.len, evictions.len),
        .pending_loads = pending_loads,
    };
}

fn residentAfter(resident_count: usize, request_count: usize, eviction_count: usize) usize {
    return resident_count + request_count - @min(resident_count + request_count, eviction_count);
}

fn compareCandidateDistance(_: void, a: Candidate, b: Candidate) bool {
    if (a.distance_m == b.distance_m) return cellLessThan(a.id, b.id);
    return a.distance_m < b.distance_m;
}

fn compareEvictionPriority(_: void, a: Candidate, b: Candidate) bool {
    const a_far = !std.math.isFinite(a.distance_m);
    const b_far = !std.math.isFinite(b.distance_m);
    if (a_far != b_far) return a_far;
    if (a.distance_m == b.distance_m) return cellLessThan(b.id, a.id);
    return a.distance_m > b.distance_m;
}

fn cellLessThan(a: world.cell.CellId, b: world.cell.CellId) bool {
    if (a.z != b.z) return a.z < b.z;
    if (a.y != b.y) return a.y < b.y;
    return a.x < b.x;
}

test "terrain residency requests nearest missing cells within load budget" {
    const candidates = [_]Candidate{
        .{ .id = .{ .x = 3, .y = 0, .z = 0 }, .distance_m = 300 },
        .{ .id = .{ .x = 0, .y = 0, .z = 0 }, .distance_m = 0 },
        .{ .id = .{ .x = 1, .y = 0, .z = 0 }, .distance_m = 100 },
    };
    var plan = try planUpdate(std.testing.allocator, &candidates, &.{}, .{ .max_loads = 2, .max_resident = 8 });
    defer plan.deinit();
    try std.testing.expectEqual(@as(usize, 2), plan.requests.len);
    try std.testing.expectEqual(world.cell.CellId{ .x = 0, .y = 0, .z = 0 }, plan.requests[0]);
    try std.testing.expectEqual(world.cell.CellId{ .x = 1, .y = 0, .z = 0 }, plan.requests[1]);
    try std.testing.expectEqual(@as(usize, 1), plan.pending_loads);
}

test "terrain residency evicts cells outside desired set" {
    const candidates = [_]Candidate{
        .{ .id = .{ .x = 0, .y = 0, .z = 0 }, .distance_m = 0 },
    };
    const residents = [_]Resident{
        .{ .id = .{ .x = 0, .y = 0, .z = 0 }, .distance_m = 0 },
        .{ .id = .{ .x = 9, .y = 0, .z = 0 }, .distance_m = 900 },
    };
    var plan = try planUpdate(std.testing.allocator, &candidates, &residents, .{ .max_loads = 4, .max_resident = 8 });
    defer plan.deinit();
    try std.testing.expectEqual(@as(usize, 0), plan.requests.len);
    try std.testing.expectEqual(@as(usize, 1), plan.evictions.len);
    try std.testing.expectEqual(world.cell.CellId{ .x = 9, .y = 0, .z = 0 }, plan.evictions[0]);
}

test "terrain residency enforces max resident budget by evicting farthest" {
    const candidates = [_]Candidate{
        .{ .id = .{ .x = 0, .y = 0, .z = 0 }, .distance_m = 0 },
        .{ .id = .{ .x = 1, .y = 0, .z = 0 }, .distance_m = 100 },
        .{ .id = .{ .x = 2, .y = 0, .z = 0 }, .distance_m = 200 },
    };
    const residents = [_]Resident{
        .{ .id = .{ .x = 0, .y = 0, .z = 0 }, .distance_m = 0 },
        .{ .id = .{ .x = 2, .y = 0, .z = 0 }, .distance_m = 200 },
    };
    var plan = try planUpdate(std.testing.allocator, &candidates, &residents, .{ .max_loads = 1, .max_resident = 2 });
    defer plan.deinit();
    try std.testing.expectEqual(@as(usize, 1), plan.requests.len);
    try std.testing.expectEqual(world.cell.CellId{ .x = 1, .y = 0, .z = 0 }, plan.requests[0]);
    try std.testing.expectEqual(@as(usize, 0), plan.pending_loads);
    try std.testing.expectEqual(@as(usize, 1), plan.evictions.len);
    try std.testing.expectEqual(world.cell.CellId{ .x = 2, .y = 0, .z = 0 }, plan.evictions[0]);
}

test "terrain residency desired count reflects capped resident target" {
    const candidates = [_]Candidate{
        .{ .id = .{ .x = 0, .y = 0, .z = 0 }, .distance_m = 0 },
        .{ .id = .{ .x = 1, .y = 0, .z = 0 }, .distance_m = 100 },
        .{ .id = .{ .x = 2, .y = 0, .z = 0 }, .distance_m = 200 },
        .{ .id = .{ .x = 3, .y = 0, .z = 0 }, .distance_m = 300 },
    };
    const residents = [_]Resident{
        .{ .id = .{ .x = 0, .y = 0, .z = 0 }, .distance_m = 0 },
        .{ .id = .{ .x = 1, .y = 0, .z = 0 }, .distance_m = 100 },
    };
    var plan = try planUpdate(std.testing.allocator, &candidates, &residents, .{ .max_loads = 4, .max_resident = 2 });
    defer plan.deinit();
    try std.testing.expectEqual(@as(usize, 2), plan.desired_count);
    try std.testing.expectEqual(@as(usize, 0), plan.requests.len);
    try std.testing.expectEqual(@as(usize, 0), plan.pending_loads);
    try std.testing.expectEqual(@as(usize, 2), plan.resident_after);
}
