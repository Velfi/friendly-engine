//! A streaming tokenizer for KDL documents.
const Tokenizer = @This();

pub const Token = struct {
    loc: Loc,
    tag: Token.Tag,

    pub const Loc = struct {
        start: usize,
        stop: usize,
    };

    pub const Tag = enum {
        invalid,
        lparen,
        rparen,
        lbrace,
        rbrace,
        number,
        string,
        comment,
        equal,
        keyword,
        continuation,
        raw,
        slashdash,
        whitespace,
        newline,
        semicolon,
        eof,
        bom,
    };
};

buffer: [:0]const u8,
index: usize,

pub fn init(string: [:0]const u8) @This() {
    return .{
        .buffer = string,
        .index = 0,
    };
}

pub fn text(this: *const @This(), token: Token) []const u8 {
    return this.buffer[token.loc.start..token.loc.stop];
}

pub const State = enum {
    invalid,
    start,
    newline,
    whitespace,
    raw_string,
    multiline,
    string,
    quote,
    hash,
    identifier,
    comment,
    multiline_comment,
    binary,
    octal,
    decimal,
    hexadecimal,
    escape_whitespace,
    escape_codepoint,
};

pub fn nextParseable(this: *@This()) Token {
    var tok = this.next();
    while (tok.tag == .whitespace or tok.tag == .comment) tok = this.next();
    return tok;
}

pub fn nextNonWhitespace(this: *@This()) Token {
    var tok = this.next();
    while (tok.tag == .whitespace) tok = this.next();
    return tok;
}

