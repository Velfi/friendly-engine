const std = @import("std");
const friendly_engine = @import("friendly_engine");
const runtime_shared = @import("runtime_shared");

const world_mod = friendly_engine.world;
const modules = friendly_engine.modules;
const scene_kdl = runtime_shared.scene_kdl;
const scene_resolve = runtime_shared.scene_resolve;
const world_prefetch = @import("world_prefetch.zig");

pub const BakeWorldSummary = struct {
    world_id: []u8,
    written_cells: usize,

    pub fn deinit(self: *BakeWorldSummary, allocator: std.mem.Allocator) void {
        allocator.free(self.world_id);
    }
};

pub const BakeWorldOptions = struct {
    cells: []const world_mod.cell.CellId = &.{},
    progress_context: ?*anyopaque = null,
    progress: ?*const fn (?*anyopaque, BakeProgress) void = null,
};

pub const BakeProgressStage = enum {
    planning_layers,
    baking_cell,
    compiling_layer,
    writing_prefetch,
};

pub const BakeProgress = struct {
    stage: BakeProgressStage,
    current: usize = 0,
    total: usize = 0,
    cell: ?world_mod.cell.CellId = null,
    layer_name: []const u8 = "",
    scene_path: []const u8 = "",
};

pub fn bakeWorld(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    manifest_path: []const u8,
    target: []const u8,
) !BakeWorldSummary {
    return bakeWorldWithOptions(allocator, io, project_path, manifest_path, target, .{});
}

pub fn bakeWorldWithOptions(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_path: []const u8,
    manifest_path: []const u8,
    target: []const u8,
    options: BakeWorldOptions,
) !BakeWorldSummary {
    var loaded_manifest = try world_mod.manifest.loadManifest(allocator, io, project_path, manifest_path);
    defer loaded_manifest.deinit();

    var module_graph = try modules.initBuiltinGraph(allocator);
    defer module_graph.deinit();
    try module_graph.resolveAll();
    var services = modules.ServiceRegistry.init(allocator);
    defer services.deinit();
    try module_graph.registerAll(&services);

    const compile_ctx = world_mod.compiler.layer.CompileContext{
        .allocator = allocator,
        .io = io,
        .project_path = project_path,
        .target = target,
        .manifest_path = manifest_path,
        .loaded_manifest = &loaded_manifest,
    };
    emitProgress(options, .{ .stage = .planning_layers });
    const layer_plans = try buildLayerPlans(allocator, &compile_ctx, services.worldCompilerLayers());
    defer freeLayerPlans(allocator, layer_plans);

    var project_dir = try openProjectDir(io, project_path);
    defer project_dir.close(io);
    var cell_file_io = try world_mod.file_io.SyncCellFileIo.init(
        allocator,
        io,
        project_path,
        target,
        loaded_manifest.world_id,
    );
    defer cell_file_io.deinit();

    var written_cells: usize = 0;
    var prefetch_entries = std.ArrayList(world_prefetch.CellEntry).empty;
    defer {
        for (prefetch_entries.items) |entry| {
            for (entry.dependencies) |dependency| {
                allocator.free(dependency.kind);
                allocator.free(dependency.path);
            }
            allocator.free(entry.dependencies);
        }
        prefetch_entries.deinit(allocator);
    }

    const total_cells = countSelectedCells(loaded_manifest.cells, options.cells);
    var current_cell: usize = 0;
    for (loaded_manifest.cells) |manifest_cell| {
        if (options.cells.len > 0 and !containsCell(options.cells, manifest_cell.id)) continue;
        current_cell += 1;
        emitProgress(options, .{
            .stage = .baking_cell,
            .current = current_cell,
            .total = total_cells,
            .cell = manifest_cell.id,
            .scene_path = manifest_cell.authoring_path,
        });
        var inputs = std.ArrayList(world_mod.compiler.SceneObjectInput).empty;
        defer {
            for (inputs.items) |entry| {
                allocator.free(entry.name);
                allocator.free(entry.vertices);
                allocator.free(entry.indices);
                allocator.free(entry.texture);
            }
            inputs.deinit(allocator);
        }

        const scene_bytes = try project_dir.readFileAlloc(io, manifest_cell.authoring_path, allocator, .limited(16 * 1024 * 1024));
        defer allocator.free(scene_bytes);
        var document = try scene_kdl.parseSceneDocument(allocator, scene_bytes);
        defer document.deinit(allocator);

        const resolver = scene_resolve.AssetResolver{
            .io = io,
            .project_dir = project_dir,
            .cache_target = target,
        };
        var loaded_scene = try scene_resolve.resolveDocument(allocator, document, resolver);
        defer loaded_scene.deinit(allocator);

        for (loaded_scene.objects) |object| {
            if (object.object_kind == .marker) continue;
            const is_prop = object.prop_asset_id != null;
            const converted_verts = try allocator.alloc(world_mod.cell.RenderVertex, if (is_prop) 0 else object.mesh.vertices.len);
            if (!is_prop) {
                for (object.mesh.vertices, 0..) |src, i| {
                    converted_verts[i] = .{
                        .position = src.position,
                        .normal = src.normal,
                        .uv = src.uv,
                    };
                }
            }
            const indices = if (is_prop) try allocator.alloc(u32, 0) else try allocator.dupe(u32, object.mesh.indices);
            const texture = if (is_prop) try allocator.alloc(u8, 0) else try allocator.dupe(u8, object.texture);

            try inputs.append(allocator, .{
                .id = object.id,
                .name = try allocator.dupe(u8, object.name),
                .prop_asset_id = object.prop_asset_id,
                .variant = parseVariantIndex(object.variant),
                .interactable = if (object.gameplay) |gameplay| gameplay.interactable else false,
                .vertices = converted_verts,
                .indices = indices,
                .texture = texture,
                .base_color = .{
                    .r = object.base_color.r,
                    .g = object.base_color.g,
                    .b = object.base_color.b,
                    .a = object.base_color.a,
                },
                .position = object.position,
                .scale = object.scale,
            });
        }

        const neighbors = try collectNeighborLinks(allocator, &loaded_manifest, manifest_cell.id);
        defer allocator.free(neighbors);

        var compiled = try world_mod.compiler.compileSceneLayerCell(
            allocator,
            manifest_cell.id,
            loaded_manifest.cell_size_m,
            inputs.items,
            neighbors,
        );
        defer compiled.deinit(allocator);

        for (layer_plans) |plan| {
            if (!containsCell(plan.affected_cells, manifest_cell.id)) continue;
            emitProgress(options, .{
                .stage = .compiling_layer,
                .current = current_cell,
                .total = total_cells,
                .cell = manifest_cell.id,
                .layer_name = plan.layer.name,
                .scene_path = manifest_cell.authoring_path,
            });
            var output = try plan.layer.compile_cell(plan.layer.ctx, &compile_ctx, manifest_cell.id, allocator);
            defer output.deinit(allocator);
            try world_mod.compiler.mergeLayerOutput(allocator, &compiled, &output);
        }

        try appendSceneDependencies(allocator, &compiled, manifest_cell.authoring_path, document);
        try prefetch_entries.append(allocator, try world_prefetch.copyCellEntry(allocator, manifest_cell.id, compiled.dependencies));
        try cell_file_io.writeCell(compiled);
        written_cells += 1;
    }

    emitProgress(options, .{ .stage = .writing_prefetch, .current = written_cells, .total = total_cells });
    try world_prefetch.write(allocator, io, project_dir, target, loaded_manifest.world_id, prefetch_entries.items);
    return .{
        .world_id = try allocator.dupe(u8, loaded_manifest.world_id),
        .written_cells = written_cells,
    };
}

