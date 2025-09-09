const std = @import("std");
const cli = @import("cli");
const cmd = cli.cmd;
const result = @import("result");
const corelib = @import("core");
const image = @import("img");
const utils = @import("utils");
const usage = @import("usage");
const config = @import("config");
const time = corelib.time;
const Image = image.Image;
const ImageRaw = image.ImageRaw;

pub const build_options = @import("build_options");
const enable_video = build_options.video;

pub const commands = usage.commands;
pub const options = usage.options;

pub const ResultImage = result.Result(ImageRaw, result.ErrorWrap);

pub const ExecError = error{
    NoFileName,
    FileLoadError,
    FileLoadErrorMem,
    ParseErrorHeight,
    ParseErrorWidth,
    ParseErrorScale,
    ParseErrorBrightness,
    ParseErrorSigma,
    DuplicateInput,
    NoInputFile,
    NoAlgorithmFound,
    NoColorModeFound,
    NoConfigFound,
    NoConfigTable,
    NoConfigCharset,
    FetchError,
    InvalidUrl,
    VideoBuildOptionNotSet,
};

fn input_file(cli_: *cli.Cli) ![]const u8 {
    var input: ?[]const u8 = null;
    if (cli_.find_opt("input")) |opt_input| {
        input = opt_input.arg.?.value;
    }
    if (cli_.global_args) |ga| {
        if (input) |_| return ExecError.DuplicateInput;
        input = ga;
    }
    return input orelse ExecError.NoInputFile;
}

fn output_path(cli_: *cli.Cli) ?[]const u8 {
    const option = cli_.find_opt("out");
    if (option) |opt| {
        return opt.arg.?.value.?;
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
            result.ErrorWrap.create(ExecError.InvalidUrl, "{s}", .{filepath}),
        );
    };

    if (input_url) {
        const content = fetch_url_content(allocator, filepath) catch |err| {
            return ResultImage.wrap_err(
                result.ErrorWrap.create(err, "{s}", .{filepath}),
            );
        };
        defer allocator.free(content);
        const raw_image = image.load_image_from_memory(content) catch {
            return ResultImage.wrap_err(
                result.ErrorWrap.create(ExecError.FileLoadErrorMem, "", .{}),
            );
        };
        return ResultImage.wrap_ok(raw_image);
    } else {
        const raw_image = image.load_image(filepath, null) catch {
            return ResultImage.wrap_err(
                result.ErrorWrap.create(ExecError.FileLoadError, "{s}", .{filepath}),
            );
        };
        return ResultImage.wrap_ok(raw_image);
    }
}