pub fn next(this: *@This()) Token {
    this.index = @min(this.index, this.buffer.len);
    var result = Token{
        .tag = undefined,
        .loc = .{
            .start = this.index,
            .stop = undefined,
        },
    };
    var hashes: u32 = 0;
    var quotes: u32 = 0;
    var hashes_end: u32 = 0;
    var quotes_end: u32 = 0;
    var mc: u32 = 0;
    var point_count: u32 = 0;
    var escape_return: ?State = null;
    var codepoint_len: u8 = 0;
    state: switch (State.start) {
        .start => switch (this.buffer[this.index]) {
            0 => {
                if (this.index == this.buffer.len) {
                    return .{
                        .tag = .eof,
                        .loc = .{
                            .start = this.index,
                            .stop = this.index,
                        },
                    };
                } else {
                    continue :state .invalid;
                }
            },
            ' ', '\t' => {
                this.index += 1;
                result.tag = .whitespace;
                continue :state .whitespace;
            },
            '\n', '\r' => {
                continue :state .newline;
            },
            '\\' => {
                this.index += 1;
                result.tag = .continuation;
            },
            '/' => {
                this.index += 1;
                switch (this.buffer[this.index]) {
                    '/' => {
                        this.index += 1;
                        continue :state .comment;
                    },
                    '*' => {
                        this.index += 1;
                        mc += 1;
                        continue :state .multiline_comment;
                    },
                    '-' => {
                        this.index += 1;
                        result.tag = .slashdash;
                    },
                    else => {
                        this.index += 1;
                        continue :state .invalid;
                    },
                }
            },
            '#' => {
                hashes = 1;
                this.index += 1;
                continue :state .hash;
            },
            '"' => {
                quotes = 1;
                this.index += 1;
                continue :state .quote;
            },
            '{' => {
                this.index += 1;
                result.tag = .lbrace;
            },
            '}' => {
                this.index += 1;
                result.tag = .rbrace;
            },
            '(' => {
                this.index += 1;
                result.tag = .lparen;
            },
            ')' => {
                this.index += 1;
                result.tag = .rparen;
            },
            '=' => {
                this.index += 1;
                result.tag = .equal;
            },
            ';' => {
                this.index += 1;
                result.tag = .semicolon;
            },
            '.', '-', '+' => {
                this.index += 1;
                if (this.index != this.buffer.len)
                    switch (this.buffer[this.index]) {
                        '0'...'9' => continue :state .decimal,
                        else => continue :state .identifier,
                    };
                result.tag = .string;
            },
            '0' => {
                this.index += 1;
                if (this.index != this.buffer.len) {
                    switch (this.buffer[this.index]) {
                        'b' => {
                            this.index += 1;
                            continue :state .binary;
                        },
                        'o' => {
                            this.index += 1;
                            continue :state .octal;
                        },
                        'x' => {
                            this.index += 1;
                            continue :state .hexadecimal;
                        },
                        else => continue :state .decimal,
                    }
                } else {
                    result.tag = .number;
                }
            },
            '1'...'9' => {
                this.index += 1;
                continue :state .decimal;
            },
            '\xEF' => {
                if (this.index != 0) continue :state .invalid;
                if (this.buffer.len < 3) continue :state .invalid;
                if (!std.mem.eql(u8, "\u{FEFF}", this.buffer[0..3])) continue :state .invalid;
                this.index = 3;
                result.tag = .bom;
            },
            else => |byte| {
                const len = std.unicode.utf8ByteSequenceLength(byte) catch {
                    continue :state .invalid;
                };
                this.index += len;
                continue :state .identifier;
            },
        },
        .whitespace => {
            switch (this.buffer[this.index]) {
                ' ', '\t' => {
                    this.index += 1;
                    continue :state .whitespace;
                },
                else => {
                    result.tag = .whitespace;
                },
            }
        },
        .newline => {
            const len = newlineLength(this.buffer[this.index..]);
            std.debug.assert(len != 0);
            this.index += len;
            result.tag = .newline;
        },
        .invalid => {
            if (this.index < this.buffer.len) {
                switch (this.buffer[this.index]) {
                    '\n', '\r' => {
                        result.tag = .invalid;
                    },
                    else => {
                        this.index += 1;
                        continue :state .invalid;
                    },
                }
            } else {
                result.tag = .invalid;
            }
        },
        .hash => switch (this.buffer[this.index]) {
            '#' => {
                hashes += 1;
                this.index += 1;
                continue :state .hash;
            },
            '"' => {
                quotes += 1;
                this.index += 1;
                continue :state .quote;
            },
            else => {
                result.tag = .keyword;
                continue :state .identifier;
            },
        },
        .identifier => switch (this.buffer[this.index]) {
            '(', ')', '{', '[', '/', ';', '=', ' ', '\n', '\t', '\r' => {
                result.tag = if (hashes != 0)
                    .keyword
                else
                    .string;
            },
            '}', ']', '\\', '"', '#' => {
                result.tag = .invalid;
            },
            else => |byte| {
                const len = std.unicode.utf8ByteSequenceLength(byte) catch continue :state .invalid;
                this.index += len;
                if (this.index < this.buffer.len) continue :state .identifier;
                result.tag = if (hashes != 0)
                    .keyword
                else
                    .string;
            },
        },
        .quote => switch (this.buffer[this.index]) {
            '"' => {
                quotes += 1;
                this.index += 1;
                if (this.index < this.buffer.len) {
                    if (quotes > 3) continue :state .invalid;
                    continue :state .quote;
                }
                result.tag = .invalid;
            },
            '\n' => {
                if (quotes == 3) {
                    this.index += 1;
                    if (this.index < this.buffer.len) continue :state .multiline;
                } else if (quotes == 2) {
                    result.tag = .string;
                } else {
                    continue :state .invalid;
                }
            },
            else => switch (quotes) {
                3 => continue :state .invalid,
                2 => {
                    if (hashes != 0) {
                        quotes = 1;
                        continue :state .raw_string;
                    } else {
                        result.tag = .string;
                    }
                },
                1 => {
                    if (hashes != 0) {
                        continue :state .raw_string;
                    } else {
                        continue :state .string;
                    }
                },
                else => {
                    this.index += 1;
                    continue :state .invalid;
                },
            },
        },
        .string => switch (this.buffer[this.index]) {
            '"' => {
                this.index += 1;
                result.tag = .string;
            },
            '\\' => {
                this.index += 1;
                if (this.index == this.buffer.len) continue :state .invalid;
                const char = this.buffer[this.index];
                const kind = escapeKind(char) orelse continue :state .invalid;
                var next_state: State = .string;
                switch (kind) {
                    .character => {
                        this.index += 2;
                        next_state = .string;
                    },
                    .whitespace => {
                        this.index += 1;
                        next_state = .escape_whitespace;
                        escape_return = .string;
                    },
                    .codepoint => {
                        this.index += 1;
                        next_state = .escape_codepoint;
                        escape_return = .string;
                    },
                }
                if (this.index < this.buffer.len) continue :state next_state;
                continue :state .invalid;
            },
            else => {
                this.index += 1;
                if (this.index < this.buffer.len) continue :state .string;
                result.tag = .string;
            },
        },
        .escape_whitespace => switch (this.buffer[this.index]) {
            '\n', '\t', '\r' => {
                this.index += 1;
                if (this.index < this.buffer.len) continue :state .string;
                continue :state .invalid;
            },
            else => {
                defer escape_return = null;
                continue :state escape_return orelse .invalid;
            },
        },
        .escape_codepoint => switch (this.buffer[this.index]) {
            '{' => {
                if (codepoint_len != 0) continue :state .invalid;
                codepoint_len += 1;
                this.index += 1;
                if (this.index < this.buffer.len) continue :state .escape_codepoint;
                continue :state .invalid;
            },
            '0'...'9',
            'a'...'f',
            'A'...'F',
            => {
                if (codepoint_len == 0 or codepoint_len > 6) continue :state .invalid;
                codepoint_len += 1;
                this.index += 1;
                if (this.index < this.buffer.len) continue :state .escape_codepoint;
                continue :state .invalid;
            },
            '}' => {
                if (codepoint_len < 2 or codepoint_len > 6) continue :state .invalid;
                this.index += 1;
                const slice_start = this.index - codepoint_len;
                const slice = this.buffer[slice_start .. this.index - 1];
                codepoint_len = 0;
                if (std.fmt.parseInt(u21, slice, 16)) |codepoint| {
                    if (codepoint > 0x10FFFF) continue :state .invalid;
                } else |_| continue :state .invalid;
                if (this.index < this.buffer.len) {
                    defer escape_return = null;
                    continue :state escape_return orelse .invalid;
                }
                continue :state .invalid;
            },
            else => {
                continue :state .invalid;
            },
        },
        .multiline => switch (this.buffer[this.index]) {
            '"' => {
                quotes_end += 1;
                this.index += 1;
                if (quotes_end == 3 and hashes != 0) {
                    continue :state .raw_string;
                } else if (quotes_end == 3) {
                    result.tag = .string;
                } else if (this.index != this.buffer.len) {
                    continue :state .multiline;
                }
            },
            '\\' => {
                this.index += 1;
                if (hashes == 0) {
                    if (this.index == this.buffer.len) continue :state .invalid;
                    const char = this.buffer[this.index];
                    const kind = escapeKind(char) orelse continue :state .invalid;
                    var next_state: State = .string;
                    switch (kind) {
                        .character => {
                            this.index += 2;
                            next_state = .string;
                        },
                        .whitespace => {
                            this.index += 1;
                            next_state = .escape_whitespace;
                            escape_return = .string;
                        },
                        .codepoint => {
                            this.index += 1;
                            next_state = .escape_codepoint;
                            escape_return = .string;
                        },
                    }
                }
                if (this.index < this.buffer.len) continue :state .multiline;
                continue :state .invalid;
            },
            else => {
                quotes_end = 0;
                this.index += 1;
                if (this.index != this.buffer.len) continue :state .multiline;
                result.tag = .string;
            },
        },
        .raw_string => switch (this.buffer[this.index]) {
            '#' => {
                hashes_end += 1;
                this.index += 1;
                if (quotes_end != quotes or hashes_end != hashes) {
                    if (this.index != this.buffer.len) continue :state .raw_string;
                    result.tag = .invalid;
                } else {
                    result.tag = .raw;
                }
            },
            '"' => {
                quotes_end += 1;
                hashes_end = 0;
                this.index += 1;
                if (this.index != this.buffer.len) continue :state .raw_string;
                result.tag = .raw;
            },
            else => {
                quotes_end = 0;
                hashes_end = 0;
                this.index += 1;
                if (this.index != this.buffer.len) {
                    continue :state .raw_string;
                }
                result.tag = .raw;
            },
        },
        .comment => switch (this.buffer[this.index]) {
            '\n' => result.tag = .comment,
            else => {
                this.index += 1;
                if (this.index != this.buffer.len) continue :state .comment;
                result.tag = .comment;
            },
        },
        .multiline_comment => switch (this.buffer[this.index]) {
            '/' => {
                this.index += 1;
                if (this.buffer[this.index] == '*') mc += 1;
                continue :state .multiline_comment;
            },
            '*' => {
                this.index += 1;
                if (this.buffer[this.index] != '/') continue :state .multiline_comment;
                this.index += 1;
                mc -= 1;
                if (mc != 0) continue :state .multiline_comment;
                result.tag = .comment;
            },
            else => {
                this.index += 1;
                continue :state .multiline_comment;
            },
        },
        .binary => switch (this.buffer[this.index]) {
            // TODO: more comprehensive testing
            '0', '1', '_' => {
                this.index += 1;
                if (this.index != this.buffer.len) continue :state .binary;
                result.tag = .number;
            },
            else => {
                result.tag = .number;
            },
        },
        .octal => switch (this.buffer[this.index]) {
            '0'...'9', '_', 'E', '.', 'x', 'a', 'b', 'c', 'd', 'e', 'f' => {
                this.index += 1;
                if (this.index != this.buffer.len) continue :state .octal;
                result.tag = .number;
            },
            else => {
                result.tag = .number;
            },
        },
        .decimal => switch (this.buffer[this.index]) {
            '0'...'9', '_', 'e', 'E', '+', '-' => {
                this.index += 1;
                if (this.index != this.buffer.len) continue :state .decimal;
                result.tag = .number;
            },
            '.' => {
                this.index += 1;
                point_count += 1;
                if (point_count > 1) {
                    result.tag = .invalid;
                } else {
                    if (this.index != this.buffer.len) continue :state .decimal;
                    result.tag = .number;
                }
            },
            else => {
                result.tag = .number;
            },
        },
        .hexadecimal => switch (this.buffer[this.index]) {
            '0'...'9', 'A'...'F', 'a'...'f', '_' => {
                this.index += 1;
                if (this.index != this.buffer.len) continue :state .hexadecimal;
                result.tag = .number;
            },
            else => {
                result.tag = .number;
            },
        },
    }
    result.loc.stop = this.index;
    return result;
}

