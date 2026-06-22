/// Given a KDL string token,
/// returns the corresponding "real" string.
///
/// A "real" string has uses the posix new line convention (no CRLF),
/// has replaced escape codes with their unescaped form (except raw strings),
/// has removed the whitespace prefix from multiline strings,
/// and does not include the delimiters.
pub fn makeRealString(gpa: std.mem.Allocator, string: []const u8) ![]const u8 {
    const string_kind = getStringKind(string);

    const outer = switch (string_kind) {
        .identifier => return gpa.dupe(u8, string),
        .multiline => try makeRealStringMultiline(gpa, string),
        .multiline_raw => try makeRealStringMultilineRaw(gpa, string),
        .raw => try gpa.dupe(u8, string),
        .quoted => try makeRealStringQuoted(gpa, string),
    };
    defer gpa.free(outer);

    const inside_slice = getStringContents(outer);
    const inside = try gpa.dupe(u8, inside_slice);
    errdefer gpa.free(inside);

    errdefer unreachable;

    return inside;
}

fn makeRealStringMultilineRaw(gpa: std.mem.Allocator, string: []const u8) ![]const u8 {
    const norm_lf = try normalizeNewlines(gpa, string);
    defer gpa.free(norm_lf);

    const norm_ws = removeWhitespacePrefix(gpa, norm_lf) catch |e| switch (e) {
        error.NoPrefix => try gpa.dupe(u8, norm_lf),
        else => return e,
    };

    return norm_ws;
}

fn makeRealStringMultiline(gpa: std.mem.Allocator, string: []const u8) ![]const u8 {
    const norm_lf = try normalizeNewlines(gpa, string);
    defer gpa.free(norm_lf);

    const norm_ws_esc = try unescapeWhitespace(gpa, norm_lf);
    defer gpa.free(norm_ws_esc);

    const norm_ws = removeWhitespacePrefix(gpa, norm_ws_esc) catch |e| switch (e) {
        error.NoPrefix => try gpa.dupe(u8, norm_ws_esc),
        else => return e,
    };
    defer gpa.free(norm_ws);

    const norm_esc = try unescapeString(gpa, norm_ws);

    return norm_esc;
}

fn makeRealStringQuoted(gpa: std.mem.Allocator, string: []const u8) ![]const u8 {
    const norm_lf = try normalizeNewlines(gpa, string);
    defer gpa.free(norm_lf);

    const norm_ws = try unescapeWhitespace(gpa, norm_lf);
    defer gpa.free(norm_ws);

    const norm_esc = try unescapeString(gpa, norm_ws);
    return norm_esc;
}

/// Given a "real" string (see `makeRealString()`),
/// returns an inline KDL string.
pub fn makeInlineString(gpa: std.mem.Allocator, string: []const u8) ![]const u8 {
    // Start by escaping the escape sequences
    const esc_esc = try std.mem.replaceOwned(u8, gpa, string, "\\", "\\\\");
    defer gpa.free(esc_esc);

    // Then escape newlines
    const esc_nl = try std.mem.replaceOwned(u8, gpa, esc_esc, "\n", "\\n");
    defer gpa.free(esc_nl);

    // Then escape newlines
    const esc_tabs = try std.mem.replaceOwned(u8, gpa, esc_nl, "\t", "\\t");
    defer gpa.free(esc_tabs);

    // Then escape quotes
    const esc_qt = try std.mem.replaceOwned(u8, gpa, esc_tabs, "\"", "\\\"");

    if (!isKeyword(esc_qt) and !isIdentifier(esc_qt)) {
        defer gpa.free(esc_qt);
        return std.fmt.allocPrint(gpa, "\"{f}\"", .{std.unicode.fmtUtf8(esc_qt)});
    }
    assert(findAny(u8, esc_qt, "/") == null);

    return esc_qt;
}

test "Real multiline string to inline" {
    const input = test_real_string;
    const output = try makeInlineString(std.testing.allocator, input);
    defer std.testing.allocator.free(output);
    try std.testing.expectEqualStrings(test_inline_string, output);
}

