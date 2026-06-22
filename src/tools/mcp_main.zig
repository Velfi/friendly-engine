const std = @import("std");
const editor_control_commands = @import("editor_control_commands");

const control_port: u16 = 39743;

pub fn main(init: std.process.Init) !void {
    var stdin_buf: [64 * 1024]u8 = undefined;
    var stdout_buf: [64 * 1024]u8 = undefined;
    var stdin_reader_state = std.Io.File.stdin().readerStreaming(init.io, &stdin_buf);
    var stdout_writer_state = std.Io.File.stdout().writerStreaming(init.io, &stdout_buf);
    const reader = &stdin_reader_state.interface;
    const writer = &stdout_writer_state.interface;

    while (true) {
        const line = readLineAlloc(init.gpa, reader, 64 * 1024) catch |err| switch (err) {
            error.StreamTooLong => {
                const response = try errorResponse(init.gpa, "null", -32700, "Message too large");
                defer init.gpa.free(response);
                try writer.writeAll(response);
                try writer.writeAll("\n");
                try writer.flush();
                continue;
            },
            else => return err,
        } orelse return;
        defer init.gpa.free(line);
        if (line.len == 0) continue;
        const response = try handleMessage(init.gpa, init.io, line);
        defer init.gpa.free(response);
        if (response.len == 0) continue;
        try writer.writeAll(response);
        try writer.writeAll("\n");
        try writer.flush();
    }
}

fn handleMessage(allocator: std.mem.Allocator, io: std.Io, line: []const u8) ![]u8 {
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, line, .{ .ignore_unknown_fields = true }) catch
        return errorResponse(allocator, "null", -32700, "Parse error");
    defer parsed.deinit();

    const root = switch (parsed.value) {
        .object => |object| object,
        else => return errorResponse(allocator, "null", -32600, "Invalid Request"),
    };
    const method = valueString(root.get("method") orelse return errorResponse(allocator, "null", -32600, "Missing method")) orelse
        return errorResponse(allocator, "null", -32600, "Invalid method");
    if (std.mem.startsWith(u8, method, "notifications/")) return allocator.dupe(u8, "");
    const id_text = idJson(allocator, root.get("id")) catch
        return errorResponse(allocator, "null", -32600, "Invalid request id");
    defer allocator.free(id_text);

    if (std.mem.eql(u8, method, "initialize")) return initializeResponse(allocator, id_text);
    if (std.mem.eql(u8, method, "tools/list")) return toolsListResponse(allocator, id_text);
    if (std.mem.eql(u8, method, "tools/call")) {
        const params = root.get("params") orelse return errorResponse(allocator, id_text, -32602, "Missing params");
        return callToolResponse(allocator, io, id_text, params);
    }
    return errorResponse(allocator, id_text, -32601, "Method not found");
}

fn initializeResponse(allocator: std.mem.Allocator, id_text: []const u8) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "{{\"jsonrpc\":\"2.0\",\"id\":{s},\"result\":{{\"protocolVersion\":\"2025-06-18\",\"capabilities\":{{\"tools\":{{\"listChanged\":false}}}},\"serverInfo\":{{\"name\":\"friendly-engine\",\"version\":\"0.1.0\"}}}}}}",
        .{id_text},
    );
}

fn toolsListResponse(allocator: std.mem.Allocator, id_text: []const u8) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, 8192);
    defer out.deinit(allocator);
    try appendFmt(allocator, &out, "{{\"jsonrpc\":\"2.0\",\"id\":{s},\"result\":{{\"tools\":[", .{id_text});
    var first = true;
    for (editor_control_commands.entries) |entry| {
        if (!entry.exposedToMcp()) continue;
        if (!first) try out.appendSlice(allocator, ",");
        first = false;
        try appendToolJson(allocator, &out, entry);
    }
    try out.appendSlice(allocator, "]}}");
    return out.toOwnedSlice(allocator);
}

fn callToolResponse(allocator: std.mem.Allocator, io: std.Io, id_text: []const u8, params_value: std.json.Value) ![]u8 {
    _ = io;
    const params = switch (params_value) {
        .object => |object| object,
        else => return errorResponse(allocator, id_text, -32602, "Invalid params"),
    };
    const name = valueString(params.get("name") orelse return errorResponse(allocator, id_text, -32602, "Missing tool name")) orelse
        return errorResponse(allocator, id_text, -32602, "Invalid tool name");
    const arguments = params.get("arguments");
    const editor_command = buildEditorCommand(allocator, name, arguments) catch |err| switch (err) {
        error.UnknownTool => return errorResponse(allocator, id_text, -32602, "Unknown tool"),
        error.InvalidToolArguments => return errorResponse(allocator, id_text, -32602, "Invalid tool arguments"),
        else => return err,
    };
    defer allocator.free(editor_command);
    const editor_result = sendEditorCommand(allocator, editor_command) catch |err| {
        const err_text = try std.fmt.allocPrint(allocator, "{{\"ok\":false,\"error\":\"{s}\"}}", .{@errorName(err)});
        defer allocator.free(err_text);
        return toolTextResponse(allocator, id_text, true, err_text);
    };
    defer allocator.free(editor_result);
    const is_error = std.mem.indexOf(u8, editor_result, "\"ok\":false") != null;
    return toolTextResponse(allocator, id_text, is_error, editor_result);
}

fn buildEditorCommand(allocator: std.mem.Allocator, tool_name: []const u8, arguments: ?std.json.Value) ![]u8 {
    const entry = editor_control_commands.findByMcpToolName(tool_name) orelse return error.UnknownTool;
    var out = try std.ArrayList(u8).initCapacity(allocator, 256);
    defer out.deinit(allocator);
    try appendFmt(allocator, &out, "{{\"id\":\"mcp-{s}\",\"name\":", .{tool_name});
    try appendJsonString(allocator, &out, entry.command_name);

    if (arguments) |args_value| {
        const args = switch (args_value) {
            .object => |object| object,
            .null => null,
            else => return error.InvalidToolArguments,
        };
        if (args) |object| {
            switch (entry.argument_policy) {
                .empty => if (object.count() != 0) return error.InvalidToolArguments,
                .fields, .object_string => {
                    try validateArgumentsAgainstSchema(allocator, entry, args_value);
                    var it = object.iterator();
                    while (it.next()) |item| {
                        const field = commandField(entry, item.key_ptr.*) orelse return error.InvalidToolArguments;
                        switch (field.kind) {
                            .string => try appendStringField(allocator, &out, field.name, item.value_ptr.*),
                            .number => try appendNumberField(allocator, &out, field.name, item.value_ptr.*),
                            .boolean => try appendBooleanField(allocator, &out, field.name, item.value_ptr.*),
                            .json => try appendJsonField(allocator, &out, field.name, item.value_ptr.*),
                        }
                    }
                },
                .strict_json_object => {
                    try validateArgumentsAgainstSchema(allocator, entry, args_value);
                    const object_text = try std.fmt.allocPrint(allocator, "{f}", .{std.json.fmt(args_value, .{})});
                    defer allocator.free(object_text);
                    try appendFmt(allocator, &out, ",\"object\":", .{});
                    try appendJsonString(allocator, &out, object_text);
                    try out.appendSlice(allocator, "}\n");
                    return out.toOwnedSlice(allocator);
                },
            }
        } else if (schemaHasRequiredFields(entry)) {
            return error.InvalidToolArguments;
        }
    } else if (schemaHasRequiredFields(entry)) {
        return error.InvalidToolArguments;
    }
    try out.appendSlice(allocator, "}\n");
    return out.toOwnedSlice(allocator);
}

