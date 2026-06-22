const std = @import("std");

const c = @cImport({
    @cInclude("fe_audio_decode.h");
});

pub const DecodedAudio = struct {
    raw: c.FeDecodedAudio,

    pub fn deinit(self: *DecodedAudio) void {
        c.fe_audio_decoded_free(&self.raw);
    }

    pub fn samples(self: *const DecodedAudio) []const f32 {
        const len = self.sampleCount();
        return self.raw.samples[0..len];
    }

    pub fn sampleCount(self: *const DecodedAudio) usize {
        return @intCast(self.raw.frame_count * self.raw.channels);
    }

    pub fn byteCount(self: *const DecodedAudio) usize {
        return self.sampleCount() * @sizeOf(f32);
    }

    pub fn channels(self: *const DecodedAudio) u32 {
        return @intCast(self.raw.channels);
    }

    pub fn sampleRate(self: *const DecodedAudio) u32 {
        return @intCast(self.raw.sample_rate);
    }
};

pub fn decodeFile(path: [:0]const u8) !DecodedAudio {
    var raw: c.FeDecodedAudio = undefined;
    const result = c.fe_audio_decode_file(path.ptr, &raw);
    if (result != 0) return error.AudioDecodeFailed;
    if (raw.samples == null or raw.frame_count == 0 or raw.channels == 0 or raw.sample_rate == 0) {
        c.fe_audio_decoded_free(&raw);
        return error.AudioDecodeFailed;
    }
    return .{ .raw = raw };
}
