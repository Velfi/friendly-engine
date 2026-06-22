const std = @import("std");
const commands = @import("commands.zig");
const context = @import("context.zig");
const input = @import("input.zig");
const layout = @import("layout.zig");

pub const TextInputOptions = struct {
    id: []const u8,
    default_text: []const u8 = "",
};

pub fn textInput(ui: *context.UiContext, options: TextInputOptions) !struct { text: []const u8, changed: bool, submitted: bool } {
    const stable = try ui.stableId(options.id, options.id);
    var text_state = try ui.getTextState(stable, options.default_text);
    const rect = try ui.allocFullWidthRow((try ui.currentLayout()).row_height);
    const focused = input.claimFocus(ui, stable, rect);
    var changed = false;

    if (focused) {
        for (ui.input.key_chars) |ch| {
            try ui.appendTextChar(stable, ch);
            changed = true;
        }
        if (ui.input.backspace_pressed) {
            ui.backspaceText(stable);
            changed = true;
        }
        text_state = try ui.getTextState(stable, options.default_text);
    }

    const click = input.handleClick(ui, stable, rect);
    try ui.pushCommand(.{
        .text_input = .{
            .id = ui.nextCommandId(stable),
            .rect = rect,
            .text = try ui.dupeText(text_state.buffer),
            .cursor = text_state.cursor,
            .focused = focused,
            .hovered = click.hovered,
        },
    });

    const submitted = focused and ui.input.enter_pressed;
    return .{
        .text = text_state.buffer,
        .changed = changed,
        .submitted = submitted,
    };
}

pub fn searchInput(ui: *context.UiContext, id: []const u8) !struct { text: []const u8, changed: bool, submitted: bool } {
    const result = try textInput(ui, .{ .id = id, .default_text = "" });
    return .{ .text = result.text, .changed = result.changed, .submitted = result.submitted };
}

pub const NumberInputOptions = struct {
    id: []const u8,
    value: f32,
    min: f32 = 0.0,
    max: f32 = 100.0,
    speed: f32 = 0.1,
};

pub fn numberInput(ui: *context.UiContext, options: NumberInputOptions) !struct { value: f32, changed: bool } {
    const stable = try ui.stableId(options.id, options.id);
    var value = try ui.getFloatState(stable, options.value);
    const rect = try ui.allocFullWidthRow((try ui.currentLayout()).row_height);
    const focused = input.claimFocus(ui, stable, rect);
    const drag = input.handleDrag(ui, stable, rect);
    var changed = false;

    if (drag.dragging) {
        value += drag.drag_delta_x * options.speed;
        value = std.math.clamp(value, options.min, options.max);
        try ui.setFloatState(stable, value);
        changed = true;
    }

    if (focused) {
        for (ui.input.key_chars) |ch| {
            if (ch >= '0' and ch <= '9' or ch == '.' or ch == '-') {
                try ui.appendTextChar(stable, ch);
                changed = true;
            }
        }
        if (ui.input.backspace_pressed) {
            ui.backspaceText(stable);
            changed = true;
        }
        if (ui.input.enter_pressed) {
            const text_state = try ui.getTextState(stable, "");
            value = try std.fmt.parseFloat(f32, text_state.buffer);
            value = std.math.clamp(value, options.min, options.max);
            try ui.setFloatState(stable, value);
            changed = true;
        }
    }
    if (!focused and !drag.dragging and @abs(value - options.value) > 0.0001) {
        value = std.math.clamp(options.value, options.min, options.max);
        try ui.setFloatState(stable, value);
    }

    var text_buf: [32]u8 = undefined;
    const text = input.formatFloat(&text_buf, value);
    try ui.pushCommand(.{
        .number_input = .{
            .id = ui.nextCommandId(stable),
            .rect = rect,
            .text = try ui.dupeText(text),
            .value = value,
            .dragging = drag.dragging,
            .hovered = drag.hovered,
            .focused = focused,
        },
    });
    return .{ .value = value, .changed = changed };
}

pub const SliderOptions = struct {
    id: []const u8,
    value: f32,
    min: f32 = 0.0,
    max: f32 = 1.0,
};

