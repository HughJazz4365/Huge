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
        try .create(.{ .title = "sample#0", .size = huge.Window.HD });
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
    var mvp_buffer: vk.VKBuffer = try .create(@sizeOf(math.mat) * 2, .{ .storage = true }, .persistent);
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
        .{ .@"2d" = @splat(16) },
        .rgba8_norm,
        .{ .tiling = @splat(.repeat), .expand = .linear },
        .{ .transfer_dst = true },
    );
    _ = &test_texture_bytes;
    try test_texture.load(&testGradientTextureBytes(16, .{ 1, 0, 0, 1 }, .{ 0, 1, 0, 1 }));

    var euler: math.vec3 = @splat(0);
    try vk.updateDescriptorSet(&.{&mvp_buffer}, &.{}, &.{&test_texture});
    var avg: f64 = 0;
    while (window.tick()) {
        if (avg != huge.time.avg64()) {
            avg = huge.time.avg64();
            std.debug.print("[AVG] ms: {d:.4} | FPS: {d:.2}\n", .{ avg * 1000, 1.0 / avg });
        }
        //game update
        const speed = 5;
        const sensitivity = 1;

        window.firstPersonCameraMovement(&euler, sensitivity);
        camera_transform.rotation = math.quatFromEuler(euler);
        camera_transform.position += math.scale(window.warsudVector(euler[1]), huge.time.delta() * speed);

        cube_transform.rotation = math.quatFromEuler(.{ 0, huge.time.seconds() * 0.3, 0 });

        mvp_mapping[0] = camera.viewProjectionMat();
        mvp_mapping[1] = cube_transform.modelMat();

        //render
        try vk.acquireSwapchainImage(&window.context);
        try cmd.begin();

        vk.cmdBeginRenderingToWindow(&cmd, &window.context, .{ .color = @splat(0.09) });
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

fn testGradientTextureBytes(comptime dim: usize, comptime a_color: math.vec4, comptime b_color: math.vec4) [dim * dim * 4]u8 {
    var result: [dim * dim * 4]u8 = undefined;
    for (0..dim) |x| {
        for (0..dim) |y| {
            const value = math.cast(f32, x + y) / math.cast(f32, dim + dim);
            const c = math.scale(std.math.clamp(
                std.math.lerp(a_color, b_color, math.cast(math.vec4, value)),
                math.zero(math.vec4),
                math.one(math.vec4),
            ), 255);
            const byte_vec = math.cast(@Vector(4, u8), c);
            inline for (0..4) |i| result[(y * dim + x) * 4 + i] = byte_vec[i];
        }
    }
    return result;
}
