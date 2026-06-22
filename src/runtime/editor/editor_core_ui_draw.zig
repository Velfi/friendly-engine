const draw_icons = @import("editor_core_ui_draw_icons.zig");

const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const draw_primitives = @import("editor_draw_primitives.zig");
const editor_draw = @import("editor_draw.zig");
const editor_ui_batch = @import("editor_ui_batch.zig");

const core_ui = friendly_engine.modules.core_ui;

pub const Style = shared.core_ui_overlay.Style;

pub const DrawContext = struct {
    renderer: *editor_draw.SDL_Renderer,
    text_renderer: *editor_draw.TextRenderer,
    batch: *editor_ui_batch.UiDrawBatch,
    style: Style,
};

pub fn drawCommands(ctx: DrawContext, commands: []const core_ui.RenderCommand) !void {
    var clips: [8]core_ui.Rect = undefined;
    var scroll_areas: [8]core_ui.commands.ScrollAreaCommand = undefined;
    var clip_depth: usize = 0;

    for (commands) |command| {
        switch (command) {
            .scroll_area => |area| {
                try fillPanel(ctx, area.rect, ctx.style.input_bg_color, ctx.style.separator_color);
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
                    try drawScrollbar(ctx, scroll_areas[clip_depth]);
                }
            },
            .tooltip => {},
            else => try drawCommand(ctx, command, if (clip_depth > 0) clips[clip_depth - 1] else null),
        }
    }

    for (commands) |command| {
        switch (command) {
            .tooltip => |tip| {
                const measured = if (tip.spans.len > 0) try ctx.text_renderer.measureRichText(tip.spans) else try ctx.text_renderer.measureText(tip.text);
                const tip_rect = core_ui.Rect{
                    .x = tip.rect.x,
                    .y = tip.rect.y,
                    .w = measured + core_ui.text_layout.pad_x + core_ui.text_layout.pad_right,
                    .h = tip.rect.h,
                };
                try fillPanelClipped(ctx, tip_rect, ctx.style.tooltip_bg_color, ctx.style.separator_color, null);
                const top_y = core_ui.text_layout.editorTextTopAlignedY(tip_rect);
                try drawCommandText(ctx, tip.text, tip.spans, tip_rect.x + core_ui.text_layout.pad_x, top_y, null, ctx.style.text_color);
            },
            else => {},
        }
    }
}

fn clipRect(rect: core_ui.Rect, clip: ?core_ui.Rect) ?core_ui.Rect {
    if (clip) |active| return active.intersect(rect);
    return rect;
}

