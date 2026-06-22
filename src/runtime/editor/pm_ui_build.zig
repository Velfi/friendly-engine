const std = @import("std");
const builtin = @import("builtin");
const friendly_engine = @import("friendly_engine");
const menu = @import("menu.zig");
const pm_presets = @import("pm_presets.zig");
const pm_state = @import("pm_state.zig");
const pm_state_projects = @import("pm_state_projects.zig");
const pm_util = @import("pm_util.zig");

const core_ui = friendly_engine.modules.core_ui;

const outer_pad: f32 = 10;
const panel_gap: f32 = 6;
const top_h: f32 = 52;
const bottom_h: f32 = 30;
const details_w: f32 = 276;
const panel_pad: f32 = 8;
const inspector_pad: f32 = 12;
const row_h: f32 = 26;
const row_spacing: f32 = 6;
const project_row_h: f32 = 86;
const project_row_inset: f32 = 8;

const Layout = struct {
    menubar: core_ui.Rect,
    top: core_ui.Rect,
    list: core_ui.Rect,
    details: core_ui.Rect,
    bottom: core_ui.Rect,
};

pub fn build(ui: *core_ui.UiContext, state: *pm_state.ProjectManagerState, window_w: f32, window_h: f32) !void {
    const layout = computeLayout(window_w, window_h);
    try buildWindowMenu(ui, state, layout.menubar);
    try buildTopBar(ui, state, layout.top);
    try buildProjectList(ui, state, layout.list);
    try buildDetails(ui, state, layout.details);
    try buildBottomStrip(ui, state, layout.bottom);
    if (state.mode != .none) try buildModal(ui, state, window_w, window_h);
}

fn computeLayout(window_w: f32, window_h: f32) Layout {
    const show_menu = builtin.os.tag != .macos;
    const menubar_h: f32 = if (show_menu) 30 else 0;
    const menubar_gap: f32 = if (show_menu) panel_gap else 0;
    const layout_top = outer_pad + menubar_h + menubar_gap;
    const content_y = layout_top + top_h + panel_gap;
    const content_h = @max(200, window_h - content_y - bottom_h - panel_gap - outer_pad);
    const list_w = @max(320, window_w - outer_pad * 2 - details_w - panel_gap);
    const bottom_y = content_y + content_h + panel_gap;
    return .{
        .menubar = .{ .x = outer_pad, .y = outer_pad, .w = window_w - outer_pad * 2, .h = menubar_h },
        .top = .{ .x = outer_pad, .y = layout_top, .w = window_w - outer_pad * 2, .h = top_h },
        .list = .{ .x = outer_pad, .y = content_y, .w = list_w, .h = content_h },
        .details = .{ .x = outer_pad + list_w + panel_gap, .y = content_y, .w = details_w, .h = content_h },
        .bottom = .{ .x = outer_pad, .y = bottom_y, .w = window_w - outer_pad * 2, .h = bottom_h },
    };
}

fn buildWindowMenu(ui: *core_ui.UiContext, state: *pm_state.ProjectManagerState, rect: core_ui.Rect) !void {
    if (builtin.os.tag == .macos) return;
    try ui.beginPanel(.{ .id = "pm-menu", .rect = rect, .row_height = row_h, .padding = panel_pad, .spacing = 4 });
    try core_ui.layout.sameLine(ui);
    if ((try button(ui, "pm-menu-file", "File", 52, null, false)).clicked) {
        state.open_window_menu = if (state.open_window_menu == .file) .none else .file;
    }
    if ((try button(ui, "pm-menu-help", "Help", 52, null, false)).clicked) {
        state.open_window_menu = if (state.open_window_menu == .help) .none else .help;
    }
    try core_ui.layout.endSameLine(ui);
    ui.endPanel();
    if (state.open_window_menu != .none) try buildWindowMenuDropdown(ui, state, rect);
}

