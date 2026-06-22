const std = @import("std");
const shared = @import("runtime_shared");
const project_editor_edit = @import("project_editor_edit.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_prop_catalog = @import("project_editor_prop_catalog.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const findCatalogEntry = project_editor_prop_catalog.findCatalogEntry;

pub fn cycleSelectedVariant(state: *ProjectEditorState) void {
    const idx = state.selected_object orelse {
        project_editor_state.setStatus(state, "Select a prop to cycle variants");
        return;
    };
    const obj = &state.objects.items[idx];
    if (!obj.canModifyObject()) {
        project_editor_state.setStatus(state, "Object is immutable");
        return;
    }
    project_editor_edit.pushUndoSnapshot(state);
    const variant_count = if (obj.prop_asset_id) |asset_id| blk: {
        if (findCatalogEntry(asset_id)) |entry| break :blk entry.variant_count;
        break :blk 3;
    } else 3;

    const current = if (obj.variant) |variant| std.fmt.parseInt(u32, variant, 10) catch 0 else 0;
    const next = (current + 1) % @max(1, variant_count);
    if (obj.variant) |old| state.allocator.free(old);
    obj.variant = std.fmt.allocPrint(state.allocator, "{d}", .{next}) catch {
        project_editor_state.setStatus(state, "Variant update failed");
        return;
    };
    state.prop_variant_index = next;
    state.scene_dirty = true;
    project_editor_state.setStatus(state, "Variant cycled");
}

pub fn setTrigger(state: *ProjectEditorState, enabled: bool) void {
    const idx = state.selected_object orelse return;
    const obj = &state.objects.items[idx];
    if (!obj.canModifyObject()) {
        project_editor_state.setStatus(state, "Object is immutable");
        return;
    }
    project_editor_edit.pushUndoSnapshot(state);
    var body = obj.physics orelse shared.scene_physics.Body{};
    body.trigger = enabled;
    obj.physics = body;
    state.scene_dirty = true;
    project_editor_state.setStatus(state, if (enabled) "Trigger collider enabled" else "Trigger collider disabled");
}

pub fn setInteractable(state: *ProjectEditorState, enabled: bool) void {
    const idx = state.selected_object orelse return;
    const obj = &state.objects.items[idx];
    if (!obj.canModifyObject()) {
        project_editor_state.setStatus(state, "Object is immutable");
        return;
    }
    project_editor_edit.pushUndoSnapshot(state);
    if (enabled) {
        if (obj.gameplay == null) {
            const tag = shared.scene_gameplay.Component.defaultTag(state.allocator) catch {
                project_editor_state.setStatus(state, "Gameplay component failed");
                return;
            };
            obj.gameplay = shared.scene_gameplay.Component.duplicate(state.allocator, .{ .tag = tag }) catch {
                state.allocator.free(tag);
                project_editor_state.setStatus(state, "Gameplay component failed");
                return;
            };
        }
        obj.gameplay.?.interactable = true;
    } else if (obj.gameplay) |*gameplay| {
        gameplay.interactable = false;
    }
    state.scene_dirty = true;
    project_editor_state.setStatus(state, if (enabled) "Interactable enabled" else "Interactable disabled");
}

pub fn setGameplayTag(state: *ProjectEditorState, tag_text: []const u8) !void {
    const idx = state.selected_object orelse return;
    if (!state.objects.items[idx].canModifyObject()) {
        project_editor_state.setStatus(state, "Object is immutable");
        return;
    }
    const trimmed = std.mem.trim(u8, tag_text, " \t\r\n");
    const new_tag = try shared.scene_gameplay.parseTag(state.allocator, trimmed);
    errdefer state.allocator.free(new_tag);

    project_editor_edit.pushUndoSnapshot(state);
    const obj = &state.objects.items[idx];
    if (obj.gameplay == null) {
        obj.gameplay = .{ .tag = new_tag };
    } else {
        state.allocator.free(obj.gameplay.?.tag);
        obj.gameplay.?.tag = new_tag;
    }
    state.scene_dirty = true;
    project_editor_state.setStatus(state, "Gameplay tag updated");
}

pub fn setParentId(state: *ProjectEditorState, parent_id: ?u64) void {
    const idx = state.selected_object orelse return;
    if (!state.objects.items[idx].canModifyObject()) {
        project_editor_state.setStatus(state, "Object is immutable");
        return;
    }
    project_editor_edit.pushUndoSnapshot(state);
    state.objects.items[idx].parent_id = parent_id;
    state.scene_dirty = true;
    project_editor_state.setStatus(state, if (parent_id) |id| blk: {
        var buf: [64]u8 = undefined;
        break :blk std.fmt.bufPrint(&buf, "Parent set to {d}", .{id}) catch "Parent updated";
    } else "Parent cleared");
}

pub fn setLayer(state: *ProjectEditorState, layer: []const u8) !void {
    const idx = state.selected_object orelse return;
    const obj = &state.objects.items[idx];
    if (!obj.canModifyObject()) {
        project_editor_state.setStatus(state, "Object is immutable");
        return;
    }
    project_editor_edit.pushUndoSnapshot(state);
    if (obj.layer.len > 0) state.allocator.free(obj.layer);
    const trimmed = std.mem.trim(u8, layer, " \t\r\n");
    if (trimmed.len == 0 or std.mem.eql(u8, trimmed, "Default")) {
        obj.layer = "";
    } else {
        obj.layer = try state.allocator.dupe(u8, trimmed);
    }
    state.scene_dirty = true;
    project_editor_state.setStatus(state, "Layer updated");
}
