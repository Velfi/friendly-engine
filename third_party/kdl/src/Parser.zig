const Parser = @This();

tokenizer: Tokenizer,
node_value: ?Value = null,
next_token: ?Tokenizer.Token = null,
depth: i32,

pub fn init(buffer: [:0]const u8) @This() {
    return .{
        .tokenizer = .init(buffer),
        .next_token = null,
        .depth = 0,
    };
}

pub const DeinitStatus = struct {
    at_end: bool,
    depth: enum { ok, lo, hi },
};

/// If the parser state is in an unexpected state, returns `DeinitStatus`.
/// Otherwiser, returns null.
pub fn deinit(parser: *const Parser) ?DeinitStatus {
    if (parser.node_value == null and
        parser.next_token == null and
        parser.depth == 0)
        return null;
    return DeinitStatus{
        .at_end = parser.next_token == null and parser.node_value == null,
        .depth = switch (std.math.order(parser.depth, 0)) {
            .eq => .ok,
            .gt => .hi,
            .lt => .lo,
        },
    };
}

/// A single KDL node.
/// Use `argcount` to determine the number of arguments.
/// Use `arg` to get arguments by index.
/// Use `prop` to  get properties by key.
pub const Node = struct {
    annotation: ?[]const u8 = null,
    name: []const u8,
    args: []Value,
    props: StringHashMap(Value),
    depth: i32,

    pub const StaticProperty = struct {
        key: []const u8,
        val: Value,

        pub fn u(key: []const u8, ann: ?[]const u8, val: []const u8) StaticProperty {
            return .{ .key = key, .val = .{ .ann = ann, .val = val } };
        }

        pub fn t(key: []const u8, ann: ?[]const u8, val: []const u8) StaticProperty {
            return .{ .key = key, .val = .{ .ann = ann, .val = val } };
        }
    };

    pub fn init(gpa: std.mem.Allocator, node: Value, args: []const Value, props: []const StaticProperty) !*Node {
        const this = try gpa.create(Node);
        this.* = .{
            .annotation = node.ann,
            .name = node.val,
            .args = try gpa.dupe(Value, args),
            .props = .empty,
        };
        try this.props.ensureTotalCapacity(gpa, @intCast(props.len));
        for (props) |prop| {
            this.props.putAssumeCapacityNoClobber(prop.key, prop.val);
        }
        return this;
    }
    pub fn deinit(node: *Node, gpa: std.mem.Allocator) void {
        if (node.annotation) |ann| gpa.free(ann);
        gpa.free(node.name);
        for (node.args) |str_arg| {
            if (str_arg.ann) |ann| gpa.free(ann);
            gpa.free(str_arg.val);
        }
        gpa.free(node.args);
        var iter = node.props.valueIterator();
        while (iter.next()) |prop| {
            if (prop.ann) |ann| gpa.free(ann);
            gpa.free(prop.val);
        }
        node.props.deinit(gpa);
        gpa.destroy(node);
    }

    pub fn argcount(this: @This()) usize {
        return this.arguments.len;
    }

    /// Attempts to parse a string value into the given type. Behavior depends on the type `T`.
    /// - `bool`: Value must be equal to the keywords #true or #false.
    pub fn arg(node: Node, comptime T: type, arg_idx: usize) ?T {
        if (arg_idx > node.args.len) return null;
        return stringToType(T, node.args[arg_idx].val);
    }
};

/// Attempts to parse a string value into the given type. Behavior depends on the type `T`.
/// - `bool`: Value must be equal to the keywords #true or #false.
fn stringToType(comptime T: type, string_value: []const u8) ?T {
    const tinfo: std.builtin.Type = @typeInfo(T);
    switch (tinfo) {
        .pointer => {
            if (T == []const u8) return string_value;
            @compileError("Non-string pointers not supported");
        },
        .bool => {
            if (std.mem.eql(u8, string_value, "#true")) return true;
            if (std.mem.eql(u8, string_value, "#false")) return false;
            return null;
        },
        .int => {
            // KDL ignores trailing underscores, while parseInt errors on them
            const trimmed = std.mem.trimEnd(u8, string_value, "_");
            return std.fmt.parseInt(T, trimmed, 0) catch null;
        },
        .float => {
            // KDL ignores trailing underscores
            const trimmed = std.mem.trimEnd(u8, string_value, "_");
            return std.fmt.parseFloat(T, trimmed) catch null;
        },
        .@"enum" => return std.meta.stringToEnum(T, string_value),
        else => @compileError("Type " ++ @typeName(T) ++ " not supported"),
    }
}

