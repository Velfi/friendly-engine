const std = @import("std");
const core = @import("../core/mod.zig");

pub const SceneFn = *const fn (context: *anyopaque) anyerror!void;

pub const SceneCallbacks = struct {
    on_enter: ?SceneFn = null,
    on_exit: ?SceneFn = null,
    on_update: ?SceneFn = null,
};

pub const SceneDesc = struct {
    name: []const u8,
    callbacks: SceneCallbacks = .{},
};

pub const Scene = struct {
    id: core.SceneId,
    name: []const u8,
    callbacks: SceneCallbacks,
};

pub const SceneManager = struct {
    allocator: std.mem.Allocator,
    id_generator: core.IdGenerator,
    scenes: std.ArrayList(Scene),
    active_index: ?usize = null,

    pub fn init(allocator: std.mem.Allocator) SceneManager {
        return .{
            .allocator = allocator,
            .id_generator = core.IdGenerator.init(1),
            .scenes = .empty,
        };
    }

    pub fn deinit(self: *SceneManager) void {
        for (self.scenes.items) |scene_item| {
            self.allocator.free(scene_item.name);
        }
        self.scenes.deinit(self.allocator);
    }

    pub fn registerScene(self: *SceneManager, desc: SceneDesc) !core.SceneId {
        const scene_id: core.SceneId = self.id_generator.nextId();
        try self.scenes.append(self.allocator, .{
            .id = scene_id,
            .name = try self.allocator.dupe(u8, desc.name),
            .callbacks = desc.callbacks,
        });
        return scene_id;
    }

    pub fn activate(self: *SceneManager, scene_id: core.SceneId, context: *anyopaque) !void {
        const next_index = self.findSceneIndex(scene_id) orelse return error.SceneNotFound;
        if (self.active_index) |current_index| {
            if (current_index == next_index) return;
            if (self.scenes.items[current_index].callbacks.on_exit) |on_exit| {
                try on_exit(context);
            }
        }

        self.active_index = next_index;
        if (self.scenes.items[next_index].callbacks.on_enter) |on_enter| {
            try on_enter(context);
        }
    }

    pub fn updateActive(self: *SceneManager, context: *anyopaque) !void {
        const active_index = self.active_index orelse return;
        if (self.scenes.items[active_index].callbacks.on_update) |on_update| {
            try on_update(context);
        }
    }

    pub fn activeSceneId(self: *const SceneManager) ?core.SceneId {
        const active_index = self.active_index orelse return null;
        return self.scenes.items[active_index].id;
    }

    fn findSceneIndex(self: *const SceneManager, scene_id: core.SceneId) ?usize {
        for (self.scenes.items, 0..) |scene_item, idx| {
            if (scene_item.id == scene_id) return idx;
        }
        return null;
    }
};

const SceneLifecycleTestContext = struct {
    enter_count: usize = 0,
    exit_count: usize = 0,
    update_count: usize = 0,
};

fn onEnter(context: *anyopaque) !void {
    const typed_context: *SceneLifecycleTestContext = @ptrCast(@alignCast(context));
    typed_context.enter_count += 1;
}

fn onExit(context: *anyopaque) !void {
    const typed_context: *SceneLifecycleTestContext = @ptrCast(@alignCast(context));
    typed_context.exit_count += 1;
}

fn onUpdate(context: *anyopaque) !void {
    const typed_context: *SceneLifecycleTestContext = @ptrCast(@alignCast(context));
    typed_context.update_count += 1;
}

test "scene manager activates and updates scene lifecycle" {
    var manager = SceneManager.init(std.testing.allocator);
    defer manager.deinit();

    var context = SceneLifecycleTestContext{};
    const scene_a = try manager.registerScene(.{
        .name = "scene_a",
        .callbacks = .{
            .on_enter = onEnter,
            .on_exit = onExit,
            .on_update = onUpdate,
        },
    });
    const scene_b = try manager.registerScene(.{
        .name = "scene_b",
    });

    try manager.activate(scene_a, &context);
    try manager.updateActive(&context);
    try manager.activate(scene_b, &context);

    try std.testing.expectEqual(@as(usize, 1), context.enter_count);
    try std.testing.expectEqual(@as(usize, 1), context.update_count);
    try std.testing.expectEqual(@as(usize, 1), context.exit_count);
}
