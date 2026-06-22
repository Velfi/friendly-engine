const std = @import("std");
const builtin = @import("builtin");
const editor_draw = @import("editor_draw.zig");
const menu = @import("menu.zig");
const pm_types = @import("pm_types.zig");
const pm_util = @import("pm_util.zig");
const pm_presets = @import("pm_presets.zig");
const pm_state_config = @import("pm_state_config.zig");
const pm_state_projects = @import("pm_state_projects.zig");

const SDL_Window = editor_draw.SDL_Window;
const SDL_Event = editor_draw.SDL_Event;
const SDL_ShowOpenFolderDialog = editor_draw.SDL_ShowOpenFolderDialog;

const SDL_QUIT: u32 = editor_draw.SDL_QUIT;
const SDL_EVENT_KEY_DOWN: u32 = editor_draw.SDL_EVENT_KEY_DOWN;
const SDL_EVENT_TEXT_INPUT: u32 = editor_draw.SDL_EVENT_TEXT_INPUT;
const SDLK_RETURN: i32 = 0x0d;
const SDLK_ESCAPE: i32 = 0x1b;
const SDLK_BACKSPACE: i32 = 0x08;
const SDLK_N: i32 = 0x6e;
const SDLK_O: i32 = 0x6f;
const SDLK_I: i32 = 0x69;
const SDLK_Q: i32 = 0x71;
const SDL_KMOD_CTRL: u16 = 0x0040 | 0x0080;
const SDL_KMOD_GUI: u16 = 0x0400 | 0x0800;