fn expectEqualToken(tokenizer: Tokenizer, expected_tag: Token.Tag, expected_str: [:0]const u8, actual: Token) !void {
    const str_err = testing.expectEqualStrings(expected_str, tokenizer.buffer[actual.loc.start..actual.loc.stop]);
    const tag_err = testing.expectEqual(expected_tag, actual.tag);
    if (tag_err) {} else |_| std.debug.print("Expected tag {}, found {}\n", .{ expected_tag, actual.tag });
    try str_err;
    try tag_err;
}

fn isDisallowedCodepoint(cp: u21) bool {
    return switch (cp) {
        0x0000...0x0008, // control characters
        0x000E...0x001F,
        0x007F, // delete control character
        0xD800...0xDFFF, // unicode non-scalar values
        0x200E...0x200F, // unicode direction control characters
        0x202A...0x202E,
        0x2066...0x2069,
        0xFEFF, // Zero-width Non-breaking Space/Byte Order Mark
        => true,
        else => false,
    };
}

fn isValidEscape(cp: u21) bool {
    return switch (cp) {
        'n', // \n => newline
        'r', // \r => carriage return
        't', // \t => tab
        '\\', // \\ => reverse solidus
        '\"', // \" => double quote
        'b', // \b => backspace
        'f', // \f => form feed
        's', // \s => space
        'u', // \u{} => hex codepoint
        ' ', // \ => whitespace escape
        '\t',
        '\n',
        => true,
        else => false,
    };
}

