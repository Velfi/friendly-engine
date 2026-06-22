const std = @import("std");
const builtin = @import("builtin");
const kdl = @import("kdl");
const print = std.debug.print;

const DebugAllocator = std.heap.DebugAllocator(.{});

pub fn main(init: std.process.Init) !void {
    var test_failed = false;

    const gpa = init.gpa;

    // Printing setup
    const buffer_size = std.heap.pageSize();

    const stdout_buffer = try gpa.alloc(u8, buffer_size);
    defer gpa.free(stdout_buffer);

    const stderr_buffer = try gpa.alloc(u8, buffer_size);
    defer gpa.free(stderr_buffer);

    const stdout_file = std.Io.File.stdout();
    var stdout_writer = stdout_file.writer(init.io, stdout_buffer);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    const stderr_file = std.Io.File.stderr();
    var stderr_writer = stderr_file.writer(init.io, stderr_buffer);
    const stderr = &stderr_writer.interface;
    defer stderr.flush() catch {};

    // Buffers to read files into
    const input_buffer = try gpa.alloc(u8, buffer_size);
    defer gpa.free(input_buffer);

    const expected_buffer = try gpa.alloc(u8, buffer_size);
    defer gpa.free(expected_buffer);

    // Process arguments (should be just the exe name and the path to the tests)
    const args = try init.minimal.args.toSlice(gpa);
    defer gpa.free(args);

    if (args.len < 2) return error.WrongArgCount;

    var test_path_opt: ?[]const u8 = null;
    var filter: ?[]const u8 = null;

    const Args = enum { verbose, filter, fail_fast };
    const arg_map = std.StaticStringMap(Args).initComptime(.{
        .{ "v", .verbose },
        .{ "verbose", .verbose },
        .{ "f", .filter },
        .{ "filter", .filter },
        .{ "d", .fail_fast },
        .{ "fail-fast", .fail_fast },
    });

    var verbose = false;
    var fail_fast = false;

    for (args[1..]) |arg| {
        if (std.mem.startsWith(u8, arg, "-")) {
            // do nothing
        } else if (test_path_opt == null) {
            test_path_opt = arg;
            continue;
        } else if (test_path_opt) |_| {
            return error.WrongArgCount;
        }

        const arg_no_dash = std.mem.trim(u8, arg, "-");

        if (arg_map.getLongestPrefix(arg_no_dash)) |kv| switch (kv.value) {
            .verbose => {
                verbose = true;
            },
            .fail_fast => {
                fail_fast = true;
            },
            .filter => {
                const idx = if (std.mem.findScalar(u8, arg_no_dash, '=')) |i| i else 0;
                filter = arg_no_dash[idx + 1 ..];
            },
        };
    }
    const test_path = test_path_opt orelse return error.WrongArgCount;

    const test_dir = try std.Io.Dir.openDirAbsolute(init.io, test_path, .{});

    // Verify the KDL spec test directory structure exists
    const result_input_dir = test_dir.openDir(init.io, "input", .{ .iterate = true });
    const result_expected_dir = test_dir.openDir(init.io, "expected_kdl", .{ .iterate = true });

    const exists_input = if (result_input_dir) |_| true else |_| false;
    const exists_expected = if (result_expected_dir) |_| true else |_| false;

    if (!exists_input and !exists_expected) {
        return error.MissingBothDirs;
    } else if (!exists_input) {
        return error.MissingInputDir;
    } else if (!exists_expected) {
        return error.MissingExpectedDir;
    }

    var input_dir = try result_input_dir;
    defer input_dir.close(init.io);

    var expected_dir = try result_expected_dir;
    defer expected_dir.close(init.io);

    // Iterate over all files in the input directory
    var input_iter = input_dir.iterate();
    var count_input_total: usize = 0;
    var count_input_passed: usize = 0;
    var count_input_leaked: usize = 0;
    var longest_filename: usize = 0;

    while (try input_iter.next(init.io)) |input_entry| {
        defer {
            stdout.flush() catch {};
            stderr.flush() catch {};
        }
        if (input_entry.kind != .file) return error.UnexpectedFolderInInputDir;
        count_input_total += 1;
        longest_filename = @max(longest_filename, input_entry.name.len);

        if (filter) |filt| {
            if (!std.mem.eql(u8, filt, input_entry.name)) continue;
        }

        if (verbose) {
            try stdout.print("\n{s: <80}\t", .{input_entry.name});
            stdout.flush() catch {};
        }

        var temp_dba = DebugAllocator{
            .backing_allocator = gpa,
        };
        const dba = temp_dba.allocator();

        const input_file = try input_dir.openFile(init.io, input_entry.name, .{});
        defer input_file.close(init.io);

        const input_len = try input_file.length(init.io);
        if (input_len == 0) {
            test_failed = true;
            continue;
        }

        var input_mem = try input_file.createMemoryMap(init.io, .{ .len = input_len + 1, .protection = .{ .read = true } });
        defer input_mem.destroy(init.io);

        const input = input_mem.memory[0..input_len :0];

        if (std.mem.endsWith(u8, input_entry.name, "_fail.kdl")) {
            var found_invalid = false;

            var event_count: u32 = 0;
            var parser = kdl.Parser.init(input);
            var event = try parser.next();
            while (event != .eof) : (event = try parser.next()) {
                if (verbose) {
                    stderr.print("\nevent[{d}]: {s:<6} {f}", .{ event_count, @tagName(event), event }) catch {};
                }
                event_count += 1;
                if (event == .invalid) {
                    found_invalid = true;
                    break;
                }
            }

            if (found_invalid) {
                count_input_passed += 1;
            } else {
                if (verbose) {
                    try stdout.print(
                        "X\tno error while parsing input expected to fail",
                        .{},
                    );
                    stderr.print("\ninput:\n{s}\n", .{input}) catch {};
                } else {
                    try stdout.print("\n{s: <80}\t", .{input_entry.name});
                }
                test_failed = true;
            }
        } else {
            const expected_file = try expected_dir.openFile(init.io, input_entry.name, .{});
            defer expected_file.close(init.io);

            var expected_reader_real = expected_file.reader(init.io, expected_buffer);

            const expected_reader = &expected_reader_real.interface;

            expected_reader.fillMore() catch |err| switch (err) {
                error.EndOfStream => {},
                error.ReadFailed => return err,
            };

            var writer = std.Io.Writer.Allocating.init(gpa);
            defer writer.deinit();
            const pretty_printed = &writer.writer;

            const expected = expected_reader.buffered();

            // parse input
            var parser = kdl.Parser.init(input);
            var node_iter = parser.nodeIterator();
            var is_first = true;
            var encountered_invalid = false;

            while (node_iter.next(dba) catch |err| node: {
                if (err != error.EndOfFile) {
                    encountered_invalid = true;
                    if (verbose) try stderr.print("parse error! {}\n", .{err});
                }
                break :node null;
            }) |event| {
                switch (event) {
                    .node => |node| {
                        defer node.deinit(dba);
                        if (!is_first) {
                            try pretty_printed.writeByte('\n');
                        } else {
                            is_first = false;
                        }
                        _ = try pretty_printed.writeSplat(&.{"    "}, @intCast(node.depth));
                        if (node.annotation) |ann| {
                            try pretty_printed.writeByte('(');
                            try pretty_printed.writeAll(ann);
                            try pretty_printed.writeByte(')');
                        }
                        try pretty_printed.writeAll(node.name);
                        for (0..node.args.len) |idx| {
                            const arg = node.args[idx];
                            try pretty_printed.writeByte(' ');
                            try printVal(dba, pretty_printed, arg);
                        }
                        var prop_iter = node.props.iterator();
                        while (prop_iter.next()) |prop| {
                            const key = prop.key_ptr.*;
                            try pretty_printed.print(" {s}=", .{key});

                            const arg = prop.value_ptr.*;
                            try printVal(dba, pretty_printed, arg);
                        }
                    },
                    .child_block_begin => try pretty_printed.writeAll(" {"),
                    .child_block_end => try pretty_printed.writeAll("\n}"),
                }
            }

            try pretty_printed.writeByte('\n');

            if (verbose and printDiff(expected, pretty_printed.buffered())) {
                test_failed = true;
                try stdout.writeAll("\n");

                try stderr.print("\ntokens:\n", .{});
                var tokenizer = kdl.Tokenizer.init(input);
                var token = tokenizer.next();
                while (token.tag != .eof) : (token = tokenizer.next()) {
                    try stderr.print("\t{t:<16}\"{f}\"\n", .{ token.tag, std.zig.fmtString(tokenizer.text(token)) });
                }
            } else if (!verbose and !std.mem.eql(u8, expected, pretty_printed.buffered())) {
                try stdout.print("\n{s: <80}\t", .{input_entry.name});
                test_failed = true;
            } else {
                if (!encountered_invalid) count_input_passed += 1;
            }
            switch (temp_dba.deinit()) {
                .ok => {},
                .leak => {
                    count_input_leaked += 1;
                },
            }
            if (fail_fast and test_failed) break;
        }
        try stdout.flush();
    }

    try stdout.writeAll("\n============= RESULTS ================\n");
    try stdout.print(
        "Passed {}/{} tests\n",
        .{ count_input_passed, count_input_total },
    );
    try stdout.print(
        "Memory leak in {}/{} tests\n",
        .{ count_input_leaked, count_input_total },
    );
    try stdout.print(
        "Longest filename: {} bytes\n",
        .{longest_filename},
    );
    try stdout.flush();
    try stderr.flush();

    if (test_failed) return error.TestFailed;
}

