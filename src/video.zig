const std = @import("std");
const av = @import("av");
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

pub fn process_video(
    allocator: std.mem.Allocator,
    core: *corelib.Core,
    path: []const u8,
    output: ?[]const u8,
) !void {
    const fmt_ctx: *av.FormatCtx = try av.open_video_file(path);
    const video_stream_index: usize = try av.get_stream_ind(fmt_ctx);
    const codec_ctx: *av.CodecCtx = try av.get_decoder(fmt_ctx, video_stream_index);
    var packet: av.Packet = undefined;

    const sws = av.sws_get_context(
        codec_ctx.width,
        codec_ctx.height,
        codec_ctx.pix_fmt,
        codec_ctx.width,
        codec_ctx.height,
        av.PIX_FMT_RGBA,
        av.SWS_BILINEAR,
        null,
        null,
        null,
    );

    var frame: *av.Frame = av.frame_alloc();
    defer av.frame_free(&frame);
    var frame_rgba: *av.Frame = av.frame_alloc();
    defer av.frame_free(&frame_rgba);
    frame_rgba.format = av.PIX_FMT_RGBA;
    frame_rgba.width = codec_ctx.width;
    frame_rgba.height = codec_ctx.height;
    if (av.frame_get_buffer(frame_rgba, 32) < 0) return error.NoFrameBuffer;

    const rgba_buf: []u32 = try allocator.alloc(
        u32,
        @intCast(frame_rgba.width * frame_rgba.height),
    );
    defer allocator.free(rgba_buf);

    var width: usize = @intCast(frame_rgba.width);
    var height: usize = @intCast(frame_rgba.height);
    try core.apply_scale(&width, &height);

    var video = try Video.init(allocator, height, width);
    video.output_path = output;
    video.mode = if (output) |_| .Dump else .Realtime;
    video.core = core;
    defer video.deinit();

    const stream = fmt_ctx.*.streams[video_stream_index];
    video.fps = @as(f64, @floatFromInt(stream.*.avg_frame_rate.num)) /
        @as(f64, @floatFromInt(stream.*.avg_frame_rate.den));
    video.frame_ns = @intFromFloat(1_000_000_000 / video.fps);

    var frame_count: usize = 0;
    while (av.read_frame(fmt_ctx, &packet) >= 0) {
        if (packet.stream_index == video_stream_index) {
            if (av.send_packet(codec_ctx, &packet) == 0) {
                while (av.receive_frame(codec_ctx, frame) == 0) {
                    _ = av.sws_scale(
                        sws,
                        @ptrCast(&frame.*.data),
                        @ptrCast(&frame.*.linesize),
                        0,
                        codec_ctx.height,
                        &frame_rgba.*.data,
                        &frame_rgba.*.linesize,
                    );

                    try compress_frame(frame_rgba, rgba_buf);

                    corelib.scale_nearest(
                        rgba_buf,
                        video.frame,
                        @intCast(frame_rgba.width),
                        @intCast(frame_rgba.height),
                        video.width,
                        video.height,
                    );

                    try video.handle_frame(frame_count);
                    frame_count += 1;
                }
            }
        }
        av.packet_unref(&packet);
    }
}

pub fn compress_frame(frame: *av.Frame, dst: []u32) !void {
    const width: usize = @intCast(frame.width);
    const height: usize = @intCast(frame.height);
    const row_stride: usize = @as(usize, @intCast(frame.linesize[0])) / @sizeOf(u32);
    const buf_ptr: [*]u32 = @ptrCast(@alignCast(frame.data[0]));

    for (0..height) |y| {
        const src_row = buf_ptr[y * row_stride .. y * row_stride + width];
        const dst_row = dst[y * width .. (y + 1) * width];
        @memcpy(dst_row, src_row);
    }
}

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
