pub const Window = @import("Window.zig");
pub const math = @import("math.zig");
pub const gpu = @import("gpu/gpu.zig");
pub const util = @import("util.zig");

pub var initialized = false;
pub fn init() !void {
    try Window.init();
    initialized = true;
}
pub fn deinit() void {
    Window.terminate();
    initialized = false;
}
