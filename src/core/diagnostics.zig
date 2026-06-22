const std = @import("std");
const time = @import("time.zig");

pub const LogLevel = enum(u8) {
    debug,
    info,
    warn,
    err,
};

pub const DiagnosticEntry = struct {
    timestamp_ns: i128,
    level: LogLevel,
    message: []const u8,
};

pub const Diagnostics = struct {
    allocator: std.mem.Allocator,
    capacity: usize,
    entries: std.ArrayList(DiagnosticEntry),

    pub fn init(allocator: std.mem.Allocator, capacity: usize) Diagnostics {
        return .{
            .allocator = allocator,
            .capacity = @max(capacity, 1),
            .entries = .empty,
        };
    }

    pub fn deinit(self: *Diagnostics) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.message);
        }
        self.entries.deinit(self.allocator);
    }

    pub fn record(self: *Diagnostics, level: LogLevel, message: []const u8) !void {
        if (self.entries.items.len >= self.capacity) {
            const first = self.entries.orderedRemove(0);
            self.allocator.free(first.message);
        }

        try self.entries.append(self.allocator, .{
            .timestamp_ns = time.monotonicNs(),
            .level = level,
            .message = try self.allocator.dupe(u8, message),
        });
    }

    pub fn latest(self: *const Diagnostics) ?DiagnosticEntry {
        if (self.entries.items.len == 0) return null;
        return self.entries.items[self.entries.items.len - 1];
    }
};

pub fn scopedTimerStart() i128 {
    return time.monotonicNs();
}

pub fn scopedTimerElapsedNs(start_ns: i128) u64 {
    const now_ns = time.monotonicNs();
    const delta = now_ns - start_ns;
    if (delta <= 0) return 0;
    return @as(u64, @intCast(delta));
}

test "diagnostics ring buffer behavior" {
    var diagnostics = Diagnostics.init(std.testing.allocator, 2);
    defer diagnostics.deinit();

    try diagnostics.record(.info, "first");
    try diagnostics.record(.warn, "second");
    try diagnostics.record(.err, "third");

    try std.testing.expectEqual(@as(usize, 2), diagnostics.entries.items.len);
    try std.testing.expectEqualStrings("second", diagnostics.entries.items[0].message);
    try std.testing.expectEqualStrings("third", diagnostics.entries.items[1].message);
}

test "scoped timer reports elapsed time" {
    const start = scopedTimerStart();
    const elapsed_ns = scopedTimerElapsedNs(start);
    try std.testing.expect(elapsed_ns >= 0);
}
