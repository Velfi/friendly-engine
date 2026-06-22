//! # KDL
//!
//! KDL is a node-oriented document language;
//! the specification can be found [at this link][kdl-spec].
//! This library implements a streaming tokenizer and parser for kdl documents.
//!
//! [kdl-spec]: https://kdl.dev/spec/

pub const Tokenizer = @import("Tokenizer.zig");
pub const Parser = @import("Parser.zig");
pub const string_utils = @import("string.zig");

pub const TokenTable = std.MultiArrayList(Tokenizer.Token);
/// Tokenizes contents of reader until `EndOfStream` and returns the list of tokens.
/// To free used memory, call `tokenizeFree`.
pub fn tokenize(gpa: std.mem.Allocator, reader: *std.Io.Reader, opt: struct {
    /// Size of output buffer to be used by the streaming tokenizer.
    /// This sets an upper bound on the token length.
    tok_buffer_size: usize = 256,
    parse_strings: bool = false,
    /// Options to pass to the streaming tokenizer.
    tokenizer: Tokenizer.Options = .{},
}) !TokenTable {
    var tok_table = TokenTable{};
    errdefer tokenizeFree(gpa, &tok_table);
    // TODO errdefer
    var tok_iter = Tokenizer.init(reader, gpa, opt.tokenizer);
    defer tok_iter.deinit();
    while (try tok_iter.next()) |tok| {
        const slice = slice: {
            if (opt.parse_strings) switch (tok.tag) {
                .node, .string, .raw_string => {
                    const parsed = string_utils.makeRealString(gpa, tok.slice) catch {
                        // log.err("couldn't parse as multiline string: \"{s}\"", .{tok.slice});
                        break :slice try gpa.dupe(u8, tok.slice);
                    };
                    break :slice parsed;
                },
                else => {},
            };
            break :slice try gpa.dupe(u8, tok.slice);
        };

        try tok_table.append(gpa, .{
            .tag = tok.tag,
            .slice = slice,
        });
    }
    return tok_table;
}

/// Frees memory used by result of `tokenize`.
pub fn tokenizeFree(gpa: std.mem.Allocator, tok_table: *TokenTable) void {
    for (tok_table.items(.slice)) |tok| {
        gpa.free(tok);
    }
    tok_table.deinit(gpa);
}

pub fn skipSlashdash(tokenizer: *Tokenizer, initial_token: Tokenizer.Token) !void {
    var iter = slashdashIter(tokenizer, initial_token);
    while (try iter.next()) |_| {}
}

/// Initial token must be a slashdash token.
pub fn slashdashIter(tokenizer: *Tokenizer, initial_token: Tokenizer.Token) SlashdashIter {
    std.debug.assert(initial_token.tag == .slashdash);

    return .{
        .tokenizer = tokenizer,
        .scope = .unknown,
    };
}

const SlashdashIter = struct {
    depth: usize = 0,
    tokenizer: *Tokenizer,
    scope: Scope,
    complete: bool = false,

    const Scope = enum {
        unknown,
        node,
        block,
        arg_or_prop,
        prop,
        /// Determine scope of slashdash
        fn fromTag(tag: Tokenizer.Tag) Scope {
            return switch (tag) {
                .child_block_begin => .block,
                .node => .node,
                .string, .raw_string, .number, .keyword => .arg_or_prop,
                .comment, .slashdash, .whitespace => .unknown,
                .type_begin, .type_end => .unknown,
                .equals, .child_block_end => .unknown,
                .invalid => .unknown,
            };
        }
    };

    pub fn next(this: *@This()) !?Tokenizer.Token {
        if (this.complete) return null;
        if (try this.tokenizer.peek()) |token| {
            if (this.scope == .arg_or_prop) {
                if (token.tag != .equals) {
                    // argument skip finished, drop the token
                    this.complete = true;
                    return this.tokenizer.next();
                }
                this.scope = .prop;
            }
            switch (token.tag) {
                .child_block_begin => {
                    this.depth += 1;
                },
                .child_block_end => {
                    if (this.depth == 0) {
                        this.complete = true;
                        return null;
                    }
                    this.depth -= 1;
                },
                .node => {
                    if ((this.scope == .node or this.scope == .block) and this.depth == 0) {
                        this.complete = true;
                        return null; // dont drop the token
                    }
                },
                .string, .raw_string, .number, .keyword => {
                    if (this.scope == .prop) { // drop the token
                        this.complete = true;
                        return this.tokenizer.next();
                    }
                },
                else => {},
            }
            if (this.scope == .unknown) {
                this.scope = .fromTag(token.tag);
            }
            std.debug.assert(this.depth >= 0);
        }
        return this.tokenizer.next();
    }
};

