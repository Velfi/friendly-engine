const std = @import("std");
const kdl = @import("kdl");

pub fn decodeValue(allocator: std.mem.Allocator, raw: []const u8) ![]const u8 {
    return kdl.string_utils.makeRealString(allocator, raw);
}

pub fn parseI32Triple(text: []const u8) ![3]i32 {
    var values: [3]i32 = .{ 0, 0, 0 };
    const count = try parseI32ListInto(text, &values);
    if (count != 2 and count != 3) return error.InvalidLayerValue;
    return values;
}

pub fn parseF32Triple(text: []const u8) ![3]f32 {
    var values: [3]f32 = .{ 0, 0, 0 };
    const count = try parseF32ListInto(text, &values);
    if (count != 3) return error.InvalidLayerValue;
    return values;
}

pub fn parseF32Pair(text: []const u8) ![2]f32 {
    var values: [2]f32 = .{ 0, 0 };
    const count = try parseF32ListInto(text, &values);
    if (count != 2) return error.InvalidLayerValue;
    return values;
}

pub fn parseU32List(allocator: std.mem.Allocator, text: []const u8) ![]u32 {
    var values = std.ArrayList(u32).empty;
    errdefer values.deinit(allocator);
    var parts = std.mem.splitScalar(u8, text, ',');
    while (parts.next()) |part| {
        const trimmed = std.mem.trim(u8, part, " \t\r\n");
        if (trimmed.len == 0) continue;
        try values.append(allocator, try std.fmt.parseInt(u32, trimmed, 10));
    }
    return values.toOwnedSlice(allocator);
}

pub fn parseU8List(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var values = std.ArrayList(u8).empty;
    errdefer values.deinit(allocator);
    var parts = std.mem.splitScalar(u8, text, ',');
    while (parts.next()) |part| {
        const trimmed = std.mem.trim(u8, part, " \t\r\n");
        if (trimmed.len == 0) continue;
        try values.append(allocator, @intCast(try std.fmt.parseInt(u16, trimmed, 10)));
    }
    return values.toOwnedSlice(allocator);
}

pub fn parseStringList(allocator: std.mem.Allocator, text: []const u8) ![][]u8 {
    var values = std.ArrayList([]u8).empty;
    errdefer {
        for (values.items) |value| allocator.free(value);
        values.deinit(allocator);
    }
    var parts = std.mem.splitScalar(u8, text, ',');
    while (parts.next()) |part| {
        const trimmed = std.mem.trim(u8, part, " \t\r\n");
        try values.append(allocator, try allocator.dupe(u8, trimmed));
    }
    return values.toOwnedSlice(allocator);
}

pub fn parseU8QuadList(allocator: std.mem.Allocator, text: []const u8) ![][4]u8 {
    var values = std.ArrayList([4]u8).empty;
    errdefer values.deinit(allocator);
    var parts = std.mem.splitScalar(u8, text, ';');
    while (parts.next()) |part| {
        const trimmed = std.mem.trim(u8, part, " \t\r\n");
        if (trimmed.len == 0) continue;
        var quad: [4]u8 = .{ 0, 0, 0, 0 };
        var fields = std.mem.splitScalar(u8, trimmed, ',');
        var count: usize = 0;
        while (fields.next()) |field| {
            if (count >= quad.len) return error.InvalidLayerValue;
            const value = std.mem.trim(u8, field, " \t\r\n");
            if (value.len == 0) continue;
            quad[count] = @intCast(try std.fmt.parseInt(u16, value, 10));
            count += 1;
        }
        if (count != quad.len) return error.InvalidLayerValue;
        try values.append(allocator, quad);
    }
    return values.toOwnedSlice(allocator);
}

pub fn parseF32List(allocator: std.mem.Allocator, text: []const u8) ![]f32 {
    var values = std.ArrayList(f32).empty;
    errdefer values.deinit(allocator);
    var parts = std.mem.splitScalar(u8, text, ',');
    while (parts.next()) |part| {
        const trimmed = std.mem.trim(u8, part, " \t\r\n");
        if (trimmed.len == 0) continue;
        const value = try std.fmt.parseFloat(f32, trimmed);
        if (!std.math.isFinite(value)) return error.InvalidLayerValue;
        try values.append(allocator, value);
    }
    return values.toOwnedSlice(allocator);
}

