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
mapping: ?[*]u8 = null,

descriptor_id: vulkan.DescriptorID = .null,

pub fn createValue(
    value: anytype,
    usage: BufferUsage,
    memory_flags: vulkan.MemoryFlags,
) Error!VKBuffer {
    const tinfo = @typeInfo(@TypeOf(value));
    const T = if (tinfo == .pointer) tinfo.pointer.child else @TypeOf(value);
    const size: u64 = @sizeOf(T);
    var mem_flags = memory_flags;
    mem_flags.add(.{ .host_visible = true });
    var buffer: VKBuffer = try .create(size, usage, mem_flags);
    try buffer.load(value, 0);
    return buffer;
}
pub fn load(self: *VKBuffer, value: anytype, offset: u64) Error!void {
    const tinfo = @typeInfo(@TypeOf(value));
    const bytes: []const u8 = @ptrCast(@alignCast(if (tinfo == .pointer) value else &value));
    try self.loadBytes(bytes, offset);
}
pub fn loadBytes(self: *VKBuffer, bytes: []const u8, offset: u64) Error!void {
    const mapped = try self.map(offset);
    const len = @min(mapped.len, bytes.len);
    @memcpy(mapped[0..len], bytes[0..len]);
    self.unmap();
}
pub fn map(self: *VKBuffer, offset: u64) Error![]u8 {
    if (self.mapping) |m| return m[0..self.size];

    huge.dassert(vulkan.heaps.items[self.allocation.heap_index].memory_flags.host_visible);
    const ptr: [*]u8 = @ptrCast((vulkan.device.mapMemory(
        vulkan.heaps.items[self.allocation.heap_index].device_memory,
        self.allocation.offset + offset,
        self.size,
        .{},
    ) catch |err| return switch (err) {
        error.MemoryMapFailed => Error.MemoryMapFailed,
        error.OutOfDeviceMemory => Error.OutOfDeviceMemory,
        else => Error.OutOfMemory,
    }) orelse return Error.MemoryMapFailed);
    self.mapping = ptr;

    return ptr[0..self.size];
}
pub fn unmap(self: *VKBuffer) void {
    if (self.mapping) |_|
        vulkan.device.unmapMemory(vulkan.heaps.items[self.allocation.heap_index].device_memory);
}

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

    const allocation = try vulkan.allocateDeviceMemory(
        vulkan.device.getBufferMemoryRequirements(handle),
        memory_flags,
    );
    vulkan.device.bindBufferMemory(
        handle,
        vulkan.heaps.items[allocation.heap_index].device_memory,
        allocation.offset,
    ) catch |err| return vulkan.wrapMemoryErrors(err);
    return .{
        .handle = handle,
        .size = size,
        .allocation = allocation,
        .usage = usage,
    };
}

pub const BufferUsage = packed struct {
    transfer_src: bool = false,
    transfer_dst: bool = false,
    storage: bool = false,
    uniform: bool = false,
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
