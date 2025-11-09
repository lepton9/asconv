const std = @import("std");
const zcli = @import("zcli");
const result = @import("result");
const corelib = @import("core");
const image = @import("img");
const utils = @import("utils");
const usage = @import("usage");
const config = @import("config");
const term = @import("term");
const Input = @import("input").Input;
const time = corelib.time;
const Image = image.Image;
const ImageRaw = image.ImageRaw;

pub const build_options = @import("build_options");
const enable_video = build_options.video;

pub const commands = usage.commands;
pub const options = usage.options;
pub const positionals = usage.positionals;

pub const ErrorWrap = result.ErrorWrap;
pub const ResultImage = result.Result(ImageRaw, ErrorWrap);

pub const ExecError = error{
    FileLoadError,
    FileLoadErrorMem,
    ParseErrorHeight,
    ParseErrorWidth,
    ParseErrorScale,
    ParseErrorBrightness,
    ParseErrorSigma,
    ParseErrorFps,
    DuplicateInput,
    NoCommand,
    NoInput,
    InvalidInput,
    NoAlgorithmFound,
    NoColorModeFound,
    NoConfigFound,
    NoConfigTable,
    NoConfigCharset,
    FetchError,
    InvalidUrl,
    VideoBuildOptionNotSet,
};

fn get_input_result(
    gpa: std.mem.Allocator,
    cli: *zcli.Cli,
) result.Result([]const u8, ErrorWrap) {
    const result_type: type = result.Result([]const u8, ErrorWrap);
    var input: ?[]const u8 = null;
    if (cli.find_opt("input")) |opt_input| {
        input = opt_input.value.?.string;
    }
    if (cli.find_positional("input")) |pos| {
        if (input) |_| return result_type.wrap_err(ErrorWrap.create_ctx(
            gpa,
            ExecError.DuplicateInput,
            "{s}",
            .{pos.value},
        ));
        input = pos.value;
    }
    return if (input) |i| result_type.wrap_ok(i) else result_type.wrap_err(
        ErrorWrap.create(ExecError.NoInput),
    );
}

fn output_path(cli: *zcli.Cli) ?[]const u8 {
    const option = cli.find_opt("out");
    if (option) |opt| {
        return opt.value.?.string;
    }
    return null;
}

fn write_to_file(file_path: []const u8, data: []const u8) !void {
    var file = try std.fs.cwd().createFile(file_path, .{});
    defer file.close();
    try file.writeAll(data);
}

fn write_to_stdio(data: []const u8) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print("{s}\n", .{data});
    try stdout.flush();
}

fn validate_url(uri: std.Uri) !void {
    if (!std.mem.eql(u8, uri.scheme, "http") and
        !std.mem.eql(u8, uri.scheme, "https"))
    {
        return error.InvalidUrlScheme;
    }
}

fn is_url(input: []const u8) !bool {
    const uri = std.Uri.parse(input) catch return false;
    try validate_url(uri);
    return true;
}

fn fetch_url_content(allocator: std.mem.Allocator, url: []const u8) ![]const u8 {
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();
    var writer = std.Io.Writer.Allocating.init(allocator);
    defer writer.deinit();

    const res = try client.fetch(.{
        .method = .GET,
        .location = .{ .url = url },
        .response_writer = &writer.writer,
    });

    if (res.status != std.http.Status.ok) return ExecError.FetchError;
    return try writer.toOwnedSlice();
}

fn get_input_image(allocator: std.mem.Allocator, filepath: []const u8) ResultImage {
    const input_url = is_url(filepath) catch {
        return ResultImage.wrap_err(
            ErrorWrap.create_ctx(allocator, ExecError.InvalidUrl, "{s}", .{filepath}),
        );
    };

    if (input_url) {
        const content = fetch_url_content(allocator, filepath) catch |err| {
            return ResultImage.wrap_err(
                ErrorWrap.create_ctx(allocator, err, "{s}", .{filepath}),
            );
        };
        defer allocator.free(content);
        const raw_image = image.load_image_from_memory(content) catch {
            return ResultImage.wrap_err(
                ErrorWrap.create(ExecError.FileLoadErrorMem),
            );
        };
        return ResultImage.wrap_ok(raw_image);
    } else {
        const raw_image = image.load_image(filepath, null) catch {
            return ResultImage.wrap_err(
                ErrorWrap.create_ctx(allocator, ExecError.FileLoadError, "{s}", .{filepath}),
            );
        };
        return ResultImage.wrap_ok(raw_image);
    }
}

