const std = @import("std");
const root = @import("root.zig");
const Time = @This();

timer: std.time.Timer = undefined,

frame_time: u64 = 0,
time: u64 = 0,

avg_frame_time: f64 = 0,
avg_accumulator: u64 = 0,
avg_frame_count: u64 = 0,
pub var avg_threshold: u64 = std.time.ns_per_s / 2;

pub fn tick(self: *Time) void {
    if (self.time == 0) {
        @branchHint(.cold);
        self.timer = std.time.Timer.start() catch unreachable;
    }
    self.frame_time = self.timer.lap();
    self.time += self.frame_time;

    self.avg_accumulator += self.frame_time;
    self.avg_frame_count += 1;
    if (self.avg_accumulator >= avg_threshold) {
        self.avg_frame_time = ns2s64(self.avg_accumulator) / @as(f64, @floatFromInt(self.avg_frame_count + 1));
        self.avg_frame_count = 0;
        self.avg_accumulator = 0;
    }
}
pub fn avg(self: Time) f32 {
    return @floatCast(self.avg64());
}
pub inline fn avg64(self: Time) f64 {
    return self.avg_frame_time;
}

pub fn delta(self: Time) f32 {
    return ns2s(self.frame_time);
}
pub fn delta64(self: Time) f64 {
    return ns2s64(self.frame_time);
}
pub fn seconds(self: Time) f32 {
    return ns2s(self.time);
}
pub fn ns2s(ns: u64) f32 {
    return @as(f32, @floatFromInt(ns / 1_000)) *
        comptime (1.0 / @as(f32, @floatFromInt(std.time.us_per_s)));
}
pub fn ns2s64(ns: u64) f64 {
    return @as(f64, @floatFromInt(ns / 1_000)) *
        comptime (1.0 / @as(f64, @floatFromInt(std.time.us_per_s)));
}
