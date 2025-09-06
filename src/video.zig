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
    output_path: ?[]const u8 = null,
    writer: std.io.BufferedWriter(4096, std.fs.File.Writer) = undefined,
    fps: f64,
    frame_ns: u64,
    width: usize,
    height: usize,
    frame: []u32,
    frame_ascii_buffer: std.ArrayList(u8),
    edges: ?corelib.EdgeData = null,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, height: usize, width: usize) !*Video {
        const video = try allocator.create(Video);
        video.* = .{
            .allocator = allocator,
            .fps = 30,
            .frame_ns = 0,
            .height = height,
            .width = width,
            .frame = try allocator.alloc(u32, height * width),
            .frame_ascii_buffer = std.ArrayList(u8).init(allocator),
        };
        return video;
    }

    pub fn deinit(self: *Video) void {
        if (self.edges) |edges| {
            edges.deinit(self.allocator);
        }
        self.frame_ascii_buffer.deinit();
        self.allocator.free(self.frame);
        self.allocator.destroy(self);
    }

    pub fn set_output(self: *Video, output: ?[]const u8) void {
        if (output) |out| {
            self.mode = .Dump;
            self.output_path = out;
        } else {
            self.mode = .Realtime;
            self.output_path = null;
            const stdout_file = std.io.getStdOut().writer();
            const bw = std.io.bufferedWriter(stdout_file);
            self.writer = bw;
        }
    }

    pub fn set_edge_detection(self: *Video) !void {
        if (self.edges) |edges| {
            edges.deinit(self.allocator);
        }
        self.edges = null;
        if (!self.core.edge_detection) return;
        self.edges = try corelib.EdgeData.init(
            self.allocator,
            @intCast(self.height),
            @intCast(self.width),
        );
    }

    fn get_char(self: *Video, x: usize, y: usize) []const u8 {
        if (self.core.edge_detection) {
            if (corelib.edge_char(self.edges.?, y * self.width + x, self.core.edge_chars)) |c| {
                return c;
            }
        }
        return self.core.pixel_to_char(self.frame[y * self.width + x]);
    }

    fn pixel_to_ascii(
        self: *Video,
        buffer: *std.ArrayList(u8),
        x: usize,
        y: usize,
    ) !void {
        const c: []const u8 = self.get_char(x, y);
        if (self.core.color) switch (self.core.color_mode) {
            .color256 => try corelib.append_256_color(buffer, c, self.frame[y * self.width + x]),
            .truecolor => try corelib.append_truecolor(buffer, c, self.frame[y * self.width + x]),
        } else {
            try buffer.appendSlice(c);
            try buffer.appendSlice(c);
        }
    }

    pub fn frame_to_ascii(self: *Video) ![]const u8 {
        var timer = try corelib.time.Timer.start_add(&self.core.perf.converting);
        defer timer.stop();
        self.frame_ascii_buffer.clearRetainingCapacity();
        for (0..self.height) |y| {
            for (0..self.width) |x| {
                try self.pixel_to_ascii(&self.frame_ascii_buffer, x, y);
            }
            try self.frame_ascii_buffer.append('\n');
        }
        return self.frame_ascii_buffer.items;
    }

    fn handle_frame(self: *Video, frame_no: usize) !void {
        const ascii = try self.frame_to_ascii();
        switch (self.mode) {
            .Realtime => {
                try print_frame(&self.writer, ascii);
                std.time.sleep(self.frame_ns);
            },
            .Dump => {
                try dump_frame(self.allocator, frame_no, ascii, self.output_path.?);
            },
        }
    }

    fn process_frame(video: *Video) !void {
        if (video.core.edge_detection) {
            var timer = try corelib.time.Timer.start_add(&video.core.perf.edge_detect);
            defer timer.stop();
            try corelib.calc_edges(
                video.allocator,
                video.core.*,
                video.edges.?,
                video.frame,
                video.width,
                video.height,
            );
        }
    }
};

