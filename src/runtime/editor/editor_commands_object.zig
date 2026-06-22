const std = @import("std");
const shared = @import("runtime_shared");
const editor_command_file = @import("editor_command_file.zig");
const editor_scene_hierarchy = @import("editor_scene_hierarchy.zig");
const project_editor_edit = @import("project_editor_edit.zig");
const project_editor_state = @import("project_editor_state.zig");

const editor_math = shared.editor_math;
const CommandFile = editor_command_file.CommandFile;
const ProjectEditorState = project_editor_state.ProjectEditorState;
const SceneObject = project_editor_state.SceneObject;

pub fn setParent(allocator: std.mem.Allocator, command: CommandFile, state: *ProjectEditorState) ![]u8 {
    const child_idx = try findIndex(state, command.object orelse return error.MissingObject);
    if (!state.objects.items[child_idx].canModifyObject()) return error.ObjectImmutable;
    const parent_idx = try findIndex(state, command.parent orelse return error.MissingParent);
    const child_id = state.objects.items[child_idx].id;
    const parent_id = state.objects.items[parent_idx].id;
    if (!editor_scene_hierarchy.canSetParent(state.objects.items, child_id, parent_id)) return error.InvalidParent;
    const child_world = editor_scene_hierarchy.objectWorldPosition(state.objects.items, child_idx);
    const parent_world = editor_scene_hierarchy.objectWorldPosition(state.objects.items, parent_idx);

    project_editor_edit.pushUndoSnapshot(state);
    state.objects.items[child_idx].parent_id = parent_id;
    state.objects.items[child_idx].position = editor_math.Vec3.sub(child_world, parent_world);
    state.selected_object = child_idx;
    state.selected_vertex = null;
    state.selected_edge = null;
    state.selected_face = null;
    state.scene_dirty = true;
    project_editor_state.setStatus(state, "Object parent set");

    return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"object\":\"{s}\",\"object_id\":{d},\"parent\":\"{s}\",\"parent_id\":{d},\"status\":\"Object parent set\"}}\n", .{
        command.id,
        command.name,
        state.objects.items[child_idx].name,
        child_id,
        state.objects.items[parent_idx].name,
        parent_id,
    });
}

pub fn setProperties(allocator: std.mem.Allocator, command: CommandFile, state: *ProjectEditorState) ![]u8 {
    const idx = try findIndex(state, command.object orelse return error.MissingObject);
    const properties = try buildProperties(state.allocator, command.properties orelse return error.MissingProperties);
    errdefer freeProperties(state.allocator, properties);

    project_editor_edit.pushUndoSnapshot(state);
    freeProperties(state.allocator, state.objects.items[idx].properties);
    state.objects.items[idx].properties = properties;
    state.selected_object = idx;
    state.selected_vertex = null;
    state.selected_edge = null;
    state.selected_face = null;
    state.scene_dirty = true;
    project_editor_state.setStatus(state, "Object properties updated");

    return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"object\":\"{s}\",\"object_id\":{d},\"properties\":{f},\"status\":\"Object properties updated\"}}\n", .{
        command.id,
        command.name,
        state.objects.items[idx].name,
        state.objects.items[idx].id,
        std.json.fmt(command.properties.?, .{}),
    });
}

pub fn setGameplay(allocator: std.mem.Allocator, command: CommandFile, state: *ProjectEditorState) ![]u8 {
    const idx = try findIndex(state, command.object orelse return error.MissingObject);
    if (!state.objects.items[idx].canModifyObject()) return error.ObjectImmutable;
    const tag = try shared.scene_gameplay.parseTag(state.allocator, command.tag orelse return error.MissingGameplayTag);
    errdefer state.allocator.free(tag);

    project_editor_edit.pushUndoSnapshot(state);
    if (state.objects.items[idx].gameplay) |*gameplay| gameplay.deinit(state.allocator);
    state.objects.items[idx].gameplay = .{
        .tag = tag,
        .health = command.health orelse 100.0,
        .score = command.score orelse 0,
        .team = command.team orelse 0,
        .interactable = command.interactable orelse false,
    };
    state.selected_object = idx;
    state.selected_vertex = null;
    state.selected_edge = null;
    state.selected_face = null;
    state.scene_dirty = true;
    project_editor_state.setStatus(state, "Object gameplay updated");

    return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"object\":\"{s}\",\"object_id\":{d},\"tag\":\"{s}\",\"interactable\":{s},\"status\":\"Object gameplay updated\"}}\n", .{
        command.id,
        command.name,
        state.objects.items[idx].name,
        state.objects.items[idx].id,
        tag,
        if (state.objects.items[idx].gameplay.?.interactable) "true" else "false",
    });
}

