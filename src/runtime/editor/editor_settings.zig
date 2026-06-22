const std = @import("std");
const editor_core_ui_draw = @import("editor_core_ui_draw.zig");
const pm_util = @import("pm_util.zig");
const shared = @import("runtime_shared");

pub const Style = editor_core_ui_draw.Style;
const Color = shared.color.Color;

const settings_file_name = "editor_settings.json";
const default_theme_file = "themes/gray_dark.json";
const legacy_default_theme_file = "themes/default_dark.json";
pub const default_refresh_rate_hz: ?u32 = 60;
pub const default_terrain_undo_limit_mb: u64 = 1024;

pub const ThemeChoice = struct {
    label: []const u8,
    file: []const u8,
};

pub const builtin_theme_choices = [_]ThemeChoice{
    .{ .label = "Gray Dark", .file = "themes/gray_dark.json" },
    .{ .label = "Gray Light", .file = "themes/gray_light.json" },
};

pub const OwnedEditorSettings = struct {
    settings_file_path: []u8,
    theme_file: []u8,
    theme_path: []u8,
    refresh_rate_hz: ?u32,
    terrain_undo_limit_mb: u64,
    style: Style,

    pub fn deinit(self: *OwnedEditorSettings, allocator: std.mem.Allocator) void {
        allocator.free(self.settings_file_path);
        allocator.free(self.theme_file);
        allocator.free(self.theme_path);
    }
};

pub fn load(
    allocator: std.mem.Allocator,
    io: std.Io,
    environ_map: *const std.process.Environ.Map,
) !OwnedEditorSettings {
    const app_data_dir = try pm_util.resolveAppDataDirectory(allocator, environ_map, "friendly-engine");
    defer allocator.free(app_data_dir);

    try std.Io.Dir.cwd().createDirPath(io, app_data_dir);

    const settings_file_path = try std.fs.path.join(allocator, &.{ app_data_dir, settings_file_name });
    errdefer allocator.free(settings_file_path);

    const settings_dir = std.fs.path.dirname(settings_file_path) orelse return error.InvalidEditorSettingsPath;
    const themes_dir = try std.fs.path.join(allocator, &.{ settings_dir, "themes" });
    defer allocator.free(themes_dir);
    try std.Io.Dir.cwd().createDirPath(io, themes_dir);

    try ensureBuiltinThemeFiles(allocator, io, settings_dir);
    try ensureDefaultSettingsFile(allocator, io, settings_file_path);

    var settings = try readSettingsFile(allocator, io, settings_file_path);
    errdefer allocator.free(settings.theme_file);
    try migrateLegacyDefaultTheme(allocator, io, settings_file_path, &settings);

    const theme_path = try resolveThemePath(allocator, settings_dir, settings.theme_file);
    errdefer allocator.free(theme_path);

    const style = try readThemeFile(allocator, io, theme_path);

    return .{
        .settings_file_path = settings_file_path,
        .theme_file = settings.theme_file,
        .theme_path = theme_path,
        .refresh_rate_hz = settings.refresh_rate_hz,
        .terrain_undo_limit_mb = settings.terrain_undo_limit_mb,
        .style = style,
    };
}

pub fn applyThemeFile(
    allocator: std.mem.Allocator,
    io: std.Io,
    settings: *OwnedEditorSettings,
    theme_file: []const u8,
) !void {
    if (theme_file.len == 0) return error.EmptyEditorThemeFile;
    const settings_dir = std.fs.path.dirname(settings.settings_file_path) orelse return error.InvalidEditorSettingsPath;
    const theme_path = try resolveThemePath(allocator, settings_dir, theme_file);
    errdefer allocator.free(theme_path);
    const style = try readThemeFile(allocator, io, theme_path);
    const owned_theme_file = try allocator.dupe(u8, theme_file);
    errdefer allocator.free(owned_theme_file);

    try writeSettingsFile(allocator, io, settings.settings_file_path, .{
        .theme_file = theme_file,
        .refresh_rate_hz = settings.refresh_rate_hz,
        .terrain_undo_limit_mb = settings.terrain_undo_limit_mb,
    });

    allocator.free(settings.theme_file);
    allocator.free(settings.theme_path);
    settings.theme_file = owned_theme_file;
    settings.theme_path = theme_path;
    settings.style = style;
}

pub fn applyRefreshRate(
    allocator: std.mem.Allocator,
    io: std.Io,
    settings: *OwnedEditorSettings,
    refresh_rate_hz: ?u32,
) !void {
    try validateRefreshRate(refresh_rate_hz);
    try writeSettingsFile(allocator, io, settings.settings_file_path, .{
        .theme_file = settings.theme_file,
        .refresh_rate_hz = refresh_rate_hz,
        .terrain_undo_limit_mb = settings.terrain_undo_limit_mb,
    });
    settings.refresh_rate_hz = refresh_rate_hz;
}

