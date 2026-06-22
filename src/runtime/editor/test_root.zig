//! Test root for the editor module.
//!
//! `build.zig` builds the editor test binary from this file rather than
//! `main.zig`. Zig only resolves the root file's top-level declarations, then
//! discovers tests in other files solely when they are referenced from there
//! (lazy analysis). `main.zig` reaches the editor graph only through `pub fn
//! main`, which the test runner never calls, so rooting tests at it analyzes
//! zero editor files and runs zero tests.
//!
//! Mirroring `shared/mod.zig`, every editor source file is re-exported below as
//! a top-level declaration so each is resolved and its top-level `test {}`
//! blocks run. New editor files must be added here or their tests are silently
//! skipped.

pub const app = @import("app.zig");
pub const command_palette_fuzzy = @import("command_palette_fuzzy.zig");
pub const command_palette_search = @import("command_palette_search.zig");
pub const desktop_backend = @import("desktop_backend.zig");
pub const editor_commands = @import("editor_commands.zig");
pub const editor_core_ui = @import("editor_core_ui.zig");
pub const editor_core_ui_draw = @import("editor_core_ui_draw.zig");
pub const editor_core_ui_draw_icons = @import("editor_core_ui_draw_icons.zig");
pub const editor_core_ui_gpu = @import("editor_core_ui_gpu.zig");
pub const editor_core_ui_input = @import("editor_core_ui_input.zig");
pub const editor_display = @import("editor_display.zig");
pub const editor_draw = @import("editor_draw.zig");
pub const editor_draw_primitives = @import("editor_draw_primitives.zig");
pub const editor_frame_perf = @import("editor_frame_perf.zig");
pub const editor_icon_atlas = @import("editor_icon_atlas.zig");
pub const editor_raycast = @import("editor_raycast.zig");
pub const editor_gesture = @import("editor_gesture.zig");
pub const editor_selection = @import("editor_selection.zig");
pub const editor_scene_hierarchy = @import("editor_scene_hierarchy.zig");
pub const editor_scene_object = @import("editor_scene_object.zig");
pub const editor_sdf_atlas = @import("editor_sdf_atlas.zig");
pub const editor_settings = @import("editor_settings.zig");
pub const editor_shortcuts = @import("editor_shortcuts.zig");
pub const editor_text_atlas = @import("editor_text_atlas.zig");
pub const editor_ui_batch = @import("editor_ui_batch.zig");
pub const editor_viewport_gpu = @import("editor_viewport_gpu.zig");
pub const main = @import("main.zig");
pub const menu = @import("menu.zig");
pub const options = @import("options.zig");
pub const pm_apply_input = @import("pm_apply_input.zig");
pub const pm_presets = @import("pm_presets.zig");
pub const pm_state = @import("pm_state.zig");
pub const pm_state_config = @import("pm_state_config.zig");
pub const pm_state_projects = @import("pm_state_projects.zig");
pub const pm_types = @import("pm_types.zig");
pub const pm_ui = @import("pm_ui.zig");
pub const pm_ui_build = @import("pm_ui_build.zig");
pub const pm_util = @import("pm_util.zig");
pub const project_editor = @import("project_editor.zig");
pub const project_editor_architecture = @import("project_editor_architecture.zig");
pub const project_editor_architecture_curve = @import("project_editor_architecture_curve.zig");
pub const project_editor_asset_browser = @import("project_editor_asset_browser.zig");
pub const project_editor_blockout = @import("project_editor_blockout.zig");
pub const project_editor_blockout_primitives = @import("project_editor_blockout_primitives.zig");
pub const project_editor_blockout_resize = @import("project_editor_blockout_resize.zig");
pub const project_editor_build = @import("project_editor_build.zig");
pub const project_editor_command_dispatch = @import("project_editor_command_dispatch.zig");
pub const project_editor_command_palette = @import("project_editor_command_palette.zig");
pub const project_editor_concept_paint = @import("project_editor_concept_paint.zig");
pub const project_editor_dirty_cells = @import("project_editor_dirty_cells.zig");
pub const project_editor_edit = @import("project_editor_edit.zig");
pub const project_editor_edit_gizmo = @import("project_editor_edit_gizmo.zig");
pub const project_editor_edit_undo = @import("project_editor_edit_undo.zig");
pub const project_editor_input = @import("project_editor_input.zig");
pub const project_editor_input_cancel = @import("project_editor_input_cancel.zig");
pub const project_editor_input_cancel_tests = @import("project_editor_input_cancel_tests.zig");
pub const project_editor_input_drag = @import("project_editor_input_drag.zig");
pub const project_editor_input_drag_tests = @import("project_editor_input_drag_tests.zig");
pub const project_editor_input_keyboard = @import("project_editor_input_keyboard.zig");
pub const project_editor_input_viewport = @import("project_editor_input_viewport.zig");
pub const project_editor_input_walk = @import("project_editor_input_walk.zig");
pub const project_editor_life = @import("project_editor_life.zig");
pub const project_editor_life_gizmo = @import("project_editor_life_gizmo.zig");
pub const project_editor_material_apply = @import("project_editor_material_apply.zig");
pub const project_editor_material_faces = @import("project_editor_material_faces.zig");
pub const project_editor_materials = @import("project_editor_materials.zig");
pub const project_editor_marker = @import("project_editor_marker.zig");
pub const project_editor_mode_config = @import("project_editor_mode_config.zig");
pub const project_editor_mode_gems = @import("project_editor_mode_gems.zig");
pub const project_editor_modes = @import("project_editor_modes.zig");
pub const project_editor_physics = @import("project_editor_physics.zig");
pub const project_editor_preferences = @import("project_editor_preferences.zig");
pub const project_editor_prop = @import("project_editor_prop.zig");
pub const project_editor_prop_asset = @import("project_editor_prop_asset.zig");
pub const project_editor_prop_dialog = @import("project_editor_prop_dialog.zig");
pub const project_editor_prop_index = @import("project_editor_prop_index.zig");
pub const project_editor_prop_catalog = @import("project_editor_prop_catalog.zig");
pub const project_editor_prop_edit = @import("project_editor_prop_edit.zig");
pub const project_editor_prop_instantiate = @import("project_editor_prop_instantiate.zig");
pub const project_editor_prop_open = @import("project_editor_prop_open.zig");
pub const project_editor_prop_placement = @import("project_editor_prop_placement.zig");
pub const project_editor_prop_recent = @import("project_editor_prop_recent.zig");
pub const project_editor_prop_tests = @import("project_editor_prop_tests.zig");
pub const project_editor_render = @import("project_editor_render.zig");
pub const project_editor_render_viewport = @import("project_editor_render_viewport.zig");
pub const project_editor_scatter_preview = @import("project_editor_scatter_preview.zig");
pub const project_editor_scene = @import("project_editor_scene.zig");
pub const project_editor_scene_filter = @import("project_editor_scene_filter.zig");
pub const project_editor_scene_mesh_edit = @import("project_editor_scene_mesh_edit.zig");
pub const project_editor_scene_objects = @import("project_editor_scene_objects.zig");
pub const project_editor_scene_pick = @import("project_editor_scene_pick.zig");
pub const project_editor_scene_tests = @import("project_editor_scene_tests.zig");
pub const project_editor_skinning = @import("project_editor_skinning.zig");
pub const project_editor_spline_preview = @import("project_editor_spline_preview.zig");
pub const project_editor_spline_targets = @import("project_editor_spline_targets.zig");
pub const project_editor_state = @import("project_editor_state.zig");
pub const project_editor_surface_faces = @import("project_editor_surface_faces.zig");
pub const project_editor_terrain_preview = @import("project_editor_terrain_preview.zig");
pub const project_editor_terrain_undo_store = @import("project_editor_terrain_undo_store.zig");
pub const project_editor_texture_paint = @import("project_editor_texture_paint.zig");
pub const project_editor_types = @import("project_editor_types.zig");
pub const project_editor_ui_architecture = @import("project_editor_ui_architecture.zig");
pub const project_editor_ui_build = @import("project_editor_ui_build.zig");
pub const project_editor_ui_build_left = @import("project_editor_ui_build_left.zig");
pub const project_editor_ui_build_palette = @import("project_editor_ui_build_palette.zig");
pub const project_editor_ui_inspector = @import("project_editor_ui_inspector.zig");
pub const project_editor_ui_layout = @import("project_editor_ui_layout.zig");
pub const project_editor_ui_life = @import("project_editor_ui_life.zig");
pub const project_editor_ui_prop = @import("project_editor_ui_prop.zig");
pub const project_editor_ui_tree = @import("project_editor_ui_tree.zig");
pub const project_editor_ui_widgets = @import("project_editor_ui_widgets.zig");
pub const project_editor_ui_world = @import("project_editor_ui_world.zig");
pub const project_editor_view_nav = @import("project_editor_view_nav.zig");
pub const project_editor_viewport = @import("project_editor_viewport.zig");
pub const project_editor_world_atmosphere = @import("project_editor_world_atmosphere.zig");
pub const project_editor_world_authoring = @import("project_editor_world_authoring.zig");
pub const project_editor_world_authoring_atmosphere = @import("project_editor_world_authoring_atmosphere.zig");
pub const project_editor_world_authoring_csg = @import("project_editor_world_authoring_csg.zig");
pub const project_editor_world_authoring_layers = @import("project_editor_world_authoring_layers.zig");
pub const project_editor_world_authoring_manifest = @import("project_editor_world_authoring_manifest.zig");
pub const project_editor_world_authoring_ocean = @import("project_editor_world_authoring_ocean.zig");
pub const project_editor_world_authoring_scatter = @import("project_editor_world_authoring_scatter.zig");
pub const project_editor_world_authoring_scatter_mask = @import("project_editor_world_authoring_scatter_mask.zig");
pub const project_editor_world_authoring_splines = @import("project_editor_world_authoring_splines.zig");
pub const project_editor_world_authoring_terrain = @import("project_editor_world_authoring_terrain.zig");
pub const project_editor_world_authoring_terrain_serializer = @import("project_editor_world_authoring_terrain_serializer.zig");
pub const project_editor_world_bake = @import("project_editor_world_bake.zig");
pub const project_editor_world_curve_gizmos = @import("project_editor_world_curve_gizmos.zig");
pub const shape_operation = @import("shape_operation.zig");
pub const shape_source = @import("shape_source.zig");

const std = @import("std");

// Zig 0.16's lazy analysis means a file imported only as a namespace (as all
// of the above are) never gets its body analyzed, so its `test {}` blocks are
// silently never discovered or run. Force every submodule to be referenced so
// its tests are pulled into `zig build test`.
test {
    std.testing.refAllDecls(@This());
    inline for (comptime std.meta.declarations(@This())) |decl| {
        std.testing.refAllDecls(@field(@This(), decl.name));
    }
}
