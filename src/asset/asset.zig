const std = @import("std");
const huge = @import("../root.zig");
const util = huge.util;
const math = huge.math;

pub const Error = Allocator.Error || std.Io.Writer.Error || error{StreamTooLong};
pub fn readFileAlloc(io: std.Io, allocator: Allocator, path: []const u8) []u8 {
    const file = std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    var file_reader = file.reader(io, &.{});
    return try file_reader.interface.allocRemaining(allocator, .unlimited);
}

const Allocator = std.mem.Allocator;
