const std = @import("std");
const framework = @import("../framework/mod.zig");
const kdl = @import("kdl");
const scene_spawn = @import("scene_spawn.zig");

pub const PropAssetCache = struct {
    allocator: std.mem.Allocator,
    io: ?std.Io = null,
    project_path: []u8 = "",
    entries: std.ArrayList(Entry),

    const Entry = struct {
        asset_id: []u8,
        mesh_index: u32,
        ref_count: usize = 0,

        fn deinit(self: *Entry, allocator: std.mem.Allocator) void {
            allocator.free(self.asset_id);
            self.asset_id = "";
        }
    };

    pub fn init(allocator: std.mem.Allocator) PropAssetCache {
        return .{
            .allocator = allocator,
            .entries = .empty,
        };
    }

    pub fn initWithProject(allocator: std.mem.Allocator, io: std.Io, project_path: []const u8) !PropAssetCache {
        var cache = init(allocator);
        cache.io = io;
        cache.project_path = try allocator.dupe(u8, project_path);
        return cache;
    }

    pub fn deinit(self: *PropAssetCache) void {
        for (self.entries.items) |*entry| entry.deinit(self.allocator);
        self.entries.deinit(self.allocator);
        if (self.project_path.len > 0) self.allocator.free(self.project_path);
        self.project_path = "";
    }

    pub fn retainMesh(
        self: *PropAssetCache,
        scene_state: *scene_spawn.SceneSpawnState,
        world: *framework.World,
        asset_id: []const u8,
        base_color: scene_spawn.SceneColor,
    ) !u32 {
        _ = base_color;
        for (self.entries.items) |*entry| {
            if (std.mem.eql(u8, entry.asset_id, asset_id)) {
                entry.ref_count += 1;
                return entry.mesh_index;
            }
        }

        const io = self.io orelse return error.MissingPropAssetLoader;
        if (self.project_path.len == 0) return error.MissingPropAssetLoader;

        var project_dir = try openProjectDir(io, self.project_path);
        defer project_dir.close(io);

        const doc_path = try propDocumentPath(self.allocator, asset_id);
        defer self.allocator.free(doc_path);
        const doc_bytes = try project_dir.readFileAlloc(io, doc_path, self.allocator, .limited(1024 * 1024));
        defer self.allocator.free(doc_bytes);
        var doc = try parseRuntimePropDocument(self.allocator, doc_bytes);
        defer doc.deinit(self.allocator);

        const mesh_bytes = try project_dir.readFileAlloc(io, doc.mesh_path, self.allocator, .limited(64 * 1024 * 1024));
        defer self.allocator.free(mesh_bytes);

        var mesh = try decodePropMesh(self.allocator, mesh_bytes);
        defer mesh.deinit(self.allocator);

        const texture = if (doc.texture_path) |texture_path|
            try project_dir.readFileAlloc(io, texture_path, self.allocator, .limited(128 * 128 * 4 + 1))
        else
            try solidTexture(self.allocator, doc.base_color);
        defer self.allocator.free(texture);
        if (texture.len != 128 * 128 * 4) return error.InvalidPropTexture;

        const mesh_index = try scene_state.appendMesh(world, .{
            .position = .{ .x = 0, .y = 0, .z = 0 },
            .scale = .{ .x = 1, .y = 1, .z = 1 },
            .vertices = mesh.vertices,
            .indices = mesh.indices,
            .texture = texture,
            .base_color = doc.base_color,
        });

        const owned_id = try self.allocator.dupe(u8, asset_id);
        errdefer self.allocator.free(owned_id);
        try self.entries.append(self.allocator, .{
            .asset_id = owned_id,
            .mesh_index = mesh_index,
            .ref_count = 1,
        });
        return mesh_index;
    }

    pub fn releaseMesh(self: *PropAssetCache, asset_id: []const u8) !void {
        for (self.entries.items) |*entry| {
            if (std.mem.eql(u8, entry.asset_id, asset_id)) {
                if (entry.ref_count == 0) return error.PropAssetNotRetained;
                entry.ref_count -= 1;
                return;
            }
        }
        return error.UnknownPropAsset;
    }

    pub fn activeAssetCount(self: *const PropAssetCache) usize {
        var count: usize = 0;
        for (self.entries.items) |entry| {
            if (entry.ref_count > 0) count += 1;
        }
        return count;
    }
};

