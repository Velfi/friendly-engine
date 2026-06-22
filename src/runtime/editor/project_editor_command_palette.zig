const std = @import("std");
const shared = @import("runtime_shared");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_command_dispatch = @import("project_editor_command_dispatch.zig");
const command_palette_search = @import("command_palette_search.zig");

const catalog = shared.editor_command_catalog;
const ProjectEditorState = project_editor_state.ProjectEditorState;

pub const Entry = catalog.Entry;
pub const Match = command_palette_search.Match;
pub const max_matches = command_palette_search.max_matches;
pub const visible_matches = command_palette_search.visible_matches;

pub fn rankMatches(state: *const ProjectEditorState, out: []Match) usize {
    return command_palette_search.rankMatches(state, out);
}

pub fn execute(state: *ProjectEditorState, entry: Entry) void {
    project_editor_command_dispatch.execute(state, entry.id);
}

pub fn toggle(state: *ProjectEditorState) void {
    state.command_palette_open = !state.command_palette_open;
    resetFilter(state);
    project_editor_state.setStatus(state, if (state.command_palette_open) "Command palette" else "Command palette closed");
}

pub fn close(state: *ProjectEditorState) void {
    state.command_palette_open = false;
    resetFilter(state);
}

pub fn resetFilter(state: *ProjectEditorState) void {
    state.command_palette_filter_len = 0;
    state.command_palette_highlight = 0;
}

pub fn appendFilterChar(state: *ProjectEditorState, ch: u8) void {
    if (state.command_palette_filter_len >= state.command_palette_filter.len) return;
    state.command_palette_filter[state.command_palette_filter_len] = ch;
    state.command_palette_filter_len += 1;
    state.command_palette_highlight = 0;
}

pub fn popFilterChar(state: *ProjectEditorState) void {
    if (state.command_palette_filter_len == 0) return;
    state.command_palette_filter_len -= 1;
    state.command_palette_highlight = 0;
}

pub fn appendFilterText(state: *ProjectEditorState, text: []const u8) void {
    for (text) |ch| appendFilterChar(state, ch);
}

pub fn moveHighlight(state: *ProjectEditorState, delta: i32) void {
    var matches: [max_matches]Match = undefined;
    const count = rankMatches(state, &matches);
    if (count == 0) {
        state.command_palette_highlight = 0;
        return;
    }
    const count_i: i32 = @intCast(count);
    var next: i32 = @intCast(state.command_palette_highlight);
    next = @mod(next + delta, count_i);
    if (next < 0) next += count_i;
    state.command_palette_highlight = @intCast(next);
}

pub fn executeHighlighted(state: *ProjectEditorState) bool {
    var matches: [max_matches]Match = undefined;
    const count = rankMatches(state, &matches);
    if (count == 0) return false;
    const index = @min(state.command_palette_highlight, count - 1);
    execute(state, matches[index].entry);
    close(state);
    return true;
}

pub fn autocompleteFilter(state: *ProjectEditorState) bool {
    var matches: [max_matches]Match = undefined;
    const count = rankMatches(state, &matches);
    if (count == 0) return false;
    const filter = state.command_palette_filter[0..state.command_palette_filter_len];
    const suffix = command_palette_search.completionSuffix(filter, matches[0..count]);
    if (suffix.len == 0) return false;
    appendFilterText(state, suffix);
    state.command_palette_highlight = 0;
    return true;
}

pub fn ghostSuffix(state: *const ProjectEditorState) []const u8 {
    var matches: [max_matches]Match = undefined;
    const count = rankMatches(state, &matches);
    if (count == 0) return "";
    const filter = state.command_palette_filter[0..state.command_palette_filter_len];
    return command_palette_search.ghostSuffix(filter, matches[0..count]);
}
