const std = @import("std");
const huge = @import("huge");
const gpu = huge.gpu;

pub fn main() !void {
    try huge.init();
    defer huge.deinit();

    const m = try gpu.Pipeline.createPath(.surface, &.{
        .{ .path = "shader.hgsl", .entry_point = "vert" },
        .{ .path = "shader.hgsl", .entry_point = "frag" },
    });
    _ = m;
    var window = try huge.Window.create(.{ .title = "sample#0", .size = huge.Window.HD });
    defer window.destroy();

    while (!window.shouldClose()) {
        try window.present();
    }
}
