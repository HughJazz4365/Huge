const std = @import("std");
const zigbuiltin = @import("builtin");
const huge = @import("../../root.zig");
const util = huge.util;
const gpu = huge.gpu;
const hgsl = gpu.hgsl;

pub const vk = @import("vk.zig");

//=====|constants|======

const timeout: u64 = std.time.ns_per_s * 5;
const max_queue_family_count = 16;
const max_physical_devices = 3;

const min_vulkan_version: Version = .{ .major = 1, .minor = 2 };
const max_vulkan_version: Version = undefined;

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

var bwp: vk.BaseWrapper = undefined;
var iwp: vk.InstanceWrapper = undefined;
var dwp: vk.DeviceWrapper = undefined;
var queues: [queue_type_count]vk.Queue = @splat(.null_handle);
inline fn queue(queue_type: QueueType) vk.Queue {
    return queues[@intFromEnum(queue_type)];
}

var command_pools: [queue_type_count]vk.CommandPool = @splat(.null_handle);
fn commandPool(queue_type: QueueType) Error!vk.CommandPool {
    const index = @intFromEnum(queue_type);
    if (command_pools[index] == .null_handle) {
        const qfi = pd().queueFamilyIndex(queue_type);
        const created = device.createCommandPool(&.{
            .flags = .{ .reset_command_buffer_bit = true },
            .queue_family_index = qfi,
        }, vka) catch
            return Error.ResourceCreationError;
        for (&command_pools, 0..) |*cmd_pools, i| {
            if (pd().queueFamilyIndex(@enumFromInt(i)) == qfi)
                cmd_pools.* = created;
        }
    }
    return command_pools[index];
}
fn allocCommandBuffer(queue_type: QueueType, level: vk.CommandBufferLevel) Error!vk.CommandBuffer {
    var result: vk.CommandBuffer = .null_handle;
    device.allocateCommandBuffers(&.{
        .command_pool = try commandPool(queue_type),
        .level = level,
        .command_buffer_count = 1,
    }, @ptrCast(&result)) catch return Error.ResourceCreationError;
    return result;
}

inline fn pd() PhysicalDevice {
    return physical_devices[current_physical_device_index];
}

var api_version: Version = undefined;
// var arena: std.heap.ArenaAllocator = un
var shader_compiler: hgsl.Compiler = undefined;
// var pipelines: List(VKPipeline) = .empty;

var shader_module_list: List(VKShaderModule) = .empty;
var pipeline_list: List(VKPipeline) = .empty;

var window_context_primary: VKWindowContext = undefined;
var window_context_list: List(VKWindowContext) = .empty;
var window_context_count: u32 = 0;
//======|methods|========

fn draw(
    cmd: CommandBuffer,
    render_target: RenderTarget,
    pipeline: Pipeline,
    params: gpu.DrawParams,
) Error!void {
    _ = .{ cmd, render_target, pipeline, params };
}
fn createPipeline(stages: []const ShaderModule) Error!Pipeline {
    _ = stages;
    return @enumFromInt(0);
}
fn getWindowRenderTarget(window: huge.Window) RenderTarget {
    return @enumFromInt((1 << 31) | @intFromEnum(window.context));
}
fn createWindowContext(window: huge.Window) Error!WindowContext {
    const wc = VKWindowContext.create(window) catch
        return Error.WindowContextCreationError;
    if (window_context_count == 0) {
        window_context_primary = wc;
        return @enumFromInt(0);
    } else {
        @panic("VK multiple window contexts");
    }
}
fn destroyWindowContext(handle: WindowContext) void {
    const window_context = VKWindowContext.get(handle);
    window_context.destroy();
}

