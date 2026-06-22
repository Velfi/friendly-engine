pub const TextColor = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,
};

pub const TextStyle = struct {
    color: ?TextColor = null,
    bold: bool = false,
    italic: bool = false,
    monospace: bool = false,
    underline: bool = false,
    strikethrough: bool = false,
};

pub const Span = struct {
    text: []const u8,
    style: TextStyle = .{},
};

pub const RichText = []const Span;

pub fn plain(text: []const u8) Span {
    return .{ .text = text };
}
