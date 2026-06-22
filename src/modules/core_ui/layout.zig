const std = @import("std");
const commands = @import("commands.zig");
const context = @import("context.zig");
const input = @import("input.zig");
const input_tree = @import("input_tree.zig");

pub const ButtonResult = struct {
    id: context.WidgetId,
    rect: context.Rect,
    hovered: bool,
    clicked: bool,
};

// Re-exported for widgets_basic.zig

pub fn beginPanel(ui: *context.UiContext, desc: context.PanelDesc) !void {
    const panel_id = try ui.stableId(desc.id, desc.id);
    try input_tree.pushPanel(ui, desc.rect);
    const content_x = desc.rect.x + desc.padding;
    const content_w = @max(0.0, desc.rect.w - (desc.padding * 2.0));
    try ui.pushCommand(.{
        .panel = .{
            .id = ui.nextCommandId(panel_id),
            .rect = desc.rect,
        },
    });
    try ui.layout_stack.append(ui.allocator, .{
        .panel_id = panel_id,
        .panel_rect = desc.rect,
        .cursor_x = content_x,
        .cursor_y = desc.rect.y + desc.padding,
        .content_x = content_x,
        .content_w = content_w,
        .row_height = desc.row_height,
        .spacing = desc.spacing,
        .inline_spacing = desc.inline_spacing,
    });
    try ui.id_prefix_marks.append(ui.allocator, ui.id_prefix.items.len);
    try ui.id_prefix.appendSlice(ui.allocator, desc.id);
    try ui.id_prefix.append(ui.allocator, '/');
}

pub fn endPanel(ui: *context.UiContext) void {
    input_tree.pop(ui);
    if (ui.layout_stack.items.len > 0) {
        _ = ui.layout_stack.pop();
    }
    if (ui.id_prefix_marks.items.len > 0) {
        const mark = ui.id_prefix_marks.items[ui.id_prefix_marks.items.len - 1];
        _ = ui.id_prefix_marks.pop();
        ui.id_prefix.shrinkRetainingCapacity(mark);
    }
}

pub fn separator(ui: *context.UiContext) !void {
    const cursor = try ui.currentLayout();
    const rect = try ui.allocFullWidthRow(1.0);
    const stable = try ui.stableId(null, "separator");
    try ui.pushCommand(.{
        .separator = .{
            .id = ui.nextCommandId(stable),
            .rect = rect,
        },
    });
    _ = cursor;
}

pub fn spacer(ui: *context.UiContext, height: f32) !void {
    const stable = try ui.stableId(null, "spacer");
    const rect = try ui.allocFullWidthRow(height);
    try ui.pushCommand(.{
        .spacer = .{
            .id = ui.nextCommandId(stable),
            .rect = rect,
        },
    });
}

pub fn sameLine(ui: *context.UiContext) !void {
    const cursor = try ui.currentLayout();
    cursor.same_line = true;
    cursor.same_line_y = cursor.cursor_y;
    cursor.cursor_x = cursor.content_x;
}

pub fn endSameLine(ui: *context.UiContext) !void {
    const cursor = try ui.currentLayout();
    if (cursor.same_line) {
        cursor.same_line = false;
        cursor.cursor_y = cursor.same_line_y + cursor.row_height + cursor.spacing;
        cursor.cursor_x = cursor.content_x;
    }
}

pub const ScrollAreaOptions = struct {
    id: []const u8,
    height: f32,
    input: ScrollAreaInput = .{},
};

pub const ScrollAreaInput = struct {
    wheel: bool = true,
    mouse_drag: bool = false,
    keyboard: bool = false,
    navigation: bool = false,
    drag_scale: f32 = 1.0,
    keyboard_lines: f32 = 3.0,
    navigation_lines: f32 = 3.0,
};

pub const VirtualListRange = struct {
    start: usize,
    end: usize,
    top_padding: f32,
    bottom_padding: f32,
};

pub fn computeVirtualListRange(total_count: usize, row_height: f32, spacing: f32, scroll_y: f32, viewport_height: f32) VirtualListRange {
    if (total_count == 0 or row_height <= 0 or viewport_height <= 0) return .{ .start = 0, .end = 0, .top_padding = 0, .bottom_padding = 0 };
    const pitch = row_height + @max(0, spacing);
    const first = @as(usize, @intFromFloat(@max(0, scroll_y) / pitch));
    const visible = @as(usize, @intFromFloat(@ceil(viewport_height / pitch))) + 2;
    const start = @min(first, total_count);
    const end = @min(total_count, start + visible);
    return .{
        .start = start,
        .end = end,
        .top_padding = @as(f32, @floatFromInt(start)) * pitch,
        .bottom_padding = @as(f32, @floatFromInt(total_count - end)) * pitch,
    };
}

