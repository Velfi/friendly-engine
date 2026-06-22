const std = @import("std");
const core = @import("../core/mod.zig");

pub const PlaySound = struct {
    sound_asset: core.AssetId,
    volume: f32 = 1.0,
    loop: bool = false,
};

pub const AudioCommand = union(enum) {
    play_sound: PlaySound,
    stop_all,
};

pub const BackendVTable = struct {
    submit: *const fn (context: *anyopaque, command: AudioCommand) anyerror!void,
};

pub const Backend = struct {
    context: *anyopaque,
    vtable: *const BackendVTable,
};

pub const AudioSystem = struct {
    allocator: std.mem.Allocator,
    backend: ?Backend = null,
    commands: std.ArrayList(AudioCommand),

    pub fn init(allocator: std.mem.Allocator) AudioSystem {
        return .{
            .allocator = allocator,
            .commands = .empty,
        };
    }

    pub fn deinit(self: *AudioSystem) void {
        self.commands.deinit(self.allocator);
    }

    pub fn setBackend(self: *AudioSystem, backend: Backend) void {
        self.backend = backend;
    }

    pub fn playSound(self: *AudioSystem, sound_asset: core.AssetId, volume: f32) !void {
        try self.commands.append(self.allocator, .{
            .play_sound = .{
                .sound_asset = sound_asset,
                .volume = volume,
            },
        });
    }

    pub fn stopAll(self: *AudioSystem) !void {
        try self.commands.append(self.allocator, .stop_all);
    }

    pub fn flush(self: *AudioSystem) !void {
        if (self.commands.items.len == 0) return;
        const backend = self.backend orelse return error.AudioBackendMissing;
        for (self.commands.items) |command| {
            try backend.vtable.submit(backend.context, command);
        }
        self.commands.clearRetainingCapacity();
    }

    pub fn pendingCount(self: *const AudioSystem) usize {
        return self.commands.items.len;
    }
};

const AudioTestContext = struct {
    submitted_count: usize = 0,
};

fn mockSubmit(context: *anyopaque, command: AudioCommand) !void {
    _ = command;
    const typed_context: *AudioTestContext = @ptrCast(@alignCast(context));
    typed_context.submitted_count += 1;
}

const mock_backend_vtable = BackendVTable{
    .submit = mockSubmit,
};

test "audio system fails loudly without playback backend" {
    var audio = AudioSystem.init(std.testing.allocator);
    defer audio.deinit();

    try audio.playSound(42, 0.75);
    try std.testing.expectError(error.AudioBackendMissing, audio.flush());
    try std.testing.expectEqual(@as(usize, 1), audio.pendingCount());
}

test "audio system submits queued commands" {
    var audio = AudioSystem.init(std.testing.allocator);
    defer audio.deinit();

    var context = AudioTestContext{};
    audio.setBackend(.{
        .context = &context,
        .vtable = &mock_backend_vtable,
    });
    try audio.playSound(7, 1.0);
    try audio.stopAll();
    try audio.flush();

    try std.testing.expectEqual(@as(usize, 2), context.submitted_count);
    try std.testing.expectEqual(@as(usize, 0), audio.pendingCount());
}
