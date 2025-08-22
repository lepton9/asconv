const std = @import("std");
const result = @import("result");
const exec = @import("exec");
const cli = @import("cli");
const cmd = cli.cmd;
const arg = cli.arg;

fn handle_cli(cli_result: cli.ResultCli) ?cli.Cli {
    return cli_result.unwrap_try() catch {
        const err = cli_result.unwrap_err();
        switch (err.err) {
            cli.ArgsError.UnknownCommand => {
                std.log.err("Unknown command: '{s}'", .{err.get_ctx()});
            },
            cli.ArgsError.UnknownOption => {
                std.log.err("Unknown option: '{s}'\n", .{err.get_ctx()});
            },
            cli.ArgsError.NoCommand => {
                std.log.err("No command given\n", .{});
            },
            cli.ArgsError.NoGlobalArgs => {
                std.log.err("No global arguments\n", .{});
            },
            cli.ArgsError.NoOptionValue => {
                std.log.err("No option value for option '{s}'\n", .{err.get_ctx()});
            },
            cli.ArgsError.NoRequiredOption => {
                std.log.err("Required options not given: {s}\n", .{err.get_ctx()});
            },
            cli.ArgsError.TooManyArgs => {
                std.log.err("Too many arguments: '{s}'\n", .{err.get_ctx()});
            },
            cli.ArgsError.DuplicateOption => {
                std.log.err("Duplicate option: '{s}'\n", .{err.get_ctx()});
            },
            else => {
                std.log.err("Error\n", .{});
            },
        }
        return null;
    };
}

fn handle_exec_error(err: result.ErrorWrap) void {
    switch (err.err) {
        exec.ExecError.NoFileName => {
            std.log.err("No file given as argument", .{});
        },
        exec.ExecError.FileLoadError => {
            std.log.err("Failed to load image '{s}'", .{err.get_ctx()});
        },
        exec.ExecError.FileLoadErrorMem => {
            std.log.err("Failed to load image from memory", .{});
        },
        exec.ExecError.ParseErrorHeight => {
            std.log.err("Failed to parse height '{s}'", .{err.get_ctx()});
        },
        exec.ExecError.ParseErrorWidth => {
            std.log.err("Failed to parse width '{s}'", .{err.get_ctx()});
        },
        exec.ExecError.ParseErrorScale => {
            std.log.err("Failed to parse scale '{s}'", .{err.get_ctx()});
        },
        exec.ExecError.ParseErrorBrightness => {
            std.log.err("Failed to parse brightness '{s}'", .{err.get_ctx()});
        },
        exec.ExecError.ParseErrorSigma => {
            std.log.err("Failed to parse sigma '{s}'", .{err.get_ctx()});
        },
        exec.ExecError.DuplicateInput => {
            std.log.err("Multiple input files '{s}'", .{err.get_ctx()});
        },
        exec.ExecError.NoInputFile => {
            std.log.err("No input file given", .{});
        },
        exec.ExecError.NoAlgorithmFound => {
            std.log.err("No edge detection algorithm '{s}'", .{err.get_ctx()});
        },
        exec.ExecError.FetchError => {
            std.log.err("Failed to fetch image {s}", .{err.get_ctx()});
        },
        exec.ExecError.InvalidUrl => {
            std.log.err("Invalid url {s}", .{err.get_ctx()});
        },
        else => {
            std.log.err("Error: '{s}'", .{err.get_ctx()});
        },
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var alloc = gpa.allocator();

    const app = try cmd.ArgsStructure.init(&alloc);
    defer app.deinit(&alloc);
    app.cmd_required = true;
    app.set_commands(&exec.commands);
    app.set_options(&exec.options);

    var args_str = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args_str);
    const args = try arg.parse_args(alloc, args_str[1..]);
    defer alloc.free(args);

    const cli_result = cli.validate_parsed_args(args, app);
    var cli_ = handle_cli(cli_result) orelse return;

    const err = try exec.cmd_func(alloc, &cli_, app);
    if (err) |e| handle_exec_error(e);
}
