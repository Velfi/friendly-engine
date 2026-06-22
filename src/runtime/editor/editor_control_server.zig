const std = @import("std");

pub const control_port: u16 = 39743;
pub const max_command_bytes = 16 * 1024;
const control_request_drain_count_threshold = 16;
const control_request_drain_bytes_threshold = 128 * 1024;

pub const ControlRequest = struct {
    bytes: []u8,
    result: ?[]u8 = null,
    done: bool = false,
    condition: std.Io.Condition = .init,

    fn deinit(self: *ControlRequest, allocator: std.mem.Allocator) void {
        allocator.free(self.bytes);
        if (self.result) |result| allocator.free(result);
        allocator.destroy(self);
    }
};

pub const ControlStats = struct {
    executed: u64 = 0,
    inflight: u32 = 0,
    queued: u32 = 0,
    queued_bytes: usize = 0,
};

pub const ControlServer = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    server: std.Io.net.Server,
    thread: ?std.Thread = null,
    mutex: std.Io.Mutex = .init,
    request_ready: std.Io.Condition = .init,
    requests: std.ArrayList(*ControlRequest) = .empty,
    queued_bytes: usize = 0,
    executed_count: u64 = 0,
    active_count: u32 = 0,
    drain_all_next_frame: bool = false,
    stopping: bool = false,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) !ControlServer {
        const address = std.Io.net.IpAddress{ .ip4 = std.Io.net.Ip4Address.loopback(control_port) };
        var server = std.Io.net.IpAddress.listen(&address, io, .{ .reuse_address = true }) catch |err| switch (err) {
            error.AddressInUse => return error.EditorControlPortInUse,
            else => return err,
        };
        errdefer server.deinit(io);

        return .{
            .allocator = allocator,
            .io = io,
            .server = server,
        };
    }

    pub fn start(self: *ControlServer) !void {
        self.thread = try std.Thread.spawn(.{}, acceptLoop, .{self});
    }

    pub fn deinit(self: *ControlServer) void {
        self.mutex.lockUncancelable(self.io);
        self.stopping = true;
        self.request_ready.broadcast(self.io);
        self.mutex.unlock(self.io);
        self.server.deinit(self.io);
        if (self.thread) |thread| thread.join();

        self.mutex.lockUncancelable(self.io);
        for (self.requests.items) |request| {
            if (!request.done) {
                request.result = std.fmt.allocPrint(self.allocator, "{{\"ok\":false,\"error\":\"EditorControlStopped\"}}\n", .{}) catch null;
                request.done = true;
                request.condition.signal(self.io);
            }
        }
        self.requests.deinit(self.allocator);
        self.mutex.unlock(self.io);
    }

    fn acceptLoop(self: *ControlServer) void {
        while (true) {
            self.mutex.lockUncancelable(self.io);
            const stopping = self.stopping;
            self.mutex.unlock(self.io);
            if (stopping) return;

            const stream = self.server.accept(self.io) catch return;
            handleClient(self, stream) catch {};
        }
    }

    fn handleClient(self: *ControlServer, stream: std.Io.net.Stream) !void {
        defer stream.close(self.io);
        var read_buffer: [32 * 1024]u8 = undefined;
        var write_buffer: [32 * 1024]u8 = undefined;
        var reader_state = stream.reader(self.io, &read_buffer);
        var writer_state = stream.writer(self.io, &write_buffer);
        const reader = &reader_state.interface;
        const writer = &writer_state.interface;

        while (true) {
            const line = try readLineAlloc(self.allocator, reader, max_command_bytes) orelse return;
            if (line.len == 0) {
                self.allocator.free(line);
                continue;
            }
            const request = try self.allocator.create(ControlRequest);
            request.* = .{ .bytes = line };
            errdefer request.deinit(self.allocator);

            try self.mutex.lock(self.io);
            errdefer self.mutex.unlock(self.io);
            if (self.stopping) return error.EditorControlStopped;
            try self.requests.append(self.allocator, request);
            self.queued_bytes += request.bytes.len;
            if (self.requests.items.len > control_request_drain_count_threshold or self.queued_bytes > control_request_drain_bytes_threshold) {
                self.drain_all_next_frame = true;
            }
            self.request_ready.signal(self.io);
            while (!request.done) try request.condition.wait(self.io, &self.mutex);
            const result = request.result orelse return error.EditorControlMissingResult;
            self.mutex.unlock(self.io);

            try writer.writeAll(result);
            if (result.len == 0 or result[result.len - 1] != '\n') try writer.writeAll("\n");
            try writer.flush();
            self.mutex.lockUncancelable(self.io);
            request.deinit(self.allocator);
            self.mutex.unlock(self.io);
        }
    }

    pub fn popRequest(self: *ControlServer) ?*ControlRequest {
        if (self.requests.items.len == 0) return null;
        self.active_count += 1;
        const request = self.requests.orderedRemove(0);
        self.queued_bytes -|= request.bytes.len;
        return request;
    }

    pub fn takeDrainAllFrame(self: *ControlServer) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const drain_all = self.drain_all_next_frame;
        self.drain_all_next_frame = false;
        return drain_all;
    }

    pub fn statsSnapshot(self: *ControlServer) ControlStats {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return .{
            .executed = self.executed_count,
            .inflight = self.active_count + @as(u32, @intCast(self.requests.items.len)),
            .queued = @intCast(self.requests.items.len),
            .queued_bytes = self.queued_bytes,
        };
    }
};

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
        if (out.items.len >= max_bytes) return error.StreamTooLong;
        try out.append(allocator, byte);
    }
}
