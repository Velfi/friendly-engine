const std = @import("std");
const kdl = @import("kdl");

pub fn decodeValue(allocator: std.mem.Allocator, raw: []const u8) ![]const u8 {
    return kdl.string_utils.makeRealString(allocator, raw);
}

pub fn parseU32(text: []const u8) !u32 {
    return std.fmt.parseInt(u32, text, 10);
}

pub fn parseU64(text: []const u8) !u64 {
    return std.fmt.parseInt(u64, text, 10);
}

pub fn parseF32(text: []const u8) !f32 {
    return std.fmt.parseFloat(f32, text);
}

pub fn parseBool(text: []const u8) !bool {
    if (std.mem.eql(u8, text, "true")) return true;
    if (std.mem.eql(u8, text, "false")) return false;
    return error.InvalidValue;
}

pub fn parseFloatTriple(text: []const u8) ![3]f32 {
    var parts: [3]f32 = undefined;
    var iter = std.mem.splitScalar(u8, text, ',');
    var i: usize = 0;
    while (iter.next()) |part| {
        if (i >= 3) return error.InvalidValue;
        parts[i] = try std.fmt.parseFloat(f32, std.mem.trim(u8, part, " \t"));
        i += 1;
    }
    if (i != 3) return error.InvalidValue;
    return parts;
}

pub fn parseU8Quad(text: []const u8) ![4]u8 {
    var parts: [4]u8 = undefined;
    var iter = std.mem.splitScalar(u8, text, ',');
    var i: usize = 0;
    while (iter.next()) |part| {
        if (i >= 4) return error.InvalidValue;
        parts[i] = @intCast(try std.fmt.parseInt(u16, std.mem.trim(u8, part, " \t"), 10));
        i += 1;
    }
    if (i != 4) return error.InvalidValue;
    return parts;
}

pub fn boolName(value: bool) []const u8 {
    return if (value) "true" else "false";
}
