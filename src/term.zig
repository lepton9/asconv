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
        std.io.getStdOut().handle,
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
    var info: std.os.windows.CONSOLE_SCREEN_BUFFER_INFO = .{
        .dwSize = .{ .X = 0, .Y = 0 },
        .dwCursorPosition = .{ .X = 0, .Y = 0 },
        .wAttributes = 0,
        .srWindow = .{ .Left = 0, .Top = 0, .Right = 0, .Bottom = 0 },
        .dwMaximumWindowSize = .{ .X = 0, .Y = 0 },
    };

    if (win.kernel32.GetConsoleScreenBufferInfo(win.STD_OUTPUT_HANDLE, &info) == 0) switch (win.kernel32.GetLastError()) {
        else => |e| return std.os.windows.unexpectedError(e),
    };

    return TermSize{
        .height = @intCast(info.srWindow.Bottom - info.srWindow.Top + 1),
        .width = @intCast(info.srWindow.Right - info.srWindow.Left + 1),
    };
}
