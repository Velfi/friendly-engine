const std = @import("std");
const friendly = @import("friendly_engine");
const gpu_scene = @import("gpu_scene.zig");
const shared_color = @import("color.zig");
const core_ui_font = @import("core_ui_font.zig");

const core_ui = friendly.modules.core_ui;

pub const Style = struct {
    panel_color: shared_color.Color = .{ .r = 24, .g = 30, .b = 40, .a = 236 },
    button_color: shared_color.Color = .{ .r = 42, .g = 50, .b = 64, .a = 255 },
    button_hovered_color: shared_color.Color = .{ .r = 58, .g = 69, .b = 86, .a = 255 },
    button_active_color: shared_color.Color = .{ .r = 76, .g = 94, .b = 120, .a = 255 },
    button_disabled_color: shared_color.Color = .{ .r = 32, .g = 36, .b = 44, .a = 255 },
    accent_color: shared_color.Color = .{ .r = 76, .g = 130, .b = 200, .a = 255 },
    text_color: shared_color.Color = .{ .r = 220, .g = 226, .b = 234, .a = 255 },
    muted_text_color: shared_color.Color = .{ .r = 140, .g = 150, .b = 165, .a = 255 },
    separator_color: shared_color.Color = .{ .r = 52, .g = 60, .b = 74, .a = 255 },
    input_bg_color: shared_color.Color = .{ .r = 18, .g = 22, .b = 30, .a = 255 },
    input_focus_color: shared_color.Color = .{ .r = 32, .g = 40, .b = 54, .a = 255 },
    toggle_on_color: shared_color.Color = .{ .r = 56, .g = 96, .b = 148, .a = 255 },
    selected_color: shared_color.Color = .{ .r = 48, .g = 72, .b = 108, .a = 255 },
    error_color: shared_color.Color = .{ .r = 180, .g = 60, .b = 60, .a = 255 },
    warning_color: shared_color.Color = .{ .r = 200, .g = 140, .b = 40, .a = 255 },
    info_color: shared_color.Color = .{ .r = 50, .g = 90, .b = 140, .a = 255 },
    tooltip_bg_color: shared_color.Color = .{ .r = 36, .g = 44, .b = 58, .a = 250 },
    progress_fill_color: shared_color.Color = .{ .r = 70, .g = 120, .b = 180, .a = 255 },
    checkbox_check_color: shared_color.Color = .{ .r = 120, .g = 180, .b = 255, .a = 255 },
};

pub fn appendCoreUiOverlayQuads(
    allocator: std.mem.Allocator,
    commands: []const core_ui.RenderCommand,
    style: Style,
    out: *std.ArrayList(gpu_scene.OverlayQuad),
) !void {
    var clips: [8]core_ui.Rect = undefined;
    var scroll_areas: [8]core_ui.commands.ScrollAreaCommand = undefined;
    var clip_depth: usize = 0;

    for (commands) |command| {
        switch (command) {
            .scroll_area => |area| {
                try out.append(allocator, quadFromRect(area.rect, .{ .r = 20, .g = 24, .b = 32, .a = 180 }));
                if (clip_depth < clips.len) {
                    if (clip_depth > 0) {
                        clips[clip_depth] = clips[clip_depth - 1].intersect(area.clip_rect) orelse .{ .x = 0, .y = 0, .w = 0, .h = 0 };
                    } else {
                        clips[clip_depth] = area.clip_rect;
                    }
                    scroll_areas[clip_depth] = area;
                    clip_depth += 1;
                }
            },
            .scroll_area_end => {
                if (clip_depth > 0) {
                    clip_depth -= 1;
                    try appendScrollbar(allocator, out, scroll_areas[clip_depth], style);
                }
            },
            .tooltip => {},
            else => try appendCommandQuads(
                allocator,
                command,
                style,
                out,
                if (clip_depth > 0) clips[clip_depth - 1] else null,
            ),
        }
    }

    for (commands) |command| {
        switch (command) {
            .tooltip => |tip| {
                const tip_w = core_ui.text_layout.tooltipWidth(tip.text);
                const tip_rect = core_ui.Rect{ .x = tip.rect.x, .y = tip.rect.y, .w = tip_w, .h = tip.rect.h };
                try clippedAppendQuad(allocator, out, tip_rect, style.tooltip_bg_color, null);
                try appendTextTopAligned(allocator, tip_rect, tip.text, core_ui.text_layout.pad_x, style.text_color, out, null);
            },
            else => {},
        }
    }
}