fn buildWindowMenuDropdown(ui: *core_ui.UiContext, state: *pm_state.ProjectManagerState, menubar: core_ui.Rect) !void {
    const items = menu.windowMenuItems(state.open_window_menu);
    if (items.len == 0) return;
    const x = switch (state.open_window_menu) {
        .none => menubar.x,
        .file => menubar.x + panel_pad,
        .help => menubar.x + 64,
    };
    try ui.beginPanel(.{
        .id = "pm-menu-dropdown",
        .rect = .{ .x = x, .y = menubar.y + menubar.h + 2, .w = 240, .h = @as(f32, @floatFromInt(items.len)) * row_h + panel_pad * 2 },
        .row_height = row_h,
        .padding = 4,
        .spacing = 2,
    });
    for (items) |item| {
        if ((try button(ui, item.label, item.label, 232, null, false)).clicked) {
            try state.dispatchMenuAction(item.action, state.window.?);
            state.open_window_menu = .none;
        }
    }
    ui.endPanel();
}

fn buildTopBar(ui: *core_ui.UiContext, state: *pm_state.ProjectManagerState, rect: core_ui.Rect) !void {
    try ui.beginPanel(.{ .id = "pm-top", .rect = rect, .row_height = row_h, .padding = 7, .spacing = row_spacing });
    try text(ui, "pm-title", .{ .x = rect.x + 12, .y = rect.y + 6, .w = 240, .h = 18 }, "Project Manager", false);
    try text(ui, "pm-subtitle", .{ .x = rect.x + 12, .y = rect.y + 28, .w = 320, .h = 14 }, "Manual project list", true);

    const button_w: f32 = 88;
    const button_gap: f32 = row_spacing;
    const buttons_w = button_w * 4 + button_gap * 3;
    const button_y = rect.y + (rect.h - row_h) * 0.5;
    try rowAt(ui, rect.x + rect.w - 12 - buttons_w, button_y);
    if ((try button(ui, "pm-create", "Create", button_w, null, false)).clicked) state.beginMode(.create, "new_project");
    if ((try button(ui, "pm-presets", "Presets", button_w, null, false)).clicked) {
        state.syncCreatePresetSelection();
        state.loadPresetScratch(state.selected_preset_index);
        state.beginMode(.manage_presets, "");
    }
    if ((try button(ui, "pm-import", "Import", button_w, null, false)).clicked) {
        if (state.window) |window| try state.requestImportFolderDialog(window);
    }
    const open_disabled = state.projects.items.len == 0 or (state.projects.items.len > 0 and selectedProjectIsStale(state));
    if ((try button(ui, "pm-open", "Open", button_w, null, open_disabled)).clicked) try openSelected(state);
    try core_ui.layout.endSameLine(ui);
    ui.endPanel();
}

