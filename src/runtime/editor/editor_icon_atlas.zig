const std = @import("std");
const shared = @import("runtime_shared");
const draw_icons = @import("editor_core_ui_draw_icons.zig");

const c = @cImport({
    @cInclude("fe_plutosvg_bridge.h");
});

pub const Slot = struct {
    u0: f32,
    v0: f32,
    u1: f32,
    v1: f32,
};

pub const IconAtlas = struct {
    allocator: std.mem.Allocator,
    width: u32,
    height: u32,
    pixels: []u8,
    slots: std.StringHashMap(Slot),
    next_slot: u32 = 0,
    dirty: bool = true,

    pub fn init(allocator: std.mem.Allocator) !IconAtlas {
        const pixel_count = atlas_size * atlas_size * 4;
        const pixels = try allocator.alloc(u8, pixel_count);
        @memset(pixels, 0);
        return .{
            .allocator = allocator,
            .width = atlas_size,
            .height = atlas_size,
            .pixels = pixels,
            .slots = std.StringHashMap(Slot).init(allocator),
        };
    }

    pub fn deinit(self: *IconAtlas) void {
        var keys = self.slots.keyIterator();
        while (keys.next()) |key| {
            self.allocator.free(key.*);
        }
        self.slots.deinit();
        self.allocator.free(self.pixels);
    }

    pub fn getOrCreate(self: *IconAtlas, icon: []const u8) !Slot {
        if (self.slots.get(icon)) |slot| return slot;
        const slot = try self.allocSlot();
        self.clearSlot(slot);
        if (draw_icons.iconoirSvg(icon)) |svg| {
            try self.rasterizeSvg(slot, svg);
        } else {
            return error.UnknownEditorIcon;
        }
        const owned_icon = try self.allocator.dupe(u8, icon);
        errdefer self.allocator.free(owned_icon);
        try self.slots.put(owned_icon, slot);
        self.dirty = true;
        return slot;
    }

    pub fn markClean(self: *IconAtlas) void {
        self.dirty = false;
    }

    fn allocSlot(self: *IconAtlas) !Slot {
        const slots_per_row = self.width / slot_size;
        const max_slots = slots_per_row * (self.height / slot_size);
        if (self.next_slot >= max_slots) return error.IconAtlasFull;
        const index = self.next_slot;
        self.next_slot += 1;
        const x = (index % slots_per_row) * slot_size;
        const y = (index / slots_per_row) * slot_size;
        const fw: f32 = @floatFromInt(self.width);
        const fh: f32 = @floatFromInt(self.height);
        const half_texel_u: f32 = 0.5 / fw;
        const half_texel_v: f32 = 0.5 / fh;
        const px: f32 = @floatFromInt(x);
        const py: f32 = @floatFromInt(y);
        const slot_end: f32 = @floatFromInt(x + slot_size);
        const slot_bottom: f32 = @floatFromInt(y + slot_size);
        return .{
            .u0 = px / fw + half_texel_u,
            .v0 = py / fh + half_texel_v,
            .u1 = slot_end / fw - half_texel_u,
            .v1 = slot_bottom / fh - half_texel_v,
        };
    }

    fn clearSlot(self: *IconAtlas, slot: Slot) void {
        const rect = self.slotPixels(slot);
        var y: u32 = 0;
        while (y < slot_size) : (y += 1) {
            var x: u32 = 0;
            while (x < slot_size) : (x += 1) {
                self.writePixel(rect.x + x, rect.y + y, 0);
            }
        }
    }

    fn rasterizeSvg(self: *IconAtlas, slot: Slot, svg: []const u8) !void {
        const rect = self.slotPixels(slot);
        var rendered: [slot_size * slot_size * 4]u8 = undefined;
        const result = c.fe_svg_render_rgba(
            svg.ptr,
            @intCast(svg.len),
            slot_size,
            slot_size,
            &rendered,
            rendered.len,
        );
        if (result != 0) return error.InvalidIconSvg;

        var y: u32 = 0;
        while (y < slot_size) : (y += 1) {
            var x: u32 = 0;
            while (x < slot_size) : (x += 1) {
                const src = (@as(usize, y) * slot_size + x) * 4;
                const dst = (@as(usize, rect.y + y) * self.width + rect.x + x) * 4;
                self.pixels[dst] = rendered[src];
                self.pixels[dst + 1] = rendered[src + 1];
                self.pixels[dst + 2] = rendered[src + 2];
                self.pixels[dst + 3] = rendered[src + 3];
            }
        }
    }

    fn writePixel(self: *IconAtlas, x: u32, y: u32, alpha: u8) void {
        const idx = (@as(usize, y) * self.width + x) * 4;
        self.pixels[idx] = 0;
        self.pixels[idx + 1] = 0;
        self.pixels[idx + 2] = 0;
        self.pixels[idx + 3] = alpha;
    }

    fn slotPixels(self: *const IconAtlas, slot: Slot) struct { x: u32, y: u32 } {
        return .{
            .x = @intFromFloat(slot.u0 * @as(f32, @floatFromInt(self.width))),
            .y = @intFromFloat(slot.v0 * @as(f32, @floatFromInt(self.height))),
        };
    }
};

