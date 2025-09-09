const std = @import("std");

pub fn itof(comptime T: type, i: anytype) T {
    return @as(T, @floatFromInt(i));
}

pub fn ftoi(comptime T: type, i: anytype) T {
    return @as(T, @intFromFloat(std.math.floor(i)));
}

pub fn format_slice(comptime T: type, items: []const T, allocator: std.mem.Allocator, field_fn: fn (item: T, buf: []u8) []const u8) ![]u8 {
    var item_buf: [32]u8 = undefined;
    var buf = try std.ArrayList(u8).initCapacity(allocator, 1024);
    errdefer buf.deinit(allocator);
    for (items, 0..) |item, i| {
        if (i != 0) buf.appendSlice(allocator, ", ") catch return "";
        buf.appendSlice(allocator, field_fn(item, &item_buf)) catch return "";
    }
    return buf.toOwnedSlice(allocator) catch "";
}

pub fn string_to_enum_ic(comptime T: type, str: []const u8) ?T {
    inline for (@typeInfo(T).@"enum".fields) |enumField| {
        if (std.ascii.eqlIgnoreCase(str, enumField.name)) {
            return @field(T, enumField.name);
        }
    }
    return null;
}
