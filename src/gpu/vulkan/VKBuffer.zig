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
descriptor_id: vulkan.DescriptorID = .null,

pub fn createValue(
    value: anytype,
    usage: BufferUsage,
    memory_type: vulkan.MemoryType,
) Error!VKBuffer {
    const tinfo = @typeInfo(@TypeOf(value));
    const T = if (tinfo == .pointer) tinfo.pointer.child else @TypeOf(value);
    const size: u64 = @sizeOf(T);
    var buffer: VKBuffer = try .create(size, usage, memory_type);
    try buffer.load(value, 0);
    return buffer;
}
pub fn load(self: *VKBuffer, value: anytype, offset: u64) Error!void {
    const tinfo = @typeInfo(@TypeOf(value));
    const bytes: []const u8 = @ptrCast(@alignCast(if (tinfo == .pointer) value else &value));
    try self.loadBytes(bytes, offset);
}
pub fn loadBytes(self: *VKBuffer, bytes: []const u8, offset: u64) Error!void {
    const memory_type = vulkan.device_allocator.blocks[self.allocation.block_index].type;
    if (memory_type == .regular or memory_type == .device_only)
        @panic("TODO: load buffer through staging buffer if not mappable");

    //fallback to staging buffer thing if map fails(already mapped etc)
    const mapped = try self.map(offset);
    const len = @min(mapped.len, bytes.len);
    @memcpy(mapped[0..len], bytes[0..len]);
    self.unmap();
}
pub fn map(self: *VKBuffer, offset: u64) Error![]u8 {
    return try vulkan.device_allocator.map(self.allocation, offset, self.size);
}
pub fn unmap(self: *VKBuffer) void {
    return vulkan.device_allocator.unmap(self.allocation);
}

pub fn create(
    size: u64,
    usage: BufferUsage,
    memory_type: vulkan.MemoryType,
) Error!VKBuffer {
    const handle = vulkan.device.createBuffer(&.{
        .flags = .{},
        .size = size,
        .usage = castBufferUsage(usage),
        .sharing_mode = .exclusive,
    }, vulkan.vka) catch |err|
        return vulkan.wrapMemoryErrors(err);

    const allocation = try vulkan.allocateDeviceMemory(
        vulkan.device.getBufferMemoryRequirements(handle),
        memory_type,
    );
    try vulkan.device_allocator.bind(.{ .buffer = handle }, allocation, 0);
    return .{
        .handle = handle,
        .size = size,
        .allocation = allocation,
        .usage = usage,
    };
}

pub const BufferUsage = util.StructFromEnum(enum {
    transfer_src,
    transfer_dst,
    storage,
    uniform,
    index,
    vertex,
    indirect,
}, bool, false, .@"packed");
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
