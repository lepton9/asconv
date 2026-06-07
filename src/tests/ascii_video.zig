const std = @import("std");
const zcli = @import("zcli");
const exec = @import("exec");

const test_input = "https://cdn.7tv.app/emote/01GXHWC0QG000BFY6BHVKSSEXW/4x.gif";
const output = "test_output";

const app = zcli.CliApp{
    .commands = &exec.commands,
    .options = &exec.options,
    .positionals = &exec.positionals,
};

test "video" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, output);
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();

    const args: []const [:0]const u8 = &.{
        "asconv",
        "asciivid",
        "--out",
        output,
        "--scale=0.1",
        "--edges=sobel",
        test_input,
    };
    const cli = try zcli.parseFrom(gpa, args, &app);
    defer cli.deinit(gpa);

    if (try exec.cmd_func(io, gpa, &env, cli, &app)) |err| {
        std.debug.print("Error: {}\n", .{err.err});
    }
    try cwd.deleteTree(io, output);
}
