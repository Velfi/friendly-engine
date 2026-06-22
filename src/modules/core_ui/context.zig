const std = @import("std");
const core = @import("../../core/mod.zig");
const commands = @import("commands.zig");
const input = @import("input.zig");

pub const WidgetId = commands.WidgetId;
pub const RenderCommand = commands.RenderCommand;

pub const Rect = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,

    pub fn contains(self: Rect, point: core.math.Vec2f) bool {
        return point.x >= self.x and
            point.x <= self.x + self.w and
            point.y >= self.y and
            point.y <= self.y + self.h;
    }

    pub fn inset(self: Rect, amount: f32) Rect {
        return .{
            .x = self.x + amount,
            .y = self.y + amount,
            .w = @max(0.0, self.w - (amount * 2.0)),
            .h = @max(0.0, self.h - (amount * 2.0)),
        };
    }

    pub fn intersect(self: Rect, other: Rect) ?Rect {
        const x = @max(self.x, other.x);
        const y = @max(self.y, other.y);
        const right = @min(self.x + self.w, other.x + other.w);
        const bottom = @min(self.y + self.h, other.y + other.h);
        if (right <= x or bottom <= y) return null;
        return .{ .x = x, .y = y, .w = right - x, .h = bottom - y };
    }
};

pub const PanelDesc = struct {
    id: []const u8,
    rect: Rect,
    padding: f32 = 10.0,
    spacing: f32 = 6.0,
    inline_spacing: f32 = 5.0,
    row_height: f32 = 26.0,
};

pub const LayoutCursor = struct {
    panel_id: WidgetId,
    panel_rect: Rect,
    cursor_x: f32,
    cursor_y: f32,
    content_x: f32,
    content_w: f32,
    row_height: f32,
    spacing: f32,
    inline_spacing: f32,
    same_line: bool = false,
    same_line_y: f32 = 0.0,
    clip_rect: ?Rect = null,
    scroll_y: f32 = 0.0,
    scroll_viewport_bottom: f32 = 0.0,
    scroll_area_id: ?WidgetId = null,
    scroll_command_index: ?usize = null,
    scroll_content_top: f32 = 0.0,
    scroll_viewport_height: f32 = 0.0,
};

pub const PersistentState = union(enum) {
    boolean: bool,
    text: struct {
        buffer: []u8,
        cursor: usize,
    },
    float_value: f32,
    int_value: i32,
    scroll_offset: f32,
};

