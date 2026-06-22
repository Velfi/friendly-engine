const std = @import("std");
const core = @import("../core/mod.zig");
const cell = @import("cell.zig");
const fcell = @import("fcell.zig");
const file_io = @import("file_io.zig");
const manifest = @import("manifest.zig");

pub const StreamUpdateResult = struct {
    loaded: usize = 0,
    unloaded: usize = 0,
    pending_loads: usize = 0,
    loaded_ids: []const cell.CellId = &.{},
    unloaded_ids: []const cell.CellId = &.{},

    pub fn changed(self: StreamUpdateResult) bool {
        return self.loaded > 0 or self.unloaded > 0;
    }
};

pub const StreamProgress = struct {
    async_loading: bool = false,
    active_cells: usize = 0,
    desired_cells: usize = 0,
    pending_loads: usize = 0,
    inflight_loads: usize = 0,
    completed_pending_loads: usize = 0,
    failed_pending_loads: usize = 0,
    queued_loads_total: u64 = 0,
    completed_loads_total: u64 = 0,
    failed_loads_total: u64 = 0,
    last_loaded: usize = 0,
    last_unloaded: usize = 0,
};

pub const ReloadResult = struct {
    reloaded: usize = 0,
};

pub const ViewPolicy = struct {
    position: core.math.Vec3f,
    forward: core.math.Vec3f,
    fov_y_rad: f32,
    aspect: f32,
    far_distance_m: f32,
};

pub const InteriorStreamMode = enum {
    disabled,
    active_parent,
};