pub const Value = struct {
    /// Type annotation.
    ann: ?[]const u8 = null,
    /// Must not be .none
    val: []const u8,
    val_tok: Tokenizer.Token.Tag,

    pub fn u(val: []const u8) Value {
        return .{ .val = val };
    }

    pub fn t(ann: []const u8, val: []const u8) Value {
        return .{ .ann = ann, .val = val };
    }

    pub fn format(val: Value, writer: *std.Io.Writer) !void {
        try writer.print("({?s}){s}", .{ val.ann, val.val });
    }

    /// Attempts to parse a string value into the given type. Behavior depends on the type `T`.
    /// - `bool`: Value must be equal to the keywords #true or #false.
    pub fn into(value: Value, comptime T: type) ?T {
        return stringToType(T, value.val);
    }
};

pub const Property = struct {
    key: []const u8,
    ann: ?[]const u8 = null,
    val: []const u8,
    val_tok: Tokenizer.Token.Tag,

    pub fn format(prop: Property, writer: *std.Io.Writer) !void {
        try writer.print("{s}=({?s}){s}", .{ prop.key, prop.ann, prop.val });
    }
};

pub const Event = union(enum) {
    node: Value,
    arg: Value,
    prop: Property,
    child_block_begin,
    child_block_end,
    invalid,
    eof,

    pub fn format(event: Event, writer: *std.Io.Writer) !void {
        switch (event) {
            inline .node,
            .arg,
            .prop,
            => |val| {
                try writer.print("{f}", .{val});
            },
            .child_block_begin => {
                try writer.writeAll("{");
            },
            .child_block_end => {
                try writer.writeAll("}");
            },
            .invalid => {
                try writer.writeAll("INVALID");
            },
            .eof => {
                try writer.writeAll("EOF");
            },
        }
    }
};

const State = enum {
    start,
    invalid,
    params,
    property,
    annotation,
    slashdash_node,
    slashdash_children,
    slashdash_param,
};