pub fn buildProperties(allocator: std.mem.Allocator, properties: std.json.Value) ![]shared.scene_document.Property {
    const object = switch (properties) {
        .object => |object| object,
        else => return error.InvalidProperties,
    };
    if (object.count() == 0) return error.InvalidProperties;
    const out = try allocator.alloc(shared.scene_document.Property, object.count());
    var initialized: usize = 0;
    errdefer {
        for (out[0..initialized]) |*property| property.deinit(allocator);
        allocator.free(out);
    }
    var it = object.iterator();
    while (it.next()) |entry| {
        const key = entry.key_ptr.*;
        try validatePropertyKey(key);
        const value_text = try propertyValueText(allocator, entry.value_ptr.*);
        try validatePropertyValue(value_text);
        out[initialized] = .{
            .key = try allocator.dupe(u8, key),
            .value = value_text,
        };
        initialized += 1;
    }
    return out;
}

pub fn freeProperties(allocator: std.mem.Allocator, properties: []shared.scene_document.Property) void {
    for (properties) |*property| property.deinit(allocator);
    allocator.free(properties);
}

pub fn nameExists(state: *const ProjectEditorState, name: []const u8) bool {
    for (state.objects.items) |obj| {
        if (std.mem.eql(u8, obj.name, name)) return true;
    }
    return false;
}

pub fn hasComponent(obj: *const SceneObject, component_name: []const u8) bool {
    for (obj.components) |component| {
        if (std.mem.eql(u8, component, component_name)) return true;
    }
    return false;
}

pub fn findIndex(state: *const ProjectEditorState, target: []const u8) !usize {
    if (std.fmt.parseUnsigned(u64, target, 10)) |id| {
        for (state.objects.items, 0..) |obj, idx| {
            if (obj.id == id) return idx;
        }
    } else |_| {}
    for (state.objects.items, 0..) |obj, idx| {
        if (std.mem.eql(u8, obj.name, target)) return idx;
    }
    return error.ObjectNotFound;
}

fn validatePropertyKey(key: []const u8) !void {
    if (key.len == 0) return error.InvalidPropertyKey;
    for (key) |ch| {
        const ok = (ch >= 'a' and ch <= 'z') or
            (ch >= 'A' and ch <= 'Z') or
            (ch >= '0' and ch <= '9') or
            ch == '_' or ch == '-' or ch == '.';
        if (!ok) return error.InvalidPropertyKey;
    }
}

fn validatePropertyValue(value: []const u8) !void {
    const trimmed = std.mem.trim(u8, value, " \t\r\n");
    if (trimmed.len == 0) return error.InvalidPropertyValue;
    if (std.mem.indexOfAny(u8, value, ",\r\n") != null) return error.InvalidPropertyValue;
}

fn propertyValueText(allocator: std.mem.Allocator, value: std.json.Value) ![]u8 {
    return switch (value) {
        .string => |text| allocator.dupe(u8, text),
        .integer => |integer| std.fmt.allocPrint(allocator, "{d}", .{integer}),
        .float => |float| std.fmt.allocPrint(allocator, "{d}", .{float}),
        .number_string => |text| allocator.dupe(u8, text),
        .bool => |flag| allocator.dupe(u8, if (flag) "true" else "false"),
        else => error.InvalidPropertyValue,
    };
}