fn size(allocator: std.mem.Allocator, cli: *zcli.Cli) !?ErrorWrap {
    const res = get_input_result(allocator, cli);
    const filename = res.unwrap_try() catch return res.unwrap_err();
    const img = try Image.init(allocator, 0, 0);
    img.core = try corelib.Core.init(allocator);
    defer Image.deinit(img);

    const img_result = get_input_image(allocator, filename);
    img.set_raw_image(img_result.unwrap_try() catch {
        return img_result.unwrap_err();
    }, filename);

    var buffer: [256]u8 = undefined;
    var buf = try std.ArrayList(u8).initCapacity(allocator, 1024);
    defer buf.deinit(allocator);
    try buf.appendSlice(allocator, try std.fmt.bufPrint(&buffer, "Image: {s}\n", .{filename}));
    try buf.appendSlice(allocator, try std.fmt.bufPrint(
        &buffer,
        "Size: {d}x{d}\n",
        .{ img.raw_image.width, img.raw_image.height },
    ));
    try buf.appendSlice(
        allocator,
        try std.fmt.bufPrint(&buffer, "Channels: {d}\n", .{img.raw_image.nchan}),
    );
    try write_to_stdio(buf.items);
    return null;
}

fn playback(allocator: std.mem.Allocator, cli: *zcli.Cli) !?ErrorWrap {
    const res = get_input_result(allocator, cli);
    const input_dir = res.unwrap_try() catch return res.unwrap_err();
    const cwd = std.fs.cwd();

    const dir = cwd.openDir(input_dir, .{ .iterate = true }) catch {
        return ErrorWrap.create_ctx(allocator, ExecError.InvalidInput, "{s}", .{input_dir});
    };

    var core = try corelib.Core.init(allocator);
    defer core.deinit(allocator);
    if (try ascii_opts(allocator, cli, core)) |err| {
        return err;
    }

    var frame_n: usize = 0;
    const render = try term.TermRenderer.init(allocator, 4096);
    defer render.deinit(allocator);

    var input_handler = try Input.init(allocator, true);
    defer input_handler.deinit();
    const input_thread = try std.Thread.spawn(
        .{ .allocator = allocator },
        Input.run,
        .{input_handler},
    );

    const fps: f32 = core.fps orelse 30.0;
    var exit: bool = false;

    var it = dir.iterate();
    var buffer: []u8 = undefined;
    defer allocator.free(buffer);

    while (it.next() catch null) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.startsWith(u8, entry.name, "frame_")) continue;
        buffer = try dir.readFileAlloc(
            allocator,
            entry.name,
            std.Io.Limit.unlimited.toInt().?,
        );
        it.reset();
        break;
    }

    render.clear_screen();
    render.cursor_hide();
    defer render.cursor_show();

    while (!exit) {
        while (it.next() catch null) |entry| {
            if (input_handler.getKey()) |k| switch (k) {
                'q', 'Q' => {
                    exit = true;
                    break;
                },
                else => {},
            };

            if (entry.kind != .file) continue;
            if (!std.mem.startsWith(u8, entry.name, "frame_")) continue;

            const file_content = try dir.readFile(entry.name, buffer);
            try render.write("\x1b[H");
            try render.writef(file_content);

            const ns: u64 = @intFromFloat(
                @divTrunc(@as(f64, @floatFromInt(1_000_000_000)), @as(f64, fps)),
            );
            std.Thread.sleep(ns);
            frame_n += 1;
        }
        if (!core.loop) break;
        it.reset();
    }

    input_handler.endInputDetection();
    input_thread.detach();
    return null;
}