fn clipRect(rect: core_ui.Rect, clip: ?core_ui.Rect) ?core_ui.Rect {
    if (clip) |active| return active.intersect(rect);
    return rect;
}

fn clippedAppendQuad(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(gpu_scene.OverlayQuad),
    rect: core_ui.Rect,
    color: shared_color.Color,
    clip: ?core_ui.Rect,
) !void {
    const clipped = clipRect(rect, clip) orelse return;
    if (clipped.w <= 0 or clipped.h <= 0) return;
    try out.append(allocator, quadFromRect(clipped, color));
}

fn appendScrollbar(allocator: std.mem.Allocator, out: *std.ArrayList(gpu_scene.OverlayQuad), area: core_ui.commands.ScrollAreaCommand, style: Style) !void {
    const thumb = scrollThumbRect(area) orelse return;
    const track = core_ui.Rect{ .x = area.rect.x + area.rect.w - 5.0, .y = area.rect.y + 3.0, .w = 2.0, .h = @max(0.0, area.rect.h - 6.0) };
    try clippedAppendQuad(allocator, out, track, style.separator_color, null);
    try clippedAppendQuad(allocator, out, thumb, style.muted_text_color, null);
}

fn scrollThumbRect(area: core_ui.commands.ScrollAreaCommand) ?core_ui.Rect {
    if (area.max_scroll <= 0.0 or area.content_height <= area.rect.h) return null;
    const inset: f32 = 3.0;
    const track_h = @max(0.0, area.rect.h - inset * 2.0);
    if (track_h <= 0.0) return null;
    const thumb_h = std.math.clamp(area.rect.h * area.rect.h / @max(1.0, area.content_height), @min(18.0, track_h), track_h);
    const t = std.math.clamp(area.scroll_y / area.max_scroll, 0.0, 1.0);
    return .{
        .x = area.rect.x + area.rect.w - 7.0,
        .y = area.rect.y + inset + (track_h - thumb_h) * t,
        .w = 4.0,
        .h = thumb_h,
    };
}

