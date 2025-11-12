const std = @import("std");
const root = @import("../root.zig");
pub const shader = @import("shader.zig");
pub const Backend = @import("GPUBackend.zig");

pub var backend: Backend = @import("vulkan/vulkanBackend.zig").vulkanBackend;
pub fn init() void {
    shader.init();
}
pub fn deinit() void {
    shader.deinit();
}
pub const Pipeline = enum(u32) { null = u32m, _ };

pub const GApi = enum {
    vulkan,
    opengl,
    none,
};
pub const ApiVersion = struct { major: u32 = 0, minor: u32 = 0 };
const u32m = ~@as(u32, 0);