// # Tests

// test "tokenize 3.1.1. Example" {
//     const document =
//         \\foo {
//         \\    bar
//         \\}
//         \\baz
//     ;
//     var reader = std.Io.Reader.fixed(document);

//     var token_table = try tokenize(testing.allocator, &reader, .{});
//     defer tokenizeFree(testing.allocator, &token_table);

//     try testing.expectEqualSlices(
//         Tokenizer.Tag,
//         &.{ .node, .child_block_begin, .node, .child_block_end, .node },
//         token_table.items(.tag),
//     );
// }

// test "tokenize 3.2.1. Example" {
//     const document = @embedFile("test/example.3.2.1.kdl");
//     var reader = std.Io.Reader.fixed(document);

//     var token_table = try tokenize(testing.allocator, &reader, .{});
//     defer tokenizeFree(testing.allocator, &token_table);

//     try testing.expectEqualSlices(
//         Tokenizer.Tag,
//         &.{
//             .comment,
//             .node,
//             .number,
//             .string,
//             .equals,
//             .string,
//             .number,
//             .child_block_begin,
//             .node,
//             .type_begin,
//             .string,
//             .type_end,
//             .node,
//             .number,
//             .number,
//             .child_block_end,
//         },
//         token_table.items(.tag),
//     );
// }

// test "tokenize 3.3.1. Example" {
//     const document = @embedFile("test/example.3.3.1.kdl");
//     var reader = std.Io.Reader.fixed(document);

//     var token_table = try tokenize(testing.allocator, &reader, .{});
//     defer tokenizeFree(testing.allocator, &token_table);

//     try testing.expectEqualSlices(
//         Tokenizer.Tag,
//         &.{
//             .node,
//             .number,
//             .number,
//             .comment,
//             .number,
//             .number,
//             .comment,
//         },
//         token_table.items(.tag),
//     );
// }

// test "tokenize 3.5.1. Example" {
//     const document = @embedFile("test/example.3.5.1.kdl");
//     var reader = std.Io.Reader.fixed(document);

//     var token_table = try tokenize(testing.allocator, &reader, .{});
//     defer tokenizeFree(testing.allocator, &token_table);

//     try testing.expectEqualSlices(
//         Tokenizer.Tag,
//         &.{
//             .node,
//             .number,
//             .number,
//             .number,
//             .string,
//             .string,
//             .string,
//         },
//         token_table.items(.tag),
//     );
// }

// test "tokenize 3.6.1. Example" {
//     const document = @embedFile("test/example.3.6.1.kdl");
//     var reader = std.Io.Reader.fixed(document);

//     var token_table = try tokenize(testing.allocator, &reader, .{});
//     defer tokenizeFree(testing.allocator, &token_table);

//     try testing.expectEqualSlices(
//         Tokenizer.Tag,
//         &.{
//             .node,
//             .child_block_begin,
//             .node,
//             .node,
//             .child_block_end,
//             .node,
//             .child_block_begin,
//             .node,
//             .node,
//             .child_block_end,
//         },
//         token_table.items(.tag),
//     );
// }

// test "tokenize 3.8.4. Example" {
//     const document = @embedFile("test/example.3.8.4.kdl");
//     var reader = std.Io.Reader.fixed(document);

//     var token_table = try tokenize(testing.allocator, &reader, .{});
//     defer tokenizeFree(testing.allocator, &token_table);

//     try testing.expectEqualSlices(
//         Tokenizer.Tag,
//         &.{
//             .node,
//             .type_begin,
//             .string,
//             .type_end,
//             .number,

//             .node,
//             .string,
//             .equals,
//             .type_begin,
//             .string,
//             .type_end,
//             .string,

//             .type_begin,
//             .string,
//             .type_end,
//             .node,
//             .string,

//             .type_begin,
//             .string,
//             .type_end,
//             .node,
//             .string,
//             .equals,
//             .string,
//         },
//         token_table.items(.tag),
//     );
// }

// test "tokenize slashdash" {
//     const document = @embedFile("test/example.slashdash.kdl");
//     var reader = std.Io.Reader.fixed(document);