fn appendCommandQuads(
    allocator: std.mem.Allocator,
    command: core_ui.RenderCommand,
    style: Style,
    out: *std.ArrayList(gpu_scene.OverlayQuad),
    clip: ?core_ui.Rect,
) !void {
    switch (command) {
        .panel => |panel| try clippedAppendQuad(allocator, out, panel.rect, style.panel_color, clip),
        .label, .text => |text_cmd| {
            try appendText(allocator, text_cmd.rect, text_cmd.text, textColor(style, text_cmd.muted), out, clip);
        },
        .status_label => |label| {
            try appendText(allocator, label.rect, label.text, style.muted_text_color, out, clip);
        },
        .button => |button| {
            const color = if (button.disabled)
                style.button_disabled_color
            else
                buttonColor(style, button.hovered, button.active, false);
            try clippedAppendQuad(allocator, out, button.rect, color, clip);
            try appendTextCentered(allocator, button.rect, button.text, if (button.disabled) style.muted_text_color else style.text_color, out, clip);
        },
        .icon_button => |button| {
            const color = buttonColor(style, button.hovered, button.active, button.toggled);
            try clippedAppendQuad(allocator, out, button.rect, color, clip);
            try appendTextCentered(allocator, button.rect, button.icon, style.text_color, out, clip);
        },
        .toggle => |toggle| {
            const color = if (toggle.value)
                style.toggle_on_color
            else
                buttonColor(style, toggle.hovered, toggle.active, false);
            try clippedAppendQuad(allocator, out, toggle.rect, color, clip);
            try appendTextCentered(allocator, toggle.rect, toggle.text, style.text_color, out, clip);
        },
        .toggle_group_item => |item| {
            const color = if (item.selected)
                style.selected_color
            else
                buttonColor(style, item.hovered, item.active, false);
            try clippedAppendQuad(allocator, out, item.rect, color, clip);
            try appendTextCentered(allocator, item.rect, item.text, style.text_color, out, clip);
        },
        .separator => |sep| try clippedAppendQuad(allocator, out, sep.rect, style.separator_color, clip),
        .spacer => {},
        .text_input => |field| {
            const bg = if (field.focused) style.input_focus_color else style.input_bg_color;
            try clippedAppendQuad(allocator, out, field.rect, bg, clip);
            if (field.focused) {
                const border = core_ui.Rect{ .x = field.rect.x, .y = field.rect.y, .w = 2.0, .h = field.rect.h };
                try clippedAppendQuad(allocator, out, border, style.accent_color, clip);
            }
            try appendTextCentered(allocator, field.rect, field.text, style.text_color, out, clip);
        },
        .number_input => |field| {
            const bg = if (field.focused or field.dragging) style.input_focus_color else style.input_bg_color;
            try clippedAppendQuad(allocator, out, field.rect, bg, clip);
            try appendTextCentered(allocator, field.rect, field.text, style.text_color, out, clip);
        },
        .slider => |slider| {
            try clippedAppendQuad(allocator, out, slider.track_rect, style.input_bg_color, clip);
            try clippedAppendQuad(allocator, out, slider.fill_rect, style.progress_fill_color, clip);
        },
        .checkbox => |box| {
            try clippedAppendQuad(allocator, out, box.box_rect, style.input_bg_color, clip);
            if (box.checked) {
                const inset = box.box_rect.inset(4.0);
                try clippedAppendQuad(allocator, out, inset, style.checkbox_check_color, clip);
            }
            const text_rect = core_ui.Rect{
                .x = box.box_rect.x + box.box_rect.w + 6.0,
                .y = box.rect.y,
                .w = box.rect.w - box.box_rect.w - 6.0,
                .h = box.rect.h,
            };
            try appendText(allocator, text_rect, box.text, style.text_color, out, clip);
        },
        .select => |dropdown| {
            const color = buttonColor(style, dropdown.hovered, dropdown.active, dropdown.open);
            try clippedAppendQuad(allocator, out, dropdown.rect, color, clip);
            try appendTextCentered(allocator, dropdown.rect, dropdown.text, style.text_color, out, clip);
        },
        .select_item => |item| {
            const color = if (item.selected) style.selected_color else style.input_bg_color;
            try clippedAppendQuad(allocator, out, item.rect, color, clip);
            try appendTextCentered(allocator, item.rect, item.text, style.text_color, out, clip);
        },
        .tab => |tab| {
            const color = if (tab.selected)
                style.selected_color
            else
                buttonColor(style, tab.hovered, tab.active, false);
            try clippedAppendQuad(allocator, out, tab.rect, color, clip);
            try appendTextCentered(allocator, tab.rect, tab.text, style.text_color, out, clip);
        },
        .tree_node => |node| {
            const transparent = shared_color.Color{ .r = 0, .g = 0, .b = 0, .a = 0 };
            const color = if (node.hovered) style.button_hovered_color else transparent;
            if (color.a > 0) try clippedAppendQuad(allocator, out, node.rect, color, clip);
            const prefix = if (node.open) "\u{25BE} " else "\u{25B8} ";
            var buf: [128]u8 = undefined;
            const text = std.fmt.bufPrint(&buf, "{s}{s}", .{ prefix, node.text }) catch node.text;
            try appendText(allocator, node.rect, text, style.text_color, out, clip);
        },
        .selectable => |row| {
            if (row.selected or row.hovered) {
                const color = if (row.selected) style.selected_color else style.button_hovered_color;
                try clippedAppendQuad(allocator, out, row.rect, color, clip);
            }
            try appendTextTopAligned(allocator, row.rect, row.text, row.text_pad_x, style.text_color, out, clip);
        },
        .asset_preview => |preview| {
            const fill = if (preview.selected)
                style.selected_color
            else if (preview.hovered)
                style.button_hovered_color
            else
                style.input_bg_color;
            try clippedAppendQuad(allocator, out, preview.rect, fill, clip);
            try clippedAppendQuad(allocator, out, preview.thumbnail_rect, .{ .r = 16, .g = 20, .b = 28, .a = 255 }, clip);
            try appendPreviewShape(allocator, out, preview, clip);
            try appendText(allocator, preview.text_rect, preview.label, style.text_color, out, clip);
        },
        .scroll_area, .scroll_area_end => {},
        .tooltip => |tip| {
            try clippedAppendQuad(allocator, out, tip.rect, style.tooltip_bg_color, clip);
            try appendText(allocator, tip.rect, tip.text, style.text_color, out, clip);
        },
        .badge => |pill| {
            const color = badgeColor(style, pill.variant);
            try clippedAppendQuad(allocator, out, pill.rect, color, clip);
            try appendText(allocator, pill.rect, pill.text, style.text_color, out, clip);
        },
        .collapsing_header => |header| {
            const color = buttonColor(style, header.hovered, header.active, header.open);
            try clippedAppendQuad(allocator, out, header.rect, color, clip);
            const prefix = if (header.open) "\u{25BE} " else "\u{25B8} ";
            var buf: [128]u8 = undefined;
            const text = std.fmt.bufPrint(&buf, "{s}{s}", .{ prefix, header.text }) catch header.text;
            try appendText(allocator, header.rect, text, style.text_color, out, clip);
        },
        .progress_bar => |bar| {
            try clippedAppendQuad(allocator, out, bar.rect, style.input_bg_color, clip);
            try clippedAppendQuad(allocator, out, bar.fill_rect, style.progress_fill_color, clip);
        },
        .inline_alert => |alert| {
            const color = alertColor(style, alert.variant);
            try clippedAppendQuad(allocator, out, alert.rect, color, clip);
            try appendText(allocator, alert.rect, alert.text, style.text_color, out, clip);
        },
        .table_header_cell => |cell| {
            const color = if (cell.sort_active)
                style.selected_color
            else
                buttonColor(style, cell.hovered, cell.active, false);
            try clippedAppendQuad(allocator, out, cell.rect, color, clip);
            try appendText(allocator, cell.rect, cell.text, style.text_color, out, clip);
        },
        .table_row => |row| {
            if (row.selected or row.hovered) {
                const color = if (row.selected) style.selected_color else style.button_hovered_color;
                try clippedAppendQuad(allocator, out, row.rect, color, clip);
            }
        },
        .table_cell => |cell| {
            try appendText(allocator, cell.rect, cell.text, style.text_color, out, clip);
        },
        .combobox => |box| {
            const bg = if (box.focused) style.input_focus_color else buttonColor(style, box.hovered, box.active, box.open);
            try clippedAppendQuad(allocator, out, box.text_rect, bg, clip);
            try appendText(allocator, box.text_rect, box.text, style.text_color, out, clip);
            const arrow_color = buttonColor(style, box.hovered, box.active, box.open);
            try clippedAppendQuad(allocator, out, box.arrow_rect, arrow_color, clip);
            try appendText(allocator, box.arrow_rect, "\u{25BE}", style.text_color, out, clip);
        },
        .combobox_item => |item| {
            const color = if (item.selected)
                style.selected_color
            else if (item.highlighted)
                style.button_hovered_color
            else
                style.input_bg_color;
            try clippedAppendQuad(allocator, out, item.rect, color, clip);
            try appendText(allocator, item.rect, item.text, style.text_color, out, clip);
        },
        .split_pane => |pane| {
            const handle_color = if (pane.dragging or pane.hovered)
                style.accent_color
            else
                style.separator_color;
            try clippedAppendQuad(allocator, out, pane.handle_rect, handle_color, clip);
        },
        .spinner => |spin| {
            if (clipRect(spin.rect, clip)) |clipped_rect| {
                try appendSpinner(allocator, clipped_rect, spin.rotation, style.accent_color, out);
            }
            if (spin.label_rect) |label_rect| {
                if (spin.label) |label_text| {
                    try appendText(allocator, label_rect, label_text, style.muted_text_color, out, clip);
                }
            }
        },
    }
}

