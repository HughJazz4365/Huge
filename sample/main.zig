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
    var window = try huge.Window.create(.{ .title = "sample#0", .size = huge.Window.HD });
    defer window.destroy();

    const cmd: gpu.CommandBuffer = undefined;
    const rend: gpu.RawRenderer = .{ .pipeline = pipeline };

    while (!window.shouldClose()) {
        rend.draw(cmd, 3);
        cmd.submit();
        try window.present();
    }
}
