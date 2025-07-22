pub fn Result(comptime T: type, comptime E: type) type {
    return union(enum) {
        Ok: T,
        Err: E,

        pub fn is_ok(self: @This()) bool {
            return self == @This().Ok;
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
