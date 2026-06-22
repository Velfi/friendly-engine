const std = @import("std");
const core = @import("../core/mod.zig");

pub const ActionState = enum(u8) {
    up,
    pressed,
    held,
    released,
};

pub const BackendVTable = struct {
    poll: *const fn (context: *anyopaque, system: *InputSystem) anyerror!void,
};

pub const Backend = struct {
    context: *anyopaque,
    vtable: *const BackendVTable,
};

pub const InputRoute = struct {
    action_id: core.ActionId,
    owner: []const u8,
    priority: i32 = 0,
    captures: bool = true,
};

pub const InputSystem = struct {
    allocator: std.mem.Allocator,
    backend: ?Backend = null,
    actions: std.AutoHashMap(core.ActionId, ActionState),
    routes: std.AutoHashMap(core.ActionId, InputRoute),

    pub fn init(allocator: std.mem.Allocator) InputSystem {
        return .{
            .allocator = allocator,
            .actions = std.AutoHashMap(core.ActionId, ActionState).init(allocator),
            .routes = std.AutoHashMap(core.ActionId, InputRoute).init(allocator),
        };
    }

    pub fn deinit(self: *InputSystem) void {
        self.clearRoutes();
        self.routes.deinit();
        self.actions.deinit();
    }

    pub fn setBackend(self: *InputSystem, backend: Backend) void {
        self.backend = backend;
    }

    pub fn actionId(action_name: []const u8) core.ActionId {
        return core.ids.hashString64(action_name);
    }

    pub fn setActionState(self: *InputSystem, action_id: core.ActionId, state: ActionState) !void {
        try self.actions.put(action_id, state);
    }

    pub fn setActionStateByName(self: *InputSystem, action_name: []const u8, state: ActionState) !void {
        try self.setActionState(actionId(action_name), state);
    }

    pub fn getActionState(self: *const InputSystem, action_id: core.ActionId) ActionState {
        return self.actions.get(action_id) orelse .up;
    }

    pub fn routeActionByName(
        self: *InputSystem,
        action_name: []const u8,
        owner: []const u8,
        priority: i32,
        captures: bool,
    ) !void {
        try self.routeAction(actionId(action_name), owner, priority, captures);
    }

    pub fn routeAction(
        self: *InputSystem,
        action_id: core.ActionId,
        owner: []const u8,
        priority: i32,
        captures: bool,
    ) !void {
        if (self.routes.getPtr(action_id)) |existing| {
            if (existing.priority > priority) return;
            self.allocator.free(existing.owner);
            existing.* = .{
                .action_id = action_id,
                .owner = try self.allocator.dupe(u8, owner),
                .priority = priority,
                .captures = captures,
            };
            return;
        }

        try self.routes.put(action_id, .{
            .action_id = action_id,
            .owner = try self.allocator.dupe(u8, owner),
            .priority = priority,
            .captures = captures,
        });
    }

    pub fn routeOwner(self: *const InputSystem, action_id: core.ActionId) ?[]const u8 {
        const route = self.routes.get(action_id) orelse return null;
        return route.owner;
    }

    pub fn clearRoutesForOwner(self: *InputSystem, owner: []const u8) void {
        var iter = self.routes.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, entry.value_ptr.owner, owner)) {
                self.allocator.free(entry.value_ptr.owner);
                _ = self.routes.remove(entry.key_ptr.*);
            }
        }
    }

    pub fn clearRoutes(self: *InputSystem) void {
        var iter = self.routes.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.owner);
        }
        self.routes.clearRetainingCapacity();
    }

    pub fn poll(self: *InputSystem) !void {
        const backend = self.backend orelse return;
        try backend.vtable.poll(backend.context, self);
    }
};

const InputTestContext = struct {};

fn mockPoll(context: *anyopaque, system: *InputSystem) !void {
    _ = context;
    try system.setActionStateByName("jump", .pressed);
}

const mock_backend_vtable = BackendVTable{
    .poll = mockPoll,
};

test "input system uses backend abstraction" {
    var input = InputSystem.init(std.testing.allocator);
    defer input.deinit();

    var context = InputTestContext{};
    input.setBackend(.{
        .context = &context,
        .vtable = &mock_backend_vtable,
    });
    try input.poll();

    const jump_state = input.getActionState(InputSystem.actionId("jump"));
    try std.testing.expectEqual(.pressed, jump_state);
}

test "input routes track scene ownership by priority" {
    var input = InputSystem.init(std.testing.allocator);
    defer input.deinit();

    try input.routeActionByName("confirm", "gameplay", 10, true);
    try input.routeActionByName("confirm", "pause", 5, true);
    try std.testing.expectEqualStrings("gameplay", input.routeOwner(InputSystem.actionId("confirm")).?);

    try input.routeActionByName("confirm", "pause", 20, true);
    try std.testing.expectEqualStrings("pause", input.routeOwner(InputSystem.actionId("confirm")).?);

    input.clearRoutesForOwner("pause");
    try std.testing.expect(input.routeOwner(InputSystem.actionId("confirm")) == null);
}
