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

    while (!window.shouldClosePoll()) {
        try gpu.beginRendering(window.renderTarget(), .{ .color = .{ 1, 0, 0, 1 } });
        try gpu.draw(pipeline, .{ .count = 3 });

        try gpu.endRendering();
    }
}
// try gpu.draw(cmd, window.renderTarget(), pipeline, .{ .count = 3 });
// try gpu.clear(window.renderTarget(), .{
//     .color = @splat(1),
// });