fn printVal(alloc: std.mem.Allocator, writer: *std.Io.Writer, value: kdl.Parser.Value) !void {
    if (value.ann) |annotation| {
        const norm = try kdl.string_utils.makeInlineString(alloc, annotation);
        defer alloc.free(norm);
        try writer.print("({s})", .{norm});
    }
    if (value.into(i128)) |number| {
        try writer.print("{d}", .{number});
    } else if (value.into(f128)) |number| {
        // Custom printing
        if (number >= 0 and number <= 10) {
            try writer.print("{d:.1}", .{number});
        } else {
            const str = try std.fmt.allocPrint(alloc, "{e}", .{number});
            defer alloc.free(str);

            const e_idx = std.mem.findAny(u8, str, "eE") orelse 0;
            const _val = str[0..e_idx];
            const val = if (std.mem.findScalar(u8, _val, '.')) |_|
                try alloc.dupe(u8, _val)
            else
                try std.fmt.allocPrint(alloc, "{s}.0", .{_val});
            defer alloc.free(val);
            const exp = str[e_idx + 1 ..];
            const sign = if (exp.len != 0 and exp[0] == '-') "" else "+";
            try writer.print("{s}E{s}{s}", .{ val, sign, exp });
        }
    } else {
        const norm = try kdl.string_utils.makeInlineString(alloc, value.val);
        defer alloc.free(norm);
        try writer.writeAll(norm);
    }
}