fn appendText(
    allocator: std.mem.Allocator,
    rect: core_ui.Rect,
    text: []const u8,
    color: shared_color.Color,
    out: *std.ArrayList(gpu_scene.OverlayQuad),
    clip: ?core_ui.Rect,
) !void {
    try appendTextTopAligned(allocator, rect, text, core_ui.text_layout.pad_x, color, out, clip);
}

fn appendTextCentered(
    allocator: std.mem.Allocator,
    rect: core_ui.Rect,
    text: []const u8,
    color: shared_color.Color,
    out: *std.ArrayList(gpu_scene.OverlayQuad),
    clip: ?core_ui.Rect,
) !void {
    try appendTextCenteredWithPad(allocator, rect, text, core_ui.text_layout.pad_x, color, out, clip);
}

fn appendTextTopAligned(
    allocator: std.mem.Allocator,
    rect: core_ui.Rect,
    text: []const u8,
    pad_x: f32,
    color: shared_color.Color,
    out: *std.ArrayList(gpu_scene.OverlayQuad),
    clip: ?core_ui.Rect,
) !void {
    const clipped = clipRect(rect, clip) orelse return;
    if (clipped.w <= 0 or clipped.h <= 0) return;
    const max_width = core_ui.text_layout.textWidthForPad(clipped, pad_x);
    const top_y = core_ui.text_layout.overlayTextTopAlignedY(clipped);
    try core_ui_font.appendTextQuadsBounded(text, clipped.x + pad_x, top_y, max_width, color, out, allocator);
}

