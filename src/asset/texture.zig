const std = @import("std");
const huge = @import("../root.zig");
const asset = huge.asset;
const util = huge.util;
const math = huge.math;

pub fn loadTextureBytes(io: std.Io, allocator: Allocator, path: []const u8) Error![]u8 {
    const bytes: []const u8 = asset.readFileAlloc(io, allocator, path) catch &missing_texture_bytes;
    defer if (@intFromPtr(bytes.ptr) != &missing_texture_bytes) allocator.free(bytes);
    return bytes;
}
//2x2 image: |purple| crimson|
//           |black | purple |
const missing_texture_bytes = [_]u8{
    255, 0, 255, 255,
    0,   0, 50,  0,
    0,   0, 0,   0,
    255, 0, 255, 255,
};
const Error = asset.Error;
const Allocator = std.mem.Allocator;