fn schemaHasRequiredFields(entry: editor_control_commands.Entry) bool {
    return entry.argument_policy != .empty and std.mem.indexOf(u8, entry.input_schema, "\"required\"") != null;
}

fn validateArgumentsAgainstSchema(allocator: std.mem.Allocator, entry: editor_control_commands.Entry, value: std.json.Value) !void {
    if (entry.argument_policy == .empty) return;
    var parsed_schema = std.json.parseFromSlice(std.json.Value, allocator, entry.input_schema, .{}) catch
        return error.InvalidToolArguments;
    defer parsed_schema.deinit();
    validateValueAgainstSchema(value, parsed_schema.value) catch return error.InvalidToolArguments;
}

fn validateValueAgainstSchema(value: std.json.Value, schema: std.json.Value) anyerror!void {
    const schema_object = switch (schema) {
        .object => |schema_object| schema_object,
        else => return error.InvalidToolArguments,
    };
    if (schema_object.get("oneOf")) |one_of_value| {
        const one_of = switch (one_of_value) {
            .array => |one_of| one_of,
            else => return error.InvalidToolArguments,
        };
        for (one_of.items) |candidate| {
            validateValueAgainstSchema(value, candidate) catch continue;
            return;
        }
        return error.InvalidToolArguments;
    }
    if (schema_object.get("const")) |constant| {
        if (!jsonValuesEqual(value, constant)) return error.InvalidToolArguments;
    }
    const type_text = valueString(schema_object.get("type") orelse return error.InvalidToolArguments) orelse
        return error.InvalidToolArguments;
    if (std.mem.eql(u8, type_text, "object")) return validateObjectAgainstSchema(value, schema_object);
    if (std.mem.eql(u8, type_text, "array")) return validateArrayAgainstSchema(value, schema_object);
    if (std.mem.eql(u8, type_text, "string")) return validateStringAgainstSchema(value, schema_object);
    if (std.mem.eql(u8, type_text, "number")) return validateNumberAgainstSchema(value, schema_object);
    if (std.mem.eql(u8, type_text, "integer")) return validateIntegerAgainstSchema(value, schema_object);
    if (std.mem.eql(u8, type_text, "boolean")) {
        if (value != .bool) return error.InvalidToolArguments;
        return;
    }
    return error.InvalidToolArguments;
}

fn validateObjectAgainstSchema(value: std.json.Value, schema_object: anytype) anyerror!void {
    const object = switch (value) {
        .object => |object| object,
        else => return error.InvalidToolArguments,
    };
    const min_properties = schemaInteger(schema_object.get("minProperties")) orelse 0;
    if (object.count() < @as(usize, @intCast(min_properties))) return error.InvalidToolArguments;
    const properties_value = schema_object.get("properties");
    const properties = if (properties_value) |maybe_properties| switch (maybe_properties) {
        .object => |properties| properties,
        else => return error.InvalidToolArguments,
    } else null;
    if (schema_object.get("required")) |required_value| {
        const required = switch (required_value) {
            .array => |required| required,
            else => return error.InvalidToolArguments,
        };
        for (required.items) |item| {
            const field_name = valueString(item) orelse return error.InvalidToolArguments;
            if (!object.contains(field_name)) return error.InvalidToolArguments;
        }
    }

    const additional_properties = schema_object.get("additionalProperties");
    var it = object.iterator();
    while (it.next()) |item| {
        if (properties) |property_map| {
            if (property_map.get(item.key_ptr.*)) |property_schema| {
                try validateValueAgainstSchema(item.value_ptr.*, property_schema);
                continue;
            }
        }
        if (additional_properties) |additional| {
            switch (additional) {
                .bool => |allowed| {
                    if (!allowed) return error.InvalidToolArguments;
                },
                .object => try validateValueAgainstSchema(item.value_ptr.*, additional),
                else => return error.InvalidToolArguments,
            }
        } else {
            return error.InvalidToolArguments;
        }
    }
}

fn validateArrayAgainstSchema(value: std.json.Value, schema_object: anytype) anyerror!void {
    const array = switch (value) {
        .array => |array| array,
        else => return error.InvalidToolArguments,
    };
    if (schemaInteger(schema_object.get("minItems"))) |min_items| {
        if (array.items.len < @as(usize, @intCast(min_items))) return error.InvalidToolArguments;
    }
    if (schemaInteger(schema_object.get("maxItems"))) |max_items| {
        if (array.items.len > @as(usize, @intCast(max_items))) return error.InvalidToolArguments;
    }
    if (schema_object.get("items")) |item_schema| {
        for (array.items) |item| try validateValueAgainstSchema(item, item_schema);
    }
}

fn validateStringAgainstSchema(value: std.json.Value, schema_object: anytype) !void {
    const text = valueString(value) orelse return error.InvalidToolArguments;
    if (schema_object.get("enum")) |enum_value| {
        const enum_items = switch (enum_value) {
            .array => |enum_items| enum_items,
            else => return error.InvalidToolArguments,
        };
        for (enum_items.items) |item| {
            const allowed = valueString(item) orelse return error.InvalidToolArguments;
            if (std.mem.eql(u8, text, allowed)) return;
        }
        return error.InvalidToolArguments;
    }
}

fn validateNumberAgainstSchema(value: std.json.Value, schema_object: anytype) !void {
    const number = jsonNumberAsFloat(value) orelse return error.InvalidToolArguments;
    try validateNumericBounds(number, schema_object);
}

fn validateIntegerAgainstSchema(value: std.json.Value, schema_object: anytype) !void {
    const integer = jsonIntegerAsFloat(value) orelse return error.InvalidToolArguments;
    try validateNumericBounds(integer, schema_object);
}

fn validateNumericBounds(number: f64, schema_object: anytype) !void {
    if (jsonNumberAsFloat(schema_object.get("minimum") orelse .null)) |minimum| {
        if (number < minimum) return error.InvalidToolArguments;
    }
    if (jsonNumberAsFloat(schema_object.get("maximum") orelse .null)) |maximum| {
        if (number > maximum) return error.InvalidToolArguments;
    }
}

