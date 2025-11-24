const std = @import("std");
pub const zigbuiltin = @import("builtin");
pub const core = @import("core.zig");
pub const Window = @import("Window.zig");
pub const math = @import("math.zig");
pub const gpu = @import("gpu/gpu.zig");
pub const rend = @import("gpu/rendering.zig");
pub const util = @import("util.zig");

pub const Time = @import("Time.zig");
pub var time: Time = .{}; //global time

pub const Transform = core.Transform;
pub const Camera = core.Camera;

pub const name = "huge";
pub const version: Version = .new(0, 0); //parse from zon;
pub var initialized = false;

pub fn dassert(ok: bool) void {
    if (zigbuiltin.mode == .Debug and !ok) @panic("ASSERTION FAILED");
}
pub fn cassert(comptime condition: bool) void {
    if (!condition) @compileError("comptime assertion failed");
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
