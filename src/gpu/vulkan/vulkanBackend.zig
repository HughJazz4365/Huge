const std = @import("std");
const zigbuiltin = @import("builtin");
const huge = @import("../../root.zig");
const util = huge.util;
const gpu = huge.gpu;
const hgsl = gpu.hgsl;

const vk = @import("vk.zig");

//=====|constants|======

const max_queue_family_count = 16;
const max_physical_devices = 3;
const min_vulkan_version: Version = .{ .major = 1, .minor = 3 };
const layers: []const [*:0]const u8 = if (zigbuiltin.mode == .Debug) &.{
    "VK_LAYER_KHRONOS_validation",
    // "VK_LAYER_LUNARG_api_dump",
} else &.{};

//=======|state|========

var vka: ?*vk.AllocationCallbacks = null;

var instance: vk.InstanceProxy = undefined;
var physical_devices: [max_physical_devices]PhysicalDevice = @splat(.{});
var valid_physical_device_count: usize = 0;
var current_physical_device_index: usize = 0;
var device: vk.DeviceProxy = undefined;

pub var bwp: vk.BaseWrapper = undefined;
pub var iwp: vk.InstanceWrapper = undefined;
pub var dwp: vk.DeviceWrapper = undefined;
// var queues: [queue_type_count]vk.Queue = undefined;
//
inline fn pd() PhysicalDevice {
    return physical_devices[current_physical_device_index];
}

var shader_compiler: hgsl.Compiler = undefined;

//======|methods|========

fn createPipeline(stages: []const gpu.ShaderModule) Error!Pipeline {
    _ = stages;
    return @enumFromInt(0);
}

//===|initialization|====

pub fn initBackend() VKError!gpu.Backend {
    bwp = .load(loader);
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer _ = arena.deinit();

    const instance_api_version = castVersion(@bitCast(bwp.enumerateInstanceVersion() catch return error.OutOfMemory));
    if (!instance_api_version.@">="(min_vulkan_version))
        return VKError.UnsupportedApiVersion;
    try initInstance(arena.allocator(), instance_api_version);

    const device_extensions: []const [*:0]const u8 = &.{
        vk.extensions.khr_swapchain.name,
    }; //optional extensions
    try initPhysicalDevices(arena.allocator(), device_extensions);
    const physical_device_api_version = castVersion(@bitCast(instance.getPhysicalDeviceProperties(pd().handle).api_version));

    const api_version = if (physical_device_api_version.@">="(instance_api_version)) instance_api_version else physical_device_api_version;
    shader_compiler = .new(null, null, .{ .target_env = .vulkan1_4 });
    return versionBackend(api_version);
}

fn deinit() void {
    shader_compiler.deinit();
}