fn emitProgress(options: BakeWorldOptions, progress: BakeProgress) void {
    if (options.progress) |callback| callback(options.progress_context, progress);
}

fn parseVariantIndex(variant: ?[]const u8) u32 {
    const value = variant orelse return 0;
    return std.fmt.parseUnsigned(u32, value, 10) catch 0;
}

fn appendSceneDependencies(
    allocator: std.mem.Allocator,
    compiled: *world_mod.cell.WorldCellData,
    authoring_path: []const u8,
    document: runtime_shared.scene_document.SceneDocument,
) !void {
    try appendCellDependency(allocator, compiled, "scene", authoring_path);
    for (document.entities) |entity| {
        if (entity.prop_asset_id) |asset_id| {
            try appendCellDependency(allocator, compiled, "prop", asset_id);
            continue;
        }
        if (entity.texture_file.len > 0) {
            try appendCellDependency(allocator, compiled, "texture", entity.texture_file);
        }
        switch (entity.mesh) {
            .primitive => {},
            .asset => |path| try appendCellDependency(allocator, compiled, "mesh", path),
        }
    }
}

fn appendCellDependency(
    allocator: std.mem.Allocator,
    compiled: *world_mod.cell.WorldCellData,
    kind: []const u8,
    path: []const u8,
) !void {
    for (compiled.dependencies) |dependency| {
        if (std.mem.eql(u8, dependency.kind, kind) and std.mem.eql(u8, dependency.path, path)) return;
    }
    const old_len = compiled.dependencies.len;
    const merged = try allocator.alloc(world_mod.cell.CellDependency, old_len + 1);
    @memcpy(merged[0..old_len], compiled.dependencies);
    merged[old_len] = .{
        .kind = try allocator.dupe(u8, kind),
        .path = try allocator.dupe(u8, path),
    };
    if (old_len > 0) allocator.free(compiled.dependencies);
    compiled.dependencies = merged;
}

const LayerPlan = struct {
    layer: world_mod.compiler.layer.WorldCompilerLayer,
    affected_cells: []world_mod.cell.CellId,
};

