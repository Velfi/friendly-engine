const std = @import("std");
const friendly_engine = @import("friendly_engine");
const editor_draw = @import("editor_draw.zig");

const core_ui = friendly_engine.modules.core_ui;
const log = std.log.scoped(.editor_input);

const gamepad_axis_deadzone: f32 = 0.24;

pub const KeyEvent = struct {
    key: editor_draw.SDL_Keycode,
    mod: u16,
    down: bool,
    repeat: bool,
};

pub const Accumulator = struct {
    allocator: std.mem.Allocator,
    input: core_ui.InputState = .{},
    text_buffer: std.ArrayList(u8) = .empty,
    key_events: std.ArrayList(KeyEvent) = .empty,
    gamepads: std.AutoHashMap(i32, *editor_draw.SDL_Gamepad),
    gamepad_scroll_x: f32 = 0.0,
    gamepad_scroll_y: f32 = 0.0,
    dpad_left: bool = false,
    dpad_right: bool = false,
    dpad_up: bool = false,
    dpad_down: bool = false,
    quit_requested: bool = false,

    pub fn init(allocator: std.mem.Allocator) Accumulator {
        return .{
            .allocator = allocator,
            .key_events = .empty,
            .gamepads = std.AutoHashMap(i32, *editor_draw.SDL_Gamepad).init(allocator),
        };
    }

    pub fn deinit(self: *Accumulator) void {
        var gamepad_iter = self.gamepads.iterator();
        while (gamepad_iter.next()) |entry| editor_draw.SDL_CloseGamepad(entry.value_ptr.*);
        self.gamepads.deinit();
        self.text_buffer.deinit(self.allocator);
        self.key_events.deinit(self.allocator);
    }

    pub fn beginFrame(self: *Accumulator) void {
        self.input.primary_pressed = false;
        self.input.primary_released = false;
        self.input.primary_click_count = 0;
        self.input.middle_pressed = false;
        self.input.middle_released = false;
        self.input.right_button_pressed = false;
        self.input.right_button_released = false;
        self.input.scroll_delta_x = 0.0;
        self.input.scroll_delta_y = 0.0;
        self.input.scroll_is_precise = false;
        self.input.scroll_direction_flipped = false;
        self.input.navigation_scroll_x = 0.0;
        self.input.navigation_scroll_y = 0.0;
        self.input.motion_delta_x = 0.0;
        self.input.motion_delta_y = 0.0;
        self.input.key_chars = "";
        self.input.backspace_pressed = false;
        self.input.enter_pressed = false;
        self.input.tab_pressed = false;
        self.input.escape_pressed = false;
        self.input.left_pressed = false;
        self.input.right_pressed = false;
        self.input.up_pressed = false;
        self.input.down_pressed = false;
        self.text_buffer.clearRetainingCapacity();
        self.key_events.clearRetainingCapacity();
        self.quit_requested = false;
    }

    pub fn feedEvent(self: *Accumulator, event: *const editor_draw.SDL_Event) !void {
        switch (event.type) {
            editor_draw.SDL_QUIT => self.quit_requested = true,
            editor_draw.SDL_EVENT_MOUSE_MOTION => {
                self.input.mouse_position = .{ .x = event.motion.x, .y = event.motion.y };
                self.input.motion_delta_x += event.motion.xrel;
                self.input.motion_delta_y += event.motion.yrel;
            },
            editor_draw.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                self.input.mouse_position = .{ .x = event.button.x, .y = event.button.y };
                switch (event.button.button) {
                    editor_draw.SDL_BUTTON_LEFT => {
                        self.input.primary_down = true;
                        self.input.primary_pressed = true;
                        self.input.primary_click_count = event.button.clicks;
                    },
                    editor_draw.SDL_BUTTON_MIDDLE => {
                        self.input.middle_down = true;
                        self.input.middle_pressed = true;
                    },
                    editor_draw.SDL_BUTTON_RIGHT => {
                        self.input.right_button_down = true;
                        self.input.right_button_pressed = true;
                    },
                    else => {},
                }
            },
            editor_draw.SDL_EVENT_MOUSE_BUTTON_UP => {
                self.input.mouse_position = .{ .x = event.button.x, .y = event.button.y };
                switch (event.button.button) {
                    editor_draw.SDL_BUTTON_LEFT => {
                        self.input.primary_down = false;
                        self.input.primary_released = true;
                        self.input.primary_click_count = event.button.clicks;
                    },
                    editor_draw.SDL_BUTTON_MIDDLE => {
                        self.input.middle_down = false;
                        self.input.middle_released = true;
                    },
                    editor_draw.SDL_BUTTON_RIGHT => {
                        self.input.right_button_down = false;
                        self.input.right_button_released = true;
                    },
                    else => {},
                }
            },
            editor_draw.SDL_EVENT_MOUSE_WHEEL => {
                self.input.mouse_position = .{ .x = event.wheel.mouse_x, .y = event.wheel.mouse_y };
                self.input.scroll_delta_x += event.wheel.x;
                self.input.scroll_delta_y += event.wheel.y;
                self.input.scroll_direction_flipped = self.input.scroll_direction_flipped or
                    event.wheel.direction == editor_draw.SDL_MOUSEWHEEL_FLIPPED;
                self.input.scroll_is_precise = self.input.scroll_is_precise or
                    preciseWheelAxis(event.wheel.x, event.wheel.integer_x) or
                    preciseWheelAxis(event.wheel.y, event.wheel.integer_y);
            },
            editor_draw.SDL_EVENT_TEXT_INPUT => {
                try self.text_buffer.appendSlice(self.allocator, std.mem.span(event.text.text));
                self.input.key_chars = self.text_buffer.items;
            },
            editor_draw.SDL_EVENT_KEY_DOWN => {
                applyModifiers(&self.input, event.key.mod);
                try self.key_events.append(self.allocator, .{
                    .key = event.key.key,
                    .mod = event.key.mod,
                    .down = event.key.down,
                    .repeat = event.key.repeat,
                });
                if (event.key.down and !event.key.repeat) {
                    applyKeyPress(&self.input, event.key.key);
                }
            },
            editor_draw.SDL_EVENT_KEY_UP => {
                applyModifiers(&self.input, event.key.mod);
                try self.key_events.append(self.allocator, .{
                    .key = event.key.key,
                    .mod = event.key.mod,
                    .down = false,
                    .repeat = false,
                });
            },
            editor_draw.SDL_EVENT_GAMEPAD_ADDED => {
                const device_id: i32 = @intCast(event.gdevice.which);
                if (!self.gamepads.contains(device_id)) {
                    const gamepad = editor_draw.SDL_OpenGamepad(@intCast(device_id)) orelse {
                        log.err("SDL gamepad open failed id={} err={s}", .{ device_id, std.mem.span(editor_draw.SDL_GetError()) });
                        return error.SdlGamepadOpenFailed;
                    };
                    try self.gamepads.put(device_id, gamepad);
                }
            },
            editor_draw.SDL_EVENT_GAMEPAD_REMOVED => {
                const device_id: i32 = @intCast(event.gdevice.which);
                if (self.gamepads.fetchRemove(device_id)) |removed| editor_draw.SDL_CloseGamepad(removed.value);
                self.gamepad_scroll_x = 0.0;
                self.gamepad_scroll_y = 0.0;
                self.dpad_left = false;
                self.dpad_right = false;
                self.dpad_up = false;
                self.dpad_down = false;
            },
            editor_draw.SDL_EVENT_GAMEPAD_AXIS_MOTION => {
                const axis = event.gaxis.axis;
                const value = applyGamepadDeadzone(normalizeGamepadAxis(event.gaxis.value));
                if (axis == @as(u8, @intCast(editor_draw.SDL_GAMEPAD_AXIS_RIGHTX))) {
                    self.gamepad_scroll_x = value;
                } else if (axis == @as(u8, @intCast(editor_draw.SDL_GAMEPAD_AXIS_RIGHTY))) {
                    self.gamepad_scroll_y = -value;
                }
            },
            editor_draw.SDL_EVENT_GAMEPAD_BUTTON_DOWN, editor_draw.SDL_EVENT_GAMEPAD_BUTTON_UP => {
                const down = event.type == editor_draw.SDL_EVENT_GAMEPAD_BUTTON_DOWN and event.gbutton.down;
                applyGamepadButton(&self.input, &self.dpad_left, &self.dpad_right, &self.dpad_up, &self.dpad_down, event.gbutton.button, down);
            },
            else => {},
        }
    }

    pub fn snapshot(self: *Accumulator) core_ui.InputState {
        var input = self.input;
        input.key_chars = self.text_buffer.items;
        input.navigation_scroll_x += self.gamepad_scroll_x + digitalAxis(self.dpad_right, self.dpad_left);
        input.navigation_scroll_y += self.gamepad_scroll_y + digitalAxis(self.dpad_up, self.dpad_down);
        return input;
    }
};