fn printIndicatorLine(source: []const u8, indicator_index: usize) void {
    const line_begin_index = if (std.mem.lastIndexOfScalar(u8, source[0..indicator_index], '\n')) |line_begin|
        line_begin + 1
    else
        0;
    const line_end_index = if (std.mem.findScalar(u8, source[indicator_index..], '\n')) |line_end|
        (indicator_index + line_end)
    else
        source.len;

    printLine(source[line_begin_index..line_end_index]);
    for (line_begin_index..indicator_index) |_|
        print(" ", .{});
    if (indicator_index >= source.len)
        print("^ (end of string)\n", .{})
    else
        print("^ ('\\x{x:0>2}')\n", .{source[indicator_index]});
}

fn printWithVisibleNewlines(source: []const u8) void {
    var i: usize = 0;
    while (std.mem.findScalar(u8, source[i..], '\n')) |nl| : (i += nl + 1) {
        printLine(source[i..][0..nl]);
    }
    print("{s}␃\n", .{source[i..]}); // End of Text symbol (ETX)
}

fn printLine(line: []const u8) void {
    if (line.len != 0) switch (line[line.len - 1]) {
        ' ', '\t' => return print("{s}⏎\n", .{line}), // Return symbol
        else => {},
    };
    print("{s}\n", .{line});
}

/// Returns true if there is a difference, false otherwise
fn printDiff(expected: []const u8, actual: []const u8) bool {
    if (std.mem.findDiff(u8, actual, expected)) |diff_index| {
        print("\n====== expected this output: =========\n", .{});
        printWithVisibleNewlines(expected);
        print("\n======== instead found this: =========\n", .{});
        printWithVisibleNewlines(actual);
        print("\n======================================\n", .{});

        var diff_line_number: usize = 1;
        for (expected[0..diff_index]) |value| {
            if (value == '\n') diff_line_number += 1;
        }
        print("First difference occurs on line {d}:\n", .{diff_line_number});

        print("expected:\n", .{});
        printIndicatorLine(expected, diff_index);

        print("found:\n", .{});
        printIndicatorLine(actual, diff_index);
        return true;
    }
    return false;
}
