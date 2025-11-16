const std = @import("std");
pub const Window = @import("Window.zig");
pub const math = @import("math.zig");
pub const gpu = @import("gpu/gpu.zig");
pub const util = @import("util.zig");
pub const time = void;

pub const name = "huge";
pub const version: Version = .new(0, 0); //parse from zon;
pub var initialized = false;
pub fn init() !void {
    try Window.init();
    try gpu.init();
    initialized = true;
}
pub fn deinit() void {
    defer Window.terminate();
    defer gpu.deinit();
    initialized = false;
}
pub const Version = struct {
    major: u32 = 0,
    minor: u32 = 0,
    pub fn new(major: u32, minor: u32) Version {
        return .{ .major = major, .minor = minor };
    }
    pub fn @">="(self: Version, other: Version) bool {
        return self.major >= other.major and self.minor >= other.minor;
    }
    pub fn format(self: Version, writer: *std.Io.Writer) !void {
        try writer.print("v{d}.{d}", .{ self.major, self.minor });
    }
};
