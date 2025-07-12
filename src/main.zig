const std = @import("std");
const compress = @import("compress");
const image = compress.image;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    const img_height: u32 = 30;
    const img_width: u32 = 30;

    var malloc = gpa.allocator();
    const img = try image.init(&malloc, img_height, img_width);
    defer image.deinit(img, &malloc);

    var mat: [img_height][img_width]u32 = .{.{0} ** img_width} ** img_height;

    for (&mat) |row| {
        for (row) |pixel| {
            try stdout.print("{c} ", .{compress.pixel_to_char(pixel)});
        }
        try stdout.print("\n", .{});
    }
    try bw.flush();
}
