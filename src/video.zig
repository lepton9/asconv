const std = @import("std");
const av = @import("av");
const corelib = @import("core");
const term = @import("term");

pub const OutputMode = enum {
    Realtime,
    Dump,
};

const Render = struct {
    width: usize,
    height: usize,
    frames_total: usize = 0,
    show_progress: bool = false,
    bar_width: usize = 40,
    mode: OutputMode = .Realtime,
    output_path: ?[]const u8 = null,
    stdout: *term.TermRenderer,

    fn init(allocator: std.mem.Allocator, height: usize, width: usize) !*Render {
        const render = try allocator.create(Render);
        const stdout = try term.TermRenderer.init(allocator);
        render.* = .{
            .width = width,
            .height = height,
            .stdout = stdout,
        };
        return render;
    }

    fn deinit(self: *Render, allocator: std.mem.Allocator) void {
        self.stdout.deinit(allocator);
        allocator.destroy(self);
    }

    fn set_output(self: *Render, output: ?[]const u8) !void {
        self.output_path = output;
        if (output) |out| {
            self.mode = .Dump;
            try std.fs.cwd().makePath(out);
        } else {
            self.mode = .Realtime;
            self.stdout.clear_screen();
            self.stdout.cursor_hide();
        }
    }

    fn cleanup(self: *Render) void {
        if (self.mode == .Realtime) self.stdout.cursor_show();
    }

    fn handle_frame(
        self: *Render,
        allocator: std.mem.Allocator,
        frame: []const u8,
        frame_no: usize,
    ) !void {
        switch (self.mode) {
            .Realtime => {
                try self.print_frame(frame);
            },
            .Dump => {
                try self.dump_frame(allocator, frame, frame_no);
            },
        }
        if (self.show_progress) self.print_progress(frame_no);
    }

    fn print_frame(self: *Render, frame: []const u8) !void {
        try self.stdout.printf("\x1b[H{s}", .{frame});
    }

    fn dump_frame(
        self: *Render,
        allocator: std.mem.Allocator,
        frame: []const u8,
        frame_no: usize,
    ) !void {
        const filename = try std.fmt.allocPrint(
            allocator,
            "frame_{d:05}.txt",
            .{frame_no},
        );
        defer allocator.free(filename);

        const path = try std.fs.path.join(allocator, &.{ self.output_path.?, filename });
        defer allocator.free(path);

        var file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        try file.writeAll(frame);
    }

    fn print_progress(self: *Render, frame_no: usize) void {
        if (self.frames_total == 0) return;
        var stdout = self.stdout;
        const percentage: f64 = @as(f64, @floatFromInt(frame_no)) /
            @as(f64, @floatFromInt(self.frames_total));
        const filled: usize = @intFromFloat(@ceil(percentage *
            @as(f64, @floatFromInt(self.bar_width))));
        const empty: usize = self.bar_width - filled;

        stdout.write("\x1b[0G\x1b[0K") catch {};
        stdout.write("[") catch {};
        for (0..filled) |_| stdout.write("#") catch {};
        for (0..empty) |_| stdout.write("-") catch {};
        stdout.writef("] ") catch {};
        stdout.printf("{d:.0}%", .{percentage * 100}) catch {};
    }
};

