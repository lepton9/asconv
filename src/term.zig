const std = @import("std");

const TermSize = struct {
    width: u16,
    height: u16,
};

pub fn get_term_size() !TermSize {
    if (@import("builtin").os.tag == .windows) {
        return term_size_windows();
    } else {
        return term_size_linux();
    }
}

fn term_size_linux() !TermSize {
    const posix = std.posix;
    var ws: posix.winsize = undefined;
    const err = posix.system.ioctl(
        std.fs.File.stdout().handle,
        posix.T.IOCGWINSZ,
        @intFromPtr(&ws),
    );
    if (posix.errno(err) == .SUCCESS) {
        return TermSize{
            .width = ws.col,
            .height = ws.row,
        };
    }
    return error.IoctlError;
}

fn term_size_windows() !TermSize {
    const win = std.os.windows;
    var info: std.os.windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;

    if (win.kernel32.GetConsoleScreenBufferInfo(try win.GetStdHandle(win.STD_OUTPUT_HANDLE), &info) == win.FALSE)
        switch (win.kernel32.GetLastError()) {
            else => |e| return win.unexpectedError(e),
        };

    return TermSize{
        .height = @intCast(info.srWindow.Bottom - info.srWindow.Top),
        .width = @intCast(info.srWindow.Right - info.srWindow.Left),
    };
}

pub const TermRenderer = struct {
    stdout: std.fs.File.Writer,
    buffer: ?[]u8,

    pub fn init(allocator: std.mem.Allocator, buffer_size: ?usize) !*TermRenderer {
        const render = try allocator.create(TermRenderer);
        render.buffer = if (buffer_size) |size|
            try allocator.alloc(u8, size)
        else
            null;
        render.stdout = std.fs.File.stdout().writer(render.buffer orelse &.{});
        return render;
    }

    pub fn deinit(self: *TermRenderer, allocator: std.mem.Allocator) void {
        if (self.buffer) |buf| allocator.free(buf);
        allocator.destroy(self);
    }

    pub fn write(self: *TermRenderer, buf: []const u8) !void {
        try self.stdout.interface.writeAll(buf);
    }

    pub fn writef(self: *TermRenderer, buf: []const u8) !void {
        try self.write(buf);
        try self.flush();
    }

    pub fn print(self: *TermRenderer, comptime fmt: []const u8, args: anytype) !void {
        try self.stdout.interface.print(fmt, args);
    }

    pub fn printf(self: *TermRenderer, comptime fmt: []const u8, args: anytype) !void {
        try self.print(fmt, args);
        try self.flush();
    }

    pub fn flush(self: *TermRenderer) !void {
        try self.stdout.interface.flush();
    }

    pub fn clear_screen(self: *TermRenderer) void {
        self.writef("\x1b[2J") catch {};
    }

    pub fn cursor_hide(self: *TermRenderer) void {
        self.writef("\x1b[?25l") catch {};
    }

    pub fn cursor_show(self: *TermRenderer) void {
        self.writef("\x1b[?25h") catch {};
    }
};