fn jsonNumberAsFloat(value: std.json.Value) ?f64 {
    return switch (value) {
        .integer => |integer| @floatFromInt(integer),
        .float => |float| float,
        .number_string => |text| std.fmt.parseFloat(f64, text) catch null,
        else => null,
    };
}

fn jsonIntegerAsFloat(value: std.json.Value) ?f64 {
    return switch (value) {
        .integer => |integer| @floatFromInt(integer),
        .number_string => |text| @floatFromInt(std.fmt.parseInt(i64, text, 10) catch return null),
        else => null,
    };
}

fn jsonValuesEqual(a: std.json.Value, b: std.json.Value) bool {
    return switch (a) {
        .null => b == .null,
        .bool => |a_bool| switch (b) {
            .bool => |b_bool| a_bool == b_bool,
            else => false,
        },
        .integer, .float, .number_string => if (jsonNumberAsFloat(a)) |a_num| if (jsonNumberAsFloat(b)) |b_num| a_num == b_num else false else false,
        .string => |a_text| switch (b) {
            .string => |b_text| std.mem.eql(u8, a_text, b_text),
            else => false,
        },
        else => false,
    };
}

fn commandField(entry: editor_control_commands.Entry, name: []const u8) ?editor_control_commands.Field {
    for (entry.fields) |field| {
        if (std.mem.eql(u8, field.name, name)) return field;
    }
    return null;
}

fn appendToolJson(allocator: std.mem.Allocator, out: *std.ArrayList(u8), entry: editor_control_commands.Entry) !void {
    try out.appendSlice(allocator, "{\"name\":");
    try appendJsonString(allocator, out, entry.mcp_tool_name);
    try out.appendSlice(allocator, ",\"title\":");
    try appendJsonString(allocator, out, entry.title);
    try out.appendSlice(allocator, ",\"description\":");
    try appendJsonString(allocator, out, entry.description);
    try out.appendSlice(allocator, ",\"annotations\":{\"tier\":");
    try appendJsonString(allocator, out, entry.tier.label());
    try out.appendSlice(allocator, ",\"owner\":");
    try appendJsonString(allocator, out, entry.owner.label());
    try out.appendSlice(allocator, "},\"inputSchema\":");
    try out.appendSlice(allocator, entry.input_schema);
    try out.appendSlice(allocator, "}");
}

fn sendEditorCommand(allocator: std.mem.Allocator, command: []const u8) ![]u8 {
    const fd = try connectEditorSocket();
    defer _ = std.c.close(fd);

    try writeAllFd(fd, command);
    return (try readLineFdAlloc(allocator, fd, 64 * 1024)) orelse error.EditorControlMissingResult;
}

fn connectEditorSocket() !std.c.fd_t {
    const fd = std.c.socket(std.c.AF.INET, std.c.SOCK.STREAM, 0);
    if (fd < 0) return translateSocketErrno();
    errdefer _ = std.c.close(fd);

    var address = std.c.sockaddr.in{
        .port = std.mem.nativeToBig(u16, control_port),
        .addr = @bitCast([4]u8{ 127, 0, 0, 1 }),
    };
    const rc = std.c.connect(
        fd,
        @ptrCast(&address),
        @sizeOf(std.c.sockaddr.in),
    );
    if (rc < 0) return translateSocketErrno();
    return fd;
}

fn translateSocketErrno() anyerror {
    return switch (std.posix.errno(-1)) {
        .ACCES, .PERM => error.AccessDenied,
        .CONNREFUSED => error.ConnectionRefused,
        .CONNRESET => error.ConnectionResetByPeer,
        .HOSTUNREACH => error.HostUnreachable,
        .NETUNREACH => error.NetworkUnreachable,
        .TIMEDOUT => error.Timeout,
        .ADDRNOTAVAIL => error.AddressUnavailable,
        .AFNOSUPPORT => error.AddressFamilyUnsupported,
        .MFILE => error.ProcessFdQuotaExceeded,
        .NFILE => error.SystemFdQuotaExceeded,
        .NOBUFS, .NOMEM => error.SystemResources,
        else => error.UnexpectedSocketError,
    };
}

fn writeAllFd(fd: std.c.fd_t, bytes: []const u8) !void {
    var written: usize = 0;
    while (written < bytes.len) {
        const rc = std.c.write(fd, bytes[written..].ptr, bytes.len - written);
        if (rc < 0) return translateSocketErrno();
        if (rc == 0) return error.ConnectionResetByPeer;
        written += @intCast(rc);
    }
}

fn readLineFdAlloc(allocator: std.mem.Allocator, fd: std.c.fd_t, max_bytes: usize) !?[]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, 256);
    errdefer out.deinit(allocator);
    var buffer: [1024]u8 = undefined;
    while (true) {
        const rc = std.c.read(fd, &buffer, buffer.len);
        if (rc < 0) return translateSocketErrno();
        if (rc == 0) {
            if (out.items.len == 0) {
                out.deinit(allocator);
                return null;
            }
            return try out.toOwnedSlice(allocator);
        }
        const read_len: usize = @intCast(rc);
        for (buffer[0..read_len]) |byte| {
            if (byte == '\n') return try out.toOwnedSlice(allocator);
            if (byte == '\r') continue;
            if (out.items.len >= max_bytes) return error.StreamTooLong;
            try out.append(allocator, byte);
        }
    }
}

fn readLineAlloc(allocator: std.mem.Allocator, reader: *std.Io.Reader, max_bytes: usize) !?[]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, 256);
    errdefer out.deinit(allocator);
    while (true) {
        const byte = reader.takeByte() catch |err| switch (err) {
            error.EndOfStream => {
                if (out.items.len == 0) {
                    out.deinit(allocator);
                    return null;
                }
                return try out.toOwnedSlice(allocator);
            },
            else => return err,
        };
        if (byte == '\n') return try out.toOwnedSlice(allocator);
        if (byte == '\r') continue;
        if (out.items.len >= max_bytes) {
            try discardLine(reader);
            return error.StreamTooLong;
        }
        try out.append(allocator, byte);
    }
}

fn discardLine(reader: *std.Io.Reader) !void {
    while (true) {
        const byte = reader.takeByte() catch |err| switch (err) {
            error.EndOfStream => return,
            else => return err,
        };
        if (byte == '\n') return;
    }
}

fn toolTextResponse(allocator: std.mem.Allocator, id_text: []const u8, is_error: bool, text: []const u8) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, text.len + 128);
    defer out.deinit(allocator);
    try appendFmt(allocator, &out, "{{\"jsonrpc\":\"2.0\",\"id\":{s},\"result\":{{\"content\":[{{\"type\":\"text\",\"text\":", .{id_text});
    try appendJsonString(allocator, &out, text);
    try appendFmt(allocator, &out, "}}],\"isError\":{}}}}}", .{is_error});
    return out.toOwnedSlice(allocator);
}

