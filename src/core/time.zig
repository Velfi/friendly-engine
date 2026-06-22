const std = @import("std");
const builtin = @import("builtin");
const c = std.c;

pub const SecondsF64 = f64;

pub fn monotonicNs() i128 {
    if (builtin.os.tag == .windows) {
        const kernel32 = std.os.windows.kernel32;
        var count: i64 = undefined;
        _ = kernel32.QueryPerformanceCounter(&count);
        const freq = windowsPerformanceFrequency();
        return @divFloor(@as(i128, count) * std.time.ns_per_s, freq);
    }
    var ts: c.timespec = undefined;
    _ = c.clock_gettime(c.CLOCK.MONOTONIC, &ts);
    return @as(i128, ts.sec) * std.time.ns_per_s + @as(i128, ts.nsec);
}

fn windowsPerformanceFrequency() i64 {
    const kernel32 = std.os.windows.kernel32;
    var freq: i64 = undefined;
    _ = kernel32.QueryPerformanceFrequency(&freq);
    return freq;
}

pub const Stopwatch = struct {
    start_ns: i128,

    pub fn start() Stopwatch {
        return .{ .start_ns = monotonicNs() };
    }

    pub fn restart(self: *Stopwatch) void {
        self.start_ns = monotonicNs();
    }

    pub fn elapsedNs(self: *const Stopwatch) u64 {
        const now_ns = monotonicNs();
        const delta = now_ns - self.start_ns;
        if (delta <= 0) return 0;
        return @as(u64, @intCast(delta));
    }

    pub fn elapsedSeconds(self: *const Stopwatch) SecondsF64 {
        return @as(SecondsF64, @floatFromInt(self.elapsedNs())) / std.time.ns_per_s;
    }
};

pub const FrameClock = struct {
    last_tick_ns: i128,
    delta_seconds: SecondsF64 = 0,
    total_seconds: SecondsF64 = 0,

    pub fn init() FrameClock {
        return .{
            .last_tick_ns = monotonicNs(),
        };
    }

    pub fn tick(self: *FrameClock) void {
        const now_ns = monotonicNs();
        const delta_ns = now_ns - self.last_tick_ns;
        self.last_tick_ns = now_ns;

        if (delta_ns <= 0) {
            self.delta_seconds = 0;
            return;
        }

        self.delta_seconds = @as(SecondsF64, @floatFromInt(delta_ns)) / std.time.ns_per_s;
        self.total_seconds += self.delta_seconds;
    }
};

pub const FixedStep = struct {
    step_seconds: SecondsF64,
    accumulator: SecondsF64 = 0,

    pub fn init(step_seconds: SecondsF64) FixedStep {
        return .{ .step_seconds = step_seconds };
    }

    pub fn pushDelta(self: *FixedStep, delta_seconds: SecondsF64) u32 {
        self.accumulator += delta_seconds;

        var ticks: u32 = 0;
        while (self.accumulator >= self.step_seconds) {
            self.accumulator -= self.step_seconds;
            ticks += 1;
        }
        return ticks;
    }
};

test "stopwatch starts and reports elapsed" {
    var watch = Stopwatch.start();
    const elapsed_ns = watch.elapsedNs();
    try std.testing.expect(elapsed_ns >= 0);
    watch.restart();
}

test "fixed step emits simulation ticks" {
    var fixed = FixedStep.init(1.0 / 60.0);
    const ticks = fixed.pushDelta(1.0 / 30.0);
    try std.testing.expectEqual(@as(u32, 2), ticks);
}
