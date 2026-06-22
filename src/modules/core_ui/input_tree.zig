const std = @import("std");
const core = @import("../../core/mod.zig");
const context = @import("context.zig");

pub const Capture = packed struct {
    pointer: bool = false,
    scroll: bool = false,
    keyboard: bool = false,
};

pub const Node = struct {
    rect: context.Rect,
    captures: Capture,
    scroll_id: ?context.WidgetId = null,
};

pub fn reset(ui: *context.UiContext) void {
    ui.input_nodes.clearRetainingCapacity();
}

pub fn pushPanel(ui: *context.UiContext, rect: context.Rect) !void {
    try push(ui, .{
        .rect = rect,
        .captures = .{ .pointer = true, .scroll = true },
    });
}

pub fn pushOverlay(ui: *context.UiContext, rect: context.Rect) !void {
    try push(ui, .{
        .rect = rect,
        .captures = .{ .pointer = true, .scroll = true, .keyboard = true },
    });
}

pub fn pushScrollArea(ui: *context.UiContext, rect: context.Rect, scroll_id: context.WidgetId) !void {
    try push(ui, .{
        .rect = rect,
        .captures = .{ .scroll = true },
        .scroll_id = scroll_id,
    });
}

pub fn pop(ui: *context.UiContext) void {
    _ = ui;
}

pub fn topNodeAt(ui: *const context.UiContext, point: core.math.Vec2f, capture: Capture) ?Node {
    var index = ui.input_nodes.items.len;
    while (index > 0) {
        index -= 1;
        const node = ui.input_nodes.items[index];
        if (!nodeIntersectsCapture(node.captures, capture)) continue;
        if (!node.rect.contains(point)) continue;
        return node;
    }
    return null;
}

pub fn blocksPointerAt(ui: *const context.UiContext, point: core.math.Vec2f) bool {
    return topNodeAt(ui, point, .{ .pointer = true }) != null;
}

pub fn blocksViewportPointer(ui: *const context.UiContext) bool {
    return blocksPointerAt(ui, ui.input.mouse_position);
}

pub fn blocksViewportScroll(ui: *const context.UiContext) bool {
    return topNodeAt(ui, ui.input.mouse_position, .{ .scroll = true }) != null;
}

pub fn blocksKeyboard(ui: *const context.UiContext) bool {
    var index = ui.input_nodes.items.len;
    while (index > 0) {
        index -= 1;
        if (ui.input_nodes.items[index].captures.keyboard) return true;
    }
    return false;
}

pub fn ownsScrollAt(ui: *const context.UiContext, scroll_id: context.WidgetId) bool {
    const node = topNodeAt(ui, ui.input.mouse_position, .{ .scroll = true }) orelse return false;
    return node.scroll_id == scroll_id;
}

fn push(ui: *context.UiContext, node: Node) !void {
    try ui.input_nodes.append(ui.allocator, node);
}

fn nodeIntersectsCapture(node_captures: Capture, query: Capture) bool {
    if (query.pointer and node_captures.pointer) return true;
    if (query.scroll and node_captures.scroll) return true;
    if (query.keyboard and node_captures.keyboard) return true;
    return false;
}

test "top node prefers later registration" {
    var ui = context.UiContext.init(std.testing.allocator);
    defer ui.deinit();

    ui.beginFrame(.{ .mouse_position = .{ .x = 50, .y = 50 } });
    try pushPanel(&ui, .{ .x = 0, .y = 0, .w = 100, .h = 100 });
    try pushPanel(&ui, .{ .x = 40, .y = 40, .w = 40, .h = 40 });

    const top = topNodeAt(&ui, .{ .x = 50, .y = 50 }, .{ .scroll = true }).?;
    try std.testing.expect(top.rect.w == 40);

    pop(&ui);
    try std.testing.expect(topNodeAt(&ui, .{ .x = 50, .y = 50 }, .{ .scroll = true }).?.rect.w == 40);
}
