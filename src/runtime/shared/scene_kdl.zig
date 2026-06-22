const std = @import("std");
const kdl = @import("kdl");
const scene_document = @import("scene_document.zig");
const scene_physics = @import("scene_physics.zig");
const scene_surface = @import("scene_surface.zig");
const scene_animation = @import("scene_animation.zig");
const scene_animation_kdl = @import("scene_animation_kdl.zig");
const scene_kdl_values = @import("scene_kdl_values.zig");
const scene_kdl_entity_builder = @import("scene_kdl_entity_builder.zig");
const scene_kdl_format = @import("scene_kdl_format.zig");
const scene_blockout = @import("scene_blockout.zig");
const scene_marker = @import("scene_marker.zig");

pub const formatScene = scene_kdl_format.formatScene;

pub fn parseSceneDocument(allocator: std.mem.Allocator, source: []const u8) !scene_document.SceneDocument {
    const buffer = try allocator.allocSentinel(u8, source.len, 0);
    defer allocator.free(buffer);
    @memcpy(buffer, source);

    var parser = kdl.Parser.init(buffer);

    var schema_version: u32 = 1;
    var next_object_id: u64 = 1;
    var entities = std.ArrayList(scene_document.SceneEntity).empty;
    errdefer {
        for (entities.items) |*entity| entity.deinit(allocator);
        entities.deinit(allocator);
    }

    var depth: i32 = 0;
    var entity: ?scene_kdl_entity_builder.EntityBuilder = null;
    var section: ?[]const u8 = null;

    while (true) {
        const event = try parser.next();
        switch (event) {
            .node => |node| {
                if (depth == 0) {
                    if (!std.mem.eql(u8, node.val, "scene")) return error.InvalidSceneDocument;
                    continue;
                }
                if (depth == 1) {
                    if (!std.mem.eql(u8, node.val, "entity")) continue;
                    entity = scene_kdl_entity_builder.EntityBuilder.init(allocator);
                    section = null;
                    continue;
                }
                if (depth == 2) {
                    section = node.val;
                }
            },
            .prop => |prop| {
                if (depth == 0) {
                    const value = try scene_kdl_values.decodeValue(allocator, prop.val);
                    defer allocator.free(value);
                    if (std.mem.eql(u8, prop.key, "version")) {
                        schema_version = try scene_kdl_values.parseU32(value);
                    } else if (std.mem.eql(u8, prop.key, "next_object_id")) {
                        next_object_id = try scene_kdl_values.parseU64(value);
                    }
                    continue;
                }
                if (depth == 1) {
                    if (entity == null) continue;
                    const builder = &(entity orelse return error.InvalidSceneDocument);
                    const value = try scene_kdl_values.decodeValue(allocator, prop.val);
                    defer allocator.free(value);
                    if (std.mem.eql(u8, prop.key, "id")) {
                        builder.id = try scene_kdl_values.parseU64(value);
                    } else if (std.mem.eql(u8, prop.key, "name")) {
                        try builder.setName(value);
                    }
                    continue;
                }
                if (depth == 2) {
                    if (entity == null) continue;
                    const builder = &(entity orelse return error.InvalidSceneDocument);
                    const section_name = section orelse return error.InvalidSceneDocument;
                    const value = try scene_kdl_values.decodeValue(allocator, prop.val);
                    defer allocator.free(value);
                    try builder.applyProp(section_name, prop.key, value);
                }
            },
            .child_block_begin => depth += 1,
            .child_block_end => {
                depth -= 1;
                if (depth == 1 and entity != null) {
                    try entities.append(allocator, try entity.?.finish(allocator));
                    entity = null;
                    section = null;
                }
            },
            .arg, .invalid => return error.InvalidSceneDocument,
            .eof => break,
        }
    }

    if (depth != 0) return error.InvalidSceneDocument;

    const animation_doc = try scene_animation_kdl.parseAnimations(allocator, source);

    return .{
        .schema_version = schema_version,
        .next_object_id = next_object_id,
        .entities = try entities.toOwnedSlice(allocator),
        .animations = animation_doc.clips,
        .skeletons = animation_doc.skeletons,
    };
}

