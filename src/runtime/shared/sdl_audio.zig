const std = @import("std");
const friendly_engine = @import("friendly_engine");
const framework = friendly_engine.framework;
const audio_decode = @import("audio_decode.zig");
const sdl = @import("sdl.zig");

pub const SdlAudioBackend = struct {
    allocator: std.mem.Allocator,
    assets: ?*framework.assets.AssetSystem = null,
    stream: ?*sdl.SDL_AudioStream = null,
    submitted_commands: usize = 0,

    pub fn init(allocator: std.mem.Allocator) SdlAudioBackend {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SdlAudioBackend) void {
        if (self.stream) |stream| {
            sdl.SDL_DestroyAudioStream(stream);
            self.stream = null;
        }
    }

    pub fn install(self: *SdlAudioBackend, world: *framework.World) void {
        self.assets = &world.assets;
        world.audio.setBackend(.{
            .context = self,
            .vtable = &backend_vtable,
        });
    }

    fn submit(context: *anyopaque, command: framework.audio.AudioCommand) !void {
        const self: *SdlAudioBackend = @ptrCast(@alignCast(context));
        switch (command) {
            .play_sound => |play| try self.playSound(play),
            .stop_all => return error.AudioStopAllUnsupported,
        }
        self.submitted_commands += 1;
    }

    fn playSound(self: *SdlAudioBackend, play: framework.audio.PlaySound) !void {
        const assets = self.assets orelse return error.AudioAssetsMissing;
        const record = assets.get(play.sound_asset) orelse return error.AudioAssetMissing;
        if (!isSupportedPath(record.path)) return error.UnsupportedAudioFormat;

        if (!sdl.SDL_InitSubSystem(sdl.SDL_INIT_AUDIO)) return error.SdlAudioInitFailed;

        const path_z = try self.allocator.dupeZ(u8, record.path);
        defer self.allocator.free(path_z);
        var decoded = try audio_decode.decodeFile(path_z);
        defer decoded.deinit();

        const spec = sdl.SDL_AudioSpec{
            .format = sdl.SDL_AUDIO_F32,
            .channels = @intCast(decoded.channels()),
            .freq = @intCast(decoded.sampleRate()),
        };

        if (self.stream == null) {
            const stream = sdl.SDL_OpenAudioDeviceStream(
                sdl.SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK,
                &spec,
                null,
                null,
            ) orelse return error.SdlAudioDeviceOpenFailed;
            self.stream = stream;
            if (!sdl.SDL_ResumeAudioStreamDevice(stream)) return error.SdlAudioResumeFailed;
        }

        const volume = @max(0.0, play.volume);
        if (volume == 0.0) return;
        if (decoded.byteCount() > std.math.maxInt(c_int)) return error.AudioBufferTooLarge;
        if (!sdl.SDL_PutAudioStreamData(self.stream.?, decoded.samples().ptr, @intCast(decoded.byteCount()))) {
            return error.SdlAudioQueueFailed;
        }
    }
};

const backend_vtable = framework.audio.BackendVTable{
    .submit = SdlAudioBackend.submit,
};

fn isSupportedPath(path: []const u8) bool {
    return std.ascii.endsWithIgnoreCase(path, ".wav") or
        std.ascii.endsWithIgnoreCase(path, ".wave") or
        std.ascii.endsWithIgnoreCase(path, ".mp3") or
        std.ascii.endsWithIgnoreCase(path, ".flac") or
        std.ascii.endsWithIgnoreCase(path, ".ogg");
}

test "sdl audio backend rejects unsupported formats before touching SDL" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();
    var backend = SdlAudioBackend.init(std.testing.allocator);
    backend.install(&world);

    const asset = try world.assets.register("audio", "assets/audio/music.aac");
    try world.audio.playSound(asset, 1.0);
    try std.testing.expectError(error.UnsupportedAudioFormat, world.audio.flush());
}

test "sdl audio backend installs into audio system" {
    var world = framework.World.init(std.testing.allocator);
    defer world.deinit();
    var backend = SdlAudioBackend.init(std.testing.allocator);
    backend.install(&world);
    try std.testing.expect(world.audio.backend != null);
}
