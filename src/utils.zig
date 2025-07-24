const std = @import("std");

pub fn itof(comptime T: type, i: usize) T {
    return @as(T, @floatFromInt(i));
}

pub fn ftoi(comptime T: type, i: f64) T {
    return @as(T, @intFromFloat(std.math.floor(i)));
}

pub fn format_slice(comptime T: type, items: []const T, allocator: std.mem.Allocator, field_fn: fn (item: T, buf: []u8) []const u8) []u8 {
    var item_buf: [32]u8 = undefined;
    var buf = std.ArrayList(u8).init(allocator);
    errdefer buf.deinit();
    var writer = buf.writer();
    for (items, 0..) |item, i| {
        if (i != 0) writer.writeAll(", ") catch return "";
        writer.writeAll(field_fn(item, &item_buf)) catch return "";
    }
    return buf.toOwnedSlice() catch "";
}
