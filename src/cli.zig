const std = @import("std");
const cmd = @import("cmd");
const arg = @import("arg");
const result = @import("result");
const utils = @import("utils");

const ErrorWrap = result.ErrorWrap;
pub const ResultCli = result.Result(Cli, ErrorWrap);

pub const ArgsError = error{
    NoCommand,
    NoGlobalArgs,
    UnknownOption,
    UnknownCommand,
    NoOptionValue,
    NoRequiredOption,
    TooManyArgs,
    DuplicateOption,
};

pub const Cli = struct {
    cmd: ?cmd.Cmd = null,
    args: ?std.ArrayList(cmd.Option) = null,
    global_args: ?[]const u8 = null,

    pub fn find_opt(self: *Cli, opt_name: []const u8) ?*cmd.Option {
        if (self.args == null) return null;
        for (self.args.?.items) |*option| {
            if (std.mem.eql(u8, option.long_name, opt_name)) {
                return option;
            }
        }
        return null;
    }

    fn add_opt(self: *Cli, opt: cmd.Option) void {
        if (self.args == null) {
            self.args = std.ArrayList(cmd.Option).init(std.heap.page_allocator);
        }
        self.args.?.append(opt) catch {};
    }

    fn add_unique(self: *Cli, opt: cmd.Option) ArgsError!void {
        const option = self.find_opt(opt.long_name);
        if (option != null) return ArgsError.DuplicateOption;
        self.add_opt(opt);
    }
};

fn missing_required_opts(cli: *Cli, app: *const cmd.ArgsStructure) ?[]*const cmd.Option {
    var missing_opts = std.ArrayList(*const cmd.Option).init(std.heap.page_allocator);
    defer missing_opts.deinit();
    for (app.options) |*opt| {
        if (!opt.required) continue;
        var found = false;
        if (cli.args == null) {
            missing_opts.append(opt) catch {};
            continue;
        }
        for (cli.args.?.items) |o| {
            if (std.mem.eql(u8, o.long_name, opt.long_name)) {
                found = true;
                break;
            }
        }
        if (!found) {
            missing_opts.append(opt) catch {};
        }
    }
    if (missing_opts.items.len == 0) return null;
    return missing_opts.toOwnedSlice() catch return null;
}

pub fn validate_parsed_args(args: []const arg.ArgParse, app: *const cmd.ArgsStructure) ResultCli {
    var cli = Cli{};
    var opt_empty: ?cmd.Option = null;
    var opt_type: ?arg.OptType = null;
    for (args, 0..) |a, i| {
        switch (a) {
            .option => {
                if (cli.cmd == null and app.cmd_required) {
                    return ResultCli.wrap_err(ErrorWrap.create(ArgsError.NoCommand, "", .{}));
                }
                if (opt_empty != null) {
                    return ResultCli.wrap_err(ErrorWrap.create(ArgsError.NoOptionValue, "{s}{s}", switch (opt_type.?) {
                        .long => .{ "--", opt_empty.?.long_name },
                        .short => .{ "-", opt_empty.?.short_name },
                    }));
                }
                const opt = app.find_option(a.option.name, a.option.option_type) catch {
                    return ResultCli.wrap_err(ErrorWrap.create(ArgsError.UnknownOption, "{s}{s}", .{ switch (a.option.option_type) {
                        .long => "--",
                        .short => "-",
                    }, a.option.name }));
                };
                if (a.option.value == null and opt.arg_name != null) {
                    opt_empty = opt;
                    opt_type = a.option.option_type;
                } else {
                    cli.add_unique(opt) catch |err| {
                        return ResultCli.wrap_err(ErrorWrap.create(err, "{s}{s}", .{
                            switch (a.option.option_type) {
                                .long => "--",
                                .short => "-",
                            },
                            a.option.name,
                        }));
                    };
                }
            },
            .value => {
                if (cli.cmd == null and i == 0) {
                    const c = app.find_cmd(a.value) catch {
                        return ResultCli.wrap_err(ErrorWrap.create(ArgsError.UnknownCommand, "{s}", .{a.value}));
                    };
                    cli.cmd = c;
                } else if (opt_empty != null) {
                    opt_empty.?.arg_value = a.value;
                    cli.add_unique(opt_empty.?) catch |err| {
                        return ResultCli.wrap_err(ErrorWrap.create(err, "{s}{s}", switch (opt_type.?) {
                            .long => .{ "--", opt_empty.?.long_name },
                            .short => .{ "-", opt_empty.?.short_name },
                        }));
                    };
                    opt_empty = null;
                    opt_type = null;
                } else if (cli.global_args == null) {
                    cli.global_args = a.value;
                } else {
                    return ResultCli.wrap_err(ErrorWrap.create(ArgsError.TooManyArgs, "{s}", .{a.value}));
                }
            },
        }
    }
    if (cli.cmd == null and app.cmd_required) {
        return ResultCli.wrap_err(ErrorWrap.create(ArgsError.NoCommand, "", .{}));
    }
    if (opt_empty != null) {
        return ResultCli.wrap_err(ErrorWrap.create(ArgsError.NoOptionValue, "{s}{s}", switch (opt_type.?) {
            .long => .{ "--", opt_empty.?.long_name },
            .short => .{ "-", opt_empty.?.short_name },
        }));
    }
    const missing_opts = missing_required_opts(&cli, app);
    if (missing_opts != null) {
        return ResultCli.wrap_err(ErrorWrap.create(
            ArgsError.NoRequiredOption,
            "[{s}]",
            .{utils.format_slice(
                *const cmd.Option,
                missing_opts.?,
                std.heap.page_allocator,
                cmd.Option.get_format_name,
            )},
        ));
    }
    return ResultCli.wrap_ok(cli);
}