test "\"type/\" round trip" {
    const alloc = std.testing.allocator;
    const input =
        \\"type/"
    ;

    const real = try makeRealString(alloc, input);
    defer alloc.free(real);

    try std.testing.expectEqualStrings("type/", real);

    const output = try makeInlineString(alloc, real);
    defer alloc.free(output);

    try std.testing.expectEqualStrings(input, output);
}

pub const NormalizeNewlinesError = std.mem.Allocator.Error;

/// Given a slice from a multiline string literal,
/// returns a copy of the string with normalized newlines.
/// - "\r\n" becomes "\n"
/// - "\r" becomes "\n"
pub fn normalizeNewlines(gpa: std.mem.Allocator, string: []const u8) NormalizeNewlinesError![]const u8 {
    const all_lf = try std.mem.replaceOwned(u8, gpa, string, "\r\n", "\n");
    _ = std.mem.replace(u8, all_lf, "\r", "\n", all_lf);
    return all_lf;
}

test "Normalize newlines" {
    const input = " \n \r\n \n \r";
    const expected = " \n \n \n \n";
    const output = try normalizeNewlines(std.testing.allocator, input);
    defer std.testing.allocator.free(output);
    try std.testing.expectEqualStrings(expected, output);
}

test "Normalize newlines on string that does not need normalization" {
    const input = test_multiline_string;
    const output = try normalizeNewlines(std.testing.allocator, input);
    defer std.testing.allocator.free(output);
    try std.testing.expectEqualStrings(input, output);
}

pub const RemoveWhitespacePrefixError = error{NoPrefix} || std.mem.Allocator.Error;

/// Returns
pub fn removeWhitespacePrefix(gpa: std.mem.Allocator, string: []const u8) RemoveWhitespacePrefixError![]const u8 {
    const prefix = getWhitespacePrefix(string) orelse return error.NoPrefix;
    const removed = try std.mem.replaceOwned(u8, gpa, string, prefix, "\n");
    return removed;
}

/// Given a KDL multiline string (including triple quotes),
/// returns the whitespace prefix (including newline) from the string.
/// Returns null if the string is not multiline.
/// Returns null if the whitespace prefix (excluding newlines) would be zero-length.
/// Returns null if there are non-whitespace characters on the last line.
fn getWhitespacePrefix(string: []const u8) ?[]const u8 {
    if (!isMultiLineString(string)) return null;
    const likely_start: usize = findNone(u8, string, "#\"") orelse return null;
    const likely_end: usize = findLastNone(u8, string, "#\"") orelse return null;
    if (likely_start < 3 or string.len - likely_end < 3) return null;
    assert(std.mem.containsAtLeast(u8, string[0..likely_start], 1, "\"\"\""));
    assert(std.mem.containsAtLeast(u8, string[likely_end..], 1, "\"\"\""));
    const last_line_start = std.mem.lastIndexOfScalar(u8, string, '\n') orelse return null;

    // If the first character of the last line is likely_end, prefix is empty
    if (last_line_start == likely_end) return null;
    assert(last_line_start < likely_end);

    const last_line = string[last_line_start .. likely_end + 1];

    // Earlier check should prevent this from happening
    assert(last_line.len != 0);

    // All characters on the last line must be whitespace
    for (last_line) |character| if (!isWhitespace(character)) return null;

    return last_line;
}

/// Passed string must begin with `\u{`, end with `}`, and include a 1-6 digit hex code.
/// Returns the escaped codepoint.
fn codepointFromEscape(escape_string: []const u8) !u21 {
    assert(escape_string[0] == '\\');
    assert(escape_string[1] == 'u');
    assert(escape_string[2] == '{');
    assert(escape_string[escape_string.len - 1] == '}');
    assert(escape_string.len <= 10);
    const str_int = escape_string[3 .. escape_string.len - 1];
    const codepoint = try std.fmt.parseInt(u21, str_int, 16);
    return codepoint;
}

const EscapeIterator = struct {
    string: []const u8,
    index: usize = 0,
    fn next(this: *@This()) ?[]const u8 {
        if (this.index >= this.string.len) return null;
        var next_index = std.mem.indexOfScalarPos(u8, this.string, this.index + 1, '\\') orelse this.string.len;
        if (this.string[this.index] == '\\' and
            this.index + 1 < this.string.len and
            this.index + 1 == next_index)
            next_index = std.mem.indexOfScalarPos(u8, this.string, next_index + 1, '\\') orelse this.string.len;
        const string = this.string[this.index..next_index];
        this.index = next_index;
        return string;
    }
};

