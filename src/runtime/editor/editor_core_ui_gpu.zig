const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const editor_draw = @import("editor_draw.zig");
const editor_icon_atlas = @import("editor_icon_atlas.zig");
const editor_sdf_atlas = @import("editor_sdf_atlas.zig");

const core_ui = friendly_engine.modules.core_ui;
const OverlayQuad = shared.gpu_api.OverlayQuad;
const GpuTexture = shared.sdl_gpu.SDL_GPUTexture;
const Style = shared.core_ui_overlay.Style;

pub const Renderer = struct {
    allocator: std.mem.Allocator,
    icon_atlas: editor_icon_atlas.IconAtlas,
    sdf_atlas: ?editor_sdf_atlas.RuntimeAtlas = null,
    text_texture: ?*GpuTexture = null,
    icon_texture: ?*GpuTexture = null,

    pub fn init(allocator: std.mem.Allocator) !Renderer {
        return .{
            .allocator = allocator,
            .icon_atlas = try editor_icon_atlas.IconAtlas.init(allocator),
        };
    }

    pub fn deinit(self: *Renderer, gpu: ?*shared.gpu_api.GpuRenderer) void {
        if (gpu) |renderer| {
            if (self.text_texture) |texture| renderer.releaseOverlayTexture(texture);
            if (self.icon_texture) |texture| renderer.releaseOverlayTexture(texture);
        }
        self.icon_atlas.deinit();
        self.text_texture = null;
        self.icon_texture = null;
    }

    pub fn setSdfAtlas(self: *Renderer, atlas: editor_sdf_atlas.RuntimeAtlas) void {
        self.sdf_atlas = atlas;
    }

    pub fn clearSdfAtlas(self: *Renderer) void {
        self.sdf_atlas = null;
    }

    pub fn draw(self: *Renderer, gpu: *shared.gpu_api.GpuRenderer, text_renderer: *editor_draw.TextRenderer, commands: []const core_ui.RenderCommand, style: Style, scale: f32) !void {
        try self.ensureTextTexture(gpu, text_renderer);
        try self.ensureIconTexture(gpu);

        var quads: std.ArrayList(OverlayQuad) = .empty;
        defer quads.deinit(self.allocator);

        var clips: [8]core_ui.Rect = undefined;
        var scroll_areas: [8]core_ui.commands.ScrollAreaCommand = undefined;
        var clip_depth: usize = 0;
        for (commands) |command| {
            switch (command) {
                .scroll_area => |area| {
                    try appendPanel(&quads, self.allocator, area.rect, style.input_bg_color, style.separator_color, null);
                    if (clip_depth < clips.len) {
                        clips[clip_depth] = if (clip_depth > 0)
                            clips[clip_depth - 1].intersect(area.clip_rect) orelse zeroRect()
                        else
                            area.clip_rect;
                        scroll_areas[clip_depth] = area;
                        clip_depth += 1;
                    }
                },
                .scroll_area_end => if (clip_depth > 0) {
                    clip_depth -= 1;
                    try appendScrollbar(&quads, self.allocator, scroll_areas[clip_depth], style);
                },
                .tooltip => {},
                else => try self.appendCommand(text_renderer, &quads, command, style, if (clip_depth > 0) clips[clip_depth - 1] else null),
            }
        }

        for (commands) |command| {
            if (command != .tooltip) continue;
            const tip = command.tooltip;
            const measured = if (tip.spans.len > 0) try text_renderer.measureRichText(tip.spans) else try text_renderer.measureText(tip.text);
            const tip_rect = core_ui.Rect{
                .x = tip.rect.x,
                .y = tip.rect.y,
                .w = measured + core_ui.text_layout.pad_x + core_ui.text_layout.pad_right,
                .h = tip.rect.h,
            };
            try appendPanel(&quads, self.allocator, tip_rect, style.tooltip_bg_color, style.separator_color, null);
            try self.appendCommandTextTopAlignedWithPad(text_renderer, &quads, tip_rect, tip.text, tip.spans, core_ui.text_layout.pad_x, style.text_color, null);
        }

        if (text_renderer.atlasDirty()) try self.updateTextTexture(gpu, text_renderer);
        if (self.icon_atlas.dirty) try self.updateIconTexture(gpu);
        scaleOverlayQuads(quads.items, scale);
        try gpu.drawOverlayQuads(quads.items);
    }

    fn appendCommand(self: *Renderer, text_renderer: *editor_draw.TextRenderer, quads: *std.ArrayList(OverlayQuad), command: core_ui.RenderCommand, style: Style, clip: ?core_ui.Rect) !void {
        switch (command) {
            .panel => |panel| try appendPanel(quads, self.allocator, panel.rect, style.panel_color, style.separator_color, clip),
            .label, .text => |text| try self.appendCommandTextTopAligned(text_renderer, quads, text.rect, text.text, text.spans, coreTextColor(style, text.muted), clip),
            .status_label => |text| try self.appendCommandTextTopAligned(text_renderer, quads, text.rect, text.text, text.spans, style.muted_text_color, clip),
            .button => |button| {
                const fill = if (button.disabled) style.button_disabled_color else buttonColor(style, button.hovered, button.active, false);
                const label = if (button.disabled) style.muted_text_color else style.text_color;
                try appendPanel(quads, self.allocator, button.rect, fill, style.separator_color, clip);
                try self.appendTextCentered(text_renderer, quads, button.rect, button.text, label, clip);
            },
            .icon_button => |button| {
                try appendPanel(quads, self.allocator, button.rect, buttonColor(style, button.hovered, button.active, button.toggled), style.separator_color, clip);
                try self.appendIcon(quads, button.rect, button.icon, style.text_color, clip);
            },
            .toggle => |toggle| {
                const fill = if (toggle.value) style.toggle_on_color else buttonColor(style, toggle.hovered, toggle.active, false);
                try appendPanel(quads, self.allocator, toggle.rect, fill, style.separator_color, clip);
                try self.appendTextCentered(text_renderer, quads, toggle.rect, toggle.text, style.text_color, clip);
            },
            .toggle_group_item => |item| {
                const fill = if (item.selected) style.selected_color else buttonColor(style, item.hovered, item.active, false);
                try appendPanel(quads, self.allocator, item.rect, fill, style.separator_color, clip);
                try self.appendTextCentered(text_renderer, quads, item.rect, item.text, style.text_color, clip);
            },
            .separator => |sep| try appendRect(quads, self.allocator, sep.rect, style.separator_color, clip),
            .spacer => {},
            .text_input => |field| {
                const fill = if (field.focused) style.input_focus_color else style.input_bg_color;
                try appendPanel(quads, self.allocator, field.rect, fill, style.separator_color, clip);
                try self.appendTextCentered(text_renderer, quads, field.rect, field.text, style.text_color, clip);
                if (field.focused) try appendRect(quads, self.allocator, .{ .x = field.rect.x, .y = field.rect.y, .w = 2, .h = field.rect.h }, style.accent_color, clip);
            },
            .number_input => |field| {
                const fill = if (field.focused or field.dragging) style.input_focus_color else style.input_bg_color;
                try appendPanel(quads, self.allocator, field.rect, fill, style.separator_color, clip);
                try self.appendTextCentered(text_renderer, quads, field.rect, field.text, style.text_color, clip);
            },
            .slider => |slider| {
                try appendRect(quads, self.allocator, slider.track_rect, style.input_bg_color, clip);
                try appendRect(quads, self.allocator, slider.fill_rect, style.progress_fill_color, clip);
            },
            .checkbox => |box| {
                try appendPanel(quads, self.allocator, box.box_rect, style.input_bg_color, style.separator_color, clip);
                if (box.checked) try appendRect(quads, self.allocator, box.box_rect.inset(3.0), style.checkbox_check_color, clip);
                try self.appendTextTopAligned(text_renderer, quads, textAfterBox(box.rect, box.box_rect), box.text, style.text_color, clip);
            },
            .select => |select| {
                try appendPanel(quads, self.allocator, select.rect, buttonColor(style, select.hovered, select.active, select.open), style.separator_color, clip);
                try self.appendTextCentered(text_renderer, quads, select.rect, select.text, style.text_color, clip);
            },
            .select_item => |item| {
                const fill = if (item.selected or item.hovered) style.selected_color else style.input_bg_color;
                try appendPanel(quads, self.allocator, item.rect, fill, style.separator_color, clip);
                try self.appendTextCentered(text_renderer, quads, item.rect, item.text, style.text_color, clip);
            },
            .tab => |tab| {
                const fill = if (tab.selected) style.selected_color else buttonColor(style, tab.hovered, tab.active, false);
                try appendPanel(quads, self.allocator, tab.rect, fill, style.separator_color, clip);
                try self.appendTextCentered(text_renderer, quads, tab.rect, tab.text, style.text_color, clip);
            },
            .tree_node => |node| try self.appendExpandableRow(text_renderer, quads, node.rect, node.text, node.open, node.hovered, node.active, style, clip),
            .selectable => |row| {
                if (row.selected or row.hovered) {
                    try appendRect(quads, self.allocator, row.rect, if (row.selected) style.selected_color else style.button_hovered_color, clip);
                }
                try self.appendTextTopAlignedWithPad(text_renderer, quads, row.rect, row.text, row.text_pad_x, style.text_color, clip);
            },
            .asset_preview => |preview| try self.appendAssetPreview(text_renderer, quads, preview, style, clip),
            .scroll_area, .scroll_area_end => {},
            .tooltip => |tip| {
                try appendPanel(quads, self.allocator, tip.rect, style.tooltip_bg_color, style.separator_color, clip);
                try self.appendCommandTextCentered(text_renderer, quads, tip.rect, tip.text, tip.spans, style.text_color, clip);
            },
            .badge => |badge| {
                try appendPanel(quads, self.allocator, badge.rect, badgeColor(style, badge.variant), style.separator_color, clip);
                try self.appendTextCentered(text_renderer, quads, badge.rect, badge.text, style.text_color, clip);
            },
            .collapsing_header => |header| try self.appendExpandableRow(text_renderer, quads, header.rect, header.text, header.open, header.hovered, header.active, style, clip),
            .progress_bar => |bar| {
                try appendPanel(quads, self.allocator, bar.rect, style.input_bg_color, style.separator_color, clip);
                try appendRect(quads, self.allocator, bar.fill_rect, style.progress_fill_color, clip);
            },
            .inline_alert => |alert| {
                try appendPanel(quads, self.allocator, alert.rect, alertColor(style, alert.variant), style.separator_color, clip);
                try self.appendTextTopAligned(text_renderer, quads, alert.rect, alert.text, style.text_color, clip);
            },
            .table_header_cell => |cell| {
                const fill = if (cell.sort_active) style.selected_color else buttonColor(style, cell.hovered, cell.active, false);
                try appendPanel(quads, self.allocator, cell.rect, fill, style.separator_color, clip);
                try self.appendTextCentered(text_renderer, quads, cell.rect, cell.text, style.text_color, clip);
            },
            .table_row => |row| if (row.selected or row.hovered) {
                try appendRect(quads, self.allocator, row.rect, if (row.selected) style.selected_color else style.button_hovered_color, clip);
            },
            .table_cell => |cell| try self.appendTextTopAligned(text_renderer, quads, cell.rect, cell.text, style.text_color, clip),
            .combobox => |box| {
                const fill = if (box.focused) style.input_focus_color else buttonColor(style, box.hovered, box.active, box.open);
                try appendPanel(quads, self.allocator, box.text_rect, fill, style.separator_color, clip);
                try self.appendTextCentered(text_renderer, quads, box.text_rect, box.text, style.text_color, clip);
                try appendPanel(quads, self.allocator, box.arrow_rect, style.button_color, style.separator_color, clip);
                try self.appendIcon(quads, box.arrow_rect, "chevron-down", style.text_color, clip);
            },
            .combobox_item => |item| {
                const fill = if (item.selected) style.selected_color else if (item.highlighted or item.hovered) style.button_hovered_color else style.input_bg_color;
                try appendPanel(quads, self.allocator, item.rect, fill, style.separator_color, clip);
                try self.appendTextCentered(text_renderer, quads, item.rect, item.text, style.text_color, clip);
            },
            .split_pane => |pane| try appendRect(quads, self.allocator, pane.handle_rect, if (pane.dragging or pane.hovered) style.accent_color else style.separator_color, clip),
            .spinner => |spinner| if (spinner.label_rect) |label_rect| {
                if (spinner.label) |label| try self.appendTextTopAligned(text_renderer, quads, label_rect, label, style.muted_text_color, clip);
            },
        }
    }

    fn appendAssetPreview(
        self: *Renderer,
        text_renderer: *editor_draw.TextRenderer,
        quads: *std.ArrayList(OverlayQuad),
        preview: core_ui.commands.AssetPreviewCommand,
        style: Style,
        clip: ?core_ui.Rect,
    ) !void {
        const fill = if (preview.selected)
            style.selected_color
        else if (preview.hovered)
            style.button_hovered_color
        else
            style.input_bg_color;
        try appendPanel(quads, self.allocator, preview.rect, fill, style.separator_color, clip);
        try appendPanel(quads, self.allocator, preview.thumbnail_rect, .{ .r = 16, .g = 20, .b = 28, .a = 255 }, style.separator_color, clip);
        try appendPreviewShape(quads, self.allocator, preview, clip);
        const label_rect = core_ui.Rect{ .x = preview.text_rect.x, .y = preview.text_rect.y, .w = preview.text_rect.w, .h = 22 };
        try self.appendTextTopAligned(text_renderer, quads, label_rect, preview.label, style.text_color, clip);
        if (preview.detail.len > 0) {
            const detail_rect = core_ui.Rect{ .x = preview.text_rect.x, .y = preview.text_rect.y + 22, .w = preview.text_rect.w, .h = 18 };
            try self.appendTextTopAligned(text_renderer, quads, detail_rect, preview.detail, style.muted_text_color, clip);
        }
    }

    fn ensureTextTexture(self: *Renderer, gpu: *shared.gpu_api.GpuRenderer, text_renderer: *editor_draw.TextRenderer) !void {
        if (self.text_texture == null) {
            const mask_pixels = try alphaCoveragePixels(self.allocator, text_renderer.atlas.pixels);
            defer self.allocator.free(mask_pixels);
            self.text_texture = try gpu.createOverlayTextureFromRgba(mask_pixels, text_renderer.atlas.width, text_renderer.atlas.height);
            text_renderer.markAtlasClean();
        }
    }

    fn updateTextTexture(self: *Renderer, gpu: *shared.gpu_api.GpuRenderer, text_renderer: *editor_draw.TextRenderer) !void {
        const texture = self.text_texture orelse return error.GpuUiTextTextureMissing;
        const mask_pixels = try alphaCoveragePixels(self.allocator, text_renderer.atlas.pixels);
        defer self.allocator.free(mask_pixels);
        try gpu.updateOverlayTextureFromRgba(texture, mask_pixels, text_renderer.atlas.width, text_renderer.atlas.height);
        text_renderer.markAtlasClean();
    }

    fn ensureIconTexture(self: *Renderer, gpu: *shared.gpu_api.GpuRenderer) !void {
        if (self.icon_texture == null) {
            const mask_pixels = try alphaCoveragePixels(self.allocator, self.icon_atlas.pixels);
            defer self.allocator.free(mask_pixels);
            self.icon_texture = try gpu.createOverlayTextureFromRgba(mask_pixels, self.icon_atlas.width, self.icon_atlas.height);
            self.icon_atlas.markClean();
        }
    }

    fn updateIconTexture(self: *Renderer, gpu: *shared.gpu_api.GpuRenderer) !void {
        const texture = self.icon_texture orelse return error.GpuUiIconTextureMissing;
        const mask_pixels = try alphaCoveragePixels(self.allocator, self.icon_atlas.pixels);
        defer self.allocator.free(mask_pixels);
        try gpu.updateOverlayTextureFromRgba(texture, mask_pixels, self.icon_atlas.width, self.icon_atlas.height);
        self.icon_atlas.markClean();
    }

    fn appendTextTopAligned(self: *Renderer, text_renderer: *editor_draw.TextRenderer, quads: *std.ArrayList(OverlayQuad), rect: core_ui.Rect, text: []const u8, color: shared.color.Color, clip: ?core_ui.Rect) !void {
        try self.appendTextTopAlignedWithPad(text_renderer, quads, rect, text, core_ui.text_layout.pad_x, color, clip);
    }

    fn appendTextTopAlignedWithPad(self: *Renderer, text_renderer: *editor_draw.TextRenderer, quads: *std.ArrayList(OverlayQuad), rect: core_ui.Rect, text: []const u8, pad_x: f32, color: shared.color.Color, clip: ?core_ui.Rect) !void {
        try self.appendCommandTextTopAlignedWithPad(text_renderer, quads, rect, text, &.{}, pad_x, color, clip);
    }

    fn appendTextCentered(self: *Renderer, text_renderer: *editor_draw.TextRenderer, quads: *std.ArrayList(OverlayQuad), rect: core_ui.Rect, text: []const u8, color: shared.color.Color, clip: ?core_ui.Rect) !void {
        try self.appendCommandTextCentered(text_renderer, quads, rect, text, &.{}, color, clip);
    }

    fn appendCommandTextTopAligned(self: *Renderer, text_renderer: *editor_draw.TextRenderer, quads: *std.ArrayList(OverlayQuad), rect: core_ui.Rect, text: []const u8, spans: core_ui.rich_text.RichText, color: shared.color.Color, clip: ?core_ui.Rect) !void {
        try self.appendCommandTextTopAlignedWithPad(text_renderer, quads, rect, text, spans, core_ui.text_layout.pad_x, color, clip);
    }

    fn appendCommandTextTopAlignedWithPad(self: *Renderer, text_renderer: *editor_draw.TextRenderer, quads: *std.ArrayList(OverlayQuad), rect: core_ui.Rect, text: []const u8, spans: core_ui.rich_text.RichText, pad_x: f32, color: shared.color.Color, clip: ?core_ui.Rect) !void {
        const clipped = clipRect(rect, clip) orelse return;
        if (clipped.w <= 0 or clipped.h <= 0) return;
        const max_width = core_ui.text_layout.textWidthForPad(clipped, pad_x);
        const top_y = core_ui.text_layout.editorTextTopAlignedY(clipped);
        if (spans.len > 0) {
            try text_renderer.appendRichOverlayQuads(spans, clipped.x + pad_x, top_y, max_width, color, self.text_texture.?, quads, self.allocator);
        } else {
            try text_renderer.appendOverlayQuads(text, clipped.x + pad_x, top_y, max_width, color, self.text_texture.?, quads, self.allocator);
        }
    }

    fn appendCommandTextCentered(self: *Renderer, text_renderer: *editor_draw.TextRenderer, quads: *std.ArrayList(OverlayQuad), rect: core_ui.Rect, text: []const u8, spans: core_ui.rich_text.RichText, color: shared.color.Color, clip: ?core_ui.Rect) !void {
        const clipped = clipRect(rect, clip) orelse return;
        if (clipped.w <= 0 or clipped.h <= 0) return;
        const max_width = core_ui.text_layout.textWidthForPad(clipped, core_ui.text_layout.pad_x);
        const top_y = core_ui.text_layout.editorTextCenteredY(clipped);
        if (spans.len > 0) {
            try text_renderer.appendRichOverlayQuads(spans, clipped.x + core_ui.text_layout.pad_x, top_y, max_width, color, self.text_texture.?, quads, self.allocator);
        } else {
            try text_renderer.appendOverlayQuads(text, clipped.x + core_ui.text_layout.pad_x, top_y, max_width, color, self.text_texture.?, quads, self.allocator);
        }
    }

    fn appendIcon(self: *Renderer, quads: *std.ArrayList(OverlayQuad), rect: core_ui.Rect, icon: []const u8, color: shared.color.Color, clip: ?core_ui.Rect) !void {
        const clipped = clipRect(rect, clip) orelse return;
        if (clipped.w <= 0 or clipped.h <= 0) return;
        const size = @max(1.0, @min(clipped.w, clipped.h) - 4.0);
        const left = clipped.x + (clipped.w - size) * 0.5;
        const top = clipped.y + (clipped.h - size) * 0.5;
        if (self.sdf_atlas) |atlas| {
            if (try atlas.appendIcon(self.allocator, quads, icon, .{ .x = left, .y = top, .w = size, .h = size }, color)) return;
        }
        const slot = try self.icon_atlas.getOrCreate(icon);
        try quads.append(self.allocator, .{
            .rect = .{ left, top, size, size },
            .uv = .{ slot.u0, slot.v0, slot.u1, slot.v1 },
            .gpu_texture = @ptrCast(self.icon_texture.?),
            .color = color,
        });
    }

    fn appendExpandableRow(self: *Renderer, text_renderer: *editor_draw.TextRenderer, quads: *std.ArrayList(OverlayQuad), rect: core_ui.Rect, text: []const u8, open: bool, hovered: bool, active: bool, style: Style, clip: ?core_ui.Rect) !void {
        const clipped = clipRect(rect, clip) orelse return;
        if (clipped.w <= 0 or clipped.h <= 0) return;
        try appendPanel(quads, self.allocator, clipped, buttonColor(style, hovered, active, false), style.separator_color, null);
        const icon_rect = core_ui.Rect{ .x = clipped.x + 2, .y = clipped.y, .w = 20, .h = clipped.h };
        try self.appendIcon(quads, icon_rect, if (open) "chevron-down" else "chevron-right", style.text_color, null);
        const text_rect = core_ui.Rect{ .x = clipped.x + 22, .y = clipped.y, .w = clipped.w - 22, .h = clipped.h };
        try self.appendTextTopAlignedWithPad(text_renderer, quads, text_rect, text, core_ui.text_layout.pad_x, style.text_color, null);
    }
};