fn applyGamepadButton(
    input: *core_ui.InputState,
    dpad_left: *bool,
    dpad_right: *bool,
    dpad_up: *bool,
    dpad_down: *bool,
    button: u8,
    down: bool,
) void {
    if (button == @as(u8, @intCast(editor_draw.SDL_GAMEPAD_BUTTON_DPAD_LEFT))) {
        dpad_left.* = down;
        if (down) input.left_pressed = true;
    } else if (button == @as(u8, @intCast(editor_draw.SDL_GAMEPAD_BUTTON_DPAD_RIGHT))) {
        dpad_right.* = down;
        if (down) input.right_pressed = true;
    } else if (button == @as(u8, @intCast(editor_draw.SDL_GAMEPAD_BUTTON_DPAD_UP))) {
        dpad_up.* = down;
        if (down) input.up_pressed = true;
    } else if (button == @as(u8, @intCast(editor_draw.SDL_GAMEPAD_BUTTON_DPAD_DOWN))) {
        dpad_down.* = down;
        if (down) input.down_pressed = true;
    }
}

fn digitalAxis(positive: bool, negative: bool) f32 {
    if (positive == negative) return 0.0;
    return if (positive) 1.0 else -1.0;
}

fn normalizeGamepadAxis(value: i16) f32 {
    if (value < 0) return @as(f32, @floatFromInt(value)) / 32768.0;
    return @as(f32, @floatFromInt(value)) / 32767.0;
}

