const std = @import("std");
const huge = @import("../../root.zig");
const util = huge.util;
const vulkan = @import("vulkan.zig");
const vk = @import("vk.zig");

pub fn allocateDeviceMemory(
    memory_requirements: vk.MemoryRequirements,
    flags: MemoryFlags,
) Error!DeviceAllocation {
    const vk_flags = flags.cast();
    const memory_type_index: u32 = for (0..vulkan.physical_device_memory_properties.memory_type_count) |i| {
        if ((memory_requirements.memory_type_bits & (@as(u32, 1) << @as(u5, @intCast(i)))) == 0) continue;
        if (vulkan.physical_device_memory_properties.memory_types[i].property_flags.contains(vk_flags))
            break @intCast(i);
    } else return Error.OutOfDeviceMemory;

    const heap_index: usize = for (vulkan.heaps.items, 0..) |*heap, i| {
        if (heap.memory_type_index == memory_type_index and
            heap.size - heap.consumed >= memory_requirements.size) break i;
    } else blk: {
        try expandHeapsIfNeeded();
        const is_special = flags.host_coherent or flags.host_visible or flags.device_local;
        const allocation_size: u64 = @max(
            if (is_special)
                MemoryHeap.special_size
            else
                MemoryHeap.general_size,
            memory_requirements.size,
        );
        vulkan.heaps.appendAssumeCapacity(.{
            .device_memory = vulkan.device.allocateMemory(&.{
                .allocation_size = allocation_size,
                .memory_type_index = memory_type_index,
            }, vulkan.vka) catch return Error.OutOfDeviceMemory,
            .size = allocation_size,
            .memory_type_index = memory_type_index,
        });
        break :blk vulkan.heaps.items.len - 1;
    };
    const aligned_offset = util.rut(u64, vulkan.heaps.items[heap_index].consumed, memory_requirements.alignment);
    std.debug.print("ALLOC: {d} KiB(+frag = {d} B)\n", .{
        @as(f64, @floatFromInt(memory_requirements.size)) / 1024.0,
        aligned_offset - vulkan.heaps.items[heap_index].consumed,
    });
    vulkan.heaps.items[heap_index].consumed = aligned_offset + memory_requirements.size;

    return .{ .heap_index = heap_index, .offset = aligned_offset };
}
fn expandHeapsIfNeeded() Error!void {
    if (vulkan.heaps.items.len == vulkan.heaps.capacity) {
        @branchHint(.cold);
        const new_buffer = try vulkan.arena.allocator().alloc(MemoryHeap, vulkan.heaps.capacity * 2);
        @memcpy(new_buffer[0..vulkan.heaps.items.len], vulkan.heaps.items);
        vulkan.heaps = .{
            .items = new_buffer[0..vulkan.heaps.items.len],
            .capacity = new_buffer.len,
        };
    }
}
pub const DeviceAllocation = struct {
    heap_index: usize,
    offset: u64 = 0,
};
pub const MemoryHeap = struct {
    device_memory: vk.DeviceMemory = .null_handle,
    consumed: u64 = 0,
    size: u64,

    memory_type_index: u32,
    //store fragmented regions

    pub const general_size: u64 = 128 * MiB;
    pub const special_size: u64 = 64 * MiB;

    pub const MiB = 1024 * 1024;
};

pub const MemoryFlags = packed struct {
    device_local: bool = false,
    host_visible: bool = false,
    host_coherent: bool = false,
    pub fn cast(self: MemoryFlags) vk.MemoryPropertyFlags {
        return .{
            .device_local_bit = self.device_local,
            .host_visible_bit = self.host_visible,
            .host_coherent_bit = self.host_coherent,
        };
    }
};
const Error = vulkan.Error;
const List = std.ArrayList;