pub const StreamManager = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []u8,
    target: []u8,
    manifest: *const manifest.OwnedWorldManifest,
    cell_io: file_io.SyncCellFileIo,
    cell_data_allocator: std.mem.Allocator,
    active_radius_cells: i32 = 1,
    active_vertical_radius_cells: i32 = 0,
    max_loads_per_update: ?usize = null,
    async_loading: bool = false,
    stream_vertical_cells: bool = false,
    interior_mode: InteriorStreamMode = .active_parent,
    active_cells: std.AutoHashMap(cell.CellId, cell.WorldCellData),
    pending_loads: std.ArrayList(*AsyncCellLoad),
    last_loaded_ids: std.ArrayList(cell.CellId),
    last_unloaded_ids: std.ArrayList(cell.CellId),
    last_desired_cells: usize = 0,
    last_pending_loads: usize = 0,
    queued_loads_total: u64 = 0,
    completed_loads_total: u64 = 0,
    failed_loads_total: u64 = 0,

    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        project_path: []const u8,
        target: []const u8,
        loaded_manifest: *const manifest.OwnedWorldManifest,
    ) !StreamManager {
        const owned_project_path = try allocator.dupe(u8, project_path);
        errdefer allocator.free(owned_project_path);
        const owned_target = try allocator.dupe(u8, target);
        errdefer allocator.free(owned_target);
        var cell_file_io = try file_io.SyncCellFileIo.init(allocator, io, project_path, target, loaded_manifest.world_id);
        errdefer cell_file_io.deinit();

        return .{
            .allocator = allocator,
            .io = io,
            .project_path = owned_project_path,
            .target = owned_target,
            .manifest = loaded_manifest,
            .cell_io = cell_file_io,
            .cell_data_allocator = allocator,
            .active_cells = std.AutoHashMap(cell.CellId, cell.WorldCellData).init(allocator),
            .pending_loads = .empty,
            .last_loaded_ids = .empty,
            .last_unloaded_ids = .empty,
        };
    }

    pub fn deinit(self: *StreamManager) void {
        self.joinPendingLoads();
        var iter = self.active_cells.iterator();
        while (iter.next()) |entry| {
            var value = entry.value_ptr.*;
            value.deinit(self.cell_data_allocator);
        }
        self.active_cells.deinit();
        self.pending_loads.deinit(self.allocator);
        self.last_loaded_ids.deinit(self.allocator);
        self.last_unloaded_ids.deinit(self.allocator);
        self.cell_io.deinit();
        self.allocator.free(self.project_path);
        self.allocator.free(self.target);
    }

    pub fn activeCellCount(self: *const StreamManager) usize {
        return self.active_cells.count();
    }

    pub fn progressSnapshot(self: *const StreamManager) StreamProgress {
        var inflight_loads: usize = 0;
        var completed_pending_loads: usize = 0;
        var failed_pending_loads: usize = 0;
        for (self.pending_loads.items) |pending| {
            if (!pending.done.load(.acquire)) {
                inflight_loads += 1;
                continue;
            }
            if (pending.err != null) {
                failed_pending_loads += 1;
            } else {
                completed_pending_loads += 1;
            }
        }

        return .{
            .async_loading = self.async_loading,
            .active_cells = self.active_cells.count(),
            .desired_cells = self.last_desired_cells,
            .pending_loads = self.last_pending_loads,
            .inflight_loads = inflight_loads,
            .completed_pending_loads = completed_pending_loads,
            .failed_pending_loads = failed_pending_loads,
            .queued_loads_total = self.queued_loads_total,
            .completed_loads_total = self.completed_loads_total,
            .failed_loads_total = self.failed_loads_total,
            .last_loaded = self.last_loaded_ids.items.len,
            .last_unloaded = self.last_unloaded_ids.items.len,
        };
    }

    pub fn enableAsyncLoading(self: *StreamManager, cell_data_allocator: std.mem.Allocator) void {
        std.debug.assert(self.active_cells.count() == 0);
        std.debug.assert(self.pending_loads.items.len == 0);
        self.async_loading = true;
        self.cell_data_allocator = cell_data_allocator;
    }

    pub fn updateAroundPosition(self: *StreamManager, position: core.math.Vec3f) !StreamUpdateResult {
        return self.updateAroundPositionBudgeted(position, self.max_loads_per_update);
    }

    pub fn updateAroundView(self: *StreamManager, view: ViewPolicy) !StreamUpdateResult {
        return self.updateAroundViewBudgeted(view, self.max_loads_per_update);
    }

    pub fn updateAroundPositionBudgeted(
        self: *StreamManager,
        position: core.math.Vec3f,
        max_loads: ?usize,
    ) !StreamUpdateResult {
        return self.updateDesiredCells(position, null, max_loads);
    }

    pub fn updateAroundViewBudgeted(
        self: *StreamManager,
        view: ViewPolicy,
        max_loads: ?usize,
    ) !StreamUpdateResult {
        return self.updateDesiredCells(view.position, view, max_loads);
    }

    fn updateDesiredCells(
        self: *StreamManager,
        position: core.math.Vec3f,
        view: ?ViewPolicy,
        max_loads: ?usize,
    ) !StreamUpdateResult {
        if (self.active_radius_cells < 0 or self.active_vertical_radius_cells < 0) {
            return error.InvalidStreamPolicy;
        }

        self.last_loaded_ids.clearRetainingCapacity();
        self.last_unloaded_ids.clearRetainingCapacity();

        const center = cell.CellId{
            .x = coordForPosition(position.x, self.manifest.cell_size_m),
            .y = coordForPosition(position.z, self.manifest.cell_size_m),
            .z = if (self.stream_vertical_cells) coordForPosition(position.y, cell.default_cell_height_m) else 0,
        };

        var desired = DesiredCells.init(self.allocator);
        defer desired.deinit();

        var dz: i32 = -self.active_vertical_radius_cells;
        while (dz <= self.active_vertical_radius_cells) : (dz += 1) {
            var dy: i32 = -self.active_radius_cells;
            while (dy <= self.active_radius_cells) : (dy += 1) {
                var dx: i32 = -self.active_radius_cells;
                while (dx <= self.active_radius_cells) : (dx += 1) {
                    const id = cell.CellId{
                        .x = center.x + dx,
                        .y = center.y + dy,
                        .z = center.z + dz,
                    };
                    if (self.manifest.hasCell(id)) {
                        try desired.add(id);
                    }
                }
            }
        }

        if (view) |policy| {
            try self.includeVisibleCells(&desired, policy);
        }

        switch (self.interior_mode) {
            .disabled => {},
            .active_parent => try self.includeInteriorChildren(&desired),
        }
        self.last_desired_cells = desired.ids.items.len;

        var result = StreamUpdateResult{};

        var loaded_this_update: usize = 0;
        if (self.async_loading) {
            try self.collectCompletedLoads(&desired, &result);
        }

        for (desired.ids.items) |id| {
            if (self.active_cells.contains(id)) continue;
            if (self.hasPendingLoad(id)) {
                result.pending_loads += 1;
                continue;
            }
            if (self.async_loading and id.eql(center)) {
                var loaded = try self.loadCell(id);
                errdefer loaded.deinit(self.cell_data_allocator);
                try self.active_cells.put(id, loaded);
                try self.last_loaded_ids.append(self.allocator, id);
                continue;
            }
            if (max_loads) |limit| {
                if (loaded_this_update >= limit) {
                    result.pending_loads += 1;
                    continue;
                }
            }

            if (self.async_loading) {
                try self.queueAsyncLoad(id);
                result.pending_loads += 1;
                loaded_this_update += 1;
                continue;
            }

            var loaded = try self.loadCell(id);
            errdefer loaded.deinit(self.cell_data_allocator);
            try self.active_cells.put(id, loaded);
            try self.last_loaded_ids.append(self.allocator, id);
            loaded_this_update += 1;
        }

        var remove_ids = std.ArrayList(cell.CellId).empty;
        defer remove_ids.deinit(self.allocator);
        var active_iter = self.active_cells.iterator();
        while (active_iter.next()) |entry| {
            const id = entry.key_ptr.*;
            if (!desired.lookup.contains(id)) {
                try remove_ids.append(self.allocator, id);
            }
        }

        for (remove_ids.items) |id| {
            var removed = self.active_cells.fetchRemove(id) orelse continue;
            removed.value.deinit(self.cell_data_allocator);
            try self.last_unloaded_ids.append(self.allocator, id);
        }

        result.loaded = self.last_loaded_ids.items.len;
        result.unloaded = self.last_unloaded_ids.items.len;
        result.loaded_ids = self.last_loaded_ids.items;
        result.unloaded_ids = self.last_unloaded_ids.items;
        self.last_pending_loads = result.pending_loads;
        return result;
    }

    pub fn reloadActiveCell(self: *StreamManager, id: cell.CellId) !bool {
        const existing = self.active_cells.getPtr(id) orelse return false;
        var loaded = try self.loadCell(id);
        errdefer loaded.deinit(self.cell_data_allocator);
        var old = existing.*;
        existing.* = loaded;
        old.deinit(self.cell_data_allocator);
        return true;
    }

    pub fn reloadActiveCells(self: *StreamManager) !ReloadResult {
        var ids = std.ArrayList(cell.CellId).empty;
        defer ids.deinit(self.allocator);

        var iter = self.active_cells.iterator();
        while (iter.next()) |entry| {
            try ids.append(self.allocator, entry.key_ptr.*);
        }

        var result = ReloadResult{};
        for (ids.items) |id| {
            if (try self.reloadActiveCell(id)) {
                result.reloaded += 1;
            }
        }
        return result;
    }

    fn includeInteriorChildren(
        self: *StreamManager,
        desired: *DesiredCells,
    ) !void {
        var changed = true;
        while (changed) {
            changed = false;
            for (self.manifest.cells) |entry| {
                const parent = entry.interior_parent orelse continue;
                if (desired.lookup.contains(entry.id) or !desired.lookup.contains(parent)) continue;
                try desired.add(entry.id);
                changed = true;
            }
        }
    }

    fn includeVisibleCells(
        self: *StreamManager,
        desired: *DesiredCells,
        view: ViewPolicy,
    ) !void {
        const forward_xz = normalize2(.{ .x = view.forward.x, .y = view.forward.z });
        if (lengthSquared2(forward_xz) <= std.math.floatEps(f32)) return;

        const aspect = @max(0.001, view.aspect);
        const far_distance = @max(0, view.far_distance_m);
        const half_fov_y = @max(0.001, view.fov_y_rad * 0.5);
        const half_fov_x = std.math.atan(@tan(half_fov_y) * aspect);
        const cell_radius = self.manifest.cell_size_m * @sqrt(@as(f32, 0.5));

        for (self.manifest.cells) |entry| {
            if (entry.interior_parent != null) continue;
            if (entry.id.z != 0 and !self.stream_vertical_cells) continue;

            const center = cellCenter(entry.id, self.manifest.cell_size_m);
            const to_cell = core.math.Vec2f{
                .x = center.x - view.position.x,
                .y = center.z - view.position.z,
            };
            const distance_sq = lengthSquared2(to_cell);
            const max_distance = far_distance + cell_radius;
            if (distance_sq > max_distance * max_distance) continue;
            if (distance_sq <= cell_radius * cell_radius) {
                try desired.add(entry.id);
                continue;
            }

            const distance = @sqrt(distance_sq);
            const direction = scale2(to_cell, 1.0 / distance);
            const dot = std.math.clamp(dot2(forward_xz, direction), -1.0, 1.0);
            const angle = std.math.acos(dot);
            const angular_padding = std.math.atan(cell_radius / distance);
            if (angle <= half_fov_x + angular_padding) {
                try desired.add(entry.id);
            }
        }
    }

    fn loadCell(self: *StreamManager, id: cell.CellId) !cell.WorldCellData {
        return self.cell_io.readCellWithAllocator(self.cell_data_allocator, id);
    }

    fn hasPendingLoad(self: *const StreamManager, id: cell.CellId) bool {
        for (self.pending_loads.items) |pending| {
            if (pending.id.eql(id)) return true;
        }
        return false;
    }

    fn queueAsyncLoad(self: *StreamManager, id: cell.CellId) !void {
        const pending = try self.allocator.create(AsyncCellLoad);
        pending.* = .{
            .id = id,
            .allocator = self.cell_data_allocator,
            .cell_io = &self.cell_io,
        };
        try self.pending_loads.append(self.allocator, pending);
        errdefer {
            _ = self.pending_loads.pop();
            pending.joinAndDeinit(self.allocator);
        }
        pending.thread = try std.Thread.spawn(.{}, AsyncCellLoad.run, .{pending});
        self.queued_loads_total += 1;
    }

    fn collectCompletedLoads(
        self: *StreamManager,
        desired: *const DesiredCells,
        result: *StreamUpdateResult,
    ) !void {
        var i: usize = 0;
        while (i < self.pending_loads.items.len) {
            const pending = self.pending_loads.items[i];
            if (!pending.done.load(.acquire)) {
                i += 1;
                continue;
            }

            _ = self.pending_loads.orderedRemove(i);
            pending.join();
            defer self.allocator.destroy(pending);

            if (pending.err) |err| {
                self.failed_loads_total += 1;
                if (desired.lookup.contains(pending.id)) return err;
                continue;
            }

            var loaded = pending.result orelse continue;
            self.completed_loads_total += 1;
            if (!desired.lookup.contains(pending.id) or self.active_cells.contains(pending.id)) {
                loaded.deinit(self.cell_data_allocator);
                continue;
            }
            errdefer loaded.deinit(self.cell_data_allocator);
            try self.active_cells.put(pending.id, loaded);
            try self.last_loaded_ids.append(self.allocator, pending.id);
            result.loaded += 1;
        }
    }

    fn joinPendingLoads(self: *StreamManager) void {
        for (self.pending_loads.items) |pending| {
            pending.joinAndDeinit(self.allocator);
        }
        self.pending_loads.clearRetainingCapacity();
    }
};