const EscapeKind = enum {
    character,
    codepoint,
    whitespace,
};

fn escapeKind(cp: u21) ?EscapeKind {
    return switch (cp) {
        'n', // \n => newline
        'r', // \r => carriage return
        't', // \t => tab
        '\\', // \\ => reverse solidus
        '\"', // \" => double quote
        'b', // \b => backspace
        'f', // \f => form feed
        's', // \s => space
        => .character,
        'u', // \u{} => hex codepoint
        => .codepoint,
        '\t',
        '\n',
        ' ', // \ => whitespace escape
        => .whitespace,
        else => null,
    };
}

/// Returns true if the codepoint is defined as a non-newline whitespace,
/// per the KDL Specification § 3.17 Whitespace.
fn isNonNewlineWhitespace(cp: u21) bool {
    return switch (cp) {
        '\u{0009}', // Character Tabulation
        '\u{0020}', // Space
        '\u{00A0}', // No-Break Space
        '\u{1680}', // Ogham Space Mark
        '\u{2000}', // En Quad
        '\u{2001}', // Em Quad
        '\u{2002}', // En Space
        '\u{2003}', // Em Space
        '\u{2004}', // Three-Per-Em Space
        '\u{2005}', // Four-Per-Em Space
        '\u{2006}', // Six-Per-Em Space
        '\u{2007}', // Figure Space
        '\u{2008}', // Punctuation Space
        '\u{2009}', // Thin Space
        '\u{200A}', // Hair Space
        '\u{202F}', // Narrow No-Break Space
        '\u{205F}', // Medium Mathematical Space
        '\u{3000}', // Ideographic Space
        => true,
        else => false,
    };
}

