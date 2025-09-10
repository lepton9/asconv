const std = @import("std");

pub const ResultError = error{
    UnwrapError,
};

pub fn Result(comptime T: type, comptime E: type) type {
    return union(enum) {
        Ok: T,
        Err: E,

        pub fn is_ok(self: @This()) bool {
            return self == @This().Ok;
        }

        pub fn unwrap_try(self: @This()) !T {
            return switch (self) {
                .Ok => |v| v,
                .Err => |_| return ResultError.UnwrapError,
            };
        }

        pub fn unwrap(self: @This()) T {
            return switch (self) {
                .Ok => |v| v,
                .Err => |_| @panic("Tried to unwrap Err"),
            };
        }

        pub fn unwrap_err(self: @This()) E {
            return switch (self) {
                .Err => |e| e,
                .Ok => |_| @panic("Tried to unwrap_err Ok"),
            };
        }

        pub fn wrap_ok(value: T) @This() {
            return .{ .Ok = value };
        }

        pub fn wrap_err(err: E) @This() {
            return .{ .Err = err };
        }
    };
}

pub const ErrorWrap = struct {
    err: anyerror,
    context: ?[]const u8 = null,

    pub fn create(
        allocator: std.mem.Allocator,
        err: anyerror,
        comptime fmt: []const u8,
        args: anytype,
    ) ErrorWrap {
        const formatted: []u8 = std.fmt.allocPrint(allocator, fmt, args) catch {
            return .{ .err = err };
        };
        return .{ .err = err, .context = formatted };
    }

    pub fn deinit(self: ErrorWrap, allocator: std.mem.Allocator) void {
        if (self.context) |ctx| {
            allocator.free(ctx);
        }
    }

    pub fn get_ctx(self: ErrorWrap) []const u8 {
        return self.context orelse "";
    }
};
