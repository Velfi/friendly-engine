const std = @import("std");
const kdl = @import("kdl");

const Color = std.Io.Terminal.Color;
const Colors = struct {
    node: Color = .blue,
    string: Color = .green,
    raw_string: Color = .magenta,
    number: Color = .red,
    keyword: Color = .blue,
    equals: Color = .bright_white,
    child_block_begin: Color = .bright_white,
    child_block_end: Color = .bright_white,
    type_begin: Color = .bright_white,
    type_end: Color = .bright_white,
    comment: Color = .white,
    slashdash: Color = .white,
    whitespace: Color = .white,
};

fn getConfigPath(alloc: std.mem.Allocator, env_map: *const std.process.Environ.Map) ![]const u8 {
    if (env_map.get("XDG_CONFIG_HOME")) |xdg_config_home| {
        return std.fs.path.join(alloc, &.{ xdg_config_home, "zkdl.kdl" });
    }
    if (env_map.get("HOME")) |home| {
        return std.fs.path.join(alloc, &.{ home, ".config", "zkdl.kdl" });
    }
    return alloc.dupe(u8, "/etc/xdg/zkdl.kdl");
}

const Options = struct {
    verbose: bool = false,
    config: ?[]const u8 = null,
    help: bool = false,

    pub const shorthands = .{
        .v = "verbose",
        .C = "config",
        .h = "help",
    };

    pub const meta = .{
        .option_docs = .{
            .verbose = "Enable verbose output",
            .config = "Specify config file to load",
            .help = "output this message then exit",
        },
    };
};

pub fn main(init: std.process.Init) !void {
    // Program setup
    const buffer_size = std.heap.pageSize();
    const stdout_buffer = try init.gpa.alloc(u8, buffer_size);
    defer init.gpa.free(stdout_buffer);

    const stdout_file = std.Io.File.stdout();
    var stdout_writer = stdout_file.writer(init.io, stdout_buffer[0 .. buffer_size / 2]);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    const stderr_file = std.Io.File.stderr();
    var stderr_writer = stderr_file.writer(init.io, stdout_buffer[buffer_size / 2 ..]);
    const stderr = &stderr_writer.interface;
    defer stderr.flush() catch {};

    const NO_COLOR = init.environ_map.contains("NO_COLOR");
    const CLICOLOR_FORCE = init.environ_map.contains("CLICOLOR_FORCE");

    const tty_conf = std.Io.Terminal{
        .writer = stdout,
        .mode = std.Io.Terminal.Mode.detect(init.io, stdout_file, NO_COLOR, CLICOLOR_FORCE) catch .no_color,
    };
    try tty_conf.setColor(.reset);
    defer tty_conf.setColor(.reset) catch {};

    var positionals = std.ArrayList([]const u8).empty;
    var args: Options = .{};
    var arg_error = false;
    var args_iter = try init.minimal.args.iterateAllocator(init.arena.allocator());
    _ = args_iter.next(); // skip the executable name argument
    while (args_iter.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "--")) {
            if (std.mem.eql(u8, arg, "--help")) args.help = true;
            if (std.mem.eql(u8, arg, "--verbose")) args.verbose = true;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            switch (arg[1]) {
                'h' => args.help = true,
                'v' => args.verbose = true,
                else => arg_error = true,
            }
        } else {
            try positionals.append(init.arena.allocator(), arg);
        }
    }
    if (args.help or arg_error) {
        try stderr.print("zkdl\n{any}", .{Options.meta});
        try stderr.flush();
        return;
    }

    var ctx = Context{
        .io = init.io,
        .tty_conf = tty_conf,
        .stdout = stdout,
        .stderr = stderr,
        .gpa = init.gpa,
        .colors = .{},
        .verbose = args.verbose,
    };

    config: {
        const config_path = try getConfigPath(init.gpa, init.environ_map);
        defer init.gpa.free(config_path);

        const config = std.Io.Dir.openFileAbsolute(init.io, config_path, .{ .mode = .read_only }) catch break :config;
        defer config.close(init.io);

        const doc_len = try config.length(init.io);

        var doc_conf = try config.createMemoryMap(init.io, .{ .len = doc_len + 1, .protection = .{ .read = true } });
        defer doc_conf.destroy(init.io);

        var config_parser = kdl.Parser.init(doc_conf.memory[0..doc_len :0]);

        var depth: usize = 0;

        var event = try config_parser.next();

        var field_ptr: ?*std.Io.Terminal.Color = null;

        while (event != .eof) : (event = try config_parser.next()) {
            switch (event) {
                .node => |node| {
                    blk: {
                        if (depth != 0) break :blk;

                        if (std.meta.stringToEnum(std.meta.FieldEnum(Colors), node.val)) |field| {
                            switch (field) {
                                inline else => |F| field_ptr = &@field(ctx.colors, @tagName(F)),
                            }
                        }
                    }

                    if (args.verbose)
                        if (depth == 0)
                            std.log.warn("Unknown config option {s}", .{node.val})
                        else
                            std.log.warn("Unknown config option {s} (depth = {d})", .{ node.val, depth });
                },
                .arg => |arg| {
                    const color = std.meta.stringToEnum(std.Io.Terminal.Color, arg.val) orelse continue;
                    field_ptr.?.* = color;
                },
                .prop => {},
                .child_block_begin => depth += 1,
                .child_block_end => depth -= 1,
                .invalid => return error.Config,
                .eof => break,
            }
        }
    }
    if (positionals.items.len == 0) {
        // try argsParse.printHelp(Options, "zkdl", stderr);
        return error.MissingFileArguments;
    }
    for (positionals.items) |arg| try highlight(ctx, arg);
}