fn drawCommand(ctx: DrawContext, command: core_ui.RenderCommand, clip: ?core_ui.Rect) !void {
    switch (command) {
        .panel => |panel| try fillPanelClipped(ctx, panel.rect, ctx.style.panel_color, ctx.style.separator_color, clip),
        .label, .text => |text| try drawRichTextTopAlignedClipped(ctx, text.rect, text.text, text.spans, textColor(ctx.style, text.muted), clip),
        .status_label => |text| try drawRichTextTopAlignedClipped(ctx, text.rect, text.text, text.spans, ctx.style.muted_text_color, clip),
        .button => |button| {
            const fill = if (button.disabled)
                ctx.style.button_disabled_color
            else
                buttonColor(ctx.style, button.hovered, button.active, false);
            const label_color = if (button.disabled) ctx.style.muted_text_color else ctx.style.text_color;
            try fillPanelClipped(ctx, button.rect, fill, ctx.style.separator_color, clip);
            try drawTextCenteredClipped(ctx, button.rect, button.text, label_color, clip);
        },
        .icon_button => |button| {
            try fillPanelClipped(ctx, button.rect, buttonColor(ctx.style, button.hovered, button.active, button.toggled), ctx.style.separator_color, clip);
            try drawIconClipped(ctx, button.rect, button.icon, ctx.style.text_color, clip);
        },
        .toggle => |toggle| {
            const fill = if (toggle.value) ctx.style.toggle_on_color else buttonColor(ctx.style, toggle.hovered, toggle.active, false);
            try fillPanelClipped(ctx, toggle.rect, fill, ctx.style.separator_color, clip);
            try drawTextCenteredClipped(ctx, toggle.rect, toggle.text, ctx.style.text_color, clip);
        },
        .toggle_group_item => |item| {
            const fill = if (item.selected) ctx.style.selected_color else buttonColor(ctx.style, item.hovered, item.active, false);
            try fillPanelClipped(ctx, item.rect, fill, ctx.style.separator_color, clip);
            try drawTextCenteredClipped(ctx, item.rect, item.text, ctx.style.text_color, clip);
        },
        .separator => |sep| try fillRectClipped(ctx.renderer, ctx.batch, sep.rect, ctx.style.separator_color, clip),
        .spacer => {},
        .text_input => |field| {
            const fill = if (field.focused) ctx.style.input_focus_color else ctx.style.input_bg_color;
            try fillPanelClipped(ctx, field.rect, fill, ctx.style.separator_color, clip);
            try drawTextCenteredClipped(ctx, field.rect, field.text, ctx.style.text_color, clip);
            if (field.focused) try fillRectClipped(ctx.renderer, ctx.batch, .{ .x = field.rect.x, .y = field.rect.y, .w = 2, .h = field.rect.h }, ctx.style.accent_color, clip);
        },
        .number_input => |field| {
            const fill = if (field.focused or field.dragging) ctx.style.input_focus_color else ctx.style.input_bg_color;
            try fillPanelClipped(ctx, field.rect, fill, ctx.style.separator_color, clip);
            try drawTextCenteredClipped(ctx, field.rect, field.text, ctx.style.text_color, clip);
        },
        .slider => |slider| {
            try fillRectClipped(ctx.renderer, ctx.batch, slider.track_rect, ctx.style.input_bg_color, clip);
            try fillRectClipped(ctx.renderer, ctx.batch, slider.fill_rect, ctx.style.progress_fill_color, clip);
        },
        .checkbox => |box| {
            try fillPanelClipped(ctx, box.box_rect, ctx.style.input_bg_color, ctx.style.separator_color, clip);
            if (box.checked) try fillRectClipped(ctx.renderer, ctx.batch, box.box_rect.inset(3.0), ctx.style.checkbox_check_color, clip);
            try drawTextTopAlignedClipped(ctx, textAfterBox(box.rect, box.box_rect), box.text, ctx.style.text_color, clip);
        },
        .select => |select| {
            try fillPanelClipped(ctx, select.rect, buttonColor(ctx.style, select.hovered, select.active, select.open), ctx.style.separator_color, clip);
            try drawTextCenteredClipped(ctx, select.rect, select.text, ctx.style.text_color, clip);
        },
        .select_item => |item| {
            const fill = if (item.selected or item.hovered) ctx.style.selected_color else ctx.style.input_bg_color;
            try fillPanelClipped(ctx, item.rect, fill, ctx.style.separator_color, clip);
            try drawTextCenteredClipped(ctx, item.rect, item.text, ctx.style.text_color, clip);
        },
        .tab => |tab| {
            const fill = if (tab.selected) ctx.style.selected_color else buttonColor(ctx.style, tab.hovered, tab.active, false);
            try fillPanelClipped(ctx, tab.rect, fill, ctx.style.separator_color, clip);
            try drawTextCenteredClipped(ctx, tab.rect, tab.text, ctx.style.text_color, clip);
        },
        .tree_node => |node| try drawExpandableRowClipped(ctx, node.rect, node.text, node.open, node.hovered, node.active, clip),
        .selectable => |row| {
            if (row.selected or row.hovered) {
                const fill = if (row.selected) ctx.style.selected_color else ctx.style.button_hovered_color;
                try fillPanelClipped(ctx, row.rect, fill, ctx.style.separator_color, clip);
            }
            try drawTextTopAlignedWithPad(ctx, row.rect, row.text, row.text_pad_x, ctx.style.text_color, clip);
        },
        .asset_preview => |preview| try drawAssetPreviewClipped(ctx, preview, clip),
        .scroll_area, .scroll_area_end => {},
        .tooltip => |tip| {
            try fillPanelClipped(ctx, tip.rect, ctx.style.tooltip_bg_color, ctx.style.separator_color, clip);
            try drawTextCenteredClipped(ctx, tip.rect, tip.text, ctx.style.text_color, clip);
        },
        .badge => |badge| {
            try fillPanelClipped(ctx, badge.rect, badgeColor(ctx.style, badge.variant), ctx.style.separator_color, clip);
            try drawTextCenteredClipped(ctx, badge.rect, badge.text, ctx.style.text_color, clip);
        },
        .collapsing_header => |header| try drawExpandableRowClipped(ctx, header.rect, header.text, header.open, header.hovered, header.active, clip),
        .progress_bar => |bar| {
            try fillPanelClipped(ctx, bar.rect, ctx.style.input_bg_color, ctx.style.separator_color, clip);
            try fillRectClipped(ctx.renderer, ctx.batch, bar.fill_rect, ctx.style.progress_fill_color, clip);
        },
        .inline_alert => |alert| {
            try fillPanelClipped(ctx, alert.rect, alertColor(ctx.style, alert.variant), ctx.style.separator_color, clip);
            try drawTextTopAlignedClipped(ctx, alert.rect, alert.text, ctx.style.text_color, clip);
        },
        .table_header_cell => |cell| {
            const fill = if (cell.sort_active) ctx.style.selected_color else buttonColor(ctx.style, cell.hovered, cell.active, false);
            try fillPanelClipped(ctx, cell.rect, fill, ctx.style.separator_color, clip);
            try drawTextCenteredClipped(ctx, cell.rect, cell.text, ctx.style.text_color, clip);
        },
        .table_row => |row| if (row.selected or row.hovered) {
            const fill = if (row.selected) ctx.style.selected_color else ctx.style.button_hovered_color;
            try fillRectClipped(ctx.renderer, ctx.batch, row.rect, fill, clip);
        },
        .table_cell => |cell| try drawTextTopAlignedClipped(ctx, cell.rect, cell.text, ctx.style.text_color, clip),
        .combobox => |box| {
            const fill = if (box.focused) ctx.style.input_focus_color else buttonColor(ctx.style, box.hovered, box.active, box.open);
            try fillPanelClipped(ctx, box.text_rect, fill, ctx.style.separator_color, clip);
            try drawTextCenteredClipped(ctx, box.text_rect, box.text, ctx.style.text_color, clip);
            try fillPanelClipped(ctx, box.arrow_rect, ctx.style.button_color, ctx.style.separator_color, clip);
            try drawIconClipped(ctx, box.arrow_rect, "chevron-down", ctx.style.text_color, clip);
        },
        .combobox_item => |item| {
            const fill = if (item.selected) ctx.style.selected_color else if (item.highlighted or item.hovered) ctx.style.button_hovered_color else ctx.style.input_bg_color;
            try fillPanelClipped(ctx, item.rect, fill, ctx.style.separator_color, clip);
            try drawTextCenteredClipped(ctx, item.rect, item.text, ctx.style.text_color, clip);
        },
        .split_pane => |pane| try fillRectClipped(ctx.renderer, ctx.batch, pane.handle_rect, if (pane.dragging or pane.hovered) ctx.style.accent_color else ctx.style.separator_color, clip),
        .spinner => |spinner| if (spinner.label_rect) |label_rect| {
            if (spinner.label) |label| try drawTextTopAlignedClipped(ctx, label_rect, label, ctx.style.muted_text_color, clip);
        },
    }
}

