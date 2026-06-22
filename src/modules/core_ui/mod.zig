const std = @import("std");
const core = @import("../../core/mod.zig");
const framework = @import("../../framework/mod.zig");

pub const module_name = "gem.core_ui";
pub const commands = @import("commands.zig");
pub const WidgetId = commands.WidgetId;
pub const RenderCommand = @import("commands.zig").RenderCommand;
pub const BadgeVariant = commands.BadgeVariant;
pub const InlineAlertVariant = commands.InlineAlertVariant;
pub const SplitAxis = commands.SplitAxis;
pub const SpinnerSize = commands.SpinnerSize;
pub const Rect = @import("context.zig").Rect;
pub const InputState = @import("input.zig").InputState;
pub const InputHook = @import("input.zig").InputHook;
pub const InputHookVTable = @import("input.zig").InputHookVTable;
pub const PanelDesc = @import("context.zig").PanelDesc;
pub const UiContext = @import("context.zig").UiContext;
pub const ButtonResult = @import("layout.zig").ButtonResult;

pub const layout = @import("layout.zig");
pub const input = @import("input.zig");
pub const input_tree = @import("input_tree.zig");
pub const widgets_basic = @import("widgets_basic.zig");
pub const widgets_input = @import("widgets_input.zig");
pub const widgets_nav = @import("widgets_nav.zig");
pub const widgets_feedback = @import("widgets_feedback.zig");
pub const widgets_table = @import("widgets_table.zig");
pub const text_layout = @import("text_layout.zig");
pub const rich_text = @import("rich_text.zig");

pub fn register(registry: anytype) !void {
    _ = registry;
}

pub fn start(world: *framework.World) !void {
    try world.notifications.publish("gem.core_ui.started", "{}");
}

pub fn stop(world: *framework.World) !void {
    try world.notifications.publish("gem.core_ui.stopped", "{}");
}

const UiInputHookTestContext = struct {};

fn collectInput(context_ptr: *anyopaque, state: *InputState) !void {
    _ = context_ptr;
    state.mouse_position = .{ .x = 16.0, .y = 18.0 };
    state.primary_pressed = true;
    state.primary_down = true;
}

const test_input_vtable = InputHookVTable{
    .collect = collectInput,
};

test {
    _ = @import("rich_text.zig");
    _ = @import("input.zig");
    _ = @import("input_tree.zig");
    _ = @import("layout.zig");
    _ = @import("widgets_basic.zig");
    _ = @import("widgets_input.zig");
    _ = @import("widgets_nav.zig");
    _ = @import("widgets_feedback.zig");
    _ = @import("widgets_table.zig");
}

test "ui context produces commands and click events" {
    var ui = UiContext.init(std.testing.allocator);
    defer ui.deinit();

    ui.beginFrame(.{
        .mouse_position = .{ .x = 20.0, .y = 20.0 },
        .primary_down = true,
        .primary_pressed = true,
    });
    try layout.beginPanel(&ui, .{
        .id = "inspector",
        .rect = .{ .x = 10.0, .y = 10.0, .w = 300.0, .h = 220.0 },
    });
    _ = try widgets_basic.button(&ui, "Apply");
    layout.endPanel(&ui);

    ui.beginFrame(.{
        .mouse_position = .{ .x = 20.0, .y = 20.0 },
        .primary_released = true,
    });
    ui.active_widget = try ui.stableId(null, "Apply");
    try layout.beginPanel(&ui, .{
        .id = "inspector",
        .rect = .{ .x = 10.0, .y = 10.0, .w = 300.0, .h = 220.0 },
    });
    const result = try widgets_basic.button(&ui, "Apply");
    layout.endPanel(&ui);

    try std.testing.expect(result.clicked);
    try std.testing.expect(ui.renderCommands().len >= 2);
}

test "scroll area consumes wheel over inspector panel" {
    var ui = UiContext.init(std.testing.allocator);
    defer ui.deinit();

    ui.beginFrame(.{
        .mouse_position = .{ .x = 40.0, .y = 40.0 },
        .scroll_delta_y = -3.0,
    });
    try layout.beginPanel(&ui, .{
        .id = "inspector",
        .rect = .{ .x = 10.0, .y = 10.0, .w = 200.0, .h = 200.0 },
    });
    try layout.beginScrollArea(&ui, .{ .id = "inspector-scroll", .height = 20.0 });
    try widgets_basic.label(&ui, "Transform");
    try layout.endScrollArea(&ui);
    layout.endPanel(&ui);

    try std.testing.expect(input_tree.blocksViewportScroll(&ui));
    const scroll_id = try ui.stableId("inspector-scroll", "inspector-scroll");
    try std.testing.expectEqual(@as(f32, 12.0), try ui.getScrollState(scroll_id));
}

