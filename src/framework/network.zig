const std = @import("std");
const core = @import("../core/mod.zig");

pub const Packet = struct {
    connection: core.ConnectionId,
    channel: u8,
    payload: []const u8,
};

const OwnedPacket = struct {
    connection: core.ConnectionId,
    channel: u8,
    payload: []u8,
};

pub const BackendVTable = struct {
    send: *const fn (context: *anyopaque, packet: Packet) anyerror!void,
};

pub const Backend = struct {
    context: *anyopaque,
    vtable: *const BackendVTable,
};

pub const NetworkSystem = struct {
    allocator: std.mem.Allocator,
    backend: ?Backend = null,
    outgoing: std.ArrayList(OwnedPacket),
    incoming: std.ArrayList(OwnedPacket),

    pub fn init(allocator: std.mem.Allocator) NetworkSystem {
        return .{
            .allocator = allocator,
            .outgoing = .empty,
            .incoming = .empty,
        };
    }

    pub fn deinit(self: *NetworkSystem) void {
        self.clearPacketList(&self.outgoing);
        self.clearPacketList(&self.incoming);
        self.outgoing.deinit(self.allocator);
        self.incoming.deinit(self.allocator);
    }

    pub fn setBackend(self: *NetworkSystem, backend: Backend) void {
        self.backend = backend;
    }

    pub fn queueOutgoing(
        self: *NetworkSystem,
        connection: core.ConnectionId,
        channel: u8,
        payload: []const u8,
    ) !void {
        const owned_payload = try self.allocator.dupe(u8, payload);
        errdefer self.allocator.free(owned_payload);

        try self.outgoing.append(self.allocator, .{
            .connection = connection,
            .channel = channel,
            .payload = owned_payload,
        });
    }

    pub fn pushIncoming(
        self: *NetworkSystem,
        connection: core.ConnectionId,
        channel: u8,
        payload: []const u8,
    ) !void {
        const owned_payload = try self.allocator.dupe(u8, payload);
        errdefer self.allocator.free(owned_payload);

        try self.incoming.append(self.allocator, .{
            .connection = connection,
            .channel = channel,
            .payload = owned_payload,
        });
    }

    pub fn drainOutgoing(self: *NetworkSystem) !void {
        const backend = self.backend orelse return;
        for (self.outgoing.items) |packet| {
            try backend.vtable.send(backend.context, .{
                .connection = packet.connection,
                .channel = packet.channel,
                .payload = packet.payload,
            });
        }

        self.clearPacketList(&self.outgoing);
        self.outgoing.clearRetainingCapacity();
    }

    pub fn incomingCount(self: *const NetworkSystem) usize {
        return self.incoming.items.len;
    }

    pub fn incomingAt(self: *const NetworkSystem, index: usize) Packet {
        const packet = self.incoming.items[index];
        return .{
            .connection = packet.connection,
            .channel = packet.channel,
            .payload = packet.payload,
        };
    }

    pub fn clearIncoming(self: *NetworkSystem) void {
        self.clearPacketList(&self.incoming);
        self.incoming.clearRetainingCapacity();
    }

    fn clearPacketList(self: *NetworkSystem, list: *std.ArrayList(OwnedPacket)) void {
        for (list.items) |packet| {
            self.allocator.free(packet.payload);
        }
    }
};

const NetworkTestContext = struct {
    sent_packets: usize = 0,
};

fn mockSend(context: *anyopaque, packet: Packet) !void {
    const typed_context: *NetworkTestContext = @ptrCast(@alignCast(context));
    typed_context.sent_packets += 1;
    try std.testing.expect(packet.payload.len > 0);
}

const mock_backend_vtable = BackendVTable{
    .send = mockSend,
};

test "network abstraction queues and drains outgoing packets" {
    var network = NetworkSystem.init(std.testing.allocator);
    defer network.deinit();

    var context = NetworkTestContext{};
    network.setBackend(.{
        .context = &context,
        .vtable = &mock_backend_vtable,
    });

    try network.queueOutgoing(1, 0, "hello");
    try network.queueOutgoing(2, 1, "world");
    try network.drainOutgoing();

    try std.testing.expectEqual(@as(usize, 2), context.sent_packets);
    try std.testing.expectEqual(@as(usize, 0), network.outgoing.items.len);
}

test "network abstraction stores incoming packets" {
    var network = NetworkSystem.init(std.testing.allocator);
    defer network.deinit();

    try network.pushIncoming(42, 0, "abc");
    try std.testing.expectEqual(@as(usize, 1), network.incomingCount());
    const packet = network.incomingAt(0);
    try std.testing.expectEqual(@as(core.ConnectionId, 42), packet.connection);
    try std.testing.expectEqualStrings("abc", packet.payload);

    network.clearIncoming();
    try std.testing.expectEqual(@as(usize, 0), network.incomingCount());
}