pub fn virtualListRange(ui: *context.UiContext, total_count: usize, row_height: f32) !VirtualListRange {
    const cursor = try ui.currentLayout();
    return computeVirtualListRange(total_count, row_height, cursor.spacing, cursor.scroll_y, cursor.scroll_viewport_height);
}

pub fn virtualListSpacer(ui: *context.UiContext, height: f32) !void {
    if (height <= 0) return;
    try spacer(ui, height);
}

pub const panel_scroll_input = ScrollAreaInput{
    .wheel = true,
    .mouse_drag = true,
    .keyboard = true,
    .navigation = true,
};

pub fn remainingPanelContentHeight(ui: *context.UiContext) !f32 {
    const cursor = try ui.currentLayout();
    const padding = cursor.content_x - cursor.panel_rect.x;
    const content_bottom = cursor.panel_rect.y + cursor.panel_rect.h - padding;
    return @max(0, content_bottom - cursor.cursor_y);
}

pub fn beginScrollArea(ui: *context.UiContext, options: ScrollAreaOptions) !void {
    const stable = try ui.stableId(options.id, options.id);
    const rect = try ui.allocFullWidthRow(options.height);
    try input_tree.pushScrollArea(ui, rect, stable);
    const cursor = try ui.currentLayout();
    const scroll_y = try ui.getScrollState(stable);
    const owns_pointer = input_tree.ownsScrollAt(ui, stable);
    if (options.input.mouse_drag and owns_pointer and ui.input.primary_pressed) {
        ui.focused_widget = stable;
        ui.active_widget = stable;
    }
    if ((options.input.keyboard or options.input.navigation) and owns_pointer and ui.input.primary_pressed) {
        ui.focused_widget = stable;
    }
    const focused = ui.focused_widget != null and ui.focused_widget.? == stable;
    const dragging = options.input.mouse_drag and ui.active_widget != null and ui.active_widget.? == stable and ui.input.primary_down;
    var next_scroll = scroll_y;
    const wheel_delta_y = if (ui.input.scroll_direction_flipped) -ui.input.scroll_delta_y else ui.input.scroll_delta_y;
    if (options.input.wheel and owns_pointer and wheel_delta_y != 0) {
        const scroll_scale = if (ui.input.scroll_is_precise) 1.0 else cursor.row_height + cursor.spacing;
        next_scroll = @max(0, next_scroll - wheel_delta_y * scroll_scale);
    }
    if (dragging and ui.input.motion_delta_y != 0) {
        next_scroll = @max(0, next_scroll - ui.input.motion_delta_y * options.input.drag_scale);
    }
    if (focused and options.input.keyboard) {
        var keyboard_delta: f32 = 0.0;
        if (ui.input.up_pressed) keyboard_delta += 1.0;
        if (ui.input.down_pressed) keyboard_delta -= 1.0;
        if (keyboard_delta != 0) {
            next_scroll = @max(0, next_scroll - keyboard_delta * (cursor.row_height + cursor.spacing) * options.input.keyboard_lines);
        }
    }
    if (focused and options.input.navigation and ui.input.navigation_scroll_y != 0) {
        next_scroll = @max(0, next_scroll - ui.input.navigation_scroll_y * (cursor.row_height + cursor.spacing) * options.input.navigation_lines);
    }
    if (ui.input.primary_released and ui.active_widget != null and ui.active_widget.? == stable) {
        ui.active_widget = null;
    }
    if (next_scroll != scroll_y) try ui.setScrollState(stable, next_scroll);
    const updated_scroll = try ui.getScrollState(stable);
    const command_index = ui.commands.items.len;
    try ui.pushCommand(.{
        .scroll_area = .{
            .id = ui.nextCommandId(stable),
            .rect = rect,
            .clip_rect = rect,
            .scroll_y = updated_scroll,
        },
    });
    cursor.clip_rect = rect;
    cursor.scroll_y = updated_scroll;
    cursor.scroll_viewport_bottom = rect.y + rect.h;
    cursor.scroll_area_id = stable;
    cursor.scroll_command_index = command_index;
    cursor.scroll_content_top = rect.y;
    cursor.scroll_viewport_height = rect.h;
    cursor.cursor_x = cursor.content_x;
    cursor.cursor_y = rect.y;
    cursor.same_line = false;
}

