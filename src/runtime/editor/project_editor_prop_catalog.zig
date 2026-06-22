const std = @import("std");
const project_editor_state = @import("project_editor_state.zig");
const shared = @import("runtime_shared");
const geometry = shared.geometry;
const shared_color = shared.color;

const ProjectEditorState = project_editor_state.ProjectEditorState;

pub const cache_target = "client-debug";
pub const max_recent_props: usize = 8;

pub const CatalogEntry = struct {
    id: []const u8,
    label: []const u8,
    mesh_ref: []const u8,
    recipe: PropRecipe,
    kind: geometry.PrimitiveKind,
    params: geometry.PrimitiveParams,
    color: shared_color.Color,
    variant_count: u32,
};

pub const PropRecipe = struct {
    base_kind: geometry.PrimitiveKind,
    base_params: geometry.PrimitiveParams,
    shaping: []const []const u8 = &.{},
    sources: []const PropSource = &.{},

    pub fn summary(self: PropRecipe, buf: []u8) []const u8 {
        return switch (self.base_kind) {
            .cylinder => std.fmt.bufPrint(buf, "Cylinder  r {d:.2}  h {d:.2}", .{
                self.base_params.radius,
                self.base_params.height,
            }) catch "Base recipe",
            .sphere => std.fmt.bufPrint(buf, "Sphere  r {d:.2}", .{self.base_params.radius}) catch "Base recipe",
            else => std.fmt.bufPrint(buf, "{s}  {d:.2} x {d:.2} x {d:.2}", .{
                primitiveLabel(self.base_kind),
                self.base_params.width,
                self.base_params.height,
                self.base_params.depth,
            }) catch "Base recipe",
        };
    }
};

pub const PropSource = struct {
    id: []const u8,
    position: [3]f32 = .{ 0, 0, 0 },
    scale: [3]f32,
    radius: f32 = 1,
    segments: u32 = 12,
    rings: u32 = 8,
};

