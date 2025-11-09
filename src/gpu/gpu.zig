const std = @import("std");
const root = @import("../root.zig");

var backend: Backend = @import("vulkan/vulkanBackend.zig").vulkanBackend;
pub fn currentGApi() GApi {
    return backend.gpu_api;
}

pub const GApi = enum {
    vulkan,
    opengl,
    none,
};
pub const Backend = @import("GPUBackend.zig");