/// Returns true if the codepoint is defined as a newline,
/// per the KDL Specification § 3.18 Newline.
fn isNewline(cp: u21) bool {
    return switch (cp) {
        '\u{000D}', // CR  : Carriage Return (NOTE: a CRLF sequence is considered a single newline)
        '\u{000A}', // LF  : Line Feed
        '\u{0085}', // NEL : Next Line
        '\u{000B}', // VT  : Vertical Tab
        '\u{000C}', // FF  : Form Feed
        '\u{2028}', // LS  : Line Separator
        '\u{2029}', // PS  : Paragraph Separator
        => true,
        else => false,
    };
}

/// Returns the length of the next newline,
/// per the KDL Specification § 3.18 Newline.
fn newlineLength(str: []const u8) usize {
    if (str.len < 1) return 0;
    const codepoint: u21 = codepoint: {
        const view = std.unicode.Utf8View.init(str) catch break :codepoint str[0];
        var iter = view.iterator();
        break :codepoint iter.nextCodepoint() orelse str[0];
    };
    return switch (codepoint) {
        '\u{000D}', // CR  : Carriage Return (NOTE: a CRLF sequence is considered a single newline)
        => {
            if (str.len >= 2 and str[1] == '\u{000A}') return 2;
            return 1;
        },
        '\u{000A}', // LF  : Line Feed
        '\u{0085}', // NEL : Next Line
        '\u{000B}', // VT  : Vertical Tab
        '\u{000C}', // FF  : Form Feed
        '\u{2028}', // LS  : Line Separator
        '\u{2029}', // PS  : Paragraph Separator
        => return 1,
        else => return 0,
    };
}

fn isWhitespace(cp: u21) bool {
    return switch (cp) {
        '\n', '\r', '\t', '\\', ' ', ';' => true,
        else => false,
    };
}

/// Returns true if the codepoint is defined as a node terminator,
/// per the KDL Specification § 4 Full Grammar.
fn isNodeTerminator(cp: u21) bool {
    return switch (cp) {
        '\n',
        '\r',
        ';',
        '/', // single line comments
        => true,
        else => false,
    };
}

