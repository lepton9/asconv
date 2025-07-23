const std = @import("std");
const stb = @import("stb_image");
const cli = @import("cli");
const cmd = @import("cmd");
const arg = @import("arg");
const compress = @import("compress");
const Image = compress.Image;

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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    const filename = "./images/test.jpg";
    const height: u32 = 10;
    const width: u32 = 10;

    var malloc = gpa.allocator();
    const img = try Image.init(&malloc, height, width);
    defer Image.deinit(img, &malloc);
    for (img.pixels) |row| {
        for (row) |pixel| {
            try stdout.print("{c} ", .{compress.pixel_to_char(pixel)});
        }
        try stdout.print("\n", .{});
    }
    try bw.flush();

    img.raw_image.* = try stb.load_image(filename, null);
    std.debug.print("Image: {s}\n", .{filename});
    std.debug.print("Image of size {d}x{d} with {d} channels\n", .{ img.raw_image.width, img.raw_image.height, img.raw_image.nchan });
}
