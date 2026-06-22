const shared = @import("runtime_shared");

const shared_color = shared.color;
const command_ids = shared.editor_command_ids;

pub const MaterialId = enum {
    light,
    slate,
    red,
    green,
    blue,
    gold,
};

pub const MaterialAsset = struct {
    id: MaterialId,
    asset_command_id: []const u8,
    toolbar_command_id: []const u8,
    label: []const u8,
    path: []const u8,
    color: shared_color.Color,
};

pub const catalog = [_]MaterialAsset{
    .{
        .id = .light,
        .asset_command_id = command_ids.materialAsset("light"),
        .toolbar_command_id = command_ids.materialToolbar("light"),
        .label = "Light",
        .path = "materials/editor/light.checker",
        .color = .{ .r = 190, .g = 198, .b = 210, .a = 255 },
    },
    .{
        .id = .slate,
        .asset_command_id = command_ids.materialAsset("slate"),
        .toolbar_command_id = command_ids.materialToolbar("slate"),
        .label = "Slate",
        .path = "materials/editor/slate.checker",
        .color = .{ .r = 148, .g = 164, .b = 184, .a = 255 },
    },
    .{
        .id = .red,
        .asset_command_id = command_ids.materialAsset("red"),
        .toolbar_command_id = command_ids.materialToolbar("red"),
        .label = "Red",
        .path = "materials/editor/red.checker",
        .color = .{ .r = 200, .g = 80, .b = 60, .a = 255 },
    },
    .{
        .id = .green,
        .asset_command_id = command_ids.materialAsset("green"),
        .toolbar_command_id = command_ids.materialToolbar("green"),
        .label = "Green",
        .path = "materials/editor/green.checker",
        .color = .{ .r = 80, .g = 160, .b = 90, .a = 255 },
    },
    .{
        .id = .blue,
        .asset_command_id = command_ids.materialAsset("blue"),
        .toolbar_command_id = command_ids.materialToolbar("blue"),
        .label = "Blue",
        .path = "materials/editor/blue.checker",
        .color = .{ .r = 70, .g = 120, .b = 200, .a = 255 },
    },
    .{
        .id = .gold,
        .asset_command_id = command_ids.materialAsset("gold"),
        .toolbar_command_id = command_ids.materialToolbar("gold"),
        .label = "Gold",
        .path = "materials/editor/gold.checker",
        .color = .{ .r = 220, .g = 200, .b = 80, .a = 255 },
    },
};

pub fn get(id: MaterialId) MaterialAsset {
    for (catalog) |material| {
        if (material.id == id) return material;
    }
    unreachable;
}

test "material catalog has stable ids and paths" {
    const red = get(.red);
    try @import("std").testing.expectEqualStrings("Red", red.label);
    try @import("std").testing.expectEqualStrings("materials/editor/red.checker", red.path);
}
