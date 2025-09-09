comptime {
    _ = @import("ascii.zig");

    if (@import("exec").build_options.video) {
        _ = @import("ascii_video.zig");
    }
}