fn drawAssetPreviewClipped(ctx: DrawContext, preview: core_ui.commands.AssetPreviewCommand, clip: ?core_ui.Rect) !void {
    const clipped = clipRect(preview.rect, clip) orelse return;
    if (clipped.w <= 0 or clipped.h <= 0) return;
    const fill = if (preview.selected)
        ctx.style.selected_color
    else if (preview.hovered)
        ctx.style.button_hovered_color
    else
        ctx.style.input_bg_color;
    try fillPanelClipped(ctx, preview.rect, fill, ctx.style.separator_color, clip);
    try fillPanelClipped(ctx, preview.thumbnail_rect, .{ .r = 16, .g = 20, .b = 28, .a = 255 }, ctx.style.separator_color, clip);
    try drawPreviewShape(ctx, preview, clip);
    const label_rect = core_ui.Rect{ .x = preview.text_rect.x, .y = preview.text_rect.y, .w = preview.text_rect.w, .h = 22 };
    try drawTextTopAlignedClipped(ctx, label_rect, preview.label, ctx.style.text_color, clip);
    if (preview.detail.len > 0) {
        const detail_rect = core_ui.Rect{ .x = preview.text_rect.x, .y = preview.text_rect.y + 22, .w = preview.text_rect.w, .h = 18 };
        try drawTextTopAlignedClipped(ctx, detail_rect, preview.detail, ctx.style.muted_text_color, clip);
    }
}

