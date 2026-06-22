const std = @import("std");
const friendly_engine = @import("friendly_engine");

pub const CellId = friendly_engine.world.cell.CellId;

pub const max_dirty_cells = 32;

pub const DirtyCell = struct {
    layer_name: []const u8,
    cell: CellId,
    last_change: []const u8,
    sequence: u64,
};

pub const DirtyCellTracker = struct {
    cells: [max_dirty_cells]DirtyCell = undefined,
    count: usize = 0,
    total_marks: u64 = 0,

    pub fn mark(self: *DirtyCellTracker, layer_name: []const u8, cell: CellId, change: []const u8) !void {
        if (layer_name.len == 0) return error.EmptyDirtyLayerName;
        if (change.len == 0) return error.EmptyDirtyChange;
        for (self.cells[0..self.count]) |*entry| {
            if (entry.cell.eql(cell) and std.mem.eql(u8, entry.layer_name, layer_name)) {
                self.total_marks += 1;
                entry.last_change = change;
                entry.sequence = self.total_marks;
                return;
            }
        }
        if (self.count == self.cells.len) return error.TooManyDirtyCells;
        self.total_marks += 1;
        self.cells[self.count] = .{
            .layer_name = layer_name,
            .cell = cell,
            .last_change = change,
            .sequence = self.total_marks,
        };
        self.count += 1;
    }

    pub fn removeCell(self: *DirtyCellTracker, cell: CellId) void {
        var i: usize = 0;
        while (i < self.count) {
            if (self.cells[i].cell.eql(cell)) {
                self.cells[i] = self.cells[self.count - 1];
                self.count -= 1;
            } else {
                i += 1;
            }
        }
    }

    pub fn last(self: *const DirtyCellTracker) ?DirtyCell {
        if (self.count == 0) return null;
        var latest = self.cells[0];
        for (self.cells[1..self.count]) |entry| {
            if (entry.sequence > latest.sequence) latest = entry;
        }
        return latest;
    }

    pub fn formatStatus(self: *const DirtyCellTracker, buf: []u8) ![]const u8 {
        const entry = self.last() orelse return "No dirty world cells";
        return std.fmt.bufPrint(
            buf,
            "Dirty {s} cell {d},{d},{d} ({d} total): {s}",
            .{ entry.layer_name, entry.cell.x, entry.cell.y, entry.cell.z, self.count, entry.last_change },
        );
    }
};

test "dirty cell tracker removes baked cell entries" {
    var tracker = DirtyCellTracker{};
    try tracker.mark("Terrain", .{ .x = 1, .y = 2, .z = 0 }, "height brush");
    try tracker.mark("Scatter", .{ .x = 1, .y = 2, .z = 0 }, "rule seed");
    try std.testing.expectEqual(@as(usize, 2), tracker.count);
    tracker.removeCell(.{ .x = 1, .y = 2, .z = 0 });
    try std.testing.expectEqual(@as(usize, 0), tracker.count);
}
test "dirty cell tracker dedupes layer cells and keeps last change" {
    var tracker = DirtyCellTracker{};
    try tracker.mark("Terrain", .{ .x = 1, .y = 2, .z = 0 }, "tile paint");
    try tracker.mark("Terrain", .{ .x = 1, .y = 2, .z = 0 }, "height paint");
    try tracker.mark("Scatter", .{ .x = 1, .y = 2, .z = 0 }, "rule seed");

    try std.testing.expectEqual(@as(usize, 2), tracker.count);
    try std.testing.expectEqual(@as(u64, 3), tracker.total_marks);
    const latest = tracker.last().?;
    try std.testing.expectEqualStrings("Scatter", latest.layer_name);
    try std.testing.expect(latest.cell.eql(.{ .x = 1, .y = 2, .z = 0 }));

    var buf: [128]u8 = undefined;
    try std.testing.expectEqualStrings(
        "Dirty Scatter cell 1,2,0 (2 total): rule seed",
        try tracker.formatStatus(&buf),
    );
}
