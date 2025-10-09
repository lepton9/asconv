const std = @import("std");
const builtin = @import("builtin");

pub const Input = struct {
    key_queue: std.ArrayList(u8),
    stdin: std.fs.File.Reader,
    raw_input: bool,
    exit: bool = false,
    mutex: std.Thread.Mutex,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, raw_input: bool) !*Input {
        const input = try allocator.create(Input);
        var buf: [8]u8 = undefined;
        input.* = .{
            .key_queue = try std.ArrayList(u8).initCapacity(allocator, 10),
            .stdin = std.fs.File.stdin().reader(&buf),
            .raw_input = raw_input,
            .mutex = std.Thread.Mutex{},
            .allocator = allocator,
        };
        return input;
    }

    pub fn deinit(self: *Input) void {
        self.key_queue.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn run(self: *Input) !void {
        var stdin = std.fs.File.stdin();
        // Exit if stdin is not a terminal
        if (!std.posix.isatty(stdin.handle)) {
            self.exit = true;
            return;
        }
        if (self.raw_input) try rawModeOn(&stdin);
        while (!self.exit) {
            const key = self.detectKeyPress();
            if (key) |k| try self.handleKeyPress(k);
        }
        if (self.raw_input) try rawModeOff(&stdin);
    }

    pub fn endInputDetection(self: *Input) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.exit = true;
    }

    fn detectKeyPress(self: *Input) ?u8 {
        return self.stdin.interface.takeByte() catch null;
    }

    fn handleKeyPress(self: *Input, key: u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.key_queue.insert(self.allocator, 0, key);
    }

    pub fn getKey(self: *Input) ?u8 {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.key_queue.pop();
    }
};

fn rawModeOn(stdin: *const std.fs.File) !void {
    var term = try std.posix.tcgetattr(stdin.handle);
    term.lflag.ICANON = false;
    term.lflag.ECHO = false;
    try std.posix.tcsetattr(stdin.handle, .NOW, term);
}

fn rawModeOff(stdin: *const std.fs.File) !void {
    const term = try std.posix.tcgetattr(stdin.handle);
    try std.posix.tcsetattr(stdin.handle, .NOW, term);
}
