const std = @import("std");

pub const Stats = struct {
    total: u64 = 0,
    scaling: u64 = 0,
    edge_detect: u64 = 0,
    converting: u64 = 0,
    read: u64 = 0,
    write: u64 = 0,
    fps: ?u64 = null,
    frames_n: ?usize = null,
    dropped_frames: ?usize = null,

    pub fn init() Stats {
        return Stats{};
    }
};

pub const Timer = struct {
    value: *u64,
    timer: std.time.Timer,

    pub fn start(value: *u64) !Timer {
        value.* = 0;
        return start_add(value);
    }

    pub fn start_add(value: *u64) !Timer {
        return .{
            .value = value,
            .timer = try std.time.Timer.start(),
        };
    }

    pub fn stop(self: *Timer) void {
        self.value.* += self.read();
    }

    pub fn read(self: *Timer) u64 {
        return self.timer.read();
    }

    pub fn reset(self: *Timer) void {
        self.timer.reset();
    }
};

pub fn to_ms(ns: u64) f64 {
    return @as(f64, @floatFromInt(ns)) / 1_000_000.0;
}

pub fn to_s(ns: u64) f64 {
    return @as(f64, @floatFromInt(ns)) / 1_000_000_000.0;
}