fn buildProjectList(ui: *core_ui.UiContext, state: *pm_state.ProjectManagerState, rect: core_ui.Rect) !void {
    if (state.projects.items.len > 0 and state.selected_index >= state.projects.items.len) {
        state.selected_index = state.projects.items.len - 1;
    }
    try ui.beginPanel(.{ .id = "pm-list", .rect = rect, .row_height = row_h, .padding = panel_pad, .spacing = row_spacing });
    try ui.label("Projects");
    try core_ui.layout.sameLine(ui);
    if ((try button(ui, "pm-filter-all", "All", 52, state.list_filter == .all, false)).clicked) state.list_filter = .all;
    if ((try button(ui, "pm-filter-recent", "Recent", 72, state.list_filter == .recent, false)).clicked) state.list_filter = .recent;
    const cursor = try ui.currentLayout();
    const count_label = try countText(ui, state.filteredProjectCount());
    const count_w: f32 = 96;
    try text(ui, "pm-count", .{
        .x = cursor.content_x + cursor.content_w - count_w,
        .y = cursor.same_line_y,
        .w = count_w,
        .h = row_h,
    }, count_label, true);
    try core_ui.layout.endSameLine(ui);
    try core_ui.layout.spacer(ui, 2);

    const visible_count = state.filteredProjectCount();
    var display_idx: usize = 0;
    while (display_idx < visible_count) : (display_idx += 1) {
        const project_idx = state.filteredProjectIndex(display_idx) orelse break;
        const entry = state.projects.items[project_idx];
        const row = try projectRow(ui, state, project_idx, entry.path, entry.name);
        if (row.clicked) {
            state.selected_index = project_idx;
            if (ui.input.primary_click_count >= 2) {
                try openSelected(state);
                ui.endPanel();
                return;
            } else {
                try state.saveConfig();
            }
        }
        try text(ui, entry.path, .{
            .x = row.rect.x + project_row_inset,
            .y = row.rect.y + 22,
            .w = row.rect.w - project_row_inset * 2,
            .h = 16,
        }, entry.path, true);
        try text(ui, entry.tags, .{
            .x = row.rect.x + project_row_inset,
            .y = row.rect.y + 42,
            .w = row.rect.w - project_row_inset * 2,
            .h = 16,
        }, entry.tags, false);
        try text(ui, entry.status, .{
            .x = row.rect.x + project_row_inset,
            .y = row.rect.y + 62,
            .w = row.rect.w - project_row_inset * 2,
            .h = 16,
        }, entry.status, true);
    }
    ui.endPanel();
}

fn buildDetails(ui: *core_ui.UiContext, state: *pm_state.ProjectManagerState, rect: core_ui.Rect) !void {
    try ui.beginPanel(.{ .id = "pm-details", .rect = rect, .row_height = row_h, .padding = inspector_pad, .spacing = row_spacing });
    try ui.label("Project Details");
    if (state.projects.items.len == 0) {
        try core_ui.widgets_feedback.statusLabel(ui, "No projects yet");
        try ui.label("Create or import a project");
        ui.endPanel();
        return;
    }
    const selected = state.projects.items[state.selected_index];
    try ui.label(selected.name);
    try detail(ui, "Last opened", selected.last_opened);
    try detail(ui, "Path", selected.path);
    try detail(ui, "Status", selected.status);
    try ui.label("Enabled modules");
    try core_ui.widgets_feedback.statusLabel(ui, selected.tags);
    try core_ui.layout.spacer(ui, 6);
    try core_ui.layout.sameLine(ui);
    const stale = std.mem.startsWith(u8, selected.status, "Stale");
    if ((try button(ui, "pm-relocate", "Relocate...", 102, null, false)).clicked) {
        if (state.window) |window| try state.requestRelocateFolderDialog(window);
    }
    if ((try button(ui, "pm-remove", "Remove", 88, null, false)).clicked) {
        try pm_state_projects.removeSelectedProject(state);
    }
    if (stale) {
        try core_ui.widgets_feedback.statusLabel(ui, "Point this entry at the correct folder or remove it");
    }
    try core_ui.layout.endSameLine(ui);
    ui.endPanel();
}

fn buildBottomStrip(ui: *core_ui.UiContext, state: *pm_state.ProjectManagerState, rect: core_ui.Rect) !void {
    try ui.beginPanel(.{ .id = "pm-bottom", .rect = rect, .row_height = 24, .padding = 6, .spacing = row_spacing });
    try text(ui, "pm-status", .{ .x = rect.x + 10, .y = rect.y + 5, .w = rect.w - 20, .h = 22 }, state.status(), true);
    ui.endPanel();
}

