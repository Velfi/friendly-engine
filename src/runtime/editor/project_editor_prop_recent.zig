const std = @import("std");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_prop_catalog = @import("project_editor_prop_catalog.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const max_recent_props = project_editor_prop_catalog.max_recent_props;

pub fn invalidatePropPreviewMesh(state: *ProjectEditorState) void {
    if (state.prop_preview_mesh) |*mesh| mesh.deinit(state.allocator);
    state.prop_preview_mesh = null;
    if (state.prop_preview_mesh_id) |id| state.allocator.free(id);
    state.prop_preview_mesh_id = null;
}

pub fn rebuildRecentFromObjects(state: *ProjectEditorState) void {
    for (state.prop_recent_ids.items) |id| state.allocator.free(id);
    state.prop_recent_ids.clearRetainingCapacity();
    var idx = state.objects.items.len;
    while (idx > 0) {
        idx -= 1;
        const asset_id = state.objects.items[idx].prop_asset_id orelse continue;
        recordRecentProp(state, asset_id);
    }
}

pub fn recordRecentProp(state: *ProjectEditorState, catalog_id: []const u8) void {
    for (state.prop_recent_ids.items, 0..) |existing, idx| {
        if (std.mem.eql(u8, existing, catalog_id)) {
            const moved = state.prop_recent_ids.items[idx];
            _ = state.prop_recent_ids.orderedRemove(idx);
            state.prop_recent_ids.insert(state.allocator, 0, moved) catch {
                state.allocator.free(moved);
            };
            return;
        }
    }
    const owned = state.allocator.dupe(u8, catalog_id) catch return;
    state.prop_recent_ids.insert(state.allocator, 0, owned) catch {
        state.allocator.free(owned);
        return;
    };
    while (state.prop_recent_ids.items.len > max_recent_props) {
        const tail = state.prop_recent_ids.pop() orelse break;
        state.allocator.free(tail);
    }
}

test "recordRecentProp moves existing id without dangling it" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = @constCast(""),
        .project_name = @constCast(""),
        .objects = .empty,
    };
    defer {
        for (state.prop_recent_ids.items) |id| state.allocator.free(id);
        state.prop_recent_ids.deinit(state.allocator);
    }

    recordRecentProp(&state, "crate_wood");
    recordRecentProp(&state, "lamp_wall");
    recordRecentProp(&state, "crate_wood");

    try std.testing.expectEqual(@as(usize, 2), state.prop_recent_ids.items.len);
    try std.testing.expectEqualStrings("crate_wood", state.prop_recent_ids.items[0]);
    try std.testing.expectEqualStrings("lamp_wall", state.prop_recent_ids.items[1]);
}
