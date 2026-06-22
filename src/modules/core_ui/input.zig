const std = @import("std");
const core = @import("../../core/mod.zig");
const context = @import("context.zig");

pub const InputState = struct {
    mouse_position: core.math.Vec2f = .{ .x = 0.0, .y = 0.0 },
    primary_down: bool = false,
    primary_pressed: bool = false,
    primary_released: bool = false,
    primary_click_count: u8 = 0,
    scroll_delta_x: f32 = 0.0,
    scroll_delta_y: f32 = 0.0,
    scroll_is_precise: bool = false,
    scroll_direction_flipped: bool = false,
    navigation_scroll_x: f32 = 0.0,
    navigation_scroll_y: f32 = 0.0,
    motion_delta_x: f32 = 0.0,
    motion_delta_y: f32 = 0.0,
    middle_down: bool = false,
    middle_pressed: bool = false,
    middle_released: bool = false,
    right_button_down: bool = false,
    right_button_pressed: bool = false,
    right_button_released: bool = false,
    keyboard_mods: u16 = 0,
    key_chars: []const u8 = "",
    backspace_pressed: bool = false,
    enter_pressed: bool = false,
    tab_pressed: bool = false,
    escape_pressed: bool = false,
    left_pressed: bool = false,
    right_pressed: bool = false,
    up_pressed: bool = false,
    down_pressed: bool = false,
    shift_down: bool = false,
    ctrl_down: bool = false,
};

pub const InputHookVTable = struct {
    collect: *const fn (context_ptr: *anyopaque, state: *InputState) anyerror!void,
};

pub const InputHook = struct {
    context: *anyopaque,
    vtable: *const InputHookVTable,
};

pub const ClickResult = struct {
    hovered: bool = false,
    clicked: bool = false,
    active: bool = false,
};

pub fn isHovered(ui: *const context.UiContext, rect: context.Rect) bool {
    return effectiveHover(ui, rect);
}

fn effectiveHover(ui: *const context.UiContext, rect: context.Rect) bool {
    if (!rect.contains(ui.input.mouse_position)) return false;
    const layout = ui.layout_stack.items;
    if (layout.len == 0) return true;
    const cursor = layout[layout.len - 1];
    if (cursor.clip_rect) |clip| return clip.contains(ui.input.mouse_position);
    return true;
}

pub fn handleClick(ui: *context.UiContext, widget_id: context.WidgetId, rect: context.Rect) ClickResult {
    const hovered = effectiveHover(ui, rect);
    if (hovered) {
        ui.hot_widget = widget_id;
        if (ui.input.primary_pressed) {
            ui.active_widget = widget_id;
        }
    }

    const active = ui.active_widget != null and ui.active_widget.? == widget_id;
    const clicked = hovered and active and ui.input.primary_released;
    if (ui.input.primary_released and active) {
        ui.active_widget = null;
    }

    return .{
        .hovered = hovered,
        .clicked = clicked,
        .active = active,
    };
}

pub const DragResult = struct {
    hovered: bool = false,
    dragging: bool = false,
    drag_delta_x: f32 = 0.0,
    drag_delta_y: f32 = 0.0,
};

pub fn handleDrag(
    ui: *context.UiContext,
    widget_id: context.WidgetId,
    rect: context.Rect,
) DragResult {
    return handleDrag2D(ui, widget_id, rect);
}

pub fn handleDrag2D(
    ui: *context.UiContext,
    widget_id: context.WidgetId,
    rect: context.Rect,
) DragResult {
    const hovered = effectiveHover(ui, rect);
    if (hovered and ui.input.primary_pressed) {
        ui.active_widget = widget_id;
    }

    const dragging = ui.active_widget != null and ui.active_widget.? == widget_id and ui.input.primary_down;
    if (ui.input.primary_released and ui.active_widget != null and ui.active_widget.? == widget_id) {
        ui.active_widget = null;
    }

    const drag_delta_x = if (dragging) ui.input.mouse_position.x - ui.drag_start_x else 0.0;
    const drag_delta_y = if (dragging) ui.input.mouse_position.y - ui.drag_start_y else 0.0;
    if (ui.input.primary_pressed and hovered) {
        ui.drag_start_x = ui.input.mouse_position.x;
        ui.drag_start_y = ui.input.mouse_position.y;
    }

    return .{
        .hovered = hovered,
        .dragging = dragging,
        .drag_delta_x = drag_delta_x,
        .drag_delta_y = drag_delta_y,
    };
}

pub fn claimFocus(ui: *context.UiContext, widget_id: context.WidgetId, rect: context.Rect) bool {
    const hovered = effectiveHover(ui, rect);
    if (hovered and ui.input.primary_pressed) {
        ui.focused_widget = widget_id;
    }
    return ui.focused_widget != null and ui.focused_widget.? == widget_id;
}

pub fn formatFloat(buf: []u8, value: f32) []const u8 {
    return std.fmt.bufPrint(buf, "{d:.3}", .{value}) catch "0";
}

test "handleClick detects press and release" {
    var ui = context.UiContext.init(std.testing.allocator);
    defer ui.deinit();

    ui.beginFrame(.{
        .mouse_position = .{ .x = 20.0, .y = 20.0 },
        .primary_down = true,
        .primary_pressed = true,
    });
    const press = handleClick(&ui, 42, .{ .x = 10, .y = 10, .w = 100, .h = 24 });
    try std.testing.expect(press.hovered);
    try std.testing.expect(press.active);

    ui.beginFrame(.{
        .mouse_position = .{ .x = 20.0, .y = 20.0 },
        .primary_released = true,
    });
    ui.active_widget = 42;
    const release = handleClick(&ui, 42, .{ .x = 10, .y = 10, .w = 100, .h = 24 });
    try std.testing.expect(release.clicked);
}
