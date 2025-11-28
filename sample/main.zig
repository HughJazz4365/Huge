// io must only be scalar or vector!!(arrays??)

// 1. hgsl texture
// + obj, png loading

const std = @import("std");
const huge = @import("huge");
const math = huge.math;
const gpu = huge.gpu;

const cube = @import("cube.zig");

pub fn main() !void {
    try huge.init();
    defer huge.deinit();
    huge.Time.avg_threshold = 5 * std.time.ns_per_s;

    var window: huge.Window = try .create(.{ .title = "sample#0", .size = .{ 800, 600 } });

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
        .position = .{ -1, -1.4, 2 },
        .scale = .{ 2.5, 1, 2 },
    };

    const ubo: gpu.Buffer = try .create(12, .uniform);
    const texture: gpu.Texture = try .create(.{ 2, 2, 0 }, .rgba8_norm, .{ .filtering = .{ .shrink = .linear, .expand = .linear } });
    _ = texture;

    var avg: f64 = 0;
    // if (true) return;
    window.disableCursor();
    var euler: math.vec3 = @splat(0);
    while (window.tick()) {
        if (window.frame_count % 200 == 0) try gpu.reloadPipelines();
        if (huge.time.avg64() != avg) {
            avg = huge.time.avg64();
            std.debug.print("AVGFPS: {d}\n", .{1.0 / avg});
        }

        const speed = 5;
        const sensitivity = 1000;

        const cursor_delta = window.getCursorDeltaNormalized();
        const limit = math.r2d * (90 - 0.001);
        euler = .{
            std.math.clamp(euler[0] + -cursor_delta[1] * sensitivity, -limit, limit),
            euler[1] + cursor_delta[0] * sensitivity,
            0,
        };
        camera_transform.rotation = math.quatFromEuler(euler);
        camera_transform.position += math.scale(window.warsudVector(euler[1]), huge.time.delta() * speed);
        try ubo.loadBytes(@ptrCast(@alignCast(&camera_transform.position)), 0);

        cube_transform.rotation = math.quatFromEuler(.{ 0, huge.time.seconds(), 0 });

        try gpu.beginRendering(window.renderTarget(), .{ .color = @splat(0.14) });
        pipeline.setPropertiesStruct(.{
            .model = &cube_transform,
            .vp = &camera,
            .ubo = ubo,
        });
        mesh.draw(pipeline);

        try gpu.endRendering();
    }
}
