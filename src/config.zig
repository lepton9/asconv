const cli = @import("cli");
const Cmd = cli.Cmd;
const Option = cli.Option;

pub const characters = "M0WN#B@RZUKHEDQA84wmhPkXVOGFgdbS52yqpYL96*3TJCunfzrojea7%x1vscItli+=:-. ";

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
        .arg_name = "path",
    },
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
    .{
        .long_name = "brightness",
        .short_name = "b",
        .desc = "Set brightness boost",
        .required = false,
        .arg_name = "float",
    },
    .{
        .long_name = "reverse",
        .short_name = "r",
        .desc = "Reverse the charset",
        .required = false,
        .arg_name = null,
    },
    .{
        .long_name = "color",
        .short_name = "c",
        .desc = "Output with ANSI colors",
        .required = false,
        .arg_name = null,
    },
    .{
        .long_name = "colormode",
        .short_name = null,
        .desc = "Set the range of colors used (default: color256)",
        .required = false,
        .arg_name = "color256|truecolor",
    },
    .{
        .long_name = "edges",
        .short_name = "e",
        .desc = "Edge detection",
        .required = false,
        .arg_name = null,
    },
    .{
        .long_name = "alg",
        .short_name = null,
        .desc = "Algorithm for edge detection (default: sobel)",
        .required = false,
        .arg_name = "sobel|LoG|DoG",
    },
    .{
        .long_name = "sigma",
        .short_name = null,
        .desc = "Sigma value for DoG and LoG (default: 1.0)",
        .required = false,
        .arg_name = "float",
    },
    .{
        .long_name = "time",
        .short_name = "t",
        .desc = "Show the time taken to convert the image",
        .required = false,
        .arg_name = null,
    },
};
