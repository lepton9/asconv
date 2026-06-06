const std = @import("std");

pub const Stats = struct {
    total_ms: u64 = 0,
    scaling_ms: u64 = 0,
    edge_detect_ms: u64 = 0,
    converting_ms: u64 = 0,
    read_ms: u64 = 0,
    write_ms: u64 = 0,
    fps: ?u64 = null,
    frames_n: ?usize = null,
    dropped_frames: ?usize = null,

    pub fn init() Stats {
        return Stats{};
    }
};

pub const Timer = struct {
    value: *u64,
    timer: std.Io.Timestamp,

    pub fn start(io: std.Io, value: *u64) !Timer {
        value.* = 0;
        return start_add(io, value);
    }

    pub fn start_add(io: std.Io, value: *u64) !Timer {
        return .{
            .value = value,
            .timer = std.Io.Clock.awake.now(io),
        };
    }

    pub fn stop(self: *Timer, io: std.Io) void {
        self.value.* += self.read(io);
    }

    pub fn read(self: *Timer, io: std.Io) u64 {
        const elapsed = self.timer.untilNow(io, .awake);
        return @intCast(elapsed.toMilliseconds());
    }

    // pub fn reset(self: *Timer) void {
    //     _ = self;
    //     // self.timer.reset();
    // }
};

pub fn to_s(ms: u64) f64 {
    return @as(f64, @floatFromInt(ms)) / 1_000.0;
}
