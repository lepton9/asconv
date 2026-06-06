const std = @import("std");
const builtin = @import("builtin");

pub const Input = struct {
    key_queue: std.ArrayList(u8),
    stdin: std.Io.File.Reader = undefined,
    read_buf: [8]u8 = undefined,
    raw_input: bool,
    exit: bool = false,
    mutex: std.Io.Mutex,
    allocator: std.mem.Allocator,
    io: std.Io,

    pub fn init(io: std.Io, gpa: std.mem.Allocator, raw_input: bool) !*Input {
        const input = try gpa.create(Input);
        input.* = .{
            .key_queue = try std.ArrayList(u8).initCapacity(gpa, 10),
            .raw_input = raw_input,
            .mutex = std.Io.Mutex.init,
            .allocator = gpa,
            .io = io,
        };
        input.stdin = std.Io.File.stdin().reader(io, &input.read_buf);
        return input;
    }

    pub fn deinit(self: *Input) void {
        self.key_queue.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn run(self: *Input) !void {
        var stdin = std.Io.File.stdin();
        // Exit if stdin is not a terminal

        if (!(stdin.isTty(self.io) catch false)) {
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

    pub fn endInputDetection(self: *Input) !void {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        self.exit = true;
    }

    fn detectKeyPress(self: *Input) ?u8 {
        return self.stdin.interface.takeByte() catch null;
    }

    fn handleKeyPress(self: *Input, key: u8) !void {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        try self.key_queue.insert(self.allocator, 0, key);
    }

    pub fn getKey(self: *Input) ?u8 {
        self.mutex.lock(self.io) catch return null;
        defer self.mutex.unlock(self.io);
        return self.key_queue.pop();
    }
};

fn rawModeOn(stdin: *const std.Io.File) !void {
    if (builtin.os.tag == .windows) return;
    var term = try std.posix.tcgetattr(stdin.handle);
    term.lflag.ICANON = false;
    term.lflag.ECHO = false;
    try std.posix.tcsetattr(stdin.handle, .NOW, term);
}

fn rawModeOff(stdin: *const std.Io.File) !void {
    if (builtin.os.tag == .windows) return;
    const term = try std.posix.tcgetattr(stdin.handle);
    try std.posix.tcsetattr(stdin.handle, .NOW, term);
}