pub fn endScrollArea(ui: *context.UiContext) !void {
    input_tree.pop(ui);
    if (ui.layout_stack.items.len > 0) {
        const cursor = &ui.layout_stack.items[ui.layout_stack.items.len - 1];
        if (cursor.scroll_area_id) |scroll_id| {
            const content_h = @max(0.0, cursor.cursor_y - cursor.scroll_content_top);
            const max_scroll = @max(0.0, content_h - cursor.scroll_viewport_height);
            if (cursor.scroll_command_index) |command_index| {
                if (command_index < ui.commands.items.len) {
                    switch (ui.commands.items[command_index]) {
                        .scroll_area => |*area| {
                            area.content_height = content_h;
                            area.max_scroll = max_scroll;
                        },
                        else => {},
                    }
                }
            }
            if (cursor.scroll_y > max_scroll) {
                try ui.setScrollState(scroll_id, max_scroll);
                cursor.scroll_y = max_scroll;
                if (cursor.scroll_command_index) |command_index| {
                    if (command_index < ui.commands.items.len) {
                        switch (ui.commands.items[command_index]) {
                            .scroll_area => |*area| area.scroll_y = max_scroll,
                            else => {},
                        }
                    }
                }
            }
        }
        if (cursor.scroll_viewport_bottom > 0) {
            cursor.cursor_y = cursor.scroll_viewport_bottom + cursor.spacing;
        }
        cursor.clip_rect = null;
        cursor.scroll_y = 0.0;
        cursor.scroll_viewport_bottom = 0.0;
        cursor.scroll_area_id = null;
        cursor.scroll_command_index = null;
        cursor.scroll_content_top = 0.0;
        cursor.scroll_viewport_height = 0.0;
    }
    try ui.pushCommand(.{ .scroll_area_end = .{} });
}

pub const SplitPaneOptions = struct {
    id: []const u8,
    rect: context.Rect,
    axis: commands.SplitAxis,
    ratio: *f32,
    min_first: f32 = 50.0,
    min_second: f32 = 50.0,
    handle_size: f32 = 4.0,
};

pub const SplitPaneResult = struct {
    first: context.Rect,
    second: context.Rect,
};

pub fn splitPane(ui: *context.UiContext, options: SplitPaneOptions) !SplitPaneResult {
    const stable = try ui.stableId(options.id, options.id);
    var ratio = try ui.getFloatState(stable, options.ratio.*);
    ratio = std.math.clamp(ratio, 0.05, 0.95);

    var first: context.Rect = undefined;
    var second: context.Rect = undefined;
    var handle_rect: context.Rect = undefined;

    switch (options.axis) {
        .horizontal => {
            const usable = options.rect.w - options.handle_size;
            const first_w = std.math.clamp(usable * ratio, options.min_first, usable - options.min_second);
            ratio = first_w / @max(1.0, usable);
            first = .{
                .x = options.rect.x,
                .y = options.rect.y,
                .w = first_w,
                .h = options.rect.h,
            };
            handle_rect = .{
                .x = options.rect.x + first_w,
                .y = options.rect.y,
                .w = options.handle_size,
                .h = options.rect.h,
            };
            second = .{
                .x = handle_rect.x + options.handle_size,
                .y = options.rect.y,
                .w = options.rect.w - first_w - options.handle_size,
                .h = options.rect.h,
            };
        },
        .vertical => {
            const usable = options.rect.h - options.handle_size;
            const first_h = std.math.clamp(usable * ratio, options.min_first, usable - options.min_second);
            ratio = first_h / @max(1.0, usable);
            first = .{
                .x = options.rect.x,
                .y = options.rect.y,
                .w = options.rect.w,
                .h = first_h,
            };
            handle_rect = .{
                .x = options.rect.x,
                .y = options.rect.y + first_h,
                .w = options.rect.w,
                .h = options.handle_size,
            };
            second = .{
                .x = options.rect.x,
                .y = handle_rect.y + options.handle_size,
                .w = options.rect.w,
                .h = options.rect.h - first_h - options.handle_size,
            };
        },
    }

    const drag = input.handleDrag2D(ui, stable, handle_rect);
    if (drag.dragging) {
        switch (options.axis) {
            .horizontal => {
                const usable = options.rect.w - options.handle_size;
                const next_first = std.math.clamp(first.w + drag.drag_delta_x, options.min_first, usable - options.min_second);
                ratio = next_first / @max(1.0, usable);
            },
            .vertical => {
                const usable = options.rect.h - options.handle_size;
                const next_first = std.math.clamp(first.h + drag.drag_delta_y, options.min_first, usable - options.min_second);
                ratio = next_first / @max(1.0, usable);
            },
        }
    }

    try ui.setFloatState(stable, ratio);
    options.ratio.* = ratio;

    try ui.pushCommand(.{
        .split_pane = .{
            .id = ui.nextCommandId(stable),
            .rect = options.rect,
            .handle_rect = handle_rect,
            .axis = options.axis,
            .dragging = drag.dragging,
            .hovered = drag.hovered,
        },
    });

    return .{ .first = first, .second = second };
}