fn ascii_video(
    allocator: std.mem.Allocator,
    cli: *zcli.Cli,
    core: *corelib.Core,
    filename: []const u8,
) !?ErrorWrap {
    if (!enable_video) return ErrorWrap.create(ExecError.VideoBuildOptionNotSet);
    const video = @import("video");

    if (try ascii_opts(allocator, cli, core)) |err| {
        return err;
    }
    const progress = (cli.find_opt("progress") != null);
    const output = output_path(cli);
    video.process_video(
        allocator,
        core,
        filename,
        output,
        progress,
    ) catch |err| switch (err) {
        video.AVError.FailedOpenInput => return ErrorWrap.create_ctx(
            allocator,
            err,
            "{s}",
            .{filename},
        ),
        else => return err,
    };
    return null;
}

fn ascii_image(
    allocator: std.mem.Allocator,
    cli: *zcli.Cli,
    core: *corelib.Core,
    filename: []const u8,
) !?ErrorWrap {
    var timer_read = try time.Timer.start(&core.stats.read);
    const img_result = get_input_image(allocator, filename);
    timer_read.stop();
    var raw_image = img_result.unwrap_try() catch {
        return img_result.unwrap_err();
    };

    if (try ascii_opts(allocator, cli, core)) |err| {
        raw_image.deinit();
        return err;
    }

    var height: usize = @intCast(raw_image.height);
    var width: usize = @intCast(raw_image.width);
    try core.apply_scale(&width, &height);

    var img = try Image.init(allocator, @intCast(height), @intCast(width));
    defer Image.deinit(img);
    img.core = core;
    if (core.edge_detection) try img.set_edge_detection();
    img.set_raw_image(raw_image, filename);
    try img.fit_image();

    const data = try img.to_ascii();
    defer allocator.free(data);
    const file = output_path(cli);
    var timer_print = try time.Timer.start(&core.stats.write);
    if (file) |path| {
        try write_to_file(path, data);
    } else {
        try write_to_stdio(data);
    }
    timer_print.stop();
    return null;
}

fn ascii(allocator: std.mem.Allocator, cli: *zcli.Cli, file_type: corelib.MediaType) !?ErrorWrap {
    var core = try corelib.Core.init(allocator);
    defer core.deinit(allocator);
    var timer_total = try time.Timer.start(&core.stats.total);
    const res = get_input_result(allocator, cli);
    const filename = res.unwrap_try() catch return res.unwrap_err();

    try core.set_ascii_info(allocator, usage.characters);
    switch (file_type) {
        .Video => {
            if (try ascii_video(allocator, cli, core, filename)) |err| return err;
        },
        else => {
            if (try ascii_image(allocator, cli, core, filename)) |err| return err;
        },
    }
    timer_total.stop();
    if (cli.find_opt("time")) |_| {
        try show_performance(allocator, &core.stats, file_type);
    }
    return null;
}

