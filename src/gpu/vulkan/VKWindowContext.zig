const std = @import("std");
const huge = @import("../../root.zig");
const util = huge.util;
const glfw = huge.Window.glfw;

const vulkan = @import("vulkan.zig");
const vk = @import("vk.zig");
const WindowContext = @This();
const mic = 3; //max_image_count
pub const mfif = mic - 1; //max_frame_in_flight

acquired_image_index: u32 = std.math.maxInt(u32),

surface: vk.SurfaceKHR = .null_handle,
request_recreate: bool = false,
swapchain: vk.SwapchainKHR = .null_handle,

images: [mic]vk.Image = @splat(.null_handle),
image_views: [mic]vk.ImageView = @splat(.null_handle),
image_count: u32 = 0,

extent: vk.Extent2D = .{ .width = 0, .height = 0 },
surface_format: vk.SurfaceFormatKHR = undefined,
present_mode: vk.PresentModeKHR = .fifo_khr,

current_frame: usize = 0,
acquire_semaphores: [mfif]vk.Semaphore = @splat(.null_handle),
submit_semaphores: [mic]vk.Semaphore = @splat(.null_handle),
fences: [mfif]vk.Fence = @splat(.null_handle),

inline fn fif(self: WindowContext) u32 {
    return @max(@max(self.image_count, 1) - 1, 1);
}
pub fn startFrame(self: *WindowContext) Error!void {
    //INCREMENT FIF INDEX
    // self.fif_index = (self.fif_index + 1) % self.fif();
    // if (~self.acquired_image_index != 0) return;

    _ = vulkan.device.waitForFences(1, &.{self.fences[self.fif_index]}, .true, vulkan.timeout) catch
        return Error.SynchronisationError;
    vulkan.device.resetFences(1, &.{self.fences[self.fif_index]}) catch
        return Error.SynchronisationError;
    self.acquired_image_index = (vulkan.device.acquireNextImageKHR(
        self.swapchain,
        vulkan.timeout,
        self.acquire_semaphores[self.fif_index],
        .null_handle,
    ) catch return Error.ResourceCreationError).image_index;
}

pub fn create(window: huge.Window) !WindowContext {
    var surface_handle: u64 = undefined;
    if (glfw.createWindowSurface(
        @intFromEnum(vulkan.instance.handle),
        window.handle,
        null,
        &surface_handle,
    ) != .success) return Error.WindowContextCreationError;
    var result: WindowContext = .{
        .surface = @enumFromInt(surface_handle),
    };

    const capabilities = try vulkan.instance.getPhysicalDeviceSurfaceCapabilitiesKHR(vulkan.pd().handle, result.surface);

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
        _ = try vulkan.instance.getPhysicalDeviceSurfaceFormatsKHR(vulkan.pd().handle, result.surface, &surface_format_count, null);
        surface_format_count = @min(max_surface_format_count, surface_format_count);
        var surface_format_storage: [max_surface_format_count]vk.SurfaceFormatKHR = undefined;
        _ = try vulkan.instance.getPhysicalDeviceSurfaceFormatsKHR(vulkan.pd().handle, result.surface, &surface_format_count, &surface_format_storage);
        break :blk for (surface_format_storage[0..surface_format_count]) |sf| {
            if (sf.format == .b8g8r8a8_unorm and sf.color_space == .srgb_nonlinear_khr) break sf;
        } else surface_format_storage[0];
    };

    result.present_mode = blk: {
        var present_mode_storage: [@typeInfo(vk.PresentModeKHR).@"enum".fields.len]vk.PresentModeKHR = undefined;
        var present_mode_count: u32 = 0;
        _ = try vulkan.instance.getPhysicalDeviceSurfacePresentModesKHR(vulkan.pd().handle, result.surface, &present_mode_count, null);
        _ = try vulkan.instance.getPhysicalDeviceSurfacePresentModesKHR(vulkan.pd().handle, result.surface, &present_mode_count, &present_mode_storage);
        break :blk for (present_mode_storage[0..present_mode_count]) |pm| {
            if (pm == vk.PresentModeKHR.mailbox_khr) break pm;
        } else vk.PresentModeKHR.fifo_khr;
    };

    result.image_count = @max(capabilities.min_image_count, @as(u32, if (result.present_mode == .mailbox_khr) 3 else 2));
    const exclusive = vulkan.qfi(.graphics) == vulkan.qfi(.presentation);
    result.swapchain = try vulkan.device.createSwapchainKHR(&.{
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
            vulkan.qfi(.graphics),
            vulkan.qfi(.presentation),
        },
        .pre_transform = capabilities.current_transform,
        .composite_alpha = .{ .opaque_bit_khr = true },
        .clipped = .true,
    }, vulkan.vka);

    _ = try vulkan.device.getSwapchainImagesKHR(result.swapchain, &result.image_count, null);
    result.image_count = @min(result.image_count, mic);
    _ = try vulkan.device.getSwapchainImagesKHR(result.swapchain, &result.image_count, &result.images);

    for (0..result.image_count) |i|
        result.image_views[i] = try vulkan.device.createImageView(&.{
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
        }, vulkan.vka);

    for (0..result.fif()) |i| {
        result.acquire_semaphores[i] = try vulkan.device.createSemaphore(&.{}, vulkan.vka);
        result.fences[i] = try vulkan.device.createFence(&.{ .flags = .{ .signaled_bit = true } }, vulkan.vka);
    }
    for (0..result.image_count) |i|
        result.submit_semaphores[i] = try vulkan.device.createSemaphore(&.{}, vulkan.vka);

    return result;
}
pub fn destroy(self: *WindowContext) void {
    // if (handle != null and vulkan.current_render_target == getWindowContextRenderTarget(handle.?)) {
    //     self.forceEndRendering();
    // }
    vulkan.device.queueWaitIdle(vulkan.queue(.presentation)) catch {};

    for (self.image_views[0..self.image_count]) |iw|
        vulkan.device.destroyImageView(iw, vulkan.vka);
    vulkan.device.destroySwapchainKHR(self.swapchain, vulkan.vka);

    for (0..self.fif()) |i| {
        vulkan.device.destroySemaphore(self.acquire_semaphores[i], vulkan.vka);
        vulkan.device.destroyFence(self.fences[i], vulkan.vka);
    }
    for (0..self.image_count) |i|
        vulkan.device.destroySemaphore(self.submit_semaphores[i], vulkan.vka);

    vulkan.instance.destroySurfaceKHR(self.surface, vulkan.vka);
    self.* = .{};
}
const Error = vulkan.Error;
