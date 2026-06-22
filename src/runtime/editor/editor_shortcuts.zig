const builtin = @import("builtin");
const editor_draw = @import("editor_draw.zig");

pub fn shortcutModifierPressed(mod: u16) bool {
    if (builtin.os.tag == .macos) {
        return (mod & editor_draw.SDL_KMOD_GUI) != 0;
    }
    return (mod & editor_draw.SDL_KMOD_CTRL) != 0;
}

pub fn commandPaletteShortcutLabel() []const u8 {
    if (builtin.os.tag == .macos) return "\u{2318}P";
    return "Ctrl+P";
}
