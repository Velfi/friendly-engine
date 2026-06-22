pub const color = @import("color.zig");
pub const sdl = @import("sdl.zig");
pub const audio_decode = @import("audio_decode.zig");
pub const text_shape = @import("text_shape.zig");
pub const sdl_audio = @import("sdl_audio.zig");
pub const file_persistence = @import("file_persistence.zig");
pub const gpu_scene = @import("gpu_scene.zig");
pub const gpu_api = @import("gpu_api.zig");
pub const gpu_backend = @import("gpu_backend.zig");
pub const gpu_backend_sdl = @import("gpu_backend_sdl.zig");
pub const gpu_backend_sdl_overlay = @import("gpu_backend_sdl_overlay.zig");
pub const render_lighting = @import("render_lighting.zig");
pub const render_sky = @import("render_sky.zig");
pub const render_fog = @import("render_fog.zig");
pub const atmosphere_render = @import("atmosphere_render.zig");
pub const render_settings = @import("render_settings.zig");
pub const render_tonemap = @import("render_tonemap.zig");
pub const render_commands = @import("render_commands.zig");
pub const render_graph = @import("render_graph.zig");
pub const render_visibility = @import("render_visibility.zig");
pub const core_ui_overlay = @import("core_ui_overlay.zig");
pub const editor_command_ids = @import("editor_command_ids.zig");
pub const editor_command_catalog = @import("editor_command_catalog.zig");
pub const editor_mode_catalog = @import("editor_mode_catalog.zig");
pub const editor_control_commands = @import("editor_control_commands.zig");
pub const sdl_gpu = @import("sdl_gpu.zig");
pub const editor_math = @import("editor_math.zig");
pub const geometry = @import("geometry.zig");
pub const uv_atlas = @import("uv_atlas.zig");
pub const scene_io = @import("scene_io.zig");
pub const scene_kdl = @import("scene_kdl.zig");
pub const scene_binary = @import("scene_binary.zig");
pub const scene_document = @import("scene_document.zig");
pub const scene_physics = @import("scene_physics.zig");
pub const scene_physics_validate = @import("scene_physics_validate.zig");
pub const scene_blockout = @import("scene_blockout.zig");
pub const architecture = @import("architecture.zig");
pub const scene_texture = @import("scene_texture.zig");
pub const scene_surface = @import("scene_surface.zig");
pub const scene_gameplay = @import("scene_gameplay.zig");
pub const scene_marker = @import("scene_marker.zig");
pub const scene_marker_query = @import("scene_marker_query.zig");
pub const scene_animation = @import("scene_animation.zig");
pub const scene_skinning = @import("scene_skinning.zig");
pub const gltf_import = @import("gltf_import.zig");
pub const gltf_export = @import("gltf_export.zig");
pub const scene_resolve = @import("scene_resolve.zig");
pub const mesh_codec = @import("mesh_codec.zig");
pub const prop_asset_doc = @import("prop_asset_doc.zig");

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
