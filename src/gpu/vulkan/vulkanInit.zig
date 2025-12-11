const std = @import("std");
const huge = @import("../../root.zig");
const vulkan = @import("vulkan.zig");
const util = huge.util;
const glfw = huge.Window.glfw;

const vk = @import("vk.zig");

const Names = []const [*:0]const u8;
//this need allocation size tracking

pub fn getArenaAllocationCallbacks(arena: *std.heap.ArenaAllocator) vk.AllocationCallbacks {
    // pfn_reallocation:
    // vk.PfnReallocationFunction,
    // pfn_free:
    // vk.PfnFreeFunction,
    // pfn_internal_allocation:
    // vk.PfnInternalAllocationNotification = null,
    // pfn_internal_free:
    // vk.PfnInternalFreeNotification = null,

    const S = struct {
        pub fn allocate(
            user_data: ?*anyopaque,
            size: usize,
            alignment: usize,
            _: vk.SystemAllocationScope,
        ) callconv(vk.vulkan_call_conv) ?*anyopaque {
            const arena_ptr: *std.heap.ArenaAllocator = @ptrCast(@alignCast(user_data.?));
            return @ptrCast((switch (alignment) {
                else => arena_ptr.allocator().alignedAlloc(u8, .@"1", size),
                2 => arena_ptr.allocator().alignedAlloc(u8, .@"2", size),
                4 => arena_ptr.allocator().alignedAlloc(u8, .@"4", size),
                8 => arena_ptr.allocator().alignedAlloc(u8, .@"8", size),
                16 => arena_ptr.allocator().alignedAlloc(u8, .@"16", size),
                32 => arena_ptr.allocator().alignedAlloc(u8, .@"32", size),
                64 => arena_ptr.allocator().alignedAlloc(u8, .@"64", size),
            }) catch return null);
        }
        pub fn free(_: ?*anyopaque, _: ?*anyopaque) callconv(vk.vulkan_call_conv) void {
            // const arena_ptr: *std.heap.ArenaAllocator = @ptrCast(@alignCast(user_data.?));
            // if (memory) |mem| arena_ptr.allocator().free(@as([*]u8, @ptrCast(mem)));
        }
        pub fn realloc(
            user_data: ?*anyopaque,
            original: ?*anyopaque,
            size: usize,
            alignment: usize,
            _: vk.SystemAllocationScope,
        ) callconv(vk.vulkan_call_conv) ?*anyopaque {
            const arena_ptr: *std.heap.ArenaAllocator = @ptrCast(@alignCast(user_data.?));
            _ = .{ user_data, original, size, alignment, arena_ptr };
        }
    };
    return .{
        .p_user_data = @ptrCast(@alignCast(arena)),
        .pfn_allocation = &S.allocate,
        .pfn_reallocation = null,
        .pfn_free = &S.free,
        .pfn_internal_allocation = null,
    };
}
pub fn initLogicalDeviceAndQueues(layers: Names, extensions: Names, create_queue_configuration: vulkan.QueueConfiguration) Error!void {
    var queue_create_infos: [vulkan.queue_type_count]vk.DeviceQueueCreateInfo = undefined;
    var queues_to_create: [vulkan.queue_type_count]u8 = undefined;
    var count: usize = 0;

    //create queues for all unique queue families
    inline for (vulkan.pd().queue_family_indices, 0..) |qi, i| {
        const requested_create = @field(create_queue_configuration, @typeInfo(vulkan.QueueType).@"enum".fields[i].name);
        if (requested_create and ~qi != 0) {
            for (0..count) |c| {
                if (queues_to_create[c] == qi) break;
            } else {
                queues_to_create[count] = qi;
                queue_create_infos[count] = .{
                    .queue_count = 1,
                    .queue_family_index = qi,
                    .p_queue_priorities = &.{1.0},
                };
                count += 1;
            }
        }
    }
    //device p_next chain
    const physical_device_features_ptr: *const anyopaque =
        &vk.PhysicalDeviceFeatures2{
            .features = .{
                .image_cube_array = .true,
                .geometry_shader = .true,
                .tessellation_shader = .true,
                .logic_op = .true,
                .multi_draw_indirect = .true,
                .depth_clamp = .true,
                .depth_bias_clamp = .true,
                .fill_mode_non_solid = .true,
                .depth_bounds = .true,
                .wide_lines = .true,
                .large_points = .true,
                .multi_viewport = .true,
                .texture_compression_bc = .true,
                .vertex_pipeline_stores_and_atomics = .true,
                .fragment_stores_and_atomics = .true,
                .shader_tessellation_and_geometry_point_size = .true,
                .shader_storage_image_extended_formats = .true,
                .shader_storage_image_multisample = .true,
                .shader_storage_image_read_without_format = .true,
                .shader_storage_image_write_without_format = .true,
                .shader_uniform_buffer_array_dynamic_indexing = .true,
                .shader_sampled_image_array_dynamic_indexing = .true,
                .shader_storage_buffer_array_dynamic_indexing = .true,
                .shader_storage_image_array_dynamic_indexing = .true,
                .shader_float_64 = .true,
                .shader_int_64 = .true,
                .shader_int_16 = .true,
            },
        };
    const descriptor_indexing_features_ptr: *const anyopaque =
        &vk.PhysicalDeviceDescriptorIndexingFeatures{
            .p_next = @constCast(physical_device_features_ptr),
            .descriptor_binding_partially_bound = .true,
            .runtime_descriptor_array = .true,

            .shader_sampled_image_array_non_uniform_indexing = .true,
            .shader_storage_buffer_array_non_uniform_indexing = .true,
            .shader_storage_image_array_non_uniform_indexing = .true,

            .descriptor_binding_sampled_image_update_after_bind = .true,
            .descriptor_binding_storage_image_update_after_bind = .true,
            .descriptor_binding_storage_buffer_update_after_bind = .true,
        };
    const synchronization2_features_ptr: *const anyopaque =
        &vk.PhysicalDeviceSynchronization2Features{
            .p_next = @constCast(descriptor_indexing_features_ptr),
            .synchronization_2 = .true,
        };

    const dynamic_rendering_features_ptr: *const anyopaque =
        &vk.PhysicalDeviceDynamicRenderingFeatures{
            .p_next = @constCast(synchronization2_features_ptr),
            .dynamic_rendering = .true,
        };

    const device_create_info: vk.DeviceCreateInfo = .{
        .enabled_extension_count = @intCast(extensions.len),
        .pp_enabled_extension_names = extensions.ptr,
        .queue_create_info_count = @intCast(count),
        .p_queue_create_infos = &queue_create_infos,
        .pp_enabled_layer_names = layers.ptr,
        .enabled_layer_count = @intCast(layers.len),

        .p_next = dynamic_rendering_features_ptr,
    };

    const device_handle = vulkan.instance.createDevice(
        vulkan.pd().handle,
        &device_create_info,
        vulkan.vka,
    ) catch return Error.InitializationFailure;
    vulkan.dwp = .load(device_handle, vulkan.instance.wrapper.dispatch.vkGetDeviceProcAddr.?);
    vulkan.device = .init(device_handle, &vulkan.dwp);

    inline for (0..vulkan.queue_type_count) |i| {
        const requested_create = @field(create_queue_configuration, @typeInfo(vulkan.QueueType).@"enum".fields[i].name);
        if (~vulkan.pd().queue_family_indices[i] != 0 and requested_create)
            vulkan.queues[i] = vulkan.device.getDeviceQueue(vulkan.pd().queue_family_indices[i], 0);
    }
}
pub fn initPhysicalDevices(
    minimal_vulkan_version: vk.Version,
    extensions: Names,
    minimal_queue_configuration: vulkan.QueueConfiguration,
) Error!usize {
    var count: u32 = 0;
    _ = vulkan.instance.enumeratePhysicalDevices(&count, null) catch
        return Error.InitializationFailure;

    if (count == 0) return Error.NoCompatiblePhysicalDevices;

    count = @min(vulkan.physical_devices.len, count);
    var physical_device_handles: [vulkan.physical_devices.len]vk.PhysicalDevice = undefined;
    _ = vulkan.instance.enumeratePhysicalDevices(&count, &physical_device_handles) catch
        return Error.InitializationFailure;
    for (&vulkan.physical_devices, &physical_device_handles) |*p, *ph| p.handle = ph.*;

    // create dummy window to use its surface
    // for physical device initialization
    const dummy_window = huge.Window.createDummy(@intFromEnum(vulkan.instance.handle)) catch
        return Error.InitializationFailure;
    defer {
        vulkan.instance.destroySurfaceKHR(@enumFromInt(dummy_window.surface_handle), vulkan.vka);
        glfw.destroyWindow(dummy_window.handle);
    }

    vulkan.valid_physical_device_count = count;
    var i: usize = 0;
    while (i < vulkan.valid_physical_device_count) : (i += 1)
        initPhysicalDevice(
            &vulkan.physical_devices[i],
            minimal_vulkan_version,
            extensions,
            dummy_window,
            minimal_queue_configuration,
        ) catch {
            vulkan.valid_physical_device_count -= 1;
            std.mem.swap(vulkan.PhysicalDevice, &vulkan.physical_devices[i], &vulkan.physical_devices[vulkan.valid_physical_device_count]);
            i -= 1;
            continue; //remove from the array if initializaiton failed
        };
    if (vulkan.valid_physical_device_count == 0) return Error.NoCompatiblePhysicalDevices;

    var max_score: u32 = 0; //pick best physical device
    var current_physical_device_index: usize = 0;
    //add ability to overwrite current physical device index
    for (vulkan.physical_devices[0..vulkan.valid_physical_device_count], 0..) |p, index| {
        const score = scorePhysicalDevice(p);
        if (score > max_score) {
            current_physical_device_index = index;
            max_score = score;
        }
    }
    return current_physical_device_index;
}