fn buildModal(ui: *core_ui.UiContext, state: *pm_state.ProjectManagerState, window_w: f32, window_h: f32) !void {
    const backdrop = core_ui.Rect{ .x = 0, .y = 0, .w = window_w, .h = window_h };
    try core_ui.input_tree.pushOverlay(ui, backdrop);
    defer core_ui.input_tree.pop(ui);
    try ui.pushCommand(.{ .panel = .{ .id = 9, .rect = backdrop } });
    if (state.mode == .manage_presets) return buildPresetManagerModal(ui, state, window_w, window_h);

    const modal_h: f32 = if (state.mode == .about) 200 else 220;
    const rect = core_ui.Rect{ .x = (window_w - 520) * 0.5, .y = (window_h - modal_h) * 0.5, .w = 520, .h = modal_h };
    try ui.beginPanel(.{ .id = "pm-modal", .rect = rect, .row_height = row_h, .padding = inspector_pad, .spacing = row_spacing });
    try ui.label(switch (state.mode) {
        .create => "Create New Project",
        .preset_name => if (state.preset_name_action == .new) "New Preset" else "Rename Preset",
        .about => "About friendly-engine editor",
        .none, .manage_presets => "",
    });
    try core_ui.widgets_feedback.statusLabel(ui, switch (state.mode) {
        .create => "Enter a folder name or path",
        .preset_name => "Enter a preset name",
        .about => "Cross-platform 3D game engine editor shell.",
        .none, .manage_presets => "",
    });
    if (state.mode == .create) {
        try buildCreatePresetPicker(ui, state);
        try inputDisplay(ui, "pm-create-input", state.inputText());
        try core_ui.widgets_feedback.statusLabel(ui, "Enter = confirm, Esc = cancel");
    } else if (state.mode == .preset_name) {
        try inputDisplay(ui, "pm-preset-name-input", state.inputText());
        try core_ui.widgets_feedback.statusLabel(ui, "Enter = confirm, Esc = back");
    } else {
        try core_ui.layout.spacer(ui, 36);
    }
    try core_ui.layout.sameLine(ui);
    if ((try button(ui, "pm-cancel", "Cancel", 96, null, false)).clicked) state.cancelMode();
    const confirm_label: []const u8 = if (state.mode == .create) "Create" else "Close";
    if ((try button(ui, "pm-confirm", confirm_label, 96, null, false)).clicked) state.submitInputFromUi();
    try core_ui.layout.endSameLine(ui);
    ui.endPanel();
}

fn buildCreatePresetPicker(ui: *core_ui.UiContext, state: *pm_state.ProjectManagerState) !void {
    state.syncCreatePresetSelection();
    const preset_name = state.selectedCreatePresetName();
    try core_ui.layout.sameLine(ui);
    if ((try button(ui, "pm-create-preset-prev", "<", 36, null, false)).clicked) try state.cycleCreatePreset(-1);
    const label = try std.fmt.allocPrint(ui.frame_arena.allocator(), "{s}", .{preset_name});
    if ((try button(ui, "pm-create-preset-name", label, 284, null, false)).clicked) {
        state.loadPresetScratch(state.selected_preset_index);
        state.beginMode(.manage_presets, state.inputText());
    }
    if ((try button(ui, "pm-create-preset-next", ">", 36, null, false)).clicked) try state.cycleCreatePreset(1);
    if ((try button(ui, "pm-create-preset-manage", "Manage...", 112, null, false)).clicked) {
        state.loadPresetScratch(state.selected_preset_index);
        state.beginMode(.manage_presets, state.inputText());
    }
    try core_ui.layout.endSameLine(ui);

    const summary = try pm_util.formatEnabledModules(ui.frame_arena.allocator(), state.selectedCreateModules());
    try core_ui.widgets_feedback.statusLabel(ui, summary);
    if (!pm_presets.hasEditorGem(state.selectedCreateModules())) {
        try core_ui.widgets_feedback.statusLabel(ui, "Won't open in the editor - no editor gems");
    }
}

