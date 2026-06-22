const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const zigimg = @import("zigimg");

const editor_math = shared.editor_math;
const geometry = shared.geometry;
const project_editor_edit = @import("project_editor_edit.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_texture_paint = @import("project_editor_texture_paint.zig");
const project_editor_types = @import("project_editor_types.zig");
const project_editor_world_authoring_manifest = @import("project_editor_world_authoring_manifest.zig");
const project_editor_world_authoring_terrain = @import("project_editor_world_authoring_terrain.zig");
const scene_object = @import("editor_scene_object.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const ConceptPaintSession = project_editor_types.ConceptPaintSession;
const ConceptPaintBlendMode = project_editor_types.ConceptPaintBlendMode;
const ConceptPaintScope = project_editor_types.ConceptPaintScope;
const EditorMode = project_editor_types.EditorMode;
const TextureSize = scene_object.TextureSize;
const modules = friendly_engine.modules;
const time = friendly_engine.core.time;
const world = friendly_engine.world;

const concept_dir = ".friendly-engine/concept-paint";
const max_image_bytes = 64 * 1024 * 1024;

pub const CaptureSpec = struct {
    screenshot_path: []const u8,
    prompt: []const u8 = "",
    provider: []const u8 = "",
    desired_style: []const u8 = "",
    output_path: []const u8 = "",
    opacity: f32 = 1.0,
    blend_mode: []const u8 = "normal",
};

pub const ImportSpec = struct {
    styled_path: []const u8,
};

pub const ApplyReport = struct {
    objects_changed: usize = 0,
    terrain_cells_changed: usize = 0,
    samples_changed: usize = 0,
};

const StyledImage = struct {
    pixels: []u8,
    width: u32,
    height: u32,

    fn deinit(self: *StyledImage, allocator: std.mem.Allocator) void {
        allocator.free(self.pixels);
        self.* = undefined;
    }
};

pub fn capture(state: *ProjectEditorState, spec: CaptureSpec) !void {
    try validateReadableImagePath(state, spec.screenshot_path);
    if (state.concept_paint_session) |*existing| {
        existing.deinit(state.allocator);
        state.concept_paint_session = null;
    }
    const session_id: u64 = @intCast(@max(1, time.monotonicNs()));
    const scope = scopeForMode(state.mode);
    const output_path = if (spec.output_path.len > 0)
        try state.allocator.dupe(u8, spec.output_path)
    else
        try defaultStyledOutputPath(state.allocator, session_id);
    errdefer state.allocator.free(output_path);
    var session = ConceptPaintSession{
        .id = session_id,
        .mode = state.mode,
        .scope = scope,
        .camera = state.camera,
        .projection_mode = project_editor_state.projectionMode(state),
        .viewport_w = @intFromFloat(@max(1.0, state.viewport_screen_rect.w)),
        .viewport_h = @intFromFloat(@max(1.0, state.viewport_screen_rect.h)),
        .screenshot_path = try state.allocator.dupe(u8, spec.screenshot_path),
        .prompt = try state.allocator.dupe(u8, spec.prompt),
        .provider = try state.allocator.dupe(u8, spec.provider),
        .desired_style = try state.allocator.dupe(u8, spec.desired_style),
        .output_path = output_path,
        .opacity = std.math.clamp(spec.opacity, 0.0, 1.0),
        .blend_mode = try ConceptPaintBlendMode.parse(spec.blend_mode),
    };
    session.setStatus("Concept paint captured");
    state.concept_paint_session = session;
    project_editor_state.setStatus(state, "Concept paint captured");
}

pub fn importStyled(state: *ProjectEditorState, spec: ImportSpec) !void {
    const session = if (state.concept_paint_session) |*active| active else return error.ConceptPaintSessionMissing;
    try validateReadableImagePath(state, spec.styled_path);
    if (session.styled_path.len > 0) state.allocator.free(session.styled_path);
    session.styled_path = try state.allocator.dupe(u8, spec.styled_path);
    session.setStatus("Concept paint styled image imported");
    project_editor_state.setStatus(state, "Concept paint styled image imported");
}

pub fn clear(state: *ProjectEditorState) void {
    if (state.concept_paint_session) |*session| session.deinit(state.allocator);
    state.concept_paint_session = null;
    project_editor_state.setStatus(state, "Concept paint cleared");
}

pub fn requestPackage(state: *ProjectEditorState) ![]u8 {
    const session = state.concept_paint_session orelse return error.ConceptPaintSessionMissing;
    if (session.screenshot_path.len == 0) return error.ConceptPaintScreenshotMissing;
    if (session.provider.len == 0) return error.ConceptPaintProviderMissing;
    try ensureConceptDir(state);
    const package_rel = try std.fmt.allocPrint(state.allocator, "{s}/session-{d}.json", .{ concept_dir, session.id });
    errdefer state.allocator.free(package_rel);
    var project_dir = try openProjectDir(state);
    defer project_dir.close(state.io);
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(state.allocator);
    try appendFmt(state.allocator, &out, "{{\"session_id\":{d},\"screenshot_path\":", .{session.id});
    try appendJsonString(state.allocator, &out, session.screenshot_path);
    try appendFmt(state.allocator, &out, ",\"prompt\":", .{});
    try appendJsonString(state.allocator, &out, session.prompt);
    try appendFmt(state.allocator, &out, ",\"provider\":", .{});
    try appendJsonString(state.allocator, &out, session.provider);
    try appendFmt(state.allocator, &out, ",\"desired_style\":", .{});
    try appendJsonString(state.allocator, &out, session.desired_style);
    try appendFmt(state.allocator, &out, ",\"output_path\":", .{});
    try appendJsonString(state.allocator, &out, session.output_path);
    try appendFmt(state.allocator, &out, "}}\n", .{});
    try project_dir.writeFile(state.io, .{ .sub_path = package_rel, .data = out.items });
    project_editor_state.setStatus(state, "Concept paint package written");
    return package_rel;
}

pub fn apply(state: *ProjectEditorState) !ApplyReport {
    const session = state.concept_paint_session orelse return error.ConceptPaintSessionMissing;
    try validateSessionReady(session);
    var image = try loadStyledImage(state, session.styled_path);
    defer image.deinit(state.allocator);

    var report = ApplyReport{};
    switch (session.scope) {
        .terrain => try applyTerrain(state, session, image, &report),
        .prop => try applySelectedObject(state, session, image, true, &report),
        .architecture => try applySelectedObject(state, session, image, false, &report),
        .layout => {
            try applyTerrain(state, session, image, &report);
            try applyLayoutObjects(state, session, image, &report);
        },
    }
    if (report.samples_changed == 0) return error.ConceptPaintNoEditableSurfacesInProjection;
    if (state.concept_paint_session) |*active| active.setStatus("Concept paint applied");
    state.scene_dirty = true;
    var status_buf: [128]u8 = undefined;
    project_editor_state.setStatus(state, std.fmt.bufPrint(
        &status_buf,
        "Concept paint applied: {d} samples",
        .{report.samples_changed},
    ) catch "Concept paint applied");
    return report;
}

pub fn describe(allocator: std.mem.Allocator, state: *const ProjectEditorState) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    try appendFmt(allocator, &out, "{{\"ok\":true,\"active\":{}", .{state.concept_paint_session != null});
    if (state.concept_paint_session) |session| {
        try appendFmt(allocator, &out, ",\"session_id\":{d},\"scope\":\"{s}\",\"mode\":\"{s}\",\"viewport_w\":{d},\"viewport_h\":{d},\"opacity\":{d:.3},\"blend_mode\":\"{s}\",\"screenshot_path\":", .{
            session.id,
            session.scope.label(),
            @tagName(session.mode),
            session.viewport_w,
            session.viewport_h,
            session.opacity,
            session.blend_mode.label(),
        });
        try appendJsonString(allocator, &out, session.screenshot_path);
        try appendFmt(allocator, &out, ",\"styled_path\":", .{});
        try appendJsonString(allocator, &out, session.styled_path);
        try appendFmt(allocator, &out, ",\"prompt\":", .{});
        try appendJsonString(allocator, &out, session.prompt);
        try appendFmt(allocator, &out, ",\"provider\":", .{});
        try appendJsonString(allocator, &out, session.provider);
        try appendFmt(allocator, &out, ",\"desired_style\":", .{});
        try appendJsonString(allocator, &out, session.desired_style);
        try appendFmt(allocator, &out, ",\"output_path\":", .{});
        try appendJsonString(allocator, &out, session.output_path);
        try appendFmt(allocator, &out, ",\"ready\":{},\"status\":", .{session.styled_path.len > 0});
        try appendJsonString(allocator, &out, session.statusText());
    }
    try appendFmt(allocator, &out, "}}\n", .{});
    return out.toOwnedSlice(allocator);
}

fn scopeForMode(mode: EditorMode) ConceptPaintScope {
    return switch (mode) {
        .world_creation => .terrain,
        .prop_creation => .prop,
        .architecture_creation => .architecture,
        .layout => .layout,
        .life => .layout,
    };
}

fn validateSessionReady(session: ConceptPaintSession) !void {
    if (session.screenshot_path.len == 0) return error.ConceptPaintScreenshotMissing;
    if (session.styled_path.len == 0) return error.ConceptPaintStyledImageMissing;
    if (session.viewport_w == 0 or session.viewport_h == 0) return error.ConceptPaintInvalidViewport;
}

fn applySelectedObject(
    state: *ProjectEditorState,
    session: ConceptPaintSession,
    image: StyledImage,
    require_prop: bool,
    report: *ApplyReport,
) !void {
    const idx = state.selected_object orelse return error.ConceptPaintNoEditableSurfacesInProjection;
    if (require_prop and state.objects.items[idx].prop_asset_id == null) return error.SelectionIsNotPropAsset;
    project_editor_edit.pushUndoSnapshot(state);
    const obj = &state.objects.items[idx];
    if (!project_editor_texture_paint.ensurePaintAtlas(state, obj)) return error.InvalidPaintAtlas;
    const changed = bakeObjectTexture(state, session, image, obj);
    if (changed == 0) return error.ConceptPaintNoEditableSurfacesInProjection;
    if (obj.prop_asset_id) |asset_id| try @import("project_editor_prop_asset.zig").persistPaintedTexture(state, idx, asset_id);
    report.objects_changed += 1;
    report.samples_changed += changed;
}

fn applyLayoutObjects(
    state: *ProjectEditorState,
    session: ConceptPaintSession,
    image: StyledImage,
    report: *ApplyReport,
) !void {
    var changed_any = false;
    project_editor_edit.pushUndoSnapshot(state);
    for (state.objects.items) |*obj| {
        if (!obj.enabled or !obj.renderer_visible or obj.prop_asset_id != null or obj.editor_only) continue;
        if (!project_editor_texture_paint.ensurePaintAtlas(state, obj)) continue;
        const changed = bakeObjectTexture(state, session, image, obj);
        if (changed == 0) continue;
        changed_any = true;
        report.objects_changed += 1;
        report.samples_changed += changed;
    }
    if (!changed_any and report.terrain_cells_changed == 0) return error.ConceptPaintNoEditableSurfacesInProjection;
}

fn bakeObjectTexture(state: *ProjectEditorState, session: ConceptPaintSession, image: StyledImage, obj: *scene_object.SceneObject) usize {
    var changed: usize = 0;
    const world_xf = obj.worldTransform(state.objects.items);
    var tri: usize = 0;
    while (tri + 2 < obj.mesh.indices.len) : (tri += 3) {
        const ia = obj.mesh.indices[tri];
        const ib = obj.mesh.indices[tri + 1];
        const ic = obj.mesh.indices[tri + 2];
        if (ia >= obj.mesh.vertices.len or ib >= obj.mesh.vertices.len or ic >= obj.mesh.vertices.len) continue;
        const va = obj.mesh.vertices[ia];
        const vb = obj.mesh.vertices[ib];
        const vc = obj.mesh.vertices[ic];
        const wa = world_xf.transformPoint(va.position);
        const wb = world_xf.transformPoint(vb.position);
        const wc = world_xf.transformPoint(vc.position);
        const normal = editor_math.Vec3.normalized(editor_math.cross(editor_math.Vec3.sub(wb, wa), editor_math.Vec3.sub(wc, wa)));
        if (editor_math.Vec3.dot(normal, session.camera.forward()) >= -0.05) continue;
        const bounds = uvPixelBounds(va.uv, vb.uv, vc.uv, TextureSize);
        var y = bounds.min_y;
        while (y <= bounds.max_y) : (y += 1) {
            var x = bounds.min_x;
            while (x <= bounds.max_x) : (x += 1) {
                const uv = pixelUv(TextureSize, x, y);
                const bary = barycentric2(uv, va.uv, vb.uv, vc.uv) orelse continue;
                const world_pos = baryWorld(wa, wb, wc, bary);
                const sample_uv = projectToStencil(session, world_pos) orelse continue;
                const color = sampleImage(image, sample_uv.x, sample_uv.y);
                blendTexturePixel(obj.texture, TextureSize, x, y, color, session.opacity, session.blend_mode);
                changed += 1;
            }
        }
    }
    return changed;
}

fn applyTerrain(
    state: *ProjectEditorState,
    session: ConceptPaintSession,
    image: StyledImage,
    report: *ApplyReport,
) !void {
    _ = try state.ensureWorldCache();
    const manifest_path = try project_editor_world_authoring_manifest.pathForState(state);
    var manifest = try world.manifest.loadManifest(state.allocator, state.io, state.project_path, manifest_path);
    defer manifest.deinit();
    var doc = try modules.terrain.authoring.load(state.allocator, state.io, state.project_path, manifest_path);
    defer doc.deinit();
    var changed_cells: usize = 0;
    var sample_count: usize = 0;
    for (doc.tiles.items) |*tile| {
        const bounds = world.cell.boundsForCell(tile.id(), manifest.cell_size_m, world.cell.default_cell_height_m);
        const splat_bounds = terrainSplatBoundsInProjection(session, bounds, tile, manifest.cell_size_m) orelse continue;
        const changed = try bakeTerrainTile(session, image, tile, bounds, manifest.cell_size_m, splat_bounds);
        if (changed == 0) continue;
        try modules.terrain.authoring.upsertTileFile(state.allocator, state.io, state.project_path, manifest_path, .{
            .cell = tile.id(),
            .size = tile.size,
            .lod_levels = tile.lod_levels,
            .heights = tile.heights,
            .splat_size = tile.splat_size,
            .splat = tile.splat,
            .paint_layers = tile.paint_layers,
            .paint_colors = tile.paint_colors,
            .paint_albedo_textures = tile.paint_albedo_textures,
            .paint_roughness_textures = tile.paint_roughness_textures,
            .paint_specular_textures = tile.paint_specular_textures,
            .paint_displacement_textures = tile.paint_displacement_textures,
            .material = tile.material,
        });
        try project_editor_state.markDirtyCell(state, "Terrain", tile.id(), "concept paint");
        changed_cells += 1;
        sample_count += changed;
    }
    if (changed_cells > 0) {
        state.invalidateWorldCache();
        state.terrain_preview_stale = true;
    }
    report.terrain_cells_changed += changed_cells;
    report.samples_changed += sample_count;
}

fn bakeTerrainTile(
    session: ConceptPaintSession,
    image: StyledImage,
    tile: *modules.terrain.authoring.OwnedTerrainTile,
    bounds: world.cell.CellBounds,
    cell_size_m: f32,
    splat_bounds: SplatBounds,
) !usize {
    const layer_count = tile.paint_layers.len;
    if (layer_count == 0) return error.InvalidTerrainDocument;
    var changed: usize = 0;
    var y: u32 = splat_bounds.min_y;
    while (y <= splat_bounds.max_y) : (y += 1) {
        var x: u32 = splat_bounds.min_x;
        while (x <= splat_bounds.max_x) : (x += 1) {
            const idx = @as(usize, y) * @as(usize, tile.splat_size) + @as(usize, x);
            const height = if (idx < tile.heights.len) tile.heights[idx] else 0;
            const wx = bounds.min.x + (@as(f32, @floatFromInt(x)) + 0.5) / @as(f32, @floatFromInt(tile.splat_size)) * cell_size_m;
            const wz = bounds.min.z + (@as(f32, @floatFromInt(y)) + 0.5) / @as(f32, @floatFromInt(tile.splat_size)) * cell_size_m;
            const sample_uv = projectToStencil(session, .{ .x = wx, .y = height, .z = wz }) orelse continue;
            const color = sampleImage(image, sample_uv.x, sample_uv.y);
            const layer = nearestTerrainLayer(color, tile.paint_colors);
            blendSplat(tile.splat, idx, layer_count, layer, session.opacity);
            changed += 1;
        }
    }
    return changed;
}

const SplatBounds = struct {
    min_x: u32,
    max_x: u32,
    min_y: u32,
    max_y: u32,
};

fn terrainSplatBoundsInProjection(
    session: ConceptPaintSession,
    bounds: world.cell.CellBounds,
    tile: *const modules.terrain.authoring.OwnedTerrainTile,
    cell_size_m: f32,
) ?SplatBounds {
    if (tile.splat_size == 0) return null;
    const full = SplatBounds{
        .min_x = 0,
        .max_x = tile.splat_size - 1,
        .min_y = 0,
        .max_y = tile.splat_size - 1,
    };
    const eye = session.camera.eye();
    if (eye.x >= bounds.min.x and eye.x <= bounds.max.x and eye.z >= bounds.min.z and eye.z <= bounds.max.z) return full;

    const coarse_steps: u32 = 8;
    const expansion = @max(@as(u32, 1), tile.splat_size / coarse_steps);
    var found = false;
    var min_x: u32 = tile.splat_size - 1;
    var min_y: u32 = tile.splat_size - 1;
    var max_x: u32 = 0;
    var max_y: u32 = 0;
    var gy: u32 = 0;
    while (gy <= coarse_steps) : (gy += 1) {
        const sy = @min(tile.splat_size - 1, (gy * (tile.splat_size - 1)) / coarse_steps);
        var gx: u32 = 0;
        while (gx <= coarse_steps) : (gx += 1) {
            const sx = @min(tile.splat_size - 1, (gx * (tile.splat_size - 1)) / coarse_steps);
            const idx = @as(usize, sy) * @as(usize, tile.splat_size) + @as(usize, sx);
            const height = if (idx < tile.heights.len) tile.heights[idx] else bounds.min.y;
            const wx = bounds.min.x + (@as(f32, @floatFromInt(sx)) + 0.5) / @as(f32, @floatFromInt(tile.splat_size)) * cell_size_m;
            const wz = bounds.min.z + (@as(f32, @floatFromInt(sy)) + 0.5) / @as(f32, @floatFromInt(tile.splat_size)) * cell_size_m;
            const screen = projectToScreen(session, .{ .x = wx, .y = height, .z = wz }) orelse continue;
            const pad: f32 = 64.0;
            if (screen.x < -pad or screen.y < -pad or
                screen.x > @as(f32, @floatFromInt(session.viewport_w)) + pad or
                screen.y > @as(f32, @floatFromInt(session.viewport_h)) + pad) continue;
            found = true;
            min_x = @min(min_x, sx);
            min_y = @min(min_y, sy);
            max_x = @max(max_x, sx);
            max_y = @max(max_y, sy);
        }
    }
    if (!found) return null;
    return .{
        .min_x = min_x -| expansion,
        .max_x = @min(tile.splat_size - 1, max_x + expansion),
        .min_y = min_y -| expansion,
        .max_y = @min(tile.splat_size - 1, max_y + expansion),
    };
}

fn projectToScreen(session: ConceptPaintSession, point: editor_math.Vec3) ?editor_math.Vec2 {
    return editor_math.projectWorldPoint(
        session.camera,
        point,
        @floatFromInt(session.viewport_w),
        @floatFromInt(session.viewport_h),
        session.projection_mode,
    );
}

fn projectToStencil(session: ConceptPaintSession, point: editor_math.Vec3) ?editor_math.Vec2 {
    const screen = projectToScreen(session, point) orelse return null;
    if (screen.x < 0 or screen.y < 0 or screen.x >= @as(f32, @floatFromInt(session.viewport_w)) or screen.y >= @as(f32, @floatFromInt(session.viewport_h))) return null;
    return .{
        .x = screen.x / @as(f32, @floatFromInt(session.viewport_w)),
        .y = screen.y / @as(f32, @floatFromInt(session.viewport_h)),
    };
}

fn uvPixelBounds(a: editor_math.Vec2, b: editor_math.Vec2, c: editor_math.Vec2, size: u32) struct { min_x: u32, max_x: u32, min_y: u32, max_y: u32 } {
    const max_idx = @as(f32, @floatFromInt(size - 1));
    const min_u = std.math.clamp(@min(a.x, @min(b.x, c.x)), 0, 1);
    const max_u = std.math.clamp(@max(a.x, @max(b.x, c.x)), 0, 1);
    const min_v = std.math.clamp(@min(a.y, @min(b.y, c.y)), 0, 1);
    const max_v = std.math.clamp(@max(a.y, @max(b.y, c.y)), 0, 1);
    return .{
        .min_x = @intFromFloat(@floor(min_u * max_idx)),
        .max_x = @intFromFloat(@ceil(max_u * max_idx)),
        .min_y = @intFromFloat(@floor(min_v * max_idx)),
        .max_y = @intFromFloat(@ceil(max_v * max_idx)),
    };
}

fn pixelUv(size: u32, x: u32, y: u32) editor_math.Vec2 {
    const denom = @as(f32, @floatFromInt(size));
    return .{ .x = (@as(f32, @floatFromInt(x)) + 0.5) / denom, .y = (@as(f32, @floatFromInt(y)) + 0.5) / denom };
}

fn barycentric2(p: editor_math.Vec2, a: editor_math.Vec2, b: editor_math.Vec2, c: editor_math.Vec2) ?[3]f32 {
    const v0x = b.x - a.x;
    const v0y = b.y - a.y;
    const v1x = c.x - a.x;
    const v1y = c.y - a.y;
    const v2x = p.x - a.x;
    const v2y = p.y - a.y;
    const den = v0x * v1y - v1x * v0y;
    if (@abs(den) < 0.000001) return null;
    const v = (v2x * v1y - v1x * v2y) / den;
    const w = (v0x * v2y - v2x * v0y) / den;
    const u = 1.0 - v - w;
    if (u < -0.001 or v < -0.001 or w < -0.001) return null;
    return .{ u, v, w };
}

fn baryWorld(a: editor_math.Vec3, b: editor_math.Vec3, c: editor_math.Vec3, bary: [3]f32) editor_math.Vec3 {
    return .{
        .x = a.x * bary[0] + b.x * bary[1] + c.x * bary[2],
        .y = a.y * bary[0] + b.y * bary[1] + c.y * bary[2],
        .z = a.z * bary[0] + b.z * bary[1] + c.z * bary[2],
    };
}

fn sampleImage(image: StyledImage, u: f32, v: f32) [4]u8 {
    const x: u32 = @intFromFloat(std.math.clamp(u, 0, 0.9999) * @as(f32, @floatFromInt(image.width)));
    const y: u32 = @intFromFloat(std.math.clamp(v, 0, 0.9999) * @as(f32, @floatFromInt(image.height)));
    const idx = (@as(usize, y) * @as(usize, image.width) + @as(usize, x)) * 4;
    return .{ image.pixels[idx], image.pixels[idx + 1], image.pixels[idx + 2], image.pixels[idx + 3] };
}

fn blendTexturePixel(pixels: []u8, size: u32, x: u32, y: u32, color: [4]u8, opacity: f32, blend: ConceptPaintBlendMode) void {
    const idx = (@as(usize, y) * @as(usize, size) + @as(usize, x)) * 4;
    const alpha = std.math.clamp(opacity * (@as(f32, @floatFromInt(color[3])) / 255.0), 0.0, 1.0);
    pixels[idx] = blendByte(pixels[idx], color[0], alpha, blend);
    pixels[idx + 1] = blendByte(pixels[idx + 1], color[1], alpha, blend);
    pixels[idx + 2] = blendByte(pixels[idx + 2], color[2], alpha, blend);
    pixels[idx + 3] = 255;
}

fn blendByte(dst: u8, src: u8, alpha: f32, blend: ConceptPaintBlendMode) u8 {
    const base = switch (blend) {
        .normal => src,
        .multiply => @as(u8, @intCast((@as(u16, dst) * @as(u16, src)) / 255)),
    };
    const value = @as(f32, @floatFromInt(dst)) + (@as(f32, @floatFromInt(base)) - @as(f32, @floatFromInt(dst))) * alpha;
    return @intFromFloat(std.math.clamp(@round(value), 0, 255));
}

fn nearestTerrainLayer(color: [4]u8, palette: []const [4]u8) usize {
    var best_idx: usize = 0;
    var best_dist: u32 = std.math.maxInt(u32);
    for (palette, 0..) |candidate, idx| {
        const dr = @as(i32, color[0]) - @as(i32, candidate[0]);
        const dg = @as(i32, color[1]) - @as(i32, candidate[1]);
        const db = @as(i32, color[2]) - @as(i32, candidate[2]);
        const dist: u32 = @intCast(dr * dr + dg * dg + db * db);
        if (dist < best_dist) {
            best_dist = dist;
            best_idx = idx;
        }
    }
    return best_idx;
}

fn blendSplat(splat: []u8, sample_idx: usize, layer_count: usize, layer: usize, opacity: f32) void {
    const base = sample_idx * layer_count;
    if (base + layer >= splat.len) return;
    const amount: u8 = @intFromFloat(std.math.clamp(@round(opacity * 255.0), 0, 255));
    for (0..layer_count) |idx| {
        const old = splat[base + idx];
        splat[base + idx] = if (idx == layer)
            @intCast(@min(255, @as(u16, old) + amount))
        else
            @intCast((@as(u16, old) * @as(u16, 255 - amount)) / 255);
    }
}

fn loadStyledImage(state: *ProjectEditorState, path: []const u8) !StyledImage {
    const bytes = try readProjectOrAbsoluteFile(state, path);
    defer state.allocator.free(bytes);
    var image = try zigimg.Image.fromMemory(state.allocator, bytes);
    defer image.deinit(state.allocator);
    try image.convert(state.allocator, .rgba32);
    return .{
        .pixels = try state.allocator.dupe(u8, image.rawBytes()),
        .width = @intCast(image.width),
        .height = @intCast(image.height),
    };
}

fn validateReadableImagePath(state: *ProjectEditorState, path: []const u8) !void {
    if (path.len == 0) return error.InvalidConceptPaintImagePath;
    if (std.mem.indexOfScalar(u8, path, '\\') != null) return error.InvalidConceptPaintImagePath;
    const ext = std.fs.path.extension(path);
    if (!std.ascii.eqlIgnoreCase(ext, ".png") and !std.ascii.eqlIgnoreCase(ext, ".jpg") and !std.ascii.eqlIgnoreCase(ext, ".jpeg")) {
        return error.InvalidConceptPaintImagePath;
    }
    const bytes = try readProjectOrAbsoluteFile(state, path);
    state.allocator.free(bytes);
}

fn readProjectOrAbsoluteFile(state: *ProjectEditorState, path: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(path)) {
        const parent = std.fs.path.dirname(path) orelse return error.InvalidConceptPaintImagePath;
        const base = std.fs.path.basename(path);
        var dir = try std.Io.Dir.openDirAbsolute(state.io, parent, .{});
        defer dir.close(state.io);
        return dir.readFileAlloc(state.io, base, state.allocator, .limited(max_image_bytes));
    }
    var project_dir = try openProjectDir(state);
    defer project_dir.close(state.io);
    return project_dir.readFileAlloc(state.io, path, state.allocator, .limited(max_image_bytes));
}

