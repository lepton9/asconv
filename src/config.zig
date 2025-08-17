const cli = @import("cli");
const Cmd = cli.Cmd;
const Option = cli.Option;

pub const characters = "M0WN#B@RZUKHEDQA84wmhPkXVOGFgdbS52yqpYL96*3TJCunfzrojea7%x1vscItli+=:-. ";

pub const commands = [_]Cmd{
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
        .long_name = "reverse",
        .short_name = "r",
        .desc = "Reverse the charset",
        .required = false,
        .arg_name = null,
    },
};
