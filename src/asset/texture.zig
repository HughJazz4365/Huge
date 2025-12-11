const std = @import("std");
const huge = @import("../root.zig");
const asset = huge.asset;
const util = huge.util;
const math = huge.math;

pub fn loadTextureBytes(io: std.Io, allocator: Allocator, path: []const u8) Error![]u8 {
    const bytes = try asset.readFileAlloc(io, allocator, path);
    return bytes;
}
const Error = asset.Error;
const Allocator = std.mem.Allocator;