const mesh_magic: [4]u8 = .{ 'F', 'M', 'E', 'S' };
const mesh_version: u32 = 2;
const mesh_version_v1: u32 = 1;

const DecodedPropMesh = struct {
    vertices: []scene_spawn.StoredVertex,
    indices: []u32,

    fn deinit(self: *DecodedPropMesh, allocator: std.mem.Allocator) void {
        allocator.free(self.vertices);
        allocator.free(self.indices);
        self.vertices = &.{};
        self.indices = &.{};
    }
};

const RuntimePropDocument = struct {
    mesh_path: []u8,
    texture_path: ?[]u8,
    base_color: scene_spawn.SceneColor,

    fn deinit(self: *RuntimePropDocument, allocator: std.mem.Allocator) void {
        allocator.free(self.mesh_path);
        if (self.texture_path) |path| allocator.free(path);
    }
};

fn parseRuntimePropDocument(allocator: std.mem.Allocator, source: []const u8) !RuntimePropDocument {
    const buffer = try allocator.allocSentinel(u8, source.len, 0);
    defer allocator.free(buffer);
    @memcpy(buffer, source);

    var parser = kdl.Parser.init(buffer);
    var depth: i32 = 0;
    var section: ?[]const u8 = null;
    var mesh_path: ?[]u8 = null;
    var texture_path: ?[]u8 = null;
    var base_color: scene_spawn.SceneColor = .{ .r = 255, .g = 255, .b = 255, .a = 255 };
    errdefer {
        if (mesh_path) |path| allocator.free(path);
        if (texture_path) |path| allocator.free(path);
    }

    while (true) {
        const event = try parser.next();
        switch (event) {
            .node => |node| {
                if (depth == 0) {
                    if (!std.mem.eql(u8, node.val, "prop_asset")) return error.InvalidPropAssetDocument;
                } else if (depth == 1) {
                    section = node.val;
                }
            },
            .prop => |prop| {
                if (depth != 1) continue;
                const section_name = section orelse return error.InvalidPropAssetDocument;
                const value = try decodeKdlValue(allocator, prop.val);
                defer allocator.free(value);
                if (std.mem.eql(u8, section_name, "mesh") and std.mem.eql(u8, prop.key, "asset")) {
                    if (mesh_path) |existing| allocator.free(existing);
                    mesh_path = try allocator.dupe(u8, value);
                } else if (std.mem.eql(u8, section_name, "material")) {
                    if (std.mem.eql(u8, prop.key, "base_color")) {
                        base_color = try parseColor(value);
                    } else if (std.mem.eql(u8, prop.key, "texture")) {
                        if (texture_path) |existing| allocator.free(existing);
                        texture_path = try allocator.dupe(u8, value);
                    }
                }
            },
            .child_block_begin => depth += 1,
            .child_block_end => {
                depth -= 1;
                if (depth == 0) section = null;
            },
            .arg, .invalid => return error.InvalidPropAssetDocument,
            .eof => break,
        }
    }
    if (depth != 0) return error.InvalidPropAssetDocument;
    return .{
        .mesh_path = mesh_path orelse return error.MissingPropAssetMesh,
        .texture_path = texture_path,
        .base_color = base_color,
    };
}