fn scorePhysicalDevice(physical_device: vulkan.PhysicalDevice) u32 {
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

fn initPhysicalDevice(
    p: *vulkan.PhysicalDevice,
    minimal_vulkan_version: vk.Version,
    extensions: Names,
    dummy_window: huge.Window.DummyWindow,
    minimal_queue_configuration: vulkan.QueueConfiguration,
) Error!void {
    p.features = getPhysicalDeviceFeatures(p.handle);

    const properties = vulkan.instance.getPhysicalDeviceProperties(p.handle); //limits?
    if (properties.api_version < @as(u32, @bitCast(minimal_vulkan_version)))
        return Error.UnsupportedApiVersion;

    p.type = properties.device_type;
    p.name_len = @min(
        std.mem.len(@as([*:0]const u8, @ptrCast(@alignCast(&properties.device_name)))),
        vulkan.PhysicalDevice.max_name_len,
    );
    @memcpy(p.name_storage[0..p.name_len], properties.device_name[0..p.name_len]);

    const available_extensions =
        vulkan.instance.enumerateDeviceExtensionPropertiesAlloc(p.handle, null, vulkan.arena.allocator()) catch return Error.OutOfMemory;
    try checkExtensionPresence(extensions, available_extensions);
    vulkan.arena.allocator().free(available_extensions);

    p.queue_family_indices = try getQueueFamilyIndices(p.handle, dummy_window, minimal_queue_configuration);
    p.features.sparse_binding = ~p.queue_family_indices[@intFromEnum(vulkan.QueueType.sparse_binding)] != 0;
}
fn getQueueFamilyIndices(
    handle: vk.PhysicalDevice,
    dummy_window: huge.Window.DummyWindow,
    minimal_queue_configuration: vulkan.QueueConfiguration,
) Error![vulkan.queue_type_count]QFI {
    const queue_family_properties = vulkan.instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(handle, vulkan.arena.allocator()) catch
        return Error.OutOfMemory;
    defer vulkan.arena.allocator().free(queue_family_properties);

    var index_lists: [vulkan.queue_type_count]IndexList = undefined;

    for (&index_lists) |*l| l.init();

    for (queue_family_properties, 0..) |qfp, i| {
        const flags: vulkan.QueueConfiguration = .{
            .graphics = qfp.queue_flags.graphics_bit,
            .presentation = @intFromEnum(vulkan.instance.getPhysicalDeviceSurfaceSupportKHR(handle, @intCast(i), @enumFromInt(dummy_window.surface_handle)) catch .false) > 0,
            .compute = qfp.queue_flags.compute_bit,
            .transfer = qfp.queue_flags.transfer_bit,
            .sparse_binding = qfp.queue_flags.sparse_binding_bit,
            // .protected = qfp.queue_flags.protected_bit,
            .video_decode = qfp.queue_flags.video_decode_bit_khr,
            .video_encode = qfp.queue_flags.video_encode_bit_khr,
        };
        inline for (@typeInfo(vulkan.QueueType).@"enum".fields, 0..) |ef, j|
            if (@field(flags, ef.name))
                index_lists[j].append(@intCast(i));
    }
    //check for minimal reqired queues
    var any_flags: vulkan.QueueConfiguration = .{};
    inline for (@typeInfo(vulkan.QueueType).@"enum".fields, 0..) |ef, i| {
        // check if there are any queue families
        // at the index corresponding to that queue
        @field(any_flags, ef.name) = index_lists[i].list.items.len > 0;
    }
    if (!util.matchFlagStructs(
        vulkan.QueueConfiguration,
        any_flags,
        minimal_queue_configuration,
    )) return Error.InitializationFailure;

    //iterate through all the possible queue configurations score them and use the best one
    var non_empty_index_storage: [vulkan.queue_type_count]usize = undefined;
    var count: usize = 0;
    //use this to avoid iterating through queue families that have no available queue
    for (&index_lists, 0..) |*l, i| {
        if (l.list.items.len > 0) {
            non_empty_index_storage[count] = i;
            count += 1;
        }
    }
    var max_score: QueueFamilyConfigurationScore = std.math.minInt(QueueFamilyConfigurationScore);
    var current_queue_family_indices: [vulkan.queue_type_count]QFI = @splat(vulkan.PhysicalDevice.qfi_null);

    var queue_family_indices: [vulkan.queue_type_count]u8 = @splat(0xff);
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
    const max_queue_family_count = 16;
    list: std.ArrayList(u8),
    buf: [max_queue_family_count]QFI,
    pub fn init(self: *IndexList) void {
        self.list = .initBuffer(&self.buf);
    }
    pub fn append(self: *IndexList, i: u8) void {
        self.list.appendAssumeCapacity(i);
    }
};
fn findBestQueueConfiguration(
    out: *[vulkan.queue_type_count]u8,
    index_lists: [vulkan.queue_type_count]IndexList,
    non_empty_indices: []usize,
    current: *[vulkan.queue_type_count]u8,
    depth: usize,
    max_score: *QueueFamilyConfigurationScore,
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
fn scoreQueueConfiguration(configuration: []QFI) QueueFamilyConfigurationScore {
    var score: QueueFamilyConfigurationScore = 0;
    inline for (queueConfigurationScoringRules) |rule| {
        const values: [2]QFI = .{
            configuration[@intFromEnum(rule[1][0])],
            configuration[@intFromEnum(rule[1][1])],
        };
        if (values[0] == values[1] and ~values[0] != 0) score += rule[0];
    }
    return score;
}
fn getPhysicalDeviceFeatures(handle: vk.PhysicalDevice) vulkan.FeatureSet {
    const vk_features = vulkan.instance.getPhysicalDeviceFeatures(handle);
    return .{
        .geometry_shaders = vk_features.geometry_shader == .true,
        .tessellation_shaders = vk_features.tessellation_shader == .true,
        .shader_float64 = vk_features.shader_float_64 == .true,
        .shader_int64 = vk_features.shader_int_64 == .true,
        .shader_int16 = vk_features.shader_int_16 == .true,
    };
}

pub fn initInstance(minimal_vulkan_version: vk.Version, layers: Names, extensions: Names) Error!vk.InstanceProxy {
    const instance_version: u32 = if (vulkan.bwp.dispatch.vkEnumerateInstanceVersion) |_|
        vulkan.bwp.enumerateInstanceVersion() catch return Error.InitializationFailure
    else
        @bitCast(vk.Version{ .major = 1, .minor = 0 });
    if (instance_version < @as(u32, @bitCast(minimal_vulkan_version)))
        return Error.UnsupportedApiVersion;

    const allocator = vulkan.arena.allocator();
    const available_layers: []vk.LayerProperties =
        if (layers.len > 0) vulkan.bwp.enumerateInstanceLayerPropertiesAlloc(allocator) catch return Error.OutOfMemory else &.{};

    try checkLayerPresence(layers, available_layers);
    if (layers.len > 0) allocator.free(available_layers);

    var glfw_ext_count: u32 = 0; //get platform presentation extensions
    const glfw_exts = glfw.getRequiredInstanceExtensions(&glfw_ext_count);
    _ = extensions;
    const instance_extensions: Names = if (glfw_exts) |ge| ge[0..glfw_ext_count] else &.{};

    const available_instance_extensions: []vk.ExtensionProperties =
        vulkan.bwp.enumerateInstanceExtensionPropertiesAlloc(null, allocator) catch return Error.OutOfMemory;

    try checkExtensionPresence(instance_extensions, available_instance_extensions);
    allocator.free(available_instance_extensions);

    const app_info: vk.ApplicationInfo = .{
        .p_application_name = huge.name ++ " app",
        .application_version = @bitCast(@as(u32, 0)),
        .p_engine_name = huge.name,
        .engine_version = @bitCast(vk.Version{ .major = 0, .minor = 0 }),
        .api_version = @bitCast(minimal_vulkan_version),
    };
    const instance_create_info: vk.InstanceCreateInfo = .{
        .p_application_info = &app_info,
        .enabled_extension_count = @intCast(instance_extensions.len),
        .pp_enabled_extension_names = instance_extensions.ptr,
        .enabled_layer_count = @intCast(layers.len),
        .pp_enabled_layer_names = layers.ptr,
    };
    const instance_handle = vulkan.bwp.createInstance(&instance_create_info, vulkan.vka) catch |err| return switch (err) {
        error.OutOfHostMemory => Error.OutOfMemory,
        error.OutOfDeviceMemory => Error.OutOfDeviceMemory,
        else => Error.InitializationFailure,
    };

    vulkan.iwp = .load(instance_handle, vulkan.loader);
    return .init(instance_handle, &vulkan.iwp);
}
fn checkExtensionPresence(required: Names, available: []const vk.ExtensionProperties) Error!void {
    for (required) |re| { //check for unavailable instance extensions
        if (!for (available) |ae| {
            if (huge.util.strEqlNullTerm(re, @ptrCast(@alignCast(&ae.extension_name)))) break true;
        } else false) return Error.InitializationFailure; //TODO: log missing extension name
    }
}
fn checkLayerPresence(required: Names, available: []const vk.LayerProperties) Error!void {
    for (required) |rl| { //check for unavailable instance extensions
        if (!for (available) |al| {
            if (huge.util.strEqlNullTerm(rl, @ptrCast(@alignCast(&al.layer_name)))) break true;
        } else false) return Error.InitializationFailure; //TODO: log missing layer name
    }
}

const QueueFamilyConfigurationScore = i32;
const queueConfigurationScoringRules: []const std.meta.Tuple(&.{ QueueFamilyConfigurationScore, [2]vulkan.QueueType }) = &.{
    .{ -150, .{ .graphics, .compute } },
    .{ -150, .{ .graphics, .transfer } },
    .{ -90, .{ .compute, .transfer } },
    .{ 30, .{ .sparse_binding, .transfer } },
};
const Error = vulkan.Error;
const QFI = vulkan.QFI;