test "kdl scene parse and format round trip" {
    const source =
        \\scene version=1 next_object_id=3 {
        \\  entity id=1 name="Floor" {
        \\    transform position="0,0,0" rotation="0.1,0.2,0.3" scale="1,1,1"
        \\    material base_color="90,100,110,255" texture="textures/floor.png"
        \\    mesh primitive=plane width=8 depth=8
        \\    physics body=static
        \\  }
        \\}
        \\
    ;

    var document = try parseSceneDocument(std.testing.allocator, source);
    defer document.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), document.entities.len);
    try std.testing.expectEqualStrings("Floor", document.entities[0].name);
    try std.testing.expectEqual(@as(f32, 0.2), document.entities[0].rotation[1]);
    try std.testing.expect(document.entities[0].mesh == .primitive);
    try std.testing.expectEqual(scene_physics.BodyKind.static, document.entities[0].physics.?.kind);
    try std.testing.expect(document.entities[0].mesh.primitive.kind == .plane);

    const formatted = try formatScene(std.testing.allocator, document);
    defer std.testing.allocator.free(formatted);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "entity id=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "rotation=\"") != null);
}

test "kdl scene properties round trip" {
    const source =
        \\scene version=1 next_object_id=2 {
        \\  entity id=1 name="Plot" {
        \\    transform position="0,0,0" rotation="0,0,0" scale="1,1,1"
        \\    material base_color="102,136,86,255" texture="textures/plot.png"
        \\    mesh primitive=plane width=8 depth=6
        \\    properties role="village_green" scenario="village_center" occupied=true
        \\  }
        \\}
        \\
    ;

    var document = try parseSceneDocument(std.testing.allocator, source);
    defer document.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), document.entities[0].properties.len);
    try std.testing.expectEqualStrings("role", document.entities[0].properties[0].key);
    try std.testing.expectEqualStrings("village_green", document.entities[0].properties[0].value);
    try std.testing.expectEqualStrings("occupied", document.entities[0].properties[2].key);
    try std.testing.expectEqualStrings("true", document.entities[0].properties[2].value);

    const formatted = try formatScene(std.testing.allocator, document);
    defer std.testing.allocator.free(formatted);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "properties role=\"village_green\" scenario=\"village_center\" occupied=\"true\"") != null);
}

test "kdl scene animation and skeleton round trip" {
    const source =
        \\scene version=1 next_object_id=2 {
        \\  entity id=1 name="Actor" {
        \\    transform position="0,0,0" rotation="0,0,0" scale="1,1,1"
        \\    material base_color="255,255,255,255" texture="textures/actor.png"
        \\    mesh primitive=box width=1 height=1 depth=1
        \\    meta kind=mesh enabled=true visible=true cast_shadows=true receive_shadows=true
        \\  }
        \\  skeleton asset="actors/actor.glb" {
        \\    bone index=0 parent=-1 name="Root" rest_position="0,0,0" rest_rotation="0,0,0" rest_scale="1,1,1"
        \\    bone index=1 parent=0 name="Arm" rest_position="0,1,0" rest_rotation="0,0,0" rest_scale="1,1,1"
        \\  }
        \\  animation_clip id=1 name="Wave" duration=1 looping=true {
        \\    track target=object object_id=1 {
        \\      keyframe time=0 position="0,0,0" rotation="0,0,0" scale="1,1,1"
        \\      keyframe time=1 position="1,0,0" rotation="0,0,0" scale="1,1,1"
        \\    }
        \\    track target=bone object_id=1 bone_index=1 {
        \\      keyframe time=0.5 position="0,1,0" rotation="0,0.5,0" scale="1,1,1"
        \\    }
        \\    pose name="wave" {
        \\      snapshot target=object object_id=1 position="0,0.5,0" rotation="0,0,0" scale="1,1,1"
        \\    }
        \\  }
        \\}
        \\
    ;

    var document = try parseSceneDocument(std.testing.allocator, source);
    defer document.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), document.animations.len);
    try std.testing.expectEqual(@as(usize, 2), document.animations[0].tracks.len);
    try std.testing.expectEqual(@as(usize, 1), document.skeletons.len);
    try std.testing.expectEqual(@as(usize, 2), document.skeletons[0].bones.len);
    try std.testing.expectEqual(@as(usize, 1), document.animations[0].poses.len);
    try std.testing.expectEqualStrings("wave", document.animations[0].poses[0].name);

    const formatted = try formatScene(std.testing.allocator, document);
    defer std.testing.allocator.free(formatted);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "animation_clip") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "bone index=1") != null);
}

