const zcli = @import("zcli");
const Cmd = zcli.Cmd;
const Opt = zcli.Opt;
const PosArg = zcli.PosArg;

pub const characters = " .-:=+iltIcsv1x%7aejorzfnuCJT3*69LYpqy25SbdgFGOVXkPhmw48AQDEHKUZR@B#NW0M";

pub const commands = [_]Cmd{
    .{
        .name = "ascii",
        .desc = "Convert image to ascii",
        .options = null,
    },
    .{
        .name = "asciivid",
        .desc = "Convert video to ascii",
        .options = null,
    },
    .{
        .name = "playback",
        .desc = "Play converted ascii video",
        .options = null,
    },
    .{
        .name = "size",
        .desc = "Show size of the image",
        .options = null,
    },
};

pub const options = [_]Opt{
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
        .desc = "Path of the output file (omit to output to stdout)",
        .required = false,
        .arg = .{ .name = "filename" },
    },
    .{
        .long_name = "width",
        .short_name = "W",
        .desc = "Width of wanted image",
        .required = false,
        .arg = .{ .name = "int" },
    },
    .{
        .long_name = "height",
        .short_name = "H",
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
        .desc = "Output with ANSI colors and set color range",
        .required = false,
        .arg = .{ .name = "color256|truecolor", .default = "color256", .required = false },
    },
    .{
        .long_name = "edges",
        .short_name = "e",
        .desc = "Turn on edge detection and set algorithm",
        .required = false,
        .arg = .{ .name = "sobel|LoG|DoG", .default = "sobel", .required = false },
    },
    .{
        .long_name = "sigma",
        .short_name = null,
        .desc = "Sigma value for DoG and LoG",
        .required = false,
        .arg = .{ .name = "float", .default = "1.0" },
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
    .{
        .long_name = "fps",
        .short_name = null,
        .desc = "Set target FPS for video",
        .required = false,
        .arg = .{ .name = "float" },
    },
    .{
        .long_name = "loop",
        .short_name = "l",
        .desc = "Loop the video",
        .required = false,
        .arg = null,
    },
    .{
        .long_name = "progress",
        .short_name = "p",
        .desc = "Display the progress of converting video to ASCII",
        .required = false,
        .arg = null,
    },
    .{
        .long_name = "dropframes",
        .short_name = "d",
        .desc = "Enable frame dropping to maintain target FPS",
        .required = false,
        .arg = null,
    },
    .{
        .long_name = "version",
        .short_name = "V",
        .desc = "Print version",
    },
    .{
        .long_name = "help",
        .short_name = "h",
        .desc = "Print help",
    },
};

pub const positionals = [_]PosArg{
    .{ .name = "input", .required = false },
};