fn isSingleLineComment(slice: []const u8) bool {
    return slice.len >= 2 and slice[0] == '/' and slice[1] == '/';
}

pub fn isMultiLineString(slice: []const u8) bool {
    return slice.len >= 6 and std.mem.containsAtLeast(u8, slice, 2,
        \\"""
    );
}

// Tests
test "tokenizer website.kdl" {
    const document = @embedFile("test/website.kdl");

    var tok_iter = Tokenizer.init(document);
    try tok_iter.expectEqualToken(.string, "package", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.lbrace, "{", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.newline, "\n", tok_iter.nextNonWhitespace());

    try tok_iter.expectEqualToken(.string, "name", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.string, "my-pkg", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.newline, "\n", tok_iter.nextNonWhitespace());

    try tok_iter.expectEqualToken(.string, "version", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.string, "\"1.2.3\"", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.newline, "\n", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.newline, "\n", tok_iter.nextNonWhitespace());

    try tok_iter.expectEqualToken(.string, "dependencies", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.lbrace, "{", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.newline, "\n", tok_iter.nextNonWhitespace());

    try tok_iter.expectEqualToken(.comment,
        \\// Nodes can have standalone values as well as
    , tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.newline, "\n", tok_iter.nextNonWhitespace());

    try tok_iter.expectEqualToken(.comment,
        \\// key/value pairs.
    , tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.newline, "\n", tok_iter.nextNonWhitespace());

    try tok_iter.expectEqualToken(.string, "lodash", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.string, "\"^3.2.1\"", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.string, "optional", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.equal, "=", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.keyword, "#true", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.string, "alias", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.equal, "=", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.string, "underscore", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.newline, "\n", tok_iter.nextNonWhitespace());

    try tok_iter.expectEqualToken(.rbrace, "}", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.newline, "\n", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.newline, "\n", tok_iter.nextNonWhitespace());

    try tok_iter.expectEqualToken(.string, "scripts", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.lbrace, "{", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.newline, "\n", tok_iter.nextNonWhitespace());

    try tok_iter.expectEqualToken(.comment,
        \\// "Raw" and dedented multi-line strings are supported.
    , tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.newline, "\n", tok_iter.nextNonWhitespace());

    try tok_iter.expectEqualToken(.string, "message", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.string,
        \\"""
        \\      hello
        \\      world
        \\      """
    , tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.newline, "\n", tok_iter.nextNonWhitespace());

    try tok_iter.expectEqualToken(.string, "build", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.raw,
        \\#"""
        \\      echo "foo"
        \\      node -c "console.log('hello, world!');"
        \\      echo "foo" > some-file.txt
        \\      """#
    , tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.newline, "\n", tok_iter.nextNonWhitespace());

    try tok_iter.expectEqualToken(.rbrace, "}", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.newline, "\n", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.newline, "\n", tok_iter.nextNonWhitespace());

    try tok_iter.expectEqualToken(.comment,
        \\// `\` breaks up a single node across multiple lines.
    , tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.newline, "\n", tok_iter.nextNonWhitespace());

    try tok_iter.expectEqualToken(.string, "the-matrix", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.number, "1", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.number, "2", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.number, "3", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.continuation, "\\", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.newline, "\n", tok_iter.nextNonWhitespace());

    try tok_iter.expectEqualToken(.number, "4", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.number, "5", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.number, "6", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.continuation, "\\", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.newline, "\n", tok_iter.nextNonWhitespace());

    try tok_iter.expectEqualToken(.number, "7", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.number, "8", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.number, "9", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.newline, "\n", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.newline, "\n", tok_iter.nextNonWhitespace());

    try tok_iter.expectEqualToken(.comment,
        \\// "Slashdash" comments operate at the node level,
    , tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.newline, "\n", tok_iter.nextNonWhitespace());

    try tok_iter.expectEqualToken(.comment,
        \\// with just `/-`.
    , tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.newline, "\n", tok_iter.nextNonWhitespace());

    try tok_iter.expectEqualToken(.slashdash, "/-", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.string, "this-is-commented", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.lbrace, "{", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.newline, "\n", tok_iter.nextNonWhitespace());

    try tok_iter.expectEqualToken(.string, "this", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.string, "entire", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.string, "node", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.lbrace, "{", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.newline, "\n", tok_iter.nextNonWhitespace());

    try tok_iter.expectEqualToken(.string, "is", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.string, "gone", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.newline, "\n", tok_iter.nextNonWhitespace());

    try tok_iter.expectEqualToken(.rbrace, "}", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.newline, "\n", tok_iter.nextNonWhitespace());

    try tok_iter.expectEqualToken(.rbrace, "}", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.newline, "\n", tok_iter.nextNonWhitespace());

    try tok_iter.expectEqualToken(.rbrace, "}", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.newline, "\n", tok_iter.nextNonWhitespace());

    try tok_iter.expectEqualToken(.eof, "", tok_iter.nextNonWhitespace());
}

test "tokenizer whitespace" {
    const document = @embedFile("test/website.kdl");

    var tok_iter = Tokenizer.init(document);

    try tok_iter.expectEqualToken(.string, "package", tok_iter.next());
    try tok_iter.expectEqualToken(.whitespace, " ", tok_iter.next());
    try tok_iter.expectEqualToken(.lbrace, "{", tok_iter.next());
    try tok_iter.expectEqualToken(.newline, "\n", tok_iter.next());
    try tok_iter.expectEqualToken(.whitespace, "  ", tok_iter.next());
    try tok_iter.expectEqualToken(.string, "name", tok_iter.next());
    try tok_iter.expectEqualToken(.whitespace, " ", tok_iter.next());
    try tok_iter.expectEqualToken(.string, "my-pkg", tok_iter.next());
}

test "tokenizer BOM no version" {
    const document = @embedFile("test/bom-no-version.kdl");

    var tok_iter = Tokenizer.init(document);

    try tok_iter.expectEqualToken(.bom, "\u{FEFF}", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.comment, "// This file is UTF-8 encoded and starts with a Byte Order Mark", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.newline, "\n", tok_iter.nextNonWhitespace());

    try tok_iter.expectEqualToken(.string, "example", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.lbrace, "{", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.newline, "\n", tok_iter.nextNonWhitespace());

    try tok_iter.expectEqualToken(.string, "name", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.string, "\"BOM no version\"", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.newline, "\n", tok_iter.nextNonWhitespace());

    try tok_iter.expectEqualToken(.rbrace, "}", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.newline, "\n", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.eof, "", tok_iter.nextNonWhitespace());
}

test "tokenizer BOM with version" {
    const document = @embedFile("test/bom.kdl");

    var tok_iter = Tokenizer.init(document);

    try tok_iter.expectEqualToken(.bom, "\u{FEFF}", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.slashdash, "/-", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.string, "kdl-version", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.number, "2", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.newline, "\n", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.comment, "// This file is UTF-8 encoded and starts with a Byte Order Mark,", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.newline, "\n", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.comment, "// and is followed by a kdl-version identifier", tok_iter.nextNonWhitespace());
}

test "tokenizer raw string" {
    const document =
        \\node_1 prop=#""arg#"\n"#
        \\node_2 prop=##"#"arg#"#\n"##
    ;

    var tok_iter = Tokenizer.init(document);

    try tok_iter.expectEqualToken(.string, "node_1", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.string, "prop", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.equal, "=", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.raw,
        \\#""arg#"\n"#
    , tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.newline, "\n", tok_iter.nextNonWhitespace());

    try tok_iter.expectEqualToken(.string, "node_2", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.string, "prop", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.equal, "=", tok_iter.nextNonWhitespace());
    try tok_iter.expectEqualToken(.raw,
        \\##"#"arg#"#\n"##
    , tok_iter.nextNonWhitespace());
}

const log = std.log.scoped(.@"kdl-tokenizer");
const testing = std.testing;
const std = @import("std");
