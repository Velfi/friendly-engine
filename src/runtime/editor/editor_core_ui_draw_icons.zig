const std = @import("std");
const editor_draw = @import("editor_draw.zig");
const draw_primitives = @import("editor_draw_primitives.zig");

pub fn iconoirSvg(icon: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, icon, "undo")) return @embedFile("icons/iconoir/undo.svg");
    if (std.mem.eql(u8, icon, "redo")) return @embedFile("icons/iconoir/redo.svg");
    if (std.mem.eql(u8, icon, "save")) return @embedFile("icons/iconoir/floppy-disk.svg");
    if (std.mem.eql(u8, icon, "play")) return @embedFile("icons/iconoir/play.svg");
    if (std.mem.eql(u8, icon, "music-note")) return @embedFile("icons/iconoir/music-note.svg");
    if (std.mem.eql(u8, icon, "build")) return @embedFile("icons/iconoir/hammer.svg");
    if (std.mem.eql(u8, icon, "settings")) return @embedFile("icons/iconoir/settings.svg");
    if (std.mem.eql(u8, icon, "close")) return @embedFile("icons/iconoir/xmark.svg");
    if (std.mem.eql(u8, icon, "delete")) return @embedFile("icons/iconoir/trash.svg");
    if (std.mem.eql(u8, icon, "trash")) return @embedFile("icons/iconoir/trash.svg");
    if (std.mem.eql(u8, icon, "select")) return @embedFile("icons/iconoir/selective-tool.svg");
    if (std.mem.eql(u8, icon, "selective-tool")) return @embedFile("icons/iconoir/selective-tool.svg");
    if (std.mem.eql(u8, icon, "cursor")) return @embedFile("icons/iconoir/cursor-pointer.svg");
    if (std.mem.eql(u8, icon, "cursor-pointer")) return @embedFile("icons/iconoir/cursor-pointer.svg");
    if (std.mem.eql(u8, icon, "move")) return @embedFile("icons/iconoir/drag-hand-gesture.svg");
    if (std.mem.eql(u8, icon, "rotate")) return @embedFile("icons/iconoir/rotate-camera-right.svg");
    if (std.mem.eql(u8, icon, "rotate-camera-right")) return @embedFile("icons/iconoir/rotate-camera-right.svg");
    if (std.mem.eql(u8, icon, "scale")) return @embedFile("icons/iconoir/scale-frame-enlarge.svg");
    if (std.mem.eql(u8, icon, "frame")) return @embedFile("icons/iconoir/frame-select.svg");
    if (std.mem.eql(u8, icon, "duplicate")) return @embedFile("icons/iconoir/copy.svg");
    if (std.mem.eql(u8, icon, "copy")) return @embedFile("icons/iconoir/copy.svg");
    if (std.mem.eql(u8, icon, "grid")) return @embedFile("icons/iconoir/view-grid.svg");
    if (std.mem.eql(u8, icon, "view-grid")) return @embedFile("icons/iconoir/view-grid.svg");
    if (std.mem.eql(u8, icon, "snap")) return @embedFile("icons/iconoir/magnet.svg");
    if (std.mem.eql(u8, icon, "magnet")) return @embedFile("icons/iconoir/magnet.svg");
    if (std.mem.eql(u8, icon, "gizmo")) return @embedFile("icons/iconoir/box-3d-center.svg");
    if (std.mem.eql(u8, icon, "box")) return @embedFile("icons/iconoir/cube.svg");
    if (std.mem.eql(u8, icon, "mesh")) return @embedFile("icons/iconoir/cube-dots.svg");
    if (std.mem.eql(u8, icon, "cube-scan")) return @embedFile("icons/iconoir/cube-scan.svg");
    if (std.mem.eql(u8, icon, "world")) return @embedFile("icons/iconoir/planet.svg");
    if (std.mem.eql(u8, icon, "pivot")) return @embedFile("icons/iconoir/box-3d-point.svg");
    if (std.mem.eql(u8, icon, "eye")) return @embedFile("icons/iconoir/eye.svg");
    if (std.mem.eql(u8, icon, "eye-closed")) return @embedFile("icons/iconoir/eye-closed.svg");
    if (std.mem.eql(u8, icon, "lock")) return @embedFile("icons/iconoir/lock.svg");
    if (std.mem.eql(u8, icon, "lock-slash")) return @embedFile("icons/iconoir/lock-slash.svg");
    if (std.mem.eql(u8, icon, "scene")) return @embedFile("icons/iconoir/list-select.svg");
    if (std.mem.eql(u8, icon, "list-select")) return @embedFile("icons/iconoir/list-select.svg");
    if (std.mem.eql(u8, icon, "assets")) return @embedFile("icons/iconoir/folder.svg");
    if (std.mem.eql(u8, icon, "package")) return @embedFile("icons/iconoir/package.svg");
    if (std.mem.eql(u8, icon, "add")) return @embedFile("icons/iconoir/plus.svg");
    if (std.mem.eql(u8, icon, "plus")) return @embedFile("icons/iconoir/plus.svg");
    if (std.mem.eql(u8, icon, "minus")) return @embedFile("icons/iconoir/minus.svg");
    if (std.mem.eql(u8, icon, "search")) return @embedFile("icons/iconoir/search.svg");
    if (std.mem.eql(u8, icon, "material")) return @embedFile("icons/iconoir/color-wheel.svg");
    if (std.mem.eql(u8, icon, "fill-color")) return @embedFile("icons/iconoir/fill-color.svg");
    if (std.mem.eql(u8, icon, "component")) return @embedFile("icons/iconoir/component.svg");
    if (std.mem.eql(u8, icon, "dots-grid-3x3")) return @embedFile("icons/iconoir/dots-grid-3x3.svg");
    if (std.mem.eql(u8, icon, "physics")) return @embedFile("icons/iconoir/ruler.svg");
    if (std.mem.eql(u8, icon, "select-point-3d")) return @embedFile("icons/iconoir/select-point-3d.svg");
    if (std.mem.eql(u8, icon, "select-edge-3d")) return @embedFile("icons/iconoir/select-edge-3d.svg");
    if (std.mem.eql(u8, icon, "select-face-3d")) return @embedFile("icons/iconoir/select-face-3d.svg");
    if (std.mem.eql(u8, icon, "perspective")) return @embedFile("icons/iconoir/perspective-view.svg");
    if (std.mem.eql(u8, icon, "orthographic")) return @embedFile("icons/iconoir/orthogonal-view.svg");
    if (std.mem.eql(u8, icon, "chevron-down")) return @embedFile("icons/iconoir/nav-arrow-down.svg");
    if (std.mem.eql(u8, icon, "chevron-right")) return @embedFile("icons/iconoir/nav-arrow-right.svg");
    return null;
}

