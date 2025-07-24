const std = @import("std");
const stb = @import("stb_image");
const cli = @import("cli");
const cmd = @import("cmd");
const arg = @import("arg");
const compress = @import("compress");
const result = @import("result");
const Image = compress.Image;

pub const ExecError = error{
    NoFileName,
    FileLoadError,
    ParseErrorHeight,
    ParseErrorWidth,
};

const characters = "M0WN#B@RZUKHEDQA84wmhPkXVOGFgdbS52yqpYL96*3TJCunfzrojea7%x1vscItli+=:-. ";

const commands = [_]cmd.Cmd{
    .{
        .name = "size",
        .desc = "Show size of the image",
        .options = null,
    },
    .{
        .name = "ascii",
        .desc = "Convert to ascii",
        .options = null,
    },
    .{
        .name = "compress",
        .desc = "Compress image",
        .options = null,
    },
    .{
        .name = "help",
        .desc = "Print help",
        .options = null,
    },
};

const options = [_]cmd.Option{
    .{
        .long_name = "out",
        .short_name = "o",
        .desc = "Path of output file",
        .required = false,
        .arg_name = "filename",
    },
    .{
        .long_name = "width",
        .short_name = "w",
        .desc = "Width of wanted image",
        .required = false,
        .arg_name = "int",
    },
    .{
        .long_name = "height",
        .short_name = "h",
        .desc = "Height of wanted image",
        .required = false,
        .arg_name = "int",
    },
    .{
        .long_name = "scale",
        .short_name = "s",
        .desc = "Scale the image to size",
        .required = false,
        .arg_name = "float",
    },
};

fn handle_cli(cli_result: cli.ResultCli) ?cli.Cli {
    return cli_result.unwrap_try() catch {
        const err = cli_result.unwrap_err();
        switch (err.err) {
            cli.ArgsError.UnknownCommand => {
                std.log.err("Unknown command: '{s}'", .{err.get_ctx()});
            },
            cli.ArgsError.UnknownOption => {
                std.log.err("Unknown option: '{s}'\n", .{err.get_ctx()});
            },
            cli.ArgsError.NoCommand => {
                std.log.err("No command given\n", .{});
            },
            cli.ArgsError.NoGlobalArgs => {
                std.log.err("No global arguments\n", .{});
            },
            cli.ArgsError.NoOptionValue => {
                std.log.err("No option value for option '{s}'\n", .{err.get_ctx()});
            },
            cli.ArgsError.NoRequiredOption => {
                std.log.err("Required options not given: {s}\n", .{err.get_ctx()});
            },
            cli.ArgsError.TooManyArgs => {
                std.log.err("Too many arguments: '{s}'\n", .{err.get_ctx()});
            },
            cli.ArgsError.DuplicateOption => {
                std.log.err("Duplicate option: '{s}'\n", .{err.get_ctx()});
            },
            else => {
                std.log.err("Error\n", .{});
            },
        }
        return null;
    };
}

fn handle_exec_error(err: result.ErrorWrap) void {
    switch (err.err) {
        ExecError.NoFileName => {
            std.log.err("No file given as argument", .{});
        },
        ExecError.FileLoadError => {
            std.log.err("Failed to load image '{s}'", .{err.get_ctx()});
        },
        ExecError.ParseErrorHeight => {
            std.log.err("Failed to parse height '{s}'", .{err.get_ctx()});
        },
        ExecError.ParseErrorWidth => {
            std.log.err("Failed to parse width '{s}'", .{err.get_ctx()});
        },
        else => {
            std.log.err("Error: '{s}'", .{err.get_ctx()});
        },
    }
}

fn output_file(cli_: *cli.Cli) ?[]const u8 {
    const option = cli_.find_opt("out");
    if (option) |opt| {
        return opt.arg_value.?;
    }
    return null;
}

