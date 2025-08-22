const std = @import("std");

pub const Time = struct {
    total: u64 = 0,
    scaling: u64 = 0,
    edge_detect: u64 = 0,
    converting: u64 = 0,
    writing: u64 = 0,

    pub fn init() Time {
        return Time{};
    }
};

pub const Timer = struct {
    value: *u64,
    timer: std.time.Timer,

    pub fn start(value: *u64) !Timer {
        value.* = 0;
        return .{
            .value = value,
            .timer = try std.time.Timer.start(),
        };
    }

    pub fn stop(self: Timer) void {
        var timer = self.timer;
        self.value.* = timer.read();
    }
};

pub fn to_ms(ns: u64) f64 {
    return @as(f64, @floatFromInt(ns)) / 1_000_000.0;
}

pub fn to_s(ns: u64) f64 {
    return @as(f64, @floatFromInt(ns)) / 1_000_000_000.0;
}
