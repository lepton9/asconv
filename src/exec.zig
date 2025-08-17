const std = @import("std");
const cli = @import("cli");
const cmd = cli.cmd;
const result = @import("result");
const image = @import("img");
const utils = @import("utils");
const config = @import("config.zig");
const Image = image.Image;
const ImageRaw = image.ImageRaw;

pub const commands = config.commands;
pub const options = config.options;

pub const ResultImage = result.Result(ImageRaw, result.ErrorWrap);

pub const ExecError = error{
    NoFileName,
    FileLoadError,
    FileLoadErrorMem,
    ParseErrorHeight,
    ParseErrorWidth,
    ParseErrorScale,
    DuplicateInput,
    NoInputFile,
    FetchError,
    InvalidUrl,
};

fn input_file(cli_: *cli.Cli) ![]const u8 {
    var input: ?[]const u8 = null;
    if (cli_.find_opt("input")) |opt_input| {
        input = opt_input.arg_value.?;
    }
    if (cli_.global_args) |ga| {
        if (input) |_| return ExecError.DuplicateInput;
        input = ga;
    }
    return input orelse ExecError.NoInputFile;
}

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

fn validate_url(uri: std.Uri) !void {
    if (!std.mem.eql(u8, uri.scheme, "http") and
        !std.mem.eql(u8, uri.scheme, "https"))
    {
        return error.InvalidUrlScheme;
    }
}

fn is_url(input: []const u8) !bool {
    const uri = std.Uri.parse(input) catch return false;
    try validate_url(uri);
    return true;
}

fn fetch_url_content(allocator: std.mem.Allocator, url: []const u8) ![]const u8 {
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();
    var data = std.ArrayList(u8).init(allocator);

    const res = try client.fetch(.{
        .method = .GET,
        .location = .{ .url = url },
        .response_storage = .{ .dynamic = &data },
    });

    if (res.status != std.http.Status.ok) return ExecError.FetchError;
    return data.toOwnedSlice();
}

fn get_input_image(allocator: std.mem.Allocator, filepath: []const u8) ResultImage {
    const input_url = is_url(filepath) catch {
        return ResultImage.wrap_err(
            result.ErrorWrap.create(ExecError.InvalidUrl, "{s}", .{filepath}),
        );
    };

    if (input_url) {
        const fetched_content = fetch_url_content(allocator, filepath) catch |err| {
            return ResultImage.wrap_err(
                result.ErrorWrap.create(err, "{s}", .{filepath}),
            );
        };
        const raw_image = image.load_image_from_memory(fetched_content) catch {
            return ResultImage.wrap_err(
                result.ErrorWrap.create(ExecError.FileLoadErrorMem, "", .{}),
            );
        };
        return ResultImage.wrap_ok(raw_image);
    } else {
        const raw_image = image.load_image(filepath, null) catch {
            return ResultImage.wrap_err(
                result.ErrorWrap.create(ExecError.FileLoadError, "{s}", .{filepath}),
            );
        };
        return ResultImage.wrap_ok(raw_image);
    }
}

fn size(allocator: std.mem.Allocator, cli_: *cli.Cli) !?result.ErrorWrap {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    const filename = input_file(cli_) catch |err| {
        return result.ErrorWrap.create(err, "{s}", .{cli_.global_args orelse ""});
    };
    const img = try Image.init(allocator, 0, 0);
    defer Image.deinit(img);

    const img_result = get_input_image(allocator, filename);
    img.set_raw_image(img_result.unwrap_try() catch {
        return img_result.unwrap_err();
    }, filename);

    try stdout.print("Image: {s}\n", .{filename});
    try stdout.print("Size: {d}x{d}\n", .{ img.raw_image.width, img.raw_image.height });
    try stdout.print("Channels: {d}\n", .{img.raw_image.nchan});
    try bw.flush();
    return null;
}

fn ascii(allocator: std.mem.Allocator, cli_: *cli.Cli) !?result.ErrorWrap {
    const filename = input_file(cli_) catch |err| {
        return result.ErrorWrap.create(err, "{s}", .{cli_.global_args orelse ""});
    };
    const img_result = get_input_image(allocator, filename);
    const raw_image = img_result.unwrap_try() catch {
        return img_result.unwrap_err();
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