fn make_ascii_data(img: *Image) ![]const u8 {
    var buffer = std.ArrayList(u8).init(std.heap.page_allocator);
    defer buffer.deinit();
    for (img.pixels) |row| {
        for (row) |pixel| {
            const c: []const u8 = img.pixel_char(pixel);
            try buffer.appendSlice(c);
            try buffer.appendSlice(c);
        }
        try buffer.appendSlice("\n");
    }
    return buffer.toOwnedSlice();
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

fn size(cli_: *cli.Cli) !?result.ErrorWrap {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var malloc = gpa.allocator();
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    const filename = cli_.global_args orelse "";
    const img = try Image.init(&malloc, 0, 0);
    defer Image.deinit(img, &malloc);
    img.raw_image.* = stb.load_image(filename, null) catch {
        return result.ErrorWrap.create(ExecError.FileLoadError, "{s}", .{filename});
    };
    img.name = filename;

    try stdout.print("Image: {s}\n", .{filename});
    try stdout.print("Size: {d}x{d}\n", .{ img.raw_image.width, img.raw_image.height });
    try stdout.print("Channels: {d}\n", .{img.raw_image.nchan});
    try bw.flush();
    return null;
}

fn ascii(cli_: *cli.Cli) !?result.ErrorWrap {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var malloc = gpa.allocator();
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    const filename = cli_.global_args orelse {
        return result.ErrorWrap.create(ExecError.NoFileName, "", .{});
    };
    var height: u32 = 0;
    var width: u32 = 0;

    var img = try Image.init(&malloc, height, width);
    defer Image.deinit(img, &malloc);
    img.raw_image.* = stb.load_image(filename, null) catch {
        return result.ErrorWrap.create(ExecError.FileLoadError, "{s}", .{filename});
    };
    img.name = filename;
    img.ascii_info = try compress.AsciiInfo.init(&malloc, characters);

    const scale_opt = cli_.find_opt("scale");
    if (scale_opt != null) {
        const mul = try std.fmt.parseFloat(f32, scale_opt.?.arg_value.?);
        height = @intFromFloat(@as(f32, @floatFromInt(img.raw_image.height)) * mul);
        width = @intFromFloat(@as(f32, @floatFromInt(img.raw_image.width)) * mul);
    } else {
        const opt_height = cli_.find_opt("height");
        const opt_width = cli_.find_opt("width");
        height = if (opt_height != null)
            std.fmt.parseInt(u32, opt_height.?.arg_value.?, 10) catch {
                return result.ErrorWrap.create(ExecError.ParseErrorHeight, "{s}", .{opt_height.?.arg_value.?});
            }
        else
            @as(u32, @intCast(img.raw_image.height));

        width = if (opt_width != null)
            std.fmt.parseInt(u32, opt_width.?.arg_value.?, 10) catch {
                return result.ErrorWrap.create(ExecError.ParseErrorWidth, "{s}", .{opt_width.?.arg_value.?});
            }
        else
            @as(u32, @intCast(img.raw_image.width));
    }
    try img.resize(&malloc, height, width);
    img.fit_image();

    const data = try make_ascii_data(img);
    const file = output_file(cli_);
    if (file) |path| {
        try write_to_file(path, data);
    } else {
        try write_to_stdio(data);
    }

    try stdout.print("Image: {s}\n", .{filename});
    try stdout.print("Image of size {d}x{d} with {d} channels\n", .{ img.raw_image.width, img.raw_image.height, img.raw_image.nchan });
    try bw.flush();
    return null;
}

fn cmd_func(cli_: *cli.Cli, args_struct: *cmd.ArgsStructure) !?result.ErrorWrap {
    if (cli_.cmd == null) {
        std.log.info("No command", .{});
        return null;
    }
    const cmd_name = cli_.cmd.?.name.?;
    if (std.mem.eql(u8, cmd_name, "size")) {
        return try size(cli_);
    } else if (std.mem.eql(u8, cmd_name, "ascii")) {
        return try ascii(cli_);
    } else if (std.mem.eql(u8, cmd_name, "compress")) {} else if (std.mem.eql(u8, cmd_name, "help")) {
        args_struct.print_commands();
    }
    return null;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var malloc = gpa.allocator();

    const app = try cmd.ArgsStructure.init(&malloc);
    defer app.deinit(&malloc);
    app.cmd_required = true;
    app.set_commands(&commands);
    app.set_options(&options);

    var args_str = try std.process.argsAlloc(malloc);
    defer std.process.argsFree(malloc, args_str);
    const args = try arg.parse_args(args_str[1..]);

    const cli_result = cli.validate_parsed_args(args, app);
    var cli_ = handle_cli(cli_result) orelse return;

    const err = try cmd_func(&cli_, app);
    if (err) |e| handle_exec_error(e);
}
