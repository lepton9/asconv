const std = @import("std");
const cli = @import("cli");
const exec = @import("exec");
const cmd = cli.cmd;
const arg = cli.arg;

const test_image = "https://cdn.7tv.app/emote/01GXHWC0QG000BFY6BHVKSSEXW/4x.gif";

const app = cmd.ArgsStructure{
    .commands = &exec.commands,
    .options = &exec.options,
};

test "ascii_sobel" {
    const alloc = std.testing.allocator;
    var args = std.ArrayList(arg.ArgParse).init(alloc);
    try args.append(.{ .value = "ascii" });
    try args.append(.{ .option = .{ .name = "out", .option_type = .long, .value = "out.txt" } });
    try args.append(.{ .option = .{ .name = "scale", .option_type = .long, .value = "0.1" } });
    try args.append(.{ .option = .{ .name = "edges", .option_type = .long, .value = "sobel" } });
    try args.append(.{ .value = test_image });
    defer args.deinit();

    const cli_result = cli.validate_parsed_args(args.items, &app);
    if (cli_result.is_ok()) {
        var cli_ = try cli_result.unwrap_try();
        if (try exec.cmd_func(alloc, &cli_, &app)) |err| {
            std.debug.print("Error: {}\n", .{err.err});
        }
    }
}

test "ascii_dog" {
    const alloc = std.testing.allocator;
    var args = std.ArrayList(arg.ArgParse).init(alloc);
    try args.append(.{ .value = "ascii" });
    try args.append(.{ .option = .{ .name = "out", .option_type = .long, .value = "out.txt" } });
    try args.append(.{ .option = .{ .name = "scale", .option_type = .long, .value = "0.1" } });
    try args.append(.{ .option = .{ .name = "edges", .option_type = .long, .value = "dog" } });
    try args.append(.{ .option = .{ .name = "sigma", .option_type = .long, .value = "1.0" } });
    try args.append(.{ .value = test_image });
    defer args.deinit();

    const cli_result = cli.validate_parsed_args(args.items, &app);
    if (cli_result.is_ok()) {
        var cli_ = try cli_result.unwrap_try();
        if (try exec.cmd_func(alloc, &cli_, &app)) |err| {
            std.debug.print("Error: {}\n", .{err.err});
        }
    }
}

test "ascii_log" {
    const alloc = std.testing.allocator;
    var args = std.ArrayList(arg.ArgParse).init(alloc);
    try args.append(.{ .value = "ascii" });
    try args.append(.{ .option = .{ .name = "out", .option_type = .long, .value = "out.txt" } });
    try args.append(.{ .option = .{ .name = "scale", .option_type = .long, .value = "0.1" } });
    try args.append(.{ .option = .{ .name = "edges", .option_type = .long, .value = "log" } });
    try args.append(.{ .option = .{ .name = "sigma", .option_type = .long, .value = "1.0" } });
    try args.append(.{ .value = test_image });
    defer args.deinit();

    const cli_result = cli.validate_parsed_args(args.items, &app);
    if (cli_result.is_ok()) {
        var cli_ = try cli_result.unwrap_try();
        if (try exec.cmd_func(alloc, &cli_, &app)) |err| {
            std.debug.print("Error: {}\n", .{err.err});
        }
    }
}

test "ascii_color" {
    const alloc = std.testing.allocator;
    var args = std.ArrayList(arg.ArgParse).init(alloc);
    try args.append(.{ .value = "ascii" });
    try args.append(.{ .option = .{ .name = "out", .option_type = .long, .value = "out.txt" } });
    try args.append(.{ .option = .{ .name = "scale", .option_type = .long, .value = "0.1" } });
    try args.append(.{ .option = .{ .name = "color", .option_type = .long, .value = "color256" } });
    try args.append(.{ .value = test_image });
    defer args.deinit();

    const cli_result = cli.validate_parsed_args(args.items, &app);
    if (cli_result.is_ok()) {
        var cli_ = try cli_result.unwrap_try();
        if (try exec.cmd_func(alloc, &cli_, &app)) |err| {
            std.debug.print("Error: {}\n", .{err.err});
        }
    }
}