pub const Video = struct {
    core: *corelib.Core = undefined,
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
            .frame_ascii_buffer = try std.ArrayList(u8).initCapacity(
                allocator,
                width * height * 256,
            ),
        };
        return video;
    }

    pub fn deinit(self: *Video) void {
        if (self.edges) |edges| {
            edges.deinit(self.allocator);
        }
        self.frame_ascii_buffer.deinit(self.allocator);
        self.allocator.free(self.frame);
        self.allocator.destroy(self);
    }

    fn set_edge_detection(self: *Video) !void {
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

    fn set_target_fps(self: *Video, fps: f64) void {
        self.fps = fps;
        self.frame_ns = @intFromFloat(std.time.ns_per_s / fps);
        self.core.stats.fps = 0;
        self.core.stats.frames_n = 0;
        self.core.stats.dropped_frames = 0;
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
            .color256 => try corelib.append_256_color(self.allocator, buffer, c, self.frame[y * self.width + x]),
            .truecolor => try corelib.append_truecolor(self.allocator, buffer, c, self.frame[y * self.width + x]),
        } else {
            try buffer.appendSlice(self.allocator, c);
            try buffer.appendSlice(self.allocator, c);
        }
    }

    fn frame_to_ascii(self: *Video) ![]const u8 {
        var timer = try corelib.time.Timer.start_add(&self.core.stats.converting);
        defer timer.stop();
        self.frame_ascii_buffer.clearRetainingCapacity();
        for (0..self.height) |y| {
            for (0..self.width) |x| {
                try self.pixel_to_ascii(&self.frame_ascii_buffer, x, y);
            }
            if (y < self.height - 1) try self.frame_ascii_buffer.append(self.allocator, '\n');
        }
        return self.frame_ascii_buffer.items;
    }

    fn process_frame(video: *Video) !void {
        if (video.core.edge_detection) {
            var timer = try corelib.time.Timer.start_add(&video.core.stats.edge_detect);
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
    display_progress: bool,
) !void {
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

    var video = try Video.init(allocator, height, width);
    defer video.deinit();
    video.core = core;
    try video.set_edge_detection();

    var render = try Render.init(allocator, height, width);
    defer render.deinit(allocator);
    try render.set_output(output);
    defer render.cleanup();

    const stream: *av.Stream = fmt_ctx.*.streams[video_stream_index];
    const target_fps = core.fps orelse @as(f64, @floatFromInt(stream.*.avg_frame_rate.num)) /
        @as(f64, @floatFromInt(stream.*.avg_frame_rate.den));
    video.set_target_fps(target_fps);
    render.frames_total = total_frames(stream);
    render.show_progress = display_progress;

    var timer_read = try corelib.time.Timer.start(&core.stats.read);
    var timer_fps = try corelib.time.Timer.start(&core.stats.fps.?);

    while (av.read_frame(fmt_ctx, &packet) >= 0) {
        if (packet.stream_index == video_stream_index) {
            defer av.packet_unref(&packet);

            if (av.send_packet(codec_ctx, &packet) != 0) continue;
            while (av.receive_frame(codec_ctx, frame) == 0) {
                timer_read.stop();
                defer timer_read.reset();
                if (render.mode == .Realtime and core.drop_frames) {
                    const target_time = core.stats.frames_n.? * video.frame_ns;
                    const elapsed = timer_fps.read();
                    if (elapsed > target_time + video.frame_ns) {
                        // More than 1 frame late
                        core.stats.frames_n.? += 1;
                        core.stats.dropped_frames.? += 1;
                        continue;
                    }
                }

                var timer_scale = try corelib.time.Timer.start_add(&video.core.stats.scaling);
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

                try render.handle_frame(
                    allocator,
                    try video.frame_to_ascii(),
                    core.stats.frames_n.?,
                );

                core.stats.frames_n.? += 1;
                if (render.mode == .Dump) continue;

                // Target time for the next frame
                const next_target_time = (core.stats.frames_n.?) * video.frame_ns;
                const now = timer_fps.read();
                if (now < next_target_time) {
                    std.Thread.sleep(next_target_time - now);
                }
            }
        }
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

fn total_frames(stream: *av.Stream) usize {
    if (stream.nb_frames > 0) {
        return @intCast(stream.nb_frames);
    }
    if (stream.duration > 0 and stream.avg_frame_rate.den != 0) {
        const duration_sec = @as(f64, @floatFromInt(stream.duration)) *
            @as(f64, @floatFromInt(stream.time_base.num)) /
            @as(f64, @floatFromInt(stream.time_base.den));

        const fps = @as(f64, @floatFromInt(stream.avg_frame_rate.num)) /
            @as(f64, @floatFromInt(stream.avg_frame_rate.den));

        if (fps > 0) {
            return @intFromFloat(duration_sec * fps);
        }
    }
    return 0;
}