fn applyGamepadDeadzone(value: f32) f32 {
    const magnitude = @abs(value);
    if (magnitude <= gamepad_axis_deadzone) return 0.0;
    return std.math.sign(value) * ((magnitude - gamepad_axis_deadzone) / (1.0 - gamepad_axis_deadzone));
}

fn applyKeyPress(input: *core_ui.InputState, key: editor_draw.SDL_Keycode) void {
    switch (key) {
        editor_draw.SDLK_BACKSPACE => input.backspace_pressed = true,
        editor_draw.SDLK_RETURN => input.enter_pressed = true,
        editor_draw.SDLK_TAB => input.tab_pressed = true,
        editor_draw.SDLK_ESCAPE => input.escape_pressed = true,
        editor_draw.SDLK_LEFT => input.left_pressed = true,
        editor_draw.SDLK_RIGHT => input.right_pressed = true,
        editor_draw.SDLK_UP => input.up_pressed = true,
        editor_draw.SDLK_DOWN => input.down_pressed = true,
        else => {},
    }
}

fn preciseWheelAxis(value: f32, integer_value: i32) bool {
    if (value == 0.0) return false;
    return @abs(value - @as(f32, @floatFromInt(integer_value))) > 0.001;
}

fn applyModifiers(input: *core_ui.InputState, mods: c_int) void {
    input.keyboard_mods = @intCast(mods);
    input.shift_down = (mods & editor_draw.SDL_KMOD_SHIFT) != 0;
    input.ctrl_down = (mods & editor_draw.SDL_KMOD_CTRL) != 0 or
        (mods & editor_draw.SDL_KMOD_GUI) != 0;
}

test "accumulator captures click count" {
    var acc = Accumulator.init(std.testing.allocator);
    defer acc.deinit();

    acc.input.primary_click_count = 2;
    const snap = acc.snapshot();
    try std.testing.expectEqual(@as(u8, 2), snap.primary_click_count);

    acc.beginFrame();
    try std.testing.expectEqual(@as(u8, 0), acc.snapshot().primary_click_count);
}

