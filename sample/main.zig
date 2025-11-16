const std = @import("std");
const huge = @import("huge");
const gpu = huge.gpu;

pub fn main() !void {
    try huge.init();
    defer huge.deinit();

    const m = try gpu.Pipeline.create(.surface, &.{
        .{ .path = "test.hgsl", .entry_point = "vert" },
        .{ .path = "test.hgsl", .entry_point = "frag" },
    });
    _ = m;
    var window = try huge.Window.create(.{ .title = "sample#0", .size = huge.Window.HD });
    defer window.destroy();

    // while (!window.shouldClose()) {
    // window.frameEnd();
    // }
}
