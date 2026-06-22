const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const project_editor_state = @import("project_editor_state.zig");

const core_ui = friendly_engine.modules.core_ui;
const catalog = shared.editor_command_catalog;
const ProjectEditorState = project_editor_state.ProjectEditorState;

pub fn describeCommands(ui: *core_ui.UiContext, buf: []u8) ![]const u8 {
    var panels: usize = 0;
    var buttons: usize = 0;
    var copy_nodes: usize = 0;
    var catalog_owned: usize = 0;
    var top_source: []const u8 = "";
    for (ui.renderCommands()) |cmd| {
        switch (cmd) {
            .panel => panels += 1,
            .button => |button| {
                buttons += 1;
                copy_nodes += 1;
                if (catalogEntryForText(button.text)) |entry| {
                    catalog_owned += 1;
                    if (top_source.len == 0) top_source = catalog.sourceForEntry(entry);
                }
            },
            .icon_button => buttons += 1,
            .label => |label| {
                copy_nodes += 1;
                if (catalogEntryForText(label.text)) |entry| {
                    catalog_owned += 1;
                    if (top_source.len == 0) top_source = catalog.sourceForEntry(entry);
                }
            },
            .text => |text| {
                copy_nodes += 1;
                if (catalogEntryForText(text.text)) |entry| {
                    catalog_owned += 1;
                    if (top_source.len == 0) top_source = catalog.sourceForEntry(entry);
                }
            },
            .status_label => |label| {
                copy_nodes += 1;
                if (catalogEntryForText(label.text)) |entry| {
                    catalog_owned += 1;
                    if (top_source.len == 0) top_source = catalog.sourceForEntry(entry);
                }
            },
            else => {},
        }
    }
    const source = if (top_source.len > 0) top_source else "no catalog-owned visible copy";
    return std.fmt.bufPrint(buf, "UI tree: {d} panels, {d} actions, {d}/{d} copy owned · {s}", .{
        panels,
        buttons,
        catalog_owned,
        copy_nodes,
        source,
    });
}

pub fn formatStatus(state: *ProjectEditorState, ui: *core_ui.UiContext, buf: []u8) ![]const u8 {
    _ = state;
    return describeCommands(ui, buf);
}

fn catalogEntryForText(text: []const u8) ?catalog.Entry {
    for (catalog.entries) |entry| {
        if (!catalog.isProjectEditorEntry(entry)) continue;
        if (std.mem.eql(u8, entry.label, text)) return entry;
    }
    return null;
}

test "ui tree summarizes render commands" {
    var ui = core_ui.UiContext.init(std.testing.allocator);
    defer ui.deinit();
    try ui.beginPanel(.{ .id = "test-panel", .rect = .{ .x = 0, .y = 0, .w = 100, .h = 50 } });
    _ = try ui.button("Run");
    ui.endPanel();
    var buf: [256]u8 = undefined;
    const text = try describeCommands(&ui, &buf);
    try std.testing.expect(std.mem.indexOf(u8, text, "panels") != null);
}

test "ui tree reports catalog copy ownership" {
    var ui = core_ui.UiContext.init(std.testing.allocator);
    defer ui.deinit();
    try ui.beginPanel(.{ .id = "test-panel", .rect = .{ .x = 0, .y = 0, .w = 100, .h = 50 } });
    _ = try ui.button("Save");
    ui.endPanel();
    var buf: [256]u8 = undefined;
    const text = try describeCommands(&ui, &buf);
    try std.testing.expect(std.mem.indexOf(u8, text, "1/1 copy owned") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "project_editor_ui_build.zig") != null);
}