test "kdl scene blockout prism footprint round trip" {
    const source =
        \\scene version=1 next_object_id=2 {
        \\  entity id=1 name="Prism Cutter" {
        \\    transform position="0,0,0" rotation="0,0,0" scale="1,1,1"
        \\    material base_color="255,255,255,255" texture="textures/cutter.png"
        \\    mesh primitive=box width=1 height=1 depth=1
        \\    blockout kind=subtract_prism min="0,0,0" max="2,3,4" footprint="0,0; 2,0; 0,4"
        \\  }
        \\}
        \\
    ;

    var document = try parseSceneDocument(std.testing.allocator, source);
    defer document.deinit(std.testing.allocator);

    const intent = document.entities[0].blockout_intent.?;
    try std.testing.expectEqual(scene_blockout.Kind.subtract_prism, intent.kind);
    try std.testing.expectEqual(@as(usize, 3), intent.footprint.len);
    try std.testing.expectEqual(@as(f32, 2), intent.footprint[1][0]);
    try std.testing.expectEqual(@as(f32, 4), intent.footprint[2][1]);

    const formatted = try formatScene(std.testing.allocator, document);
    defer std.testing.allocator.free(formatted);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "footprint=\"0,0; 2,0; 0,4\"") != null);

    var round_trip = try parseSceneDocument(std.testing.allocator, formatted);
    defer round_trip.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 3), round_trip.entities[0].blockout_intent.?.footprint.len);
    try std.testing.expectEqual(@as(f32, 4), round_trip.entities[0].blockout_intent.?.footprint[2][1]);
}

test "kdl scene five-mode fields round trip" {
    const source =
        \\scene version=1 next_object_id=3 {
        \\  entity id=1 name="Trigger" {
        \\    transform position="0,0,0" rotation="0,0,0" scale="1,1,1"
        \\    material base_color="255,255,255,255" texture="textures/floor.png" lightmap="textures/floor_lm.png"
        \\    mesh primitive=box width=1 height=1 depth=1
        \\    meta kind=trigger enabled=true visible=true cast_shadows=true receive_shadows=true parent_id=2 layer="gameplay" variant="door_a" prop_asset="props/door"
        \\    physics body=static collider=box mass=1 friction=0.6 restitution=0 trigger=true
        \\    gameplay tag="switch" health=100 score=0 team=1 interactable=true
        \\    surface index=3 type=walkable
        \\  }
        \\  animation_clip id=1 name="PoseClip" duration=1 looping=false {
        \\    track target=object object_id=1 {
        \\      keyframe time=0 position="0,0,0" rotation="0,0,0" scale="1,1,1" key_position=true key_rotation=false key_scale=false interpolation="ease_in"
        \\    }
        \\    pose name="Open" {
        \\      snapshot target=object object_id=1 position="0,1,0" rotation="0,0.5,0" scale="1,1,1"
        \\    }
        \\  }
        \\}
        \\
    ;

    var document = try parseSceneDocument(std.testing.allocator, source);
    defer document.deinit(std.testing.allocator);

    const entity = document.entities[0];
    try std.testing.expectEqual(@as(?u64, 2), entity.parent_id);
    try std.testing.expectEqualStrings("gameplay", entity.layer);
    try std.testing.expectEqualStrings("door_a", entity.variant.?);
    try std.testing.expectEqualStrings("props/door", entity.prop_asset_id.?);
    try std.testing.expectEqualStrings("textures/floor_lm.png", entity.lightmap_path.?);
    try std.testing.expect(entity.physics.?.trigger);
    try std.testing.expect(entity.gameplay.?.interactable);
    try std.testing.expectEqual(@as(usize, 1), entity.face_surfaces.len);
    try std.testing.expectEqual(scene_surface.SurfaceType.walkable, entity.face_surfaces[0].surface_type);
    try std.testing.expectEqual(@as(usize, 3), entity.face_surfaces[0].face_index);

    try std.testing.expectEqual(@as(usize, 1), document.animations.len);
    const clip = document.animations[0];
    try std.testing.expectEqual(@as(usize, 1), clip.poses.len);
    try std.testing.expectEqualStrings("Open", clip.poses[0].name);
    try std.testing.expectEqual(scene_animation.Interpolation.ease_in, clip.tracks[0].keyframes[0].interpolation);
    try std.testing.expect(!clip.tracks[0].keyframes[0].channels.rotation);

    const formatted = try formatScene(std.testing.allocator, document);
    defer std.testing.allocator.free(formatted);

    var round_trip = try parseSceneDocument(std.testing.allocator, formatted);
    defer round_trip.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("textures/floor_lm.png", round_trip.entities[0].lightmap_path.?);
    try std.testing.expectEqualStrings("Open", round_trip.animations[0].poses[0].name);
}

