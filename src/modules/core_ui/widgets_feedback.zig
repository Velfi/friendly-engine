const std = @import("std");
const commands = @import("commands.zig");
const context = @import("context.zig");
const input = @import("input.zig");
const layout = @import("layout.zig");
const text_layout = @import("text_layout.zig");

pub fn statusLabel(ui: *context.UiContext, text: []const u8) !void {
    const rect = try ui.allocFullWidthRow((try ui.currentLayout()).row_height);
    const stable = try ui.stableId(null, text);
    try ui.pushCommand(.{
        .status_label = .{
            .id = ui.nextCommandId(stable),
            .rect = rect,
            .text = try ui.dupeText(text),
            .muted = true,
        },
    });
}

pub fn richStatusLabel(ui: *context.UiContext, id: []const u8, spans: []const commands.rich_text.Span) !void {
    const rect = try ui.allocFullWidthRow((try ui.currentLayout()).row_height);
    const stable = try ui.stableId(id, id);
    try ui.pushCommand(.{
        .status_label = .{
            .id = ui.nextCommandId(stable),
            .rect = rect,
            .text = "",
            .spans = try ui.dupeRichText(spans),
            .muted = true,
        },
    });
}

pub fn badge(ui: *context.UiContext, text: []const u8, variant: commands.BadgeVariant) !void {
    const rect = try ui.allocRowRect(48.0, (try ui.currentLayout()).row_height);
    const stable = try ui.stableId(null, text);
    try ui.pushCommand(.{
        .badge = .{
            .id = ui.nextCommandId(stable),
            .rect = rect,
            .text = try ui.dupeText(text),
            .variant = variant,
        },
    });
}

pub fn progressBar(ui: *context.UiContext, id: []const u8, value: ?f32) !void {
    const stable = try ui.stableId(id, id);
    const rect = try ui.allocFullWidthRow(8.0);

    if (value) |determinate| {
        const clamped = std.math.clamp(determinate, 0.0, 1.0);
        const fill_rect = context.Rect{
            .x = rect.x,
            .y = rect.y,
            .w = rect.w * clamped,
            .h = rect.h,
        };
        try ui.pushCommand(.{
            .progress_bar = .{
                .id = ui.nextCommandId(stable),
                .rect = rect,
                .fill_rect = fill_rect,
                .value = clamped,
                .indeterminate = false,
            },
        });
        return;
    }

    const phase = @as(f32, @floatFromInt(ui.frame_counter % 120)) / 120.0;
    const fill_w = rect.w * 0.35;
    const fill_x = rect.x + (rect.w + fill_w) * phase - fill_w;
    try ui.pushCommand(.{
        .progress_bar = .{
            .id = ui.nextCommandId(stable),
            .rect = rect,
            .fill_rect = .{
                .x = fill_x,
                .y = rect.y,
                .w = fill_w,
                .h = rect.h,
            },
            .value = 0.0,
            .indeterminate = true,
            .marquee_offset = phase,
        },
    });
}

pub fn spinner(ui: *context.UiContext, id: []const u8, size: commands.SpinnerSize, label: ?[]const u8) !void {
    const stable = try ui.stableId(id, id);
    const diameter: f32 = switch (size) {
        .small => 16.0,
        .medium => 24.0,
    };
    const label_h: f32 = if (label != null) 18.0 else 0.0;
    const total_h = diameter + label_h;
    const rect = try ui.allocFullWidthRow(total_h);
    const spinner_rect = context.Rect{
        .x = rect.x + (rect.w - diameter) * 0.5,
        .y = rect.y,
        .w = diameter,
        .h = diameter,
    };
    const label_rect = if (label != null) context.Rect{
        .x = rect.x,
        .y = rect.y + diameter + 2.0,
        .w = rect.w,
        .h = label_h,
    } else null;
    const rotation = @as(f32, @floatFromInt(ui.frame_counter % 60)) * 6.0;

    try ui.pushCommand(.{
        .spinner = .{
            .id = ui.nextCommandId(stable),
            .rect = spinner_rect,
            .label_rect = label_rect,
            .label = if (label) |label_text| try ui.dupeText(label_text) else null,
            .size = size,
            .rotation = rotation,
        },
    });
}

test "progress bar emits determinate and indeterminate commands" {
    var ui = context.UiContext.init(std.testing.allocator);
    defer ui.deinit();
    ui.beginFrame(.{});
    try layout.beginPanel(&ui, .{ .id = "p", .rect = .{ .x = 0, .y = 0, .w = 200, .h = 80 } });
    try progressBar(&ui, "load", 0.5);
    try progressBar(&ui, "busy", null);
    layout.endPanel(&ui);

    const commands_list = ui.renderCommands();
    try std.testing.expectEqual(@as(usize, 2), commands_list.len);
    try std.testing.expect(!commands_list[0].progress_bar.indeterminate);
    try std.testing.expect(commands_list[1].progress_bar.indeterminate);
}