pub const ProjectManagerState = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    workspace_path: []u8,
    state_file_path: []u8,
    projects: std.ArrayList(pm_types.ProjectManagerEntry),
    selected_index: usize = 0,
    mode: pm_types.InputMode = .none,
    input_buf: [512]u8 = [_]u8{0} ** 512,
    input_len: usize = 0,
    status_buf: [256]u8 = [_]u8{0} ** 256,
    status_len: usize = 0,
    default_enabled_modules_json: []u8,
    default_enabled_modules: [][]u8,
    user_presets: std.ArrayList(pm_presets.GemPreset),
    create_preset_name: []u8,
    selected_preset_index: usize = 0,
    preset_edit_modules: []bool,
    preset_name_action: pm_types.PresetNameAction = .none,
    window: ?*SDL_Window = null,
    list_filter: pm_types.ListFilter = .all,
    open_window_menu: menu.WindowMenuId = .none,
    pending_dialog_path_buf: [512]u8 = undefined,
    pending_dialog_path_len: std.atomic.Value(u16) = std.atomic.Value(u16).init(0),
    pending_dialog_kind_atomic: std.atomic.Value(u8) = std.atomic.Value(u8).init(0),
    should_quit: bool = false,
    pending_open_editor: bool = false,

    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        environ_map: *const std.process.Environ.Map,
        workspace_path: []const u8,
        enabled_modules: []const []const u8,
        enable_renderer: bool,
    ) !ProjectManagerState {
        const state_file_path = try pm_util.resolveProjectManagerStatePath(allocator, environ_map);

        try std.Io.Dir.cwd().createDirPath(io, std.fs.path.dirname(state_file_path).?);

        var state = ProjectManagerState{
            .allocator = allocator,
            .io = io,
            .workspace_path = try allocator.dupe(u8, workspace_path),
            .state_file_path = state_file_path,
            .projects = .empty,
            .default_enabled_modules_json = try pm_util.formatEnabledModulesJson(allocator, enabled_modules),
            .default_enabled_modules = try dupeStringList(allocator, enabled_modules),
            .user_presets = .empty,
            .create_preset_name = try allocator.dupe(u8, "Minimal"),
            .preset_edit_modules = try allocator.alloc(bool, pm_presets.catalogModuleNames().len),
        };
        errdefer allocator.free(state.workspace_path);
        errdefer allocator.free(state.state_file_path);
        errdefer allocator.free(state.default_enabled_modules_json);
        errdefer freeStringList(allocator, state.default_enabled_modules);
        errdefer allocator.free(state.create_preset_name);
        errdefer allocator.free(state.preset_edit_modules);
        errdefer freePresetList(allocator, &state.user_presets);
        errdefer state.projects.deinit(allocator);

        const loaded_from_disk = try pm_state_config.loadConfig(&state);
        state.syncCreatePresetSelection();
        state.loadPresetScratch(state.selected_preset_index);

        if (state.projects.items.len == 0) {
            const default_modules_summary = try pm_util.formatEnabledModules(allocator, enabled_modules);
            defer allocator.free(default_modules_summary);
            const initial_entry = try pm_util.makeProjectEntry(
                allocator,
                std.fs.path.basename(workspace_path),
                workspace_path,
                if (enable_renderer) "Forward+" else "Headless",
                default_modules_summary,
                "Current workspace",
                "Loaded from engine.kdl",
            );
            try state.projects.append(allocator, initial_entry);
            state.selected_index = 0;
            try pm_state_config.saveConfig(&state);
            state.setStatus("Project Manager initialized (new config)");
        } else if (loaded_from_disk) {
            state.setStatus("Project Manager loaded from OS app data");
        }
        return state;
    }

    pub fn deinit(self: *ProjectManagerState) void {
        for (self.projects.items) |*entry| {
            pm_util.deinitProjectEntry(self.allocator, entry);
        }
        self.projects.deinit(self.allocator);
        self.allocator.free(self.workspace_path);
        self.allocator.free(self.state_file_path);
        self.allocator.free(self.default_enabled_modules_json);
        freeStringList(self.allocator, self.default_enabled_modules);
        self.allocator.free(self.create_preset_name);
        self.allocator.free(self.preset_edit_modules);
        freePresetList(self.allocator, &self.user_presets);
    }

    pub fn processPending(self: *ProjectManagerState, window: *SDL_Window) !bool {
        var menu_action: c_int = 0;
        if (menu.fe_menubar_poll_action(&menu_action)) {
            try self.dispatchMenuAction(@enumFromInt(menu_action), window);
            if (self.should_quit) return false;
        }

        const dialog_len = self.pending_dialog_path_len.swap(0, .acquire);
        if (dialog_len > 0) {
            const dialog_kind_val = self.pending_dialog_kind_atomic.swap(0, .acquire);
            const dialog_kind: pm_types.PendingDialogKind = @enumFromInt(dialog_kind_val);
            const dialog_path = self.pending_dialog_path_buf[0..dialog_len];
            switch (dialog_kind) {
                .none => {},
                .import_folder => try pm_state_projects.importProjectAtPath(self, dialog_path),
            }
        }
        return true;
    }

    pub fn dispatchMenuAction(self: *ProjectManagerState, action: menu.FeMenuAction, window: *SDL_Window) !void {
        switch (action) {
            .none => {},
            .new_project => self.beginMode(.create, "new_project"),
            .manage_presets => {
                self.syncCreatePresetSelection();
                self.loadPresetScratch(self.selected_preset_index);
                self.beginMode(.manage_presets, "");
            },
            .import_project => try self.requestImportFolderDialog(window),
            .open_project => try pm_state_projects.openSelectedProject(self),
            .about => self.beginMode(.about, ""),
            .quit => self.should_quit = true,
            .remove_from_list => try pm_state_projects.removeSelectedProject(self),
        }
    }

    fn nullTerminatedPath(allocator: std.mem.Allocator, path: []const u8) ![:0]const u8 {
        return allocator.dupeZ(u8, path);
    }

    pub fn requestImportFolderDialog(self: *ProjectManagerState, window: *SDL_Window) !void {
        const default_location = try ProjectManagerState.nullTerminatedPath(self.allocator, self.workspace_path);
        defer self.allocator.free(default_location);
        SDL_ShowOpenFolderDialog(pm_util.folderDialogCallback, self, window, default_location.ptr, false);
    }

    pub fn queueDialogPath(self: *ProjectManagerState, path: []const u8, kind: pm_types.PendingDialogKind) void {
        const len = @min(path.len, self.pending_dialog_path_buf.len);
        @memcpy(self.pending_dialog_path_buf[0..len], path[0..len]);
        self.pending_dialog_kind_atomic.store(@intFromEnum(kind), .release);
        self.pending_dialog_path_len.store(@intCast(len), .release);
    }

    pub fn openSelectedProject(self: *ProjectManagerState) !void {
        return pm_state_projects.openSelectedProject(self);
    }

    pub fn filteredProjectCount(self: *const ProjectManagerState) usize {
        return switch (self.list_filter) {
            .all => self.projects.items.len,
            .recent => @min(5, self.projects.items.len),
        };
    }

    pub fn filteredProjectIndex(self: *const ProjectManagerState, display_index: usize) ?usize {
        if (display_index >= self.filteredProjectCount()) return null;
        return display_index;
    }

    pub fn setStatus(self: *ProjectManagerState, message: []const u8) void {
        self.status_len = @min(message.len, self.status_buf.len);
        @memcpy(self.status_buf[0..self.status_len], message[0..self.status_len]);
    }

    pub fn status(self: *const ProjectManagerState) []const u8 {
        return self.status_buf[0..self.status_len];
    }

    pub fn beginMode(self: *ProjectManagerState, mode: pm_types.InputMode, seed: []const u8) void {
        self.mode = mode;
        self.input_len = @min(seed.len, self.input_buf.len);
        @memcpy(self.input_buf[0..self.input_len], seed[0..self.input_len]);
    }

    pub fn cancelMode(self: *ProjectManagerState) void {
        self.mode = .none;
        self.input_len = 0;
    }

    pub fn inputText(self: *const ProjectManagerState) []const u8 {
        return self.input_buf[0..self.input_len];
    }

    pub fn submitInput(self: *ProjectManagerState) !void {
        switch (self.mode) {
            .none => {},
            .create => try pm_state_projects.createProjectFromInput(self),
            .manage_presets => {},
            .preset_name => try self.submitPresetName(),
            .about => self.cancelMode(),
        }
    }

    pub fn saveConfig(self: *ProjectManagerState) !void {
        return pm_state_config.saveConfig(self);
    }

    pub fn presetCount(self: *const ProjectManagerState) usize {
        return pm_presets.builtinPresets().len + self.user_presets.items.len;
    }

    pub fn presetAt(self: *const ProjectManagerState, index: usize) pm_presets.GemPreset {
        const builtins = pm_presets.builtinPresets();
        if (index < builtins.len) return builtins[index];
        return self.user_presets.items[index - builtins.len];
    }

    pub fn selectedCreateModules(self: *const ProjectManagerState) []const []const u8 {
        if (pm_presets.findPreset(self, self.create_preset_name)) |preset| return preset.modules;
        return pm_presets.builtinPresets()[0].modules;
    }

    pub fn selectedCreatePresetName(self: *const ProjectManagerState) []const u8 {
        if (pm_presets.findPreset(self, self.create_preset_name)) |preset| return preset.name;
        return "Minimal";
    }

    pub fn selectCreatePreset(self: *ProjectManagerState, index: usize) !void {
        if (self.presetCount() == 0) return;
        const clamped = @min(index, self.presetCount() - 1);
        const preset = self.presetAt(clamped);
        try self.replaceCreatePresetName(preset.name);
        self.selected_preset_index = clamped;
        self.loadPresetScratch(clamped);
    }

    pub fn cycleCreatePreset(self: *ProjectManagerState, delta: isize) !void {
        const count = self.presetCount();
        if (count == 0) return;
        self.syncCreatePresetSelection();
        const current: isize = @intCast(self.selected_preset_index);
        const count_i: isize = @intCast(count);
        const next = @mod(current + delta, count_i);
        try self.selectCreatePreset(@intCast(next));
    }

    pub fn syncCreatePresetSelection(self: *ProjectManagerState) void {
        const count = self.presetCount();
        var i: usize = 0;
        while (i < count) : (i += 1) {
            if (std.mem.eql(u8, self.presetAt(i).name, self.create_preset_name)) {
                self.selected_preset_index = i;
                return;
            }
        }
        self.selected_preset_index = 0;
    }

    pub fn selectPresetForEditing(self: *ProjectManagerState, index: usize) void {
        if (self.presetCount() == 0) return;
        self.selected_preset_index = @min(index, self.presetCount() - 1);
        self.loadPresetScratch(self.selected_preset_index);
    }

    pub fn loadPresetScratch(self: *ProjectManagerState, index: usize) void {
        const catalog = pm_presets.catalogModuleNames();
        @memset(self.preset_edit_modules, false);
        if (catalog.len == 0 or index >= self.presetCount()) return;
        const preset = self.presetAt(index);
        for (catalog, 0..) |module_name, module_index| {
            for (preset.modules) |enabled| {
                if (std.mem.eql(u8, enabled, module_name)) {
                    self.preset_edit_modules[module_index] = true;
                    break;
                }
            }
        }
    }

    pub fn togglePresetModule(self: *ProjectManagerState, module_index: usize) void {
        if (module_index >= self.preset_edit_modules.len) return;
        const preset = self.presetAt(self.selected_preset_index);
        if (preset.builtin) return;
        self.preset_edit_modules[module_index] = !self.preset_edit_modules[module_index];
    }

    pub fn saveSelectedPresetModules(self: *ProjectManagerState) !void {
        const builtins = pm_presets.builtinPresets();
        if (self.selected_preset_index < builtins.len) return error.BuiltinPresetReadOnly;
        const user_index = self.selected_preset_index - builtins.len;
        const modules = try self.modulesFromScratch();
        errdefer freeStringList(self.allocator, modules);
        for (self.user_presets.items[user_index].modules) |module| self.allocator.free(@constCast(module));
        self.allocator.free(@constCast(self.user_presets.items[user_index].modules));
        self.user_presets.items[user_index].modules = modules;
        try self.saveConfig();
        self.setStatus("Preset saved");
    }

    pub fn beginNewPreset(self: *ProjectManagerState) void {
        self.preset_name_action = .new;
        self.beginMode(.preset_name, "Custom Preset");
    }

    pub fn beginRenamePreset(self: *ProjectManagerState) void {
        const preset = self.presetAt(self.selected_preset_index);
        if (preset.builtin) {
            self.setStatus("Built-in presets are read-only");
            return;
        }
        self.preset_name_action = .rename;
        self.beginMode(.preset_name, preset.name);
    }

    pub fn deleteSelectedPreset(self: *ProjectManagerState) !void {
        const builtins = pm_presets.builtinPresets();
        if (self.selected_preset_index < builtins.len) return error.BuiltinPresetReadOnly;
        const user_index = self.selected_preset_index - builtins.len;
        const should_reset_create_preset = std.mem.eql(u8, self.create_preset_name, self.user_presets.items[user_index].name);
        var preset = self.user_presets.orderedRemove(user_index);
        pm_presets.freeOwnedPreset(self.allocator, &preset);
        if (should_reset_create_preset) try self.replaceCreatePresetName("Minimal");
        self.selected_preset_index = @min(self.selected_preset_index, if (self.presetCount() == 0) 0 else self.presetCount() - 1);
        self.loadPresetScratch(self.selected_preset_index);
        try self.saveConfig();
        self.setStatus("Preset deleted");
    }

    pub fn addPreset(self: *ProjectManagerState, name: []const u8, modules: []const []const u8) !void {
        const trimmed = std.mem.trim(u8, name, " \t\r\n");
        if (trimmed.len == 0) return error.EmptyPresetName;
        if (pm_presets.findPreset(self, trimmed) != null) return error.DuplicatePresetName;
        const owned_modules = try pm_presets.dupeModuleList(self.allocator, modules);
        errdefer freeStringList(self.allocator, owned_modules);
        const preset = pm_presets.GemPreset{
            .name = try self.allocator.dupe(u8, trimmed),
            .modules = owned_modules,
            .builtin = false,
        };
        errdefer self.allocator.free(@constCast(preset.name));
        try self.user_presets.append(self.allocator, preset);
    }

    pub fn renameSelectedPreset(self: *ProjectManagerState, name: []const u8) !void {
        const builtins = pm_presets.builtinPresets();
        if (self.selected_preset_index < builtins.len) return error.BuiltinPresetReadOnly;
        const trimmed = std.mem.trim(u8, name, " \t\r\n");
        if (trimmed.len == 0) return error.EmptyPresetName;
        const current = self.presetAt(self.selected_preset_index);
        if (!std.mem.eql(u8, current.name, trimmed) and pm_presets.findPreset(self, trimmed) != null) return error.DuplicatePresetName;
        const user_index = self.selected_preset_index - builtins.len;
        const should_update_create_preset = std.mem.eql(u8, self.create_preset_name, self.user_presets.items[user_index].name);
        const new_name = try self.allocator.dupe(u8, trimmed);
        self.allocator.free(@constCast(self.user_presets.items[user_index].name));
        self.user_presets.items[user_index].name = new_name;
        if (should_update_create_preset) try self.replaceCreatePresetName(new_name);
    }

    fn submitPresetName(self: *ProjectManagerState) !void {
        const name = self.inputText();
        switch (self.preset_name_action) {
            .none => {},
            .new => {
                const modules = try self.modulesFromScratch();
                defer freeStringList(self.allocator, modules);
                try self.addPreset(name, modules);
                self.selected_preset_index = self.presetCount() - 1;
                try self.replaceCreatePresetName(self.presetAt(self.selected_preset_index).name);
                self.loadPresetScratch(self.selected_preset_index);
                try self.saveConfig();
                self.setStatus("Preset created");
            },
            .rename => {
                try self.renameSelectedPreset(name);
                try self.saveConfig();
                self.setStatus("Preset renamed");
            },
        }
        self.preset_name_action = .none;
        self.mode = .manage_presets;
        self.input_len = 0;
    }

    fn modulesFromScratch(self: *ProjectManagerState) ![][]u8 {
        const catalog = pm_presets.catalogModuleNames();
        var modules = std.ArrayList([]const u8).empty;
        defer modules.deinit(self.allocator);
        for (catalog, 0..) |module_name, idx| {
            if (self.preset_edit_modules[idx]) try modules.append(self.allocator, module_name);
        }
        return pm_presets.dupeModuleList(self.allocator, modules.items);
    }

    fn replaceCreatePresetName(self: *ProjectManagerState, name: []const u8) !void {
        const owned = try self.allocator.dupe(u8, name);
        self.allocator.free(self.create_preset_name);
        self.create_preset_name = owned;
    }
};

