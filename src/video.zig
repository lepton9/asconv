const std = @import("std");
const corelib = @import("core");
const term = @import("term");
const ffmpeg = @import("ffmpeg");

const Input = @import("input").Input;

pub const OutputMode = enum {
    Realtime,
    Dump,
};

pub const AVError = error{
    InputFileNotFound,
    NoVideoStream,
    CannotOpenDecoder,
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
    io: std.Io,

    fn init(io: std.Io, gpa: std.mem.Allocator, height: usize, width: usize) !*Render {
        const render = try gpa.create(Render);
        const stdout = try term.TermRenderer.init(io, gpa, 4096);
        render.* = .{
            .width = width,
            .height = height,
            .stdout = stdout,
            .io = io,
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
            try std.Io.Dir.cwd().createDirPath(self.io, out);
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
        if (self.show_progress) try self.print_progress(frame_no);
    }

    fn print_frame(self: *Render, frame: []const u8) !void {
        try self.stdout.writef("\x1b[H");
        try self.stdout.writef(frame);
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

        var file = try std.Io.Dir.cwd().createFile(self.io, path, .{});
        defer file.close(self.io);
        try file.writeStreamingAll(self.io, frame);
    }

    fn print_progress(self: *Render, frame_no: usize) !void {
        if (self.frames_total == 0) return;
        var stdout = self.stdout;
        const percentage: f64 = @as(f64, @floatFromInt(frame_no)) /
            @as(f64, @floatFromInt(self.frames_total));
        const filled: usize = @intFromFloat(@ceil(percentage *
            @as(f64, @floatFromInt(self.bar_width))));
        const empty: usize = self.bar_width - filled;

        try stdout.write("\x1b[0G");
        try stdout.write("[");
        for (0..filled) |_| try stdout.write("#");
        for (0..empty) |_| try stdout.write("-");
        try stdout.write("] ");
        stdout.print("{d:.0}%", .{percentage * 100}) catch {};
        try stdout.flush();
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
    exit: bool = false,

    gpa: std.mem.Allocator,
    io: std.Io,

    pub fn init(io: std.Io, gpa: std.mem.Allocator, height: usize, width: usize) !*Video {
        const video = try gpa.create(Video);
        video.* = .{
            .io = io,
            .gpa = gpa,
            .fps = 30,
            .frame_ns = 0,
            .height = height,
            .width = width,
            .frame = try gpa.alloc(u32, height * width),
            .frame_ascii_buffer = try std.ArrayList(u8).initCapacity(
                gpa,
                width * height * 256,
            ),
        };
        return video;
    }

    pub fn deinit(self: *Video) void {
        if (self.edges) |edges| {
            edges.deinit(self.gpa);
        }
        self.frame_ascii_buffer.deinit(self.gpa);
        self.gpa.free(self.frame);
        self.gpa.destroy(self);
    }

    fn set_edge_detection(self: *Video) !void {
        if (self.edges) |edges| {
            edges.deinit(self.gpa);
        }
        self.edges = null;
        if (!self.core.edge_detection) return;
        self.edges = try corelib.EdgeData.init(
            self.gpa,
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
            .color256 => try corelib.append_256_color(self.gpa, buffer, c, self.frame[y * self.width + x]),
            .truecolor => try corelib.append_truecolor(self.gpa, buffer, c, self.frame[y * self.width + x]),
        } else {
            try buffer.appendSlice(self.gpa, c);
            try buffer.appendSlice(self.gpa, c);
        }
    }

    fn frame_to_ascii(self: *Video) ![]const u8 {
        var timer = try corelib.time.Timer.start_add(self.io, &self.core.stats.converting_ns);
        defer timer.stop(self.io);
        self.frame_ascii_buffer.clearRetainingCapacity();
        for (0..self.height) |y| {
            for (0..self.width) |x| {
                try self.pixel_to_ascii(&self.frame_ascii_buffer, x, y);
            }
            if (y < self.height - 1) try self.frame_ascii_buffer.append(self.gpa, '\n');
        }
        return self.frame_ascii_buffer.items;
    }

    fn process_frame(video: *Video) !void {
        if (video.core.edge_detection) {
            var timer = try corelib.time.Timer.start_add(
                video.io,
                &video.core.stats.edge_detect_ns,
            );
            defer timer.stop(video.io);
            try corelib.calc_edges(
                video.gpa,
                video.core.*,
                video.edges.?,
                video.frame,
                video.width,
                video.height,
            );
        }
    }
};

const AvVideo = struct {
    fmt_ctx: *ffmpeg.FormatContext,
    codec_ctx: *ffmpeg.Codec.Context,
    sws: *ffmpeg.sws.Context,
    frame: *ffmpeg.Frame,
    frame_rgba: *ffmpeg.Frame,
    stream_idx: usize,

    fn open_video(input: []const u8, _: ?[]const u8) !AvVideo {
        const fmt_ctx: *ffmpeg.FormatContext = try AvVideo.format_open_input(input, null);
        const video_stream_idx: usize = try AvVideo.get_stream_ind(fmt_ctx);

        return .{
            .fmt_ctx = fmt_ctx,
            .codec_ctx = try AvVideo.get_decoder(fmt_ctx, video_stream_idx),
            .sws = undefined,
            .frame = undefined,
            .frame_rgba = undefined,
            .stream_idx = video_stream_idx,
        };
    }

    fn init_frame(av_video: *AvVideo, width: usize, height: usize) !void {
        const frame: *ffmpeg.Frame = try ffmpeg.Frame.alloc();
        var frame_rgba: *ffmpeg.Frame = try ffmpeg.Frame.alloc();
        frame_rgba.width = @intCast(width);
        frame_rgba.height = @intCast(height);
        frame_rgba.format = .{ .pixel = .RGBA };

        const sws = try ffmpeg.sws.Context.get(
            av_video.codec_ctx.width,
            av_video.codec_ctx.height,
            av_video.codec_ctx.pix_fmt,
            frame_rgba.width,
            frame_rgba.height,
            .RGBA,
            .{ .BILINEAR = true },
            null,
            null,
            null,
        );

        av_video.frame = frame;
        av_video.frame_rgba = frame_rgba;
        av_video.sws = sws;
    }

    fn deinit(av_video: *AvVideo) void {
        av_video.frame.free();
        av_video.frame_rgba.free();
        ffmpeg.sws.Context.free(av_video.sws);
        av_video.codec_ctx.free();
        ffmpeg.FormatContext.free(av_video.fmt_ctx);
    }

    fn format_open_input(
        input_name: []const u8,
        input_fmt: ?*const ffmpeg.InputFormat,
    ) !*ffmpeg.FormatContext {
        var fmt_ctx = ffmpeg.FormatContext.open_input(
            @ptrCast(input_name.ptr),
            input_fmt,
            null,
            null,
        ) catch |err| return switch (err) {
            error.FileNotFound => AVError.InputFileNotFound,
            else => err,
        };
        try fmt_ctx.find_stream_info(null);
        return fmt_ctx;
    }

    fn get_stream_ind(fmt_ctx: *ffmpeg.FormatContext) !usize {
        // TODO: use ffmpeg.av_find_best_stream()?
        var video_stream_index: c_int = -1;
        for (0..fmt_ctx.*.nb_streams) |i| {
            if (fmt_ctx.*.streams[i].*.codecpar.*.codec_type == .VIDEO) {
                video_stream_index = @intCast(i);
                break;
            }
        }
        if (video_stream_index == -1) return AVError.NoVideoStream;
        return @intCast(video_stream_index);
    }

    fn get_decoder(
        fmt_ctx: *ffmpeg.FormatContext,
        video_stream_index: usize,
    ) !*ffmpeg.Codec.Context {
        const codecpar = fmt_ctx.*.streams[@intCast(video_stream_index)].*.codecpar;
        const codec = try ffmpeg.Codec.find_decoder(codecpar.*.codec_id);
        const codec_ctx = try ffmpeg.Codec.Context.alloc(codec);

        try codec_ctx.parameters_to_context(codecpar);
        codec_ctx.open(codec, null) catch return AVError.CannotOpenDecoder;
        return codec_ctx;
    }

    pub fn reset_video(self: *AvVideo) !void {
        try self.fmt_ctx.seek_frame(@intCast(self.stream_idx), 0, 1);
        self.codec_ctx.flush_buffers();
    }
};

pub fn process_video(
    io: std.Io,
    gpa: std.mem.Allocator,
    core: *corelib.Core,
    path: []const u8,
    output: ?[]const u8,
    display_progress: bool,
) !void {
    var av_video = try AvVideo.open_video(path, null);
    defer av_video.deinit();

    var width: usize = @intCast(av_video.codec_ctx.width);
    var height: usize = @intCast(av_video.codec_ctx.height);
    try core.apply_scale(&width, &height);

    try av_video.init_frame(width, height);

    var video = try Video.init(io, gpa, height, width);
    defer video.deinit();
    video.core = core;
    try video.set_edge_detection();

    var render = try Render.init(io, gpa, height, width);
    defer render.deinit(gpa);
    try render.set_output(output);
    defer render.cleanup();

    const stream: *ffmpeg.Stream = av_video.fmt_ctx.*.streams[av_video.stream_idx];
    const target_fps = core.fps orelse @as(f64, @floatFromInt(stream.*.avg_frame_rate.num)) /
        @as(f64, @floatFromInt(stream.*.avg_frame_rate.den));
    video.set_target_fps(target_fps);
    render.frames_total = total_frames(stream);
    render.show_progress = display_progress;
    core.stats.fps = 0;

    var input_handler = try Input.init(io, gpa, true);
    defer input_handler.deinit();
    const input_thread = try std.Thread.spawn(
        .{ .allocator = gpa },
        Input.run,
        .{input_handler},
    );

    while (!video.exit) {
        try process_frames(
            video,
            &av_video,
            render,
            input_handler,
        );
        if (!core.loop or render.mode == .Dump) break;

        try av_video.reset_video();
    }
    try input_handler.endInputDetection();
    input_thread.detach();
}

fn process_frames(
    video: *Video,
    av_video: *AvVideo,
    render: *Render,
    input: *Input,
) !void {
    var timer_read: corelib.time.Timer = try .start_add(video.io, &video.core.stats.read_ns);
    var timer_fps: corelib.time.Timer = try .start_add(video.io, &video.core.stats.fps.?);
    var frame_no: usize = 0;

    var packet: ffmpeg.Packet = undefined;

    while (true) {
        av_video.fmt_ctx.read_frame(&packet) catch break;
        defer packet.unref();
        if (input.getKey()) |k| switch (k) {
            'q', 'Q' => {
                video.exit = true;
                break;
            },
            else => {},
        };
        if (packet.stream_index == av_video.stream_idx) {
            av_video.codec_ctx.send_packet(&packet) catch continue;
            while (true) {
                av_video.codec_ctx.receive_frame(av_video.frame) catch break;
                timer_read.stop(video.io);
                defer timer_read.reset(video.io);
                if (render.mode == .Realtime and video.core.drop_frames) {
                    const target_time = frame_no * video.frame_ns;
                    const elapsed = timer_fps.read(video.io);
                    if (elapsed > target_time + video.frame_ns) {
                        // More than 1 frame late
                        frame_no += 1;
                        video.core.stats.frames_n.? += 1;
                        video.core.stats.dropped_frames.? += 1;
                        continue;
                    }
                }

                var timer_scale = try corelib.time.Timer.start_add(
                    video.io,
                    &video.core.stats.scaling_ns,
                );

                try av_video.sws.scale_frame(av_video.frame_rgba, av_video.frame);

                try compress_frame(av_video.frame_rgba, video.frame);
                timer_scale.stop(video.io);

                try video.process_frame();

                try render.handle_frame(
                    video.gpa,
                    try video.frame_to_ascii(),
                    frame_no,
                );

                video.core.stats.frames_n.? += 1;
                frame_no += 1;
                if (render.mode == .Dump) continue;

                // Target time for the next frame
                const next_target_time = frame_no * video.frame_ns;
                const now = timer_fps.read(video.io);
                if (now < next_target_time) {
                    try std.Io.sleep(video.io, .fromNanoseconds(next_target_time - now), .awake);
                }
            }
        }
    }
    timer_fps.stop(video.io);
}

fn compress_frame(frame: *ffmpeg.Frame, dst: []u32) !void {
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

fn total_frames(stream: *ffmpeg.Stream) usize {
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
