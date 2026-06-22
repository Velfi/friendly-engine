const std = @import("std");
const friendly_engine = @import("friendly_engine");

const terrain_authoring = friendly_engine.modules.terrain.authoring;
const world = friendly_engine.world;

const TerrainCliOptions = struct {
    project_path: []const u8 = ".",
    world_path: []const u8 = "world.kdl",
    target: []const u8 = "client-debug",
    cell: ?world.cell.CellId = null,
};

pub fn runCli(allocator: std.mem.Allocator, io: std.Io, args: []const []const u8) !void {
    if (args.len == 0) return error.InvalidArguments;

    const command = args[0];
    var options = TerrainCliOptions{};
    try parseOptions(&options, args[1..]);

    if (std.mem.eql(u8, command, "validate")) {
        const report = try terrain_authoring.validateSeamsFile(
            allocator,
            io,
            options.project_path,
            options.world_path,
        );
        printReport(report);
        if (report.incompatible_seams > 0 or report.mismatched_seams > 0) return error.InvalidTerrainSeams;
        return;
    }

    if (std.mem.eql(u8, command, "color-sample")) {
        try colorSample(allocator, io, options);
        return;
    }

    return error.InvalidArguments;
}

fn parseOptions(options: *TerrainCliOptions, args: []const []const u8) !void {
    var i: usize = 0;
    while (i < args.len) {
        const flag = args[i];
        i += 1;
        if (i >= args.len) return error.InvalidArguments;
        const value = args[i];
        i += 1;

        if (std.mem.eql(u8, flag, "--project")) {
            options.project_path = value;
        } else if (std.mem.eql(u8, flag, "--world")) {
            options.world_path = value;
        } else if (std.mem.eql(u8, flag, "--target")) {
            options.target = value;
        } else if (std.mem.eql(u8, flag, "--cell")) {
            options.cell = try parseCellArg(value);
        } else {
            return error.InvalidArguments;
        }
    }
}

fn printReport(report: terrain_authoring.SeamValidationReport) void {
    std.debug.print(
        "terrain validate: seams={d} incompatible={d} mismatched={d} max_delta={d:.6}\n",
        .{ report.seam_count, report.incompatible_seams, report.mismatched_seams, report.max_delta },
    );
}

const SamplePoint = struct {
    name: []const u8,
    u: f32,
    v: f32,
};

const sample_points = [_]SamplePoint{
    .{ .name = "center", .u = 0.50, .v = 0.50 },
    .{ .name = "north_mid", .u = 0.50, .v = 0.15 },
    .{ .name = "south_mid", .u = 0.50, .v = 0.85 },
    .{ .name = "west_mid", .u = 0.15, .v = 0.50 },
    .{ .name = "east_mid", .u = 0.85, .v = 0.50 },
    .{ .name = "nw_quarter", .u = 0.25, .v = 0.25 },
    .{ .name = "se_quarter", .u = 0.75, .v = 0.75 },
};

fn colorSample(allocator: std.mem.Allocator, io: std.Io, options: TerrainCliOptions) !void {
    const id = options.cell orelse return error.InvalidArguments;
    var loaded_manifest = try world.manifest.loadManifest(allocator, io, options.project_path, options.world_path);
    defer loaded_manifest.deinit();

    var cell_io = try world.file_io.SyncCellFileIo.init(
        allocator,
        io,
        options.project_path,
        options.target,
        loaded_manifest.world_id,
    );
    defer cell_io.deinit();

    var world_cell = try cell_io.readCell(id);
    defer world_cell.deinit(allocator);

    std.debug.print(
        "terrain color-sample: cell={d},{d},{d} world={s} target={s}\n",
        .{ id.x, id.y, id.z, loaded_manifest.world_id, options.target },
    );

    for (sample_points) |point| {
        std.debug.print("  sample {s} uv={d:.3},{d:.3}\n", .{ point.name, point.u, point.v });
        var first: ?[4]u8 = null;
        var same = true;
        for (world_cell.render_meshes) |mesh| {
            if (!std.mem.startsWith(u8, mesh.name, "terrain.lod")) continue;
            const color = sampleTextureNearest(mesh.texture, point.u, point.v) orelse return error.InvalidTerrainTexture;
            if (first) |existing| {
                same = same and std.mem.eql(u8, &existing, &color);
            } else {
                first = color;
            }
            std.debug.print(
                "    {s}: rgba={d},{d},{d},{d}\n",
                .{ mesh.name, color[0], color[1], color[2], color[3] },
            );
        }
        std.debug.print("    lods_match={}\n", .{same});
    }
}

fn sampleTextureNearest(texture: []const u8, u_raw: f32, v_raw: f32) ?[4]u8 {
    if (texture.len == 0 or texture.len % 4 != 0) return null;
    const pixels = texture.len / 4;
    const side_float = @sqrt(@as(f64, @floatFromInt(pixels)));
    const side: usize = @intFromFloat(side_float);
    if (side == 0 or side * side != pixels) return null;

    const u = std.math.clamp(u_raw, 0.0, 1.0);
    const v = std.math.clamp(v_raw, 0.0, 1.0);
    const x: usize = @intFromFloat(@round(u * @as(f32, @floatFromInt(side - 1))));
    const y: usize = @intFromFloat(@round(v * @as(f32, @floatFromInt(side - 1))));
    const idx = (y * side + x) * 4;
    return .{ texture[idx], texture[idx + 1], texture[idx + 2], texture[idx + 3] };
}

fn parseCellArg(text: []const u8) !world.cell.CellId {
    var values: [3]i32 = .{ 0, 0, 0 };
    var count: usize = 0;
    var it = std.mem.splitScalar(u8, text, ',');
    while (it.next()) |part| {
        if (count >= values.len) return error.InvalidArguments;
        const trimmed = std.mem.trim(u8, part, " \t\r\n");
        if (trimmed.len == 0) return error.InvalidArguments;
        values[count] = try std.fmt.parseInt(i32, trimmed, 10);
        count += 1;
    }
    if (count < 2) return error.InvalidArguments;
    return .{ .x = values[0], .y = values[1], .z = values[2] };
}
