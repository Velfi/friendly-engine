const std = @import("std");

pub const FrameToneMapping = extern struct {
    exposure: f32 = 1.0,
    min_exposure: f32 = 0.2,
    max_exposure: f32 = 8.0,
    enabled: u32 = 1,
};

pub const ExposureState = struct {
    current: f32 = 1.0,
    min: f32 = 0.2,
    max: f32 = 8.0,
    last_update_ns: i128 = 0,

    pub fn uniforms(self: ExposureState, enabled: bool) FrameToneMapping {
        return .{
            .exposure = self.current,
            .min_exposure = self.min,
            .max_exposure = self.max,
            .enabled = if (enabled) 1 else 0,
        };
    }

    pub fn updateFromAverageLogLuminance(self: *ExposureState, avg_log_luma: f32, now_ns: i128) void {
        const luma = luminanceFromAverageLog(avg_log_luma);
        const target = targetExposure(luma, self.min, self.max);
        const dt = if (self.last_update_ns == 0)
            1.0 / 60.0
        else
            @max(0.0, @as(f32, @floatFromInt(now_ns - self.last_update_ns)) / 1_000_000_000.0);
        self.current = smoothExposure(self.current, target, dt);
        self.last_update_ns = now_ns;
    }
};

pub fn acesFittedScalar(x: f32) f32 {
    const a: f32 = 2.51;
    const b: f32 = 0.03;
    const c: f32 = 2.43;
    const d: f32 = 0.59;
    const e: f32 = 0.14;
    const mapped = (x * (a * x + b)) / (x * (c * x + d) + e);
    return std.math.clamp(mapped, 0.0, 1.0);
}

pub fn luminanceFromAverageLog(avg_log_luma: f32) f32 {
    if (!std.math.isFinite(avg_log_luma)) return 0.0001;
    return @max(0.0001, std.math.pow(f32, 2.0, avg_log_luma));
}

pub fn targetExposure(luma: f32, min_exposure: f32, max_exposure: f32) f32 {
    const safe_luma = @max(luma, 0.0001);
    const target = 0.18 / safe_luma;
    return std.math.clamp(target, min_exposure, max_exposure);
}

pub fn smoothExposure(current: f32, target: f32, dt_seconds: f32) f32 {
    if (!std.math.isFinite(current)) return target;
    if (!std.math.isFinite(target)) return current;
    if (dt_seconds <= 0.0) return current;
    const tau: f32 = if (target > current) 0.8 else 0.25;
    const alpha = 1.0 - std.math.exp(-dt_seconds / tau);
    const next = current + (target - current) * std.math.clamp(alpha, 0.0, 1.0);
    return if (target > current) @min(next, target) else @max(next, target);
}

test "ACES fitted helper is monotonic finite and bounded" {
    var last: f32 = acesFittedScalar(0.0);
    try std.testing.expectEqual(@as(f32, 0.0), last);
    const values = [_]f32{ 0.01, 0.1, 0.5, 1.0, 2.0, 8.0, 32.0 };
    for (values) |value| {
        const mapped = acesFittedScalar(value);
        try std.testing.expect(std.math.isFinite(mapped));
        try std.testing.expect(mapped >= 0.0 and mapped <= 1.0);
        try std.testing.expect(mapped >= last);
        last = mapped;
    }
}

test "exposure target handles luminance clamp bounds" {
    try std.testing.expectEqual(@as(f32, 8.0), targetExposure(0.0, 0.2, 8.0));
    try std.testing.expectEqual(@as(f32, 8.0), targetExposure(0.00001, 0.2, 8.0));
    try std.testing.expectEqual(@as(f32, 0.2), targetExposure(10.0, 0.2, 8.0));
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), targetExposure(0.18, 0.2, 8.0), 0.0001);
}

test "exposure smoothing moves without overshoot" {
    const brighter = smoothExposure(1.0, 4.0, 0.1);
    try std.testing.expect(brighter > 1.0 and brighter < 4.0);

    const darker = smoothExposure(4.0, 1.0, 0.1);
    try std.testing.expect(darker < 4.0 and darker > 1.0);

    try std.testing.expectEqual(@as(f32, 2.0), smoothExposure(2.0, 8.0, 0.0));
}
