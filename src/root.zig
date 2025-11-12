pub const Window = @import("Window.zig");
pub const math = @import("math.zig");
pub const gpu = @import("gpu/gpu.zig");
pub const util = @import("util.zig");
pub const time = void;

pub var initialized = false;
pub fn init() !void {
    gpu.init();
    try Window.init();
    initialized = true;
}
pub fn deinit() void {
    defer gpu.deinit();
    Window.terminate();
    initialized = false;
}
