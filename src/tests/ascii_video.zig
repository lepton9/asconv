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
    const alloc = std.testing.allocator;
    const cwd = std.fs.cwd();
    try cwd.makePath(output);

    var args = [_][:0]u8{
        @constCast("asconv"),
        @constCast("asciivid"),
        @constCast("--out"),
        @constCast(output),
        @constCast("--scale=0.1"),
        @constCast("--edges=sobel"),
        @constCast(test_input),
    };
    const cli = try zcli.parse_from(alloc, &app, &args);
    defer cli.deinit(alloc);
    if (try exec.cmd_func(alloc, cli)) |err| {
        std.debug.print("Error: {}\n", .{err.err});
    }
    try cwd.deleteTree(output);
}
