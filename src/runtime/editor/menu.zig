pub const FeMenuAction = enum(c_int) {
    none = 0,
    new_project = 1,
    import_project = 2,
    open_project = 3,
    quit = 4,
    about = 5,
    remove_from_list = 6,
    manage_presets = 7,
};

pub extern fn fe_menubar_install() void;
pub extern fn fe_menubar_poll_action(out_action: *c_int) bool;

pub const WindowMenuId = enum {
    none,
    file,
    help,
};

pub const WindowMenuItem = struct {
    label: []const u8,
    action: FeMenuAction,
};

pub fn windowMenuItems(menu: WindowMenuId) []const WindowMenuItem {
    return switch (menu) {
        .none => &.{},
        .file => &.{
            .{ .label = "New Project...", .action = .new_project },
            .{ .label = "Presets...", .action = .manage_presets },
            .{ .label = "Import Project...", .action = .import_project },
            .{ .label = "Open Project", .action = .open_project },
            .{ .label = "Remove from List", .action = .remove_from_list },
            .{ .label = "Quit", .action = .quit },
        },
        .help => &.{
            .{ .label = "About friendly-engine editor", .action = .about },
        },
    };
}