pub const catalog = [_]CatalogEntry{
    .{
        .id = "crate_wood",
        .label = "Crate Wood",
        .mesh_ref = "assets/source/meshes/box.glb",
        .recipe = .{
            .base_kind = .box,
            .base_params = .{ .width = 0.8, .height = 0.8, .depth = 0.8 },
            .shaping = &.{ "panel insets", "edge bevels", "variant boards" },
        },
        .kind = .box,
        .params = .{ .width = 0.8, .height = 0.8, .depth = 0.8 },
        .color = .{ .r = 165, .g = 130, .b = 85, .a = 255 },
        .variant_count = 3,
    },
    .{
        .id = "barrel_rust",
        .label = "Barrel Rust",
        .mesh_ref = "assets/source/meshes/props/barrel_rust.glb",
        .recipe = .{
            .base_kind = .cylinder,
            .base_params = .{ .radius = 0.35, .height = 0.9, .segments = 16 },
            .shaping = &.{ "rim bands", "vertical dents", "rust tint mask" },
        },
        .kind = .cylinder,
        .params = .{ .radius = 0.35, .height = 0.9 },
        .color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .variant_count = 2,
    },
    .{
        .id = "lamp_wall",
        .label = "Lamp Wall",
        .mesh_ref = "assets/source/meshes/props/lamp_wall.glb",
        .recipe = .{
            .base_kind = .box,
            .base_params = .{ .width = 0.2, .height = 0.5, .depth = 0.25 },
            .shaping = &.{ "back plate", "light socket", "shade bracket" },
        },
        .kind = .box,
        .params = .{ .width = 0.2, .height = 0.5, .depth = 0.25 },
        .color = .{ .r = 210, .g = 200, .b = 170, .a = 255 },
        .variant_count = 2,
    },
    .{
        .id = "door_metal",
        .label = "Door Metal",
        .mesh_ref = "assets/source/meshes/props/door_metal.glb",
        .recipe = .{
            .base_kind = .box,
            .base_params = .{ .width = 0.9, .height = 2.0, .depth = 0.12 },
            .shaping = &.{ "panel recess", "hinge strip", "handle socket" },
        },
        .kind = .box,
        .params = .{ .width = 0.9, .height = 2.0, .depth = 0.12 },
        .color = .{ .r = 120, .g = 125, .b = 135, .a = 255 },
        .variant_count = 2,
    },
    .{
        .id = "chair_old",
        .label = "Chair Old",
        .mesh_ref = "assets/source/meshes/props/chair_old.glb",
        .recipe = .{
            .base_kind = .box,
            .base_params = .{ .width = 0.45, .height = 0.85, .depth = 0.45 },
            .shaping = &.{ "seat slab", "leg array", "back support" },
        },
        .kind = .box,
        .params = .{ .width = 0.45, .height = 0.85, .depth = 0.45 },
        .color = .{ .r = 150, .g = 110, .b = 70, .a = 255 },
        .variant_count = 2,
    },
    .{
        .id = "table_small",
        .label = "Table Small",
        .mesh_ref = "assets/source/meshes/props/table_small.glb",
        .recipe = .{
            .base_kind = .box,
            .base_params = .{ .width = 0.9, .height = 0.75, .depth = 0.6 },
            .shaping = &.{ "top slab", "leg array", "edge bevels" },
        },
        .kind = .box,
        .params = .{ .width = 0.9, .height = 0.75, .depth = 0.6 },
        .color = .{ .r = 175, .g = 140, .b = 95, .a = 255 },
        .variant_count = 2,
    },
    .{
        .id = "bench_wood",
        .label = "Bench Wood",
        .mesh_ref = "assets/source/meshes/props/bench_wood.glb",
        .recipe = .{
            .base_kind = .box,
            .base_params = .{ .width = 1.2, .height = 0.55, .depth = 0.42 },
            .shaping = &.{ "seat plank", "back plank", "four legs" },
            .sources = &.{
                .{ .id = "seat", .position = .{ 0, 0.12, 0 }, .scale = .{ 0.72, 0.08, 0.24 } },
                .{ .id = "back", .position = .{ 0, 0.44, 0.22 }, .scale = .{ 0.72, 0.08, 0.12 } },
                .{ .id = "leg_fl", .position = .{ -0.5, -0.22, -0.14 }, .scale = .{ 0.08, 0.28, 0.08 } },
                .{ .id = "leg_fr", .position = .{ 0.5, -0.22, -0.14 }, .scale = .{ 0.08, 0.28, 0.08 } },
                .{ .id = "leg_bl", .position = .{ -0.5, -0.22, 0.14 }, .scale = .{ 0.08, 0.28, 0.08 } },
                .{ .id = "leg_br", .position = .{ 0.5, -0.22, 0.14 }, .scale = .{ 0.08, 0.28, 0.08 } },
            },
        },
        .kind = .box,
        .params = .{ .width = 1.2, .height = 0.55, .depth = 0.42 },
        .color = .{ .r = 142, .g = 101, .b = 61, .a = 255 },
        .variant_count = 2,
    },
    .{
        .id = "signpost_wood",
        .label = "Signpost Wood",
        .mesh_ref = "assets/source/meshes/props/signpost_wood.glb",
        .recipe = .{
            .base_kind = .box,
            .base_params = .{ .width = 0.75, .height = 1.35, .depth = 0.16 },
            .shaping = &.{ "upright post", "direction boards", "cap" },
            .sources = &.{
                .{ .id = "post", .position = .{ 0, 0.0, 0 }, .scale = .{ 0.09, 0.72, 0.09 }, .segments = 10 },
                .{ .id = "board_l", .position = .{ -0.27, 0.42, 0 }, .scale = .{ 0.42, 0.1, 0.06 } },
                .{ .id = "board_r", .position = .{ 0.34, 0.2, 0 }, .scale = .{ 0.46, 0.1, 0.06 } },
                .{ .id = "cap", .position = .{ 0, 0.76, 0 }, .scale = .{ 0.14, 0.08, 0.14 }, .segments = 10 },
            },
        },
        .kind = .box,
        .params = .{ .width = 0.75, .height = 1.35, .depth = 0.16 },
        .color = .{ .r = 126, .g = 88, .b = 50, .a = 255 },
        .variant_count = 2,
    },
    .{
        .id = "well_stone",
        .label = "Well Stone",
        .mesh_ref = "assets/source/meshes/props/well_stone.glb",
        .recipe = .{
            .base_kind = .cylinder,
            .base_params = .{ .radius = 0.42, .height = 0.9, .segments = 16 },
            .shaping = &.{ "stone ring", "roof supports", "cross beam" },
            .sources = &.{
                .{ .id = "ring", .position = .{ 0, -0.2, 0 }, .scale = .{ 0.46, 0.2, 0.46 }, .segments = 16, .rings = 8 },
                .{ .id = "water", .position = .{ 0, -0.02, 0 }, .scale = .{ 0.28, 0.035, 0.28 }, .segments = 16, .rings = 6 },
                .{ .id = "post_l", .position = .{ -0.38, 0.45, 0 }, .scale = .{ 0.07, 0.62, 0.07 } },
                .{ .id = "post_r", .position = .{ 0.38, 0.45, 0 }, .scale = .{ 0.07, 0.62, 0.07 } },
                .{ .id = "beam", .position = .{ 0, 1.0, 0 }, .scale = .{ 0.48, 0.06, 0.07 } },
            },
        },
        .kind = .cylinder,
        .params = .{ .radius = 0.42, .height = 0.9, .segments = 16 },
        .color = .{ .r = 117, .g = 112, .b = 101, .a = 255 },
        .variant_count = 2,
    },
    .{
        .id = "cart_hand",
        .label = "Hand Cart",
        .mesh_ref = "assets/source/meshes/props/cart_hand.glb",
        .recipe = .{
            .base_kind = .box,
            .base_params = .{ .width = 1.1, .height = 0.55, .depth = 0.72 },
            .shaping = &.{ "cart bed", "two wheels", "handles" },
            .sources = &.{
                .{ .id = "bed", .position = .{ 0, 0.08, 0 }, .scale = .{ 0.62, 0.12, 0.38 } },
                .{ .id = "wheel_l", .position = .{ -0.44, -0.12, 0.28 }, .scale = .{ 0.18, 0.18, 0.06 }, .segments = 14 },
                .{ .id = "wheel_r", .position = .{ 0.44, -0.12, 0.28 }, .scale = .{ 0.18, 0.18, 0.06 }, .segments = 14 },
                .{ .id = "handle_l", .position = .{ -0.36, 0.08, -0.5 }, .scale = .{ 0.05, 0.05, 0.42 } },
                .{ .id = "handle_r", .position = .{ 0.36, 0.08, -0.5 }, .scale = .{ 0.05, 0.05, 0.42 } },
            },
        },
        .kind = .box,
        .params = .{ .width = 1.1, .height = 0.55, .depth = 0.72 },
        .color = .{ .r = 132, .g = 87, .b = 48, .a = 255 },
        .variant_count = 2,
    },
    .{
        .id = "window_stone_frame",
        .label = "Stone Window Frame",
        .mesh_ref = "assets/source/meshes/props/window_stone_frame.glb",
        .recipe = .{
            .base_kind = .box,
            .base_params = .{ .width = 0.78, .height = 0.92, .depth = 0.08 },
            .shaping = &.{ "sandstone sill", "lintel", "side jambs" },
            .sources = &.{
                .{ .id = "sill", .position = .{ 0, -0.42, 0 }, .scale = .{ 0.48, 0.055, 0.055 } },
                .{ .id = "lintel", .position = .{ 0, 0.42, 0 }, .scale = .{ 0.48, 0.06, 0.055 } },
                .{ .id = "jamb_l", .position = .{ -0.39, 0, 0 }, .scale = .{ 0.06, 0.42, 0.055 } },
                .{ .id = "jamb_r", .position = .{ 0.39, 0, 0 }, .scale = .{ 0.06, 0.42, 0.055 } },
            },
        },
        .kind = .box,
        .params = .{ .width = 0.78, .height = 0.92, .depth = 0.08 },
        .color = .{ .r = 205, .g = 159, .b = 111, .a = 255 },
        .variant_count = 2,
    },
    .{
        .id = "door_sandstone_surround",
        .label = "Sandstone Door Surround",
        .mesh_ref = "assets/source/meshes/props/door_sandstone_surround.glb",
        .recipe = .{
            .base_kind = .box,
            .base_params = .{ .width = 1.18, .height = 2.18, .depth = 0.1 },
            .shaping = &.{ "classical lintel", "side jambs", "threshold" },
            .sources = &.{
                .{ .id = "threshold", .position = .{ 0, -1.02, 0 }, .scale = .{ 0.65, 0.06, 0.065 } },
                .{ .id = "lintel", .position = .{ 0, 1.04, 0 }, .scale = .{ 0.68, 0.08, 0.065 } },
                .{ .id = "jamb_l", .position = .{ -0.55, 0, 0 }, .scale = .{ 0.075, 1.02, 0.065 } },
                .{ .id = "jamb_r", .position = .{ 0.55, 0, 0 }, .scale = .{ 0.075, 1.02, 0.065 } },
                .{ .id = "pediment", .position = .{ 0, 1.22, 0 }, .scale = .{ 0.5, 0.06, 0.06 } },
            },
        },
        .kind = .box,
        .params = .{ .width = 1.18, .height = 2.18, .depth = 0.1 },
        .color = .{ .r = 218, .g = 169, .b = 115, .a = 255 },
        .variant_count = 2,
    },
};