fn size(allocator: std.mem.Allocator, cli_: *cli.Cli) !?result.ErrorWrap {
    const filename = input_file(cli_) catch |err| {
        return result.ErrorWrap.create(err, "{s}", .{cli_.global_args orelse ""});
    };
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

fn ascii_video(
    allocator: std.mem.Allocator,
    cli_: *cli.Cli,
    core: *corelib.Core,
    filename: []const u8,
) !?result.ErrorWrap {
    if (!enable_video) return result.ErrorWrap.create(
        ExecError.VideoBuildOptionNotSet,
        "{s}",
        .{"video"},
    );

    if (try ascii_opts(allocator, cli_, core)) |err| {
        return err;
    }
    const progress = (cli_.find_opt("progress") != null);
    const output = output_path(cli_);
    try @import("video").process_video(allocator, core, filename, output, progress);
    return null;
}

fn ascii_image(
    allocator: std.mem.Allocator,
    cli_: *cli.Cli,
    core: *corelib.Core,
    filename: []const u8,
) !?result.ErrorWrap {
    var timer_read = try time.Timer.start(&core.stats.read);
    const img_result = get_input_image(allocator, filename);
    timer_read.stop();
    var raw_image = img_result.unwrap_try() catch {
        return img_result.unwrap_err();
    };

    if (try ascii_opts(allocator, cli_, core)) |err| {
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
    const file = output_path(cli_);
    var timer_print = try time.Timer.start(&core.stats.write);
    if (file) |path| {
        try write_to_file(path, data);
    } else {
        try write_to_stdio(data);
    }
    timer_print.stop();
    return null;
}

fn ascii(allocator: std.mem.Allocator, cli_: *cli.Cli, file_type: corelib.MediaType) !?result.ErrorWrap {
    var core = try corelib.Core.init(allocator);
    defer core.deinit(allocator);
    var timer_total = try time.Timer.start(&core.stats.total);
    const filename = input_file(cli_) catch |err| {
        return result.ErrorWrap.create(err, "{s}", .{cli_.global_args orelse ""});
    };
    try core.set_ascii_info(allocator, usage.characters);
    switch (file_type) {
        .Video => {
            if (try ascii_video(allocator, cli_, core, filename)) |err| return err;
        },
        else => {
            if (try ascii_image(allocator, cli_, core, filename)) |err| return err;
        },
    }
    timer_total.stop();
    if (cli_.find_opt("time")) |_| {
        try show_performance(allocator, &core.stats, file_type);
    }
    return null;
}

fn ascii_opts(
    allocator: std.mem.Allocator,
    cli_: *cli.Cli,
    core: *corelib.Core,
) !?result.ErrorWrap {
    const config_path: ?[]const u8 = blk: {
        if (cli_.find_opt("config")) |opt| {
            break :blk opt.arg.?.value.?;
        }
        break :blk null;
    };
    const conf: ?config.Config = blk: {
        if (config_path) |path| {
            if (try config.get_config_from_path(allocator, path)) |c| {
                break :blk c;
            }
            return result.ErrorWrap.create(ExecError.NoConfigFound, "{s}", .{path});
        } else break :blk try config.get_config(allocator);
    };
    defer if (conf) |c| c.deinit(allocator);
    if (cli_.args == null) return null;

    for (cli_.args.?.items) |*opt| {
        if (std.mem.eql(u8, opt.long_name, "height")) {
            core.height = std.fmt.parseInt(u32, opt.arg.?.value.?, 10) catch {
                return result.ErrorWrap.create(ExecError.ParseErrorHeight, "{s}", .{opt.arg.?.value.?});
            };
        } else if (std.mem.eql(u8, opt.long_name, "width")) {
            core.width = std.fmt.parseInt(u32, opt.arg.?.value.?, 10) catch {
                return result.ErrorWrap.create(ExecError.ParseErrorWidth, "{s}", .{opt.arg.?.value.?});
            };
        } else if (std.mem.eql(u8, opt.long_name, "scale")) {
            core.scale = std.fmt.parseFloat(f32, opt.arg.?.value.?) catch {
                return result.ErrorWrap.create(ExecError.ParseErrorScale, "{s}", .{opt.arg.?.value.?});
            };
        } else if (std.mem.eql(u8, opt.long_name, "fit")) {
            core.fit_screen = true;
        } else if (std.mem.eql(u8, opt.long_name, "brightness")) {
            core.brightness = std.fmt.parseFloat(f32, opt.arg.?.value.?) catch {
                return result.ErrorWrap.create(ExecError.ParseErrorBrightness, "{s}", .{opt.arg.?.value.?});
            };
        } else if (std.mem.eql(u8, opt.long_name, "reverse")) {
            try core.ascii_info.reverse(allocator);
        } else if (std.mem.eql(u8, opt.long_name, "charset")) {
            try core.set_ascii_info(allocator, opt.arg.?.value.?);
        } else if (std.mem.eql(u8, opt.long_name, "color")) {
            core.toggle_color();
            if (opt.arg.?.value) |val| {
                core.set_color_mode(val) catch {
                    return result.ErrorWrap.create(ExecError.NoColorModeFound, "{s}", .{val});
                };
            }
        } else if (std.mem.eql(u8, opt.long_name, "edges")) {
            core.edge_detection = true;
            if (opt.arg.?.value) |val| {
                core.set_edge_alg(val) catch {
                    return result.ErrorWrap.create(ExecError.NoAlgorithmFound, "{s}", .{val});
                };
            }
        } else if (std.mem.eql(u8, opt.long_name, "sigma")) {
            core.set_sigma(
                std.fmt.parseFloat(f32, opt.arg.?.value.?) catch {
                    return result.ErrorWrap.create(ExecError.ParseErrorSigma, "{s}", .{opt.arg.?.value.?});
                },
            );
        } else if (std.mem.eql(u8, opt.long_name, "ccharset")) {
            if (conf) |c| {
                const charsets = c.table.get_table().get("charsets");
                if (charsets == null or charsets.? != .table)
                    return result.ErrorWrap.create(ExecError.NoConfigTable, "charsets", .{});
                const cs = charsets.?.get(opt.arg.?.value.?);
                if (cs == null or cs.? != .string)
                    return result.ErrorWrap.create(
                        ExecError.NoConfigCharset,
                        "{s}",
                        .{opt.arg.?.value.?},
                    );
                try core.set_ascii_info(allocator, cs.?.string);
            } else {
                return result.ErrorWrap.create(
                    ExecError.NoConfigFound,
                    "{s}",
                    .{config_path orelse "default_path"},
                );
            }
        } else if (std.mem.eql(u8, opt.long_name, "dropframes")) {
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

fn help(allocator: std.mem.Allocator, args_struct: *const cmd.ArgsStructure) !void {
    var buf = try std.ArrayList(u8).initCapacity(allocator, 1024);
    defer buf.deinit(allocator);
    try buf.appendSlice(allocator, "Usage: asconv [command] [options]\n\n");
    const args = try args_struct.args_structure_string(allocator);
    defer allocator.free(args);
    try buf.appendSlice(allocator, args);
    try write_to_stdio(buf.items);
}

pub fn cmd_func(allocator: std.mem.Allocator, cli_: *cli.Cli, args_struct: *const cmd.ArgsStructure) !?result.ErrorWrap {
    if (cli_.cmd == null) {
        std.log.info("No command", .{});
        return null;
    }
    const cmd_name = cli_.cmd.?.name.?;
    if (std.mem.eql(u8, cmd_name, "size")) {
        return try size(allocator, cli_);
    } else if (std.mem.eql(u8, cmd_name, "ascii")) {
        return try ascii(allocator, cli_, .Image);
    } else if (std.mem.eql(u8, cmd_name, "asciivid")) {
        return try ascii(allocator, cli_, .Video);
    } else if (std.mem.eql(u8, cmd_name, "compress")) {
        return null;
    } else if (std.mem.eql(u8, cmd_name, "help")) {
        try help(allocator, args_struct);
    }
    return null;
}