/// Tries to read the next node from the token stream and returns `Event.node` if successful.
/// Returns `Event.child_block_begin` when a child block starts
/// and `Event.child_block_end` when a child block ends.
/// If there are no more tokens to read, returns null.
///
/// Strings in `Event.node` are valid only until `next()` is called again.
pub fn next(this: *@This()) !Event {
    var token = this.next_token orelse this.tokenizer.nextParseable();
    this.next_token = null;
    var property_str: ?[]const u8 = null;
    var annotation_prev_state: ?State = null;
    var annotation_tok: ?Tokenizer.Token = null;
    const start_state = if (this.node_value) |_| State.params else State.start;
    state: switch (start_state) {
        .start => switch (token.tag) {
            .string, .raw => {
                this.node_value = .{
                    .ann = if (annotation_tok) |ann| this.tokenizer.text(ann) else null,
                    .val = this.tokenizer.text(token),
                    .val_tok = token.tag,
                };
                annotation_tok = null;
                return .{ .node = this.node_value.? };
            },
            .lparen => {
                token = this.tokenizer.nextParseable();
                annotation_prev_state = .start;
                continue :state .annotation;
            },
            .lbrace => {
                // End of node
                this.next_token = this.tokenizer.nextParseable();
                this.depth += 1;
                return .child_block_begin;
            },
            .rbrace => {
                // End of node
                this.next_token = this.tokenizer.nextParseable();
                this.depth -= 1;
                return .child_block_end;
            },
            .newline => {
                token = this.tokenizer.nextParseable();
                continue :state .start;
            },
            .eof => {
                if (annotation_tok) |_| continue :state .invalid;
                return .eof;
            },
            .slashdash => {
                token = this.tokenizer.nextParseable();
                continue :state .slashdash_node;
            },
            .continuation => {
                token = this.tokenizer.nextParseable();
                continue :state .start;
            },
            else => continue :state .invalid,
        },
        .params => {
            switch (token.tag) {
                .eof, .newline, .semicolon, .lbrace => {
                    // end node
                    this.node_value = null;
                    continue :state .start;
                },
                .lparen => {
                    token = this.tokenizer.nextParseable();
                    annotation_prev_state = .params;
                    continue :state .annotation;
                },
                .string, .raw, .number, .keyword => {
                    const ann = if (annotation_tok) |ann| this.tokenizer.text(ann) else null;
                    const val = this.tokenizer.text(token);
                    annotation_tok = null;

                    // grab next token, save it in case this is an argument
                    this.next_token = this.tokenizer.nextParseable();
                    if (this.next_token.?.tag == .equal) {
                        property_str = val;
                        if (ann != null) continue :state .invalid;
                        this.next_token = null;
                        token = this.tokenizer.nextParseable();
                        continue :state .property;
                    } else {
                        // return argument
                        return .{ .arg = .{
                            .ann = ann,
                            .val = val,
                            .val_tok = token.tag,
                        } };
                    }
                },
                .continuation => {
                    if (this.tokenizer.nextParseable().tag != .newline) continue :state .invalid;
                    token = this.tokenizer.nextParseable();
                    continue :state .params;
                },
                .slashdash => {
                    if (annotation_tok) |_| continue :state .invalid;
                    continue :state .slashdash_param;
                },
                .equal,
                .invalid,
                .rparen,
                .rbrace,
                .comment,
                .whitespace,
                .bom,
                => continue :state .invalid,
            }
        },
        .property => {
            switch (token.tag) {
                .lparen => {
                    token = this.tokenizer.nextParseable();
                    annotation_prev_state = .property;
                    continue :state .annotation;
                },
                .string, .raw, .number, .keyword => {
                    const ann = if (annotation_tok) |ann| this.tokenizer.text(ann) else null;
                    const val = this.tokenizer.text(token);
                    annotation_tok = null;

                    return .{ .prop = .{
                        .key = property_str orelse continue :state .invalid,
                        .ann = ann,
                        .val = val,
                        .val_tok = token.tag,
                    } };
                },
                .eof,
                .newline,
                .semicolon,
                .lbrace,
                .continuation,
                .slashdash,
                .equal,
                .invalid,
                .rparen,
                .rbrace,
                .comment,
                .whitespace,
                .bom,
                => continue :state .invalid,
            }
        },
        .annotation => {
            switch (token.tag) {
                .string => {
                    if (annotation_tok) |_| continue :state .invalid;
                    annotation_tok = token;
                    token = this.tokenizer.nextParseable();
                    continue :state .annotation;
                },
                .rparen => {
                    token = this.tokenizer.nextParseable();
                    const state = annotation_prev_state orelse continue :state .invalid;
                    annotation_prev_state = null;
                    continue :state state;
                },
                else => {
                    continue :state .invalid;
                },
            }
        },
        .slashdash_node => {
            while (token.tag != .eof) : (token = this.tokenizer.nextParseable()) {
                switch (token.tag) {
                    .newline,
                    .semicolon,
                    => break,
                    .lbrace => continue :state .slashdash_children,
                    else => {},
                }
            }
            continue :state .start;
        },
        .slashdash_param => {
            std.debug.assert(token.tag == .slashdash);
            const maybe_arg = this.tokenizer.nextParseable(); // skip arg or prop key
            switch (maybe_arg.tag) {
                .equal, .semicolon, .newline, .eof => continue :state .invalid,
                .continuation => {
                    while (true) {
                        const sd_arg = this.tokenizer.nextParseable(); // skip arg or prop key
                        switch (sd_arg.tag) {
                            .whitespace, .comment => continue,
                            .newline => break,
                            else => continue :state .invalid,
                        }
                    }
                    continue :state .slashdash_param;
                },
                .lbrace => continue :state .slashdash_children,
                else => {},
            }
            token = this.tokenizer.nextParseable(); // maybe equal token
            switch (token.tag) {
                .equal => {
                    _ = this.tokenizer.nextParseable(); // skip prop
                    token = this.tokenizer.nextParseable(); // ready next token
                },
                .lbrace => continue :state .slashdash_children,
                else => {},
            }
            continue :state .params;
        },
        .slashdash_children => {
            while (token.tag != .rbrace) : (token = this.tokenizer.nextParseable()) {
                if (token.tag == .eof) continue :state .invalid;
            }
            token = this.tokenizer.nextParseable();
            if (token.tag != .newline) continue :state .invalid;
            continue :state .start;
        },
        .invalid => {
            // TODO
            if (annotation_tok) |ann_tok| {
                log.warn("[{}..{}]={} prop({?s}) ann_state({?}) ann([{}..{}]={}) start({})", .{
                    token.loc.start,
                    token.loc.stop,
                    token.tag,
                    property_str,
                    annotation_prev_state,
                    ann_tok.loc.start,
                    ann_tok.loc.stop,
                    ann_tok.tag,
                    start_state,
                });
            } else {
                log.warn("[{}..{}]={} prop({?s}) ann_state({?}) ann({?}) start({})", .{
                    token.loc.start,
                    token.loc.stop,
                    token.tag,
                    property_str,
                    annotation_prev_state,
                    annotation_tok,
                    start_state,
                });
            }
            return .invalid;
        },
    }
}