fn appendPanel(quads: *std.ArrayList(OverlayQuad), allocator: std.mem.Allocator, rect: core_ui.Rect, fill: shared.color.Color, border: shared.color.Color, clip: ?core_ui.Rect) !void {
    try appendRect(quads, allocator, rect, fill, clip);
    try appendRect(quads, allocator, .{ .x = rect.x, .y = rect.y, .w = rect.w, .h = 1 }, border, clip);
    try appendRect(quads, allocator, .{ .x = rect.x, .y = rect.y + rect.h - 1, .w = rect.w, .h = 1 }, border, clip);
    try appendRect(quads, allocator, .{ .x = rect.x, .y = rect.y, .w = 1, .h = rect.h }, border, clip);
    try appendRect(quads, allocator, .{ .x = rect.x + rect.w - 1, .y = rect.y, .w = 1, .h = rect.h }, border, clip);
}

fn appendRect(quads: *std.ArrayList(OverlayQuad), allocator: std.mem.Allocator, rect: core_ui.Rect, color: shared.color.Color, clip: ?core_ui.Rect) !void {
    const clipped = clipRect(rect, clip) orelse return;
    if (clipped.w <= 0 or clipped.h <= 0) return;
    try quads.append(allocator, .{ .rect = .{ clipped.x, clipped.y, clipped.w, clipped.h }, .color = color });
}

