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
    UnsupportedShell,
    VideoBuildOptionNotSet,
};

fn get_input_result(
    gpa: std.mem.Allocator,
    cli: *zcli.Cli,
) result.Result([]const u8, ErrorWrap) {
    const result_type: type = result.Result([]const u8, ErrorWrap);
    var input: ?[]const u8 = null;
    if (cli.findOption("input")) |opt_input| {
        input = opt_input.value.?.string;
    }
    if (cli.findPositional("input")) |pos| {
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
    const option = cli.findOption("out");
    if (option) |opt| {
        return opt.value.?.string;
    }
    return null;
}

fn writeToFile(io: std.Io, file_path: []const u8, data: []const u8) !void {
    var file = try std.Io.Dir.cwd().createFile(io, file_path, .{});
    defer file.close(io);
    try file.writeStreamingAll(io, data);
}

/// Write to stdout with format.
fn fmtWrite(io: std.Io, comptime fmt: []const u8, args: anytype) !void {
    var buffer: [1024]u8 = undefined;
    var writer: std.Io.File.Writer = .init(.stdout(), io, &buffer);
    const stdout = &writer.interface;
    try stdout.print(fmt, args);
    try stdout.flush();
}

/// Write all the data to stdout.
/// Add newline at the end.
fn writeEndNl(io: std.Io, bytes: []const u8) !void {
    return fmtWrite(io, "{s}\n", .{bytes});
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

fn fetch_url_content(io: std.Io, gpa: std.mem.Allocator, url: []const u8) ![]const u8 {
    var client = std.http.Client{ .io = io, .allocator = gpa };
    defer client.deinit();
    var writer = std.Io.Writer.Allocating.init(gpa);
    defer writer.deinit();

    const res = try client.fetch(.{
        .method = .GET,
        .location = .{ .url = url },
        .response_writer = &writer.writer,
    });

    if (res.status != std.http.Status.ok) return ExecError.FetchError;
    return try writer.toOwnedSlice();
}

fn get_input_image(
    io: std.Io,
    gpa: std.mem.Allocator,
    file_path: []const u8,
) ResultImage {
    const input_url = is_url(file_path) catch {
        return ResultImage.wrap_err(
            ErrorWrap.create_ctx(gpa, ExecError.InvalidUrl, "{s}", .{file_path}),
        );
    };

    if (input_url) {
        const content = fetch_url_content(io, gpa, file_path) catch |err| {
            return ResultImage.wrap_err(
                ErrorWrap.create_ctx(gpa, err, "{s}", .{file_path}),
            );
        };
        defer gpa.free(content);
        const raw_image = image.load_image_from_memory(content) catch {
            return ResultImage.wrap_err(
                ErrorWrap.create(ExecError.FileLoadErrorMem),
            );
        };
        return ResultImage.wrap_ok(raw_image);
    } else {
        const raw_image = image.load_image(file_path, null) catch {
            return ResultImage.wrap_err(
                ErrorWrap.create_ctx(gpa, ExecError.FileLoadError, "{s}", .{file_path}),
            );
        };
        return ResultImage.wrap_ok(raw_image);
    }
}

fn size(io: std.Io, gpa: std.mem.Allocator, cli: *zcli.Cli) !?ErrorWrap {
    const res = get_input_result(gpa, cli);
    const filename = res.unwrap_try() catch return res.unwrap_err();
    const img = try Image.init(io, gpa, 0, 0);
    img.core = try corelib.Core.init(gpa);
    defer Image.deinit(img);

    const img_result = get_input_image(io, gpa, filename);
    img.set_raw_image(img_result.unwrap_try() catch {
        return img_result.unwrap_err();
    }, filename);

    var buffer: [256]u8 = undefined;
    var buf = try std.ArrayList(u8).initCapacity(gpa, 1024);
    defer buf.deinit(gpa);
    try buf.appendSlice(gpa, try std.fmt.bufPrint(&buffer, "Image: {s}\n", .{filename}));
    try buf.appendSlice(gpa, try std.fmt.bufPrint(
        &buffer,
        "Size: {d}x{d}\n",
        .{ img.raw_image.width, img.raw_image.height },
    ));
    try buf.appendSlice(
        gpa,
        try std.fmt.bufPrint(&buffer, "Channels: {d}\n", .{img.raw_image.nchan}),
    );
    try writeEndNl(io, buf.items);
    return null;
}

fn playback(
    io: std.Io,
    gpa: std.mem.Allocator,
    env: *std.process.Environ.Map,
    cli: *zcli.Cli,
) !?ErrorWrap {
    const res = get_input_result(gpa, cli);
    const input_dir = res.unwrap_try() catch return res.unwrap_err();
    const cwd = std.Io.Dir.cwd();

    const dir = cwd.openDir(io, input_dir, .{ .iterate = true }) catch {
        return ErrorWrap.create_ctx(gpa, ExecError.InvalidInput, "{s}", .{input_dir});
    };

    var core = try corelib.Core.init(gpa);
    defer core.deinit(gpa);
    if (try ascii_opts(io, gpa, env, cli, core)) |err| {
        return err;
    }

    var frame_n: usize = 0;
    const render = try term.TermRenderer.init(io, gpa, 4096);
    defer render.deinit(gpa);

    var input_handler = try Input.init(io, gpa, true);
    defer input_handler.deinit();
    const input_thread = try std.Thread.spawn(
        .{ .allocator = gpa },
        Input.run,
        .{input_handler},
    );

    const fps: f32 = core.fps orelse 30.0;
    var exit: bool = false;

    var it = dir.iterate();
    var buffer: []u8 = undefined;
    defer gpa.free(buffer);

    while (it.next(io) catch null) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.startsWith(u8, entry.name, "frame_")) continue;
        buffer = try dir.readFileAlloc(
            io,
            entry.name,
            gpa,
            .unlimited,
        );
        it.reader.reset();
        break;
    }

    render.clear_screen();
    render.cursor_hide();
    defer render.cursor_show();

    while (!exit) {
        while (it.next(io) catch null) |entry| {
            if (input_handler.getKey()) |k| switch (k) {
                'q', 'Q' => {
                    exit = true;
                    break;
                },
                else => {},
            };

            if (entry.kind != .file) continue;
            if (!std.mem.startsWith(u8, entry.name, "frame_")) continue;

            const file_content = try dir.readFile(io, entry.name, buffer);
            try render.write("\x1b[H");
            try render.writef(file_content);

            const ns: u64 = @intFromFloat(
                @divTrunc(@as(f64, @floatFromInt(1_000_000_000)), @as(f64, fps)),
            );
            try std.Io.sleep(io, .fromNanoseconds(ns), .real);
            frame_n += 1;
        }
        if (!core.loop) break;
        it.reader.reset();
    }

    try input_handler.endInputDetection();
    input_thread.detach();
    return null;
}