fn dupeStringList(allocator: std.mem.Allocator, values: []const []const u8) ![][]u8 {
    var owned = try allocator.alloc([]u8, values.len);
    var i: usize = 0;
    errdefer {
        while (i > 0) {
            i -= 1;
            allocator.free(owned[i]);
        }
        allocator.free(owned);
    }
    for (values) |value| {
        owned[i] = try allocator.dupe(u8, value);
        i += 1;
    }
    return owned;
}

fn freeStringList(allocator: std.mem.Allocator, values: [][]u8) void {
    for (values) |value| allocator.free(value);
    allocator.free(values);
}

fn freePresetList(allocator: std.mem.Allocator, presets: *std.ArrayList(pm_presets.GemPreset)) void {
    for (presets.items) |*preset| pm_presets.freeOwnedPreset(allocator, preset);
    presets.deinit(allocator);
}

fn makeTestState(allocator: std.mem.Allocator) !ProjectManagerState {
    return .{
        .allocator = allocator,
        .io = std.testing.io,
        .workspace_path = try allocator.dupe(u8, "/tmp"),
        .state_file_path = try allocator.dupe(u8, "/tmp/project_manager.json"),
        .projects = .empty,
        .default_enabled_modules_json = try allocator.dupe(u8, ""),
        .default_enabled_modules = try allocator.alloc([]u8, 0),
        .user_presets = .empty,
        .create_preset_name = try allocator.dupe(u8, "Minimal"),
        .preset_edit_modules = try allocator.alloc(bool, pm_presets.catalogModuleNames().len),
    };
}

test "preset CRUD rejects builtins and duplicate names" {
    const allocator = std.testing.allocator;
    var state = try makeTestState(allocator);
    defer state.deinit();

    try std.testing.expectError(error.BuiltinPresetReadOnly, state.deleteSelectedPreset());
    try state.addPreset("Custom", &.{"gem.ecs"});
    try std.testing.expectError(error.DuplicatePresetName, state.addPreset("Custom", &.{"gem.core_ui"}));

    state.selectPresetForEditing(0);
    try std.testing.expectError(error.BuiltinPresetReadOnly, state.renameSelectedPreset("Tiny"));

    state.selectPresetForEditing(2);
    try state.renameSelectedPreset("Renamed");
    try std.testing.expectEqualStrings("Renamed", state.user_presets.items[0].name);
}