pub fn applyTerrainUndoLimitMb(
    allocator: std.mem.Allocator,
    io: std.Io,
    settings: *OwnedEditorSettings,
    terrain_undo_limit_mb: u64,
) !void {
    try validateTerrainUndoLimitMb(terrain_undo_limit_mb);
    try writeSettingsFile(allocator, io, settings.settings_file_path, .{
        .theme_file = settings.theme_file,
        .refresh_rate_hz = settings.refresh_rate_hz,
        .terrain_undo_limit_mb = terrain_undo_limit_mb,
    });
    settings.terrain_undo_limit_mb = terrain_undo_limit_mb;
}

pub fn currentThemeLabel(settings: OwnedEditorSettings) []const u8 {
    for (builtin_theme_choices) |choice| {
        if (std.mem.eql(u8, settings.theme_file, choice.file)) return choice.label;
    }
    return settings.theme_file;
}

pub fn refreshRateLabel(refresh_rate_hz: ?u32) []const u8 {
    return switch (refresh_rate_hz orelse 0) {
        0 => "Uncapped",
        30 => "30 Hz",
        60 => "60 Hz",
        90 => "90 Hz",
        120 => "120 Hz",
        144 => "144 Hz",
        else => "Custom",
    };
}

pub fn terrainUndoLimitLabel(limit_mb: u64) []const u8 {
    return switch (limit_mb) {
        0 => "Unlimited",
        256 => "256 MB",
        512 => "512 MB",
        1024 => "1 GB",
        2048 => "2 GB",
        4096 => "4 GB",
        else => "Custom",
    };
}

const ParsedSettings = struct {
    schema_version: u32,
    theme_file: []const u8,
    refresh_rate_hz: ?u32 = default_refresh_rate_hz,
    terrain_undo_limit_mb: u64 = default_terrain_undo_limit_mb,
};

const OwnedParsedSettings = struct {
    theme_file: []u8,
    refresh_rate_hz: ?u32,
    terrain_undo_limit_mb: u64,
};

fn readSettingsFile(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !OwnedParsedSettings {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(64 * 1024));
    defer allocator.free(bytes);

    var parsed = try std.json.parseFromSlice(ParsedSettings, allocator, bytes, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    if (parsed.value.schema_version != 1) return error.UnsupportedEditorSettingsSchema;
    if (parsed.value.theme_file.len == 0) return error.EmptyEditorThemeFile;
    try validateRefreshRate(parsed.value.refresh_rate_hz);
    try validateTerrainUndoLimitMb(parsed.value.terrain_undo_limit_mb);

    return .{
        .theme_file = try allocator.dupe(u8, parsed.value.theme_file),
        .refresh_rate_hz = parsed.value.refresh_rate_hz,
        .terrain_undo_limit_mb = parsed.value.terrain_undo_limit_mb,
    };
}

fn resolveThemePath(allocator: std.mem.Allocator, settings_dir: []const u8, theme_file: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(theme_file)) return allocator.dupe(u8, theme_file);
    return std.fs.path.join(allocator, &.{ settings_dir, theme_file });
}

fn ensureDefaultSettingsFile(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !void {
    std.Io.Dir.cwd().access(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => try writeSettingsFile(allocator, io, path, .{
            .theme_file = default_theme_file,
            .refresh_rate_hz = default_refresh_rate_hz,
            .terrain_undo_limit_mb = default_terrain_undo_limit_mb,
        }),
        else => return err,
    };
}

fn migrateLegacyDefaultTheme(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    settings: *OwnedParsedSettings,
) !void {
    if (!std.mem.eql(u8, settings.theme_file, legacy_default_theme_file)) return;

    const migrated_theme_file = try allocator.dupe(u8, default_theme_file);
    try writeSettingsFile(allocator, io, path, .{
        .theme_file = migrated_theme_file,
        .refresh_rate_hz = settings.refresh_rate_hz,
        .terrain_undo_limit_mb = settings.terrain_undo_limit_mb,
    });
    allocator.free(settings.theme_file);
    settings.theme_file = migrated_theme_file;
}

const SettingsWrite = struct {
    theme_file: []const u8,
    refresh_rate_hz: ?u32,
    terrain_undo_limit_mb: u64,
};

fn writeSettingsFile(allocator: std.mem.Allocator, io: std.Io, path: []const u8, settings: SettingsWrite) !void {
    try validateRefreshRate(settings.refresh_rate_hz);
    try validateTerrainUndoLimitMb(settings.terrain_undo_limit_mb);
    const payload = ParsedSettings{
        .schema_version = 1,
        .theme_file = settings.theme_file,
        .refresh_rate_hz = settings.refresh_rate_hz,
        .terrain_undo_limit_mb = settings.terrain_undo_limit_mb,
    };
    const json = try std.fmt.allocPrint(
        allocator,
        "{f}\n",
        .{std.json.fmt(payload, .{ .whitespace = .indent_2 })},
    );
    defer allocator.free(json);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = json });
}

