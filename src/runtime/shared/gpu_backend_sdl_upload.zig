const std = @import("std");
const sdl_gpu = @import("sdl_gpu.zig");
const gpu_scene = @import("gpu_scene.zig");
const shared_color = @import("color.zig");
const types = @import("gpu_backend_sdl_types.zig");

const content_hash_vertex_limit: usize = 4096;
const content_hash_index_limit: usize = 8192;
const content_hash_texture_limit: usize = 4096;

pub fn clearMeshes(self: anytype) void {
    for (self.meshes.items) |mesh| {
        if (mesh.vertex_buffer) |buffer| sdl_gpu.SDL_ReleaseGPUBuffer(self.device, buffer);
        if (mesh.index_buffer) |buffer| sdl_gpu.SDL_ReleaseGPUBuffer(self.device, buffer);
        if (mesh.wireframe_index_buffer) |buffer| sdl_gpu.SDL_ReleaseGPUBuffer(self.device, buffer);
        if (mesh.texture) |tex| sdl_gpu.SDL_ReleaseGPUTexture(self.device, tex);
    }
    self.meshes.clearRetainingCapacity();
    self.cached_object_count = 0;
    self.cached_scene_hash = 0;
}

pub fn syncSceneObjects(self: anytype, objects: []const gpu_scene.SceneGpuObject) !void {
    const scene_hash = hashSceneObjects(objects);
    if (self.cached_object_count == objects.len and
        self.cached_scene_hash == scene_hash and
        objects.len == self.meshes.items.len)
    {
        updateDynamicSceneObjectState(self, objects);
        return;
    }
    clearMeshes(self);
    for (objects) |obj| {
        try uploadMesh(self, obj);
    }
    self.cached_object_count = objects.len;
    self.cached_scene_hash = scene_hash;
}

pub fn initGrid(self: anytype) !void {
    var verts: [84]types.GridColorVertex = undefined;
    var count: usize = 0;

    var i: i32 = -10;
    while (i <= 10) : (i += 1) {
        const t = @as(f32, @floatFromInt(i));
        verts[count] = .{ .x = t, .y = 0, .z = -10, .r = 48, .g = 56, .b = 72, .a = 255 };
        count += 1;
        verts[count] = .{ .x = t, .y = 0, .z = 10, .r = 48, .g = 56, .b = 72, .a = 255 };
        count += 1;
    }
    i = -10;
    while (i <= 10) : (i += 1) {
        const t = @as(f32, @floatFromInt(i));
        verts[count] = .{ .x = -10, .y = 0, .z = t, .r = 48, .g = 56, .b = 72, .a = 255 };
        count += 1;
        verts[count] = .{ .x = 10, .y = 0, .z = t, .r = 48, .g = 56, .b = 72, .a = 255 };
        count += 1;
    }
    self.grid_vertex_count = @intCast(count);
    self.grid_vertex_buffer = try uploadVertexData(self, types.GridColorVertex, verts[0..count]);
}

pub fn createSolidTexture(
    self: anytype,
    r: u8,
    g: u8,
    b: u8,
    a: u8,
) !*sdl_gpu.SDL_GPUTexture {
    var data: [gpu_scene.TextureSize * gpu_scene.TextureSize * 4]u8 = undefined;
    for (0..gpu_scene.TextureSize * gpu_scene.TextureSize) |i| {
        data[i * 4 ..][0..4].* = .{ r, g, b, a };
    }
    return uploadRgbaTexture(self, &data);
}

