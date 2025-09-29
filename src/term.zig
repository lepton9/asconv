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

    pub fn init(allocator: std.mem.Allocator) !*TermRenderer {
        const render = try allocator.create(TermRenderer);
        var buf: [4096]u8 = undefined;
        const stdout = std.fs.File.stdout().writer(&buf);
        render.* = .{
            .stdout = stdout,
        };
        return render;
    }

    pub fn deinit(self: *TermRenderer, allocator: std.mem.Allocator) void {
        allocator.destroy(self);
    }

    pub fn write_escaped(self: *TermRenderer, esc_seq: []const u8, buf: []const u8) !void {
        try self.stdout.interface.writeAll(esc_seq);
        try self.writef(buf);
    }

    pub fn write(self: *TermRenderer, buf: []const u8) !void {
        try self.stdout.interface.writeAll(buf);
    }

    pub fn writef(self: *TermRenderer, buf: []const u8) !void {
        try self.write(buf);
        try self.stdout.interface.flush();
    }

    pub fn print(self: *TermRenderer, comptime fmt: []const u8, args: anytype) !void {
        try self.stdout.interface.print(fmt, args);
    }

    pub fn flush(self: *TermRenderer) !void {
        try self.stdout.interface.flush();
    }

    pub fn clear_screen(self: *TermRenderer) void {
        self.stdout.interface.print("\x1b[2J", .{}) catch {};
        self.stdout.interface.flush() catch {};
    }

    pub fn cursor_hide(self: *TermRenderer) void {
        self.stdout.interface.writeAll("\x1b[?25l") catch {};
        self.stdout.interface.flush() catch {};
    }

    pub fn cursor_show(self: *TermRenderer) void {
        self.stdout.interface.writeAll("\x1b[?25h") catch {};
        self.stdout.interface.flush() catch {};
    }
};