fn validateRefreshRate(refresh_rate_hz: ?u32) !void {
    const hz = refresh_rate_hz orelse return;
    switch (hz) {
        30, 60, 90, 120, 144 => {},
        else => return error.UnsupportedRefreshRate,
    }
}

fn validateTerrainUndoLimitMb(terrain_undo_limit_mb: u64) !void {
    if (terrain_undo_limit_mb > 1024 * 1024) return error.UnsupportedTerrainUndoLimit;
}

const BuiltinTheme = struct {
    file: []const u8,
    json: []const u8,
};

fn ensureBuiltinThemeFiles(allocator: std.mem.Allocator, io: std.Io, settings_dir: []const u8) !void {
    const themes = [_]BuiltinTheme{
        .{ .file = builtin_theme_choices[0].file, .json = grayDarkThemeJson() },
        .{ .file = builtin_theme_choices[1].file, .json = grayLightThemeJson() },
    };
    for (themes) |theme| {
        const path = try std.fs.path.join(allocator, &.{ settings_dir, theme.file });
        defer allocator.free(path);
        try ensureThemeFile(io, path, theme.json);
    }
}

fn ensureThemeFile(io: std.Io, path: []const u8, json: []const u8) !void {
    std.Io.Dir.cwd().access(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => try std.Io.Dir.cwd().writeFile(io, .{
            .sub_path = path,
            .data = json,
        }),
        else => return err,
    };
}

fn readThemeFile(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !Style {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(64 * 1024));
    defer allocator.free(bytes);
    return parseThemeBytes(allocator, bytes);
}