fn buildPresetManagerModal(ui: *core_ui.UiContext, state: *pm_state.ProjectManagerState, window_w: f32, window_h: f32) !void {
    const modal_w: f32 = @min(840, window_w - outer_pad * 2);
    const modal_h: f32 = @min(620, window_h - outer_pad * 2);
    const rect = core_ui.Rect{ .x = (window_w - modal_w) * 0.5, .y = (window_h - modal_h) * 0.5, .w = modal_w, .h = modal_h };
    try ui.beginPanel(.{ .id = "pm-presets-modal", .rect = rect, .row_height = 24, .padding = inspector_pad, .spacing = 5 });
    try ui.label("Gem Presets");
    try core_ui.widgets_feedback.statusLabel(ui, "Built-ins are read-only. Custom presets seed new projects.");

    const list_x = rect.x + inspector_pad;
    const list_y = rect.y + 70;
    const list_w: f32 = 220;
    const list_row_h: f32 = 26;
    const right_x = list_x + list_w + 18;
    const right_w = rect.w - (right_x - rect.x) - inspector_pad;
    const selected = state.presetAt(state.selected_preset_index);
    const selected_readonly = selected.builtin;

    try text(ui, "pm-presets-list-title", .{ .x = list_x, .y = list_y - 24, .w = list_w, .h = 18 }, "Presets", true);
    var i: usize = 0;
    while (i < state.presetCount()) : (i += 1) {
        const preset = state.presetAt(i);
        const y = list_y + @as(f32, @floatFromInt(i)) * (list_row_h + 4);
        try rowAt(ui, list_x, y);
        const label = if (preset.builtin)
            try std.fmt.allocPrint(ui.frame_arena.allocator(), "{s} (read-only)", .{preset.name})
        else
            preset.name;
        if ((try button(ui, preset.name, label, list_w, i == state.selected_preset_index, false)).clicked) {
            state.selectPresetForEditing(i);
        }
    }

    try text(ui, "pm-presets-right-title", .{ .x = right_x, .y = list_y - 24, .w = right_w, .h = 18 }, selected.name, false);
    const summary = try pm_util.formatEnabledModules(ui.frame_arena.allocator(), selected.modules);
    try text(ui, "pm-presets-summary", .{ .x = right_x, .y = list_y - 4, .w = right_w, .h = 18 }, summary, true);

    const catalog = pm_presets.catalogModuleNames();
    const gem_y = list_y + 24;
    const gem_row_h: f32 = 22;
    const columns: usize = if (right_w > 430) 2 else 1;
    const col_w = (right_w - 12) / @as(f32, @floatFromInt(columns));
    for (catalog, 0..) |module_name, module_index| {
        const col: usize = module_index % columns;
        const row: usize = module_index / columns;
        const x = right_x + @as(f32, @floatFromInt(col)) * (col_w + 12);
        const y = gem_y + @as(f32, @floatFromInt(row)) * (gem_row_h + 4);
        try rowAt(ui, x, y);
        const checked = if (module_index < state.preset_edit_modules.len and state.preset_edit_modules[module_index]) "[x]" else "[ ]";
        const label = try std.fmt.allocPrint(ui.frame_arena.allocator(), "{s} {s}", .{ checked, module_name });
        if ((try button(ui, module_name, label, col_w, null, selected_readonly)).clicked) state.togglePresetModule(module_index);
    }

    const controls_y = rect.y + rect.h - inspector_pad - row_h;
    try rowAt(ui, rect.x + inspector_pad, controls_y);
    if ((try button(ui, "pm-preset-new", "New", 82, null, false)).clicked) state.beginNewPreset();
    if ((try button(ui, "pm-preset-rename", "Rename", 92, null, selected_readonly)).clicked) state.beginRenamePreset();
    if ((try button(ui, "pm-preset-delete", "Delete", 92, null, selected_readonly)).clicked) {
        state.deleteSelectedPreset() catch |err| setErrorStatus(state, "Delete failed", err);
    }
    if ((try button(ui, "pm-preset-save", "Save", 82, null, selected_readonly)).clicked) {
        state.saveSelectedPresetModules() catch |err| setErrorStatus(state, "Save failed", err);
    }
    if ((try button(ui, "pm-preset-use-create", "Use", 82, null, false)).clicked) {
        try state.selectCreatePreset(state.selected_preset_index);
        state.beginMode(.create, state.inputText());
    }
    if ((try button(ui, "pm-preset-close", "Close", 82, null, false)).clicked) state.cancelMode();
    try core_ui.layout.endSameLine(ui);
    ui.endPanel();
}

