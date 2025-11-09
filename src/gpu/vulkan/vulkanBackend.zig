const root = @import("../../root.zig");
const gpu = root.gpu;

pub const vulkanBackend: gpu.Backend = .{
    .gpu_api = .vulkan,
};