pub fn drawIconoirSvg(renderer: *editor_draw.SDL_Renderer, svg: []const u8, left: f32, top: f32, scale: f32, color: editor_draw.Color) !void {
    var search_index: usize = 0;
    while (std.mem.indexOfPos(u8, svg, search_index, " d=\"")) |attr_start| {
        const d_start = attr_start + 4;
        const d_end = std.mem.indexOfScalarPos(u8, svg, d_start, '"') orelse return error.InvalidIconSvg;
        try drawSvgPath(renderer, svg[d_start..d_end], left, top, scale, color);
        search_index = d_end + 1;
    }
}

pub fn drawSvgPath(renderer: *editor_draw.SDL_Renderer, path: []const u8, left: f32, top: f32, scale: f32, color: editor_draw.Color) !void {
    var parser = SvgPathParser{ .path = path };
    var command: u8 = 0;
    var cursor = SvgPoint{ .x = 0, .y = 0 };
    var start = cursor;
    while (parser.nextCommandOrNumberStart(&command)) {
        switch (command) {
            'M' => {
                cursor = try parser.readPoint();
                start = cursor;
                while (parser.hasNumberAhead()) {
                    const next = try parser.readPoint();
                    try svgLine(renderer, left, top, scale, cursor, next, color);
                    cursor = next;
                }
            },
            'L' => {
                while (parser.hasNumberAhead()) {
                    const next = try parser.readPoint();
                    try svgLine(renderer, left, top, scale, cursor, next, color);
                    cursor = next;
                }
            },
            'H' => {
                while (parser.hasNumberAhead()) {
                    const next = SvgPoint{ .x = try parser.readNumber(), .y = cursor.y };
                    try svgLine(renderer, left, top, scale, cursor, next, color);
                    cursor = next;
                }
            },
            'V' => {
                while (parser.hasNumberAhead()) {
                    const next = SvgPoint{ .x = cursor.x, .y = try parser.readNumber() };
                    try svgLine(renderer, left, top, scale, cursor, next, color);
                    cursor = next;
                }
            },
            'C' => {
                while (parser.hasNumberAhead()) {
                    const c1 = try parser.readPoint();
                    const c2 = try parser.readPoint();
                    const end = try parser.readPoint();
                    try svgCubic(renderer, left, top, scale, cursor, c1, c2, end, color);
                    cursor = end;
                }
            },
            'Z' => {
                try svgLine(renderer, left, top, scale, cursor, start, color);
                cursor = start;
            },
            else => return error.UnsupportedIconSvgCommand,
        }
    }
}