test "scroll area ignores wheel when content fits" {
    var ui = UiContext.init(std.testing.allocator);
    defer ui.deinit();

    ui.beginFrame(.{
        .mouse_position = .{ .x = 40.0, .y = 40.0 },
        .scroll_delta_y = -12.0,
    });
    try layout.beginPanel(&ui, .{
        .id = "inspector",
        .rect = .{ .x = 10.0, .y = 10.0, .w = 200.0, .h = 200.0 },
    });
    try layout.beginScrollArea(&ui, .{ .id = "inspector-scroll", .height = 120.0 });
    try widgets_basic.label(&ui, "Transform");
    try layout.endScrollArea(&ui);
    layout.endPanel(&ui);

    const scroll_id = try ui.stableId("inspector-scroll", "inspector-scroll");
    try std.testing.expectEqual(@as(f32, 0.0), try ui.getScrollState(scroll_id));
}

test "scroll area clamps wheel to overflowing inspector content" {
    var ui = UiContext.init(std.testing.allocator);
    defer ui.deinit();

    ui.beginFrame(.{
        .mouse_position = .{ .x = 40.0, .y = 40.0 },
        .scroll_delta_y = -1000.0,
    });
    try layout.beginPanel(&ui, .{
        .id = "inspector",
        .rect = .{ .x = 10.0, .y = 10.0, .w = 200.0, .h = 200.0 },
    });
    try layout.beginScrollArea(&ui, .{ .id = "inspector-scroll", .height = 60.0 });
    try widgets_basic.label(&ui, "Transform");
    try widgets_basic.label(&ui, "Object");
    try widgets_basic.label(&ui, "Parent");
    try layout.endScrollArea(&ui);
    layout.endPanel(&ui);

    const scroll_id = try ui.stableId("inspector-scroll", "inspector-scroll");
    try std.testing.expectEqual(@as(f32, 36.0), try ui.getScrollState(scroll_id));
}

test "scroll area normalizes flipped wheel direction" {
    var ui = UiContext.init(std.testing.allocator);
    defer ui.deinit();

    ui.beginFrame(.{
        .mouse_position = .{ .x = 40.0, .y = 40.0 },
        .scroll_delta_y = 3.0,
        .scroll_direction_flipped = true,
    });
    try layout.beginPanel(&ui, .{
        .id = "inspector",
        .rect = .{ .x = 10.0, .y = 10.0, .w = 200.0, .h = 200.0 },
    });
    try layout.beginScrollArea(&ui, .{ .id = "inspector-scroll", .height = 60.0 });
    try widgets_basic.label(&ui, "Transform");
    try widgets_basic.label(&ui, "Object");
    try widgets_basic.label(&ui, "Parent");
    try layout.endScrollArea(&ui);
    layout.endPanel(&ui);

    const scroll_id = try ui.stableId("inspector-scroll", "inspector-scroll");
    try std.testing.expectEqual(@as(f32, 36.0), try ui.getScrollState(scroll_id));
}

test "scroll area reports measured content overflow" {
    var ui = UiContext.init(std.testing.allocator);
    defer ui.deinit();

    ui.beginFrame(.{});
    try layout.beginPanel(&ui, .{
        .id = "inspector",
        .rect = .{ .x = 10.0, .y = 10.0, .w = 200.0, .h = 200.0 },
    });
    try layout.beginScrollArea(&ui, .{ .id = "inspector-scroll", .height = 60.0 });
    try widgets_basic.label(&ui, "Transform");
    try widgets_basic.label(&ui, "Object");
    try widgets_basic.label(&ui, "Parent");
    try layout.endScrollArea(&ui);
    layout.endPanel(&ui);

    for (ui.renderCommands()) |command| {
        if (command != .scroll_area) continue;
        try std.testing.expectEqual(@as(f32, 60.0), command.scroll_area.rect.h);
        try std.testing.expectEqual(@as(f32, 96.0), command.scroll_area.content_height);
        try std.testing.expectEqual(@as(f32, 36.0), command.scroll_area.max_scroll);
        return;
    }
    return error.ExpectedScrollAreaCommand;
}

test "scroll area offsets child command positions" {
    var ui = UiContext.init(std.testing.allocator);
    defer ui.deinit();

    const scroll_id = try ui.stableId("inspector-scroll", "inspector-scroll");
    try ui.setScrollState(scroll_id, 32.0);
    ui.beginFrame(.{});
    try layout.beginPanel(&ui, .{
        .id = "inspector",
        .rect = .{ .x = 10.0, .y = 10.0, .w = 200.0, .h = 200.0 },
    });
    try layout.beginScrollArea(&ui, .{ .id = "inspector-scroll", .height = 60.0 });
    try widgets_basic.label(&ui, "Transform");
    try widgets_basic.label(&ui, "Object");
    try widgets_basic.label(&ui, "Parent");
    try layout.endScrollArea(&ui);
    layout.endPanel(&ui);

    for (ui.renderCommands()) |command| {
        if (command != .label) continue;
        if (!std.mem.eql(u8, command.label.text, "Transform")) continue;
        try std.testing.expectEqual(@as(f32, -12.0), command.label.rect.y);
        return;
    }
    return error.ExpectedScrolledLabel;
}