fn ascii_video(
    io: std.Io,
    gpa: std.mem.Allocator,
    env: *std.process.Environ.Map,
    cli: *zcli.Cli,
    core: *corelib.Core,
    filename: []const u8,
) !?ErrorWrap {
    if (!enable_video) return ErrorWrap.create(ExecError.VideoBuildOptionNotSet);
    const video = @import("video");

    if (try ascii_opts(io, gpa, env, cli, core)) |err| {
        return err;
    }
    const progress = (cli.findOption("progress") != null);
    const output = output_path(cli);
    video.process_video(
        io,
        gpa,
        core,
        filename,
        output,
        progress,
    ) catch |err| switch (err) {
        video.AVError.InputFileNotFound => return ErrorWrap.create_ctx(
            gpa,
            err,
            "{s}",
            .{filename},
        ),
        else => return err,
    };
    return null;
}

fn ascii_image(
    io: std.Io,
    gpa: std.mem.Allocator,
    env: *std.process.Environ.Map,
    cli: *zcli.Cli,
    core: *corelib.Core,
    filename: []const u8,
) !?ErrorWrap {
    var timer_read = try time.Timer.start(io, &core.stats.read_ns);
    const img_result = get_input_image(io, gpa, filename);
    timer_read.stop(io);
    var raw_image = img_result.unwrap_try() catch {
        return img_result.unwrap_err();
    };

    if (try ascii_opts(io, gpa, env, cli, core)) |err| {
        raw_image.deinit();
        return err;
    }

    var height: usize = @intCast(raw_image.height);
    var width: usize = @intCast(raw_image.width);
    try core.apply_scale(&width, &height);

    var img = try Image.init(io, gpa, @intCast(height), @intCast(width));
    defer Image.deinit(img);
    img.core = core;
    if (core.edge_detection) try img.set_edge_detection();
    img.set_raw_image(raw_image, filename);
    try img.fit_image();

    const data = try img.to_ascii();
    defer gpa.free(data);
    const file = output_path(cli);
    var timer_print = try time.Timer.start(io, &core.stats.write_ns);
    if (file) |path| {
        try writeToFile(io, path, data);
    } else {
        try writeEndNl(io, data);
    }
    timer_print.stop(io);
    return null;
}

