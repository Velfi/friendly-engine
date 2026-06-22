const std = @import("std");
const time = @import("friendly_engine").core.time;
const shared = @import("runtime_shared");
const friendly_engine = @import("friendly_engine");
const editor_draw = @import("editor_draw.zig");
const editor_frame_perf = @import("editor_frame_perf.zig");
const editor_viewport_gpu = @import("editor_viewport_gpu.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_skinning = @import("project_editor_skinning.zig");
const project_editor_view_nav = @import("project_editor_view_nav.zig");
const project_editor_viewport = @import("project_editor_viewport.zig");
const project_editor_life = @import("project_editor_life.zig");
const project_editor_terrain_preview = @import("project_editor_terrain_preview.zig");
const project_editor_spline_preview = @import("project_editor_spline_preview.zig");
const world_atmosphere = @import("project_editor_world_atmosphere.zig");
const project_editor_modes = @import("project_editor_modes.zig");
const scene_hierarchy = @import("editor_scene_hierarchy.zig");
const project_editor_gizmo_gallery = @import("project_editor_gizmo_gallery.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const editor_math = shared.editor_math;
const grass_runtime = friendly_engine.modules.grass.runtime;
const grass_camera_exclusion_radius_m: f32 = 1.25;

pub fn draw(
    state: *ProjectEditorState,
    renderer: *editor_draw.SDL_Renderer,
    text_renderer: *editor_draw.TextRenderer,
    rect: editor_draw.SDL_FRect,
    viewport_gpu: ?*editor_viewport_gpu.EditorViewportGpu,
    clear_color: shared.color.Color,
    use_atmosphere_sky: bool,
) !void {
    const vp_w: u32 = @intFromFloat(@max(1.0, rect.w));
    const vp_h: u32 = @intFromFloat(@max(1.0, rect.h));
    const gpu_ctx = viewport_gpu orelse return error.GpuViewportUnavailable;
    if (!gpu_ctx.use_gpu) return error.GpuViewportUnavailable;
    state.uses_gpu_viewport_texture = !state.uses_gpu_ui;

    try drawOffscreen(state, viewport_gpu, vp_w, vp_h, clear_color, use_atmosphere_sky);

    if (state.uses_gpu_ui) return;

    const w = @as(f32, @floatFromInt(vp_w));
    const h = @as(f32, @floatFromInt(vp_h));

    state.frame_perf.mark(.render_viewport_texture);
    try ensureGpuViewportTexture(state, renderer, gpu_ctx);
    if (state.viewport_texture) |tex| {
        if (!editor_draw.SDL_RenderTexture(renderer, tex, null, &rect)) return error.SdlTextureBlitFailed;
    }
    state.frame_perf.mark(.render_viewport_overlays);
    state.viewport_overlay_renderer = renderer;
    state.viewport_overlay_rect = rect;
    drawViewportOverlays(state, w, h);
    state.viewport_overlay_renderer = null;

    if (state.show_gizmo and (state.mode == .layout or project_editor_life.transformToolActive(state)) and state.selected_object != null) {
        try project_editor_viewport.drawTransformGizmoOverlay(state, renderer, rect);
    }
    try project_editor_gizmo_gallery.drawSdl(state, renderer, rect);
    try project_editor_view_nav.drawOverlay(state, renderer, text_renderer, rect);
}

pub fn drawOffscreen(
    state: *ProjectEditorState,
    viewport_gpu: ?*editor_viewport_gpu.EditorViewportGpu,
    vp_w: u32,
    vp_h: u32,
    clear_color: shared.color.Color,
    use_atmosphere_sky: bool,
) !void {
    const gpu_ctx = viewport_gpu orelse return error.GpuViewportUnavailable;
    if (!gpu_ctx.use_gpu) return error.GpuViewportUnavailable;

    state.frame_perf.mark(.render_viewport_gpu);
    try drawGpu(state, gpu_ctx, vp_w, vp_h, clear_color, use_atmosphere_sky);
}

pub fn compositeGpuViewport(
    state: *ProjectEditorState,
    gpu: *shared.gpu_api.GpuRenderer,
    rect: editor_draw.SDL_FRect,
) !void {
    const texture = gpu.offscreenColorTexture() orelse return error.GpuOffscreenTextureMissing;
    try gpu.drawGpuTextureRect(texture, rect.x, rect.y, rect.w, rect.h);
    _ = state;
}

fn drawViewportOverlays(state: *ProjectEditorState, vp_w: f32, vp_h: f32) void {
    if (state.mode == .layout or state.selection_scope == .marker or selectedObjectIsMarker(state)) {
        project_editor_viewport.drawObjectMarkers(state, vp_w, vp_h);
    }
    if ((state.mode == .architecture_creation or (state.mode == .prop_creation and state.prop_tool == .edit)) and state.selected_object != null) {
        project_editor_viewport.drawEditVertices(state, vp_w, vp_h);
        project_editor_viewport.drawSelectedEdge(state, vp_w, vp_h);
        project_editor_viewport.drawSelectedFace(state, vp_w, vp_h);
    }
    if (state.mode == .architecture_creation and state.architecture_tool.isBlockoutDrawTool() and state.csg_preview_live and state.blockout_drag_start != null and state.blockout_drag_end != null) {
        project_editor_viewport.drawBlockoutPreview(state, vp_w, vp_h);
    }
    if (state.mode == .architecture_creation and state.architecture_tool == .wall) {
        project_editor_viewport.drawWallOutlinePreview(state, vp_w, vp_h);
    }
    project_editor_viewport.drawSelectionBox(state);
    project_editor_modes.drawViewportOverlays(state, vp_w, vp_h);
}

fn selectedObjectIsMarker(state: *const ProjectEditorState) bool {
    const idx = state.selected_object orelse return false;
    if (idx >= state.objects.items.len) return false;
    return state.objects.items[idx].marker != null;
}

fn shouldRenderObjectMesh(obj: *const project_editor_state.SceneObject) bool {
    if (obj.marker != null) return false;
    return obj.mesh.vertices.len > 0 and obj.mesh.indices.len > 0;
}

fn drawGpu(
    state: *ProjectEditorState,
    viewport_gpu: *editor_viewport_gpu.EditorViewportGpu,
    vp_w: u32,
    vp_h: u32,
    clear_color: shared.color.Color,
    use_atmosphere_sky: bool,
) !void {
    const gpu = &viewport_gpu.gpu_renderer.?;
    const projection_mode = project_editor_state.projectionMode(state);

    const begin_frame_start = time.monotonicNs();
    try gpu.beginOffscreenFrame(vp_w, vp_h, if (use_atmosphere_sky) world_atmosphere.skyColor(state) else clear_color);
    recordGpuScope(state, .gpu_begin_frame, begin_frame_start);
    defer {
        const end_frame_start = time.monotonicNs();
        gpu.endOffscreenFrame();
        recordGpuScope(state, .gpu_end_frame, end_frame_start);
    }

    const collect_scene_start = time.monotonicNs();
    var gpu_objects: std.ArrayList(shared.gpu_backend.SceneGpuObject) = .empty;
    defer gpu_objects.deinit(state.allocator);
    var scene_object_mesh_indices: std.ArrayList(usize) = .empty;
    defer scene_object_mesh_indices.deinit(state.allocator);
    for (state.objects.items, 0..) |*obj, idx| {
        if (!project_editor_state.objectVisible(state, obj)) continue;
        if (!obj.enabled or !obj.renderer_visible) continue;
        if (!shouldRenderObjectMesh(obj)) continue;
        try scene_object_mesh_indices.append(state.allocator, idx);
        try gpu_objects.append(state.allocator, .{
            .mesh = &obj.mesh,
            .texture = obj.texture,
            .base_color = obj.base_color,
        });
    }
    const terrain_mesh_base: usize = gpu_objects.items.len;
    var terrain_mesh_end: usize = terrain_mesh_base;
    const draw_world_context = project_editor_state.worldContextVisible(state);
    if (draw_world_context) {
        try project_editor_terrain_preview.appendGpuObjects(state, &gpu_objects);
        terrain_mesh_end = gpu_objects.items.len;
    }
    if (draw_world_context) try project_editor_spline_preview.appendGpuObjects(state, &gpu_objects);
    recordGpuScope(state, .gpu_collect_scene, collect_scene_start);

    const sync_scene_start = time.monotonicNs();
    try gpu.syncSceneObjects(gpu_objects.items);
    recordGpuScope(state, .gpu_sync_scene, sync_scene_start);

    const lighting_start = time.monotonicNs();
    var lighting = world_atmosphere.buildFrameLighting(state);
    if (state.mode == .prop_creation) {
        lighting.sun_direction = shared.render_lighting.defaultSunDirection();
        lighting.sun_color = .{ .r = 255, .g = 246, .b = 226, .a = 255 };
        lighting.sun_intensity = 0.95;
        lighting.ambient = 0.62;
        lighting.shadows_enabled = false;
        lighting.fog.enabled = false;
    }
    var light_objects: std.ArrayList(shared.render_lighting.EditorLightObject) = .empty;
    defer light_objects.deinit(state.allocator);
    for (state.objects.items) |*obj| {
        if (!project_editor_state.objectVisible(state, obj)) continue;
        if (obj.marker != null) continue;
        try light_objects.append(state.allocator, .{
            .object_kind = obj.object_kind,
            .enabled = obj.enabled,
            .position = obj.position,
            .base_color = obj.base_color,
        });
    }
    shared.render_lighting.gatherEditorLights(&lighting, light_objects.items, null, null);
    gpu.setFrameLighting(lighting);
    gpu.setFrameSky(if (use_atmosphere_sky) world_atmosphere.buildFrameSky(state) else .{
        .enabled = false,
        .camera = state.camera,
    });
    recordGpuScope(state, .gpu_lighting, lighting_start);

    const build_commands_start = time.monotonicNs();
    var commands = shared.render_commands.CommandBuffer.init(state.allocator);
    defer commands.deinit();
    if (state.show_grid) try commands.appendGridDraw(gridDrawForState(state));

    const filled_shading = filledMeshShadingMode(state);
    var visible_meshes: std.ArrayList(shared.render_visibility.SceneMesh) = .empty;
    defer visible_meshes.deinit(state.allocator);
    if (filled_shading != null) {
        const shading = filled_shading.?;
        for (scene_object_mesh_indices.items) |idx| {
            const obj = &state.objects.items[idx];
            const transform = scene_hierarchy.objectWorldTransform(state.objects.items, idx).m;
            try visible_meshes.append(state.allocator, .{
                .transform = transform,
                .bounds = shared.render_visibility.boundsFromTransform(transform),
                .cast_shadows = obj.cast_shadows and shading.castsShadows(),
                .receive_shadows = obj.receive_shadows,
                .shading = shading,
                .projection_mode = projection_mode,
                .surface = if (project_editor_state.objectIsWaterSurface(obj)) .water else .@"opaque",
            });
        }
        state.visibility_stats = try shared.render_visibility.prepareSceneMeshes(
            &commands,
            visible_meshes.items,
            .{ .camera = state.camera, .max_distance = state.camera.far_clip_m },
        );
    } else {
        state.visibility_stats = .{};
    }
    if (draw_world_context) {
        const identity = editor_math.Mat4.identity().m;
        var mesh_index: usize = terrain_mesh_base;
        if (filled_shading != null) {
            const terrain_shading = filled_shading.?;
            while (mesh_index < terrain_mesh_end) : (mesh_index += 1) {
                try commands.appendSceneMesh(mesh_index, .{
                    .transform = identity,
                    .bounds = meshBounds(gpu_objects.items[mesh_index].mesh),
                    .cast_shadows = terrain_shading.castsShadows(),
                    .shading = terrain_shading,
                    .double_sided = true,
                    .projection_mode = projection_mode,
                }, state.camera, 0);
            }
            while (mesh_index < gpu_objects.items.len) : (mesh_index += 1) {
                try commands.appendSceneMesh(mesh_index, .{
                    .transform = identity,
                    .bounds = shared.render_visibility.boundsFromTransform(identity),
                    .cast_shadows = terrain_shading.castsShadows(),
                    .shading = terrain_shading,
                    .projection_mode = projection_mode,
                }, state.camera, 0);
            }
        }
        if (drawsWireframe(state)) {
            mesh_index = terrain_mesh_base;
            while (mesh_index < gpu_objects.items.len) : (mesh_index += 1) {
                try commands.appendWireframeMeshWithProjection(mesh_index, identity, state.camera, 0, projection_mode);
            }
        }
    }
    if (draw_world_context and filled_shading != null) {
        try appendEditorGrassPreview(state, &commands);
    }
    if (drawsWireframe(state)) {
        for (scene_object_mesh_indices.items, 0..) |idx, mesh_index| {
            try commands.appendWireframeMeshWithProjection(mesh_index, scene_hierarchy.objectWorldTransform(state.objects.items, idx).m, state.camera, 0, projection_mode);
        }
    }
    recordGpuScope(state, .gpu_build_commands, build_commands_start);

    const submit_commands_start = time.monotonicNs();
    try gpu.submitCommands(&commands);
    recordGpuScope(state, .gpu_submit_commands, submit_commands_start);
    state.render_command_stats = gpu.lastCommandStats();
}

fn meshBounds(mesh: *const shared.geometry.Mesh) shared.render_visibility.Bounds {
    var bounds = shared.render_visibility.Bounds{
        .min = .{
            .x = std.math.inf(f32),
            .y = std.math.inf(f32),
            .z = std.math.inf(f32),
        },
        .max = .{
            .x = -std.math.inf(f32),
            .y = -std.math.inf(f32),
            .z = -std.math.inf(f32),
        },
    };
    for (mesh.vertices) |vertex| {
        const p = vertex.position;
        bounds.min.x = @min(bounds.min.x, p.x);
        bounds.min.y = @min(bounds.min.y, p.y);
        bounds.min.z = @min(bounds.min.z, p.z);
        bounds.max.x = @max(bounds.max.x, p.x);
        bounds.max.y = @max(bounds.max.y, p.y);
        bounds.max.z = @max(bounds.max.z, p.z);
    }
    if (mesh.vertices.len == 0) {
        bounds.min = .{ .x = 0, .y = 0, .z = 0 };
        bounds.max = .{ .x = 0, .y = 0, .z = 0 };
    }
    return bounds;
}

fn appendEditorGrassPreview(state: *ProjectEditorState, commands: *shared.render_commands.CommandBuffer) !void {
    const camera_pos = state.camera.eye();
    var visible_instances: std.ArrayList(shared.render_commands.GrassInstance) = .empty;
    defer visible_instances.deinit(state.allocator);

    for (state.terrain_preview.entries.items) |*entry| {
        const grass = &(entry.grass_preview orelse continue);
        const fade = grass_runtime.batchFadeFactor(.{
            .cull_distance_m = grass.meta.controls.cull_distance_m,
            .fade_distance_m = grass.meta.controls.fade_distance_m,
        }, .{ .x = camera_pos.x, .y = camera_pos.y, .z = camera_pos.z }, grass.center) orelse continue;

        visible_instances.clearRetainingCapacity();
        for (grass.instances) |instance| {
            const sanitized = sanitizedGrassInstance(instance) orelse continue;
            if (grassInstanceTooCloseToCamera(sanitized, camera_pos)) continue;
            try visible_instances.append(state.allocator, sanitized);
        }
        if (visible_instances.items.len == 0) continue;

        try commands.appendGrass(visible_instances.items, &.{}, state.camera, .{
            .instance_offset = 0,
            .instance_count = 0,
            .influencer_offset = 0,
            .influencer_count = 0,
            .camera = state.camera,
            .cull_fade = fade,
            .wind_direction_deg = grass.meta.controls.wind_direction_deg,
            .wind_speed_mps = grass.meta.controls.wind_speed_mps,
            .wind_strength = grass.meta.controls.wind_strength,
            .bend_strength = grass.meta.controls.bend_strength,
            .stiffness = grass.meta.controls.stiffness,
        }, 0);
    }
}

fn sanitizedGrassInstance(instance: shared.render_commands.GrassInstance) ?shared.render_commands.GrassInstance {
    if (!finite3(instance.position)) return null;
    if (!finite3(instance.normal)) return null;
    if (!std.math.isFinite(instance.height) or !std.math.isFinite(instance.width) or
        !std.math.isFinite(instance.yaw) or !std.math.isFinite(instance.phase))
    {
        return null;
    }
    if (instance.height <= 0 or instance.width <= 0) return null;
    const len_sq = dot3(instance.normal, instance.normal);
    if (!std.math.isFinite(len_sq) or len_sq <= 0.0001) return null;
    var result = instance;
    const inv_len = 1.0 / @sqrt(len_sq);
    result.normal = .{
        instance.normal[0] * inv_len,
        instance.normal[1] * inv_len,
        instance.normal[2] * inv_len,
    };
    return result;
}

fn grassInstanceTooCloseToCamera(instance: shared.render_commands.GrassInstance, camera_pos: editor_math.Vec3) bool {
    const dx = instance.position[0] - camera_pos.x;
    const dy = instance.position[1] - camera_pos.y;
    const dz = instance.position[2] - camera_pos.z;
    const radius = @max(grass_camera_exclusion_radius_m, instance.height + instance.width);
    return dx * dx + dy * dy + dz * dz < radius * radius;
}

fn finite3(value: [3]f32) bool {
    return std.math.isFinite(value[0]) and std.math.isFinite(value[1]) and std.math.isFinite(value[2]);
}

fn dot3(a: [3]f32, b: [3]f32) f32 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

fn recordGpuScope(state: *ProjectEditorState, scope: editor_frame_perf.Scope, start_ns: i128) void {
    const elapsed_ns = time.monotonicNs() - start_ns;
    const ms = if (elapsed_ns <= 0) 0 else @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, @floatFromInt(std.time.ns_per_ms));
    state.frame_perf.recordScope(scope, ms);
}

fn filledMeshShadingMode(state: *const ProjectEditorState) ?shared.render_commands.MeshShadingMode {
    return switch (state.shading_mode) {
        .wireframe => null,
        .solid => .solid,
        .material_preview => .material_preview,
        .lod_debug => .material_preview,
        .rendered => .rendered,
    };
}

fn drawsWireframe(state: *const ProjectEditorState) bool {
    return state.shading_mode == .wireframe or showsEditableWire(state);
}

fn showsEditableWire(state: *const ProjectEditorState) bool {
    return state.mode == .architecture_creation and state.selected_object != null;
}

fn gridDrawForState(state: *const ProjectEditorState) editor_math.GridDraw {
    const step = if (state.mode == .world_creation) state.world_grid_scale.meters() else 1.0;
    var grid = editor_math.GridDraw.centeredOnOrigin(state.camera, step);
    grid.projection_mode = project_editor_state.projectionMode(state);
    return grid;
}

fn ensureGpuViewportTexture(
    state: *ProjectEditorState,
    renderer: *editor_draw.SDL_Renderer,
    viewport_gpu: *editor_viewport_gpu.EditorViewportGpu,
) !void {
    const gpu = &viewport_gpu.gpu_renderer.?;
    const gpu_tex = gpu.offscreenColorTexture() orelse return error.GpuOffscreenTextureMissing;
    const tex_w = gpu.offscreenWidth();
    const tex_h = gpu.offscreenHeight();
    if (state.viewport_texture != null and
        state.viewport_texture_w == tex_w and
        state.viewport_texture_h == tex_h and
        state.viewport_texture_gpu_source == gpu_tex)
    {
        return;
    }

    if (state.viewport_texture) |existing| {
        editor_draw.SDL_DestroyTexture(existing);
        state.viewport_texture = null;
    }

    state.viewport_texture = try editor_draw.createTextureFromGpuTexture(
        renderer,
        @ptrCast(gpu_tex),
        tex_w,
        tex_h,
    );
    state.viewport_texture_w = tex_w;
    state.viewport_texture_h = tex_h;
    state.viewport_texture_gpu_source = gpu_tex;
}

test "viewport render modes map to filled mesh shading commands" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
    };

    state.shading_mode = .wireframe;
    try std.testing.expectEqual(@as(?shared.render_commands.MeshShadingMode, null), filledMeshShadingMode(&state));
    state.shading_mode = .solid;
    try std.testing.expectEqual(shared.render_commands.MeshShadingMode.solid, filledMeshShadingMode(&state).?);
    state.shading_mode = .material_preview;
    try std.testing.expectEqual(shared.render_commands.MeshShadingMode.material_preview, filledMeshShadingMode(&state).?);
    state.shading_mode = .lod_debug;
    try std.testing.expectEqual(shared.render_commands.MeshShadingMode.material_preview, filledMeshShadingMode(&state).?);
    state.shading_mode = .rendered;
    try std.testing.expectEqual(shared.render_commands.MeshShadingMode.rendered, filledMeshShadingMode(&state).?);
}

