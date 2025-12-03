const std = @import("std");
const huge = @import("huge");

pub fn main() !void {
    try huge.init();
    defer huge.deinit();
    huge.Time.avg_threshold = 5 * std.time.ns_per_s;

    var window: huge.Window = try .create(.{ .title = "sample#0", .size = .{ 800, 600 } });
    defer window.destroy();
    // const f = io.async(struct{pub fn func(cmd){
    //     cmd.recordStuff(...)
    // });
    // f.await()//and it should just work

    // maybe difference in synchronisation between
    // single queue devices and not is irrelevant with timeline semaphores
}
