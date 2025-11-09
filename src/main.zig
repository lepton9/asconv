const std = @import("std");
const result = @import("result");
const exec = @import("exec");
const zcli = @import("zcli");

fn handle_exec_error(gpa: std.mem.Allocator, err: result.ErrorWrap) u8 {
    defer err.deinit(gpa);
    switch (err.err) {
        exec.ExecError.FileLoadError => {
            std.log.err("Failed to load image '{s}'", .{err.get_ctx()});
        },
        exec.ExecError.FileLoadErrorMem => {
            std.log.err("Failed to load image from memory", .{});
        },
        exec.ExecError.DuplicateInput => {
            std.log.err("Multiple input files '{s}'", .{err.get_ctx()});
        },
        exec.ExecError.NoCommand => {
            std.log.err("No subcommand given", .{});
        },
        exec.ExecError.NoInput => {
            std.log.err("No input given", .{});
        },
        exec.ExecError.InvalidInput => {
            std.log.err("Invalid input '{s}'", .{err.get_ctx()});
        },
        exec.ExecError.NoAlgorithmFound => {
            std.log.err("No edge detection algorithm '{s}'", .{err.get_ctx()});
        },
        exec.ExecError.NoColorModeFound => {
            std.log.err("No colormode '{s}'", .{err.get_ctx()});
        },
        exec.ExecError.FetchError => {
            std.log.err("Failed to fetch image '{s}'", .{err.get_ctx()});
        },
        exec.ExecError.InvalidUrl => {
            std.log.err("Invalid url '{s}'", .{err.get_ctx()});
        },
        exec.ExecError.NoConfigFound => {
            std.log.err("No config found '{s}'", .{err.get_ctx()});
        },
        exec.ExecError.NoConfigTable => {
            std.log.err("No table in config '{s}'", .{err.get_ctx()});
        },
        exec.ExecError.NoConfigCharset => {
            std.log.err("No charset in config with key '{s}'", .{err.get_ctx()});
        },
        exec.ExecError.VideoBuildOptionNotSet => {
            std.log.err(
                "Build option '-Dvideo' is not set. Video support disabled",
                .{},
            );
        },
        else => {
            std.log.err("{}: '{s}'", .{ err.err, err.get_ctx() });
        },
    }
    return 1;
}

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const app = comptime zcli.CliApp{
        .config = .{
            .name = exec.build_options.PROGRAM_NAME,
            .cmd_required = false,
            .auto_help = true,
            .auto_version = true,
        },
        .commands = &exec.commands,
        .options = &exec.options,
        .positionals = &exec.positionals,
    };

    const cli: *zcli.Cli = try zcli.parse_args(allocator, &app);
    defer cli.deinit(allocator);

    const err = try exec.cmd_func(allocator, cli);
    if (err) |e| return handle_exec_error(allocator, e);
    return 0;
}