fn uploadMesh(self: anytype, obj: gpu_scene.SceneGpuObject) !void {
    const mesh = obj.mesh;

    if (mesh.vertices.len == 0 or mesh.indices.len == 0) {
        try self.meshes.append(self.allocator, .{
            .vertex_buffer = null,
            .index_buffer = null,
            .wireframe_index_buffer = null,
            .texture = null,
            .index_count = 0,
            .wireframe_index_count = 0,
            .has_texture = false,
            .texture_usage = obj.texture_usage,
            .base_color = .{
                @as(f32, @floatFromInt(obj.base_color.r)) / 255.0,
                @as(f32, @floatFromInt(obj.base_color.g)) / 255.0,
                @as(f32, @floatFromInt(obj.base_color.b)) / 255.0,
                @as(f32, @floatFromInt(obj.base_color.a)) / 255.0,
            },
            .dissolve_amount = sanitizeDissolveAmount(obj.dissolve_amount),
            .dissolve_inverted = obj.dissolve_inverted,
        });
        return;
    }

    var verts = try self.allocator.alloc(types.SdlGpuVertex, mesh.vertices.len);
    defer self.allocator.free(verts);
    for (mesh.vertices, 0..) |v, idx| {
        verts[idx] = .{
            .x = v.position.x,
            .y = v.position.y,
            .z = v.position.z,
            .w = 1,
            .nx = v.normal.x,
            .ny = v.normal.y,
            .nz = v.normal.z,
            .u = v.uv.x,
            .v = v.uv.y,
        };
    }

    const vertex_buffer = try uploadVertexBytes(self, std.mem.sliceAsBytes(verts));
    const index_buffer = try uploadIndexData(self, mesh.indices);
    errdefer sdl_gpu.SDL_ReleaseGPUBuffer(self.device, index_buffer);
    const wireframe_indices = try buildWireframeIndices(self.allocator, mesh.indices);
    defer self.allocator.free(wireframe_indices);
    const wireframe_index_buffer = try uploadIndexData(self, wireframe_indices);
    errdefer sdl_gpu.SDL_ReleaseGPUBuffer(self.device, wireframe_index_buffer);

    const material_rgba = try self.allocator.alloc(u8, gpu_scene.TextureSize * gpu_scene.TextureSize * 4);
    defer self.allocator.free(material_rgba);

    var has_texture = false;
    if (obj.texture) |tex| {
        if (tex.len >= gpu_scene.TextureSize * gpu_scene.TextureSize * 4) {
            fillMaterialTexture(
                material_rgba,
                tex[0 .. gpu_scene.TextureSize * gpu_scene.TextureSize * 4],
                obj.base_color,
            );
            has_texture = true;
        } else {
            fillSolidMaterialTexture(material_rgba, obj.base_color);
        }
    } else {
        fillSolidMaterialTexture(material_rgba, obj.base_color);
    }
    const texture = try uploadRgbaTexture(self, material_rgba);

    try self.meshes.append(self.allocator, .{
        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
        .wireframe_index_buffer = wireframe_index_buffer,
        .texture = texture,
        .index_count = @intCast(mesh.indices.len),
        .wireframe_index_count = @intCast(wireframe_indices.len),
        .has_texture = has_texture,
        .texture_usage = obj.texture_usage,
        .base_color = .{
            @as(f32, @floatFromInt(obj.base_color.r)) / 255.0,
            @as(f32, @floatFromInt(obj.base_color.g)) / 255.0,
            @as(f32, @floatFromInt(obj.base_color.b)) / 255.0,
            @as(f32, @floatFromInt(obj.base_color.a)) / 255.0,
        },
        .dissolve_amount = sanitizeDissolveAmount(obj.dissolve_amount),
        .dissolve_inverted = obj.dissolve_inverted,
    });
}

fn updateDynamicSceneObjectState(self: anytype, objects: []const gpu_scene.SceneGpuObject) void {
    for (objects, 0..) |obj, index| {
        self.meshes.items[index].dissolve_amount = sanitizeDissolveAmount(obj.dissolve_amount);
        self.meshes.items[index].dissolve_inverted = obj.dissolve_inverted;
    }
}

fn sanitizeDissolveAmount(value: f32) f32 {
    if (!std.math.isFinite(value)) return 0.0;
    return std.math.clamp(value, 0.0, 1.0);
}

pub fn fillSolidMaterialTexture(dest: []u8, base_color: shared_color.Color) void {
    var i: usize = 0;
    while (i + 3 < dest.len) : (i += 4) {
        dest[i] = base_color.r;
        dest[i + 1] = base_color.g;
        dest[i + 2] = base_color.b;
        dest[i + 3] = base_color.a;
    }
}

pub fn fillMaterialTexture(dest: []u8, source: []const u8, base_color: shared_color.Color) void {
    const len = @min(dest.len, source.len);
    var i: usize = 0;
    while (i + 3 < len) : (i += 4) {
        dest[i] = modulateChannel(source[i], base_color.r);
        dest[i + 1] = modulateChannel(source[i + 1], base_color.g);
        dest[i + 2] = modulateChannel(source[i + 2], base_color.b);
        dest[i + 3] = modulateChannel(source[i + 3], base_color.a);
    }
    while (i + 3 < dest.len) : (i += 4) {
        dest[i] = 0;
        dest[i + 1] = 0;
        dest[i + 2] = 0;
        dest[i + 3] = 0;
    }
}