fn appendTextCenteredWithPad(
    allocator: std.mem.Allocator,
    rect: core_ui.Rect,
    text: []const u8,
    pad_x: f32,
    color: shared_color.Color,
    out: *std.ArrayList(gpu_scene.OverlayQuad),
    clip: ?core_ui.Rect,
) !void {
    const clipped = clipRect(rect, clip) orelse return;
    if (clipped.w <= 0 or clipped.h <= 0) return;
    const max_width = core_ui.text_layout.textWidthForPad(clipped, pad_x);
    const top_y = core_ui.text_layout.overlayTextCenteredY(clipped);
    try core_ui_font.appendTextQuadsBounded(text, clipped.x + pad_x, top_y, max_width, color, out, allocator);
}

fn textColor(style: Style, muted: bool) shared_color.Color {
    return if (muted) style.muted_text_color else style.text_color;
}

fn buttonColor(style: Style, hovered: bool, active: bool, toggled: bool) shared_color.Color {
    if (toggled) return style.toggle_on_color;
    if (active) return style.button_active_color;
    if (hovered) return style.button_hovered_color;
    return style.button_color;
}

fn badgeColor(style: Style, variant: core_ui.commands.BadgeVariant) shared_color.Color {
    return switch (variant) {
        .neutral => style.button_color,
        .accent => style.accent_color,
        .err => style.error_color,
        .warning => style.warning_color,
    };
}

fn alertColor(style: Style, variant: core_ui.commands.InlineAlertVariant) shared_color.Color {
    return switch (variant) {
        .info => style.info_color,
        .warning => style.warning_color,
        .err => style.error_color,
    };
}

fn quadFromRect(rect: core_ui.Rect, color: shared_color.Color) gpu_scene.OverlayQuad {
    return .{
        .rect = .{ rect.x, rect.y, rect.w, rect.h },
        .color = color,
    };
}