pub fn slider(ui: *context.UiContext, options: SliderOptions) !struct { value: f32, changed: bool } {
    const stable = try ui.stableId(options.id, options.id);
    var value = try ui.getFloatState(stable, options.value);
    const rect = try ui.allocFullWidthRow((try ui.currentLayout()).row_height);
    const drag = input.handleDrag(ui, stable, rect);
    var changed = false;

    if (drag.dragging or drag.hovered and ui.input.primary_pressed) {
        const t = std.math.clamp((ui.input.mouse_position.x - rect.x) / @max(1.0, rect.w), 0.0, 1.0);
        value = options.min + (options.max - options.min) * t;
        try ui.setFloatState(stable, value);
        changed = true;
    }

    const fill_w = rect.w * ((value - options.min) / @max(0.0001, options.max - options.min));
    try ui.pushCommand(.{
        .slider = .{
            .id = ui.nextCommandId(stable),
            .rect = rect,
            .track_rect = rect,
            .fill_rect = .{ .x = rect.x, .y = rect.y, .w = fill_w, .h = rect.h },
            .value = value,
            .hovered = drag.hovered,
            .active = drag.dragging,
        },
    });
    return .{ .value = value, .changed = changed };
}

pub fn checkbox(ui: *context.UiContext, label_text: []const u8, explicit_id: ?[]const u8) !struct { checked: bool, clicked: bool } {
    const stable = try ui.stableId(explicit_id, label_text);
    var checked = try ui.getBoolState(stable, false);
    const row_h = (try ui.currentLayout()).row_height;
    const rect = try ui.allocFullWidthRow(row_h);
    const box_size = @min(row_h - 8.0, 16.0);
    const box_rect = context.Rect{
        .x = rect.x + @import("text_layout.zig").pad_x,
        .y = rect.y + (row_h - box_size) * 0.5,
        .w = box_size,
        .h = box_size,
    };
    const click = input.handleClick(ui, stable, rect);
    if (click.clicked) checked = !checked;
    try ui.setBoolState(stable, checked);
    try ui.pushCommand(.{
        .checkbox = .{
            .id = ui.nextCommandId(stable),
            .rect = rect,
            .box_rect = box_rect,
            .text = try ui.dupeText(label_text),
            .checked = checked,
            .hovered = click.hovered,
            .active = click.active,
        },
    });
    return .{ .checked = checked, .clicked = click.clicked };
}

pub const SelectItem = struct {
    id: []const u8,
    label: []const u8,
};

pub fn select(ui: *context.UiContext, id: []const u8, items: []const SelectItem) !?[]const u8 {
    const stable = try ui.stableId(id, id);
    const selected_index = try ui.getIntState(stable, 0);
    const open = try ui.getBoolState(stable ^ 0xA11CE, false);
    const rect = try ui.allocFullWidthRow((try ui.currentLayout()).row_height);
    const click = input.handleClick(ui, stable, rect);
    var open_state = open;
    if (click.clicked) open_state = !open_state;
    try ui.setBoolState(stable ^ 0xA11CE, open_state);

    const selected_label = if (selected_index >= 0 and selected_index < items.len)
        items[@intCast(selected_index)].label
    else if (items.len > 0)
        items[0].label
    else
        "";

    try ui.pushCommand(.{
        .select = .{
            .id = ui.nextCommandId(stable),
            .rect = rect,
            .text = try ui.dupeText(selected_label),
            .open = open_state,
            .hovered = click.hovered,
            .active = click.active,
        },
    });

    var changed_label: ?[]const u8 = null;
    if (open_state) {
        for (items, 0..) |item, index| {
            const item_rect = try ui.allocFullWidthRow((try ui.currentLayout()).row_height);
            const item_stable = try ui.stableId(item.id, item.label);
            const item_click = input.handleClick(ui, item_stable, item_rect);
            const is_selected = selected_index == @as(i32, @intCast(index));
            if (item_click.clicked) {
                try ui.setIntState(stable, @intCast(index));
                try ui.setBoolState(stable ^ 0xA11CE, false);
                changed_label = item.label;
            }
            try ui.pushCommand(.{
                .select_item = .{
                    .id = ui.nextCommandId(item_stable),
                    .select_id = stable,
                    .rect = item_rect,
                    .text = try ui.dupeText(item.label),
                    .selected = is_selected,
                    .hovered = item_click.hovered,
                },
            });
        }
    }
    return changed_label;
}

