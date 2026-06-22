const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const editor_math = shared.editor_math;
const shared_color = shared.color;
const uv_atlas = shared.uv_atlas;
const project_editor_edit = @import("project_editor_edit.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_types = @import("project_editor_types.zig");
const ui_widgets = @import("project_editor_ui_widgets.zig");
const scene_object = @import("editor_scene_object.zig");

const core_ui = friendly_engine.modules.core_ui;
const ProjectEditorState = project_editor_state.ProjectEditorState;
const SceneObject = scene_object.SceneObject;
const TextureSize = scene_object.TextureSize;
const TexturePaintBrush = project_editor_types.TexturePaintBrush;
const TexturePaintStencil = project_editor_types.TexturePaintStencil;

pub fn ensurePaintAtlas(state: *ProjectEditorState, obj: *SceneObject) bool {
    if (obj.paint_atlas_status == .valid) {
        if (std.mem.eql(u8, obj.paint_atlas_generator, uv_atlas.xatlas_commit)) {
            if (uv_atlas.validateUvSet(&obj.mesh)) |_| return true else |_| obj.paint_atlas_status = .stale;
        } else {
            obj.paint_atlas_status = .stale;
        }
    }

    const options = uv_atlas.AtlasOptions{
        .atlas_size = TextureSize,
        .padding_px = 4,
    };
    const result = uv_atlas.generatePaintAtlas(state.allocator, &obj.mesh, options) catch |err| {
        obj.paint_atlas_status = .missing;
        setAtlasErrorStatus(state, err);
        return false;
    };

    obj.mesh.deinit(state.allocator);
    obj.mesh = result.mesh;
    obj.paint_atlas_status = .valid;
    obj.paint_atlas_size = result.report.atlas_width;
    obj.paint_atlas_padding_px = options.padding_px;
    obj.paint_atlas_report = result.report;
    obj.paint_atlas_generator = uv_atlas.xatlas_commit;
    state.scene_dirty = true;
    project_editor_state.setStatus(state, "Paint atlas rebuilt");
    return true;
}

pub fn markPaintAtlasStale(obj: *SceneObject) void {
    obj.paint_atlas_status = .stale;
}

pub fn paintAtUv(state: *ProjectEditorState, obj: *SceneObject, uv: editor_math.Vec2) void {
    if (!ensurePaintAtlas(state, obj)) return;
    paintTexture(obj.texture, TextureSize, uv, state.brush_color, .{
        .radius = state.brush_radius,
        .opacity = state.texture_paint_opacity,
        .hardness = state.texture_paint_hardness,
        .noise = state.texture_paint_noise,
        .brush = state.texture_paint_brush,
        .stencil = state.texture_paint_stencil,
    });
    state.scene_dirty = true;
}

pub fn fillSelectedOrObject(state: *ProjectEditorState) void {
    const idx = state.selected_object orelse {
        project_editor_state.setStatus(state, "Select an object to fill");
        return;
    };
    project_editor_edit.pushUndoSnapshot(state);
    const obj = &state.objects.items[idx];
    if (!ensurePaintAtlas(state, obj)) return;
    if (state.selected_face) |face| {
        fillFaceTexture(obj, face, state.brush_color, state.texture_paint_opacity, state.texture_paint_stencil);
        project_editor_state.setStatus(state, "Face fill applied");
    } else {
        fillObjectTexture(obj, state.brush_color, state.texture_paint_opacity, state.texture_paint_stencil);
        project_editor_state.setStatus(state, "Texture fill applied");
    }
    state.scene_dirty = true;
}

fn setAtlasErrorStatus(state: *ProjectEditorState, err: anyerror) void {
    project_editor_state.setStatus(state, switch (err) {
        error.EmptyMesh => "Paint atlas failed: empty mesh",
        error.InvalidIndexCount => "Paint atlas failed: invalid indices",
        error.IndexOutOfRange => "Paint atlas failed: index out of range",
        error.DegenerateTriangle => "Paint atlas failed: degenerate triangle",
        error.UnsupportedSkinnedAtlasGeneration => "Paint atlas failed: skinned mesh unsupported",
        error.CollapsedUvChart => "Paint atlas failed: collapsed UV chart",
        error.OverlappingUvChart => "Paint atlas failed: overlapping UV chart",
        error.UvOutOfRange => "Paint atlas failed: UV out of range",
        else => "Paint atlas failed",
    });
}

pub fn cycleBrush(state: *ProjectEditorState) void {
    state.texture_paint_brush = state.texture_paint_brush.next();
    project_editor_state.setStatus(state, "Texture brush changed");
}

pub fn cycleStencil(state: *ProjectEditorState) void {
    state.texture_paint_stencil = state.texture_paint_stencil.next();
    project_editor_state.setStatus(state, "Texture stencil changed");
}

pub fn buildToolControls(ui: *core_ui.UiContext, state: *ProjectEditorState, id_prefix: []const u8) !void {
    try ui.label("Paint On Mesh");
    try ui_widgets.compactInfo(ui, "Brush directly on the prop");
    try ui_widgets.compactInfo(ui, "No UV setup");
    try ui.label("Detail Budget");
    try ui_widgets.compactInfo(ui, "Higher detail costs memory");
    try core_ui.layout.sameLine(ui);
    var q1_id: [80]u8 = undefined;
    if ((try ui_widgets.button(ui, std.fmt.bufPrint(&q1_id, "{s}-quality-1x", .{id_prefix}) catch "ed-texture-quality-1x", "1x", 42, state.prop_texture_quality == 1)).clicked) {
        state.prop_texture_quality = 1;
        project_editor_state.setStatus(state, "Texture detail 1x");
    }
    var q2_id: [80]u8 = undefined;
    if ((try ui_widgets.button(ui, std.fmt.bufPrint(&q2_id, "{s}-quality-2x", .{id_prefix}) catch "ed-texture-quality-2x", "2x", 42, state.prop_texture_quality == 2)).clicked) {
        state.prop_texture_quality = 2;
        project_editor_state.setStatus(state, "Texture detail 2x");
    }
    var q4_id: [80]u8 = undefined;
    if ((try ui_widgets.button(ui, std.fmt.bufPrint(&q4_id, "{s}-quality-4x", .{id_prefix}) catch "ed-texture-quality-4x", "4x", 42, state.prop_texture_quality == 4)).clicked) {
        state.prop_texture_quality = 4;
        project_editor_state.setStatus(state, "Texture detail 4x");
    }
    try core_ui.layout.endSameLine(ui);

    try ui.label("Brush Feel");
    try core_ui.layout.sameLine(ui);
    var brush_id: [80]u8 = undefined;
    if ((try ui_widgets.button(ui, std.fmt.bufPrint(&brush_id, "{s}-brush", .{id_prefix}) catch "ed-texture-paint-brush", state.texture_paint_brush.label(), 74, false)).clicked) {
        cycleBrush(state);
    }
    var stencil_id: [80]u8 = undefined;
    if ((try ui_widgets.button(ui, std.fmt.bufPrint(&stencil_id, "{s}-stencil", .{id_prefix}) catch "ed-texture-paint-stencil", state.texture_paint_stencil.label(), 78, state.texture_paint_stencil != .none)).clicked) {
        cycleStencil(state);
    }
    var fill_id: [80]u8 = undefined;
    if ((try ui_widgets.button(ui, std.fmt.bufPrint(&fill_id, "{s}-fill", .{id_prefix}) catch "ed-texture-paint-fill", "Fill", 58, false)).clicked) {
        fillSelectedOrObject(state);
    }
    try core_ui.layout.endSameLine(ui);

    try ui.label("Paint Color");
    try ui_widgets.buildMaterialButtons(ui, state);
    try ui_widgets.compactMaterialSwatch(ui, "ed-texture-current-color", "Brush color", state.brush_color);
    state.brush_radius = try sliderWithLabel(ui, id_prefix, "radius", "Size", state.brush_radius, 0.01, 0.22);
    state.texture_paint_opacity = try sliderWithLabel(ui, id_prefix, "opacity", "Opacity", state.texture_paint_opacity, 0.05, 1.0);
    state.texture_paint_hardness = try sliderWithLabel(ui, id_prefix, "hardness", "Hardness", state.texture_paint_hardness, 0.05, 1.0);
}

pub const PaintOptions = struct {
    radius: f32,
    opacity: f32,
    hardness: f32,
    noise: f32,
    brush: TexturePaintBrush,
    stencil: TexturePaintStencil,
};

pub fn paintTexture(pixels: []u8, size: u32, uv: editor_math.Vec2, color: shared_color.Color, options: PaintOptions) void {
    const radius_px = @max(1, @as(i32, @intFromFloat(options.radius * @as(f32, @floatFromInt(size)))));
    const cx = @as(i32, @intFromFloat(std.math.clamp(uv.x, 0.0, 0.9999) * @as(f32, @floatFromInt(size))));
    const cy = @as(i32, @intFromFloat(std.math.clamp(uv.y, 0.0, 0.9999) * @as(f32, @floatFromInt(size))));
    var y = cy - radius_px;
    while (y <= cy + radius_px) : (y += 1) {
        if (y < 0 or y >= @as(i32, @intCast(size))) continue;
        var x = cx - radius_px;
        while (x <= cx + radius_px) : (x += 1) {
            if (x < 0 or x >= @as(i32, @intCast(size))) continue;
            const sample_uv = pixelUv(size, x, y);
            const alpha = brushAlpha(x - cx, y - cy, radius_px, sample_uv, options);
            if (alpha <= 0.0) continue;
            blendPixel(pixels, size, x, y, color, alpha);
        }
    }
}

fn fillObjectTexture(pixels_obj: *SceneObject, color: shared_color.Color, opacity: f32, stencil: TexturePaintStencil) void {
    const size = TextureSize;
    for (0..size) |y| {
        for (0..size) |x| {
            const ix: i32 = @intCast(x);
            const iy: i32 = @intCast(y);
            const uv = pixelUv(size, ix, iy);
            const alpha = std.math.clamp(opacity, 0.0, 1.0) * stencilAlpha(stencil, uv);
            if (alpha > 0.0) blendPixel(pixels_obj.texture, size, ix, iy, color, alpha);
        }
    }
}

fn fillFaceTexture(obj: *SceneObject, face: usize, color: shared_color.Color, opacity: f32, stencil: TexturePaintStencil) void {
    if (face + 2 >= obj.mesh.indices.len) return;
    const ia = obj.mesh.indices[face];
    const ib = obj.mesh.indices[face + 1];
    const ic = obj.mesh.indices[face + 2];
    if (ia >= obj.mesh.vertices.len or ib >= obj.mesh.vertices.len or ic >= obj.mesh.vertices.len) return;
    const a = obj.mesh.vertices[ia].uv;
    const b = obj.mesh.vertices[ib].uv;
    const c = obj.mesh.vertices[ic].uv;
    const size = TextureSize;
    for (0..size) |y| {
        for (0..size) |x| {
            const ix: i32 = @intCast(x);
            const iy: i32 = @intCast(y);
            const uv = pixelUv(size, ix, iy);
            if (!pointInTriangle(uv, a, b, c)) continue;
            const alpha = std.math.clamp(opacity, 0.0, 1.0) * stencilAlpha(stencil, uv);
            if (alpha > 0.0) blendPixel(obj.texture, size, ix, iy, color, alpha);
        }
    }
}

fn brushAlpha(dx: i32, dy: i32, radius_px: i32, uv: editor_math.Vec2, options: PaintOptions) f32 {
    const fx = @as(f32, @floatFromInt(dx));
    const fy = @as(f32, @floatFromInt(dy));
    const radius = @as(f32, @floatFromInt(radius_px));
    const dist = switch (options.brush) {
        .hard_square => @max(@abs(fx), @abs(fy)) / radius,
        .soft_round, .noise => @sqrt(fx * fx + fy * fy) / radius,
    };
    if (dist > 1.0) return 0.0;
    const hard = std.math.clamp(options.hardness, 0.01, 1.0);
    var alpha: f32 = if (dist <= hard) 1.0 else 1.0 - ((dist - hard) / @max(0.001, 1.0 - hard));
    if (options.brush == .noise) alpha *= 1.0 - options.noise * hashNoise(uv);
    alpha *= stencilAlpha(options.stencil, uv);
    alpha *= std.math.clamp(options.opacity, 0.0, 1.0);
    return std.math.clamp(alpha, 0.0, 1.0);
}

fn stencilAlpha(stencil: TexturePaintStencil, uv: editor_math.Vec2) f32 {
    return switch (stencil) {
        .none => 1.0,
        .checker => if (((@as(i32, @intFromFloat(uv.x * 16.0)) + @as(i32, @intFromFloat(uv.y * 16.0))) & 1) == 0) 1.0 else 0.18,
        .stripes => if ((@as(i32, @intFromFloat((uv.x + uv.y) * 24.0)) & 1) == 0) 1.0 else 0.0,
        .edge_wear => edgeWearAlpha(uv),
    };
}

fn edgeWearAlpha(uv: editor_math.Vec2) f32 {
    const edge = @min(@min(uv.x, 1.0 - uv.x), @min(uv.y, 1.0 - uv.y));
    return std.math.clamp(1.0 - edge * 8.0, 0.0, 1.0);
}

fn blendPixel(pixels: []u8, size: u32, x: i32, y: i32, color: shared_color.Color, alpha: f32) void {
    const idx = (@as(usize, @intCast(y)) * @as(usize, size) + @as(usize, @intCast(x))) * 4;
    pixels[idx] = lerpByte(pixels[idx], color.r, alpha);
    pixels[idx + 1] = lerpByte(pixels[idx + 1], color.g, alpha);
    pixels[idx + 2] = lerpByte(pixels[idx + 2], color.b, alpha);
    pixels[idx + 3] = 255;
}

fn lerpByte(a: u8, b: u8, t: f32) u8 {
    const af = @as(f32, @floatFromInt(a));
    const bf = @as(f32, @floatFromInt(b));
    return @intFromFloat(std.math.clamp(af + (bf - af) * t, 0.0, 255.0));
}

fn pixelUv(size: u32, x: i32, y: i32) editor_math.Vec2 {
    const denom = @as(f32, @floatFromInt(size));
    return .{
        .x = (@as(f32, @floatFromInt(x)) + 0.5) / denom,
        .y = (@as(f32, @floatFromInt(y)) + 0.5) / denom,
    };
}

fn pointInTriangle(p: editor_math.Vec2, a: editor_math.Vec2, b: editor_math.Vec2, c: editor_math.Vec2) bool {
    const d1 = sign2d(p, a, b);
    const d2 = sign2d(p, b, c);
    const d3 = sign2d(p, c, a);
    const has_neg = d1 < 0 or d2 < 0 or d3 < 0;
    const has_pos = d1 > 0 or d2 > 0 or d3 > 0;
    return !(has_neg and has_pos);
}

fn sign2d(p1: editor_math.Vec2, p2: editor_math.Vec2, p3: editor_math.Vec2) f32 {
    return (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y);
}

fn hashNoise(uv: editor_math.Vec2) f32 {
    const x: u32 = @intFromFloat(@abs(uv.x) * 4096.0);
    const y: u32 = @intFromFloat(@abs(uv.y) * 4096.0);
    var n = x *% 374761393 +% y *% 668265263;
    n = (n ^ (n >> 13)) *% 1274126177;
    return @as(f32, @floatFromInt(n & 0xffff)) / 65535.0;
}

fn sliderWithLabel(ui: *core_ui.UiContext, id_prefix: []const u8, id_suffix: []const u8, label: []const u8, value: f32, min: f32, max: f32) !f32 {
    var label_buf: [80]u8 = undefined;
    try ui_widgets.compactInfo(ui, sliderDisplay(label, value, min, max, &label_buf));
    var id_buf: [96]u8 = undefined;
    const result = try core_ui.widgets_input.slider(ui, .{
        .id = std.fmt.bufPrint(&id_buf, "{s}-{s}", .{ id_prefix, id_suffix }) catch id_suffix,
        .value = value,
        .min = min,
        .max = max,
    });
    return if (result.changed) result.value else value;
}

fn sliderDisplay(label: []const u8, value: f32, min: f32, max: f32, buf: []u8) []const u8 {
    const normalized = std.math.clamp((value - min) / @max(0.0001, max - min), 0.0, 1.0);
    if (std.mem.eql(u8, label, "Size")) {
        return std.fmt.bufPrint(buf, "{s}  {d:.0}%", .{ label, normalized * 100.0 }) catch label;
    }
    return std.fmt.bufPrint(buf, "{s}  {d:.0}%", .{ label, value * 100.0 }) catch label;
}

test "soft brush blends selected pixels" {
    var pixels = [_]u8{0} ** (8 * 8 * 4);
    paintTexture(&pixels, 8, .{ .x = 0.5, .y = 0.5 }, .{ .r = 200, .g = 100, .b = 50, .a = 255 }, .{
        .radius = 0.25,
        .opacity = 0.5,
        .hardness = 1.0,
        .noise = 0.0,
        .brush = .soft_round,
        .stencil = .none,
    });
    const idx = (4 * 8 + 4) * 4;
    try std.testing.expect(pixels[idx] > 90 and pixels[idx] < 110);
    try std.testing.expectEqual(@as(u8, 255), pixels[idx + 3]);
}

test "stripe stencil skips some pixels" {
    var pixels = [_]u8{0} ** (8 * 8 * 4);
    paintTexture(&pixels, 8, .{ .x = 0.5, .y = 0.5 }, .{ .r = 255, .g = 0, .b = 0, .a = 255 }, .{
        .radius = 0.5,
        .opacity = 1.0,
        .hardness = 1.0,
        .noise = 0.0,
        .brush = .hard_square,
        .stencil = .stripes,
    });
    var painted: usize = 0;
    var skipped_inside: usize = 0;
    for (0..8) |y| {
        for (0..8) |x| {
            const idx = (y * 8 + x) * 4;
            if (pixels[idx] == 255) painted += 1 else skipped_inside += 1;
        }
    }
    try std.testing.expect(painted > 0);
    try std.testing.expect(skipped_inside > 0);
}
