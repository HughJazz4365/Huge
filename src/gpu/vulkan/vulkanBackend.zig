const root = @import("../../root.zig");
const gpu = root.gpu;

pub const vulkanBackend: gpu.Backend = .{
    .api = .vulkan,
    .api_version = .{ .major = 1, .minor = 4 },
};
