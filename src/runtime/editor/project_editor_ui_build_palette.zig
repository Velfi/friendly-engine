const std = @import("std");
const friendly_engine = @import("friendly_engine");
const editor_shortcuts = @import("editor_shortcuts.zig");
const project_editor_command_palette = @import("project_editor_command_palette.zig");
const project_editor_state = @import("project_editor_state.zig");
const ui_widgets = @import("project_editor_ui_widgets.zig");

const core_ui = friendly_engine.modules.core_ui;
const catalog = @import("runtime_shared").editor_command_catalog;
const ProjectEditorState = project_editor_state.ProjectEditorState;

pub fn buildCommandPalette(ui: *core_ui.UiContext, state: *ProjectEditorState, bottom: core_ui.Rect) !void {
    const palette_rect = core_ui.Rect{ .x = bottom.x + 80, .y = bottom.y - 320, .w = 480, .h = 310 };
    try ui.beginPanel(.{ .id = "ed-command-palette", .rect = palette_rect, .row_height = 22, .padding = 8, .spacing = 4 });
    var header_buf: [96]u8 = undefined;
    const header = std.fmt.bufPrint(&header_buf, "Commands  {s}", .{editor_shortcuts.commandPaletteShortcutLabel()}) catch "Commands";
    try ui.label(header);
    const filter = if (state.command_palette_filter_len > 0)
        state.command_palette_filter[0..state.command_palette_filter_len]
    else
        "";
    const ghost = project_editor_command_palette.ghostSuffix(state);
    var prompt_buf: [96]u8 = undefined;
    const prompt = std.fmt.bufPrint(&prompt_buf, "> {s}", .{filter}) catch "> ";
    const prompt_x: f32 = palette_rect.x + 12;
    const prompt_y: f32 = palette_rect.y + 28;
    try ui_widgets.text(ui, "ed-cmd-prompt", .{ .x = prompt_x, .y = prompt_y, .w = palette_rect.w - 24, .h = 18 }, prompt, false);
    if (ghost.len > 0) {
        const ghost_x = prompt_x + 14.0 + @as(f32, @floatFromInt(filter.len)) * 7.0;
        try ui_widgets.text(ui, "ed-cmd-ghost", .{ .x = ghost_x, .y = prompt_y, .w = palette_rect.w - 24, .h = 18 }, ghost, true);
    }
    try ui_widgets.text(ui, "ed-cmd-hint", .{ .x = prompt_x, .y = prompt_y + 18, .w = palette_rect.w - 24, .h = 16 }, "↑↓ navigate · Enter run · Tab complete", true);

    var matches: [project_editor_command_palette.max_matches]project_editor_command_palette.Match = undefined;
    const match_count = project_editor_command_palette.rankMatches(state, &matches);
    if (match_count > 0 and state.command_palette_highlight >= match_count) {
        state.command_palette_highlight = match_count - 1;
    }

    const scroll_h: f32 = palette_rect.h - 72;
    try core_ui.layout.beginScrollArea(ui, .{ .id = "ed-cmd-scroll", .height = scroll_h });
    const visible = @min(match_count, project_editor_command_palette.visible_matches);
    if (visible == 0) {
        try ui.label("No matching commands");
    } else {
        for (matches[0..visible], 0..) |match, index| {
            var row_buf: [256]u8 = undefined;
            const source = catalog.sourceForEntry(match.entry);
            const row_label = if (match.unavailable_suffix.len > 0)
                std.fmt.bufPrint(&row_buf, "{s}  ·  {s}  ·  {s}{s}", .{ match.entry.label, match.entry.section, source, match.unavailable_suffix }) catch match.entry.label
            else
                std.fmt.bufPrint(&row_buf, "{s}  ·  {s}  ·  {s}", .{ match.entry.label, match.entry.section, source }) catch match.entry.label;
            const selected = index == state.command_palette_highlight;
            if ((try ui_widgets.row(ui, match.entry.id, row_label, selected)).clicked) {
                project_editor_command_palette.execute(state, match.entry);
                project_editor_command_palette.close(state);
            }
        }
    }
    try core_ui.layout.endScrollArea(ui);
    ui.endPanel();
}