fn openProjectDir(state: *ProjectEditorState) !std.Io.Dir {
    if (std.fs.path.isAbsolute(state.project_path)) {
        return std.Io.Dir.openDirAbsolute(state.io, state.project_path, .{});
    }
    return std.Io.Dir.cwd().openDir(state.io, state.project_path, .{});
}

fn ensureConceptDir(state: *ProjectEditorState) !void {
    var project_dir = try openProjectDir(state);
    defer project_dir.close(state.io);
    try project_dir.createDirPath(state.io, concept_dir);
}

fn defaultStyledOutputPath(allocator: std.mem.Allocator, session_id: u64) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}/session-{d}-styled.png", .{ concept_dir, session_id });
}

fn appendJsonString(allocator: std.mem.Allocator, out: *std.ArrayList(u8), value: []const u8) !void {
    try out.append(allocator, '"');
    for (value) |ch| switch (ch) {
        '"' => try out.appendSlice(allocator, "\\\""),
        '\\' => try out.appendSlice(allocator, "\\\\"),
        '\n' => try out.appendSlice(allocator, "\\n"),
        '\r' => try out.appendSlice(allocator, "\\r"),
        '\t' => try out.appendSlice(allocator, "\\t"),
        0...8, 11, 12, 14...0x1f => try appendFmt(allocator, out, "\\u{x:0>4}", .{ch}),
        else => try out.append(allocator, ch),
    };
    try out.append(allocator, '"');
}

fn appendFmt(allocator: std.mem.Allocator, out: *std.ArrayList(u8), comptime fmt: []const u8, args: anytype) !void {
    const piece = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(piece);
    try out.appendSlice(allocator, piece);
}

test "nearest terrain layer selects closest palette color" {
    const palette = [_][4]u8{
        .{ 10, 10, 10, 255 },
        .{ 220, 80, 40, 255 },
    };
    try std.testing.expectEqual(@as(usize, 1), nearestTerrainLayer(.{ 210, 75, 45, 255 }, &palette));
}

test "normal blend byte respects alpha" {
    try std.testing.expectEqual(@as(u8, 150), blendByte(100, 200, 0.5, .normal));
}

test "barycentric rejects points outside triangle" {
    const a = editor_math.Vec2{ .x = 0, .y = 0 };
    const b = editor_math.Vec2{ .x = 1, .y = 0 };
    const c = editor_math.Vec2{ .x = 0, .y = 1 };
    try std.testing.expect(barycentric2(.{ .x = 0.25, .y = 0.25 }, a, b, c) != null);
    try std.testing.expect(barycentric2(.{ .x = 1.2, .y = 0.25 }, a, b, c) == null);
}