const Context = struct {
    tty_conf: std.Io.Terminal,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
    gpa: std.mem.Allocator,
    colors: Colors,
    verbose: bool,
    io: std.Io,
};

fn highlight(ctx: Context, document_path: []const u8) !void {
    const tty_conf = ctx.tty_conf;
    const stdout = ctx.stdout;
    const stderr = ctx.stderr;

    const document = try std.Io.Dir.cwd().openFile(ctx.io, document_path, .{ .mode = .read_only });
    defer document.close(ctx.io);
    errdefer stdout.flush() catch {};

    const doc_len = try document.length(ctx.io);
    var doc = try document.createMemoryMap(ctx.io, .{ .len = doc_len + 1, .protection = .{ .read = true } });
    defer doc.destroy(ctx.io);

    var tok_iter = kdl.Tokenizer.init(doc.memory[0..doc_len :0]);

    try tty_conf.setColor(.reset);
    try tty_conf.setColor(.bold);

    try stdout.print("{s}:\n", .{document_path});
    var tok = tok_iter.next();
    while (tok.tag != .eof) : (tok = tok_iter.next()) {
        try tty_conf.setColor(.reset); // Reset after each token
        if (ctx.verbose) {
            try stderr.print("{any}\n", .{tok});
        }
        switch (tok.tag) { // Set emphasis (bold, normal, dim)
            .slashdash,
            .comment,
            .continuation,
            => try tty_conf.setColor(.dim),
            .equal,
            .lbrace,
            .rbrace,
            .lparen,
            .rparen,
            .keyword,
            .semicolon,
            => try tty_conf.setColor(.bold),
            else => {},
        }
        switch (tok.tag) { // Set color
            .string => try tty_conf.setColor(ctx.colors.string),
            .raw => try tty_conf.setColor(ctx.colors.raw_string),
            .number => try tty_conf.setColor(ctx.colors.number),
            .keyword => try tty_conf.setColor(ctx.colors.keyword),
            .equal => try tty_conf.setColor(ctx.colors.equals),
            .lbrace => try tty_conf.setColor(ctx.colors.child_block_begin),
            .rbrace => try tty_conf.setColor(ctx.colors.child_block_end),
            .lparen => try tty_conf.setColor(ctx.colors.type_begin),
            .rparen => try tty_conf.setColor(ctx.colors.type_end),
            .comment => try tty_conf.setColor(ctx.colors.comment),
            .newline,
            .continuation,
            .whitespace,
            .semicolon,
            => try tty_conf.setColor(ctx.colors.whitespace),

            .slashdash => {
                // TODO: get this working again
                try tty_conf.setColor(ctx.colors.comment);
            },
            .bom,
            .invalid,
            => {
                // Replace invalid characters with the unicode replacement character
                try tty_conf.setColor(ctx.colors.whitespace);
                try stdout.writeAll("\u{FFFD}");
                continue;
            },
            .eof => break,
        }
        try stdout.writeAll(tok_iter.text(tok));
    }

    try stdout.writeAll("\n\n");
    try stdout.flush();
}