test "kdl scene marker round trip" {
    const source =
        \\scene version=1 next_object_id=2 {
        \\  entity id=1 name="Player Start" {
        \\    transform position="1,0,2" rotation="0,1.57,0" scale="1,1,1"
        \\    material base_color="90,180,255,255" texture="textures/player_start.png"
        \\    mesh primitive=box width=0.4 height=1 depth=0.4
        \\    meta kind=marker enabled=true visible=true cast_shadows=false receive_shadows=false
        \\    marker kind=player_start shape=point id="start" group="" binding="controller:fps" radius=1 order=0
        \\  }
        \\}
        \\
    ;

    var document = try parseSceneDocument(std.testing.allocator, source);
    defer document.deinit(std.testing.allocator);

    try std.testing.expectEqual(scene_document.ObjectKind.marker, document.entities[0].object_kind);
    try std.testing.expectEqual(scene_marker.Kind.player_start, document.entities[0].marker.?.kind);
    try std.testing.expectEqualStrings("controller:fps", document.entities[0].marker.?.binding);

    const formatted = try formatScene(std.testing.allocator, document);
    defer std.testing.allocator.free(formatted);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "marker kind=player_start") != null);

    var round_trip = try parseSceneDocument(std.testing.allocator, formatted);
    defer round_trip.deinit(std.testing.allocator);
    try std.testing.expectEqual(scene_marker.Kind.player_start, round_trip.entities[0].marker.?.kind);
}

test "kdl scene marker round trips every marker kind" {
    inline for (std.meta.fields(scene_marker.Kind)) |field| {
        var marker = try scene_marker.defaultForKind(std.testing.allocator, @enumFromInt(field.value));
        defer marker.deinit(std.testing.allocator);
        const source = try std.fmt.allocPrint(
            std.testing.allocator,
            \\scene version=1 next_object_id=2 {{
            \\  entity id=1 name="{s}" {{
            \\    transform position="0,0,0" rotation="0,0,0" scale="1,1,1"
            \\    material base_color="90,180,255,255" texture="textures/marker.png"
            \\    mesh primitive=box width=0.4 height=1 depth=0.4
            \\    meta kind=marker enabled=true visible=true cast_shadows=false receive_shadows=false
            \\    marker kind={s} shape={s} id="{s}" group="{s}" binding="{s}" radius={d} order={d}
            \\  }}
            \\}}
            \\
        ,
            .{
                marker.kind.label(),
                marker.kind.name(),
                marker.shape.name(),
                marker.marker_id,
                marker.group,
                marker.binding,
                marker.radius,
                marker.order,
            },
        );
        defer std.testing.allocator.free(source);

        var document = try parseSceneDocument(std.testing.allocator, source);
        defer document.deinit(std.testing.allocator);
        try std.testing.expectEqual(@as(scene_marker.Kind, @enumFromInt(field.value)), document.entities[0].marker.?.kind);

        const formatted = try formatScene(std.testing.allocator, document);
        defer std.testing.allocator.free(formatted);
        var round_trip = try parseSceneDocument(std.testing.allocator, formatted);
        defer round_trip.deinit(std.testing.allocator);
        try std.testing.expectEqual(@as(scene_marker.Kind, @enumFromInt(field.value)), round_trip.entities[0].marker.?.kind);
        try round_trip.entities[0].marker.?.validate();
    }
}