fn errorResponse(allocator: std.mem.Allocator, id_text: []const u8, code: i32, message: []const u8) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, 160);
    defer out.deinit(allocator);
    try appendFmt(allocator, &out, "{{\"jsonrpc\":\"2.0\",\"id\":{s},\"error\":{{\"code\":{d},\"message\":", .{ id_text, code });
    try appendJsonString(allocator, &out, message);
    try appendFmt(allocator, &out, "}}}}", .{});
    return out.toOwnedSlice(allocator);
}

fn idJson(allocator: std.mem.Allocator, maybe_value: ?std.json.Value) ![]u8 {
    const value = maybe_value orelse return allocator.dupe(u8, "null");
    switch (value) {
        .integer => |integer| return std.fmt.allocPrint(allocator, "{d}", .{integer}),
        .float => |float| return std.fmt.allocPrint(allocator, "{d}", .{float}),
        .number_string => |text| return allocator.dupe(u8, text),
        .string => |text| {
            var out = try std.ArrayList(u8).initCapacity(allocator, text.len + 2);
            defer out.deinit(allocator);
            try appendJsonString(allocator, &out, text);
            return out.toOwnedSlice(allocator);
        },
        .null => return allocator.dupe(u8, "null"),
        else => return error.InvalidRequestId,
    }
}

fn valueString(value: std.json.Value) ?[]const u8 {
    return switch (value) {
        .string => |text| text,
        else => null,
    };
}

fn appendStringField(allocator: std.mem.Allocator, out: *std.ArrayList(u8), name: []const u8, value: std.json.Value) !void {
    const text = valueString(value) orelse return error.InvalidToolArguments;
    try appendFmt(allocator, out, ",\"{s}\":", .{name});
    try appendJsonString(allocator, out, text);
}

fn appendNumberField(allocator: std.mem.Allocator, out: *std.ArrayList(u8), name: []const u8, value: std.json.Value) !void {
    try appendFmt(allocator, out, ",\"{s}\":", .{name});
    switch (value) {
        .integer => |integer| try appendFmt(allocator, out, "{d}", .{integer}),
        .float => |float| try appendFmt(allocator, out, "{d}", .{float}),
        .number_string => |text| try out.appendSlice(allocator, text),
        else => return error.InvalidToolArguments,
    }
}

fn appendBooleanField(allocator: std.mem.Allocator, out: *std.ArrayList(u8), name: []const u8, value: std.json.Value) !void {
    try appendFmt(allocator, out, ",\"{s}\":", .{name});
    switch (value) {
        .bool => |boolean| try out.appendSlice(allocator, if (boolean) "true" else "false"),
        else => return error.InvalidToolArguments,
    }
}

fn appendJsonField(allocator: std.mem.Allocator, out: *std.ArrayList(u8), name: []const u8, value: std.json.Value) !void {
    try appendFmt(allocator, out, ",\"{s}\":{f}", .{ name, std.json.fmt(value, .{}) });
}

fn appendJsonString(allocator: std.mem.Allocator, out: *std.ArrayList(u8), value: []const u8) !void {
    try out.append(allocator, '"');
    for (value) |ch| {
        switch (ch) {
            '"' => try out.appendSlice(allocator, "\\\""),
            '\\' => try out.appendSlice(allocator, "\\\\"),
            '\n' => try out.appendSlice(allocator, "\\n"),
            '\r' => try out.appendSlice(allocator, "\\r"),
            '\t' => try out.appendSlice(allocator, "\\t"),
            else => if (ch < 0x20) {
                try appendFmt(allocator, out, "\\u{x:0>4}", .{ch});
            } else {
                try out.append(allocator, ch);
            },
        }
    }
    try out.append(allocator, '"');
}

fn appendFmt(allocator: std.mem.Allocator, out: *std.ArrayList(u8), comptime fmt: []const u8, args: anytype) !void {
    const text = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(text);
    try out.appendSlice(allocator, text);
}

test "mcp mapper rejects missing required fields" {
    try expectInvalidToolArguments("world_region_upsert", "{}");
    try expectInvalidToolArguments("world_region_upsert", "{\"object\":\"village-core\"}");
    try expectInvalidToolArguments("world_region_upsert", "{\"cells\":\"\"}");
    try expectInvalidToolArguments("world_region_upsert", "null");
    try std.testing.expectError(error.InvalidToolArguments, buildEditorCommand(std.testing.allocator, "world_region_upsert", null));

    try expectInvalidToolArguments("world_region_paint", "{\"object\":\"village-core\",\"point_x\":0,\"point_y\":0}");
    try expectInvalidToolArguments("world_region_delete", "{}");
    try expectInvalidToolArguments("prop_source_delete", "{}");

    try expectValidToolArguments("world_region_upsert", "{\"object\":\"village-core\",\"cells\":\"\"}");
    try expectValidToolArguments("prop_source_delete", "{\"source_id\":\"chimney-stack\"}");
    try expectValidToolArguments("prop_delete", "null");
    try expectValidToolArguments("prop_delete", "{}");
}

