const std = @import("std");

pub const Stats = struct {
    total_ns: u64 = 0,
    scaling_ns: u64 = 0,
    edge_detect_ns: u64 = 0,
    converting_ns: u64 = 0,
    read_ns: u64 = 0,
    write_ns: u64 = 0,
    fps: ?u64 = null,
    frames_n: ?usize = null,
    dropped_frames: ?usize = null,

    pub fn init() Stats {
        return Stats{};
    }
};

pub const Timer = struct {
    timestamp: std.Io.Timestamp,
    value: *u64,
    unit: enum { ms, ns } = .ns,

    pub fn start(io: std.Io, value: *u64) !Timer {
        value.* = 0;
        return start_add(io, value);
    }

    pub fn start_add(io: std.Io, value: *u64) !Timer {
        return .{
            .value = value,
            .timestamp = std.Io.Clock.awake.now(io),
        };
    }

    pub fn stop(self: *Timer, io: std.Io) void {
        self.value.* += self.read(io);
    }

    pub fn read(self: *Timer, io: std.Io) u64 {
        const elapsed = self.read_elapsed(io);
        return switch (self.unit) {
            .ms => @intCast(elapsed.toMilliseconds()),
            .ns => @intCast(@as(i64, @truncate(elapsed.toNanoseconds()))),
        };
    }

    pub fn read_elapsed(self: *Timer, io: std.Io) std.Io.Duration {
        return self.timestamp.untilNow(io, .awake);
    }

    pub fn reset(self: *Timer, io: std.Io) void {
        self.timestamp = std.Io.Clock.awake.now(io);
    }
};

pub fn to_s(ns: u64) f64 {
    return @as(f64, @floatFromInt(ns)) / 1_000_000_000.0;
}
