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

    var window: huge.Window =
        try .create(.{ .title = "sample#0", .size = .{ 800, 600 } });
    defer window.close();
    window.disableCursor();

    const pipeline: vk.VKPipeline = try .createFiles(io, .{ .graphics = .{
        .vertex = .{ .path = "shader.hgsl", .entry_point = "vert" },
        .fragment = .{ .path = "shader.hgsl", .entry_point = "frag" },
    } });
    var cmd = try vk.allocateCommandBuffer(.main, .graphics);

    var camera_transform: huge.Transform = .{ .position = .{ 0, 0, -5 } };
    var camera: huge.Camera = .{
        .aspect_ratio = window.aspectRatio(),
        .transform = &camera_transform,
    };
    var cube_transform: huge.Transform = .{
        .position = .{ -1, -1.4, 2 },
        .scale = .{ 2.5, 1, 2 },
    };

    var vertex_buffer: vk.VKBuffer = try .createValue(&cube.vertices, .{ .vertex = true }, .map);
    var index_buffer: vk.VKBuffer = try .createValue(&cube.indices, .{ .index = true }, .map);
    var mvp_buffer: vk.VKBuffer = try .create(@sizeOf(math.mat) * 2, .{ .storage = true }, .persistent_small);
    const mvp_mapping: []math.mat = @ptrCast(@alignCast(try mvp_buffer.map(0)));

    //2x2 image: |purple| green|
    //           |red   | blue |
    const test_texture_bytes = [_]u8{
        156, 39,  176, 255,
        0,   244, 92,  255,
        255, 0,   0,   255,
        3,   81,  244, 255,
    };
    // _ = test_texture_bytes;
    var test_texture: vk.VKTexture = try .create(
        .{ .@"2d" = @splat(2) },
        .rgba8_norm,
        .{ .tiling = @splat(.repeat) },
        .{ .transfer_dst = true },
    );
    try test_texture.load(&test_texture_bytes);

    var euler: math.vec3 = @splat(0);
    try vk.updateDescriptorSet(&.{&mvp_buffer}, &.{}, &.{&test_texture});
    while (window.tick()) {
        //game update
        const speed = 5;
        const sensitivity = 400;

        window.firstPersonCameraMovement(&euler, sensitivity);
        camera_transform.rotation = math.quatFromEuler(euler);
        camera_transform.position += math.scale(window.warsudVector(euler[1]), huge.time.delta() * speed);

        cube_transform.rotation = math.quatFromEuler(.{ 0, huge.time.seconds(), 0 });

        mvp_mapping[0] = camera.viewProjectionMat();
        mvp_mapping[1] = cube_transform.modelMat();

        //render
        try vk.acquireSwapchainImage(&window.context);
        try cmd.begin();

        vk.cmdBeginRenderingToWindow(&cmd, &window.context, .{ .color = @splat(0.09) });
        window.setAttributes(.{});
        vk.cmdSetDynamicStateConfig(&cmd, .{
            .viewport = .{ .size = @floatFromInt(window.size()) },
            .scissor = .{ .size = window.size() },
            .cull_mode = .back,
        });

        vk.cmdPushConstantsStruct(&cmd, pipeline, .{
            .mvp_id = mvp_buffer,
            .tex_id = test_texture,
            .eye_pos = camera_transform.position,
        });
        vk.cmdBindIndexBuffer(&cmd, &index_buffer, 0, .u16);
        vk.cmdBindVertexBuffer(&cmd, &vertex_buffer, 0);

        vk.cmdDraw(&cmd, pipeline, .{ .count = cube.indices.len, .mode = .indexed });

        try vk.present(&cmd, &window.context);
    }
}

// std.debug.print("[AVG] ms: {d:.4} | FPS: {d:.2}\n", .{ avg * 1000, 1.0 / avg });