test "mcp mapper enforces schema constraints beyond required fields" {
    try expectInvalidToolArguments("terrain_sculpt", "{\"point_x\":0,\"point_z\":0,\"operation\":\"explode\"}");
    try expectInvalidToolArguments("terrain_sculpt", "{\"point_x\":0,\"point_z\":0,\"operation\":\"raise\",\"radius\":0}");
    try expectInvalidToolArguments("terrain_material_paint", "{\"object\":\"snow\",\"point_x\":0,\"point_z\":0}");
    try expectInvalidToolArguments("terrain_material_paint", "{\"object\":\"rock\",\"point_x\":0,\"point_z\":0,\"hardness\":0}");
    try expectInvalidToolArguments("terrain_geology_start", "{\"min_x\":0,\"max_x\":0,\"min_z\":0,\"max_z\":0,\"cell_size_m\":1,\"batch_size\":2,\"properties\":{}}");
    try expectInvalidToolArguments("terrain_heightmap_batch_load", "{\"path\":\"height.png\",\"min_x\":0,\"max_x\":0,\"min_z\":0,\"max_z\":0,\"cell_size_m\":1,\"min_height\":0}");
    try expectInvalidToolArguments("terrain_heightmap_batch_load", "{\"path\":\"height.png\",\"min_x\":0,\"max_x\":0,\"min_z\":0,\"max_z\":0,\"cell_size_m\":0,\"min_height\":0,\"max_height\":1}");
    try expectInvalidToolArguments("prop_source_sphere_add", "{\"source_id\":\"sphere\",\"position\":[0,0],\"rotation\":[0,0,0,1],\"scale\":[1,1,1],\"radius\":1,\"segments\":4,\"rings\":4}");
    try expectInvalidToolArguments("prop_source_sphere_add", "{\"source_id\":\"sphere\",\"position\":[0,0,0],\"rotation\":[0,0,0,1],\"scale\":[1,1,1],\"radius\":1,\"segments\":3,\"rings\":4}");
    try expectInvalidToolArguments("marker_create", "{\"kind\":\"boss_zone\",\"point_x\":0,\"point_z\":0}");
    try expectInvalidToolArguments("marker_create", "{\"kind\":\"spawn_point\",\"radius\":0}");
    try expectInvalidToolArguments("marker_update", "{\"radius\":2}");
    try expectInvalidToolArguments("marker_update", "{\"object\":\"Start\",\"kind\":\"boss_zone\"}");
    try expectInvalidToolArguments("selection_scope_set", "{\"scope\":\"everything\"}");
    try expectInvalidToolArguments("selection_box_select", "{\"screen_x\":1,\"screen_y\":2,\"end_x\":3}");
    try expectInvalidToolArguments("object_properties_set", "{\"object\":\"plot\",\"properties\":{}}");
    try expectInvalidToolArguments("object_properties_set", "{\"object\":\"plot\",\"properties\":{\"bad\":[]}}");
    try expectInvalidToolArguments("prop_texture_fill", "{\"r\":-1,\"g\":0,\"b\":0}");
    try expectInvalidToolArguments("prop_texture_fill", "{\"r\":0,\"g\":0,\"b\":256}");

    try expectValidToolArguments("terrain_sculpt", "{\"point_x\":0,\"point_z\":0,\"operation\":\"raise\",\"radius\":0.001}");
    try expectValidToolArguments("terrain_material_paint", "{\"object\":\"rock\",\"point_x\":0,\"point_z\":0,\"radius\":256,\"opacity\":1,\"hardness\":0.5}");
    try expectValidToolArguments("terrain_geology_start", "{\"min_x\":0,\"max_x\":0,\"min_z\":0,\"max_z\":0,\"cell_size_m\":1,\"batch_size\":1,\"properties\":{}}");
    try expectValidToolArguments("terrain_heightmap_batch_load", "{\"path\":\"height.png\",\"min_x\":-1,\"max_x\":0,\"min_z\":-1,\"max_z\":0,\"cell_size_m\":256,\"min_height\":-25,\"max_height\":760}");
    try expectValidToolArguments("prop_source_sphere_add", "{\"source_id\":\"sphere\",\"position\":[0,0,0],\"rotation\":[0,0,0,1],\"scale\":[1,1,1],\"radius\":1,\"segments\":4,\"rings\":4}");
    try expectValidToolArguments("prop_sketch_profile_point", "{\"point_x\":0.25,\"point_z\":1.0}");
    try expectValidToolArguments("marker_create", "{\"kind\":\"spawn_point\",\"object\":\"Spawn A\",\"marker_id\":\"spawn-a\",\"group\":\"wave-1\",\"point_x\":0,\"point_y\":1,\"point_z\":2,\"radius\":2}");
    try expectValidToolArguments("marker_update", "{\"object\":\"Spawn A\",\"group\":\"wave-2\",\"point_x\":3,\"radius\":3}");
    try expectValidToolArguments("selection_scope_set", "{\"scope\":\"source\"}");
    try expectValidToolArguments("selection_pick", "{\"screen_x\":16,\"screen_y\":24}");
    try expectValidToolArguments("selection_box_select", "{\"screen_x\":16,\"screen_y\":24,\"end_x\":64,\"end_y\":96}");
    try expectValidToolArguments("selection_pick_world", "{\"point_x\":0,\"point_y\":1,\"point_z\":0}");
    try expectValidToolArguments("object_properties_set", "{\"object\":\"plot\",\"properties\":{\"material_wall\":\"stone\"}}");
    try expectValidToolArguments("prop_texture_fill", "{\"r\":0,\"g\":0,\"b\":255}");
}

test "mcp exposed command schemas are internally consistent" {
    var seen_tools = std.StringHashMap(void).init(std.testing.allocator);
    defer seen_tools.deinit();
    var seen_commands = std.StringHashMap(void).init(std.testing.allocator);
    defer seen_commands.deinit();

    for (editor_control_commands.entries) |entry| {
        if (!entry.exposedToMcp()) continue;
        try std.testing.expect(!seen_tools.contains(entry.mcp_tool_name));
        try seen_tools.put(entry.mcp_tool_name, {});
        try std.testing.expect(!seen_commands.contains(entry.command_name));
        try seen_commands.put(entry.command_name, {});

        var parsed_schema = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, entry.input_schema, .{});
        defer parsed_schema.deinit();
        const schema_object = switch (parsed_schema.value) {
            .object => |schema_object| schema_object,
            else => return error.InvalidMcpSchema,
        };
        try std.testing.expectEqualStrings("object", valueString(schema_object.get("type") orelse return error.InvalidMcpSchema) orelse return error.InvalidMcpSchema);
        if (schema_object.get("properties")) |properties_value| {
            const properties = switch (properties_value) {
                .object => |properties| properties,
                else => return error.InvalidMcpSchema,
            };
            var fields = properties.iterator();
            while (fields.next()) |field| {
                if (entry.argument_policy == .fields or entry.argument_policy == .object_string) {
                    try std.testing.expect(commandField(entry, field.key_ptr.*) != null);
                }
            }
        }
        if (schema_object.get("required")) |required_value| {
            const required = switch (required_value) {
                .array => |required| required,
                else => return error.InvalidMcpSchema,
            };
            for (required.items) |item| {
                const field_name = valueString(item) orelse return error.InvalidMcpSchema;
                if (entry.argument_policy == .fields or entry.argument_policy == .object_string) {
                    try std.testing.expect(commandField(entry, field_name) != null);
                }
            }
        }
    }
}

test "mcp mapper accepts generated minimum arguments for every exposed tool" {
    for (editor_control_commands.entries) |entry| {
        if (!entry.exposedToMcp()) continue;
        const args_json = try minimumArgumentsJson(std.testing.allocator, entry, null);
        defer std.testing.allocator.free(args_json);
        var parsed_args = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, args_json, .{});
        defer parsed_args.deinit();

        const command_json = buildEditorCommand(std.testing.allocator, entry.mcp_tool_name, parsed_args.value) catch |err| {
            std.debug.print("minimum args failed for {s}: args={s}\n", .{ entry.mcp_tool_name, args_json });
            return err;
        };
        defer std.testing.allocator.free(command_json);

        var command = try std.json.parseFromSlice(struct {
            id: []const u8,
            name: []const u8,
        }, std.testing.allocator, command_json, .{ .ignore_unknown_fields = true });
        defer command.deinit();
        try std.testing.expectEqualStrings(entry.command_name, command.value.name);
    }
}