pub fn combobox(ui: *context.UiContext, id: []const u8, items: []const SelectItem) !?[]const u8 {
    const stable = try ui.stableId(id, id);
    const open_key = stable ^ 0xC08B0001;
    const highlight_key = stable ^ 0xB1CC0123;
    const filter_key = stable ^ 0xF11EE123;
    const arrow_key = stable ^ 0xA77A0123;

    var open = try ui.getBoolState(open_key, false);
    const selected_index = try ui.getIntState(stable, if (items.len > 0) 0 else -1);
    var highlight = try ui.getIntState(highlight_key, selected_index);

    const row_h = (try ui.currentLayout()).row_height;
    const rect = try ui.allocFullWidthRow(row_h);
    const arrow_w = 24.0;
    const text_rect = context.Rect{
        .x = rect.x,
        .y = rect.y,
        .w = rect.w - arrow_w,
        .h = rect.h,
    };
    const arrow_rect = context.Rect{
        .x = rect.x + rect.w - arrow_w,
        .y = rect.y,
        .w = arrow_w,
        .h = rect.h,
    };

    const text_click = input.handleClick(ui, stable, text_rect);
    const arrow_click = input.handleClick(ui, arrow_key, arrow_rect);
    const focused = input.claimFocus(ui, stable, text_rect);

    if (text_click.clicked or arrow_click.clicked) {
        open = !open;
        if (open) highlight = selected_index;
    }

    var filter_state = try ui.getTextState(filter_key, "");
    if (focused) {
        for (ui.input.key_chars) |ch| {
            try ui.appendTextChar(filter_key, ch);
            open = true;
        }
        if (ui.input.backspace_pressed) {
            ui.backspaceText(filter_key);
            open = true;
        }
        if (ui.input.escape_pressed) open = false;
        filter_state = try ui.getTextState(filter_key, "");
    }

    var filtered_indices: [64]i32 = undefined;
    var filtered_count: usize = 0;
    for (items, 0..) |item, index| {
        if (filtered_count >= filtered_indices.len) break;
        if (filter_state.buffer.len == 0 or std.mem.indexOf(u8, item.label, filter_state.buffer) != null) {
            filtered_indices[filtered_count] = @intCast(index);
            filtered_count += 1;
        }
    }

    if (focused and open) {
        if (ui.input.down_pressed) {
            highlight = nextFilteredIndex(filtered_indices[0..filtered_count], highlight, 1);
        }
        if (ui.input.up_pressed) {
            highlight = nextFilteredIndex(filtered_indices[0..filtered_count], highlight, -1);
        }
    }

    if (filtered_count > 0 and open) {
        var found = false;
        for (filtered_indices[0..filtered_count]) |candidate| {
            if (candidate == highlight) {
                found = true;
                break;
            }
        }
        if (!found) highlight = filtered_indices[0];
    }

    const display_text = if (focused and open)
        filter_state.buffer
    else if (selected_index >= 0 and selected_index < items.len)
        items[@intCast(selected_index)].label
    else if (items.len > 0)
        items[0].label
    else
        "";

    try ui.pushCommand(.{
        .combobox = .{
            .id = ui.nextCommandId(stable),
            .rect = rect,
            .text_rect = text_rect,
            .arrow_rect = arrow_rect,
            .text = try ui.dupeText(display_text),
            .open = open,
            .focused = focused,
            .hovered = text_click.hovered or arrow_click.hovered,
            .active = text_click.active or arrow_click.active,
        },
    });

    var changed_label: ?[]const u8 = null;
    var popup_hit = rect.contains(ui.input.mouse_position);

    if (open) {
        for (0..filtered_count) |filtered_slot| {
            const item_index = filtered_indices[filtered_slot];
            const item = items[@intCast(item_index)];
            const item_rect = try ui.allocFullWidthRow(row_h);
            popup_hit = popup_hit or item_rect.contains(ui.input.mouse_position);
            const item_stable = try ui.stableId(item.id, item.label);
            const item_click = input.handleClick(ui, item_stable, item_rect);
            const is_selected = selected_index == item_index;
            const is_highlighted = highlight == item_index;
            if (item_click.clicked) {
                try ui.setIntState(stable, item_index);
                try ui.setBoolState(open_key, false);
                try ui.resetTextState(filter_key, "");
                changed_label = item.label;
            }
            try ui.pushCommand(.{
                .combobox_item = .{
                    .id = ui.nextCommandId(item_stable),
                    .combobox_id = stable,
                    .rect = item_rect,
                    .text = try ui.dupeText(item.label),
                    .selected = is_selected,
                    .highlighted = is_highlighted,
                    .hovered = item_click.hovered,
                },
            });
        }

        if (focused and ui.input.enter_pressed and filtered_count > 0) {
            const picked = highlight;
            if (picked >= 0 and picked < items.len) {
                try ui.setIntState(stable, picked);
                try ui.setBoolState(open_key, false);
                changed_label = items[@intCast(picked)].label;
            }
        }
    }

    if (open and ui.input.primary_pressed and !popup_hit) {
        open = false;
    }

    try ui.setBoolState(open_key, open);
    try ui.setIntState(highlight_key, highlight);
    return changed_label;
}

fn nextFilteredIndex(filtered: []const i32, current: i32, direction: i32) i32 {
    if (filtered.len == 0) return current;
    var slot: usize = 0;
    while (slot < filtered.len and filtered[slot] != current) : (slot += 1) {}
    if (slot >= filtered.len) return filtered[0];
    const next = @as(i32, @intCast(slot)) + direction;
    const clamped = std.math.clamp(next, 0, @as(i32, @intCast(filtered.len - 1)));
    return filtered[@intCast(clamped)];
}