pub fn process_video(
    allocator: std.mem.Allocator,
    core: *corelib.Core,
    path: []const u8,
    output: ?[]const u8,
) !void {
    var timer_read = try corelib.time.Timer.start(&core.perf.read);
    const fmt_ctx: *av.FormatCtx = try av.open_video_file(path);
    const video_stream_index: usize = try av.get_stream_ind(fmt_ctx);
    const codec_ctx: *av.CodecCtx = try av.get_decoder(fmt_ctx, video_stream_index);
    var packet: av.Packet = undefined;

    var width: usize = @intCast(codec_ctx.width);
    var height: usize = @intCast(codec_ctx.height);
    try core.apply_scale(&width, &height);

    var frame: *av.Frame = av.frame_alloc();
    defer av.frame_free(&frame);
    var frame_rgba: *av.Frame = av.frame_alloc();
    defer av.frame_free(&frame_rgba);
    frame_rgba.width = @intCast(width);
    frame_rgba.height = @intCast(height);
    frame_rgba.format = av.PIX_FMT_RGBA;
    if (av.frame_get_buffer(frame_rgba, 32) < 0) return error.NoFrameBuffer;

    const sws = av.sws_get_context(
        codec_ctx.width,
        codec_ctx.height,
        codec_ctx.pix_fmt,
        frame_rgba.width,
        frame_rgba.height,
        av.PIX_FMT_RGBA,
        av.SWS_BILINEAR,
        null,
        null,
        null,
    );
    timer_read.stop();

    var video = try Video.init(allocator, height, width);
    defer video.deinit();
    video.core = core;
    video.set_output(output);
    try video.set_edge_detection();
    if (video.mode == .Realtime) try clear_screen(&video.writer);

    const stream = fmt_ctx.*.streams[video_stream_index];
    video.fps = @as(f64, @floatFromInt(stream.*.avg_frame_rate.num)) /
        @as(f64, @floatFromInt(stream.*.avg_frame_rate.den));
    video.frame_ns = @intFromFloat(1_000_000_000 / video.fps);

    core.perf.fps = 0;
    var timer_fps = try corelib.time.Timer.start_add(&core.perf.fps.?);

    core.perf.frames_n = 0;
    while (av.read_frame(fmt_ctx, &packet) >= 0) {
        if (packet.stream_index == video_stream_index) {
            if (av.send_packet(codec_ctx, &packet) == 0) {
                while (av.receive_frame(codec_ctx, frame) == 0) {
                    var timer_scale = try corelib.time.Timer.start_add(&video.core.perf.scaling);
                    if (av.sws_scale(
                        sws,
                        @ptrCast(&frame.*.data),
                        @ptrCast(&frame.*.linesize),
                        0,
                        codec_ctx.height,
                        &frame_rgba.*.data,
                        &frame_rgba.*.linesize,
                    ) < 0) return error.ScaleError;
                    try compress_frame(frame_rgba, video.frame);
                    timer_scale.stop();

                    try video.process_frame();
                    try video.handle_frame(core.perf.frames_n.?);
                    core.perf.frames_n.? += 1;
                }
            }
        }
        av.packet_unref(&packet);
    }
    timer_fps.stop();
}

fn compress_frame(frame: *av.Frame, dst: []u32) !void {
    const width: usize = @intCast(frame.width);
    const height: usize = @intCast(frame.height);
    const bpp: usize = 4;
    const row_stride: usize = @intCast(frame.linesize[0]);
    const src: [*]u8 = @ptrCast(@alignCast(frame.data[0]));
    const little_endian: bool = comptime @byteSwap(@as(i8, 1)) == 1;

    for (0..height) |y| {
        const src_row = src[y * row_stride .. y * row_stride + width * bpp];
        const dst_row = dst[y * width .. (y + 1) * width];
        const dst_bytes: []u8 = @ptrCast(dst_row);
        @memcpy(dst_bytes[0 .. width * bpp], src_row);

        if (!little_endian) continue;
        for (dst_row) |*pix| {
            pix.* = @byteSwap(pix.*);
        }
    }
}

fn clear_screen(bw: *std.io.BufferedWriter(4096, std.fs.File.Writer)) !void {
    try bw.writer().writeAll("\x1b[2J");
    try bw.flush();
}

fn print_frame(
    bw: *std.io.BufferedWriter(4096, std.fs.File.Writer),
    ascii: []const u8,
) !void {
    const writer = bw.writer();
    try writer.writeAll("\x1b[H");
    try writer.writeAll(ascii);
    try bw.flush();
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