fn decodePropMesh(allocator: std.mem.Allocator, bytes: []const u8) !DecodedPropMesh {
    if (bytes.len < 16) return error.InvalidMeshFormat;
    if (!std.mem.eql(u8, bytes[0..4], &mesh_magic)) return error.InvalidMeshFormat;

    const file_version = std.mem.readInt(u32, bytes[4..8], .little);
    const vertex_count = std.mem.readInt(u32, bytes[8..12], .little);
    const index_count = std.mem.readInt(u32, bytes[12..16], .little);
    const vertex_bytes = vertex_count * @sizeOf(scene_spawn.StoredVertex);
    const index_bytes = index_count * @sizeOf(u32);
    const payload_end = 16 + vertex_bytes + index_bytes;
    if (bytes.len < payload_end) return error.InvalidMeshFormat;

    switch (file_version) {
        mesh_version_v1 => if (bytes.len != payload_end) return error.InvalidMeshFormat,
        mesh_version => if (bytes.len < payload_end + 1) return error.InvalidMeshFormat,
        else => return error.UnsupportedMeshVersion,
    }

    const vertices = try allocator.alloc(scene_spawn.StoredVertex, vertex_count);
    errdefer allocator.free(vertices);
    @memcpy(std.mem.sliceAsBytes(vertices), bytes[16 .. 16 + vertex_bytes]);

    const indices = try allocator.alloc(u32, index_count);
    errdefer allocator.free(indices);
    @memcpy(std.mem.sliceAsBytes(indices), bytes[16 + vertex_bytes .. payload_end]);

    if (file_version == mesh_version and bytes[payload_end] != 0) return error.UnsupportedSkinnedPropMesh;

    return .{ .vertices = vertices, .indices = indices };
}

fn propDocumentPath(allocator: std.mem.Allocator, id: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "props/{s}.kdl", .{id});
}

fn decodeKdlValue(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    if (raw.len < 2 or raw[0] != '"' or raw[raw.len - 1] != '"') return allocator.dupe(u8, raw);
    var out = try std.ArrayList(u8).initCapacity(allocator, raw.len - 2);
    defer out.deinit(allocator);
    var idx: usize = 1;
    while (idx + 1 < raw.len) : (idx += 1) {
        const ch = raw[idx];
        if (ch == '\\' and idx + 2 < raw.len) {
            idx += 1;
            const escaped = raw[idx];
            try out.append(allocator, switch (escaped) {
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                else => escaped,
            });
        } else {
            try out.append(allocator, ch);
        }
    }
    return out.toOwnedSlice(allocator);
}

fn parseColor(value: []const u8) !scene_spawn.SceneColor {
    var parts = std.mem.splitScalar(u8, value, ',');
    const r = try parseColorByte(parts.next() orelse return error.InvalidPropColor);
    const g = try parseColorByte(parts.next() orelse return error.InvalidPropColor);
    const b = try parseColorByte(parts.next() orelse return error.InvalidPropColor);
    const a = try parseColorByte(parts.next() orelse return error.InvalidPropColor);
    if (parts.next() != null) return error.InvalidPropColor;
    return .{ .r = r, .g = g, .b = b, .a = a };
}

fn parseColorByte(text: []const u8) !u8 {
    return try std.fmt.parseInt(u8, std.mem.trim(u8, text, " \t\r\n"), 10);
}

fn solidTexture(allocator: std.mem.Allocator, color: scene_spawn.SceneColor) ![]u8 {
    const pixel_count: usize = 128 * 128;
    const texture = try allocator.alloc(u8, pixel_count * 4);
    var offset: usize = 0;
    while (offset < texture.len) : (offset += 4) {
        texture[offset] = color.r;
        texture[offset + 1] = color.g;
        texture[offset + 2] = color.b;
        texture[offset + 3] = color.a;
    }
    return texture;
}

fn openProjectDir(io: std.Io, project_path: []const u8) !std.Io.Dir {
    if (std.fs.path.isAbsolute(project_path)) {
        return try std.Io.Dir.openDirAbsolute(io, project_path, .{});
    }
    return try std.Io.Dir.cwd().openDir(io, project_path, .{});
}

test "empty prop cache tracks no active assets" {
    var cache = PropAssetCache.init(std.testing.allocator);
    defer cache.deinit();

    try std.testing.expectEqual(@as(usize, 0), cache.activeAssetCount());
}