fn drawPreviewShape(ctx: DrawContext, preview: core_ui.commands.AssetPreviewCommand, clip: ?core_ui.Rect) !void {
    const r = preview.thumbnail_rect.inset(8);
    const color = previewColor(preview.fill_color);
    const accent = previewColor(preview.accent_color);
    switch (preview.shape) {
        .box => {
            try fillRectClipped(ctx.renderer, ctx.batch, .{ .x = r.x + 7, .y = r.y + 9, .w = r.w - 8, .h = r.h - 7 }, color, clip);
            try fillRectClipped(ctx.renderer, ctx.batch, .{ .x = r.x + 3, .y = r.y + 4, .w = r.w - 8, .h = 8 }, accent, clip);
            try fillRectClipped(ctx.renderer, ctx.batch, .{ .x = r.x + 3, .y = r.y + 4, .w = 8, .h = r.h - 8 }, shade(color, 0.74), clip);
        },
        .cylinder => {
            try fillRectClipped(ctx.renderer, ctx.batch, .{ .x = r.x + 7, .y = r.y + 7, .w = r.w - 14, .h = r.h - 8 }, color, clip);
            try fillRectClipped(ctx.renderer, ctx.batch, .{ .x = r.x + 5, .y = r.y + 4, .w = r.w - 10, .h = 6 }, accent, clip);
            try fillRectClipped(ctx.renderer, ctx.batch, .{ .x = r.x + 5, .y = r.y + r.h - 8, .w = r.w - 10, .h = 5 }, shade(color, 0.68), clip);
        },
        .plane => {
            try fillRectClipped(ctx.renderer, ctx.batch, .{ .x = r.x + 3, .y = r.y + r.h * 0.55, .w = r.w - 6, .h = 8 }, color, clip);
            try fillRectClipped(ctx.renderer, ctx.batch, .{ .x = r.x + 8, .y = r.y + r.h * 0.4, .w = r.w - 16, .h = 5 }, accent, clip);
        },
        .sphere => {
            try draw_primitives.fillCircle(ctx.renderer, r.x + r.w * 0.5, r.y + r.h * 0.52, @min(r.w, r.h) * 0.34, color);
            try draw_primitives.fillCircle(ctx.renderer, r.x + r.w * 0.42, r.y + r.h * 0.4, @min(r.w, r.h) * 0.12, accent);
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
                    try fillRectClipped(ctx.renderer, ctx.batch, .{
                        .x = r.x + @as(f32, @floatFromInt(x)) * (cell_w + gap),
                        .y = r.y + @as(f32, @floatFromInt(y)) * (cell_h + gap),
                        .w = cell_w,
                        .h = cell_h,
                    }, if (filled) color else shade(color, 0.38), clip);
                }
            }
            try fillRectClipped(ctx.renderer, ctx.batch, .{ .x = r.x + r.w * 0.18, .y = r.y + r.h * 0.18, .w = r.w * 0.64, .h = 2 }, accent, clip);
        },
    }
}

fn previewColor(color: core_ui.commands.PreviewColor) editor_draw.Color {
    return .{ .r = color.r, .g = color.g, .b = color.b, .a = color.a };
}

fn shade(color: editor_draw.Color, factor: f32) editor_draw.Color {
    return .{
        .r = @intFromFloat(@as(f32, @floatFromInt(color.r)) * factor),
        .g = @intFromFloat(@as(f32, @floatFromInt(color.g)) * factor),
        .b = @intFromFloat(@as(f32, @floatFromInt(color.b)) * factor),
        .a = color.a,
    };
}

fn fillPanelClipped(ctx: DrawContext, rect: core_ui.Rect, fill: editor_draw.Color, border: editor_draw.Color, clip: ?core_ui.Rect) !void {
    const clipped = clipRect(rect, clip) orelse return;
    if (clipped.w <= 0 or clipped.h <= 0) return;
    try fillPanel(ctx, clipped, fill, border);
}

fn fillRectClipped(renderer: *editor_draw.SDL_Renderer, batch: *editor_ui_batch.UiDrawBatch, rect: core_ui.Rect, color: editor_draw.Color, clip: ?core_ui.Rect) !void {
    const clipped = clipRect(rect, clip) orelse return;
    if (clipped.w <= 0 or clipped.h <= 0) return;
    try fillRect(renderer, batch, clipped, color);
}

