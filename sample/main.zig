const std = @import("std");
const huge = @import("huge");
const gpu = huge.gpu;

pub fn main() !void {
    try huge.init();
    defer huge.deinit();

    const pipeline = try gpu.Pipeline.createPath(.{ .surface = .{
        .vertex = .{ .path = "shader.hgsl", .entry_point = "vert" },
        .fragment = .{ .path = "shader.hgsl", .entry_point = "frag" },
    } });
    var window: huge.Window = try .create(.{ .title = "sample#0", .size = huge.Window.HD });
    defer window.destroy();

    _ = pipeline;
    while (!window.shouldClose()) {
        try gpu.beginRendering(window.renderTarget(), .{ .color = @splat(1) });
        //try gpu.draw(pipeline, .{ .count = 3 });

        try gpu.endRendering();
        break;
    }
}
// try gpu.draw(cmd, window.renderTarget(), pipeline, .{ .count = 3 });
// try gpu.clear(window.renderTarget(), .{
//     .color = @splat(1),
// });
