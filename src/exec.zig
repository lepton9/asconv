const std = @import("std");
const cli = @import("cli");
const cmd = cli.cmd;
const result = @import("result");
const compress = @import("compress");
const utils = @import("utils");
const config = @import("config.zig");
const Image = compress.Image;

pub const commands = config.commands;
pub const options = config.options;

pub const ExecError = error{
    NoFileName,
    FileLoadError,
    ParseErrorHeight,
    ParseErrorWidth,
    ParseErrorScale,
};

fn output_file(cli_: *cli.Cli) ?[]const u8 {
    const option = cli_.find_opt("out");
    if (option) |opt| {
        return opt.arg_value.?;
    }
    return null;
}

fn write_to_file(file_path: []const u8, data: []const u8) !void {
    var file = try std.fs.cwd().createFile(file_path, .{});
    defer file.close();
    try file.writeAll(data);
}

fn write_to_stdio(data: []const u8) !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    try stdout.print("{s}\n", .{data});
    try bw.flush();
}

fn size(allocator: std.mem.Allocator, cli_: *cli.Cli) !?result.ErrorWrap {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    const filename = cli_.global_args orelse "";
    const img = try Image.init(allocator, 0, 0);
    defer Image.deinit(img);
    img.raw_image.* = compress.load_image(filename, null) catch {
        return result.ErrorWrap.create(ExecError.FileLoadError, "{s}", .{filename});
    };
    img.name = filename;

    try stdout.print("Image: {s}\n", .{filename});
    try stdout.print("Size: {d}x{d}\n", .{ img.raw_image.width, img.raw_image.height });
    try stdout.print("Channels: {d}\n", .{img.raw_image.nchan});
    try bw.flush();
    return null;
}

fn ascii(allocator: std.mem.Allocator, cli_: *cli.Cli) !?result.ErrorWrap {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    const filename = cli_.global_args orelse {
        return result.ErrorWrap.create(ExecError.NoFileName, "", .{});
    };
    const raw_image = compress.load_image(filename, null) catch {
        return result.ErrorWrap.create(ExecError.FileLoadError, "{s}", .{filename});
    };
    var height: u32 = @intCast(raw_image.height);
    var width: u32 = @intCast(raw_image.width);
    const charset: []u8 = try allocator.dupe(u8, config.characters);
    defer allocator.free(charset);

    if (cli_.find_opt("height")) |opt_height| {
        height = std.fmt.parseInt(u32, opt_height.arg_value.?, 10) catch {
            return result.ErrorWrap.create(ExecError.ParseErrorHeight, "{s}", .{opt_height.arg_value.?});
        };
    }
    if (cli_.find_opt("width")) |opt_width| {
        width = std.fmt.parseInt(u32, opt_width.arg_value.?, 10) catch {
            return result.ErrorWrap.create(ExecError.ParseErrorWidth, "{s}", .{opt_width.arg_value.?});
        };
    }
    if (cli_.find_opt("scale")) |opt_scale| {
        const scalar = std.fmt.parseFloat(f32, opt_scale.arg_value.?) catch {
            return result.ErrorWrap.create(ExecError.ParseErrorScale, "{s}", .{opt_scale.arg_value.?});
        };
        height = @intFromFloat(utils.itof(f32, height) * scalar);
        width = @intFromFloat(utils.itof(f32, width) * scalar);
    }
    if (cli_.find_opt("reverse")) |_| {
        std.mem.reverse(u8, charset);
    }

    var img = try Image.init(allocator, height, width);
    defer Image.deinit(img);
    img.set_raw_image(raw_image, filename);
    try img.set_ascii_info(charset);
    try img.fit_image();

    const data = try img.to_ascii();
    const file = output_file(cli_);
    if (file) |path| {
        try write_to_file(path, data);
    } else {
        try write_to_stdio(data);
    }

    try stdout.print("Image: {s}\n", .{filename});
    try stdout.print("Image of size {d}x{d} with {d} channels\n", .{ img.raw_image.width, img.raw_image.height, img.raw_image.nchan });
    try bw.flush();
    return null;
}

pub fn cmd_func(allocator: std.mem.Allocator, cli_: *cli.Cli, args_struct: *cmd.ArgsStructure) !?result.ErrorWrap {
    if (cli_.cmd == null) {
        std.log.info("No command", .{});
        return null;
    }
    const cmd_name = cli_.cmd.?.name.?;
    if (std.mem.eql(u8, cmd_name, "size")) {
        return try size(allocator, cli_);
    } else if (std.mem.eql(u8, cmd_name, "ascii")) {
        return try ascii(allocator, cli_);
    } else if (std.mem.eql(u8, cmd_name, "compress")) {} else if (std.mem.eql(u8, cmd_name, "help")) {
        args_struct.print_commands();
    }
    return null;
}