fn drawScrollbar(ctx: DrawContext, area: core_ui.commands.ScrollAreaCommand) !void {
    const thumb = scrollThumbRect(area) orelse return;
    const track = core_ui.Rect{ .x = area.rect.x + area.rect.w - 5.0, .y = area.rect.y + 3.0, .w = 2.0, .h = @max(0.0, area.rect.h - 6.0) };
    try fillRectClipped(ctx.renderer, ctx.batch, track, ctx.style.separator_color, null);
    try fillRectClipped(ctx.renderer, ctx.batch, thumb, ctx.style.muted_text_color, null);
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

fn drawIconClipped(ctx: DrawContext, rect: core_ui.Rect, icon: []const u8, color: editor_draw.Color, clip: ?core_ui.Rect) !void {
    const clipped = clipRect(rect, clip) orelse return;
    if (clipped.w <= 0 or clipped.h <= 0) return;
    try drawIcon(ctx, clipped, icon, color);
}

fn drawExpandableRowClipped(
    ctx: DrawContext,
    rect: core_ui.Rect,
    text: []const u8,
    open: bool,
    hovered: bool,
    active: bool,
    clip: ?core_ui.Rect,
) !void {
    const clipped = clipRect(rect, clip) orelse return;
    if (clipped.w <= 0 or clipped.h <= 0) return;
    try drawExpandableRow(ctx, clipped, text, open, hovered, active);
}

fn fillPanel(ctx: DrawContext, rect: core_ui.Rect, fill: editor_draw.Color, border: editor_draw.Color) !void {
    try editor_draw.drawPanel(ctx.renderer, toSdlRect(rect), fill, border);
}

fn fillRect(renderer: *editor_draw.SDL_Renderer, batch: *editor_ui_batch.UiDrawBatch, rect: core_ui.Rect, color: editor_draw.Color) !void {
    _ = batch;
    if (!editor_draw.SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a)) return error.SdlColorSetFailed;
    var sdl_rect = toSdlRect(rect);
    if (!editor_draw.SDL_RenderFillRect(renderer, &sdl_rect)) return error.SdlFillRectFailed;
}

fn drawTextTopAlignedClipped(ctx: DrawContext, rect: core_ui.Rect, text: []const u8, color: editor_draw.Color, clip: ?core_ui.Rect) !void {
    try drawTextTopAlignedWithPad(ctx, rect, text, core_ui.text_layout.pad_x, color, clip);
}

fn drawTextCenteredClipped(ctx: DrawContext, rect: core_ui.Rect, text: []const u8, color: editor_draw.Color, clip: ?core_ui.Rect) !void {
    try drawTextCenteredWithPad(ctx, rect, text, core_ui.text_layout.pad_x, color, clip);
}

fn drawTextTopAlignedWithPad(
    ctx: DrawContext,
    rect: core_ui.Rect,
    text: []const u8,
    pad_x: f32,
    color: editor_draw.Color,
    clip: ?core_ui.Rect,
) !void {
    const clipped = clipRect(rect, clip) orelse return;
    if (clipped.w <= 0 or clipped.h <= 0) return;
    const text_w = core_ui.text_layout.textWidthForPad(clipped, pad_x);
    const top_y = core_ui.text_layout.editorTextTopAlignedY(clipped);
    try drawCommandText(ctx, text, &.{}, clipped.x + pad_x, top_y, text_w, color);
}

fn drawTextCenteredWithPad(
    ctx: DrawContext,
    rect: core_ui.Rect,
    text: []const u8,
    pad_x: f32,
    color: editor_draw.Color,
    clip: ?core_ui.Rect,
) !void {
    const clipped = clipRect(rect, clip) orelse return;
    if (clipped.w <= 0 or clipped.h <= 0) return;
    const text_w = core_ui.text_layout.textWidthForPad(clipped, pad_x);
    const top_y = core_ui.text_layout.editorTextCenteredY(clipped);
    try drawCommandText(ctx, text, &.{}, clipped.x + pad_x, top_y, text_w, color);
}

fn drawRichTextTopAlignedClipped(ctx: DrawContext, rect: core_ui.Rect, text: []const u8, spans: core_ui.rich_text.RichText, color: editor_draw.Color, clip: ?core_ui.Rect) !void {
    const clipped = clipRect(rect, clip) orelse return;
    if (clipped.w <= 0 or clipped.h <= 0) return;
    const text_w = core_ui.text_layout.textWidthForPad(clipped, core_ui.text_layout.pad_x);
    const top_y = core_ui.text_layout.editorTextTopAlignedY(clipped);
    try drawCommandText(ctx, text, spans, clipped.x + core_ui.text_layout.pad_x, top_y, text_w, color);
}

fn drawRichTextCenteredClipped(ctx: DrawContext, rect: core_ui.Rect, text: []const u8, spans: core_ui.rich_text.RichText, color: editor_draw.Color, clip: ?core_ui.Rect) !void {
    const clipped = clipRect(rect, clip) orelse return;
    if (clipped.w <= 0 or clipped.h <= 0) return;
    const text_w = core_ui.text_layout.textWidthForPad(clipped, core_ui.text_layout.pad_x);
    const top_y = core_ui.text_layout.editorTextCenteredY(clipped);
    try drawCommandText(ctx, text, spans, clipped.x + core_ui.text_layout.pad_x, top_y, text_w, color);
}