pub fn findCatalogEntry(id: []const u8) ?CatalogEntry {
    for (catalog) |entry| {
        if (std.mem.eql(u8, entry.id, id)) return entry;
    }
    return null;
}

pub fn catalogLabel(id: []const u8) []const u8 {
    if (findCatalogEntry(id)) |entry| return entry.label;
    return id;
}

pub fn primitiveLabel(kind: geometry.PrimitiveKind) []const u8 {
    return switch (kind) {
        .box => "Box",
        .plane => "Plane",
        .cylinder => "Cylinder",
        .sphere => "Sphere",
    };
}

pub fn layerLabel(layer: []const u8) []const u8 {
    return if (layer.len > 0) layer else "Default";
}

pub fn objectNameById(state: *const ProjectEditorState, id: u64) ?[]const u8 {
    for (state.objects.items) |obj| {
        if (obj.id == id) return obj.name;
    }
    return null;
}

pub fn objectIndexById(state: *const ProjectEditorState, id: u64) ?usize {
    for (state.objects.items, 0..) |obj, idx| {
        if (obj.id == id) return idx;
    }
    return null;
}

pub fn resolveParentId(state: *const ProjectEditorState, text: []const u8) ?u64 {
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    if (trimmed.len == 0 or std.mem.eql(u8, trimmed, "None")) return null;
    if (std.fmt.parseInt(u64, trimmed, 10)) |id| return id else |_| {}
    for (state.objects.items) |obj| {
        if (std.mem.eql(u8, obj.name, trimmed)) return obj.id;
    }
    return null;
}
