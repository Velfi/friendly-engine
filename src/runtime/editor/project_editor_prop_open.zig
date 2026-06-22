const std = @import("std");
const shared = @import("runtime_shared");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_prop_catalog = @import("project_editor_prop_catalog.zig");
const project_editor_prop_recent = @import("project_editor_prop_recent.zig");
const project_editor_prop_asset = @import("project_editor_prop_asset.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;

pub fn openAssetForEditing(state: *ProjectEditorState, asset_id: []const u8) !void {
    if (project_editor_prop_catalog.findCatalogEntry(asset_id)) |entry| {
        try openCatalogAssetForEditing(state, entry);
        return;
    }

    var doc = project_editor_prop_asset.loadAssetDocument(state, asset_id) catch |err| switch (err) {
        error.FileNotFound => {
            project_editor_state.setStatus(state, "Unknown prop asset");
            return;
        },
        else => return err,
    };
    doc.deinit(state.allocator);
    try openProjectAssetForEditing(state, asset_id);
}

fn openCatalogAssetForEditing(
    state: *ProjectEditorState,
    entry: project_editor_prop_catalog.CatalogEntry,
) !void {
    state.prop_selected_asset = entry.id;
    state.prop_workspace_mode = .display;
    state.prop_tool = .select;
    state.shading_mode = .rendered;
    project_editor_prop_recent.invalidatePropPreviewMesh(state);
    try setActivePropAsset(state, entry.id);
    project_editor_prop_asset.clearEditablePropWorkingCopies(state, entry.id);

    if (findObjectForAsset(state, entry.id)) |idx| {
        selectOpenedProp(state, idx);
        try refreshObjectFromAssetDocument(state, idx, entry.id);
        frameOpenedProp(state, idx);
        project_editor_state.setStatus(state, "Opened prop asset instance for editing");
        return;
    }

    var doc = try project_editor_prop_asset.ensureAssetDocument(state, entry.id);
    doc.deinit(state.allocator);
    try project_editor_prop_asset.modifyAssetWorkingCopy(state, entry.id);
    state.prop_workspace_mode = .display;
    state.prop_tool = .select;
    if (state.selected_object) |idx| {
        selectOpenedProp(state, idx);
        frameOpenedProp(state, idx);
    }
    project_editor_state.setStatus(state, "Opened prop asset working copy");
}

fn openProjectAssetForEditing(state: *ProjectEditorState, asset_id: []const u8) !void {
    state.prop_workspace_mode = .display;
    state.prop_tool = .select;
    state.shading_mode = .rendered;
    project_editor_prop_recent.invalidatePropPreviewMesh(state);

    try project_editor_prop_asset.modifyAssetWorkingCopy(state, asset_id);
    state.prop_workspace_mode = .display;
    state.prop_tool = .select;
    if (state.selected_object) |idx| {
        selectOpenedProp(state, idx);
        frameOpenedProp(state, idx);
    }
    project_editor_state.setStatus(state, "Opened project prop asset working copy");
}

pub fn setOpenAssetErrorDetail(
    state: *ProjectEditorState,
    catalog_id: []const u8,
    err: anyerror,
    trace: ?*std.builtin.StackTrace,
) !void {
    var out: std.Io.Writer.Allocating = .init(state.allocator);
    defer out.deinit();
    const writer = &out.writer;
    try writer.writeAll("Open Prop Asset failed\n\nOperation trace:\n");
    try writer.print("- selected asset: {s}\n", .{catalog_id});
    try writer.print("- project path: {s}\n", .{state.project_path});
    try writer.writeAll("- action: open prop asset for editing\n");
    try writer.print("- error: {s}\n", .{@errorName(err)});
    try writer.writeAll("\nZig error return trace:\n");
    if (trace) |error_trace| {
        std.debug.writeErrorReturnTrace(error_trace, .{ .writer = writer, .mode = .no_color }) catch |trace_err| {
            try writer.print("(failed to render error return trace: {s})\n", .{@errorName(trace_err)});
        };
    } else {
        try writer.writeAll("(unavailable in this build)\n");
    }
    const detail = try out.toOwnedSlice();
    defer state.allocator.free(detail);
    try project_editor_state.setEditorErrorDetail(state, "Open Prop Failed", detail);
}

fn refreshObjectFromAssetDocument(state: *ProjectEditorState, idx: usize, catalog_id: []const u8) !void {
    var doc = try project_editor_prop_asset.ensureAssetDocument(state, catalog_id);
    defer doc.deinit(state.allocator);
    var mesh = try project_editor_prop_asset.loadAssetMesh(state, doc);
    errdefer mesh.deinit(state.allocator);
    var obj = &state.objects.items[idx];
    obj.mesh.deinit(state.allocator);
    obj.mesh = mesh;
    obj.primitive_kind = null;
    obj.base_color = doc.base_color;
    state.allocator.free(obj.name);
    obj.name = try std.fmt.allocPrint(state.allocator, "{s} {d}", .{ doc.label, obj.id });
    try project_editor_prop_asset.applyAssetMaterialTexture(state.allocator, obj, catalog_id);
    try project_editor_prop_asset.propagateSelectedAssetGeometryFallible(state);
}

fn setActivePropAsset(state: *ProjectEditorState, catalog_id: []const u8) !void {
    if (state.active_prop_asset_id) |existing| {
        if (std.mem.eql(u8, existing, catalog_id)) return;
        state.allocator.free(existing);
        state.active_prop_asset_id = null;
    }
    state.active_prop_asset_id = try state.allocator.dupe(u8, catalog_id);
}

fn findObjectForAsset(state: *const ProjectEditorState, catalog_id: []const u8) ?usize {
    for (state.objects.items, 0..) |obj, idx| {
        if (!obj.editor_only) continue;
        const asset_id = obj.prop_asset_id orelse continue;
        if (std.mem.eql(u8, asset_id, catalog_id)) return idx;
    }
    return null;
}

fn selectOpenedProp(state: *ProjectEditorState, idx: usize) void {
    state.selected_object = idx;
    state.selected_vertex = null;
    state.selected_edge = null;
    state.selected_face = null;
    state.camera.target = state.objects.items[idx].position;
}

fn frameOpenedProp(state: *ProjectEditorState, idx: usize) void {
    const obj = state.objects.items[idx];
    state.camera.target = .{ .x = obj.position.x, .y = obj.position.y, .z = obj.position.z };
    state.camera.yaw = 0.62;
    state.camera.pitch = 0.24;
    state.camera.distance = 1.65;
    state.show_grid = false;
}
