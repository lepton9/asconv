const std = @import("std");
const zcli = @import("zcli");
const exec = @import("exec");

const test_image = "https://cdn.7tv.app/emote/01GXHWC0QG000BFY6BHVKSSEXW/4x.gif";
const output = "test_out.txt";

const app = zcli.CliApp{
    .commands = &exec.commands,
    .options = &exec.options,
    .positionals = &exec.positionals,
};

test "sobel" {
    const alloc = std.testing.allocator;
    var args = [_][:0]u8{
        @constCast("asconv"),
        @constCast("ascii"),
        @constCast("--out"),
        @constCast(output),
        @constCast("--scale=0.1"),
        @constCast("--edges=sobel"),
        @constCast(test_image),
    };
    const cli = try zcli.parseFrom(alloc, &app, &args);
    defer cli.deinit(alloc);
    if (try exec.cmd_func(alloc, cli, &app)) |err| {
        std.debug.print("Error: {}\n", .{err.err});
    }
    try std.fs.cwd().deleteFile(output);
}

test "dog" {
    const alloc = std.testing.allocator;
    var args = [_][:0]u8{
        @constCast("asconv"),
        @constCast("ascii"),
        @constCast("--out"),
        @constCast(output),
        @constCast("--scale=0.1"),
        @constCast("--edges=dog"),
        @constCast("--sigma=1.0"),
        @constCast(test_image),
    };
    const cli = try zcli.parseFrom(alloc, &app, &args);
    defer cli.deinit(alloc);
    if (try exec.cmd_func(alloc, cli, &app)) |err| {
        std.debug.print("Error: {}\n", .{err.err});
    }
    try std.fs.cwd().deleteFile(output);
}

test "log" {
    const alloc = std.testing.allocator;
    var args = [_][:0]u8{
        @constCast("asconv"),
        @constCast("ascii"),
        @constCast("--out"),
        @constCast(output),
        @constCast("--scale=0.1"),
        @constCast("--edges=log"),
        @constCast("--sigma=1.0"),
        @constCast(test_image),
    };
    const cli = try zcli.parseFrom(alloc, &app, &args);
    defer cli.deinit(alloc);
    if (try exec.cmd_func(alloc, cli, &app)) |err| {
        std.debug.print("Error: {}\n", .{err.err});
    }
    try std.fs.cwd().deleteFile(output);
}

test "color" {
    const alloc = std.testing.allocator;
    var args = [_][:0]u8{
        @constCast("asconv"),
        @constCast("ascii"),
        @constCast("--out"),
        @constCast(output),
        @constCast("--scale=0.1"),
        @constCast("--color=color256"),
        @constCast(test_image),
    };
    const cli = try zcli.parseFrom(alloc, &app, &args);
    defer cli.deinit(alloc);
    if (try exec.cmd_func(alloc, cli, &app)) |err| {
        std.debug.print("Error: {}\n", .{err.err});
    }
    try std.fs.cwd().deleteFile(output);
}

test "charset" {
    const alloc = std.testing.allocator;
    var args = [_][:0]u8{
        @constCast("asconv"),
        @constCast("ascii"),
        @constCast("--out"),
        @constCast(output),
        @constCast("--scale=0.1"),
        @constCast("--charset=@#%xo;:.,"),
        @constCast("--reverse"),
        @constCast(test_image),
    };
    const cli = try zcli.parseFrom(alloc, &app, &args);
    defer cli.deinit(alloc);
    if (try exec.cmd_func(alloc, cli, &app)) |err| {
        std.debug.print("Error: {}\n", .{err.err});
    }
    try std.fs.cwd().deleteFile(output);
}
