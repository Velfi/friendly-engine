const std = @import("std");
const context = @import("context.zig");
const input = @import("input.zig");
const layout = @import("layout.zig");
const rich_text = @import("rich_text.zig");

pub fn label(ui: *context.UiContext, text: []const u8) !void {
    const rect = try ui.allocFullWidthRow((try ui.currentLayout()).row_height);
    const stable = try ui.stableId(null, text);
    try ui.pushCommand(.{
        .label = .{
            .id = ui.nextCommandId(stable),
            .rect = rect,
            .text = try ui.dupeText(text),
        },
    });
}

pub fn richLabel(ui: *context.UiContext, id: []const u8, spans: []const rich_text.Span) !void {
    const rect = try ui.allocFullWidthRow((try ui.currentLayout()).row_height);
    const stable = try ui.stableId(id, id);
    try ui.pushCommand(.{
        .label = .{
            .id = ui.nextCommandId(stable),
            .rect = rect,
            .text = "",
            .spans = try ui.dupeRichText(spans),
        },
    });
}

pub fn button(ui: *context.UiContext, label_text: []const u8) !layout.ButtonResult {
    const rect = try ui.allocFullWidthRow((try ui.currentLayout()).row_height);
    const stable = try ui.stableId(null, label_text);
    const widget_id = ui.nextCommandId(stable);
    const click = input.handleClick(ui, stable, rect);
    try ui.pushCommand(.{
        .button = .{
            .id = widget_id,
            .rect = rect,
            .text = try ui.dupeText(label_text),
            .hovered = click.hovered,
            .active = click.active,
            .disabled = false,
        },
    });
    return .{
        .id = stable,
        .rect = rect,
        .hovered = click.hovered,
        .clicked = click.clicked,
    };
}

pub fn disabledButton(ui: *context.UiContext, label_text: []const u8) !layout.ButtonResult {
    const rect = try ui.allocFullWidthRow((try ui.currentLayout()).row_height);
    const stable = try ui.stableId(null, label_text);
    try ui.pushCommand(.{
        .button = .{
            .id = ui.nextCommandId(stable),
            .rect = rect,
            .text = try ui.dupeText(label_text),
            .hovered = false,
            .active = false,
            .disabled = true,
        },
    });
    return .{
        .id = stable,
        .rect = rect,
        .hovered = false,
        .clicked = false,
    };
}

pub const IconButtonOptions = struct {
    id: ?[]const u8 = null,
    icon: []const u8,
    width: f32 = 28.0,
};

pub fn iconButton(ui: *context.UiContext, options: IconButtonOptions) !layout.ButtonResult {
    const rect = try ui.allocRowRect(options.width, (try ui.currentLayout()).row_height);
    const stable = try ui.stableId(options.id, options.icon);
    const click = input.handleClick(ui, stable, rect);
    try ui.pushCommand(.{
        .icon_button = .{
            .id = ui.nextCommandId(stable),
            .rect = rect,
            .icon = try ui.dupeText(options.icon),
            .hovered = click.hovered,
            .active = click.active,
        },
    });
    return .{
        .id = stable,
        .rect = rect,
        .hovered = click.hovered,
        .clicked = click.clicked,
    };
}

pub fn toggle(ui: *context.UiContext, label_text: []const u8, explicit_id: ?[]const u8) !struct { value: bool, clicked: bool } {
    const rect = try ui.allocFullWidthRow((try ui.currentLayout()).row_height);
    const stable = try ui.stableId(explicit_id, label_text);
    var value = try ui.getBoolState(stable, false);
    const click = input.handleClick(ui, stable, rect);
    if (click.clicked) value = !value;
    try ui.setBoolState(stable, value);
    try ui.pushCommand(.{
        .toggle = .{
            .id = ui.nextCommandId(stable),
            .rect = rect,
            .text = try ui.dupeText(label_text),
            .value = value,
            .hovered = click.hovered,
            .active = click.active,
        },
    });
    return .{ .value = value, .clicked = click.clicked };
}