const SvgPoint = struct { x: f32, y: f32 };

const SvgPathParser = struct {
    path: []const u8,
    index: usize = 0,

    fn nextCommandOrNumberStart(self: *SvgPathParser, command: *u8) bool {
        self.skipSeparators();
        if (self.index >= self.path.len) return false;
        const ch = self.path[self.index];
        if (isCommand(ch)) {
            command.* = ch;
            self.index += 1;
        }
        return true;
    }

    fn hasNumberAhead(self: *SvgPathParser) bool {
        self.skipSeparators();
        if (self.index >= self.path.len) return false;
        return !isCommand(self.path[self.index]);
    }

    fn readPoint(self: *SvgPathParser) !SvgPoint {
        return .{ .x = try self.readNumber(), .y = try self.readNumber() };
    }

    fn readNumber(self: *SvgPathParser) !f32 {
        self.skipSeparators();
        const start = self.index;
        if (self.index < self.path.len and (self.path[self.index] == '-' or self.path[self.index] == '+')) self.index += 1;
        while (self.index < self.path.len and isNumberChar(self.path[self.index])) self.index += 1;
        if (start == self.index) return error.InvalidIconSvg;
        return std.fmt.parseFloat(f32, self.path[start..self.index]);
    }

    fn skipSeparators(self: *SvgPathParser) void {
        while (self.index < self.path.len) : (self.index += 1) {
            const ch = self.path[self.index];
            if (ch != ' ' and ch != '\n' and ch != '\t' and ch != '\r' and ch != ',') break;
        }
    }
};

pub fn isCommand(ch: u8) bool {
    return ch == 'M' or ch == 'L' or ch == 'H' or ch == 'V' or ch == 'C' or ch == 'Z';
}

pub fn isNumberChar(ch: u8) bool {
    return (ch >= '0' and ch <= '9') or ch == '.';
}

pub fn svgLine(renderer: *editor_draw.SDL_Renderer, left: f32, top: f32, scale: f32, a: SvgPoint, b: SvgPoint, color: editor_draw.Color) !void {
    try draw_primitives.line(
        renderer,
        left + a.x * scale,
        top + a.y * scale,
        left + b.x * scale,
        top + b.y * scale,
        1.25,
        color,
    );
}

pub fn svgCubic(renderer: *editor_draw.SDL_Renderer, left: f32, top: f32, scale: f32, p0: SvgPoint, c1: SvgPoint, c2: SvgPoint, p3: SvgPoint, color: editor_draw.Color) !void {
    var prev = p0;
    var i: usize = 1;
    while (i <= 10) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / 10.0;
        const next = cubicPoint(p0, c1, c2, p3, t);
        try svgLine(renderer, left, top, scale, prev, next, color);
        prev = next;
    }
}

pub fn cubicPoint(p0: SvgPoint, c1: SvgPoint, c2: SvgPoint, p3: SvgPoint, t: f32) SvgPoint {
    const mt = 1.0 - t;
    const a = mt * mt * mt;
    const b = 3.0 * mt * mt * t;
    const c = 3.0 * mt * t * t;
    const d = t * t * t;
    return .{
        .x = p0.x * a + c1.x * b + c2.x * c + p3.x * d,
        .y = p0.y * a + c1.y * b + c2.y * c + p3.y * d,
    };
}
