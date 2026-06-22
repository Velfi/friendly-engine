const std = @import("std");
const sdl_gpu = @import("sdl_gpu.zig");
const types = @import("gpu_backend_sdl_types.zig");

pub fn uploadGrassInstancesOnCommandBuffer(
    self: anytype,
    cmdbuf: *sdl_gpu.SDL_GPUCommandBuffer,
    instances: []const types.GpuGrassInstance,
) !*sdl_gpu.SDL_GPUBuffer {
    if (instances.len == 0) return error.EmptyGrassBatch;
    return uploadBytesOnCommandBuffer(self, cmdbuf, std.mem.sliceAsBytes(instances));
}

pub fn uploadInstancesOnCommandBuffer(
    self: anytype,
    cmdbuf: *sdl_gpu.SDL_GPUCommandBuffer,
    instances: []const types.GpuMeshInstance,
) !*sdl_gpu.SDL_GPUBuffer {
    if (instances.len == 0) return error.EmptyInstanceBatch;
    const bytes = std.mem.sliceAsBytes(instances);
    return uploadBytesOnCommandBuffer(self, cmdbuf, bytes);
}

fn uploadBytesOnCommandBuffer(self: anytype, cmdbuf: *sdl_gpu.SDL_GPUCommandBuffer, bytes: []const u8) !*sdl_gpu.SDL_GPUBuffer {
    try ensureInstanceBufferCapacity(self, bytes.len);
    const buffer = self.instance_buffer.?;

    const transfer = sdl_gpu.SDL_CreateGPUTransferBuffer(self.device, &.{
        .usage = sdl_gpu.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = @intCast(bytes.len),
    }) orelse return error.TransferBufferCreateFailed;
    defer sdl_gpu.SDL_ReleaseGPUTransferBuffer(self.device, transfer);

    const mapped = sdl_gpu.SDL_MapGPUTransferBuffer(self.device, transfer, false) orelse return error.TransferMapFailed;
    const mapped_bytes = @as([*]u8, @ptrCast(mapped))[0..bytes.len];
    @memcpy(mapped_bytes, bytes);
    sdl_gpu.SDL_UnmapGPUTransferBuffer(self.device, transfer);

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
    return buffer;
}

fn ensureInstanceBufferCapacity(self: anytype, byte_size: usize) !void {
    if (self.instance_buffer != null and self.instance_buffer_capacity >= byte_size) return;
    if (self.instance_buffer) |buffer| {
        sdl_gpu.SDL_ReleaseGPUBuffer(self.device, buffer);
        self.instance_buffer = null;
        self.instance_buffer_capacity = 0;
    }
    const buffer = sdl_gpu.SDL_CreateGPUBuffer(self.device, &.{
        .usage = sdl_gpu.SDL_GPU_BUFFERUSAGE_VERTEX,
        .size = @intCast(byte_size),
    }) orelse return error.BufferCreateFailed;
    self.instance_buffer = buffer;
    self.instance_buffer_capacity = byte_size;
}

pub fn releaseInstanceBuffer(self: anytype) void {
    if (self.instance_buffer) |buffer| {
        sdl_gpu.SDL_ReleaseGPUBuffer(self.device, buffer);
        self.instance_buffer = null;
        self.instance_buffer_capacity = 0;
    }
}

test "gpu mesh instance layout stores model matrix" {
    try std.testing.expectEqual(@as(usize, 64), @sizeOf(types.GpuMeshInstance));
}

test "gpu grass instance layout stays tightly packed" {
    try std.testing.expectEqual(@as(usize, 64), @sizeOf(types.GpuGrassInstance));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(types.GpuGrassInstance, "position"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(types.GpuGrassInstance, "normal_height"));
    try std.testing.expectEqual(@as(usize, 32), @offsetOf(types.GpuGrassInstance, "color"));
    try std.testing.expectEqual(@as(usize, 48), @offsetOf(types.GpuGrassInstance, "blade"));
}
