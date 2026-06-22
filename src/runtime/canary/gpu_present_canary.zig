const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");

const sdl = shared.sdl;
const gpu = shared.sdl_gpu;
const engine_time = friendly_engine.core.time;

const Options = struct {
    frames: u32 = 180,
    present: PresentMode = .default,
};

const PresentMode = enum {
    default,
    vsync,
    immediate,
    mailbox,
};

const FrameStats = struct {
    wait_acquire_ms: f64 = 0,
    render_pass_ms: f64 = 0,
    submit_ms: f64 = 0,
    frame_ms: f64 = 0,
};

pub fn main(init: std.process.Init) !void {
    var options = Options{};
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--frames")) {
            const value = args.next() orelse return error.MissingFrameCount;
            options.frames = try std.fmt.parseInt(u32, value, 10);
        } else if (std.mem.eql(u8, arg, "--present")) {
            const value = args.next() orelse return error.MissingPresentMode;
            options.present = parsePresentMode(value) orelse return error.InvalidPresentMode;
        } else if (std.mem.eql(u8, arg, "--help")) {
            try printUsage();
            return;
        } else {
            return error.UnknownArgument;
        }
    }

    if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO)) {
        std.debug.print("SDL_Init failed: {s}\n", .{sdl.errorMessage()});
        return error.SdlInitFailed;
    }
    defer sdl.SDL_Quit();

    const window = sdl.SDL_CreateWindow(
        "friendly-engine GPU canary",
        960,
        540,
        sdl.SDL_WINDOW_RESIZABLE | sdl.SDL_WINDOW_HIGH_PIXEL_DENSITY,
    ) orelse {
        std.debug.print("SDL_CreateWindow failed: {s}\n", .{sdl.errorMessage()});
        return error.SdlWindowFailed;
    };
    defer sdl.SDL_DestroyWindow(window);

    const device = gpu.SDL_CreateGPUDevice(gpu.preferredShaderFormats(), true, null) orelse {
        std.debug.print("SDL_CreateGPUDevice failed: {s}\n", .{sdl.errorMessage()});
        return error.GpuDeviceFailed;
    };
    defer gpu.SDL_DestroyGPUDevice(device);

    const gpu_window: *gpu.SDL_Window = @ptrCast(window);
    if (!gpu.SDL_ClaimWindowForGPUDevice(device, gpu_window)) {
        std.debug.print("SDL_ClaimWindowForGPUDevice failed: {s}\n", .{sdl.errorMessage()});
        return error.GpuWindowClaimFailed;
    }
    defer gpu.SDL_ReleaseWindowFromGPUDevice(device, gpu_window);

    const active_format = gpu.activeShaderFormat(device);
    const texture_format = gpu.SDL_GetGPUSwapchainTextureFormat(device, gpu_window);
    const supports_vsync = gpu.SDL_WindowSupportsGPUPresentMode(device, gpu_window, gpu.SDL_GPU_PRESENTMODE_VSYNC);
    const supports_immediate = gpu.SDL_WindowSupportsGPUPresentMode(device, gpu_window, gpu.SDL_GPU_PRESENTMODE_IMMEDIATE);
    const supports_mailbox = gpu.SDL_WindowSupportsGPUPresentMode(device, gpu_window, gpu.SDL_GPU_PRESENTMODE_MAILBOX);

    if (options.present != .default) {
        const mode = presentModeValue(options.present);
        if (!gpu.SDL_SetGPUSwapchainParameters(device, gpu_window, gpu.SDL_GPU_SWAPCHAINCOMPOSITION_SDR, mode)) {
            std.debug.print("SDL_SetGPUSwapchainParameters({s}) failed: {s}\n", .{ @tagName(options.present), sdl.errorMessage() });
            return error.GpuSwapchainParametersFailed;
        }
    }

    std.debug.print(
        "gpu_canary backend={s} texture_format={d} present={s} support(vsync={}, immediate={}, mailbox={}) frames={d}\n",
        .{
            gpu.backendName(active_format),
            texture_format,
            @tagName(options.present),
            supports_vsync,
            supports_immediate,
            supports_mailbox,
            options.frames,
        },
    );

    var totals = FrameStats{};
    var worst = FrameStats{};
    var completed: u32 = 0;

    var event: sdl.SDL_Event = undefined;
    while (completed < options.frames) : (completed += 1) {
        while (sdl.SDL_PollEvent(&event)) {
            if (event.type == sdl.SDL_QUIT) return;
        }

        const frame_start = engine_time.monotonicNs();
        const cmdbuf = gpu.SDL_AcquireGPUCommandBuffer(device) orelse return error.GpuCommandBufferFailed;

        var swapchain_texture: ?*gpu.SDL_GPUTexture = null;
        var swapchain_w: c_uint = 0;
        var swapchain_h: c_uint = 0;

        const acquire_start = engine_time.monotonicNs();
        if (!gpu.SDL_WaitAndAcquireGPUSwapchainTexture(cmdbuf, gpu_window, &swapchain_texture, &swapchain_w, &swapchain_h)) {
            std.debug.print("SDL_WaitAndAcquireGPUSwapchainTexture failed: {s}\n", .{sdl.errorMessage()});
            return error.GpuSwapchainAcquireFailed;
        }
        const acquire_end = engine_time.monotonicNs();

        if (swapchain_texture) |texture| {
            const color = gpu.SDL_GPUColorTargetInfo{
                .texture = texture,
                .mip_level = 0,
                .layer_or_depth_plane = 0,
                .clear_color = .{
                    .r = 0.03,
                    .g = 0.05,
                    .b = 0.09,
                    .a = 1.0,
                },
                .load_op = gpu.SDL_GPU_LOADOP_CLEAR,
                .store_op = gpu.SDL_GPU_STOREOP_STORE,
                .resolve_texture = null,
                .resolve_mip_level = 0,
                .resolve_layer = 0,
                .cycle = false,
                .cycle_resolve_texture = false,
            };
            const pass_start = engine_time.monotonicNs();
            const pass = gpu.SDL_BeginGPURenderPass(cmdbuf, &.{color}, 1, null) orelse return error.GpuRenderPassFailed;
            gpu.SDL_EndGPURenderPass(pass);
            const pass_end = engine_time.monotonicNs();
            totals.render_pass_ms += msBetween(pass_start, pass_end);
            worst.render_pass_ms = @max(worst.render_pass_ms, msBetween(pass_start, pass_end));
        }

        const submit_start = engine_time.monotonicNs();
        if (!gpu.SDL_SubmitGPUCommandBuffer(cmdbuf)) {
            std.debug.print("SDL_SubmitGPUCommandBuffer failed: {s}\n", .{sdl.errorMessage()});
            return error.GpuSubmitFailed;
        }
        const submit_end = engine_time.monotonicNs();
        const frame_end = submit_end;

        const stats = FrameStats{
            .wait_acquire_ms = msBetween(acquire_start, acquire_end),
            .render_pass_ms = 0,
            .submit_ms = msBetween(submit_start, submit_end),
            .frame_ms = msBetween(frame_start, frame_end),
        };
        totals.wait_acquire_ms += stats.wait_acquire_ms;
        totals.submit_ms += stats.submit_ms;
        totals.frame_ms += stats.frame_ms;
        worst.wait_acquire_ms = @max(worst.wait_acquire_ms, stats.wait_acquire_ms);
        worst.submit_ms = @max(worst.submit_ms, stats.submit_ms);
        worst.frame_ms = @max(worst.frame_ms, stats.frame_ms);
    }

    const n: f64 = @floatFromInt(completed);
    std.debug.print(
        "gpu_canary avg frame={d:.3}ms acquire={d:.3}ms render_pass={d:.3}ms submit={d:.3}ms fps={d:.1}\n",
        .{
            totals.frame_ms / n,
            totals.wait_acquire_ms / n,
            totals.render_pass_ms / n,
            totals.submit_ms / n,
            1000.0 / (totals.frame_ms / n),
        },
    );
    std.debug.print(
        "gpu_canary worst frame={d:.3}ms acquire={d:.3}ms render_pass={d:.3}ms submit={d:.3}ms\n",
        .{
            worst.frame_ms,
            worst.wait_acquire_ms,
            worst.render_pass_ms,
            worst.submit_ms,
        },
    );
}

fn parsePresentMode(value: []const u8) ?PresentMode {
    if (std.mem.eql(u8, value, "default")) return .default;
    if (std.mem.eql(u8, value, "vsync")) return .vsync;
    if (std.mem.eql(u8, value, "immediate")) return .immediate;
    if (std.mem.eql(u8, value, "mailbox")) return .mailbox;
    return null;
}

fn presentModeValue(mode: PresentMode) gpu.SDL_GPUPresentMode {
    return switch (mode) {
        .default, .vsync => gpu.SDL_GPU_PRESENTMODE_VSYNC,
        .immediate => gpu.SDL_GPU_PRESENTMODE_IMMEDIATE,
        .mailbox => gpu.SDL_GPU_PRESENTMODE_MAILBOX,
    };
}

fn msBetween(start: i128, end: i128) f64 {
    return @as(f64, @floatFromInt(end - start)) / std.time.ns_per_ms;
}

fn printUsage() !void {
    std.debug.print(
        \\usage: friendly_engine_gpu_canary [--frames n] [--present default|vsync|immediate|mailbox]
        \\
    , .{});
}
