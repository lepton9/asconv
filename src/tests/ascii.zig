const std = @import("std");
const cwd = std.fs.cwd();
const cli = @import("cli");
const exec = @import("exec");
const cmd = cli.cmd;
const arg = cli.arg;

const test_image = "https://cdn.7tv.app/emote/01GXHWC0QG000BFY6BHVKSSEXW/4x.gif";
const output = "test_out.txt";

const app = cmd.ArgsStructure{
    .commands = &exec.commands,
    .options = &exec.options,
};

test "sobel" {
    const alloc = std.testing.allocator;
    var args = try std.ArrayList(arg.ArgParse).initCapacity(alloc, 5);
    try args.append(alloc, .{ .value = "ascii" });
    try args.append(alloc, .{ .option = .{ .name = "out", .option_type = .long, .value = output } });
    try args.append(alloc, .{ .option = .{ .name = "scale", .option_type = .long, .value = "0.1" } });
    try args.append(alloc, .{ .option = .{ .name = "edges", .option_type = .long, .value = "sobel" } });
    try args.append(alloc, .{ .value = test_image });
    defer args.deinit(alloc);

    const cli_result = try cli.validate_parsed_args(alloc, args.items, &app);
    if (cli_result.is_ok()) {
        const cli_ = try cli_result.unwrap_try();
        defer cli_.deinit(alloc);
        if (try exec.cmd_func(alloc, cli_, &app)) |err| {
            std.debug.print("Error: {}\n", .{err.err});
        }
    }
    try cwd.deleteFile(output);
}

test "dog" {
    const alloc = std.testing.allocator;
    var args = try std.ArrayList(arg.ArgParse).initCapacity(alloc, 6);
    try args.append(alloc, .{ .value = "ascii" });
    try args.append(alloc, .{ .option = .{ .name = "out", .option_type = .long, .value = output } });
    try args.append(alloc, .{ .option = .{ .name = "scale", .option_type = .long, .value = "0.1" } });
    try args.append(alloc, .{ .option = .{ .name = "edges", .option_type = .long, .value = "dog" } });
    try args.append(alloc, .{ .option = .{ .name = "sigma", .option_type = .long, .value = "1.0" } });
    try args.append(alloc, .{ .value = test_image });
    defer args.deinit(alloc);

    const cli_result = try cli.validate_parsed_args(alloc, args.items, &app);
    if (cli_result.is_ok()) {
        const cli_ = try cli_result.unwrap_try();
        defer cli_.deinit(alloc);
        if (try exec.cmd_func(alloc, cli_, &app)) |err| {
            std.debug.print("Error: {}\n", .{err.err});
        }
    }
    try cwd.deleteFile(output);
}

test "log" {
    const alloc = std.testing.allocator;
    var args = try std.ArrayList(arg.ArgParse).initCapacity(alloc, 6);
    try args.append(alloc, .{ .value = "ascii" });
    try args.append(alloc, .{ .option = .{ .name = "out", .option_type = .long, .value = output } });
    try args.append(alloc, .{ .option = .{ .name = "scale", .option_type = .long, .value = "0.1" } });
    try args.append(alloc, .{ .option = .{ .name = "edges", .option_type = .long, .value = "log" } });
    try args.append(alloc, .{ .option = .{ .name = "sigma", .option_type = .long, .value = "1.0" } });
    try args.append(alloc, .{ .value = test_image });
    defer args.deinit(alloc);

    const cli_result = try cli.validate_parsed_args(alloc, args.items, &app);
    if (cli_result.is_ok()) {
        const cli_ = try cli_result.unwrap_try();
        defer cli_.deinit(alloc);
        if (try exec.cmd_func(alloc, cli_, &app)) |err| {
            std.debug.print("Error: {}\n", .{err.err});
        }
    }
    try cwd.deleteFile(output);
}

test "color" {
    const alloc = std.testing.allocator;
    var args = try std.ArrayList(arg.ArgParse).initCapacity(alloc, 5);
    try args.append(alloc, .{ .value = "ascii" });
    try args.append(alloc, .{ .option = .{ .name = "out", .option_type = .long, .value = output } });
    try args.append(alloc, .{ .option = .{ .name = "scale", .option_type = .long, .value = "0.1" } });
    try args.append(alloc, .{ .option = .{ .name = "color", .option_type = .long, .value = "color256" } });
    try args.append(alloc, .{ .value = test_image });
    defer args.deinit(alloc);

    const cli_result = try cli.validate_parsed_args(alloc, args.items, &app);
    if (cli_result.is_ok()) {
        const cli_ = try cli_result.unwrap_try();
        defer cli_.deinit(alloc);
        if (try exec.cmd_func(alloc, cli_, &app)) |err| {
            std.debug.print("Error: {}\n", .{err.err});
        }
    }
    try cwd.deleteFile(output);
}

test "charset" {
    const alloc = std.testing.allocator;
    var args = try std.ArrayList(arg.ArgParse).initCapacity(alloc, 6);
    try args.append(alloc, .{ .value = "ascii" });
    try args.append(alloc, .{ .option = .{ .name = "out", .option_type = .long, .value = output } });
    try args.append(alloc, .{ .option = .{ .name = "scale", .option_type = .long, .value = "0.1" } });
    try args.append(alloc, .{ .option = .{ .name = "charset", .option_type = .long, .value = "@#%xo;:.," } });
    try args.append(alloc, .{ .option = .{ .name = "reverse", .option_type = .long, .value = null } });
    try args.append(alloc, .{ .value = test_image });
    defer args.deinit(alloc);

    const cli_result = try cli.validate_parsed_args(alloc, args.items, &app);
    if (cli_result.is_ok()) {
        const cli_ = try cli_result.unwrap_try();
        defer cli_.deinit(alloc);
        if (try exec.cmd_func(alloc, cli_, &app)) |err| {
            std.debug.print("Error: {}\n", .{err.err});
        }
    }
    try cwd.deleteFile(output);
}