test "spinner emits rotation command" {
    var ui = context.UiContext.init(std.testing.allocator);
    defer ui.deinit();
    ui.beginFrame(.{});
    try layout.beginPanel(&ui, .{ .id = "p", .rect = .{ .x = 0, .y = 0, .w = 200, .h = 80 } });
    try spinner(&ui, "wait", .medium, "Loading");
    layout.endPanel(&ui);

    try std.testing.expectEqual(@as(usize, 1), ui.renderCommands().len);
    try std.testing.expect(ui.renderCommands()[0].spinner.rotation >= 0.0);
}

pub fn inlineAlert(ui: *context.UiContext, text: []const u8, variant: commands.InlineAlertVariant) !void {
    const rect = try ui.allocFullWidthRow((try ui.currentLayout()).row_height);
    const stable = try ui.stableId(null, text);
    try ui.pushCommand(.{
        .inline_alert = .{
            .id = ui.nextCommandId(stable),
            .rect = rect,
            .text = try ui.dupeText(text),
            .variant = variant,
        },
    });
}

fn tooltipMargin() f32 {
    return 4.0;
}

fn frameBounds(ui: *const context.UiContext) ?context.Rect {
    const bounds = ui.frame_bounds;
    if (bounds.w <= 0 or bounds.h <= 0) return null;
    return bounds;
}

fn fitsBelow(hover_rect: context.Rect, tip_h: f32, bounds: context.Rect) bool {
    return hover_rect.y + hover_rect.h + tooltipMargin() + tip_h <= bounds.y + bounds.h;
}

fn fitsAbove(hover_rect: context.Rect, tip_h: f32, bounds: context.Rect) bool {
    return hover_rect.y - tooltipMargin() - tip_h >= bounds.y;
}

fn tooltipRect(ui: *context.UiContext, hover_rect: context.Rect, text: []const u8) context.Rect {
    const tip_h = text_layout.tooltipHeight();
    const tip_w = text_layout.tooltipWidth(text);
    const margin = tooltipMargin();
    var tip_x = hover_rect.x;
    var tip_y = hover_rect.y + hover_rect.h + margin;

    if (frameBounds(ui)) |bounds| {
        if (!fitsBelow(hover_rect, tip_h, bounds) and fitsAbove(hover_rect, tip_h, bounds)) {
            tip_y = hover_rect.y - tip_h - margin;
        }
        if (tip_x + tip_w > bounds.x + bounds.w) {
            tip_x = @max(bounds.x, bounds.x + bounds.w - tip_w);
        }
        if (tip_x < bounds.x) tip_x = bounds.x;
    }

    return .{
        .x = tip_x,
        .y = tip_y,
        .w = tip_w,
        .h = tip_h,
    };
}

pub fn tooltip(ui: *context.UiContext, hover_rect: context.Rect, text: []const u8) !void {
    if (!input.isHovered(ui, hover_rect)) return;
    const stable = try ui.stableId(null, text);
    const tip_rect = tooltipRect(ui, hover_rect, text);
    try ui.pushTooltip(.{
        .id = ui.nextCommandId(stable),
        .rect = tip_rect,
        .text = try ui.dupeText(text),
    });
}

pub fn richTooltip(ui: *context.UiContext, hover_rect: context.Rect, id: []const u8, plain_width_text: []const u8, spans: []const commands.rich_text.Span) !void {
    if (!input.isHovered(ui, hover_rect)) return;
    const stable = try ui.stableId(id, id);
    const tip_rect = tooltipRect(ui, hover_rect, plain_width_text);
    try ui.pushTooltip(.{
        .id = ui.nextCommandId(stable),
        .rect = tip_rect,
        .text = try ui.dupeText(plain_width_text),
        .spans = try ui.dupeRichText(spans),
    });
}

pub fn tooltipOnLastItem(ui: *context.UiContext, item_rect: context.Rect, text: []const u8) !void {
    try tooltip(ui, item_rect, text);
}

test "tooltip deferred until flush" {
    var ui = context.UiContext.init(std.testing.allocator);
    defer ui.deinit();
    ui.beginFrame(.{ .mouse_position = .{ .x = 20, .y = 20 } });
    try tooltip(&ui, .{ .x = 10, .y = 10, .w = 40, .h = 20 }, "Hint");
    try std.testing.expectEqual(@as(usize, 0), ui.renderCommands().len);
    try ui.flushTooltips();
    try std.testing.expectEqual(@as(usize, 1), ui.renderCommands().len);
    const tip = ui.renderCommands()[0].tooltip;
    try std.testing.expectEqual(@as(f32, 34), tip.rect.y);
    try std.testing.expectEqual(text_layout.tooltipHeight(), tip.rect.h);
    try std.testing.expect(tip.rect.w >= text_layout.tooltipWidth("Hint"));
}

test "tooltip flips above near frame bottom" {
    var ui = context.UiContext.init(std.testing.allocator);
    defer ui.deinit();
    ui.setFrameBounds(.{ .x = 0, .y = 0, .w = 320, .h = 80 });
    ui.beginFrame(.{ .mouse_position = .{ .x = 20, .y = 70 } });
    try tooltip(&ui, .{ .x = 10, .y = 58, .w = 40, .h = 20 }, "Hint");
    try ui.flushTooltips();
    const tip = ui.renderCommands()[0].tooltip;
    try std.testing.expect(tip.rect.y < 58);
}
