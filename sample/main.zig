const std = @import("std");
const huge = @import("huge");
const math = huge.math;
const vk = huge.vk;

const cube = @import("cube.zig");

pub fn main() !void {
    var threaded_io: std.Io.Threaded = .init_single_threaded;
    const io = threaded_io.ioBasic();

    try huge.init();
    defer huge.deinit();
    huge.Time.avg_threshold = 5 * std.time.ns_per_s;

    var window: huge.Window = try .create(.{
        .title = "sample#0",
        .size = .{ 800, 600 },
        .resizable = true,
    });
    defer window.close();

    const pipeline: vk.VKPipeline = try .createFiles(io, .{ .graphics = .{
        .vertex = .{ .path = "triangle.hgsl", .entry_point = "vert" },
        .fragment = .{ .path = "triangle.hgsl", .entry_point = "frag" },
    } });
    var cmd = try vk.allocateCommandBuffer(.main, .graphics);

    var camera_transform: huge.Transform = .{
        .position = .{ 0, 0, -5 },
    };
    var camera: huge.Camera = .{
        .aspect_ratio = window.aspectRatio(),
        .transform = &camera_transform,
    };
    _ = &camera;

    // const mesh: huge.rend.MeshRenderer = try .new(@ptrCast(&cube.vertices), u16, &cube.indices);
    var cube_transform: huge.Transform = .{
        .position = .{ -1, -1.4, 2 },
        .scale = .{ 2.5, 1, 2 },
    };
    const buff: vk.VKBuffer = try .create(@sizeOf(@TypeOf(cube.vertices)), .{ .vertex = true }, .{});
    _ = buff;

    window.disableCursor();
    var euler: math.vec3 = @splat(0);

    while (window.tick()) {
        //game update
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
        // try ubo.loadBytes(@ptrCast(@alignCast(&camera_transform.position)), 0);

        cube_transform.rotation = math.quatFromEuler(.{ 0, huge.time.seconds(), 0 });

        //render
        try vk.acquireSwapchainImage(&window.context);
        try cmd.begin();

        vk.cmdBeginRenderingToWindow(&cmd, &window.context, .{ .color = .{ 1, 0, 0, 0 } });

        window.setAttributes(.{});
        vk.cmdSetDynamicStateConfig(&cmd, .{
            .viewport = .{ .size = @floatFromInt(window.size()) },
            .scissor = .{ .size = window.size() },
            .primitive_topology = .triangle_strip,
        });

        pipeline.cmdSetPropertiesStruct(&cmd, .{
            .model = &cube_transform,
            .vp = &camera,
        });

        vk.cmdDraw(&cmd, pipeline, .{ .count = 4 });

        try vk.present(&cmd, &window.context);
    }
}

// std.debug.print("[AVG] ms: {d:.4} | FPS: {d:.2}\n", .{ avg * 1000, 1.0 / avg });