fn ascii_opts(
    allocator: std.mem.Allocator,
    cli: *zcli.Cli,
    core: *corelib.Core,
) !?ErrorWrap {
    const config_path: ?[]const u8 = blk: {
        if (cli.find_opt("config")) |opt| {
            break :blk opt.value.?.string;
        }
        break :blk null;
    };
    const conf: ?config.Config = blk: {
        if (config_path) |path| {
            if (try config.get_config_from_path(allocator, path)) |c| {
                break :blk c;
            }
            return ErrorWrap.create_ctx(allocator, ExecError.NoConfigFound, "{s}", .{path});
        } else break :blk try config.get_config(allocator);
    };
    defer if (conf) |c| c.deinit(allocator);
    if (cli.args.count() == 0) return null;

    var opt_it = cli.args.iterator();
    while (opt_it.next()) |entry| {
        const opt = entry.value_ptr.*;
        if (std.mem.eql(u8, opt.name, "height")) {
            core.height = std.fmt.parseInt(u32, opt.value.?.string, 10) catch {
                return ErrorWrap.create_ctx(allocator, ExecError.ParseErrorHeight, "{s}", .{opt.value.?.string});
            };
        } else if (std.mem.eql(u8, opt.name, "width")) {
            core.width = std.fmt.parseInt(u32, opt.value.?.string, 10) catch {
                return ErrorWrap.create_ctx(allocator, ExecError.ParseErrorWidth, "{s}", .{opt.value.?.string});
            };
        } else if (std.mem.eql(u8, opt.name, "scale")) {
            core.scale = std.fmt.parseFloat(f32, opt.value.?.string) catch {
                return ErrorWrap.create_ctx(allocator, ExecError.ParseErrorScale, "{s}", .{opt.value.?.string});
            };
        } else if (std.mem.eql(u8, opt.name, "fit")) {
            core.fit_screen = true;
        } else if (std.mem.eql(u8, opt.name, "brightness")) {
            core.brightness = std.fmt.parseFloat(f32, opt.value.?.string) catch {
                return ErrorWrap.create_ctx(allocator, ExecError.ParseErrorBrightness, "{s}", .{opt.value.?.string});
            };
        } else if (std.mem.eql(u8, opt.name, "fps")) {
            core.fps = std.fmt.parseFloat(f32, opt.value.?.string) catch {
                return ErrorWrap.create_ctx(allocator, ExecError.ParseErrorFps, "{s}", .{opt.value.?.string});
            };
        } else if (std.mem.eql(u8, opt.name, "loop")) {
            core.loop = true;
        } else if (std.mem.eql(u8, opt.name, "reverse")) {
            try core.ascii_info.reverse(allocator);
        } else if (std.mem.eql(u8, opt.name, "charset")) {
            try core.set_ascii_info(allocator, opt.value.?.string);
        } else if (std.mem.eql(u8, opt.name, "color")) {
            core.toggle_color();
            if (opt.value) |val| {
                const value = val.string;
                core.set_color_mode(value) catch {
                    return ErrorWrap.create_ctx(allocator, ExecError.NoColorModeFound, "{s}", .{value});
                };
            }
        } else if (std.mem.eql(u8, opt.name, "edges")) {
            core.edge_detection = true;
            if (opt.value) |val| {
                const value = val.string;
                core.set_edge_alg(value) catch {
                    return ErrorWrap.create_ctx(allocator, ExecError.NoAlgorithmFound, "{s}", .{value});
                };
            }
        } else if (std.mem.eql(u8, opt.name, "sigma")) {
            core.set_sigma(
                std.fmt.parseFloat(f32, opt.value.?.string) catch {
                    return ErrorWrap.create_ctx(allocator, ExecError.ParseErrorSigma, "{s}", .{opt.value.?.string});
                },
            );
        } else if (std.mem.eql(u8, opt.name, "ccharset")) {
            if (conf) |c| {
                const charsets = c.table.get_table().get("charsets");
                if (charsets == null or charsets.? != .table)
                    return ErrorWrap.create_ctx(allocator, ExecError.NoConfigTable, "charsets", .{});
                const cs = charsets.?.get(opt.value.?.string);
                if (cs == null or cs.? != .string)
                    return ErrorWrap.create_ctx(
                        allocator,
                        ExecError.NoConfigCharset,
                        "{s}",
                        .{opt.value.?.string},
                    );
                try core.set_ascii_info(allocator, cs.?.string);
            } else {
                return ErrorWrap.create_ctx(
                    allocator,
                    ExecError.NoConfigFound,
                    "{s}",
                    .{config_path orelse "default_path"},
                );
            }
        } else if (std.mem.eql(u8, opt.name, "dropframes")) {
            core.drop_frames = true;
        }
    }
    return null;
}

