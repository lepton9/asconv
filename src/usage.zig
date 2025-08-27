const cli = @import("cli");
const Cmd = cli.Cmd;
const Option = cli.Option;

pub const characters = " .-:=+iltIcsv1x%7aejorzfnuCJT3*69LYpqy25SbdgFGOVXkPhmw48AQDEHKUZR@B#NW0M";

pub const commands = [_]Cmd{
    .{
        .name = "ascii",
        .desc = "Convert to ascii",
        .options = null,
    },
    .{
        .name = "size",
        .desc = "Show size of the image",
        .options = null,
    },
    // .{
    //     .name = "compress",
    //     .desc = "Compress image",
    //     .options = null,
    // },
    .{
        .name = "help",
        .desc = "Print help",
        .options = null,
    },
};

pub const options = [_]Option{
    .{
        .long_name = "input",
        .short_name = "i",
        .desc = "Input file or url",
        .required = false,
        .arg = .{ .name = "path" },
    },
    .{
        .long_name = "out",
        .short_name = "o",
        .desc = "Path of output file",
        .required = false,
        .arg = .{ .name = "filename" },
    },
    .{
        .long_name = "width",
        .short_name = "w",
        .desc = "Width of wanted image",
        .required = false,
        .arg = .{ .name = "int" },
    },
    .{
        .long_name = "height",
        .short_name = "h",
        .desc = "Height of wanted image",
        .required = false,
        .arg = .{ .name = "int" },
    },
    .{
        .long_name = "scale",
        .short_name = "s",
        .desc = "Scale the image to size",
        .required = false,
        .arg = .{ .name = "float" },
    },
    .{
        .long_name = "fit",
        .short_name = "f",
        .desc = "Scale the image to fit the terminal",
        .required = false,
        .arg = null,
    },
    .{
        .long_name = "brightness",
        .short_name = "b",
        .desc = "Set brightness boost",
        .required = false,
        .arg = .{ .name = "float" },
    },
    .{
        .long_name = "reverse",
        .short_name = "r",
        .desc = "Reverse the charset",
        .required = false,
        .arg = null,
    },
    .{
        .long_name = "charset",
        .short_name = null,
        .desc = "Set custom characters to use",
        .required = false,
        .arg = .{ .name = "string" },
    },
    .{
        .long_name = "color",
        .short_name = "c",
        .desc = "Output with ANSI colors and set color range (default: color256)",
        .required = false,
        .arg = .{ .name = "color256|truecolor", .required = false },
    },
    .{
        .long_name = "edges",
        .short_name = "e",
        .desc = "Turn on edge detection and set algorithm (default: sobel)",
        .required = false,
        .arg = .{ .name = "sobel|LoG|DoG", .required = false },
    },
    .{
        .long_name = "sigma",
        .short_name = null,
        .desc = "Sigma value for DoG and LoG (default: 1.0)",
        .required = false,
        .arg = .{ .name = "float" },
    },
    .{
        .long_name = "time",
        .short_name = "t",
        .desc = "Show the time taken to convert the image",
        .required = false,
        .arg = null,
    },
    .{
        .long_name = "config",
        .short_name = null,
        .desc = "Set custom config path to use",
        .required = false,
        .arg = .{ .name = "string" },
    },
    .{
        .long_name = "ccharset",
        .short_name = null,
        .desc = "Use custom characters that are saved in the config",
        .required = false,
        .arg = .{ .name = "key" },
    },
};
