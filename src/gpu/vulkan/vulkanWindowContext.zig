const huge = @import("../../root.zig");
const vkb = @import("vulkanBackend.zig");
const vk = vkb.vk;

pub const mic = 3; //max_image_count
pub const mfif = mic - 1; //max_frame_in_flight

surface: vk.SurfaceKHR = .null_handle,
request_recreate: bool = false,

swapchain: vk.SwapchainKHR = .null_handle,

images: [mic]vk.Image = @splat(.null_handle),
image_views: [mic]vk.ImageView = @splat(.null_handle),
framebuffers: [mic]vk.Framebuffer = @splat(.null_handle),
image_count: u32 = undefined,

extent: vk.Extent2D = undefined,
surface_format: vk.SurfaceFormatKHR,
present_mode: vk.PresentModeKHR,

current_frame: usize = 0,
present_finished_semaphores: [mfif]vk.Semaphore = undefined,
render_finished_semaphores: [mfif]vk.Semaphore = undefined,
fences: [mfif]vk.Fence = undefined,
inline fn fif(self: WindowContext) u32 {
    return @max(self.image_count - 1, 1);
}
pub fn create(window: huge.Window) Error!WindowContext {
    _ = window;
    @panic("");
}
const Error = huge.gpu.Error;
const WindowContext = @This();
