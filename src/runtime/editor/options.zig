const std = @import("std");
const shared = @import("runtime_shared");
const editor_viewport_gpu = @import("editor_viewport_gpu.zig");

const log = std.log.scoped(.editor);

pub const EditorRunOptions = struct {
    frame_limit: ?u64 = null,
    help: bool = false,
    open_current: bool = false,
    render_mode: editor_viewport_gpu.RenderMode = .gpu,
    render_settings: shared.gpu_api.RenderSettings = .{},
};

pub fn parseOptions(args: std.process.Args, allocator: std.mem.Allocator) !EditorRunOptions {
    var arg_it = try args.iterateAllocator(allocator);
    defer arg_it.deinit();

    _ = arg_it.next();
    var options = EditorRunOptions{};
    while (arg_it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            options.help = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--gpu")) {
            options.render_mode = .gpu;
            continue;
        }
        if (std.mem.eql(u8, arg, "--software")) {
            options.render_mode = .software;
            continue;
        }
        if (std.mem.eql(u8, arg, "--render-settings")) {
            const next_arg = arg_it.next() orelse return error.MissingRenderSettingsValue;
            try options.render_settings.parseOverrides(next_arg);
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--render-settings=")) {
            try options.render_settings.parseOverrides(arg["--render-settings=".len..]);
            continue;
        }
        if (std.mem.eql(u8, arg, "--open-current")) {
            options.open_current = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--frames")) {
            const next_arg = arg_it.next() orelse return error.MissingFramesValue;
            options.frame_limit = try std.fmt.parseUnsigned(u64, next_arg, 10);
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--frames=")) {
            options.frame_limit = try std.fmt.parseUnsigned(u64, arg["--frames=".len..], 10);
            continue;
        }

        log.err("unknown argument: {s}", .{arg});
        return error.UnknownArgument;
    }

    return options;
}