test "mcp mapper rejects generated arguments missing each required field" {
    for (editor_control_commands.entries) |entry| {
        if (!entry.exposedToMcp()) continue;
        var parsed_schema = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, entry.input_schema, .{});
        defer parsed_schema.deinit();
        const schema_object = switch (parsed_schema.value) {
            .object => |schema_object| schema_object,
            else => return error.InvalidMcpSchema,
        };
        const required_value = schema_object.get("required") orelse continue;
        const required = switch (required_value) {
            .array => |required| required,
            else => return error.InvalidMcpSchema,
        };
        for (required.items) |item| {
            const omitted_field = valueString(item) orelse return error.InvalidMcpSchema;
            const args_json = try minimumArgumentsJson(std.testing.allocator, entry, omitted_field);
            defer std.testing.allocator.free(args_json);
            var parsed_args = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, args_json, .{});
            defer parsed_args.deinit();

            const command_json = buildEditorCommand(std.testing.allocator, entry.mcp_tool_name, parsed_args.value) catch |err| {
                try std.testing.expectEqual(error.InvalidToolArguments, err);
                continue;
            };
            defer std.testing.allocator.free(command_json);
            std.debug.print("missing required field accepted for {s}.{s}: args={s} command={s}\n", .{
                entry.mcp_tool_name,
                omitted_field,
                args_json,
                command_json,
            });
            return error.ExpectedInvalidToolArguments;
        }
    }
}

test "mcp mapper rejects unknown root fields for closed schemas" {
    for (editor_control_commands.entries) |entry| {
        if (!entry.exposedToMcp()) continue;
        if (!try rootRejectsAdditionalProperties(std.testing.allocator, entry)) continue;
        const args_json = try minimumArgumentsJson(std.testing.allocator, entry, null);
        defer std.testing.allocator.free(args_json);
        const unexpected_args_json = try addUnexpectedRootField(std.testing.allocator, args_json);
        defer std.testing.allocator.free(unexpected_args_json);
        var parsed_args = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, unexpected_args_json, .{});
        defer parsed_args.deinit();

        const command_json = buildEditorCommand(std.testing.allocator, entry.mcp_tool_name, parsed_args.value) catch |err| {
            try std.testing.expectEqual(error.InvalidToolArguments, err);
            continue;
        };
        defer std.testing.allocator.free(command_json);
        std.debug.print("unknown root field accepted for {s}: args={s} command={s}\n", .{
            entry.mcp_tool_name,
            unexpected_args_json,
            command_json,
        });
        return error.ExpectedInvalidToolArguments;
    }
}

test "mcp json-rpc envelope fuzz returns parseable responses without editor socket" {
    var prng = std.Random.DefaultPrng.init(0x6d63705f72706331);
    var random = prng.random();
    var line_buf: [768]u8 = undefined;

    var i: usize = 0;
    while (i < 512) : (i += 1) {
        const line = try randomMcpEnvelopeJson(&random, &line_buf, i);
        const response = try handleMessage(std.testing.allocator, undefined, line);
        defer std.testing.allocator.free(response);
        if (response.len == 0) continue;
        try expectJsonRpcResponse(response);
    }
}

test "mcp json-rpc invalid ids fail as responses and notifications stay silent" {
    try expectJsonRpcError(
        "{\"jsonrpc\":\"2.0\",\"id\":{},\"method\":\"initialize\"}",
        -32600,
        "Invalid request id",
    );
    try expectJsonRpcError(
        "{\"jsonrpc\":\"2.0\",\"id\":[],\"method\":\"tools/list\"}",
        -32600,
        "Invalid request id",
    );
    try expectJsonRpcError(
        "{\"jsonrpc\":\"2.0\",\"id\":true,\"method\":\"unknown\"}",
        -32600,
        "Invalid request id",
    );
    const notification_response = try handleMessage(
        std.testing.allocator,
        undefined,
        "{\"jsonrpc\":\"2.0\",\"id\":{},\"method\":\"notifications/cancelled\"}",
    );
    defer std.testing.allocator.free(notification_response);
    try std.testing.expectEqual(@as(usize, 0), notification_response.len);
}

test "mcp stdin line reader drains oversized lines before next message" {
    var input = [_]u8{0} ** 96;
    @memset(input[0..40], 'x');
    input[40] = '\n';
    @memcpy(input[41..46], "short");
    input[46] = '\n';
    var reader = std.Io.Reader.fixed(input[0..47]);

    try std.testing.expectError(error.StreamTooLong, readLineAlloc(std.testing.allocator, &reader, 16));
    const line = try readLineAlloc(std.testing.allocator, &reader, 16) orelse return error.MissingSecondLine;
    defer std.testing.allocator.free(line);
    try std.testing.expectEqualStrings("short", line);
    try std.testing.expect((try readLineAlloc(std.testing.allocator, &reader, 16)) == null);
}

test "mcp region argument mapper fuzz parses or rejects cleanly" {
    var prng = std.Random.DefaultPrng.init(0x6d63705f6d617031);
    var random = prng.random();
    var json_buf: [384]u8 = undefined;

    var i: usize = 0;
    while (i < 512) : (i += 1) {
        const tool_name = switch (i % 5) {
            0, 1 => "world_region_upsert",
            2, 3 => "world_region_paint",
            else => "world_region_delete",
        };
        const args_json = try randomRegionArgumentsJson(&random, &json_buf, tool_name, i);
        var parsed_args = std.json.parseFromSlice(std.json.Value, std.testing.allocator, args_json, .{ .ignore_unknown_fields = true }) catch continue;
        defer parsed_args.deinit();

        const command_json = buildEditorCommand(std.testing.allocator, tool_name, parsed_args.value) catch continue;
        defer std.testing.allocator.free(command_json);

        var command = std.json.parseFromSlice(struct {
            id: []const u8,
            name: []const u8,
            object: ?[]const u8 = null,
            parent: ?[]const u8 = null,
            cells: ?[]const u8 = null,
            operation: ?[]const u8 = null,
            point_x: ?f64 = null,
            point_y: ?f64 = null,
            point_z: ?f64 = null,
            screen_x: ?f64 = null,
            screen_y: ?f64 = null,
            radius: ?f64 = null,
        }, std.testing.allocator, command_json, .{ .ignore_unknown_fields = false }) catch |err| {
            std.debug.print("failed command_json={s}\n", .{command_json});
            return err;
        };
        defer command.deinit();

        const expected_name = editor_control_commands.findByMcpToolName(tool_name).?.command_name;
        try std.testing.expectEqualStrings(expected_name, command.value.name);
        try std.testing.expect(std.mem.startsWith(u8, command.value.id, "mcp-"));
        if (std.mem.eql(u8, tool_name, "world_region_upsert")) {
            try std.testing.expect(command.value.object != null);
            try std.testing.expect(command.value.cells != null);
        } else if (std.mem.eql(u8, tool_name, "world_region_paint")) {
            try std.testing.expect(command.value.object != null);
            try std.testing.expect(command.value.point_x != null);
            try std.testing.expect(command.value.point_y != null);
            try std.testing.expect(command.value.point_z != null);
        } else if (std.mem.eql(u8, tool_name, "world_region_delete")) {
            try std.testing.expect(command.value.object != null);
        }
    }
}

