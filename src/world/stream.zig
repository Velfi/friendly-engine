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

pub const ReloadResult = struct {
    reloaded: usize = 0,
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
    active_radius_cells: i32 = 1,
    active_vertical_radius_cells: i32 = 0,
    max_loads_per_update: ?usize = null,
    stream_vertical_cells: bool = false,
    interior_mode: InteriorStreamMode = .active_parent,
    active_cells: std.AutoHashMap(cell.CellId, cell.WorldCellData),
    last_loaded_ids: std.ArrayList(cell.CellId),
    last_unloaded_ids: std.ArrayList(cell.CellId),

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
            .active_cells = std.AutoHashMap(cell.CellId, cell.WorldCellData).init(allocator),
            .last_loaded_ids = .empty,
            .last_unloaded_ids = .empty,
        };
    }

    pub fn deinit(self: *StreamManager) void {
        var iter = self.active_cells.iterator();
        while (iter.next()) |entry| {
            var value = entry.value_ptr.*;
            value.deinit(self.allocator);
        }
        self.active_cells.deinit();
        self.last_loaded_ids.deinit(self.allocator);
        self.last_unloaded_ids.deinit(self.allocator);
        self.cell_io.deinit();
        self.allocator.free(self.project_path);
        self.allocator.free(self.target);
    }

    pub fn activeCellCount(self: *const StreamManager) usize {
        return self.active_cells.count();
    }

    pub fn updateAroundPosition(self: *StreamManager, position: core.math.Vec3f) !StreamUpdateResult {
        return self.updateAroundPositionBudgeted(position, self.max_loads_per_update);
    }

    pub fn updateAroundPositionBudgeted(
        self: *StreamManager,
        position: core.math.Vec3f,
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

        switch (self.interior_mode) {
            .disabled => {},
            .active_parent => try self.includeInteriorChildren(&desired),
        }

        var result = StreamUpdateResult{};

        var loaded_this_update: usize = 0;
        for (desired.ids.items) |id| {
            if (self.active_cells.contains(id)) continue;
            if (max_loads) |limit| {
                if (loaded_this_update >= limit) {
                    result.pending_loads += 1;
                    continue;
                }
            }
            var loaded = try self.loadCell(id);
            errdefer loaded.deinit(self.allocator);
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
            removed.value.deinit(self.allocator);
            try self.last_unloaded_ids.append(self.allocator, id);
        }

        result.loaded = self.last_loaded_ids.items.len;
        result.unloaded = self.last_unloaded_ids.items.len;
        result.loaded_ids = self.last_loaded_ids.items;
        result.unloaded_ids = self.last_unloaded_ids.items;
        return result;
    }

    pub fn reloadActiveCell(self: *StreamManager, id: cell.CellId) !bool {
        const existing = self.active_cells.getPtr(id) orelse return false;
        var loaded = try self.loadCell(id);
        errdefer loaded.deinit(self.allocator);
        var old = existing.*;
        existing.* = loaded;
        old.deinit(self.allocator);
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

    fn loadCell(self: *StreamManager, id: cell.CellId) !cell.WorldCellData {
        return self.cell_io.readCell(id);
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

comptime {
    _ = @import("stream_tests.zig");
}