fn initInstance(allocator: Allocator, api_version: Version) VKError!void {
    const available_layers: []vk.LayerProperties =
        if (layers.len > 0) bwp.enumerateInstanceLayerPropertiesAlloc(allocator) catch return VKError.OutOfMemory else &.{};

    for (layers) |l| { //check for unavailable layers
        if (!for (available_layers) |al| {
            if (huge.util.strEqlNullTerm(l, @ptrCast(@alignCast(&al.layer_name)))) break true;
        } else false) return VKError.UnavailableLayer; //TODO: log the layer name
    }

    var glfw_ext_count: u32 = 0; //get platform presentation extensions
    const glfw_exts = glfw.getRequiredInstanceExtensions(&glfw_ext_count);
    const instance_extensions: []const [*:0]const u8 = if (glfw_exts) |ge| ge[0..glfw_ext_count] else &.{};

    const available_instance_extensions: []vk.ExtensionProperties =
        bwp.enumerateInstanceExtensionPropertiesAlloc(null, allocator) catch return VKError.OutOfMemory;
    try checkExtensionPresence(instance_extensions, available_instance_extensions);
    allocator.free(available_instance_extensions);

    const app_info: vk.ApplicationInfo = .{
        .p_application_name = huge.name ++ " app",
        .application_version = @bitCast(@as(u32, 0)),
        .p_engine_name = huge.name,
        .engine_version = toVulkanVersion(huge.version),
        .api_version = toVulkanVersion(api_version),
    };
    const instance_create_info: vk.InstanceCreateInfo = .{
        .p_application_info = &app_info,
        .enabled_extension_count = @intCast(instance_extensions.len),
        .pp_enabled_extension_names = instance_extensions.ptr,
        .enabled_layer_count = @intCast(layers.len),
        .pp_enabled_layer_names = layers.ptr,
    };
    const instance_handle = bwp.createInstance(&instance_create_info, vka) catch return VKError.InstanceInitializationFailure;

    iwp = .load(instance_handle, loader);
    instance = .init(instance_handle, &iwp);
}
fn initPhysicalDevices(allocator: Allocator, extensions: []const [*:0]const u8) VKError!void {
    var count: u32 = 0;
    _ = instance.enumeratePhysicalDevices(&count, null) catch
        return VKError.PhysicalDeviceInitializationFailure;

    if (count == 0) return error.PhysicalDeviceInitializationFailure;

    count = @min(max_physical_devices, count);
    var physical_device_handles: [max_physical_devices]vk.PhysicalDevice = undefined;
    _ = instance.enumeratePhysicalDevices(&count, &physical_device_handles) catch
        return VKError.PhysicalDeviceInitializationFailure;
    for (&physical_devices, &physical_device_handles) |*p, *ph| p.handle = ph.*;

    // create dummy window to use its surface
    // for physical device initialization
    const dummy_window = huge.Window.createDummy(@intFromEnum(instance.handle)) catch
        return VKError.DummyWindowCreationFailure;
    defer {
        instance.destroySurfaceKHR(@enumFromInt(dummy_window.surface_handle), vka);
        glfw.destroyWindow(dummy_window.handle);
    }

    valid_physical_device_count = count;
    var i: usize = 0;
    while (i < valid_physical_device_count) : (i += 1)
        initPhysicalDevice(allocator, &physical_devices[i], extensions, dummy_window) catch {
            valid_physical_device_count -= 1;
            std.mem.swap(PhysicalDevice, &physical_devices[i], &physical_devices[valid_physical_device_count]);
            i -= 1;
            continue; //remove from the array if initializaiton failed
        };
    if (valid_physical_device_count == 0) return VKError.PhysicalDeviceInitializationFailure;

    var max_score: u32 = 0; //pick best physical device
    //add ability to overwrite current physical device index
    for (physical_devices[0..valid_physical_device_count], 0..) |p, index| {
        const score = scorePhysicalDevice(p);
        if (score > max_score) {
            current_physical_device_index = index;
            max_score = score;
        }
    }
}

fn scorePhysicalDevice(physical_device: PhysicalDevice) u32 {
    var score: u32 = 0;
    score = switch (physical_device.type) {
        .discrete_gpu => 4000,
        .integrated_gpu => 3000,
        .virtual_gpu => 2000,
        .cpu => 1000,
        else => 1,
    };
    if (physical_device.features.geometry_shaders) score += 100;
    if (physical_device.features.tessellation_shaders) score += 100;
    return score;
}

