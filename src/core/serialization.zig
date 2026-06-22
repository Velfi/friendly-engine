const std = @import("std");

pub fn writeStruct(writer: anytype, value: anytype) !void {
    const bytes = std.mem.asBytes(&value);
    try writer.writeAll(bytes);
}

pub fn readStruct(reader: anytype, comptime T: type) !T {
    var value: T = undefined;
    try reader.readNoEof(std.mem.asBytes(&value));
    return value;
}

pub fn toHexU64(value: u64, buffer: *[16]u8) []const u8 {
    _ = std.fmt.bufPrint(buffer, "{x:0>16}", .{value}) catch unreachable;
    return buffer;
}

pub fn parseHexU64(bytes: []const u8) !u64 {
    return std.fmt.parseInt(u64, bytes, 16);
}

test "binary struct round-trip" {
    const Example = packed struct {
        a: u16,
        b: u16,
    };

    var backing: [32]u8 = undefined;
    var stream = std.io.fixedBufferStream(&backing);
    try writeStruct(stream.writer(), Example{ .a = 10, .b = 22 });

    stream.reset();
    const restored = try readStruct(stream.reader(), Example);
    try std.testing.expectEqual(@as(u16, 10), restored.a);
    try std.testing.expectEqual(@as(u16, 22), restored.b);
}

test "hex serialization round-trip" {
    var hex_buffer: [16]u8 = undefined;
    const encoded = toHexU64(0x1234ABCD, &hex_buffer);
    const parsed = try parseHexU64(encoded);
    try std.testing.expectEqual(@as(u64, 0x1234ABCD), parsed);
}
