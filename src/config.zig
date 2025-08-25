const std = @import("std");
const builtin = @import("builtin");
const toml = @import("toml");
const fs = std.fs;

const config_name = "config.toml";
const appname = "asconv";

pub const Config = struct {
    table: *toml.Toml,
    path: []const u8,

    pub fn deinit(self: Config, allocator: std.mem.Allocator) void {
        self.table.deinit();
        allocator.free(self.path);
    }
};

pub fn get_config(allocator: std.mem.Allocator) !?Config {
    if (try find_config(allocator)) |path| {
        errdefer allocator.free(path);
        const parser = try toml.Parser.init(allocator);
        defer parser.deinit();
        const table: *toml.Toml = try parser.parse_file(path);
        return .{
            .table = table,
            .path = path,
        };
    }
    return null;
}

pub fn find_config(allocator: std.mem.Allocator) !?[]u8 {
    const config = blk: {
        if (builtin.os.tag == .linux or std.builtin.os.tag == .freebsd)
            break :blk try find_config_linux(allocator);
        if (builtin.os.tag == .windows)
            break :blk try find_config_windows(allocator);
        if (builtin.os.tag == .macos)
            break :blk try find_config_macos(allocator);
    };
    if (config) |c| return c;

    const file: fs.File = fs.cwd().openFile(config_name, .{}) catch {
        return null;
    };
    file.close();
    return try allocator.dupe(u8, config_name);
}

fn find_config_linux(allocator: std.mem.Allocator) !?[]u8 {
    if (get_env(allocator, "XDG_CONFIG_HOME")) |xdg| {
        defer allocator.free(xdg);
        const path = try fs.path.join(allocator, &.{ xdg, appname, config_name });
        const file: ?fs.File = blk: {
            break :blk fs.cwd().openFile(path, .{}) catch {
                allocator.free(path);
                break :blk null;
            };
        };
        if (file) |f| {
            f.close();
            return path;
        }
    }

    if (get_env(allocator, "HOME")) |home| {
        defer allocator.free(home);
        const path = try fs.path.join(
            allocator,
            &.{ home, ".config", appname, config_name },
        );
        const file: fs.File = fs.cwd().openFile(path, .{}) catch {
            allocator.free(path);
            return null;
        };
        file.close();
        return path;
    }
    return null;
}

fn find_config_windows(allocator: std.mem.Allocator) !?[]u8 {
    if (get_env(allocator, "APPDATA")) |appdata| {
        defer allocator.free(appdata);
        const path = try fs.path.join(
            allocator,
            &.{ appdata, appname, config_name },
        );
        const file: fs.File = fs.cwd().openFile(path, .{}) catch {
            allocator.free(path);
            return null;
        };
        file.close();
        return path;
    }
    return null;
}

fn find_config_macos(allocator: std.mem.Allocator) !?[]u8 {
    if (get_env(allocator, "HOME")) |home| {
        defer allocator.free(home);
        const path = try fs.path.join(
            allocator,
            &.{ home, "Library", "Application Support", appname, config_name },
        );
        const file: fs.File = fs.cwd().openFile(path, .{}) catch {
            allocator.free(path);
            return null;
        };
        file.close();
        return path;
    }
    return null;
}

fn get_env(allocator: std.mem.Allocator, env_var: []const u8) ?[]u8 {
    return std.process.getEnvVarOwned(allocator, env_var) catch null;
}

test "find" {
    const allocator = std.testing.allocator;
    const path = try find_config(allocator);
    if (path) |p| {
        allocator.free(p);
    }
}

test "config" {
    const allocator = std.testing.allocator;
    const config = try get_config(allocator);
    if (config) |c| {
        c.deinit(allocator);
    }
}