fn drawCommandText(ctx: DrawContext, text: []const u8, spans: core_ui.rich_text.RichText, x: f32, y: f32, max_width: ?f32, color: editor_draw.Color) !void {
    if (spans.len > 0) {
        try ctx.text_renderer.drawRichInRect(ctx.renderer, ctx.batch, spans, x, y, max_width, color);
    } else {
        try ctx.text_renderer.drawInRect(ctx.renderer, ctx.batch, text, x, y, max_width, color);
    }
}

fn drawIcon(ctx: DrawContext, rect: core_ui.Rect, icon: []const u8, color: editor_draw.Color) !void {
    if (!editor_draw.SDL_SetRenderDrawColor(ctx.renderer, color.r, color.g, color.b, color.a)) return error.SdlColorSetFailed;
    const size = @min(rect.w, rect.h) - 9.0;
    const left = rect.x + (rect.w - size) * 0.5;
    const top = rect.y + (rect.h - size) * 0.5;
    const s = size / 24.0;
    if (draw_icons.iconoirSvg(icon)) |svg| {
        try draw_icons.drawIconoirSvg(ctx.renderer, svg, left, top, s, color);
        return;
    }
    const p = struct {
        fn x(origin: f32, scale: f32, value: f32) f32 {
            return origin + value * scale;
        }
        fn y(origin: f32, scale: f32, value: f32) f32 {
            return origin + value * scale;
        }
    };
    const line = struct {
        fn draw(renderer: *editor_draw.SDL_Renderer, ox: f32, oy: f32, scale: f32, x0: f32, y0: f32, x1: f32, y1: f32) !void {
            if (!editor_draw.SDL_RenderLine(renderer, p.x(ox, scale, x0), p.y(oy, scale, y0), p.x(ox, scale, x1), p.y(oy, scale, y1))) return error.SdlLineFailed;
        }
    }.draw;
    const box = struct {
        fn draw(renderer: *editor_draw.SDL_Renderer, ox: f32, oy: f32, scale: f32, x: f32, y: f32, w: f32, h: f32) !void {
            var r = editor_draw.SDL_FRect{ .x = p.x(ox, scale, x), .y = p.y(oy, scale, y), .w = w * scale, .h = h * scale };
            if (!editor_draw.SDL_RenderRect(renderer, &r)) return error.SdlRectFailed;
        }
    }.draw;

    if (std.mem.eql(u8, icon, "undo") or std.mem.eql(u8, icon, "redo")) {
        if (std.mem.eql(u8, icon, "undo")) {
            try line(ctx.renderer, left, top, s, 6, 8, 15, 8);
            try line(ctx.renderer, left, top, s, 6, 8, 9, 5);
            try line(ctx.renderer, left, top, s, 6, 8, 9, 11);
            try line(ctx.renderer, left, top, s, 15, 8, 18, 12);
            try line(ctx.renderer, left, top, s, 18, 12, 15, 16);
            try line(ctx.renderer, left, top, s, 15, 16, 8, 16);
        } else {
            try line(ctx.renderer, left, top, s, 18, 8, 9, 8);
            try line(ctx.renderer, left, top, s, 18, 8, 15, 5);
            try line(ctx.renderer, left, top, s, 18, 8, 15, 11);
            try line(ctx.renderer, left, top, s, 9, 8, 6, 12);
            try line(ctx.renderer, left, top, s, 6, 12, 9, 16);
            try line(ctx.renderer, left, top, s, 9, 16, 16, 16);
        }
    } else if (std.mem.eql(u8, icon, "save")) {
        try box(ctx.renderer, left, top, s, 5, 4, 14, 16);
        try box(ctx.renderer, left, top, s, 8, 4, 8, 5);
        try box(ctx.renderer, left, top, s, 8, 14, 8, 6);
    } else if (std.mem.eql(u8, icon, "play")) {
        try line(ctx.renderer, left, top, s, 8, 5, 18, 12);
        try line(ctx.renderer, left, top, s, 18, 12, 8, 19);
        try line(ctx.renderer, left, top, s, 8, 19, 8, 5);
    } else if (std.mem.eql(u8, icon, "build")) {
        try line(ctx.renderer, left, top, s, 7, 17, 17, 7);
        try line(ctx.renderer, left, top, s, 14, 4, 20, 10);
        try line(ctx.renderer, left, top, s, 5, 19, 9, 15);
    } else if (std.mem.eql(u8, icon, "close") or std.mem.eql(u8, icon, "delete")) {
        try line(ctx.renderer, left, top, s, 7, 7, 17, 17);
        try line(ctx.renderer, left, top, s, 17, 7, 7, 17);
    } else if (std.mem.eql(u8, icon, "select")) {
        try line(ctx.renderer, left, top, s, 6, 5, 16, 12);
        try line(ctx.renderer, left, top, s, 6, 5, 9, 18);
        try line(ctx.renderer, left, top, s, 9, 18, 12, 14);
        try line(ctx.renderer, left, top, s, 12, 14, 16, 20);
    } else if (std.mem.eql(u8, icon, "move")) {
        try line(ctx.renderer, left, top, s, 12, 4, 12, 20);
        try line(ctx.renderer, left, top, s, 4, 12, 20, 12);
        try line(ctx.renderer, left, top, s, 12, 4, 9, 7);
        try line(ctx.renderer, left, top, s, 12, 4, 15, 7);
        try line(ctx.renderer, left, top, s, 20, 12, 17, 9);
        try line(ctx.renderer, left, top, s, 20, 12, 17, 15);
    } else if (std.mem.eql(u8, icon, "rotate")) {
        try line(ctx.renderer, left, top, s, 7, 9, 12, 5);
        try line(ctx.renderer, left, top, s, 12, 5, 17, 9);
        try line(ctx.renderer, left, top, s, 17, 9, 17, 15);
        try line(ctx.renderer, left, top, s, 17, 15, 12, 19);
        try line(ctx.renderer, left, top, s, 7, 15, 7, 9);
        try line(ctx.renderer, left, top, s, 7, 9, 5, 12);
    } else if (std.mem.eql(u8, icon, "scale") or std.mem.eql(u8, icon, "frame")) {
        try box(ctx.renderer, left, top, s, 6, 6, 12, 12);
        try line(ctx.renderer, left, top, s, 14, 6, 18, 6);
        try line(ctx.renderer, left, top, s, 18, 6, 18, 10);
    } else if (std.mem.eql(u8, icon, "duplicate")) {
        try box(ctx.renderer, left, top, s, 8, 8, 10, 10);
        try box(ctx.renderer, left, top, s, 5, 5, 10, 10);
    } else if (std.mem.eql(u8, icon, "grid")) {
        try box(ctx.renderer, left, top, s, 5, 5, 14, 14);
        try line(ctx.renderer, left, top, s, 9.7, 5, 9.7, 19);
        try line(ctx.renderer, left, top, s, 14.3, 5, 14.3, 19);
        try line(ctx.renderer, left, top, s, 5, 9.7, 19, 9.7);
        try line(ctx.renderer, left, top, s, 5, 14.3, 19, 14.3);
    } else if (std.mem.eql(u8, icon, "gizmo") or std.mem.eql(u8, icon, "box") or std.mem.eql(u8, icon, "mesh")) {
        try line(ctx.renderer, left, top, s, 8, 7, 15, 4);
        try line(ctx.renderer, left, top, s, 15, 4, 19, 10);
        try line(ctx.renderer, left, top, s, 19, 10, 12, 14);
        try line(ctx.renderer, left, top, s, 12, 14, 8, 7);
        try line(ctx.renderer, left, top, s, 8, 7, 5, 14);
        try line(ctx.renderer, left, top, s, 5, 14, 12, 20);
        try line(ctx.renderer, left, top, s, 12, 20, 19, 10);
        try line(ctx.renderer, left, top, s, 12, 14, 12, 20);
    } else if (std.mem.eql(u8, icon, "world")) {
        try box(ctx.renderer, left, top, s, 6, 6, 12, 12);
        try line(ctx.renderer, left, top, s, 12, 6, 12, 18);
        try line(ctx.renderer, left, top, s, 6, 12, 18, 12);
    } else if (std.mem.eql(u8, icon, "pivot")) {
        try line(ctx.renderer, left, top, s, 12, 5, 12, 19);
        try line(ctx.renderer, left, top, s, 5, 12, 19, 12);
        try box(ctx.renderer, left, top, s, 10, 10, 4, 4);
    } else if (std.mem.eql(u8, icon, "eye")) {
        try line(ctx.renderer, left, top, s, 4, 12, 8, 8);
        try line(ctx.renderer, left, top, s, 8, 8, 16, 8);
        try line(ctx.renderer, left, top, s, 16, 8, 20, 12);
        try line(ctx.renderer, left, top, s, 20, 12, 16, 16);
        try line(ctx.renderer, left, top, s, 16, 16, 8, 16);
        try line(ctx.renderer, left, top, s, 8, 16, 4, 12);
        try box(ctx.renderer, left, top, s, 10, 10, 4, 4);
    } else if (std.mem.eql(u8, icon, "lock")) {
        try box(ctx.renderer, left, top, s, 7, 10, 10, 8);
        try line(ctx.renderer, left, top, s, 9, 10, 9, 7);
        try line(ctx.renderer, left, top, s, 9, 7, 15, 7);
        try line(ctx.renderer, left, top, s, 15, 7, 15, 10);
    } else if (std.mem.eql(u8, icon, "scene") or std.mem.eql(u8, icon, "assets")) {
        try line(ctx.renderer, left, top, s, 6, 7, 18, 7);
        try line(ctx.renderer, left, top, s, 6, 12, 18, 12);
        try line(ctx.renderer, left, top, s, 6, 17, 18, 17);
    } else if (std.mem.eql(u8, icon, "add")) {
        try line(ctx.renderer, left, top, s, 12, 6, 12, 18);
        try line(ctx.renderer, left, top, s, 6, 12, 18, 12);
    } else if (std.mem.eql(u8, icon, "search")) {
        try box(ctx.renderer, left, top, s, 6, 6, 8, 8);
        try line(ctx.renderer, left, top, s, 13, 13, 18, 18);
    } else if (std.mem.eql(u8, icon, "material")) {
        try box(ctx.renderer, left, top, s, 5, 5, 14, 14);
        try line(ctx.renderer, left, top, s, 5, 19, 19, 5);
    } else if (std.mem.eql(u8, icon, "physics")) {
        try line(ctx.renderer, left, top, s, 6, 18, 18, 6);
        try line(ctx.renderer, left, top, s, 9, 18, 6, 15);
        try line(ctx.renderer, left, top, s, 15, 6, 18, 9);
    } else {
        return error.UnknownEditorIcon;
    }
}

