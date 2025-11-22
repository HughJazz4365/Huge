const std = @import("std");
const zigbuiltin = @import("builtin");
pub const Window = @import("Window.zig");
pub const math = @import("math.zig");
pub const gpu = @import("gpu/gpu.zig");
pub const rend = @import("gpu/rendering.zig");
pub const util = @import("util.zig");
pub const time = void;

pub const name = "huge";
pub const version: Version = .new(0, 0); //parse from zon;
pub var initialized = false;

pub fn dassert(ok: bool) void {
    if (zigbuiltin.mode == .Debug and !ok) @panic("ASSERTION FAILED");
}
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
