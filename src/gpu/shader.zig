const std = @import("std");
const hgsl = @import("hgsl");
const root = @import("../root.zig");
const gpu = root.gpu;

pub const Stage = hgsl.Parser.ShaderStage;
pub const ShaderInfo = struct { source: []const u8, stage: Stage };

//state

var compiler: hgsl.Compiler = undefined;

pub fn init() void {
    compiler = .new(null, null, .{
        .target_env = switch (gpu.backend.api) {
            .vulkan => .vulkan1_4,
            else => .vulkan1_4,
        },
    });
}
pub fn deinit() void {
    // compiler.deinit();
}