fn show_stats_image(
    allocator: std.mem.Allocator,
    buffer: *std.ArrayList(u8),
    stats: *time.Stats,
) !void {
    var line_buf: [256]u8 = undefined;
    try buffer.appendSlice(allocator, try std.fmt.bufPrint(&line_buf, "Scaling: {d:.3} s\n", .{time.to_s(stats.scaling)}));
    try buffer.appendSlice(
        allocator,
        try std.fmt.bufPrint(&line_buf, "Edge detecting: {d:.3} s\n", .{time.to_s(stats.edge_detect)}),
    );
    try buffer.appendSlice(
        allocator,
        try std.fmt.bufPrint(&line_buf, "Converting: {d:.3} s\n", .{time.to_s(stats.converting)}),
    );
    try buffer.appendSlice(
        allocator,
        try std.fmt.bufPrint(&line_buf, "Read: {d:.3} s\n", .{time.to_s(stats.read)}),
    );
    try buffer.appendSlice(
        allocator,
        try std.fmt.bufPrint(&line_buf, "Write: {d:.3} s\n", .{time.to_s(stats.write)}),
    );
}

fn show_stats_video(
    allocator: std.mem.Allocator,
    buffer: *std.ArrayList(u8),
    stats: *time.Stats,
) !void {
    var line_buf: [256]u8 = undefined;
    const frames_float = @as(f64, @floatFromInt(stats.frames_n orelse 0));
    try buffer.appendSlice(allocator, try std.fmt.bufPrint(
        &line_buf,
        "Scaling: {d:.3} s/f\n",
        .{time.to_s(stats.scaling) / frames_float},
    ));
    try buffer.appendSlice(allocator, try std.fmt.bufPrint(
        &line_buf,
        "Edge detecting: {d:.3} s/f\n",
        .{time.to_s(stats.edge_detect) / frames_float},
    ));
    try buffer.appendSlice(allocator, try std.fmt.bufPrint(
        &line_buf,
        "Converting: {d:.3} s/f\n",
        .{time.to_s(stats.converting) / frames_float},
    ));
    try buffer.appendSlice(allocator, try std.fmt.bufPrint(
        &line_buf,
        "Read: {d:.3} s/f\n",
        .{time.to_s(stats.read) / frames_float},
    ));
    try buffer.appendSlice(allocator, try std.fmt.bufPrint(
        &line_buf,
        "Write: {d:.3} s/f\n",
        .{time.to_s(stats.write) / frames_float},
    ));
    try buffer.appendSlice(allocator, try std.fmt.bufPrint(&line_buf, "Fps: {d:.1}\n", .{
        frames_float / time.to_s(stats.fps.?),
    }));
    try buffer.appendSlice(allocator, try std.fmt.bufPrint(&line_buf, "Frames: {d}\n", .{
        stats.frames_n.?,
    }));
    try buffer.appendSlice(allocator, try std.fmt.bufPrint(&line_buf, "Dropped frames: {d}\n", .{
        stats.dropped_frames.?,
    }));
}

fn show_performance(
    allocator: std.mem.Allocator,
    stats: *time.Stats,
    file_type: corelib.MediaType,
) !void {
    var line_buf: [256]u8 = undefined;
    var buffer = try std.ArrayList(u8).initCapacity(allocator, 1024);
    defer buffer.deinit(allocator);
    try buffer.append(allocator, '\n');
    switch (file_type) {
        .Video => try show_stats_video(allocator, &buffer, stats),
        else => try show_stats_image(allocator, &buffer, stats),
    }
    try buffer.appendSlice(allocator, try std.fmt.bufPrint(
        &line_buf,
        "Total time taken: {d:.3} s\n",
        .{time.to_s(stats.total)},
    ));
    try write_to_stdio(buffer.items);
}

pub fn cmd_func(
    allocator: std.mem.Allocator,
    cli: *zcli.Cli,
) !?ErrorWrap {
    if (cli.cmd == null) {
        return ErrorWrap.create(ExecError.NoCommand);
    }
    const cmd_name = cli.cmd.?.name;
    if (std.mem.eql(u8, cmd_name, "size")) {
        return try size(allocator, cli);
    } else if (std.mem.eql(u8, cmd_name, "ascii")) {
        return try ascii(allocator, cli, .Image);
    } else if (std.mem.eql(u8, cmd_name, "asciivid")) {
        return try ascii(allocator, cli, .Video);
    } else if (std.mem.eql(u8, cmd_name, "playback")) {
        return try playback(allocator, cli);
    } else if (std.mem.eql(u8, cmd_name, "compress")) {
        return null;
    }
    return null;
}