fn ascii(
    io: std.Io,
    gpa: std.mem.Allocator,
    env: *std.process.Environ.Map,
    cli: *zcli.Cli,
    file_type: corelib.MediaType,
) !?ErrorWrap {
    var core = try corelib.Core.init(gpa);
    defer core.deinit(gpa);
    var timer_total = try time.Timer.start(io, &core.stats.total_ns);
    const res = get_input_result(gpa, cli);
    const filename = res.unwrap_try() catch return res.unwrap_err();

    try core.set_ascii_info(gpa, usage.characters);
    switch (file_type) {
        .Video => {
            if (try ascii_video(io, gpa, env, cli, core, filename)) |err| return err;
        },
        else => {
            if (try ascii_image(io, gpa, env, cli, core, filename)) |err| return err;
        },
    }
    timer_total.stop(io);
    if (cli.findOption("time")) |_| {
        try show_performance(io, gpa, &core.stats, file_type);
    }
    return null;
}

fn ascii_opts(
    io: std.Io,
    gpa: std.mem.Allocator,
    env: *std.process.Environ.Map,
    cli: *zcli.Cli,
    core: *corelib.Core,
) !?ErrorWrap {
    const config_path: ?[]const u8 = blk: {
        if (cli.findOption("config")) |opt| {
            break :blk opt.value.?.string;
        }
        break :blk null;
    };
    const conf: ?config.Config = blk: {
        if (config_path) |path| {
            if (try config.get_config_from_path(io, gpa, path)) |c| {
                break :blk c;
            }
            return ErrorWrap.create_ctx(gpa, ExecError.NoConfigFound, "{s}", .{path});
        } else break :blk try config.get_config(io, gpa, env);
    };
    defer if (conf) |c| c.deinit(gpa);
    if (cli.args.count() == 0) return null;

    var opt_it = cli.args.iterator();
    while (opt_it.next()) |entry| {
        const opt = entry.value_ptr.*;
        if (std.mem.eql(u8, opt.name, "height")) {
            core.height = @intCast(@max(opt.value.?.int, 0));
        } else if (std.mem.eql(u8, opt.name, "width")) {
            core.width = @intCast(@max(opt.value.?.int, 0));
        } else if (std.mem.eql(u8, opt.name, "scale")) {
            core.scale = @floatCast(@max(opt.value.?.float, 0));
        } else if (std.mem.eql(u8, opt.name, "fit")) {
            core.fit_screen = true;
        } else if (std.mem.eql(u8, opt.name, "brightness")) {
            core.brightness = @floatCast(@max(opt.value.?.float, 0));
        } else if (std.mem.eql(u8, opt.name, "fps")) {
            core.fps = @floatCast(@max(opt.value.?.float, 0));
        } else if (std.mem.eql(u8, opt.name, "loop")) {
            core.loop = true;
        } else if (std.mem.eql(u8, opt.name, "reverse")) {
            try core.ascii_info.reverse(gpa);
        } else if (std.mem.eql(u8, opt.name, "charset")) {
            try core.set_ascii_info(gpa, opt.value.?.string);
        } else if (std.mem.eql(u8, opt.name, "color")) {
            core.toggle_color();
            if (opt.value) |val| {
                const value = val.string;
                core.set_color_mode(value) catch {
                    return ErrorWrap.create_ctx(gpa, ExecError.NoColorModeFound, "{s}", .{value});
                };
            }
        } else if (std.mem.eql(u8, opt.name, "edges")) {
            core.edge_detection = true;
            if (opt.value) |val| {
                const value = val.string;
                core.set_edge_alg(value) catch {
                    return ErrorWrap.create_ctx(gpa, ExecError.NoAlgorithmFound, "{s}", .{value});
                };
            }
        } else if (std.mem.eql(u8, opt.name, "sigma")) {
            core.set_sigma(@floatCast(@max(opt.value.?.float, 0)));
        } else if (std.mem.eql(u8, opt.name, "ccharset")) {
            if (conf) |c| {
                const charsets = c.table.getTable().get("charsets");
                if (charsets == null or charsets.? != .table)
                    return ErrorWrap.create_ctx(gpa, ExecError.NoConfigTable, "charsets", .{});
                const cs = charsets.?.get(opt.value.?.string);
                if (cs == null or cs.? != .string)
                    return ErrorWrap.create_ctx(
                        gpa,
                        ExecError.NoConfigCharset,
                        "{s}",
                        .{opt.value.?.string},
                    );
                try core.set_ascii_info(gpa, cs.?.string);
            } else {
                return ErrorWrap.create_ctx(
                    gpa,
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
    try buffer.appendSlice(allocator, try std.fmt.bufPrint(&line_buf, "Scaling: {d:.3} s\n", .{time.to_s(stats.scaling_ns)}));
    try buffer.appendSlice(
        allocator,
        try std.fmt.bufPrint(&line_buf, "Edge detecting: {d:.3} s\n", .{time.to_s(stats.edge_detect_ns)}),
    );
    try buffer.appendSlice(
        allocator,
        try std.fmt.bufPrint(&line_buf, "Converting: {d:.3} s\n", .{time.to_s(stats.converting_ns)}),
    );
    try buffer.appendSlice(
        allocator,
        try std.fmt.bufPrint(&line_buf, "Read: {d:.3} s\n", .{time.to_s(stats.read_ns)}),
    );
    try buffer.appendSlice(
        allocator,
        try std.fmt.bufPrint(&line_buf, "Write: {d:.3} s\n", .{time.to_s(stats.write_ns)}),
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
        .{time.to_s(stats.scaling_ns) / frames_float},
    ));
    try buffer.appendSlice(allocator, try std.fmt.bufPrint(
        &line_buf,
        "Edge detecting: {d:.3} s/f\n",
        .{time.to_s(stats.edge_detect_ns) / frames_float},
    ));
    try buffer.appendSlice(allocator, try std.fmt.bufPrint(
        &line_buf,
        "Converting: {d:.3} s/f\n",
        .{time.to_s(stats.converting_ns) / frames_float},
    ));
    try buffer.appendSlice(allocator, try std.fmt.bufPrint(
        &line_buf,
        "Read: {d:.3} s/f\n",
        .{time.to_s(stats.read_ns) / frames_float},
    ));
    try buffer.appendSlice(allocator, try std.fmt.bufPrint(
        &line_buf,
        "Write: {d:.3} s/f\n",
        .{time.to_s(stats.write_ns) / frames_float},
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
    io: std.Io,
    gpa: std.mem.Allocator,
    stats: *time.Stats,
    file_type: corelib.MediaType,
) !void {
    var line_buf: [256]u8 = undefined;
    var buffer = try std.ArrayList(u8).initCapacity(gpa, 1024);
    defer buffer.deinit(gpa);
    try buffer.append(gpa, '\n');
    switch (file_type) {
        .Video => try show_stats_video(gpa, &buffer, stats),
        else => try show_stats_image(gpa, &buffer, stats),
    }
    try buffer.appendSlice(gpa, try std.fmt.bufPrint(
        &line_buf,
        "Total time taken: {d:.3} s\n",
        .{time.to_s(stats.total_ns)},
    ));
    try writeEndNl(io, buffer.items);
}

fn generate_completion(
    io: std.Io,
    gpa: std.mem.Allocator,
    cli: *zcli.Cli,
    comptime cli_spec: *const zcli.CliApp,
) !?ErrorWrap {
    var buf: [8096]u8 = undefined;
    const shell = cli.findPositional("shell") orelse
        return ErrorWrap.create(error.NoShellArgument);
    const script = zcli.complete.getCompletion(
        &buf,
        cli_spec,
        cli_spec.config.name.?,
        shell.value,
    ) catch |err| return switch (err) {
        error.UnsupportedShell => ErrorWrap.create_ctx(
            gpa,
            ExecError.UnsupportedShell,
            "{s}",
            .{shell.value},
        ),
        else => err,
    };
    try writeEndNl(io, script);
    return null;
}

pub fn cmd_func(
    io: std.Io,
    gpa: std.mem.Allocator,
    env: *std.process.Environ.Map,
    cli: *zcli.Cli,
    comptime cli_spec: *const zcli.CliApp,
) !?ErrorWrap {
    if (cli.cmd == null) {
        return ErrorWrap.create(ExecError.NoCommand);
    }

    const cmd_name = cli.cmd.?.name;
    if (std.mem.eql(u8, cmd_name, "size")) {
        return try size(io, gpa, cli);
    } else if (std.mem.eql(u8, cmd_name, "ascii")) {
        return try ascii(io, gpa, env, cli, .Image);
    } else if (std.mem.eql(u8, cmd_name, "asciivid")) {
        return try ascii(io, gpa, env, cli, .Video);
    } else if (std.mem.eql(u8, cmd_name, "playback")) {
        return try playback(io, gpa, env, cli);
    } else if (std.mem.eql(u8, cmd_name, "compress")) {
        return null;
    } else if (std.mem.eql(u8, cmd_name, "gen-completion")) {
        return try generate_completion(io, gpa, cli, cli_spec);
    }
    return null;
}