test "Escape iterator" {
    {
        const string = " \\ \t\r\n";
        var esc_iter = EscapeIterator{ .string = string };
        try std.testing.expectEqualStrings(" ", esc_iter.next() orelse return error.Test);
        try std.testing.expectEqualStrings("\\ \t\r\n", esc_iter.next() orelse return error.Test);
        try std.testing.expectEqual(null, esc_iter.next());
    }
    {
        const string = "\\ \t\r\n";
        var esc_iter = EscapeIterator{ .string = string };
        try std.testing.expectEqualStrings("\\ \t\r\n", esc_iter.next() orelse return error.Test);
        try std.testing.expectEqual(null, esc_iter.next());
    }
    {
        const string = "\\ \t\r\n\\n";
        var esc_iter = EscapeIterator{ .string = string };
        try std.testing.expectEqualStrings("\\ \t\r\n", esc_iter.next() orelse return error.Test);
        try std.testing.expectEqualStrings("\\n", esc_iter.next() orelse return error.Test);
        try std.testing.expectEqual(null, esc_iter.next());
    }
    {
        const string =
            \\ \t\u{3B8}\    hi
        ;
        var esc_iter = EscapeIterator{ .string = string };
        try std.testing.expectEqualStrings(" ", esc_iter.next() orelse return error.Test);
        try std.testing.expectEqualStrings("\\t", esc_iter.next() orelse return error.Test);
        try std.testing.expectEqualStrings("\\u{3B8}", esc_iter.next() orelse return error.Test);
        try std.testing.expectEqualStrings("\\    hi", esc_iter.next() orelse return error.Test);
        try std.testing.expectEqual(null, esc_iter.next());
    }
    {
        const string =
            \\ \t\u{3B8}hi
        ;
        var esc_iter = EscapeIterator{ .string = string };
        try std.testing.expectEqualStrings(" ", esc_iter.next() orelse return error.Test);
        try std.testing.expectEqualStrings("\\t", esc_iter.next() orelse return error.Test);
        try std.testing.expectEqualStrings("\\u{3B8}hi", esc_iter.next() orelse return error.Test);
        try std.testing.expectEqual(null, esc_iter.next());
    }
    {
        const string = "    \\\n" ++ " " ** 25 ++ "\n    ";
        var esc_iter = EscapeIterator{ .string = string };
        try std.testing.expectEqualStrings("    ", esc_iter.next() orelse return error.Test);
        try std.testing.expectEqualStrings("\\\n" ++ " " ** 25 ++ "\n    ", esc_iter.next() orelse return error.Test);
        try std.testing.expectEqual(null, esc_iter.next());
    }
}

/// Unescapes ONLY escaped whitespace.
fn unescapeWhitespace(gpa: std.mem.Allocator, string: []const u8) ![]const u8 {
    var new = std.ArrayList(u8).empty;
    errdefer new.deinit(gpa);

    var state: enum { backslash, escape, other } = .other;
    var index: usize = 0;
    while (index < string.len) : (index += 1) {
        switch (state) {
            .backslash => {
                if (std.mem.indexOfScalar(u8, " \n\t\r", string[index])) |_| {
                    state = .escape;
                } else {
                    try new.appendSlice(gpa, &.{ '\\', string[index] });
                    state = .other;
                }
            },
            .escape => {
                if (std.mem.indexOfScalar(u8, " \n\t\r", string[index]) == null) {
                    try new.append(gpa, string[index]);
                    state = .other;
                }
            },
            .other => {
                if (string[index] == '\\') {
                    state = .backslash;
                } else {
                    try new.append(gpa, string[index]);
                }
            },
        }
    }

    return new.toOwnedSlice(gpa);
}

