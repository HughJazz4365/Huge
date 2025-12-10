const std = @import("std");
const huge = @import("../../root.zig");
const util = huge.util;
const vulkan = @import("vulkan.zig");
const vk = @import("vk.zig");

const DeviceAllocator = @This();

const base_block_size = 128 * util.MiB;
const persistent_block_size = 4 * util.MiB;
const persistent_urgent_block_size = 256 * util.KiB;

const stack_block_count = (4 * util.GiB) / base_block_size;

var stack_blocks: [stack_block_count]MemoryBlock = undefined;
var capacity: usize = stack_block_count;

var blocks: []MemoryBlock = stack_blocks[0..0];
pub fn bind(handle: union(enum) {
    buffer: vk.Buffer,
    image: vk.Image,
}, allocation: DeviceAllocation, offset: u64) Error!void {
    const device_memory = blocks[allocation.block_index].device_memory;
    const off = allocation.offset + offset;
    switch (handle) {
        .buffer => |buffer| vulkan.device.bindBufferMemory(buffer, device_memory, off) catch |err|
            return vulkan.wrapMemoryErrors(err),
        .image => |image| vulkan.device.bindImageMemory(image, device_memory, off) catch |err|
            return vulkan.wrapMemoryErrors(err),
    }
}
pub fn map(allocation: DeviceAllocation, offset: u64, size: u64) Error![]u8 {
    const off = allocation.offset + offset;
    const block = &blocks[allocation.block_index];
    if (block.map_counts == 0) {
        if (block.type == .persistent or block.type == .persistent_small) {
            block.mapping = try mapDeviceMemory(block.device_memory, 0, block.size);
            block.map_counts = 1;
            return block.mapping[off .. off + size];
        } else {
            block.mapping = try mapDeviceMemory(block.device_memory, off, size);
            block.map_counts = 1;
            return block.mapping;
        }
    } else if (block.type == .persistent or block.type == .persistent_small) {
        block.map_counts += 1;
        return block.mapping[off .. off + size];
    } else return Error.MemoryMapFailed;
}
pub fn unmap(allocation: DeviceAllocation) void {
    if (blocks[allocation.block_index].map_counts == 0) return;
    blocks[allocation.block_index].map_counts -= 1;
    if (blocks[allocation.block_index].map_counts == 0) {
        vulkan.device.unmapMemory(blocks[allocation.block_index].device_memory);
    }
}
fn mapDeviceMemory(device_memory: vk.DeviceMemory, offset: u64, size: u64) Error![]u8 {
    return @as([*]u8, @ptrCast((vulkan.device.mapMemory(device_memory, offset, size, .{}) catch |err| switch (err) {
        error.OutOfDeviceMemory => return Error.OutOfDeviceMemory,
        error.MemoryMapFailed => return Error.MemoryMapFailed,
        else => return Error.OutOfMemory,
    }) orelse return Error.MemoryMapFailed))[0..size];
}

pub fn allocateDeviceMemory(requirements: vk.MemoryRequirements, memory_type: MemoryType) Error!DeviceAllocation {
    var index: usize = 0;
    var best_score: i32 = -1;
    for (blocks, 0..) |block, i| {
        const score = memory_type.score(block.flags) *
            (@as(i32, @intFromBool(block.type == memory_type)) * 2 + 1);
        const fits = util.rut(u64, block.offset, requirements.alignment) + requirements.size <= block.size;
        if (best_score >= score and fits and
            (requirements.memory_type_bits & (@as(u32, 1) << block.memory_type_index)) != 0)
        {
            best_score = score;
            index = i;
        }
    }
    if (best_score < 0) {
        index = blocks.len;
        if (blocks.len >= capacity) {
            capacity *= 2;
            blocks = (try vulkan.arena.allocator().alloc(MemoryBlock, capacity))[0 .. blocks.len + 1];
        } else blocks.len += 1;

        var memory_type_index: u5 = 0;
        var best_memory_type_index_score: i32 = -1;
        for (0..vulkan.physical_device_memory_properties.memory_type_count) |i| {
            if ((requirements.memory_type_bits & (@as(u32, 1) << @intCast(i))) == 0) continue;
            const score = memory_type.score(vulkan.physical_device_memory_properties.memory_types[i].property_flags);
            if (score >= best_memory_type_index_score) {
                best_memory_type_index_score = score;
                blocks[index].flags = vulkan.physical_device_memory_properties.memory_types[i].property_flags;
                memory_type_index = @intCast(i);
            }
        }
        if (best_memory_type_index_score < 0) return Error.OutOfDeviceMemory;
        const size = @max(memory_type.blockSize(), requirements.size);
        blocks[index] = .{
            .type = memory_type,
            .memory_type_index = memory_type_index,
            .flags = blocks[index].flags,
            .size = size,
            .device_memory = vulkan.device.allocateMemory(&.{
                .allocation_size = size,
                .memory_type_index = memory_type_index,
            }, vulkan.vka) catch |err| return vulkan.wrapMemoryErrors(err),
        };
    }
    const aligned_offset = util.rut(u64, blocks[index].offset, requirements.alignment);
    std.debug.print("[{d}]ALLOC: {d:.3} KiB/ {d:.3} KiB(HI: {d}, Off: {d} B, Pad: {d} B)\n", .{
        blocks[index].memory_type_index,
        @as(f64, @floatFromInt(requirements.size)) / 1024.0,
        @as(f64, @floatFromInt(blocks[index].size)) / 1024.0,
        index,
        blocks[index].offset,
        aligned_offset - blocks[index].offset,
    });
    blocks[index].offset = aligned_offset + requirements.size;
    return .{ .block_index = index, .offset = aligned_offset };
}
pub const DeviceAllocation = struct {
    block_index: usize,
    offset: u64,
};

pub const MemoryBlock = struct {
    offset: u64 = 0,
    size: u64 = 0,
    device_memory: vk.DeviceMemory = .null_handle,

    type: MemoryType = .regular,
    flags: vk.MemoryPropertyFlags,
    memory_type_index: u5,

    map_counts: u32 = 0,
    mapping: []u8 = @constCast(&.{}),
};
pub const MemoryType = enum {
    regular, // preferrably device local
    device_only, //must be lazily allocated
    map, //must be host visible
    persistent, //host coherent
    persistent_small, //host coherent, in its own allocation

    pub inline fn mappable(self: MemoryType) bool {
        return self != .regular and self != .device_only;
    }

    pub fn blockSize(self: MemoryType) usize {
        return switch (self) {
            .persistent => persistent_block_size,
            .persistent_small => persistent_urgent_block_size,
            else => base_block_size,
        };
    }
    /// if <0 - compatible
    /// if >=0 - compalible
    pub fn score(memory_type: MemoryType, flags: vk.MemoryPropertyFlags) i32 {
        return switch (memory_type) {
            .regular => @as(i32, @intFromBool(flags.device_local_bit)) -
                @as(i32, @intFromBool(flags.lazily_allocated_bit)) * 2,
            .device_only => @as(i32, @intFromBool(flags.lazily_allocated_bit)) * 2 - 1,
            .map => @as(i32, @intFromBool(flags.host_visible_bit)),
            .persistent, .persistent_small => @as(i32, @intFromBool(flags.host_coherent_bit)),
        };
    }
};
const List = std.ArrayList;
const Error = vulkan.Error;