test "combobox filter and select" {
    const items = [_]SelectItem{
        .{ .id = "a", .label = "Alpha" },
        .{ .id = "b", .label = "Beta" },
        .{ .id = "c", .label = "Gamma" },
    };

    var ui = context.UiContext.init(std.testing.allocator);
    defer ui.deinit();

    ui.beginFrame(.{
        .mouse_position = .{ .x = 20, .y = 14 },
        .primary_pressed = true,
    });
    try layout.beginPanel(&ui, .{ .id = "p", .rect = .{ .x = 0, .y = 0, .w = 200, .h = 120 } });
    _ = try combobox(&ui, "pick", &items);
    layout.endPanel(&ui);

    ui.beginFrame(.{
        .mouse_position = .{ .x = 20, .y = 14 },
        .primary_released = true,
    });
    ui.active_widget = try ui.stableId("pick", "pick");
    ui.focused_widget = try ui.stableId("pick", "pick");
    try layout.beginPanel(&ui, .{ .id = "p", .rect = .{ .x = 0, .y = 0, .w = 200, .h = 120 } });
    _ = try combobox(&ui, "pick", &items);
    layout.endPanel(&ui);

    ui.beginFrame(.{
        .mouse_position = .{ .x = 20, .y = 40 },
        .key_chars = "Be",
    });
    ui.focused_widget = try ui.stableId("pick", "pick");
    try layout.beginPanel(&ui, .{ .id = "p", .rect = .{ .x = 0, .y = 0, .w = 200, .h = 120 } });
    _ = try combobox(&ui, "pick", &items);
    layout.endPanel(&ui);

    ui.beginFrame(.{
        .mouse_position = .{ .x = 20, .y = 40 },
        .primary_pressed = true,
    });
    try layout.beginPanel(&ui, .{ .id = "p", .rect = .{ .x = 0, .y = 0, .w = 200, .h = 120 } });
    _ = try combobox(&ui, "pick", &items);
    layout.endPanel(&ui);

    ui.beginFrame(.{
        .mouse_position = .{ .x = 20, .y = 40 },
        .primary_released = true,
    });
    ui.active_widget = try ui.stableId("b", "Beta");
    try layout.beginPanel(&ui, .{ .id = "p", .rect = .{ .x = 0, .y = 0, .w = 200, .h = 120 } });
    const picked = try combobox(&ui, "pick", &items);
    layout.endPanel(&ui);

    try std.testing.expectEqualStrings("Beta", picked.?);
}

pub fn fieldRow(ui: *context.UiContext, label_text: []const u8, control_width_ratio: f32) !struct { label_rect: context.Rect, control_rect: context.Rect } {
    return layout.fieldRow(ui, label_text, control_width_ratio);
}

test "number input drag changes value" {
    var ui = context.UiContext.init(std.testing.allocator);
    defer ui.deinit();
    ui.beginFrame(.{
        .mouse_position = .{ .x = 50, .y = 20 },
        .primary_down = true,
        .primary_pressed = true,
    });
    try layout.beginPanel(&ui, .{ .id = "p", .rect = .{ .x = 0, .y = 0, .w = 200, .h = 100 } });
    _ = try numberInput(&ui, .{ .id = "x", .value = 1.0 });
    layout.endPanel(&ui);

    ui.beginFrame(.{
        .mouse_position = .{ .x = 70, .y = 20 },
        .primary_down = true,
    });
    ui.active_widget = try ui.stableId("x", "x");
    try layout.beginPanel(&ui, .{ .id = "p", .rect = .{ .x = 0, .y = 0, .w = 200, .h = 100 } });
    const result = try numberInput(&ui, .{ .id = "x", .value = 1.0 });
    layout.endPanel(&ui);
    try std.testing.expect(result.value > 1.0);
}

test "number input refreshes from external value when idle" {
    var ui = context.UiContext.init(std.testing.allocator);
    defer ui.deinit();
    ui.beginFrame(.{});
    try layout.beginPanel(&ui, .{ .id = "p", .rect = .{ .x = 0, .y = 0, .w = 200, .h = 100 } });
    _ = try numberInput(&ui, .{ .id = "x", .value = 1.0 });
    layout.endPanel(&ui);

    ui.beginFrame(.{});
    try layout.beginPanel(&ui, .{ .id = "p", .rect = .{ .x = 0, .y = 0, .w = 200, .h = 100 } });
    const result = try numberInput(&ui, .{ .id = "x", .value = 2.5 });
    layout.endPanel(&ui);

    try std.testing.expectApproxEqAbs(@as(f32, 2.5), result.value, 0.0001);
    try std.testing.expect(!result.changed);
}