fn initPhysicalDevice(allocator: Allocator, p: *PhysicalDevice, extensions: []const [*:0]const u8, dummy_window: huge.Window.DummyWindow) VKError!void {
    p.features = getPhysicalDeviceFeatures(p.handle);

    const properties = instance.getPhysicalDeviceProperties(p.handle); //limits?
    if (!castVersion(@bitCast(properties.api_version)).@">="(min_vulkan_version))
        return VKError.UnsupportedApiVersion;

    p.type = properties.device_type;
    p.name_len = @min(
        std.mem.len(@as([*:0]const u8, @ptrCast(@alignCast(&properties.device_name)))),
        PhysicalDevice.max_name_len,
    );
    @memcpy(p.name_storage[0..p.name_len], properties.device_name[0..p.name_len]);

    const available_extensions =
        instance.enumerateDeviceExtensionPropertiesAlloc(p.handle, null, allocator) catch return VKError.OutOfMemory;
    try checkExtensionPresence(extensions, available_extensions);
    allocator.free(available_extensions);

    p.queue_family_indices =
        try getQueueFamilyIndices(allocator, p.handle, dummy_window);
}
fn getQueueFamilyIndices(allocator: Allocator, handle: vk.PhysicalDevice, dummy_window: huge.Window.DummyWindow) VKError![queue_type_count]u8 {
    const queue_family_properties = instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(handle, allocator) catch
        return VKError.OutOfMemory;
    defer allocator.free(queue_family_properties);

    var index_lists: [queue_type_count]IndexList = undefined;

    for (&index_lists) |*l| l.init();

    for (queue_family_properties, 0..) |qfp, i| {
        const flags: QueueConfiguration = .{
            .graphics = qfp.queue_flags.graphics_bit,
            .compute = qfp.queue_flags.compute_bit,
            .transfer = qfp.queue_flags.transfer_bit,
            .sparse_binding = qfp.queue_flags.sparse_binding_bit,
            .protected = qfp.queue_flags.protected_bit,
            .video_decode = qfp.queue_flags.video_decode_bit_khr,
            .video_encode = qfp.queue_flags.video_encode_bit_khr,
            .optical_flow = qfp.queue_flags.optical_flow_bit_nv,
            .presentation = @intFromEnum(instance.getPhysicalDeviceSurfaceSupportKHR(handle, @intCast(i), @enumFromInt(dummy_window.surface_handle)) catch .false) > 0,
        };
        inline for (@typeInfo(QueueType).@"enum".fields, 0..) |ef, j|
            if (@field(flags, ef.name))
                index_lists[j].append(@intCast(i));
    }
    //check for minimal reqired queues
    var any_flags: QueueConfiguration = .{};
    inline for (@typeInfo(QueueType).@"enum".fields, 0..) |ef, i| {
        // check if there are any queue families
        // at the index corresponding to that queue
        @field(any_flags, ef.name) = index_lists[i].list.items.len > 0;
    }
    if (!util.matchFlagStructs(
        QueueConfiguration,
        any_flags,
        minimal_required_queue_family_config,
    )) return VKError.MissingQueueType;

    // inline for (&index_lists, 0..) |l, i| {
    //     std.debug.print("{s} : {any}\n", .{ @tagName(@as(QueueType, @enumFromInt(i))), l.list.items });
    // }

    //iterate through all the possible queue configurations score them and use the best one
    var non_empty_index_storage: [queue_type_count]usize = undefined;
    var count: usize = 0;
    //use this to avoid iterating through queue families that have no available queue
    for (&index_lists, 0..) |*l, i| {
        if (l.list.items.len > 0) {
            non_empty_index_storage[count] = i;
            count += 1;
        }
    }
    var max_score: i32 = std.math.minInt(i32);
    var current_queue_family_indices: [queue_type_count]u8 = @splat(0xff);

    var queue_family_indices: [queue_type_count]u8 = @splat(0xff);
    findBestQueueConfiguration(
        &queue_family_indices,
        index_lists,
        non_empty_index_storage[0..count],
        &current_queue_family_indices,
        0,
        &max_score,
    );
    return queue_family_indices;
}

