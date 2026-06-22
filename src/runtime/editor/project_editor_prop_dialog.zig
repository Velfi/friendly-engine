const std = @import("std");
const editor_draw = @import("editor_draw.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_types = @import("project_editor_types.zig");
const project_editor_prop_asset = @import("project_editor_prop_asset.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const SDL_Window = editor_draw.SDL_Window;
const SDL_DialogFileFilter = editor_draw.SDL_DialogFileFilter;

const glb_filters = [_]SDL_DialogFileFilter{
    .{ .name = "glTF Binary", .pattern = "glb" },
};

pub fn requestImportPropGlbDialog(state: *ProjectEditorState, window: *SDL_Window) void {
    editor_draw.SDL_ShowOpenFileDialog(importGlbDialogCallback, state, window, &glb_filters, glb_filters.len, null, false);
}

pub fn requestExportPropGlbDialog(state: *ProjectEditorState, window: *SDL_Window) void {
    editor_draw.SDL_ShowSaveFileDialog(exportGlbDialogCallback, state, window, &glb_filters, glb_filters.len, null);
}

fn importGlbDialogCallback(userdata: ?*anyopaque, filelist: ?[*]const ?[*:0]const u8, filter: c_int) callconv(.c) void {
    _ = filter;
    const state = @as(*ProjectEditorState, @ptrCast(@alignCast(userdata.?)));
    if (filelist == null or filelist.?[0] == null) return;
    project_editor_state.queuePropDialogPath(state, std.mem.span(filelist.?[0].?), .import_prop_glb);
}

fn exportGlbDialogCallback(userdata: ?*anyopaque, filelist: ?[*]const ?[*:0]const u8, filter: c_int) callconv(.c) void {
    _ = filter;
    const state = @as(*ProjectEditorState, @ptrCast(@alignCast(userdata.?)));
    if (filelist == null or filelist.?[0] == null) return;
    project_editor_state.queuePropDialogPath(state, std.mem.span(filelist.?[0].?), .export_prop_glb);
}

/// Drains a path picked from a native OS file dialog (queued from the
/// dialog's own callback thread via queuePropDialogPath) and performs the
/// actual import/export. Call once per frame from the main loop.
pub fn processPendingPropDialog(state: *ProjectEditorState) void {
    const len = state.pending_prop_dialog_path_len.swap(0, .acquire);
    if (len == 0) return;
    const kind_val = state.pending_prop_dialog_kind_atomic.swap(0, .acquire);
    const kind: project_editor_types.PendingPropDialogKind = @enumFromInt(kind_val);
    const path = state.pending_prop_dialog_path_buf[0..len];
    switch (kind) {
        .none => {},
        .import_prop_glb => project_editor_prop_asset.importGlbIntoSelected(state, path) catch {
            project_editor_state.setStatus(state, "GLB import failed");
        },
        .export_prop_glb => project_editor_prop_asset.exportSelectedToGlb(state, path) catch {
            project_editor_state.setStatus(state, "GLB export failed");
        },
    }
}