fn buildLayerPlans(
    allocator: std.mem.Allocator,
    compile_ctx: *const world_mod.compiler.layer.CompileContext,
    layers: []const world_mod.compiler.layer.WorldCompilerLayer,
) ![]LayerPlan {
    var plans = std.ArrayList(LayerPlan).empty;
    defer plans.deinit(allocator);
    errdefer {
        for (plans.items) |plan| {
            allocator.free(plan.affected_cells);
        }
    }
    for (layers) |layer| {
        const affected = try layer.affected_cells(layer.ctx, compile_ctx, allocator);
        var affected_owned = false;
        errdefer if (!affected_owned) allocator.free(affected);
        try plans.append(allocator, .{
            .layer = layer,
            .affected_cells = affected,
        });
        affected_owned = true;
    }
    return plans.toOwnedSlice(allocator);
}

fn freeLayerPlans(allocator: std.mem.Allocator, plans: []LayerPlan) void {
    for (plans) |plan| {
        allocator.free(plan.affected_cells);
    }
    allocator.free(plans);
}

fn containsCell(list: []const world_mod.cell.CellId, target: world_mod.cell.CellId) bool {
    for (list) |entry| {
        if (entry.eql(target)) return true;
    }
    return false;
}

fn countSelectedCells(cells: []const world_mod.manifest.ManifestCell, selected: []const world_mod.cell.CellId) usize {
    if (selected.len == 0) return cells.len;
    var count: usize = 0;
    for (cells) |entry| {
        if (containsCell(selected, entry.id)) count += 1;
    }
    return count;
}

pub fn runCli(allocator: std.mem.Allocator, io: std.Io, args: []const []const u8) !void {
    var project_path: []const u8 = ".";
    var manifest_path: []const u8 = "world.kdl";
    var target: []const u8 = "client-debug";
    var cells = std.ArrayList(world_mod.cell.CellId).empty;
    defer cells.deinit(allocator);

    var i: usize = 0;
    while (i < args.len) {
        const flag = args[i];
        i += 1;
        if (i >= args.len) return error.InvalidArguments;
        const value = args[i];
        i += 1;

        if (std.mem.eql(u8, flag, "--project")) {
            project_path = value;
            continue;
        }
        if (std.mem.eql(u8, flag, "--world")) {
            manifest_path = value;
            continue;
        }
        if (std.mem.eql(u8, flag, "--target")) {
            target = value;
            continue;
        }
        if (std.mem.eql(u8, flag, "--cell")) {
            try cells.append(allocator, try parseCellArg(value));
            continue;
        }
        return error.InvalidArguments;
    }

    var summary = try bakeWorldWithOptions(allocator, io, project_path, manifest_path, target, .{
        .cells = cells.items,
    });
    defer summary.deinit(allocator);
    std.debug.print(
        "world-bake complete: world={s} cells={d} target={s}\n",
        .{ summary.world_id, summary.written_cells, target },
    );
}

pub fn parseCellArg(value: []const u8) !world_mod.cell.CellId {
    var parts = std.mem.splitScalar(u8, value, ',');
    const x_text = parts.next() orelse return error.InvalidCellArgument;
    const y_text = parts.next() orelse return error.InvalidCellArgument;
    const z_text = parts.next();
    if (parts.next() != null) return error.InvalidCellArgument;
    if (x_text.len == 0 or y_text.len == 0) return error.InvalidCellArgument;
    if (z_text) |text| {
        if (text.len == 0) return error.InvalidCellArgument;
    }
    return .{
        .x = try std.fmt.parseInt(i32, x_text, 10),
        .y = try std.fmt.parseInt(i32, y_text, 10),
        .z = if (z_text) |text| try std.fmt.parseInt(i32, text, 10) else 0,
    };
}

fn collectNeighborLinks(
    allocator: std.mem.Allocator,
    loaded_manifest: *const world_mod.manifest.OwnedWorldManifest,
    id: world_mod.cell.CellId,
) ![]world_mod.cell.CellId {
    const directions = [_]world_mod.cell.CellId{
        .{ .x = 1, .y = 0, .z = 0 },
        .{ .x = -1, .y = 0, .z = 0 },
        .{ .x = 0, .y = 1, .z = 0 },
        .{ .x = 0, .y = -1, .z = 0 },
        .{ .x = 0, .y = 0, .z = 1 },
        .{ .x = 0, .y = 0, .z = -1 },
    };

    var neighbors = std.ArrayList(world_mod.cell.CellId).empty;
    defer neighbors.deinit(allocator);

    for (directions) |dir| {
        const candidate = world_mod.cell.CellId{
            .x = id.x + dir.x,
            .y = id.y + dir.y,
            .z = id.z + dir.z,
        };
        if (loaded_manifest.hasCell(candidate)) {
            try neighbors.append(allocator, candidate);
        }
    }

    return neighbors.toOwnedSlice(allocator);
}

fn openProjectDir(io: std.Io, project_path: []const u8) !std.Io.Dir {
    if (std.fs.path.isAbsolute(project_path)) {
        return try std.Io.Dir.openDirAbsolute(io, project_path, .{});
    }
    return try std.Io.Dir.cwd().openDir(io, project_path, .{});
}

comptime {
    _ = @import("world_bake_tests.zig");
}
