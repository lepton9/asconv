const std = @import("std");
const cli = @import("cli");
const cmd = cli.cmd;
const result = @import("result");
const image = @import("img");
const utils = @import("utils");
const usage = @import("usage");
const config = @import("config");
const term = @import("term.zig");
const time = image.time;
const Image = image.Image;
const ImageRaw = image.ImageRaw;

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

fn output_file(cli_: *cli.Cli) ?[]const u8 {
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
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    try stdout.print("{s}\n", .{data});
    try bw.flush();
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
    var data = std.ArrayList(u8).init(allocator);

    const res = try client.fetch(.{
        .method = .GET,
        .location = .{ .url = url },
        .response_storage = .{ .dynamic = &data },
    });

    if (res.status != std.http.Status.ok) return ExecError.FetchError;
    return data.toOwnedSlice();
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
    img.core = try image.Core.init(allocator);
    defer Image.deinit(img);

    const img_result = get_input_image(allocator, filename);
    img.set_raw_image(img_result.unwrap_try() catch {
        return img_result.unwrap_err();
    }, filename);

    var buffer: [256]u8 = undefined;
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    try buf.appendSlice(try std.fmt.bufPrint(&buffer, "Image: {s}\n", .{filename}));
    try buf.appendSlice(try std.fmt.bufPrint(
        &buffer,
        "Size: {d}x{d}\n",
        .{ img.raw_image.width, img.raw_image.height },
    ));
    try buf.appendSlice(
        try std.fmt.bufPrint(&buffer, "Channels: {d}\n", .{img.raw_image.nchan}),
    );
    try write_to_stdio(buf.items);
    return null;
}

fn ascii(allocator: std.mem.Allocator, cli_: *cli.Cli) !?result.ErrorWrap {
    var core = try image.Core.init(allocator);
    var timer_total = try time.Timer.start(&core.perf.total);
    const filename = input_file(cli_) catch |err| {
        return result.ErrorWrap.create(err, "{s}", .{cli_.global_args orelse ""});
    };
    var timer_read = try time.Timer.start(&core.perf.read);
    const img_result = get_input_image(allocator, filename);
    timer_read.stop();
    const raw_image = img_result.unwrap_try() catch {
        return img_result.unwrap_err();
    };
    var height: u32 = @intCast(raw_image.height);
    var width: u32 = @intCast(raw_image.width);
    try core.set_ascii_info(allocator, usage.characters);

    if (try ascii_opts(allocator, cli_, core, &width, &height)) |err| {
        return err;
    }

    var img = try Image.init(allocator, height, width);
    defer Image.deinit(img);
    img.core = core;
    if (core.edge_detection) try img.set_edge_detection();
    img.set_raw_image(raw_image, filename);
    try img.fit_image();

    const data = try img.to_ascii();
    defer allocator.free(data);
    const file = output_file(cli_);
    var timer_print = try time.Timer.start(&core.perf.write);
    if (file) |path| {
        try write_to_file(path, data);
    } else {
        try write_to_stdio(data);
    }
    timer_print.stop();
    timer_total.stop();
    if (cli_.find_opt("time")) |_| {
        try show_performance(allocator, core.perf);
    }
    return null;
}

fn ascii_opts(
    allocator: std.mem.Allocator,
    cli_: *cli.Cli,
    core: *image.Core,
    width: *u32,
    height: *u32,
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

    for (cli_.args.?.items) |*opt| {
        if (std.mem.eql(u8, opt.long_name, "height")) {
            height.* = std.fmt.parseInt(u32, opt.arg.?.value.?, 10) catch {
                return result.ErrorWrap.create(ExecError.ParseErrorHeight, "{s}", .{opt.arg.?.value.?});
            };
        } else if (std.mem.eql(u8, opt.long_name, "width")) {
            width.* = std.fmt.parseInt(u32, opt.arg.?.value.?, 10) catch {
                return result.ErrorWrap.create(ExecError.ParseErrorWidth, "{s}", .{opt.arg.?.value.?});
            };
        } else if (std.mem.eql(u8, opt.long_name, "scale")) {
            core.scale = std.fmt.parseFloat(f32, opt.arg.?.value.?) catch {
                return result.ErrorWrap.create(ExecError.ParseErrorScale, "{s}", .{opt.arg.?.value.?});
            };
            height.* = @intFromFloat(utils.itof(f32, height.*) * core.scale);
            width.* = @intFromFloat(utils.itof(f32, width.*) * core.scale);
        } else if (std.mem.eql(u8, opt.long_name, "fit")) {
            const term_size = try term.get_term_size();
            core.scale = image.get_scale(
                @intCast(width.*),
                @intCast(height.*),
                term_size.width,
                term_size.height,
            );
            height.* = @intFromFloat(utils.itof(f32, height.*) * core.scale);
            width.* = @intFromFloat(utils.itof(f32, width.*) * core.scale);
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
        }
    }
    return null;
}

fn show_performance(allocator: std.mem.Allocator, perf: time.Time) !void {
    var line_buf: [256]u8 = undefined;
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    try buffer.appendSlice(
        try std.fmt.bufPrint(&line_buf, "Scaling: {d:.3} s\n", .{time.to_s(perf.scaling)}),
    );
    try buffer.appendSlice(
        try std.fmt.bufPrint(&line_buf, "Edge detecting: {d:.3} s\n", .{time.to_s(perf.edge_detect)}),
    );
    try buffer.appendSlice(
        try std.fmt.bufPrint(&line_buf, "Converting: {d:.3} s\n", .{time.to_s(perf.converting)}),
    );
    try buffer.appendSlice(
        try std.fmt.bufPrint(&line_buf, "Read: {d:.3} s\n", .{time.to_s(perf.read)}),
    );
    try buffer.appendSlice(
        try std.fmt.bufPrint(&line_buf, "Write: {d:.3} s\n", .{time.to_s(perf.write)}),
    );
    try buffer.appendSlice(
        try std.fmt.bufPrint(&line_buf, "Total: {d:.3} s\n", .{time.to_s(perf.total)}),
    );
    try write_to_stdio(buffer.items);
}

fn help(allocator: std.mem.Allocator, args_struct: *cmd.ArgsStructure) !void {
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    try buf.appendSlice("Usage: asconv [command] [options]\n\n");
    const args = try args_struct.args_structure_string(allocator);
    defer allocator.free(args);
    try buf.appendSlice(args);
    try write_to_stdio(buf.items);
}

pub fn cmd_func(allocator: std.mem.Allocator, cli_: *cli.Cli, args_struct: *cmd.ArgsStructure) !?result.ErrorWrap {
    if (cli_.cmd == null) {
        std.log.info("No command", .{});
        return null;
    }
    const cmd_name = cli_.cmd.?.name.?;
    if (std.mem.eql(u8, cmd_name, "size")) {
        return try size(allocator, cli_);
    } else if (std.mem.eql(u8, cmd_name, "ascii")) {
        return try ascii(allocator, cli_);
    } else if (std.mem.eql(u8, cmd_name, "compress")) {
        return null;
    } else if (std.mem.eql(u8, cmd_name, "help")) {
        try help(allocator, args_struct);
    }
    return null;
}
