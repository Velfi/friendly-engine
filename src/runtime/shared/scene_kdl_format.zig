const std = @import("std");
const kdl = @import("kdl");
const scene_document = @import("scene_document.zig");
const scene_physics = @import("scene_physics.zig");
const scene_blockout = @import("scene_blockout.zig");
const scene_surface = @import("scene_surface.zig");
const scene_animation_kdl = @import("scene_animation_kdl.zig");
const scene_kdl_values = @import("scene_kdl_values.zig");

pub fn formatScene(
    allocator: std.mem.Allocator,
    document: scene_document.SceneDocument,
) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    const writer = &out.writer;

    try writer.print(
        "scene version={d} next_object_id={d} {{\n",
        .{ document.schema_version, document.next_object_id },
    );

    for (document.entities) |entity| {
        try writer.print("  entity id={d} name=\"{s}\" {{\n", .{ entity.id, entity.name });
        try writer.print(
            "    transform position=\"{d},{d},{d}\" rotation=\"{d},{d},{d}\" scale=\"{d},{d},{d}\"\n",
            .{
                entity.position[0],
                entity.position[1],
                entity.position[2],
                entity.rotation[0],
                entity.rotation[1],
                entity.rotation[2],
                entity.scale[0],
                entity.scale[1],
                entity.scale[2],
            },
        );
        try writer.print(
            "    material base_color=\"{d},{d},{d},{d}\" texture=\"{s}\"",
            .{ entity.base_color[0], entity.base_color[1], entity.base_color[2], entity.base_color[3], entity.texture_file },
        );
        if (entity.lightmap_path) |lightmap| try writer.print(" lightmap=\"{s}\"", .{lightmap});
        try writer.writeAll("\n");
        switch (entity.mesh) {
            .primitive => |prim| {
                try writer.print("    mesh primitive={s}", .{scene_document.primitiveKindName(prim.kind)});
                if (prim.kind == .plane) {
                    try writer.print(" width={d} depth={d}\n", .{ prim.params.width, prim.params.depth });
                } else if (prim.kind == .box) {
                    try writer.print(" width={d} height={d} depth={d}\n", .{ prim.params.width, prim.params.height, prim.params.depth });
                } else if (prim.kind == .cylinder) {
                    try writer.print(" radius={d} height={d}\n", .{ prim.params.radius, prim.params.height });
                } else {
                    try writer.print(" radius={d}\n", .{prim.params.radius});
                }
            },
            .asset => |path| {
                try writer.print("    mesh asset=\"{s}\"\n", .{path});
            },
        }
        try writer.print(
            "    meta kind={s} enabled={s} visible={s} cast_shadows={s} receive_shadows={s}",
            .{
                scene_document.objectKindName(entity.object_kind),
                scene_kdl_values.boolName(entity.enabled),
                scene_kdl_values.boolName(entity.renderer_visible),
                scene_kdl_values.boolName(entity.cast_shadows),
                scene_kdl_values.boolName(entity.receive_shadows),
            },
        );
        if (entity.skeleton_asset) |asset| try writer.print(" skeleton=\"{s}\"", .{asset});
        if (entity.parent_id) |parent_id| try writer.print(" parent_id={d}", .{parent_id});
        if (entity.layer.len > 0) try writer.print(" layer=\"{s}\"", .{entity.layer});
        if (entity.variant) |variant| try writer.print(" variant=\"{s}\"", .{variant});
        if (entity.prop_asset_id) |asset_id| try writer.print(" prop_asset=\"{s}\"", .{asset_id});
        try writer.writeAll("\n");
        if (entity.components.len > 0) {
            try writer.writeAll("    components names=\"");
            for (entity.components, 0..) |component, component_idx| {
                if (component_idx > 0) try writer.writeAll(",");
                try writer.writeAll(component);
            }
            try writer.writeAll("\"\n");
        }
        if (entity.properties.len > 0) {
            try writer.writeAll("    properties");
            for (entity.properties) |property| {
                const raw_value = if (std.mem.eql(u8, property.value, "\"\"")) "" else property.value;
                const value = try kdl.string_utils.makeInlineString(allocator, raw_value);
                defer allocator.free(value);
                if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
                    try writer.print(" {s}={s}", .{ property.key, value });
                } else {
                    try writer.print(" {s}=\"{s}\"", .{ property.key, value });
                }
            }
            try writer.writeAll("\n");
        }
        if (entity.physics) |physics| {
            try writer.print(
                "    physics body={s} collider={s} mass={d} friction={d} restitution={d}",
                .{
                    scene_physics.kindName(physics.kind),
                    scene_physics.colliderName(physics.collider),
                    physics.mass,
                    physics.friction,
                    physics.restitution,
                },
            );
            if (physics.trigger) try writer.print(" trigger={s}", .{scene_kdl_values.boolName(true)});
            try writer.writeAll("\n");
        }
        if (entity.blockout_intent) |intent| {
            try writer.print("    blockout kind={s}", .{intent.kind.name()});
            try writer.writeAll(" min=\"");
            try scene_blockout.formatTriple(writer, intent.min);
            try writer.writeAll("\" max=\"");
            try scene_blockout.formatTriple(writer, intent.max);
            try writer.writeAll("\"");
            if (intent.wall_min) |wall_min| {
                try writer.writeAll(" wall_min=\"");
                try scene_blockout.formatTriple(writer, wall_min);
                try writer.writeAll("\"");
            }
            if (intent.wall_max) |wall_max| {
                try writer.writeAll(" wall_max=\"");
                try scene_blockout.formatTriple(writer, wall_max);
                try writer.writeAll("\"");
            }
            if (intent.footprint.len > 0) {
                try writer.writeAll(" footprint=\"");
                try scene_blockout.formatPoint2List(writer, intent.footprint);
                try writer.writeAll("\"");
            }
            try writer.writeAll("\n");
        }
        if (entity.texture_transform.scale_world != 1.0 or entity.texture_transform.rotation_deg != 0.0 or
            entity.texture_transform.offset_u != 0.0 or entity.texture_transform.offset_v != 0.0)
        {
            try writer.print(
                "    texture scale_world={d} rotation_deg={d} offset_u={d} offset_v={d}\n",
                .{
                    entity.texture_transform.scale_world,
                    entity.texture_transform.rotation_deg,
                    entity.texture_transform.offset_u,
                    entity.texture_transform.offset_v,
                },
            );
        }
        for (entity.face_materials) |face| {
            try writer.print(
                "    face index={d} material=\"{s}\" scale_world={d} rotation_deg={d}\n",
                .{ face.face_index, face.material_path, face.transform.scale_world, face.transform.rotation_deg },
            );
        }
        for (entity.face_surfaces) |face| {
            try writer.print(
                "    surface index={d} type={s}\n",
                .{ face.face_index, face.surface_type.label() },
            );
        }
        if (entity.gameplay) |gameplay| {
            try writer.print(
                "    gameplay tag=\"{s}\" health={d} score={d} team={d}",
                .{ gameplay.tag, gameplay.health, gameplay.score, gameplay.team },
            );
            if (gameplay.interactable) try writer.print(" interactable={s}", .{scene_kdl_values.boolName(true)});
            try writer.writeAll("\n");
        }
        if (entity.marker) |marker| {
            try writer.print(
                "    marker kind={s} shape={s} id=\"{s}\" group=\"{s}\" binding=\"{s}\" radius={d} order={d}\n",
                .{
                    marker.kind.name(),
                    marker.shape.name(),
                    marker.marker_id,
                    marker.group,
                    marker.binding,
                    marker.radius,
                    marker.order,
                },
            );
        }
        try writer.writeAll("  }\n");
    }

    try scene_animation_kdl.writeAnimations(writer, document.animations, document.skeletons);

    try writer.writeAll("}\n");
    return out.toOwnedSlice();
}
