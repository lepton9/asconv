const std = @import("std");
const corelib = @import("core");

pub const OutputMode = enum {
    Realtime,
    Dump,
};

pub const Video = struct {
    core: *corelib.Core = undefined,
    mode: OutputMode = .Realtime,
    output_path: ?[]const u8,
    fps: f64,
    frame_ns: u64,
    width: usize,
    height: usize,
    frame: []u32,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, height: usize, width: usize) !*Video {
        var video = try allocator.create(Video);
        video.allocator = allocator;
        video.height = height;
        video.width = width;
        video.frame = try allocator.alloc(u32, height * width);
        @memset(video.frame, 0);
        return video;
    }

    pub fn deinit(self: *Video) void {
        self.allocator.free(self.frame);
        self.allocator.destroy(self);
    }

    fn pixel_to_ascii(
        self: *Video,
        buffer: *std.ArrayList(u8),
        x: usize,
        y: usize,
    ) !void {
        const c: []const u8 = self.core.pixel_to_char(self.frame[y * self.width + x]);
        try buffer.appendSlice(c);
        try buffer.appendSlice(c);
    }

    pub fn frame_to_ascii(self: *Video) ![]const u8 {
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();
        for (0..self.height) |y| {
            for (0..self.width) |x| {
                try self.pixel_to_ascii(&buffer, x, y);
            }
            try buffer.appendSlice("\n");
        }
        return buffer.toOwnedSlice();
    }

    fn handle_frame(self: *Video, frame_no: usize) !void {
        const ascii = try self.frame_to_ascii();
        defer self.allocator.free(ascii);

        switch (self.mode) {
            .Realtime => {
                std.debug.print("{s}\n", .{ascii});
                std.time.sleep(self.frame_ns);
                std.debug.print("\x1b[H", .{});
            },
            .Dump => {
                try dump_frame(self.allocator, frame_no, ascii, self.output_path.?);
            },
        }
    }
};

fn dump_frame(
    allocator: std.mem.Allocator,
    frame_no: usize,
    ascii: []const u8,
    output_path: []const u8,
) !void {
    const filename = try std.fmt.allocPrint(allocator, "frame_{d:05}.txt", .{frame_no});
    defer allocator.free(filename);

    const path = try std.fs.path.join(allocator, &.{ output_path, filename });
    defer allocator.free(path);

    var file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(ascii);
}