//     var token_table = try tokenize(testing.allocator, &reader, .{
//         .tokenizer = .{ .include_comments = .all },
//     });
//     defer tokenizeFree(testing.allocator, &token_table);

//     try testing.expectEqualSlices(
//         Tokenizer.Tag,
//         &.{
//             .slashdash,
//             .node,
//             .child_block_begin,
//             .child_block_end,
//         },
//         token_table.items(.tag),
//     );
// }

// test "tokenize Website Example" {
//     const document = @embedFile("test/website.kdl");

//     var reader = std.Io.Reader.fixed(document);

//     var token_table = try tokenize(testing.allocator, &reader, .{});
//     defer tokenizeFree(testing.allocator, &token_table);

//     try testing.expectEqualSlices(
//         Tokenizer.Tag,
//         // zig fmt: off
//         &.{ .node, .child_block_begin,
//                    .node, .string,
//                    .node, .string,
//                    .node, .child_block_begin, .comment, .comment,
//                    .node, .string, .string, .equals, .keyword, .string, .equals, .string,
//                    .child_block_end,
//                    .node, .child_block_begin, .comment,
//                    .node, .string,
//                    .node, .raw_string,
//                    .child_block_end,
//                    .comment,
//                    .node, .number, .number, .number,
//                           .number, .number, .number,
//                           .number, .number, .number,
//                     .comment, .comment,
//                    .slashdash,
//                    .node, .child_block_begin,
//                           .node, .string, .string, .child_block_begin,
//                                  .node, .string,
//                           .child_block_end,
//                    .child_block_end,
//             .child_block_end,
//         },
//         // zig fmt: on
//         token_table.items(.tag),
//     );
// }

// test "tokenize Version 1 Mark" {
//     const document = @embedFile("test/version1.kdl");

//     var reader = std.Io.Reader.fixed(document);

//     var token_table = try tokenize(testing.allocator, &reader, .{});
//     defer tokenizeFree(testing.allocator, &token_table);

//     // Not failing the tokenize step means success
// }

// test "tokenize Version 2 Mark" {
//     const document = @embedFile("test/version2.kdl");

//     var reader = std.Io.Reader.fixed(document);

//     var token_table = try tokenize(testing.allocator, &reader, .{});
//     defer tokenizeFree(testing.allocator, &token_table);

//     // Not failing the tokenize step means success
// }

// test "tokenize Comment Multi-line" {
//     const document = @embedFile("test/multiline-comment.kdl");

//     var reader = std.Io.Reader.fixed(document);

//     var token_table = try tokenize(testing.allocator, &reader, .{});
//     defer tokenizeFree(testing.allocator, &token_table);

//     try testing.expectEqualSlices(
//         Tokenizer.Tag,
//         &.{
//             .comment,
//             .node,
//             .string,
//             .string,
//             .equals,
//             .string,
//             .comment,
//             .node,
//             .string,
//             .string,
//             .equals,
//             .string,
//         },
//         token_table.items(.tag),
//     );
// }

// test "tokenize Website slashdash" {
//     const document = @embedFile("test/website-slashdash.kdl");

//     var reader = std.Io.Reader.fixed(document);

//     var token_table = try tokenize(testing.allocator, &reader, .{});
//     defer tokenizeFree(testing.allocator, &token_table);

//     try testing.expectEqualSlices(
//         Tokenizer.Tag,
//         &.{
//             .comment,
//             .slashdash,
//             .node,
//             .string,
//             .string,
//             .equals,
//             .number,
//             .child_block_begin,
//             .node,
//             .node,
//             .node,
//             .child_block_end,
//             .node,
//             .slashdash,
//             .string,
//             .string,
//             .slashdash,
//             .string,
//             .equals,
//             .string,
//             .slashdash,
//             .child_block_begin,
//             .node,
//             .node,
//             .child_block_end,
//             .comment,
//             .node,
//             .string,
//         },
//         token_table.items(.tag),
//     );
// }

// test "normalize multi-line string" {
//     const document = @embedFile("test/website.kdl");

//     var reader = std.Io.Reader.fixed(document);

//     var token_table = try tokenize(testing.allocator, &reader, .{});
//     defer tokenizeFree(testing.allocator, &token_table);