pub fn parsePoint2List(allocator: std.mem.Allocator, text: []const u8) ![]const []const f32 {
    var rows = std.ArrayList([]const f32).empty;
    errdefer {
        for (rows.items) |row| allocator.free(row);
        rows.deinit(allocator);
    }
    var parts = std.mem.splitScalar(u8, text, ';');
    while (parts.next()) |part| {
        const trimmed = std.mem.trim(u8, part, " \t\r\n");
        if (trimmed.len == 0) continue;
        const row = try parseF32List(allocator, trimmed);
        if (row.len != 2) {
            allocator.free(row);
            return error.InvalidLayerValue;
        }
        try rows.append(allocator, row);
    }
    return rows.toOwnedSlice(allocator);
}

pub fn parsePoint3List(allocator: std.mem.Allocator, text: []const u8) ![]const []const f32 {
    var rows = std.ArrayList([]const f32).empty;
    errdefer {
        for (rows.items) |row| allocator.free(row);
        rows.deinit(allocator);
    }
    var parts = std.mem.splitScalar(u8, text, ';');
    while (parts.next()) |part| {
        const trimmed = std.mem.trim(u8, part, " \t\r\n");
        if (trimmed.len == 0) continue;
        const row = try parseF32List(allocator, trimmed);
        if (row.len != 3) {
            allocator.free(row);
            return error.InvalidLayerValue;
        }
        try rows.append(allocator, row);
    }
    return rows.toOwnedSlice(allocator);
}

pub fn freeNestedF32(allocator: std.mem.Allocator, rows: []const []const f32) void {
    for (rows) |row| allocator.free(row);
    allocator.free(rows);
}

pub fn writeI32Triple(writer: *std.Io.Writer, values: [3]i32) !void {
    try writer.print("{d},{d},{d}", .{ values[0], values[1], values[2] });
}

pub fn writeF32Triple(writer: *std.Io.Writer, values: [3]f32) !void {
    try writer.print("{d},{d},{d}", .{ values[0], values[1], values[2] });
}

pub fn writeF32PairList(writer: *std.Io.Writer, values: []const [2]f32) !void {
    for (values, 0..) |value, index| {
        if (index > 0) try writer.writeAll("; ");
        try writer.print("{d},{d}", .{ value[0], value[1] });
    }
}

pub fn writeF32Triples(writer: *std.Io.Writer, values: []const [3]f32) !void {
    for (values, 0..) |value, index| {
        if (index > 0) try writer.writeAll("; ");
        try writer.print("{d},{d},{d}", .{ value[0], value[1], value[2] });
    }
}

pub fn writeU32List(writer: *std.Io.Writer, values: []const u32) !void {
    for (values, 0..) |value, index| {
        if (index > 0) try writer.writeByte(',');
        try writer.print("{d}", .{value});
    }
}

pub fn writeU8List(writer: *std.Io.Writer, values: []const u8) !void {
    for (values, 0..) |value, index| {
        if (index > 0) try writer.writeByte(',');
        try writer.print("{d}", .{value});
    }
}

pub fn writeStringList(writer: *std.Io.Writer, values: []const []const u8) !void {
    for (values, 0..) |value, index| {
        if (index > 0) try writer.writeByte(',');
        try writer.writeAll(value);
    }
}

pub fn writeU8QuadList(writer: *std.Io.Writer, values: []const [4]u8) !void {
    for (values, 0..) |value, index| {
        if (index > 0) try writer.writeAll("; ");
        try writer.print("{d},{d},{d},{d}", .{ value[0], value[1], value[2], value[3] });
    }
}

pub fn writeF32List(writer: *std.Io.Writer, values: []const f32) !void {
    for (values, 0..) |value, index| {
        if (index > 0) try writer.writeByte(',');
        try writer.print("{d}", .{value});
    }
}

fn parseI32ListInto(text: []const u8, values: []i32) !usize {
    var count: usize = 0;
    var parts = std.mem.splitScalar(u8, text, ',');
    while (parts.next()) |part| {
        if (count >= values.len) return error.InvalidLayerValue;
        const trimmed = std.mem.trim(u8, part, " \t\r\n");
        if (trimmed.len == 0) continue;
        values[count] = try std.fmt.parseInt(i32, trimmed, 10);
        count += 1;
    }
    return count;
}

fn parseF32ListInto(text: []const u8, values: []f32) !usize {
    var count: usize = 0;
    var parts = std.mem.splitScalar(u8, text, ',');
    while (parts.next()) |part| {
        if (count >= values.len) return error.InvalidLayerValue;
        const trimmed = std.mem.trim(u8, part, " \t\r\n");
        if (trimmed.len == 0) continue;
        values[count] = try std.fmt.parseFloat(f32, trimmed);
        if (!std.math.isFinite(values[count])) return error.InvalidLayerValue;
        count += 1;
    }
    return count;
}
