const std = @import("std");
const builtin = @import("builtin");
const toml = @import("toml");

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

pub fn get_config_from_path(io: std.Io, gpa: std.mem.Allocator, path: []const u8) !?Config {
    const cwd = std.Io.Dir.cwd();
    const file: ?std.Io.File = cwd.openFile(io, path, .{}) catch null;
    if (file) |f| {
        f.close(io);
        const parser = try toml.Parser.init(gpa);
        defer parser.deinit();
        const table: *toml.Toml = try parser.parseFile(io, path);
        return .{
            .table = table,
            .path = try gpa.dupe(u8, path),
        };
    }
    return null;
}

pub fn get_config(
    io: std.Io,
    gpa: std.mem.Allocator,
    env: *std.process.Environ.Map,
) !?Config {
    if (try find_config(io, gpa, env)) |path| {
        errdefer gpa.free(path);
        const parser = try toml.Parser.init(gpa);
        defer parser.deinit();
        const table: *toml.Toml = try parser.parseFile(io, path);
        return .{
            .table = table,
            .path = path,
        };
    }
    return null;
}

pub fn find_config(
    io: std.Io,
    gpa: std.mem.Allocator,
    env: *std.process.Environ.Map,
) !?[]u8 {
    const config = switch (builtin.os.tag) {
        .linux, .freebsd => try find_config_linux(io, gpa, env),
        .windows => try find_config_windows(io, gpa, env),
        .macos => try find_config_macos(io, gpa, env),
        else => null,
    };
    if (config) |c| return c;

    const file = std.Io.Dir.cwd().openFile(io, config_name, .{}) catch {
        return null;
    };
    file.close(io);
    return try gpa.dupe(u8, config_name);
}

fn find_config_linux(
    io: std.Io,
    gpa: std.mem.Allocator,
    env: *std.process.Environ.Map,
) !?[]u8 {
    if (env.get("XDG_CONFIG_HOME")) |xdg| {
        const path = try std.fs.path.join(gpa, &.{ xdg, appname, config_name });
        const file: ?std.Io.File = blk: {
            break :blk std.Io.Dir.cwd().openFile(io, path, .{}) catch {
                gpa.free(path);
                break :blk null;
            };
        };
        if (file) |f| {
            f.close(io);
            return path;
        }
    }

    if (env.get("HOME")) |home| {
        const path = try std.fs.path.join(
            gpa,
            &.{ home, ".config", appname, config_name },
        );
        const file = std.Io.Dir.cwd().openFile(io, path, .{}) catch {
            gpa.free(path);
            return null;
        };
        file.close(io);
        return path;
    }
    return null;
}

fn find_config_windows(
    io: std.Io,
    gpa: std.mem.Allocator,
    env: *std.process.Environ.Map,
) !?[]u8 {
    if (env.get("APPDATA")) |appdata| {
        const path = try std.fs.path.join(
            gpa,
            &.{ appdata, appname, config_name },
        );
        const file = std.Io.Dir.cwd().openFile(io, path, .{}) catch {
            gpa.free(path);
            return null;
        };
        file.close(io);
        return path;
    }
    return null;
}

fn find_config_macos(
    io: std.Io,
    gpa: std.mem.Allocator,
    env: *std.process.Environ.Map,
) !?[]u8 {
    if (env.get("HOME")) |home| {
        const path = try std.fs.path.join(
            gpa,
            &.{ home, "Library", "Application Support", appname, config_name },
        );
        const file = std.Io.Dir.cwd().openFile(io, path, .{}) catch {
            gpa.free(path);
            return null;
        };
        file.close(io);
        return path;
    }
    return null;
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