test "Unescaping Whitespace" {
    const gpa = std.testing.allocator;
    {
        const input = try unescapeWhitespace(gpa, " \\ \t\r\n");
        defer gpa.free(input);
        try std.testing.expectEqualStrings(" ", input);
    }
    {
        const input = try unescapeWhitespace(gpa, "\\ \t\r\n");
        defer gpa.free(input);
        try std.testing.expectEqualStrings("", input);
    }
    {
        const input = try unescapeWhitespace(gpa, "\\ \t\r\n\\n");
        defer gpa.free(input);
        try std.testing.expectEqualStrings("\\n", input);
    }
    {
        const input = try unescapeWhitespace(gpa,
            \\ \t\u{3B8}\    hi
        );
        const expected =
            \\ \t\u{3B8}hi
        ;
        defer gpa.free(input);
        try std.testing.expectEqualStrings(expected, input);
    }
    {
        const input = "    \\\n" ++ " " ** 25 ++ "\n    ";
        const expected = "    ";
        const output = try unescapeWhitespace(gpa, input);
        defer gpa.free(output);
        try std.testing.expectEqualStrings(expected, output);
    }
}

/// Must NOT contain a whitespace escape (backslash followed by literal whitespace, like so `\   `).
pub fn unescapeString(gpa: std.mem.Allocator, string: []const u8) ![]const u8 {
    var new = std.ArrayList(u8).empty;
    errdefer new.deinit(gpa);

    // Other escapes
    var esc_iter = EscapeIterator{ .string = string };

    while (esc_iter.next()) |slice| {
        if (slice.len == 0) continue;
        if (slice[0] != '\\' or slice.len == 1) {
            try new.appendSlice(gpa, slice);
            continue;
        }
        switch (slice[1]) {
            ' ', '\n', '\r', '\t' => {
                // there should be no whitespace escapes
                std.log.warn("whitespace escape?!", .{});
            },
            'n', 'r', 't', '\\', '"', 'b', 'f', 's' => |char| { // normal escapes
                try new.append(gpa, switch (char) {
                    'n' => '\n',
                    't' => '\t',
                    'r' => '\r',
                    '\\' => '\\',
                    '"' => '"',
                    'b' => '\x08',
                    'f' => '\x0C',
                    's' => ' ',
                    else => unreachable,
                });
                if (slice.len > 2) try new.appendSlice(gpa, slice[2..]);
            },
            'u' => {
                assert(slice[2] == '{');
                const end = std.mem.indexOf(u8, slice, "}") orelse return error.InvalidEscape;
                const input = slice[0 .. end + 1];
                const extra = slice[input.len..];
                assert(input.len <= 10);
                // Get the codepoint
                const codepoint = try codepointFromEscape(input);
                const codepoint_size = try std.unicode.utf8CodepointSequenceLength(codepoint);
                // Allocate space at end of list
                const slice_utf8 = try new.addManyAsSlice(gpa, codepoint_size);
                // Write utf-8 bytes to list
                const bytes_len = try std.unicode.utf8Encode(codepoint, slice_utf8);
                // Verify bytes written matches expected codepoint size
                assert(codepoint_size == bytes_len);
                if (extra.len > 0) try new.appendSlice(gpa, extra);
            },
            else => return error.InvalidEscape,
        }
    }

    return new.toOwnedSlice(gpa);
}

test "Unescaping strings" {
    const gpa = std.testing.allocator;
    {
        const input = try unescapeString(gpa,
            \\\t\r\n\\\"\b\f
        );
        defer gpa.free(input);
        try std.testing.expectEqualStrings("\t\r\n\\\"\x08\x0C", input);
    }
    {
        const input = try unescapeString(gpa,
            \\echo "\tHello, World!"
        );
        defer gpa.free(input);
        try std.testing.expectEqualStrings("echo \"\tHello, World!\"", input);
    }
}

test "unescape whitespace, unescape string" {
    const string =
        \\ \t\u{3B8}\    hi
    ;
    const unescaped_ws = try unescapeWhitespace(std.testing.allocator, string);
    defer std.testing.allocator.free(unescaped_ws);

    try std.testing.expectEqualSlices(u8,
        \\ \t\u{3B8}hi
    , unescaped_ws);

    const unescaped = try unescapeString(std.testing.allocator, unescaped_ws);
    defer std.testing.allocator.free(unescaped);

    try std.testing.expectEqualSlices(u8, " \tθhi", unescaped);
}