fn appendScrollbar(quads: *std.ArrayList(OverlayQuad), allocator: std.mem.Allocator, area: core_ui.commands.ScrollAreaCommand, style: Style) !void {
    const thumb = scrollThumbRect(area) orelse return;
    const track = core_ui.Rect{ .x = area.rect.x + area.rect.w - 5.0, .y = area.rect.y + 3.0, .w = 2.0, .h = @max(0.0, area.rect.h - 6.0) };
    try appendRect(quads, allocator, track, style.separator_color, null);
    try appendRect(quads, allocator, thumb, style.muted_text_color, null);
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

fn appendPreviewShape(
    quads: *std.ArrayList(OverlayQuad),
    allocator: std.mem.Allocator,
    preview: core_ui.commands.AssetPreviewCommand,
    clip: ?core_ui.Rect,
) !void {
    const r = preview.thumbnail_rect.inset(8);
    const color = previewColor(preview.fill_color);
    const accent = previewColor(preview.accent_color);
    switch (preview.shape) {
        .box => {
            try appendRect(quads, allocator, .{ .x = r.x + 7, .y = r.y + 9, .w = r.w - 8, .h = r.h - 7 }, color, clip);
            try appendRect(quads, allocator, .{ .x = r.x + 3, .y = r.y + 4, .w = r.w - 8, .h = 8 }, accent, clip);
            try appendRect(quads, allocator, .{ .x = r.x + 3, .y = r.y + 4, .w = 8, .h = r.h - 8 }, shade(color, 0.74), clip);
        },
        .cylinder => {
            try appendRect(quads, allocator, .{ .x = r.x + 7, .y = r.y + 7, .w = r.w - 14, .h = r.h - 8 }, color, clip);
            try appendRect(quads, allocator, .{ .x = r.x + 5, .y = r.y + 4, .w = r.w - 10, .h = 6 }, accent, clip);
            try appendRect(quads, allocator, .{ .x = r.x + 5, .y = r.y + r.h - 8, .w = r.w - 10, .h = 5 }, shade(color, 0.68), clip);
        },
        .plane => {
            try appendRect(quads, allocator, .{ .x = r.x + 3, .y = r.y + r.h * 0.55, .w = r.w - 6, .h = 8 }, color, clip);
            try appendRect(quads, allocator, .{ .x = r.x + 8, .y = r.y + r.h * 0.4, .w = r.w - 16, .h = 5 }, accent, clip);
        },
        .sphere => {
            try appendRect(quads, allocator, .{ .x = r.x + 7, .y = r.y + 7, .w = r.w - 14, .h = r.h - 14 }, color, clip);
            try appendRect(quads, allocator, .{ .x = r.x + 10, .y = r.y + 9, .w = 8, .h = 8 }, accent, clip);
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
                    try appendRect(quads, allocator, .{
                        .x = r.x + @as(f32, @floatFromInt(x)) * (cell_w + gap),
                        .y = r.y + @as(f32, @floatFromInt(y)) * (cell_h + gap),
                        .w = cell_w,
                        .h = cell_h,
                    }, if (filled) color else shade(color, 0.38), clip);
                }
            }
            try appendRect(quads, allocator, .{ .x = r.x + r.w * 0.18, .y = r.y + r.h * 0.18, .w = r.w * 0.64, .h = 2 }, accent, clip);
        },
    }
}

