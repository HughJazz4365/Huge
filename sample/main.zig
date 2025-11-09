const std = @import("std");
const huge = @import("huge");

pub fn main() !void {
    try huge.init();
    defer huge.deinit();

    var window = try huge.Window.create(.{ .title = "sample#0", .size = huge.Window.HD });
    defer window.destroy();

    while (!window.shouldClose()) {
        window.frameEnd();
    }
}