test "accumulator reads SDL3 wheel axes and precision fields" {
    var acc = Accumulator.init(std.testing.allocator);
    defer acc.deinit();

    try acc.feedEvent(&.{
        .wheel = .{
            .type = editor_draw.SDL_EVENT_MOUSE_WHEEL,
            .reserved = 0,
            .timestamp = 0,
            .windowID = 1,
            .which = 0,
            .x = 0.25,
            .y = -1.5,
            .direction = editor_draw.SDL_MOUSEWHEEL_FLIPPED,
            .mouse_x = 40.0,
            .mouse_y = 50.0,
            .integer_x = 0,
            .integer_y = -1,
        },
    });

    const snap = acc.snapshot();
    try std.testing.expectEqual(@as(f32, 0.25), snap.scroll_delta_x);
    try std.testing.expectEqual(@as(f32, -1.5), snap.scroll_delta_y);
    try std.testing.expect(snap.scroll_is_precise);
    try std.testing.expect(snap.scroll_direction_flipped);
}

test "accumulator updates pointer position from wheel events" {
    var acc = Accumulator.init(std.testing.allocator);
    defer acc.deinit();

    acc.input.mouse_position = .{ .x = 12.0, .y = 16.0 };

    try acc.feedEvent(&.{
        .wheel = .{
            .type = editor_draw.SDL_EVENT_MOUSE_WHEEL,
            .reserved = 0,
            .timestamp = 0,
            .windowID = 1,
            .which = 0,
            .x = 0.0,
            .y = -2.0,
            .direction = editor_draw.SDL_MOUSEWHEEL_NORMAL,
            .mouse_x = 268.0,
            .mouse_y = 54.0,
            .integer_x = 0,
            .integer_y = -2,
        },
    });

    const snap = acc.snapshot();
    try std.testing.expectEqual(@as(f32, 268.0), snap.mouse_position.x);
    try std.testing.expectEqual(@as(f32, 54.0), snap.mouse_position.y);
}

test "accumulator maps right stick to navigation scroll" {
    var acc = Accumulator.init(std.testing.allocator);
    defer acc.deinit();

    try acc.feedEvent(&.{
        .gaxis = .{
            .type = editor_draw.SDL_EVENT_GAMEPAD_AXIS_MOTION,
            .reserved = 0,
            .timestamp = 0,
            .which = 1,
            .axis = @intCast(editor_draw.SDL_GAMEPAD_AXIS_RIGHTY),
            .padding1 = 0,
            .padding2 = 0,
            .padding3 = 0,
            .value = 32767,
            .padding4 = 0,
        },
    });

    const snap = acc.snapshot();
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), snap.navigation_scroll_y, 0.001);

    acc.beginFrame();
    const held_snap = acc.snapshot();
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), held_snap.navigation_scroll_y, 0.001);
}

test "accumulator maps held dpad to navigation scroll" {
    var acc = Accumulator.init(std.testing.allocator);
    defer acc.deinit();

    try acc.feedEvent(&.{
        .gbutton = .{
            .type = editor_draw.SDL_EVENT_GAMEPAD_BUTTON_DOWN,
            .reserved = 0,
            .timestamp = 0,
            .which = 1,
            .button = @intCast(editor_draw.SDL_GAMEPAD_BUTTON_DPAD_DOWN),
            .down = true,
            .padding1 = 0,
            .padding2 = 0,
        },
    });

    var snap = acc.snapshot();
    try std.testing.expect(snap.down_pressed);
    try std.testing.expectEqual(@as(f32, -1.0), snap.navigation_scroll_y);

    acc.beginFrame();
    snap = acc.snapshot();
    try std.testing.expect(!snap.down_pressed);
    try std.testing.expectEqual(@as(f32, -1.0), snap.navigation_scroll_y);

    try acc.feedEvent(&.{
        .gbutton = .{
            .type = editor_draw.SDL_EVENT_GAMEPAD_BUTTON_UP,
            .reserved = 0,
            .timestamp = 0,
            .which = 1,
            .button = @intCast(editor_draw.SDL_GAMEPAD_BUTTON_DPAD_DOWN),
            .down = false,
            .padding1 = 0,
            .padding2 = 0,
        },
    });
    snap = acc.snapshot();
    try std.testing.expectEqual(@as(f32, 0.0), snap.navigation_scroll_y);
}