const atlas_size: u32 = 1024;
const slot_size: u32 = 32;

test "icon atlas rasterizes embedded svg" {
    var atlas = try IconAtlas.init(std.testing.allocator);
    defer atlas.deinit();
    _ = try atlas.getOrCreate("save");
    var alpha_count: usize = 0;
    for (0..atlas.pixels.len / 4) |i| {
        if (atlas.pixels[i * 4 + 3] != 0) alpha_count += 1;
    }
    try std.testing.expect(alpha_count > 0);
    try std.testing.expect(alpha_count < slot_size * slot_size);
}

test "icon atlas preserves transparent SVG background" {
    var atlas = try IconAtlas.init(std.testing.allocator);
    defer atlas.deinit();
    const slot = try atlas.getOrCreate("gizmo");
    const rect = atlas.slotPixels(slot);

    try std.testing.expectEqual(@as(u8, 0), pixelAlpha(&atlas, rect.x, rect.y));
    try std.testing.expectEqual(@as(u8, 0), pixelAlpha(&atlas, rect.x + slot_size - 1, rect.y));
    try std.testing.expectEqual(@as(u8, 0), pixelAlpha(&atlas, rect.x, rect.y + slot_size - 1));
    try std.testing.expectEqual(@as(u8, 0), pixelAlpha(&atlas, rect.x + slot_size - 1, rect.y + slot_size - 1));

    const coverage = slotAlphaCount(&atlas, slot);
    try std.testing.expect(coverage > 0);
    try std.testing.expect(coverage < (slot_size * slot_size * 3) / 4);
}

test "icon atlas preserves inherited fill none on outline icons" {
    var atlas = try IconAtlas.init(std.testing.allocator);
    defer atlas.deinit();
    const slot = try atlas.getOrCreate("grid");
    const rect = atlas.slotPixels(slot);

    try std.testing.expectEqual(@as(u8, 0), pixelAlpha(&atlas, rect.x + 9, rect.y + 9));
    try std.testing.expectEqual(@as(u8, 0), pixelAlpha(&atlas, rect.x + 23, rect.y + 9));
    try std.testing.expectEqual(@as(u8, 0), pixelAlpha(&atlas, rect.x + 9, rect.y + 23));
    try std.testing.expectEqual(@as(u8, 0), pixelAlpha(&atlas, rect.x + 23, rect.y + 23));
}

test "icon atlas rejects unknown icons" {
    var atlas = try IconAtlas.init(std.testing.allocator);
    defer atlas.deinit();
    try std.testing.expectError(error.UnknownEditorIcon, atlas.getOrCreate("missing-icon"));
}

test "icon atlas rasterizes every editor icon mapping" {
    var atlas = try IconAtlas.init(std.testing.allocator);
    defer atlas.deinit();
    const icons = [_][]const u8{
        "undo",
        "redo",
        "save",
        "play",
        "music-note",
        "build",
        "settings",
        "close",
        "delete",
        "select",
        "move",
        "rotate",
        "scale",
        "frame",
        "duplicate",
        "grid",
        "snap",
        "gizmo",
        "box",
        "mesh",
        "world",
        "pivot",
        "eye",
        "eye-closed",
        "lock",
        "lock-slash",
        "scene",
        "assets",
        "add",
        "search",
        "material",
        "physics",
        "perspective",
        "orthographic",
        "chevron-down",
        "chevron-right",
    };
    for (icons) |icon| {
        const before = alphaCount(atlas.pixels);
        _ = try atlas.getOrCreate(icon);
        const after = alphaCount(atlas.pixels);
        try std.testing.expect(after > before);
        try std.testing.expect(after - before < slot_size * slot_size);
    }
}

fn alphaCount(pixels: []const u8) usize {
    var count: usize = 0;
    for (0..pixels.len / 4) |i| {
        if (pixels[i * 4 + 3] != 0) count += 1;
    }
    return count;
}

fn pixelAlpha(self: *const IconAtlas, x: u32, y: u32) u8 {
    const idx = (@as(usize, y) * self.width + x) * 4;
    return self.pixels[idx + 3];
}

fn slotAlphaCount(self: *const IconAtlas, slot: Slot) usize {
    const rect = self.slotPixels(slot);
    var count: usize = 0;
    var y: u32 = 0;
    while (y < slot_size) : (y += 1) {
        var x: u32 = 0;
        while (x < slot_size) : (x += 1) {
            if (pixelAlpha(self, rect.x + x, rect.y + y) != 0) count += 1;
        }
    }
    return count;
}
