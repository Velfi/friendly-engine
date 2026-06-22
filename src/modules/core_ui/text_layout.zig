const context = @import("context.zig");

pub const pad_x: f32 = 6.0;
pub const pad_right: f32 = 6.0;
pub const pad_y: f32 = 5.0;
pub const editor_font_size: f32 = 18.0;
pub const editor_descent: f32 = 4.0;
/// Average glyph advance for the 18px editor font (legacy code used 7px per char).
pub const editor_char_advance: f32 = 10.5;
pub const overlay_glyph_height: f32 = 8.0;
pub const overlay_char_advance: f32 = 7.0;

pub fn textWidth(rect: context.Rect) f32 {
    return textWidthForPad(rect, pad_x);
}

pub fn textWidthForPad(rect: context.Rect, pad_x_val: f32) f32 {
    return @max(0, rect.w - pad_x_val - pad_right);
}

pub fn editorTextBlockHeight() f32 {
    return editor_font_size + editor_descent;
}

pub fn editorTextTopAlignedY(rect: context.Rect) f32 {
    const block_h = editorTextBlockHeight();
    return @min(rect.y + pad_y, @max(rect.y, rect.y + rect.h - block_h));
}

pub fn editorTextCenteredY(rect: context.Rect) f32 {
    const block_h = editorTextBlockHeight();
    if (rect.h <= block_h) return rect.y;
    return rect.y + (rect.h - block_h) * 0.5;
}

pub fn overlayTextTopAlignedY(rect: context.Rect) f32 {
    return rect.y + 2.0;
}

pub fn overlayTextCenteredY(rect: context.Rect) f32 {
    return rect.y + @max(2.0, (rect.h - overlay_glyph_height) * 0.5);
}

pub fn estimatedTextWidth(text: []const u8, char_advance: f32) f32 {
    return @as(f32, @floatFromInt(text.len)) * char_advance;
}

pub fn editorEstimatedTextWidth(text: []const u8) f32 {
    return estimatedTextWidth(text, editor_char_advance);
}

pub fn tooltipHeight() f32 {
    return pad_y * 2.0 + editorTextBlockHeight();
}

pub fn tooltipWidth(text: []const u8) f32 {
    return @min(320.0, @max(48.0, editorEstimatedTextWidth(text) + pad_x + pad_right));
}

test "editor width estimate exceeds legacy 7px heuristic" {
    const text = "Hide object";
    try @import("std").testing.expect(editorEstimatedTextWidth(text) > @as(f32, @floatFromInt(text.len * 7)));
}

test "centered text fits 24px rows" {
    const rect = context.Rect{ .x = 0, .y = 0, .w = 80, .h = 24 };
    const top = editorTextCenteredY(rect);
    try @import("std").testing.expect(top + editorTextBlockHeight() <= rect.y + rect.h);
}