//     try std.testing.expectEqual(Tokenizer.Tag.raw_string, token_table.items(.tag)[25]);
//     const raw_string = token_table.items(.slice)[25];
//     const normalized = try string_utils.makeRealString(testing.allocator, raw_string);
//     defer testing.allocator.free(normalized);
//     try testing.expectEqualSlices(u8,
//         \\echo "foo"
//         \\node -c "console.log('hello, world!');"
//         \\echo "foo" > some-file.txt
//     , normalized);
// }

// test "normalize multi-line string with crlf" {
//     // NOTE: Writing this out with escaped strings to prevent git from
//     //       turning the CRLF sequences into just line feeds.
//     const raw_string = string_utils.multiline_delimiter ++ "\r\n" ++
//         "  echo \"foo\"\r\n" ++
//         "  node -c \"console.log('hello, world!');\"\r\n" ++
//         "  echo \"foo\" > some-file.txt\r\n" ++
//         "  " ++ string_utils.multiline_delimiter;
//     const normalized = try string_utils.makeRealString(testing.allocator, raw_string);
//     defer testing.allocator.free(normalized);
//     try testing.expectEqualSlices(u8,
//         \\echo "foo"
//         \\node -c "console.log('hello, world!');"
//         \\echo "foo" > some-file.txt
//     , normalized);
// }

// test "normalize multi-line string with mixed line endings" {
//     // NOTE: Writing this out with escaped strings to prevent git from
//     //       turning the CRLF sequences into just line feeds.
//     const raw_string = string_utils.multiline_delimiter ++ "\n" ++
//         "  echo \"foo\"\r\n" ++
//         "  node -c \"console.log('hello, world!');\"\r" ++
//         "  echo \"foo\" > some-file.txt\r\n" ++
//         "  " ++ string_utils.multiline_delimiter;
//     const normalized = try string_utils.makeRealString(testing.allocator, raw_string);
//     defer testing.allocator.free(normalized);
//     try testing.expectEqualSlices(u8,
//         \\echo "foo"
//         \\node -c "console.log('hello, world!');"
//         \\echo "foo" > some-file.txt
//     , normalized);
// }

// test "normalize multi-line string preserve leading indentation" {
//     const string = string_utils.multiline_delimiter ++ "\n" ++
//         \\  def hello():
//         \\    print ("hello, world!")
//     ++ "\n  " ++ string_utils.multiline_delimiter;
//     const normalized = try string_utils.makeRealString(testing.allocator, string);
//     defer testing.allocator.free(normalized);
//     try testing.expectEqualSlices(u8,
//         \\def hello():
//         \\  print ("hello, world!")
//     , normalized);
// }

// test "multi-line string node name" {
//     const document =
//         \\"""
//         \\    this is a node
//         \\    """ argument1 argument2
//     ;
//     var reader = std.Io.Reader.fixed(document);

//     var token_table = try tokenize(testing.allocator, &reader, .{
//         .parse_strings = true,
//     });
//     defer tokenizeFree(testing.allocator, &token_table);

//     try testing.expectEqualSlices(
//         Tokenizer.Tag,
//         &.{
//             .node,
//             .string,
//             .string,
//         },
//         token_table.items(.tag),
//     );
//     const strings = token_table.items(.slice);
//     try testing.expectEqualStrings("this is a node", strings[0]);
//     try testing.expectEqualStrings("argument1", strings[1]);
//     try testing.expectEqualStrings("argument2", strings[2]);
// }

// test "tokenize Playground Example" {
//     const document = @embedFile("test/playground.example.kdl");
//     var reader = std.Io.Reader.fixed(document);

//     var token_table = try tokenize(testing.allocator, &reader, .{});
//     defer tokenizeFree(testing.allocator, &token_table);

//     try testing.expectEqualSlices(
//         Tokenizer.Tag,
//         // zig fmt: off
//         &.{ .node, .number, .string, .string, .equals, .type_begin, .string, .type_end, .number, .child_block_begin,
//                 .type_begin, .string, .type_end, .node, .keyword, .keyword, .keyword,
//             .child_block_end
//         },
//         // zig fmt: on
//         token_table.items(.tag),
//     );
// }

comptime {
    if (builtin.is_test) {
        _ = Tokenizer;
        _ = Parser;
        _ = string_utils;
    }
}

const builtin = @import("builtin");
const testing = std.testing;
const log = std.log.scoped(.kdl);
const std = @import("std");
