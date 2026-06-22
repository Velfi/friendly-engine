const std = @import("std");
const sdl_gpu = @import("sdl_gpu.zig");

pub const Antialiasing = enum {
    none,
    msaa2,
    msaa4,
    msaa8,

    pub fn sampleCount(self: Antialiasing) sdl_gpu.SDL_GPUSampleCount {
        return switch (self) {
            .none => sdl_gpu.SDL_GPU_SAMPLECOUNT_1,
            .msaa2 => sdl_gpu.SDL_GPU_SAMPLECOUNT_2,
            .msaa4 => sdl_gpu.SDL_GPU_SAMPLECOUNT_4,
            .msaa8 => sdl_gpu.SDL_GPU_SAMPLECOUNT_8,
        };
    }

    pub fn label(self: Antialiasing) []const u8 {
        return switch (self) {
            .none => "Off",
            .msaa2 => "MSAA 2x",
            .msaa4 => "MSAA 4x",
            .msaa8 => "MSAA 8x",
        };
    }

    pub fn parse(text: []const u8) !Antialiasing {
        if (std.mem.eql(u8, text, "off") or std.mem.eql(u8, text, "none")) return .none;
        if (std.mem.eql(u8, text, "2x") or std.mem.eql(u8, text, "msaa2")) return .msaa2;
        if (std.mem.eql(u8, text, "4x") or std.mem.eql(u8, text, "msaa4")) return .msaa4;
        if (std.mem.eql(u8, text, "8x") or std.mem.eql(u8, text, "msaa8")) return .msaa8;
        return error.InvalidAntialiasing;
    }
};

pub const ShadowQuality = enum {
    off,
    low,
    medium,
    high,

    pub fn mapResolution(self: ShadowQuality) u32 {
        return switch (self) {
            .off => 0,
            .low => 512,
            .medium => 1024,
            .high => 2048,
        };
    }

    pub fn label(self: ShadowQuality) []const u8 {
        return switch (self) {
            .off => "Off",
            .low => "Low",
            .medium => "Medium",
            .high => "High",
        };
    }

    pub fn parse(text: []const u8) !ShadowQuality {
        if (std.mem.eql(u8, text, "off") or std.mem.eql(u8, text, "none")) return .off;
        if (std.mem.eql(u8, text, "low")) return .low;
        if (std.mem.eql(u8, text, "medium")) return .medium;
        if (std.mem.eql(u8, text, "high")) return .high;
        return error.InvalidShadowQuality;
    }
};

pub const ColorPipeline = enum {
    sdr_direct,
    hdr_aces_auto_exposure,

    pub fn label(self: ColorPipeline) []const u8 {
        return switch (self) {
            .sdr_direct => "SDR Direct",
            .hdr_aces_auto_exposure => "HDR ACES Auto Exposure",
        };
    }

    pub fn hdrEnabled(self: ColorPipeline) bool {
        return self == .hdr_aces_auto_exposure;
    }

    pub fn parse(text: []const u8) !ColorPipeline {
        if (std.mem.eql(u8, text, "sdr") or std.mem.eql(u8, text, "sdr_direct") or std.mem.eql(u8, text, "direct")) return .sdr_direct;
        if (std.mem.eql(u8, text, "hdr") or std.mem.eql(u8, text, "aces") or std.mem.eql(u8, text, "hdr_aces") or std.mem.eql(u8, text, "hdr_aces_auto_exposure")) return .hdr_aces_auto_exposure;
        return error.InvalidColorPipeline;
    }
};

pub const RenderSettings = struct {
    antialiasing: Antialiasing = .msaa4,
    shadows: ShadowQuality = .medium,
    color_pipeline: ColorPipeline = .hdr_aces_auto_exposure,

    pub fn sampleCount(self: RenderSettings) sdl_gpu.SDL_GPUSampleCount {
        return self.antialiasing.sampleCount();
    }

    pub fn shadowsEnabled(self: RenderSettings) bool {
        return self.shadows != .off;
    }

    pub fn hdrEnabled(self: RenderSettings) bool {
        return self.color_pipeline.hdrEnabled();
    }

    pub fn parseOverrides(self: *RenderSettings, text: []const u8) !void {
        if (text.len == 0) return error.EmptyRenderSettings;

        var pairs = std.mem.splitScalar(u8, text, ',');
        while (pairs.next()) |raw_pair| {
            const pair = std.mem.trim(u8, raw_pair, " \t\r\n");
            if (pair.len == 0) return error.EmptyRenderSettingsEntry;

            const eq = std.mem.indexOfScalar(u8, pair, '=') orelse return error.InvalidRenderSettingsEntry;
            const key = std.mem.trim(u8, pair[0..eq], " \t\r\n");
            const value = std.mem.trim(u8, pair[eq + 1 ..], " \t\r\n");
            if (key.len == 0 or value.len == 0) return error.InvalidRenderSettingsEntry;

            if (std.mem.eql(u8, key, "antialiasing") or std.mem.eql(u8, key, "aa")) {
                self.antialiasing = try Antialiasing.parse(value);
                continue;
            }
            if (std.mem.eql(u8, key, "shadows")) {
                self.shadows = try ShadowQuality.parse(value);
                continue;
            }
            if (std.mem.eql(u8, key, "color_pipeline") or std.mem.eql(u8, key, "color") or std.mem.eql(u8, key, "hdr")) {
                self.color_pipeline = try ColorPipeline.parse(value);
                continue;
            }
            return error.UnknownRenderSetting;
        }
    }
};

test "render settings map antialiasing to SDL sample counts" {
    try std.testing.expectEqual(@as(sdl_gpu.SDL_GPUSampleCount, sdl_gpu.SDL_GPU_SAMPLECOUNT_1), Antialiasing.none.sampleCount());
    try std.testing.expectEqual(@as(sdl_gpu.SDL_GPUSampleCount, sdl_gpu.SDL_GPU_SAMPLECOUNT_4), Antialiasing.msaa4.sampleCount());
    try std.testing.expectEqual(Antialiasing.msaa8, try Antialiasing.parse("8x"));
}

test "render settings parse extensible key value overrides" {
    var settings = RenderSettings{};
    try settings.parseOverrides("antialiasing=off");
    try std.testing.expectEqual(Antialiasing.none, settings.antialiasing);

    try settings.parseOverrides("aa=2x");
    try std.testing.expectEqual(Antialiasing.msaa2, settings.antialiasing);

    try settings.parseOverrides("shadows=high");
    try std.testing.expectEqual(ShadowQuality.high, settings.shadows);
    try std.testing.expectEqual(@as(u32, 2048), settings.shadows.mapResolution());

    try settings.parseOverrides("color=sdr");
    try std.testing.expectEqual(ColorPipeline.sdr_direct, settings.color_pipeline);

    try settings.parseOverrides("hdr=hdr_aces_auto_exposure");
    try std.testing.expectEqual(ColorPipeline.hdr_aces_auto_exposure, settings.color_pipeline);
}