fn previewColor(color: core_ui.commands.PreviewColor) shared.color.Color {
    return .{ .r = color.r, .g = color.g, .b = color.b, .a = color.a };
}

fn shade(color: shared.color.Color, factor: f32) shared.color.Color {
    return .{
        .r = @intFromFloat(@as(f32, @floatFromInt(color.r)) * factor),
        .g = @intFromFloat(@as(f32, @floatFromInt(color.g)) * factor),
        .b = @intFromFloat(@as(f32, @floatFromInt(color.b)) * factor),
        .a = color.a,
    };
}

fn scaleOverlayQuads(quads: []OverlayQuad, scale: f32) void {
    if (scale == 1) return;
    for (quads) |*quad| {
        quad.rect[0] *= scale;
        quad.rect[1] *= scale;
        quad.rect[2] *= scale;
        quad.rect[3] *= scale;
        quad.skew_x *= scale;
    }
}

fn clipRect(rect: core_ui.Rect, clip: ?core_ui.Rect) ?core_ui.Rect {
    if (clip) |active| return active.intersect(rect);
    return rect;
}

fn zeroRect() core_ui.Rect {
    return .{ .x = 0, .y = 0, .w = 0, .h = 0 };
}

fn textAfterBox(rect: core_ui.Rect, box: core_ui.Rect) core_ui.Rect {
    const gap = core_ui.text_layout.pad_x;
    return .{ .x = box.x + box.w + gap, .y = rect.y, .w = @max(0, rect.w - box.w - gap - core_ui.text_layout.pad_x), .h = rect.h };
}

