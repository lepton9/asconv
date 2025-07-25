const std = @import("std");
const stb = @import("stb_image");
const cli = @import("cli");
const cmd = @import("cmd");
const arg = @import("arg");
const compress = @import("compress");
const result = @import("result");
const utils = @import("utils");
const Image = compress.Image;

pub const ExecError = error{
    NoFileName,
    FileLoadError,
    ParseErrorHeight,
    ParseErrorWidth,
    ParseErrorScale,
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
        ExecError.ParseErrorScale => {
            std.log.err("Failed to parse scale '{s}'", .{err.get_ctx()});
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
    const malloc = gpa.allocator();
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    const filename = cli_.global_args orelse "";
    const img = try Image.init(malloc, 0, 0);
    defer Image.deinit(img);
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
    const malloc = gpa.allocator();
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    const filename = cli_.global_args orelse {
        return result.ErrorWrap.create(ExecError.NoFileName, "", .{});
    };
    const raw_image = stb.load_image(filename, null) catch {
        return result.ErrorWrap.create(ExecError.FileLoadError, "{s}", .{filename});
    };
    var height: u32 = @intCast(raw_image.height);
    var width: u32 = @intCast(raw_image.width);

    if (cli_.find_opt("height")) |opt_height| {
        height = std.fmt.parseInt(u32, opt_height.arg_value.?, 10) catch {
            return result.ErrorWrap.create(ExecError.ParseErrorHeight, "{s}", .{opt_height.arg_value.?});
        };
    }
    if (cli_.find_opt("width")) |opt_width| {
        width = std.fmt.parseInt(u32, opt_width.arg_value.?, 10) catch {
            return result.ErrorWrap.create(ExecError.ParseErrorWidth, "{s}", .{opt_width.arg_value.?});
        };
    }
    if (cli_.find_opt("scale")) |opt_scale| {
        const scalar = std.fmt.parseFloat(f32, opt_scale.arg_value.?) catch {
            return result.ErrorWrap.create(ExecError.ParseErrorScale, "{s}", .{opt_scale.arg_value.?});
        };
        height = @intFromFloat(utils.itof(f32, height) * scalar);
        width = @intFromFloat(utils.itof(f32, width) * scalar);
    }

    var img = try Image.init(malloc, height, width);
    defer Image.deinit(img);
    img.set_raw_image(raw_image, filename);
    try img.set_ascii_info(characters);
    try img.fit_image();

    const data = try img.to_ascii();
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