fn drawExpandableRow(ctx: DrawContext, rect: core_ui.Rect, text: []const u8, open: bool, hovered: bool, active: bool) !void {
    try fillPanel(ctx, rect, buttonColor(ctx.style, hovered, active, false), ctx.style.separator_color);
    const icon_rect = core_ui.Rect{ .x = rect.x + 2, .y = rect.y, .w = 20, .h = rect.h };
    try drawIcon(ctx, icon_rect, if (open) "chevron-down" else "chevron-right", ctx.style.text_color);
    const text_rect = core_ui.Rect{ .x = rect.x + 22, .y = rect.y, .w = rect.w - 22, .h = rect.h };
    try drawTextTopAlignedWithPad(ctx, text_rect, text, core_ui.text_layout.pad_x, ctx.style.text_color, null);
}

fn textAfterBox(rect: core_ui.Rect, box: core_ui.Rect) core_ui.Rect {
    const gap = core_ui.text_layout.pad_x;
    return .{ .x = box.x + box.w + gap, .y = rect.y, .w = @max(0, rect.w - box.w - gap - core_ui.text_layout.pad_x), .h = rect.h };
}

fn toSdlRect(rect: core_ui.Rect) editor_draw.SDL_FRect {
    return .{ .x = rect.x, .y = rect.y, .w = rect.w, .h = rect.h };
}

fn textColor(style: Style, muted: bool) editor_draw.Color {
    return if (muted) style.muted_text_color else style.text_color;
}

fn buttonColor(style: Style, hovered: bool, active: bool, toggled: bool) editor_draw.Color {
    if (toggled) return style.toggle_on_color;
    if (active) return style.button_active_color;
    if (hovered) return style.button_hovered_color;
    return style.button_color;
}

fn badgeColor(style: Style, variant: core_ui.BadgeVariant) editor_draw.Color {
    return switch (variant) {
        .neutral => style.button_color,
        .accent => style.accent_color,
        .err => style.error_color,
        .warning => style.warning_color,
    };
}

fn alertColor(style: Style, variant: core_ui.commands.InlineAlertVariant) editor_draw.Color {
    return switch (variant) {
        .info => style.info_color,
        .warning => style.warning_color,
        .err => style.error_color,
    };
}

test "button color follows interaction state" {
    const style = Style{};
    try std.testing.expectEqual(style.button_hovered_color, buttonColor(style, true, false, false));
    try std.testing.expectEqual(style.button_active_color, buttonColor(style, true, true, false));
}
