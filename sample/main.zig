const std = @import("std");
const huge = @import("huge");
const gpu = huge.gpu;

pub fn main() !void {
    try huge.init();
    defer huge.deinit();

    // const pipeline = try gpu.Pipeline.createPath(.{ .surface = .{
    //     .vertex = .{ .path = "shader.hgsl", .entry_point = "vert" },
    //     .fragment = .{ .path = "shader.hgsl", .entry_point = "frag" },
    // } });
    var window: huge.Window = try .create(.{ .title = "sample#0", .size = huge.Window.HD });
    defer window.destroy();

    // const cmd: gpu.CommandBuffer = try .new();

    while (!window.shouldClose()) {
        // try gpu.draw(cmd, window.renderTarget(), pipeline, .{ .count = 3 });
        // try gpu.clear(cmd, window.renderTarget(), .{
        //     .color = @splat(1),
        // });
        // cmd.submit();
        try window.present();
    }
}