fn detail(ui: *core_ui.UiContext, name: []const u8, value: []const u8) !void {
    try core_ui.widgets_feedback.statusLabel(ui, name);
    try ui.label(value);
}

fn inputDisplay(ui: *core_ui.UiContext, id: []const u8, value: []const u8) !void {
    const rect = try ui.allocFullWidthRow(40);
    const stable = try ui.stableId(id, id);
    try ui.pushCommand(.{ .text_input = .{
        .id = ui.nextCommandId(stable),
        .rect = rect,
        .text = try ui.dupeText(value),
        .cursor = value.len,
        .focused = true,
        .hovered = rect.contains(ui.input.mouse_position),
    } });
}

fn projectRow(ui: *core_ui.UiContext, state: *pm_state.ProjectManagerState, index: usize, id: []const u8, label: []const u8) !struct { rect: core_ui.Rect, clicked: bool } {
    const rect = try ui.allocFullWidthRow(project_row_h);
    const stable = try ui.stableId(id, label);
    const click = core_ui.input.handleClick(ui, stable, rect);
    try ui.pushCommand(.{ .selectable = .{
        .id = ui.nextCommandId(stable),
        .rect = rect,
        .text = try ui.dupeText(label),
        .text_pad_x = project_row_inset,
        .selected = state.selected_index == index,
        .hovered = click.hovered,
        .active = click.active,
    } });
    return .{ .rect = rect, .clicked = click.clicked };
}

fn button(ui: *core_ui.UiContext, id: []const u8, label: []const u8, width: f32, selected: ?bool, disabled: bool) !core_ui.ButtonResult {
    const rect = try ui.allocRowRect(width, (try ui.currentLayout()).row_height);
    const stable = try ui.stableId(id, id);
    const click = if (disabled) core_ui.input.ClickResult{} else core_ui.input.handleClick(ui, stable, rect);
    try ui.pushCommand(.{ .button = .{
        .id = ui.nextCommandId(stable),
        .rect = rect,
        .text = try ui.dupeText(label),
        .hovered = click.hovered,
        .active = click.active or (selected orelse false),
        .disabled = disabled,
    } });
    return .{ .id = stable, .rect = rect, .hovered = click.hovered, .clicked = click.clicked };
}

fn text(ui: *core_ui.UiContext, id: []const u8, rect: core_ui.Rect, value: []const u8, muted: bool) !void {
    const stable = try ui.stableId(id, id);
    try ui.pushCommand(.{ .text = .{ .id = ui.nextCommandId(stable), .rect = rect, .text = try ui.dupeText(value), .muted = muted } });
}

fn rowAt(ui: *core_ui.UiContext, x: f32, y: f32) !void {
    const cursor = try ui.currentLayout();
    cursor.same_line = true;
    cursor.same_line_y = y;
    cursor.cursor_x = x;
    cursor.cursor_y = y;
}

fn countText(ui: *core_ui.UiContext, count: usize) ![]const u8 {
    return std.fmt.allocPrint(ui.frame_arena.allocator(), "{d} projects", .{count});
}

fn openSelected(state: *pm_state.ProjectManagerState) !void {
    state.openSelectedProject() catch |err| {
        var buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "Open failed: {s}", .{@errorName(err)}) catch unreachable;
        state.setStatus(msg);
    };
}

fn selectedProjectIsStale(state: *const pm_state.ProjectManagerState) bool {
    if (state.projects.items.len == 0 or state.selected_index >= state.projects.items.len) return false;
    return std.mem.startsWith(u8, state.projects.items[state.selected_index].status, "Stale");
}

fn setErrorStatus(state: *pm_state.ProjectManagerState, prefix: []const u8, err: anyerror) void {
    var buf: [128]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "{s}: {s}", .{ prefix, @errorName(err) }) catch unreachable;
    state.setStatus(msg);
}