fn modulateChannel(source: u8, material: u8) u8 {
    return @intCast((@as(u16, source) * @as(u16, material) + 127) / 255);
}

pub fn hashSceneObjects(objects: []const gpu_scene.SceneGpuObject) u64 {
    var hasher = std.hash.Wyhash.init(0);
    for (objects) |obj| {
        hasher.update(std.mem.asBytes(&obj.base_color));
        hasher.update(std.mem.asBytes(&obj.texture_usage));
        hashMeshIdentity(&hasher, obj.mesh);
        if (obj.texture) |texture| {
            hashSliceIdentity(u8, &hasher, texture, content_hash_texture_limit);
        } else {
            hasher.update(&.{0});
        }
    }
    return hasher.final();
}

fn hashMeshIdentity(hasher: *std.hash.Wyhash, mesh: anytype) void {
    hashSliceIdentity(std.meta.Child(@TypeOf(mesh.vertices)), hasher, mesh.vertices, content_hash_vertex_limit);
    hashSliceIdentity(u32, hasher, mesh.indices, content_hash_index_limit);
    const has_skin = mesh.skin != null;
    hasher.update(std.mem.asBytes(&has_skin));
}

fn hashSliceIdentity(comptime T: type, hasher: *std.hash.Wyhash, slice: []const T, content_limit: usize) void {
    const ptr_value = @intFromPtr(slice.ptr);
    hasher.update(std.mem.asBytes(&ptr_value));
    hasher.update(std.mem.asBytes(&slice.len));
    if (slice.len <= content_limit) {
        hasher.update(std.mem.sliceAsBytes(slice));
        return;
    }
    const window = @max(@as(usize, 1), content_limit / 4);
    const starts = [_]usize{
        0,
        slice.len / 3,
        (slice.len * 2) / 3,
        slice.len - window,
    };
    for (starts) |start_raw| {
        const start = @min(start_raw, slice.len - window);
        hasher.update(std.mem.sliceAsBytes(slice[start .. start + window]));
    }
}

fn uploadVertexData(self: anytype, comptime T: type, data: []const T) !*sdl_gpu.SDL_GPUBuffer {
    return uploadVertexBytes(self, std.mem.sliceAsBytes(data));
}

fn uploadVertexBytes(self: anytype, bytes: []const u8) !*sdl_gpu.SDL_GPUBuffer {
    const buffer = sdl_gpu.SDL_CreateGPUBuffer(self.device, &.{
        .usage = sdl_gpu.SDL_GPU_BUFFERUSAGE_VERTEX,
        .size = @intCast(bytes.len),
    }) orelse return error.BufferCreateFailed;
    errdefer sdl_gpu.SDL_ReleaseGPUBuffer(self.device, buffer);
    try uploadBytesToBuffer(self, buffer, bytes);
    return buffer;
}

pub fn buildWireframeIndices(allocator: std.mem.Allocator, triangle_indices: []const u32) ![]u32 {
    var seen_edges = std.AutoHashMap(u64, void).init(allocator);
    defer seen_edges.deinit();

    var line_indices: std.ArrayList(u32) = .empty;
    errdefer line_indices.deinit(allocator);
    try line_indices.ensureTotalCapacity(allocator, (triangle_indices.len / 3) * 6);

    var tri: usize = 0;
    while (tri + 2 < triangle_indices.len) : (tri += 3) {
        const vi0 = triangle_indices[tri];
        const vi1 = triangle_indices[tri + 1];
        const vi2 = triangle_indices[tri + 2];
        try appendUniqueEdge(allocator, &seen_edges, &line_indices, vi0, vi1);
        try appendUniqueEdge(allocator, &seen_edges, &line_indices, vi1, vi2);
        try appendUniqueEdge(allocator, &seen_edges, &line_indices, vi2, vi0);
    }
    return try line_indices.toOwnedSlice(allocator);
}

fn appendUniqueEdge(
    allocator: std.mem.Allocator,
    seen_edges: *std.AutoHashMap(u64, void),
    line_indices: *std.ArrayList(u32),
    a: u32,
    b: u32,
) !void {
    const key = edgeKey(a, b);
    const entry = try seen_edges.getOrPut(key);
    if (entry.found_existing) return;
    try line_indices.append(allocator, a);
    try line_indices.append(allocator, b);
}

fn edgeKey(a: u32, b: u32) u64 {
    const lo = @min(a, b);
    const hi = @max(a, b);
    return (@as(u64, lo) << 32) | @as(u64, hi);
}