fn expectInvalidToolArguments(tool_name: []const u8, args_json: []const u8) !void {
    var parsed_args = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, args_json, .{ .ignore_unknown_fields = true });
    defer parsed_args.deinit();
    const command_json = buildEditorCommand(std.testing.allocator, tool_name, parsed_args.value) catch |err| {
        try std.testing.expectEqual(error.InvalidToolArguments, err);
        return;
    };
    defer std.testing.allocator.free(command_json);
    std.debug.print("expected InvalidToolArguments for {s} args={s}, got command={s}\n", .{ tool_name, args_json, command_json });
    return error.ExpectedInvalidToolArguments;
}

fn expectValidToolArguments(tool_name: []const u8, args_json: []const u8) !void {
    var parsed_args = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, args_json, .{ .ignore_unknown_fields = true });
    defer parsed_args.deinit();
    const command_json = try buildEditorCommand(std.testing.allocator, tool_name, parsed_args.value);
    defer std.testing.allocator.free(command_json);
    var command = try std.json.parseFromSlice(struct {
        id: []const u8,
        name: []const u8,
    }, std.testing.allocator, command_json, .{ .ignore_unknown_fields = true });
    defer command.deinit();
    const expected_name = editor_control_commands.findByMcpToolName(tool_name).?.command_name;
    try std.testing.expectEqualStrings(expected_name, command.value.name);
}

fn minimumArgumentsJson(allocator: std.mem.Allocator, entry: editor_control_commands.Entry, omit_required_field: ?[]const u8) ![]u8 {
    var parsed_schema = try std.json.parseFromSlice(std.json.Value, allocator, entry.input_schema, .{});
    defer parsed_schema.deinit();
    const schema_object = switch (parsed_schema.value) {
        .object => |schema_object| schema_object,
        else => return error.InvalidMcpSchema,
    };
    const properties_value = schema_object.get("properties");
    const properties = if (properties_value) |value| switch (value) {
        .object => |properties| properties,
        else => return error.InvalidMcpSchema,
    } else null;
    const required_value = schema_object.get("required");
    const required = if (required_value) |value| switch (value) {
        .array => |required| required,
        else => return error.InvalidMcpSchema,
    } else null;

    var out = try std.ArrayList(u8).initCapacity(allocator, 128);
    defer out.deinit(allocator);
    try out.append(allocator, '{');
    var first = true;
    if (required) |required_fields| {
        for (required_fields.items) |item| {
            const field_name = valueString(item) orelse return error.InvalidMcpSchema;
            if (omit_required_field) |omit| {
                if (std.mem.eql(u8, field_name, omit)) continue;
            }
            const property_schema = if (properties) |property_map|
                property_map.get(field_name) orelse return error.InvalidMcpSchema
            else
                return error.InvalidMcpSchema;
            if (!first) try out.append(allocator, ',');
            first = false;
            try appendJsonString(allocator, &out, field_name);
            try out.append(allocator, ':');
            try appendSampleJsonValue(allocator, &out, property_schema);
        }
    }
    try out.append(allocator, '}');
    return out.toOwnedSlice(allocator);
}

fn rootRejectsAdditionalProperties(allocator: std.mem.Allocator, entry: editor_control_commands.Entry) !bool {
    var parsed_schema = try std.json.parseFromSlice(std.json.Value, allocator, entry.input_schema, .{});
    defer parsed_schema.deinit();
    const schema_object = switch (parsed_schema.value) {
        .object => |schema_object| schema_object,
        else => return error.InvalidMcpSchema,
    };
    const additional = schema_object.get("additionalProperties") orelse return false;
    return switch (additional) {
        .bool => |allowed| !allowed,
        else => false,
    };
}

fn addUnexpectedRootField(allocator: std.mem.Allocator, args_json: []const u8) ![]u8 {
    if (args_json.len < 2 or args_json[0] != '{' or args_json[args_json.len - 1] != '}') return error.InvalidMcpSchema;
    if (std.mem.eql(u8, args_json, "{}")) {
        return allocator.dupe(u8, "{\"__unexpected\":true}");
    }
    return std.fmt.allocPrint(allocator, "{s},\"__unexpected\":true}}", .{args_json[0 .. args_json.len - 1]});
}

fn appendSampleJsonValue(allocator: std.mem.Allocator, out: *std.ArrayList(u8), schema: std.json.Value) anyerror!void {
    const schema_object = switch (schema) {
        .object => |schema_object| schema_object,
        else => return error.InvalidMcpSchema,
    };
    if (schema_object.get("const")) |constant| {
        const text = try std.fmt.allocPrint(allocator, "{f}", .{std.json.fmt(constant, .{})});
        defer allocator.free(text);
        try out.appendSlice(allocator, text);
        return;
    }
    if (schema_object.get("oneOf")) |one_of_value| {
        const one_of = switch (one_of_value) {
            .array => |one_of| one_of,
            else => return error.InvalidMcpSchema,
        };
        if (one_of.items.len == 0) return error.InvalidMcpSchema;
        return appendSampleJsonValue(allocator, out, one_of.items[0]);
    }
    const type_text = valueString(schema_object.get("type") orelse return error.InvalidMcpSchema) orelse return error.InvalidMcpSchema;
    if (std.mem.eql(u8, type_text, "string")) {
        if (schema_object.get("enum")) |enum_value| {
            const enum_items = switch (enum_value) {
                .array => |enum_items| enum_items,
                else => return error.InvalidMcpSchema,
            };
            if (enum_items.items.len == 0) return error.InvalidMcpSchema;
            const first = valueString(enum_items.items[0]) orelse return error.InvalidMcpSchema;
            return appendJsonString(allocator, out, first);
        }
        return appendJsonString(allocator, out, "sample");
    }
    if (std.mem.eql(u8, type_text, "number")) {
        const minimum = jsonNumberAsFloat(schema_object.get("minimum") orelse .null) orelse 1.25;
        return appendFmt(allocator, out, "{d}", .{minimum});
    }
    if (std.mem.eql(u8, type_text, "integer")) {
        const minimum = schemaInteger(schema_object.get("minimum")) orelse 1;
        return appendFmt(allocator, out, "{d}", .{minimum});
    }
    if (std.mem.eql(u8, type_text, "boolean")) {
        return out.appendSlice(allocator, "true");
    }
    if (std.mem.eql(u8, type_text, "array")) {
        try out.append(allocator, '[');
        const count = schemaInteger(schema_object.get("minItems")) orelse 1;
        const item_schema = schema_object.get("items") orelse return error.InvalidMcpSchema;
        var i: i64 = 0;
        while (i < count) : (i += 1) {
            if (i != 0) try out.append(allocator, ',');
            try appendSampleJsonValue(allocator, out, item_schema);
        }
        return out.append(allocator, ']');
    }
    if (std.mem.eql(u8, type_text, "object")) {
        return appendSampleJsonObject(allocator, out, schema_object);
    }
    return error.InvalidMcpSchema;
}