pub fn getStringContents(string: []const u8) []const u8 {
    const start: usize = std.mem.indexOfNone(u8, string, "#\"") orelse return "";
    const end: usize = std.mem.lastIndexOfNone(u8, string, "#\"") orelse return "";
    if (!isMultiLineString(string)) {
        return string[start .. end + 1];
    } else {
        assert(string[start] == '\n');
        const idx_last = std.mem.lastIndexOfScalar(u8, string[0 .. end + 1], '\n') orelse unreachable;
        assert(string[idx_last] == '\n');
        if (start == idx_last) return "";
        return string[start + 1 .. idx_last];
    }
}

test "Contents of multiline string" {
    const input = test_multiline_string;
    const output = getStringContents(input);
    try std.testing.expectEqualStrings(test_multiline_string_contents, output);

    try std.testing.expectEqualStrings("", getStringContents(
        \\"""
        \\"""
    ));
}

pub const StringKind = enum {
    identifier,
    quoted,
    raw,
    multiline,
    multiline_raw,
};

pub fn getStringKind(string: []const u8) StringKind {
    if (isRawString(string) and isMultiLineString(string))
        return .multiline_raw;
    if (isRawString(string))
        return .raw;
    if (isMultiLineString(string))
        return .multiline;
    if (isQuoted(string))
        return .quoted;
    return .identifier;
}

fn isRawString(string: []const u8) bool {
    const start = findNone(u8, string, "#") orelse return false;
    const end = findLastNone(u8, string, "#") orelse return false;
    return start > 0 and string.len - end > 0 and
        string[start] == '"' and string[end] == '"';
}

fn isQuoted(string: []const u8) bool {
    return findScalar(u8, string, '"') != null;
}

pub fn isMultiLineString(slice: []const u8) bool {
    const containsAtLeast = std.mem.containsAtLeast;
    return slice.len >= 7 and
        containsAtLeast(u8, slice, 1, "\n") and
        containsAtLeast(u8, slice, 2,
            \\"""
        );
}

fn isWhitespace(cp: u21) bool {
    return switch (cp) {
        '\n', '\r', '\t', '\\', ' ', ';' => true,
        else => false,
    };
}

fn isIdentifier(string: []const u8) bool {
    if (string.len == 0) return false;
    for (string) |char| {
        switch (char) {
            '(', ')', '{', '}', '[', ']', '/', '\\', '"', ';', '=', '#' => return false, // non-identifier character! stop loop
            ' ', '\n', '\t', '\r' => return false, // whitespace character! stop loop
            else => {},
        }
    }
    return true;
}

test "is 'type/' a keyword or identifier" {
    try std.testing.expect(!isKeyword("type/"));
    try std.testing.expect(!isIdentifier("type/"));
}

fn isKeyword(string: []const u8) bool {
    if (string.len < 2) return false;
    if (string[0] != '#') return false;
    return isIdentifier(string[1..]);
}

pub const multiline_delimiter =
    \\"""
;

const test_multiline_string =
    \\"""
    \\    #!/bin/sh
    \\    echo "\tHello, World!"
    \\    """
;
const test_multiline_string_contents =
    \\    #!/bin/sh
    \\    echo "\tHello, World!"
;
const test_real_string = "#!/bin/sh\necho \"\tHello, World!\"";
const test_inline_string = "\"#!/bin/sh\\necho \\\"\\tHello, World!\\\"\"";

test "Multiline string to real" {
    const input = test_multiline_string;
    const output = try makeRealString(std.testing.allocator, input);
    defer std.testing.allocator.free(output);
    try std.testing.expectEqualStrings(test_real_string, output);
}

const findScalar = if (@hasDecl(std.mem, "findScalar")) std.mem.findScalar else std.mem.indexOfScalar;
const findNone = if (@hasDecl(std.mem, "findNone")) std.mem.findNone else std.mem.indexOfNone;
const findLastNone = if (@hasDecl(std.mem, "findLastNone")) std.mem.findLastNone else std.mem.lastIndexOfNone;
const findAny = if (@hasDecl(std.mem, "findAny")) std.mem.findAny else std.mem.indexOfAny;
const assert = std.debug.assert;
const std = @import("std");