test "scroll area can be dragged like touch content" {
    var ui = UiContext.init(std.testing.allocator);
    defer ui.deinit();

    ui.beginFrame(.{
        .mouse_position = .{ .x = 40.0, .y = 40.0 },
        .primary_pressed = true,
        .primary_down = true,
    });
    try layout.beginPanel(&ui, .{
        .id = "inspector",
        .rect = .{ .x = 10.0, .y = 10.0, .w = 200.0, .h = 200.0 },
    });
    try layout.beginScrollArea(&ui, .{ .id = "inspector-scroll", .height = 60.0, .input = layout.panel_scroll_input });
    try widgets_basic.label(&ui, "Transform");
    try widgets_basic.label(&ui, "Object");
    try widgets_basic.label(&ui, "Parent");
    try layout.endScrollArea(&ui);
    layout.endPanel(&ui);

    ui.beginFrame(.{
        .mouse_position = .{ .x = 40.0, .y = 20.0 },
        .primary_down = true,
        .motion_delta_y = -20.0,
    });
    try layout.beginPanel(&ui, .{
        .id = "inspector",
        .rect = .{ .x = 10.0, .y = 10.0, .w = 200.0, .h = 200.0 },
    });
    try layout.beginScrollArea(&ui, .{ .id = "inspector-scroll", .height = 60.0, .input = layout.panel_scroll_input });
    try widgets_basic.label(&ui, "Transform");
    try widgets_basic.label(&ui, "Object");
    try widgets_basic.label(&ui, "Parent");
    try layout.endScrollArea(&ui);
    layout.endPanel(&ui);

    const scroll_id = try ui.stableId("inspector-scroll", "inspector-scroll");
    try std.testing.expectEqual(@as(f32, 20.0), try ui.getScrollState(scroll_id));
}

test "scroll area can be driven by keyboard after focus" {
    var ui = UiContext.init(std.testing.allocator);
    defer ui.deinit();

    const scroll_id = try ui.stableId("inspector-scroll", "inspector-scroll");
    ui.focused_widget = scroll_id;
    ui.beginFrame(.{
        .mouse_position = .{ .x = 400.0, .y = 400.0 },
        .down_pressed = true,
    });
    ui.focused_widget = scroll_id;
    try layout.beginPanel(&ui, .{
        .id = "inspector",
        .rect = .{ .x = 10.0, .y = 10.0, .w = 200.0, .h = 200.0 },
    });
    try layout.beginScrollArea(&ui, .{ .id = "inspector-scroll", .height = 60.0, .input = layout.panel_scroll_input });
    try widgets_basic.label(&ui, "Transform");
    try widgets_basic.label(&ui, "Object");
    try widgets_basic.label(&ui, "Parent");
    try layout.endScrollArea(&ui);
    layout.endPanel(&ui);

    try std.testing.expectEqual(@as(f32, 36.0), try ui.getScrollState(scroll_id));
}

test "scroll area accepts generic navigation scroll input" {
    var ui = UiContext.init(std.testing.allocator);
    defer ui.deinit();

    const scroll_id = try ui.stableId("inspector-scroll", "inspector-scroll");
    ui.focused_widget = scroll_id;
    ui.beginFrame(.{
        .mouse_position = .{ .x = 400.0, .y = 400.0 },
        .navigation_scroll_y = -0.5,
    });
    ui.focused_widget = scroll_id;
    try layout.beginPanel(&ui, .{
        .id = "inspector",
        .rect = .{ .x = 10.0, .y = 10.0, .w = 200.0, .h = 200.0 },
    });
    try layout.beginScrollArea(&ui, .{ .id = "inspector-scroll", .height = 60.0, .input = layout.panel_scroll_input });
    try widgets_basic.label(&ui, "Transform");
    try widgets_basic.label(&ui, "Object");
    try widgets_basic.label(&ui, "Parent");
    try layout.endScrollArea(&ui);
    layout.endPanel(&ui);

    try std.testing.expectEqual(@as(f32, 36.0), try ui.getScrollState(scroll_id));
}

test "ui context can consume input hook" {
    var ui = UiContext.init(std.testing.allocator);
    defer ui.deinit();

    var hook_context = UiInputHookTestContext{};
    ui.setInputHook(.{
        .context = &hook_context,
        .vtable = &test_input_vtable,
    });
    try ui.beginFrameFromHook();

    try layout.beginPanel(&ui, .{
        .id = "viewport",
        .rect = .{ .x = 10.0, .y = 10.0, .w = 300.0, .h = 200.0 },
    });
    try widgets_basic.label(&ui, "Scene");
    const button_result = try widgets_basic.button(&ui, "Focus");
    layout.endPanel(&ui);

    try std.testing.expect(button_result.hovered);
    try std.testing.expect(ui.renderCommands().len >= 3);
}