var temp_cmd: vk.CommandBuffer = .null_handle;
fn present(window: huge.Window) Error!void {
    const window_context = VKWindowContext.get(window.context);
    _ = device.waitForFences(
        1,
        &.{window_context.fences[window_context.fif_index]},
        .true,
        timeout,
    ) catch return Error.CommadBufferSubmitionError;

    device.resetFences(1, &.{window_context.fences[window_context.fif_index]}) catch
        return Error.PresentationError;

    const image_index = (device.acquireNextImageKHR(
        window_context.swapchain,
        timeout,
        window_context.acquire_semaphores[window_context.fif_index],
        .null_handle,
    ) catch return Error.PresentationError).image_index;
    if (~image_index == 0) return;

    if (temp_cmd == .null_handle)
        temp_cmd = try allocCommandBuffer(.graphics, .primary);
    if (temp_cmd != .null_handle)
        device.resetCommandBuffer(temp_cmd, .{}) catch return Error.PresentationError;

    const image_barrier: vk.ImageMemoryBarrier = .{
        .src_access_mask = .{ .color_attachment_write_bit = true },
        .dst_access_mask = .{},
        .old_layout = .undefined,
        .new_layout = .present_src_khr,
        .src_queue_family_index = pd().queueFamilyIndex(.presentation),
        .dst_queue_family_index = pd().queueFamilyIndex(.presentation),
        .image = window_context.images[image_index],
        .subresource_range = .{
            .aspect_mask = .{ .color_bit = true },
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
    };
    device.beginCommandBuffer(temp_cmd, &.{
        .flags = .{},
    }) catch return Error.CommadBufferRecordingError;
    device.cmdPipelineBarrier(
        temp_cmd,
        .{ .all_commands_bit = true },
        .{ .bottom_of_pipe_bit = true },
        .{},
        0,
        null,
        0,
        null,
        1,
        &.{image_barrier},
    );
    device.endCommandBuffer(temp_cmd) catch
        return Error.CommadBufferRecordingError;
    device.queueSubmit(
        queue(.presentation),
        1,
        &.{.{
            .command_buffer_count = 1,
            .p_command_buffers = &.{temp_cmd},
            .p_wait_dst_stage_mask = &.{.{ .color_attachment_output_bit = true }},

            .wait_semaphore_count = 1,
            .p_wait_semaphores = &.{window_context.acquire_semaphores[window_context.fif_index]},
            .signal_semaphore_count = 1,
            .p_signal_semaphores = &.{window_context.submit_semaphores[image_index]},
        }},
        window_context.fences[window_context.fif_index],
    ) catch return Error.CommadBufferSubmitionError;

    _ = device.queuePresentKHR(queue(.presentation), &.{
        .wait_semaphore_count = 1,
        .p_wait_semaphores = &.{window_context.submit_semaphores[image_index]},
        .swapchain_count = 1,
        .p_swapchains = &.{window_context.swapchain},
        .p_image_indices = &.{image_index},
    }) catch |err|
        switch (err) {
            error.OutOfDateKHR => {
                @panic("recreate swapchain");
                // self.request_recreate = true;
            },
            else => return Error.PresentationError,
        };
}
//===|implementations|===
const VKShaderModule = struct {
    vk_handle: vk.ShaderModule = .null_handle,
    stage: gpu.ShaderStage,

    push_constant_mappings: []const hgsl.PushConstantMapping,
    opaque_uniform_mappings: []const hgsl.OpaqueUniformMapping,
    pub fn createPath(path: []const u8, entry_point: []const u8) Error!VKShaderModule {
        _ = .{ path, entry_point };
        // const result = shader_compiler.compileFile(path);
    }
    pub fn createSource(source: []const u8, entry_point: []const u8) Error!VKShaderModule {
        if (true) @panic("VKShaderModule.createRaw");
        return try createPath(source, entry_point);
    }

    pub fn get(handle: ShaderModule) *VKShaderModule {
        return shader_module_list[@intFromEnum(handle)];
    }
};
//handle array with functions that have explicit
//(offset and size) or (binding) args on top of 'name'
const VKPipeline = struct {
    //descriptor_set
    //stages
    //pc mapping, uniform mapping(just concat from stages
    // and dont care about repeating names)
    pub fn get(handle: Pipeline) *VKPipeline {
        return pipeline_list[@intFromEnum(handle)];
    }
};

const VKRenderTarget = struct {};

const VKCommandBuffer = struct {
    handles: [queue_type_count]vk.CommandBuffer = @splat(.null_handle),
};

const VKWindowContext = struct {
    const mic = 3; //max_image_count
    const mfif = mic - 1; //max_frame_in_flight
    image_transition_command_buffer: vk.CommandBuffer = .null_handle,

    fif_index: u32 = 0, //current frame-in-flight index

    surface: vk.SurfaceKHR = .null_handle,
    request_recreate: bool = false,
    swapchain: vk.SwapchainKHR = .null_handle,

    images: [mic]vk.Image = @splat(.null_handle),
    image_views: [mic]vk.ImageView = @splat(.null_handle),
    image_count: u32 = undefined,

    extent: vk.Extent2D = undefined,
    surface_format: vk.SurfaceFormatKHR = undefined,
    present_mode: vk.PresentModeKHR = .fifo_khr,

    current_frame: usize = 0,
    acquire_semaphores: [mfif]vk.Semaphore = undefined,
    submit_semaphores: [mic]vk.Semaphore = undefined,
    fences: [mfif]vk.Fence = undefined,
    inline fn fif(self: VKWindowContext) u32 {
        return @max(self.image_count - 1, 1);
    }
    pub fn waitForFence(self: VKWindowContext) !void {
        _ = try device.waitForFences(
            1,
            &.{self.fences[self.fif_index]},
            .true,
            timeout,
        );
        try device.resetFences(1, &.{self.fences[self.fif_index]});
    }
    pub fn create(window: huge.Window) !VKWindowContext {
        var surface_handle: u64 = undefined;
        if (glfw.createWindowSurface(
            @intFromEnum(instance.handle),
            window.handle,
            null,
            &surface_handle,
        ) != .success) return Error.WindowContextCreationError;
        var result: VKWindowContext = .{
            .surface = @enumFromInt(surface_handle),
        };

        const capabilities = try instance.getPhysicalDeviceSurfaceCapabilitiesKHR(pd().handle, result.surface);

        result.extent = blk: {
            if (capabilities.current_extent.width == std.math.maxInt(u32)) {
                var res: [2]c_int = @splat(0);
                glfw.getFramebufferSize(window.handle, &res[0], &res[1]);
                break :blk .{
                    .width = std.math.clamp(@as(u32, @intCast(res[0])), capabilities.min_image_extent.width, capabilities.max_image_extent.width),
                    .height = std.math.clamp(@as(u32, @intCast(res[1])), capabilities.min_image_extent.height, capabilities.max_image_extent.height),
                };
            }
            break :blk .{
                .width = std.math.clamp(capabilities.current_extent.width, capabilities.min_image_extent.width, capabilities.max_image_extent.width),
                .height = std.math.clamp(capabilities.current_extent.height, capabilities.min_image_extent.height, capabilities.max_image_extent.height),
            };
        };

        result.surface_format = blk: {
            const max_surface_format_count = 100;
            var surface_format_count: u32 = 0;
            _ = try instance.getPhysicalDeviceSurfaceFormatsKHR(pd().handle, result.surface, &surface_format_count, null);
            surface_format_count = @min(max_surface_format_count, surface_format_count);
            var surface_format_storage: [max_surface_format_count]vk.SurfaceFormatKHR = undefined;
            _ = try instance.getPhysicalDeviceSurfaceFormatsKHR(pd().handle, result.surface, &surface_format_count, &surface_format_storage);
            break :blk for (surface_format_storage[0..surface_format_count]) |sf| {
                if (sf.format == .b8g8r8a8_unorm and sf.color_space == .srgb_nonlinear_khr) break sf;
            } else surface_format_storage[0];
        };

        result.present_mode = blk: {
            var present_mode_storage: [@typeInfo(vk.PresentModeKHR).@"enum".fields.len]vk.PresentModeKHR = undefined;
            var present_mode_count: u32 = 0;
            _ = try instance.getPhysicalDeviceSurfacePresentModesKHR(pd().handle, result.surface, &present_mode_count, null);
            _ = try instance.getPhysicalDeviceSurfacePresentModesKHR(pd().handle, result.surface, &present_mode_count, &present_mode_storage);
            break :blk for (present_mode_storage[0..present_mode_count]) |pm| {
                if (pm == vk.PresentModeKHR.mailbox_khr) break pm;
            } else vk.PresentModeKHR.fifo_khr;
        };
        result.image_count = if (result.present_mode == .mailbox_khr) 3 else 2;
        const exclusive = pd().queueFamilyIndex(.graphics) == pd().queueFamilyIndex(.presentation);
        result.swapchain = try device.createSwapchainKHR(&.{
            .surface = result.surface,
            .min_image_count = result.image_count,

            .present_mode = result.present_mode,
            .image_format = result.surface_format.format,
            .image_color_space = result.surface_format.color_space,
            .image_extent = result.extent,

            .image_array_layers = 1,
            .image_sharing_mode = if (exclusive) .exclusive else .concurrent,
            .image_usage = .{
                .transfer_dst_bit = true,
                .color_attachment_bit = true,
            },
            .queue_family_index_count = if (exclusive) 0 else 2,
            .p_queue_family_indices = if (exclusive) null else &.{
                pd().queueFamilyIndex(.graphics),
                pd().queueFamilyIndex(.presentation),
            },
            .pre_transform = capabilities.current_transform,
            .composite_alpha = .{ .opaque_bit_khr = true },
            .clipped = .true,
        }, vka);

        _ = try device.getSwapchainImagesKHR(result.swapchain, &result.image_count, null);
        result.image_count = @min(result.image_count, mic);
        _ = try device.getSwapchainImagesKHR(result.swapchain, &result.image_count, &result.images);

        for (0..result.image_count) |i|
            result.image_views[i] = try device.createImageView(&.{
                .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
                .format = result.surface_format.format,
                .image = result.images[i],
                .subresource_range = .{
                    .aspect_mask = .{ .color_bit = true },
                    .layer_count = 1,
                    .base_array_layer = 0,
                    .level_count = 1,
                    .base_mip_level = 0,
                },
                .view_type = .@"2d",
            }, vka);

        for (0..result.fif()) |i| {
            result.acquire_semaphores[i] = try device.createSemaphore(&.{}, vka);
            result.fences[i] = try device.createFence(&.{ .flags = .{ .signaled_bit = true } }, vka);
        }
        for (0..result.image_count) |i|
            result.submit_semaphores[i] = try device.createSemaphore(&.{}, vka);
        return result;
    }
    pub fn destroy(self: VKWindowContext) void {
        device.queueWaitIdle(queue(.presentation)) catch
            @panic("window context destruction failure");
        _ = device.waitForFences(self.fif(), &self.fences, .true, timeout) catch
            @panic("window context destruction failure");
        for (self.image_views[0..self.image_count]) |iw|
            device.destroyImageView(iw, vka);
        device.destroySwapchainKHR(self.swapchain, vka);

        for (0..self.fif()) |i| {
            device.destroySemaphore(self.acquire_semaphores[i], vka);
            device.destroyFence(self.fences[i], vka);
        }
        for (0..self.image_count) |i|
            device.destroySemaphore(self.submit_semaphores[i], vka);

        instance.destroySurfaceKHR(self.surface, vka);
    }
    pub fn get(handle: WindowContext) *VKWindowContext {
        return if (@intFromEnum(handle) == 0)
            &window_context_primary
        else
            @panic("");
    }
};
//===|vkextensions|====

fn isDynamicRenderingBuiltin() bool {
    return api_version.@">="(.{ .major = 1, .minor = 3 });
}
fn cmdBeginRendering(command_buffer: vk.CommandBuffer, rendering_info: *const vk.RenderingInfo) void {
    if (isDynamicRenderingBuiltin())
        device.cmdBeginRendering(command_buffer, rendering_info)
    else
        device.cmdBeginRenderingKHR(command_buffer, rendering_info);
}
fn cmdEndRendering(command_buffer: vk.CommandBuffer, rendering_info: *const vk.RenderingInfo) void {
    if (isDynamicRenderingBuiltin())
        device.cmdEndRendering(command_buffer, rendering_info)
    else
        device.cmdEndRenderingKHR(command_buffer, rendering_info);
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

    var extension_name_buf: [10][*:0]const u8 = undefined;
    var device_extension_list: List([*:0]const u8) = .initBuffer(&extension_name_buf);

    device_extension_list.appendAssumeCapacity(vk.extensions.khr_swapchain.name);
    if (!instance_api_version.@">="(.{ .major = 1, .minor = 3 }))
        device_extension_list.appendAssumeCapacity(vk.extensions.khr_dynamic_rendering.name);

    try initPhysicalDevices(arena.allocator(), device_extension_list.items);
    const physical_device_api_version = castVersion(@bitCast(instance.getPhysicalDeviceProperties(pd().handle).api_version));

    api_version = if (physical_device_api_version.@">="(instance_api_version)) instance_api_version else physical_device_api_version;
    try initLogicalDeviceAndQueues(device_extension_list.items);

    shader_compiler = .new(null, null, .{ .target_env = .vulkan1_4 });
    return versionBackend(api_version);
}

fn deinit() void {
    device.deviceWaitIdle() catch {};
    shader_compiler.deinit();
    for (&command_pools) |cmd_pool| {
        for (&command_pools) |*i| {
            if (cmd_pool == i.*) i.* = .null_handle;
        }
        if (cmd_pool != .null_handle)
            device.destroyCommandPool(cmd_pool, vka);
    }
}
fn initLogicalDeviceAndQueues(extensions: []const [*:0]const u8) VKError!void {
    var queue_create_infos: [queue_type_count]vk.DeviceQueueCreateInfo = undefined;
    var queues_to_create: [queue_type_count]u8 = undefined;
    var count: usize = 0;

    //track all unique queue families
    for (pd().queue_family_indices) |qi| {
        if (~qi == 0) continue;

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

    const dynamic_rendering_feature_ptr: *const anyopaque =
        if (isDynamicRenderingBuiltin())
            &vk.PhysicalDeviceDynamicRenderingFeatures{ .dynamic_rendering = .true }
        else
            &vk.PhysicalDeviceDynamicRenderingFeaturesKHR{ .dynamic_rendering = .true };

    const device_create_info: vk.DeviceCreateInfo = .{
        .enabled_extension_count = @intCast(extensions.len),
        .pp_enabled_extension_names = extensions.ptr,
        .queue_create_info_count = @intCast(count),
        .p_queue_create_infos = &queue_create_infos,
        .pp_enabled_layer_names = layers.ptr,
        .enabled_layer_count = @intCast(layers.len),

        .p_next = dynamic_rendering_feature_ptr,
    };

    const device_handle = instance.createDevice(
        pd().handle,
        &device_create_info,
        vka,
    ) catch return VKError.LogicalDeviceInitializationFailure;
    dwp = .load(device_handle, instance.wrapper.dispatch.vkGetDeviceProcAddr.?);
    device = .init(device_handle, &dwp);

    for (0..queue_type_count) |i| {
        if (~pd().queue_family_indices[i] != 0)
            queues[i] = device.getDeviceQueue(pd().queue_family_indices[i], 0);
    }
}
fn initInstance(allocator: Allocator, instance_api_version: Version) VKError!void {
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
    // for (available_instance_extensions) |aie| {
    //     std.debug.print("ext: {s}\n", .{@as([*:0]const u8, @ptrCast(@alignCast(&aie.extension_name)))});
    // }

    try checkExtensionPresence(instance_extensions, available_instance_extensions);
    allocator.free(available_instance_extensions);

    const app_info: vk.ApplicationInfo = .{
        .p_application_name = huge.name ++ " app",
        .application_version = @bitCast(@as(u32, 0)),
        .p_engine_name = huge.name,
        .engine_version = toVulkanVersion(huge.version),
        .api_version = toVulkanVersion(instance_api_version),
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
    // for (available_extensions) |aie| {
    //     std.debug.print("dext: {s}\n", .{@as([*:0]const u8, @ptrCast(@alignCast(&aie.extension_name)))});
    // }
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
    pub fn queueFamilyIndex(self: *const PhysicalDevice, queue_type: QueueType) u8 {
        return self.queue_family_indices[@intFromEnum(queue_type)];
    }
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
pub const QueueType = enum(u8) { graphics, presentation, compute, transfer, sparse_binding, protected, video_decode, video_encode };

//=======================
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
const glfw = huge.Window.glfw;
const Error = gpu.Error;
const Pipeline = gpu.Pipeline;
const ShaderModule = gpu.ShaderModule;
const CommandBuffer = gpu.CommandBuffer;
const RenderTarget = gpu.RenderTarget;
const WindowContext = gpu.WindowContext;
const Version = huge.Version;
const Allocator = std.mem.Allocator;
const List = std.ArrayList;
const VKError = error{
    OutOfMemory,

    UnavailableExtension,
    UnsupportedApiVersion,
    UnavailableLayer,

    InstanceInitializationFailure,
    PhysicalDeviceInitializationFailure,
    DummyWindowCreationFailure,
    MissingQueueType,

    LogicalDeviceInitializationFailure,
};
fn versionBackend(version: Version) gpu.Backend {
    return .{
        .api = .vulkan,
        .api_version = version,
        .deinit = &deinit,

        .draw = &draw,

        .createPipeline = &createPipeline,

        .present = &present,
        .getWindowRenderTarget = &getWindowRenderTarget,

        .createWindowContext = &createWindowContext,
        .destroyWindowContext = &destroyWindowContext,
    };
}
