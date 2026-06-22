const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");

pub const std_options: std.Options = .{
    .logFn = friendly_engine.core.logging.logFn,
};

const log = std.log.scoped(.server);

pub fn main(init: std.process.Init) !void {
    run(init) catch |err| {
        log.err("runtime exited with error: {s}", .{@errorName(err)});
        return err;
    };
}

fn run(init: std.process.Init) !void {
    log.info("starting dedicated server runtime", .{});

    const config = friendly_engine.EngineConfig{
        .runtime = .server,
        .enable_renderer = false,
        .enable_audio = false,
    };

    var boot = try friendly_engine.bootstrap.bootWorld(
        std.heap.page_allocator,
        init.io,
        config,
        "engine.kdl",
    );
    defer boot.deinit();
    var world = boot.world;
    friendly_engine.game.setActiveWorld(&world);

    var persistence_backend = try shared.file_persistence.FilePersistenceBackend.init(
        std.heap.page_allocator,
        init.io,
        ".",
    );
    defer persistence_backend.deinit();
    persistence_backend.install(&world);

    for (0..default_max_ticks) |_| {
        try friendly_engine.game.tickServer(&world);
        try world.tick();
    }

    log.info("dedicated server runtime stopped ticks={d}", .{default_max_ticks});
}

const default_max_ticks: usize = 3;
