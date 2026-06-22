const std = @import("std");
const cell = @import("cell.zig");
const fcell = @import("fcell.zig");

const max_cell_bytes = 64 * 1024 * 1024;
const log = std.log.scoped(.world_file_io);

pub const SyncCellFileIo = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []u8,
    target: []u8,
    world_id: []u8,

    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        project_path: []const u8,
        target: []const u8,
        world_id: []const u8,
    ) !SyncCellFileIo {
        return .{
            .allocator = allocator,
            .io = io,
            .project_path = try allocator.dupe(u8, project_path),
            .target = try allocator.dupe(u8, target),
            .world_id = try allocator.dupe(u8, world_id),
        };
    }

    pub fn deinit(self: *SyncCellFileIo) void {
        self.allocator.free(self.world_id);
        self.allocator.free(self.target);
        self.allocator.free(self.project_path);
    }

    pub fn readCell(self: *const SyncCellFileIo, id: cell.CellId) !cell.WorldCellData {
        return self.readCellWithAllocator(self.allocator, id);
    }

    pub fn readCellWithAllocator(
        self: *const SyncCellFileIo,
        data_allocator: std.mem.Allocator,
        id: cell.CellId,
    ) !cell.WorldCellData {
        var project_dir = try openProjectDir(self.io, self.project_path);
        defer project_dir.close(self.io);

        const baked_path = try fcell.bakedCellPath(data_allocator, self.target, self.world_id, id);
        defer data_allocator.free(baked_path);

        const bytes = project_dir.readFileAlloc(self.io, baked_path, data_allocator, .limited(max_cell_bytes)) catch |err| {
            switch (err) {
                error.FileNotFound => log.err(
                    "missing baked world cell: project={s} target={s} world={s} cell={d},{d},{d} path={s}. Run `zig build run-tools -- world-bake --project {s} --world world.kdl --target {s} --cell {d},{d},{d}` or use the editor's Recompile Cells command before Play.",
                    .{
                        self.project_path,
                        self.target,
                        self.world_id,
                        id.x,
                        id.y,
                        id.z,
                        baked_path,
                        self.project_path,
                        self.target,
                        id.x,
                        id.y,
                        id.z,
                    },
                ),
                else => log.err(
                    "failed to read baked world cell: project={s} target={s} world={s} cell={d},{d},{d} path={s} err={s}",
                    .{
                        self.project_path,
                        self.target,
                        self.world_id,
                        id.x,
                        id.y,
                        id.z,
                        baked_path,
                        @errorName(err),
                    },
                ),
            }
            return err;
        };
        defer data_allocator.free(bytes);
        return fcell.decodeCell(data_allocator, bytes) catch |err| {
            log.err(
                "failed to decode baked world cell: project={s} target={s} world={s} cell={d},{d},{d} path={s} err={s}. Re-run world bake for this cell.",
                .{
                    self.project_path,
                    self.target,
                    self.world_id,
                    id.x,
                    id.y,
                    id.z,
                    baked_path,
                    @errorName(err),
                },
            );
            return err;
        };
    }

    pub fn writeCell(self: *const SyncCellFileIo, world_cell: cell.WorldCellData) !void {
        var project_dir = try openProjectDir(self.io, self.project_path);
        defer project_dir.close(self.io);

        const encoded = try fcell.encodeCell(self.allocator, world_cell);
        defer self.allocator.free(encoded);

        const baked_path = try fcell.bakedCellPath(self.allocator, self.target, self.world_id, world_cell.id);
        defer self.allocator.free(baked_path);

        if (std.fs.path.dirname(baked_path)) |parent| {
            try project_dir.createDirPath(self.io, parent);
        }
        try project_dir.writeFile(self.io, .{
            .sub_path = baked_path,
            .data = encoded,
        });
    }
};

fn openProjectDir(io: std.Io, project_path: []const u8) !std.Io.Dir {
    if (std.fs.path.isAbsolute(project_path)) {
        return try std.Io.Dir.openDirAbsolute(io, project_path, .{});
    }
    return try std.Io.Dir.cwd().openDir(io, project_path, .{});
}

test "sync cell file io writes and reads baked cells" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);

    var cell_io = try SyncCellFileIo.init(std.testing.allocator, std.testing.io, project_path, "client-debug", "main");
    defer cell_io.deinit();

    var source = try makeTestCell(.{ .x = 2, .y = -1, .z = 0 }, 1.25);
    defer source.deinit(std.testing.allocator);
    try cell_io.writeCell(source);

    var loaded = try cell_io.readCell(source.id);
    defer loaded.deinit(std.testing.allocator);
    try std.testing.expect(source.id.eql(loaded.id));
    try std.testing.expectEqual(@as(f32, 1.25), loaded.light_probes[0].intensity);
}

test "sync cell file io fails loudly when baked cell is missing" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const project_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_path);

    var cell_io = try SyncCellFileIo.init(std.testing.allocator, std.testing.io, project_path, "client-debug", "main");
    defer cell_io.deinit();

    try std.testing.expectError(
        error.FileNotFound,
        cell_io.readCell(.{ .x = 99, .y = 0, .z = 0 }),
    );
}

fn makeTestCell(id: cell.CellId, intensity: f32) !cell.WorldCellData {
    return .{
        .id = id,
        .cell_size_m = 256,
        .render_meshes = try std.testing.allocator.alloc(cell.RenderMesh, 0),
        .collisions = try std.testing.allocator.alloc(cell.CollisionPlaceholder, 0),
        .instances = try std.testing.allocator.alloc(cell.InstanceRecord, 0),
        .light_probes = try std.testing.allocator.dupe(cell.LightProbeMeta, &.{.{
            .position = .{ .x = 0, .y = 2, .z = 0 },
            .intensity = intensity,
        }}),
        .neighbors = try std.testing.allocator.alloc(cell.CellId, 0),
        .blobs = try std.testing.allocator.alloc(cell.CellBlob, 0),
    };
}