fn uploadIndexData(self: anytype, indices: []const u32) !*sdl_gpu.SDL_GPUBuffer {
    const bytes = std.mem.sliceAsBytes(indices);
    const buffer = sdl_gpu.SDL_CreateGPUBuffer(self.device, &.{
        .usage = sdl_gpu.SDL_GPU_BUFFERUSAGE_INDEX,
        .size = @intCast(bytes.len),
    }) orelse return error.BufferCreateFailed;
    errdefer sdl_gpu.SDL_ReleaseGPUBuffer(self.device, buffer);
    try uploadBytesToBuffer(self, buffer, bytes);
    return buffer;
}

fn uploadBytesToBuffer(self: anytype, buffer: *sdl_gpu.SDL_GPUBuffer, bytes: []const u8) !void {
    const transfer = sdl_gpu.SDL_CreateGPUTransferBuffer(self.device, &.{
        .usage = sdl_gpu.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = @intCast(bytes.len),
    }) orelse return error.TransferBufferCreateFailed;
    defer sdl_gpu.SDL_ReleaseGPUTransferBuffer(self.device, transfer);

    const mapped = sdl_gpu.SDL_MapGPUTransferBuffer(self.device, transfer, false) orelse return error.TransferMapFailed;
    const mapped_bytes = @as([*]u8, @ptrCast(mapped))[0..bytes.len];
    @memcpy(mapped_bytes, bytes);
    sdl_gpu.SDL_UnmapGPUTransferBuffer(self.device, transfer);

    const cmdbuf = sdl_gpu.SDL_AcquireGPUCommandBuffer(self.device) orelse return error.CommandBufferFailed;
    const copy_pass = sdl_gpu.SDL_BeginGPUCopyPass(cmdbuf) orelse return error.CopyPassFailed;
    sdl_gpu.SDL_UploadToGPUBuffer(copy_pass, &.{
        .transfer_buffer = transfer,
        .offset = 0,
    }, &.{
        .buffer = buffer,
        .offset = 0,
        .size = @intCast(bytes.len),
    }, false);
    sdl_gpu.SDL_EndGPUCopyPass(copy_pass);
    if (!sdl_gpu.SDL_SubmitGPUCommandBuffer(cmdbuf)) return error.CommandSubmitFailed;
}

fn uploadRgbaTexture(self: anytype, rgba: []const u8) !*sdl_gpu.SDL_GPUTexture {
    const texture = sdl_gpu.SDL_CreateGPUTexture(self.device, &.{
        .type = sdl_gpu.SDL_GPU_TEXTURETYPE_2D,
        .format = sdl_gpu.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
        .usage = sdl_gpu.SDL_GPU_TEXTUREUSAGE_SAMPLER,
        .width = gpu_scene.TextureSize,
        .height = gpu_scene.TextureSize,
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .sample_count = sdl_gpu.SDL_GPU_SAMPLECOUNT_1,
    }) orelse return error.TextureCreateFailed;
    errdefer sdl_gpu.SDL_ReleaseGPUTexture(self.device, texture);

    const transfer = sdl_gpu.SDL_CreateGPUTransferBuffer(self.device, &.{
        .usage = sdl_gpu.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = @intCast(rgba.len),
    }) orelse return error.TransferBufferCreateFailed;
    defer sdl_gpu.SDL_ReleaseGPUTransferBuffer(self.device, transfer);

    const mapped = sdl_gpu.SDL_MapGPUTransferBuffer(self.device, transfer, false) orelse return error.TransferMapFailed;
    const mapped_rgba = @as([*]u8, @ptrCast(mapped))[0..rgba.len];
    @memcpy(mapped_rgba, rgba);
    sdl_gpu.SDL_UnmapGPUTransferBuffer(self.device, transfer);

    const cmdbuf = sdl_gpu.SDL_AcquireGPUCommandBuffer(self.device) orelse return error.CommandBufferFailed;
    const copy_pass = sdl_gpu.SDL_BeginGPUCopyPass(cmdbuf) orelse return error.CopyPassFailed;
    sdl_gpu.SDL_UploadToGPUTexture(copy_pass, &.{
        .transfer_buffer = transfer,
        .offset = 0,
    }, &.{
        .texture = texture,
        .w = gpu_scene.TextureSize,
        .h = gpu_scene.TextureSize,
        .d = 1,
    }, false);
    sdl_gpu.SDL_EndGPUCopyPass(copy_pass);
    if (!sdl_gpu.SDL_SubmitGPUCommandBuffer(cmdbuf)) return error.CommandSubmitFailed;
    return texture;
}

