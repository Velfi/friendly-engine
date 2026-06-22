const std = @import("std");
const commands = @import("commands.zig");
const context = @import("context.zig");
const input = @import("input.zig");
const layout = @import("layout.zig");

pub const TabItem = struct {
    id: []const u8,
    label: []const u8,
};

pub fn tabs(ui: *context.UiContext, bar_id: []const u8, items: []const TabItem) ![]const u8 {
    const bar_stable = try ui.stableId(bar_id, bar_id);
    const selected = try ui.getIntState(bar_stable, 0);
    const item_width = (try ui.currentLayout()).content_w / @as(f32, @floatFromInt(@max(1, items.len)));
    try layout.sameLine(ui);

    for (items, 0..) |item, index| {
        const rect = try ui.allocRowRect(item_width, (try ui.currentLayout()).row_height);
        const item_stable = try ui.stableId(item.id, item.label);
        const click = input.handleClick(ui, item_stable, rect);
        if (click.clicked) try ui.setIntState(bar_stable, @intCast(index));
        const is_selected = selected == @as(i32, @intCast(index));
        try ui.pushCommand(.{
            .tab = .{
                .id = ui.nextCommandId(item_stable),
                .bar_id = bar_stable,
                .rect = rect,
                .text = try ui.dupeText(item.label),
                .selected = is_selected,
                .hovered = click.hovered,
                .active = click.active,
            },
        });
    }
    try layout.endSameLine(ui);
    const idx = try ui.getIntState(bar_stable, 0);
    if (idx >= 0 and idx < items.len) return items[@intCast(idx)].label;
    return items[0].label;
}

pub fn treeNode(ui: *context.UiContext, label_text: []const u8, depth: u32) !struct { open: bool, clicked: bool } {
    const stable = try ui.stableId(null, label_text);
    var open = try ui.getBoolState(stable, false);
    const indent = @as(f32, @floatFromInt(depth)) * 14.0;
    const rect = try ui.allocFullWidthRow((try ui.currentLayout()).row_height);
    const hit_rect = context.Rect{
        .x = rect.x + indent,
        .y = rect.y,
        .w = rect.w - indent,
        .h = rect.h,
    };
    const click = input.handleClick(ui, stable, hit_rect);
    if (click.clicked) open = !open;
    try ui.setBoolState(stable, open);
    try ui.pushCommand(.{
        .tree_node = .{
            .id = ui.nextCommandId(stable),
            .rect = hit_rect,
            .text = try ui.dupeText(label_text),
            .depth = depth,
            .open = open,
            .hovered = click.hovered,
            .active = click.active,
        },
    });
    return .{ .open = open, .clicked = click.clicked };
}

pub fn selectable(ui: *context.UiContext, label_text: []const u8, selection_group: []const u8, item_index: i32) !struct { selected: bool, clicked: bool } {
    const group_stable = try ui.stableId(selection_group, selection_group);
    const stable = try ui.stableId(null, label_text);
    const selected_index = try ui.getIntState(group_stable, 0);
    const rect = try ui.allocFullWidthRow((try ui.currentLayout()).row_height);
    const click = input.handleClick(ui, stable, rect);
    var selected = selected_index == item_index;
    if (click.clicked) {
        try ui.setIntState(group_stable, item_index);
        selected = true;
    }
    try ui.pushCommand(.{
        .selectable = .{
            .id = ui.nextCommandId(stable),
            .rect = rect,
            .text = try ui.dupeText(label_text),
            .selected = selected,
            .hovered = click.hovered,
            .active = click.active,
        },
    });
    return .{ .selected = selected, .clicked = click.clicked };
}

pub fn collapsingHeader(ui: *context.UiContext, label_text: []const u8) !struct { open: bool, clicked: bool } {
    const stable = try ui.stableId(null, label_text);
    var open = try ui.getBoolState(stable, true);
    const rect = try ui.allocFullWidthRow((try ui.currentLayout()).row_height);
    const click = input.handleClick(ui, stable, rect);
    if (click.clicked) open = !open;
    try ui.setBoolState(stable, open);
    try ui.pushCommand(.{
        .collapsing_header = .{
            .id = ui.nextCommandId(stable),
            .rect = rect,
            .text = try ui.dupeText(label_text),
            .open = open,
            .hovered = click.hovered,
            .active = click.active,
        },
    });
    return .{ .open = open, .clicked = click.clicked };
}

test "tabs switch active tab" {
    var ui = context.UiContext.init(std.testing.allocator);
    defer ui.deinit();

    ui.beginFrame(.{
        .mouse_position = .{ .x = 150, .y = 20 },
        .primary_pressed = true,
        .primary_down = true,
    });
    try layout.beginPanel(&ui, .{ .id = "rail", .rect = .{ .x = 0, .y = 0, .w = 300, .h = 100 } });
    _ = try tabs(&ui, "main", &.{ .{ .id = "scene", .label = "Scene" }, .{ .id = "add", .label = "Add" } });
    layout.endPanel(&ui);

    ui.beginFrame(.{
        .mouse_position = .{ .x = 150, .y = 20 },
        .primary_released = true,
    });
    ui.active_widget = try ui.stableId("add", "Add");
    try layout.beginPanel(&ui, .{ .id = "rail", .rect = .{ .x = 0, .y = 0, .w = 300, .h = 100 } });
    const active = try tabs(&ui, "main", &.{ .{ .id = "scene", .label = "Scene" }, .{ .id = "add", .label = "Add" } });
    layout.endPanel(&ui);
    try std.testing.expectEqualStrings("Add", active);
}

test "tree node expands on click" {
    var ui = context.UiContext.init(std.testing.allocator);
    defer ui.deinit();

    ui.beginFrame(.{
        .mouse_position = .{ .x = 20, .y = 20 },
        .primary_pressed = true,
        .primary_down = true,
    });
    try layout.beginPanel(&ui, .{ .id = "tree", .rect = .{ .x = 0, .y = 0, .w = 200, .h = 100 } });
    _ = try treeNode(&ui, "Root", 0);
    layout.endPanel(&ui);

    ui.beginFrame(.{
        .mouse_position = .{ .x = 20, .y = 20 },
        .primary_released = true,
    });
    ui.active_widget = try ui.stableId(null, "Root");
    try layout.beginPanel(&ui, .{ .id = "tree", .rect = .{ .x = 0, .y = 0, .w = 200, .h = 100 } });
    const result = try treeNode(&ui, "Root", 0);
    layout.endPanel(&ui);
    try std.testing.expect(result.open);
}