const AsyncCellLoad = struct {
    id: cell.CellId,
    allocator: std.mem.Allocator,
    cell_io: *const file_io.SyncCellFileIo,
    done: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    thread: ?std.Thread = null,
    result: ?cell.WorldCellData = null,
    err: ?anyerror = null,

    fn run(self: *AsyncCellLoad) void {
        self.result = self.cell_io.readCellWithAllocator(self.allocator, self.id) catch |err| {
            self.err = err;
            self.done.store(true, .release);
            return;
        };
        self.done.store(true, .release);
    }

    fn join(self: *AsyncCellLoad) void {
        if (self.thread) |thread| {
            thread.join();
            self.thread = null;
        }
    }

    fn joinAndDeinit(self: *AsyncCellLoad, owner_allocator: std.mem.Allocator) void {
        self.join();
        if (self.result) |*loaded| {
            loaded.deinit(self.allocator);
        }
        owner_allocator.destroy(self);
    }
};

const DesiredCells = struct {
    allocator: std.mem.Allocator,
    lookup: std.AutoHashMap(cell.CellId, void),
    ids: std.ArrayList(cell.CellId),

    fn init(allocator: std.mem.Allocator) DesiredCells {
        return .{
            .allocator = allocator,
            .lookup = std.AutoHashMap(cell.CellId, void).init(allocator),
            .ids = .empty,
        };
    }

    fn deinit(self: *DesiredCells) void {
        self.lookup.deinit();
        self.ids.deinit(self.allocator);
    }

    fn add(self: *DesiredCells, id: cell.CellId) !void {
        if (self.lookup.contains(id)) return;
        try self.lookup.put(id, {});
        try self.ids.append(self.allocator, id);
    }
};