test "split pane drag updates ratio" {
    var ui = context.UiContext.init(std.testing.allocator);
    defer ui.deinit();
    var ratio: f32 = 0.5;

    ui.beginFrame(.{
        .mouse_position = .{ .x = 100, .y = 10 },
        .primary_pressed = true,
    });
    ui.beginFrame(.{
        .mouse_position = .{ .x = 130, .y = 10 },
        .primary_down = true,
    });
    ui.active_widget = try ui.stableId("main", "main");
    ui.drag_start_x = 100.0;

    const split = try splitPane(&ui, .{
        .id = "main",
        .rect = .{ .x = 0, .y = 0, .w = 200, .h = 100 },
        .axis = .horizontal,
        .ratio = &ratio,
    });
    try std.testing.expect(split.first.w > 0.0);
    try std.testing.expect(split.second.w > 0.0);
    try std.testing.expect(ratio > 0.5);
}

pub fn fieldRow(ui: *context.UiContext, label_text: []const u8, control_width_ratio: f32) !struct { label_rect: context.Rect, control_rect: context.Rect } {
    const cursor = try ui.currentLayout();
    const row_h = cursor.row_height;
    const row_y = cursor.cursor_y - cursor.scroll_y;
    const label_w = cursor.content_w * (1.0 - control_width_ratio);
    const control_w = cursor.content_w * control_width_ratio;
    const label_rect = context.Rect{
        .x = cursor.content_x,
        .y = row_y,
        .w = label_w,
        .h = row_h,
    };
    const control_rect = context.Rect{
        .x = cursor.content_x + label_w,
        .y = row_y,
        .w = control_w,
        .h = row_h,
    };
    const stable = try ui.stableId(null, label_text);
    try ui.pushCommand(.{
        .label = .{
            .id = ui.nextCommandId(stable),
            .rect = label_rect,
            .text = try ui.dupeText(label_text),
        },
    });
    cursor.cursor_y += row_h + cursor.spacing;
    return .{ .label_rect = label_rect, .control_rect = control_rect };
}

test "panel layout advances cursor" {
    var ui = context.UiContext.init(std.testing.allocator);
    defer ui.deinit();
    ui.beginFrame(.{});
    try beginPanel(&ui, .{
        .id = "panel",
        .rect = .{ .x = 0, .y = 0, .w = 200, .h = 200 },
    });
    try spacer(&ui, 12.0);
    endPanel(&ui);
    try std.testing.expectEqual(@as(usize, 2), ui.renderCommands().len);
}

test "virtual list range tracks first middle and end windows" {
    const first = computeVirtualListRange(1000, 20, 4, 0, 100);
    try std.testing.expectEqual(@as(usize, 0), first.start);
    try std.testing.expect(first.end < 10);
    try std.testing.expect(first.bottom_padding > 0);

    const middle = computeVirtualListRange(1000, 20, 4, 2400, 100);
    try std.testing.expectEqual(@as(usize, 100), middle.start);
    try std.testing.expect(middle.end > middle.start);
    try std.testing.expect(middle.top_padding > 0);
    try std.testing.expect(middle.bottom_padding > 0);

    const end = computeVirtualListRange(1000, 20, 4, 24000, 100);
    try std.testing.expectEqual(@as(usize, 1000), end.start);
    try std.testing.expectEqual(@as(usize, 1000), end.end);
    try std.testing.expectEqual(@as(f32, 0), end.bottom_padding);
}