pub const NodeIterator = struct {
    parser: *Parser,
    next_event: ?Parser.Event = null,

    pub const Event = union(Tag) {
        node: *Node,
        child_block_begin,
        child_block_end,

        pub const Tag = enum { node, child_block_begin, child_block_end };
    };

    pub fn next(this: *@This(), gpa: std.mem.Allocator) !NodeIterator.Event {
        var event = this.next_event orelse try this.parser.next();

        var node: *Node = try gpa.create(Node);
        errdefer gpa.destroy(node);

        switch (event) {
            .node => |node_val| {
                node.annotation = if (node_val.ann) |ann| try string_util.makeRealString(gpa, ann) else null;
                node.name = try string_util.makeRealString(gpa, node_val.val);
                node.depth = this.parser.depth;
            },
            .child_block_begin => {
                this.next_event = null;
                gpa.destroy(node);
                return .child_block_begin;
            },
            .child_block_end => {
                this.next_event = null;
                gpa.destroy(node);
                return .child_block_end;
            },
            .prop,
            .arg,
            .invalid,
            => {
                std.log.err("Unexpected parse event: {any}", .{event});
                return error.Invalid;
            },
            .eof => return error.EndOfFile,
        }
        errdefer {
            if (node.annotation) |ann| gpa.free(ann);
            gpa.free(node.name);
        }

        var args = std.ArrayList(Value).empty;
        errdefer {
            for (args.items) |arg| {
                if (arg.ann) |ann| gpa.free(ann);
                gpa.free(arg.val);
            }
            args.deinit(gpa);
        }
        var props = StringHashMap(Value).empty;
        errdefer {
            var iter = props.valueIterator();
            while (iter.next()) |prop| {
                if (prop.ann) |ann| gpa.free(ann);
                gpa.free(prop.val);
            }
            props.deinit(gpa);
        }

        event = try this.parser.next();

        while (event != .eof) : (event = try this.parser.next()) switch (event) {
            .node => {
                break;
            },
            .arg => |arg| try args.append(gpa, .{
                .ann = if (arg.ann) |ann| try string_util.makeRealString(gpa, ann) else null,
                .val = try string_util.makeRealString(gpa, arg.val),
                .val_tok = arg.val_tok,
            }),
            .prop => |prop| {
                const maybe_prev = try props.fetchPut(gpa, prop.key, .{
                    .ann = if (prop.ann) |ann| try string_util.makeRealString(gpa, ann) else null,
                    .val = try string_util.makeRealString(gpa, prop.val),
                    .val_tok = prop.val_tok,
                });
                if (maybe_prev) |prev| {
                    if (prev.value.ann) |ann| gpa.free(ann);
                    gpa.free(prev.value.val);
                }
            },
            .child_block_begin, .child_block_end, .eof => break,
            .invalid => return error.Invalid,
        };

        this.next_event = event;

        node.args = try args.toOwnedSlice(gpa);
        node.props = props;

        return .{ .node = node };
    }
};

pub fn nodeIterator(this: *@This()) NodeIterator {
    return NodeIterator{ .parser = this };
}

test "parser" {
    const document = @embedFile("test/playground.example.kdl");

    var parser = Parser.init(document);

    {
        try std.testing.expectEqualStrings("foo", (try parser.next()).node.val);
        try std.testing.expectEqualStrings("1", (try parser.next()).arg.val);
        try std.testing.expectEqualStrings("\"two\"", (try parser.next()).arg.val);
        const prop = (try parser.next()).prop;
        try std.testing.expectEqualStrings("three", prop.key);
        try std.testing.expectEqualStrings("decimal", prop.ann.?);
        try std.testing.expectEqualStrings("0xff", prop.val);
    }

    try std.testing.expectEqual(.child_block_begin, try parser.next());

    {
        const node = (try parser.next()).node;
        try std.testing.expectEqualStrings("thing", node.ann.?);
        try std.testing.expectEqualStrings("bar", node.val);
        try std.testing.expectEqualStrings("#true", (try parser.next()).arg.val);
        try std.testing.expectEqualStrings("#false", (try parser.next()).arg.val);
        try std.testing.expectEqualStrings("#null", (try parser.next()).arg.val);
    }

    try std.testing.expectEqual(.child_block_end, try parser.next());
    try std.testing.expectEqual(.eof, try parser.next());

    try std.testing.expectEqual(null, parser.deinit());
}