fn appendPreviewShape(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(gpu_scene.OverlayQuad),
    preview: core_ui.commands.AssetPreviewCommand,
    clip: ?core_ui.Rect,
) !void {
    const r = preview.thumbnail_rect.inset(8);
    const color = previewColor(preview.fill_color);
    const accent = previewColor(preview.accent_color);
    switch (preview.shape) {
        .box => {
            try clippedAppendQuad(allocator, out, .{ .x = r.x + 7, .y = r.y + 9, .w = r.w - 8, .h = r.h - 7 }, color, clip);
            try clippedAppendQuad(allocator, out, .{ .x = r.x + 3, .y = r.y + 4, .w = r.w - 8, .h = 8 }, accent, clip);
            try clippedAppendQuad(allocator, out, .{ .x = r.x + 3, .y = r.y + 4, .w = 8, .h = r.h - 8 }, shade(color, 0.74), clip);
        },
        .cylinder => {
            try clippedAppendQuad(allocator, out, .{ .x = r.x + 7, .y = r.y + 7, .w = r.w - 14, .h = r.h - 8 }, color, clip);
            try clippedAppendQuad(allocator, out, .{ .x = r.x + 5, .y = r.y + 4, .w = r.w - 10, .h = 6 }, accent, clip);
            try clippedAppendQuad(allocator, out, .{ .x = r.x + 5, .y = r.y + r.h - 8, .w = r.w - 10, .h = 5 }, shade(color, 0.68), clip);
        },
        .plane => {
            try clippedAppendQuad(allocator, out, .{ .x = r.x + 3, .y = r.y + r.h * 0.55, .w = r.w - 6, .h = 8 }, color, clip);
            try clippedAppendQuad(allocator, out, .{ .x = r.x + 8, .y = r.y + r.h * 0.4, .w = r.w - 16, .h = 5 }, accent, clip);
        },
        .sphere => {
            try clippedAppendQuad(allocator, out, .{ .x = r.x + 7, .y = r.y + 7, .w = r.w - 14, .h = r.h - 14 }, color, clip);
            try clippedAppendQuad(allocator, out, .{ .x = r.x + 10, .y = r.y + 9, .w = 8, .h = 8 }, accent, clip);
        },
        .region_map => {
            const gap: f32 = 1;
            const cell_w = (r.w - gap * 3) / 4;
            const cell_h = (r.h - gap * 3) / 4;
            var y: usize = 0;
            while (y < 4) : (y += 1) {
                var x: usize = 0;
                while (x < 4) : (x += 1) {
                    const bit: u4 = @intCast(y * @as(usize, 4) + x);
                    const filled = (preview.preview_mask & (@as(u16, 1) << bit)) != 0;
                    try clippedAppendQuad(allocator, out, .{
                        .x = r.x + @as(f32, @floatFromInt(x)) * (cell_w + gap),
                        .y = r.y + @as(f32, @floatFromInt(y)) * (cell_h + gap),
                        .w = cell_w,
                        .h = cell_h,
                    }, if (filled) color else shade(color, 0.38), clip);
                }
            }
            try clippedAppendQuad(allocator, out, .{ .x = r.x + r.w * 0.18, .y = r.y + r.h * 0.18, .w = r.w * 0.64, .h = 2 }, accent, clip);
        },
    }
}

fn previewColor(color: core_ui.commands.PreviewColor) shared_color.Color {
    return .{ .r = color.r, .g = color.g, .b = color.b, .a = color.a };
}

fn shade(color: shared_color.Color, factor: f32) shared_color.Color {
    return .{
        .r = @intFromFloat(@as(f32, @floatFromInt(color.r)) * factor),
        .g = @intFromFloat(@as(f32, @floatFromInt(color.g)) * factor),
        .b = @intFromFloat(@as(f32, @floatFromInt(color.b)) * factor),
        .a = color.a,
    };
}