fn coordForPosition(value: f32, cell_size_m: f32) i32 {
    const scaled = value / cell_size_m;
    return @intFromFloat(@floor(scaled));
}

fn cellCenter(id: cell.CellId, cell_size_m: f32) core.math.Vec3f {
    return .{
        .x = (@as(f32, @floatFromInt(id.x)) + 0.5) * cell_size_m,
        .y = (@as(f32, @floatFromInt(id.z)) + 0.5) * cell.default_cell_height_m,
        .z = (@as(f32, @floatFromInt(id.y)) + 0.5) * cell_size_m,
    };
}

fn dot2(a: core.math.Vec2f, b: core.math.Vec2f) f32 {
    return a.x * b.x + a.y * b.y;
}

fn lengthSquared2(v: core.math.Vec2f) f32 {
    return dot2(v, v);
}

fn scale2(v: core.math.Vec2f, s: f32) core.math.Vec2f {
    return .{ .x = v.x * s, .y = v.y * s };
}

fn normalize2(v: core.math.Vec2f) core.math.Vec2f {
    const len_sq = lengthSquared2(v);
    if (len_sq <= std.math.floatEps(f32)) return .{ .x = 0, .y = 0 };
    return scale2(v, 1.0 / @sqrt(len_sq));
}

comptime {
    _ = @import("stream_tests.zig");
}