pub const ToggleGroupItem = struct {
    id: []const u8,
    label: []const u8,
};

pub fn toggleGroup(ui: *context.UiContext, group_id: []const u8, items: []const ToggleGroupItem) ![]const u8 {
    const group_stable = try ui.stableId(group_id, group_id);
    const selected = try ui.getIntState(group_stable, 0);
    const item_width = (try ui.currentLayout()).content_w / @as(f32, @floatFromInt(@max(1, items.len)));
    var clicked_label: ?[]const u8 = null;
    try layout.sameLine(ui);

    for (items, 0..) |item, index| {
        const rect = try ui.allocRowRect(item_width, (try ui.currentLayout()).row_height);
        const item_stable = try ui.stableId(item.id, item.label);
        const click = input.handleClick(ui, item_stable, rect);
        if (click.clicked) {
            try ui.setIntState(group_stable, @intCast(index));
            clicked_label = item.label;
        }
        const is_selected = selected == @as(i32, @intCast(index));
        try ui.pushCommand(.{
            .toggle_group_item = .{
                .id = ui.nextCommandId(item_stable),
                .group_id = group_stable,
                .rect = rect,
                .text = try ui.dupeText(item.label),
                .selected = is_selected,
                .hovered = click.hovered,
                .active = click.active,
            },
        });
    }
    try layout.endSameLine(ui);
    if (clicked_label) |label_text| return label_text;
    if (selected >= 0 and selected < items.len) return items[@intCast(selected)].label;
    return items[0].label;
}

test "toggle flips persistent state" {
    var ui = context.UiContext.init(std.testing.allocator);
    defer ui.deinit();

    ui.beginFrame(.{
        .mouse_position = .{ .x = 20, .y = 20 },
        .primary_pressed = true,
        .primary_down = true,
    });
    try layout.beginPanel(&ui, .{ .id = "p", .rect = .{ .x = 0, .y = 0, .w = 200, .h = 100 } });
    _ = try toggle(&ui, "Snap", null);
    layout.endPanel(&ui);

    ui.beginFrame(.{
        .mouse_position = .{ .x = 20, .y = 20 },
        .primary_released = true,
    });
    ui.active_widget = try ui.stableId(null, "Snap");
    try layout.beginPanel(&ui, .{ .id = "p", .rect = .{ .x = 0, .y = 0, .w = 200, .h = 100 } });
    const result = try toggle(&ui, "Snap", null);
    layout.endPanel(&ui);
    try std.testing.expect(result.value);
}

test "disabled button never clicks" {
    var ui = context.UiContext.init(std.testing.allocator);
    defer ui.deinit();

    ui.beginFrame(.{
        .mouse_position = .{ .x = 20, .y = 20 },
        .primary_released = true,
    });
    try layout.beginPanel(&ui, .{ .id = "p", .rect = .{ .x = 0, .y = 0, .w = 200, .h = 100 } });
    const result = try disabledButton(&ui, "Open");
    layout.endPanel(&ui);

    try std.testing.expect(!result.clicked);
    try std.testing.expect(ui.renderCommands()[1].button.disabled);
}

test "rich label stores styled spans for the frame" {
    var ui = context.UiContext.init(std.testing.allocator);
    defer ui.deinit();

    ui.beginFrame(.{});
    try layout.beginPanel(&ui, .{ .id = "p", .rect = .{ .x = 0, .y = 0, .w = 200, .h = 100 } });
    try richLabel(&ui, "health-readout", &.{
        .{ .text = "Health ", .style = .{ .color = .{ .r = 200, .g = 210, .b = 220 } } },
        .{ .text = "low", .style = .{ .color = .{ .r = 220, .g = 70, .b = 70 }, .bold = true, .underline = true } },
    });
    layout.endPanel(&ui);

    const command = ui.renderCommands()[1].label;
    try std.testing.expectEqual(@as(usize, 2), command.spans.len);
    try std.testing.expect(command.spans[1].style.bold);
    try std.testing.expect(command.spans[1].style.underline);
    try std.testing.expectEqualStrings("low", command.spans[1].text);
}
