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
    var info: std.os.windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;

    if (win.kernel32.GetConsoleScreenBufferInfo(win.STD_OUTPUT_HANDLE, &info) == win.FALSE)
        switch (win.kernel32.GetLastError()) {
            else => |e| return win.unexpectedError(e),
        };

    return TermSize{
        .height = @intCast(info.srWindow.Bottom - info.srWindow.Top),
        .width = @intCast(info.srWindow.Right - info.srWindow.Left),
    };
}