test "wireframe indices expand triangle edges" {
    const triangle_indices = [_]u32{ 0, 1, 2, 2, 3, 0 };
    const line_indices = try buildWireframeIndices(std.testing.allocator, &triangle_indices);
    defer std.testing.allocator.free(line_indices);

    try std.testing.expectEqual(@as(usize, 10), line_indices.len);
    try std.testing.expectEqualSlices(u32, &.{ 0, 1, 1, 2, 2, 0, 2, 3, 3, 0 }, line_indices);
}

test "solid material texture fills base color" {
    var pixels: [8]u8 = undefined;
    fillSolidMaterialTexture(&pixels, .{ .r = 24, .g = 48, .b = 96, .a = 192 });

    try std.testing.expectEqualSlices(u8, &.{ 24, 48, 96, 192 }, pixels[0..4]);
    try std.testing.expectEqualSlices(u8, &.{ 24, 48, 96, 192 }, pixels[4..8]);
}

test "textured material is modulated by base color" {
    const source = [_]u8{
        255, 128, 64,  255,
        80,  120, 200, 128,
    };
    var pixels: [8]u8 = undefined;
    fillMaterialTexture(&pixels, &source, .{ .r = 128, .g = 255, .b = 64, .a = 128 });

    try std.testing.expectEqualSlices(u8, &.{ 128, 128, 16, 128 }, pixels[0..4]);
    try std.testing.expectEqualSlices(u8, &.{ 40, 120, 50, 64 }, pixels[4..8]);
}

test "scene object hash changes when material color changes" {
    const geometry = @import("geometry.zig");
    var mesh = try geometry.buildPrimitive(std.testing.allocator, .box, .{});
    defer mesh.deinit(std.testing.allocator);

    const red = [_]gpu_scene.SceneGpuObject{.{
        .mesh = &mesh,
        .texture = null,
        .base_color = .{ .r = 255, .g = 0, .b = 0, .a = 255 },
    }};
    const blue = [_]gpu_scene.SceneGpuObject{.{
        .mesh = &mesh,
        .texture = null,
        .base_color = .{ .r = 0, .g = 0, .b = 255, .a = 255 },
    }};

    try std.testing.expect(hashSceneObjects(&red) != hashSceneObjects(&blue));
}

test "scene object hash changes when texture usage changes" {
    const geometry = @import("geometry.zig");
    var mesh = try geometry.buildPrimitive(std.testing.allocator, .box, .{});
    defer mesh.deinit(std.testing.allocator);

    const material = [_]gpu_scene.SceneGpuObject{.{
        .mesh = &mesh,
        .texture = null,
        .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .texture_usage = .material,
    }};
    const terrain_mask = [_]gpu_scene.SceneGpuObject{.{
        .mesh = &mesh,
        .texture = null,
        .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .texture_usage = .terrain_mask,
    }};

    try std.testing.expect(hashSceneObjects(&material) != hashSceneObjects(&terrain_mask));
}

test "scene object hash ignores dynamic dissolve amount" {
    const geometry = @import("geometry.zig");
    var mesh = try geometry.buildPrimitive(std.testing.allocator, .box, .{});
    defer mesh.deinit(std.testing.allocator);

    const solid_object = [_]gpu_scene.SceneGpuObject{.{
        .mesh = &mesh,
        .texture = null,
        .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .dissolve_amount = 0.0,
    }};
    const dissolving = [_]gpu_scene.SceneGpuObject{.{
        .mesh = &mesh,
        .texture = null,
        .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .dissolve_amount = 0.75,
    }};

    try std.testing.expectEqual(hashSceneObjects(&solid_object), hashSceneObjects(&dissolving));
}

test "scene object hash notices large texture tail changes" {
    const geometry = @import("geometry.zig");
    var mesh = try geometry.buildPrimitive(std.testing.allocator, .box, .{});
    defer mesh.deinit(std.testing.allocator);

    var texture = try std.testing.allocator.alloc(u8, gpu_scene.TextureSize * gpu_scene.TextureSize * 4);
    defer std.testing.allocator.free(texture);
    @memset(texture, 32);

    const object = [_]gpu_scene.SceneGpuObject{.{
        .mesh = &mesh,
        .texture = texture,
        .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .texture_usage = .terrain_mask,
    }};
    const before = hashSceneObjects(&object);
    texture[texture.len - 1] = 240;
    try std.testing.expect(before != hashSceneObjects(&object));
}