test "parser nodeIterator" {
    const document = @embedFile("test/playground.example.kdl");
    const gpa = std.testing.allocator;

    var parser = Parser.init(document);
    var node_iter = parser.nodeIterator();

    {
        const event = try node_iter.next(gpa);
        try std.testing.expectEqual(.node, @as(NodeIterator.Event.Tag, event));
        defer event.node.deinit(gpa);
    }

    try std.testing.expectEqual(.child_block_begin, try node_iter.next(gpa));

    {
        const event = try node_iter.next(gpa);
        try std.testing.expectEqual(.node, @as(NodeIterator.Event.Tag, event));
        defer event.node.deinit(gpa);
    }

    try std.testing.expectEqual(.child_block_end, try node_iter.next(gpa));
    try std.testing.expectError(error.EndOfFile, node_iter.next(gpa));

    try std.testing.expectEqual(null, parser.deinit());
}

test "parser does not inifinitely loop" {
    const document = @embedFile("test/example.3.2.1.kdl");

    var parser = Parser.init(document);

    var event = try parser.next();
    var iterations: usize = 0;
    while (event != .eof) : ({
        event = try parser.next();
        iterations += 1;
    }) {
        if (iterations > 10) {
            return error.TestIterationCount;
        }
    }

    try std.testing.expectEqual(null, parser.deinit());
}

test "parser nodeIterator duplicate property" {
    const document = @embedFile("test/duplicate-prop.kdl");
    const gpa = std.testing.allocator;

    var parser = Parser.init(document);
    var node_iter = parser.nodeIterator();

    var iterations: usize = 0;
    while (node_iter.next(gpa) catch null) |event| : (iterations += 1) {
        switch (event) {
            .node => |node| {
                defer node.deinit(gpa);
                try std.testing.expectEqual(1, node.props.size);
            },
            .child_block_begin,
            .child_block_end,
            => return error.UnexpectedChildBlock,
        }
        if (iterations > 1) {
            return error.TestIterationCount;
        }
    }

    try std.testing.expectError(error.EndOfFile, node_iter.next(gpa));
    try std.testing.expectEqual(null, parser.deinit());
}

// test "parser zkdl config" {
//     const document = @embedFile("zkdl.default.kdl");

//     var parser = try Parser.init(std.testing.allocator, document);
//     defer parser.deinit();

//     try parser.expectNode(.{ "", "node" }, &.{.{ "", "blue" }}, &.{}, (try parser.next()).node);
//     try parser.expectNode(.{ "", "string" }, &.{.{ "", "green" }}, &.{}, (try parser.next()).node);
//     try parser.expectNode(.{ "", "raw_string" }, &.{.{ "", "magenta" }}, &.{}, (try parser.next()).node);
//     try parser.expectNode(.{ "", "number" }, &.{.{ "", "red" }}, &.{}, (try parser.next()).node);
//     try parser.expectNode(.{ "", "keyword" }, &.{.{ "", "blue" }}, &.{}, (try parser.next()).node);
//     try parser.expectNode(.{ "", "equals" }, &.{.{ "", "bright_white" }}, &.{}, (try parser.next()).node);
//     try parser.expectNode(.{ "", "child_block_begin" }, &.{.{ "", "bright_white" }}, &.{}, (try parser.next()).node);
//     try parser.expectNode(.{ "", "child_block_end" }, &.{.{ "", "bright_white" }}, &.{}, (try parser.next()).node);
//     try parser.expectNode(.{ "", "type_begin" }, &.{.{ "", "bright_white" }}, &.{}, (try parser.next()).node);
//     try parser.expectNode(.{ "", "type_end" }, &.{.{ "", "bright_white" }}, &.{}, (try parser.next()).node);
//     try parser.expectNode(.{ "", "comment" }, &.{.{ "", "white" }}, &.{}, (try parser.next()).node);
//     try parser.expectNode(.{ "", "slashdash" }, &.{.{ "", "white" }}, &.{}, (try parser.next()).node);
//     try parser.expectNode(.{ "", "whitespace" }, &.{.{ "", "white" }}, &.{}, (try parser.next()).node);

//     try std.testing.expectEqual(.eof, try parser.next());
// }

// test "Arg with property before argument" {
//     const document = "mynode host=myhost \"value1\" \"value2\"";