pub const UiContext = struct {
    allocator: std.mem.Allocator,
    frame_arena: std.heap.ArenaAllocator,
    persistent_arena: std.heap.ArenaAllocator,
    commands: std.ArrayList(RenderCommand),
    layout_stack: std.ArrayList(LayoutCursor),
    deferred_tooltips: std.ArrayList(commands.TooltipCommand),
    persistent: std.AutoHashMap(u64, PersistentState),
    input: input.InputState = .{},
    /// When w/h are zero, tooltip placement is not clamped to the window.
    frame_bounds: Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
    input_hook: ?input.InputHook = null,
    hot_widget: ?WidgetId = null,
    active_widget: ?WidgetId = null,
    focused_widget: ?WidgetId = null,
    drag_start_x: f32 = 0.0,
    drag_start_y: f32 = 0.0,
    frame_counter: u64 = 0,
    widget_serial: u64 = 0,
    id_prefix: std.ArrayList(u8),
    id_prefix_marks: std.ArrayList(usize),
    input_nodes: std.ArrayList(@import("input_tree.zig").Node),

    pub fn init(allocator: std.mem.Allocator) UiContext {
        return .{
            .allocator = allocator,
            .frame_arena = std.heap.ArenaAllocator.init(allocator),
            .persistent_arena = std.heap.ArenaAllocator.init(allocator),
            .commands = .empty,
            .layout_stack = .empty,
            .deferred_tooltips = .empty,
            .persistent = std.AutoHashMap(u64, PersistentState).init(allocator),
            .id_prefix = .empty,
            .id_prefix_marks = .empty,
            .input_nodes = .empty,
        };
    }

    pub fn deinit(self: *UiContext) void {
        self.layout_stack.deinit(self.allocator);
        self.commands.deinit(self.allocator);
        self.deferred_tooltips.deinit(self.allocator);
        self.id_prefix.deinit(self.allocator);
        self.id_prefix_marks.deinit(self.allocator);
        self.input_nodes.deinit(self.allocator);
        self.persistent.deinit();
        self.persistent_arena.deinit();
        self.frame_arena.deinit();
    }

    pub fn setInputHook(self: *UiContext, hook: input.InputHook) void {
        self.input_hook = hook;
    }

    pub fn setFrameBounds(self: *UiContext, bounds: Rect) void {
        self.frame_bounds = bounds;
    }

    pub fn beginFrame(self: *UiContext, frame_input: input.InputState) void {
        self.resetFrame();
        self.input = frame_input;
        self.frame_counter += 1;
    }

    pub fn beginFrameFromHook(self: *UiContext) !void {
        self.resetFrame();
        self.input = .{};
        const hook = self.input_hook orelse return;
        try hook.vtable.collect(hook.context, &self.input);
    }

    pub fn renderCommands(self: *const UiContext) []const RenderCommand {
        return self.commands.items;
    }

    pub fn stableId(self: *UiContext, explicit_id: ?[]const u8, fallback_label: []const u8) !WidgetId {
        if (explicit_id) |id| return core.ids.hashString64(id);
        var path = std.ArrayList(u8).empty;
        defer path.deinit(self.allocator);
        if (self.id_prefix.items.len > 0) {
            try path.appendSlice(self.allocator, self.id_prefix.items);
            try path.append(self.allocator, '/');
        }
        try path.appendSlice(self.allocator, fallback_label);
        return core.ids.hashString64(path.items);
    }

    pub fn nextCommandId(self: *UiContext, stable: WidgetId) WidgetId {
        const serial_mix = self.widget_serial *% 0x9e37_79b9_7f4a_7c15;
        self.widget_serial += 1;
        return stable ^ serial_mix;
    }

    pub fn dupeText(self: *UiContext, text: []const u8) ![]u8 {
        return self.frame_arena.allocator().dupe(u8, text);
    }

    pub fn dupeRichText(self: *UiContext, spans: []const commands.rich_text.Span) ![]commands.rich_text.Span {
        const owned = try self.frame_arena.allocator().alloc(commands.rich_text.Span, spans.len);
        for (spans, 0..) |span, index| {
            owned[index] = .{
                .text = try self.dupeText(span.text),
                .style = span.style,
            };
        }
        return owned;
    }

    pub fn pushCommand(self: *UiContext, command: RenderCommand) !void {
        try self.commands.append(self.allocator, command);
    }

    pub fn pushTooltip(self: *UiContext, command: commands.TooltipCommand) !void {
        try self.deferred_tooltips.append(self.allocator, command);
    }

    pub fn flushTooltips(self: *UiContext) !void {
        if (self.deferred_tooltips.items.len == 0) return;
        for (self.deferred_tooltips.items) |tip| {
            try self.pushCommand(.{ .tooltip = tip });
        }
        self.deferred_tooltips.clearRetainingCapacity();
    }

    pub fn beginPanel(self: *UiContext, desc: PanelDesc) !void {
        return @import("layout.zig").beginPanel(self, desc);
    }

    pub fn endPanel(self: *UiContext) void {
        @import("layout.zig").endPanel(self);
    }

    pub fn label(self: *UiContext, text: []const u8) !void {
        return @import("widgets_basic.zig").label(self, text);
    }

    pub fn richLabel(self: *UiContext, id: []const u8, spans: []const commands.rich_text.Span) !void {
        return @import("widgets_basic.zig").richLabel(self, id, spans);
    }

    pub fn button(self: *UiContext, label_text: []const u8) !@import("layout.zig").ButtonResult {
        return @import("widgets_basic.zig").button(self, label_text);
    }

    pub fn currentLayout(self: *UiContext) !*LayoutCursor {
        if (self.layout_stack.items.len == 0) return error.NoActivePanel;
        return &self.layout_stack.items[self.layout_stack.items.len - 1];
    }

    pub fn allocRowRect(self: *UiContext, width: f32, height: f32) !Rect {
        const cursor = try self.currentLayout();
        var row_w = width;
        if (cursor.same_line) {
            const remaining = cursor.content_x + cursor.content_w - cursor.cursor_x;
            row_w = @min(width, @max(0, remaining));
        }
        const rect = Rect{
            .x = cursor.cursor_x,
            .y = cursor.cursor_y - cursor.scroll_y,
            .w = row_w,
            .h = height,
        };
        if (!cursor.same_line) {
            cursor.cursor_y += height + cursor.spacing;
        } else {
            cursor.cursor_x += row_w + cursor.inline_spacing;
            cursor.cursor_y = cursor.same_line_y;
        }
        return rect;
    }

    pub fn allocFullWidthRow(self: *UiContext, height: f32) !Rect {
        const cursor = try self.currentLayout();
        return self.allocRowRect(cursor.content_w, height);
    }

    pub fn getBoolState(self: *UiContext, id: WidgetId, default_value: bool) !bool {
        const entry = self.persistent.get(id) orelse {
            try self.persistent.put(id, .{ .boolean = default_value });
            return default_value;
        };
        return switch (entry) {
            .boolean => |value| value,
            else => error.WidgetStateTypeMismatch,
        };
    }

    pub fn setBoolState(self: *UiContext, id: WidgetId, value: bool) !void {
        try self.persistent.put(id, .{ .boolean = value });
    }

    pub fn getFloatState(self: *UiContext, id: WidgetId, default_value: f32) !f32 {
        const entry = self.persistent.get(id) orelse {
            try self.persistent.put(id, .{ .float_value = default_value });
            return default_value;
        };
        return switch (entry) {
            .float_value => |value| value,
            else => error.WidgetStateTypeMismatch,
        };
    }

    pub fn setFloatState(self: *UiContext, id: WidgetId, value: f32) !void {
        try self.persistent.put(id, .{ .float_value = value });
    }

    pub fn getIntState(self: *UiContext, id: WidgetId, default_value: i32) !i32 {
        const entry = self.persistent.get(id) orelse {
            try self.persistent.put(id, .{ .int_value = default_value });
            return default_value;
        };
        return switch (entry) {
            .int_value => |value| value,
            else => error.WidgetStateTypeMismatch,
        };
    }

    pub fn setIntState(self: *UiContext, id: WidgetId, value: i32) !void {
        try self.persistent.put(id, .{ .int_value = value });
    }

    pub fn getScrollState(self: *UiContext, id: WidgetId) !f32 {
        const entry = self.persistent.get(id) orelse return 0.0;
        return switch (entry) {
            .scroll_offset => |value| value,
            else => error.WidgetStateTypeMismatch,
        };
    }

    pub fn setScrollState(self: *UiContext, id: WidgetId, value: f32) !void {
        try self.persistent.put(id, .{ .scroll_offset = value });
    }

    pub fn getTextState(self: *UiContext, id: WidgetId, default_text: []const u8) !struct { buffer: []u8, cursor: usize } {
        const gop = try self.persistent.getOrPut(id);
        if (!gop.found_existing) {
            const owned = try self.persistent_arena.allocator().dupe(u8, default_text);
            gop.value_ptr.* = .{ .text = .{ .buffer = owned, .cursor = owned.len } };
        }
        return switch (gop.value_ptr.*) {
            .text => |*text_state| .{
                .buffer = text_state.buffer,
                .cursor = text_state.cursor,
            },
            else => error.InvalidTextState,
        };
    }

    pub fn setTextCursor(self: *UiContext, id: WidgetId, cursor: usize) void {
        const entry = self.persistent.getPtr(id) orelse return;
        switch (entry.*) {
            .text => |*text_state| text_state.cursor = cursor,
            else => {},
        }
    }

    pub fn resetTextState(self: *UiContext, id: WidgetId, text: []const u8) !void {
        const owned = try self.persistent_arena.allocator().dupe(u8, text);
        try self.persistent.put(id, .{ .text = .{ .buffer = owned, .cursor = owned.len } });
    }

    pub fn appendTextChar(self: *UiContext, id: WidgetId, ch: u8) !void {
        const entry = self.persistent.getPtr(id) orelse return;
        switch (entry.*) {
            .text => |*text_state| {
                const new_len = text_state.buffer.len + 1;
                const new_buf = try self.persistent_arena.allocator().alloc(u8, new_len);
                @memcpy(new_buf[0..text_state.buffer.len], text_state.buffer);
                new_buf[text_state.buffer.len] = ch;
                text_state.buffer = new_buf;
                text_state.cursor = new_buf.len;
            },
            else => {},
        }
    }

    pub fn backspaceText(self: *UiContext, id: WidgetId) void {
        const entry = self.persistent.getPtr(id) orelse return;
        switch (entry.*) {
            .text => |*text_state| {
                if (text_state.cursor == 0) return;
                const new_len = text_state.buffer.len - 1;
                const cursor = text_state.cursor - 1;
                const new_buf = self.persistent_arena.allocator().alloc(u8, new_len) catch return;
                @memcpy(new_buf[0..cursor], text_state.buffer[0..cursor]);
                @memcpy(new_buf[cursor..new_len], text_state.buffer[cursor + 1 ..]);
                text_state.buffer = new_buf;
                text_state.cursor = cursor;
            },
            else => {},
        }
    }

    fn resetFrame(self: *UiContext) void {
        self.commands.clearRetainingCapacity();
        self.layout_stack.clearRetainingCapacity();
        self.deferred_tooltips.clearRetainingCapacity();
        @import("input_tree.zig").reset(self);
        self.hot_widget = null;
        self.widget_serial = 0;
        self.id_prefix.clearRetainingCapacity();
        self.id_prefix_marks.clearRetainingCapacity();
        self.frame_arena.deinit();
        self.frame_arena = std.heap.ArenaAllocator.init(self.allocator);
    }
};
