const std = @import("std");

pub const math = @import("math.zig");
pub const memory = @import("memory.zig");
pub const ids = @import("ids.zig");
pub const serialization = @import("serialization.zig");
pub const diagnostics = @import("diagnostics.zig");
pub const time = @import("time.zig");
pub const jobs = @import("jobs.zig");
pub const logging = @import("logging.zig");

pub const EntityId = ids.EntityId;
pub const ComponentTypeId = ids.ComponentTypeId;
pub const SceneId = ids.SceneId;
pub const AssetId = ids.AssetId;
pub const ActionId = ids.ActionId;
pub const ConnectionId = ids.ConnectionId;
pub const IdGenerator = ids.IdGenerator;

pub const EventEnvelope = struct {
    name: []const u8,
    schema_version: u16,
    payload: []const u8,
};

pub const NotificationBus = struct {
    allocator: std.mem.Allocator,
    events: std.ArrayList(EventEnvelope),

    pub fn init(allocator: std.mem.Allocator) NotificationBus {
        return .{
            .allocator = allocator,
            .events = .empty,
        };
    }

    pub fn deinit(self: *NotificationBus) void {
        for (self.events.items) |event| {
            self.allocator.free(event.name);
            self.allocator.free(event.payload);
        }
        self.events.deinit(self.allocator);
    }

    pub fn publish(self: *NotificationBus, name: []const u8, payload: []const u8) !void {
        return self.publishVersioned(name, 1, payload);
    }

    pub fn publishVersioned(
        self: *NotificationBus,
        name: []const u8,
        schema_version: u16,
        payload: []const u8,
    ) !void {
        const owned_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned_name);
        const owned_payload = try self.allocator.dupe(u8, payload);
        errdefer self.allocator.free(owned_payload);

        try self.events.append(self.allocator, .{
            .name = owned_name,
            .schema_version = schema_version,
            .payload = owned_payload,
        });
    }
};

pub const RequestHandlerFn = *const fn (
    context: ?*anyopaque,
    allocator: std.mem.Allocator,
    payload: []const u8,
) anyerror![]u8;

pub const RequestHandler = struct {
    context: ?*anyopaque = null,
    call: RequestHandlerFn,
};

pub const RegisteredRequest = struct {
    name: []const u8,
    handler: RequestHandler,
};

pub const RequestBus = struct {
    allocator: std.mem.Allocator,
    handlers: std.ArrayList(RegisteredRequest),

    pub fn init(allocator: std.mem.Allocator) RequestBus {
        return .{
            .allocator = allocator,
            .handlers = .empty,
        };
    }

    pub fn deinit(self: *RequestBus) void {
        self.clear();
        self.handlers.deinit(self.allocator);
    }

    pub fn register(self: *RequestBus, name: []const u8, handler: RequestHandler) !void {
        if (self.findRegistered(name) != null) return error.RequestAlreadyRegistered;

        const owned_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned_name);

        try self.handlers.append(self.allocator, .{
            .name = owned_name,
            .handler = handler,
        });
    }

    pub fn unregister(self: *RequestBus, name: []const u8) bool {
        for (self.handlers.items, 0..) |entry, i| {
            if (std.mem.eql(u8, entry.name, name)) {
                self.allocator.free(entry.name);
                _ = self.handlers.orderedRemove(i);
                return true;
            }
        }
        return false;
    }

    pub fn clear(self: *RequestBus) void {
        for (self.handlers.items) |entry| {
            self.allocator.free(entry.name);
        }
        self.handlers.clearRetainingCapacity();
    }

    pub fn request(self: *const RequestBus, name: []const u8, payload: []const u8) ![]u8 {
        const registered = self.findRegistered(name) orelse return error.UnknownRequest;
        return registered.handler.call(registered.handler.context, self.allocator, payload);
    }

    fn findRegistered(self: *const RequestBus, name: []const u8) ?*const RegisteredRequest {
        for (self.handlers.items) |*entry| {
            if (std.mem.eql(u8, entry.name, name)) return entry;
        }
        return null;
    }
};

test "notification bus stores copied payloads" {
    var bus = NotificationBus.init(std.testing.allocator);
    defer bus.deinit();

    var mutable: [3]u8 = .{ 'o', 'n', 'e' };
    try bus.publish("test.event", mutable[0..]);
    mutable[0] = 'x';

    try std.testing.expectEqual(@as(usize, 1), bus.events.items.len);
    try std.testing.expectEqual(@as(u16, 1), bus.events.items[0].schema_version);
    try std.testing.expectEqualStrings("one", bus.events.items[0].payload);
}

fn echoRequest(_: ?*anyopaque, allocator: std.mem.Allocator, payload: []const u8) ![]u8 {
    return allocator.dupe(u8, payload);
}

const PrefixContext = struct {
    prefix: []const u8,
};

fn prefixedRequest(context: ?*anyopaque, allocator: std.mem.Allocator, payload: []const u8) ![]u8 {
    const typed_context: *const PrefixContext = @ptrCast(@alignCast(context.?));
    return std.fmt.allocPrint(allocator, "{s}:{s}", .{ typed_context.prefix, payload });
}

test "request bus supports registration lifecycle" {
    var bus = RequestBus.init(std.testing.allocator);
    defer bus.deinit();

    try bus.register("asset.load", .{
        .call = echoRequest,
    });
    try std.testing.expectError(error.RequestAlreadyRegistered, bus.register("asset.load", .{
        .call = echoRequest,
    }));

    try std.testing.expect(bus.unregister("asset.load"));
    try std.testing.expect(!bus.unregister("asset.load"));
}

test "request bus routes requests through registered handlers" {
    var bus = RequestBus.init(std.testing.allocator);
    defer bus.deinit();

    var context = PrefixContext{ .prefix = "ok" };
    try bus.register("debug.echo", .{
        .context = &context,
        .call = prefixedRequest,
    });

    const response = try bus.request("debug.echo", "ping");
    defer std.testing.allocator.free(response);

    try std.testing.expectEqualStrings("ok:ping", response);
}

test "request bus returns unknown request for missing handlers" {
    var bus = RequestBus.init(std.testing.allocator);
    defer bus.deinit();

    try std.testing.expectError(error.UnknownRequest, bus.request("missing.request", "{}"));
}

test "request bus clear removes all handlers" {
    var bus = RequestBus.init(std.testing.allocator);
    defer bus.deinit();

    try bus.register("first", .{ .call = echoRequest });
    try bus.register("second", .{ .call = echoRequest });
    try std.testing.expectEqual(@as(usize, 2), bus.handlers.items.len);

    bus.clear();

    try std.testing.expectEqual(@as(usize, 0), bus.handlers.items.len);
    try std.testing.expectError(error.UnknownRequest, bus.request("first", "{}"));
}
