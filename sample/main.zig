const std = @import("std");
const huge = @import("huge");
const vk = huge.vk;

pub fn main() !void {
    try huge.init();
    defer huge.deinit();
    huge.Time.avg_threshold = 5 * std.time.ns_per_s;

    var window: huge.Window = try .create(.{ .title = "sample#0", .size = .{ 800, 600 } });
    defer window.close();

    const pipeline: vk.VKPipeline = try .create();

    var cmd = try vk.allocateCommandBuffer(.main, .graphics);
    std.debug.print("handles: {any}\n", .{cmd.handles});

    var avg: f64 = 0;
    while (window.tick()) {
        if (huge.time.avg64() != avg) {
            avg = huge.time.avg64();
            std.debug.print("AVGFPS: {d}\n", .{1.0 / avg});
        }
        try vk.acquireSwapchainImage(&window.context);
        try cmd.begin();

        vk.cmdBeginRenderingToWindow(&cmd, &window.context, .{ .color = .{ 1, 0, 0, 0 } });

        vk.cmdDraw(&cmd, pipeline, .{ .count = 3 });

        try vk.present(&cmd, &window.context);
    }

    // const cmd = try vk.createCmd(.main, .graphics);
    // vk.submit(&.{cmd});
}
// var thread_ids: [1]vk.ThreadID = undefined;
// try vk.initAdditionalThreadResources(&thread_ids);
// std.debug.print("tids: {any}\n", .{thread_ids});
// const cmd = try vk.createCmd(.main, .graphics);

// cmd.begin();
// _async(struct {
//     pub fn f(
//         cmd: vk.CommandBuffer,
//         pipeline: vk.Pipeline,
//     ) void {
//         vk.cmdBindPipeline(cmd, pipeline);
//         pipeline.cmdSetAttributeStruct(cmd, .{});
//         vk.cmdDraw(cmd, .{});
//     }
// }.f);
// cmd.end();