fn coreTextColor(style: Style, muted: bool) shared.color.Color {
    return if (muted) style.muted_text_color else style.text_color;
}

fn buttonColor(style: Style, hovered: bool, active: bool, toggled: bool) shared.color.Color {
    if (toggled) return style.toggle_on_color;
    if (active) return style.button_active_color;
    if (hovered) return style.button_hovered_color;
    return style.button_color;
}

fn badgeColor(style: Style, variant: core_ui.BadgeVariant) shared.color.Color {
    return switch (variant) {
        .neutral => style.button_color,
        .accent => style.accent_color,
        .err => style.error_color,
        .warning => style.warning_color,
    };
}

fn alertColor(style: Style, variant: core_ui.commands.InlineAlertVariant) shared.color.Color {
    return switch (variant) {
        .info => style.info_color,
        .warning => style.warning_color,
        .err => style.error_color,
    };
}

fn alphaCoveragePixels(allocator: std.mem.Allocator, rgba: []const u8) ![]u8 {
    if (rgba.len % 4 != 0) return error.InvalidTextureUploadSize;
    const out = try allocator.alloc(u8, rgba.len);
    var i: usize = 0;
    while (i < rgba.len) : (i += 4) {
        const coverage = rgba[i + 3];
        out[i] = coverage;
        out[i + 1] = coverage;
        out[i + 2] = coverage;
        out[i + 3] = coverage;
    }
    return out;
}

test "alphaCoveragePixels stores coverage in every channel" {
    const source = [_]u8{ 255, 255, 255, 128, 255, 255, 255, 0 };
    const out = try alphaCoveragePixels(std.testing.allocator, &source);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqual(@as(u8, 128), out[0]);
    try std.testing.expectEqual(@as(u8, 128), out[1]);
    try std.testing.expectEqual(@as(u8, 128), out[2]);
    try std.testing.expectEqual(@as(u8, 128), out[3]);
    try std.testing.expectEqual(@as(u8, 0), out[4]);
    try std.testing.expectEqual(@as(u8, 0), out[7]);
}