fn appendSampleJsonObject(allocator: std.mem.Allocator, out: *std.ArrayList(u8), schema_object: anytype) anyerror!void {
    const properties_value = schema_object.get("properties");
    const properties = if (properties_value) |value| switch (value) {
        .object => |properties| properties,
        else => return error.InvalidMcpSchema,
    } else null;
    const required_value = schema_object.get("required");
    const required = if (required_value) |value| switch (value) {
        .array => |required| required,
        else => return error.InvalidMcpSchema,
    } else null;
    const min_properties = schemaInteger(schema_object.get("minProperties")) orelse 0;

    try out.append(allocator, '{');
    var first = true;
    if (required) |required_fields| {
        for (required_fields.items) |item| {
            const field_name = valueString(item) orelse return error.InvalidMcpSchema;
            const property_schema = if (properties) |property_map|
                property_map.get(field_name) orelse return error.InvalidMcpSchema
            else
                return error.InvalidMcpSchema;
            if (!first) try out.append(allocator, ',');
            first = false;
            try appendJsonString(allocator, out, field_name);
            try out.append(allocator, ':');
            try appendSampleJsonValue(allocator, out, property_schema);
        }
    }
    if (first and min_properties > 0) {
        try appendJsonString(allocator, out, "sample");
        try out.append(allocator, ':');
        try out.appendSlice(allocator, "\"value\"");
    }
    try out.append(allocator, '}');
}

fn schemaInteger(maybe_value: ?std.json.Value) ?i64 {
    const value = maybe_value orelse return null;
    return switch (value) {
        .integer => |integer| integer,
        .number_string => |text| std.fmt.parseInt(i64, text, 10) catch null,
        else => null,
    };
}

fn expectJsonRpcResponse(response: []const u8) !void {
    var parsed = std.json.parseFromSlice(std.json.Value, std.testing.allocator, response, .{}) catch |err| {
        std.debug.print("invalid response json={s}\n", .{response});
        return err;
    };
    defer parsed.deinit();
    const root = switch (parsed.value) {
        .object => |object| object,
        else => return error.InvalidMcpResponse,
    };
    try std.testing.expectEqualStrings("2.0", valueString(root.get("jsonrpc") orelse return error.InvalidMcpResponse) orelse return error.InvalidMcpResponse);
    try std.testing.expect(root.get("result") != null or root.get("error") != null);
}

fn expectJsonRpcError(line: []const u8, expected_code: i32, expected_message: []const u8) !void {
    const response = try handleMessage(std.testing.allocator, undefined, line);
    defer std.testing.allocator.free(response);
    var parsed = try std.json.parseFromSlice(struct {
        jsonrpc: []const u8,
        id: ?std.json.Value = null,
        @"error": struct {
            code: i32,
            message: []const u8,
        },
    }, std.testing.allocator, response, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try std.testing.expectEqualStrings("2.0", parsed.value.jsonrpc);
    try std.testing.expectEqual(expected_code, parsed.value.@"error".code);
    try std.testing.expectEqualStrings(expected_message, parsed.value.@"error".message);
}

fn randomMcpEnvelopeJson(random: *std.Random, out: []u8, iteration: usize) ![]const u8 {
    _ = random.uintLessThan(u8, 255);
    return switch (iteration % 20) {
        0 => "{",
        1 => "[]",
        2 => "{\"jsonrpc\":\"2.0\",\"id\":1}",
        3 => "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":7}",
        4 => "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"notifications/cancelled\"}",
        5 => "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"initialize\"}",
        6 => "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/list\"}",
        7 => "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"tools/call\"}",
        8 => "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/call\",\"params\":[]}",
        9 => "{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"tools/call\",\"params\":{}}",
        10 => "{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"tools/call\",\"params\":{\"name\":42}}",
        11 => "{\"jsonrpc\":\"2.0\",\"id\":10,\"method\":\"tools/call\",\"params\":{\"name\":\"missing_tool\",\"arguments\":{}}}",
        12 => "{\"jsonrpc\":\"2.0\",\"id\":11,\"method\":\"tools/call\",\"params\":{\"name\":\"world_region_upsert\",\"arguments\":{}}}",
        13 => "{\"jsonrpc\":\"2.0\",\"id\":\"abc\",\"method\":\"unknown\"}",
        14 => "{\"jsonrpc\":\"2.0\",\"id\":null,\"method\":\"tools/call\",\"params\":{\"name\":\"world_region_delete\",\"arguments\":null}}",
        15 => "{\"jsonrpc\":\"2.0\",\"id\":{},\"method\":\"initialize\"}",
        16 => "{\"jsonrpc\":\"2.0\",\"id\":[],\"method\":\"tools/list\"}",
        17 => "{\"jsonrpc\":\"2.0\",\"id\":false,\"method\":\"unknown\"}",
        18 => "{\"jsonrpc\":\"2.0\",\"id\":{},\"method\":\"notifications/cancelled\"}",
        else => std.fmt.bufPrint(out, "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"tools/call\",\"params\":{{\"name\":\"world_region_paint\",\"arguments\":{{\"object\":\"r-{d}\",\"point_x\":{d}}}}}}}", .{
            iteration,
            iteration,
            @as(i32, @intCast(iteration % 17)),
        }),
    };
}

fn randomRegionArgumentsJson(random: *std.Random, out: []u8, tool_name: []const u8, iteration: usize) ![]const u8 {
    const shape = random.uintLessThan(u8, 8);
    if (shape == 0) return "{}";
    if (shape == 1) return "[]";
    if (shape == 2) return "{\"object\":42}";
    if (shape == 3) return "{\"unknown\":\"field\"}";

    const object = if (iteration % 11 == 0) "bad\\nregion" else "region-safe";
    if (std.mem.eql(u8, tool_name, "world_region_delete")) {
        return std.fmt.bufPrint(out, "{{\"object\":\"{s}\"}}", .{object});
    }
    if (std.mem.eql(u8, tool_name, "world_region_paint")) {
        const operation = if (iteration % 7 == 0) "smear" else if (iteration % 2 == 0) "assign" else "erase";
        return std.fmt.bufPrint(out, "{{\"object\":\"{s}\",\"parent\":\"Region Safe\",\"operation\":\"{s}\",\"point_x\":{d},\"point_y\":0,\"point_z\":{d},\"radius\":{d}}}", .{
            object,
            operation,
            @as(i32, @intCast(iteration % 17)),
            -@as(i32, @intCast(iteration % 13)),
            @as(i32, @intCast((iteration % 5) * 128)),
        });
    }
    const cells = if (iteration % 9 == 0) "0,0,0;0,0,0" else if (iteration % 4 == 0) "x,y,z" else "0,0,0;1,0,0";
    return std.fmt.bufPrint(out, "{{\"object\":\"{s}\",\"parent\":\"Region Safe\",\"cells\":\"{s}\"}}", .{ object, cells });
}
