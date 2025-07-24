const std = @import("std");
const stb = @import("stb_image");
const cli = @import("cli");
const cmd = @import("cmd");
const arg = @import("arg");
const compress = @import("compress");
const Image = compress.Image;

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

fn size(cli_: *cli.Cli) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var malloc = gpa.allocator();
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    const filename = cli_.global_args orelse "";
    const img = try Image.init(&malloc, 0, 0);
    defer Image.deinit(img, &malloc);
    img.raw_image.* = try stb.load_image(filename, null);
    img.name = filename;

    try stdout.print("Image: {s}\n", .{filename});
    try stdout.print("Size: {d}x{d}\n", .{ img.raw_image.width, img.raw_image.height });
    try stdout.print("Channels: {d}\n", .{img.raw_image.nchan});
    try bw.flush();
}

fn ascii(cli_: *cli.Cli) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var malloc = gpa.allocator();
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    const filename = cli_.global_args orelse "";
    var height: u32 = 0;
    var width: u32 = 0;

    var img = try Image.init(&malloc, height, width);
    defer Image.deinit(img, &malloc);
    img.raw_image.* = try stb.load_image(filename, null);
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
            std.fmt.parseInt(u32, opt_height.?.arg_value.?, 10) catch |err| {
                try stdout.print("Error parsing height: {}\n", .{err});
                return;
            }
        else
            @as(u32, @intCast(img.raw_image.height));

        width = if (opt_width != null)
            std.fmt.parseInt(u32, opt_width.?.arg_value.?, 10) catch |err| {
                try stdout.print("Error parsing width: {}\n", .{err});
                return;
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
}

fn cmd_func(cli_: *cli.Cli, args_struct: *cmd.ArgsStructure) !void {
    const cmd_name = cli_.cmd.?.name.?;
    if (std.mem.eql(u8, cmd_name, "size")) {
        try size(cli_);
    } else if (std.mem.eql(u8, cmd_name, "ascii")) {
        try ascii(cli_);
    } else if (std.mem.eql(u8, cmd_name, "compress")) {
        return;
    } else if (std.mem.eql(u8, cmd_name, "help")) {
        args_struct.print_commands();
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var malloc = gpa.allocator();

    const app = try cmd.ArgsStructure.init(&malloc);
    defer app.deinit(&malloc);
    app.set_commands(&commands);
    app.set_options(&options);

    var args_str = try std.process.argsAlloc(malloc);
    defer std.process.argsFree(malloc, args_str);
    const args = try arg.parse_args(args_str[1..]);

    const cli_result = cli.validate_parsed_args(args, app);
    var cli_ = handle_cli(cli_result) orelse return;

    try cmd_func(&cli_, app);
}
