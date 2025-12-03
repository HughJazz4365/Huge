const std = @import("std");
const huge = @import("../../root.zig");
const util = huge.util;
const glfw = huge.Window.glfw;

const vk = @import("vk.zig");
pub var bwp: vk.BaseWrapper = undefined;
pub var iwp: vk.InstanceWrapper = undefined;
pub var dwp: vk.DeviceWrapper = undefined;

pub var arena: std.heap.ArenaAllocator = undefined;
var thread_safe_allocator: std.heap.ThreadSafeAllocator = undefined;
const pr = std.debug.print;

//=========|constants|==========

pub const timeout: u64 = std.time.ns_per_s * 5;

//===========|state|============

pub var vka: ?*vk.AllocationCallbacks = null;
pub var api_version: vk.Version = undefined;

pub var instance: vk.InstanceProxy = undefined;

pub var physical_devices: [3]PhysicalDevice = @splat(.{});
pub var valid_physical_device_count: usize = 0;
var current_physical_device_index: usize = 0;
var physical_device_memory_properties: vk.PhysicalDeviceMemoryProperties = undefined;

pub var device: vk.DeviceProxy = undefined;

pub var queues: [queue_type_count]vk.Queue = @splat(.null_handle);
// var command_pools: [queue_type_count]vk.CommandPool = @splat(.null_handle);

//==============================

pub inline fn pd() PhysicalDevice {
    return physical_devices[current_physical_device_index];
}

pub inline fn queue(queue_type: QueueType) vk.Queue {
    return queues[@intFromEnum(queue_type)];
}
pub inline fn qfi(queue_type: QueueType) QFI {
    return pd().queue_family_indices[@intFromEnum(queue_type)];
}

//======|initialization|========

pub fn init(allocator: Allocator, create_queue_configuration: QueueConfiguration) Error!void {
    arena = .init(allocator);
    thread_safe_allocator = .{ .child_allocator = arena.allocator() };

    bwp = .load(loader);
    const minimal_vulkan_version: vk.Version = .{ .major = 1, .minor = 3 };
    const vkinit = @import("vulkanInit.zig");
    const layers: []const [*:0]const u8 = if (huge.zigbuiltin.mode == .Debug) &.{
        "VK_LAYER_KHRONOS_validation",
        // "VK_LAYER_LUNARG_api_dump",
    } else &.{};
    instance = try vkinit.initInstance(minimal_vulkan_version, layers, &.{});

    var extension_name_buf: [10][*:0]const u8 = undefined;
    var device_extension_list: List([*:0]const u8) = .initBuffer(&extension_name_buf);

    device_extension_list.appendAssumeCapacity(vk.extensions.khr_swapchain.name);
    current_physical_device_index = try vkinit.initPhysicalDevices(
        minimal_vulkan_version,
        device_extension_list.items,
        create_queue_configuration,
    );

    physical_device_memory_properties = instance.getPhysicalDeviceMemoryProperties(pd().handle);
    try vkinit.initLogicalDeviceAndQueues(layers, device_extension_list.items, create_queue_configuration);
    pr("{f}\n", .{pd()});
}

pub fn deinit() void {
    defer arena.deinit();
    defer instance.destroyInstance(vka);
    defer device.destroyDevice(vka);
}

//==============================

pub const PhysicalDevice = struct {
    pub const qfi_null: QFI = 0xff;
    handle: vk.PhysicalDevice = .null_handle,
    queue_family_indices: [queue_type_count]QFI = @splat(qfi_null),
    name_storage: [max_name_len]u8 = @splat(0),
    name_len: usize = 0,
    features: FeatureSet = .{},
    type: vk.PhysicalDeviceType = .discrete_gpu,

    pub const max_name_len = 128;

    //     pub fn getUniqueQFIIndex(self: *const PhysicalDevice, queue_type: QueueType) usize {
    //         const qfi = self.queueFamilyIndex(queue_type);
    //         var unique_qfi: [queue_type_count]u8 = @splat(0xff);
    //         var count: usize = 0;

    //         return for (&self.queue_family_indices) |q| {
    //             if (q == qfi) break count;
    //             for (unique_qfi[0..count]) |u| (if (u == q) break) else {
    //                 unique_qfi[count] = q;
    //                 count += 1;
    //             }
    //         } else unreachable;
    //     }
    pub fn format(self: PhysicalDevice, writer: *std.Io.Writer) !void {
        try writer.print("Physical Device({}){{\n", .{self.handle});
        try writer.print("Name: {s}\n", .{self.name_storage[0..self.name_len]});
        try writer.print("Family Queue Indices: {any}\n", .{self.queue_family_indices});
        try writer.print("Type: {}\n", .{self.type});
        try writer.print("Features: {{\n", .{});
        inline for (@typeInfo(Feature).@"enum".fields) |ef|
            try writer.print("\t{s} = {}\n", .{ ef.name, @field(self.features, ef.name) });
        try writer.print("}}", .{});
    }
};
pub const Feature = enum {
    geometry_shaders,
    tessellation_shaders,
    sparse_binding,

    shader_float64,
    shader_int64,
    shader_int16,
};
pub const FeatureSet = huge.util.StructFromEnum(Feature, bool, false, .@"packed");

pub const queue_type_count = util.enumLen(QueueType);
pub const QueueConfiguration = util.StructFromEnum(QueueType, bool, false, .@"packed");
pub const QueueType = enum(u8) { graphics, presentation, compute, transfer, sparse_binding, video_decode, video_encode };
pub const QFI = u8;

pub const loader = &struct {
    pub fn l(i: vk.Instance, name: [*:0]const u8) ?glfw.VKproc {
        return glfw.getInstanceProcAddress(@intFromEnum(i), name);
    }
}.l;

//==============================

const Allocator = std.mem.Allocator;
const List = std.ArrayList;
pub const WindowContext = @import("VulkanWindowContext.zig");

pub const Error = error{
    InitializationFailure,
    UnsupportedApiVersion,

    UnavailableExtension,
    UnavailableLayer,
    PhysicalDeviceInitializationFailure,
    NoCompatiblePhysicalDevices,
    DummyWindowCreationFailure,
    DeviceInitializationFailure,
    WindowContextCreationError,

    OutOfMemory,
    OutOfDeviceMemory,
};