test "marker objects are excluded from scene mesh rendering" {
    var mesh = try shared.geometry.buildPrimitive(std.testing.allocator, .box, .{});
    defer mesh.deinit(std.testing.allocator);
    var marker = try shared.scene_marker.defaultForKind(std.testing.allocator, .trigger_volume);
    defer marker.deinit(std.testing.allocator);

    const visible_mesh = project_editor_state.SceneObject{
        .id = 1,
        .name = @constCast("mesh"),
        .mesh = mesh,
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = @constCast(""),
        .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    };
    try std.testing.expect(shouldRenderObjectMesh(&visible_mesh));

    var marker_mesh = visible_mesh;
    marker_mesh.id = 2;
    marker_mesh.name = @constCast("marker");
    marker_mesh.marker = marker;
    marker_mesh.object_kind = .marker;
    try std.testing.expect(!shouldRenderObjectMesh(&marker_mesh));

    var empty_mesh = visible_mesh;
    empty_mesh.id = 3;
    empty_mesh.name = @constCast("empty");
    empty_mesh.mesh = .{ .vertices = &.{}, .indices = &.{} };
    try std.testing.expect(!shouldRenderObjectMesh(&empty_mesh));
}

test "mesh bounds cover world-space terrain vertices" {
    const mesh = shared.geometry.Mesh{
        .vertices = @constCast(&[_]shared.geometry.Vertex{
            .{
                .position = .{ .x = 128, .y = -2, .z = 256 },
                .normal = .{ .x = 0, .y = 1, .z = 0 },
                .uv = .{ .x = 0, .y = 0 },
            },
            .{
                .position = .{ .x = 384, .y = 12, .z = 512 },
                .normal = .{ .x = 0, .y = 1, .z = 0 },
                .uv = .{ .x = 1, .y = 1 },
            },
        }),
        .indices = @constCast(&[_]u32{ 0, 1, 0 }),
    };
    const bounds = meshBounds(&mesh);
    try std.testing.expectEqual(@as(f32, 128), bounds.min.x);
    try std.testing.expectEqual(@as(f32, -2), bounds.min.y);
    try std.testing.expectEqual(@as(f32, 256), bounds.min.z);
    try std.testing.expectEqual(@as(f32, 384), bounds.max.x);
    try std.testing.expectEqual(@as(f32, 12), bounds.max.y);
    try std.testing.expectEqual(@as(f32, 512), bounds.max.z);
}
