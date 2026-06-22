const std = @import("std");
const geometry = @import("geometry.zig");
const scene_document = @import("scene_document.zig");
const scene_physics = @import("scene_physics.zig");
const scene_blockout = @import("scene_blockout.zig");
const scene_texture = @import("scene_texture.zig");
const scene_surface = @import("scene_surface.zig");
const scene_gameplay = @import("scene_gameplay.zig");
const scene_marker = @import("scene_marker.zig");
const scene_kdl_values = @import("scene_kdl_values.zig");

pub const EntityBuilder = struct {
    allocator: std.mem.Allocator,
    id: u64 = 0,
    name: ?[]u8 = null,
    position: [3]f32 = .{ 0, 0, 0 },
    rotation: [3]f32 = .{ 0, 0, 0 },
    scale: [3]f32 = .{ 1, 1, 1 },
    base_color: [4]u8 = .{ 255, 255, 255, 255 },
    texture_file: ?[]u8 = null,
    mesh: ?scene_document.EntityMesh = null,
    object_kind: scene_document.ObjectKind = .mesh,
    enabled: bool = true,
    renderer_visible: bool = true,
    cast_shadows: bool = true,
    receive_shadows: bool = true,
    components: std.ArrayList([]u8) = .empty,
    properties: std.ArrayList(scene_document.Property) = .empty,
    physics: ?scene_physics.Body = null,
    blockout_intent: ?scene_blockout.Intent = null,
    texture_transform: scene_texture.Transform = .{},
    face_materials: std.ArrayList(scene_texture.FaceMaterial) = .empty,
    face_surfaces: std.ArrayList(scene_surface.FaceSurface) = .empty,
    surface_pending_index: usize = 0,
    gameplay: ?scene_gameplay.Component = null,
    marker: ?scene_marker.Marker = null,
    lightmap_path: ?[]u8 = null,
    skeleton_asset: ?[]u8 = null,
    parent_id: ?u64 = null,
    layer: []u8 = "",
    variant: ?[]u8 = null,
    prop_asset_id: ?[]u8 = null,

    pub fn init(allocator: std.mem.Allocator) EntityBuilder {
        return .{ .allocator = allocator };
    }

    pub fn setName(self: *EntityBuilder, value: []const u8) !void {
        if (self.name) |existing| self.allocator.free(existing);
        self.name = try self.allocator.dupe(u8, value);
    }

    pub fn applyProp(self: *EntityBuilder, section_name: []const u8, key: []const u8, value: []const u8) !void {
        if (std.mem.eql(u8, section_name, "transform")) {
            if (std.mem.eql(u8, key, "position")) {
                self.position = try scene_kdl_values.parseFloatTriple(value);
            } else if (std.mem.eql(u8, key, "rotation")) {
                self.rotation = try scene_kdl_values.parseFloatTriple(value);
            } else if (std.mem.eql(u8, key, "scale")) {
                self.scale = try scene_kdl_values.parseFloatTriple(value);
            }
            return;
        }
        if (std.mem.eql(u8, section_name, "material")) {
            if (std.mem.eql(u8, key, "base_color")) {
                self.base_color = try scene_kdl_values.parseU8Quad(value);
            } else if (std.mem.eql(u8, key, "texture")) {
                if (self.texture_file) |existing| self.allocator.free(existing);
                self.texture_file = try self.allocator.dupe(u8, value);
            } else if (std.mem.eql(u8, key, "lightmap")) {
                if (self.lightmap_path) |existing| self.allocator.free(existing);
                self.lightmap_path = try self.allocator.dupe(u8, value);
            }
            return;
        }
        if (std.mem.eql(u8, section_name, "mesh")) {
            var params: geometry.PrimitiveParams = .{};
            var kind: ?geometry.PrimitiveKind = null;
            if (self.mesh) |existing| switch (existing) {
                .primitive => |prim| {
                    kind = prim.kind;
                    params = prim.params;
                },
                .asset => |path| self.allocator.free(path),
            };

            if (std.mem.eql(u8, key, "primitive")) {
                kind = scene_document.primitiveKindFromName(value) orelse return error.InvalidValue;
            } else if (std.mem.eql(u8, key, "asset")) {
                self.mesh = .{ .asset = try self.allocator.dupe(u8, value) };
                return;
            } else if (std.mem.eql(u8, key, "width")) {
                params.width = try scene_kdl_values.parseF32(value);
            } else if (std.mem.eql(u8, key, "height")) {
                params.height = try scene_kdl_values.parseF32(value);
            } else if (std.mem.eql(u8, key, "depth")) {
                params.depth = try scene_kdl_values.parseF32(value);
            } else if (std.mem.eql(u8, key, "radius")) {
                params.radius = try scene_kdl_values.parseF32(value);
            }

            const resolved_kind = kind orelse return error.MissingPrimitiveKind;
            self.mesh = .{ .primitive = .{
                .kind = resolved_kind,
                .params = params,
            } };
            return;
        }
        if (std.mem.eql(u8, section_name, "meta")) {
            if (std.mem.eql(u8, key, "kind")) {
                self.object_kind = scene_document.objectKindFromName(value) orelse return error.InvalidValue;
            } else if (std.mem.eql(u8, key, "enabled")) {
                self.enabled = try scene_kdl_values.parseBool(value);
            } else if (std.mem.eql(u8, key, "visible")) {
                self.renderer_visible = try scene_kdl_values.parseBool(value);
            } else if (std.mem.eql(u8, key, "cast_shadows")) {
                self.cast_shadows = try scene_kdl_values.parseBool(value);
            } else if (std.mem.eql(u8, key, "receive_shadows")) {
                self.receive_shadows = try scene_kdl_values.parseBool(value);
            } else if (std.mem.eql(u8, key, "skeleton")) {
                if (self.skeleton_asset) |existing| self.allocator.free(existing);
                self.skeleton_asset = try self.allocator.dupe(u8, value);
            } else if (std.mem.eql(u8, key, "parent_id")) {
                self.parent_id = try scene_kdl_values.parseU64(value);
            } else if (std.mem.eql(u8, key, "layer")) {
                if (self.layer.len > 0) self.allocator.free(self.layer);
                self.layer = try self.allocator.dupe(u8, value);
            } else if (std.mem.eql(u8, key, "variant")) {
                if (self.variant) |existing| self.allocator.free(existing);
                self.variant = try self.allocator.dupe(u8, value);
            } else if (std.mem.eql(u8, key, "prop_asset")) {
                if (self.prop_asset_id) |existing| self.allocator.free(existing);
                self.prop_asset_id = try self.allocator.dupe(u8, value);
            }
            return;
        }
        if (std.mem.eql(u8, section_name, "components")) {
            if (std.mem.eql(u8, key, "names")) {
                try self.setComponents(value);
            }
            return;
        }
        if (std.mem.eql(u8, section_name, "properties")) {
            try self.properties.append(self.allocator, .{
                .key = try self.allocator.dupe(u8, key),
                .value = try self.allocator.dupe(u8, value),
            });
            return;
        }
        if (std.mem.eql(u8, section_name, "physics")) {
            if (std.mem.eql(u8, key, "body")) {
                var body = self.physics orelse scene_physics.Body{};
                body.kind = scene_physics.kindFromName(value) orelse return error.InvalidValue;
                self.physics = body;
            } else if (std.mem.eql(u8, key, "collider")) {
                var body = self.physics orelse scene_physics.Body{};
                body.collider = scene_physics.colliderFromName(value) orelse return error.InvalidValue;
                self.physics = body;
            } else if (std.mem.eql(u8, key, "mass")) {
                var body = self.physics orelse scene_physics.Body{};
                body.mass = try scene_kdl_values.parseF32(value);
                self.physics = body;
            } else if (std.mem.eql(u8, key, "friction")) {
                var body = self.physics orelse scene_physics.Body{};
                body.friction = try scene_kdl_values.parseF32(value);
                self.physics = body;
            } else if (std.mem.eql(u8, key, "restitution")) {
                var body = self.physics orelse scene_physics.Body{};
                body.restitution = try scene_kdl_values.parseF32(value);
                self.physics = body;
            } else if (std.mem.eql(u8, key, "trigger")) {
                var body = self.physics orelse scene_physics.Body{};
                body.trigger = try scene_kdl_values.parseBool(value);
                self.physics = body;
            }
            return;
        }
        if (std.mem.eql(u8, section_name, "blockout")) {
            var intent = self.blockout_intent orelse scene_blockout.Intent{
                .kind = .box_add,
                .min = .{ .x = 0, .y = 0, .z = 0 },
                .max = .{ .x = 1, .y = 1, .z = 1 },
            };
            if (std.mem.eql(u8, key, "kind")) {
                intent.kind = scene_blockout.Kind.fromName(value) orelse return error.InvalidValue;
            } else if (std.mem.eql(u8, key, "min")) {
                intent.min = scene_blockout.tripleToVec3(try scene_blockout.parseTriple(value));
            } else if (std.mem.eql(u8, key, "max")) {
                intent.max = scene_blockout.tripleToVec3(try scene_blockout.parseTriple(value));
            } else if (std.mem.eql(u8, key, "wall_min")) {
                intent.wall_min = scene_blockout.tripleToVec3(try scene_blockout.parseTriple(value));
            } else if (std.mem.eql(u8, key, "wall_max")) {
                intent.wall_max = scene_blockout.tripleToVec3(try scene_blockout.parseTriple(value));
            } else if (std.mem.eql(u8, key, "footprint")) {
                const footprint = try scene_blockout.parsePoint2List(self.allocator, value);
                self.allocator.free(intent.footprint);
                intent.footprint = footprint;
            }
            self.blockout_intent = intent;
            return;
        }
        if (std.mem.eql(u8, section_name, "texture")) {
            if (std.mem.eql(u8, key, "scale_world")) {
                self.texture_transform.scale_world = try scene_kdl_values.parseF32(value);
            } else if (std.mem.eql(u8, key, "rotation_deg")) {
                self.texture_transform.rotation_deg = try scene_kdl_values.parseF32(value);
            } else if (std.mem.eql(u8, key, "offset_u")) {
                self.texture_transform.offset_u = try scene_kdl_values.parseF32(value);
            } else if (std.mem.eql(u8, key, "offset_v")) {
                self.texture_transform.offset_v = try scene_kdl_values.parseF32(value);
            } else if (std.mem.eql(u8, key, "align_u")) {
                self.texture_transform.align_u = try scene_kdl_values.parseF32(value);
            } else if (std.mem.eql(u8, key, "align_v")) {
                self.texture_transform.align_v = try scene_kdl_values.parseF32(value);
            }
            return;
        }
        if (std.mem.eql(u8, section_name, "face")) {
            var face_index: usize = 0;
            var material_path: ?[]u8 = null;
            var transform = scene_texture.Transform{};
            if (std.mem.eql(u8, key, "index")) {
                face_index = try std.fmt.parseInt(usize, value, 10);
            } else if (std.mem.eql(u8, key, "material")) {
                material_path = try self.allocator.dupe(u8, value);
            } else if (std.mem.eql(u8, key, "scale_world")) {
                transform.scale_world = try scene_kdl_values.parseF32(value);
            } else if (std.mem.eql(u8, key, "rotation_deg")) {
                transform.rotation_deg = try scene_kdl_values.parseF32(value);
            }
            if (material_path) |path| {
                try self.face_materials.append(self.allocator, .{
                    .face_index = face_index,
                    .material_path = path,
                    .transform = transform,
                });
            }
            return;
        }
        if (std.mem.eql(u8, section_name, "surface")) {
            if (std.mem.eql(u8, key, "index")) {
                self.surface_pending_index = try std.fmt.parseInt(usize, value, 10);
            } else if (std.mem.eql(u8, key, "type")) {
                const surface_type = scene_surface.SurfaceType.fromName(value) orelse return error.InvalidValue;
                try self.face_surfaces.append(self.allocator, .{
                    .face_index = self.surface_pending_index,
                    .surface_type = surface_type,
                });
            }
            return;
        }
        if (std.mem.eql(u8, section_name, "gameplay")) {
            var component = self.gameplay orelse scene_gameplay.Component{
                .tag = try scene_gameplay.Component.defaultTag(self.allocator),
            };
            if (std.mem.eql(u8, key, "tag")) {
                self.allocator.free(component.tag);
                component.tag = try self.allocator.dupe(u8, value);
            } else if (std.mem.eql(u8, key, "health")) {
                component.health = try scene_kdl_values.parseF32(value);
            } else if (std.mem.eql(u8, key, "score")) {
                component.score = try std.fmt.parseInt(i32, value, 10);
            } else if (std.mem.eql(u8, key, "team")) {
                component.team = try std.fmt.parseInt(i32, value, 10);
            } else if (std.mem.eql(u8, key, "interactable")) {
                component.interactable = try scene_kdl_values.parseBool(value);
            }
            self.gameplay = component;
            return;
        }
        if (std.mem.eql(u8, section_name, "marker")) {
            var marker = self.marker orelse try scene_marker.defaultForKind(self.allocator, .player_start);
            if (std.mem.eql(u8, key, "kind")) {
                marker.kind = scene_marker.Kind.fromName(value) orelse return error.InvalidValue;
            } else if (std.mem.eql(u8, key, "shape")) {
                marker.shape = scene_marker.Shape.fromName(value) orelse return error.InvalidValue;
            } else if (std.mem.eql(u8, key, "id")) {
                if (marker.marker_id.len > 0) self.allocator.free(marker.marker_id);
                marker.marker_id = try self.allocator.dupe(u8, value);
            } else if (std.mem.eql(u8, key, "group")) {
                if (marker.group.len > 0) self.allocator.free(marker.group);
                marker.group = try self.allocator.dupe(u8, value);
            } else if (std.mem.eql(u8, key, "binding")) {
                if (marker.binding.len > 0) self.allocator.free(marker.binding);
                marker.binding = try self.allocator.dupe(u8, value);
            } else if (std.mem.eql(u8, key, "radius")) {
                marker.radius = try scene_kdl_values.parseF32(value);
            } else if (std.mem.eql(u8, key, "order")) {
                marker.order = try std.fmt.parseInt(i32, value, 10);
            }
            self.marker = marker;
            return;
        }
    }

    fn setComponents(self: *EntityBuilder, value: []const u8) !void {
        for (self.components.items) |component| self.allocator.free(component);
        self.components.clearRetainingCapacity();

        var iter = std.mem.splitScalar(u8, value, ',');
        while (iter.next()) |raw_part| {
            const part = std.mem.trim(u8, raw_part, " \t\r\n");
            if (part.len == 0) continue;
            try self.components.append(self.allocator, try self.allocator.dupe(u8, part));
        }
    }

    pub fn finish(self: *EntityBuilder, allocator: std.mem.Allocator) !scene_document.SceneEntity {
        const entity_name = self.name orelse return error.MissingEntityName;
        const texture = self.texture_file orelse return error.MissingTexture;
        if (texture.len == 0) return error.MissingTexture;
        const entity_mesh: scene_document.EntityMesh = self.mesh orelse return error.MissingEntityMesh;
        const components = try self.components.toOwnedSlice(allocator);
        const properties = try self.properties.toOwnedSlice(allocator);
        const face_materials = try self.face_materials.toOwnedSlice(allocator);
        const face_surfaces = try self.face_surfaces.toOwnedSlice(allocator);
        const blockout_intent = self.blockout_intent;
        self.name = null;
        self.texture_file = null;
        self.mesh = null;
        self.blockout_intent = null;
        self.properties = .empty;
        return .{
            .id = self.id,
            .name = entity_name,
            .position = self.position,
            .rotation = self.rotation,
            .scale = self.scale,
            .base_color = self.base_color,
            .texture_file = texture,
            .mesh = entity_mesh,
            .object_kind = self.object_kind,
            .enabled = self.enabled,
            .renderer_visible = self.renderer_visible,
            .cast_shadows = self.cast_shadows,
            .receive_shadows = self.receive_shadows,
            .components = components,
            .properties = properties,
            .physics = self.physics,
            .blockout_intent = blockout_intent,
            .texture_transform = self.texture_transform,
            .face_materials = face_materials,
            .face_surfaces = face_surfaces,
            .gameplay = self.gameplay,
            .marker = self.marker,
            .lightmap_path = self.lightmap_path,
            .skeleton_asset = self.skeleton_asset,
            .parent_id = self.parent_id,
            .layer = self.layer,
            .variant = self.variant,
            .prop_asset_id = self.prop_asset_id,
        };
    }
};
