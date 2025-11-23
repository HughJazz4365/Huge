const std = @import("std");
const huge = @import("huge");
const math = huge.math;
const gpu = huge.gpu;

const cube = @import("cube.zig");

pub fn main() !void {
    try huge.init();
    defer huge.deinit();
    var window: huge.Window = try .create(.{ .title = "sample#0", .size = huge.Window.HD });
    defer window.destroy();

    const pipeline = try gpu.Pipeline.createPath(.{ .surface = .{
        .vertex = .{ .path = "shader.hgsl", .entry_point = "vert" },
        .fragment = .{ .path = "shader.hgsl", .entry_point = "frag" },
    } }, .{ .primitive = .triangle, .cull = .back });

    var camera_transform: huge.Transform = .{
        .position = .{ 0, 0, -5 },
    };
    var camera: huge.Camera = .{
        .aspect_ratio = window.aspectRatio(),
        .transform = &camera_transform,
    };

    const mesh: huge.rend.MeshRenderer = try .new(@ptrCast(&cube.vertices), u16, &cube.indices);
    var cube_transform: huge.Transform = .{
        .position = .{ 1, 0, 0 },
        .rotation = math.quatFromEulerDeg(.{ 0, 45, 0 }),
    };

    var avg: f64 = 0;
    huge.Time.avg_threshold = 10 * std.time.ns_per_s;
    while (window.tick()) {
        if (huge.time.avg64() != avg) {
            avg = huge.time.avg64();
            std.debug.print("AVGFPS: {d}\n", .{1.0 / avg});
        }

        const speed = 5;
        camera_transform.position += math.scale(window.warsudVector(), huge.time.delta() * speed);

        try gpu.beginRendering(window.renderTarget(), .{ .color = @splat(0.14) });
        try pipeline.setPropertiesStruct(.{
            .model = &cube_transform,
            .vp = &camera,
        });
        try mesh.draw(pipeline);

        try gpu.endRendering();
    }
}
