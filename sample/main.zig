// + vertex attribute formats??(from shader compiler)
// extra locations that dont have match are a validation error
// not critical tho??
// non matching location types should def be an error

// + Textures, opaque uniforms
// + obj, png loading
// + shader linkage checking
// + camera movement(mouse input)

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
        .position = .{ 1, 0, 0 },
        .scale = .{ 2.5, 1, 2 },
    };
    const texture: gpu.Texture = try .create(.{ 2, 2, 0 }, .rgba8_norm, .{});
    std.debug.print("th: {}\n", .{texture});
    const rt = try texture.renderTarget();
    std.debug.print("t_rt: {}, size: {d}, wrt: {d}\n", .{
        rt,
        rt.size(),
        window.renderTarget().size(),
    });

    var avg: f64 = 0;
    while (window.tick()) {
        if (window.frame_count % 100 == 0) try gpu.reloadPipelines();
        if (huge.time.avg64() != avg) {
            avg = huge.time.avg64();
            std.debug.print("AVGFPS: {d}\n", .{1.0 / avg});
        }

        const speed = 5;
        cube_transform.rotation = math.quatFromEuler(.{ 0, huge.time.seconds(), 0 });
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