fn appendSpinner(
    allocator: std.mem.Allocator,
    rect: core_ui.Rect,
    rotation_deg: f32,
    color: shared_color.Color,
    out: *std.ArrayList(gpu_scene.OverlayQuad),
) !void {
    const cx = rect.x + rect.w * 0.5;
    const cy = rect.y + rect.h * 0.5;
    const radius = @min(rect.w, rect.h) * 0.5;
    const dot_size = @max(2.0, radius * 0.22);
    const radians = rotation_deg * std.math.pi / 180.0;

    var i: u32 = 0;
    while (i < 8) : (i += 1) {
        const angle = radians + (@as(f32, @floatFromInt(i)) / 8.0) * std.math.pi * 2.0;
        const alpha_scale: f32 = 1.0 - (@as(f32, @floatFromInt(i)) / 8.0) * 0.65;
        const dot_color = shared_color.Color{
            .r = @intFromFloat(@round(@as(f32, @floatFromInt(color.r)) * alpha_scale)),
            .g = @intFromFloat(@round(@as(f32, @floatFromInt(color.g)) * alpha_scale)),
            .b = @intFromFloat(@round(@as(f32, @floatFromInt(color.b)) * alpha_scale)),
            .a = color.a,
        };
        const dot_rect = core_ui.Rect{
            .x = cx + @cos(angle) * radius - dot_size * 0.5,
            .y = cy + @sin(angle) * radius - dot_size * 0.5,
            .w = dot_size,
            .h = dot_size,
        };
        try out.append(allocator, quadFromRect(dot_rect, dot_color));
    }
}

test "core ui overlay renders spinner and indeterminate progress" {
    const commands = [_]core_ui.RenderCommand{
        .{ .spinner = .{
            .id = 1,
            .rect = .{ .x = 10, .y = 10, .w = 24, .h = 24 },
            .label_rect = null,
            .label = null,
            .size = .medium,
            .rotation = 30.0,
        } },
        .{ .progress_bar = .{
            .id = 2,
            .rect = .{ .x = 10, .y = 40, .w = 120, .h = 8 },
            .fill_rect = .{ .x = 20, .y = 40, .w = 40, .h = 8 },
            .value = 0.0,
            .indeterminate = true,
            .marquee_offset = 0.25,
        } },
    };

    var quads: std.ArrayList(gpu_scene.OverlayQuad) = .empty;
    defer quads.deinit(std.testing.allocator);
    try appendCoreUiOverlayQuads(std.testing.allocator, &commands, .{}, &quads);
    try std.testing.expect(quads.items.len >= 9);
}

test "core ui panel and button commands become overlay quads" {
    const commands = [_]core_ui.RenderCommand{
        .{ .panel = .{ .id = 1, .rect = .{ .x = 10, .y = 20, .w = 100, .h = 80 } } },
        .{ .label = .{ .id = 2, .rect = .{ .x = 12, .y = 22, .w = 40, .h = 20 }, .text = "Title" } },
        .{ .button = .{
            .id = 3,
            .rect = .{ .x = 14, .y = 44, .w = 60, .h = 24 },
            .text = "Run",
            .hovered = true,
            .active = false,
        } },
    };

    var quads: std.ArrayList(gpu_scene.OverlayQuad) = .empty;
    defer quads.deinit(std.testing.allocator);
    try appendCoreUiOverlayQuads(std.testing.allocator, &commands, .{}, &quads);

    try std.testing.expect(quads.items.len >= 3);
    try std.testing.expectEqual(@as(f32, 10), quads.items[0].rect[0]);
}

test "tooltips ignore scroll clipping" {
    const scroll = core_ui.Rect{ .x = 0, .y = 0, .w = 100, .h = 40 };
    const commands = [_]core_ui.RenderCommand{
        .{ .scroll_area = .{ .id = 1, .rect = scroll, .clip_rect = scroll, .scroll_y = 0 } },
        .{ .scroll_area_end = .{} },
        .{ .tooltip = .{ .id = 2, .rect = .{ .x = 10, .y = 34, .w = 48, .h = 32 }, .text = "Hide object" } },
    };

    var quads: std.ArrayList(gpu_scene.OverlayQuad) = .empty;
    defer quads.deinit(std.testing.allocator);
    try appendCoreUiOverlayQuads(std.testing.allocator, &commands, .{}, &quads);

    const expected_w = core_ui.text_layout.tooltipWidth("Hide object");
    var found_full_tooltip_bg = false;
    for (quads.items) |quad| {
        if (quad.rect[1] == 34 and quad.rect[2] == expected_w and quad.rect[3] == 32) found_full_tooltip_bg = true;
    }
    try std.testing.expect(found_full_tooltip_bg);
}