const IndexList = struct {
    list: std.ArrayList(u8),
    buf: [max_queue_family_count]u8,
    pub fn init(self: *IndexList) void {
        self.list = .initBuffer(&self.buf);
    }
    pub fn append(self: *IndexList, i: u8) void {
        self.list.appendAssumeCapacity(i);
    }
};
fn findBestQueueConfiguration(
    out: *[queue_type_count]u8,
    index_lists: [queue_type_count]IndexList,
    non_empty_indices: []usize,
    current: *[queue_type_count]u8,
    depth: usize,
    max_score: *i32,
) void {
    if (depth == non_empty_indices.len) {
        const score = scoreQueueConfiguration(current);
        if (score > max_score.*) {
            max_score.* = score;
            //copy the best into the global storage
            out.* = current.*;
        }
        return;
    }
    const index = non_empty_indices[depth];
    for (index_lists[index].list.items) |value| {
        current[index] = value;
        findBestQueueConfiguration(
            out,
            index_lists,
            non_empty_indices,
            current,
            depth + 1,
            max_score,
        );
    }
}
fn scoreQueueConfiguration(configuration: []u8) i32 {
    var score: i32 = 0;
    inline for (queueConfigurationScoringRules) |rule| {
        const values: [2]u8 = .{
            configuration[@intFromEnum(rule[1][0])],
            configuration[@intFromEnum(rule[1][1])],
        };
        if (values[0] == values[1] and ~values[0] != 0) score += rule[0];
    }
    return score;
}
fn getPhysicalDeviceFeatures(handle: vk.PhysicalDevice) gpu.FeatureSet {
    const vk_features = instance.getPhysicalDeviceFeatures(handle);
    return .{
        .geometry_shaders = vk_features.geometry_shader != .false,
        .tessellation_shaders = vk_features.tessellation_shader != .false,
        .shader_float64 = vk_features.shader_float_64 != .false,
        .shader_int64 = vk_features.shader_int_64 != .false,
        .shader_int16 = vk_features.shader_int_16 != .false,
    };
}
const PhysicalDevice = struct {
    handle: vk.PhysicalDevice = .null_handle,
    queue_family_indices: [queue_type_count]u8 = @splat(0xff),
    name_storage: [max_name_len]u8 = @splat(0),
    name_len: usize = 0,
    features: gpu.FeatureSet = .{},
    type: vk.PhysicalDeviceType = .discrete_gpu,

    pub const max_name_len = 128;
    pub fn format(self: PhysicalDevice, writer: *std.Io.Writer) !void {
        try writer.print("Physical Device({}){{\n", .{self.handle});
        try writer.print("Name: {s}\n", .{self.name_storage[0..self.name_len]});
        try writer.print("Family Queue Indices: {any}\n", .{self.queue_family_indices});
        try writer.print("Type: {}\n", .{self.type});
        try writer.print("Features: {{\n", .{});
        inline for (@typeInfo(gpu.Feature).@"enum".fields) |ef|
            try writer.print("\t{s} = {}\n", .{ ef.name, @field(self.features, ef.name) });
        try writer.print("}}", .{});
    }
};
fn checkExtensionPresence(required: []const [*:0]const u8, available: []const vk.ExtensionProperties) VKError!void {
    for (required) |e| { //chech for unavailable instance extensions
        if (!for (available) |ae| {
            if (huge.util.strEqlNullTerm(e, @ptrCast(@alignCast(&ae.extension_name)))) break true;
        } else false) return VKError.UnavailableExtension; //TODO: log the layer name
    }
}

//=======================

pub const queue_type_count = @typeInfo(QueueType).@"enum".fields.len;
const QueueConfiguration = util.StructFromEnum(QueueType, bool, false, .@"packed");
const queueConfigurationScoringRules: []const std.meta.Tuple(&.{ i32, [2]QueueType }) = &.{
    .{ -150, .{ .graphics, .compute } },
    .{ -150, .{ .graphics, .transfer } },
    .{ 100, .{ .graphics, .presentation } },
    .{ -90, .{ .compute, .transfer } },
    .{ 30, .{ .sparse_binding, .transfer } },
};
pub const minimal_required_queue_family_config: QueueConfiguration = .{
    .graphics = true,
    .presentation = true,
    .transfer = true,
    .compute = true,
};
pub const QueueType = enum(u8) { graphics, presentation, compute, transfer, sparse_binding, protected, video_decode, video_encode, optical_flow };

//=======================
fn versionBackend(version: Version) gpu.Backend {
    return .{
        .api = .vulkan,
        .api_version = version,
        .deinit = &deinit,
        .createPipeline = &createPipeline,
    };
}
pub const loader = &struct {
    pub fn l(i: vk.Instance, name: [*:0]const u8) ?glfw.VKproc {
        return glfw.getInstanceProcAddress(@intFromEnum(i), name);
    }
}.l;
fn castVersion(vk_version: vk.Version) Version {
    return .{
        .major = vk_version.major,
        .minor = vk_version.minor,
    };
}
fn toVulkanVersion(version: Version) u32 {
    return @bitCast(vk.makeApiVersion(0, @truncate(version.major), @truncate(version.minor), 0));
}
const VKError = error{
    OutOfMemory,

    UnavailableExtension,
    UnsupportedApiVersion,
    UnavailableLayer,

    InstanceInitializationFailure,
    PhysicalDeviceInitializationFailure,
    DummyWindowCreationFailure,
    MissingQueueType,
};
const glfw = huge.Window.glfw;
const Error = gpu.Error;
const Pipeline = gpu.Pipeline;
const Version = huge.Version;
const Allocator = std.mem.Allocator;
