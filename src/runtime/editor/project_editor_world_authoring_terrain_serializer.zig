const std = @import("std");

const BufferedWriter = struct {
    writer: *std.Io.Writer,
    bytes: [8192]u8 = undefined,
    len: usize = 0,

    fn init(writer: *std.Io.Writer) BufferedWriter {
        return .{ .writer = writer };
    }

    fn flush(self: *BufferedWriter) !void {
        if (self.len == 0) return;
        try self.writer.writeAll(self.bytes[0..self.len]);
        self.len = 0;
    }

    fn writeByte(self: *BufferedWriter, byte: u8) !void {
        if (self.len == self.bytes.len) try self.flush();
        self.bytes[self.len] = byte;
        self.len += 1;
    }

    fn writeAll(self: *BufferedWriter, bytes: []const u8) !void {
        if (bytes.len > self.bytes.len) {
            try self.flush();
            try self.writer.writeAll(bytes);
            return;
        }
        if (self.len + bytes.len > self.bytes.len) try self.flush();
        @memcpy(self.bytes[self.len..][0..bytes.len], bytes);
        self.len += bytes.len;
    }
};

pub fn writeF32Csv(writer: *std.Io.Writer, values: []const f32) !void {
    var buffered = BufferedWriter.init(writer);
    var scratch: [32]u8 = undefined;
    for (values, 0..) |value, index| {
        if (index != 0) try buffered.writeByte(',');
        const text = std.fmt.bufPrint(&scratch, "{d:.1}", .{value}) catch unreachable;
        try buffered.writeAll(text);
    }
    try buffered.flush();
}

pub fn writeU8Csv(writer: *std.Io.Writer, values: []const u8) !void {
    var buffered = BufferedWriter.init(writer);
    var scratch: [3]u8 = undefined;
    for (values, 0..) |value, index| {
        if (index != 0) try buffered.writeByte(',');
        switch (value) {
            0 => try buffered.writeByte('0'),
            255 => try buffered.writeAll("255"),
            else => {
                const text = std.fmt.bufPrint(&scratch, "{d}", .{value}) catch unreachable;
                try buffered.writeAll(text);
            },
        }
    }
    try buffered.flush();
}

pub fn writeStringCsv(writer: *std.Io.Writer, values: []const []const u8) !void {
    var buffered = BufferedWriter.init(writer);
    for (values, 0..) |value, index| {
        if (index != 0) try buffered.writeByte(',');
        try buffered.writeAll(value);
    }
    try buffered.flush();
}

pub fn writeColorCsv(writer: *std.Io.Writer, values: []const [4]u8) !void {
    var buffered = BufferedWriter.init(writer);
    var scratch: [32]u8 = undefined;
    for (values, 0..) |value, index| {
        if (index != 0) try buffered.writeAll("; ");
        const text = std.fmt.bufPrint(&scratch, "{d},{d},{d},{d}", .{ value[0], value[1], value[2], value[3] }) catch unreachable;
        try buffered.writeAll(text);
    }
    try buffered.flush();
}

test "buffered serializer writes u8 csv" {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try writeU8Csv(&out.writer, &.{ 0, 255, 7 });
    try std.testing.expectEqualStrings("0,255,7", out.written());
}

test "buffered serializer writes f32 csv" {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try writeF32Csv(&out.writer, &.{ 1, 2.25 });
    try std.testing.expectEqualStrings("1.0,2.3", out.written());
}
