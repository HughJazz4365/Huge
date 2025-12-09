const std = @import("std");
const vk = @import("vk.zig");
const vulkan = @import("vulkan.zig");
const huge = @import("../../root.zig");
const util = huge.util;

pub const VKBuffer = @This();

handle: vk.Buffer = .null_handle,
allocation: vulkan.DeviceAllocation,
size: u64 = 0,

usage: BufferUsage = .{},

pub fn create(
    size: u64,
    usage: BufferUsage,
    memory_flags: vulkan.MemoryFlags,
) Error!VKBuffer {
    const handle = vulkan.device.createBuffer(&.{
        .flags = .{},
        .size = size,
        .usage = castBufferUsage(usage),
        .sharing_mode = .exclusive,
    }, vulkan.vka) catch |err|
        return vulkan.wrapMemoryErrors(err);

    return .{
        .handle = handle,
        .size = size,
        .allocation = try vulkan.allocateDeviceMemory(
            vulkan.device.getBufferMemoryRequirements(handle),
            memory_flags,
        ),
        .usage = usage,
    };
}

pub const BufferUsage = packed struct {
    transfer_src: bool = false,
    transfer_dst: bool = false,
    uniform: bool = false,
    storage: bool = false,
    index: bool = false,
    vertex: bool = false,
    indirect: bool = false,
};
fn castBufferUsage(usage: BufferUsage) vk.BufferUsageFlags {
    return .{
        .transfer_src_bit = usage.transfer_src,
        .transfer_dst_bit = usage.transfer_dst,
        .uniform_buffer_bit = usage.uniform,
        .storage_buffer_bit = usage.storage,
        .index_buffer_bit = usage.index,
        .vertex_buffer_bit = usage.vertex,
        .indirect_buffer_bit = usage.indirect,
    };
}
const Error = vulkan.Error;