//     var reader = std.Io.Reader.fixed(document);

//     var parser = try Parser.init(std.testing.allocator, &reader, .{});
//     defer parser.deinit();

//     const node = (try parser.next() orelse return error.MissingNode).node;
//     try std.testing.expectEqualStrings("mynode", node.name);
//     try std.testing.expectEqual(2, node.argcount());
//     try std.testing.expectEqualStrings("myhost", try node.prop([]const u8, &parser, "host") orelse return error.MissingString);
//     try std.testing.expectEqualStrings("value1", node.argument(&parser, 0) orelse return error.MissingString);
//     try std.testing.expectEqualStrings("value2", node.argument(&parser, 1) orelse return error.MissingString);
//     try std.testing.expectEqual(null, node.argument(&parser, 2));
// }

// test "Unbalanced Child Node" {
//     const document = @embedFile("test/unbalanced.kdl");

//     var reader = std.Io.Reader.fixed(document);

//     var parser = try Parser.init(std.testing.allocator, &reader, .{});
//     defer parser.deinit();

//     {
//         const next_val = try parser.next() orelse return error.MissingNode;
//         const node = next_val.node;
//         try std.testing.expectEqualStrings("attach_mode", node.name);
//     }
//     {
//         const next_val = try parser.next() orelse return error.MissingNode;
//         const node = next_val.node;
//         try std.testing.expectEqualStrings("focus_follows_pointer", node.name);
//     }
//     {
//         const next_val = try parser.next() orelse return error.MissingNode;
//         const node = next_val.node;
//         try std.testing.expectEqualStrings("pointer_warp_on_focus_change", node.name);
//     }

//     try std.testing.expectError(error.InvalidChildBlockEnd, parser.next());
// }

// test "Typed argument/property parsing" {
//     const TestEnum = enum { an_enum_value, boogaloo };
//     const document = "mynode prop1=0xff prop2=3.14 prop3=an_enum_value prop4=\"a string\" 0b1111 2.718 boogaloo \"another string\" prop5=#true";

//     var reader = std.Io.Reader.fixed(document);

//     var parser = try Parser.init(std.testing.allocator, &reader, .{});
//     defer parser.deinit();

//     const node = (try parser.next() orelse return error.MissingNode).node;
//     try std.testing.expectEqualStrings("mynode", node.name);

//     try std.testing.expectEqual(0xff, try node.prop(i32, &parser, "prop1") orelse return error.MissingProperty);
//     try std.testing.expectEqual(3.14, try node.prop(f32, &parser, "prop2") orelse return error.MissingProperty);
//     try std.testing.expectEqual(TestEnum.an_enum_value, try node.prop(TestEnum, &parser, "prop3") orelse return error.MissingProperty);
//     try std.testing.expectEqualStrings("a string", try node.prop([]const u8, &parser, "prop4") orelse return error.MissingProperty);
//     try std.testing.expectEqual(true, try node.prop(bool, &parser, "prop5") orelse return error.MissingProperty);

//     try std.testing.expectEqual(4, node.argcount());
//     try std.testing.expectEqual(15, try node.arg(i32, &parser, 0) orelse return error.MissingProperty);
//     try std.testing.expectEqual(2.718, try node.arg(f32, &parser, 1) orelse return error.MissingProperty);
//     try std.testing.expectEqual(TestEnum.boogaloo, try node.arg(TestEnum, &parser, 2) orelse return error.MissingProperty);
//     try std.testing.expectEqualStrings("another string", try node.arg([]const u8, &parser, 3) orelse return error.MissingProperty);

//     // Errors
//     try std.testing.expectError(error.Parsing, err: {
//         if (node.prop(bool, &parser, "prop1")) |_| {} else |e| {
//             break :err e;
//         }
//     });
//     try std.testing.expectError(error.Parsing, err: {
//         if (node.prop(i32, &parser, "prop2")) |_| {} else |e| {
//             break :err e;
//         }
//     });
//     try std.testing.expectError(error.Parsing, err: {
//         if (node.prop(f32, &parser, "prop5")) |_| {} else |e| {
//             break :err e;
//         }
//     });
// }

const Tokenizer = @import("Tokenizer.zig");
const StringHashMap = std.StringHashMapUnmanaged;

const string_util = @import("string.zig");
const assert = std.debug.assert;
const testing = std.testing;
const root = @import("root.zig");
const log = std.log.scoped(.kdl_parser);
const std = @import("std");