pub fn parseThemeBytes(allocator: std.mem.Allocator, bytes: []const u8) !Style {
    var parsed = try std.json.parseFromSlice(RequiredTheme, allocator, bytes, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    return parsed.value.toStyle();
}

const RequiredTheme = struct {
    panel_color: Color,
    button_color: Color,
    button_hovered_color: Color,
    button_active_color: Color,
    button_disabled_color: Color,
    accent_color: Color,
    text_color: Color,
    muted_text_color: Color,
    separator_color: Color,
    input_bg_color: Color,
    input_focus_color: Color,
    toggle_on_color: Color,
    selected_color: Color,
    error_color: Color,
    warning_color: Color,
    info_color: Color,
    tooltip_bg_color: Color,
    progress_fill_color: Color,
    checkbox_check_color: Color,

    fn toStyle(self: RequiredTheme) Style {
        return .{
            .panel_color = self.panel_color,
            .button_color = self.button_color,
            .button_hovered_color = self.button_hovered_color,
            .button_active_color = self.button_active_color,
            .button_disabled_color = self.button_disabled_color,
            .accent_color = self.accent_color,
            .text_color = self.text_color,
            .muted_text_color = self.muted_text_color,
            .separator_color = self.separator_color,
            .input_bg_color = self.input_bg_color,
            .input_focus_color = self.input_focus_color,
            .toggle_on_color = self.toggle_on_color,
            .selected_color = self.selected_color,
            .error_color = self.error_color,
            .warning_color = self.warning_color,
            .info_color = self.info_color,
            .tooltip_bg_color = self.tooltip_bg_color,
            .progress_fill_color = self.progress_fill_color,
            .checkbox_check_color = self.checkbox_check_color,
        };
    }
};

fn grayDarkThemeJson() []const u8 {
    return
    \\{
    \\  "panel_color": { "r": 30, "g": 30, "b": 32, "a": 236 },
    \\  "button_color": { "r": 48, "g": 48, "b": 51, "a": 255 },
    \\  "button_hovered_color": { "r": 64, "g": 64, "b": 68, "a": 255 },
    \\  "button_active_color": { "r": 82, "g": 82, "b": 88, "a": 255 },
    \\  "button_disabled_color": { "r": 38, "g": 38, "b": 40, "a": 255 },
    \\  "accent_color": { "r": 132, "g": 132, "b": 140, "a": 255 },
    \\  "text_color": { "r": 232, "g": 232, "b": 235, "a": 255 },
    \\  "muted_text_color": { "r": 158, "g": 158, "b": 164, "a": 255 },
    \\  "separator_color": { "r": 72, "g": 72, "b": 76, "a": 255 },
    \\  "input_bg_color": { "r": 22, "g": 22, "b": 24, "a": 255 },
    \\  "input_focus_color": { "r": 42, "g": 42, "b": 46, "a": 255 },
    \\  "toggle_on_color": { "r": 94, "g": 94, "b": 102, "a": 255 },
    \\  "selected_color": { "r": 70, "g": 70, "b": 76, "a": 255 },
    \\  "error_color": { "r": 170, "g": 82, "b": 82, "a": 255 },
    \\  "warning_color": { "r": 170, "g": 142, "b": 72, "a": 255 },
    \\  "info_color": { "r": 96, "g": 112, "b": 128, "a": 255 },
    \\  "tooltip_bg_color": { "r": 44, "g": 44, "b": 48, "a": 250 },
    \\  "progress_fill_color": { "r": 118, "g": 118, "b": 126, "a": 255 },
    \\  "checkbox_check_color": { "r": 190, "g": 190, "b": 198, "a": 255 }
    \\}
    \\
    ;
}

fn grayLightThemeJson() []const u8 {
    return
    \\{
    \\  "panel_color": { "r": 240, "g": 240, "b": 242, "a": 246 },
    \\  "button_color": { "r": 222, "g": 222, "b": 225, "a": 255 },
    \\  "button_hovered_color": { "r": 210, "g": 210, "b": 214, "a": 255 },
    \\  "button_active_color": { "r": 194, "g": 194, "b": 199, "a": 255 },
    \\  "button_disabled_color": { "r": 232, "g": 232, "b": 234, "a": 255 },
    \\  "accent_color": { "r": 92, "g": 92, "b": 98, "a": 255 },
    \\  "text_color": { "r": 30, "g": 30, "b": 32, "a": 255 },
    \\  "muted_text_color": { "r": 106, "g": 106, "b": 112, "a": 255 },
    \\  "separator_color": { "r": 188, "g": 188, "b": 194, "a": 255 },
    \\  "input_bg_color": { "r": 250, "g": 250, "b": 251, "a": 255 },
    \\  "input_focus_color": { "r": 232, "g": 232, "b": 236, "a": 255 },
    \\  "toggle_on_color": { "r": 174, "g": 174, "b": 181, "a": 255 },
    \\  "selected_color": { "r": 204, "g": 204, "b": 210, "a": 255 },
    \\  "error_color": { "r": 168, "g": 76, "b": 76, "a": 255 },
    \\  "warning_color": { "r": 148, "g": 120, "b": 58, "a": 255 },
    \\  "info_color": { "r": 126, "g": 134, "b": 144, "a": 255 },
    \\  "tooltip_bg_color": { "r": 225, "g": 225, "b": 230, "a": 250 },
    \\  "progress_fill_color": { "r": 130, "g": 130, "b": 138, "a": 255 },
    \\  "checkbox_check_color": { "r": 72, "g": 72, "b": 78, "a": 255 }
    \\}
    \\
    ;
}

test "built-in gray themes parse" {
    const dark = try parseThemeBytes(std.testing.allocator, grayDarkThemeJson());
    const light = try parseThemeBytes(std.testing.allocator, grayLightThemeJson());
    try std.testing.expect(dark.text_color.r > dark.panel_color.r);
    try std.testing.expect(light.text_color.r < light.panel_color.r);
    try std.testing.expectEqual(@as(u8, 132), dark.accent_color.r);
    try std.testing.expectEqual(@as(u8, 92), light.accent_color.r);
}

test "theme requires every editor color" {
    const err = parseThemeBytes(std.testing.allocator,
        \\{
        \\  "panel_color": { "r": 24, "g": 30, "b": 40, "a": 236 }
        \\}
    );
    try std.testing.expectError(error.MissingField, err);
}

test "refresh rate settings support capped choices and uncapped" {
    try validateRefreshRate(null);
    try validateRefreshRate(60);
    try validateRefreshRate(144);
    try std.testing.expectError(error.UnsupportedRefreshRate, validateRefreshRate(75));
    try std.testing.expectEqualStrings("Uncapped", refreshRateLabel(null));
    try std.testing.expectEqualStrings("60 Hz", refreshRateLabel(60));
}

test "terrain undo limit supports unlimited and bounded budgets" {
    try validateTerrainUndoLimitMb(0);
    try validateTerrainUndoLimitMb(1024);
    try std.testing.expectError(error.UnsupportedTerrainUndoLimit, validateTerrainUndoLimitMb(1024 * 1024 + 1));
    try std.testing.expectEqualStrings("Unlimited", terrainUndoLimitLabel(0));
    try std.testing.expectEqualStrings("1 GB", terrainUndoLimitLabel(1024));
}
